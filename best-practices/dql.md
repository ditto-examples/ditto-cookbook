# Reading and Writing Data with DQL

This page covers what every DQL statement depends on (where queries run, parameters, MISSING and NULL, query results), reading with `SELECT`, and writing with `INSERT`, `UPDATE`, `DELETE`, and `EVICT`. The functions and operators are listed in [DQL Functions and Operators](../knowledge/dql-functions.md).

## DQL Fundamentals

DQL (Ditto Query Language) is the SQL-like language you use to read, write, and observe documents in Ditto. It looks familiar if you know SQL, but it works on schemaless JSON-like documents, distinguishes a missing field from a `null` field, and has Ditto-specific statements for conflict handling, CRDT types, and local eviction.

| Statement | Purpose | Covered in |
|---|---|---|
| `SELECT` | Read documents: projections, aggregates, `GROUP BY`, `ORDER BY`, `LIMIT`, `JOIN` (SDK 5.1+) | [Reading Data with SELECT](#reading-data-with-select) |
| `INSERT` | Create documents, upsert with `ON ID CONFLICT`, seed defaults with `INITIAL DOCUMENTS` | [INSERT and Conflict Handling](#insert-and-conflict-handling) |
| `UPDATE` | Change individual fields with `SET` / `UNSET`, counters with `APPLY` | [UPDATE](#update) |
| `DELETE` / `EVICT` | Delete everywhere (tombstone) / remove from this device only | [Deletion and Storage Management](deletion-and-storage.md) |
| `CREATE INDEX` / `DROP INDEX`, `EXPLAIN`, `PROFILE`; `ADVISE` (SDK 5.1+) | Indexing and query diagnostics | [Indexing and Query Performance](indexing-and-performance.md) |
| `ALTER SYSTEM` / `SHOW` | Runtime system parameters | [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters) |

There is no `CREATE COLLECTION` or `DROP COLLECTION` statement: a collection exists as soon as a document is written to it, and it cannot be removed. <!-- lint-ignore -->

Keep the number of collections small. In our testing with SDK 5.1.0 and 5.2.0, the first write to a new collection slowed down as collections accumulated (about 20 ms with 1,000 collections), each collection took about 15 to 17 KB of disk, and evicting the documents of a collection removed neither (see [Since SDK 5.1, each new collection makes the first write to a collection slower](../knowledge/observations/performance-measurements.md#since-sdk-51-each-new-collection-makes-the-first-write-to-a-collection-slower)). Do not create a collection per user, tenant, or day; partition one collection with part of `_id` (`{"tenant": ..., "orderId": ...}`) or a field instead.

### Where Queries Run

DQL statements always run against the **local store** of the device. Which API you pass a statement to decides what happens with it:

| API (Flutter) | What it does |
|---|---|
| `ditto.store.execute(query, arguments: {...})` | Runs one statement against the local store and returns a `QueryResult`. Never contacts other peers. |
| `tx.execute(query, arguments: {...})` | Same, inside `ditto.store.transaction(...)`. See [Transactions](transactions.md). |
| `ditto.store.registerObserver(query, arguments: {...})` | Re-runs a `SELECT` whenever matching local data changes. See [Observing Changes](observers.md). |
| `ditto.sync.registerSubscription(query, arguments: {...})` | Tells connected peers which documents this device wants. Only `SELECT * FROM c [WHERE ...]` is accepted. See [Sync and Subscriptions](sync-and-subscriptions.md). |

Queries never fetch data from other peers: a `SELECT` sees only documents that were created on this device or that a subscription has already brought to it. See [Core Principles](../knowledge/understanding-ditto.md#core-principles) for how queries and subscriptions work together.

```dart
// ✅ GOOD: A long-lived subscription (owned by an app-level service) brings
// matching documents to this device; execute() reads whatever has arrived so far.
SyncSubscription subscribeToOpenOrders(Ditto ditto) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );

Future<List<Map<String, dynamic>>> loadOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}
```

### Parameters and Literals

#### Always pass values as parameters

Reference values with `:name` placeholders and pass them in `arguments`. Parameter names are case-sensitive (`:Status` and `:status` are different), and a placeholder without a matching argument fails with `Parameter Status was not provided`. Write argument names without the colon: an argument named `':status'` leaves `:status` without a value, which fails the same way. Arguments that the statement does not use are ignored, and `$status` is a syntax error.

**✅ DO:**
- Use parameters for every value that comes from your app: IDs, user input, dates, limits, whole documents.
- Pass whole documents to `INSERT` as a single parameter: `INSERT INTO orders DOCUMENTS (:order)`.
- Pass arrays for membership tests: `WHERE status IN :statuses`.

**❌ DON'T:**
- Build DQL strings with string interpolation or concatenation.
- Write `IN (:statuses)` with an array parameter. The parentheses turn it into a one-element list whose only element is the array, so nothing matches.
- Pass a single value where the statement expects an array. In our testing, `status IN :statuses` with a string instead of a list matched nothing, without an error (see [Wrong argument types fail silently](../knowledge/observations/dql-behavior.md#wrong-argument-types-fail-silently)); wrap a single value in a list.

```dart
// ✅ GOOD: Values travel as typed parameters
Future<List<Map<String, dynamic>>> findOrders(
  Ditto ditto,
  String customerId,
  List<String> statuses,
  int pageSize,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE customerId = :customerId AND status IN :statuses '
    'ORDER BY createdAt DESC LIMIT :pageSize',
    arguments: {
      'customerId': customerId,
      'statuses': statuses,
      'pageSize': pageSize,
    },
  );
  return result.items.map((item) => item.value).toList();
}
```

```dart
// ❌ BAD: Interpolated values (injection risk, broken quoting, no statement reuse)
Future<void> findOrdersUnsafe(Ditto ditto, String customerId) async {
  await ditto.store.execute(
    "SELECT * FROM orders WHERE customerId = '$customerId'",
  );
}

// ❌ BAD: The array becomes a single list element, so no document matches
Future<void> findByStatusesWrong(Ditto ditto) async {
  await ditto.store.execute(
    'SELECT * FROM orders WHERE status IN (:statuses)',
    arguments: {'statuses': ['open', 'pending']},
  );
}
```

**Why:**
- **Security**: Interpolated input can change the meaning of the statement (DQL injection).
- **Correctness**: DQL string literals interpret backslash escapes (see below), so user text containing `\` or quotes can be silently altered or break the statement. Parameters keep their exact value and type (an `int` stays an integer, a `bool` stays a boolean).
- **Performance**: The statement text stays identical between calls, so Ditto's shared statement cache can reuse the prepared plan instead of planning the query again.

#### Literals

When you do write values inline (constants such as `'open'`, or examples in the DQL console), these rules apply:

| Literal | Syntax | Notes |
|---|---|---|
| String | `'open'` or `"open"` | Single and double quotes both delimit strings. Double quotes never refer to a field. |
| Escapes in strings | `'line1\nline2'`, `'it\'s'`, `'caf\u00e9'` | JSON escape sequences are interpreted in both quote styles. `'it''s'` (doubled quote) is a syntax error. An unknown escape such as `\q` drops the backslash. A literal backslash must be written `\\`. This changed in 5.1.0: on 5.0.x, `''` was the escape for `'` and backslashes were not interpreted, so string literals written for 5.0.x can fail or change meaning after an upgrade. |
| Identifier | `` `my field` ``, `` `collection` `` | Backticks quote field names, aliases, and collection names that contain special characters or are reserved words. Identifiers are case-sensitive: `Orders` and `orders` are different collections. |
| Number | `42`, `-1`, `2.5`, `1e3` | `1e3` is a float. Integer division stays integer: `5 / 2` is `2`, `5.0 / 2` is `2.5`. Division and modulo by zero (`1 / 0`, `1 % 0`) give MISSING, not an error (see [Comparisons across types are MISSING, and strings sort by code point](../knowledge/observations/dql-behavior.md#comparisons-across-types-are-missing-and-strings-sort-by-code-point)). |
| Hexadecimal | `0xFF` | Integer constant (`255`). |
| Boolean / null | `true`, `FALSE`, `null` | Case-insensitive keywords. |
| Array | `[1, 'a']` | JSON-style. |
| Object | `{'status': 'open', 'total': 10}` | Every key must be a quoted string (see below). |

```sql
SELECT 'it\'s' AS a, "double quoted" AS b, `my field` AS c, 0xFF AS d
FROM orders
```

Backslashes are interpreted twice when the statement is written inside a Dart string: first by Dart, then by DQL. This is another reason to pass text as a parameter.

```dart
// ✅ GOOD: The path is passed as data and stored exactly as given
Future<void> saveExportPath(Ditto ditto) async {
  await ditto.store.execute(
    'UPDATE settings SET exportPath = :path WHERE _id = :id',
    arguments: {'id': 'device', 'path': r'C:\temp\exports'},
  );
}
```

#### Quote every key in inline object literals

Object literals written inside a statement must use quoted keys. Unquoted keys fail in `INSERT` and, worse, are silently evaluated as field references in `SELECT` (usually producing an empty object).

<!-- expect-error -->
```sql
-- ❌ BAD: Unquoted keys are rejected: "Cannot convert to a literal"
INSERT INTO orders DOCUMENTS ({_id: 'order-1', status: 'open'})
```

```sql
-- ❌ BAD: No error, but o is returned as {} (the unquoted key is evaluated as a field reference)
SELECT {a: 1} AS o FROM system:dual
```

```sql
-- ✅ GOOD: Quoted keys
INSERT INTO orders DOCUMENTS ({'_id': 'order-1', 'status': 'open'})

SELECT {'a': 1} AS o FROM system:dual
```

The recommended form is to avoid inline objects entirely and pass the document as a parameter (`DOCUMENTS (:order)`).

#### Reserved words

Ditto's [DQL identifiers reference](https://docs.ditto.live/dql/ids-paths-strings-keywords) reserves keywords such as `COLLECTION`, `ORDER`, `SELECT`, `VALUE`, and `ALL`, and says that an identifier equal to one of them must be quoted. The SDKs enforce this only for some of them: in our testing, of 32 keywords used as bare collection and field names, only a collection named `collection` failed (`SELECT * FROM collection` is a parser error, `expected identifier`), while `order`, `select`, `from`, `where`, `value`, and `all`, among others, were accepted (see [Names are case-sensitive, and most DQL keywords are accepted as bare names](../knowledge/observations/dql-behavior.md#names-are-case-sensitive-and-most-dql-keywords-are-accepted-as-bare-names)). Follow the documented rule rather than what an SDK accepts today. Literals are a different case: a bare `true`, `false`, or `null` is read as the value, never as a field of that name, and the statement runs without an error.

**✅ DO:**
- Choose collection and field names that are not DQL keywords (`orders`, `tasks`, `createdAt`).
- Quote an existing reserved name with backticks if you cannot rename it: ``SELECT * FROM `collection` ``.
- Quote fields named like a literal with backticks (`` `null` ``, `` `true` ``).

The full keyword list is in the [DQL identifiers, paths, strings, and keywords](https://docs.ditto.live/dql/ids-paths-strings-keywords) reference, which also lists the keywords that are no longer reserved since SDK 5.0, such as `COUNT`, `MAP`, and `REGISTER`.

#### Comments

Statements may contain `-- line comments` and `/* block comments */`. Comments that start with `/*+` or `--+` are query directives (see [Indexing and Query Performance](indexing-and-performance.md)), so do not use those prefixes for ordinary comments.

### MISSING and NULL

Ditto documents are schemaless, so a field can be absent from a document (**MISSING**) or present with the value `null` (**NULL**). DQL treats them differently, and most surprises come from the fact that a comparison involving a missing or null field is neither true nor false. In a `WHERE` clause such a row is simply not returned.

Which documents each `WHERE` expression matches, when `isDeleted` is `true`, `false`, `null`, or missing:

| `WHERE` expression | `true` | `false` | `null` | missing |
|---|---|---|---|---|
| `isDeleted = false` | | ✓ | | |
| `isDeleted != true` / `NOT isDeleted` | | ✓ | | | <!-- lint-ignore -->
| `coalesce(isDeleted, false) = false` | | ✓ | ✓ | ✓ |
| `isDeleted IS NULL` | | | ✓ | |
| `isDeleted IS NOT NULL` | ✓ | ✓ | | ✓ | <!-- lint-ignore -->
| `isDeleted IS MISSING` | | | | ✓ |
| `isDeleted IS NOT MISSING` | ✓ | ✓ | ✓ | |
| `isDeleted IS NOT MISSING AND isDeleted IS NOT NULL` | ✓ | ✓ | | | <!-- lint-ignore -->
| `ismissingornull(isDeleted)` | | | ✓ | ✓ |

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

Note that `IS NOT NULL` is true for a missing field, and that `!= true` drops both `null` and missing rows. <!-- lint-ignore -->

In the JavaScript SDK, a field whose value is `undefined` is stored as `null`, not left out, so it no longer matches `IS MISSING`, also inside arrays and objects (in our testing; see [JavaScript values that are not plain JSON change when stored](../knowledge/observations/dql-behavior.md#javascript-values-that-are-not-plain-json-change-when-stored)). Omit the key to leave a field missing.

**✅ DO:**
- Filter optional booleans with `coalesce(field, default)`: `coalesce(isDeleted, false) = false`.
- Test for field existence with `IS MISSING` / `IS NOT MISSING`.
- Test "has a real value" with `field IS NOT MISSING AND field IS NOT NULL`. <!-- lint-ignore -->
- Remove a field with `UNSET` (see [UPDATE](#update)) when you want it to become missing; writing `null` keeps the field present with a null value.

**❌ DON'T:**
- Use `field != true` or `NOT field` to mean "false or not set". <!-- lint-ignore -->
- Use `IS NOT NULL` to check that a field exists. <!-- lint-ignore -->

```dart
// ✅ GOOD: Treat a missing or null isDeleted flag as "not deleted"
Future<List<Map<String, dynamic>>> activeTasks(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false ORDER BY createdAt',
  );
  return result.items.map((item) => item.value).toList();
}

// ❌ BAD: Tasks that never had isDeleted set (or have null) are silently excluded
Future<List<Map<String, dynamic>>> activeTasksWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt',
  );
  return result.items.map((item) => item.value).toList();
}
```

**Why:** Documents written by older app versions, by other platforms, or created before a field was introduced often lack the field entirely. A filter that ignores MISSING hides those documents without any error. The [Soft Delete](deletion-and-storage.md#soft-delete) pattern depends on getting this right.

Related behavior:
- In projections, an expression that evaluates to MISSING is omitted from the result row (the key is absent from `item.value`), while `null` appears as a `null` value.
- Comparing values of different types, including with `=` and `!=` (`1 = 'a'`, `1 != 'a'`, `1 < 'a'`), also evaluates to MISSING (see [Comparisons across types are MISSING, and strings sort by code point](../knowledge/observations/dql-behavior.md#comparisons-across-types-are-missing-and-strings-sort-by-code-point)), as do operators applied to the wrong types (`'a' || 1`). Integers and floats compare normally (`1 = 1.0` is `true`). <!-- lint-ignore -->
- `ORDER BY` sorts `null` and missing values after all other values in ascending order (see [ORDER BY](#order-by) and [Descending order puts missing and null first](../knowledge/observations/dql-behavior.md#descending-order-puts-missing-and-null-first)).
- Aggregates other than `COUNT` return MISSING, not `0`, over zero matching documents (see [Aggregates](#aggregates)).

### Working with Query Results

`ditto.store.execute` returns a `QueryResult`:

| Member (Flutter) | Type | Description |
|---|---|---|
| `items` | `Iterable<QueryResultItem>` | The result rows. An `Iterable`, not a `List`: use `map`, `first`, `length`, or `toList()`. |
| `item.value` | `Map<String, dynamic>` | The row decoded into Dart values. Decoded on first access and cached on that item object. |
| `item.jsonString` | `String` | The row as a JSON string (a property, not a method). |
| `item.cborBytes` | `Uint8List` | The row as CBOR bytes (a property, not a method). |
| `mutatedDocumentIDs()` | `List<dynamic>` | IDs of documents changed by an `INSERT` / `UPDATE` / `DELETE` / `EVICT`. A method that builds a new list on every call; call it once and keep the list. IDs are raw values (a `String`, or a `Map` for composite IDs). |
| `commitID` | `int?` | ID of the local commit for a mutating statement; `null` for reads. Inside a transaction it is only available after the transaction commits. |

In the JavaScript SDK, the `QueryResult` equivalents are `items[i].value`, `items[i].jsonString()` (a method), and `mutatedDocumentIDsV2()`. Arguments are passed as the second positional parameter: `ditto.store.execute(query, { status: 'open' })`. <!-- lint-ignore -->

```dart
// Read: convert rows to plain Dart data right away
Future<List<Map<String, dynamic>>> openOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, total, status FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}

// Write: inspect which documents changed
Future<List<dynamic>> closeOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id IN :ids',
    arguments: {'status': 'closed', 'ids': ids},
  );
  final int? commitId = result.commitID; // null for reads
  debugPrint('Committed as $commitId');
  return result.mutatedDocumentIDs(); // call once and keep the list
}

// Alternative encodings, for example to hand rows to a JSON decoder or another isolate
Future<List<String>> openOrdersAsJson(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.jsonString).toList();
}
```

#### Materialize values, then let the result go

**✅ DO:**
- Convert each row to a `Map` or to your own model class once, then work with those objects.
- Iterate `items` once. Each pass over `items` creates new `QueryResultItem` wrappers, so `result.items.first.value` evaluated twice decodes the row twice. (JavaScript differs: `items` and `item.value` return the same objects every time; see [Platform Differences](../knowledge/platform-differences.md) and [In JavaScript, query results return the same objects](../knowledge/observations/observer-behavior.md#in-javascript-query-results-return-the-same-objects).)
- Keep only the data you need; let the `QueryResult` go out of scope.

**❌ DON'T:**
- Store `QueryResult` or `QueryResultItem` objects in state, caches, or across observer callbacks. They reference native memory that is released only when the Dart object is garbage-collected.

```dart
class Order {
  Order({required this.id, required this.status, required this.total});

  factory Order.fromValue(Map<String, dynamic> value) => Order(
        id: value['_id'] as String,
        status: value['status'] as String? ?? 'unknown',
        total: (value['total'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String status;
  final double total;
}

// ✅ GOOD: One pass, plain Dart objects out
Future<List<Order>> loadOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => Order.fromValue(item.value)).toList();
}
```

#### Large results

Every row of a `SELECT` is materialized in the result. To keep results small on mobile devices:

- **Project** only the fields you need (`SELECT _id, title, status ...`). Projections do not change what syncs, but they reduce decoding work and memory.
- **Filter** in `WHERE` rather than in Dart.
- **Page** with `ORDER BY ... LIMIT` (see [LIMIT and OFFSET](#limit-and-offset)).
- **Count** with `SELECT COUNT(*)` instead of loading documents to call `.length`.
- **Let large results go** once you have extracted what you need, and read very large sets in pages. In our testing with the JavaScript SDK, the process's resident memory did not shrink after a large result had been released and garbage-collected; on 5.2.0, the same result used about 20 to 30% less memory than on 5.1.0 while it was held, and about 35% less once it was read, in line with the release notes, which say that query results stay compact until they are read (see [Large query results keep process memory after they are released](../knowledge/observations/performance-measurements.md#large-query-results-keep-process-memory-after-they-are-released)).
- **Check existence** with `LIMIT 1`.

## Reading Data with SELECT

```text
SELECT [DISTINCT] projection
FROM collection [[AS] alias] [USE IDS ...]
  [[INNER | LEFT [OUTER] | RIGHT [OUTER]] JOIN collection2 [[AS] alias2] ON condition] ...
[WHERE condition]
[GROUP BY expression, ...]
[HAVING condition]
[ORDER BY expression [ASC | DESC], ...]
[LIMIT n]
[OFFSET m]
```

### Projections and Aliases

| Projection | Example | Result |
|---|---|---|
| All fields | `SELECT * FROM orders` | Whole documents |
| Fields | `SELECT _id, status FROM orders` | Only those fields |
| Expressions with aliases | `SELECT _id, total * 1.1 AS gross FROM orders` | Computed field `gross` |
| All fields plus expressions | `SELECT orders.*, total * 1.1 AS gross FROM orders` | Qualify `*` with the collection name or alias |
| All fields except some | `SELECT orders.*, MISSING notes FROM orders` | Every field but `notes` |

**✅ DO:**
- Select only the fields you need in `execute` and observers.
- Give every computed expression an explicit alias with `AS`. Without one, Ditto names the column after its position in the projection list, such as `($2)` for the second element.
- Qualify `*` when combining it with other projections: `SELECT orders.*, ...`. An unqualified `SELECT *, total * 2 AS doubled` fails with `unqualified * with other projection elements is not supported`.

```dart
// ✅ GOOD: Only the fields the list screen shows, with readable aliases
Future<List<Map<String, dynamic>>> orderSummaries(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, customerName, total * 1.1 AS totalWithTax '
    'FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}
```

**Why:** A projection shapes the local result only. Synchronization works on whole documents and is controlled by subscriptions, which always use `SELECT *`. Smaller projections mean less decoding and memory, and an index that contains every projected field can answer the query without fetching documents (see [Indexing and Query Performance](indexing-and-performance.md)).

### DISTINCT

`SELECT DISTINCT` removes duplicate result rows. To guarantee uniqueness Ditto keeps every distinct row it has produced in memory, so memory grows with the number of unique rows.

**✅ DO:**
- Use `DISTINCT` on a few low-cardinality fields: `SELECT DISTINCT status FROM orders`.

**❌ DON'T:**
- Use `DISTINCT` together with `_id` or `*`. Every document is already unique, so it only adds memory use.

```sql
SELECT DISTINCT status FROM orders ORDER BY status
```

### Aggregates

| Function | Result |
|---|---|
| `COUNT(*)` | Number of rows |
| `COUNT(expr)` | Number of rows where `expr` is **not** `null`, missing, **or `false`** |
| `COUNT(DISTINCT expr)` | Number of distinct values of `expr`, with the same exclusions |
| `SUM(expr)` / `AVG(expr)` | Sum / average of numeric values; other types are ignored |
| `MIN(expr)` / `MAX(expr)` | Smallest / largest value in Ditto's type order |
| `MEDIAN(expr)` | Positional median of numeric values |
| `MID(expr)` | `(MIN + MAX) / 2`, the midpoint between the extremes (not the median) |

`SUM`, `AVG`, `MEDIAN`, and `MID` also accept `DISTINCT`.

`COUNT` behavior over five documents whose `isPaid` field is `true`, `false`, `null`, missing, and `true`:

| Expression | Result |
|---|---|
| `COUNT(*)` | 5 |
| `COUNT(isPaid)` | 2 (only `true`) |
| `COUNT(isPaid = false)` | 1 |

**✅ DO:**
- Use `COUNT(*)` to count documents. A full-collection `COUNT(*)` is answered from a dedicated fast path (SDK 5.1+).
- Count values that exist with `COUNT(field IS NOT MISSING)` when the field can be `false`.
- Wrap aggregates that may see zero rows: `ifmissing(SUM(total), 0)`. With no matching rows, every aggregate other than `COUNT` (`SUM`, `AVG`, `MIN`, `MAX`, `MEDIAN`, `MID`) returns MISSING (the alias is absent from the row), while `COUNT(*)` and `COUNT(expr)` return `0`.
- Use `LIMIT 1` to check whether at least one matching document exists.

**❌ DON'T:**
- Use `COUNT(field)` to count "documents that have the field" when the field is a boolean: `false` values are not counted.
- Use `MID` when you need the median.

```dart
// ✅ GOOD: Aggregates with explicit aliases and a default for empty sets
Future<Map<String, dynamic>> orderStats(Ditto ditto, String customerId) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(*) AS orderCount, '
    'ifmissing(SUM(total), 0) AS revenue, '
    'ifmissing(AVG(total), 0) AS averageOrder '
    'FROM orders WHERE customerId = :customerId',
    arguments: {'customerId': customerId},
  );
  return result.items.first.value;
}

// ✅ GOOD: Existence check stops at the first match
Future<bool> hasOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE status = :status LIMIT 1',
    arguments: {'status': 'open'},
  );
  return result.items.isNotEmpty;
}
```

**Why:** Aggregates must process every matching document before they return (they are blocking steps in the query pipeline). Memory grows with the number of groups, not with the number of documents, but the work still grows with the number of matching documents. Keep `WHERE` selective and avoid running expensive aggregates in observers that fire frequently.

### GROUP BY and HAVING

Every non-aggregate projection must be a `GROUP BY` key. `GROUP BY` and `HAVING` **cannot reference projection aliases**: repeat the expression instead. `ORDER BY` can use aliases.

<!-- expect-error -->
```sql
-- ❌ BAD: GROUP BY uses the alias "day":
-- Projection "day" must depend only on group keys or aggregates
SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue
FROM orders
GROUP BY day
```

<!-- expect-error -->
```sql
-- ❌ BAD: HAVING uses the alias "revenue":
-- HAVING clause terms must depend only on group keys or aggregates
SELECT customerId, SUM(total) AS revenue
FROM orders
GROUP BY customerId
HAVING revenue > 1000
```

```sql
-- ✅ GOOD: Repeat the expressions in GROUP BY and HAVING; ORDER BY may use aliases
SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue
FROM orders
WHERE createdAt >= :since
GROUP BY date_format(createdAt, 'YYYY-MM-DD')
HAVING SUM(total) > 1000
ORDER BY day
```

```dart
// ✅ GOOD: Revenue per customer, highest first
Future<List<Map<String, dynamic>>> revenueByCustomer(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT customerId, COUNT(*) AS orderCount, SUM(total) AS revenue '
    'FROM orders WHERE status = :status '
    'GROUP BY customerId '
    'HAVING COUNT(*) >= :minOrders '
    'ORDER BY revenue DESC',
    arguments: {'status': 'completed', 'minOrders': 2},
  );
  return result.items.map((item) => item.value).toList();
}
```

### ORDER BY

Results have no guaranteed order unless you specify `ORDER BY`. The default direction is `ASC`. When values of different types are sorted together, the ascending order is:

`false` < `true` < numbers < binary < strings < arrays < objects < `null` < missing

`DESC` reverses the whole sequence, so documents with a missing sort field come **first** in descending order, followed by those with `null`: a newest-first list (`ORDER BY createdAt DESC`) shows documents without `createdAt` at the top (see [Descending order puts missing and null first](../knowledge/observations/dql-behavior.md#descending-order-puts-missing-and-null-first)).

Strings compare by Unicode code point, not in the alphabetical order of a language: uppercase letters sort before lowercase ones (`'B'` before `'a'`), accented letters after `'z'`, and digits as characters (`'10'` before `'9'`). `LIKE` is case-sensitive too; use `ILIKE` to ignore case (in our testing; see [Comparisons across types are MISSING, and strings sort by code point](../knowledge/observations/dql-behavior.md#comparisons-across-types-are-missing-and-strings-sort-by-code-point)).

**✅ DO:**
- Add `ORDER BY` to every observer query whose order matters in the UI. Observers do not guarantee a stable order without it.
- Add a unique tie-breaker such as `_id` when the sort key can repeat: `ORDER BY createdAt DESC, _id`. In our testing, SDK 5.1.0 and 5.2.0 returned rows with equal sort keys in ascending `_id` order, also with `DESC`, but that is not documented, and SDK 5.0.3 returned them in another order, so that `LIMIT n` did not return the first n rows (see [Rows with equal sort keys come back in _id order since SDK 5.1](../knowledge/observations/dql-behavior.md#rows-with-equal-sort-keys-come-back-in-_id-order-since-sdk-51)). Give the tie-breaker the same direction as the sort key (`ORDER BY createdAt DESC, _id DESC`) if ties should reverse too.
- Store sortable values in one consistent type (for example, all timestamps as ISO-8601 UTC strings produced by one helper with a fixed precision; see [Timestamps](data-modeling.md#timestamps)), and numbers as numbers, not as strings of digits.
- Sort names for display in your app with the user's locale, or on `lower(name)` for small results (a function on the field cannot use an index); `ORDER BY name` puts `Zoe` before `adam`.

**❌ DON'T:**
- Rely on insertion order.
- Expect `ORDER BY status = 'urgent'` to put matching documents first in ascending order: `false` sorts before `true`. Use `DESC` (and keep in mind that missing values then come first) or an explicit `CASE`.

```sql
-- Urgent tasks first, then by due date
SELECT * FROM tasks
WHERE coalesce(isDeleted, false) = false
ORDER BY CASE WHEN priority = 'urgent' THEN 0 ELSE 1 END, dueAt, _id
```

Sorting large result sets costs memory and time unless an index provides the order; see [Index Usage Rules](indexing-and-performance.md#index-usage-rules).

### LIMIT and OFFSET

`LIMIT` and `OFFSET` accept parameters. Always combine them with `ORDER BY`, otherwise the page contents are not well defined.

**✅ DO:**
- Prefer keyset pagination (`WHERE sortKey < :lastValue ORDER BY sortKey DESC LIMIT n`) for long lists; use a unique sort key or add a tie-breaker. In our testing, one document inserted at the top between two `OFFSET` page reads made the last row of the first page appear again on the second, while keyset pagination with `_id` as the tie-breaker (`WHERE createdAt < :at OR (createdAt = :at AND _id < :id)`) returned no duplicates and skipped nothing (see [OFFSET pages repeat rows after inserts, and keyset pages do not](../knowledge/observations/dql-behavior.md#offset-pages-repeat-rows-after-inserts-and-keyset-pages-do-not)).
- Use `LIMIT` in `execute` and observers to cap memory.

**❌ DON'T:**
- Put `LIMIT` or `ORDER BY` in a subscription. Subscriptions reject them by default, and a subscription defines which documents sync, not how a screen pages through them. See [Subscription Rules](sync-and-subscriptions.md#subscription-rules).

```dart
// ✅ GOOD: Keyset pagination: continue after the last row of the previous page.
// _id breaks ties between rows that share the same createdAt.
// Load the first page with the same query without the WHERE clause.
Future<List<Map<String, dynamic>>> nextPage(
  Ditto ditto, {
  required String afterCreatedAt,
  required String afterId,
  int pageSize = 50,
}) async {
  final result = await ditto.store.execute(
    'SELECT _id, title, createdAt FROM tasks '
    'WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId) '
    'ORDER BY createdAt DESC, _id DESC LIMIT :pageSize',
    arguments: {
      'after': afterCreatedAt,
      'afterId': afterId,
      'pageSize': pageSize,
    },
  );
  return result.items.map((item) => item.value).toList();
}

// Works, but every page re-reads and skips all earlier rows.
// _id makes the order unique, so rows are not repeated or skipped across pages.
Future<List<Map<String, dynamic>>> pageByOffset(Ditto ditto, int page) async {
  const pageSize = 50;
  final result = await ditto.store.execute(
    'SELECT _id, title, createdAt FROM tasks '
    'ORDER BY createdAt DESC, _id DESC LIMIT :pageSize OFFSET :offset',
    arguments: {'pageSize': pageSize, 'offset': page * pageSize},
  );
  return result.items.map((item) => item.value).toList();
}
```

### USE IDS

`USE IDS` reads documents by ID directly:

```sql
SELECT * FROM orders USE IDS 'order-1', 'order-2'

SELECT * FROM orders USE IDS LIST :ids
```

| Form | Behavior |
|---|---|
| `USE IDS 'a', 'b'` | ✅ Literal IDs, comma-separated, no parentheses |
| `USE IDS LIST :ids` | ✅ Array parameter |
| `USE IDS ('a', 'b')` | ❌ Error: `('a', 'b') is not supported` | <!-- lint-ignore -->
| `USE IDS :ids` with an array | ❌ Treats the whole array as a single ID: returns nothing, or, above 256 bytes, fails with `SerializedFormOverLimit` |

A `WHERE _id = :id` or `WHERE _id IN :ids` filter is also planned as a direct ID lookup, so for most code the `WHERE` form is the simplest choice. For long lists, it is slower: the plan checks each found document against the list again, and in our testing with SDK 5.1.0 and 5.2.0, 10,000 IDs took about 0.7 seconds with `WHERE _id IN :ids`, for reads and writes alike, and 17 to 65 ms with `USE IDS LIST :ids`. Above about 1,000 IDs, use `USE IDS LIST :ids` for reads and `UPDATE`, or split the list into chunks of 1,000. A subscription by a long ID list also made the initial sync slower than one by a field that selects the same documents (3.3 against 0.9 seconds for 10,000 documents); see [Long ID lists are faster with USE IDS LIST than with WHERE _id IN](../knowledge/observations/performance-measurements.md#long-id-lists-are-faster-with-use-ids-list-than-with-where-_id-in).

For `DELETE` and `EVICT`, prefer the `WHERE` form as long as any device runs SDK 5.1.0, where `USE IDS` without a `WHERE` predicate removes nothing (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510) and [On SDK 5.1.0, DELETE and EVICT with USE IDS and no WHERE predicate remove nothing](../knowledge/observations/dql-behavior.md#on-sdk-510-delete-and-evict-with-use-ids-and-no-where-predicate-remove-nothing)); SDK 5.0.3 rejected `USE IDS` in `DELETE` as a syntax error in our testing (see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)).

```dart
// ✅ GOOD: Direct ID lookup with an array parameter
Future<List<Map<String, dynamic>>> ordersByIds(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

### Filtering by Membership

| Goal | Expression | Notes |
|---|---|---|
| Field equals one of several values | `status IN :statuses` | ✅ Array parameter; can use an index on `status` |
| Field equals none of several values | `status NOT IN :statuses` | Documents where `status` is missing are not returned |
| Literal list | `status IN ('open', 'pending')` | ✅ |
| Array field contains a value | `:tag IN tags` or `array_contains(tags, :tag)` | ✅ Element lookups cannot use an index |
| Array parameter, wrapped in parentheses | `status IN (:statuses)` | ❌ Matches nothing |
| A single value instead of an array | `status IN :statuses` with `'open'` | ❌ Matches nothing, without an error |
| Equality with an array parameter | `status = :statuses` | ❌ Compares with the whole array, so only array fields with the same elements match |

An empty array returns no rows, also without an error (see [Wrong argument types fail silently](../knowledge/observations/dql-behavior.md#wrong-argument-types-fail-silently)). Pass a set of alternatives as one array parameter with `IN :values`, not as a chain of `OR` terms built in code. Long chains crashed SDK 5.1.0, in our testing at 15,000 `OR` terms and without an exception (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510) and [Long OR chains crashed SDK 5.1.0](../knowledge/observations/dql-behavior.md#long-or-chains-crashed-sdk-510)), and in our testing with 5.1.0 and 5.2.0, a condition that wrapped each term in another pair of parentheses failed at 100 levels with `DQL parser error: recursion limit exceeded` (see [Conditions fail at 100 levels of nested parentheses](../knowledge/observations/dql-behavior.md#conditions-fail-at-100-levels-of-nested-parentheses)).

```dart
// ✅ GOOD: Membership against an array parameter
Future<List<Map<String, dynamic>>> tasksWithStatus(
  Ditto ditto,
  List<String> statuses,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE status IN :statuses ORDER BY _id',
    arguments: {'statuses': statuses},
  );
  return result.items.map((item) => item.value).toList();
}

// ✅ GOOD: Documents whose tags array contains a value
Future<List<Map<String, dynamic>>> tasksTagged(Ditto ditto, String tag) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE :tag IN tags ORDER BY _id',
    arguments: {'tag': tag},
  );
  return result.items.map((item) => item.value).toList();
}
```

> **Note (SDK 5.1.0 and 5.2.0):** An `ANY ... SATISFIES ... END` expression in a `WHERE` clause that iterates over a parameter or a literal array, such as `WHERE ANY s IN :statuses SATISFIES s = status END`, returns no rows. Use `status IN :statuses` (or `array_contains(:statuses, status)`) for membership filters. This is a known issue since 5.1.0, and 5.2.0 does not fix it; in our testing, 5.0.3 returned the matching documents (see [ANY and EVERY over a parameter or literal array return no rows since SDK 5.1.0](../knowledge/observations/dql-behavior.md#any-and-every-over-a-parameter-or-literal-array-return-no-rows-since-sdk-510)). A subscription with the same `WHERE` clause syncs the right documents, so the usual "subscribe and observe with the same query" pattern receives the data but shows an empty list. See [ANY and EVERY](../knowledge/dql-functions.md#any-and-every). <!-- lint-ignore -->

### Joining Collections (SDK 5.1+)

`SELECT` can combine documents from several collections with `JOIN`. Joins run on the documents that are already in the local store.

#### Join types

| Join | Rows returned | Unmatched right side |
|---|---|---|
| `JOIN` / `INNER JOIN` | Only pairs that satisfy `ON` | Row dropped |
| `LEFT [OUTER] JOIN` | Every left row, matched or not | Right-side fields are MISSING |
| `RIGHT [OUTER] JOIN` | Every right row, matched or not | Left-side fields are MISSING; allowed only as the first join |

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)).

`FULL OUTER JOIN`, `CROSS JOIN`, comma joins (`FROM a, b`), and joins in `UPDATE` / `DELETE` are not supported.

The `ON` clause can be any condition over the aliases introduced so far, including `AND` / `OR` and filters on one side:

```sql
-- Every customer with their orders; customers without orders are kept
-- (requires an index on orders.customerId; see Index requirement below)
SELECT c.name, o._id AS orderId, o.total
FROM customers c
LEFT JOIN orders o ON o.customerId = c._id AND o.status = 'open'
ORDER BY c.name, o.total
```

```sql
-- Customers without any order (unmatched LEFT JOIN rows)
-- (requires an index on orders.customerId; see Index requirement below)
SELECT c._id, c.name
FROM customers c
LEFT JOIN orders o ON o.customerId = c._id
WHERE o._id IS MISSING
```

#### Index requirement

Ditto executes joins as nested loops: for each row of the outer collection it looks up matching rows in the inner (joined) collection. This lookup must use an index or an ID lookup unless you explicitly allow a scan with `USE INDEX ''` (see below). Without one, the query fails before it runs:

<!-- expect-error -->
```sql
-- ❌ BAD: No index on customers.email
SELECT o._id, c.name
FROM orders o
JOIN customers c ON c.email = o.customerEmail
```

```text
Query failed: `Joining to "c" disallowed without appropriate index support. Please run ADVISE for recommendations.`
```

In our testing on SDK 5.1.0 and 5.2.0, a join without an index failed with this error, while a join on `_id` and a join with `USE INDEX ''` worked without an index (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)).

The fix is to index the join key of the inner collection (here `CREATE INDEX IF NOT EXISTS idx_customers_email ON customers (email)`). For example, joining orders by `customerId` needs this index:

```sql
-- ✅ GOOD: Index the join key of the inner collection
CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)
```

```sql
SELECT c.name, o._id AS orderId, o.total
FROM customers c
JOIN orders o ON o.customerId = c._id
WHERE c.tier = 'gold'
ORDER BY c.name, o.total DESC
```

Joining **on `_id`** of the inner collection needs no extra index, because Ditto looks documents up by ID:

```sql
-- ✅ GOOD: Inner side is looked up by _id
SELECT o._id, o.total, c.name AS customerName
FROM orders o
JOIN customers c ON c._id = o.customerId
WHERE o.status = 'open'
ORDER BY o._id
```

For a small collection, you can explicitly allow a full scan of one join term with `USE INDEX ""` (or `USE INDEX ''`) placed before `ON`. Other join terms in the same statement still need an index.

```sql
-- Explicitly accept a collection scan of a small lookup collection
SELECT o._id, r.label
FROM orders o
JOIN regions r USE INDEX '' ON r.code = o.regionCode
```

Run `ADVISE` on a join query to get the `CREATE INDEX` statements it needs; see [ADVISE (SDK 5.1+)](indexing-and-performance.md#advise-sdk-51). Indexes persist across app restarts, so create them once (for example with `CREATE INDEX IF NOT EXISTS` at startup).

#### Result shape

| Projection | Result row |
|---|---|
| `SELECT *` | One nested object per alias: `{"c": {...}, "o": {...}}` |
| `SELECT c.*, o.total` | Flat: all customer fields plus `total` |
| `SELECT _id` | A composite ID per joined row: `{"c": "c1", "o": "o1"}` |
| `SELECT name` (field exists on both sides) | Error: `Ambiguous reference to field: name` |

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)).

Always qualify fields with their alias (`c.name`, `o.total`) and alias projected fields that would otherwise collide (`o._id AS orderId`).

#### Restrictions

- **Local data only**: A join reads only documents already in the local store. It never fetches missing documents from peers, so every joined collection needs its own subscription.
- **Not in subscriptions**: `registerSubscription` rejects joins (`Unsupported feature: Joining`). Subscribe to each collection separately with `SELECT * FROM c WHERE ...`.
- **Not on Ditto Server**: Joins are a Small Peer feature; Ditto Server queries (including the HTTP API) do not support them.
- **`RIGHT JOIN` only as the first join**: A later `RIGHT JOIN` fails with `RIGHT OUTER join that isn't the first join is not supported` (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)). Because Ditto rewrites a `RIGHT JOIN` as a `LEFT JOIN` with the sides swapped, the collection written on the left then becomes the inner side and needs the index (or the `_id` join).
- **At most 10 joins per statement** by default (directive `#max_joins`; see [Directives](indexing-and-performance.md#directives)). More fail with `Too many joins: the number of joined terms exceeds the maximum permitted.`

#### Joins in observers

`registerObserver` accepts joins, and the observer delivers a new result when a change in any of the joined collections changes the joined rows (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)). On SDK 5.1.0, each row delivered to the observer carried a composite `_id` (for example `{"c": "c1", "o": "o1"}`); on 5.2.0 it did not in our testing (see [On SDK 5.2.0, observer rows include _id only when it is projected](../knowledge/observations/observer-behavior.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected)), so project the keys that identify a row yourself (for example `o._id AS orderId`) when you diff or key a list. Subscribe to each collection the join reads.

```dart
// ✅ GOOD: Subscribe per collection (app or feature scope), join locally
List<SyncSubscription> subscribeForOrderList(Ditto ditto) => [
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE status = :status',
        arguments: {'status': 'open'},
      ),
      ditto.sync.registerSubscription('SELECT * FROM customers'),
    ];

// ✅ GOOD: Observe the join (screen scope); call dispose() when the screen goes away
class OpenOrdersWithCustomers {
  OpenOrdersWithCustomers(
    Ditto ditto,
    void Function(List<Map<String, dynamic>> rows) onRows,
  ) : _observer = ditto.store.registerObserver(
          'SELECT o._id AS orderId, o.total, c.name AS customerName '
          'FROM orders o JOIN customers c ON c._id = o.customerId '
          'WHERE o.status = :status ORDER BY o.createdAt DESC, o._id',
          arguments: {'status': 'open'},
        ) {
    _changes = _observer.changes.listen(
      (result) => onRows(result.items.map((item) => item.value).toList()),
    );
  }

  final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;

  void dispose() {
    _changes.cancel();
    _observer.cancel();
  }
}
```

For a complete widget lifecycle (register in `initState`, cancel the stream subscription and the observer in `dispose`), follow [Store Observers in Flutter](observers.md#store-observers-in-flutter).

#### Join or embed?

Joins make separate, normalized collections practical to query, but they do not change the main data modeling trade-offs: embedded data is updated atomically in one document and syncs as one unit, while separate collections let you sync, secure, and update parts independently. Ditto's guidance remains to embed by default and to split data when access patterns, permissions, or document size call for it. See [Relationships: Embedding, Separate Collections, and JOIN](data-modeling.md#relationships-embedding-separate-collections-and-join).

#### Performance tips

**✅ DO:**
- Index the join key of every inner collection, or join on `_id`.
- Start from the most selective collection and filter it in `WHERE` (for example `WHERE o.status = 'open'`), so fewer outer rows drive lookups.
- Qualify every field with its alias.
- Check the plan with `EXPLAIN` during development (a join appears as `nlJoin`) and run `ADVISE` before release. See [EXPLAIN and PROFILE](indexing-and-performance.md#explain-and-profile).

**❌ DON'T:**
- Use `USE INDEX ''` on large collections to silence the index error: every outer row then scans the whole inner collection.
- Rely on a join to pull related documents onto a device: subscribe to them explicitly.

## Writing Data

### INSERT and Conflict Handling

Insert documents by passing them as parameters. Each document needs a unique `_id` (or Ditto generates one; see [Document IDs](data-modeling.md#document-ids)).

```dart
// ✅ GOOD: One document as a parameter
Future<void> createOrder(Ditto ditto, String id, String customerId) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': id,
        'customerId': customerId,
        'status': 'open',
        'total': 0,
        // createdAt is sorted and compared, so it uses the fixed-precision
        // helper. utcTimestamp() is defined in the Timestamps section.
        'createdAt': utcTimestamp(),
      },
    },
  );
}

// ✅ GOOD: Several documents in one statement, as an array parameter
Future<void> importProducts(Ditto ditto, List<Map<String, dynamic>> products) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'products': products},
  );
}
```

You can also list several parameters: `DOCUMENTS (:first), (:second)`. A multi-document insert is atomic: if one document fails (for example with an ID conflict under `FAIL`), none of them is inserted. Two documents with the same `_id` in one statement fail with `Expected unique document identifiers`.

The number of statements matters more than the number of documents. In our testing with the JavaScript SDK, 2,000 documents took about 4 seconds as 2,000 awaited `INSERT` statements and 17 ms as one statement with an array parameter (see [The number of execute calls matters more than the number of documents](../knowledge/observations/performance-measurements.md#the-number-of-execute-calls-matters-more-than-the-number-of-documents)). Import data in a few large statements, for example in chunks of a few hundred documents.

#### ON ID CONFLICT

| Policy | When the `_id` already exists locally |
|---|---|
| `FAIL` (default when omitted) | The statement fails: `Identifier conflict on document "...": using FAIL conflict policy` |
| `DO NOTHING` | The existing document is left unchanged; no error |
| `DO UPDATE` | Fields from the new document are written into the existing one. Fields you do not supply are kept, and nested objects are merged. Every supplied field is written, even if the value is identical, so the document is reported as mutated and observers can fire again (a `SELECT *` observer on the collection does). A field written again with its current value still wins over an earlier concurrent edit of that field on another device. |
| `DO UPDATE_LOCAL_DIFF` | Same merge, but only fields whose values differ from the local document are written. If nothing changed, nothing is written and `mutatedDocumentIDs()` is empty. A value from a stale copy differs from the local one and is written. |

In our testing on one device with SDK 5.1.0 and 5.2.0, the four policies behaved as this table describes (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

**✅ DO:**
- Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports (for example when refreshing reference data from your backend).
- Use `DO NOTHING` for "create if absent" logic.
- Use `UNSET` (see [UPDATE](#update)) to remove fields. No `INSERT` policy deletes fields.

**❌ DON'T:**
- Use `DO UPDATE` to "replace" a document. It merges; fields missing from the new document stay.
- Use `DO UPDATE` for periodic re-upserts of unchanged data. Every run rewrites all supplied fields, records a mutation, can wake observers, and overwrites concurrent edits of those fields that other devices made earlier.
- Upsert documents that contain a `COUNTER` field. The upserted value restarts the counter and discards increments that have not reached this device yet (see [Writing documents that contain counters](data-modeling.md#writing-documents-that-contain-counters) and [An upsert that declares a counter restarts it](../knowledge/observations/merge-behavior.md#an-upsert-that-declares-a-counter-restarts-it)).

```dart
// ✅ GOOD: Re-upserting unchanged data is a no-op
Future<bool> syncCatalogItem(Ditto ditto, Map<String, dynamic> item) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:item) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'item': item},
  );
  // Empty when the stored document already had the same values
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

Merge behavior, starting from `{"_id": "p1", "name": "Pen", "price": 5, "address": {"city": "Oslo", "zip": "0150"}}`:

```dart
Future<void> doUpdateMerges(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE',
    arguments: {
      'doc': {
        '_id': 'p1',
        'price': 6,
        'address': {'street': 'Main St'},
      },
    },
  );
  // Stored document afterwards:
  // {"_id": "p1", "name": "Pen", "price": 6,
  //  "address": {"city": "Oslo", "zip": "0150", "street": "Main St"}}
}
```

**Why:** With the default `DQL_STRICT_MODE = false`, objects are stored as CRDT maps that merge field by field (see [Strict Mode](data-modeling.md#strict-mode) and [CRDT Types and Merge Behavior](../knowledge/crdt-types.md)). A field that is written again, even with the value it already has, is a new write that wins over an earlier concurrent edit of that field on another device (see [Writing a Value That Did Not Change](../knowledge/crdt-types.md#writing-a-value-that-did-not-change) and [Rewriting an unchanged value overwrites concurrent edits](../knowledge/observations/merge-behavior.md#rewriting-an-unchanged-value-overwrites-concurrent-edits)). Writing only what changed avoids that, and it keeps sync deltas small.

#### INITIAL DOCUMENTS

`INSERT INTO c INITIAL DOCUMENTS (...)` seeds default data, such as default settings or a starter catalog, that every peer may create independently. The syntax is the same as for `DOCUMENTS`: pass each document as a parameter.

- If no document with that `_id` exists locally, it is inserted; if one exists, nothing happens and no error is raised.
- When several devices create the same document independently, the initial values do not replace what other devices have already changed. This makes `INITIAL DOCUMENTS` the way to create a document with a `COUNTER` on each device (see [Writing documents that contain counters](data-modeling.md#writing-documents-that-contain-counters) and [INITIAL DOCUMENTS keeps concurrent counter increments](../knowledge/observations/merge-behavior.md#initial-documents-keeps-concurrent-counter-increments)).
- `ON ID CONFLICT` cannot be combined with `INITIAL DOCUMENTS` (parser error), and the source cannot be a `SELECT` (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

How initial documents merge across peers, and what happens after a seeded document is deleted or evicted, is described in [Default Data with INITIAL Documents](data-modeling.md#default-data-with-initial-documents).

```dart
// ✅ GOOD: Seed defaults on every launch; existing (possibly edited) data is kept
Future<void> seedDefaults(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO settings INITIAL DOCUMENTS (:defaults)',
    arguments: {
      'defaults': {
        '_id': 'app',
        'theme': 'light',
        'currency': 'USD',
      },
    },
  );
}
```

**❌ DON'T:** Use `INITIAL DOCUMENTS` to keep data off the network. Whether data syncs is decided by subscriptions.

#### INSERT ... SELECT (SDK 5.1+)

Copy or derive documents from a query. Each result row becomes a document, and projection aliases become field names. If the projection includes `_id`, it is used as the document ID; otherwise a new ID is generated.

```sql
-- Copy closed orders into an archive collection; safe to re-run
INSERT INTO archivedOrders
SELECT * FROM orders WHERE status = 'closed'
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
-- Build one summary document per status
INSERT INTO orderStats
SELECT status AS _id, COUNT(*) AS orderCount FROM orders GROUP BY status
ON ID CONFLICT DO UPDATE
```

The `SELECT` follows `INSERT INTO c` directly. Wrapping it in parentheses or in `DOCUMENTS (...)` is a syntax error, and `INITIAL DOCUMENTS` cannot be combined with a `SELECT` source (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

A query result contains plain values, so declare `COUNTER` and `ATTACHMENT` fields on **both** sides when the copied documents have them. Without the declarations, the copy stores a counter as a plain number, which a later `INCREMENT` on the copy hides behind a new counter that starts at 0, and an attachment as an ordinary map that cannot be fetched (in our testing; see [INSERT ... SELECT copies counters and attachments as plain values](../knowledge/observations/merge-behavior.md#insert--select-copies-counters-and-attachments-as-plain-values)). Do not add `ON ID CONFLICT DO UPDATE` here: an upsert restarts the copied counters (see [Writing documents that contain counters](data-modeling.md#writing-documents-that-contain-counters)).

```sql
-- Copy closed orders that have a counter and an attachment
INSERT INTO COLLECTION archivedOrders (tipCount COUNTER, receipt ATTACHMENT)
SELECT * FROM COLLECTION orders (tipCount COUNTER, receipt ATTACHMENT)
WHERE status = 'closed'
```

### UPDATE

```text
UPDATE collection [USE IDS ...]
[APPLY counterField INCREMENT BY n, ...]
[SET field = value, nested.path = value, ...]
[UNSET field, nested.path, ...]
[WHERE condition]
[RETURNING projection]
```

At least one of `APPLY`, `SET`, or `UNSET` is required. Without `WHERE`, every document in the collection is updated, without a warning. The clauses must appear in this order: `APPLY` (counters) before `SET`, and `UNSET` after `SET`. Counter updates are covered in [Counters](data-modeling.md#counters).

```dart
// ✅ GOOD: Change only the fields that changed
Future<void> completeOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status, completedAt = :completedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'status': 'completed',
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

// ✅ GOOD: Nested paths; missing intermediate objects are created automatically
Future<void> setShippingCity(Ditto ditto, String orderId, String city) async {
  await ditto.store.execute(
    'UPDATE orders SET shipping.address.city = :city WHERE _id = :id',
    arguments: {'id': orderId, 'city': city},
  );
}

// ✅ GOOD: UNSET removes fields (they become MISSING)
Future<void> clearDiscount(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id',
    arguments: {'id': orderId},
  );
}
```

Errors to expect:
- `SET _id = ...` fails: ``The document id `_id` cannot be modified``.
- Setting the same path twice in one statement fails: `More than one modification specified for the path ...`.
- Array elements cannot be assigned (`SET items[0] = ...` is a syntax error). Replace the whole array, or model the collection as a map keyed by ID (see [Arrays and Maps](data-modeling.md#arrays-and-maps)).

In our testing, SDK 5.1.0 and 5.2.0 reported each of these errors (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

Not reported as an error: a nested `SET a.b = 1` adds `b` when `a` is an object, but when `a` holds a string, a number, an array, or `null`, it replaces `a` with `{"b": 1}`, and the old value is lost (in our testing; see [Statements without WHERE change every document](../knowledge/observations/dql-behavior.md#statements-without-where-change-every-document)).

#### Assigning an object merges it

With the default strict mode (`DQL_STRICT_MODE = false`), an object field is a CRDT map. `SET obj = {...}` **merges** the new keys into the existing object instead of replacing it, and `SET obj = {}` leaves the object unchanged.

Keys are removed only by `UNSET`, so replacing an object takes `UNSET` followed by `SET` in one transaction. The full table of local write semantics for maps, including upserts and scalar overwrites, is in [Local Write Semantics You Must Know](../knowledge/crdt-types.md#local-write-semantics-you-must-know).

**✅ DO:**
- Update nested fields individually: `SET address.city = :city`.
- Remove keys with `UNSET address.zip`.
- To replace an object completely, run `UNSET` and then `SET` inside one transaction, or declare the field as a `REGISTER` so it is always replaced as a whole (see [Strict Mode](data-modeling.md#strict-mode)).

**❌ DON'T:**
- Expect `SET obj = {...}` to remove keys that are not in the new value.
- Use `SET obj = {}` to clear an object.

```dart
// ✅ GOOD: Replace an object: remove the old map, then write the new one,
// in one transaction so that no observer sees the object missing
Future<void> replaceAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.transaction(hint: 'replaceAddress', (tx) async {
    await tx.execute(
      'UPDATE customers UNSET address WHERE _id = :id',
      arguments: {'id': customerId},
    );
    await tx.execute(
      'UPDATE customers SET address = :address WHERE _id = :id',
      arguments: {'id': customerId, 'address': newAddress},
    );
  });
}
```

#### Prefer field-level updates over whole-document rewrites

**✅ DO:**
- Use `UPDATE ... SET` for the fields that changed.
- Skip writes that would not change anything, for example with a condition in `WHERE`, or use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts (it skips unchanged fields but does not protect a stale in-memory copy; see [Prefer field-level updates](data-modeling.md#prefer-field-level-updates) in Document Structure).

**❌ DON'T:**
- Read a document, modify it in Dart, and write the whole map back with `INSERT ... ON ID CONFLICT DO UPDATE`.
- Write values that are already stored. An `UPDATE` that sets a field to its current value is still recorded as a mutation, appears in `mutatedDocumentIDs()`, and can wake observers (a `SELECT *` observer fires again with an identical result; see [When an observer fires depends on its query](../knowledge/observations/observer-behavior.md#when-an-observer-fires-depends-on-its-query)). It is also synced: in our testing, a `SELECT *` observer on another device fired for it as well, and the rewritten value replaced a concurrent edit of the field that the other device had made earlier (see [Rewriting an unchanged value overwrites concurrent edits](../knowledge/observations/merge-behavior.md#rewriting-an-unchanged-value-overwrites-concurrent-edits) and [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)).

```dart
// ❌ BAD: Read-modify-write of the whole document
Future<void> completeOrderByRewrite(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': orderId},
  );
  if (result.items.isEmpty) return;
  final order = Map<String, dynamic>.from(result.items.first.value);
  order['status'] = 'completed';
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
    arguments: {'order': order},
  );
}

// ✅ GOOD: Single field-level update that skips unchanged documents
Future<bool> setStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': ''},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

The `coalesce` in the condition keeps documents whose `status` is missing or `null` eligible for the update; a plain `status != :status` would skip them (see [MISSING and NULL](#missing-and-null)).

**Why:** Ditto syncs changes at field level, and every field that a statement writes counts as a new write, even when its value did not change. Rewriting a whole document therefore overwrites every concurrent edit that another device made earlier to any of its fields, and it makes the change larger (see [Writing a Value That Did Not Change](../knowledge/crdt-types.md#writing-a-value-that-did-not-change)). Field-level updates touch only what the user actually changed.

### RETURNING (SDK 5.1+)

Add `RETURNING` to `INSERT`, `UPDATE`, `DELETE`, or `EVICT` to get the affected documents back in `items`, in the same statement.

| Statement | Rows in `items` |
|---|---|
| `INSERT ... RETURNING` | The documents written (documents skipped by `DO NOTHING` or left unchanged by `DO UPDATE_LOCAL_DIFF` are not returned) |
| `UPDATE ... RETURNING` | The documents **after** the update |
| `DELETE ... RETURNING` / `EVICT ... RETURNING` | The documents **before** they were removed |

In our testing on SDK 5.1.0 and 5.2.0, `INSERT`, `UPDATE`, and `DELETE` returned the rows this table describes (see [JOIN, RETURNING, document ID, and timestamp statements held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#join-returning-document-id-and-timestamp-statements-held-on-sdk-510-and-520)).

`commitID` is populated as usual when `RETURNING` is used, and so is `mutatedDocumentIDs()`. With `RETURNING`, read the affected documents from `items`, and include `_id` in the `RETURNING` projection when you need the IDs instead of relying on `mutatedDocumentIDs()`.

```dart
// ✅ GOOD: Update and read the new values in one statement
Future<List<Map<String, dynamic>>> markShipped(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status, shippedAt = :now '
    'WHERE _id IN :ids AND status = :expected '
    'RETURNING _id, status, shippedAt',
    arguments: {
      'ids': ids,
      'status': 'shipped',
      'expected': 'packed',
      'now': DateTime.now().toUtc().toIso8601String(),
    },
  );
  return result.items.map((item) => item.value).toList();
}

// ✅ GOOD: Keep a copy of what was deleted (for an undo banner or an audit log)
Future<List<Map<String, dynamic>>> deleteDrafts(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'DELETE FROM drafts WHERE _id IN :ids RETURNING *',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

The projection syntax is the same as in `SELECT`, including aliases and expressions. Aggregates summarize all affected documents:

```sql
DELETE FROM sessions WHERE expiresAt < :now RETURNING COUNT(*) AS removed
```

**Why:** `RETURNING` replaces the "write, then query again" pattern with one statement, so the values you read are exactly the ones you wrote, and for `DELETE` it returns the removed content from the same atomic statement.

### DELETE and EVICT

| Statement | Effect |
|---|---|
| `DELETE FROM c WHERE ...` | Deletes the documents on all peers. Leaves a tombstone that syncs the deletion. |
| `EVICT FROM c WHERE ...` | Removes the documents from this device only. Other peers keep them, and they can be synced back while a matching subscription is active (see [EVICT](deletion-and-storage.md#evict)). |

Choosing between them, tombstone lifetime, soft delete, and storage cleanup are covered in [Deletion and Storage Management](deletion-and-storage.md).

**❌ DON'T:**
- Build the `WHERE` clause of a `DELETE`, `EVICT`, or `UPDATE` from optional filters in a way that can leave it empty. Without `WHERE`, the statement changes every document in the collection, and nothing asks for confirmation or logs a warning (see [Statements without WHERE change every document](../knowledge/observations/dql-behavior.md#statements-without-where-change-every-document)). Write one fixed statement per case and pass the values as parameters.

To select documents by ID, use `WHERE _id = :id` or `WHERE _id IN :ids`; it is planned as an ID lookup and also works on SDK 5.1.0, where `USE IDS` without a `WHERE` predicate removes nothing (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510) and [On SDK 5.1.0, DELETE and EVICT with USE IDS and no WHERE predicate remove nothing](../knowledge/observations/dql-behavior.md#on-sdk-510-delete-and-evict-with-use-ids-and-no-where-predicate-remove-nothing)).

`RETURNING` (SDK 5.1+) on `DELETE` and `EVICT` returns the documents as they were before removal; see [DELETE and Tombstones](deletion-and-storage.md#delete-and-tombstones) for more examples.
