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

In our testing, every row of this table held on SDK 5.1.0 and 5.2.0 (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

Consequences for your design:

- **Subscriptions always sync whole documents.** There is no way to subscribe to some fields of a document. To reduce what a device receives, split rarely needed data into a separate collection or move large binary data into [Attachments](attachments.md).
- **Subscriptions cannot join.** If a child collection must be filtered by a key that lives on the parent (for example, `orderItems` by `storeId`), copy that key into the child documents so that the child collection can be subscribed to on its own. `JOIN` remains available for local queries (see [Joining Collections (SDK 5.1+)](dql.md#joining-collections-sdk-51)).
- **`WHERE` follows the same rules as a local query.** A subscription filtered with `!=` or `NOT IN` does not receive documents in which the field is missing or `null` (see [MISSING and NULL](dql.md#missing-and-null)); on the other device, that looks like data that does not sync. In our testing, every condition we tried delivered exactly the documents that the same local query returned on the sending device (see [The sending peer evaluates a subscription's WHERE clause like a local query](../knowledge/observations/subscriptions-and-replication.md#the-sending-peer-evaluates-a-subscriptions-where-clause-like-a-local-query)). Add `OR field IS MISSING` when older documents may lack the field. A syntax error, a missing argument, or an unknown function throws when you register the subscription.
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

`LIMIT` and `ORDER BY` are rejected in subscriptions as long as the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` (note the plural; the name is case-insensitive) has its default value `true`. Setting it to `false` (for example, `ALTER SYSTEM SET DQL_RESTRICT_SUBSCRIPTIONS = false`) allows only `LIMIT` and `ORDER BY`; projections, aggregates, `DISTINCT`, `JOIN`, and `USE IDS` remain rejected (see [The single-store DQL tables held on SDK 5.1.0 and 5.2.0](../knowledge/observations/dql-behavior.md#the-single-store-dql-tables-held-on-sdk-510-and-520)).

**Keep the default.** A subscription with `LIMIT` (or `LIMIT` with `ORDER BY`) is a *stateful subscription*: the sync engine must track which documents currently fall inside the limit boundary. Whenever a document inside the boundary is deleted, stops matching the `WHERE` clause, or moves under the `ORDER BY`, Ditto has to invalidate its cache and re-evaluate the query, which degrades sync performance. If you must use one, avoid filtering (`WHERE`) or sorting (`ORDER BY`) on mutable fields. In most apps, a subscription scoped by a stable key plus a local `ORDER BY ... LIMIT` query gives the same UI without these costs.

> **Note (SDK 5.1.0 and 5.2.0):** `LIMIT` in a subscription bounds **only the initial download**. In our testing, the first sync delivered exactly the top N documents, and after that every new or changed document that matched the `WHERE` clause was synced, whether or not it ranked inside the window (see [A LIMIT in a subscription limits only the first download](../knowledge/observations/subscriptions-and-replication.md#a-limit-in-a-subscription-limits-only-the-first-download)). A "sync only the latest 50 orders" subscription therefore ends up syncing every matching order that is created or edited later. Bound the synced set with a `WHERE` on a stable key or a time window instead, keep `ORDER BY ... LIMIT` in the local query, and evict what the device no longer needs (see [EVICT](deletion-and-storage.md#evict)). `DQL_RESTRICT_SUBSCRIPTIONS` is checked only on the device that registers the subscription; the setting on the device that serves the data makes no difference.

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

**Why:** Subscriptions decide what crosses the network and what each device stores. A well-scoped subscription reduces bandwidth, storage, and CPU on every device in the mesh. It does not give some data priority over other data: see the large initial sync in [Subscription Lifecycle](#subscription-lifecycle) and [A large initial sync holds up the device's other sync](../knowledge/observations/subscriptions-and-replication.md#a-large-initial-sync-holds-up-the-devices-other-sync). An unfiltered subscription is acceptable only for a small reference-data collection that every device needs (for example, a short list of product categories).

Scope matters most when many devices reconnect at once with changes they made offline, for example at opening time or when the network comes back. If every device subscribes to everything, each device receives every other device's changes, so the time until all devices agree grows faster than their number: in our testing, from about 0.3 seconds with 5 devices to about 4 seconds with 20, and documents written in the meantime waited behind the backlog. When each device subscribed only to its own orders, a shared total reached every device about twice as fast (see [Convergence after simultaneous reconnects grew faster than the number of devices](../knowledge/observations/subscriptions-and-replication.md#convergence-after-simultaneous-reconnects-grew-faster-than-the-number-of-devices)).

## Subscription Lifecycle

Registering, cancelling, or changing a subscription makes peers across the mesh re-evaluate which documents they must send to the device. **Avoid changing subscriptions more often than about every 15 minutes.** The guideline is about that re-evaluation work, not about data transfer: in our testing, documents the device already held were not downloaded again, an identical second registration transferred nothing, and re-registering after a cancel fetched only what had changed in between (see [Sync traffic is compressed and carries field-level changes](../knowledge/observations/subscriptions-and-replication.md#sync-traffic-is-compressed-and-carries-field-level-changes)). Each registration is a separate object, though: data keeps syncing until **every** copy of an identical subscription is cancelled (see [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)).

The re-evaluation reads the whole collection on each peer that holds the data, and an index for the subscription's filter does not shorten it (see [Where indexes live](indexing-and-performance.md#where-indexes-live)). Each new registration repeats it for all of the device's subscriptions together, also for a subscription filtered by `_id`; in our testing, ten subscriptions registered together cost the hub about a fifth of ten registered one at a time, and cancelling and reconnecting cost almost nothing (see [Each new subscription makes the data holder read the whole collection](../knowledge/observations/subscriptions-and-replication.md#each-new-subscription-makes-the-data-holder-read-the-whole-collection)). The number of subscriptions did not change what was transferred (see [The number of subscriptions did not change the transfer](../knowledge/observations/subscriptions-and-replication.md#the-number-of-subscriptions-did-not-change-the-transfer)), so keep subscriptions few to keep them manageable (each one must be cancelled), not to save bandwidth.

> **Note (SDK 5.1.0 and 5.2.0):** While a device receives the initial sync of a large subscription, its other sync waits until that sync is done: changes for its existing subscriptions and its own writes to other devices. In our testing, an initial sync of 30,000 documents held up other changes on that device for about 2 seconds, while other devices kept syncing normally; registering the parts of a split subscription one after another kept other changes within about one second, but the whole download took about 2.5 times as long (see [A large initial sync holds up the device's other sync](../knowledge/observations/subscriptions-and-replication.md#a-large-initial-sync-holds-up-the-devices-other-sync)). If the app must exchange orders or notifications while it downloads a large data set after login, register the large subscription in parts that way, as a one-time step at startup, or start it when the user is less active.

> **Note (SDK 5.1.0 and 5.2.0):** The receiving device shows an initial sync all at once, not document by document, and an interrupted initial sync resumes where it stopped (see [An initial sync appears on the receiving device all at once](../knowledge/observations/subscriptions-and-replication.md#an-initial-sync-appears-on-the-receiving-device-all-at-once) and [An interrupted initial sync resumes where it stopped](../knowledge/observations/subscriptions-and-replication.md#an-interrupted-initial-sync-resumes-where-it-stopped)). While a large subscription first syncs, show that data is downloading rather than a document count.

**✅ DO:**
- Register subscriptions when the data first becomes relevant: at app start, after login, or when the user enters a workspace (store, region, team). Register the long-lived set together, before `ditto.sync.start()` where possible.
- Own subscriptions in an app-level or feature-level service, not in individual widgets.
- Keep a reference to every subscription you register, and call `cancel()` when its data is no longer relevant (logout, leaving a workspace) or when you register a replacement; subscriptions stay active until cancelled or until the `Ditto` instance is closed.
- Register the subscriptions again after every `Ditto.open()`, as part of your startup code. Subscriptions are not stored in the persistence directory. **Note (SDK 5.1.0 and 5.2.0):** in our testing, a device that reopened its directory without registering again still sent its own changes, but it received neither updates to documents it held nor new documents, without an error, so its screens kept showing old data (see [Subscriptions are not stored in the persistence directory](../knowledge/observations/subscriptions-and-replication.md#subscriptions-are-not-stored-in-the-persistence-directory)).
- Filter what the user sees with local queries and observers on top of a stable subscription.

**❌ DON'T:**
- Register subscriptions in `build()` or on every screen visit.
- Re-register a subscription with new arguments whenever the user changes a filter, search term, or sort order.
- Drop the reference to a subscription without cancelling it. Always release these objects explicitly; do not rely on garbage collection to cancel them. In our testing with the JavaScript SDK, subscriptions and observers whose objects had been garbage-collected kept syncing and kept calling back, and only the entries of `ditto.sync.subscriptions` and `ditto.store.observers` could still cancel them (see [In JavaScript, garbage-collected subscriptions and observers keep running](../knowledge/observations/observer-behavior.md#in-javascript-garbage-collected-subscriptions-and-observers-keep-running)).

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

- **Cancelling does not delete local data.** Documents already received stay in the local store and remain visible to local queries (see [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)). They stop receiving updates, new documents, and **deletions** from other peers, so a document deleted elsewhere after the cancel stays on this device. To free storage, evict them explicitly (see [EVICT](deletion-and-storage.md#evict)).
- **Overlapping subscriptions add up.** A device receives the union of all its active subscriptions. Cancelling one of them leaves the documents that another one still matches in sync.
- **Cancel before you evict.** Evicting documents that still match an active subscription is futile: connected peers notice that the device is missing documents it subscribes to and send them back. Stop the affected subscriptions *before* calling `EVICT`, including every overlapping subscription that also matches the documents: in our testing, documents that an active subscription still matched were downloaded again within seconds (see [Deletion flags and DELETE transfer little, and eviction under a subscription refetches](../knowledge/observations/storage-and-deletion.md#deletion-flags-and-delete-transfer-little-and-eviction-under-a-subscription-refetches)).
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

- `ditto.sync.stop()` disconnects from all peers and **pauses** all subscriptions. You do not need to cancel subscriptions to stop syncing; they resume when you call `ditto.sync.start()` again (see [Starting and stopping sync behaved as documented](../knowledge/observations/subscriptions-and-replication.md#starting-and-stopping-sync-behaved-as-documented)).
- `await ditto.close()` stops sync and marks every subscription as cancelled (`isCancelled == true`); calling `cancel()` afterwards is a safe no-op (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown)).
- `ditto.sync.subscriptions` returns the currently active subscriptions. Use it for debugging (for example, logging `queryString`), but manage subscriptions through the references you keep yourself.

> **Note (SDK 5.1.0):** Do not read `queryArguments` or `queryArgumentsJsonString` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this can terminate a Flutter app (in our testing, the JavaScript SDK returned `null` instead; see [In JavaScript, queryArguments of a subscription without arguments is empty](../knowledge/observations/subscriptions-and-replication.md#in-javascript-queryarguments-of-a-subscription-without-arguments-is-empty)). Read only `queryString` and `isCancelled` there, and keep your own references (as `OrderSync` does) when you need the arguments.

## Scope Balancing

Subscription scope is a trade-off. Too broad wastes resources; too narrow can leave devices without data they need, especially in peer-to-peer meshes.

| | Too broad | Too narrow |
|---|---|---|
| Symptoms | High storage use, long initial sync, battery and bandwidth drain | Missing data on devices that are not directly connected to the source, data appearing late |
| Typical cause | Unfiltered subscriptions on large collections | Filters on fields that change often, or relay devices that subscribe to less than the devices behind them |
| Fix | Filter by stable partition keys (tenant, store, region) | Subscribe to the full partition; filter further with local queries |

### Multi-hop relay

Ditto can relay documents through intermediate devices that are not directly connected to each other. Ditto's [multi-hop sync documentation](https://docs.ditto.live/home/glossary#multi-hop-sync) states that an intermediate device **can only relay documents it has in its local store**: if its subscription is too narrow, it does not store certain documents and cannot pass them on (see [A relay forwards only the documents that it holds](../knowledge/observations/subscriptions-and-replication.md#a-relay-forwards-only-the-documents-that-it-holds)).

The same limit applies to transactions: a device connected only through a relay with narrower subscriptions can receive only part of a multi-document transaction (see [Transactions and Sync](transactions.md#transactions-and-sync) for an example).

In a mesh, a device receives each new document from most of its directly connected peers. In our testing, six peers connected to each other over TCP each received each new document 3 to 5 times, and the mesh carried 3.5 to 5 times the bytes of a hub layout, while in a hub layout or a line each device received each document once (see [In a mesh, a new document arrives once from each neighbor](../knowledge/observations/subscriptions-and-replication.md#in-a-mesh-a-new-document-arrives-once-from-each-neighbor)). The number of hops itself cost little: a document crossed a line of 20 peers on one machine in 0.12 to 0.18 seconds (see [Presence and sync work across a chain of 20 devices](../knowledge/observations/connections-and-presence.md#presence-and-sync-work-across-a-chain-of-20-devices) and [Each relay hop added about 4 ms](../knowledge/observations/subscriptions-and-replication.md#each-relay-hop-added-about-4-ms)); on real devices, each hop adds its network round trip. Where many devices share a narrow link, a layout with a fixed hub uses the link more efficiently than one in which every device connects to every other.

**✅ DO:**
- Give devices in the same role the same subscriptions, so that each of them can serve the others.
- On devices that act as relays or hubs (for example, a fixed tablet that many handhelds connect to), subscribe to at least everything the devices behind them need. A device that subscribes to nothing relays nothing, so if you add a second relay for redundancy, give it the same subscriptions; in our testing, updates kept flowing through the remaining relay when one stopped or crashed (see [With two relays, sync continued when one of them stopped](../knowledge/observations/subscriptions-and-replication.md#with-two-relays-sync-continued-when-one-of-them-stopped)).
- Count on carriers too. Relays do not need to be connected at the same time: a device that moves between two sites that never connect carries the documents and deletions that match its own subscriptions to the next site it visits, regardless of what the destination subscribes to, and a visit that ends before a large initial sync completes carries nothing (in our testing; see [Devices that move between sites carry documents and deletions](../knowledge/observations/subscriptions-and-replication.md#devices-that-move-between-sites-carry-documents-and-deletions)).
- On a hub that more than six devices connect to over TCP, raise the per-transport connection limit before starting sync (see [Transport Configuration](setup-and-lifecycle.md#transport-configuration), [A device accepts six TCP connections by default](../knowledge/observations/connections-and-presence.md#a-device-accepts-six-tcp-connections-by-default), and [Raising the TCP limit takes effect only before sync starts](../knowledge/observations/connections-and-presence.md#raising-the-tcp-limit-takes-effect-only-before-sync-starts)).
- Filter subscriptions on stable fields that do not change during a document's lifetime (`storeId`, `tenantId`, `region`).
- Ensure sufficient connectivity with peers that have broader subscription sets.

**❌ DON'T:**
- Give a relay device a narrower subscription than the devices that depend on it.
- Filter subscriptions on fields that change often (`status`, `assignee`) and expect every device to follow each document through all of its states (soft-delete flags are a special case; see the next paragraph).

> **Note (SDK 5.1.0 and 5.2.0):** A document that stops matching a subscription becomes a **frozen copy** on the device. In our testing, the device received the change that made the document stop matching (for example, `status: 'closed'`) but nothing after it: neither later edits nor the deletion of the document arrived (see [Documents that leave a subscription stay as frozen copies](../knowledge/observations/subscriptions-and-replication.md#documents-that-leave-a-subscription-stay-as-frozen-copies)). Local queries keep returning the stale copy. When the document matches again, it arrives in its latest state. Filter such documents out locally, and evict them when the device no longer needs them.

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
- Remember that a scope set while sync is running applies to later changes immediately, without a restart. Copies that other devices already received stay there as frozen copies, with no further updates (in our testing; see [Sync scopes behaved as documented on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#sync-scopes-behaved-as-documented-on-sdk-510-and-520)).
- Quote the collection names (map keys) in the literal, or build the statement from a reviewed constant.
- List every scoped collection in one map: each `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` replaces the whole map, so collections left out of a later statement lose their scope, and their sync resumes immediately (in our testing; see [Sync scopes behaved as documented on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#sync-scopes-behaved-as-documented-on-sdk-510-and-520)).

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

> **Note (SDK 5.1.0 and 5.2.0):** A statement that changes nothing still returns a `commitID`. Examples are `ON ID CONFLICT DO NOTHING` or `DO UPDATE_LOCAL_DIFF` on an existing document, and an `UPDATE` whose `WHERE` matches nothing. In our testing, peers did not confirm such an empty commit on its own: `synced_up_to_local_commit_id` passed it only with the next sync exchange between the devices, up to about 27 seconds later, although on 5.2.0 often within a few seconds (see [An empty commit is confirmed only with the next sync exchange](../knowledge/observations/subscriptions-and-replication.md#an-empty-commit-is-confirmed-only-with-the-next-sync-exchange)). Track a `commitID` only when `mutatedDocumentIDs()` is not empty.

> **Note (SDK 5.1.0 and 5.2.0):** `sync_session_status` reacts slowly to disconnections. In our testing, the row stayed `"Connected"` for about 73 seconds after the other peer closed Ditto or called `ditto.sync.stop()`, while the presence graph dropped the peer within about 0.1 seconds (see [The sync session status lags about 73 seconds behind a disconnection](../knowledge/observations/subscriptions-and-replication.md#the-sync-session-status-lags-about-73-seconds-behind-a-disconnection)); a peer that stopped responding without closing its connection left the presence graph after about 7 to 9 seconds (see [A silent network outage removes a peer after about 7 seconds](../knowledge/observations/connections-and-presence.md#a-silent-network-outage-removes-a-peer-after-about-7-seconds) and [A suspended device leaves the presence graph after about 9 seconds](../knowledge/observations/connections-and-presence.md#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds)). Use `sync_session_status` for upload progress, and use [Presence](setup-and-lifecycle.md#presence) for "connected now" indicators.

```sql
SELECT * FROM system:data_sync_info WHERE is_ditto_server = true
```

**✅ DO:**
- Use sync status to **enhance** the user experience (an "uploaded" check mark, a pending-changes badge), never to block the user from working.
- Query `system:data_sync_info` with `execute` when you need a snapshot (for example, when the user opens a status screen).
- Keep observer callbacks on `system:data_sync_info` trivial and update the UI only when the derived value actually changes.
- Track only the commit IDs that matter (payments, submitted forms) and forget them once confirmed. Wait for such an ID before you close Ditto at a point where the write must reach another device; closing does not wait for changes that are still being sent (see [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown) and [A write made right before close or stop may not leave the device](../knowledge/observations/subscriptions-and-replication.md#a-write-made-right-before-close-or-stop-may-not-leave-the-device)).
- Check `mutatedDocumentIDs()` before tracking a `commitID`; skip statements that changed nothing.

**❌ DON'T:**
- Register observers on `system:data_sync_info` in many widgets. Each one re-reads the sync state of every connection. How often they fire varies: Ditto's page on monitoring sync status describes a callback every 500 ms, while its virtual collections reference does not list `system:data_sync_info` among the collections whose observers run on a timer. In our testing with SDK 5.1.0 and 5.2.0, an observer with one idle peer was called 3 or 4 times in 40 seconds, the last time about 27 seconds after registration (see [An observer of system:data_sync_info fired about every 27 seconds with an idle peer](../knowledge/observations/observer-behavior.md#an-observer-of-systemdata_sync_info-fired-about-every-27-seconds-with-an-idle-peer)). Write code that works with either behavior.
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
  // with their next sync exchange (up to about 27 seconds later).
  return result.mutatedDocumentIDs().isEmpty ? null : result.commitID;
}
```

**Why:** `system:data_sync_info` is cheap to read, but every callback re-reads the row of every connection, and Ditto's documentation allows these observers to fire every 500 ms. A single small observer per relevant screen is fine; dozens of observers that may rebuild widgets twice per second are not. For connectivity information (which peers are nearby, whether Ditto Server is connected), use the presence API instead (see [Presence](setup-and-lifecycle.md#presence)).
