# Indexing and Query Performance

Indexes let the query engine find matching documents without scanning a whole collection. They speed up `WHERE` filters, `ORDER BY` clauses, and the inner side of a JOIN (see [Joining Collections (SDK 5.1+)](dql.md#joining-collections-sdk-51)). Every index also has a cost: it is updated on every write to the collection, uses storage, and creating it scans the whole collection.

Indexes help most when a query returns a small fraction of a collection, because the engine can skip the documents that do not match. For queries that return most of a collection, an index adds little.

## Creating Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)

CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)

CREATE INDEX IF NOT EXISTS idx_orders_city ON orders (address.city)
```

Syntax:

```text
CREATE INDEX [IF NOT EXISTS] <name> ON <collection> (<field> [ASC|DESC], ...)
DROP INDEX [IF EXISTS] <name> ON <collection>
```

- **Single-field indexes** cover one field. `ASC` is the default.
- **Composite indexes (SDK 5.1+)** cover several fields in order. Put equality fields first and range or sort fields last (see [Index Usage Rules](#index-usage-rules)). On SDK 5.1.0, do not mix `ASC` and `DESC` keys in one index: queries that use such an index can return their results in the wrong order (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)).
- **Nested paths** use dot notation, for example `address.city`.
- **Array and object values (SDK 5.1+)** can be indexed, but only as whole values: an index on `tags` speeds up `tags = ['x', 'y']`, not "contains `'x'`", and an index on `address` does not help a filter on `address.city`. Index the full path you filter on.
- **Expression indexes do not exist.** `CREATE INDEX ... (lower(name))` is a parser error. Partial and functional indexes are not supported.
- Documents that do not contain the indexed field are still covered by SDK indexes, so `IS MISSING` and `!=` filters return correct results through an index.

`IF NOT EXISTS` checks only the **name**. If an index with the same name already exists on the collection, the statement succeeds and changes nothing, even when the field list differs. To change an index definition, create it under a new name (and drop the old one), or drop and recreate it. Without `IF NOT EXISTS`, a duplicate name fails with `an index with the given name already exists on the given collection`. Index names are scoped to a collection.

```sql
-- ✅ GOOD: DROP INDEX requires ON <collection>
DROP INDEX IF EXISTS idx_orders_city ON orders
```

<!-- expect-error -->
```sql
-- ❌ BAD: parser error (expected ON)
DROP INDEX idx_orders_city
```

<!-- expect-error -->
```sql
-- ❌ BAD: expression indexes are not supported (parser error)
CREATE INDEX idx_orders_name_lower ON orders (lower(name))
```

### Listing indexes

`system:indexes` lists the indexes on this device:

```sql
SELECT * FROM system:indexes WHERE collection = :collection
```

Example output for the indexes created above:

```json
{"_id": "orders.idx_orders_status", "collection": "orders", "fields": [{"direction": "asc", "key": ["status"]}]}
{"_id": "orders.idx_orders_status_createdAt", "collection": "orders",
 "fields": [{"direction": "asc", "key": ["status"]}, {"direction": "desc", "key": ["createdAt"]}]}
```

### Where indexes live

- **Indexes persist.** After closing Ditto and reopening the same persistence directory, all indexes are still present and used by the planner.
- **Indexes are local to each device.** `CREATE INDEX` and `DROP INDEX` run on the local SDK. Create the indexes your queries need on every device, as part of startup.
- **`CREATE INDEX` / `DROP INDEX` run only through `execute`.**
- **Indexes speed up `execute` and store observers;** subscriptions and Ditto Server queries do not use them (in our testing, the peer that served a subscription read the whole collection even with an index for the filter; see [Each new subscription makes the data holder read the whole collection](../knowledge/subscriptions-and-replication.md#each-new-subscription-makes-the-data-holder-read-the-whole-collection)), and custom indexes are not supported on the Ditto Server.
- **In-memory stores do not support indexes.** On the Web (Flutter Web and JavaScript Web), where the store is in memory, skip index creation; `CREATE INDEX` fails there with `the database implementation does not support indexing`.

**✅ DO:**
- Create indexes at startup with `CREATE INDEX IF NOT EXISTS`, which is idempotent and needs no extra query.
- Create indexes after `Ditto.open` and before your queries and observers start, so the first queries already benefit.
- Use [ADVISE](#advise-sdk-51) during development to decide which indexes to create.
- Drop indexes that no queries use any more; every index costs write time and storage.

**❌ DON'T:**
- Create indexes on demand right before a query; creation scans the collection.
- Index every field "just in case".
- Index a field with only a few distinct values (a boolean, a status with two or three values) on its own. The planner uses such an index, and it can be slower than no index: in our testing, an index on `status` alone made a query on 100,000 documents about 1.5 times slower than no index, while a composite index on `(store, status)` made it about 5 times faster (see [An index on a field with two values made queries slower](../knowledge/performance-measurements.md#an-index-on-a-field-with-two-values-made-queries-slower)). Put such fields after a selective key in a composite index, and measure the time after adding an index, not only the plan.
- Rely on indexes when [strict mode](data-modeling.md#strict-mode) is enabled (see [Strict mode and data types](#strict-mode-and-data-types)).

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

// ✅ GOOD: Create the indexes this app relies on, once per launch.
Future<void> ensureIndexes(Ditto ditto) async {
  // In-memory stores (Flutter Web) do not support indexes.
  if (kIsWeb) return;

  const statements = [
    'CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt '
        'ON orders (status, createdAt DESC)',
    'CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)',
  ];
  for (final statement in statements) {
    try {
      await ditto.store.execute(statement);
    } catch (error) {
      // Without the index, queries that use it fall back to a collection scan
      // (and a JOIN on it fails): report and continue.
      showError(error);
    }
  }
}
```

### Upgrading and downgrading

SDK 5.1 uses a new on-disk index format and migrates existing indexes automatically the first time an app starts with it. SDK 5.2 keeps that format, so an app can move between 5.1 and 5.2 without migration. Upgrade devices on SDK 5.0.x directly to 5.2.0, not through 5.1.0: on a store that 5.1.0 has migrated, writes to a collection whose index was created while the collection was empty fail with `no such table: ___idx_coll_...`, and in our testing that store stayed broken after a later upgrade to 5.2.0 (see [An index created on an empty collection breaks in the 5.1.0 migration](../knowledge/dql-behavior.md#an-index-created-on-an-empty-collection-breaks-in-the-510-migration)). Dropping that index (`DROP INDEX ... ON ...`) and creating it again fixed it. To downgrade to 5.0 or v4, go through SDK 5.0.2 or later (or 4.14.6 or later), which converts the format back and replaces each composite index with one single-field index per key. See the [indexing documentation](https://docs.ditto.live/dql/indexing#migration), the migration guides, and [Rolling Back](../knowledge/upgrading.md#rolling-back).

## Index Usage Rules

The query planner chooses indexes by rules, not by statistics about your data. `EXPLAIN` shows these plans (11 of the conditions below, tested with SDK 5.1.0 and 5.2.0 on 50,000 documents, produced the listed plans; for example, `status = 'open'` with 5,000 matches took 6 ms through the index, and `LIKE '%001%'` or `lower(status) = 'open'` took 43 to 64 ms as a collection scan):

| Predicate | Plan | Notes |
|---|---|---|
| `status = :status` | Index scan | |
| `status IN :statuses` (array parameter) | Index scan, one span per value | Write `IN :statuses`; `IN (:statuses)` matches nothing (see [Parameters and Literals](dql.md#parameters-and-literals)) |
| `total > 100`, `total >= :min AND total < :max` | Index scan over a range | |
| `name LIKE 'abc%'` | Index scan over a range | Case-sensitive prefix without a leading wildcard; works with a literal or a parameter |
| `starts_with(name, 'abc')` | Collection scan | Use `LIKE 'abc%'` instead |
| `lower(name) = 'abc'`, any function applied to the field | Collection scan | Functions on the value side (for example `= :param`) are fine |
| `status != 'open'`, `NOT (status = 'open')` | Index scan over two ranges | |
| `flag IS MISSING` | Index scan | SDK indexes include documents without the field |
| `coalesce(isDeleted, false) = false` | Collection scan | See [Indexing soft-delete filters](deletion-and-storage.md#indexing-soft-delete-filters) |
| `_id = :id`, `_id IN :ids`, `USE IDS` | ID scan | No index needed |
| `a = 1 OR b = 2` (both indexed) | Union scan | |
| `a = 1 OR b = 2` (`b` not indexed) | **Collection scan** | Every `OR` branch must be indexable |
| `a = 1 AND b = 2` (separate indexes) | Intersect scan | A composite index on `(a, b)` is generally better; in our testing, the intersect scan was slower than the more selective index alone, and its time varied widely with `LIMIT` (see [An index on a field with two values made queries slower](../knowledge/performance-measurements.md#an-index-on-a-field-with-two-values-made-queries-slower)) |
| `address.city = 'Tokyo'` (index on `address.city`) | Index scan | Index the full path you filter on |
| `tags = ['x', 'y']` (index on `tags`) | Index scan | Whole-value match only |
| `array_contains(tags, 'x')`, `:tag IN tags` | Collection scan | Element lookups cannot use an index |
| `SELECT COUNT(*) FROM orders` (no `WHERE`) | Count scan | Does not read documents |

### Composite indexes and key order (SDK 5.1+)

A composite index works like a phone book sorted by last name, then first name: it is efficient when the query fixes the leading fields with equality and then filters or sorts by the next one.

- Put **equality** fields first, then the **range** or **sort** field.
- Match the **sort direction**: with an index on `(status, total DESC)`, `WHERE status = 'open' ORDER BY total DESC` uses the index without a separate sort, while `ORDER BY total ASC` needs an extra sort step.
- Queries that do not constrain the leading field benefit less, and the planner may choose a different index.

```sql
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- ✅ GOOD: equality on the leading key, range and sort on the second key
SELECT * FROM orders
WHERE customerId = :customerId AND createdAt >= :since
ORDER BY createdAt DESC
```

```sql
-- ❌ BAD: the sort direction does not match the index, so an extra sort step is needed
SELECT * FROM orders
WHERE customerId = :customerId
ORDER BY createdAt ASC
```

**Why:** The planner can read a composite index in key order and stop early. When the sort direction or key order does not match, it has to collect all matching documents and sort them, which costs memory and time on large results.

On SDK 5.1.0, this advice applies only to indexes whose keys all have the same direction. With an index that mixes `ASC` and `DESC` keys, such as `(customerId, createdAt DESC)`, 5.1.0 skips the sort but returns the results in the wrong order, and with `LIMIT` it returns the wrong documents. Use `(customerId, createdAt)` on 5.1.0 and accept the extra sort step (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)).

### Covering scans

When a query projects only fields that are in the index (plus `_id`), the planner can answer it from the index without fetching documents. `EXPLAIN` shows `"covering": true` and no `fetch` step:

```sql
-- Answered from idx_orders_status alone
SELECT _id, status FROM orders WHERE status = :status
```

Projecting only the fields a screen needs therefore helps twice: less data is materialized, and some queries avoid document fetches entirely. The second effect is the larger one: in our testing with SDK 5.1.0 and 5.2.0 (5,000 of 50,000 documents of about 1 KB matching), `SELECT _id, status` answered from the index took 16 ms, while adding one field outside the index or using `SELECT *` took 23 to 26 ms; once documents had to be fetched, projecting fewer fields saved almost nothing (see [Counts, index plans, and observer result sizes in numbers](../knowledge/performance-measurements.md#counts-index-plans-and-observer-result-sizes-in-numbers)). (On SDK 5.1.0, an indexed query that projects fields and sorts by one of them can return the rows in the wrong order; see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510).)

### Strict mode and data types

- **Strict mode:** with `DQL_STRICT_MODE` set to `true`, the query planner of SDK 5.1.0 and 5.2.0 does not use secondary indexes: queries that would use an index scan fall back to a collection scan, both for existing indexes and for indexes created while strict mode is enabled. ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions. Keep the default (`false`) if you rely on indexes. See [Strict Mode](data-modeling.md#strict-mode).
- **Mixed CRDT types:** according to Ditto's documentation, only the most recently written CRDT type of a field is indexed, so if the same field is written with different type declarations (for example once as `REGISTER` and once as `MAP`), an index on it can return incorrect or mis-ordered results for queries that request the other type. In our testing, the results were the same with and without the index, because only the query without a declaration used it; what did show is that the same document reads differently depending on the declaration (see [Mixed type declarations change what a query reads, not the index results](../knowledge/dql-behavior.md#mixed-type-declarations-change-what-a-query-reads-not-the-index-results) and [Keep type declarations consistent](data-modeling.md#keep-type-declarations-consistent)). Keep type declarations consistent, and do not index fields that are written with more than one type.

## ADVISE (SDK 5.1+)

Prefix a statement with `ADVISE` to get index recommendations for it. The statement is planned but **not executed**, and no documents are read or written. `ADVISE` is available on Small Peers for `SELECT`, `UPDATE`, `DELETE`, `EVICT`, and `INSERT ... SELECT`.

```sql
ADVISE SELECT * FROM orders WHERE status = :status AND isDeleted = false ORDER BY createdAt DESC
```

This example filters with `isDeleted = false`, which is correct only when every document has the field; otherwise keep the `coalesce` form (see [Indexing soft-delete filters](deletion-and-storage.md#indexing-soft-delete-filters)).

Example output (one row, formatted for readability):

```json
{
  "advice": {
    "statement": "SELECT * FROM orders WHERE status = :status AND isDeleted = false ORDER BY createdAt DESC",
    "suggestedIndexes": [
      {
        "collection": "orders",
        "reason": "equality predicates on `isDeleted`, `status`; order by on `createdAt`",
        "statement": "CREATE INDEX IF NOT EXISTS adv_orders_isDeleted_status_createdAt ON default:`orders` (`isDeleted` ASC, `status` ASC, `createdAt` DESC)"
      }
    ]
  }
}
```

SDK 5.1.0 and 5.2.0 return the same suggestion. On 5.1.0, do not create it as suggested: it mixes `ASC` and `DESC` keys, which returns the results in the wrong order on that release (see [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510)).

When related indexes already exist, they are listed in `existingIndexes`, and the suggestion builds on the query's predicates:

```json
{
  "advice": {
    "existingIndexes": [
      {"collection": "orders", "statement": "CREATE INDEX IF NOT EXISTS ix_cust ON default:`orders` (`cust` ASC)"}
    ],
    "statement": "SELECT * FROM orders WHERE cust = 'c1' AND total > 10",
    "suggestedIndexes": [
      {
        "collection": "orders",
        "reason": "equality predicates on `cust`; range predicates on `total`",
        "statement": "CREATE INDEX IF NOT EXISTS adv_orders_cust_total ON default:`orders` (`cust` ASC, `total` ASC)"
      }
    ]
  }
}
```

The `outcome` field explains when there is nothing to suggest. Values include `optimal indexes already exist`, `no advice available for statement` (for example for `INSERT ... DOCUMENTS` or a query that is already answered by an ID scan), and `no keys to advise on` (for example when every condition applies a function to the field, such as `coalesce(isDeleted, false) = false`).

`ADVISE AND PROVISION` returns the same advice **and creates** the suggested indexes, listing them in `createdIndexes` (and any failures in `failedIndexes`).

**✅ DO:**
- Run `ADVISE` for each important query during development and review the suggestions.
- Copy the suggested `CREATE INDEX IF NOT EXISTS` statements (you may rename them) into your startup code, so every device creates the same indexes.
- Rerun `ADVISE` when you add or change queries.

**❌ DON'T:**
- Run `ADVISE AND PROVISION` from production code paths; it creates indexes as a side effect, and the result depends on whichever queries happen to run.

```dart
// ✅ GOOD (development only): print index suggestions for a query.
Future<void> printIndexAdvice(
  Ditto ditto,
  String query,
  Map<String, dynamic> arguments,
) async {
  final result = await ditto.store.execute('ADVISE $query', arguments: arguments);
  final advice = result.items.first.value['advice'] as Map<String, dynamic>;
  final suggested = (advice['suggestedIndexes'] as List<dynamic>?) ?? const [];
  if (suggested.isEmpty) {
    debugPrint('No suggestions: ${advice['outcome']}');
  }
  for (final index in suggested) {
    final entry = index as Map<String, dynamic>;
    debugPrint('${entry['reason']}\n  ${entry['statement']}');
  }
}
```

## EXPLAIN and PROFILE

`EXPLAIN` and `PROFILE` answer different questions (the table was checked on SDK 5.1.0 and 5.2.0):

| | `EXPLAIN` | `PROFILE` |
|---|---|---|
| Executes the statement | ❌ (parse and plan only) | ✅ |
| Returns | The query plan | The normal results, followed by one extra profile row |
| Use it to | Check which access path and indexes are used | Measure where time is spent and how many documents flow through each step |
| Statements | `SELECT`, mutations (SDK 5.1+), `CREATE INDEX` / `DROP INDEX`, and `ADVISE` (not `SHOW` or `ALTER SYSTEM`) | `SELECT` and mutations (`INSERT`, `UPDATE`, `DELETE`, `EVICT`) get a profile row; mutations are executed. `PROFILE SHOW` returns only the `SHOW` result |

**❌ DON'T:**

- Use `EXPLAIN` to measure performance; it never runs the query. Use `PROFILE`.

### Reading an EXPLAIN plan

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'open'
```

Example output (formatted):

```json
{"plan": {"#operator": "sequence", "children": [
  {"#operator": "indexScan", "collection": "orders", "desc": {"index": "idx_orders_status",
    "spans": [[{"index_key": {"direction": "asc", "include_missing": true, "key": ["status"]},
                "range": {"low": {"expr": "\"open\"", "included": true}, "high": {"expr": "\"open\"", "included": true}}}]]}},
  {"#operator": "fetch", "collection": "orders"},
  {"#operator": "filter", "condition": "(`orders`.`status` = \"open\")"},
  {"#operator": "finalProjection"}
]}}
```

Read the plan from top to bottom, in the order data flows. The operators you will see most often:

| Operator | Meaning |
|---|---|
| `scan` | Collection scan: every document is read. Expected for small collections, a warning sign for large ones |
| `indexScan` | Reads an index; `desc.index` names it, `spans` show the ranges, `covering: true` means the filter can be evaluated from the index (if no `fetch` step follows, the whole query is answered from the index) |
| `idScan` | Direct lookup by `_id` |
| `unionScan` / `intersectScan` | Combines several index scans for `OR` / `AND` |
| `countScan` | Answers `COUNT(*)` without reading documents |
| `fetch` | Loads the documents found by a scan |
| `filter` | Applies the full `WHERE` condition (always reapplied after an index scan) |
| `sort` / `limit` / `projection` | Ordering, row limit, and the `SELECT` list |
| `nlJoin` | Nested-loop JOIN (SDK 5.1+) |

### Measuring with PROFILE

`PROFILE` runs the statement and appends a row with the key `~request_profile` after the normal results (for mutations without `RETURNING`, the profile row is the only row). Each operator in its `plan` carries `#stats` with `documentsIn`, `documentsOut`, and `phaseTimes`; `times` holds the overall `elapsed`, `parse`, and `plan` times (in nanoseconds).

```sql
PROFILE SELECT * FROM orders WHERE total = 5
```

Example profile row (abridged):

```json
{"~request_profile": {
  "plan": {"#operator": "sequence", "children": [
    {"#operator": "indexScan", "#stats": {"documentsOut": 1, "phaseTimes": {"exec": 21226, "recv": 41893, "send": 167}},
     "desc": {"index": "adv_orders_total"}},
    {"#operator": "fetch", "#stats": {"documentsIn": 1, "documentsOut": 1, "phaseTimes": {"exec": 1792, "recv": 61036, "send": 2976, "stor": 31309}}},
    {"#operator": "filter", "#stats": {"documentsIn": 1, "documentsOut": 1, "phaseTimes": {"exec": 1500, "send": 1268}}},
    {"#operator": "finalProjection", "#stats": {"documentsIn": 1, "documentsOut": 1}}
  ]},
  "queryType": "select", "resultCount": 1, "state": "completed",
  "times": {"elapsed": 196690, "parse": 9583, "plan": 31935}
}}
```

What to look for:

- A `filter` whose `documentsIn` is much larger than its `documentsOut`: many documents are read and then discarded. An index on the filtered field usually helps.
- A `scan` or `fetch` with a high document count on a large collection.
- `sort` or grouping steps on large inputs: they must collect all input before producing output, which costs memory.

```dart
import 'dart:convert';

// ✅ GOOD (development only): separate the profile row from the results.
Future<void> profileQuery(
  Ditto ditto,
  String query,
  Map<String, dynamic> arguments,
) async {
  final result = await ditto.store.execute('PROFILE $query', arguments: arguments);
  final rows = result.items.map((item) => item.value).toList();
  final profile = rows.lastWhere(
    (row) => row.containsKey('~request_profile'),
    orElse: () => const {},
  )['~request_profile'] as Map<String, dynamic>?;
  final resultCount = rows.length - (profile == null ? 0 : 1);
  debugPrint('rows=$resultCount times=${profile?['times']}');
  debugPrint(const JsonEncoder.withIndent('  ').convert(profile?['plan']));
}
```

### Directives

Directives let you override the planner for a single statement. Use them only after `EXPLAIN` and `PROFILE` have shown that the planner's choice is wrong for your data:

```sql
-- Force a specific index (silently ignored if the index does not exist or cannot serve the query)
SELECT * FROM orders USE INDEX 'idx_orders_customerId' WHERE customerId = :customerId
```

- `USE INDEX ''` explicitly requests a collection scan (also used to allow a JOIN without an index on the inner collection).
- Comment-style directives (`/*+ {...} */`) and `USE DIRECTIVES` give finer control. Place them after `SELECT` or after the collection name; a directive comment after `WHERE` is ignored.
- The system parameter `DQL_DEFAULT_DIRECTIVES` sets default directives for every statement.
- Do not put directives in subscription queries; indexes and directives only affect local query execution.

See the [DQL directives documentation](https://docs.ditto.live/dql/directives) for the available directives.

## Query Scope and Execution

Indexes are only part of query performance. How much data a query touches and how often it runs matter just as much.

**✅ DO:**
- **Filter narrowly.** Put every condition you can into `WHERE` instead of filtering in Dart after the query.
- **Project only what you need.** `SELECT _id, status, total` materializes less data than `SELECT *` and can enable covering scans. (Subscriptions are different: they always sync whole documents and only accept `SELECT *`; see [Subscription Rules](sync-and-subscriptions.md#subscription-rules).)
- **Use `LIMIT` for local queries** that only need the first rows (for example the latest 50 orders), together with `ORDER BY`.
- **Keep query strings constant and pass values as parameters.** A string built for every value is unsafe (see [Parameters and Literals](dql.md#parameters-and-literals)). It was not measurably slower in our testing (see [Constant query strings were not faster](../knowledge/performance-measurements.md#constant-query-strings-were-not-faster)), so the reason is safety, not speed.
- **Keep observer result sets small.** A store observer re-runs its query and delivers the full result set whenever relevant data changes. In our testing, an observer of 5,000 documents was called about six times later after a write than one limited to 50 rows, and an observer that returned 200 documents while other devices kept updating them grew the process's memory on every callback, steadily for 10 minutes, until it was cancelled (see [Counts, index plans, and observer result sizes in numbers](../knowledge/performance-measurements.md#counts-index-plans-and-observer-result-sizes-in-numbers) and [An observer of 200 documents grows memory on every callback](../knowledge/performance-measurements.md#an-observer-of-200-documents-grows-memory-on-every-callback)). On devices that run for hours, observe only the rows on screen and cancel observers of screens that are not visible. Prefer several focused observers with `WHERE` and `LIMIT` over one observer of a whole collection (see [Store Observers in Flutter](observers.md#store-observers-in-flutter)). Since SDK 5.2, an observer no longer re-runs its query after writes to collections it does not observe, and observers hold less memory between updates, so splitting observers by collection costs less than before.

**❌ DON'T:**
- Observe an entire large collection and filter or paginate in Dart.
- Run queries in a tight loop when one query with `IN :ids` can return the same data. Each `execute` call has a fixed cost: in our testing, reading 500 of 20,000 documents took 841 ms as 500 `_id = :id` queries and 14 ms as one `_id IN :ids` query (see [The number of execute calls matters more than the number of documents](../knowledge/performance-measurements.md#the-number-of-execute-calls-matters-more-than-the-number-of-documents)).

```dart
// ❌ BAD: one query per ID
Future<List<Map<String, dynamic>>> loadOrdersOneByOne(
  Ditto ditto,
  List<String> ids,
) async {
  final orders = <Map<String, dynamic>>[];
  for (final id in ids) {
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': id},
    );
    orders.addAll(result.items.map((item) => item.value));
  }
  return orders;
}

// ✅ GOOD: one query, planned as an ID scan
Future<List<Map<String, dynamic>>> loadOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

### Counting documents

A full-collection `COUNT(*)` is answered by a dedicated count scan (SDK 5.1+) without reading documents, so it is cheap enough for badges and dashboard totals. Ditto's 5.1 benchmark reported a full-collection `COUNT(*)` going from 149.03 ms to 0.89 ms (about 167x faster), and a filtered count improving from 60.85 ms to 13.89 ms (about 4.4x). These figures compare median runtimes of SDK 5.0.3 and 5.1.0 on a single Android device (Orion O6) with one retail dataset of about 93,000 documents. Our own measurements on a Mac point the same way (see [Counts, index plans, and observer result sizes in numbers](../knowledge/performance-measurements.md#counts-index-plans-and-observer-result-sizes-in-numbers)). Performance depends on the device, data shape, indexes, and query mix, so test representative workloads on your target hardware.

A filtered `COUNT(*)` still has to evaluate the filter, so index the filtered fields. To check whether any matching document exists, `SELECT _id ... LIMIT 1` remains the simplest query.

### Long-running requests (SDK 5.1+)

Two system parameters help you detect and contain slow DQL requests:

| Parameter | Default | Effect |
|---|---|---|
| `DQL_SLOW_REQUEST_WARN_SECONDS` | `60` | Logs a warning with the request details (the same information as `system:active_requests`) once a request has run this long, and repeats it at the same interval. `0` disables the warning |
| `DQL_REQUEST_TIMEOUT_SECONDS` | `0` (disabled) | Cancels requests that run longer than this and fails them with a timeout error. Cancellation is cooperative, so execution can continue briefly past the limit |

```sql
ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10

ALTER SYSTEM SET DQL_REQUEST_TIMEOUT_SECONDS = 30
```

The warning reads `Slow DQL request dump entry="{...}"` and includes the plan and its statistics as JSON; the timeout fails the request with `Request exceeded maximum permitted execution time.` (in our testing; see [Slow-request warnings and timeouts work, and 5.2.0 needs an explicit history threshold](../knowledge/configuration-and-diagnostics.md#slow-request-warnings-and-timeouts-work-and-520-needs-an-explicit-history-threshold)). A lower warning threshold during development surfaces slow queries early. Apply these settings after every open (see [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters)). Before enabling a timeout in production, make sure your code handles the resulting error for every query.

### Flutter execution model

On native platforms, `ditto.store.execute` runs the query on a long-lived worker isolate (one per `Ditto` instance), so a slow query does not block the UI isolate.

> **Advanced:** `Store.experimentalSkipExecuteIsolateOffload` (Experimental, default `false`) runs `execute` inline on the calling isolate instead. It avoids the per-call dispatch cost for tight loops of very small queries, but any slow query then blocks the calling isolate (usually the UI). The setting applies to every `Store` in the current isolate, persists across `Ditto.open` and `close` for the lifetime of the isolate, does not propagate to isolates you spawn, and has no effect on Web. Avoid toggling it while `execute` calls are in flight. Use it only after measuring a real throughput problem.

```dart
// Advanced (Experimental): only when queries are known to be short and
// throughput of many small queries matters more than UI responsiveness.
void enableInlineExecute() {
  Store.experimentalSkipExecuteIsolateOffload = true;
}
```
