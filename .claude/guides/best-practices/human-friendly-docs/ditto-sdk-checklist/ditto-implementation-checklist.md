# Ditto SDK Implementation Checklist

> **Version**: 2.2
> **Last Updated**: 2026-10-08
> **Applies to**: Ditto SDK 5.1.0 (Flutter `ditto_live` 5.1.0)
>
> **Ditto documentation**: [https://docs.ditto.live](https://docs.ditto.live)
>
> Each item names the section of the Ditto SDK Best Practices guide (`ditto.md`) that explains it in detail.

## Section 1: Setup and Lifecycle

### ☐ Pin ditto_live 5.1.0 and meet the platform requirements

**What this means:** Pin the SDK version in `pubspec.yaml` so that every developer and CI build uses the same release, and check the requirements of `ditto_live` 5.1.0:
- Dart 3.5.4 or later and Flutter 3.24.5 or later
- iOS 15+ and macOS 12+ on arm64 only (Intel Macs and x86_64 simulators are not supported), with CocoaPods
- Android `minSdk` 24, set explicitly in your app's Gradle file, and Kotlin Gradle plugin 2.0 or later
- Bluetooth, local network, and nearby-device permissions for peer-to-peer sync, as listed in the Flutter install guide, requested before sync starts
- On Flutter Web, data is kept in memory only, sync works only over WebSocket with Ditto Server, and indexes are not supported

**Why this matters:** A floating version lets developers, CI, and devices run different SDK releases. Missing permissions or an unsupported architecture surface late, often as peers that never connect rather than as a clear error.

**Best-practices guide:** Requirements

**Code Example**:

```yaml
dependencies:
  ditto_live: 5.1.0   # or ^5.1.0 to accept compatible 5.x updates
```

### ☐ Open one Ditto instance per persistence directory and share it

**What this means:** Open Ditto once at app start with `await Ditto.open(DittoConfig(...))` and pass the instance to the parts of the app that need it, for example through dependency injection or a service object. Guard against concurrent opens by sharing one in-flight `Future`. Never open a new instance per screen or request, and never reopen a directory before `close()` has completed.

**Why this matters:** Only one `Ditto` instance can use a persistence directory at a time. In Flutter, a second `Ditto.open()` on a directory that is already open may never complete instead of throwing, so the code that awaits it can stop silently.

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

**What this means:** Pick the `connect` mode of `DittoConfig` for each build:
- `DittoConfigConnectServer(url: ...)`: devices sync through Ditto Server and with each other, and must authenticate. Copy the Server URL from the Ditto Portal exactly as shown.
- `DittoConfigConnectSmallPeersOnly(privateKey: key)`: devices sync only with each other, using a shared key (TLS 1.3).
- `DittoConfigConnectSmallPeersOnly()` without a key: local store tests and development only (sync still requires an offline license token).

**Why this matters:** The mode decides how devices authenticate and whether traffic is encrypted. Without a `privateKey`, traffic between peers is not encrypted in transit. `databaseID` must be a valid UUID; do not rely on `Ditto.open()` to reject a leftover placeholder.

**Best-practices guide:** Initializing Ditto

### ☐ Set the offline license token before starting sync in small-peers-only mode

**What this means:** For small-peers-only deployments, obtain an offline license token from Ditto and call `ditto.setOfflineOnlyLicenseToken(token)` before `ditto.sync.start()`. No expiration handler is needed in this mode.

**Why this matters:** In small-peers-only mode, `ditto.sync.start()` throws until a valid offline license token is set, whether or not a private key is used. The local store works without a license, which is why tests that never start sync can open Ditto without one.

**Best-practices guide:** Initializing Ditto

**Code Example**:

```dart
// ✅ GOOD: Small-peers-only deployment with a shared key and a license token.
Future<Ditto> openSmallPeersOnly({
  required String sharedKey, // provisioned securely, never hardcoded
  required String offlineLicenseToken, // issued by Ditto
}) async {
  final ditto = await Ditto.open(
    DittoConfig(
      databaseID: 'YOUR_DATABASE_ID', // any UUID shared by all peers
      connect: DittoConfigConnectSmallPeersOnly(privateKey: sharedKey),
    ),
  );
  // Required before sync.start() in small-peers-only mode.
  ditto.setOfflineOnlyLicenseToken(offlineLicenseToken);
  ditto.sync.start(); // no expiration handler is needed in this mode
  return ditto;
}
```

### ☐ Set the authentication expiration handler before ditto.sync.start()

**What this means:** With `DittoConfigConnectServer`, register `await ditto.auth.setExpirationHandler(...)` before starting sync. Inside the handler:
- Fetch a fresh token from your backend and call `ditto.auth.login(token: ..., provider: ...)`
- Check `response.exception`: `login()` does not throw when the token is rejected or the server is unreachable
- Catch errors from your own token code and report them; never throw or rethrow from the handler

**Why this matters:** For server connections, `ditto.sync.start()` throws when no handler is set. The handler is called again before credentials expire, so a cached token breaks refreshes. Its return type is `void`, so an error thrown inside becomes an unhandled asynchronous error that Ditto never receives.

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

**What this means:** System parameters set with `ALTER SYSTEM SET` are kept in memory only. Apply them in one startup function every time you open Ditto, after `Ditto.open()` and before `ditto.sync.start()`, running queries, or registering observers (subscriptions may be registered first). Confirm a value with `SHOW` when needed, and restore a default with `ALTER SYSTEM RESET`.

**Why this matters:** After a restart, or after closing and reopening Ditto, every parameter is back at its default. Settings such as `DQL_STRICT_MODE`, `USER_COLLECTION_SYNC_SCOPES`, and `TOMBSTONE_TTL_HOURS` silently revert, and sync scopes applied after sync has started can let data sync unintentionally.

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

**What this means:** `ditto.sync.start()` and `ditto.sync.stop()` return `void`, so do not `await` them. `start()` throws when a prerequisite (expiration handler or offline license token) is missing and does nothing while sync is active (`ditto.sync.isActive`). To pause syncing in the background, call `stop()` and start again on resume; do not call `ditto.close()` when the app is paused.

**Why this matters:** Awaiting a `void` call is a compile error in Dart. `close()` is final for that instance: every later call throws `DittoClosedException`, and you would have to open a new instance and register all subscriptions and observers again. After `stop()`, the local store remains fully usable.

**Best-practices guide:** Starting and Stopping Sync

**Code Example**:

```dart
// ✅ GOOD: Pause sync in the background without closing Ditto.
class SyncLifecycle with WidgetsBindingObserver {
  SyncLifecycle(this.ditto) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ditto ditto;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        ditto.sync.stop(); // the local store stays usable
      case AppLifecycleState.resumed:
        if (!ditto.sync.isActive) {
          ditto.sync.start();
        }
      default:
        break;
    }
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
```

### ☐ Change transport settings with updateTransportConfig()

**What this means:** `TransportConfig` is immutable. Use `ditto.updateTransportConfig((config) { ... })`, which starts from the current configuration, and change only what you need, for example with `setAllPeerToPeerEnabled()` or a single transport under `peerToPeer`. Treat `global.syncGroup` as an optimization, not as a security boundary.

**Why this matters:** A new `TransportConfig()` has every transport disabled, including the peer-to-peer transports that a default instance enables. Configuration changes are applied asynchronously and invalid values do not throw, so a hand-built configuration can silently stop devices from finding each other.

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

**What this means:** Cancel `StoreObserver`, `StoreObserverV2`, and `SyncSubscription` objects with `cancel()`; stop `PresenceObserver`, transport-condition observers, and `AttachmentFetcher` objects with `stop()`. Before `await ditto.close()`, await your own pending queries and transactions and cancel your `StreamSubscription`s on observer `changes` streams. Call `close()` only when the whole app no longer needs Ditto, and use the instance only from the isolate that opened it.

**Why this matters:** Ditto objects hold native resources; do not rely on garbage collection to cancel them. `close()` does not wait for in-flight `execute()` calls or transactions (they can fail with `DittoClosedException`), does not end an `await for` loop over the `changes` stream of a `StoreObserver` or `StoreObserverV2`, and resets `DittoLogger.customLogCallback`.

**Best-practices guide:** Resource Cleanup and Shutdown

---

## Section 2: DQL Queries and Results

### ☐ Pass every value as a DQL parameter

**What this means:** Reference values with `:name` placeholders and pass them in `arguments`: IDs, user input, dates, limits, and whole documents (`INSERT INTO orders DOCUMENTS (:order)`). Never build DQL strings with string interpolation or concatenation. Parameter names are case-sensitive.

**Why this matters:** Interpolated input can change the meaning of a statement (DQL injection). DQL interprets backslash escapes in string literals, so user text containing `\` or quotes can be altered or break the statement. Parameters keep their exact value and type, and a constant statement text lets Ditto reuse the prepared plan from its statement cache.

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

**What this means:** Pass an array parameter without parentheses: `WHERE status IN :statuses`. To test whether an array field contains a value, use `:tag IN tags` or `array_contains(tags, :tag)`.
- Do not write `IN (:statuses)`: the parentheses make a one-element list whose only element is the array, so nothing matches
- Do not filter with `ANY` or `EVERY ... SATISFIES ... END` over a parameter or literal array in `WHERE`, such as `ANY s IN :statuses SATISFIES s = status END` (returns no rows in SDK 5.1.0; use `status IN :statuses`)

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

**What this means:** Object literals written inside a DQL statement must use quoted keys, for example `{'status': 'open'}`. Better still, avoid inline objects and pass documents as parameters (`DOCUMENTS (:order)`).

**Why this matters:** Unquoted keys are rejected in `INSERT`, and in `SELECT` they silently produce an empty object (`{}`), because the unquoted key is evaluated as a field reference.

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

**Why this matters:** `SELECT * FROM collection` is a parser error (`expected identifier`), and a reserved name forces quoting in every statement that touches it.

**Best-practices guide:** Reserved words

### ☐ Distinguish MISSING from NULL in filters

**What this means:** A field can be absent from a document (MISSING) or present with the value `null`. A comparison involving either is neither true nor false, so `WHERE` does not return the row.
- Filter optional booleans with `coalesce(field, false) = false`
- Test existence with `IS MISSING` / `IS NOT MISSING`; `IS NOT NULL` is also true for a missing field
- Remove a field with `UNSET`; writing `null` keeps the field present

**Why this matters:** Documents written by older app versions or other platforms often lack newer fields, and a filter that ignores MISSING hides them without any error. Aggregates other than `COUNT` also return MISSING, not `0`, over zero matching documents.

**Best-practices guide:** MISSING and NULL

### ☐ Convert query results to plain Dart data right away

**What this means:** Map each `QueryResultItem` to a `Map` or to your own model class once, then let the `QueryResult` go out of scope. `items` is an `Iterable`: iterate it once. Call `mutatedDocumentIDs()` once and keep the list.

**Why this matters:** `QueryResult` and `QueryResultItem` objects reference native memory that is released only when the Dart object is garbage-collected. Storing them in state, caches, or across observer callbacks keeps that memory alive, and every pass over `items` decodes the rows again.

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

**What this means:** Add `RETURNING` to `INSERT`, `UPDATE`, `DELETE`, or `EVICT` to get the affected documents in `items` from the same statement: the documents after an `UPDATE`, and the documents before removal for `DELETE` and `EVICT`. Aggregates such as `RETURNING COUNT(*) AS removed` are allowed.

**Why this matters:** It replaces the "write, then query again" pattern, so the values you read are exactly the ones you wrote. For `DELETE`, it returns the removed content from the same atomic statement. `commitID` is populated as usual, and so is `mutatedDocumentIDs()`. Treat `items` as the result: include `_id` in the `RETURNING` projection when you need the IDs, rather than making that code depend on `mutatedDocumentIDs()`.

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
      'now': DateTime.now().toUtc().toIso8601String(),
    },
  );
  return result.items.map((item) => item.value).toList();
}
```

### ☐ Know the DQL expressions that fail or return nothing

**What this means:** Watch for these common mistakes:
- `type(x) = 'number'` never matches, because `type()` returns `'integer'` or `'float'`; use `is_number(x)`
- Swapped arguments to date functions return MISSING; keep `date_add(date, part, count)` and `date_diff(date1, date2, part)`
- `GROUP BY` and `HAVING` cannot reference projection aliases (the statement fails); repeat the expression
- Comparing values of different types, including with `=` and `!=` (`1 = 'a'`, `1 != 'a'`, `1 < 'a'`), evaluates to MISSING

**Why this matters:** Most of these look like valid queries, so the bug shows up as missing rows or fields in the UI rather than as an exception.

**Best-practices guide:** DQL Functions and Operators, GROUP BY and HAVING

---

## Section 3: Data Modeling

### ☐ Update individual fields instead of rewriting whole documents

**What this means:** Use `UPDATE ... SET` for the fields that changed. Do not read a document, change it in Dart, and write the whole map back with `ON ID CONFLICT DO UPDATE`. When a user edits a document, write only the fields that the user changed. Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports of data that another system owns: it skips fields whose values are equal, but it does not protect a stale in-memory copy, because an old value that differs from the stored one is written back.

**Why this matters:** Ditto syncs changes at field level. Rewriting every field makes the change larger and lets an unchanged value written by this device win a merge against a real concurrent change from another device. An `UPDATE` that writes a value that is already stored is still recorded as a mutation and can wake observers.

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

**Why this matters:** An array is a single register: when two devices change the same array concurrently, one version wins and the other change disappears without an error. Map entries merge independently, so concurrent additions and edits to different entries are all kept.

**Best-practices guide:** Arrays and Maps

**Code Example**:

```dart
/// ✅ GOOD: Adds or updates one line item of a map keyed by item ID.
/// The key is passed as data, never spliced into the query.
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

**What this means:** With the default settings, an object is a CRDT map, and `SET obj = {...}` or `ON ID CONFLICT DO UPDATE` merges the new keys into the existing object: keys you leave out remain, and `SET obj = {}` changes nothing. Update nested fields individually (`SET address.city = :city`), remove keys with `UNSET address.zip`, and replace an object as a whole with `UNSET` followed by `SET` in one transaction, or declare it as `REGISTER`. Only a `REGISTER` guarantees that concurrent edits never mix two versions.

**Why this matters:** Add-wins maps let offline edits from many devices merge without data loss, so removal must be explicit. Code that expects an assignment to replace an object leaves stale keys behind.

**Best-practices guide:** Assigning an object merges it, CRDT Types and Merge Behavior

**Code Example**:

```dart
// ✅ GOOD: Replace a whole MAP value: clear it, then write the new object,
// in one transaction so no reader sees the intermediate state.
Future<void> replaceShippingAddress(
  Ditto ditto,
  String orderId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders UNSET shippingAddress WHERE _id = :id',
      arguments: {'id': orderId},
    );
    await tx.execute(
      'UPDATE orders SET shippingAddress = :address WHERE _id = :id',
      arguments: {'id': orderId, 'address': newAddress},
    );
  }, hint: 'replaceShippingAddress');
}
```

### ☐ Use COUNTER for values that several devices change concurrently

**What this means:** Change counters with `APPLY f INCREMENT BY n` (a negative `n` decrements) and correct them occasionally with `APPLY f RESTART WITH n`. Declare the counter in every statement, including the `INSERT` that sets the initial value, for example `UPDATE COLLECTION inventory (stockCount COUNTER) ...`. Counters hold integers only, so count money in minor units.
- Do not use counters for unique sequence numbers or for balances that must never go below zero
- Do not use counters for values you can compute with `COUNT(*)`

**Why this matters:** Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only CRDT types that add concurrent changes together. `SET stock = stock - 1` on two devices loses one of the decrements. An undeclared `INSERT` stores the initial value as a register, and a later increment starts a separate counter at 0.

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

**Why this matters:** Offline devices cannot coordinate a sequence. Two of them create the same ID, and after sync the two documents become one document whose fields are mixed together. `_id` cannot be changed after creation, so an attribute that may change does not belong in it.

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

**What this means:** Ditto logs a warning for documents above 256 KiB (soft limit) and rejects `INSERT` and `UPDATE` statements that would exceed 5 MiB (hard limit). Store binary content as attachments, move data that grows without bound (history, readings, comments) into its own collection, and leave both limits at their defaults.

**Why this matters:** Document size affects storage and memory on every device, merge cost, and initial replication: over Bluetooth LE, a 256 KiB document takes about 10 seconds to replicate the first time. A write that exceeds the hard limit fails with a `DittoException`. To bring an oversized document back under the limits, move large values to attachments or a separate collection and remove them from the document with `UNSET`.

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

**Why this matters:** A stored derived value is a separate register. When two devices update the inputs concurrently, each recomputes the total from its own partial view, and after the merge the stored total may match neither device's inputs.

**Best-practices guide:** Do not store derived values that can diverge

### ☐ Keep transient and device-local state out of synced documents

**What this means:** Keep UI state (`isExpanded`, scroll positions), progress flags (`isSaving`, `uploadProgress`), and device-local data (file paths, cache locations) in widget state, a state-management layer, or local preferences, not in synced documents.

**Why this matters:** Every stored field costs storage and memory on every device that holds the document, adds to the initial replication of new documents, and adds to merge cost. A local file path is meaningless on another device.

**Best-practices guide:** Exclude transient and unnecessary fields

### ☐ Store timestamps in UTC with a zone designator

**What this means:** Write ISO-8601 strings in UTC (`DateTime.now().toUtc().toIso8601String()`, ending in `Z`) or epoch milliseconds, and use one helper with fixed precision for every timestamp that is sorted or compared. Compute time windows such as "last 7 days" in Dart and pass the boundary as a parameter.

**Why this matters:** Dart's local `DateTime.now().toIso8601String()` has no zone designator, and DQL date functions return MISSING for such strings without an error. On native platforms Dart emits microseconds (`.123456Z`) but omits them when they are zero (`.123Z`), while the web always emits milliseconds, and mixed precisions do not sort correctly as text.

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

**What this means:** Treat stored timestamps as approximate information for display, filtering, and retention. Where order matters, model the data so that the merge cannot go wrong: a counter, a map keyed by ID, or an audit log from which you derive the current state. Tolerate small negative durations between timestamps written by different devices.

**Why this matters:** Ditto resolves concurrent register writes with its own Hybrid Logical Clock, independently of your fields. Device clocks drift (Android devices can deviate by several seconds, and manually set clocks by much more), so comparing your own timestamps at read time lets the device with the fastest clock win.

**Best-practices guide:** Clock drift

### ☐ Record history as new facts, not overwrites

**What this means:** When every change matters (status transitions, adjustments, readings), record each change instead of overwriting one field:
- Bounded history of one document: an audit-log map keyed by a millisecond-precision UTC timestamp (plus a device identifier if two devices can record a change in the same millisecond), with the current state derived when you read it
- Unbounded history: append-only event documents with UUID IDs, with eviction planned from the start
- Latest value plus full history: write the current-state and history collections in one transaction

**Why this matters:** Overwriting a status register keeps only one of two concurrent transitions. Add-wins maps and never-updated event documents keep every change, and the parent document stays small when events live in their own collection.

**Best-practices guide:** Event History and Audit Logs

### ☐ Choose between embedding and separate collections deliberately

**What this means:** Embed sub-entities that belong to one parent and are read and written with it, as a map keyed by ID. Use a separate collection when the data has different permissions, is shared by many parents, is accessed independently, or grows without bound, and read it together with `JOIN` (SDK 5.1+). Copy a value from another document only when it is a snapshot or a subscription filter key.

**Why this matters:** An embedded write is atomic and syncs as one unit. A separate collection is a separate sync unit: it needs its own subscription and an index on the join key. Concurrent edits alone are not a reason to split, because map entries merge independently.

**Best-practices guide:** Relationships: Embedding, Separate Collections, and JOIN

### ☐ Seed shared default data with INITIAL DOCUMENTS

**What this means:** Insert default settings or built-in categories with `INSERT INTO c INITIAL DOCUMENTS (:doc)`, using fixed, well-known `_id` values and identical content in every app version. Running it on every launch is safe: existing documents, including edited ones, are kept. Use a regular `INSERT` with a new UUID for data that only one device creates.

**Why this matters:** A regular `INSERT` of shared defaults fails with an ID conflict on the second run, and `ON ID CONFLICT DO UPDATE` would overwrite users' edits. Seeding a deleted ID with different content (or an ID that was first created with a regular `INSERT`) leaves a document with `null` fields, so if the seed content may change in a later app version, use a soft delete (such as an `isArchived` flag) for seed documents that users can remove. Initial documents sync like any other document.

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

**What this means:** Add new fields and read them with defaults for older documents. Instead of changing a field's meaning, unit, or type, add a new field (for example `mileageKm`). For breaking changes, version the data (a schema version in a composite `_id`, or a new collection per version) and ship a version that reads both formats before one that writes the new format.

**Why this matters:** Devices run different app versions for weeks or months. A type change on an indexed field can make queries return wrong results, because only the most recently written type of a field is indexed. Backfilling old documents does not work, because devices that are offline during the backfill reintroduce them.

**Best-practices guide:** Schema Evolution

---

## Section 4: Strict Mode and Type Declarations

### ☐ Keep DQL_STRICT_MODE at its default (false) unless you need it

**What this means:** `DQL_STRICT_MODE` defaults to `false`: objects are inferred as maps, and MAP, COUNTER, and ATTACHMENT fields are inferred from the value or operation. Choose `true` only when almost every object needs whole-object replacement and you are prepared to declare every MAP, COUNTER, and ATTACHMENT field in every statement. If you opt in, apply the setting after every open and use the same value on every peer.

**Why this matters:** With strict mode enabled, undeclared objects become registers, nested updates fail, fields stored as MAP, COUNTER, or ATTACHMENT are invisible to `SELECT` and `WHERE` unless declared, and the SDK 5.1.0 query planner does not use secondary indexes. Each peer interprets synced data with its own setting, so mixed settings make data look missing.

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

**What this means:** Keep `REGISTER`, `COUNTER`, and `ATTACHMENT` declarations identical in every `INSERT`, `UPDATE`, and `SELECT` that touches a field, and keep these statements in one place, such as a repository class. Never write a counter field with `SET`, and introduce a new field instead of changing a field's CRDT type.

**Why this matters:** When statements disagree, a field holds several CRDT values at once and each statement sees a different one. An undeclared `INSERT` of 10 followed by `INCREMENT BY 1` yields 1, not 11, which looks like data loss even on a single device.

**Best-practices guide:** Keep type declarations consistent

---

## Section 5: Subscriptions and Sync

### ☐ Pair each screen's local queries with a long-lived subscription

**What this means:** `execute`, store observers, and transactions read only the local store and never fetch data from other peers. Data reaches a device only through subscriptions registered with `ditto.sync.registerSubscription(...)` while sync is running. Register the subscriptions that bring a screen's data to the device in an app-level or feature-level service (see "Own subscriptions in a long-lived service, not in widgets"), and read that data on the screen with local queries and observers.

**Why this matters:** A `SELECT` sees only documents created on the device or already delivered by a subscription. Without a matching subscription, a screen shows only local data, and the missing documents look like a query bug.

**Best-practices guide:** Core Principles, Where Queries Run

### ☐ Write subscriptions as SELECT * FROM collection with an optional WHERE clause

**What this means:** A subscription selects whole documents from one collection: `SELECT * FROM <collection> [WHERE ...]`, with values passed as parameters. Projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, and `USE IDS` are rejected when you register, and `LIMIT` and `ORDER BY` are rejected while `DQL_RESTRICT_SUBSCRIPTIONS` keeps its default value `true`. Keep that default, and sort and limit in local queries.

**Why this matters:** Subscriptions always sync whole documents. A subscription with `LIMIT` is stateful: the sync engine must re-evaluate it whenever a document crosses the limit boundary, which degrades sync performance. A stable subscription plus a local `ORDER BY ... LIMIT` query gives the same UI without that cost.

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

**What this means:** Register subscriptions when their data becomes relevant (app start, login, entering a store), keep a reference to each one in an app-level or feature-level service, and call `cancel()` on logout, when the user leaves the workspace, or when you register a replacement. Never register subscriptions in `build()` or on every screen visit. Use `ditto.sync.subscriptions` only for debugging, and read only `queryString` and `isCancelled` there: reading `queryArguments` of a subscription registered without arguments can terminate the app in SDK 5.1.0.

**Why this matters:** Subscriptions stay active until they are cancelled or Ditto is closed, so one registered in `build()` adds a new mesh-wide subscription on every rebuild. Do not rely on garbage collection to cancel them.

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

**What this means:** When the user changes a filter, search term, tab, or sort order, replace the local observer, not the subscription. Change subscriptions only when the set of data the device needs changes, such as switching to a different store, and no more often than about every 15 minutes.

**Why this matters:** Registering, cancelling, or changing a subscription makes peers across the mesh re-evaluate what they owe the device, which degrades sync throughput and can interrupt in-flight transfers. Observers are local and cheap to replace.

**Best-practices guide:** Filter locally instead of re-registering

### ☐ Scope subscriptions by stable partition keys

**What this means:** Filter subscriptions by fields that partition your data and do not change during a document's lifetime, such as `storeId`, `tenantId`, or `region`. Give devices in the same role the same subscriptions, give relay or hub devices at least everything the devices behind them need, and keep predicates simple. Subscribe to entire collections only for small reference data.

**Why this matters:** Unfiltered subscriptions on large collections cost storage, bandwidth, and battery on every device. Filters on mutable fields (`status`, `assignee`) and narrow relay devices leave devices without data, because a device can relay only documents that it stores itself.

**Best-practices guide:** Scope subscriptions to what the device needs, Multi-hop relay

### ☐ Subscribe to every collection that a JOIN reads

**What this means:** `JOIN` (SDK 5.1+) reads only documents that are already in the local store, and it is not allowed in subscriptions. Register a separate `SELECT * FROM c WHERE ...` subscription for each joined collection. If a child collection must be filtered by a key that lives on the parent, copy that key into the child documents.

**Why this matters:** A join never pulls related documents onto a device. Without a subscription for every joined collection, joined rows are silently missing on devices that did not create the data.

**Best-practices guide:** Joining Collections (SDK 5.1+)

### ☐ Apply sync scopes before sync starts, and do not use them for access control

**What this means:** `USER_COLLECTION_SYNC_SCOPES` limits where this device sends a collection (`AllPeers`, `BigPeerOnly`, `SmallPeersOnly`, or `LocalPeerOnly`). Set it after every `Ditto.open()` and before `ditto.sync.start()`, on every device that can store the collection (devices that write it, subscribe to it, or relay it). List every scoped collection in one statement: each `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` replaces the whole map, so collections left out of a later statement lose their scope.

**Why this matters:** Sync scopes are not persisted, and a scope is checked by the device that sends the data: a device without the setting can send the collection to Ditto Server. Scopes control what a device sends, not what other devices may read; use permissions for access control.

**Best-practices guide:** Sync Scopes

### ☐ Use sync status to enhance the UI, never to block it

**What this means:** Keep the `commitID` of important writes and compare it with `synced_up_to_local_commit_id` in `system:data_sync_info` to show an "uploaded" indicator. Read the collection with `execute` for snapshots; if you observe it, use one small observer (one per screen, not one per list row) whose callback rebuilds only when the derived value changes. Use the presence API for connectivity indicators.

**Why this matters:** Ditto is offline-first, so there is no single "synced" state to wait for. Observers on `system:data_sync_info` fire every 500 ms even when nothing changed, so such observers in many widgets waste CPU and battery.

**Best-practices guide:** Monitoring Sync Status

---

## Section 6: Observers

### ☐ Consume observer results through the changes stream

**What this means:** Call `registerObserver` without `onChange`, listen to `observer.changes` with a single `StreamSubscription` (or hand the stream to one `StreamBuilder`), and cancel both the stream subscription and the observer in `dispose()`. Register observers in `initState()` or in a service, never in `build()`.

**Why this matters:** When an observer is registered with `onChange`, every result is also queued in its `changes` stream; if nothing listens to it, memory grows with every update in SDK 5.1.0. `changes` is a single-subscription stream, and cancelling the stream subscription does not cancel a `StoreObserver`. `registerObserverV2` (Experimental, SDK 5.1+) starts observing as soon as it is registered, with or without `onChange`, so listen to its `changes` stream right after registering it.

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
  Widget build(BuildContext context) => ListView(
        children: [for (final o in _orders) ListTile(title: Text('${o['_id']}'))],
      );
}
```

### ☐ Add ORDER BY with a tie-breaker to observer queries

**What this means:** Whenever the order of results matters, include `ORDER BY` with a unique tie-breaker such as `_id`, for example `ORDER BY createdAt DESC, _id`, and give list rows a `ValueKey` based on `_id`.

**Why this matters:** Without `ORDER BY`, observer results have no guaranteed order, so rows can change position on every update.

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

**What this means:** Keep `registerObserver` listeners short and synchronous: copy values, map them to models, call `setState`. For uploads, exports, or heavy aggregation per update, use `registerObserverV2` with `await for`, or `registerObserverWithSignalNext` with `signalNext()` called in a `finally` block (both Experimental, SDK 5.1+). Do not write to the observed collection from its own observer without a guard.

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

**What this means:** Observe what each region needs instead of a whole collection in the root widget: a `COUNT(*)` query for a badge, `WHERE` and `LIMIT` for lists, and `ListView.builder` with a `ValueKey` per row. With state-management libraries, let one provider or controller own each observer and cancel it in its dispose hook. Use `Differ` when you need to know which items changed.

**Why this matters:** An observer delivers the full result for any change that affects its query. A whole-collection observer at the top of a screen rebuilds everything on every change, which causes dropped frames and lost scroll position or input focus.

**Best-practices guide:** Partial UI Updates, Diffing Results

---

## Section 7: Transactions

### ☐ Use transactions for multi-document changes that must be atomic

**What this means:** Use `ditto.store.transaction(...)` for changes that span several documents (closing an order and creating its invoice), for read-check-write sequences, and for consistent multi-query reads (`isReadOnly: true`). Give every transaction a `hint`. Throwing or returning `TransactionCompletionAction.rollback` rolls the transaction back; a statement error that you catch inside the callback does not.

**Why this matters:** A single statement is already atomic, so wrapping it in a transaction adds nothing. The `hint` appears in warnings about long-running transactions, which makes them traceable. If you catch an error and continue, the remaining changes are committed unless you roll back.

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

**Why this matters:** In Flutter, `ditto.store.execute` inside a transaction throws a `DittoException`; on other platforms it can deadlock. Only one read-write transaction runs at a time, so a nested one waits for the outer one forever, and Flutter has no guard against this.

**Best-practices guide:** Transaction Rules

### ☐ Keep transactions short and do I/O outside them

**What this means:** Read, decide, write, and return. Prepare network responses, files, user input, and attachments (`newAttachment`) before the transaction starts, and never make network calls, show dialogs, or await timers inside it. Track pending transactions and await them before `ditto.close()`.

**Why this matters:** While a read-write transaction runs, every other read-write transaction and plain write waits. Ditto logs warnings once a transaction has run for 10 seconds, and `close()` does not wait for in-flight transactions.

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
        arguments: {'id': orderId, 'paidAt': DateTime.now().toUtc().toIso8601String()},
      );
    });
  });
}

// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
Future<void> checkout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(hint: 'recordPayment', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': 'paid',
        'paidAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await tx.execute(
      'INSERT INTO payments DOCUMENTS (:payment)',
      arguments: {
        'payment': {'_id': 'payment-$orderId', 'orderId': orderId},
      },
    );
  });
}
```

---

## Section 8: Deletion and Storage Management

### ☐ Choose between DELETE, soft delete, and EVICT deliberately

**What this means:** Each removal tool solves a different problem:
- `DELETE`: removes documents for every peer and leaves a tombstone; suited to data that is rarely edited concurrently, in deployments where devices sync regularly
- Soft delete (`UPDATE ... SET isDeleted = true`): for shared records that several devices edit, or for long offline periods
- `EVICT`: removes documents from this device only, to manage local storage
- In deployments with Small Peers only, contact Ditto support to review the design before relying on `DELETE`

**Why this matters:** There is no single place where a deletion happens: offline devices can reintroduce data, deletions merge with concurrent edits, and local storage is finite. Picking the wrong tool leads to resurrected data, half-deleted documents, or full devices.

**Best-practices guide:** Choosing DELETE, Soft Delete, or EVICT

### ☐ Filter soft-deleted documents with coalesce(isDeleted, false) = false

**What this means:** When deleting, set `isDeleted = true` and a UTC `deletedAt`; when creating documents, write `isDeleted: false`. Filter with `coalesce(isDeleted, false) = false` in every query and observer. To use an index, combine it with a selective indexed predicate such as `status = :status`.

**Why this matters:** `isDeleted != true` and `NOT isDeleted` silently exclude documents where the flag is missing or `null`, because comparisons with MISSING or NULL are never true. `coalesce()` applied to the field cannot use an index by itself.

**Best-practices guide:** Soft Delete, Indexing soft-delete filters

**Code Example**:

```dart
// ✅ GOOD: Soft delete with a flag and a UTC timestamp.
Future<void> softDeleteOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
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

**What this means:** Do not exclude flagged documents from the subscription; hide them in local queries instead. Clean them up in one of two ways: subscribe to the whole collection (or partition) and run a `DELETE` after a retention period on Ditto Server or on an authorized peer, or subscribe to active documents plus documents deleted within a retention window and evict exactly the older ones on each device.

**Why this matters:** A subscription that excludes flagged documents stops requesting a document as soon as it is flagged. Cancelling or narrowing a subscription never deletes local data, and a subscription filter does not hide documents in local results, so every local query and observer must filter flagged documents itself.

**Best-practices guide:** Soft delete, subscriptions, and cleanup

### ☐ Avoid DELETE for concurrently edited data and long offline periods

**What this means:** Use `DELETE` only when the same document is not updated concurrently elsewhere and every device connects within the tombstone TTL (`TOMBSTONE_TTL_HOURS`, 7 days by default on Small Peers). If you raise `TOMBSTONE_TTL_HOURS`, keep it at or below the Ditto Server tombstone TTL and apply it after every open. Make the UI tolerate documents whose fields are `null`.

**Why this matters:** A deletion merged with a concurrent update produces a husk document: the updated fields keep their values, all other fields become `null`, and the document is not deleted. A device that is offline longer than the TTL can resurrect deleted data (zombie data), and a Small Peer tombstone TTL above the Ditto Server tombstone TTL makes tombstones sync back to the server repeatedly.

**Best-practices guide:** Husk documents, Tombstone TTL and reaping

### ☐ Target deletions and evictions with WHERE _id IN :ids

**What this means:** Remove specific documents with `WHERE _id = :id` or `WHERE _id IN :ids`; both are planned as an ID scan. Do not use `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`).

**Why this matters:** `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) completes without an error but removes nothing in SDK 5.1.0. The `WHERE` form is just as efficient and works reliably.

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

**What this means:** Evict only documents that are outside every active subscription: cancel or narrow the affected subscriptions first, and write the eviction as the exact complement of the new subscription (subscribe to `createdAt >= :cutoff`, evict `createdAt < :cutoff`, with the same cutoff). Data that was already being transferred can still arrive after you cancel, so if the device must not keep it, run the eviction again later (for example, on the next app start or in a periodic cleanup).

**Why this matters:** If an active subscription still matches an evicted document, connected peers notice that it is missing and sync it straight back, so you pay the sync cost without freeing any space.

**Best-practices guide:** EVICT, Time-based eviction

**Code Example**:

```dart
// ✅ GOOD: Keep the last 7 days of orders. The subscription and the eviction
// use the same cutoff with complementary operators.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  SyncSubscription? _subscription;

  String _cutoff() => DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 7))
      .toIso8601String();

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, at most about once a day.
  Future<void> evictExpired() async {
    final cutoff = _cutoff();
    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();
    // 2. Evict exactly the complement of the new subscription.
    await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );
    // 3. Subscribe again with the moved boundary.
    _subscription = _subscribeFrom(cutoff);
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

**What this means:** Run eviction as a scheduled maintenance task during quiet periods, such as after hours, never on screen changes. Split large cleanups with `LIMIT` after cancelling or narrowing every subscription that matches the documents, for example `EVICT ... LIMIT 1000 RETURNING COUNT(*) AS evicted` in a loop until nothing is left. Treat Ditto's warning about too-frequent post-eviction cleanup (SDK 5.1+) as a sign to evict less often.

**Why this matters:** Each eviction triggers a resync with every connected peer, which costs network traffic and processing on those peers even though the local `EVICT` itself is fast. Batching keeps individual write transactions short but does not reduce that cost.

**Best-practices guide:** Eviction frequency, Batching evictions

### ☐ Monitor storage with on-demand queries

**What this means:** Read storage usage and document counts from `system:system_info` (keys such as `fs_usage_total` and `collection_num_docs[...]`) with `execute`, for example from a diagnostics screen or a daily maintenance task, and use the newest row for each key. Combine monitoring with a retention policy.

**Why this matters:** The values are collected periodically and can lag behind recent writes, and long-lived observers on `system:system_info` run every 500 ms even when nothing changed.

**Best-practices guide:** Monitoring Storage

---

## Section 9: Indexing and Query Performance

### ☐ Create indexes at startup with CREATE INDEX IF NOT EXISTS

**What this means:** Create the indexes your queries need on every device, after `Ditto.open()` and before queries and observers run. Skip index creation on Flutter Web, where the in-memory store does not support indexes. `IF NOT EXISTS` checks only the name, so change a definition by creating the index under a new name. For composite indexes (SDK 5.1+), list equality fields first and the range or sort field last. Drop indexes that no query uses.

**Why this matters:** Indexes persist but are local to each device and are not synced. Creating an index on demand right before a query scans the whole collection, and every unused index costs write time and storage.

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
      // A missing index makes queries slower, not wrong: report and continue.
      showError(error);
    }
  }
}
```

### ☐ Index the join key of every inner JOIN collection

**What this means:** Create an index on the join key of the inner (joined) collection, or join on the inner collection's `_id`, which needs no extra index. Do not silence the index error with `USE INDEX ''` on large collections, and qualify every field with its alias.

**Why this matters:** Joins run as nested loops, and the inner lookup must use an index or an ID lookup unless you explicitly allow a scan with `USE INDEX ''`. Without one, the query fails with "Joining to ... disallowed without appropriate index support"; with `USE INDEX ''`, every outer row scans the whole inner collection.

**Best-practices guide:** Index requirement

**Code Example**:

```sql
-- ✅ GOOD: Index the join key of the inner collection
CREATE INDEX IF NOT EXISTS ix_orders_customerId ON orders (customerId)

SELECT c.name, o._id AS orderId, o.total
FROM customers c
JOIN orders o ON o.customerId = c._id
WHERE c.tier = 'gold'
ORDER BY c.name, o.total DESC
```

### ☐ Write predicates that the planner can serve from an index

**What this means:** Compare indexed fields directly and keep functions on the value side:
- Do not apply functions to indexed fields (`lower(name) = :name`)
- Make every `OR` branch indexable
- Use `LIKE 'abc%'` instead of `starts_with()`
- Match a composite index's key order and sort direction, and index the full path you filter on (`address.city`)
- Keep each field's CRDT type declaration consistent, and do not index fields that are written with more than one type

**Why this matters:** The planner chooses indexes by rules, not by statistics. A function on the field, an unindexed `OR` branch, or `starts_with()` falls back to a collection scan, and an indexed field written with mixed CRDT type declarations can produce incorrect or mis-ordered results.

**Best-practices guide:** Index Usage Rules

### ☐ Check query plans with ADVISE and EXPLAIN during development

**What this means:** Prefix important queries with `ADVISE` (SDK 5.1+) to get index suggestions, copy the suggested `CREATE INDEX IF NOT EXISTS` statements into your startup code, and confirm the plan with `EXPLAIN`. Use `PROFILE` to measure where time is spent. Never run `ADVISE AND PROVISION` from production code.

**Why this matters:** `ADVISE` plans the statement without executing it, and `EXPLAIN` never runs the query, so neither can measure performance. `ADVISE AND PROVISION` creates indexes as a side effect that depends on whichever queries happen to run.

**Best-practices guide:** ADVISE (SDK 5.1+), EXPLAIN and PROFILE

**Code Example**:

```sql
-- Index suggestions for a query (planned, not executed)
ADVISE SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC

-- Confirm the access path after creating the suggested index
EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC
```

### ☐ Keep local queries lean

**What this means:** Filter in `WHERE` rather than in Dart, project only the fields a screen needs, page with `ORDER BY ... LIMIT`, count with `SELECT COUNT(*)`, check existence with `LIMIT 1`, and fetch several documents with one `WHERE _id IN :ids` query instead of one query per ID.

**Why this matters:** Every row of a `SELECT` is materialized in the result. Projections reduce decoding work and can enable covering scans, a full-collection `COUNT(*)` is answered without reading documents (SDK 5.1+), and a loop of single-document queries multiplies the per-query cost.

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

**What this means:** Lower `DQL_SLOW_REQUEST_WARN_SECONDS` (default 60) during development to log slow requests, and enable `DQL_REQUEST_TIMEOUT_SECONDS` (default 0, disabled) only after your code handles the resulting timeout error for every query. Apply both after every open.

**Why this matters:** Slow queries often appear only with production-sized data. The warning includes the request details, so you can find the query to index or rewrite before users notice.

**Best-practices guide:** Long-running requests (SDK 5.1+)

---

## Section 10: Attachments

### ☐ Store binary data as attachments with a declared ATTACHMENT field

**What this means:** Create attachments with `ditto.store.newAttachment(pathOrBytes, AttachmentMetadata({...}))` (metadata values must be strings) and store the returned object in a field declared as `ATTACHMENT`, for example `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)`. Compress and downscale media first, and never store base64-encoded files in document fields.

**Why this matters:** Base64 data counts toward the document size limit and is re-sent with the document. An attachment's token syncs with the document, while the blob is transferred only when a device fetches it, through a resumable protocol. The declaration works both with and without strict mode.

**Best-practices guide:** Creating and Inserting Attachments

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
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}
```

### ☐ Fetch attachments on demand and stop fetchers you no longer need

**What this means:** Subscriptions sync only the attachment token. Call `ditto.store.fetchAttachment(token, onEvent)` when the content is needed, for example when the user opens a photo, show lists from small thumbnail attachments, and call `stop()` on the returned `AttachmentFetcher` if the screen closes before the fetch completes.

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
  final token = result.items.first.value['image'] as Map<String, dynamic>;
  return ditto.store.fetchAttachment(token, (event) async {
    if (event is AttachmentFetchEventCompleted) {
      final bytes = await event.attachment.data;
      debugPrint('fetched ${bytes.length} bytes');
    }
  });
  // Call stop() on the returned fetcher if the screen closes first.
}
```

### ☐ Plan for attachments that cannot be fetched yet

**What this means:** Show a placeholder with the attachment's metadata while the blob is unavailable, and use a timeout with a retry in the UI. Let hub devices, or a backend connected to Ditto Server, fetch attachments that many devices need.

**Why this matters:** A blob can be fetched only while a peer that holds it is reachable, and a blob exists on a device only if that device created or fetched it. The fetch API has no "not available" event: the fetch simply makes no progress.

**Best-practices guide:** Availability

### ☐ Replace attachments instead of editing them

**What this means:** Attachments are immutable. To change a file, create a new attachment and update the token field; to remove one, `UNSET` the field with its type declared (`UPDATE COLLECTION photos (image ATTACHMENT) UNSET image ...`), delete the document, or evict it from the device.

**Why this matters:** Attachments cannot be deleted directly. Blobs that no document references are garbage-collected on Small Peers every 10 minutes, so referencing old tokens from history documents keeps every version on the device.

**Best-practices guide:** Attachments Are Immutable

---

## Section 11: Security

### ☐ Authenticate production apps through a webhook provider

**What this means:** Connect with `DittoConfigConnectServer` and authenticate users through an authentication webhook that you operate: the app fetches a short-lived token from your backend in the expiration handler, and the webhook validates it and returns the user ID, session lifetime, and permissions. Use `Authenticator.developmentProvider` and the development token from the Ditto Portal only during development.

**Why this matters:** Anyone who has the development token gets the same access, so it must never ship in a production build. Permissions are issued together with the credentials, so a moderate `expirationSeconds` lets permission changes reach devices when they re-authenticate.

**Best-practices guide:** Authentication in Production

### ☐ Provision a privateKey for small-peers-only deployments

**What this means:** Always pass a `privateKey` to `DittoConfigConnectSmallPeersOnly` in production, distribute it through a controlled channel such as MDM or secure provisioning, and keep it and the offline license token in secure storage. Never hardcode keys, tokens, or API keys in source code.

**Why this matters:** Without a key, traffic is not encrypted in transit. Keys in an app binary can be extracted by decompiling it. Shared-key mode has no per-user identity, so every key holder has full access and individual devices cannot be revoked.

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
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectSmallPeersOnly(
        privateKey: await readKeyFromSecureStorage(),
      ),
    ),
  );
  ditto.setOfflineOnlyLicenseToken(await readLicenseFromSecureStorage());
  ditto.sync.start();
  return ditto;
}

// ❌ BAD: No privateKey means no encryption in transit.
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

**What this means:** Permission queries returned by your webhook can reference only the document's `_id`. Decide permission boundaries (user, store, organization) before shipping and put them into a structured `_id`, such as `{"storeId": "store-1", "orderId": "..."}`, matched by rules like `_id.storeId == 'store-1'`. Permission queries use Ditto's legacy query syntax, not DQL, so compare with `==`, not with the DQL `=`. Grant the narrowest `read` and `write` rules each role needs.

**Why this matters:** Permissions on mutable fields such as `status` or `ownerId` are not supported, and `_id` cannot be changed after creation. Sync scopes, `syncGroup`, and client-side checks are not access control.

**Best-practices guide:** Permissions

### ☐ Validate input and treat synced data as untrusted

**What this means:** Validate required fields, types, and ranges before `INSERT` or `UPDATE`, pass every value as a parameter, and treat documents received from other peers as untrusted input when you render or process them.

**Why this matters:** Ditto collections are schema-free, so the application is responsible for validating data before writing it. Parameters keep values separate from the query text, so input cannot change the meaning of a statement.

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

**What this means:** Ditto does not encrypt its local database at rest, and there is no supported API to enable it. Rely on OS protection (screen lock and file-based encryption, enforced through MDM on managed devices), encrypt sensitive field values in the app before writing them, and keep the keys in secure storage. Never store secrets in documents, peer metadata, or `identityServiceMetadata`.

**Why this matters:** OS protections require a passcode or screen lock and, with the default settings, protect data mainly while the device is powered off or has not been unlocked since it started; an app installed from a public app store cannot enforce device encryption. Peer metadata and identity metadata are shared with every peer in the mesh, not only with directly connected peers.

**Best-practices guide:** Data at Rest, Identity metadata is visible to the mesh

### ☐ Reject identities in the webhook before revoking certificates (SDK 5.1+)

**What this means:** To remove a user's or device's access, reject the identity in your authentication webhook first, then create the certificate revocation through the Ditto Server HTTP API. Keep `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED` at its default (enabled).

**Why this matters:** A revocation applies only to certificates issued before it was created; if the webhook still accepts the user, the device re-authenticates and regains access. Revocations are permanent, reach offline peers when they next connect, and do not apply to shared-key deployments.

**Best-practices guide:** Certificate Revocation (SDK 5.1+)

---

## Section 12: Logging, Diagnostics, and Testing

### ☐ Configure logging before opening Ditto

**What this means:** Call `await Ditto.init()`, then set `DittoLogger.minimumLogLevel` (for example `kReleaseMode ? LogLevel.warning : LogLevel.debug`) before `Ditto.open()`. Forward warnings and errors with `DittoLogger.customLogCallback`, and set the callback before every `Ditto.open()`, because `ditto.close()` resets it. Use `LogLevel.verbose` only for short, targeted investigations.

**Why this matters:** `DittoLogger` throws until the SDK is initialized, and verbose logging can significantly slow down replication. On-disk logs always include debug-level entries, so a production console level of `warning` does not reduce what you can export later with `DittoLogger.exportLogs()` or request from the Ditto Portal.

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

**What this means:** Use `ditto.presence.observe(...)` for connection indicators and stop the returned `PresenceObserver` when you no longer need it. Use `ditto.observeTransportConditions()` (SDK 5.1+) to surface missing permissions or disabled radios, and `DittoSyncPermissions` to find missing runtime permissions on Android. Keep peer metadata small and non-sensitive.

**Why this matters:** Transport configuration changes do not throw, so transport conditions are the way to see why peers do not connect. Peer metadata is shared with every peer in the mesh.

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

**What this means:** Keep Ditto behind a repository interface so that UI and business logic can be unit-tested with mocks, and test every DQL statement against a real small-peers-only instance with a fresh temporary persistence directory per test. Do not start sync in these tests, apply the same system parameters as the app, and close every instance with `addTearDown`. Run them with the `integration_test` package on a desktop or device target.

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
Future<Ditto> openTestDitto() async {
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
    await directory.delete(recursive: true);
  });
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

**What this means:** Assert the write shapes your code relies on (field-level updates, maps keyed by ID, no-op re-upserts), soft-delete filters with the flag set to `true`, `false`, `null`, and missing, deletions by `WHERE _id IN :ids`, and observer and subscription cleanup (`isCancelled` after `cancel()`). Test concurrent merges, deletion propagation, relay, and attachments separately, on multiple devices with real sync.

**Why this matters:** These bugs raise no exception: a filter hides documents, a statement removes nothing, or an observer keeps running. A single device cannot reproduce a concurrent merge, but it can verify that your code produces writes that merge well. Test your own business rules rather than basic SDK behavior.

**Best-practices guide:** Testing Strategies
