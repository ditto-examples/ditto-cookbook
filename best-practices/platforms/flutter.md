# Ditto on Flutter

This page shows how to apply the guide with the Flutter SDK, `ditto_live` 5.2.0: the API calls, the Flutter patterns for widgets and app lifecycle, and the behavior that is specific to this SDK. The rules themselves, the DQL, and the reasons are on the topic pages of the guide, which apply to every SDK; each section below links to them. The same sections exist for [JavaScript](javascript.md), [Kotlin](kotlin.md), and [Swift](swift.md).

Every example imports the SDK with `import 'package:ditto_live/ditto_live.dart';`. Placeholders such as `'YOUR_DATABASE_ID'`, `fetchAuthToken()`, and `showError()` stand for values and code from your own app.

## Installing the Flutter SDK

`ditto_live` 5.2.0 has the following requirements:

| Item | Requirement |
|---|---|
| Dart | 3.5.4 or later |
| Flutter | 3.24.5 or later |
| iOS | 15 or later |
| macOS | 12 or later |
| Apple architectures | arm64 only (Intel Macs and x86_64 simulators are not supported) |
| Apple dependency manager | CocoaPods (the Flutter plugin does not support Swift Package Manager) |
| Android | `minSdk` 24 (Android 7.0) or later, set explicitly in your app's Gradle file |
| Kotlin Gradle plugin | 2.0 or later |
| Windows / Linux | Windows 10 or later (x64); Linux x64 and AArch64 |
| Web | Supported with limitations (see below) |

Pin the SDK version in `pubspec.yaml` so every developer and CI build uses the same release:

```yaml
dependencies:
  ditto_live: 5.2.0   # or ^5.2.0 to accept compatible 5.x updates
```

**Platform setup**: Peer-to-peer sync needs platform permissions and configuration, such as Bluetooth and local network usage descriptions in `Info.plist` on iOS and macOS, and Bluetooth, Wi-Fi, and nearby-device permissions in `AndroidManifest.xml` on Android. Follow the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter) for the current list, and request runtime permissions (for example with the `permission_handler` package) before starting sync.

**Flutter Web limitations**:
- Data is stored **in memory only** and is lost when the page reloads.
- Sync works **only over WebSocket** with Ditto Server. Peer-to-peer transports are not available, and `setOfflineOnlyLicenseToken()` and `setAllPeerToPeerEnabled()` have no effect.
- The in-browser store does not support indexes. Skip `CREATE INDEX` on the Web, for example with `if (!kIsWeb)` from `package:flutter/foundation.dart` (or `Ditto.currentPlatform != SupportedPlatform.web`).
- Only the default Flutter Web build mode is supported, and the development server must be restarted after source changes.
- The WebAssembly assets can be served from a CDN with `Ditto.init(wasmUrl: ..., wasmShimUrl: ...)`.

## Opening Ditto in Flutter

- `await Ditto.open(config)` is the standard way to create an instance. It initializes the SDK automatically (SDK 5.1+), so you do not need to call `Ditto.init()` first.
- Call `await Ditto.init()` yourself only when you need the SDK before opening an instance:
  - before `Ditto.openSync(config)` (the synchronous variant cannot initialize the SDK itself),
  - before using `DittoLogger` or `Ditto.defaultRootDirectory` (they throw `DittoError` with "Ditto not initialized" otherwise),
  - on the Web, to load the WebAssembly assets from a custom URL.
- `Ditto.init()` can be called more than once; later calls do nothing.

```dart
// ✅ GOOD: Explicit init is required before openSync().
Future<Ditto> openWithoutAwaitingOpen() async {
  await Ditto.init();
  // connect is omitted for brevity. The default, DittoConfigConnectSmallPeersOnly()
  // without a key, does not authenticate peers; see DittoConfig in Flutter.
  return Ditto.openSync(const DittoConfig(databaseID: 'YOUR_DATABASE_ID'));
}
```

`Ditto` and `Store` cannot be sent to another isolate. Use the instance from the isolate that opened it. On native platforms, `store.execute()` already runs queries on a background isolate managed by the SDK, so you do not need your own isolate for that (see [Executing DQL in Flutter](#executing-dql-in-flutter)).

### DittoConfig in Flutter

`DittoConfig` is immutable. Its fields, as described in [DittoConfig](../setup-and-lifecycle.md#dittoconfig):

| Field | Type | Default | Flutter specifics |
|---|---|---|---|
| `databaseID` | `String?` | All-zero UUID | |
| `connect` | `DittoConfigConnect` | `DittoConfigConnectSmallPeersOnly()` | `DittoConfigConnectServer(url: ...)` or `DittoConfigConnectSmallPeersOnly(privateKey: ...)` |
| `persistenceDirectory` | `String?` | `null` | `null` uses `ditto-<databaseID>` inside `Ditto.defaultRootDirectory`. A relative path is resolved against the application support directory (`getApplicationSupportDirectory()`). |
| `systemParameters` (SDK 5.2+) | `Map<String, Object>` | `{}` | An unknown name or a wrong type makes `Ditto.open()` fail with a `DittoException`, and a value that Dart cannot represent, such as a `DateTime`, with an `ArgumentError` (in our testing; see [System parameters passed in DittoConfig take effect when Ditto.open returns](../../knowledge/observations/configuration-and-diagnostics.md#system-parameters-passed-in-dittoconfig-take-effect-when-dittoopen-returns)) |

The Flutter SDK has no encryption at rest (see [Data at Rest](../security.md#data-at-rest)).

**Default location (SDK 5.2+)**: `Ditto.defaultRootDirectory` now resolves to the application support directory instead of the documents directory; the release notes describe the move for desktop platforms. With `persistenceDirectory: null`, Ditto still finds a database in the previous default location after the upgrade. That fallback applies only to `null`. If your app passes a relative path, check on every platform you ship that an upgraded installation still opens its existing data before you release 5.2.

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

Pass system parameters on every open (see [Applying System Parameters](../setup-and-lifecycle.md#applying-system-parameters)):

```dart
// ✅ GOOD: Pass settings on every open. Ditto applies them before it starts,
// and a misspelled name or a wrong type makes Ditto.open() fail.
Future<Ditto> openWithSystemParameters({
  required bool strictMode, // true only for apps that opt into strict mode
}) async {
  final ditto = await Ditto.open(
    DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: const DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
      systemParameters: {
        if (strictMode) 'DQL_STRICT_MODE': true,
      },
    ),
  );

  // Confirm the effective value. SHOW returns one row keyed by the
  // lowercase parameter name.
  final result = await ditto.store.execute('SHOW DQL_STRICT_MODE');
  debugPrint('dql_strict_mode = ${result.items.first.value['dql_strict_mode']}');
  return ditto;
}
```

Pass sync scopes the same way, so that they are in effect before sync starts (see [Sync Scopes](../sync-and-subscriptions.md#sync-scopes)):

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

```dart
// ❌ BAD: No privateKey means peers are not authenticated (and the SDK
// documents the mode as unencrypted); a key in source code would be visible
// to anyone who decompiles the app.
Future<Ditto> openUnprotectedSmallPeer() {
  return Ditto.open(
    const DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectSmallPeersOnly(),
    ),
  );
}
```

When a store cannot be opened for an encryption reason, Flutter reports a `DittoEncryptionException` whose `reason` is `keyRequired`, `keyUnexpected`, `keyInvalid`, `unsupportedScheme`, or `metadataCorrupt`. `DittoConfigExperimental.passphrase` remains only for compatibility: `Ditto.open()` rejects any value other than `null`.

### One shared instance in Flutter

Let concurrent callers await the same `Future`, and forget a failed attempt so that the next caller can retry (see [One instance per persistence directory](../setup-and-lifecycle.md#one-instance-per-persistence-directory)).

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

```dart
// ❌ BAD: Every call opens the same directory again. While the first instance
// is still open, the second open fails (SDK 5.2.0) or never completes (5.1.0).
Future<List<Map<String, dynamic>>> loadOrders() async {
  final ditto = await Ditto.open(const DittoConfig(databaseID: 'YOUR_DATABASE_ID'));
  final result = await ditto.store.execute('SELECT * FROM orders');
  return result.items.map((item) => item.value).toList();
}
```

> **Note (SDK 5.1.0):** Calling `Ditto.open()` on a persistence directory that is already open may never complete instead of throwing. In our testing it did not complete within 20 seconds on 5.1.0, while on 5.2.0 it failed after about a second with a `DittoException` (`File already locked, ... Multiple Ditto instances cannot run at the same time within the same working directory. ...`), and `Ditto.openSync()` failed in the same way on both releases (see [In Flutter, opening an open directory again fails within a second on SDK 5.2.0 and never completes on 5.1.0](../../knowledge/observations/flutter-sdk.md#in-flutter-opening-an-open-directory-again-fails-within-a-second-on-sdk-520-and-never-completes-on-510)). Instead of opening the directory again, share the existing instance.

**Hot restart**: in debug builds, use a randomized `persistenceDirectory` to avoid lock conflicts after a Flutter hot restart, as described in the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter). Each hot restart then starts with an empty local store. Keep a fixed directory in release builds. Hot reload works normally.

### App startup in Flutter

The recommended order (see [Complete app startup](../setup-and-lifecycle.md#complete-app-startup)), as one service that owns the instance and its long-lived subscriptions:

```dart
// ✅ GOOD: Complete startup sequence for a Ditto Server connection.
import 'package:flutter/foundation.dart';

// Most apps keep the default (strict mode off). See "Strict Mode".
const bool enableStrictMode = false;

// fetchAuthToken() and showError() stand for your app's own code.

class DittoService {
  DittoService._(this.ditto, this._subscriptions);

  final Ditto ditto;
  final List<SyncSubscription> _subscriptions;

  static Future<DittoService> start() async {
    // 1. Initialize explicitly because DittoLogger is configured before open.
    await Ditto.init();

    // 2. Configure logging after init and before open, so that startup is
    //    logged with your settings.
    DittoLogger.minimumLogLevel =
        kReleaseMode ? LogLevel.warning : LogLevel.debug;

    // 3. Open the single shared instance. System parameters are not
    //    persisted, so pass them on every open; Ditto applies them before
    //    it starts (SDK 5.2+).
    final ditto = await Ditto.open(
      DittoConfig(
        databaseID: 'YOUR_DATABASE_ID',
        // Copy the URL from the Ditto Portal exactly as shown.
        connect: const DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
        systemParameters: {
          if (enableStrictMode) 'DQL_STRICT_MODE': true,
        },
      ),
    );

    // If a later step fails, close the instance before rethrowing: opening
    // the same directory again while it is still open fails (SDK 5.2.0) or
    // never completes (SDK 5.1.0).
    try {
      // 4. Server connections require an expiration handler before sync.start().
      await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
        try {
          final response = await ditto.auth.login(
            token: await fetchAuthToken(),
            provider: 'YOUR_PROVIDER_NAME',
          );
          final exception = response.exception;
          if (exception != null) {
            showError(exception); // login() reports rejection; it does not throw
          }
        } catch (error) {
          showError(error); // for example, fetchAuthToken() failed; never rethrow here
        }
      });

      // 5. Create the indexes your queries need before queries and observers
      //    run. Indexes persist, and IF NOT EXISTS makes this safe on every
      //    start. The in-browser store on the Web does not support indexes.
      if (!kIsWeb) {
        await ditto.store.execute(
          'CREATE INDEX IF NOT EXISTS idx_orders_storeId ON orders (storeId)',
        );
      }

      // 6. Register long-lived subscriptions, then start sync.
      final subscriptions = [
        ditto.sync.registerSubscription(
          'SELECT * FROM orders WHERE storeId = :storeId',
          arguments: {'storeId': 'store-1'},
        ),
      ];
      ditto.sync.start(); // returns void; do not await

      return DittoService._(ditto, subscriptions);
    } catch (_) {
      await ditto.close();
      rethrow;
    }
  }

  // Call only when the whole app no longer needs Ditto.
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    await ditto.close();
  }
}
```

Create the indexes your queries rely on once per launch, and skip them on Flutter Web, whose in-memory store does not support indexes (see [Where indexes live](../indexing-and-performance.md#where-indexes-live)):

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

## Authentication in Flutter

Register the handler with `await ditto.auth.setExpirationHandler(...)`. Its `timeUntilExpiration` is a `Duration`; `Duration.zero` means "not authenticated yet" or "already expired". `ditto.auth.login(token: ..., provider: ...)` returns an `AuthResponse`. **It does not throw when your authentication webhook rejects the token or the server is unreachable**: check `response.exception` (non-null on failure). It can still throw for other reasons, such as `DittoClosedException` after `ditto.close()`. `response.clientInfo` contains the optional `clientInfo` JSON returned by your webhook. The handler's return type is `void`, so an exception thrown from it becomes an unhandled asynchronous error. The rules are in [Authentication](../setup-and-lifecycle.md#authentication).

```dart
// ✅ GOOD: Production login with error reporting and no throwing.
// fetchAuthToken() and showError() stand for your app's own code.
Future<void> configureAuthentication(Ditto ditto) async {
  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    if (timeUntilExpiration > Duration.zero) {
      debugPrint('Ditto credentials expire in $timeUntilExpiration; refreshing');
    }
    try {
      final response = await ditto.auth.login(
        token: await fetchAuthToken(), // from your identity provider/backend
        provider: 'YOUR_PROVIDER_NAME', // as configured in the Ditto Portal
      );
      if (response.exception != null) {
        showError(response.exception!);
      }
    } catch (error) {
      showError(error);
    }
  });
}
```

```dart
// ✅ GOOD (development only): The development provider and Portal token.
Future<void> configureDevelopmentAuthentication(
  Ditto ditto,
  String developmentToken,
) async {
  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    final response = await ditto.auth.login(
      token: developmentToken,
      provider: Authenticator.developmentProvider,
    );
    if (response.exception != null) {
      showError(response.exception!);
    }
  });
}
```

```dart
// ❌ BAD: Throwing inside the handler produces an unhandled async error,
// and nothing in Ditto can catch it.
Future<void> configureAuthenticationBadly(Ditto ditto) async {
  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    final response = await ditto.auth.login(
      token: await fetchAuthToken(),
      provider: 'YOUR_PROVIDER_NAME',
    );
    if (response.exception != null) {
      throw response.exception!;
    }
  });
}
```

**Logging out**: `await ditto.auth.logout()` clears the credentials and stops sync; `ditto.auth.status` exposes `isAuthenticated` and `userID`. To remove local data as part of logging out, pass a `cleanup` callback (SDK 5.2+): `await ditto.auth.logout(cleanup: (ditto) async { ... })`.

### Switching users in Flutter

The order of the steps is in [Switching users on a shared device](../setup-and-lifecycle.md#switching-users-on-a-shared-device).

```dart
// ✅ GOOD: Sign a user out of a shared device. waitUntilServerHas() is defined
// in "Closing Ditto in Flutter"; OrderSync owns the subscriptions (see
// "Subscriptions in Flutter").
Future<bool> signOut(
  Ditto ditto,
  OrderSync orderSync, {
  required String storeId,
  int? lastCommitId,
}) async {
  if (lastCommitId != null && !await waitUntilServerHas(ditto, lastCommitId)) {
    // Evicting now could discard changes that no other device has yet.
    showError('Some changes have not been uploaded yet. Try again online.');
    return false;
  }
  // Screens dispose their own observers when the user leaves them.
  orderSync.leaveStore(); // cancel first, or evicted documents sync back
  await ditto.auth.logout(cleanup: (ditto) async {
    // Runs after sync has stopped; EVICT is still allowed after logout.
    await ditto.store.execute(
      'EVICT FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
    await ditto.store.execute(
      'EVICT FROM orderItems WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
  });
  final left = await ditto.store.execute(
    'SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
  return left.items.first.value['n'] == 0;
}
```

## Sync and the App Lifecycle in Flutter

`ditto.sync.start()` and `ditto.sync.stop()` return `void`. Do not `await` them (`await ditto.sync.start()` is a compile error in Dart). `start()` throws if sync cannot start. <!-- lint-ignore --> The rules are in [Starting and Stopping Sync](../setup-and-lifecycle.md#starting-and-stopping-sync).

```dart
// ✅ GOOD: Start sync only when it is not already running.
void ensureSyncStarted(Ditto ditto) {
  if (!ditto.sync.isActive) {
    ditto.sync.start(); // throws if prerequisites are missing
  }
}
```

```dart
// ❌ BAD: For server connections, sync.start() throws because no expiration
// handler is set yet, so the handler below is never registered.
Future<void> startTooEarly(Ditto ditto) async {
  ditto.sync.start();
  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) {});
}
```

Do not call `ditto.close()` when the app moves to the background (`AppLifecycleState.paused`): every later call on the instance throws `DittoClosedException`. To keep syncing in the background on Android, declare Ditto's foreground service as shown in the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter).

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

## Closing Ditto in Flutter

| Object | How to release | Notes |
|---|---|---|
| `Ditto` | `await ditto.close()` | Releases everything below as well |
| `StoreObserver` | `observer.cancel()` | Cancelling a `StreamSubscription` on `changes` does not cancel the observer |
| `StoreObserverV2` (Experimental) (SDK 5.1+) | `observer.cancel()` | Cancelling the `StreamSubscription` on `changes`, or leaving an `await for` loop over it, also cancels the observer |
| `SyncSubscription` | `subscription.cancel()` | Required to stop syncing the data it matched |
| `PresenceObserver` | `observer.stop()` | |
| `TransportConditionsObserver` | `observer.stop()` | Also released by `close()` |
| `AttachmentFetcher` | `fetcher.stop()` | Only needed to cancel a fetch in progress |
| Connection request handler | `ditto.presence.connectionRequestHandler = null` | |

To find what is still registered, `ditto.store.observers` (SDK 5.2+) returns the `StoreObserver`s registered with `registerObserver` that have not been cancelled (observers from `registerObserverV2` and `registerObserverWithSignalNext` are not included), and `ditto.store.attachmentFetchers` returns the active fetchers.

`ditto.close()` in Flutter:
- **Idempotent**: calling it twice is safe. Use `ditto.isClosed` to check.
- **After closing**, observers and subscriptions report `isCancelled == true`, `cancel()` and `stop()` do nothing, and every other API call throws `DittoClosedException`: `execute` and `transaction` return a `Future` that fails with it, and the other calls throw it synchronously (see [In Flutter, calls after close() throw DittoClosedException](../../knowledge/observations/flutter-sdk.md#in-flutter-calls-after-close-throw-dittoclosedexception)).
- **Does not wait** for your pending work. Await your own writes and transactions before closing, as `TransactionTracker` in [Transactions in Flutter](#transactions-in-flutter) does for transactions.
- **Resets `DittoLogger.customLogCallback`** to `null` for the whole process. If you reopen Ditto, set it again after `Ditto.init()` and before `Ditto.open()` (see [Logging in Flutter](#logging-in-flutter)).
- **Does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`**: an `await for` loop over it does not end when Ditto closes, and `cancel()` does nothing once Ditto is closed. Cancel observers and your `StreamSubscription`s (or break out of the loop) before closing.

> **Note (SDK 5.1.0 and 5.2.0):** Do not call `close()` while a transaction is open. In our testing, `close()` during a transaction that awaited a one-second delay stopped the isolate: neither the transaction nor a one-second timer ever ran again, on macOS and on iOS, and also with a read-only transaction. In an app, this is the UI isolate, so the app stops responding (see [In Flutter, close() while a transaction is open stops the app's isolate](../../knowledge/observations/flutter-sdk.md#in-flutter-close-while-a-transaction-is-open-stops-the-apps-isolate)).

> **Note (SDK 5.1.0 and 5.2.0):** A write that is still pending when `close()` is called can be stored although its `Future` fails. In our testing, 200 writes that were not awaited all failed with `StateError: Bad state: Ditto closed before execute() completed`, and all 200 were in the store when it was opened again; writes started after `close()` was called failed with `DittoClosedException` and were not stored (see [In Flutter, close() fails pending execute calls, also writes that it stores](../../knowledge/observations/flutter-sdk.md#in-flutter-close-fails-pending-execute-calls-also-writes-that-it-stores)). Await every write before closing, and do not retry a write that failed this way without first checking whether it was stored.

Before you close Ditto at a point where data must reach another device, wait with a timeout until Ditto Server has confirmed the last write (see [Resource Cleanup and Shutdown](../setup-and-lifecycle.md#resource-cleanup-and-shutdown)):

```dart
// ✅ GOOD: Wait (with a timeout) until Ditto Server has confirmed a write.
Future<bool> waitUntilServerHas(
  Ditto ditto,
  int commitId, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final result = await ditto.store.execute(
      'SELECT * FROM system:data_sync_info WHERE is_ditto_server = true',
    );
    final confirmed = result.items.any((item) {
      final documents = item.value['documents'];
      if (documents is! Map) return false;
      final synced = documents['synced_up_to_local_commit_id'];
      return synced is int && synced >= commitId;
    });
    if (confirmed) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false; // The change stays on the device and syncs later.
}

/// [lastCommitId] is the commitID of the last write that must be uploaded.
Future<void> endShift(Ditto ditto, int? lastCommitId) async {
  if (lastCommitId != null && !await waitUntilServerHas(ditto, lastCommitId)) {
    showError('Some changes have not been uploaded yet.');
  }
  await ditto.close();
}
```

```dart
// ✅ GOOD: Release resources in reverse order of creation, then close.
import 'dart:async';

// This is app-level shutdown: call shutdown() only when the whole app no
// longer needs Ditto. Screens release their own observers and keep Ditto open.
class AppShutdown {
  AppShutdown(this.ditto);

  final Ditto ditto;
  SyncSubscription? _subscription;
  StoreObserver? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
    final observer = ditto.store.registerObserver(
      'SELECT * FROM orders ORDER BY createdAt DESC',
    );
    _observer = observer;
    _changes = observer.changes.listen((result) {
      debugPrint('orders: ${result.items.length}');
    });
  }

  Future<void> shutdown() async {
    await _changes?.cancel(); // close() does not end the changes stream
    _observer?.cancel();
    _subscription?.cancel();
    await ditto.close(); // stops sync; waits neither for in-flight queries nor for unsent changes
  }
}
```

## Executing DQL in Flutter

Pass each statement with its arguments as a `Map<String, dynamic>` in `arguments:`. The four entry points take the same shape:

| Call | Returns |
|---|---|
| `await ditto.store.execute(query, arguments: {...})` | `QueryResult` |
| `await tx.execute(query, arguments: {...})` inside `ditto.store.transaction` | `QueryResult` (see [Transactions in Flutter](#transactions-in-flutter)) |
| `ditto.store.registerObserver(query, arguments: {...})` | `StoreObserver` (see [Store Observers in Flutter](#store-observers-in-flutter)) |
| `ditto.sync.registerSubscription(query, arguments: {...})` | `SyncSubscription` (see [Subscriptions in Flutter](#subscriptions-in-flutter)) |

A statement that Ditto rejects makes `execute` and `tx.execute` return a `Future` that fails with a `DittoException`, and makes `registerObserver`, `registerObserverV2`, `registerObserverWithSignalNext`, and `registerSubscription` throw it synchronously; its message names the cause, such as `Parameter color was not provided` for a missing argument (see [When a Statement Fails or Returns Nothing](../dql.md#when-a-statement-fails-or-returns-nothing) and [In Flutter, invalid DQL fails the Future of execute and throws when an observer or subscription is registered](../../knowledge/observations/flutter-sdk.md#in-flutter-invalid-dql-fails-the-future-of-execute-and-throws-when-an-observer-or-subscription-is-registered)). The rules for parameters are in [Always pass values as parameters](../dql.md#always-pass-values-as-parameters).

```dart
// ✅ GOOD: Values travel as typed parameters
Future<List<Map<String, dynamic>>> findOrders(
  Ditto ditto,
  String customerId,
  List<String> statuses,
  int pageSize,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE customerId = :customerId AND status IN :statuses '
    'ORDER BY createdAt DESC LIMIT :pageSize',
    arguments: {
      'customerId': customerId,
      'statuses': statuses,
      'pageSize': pageSize,
    },
  );
  return result.items.map((item) => item.value).toList();
}
```

```dart
// ❌ BAD: Interpolated values (injection risk, broken quoting, no statement reuse)
Future<void> findOrdersUnsafe(Ditto ditto, String customerId) async {
  await ditto.store.execute(
    "SELECT * FROM orders WHERE customerId = '$customerId'",
  );
}
```

Validate values before you write them, then pass them as parameters (see [Input Validation and Query Parameters](../security.md#input-validation-and-query-parameters)):

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

**A map key in a path**: a path cannot be passed as a parameter, so validate a map key against a strict pattern before you place it inside a backtick-quoted path segment, and pass every value as a parameter (see [Adding, updating, and removing map entries](../data-modeling.md#adding-updating-and-removing-map-entries)).

```dart
// Map keys used in paths are validated: only UUID-shaped keys are accepted.
final _uuidKey = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Removes one line item. A path cannot be passed as a parameter, so the key
/// is validated before it is placed inside a backtick-quoted path segment.
Future<void> removeOrderItem(
  Ditto ditto, {
  required String orderId,
  required String itemId,
}) async {
  if (!_uuidKey.hasMatch(itemId)) {
    throw ArgumentError.value(itemId, 'itemId', 'must be a lowercase UUID');
  }
  await ditto.store.execute(
    'UPDATE orders UNSET items.`$itemId` WHERE _id = :id',
    arguments: {'id': orderId},
  );
}
```

**Handling the size error**: a write that would take a document over the hard size limit throws a `DittoException` whose message contains `exceeds limit of ... bytes`; handle it at the call site that may produce it (see [Document Size Limits](../data-modeling.md#document-size-limits)).

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
    showError(error); // your app's error UI
    return false;
  }
}
```

**Batched eviction**: `EVICT ... LIMIT ... RETURNING COUNT(*)` in a loop until the count is 0 (see [Batching evictions](../deletion-and-storage.md#batching-evictions)). First cancel or narrow every subscription that matches these documents.

```dart
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First cancel or narrow every subscription that matches these documents (see EVICT).
Future<int> evictInBatches(Ditto ditto, String cutoff) async {
  var total = 0;
  while (true) {
    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 '
      'RETURNING COUNT(*) AS evicted',
      arguments: {'cutoff': cutoff},
    );
    final evicted = result.items.first.value['evicted'] as int;
    total += evicted;
    if (evicted == 0) return total;
  }
}
```

**Development helpers for `ADVISE` and `PROFILE`**: `ADVISE` returns one row whose `advice` map holds `suggestedIndexes` (or an `outcome` when there is nothing to suggest), and `PROFILE` appends a row with the key `~request_profile` after the normal results (see [ADVISE (SDK 5.1+)](../indexing-and-performance.md#advise-sdk-51) and [Measuring with PROFILE](../indexing-and-performance.md#measuring-with-profile)). Use these helpers during development only.

```dart
// ✅ GOOD (development only): print index suggestions for a query.
Future<void> printIndexAdvice(
  Ditto ditto,
  String query,
  Map<String, dynamic> arguments,
) async {
  final result = await ditto.store.execute('ADVISE $query', arguments: arguments);
  final advice = result.items.first.value['advice'] as Map<String, dynamic>;
  final suggested = (advice['suggestedIndexes'] as List<dynamic>?) ?? const [];
  if (suggested.isEmpty) {
    debugPrint('No suggestions: ${advice['outcome']}');
  }
  for (final index in suggested) {
    final entry = index as Map<String, dynamic>;
    debugPrint('${entry['reason']}\n  ${entry['statement']}');
  }
}
```

```dart
import 'dart:convert';

// ✅ GOOD (development only): separate the profile row from the results.
Future<void> profileQuery(
  Ditto ditto,
  String query,
  Map<String, dynamic> arguments,
) async {
  final result = await ditto.store.execute('PROFILE $query', arguments: arguments);
  final rows = result.items.map((item) => item.value).toList();
  final profile = rows.lastWhere(
    (row) => row.containsKey('~request_profile'),
    orElse: () => const {},
  )['~request_profile'] as Map<String, dynamic>?;
  final resultCount = rows.length - (profile == null ? 0 : 1);
  debugPrint('rows=$resultCount times=${profile?['times']}');
  debugPrint(const JsonEncoder.withIndent('  ').convert(profile?['plan']));
}
```

**Execution model**: on native platforms, `ditto.store.execute` runs the query on a long-lived worker isolate (one per `Ditto` instance), so a slow query does not block the UI isolate (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution)).

> **Advanced:** `Store.experimentalSkipExecuteIsolateOffload` (Experimental, default `false`) runs `execute` inline on the calling isolate instead. It avoids the per-call dispatch cost for tight loops of very small queries, but any slow query then blocks the calling isolate (usually the UI). The setting applies to every `Store` in the current isolate, persists across `Ditto.open` and `close` for the lifetime of the isolate, does not propagate to isolates you spawn, and has no effect on Web. Avoid toggling it while `execute` calls are in flight. Use it only after measuring a real throughput problem.

```dart
// Advanced (Experimental): only when queries are known to be short and
// throughput of many small queries matters more than UI responsiveness.
void enableInlineExecute() {
  Store.experimentalSkipExecuteIsolateOffload = true;
}
```

**One query instead of a loop**: each `execute` call has a fixed cost, so read a list of documents with one `_id IN :ids` query (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution)).

```dart
// ❌ BAD: one query per ID
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

// ✅ GOOD: one query, planned as an ID scan
Future<List<Map<String, dynamic>>> loadOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

### Arguments and value types in Flutter

Pass Dart values that map to JSON: `String`, `int`, `double`, `bool`, `null`, `List`, and `Map<String, dynamic>`. Text that contains backslashes is safest in a raw string (`r'...'`) passed as an argument, because a statement written inside a Dart string is unescaped twice, first by Dart and then by DQL (see [Literals](../dql.md#literals)).

```dart
// ✅ GOOD: The path is passed as data and stored exactly as given
Future<void> saveExportPath(Ditto ditto) async {
  await ditto.store.execute(
    'UPDATE settings SET exportPath = :path WHERE _id = :id',
    arguments: {'id': 'device', 'path': r'C:\temp\exports'},
  );
}
```

The SDK encodes arguments as CBOR and decodes `item.value` from JSON, so other Dart values are converted on the way in, and some come back as a different type. In our testing on SDK 5.1.0 and 5.2.0 (see [In Flutter, Dart values change type between writing and reading](../../knowledge/observations/flutter-sdk.md#in-flutter-dart-values-change-type-between-writing-and-reading)):

| Dart value | Stored as | Read back from `item.value` |
|---|---|---|
| `DateTime` | A string: `2026-11-06T10:30:45.123456Z` for a UTC time, and with its offset, such as `+09:00`, for a local time | A `String` |
| `Uint8List` | Binary | A `List<dynamic>` of numbers, not a `Uint8List` |
| `Set` | An array | A `List<dynamic>` |
| `Uri` | A string | A `String` |
| `int` (64 bits) | An integer | The same `int` |
| `BigInt` from 2^63 to 2^64 − 1 | An integer | A `double`: the last digits are lost |
| `BigInt` of 2^64 or more | Binary | A `List<dynamic>` of bytes |
| `double.nan`, `double.infinity` | Nothing: `DittoException(<dql> Invalid query arguments: Non finite float value)` | |
| A `Map` whose keys are not strings | Nothing: `DittoException(<dql> Invalid query arguments: ...)` | |
| An object of your own class, or a `Duration` | Nothing: `NoSuchMethodError` (`... has no instance method 'toCbor'`), unless the class has a `toCbor()` method, whose result is stored | |
| A `String` with an unpaired surrogate | A string with U+FFFD in place of the surrogate, without an error | A `String` |

Convert such values yourself before you pass them, so that the stored value is the one you expect and reads the same on every SDK: timestamps with the fixed-precision UTC helper from [IDs and Timestamps in Flutter](#ids-and-timestamps-in-flutter), large or exact numbers as strings or as integer minor units, and model objects with a `toMap()` method of your own. Read a binary field back with `Uint8List.fromList`, and keep files in attachments (see [Attachments in Flutter](#attachments-in-flutter)). How Ditto types the values it stores is described in [How Values Are Typed with the Default Settings](../../knowledge/crdt-types.md#how-values-are-typed-with-the-default-settings).

```dart
import 'dart:typed_data';

// ✅ GOOD: Convert values whose type would change before you pass them.
Future<void> saveReading(
  Ditto ditto, {
  required String readingId,
  required DateTime takenAt,
  required BigInt serialNumber,
  required Uint8List signature,
}) async {
  await ditto.store.execute(
    'INSERT INTO readings DOCUMENTS (:reading)',
    arguments: {
      'reading': {
        '_id': readingId,
        'takenAt': utcTimestamp(takenAt), // not the DateTime itself
        'serialNumber': serialNumber.toString(), // a large BigInt comes back as a double
        'signature': signature, // stored as binary, read back as a List
      },
    },
  );
}

// A binary field comes back from item.value as a List, not as a Uint8List.
Uint8List signatureOf(Map<String, dynamic> reading) =>
    Uint8List.fromList((reading['signature'] as List).cast<int>());
```

### Query results in Flutter

`ditto.store.execute` returns a `QueryResult` (see [Working with Query Results](../dql.md#working-with-query-results)):

| Member | Type | Description |
|---|---|---|
| `items` | `Iterable<QueryResultItem>` | The result rows. An `Iterable`, not a `List`: use `map`, `first`, `length`, or `toList()`. |
| `item.value` | `Map<String, dynamic>` | The row decoded into Dart values. Decoded on first access and cached on that item object. |
| `item.jsonString` | `String` | The row as a JSON string (a property, not a method). |
| `item.cborBytes` | `Uint8List` | The row as CBOR bytes (a property, not a method). |
| `mutatedDocumentIDs()` | `List<dynamic>` | IDs of documents changed by a write. A method that builds a new list on every call; call it once and keep the list. |
| `commitID` | `int?` | ID of the local commit for a mutating statement; `null` for reads. |

Each pass over `items` creates new `QueryResultItem` wrappers, so `result.items.first.value` evaluated twice decodes the row twice and returns two different maps. Iterate `items` once. The map that `value` returns can be modified, but in our testing on SDK 5.1.0 and 5.2.0 a change stayed in that one item, never reached the store, and was not visible through a new item of the same result; results could still be read after `ditto.close()` (see [In Flutter, each read of result.items creates new items, and results stay readable after close](../../knowledge/observations/flutter-sdk.md#in-flutter-each-read-of-resultitems-creates-new-items-and-results-stay-readable-after-close)). `QueryResult` and `QueryResultItem` reference native memory that is released only when the Dart object is garbage-collected, so do not keep them in state, caches, or across observer callbacks.

```dart
// Read: convert rows to plain Dart data right away
Future<List<Map<String, dynamic>>> openOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, total, status FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}

// Write: inspect which documents changed
Future<List<dynamic>> closeOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id IN :ids',
    arguments: {'status': 'closed', 'ids': ids},
  );
  final int? commitId = result.commitID; // null for reads
  debugPrint('Committed as $commitId');
  return result.mutatedDocumentIDs(); // call once and keep the list
}

// Alternative encodings, for example to hand rows to a JSON decoder or another isolate
Future<List<String>> openOrdersAsJson(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.jsonString).toList();
}
```

```dart
class Order {
  Order({required this.id, required this.status, required this.total});

  factory Order.fromValue(Map<String, dynamic> value) => Order(
        id: value['_id'] as String,
        status: value['status'] as String? ?? 'unknown',
        total: (value['total'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String status;
  final double total;
}

// ✅ GOOD: One pass, plain Dart objects out
Future<List<Order>> loadOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => Order.fromValue(item.value)).toList();
}
```

**Deriving values at read time**: compute totals and the current status from the stored source data when you read a document, and skip entries whose required fields are missing or `null` (see [Do not store derived values that can diverge](../data-modeling.md#do-not-store-derived-values-that-can-diverge) and [Pattern 1: Audit-log map inside the document](../data-modeling.md#pattern-1-audit-log-map-inside-the-document)).

```dart
// ✅ GOOD: Store the source data; derive totals at read time. Entries with a
// missing or null price or quantity (an entry removed on one device while
// another device edited it) are skipped instead of crashing the screen.
int orderSubtotalCents(Map<String, dynamic> order) {
  final items = (order['items'] as Map<String, dynamic>?) ?? const {};
  var subtotal = 0;
  for (final entry in items.values) {
    if (entry is! Map<String, dynamic>) continue;
    final price = entry['unitPriceCents'];
    final quantity = entry['quantity'];
    if (price is! int || quantity is! int) continue;
    subtotal += price * quantity;
  }
  return subtotal;
}
```

```dart
// The workflow states, from earliest to most advanced.
const _statusOrder = ['created', 'confirmed', 'shipped', 'delivered'];

/// Derives the current status as the most advanced state, so a late write from
/// a device that was offline cannot move the order backwards.
String? currentStatus(Map<String, dynamic> order) {
  final log = (order['statusLog'] as Map<String, dynamic>?) ?? const {};
  String? best;
  for (final status in log.values.whereType<String>()) {
    if (best == null ||
        _statusOrder.indexOf(status) > _statusOrder.indexOf(best)) {
      best = status;
    }
  }
  return best;
}
```

**Tolerating older documents**: a model class reads a field that newer app versions added with a default, because older documents do not have it (see [Prefer additive changes](../data-modeling.md#prefer-additive-changes)).

```dart
// ✅ GOOD: A new field, read with a default for older documents.
class Car {
  Car({required this.id, required this.make, this.mileageKm});

  final String id;
  final String make;
  final int? mileageKm; // added in app version 2; absent in older documents

  factory Car.fromDocument(Map<String, dynamic> doc) => Car(
        id: doc['_id'] as String,
        make: doc['make'] as String,
        mileageKm: doc['mileageKm'] as int?,
      );
}
```

## Subscriptions in Flutter

`ditto.sync.registerSubscription(query, arguments: {...})` returns a `SyncSubscription`; release it with `subscription.cancel()`, which is a no-op if it is already cancelled or Ditto was closed. Registering a query that subscriptions do not accept throws a `DittoException` (see [Subscription Rules](../sync-and-subscriptions.md#subscription-rules)). The rules for when to register and cancel are in [Subscription Lifecycle](../sync-and-subscriptions.md#subscription-lifecycle).

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

When the user changes a filter, replace the widget's observer, not the subscription (see [Filter locally instead of re-registering](../sync-and-subscriptions.md#filter-locally-instead-of-re-registering)):

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

To switch stores, cancel first, then evict, then subscribe (see [Cancelling subscriptions and local data](../sync-and-subscriptions.md#cancelling-subscriptions-and-local-data)):

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

`ditto.sync.subscriptions` returns the active subscriptions, as new objects that are equal (`==`) to the ones that `registerSubscription` returned. After `await ditto.close()`, every subscription reports `isCancelled == true`. A subscription registered without `arguments` reports `{}` as its `queryArguments`, because `registerSubscription` passes an empty map by default (see [In Flutter, the subscriptions and observers that registration returns report their arguments](../../knowledge/observations/flutter-sdk.md#in-flutter-the-subscriptions-and-observers-that-registration-returns-report-their-arguments)).

Keep a reference to every subscription you register, and cancel it through that reference. A subscription does not end when your code drops it: in our testing on SDK 5.1.0 and 5.2.0, a `SyncSubscription` object that the garbage collector had reclaimed still synced, and only its element of `ditto.sync.subscriptions` could still cancel it (see [In Flutter, observers and subscriptions whose references were dropped keep running](../../knowledge/observations/flutter-sdk.md#in-flutter-observers-and-subscriptions-whose-references-were-dropped-keep-running)).

> **Note (SDK 5.2.0):** A `SyncSubscription` object, or a `Transaction` object that `store.transaction` creates, that is garbage-collected after its instance was closed can stop the next `Ditto.open()` or `close()` in the same process, without an error. In our testing, a process that opened and closed one store per test, each using a subscription or a transaction, stopped in the second or third test in every run on 5.2.0, but not on 5.1.0, and not when the objects were kept in a list or when every store was closed only at the end (see [In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](../../knowledge/observations/flutter-sdk.md#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close)). Avoid closing and reopening Ditto in one process on 5.2.0. When you must, as when a user signs out and in, keep the `SyncSubscription` objects reachable, for example in a service that lives as long as the app, also after `close()`; for test suites, see [A local-store test helper in Flutter](#a-local-store-test-helper-in-flutter).

> **Note (SDK 5.1.0 and 5.2.0):** Do not read `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes` from the elements of `ditto.sync.subscriptions`. For a subscription registered without arguments, reading any of them ended the app with a segmentation fault in our testing, on macOS and on iOS (see [In Flutter, reading the arguments of a listed subscription without arguments ends the app](../../knowledge/observations/flutter-sdk.md#in-flutter-reading-the-arguments-of-a-listed-subscription-without-arguments-ends-the-app)). Read only `queryString` and `isCancelled` there, and keep your own references (as `OrderSync` does) when you need the arguments; the object that `registerSubscription` returned reports them safely.

**Upload status**: one lightweight observer of `system:data_sync_info` per screen, which rebuilds only when the derived state changes, and the writes whose `commitID` it tracks (see [Monitoring Sync Status](../sync-and-subscriptions.md#monitoring-sync-status)). In our testing on SDK 5.1.0 and 5.2.0, reads of `system:data_sync_info` on a Flutter device connected to a peer in another process always completed, unlike the JavaScript SDK (see [In Flutter, reads of system:data_sync_info kept responding with a peer in another process](../../knowledge/observations/flutter-sdk.md#in-flutter-reads-of-systemdata_sync_info-kept-responding-with-a-peer-in-another-process)):

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

**Subscriptions for a JOIN**: a feature-level service creates the index of the join key and subscribes to every collection that the join reads (see [Separate collections with JOIN (SDK 5.1+)](../data-modeling.md#separate-collections-with-join-sdk-51)).

```dart
/// Keeps the three collections needed by the order screens in sync.
/// Subscriptions belong to an app- or feature-level service, not to a screen.
class StoreSync {
  StoreSync(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;
  final List<SyncSubscription> _subscriptions = [];

  Future<void> start() async {
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)',
    );
    _subscriptions.addAll([
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      ),
      ditto.sync.registerSubscription('SELECT * FROM products'),
    ]);
  }

  void stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

If the key of a joined observer (such as the `orderId`) can change while the widget is mounted, re-register the observer in `didUpdateWidget`.

**Retention windows**: a long-lived service that keeps only recent documents moves the boundary of its subscription and evicts the complement in three steps: cancel the subscription, evict with the new cutoff, and subscribe again with the same cutoff, even if the eviction failed (see [Time-based eviction](../deletion-and-storage.md#time-based-eviction)). `utcTimestamp()` is defined in [IDs and Timestamps in Flutter](#ids-and-timestamps-in-flutter).

```dart
// ✅ GOOD: Keep the last 7 days of orders on this device.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  static const retention = Duration(days: 7);
  SyncSubscription? _subscription;

  // Same fixed-precision format as createdAt (utcTimestamp() from "IDs and Timestamps in Flutter").
  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, for example once a day.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    try {
      // 2. Evict exactly the complement of the new subscription.
      final result = await ditto.store.execute(
        'EVICT FROM orders WHERE createdAt < :cutoff',
        arguments: {'cutoff': cutoff},
      );
      return result.mutatedDocumentIDs().length;
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

The same steps keep active orders and orders soft-deleted within a retention window, and evict older soft-deleted orders (Variant B in [Soft delete, subscriptions, and cleanup](../deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)):

```dart
// ✅ GOOD (Variant B): A long-lived service keeps active orders and orders
// deleted within the retention window, and evicts older deleted orders.
class OrderSoftDeleteRetention {
  OrderSoftDeleteRetention(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;

  /// Longer than the longest time a device is expected to stay offline.
  static const retention = Duration(days: 30);
  SyncSubscription? _subscription;

  // Same fixed-precision format as deletedAt (utcTimestamp() from "IDs and Timestamps in Flutter").
  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribe(_cutoff());
  }

  /// Call on a schedule, at most about once a day.
  Future<void> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    try {
      // 2. Evict only documents outside the new subscription.
      await ditto.store.execute(
        'EVICT FROM orders '
        'WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );
    } finally {
      // 3. Subscribe again with the moved boundary, even if the eviction failed.
      _subscription = _subscribe(cutoff);
    }
  }

  SyncSubscription _subscribe(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId '
        'AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}
```

## Store Observers in Flutter

Use `registerObserver` **without** `onChange`, consume its `changes` stream with a single `StreamSubscription`, and cancel both in `dispose()`. The rules that every SDK shares are in [Observing Changes](../observers.md).

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
          return ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}'));
        },
      );
}
```

**✅ DO:**
- Register observers in `initState()` (or in a service), never in `build()`.
- Copy plain values out of the result (`item.value`, or your own model objects) before storing them in state; do not keep `QueryResult` or `QueryResultItem` objects around (see [Query results in Flutter](#query-results-in-flutter)).
- Add `ORDER BY` with a tie-breaker whenever the order of results matters (see [Stable ordering](../observers.md#stable-ordering)).
- Cancel the stream subscription **and** the observer in `dispose()`.

**❌ DON'T:**
- Pass `onChange` and leave the `changes` stream unconsumed (see the note below).
- Listen to `changes` twice; it is a single-subscription stream.
- Create an observer per list item; observe the list once and pass values down.

> **Note (SDK 5.1.0 and 5.2.0):** When an observer is registered with `onChange`, every result is **also** queued in its `changes` stream. If nothing listens to `changes`, those queued results stay in memory for the lifetime of the observer, so memory use grows with every update. In our testing, 300 updates of a 200-document result left 301 results in the stream and grew the process by 100 to 129 MB, against 31 to 39 MB when the stream was consumed (see [In Flutter, an observer whose changes stream nobody consumes keeps every result in memory](../../knowledge/observations/flutter-sdk.md#in-flutter-an-observer-whose-changes-stream-nobody-consumes-keeps-every-result-in-memory)). The same applies to `registerObserverV2` and `registerObserverWithSignalNext`, which start observing as soon as they are registered, with or without `onChange`: listen to their `changes` stream right after registering them, never later. Use the pattern above (no `onChange`, consume `changes`). If you need `onChange`, also drain the stream, for example with `observer.changes.listen((_) {})`.

```dart
// ❌ BAD: onChange only; the unconsumed changes stream keeps every result in memory (SDK 5.1.0 and 5.2.0).
StoreObserver observeOrdersWithCallbackOnly(Ditto ditto, void Function(int) onCount) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    onChange: (result) => onCount(result.items.length),
  );
}

// ✅ GOOD: The same work driven by the changes stream. Register the observer
// without onChange, and cancel both the returned subscription and the observer.
StreamSubscription<QueryResult> observeOrderCount(
  StoreObserver observer,
  void Function(int) onCount,
) {
  return observer.changes.listen((result) => onCount(result.items.length));
}
```

### Observer lifecycle in Flutter

| Behavior (`registerObserver`) | Consequence |
|---|---|
| Without `onChange`, the observer starts querying only when `changes` is first listened to | An observer that is registered but never listened to produces no events and does no query work, but still holds resources until cancelled |
| With `onChange`, the observer starts immediately | Results are delivered to `onChange` and also buffered in `changes` until something listens (see the note in [Store Observers in Flutter](#store-observers-in-flutter)); listen right after registering |
| `changes` is a single-subscription stream | A second `listen()` throws a `StateError` (`Bad state: Stream has already been listened to.`), including after the first subscription was cancelled |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` as well |
| `observer.cancel()` closes the `changes` stream | A pending `await for` loop over `changes` ends |
| `await ditto.close()` marks observers as cancelled (`isCancelled == true`) but does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2` | Do not rely on `close()` to end an `await for` loop over observer results; cancel observers explicitly before closing |

In our testing on SDK 5.1.0 and 5.2.0, every row of this table held (see [In Flutter, the observer lifecycle rules held on SDK 5.1.0 and 5.2.0](../../knowledge/observations/flutter-sdk.md#in-flutter-the-observer-lifecycle-rules-held-on-sdk-510-and-520)). Two more details:

- **An observer whose references you drop keeps running.** The SDK keeps observers and their callbacks reachable, so garbage collection never cancels them: in our testing, observers registered without keeping a reference were still called after the VM had collected garbage (see [In Flutter, observers and subscriptions whose references were dropped keep running](../../knowledge/observations/flutter-sdk.md#in-flutter-observers-and-subscriptions-whose-references-were-dropped-keep-running)). Keep a reference to every observer and cancel it.
- **An exception in a callback** goes to the error handler of the zone in which you registered the observer or listened to `changes`, and the observer keeps running. Two cases differ: when `onChange` throws, that result never reaches `changes`, and when a `registerObserverWithSignalNext` callback throws before it calls `signalNext()`, no further result arrives (see [In Flutter, an exception thrown in an observer callback reaches the zone, and the observer keeps running](../../knowledge/observations/flutter-sdk.md#in-flutter-an-exception-thrown-in-an-observer-callback-reaches-the-zone-and-the-observer-keeps-running)). Catch errors inside the callback.

Because `changes` is single-subscription, a `StreamBuilder` works well when the observer is created once in `initState` and its stream is handed to exactly one `StreamBuilder`:

```dart
// ✅ GOOD: StreamBuilder variant. The query starts when StreamBuilder listens.
class OpenOrdersStream extends StatefulWidget {
  const OpenOrdersStream({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OpenOrdersStream> createState() => _OpenOrdersStreamState();
}

class _OpenOrdersStreamState extends State<OpenOrdersStream> {
  late final StoreObserver _observer;

  @override
  void initState() {
    super.initState();
    // Create the observer once; never in build().
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      arguments: {'status': 'open'},
    );
  }

  @override
  void dispose() {
    _observer.cancel(); // StreamBuilder's unsubscribe does not cancel the observer.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryResult>(
      stream: _observer.changes,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = result.items.map((item) => item.value).toList();
        return ListView(
          children: [
            for (final order in orders)
              ListTile(key: ValueKey(order['_id']), title: Text('${order['_id']}')),
          ],
        );
      },
    );
  }
}
```

**Why:** If the `StreamBuilder` is removed from the tree and later rebuilt with the same `changes` stream, the second listen throws. Keep the `StreamBuilder` mounted for the observer's lifetime, or move the observer into the same widget whose lifetime matches the `StreamBuilder`.

With state management libraries (Riverpod, Bloc, Provider), let one provider or controller own each observer, cancel it in the provider's dispose hook, and remember that `changes` can only be listened to once.

### Backpressure in Flutter

`registerObserver` has no backpressure: Ditto never waits for your code before delivering the next result, and pausing the `changes` stream of a `StoreObserver` does not slow Ditto down; results queue up in the stream instead. Keep its listener synchronous and short (copy values, map them to model objects, call `setState`), and move expensive decoding or computation off the UI isolate, for example with Flutter's `compute()` on plain values copied out of the result.

```dart
// ❌ BAD: Slow async work per update without backpressure; uploads overlap and queue up.
StreamSubscription<QueryResult> uploadOnEveryChange(
  StoreObserver observer,
  Future<void> Function(List<Map<String, dynamic>>) upload,
) {
  return observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
  });
}
```

In our testing on SDK 5.1.0 and 5.2.0, with a callback that awaited 500 ms and ten writes 50 ms apart, `listen` with an `async` function ran up to 10 callbacks at the same time, and `await for` over the `changes` of a `registerObserver` observer handled all 11 results one after another, reaching the latest value about 5 seconds after the writes. `registerObserverV2` with `await for`, and `registerObserverWithSignalNext`, made 3 calls and reached the latest value after about 1.2 seconds (see [In Flutter, a slow async observer callback does not hold back the next result](../../knowledge/observations/flutter-sdk.md#in-flutter-a-slow-async-observer-callback-does-not-hold-back-the-next-result)).

For slow or asynchronous work per update, use one of the two experimental observer APIs (SDK 5.1+). Both return a `StoreObserverV2`, and both hold back further updates while your code is busy and then deliver the latest state (see [Backpressure (SDK 5.1+)](../observers.md#backpressure-sdk-51)).

**`registerObserverV2` (Experimental)** signals readiness automatically after each result has been added to the `changes` stream, and it follows the stream's pause and resume. Because `await for` pauses its subscription while the loop body runs, slow `async` work in the loop body applies backpressure without extra code.

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

Behavior of `registerObserverV2`:

- While the stream is paused, Ditto stops delivering after the update that arrived right at the pause. On resume, that held update and the latest state are delivered; intermediate states are merged. In our testing, five writes during a pause arrived as two results (see [In Flutter, the observer lifecycle rules held on SDK 5.1.0 and 5.2.0](../../knowledge/observations/flutter-sdk.md#in-flutter-the-observer-lifecycle-rules-held-on-sdk-510-and-520)).
- Leaving the loop (`break`, `return`, or an exception) cancels the stream subscription, and cancelling the stream subscription of a `StoreObserverV2` also cancels the observer.
- `observer.cancel()` closes the stream and ends the loop; `ditto.close()` does not, so cancel the observer before closing.
- `signalNext()` has no effect on observers registered with `registerObserverV2`.

**`registerObserverWithSignalNext` (Experimental)** delivers one result and then waits until you call `signalNext()` (the callback parameter or `observer.signalNext()`; see [Since SDK 5.1, local writes are coalesced into callbacks about 30 ms apart](../../knowledge/observations/observer-behavior.md#since-sdk-51-local-writes-are-coalesced-into-callbacks-about-30-ms-apart)). **If you never call it, the observer stops delivering updates.** Do not use pause and resume on the `changes` stream of such an observer; the SDK logs a warning if you do.

```dart
// ✅ GOOD: registerObserverWithSignalNext (Experimental): request the next update when done.
class OpenOrdersUploader {
  OpenOrdersUploader(this._ditto, this._upload);

  final Ditto _ditto;
  final Future<void> Function(List<Map<String, dynamic>> orders) _upload;
  StoreObserverV2? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    stop(); // Cancel a previous start, if any.
    final observer = _ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      arguments: {'status': 'open'},
    );
    _observer = observer;
    // Consume results through the changes stream (no onChange).
    _changes = observer.changes.listen((result) {
      final orders = result.items.map((item) => item.value).toList();
      unawaited(_handle(orders, observer.signalNext));
    });
  }

  Future<void> _handle(List<Map<String, dynamic>> orders, void Function() signalNext) async {
    try {
      await _upload(orders);
    } catch (error) {
      showError(error);
    } finally {
      signalNext(); // Always signal, even after an error; otherwise updates stop.
    }
  }

  void stop() {
    unawaited(_changes?.cancel()); // Cancelling the stream also cancels a StoreObserverV2.
    _observer?.cancel();
  }
}
```

```dart
// ❌ BAD: signalNext is skipped when the work throws; the observer silently stops updating.
StoreObserverV2 fragileObserver(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  final observer = ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY createdAt',
  );
  observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
    observer.signalNext(); // Never reached if upload() throws.
  });
  return observer;
}
```

The `onChange` callback of `registerObserverWithSignalNext` receives the `signalNext` function as its second parameter, but results passed to `onChange` are also queued in `changes`, so the note in [Store Observers in Flutter](#store-observers-in-flutter) applies here too. Consuming `changes` and calling `observer.signalNext()`, as above, avoids the issue. The stable `registerObserver` remains the default choice for widget code.

### Diffing results in Flutter

`Differ().diff()` takes a `List<QueryResultItem>`, so pass `result.items.toList()` (`items` is an `Iterable`). It returns a `Diff` with `insertions`, `deletions`, and `updates` (index sets) and `moves` (`DiffMove(from: oldIndex, to: newIndex)`). Project `_id` in a diffed query: on SDK 5.2.0, the rows of `registerObserverV2` and `registerObserverWithSignalNext` had no `_id` when the query did not project it, while those of `registerObserver` still had it, so a query that relies on the implicit `_id` breaks when you change the observer API (in our testing; see [On SDK 5.2.0, observer rows include _id only when it is projected, except with Flutter's registerObserver](../../knowledge/observations/observer-behavior.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected-except-with-flutters-registerobserver)). `Differ` only accepts items produced by Ditto: a test double that implements `QueryResultItem` makes `diff()` throw `ArgumentError` (`List must not contain subtypes of QueryResultItem`; in our testing with SDK 5.1.0 and 5.2.0, see [The differs accept only items from Ditto query results, and Kotlin apps do not create one](../../knowledge/observations/observer-behavior.md#the-differs-accept-only-items-from-ditto-query-results-and-kotlin-apps-do-not-create-one)). The semantics that every SDK shares are in [Diffing Results](../observers.md#diffing-results).

```dart
// ✅ GOOD: Logging changes between results with Differ.
StreamSubscription<QueryResult> logOrderChanges(StoreObserver observer) {
  final differ = Differ();
  var previousIds = <Object?>[];

  return observer.changes.listen((result) {
    final items = result.items.toList(); // diff() takes a List.
    final Diff diff = differ.diff(items);
    final currentIds = items.map((item) => item.value['_id']).toList();

    for (final index in diff.deletions) {
      debugPrint('deleted ${previousIds[index]}'); // Index into the OLD list.
    }
    for (final index in diff.insertions) {
      debugPrint('inserted ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final index in diff.updates) {
      debugPrint('updated ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final DiffMove move in diff.moves) {
      debugPrint('moved ${move.from} -> ${move.to}');
    }
    previousIds = currentIds;
  });
}
```

`Differ` is most useful with `AnimatedList`, which needs explicit `insertItem` and `removeItem` calls. A plain `ListView.builder` with `ValueKey`s does not need `Differ` at all.

```dart
// ✅ GOOD: Driving an AnimatedList from Differ results.
class AnimatedOrders extends StatefulWidget {
  const AnimatedOrders({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<AnimatedOrders> createState() => _AnimatedOrdersState();
}

class _AnimatedOrdersState extends State<AnimatedOrders> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _differ = Differ();
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen(_apply);
  }

  void _apply(QueryResult result) {
    final items = result.items.toList();
    final diff = _differ.diff(items);
    final previous = _orders;
    final next = items.map((item) => item.value).toList();
    final list = _listKey.currentState;

    if (list != null) {
      // Remove from the end so earlier old indexes stay valid.
      final removed = {...diff.deletions, for (final m in diff.moves) m.from}.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final index in removed) {
        final order = previous[index];
        list.removeItem(index, (context, animation) => _row(order, animation));
      }
      // Insert in ascending order of new indexes.
      final inserted = {...diff.insertions, for (final m in diff.moves) m.to}.toList()
        ..sort();
      for (final index in inserted) {
        list.insertItem(index);
      }
    }
    // Updated rows are rebuilt with the new values.
    setState(() => _orders = next);
  }

  Widget _row(Map<String, dynamic> order, Animation<double> animation) =>
      SizeTransition(
        sizeFactor: animation,
        child: ListTile(title: Text('${order['_id']}'), subtitle: Text('${order['status']}')),
      );

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
        key: _listKey,
        initialItemCount: _orders.length,
        itemBuilder: (context, index, animation) => _row(_orders[index], animation),
      );
}
```

**Why:** Applying removals in descending order and insertions in ascending order keeps `AnimatedList`'s internal indexes consistent with the new list. Treating a move as a removal plus an insertion is the simplest correct approach; use dedicated move animations only if your UI needs them.

### Partial UI updates in Flutter

Give each region its own widget with its own observer, and let a `ValueNotifier` or an equality check skip rebuilds when a value has not changed. `item.value` creates a new `Map` for every result, so two maps with identical contents are never `==` to each other; map results to immutable model classes that implement `==` if you rely on equality checks. The rules that every SDK shares are in [Partial UI Updates](../observers.md#partial-ui-updates).

```dart
// ✅ GOOD: The count badge and the list each observe what they need.
class OpenOrdersCount extends StatefulWidget {
  const OpenOrdersCount({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OpenOrdersCount> createState() => _OpenOrdersCountState();
}

class _OpenOrdersCountState extends State<OpenOrdersCount> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  final _count = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      final n = result.items.isEmpty ? 0 : result.items.first.value['n'];
      // ValueNotifier only notifies listeners when the value actually changes.
      _count.value = n is int ? n : 0;
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _count,
        builder: (context, count, _) => Text('Open orders: $count'),
      );
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, required this.ditto, required this.orderList});

  final Ditto ditto;

  /// A list widget with its own observer, such as OrdersByStatus in
  /// "Subscriptions in Flutter".
  final Widget orderList;

  @override
  Widget build(BuildContext context) {
    // The screen itself observes nothing; each region rebuilds independently.
    return Scaffold(
      appBar: AppBar(title: OpenOrdersCount(ditto: ditto)),
      body: orderList,
    );
  }
}
```

Use Flutter DevTools to confirm which widgets rebuild before optimizing further.

## Transactions in Flutter

Run statements through `tx.execute(query, arguments: {...})`, never through `ditto.store.execute`, which throws a `DittoException` inside a transaction ("Attempting to use `ditto.store.execute` while in a transaction scope. Use `transaction.execute` instead ..."; see [In Flutter, store.execute inside a transaction callback throws, and outside it only writes wait](../../knowledge/observations/flutter-sdk.md#in-flutter-storeexecute-inside-a-transaction-callback-throws-and-outside-it-only-writes-wait)). Flutter has no guard against a read-write transaction started inside another: in our testing, the inner one did not start until the outer one had ended, so an outer transaction that awaits it never ends, while every other combination of read-only and read-write transactions completed at once (see [In Flutter, a read-write transaction started inside another waits for the outer one](../../knowledge/observations/flutter-sdk.md#in-flutter-a-read-write-transaction-started-inside-another-waits-for-the-outer-one)). The rules are in [Transaction Rules](../transactions.md#transaction-rules).

> **Note (SDK 5.1.0 and 5.2.0):** The SDK recognizes a transaction by a value of the Dart zone in which its callback runs, and code that the callback starts keeps that zone. In our testing, a timer started inside the callback, and the listener of an observer whose `changes` the callback had listened to, could not call `ditto.store.execute` after the commit: every call threw `DittoException(Transaction is no longer valid. Do not store the transaction object outside the transaction callback)` (see [In Flutter, code started inside a transaction callback cannot call store.execute after the commit](../../knowledge/observations/flutter-sdk.md#in-flutter-code-started-inside-a-transaction-callback-cannot-call-storeexecute-after-the-commit)). Register observers, start timers, and schedule follow-up work outside the transaction callback.

`Store.transaction` signature:

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `callback` (positional) | `Future<T> Function(Transaction)` | required | The work to do. Use only the `Transaction` passed in. |
| `isReadOnly` | `bool` | `false` | Read-only transactions reject mutating statements and can run concurrently |
| `hint` | `String?` | `null` | A label written to the logs |

How a transaction ends:

| Callback outcome | Result |
|---|---|
| Returns `TransactionCompletionAction.commit` | Committed; `transaction()` returns `TransactionCompletionAction.commit` |
| Returns `TransactionCompletionAction.rollback` | Rolled back; no changes are applied; `transaction()` returns `TransactionCompletionAction.rollback` |
| Returns any other value (including nothing) | Committed; `transaction()` returns that value |
| Throws | Rolled back; the error is rethrown to the caller of `transaction()` |
| A statement fails, but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

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
      final order = result.items.first.value;

      await tx.execute(
        'INSERT INTO invoices DOCUMENTS (:invoice)',
        arguments: {
          'invoice': {
            '_id': invoiceId,
            'orderId': orderId,
            'total': order['total'],
            'createdAt': utcTimestamp(), // Defined in the Timestamps section.
          },
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

```dart
// ✅ GOOD: Explicit rollback without throwing, and a typed return value.
Future<bool> shipOrder(Ditto ditto, String orderId) async {
  final action = await ditto.store.transaction(
    hint: 'shipOrder',
    (tx) async {
      final result = await tx.execute(
        'SELECT * FROM orders WHERE _id = :id AND status = :status',
        arguments: {'id': orderId, 'status': 'paid'},
      );
      if (result.items.isEmpty) {
        return TransactionCompletionAction.rollback; // Nothing to ship.
      }
      await tx.execute(
        'UPDATE orders SET status = :status WHERE _id = :id',
        arguments: {'id': orderId, 'status': 'shipped'},
      );
      return TransactionCompletionAction.commit;
    },
  );
  return action == TransactionCompletionAction.commit;
}

// ✅ GOOD: A read-only transaction for a consistent multi-query snapshot.
Future<(int open, int closed)> orderCounts(Ditto ditto) {
  return ditto.store.transaction(
    hint: 'orderCounts',
    isReadOnly: true,
    (tx) async {
      final open = await tx.execute(
        'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
        arguments: {'status': 'open'},
      );
      final closed = await tx.execute(
        'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
        arguments: {'status': 'closed'},
      );
      return (
        open.items.first.value['n'] as int,
        closed.items.first.value['n'] as int,
      );
    },
  );
}
```

Using the `Transaction` object outside its callback throws a `DittoException`. Await every `tx.execute`: the `unawaited_futures` lint reports a missing `await`.

```dart
// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
Future<void> badCheckout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status WHERE _id = :id',
      arguments: {'id': orderId, 'status': 'checkout'},
    );
    // Network call inside the transaction: every other write, and every change
    // from other devices, waits until the transaction ends.
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
Future<void> checkout(Ditto ditto, String orderId, Future<void> Function() chargeCard) async {
  await chargeCard(); // Outside the transaction.
  await ditto.store.transaction(hint: 'recordPayment', (tx) async {
    await tx.execute(
      'UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': 'paid',
        'paidAt': utcTimestamp(), // fixed-precision helper (see Timestamps)
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

`ditto.close()` does not wait for pending transactions in Flutter, and calling it while one is open stops the isolate (see [Closing Ditto in Flutter](#closing-ditto-in-flutter) and [In Flutter, close() while a transaction is open stops the app's isolate](../../knowledge/observations/flutter-sdk.md#in-flutter-close-while-a-transaction-is-open-stops-the-apps-isolate)). Track them yourself and await them before closing:

```dart
// ✅ GOOD: Track in-flight transactions so shutdown can wait for them.
class TransactionTracker {
  final _pending = <Future<Object?>>{};

  Future<T> run<T>(Ditto ditto, String hint, Future<T> Function(Transaction tx) work) {
    final future = ditto.store.transaction(hint: hint, work);
    _pending.add(future);
    return future.whenComplete(() => _pending.remove(future));
  }

  Future<void> closeWhenIdle(Ditto ditto) async {
    // Errors are reported to the callers of run(); ignore them here.
    // then() with an onError callback works for any result type T, whereas a
    // catchError handler would have to return a value of type T.
    await Future.wait(_pending.map((f) => f.then<void>((_) {}, onError: (Object _) {})));
    await ditto.close();
  }
}
```

**Read, change, and write in one transaction**: replacing an array, or copying a document to a new `_id`, reads a value and writes a new one. Doing both in one transaction keeps two local calls from interleaving; a concurrent edit on another device can still win the merge (see [Working with arrays](../data-modeling.md#working-with-arrays) and [IDs are immutable](../data-modeling.md#ids-are-immutable)).

```dart
// The array is a register: this write replaces it as a whole. Reading and
// writing in one transaction keeps two local calls from interleaving and
// dropping a tag; a concurrent edit on another device can still win the merge.
Future<void> addTag(Ditto ditto, String productId, String tag) async {
  await ditto.store.transaction(hint: 'addTag', (tx) async {
    final result = await tx.execute(
      'SELECT tags FROM products WHERE _id = :id',
      arguments: {'id': productId},
    );
    if (result.items.isEmpty) return;
    final current = (result.items.first.value['tags'] as List?) ?? const [];
    await tx.execute(
      'UPDATE products SET tags = :tags WHERE _id = :id',
      arguments: {'id': productId, 'tags': [...current, tag]},
    );
  });
}
```

```dart
/// Copies an order to a new ID and deletes the original, atomically.
/// Both statements declare the order's COUNTER, ATTACHMENT, and REGISTER
/// fields exactly as the other statements on orders do, so the copy keeps
/// their CRDT types. Undeclared objects such as shippingAddress are MAPs.
Future<void> moveOrder(Ditto ditto, String oldId, String newId) async {
  await ditto.store.transaction(hint: 'moveOrder', (tx) async {
    final result = await tx.execute(
      '''
      SELECT * FROM COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      WHERE _id = :id
      ''',
      arguments: {'id': oldId},
    );
    if (result.items.isEmpty) return;
    final copy = Map<String, dynamic>.from(result.items.first.value)
      ..['_id'] = newId;
    await tx.execute(
      '''
      INSERT INTO COLLECTION orders
        (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
      DOCUMENTS (:doc)
      ''',
      arguments: {'doc': copy},
    );
    await tx.execute(
      'DELETE FROM orders WHERE _id = :id',
      arguments: {'id': oldId},
    );
  });
}
```

## Attachments in Flutter

Create attachments with `ditto.store.newAttachment(pathOrBytes, [metadata])`. The rules are in [Attachments](../attachments.md).

| `newAttachment` detail | Behavior |
|---|---|
| First argument | A file path (`String`) or the raw bytes (`Uint8List`) |
| File paths | The file is copied into Ditto's store. Pass an absolute path (for example, one built from `path_provider`). Not supported in web browsers (throws). |
| Metadata | Optional positional `AttachmentMetadata(Map<String, String>)`; values must be strings |
| Result | An `Attachment` with `id`, `len`, `metadata`, `data` (a `Future<Uint8List>`) and `copyToPath(destination)` (native platforms only) |

```dart
import 'dart:typed_data';

// ✅ GOOD: Create an attachment from a file and insert it with a declared ATTACHMENT field.
Future<void> savePhoto(Ditto ditto, String photoId, String filePath) async {
  // The file is copied into Ditto's blob store; the original can be deleted afterwards.
  final Attachment attachment = await ditto.store.newAttachment(
    filePath,
    AttachmentMetadata({'name': 'receipt.jpg', 'mimeType': 'image/jpeg'}), // String values only.
  );

  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'image': attachment,
        'createdAt': utcTimestamp(), // Defined in the Timestamps section.
      },
    },
  );
}

// ✅ GOOD: Create an attachment from bytes (the only option on the Web).
Future<Attachment> attachmentFromBytes(Ditto ditto, Uint8List bytes, String name) {
  return ditto.store.newAttachment(bytes, AttachmentMetadata({'name': name}));
}
```

`ditto.store.fetchAttachment(token, onFetchEvent)` returns an `AttachmentFetcher` immediately and reports `AttachmentFetchEventProgress` (`downloadedBytes`, `totalBytes`), `AttachmentFetchEventCompleted` (`attachment`; read the bytes with `await attachment.data`), and `AttachmentFetchEventDeleted`. `AttachmentFetchEvent` is not a sealed class, so add a `default` branch to `switch` statements.

| `AttachmentFetcher` member | Meaning |
|---|---|
| `stop()` | Cancels an in-flight fetch. Not required after completion; a completed fetcher stops itself. |
| `isStopped` | `true` after `stop()` or after the fetch completed |
| `attachment` | A `Future<Attachment?>` that completes with the attachment, or with an error if it was deleted. It never completes after `stop()`, so do not await it once you have stopped the fetcher. |

```dart
import 'dart:async';
import 'dart:typed_data';

// ✅ GOOD: Lazy, cancellable attachment loading with a stall timeout.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.ditto,
    required this.token,
    this.stallTimeout = const Duration(seconds: 30),
  });

  final Ditto ditto;

  /// The attachment token read from a document field.
  final Map<String, dynamic> token;

  /// How long to wait without any progress before giving up.
  final Duration stallTimeout;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  AttachmentFetcher? _fetcher;
  Timer? _stallTimer;
  Uint8List? _bytes;
  double? _progress;
  bool _failed = false;
  int _fetchGeneration = 0; // Identifies the current fetch.

  @override
  void initState() {
    super.initState();
    _startFetch(); // Fetch only when the widget is actually built (lazy loading).
  }

  void _startFetch() {
    _fetcher?.stop();
    _failed = false;
    _progress = null;
    _restartStallTimer();
    final generation = ++_fetchGeneration;
    _fetcher = widget.ditto.store.fetchAttachment(
      widget.token,
      (event) => _onFetchEvent(event, generation),
    );
  }

  // False for events of a replaced fetch (token change, retry) or a disposed widget.
  bool _isCurrent(int generation) => mounted && generation == _fetchGeneration;

  void _restartStallTimer() {
    _stallTimer?.cancel();
    // Ditto has no fetch timeout: no event simply means no peer is delivering the blob.
    _stallTimer = Timer(widget.stallTimeout, () {
      _fetcher?.stop();
      if (mounted) setState(() => _failed = true);
    });
  }

  Future<void> _onFetchEvent(AttachmentFetchEvent event, int generation) async {
    if (!_isCurrent(generation)) return;
    switch (event) {
      case AttachmentFetchEventProgress(:final downloadedBytes, :final totalBytes):
        _restartStallTimer(); // Progress resets the stall timer.
        if (totalBytes > 0) {
          setState(() => _progress = downloadedBytes / totalBytes);
        }
      case AttachmentFetchEventCompleted(:final attachment):
        _stallTimer?.cancel();
        try {
          final bytes = await attachment.data;
          // Check again: the token can change while the bytes are read.
          if (_isCurrent(generation)) setState(() => _bytes = bytes);
        } catch (error) {
          if (_isCurrent(generation)) setState(() => _failed = true);
        }
      case AttachmentFetchEventDeleted():
        _stallTimer?.cancel();
        setState(() => _failed = true);
      default: // AttachmentFetchEvent is not sealed.
        break;
    }
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flutter can reuse this State for a different token (list updates, replaced photos).
    if (oldWidget.token['id'] != widget.token['id']) {
      _bytes = null;
      _startFetch();
    }
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _fetcher?.stop(); // Cancel the download if the widget goes away first.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    if (_failed) {
      return IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Retry',
        onPressed: () => setState(_startFetch),
      );
    }
    return Center(child: CircularProgressIndicator(value: _progress));
  }
}
```

```dart
// Reading the token from a document.
Map<String, dynamic>? imageToken(Map<String, dynamic> photo) {
  final token = photo['image'];
  return token is Map<String, dynamic> ? token : null;
}
```

To replace or remove an attachment (see [Attachments Are Immutable](../attachments.md#attachments-are-immutable)):

```dart
// ✅ GOOD: Replace an attachment by creating a new one and updating the token field.
Future<void> replacePhoto(Ditto ditto, String photoId, String newFilePath) async {
  final attachment = await ditto.store.newAttachment(
    newFilePath,
    AttachmentMetadata({'name': 'receipt-v2.jpg', 'mimeType': 'image/jpeg'}),
  );
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id',
    arguments: {'id': photoId, 'image': attachment},
  );
}

// ✅ GOOD: Remove the reference; the blob becomes eligible for garbage collection.
Future<void> removePhoto(Ditto ditto, String photoId) async {
  await ditto.store.execute(
    'UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id',
    arguments: {'id': photoId},
  );
}
```

Thumbnails and full-size images (see [Thumbnail Pattern](../attachments.md#thumbnail-pattern)):

```dart
import 'dart:typed_data';

// ✅ GOOD: Insert a thumbnail attachment and a full-size attachment together.
Future<void> savePhotoWithThumbnail(
  Ditto ditto, {
  required String photoId,
  required Uint8List thumbnailBytes, // Downscaled by your app beforehand.
  required String fullSizePath,
}) async {
  final thumbnail = await ditto.store.newAttachment(
    thumbnailBytes,
    AttachmentMetadata({'kind': 'thumbnail', 'mimeType': 'image/jpeg'}),
  );
  final fullSize = await ditto.store.newAttachment(
    fullSizePath,
    AttachmentMetadata({'kind': 'full', 'mimeType': 'image/jpeg'}),
  );

  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'thumbnail': thumbnail,
        'image': fullSize,
        'createdAt': utcTimestamp(), // Defined in the Timestamps section.
      },
    },
  );
}
```

```dart
// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when opened.
class PhotoRow extends StatelessWidget {
  const PhotoRow({super.key, required this.photo, required this.attachmentImage});

  final Map<String, dynamic> photo;

  /// Builds a lazily fetched image, for example:
  /// `(token, timeout) => AttachmentImage(ditto: ditto, token: token, stallTimeout: timeout)`.
  final Widget Function(Map<String, dynamic> token, Duration stallTimeout) attachmentImage;

  @override
  Widget build(BuildContext context) {
    final thumbnail = photo['thumbnail'];
    final fullSize = photo['image'];
    return ListTile(
      leading: SizedBox.square(
        dimension: 56,
        child: thumbnail is Map<String, dynamic>
            ? attachmentImage(thumbnail, const Duration(seconds: 30))
            : const Icon(Icons.image_not_supported),
      ),
      title: Text('${photo['_id']}'),
      onTap: fullSize is Map<String, dynamic>
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(),
                  // Larger files need a longer stall timeout.
                  body: attachmentImage(fullSize, const Duration(minutes: 2)),
                ),
              ))
          : null,
    );
  }
}
```

## IDs and Timestamps in Flutter

**IDs**: generate a random (version 4) UUID for every new document, with a maintained package (for example, `uuid` on pub.dev) or a helper such as `uuidV4()` below; never derive IDs from a counter or the clock. Keep human-readable numbers in a separate field. The rules are in [Document IDs](../data-modeling.md#document-ids).

```dart
import 'dart:math';

final _random = Random.secure();

/// Returns a random (version 4) UUID such as "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f".
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<String> createOrder(Ditto ditto, String storeId) async {
  final orderId = uuidV4();
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'storeId': storeId,
        'status': 'open',
        'createdAt': utcTimestamp(), // defined below
      },
    },
  );
  return orderId;
}
```

```dart
// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
String badSequentialId(int dailyCount) => 'order-$dailyCount';

// ❌ BAD: Collides when two devices write within the same millisecond.
String badTimestampId() => 'order-${DateTime.now().millisecondsSinceEpoch}';
```

```dart
/// A display label, not an identifier: uniqueness is not guaranteed across
/// devices, so never use it as _id or as a lookup key.
String displayNumber(String terminalCode, int localSequence) =>
    '$terminalCode-${localSequence.toString().padLeft(4, '0')}';

Future<void> createOrderWithLabel(
  Ditto ditto, {
  required String orderId,
  required String terminalCode,
  required int localSequence,
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId, // UUID
        'displayNumber': displayNumber(terminalCode, localSequence),
        'createdAt': utcTimestamp(),
      },
    },
  );
}
```

**Timestamps**: store UTC with a zone designator, and produce every timestamp that is sorted or compared with one fixed-precision helper (see [Timestamps](../data-modeling.md#timestamps)). Two details of Dart make this necessary:

- `DateTime.now().toIso8601String()` returns local time **without** a zone designator (for example, `2026-10-08T19:30:00.123456`), for which DQL date functions return `MISSING` without an error. Always call `toUtc()` first. <!-- lint-ignore -->
- On native platforms (iOS, Android, and desktop), `toIso8601String()` includes microseconds only when they are non-zero, so one device produces both `.123456Z` and `.123Z`; on the Web it includes only milliseconds (`.123Z`). Such strings do not sort chronologically as text.

Epoch milliseconds (`DateTime.now().millisecondsSinceEpoch`) are the compact alternative.

```dart
/// Returns the current time as an ISO-8601 UTC string with exactly
/// millisecond precision, e.g. "2026-10-08T10:30:00.123Z".
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ✅ GOOD: Consistent UTC timestamps from the one helper.
Future<void> markReady(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
    arguments: {'id': orderId, 'readyAt': utcTimestamp()},
  );
}
```

```dart
// ❌ BAD: Local time without a zone. DQL date functions return MISSING for it,
// and values written in different time zones do not compare correctly.
await ditto.store.execute(
  'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
  arguments: {
    'id': 'order-1',
    'readyAt': DateTime.now().toIso8601String(), // lint-ignore
  },
);
```

## Transports and Presence in Flutter

`TransportConfig` is immutable. Change it with `ditto.updateTransportConfig()`, which gives you a builder initialized with the current configuration; never assign a new `TransportConfig()`, which has every transport disabled, whereas a newly opened instance on macOS has Bluetooth LE, LAN, and AWDL enabled (in our testing with SDK 5.1.0 and 5.2.0; see [A new instance enables the platform's peer-to-peer transports, and an empty configuration enables none](../../knowledge/observations/connections-and-presence.md#a-new-instance-enables-the-platforms-peer-to-peer-transports-and-an-empty-configuration-enables-none)). The rules are in [Transport Configuration](../setup-and-lifecycle.md#transport-configuration).

```dart
// ✅ GOOD: Adjust the current configuration with the builder.
void configureTransports(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.setAllPeerToPeerEnabled(true); // BLE, LAN, AWDL / Wi-Fi Aware
    config.peerToPeer.bluetoothLE.isEnabled = false; // for example, LAN and P2P Wi-Fi only
  });
}
```

```dart
// ✅ GOOD: A hub device listens on TCP; other devices connect to it.
void configureHub(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = '[::]'
      ..port = 4040;
  });
}

void connectToHub(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.connect.tcpServers = {'192.168.1.10:4040'};
    // Additional WebSocket endpoints, if you run your own:
    // config.connect.webSocketUrls = {'wss://sync.example.com'};
  });
}
```

```dart
// ✅ GOOD: A hub that serves up to 12 TCP clients. The limit is part of the
// hub's configuration, so it is applied on every open, before sync starts
// (SDK 5.2+).
DittoConfig hubConfig(DittoConfigConnect connect) => DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: connect,
      systemParameters: const {'MESH_CHOOSER_MAX_WLAN_CONNECTIONS': 12},
    );

// Call with an instance opened from hubConfig(), after the authentication
// handler or the offline license token is set.
void startHub(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = '[::]'
      ..port = 4040;
  });
  ditto.sync.start();
}
```

**Transport conditions and permissions (SDK 5.1+)**: `ditto.observeTransportConditions()` reports why a transport is not working; call `stop()` on the returned observer when you no longer need it. On Android, `DittoSyncPermissions` reports which runtime permissions Ditto needs and which are missing; it returns empty lists on other platforms. Request the permissions with a package such as `permission_handler`. Since SDK 5.2, `requiredPermissions()` and `missingPermissions()` cover only the generally available transports; get the multicast permissions with `await DittoSyncPermissions().requiredMulticastPermissions()` and check them with `missingPermissions(multicastPermissions)` (see [Diagnosing transport problems (SDK 5.1+)](../setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51)).

```dart
// ✅ GOOD: Surface transport problems and missing permissions.
Future<TransportConditionsObserver> watchTransports(Ditto ditto) async {
  final missing = await DittoSyncPermissions().missingPermissions();
  if (missing.isNotEmpty) {
    debugPrint('Ditto is missing Android permissions: $missing');
  }

  return ditto.observeTransportConditions((event) {
    if (event.condition != TransportCondition.ok) {
      debugPrint('Transport ${event.source.name}: ${event.condition.name}');
    }
  });
}
```

**Presence**: `ditto.presence.observe((graph) { ... })` returns a `PresenceObserver`; call `stop()` on it when you no longer need it. `graph.remotePeers` is a `Set<Peer>`, and each `Peer` has `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections` (with `peer1`, `peer2`, and `connectionType`), and `peerMetadata`. Set this device's metadata with `ditto.presence.peerMetadata = {'role': 'cashier'};` and its name with `ditto.deviceName`, whose default is derived from the device model and which is truncated to 24 bytes when you set it (see [Presence](../setup-and-lifecycle.md#presence)).

```dart
// ✅ GOOD: Show connected peers and stop the observer when done.
class PeerList extends StatefulWidget {
  const PeerList({super.key, required this.ditto});
  final Ditto ditto;

  @override
  State<PeerList> createState() => _PeerListState();
}

class _PeerListState extends State<PeerList> {
  late final PresenceObserver _presence;
  List<Peer> _peers = const [];
  String _localPeerKey = '';

  @override
  void initState() {
    super.initState();
    _presence = widget.ditto.presence.observe((graph) {
      if (!mounted) return;
      setState(() {
        _localPeerKey = graph.localPeer.peerKey;
        _peers = graph.remotePeers.toList();
      });
    });
  }

  @override
  void dispose() {
    _presence.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          for (final peer in _peers)
            ListTile(
              title: Text(peer.deviceName),
              subtitle: Text(_route(peer)),
            ),
        ],
      );

  // A peer's connections include its links to other peers, so only the
  // connections that have this device at one end make it a direct neighbor.
  String _route(Peer peer) {
    final directTypes = {
      for (final connection in peer.connections)
        if (connection.peer1 == _localPeerKey ||
            connection.peer2 == _localPeerKey)
          connection.connectionType.name,
    };
    final route = directTypes.isEmpty
        ? 'Through other peers'
        : 'Direct (${directTypes.join(', ')})';
    return peer.isConnectedToDittoServer
        ? '$route, connected to Ditto Server'
        : route;
  }
}
```

**Incoming connections**: `ditto.presence.connectionRequestHandler` receives each connection request and returns `ConnectionRequestAuthorization.allow` or `deny`; set it to `null` to remove it (see [Controlling Incoming Connections](../security.md#controlling-incoming-connections)). A handler that throws, or whose `Future` fails, denies at once, and one that has not answered after 10 seconds is rejected (in our testing with SDK 5.1.0 and 5.2.0; see [A connection request handler that does not answer within 10 seconds rejects the peer, and one that throws differs by SDK](../../knowledge/observations/connections-and-presence.md#a-connection-request-handler-that-does-not-answer-within-10-seconds-rejects-the-peer-and-one-that-throws-differs-by-sdk)).

```dart
// ✅ GOOD: Accept only peers whose signed metadata belongs to this store.
// Requires DittoConfigConnectServer: identityServiceMetadata comes from your
// authentication webhook and is empty in small-peers-only mode.
void restrictConnectionsToStore(Ditto ditto, String storeId) {
  ditto.presence.connectionRequestHandler = (request) async {
    try {
      final metadata = request.identityServiceMetadata;
      return metadata['storeId'] == storeId
          ? ConnectionRequestAuthorization.allow
          : ConnectionRequestAuthorization.deny;
    } catch (_) {
      return ConnectionRequestAuthorization.deny; // deny explicitly on any error
    }
  };
}
```

## Logging in Flutter

`DittoLogger` is a set of static members. Every member throws `Ditto not initialized` until the SDK is initialized, and `Ditto.open` initializes it implicitly. To configure logging **before** opening Ditto (recommended), call `await Ditto.init()` first. The levels are `LogLevel.error`, `warning`, `info`, `debug`, and `verbose`. The rules are in [Logging](../logging-and-observability.md#logging).

```dart
import 'package:flutter/foundation.dart';

/// Call before Ditto.open().
Future<void> configureDittoLogging() async {
  // DittoLogger throws until Ditto is initialized.
  await Ditto.init();

  DittoLogger.isEnabled = true;
  DittoLogger.minimumLogLevel =
      kReleaseMode ? LogLevel.warning : LogLevel.debug;
}
```

`DittoLogger.customLogCallback` receives the log events that Ditto emits. `ditto.close()` resets it to `null` for the whole process, even if other `Ditto` instances are still open: in our testing on SDK 5.1.0 and 5.2.0, after one of two instances was closed, neither the other instance nor a newly opened one sent the callback any line (see [In Flutter, close() clears DittoLogger.customLogCallback](../../knowledge/observations/flutter-sdk.md#in-flutter-close-clears-dittologgercustomlogcallback)). If your app closes and reopens Ditto (for example when the user signs out and in again), set the callback again before each `Ditto.open()`, after `Ditto.init()`, so that logs emitted while Ditto opens are forwarded too.

```dart
/// Forwards Ditto warnings and errors to the app's logging pipeline.
/// Call after Ditto.init() and before every Ditto.open(), because
/// ditto.close() clears the callback.
void installDittoLogForwarding(void Function(String line) report) {
  DittoLogger.customLogCallback = (LogLevel level, String message) {
    if (level == LogLevel.error || level == LogLevel.warning) {
      report('[ditto ${level.name}] $message');
    }
  };
}

class DittoSession {
  DittoSession(this._config, this._report);

  final DittoConfig _config;
  final void Function(String line) _report;
  Ditto? _ditto;

  Future<Ditto> open() async {
    await Ditto.init(); // No-op after the first call.
    installDittoLogForwarding(_report); // Set before every open.
    final ditto = await Ditto.open(_config);
    return _ditto = ditto;
  }

  Future<void> close() async {
    await _ditto?.close(); // Also resets DittoLogger.customLogCallback.
    _ditto = null;
  }
}
```

`DittoLogger.isDevtoolsLoggingEnabled = true` additionally sends Ditto logs to Flutter DevTools through `dart:developer`.

`DittoLogger.exportLogs(path)` writes the on-disk logs; it throws a `DittoError` if the file exists (see [On-disk logs and exporting them](../logging-and-observability.md#on-disk-logs-and-exporting-them)):

```dart
import 'dart:io';

/// Exports Ditto's on-disk logs, for example for a "Send diagnostics" button.
/// [directory] must exist, for example a temporary or support directory.
Future<File> exportDittoLogs(Directory directory) async {
  final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final file = File('${directory.path}/ditto-logs-$timestamp.jsonl.gz');
  final bytes = await DittoLogger.exportLogs(file.path);
  debugPrint('Exported $bytes bytes of Ditto logs to ${file.path}');
  return file;
}
```

A support bundle (SDK 5.2+, native platforms only) is created with DQL and fetched like any other attachment (see [Support bundles (SDK 5.2+)](../logging-and-observability.md#support-bundles-sdk-52)):

```dart
// ✅ GOOD: Create a support bundle and save it, for example to share it with
// Ditto support. [path] must not exist yet.
Future<void> saveSupportBundle(Ditto ditto, String path) async {
  final result = await ditto.store.execute(
    "EXECUTE FUNCTION system_request_support_bundle()",
  );
  final token = Map<String, dynamic>.from(result.items.single.value['file'] as Map);
  final fetcher = ditto.store.fetchAttachment(token, (event) {});
  final attachment = await fetcher.attachment;
  await attachment!.copyToPath(path);
}
```

**Storage snapshot**: read `system:system_info` with `execute` when you need it, ordered by `timestamp`, and let later rows of a key overwrite earlier ones (see [Monitoring Storage](../deletion-and-storage.md#monitoring-storage)).

```dart
// ✅ GOOD: Read the latest storage snapshot on demand (for example from a
// diagnostics screen or a daily maintenance task).
Future<Map<String, Object?>> storageSnapshot(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT key, value, timestamp FROM system:system_info "
    "WHERE key LIKE 'fs_%' OR key LIKE 'collection_num_docs%' "
    "ORDER BY timestamp ASC",
  );
  final snapshot = <String, Object?>{};
  for (final item in result.items) {
    // Later rows overwrite earlier ones, so the newest value wins.
    snapshot[item.value['key'] as String] = item.value['value'];
  }
  return snapshot;
}
```

## Testing in Flutter

The tests below are `test(...)` calls that go inside `main()` of a file with the helper from [A local-store test helper in Flutter](#a-local-store-test-helper-in-flutter), with `ditto` provided by `setUp`. Their `import` lines belong at the top of the file. What each test checks is described in [Testing Strategies](../testing.md).

```dart
import 'package:flutter_test/flutter_test.dart';

test('adding a line item keeps the existing items (map keyed by ID)', () async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': 'order-1',
        'items': {
          'item-1': {'productId': 'p1', 'quantity': 2},
        },
      },
    },
  );

  // The code under test: an upsert of a partial document (see "Arrays and Maps").
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': 'order-1',
        'items': {
          'item-2': {'productId': 'p2', 'quantity': 1},
        },
      },
    },
  );

  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': 'order-1'},
  );
  final items = result.items.first.value['items'];
  expect(items, isA<Map<String, dynamic>>()); // not an array
  expect((items as Map).keys, containsAll(<String>['item-1', 'item-2']));
});

test('re-upserting unchanged data is a no-op', () async {
  const product = {'_id': 'p1', 'name': 'Pen', 'priceCents': 250};
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );

  final again = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'product': product},
  );
  expect(again.mutatedDocumentIDs(), isEmpty);
});

// The code under test: the app's replaceAddress() (see "Assigning an object merges it").
Future<void> replaceAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> address,
) async {
  await ditto.store.transaction(hint: 'replaceAddress', (tx) async {
    await tx.execute(
      'UPDATE customers UNSET address WHERE _id = :id',
      arguments: {'id': customerId},
    );
    await tx.execute(
      'UPDATE customers SET address = :address WHERE _id = :id',
      arguments: {'id': customerId, 'address': address},
    );
  });
}

test('replaceAddress removes keys that are not in the new address', () async {
  await ditto.store.execute(
    'INSERT INTO customers DOCUMENTS (:customer)',
    arguments: {
      'customer': {
        '_id': 'c1',
        'address': {'city': 'Oslo', 'zip': '0150'},
      },
    },
  );

  await replaceAddress(ditto, 'c1', {'city': 'Bergen'});

  final result = await ditto.store.execute(
    'SELECT * FROM customers WHERE _id = :id',
    arguments: {'id': 'c1'},
  );
  // A plain SET would keep "zip": objects merge under the default settings.
  expect(result.items.first.value['address'], {'city': 'Bergen'});
});
```

```dart
import 'package:flutter_test/flutter_test.dart';

test('active-orders query treats a missing or null flag as not deleted', () async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:orders)',
    arguments: {
      'orders': [
        {'_id': 'deleted', 'isDeleted': true},
        {'_id': 'active', 'isDeleted': false},
        {'_id': 'nullFlag', 'isDeleted': null},
        {'_id': 'noFlag'},
      ],
    },
  );

  // The query used by the app's repository.
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id',
  );
  expect(
    result.items.map((item) => item.value['_id']).toList(),
    ['active', 'noFlag', 'nullFlag'],
  );
});

test('deleting by ID removes exactly the listed documents', () async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:orders)',
    arguments: {
      'orders': [
        {'_id': 'o1'},
        {'_id': 'o2'},
        {'_id': 'o3'},
      ],
    },
  );

  // The statement used by the app; WHERE _id IN :ids, not USE IDS.
  final deleted = await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids',
    arguments: {'ids': ['o1', 'o2']},
  );
  expect(deleted.mutatedDocumentIDs(), hasLength(2));

  final remaining = await ditto.store.execute('SELECT _id FROM orders');
  expect(remaining.items.map((item) => item.value['_id']), ['o3']);
});
```

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

test('observer sees a new order and is cancelled cleanly', () async {
  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    arguments: {'status': 'open'},
  );
  final sawOrder = Completer<void>();
  final changes = observer.changes.listen((result) {
    if (result.items.length == 1 && !sawOrder.isCompleted) {
      sawOrder.complete();
    }
  });

  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {'_id': 'order-1', 'status': 'open'},
    },
  );
  await sawOrder.future.timeout(const Duration(seconds: 5));

  // The same cleanup that the widget's dispose() performs.
  await changes.cancel();
  observer.cancel();
  expect(observer.isCancelled, isTrue);
});
```

For widget tests of screens that own observers, keep the observer behind your own interface and inject a stream you control. `Differ` only accepts items produced by Ditto, so code that uses it needs a real store (see [The differs accept only items from Ditto query results, and Kotlin apps do not create one](../../knowledge/observations/observer-behavior.md#the-differs-accept-only-items-from-ditto-query-results-and-kotlin-apps-do-not-create-one)).

`registerSubscription` throws a `DittoException` for a query that subscriptions do not accept:

<!-- expect-error -->
```dart
import 'package:flutter_test/flutter_test.dart';

test('subscriptions with projections or ORDER BY/LIMIT are rejected', () async {
  expect(
    () => ditto.sync.registerSubscription('SELECT _id, status FROM orders'),
    throwsA(isA<DittoException>()),
  );
  expect(
    () => ditto.sync.registerSubscription(
      'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50',
    ),
    throwsA(isA<DittoException>()),
  );
});
```

```dart
import 'package:flutter_test/flutter_test.dart';

test("the app's subscriptions are valid", () async {
  final subscriptions = [
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': 'store-1'},
    ),
    ditto.sync.registerSubscription('SELECT * FROM products'),
  ];
  for (final subscription in subscriptions) {
    subscription.cancel();
    expect(subscription.isCancelled, isTrue);
  }
});
```

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// The app's statements with representative arguments. In a real app, keep
/// the statement strings in your repository and reference them here.
const appStatements = <String, Map<String, Object?>>{
  'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC': {
    'status': 'open',
  },
  'UPDATE orders SET status = :status WHERE _id = :id': {
    'status': 'closed',
    'id': 'order-1',
  },
  'DELETE FROM orders WHERE _id IN :ids': {
    'ids': ['order-1'],
  },
};

test('every app statement can be planned', () async {
  for (final MapEntry(key: statement, value: arguments) in appStatements.entries) {
    // EXPLAIN throws if a statement cannot be parsed or planned.
    await ditto.store.execute('EXPLAIN $statement', arguments: arguments);
  }
});

test('the open-orders query uses its index', () async {
  // In your suite, create indexes with the same startup code as the app
  // (for example, through the configure callback of openTestDitto).
  await ditto.store.execute(
    'CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt '
    'ON orders (status, createdAt DESC)',
  );
  final plan = await ditto.store.execute(
    'EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  expect(jsonEncode(plan.items.first.value), contains('indexScan'));
});
```

### A local-store test helper in Flutter

The file below contains a helper that opens a small-peers-only instance in its own temporary directory for every test, and closes all of them after the last test of the file (see [A Test Helper for a Local Store](../testing.md#a-test-helper-for-a-local-store)). Pass the same `systemParameters` that your app passes in its `DittoConfig`, and a `configure` callback for the indexes that your app creates at startup. As your suite grows, move the helper into a shared file under `integration_test/`.

> **Note (SDK 5.2.0):** Do not close each test's store when that test ends. In our testing, a file whose tests each opened a store, used a subscription or a transaction, and closed the store stopped at the `Ditto.open()` or `close()` of the second or third test, without an error, in every run on 5.2.0 but not on 5.1.0. Keeping the stores open until `tearDownAll`, as below, and keeping the subscription and transaction objects referenced both avoided it (see [In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](../../knowledge/observations/flutter-sdk.md#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close)).

```dart
// integration_test/orders_test.dart
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The stores that the tests of this file opened. They close together after
/// the last test: on SDK 5.2.0, opening a store after another store of the
/// process was closed could stop (see "A local-store test helper in Flutter").
final _testStores = <(Ditto, Directory)>[];

/// Opens a Ditto instance for one test. Sync is never started, so no
/// license token or network connection is needed.
Future<Ditto> openTestDitto({
  Map<String, Object> systemParameters = const {},
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  final ditto = await Ditto.open(
    DittoConfig(
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      persistenceDirectory: directory.path,
      // The same parameters as the app's DittoConfig (SDK 5.2+).
      systemParameters: systemParameters,
    ),
  );

  _testStores.add((ditto, directory)); // closed by closeTestDittos()

  // Create the app's indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

/// Closes every store that openTestDitto() opened and deletes its directory.
/// Register it once per file: tearDownAll(closeTestDittos).
Future<void> closeTestDittos() async {
  for (final (ditto, directory) in _testStores) {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  }
  _testStores.clear();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(closeTestDittos);

  // Every test starts with an empty store.
  late Ditto ditto;
  setUp(() async {
    // Pass `systemParameters:` and `configure:` with the settings and
    // indexes your app uses; see "Applying System Parameters".
    ditto = await openTestDitto();
  });

  test('a new store is empty', () async {
    final result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
    expect(result.items.first.value['n'], 0);
  });

  // The tests in the following sections go here.
}
```

**Running the tests:** A real `Ditto` instance needs the SDK's native library, which is packaged with your app build for each platform. Run tests that open Ditto with the `integration_test` package on a supported desktop or device target, for example `flutter test integration_test/orders_test.dart -d macos`. Tests that use only a mock of your own interface run with a plain `flutter test`. On Flutter Web the store is in memory and does not support indexes (see [Installing the Flutter SDK](#installing-the-flutter-sdk)), so skip index assertions there.

### Several peers in one test in Flutter

The helpers below open several small peers in one `integration_test` process and connect them over TCP on `127.0.0.1` only (see [Several peers in one test process](../testing.md#several-peers-in-one-test-process)). This file was verified with `ditto_live` 5.2.0 on macOS, with the license token read from a file instead of `--dart-define`; like the local-store test file, it closes its stores only after its last test (see the note in [A local-store test helper in Flutter](#a-local-store-test-helper-in-flutter)). Run it with `flutter test integration_test/multipeer_test.dart -d macos --dart-define-from-file=license.json`, where `license.json` (not committed) contains `{"DITTO_LICENSE_TOKEN": "..."}`.

```dart
// integration_test/multipeer_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Offline license token, passed with --dart-define (never commit it).
const licenseToken = String.fromEnvironment('DITTO_LICENSE_TOKEN');

/// The peers that the tests of this file opened. They close together after
/// the last test (see "A local-store test helper in Flutter").
final _peerStores = <(Ditto, Directory)>[];

/// Opens [count] peers in this process that sync with each other over TCP on
/// localhost only: peer 0 listens, the others connect to it. A device accepts
/// at most 6 TCP connections by default, so keep [count] at 7 or below.
Future<List<Ditto>> openSyncedPeers(
  int count, {
  int port = 4041,
  String databaseID = '00000000-0000-4000-8000-000000000002',
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final peers = <Ditto>[];
  for (var i = 0; i < count; i++) {
    final directory = await Directory.systemTemp.createTemp('ditto_peer${i}_');
    final ditto = await Ditto.open(
      DittoConfig(
        // All peers of a group use the same database ID; give every group
        // that can run at the same time its own ID and port.
        databaseID: databaseID,
        persistenceDirectory: directory.path,
      ),
    );
    _peerStores.add((ditto, directory)); // closed by closeSyncedPeers()
    addTearDown(ditto.sync.stop); // frees the port for the next test
    ditto.setOfflineOnlyLicenseToken(licenseToken);
    ditto.updateTransportConfig((config) {
      config.setAllPeerToPeerEnabled(false); // no Bluetooth, LAN, or AWDL
      if (i == 0) {
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = port;
      } else {
        config.connect.tcpServers = {'127.0.0.1:$port'};
        // A device that only connects still listens on every interface, so
        // bind its listener to this machine: test peers stay off the network.
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = 0;
      }
    });
    // App setup after open, such as indexes. On SDK 5.2+, pass system
    // parameters in the DittoConfig above instead.
    await configure?.call(ditto);
    ditto.sync.start();
    peers.add(ditto);
  }
  await _waitUntil(() => peers.every(_isConnected));
  return peers;
}

/// Closes every peer that openSyncedPeers() opened. Register it once per file:
/// tearDownAll(closeSyncedPeers).
Future<void> closeSyncedPeers() async {
  for (final (ditto, directory) in _peerStores) {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }
  _peerStores.clear();
}

bool _isConnected(Ditto ditto) => ditto.presence.graph.remotePeers.isNotEmpty;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Stops sync on every peer, runs [writes] while the peers are disconnected,
/// then reconnects them, so the writes are concurrent.
Future<void> whileDisconnected(
  List<Ditto> peers,
  Future<void> Function() writes,
) async {
  for (final peer in peers) {
    peer.sync.stop();
  }
  await _waitUntil(() => peers.every((peer) => !_isConnected(peer)));
  await writes();
  for (final peer in peers) {
    peer.sync.start();
  }
  await _waitUntil(() => peers.every(_isConnected));
}

/// Waits until [query] returns the same rows on every peer and [until] holds
/// for them, then returns the rows.
Future<List<Map<String, dynamic>>> waitForConvergence(
  List<Ditto> peers,
  String query, {
  Map<String, dynamic> arguments = const {},
  bool Function(List<Map<String, dynamic>> rows)? until,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final results = <List<Map<String, dynamic>>>[];
    for (final peer in peers) {
      final result = await peer.store.execute(query, arguments: arguments);
      results.add(result.items.map((item) => item.value).toList());
    }
    final first = jsonEncode(results.first);
    final same = results.every((rows) => jsonEncode(rows) == first);
    if (same && (until == null || until(results.first))) return results.first;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Peers did not converge: $results', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = licenseToken.isEmpty ? 'Needs DITTO_LICENSE_TOKEN' : null;
  tearDownAll(closeSyncedPeers);

  test('concurrent edits of different line items both survive', () async {
    final [tablet, phone] = await openSyncedPeers(2);
    for (final peer in [tablet, phone]) {
      peer.sync.registerSubscription('SELECT * FROM orders');
    }
    await tablet.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': 'order-1',
          'items': {
            'item-1': {'productId': 'p1', 'quantity': 1},
          },
        },
      },
    );
    await waitForConvergence(
      [tablet, phone],
      'SELECT * FROM orders',
      until: (rows) => rows.length == 1,
    );

    // The code under test would be the app's repository functions.
    await whileDisconnected([tablet, phone], () async {
      await tablet.store.execute(
        'UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id',
        arguments: {'id': 'order-1'},
      );
      await phone.store.execute(
        'UPDATE orders SET items.`item-2` = :item WHERE _id = :id',
        arguments: {
          'id': 'order-1',
          'item': {'productId': 'p2', 'quantity': 1},
        },
      );
    });

    final rows = await waitForConvergence(
      [tablet, phone],
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': 'order-1'},
      until: (rows) => (rows.single['items'] as Map).length == 2,
    );
    final items = rows.single['items'] as Map;
    expect(items['item-1']['quantity'], 3);
    expect(items['item-2']['productId'], 'p2');
  }, skip: skip);
}
```

## Behavior Specific to the Flutter SDK

The behavior below is specific to `ditto_live` and was observed on the releases that each note names, mostly on macOS. Each item links to the observation with its setup and numbers, and most also to the section above that shows how to handle it. Review these notes when you upgrade the SDK (see [Upgrading from SDK 5.1](../../knowledge/upgrading.md)).

- **Note (SDK 5.2.0):** Observer rows of a query that does not project `_id` keep the `_id` with `registerObserver` but have none with `registerObserverV2` and `registerObserverWithSignalNext`, as with the other SDKs; on 5.1.0, all three kept it ([Diffing results in Flutter](#diffing-results-in-flutter)). See [On SDK 5.2.0, observer rows include _id only when it is projected, except with Flutter's registerObserver](../../knowledge/observations/observer-behavior.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected-except-with-flutters-registerobserver).
- **Note (SDK 5.1.0 and 5.2.0):** Calling `ditto.close()` while a transaction is open, also a read-only one, stops the isolate, and in an app the UI stops responding. Await open transactions first ([Closing Ditto in Flutter](#closing-ditto-in-flutter)). See [In Flutter, close() while a transaction is open stops the app's isolate](../../knowledge/observations/flutter-sdk.md#in-flutter-close-while-a-transaction-is-open-stops-the-apps-isolate).
- **Note (SDK 5.2.0):** `SyncSubscription` and `Transaction` objects that are garbage-collected after their instance was closed can stop the next `Ditto.open()` or `close()` in the process; avoid closing and reopening Ditto, keep subscription objects reachable, and close test stores only after the last test ([Subscriptions in Flutter](#subscriptions-in-flutter), [A local-store test helper in Flutter](#a-local-store-test-helper-in-flutter)). See [In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](../../knowledge/observations/flutter-sdk.md#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close).
- **Note (SDK 5.1.0 and 5.2.0):** Reading `queryArguments`, `queryArgumentsJsonString`, or `queryArgumentsCborBytes` from an element of `ditto.sync.subscriptions` ends the app when that subscription was registered without arguments ([Subscriptions in Flutter](#subscriptions-in-flutter)). See [In Flutter, reading the arguments of a listed subscription without arguments ends the app](../../knowledge/observations/flutter-sdk.md#in-flutter-reading-the-arguments-of-a-listed-subscription-without-arguments-ends-the-app).
- **Note (SDK 5.1.0 and 5.2.0):** A write that is still pending when `close()` is called can be stored although its `Future` fails with `StateError: Bad state: Ditto closed before execute() completed`; await every write before closing ([Closing Ditto in Flutter](#closing-ditto-in-flutter)). See [In Flutter, close() fails pending execute calls, also writes that it stores](../../knowledge/observations/flutter-sdk.md#in-flutter-close-fails-pending-execute-calls-also-writes-that-it-stores).
- **Note (SDK 5.1.0 and 5.2.0):** An observer registered with `onChange` (`registerObserver`, `registerObserverV2`, or `registerObserverWithSignalNext`) also queues every result in its `changes` stream, which keeps them in memory until something listens ([Store Observers in Flutter](#store-observers-in-flutter)). See [In Flutter, an observer whose changes stream nobody consumes keeps every result in memory](../../knowledge/observations/flutter-sdk.md#in-flutter-an-observer-whose-changes-stream-nobody-consumes-keeps-every-result-in-memory).
- **Note (SDK 5.1.0 and 5.2.0):** Code that a transaction callback starts, such as a timer or an observer listener, keeps the callback's zone, and its calls of `ditto.store.execute` throw `Transaction is no longer valid` even after the commit ([Transactions in Flutter](#transactions-in-flutter)). See [In Flutter, code started inside a transaction callback cannot call store.execute after the commit](../../knowledge/observations/flutter-sdk.md#in-flutter-code-started-inside-a-transaction-callback-cannot-call-storeexecute-after-the-commit).
- **Note (SDK 5.1.0 and 5.2.0):** A read-write transaction started inside another waits for the outer one, so an outer transaction that awaits it never ends; other combinations of read-only and read-write transactions do not wait ([Transactions in Flutter](#transactions-in-flutter)). See [In Flutter, a read-write transaction started inside another waits for the outer one](../../knowledge/observations/flutter-sdk.md#in-flutter-a-read-write-transaction-started-inside-another-waits-for-the-outer-one).
- **Note (SDK 5.1.0 and 5.2.0):** `ditto.store.execute` inside a transaction callback throws a `DittoException`; outside the callback, reads return at once and writes wait until the transaction ends ([Transactions in Flutter](#transactions-in-flutter)). See [In Flutter, store.execute inside a transaction callback throws, and outside it only writes wait](../../knowledge/observations/flutter-sdk.md#in-flutter-storeexecute-inside-a-transaction-callback-throws-and-outside-it-only-writes-wait).
- **Note (SDK 5.1.0):** `Ditto.open()` on a persistence directory that is already open may never complete. On 5.2.0 it fails after about a second with `File already locked`, and `Ditto.openSync()` fails in the same way on both releases ([One shared instance in Flutter](#one-shared-instance-in-flutter)). See [In Flutter, opening an open directory again fails within a second on SDK 5.2.0 and never completes on 5.1.0](../../knowledge/observations/flutter-sdk.md#in-flutter-opening-an-open-directory-again-fails-within-a-second-on-sdk-520-and-never-completes-on-510).
- **Note (SDK 5.1.0 and 5.2.0):** A `registerObserver` callback does not hold back the next result: `async` listeners overlap, and `await for` over `changes` processes every queued result. Use `registerObserverV2` or `registerObserverWithSignalNext` for slow work ([Backpressure in Flutter](#backpressure-in-flutter)). See [In Flutter, a slow async observer callback does not hold back the next result](../../knowledge/observations/flutter-sdk.md#in-flutter-a-slow-async-observer-callback-does-not-hold-back-the-next-result).
- **Note (SDK 5.1.0 and 5.2.0):** An exception in an observer callback goes to the zone's error handler and the observer keeps running, but a throwing `onChange` keeps its result out of `changes`, and a throw before `signalNext()` stops the observer ([Observer lifecycle in Flutter](#observer-lifecycle-in-flutter)). See [In Flutter, an exception thrown in an observer callback reaches the zone, and the observer keeps running](../../knowledge/observations/flutter-sdk.md#in-flutter-an-exception-thrown-in-an-observer-callback-reaches-the-zone-and-the-observer-keeps-running).
- **Note (SDK 5.1.0 and 5.2.0):** Observers and subscriptions whose references your code drops keep running; garbage collection never cancels them ([Observer lifecycle in Flutter](#observer-lifecycle-in-flutter), [Subscriptions in Flutter](#subscriptions-in-flutter)). See [In Flutter, observers and subscriptions whose references were dropped keep running](../../knowledge/observations/flutter-sdk.md#in-flutter-observers-and-subscriptions-whose-references-were-dropped-keep-running).
- **Note (SDK 5.1.0 and 5.2.0):** Every rule of the observer lifecycle table held: an observer without `onChange` starts at the first `listen`, `changes` accepts one listener, and `close()` does not end an `await for` loop over it ([Observer lifecycle in Flutter](#observer-lifecycle-in-flutter)). See [In Flutter, the observer lifecycle rules held on SDK 5.1.0 and 5.2.0](../../knowledge/observations/flutter-sdk.md#in-flutter-the-observer-lifecycle-rules-held-on-sdk-510-and-520).
- **Note (SDK 5.1.0 and 5.2.0):** Some Dart values change type: a `DateTime` is stored as a string, bytes come back as a `List`, a `BigInt` of 2^63 or more comes back as a `double` or as bytes, and `NaN`, infinity, and objects without `toCbor()` cannot be written ([Arguments and value types in Flutter](#arguments-and-value-types-in-flutter)). See [In Flutter, Dart values change type between writing and reading](../../knowledge/observations/flutter-sdk.md#in-flutter-dart-values-change-type-between-writing-and-reading).
- **Note (SDK 5.1.0 and 5.2.0):** Each read of `result.items` creates new items, whose `value` maps can be modified without effect on the store; results stay readable after `close()` ([Query results in Flutter](#query-results-in-flutter)). See [In Flutter, each read of result.items creates new items, and results stay readable after close](../../knowledge/observations/flutter-sdk.md#in-flutter-each-read-of-resultitems-creates-new-items-and-results-stay-readable-after-close).
- **Note (SDK 5.1.0 and 5.2.0):** Reads of `system:data_sync_info` on a device connected to a peer in another process completed in every run, unlike the JavaScript SDK ([Subscriptions in Flutter](#subscriptions-in-flutter)). See [In Flutter, reads of system:data_sync_info kept responding with a peer in another process](../../knowledge/observations/flutter-sdk.md#in-flutter-reads-of-systemdata_sync_info-kept-responding-with-a-peer-in-another-process).
- **Note (SDK 5.1.0 and 5.2.0):** Invalid DQL fails the `Future` of `execute`, but `registerObserver` and `registerSubscription` throw synchronously ([Executing DQL in Flutter](#executing-dql-in-flutter)). See [In Flutter, invalid DQL fails the Future of execute and throws when an observer or subscription is registered](../../knowledge/observations/flutter-sdk.md#in-flutter-invalid-dql-fails-the-future-of-execute-and-throws-when-an-observer-or-subscription-is-registered).
- **Note (SDK 5.1.0 and 5.2.0):** A subscription or observer registered without `arguments` reports `{}` as its `queryArguments`, where the JavaScript SDK reports `null` ([Subscriptions in Flutter](#subscriptions-in-flutter)). See [In Flutter, the subscriptions and observers that registration returns report their arguments](../../knowledge/observations/flutter-sdk.md#in-flutter-the-subscriptions-and-observers-that-registration-returns-report-their-arguments).
- **Note (SDK 5.1.0 and 5.2.0):** After `close()`, `execute` and `transaction` return a `Future` that fails with `DittoClosedException`, and the other calls throw it synchronously ([Closing Ditto in Flutter](#closing-ditto-in-flutter)). See [In Flutter, calls after close() throw DittoClosedException](../../knowledge/observations/flutter-sdk.md#in-flutter-calls-after-close-throw-dittoclosedexception).
- **Note (SDK 5.1.0 and 5.2.0):** `ditto.close()` resets `DittoLogger.customLogCallback` to `null` for the whole process; set it again before every `Ditto.open()` ([Logging in Flutter](#logging-in-flutter)). See [In Flutter, close() clears DittoLogger.customLogCallback](../../knowledge/observations/flutter-sdk.md#in-flutter-close-clears-dittologgercustomlogcallback).
- **Note (SDK 5.1.0 and 5.2.0):** `Ditto.version` returns a string such as `iOSF5.2.0_f6bdf023fa`, also on macOS, and `0.0.0_<hash>` until the first instance of the process is opened, also after `Ditto.init()`. Extract the `x.y.z` part, after opening, when you compare or report the version. See [In Flutter, Ditto.version includes a platform prefix and a build hash](../../knowledge/observations/flutter-sdk.md#in-flutter-dittoversion-includes-a-platform-prefix-and-a-build-hash).
