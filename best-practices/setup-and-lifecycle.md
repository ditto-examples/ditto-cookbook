# SDK Setup and Lifecycle

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

**Flutter Web limitations**:
- Data is stored **in memory only** and is lost when the page reloads.
- Sync works **only over WebSocket** with Ditto Server. Peer-to-peer transports are not available, and `setOfflineOnlyLicenseToken()` and `setAllPeerToPeerEnabled()` have no effect.
- The in-browser store does not support indexes. Skip `CREATE INDEX` on the Web, for example with `if (!kIsWeb)` from `package:flutter/foundation.dart` (or `Ditto.currentPlatform != SupportedPlatform.web`).
- Only the default Flutter Web build mode is supported, and the development server must be restarted after source changes.
- The WebAssembly assets can be served from a CDN with `Ditto.init(wasmUrl: ..., wasmShimUrl: ...)`.

## Initializing Ditto

### DittoConfig

A Ditto instance is created from an immutable `DittoConfig`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `databaseID` | `String?` | All-zero UUID | Your Database ID. It must be a valid UUID. Do not rely on `Ditto.open()` to reject an invalid value; check that no placeholder is left in your configuration. Peers with different Database IDs never see each other or sync, even over an explicit TCP connection, so a mix of development and production builds on one network does not sync (in our testing; see [Devices with different Database IDs do not sync](../knowledge/observations/persistence-directory.md#devices-with-different-database-ids-do-not-sync)). |
| `connect` | `DittoConfigConnect` | `DittoConfigConnectSmallPeersOnly()` | `DittoConfigConnectServer(url: ...)` or `DittoConfigConnectSmallPeersOnly(privateKey: ...)`. |
| `persistenceDirectory` | `String?` | `null` | `null` uses `ditto-<databaseID>` inside `Ditto.defaultRootDirectory`. A relative path is resolved against the application support directory (`getApplicationSupportDirectory()`). If you choose the path yourself, include the Database ID in it: in our testing, a directory written with one Database ID opened without an error with another, and its documents synced to the new database (see [A directory written with another Database ID opens and syncs its documents](../knowledge/observations/persistence-directory.md#a-directory-written-with-another-database-id-opens-and-syncs-its-documents)). |
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
- Ship `DittoConfigConnectSmallPeersOnly()` without a `privateKey` to production. Peers do not authenticate each other in that mode: any device that runs the SDK with the same Database ID (and a valid offline license token) can connect, read, and write. The SDK's API reference describes the mode as unencrypted in transit; in our testing over TCP, the traffic was TLS-wrapped, but no shared secret authenticated the peers, so treat it as unprotected (see [Shared keys must match, and traffic is TLS-wrapped without a key](../knowledge/observations/connections-and-presence.md#shared-keys-must-match-and-traffic-is-tls-wrapped-without-a-key)).
- Hardcode the shared key in the app binary (see [Small-Peers-Only Deployments](security.md#small-peers-only-deployments)).

**Why:** In small-peers-only mode, `ditto.sync.start()` throws (`The operation failed because the Ditto instance is not yet activated`) until a valid offline license token has been set, regardless of whether a private key is used. An invalid token makes `setOfflineOnlyLicenseToken()` itself throw (`The license failed verification`). A peer without a valid token is invisible to the other peers. The local store works without a license, which is why tests can open Ditto without one as long as they do not start sync.

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

For generating, distributing, and storing the shared key, see [Small-Peers-Only Deployments](security.md#small-peers-only-deployments).

### Ditto.open, Ditto.openSync, and Ditto.init

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

### One instance per persistence directory

Only one `Ditto` instance can use a persistence directory at a time, and only one app can use a database at the same time. `Ditto.open()` on a directory that another process holds (a second window of the app, an old process left behind by a development server, or a suspended process) fails with the error code `store/persistence-directory-locked`, after about one second in our testing; the lock of a process that crashed did not remain (see [A directory locked by another process fails to open after about 1 second](../knowledge/observations/persistence-directory.md#a-directory-locked-by-another-process-fails-to-open-after-about-1-second)). Open Ditto once at app start, share the instance (for example through your app's dependency injection or a service object), and close it only when the app no longer needs it.

> **Note (SDK 5.1.0):** In the Flutter SDK, calling `Ditto.open()` on a persistence directory that is already open may never complete instead of throwing. Instead of opening the directory again, share the existing instance. (In the JavaScript SDK 5.0.3 to 5.2.0, the second `Ditto.open()` failed within 10 seconds with `File already locked, ... Multiple Ditto instances cannot run at the same time within the same working directory.`; see [In JavaScript, opening an open directory again fails](../knowledge/observations/persistence-directory.md#in-javascript-opening-an-open-directory-again-fails).)

**✅ DO:**
- Open Ditto once and pass the instance to the parts of the app that need it.
- Guard against concurrent opens by sharing a single in-flight `Future`.
- In debug builds, use a randomized `persistenceDirectory` to avoid lock conflicts after a Flutter hot restart, as described in the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter). Each hot restart then starts with an empty local store. Keep a fixed directory in release builds, where the local data must survive restarts. Hot reload works normally.

**❌ DON'T:**
- Open a new instance per screen or per request.
- Open the same directory twice, or reopen it before `close()` has completed.
- Read, write, or delete files inside the persistence directory yourself. To remove the local data, delete the whole directory after `close()` has completed.
- Copy a persistence directory to another device or installation while the original stays in use, for example by cloning a device image or an emulator snapshot, or by restoring a backup to a new device and keeping the old one.

> **Note (SDK 5.1.0 and 5.2.0):** The persistence directory holds the device's identity (its peer key) and its record of what it has synced with each peer, so a partial or copied directory breaks sync without an error. In our testing, a copied directory and its original, running at the same time, never converged, and neither device could notice (see [A copied directory and its original never converge](../knowledge/observations/persistence-directory.md#a-copied-directory-and-its-original-never-converge)); a device whose `ditto_store` subdirectory alone had been deleted kept its peer key, and some documents that it created before sync started never reached other devices (see [Deleting only ditto_store keeps the peer key and loses some writes](../knowledge/observations/persistence-directory.md#deleting-only-ditto_store-keeps-the-peer-key-and-loses-some-writes)). A device whose whole directory had been deleted came back with a new peer key and synced everything.
>
> The problem is running both copies. A copy that replaces the original, and a device that goes back to an older copy of its own directory, synced normally in our testing (see [A copy that replaces the original syncs normally](../knowledge/observations/persistence-directory.md#a-copy-that-replaces-the-original-syncs-normally) and [Restoring an older copy of a directory loses nothing](../knowledge/observations/persistence-directory.md#restoring-an-older-copy-of-a-directory-loses-nothing)). If both have run, close one of them and delete its whole directory, so that it syncs again with a new peer key; changes that only that device wrote while both ran may not come back.

To delete the local store on Flutter and JavaScript, which have no API for it, wait for `await ditto.close()` to complete, delete the whole persistence directory, and open Ditto again if the app still needs it. Swift and Kotlin have `deleteStore` (SDK 5.2+). **Note (SDK 5.1.0 and 5.2.0):** in our testing on macOS, deleting the directory while Ditto was open raised no error, a second instance could then open the same path, and the first instance's writes were lost when it closed (see [Deleting the directory while Ditto is open loses later writes](../knowledge/observations/persistence-directory.md#deleting-the-directory-while-ditto-is-open-loses-later-writes)). The lock file is no sign of whether a directory is in use, and recent writes of a small store can be only in the write-ahead log file (`db.sql-wal`; see [After close(), a small store keeps its values in the write-ahead log](../knowledge/observations/persistence-directory.md#after-close-a-small-store-keeps-its-values-in-the-write-ahead-log)), so do not back up or copy single files of the directory either.

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

### Complete app startup

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

Step 5 creates one index as an example; see [Creating Indexes](indexing-and-performance.md#creating-indexes) for which indexes to create.

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

**Why:** Credentials are issued by Ditto Server after your webhook validates the token (see [Authentication in Production](security.md#authentication-in-production)), and they expire after the `expirationSeconds` your webhook returns. The handler is the single place where the SDK asks your app for a new token, so it must be reliable and must not crash.

**Logging out**: `await ditto.auth.logout()` clears the credentials and **stops sync**. Call `ditto.sync.start()` again after the next successful login if the device should resume syncing. `ditto.auth.status` exposes `isAuthenticated` and `userID`.

To remove local data as part of logging out, pass a `cleanup` callback (SDK 5.2+): `await ditto.auth.logout(cleanup: (ditto) async { ... })`. It runs after sync has stopped, and `logout()` completes only after it finishes. After logout the instance may no longer write, except for `EVICT`, so the callback can evict sensitive documents. Evicted values can still be read from the database files (see [Data at Rest](security.md#data-at-rest) and [Deleted and evicted values remain in the database files](../knowledge/observations/storage-and-deletion.md#deleted-and-evicted-values-remain-in-the-database-files)); to remove them for sure, delete the persistence directory after `close()` (see [Deleting the directory after close() leaves no data behind](../knowledge/observations/persistence-directory.md#deleting-the-directory-after-close-leaves-no-data-behind)). Exceptions thrown by the callback are logged and do not reach the caller, so check the result yourself (for example with a `SELECT COUNT(*)`) when the cleanup must succeed. Concurrent `logout()` calls collapse into one, and only the first caller's `cleanup` runs.

## Applying System Parameters

System parameters change SDK behavior. **They are kept in memory only and are not persisted**: after the app restarts, or after closing and reopening Ditto, every parameter is back at its default value. There are two ways to set them:

| | `DittoConfig.systemParameters` (SDK 5.2+) | `ALTER SYSTEM SET ...` |
|---|---|---|
| When it applies | Before Ditto starts, as part of `Ditto.open()` | After `Ditto.open()` returns, while Ditto runs |
| Parameters that Ditto reads only at startup | Take effect | Are stored but have no effect (for example `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`) |
| Unknown name or wrong type | `Ditto.open()` fails with a `DittoException` (an `ArgumentError` for a value that Dart cannot represent) | The statement fails |
| Use it for | Every setting your app always needs | Changing a value while the app runs, for example during a support session |

In our testing with the JavaScript SDK 5.2.0, a parameter passed in the configuration was in effect when `Ditto.open()` returned, and lowercase names (`dql_strict_mode`) worked as well as uppercase ones (see [System parameters passed in DittoConfig take effect when Ditto.open returns](../knowledge/observations/configuration-and-diagnostics.md#system-parameters-passed-in-dittoconfig-take-effect-when-dittoopen-returns)).

**Environment variables**: a parameter can also be set before the process starts with the environment variable `DITTO_<NAME>`, which is the only way to pass startup-only parameters on SDK 5.1 (see [DITTO_ environment variables set system parameters at startup](../knowledge/observations/configuration-and-diagnostics.md#ditto_-environment-variables-set-system-parameters-at-startup)). Ditto reads the value as JSON: write booleans as lowercase `true` or `false`, numbers without quotes, and strings with their quotes (`DITTO_<NAME>='"value"'` in a shell). A value that is not valid JSON or has the wrong type is ignored with one log line, and Ditto starts with the default without any error in the app (in our testing; see [Environment variable values are read as JSON and ignored when invalid](../knowledge/observations/configuration-and-diagnostics.md#environment-variable-values-are-read-as-json-and-ignored-when-invalid)), so check the value with `SHOW <name>` after the start. Do not use the `DITTO_` prefix for your app's own settings: Ditto logs a warning at every start for each such variable that names no system parameter.

**✅ DO:**
- Pass the settings your app always needs in `DittoConfig.systemParameters`, on every open. Keep the map in one place, next to the rest of your configuration.
- Use `ALTER SYSTEM` only for values you change while the app runs.
- Read the current value with `SHOW <parameter>` when you need to confirm a setting.

**❌ DON'T:**
- Run `ALTER SYSTEM` once (for example in a migration) and assume it stays in effect.
- Change parameters such as `DQL_STRICT_MODE` after sync has started or after queries and observers have run.

`DQL_STRICT_MODE` defaults to `false`. Set it only if your app deliberately opts into strict mode; see [Strict Mode](data-modeling.md#strict-mode) for the trade-offs.

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

To restore a default, use `ALTER SYSTEM RESET <parameter>`. To list everything, use `SHOW ALL` (optionally filtered, for example `SHOW ALL LIKE 'dql%'`; the filter needs SDK 5.1+; see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)). The parameters most relevant to app developers are listed in [System Parameters Reference](../knowledge/system-reference.md#system-parameters-reference); others are described in the section that uses them.

## Starting and Stopping Sync

- `ditto.sync.start()` and `ditto.sync.stop()` return `void`. Do not `await` them (`await ditto.sync.start()` is a compile error in Dart). `start()` throws if sync cannot start, for example when the expiration handler or the offline license token is missing. Calling `start()` while sync is active does nothing. <!-- lint-ignore -->
- `ditto.sync.isActive` tells you whether sync is running.
- After `stop()`, the local store remains fully usable; only network sync stops. `stop()` closes all connections right away, on both sides, and subscriptions stay registered; changes made on either side while sync was stopped are exchanged after `start()` (in our testing; see [Starting and stopping sync behaved as documented](../knowledge/observations/subscriptions-and-replication.md#starting-and-stopping-sync-behaved-as-documented)).
- Subscriptions can be registered before `start()` or while sync is stopped; they take effect when sync runs.
- A short pause catches up quickly while the network is up: in our testing, devices that repeatedly stopped sync for 0.5 to 2 seconds had the latest values within tens of milliseconds after `start()`, and the devices that kept syncing were barely delayed (see [Presence callbacks stay at about one per second while peers come and go](../knowledge/observations/connections-and-presence.md#presence-callbacks-stay-at-about-one-per-second-while-peers-come-and-go)). After a real network outage, add the time until the outage is noticed (see [Presence](#presence) and [A silent network outage removes a peer after about 7 seconds](../knowledge/observations/connections-and-presence.md#a-silent-network-outage-removes-a-peer-after-about-7-seconds)).
- When many devices start sync at once with changes they made offline, staggering the starts spreads the work: in our testing, with 20 devices started half a second apart, new documents kept reaching the devices that had already synced within about 0.1 seconds, but all devices agreed only after the last one had started, and the hub did the same total work (see [Convergence after simultaneous reconnects grew faster than the number of devices](../knowledge/observations/subscriptions-and-replication.md#convergence-after-simultaneous-reconnects-grew-faster-than-the-number-of-devices) and [Scope subscriptions to what the device needs](sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs)).

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

**App lifecycle**: `sync.start()` and `sync.stop()` give you explicit control over when the device syncs. Background behavior depends on the platform:
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

## Resource Cleanup and Shutdown

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
- **Does not wait** for your pending work in Flutter. In-flight `execute()` calls and transactions can fail with `DittoClosedException`, so await your own pending work before closing. (The JavaScript SDK differs: in our testing with 5.0.3 to 5.2.0, `close()` waited for running `execute()` calls and transactions, also for writes started right after `close()` was called; see [In JavaScript, close() completes pending writes](../knowledge/observations/transaction-behavior.md#in-javascript-close-completes-pending-writes) and [In JavaScript, close() waits for open transactions](../knowledge/observations/transaction-behavior.md#in-javascript-close-waits-for-open-transactions); see [Platform Differences](../knowledge/platform-differences.md).)
- **Does not wait for changes that are still being sent.** An awaited write is in the local store, but it may not have reached any other device yet. `ditto.sync.stop()` does not wait for them either. Such changes stay on the device and sync the next time it syncs.
- **Resets `DittoLogger.customLogCallback`** to `null` for the whole process. If you reopen Ditto, set it again after `Ditto.init()` and before `Ditto.open()` (see [Forwarding logs to your own pipeline](logging-and-observability.md#forwarding-logs-to-your-own-pipeline)).
- **Does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`**: an `await for` loop over it does not end when Ditto closes, and `cancel()` does nothing once Ditto is closed. Cancel observers and your `StreamSubscription`s (or break out of the loop) before closing.

> **Note (SDK 5.1.0 and 5.2.0):** An awaited write is in the local store, but `close()`, `sync.stop()`, and ending the app do not wait until it has been sent. In our testing, a 1 MB document written right before any of them never reached the hub, and a 100-byte document did in most runs but not in all; when the device first waited until the hub's `synced_up_to_local_commit_id` reached the write's `commitID`, every write arrived (see [A write made right before close or stop may not leave the device](../knowledge/observations/subscriptions-and-replication.md#a-write-made-right-before-close-or-stop-may-not-leave-the-device)). A write that did not leave the device is sent the next time it syncs, so it is lost only if the device never syncs again, for example because its store is deleted. Before you close Ditto at a point where data must reach another device (logout, the end of a shift, before deleting the local store), wait with a timeout until the write is confirmed, and tell the user if unsent changes remain:

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

## Transport Configuration

A new Ditto instance enables the peer-to-peer transports that are stable on the current platform (Bluetooth LE, LAN, and AWDL or Wi-Fi Aware). When you connect with `DittoConfigConnectServer`, the Server URL is used automatically; you do not need to add it to the transport configuration.

`TransportConfig` is immutable. Change it with `ditto.updateTransportConfig()`, which gives you a builder initialized with the current configuration.

**✅ DO:**
- Use `updateTransportConfig()` and change only the settings you need.
- Enable or disable all peer-to-peer transports at once with `setAllPeerToPeerEnabled()`, or individual transports through `peerToPeer`.
- Observe transport conditions to detect missing permissions or disabled radios.

**❌ DON'T:**
- Build a `TransportConfig()` from scratch and assign it: a new `TransportConfig` has **every transport disabled**, including the peer-to-peer transports that a default instance enables.
- Treat `global.syncGroup` as a security boundary. It is an optimization only: in our testing, devices in different sync groups still synced when they were connected explicitly (see [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)).

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

> **Note (SDK 5.1.0 and 5.2.0):** A device accepts a limited number of connections per transport. For TCP, the limit is 6 by default (system parameter `MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In our testing with a TCP hub and eight clients, the hub accepted six, and the remaining two received no data at all; no API reported this, and only the log showed a `WARN` line, `failed to connect to peer error=... at capacity for this transport` (see [A device accepts six TCP connections by default](../knowledge/observations/connections-and-presence.md#a-device-accepts-six-tcp-connections-by-default)).
>
> On 5.2.0, a device also counts the connections that it opened itself when it decides whether to accept another one (the 5.2.0 release notes describe this as counting accepted and outgoing LAN connections together). In our testing, a hub that also connected to two other devices dropped two of its six clients on 5.2.0, and a relay that connected to an upstream hub accepted only five clients (see [SDK 5.2.0 counts outgoing connections toward the TCP limit](../knowledge/observations/connections-and-presence.md#sdk-520-counts-outgoing-connections-toward-the-tcp-limit)). Outgoing connections themselves are not limited (see [Outgoing TCP connections are not limited](../knowledge/observations/connections-and-presence.md#outgoing-tcp-connections-are-not-limited)), and the default is still 6.
>
> A client that the hub did not accept appears in no device's presence graph, so presence shows correctly that it is not connected (see [The presence graph includes indirect peers and all of their connections](../knowledge/observations/connections-and-presence.md#the-presence-graph-includes-indirect-peers-and-all-of-their-connections)). Configure each TCP link in one direction only (the clients list the hub): two devices that listed each other in `connect.tcpServers` kept two TCP connections, and when every device lists every other device, a mesh of seven or more devices on 5.2.0 is not fully connected: each device kept 3 to 7 direct connections and reached the others through them (in our testing; see [On SDK 5.2.0, a full TCP mesh of seven or more devices is not fully connected](../knowledge/observations/connections-and-presence.md#on-sdk-520-a-full-tcp-mesh-of-seven-or-more-devices-is-not-fully-connected)). Count devices with `remotePeers`, not with direct connections.
>
> When every device lists every other device in `connect.tcpServers`, a device on 5.2.0 kept 3 to 7 direct connections (6 to 9 TCP connections), so a mesh of seven or more devices was not fully connected. Every device still listed all the others in `remotePeers`, and changes reached every device within 24 to 80 ms through the others. On 5.1.0, devices kept up to 15 TCP connections, many of them duplicates. Count devices with `remotePeers`, not with direct connections.
>
> `MESH_CHOOSER_AT_CAPACITY_ACTION` decides what a full hub does when another client arrives. With the default, the extra client never connected. According to the 5.2.0 release notes, the settings that drop the oldest or the newest peer wait until the new peer has finished connecting. In our testing with those settings, every client received data, but the hub kept replacing connections about every 5 seconds (see [At-capacity actions admit extra clients but keep replacing connections](../knowledge/observations/connections-and-presence.md#at-capacity-actions-admit-extra-clients-but-keep-replacing-connections)). Raise `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` instead.
>
> If more than six devices connect to one hub, raise the limit **on the hub** so that it is in effect **before** `ditto.sync.start()`: pass it in `DittoConfig.systemParameters` (SDK 5.2+), or on SDK 5.1 run `ALTER SYSTEM` after `Ditto.open` and before `ditto.sync.start()`. In our testing, raising it after sync had started did not admit the rejected clients, even after 60 seconds (see [Raising the TCP limit takes effect only before sync starts](../knowledge/observations/connections-and-presence.md#raising-the-tcp-limit-takes-effect-only-before-sync-starts)).

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

> **Note (SDK 5.1.0 and 5.2.0):** A device that only connects also accepts connections. In our testing with the JavaScript SDK on macOS, a device with only `connect.tcpServers` set listened for TCP on all interfaces at a free port, and another device could connect to it and sync (see [A device that only connects also listens for TCP connections](../knowledge/observations/connections-and-presence.md#a-device-that-only-connects-also-listens-for-tcp-connections)). To accept no TCP connections from other devices, enable `listen.tcp` with `interfaceIP` set to `127.0.0.1` (`port` 0 picks a free port). Only devices with the same Database ID and valid credentials can sync, so this matters most for small-peers-only deployments without a shared key and for network reviews.

**Hub load**: the CPU that a hub spends on each change grows with the number of devices connected to it, even when no other device subscribes to the changed document. In our testing on a 14-core Mac, one change cost the hub at most about 6 ms of CPU with one client and about 40 ms with 30 clients, and 30 clients that each wrote 5 times a second used about 2.6 cores (see [Hub CPU per change grows with the number of connected devices](../knowledge/observations/performance-measurements.md#hub-cpu-per-change-grows-with-the-number-of-connected-devices)). Before you use a mobile device as a hub, estimate the number of clients and how often they write, and write frequently changing values (positions, sensor readings) less often or in batches.

**Replacing a hub**: a new, empty hub device recovers the data from its clients, including their tombstones, so deleted documents stay deleted (until the tombstones are reaped, see [Tombstone TTL and reaping](deletion-and-storage.md#tombstone-ttl-and-reaping)). Documents that only the old hub held are not recovered (in our testing; see [A new, empty hub recovers the data from its clients](../knowledge/observations/subscriptions-and-replication.md#a-new-empty-hub-recovers-the-data-from-its-clients)). Back up data that only the hub writes, or let a client subscribe to it.

Changes of `connect.tcpServers` and of the TCP listener take effect while sync is running, without `sync.stop()` and `start()`: in our testing, a device connected or disconnected within about 50 to 150 ms (see [TCP targets and listeners change while sync runs](../knowledge/observations/connections-and-presence.md#tcp-targets-and-listeners-change-while-sync-runs)). System parameters such as `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` are different: raising the limit after sync had started had no effect.

A device that loses a TCP connection, or fails to connect, tries again after `connect.retryInterval` (5 seconds by default): in our testing, clients reconnected to a restarted hub about 4 seconds after it was open again with the default, and about 1.1 seconds with an interval of 1 second (see [A lost TCP connection is retried at the retry interval](../knowledge/observations/connections-and-presence.md#a-lost-tcp-connection-is-retried-at-the-retry-interval)). A shorter interval suits devices that must stay connected to a hub, such as the terminals of a store.

Configuration changes are applied asynchronously while sync is running, and invalid values do not throw: an invalid `connect.tcpServers` entry or listen address only produces a log line (for example `Failed to start TCP server error=Bind address could not be parsed`). You can also point devices at a known peer with the `TRANSPORTS_DISCOVERED_PEERS` system parameter, which can be set before or after `ditto.sync.start()` and is validated (`type` is optional and must be `'force'` or `'candidate'`). It works only while the LAN transport (`peerToPeer.lan`) is enabled on the device that sets it, which is the default; with peer-to-peer transports disabled, the value is stored but nothing connects, so use `connect.tcpServers` instead. Like every system parameter, it is not persisted: pass a fixed address in `DittoConfig.systemParameters` (SDK 5.2+), or set it with `ALTER SYSTEM` after each open, for example when the address is discovered at run time:

```dart
Future<void> connectToKnownPeer(Ditto ditto) async {
  await ditto.store.execute(
    "ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS = [{'address': 'tcp://192.168.1.10:4040', 'type': 'force'}]",
  );
}
```

**WebSocket sync between Small Peers** (accepting WebSocket connections on the HTTP listener) is **off by default** (`listen.http.websocketSync = false`). Enable it only when you need it and configure TLS (`tlsKeyPath` and `tlsCertificatePath`); without them the listener uses plain HTTP.

Connections that a hub accepts over WebSocket do not count toward its TCP limit. In our testing with SDK 5.0.3, 5.1.0, and 5.2.0, a Small Peer hub that accepted WebSocket connections synced with all of 30 clients, while over TCP it served six, and with its TCP limit lowered to 2, it still served 8 WebSocket clients next to 2 TCP clients (see [WebSocket connections to a Small Peer hub do not count toward the TCP limit](../knowledge/observations/connections-and-presence.md#websocket-connections-to-a-small-peer-hub-do-not-count-toward-the-tcp-limit)). This is an alternative to raising `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` for hubs with more clients, with limits of its own: Ditto does not document a limit for WebSocket connections, we tested at most 30 clients on one machine without TLS, and a WebSocket connection that stops responding takes about 15 seconds to be dropped, against about 7 for TCP (see [Key Characteristics](../knowledge/understanding-ditto.md#key-characteristics) and [Each device sends over one of two connections and waits when it stalls](../knowledge/observations/connections-and-presence.md#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)). Test the number of devices you plan before you rely on it.

### Diagnosing transport problems (SDK 5.1+)

Because configuration changes do not throw, `ditto.observeTransportConditions()` is the way to see why a transport is not working: missing Bluetooth permissions, Bluetooth or Wi-Fi turned off, no BLE hardware, the app being in the background, mDNS or TCP listen failures, and so on. Call `stop()` on the returned observer when you no longer need it.

On Android, `DittoSyncPermissions` reports which runtime permissions Ditto needs and which are missing. It returns empty lists on other platforms. Request the permissions with a package such as `permission_handler`. Since SDK 5.2, `requiredPermissions()` and `missingPermissions()` cover only the generally available transports; the permissions for multicast are returned separately (see [Multicast (Beta) (SDK 5.1+)](#multicast-beta-sdk-51)).

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

### Multicast (Beta) (SDK 5.1+)

Multicast is an opt-in transport that sends each update once to a multicast group instead of once per connection, which reduces connection overhead in dense deployments. It is a private beta feature: **use it only in coordination with Ditto support**. It is configured through `peerToPeer.multicastBeta` and requires additional platform entitlements and permissions (for example the multicast entitlement on iOS and `CHANGE_WIFI_MULTICAST_STATE` on Android). It is not available on the Web or on Windows, and changes made while sync is active take effect only after sync is stopped and started again. On Android with SDK 5.2+, get its permissions with `await DittoSyncPermissions().requiredMulticastPermissions()` and check them with `missingPermissions(multicastPermissions)`; `requiredPermissions()` no longer includes them.

## Presence

`ditto.presence` shows which peers this device can see and how it is connected to them, which is useful for connection indicators and diagnostics.

- `ditto.presence.observe((graph) { ... })` returns a `PresenceObserver`. The callback is called with the current graph shortly after `observe()` returns (asynchronously), and again whenever peers appear, disappear, or change their connections. Updates are batched: in our testing, callbacks arrived about once per second, also while many peers kept coming and going, so a change reached the callback within about 1 second and one callback can cover several changes (see [Presence reports a joining peer after about 1.2 seconds](../knowledge/observations/connections-and-presence.md#presence-reports-a-joining-peer-after-about-12-seconds) and [Presence callbacks stay at about one per second while peers come and go](../knowledge/observations/connections-and-presence.md#presence-callbacks-stay-at-about-one-per-second-while-peers-come-and-go)). Show a connection state only after it has held for a few seconds, not the raw count of `remotePeers`, which swings while peers come and go. The callback is also called with an unchanged graph, so compare the graph with the previous one before you rebuild the UI. A peer in the graph is not necessarily up to date: over a slow link, a peer that was transferring a large attachment stayed in the graph while other changes waited behind the transfer (see [Slow links keep the connection and the presence entry](../knowledge/observations/connections-and-presence.md#slow-links-keep-the-connection-and-the-presence-entry)). Two connections to a peer in the graph do not mean that sync continues when one of them stalls (see [Each device sends over one of two connections and waits when it stalls](../knowledge/observations/connections-and-presence.md#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)). Call `stop()` on the observer when you no longer need it.
- `graph.localPeer` describes this device, and `graph.remotePeers` is a `Set<Peer>` of the other known peers, including peers that are reachable only through other peers. Each `Peer` has `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections`, and `peerMetadata`. To tell direct neighbors apart, check whether one of a peer's `connections` has this device's `peerKey` as `peer1` or `peer2`: a remote peer's `connections` lists all of that peer's connections, not only the one to this device. `connectionType` has no TCP value; TCP connections, including those to a hub, are reported as `accessPoint` (in our testing with the JavaScript SDK; see [The presence graph includes indirect peers and all of their connections](../knowledge/observations/connections-and-presence.md#the-presence-graph-includes-indirect-peers-and-all-of-their-connections)).
- A peer that stops responding without closing its connection stays in the graph for several seconds: in our testing over TCP, about 7 seconds after the network went silent, while a shorter outage was not noticed at all, and about 9 seconds for a suspended process; a process that ended disappeared at once (see [A silent network outage removes a peer after about 7 seconds](../knowledge/observations/connections-and-presence.md#a-silent-network-outage-removes-a-peer-after-about-7-seconds) and [A suspended device leaves the presence graph after about 9 seconds](../knowledge/observations/connections-and-presence.md#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds)). Other transports, such as Bluetooth LE, may take a different time; expect a connection indicator to lag by this much.
- `ditto.presence.graph` returns the current graph once, without observing.
- `ditto.presence.peerMetadata` sets metadata for this device (a JSON object of at most 4096 bytes when encoded; larger values throw). It reaches every peer in the mesh, but a peer that has just appeared can show empty `peerMetadata` until its metadata arrives. Setting it again replaces the whole object; keys are not merged. Changes reach other peers about once per second, as the value current at that moment, so intermediate values are skipped (in our testing; see [Peer metadata changes reach other peers about once per second](../knowledge/observations/connections-and-presence.md#peer-metadata-changes-reach-other-peers-about-once-per-second)).
- `ditto.deviceName` is the name that other peers see as `Peer.deviceName`. According to the API reference, it defaults to the host name. Set it before `ditto.sync.start()`: in our testing, a change made while sync was running did not reach other peers until sync was stopped and started again (see [Peer metadata is replaced, not merged, and the device name is read when sync starts](../knowledge/observations/connections-and-presence.md#peer-metadata-is-replaced-not-merged-and-the-device-name-is-read-when-sync-starts)). Other peers also see each peer's `os` and `dittoSdkVersion`, which helps to find devices that run an older SDK (see [Presence shows each peer's SDK version](../knowledge/observations/connections-and-presence.md#presence-shows-each-peers-sdk-version)).

**✅ DO:**
- Stop presence observers when the screen or feature that uses them goes away.
- Keep peer metadata small and non-sensitive, such as a role or a display name. Every connected device receives about twice its size whenever a device joins or changes it: in our testing over TCP, 3 KB of metadata cost each device about 6 KiB per change (see [Presence traffic grows faster than the number of devices](../knowledge/observations/connections-and-presence.md#presence-traffic-grows-faster-than-the-number-of-devices)). Write large or frequently changing values (positions, task state) to documents instead.
- Set peer metadata once at startup (for example `ditto.presence.peerMetadata = {'role': 'cashier'};`), not from individual screens. Other peers see at most about one change per second.
- Set `ditto.deviceName` to a name that identifies the device for your support staff and not a person, before you start sync.

**❌ DON'T:**
- Put secrets, tokens, or personal data in peer metadata. Peer metadata, and the `identityServiceMetadata` returned by your authentication webhook, are shared with every peer in the mesh, not only with directly connected peers.

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
