# DQL Reference for Queries and Writes (SDK 5.2)

Detailed rules behind the patterns in [SKILL.md](../SKILL.md). Extracted from the guide sections `§ DQL Fundamentals`, `§ Reading Data with SELECT`, and `§ Writing Data`.

## Table of Contents

- [Statements](#statements)
- [Parameters](#parameters)
- [Literals and Identifiers](#literals-and-identifiers)
- [MISSING and NULL](#missing-and-null)
- [Membership and USE IDS](#membership-and-use-ids)
- [Projections, DISTINCT, and Aggregates](#projections-distinct-and-aggregates)
- [GROUP BY and HAVING](#group-by-and-having)
- [ORDER BY, LIMIT, and OFFSET](#order-by-limit-and-offset)
- [JOIN (SDK 5.1+)](#join-sdk-51)
- [INSERT and ON ID CONFLICT](#insert-and-on-id-conflict)
- [UPDATE](#update)
- [RETURNING (SDK 5.1+)](#returning-sdk-51)
- [DELETE and EVICT](#delete-and-evict)

---

## Statements

| Statement | Purpose |
|---|---|
| `SELECT` | Read documents: projections, aggregates, `GROUP BY`, `ORDER BY`, `LIMIT`, `JOIN` (SDK 5.1+) |
| `INSERT` | Create documents, upsert with `ON ID CONFLICT`, seed defaults with `INITIAL DOCUMENTS` |
| `UPDATE` | Change fields with `SET` / `UNSET`, counters with `APPLY` |
| `DELETE` / `EVICT` | Delete everywhere (tombstone) / remove from this device only |
| `CREATE INDEX` / `DROP INDEX`, `EXPLAIN`, `PROFILE`; `ADVISE` (SDK 5.1+) | Indexing and diagnostics |
| `ALTER SYSTEM` / `SHOW` | Runtime system parameters |

There is no statement to create or drop a collection: a collection exists as soon as a document is written to it.

## Parameters

- Placeholders are `:name`; values go in the arguments map. Names are case-sensitive, and a placeholder without an argument fails with `Parameter <name> was not provided`. Argument names have no colon (`{':id': ...}` leaves `:id` without a value); unused arguments are ignored; `$id` is a syntax error.
- `LIMIT` and `OFFSET` accept parameters.
- Pass whole documents as one parameter: `DOCUMENTS (:order)`, or several: `DOCUMENTS (:first), (:second)`, or an array parameter for many documents.
- Parameters keep their exact value and type (an `int` stays an integer). Inline strings interpret backslash escapes, and inside a string literal of Dart, JavaScript, Kotlin, or Swift they are interpreted twice (the language, then DQL).

## Literals and Identifiers

| Literal | Syntax | Notes |
|---|---|---|
| String | `'open'` or `"open"` | Both quote styles delimit strings; double quotes never refer to a field |
| Escapes | `'it\'s'`, `'line1\nline2'` | JSON escapes in both quote styles; `'it''s'` is a syntax error; a literal backslash is `\\`. Changed in 5.1.0: on 5.0.x, `''` escaped a quote and backslashes were literal |
| Identifier | `` `my field` `` | Backticks quote names with special characters or reserved words. Names are case-sensitive: `Orders` and `orders` are different collections |
| Number | `42`, `2.5`, `1e3`, `0xFF` | `5 / 2` is `2`; `5.0 / 2` is `2.5`; `1 / 0` and `1 % 0` are MISSING, not an error |
| Boolean / null | `true`, `FALSE`, `null` | Case-insensitive |
| Object | `{'status': 'open'}` | Every key quoted; unquoted keys fail in `INSERT` (`Cannot convert to a literal`) and are evaluated as field references in `SELECT` (usually `{}`). Prefer passing documents as parameters |

```sql
SELECT 'it\'s' AS a, "double quoted" AS b, `my field` AS c, 0xFF AS d
FROM orders
```

- Ditto's DQL reference reserves keywords such as `COLLECTION`, `ORDER`, `SELECT`, `VALUE`, and `ALL` and says to quote identifiers equal to them. The SDKs enforce it only for some: `SELECT * FROM collection` is a parser error, while `order`, `select`, `from`, `where`, `value`, and `all` worked as bare collection and field names in our testing with SDK 5.1.0 and 5.2.0. Follow the documented rule. A bare `true`, `false`, or `null` is always the literal value, never a field. Choose non-reserved names, or quote with backticks.
- Comments: `-- line` and `/* block */`. Comments starting with `/*+` or `--+` are query directives.

## MISSING and NULL

Which documents each expression matches when `isDeleted` holds `true`, `false`, `null`, or is missing:

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

Related behavior:
- In projections, an expression that evaluates to MISSING is omitted from the row; `null` appears as `null`.
- Comparing values of different types, including with `=` and `!=` (`1 = 'a'`, `1 != 'a'`, `1 < 'a'`), evaluates to MISSING. Integers and floats compare normally (`1 = 1.0` is `true`).
- Aggregates over zero rows return MISSING (except `COUNT(*)` and `COUNT(expr)`, which return `0`).
- `UNSET field` makes a field missing; writing `null` keeps it present.

## Membership and USE IDS

| Goal | Expression | Notes |
|---|---|---|
| One of several values | `status IN :statuses` | ✅ Array parameter; can use an index |
| None of several values | `status NOT IN :statuses` | Documents where `status` is missing are not returned |
| Literal list | `status IN ('open', 'pending')` | ✅ |
| Array field contains a value | `:tag IN tags` / `array_contains(tags, :tag)` | ✅ No index |
| Array parameter in parentheses | `status IN (:statuses)` | ❌ Matches nothing |
| A single value instead of an array | `status IN :statuses` with `'open'` | ❌ Matches nothing, without an error (an empty array also returns no rows) |
| Equality with an array parameter | `status = :statuses` | ❌ Compares with the whole array |

> **Note (SDK 5.1.0 and 5.2.0):** `ANY ... SATISFIES ... END` in a `WHERE` clause that iterates over a parameter or literal array returns no rows. Use `status IN :statuses` (or `array_contains(:statuses, status)`). The bug (new in 5.1.0, not fixed in 5.2.0) affects local queries and observers; a subscription with the same predicate syncs correctly. `ANY` and `EVERY` over a document's own array field work in `WHERE`; on SDK 5.1.0, only when the condition checks a single property (a condition on several properties of an element matches every document; see `§ Known Issues in SDK 5.1.0`).

| `USE IDS` form | Behavior |
|---|---|
| `USE IDS 'a', 'b'` | ✅ Literal IDs, no parentheses |
| `USE IDS LIST :ids` | ✅ Array parameter |
| IDs wrapped in parentheses | ❌ Error |
| `USE IDS :ids` with an array | ❌ Treats the array as one ID; returns nothing, or fails with `SerializedFormOverLimit` above 256 bytes |

```sql
SELECT * FROM orders USE IDS 'order-1', 'order-2'

SELECT * FROM orders USE IDS LIST :ids
```

`WHERE _id = :id` and `WHERE _id IN :ids` are also planned as direct ID lookups and are the simplest choice. For `DELETE` and `EVICT`, prefer the `WHERE` form as long as any device runs SDK 5.1.0, where `USE IDS` without a `WHERE` predicate removes nothing.

## Projections, DISTINCT, and Aggregates

| Projection | Example |
|---|---|
| Fields | `SELECT _id, status FROM orders` |
| Expression with alias | `SELECT _id, total * 1.1 AS gross FROM orders` |
| All fields plus expressions | `SELECT orders.*, total * 1.1 AS gross FROM orders` (qualify `*`) |
| All fields except some | `SELECT orders.*, MISSING notes FROM orders` |

- Without `AS`, a computed column is named after its position in the projection list, such as `($2)` for the second element.
- An unqualified `*` with other projections fails (`unqualified * with other projection elements is not supported`).
- Projections shape the local result only; subscriptions always sync whole documents.
- `DISTINCT` keeps every distinct row in memory: use it on a few low-cardinality fields, never with `_id` or `*`.

| Aggregate | Result |
|---|---|
| `COUNT(*)` | Number of rows (`0` for no rows) |
| `COUNT(expr)` | Rows where `expr` is not `null`, missing, or `false` (`0` for no rows) |
| `COUNT(DISTINCT expr)` | Distinct values of `expr`, with the same exclusions (`0` for no rows) |
| `SUM` / `AVG` | Numeric values only; MISSING for no rows |
| `MIN` / `MAX` | By Ditto's type order; MISSING for no rows |
| `MEDIAN(expr)` | Positional median; MISSING for no rows |
| `MID(expr)` | `(MIN + MAX) / 2`, not the median; MISSING for no rows |

- Default empty aggregates: `ifmissing(SUM(total), 0)`.
- Count present values of a boolean field with `COUNT(field IS NOT MISSING)`.
- Aggregates process every matching document before returning: keep `WHERE` selective, especially in observers that fire often.

## GROUP BY and HAVING

- Every non-aggregate projection must be a `GROUP BY` key. Give computed expressions an alias with `AS`.
- `GROUP BY` and `HAVING` cannot reference projection aliases; repeat the expression. `ORDER BY` can use aliases.

<!-- expect-error -->
```sql
-- ❌ BAD: GROUP BY uses the alias "day"
SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue
FROM orders
GROUP BY day
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

## ORDER BY, LIMIT, and OFFSET

- No `ORDER BY` means no guaranteed order (observers included). Default direction is `ASC`.
- Ascending type order: `false` < `true` < numbers < binary < strings < arrays < objects < `null` < missing. `DESC` reverses it, so missing values come first, then `null`: `ORDER BY createdAt DESC` lists documents without `createdAt` at the top.
- Strings compare by Unicode code point: `'B'` before `'a'`, `'é'` after `'z'`, `'10'` before `'9'`; `LIKE` is case-sensitive (`ILIKE` is not). Sort display names in the app with the user's locale, or on `lower(name)` for small results.
- `ORDER BY status = 'urgent'` puts matching documents last in ascending order; use `DESC` or a `CASE` expression.
- Add a unique tie-breaker: `ORDER BY createdAt DESC, _id`. Store sortable values in one consistent type.
- Combine `LIMIT`/`OFFSET` with `ORDER BY`. Prefer keyset pagination over large offsets, with an `_id` tie-breaker in the `WHERE` clause (`createdAt < :after OR (createdAt = :after AND _id < :afterId)`).
- `LIMIT` and `ORDER BY` are not allowed in subscriptions by default.

```sql
-- Urgent tasks first, then by due date
SELECT * FROM tasks
WHERE coalesce(isDeleted, false) = false
ORDER BY CASE WHEN priority = 'urgent' THEN 0 ELSE 1 END, dueAt, _id
```

## JOIN (SDK 5.1+)

| Join | Rows returned | Unmatched side |
|---|---|---|
| `JOIN` / `INNER JOIN` | Pairs that satisfy `ON` | Dropped |
| `LEFT [OUTER] JOIN` | Every left row | Right-side fields MISSING |
| `RIGHT [OUTER] JOIN` | Every right row; first join only | Left-side fields MISSING |

`FULL OUTER JOIN`, `CROSS JOIN`, comma joins, and joins in `UPDATE` / `DELETE` are not supported. The `ON` clause may use `AND` / `OR` and filters on one side.

**Index requirement**: joins run as nested loops; the inner collection's lookup must use an index or `_id`. Otherwise: `Joining to "c" disallowed without appropriate index support. Please run ADVISE for recommendations.`

```sql
CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)
```

```sql
-- Every customer with their open orders; customers without orders are kept
SELECT c.name, o._id AS orderId, o.total
FROM customers c
LEFT JOIN orders o ON o.customerId = c._id AND o.status = 'open'
ORDER BY c.name, o.total
```

```sql
-- Explicitly accept a scan of a small lookup collection (other join terms still need an index)
SELECT o._id, r.label
FROM orders o
JOIN regions r USE INDEX '' ON r.code = o.regionCode
```

| Projection | Result row |
|---|---|
| `SELECT *` | One nested object per alias: `{"c": {...}, "o": {...}}` |
| `SELECT c.*, o.total` | Flat: all customer fields plus `total` |
| `SELECT _id` | Composite ID per row: `{"c": "c1", "o": "o1"}` |
| Unqualified field present on both sides | Error: `Ambiguous reference to field: name` |

Restrictions:
- Local data only: every joined collection needs its own subscription.
- Rejected by `registerSubscription` (`Unsupported feature: Joining`); not supported on Ditto Server.
- A later `RIGHT JOIN` fails; a `RIGHT JOIN` is rewritten as a `LEFT JOIN` with sides swapped, so the left collection becomes the inner side and needs the index.
- At most 10 joins per statement by default (directive `#max_joins`).
- Observers accept joins and deliver a new result when a change in any joined collection changes the joined rows; on 5.1.0 rows carried a composite `_id`, but on 5.2.0 they did not in testing, so project the row keys yourself (`o._id AS orderId`) when you diff.

Embedding remains the default modeling choice; see `§ Relationships: Embedding, Separate Collections, and JOIN`.

## INSERT and ON ID CONFLICT

| Policy | When the `_id` already exists locally |
|---|---|
| `FAIL` (default) | Fails: `Identifier conflict on document "...": using FAIL conflict policy` |
| `DO NOTHING` | Existing document unchanged; no error |
| `DO UPDATE` | Supplied fields written (merged, nested objects merged) even if identical; mutation recorded, observers can fire again, and a rewritten value wins over an earlier concurrent edit on another device |
| `DO UPDATE_LOCAL_DIFF` | Same merge, only differing fields written; nothing written if nothing changed (for upserts and re-imports; it does not protect a stale in-memory copy) |

- A multi-document insert is atomic. Two documents with the same `_id` in one statement fail with `Expected unique document identifiers`.
- No `INSERT` policy removes fields; use `UNSET`.
- Do not upsert a document that contains a `COUNTER` field: the value restarts the counter and discards increments not yet received, also with `DO UPDATE_LOCAL_DIFF` (`§ Writing documents that contain counters`).
- `INSERT INTO c INITIAL DOCUMENTS (:doc)` inserts only if no document with that `_id` exists locally (no error otherwise). It cannot be combined with `ON ID CONFLICT`. It does not keep data off the network; subscriptions decide that. Use it to create a document with a counter on each device.
- `INSERT ... SELECT` (SDK 5.1+): each result row becomes a document; projection aliases become field names; a projected `_id` is used as the document ID. Do not wrap the `SELECT` in parentheses or `DOCUMENTS (...)`. Declare `COUNTER` and `ATTACHMENT` fields on both sides (`INSERT INTO COLLECTION archive (n COUNTER, file ATTACHMENT) SELECT * FROM COLLECTION src (n COUNTER, file ATTACHMENT)`); otherwise counters are copied as plain numbers and attachments as maps that cannot be fetched (SDK 5.1.0 and 5.2.0).
- Long ID lists: `WHERE _id IN :ids` re-checks each found document against the list, so 10,000 IDs took about 0.7 s against 17 to 65 ms with `USE IDS LIST :ids` (SDK 5.1.0 and 5.2.0, in testing). Above about 1,000 IDs, read or `UPDATE` with `USE IDS LIST :ids`, or split into chunks of 1,000; for `DELETE` and `EVICT` while devices run 5.1.0, split `IN :ids` (`§ USE IDS`).
- Integers and floats are equal in `WHERE` but separate values in `GROUP BY` and `DISTINCT` (`1` and `1.0` formed two groups in testing); keep one numeric type per field or group by `cast(n AS float)`.
- Rows with equal sort keys came back in ascending `_id` order on 5.1+ (also with `DESC`), which is not documented; SDK 5.0 used another order without an index. Always add a tie-breaker, with the same direction as the sort key if ties should reverse.
- Collections cannot be dropped, and on 5.1+ the first write to a new collection slowed down as collections accumulated (about 20 ms with 1,000) while each took 15 to 17 KB of disk; partition one collection by `_id` or a field instead of creating one per user, tenant, or day (`§ DQL Fundamentals`).
- Pass alternatives as `IN :values`, not as `OR` chains built in code: a condition wrapping each term in another pair of parentheses failed at 100 levels (`DQL parser error: recursion limit exceeded`), and long `OR` chains crashed 5.1.0.

```sql
-- Copy closed orders into an archive collection; safe to re-run
INSERT INTO archivedOrders
SELECT * FROM orders WHERE status = 'closed'
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

## UPDATE

```text
UPDATE collection [USE IDS ...]
[APPLY counterField INCREMENT BY n, ...]
[SET field = value, nested.path = value, ...]
[UNSET field, nested.path, ...]
[WHERE condition]
[RETURNING projection]
```

- At least one of `APPLY`, `SET`, `UNSET`, in this order: `APPLY` before `SET`, and `UNSET` after `SET`. Without `WHERE`, every document in the collection is updated, without a warning. Counters: see `§ Counters`.
- Missing intermediate objects in nested `SET` paths are created. If `a` holds a string, number, array, or `null`, `SET a.b = 1` replaces it with `{"b": 1}` without an error (in our testing with SDK 5.1.0 and 5.2.0).
- Errors: `SET _id = ...` (``The document id `_id` cannot be modified``); the same path twice (`More than one modification specified for the path ...`); `SET items[0] = ...` (syntax error; replace the array or use a map keyed by ID).
- An `UPDATE` that writes the current value is still a mutation: it appears in `mutatedDocumentIDs()` and can wake observers. Skip unchanged documents in `WHERE` (`coalesce(status, :none) != :status`).

With the default `DQL_STRICT_MODE = false`, objects are CRDT maps and assignments merge:

| Starting `address` | Statement | Result |
|---|---|---|
| `{"city": "Oslo", "zip": "0150"}` | `SET address = :a` with `{"country": "NO"}` | `{"city": "Oslo", "zip": "0150", "country": "NO"}` |
| `{"city": "Oslo", "zip": "0150"}` | `SET address = {}` | Unchanged (the document is still reported as mutated) |
| `{"city": "Oslo", "zip": "0150"}` | `UNSET address.zip` | `{"city": "Oslo"}` |
| `{"city": "Oslo", "zip": "0150"}` | `UNSET address`, then `SET address = :a` with `{"city": "Bergen"}`, as two `tx.execute` calls in one transaction | `{"city": "Bergen"}` |

With `UNSET` and `SET`, the field is still a map, so a nested edit that another device made at the same time can merge into the new object. Only a `REGISTER` declaration guarantees that concurrent edits never mix two versions; see `§ Strict Mode`.

## RETURNING (SDK 5.1+)

Use `RETURNING` instead of "write, then query again", and to capture deleted content (`DELETE ... RETURNING *`). Example: `UPDATE orders SET status = :status WHERE _id IN :ids AND status = :expected RETURNING _id, status`; more in [dql-writes.sql](../examples/dql-writes.sql).

| Statement | Rows in `items` |
|---|---|
| `INSERT ... RETURNING` | Documents written (not those skipped by `DO NOTHING` or left unchanged by `DO UPDATE_LOCAL_DIFF`) |
| `UPDATE ... RETURNING` | Documents after the update |
| `DELETE ... RETURNING` / `EVICT ... RETURNING` | Documents before removal |

- Same projection syntax as `SELECT`, including aliases, expressions, and aggregates over all affected documents.
- `commitID` is populated as usual, and so is `mutatedDocumentIDs()`. Treat `items` as the result: include `_id` in the `RETURNING` projection when you need the IDs, rather than making that code depend on `mutatedDocumentIDs()`.

```sql
DELETE FROM sessions WHERE expiresAt < :now RETURNING COUNT(*) AS removed
```

## DELETE and EVICT

| Statement | Effect |
|---|---|
| `DELETE FROM c WHERE ...` | Deletes on all peers; leaves a tombstone that syncs the deletion |
| `EVICT FROM c WHERE ...` | Removes from this device only; can sync back while a matching subscription is active |

To select documents by ID, use `WHERE _id = :id` or `WHERE _id IN :ids`; it is planned as an ID lookup and works on every release. On SDK 5.1.0, `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) completes without an error but removes nothing (`§ Known Issues in SDK 5.1.0`).

**❌ DON'T** build the `WHERE` clause of a `DELETE`, `EVICT`, or `UPDATE` from optional filters in a way that can leave it empty: without `WHERE`, the statement changes every document in the collection, and nothing warns. Write one fixed statement per case.

Choosing between them, soft delete, and tombstones: `§ Deletion and Storage Management`.
