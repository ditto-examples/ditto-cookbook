# Query Optimization (SDK 5.2)

How to keep local queries and observers fast. Extracted from the guide sections `§ Working with Query Results`, `§ Reading Data with SELECT`, and `§ Indexing and Query Performance`. Index creation, `ADVISE`, `EXPLAIN`, and `PROFILE` are covered in the performance-observability skill.

## Table of Contents

- [Query Results](#query-results)
- [Query Scope](#query-scope)
- [Pagination](#pagination)
- [Counting and Existence](#counting-and-existence)
- [Batching Instead of N+1](#batching-instead-of-n1)
- [Writing Index-Friendly Predicates](#writing-index-friendly-predicates)
- [Composite Indexes and Covering Scans](#composite-indexes-and-covering-scans)
- [JOIN Performance](#join-performance)
- [Observers](#observers)
- [Checklist](#checklist)

---

## Query Results

| Part | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Rows | `items` (an `Iterable`; each pass creates new wrappers) | `items` (an array; the same objects every time) | `items` (a `List`) | `items` (an array) |
| Row value | `item.value` (decoded on first access, cached on the item) | `item.value` (the same object every time) | `item.value` | `item.value` |
| JSON / CBOR | `item.jsonString`, `item.cborBytes` (properties) | `item.jsonString()`, `item.cborData()` | `item.jsonString()`, `item.cborData()` | `item.jsonData()`, `item.cborData()` |
| Mutated IDs | `mutatedDocumentIDs()` (a new list per call) | `mutatedDocumentIDsV2()` | `mutatedDocumentIds()` | `mutatedDocumentIDs()` |
| Commit ID | `commitID` | `commitID` | `commitId` | `commitID` |
| Release | Garbage collection | Garbage collection | `close()`, or read inside the mapping function of `execute` | Automatic reference counting |
| Decimal numbers | A `double`, and integers an `int`: read numbers as `num` | A `number` (`10.0` is stored as an integer) | A decimal that a 32-bit float holds exactly, such as `7.5`, is a `FloatValue`: `doubleOrNull` returns `null` | Such a value is a `Float`: `as? Double` returns `nil`; read `as? NSNumber` |

- The commit ID is empty for reads and, inside a transaction, until it commits. A write that changed nothing (no mutated IDs) still gets one, which peers confirm only with their next sync exchange (up to about 27 s; SDK 5.1.0 and 5.2.0): track it only when something changed. With `RETURNING`, treat `items` as the result and project `_id` when you need the IDs.
- Read the rows once and convert them to plain values or model objects right away; project only the fields you need.
- Do not store result or row objects in state, caches, or across observer callbacks: they reference native memory.
- See `§ Working with Query Results` and `query-result-handling` in `../examples/<sdk>/`; the SDK pages' *Query results in <SDK>* sections show each SDK's model mapping.

## Query Scope

**✅ DO**:
- **Filter narrowly** in `WHERE` instead of filtering in app code.
- **Project** only the fields you need (`SELECT _id, title, status ...`). This reduces decoding and memory and can enable covering scans. Subscriptions still sync whole documents.
- **Keep statement text constant** and pass values as parameters, so the prepared plan is reused from the statement cache.
- **Materialize once**: convert rows to plain values or models in one pass and let the result go.

**❌ DON'T**:
- Load a whole collection and filter, sort, or paginate in app code.
- Use `DISTINCT` with `_id` or `*`.

## Pagination

Always combine `LIMIT` with `ORDER BY`. Keyset pagination avoids re-reading skipped rows:

```sql
-- ✅ GOOD: Keyset pagination with a parameterized page size.
-- _id breaks ties between rows that share the same createdAt.
-- Load the first page with the same query without the WHERE clause.
-- Arguments: {"after": "2026-10-08T10:30:00.123Z", "afterId": "task-42", "pageSize": 50}
SELECT _id, title, createdAt FROM tasks
WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId)
ORDER BY createdAt DESC, _id DESC LIMIT :pageSize
```

`LIMIT :pageSize OFFSET :offset` works, but every page re-reads and skips all earlier rows. Use a unique sort key or add a tie-breaker (`ORDER BY createdAt DESC, _id`) so pages are well defined.

## Counting and Existence

- Count with `SELECT COUNT(*) ...`, not by loading documents and counting them.
- A full-collection `COUNT(*)` is answered by a dedicated count scan (SDK 5.1+) without reading documents. A filtered `COUNT(*)` still evaluates the filter, so index the filtered fields (in testing with SDK 5.1.0 and 5.2.0 on 20,000 documents: 1.8 ms for the full count, 20 to 28 ms filtered without an index, 6 ms with one).
- Check existence with `SELECT _id ... LIMIT 1`.

```sql
SELECT COUNT(*) AS n FROM orders WHERE status = :status

SELECT _id FROM orders WHERE status = :status LIMIT 1
```

## Batching Instead of N+1

```sql
-- ✅ GOOD: One query, planned as an ID scan
-- Arguments: {"ids": ["order-1", "order-2"]}
SELECT * FROM orders WHERE _id IN :ids
```

Running one `SELECT ... WHERE _id = :id` per ID in a loop does the same work many times.

## Writing Index-Friendly Predicates

The planner chooses indexes by rules, not data statistics. `EXPLAIN` shows these plans:

| Predicate | Plan |
|---|---|
| `status = :status`, `status IN :statuses` | Index scan |
| `total >= :min AND total < :max` | Index range scan |
| `name LIKE 'abc%'` (case-sensitive prefix without a leading wildcard; literal or parameter) | Index range scan |
| `starts_with(name, 'abc')` | Collection scan: use `LIKE 'abc%'` |
| Any function applied to the field (`lower(name) = 'abc'`) | Collection scan (functions on the value side are fine) |
| `status != 'open'` | Index scan over two ranges |
| `flag IS MISSING` | Index scan |
| `coalesce(isDeleted, false) = false` | Collection scan |
| `_id = :id`, `_id IN :ids`, `USE IDS` | ID scan, no index needed |
| `a = 1 OR b = 2` with both indexed | Union scan |
| `a = 1 OR b = 2` with `b` not indexed | Collection scan: every `OR` branch must be indexable |
| `a = 1 AND b = 2` with separate indexes | Intersect scan; a composite index on `(a, b)` is generally better (in testing, slower than the more selective index alone) |
| `array_contains(tags, 'x')`, `:tag IN tags` | Collection scan |
| `SELECT COUNT(*) FROM orders` (no `WHERE`) | Count scan |

- Index the full nested path you filter on (`address.city`).
- Keep type declarations consistent: according to Ditto's documentation, only the most recently written CRDT type of a field is indexed, so a field written with different declarations (for example once as `REGISTER` and once as `MAP`) can give incorrect or mis-ordered index results. In our testing with SDK 5.1.0 and 5.2.0, results were the same with and without the index (queries that declared a type did not use it), but reads with different declarations returned different values (`§ Keep type declarations consistent`). Do not index fields that are written with more than one type.
- With `DQL_STRICT_MODE = true`, the planner of SDK 5.1.0 and 5.2.0 does not use secondary indexes (queries fall back to a collection scan); ID lookups and full-collection `COUNT(*)` are not affected. Keep the default (`false`) if you rely on indexes.
- In-memory stores (Flutter Web, the JavaScript SDK in browsers) do not support indexes.

## Composite Indexes and Covering Scans

Composite indexes (SDK 5.1+): put equality fields first and the range or sort field last, and match the sort direction. On SDK 5.1.0, keep all keys of an index in one direction: with an index that mixes `ASC` and `DESC` keys, such as the one below, 5.1.0 returns the results in the wrong order (and the wrong documents with `LIMIT`). Use `(customerId, createdAt)` there and accept the extra sort step (`§ Known Issues in SDK 5.1.0`).

```sql
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- ✅ GOOD: equality on the leading key, range and sort on the second key
SELECT * FROM orders
WHERE customerId = :customerId AND createdAt >= :since
ORDER BY createdAt DESC
```

When a query projects only indexed fields (plus `_id`), the planner answers it from the index without fetching documents (`"covering": true` and no `fetch` step in `EXPLAIN`):

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)

SELECT _id, status FROM orders WHERE status = :status
```

On SDK 5.1.0, an indexed query that projects fields and sorts by one of them can return the rows in the wrong order; use `SELECT *` for sorted queries that use an index there, or sort in your code. Other planner issues of 5.1.0 that 5.2.0 fixes: a comparison with the constant on the left (`1 < a`) can return wrong results through an index, so write the field on the left (`a > 1`); and long `AND` or `OR` chains in `WHERE` can crash the app, so use `IN :values` for long lists of alternatives. See `§ Known Issues in SDK 5.1.0`.

Create indexes once at startup with `CREATE INDEX IF NOT EXISTS`; indexes persist and are local to each device. See `§ Creating Indexes` and `§ Index Usage Rules`.

## JOIN Performance

- Index the join key of every inner collection, or join on `_id`.
- Start from the most selective collection and filter it in `WHERE`, so fewer outer rows drive lookups.
- Check the plan with `EXPLAIN` (a join appears as `nlJoin`) and run `ADVISE` before release.
- Do not use `USE INDEX ''` on large collections: every outer row then scans the whole inner collection.

## Observers

- An observer re-runs its query and delivers the full result set on every relevant change. Keep observed queries filtered and bounded (`WHERE` + `ORDER BY` + `LIMIT`).
- Prefer several narrow observers (one per screen region) over one observer of a whole collection.
- Use `COUNT(*)` observers for badges. An aggregate observer is called on every write to its collection, also when its result stays the same (SDK 5.1.0 and 5.2.0, in testing), so skip the rebuild for an unchanged value and avoid expensive aggregates on collections that are written often.
- Throttle UI updates for very busy collections, or use the SDK's backpressure API with a slow consumer when only the latest state matters (`registerObserverV2` (Experimental) in Flutter, `observe(...).conflate()` in Kotlin).
- `execute` is asynchronous in every SDK; decode large results and do heavy work on the values off the UI thread. In Flutter, `execute` runs on a worker isolate on native platforms; leave `Store.experimentalSkipExecuteIsolateOffload` (Experimental) at its default unless you have measured a throughput problem (`§ Query execution and the UI thread`).

## Checklist

- [ ] `WHERE` filters in DQL, not in app code
- [ ] Projections list only needed fields in `execute` and observers
- [ ] Constant statement text with parameters
- [ ] `ORDER BY` (+ `_id`) with every `LIMIT`; keyset pagination for long lists
- [ ] `COUNT(*)` for counts, `LIMIT 1` for existence
- [ ] `IN :ids` instead of per-ID loops
- [ ] Predicates avoid functions on indexed fields; every `OR` branch indexable
- [ ] Composite index key order: equality first, then range/sort, matching direction
- [ ] JOIN inner keys indexed or joined on `_id`
- [ ] Observers bounded with `WHERE` and `LIMIT`
