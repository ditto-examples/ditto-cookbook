---
name: query-sync
description: |
  Validates Ditto SDK 5.1 DQL queries, writes, subscriptions, and store observers.

  CRITICAL ISSUES PREVENTED:
  - DQL built with string interpolation instead of parameters
  - Filters that silently drop documents (MISSING vs NULL, IN (:values), ANY ... SATISFIES)
  - Subscriptions rejected at registration (projections, JOIN, LIMIT/ORDER BY) or re-registered on every filter change
  - Uncancelled subscriptions and observers; onChange-only observers retaining every result
  - Upserts that rewrite unchanged data and wake observers (DO UPDATE instead of DO UPDATE_LOCAL_DIFF)
  - JOIN queries failing without an index on the inner collection
  - Retained QueryResult / QueryResultItem objects

  TRIGGERS:
  - Writing DQL for ditto.store.execute() or tx.execute()
  - Creating subscriptions with ditto.sync.registerSubscription()
  - Setting up observers with registerObserver, registerObserverV2, or registerObserverWithSignalNext
  - Using INSERT ... ON ID CONFLICT, UPDATE, RETURNING, DELETE, or EVICT
  - Writing JOIN, GROUP BY, ORDER BY, or LIMIT queries
  - Handling QueryResult, QueryResultItem, mutatedDocumentIDs(), commitID, or Differ

  PLATFORMS: Flutter (Dart) primary; JavaScript, Swift, Kotlin where behavior differs
---

# Ditto Query and Sync Patterns

Actionable patterns for DQL, subscriptions, and store observers in Ditto SDK 5.1.0 (Flutter package `ditto_live` 5.1.0). The authoritative reference is the [Ditto SDK Best Practices guide](../../../guides/best-practices/ditto.md); each pattern links to the guide section it is extracted from.

## Table of Contents

- [Core Model](#core-model)
- [Workflow: A Screen That Shows Synced Data](#workflow-a-screen-that-shows-synced-data)
- [Critical Patterns](#critical-patterns)
- [Other Platforms](#other-platforms)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## Core Model

Every DQL statement runs against the **local store**. Only subscriptions cause data to sync to the device.

| API (Flutter) | Reads from | Causes data to sync? |
|---|---|---|
| `ditto.sync.registerSubscription(query, arguments: ...)` | Remote peers | ✅ Yes, while sync is running |
| `ditto.store.execute(query, arguments: ...)` | Local store (snapshot) | ❌ No |
| `ditto.store.registerObserver(query, arguments: ...)` | Local store (live) | ❌ No |
| `ditto.store.transaction((tx) async { ... })` | Local store | ❌ No |

Subscriptions are long-lived and scoped by stable partition keys (app or feature scope). Observers and `execute` calls are short-lived and as specific as the screen needs (screen scope). An empty local result does not mean "no data exists"; it may not have synced yet.

**Guide**: [Where Queries Run](../../../guides/best-practices/ditto.md#where-queries-run), [Sync and Subscriptions](../../../guides/best-practices/ditto.md#sync-and-subscriptions)

---

## Workflow: A Screen That Shows Synced Data

```
Progress:
- [ ] 1. Subscription: SELECT * FROM c WHERE <stable partition key> = :param, owned by an app/feature service
- [ ] 2. Indexes: CREATE INDEX IF NOT EXISTS at startup for filter, sort, and JOIN keys
- [ ] 3. Observer: registered in initState() without onChange, with ORDER BY (+ _id tie-breaker) and LIMIT if large
- [ ] 4. Listener: consume observer.changes once; copy item.value into plain Dart data; call setState
- [ ] 5. Cleanup: cancel the StreamSubscription and the observer in dispose(); cancel subscriptions on logout or workspace change
```

---

## Critical Patterns

### 1. Pass Values as Parameters (CRITICAL)

Reference values with `:name` and pass them in `arguments`. Parameter names are case-sensitive.

**✅ DO**: use parameters for IDs, user input, dates, limits, and whole documents (`INSERT INTO orders DOCUMENTS (:order)`); pass arrays for membership (`status IN :statuses`).
**❌ DON'T**: build statements with interpolation or concatenation; write `IN (:statuses)` (the array becomes a single list element and nothing matches).

```dart
// ✅ GOOD: Values travel as typed parameters
Future<List<Map<String, dynamic>>> findOrders(
  Ditto ditto,
  String customerId,
  List<String> statuses,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE customerId = :customerId AND status IN :statuses '
    'ORDER BY createdAt DESC LIMIT :pageSize',
    arguments: {'customerId': customerId, 'statuses': statuses, 'pageSize': 50},
  );
  return result.items.map((item) => item.value).toList();
}
```

**Why**: interpolation allows DQL injection, breaks on quotes and backslashes, and defeats the shared statement cache.

**Guide**: [Parameters and Literals](../../../guides/best-practices/ditto.md#parameters-and-literals) · **Examples**: [dql-queries-good.dart](examples/dql-queries-good.dart), [dql-queries-bad.dart](examples/dql-queries-bad.dart)

### 2. Quote Every Key in Inline Object Literals (HIGH)

Unquoted keys are rejected in `INSERT` and silently produce `{}` in `SELECT`. Prefer passing documents as parameters.

<!-- expect-error -->
```sql
-- ❌ BAD: Rejected ("Cannot convert to a literal")
INSERT INTO orders DOCUMENTS ({_id: 'order-1', status: 'open'})
```

```sql
-- ✅ GOOD: Quoted keys
INSERT INTO orders DOCUMENTS ({'_id': 'order-1', 'status': 'open'})
```

Other literal rules: single and double quotes both delimit strings; backticks quote identifiers; reserved words such as `collection` cannot be bare identifiers.

### 3. MISSING vs NULL in Filters (CRITICAL)

A comparison with a missing or null field is neither true nor false, so the row is dropped.

| `WHERE` expression | Matches `false` | `null` | missing |
|---|---|---|---|
| `isDeleted != true` | ✓ | | | <!-- lint-ignore -->
| `coalesce(isDeleted, false) = false` | ✓ | ✓ | ✓ |
| `isDeleted IS NOT NULL` | ✓ | | ✓ | <!-- lint-ignore -->
| `isDeleted IS NOT MISSING` | ✓ | ✓ | |

**✅ DO**: filter optional booleans with `coalesce(field, default)`; test existence with `IS MISSING` / `IS NOT MISSING`; remove a field with `UNSET`.
**❌ DON'T**: use `field != true` or `NOT field` for "false or not set"; use `IS NOT NULL` to test existence. <!-- lint-ignore -->

```dart
// ✅ GOOD: A missing or null isDeleted flag counts as "not deleted"
Future<List<Map<String, dynamic>>> activeTasks(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false ORDER BY createdAt, _id',
  );
  return result.items.map((item) => item.value).toList();
}
```

**Guide**: [MISSING and NULL](../../../guides/best-practices/ditto.md#missing-and-null)

### 4. Membership Filters (HIGH)

| Goal | Expression |
|---|---|
| Field equals one of several values | `status IN :statuses` (array parameter; can use an index) |
| Literal list | `status IN ('open', 'pending')` |
| Array field contains a value | `:tag IN tags` or `array_contains(tags, :tag)` (no index) |
| ❌ Array parameter in parentheses | `status IN (:statuses)` matches nothing |

> **Note (SDK 5.1.0):** `ANY ... SATISFIES ... END` in a `WHERE` clause that iterates over a parameter or literal array returns no rows. Use `status IN :statuses` (or `array_contains(:statuses, status)`) instead.

**Guide**: [Filtering by Membership](../../../guides/best-practices/ditto.md#filtering-by-membership)

### 5. Subscription Rules (CRITICAL)

A subscription selects whole documents from one collection: `SELECT * FROM <collection> [WHERE <condition>]`. `registerSubscription` rejects the features below with an error, even before sync starts. Subscriptions on `system:` collections (such as `system:data_sync_info`) are accepted but have no effect.

| Rejected in subscriptions | Do instead |
|---|---|
| Projections, aggregates (`A projection other than wildcard (*)`), `DISTINCT`, `GROUP BY` (`Grouping`) | Subscribe with `SELECT *`; project in local queries |
| `JOIN` | Subscribe to each collection separately; join locally |
| `USE IDS` | `WHERE _id IN :ids` |
| `LIMIT`, `ORDER BY` | Sort and limit in the local query or observer |

Keep `DQL_RESTRICT_SUBSCRIPTIONS` at its default (`true`). Setting it to `false` allows only `LIMIT`/`ORDER BY`, which creates stateful subscriptions that degrade sync performance.

```dart
// ✅ GOOD: Scope by a stable partition key; sort and limit locally
// (the subscription is owned by a long-lived service such as OrderSync)
SyncSubscription subscribeToStoreOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

Future<List<Map<String, dynamic>>> latestOrders(Ditto ditto, String storeId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC LIMIT 50',
    arguments: {'storeId': storeId},
  );
  return result.items.map((item) => item.value).toList();
}
```

**✅ DO**: filter by stable partition keys (tenant, store, region, team); use the same subscriptions on peers in the same role; keep predicates flat and simple; give relay devices at least the subscriptions of the devices behind them.
**❌ DON'T**: subscribe to entire large collections "just in case" (acceptable only for small reference data); filter subscriptions on fields that change often (`status`, `assignee`).

**Soft delete**: keep soft-deleted documents inside the subscription at least until every device has received the flag, and hide them locally with `coalesce(isDeleted, false) = false`. Variant A subscribes to the whole collection (or partition) and cleans up with a synced `DELETE`; Variant B subscribes to active documents plus a retention window so devices can `EVICT` older ones. See [Soft delete, subscriptions, and cleanup](../../../guides/best-practices/ditto.md#soft-delete-subscriptions-and-cleanup) and the storage-lifecycle skill.

**Guide**: [Subscription Rules](../../../guides/best-practices/ditto.md#subscription-rules), [Scope Balancing](../../../guides/best-practices/ditto.md#scope-balancing)

### 6. Subscription Lifecycle (CRITICAL)

Changing subscriptions makes peers across the mesh re-evaluate what they owe the device. Avoid changing subscriptions more often than about every 15 minutes.

**✅ DO**:
- Register subscriptions at app start, after login, or when the user enters a workspace, in an app- or feature-level service
- Keep a reference to every `SyncSubscription` and call `cancel()` on logout or workspace change
- Change the **observer**, not the subscription, when the user changes a filter, search term, tab, or sort order
- Cancel subscriptions **before** evicting their data; cancelling alone does not delete local data

**❌ DON'T**:
- Register subscriptions in `build()` or on every screen visit
- Drop a subscription reference without cancelling it; always release subscriptions explicitly and do not rely on garbage collection to cancel them
- Read `queryArguments` from `ditto.sync.subscriptions` (see the note below)

```dart
// ✅ GOOD: A session-level service owns long-lived subscriptions
class OrderSync {
  OrderSync(this._ditto);

  final Ditto _ditto;
  final List<SyncSubscription> _subscriptions = [];

  void enterStore(String storeId) {
    leaveStore();
    _subscriptions.add(_ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    ));
  }

  void leaveStore() {
    for (final subscription in _subscriptions) {
      subscription.cancel(); // No-op if already cancelled or Ditto was closed
    }
    _subscriptions.clear();
  }
}
```

`ditto.sync.stop()` pauses subscriptions (they resume on `start()`); `await ditto.close()` marks them cancelled.

> **Note (SDK 5.1.0):** Do not read `queryArguments` or `queryArgumentsJsonString` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this can terminate the app. Read only `queryString` and `isCancelled` there, and keep your own references (as `OrderSync` does).

**Guide**: [Subscription Lifecycle](../../../guides/best-practices/ditto.md#subscription-lifecycle) · **Examples**: [subscription-lifecycle-good.dart](examples/subscription-lifecycle-good.dart), [subscription-lifecycle-bad.dart](examples/subscription-lifecycle-bad.dart)

### 7. The Flutter Observer Pattern (CRITICAL)

Register **without** `onChange`, consume `changes` with one `StreamSubscription`, and cancel both in `dispose()`.

```dart
class OrdersList extends StatefulWidget {
  const OrdersList({super.key, required this.ditto});
  final Ditto ditto;
  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC",
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      setState(() {
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: [for (final o in _orders) ListTile(title: Text('${o['_id']}'))],
      );
}
```

> **Note (SDK 5.1.0):** With `onChange`, every result is also queued in `changes`. If nothing listens to `changes`, those results stay in memory for the observer's lifetime, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` right after registering it. Use the pattern above; if you need `onChange`, also drain the stream (`observer.changes.listen((_) {})`).

Lifecycle facts (`registerObserver`): `changes` is single-subscription (a second `listen()` throws, even after the first subscription was cancelled; a `StreamBuilder` works if it stays mounted for the observer's lifetime). Without `onChange`, the query starts when `changes` is first listened to; with `onChange`, events emitted before the first listener attaches are buffered, so listen right after registering. Cancelling the `StreamSubscription` does not cancel a `StoreObserver`, and `await ditto.close()` does not close its `changes` stream: always call `observer.cancel()` before closing. More in [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md#observer-lifecycle).

**✅ DO**: register in `initState()` or a service; when inputs change (`didUpdateWidget`), cancel and re-register the observer; give each screen region its own small observer; use `COUNT(*)` for badges.
**❌ DON'T**: register in `build()`; create an observer per list item; observe a whole collection at the root and rebuild the entire screen.

**Guide**: [Store Observers in Flutter](../../../guides/best-practices/ditto.md#store-observers-in-flutter), [Partial UI Updates](../../../guides/best-practices/ditto.md#partial-ui-updates) · **Examples**: [observer-patterns-good.dart](examples/observer-patterns-good.dart), [observer-patterns-bad.dart](examples/observer-patterns-bad.dart)

### 8. ORDER BY and LIMIT Belong in Local Queries (HIGH)

Results have no guaranteed order without `ORDER BY`, including observer results.

- Add `ORDER BY` with a unique tie-breaker: `ORDER BY createdAt DESC, _id`.
- Ascending type order: `false` < `true` < numbers < binary < strings < arrays < objects < `null` < missing. `DESC` puts missing values first.
- Always combine `LIMIT`/`OFFSET` with `ORDER BY`; prefer keyset pagination with an `_id` tie-breaker (`WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId) ORDER BY createdAt DESC, _id DESC LIMIT :pageSize`) for long lists. Check existence with `SELECT _id ... LIMIT 1`; count with `COUNT(*)`.

**Guide**: [ORDER BY](../../../guides/best-practices/ditto.md#order-by), [LIMIT and OFFSET](../../../guides/best-practices/ditto.md#limit-and-offset)

### 9. Query Result Handling (HIGH)

| Member (Flutter) | Notes |
|---|---|
| `items` | `Iterable<QueryResultItem>`, not a `List`; each pass creates new wrappers |
| `item.value` | `Map<String, dynamic>`, decoded on first access and cached on that item |
| `item.jsonString`, `item.cborBytes` | Properties, not methods |
| `mutatedDocumentIDs()` | Builds a new list on every call; call once. With `RETURNING`, read the affected documents from `items` instead |
| `commitID` | `int?`; `null` for reads, and `null` inside a transaction until it commits |

**✅ DO**: iterate `items` once and convert rows to maps or model objects right away; project only the fields you need.
**❌ DON'T**: store `QueryResult` or `QueryResultItem` objects in state, caches, or across observer callbacks (they reference native memory).

**Guide**: [Working with Query Results](../../../guides/best-practices/ditto.md#working-with-query-results) · **Example**: [query-result-handling.dart](examples/query-result-handling.dart)

### 10. Backpressure for Slow Observer Work (HIGH)

`registerObserver` has no backpressure: results keep arriving while an `async` listener waits. Keep its listener synchronous and short. For slow or asynchronous per-update work, use one of the experimental APIs (SDK 5.1+), which hold back updates and later deliver the latest state:

| Situation | API |
|---|---|
| Updating widgets | `registerObserver` + `changes` (stable, default) |
| Slow `async` work that fits a loop | `registerObserverV2` **(Experimental)** + `await for` (follows pause/resume) |
| Work finishes elsewhere (animation, external callback) | `registerObserverWithSignalNext` **(Experimental)**; call `signalNext()` in a `finally` block |

`signalNext()` has no effect on `registerObserverV2` observers. A `registerObserverWithSignalNext` observer stops updating if you never call `signalNext()`; do not pause/resume its `changes` stream. Cancelling the stream subscription of a `StoreObserverV2` also cancels the observer.

**Guide**: [Backpressure (SDK 5.1+)](../../../guides/best-practices/ditto.md#backpressure-sdk-51) · **Example**: [observer-backpressure.dart](examples/observer-backpressure.dart)

### 11. Upserts and Field-Level Updates (HIGH)

| `ON ID CONFLICT` | Existing document |
|---|---|
| `FAIL` (default) | Statement fails |
| `DO NOTHING` | Unchanged |
| `DO UPDATE` | Supplied fields merged in, even if identical (mutation recorded, observers can fire again) |
| `DO UPDATE_LOCAL_DIFF` | Only differing fields written; nothing written if nothing changed |

**✅ DO**: use `DO UPDATE_LOCAL_DIFF` for upserts and re-imports; update only changed fields with `UPDATE ... SET`; remove fields with `UNSET`; replace an object with `UNSET obj` followed by `SET obj = :value` inside one transaction (two `tx.execute` calls).
**❌ DON'T**: read-modify-write whole documents with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (a stale in-memory value differs from the stored one, so it is written back); expect `DO UPDATE` or `SET obj = {...}` to remove keys (with the default `DQL_STRICT_MODE = false`, objects merge).

```dart
// ✅ GOOD: Re-upserting unchanged data is a no-op
Future<void> syncCatalogItem(Ditto ditto, Map<String, dynamic> item) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:item) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'item': item},
  );
}
```

**Guide**: [INSERT and Conflict Handling](../../../guides/best-practices/ditto.md#insert-and-conflict-handling), [UPDATE](../../../guides/best-practices/ditto.md#update) · **Example**: [dql-writes.dart](examples/dql-writes.dart)

### 12. RETURNING (SDK 5.1+) (MEDIUM)

`RETURNING` on `INSERT`, `UPDATE`, `DELETE`, or `EVICT` returns the affected documents in `items`: after the update for `UPDATE`, before removal for `DELETE`/`EVICT`. Use it instead of "write, then query again", and to capture deleted content.

```dart
// ✅ GOOD: Update and read the new values in one statement
Future<List<Map<String, dynamic>>> markShipped(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id IN :ids AND status = :expected '
    'RETURNING _id, status',
    arguments: {'ids': ids, 'status': 'shipped', 'expected': 'packed'},
  );
  return result.items.map((item) => item.value).toList();
}
```

**Guide**: [RETURNING (SDK 5.1+)](../../../guides/best-practices/ditto.md#returning-sdk-51)

### 13. Aggregates, GROUP BY, and HAVING (MEDIUM)

- `GROUP BY` and `HAVING` cannot reference projection aliases: repeat the expression. `ORDER BY` can use aliases.
- Every non-aggregate projection must be a `GROUP BY` key. Give computed expressions an alias with `AS`.
- With zero matching rows, `SUM`/`AVG`/`MIN`/`MAX` return MISSING: wrap them, `ifmissing(SUM(total), 0)`.
- `COUNT(field)` skips `false` values; use `COUNT(*)` or `COUNT(field IS NOT MISSING)`.
- Do not use `DISTINCT` with `_id` or `*`.

<!-- expect-error -->
```sql
-- ❌ BAD: HAVING references the alias "revenue"
SELECT customerId, SUM(total) AS revenue FROM orders GROUP BY customerId HAVING revenue > 1000
```

```sql
-- ✅ GOOD: Repeat the expression in HAVING; ORDER BY may use the alias
SELECT customerId, SUM(total) AS revenue FROM orders
GROUP BY customerId HAVING SUM(total) > 1000 ORDER BY revenue DESC
```

**Guide**: [Aggregates](../../../guides/best-practices/ditto.md#aggregates), [GROUP BY and HAVING](../../../guides/best-practices/ditto.md#group-by-and-having)

### 14. JOIN (SDK 5.1+) Needs an Index on the Inner Collection (HIGH)

Joins (`INNER`, `LEFT`, `RIGHT` as first join only) run on local data. The inner collection's join key needs an index, or the join must be on its `_id`; otherwise the query fails with `Joining to "c" disallowed without appropriate index support`.

```sql
CREATE INDEX IF NOT EXISTS ix_orders_customerId ON orders (customerId)
```

```sql
-- ✅ GOOD: Inner side (orders) is looked up through ix_orders_customerId
SELECT c.name, o._id AS orderId, o.total
FROM customers c
JOIN orders o ON o.customerId = c._id
WHERE c.tier = 'gold'
ORDER BY c.name, o.total DESC
```

**✅ DO**: qualify every field with its alias and alias colliding fields (`o._id AS orderId`); subscribe to each joined collection separately; filter the outer collection selectively; run `ADVISE` for index recommendations.
**❌ DON'T**: use `JOIN` in subscriptions or on Ditto Server; use `USE INDEX ''` on large collections to silence the index error.

**Guide**: [Joining Collections (SDK 5.1+)](../../../guides/best-practices/ditto.md#joining-collections-sdk-51)

### 15. DELETE and EVICT by ID Use WHERE (HIGH)

> **Note (SDK 5.1.0):** `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) completes without an error but removes nothing. Use `WHERE _id = :id` or `WHERE _id IN :ids`.

`DELETE` removes documents on all peers (tombstone); `EVICT` removes them from this device only. See the storage-lifecycle skill.

**Guide**: [DELETE and EVICT](../../../guides/best-practices/ditto.md#delete-and-evict)

### 16. Differ for Item-Level Changes (MEDIUM)

An observer delivers the full result every time. `Differ` reports `insertions`, `deletions` (indexes into the old list), `updates`, and `moves` by `_id`.

Pass `result.items.toList()` (`diff()` takes a `List`); the first call reports every item as an insertion. `Differ` keeps the previous result and is expensive, so bound diffed queries with `LIMIT` and keep previous values yourself if you need them. A plain `ListView.builder` with `ValueKey(_id)` does not need `Differ`; use it for `AnimatedList` or for processing only new items.

**Guide**: [Diffing Results](../../../guides/best-practices/ditto.md#diffing-results) · **Example**: [observer-differ.dart](examples/observer-differ.dart)

---

## Other Platforms

Backpressure differs per platform: JavaScript `registerObserver` signals the next update when a synchronous handler returns (async handlers are not awaited; use `registerObserverWithSignalNext`), Swift offers `handler:` (automatic) and `handlerWithSignalNext:` (manual), and Kotlin has no `signalNext` (suspending handlers or a `Flow`; release with `close()`). Details: [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md#other-platforms).

JavaScript passes arguments as the second positional parameter (`execute(query, { status: 'open' })`) and reads changed IDs with `mutatedDocumentIDsV2()`. Do not port Flutter observer code one-to-one.

**Guide**: [Backpressure on Other Platforms](../../../guides/best-practices/ditto.md#backpressure-on-other-platforms)

---

## Quick Reference Checklist

### DQL
- [ ] Values passed as `:parameters`; arrays as `IN :values` (no parentheses)
- [ ] Inline object literal keys quoted; documents passed as `DOCUMENTS (:doc)`
- [ ] Optional booleans filtered with `coalesce(field, false)`; existence tested with `IS [NOT] MISSING`
- [ ] No `ANY ... SATISFIES` membership filters in `WHERE`
- [ ] `ORDER BY` with `_id` tie-breaker wherever order matters; `LIMIT` combined with `ORDER BY`
- [ ] `GROUP BY` / `HAVING` repeat expressions instead of aliases; empty aggregates wrapped with `ifmissing`
- [ ] JOIN inner keys indexed (or joined on `_id`); fields qualified with aliases
- [ ] Upserts use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`; fields removed with `UNSET`
- [ ] `DELETE` / `EVICT` by ID use `WHERE _id IN :ids`

### Subscriptions
- [ ] Only `SELECT * FROM c [WHERE ...]`, filtered by stable partition keys
- [ ] Owned by an app/feature service; references kept and cancelled on logout or workspace change
- [ ] Not re-registered for UI filters, search, tabs, or sorting
- [ ] Cancelled before evicting their data

### Observers
- [ ] Registered in `initState()` or a service, never in `build()`
- [ ] No `onChange`; `changes` consumed by exactly one listener
- [ ] Stream subscription and observer both cancelled in `dispose()`
- [ ] Listener copies `item.value` into plain data; no `QueryResult` retained
- [ ] Slow async work uses `registerObserverV2` or `registerObserverWithSignalNext` (Experimental), with `signalNext()` in `finally`

---

## See Also

### Guide sections
- [DQL Fundamentals](../../../guides/best-practices/ditto.md#dql-fundamentals)
- [Reading Data with SELECT](../../../guides/best-practices/ditto.md#reading-data-with-select)
- [Writing Data](../../../guides/best-practices/ditto.md#writing-data)
- [Sync and Subscriptions](../../../guides/best-practices/ditto.md#sync-and-subscriptions)
- [Observing Changes](../../../guides/best-practices/ditto.md#observing-changes)
- [Indexing and Query Performance](../../../guides/best-practices/ditto.md#indexing-and-query-performance)

### Other skills
- **data-modeling**: document structure, strict mode, CRDT types, relationships
- **storage-lifecycle**: DELETE, soft delete, EVICT
- **performance-observability**: indexes, ADVISE, EXPLAIN, logging
- **transactions-attachments**: `store.transaction`, attachments

### Examples
All examples are in [examples/](examples/) and linked from the patterns above; the `-good` / `-bad` pairs contrast correct and incorrect versions of the same task.

### Reference
- [reference/dql-reference.md](reference/dql-reference.md): literals, MISSING/NULL, USE IDS, JOIN details, write semantics
- [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md): subscription rules, scope, observer lifecycle, choosing an observer API
- [reference/query-optimization.md](reference/query-optimization.md): projections, indexes, pagination, counting
