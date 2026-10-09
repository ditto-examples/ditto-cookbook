# Ditto SDK Implementation Checklist

> **Version**: 2.7
> **Last Updated**: 2026-10-09
> **Applies to**: Ditto SDK 5.1.0 (Flutter `ditto_live` 5.1.0)
>
> **Ditto documentation**: [https://docs.ditto.live](https://docs.ditto.live)
>
> Each item names the sections of the Ditto SDK Best Practices guide (`ditto.md`) that explain it in detail.

## Section 1: Setup and Lifecycle

### ☐ Pin ditto_live 5.1.0 and meet the platform requirements

**What this means:** Pin the SDK version in `pubspec.yaml` so that every developer and every CI build uses the same release. Then check that your app meets the requirements of `ditto_live` 5.1.0:
- Dart 3.5.4 or later and Flutter 3.24.5 or later
- iOS 15+ and macOS 12+ on arm64 only (Intel Macs and x86_64 simulators are not supported), with CocoaPods
- Android `minSdk` 24, set explicitly in your app's Gradle file, and Kotlin Gradle plugin 2.0 or later
- The Bluetooth, local network, and nearby-device permissions that peer-to-peer sync needs (listed in the Flutter install guide), requested before sync starts
- On Flutter Web, data is kept in memory only, sync works only over WebSocket with Ditto Server, and indexes are not supported

**Why this matters:** Without a pinned version, developers, CI, and devices can end up on different SDK releases. Missing permissions and unsupported architectures are found late: they usually show up as peers that never connect, not as a clear error.

**Best-practices guide:** Requirements

**Code Example**:

```yaml
dependencies:
  ditto_live: 5.1.0   # or ^5.1.0 to accept compatible 5.x updates
```

### ☐ Open one Ditto instance per persistence directory and share it

**What this means:** Open Ditto once at app start with `await Ditto.open(DittoConfig(...))` and pass the instance to the parts of the app that need it, for example through dependency injection or a service object. If several callers may open Ditto at the same time, let them share one in-flight `Future`. Never open a new instance per screen or request, and never reopen a directory before `close()` has completed.

**Why this matters:** In Flutter, a second `Ditto.open()` on a directory that is already open may never complete, and it does not throw. The code that awaits it then stops without any error. Only one `Ditto` instance can use a persistence directory at a time.

**Best-practices guide:** One instance per persistence directory

**Code Example**:

```dart
// ✅ GOOD: One shared instance; concurrent callers await the same open.
class DittoProvider {
  DittoProvider(this._config);

  final DittoConfig _config;
  Future<Ditto>? _opening;

  Future<Ditto> get instance => _opening ??= _open();

  Future<Ditto> _open() async {
    try {
      return await Ditto.open(_config);
    } catch (_) {
      // Forget the failed attempt so that the next caller can retry.
      _opening = null;
      rethrow;
    }
  }
}
```

### ☐ Choose the connection mode deliberately

**What this means:** Choose the `connect` mode of `DittoConfig` for each build:
- `DittoConfigConnectServer(url: ...)`: devices sync through Ditto Server and with each other, and must authenticate. Copy the Server URL from the Ditto Portal exactly as shown.
- `DittoConfigConnectSmallPeersOnly(privateKey: key)`: devices sync only with each other, using a shared key (TLS 1.3).
- `DittoConfigConnectSmallPeersOnly()` without a key: for local store tests and development only. Sync in this mode still requires an offline license token.

**Why this matters:** The mode decides how devices authenticate and whether traffic is encrypted. Without a `privateKey`, peers do not authenticate each other: any device that has the SDK, the Database ID, and an offline license token can connect, read, and write. The SDK documents this mode as unencrypted in transit, so treat it as unprotected. Also make sure that `databaseID` is a valid UUID: do not count on `Ditto.open()` to reject a leftover placeholder.

**Best-practices guide:** Initializing Ditto

### ☐ Set the offline license token before starting sync in small-peers-only mode

**What this means:** For small-peers-only deployments, obtain an offline license token from Ditto and call `ditto.setOfflineOnlyLicenseToken(token)` before `ditto.sync.start()`. No expiration handler is needed in this mode.

**Why this matters:** In small-peers-only mode, `ditto.sync.start()` throws until a valid offline license token is set, whether or not you use a private key. The local store works without a license, so tests that never start sync can open Ditto without one.

**Best-practices guide:** Initializing Ditto

**Code Example**:

```dart
// ✅ GOOD: Small-peers-only deployment. The shared key and the offline license
// token (issued by Ditto) come from secure provisioning, never from source code.
Future<Ditto> openProvisionedSmallPeer({
  required Future<String> Function() readKeyFromSecureStorage,
  required Future<String> Function() readLicenseFromSecureStorage,
}) async {
  final ditto = await Ditto.open(
    DittoConfig(
      databaseID: 'YOUR_DATABASE_ID', // any UUID shared by all peers
      connect: DittoConfigConnectSmallPeersOnly(
        privateKey: await readKeyFromSecureStorage(),
      ),
    ),
  );
  // Required before sync.start() in small-peers-only mode.
  ditto.setOfflineOnlyLicenseToken(await readLicenseFromSecureStorage());
  ditto.sync.start(); // no expiration handler is needed in this mode
  return ditto;
}
```

### ☐ Set the authentication expiration handler before ditto.sync.start()

**What this means:** With `DittoConfigConnectServer`, register `await ditto.auth.setExpirationHandler(...)` before starting sync. Inside the handler:
- Fetch a fresh token from your backend and call `ditto.auth.login(token: ..., provider: ...)`
- Check `response.exception`: `login()` does not throw when the token is rejected or the server is unreachable
- Catch errors from your own token code and report them; never throw or rethrow from the handler

**Why this matters:** With a server connection, `ditto.sync.start()` throws if no handler is set. Ditto calls the handler again before the credentials expire, so reusing a cached token makes the refresh fail. The handler returns `void`: an error thrown inside it never reaches Ditto and becomes an unhandled asynchronous error.

**Best-practices guide:** Authentication

**Code Example**:

```dart
// ✅ GOOD: Production login with error reporting and no throwing.
Future<void> configureAuthentication(Ditto ditto) async {
  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    try {
      final response = await ditto.auth.login(
        token: await fetchAuthToken(), // from your identity provider/backend
        provider: 'YOUR_PROVIDER_NAME', // as configured in the Ditto Portal
      );
      if (response.exception != null) {
        showError(response.exception!); // login() reports rejection; it does not throw
      }
    } catch (error) {
      showError(error); // e.g. fetchAuthToken() failed; never rethrow here
    }
  });
}
```

### ☐ Apply ALTER SYSTEM settings after every open and before starting sync

**What this means:** System parameters set with `ALTER SYSTEM SET` are kept in memory only. Apply them in one startup function every time you open Ditto: after `Ditto.open()`, and before you call `ditto.sync.start()`, run queries, or register observers. Subscriptions may be registered before them. Use `SHOW` to check a value and `ALTER SYSTEM RESET` to restore a default.

**Why this matters:** After an app restart, or after Ditto is closed and reopened, every parameter is back at its default, so settings such as `DQL_STRICT_MODE`, `USER_COLLECTION_SYNC_SCOPES`, and `TOMBSTONE_TTL_HOURS` silently revert. Sync scopes applied after sync has started can let data sync unintentionally.

**Best-practices guide:** Applying System Parameters

**Code Example**:

```dart
// ✅ GOOD: System parameters are not persisted: apply them on every open.
Future<void> applySettingsAndStartSync(Ditto ditto) async {
  await ditto.store.execute('ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 30');
  await ditto.store.execute(
    "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = {'localDrafts': 'LocalPeerOnly'}",
  );
  ditto.sync.start(); // returns void: do not await
}
```

### ☐ Treat sync.start() and sync.stop() as synchronous, and keep Ditto open in the background

**What this means:** `ditto.sync.start()` and `ditto.sync.stop()` return `void`, so do not `await` them. `start()` throws if a prerequisite (the expiration handler or the offline license token) is missing, and does nothing if sync is already active (`ditto.sync.isActive`). Keep Ditto open while the app is paused; do not call `ditto.close()`. If your app must not sync in the background, call `stop()` when the app is paused, and on resume restart only the sync that you stopped.

**Why this matters:** In Dart, awaiting a `void` call is a compile error. `close()` cannot be undone: every later call on that instance throws `DittoClosedException`, so you would have to open a new instance and register every subscription and observer again. `stop()` has no such cost: the local store stays fully usable.

**Best-practices guide:** Starting and Stopping Sync

**Code Example**:

```dart
// ✅ GOOD: For apps that must not sync in the background: pause sync without
// closing Ditto, and resume only the sync that this class paused.
class SyncLifecycle with WidgetsBindingObserver {
  SyncLifecycle(this.ditto) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ditto ditto;
  bool _pausedByLifecycle = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        if (ditto.sync.isActive) {
          ditto.sync.stop(); // the local store stays usable
          _pausedByLifecycle = true;
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle) {
          _pausedByLifecycle = false;
          try {
            ditto.sync.start();
          } catch (error) {
            showError(error); // for example, prerequisites changed in the background
          }
        }
      default:
        break;
    }
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
```

### ☐ Change transport settings with updateTransportConfig()

**What this means:** `TransportConfig` is immutable. Call `ditto.updateTransportConfig((config) { ... })` instead: it starts from the current configuration, so you change only what you need, for example with `setAllPeerToPeerEnabled()` or one transport under `peerToPeer`. Treat `global.syncGroup` as an optimization, not as a security boundary. If more than six devices connect to a hub over TCP, run `ALTER SYSTEM SET MESH_CHOOSER_MAX_WLAN_CONNECTIONS = <n>` on the hub after every open and before `ditto.sync.start()`. This parameter is undocumented and may change in a later release, so confirm the setting with Ditto support before you rely on it in production.

**Why this matters:** A hand-built configuration can silently stop devices from finding each other. A new `TransportConfig()` has every transport disabled, including the peer-to-peer transports that a default instance enables. Changes are applied asynchronously, and invalid values do not throw. In our testing with SDK 5.1.0, a device accepted 6 TCP connections by default. Additional clients of a hub received no data, no API reported an error, and only a `WARN` log line showed the problem.

**Best-practices guide:** Transport Configuration

**Code Example**:

```dart
// ✅ GOOD: Adjust the current configuration with the builder.
void configureTransports(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.setAllPeerToPeerEnabled(true); // BLE, LAN, AWDL / Wi-Fi Aware
    config.peerToPeer.bluetoothLE.isEnabled = false; // e.g. LAN and P2P Wi-Fi only
  });
}
```

### ☐ Release Ditto objects explicitly and await pending work before close()

**What this means:** Release each Ditto object when you no longer need it: call `cancel()` on `StoreObserver`, `StoreObserverV2`, and `SyncSubscription` objects, and `stop()` on `PresenceObserver`, transport-condition observers, and `AttachmentFetcher` objects. Before `await ditto.close()`, await your own pending queries and transactions, and cancel your observers and the `StreamSubscription`s on their `changes` streams. Call `close()` only when the whole app no longer needs Ditto. Use the instance only from the isolate that opened it.

**Why this matters:** Ditto objects hold native resources, so do not rely on garbage collection to release them. `close()` does not clean up for you. It does not wait for in-flight `execute()` calls or transactions, which can then fail with `DittoClosedException`. It does not end an `await for` loop over the `changes` stream of a `StoreObserver` or `StoreObserverV2`, and once Ditto is closed, `cancel()` no longer does anything. It also resets `DittoLogger.customLogCallback` for the whole process.

**Best-practices guide:** Resource Cleanup and Shutdown

---

## Section 2: DQL Queries and Results

### ☐ Pass every value as a DQL parameter

**What this means:** Write a `:name` placeholder for every value and pass the value in `arguments`. This includes IDs, user input, dates, limits, and whole documents (`INSERT INTO orders DOCUMENTS (:order)`). Never build DQL strings with string interpolation or concatenation. Parameter names are case-sensitive.

**Why this matters:** Interpolated input can change what a statement does (DQL injection). DQL also interprets backslash escapes in string literals, so user text that contains `\` or quotes can be altered or can break the statement. Parameters keep their exact value and type. And because the statement text stays the same, Ditto can reuse the prepared plan from its statement cache.

**Best-practices guide:** Parameters and Literals

**Code Example**:

```dart
// ✅ GOOD: Values travel as typed parameters.
Future<List<Map<String, dynamic>>> findOrders(
  Ditto ditto,
  String customerId,
  int pageSize,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE customerId = :customerId '
    'ORDER BY createdAt DESC LIMIT :pageSize',
    arguments: {'customerId': customerId, 'pageSize': pageSize},
  );
  return result.items.map((item) => item.value).toList();
}

// ❌ BAD: Interpolated values (injection risk, broken quoting, no statement reuse).
Future<void> findOrdersUnsafe(Ditto ditto, String customerId) async {
  await ditto.store.execute(
    "SELECT * FROM orders WHERE customerId = '$customerId'",
  );
}
```

### ☐ Use IN :values for membership filters

**What this means:** To match any value in a list, pass the list as an array parameter without parentheses: `WHERE status IN :statuses`. To test whether an array field contains a value, use `:tag IN tags` or `array_contains(tags, :tag)`.
- Do not write `IN (:statuses)`: the parentheses wrap the array in a one-element list, so nothing matches
- Do not filter with `ANY` or `EVERY ... SATISFIES ... END` over a parameter or literal array in `WHERE`. For example, `ANY s IN :statuses SATISFIES s = status END` returns no rows in SDK 5.1.0; use `status IN :statuses` instead

**Why this matters:** Both mistakes return an empty result without an error, so the bug looks like missing data. `status IN :statuses` can also use an index on `status`.

**Best-practices guide:** Filtering by Membership

**Code Example**:

```dart
// ✅ GOOD: Membership against an array parameter.
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

// ❌ BAD: The array becomes a single list element, so no document matches.
Future<void> tasksWithStatusWrong(Ditto ditto) async {
  await ditto.store.execute(
    'SELECT * FROM tasks WHERE status IN (:statuses)',
    arguments: {'statuses': ['open', 'pending']},
  );
}
```

### ☐ Quote every key in inline object literals

**What this means:** When you write an object literal inside a DQL statement, quote every key, for example `{'status': 'open'}`. Better still, avoid inline objects and pass documents as parameters (`DOCUMENTS (:order)`).

**Why this matters:** `INSERT` rejects unquoted keys. `SELECT` accepts them without an error but evaluates them as field references, which usually produces an empty object (`{}`).

**Best-practices guide:** Quote every key in inline object literals

**Code Example**:

```sql
-- ❌ BAD: No error, but o is returned as {} (the unquoted key is evaluated as a field reference)
SELECT {a: 1} AS o FROM system:dual

-- ✅ GOOD: Quoted keys
INSERT INTO orders DOCUMENTS ({'_id': 'order-1', 'status': 'open'})
```

### ☐ Keep DQL keywords out of collection and field names

**What this means:** Choose names that are not DQL keywords, such as `orders`, `tasks`, and `createdAt`. Never name a collection `collection`. If you cannot rename an existing reserved name, quote it with backticks in every statement. Do not start ordinary comments with `/*+` or `--+`; those prefixes mark query directives.

**Why this matters:** `SELECT * FROM collection` fails with a parser error (`expected identifier`). A reserved name must be quoted with backticks in every statement that uses it.

**Best-practices guide:** Reserved words

### ☐ Distinguish MISSING from NULL in filters

**What this means:** A field can be absent from a document (MISSING) or present with the value `null`. A comparison involving either is neither true nor false, so `WHERE` does not return the row.
- Filter optional booleans with `coalesce(field, false) = false`
- Test existence with `IS MISSING` / `IS NOT MISSING`; `IS NOT NULL` is also true for a missing field
- Remove a field with `UNSET`; writing `null` keeps the field present

**Why this matters:** Documents written by older app versions or other platforms often lack newer fields. A filter that ignores MISSING hides those documents without any error. Also, when no documents match, aggregates other than `COUNT` return MISSING, not `0`.

**Best-practices guide:** MISSING and NULL

### ☐ Convert query results to plain Dart data right away

**What this means:** Convert each `QueryResultItem` to a `Map` or to your own model class once, and then let the `QueryResult` go out of scope. `items` is an `Iterable`, so iterate it only once. Likewise, call `mutatedDocumentIDs()` once and keep the list.

**Why this matters:** `QueryResult` and `QueryResultItem` objects reference native memory, which is released only when the Dart object is garbage-collected. Keeping them in state, in caches, or across observer callbacks keeps that memory alive. In addition, every pass over `items` decodes the rows again.

**Best-practices guide:** Working with Query Results

**Code Example**:

```dart
class Order {
  Order({required this.id, required this.status});

  factory Order.fromValue(Map<String, dynamic> value) => Order(
        id: value['_id'] as String,
        status: value['status'] as String? ?? 'unknown',
      );

  final String id;
  final String status;
}

// ✅ GOOD: One pass, plain Dart objects out; the QueryResult is not kept.
Future<List<Order>> loadOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, status FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => Order.fromValue(item.value)).toList();
}
```

### ☐ Use RETURNING to read what a write changed (SDK 5.1+)

**What this means:** Add `RETURNING` to an `INSERT`, `UPDATE`, `DELETE`, or `EVICT` statement to get the affected documents in its `items`. An `UPDATE` returns the documents after the change; `DELETE` and `EVICT` return them as they were before removal. Aggregates such as `RETURNING COUNT(*) AS removed` are allowed.

**Why this matters:** It replaces the "write, then query again" pattern, so the values you read are exactly the ones you wrote. For `DELETE`, you get the removed content from the same atomic statement. `commitID` and `mutatedDocumentIDs()` are populated as usual. Still, treat `items` as the result: when you need the IDs, include `_id` in the `RETURNING` list instead of relying on `mutatedDocumentIDs()`.

**Best-practices guide:** RETURNING (SDK 5.1+)

**Code Example**:

```dart
// ✅ GOOD: Update and read the new values in one statement.
Future<List<Map<String, dynamic>>> markShipped(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status, shippedAt = :now '
    'WHERE _id IN :ids AND status = :expected '
    'RETURNING _id, status, shippedAt',
    arguments: {
      'ids': ids,
      'status': 'shipped',
      'expected': 'packed',
      // utcTimestamp(): see "Store timestamps in UTC with a zone designator".
      'now': utcTimestamp(),
    },
  );
  return result.items.map((item) => item.value).toList();
}
```

### ☐ Know the DQL expressions that fail or return nothing

**What this means:** Watch for these common mistakes:
- `type(x) = 'number'` never matches, because `type()` returns `'integer'` or `'float'`; use `is_number(x)`
- `date_add` and `date_sub` return MISSING if you swap the `part` and `count` arguments; keep the order `date_add(date, part, count)`. `date_diff(date1, date2, part)` returns `date1 - date2`, so swapping the dates flips the sign
- `GROUP BY` and `HAVING` cannot reference projection aliases (the statement fails); repeat the expression
- A comparison between values of different types evaluates to MISSING, even with `=` and `!=` (`1 = 'a'`, `1 != 'a'`, `1 < 'a'`)

**Why this matters:** Most of these look like valid queries, so the bug shows up as missing rows or fields in the UI rather than as an exception.

**Best-practices guide:** Type Checking, Date and Time, GROUP BY and HAVING, MISSING and NULL

---

## Section 3: Data Modeling

### ☐ Update individual fields instead of rewriting whole documents

**What this means:** Write only the fields that changed, with `UPDATE ... SET`. When a user edits a document, write only the fields that the user changed. Do not read a document, change it in Dart, and write the whole map back with `ON ID CONFLICT DO UPDATE`. For upserts and re-imports of data that another system owns, use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`. It skips fields whose values are unchanged, but it does not protect you from a stale in-memory copy: any old value that differs from the stored one is written back.

**Why this matters:** A whole-document rewrite can undo another device's edit. Ditto syncs changes field by field, so every field you write takes part in the merge, and an unchanged value written by this device can win against a real concurrent change from another device. Rewriting every field also makes each change larger. Even an `UPDATE` that writes the value that is already stored counts as a mutation and can trigger observers.

**Best-practices guide:** Prefer field-level updates over whole-document rewrites, ON ID CONFLICT

**Code Example**:

```dart
// ❌ BAD: Read-modify-write of the whole document.
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

// ✅ GOOD: Single field-level update that skips unchanged documents.
Future<bool> setStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': ''},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

### ☐ Use maps keyed by ID, not arrays, for items that several devices edit

**What this means:** Store line items, participants, or checklist entries as a map keyed by a stable ID (`{"items": {"<itemId>": {...}}}`), and keep any display order in a field such as `position`. Use arrays only for lists that one device owns or that are replaced as a whole. To add or update one entry from code, upsert a partial document with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`.

**Why this matters:** An array is a single register: when two devices change the same array concurrently, one version wins and the other change disappears without an error. Map entries merge independently, so concurrent additions and edits to different entries are all kept. In our testing with SDK 5.1.0, removing an entry with `UNSET` did not win over a concurrent edit of the same entry, and a partial entry remained. If one device may remove an entry while another edits it, mark the entry as removed instead (`` SET items.`<id>`.removed = true ``), and make readers skip entries whose required fields are missing or `null`.

**Best-practices guide:** Arrays and Maps

**Code Example**:

```dart
/// ✅ GOOD: Adds or updates one line item of a map keyed by item ID.
/// The key is passed as data, never spliced into the query.
/// Note: if the order does not exist yet, this creates it.
Future<void> upsertOrderItem(
  Ditto ditto, {
  required String orderId,
  required String itemId,
  required Map<String, dynamic> item,
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': orderId,
        'items': {itemId: item},
      },
    },
  );
}
```

### ☐ Remove object keys explicitly with UNSET

**What this means:** With the default settings, an object is a CRDT map. `SET obj = {...}` and `ON ID CONFLICT DO UPDATE` merge the new keys into the existing object: keys you leave out remain, and `SET obj = {}` changes nothing. Update nested fields individually (`SET address.city = :city`) and remove keys with `UNSET address.zip`. To replace an object as a whole, run `UNSET` and then `SET` in one transaction, or declare the field as `REGISTER`. Only a `REGISTER` guarantees that concurrent edits never mix two versions.

**Why this matters:** Code that expects an assignment to replace an object leaves stale keys behind. Maps are add-wins so that offline edits from many devices merge without data loss; the trade-off is that removals must be explicit.

**Best-practices guide:** Assigning an object merges it, CRDT Types and Merge Behavior

**Code Example**:

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

### ☐ Use COUNTER for values that several devices change concurrently

**What this means:** Change counters with `APPLY f INCREMENT BY n` (a negative `n` decrements). For an occasional correction, use `APPLY f RESTART WITH n`, and only while every device that changes the counter is in sync. Declare the counter in every statement, including the `INSERT` that sets the initial value, for example `UPDATE COLLECTION inventory (stockCount COUNTER) ...`. Counters hold integers only, so count money in minor units.
- Do not use counters for unique sequence numbers or for balances that must never go below zero
- Do not use counters for values you can compute with `COUNT(*)`

**Why this matters:** When two devices run `SET stock = stock - 1` concurrently, one of the decrements is lost. Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only CRDT types that add concurrent changes together. An undeclared `INSERT` stores the initial value as a register, so a later increment starts a separate counter at 0. A `RESTART` discards every increment that the restarting device has not received yet, including increments that other devices make later while offline (SDK 5.1.0).

**Best-practices guide:** Counters

**Code Example**:

```dart
// ❌ BAD: Read-modify-write on a register. Two devices that sell an item
// concurrently both write the same value; one decrement is lost.
Future<void> sellOneIncorrectly(Ditto ditto, String itemId) async {
  await ditto.store.execute(
    'UPDATE inventory SET stockLevel = stockLevel - 1 WHERE _id = :id',
    arguments: {'id': itemId},
  );
}

// ✅ GOOD: Concurrent decrements are combined.
Future<void> sellOne(Ditto ditto, String itemId) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION inventory (stockCount COUNTER)
    APPLY stockCount INCREMENT BY -1
    WHERE _id = :id
    ''',
    arguments: {'id': itemId},
  );
}
```

### ☐ Use collision-free document IDs

**What this means:** Use UUIDs (version 4), composite IDs that combine stable scope fields with a UUID (`{"storeId": "s1", "orderId": "<uuid>"}`), or let Ditto generate the ID. Never use sequential numbers or timestamp-only IDs. Keep human-readable numbers such as "#A-0042" in a separate field, and put only immutable attributes into `_id`.

**Why this matters:** Offline devices cannot coordinate a sequence, so two of them can create the same ID. After sync, the two documents become one document with their fields mixed together. `_id` cannot be changed after creation, so keep attributes that may change out of it.

**Best-practices guide:** Document IDs

**Code Example**:

```dart
// ❌ BAD: Two offline devices both create the 42nd order of the day.
String badSequentialId(int dailyCount) => 'order-$dailyCount';

// ❌ BAD: Collides when two devices write within the same millisecond.
String badTimestampId() => 'order-${DateTime.now().millisecondsSinceEpoch}';

// ✅ GOOD: A composite ID with a stable scope field and a UUID
// (for example from the uuid package on pub.dev).
Future<void> createOrder(Ditto ditto, String storeId, String orderUuid) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': {'storeId': storeId, 'orderId': orderUuid},
        'status': 'open',
        // utcTimestamp(): see "Store timestamps in UTC with a zone designator".
        'createdAt': utcTimestamp(),
      },
    },
  );
}
```

### ☐ Keep documents well below 256 KiB

**What this means:** Ditto logs a warning for documents above 256 KiB (soft limit) and rejects `INSERT` and `UPDATE` statements that would make a document larger than 5 MiB (hard limit). Store binary content as attachments, move data that grows without bound (history, readings, comments) into its own collection, and leave both limits at their defaults.

**Why this matters:** Large documents cost storage and memory on every device, make merges more expensive, and slow down initial replication: over Bluetooth LE, a 256 KiB document takes more than 10 seconds to replicate the first time. A write that exceeds the hard limit fails with a `DittoException`. The limit is checked only for local writes, so offline additions on two devices can merge into a document above it. After that, every `UPDATE` of the document fails on every device (SDK 5.1.0). To bring an oversized document back under the limits, move large values to attachments or a separate collection and remove them from the document with `UNSET`.

**Best-practices guide:** Document Size Limits

**Code Example**:

```dart
// ✅ GOOD: Handle the size error at the call site that may produce it.
Future<bool> saveNotes(Ditto ditto, String visitId, String notes) async {
  try {
    await ditto.store.execute(
      'UPDATE visits SET notes = :notes WHERE _id = :id',
      arguments: {'id': visitId, 'notes': notes},
    );
    return true;
  } on DittoException catch (error) {
    // The message contains "exceeds limit of ... bytes" for oversized documents.
    showError(error);
    return false;
  }
}
```

### ☐ Compute derived values when you read them

**What this means:** Do not store totals, counts, or remaining stock that are computed from other fields. Compute them in Dart or with a DQL aggregate when you read the data. Snapshot values are different: copy the unit price at the time of sale into the line item.

**Why this matters:** A stored total can disagree with the data it summarizes. It is a separate register: when two devices update the inputs concurrently, each recomputes the total from its own partial view, and after the merge the stored total may match neither device's inputs.

**Best-practices guide:** Do not store derived values that can diverge

### ☐ Keep transient and device-local state out of synced documents

**What this means:** Keep UI state (`isExpanded`, scroll positions), progress flags (`isSaving`, `uploadProgress`), and device-local data (file paths, cache locations) in widget state, a state-management layer, or local preferences, not in synced documents.

**Why this matters:** Every stored field costs storage and memory on every device that holds the document, adds to the initial replication of new documents, and adds to merge cost. A local file path is meaningless on another device.

**Best-practices guide:** Exclude transient and unnecessary fields

### ☐ Store timestamps in UTC with a zone designator

**What this means:** Write timestamps as ISO-8601 strings in UTC (`DateTime.now().toUtc().toIso8601String()`, ending in `Z`) or as epoch milliseconds. Generate every timestamp that is sorted or compared with one helper that uses a fixed precision. Compute time windows such as "last 7 days" in Dart and pass the boundary as a parameter.

**Why this matters:** Dart's local `DateTime.now().toIso8601String()` has no zone designator, and DQL date functions silently return MISSING for such strings. Precision varies too: on native platforms Dart emits microseconds (`.123456Z`) but omits them when they are zero (`.123Z`), and on the web it always emits milliseconds. Strings with mixed precision do not sort correctly as text.

**Best-practices guide:** Timestamps

**Code Example**:

```dart
/// ✅ GOOD: The current time as an ISO-8601 UTC string with exactly
/// millisecond precision, e.g. "2026-10-08T10:30:00.123Z".
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ❌ BAD: Local time without a zone; DQL date functions return MISSING for it.
String localTimestamp() => DateTime.now().toIso8601String();
```

### ☐ Do not rely on your own timestamps to decide which write wins

**What this means:** Use stored timestamps only as approximate information for display, filtering, and retention. Where the order of writes matters, model the data so that the merge cannot go wrong: use a counter, a map keyed by ID, or an audit log from which you derive the current state. Expect small negative durations between timestamps written by different devices.

**Why this matters:** If you compare your own timestamps at read time, the device with the fastest clock wins. Device clocks drift: Android devices can deviate by several seconds, and manually set clocks by much more. Ditto itself resolves concurrent register writes with its own Hybrid Logical Clock, independently of your fields.

**Best-practices guide:** Clock drift

### ☐ Record history as new facts, not overwrites

**What this means:** When every change matters (status transitions, adjustments, readings), record each change instead of overwriting one field:
- Bounded history of one document: an audit-log map keyed by a millisecond-precision UTC timestamp (plus a device identifier if two devices can record a change in the same millisecond), with the current state derived when you read it
- Unbounded history: append-only event documents with UUID IDs, with eviction planned from the start
- Latest value plus full history: write the current-state and history collections in one transaction

**Why this matters:** Overwriting a status register keeps only one of two concurrent transitions. Add-wins maps and never-updated event documents keep every change, and the parent document stays small when events live in their own collection.

**Best-practices guide:** Event History and Audit Logs

### ☐ Choose between embedding and separate collections deliberately

**What this means:** Embed sub-entities that belong to one parent and are read and written with it, as a map keyed by ID. Use a separate collection when the data has different permissions, is shared by many parents, is accessed on its own, or grows without bound, and read the collections together with `JOIN` (SDK 5.1+). Copy a value from another document only when it is a snapshot or a subscription filter key.

**Why this matters:** An embedded write is atomic and syncs as one unit. A separate collection is a separate sync unit: it needs its own subscription and an index on the join key. Concurrent edits alone are not a reason to split, because map entries merge independently.

**Best-practices guide:** Relationships: Embedding, Separate Collections, and JOIN

### ☐ Seed shared default data with INITIAL DOCUMENTS

**What this means:** Insert default settings or built-in categories with `INSERT INTO c INITIAL DOCUMENTS (:doc)`, using fixed, well-known `_id` values and identical content in every app version. Running it on every launch is safe: existing documents, including edited ones, are kept. Use a regular `INSERT` with a new UUID for data that only one device creates.

**Why this matters:** A regular `INSERT` of shared defaults fails with an ID conflict on the second run, and `ON ID CONFLICT DO UPDATE` overwrites users' edits. Seeding an ID that was deleted leaves a document with `null` fields in two cases: when the seed content differs from the original `INITIAL` insert, and when the deleted document was originally created with a regular `INSERT`. So if the seed content may change in a later app version, let users remove seed documents with a soft delete (such as an `isArchived` flag). In our testing with SDK 5.1.0, different seeds for the same `_id` merged field by field: a key removed in a new app version came back from devices that still ran the old version. Initial documents sync like any other document.

**Best-practices guide:** Default Data with INITIAL Documents

**Code Example**:

```dart
// ✅ GOOD: Default categories that every device creates at startup. Running
// this on every launch is safe: existing documents, including edited ones, are kept.
Future<void> seedDefaultCategories(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
    arguments: {
      'categories': [
        {'_id': 'food', 'name': 'Food', 'sortOrder': 1},
        {'_id': 'drinks', 'name': 'Drinks', 'sortOrder': 2},
      ],
    },
  );
}
```

### ☐ Evolve the schema with additive changes

**What this means:** Add new fields, and read them with a default value when an older document lacks them. Instead of changing a field's meaning, unit, or type, add a new field (for example `mileageKm`). For breaking changes, version the data (a schema version in a composite `_id`, or a new collection per version). Ship an app version that reads both formats before one that writes the new format.

**Why this matters:** Devices run different app versions for weeks or months, so old and new formats coexist. Changing the CRDT type of an indexed field (for example, from REGISTER to MAP) can make queries return wrong results, because only the most recently written CRDT type of a field is indexed. Backfilling old documents does not work either: devices that are offline during the backfill bring the old documents back.

**Best-practices guide:** Schema Evolution

---

## Section 4: Strict Mode and Type Declarations

### ☐ Keep DQL_STRICT_MODE at its default (false) unless you need it

**What this means:** `DQL_STRICT_MODE` defaults to `false`: objects are inferred as maps, and MAP, COUNTER, and ATTACHMENT fields are inferred from the value or operation. Choose `true` only when almost every object needs whole-object replacement and you are prepared to declare every MAP, COUNTER, and ATTACHMENT field in every statement. If you opt in, apply the setting after every open and use the same value on every peer.

**Why this matters:** With strict mode enabled, undeclared objects become registers and nested updates fail. Fields stored as MAP, COUNTER, or ATTACHMENT are invisible to `SELECT` and `WHERE` unless the statement declares them, and the SDK 5.1.0 query planner does not use secondary indexes. Each peer interprets synced data with its own setting, so mixed settings across peers make data look missing.

**Best-practices guide:** Strict Mode

### ☐ Declare REGISTER for objects that must be replaced as a whole

**What this means:** When an object such as a shipping address or a GPS position must never mix parts from two writes, keep the default mode and declare the field as `REGISTER` in every statement that touches it. To change one part, write the whole object again.

**Why this matters:** A MAP merges each key, so concurrent edits could combine the street of one address with the city of another. A REGISTER is replaced as a whole, and concurrent writes resolve by last-writer-wins. A nested update such as `SET shippingAddress.city = :city` fails on a REGISTER.

**Best-practices guide:** When to choose strict mode

**Code Example**:

```dart
// ✅ GOOD: The address is a REGISTER, so concurrent edits never produce a mix
// of two addresses. The declaration appears in every statement.
Future<void> setShippingAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> address,
) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION customers (shippingAddress REGISTER)
    SET shippingAddress = :address
    WHERE _id = :id
    ''',
    arguments: {'id': customerId, 'address': address},
  );
}
```

### ☐ Use the same type declaration for a field in every statement

**What this means:** Keep the `REGISTER`, `COUNTER`, and `ATTACHMENT` declarations of a field identical in every `INSERT`, `UPDATE`, and `SELECT` that touches it, and keep these statements in one place, such as a repository class. Never write a counter field with `SET`. Instead of changing a field's CRDT type, introduce a new field.

**Why this matters:** When statements disagree, a field holds several CRDT values at once, and each statement sees a different one. An undeclared `INSERT` of 10 followed by `INCREMENT BY 1` yields 1, not 11, which looks like data loss even on a single device.

**Best-practices guide:** Keep type declarations consistent

---

## Section 5: Subscriptions and Sync

### ☐ Pair each screen's local queries with a long-lived subscription

**What this means:** Queries (`execute`), store observers, and transactions read only the local store; they never fetch data from other peers. Data reaches a device only through subscriptions registered with `ditto.sync.registerSubscription(...)` while sync is running. Register the subscriptions for a screen's data in an app-level or feature-level service (see "Own subscriptions in a long-lived service, not in widgets"). On the screen itself, read that data with local queries and observers.

**Why this matters:** Without a matching subscription, a screen shows only local data, and the missing documents look like a query bug. A `SELECT` sees only documents that were created on the device or already delivered by a subscription.

**Best-practices guide:** Core Principles, Where Queries Run

### ☐ Write subscriptions as SELECT * FROM collection with an optional WHERE clause

**What this means:** Write every subscription as `SELECT * FROM <collection> [WHERE ...]`, with values passed as parameters. A subscription selects whole documents from one collection. Registration rejects projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, and `USE IDS`. It also rejects `LIMIT` and `ORDER BY` while `DQL_RESTRICT_SUBSCRIPTIONS` keeps its default value, `true`. Keep that default, and sort and limit in local queries instead.

**Why this matters:** Subscriptions always sync whole documents. A subscription with `LIMIT` degrades sync performance: it is stateful, so the sync engine must re-evaluate it whenever a document crosses the limit boundary. A stable subscription plus a local `ORDER BY ... LIMIT` query gives the same UI without that cost. `LIMIT` also bounds only the initial download (SDK 5.1.0); after that, every matching new or changed document is synced, inside the window or not. In our testing with SDK 5.1.0, a document that stopped matching a filter stayed on the device as a frozen copy: later edits, and even its deletion, no longer arrived.

**Best-practices guide:** Subscription Rules

**Code Example**:

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

### ☐ Own subscriptions in a long-lived service, not in widgets

**What this means:** Register a subscription when its data becomes relevant, such as at app start, at login, or when the user enters a store. Keep a reference to each subscription in an app-level or feature-level service, and call `cancel()` on logout, when the user leaves the workspace, or when you register a replacement. Never register subscriptions in `build()` or on every screen visit. Use `ditto.sync.subscriptions` only for debugging, and read only `queryString` and `isCancelled` from it. In SDK 5.1.0, reading `queryArguments` of a subscription registered without arguments can terminate the app.

**Why this matters:** A subscription registered in `build()` adds a new mesh-wide subscription on every rebuild, because subscriptions stay active until they are cancelled or Ditto is closed. Do not rely on garbage collection to cancel them.

**Best-practices guide:** Subscription Lifecycle

**Code Example**:

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

### ☐ Filter locally instead of re-registering subscriptions

**What this means:** When the user changes a filter, search term, tab, or sort order, replace the local observer, not the subscription. Change a subscription only when the device needs a different set of data, for example after switching to a different store, and no more often than about once every 15 minutes.

**Why this matters:** Every subscription change slows sync down: registering, cancelling, or changing a subscription makes peers across the mesh re-evaluate what to send the device, which degrades sync throughput and can interrupt transfers in progress. Observers are local and cheap to replace.

**Best-practices guide:** Filter locally instead of re-registering

### ☐ Scope subscriptions by stable partition keys

**What this means:** Filter subscriptions by fields that partition your data and never change during a document's lifetime, such as `storeId`, `tenantId`, or `region`, and keep the predicates simple. Give devices in the same role the same subscriptions, and give relay or hub devices at least everything that the devices behind them need. Subscribe to an entire collection only when it holds small reference data.

**Why this matters:** Unfiltered subscriptions on large collections cost storage, bandwidth, and battery on every device. Filters on fields that change (`status`, `assignee`) leave devices without data, and so do relay devices that subscribe to less than the devices behind them need: a device can relay only documents that it stores itself.

**Best-practices guide:** Scope subscriptions to what the device needs, Multi-hop relay

### ☐ Subscribe to every collection that a JOIN reads

**What this means:** `JOIN` (SDK 5.1+) reads only documents that are already in the local store, and it is not allowed in subscriptions. Register a separate `SELECT * FROM c WHERE ...` subscription for each joined collection. If you need to filter a child collection by a key that is stored on the parent, copy that key into the child documents.

**Why this matters:** Without a subscription for every joined collection, joined rows are silently missing on devices that did not create the data. A join never pulls related documents onto a device.

**Best-practices guide:** Joining Collections (SDK 5.1+)

### ☐ Apply sync scopes before sync starts, and do not use them for access control

**What this means:** `USER_COLLECTION_SYNC_SCOPES` limits where this device sends a collection: `AllPeers`, `BigPeerOnly`, `SmallPeersOnly`, or `LocalPeerOnly`. Set it after every `Ditto.open()` and before `ditto.sync.start()` on every device that can store the collection, that is, every device that writes, subscribes to, or relays it. List all scoped collections in one statement. Each `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` replaces the whole map, so a collection left out of a later statement loses its scope.

**Why this matters:** A device without the setting can send the collection to Ditto Server, because sync scopes are not persisted and the device that sends the data is the one that checks the scope. Scopes control what a device sends, not what other devices may read. Use permissions for access control.

**Best-practices guide:** Sync Scopes

### ☐ Use sync status to enhance the UI, never to block it

**What this means:** To show an "uploaded" indicator, keep the `commitID` of important writes and compare it with `synced_up_to_local_commit_id` in `system:data_sync_info`. Track a `commitID` only when `mutatedDocumentIDs()` is not empty. Read `system:data_sync_info` with `execute` when you need a snapshot. If you observe it, use one small observer per screen, not one per list row, and rebuild only when the derived value changes. Use the presence API for connectivity indicators.

**Why this matters:** Ditto is offline-first, so there is no single "synced" state to wait for. According to the Ditto documentation, observers on `system:data_sync_info` fire every 500 ms, so using them in many widgets can waste CPU and battery. A statement that changed nothing still gets a `commitID`, which peers confirm only with a later commit (up to about 30 seconds later), and `sync_session_status` stays `"Connected"` for about 73 seconds after a peer disconnects (SDK 5.1.0).

**Best-practices guide:** Monitoring Sync Status

---

## Section 6: Observers

### ☐ Consume observer results through the changes stream

**What this means:** Call `registerObserver` without `onChange`, and listen to `observer.changes` with a single `StreamSubscription`, or hand the stream to one `StreamBuilder`. In `dispose()`, cancel both the stream subscription and the observer. Register observers in `initState()` or in a service, never in `build()`.

**Why this matters:** An observer registered with `onChange` also queues every result in its `changes` stream. If nothing listens to that stream, memory grows with every update (SDK 5.1.0). `changes` is a single-subscription stream, and cancelling the stream subscription does not cancel a `StoreObserver`. `registerObserverV2` (Experimental, SDK 5.1+) starts observing as soon as it is registered, with or without `onChange`, so listen to its `changes` stream right after registering it.

**Best-practices guide:** Store Observers in Flutter

**Code Example**:

```dart
// ✅ GOOD: The recommended observer pattern for widgets.
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
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
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
  Widget build(BuildContext context) => ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return ListTile(
            key: ValueKey(order['_id']),
            title: Text('${order['_id']}'),
          );
        },
      );
}
```

### ☐ Add ORDER BY with a tie-breaker to observer queries

**What this means:** Whenever the order of results matters, add `ORDER BY` with a unique tie-breaker such as `_id`, for example `ORDER BY createdAt DESC, _id`. Give each list row a `ValueKey` based on `_id`.

**Why this matters:** Without `ORDER BY`, observer results have no guaranteed order, so rows can change position on every update. Sorting by a timestamp is reliable only when every value is written with the same fixed-precision helper (`utcTimestamp()`).

**Best-practices guide:** Stable ordering

**Code Example**:

```dart
// ❌ BAD: No ORDER BY; rows may change position between updates.
StoreObserver observeTasksUnordered(Ditto ditto) =>
    ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false');

// ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps.
StoreObserver observeTasksOrdered(Ditto ditto) => ditto.store.registerObserver(
      'SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id',
    );
```

### ☐ Keep observer callbacks fast, and use backpressure for slow work

**What this means:** Keep `registerObserver` listeners short and synchronous: copy the values, map them to models, and call `setState`. When an update triggers slow work such as an upload, an export, or heavy aggregation, use `registerObserverV2` with `await for`, or `registerObserverWithSignalNext` with `signalNext()` called in a `finally` block (both Experimental, SDK 5.1+). Never write to the observed collection from its own observer without a guard.

**Why this matters:** `registerObserver` has no backpressure: results keep arriving while an asynchronous listener waits, so work overlaps and queues up. With the backpressure APIs, Ditto holds back updates while your code is busy and then delivers the latest state. An observer registered with `registerObserverWithSignalNext` stops delivering updates if `signalNext()` is never called.

**Best-practices guide:** Keep observer callbacks fast, Backpressure (SDK 5.1+)

**Code Example**:

```dart
// ✅ GOOD: registerObserverV2 (Experimental) with await for: one update at a time.
class SensorAggregator {
  SensorAggregator(this._ditto);

  final Ditto _ditto;
  StoreObserverV2? _observer;

  Future<void> run(
    String deviceId,
    Future<void> Function(List<Map<String, dynamic>> readings) persistAggregates,
  ) async {
    stop(); // Cancel a previous run, if any.
    final observer = _ditto.store.registerObserverV2(
      'SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100',
      arguments: {'deviceId': deviceId},
    );
    _observer = observer;
    // While the body runs, the stream is paused and Ditto holds back the next update.
    await for (final result in observer.changes) {
      await persistAggregates(result.items.map((item) => item.value).toList());
    }
    // The loop ends when stop() cancels the observer.
  }

  void stop() => _observer?.cancel();
}
```

### ☐ Give each screen region its own small observer

**What this means:** Instead of observing a whole collection in the root widget, observe only what each region needs: a `COUNT(*)` query for a badge, and `WHERE` and `LIMIT` for a list rendered with `ListView.builder` and a `ValueKey` per row. With a state-management library, let one provider or controller own each observer and cancel it in its dispose hook. Use `Differ` when you need to know which items changed.

**Why this matters:** A whole-collection observer at the top of a screen rebuilds everything on every change, which causes dropped frames and lost scroll position or input focus. An observer delivers its full result for any change that affects its query.

**Best-practices guide:** Partial UI Updates, Diffing Results

---

## Section 7: Transactions

### ☐ Use transactions for multi-document changes that must be atomic

**What this means:** Use `ditto.store.transaction(...)` for changes that span several documents, such as closing an order and creating its invoice, for read-check-write sequences, and for consistent reads across several queries (`isReadOnly: true`). Give every transaction a `hint`. To roll back, throw or return `TransactionCompletionAction.rollback`. Catching a statement error inside the callback does not roll the transaction back.

**Why this matters:** If you catch an error and continue, the remaining changes are committed unless you roll back. The `hint` appears in log messages about long-running transactions, so you can tell which code started them. A single statement is already atomic, so wrapping it in a transaction adds nothing.

**Best-practices guide:** Using store.transaction

**Code Example**:

```dart
// ✅ GOOD: Close an order and create its invoice atomically.
Future<void> closeOrderWithInvoice(Ditto ditto, String orderId, String invoiceId) async {
  await ditto.store.transaction(
    hint: 'closeOrderWithInvoice', // Appears in logs; useful for debugging.
    (tx) async {
      final result = await tx.execute(
        'SELECT * FROM orders WHERE _id = :id',
        arguments: {'id': orderId},
      );
      if (result.items.isEmpty) {
        throw StateError('Order $orderId not found'); // Throwing rolls back.
      }
      await tx.execute(
        'INSERT INTO invoices DOCUMENTS (:invoice)',
        arguments: {
          'invoice': {'_id': invoiceId, 'orderId': orderId},
        },
      );
      await tx.execute(
        'UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id',
        arguments: {'id': orderId, 'status': 'closed', 'invoiceId': invoiceId},
      );
    },
  );
}
```

### ☐ Use only tx.execute inside a transaction, and never nest read-write transactions

**What this means:** Inside the callback, run every statement through the `Transaction` passed in (`tx.execute`). Never call `ditto.store.execute` there, never start a read-write transaction inside another one, and never keep the `Transaction` object after the callback returns.

**Why this matters:** In Flutter, `ditto.store.execute` inside a transaction throws a `DittoException`; on other platforms it can deadlock. Only one read-write transaction runs at a time, so a nested one waits forever for the outer one to finish. Flutter has no guard against this.

**Best-practices guide:** Transaction Rules

### ☐ Keep transactions short and do I/O outside them

**What this means:** A transaction should only read, decide, write, and return. Prepare network responses, files, user input, and attachments (`newAttachment`) before the transaction starts, and never make network calls, show dialogs, or await timers inside it. Track pending transactions and await them before `ditto.close()`.

**Why this matters:** While a read-write transaction runs, every other read-write transaction and plain write waits. Once a transaction has run for 10 seconds, Ditto logs a message about it every 5 seconds, starting at debug level and escalating to higher levels. `close()` does not wait for in-flight transactions.

**Best-practices guide:** Transaction Rules, Concurrency and Duration

**Code Example**:

```dart
// ❌ BAD: Network I/O, store.execute, and a nested transaction inside a transaction.
Future<void> badCheckout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'checkout'},
    );
    // Network call inside the transaction: blocks every other read-write transaction.
    await chargeCard();
    // Throws in Flutter (can deadlock on other platforms): use tx.execute instead.
    await ditto.store.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'paid'},
    );
    // Deadlock: the inner read-write transaction waits for the outer one.
    await ditto.store.transaction((inner) async {
      await inner.execute(
        'UPDATE orders SET paidAt = :paidAt WHERE _id = :id',
        arguments: {'id': orderId, 'paidAt': utcTimestamp()},
      );
    });
  });
}

// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
Future<void> checkout(
  Ditto ditto,
  String orderId,
  String paymentId, // a UUID, generated once per payment
  Future<void> Function() chargeCard,
) async {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(hint: 'recordPayment', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': 'paid',
        // utcTimestamp(): see "Store timestamps in UTC with a zone designator".
        'paidAt': utcTimestamp(),
      },
    );
    await tx.execute(
      'INSERT INTO payments DOCUMENTS (:payment)',
      arguments: {
        'payment': {'_id': paymentId, 'orderId': orderId},
      },
    );
  });
}
```

---

## Section 8: Deletion and Storage Management

### ☐ Choose between DELETE, soft delete, and EVICT deliberately

**What this means:** Each removal tool solves a different problem:
- `DELETE`: removes documents on every peer and leaves a tombstone; suited to data that is rarely edited concurrently, in deployments where devices sync regularly
- Soft delete (`UPDATE ... SET isDeleted = true`): for shared records that several devices edit, or for long offline periods
- `EVICT`: removes documents from this device only, to manage local storage
- In deployments with Small Peers only, contact Ditto support to review the design before relying on `DELETE`

**Why this matters:** Picking the wrong tool leads to resurrected data, half-deleted documents, or devices that run out of storage. A deletion does not happen in one central place: offline devices can reintroduce data, deletions merge with concurrent edits, and local storage is finite.

**Best-practices guide:** Choosing DELETE, Soft Delete, or EVICT

### ☐ Filter soft-deleted documents with coalesce(isDeleted, false) = false

**What this means:** Write `isDeleted: false` when you create a document, and set `isDeleted = true` and a UTC `deletedAt` when you delete it. Filter every query and observer with `coalesce(isDeleted, false) = false`. To benefit from an index, combine this filter with a selective indexed predicate such as `status = :status`.

**Why this matters:** `isDeleted != true` and `NOT isDeleted` silently exclude documents where the flag is missing or `null`, because comparisons with MISSING or NULL are never true. A `coalesce()` condition on the field cannot use an index by itself.

**Best-practices guide:** Soft Delete, Indexing soft-delete filters

**Code Example**:

```dart
// ✅ GOOD: Soft delete with a flag and a UTC timestamp.
Future<void> softDeleteOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      // utcTimestamp(): see "Store timestamps in UTC with a zone designator".
      // deletedAt is compared with cleanup cutoffs, so it needs the fixed-precision helper.
      'deletedAt': utcTimestamp(),
    },
  );
}

// ✅ GOOD: coalesce() treats a missing or null isDeleted field as false.
Future<List<Map<String, dynamic>>> activeOrders(Ditto ditto, String status) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE status = :status AND coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
    arguments: {'status': status},
  );
  return result.items.map((item) => item.value).toList();
}
```

### ☐ Keep soft-deleted documents in the subscription until every device has the flag

**What this means:** Do not exclude flagged documents from the subscription; hide them in local queries instead. To clean them up, choose one of two approaches:
- Subscribe to the whole collection (or partition), and after a retention period run a `DELETE` on Ditto Server or on an authorized peer
- Subscribe to active documents plus documents deleted within a retention window, and on each device evict exactly the older ones

**Why this matters:** A subscription that excludes flagged documents stops requesting a document as soon as it is flagged. In our testing with SDK 5.1.0, the flag still arrived, but later changes, including a restore, did not. Subscriptions also do not change local results: cancelling or narrowing one never deletes local data, and its filter does not hide local documents. Every local query and observer must therefore filter out flagged documents itself.

**Best-practices guide:** Soft delete, subscriptions, and cleanup

### ☐ Avoid DELETE for concurrently edited data and long offline periods

**What this means:** Use `DELETE` only when both of these hold: no other device updates the same document concurrently, and every device connects within the tombstone TTL (`TOMBSTONE_TTL_HOURS`, 7 days by default on Small Peers). If you raise `TOMBSTONE_TTL_HOURS`, keep it at or below the Ditto Server tombstone TTL, and apply it after every open. Make the UI tolerate documents with `null` or missing fields.

**Why this matters:** When a deletion merges with a concurrent update, the result is a husk document: the document is not deleted, even when the `DELETE` is the later write. The updated fields keep their values (or become `null` if the deletion was later), and all other fields become missing (SDK 5.1.0). A device that stays offline longer than the TTL can resurrect deleted data (zombie data). A Small Peer tombstone TTL above the Ditto Server tombstone TTL makes tombstones sync back to the server again and again.

**Best-practices guide:** Husk documents, Tombstone TTL and reaping

### ☐ Target deletions and evictions with WHERE _id IN :ids

**What this means:** Remove specific documents with `WHERE _id = :id` or `WHERE _id IN :ids`; both are planned as an ID scan. Do not write `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate, that is, without a `WHERE` clause or with `WHERE true`.

**Why this matters:** In SDK 5.1.0, such a statement completes without an error but removes nothing. The `WHERE _id` form is just as efficient and works reliably.

**Best-practices guide:** DELETE and Tombstones

**Code Example**:

```dart
// ✅ GOOD: Delete by ID with WHERE (planned as an ID scan).
Future<void> deleteOrders(Ditto ditto, List<String> ids) async {
  await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
}

// ❌ BAD: Completes without an error, but deletes nothing in SDK 5.1.0.
Future<void> deleteOrderWithUseIds(Ditto ditto) async {
  await ditto.store.execute("DELETE FROM orders USE IDS 'order-1'");
}
```

### ☐ Cancel or narrow subscriptions before EVICT

**What this means:** Evict only documents that no active subscription matches. First cancel or narrow the affected subscriptions, then write the eviction as the exact complement of the new subscription: for example, subscribe to `createdAt >= :cutoff` and evict `createdAt < :cutoff`, with the same cutoff. Data that was already in transit can still arrive after you cancel. If the device must not keep it, run the eviction again later, for example on the next app start or in a periodic cleanup.

**Why this matters:** If an active subscription still matches an evicted document, connected peers notice that it is missing and sync it straight back, so you pay the sync cost without freeing any space.

**Best-practices guide:** EVICT, Time-based eviction

**Code Example**:

```dart
// ✅ GOOD: Keep the last 7 days of orders. The subscription and the eviction
// use the same cutoff with complementary operators.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  static const retention = Duration(days: 7);
  SyncSubscription? _subscription;

  // Same fixed-precision format as createdAt (utcTimestamp(): see
  // "Store timestamps in UTC with a zone designator").
  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, at most about once a day.
  Future<void> evictExpired() async {
    final cutoff = _cutoff();
    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();
    try {
      // 2. Evict exactly the complement of the new subscription.
      await ditto.store.execute(
        'EVICT FROM orders WHERE createdAt < :cutoff',
        arguments: {'cutoff': cutoff},
      );
    } finally {
      // 3. Subscribe again with the moved boundary, even if the eviction failed.
      _subscription = _subscribeFrom(cutoff);
    }
  }

  SyncSubscription _subscribeFrom(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE createdAt >= :cutoff',
        arguments: {'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}
```

### ☐ Evict on a schedule, at most about once per day

**What this means:** Run eviction as a scheduled maintenance task during quiet periods, such as after hours, and never on screen changes. Split a large cleanup into batches with `LIMIT` after cancelling or narrowing every subscription that matches the documents: for example, run `EVICT ... LIMIT 1000 RETURNING COUNT(*) AS evicted` in a loop until nothing is left. If Ditto warns that post-eviction cleanup runs too often (SDK 5.1+), evict less often.

**Why this matters:** The local `EVICT` itself is fast, but each eviction triggers a resync with every connected peer, which costs network traffic and processing on those peers. Batching keeps each write transaction short but does not reduce that cost.

**Best-practices guide:** Eviction frequency, Batching evictions

### ☐ Monitor storage with on-demand queries

**What this means:** Read storage usage and document counts from `system:system_info` with `execute`, for example from a diagnostics screen or a daily maintenance task. Use keys such as `fs_usage_total` and `collection_num_docs[...]`, and take the newest row for each key. Pair monitoring with a retention policy.

**Why this matters:** The values are collected periodically, so they can lag behind recent writes. A long-lived observer on `system:system_info` runs every 500 ms, even when nothing has changed.

**Best-practices guide:** Monitoring Storage

---

## Section 9: Indexing and Query Performance

### ☐ Create indexes at startup with CREATE INDEX IF NOT EXISTS

**What this means:** Create the indexes your queries need on every device, after `Ditto.open()` and before any query or observer runs. Skip this step on Flutter Web: its in-memory store does not support indexes. `IF NOT EXISTS` checks only the index name, so to change a definition, create the index under a new name. In composite indexes (SDK 5.1+), list the equality fields first and the range or sort field last. Drop indexes that no query uses.

**Why this matters:** Indexes persist across restarts, but they are local to each device and are not synced, so every device must create its own. Creating an index on demand, right before a query, scans the whole collection at that moment. Every unused index slows down writes and takes up storage.

**Best-practices guide:** Creating Indexes

**Code Example**:

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

### ☐ Index the join key of every inner JOIN collection

**What this means:** Create an index on the join key of the inner (joined) collection, or join on the inner collection's `_id`, which needs no extra index. On large collections, do not silence the missing-index error with `USE INDEX ''`. Qualify every field with its collection alias.

**Why this matters:** Joins run as nested loops. If the lookup in the inner collection can use neither an index nor `_id`, the query fails with "Joining to ... disallowed without appropriate index support". `USE INDEX ''` allows a scan instead, but then every outer row scans the whole inner collection.

**Best-practices guide:** Index requirement

**Code Example**:

```sql
-- ✅ GOOD: Index the join key of the inner collection
CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)

SELECT c.name, o._id AS orderId, o.total
FROM customers c
JOIN orders o ON o.customerId = c._id
WHERE c.tier = 'gold'
ORDER BY c.name, o.total DESC
```

### ☐ Write predicates that the planner can serve from an index

**What this means:** Compare indexed fields directly, and apply functions to the value, not to the field:
- Do not wrap an indexed field in a function, as in `lower(name) = :name`
- Make sure every branch of an `OR` can use an index
- Use `LIKE 'abc%'` instead of `starts_with()`
- Match the key order and sort direction of a composite index, and index the full path you filter on, such as `address.city`
- Keep each field's CRDT type declaration consistent, and do not index fields that are written with more than one type

**Why this matters:** The planner picks indexes by rules, not by statistics. A function on the field, an `OR` branch without an index, or `starts_with()` makes the query fall back to a collection scan. An indexed field written with mixed CRDT type declarations can produce incorrect or mis-ordered results.

**Best-practices guide:** Index Usage Rules

### ☐ Check query plans with ADVISE and EXPLAIN during development

**What this means:** Prefix important queries with `ADVISE` (SDK 5.1+) to get index suggestions. Copy the suggested `CREATE INDEX IF NOT EXISTS` statements into your startup code, and confirm the new plan with `EXPLAIN`. To measure where time is spent, use `PROFILE`. Never run `ADVISE AND PROVISION` from production code.

**Why this matters:** `ADVISE` and `EXPLAIN` only plan the statement and never execute it, so neither can measure performance. `ADVISE AND PROVISION` creates indexes as a side effect, so which indexes exist would depend on whichever queries happened to run.

**Best-practices guide:** ADVISE (SDK 5.1+), EXPLAIN and PROFILE

**Code Example**:

```sql
-- Index suggestions for a query (planned, not executed)
ADVISE SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC

-- Confirm the access path after creating the suggested index
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC
```

### ☐ Keep local queries lean

**What this means:** Let the query do the work:
- Filter in `WHERE`, not in Dart
- Select only the fields the screen needs
- Page with `ORDER BY ... LIMIT`, count with `SELECT COUNT(*)`, and check existence with `LIMIT 1`
- Fetch several documents with one `WHERE _id IN :ids` query, not one query per ID

**Why this matters:** Every row that a `SELECT` returns is materialized in the result. Selecting only the fields you need (a projection) reduces decoding work and can enable covering scans. A `COUNT(*)` over a whole collection is answered without reading documents (SDK 5.1+). A loop of single-document queries pays the per-query cost once for every ID.

**Best-practices guide:** Query Scope and Execution

**Code Example**:

```dart
// ❌ BAD: One query per ID.
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

// ✅ GOOD: One query, planned as an ID scan.
Future<List<Map<String, dynamic>>> loadOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

### ☐ Surface slow DQL requests (SDK 5.1+)

**What this means:** During development, lower `DQL_SLOW_REQUEST_WARN_SECONDS` (default 60) so that slow requests are logged. Enable `DQL_REQUEST_TIMEOUT_SECONDS` (default 0, which means disabled) only after your code handles the timeout error for every query. Apply both settings after every open.

**Why this matters:** Slow queries often show up only with production-sized data. The warning includes the request details, so you can find which query to index or rewrite before users notice.

**Best-practices guide:** Long-running requests (SDK 5.1+)

---

## Section 10: Attachments

### ☐ Store binary data as attachments with a declared ATTACHMENT field

**What this means:** Create an attachment with `ditto.store.newAttachment(pathOrBytes, AttachmentMetadata({...}))`; metadata values must be strings. Store the returned object in a field declared as `ATTACHMENT`, for example `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)`. Compress and downscale media first. Never store base64-encoded files in document fields.

**Why this matters:** Base64 data counts toward the document size limit and is re-sent with the document. With an attachment, only its token syncs with the document. The file itself (the blob) is transferred only when a device fetches it, over a resumable protocol. The `ATTACHMENT` declaration works with and without strict mode.

**Best-practices guide:** Creating and Inserting Attachments, Size Guidance

**Code Example**:

```dart
// ✅ GOOD: Create an attachment from a file and insert it with a declared ATTACHMENT field.
Future<void> savePhoto(Ditto ditto, String photoId, String filePath) async {
  // The file is copied into Ditto's blob store.
  final attachment = await ditto.store.newAttachment(
    filePath,
    AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}), // String values only.
  );

  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'image': attachment,
        // utcTimestamp(): see "Store timestamps in UTC with a zone designator".
        'createdAt': utcTimestamp(),
      },
    },
  );
}
```

### ☐ Fetch attachments on demand and stop fetchers you no longer need

**What this means:** Subscriptions sync only the attachment token. Call `ditto.store.fetchAttachment(token, onEvent)` only when the content is needed, for example when the user opens a photo. Show lists with small thumbnail attachments. If the screen closes before the fetch completes, call `stop()` on the returned `AttachmentFetcher`.

**Why this matters:** Fetching every attachment as soon as its document syncs wastes bandwidth and storage, especially over Bluetooth LE, which is much slower than Wi-Fi.

**Best-practices guide:** Fetching Attachments, Thumbnail Pattern

**Code Example**:

```dart
// ✅ GOOD: Fetch the blob only when the image is shown; stop if the screen closes.
Future<AttachmentFetcher?> showPhoto(Ditto ditto, String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE _id = :id',
    arguments: {'id': photoId},
  );
  if (result.items.isEmpty) return null;
  final token = result.items.first.value['image'];
  if (token is! Map<String, dynamic>) return null; // Field missing or null.
  // The caller calls stop() on the returned fetcher if the screen closes first.
  return ditto.store.fetchAttachment(token, (event) async {
    if (event is AttachmentFetchEventCompleted) {
      final bytes = await event.attachment.data;
      debugPrint('fetched ${bytes.length} bytes');
    }
  });
}
```

### ☐ Plan for attachments that cannot be fetched yet

**What this means:** While the blob is unavailable, show a placeholder built from the attachment's metadata, and give the UI a timeout and a retry. Have hub devices, or a backend connected to Ditto Server, fetch the attachments that many devices need.

**Why this matters:** A device can fetch a blob only while it can reach a peer that holds the blob, and a device holds a blob only if it created or fetched it. The fetch API has no "not available" event: the fetch simply makes no progress. Do not rely on relays to pass blobs on across multiple hops. In our testing with SDK 5.1.0, a device two hops away could fetch a blob only after the device in between had fetched it itself.

**Best-practices guide:** Availability

### ☐ Replace attachments instead of editing them

**What this means:** Attachments are immutable. To change a file, create a new attachment and update the token field. To remove an attachment, do one of the following:
- `UNSET` the field with its type declared: `UPDATE COLLECTION photos (image ATTACHMENT) UNSET image ...`
- Delete the document
- Evict the document from the device

**Why this matters:** You cannot delete an attachment directly. On Small Peers, blobs that no document references are garbage-collected every 10 minutes. If history documents keep referencing old tokens, every version stays on the device.

**Best-practices guide:** Attachments Are Immutable

---

## Section 11: Security

### ☐ Authenticate production apps through a webhook provider

**What this means:** Connect with `DittoConfigConnectServer` and authenticate users through an authentication webhook that you operate. In the expiration handler, the app fetches a short-lived token from your backend. The webhook validates the token and returns the user ID, the session lifetime, and the permissions. Use `Authenticator.developmentProvider` and the development token from the Ditto Portal only during development.

**Why this matters:** Anyone who has the development token gets the same access, so it must never ship in a production build. Permissions are issued together with the credentials. With a moderate `expirationSeconds`, permission changes reach devices when they re-authenticate.

**Best-practices guide:** Authentication in Production

### ☐ Provision a privateKey for small-peers-only deployments

**What this means:** In production, always pass a `privateKey` to `DittoConfigConnectSmallPeersOnly`. Distribute the key through a controlled channel such as MDM or secure provisioning, and keep it and the offline license token in secure storage. Never hardcode keys, tokens, or API keys in source code.

**Why this matters:** Without a key, peers do not authenticate each other: any device with the SDK, your Database ID, and a license token can join and read all data. The SDK also documents this mode as unencrypted. Peers with different keys, or a peer without a key, never connect, and only `WARN` logs show why. A key in an app binary can be extracted by decompiling the app. Shared-key mode has no per-user identity: every key holder has full access, and you cannot revoke individual devices.

**Best-practices guide:** Small-Peers-Only Deployments

**Code Example**:

```dart
// ✅ GOOD: The key and license token come from secure provisioning.
Future<Ditto> openProvisionedSmallPeer({
  required Future<String> Function() readKeyFromSecureStorage,
  required Future<String> Function() readLicenseFromSecureStorage,
}) async {
  final ditto = await Ditto.open(
    DittoConfig(
      databaseID: 'YOUR_DATABASE_ID', // any UUID shared by all peers
      connect: DittoConfigConnectSmallPeersOnly(
        privateKey: await readKeyFromSecureStorage(),
      ),
    ),
  );
  // Required before sync.start() in small-peers-only mode.
  ditto.setOfflineOnlyLicenseToken(await readLicenseFromSecureStorage());
  ditto.sync.start(); // no expiration handler is needed in this mode
  return ditto;
}

// ❌ BAD: Without a privateKey, peers do not authenticate each other, and the
// SDK documents this mode as unencrypted.
Future<Ditto> openUnprotectedSmallPeer() {
  return Ditto.open(
    const DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectSmallPeersOnly(),
    ),
  );
}
```

### ☐ Encode permission scopes in an immutable _id

**What this means:** The permission queries that your webhook returns can reference only the document's `_id`. Decide the permission boundaries (user, store, organization) before you ship, and put them into a structured `_id` such as `{"storeId": "store-1", "orderId": "..."}`. Rules such as `_id.storeId == 'store-1'` can then match them. Permission queries use Ditto's legacy query syntax, not DQL, so compare with `==`, not with the DQL `=`. Grant each role only the `read` and `write` rules it needs.

**Why this matters:** Permissions based on mutable fields such as `status` or `ownerId` are not supported, and `_id` cannot be changed after a document is created. Sync scopes, `syncGroup`, and client-side checks do not provide access control.

**Best-practices guide:** Permissions

### ☐ Validate input and treat synced data as untrusted

**What this means:** Before an `INSERT` or `UPDATE`, validate required fields, types, and value ranges, and pass every value as a parameter. When you render or process documents received from other peers, treat them as untrusted input.

**Why this matters:** Ditto collections have no schema, so validating data before writing it is your application's job. Parameters keep values separate from the query text, so input cannot change the meaning of a statement.

**Best-practices guide:** Input Validation and Query Parameters

**Code Example**:

```dart
// ✅ GOOD: Validate, then pass values as parameters.
Future<void> updateOrderStatus(Ditto ditto, String orderId, String status) async {
  const allowedStatuses = {'open', 'preparing', 'done'};
  if (orderId.isEmpty || !allowedStatuses.contains(status)) {
    throw ArgumentError('Invalid order update');
  }
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'id': orderId, 'status': status},
  );
}
```

### ☐ Protect sensitive data at rest and keep it out of metadata

**What this means:** Ditto does not encrypt its local database at rest, and no supported API enables it. Instead:
- Rely on OS protection: screen lock and file-based encryption, enforced through MDM on managed devices
- Encrypt sensitive field values in the app before writing them, and keep the keys in secure storage
- Never store secrets in documents, peer metadata, or `identityServiceMetadata`

**Why this matters:** OS protection requires a passcode or screen lock. With the default settings, it protects data mainly while the device is powered off or has not been unlocked since it started. An app installed from a public app store cannot enforce device encryption. Peer metadata and identity metadata are shared with every peer in the mesh, not only with directly connected peers.

**Best-practices guide:** Data at Rest, Identity metadata is visible to the mesh

### ☐ Reject identities in the webhook before revoking certificates (SDK 5.1+)

**What this means:** To remove a user's or device's access, first reject the identity in your authentication webhook, then create a certificate revocation through the Ditto Server HTTP API. Keep `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED` at its default (enabled).

**Why this matters:** If the webhook still accepts the user, the device re-authenticates and regains access, because a revocation applies only to certificates issued before it was created. Revocations are permanent. They reach offline peers when those peers next connect, and they do not apply to shared-key deployments.

**Best-practices guide:** Certificate Revocation (SDK 5.1+)

---

## Section 12: Logging, Diagnostics, and Testing

### ☐ Configure logging before opening Ditto

**What this means:** Before `Ditto.open()`, call `await Ditto.init()` and then set `DittoLogger.minimumLogLevel`, for example to `kReleaseMode ? LogLevel.warning : LogLevel.debug`. Forward warnings and errors with `DittoLogger.customLogCallback`. Set the callback again before every `Ditto.open()`, because `ditto.close()` resets it. Use `LogLevel.verbose` only for short, targeted investigations.

**Why this matters:** `DittoLogger` throws until the SDK is initialized. Verbose logging can significantly slow down replication. A production console level of `warning` does not limit later diagnosis: on-disk logs always include debug-level entries, which you can export with `DittoLogger.exportLogs()` or request from the Ditto Portal.

**Best-practices guide:** Logging

**Code Example**:

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

### ☐ Use presence and transport conditions for connectivity diagnostics

**What this means:** Show connection indicators with `ditto.presence.observe(...)`, and stop the returned `PresenceObserver` when you no longer need it. Use `ditto.observeTransportConditions()` (SDK 5.1+) to detect missing permissions or disabled radios, and `DittoSyncPermissions` to find missing runtime permissions on Android. Keep peer metadata small and free of sensitive data.

**Why this matters:** Transport configuration changes do not throw, so transport conditions are how you find out why peers do not connect. Peer metadata is shared with every peer in the mesh.

**Best-practices guide:** Diagnosing transport problems (SDK 5.1+), Presence

**Code Example**:

```dart
// ✅ GOOD: Surface transport problems and missing permissions.
Future<TransportConditionsObserver> watchTransports(Ditto ditto) async {
  final missing = await DittoSyncPermissions().missingPermissions();
  if (missing.isNotEmpty) {
    debugPrint('Ditto is missing Android permissions: $missing');
  }

  // Call stop() on the returned observer when it is no longer needed.
  return ditto.observeTransportConditions((event) {
    if (event.condition != TransportCondition.ok) {
      debugPrint('Transport ${event.source.name}: ${event.condition.name}');
    }
  });
}
```

### ☐ Test your DQL statements against a real local store

**What this means:** Put Ditto behind a repository interface so that you can unit-test the UI and business logic with mocks. Test every DQL statement against a real small-peers-only instance, with a fresh temporary persistence directory for each test. In these tests, do not start sync, apply the same system parameters as the app, and close every instance with `addTearDown`. Run them with the `integration_test` package on a desktop or device target.

**Why this matters:** Most bugs come from the data model and the queries, not from the SDK. Local store tests need no license token or network, so they can run in CI. Sharing a persistence directory between tests, or opening it twice, can make `Ditto.open()` never complete.

**Best-practices guide:** A Test Helper for a Local Store

**Code Example**:

```dart
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Opens a Ditto instance for one test. Sync is never started, so no
/// license token or network connection is needed.
Future<Ditto> openTestDitto({
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  final ditto = await Ditto.open(
    DittoConfig(
      databaseID: '00000000-0000-4000-8000-000000000001',
      persistenceDirectory: directory.path,
    ),
  );
  // Runs after the test, even when it fails.
  addTearDown(() async {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  });
  // Apply the app's system parameters and indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('re-upserting unchanged data is a no-op', () async {
    final ditto = await openTestDitto();
    const product = {'_id': 'p1', 'name': 'Pen', 'priceCents': 250};
    const upsert =
        'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF';
    await ditto.store.execute(upsert, arguments: {'product': product});
    final again = await ditto.store.execute(upsert, arguments: {'product': product});
    expect(again.mutatedDocumentIDs(), isEmpty);
  });
}
```

### ☐ Test the behaviors that fail silently

**What this means:** Write tests that assert:
- The write shapes your code relies on: field-level updates, maps keyed by ID, and re-upserts that change nothing
- Soft-delete filters, with the flag set to `true`, `false`, `null`, and missing
- Deletions with `WHERE _id IN :ids`
- Observer and subscription cleanup: `isCancelled` after `cancel()`

Test concurrent merges, deletion propagation, relay, and attachments separately, with several Ditto instances that sync for real. Most of these tests can run in one test process over localhost, and they need an offline license token.

**Why this matters:** These bugs raise no exception: a filter hides documents, a statement removes nothing, or an observer keeps running. A single device cannot reproduce a concurrent merge, but it can verify that your code produces writes that merge well. Test your own business rules rather than basic SDK behavior.

**Best-practices guide:** Testing Strategies
