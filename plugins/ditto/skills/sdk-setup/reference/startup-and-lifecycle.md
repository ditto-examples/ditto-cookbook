# Ditto Startup and Lifecycle Reference

Requirements, initialization, authentication, system parameters, sync start and stop, and shutdown for Ditto SDK 5.2.0 (Flutter). Copied from `§ SDK Setup and Lifecycle` in `../../guide/reference/best-practices/setup-and-lifecycle.md`.

## Contents

- [Requirements](#requirements)
- [Flutter Web limitations](#flutter-web-limitations)
- [DittoConfig and connection modes](#dittoconfig-and-connection-modes)
- [Ditto.open, Ditto.openSync, and Ditto.init](#dittoopen-dittoopensync-and-dittoinit)
- [One instance per persistence directory](#one-instance-per-persistence-directory)
- [Complete app startup](#complete-app-startup)
- [Authentication](#authentication)
- [Applying system parameters](#applying-system-parameters)
- [Starting and stopping sync](#starting-and-stopping-sync)
- [App lifecycle](#app-lifecycle)
- [Resource cleanup and shutdown](#resource-cleanup-and-shutdown)
- [Platform differences](#platform-differences)

---

## Requirements

Ditto SDK 5.2.0 for Flutter (`ditto_live` 5.2.0) has the following requirements:

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

`§ Requirements`

## Flutter Web limitations

- Data is stored **in memory only** and is lost when the page reloads.
- Sync works **only over WebSocket** with Ditto Server. Peer-to-peer transports are not available, and `setOfflineOnlyLicenseToken()` and `setAllPeerToPeerEnabled()` have no effect.
- The in-browser store does not support indexes. Skip `CREATE INDEX` on the Web, for example with `if (!kIsWeb)` from `package:flutter/foundation.dart` (or `Ditto.currentPlatform != SupportedPlatform.web`).
- Only the default Flutter Web build mode is supported, and the development server must be restarted after source changes.
- The WebAssembly assets can be served from a CDN with `Ditto.init(wasmUrl: ..., wasmShimUrl: ...)`.
- Data at rest: in Flutter Web apps, data is kept in memory only and is not written to disk.

## DittoConfig and connection modes

A Ditto instance is created from an immutable `DittoConfig`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `databaseID` | `String?` | All-zero UUID | Your Database ID. It must be a valid UUID. Do not rely on `Ditto.open()` to reject an invalid value; check that no placeholder is left in your configuration. |
| `connect` | `DittoConfigConnect` | `DittoConfigConnectSmallPeersOnly()` | `DittoConfigConnectServer(url: ...)` or `DittoConfigConnectSmallPeersOnly(privateKey: ...)`. |
| `persistenceDirectory` | `String?` | `null` | `null` uses `ditto-<databaseID>` inside `Ditto.defaultRootDirectory`. A relative path is resolved against the application support directory (`getApplicationSupportDirectory()`). If you choose the path yourself, include the Database ID in it: in our testing, a directory written with one Database ID opened without an error with another, and its documents synced to the new database (development data mixing into production, for example). |
| `systemParameters` (SDK 5.2+) | `Map<String, Object>` | `{}` | System parameters applied before Ditto starts (see [Applying System Parameters](#applying-system-parameters)). |

**Default location (SDK 5.2+)**: `Ditto.defaultRootDirectory` now resolves to the application support directory instead of the documents directory; the release notes describe the move for desktop platforms. With `persistenceDirectory: null`, Ditto still finds a database in the previous default location after the upgrade. That fallback applies only to `null`. If your app passes a relative path, check on every platform you ship that an upgraded installation still opens its existing data before you release 5.2.

There are two connection modes:

| Mode | Use it when | Authentication | Encryption in transit |
|---|---|---|---|
| `DittoConfigConnectServer(url: ...)` | Devices sync through Ditto Server (and with each other) | Required: set an expiration handler and log in (see [Authentication](#authentication)) | TLS |
| `DittoConfigConnectSmallPeersOnly(privateKey: key)` | Devices sync only with each other using a shared key | Shared key: every peer that holds the key is trusted (no server) | TLS 1.3 |
| `DittoConfigConnectSmallPeersOnly()` | Local store tests, and development with an offline license token | **None**: any device with the SDK, the Database ID, and a license token can connect | **Do not rely on it**: the SDK documents it as unencrypted (see below) |

**✅ DO:**
- Copy the Server URL from the Ditto Portal exactly as shown. Do not build it from the Database ID.
- Use `DittoConfigConnectSmallPeersOnly(privateKey: ...)` with a provisioned key for production small-peers-only deployments. The key is a base64-encoded P-256 (prime256v1) private key in PKCS#8 DER format, and `Ditto.open()` throws if the key is not valid.
- Obtain an **offline license token** from Ditto for small-peers-only deployments and set it with `ditto.setOfflineOnlyLicenseToken(token)` before calling `ditto.sync.start()`.

**❌ DON'T:**
- Ship `DittoConfigConnectSmallPeersOnly()` without a `privateKey` to production. Peers do not authenticate each other in that mode: any device that runs the SDK with the same Database ID (and a valid offline license token) can connect, read, and write. The SDK's API reference describes the mode as unencrypted in transit. In our testing with SDK 5.1.0 over TCP, the traffic was TLS-wrapped, but no shared secret authenticated the peers, so treat it as unprotected.
- Hardcode the shared key in the app binary (see [security.md](security.md#small-peers-only-deployments)).

**Why:** In small-peers-only mode, `ditto.sync.start()` throws (`The operation failed because the Ditto instance is not yet activated`) until a valid offline license token has been set, regardless of whether a private key is used. An invalid token makes `setOfflineOnlyLicenseToken()` itself throw (`The license failed verification`). A peer without a valid token is invisible to the other peers. The local store works without a license, which is why tests can open Ditto without one as long as they do not start sync.

The provisioned small-peers-only example (`openProvisionedSmallPeer`) is in [security.md](security.md#small-peers-only-deployments).

`§ DittoConfig`

## Ditto.open, Ditto.openSync, and Ditto.init

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
  // without a key, does not authenticate peers; see DittoConfig above.
  return Ditto.openSync(const DittoConfig(databaseID: 'YOUR_DATABASE_ID'));
}
```

`§ Ditto.open, Ditto.openSync, and Ditto.init`

## One instance per persistence directory

Only one `Ditto` instance can use a persistence directory at a time, and only one app can use a database at the same time. In our testing with SDK 5.1.0 and 5.2.0, `Ditto.open()` on a directory that another process held (a second window of the app, an old process left behind by a development server, or a suspended process) failed after about one second with the error code `store/persistence-directory-locked`. The lock of a process that crashed did not remain: another process could open the directory at once and read every committed write. Open Ditto once at app start, share the instance (for example through your app's dependency injection or a service object), and close it only when the app no longer needs it.

> **Note (SDK 5.1.0):** In the Flutter SDK, calling `Ditto.open()` on a persistence directory that is already open may never complete instead of throwing. Instead of opening the directory again, share the existing instance.

**✅ DO:**
- Open Ditto once and pass the instance to the parts of the app that need it.
- Guard against concurrent opens by sharing a single in-flight `Future`.
- In debug builds, use a randomized `persistenceDirectory` to avoid lock conflicts after a Flutter hot restart, as described in the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter). Each hot restart then starts with an empty local store. Keep a fixed directory in release builds, where the local data must survive restarts. Hot reload works normally.

**❌ DON'T:**
- Open a new instance per screen or per request.
- Open the same directory twice, or reopen it before `close()` has completed.
- Read, write, or delete files inside the persistence directory yourself. To remove the local data, delete the whole directory after `close()` has completed.
- Copy a persistence directory to another device or installation while the original stays in use, for example by cloning a device image or an emulator snapshot, or by restoring a backup to a new device and keeping the old one.

> **Note (SDK 5.1.0 and 5.2.0):** The persistence directory holds the device's identity (its peer key) and its record of what it has synced with each peer, so a partial or copied directory breaks sync without an error. In our testing, a copied directory and the original, syncing through the same hub, never converged: new documents reached every device, but updates of existing documents from one of the two did not reach the others (in all nine runs), and each device showed its own updates, so neither could notice. A device that reopened its directory after only the `ditto_store` subdirectory had been deleted kept its peer key, and some of the documents that it created before sync started never reached the hub, while later writes did. A device whose whole directory had been deleted came back with a new peer key and synced everything.

To delete the local store on Flutter and JavaScript, which have no API for it, wait for `await ditto.close()` to complete, delete the whole persistence directory, and open Ditto again if the app still needs it. Swift and Kotlin have `deleteStore` (SDK 5.2+). **Note (SDK 5.1.0 and 5.2.0):** in our testing on macOS, deleting the directory while Ditto was open raised no error: reads and writes kept working on the deleted files, a second instance could open the same path because the lock file was gone too, and every write of the first instance was lost when it closed. The lock file is no sign of whether a directory is in use; it still held the process ID after a crash. Recent writes of a small store were only in the write-ahead log file (`db.sql-wal`), so do not back up or copy single files of the directory either.

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
// ❌ BAD: Every call opens the same directory again. The second open may
// never complete while the first instance is still open.
Future<List<Map<String, dynamic>>> loadOrders() async {
  final ditto = await Ditto.open(const DittoConfig(databaseID: 'YOUR_DATABASE_ID'));
  final result = await ditto.store.execute('SELECT * FROM orders');
  return result.items.map((item) => item.value).toList();
}
```

`§ One instance per persistence directory`

## Complete app startup

The following example shows the recommended order: initialize, configure logging, open with your system parameters, set the authentication handler, create indexes, register long-lived subscriptions, and start sync.

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
    // the same directory again while it is still open may never complete.
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

Step 5 creates one index as an example; see `§ Creating Indexes` for which indexes to create.

`§ Complete app startup`

## Authentication

With `DittoConfigConnectServer`, a device must authenticate before it can sync. Authentication is driven by an **expiration handler** that you register with `await ditto.auth.setExpirationHandler(...)`.

| Behavior | Details |
|---|---|
| When it is called | When the device has not authenticated yet, when credentials are about to expire, and when they have expired |
| `timeUntilExpiration` | `Duration.zero` means "not authenticated yet" or "already expired"; a positive value is the time left before expiry |
| Required? | Yes for server connections: `ditto.sync.start()` throws ("an authentication expiration handler has not yet been set") without it |
| What to do inside | Fetch a token from your backend and call `ditto.auth.login(token: ..., provider: ...)` |

`login()` returns an `AuthResponse`. **It does not throw when your authentication webhook rejects the token or the server is unreachable**: check `response.exception` (non-null on failure). It can still throw for other reasons, such as `DittoClosedException` after `ditto.close()`. `response.clientInfo` contains the optional `clientInfo` JSON returned by your webhook.

**✅ DO:**
- Set the handler with `await` before calling `ditto.sync.start()`.
- Fetch a fresh token from your backend inside the handler, so that refreshes also work.
- Check `response.exception` and report failures through logging or the UI.
- Catch errors from your own token code inside the handler.
- Use `Authenticator.developmentProvider` with the development token from the Ditto Portal (shown in some places as the "Online Playground" token) **only during development**.

**❌ DON'T:**
- Throw from the handler (including rethrowing `response.exception`). The handler's return type is `void`, so Ditto never receives the error and it becomes an unhandled asynchronous error. Log or report it instead.
- Ship the development provider or development token in a production build.
- Cache a single token for the lifetime of the app; the handler is called again when credentials expire.

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

**Why:** Credentials are issued by Ditto Server after your webhook validates the token (see [security.md](security.md#authentication-in-production)), and they expire after the `expirationSeconds` your webhook returns. The handler is the single place where the SDK asks your app for a new token, so it must be reliable and must not crash.

**Logging out**: `await ditto.auth.logout()` clears the credentials and **stops sync**. Call `ditto.sync.start()` again after the next successful login if the device should resume syncing. `ditto.auth.status` exposes `isAuthenticated` and `userID`.

To remove local data as part of logging out, pass a `cleanup` callback (SDK 5.2+): `await ditto.auth.logout(cleanup: (ditto) async { ... })`. It runs after sync has stopped, and `logout()` completes only after it finishes. After logout the instance may no longer write, except for `EVICT`, so the callback can evict sensitive documents. Evicted values can still be read from the database files (`§ Data at Rest`); to remove them for sure, delete the persistence directory after `close()`. Exceptions thrown by the callback are logged and do not reach the caller, so check the result yourself (for example with a `SELECT COUNT(*)`) when the cleanup must succeed. Concurrent `logout()` calls collapse into one, and only the first caller's `cleanup` runs.

`§ Authentication`

## Applying system parameters

System parameters change SDK behavior. **They are kept in memory only and are not persisted**: after the app restarts, or after closing and reopening Ditto, every parameter is back at its default value. There are two ways to set them:

| | `DittoConfig.systemParameters` (SDK 5.2+) | `ALTER SYSTEM SET ...` |
|---|---|---|
| When it applies | Before Ditto starts, as part of `Ditto.open()` | After `Ditto.open()` returns, while Ditto runs |
| Parameters that Ditto reads only at startup | Take effect | Are stored but have no effect (for example `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`) |
| Unknown name or wrong type | `Ditto.open()` fails with a `DittoException` (an `ArgumentError` for a value that Dart cannot represent) | The statement fails |
| Use it for | Every setting your app always needs | Changing a value while the app runs, for example during a support session |

In our testing with the JavaScript SDK 5.2.0, a parameter passed in the configuration was in effect when `Ditto.open()` returned, and lowercase names (`dql_strict_mode`) worked as well as uppercase ones.

**Environment variables**: a parameter can also be set before the process starts with the environment variable `DITTO_<NAME>`, which is the only way to pass startup-only parameters on SDK 5.1. Ditto reads the value as JSON: write booleans as lowercase `true` or `false`, numbers without quotes, and strings with their quotes (`DITTO_<NAME>='"value"'` in a shell). In our testing with SDK 5.1.0 and 5.2.0, a value that was not valid JSON (an unquoted string, `TRUE`, an empty value) or had the wrong type (`1` for a boolean, `"24"` for a number) was ignored with one log line, and Ditto started with the default without any error in the app. Check the value with `SHOW <name>` after the start.

**✅ DO:**
- Pass the settings your app always needs in `DittoConfig.systemParameters`, on every open. Keep the map in one place, next to the rest of your configuration.
- Use `ALTER SYSTEM` only for values you change while the app runs.
- Read the current value with `SHOW <parameter>` when you need to confirm a setting.

**❌ DON'T:**
- Run `ALTER SYSTEM` once (for example in a migration) and assume it stays in effect.
- Change parameters such as `DQL_STRICT_MODE` after sync has started or after queries and observers have run.

`DQL_STRICT_MODE` defaults to `false`. Set it only if your app deliberately opts into strict mode; see `§ Strict Mode` for the trade-offs.

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

**SDK 5.1**: `DittoConfig` has no `systemParameters`. Run `ALTER SYSTEM SET ...` every time you open Ditto, after `Ditto.open()` and before `ditto.sync.start()`, running queries, or registering observers (subscriptions may be registered first). Parameters that Ditto reads only at startup cannot be set this way.

To restore a default, use `ALTER SYSTEM RESET <parameter>`. To list everything, use `SHOW ALL` (optionally filtered, for example `SHOW ALL LIKE 'dql%'`). The parameters most relevant to app developers are listed in `§ System Parameters Reference`; others are described in the section that uses them.

`§ Applying System Parameters`

## Starting and stopping sync

- `ditto.sync.start()` and `ditto.sync.stop()` return `void`. Do not `await` them (`await ditto.sync.start()` is a compile error in Dart). `start()` throws if sync cannot start, for example when the expiration handler or the offline license token is missing. Calling `start()` while sync is active does nothing. <!-- lint-ignore -->
- `ditto.sync.isActive` tells you whether sync is running.
- After `stop()`, the local store remains fully usable; only network sync stops. `stop()` closes all connections right away, on both sides. Subscriptions stay registered, and changes made on either side while sync was stopped are exchanged after `start()`.
- Subscriptions can be registered before `start()` or while sync is stopped; they take effect when sync runs.

Start sync **after** the expiration handler is set (server connections) or the offline license token is set (small-peers-only), and after system parameters have been applied.

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

`§ Starting and Stopping Sync`

## App lifecycle

`sync.start()` and `sync.stop()` give you explicit control over when the device syncs. Background behavior depends on the platform:
- **iOS**: Background sync is best-effort and requires Bluetooth LE with the Bluetooth central and peripheral background modes enabled. Low Power Mode can make it less reliable.
- **Android**: To keep syncing while the app is in the background, declare Ditto's foreground service in `AndroidManifest.xml` as shown in the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter). The service starts and stops together with sync.

**✅ DO:**
- Keep the Ditto instance open while the app is in the background.
- Use `ditto.sync.stop()` and `ditto.sync.start()` only if your app must not sync in the background, and restart only the sync that you paused.

**❌ DON'T:**
- Call `ditto.close()` when the app moves to the background (`AppLifecycleState.paused`). `close()` is final for that instance: every later call on it throws `DittoClosedException`, and you would have to open a new instance and register all subscriptions and observers again.

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

`§ Starting and Stopping Sync`

## Resource cleanup and shutdown

Ditto objects hold native resources. Always release these objects explicitly; do not rely on garbage collection to cancel them.

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

To find what is still registered, `ditto.store.observers` (SDK 5.2+) returns the `StoreObserver`s registered with `registerObserver` that have not been cancelled (observers from `registerObserverV2` and `registerObserverWithSignalNext` are not included), and `ditto.store.attachmentFetchers` returns the active fetchers. A count that keeps growing while the user moves between screens points to an observer that is never cancelled.

`ditto.close()` behavior:
- **Idempotent**: calling it twice is safe. Use `ditto.isClosed` to check.
- **Stops sync** and releases observers, subscriptions, and other resources. Afterwards, observers and subscriptions report `isCancelled == true`, `cancel()` and `stop()` do nothing, and every other API call throws `DittoClosedException`.
- **Does not wait** for your pending work. In-flight `execute()` calls and transactions can fail with `DittoClosedException`, so await your own pending work before closing.
- **Does not wait for changes that are still being sent.** An awaited write is in the local store, but it may not have reached any other device yet. `ditto.sync.stop()` does not wait for them either. Such changes stay on the device and sync the next time it syncs.
- **Resets `DittoLogger.customLogCallback`** to `null` for the whole process. If you reopen Ditto, set it again after `Ditto.init()` and before `Ditto.open()` (see `§ Forwarding logs to your own pipeline`).
- **Does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`**: an `await for` loop over it does not end when Ditto closes, and `cancel()` does nothing once Ditto is closed. Cancel observers and your `StreamSubscription`s (or break out of the loop) before closing.

> **Note (SDK 5.1.0 and 5.2.0):** In our testing, a device connected to a hub wrote one document and then called `close()` or `sync.stop()`, exited, or was killed right after the write returned. The hub never received a 1 MB document this way, nor a 300 KB document over a slow link, and a 100-byte document arrived in most runs but not in all. When the device first waited until the hub's `synced_up_to_local_commit_id` reached the write's `commitID`, every write arrived (81 of 81 runs). A write that did not leave the device reached the hub when the device opened the same directory again, so it is lost only if the device never syncs again, for example because its store is deleted. Before you close Ditto at a point where data must reach another device (logout, the end of a shift, before deleting the local store), wait with a timeout until the write is confirmed, and tell the user if unsent changes remain:

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

**Isolates**: `Ditto` and `Store` cannot be sent to another isolate. Use the instance from the isolate that opened it. On native platforms, `store.execute()` already runs queries on a background isolate managed by the SDK, so you do not need your own isolate for that.

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

`§ Resource Cleanup and Shutdown`

## Platform differences

The concepts are the same on every platform, but some APIs behave differently. Keep these differences in mind when you port code or read samples for another SDK:

| Topic | Flutter | JavaScript | Swift | Kotlin |
|---|---|---|---|---|
| Create / open | `await Ditto.open(DittoConfig(...))` | `await Ditto.open(new DittoConfig(id, { mode: 'server', url }))`, or `new DittoConfig({ databaseID, connect, ... })` (SDK 5.2+); on the Web, call `await init()` first | `try await Ditto.open(config:)` | `DittoFactory.create(config)` |
| System parameters at open (SDK 5.2+) | `DittoConfig(systemParameters: {...})` | `systemParameters` in the `DittoConfig` options | `DittoConfig(..., systemParameters: [...])` | `DittoConfig(..., systemParameters = mapOf(...))` |
| Start sync | `ditto.sync.start()` (`void`, throws on failure) | `ditto.sync.start()` | `try ditto.sync.start()` | `ditto.sync.start()` (throws on failure) |
| Close | `await ditto.close()` | `await ditto.close()` | `Ditto.close()` (SDK 5.2+). In 5.1 there is no public `close()`: release all references, and the instance shuts down when deallocated | `ditto.close()` |
| Delete the local store (SDK 5.2+) | No API; evict data in `logout(cleanup:)` | No API | `Ditto.deleteStore(databaseID:persistenceDirectory:)` | `DittoFactory.deleteStore(databaseId, persistenceDirectory)` |
| Encryption at rest (SDK 5.2+) | Not available | Not available | `DittoConfig.encryptionKey` | `DittoConfig.encryptionKey` |
| Login failure | Returns `AuthResponse` with `exception`; does not throw | Returns a result with `error`; does not throw | Reported to the completion handler as `error` | **Throws** |
| Release observers and subscriptions | `cancel()` | `cancel()` | `cancel()` | `close()` |

The full table (observer backpressure, transactions) is in `§ Platform Differences`. Kotlin, Java, Swift, and C# stored some values incorrectly before SDK 5.2, and the stored data is not corrected by the upgrade; see `§ Known Issues in SDK 5.1.0`.
