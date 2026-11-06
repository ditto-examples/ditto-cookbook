# Quick Reference

A condensed summary of the main recommendations. Follow the links for the reasoning and complete examples.

## DO

**Setup and lifecycle** ([SDK Setup and Lifecycle](setup-and-lifecycle.md))
- ✅ Open one `Ditto` instance per persistence directory and share it.
- ✅ For Ditto Server connections, set the expiration handler before `ditto.sync.start()`; check `response.exception` and never throw in the handler.
- ✅ Pass system parameters in `DittoConfig.systemParameters` on every open (SDK 5.2+); use `ALTER SYSTEM` only for values that change while the app runs.
- ✅ Configure `DittoLogger` after `await Ditto.init()` and before `Ditto.open()`.
- ✅ Cancel observers and subscriptions, stop fetchers, and await pending work before `await ditto.close()`; where a write must reach another device, wait until it is confirmed.
- ✅ On a shared device, sign a user out in the order of [Switching users on a shared device](setup-and-lifecycle.md#switching-users-on-a-shared-device).

**Data modeling** ([Data Modeling](data-modeling.md))
- ✅ Update fields, not whole documents; use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts.
- ✅ Use maps keyed by ID for items that several devices edit; use `COUNTER` for concurrent tallies, and recalibrate with `RESTART WITH` only while every device that changes the counter is in sync.
- ✅ Use UUIDs (or composite IDs with a UUID) for `_id`; put permission scopes in `_id`.
- ✅ Keep documents well below 256 KiB; store binary data as attachments.
- ✅ Store timestamps as UTC ISO-8601 strings ending in `Z`, produced by one fixed-precision helper, or as epoch milliseconds.
- ✅ Keep the default `DQL_STRICT_MODE = false` unless you have a specific reason.

**Queries** ([DQL Fundamentals](dql.md#dql-fundamentals))
- ✅ Pass every value as a parameter (`:name`); use `IN :values` for membership.
- ✅ Filter optional flags with `coalesce(flag, false) = false`; test whether a field is absent with `IS MISSING` (present: `IS NOT MISSING`).
- ✅ Project only the fields you need, and add `ORDER BY` (with a tie-breaker) to observer queries.
- ✅ Create indexes at startup with `CREATE INDEX IF NOT EXISTS`; check plans with `EXPLAIN` and `ADVISE` (SDK 5.1+).

**Sync and observers** ([Sync and Subscriptions](sync-and-subscriptions.md), [Observing Changes](observers.md))
- ✅ Scope subscriptions by stable partition keys (tenant, store, user), keep them stable and owned by an app- or feature-level service, and filter UI views locally instead of re-registering.
- ✅ Register the subscriptions again after every `Ditto.open()`; they are not persisted.
- ✅ Use `SELECT * FROM <collection> [WHERE ...]` for subscriptions; subscribe to every collection a JOIN reads. Bound what syncs with `WHERE`, not `LIMIT`.
- ✅ On a TCP hub with more than six clients, raise `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` before `ditto.sync.start()`.
- ✅ In Flutter, register observers without `onChange`, consume `changes`, and cancel both in `dispose()`.

**Writes, deletion, and storage** ([Transactions](transactions.md), [Deletion and Storage Management](deletion-and-storage.md))
- ✅ Keep transactions short, use only `tx.execute` and await each call before the callback returns, and give them a `hint`.
- ✅ Track a `commitID` for upload progress only when `mutatedDocumentIDs()` is not empty; use presence for live connection status.
- ✅ Prefer soft delete for shared records, keep soft-deleted documents in the subscriptions of devices that relay data, and target deletions with `WHERE _id IN :ids`.
- ✅ Cancel or narrow subscriptions before `EVICT`, and evict at most about once per day.

**Security** ([Security](security.md))
- ✅ Use a webhook authentication provider in production, and a provisioned `privateKey` in small-peers-only deployments.
- ✅ Validate input, and encrypt sensitive fields at the application level.

## Where to Look When Something Goes Wrong

| Symptom | Start with |
|---|---|
| A statement throws, or returns nothing although the data is on the device | [When a Statement Fails or Returns Nothing](dql.md#when-a-statement-fails-or-returns-nothing) |
| Data does not appear on another device, stops updating, or comes back | [When Data Does Not Sync](sync-and-subscriptions.md#when-data-does-not-sync) |
| No peer connects | [Diagnosing transport problems (SDK 5.1+)](setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51) |
| A query is slow | The steps at the top of [Indexing and Query Performance](indexing-and-performance.md) |
| A screen janks or memory grows | [Observing Changes](observers.md) and [Query Scope and Execution](indexing-and-performance.md#query-scope-and-execution) |

## Common Code Shapes

**Startup sequence** (condensed; the full version in [Complete app startup](setup-and-lifecycle.md#complete-app-startup) also closes the instance when a step after `Ditto.open()` fails):

```dart
import 'package:flutter/foundation.dart';

Future<Ditto> startDitto(List<SyncSubscription> subscriptions) async {
  await Ditto.init();
  DittoLogger.minimumLogLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug;

  final ditto = await Ditto.open(
    const DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
      // Not persisted: pass on every open; applied before Ditto starts.
      systemParameters: {'DQL_SLOW_REQUEST_WARN_SECONDS': 30},
    ),
  );

  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    try {
      final response = await ditto.auth.login(
        token: await fetchAuthToken(),
        provider: 'YOUR_PROVIDER_NAME',
      );
      if (response.exception != null) showError(response.exception!);
    } catch (error) {
      showError(error); // never rethrow here
    }
  });

  if (!kIsWeb) {
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)',
    );
  }

  subscriptions.add(ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': 'store-1'},
  ));
  ditto.sync.start(); // void: do not await
  return ditto;
}
```

**Subscription** ([Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle)):

```dart
/// Owns the subscriptions for the store the user works in.
class OrderSync {
  OrderSync(this._ditto);

  final Ditto _ditto;
  SyncSubscription? _orders;
  String? _storeId;

  void enterStore(String storeId) {
    if (storeId == _storeId) return; // Already subscribed; do not re-register.
    _orders?.cancel();
    _storeId = storeId;
    _orders = _ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
  }

  /// On logout or when the user leaves the store.
  void leaveStore() {
    _orders?.cancel();
    _orders = null;
    _storeId = null;
  }
}
```

**Observer** ([Store Observers in Flutter](observers.md#store-observers-in-flutter)):

```dart
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
  arguments: {'status': 'open'},
);
final changes = observer.changes.listen((result) {
  final orders = result.items.map((item) => item.value).toList();
  debugPrint('open orders: ${orders.length}');
});
// In dispose() (synchronous; do not await there):
changes.cancel();
observer.cancel();
```

**Transaction** ([Using store.transaction](transactions.md#using-storetransaction)):

```dart
await ditto.store.transaction(hint: 'closeOrder', (tx) async {
  await tx.execute(
    'UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'id': 'order-1', 'status': 'closed'},
  );
  await tx.execute(
    'INSERT INTO invoices DOCUMENTS (:invoice)',
    arguments: {
      'invoice': {'_id': 'invoice-1', 'orderId': 'order-1'},
    },
  );
});
```

**Attachment** ([Creating and Inserting Attachments](attachments.md#creating-and-inserting-attachments), [Fetching Attachments](attachments.md#fetching-attachments)):

```dart
final attachment = await ditto.store.newAttachment(
  '/path/to/photo.jpg',
  AttachmentMetadata({'name': 'photo.jpg', 'mimeType': 'image/jpeg'}),
);
await ditto.store.execute(
  'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
  arguments: {
    'photo': {'_id': 'photo-1', 'image': attachment},
  },
);

// Later, when the image is shown: fetch the blob from the token.
final result = await ditto.store.execute(
  'SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE _id = :id',
  arguments: {'id': 'photo-1'},
);
final token = result.items.first.value['image'] as Map<String, dynamic>;
final fetcher = ditto.store.fetchAttachment(token, (event) async {
  if (event is AttachmentFetchEventCompleted) {
    final bytes = await event.attachment.data;
    debugPrint('fetched ${bytes.length} bytes');
  }
});
// If the screen closes before the fetch completes:
fetcher.stop();
```

**Upsert with DO UPDATE_LOCAL_DIFF** ([INSERT and Conflict Handling](dql.md#insert-and-conflict-handling)):

```dart
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'product': {'_id': 'p1', 'name': 'Pen', 'priceCents': 250},
  },
);
```

**COUNTER update** ([Counters](data-modeling.md#counters)):

```dart
await ditto.store.execute(
  'UPDATE COLLECTION products (viewCount COUNTER) '
  'APPLY viewCount INCREMENT BY 1 WHERE _id = :id',
  arguments: {'id': 'p1'},
);
```

**Soft delete and its filter** ([Soft Delete](deletion-and-storage.md#soft-delete)):

```dart
await ditto.store.execute(
  'UPDATE orders SET isDeleted = true, deletedAt = :now WHERE _id = :id',
  arguments: {
    'id': 'order-1',
    'now': utcTimestamp(), // fixed-precision helper (see Timestamps)
  },
);
final active = await ditto.store.execute(
  'SELECT * FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY createdAt DESC',
);
```

**Index creation** ([Creating Indexes](indexing-and-performance.md#creating-indexes)):

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)
```

**Logging** ([Logging](logging-and-observability.md#logging)):

```dart
import 'package:flutter/foundation.dart';

/// Call before Ditto.open().
Future<void> configureDittoLogging() async {
  await Ditto.init(); // DittoLogger throws until Ditto is initialized.
  DittoLogger.minimumLogLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug;
  // Set again before every reopen: ditto.close() clears the callback.
  DittoLogger.customLogCallback = (level, message) {
    if (level == LogLevel.error || level == LogLevel.warning) {
      debugPrint('[ditto ${level.name}] $message'); // or your logging pipeline
    }
  };
}
```
