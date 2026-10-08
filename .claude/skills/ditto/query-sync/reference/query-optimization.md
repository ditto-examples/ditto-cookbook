# Query Optimization (SDK 5.1)

How to keep local queries and observers fast. Extracted from the guide sections [Working with Query Results](../../../../guides/best-practices/ditto.md#working-with-query-results), [Reading Data with SELECT](../../../../guides/best-practices/ditto.md#reading-data-with-select), and [Indexing and Query Performance](../../../../guides/best-practices/ditto.md#indexing-and-query-performance). Index creation, `ADVISE`, `EXPLAIN`, and `PROFILE` are covered in the performance-observability skill.

## Table of Contents

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

## Query Scope

**✅ DO**:
- **Filter narrowly** in `WHERE` instead of filtering in Dart.
- **Project** only the fields you need (`SELECT _id, title, status ...`). This reduces decoding and memory and can enable covering scans. Subscriptions still sync whole documents.
- **Keep statement text constant** and pass values as parameters, so the prepared plan is reused from the statement cache.
- **Materialize once**: convert rows to maps or models in one pass and let the `QueryResult` go.

**❌ DON'T**:
- Load a whole collection and filter, sort, or paginate in Dart.
- Use `DISTINCT` with `_id` or `*`.

## Pagination

Always combine `LIMIT` with `ORDER BY`. Keyset pagination avoids re-reading skipped rows:

```dart
// ✅ GOOD: Keyset pagination with a parameterized page size
Future<List<Map<String, dynamic>>> nextPage(
  Ditto ditto,
  String afterCreatedAt,
) async {
  final result = await ditto.store.execute(
    'SELECT _id, title, createdAt FROM tasks '
    'WHERE createdAt < :after ORDER BY createdAt DESC LIMIT :pageSize',
    arguments: {'after': afterCreatedAt, 'pageSize': 50},
  );
  return result.items.map((item) => item.value).toList();
}
```

`LIMIT :pageSize OFFSET :offset` works, but every page re-reads and skips all earlier rows. Use a unique sort key or add a tie-breaker (`ORDER BY createdAt DESC, _id`) so pages are well defined.

## Counting and Existence

- Count with `SELECT COUNT(*) ...`, not by loading documents and calling `.length`.
- A full-collection `COUNT(*)` is answered by a dedicated count scan (SDK 5.1+) without reading documents. A filtered `COUNT(*)` still evaluates the filter, so index the filtered fields.
- Check existence with `SELECT _id ... LIMIT 1`.

```sql
SELECT COUNT(*) AS n FROM orders WHERE status = :status

SELECT _id FROM orders WHERE status = :status LIMIT 1
```

## Batching Instead of N+1

```dart
// ✅ GOOD: One query, planned as an ID scan
Future<List<Map<String, dynamic>>> loadOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
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
| `a = 1 AND b = 2` with separate indexes | Intersect scan; a composite index on `(a, b)` is generally better |
| `array_contains(tags, 'x')`, `:tag IN tags` | Collection scan |
| `SELECT COUNT(*) FROM orders` (no `WHERE`) | Count scan |

- Index the full nested path you filter on (`address.city`).
- Keep each field's type consistent across documents; mixed types can make index results incorrect or mis-ordered.
- With `DQL_STRICT_MODE = true`, the SDK 5.1.0 planner does not use index scans at all. Keep the default (`false`) if you rely on indexes.
- In-memory stores (Flutter Web) do not support indexes.

## Composite Indexes and Covering Scans

Composite indexes (SDK 5.1+): put equality fields first and the range or sort field last, and match the sort direction.

```sql
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- ✅ GOOD: equality on the leading key, range and sort on the second key
SELECT * FROM orders
WHERE customerId = :customerId AND createdAt >= :since
ORDER BY createdAt DESC
```

When a query projects only indexed fields (plus `_id`), the planner answers it from the index without fetching documents (`"covering": true` in `EXPLAIN`):

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)

SELECT _id, status FROM orders WHERE status = :status
```

Create indexes once at startup with `CREATE INDEX IF NOT EXISTS`; indexes persist and are local to each device. See [Creating Indexes](../../../../guides/best-practices/ditto.md#creating-indexes) and [Index Usage Rules](../../../../guides/best-practices/ditto.md#index-usage-rules).

## JOIN Performance

- Index the join key of every inner collection, or join on `_id`.
- Start from the most selective collection and filter it in `WHERE`, so fewer outer rows drive lookups.
- Check the plan with `EXPLAIN` (a join appears as `nlJoin`) and run `ADVISE` before release.
- Do not use `USE INDEX ''` on large collections: every outer row then scans the whole inner collection.

## Observers

- An observer re-runs its query and delivers the full result set on every relevant change. Keep observed queries filtered and bounded (`WHERE` + `ORDER BY` + `LIMIT`).
- Prefer several narrow observers (one per screen region) over one observer of a whole collection.
- Use `COUNT(*)` observers for badges; avoid expensive aggregates in observers that fire often.
- Throttle UI updates for very busy collections, or use `registerObserverV2` (Experimental) with a slow consumer when only the latest state matters.
- On native platforms `execute` runs on a worker isolate, so a slow query does not block the UI isolate. Leave `Store.experimentalSkipExecuteIsolateOffload` (Experimental) at its default unless you have measured a throughput problem with many very small queries.

## Checklist

- [ ] `WHERE` filters in DQL, not in Dart
- [ ] Projections list only needed fields in `execute` and observers
- [ ] Constant statement text with parameters
- [ ] `ORDER BY` (+ `_id`) with every `LIMIT`; keyset pagination for long lists
- [ ] `COUNT(*)` for counts, `LIMIT 1` for existence
- [ ] `IN :ids` instead of per-ID loops
- [ ] Predicates avoid functions on indexed fields; every `OR` branch indexable
- [ ] Composite index key order: equality first, then range/sort, matching direction
- [ ] JOIN inner keys indexed or joined on `_id`
- [ ] Observers bounded with `WHERE` and `LIMIT`
