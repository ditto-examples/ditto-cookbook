# SDK Setup and Lifecycle

This page covers what an app does from the first launch to shutdown: requirements, opening one shared instance, authentication, system parameters, starting and stopping sync, cleanup, transports, and presence. The rules apply to every SDK; the code for each SDK is on its page: [Flutter](platforms/flutter.md), [JavaScript](platforms/javascript.md), [Kotlin](platforms/kotlin.md), and [Swift](platforms/swift.md).

The order at startup is: configure logging, open Ditto with your system parameters, set the authentication expiration handler (server connections) or the offline license token (small-peers-only), create indexes, register long-lived subscriptions, and start sync (see [Complete app startup](#complete-app-startup)). At shutdown, release observers and subscriptions, wait for writes that must reach another device, and close Ditto; in Swift, which has no `close()` in SDK 5.2.0, release the last reference to the instance instead (see [Resource Cleanup and Shutdown](#resource-cleanup-and-shutdown)).

## Requirements

Each SDK has its own package, supported operating systems, and permissions for peer-to-peer sync:

| SDK | Package | Requirements |
|---|---|---|
| Flutter | `ditto_live` on pub.dev | [Installing the Flutter SDK](platforms/flutter.md#installing-the-flutter-sdk) |
| JavaScript | `@dittolive/ditto` on npm (Node.js, browsers, React Native) | [Installing the JavaScript SDK](platforms/javascript.md#installing-the-javascript-sdk) |
| Kotlin | `com.ditto:ditto-kotlin` on Maven Central | [Installing the Kotlin SDK](platforms/kotlin.md#installing-the-kotlin-sdk) |
| Swift | `DittoSwift` through Swift Package Manager | [Installing the Swift SDK](platforms/swift.md#installing-the-swift-sdk) |

**✅ DO:**
- Pin the exact SDK version in your dependency file, so that every developer and every CI build uses the same release.
- Request the Bluetooth, local network, and nearby-device permissions that peer-to-peer sync needs before you start sync. A missing permission shows up as peers that never connect, not as an error (see [Diagnosing transport problems (SDK 5.1+)](#diagnosing-transport-problems-sdk-51)).

## Initializing Ditto

### DittoConfig

A Ditto instance is created from a `DittoConfig`. Its fields have the same meaning in every SDK; their names and types follow each SDK's conventions (see [DittoConfig in Flutter](platforms/flutter.md#dittoconfig-in-flutter), [DittoConfig in JavaScript](platforms/javascript.md#dittoconfig-in-javascript), [DittoConfig in Kotlin](platforms/kotlin.md#dittoconfig-in-kotlin), and [DittoConfig in Swift](platforms/swift.md#dittoconfig-in-swift)):

| Field | Default | Notes |
|---|---|---|
| Database ID | All-zero UUID | Your Database ID. It must be a valid UUID. Do not rely on opening Ditto to reject an invalid value; check that no placeholder is left in your configuration. Peers with different Database IDs never see each other or sync, even over an explicit TCP connection, so a mix of development and production builds on one network does not sync (in our testing; see [Devices with different Database IDs do not sync](../knowledge/observations/persistence-directory.md#devices-with-different-database-ids-do-not-sync)). |
| Connection | Small-peers-only without a key | Either a server connection with the Server URL, or small-peers-only, optionally with a shared private key. |
| Persistence directory | A directory named after the Database ID in the SDK's default location | If you choose the path yourself, include the Database ID in it: in our testing, a directory written with one Database ID opened without an error with another, and its documents synced to the new database (see [A directory written with another Database ID opens and syncs its documents](../knowledge/observations/persistence-directory.md#a-directory-written-with-another-database-id-opens-and-syncs-its-documents)). How a relative path is resolved differs by SDK. |
| System parameters (SDK 5.2+) | None | Applied before Ditto starts (see [Applying System Parameters](#applying-system-parameters)). |
| Encryption key (SDK 5.2+) | None | Kotlin and Swift only: encrypts the local store (see [Data at Rest](security.md#data-at-rest)). |

There are two connection modes:

| Mode | Use it when | Authentication | Encryption in transit |
|---|---|---|---|
| Server connection with the Server URL | Devices sync through Ditto Server (and with each other) | Required: set an expiration handler and log in (see [Authentication](#authentication)) | TLS |
| Small-peers-only with a private key | Devices sync only with each other using a shared key | Shared key: every peer that holds the key is trusted (no server) | TLS 1.3 |
| Small-peers-only without a key | Local store tests, and development with an offline license token | **None**: any device with the SDK, the Database ID, and a license token can connect | **Do not rely on it**: the SDK documents it as unencrypted (see below) |

**✅ DO:**
- Copy the Server URL from the Ditto Portal exactly as shown. Do not build it from the Database ID.
- Use small-peers-only with a provisioned private key for production small-peers-only deployments. The key is a base64-encoded P-256 (prime256v1) private key in PKCS#8 DER format, and opening Ditto fails if the key is not valid.
- Obtain an **offline license token** from Ditto for small-peers-only deployments and set it (`setOfflineOnlyLicenseToken`) before you start sync.

**❌ DON'T:**
- Ship small-peers-only without a private key to production. Peers do not authenticate each other in that mode: any device that runs the SDK with the same Database ID (and a valid offline license token) can connect, read, and write. The SDK's API reference describes the mode as unencrypted in transit; in our testing over TCP, the traffic was TLS-wrapped, but no shared secret authenticated the peers, so treat it as unprotected (see [Shared keys must match, and traffic is TLS-wrapped without a key](../knowledge/observations/connections-and-presence.md#shared-keys-must-match-and-traffic-is-tls-wrapped-without-a-key)).
- Hardcode the shared key in the app binary (see [Small-Peers-Only Deployments](security.md#small-peers-only-deployments)).

**Why:** In small-peers-only mode, starting sync fails (`The operation failed because the Ditto instance is not yet activated`) until a valid offline license token has been set, regardless of whether a private key is used. An invalid token makes setting it fail (`The license failed verification`). A peer without a valid token is invisible to the other peers. The local store works without a license, which is why tests can open Ditto without one as long as they do not start sync.

For generating, distributing, and storing the shared key, see [Small-Peers-Only Deployments](security.md#small-peers-only-deployments).

### One instance per persistence directory

**Open Ditto once at app start, share the instance, and close it only when the app no longer needs it.** Only one `Ditto` instance can use a persistence directory at a time, and only one app can use a database at the same time. Opening a directory that another process holds (a second window of the app, an old process left behind by a development server, or a suspended process) fails with the error code `store/persistence-directory-locked`, after about one second in our testing; the lock of a process that crashed did not remain (see [A directory locked by another process fails to open after about 1 second](../knowledge/observations/persistence-directory.md#a-directory-locked-by-another-process-fails-to-open-after-about-1-second)). Share the instance through your app's dependency injection or a service object.

Opening a directory that the same process already has open failed after about one second in every SDK on 5.2.0 in our testing, but on Flutter 5.1.0 the second open never completed (see [In Flutter, opening an open directory again fails within a second on SDK 5.2.0 and never completes on 5.1.0](../knowledge/observations/flutter-sdk.md#in-flutter-opening-an-open-directory-again-fails-within-a-second-on-sdk-520-and-never-completes-on-510), [In JavaScript, opening an open directory again fails](../knowledge/observations/javascript-sdk.md#in-javascript-opening-an-open-directory-again-fails), [In Kotlin, opening an open directory again fails after about a second](../knowledge/observations/kotlin-sdk.md#in-kotlin-opening-an-open-directory-again-fails-after-about-a-second), and [In Swift, opening an open directory again fails after about a second](../knowledge/observations/swift-sdk.md#in-swift-opening-an-open-directory-again-fails-after-about-a-second)). Never rely on a second open to fail.

**✅ DO:**
- Open Ditto once and pass the instance to the parts of the app that need it.
- Guard against concurrent opens by letting every caller wait for the same pending open.
- In development, when a tool restarts your app's code without ending the process (such as a hot restart), use a new persistence directory for each start, or close the instance before the restart. Keep a fixed directory in release builds, where the local data must survive restarts.

**❌ DON'T:**
- Open a new instance per screen or per request.
- Open the same directory twice, or reopen it before closing has completed.
- Read, write, or delete files inside the persistence directory yourself. To remove the local data, delete the whole directory after closing has completed.
- Copy a persistence directory to another device or installation while the original stays in use, for example by cloning a device image or an emulator snapshot, or by restoring a backup to a new device and keeping the old one.

> **Note (SDK 5.1.0 and 5.2.0):** The persistence directory holds the device's identity (its peer key) and its record of what it has synced with each peer, so a partial or copied directory breaks sync without an error. In our testing, a copied directory and its original, running at the same time, never converged, and neither device could notice (see [Updates from a copied directory and its original never converge](../knowledge/observations/persistence-directory.md#updates-from-a-copied-directory-and-its-original-never-converge)); a device whose `ditto_store` subdirectory alone had been deleted kept its peer key, and some documents that it created before sync started had not reached other devices after 30 seconds (see [Deleting only ditto_store keeps the peer key, and on SDK 5.1.0 and 5.2.0 leaves some writes unsynced](../knowledge/observations/persistence-directory.md#deleting-only-ditto_store-keeps-the-peer-key-and-on-sdk-510-and-520-leaves-some-writes-unsynced)). A device whose whole directory had been deleted came back with a new peer key and synced everything.
>
> The problem is running both copies. A copy that replaces the original, and a device that goes back to an older copy of its own directory, synced normally in our testing (see [A copy that replaces the original syncs normally](../knowledge/observations/persistence-directory.md#a-copy-that-replaces-the-original-syncs-normally) and [Restoring an older copy of a directory loses nothing that had synced](../knowledge/observations/persistence-directory.md#restoring-an-older-copy-of-a-directory-loses-nothing-that-had-synced)). If both have run, close one of them and delete its whole directory, so that it syncs again with a new peer key; changes that only that device wrote while both ran may not come back.

To delete the local store, Kotlin and Swift have `deleteStore` (SDK 5.2+). In Flutter and JavaScript, which have no API for it, wait until closing has completed, delete the whole persistence directory, and open Ditto again if the app still needs it. **Note (SDK 5.1.0 and 5.2.0):** in our testing on macOS, deleting the directory while Ditto was open raised no error, a second instance could then open the same path, and the first instance's writes were lost when it closed (see [On macOS, deleting the directory while Ditto is open loses later writes](../knowledge/observations/persistence-directory.md#on-macos-deleting-the-directory-while-ditto-is-open-loses-later-writes)). The lock file is no sign of whether a directory is in use, and recent writes of a small store can be only in the write-ahead log file (`db.sql-wal`; see [After close(), a small store keeps its values in the write-ahead log](../knowledge/observations/persistence-directory.md#after-close-a-small-store-keeps-its-values-in-the-write-ahead-log)), so do not back up or copy single files of the directory either.

The code for one shared instance: [Flutter](platforms/flutter.md#one-shared-instance-in-flutter) · [JavaScript](platforms/javascript.md#one-shared-instance-in-javascript) · [Kotlin](platforms/kotlin.md#one-shared-instance-in-kotlin) · [Swift](platforms/swift.md#one-shared-instance-in-swift).

### Complete app startup

Start Ditto in this order, in one app-level service that owns the instance and its long-lived subscriptions:

1. **Configure logging** before you open Ditto, so that startup is logged with your settings (see [Logging](logging-and-observability.md#logging)).
2. **Open the single shared instance** with your system parameters. System parameters are not persisted, so pass them on every open (see [Applying System Parameters](#applying-system-parameters)).
3. **Set up access**: for a server connection, set the expiration handler (see [Authentication](#authentication)); for small-peers-only, set the offline license token.
4. **Create the indexes** that your queries need, before queries and observers run. Indexes persist, and `CREATE INDEX IF NOT EXISTS` makes this safe on every start (see [Creating Indexes](indexing-and-performance.md#creating-indexes)).
5. **Register long-lived subscriptions** (see [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle)).
6. **Start sync.**

If a step after opening fails, close the instance before you report the error, so that a retry does not open a directory that is still open.

```sql
-- Step 4: safe on every start
CREATE INDEX IF NOT EXISTS idx_orders_storeId ON orders (storeId)

-- Step 5: a long-lived subscription, scoped by a stable key
-- Arguments: {"storeId": "store-1"}
SELECT * FROM orders WHERE storeId = :storeId
```

The complete startup service: [Flutter](platforms/flutter.md#app-startup-in-flutter) · [JavaScript](platforms/javascript.md#app-startup-in-javascript) · [Kotlin](platforms/kotlin.md#app-startup-in-kotlin) · [Swift](platforms/swift.md#app-startup-in-swift).

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

**Why:** Credentials are issued by Ditto Server after your webhook validates the token (see [Authentication in Production](security.md#authentication-in-production)), and they expire after the `expirationSeconds` your webhook returns. The handler is the single place where the SDK asks your app for a new token, so it must be reliable and must not crash.

**Logging out**: `auth.logout()` clears the credentials and **stops sync**. Start sync again after the next successful login if the device should resume syncing. `auth.status` exposes whether the device is authenticated and the user ID.

To remove local data as part of logging out, pass a cleanup callback to `logout` (SDK 5.2+). It runs after sync has stopped, and `logout` completes only after it finishes. After logout the instance may no longer write, except for `EVICT`, so the callback can evict sensitive documents. Evicted values can still be read from the database files (see [Data at Rest](security.md#data-at-rest) and [Most deleted and evicted values remain in the database files](../knowledge/observations/storage-and-deletion.md#most-deleted-and-evicted-values-remain-in-the-database-files)); to remove them for sure, delete the persistence directory after closing (see [Deleting the directory after close() leaves no data behind](../knowledge/observations/persistence-directory.md#deleting-the-directory-after-close-leaves-no-data-behind)). Exceptions thrown by the callback are logged and do not reach the caller, so check the result yourself (for example with a `SELECT COUNT(*)`) when the cleanup must succeed. Concurrent `logout` calls collapse into one, and only the first caller's cleanup runs.

The code for production and development login: [Flutter](platforms/flutter.md#authentication-in-flutter) · [JavaScript](platforms/javascript.md#authentication-in-javascript) · [Kotlin](platforms/kotlin.md#authentication-in-kotlin) · [Swift](platforms/swift.md#authentication-in-swift).

### Switching users on a shared device

The local store belongs to the device, not to the user: documents that one user's subscriptions brought to the device stay in it after logout and remain visible to local queries until they are evicted (see [Cancelling subscriptions and local data](sync-and-subscriptions.md#cancelling-subscriptions-and-local-data)). When several people use one device, sign a user out in this order:

1. **Wait for the user's important writes**, with a timeout, until Ditto Server (or, without a server, the hub or another device) has confirmed them (see [Resource Cleanup and Shutdown](#resource-cleanup-and-shutdown)). `logout` stops sync, and evicting a document can discard changes that have not left the device.
2. **Cancel the user's subscriptions** and the observers of their screens. Documents that an active subscription still matches sync back after the next start of sync.
3. **Log out with a cleanup callback** (SDK 5.2+) and evict the user's documents in the callback, then check that they are gone, because exceptions in the callback do not reach the caller.
4. **For data that must not remain readable in the database files**, close Ditto and delete the persistence directory instead (see [Data at Rest](security.md#data-at-rest)). On Flutter 5.2.0, opening Ditto again in the same process afterwards can stop without an error: in our testing, it did when a subscription or transaction object of the closed instance was garbage-collected. Keep the subscription objects reachable, or open the new store after the app restarts (see [Subscriptions in Flutter](platforms/flutter.md#subscriptions-in-flutter) and [In Flutter 5.2.0, dropped subscription and transaction objects of a closed instance stop the next open or close](../knowledge/observations/flutter-sdk.md#in-flutter-520-dropped-subscription-and-transaction-objects-of-a-closed-instance-stop-the-next-open-or-close)).
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

The code for signing a user out: [Flutter](platforms/flutter.md#switching-users-in-flutter) · [JavaScript](platforms/javascript.md#switching-users-in-javascript) · [Kotlin](platforms/kotlin.md#switching-users-in-kotlin) · [Swift](platforms/swift.md#switching-users-in-swift).

## Applying System Parameters

**Pass the settings your app always needs in the system parameters of `DittoConfig` on every open (SDK 5.2+), and use `ALTER SYSTEM` only for values you change while the app runs.** System parameters change SDK behavior. **They are kept in memory only and are not persisted**: after the app restarts, or after closing and reopening Ditto, every parameter is back at its default value. There are two ways to set them:

| | System parameters in `DittoConfig` (SDK 5.2+) | `ALTER SYSTEM SET ...` |
|---|---|---|
| When it applies | Before Ditto starts, as part of opening it | After opening has returned, while Ditto runs |
| Parameters that Ditto reads only at startup | Take effect | Are stored but have no effect (for example `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`) |
| Unknown name or wrong type | Opening Ditto fails | The statement fails |
| Use it for | Every setting your app always needs | Changing a value while the app runs, for example during a support session |

In our testing with the JavaScript SDK 5.2.0, a parameter passed in the configuration was in effect when `Ditto.open()` returned, and lowercase names (`dql_strict_mode`) worked as well as uppercase ones (see [System parameters passed in DittoConfig take effect when Ditto.open returns](../knowledge/observations/configuration-and-diagnostics.md#system-parameters-passed-in-dittoconfig-take-effect-when-dittoopen-returns)).

**Environment variables**: a parameter can also be set before the process starts with the environment variable `DITTO_<NAME>`, which is the only way to pass startup-only parameters on SDK 5.1 (see [DITTO_ environment variables set system parameters at startup](../knowledge/observations/configuration-and-diagnostics.md#ditto_-environment-variables-set-system-parameters-at-startup)). Ditto reads the value as JSON: write booleans as lowercase `true` or `false`, numbers without quotes, and strings with their quotes (`DITTO_<NAME>='"value"'` in a shell). A value that is not valid JSON or has the wrong type is ignored with one log line, and Ditto starts with the default without any error in the app (in our testing; see [Environment variable values are read as JSON and ignored when invalid](../knowledge/observations/configuration-and-diagnostics.md#environment-variable-values-are-read-as-json-and-ignored-when-invalid)), so check the value with `SHOW <name>` after the start. Do not use the `DITTO_` prefix for your app's own settings: Ditto logs a warning at every start for each such variable that names no system parameter.

**✅ DO:**
- Pass the settings your app always needs in the system parameters of `DittoConfig`, on every open. Keep them in one place, next to the rest of your configuration.
- Use `ALTER SYSTEM` only for values you change while the app runs.
- Read the current value with `SHOW <parameter>` when you need to confirm a setting.

**❌ DON'T:**
- Run `ALTER SYSTEM` once (for example in a migration) and assume it stays in effect.
- Change parameters such as `DQL_STRICT_MODE` after sync has started or after queries and observers have run.

`DQL_STRICT_MODE` defaults to `false`. Set it only if your app deliberately opts into strict mode; see [Strict Mode](data-modeling.md#strict-mode) for the trade-offs.

```sql
-- Confirm the effective value. SHOW returns one row keyed by the lowercase
-- parameter name, for example {"dql_strict_mode": true}.
SHOW DQL_STRICT_MODE

-- Change a value while the app runs, and restore the default later
ALTER SYSTEM SET DQL_REQUEST_HISTORY_SIZE = 512

ALTER SYSTEM RESET DQL_REQUEST_HISTORY_SIZE
```

**SDK 5.1**: `DittoConfig` has no system parameters. Run `ALTER SYSTEM SET ...` every time you open Ditto, after opening and before you start sync, run queries, or register observers (subscriptions may be registered first). Parameters that Ditto reads only at startup cannot be set this way.

To list everything, use `SHOW ALL` (optionally filtered, for example `SHOW ALL LIKE 'dql%'`; the filter needs SDK 5.1+; see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)). The parameters most relevant to app developers are listed in [System Parameters Reference](../knowledge/system-reference.md#system-parameters-reference); others are described in the section that uses them.

The code for passing system parameters: [Flutter](platforms/flutter.md#dittoconfig-in-flutter) · [JavaScript](platforms/javascript.md#dittoconfig-in-javascript) · [Kotlin](platforms/kotlin.md#dittoconfig-in-kotlin) · [Swift](platforms/swift.md#dittoconfig-in-swift).

## Starting and Stopping Sync

- `sync.start()` fails if sync cannot start, for example when the expiration handler or the offline license token is missing. Calling it while sync is active does nothing. `sync.isActive` tells you whether sync is running.
- After `sync.stop()`, the local store remains fully usable; only network sync stops. `stop()` closes all connections right away, on both sides, and subscriptions stay registered; changes made on either side while sync was stopped are exchanged after `start()` (in our testing; see [Starting and stopping sync behaved as documented](../knowledge/observations/subscriptions-and-replication.md#starting-and-stopping-sync-behaved-as-documented)).
- Subscriptions can be registered before `start()` or while sync is stopped; they take effect when sync runs.
- A short pause catches up quickly while the network is up: in our testing, devices that repeatedly stopped sync for 0.5 to 2 seconds had the latest values within about 0.15 seconds after `start()` (25 ms at the median), and the devices that kept syncing were barely delayed (see [Presence callbacks stay at about one per second while peers come and go](../knowledge/observations/connections-and-presence.md#presence-callbacks-stay-at-about-one-per-second-while-peers-come-and-go)). After a real network outage, add the time until the outage is noticed (see [Presence](#presence) and [A silent network outage removes a peer after about 7 seconds](../knowledge/observations/connections-and-presence.md#a-silent-network-outage-removes-a-peer-after-about-7-seconds)).
- When many devices start sync at once with changes they made offline, staggering the starts spreads the work: in our testing, with 20 devices started half a second apart, new documents kept reaching the devices that had already synced within about 0.1 seconds, but all devices agreed only after the last one had started, and the hub did the same total work (see [Convergence after simultaneous reconnects grew faster than the number of devices](../knowledge/observations/subscriptions-and-replication.md#convergence-after-simultaneous-reconnects-grew-faster-than-the-number-of-devices) and [Scope subscriptions to what the device needs](sync-and-subscriptions.md#scope-subscriptions-to-what-the-device-needs)).

Start sync **after** the expiration handler is set (server connections) or the offline license token is set (small-peers-only), and after system parameters have been applied. Starting it earlier fails for server connections, and code that registers the handler after the failed start never runs.

**App lifecycle**: `sync.start()` and `sync.stop()` give you explicit control over when the device syncs. Background behavior depends on the operating system:
- **iOS**: Background sync is best-effort and requires Bluetooth LE with the Bluetooth central and peripheral background modes enabled. Low Power Mode can make it less reliable.
- **Android**: To keep syncing while the app is in the background, declare Ditto's foreground service in `AndroidManifest.xml` as the install guide of your SDK shows. The service starts and stops together with sync.

**✅ DO:**
- Keep the Ditto instance open while the app is in the background.
- Stop and start sync only if your app must not sync in the background, and restart only the sync that you paused.

**❌ DON'T:**
- Close Ditto when the app moves to the background. Closing is final for that instance: every later call on it fails, and you would have to open a new instance and register all subscriptions and observers again.

The code for pausing sync in the background: [Flutter](platforms/flutter.md#sync-and-the-app-lifecycle-in-flutter) · [JavaScript](platforms/javascript.md#sync-and-the-app-lifecycle-in-javascript) · [Kotlin](platforms/kotlin.md#sync-and-the-app-lifecycle-in-kotlin) · [Swift](platforms/swift.md#sync-and-the-app-lifecycle-in-swift).

## Resource Cleanup and Shutdown

Ditto objects hold native resources. Always release them explicitly; do not rely on garbage collection to cancel them. Each SDK page lists its objects and their release calls (see [Closing Ditto in Flutter](platforms/flutter.md#closing-ditto-in-flutter), [Closing Ditto in JavaScript](platforms/javascript.md#closing-ditto-in-javascript), [Closing Ditto in Kotlin](platforms/kotlin.md#closing-ditto-in-kotlin), and [Closing Ditto in Swift](platforms/swift.md#closing-ditto-in-swift)):

| Object | Release it when | Notes |
|---|---|---|
| The `Ditto` instance | The whole app no longer needs Ditto | Closing also releases everything below and stops sync |
| Store observers | Their screen or owner goes away | See [Observer Lifecycle](observers.md#observer-lifecycle) |
| Sync subscriptions | The device no longer needs their data | Required to stop syncing the data they matched |
| Presence observers and transport condition observers | Their screen or feature goes away | |
| Attachment fetchers | You cancel a fetch in progress | Not needed after a fetch has completed |
| The connection request handler | You no longer filter incoming connections | Set it to none |

Each SDK can list what is still registered, such as the store's observers and attachment fetchers. A count that keeps growing while the user moves between screens points to an observer that is never released.

What closing does:
- **It is final** for the instance. Closing twice is safe, but every other call on a closed instance fails, and in Swift, where releasing the last reference shuts the instance down, some calls end the process (see [In Swift, calls after the instance is released throw or end the process](../knowledge/observations/swift-sdk.md#in-swift-calls-after-the-instance-is-released-throw-or-end-the-process)). Open a new instance if the app needs Ditto again.
- **It stops sync** and releases observers, subscriptions, and other resources.
- **What it does with your pending work differs by SDK**, so await your own pending work, and let open transactions end, before closing on every SDK:

| | Flutter | JavaScript | Kotlin | Swift (releasing the last reference) |
|---|---|---|---|---|
| An open transaction | `close()` stops the isolate, which in an app is the UI | `close()` waits for it | `close()` waits for it | The release waits about 1 second, and the transaction commits |
| Writes still in flight | Their `Future`s fail; the writes were stored only if `execute` had run before | `close()` completes them | Stored, also when the call throws | On 5.2.0, most fail |

  In our testing with SDK 5.1.0 and 5.2.0 (see [In Flutter, close() while a transaction is open stops the app's isolate](../knowledge/observations/flutter-sdk.md#in-flutter-close-while-a-transaction-is-open-stops-the-apps-isolate), [In Flutter, close() fails pending execute calls, also writes that it stores](../knowledge/observations/flutter-sdk.md#in-flutter-close-fails-pending-execute-calls-also-writes-that-it-stores), [In JavaScript, close() waits for open transactions](../knowledge/observations/javascript-sdk.md#in-javascript-close-waits-for-open-transactions), [In JavaScript, close() completes pending writes](../knowledge/observations/javascript-sdk.md#in-javascript-close-completes-pending-writes), [In Kotlin, close() waits for an open transaction](../knowledge/observations/kotlin-sdk.md#in-kotlin-close-waits-for-an-open-transaction), [In Kotlin, writes in flight when close() runs are stored even when the call throws](../knowledge/observations/kotlin-sdk.md#in-kotlin-writes-in-flight-when-close-runs-are-stored-even-when-the-call-throws), [In Swift, releasing the last reference shuts Ditto down at once](../knowledge/observations/swift-sdk.md#in-swift-releasing-the-last-reference-shuts-ditto-down-at-once), and [In Swift 5.2.0, writes in flight fail when the instance is released](../knowledge/observations/swift-sdk.md#in-swift-520-writes-in-flight-fail-when-the-instance-is-released)). A write whose call failed may still have been stored, so do not retry such writes blindly: read first, or make the write an upsert.
- **It does not wait for changes that are still being sent.** An awaited write is in the local store, but it may not have reached any other device yet. `sync.stop()` does not wait for them either. Such changes stay on the device and sync the next time it syncs.

> **Note (SDK 5.1.0 and 5.2.0):** An awaited write is in the local store, but closing, `sync.stop()`, and ending the app do not wait until it has been sent. In our testing, a 1 MB document written right before any of them never reached the hub, and a 100-byte document did in most runs but not in all; when the device first waited until the hub's `synced_up_to_local_commit_id` reached the write's `commitID`, every write arrived (see [A write made right before close or stop may not leave the device](../knowledge/observations/subscriptions-and-replication.md#a-write-made-right-before-close-or-stop-may-not-leave-the-device)). A write that did not leave the device is sent the next time it syncs, so it is lost only if the device never syncs again, for example because its store is deleted. Before you close Ditto at a point where data must reach another device (logout, the end of a shift, before deleting the local store), wait with a timeout until the write is confirmed, and tell the user if unsent changes remain:

```sql
-- Poll until Ditto Server has confirmed the write: done when
-- documents.synced_up_to_local_commit_id >= the write's commitID
SELECT * FROM system:data_sync_info WHERE is_ditto_server = true
```

Give each read of this collection its own deadline as well: in our testing with the JavaScript and Swift SDKs on 5.1.0 and 5.2.0, and with the Kotlin SDK on 5.1.0, such a read sometimes never returned (see [Monitoring Sync Status](sync-and-subscriptions.md#monitoring-sync-status), [In JavaScript, a read of system:data_sync_info can stop responding](../knowledge/observations/javascript-sdk.md#in-javascript-a-read-of-systemdata_sync_info-can-stop-responding), [In Swift, a read of system:data_sync_info can stop responding](../knowledge/observations/swift-sdk.md#in-swift-a-read-of-systemdata_sync_info-can-stop-responding), and [On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](../knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)).

The code for waiting until a write is confirmed and for shutting down in order: [Flutter](platforms/flutter.md#closing-ditto-in-flutter) · [JavaScript](platforms/javascript.md#closing-ditto-in-javascript) · [Kotlin](platforms/kotlin.md#closing-ditto-in-kotlin) · [Swift](platforms/swift.md#closing-ditto-in-swift).

## Transport Configuration

**Change transports by updating the current transport configuration; never replace it with a new, empty one, which disables every transport.** A new Ditto instance enables the peer-to-peer transports of its platform: in our testing with SDK 5.1.0 and 5.2.0, Bluetooth LE, LAN, and AWDL on macOS and iOS (also with the JavaScript SDK on Node.js on macOS), and Bluetooth LE, LAN, and Wi-Fi Aware on Android. Ditto's documentation says that a new instance enables all peer-to-peer transports, but Wi-Fi Aware stayed disabled on macOS (see [A new instance enables the platform's peer-to-peer transports, and an empty configuration enables none](../knowledge/observations/connections-and-presence.md#a-new-instance-enables-the-platforms-peer-to-peer-transports-and-an-empty-configuration-enables-none)). When you connect to Ditto Server, the Server URL is used automatically; you do not need to add it to the transport configuration.

The transport configuration has the same structure in every SDK: `peerToPeer` (Bluetooth LE, LAN, AWDL, Wi-Fi Aware), `connect` (TCP servers, WebSocket URLs, and the retry interval; the field names follow each SDK's conventions, for example `webSocketUrls` in Flutter and `websocketURLs` in JavaScript), `listen` (`tcp`, `http`), and `global`. Each SDK offers an update call that starts from the current configuration (`updateTransportConfig`; see [Transports and Presence in Flutter](platforms/flutter.md#transports-and-presence-in-flutter), [JavaScript](platforms/javascript.md#transports-and-presence-in-javascript), [Kotlin](platforms/kotlin.md#transports-and-presence-in-kotlin), and [Swift](platforms/swift.md#transports-and-presence-in-swift)).

**✅ DO:**
- Update the current configuration and change only the settings you need.
- Enable or disable all peer-to-peer transports at once, or individual transports through `peerToPeer`.
- Observe transport conditions to detect missing permissions or disabled radios.
- Configure each TCP link in one direction only: the hub listens, and the clients list the hub in `connect.tcpServers`.
- On a hub that more than six devices connect to over TCP, raise the TCP connection limit on the hub so that it is in effect before sync starts (see the note below).

**❌ DON'T:**
- Build a new transport configuration from scratch and assign it: a new configuration has **every transport disabled**, including the peer-to-peer transports that a default instance enables (in our testing with every SDK on SDK 5.1.0 and 5.2.0; see [A new instance enables the platform's peer-to-peer transports, and an empty configuration enables none](../knowledge/observations/connections-and-presence.md#a-new-instance-enables-the-platforms-peer-to-peer-transports-and-an-empty-configuration-enables-none)).
- Use `MESH_CHOOSER_AT_CAPACITY_ACTION` to admit more TCP clients than the limit; the hub keeps replacing connections (see the note below).
- Treat `global.syncGroup` as a security boundary. It is an optimization only: in our testing, devices in different sync groups still synced when they were connected explicitly (see [Relay, rewrite, and subscription behavior held on SDK 5.1.0 and 5.2.0](../knowledge/observations/subscriptions-and-replication.md#relay-rewrite-and-subscription-behavior-held-on-sdk-510-and-520)).

> **Note (SDK 5.1.0 and 5.2.0):** A device accepts a limited number of connections per transport. For TCP, the limit is 6 by default (system parameter `MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In our testing with a TCP hub and eight clients, the hub accepted six, and the remaining two received no data at all; no API reported this, and only the log showed a `WARN` line, `failed to connect to peer error=... at capacity for this transport` (see [A device accepts six TCP connections by default](../knowledge/observations/connections-and-presence.md#a-device-accepts-six-tcp-connections-by-default)).
>
> On 5.2.0, a device also counts the connections that it opened itself when it decides whether to accept another one (the 5.2.0 release notes describe this as counting accepted and outgoing LAN connections together). In our testing, a hub that also connected to two other devices dropped two of its six clients on 5.2.0, and a relay that connected to an upstream hub accepted only five clients (see [SDK 5.2.0 counts outgoing connections toward the TCP limit](../knowledge/observations/connections-and-presence.md#sdk-520-counts-outgoing-connections-toward-the-tcp-limit)). Outgoing connections themselves are not limited (see [Outgoing TCP connections are not limited](../knowledge/observations/connections-and-presence.md#outgoing-tcp-connections-are-not-limited)), and the default is still 6.
>
> A client that the hub did not accept appears in no device's presence graph, so presence shows correctly that it is not connected (see [The presence graph includes indirect peers and all of their connections](../knowledge/observations/connections-and-presence.md#the-presence-graph-includes-indirect-peers-and-all-of-their-connections)). Two devices that listed each other in `connect.tcpServers` kept two TCP connections. When every device lists every other device, a device on 5.2.0 kept 3 to 7 direct connections (6 to 9 TCP connections), so a mesh of seven or more devices was not fully connected, although every device still listed all the others in `remotePeers` and changes reached every device within 24 to 80 ms through the others; on 5.1.0, devices kept up to 15 TCP connections, many of them duplicates (in our testing; see [On SDK 5.2.0, devices in a full TCP mesh of seven or more keep 3 to 7 direct connections](../knowledge/observations/connections-and-presence.md#on-sdk-520-devices-in-a-full-tcp-mesh-of-seven-or-more-keep-3-to-7-direct-connections)). Count devices with `remotePeers`, not with direct connections.
>
> `MESH_CHOOSER_AT_CAPACITY_ACTION` decides what a full hub does when another client arrives. It takes an integer (a string such as `'DropOldest'` is rejected), and with the default, 0, the extra client never connected. According to the 5.2.0 release notes, the settings that drop the oldest or the newest peer wait until the new peer has finished connecting. In our testing with the values 1 and 2, every client received data, but the hub kept replacing connections in a 5-second cycle, and at every check, at least one client was not connected (on 5.2.0, and on 5.1.0 with 2; on 5.1.0 with 1, the cycle stopped in some runs; see [At-capacity actions 1 and 2 admit extra clients but keep replacing connections](../knowledge/observations/connections-and-presence.md#at-capacity-actions-1-and-2-admit-extra-clients-but-keep-replacing-connections)). Raise `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` instead.
>
> If more than six devices connect to one hub, raise the limit **on the hub** so that it is in effect **before** sync starts: pass it in the system parameters of `DittoConfig` (SDK 5.2+), or on SDK 5.1 run `ALTER SYSTEM` after opening Ditto and before you start sync. In our testing, raising it after sync had started did not admit the rejected clients, even after 60 seconds (see [Raising the TCP limit takes effect only before sync starts](../knowledge/observations/connections-and-presence.md#raising-the-tcp-limit-takes-effect-only-before-sync-starts)).

> **Note (SDK 5.1.0 and 5.2.0):** A device that only connects over TCP also accepts connections. In our testing with the JavaScript SDK on macOS, a device with only `connect.tcpServers` set listened for TCP on all interfaces at a free port, and another device could connect to it and sync (see [A device that only connects over TCP also listens for TCP connections](../knowledge/observations/connections-and-presence.md#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)). To accept no TCP connections from other devices, enable `listen.tcp` with `interfaceIP` set to `127.0.0.1` (`port` 0 picks a free port). Only devices with the same Database ID and valid credentials can sync, so this matters most for small-peers-only deployments without a shared key and for network reviews.

**Hub load**: the CPU that a hub spends on each change grows with the number of devices connected to it, even when no other device subscribes to the changed document. In our testing on a 14-core Mac, one change cost the hub at most about 6 ms of CPU with one client and about 40 ms with 30 clients, and 30 clients that each wrote 5 times a second used about 2.6 cores (see [Hub CPU per change grows with the number of connected devices](../knowledge/observations/performance-measurements.md#hub-cpu-per-change-grows-with-the-number-of-connected-devices)). Before you use a mobile device as a hub, estimate the number of clients and how often they write, and write frequently changing values (positions, sensor readings) less often or in batches.

**Replacing a hub**: a new, empty hub device recovers the data from its clients, including their tombstones, so deleted documents stay deleted (until the tombstones are reaped, see [Tombstone TTL and reaping](deletion-and-storage.md#tombstone-ttl-and-reaping)). Documents that only the old hub held are not recovered (in our testing; see [A new, empty hub recovers the data from its clients](../knowledge/observations/subscriptions-and-replication.md#a-new-empty-hub-recovers-the-data-from-its-clients)). Back up data that only the hub writes, or let a client subscribe to it.

Changes of `connect.tcpServers` and of the TCP listener take effect while sync is running, without stopping and starting sync: in our testing, a device connected or disconnected within about 50 to 150 ms (see [TCP targets and listeners change while sync runs](../knowledge/observations/connections-and-presence.md#tcp-targets-and-listeners-change-while-sync-runs)). System parameters such as `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` are different: raising the limit after sync had started had no effect.

A device that loses a TCP connection, or fails to connect, tries again after `connect.retryInterval` (5 seconds by default): in our testing, clients reconnected to a restarted hub about 4 seconds after it was open again with the default, and about 1.1 seconds with an interval of 1 second (see [A lost TCP connection is retried at the retry interval](../knowledge/observations/connections-and-presence.md#a-lost-tcp-connection-is-retried-at-the-retry-interval)). A shorter interval suits devices that must stay connected to a hub, such as the terminals of a store.

Configuration changes are applied asynchronously while sync is running, and invalid values do not fail: an invalid `connect.tcpServers` entry or listen address only produces a log line (for example `Failed to start TCP server error=Bind address could not be parsed`). You can also point devices at a known peer with the `TRANSPORTS_DISCOVERED_PEERS` system parameter, which can be set before or after sync starts and is validated (`type` is optional and must be `'force'` or `'candidate'`). It works only while the LAN transport (`peerToPeer.lan`) is enabled on the device that sets it, which is the default; with peer-to-peer transports disabled, the value is stored but nothing connects, so use `connect.tcpServers` instead. Like every system parameter, it is not persisted: pass a fixed address in the system parameters of `DittoConfig` (SDK 5.2+), or set it with `ALTER SYSTEM` after each open, for example when the address is discovered at run time:

```sql
ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS = [{'address': 'tcp://192.168.1.10:4040', 'type': 'force'}]
```

**WebSocket sync between Small Peers** (accepting WebSocket connections on the HTTP listener) is **off by default** (`listen.http.websocketSync = false`). Enable it only when you need it and configure TLS (`tlsKeyPath` and `tlsCertificatePath`); without them the listener uses plain HTTP.

Connections that a hub accepts over WebSocket do not count toward its TCP limit. In our testing with SDK 5.0.3, 5.1.0, and 5.2.0, a Small Peer hub that accepted WebSocket connections synced with all of 30 clients, while over TCP it served six, and with its TCP limit lowered to 2, it still served 8 WebSocket clients next to 2 TCP clients (see [WebSocket connections to a Small Peer hub do not count toward the TCP limit](../knowledge/observations/connections-and-presence.md#websocket-connections-to-a-small-peer-hub-do-not-count-toward-the-tcp-limit)). This is an alternative to raising `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` for hubs with more clients, with limits of its own: Ditto does not document a limit for WebSocket connections, we tested at most 30 clients on one machine without TLS, and a WebSocket connection that stops responding takes about 15 seconds to be dropped, against about 7 for TCP (see [Key Characteristics](../knowledge/understanding-ditto.md#key-characteristics) and [Each device sends over one of two connections and waits when it stalls](../knowledge/observations/connections-and-presence.md#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)). Test the number of devices you plan before you rely on it.

The code for the transport configuration, a TCP hub and its clients, and a hub with a raised limit: [Flutter](platforms/flutter.md#transports-and-presence-in-flutter) · [JavaScript](platforms/javascript.md#transports-and-presence-in-javascript) · [Kotlin](platforms/kotlin.md#transports-and-presence-in-kotlin) · [Swift](platforms/swift.md#transports-and-presence-in-swift).

### Diagnosing transport problems (SDK 5.1+)

Because configuration changes do not fail, observing the transport conditions is the way to see why a transport is not working: missing Bluetooth permissions, Bluetooth or Wi-Fi turned off, no BLE hardware, the app being in the background, mDNS or TCP listen failures, and so on. Stop the observer when you no longer need it. On Android, the SDK also reports which runtime permissions Ditto needs and which are missing; request them before you start sync. Since SDK 5.2, the list of required permissions covers only the generally available transports; the permissions for multicast are returned separately (see [Multicast (Beta) (SDK 5.1+)](#multicast-beta-sdk-51)).

### Multicast (Beta) (SDK 5.1+)

Multicast is an opt-in transport that sends each update once to a multicast group instead of once per connection, which reduces connection overhead in dense deployments. It is a private beta feature: **use it only in coordination with Ditto support**. It is configured through `peerToPeer.multicastBeta` and requires additional platform entitlements and permissions (for example the multicast entitlement on iOS and `CHANGE_WIFI_MULTICAST_STATE` on Android). It is not available on the Web or on Windows, and changes made while sync is active take effect only after sync is stopped and started again. On Android with SDK 5.2+, the multicast permissions are no longer part of the list of required permissions; request them separately.

## Presence

`ditto.presence` shows which peers this device can see and how it is connected to them, which is useful for connection indicators and diagnostics.

- Observing presence returns an observer. The callback is called with the current graph shortly after you start observing (asynchronously), and again whenever peers appear, disappear, or change their connections. Stop the observer when you no longer need it.
- Updates are batched: in our testing, callbacks arrived about once per second, also while many peers kept coming and going, so a change reached the callback within about 1 second and one callback can cover several changes (see [Presence reports a joining peer after about 1.2 seconds](../knowledge/observations/connections-and-presence.md#presence-reports-a-joining-peer-after-about-12-seconds) and [Presence callbacks stay at about one per second while peers come and go](../knowledge/observations/connections-and-presence.md#presence-callbacks-stay-at-about-one-per-second-while-peers-come-and-go)). Show a connection state only after it has held for a few seconds, not the raw count of `remotePeers`, which swings while peers come and go. The callback is also called with an unchanged graph, so compare the graph with the previous one before you update the UI.
- The graph's `localPeer` describes this device, and `remotePeers` lists the other known peers, including peers that are reachable only through other peers. Each peer has a peer key, a device name, whether it is connected to Ditto Server, its connections, and its peer metadata. To tell direct neighbors apart, check whether one of a peer's connections has this device's peer key at one of its ends: a remote peer's connections list all of that peer's connections, not only the one to this device. The connection type has no TCP value; TCP connections, including those to a hub, are reported as `accessPoint` (in our testing with the JavaScript SDK; see [The presence graph includes indirect peers and all of their connections](../knowledge/observations/connections-and-presence.md#the-presence-graph-includes-indirect-peers-and-all-of-their-connections)).
- `presence.graph` returns the current graph once, without observing.
- A peer that stops responding without closing its connection stays in the graph for several seconds: in our testing over TCP, about 7 seconds after the network went silent, while a shorter outage was not noticed at all, and about 9 seconds for a suspended process; a process that ended disappeared at once (see [A silent network outage removes a peer after about 7 seconds](../knowledge/observations/connections-and-presence.md#a-silent-network-outage-removes-a-peer-after-about-7-seconds) and [A suspended device leaves the presence graph after about 9 seconds](../knowledge/observations/connections-and-presence.md#a-suspended-device-leaves-the-presence-graph-after-about-9-seconds)). Other transports, such as Bluetooth LE, may take a different time; expect a connection indicator to lag by this much.
- A peer in the graph is not necessarily up to date: over a slow link, a peer that was transferring a large attachment stayed in the graph while other changes waited behind the transfer (see [Slow links keep the connection and the presence entry](../knowledge/observations/connections-and-presence.md#slow-links-keep-the-connection-and-the-presence-entry)). Two connections to a peer in the graph do not mean that sync continues when one of them stalls (see [Each device sends over one of two connections and waits when it stalls](../knowledge/observations/connections-and-presence.md#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)).
- `presence.peerMetadata` sets metadata for this device (a JSON object of at most 4096 bytes when encoded; larger values fail). It reaches every peer in the mesh, but a peer that has just appeared can show empty metadata until its metadata arrives. Setting it again replaces the whole object; keys are not merged. Changes reach other peers about once per second, as the value current at that moment, so intermediate values are skipped (in our testing; see [Peer metadata changes reach other peers about once per second](../knowledge/observations/connections-and-presence.md#peer-metadata-changes-reach-other-peers-about-once-per-second)).
- `ditto.deviceName` is the name that other peers see as the peer's device name. Its default depends on the SDK: according to the API references, Flutter derives it from the device model and JavaScript from the host name (on Node.js, it was the host name). Names longer than 24 bytes are truncated, in Flutter when you set them and in JavaScript when sync starts. Set it before you start sync: in our testing, a change made while sync was running did not reach other peers until sync was stopped and started again (see [Peer metadata is replaced, not merged, and the device name is read when sync starts](../knowledge/observations/connections-and-presence.md#peer-metadata-is-replaced-not-merged-and-the-device-name-is-read-when-sync-starts)). Other peers also see each peer's `os` and `dittoSdkVersion`, which helps to find devices that run an older SDK (see [Presence shows each peer's SDK version](../knowledge/observations/connections-and-presence.md#presence-shows-each-peers-sdk-version)).

**✅ DO:**
- Stop presence observers when the screen or feature that uses them goes away.
- Keep peer metadata small and non-sensitive, such as a role or a display name. Every connected device receives about twice its size whenever a device joins or changes it: in our testing over TCP, 3 KB of metadata cost each device about 6 KiB per change (see [Presence traffic carries each peer's metadata, and idle traffic grows faster than the number of devices](../knowledge/observations/connections-and-presence.md#presence-traffic-carries-each-peers-metadata-and-idle-traffic-grows-faster-than-the-number-of-devices)). Write large or frequently changing values (positions, task state) to documents instead.
- Set peer metadata once at startup (for example `{"role": "cashier"}`), not from individual screens. Other peers see at most about one change per second.
- Set the device name to a name that identifies the device for your support staff and not a person, before you start sync.

**❌ DON'T:**
- Put secrets, tokens, or personal data in peer metadata. Peer metadata, and the `identityServiceMetadata` returned by your authentication webhook, are shared with every peer in the mesh, not only with directly connected peers.

The code for a list of connected peers: [Flutter](platforms/flutter.md#transports-and-presence-in-flutter) · [JavaScript](platforms/javascript.md#transports-and-presence-in-javascript) · [Kotlin](platforms/kotlin.md#transports-and-presence-in-kotlin) · [Swift](platforms/swift.md#transports-and-presence-in-swift).
