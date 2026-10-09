---
name: query-sync
description: Ditto SDK DQL reads and writes, subscriptions, and store observers: query parameters, MISSING vs NULL, membership filters, subscription rules and lifecycle, the Flutter observer pattern, upserts with ON ID CONFLICT, JOIN, RETURNING. Use when writing or reviewing ditto.store.execute, ditto.sync.registerSubscription, registerObserver, or any DQL statement, or when synced data does not appear or a query returns nothing.
---

# Ditto Query and Sync Patterns

DQL statements, subscriptions, and store observers: what syncs, what a query sees, and cheap observers and upserts. Targets Ditto SDK 5.1.0; examples are Flutter (Dart).

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

## Prevents

- DQL built with string interpolation instead of parameters
- Filters that silently drop documents (MISSING vs NULL, `IN (:values)`, `ANY ... SATISFIES` over a parameter)
- "Synced data does not show": no subscription matches the data
- Subscriptions rejected at registration (projections, `JOIN`, `LIMIT`/`ORDER BY`) or re-registered on every filter change
- Uncancelled subscriptions and observers; `onChange` observers retaining every result
- Upserts that rewrite unchanged data and wake observers (`DO UPDATE` instead of `DO UPDATE_LOCAL_DIFF`)
- `JOIN` queries failing without an index on the inner collection
- Retained `QueryResult` / `QueryResultItem` objects

## Workflow

Every DQL statement runs against the **local store**. Only `ditto.sync.registerSubscription` makes data sync from remote peers (while sync is running); `ditto.store.execute` (snapshot), `ditto.store.registerObserver` (live), and `ditto.store.transaction` read local data and never cause sync.

Subscriptions are long-lived, scoped by stable partition keys; observers and `execute` calls are short-lived and screen-specific. An empty local result does not mean "no data exists"; it may not have synced yet, or no subscription matches it.

`§ Where Queries Run`, `§ Sync and Subscriptions`

A screen that shows synced data:

```
Progress:
- [ ] 1. Subscription: SELECT * FROM c WHERE <stable partition key> = :param, owned by an app/feature service
- [ ] 2. Indexes: CREATE INDEX IF NOT EXISTS at startup for filter, sort, and JOIN keys
- [ ] 3. Observer: registered in initState() without onChange, with ORDER BY (+ _id tie-breaker) and LIMIT if large
- [ ] 4. Listener: consume observer.changes once; copy item.value into plain Dart data; call setState
- [ ] 5. Cleanup: cancel the StreamSubscription and the observer in dispose(); cancel subscriptions on logout or workspace change
```

## Rules

### 1. Pass values as parameters (CRITICAL)

Reference values with `:name` and pass them in `arguments`. Names are case-sensitive; a placeholder without an argument fails. Interpolation allows DQL injection, breaks on quotes and backslashes, and defeats the shared statement cache.
**✅ DO**: parameters for IDs, user input, dates, `LIMIT`/`OFFSET`, and whole documents (`INSERT INTO orders DOCUMENTS (:order)`); arrays for membership (`status IN :statuses`).
**❌ DON'T**: build statements with interpolation or concatenation; write `IN (:statuses)` (the array becomes one list element and nothing matches).

`§ Parameters and Literals` · Examples: [dql-queries-good.dart](examples/dql-queries-good.dart), [dql-queries-bad.dart](examples/dql-queries-bad.dart)

### 2. Treat MISSING and NULL explicitly in filters (CRITICAL)

A comparison with a missing or null field is neither true nor false, so the row is dropped.

| `WHERE` expression | Matches `false` | `null` | missing |
|---|---|---|---|
| `isDeleted != true` | ✓ | | | <!-- lint-ignore -->
| `coalesce(isDeleted, false) = false` | ✓ | ✓ | ✓ |
| `isDeleted IS NOT NULL` | ✓ | | ✓ | <!-- lint-ignore -->
| `isDeleted IS NOT MISSING` | ✓ | ✓ | |

**✅ DO**: filter optional booleans with `coalesce(field, default)` (`WHERE coalesce(isDeleted, false) = false`); test absence with `IS MISSING` / `IS NOT MISSING`; remove a field with `UNSET`.
**❌ DON'T**: use `field != true` or `NOT field` for "false or not set"; use `IS NOT NULL` to test existence. <!-- lint-ignore -->

`§ MISSING and NULL`

### 3. Subscribe with SELECT * and stable partition keys (CRITICAL)

A subscription selects whole documents from one collection: `SELECT * FROM <collection> [WHERE <condition>]`. `registerSubscription` rejects the features below with an error, even before sync starts. Subscriptions on `system:` collections (such as `system:data_sync_info`) are accepted but have no effect.

| Rejected in subscriptions | Do instead |
|---|---|
| Projections, aggregates, `DISTINCT`, `GROUP BY` | Subscribe with `SELECT *`; project in local queries |
| `JOIN` | Subscribe to each collection separately; join locally |
| `USE IDS` | `WHERE _id IN :ids` |
| `LIMIT`, `ORDER BY` | Sort and limit in the local query or observer |

Keep `DQL_RESTRICT_SUBSCRIPTIONS` at its default (`true`): `false` allows `LIMIT`/`ORDER BY` as stateful subscriptions that degrade sync, and in SDK 5.1.0 such a `LIMIT` bounds only the initial download (later, every new or changed match syncs). Bound what syncs with `WHERE` (a stable key or a time window), not `LIMIT`.
**✅ DO**: filter by stable partition keys (tenant, store, region, team); use the same subscriptions on peers in the same role; keep predicates flat; give relay devices at least the subscriptions of the devices behind them.
**❌ DON'T**: subscribe to entire large collections "just in case" (acceptable only for a small reference-data collection every device needs); filter subscriptions on fields that change often (`status`, `assignee`).

Soft delete: keep soft-deleted documents in the subscription until every device has the flag; hide them locally with `coalesce(isDeleted, false) = false` (variants: `storage-lifecycle`).

`§ Subscription Rules`, `§ Scope Balancing`, `§ Soft delete, subscriptions, and cleanup`

### 4. Own subscriptions in a long-lived service and cancel them (CRITICAL)

Changing subscriptions makes peers re-evaluate which documents to send; avoid changing them more often than about every 15 minutes (documents already held are not downloaded again).
**✅ DO**:
- Register at app start, after login, or on entering a workspace, in an app- or feature-level service; keep every `SyncSubscription` and `cancel()` it on logout or workspace change
- Change the **observer**, not the subscription, when the user changes a filter, search term, tab, or sort order
- Cancel subscriptions **before** evicting their data; cancelling alone does not delete local data

**❌ DON'T**: register in `build()` or on every screen visit; drop a reference without cancelling it (do not rely on garbage collection).

```dart
class OrderSync {
  OrderSync(this._ditto);
  final Ditto _ditto;
  final List<SyncSubscription> _subscriptions = [];
  String? _storeId;

  void enterStore(String storeId) {
    if (storeId == _storeId) return; // Already subscribed; do not re-register.
    leaveStore();
    _storeId = storeId;
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
    _storeId = null;
  }
}
```

`ditto.sync.stop()` pauses subscriptions (resumed by `start()`); `await ditto.close()` marks them cancelled.

> **Note (SDK 5.1.0):** Do not read `queryArguments` or `queryArgumentsJsonString` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this can terminate the app. Read only `queryString` and `isCancelled` there, and keep your own references.

`§ Subscription Lifecycle` · Examples: [subscription-lifecycle-good.dart](examples/subscription-lifecycle-good.dart), [subscription-lifecycle-bad.dart](examples/subscription-lifecycle-bad.dart)

### 5. Use the Flutter observer pattern (CRITICAL)

Register **without** `onChange`, consume `changes` with one `StreamSubscription`, and cancel both in `dispose()`.

```dart
class _OrdersListState extends State<OrdersList> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      setState(() => _orders = result.items.map((item) => item.value).toList());
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }
  // build(): ListView.builder with ValueKey(order['_id']) per row
}
```

> **Note (SDK 5.1.0):** With `onChange`, every result is also queued in `changes`; if nothing listens, those results stay in memory for the observer's lifetime. `registerObserverV2` starts observing on registration, with or without `onChange`: listen to its `changes` right away. If you need `onChange`, also drain the stream (`observer.changes.listen((_) {})`).

Lifecycle: `changes` is single-subscription (a second `listen()` throws, even after cancelling the first). Cancelling the `StreamSubscription` does not cancel a `StoreObserver`, and `await ditto.close()` does not close its `changes` stream: call `observer.cancel()` before closing. `registerObserver` has no backpressure, so keep its listener synchronous and short.
**✅ DO**: register in `initState()` or a service; when inputs change (`didUpdateWidget`), cancel and re-register; give each screen region its own small observer; use `COUNT(*)` for badges.
**❌ DON'T**: register in `build()`; create an observer per list item; observe a whole collection at the screen root.

`§ Store Observers in Flutter`, `§ Observer lifecycle and cleanup` · Examples: [observer-patterns-good.dart](examples/observer-patterns-good.dart), [observer-patterns-bad.dart](examples/observer-patterns-bad.dart) · Details: [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md#observer-lifecycle)

### 6. Filter membership with IN :values (HIGH)

| Goal | Expression |
|---|---|
| Field equals one of several values | `status IN :statuses` (array parameter; can use an index) |
| Literal list | `status IN ('open', 'pending')` |
| Array field contains a value | `:tag IN tags` or `array_contains(tags, :tag)` (no index) |
| ❌ Array parameter in parentheses | `status IN (:statuses)` matches nothing |

> **Note (SDK 5.1.0):** `ANY ... SATISFIES ... END` in `WHERE` over a parameter or literal array returns no rows (5.0.x returned matches). Use `status IN :statuses` or `array_contains(:statuses, status)`. Only local queries and observers are affected; a subscription with the same predicate syncs the documents, so the data arrives but the list shows empty.

`§ Filtering by Membership`

### 7. Upsert with DO UPDATE_LOCAL_DIFF and update fields, not documents (HIGH)

| `ON ID CONFLICT` | Existing document |
|---|---|
| `FAIL` (default) | Statement fails |
| `DO NOTHING` | Unchanged |
| `DO UPDATE` | Supplied fields merged in, even if identical (mutation recorded, observers can fire again) |
| `DO UPDATE_LOCAL_DIFF` | Only differing fields written; nothing written if nothing changed |

**✅ DO**: `INSERT INTO products DOCUMENTS (:item) ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports; change only changed fields with `UPDATE ... SET`; remove fields with `UNSET`; replace an object with `UNSET obj` then `SET obj = :value` in one transaction (two `tx.execute` calls).
**❌ DON'T**: read-modify-write whole documents with `DO UPDATE` or `DO UPDATE_LOCAL_DIFF` (a stale in-memory value differs from the stored one and is written back); expect `DO UPDATE` or `SET obj = {...}` to remove keys (with the default `DQL_STRICT_MODE = false`, objects merge; merge semantics: `data-modeling`).

`§ INSERT and Conflict Handling`, `§ UPDATE` · Example: [dql-writes.dart](examples/dql-writes.dart)

### 8. Index the inner collection of a JOIN (SDK 5.1+) (HIGH)

Joins (`INNER`, `LEFT`, `RIGHT` as first join only) run on local data. The inner collection's join key needs an index, or the join must be on its `_id`; otherwise the query fails with `Joining to "c" disallowed without appropriate index support`.
**✅ DO**: `CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)` for `... JOIN orders o ON o.customerId = c._id`; qualify every field with its alias and alias colliding fields; subscribe to each joined collection separately; filter the outer collection selectively; run `ADVISE` for index recommendations.
**❌ DON'T**: use `JOIN` in subscriptions or on Ditto Server; use `USE INDEX ''` on large collections to silence the index error.

`§ Joining Collections (SDK 5.1+)`

### 9. Put ORDER BY and LIMIT in local queries, with a tie-breaker (HIGH)

Without `ORDER BY` (observers included) order is not guaranteed. Add a unique tie-breaker (`ORDER BY createdAt DESC, _id`); combine `LIMIT`/`OFFSET` with `ORDER BY`; prefer keyset pagination. Existence: `SELECT _id ... LIMIT 1`; counts: `COUNT(*)`. Missing values sort last ascending, first with `DESC`.

`§ ORDER BY`, `§ LIMIT and OFFSET` · Details: [reference/dql-reference.md](reference/dql-reference.md#order-by-limit-and-offset), [reference/query-optimization.md](reference/query-optimization.md#pagination)

### 10. Copy values out of query results right away (HIGH)

`items` is an `Iterable` that builds new wrappers on each pass; `mutatedDocumentIDs()` builds a new list per call.
**✅ DO**: iterate `items` once and convert rows to maps or models; project only the fields you need; track a `commitID` only when `mutatedDocumentIDs()` is not empty.
**❌ DON'T**: store `QueryResult` or `QueryResultItem` objects in state, caches, or across observer callbacks (they reference native memory).

`§ Working with Query Results` · Example: [query-result-handling.dart](examples/query-result-handling.dart) · Member table: [reference/query-optimization.md](reference/query-optimization.md#query-results)

### 11. Quote every key in inline object literals (HIGH)

Unquoted keys are rejected in `INSERT` and silently produce `{}` in `SELECT`; prefer document parameters. Backticks quote identifiers and reserved words (`collection`).

<!-- expect-error -->
```sql
-- ❌ BAD: Rejected ("Cannot convert to a literal")
INSERT INTO orders DOCUMENTS ({_id: 'order-1', status: 'open'})
```

✅ Quoted: `DOCUMENTS ({'_id': 'order-1', 'status': 'open'})`.

`§ Quote every key in inline object literals`, `§ Literals` · Details: [reference/dql-reference.md](reference/dql-reference.md#literals-and-identifiers)

### 12. Delete and evict by ID with WHERE (HIGH)

> **Note (SDK 5.1.0):** `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) completes without an error but removes nothing. Use `WHERE _id = :id` or `WHERE _id IN :ids`.

`DELETE` removes on all peers (tombstone); `EVICT` on this device only. Strategy: `storage-lifecycle`.

`§ DELETE and EVICT`

### 13. Use RETURNING instead of write-then-read (SDK 5.1+) (MEDIUM)

`RETURNING` on `INSERT`, `UPDATE`, `DELETE`, or `EVICT` returns the affected documents in `items` (after the update; before removal), e.g. `UPDATE orders SET status = :status WHERE _id IN :ids RETURNING _id, status`. Include `_id` in the projection when you need the IDs.

`§ RETURNING (SDK 5.1+)` · Details: [reference/dql-reference.md](reference/dql-reference.md#returning-sdk-51)

### 14. Repeat expressions in GROUP BY and HAVING (MEDIUM)

`GROUP BY` and `HAVING` cannot reference projection aliases (`ORDER BY` can); every non-aggregate projection must be a `GROUP BY` key. Aggregates other than `COUNT` return MISSING over zero rows: `ifmissing(SUM(total), 0)`. `COUNT(field)` skips `false`. No `DISTINCT` with `_id` or `*`.

`§ Aggregates`, `§ GROUP BY and HAVING` · Details: [reference/dql-reference.md](reference/dql-reference.md#projections-distinct-and-aggregates)

### 15. Use Differ only for item-level changes (MEDIUM)

`Differ` reports `insertions`, `deletions`, `updates`, and `moves` by `_id`; pass `result.items.toList()`. It is expensive, so bound diffed queries with `LIMIT`. A `ListView.builder` with `ValueKey(_id)` does not need it.

`§ Diffing Results` · Example: [observer-differ.dart](examples/observer-differ.dart)

### 16. Hand slow observer work to performance-observability (MEDIUM)

For slow or `async` per-update work, use `registerObserverV2` or `registerObserverWithSignalNext` **(Experimental, SDK 5.1+)**; details in `performance-observability`. JavaScript, Swift, and Kotlin observers differ ([reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md#other-platforms)).

`§ Backpressure (SDK 5.1+)`, `§ Backpressure on other platforms`, `§ Partial UI Updates` · Example: [observer-backpressure.dart](examples/observer-backpressure.dart)

## Checklist

- [ ] Values passed as `:parameters`; arrays as `IN :values` (no parentheses)
- [ ] Inline object literal keys quoted; documents passed as `DOCUMENTS (:doc)`
- [ ] Optional booleans filtered with `coalesce(field, false)`; existence tested with `IS [NOT] MISSING`
- [ ] No `ANY` or `EVERY ... SATISFIES` over a parameter or literal array in `WHERE`
- [ ] `ORDER BY` with `_id` tie-breaker wherever order matters; `LIMIT` combined with `ORDER BY`
- [ ] `GROUP BY` / `HAVING` repeat expressions; empty aggregates wrapped with `ifmissing`
- [ ] JOIN inner keys indexed (or joined on `_id`); fields qualified with aliases
- [ ] Upserts use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`; fields removed with `UNSET`
- [ ] `DELETE` / `EVICT` by ID use `WHERE _id IN :ids`
- [ ] Subscriptions: `SELECT *` on stable partition keys, owned by a service, cancelled on logout and before evicting, not re-registered for UI filters
- [ ] Observers registered in `initState()` or a service, without `onChange`; stream subscription and observer cancelled in `dispose()`
- [ ] Slow async observer work uses `registerObserverV2` or `registerObserverWithSignalNext` (Experimental), with `signalNext()` in `finally`
- [ ] Listener copies `item.value` into plain data; no `QueryResult` retained

## More

- Reference: [reference/dql-reference.md](reference/dql-reference.md) - literals, MISSING/NULL, USE IDS, aggregates, ORDER BY type order, JOIN, write semantics, RETURNING
- Reference: [reference/subscriptions-and-observers.md](reference/subscriptions-and-observers.md) - subscription errors, scope, lifecycle, observer APIs and lifecycle, backpressure, other platforms, Differ
- Reference: [reference/query-optimization.md](reference/query-optimization.md) - query result members, pagination, counting, index-friendly predicates, JOIN performance
- Examples: [examples/](examples/) - `-good` / `-bad` pairs of the same task
- Related skills: `data-modeling` (CRDT merge semantics), `storage-lifecycle` (DELETE/EVICT strategy), `performance-observability` (backpressure, partial UI updates, indexes, logging), `transactions-attachments`
