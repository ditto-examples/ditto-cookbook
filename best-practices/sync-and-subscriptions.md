# Sync and Subscriptions

Ditto uses **query-based sync**: subscriptions tell other peers which documents to send to this device, while `execute`, store observers, and transactions work on the **local store only**.

| API | Reads from | Causes data to sync to this device? |
|---|---|---|
| `ditto.sync.registerSubscription(query)` | Remote peers ("what I want other peers to send me") | ✅ Yes, while sync is running |
| `ditto.store.execute(query)` | Local store | ❌ No |
| `ditto.store.registerObserver(query)` | Local store (live) | ❌ No |
| `ditto.store.transaction(...)` | Local store | ❌ No |

Showing synced data therefore needs both a long-lived subscription, owned by an app-level or feature-level service (see [Subscription Lifecycle](#subscription-lifecycle)), and a local query or observer on the screen (see [Core Principles](../knowledge/understanding-ditto.md#core-principles) and [Where Queries Run](dql.md#where-queries-run)).

## Subscription Rules

A subscription query selects whole documents from one collection: `SELECT * FROM <collection> [WHERE <condition>]`. When you call `registerSubscription`, the SDK rejects the features below with an error, even before sync starts. Subscriptions on `system:` collections (such as `system:data_sync_info`) are accepted but have no effect.

| Query feature | Accepted in a subscription? | Error message |
|---|---|---|
| `SELECT * FROM orders` | ✅ Yes | — |
| `SELECT * FROM orders WHERE storeId = :storeId` | ✅ Yes (use parameters) | — |
| Projection (`SELECT _id, status ...`) or aggregate (`COUNT(*)`) | ❌ No | `Unsupported feature: A projection other than wildcard (*)` |
| `DISTINCT` (`SELECT DISTINCT * ...`) | ❌ No | `Unsupported feature: DISTINCT` |
| `GROUP BY` | ❌ No | `Unsupported feature: Grouping` |
| `JOIN` | ❌ No | `Unsupported feature: Joining` |
| `USE IDS` | ❌ No | `Unsupported feature: USE IDS` |
| `LIMIT`, `ORDER BY` | ❌ No (by default) | `Unsupported feature: Limit or Order by` |
| Non-`SELECT` statements | ❌ No | `Unsupported feature: non-SELECT statement in sync subscription` |

Consequences for your design:

- **Subscriptions always sync whole documents.** There is no way to subscribe to some fields of a document. To reduce what a device receives, split rarely needed data into a separate collection or move large binary data into [Attachments](attachments.md).
- **Subscriptions cannot join.** If a child collection must be filtered by a key that lives on the parent (for example, `orderItems` by `storeId`), copy that key into the child documents so that the child collection can be subscribed to on its own. `JOIN` remains available for local queries (see [Joining Collections (SDK 5.1+)](dql.md#joining-collections-sdk-51)).
- **`WHERE` follows the same rules as a local query.** A subscription filtered with `!=` or `NOT IN` does not receive documents in which the field is missing or `null` (see [MISSING and NULL](dql.md#missing-and-null)); on the other device, that looks like data that does not sync. In our testing with SDK 5.1.0 and 5.2.0, every condition we tried, including nested paths, `array_contains`, `lower()`, `LIKE`, `_id IN :ids`, and `_id.storeId = :storeId`, delivered exactly the documents that the same local query returned on the sending device. Add `OR field IS MISSING` when older documents may lack the field. A syntax error, a missing argument, or an unknown function throws when you register the subscription.
- **Use parameters**, never string interpolation, for values in the `WHERE` clause (see [Parameters and Literals](dql.md#parameters-and-literals)).

<!-- expect-error -->
```dart
// ❌ BAD: Each of these subscriptions is rejected when it is registered.
void registerInvalidSubscriptions(Ditto ditto) {
  // Projection: subscriptions always sync whole documents.
  ditto.sync.registerSubscription('SELECT _id, status FROM orders');
  // Aggregate.
  ditto.sync.registerSubscription('SELECT COUNT(*) AS n FROM orders');
  // LIMIT / ORDER BY are rejected by default (see below).
  ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC LIMIT 50',
    arguments: {'storeId': 'store-1'},
  );
  // USE IDS.
  ditto.sync.registerSubscription("SELECT * FROM orders USE IDS 'order-1', 'order-2'");
}
```

```dart
// ✅ GOOD: Filter with a WHERE clause and parameters; sort and limit locally.
SyncSubscription subscribeToStoreOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

Future<List<Map<String, dynamic>>> latestOrders(Ditto ditto, String storeId) async {
  // ORDER BY and LIMIT are fine in local queries.
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC LIMIT 50',
    arguments: {'storeId': storeId},
  );
  return result.items.map((item) => item.value).toList();
}
```

### LIMIT and ORDER BY in subscriptions

`LIMIT` and `ORDER BY` are rejected in subscriptions as long as the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` (note the plural; the name is case-insensitive) has its default value `true`. Setting it to `false` (for example, `ALTER SYSTEM SET DQL_RESTRICT_SUBSCRIPTIONS = false`) allows only `LIMIT` and `ORDER BY`; projections, aggregates, `DISTINCT`, `JOIN`, and `USE IDS` remain rejected.

**Keep the default.** A subscription with `LIMIT` (or `LIMIT` with `ORDER BY`) is a *stateful subscription*: the sync engine must track which documents currently fall inside the limit boundary. Whenever a document inside the boundary is deleted, stops matching the `WHERE` clause, or moves under the `ORDER BY`, Ditto has to invalidate its cache and re-evaluate the query, which degrades sync performance. If you must use one, avoid filtering (`WHERE`) or sorting (`ORDER BY`) on mutable fields. In most apps, a subscription scoped by a stable key plus a local `ORDER BY ... LIMIT` query gives the same UI without these costs.

> **Note (SDK 5.1.0 and 5.2.0):** `LIMIT` in a subscription bounds **only the initial download**. In our testing, the first sync delivered exactly the top N documents. After that, every new or changed document that matched the `WHERE` clause was synced, whether or not it ranked inside the window, including documents that never did. Documents already received stayed and kept receiving updates. Only documents that existed before the subscription started and were not changed afterwards were never synced. A "sync only the latest 50 orders" subscription therefore ends up syncing every matching order that is created or edited later. Bound the synced set with a `WHERE` on a stable key or a time window instead, keep `ORDER BY ... LIMIT` in the local query, and evict what the device no longer needs (see [EVICT](deletion-and-storage.md#evict)). `DQL_RESTRICT_SUBSCRIPTIONS` is checked only on the device that registers the subscription; the setting on the device that serves the data makes no difference.

### Scope subscriptions to what the device needs

**✅ DO:**
- Filter subscriptions by the dimensions that partition your data: tenant, store, region, team, or user.
- Use the same subscription shape on peers in the same role; when peers run the same subscription, any peer with matching documents can serve any other peer.
- Keep subscription predicates simple (flat comparisons such as `storeId = :storeId`); deeply nested `AND`/`OR` trees and deep object paths add server-side processing, and overly complex subscription queries are a likely cause of `503 Service Unavailable` errors from Ditto Server.

**❌ DON'T:**
- Subscribe to an entire large collection on every device "just in case".
- Generate subscription predicates dynamically from arrays or nested structures without reviewing the resulting query strings.

```dart
// ❌ BAD: Every device receives and stores every order of every tenant.
SyncSubscription subscribeToEverything(Ditto ditto) {
  return ditto.sync.registerSubscription('SELECT * FROM orders');
}

// ✅ GOOD: Each device receives only the orders of its own store.
SyncSubscription subscribeToStore(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}
```

**Why:** Subscriptions decide what crosses the network and what each device stores. A well-scoped subscription reduces bandwidth, storage, and CPU on every device in the mesh, and lets the sync engine prioritize the data that matters. An unfiltered subscription is acceptable only for a small reference-data collection that every device needs (for example, a short list of product categories).

Scope matters most when many devices reconnect at once with changes they made offline, for example at opening time or when the network comes back. If every device subscribes to everything, each device receives every other device's changes, so the time until all devices agree grows faster than their number. In our testing with SDK 5.1.0 and 5.2.0, with all devices on one 14-core Mac, 5 devices with 200 orders each agreed after about 0.3 seconds, 10 devices after about 1 second, 20 devices after about 4 seconds, and 20 devices with 1,000 orders each after about 17 seconds; documents written in the meantime waited behind the backlog. When each device subscribed only to its own orders, a shared total reached every device after 5 to 8 seconds instead of 11 to 18. No order and no counter increment was lost.

## Subscription Lifecycle

Registering, cancelling, or changing a subscription makes peers across the mesh re-evaluate which documents they must send to the device. **Avoid changing subscriptions more often than about every 15 minutes.** The guideline is about that re-evaluation work, not about data transfer: in our testing with SDK 5.1.0 and 5.2.0, documents the device already held were not downloaded again. An identical second registration transferred nothing, and re-registering after a cancel fetched only what had changed in between (1.6 KB, against 210 KB for the first download). Each registration is a separate object, though: data keeps syncing until **every** copy of an identical subscription is cancelled.

The re-evaluation reads the whole collection on each peer that holds the data, and an index for the subscription's filter does not shorten it (see [Where indexes live](indexing-and-performance.md#where-indexes-live)). Each new registration repeats it for all of the device's subscriptions together. In our testing with SDK 5.1.0 and 5.2.0, with 50,000 documents on a hub, a device's first subscription cost the hub about 0.1 seconds of CPU and its tenth about 0.2 seconds; a subscription filtered by `_id` cost the same as any other. Ten subscriptions registered together cost about a fifth of ten registered one at a time, and about a sixth when registered before `ditto.sync.start()`. Cancelling a subscription and reconnecting cost almost nothing.

**✅ DO:**
- Register subscriptions when the data first becomes relevant: at app start, after login, or when the user enters a workspace (store, region, team). Register the long-lived set together, before `ditto.sync.start()` where possible.
- Own subscriptions in an app-level or feature-level service, not in individual widgets.
- Keep a reference to every subscription you register, and call `cancel()` when its data is no longer relevant (logout, leaving a workspace) or when you register a replacement; subscriptions stay active until cancelled or until the `Ditto` instance is closed.
- Register the subscriptions again after every `Ditto.open()`, as part of your startup code. Subscriptions are not stored in the persistence directory. **Note (SDK 5.1.0 and 5.2.0):** in our testing, a device that reopened its directory without registering again still sent its own changes, but it received neither updates to documents it held nor new documents, without an error, so its screens kept showing old data. After it registered again, both arrived within about 0.1 seconds.
- Filter what the user sees with local queries and observers on top of a stable subscription.

**❌ DON'T:**
- Register subscriptions in `build()` or on every screen visit.
- Re-register a subscription with new arguments whenever the user changes a filter, search term, or sort order.
- Drop the reference to a subscription without cancelling it. Always release these objects explicitly; do not rely on garbage collection to cancel them.

```dart
// ✅ GOOD: A session-level service owns long-lived subscriptions.
class OrderSync {
  OrderSync(this._ditto);

  final Ditto _ditto;
  final List<SyncSubscription> _subscriptions = [];
  String? _storeId;

  /// Call once after login or when the user enters a store.
  void enterStore(String storeId) {
    if (storeId == _storeId) return; // Already subscribed; do not re-register.
    leaveStore();
    _storeId = storeId;
    // Scope by stable partition keys; the UI filters further with local queries.
    _subscriptions
      ..add(_ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ))
      ..add(_ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ));
  }

  /// Call on logout or when the user leaves the store.
  void leaveStore() {
    for (final subscription in _subscriptions) {
      subscription.cancel(); // No-op if already cancelled or Ditto was closed.
    }
    _subscriptions.clear();
    _storeId = null;
  }
}
```

```dart
// ❌ BAD: A new subscription on every rebuild, never cancelled.
class OrdersBadge extends StatelessWidget {
  const OrdersBadge({super.key, required this.ditto, required this.storeId});

  final Ditto ditto;
  final String storeId;

  @override
  Widget build(BuildContext context) {
    // build() can run many times per second; each call adds a subscription
    // that keeps replicating until the Ditto instance is closed.
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
    return const Icon(Icons.receipt_long);
  }
}
```

### Filter locally instead of re-registering

When the user changes a filter, change the **observer**, not the subscription. Observers are local and cheap to replace; subscriptions are mesh-wide.

```dart
// ✅ GOOD: The subscription (owned by OrderSync) stays stable; only the local observer changes.
class OrdersByStatus extends StatefulWidget {
  const OrdersByStatus({
    super.key,
    required this.ditto,
    required this.storeId,
    required this.status,
  });

  final Ditto ditto;
  final String storeId;
  final String status;

  @override
  State<OrdersByStatus> createState() => _OrdersByStatusState();
}

class _OrdersByStatusState extends State<OrdersByStatus> {
  StoreObserver? _observer;
  StreamSubscription<QueryResult>? _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observe();
  }

  @override
  void didUpdateWidget(OrdersByStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status || oldWidget.storeId != widget.storeId) {
      _stopObserving();
      _observe(); // Replacing a local observer is cheap.
    }
  }

  void _observe() {
    final observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id',
      arguments: {'storeId': widget.storeId, 'status': widget.status},
    );
    _observer = observer;
    _changes = observer.changes.listen((result) {
      setState(() {
        _orders = result.items.map((item) => item.value).toList();
      });
    });
  }

  void _stopObserving() {
    unawaited(_changes?.cancel());
    _observer?.cancel();
  }

  @override
  void dispose() {
    _stopObserving();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return ListTile(
            key: ValueKey(order['_id']),
            title: Text('${order['_id']}'),
            subtitle: Text('${order['status']}'),
          );
        },
      );
}
```

**When re-registering is right:** Change a subscription when the set of data the device *needs* changes, for example when the user switches to a different store or tenant. That happens rarely and fits the 15-minute guideline. Search boxes, tabs, filters, and sort orders should never change subscriptions.

### Cancelling subscriptions and local data

- **Cancelling does not delete local data.** Documents already received stay in the local store and remain visible to local queries. They stop receiving updates, new documents, and **deletions** from other peers, so a document deleted elsewhere after the cancel stays on this device. To free storage, evict them explicitly (see [EVICT](deletion-and-storage.md#evict)).
- **Overlapping subscriptions add up.** A device receives the union of all its active subscriptions. Cancelling one of them leaves the documents that another one still matches in sync.
- **Cancel before you evict.** Evicting documents that still match an active subscription is futile: connected peers notice that the device is missing documents it subscribes to and send them back. Stop the affected subscriptions *before* calling `EVICT`, including every overlapping subscription that also matches the documents: in our testing, a document that another active subscription still matched was synced back right after the `EVICT`.
- **Late arrivals:** Data that was already being transferred when you cancelled can still arrive afterwards. If the device must not keep the old store's data, run the eviction again later (for example, on the next app start or in a periodic cleanup).

```dart
// ✅ GOOD: Switching stores: cancel first, then evict data the device no longer needs.
Future<List<SyncSubscription>> switchStore(
  Ditto ditto,
  List<SyncSubscription> currentSubscriptions,
  String newStoreId,
) async {
  // 1. Stop asking for the old store's data.
  for (final subscription in currentSubscriptions) {
    subscription.cancel();
  }

  // 2. Remove the old store's documents from this device only.
  await ditto.store.execute(
    'EVICT FROM orders WHERE storeId != :storeId',
    arguments: {'storeId': newStoreId},
  );
  await ditto.store.execute(
    'EVICT FROM orderItems WHERE storeId != :storeId',
    arguments: {'storeId': newStoreId},
  );

  // 3. Ask for the new store's data.
  return [
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': newStoreId},
    ),
    ditto.sync.registerSubscription(
      'SELECT * FROM orderItems WHERE storeId = :storeId',
      arguments: {'storeId': newStoreId},
    ),
  ];
}
```

### Sync stop, close, and inspection

- `ditto.sync.stop()` disconnects from all peers and **pauses** all subscriptions. You do not need to cancel subscriptions to stop syncing; they resume when you call `ditto.sync.start()` again.
- `await ditto.close()` stops sync and marks every subscription as cancelled (`isCancelled == true`); calling `cancel()` afterwards is a safe no-op (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).
- `ditto.sync.subscriptions` returns the currently active subscriptions. Use it for debugging (for example, logging `queryString`), but manage subscriptions through the references you keep yourself.

> **Note (SDK 5.1.0):** Do not read `queryArguments` or `queryArgumentsJsonString` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this can terminate a Flutter app (in our testing, the JavaScript SDK 5.1.0 and 5.2.0 returned `null` instead). Read only `queryString` and `isCancelled` there, and keep your own references (as `OrderSync` does) when you need the arguments.

## Scope Balancing

Subscription scope is a trade-off. Too broad wastes resources; too narrow can leave devices without data they need, especially in peer-to-peer meshes.

| | Too broad | Too narrow |
|---|---|---|
| Symptoms | High storage use, long initial sync, battery and bandwidth drain | Missing data on devices that are not directly connected to the source, data appearing late |
| Typical cause | Unfiltered subscriptions on large collections | Filters on fields that change often, or relay devices that subscribe to less than the devices behind them |
| Fix | Filter by stable partition keys (tenant, store, region) | Subscribe to the full partition; filter further with local queries |

### Multi-hop relay

Ditto can relay documents through intermediate devices that are not directly connected to each other. Ditto's [multi-hop sync documentation](https://docs.ditto.live/home/glossary#multi-hop-sync) states that an intermediate device **can only relay documents it has in its local store**: if its subscription is too narrow, it does not store certain documents and cannot pass them on.

The same limit applies to transactions: a device connected only through a relay with narrower subscriptions can receive only part of a multi-document transaction (see [Transactions and Sync](transactions.md#transactions-and-sync) for an example).

In a mesh, a device receives each new document from most of its directly connected peers. In our testing with SDK 5.1.0 and 5.2.0, six peers connected to each other over TCP each received each new document 3 to 5 times, also when the documents were written 45 seconds apart, and the mesh carried 3.5 to 5 times the bytes of a hub layout; in a hub layout or a line, each device received each document once. Updates of existing documents were duplicated less (about 1.6 times). Where many devices share a narrow link, a layout with a fixed hub uses the link more efficiently than one in which every device connects to every other.

**✅ DO:**
- Give devices in the same role the same subscriptions, so that each of them can serve the others.
- On devices that act as relays or hubs (for example, a fixed tablet that many handhelds connect to), subscribe to at least everything the devices behind them need.
- On a hub that more than six devices connect to over TCP, raise the per-transport connection limit before starting sync (see [Transport Configuration](setup-and-lifecycle.md#transport-configuration)).
- Filter subscriptions on stable fields that do not change during a document's lifetime (`storeId`, `tenantId`, `region`).
- Ensure sufficient connectivity with peers that have broader subscription sets.

**❌ DON'T:**
- Give a relay device a narrower subscription than the devices that depend on it.
- Filter subscriptions on fields that change often (`status`, `assignee`) and expect every device to follow each document through all of its states (soft-delete flags are a special case; see the next paragraph).

> **Note (SDK 5.1.0 and 5.2.0):** A document that stops matching a subscription becomes a **frozen copy** on the device. In our testing, the device received the change that made the document stop matching (for example, `status: 'closed'`) but nothing after it: neither later edits nor the deletion of the document arrived. Local queries keep returning the stale copy. When the document matches again, it arrives in its latest state. Filter such documents out locally, and evict them when the device no longer needs them.

**Soft delete:** A device whose subscription excludes soft-deleted documents still receives the flag and a later restore for documents it holds, but it cannot relay the flag for documents it did not already hold, and a `DELETE` of a flagged document does not reach it. Keep soft-deleted documents in the subscriptions of devices that relay data, and filter them out in local queries. See [Soft delete, subscriptions, and cleanup](deletion-and-storage.md#soft-delete-subscriptions-and-cleanup) for the subscription variants and how each affects cleanup.

## Sync Scopes

Sync scopes control, per collection, **where a device sends** its documents. They are configured with the system parameter `USER_COLLECTION_SYNC_SCOPES`, which maps collection names to one of these values:

| Sync scope | Behavior |
|---|---|
| `"AllPeers"` (default) | Sync with Ditto Server and with other Small Peers |
| `"BigPeerOnly"` | Sync only with Ditto Server, not with other Small Peers |
| `"SmallPeersOnly"` | Sync only with other Small Peers, not with Ditto Server |
| `"LocalPeerOnly"` | Do not sync this collection at all |

```sql
ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = {'localDrafts': 'LocalPeerOnly', 'kitchenTickets': 'SmallPeersOnly'}
```

```dart
// ✅ GOOD: Pass sync scopes in the configuration on every open (SDK 5.2+),
// so that they are in effect before sync starts.
const scopedConfig = DittoConfig(
  databaseID: 'YOUR_DATABASE_ID',
  connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
  systemParameters: {
    'USER_COLLECTION_SYNC_SCOPES': {
      'localDrafts': 'LocalPeerOnly',
      'kitchenTickets': 'SmallPeersOnly',
    },
  },
);
```

**✅ DO:**
- Set `USER_COLLECTION_SYNC_SCOPES` on every open, so that it is in effect **before** `ditto.sync.start()`: in `DittoConfig.systemParameters` (SDK 5.2+), or on SDK 5.1 with `ALTER SYSTEM` after `Ditto.open`. System parameters are not persisted, and setting scopes late can let data sync unintentionally (see [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters)).
- Apply the same sync scopes on **every** device that can store the collection (devices that write it, subscribe to it, or relay it); a scope is checked by the device that sends the data, so a device without the setting can send the collection to Ditto Server. A scope also does not stop a device from *receiving* the collection from devices without it.
- Remember that a scope set while sync is running applies to later changes immediately, without a restart. Copies that other devices already received stay there as frozen copies: in our testing with SDK 5.1.0 and 5.2.0, they received no further updates.
- Quote the collection names (map keys) in the literal, or build the statement from a reviewed constant.
- List every scoped collection in one map: each `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` replaces the whole map, so collections left out of a later statement lose their scope (in our testing, their sync resumed immediately).

**❌ DON'T:**
- Treat sync scopes as an access-control mechanism; they control what *this* device sends, not what other devices are allowed to read (use permissions for that, see [Security](security.md)).
- Apply sync scopes to system collections (names starting with `__`); the update fails.
- Rely on sync scopes for remote query requests; they are not enforced there.

**Why:** Sync scopes and subscriptions are complementary. Subscriptions decide what a device *receives*; sync scopes limit where a device *sends* data, even if another peer subscribes to it. Typical uses are device-local drafts and caches (`LocalPeerOnly`) and high-frequency, mesh-local data such as kitchen display tickets (`SmallPeersOnly`).

## Monitoring Sync Status

Ditto is offline-first, so there is no single "synced" state. You can still show users useful progress information with two building blocks:

1. **Commit IDs:** every local `INSERT`, `UPDATE`, `DELETE`, or `EVICT` returns a `commitID` on its `QueryResult` (`int?` in Flutter). Commit IDs are device-specific and increase monotonically. `SELECT` returns `null`, and inside a transaction the value is only assigned after the commit.
2. **`system:data_sync_info`:** a local-only virtual collection with one document per peer connection.

| Field | Meaning |
|---|---|
| `_id` | Peer identifier |
| `is_ditto_server` | `true` for Ditto Server connections |
| `documents.sync_session_status` | `"Connected"`, `"Not Connected"`, or `"Disabled"` |
| `documents.synced_up_to_local_commit_id` | Highest local commit ID that this peer has confirmed |
| `documents.last_update_received_time` | Unix timestamp of the last data received from this peer |

A local write has reached a peer when that peer's `synced_up_to_local_commit_id` is greater than or equal to the write's `commitID`.

> **Note (SDK 5.1.0 and 5.2.0):** A statement that changes nothing still returns a `commitID`. Examples are `ON ID CONFLICT DO NOTHING` or `DO UPDATE_LOCAL_DIFF` on an existing document, and an `UPDATE` whose `WHERE` matches nothing. In our testing with SDK 5.1.0 and 5.2.0, peers did not confirm such an empty commit on its own; `synced_up_to_local_commit_id` passes it only with the next commit that syncs. Besides your own writes, Ditto makes an internal commit about every 30 seconds, so waiting for such an ID to be confirmed can take up to about 30 seconds instead of completing immediately (on 5.2.0, it was often confirmed within a few seconds). Track a `commitID` only when `mutatedDocumentIDs()` is not empty.

> **Note (SDK 5.1.0 and 5.2.0):** `sync_session_status` reacts slowly to disconnections. In our testing, the row stayed `"Connected"` on both devices for about 73 seconds after one peer closed Ditto or called `ditto.sync.stop()`, while the presence graph dropped the peer immediately. Use `sync_session_status` for upload progress, and use [Presence](setup-and-lifecycle.md#presence) for "connected now" indicators.

```sql
SELECT * FROM system:data_sync_info WHERE is_ditto_server = true
```

**✅ DO:**
- Use sync status to **enhance** the user experience (an "uploaded" check mark, a pending-changes badge), never to block the user from working.
- Query `system:data_sync_info` with `execute` when you need a snapshot (for example, when the user opens a status screen).
- Keep observer callbacks on `system:data_sync_info` trivial and update the UI only when the derived value actually changes.
- Track only the commit IDs that matter (payments, submitted forms) and forget them once confirmed. Wait for such an ID before you close Ditto at a point where the write must reach another device; closing does not wait for changes that are still being sent (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).
- Check `mutatedDocumentIDs()` before tracking a `commitID`; skip statements that changed nothing.

**❌ DON'T:**
- Register observers on `system:data_sync_info` in many widgets. Each one re-reads the sync state of every connection. How often they fire varies: with SDK 5.1.0 (Flutter and JavaScript) we observed an idle observer firing only when the rows changed, about once every 10 seconds, and for SDK 5.2 the Ditto documentation no longer lists `system:data_sync_info` among the collections whose observers run on a timer (older documentation described a 500 ms interval). Write code that works with either behavior.
- Do heavy work (JSON decoding of large structures, database writes, network calls) in such an observer.
- Register subscriptions on `system:data_sync_info`; it is local-only, so such a subscription is accepted but has no effect.
- Expect `system:data_sync_info` on platforms with in-memory storage such as web browsers.
- Expect attachment transfer progress here; `system:data_sync_info` does not report it (use the fetch events, see [Attachments](attachments.md)).

```dart
// ✅ GOOD: One lightweight observer that only rebuilds when the derived state changes.
// Use one instance per screen (for example, in the app bar), not one per list row.
class UploadStatusIcon extends StatefulWidget {
  const UploadStatusIcon({super.key, required this.ditto, required this.commitId});

  final Ditto ditto;

  /// The commitID returned by the write you want to track.
  final int commitId;

  @override
  State<UploadStatusIcon> createState() => _UploadStatusIconState();
}

class _UploadStatusIconState extends State<UploadStatusIcon> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  bool _uploaded = false;

  @override
  void initState() {
    super.initState();
    // May fire often, so keep the callback trivial.
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM system:data_sync_info WHERE is_ditto_server = true',
    );
    _changes = _observer.changes.listen((result) {
      final uploaded = result.items.any((item) {
        final documents = item.value['documents'];
        if (documents is! Map) return false;
        final synced = documents['synced_up_to_local_commit_id'];
        return synced is int && synced >= widget.commitId;
      });
      if (uploaded != _uploaded) {
        setState(() => _uploaded = uploaded); // Rebuild only on a real change.
      }
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Icon(_uploaded ? Icons.cloud_done : Icons.cloud_upload_outlined);
}
```

```dart
// Obtain the commit ID from the write you want to track.
Future<int?> submitOrder(Ditto ditto, Map<String, dynamic> order) async {
  final result = await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {'order': order},
  );
  return result.commitID; // null for SELECT; set for local writes.
}
```

```dart
// ✅ GOOD: Track the commitID only if the upsert actually changed the document.
Future<int?> saveSettings(Ditto ditto, Map<String, dynamic> settings) async {
  final result = await ditto.store.execute(
    'INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'settings': settings},
  );
  // An unchanged document still gets a commitID, but peers confirm it only
  // with a later commit (up to about 30 seconds later).
  return result.mutatedDocumentIDs().isEmpty ? null : result.commitID;
}
```

**Why:** `system:data_sync_info` is cheap to read, but the Ditto documentation describes observers on it as timer-driven. A single small observer per relevant screen is fine; dozens of observers that may rebuild widgets twice per second are not. For connectivity information (which peers are nearby, whether Ditto Server is connected), use the presence API instead (see [Presence](setup-and-lifecycle.md#presence)).
