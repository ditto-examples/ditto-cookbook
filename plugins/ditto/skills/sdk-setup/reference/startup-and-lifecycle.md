# Ditto Startup and Lifecycle Reference

Requirements, initialization, authentication, system parameters, sync start and stop, and shutdown for Ditto SDK 5.2.0, for every SDK. Copied from `§ SDK Setup and Lifecycle` in `../../guide/reference/best-practices/setup-and-lifecycle.md`, and the platform differences from `§ Platform Differences` in `../../guide/reference/knowledge/platform-differences.md`; the code for each SDK is on its page in `../../guide/reference/best-practices/platforms/`, linked from each section.

## Requirements

Each SDK has its own package, supported operating systems, and permissions for peer-to-peer sync:

| SDK | Package | Requirements |
|---|---|---|
| Flutter | `ditto_live` on pub.dev | [Installing the Flutter SDK](../../guide/reference/best-practices/platforms/flutter.md#installing-the-flutter-sdk) |
| JavaScript | `@dittolive/ditto` on npm (Node.js, browsers, React Native) | [Installing the JavaScript SDK](../../guide/reference/best-practices/platforms/javascript.md#installing-the-javascript-sdk) |
| Kotlin | `com.ditto:ditto-kotlin` on Maven Central | [Installing the Kotlin SDK](../../guide/reference/best-practices/platforms/kotlin.md#installing-the-kotlin-sdk) |
| Swift | `DittoSwift` through Swift Package Manager | [Installing the Swift SDK](../../guide/reference/best-practices/platforms/swift.md#installing-the-swift-sdk) |

**✅ DO:**
- Pin the exact SDK version in your dependency file, so that every developer and every CI build uses the same release.
- Request the Bluetooth, local network, and nearby-device permissions that peer-to-peer sync needs before you start sync. A missing permission shows up as peers that never connect, not as an error (see [Diagnosing transport problems (SDK 5.1+)](../../guide/reference/best-practices/setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51)).


## Initializing Ditto

### DittoConfig

A Ditto instance is created from a `DittoConfig`. Its fields have the same meaning in every SDK; their names and types follow each SDK's conventions (see [DittoConfig in Flutter](../../guide/reference/best-practices/platforms/flutter.md#dittoconfig-in-flutter), [DittoConfig in JavaScript](../../guide/reference/best-practices/platforms/javascript.md#dittoconfig-in-javascript), [DittoConfig in Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#dittoconfig-in-kotlin), and [DittoConfig in Swift](../../guide/reference/best-practices/platforms/swift.md#dittoconfig-in-swift)):

| Field | Default | Notes |
|---|---|---|
| Database ID | All-zero UUID | Your Database ID. It must be a valid UUID. Do not rely on opening Ditto to reject an invalid value; check that no placeholder is left in your configuration. Peers with different Database IDs never see each other or sync, even over an explicit TCP connection, so a mix of development and production builds on one network does not sync (in our testing; see [Devices with different Database IDs do not sync](../../guide/reference/knowledge/observations/persistence-directory.md#devices-with-different-database-ids-do-not-sync)). |
| Connection | Small-peers-only without a key | Either a server connection with the Server URL, or small-peers-only, optionally with a shared private key. |
| Persistence directory | A directory named after the Database ID in the SDK's default location | If you choose the path yourself, include the Database ID in it: in our testing, a directory written with one Database ID opened without an error with another, and its documents synced to the new database (see [A directory written with another Database ID opens and syncs its documents](../../guide/reference/knowledge/observations/persistence-directory.md#a-directory-written-with-another-database-id-opens-and-syncs-its-documents)). How a relative path is resolved differs by SDK. |
| System parameters (SDK 5.2+) | None | Applied before Ditto starts (see [Applying System Parameters](../../guide/reference/best-practices/setup-and-lifecycle.md#applying-system-parameters)). |
| Encryption key (SDK 5.2+) | None | Kotlin and Swift only: encrypts the local store (see [Data at Rest](../../guide/reference/best-practices/security.md#data-at-rest)). |

There are two connection modes:

| Mode | Use it when | Authentication | Encryption in transit |
|---|---|---|---|
| Server connection with the Server URL | Devices sync through Ditto Server (and with each other) | Required: set an expiration handler and log in (see [Authentication](../../guide/reference/best-practices/setup-and-lifecycle.md#authentication)) | TLS |
| Small-peers-only with a private key | Devices sync only with each other using a shared key | Shared key: every peer that holds the key is trusted (no server) | TLS 1.3 |
| Small-peers-only without a key | Local store tests, and development with an offline license token | **None**: any device with the SDK, the Database ID, and a license token can connect | **Do not rely on it**: the SDK documents it as unencrypted (see below) |

**✅ DO:**
- Copy the Server URL from the Ditto Portal exactly as shown. Do not build it from the Database ID.
- Use small-peers-only with a provisioned private key for production small-peers-only deployments. The key is a base64-encoded P-256 (prime256v1) private key in PKCS#8 DER format, and opening Ditto fails if the key is not valid.
- Obtain an **offline license token** from Ditto for small-peers-only deployments and set it (`setOfflineOnlyLicenseToken`) before you start sync.

**❌ DON'T:**
- Ship small-peers-only without a private key to production. Peers do not authenticate each other in that mode: any device that runs the SDK with the same Database ID (and a valid offline license token) can connect, read, and write. The SDK's API reference describes the mode as unencrypted in transit; in our testing over TCP, the traffic was TLS-wrapped, but no shared secret authenticated the peers, so treat it as unprotected (see [Shared keys must match, and traffic is TLS-wrapped without a key](../../guide/reference/knowledge/observations/connections-and-presence.md#shared-keys-must-match-and-traffic-is-tls-wrapped-without-a-key)).
- Hardcode the shared key in the app binary (see [Small-Peers-Only Deployments](../../guide/reference/best-practices/security.md#small-peers-only-deployments)).

**Why:** In small-peers-only mode, starting sync fails (`The operation failed because the Ditto instance is not yet activated`) until a valid offline license token has been set, regardless of whether a private key is used. An invalid token makes setting it fail (`The license failed verification`). A peer without a valid token is invisible to the other peers. The local store works without a license, which is why tests can open Ditto without one as long as they do not start sync.

For generating, distributing, and storing the shared key, see [Small-Peers-Only Deployments](../../guide/reference/best-practices/security.md#small-peers-only-deployments).

### One instance per persistence directory

**Open Ditto once at app start, share the instance, and close it only when the app no longer needs it.** Only one `Ditto` instance can use a persistence directory at a time, and only one app can use a database at the same time. Opening a directory that another process holds (a second window of the app, an old process left behind by a development server, or a suspended process) fails with the error code `store/persistence-directory-locked`, after about one second in our testing; the lock of a process that crashed did not remain (see [A directory locked by another process fails to open after about 1 second](../../guide/reference/knowledge/observations/persistence-directory.md#a-directory-locked-by-another-process-fails-to-open-after-about-1-second)). Share the instance through your app's dependency injection or a service object.

Opening a directory that the same process already has open failed after about one second in every SDK on 5.2.0 in our testing, but on Flutter 5.1.0 the second open never completed (see [In Flutter, opening an open directory again fails within a second on SDK 5.2.0 and never completes on 5.1.0](../../guide/reference/knowledge/observations/flutter-sdk.md#in-flutter-opening-an-open-directory-again-fails-within-a-second-on-sdk-520-and-never-completes-on-510), [In JavaScript, opening an open directory again fails](../../guide/reference/knowledge/observations/javascript-sdk.md#in-javascript-opening-an-open-directory-again-fails), [In Kotlin, opening an open directory again fails after about a second](../../guide/reference/knowledge/observations/kotlin-sdk.md#in-kotlin-opening-an-open-directory-again-fails-after-about-a-second), and [In Swift, opening an open directory again fails after about a second](../../guide/reference/knowledge/observations/swift-sdk.md#in-swift-opening-an-open-directory-again-fails-after-about-a-second)). Never rely on a second open to fail.

**✅ DO:**
- Open Ditto once and pass the instance to the parts of the app that need it.
- Guard against concurrent opens by letting every caller wait for the same pending open.
- In development, when a tool restarts your app's code without ending the process (such as a hot restart), use a new persistence directory for each start, or close the instance before the restart. Keep a fixed directory in release builds, where the local data must survive restarts.

**❌ DON'T:**
- Open a new instance per screen or per request.
- Open the same directory twice, or reopen it before closing has completed.
- Read, write, or delete files inside the persistence directory yourself. To remove the local data, delete the whole directory after closing has completed.
- Copy a persistence directory to another device or installation while the original stays in use, for example by cloning a device image or an emulator snapshot, or by restoring a backup to a new device and keeping the old one.

> **Note (SDK 5.1.0 and 5.2.0):** The persistence directory holds the device's identity (its peer key) and its record of what it has synced with each peer, so a partial or copied directory breaks sync without an error. In our testing, a copied directory and its original, running at the same time, never converged, and neither device could notice (see [Updates from a copied directory and its original never converge](../../guide/reference/knowledge/observations/persistence-directory.md#updates-from-a-copied-directory-and-its-original-never-converge)); a device whose `ditto_store` subdirectory alone had been deleted kept its peer key, and some documents that it created before sync started had not reached other devices after 30 seconds (see [Deleting only ditto_store keeps the peer key, and on SDK 5.1.0 and 5.2.0 leaves some writes unsynced](../../guide/reference/knowledge/observations/persistence-directory.md#deleting-only-ditto_store-keeps-the-peer-key-and-on-sdk-510-and-520-leaves-some-writes-unsynced)). A device whose whole directory had been deleted came back with a new peer key and synced everything.
>
> The problem is running both copies. A copy that replaces the original, and a device that goes back to an older copy of its own directory, synced normally in our testing (see [A copy that replaces the original syncs normally](../../guide/reference/knowledge/observations/persistence-directory.md#a-copy-that-replaces-the-original-syncs-normally) and [Restoring an older copy of a directory loses nothing that had synced](../../guide/reference/knowledge/observations/persistence-directory.md#restoring-an-older-copy-of-a-directory-loses-nothing-that-had-synced)). If both have run, close one of them and delete its whole directory, so that it syncs again with a new peer key; changes that only that device wrote while both ran may not come back.

To delete the local store, Kotlin and Swift have `deleteStore` (SDK 5.2+). In Flutter and JavaScript, which have no API for it, wait until closing has completed, delete the whole persistence directory, and open Ditto again if the app still needs it. **Note (SDK 5.1.0 and 5.2.0):** in our testing on macOS, deleting the directory while Ditto was open raised no error, a second instance could then open the same path, and the first instance's writes were lost when it closed (see [On macOS, deleting the directory while Ditto is open loses later writes](../../guide/reference/knowledge/observations/persistence-directory.md#on-macos-deleting-the-directory-while-ditto-is-open-loses-later-writes)). The lock file is no sign of whether a directory is in use, and recent writes of a small store can be only in the write-ahead log file (`db.sql-wal`; see [After close(), a small store keeps its values in the write-ahead log](../../guide/reference/knowledge/observations/persistence-directory.md#after-close-a-small-store-keeps-its-values-in-the-write-ahead-log)), so do not back up or copy single files of the directory either.

The code for one shared instance: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#one-shared-instance-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#one-shared-instance-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#one-shared-instance-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#one-shared-instance-in-swift).

### Complete app startup

Start Ditto in this order, in one app-level service that owns the instance and its long-lived subscriptions:

1. **Configure logging** before you open Ditto, so that startup is logged with your settings (see [Logging](../../guide/reference/best-practices/logging-and-observability.md#logging)).
2. **Open the single shared instance** with your system parameters. System parameters are not persisted, so pass them on every open (see [Applying System Parameters](../../guide/reference/best-practices/setup-and-lifecycle.md#applying-system-parameters)).
3. **Set up access**: for a server connection, set the expiration handler (see [Authentication](../../guide/reference/best-practices/setup-and-lifecycle.md#authentication)); for small-peers-only, set the offline license token.
4. **Create the indexes** that your queries need, before queries and observers run. Indexes persist, and `CREATE INDEX IF NOT EXISTS` makes this safe on every start (see [Creating Indexes](../../guide/reference/best-practices/indexing-and-performance.md#creating-indexes)).
5. **Register long-lived subscriptions** (see [Subscription Lifecycle](../../guide/reference/best-practices/sync-and-subscriptions.md#subscription-lifecycle)).
6. **Start sync.**

If a step after opening fails, close the instance before you report the error, so that a retry does not open a directory that is still open.

```sql
-- Step 4: safe on every start
CREATE INDEX IF NOT EXISTS idx_orders_storeId ON orders (storeId)

-- Step 5: a long-lived subscription, scoped by a stable key
-- Arguments: {"storeId": "store-1"}
SELECT * FROM orders WHERE storeId = :storeId
```

The complete startup service: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#app-startup-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#app-startup-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#app-startup-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#app-startup-in-swift).


## Authentication

**Set the expiration handler before you start sync, log in from it with a fresh token, check the result of the login, and never let an error escape from it.** With a server connection, a device must authenticate before it can sync. Authentication is driven by an **expiration handler** that you register on `ditto.auth`.

| Behavior | Details |
|---|---|
| When it is called | When the device has not authenticated yet, when credentials are about to expire, and when they have expired |
| Time until expiration | Zero means "not authenticated yet" or "already expired"; a positive value is the time left before expiry |
| Required? | Yes for server connections: starting sync fails ("an authentication expiration handler has not yet been set") without it |
| What to do inside | Fetch a token from your backend and call `login` with the token and your provider name |

How `login` reports a rejected token or an unreachable server differs by SDK, so check it the way your SDK reports it:

| SDK | A rejected token or an unreachable server |
|---|---|
| Flutter | `login` returns an `AuthResponse` whose `exception` is set; it does not throw |
| JavaScript | `login` returns a result whose `error` is set; it does not throw |
| Kotlin | `login` **throws** |
| Swift | The completion handler receives the error |

**✅ DO:**
- Set the handler before you start sync.
- Fetch a fresh token from your backend inside the handler, so that refreshes also work.
- Check the login result and report failures through logging or the UI.
- Catch errors from your own token code inside the handler.
- Use the development provider with the development token from the Ditto Portal (shown in some places as the "Online Playground" token) **only during development**.

**❌ DON'T:**
- Let an error escape from the handler. Ditto does not receive it, and it becomes an unhandled error in your app. Log or report it instead.
- Ship the development provider or development token in a production build.
- Cache a single token for the lifetime of the app; the handler is called again when credentials expire.

**Why:** Credentials are issued by Ditto Server after your webhook validates the token (see [Authentication in Production](../../guide/reference/best-practices/security.md#authentication-in-production)), and they expire after the `expirationSeconds` your webhook returns. The handler is the single place where the SDK asks your app for a new token, so it must be reliable and must not crash.

**Logging out**: `auth.logout()` clears the credentials and **stops sync**. Start sync again after the next successful login if the device should resume syncing. `auth.status` exposes whether the device is authenticated and the user ID.

To remove local data as part of logging out, pass a cleanup callback to `logout` (SDK 5.2+). It runs after sync has stopped, and `logout` completes only after it finishes. After logout the instance may no longer write, except for `EVICT`, so the callback can evict sensitive documents. Evicted values can still be read from the database files (see [Data at Rest](../../guide/reference/best-practices/security.md#data-at-rest) and [Most deleted and evicted values remain in the database files](../../guide/reference/knowledge/observations/storage-and-deletion.md#most-deleted-and-evicted-values-remain-in-the-database-files)); to remove them for sure, delete the persistence directory after closing (see [Deleting the directory after close() leaves no data behind](../../guide/reference/knowledge/observations/persistence-directory.md#deleting-the-directory-after-close-leaves-no-data-behind)). Exceptions thrown by the callback are logged and do not reach the caller, so check the result yourself (for example with a `SELECT COUNT(*)`) when the cleanup must succeed. Concurrent `logout` calls collapse into one, and only the first caller's cleanup runs.

The code for production and development login: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#authentication-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#authentication-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#authentication-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#authentication-in-swift).

### Switching users on a shared device

The local store belongs to the device, not to the user: documents that one user's subscriptions brought to the device stay in it after logout and remain visible to local queries until they are evicted (see [Cancelling subscriptions and local data](../../guide/reference/best-practices/sync-and-subscriptions.md#cancelling-subscriptions-and-local-data)). When several people use one device, sign a user out in this order:

1. **Wait for the user's important writes**, with a timeout, until Ditto Server (or, without a server, the hub or another device) has confirmed them (see [Resource Cleanup and Shutdown](../../guide/reference/best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown)). `logout` stops sync, and evicting a document can discard changes that have not left the device.
2. **Cancel the user's subscriptions** and the observers of their screens. Documents that an active subscription still matches sync back after the next start of sync.
3. **Log out with a cleanup callback** (SDK 5.2+) and evict the user's documents in the callback, then check that they are gone, because exceptions in the callback do not reach the caller.
4. **For data that must not remain readable in the database files**, close Ditto and delete the persistence directory instead (see [Data at Rest](../../guide/reference/best-practices/security.md#data-at-rest)). On Flutter 5.2.0, opening Ditto again in the same process afterwards can stop without an error: in our testing, it did when a subscription or transaction object of the closed instance was garbage-collected. Keep the subscription objects reachable, or open the new store after the app restarts (see [Subscriptions in Flutter](../../guide/reference/best-practices/platforms/flutter.md#subscriptions-in-flutter) and [In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](../../guide/reference/knowledge/observations/flutter-sdk.md#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close)).
5. **After the next user logs in**, register that user's subscriptions and start sync.

```sql
-- Step 3, inside the cleanup callback: evict the user's documents
-- Arguments: {"storeId": "store-1"}
EVICT FROM orders WHERE storeId = :storeId

-- Arguments: {"storeId": "store-1"}
EVICT FROM orderItems WHERE storeId = :storeId

-- After logout: confirm that nothing is left
-- Arguments: {"storeId": "store-1"}
SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId
```

The code for signing a user out: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#switching-users-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#switching-users-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#switching-users-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#switching-users-in-swift).


## Applying System Parameters

**Pass the settings your app always needs in the system parameters of `DittoConfig` on every open (SDK 5.2+), and use `ALTER SYSTEM` only for values you change while the app runs.** System parameters change SDK behavior. **They are kept in memory only and are not persisted**: after the app restarts, or after closing and reopening Ditto, every parameter is back at its default value. There are two ways to set them:

| | System parameters in `DittoConfig` (SDK 5.2+) | `ALTER SYSTEM SET ...` |
|---|---|---|
| When it applies | Before Ditto starts, as part of opening it | After opening has returned, while Ditto runs |
| Parameters that Ditto reads only at startup | Take effect | Are stored but have no effect (for example `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`) |
| Unknown name or wrong type | Opening Ditto fails | The statement fails |
| Use it for | Every setting your app always needs | Changing a value while the app runs, for example during a support session |

In our testing with the JavaScript SDK 5.2.0, a parameter passed in the configuration was in effect when `Ditto.open()` returned, and lowercase names (`dql_strict_mode`) worked as well as uppercase ones (see [System parameters passed in DittoConfig take effect when Ditto.open returns](../../guide/reference/knowledge/observations/configuration-and-diagnostics.md#system-parameters-passed-in-dittoconfig-take-effect-when-dittoopen-returns)).

**Environment variables**: a parameter can also be set before the process starts with the environment variable `DITTO_<NAME>`, which is the only way to pass startup-only parameters on SDK 5.1 (see [DITTO_ environment variables set system parameters at startup](../../guide/reference/knowledge/observations/configuration-and-diagnostics.md#ditto_-environment-variables-set-system-parameters-at-startup)). Ditto reads the value as JSON: write booleans as lowercase `true` or `false`, numbers without quotes, and strings with their quotes (`DITTO_<NAME>='"value"'` in a shell). A value that is not valid JSON or has the wrong type is ignored with one log line, and Ditto starts with the default without any error in the app (in our testing; see [Environment variable values are read as JSON and ignored when invalid](../../guide/reference/knowledge/observations/configuration-and-diagnostics.md#environment-variable-values-are-read-as-json-and-ignored-when-invalid)), so check the value with `SHOW <name>` after the start. Do not use the `DITTO_` prefix for your app's own settings: Ditto logs a warning at every start for each such variable that names no system parameter.

**✅ DO:**
- Pass the settings your app always needs in the system parameters of `DittoConfig`, on every open. Keep them in one place, next to the rest of your configuration.
- Use `ALTER SYSTEM` only for values you change while the app runs.
- Read the current value with `SHOW <parameter>` when you need to confirm a setting.

**❌ DON'T:**
- Run `ALTER SYSTEM` once (for example in a migration) and assume it stays in effect.
- Change parameters such as `DQL_STRICT_MODE` after sync has started or after queries and observers have run.

`DQL_STRICT_MODE` defaults to `false`. Set it only if your app deliberately opts into strict mode; see [Strict Mode](../../guide/reference/best-practices/data-modeling.md#strict-mode) for the trade-offs.

```sql
-- Confirm the effective value. SHOW returns one row keyed by the lowercase
-- parameter name, for example {"dql_strict_mode": true}.
SHOW DQL_STRICT_MODE

-- Change a value while the app runs, and restore the default later
ALTER SYSTEM SET DQL_REQUEST_HISTORY_SIZE = 512

ALTER SYSTEM RESET DQL_REQUEST_HISTORY_SIZE
```

**SDK 5.1**: `DittoConfig` has no system parameters. Run `ALTER SYSTEM SET ...` every time you open Ditto, after opening and before you start sync, run queries, or register observers (subscriptions may be registered first). Parameters that Ditto reads only at startup cannot be set this way.

To list everything, use `SHOW ALL` (optionally filtered, for example `SHOW ALL LIKE 'dql%'`; the filter needs SDK 5.1+; see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../../guide/reference/knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)). The parameters most relevant to app developers are listed in [System Parameters Reference](../../guide/reference/knowledge/system-reference.md#system-parameters-reference); others are described in the section that uses them.

The code for passing system parameters: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#dittoconfig-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#dittoconfig-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#dittoconfig-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#dittoconfig-in-swift).


## Starting and Stopping Sync

- `sync.start()` fails if sync cannot start, for example when the expiration handler or the offline license token is missing. Calling it while sync is active does nothing. `sync.isActive` tells you whether sync is running.
- After `sync.stop()`, the local store remains fully usable; only network sync stops. `stop()` closes all connections right away, on both sides, and subscriptions stay registered; changes made on either side while sync was stopped are exchanged after `start()` (in our testing; see [Starting and stopping sync behaved as documented](../../guide/reference/knowledge/observations/subscriptions-and-replication.md#starting-and-stopping-sync-behaved-as-documented)).
- Subscriptions can be registered before `start()` or while sync is stopped; they take effect when sync runs.
- A short pause catches up quickly while the network is up: in our testing, devices that repeatedly stopped sync for 0.5 to 2 seconds had the latest values within about 0.15 seconds after `start()` (25 ms at the median), and the devices that kept syncing were barely delayed (see [Presence callbacks stay at about one per second while peers come and go](../../guide/reference/knowledge/observations/connections-and-presence.md#presence-callbacks-stay-at-about-one-per-second-while-peers-come-and-go)). After a real network outage, add the time until the outage is noticed (see [Presence](../../guide/reference/best-practices/setup-and-lifecycle.md#presence) and [A silent network outage removes a peer after about 7 seconds](../../guide/reference/knowledge/observations/connections-and-presence.md#a-silent-network-outage-removes-a-peer-after-about-7-seconds)).
- When many devices start sync at once with changes they made offline, staggering the starts spreads the work: in our testing, with 20 devices started half a second apart, new documents kept reaching the devices that had already synced within about 0.1 seconds, but all devices agreed only after the last one had started, and the hub did the same total work (see [Convergence after simultaneous reconnects grew faster than the number of devices](../../guide/reference/knowledge/observations/subscriptions-and-replication.md#convergence-after-simultaneous-reconnects-grew-faster-than-the-number-of-devices) and [Scope subscriptions to what the device needs](../../guide/reference/best-practices/sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs)).

Start sync **after** the expiration handler is set (server connections) or the offline license token is set (small-peers-only), and after system parameters have been applied. Starting it earlier fails for server connections, and code that registers the handler after the failed start never runs.

**App lifecycle**: `sync.start()` and `sync.stop()` give you explicit control over when the device syncs. Background behavior depends on the operating system:
- **iOS**: Background sync is best-effort and requires Bluetooth LE with the Bluetooth central and peripheral background modes enabled. Low Power Mode can make it less reliable.
- **Android**: To keep syncing while the app is in the background, declare Ditto's foreground service in `AndroidManifest.xml` as the install guide of your SDK shows. The service starts and stops together with sync.

**✅ DO:**
- Keep the Ditto instance open while the app is in the background.
- Stop and start sync only if your app must not sync in the background, and restart only the sync that you paused.

**❌ DON'T:**
- Close Ditto when the app moves to the background. Closing is final for that instance: every later call on it fails, and you would have to open a new instance and register all subscriptions and observers again.

The code for pausing sync in the background: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#sync-and-the-app-lifecycle-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#sync-and-the-app-lifecycle-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#sync-and-the-app-lifecycle-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#sync-and-the-app-lifecycle-in-swift).


## Resource Cleanup and Shutdown

Ditto objects hold native resources. Always release them explicitly; do not rely on garbage collection to cancel them. Each SDK page lists its objects and their release calls (see [Closing Ditto in Flutter](../../guide/reference/best-practices/platforms/flutter.md#closing-ditto-in-flutter), [Closing Ditto in JavaScript](../../guide/reference/best-practices/platforms/javascript.md#closing-ditto-in-javascript), [Closing Ditto in Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#closing-ditto-in-kotlin), and [Closing Ditto in Swift](../../guide/reference/best-practices/platforms/swift.md#closing-ditto-in-swift)):

| Object | Release it when | Notes |
|---|---|---|
| The `Ditto` instance | The whole app no longer needs Ditto | Closing also releases everything below and stops sync |
| Store observers | Their screen or owner goes away | See [Observer Lifecycle](../../guide/reference/best-practices/observers.md#observer-lifecycle) |
| Sync subscriptions | The device no longer needs their data | Required to stop syncing the data they matched |
| Presence observers and transport condition observers | Their screen or feature goes away | |
| Attachment fetchers | You cancel a fetch in progress | Not needed after a fetch has completed |
| The connection request handler | You no longer filter incoming connections | Set it to none |

Each SDK can list what is still registered, such as the store's observers and attachment fetchers. A count that keeps growing while the user moves between screens points to an observer that is never released.

What closing does:
- **It is final** for the instance. Closing twice is safe, but every other call on a closed instance fails, and in Swift, where releasing the last reference shuts the instance down, some calls end the process (see [In Swift, calls after the instance is released throw or end the process](../../guide/reference/knowledge/observations/swift-sdk.md#in-swift-calls-after-the-instance-is-released-throw-or-end-the-process)). Open a new instance if the app needs Ditto again.
- **It stops sync** and releases observers, subscriptions, and other resources.
- **What it does with your pending work differs by SDK**, so await your own pending work, and let open transactions end, before closing on every SDK:

| | Flutter | JavaScript | Kotlin | Swift (releasing the last reference) |
|---|---|---|---|---|
| An open transaction | `close()` stops the isolate, which in an app is the UI | `close()` waits for it | `close()` waits for it | The release waits about 1 second, and the transaction commits |
| Writes still in flight | Their `Future`s fail; the writes were stored only if `execute` had run before | `close()` completes them | Stored, also when the call throws | On 5.2.0, most fail |

  In our testing with SDK 5.1.0 and 5.2.0 (see [In Flutter, close() while a transaction is open stops the app's isolate](../../guide/reference/knowledge/observations/flutter-sdk.md#in-flutter-close-while-a-transaction-is-open-stops-the-apps-isolate), [In Flutter, close() fails pending execute calls, also writes that it stores](../../guide/reference/knowledge/observations/flutter-sdk.md#in-flutter-close-fails-pending-execute-calls-also-writes-that-it-stores), [In JavaScript, close() waits for open transactions](../../guide/reference/knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-open-transactions), [In JavaScript, close() completes pending writes](../../guide/reference/knowledge/observations/javascript-sdk.md#in-javascript-close-completes-pending-writes), [In Kotlin, close() waits for an open transaction](../../guide/reference/knowledge/observations/kotlin-sdk.md#in-kotlin-close-waits-for-an-open-transaction), [In Kotlin, writes in flight when close() runs are stored even when the call throws](../../guide/reference/knowledge/observations/kotlin-sdk.md#in-kotlin-writes-in-flight-when-close-runs-are-stored-even-when-the-call-throws), [In Swift, releasing the last reference shuts Ditto down at once](../../guide/reference/knowledge/observations/swift-sdk.md#in-swift-releasing-the-last-reference-shuts-ditto-down-at-once), and [In Swift 5.2.0, writes in flight fail when the instance is released](../../guide/reference/knowledge/observations/swift-sdk.md#in-swift-520-writes-in-flight-fail-when-the-instance-is-released)). A write whose call failed may still have been stored, so do not retry such writes blindly: read first, or make the write an upsert.
- **It does not wait for changes that are still being sent.** An awaited write is in the local store, but it may not have reached any other device yet. `sync.stop()` does not wait for them either. Such changes stay on the device and sync the next time it syncs.

> **Note (SDK 5.1.0 and 5.2.0):** An awaited write is in the local store, but closing, `sync.stop()`, and ending the app do not wait until it has been sent. In our testing, a 1 MB document written right before any of them never reached the hub, and a 100-byte document did in most runs but not in all; when the device first waited until the hub's `synced_up_to_local_commit_id` reached the write's `commitID`, every write arrived (see [A write made right before close or stop may not leave the device](../../guide/reference/knowledge/observations/subscriptions-and-replication.md#a-write-made-right-before-close-or-stop-may-not-leave-the-device)). A write that did not leave the device is sent the next time it syncs, so it is lost only if the device never syncs again, for example because its store is deleted. Before you close Ditto at a point where data must reach another device (logout, the end of a shift, before deleting the local store), wait with a timeout until the write is confirmed, and tell the user if unsent changes remain:

```sql
-- Poll until Ditto Server has confirmed the write: done when
-- documents.synced_up_to_local_commit_id >= the write's commitID
SELECT * FROM system:data_sync_info WHERE is_ditto_server = true
```

Give each read of this collection its own deadline as well: in our testing with the JavaScript and Swift SDKs on 5.1.0 and 5.2.0, and with the Kotlin SDK on 5.1.0, such a read sometimes never returned (see [Monitoring Sync Status](../../guide/reference/best-practices/sync-and-subscriptions.md#monitoring-sync-status), [In JavaScript, a read of system:data_sync_info can stop responding](../../guide/reference/knowledge/observations/javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding), [In Swift, a read of system:data_sync_info can stop responding](../../guide/reference/knowledge/observations/swift-sdk.md#in-swift-a-read-of-systemdata_sync_info-can-stop-responding), and [On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](../../guide/reference/knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)).

The code for waiting until a write is confirmed and for shutting down in order: [Flutter](../../guide/reference/best-practices/platforms/flutter.md#closing-ditto-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#closing-ditto-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#closing-ditto-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#closing-ditto-in-swift).

## Platform differences

The concepts, the DQL, and the sync behavior are the same in every SDK, but the APIs and some of their behavior differ.

### API Differences

| Topic | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Package | `ditto_live` (pub.dev) | `@dittolive/ditto` (npm) | `com.ditto:ditto-kotlin` (Maven Central) | `DittoSwift` (Swift Package Manager) |
| Create / open | `await Ditto.open(DittoConfig(...))`, or `Ditto.openSync` after `await Ditto.init()` | `await Ditto.open(config)`; on the Web, call `await init()` first | `DittoFactory.create(config)`, which does not suspend; its optional `CoroutineScope` (by default `MainScope()`) runs the callbacks | `try await Ditto.open(config:)`, or `Ditto.openSync(config:)` |
| System parameters at open (SDK 5.2+) | `DittoConfig(systemParameters: {...})` | `systemParameters` in the `DittoConfig` options | `DittoConfig(..., systemParameters = mapOf(...))` | `DittoConfig(..., systemParameters: [...])` |
| Start sync | `ditto.sync.start()` (`void`, throws on failure) | `ditto.sync.start()` | `ditto.sync.start()` (throws on failure) | `try ditto.sync.start()` |
| Shut down | `await ditto.close()` | `await ditto.close()` | `ditto.close()`, which waits for an open transaction | No `close()` in DittoSwift 5.1.0 and 5.2.0, although the 5.2.0 release notes announce one: release the last strong reference to the `Ditto` instance |
| Delete the local store (SDK 5.2+) | No API: after `close()`, delete the persistence directory | No API: after `close()`, delete the persistence directory | `DittoFactory.deleteStore(databaseId, persistenceDirectory)` | `Ditto.deleteStore(databaseID:persistenceDirectory:)` |
| Encryption at rest (SDK 5.2+) | Not available | Not available | `DittoConfig.encryptionKey` | `DittoConfig.encryptionKey` |
| Login failure | Returns an `AuthResponse` whose `exception` is set; does not throw | Returns a result whose `error` is set; does not throw | **Throws** `DittoException.AuthenticationException` | Reported to the completion handler as an error |
| Arguments | `arguments: {...}` (a `Map`) | A plain object as the second argument | A `Map`, or a serializable value | A dictionary (`arguments:`), or a `Codable` value |
| Query results | `items` is an `Iterable`; released by garbage collection | `items` is an array; released by garbage collection | Read inside the mapping function of `execute`; `executeRaw` returns a result that you `close()` | Released by automatic reference counting |
| Default observer | `registerObserver`, consumed through its `changes` stream | `registerObserver(query, handler, args)` | `registerObserver(query, args) { result -> }` (a suspending handler), or `observe(...)`, which returns a `Flow` | `registerObserver(query:arguments:deliverOn:handler:)`, delivered on the main queue by default |
| Observer backpressure | `registerObserver`: none. `registerObserverV2` (automatic, when its `changes` are consumed with `await for`) and `registerObserverWithSignalNext` (manual), both (Experimental) (SDK 5.1+) | `registerObserver` waits until a synchronous handler returns; an `async` handler is not awaited. `registerObserverWithSignalNext` for asynchronous work | The suspending handler and `collect` wait for your code; no `signalNext`. A slow `Flow` collector should `.conflate()` | `handler:` waits until it returns; `handlerWithSignalNext:` waits for `signalNext()` |
| Release observers and subscriptions | `cancel()` | `cancel()` | `close()` | `cancel()` |
| Differ | `Differ` | `Differ` | None that apps create: the observer passes a `DittoDiff` to its handler | `DittoDiffer` |
| Transaction completion | Return a value to commit; throw or return `TransactionCompletionAction.rollback` to roll back | Return a value to commit, or `'rollback'` | Must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` | Must return a value or `.commit` to commit, or `.rollback` |
| Attachments | `newAttachment` and `fetchAttachment`, which returns an `AttachmentFetcher` | `newAttachment` and `fetchAttachment`, which returns a fetcher | `newAttachment`, and a suspending `fetchAttachment` that reports progress to a callback | `newAttachment` and `fetchAttachment`, which returns a `DittoAttachmentFetcher` |
| Forward log events | `DittoLogger.customLogCallback` | `Logger.setCustomLogCallback` | `DittoLogger.observeLogEvents()`, a `Flow` | `DittoLogger.setCustomLogCallback(_:)` |


### Behavior Differences

What we observed on SDK 5.1.0 and 5.2.0. Each row names the section of the guide that gives the rule, and the section "Behavior Specific to the ... SDK" of each SDK page links to the observation behind its column.

| Behavior | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| A dropped reference to an observer or a subscription ([Observer Lifecycle](../../guide/reference/best-practices/observers.md#observer-lifecycle)) | Keeps running; release it explicitly | Keeps running; release it explicitly | Keeps running; release it explicitly | Keeps running; release it explicitly |
| An exception in an observer callback ([Observer Lifecycle](../../guide/reference/best-practices/observers.md#observer-lifecycle)) | Reaches the zone; the observer keeps running, but a throwing `onChange` keeps its result out of `changes`, and a throw before `signalNext()` stops the observer | A synchronous throw is discarded; a rejected `async` callback is an unhandled rejection, which ends a Node.js process | Closes the observer, and is only logged | The handler cannot throw |
| Observer callbacks run on ([Keep observer callbacks fast](../../guide/reference/best-practices/observers.md#keep-observer-callbacks-fast)) | The isolate that registered the observer | The event loop | The main thread, unless `DittoFactory.create` gets another scope | The main queue, unless `deliverOn:` names another |
| `ditto.store.execute` inside a transaction ([Transaction Rules](../../guide/reference/best-practices/transactions.md#transaction-rules)) | Throws a `DittoException` | Writes never complete; reads complete but do not see the transaction's writes | Writes never complete; reads complete but do not see the transaction's writes | Writes never complete; reads complete |
| A read-write transaction started inside another ([Transaction Rules](../../guide/reference/best-practices/transactions.md#transaction-rules)) | Waits until the outer one ends, so an outer callback that awaits it never ends | The same | The same | The same |
| Many writes that wait behind an open transaction ([Transaction Rules](../../guide/reference/best-practices/transactions.md#transaction-rules)) | Wait until it ends (not tested with many) | Wait until it ends; 200 did | Each holds a thread; with 64 on `Dispatchers.IO`, the transaction could not resume | With as many as the CPU has cores (14 on our Mac), every task of the process stopped |
| Shutting down while a transaction is open ([Resource Cleanup and Shutdown](../../guide/reference/best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown)) | `close()` stops the isolate (in an app, the UI) | `close()` waits for the transaction | `close()` waits for the transaction | The release blocks its thread until the transaction ends (15 seconds for a transaction with 15 seconds left); the transaction commits |
| Writes in flight when Ditto shuts down ([Resource Cleanup and Shutdown](../../guide/reference/best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown)) | Their `Future`s fail; the writes were stored if the worker isolate of `execute` was already running, and none were if the first `execute` came right before `close()` | `close()` completes them | Stored, also when the call throws | 5.2.0: most fail with `useAfterCloseError` |
| Calls after shutdown ([Resource Cleanup and Shutdown](../../guide/reference/best-practices/setup-and-lifecycle.md#resource-cleanup-and-shutdown)) | `execute` and `transaction` fail their `Future` with `DittoClosedException`; registrations and `sync` calls throw it at once | Throw or reject with a plain `Error` | Throw, except `sync.start()` | `transaction` throws; `execute` throws on 5.2.0 and ends the process on 5.1.0; registering an observer or a subscription, `sync.start()`, and `presence.graph` end the process |
| Opening a directory that this process has open ([One instance per persistence directory](../../guide/reference/best-practices/setup-and-lifecycle.md#one-instance-per-persistence-directory)) | 5.2.0: fails after about 1 second. 5.1.0: never completes | Fails after about 1 second with `store/persistence-directory-locked` | Fails after about 1 second with `File already locked` | Fails after about 1 second with `persistenceDirectoryLocked` |
| Invalid DQL ([When a Statement Fails or Returns Nothing](../../guide/reference/best-practices/dql.md#when-a-statement-fails-or-returns-nothing)) | `execute` fails; registering an observer or a subscription throws | `execute` rejects; registering an observer or a subscription throws | The call that receives it throws | The call that receives it throws |
| The arguments of a listed subscription registered without arguments ([Sync stop, close, and inspection](../../guide/reference/best-practices/sync-and-subscriptions.md#sync-stop-close-and-inspection)) | Reading them ends the app | `queryArguments` is `null` | `queryArguments` is `null` | `queryArguments` is `nil` |
| Values that are not plain JSON ([Always pass values as parameters](../../guide/reference/best-practices/dql.md#always-pass-values-as-parameters)) | `DateTime` becomes a string, `Uint8List` comes back as a list, a `BigInt` of 2^63 or more comes back as a `double` or as bytes, NaN and infinity fail, maps with `int` keys and classes without `toCbor()` fail | `Date` becomes `{}`, `undefined` becomes `null`, NaN and infinity fail, integers above 2^53 − 1 come back as `BigInt`, `Set` and functions become `{}`, `10.0` is stored as an integer | `Date`, `Instant`, `UUID`, and big numbers fail; NaN and infinity fail; a decimal that a 32-bit float holds exactly, such as `7.5`, comes back as a `FloatValue` | `Date` becomes an object, NaN and infinity fail, `UUID` becomes an uppercase string; a value that fits in 32 bits, such as `12.5`, comes back as a `Float`, which `as? Double` does not read |

Kotlin, Java, Swift, and C# stored some values incorrectly before SDK 5.2, and the upgrade does not correct data that was already written; see [Known Issues in SDK 5.1.0](../../guide/reference/knowledge/upgrading.md#known-issues-in-sdk-510).
