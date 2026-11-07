# Ditto on Kotlin

This page shows how to apply the guide with the Kotlin SDK, `com.ditto:ditto-kotlin` 5.2.0 on Android: the API calls, the patterns for app components, coroutines, and the Android lifecycle, and the behavior that is specific to this SDK. The rules themselves, the DQL, and the reasons are on the topic pages of the guide, which apply to every SDK; each section below links to them. The same sections exist for [Flutter](flutter.md), [JavaScript](javascript.md), and [Swift](swift.md).

Every example assumes these imports, and shows any other import it needs:

```kotlin
import com.ditto.kotlin.*
import com.ditto.kotlin.serialization.*
import com.ditto.kotlin.transports.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
```

Placeholders such as `"YOUR_DATABASE_ID"`, `fetchAuthToken()`, and `showError()` stand for values and code from your own app. Classes that own observers receive a `CoroutineScope`: in an Android `ViewModel`, pass `viewModelScope`, and in an app-wide service, a scope that lives as long as the app.

## Installing the Kotlin SDK

`com.ditto:ditto-kotlin` 5.2.0 has the following requirements:

| Item | Requirement |
|---|---|
| Android | 7.0 or later (`minSdk` 24) |
| `compileSdk` | 36 |
| JDK | 17 |
| Kotlin | 2.0 or later; Ditto supports the four most recent stable Kotlin releases |
| Repository | Maven Central |
| Android Emulator | Supported; of the transports, the Ditto documentation lists only WebSocket for it (no Bluetooth LE, LAN discovery, or Wi-Fi Aware) |

Pin the exact version in your app's Gradle file so every developer and CI build uses the same release:

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("com.ditto:ditto-kotlin:5.2.0")
}
```

**Android context**: `DittoConfig` takes no `Context`. The SDK receives the application context through AndroidX Startup (`DittoInitializer`) when the app starts, so do not remove that initializer from the merged manifest.

**Permissions**: the SDK's `AndroidManifest.xml` declares the Bluetooth, Wi-Fi, location, and nearby-device permissions that peer-to-peer sync needs, and they are merged into your app's manifest. Request the runtime permissions that are still missing before you start sync, and call `ditto.refreshPermissions()` when the user has granted them, so that Ditto starts using them at once. `DittoSyncPermissions` reports which ones are missing (see the [Kotlin install guide](https://docs.ditto.live/sdk/latest/install-guides/kotlin)):

```kotlin
import android.content.Context

/** The runtime permissions Ditto needs that the user has not granted yet; request them before sync starts. */
fun missingDittoPermissions(context: Context): Array<String> =
    DittoSyncPermissions(context).missingPermissions()

/** Call from the permission request's result callback. */
fun onDittoPermissionsResult(ditto: Ditto) {
    ditto.refreshPermissions() // Ditto picks up newly granted permissions at once.
}
```

**Release builds with R8**: keep Ditto's classes, which the native library reaches through JNI, and the platform certificate verifier, which TLS connections to Ditto Server need. Without these rules, a minified build crashes with errors such as `NoSuchMethodError: no static method "Lcom/ditto/internal/dittoffi/DittoFFI;..."`:

```text
-keep class com.ditto.** { *; }
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
```

## Opening Ditto in Kotlin

- `DittoFactory.create(config)` creates the instance. It is not a suspending function, needs no separate initialization, and throws a `DittoException` when the instance cannot be opened. The Kotlin SDK has no `Ditto.open`.
- `DittoFactory.create(config, coroutineScope)` takes the `CoroutineScope` in which Ditto calls your code: observer handlers, the authentication expiration handler, and connection request handlers. On Android, the default scope is `MainScope()`, so **these handlers run on the main thread** unless you pass another scope (see [In Kotlin, observer handlers run on the main thread unless DittoFactory.create gets another scope](../../knowledge/observations/kotlin-sdk.md#in-kotlin-observer-handlers-run-on-the-main-thread-unless-dittofactorycreate-gets-another-scope)).
- `ditto.close()` releases the instance (see [Closing Ditto in Kotlin](#closing-ditto-in-kotlin)).

```kotlin
// ✅ GOOD: Observer and auth handlers run on Dispatchers.Default instead of the
// main thread. Switch to Dispatchers.Main only to touch views.
fun openWithBackgroundHandlers(config: DittoConfig): Ditto =
    DittoFactory.create(config, CoroutineScope(SupervisorJob() + Dispatchers.Default))
```

With the default scope, keep handlers short or move their work off the main thread with `withContext(Dispatchers.Default)`; a handler that blocks freezes the UI.

### DittoConfig in Kotlin

`DittoConfig` is immutable: its properties are `val`s. Its fields, as described in [DittoConfig](../setup-and-lifecycle.md#dittoconfig):

| Field | Type | Default | Kotlin specifics |
|---|---|---|---|
| `databaseId` | `String` | required | |
| `connect` | `DittoConfig.Connect` | required | `DittoConfig.Connect.Server(url = ...)` or `DittoConfig.Connect.SmallPeersOnly(privateKey = ...)` |
| `persistenceDirectory` | `String?` | `null` | `null` uses a directory named `ditto-<databaseId>` in the app's storage |
| `experimental` | `DittoConfig.Experimental` | defaults | |
| `encryptionKey` (SDK 5.2+) | `DittoEncryptionKey?` | `null` | `DittoEncryptionKey.raw(bytes)` with exactly 32 bytes |
| `systemParameters` (SDK 5.2+) | `Map<String, Any>` | empty | An unknown name or a wrong type makes `DittoFactory.create` throw `DittoException.ValidationException` (in our testing; see [System parameters passed in DittoConfig take effect when Ditto.open returns](../../knowledge/observations/configuration-and-diagnostics.md#system-parameters-passed-in-dittoconfig-take-effect-when-dittoopen-returns)) |

The errors that `DittoFactory.create` throws for configuration and encryption problems (see [In Kotlin, an invalid configuration or a wrong encryption key makes create() throw](../../knowledge/observations/kotlin-sdk.md#in-kotlin-an-invalid-configuration-or-a-wrong-encryption-key-makes-create-throw)):

| Problem | Exception and message |
|---|---|
| Unknown system parameter | `DittoException.ValidationException`: `Invalid DittoConfig: unknown parameter 'not_a_parameter'` |
| Wrong type of a system parameter | `DittoException.ValidationException`: `... type error: value String("yes") doesn't match system parameter dql_strict_mode type of bool` |
| Encrypted store opened without a key | `DittoException.EncryptionException`: `no encryption key was provided while required.` |
| Encrypted store opened with another key | `DittoException.EncryptionException`: `wrong encryption key provided` |
| Unencrypted store opened with a key | `DittoException.EncryptionException`: `an encryption key was provided while not required.` |
| A key that is not 32 bytes | `IllegalArgumentException` from `DittoEncryptionKey.raw`: `encryption key must be exactly 32 bytes` |

```kotlin
// ✅ GOOD: Small-peers-only deployment. The shared key and the offline license
// token (issued by Ditto) come from secure provisioning, never from source code.
suspend fun openProvisionedSmallPeer(
    readKeyFromSecureStorage: suspend () -> String,
    readLicenseFromSecureStorage: suspend () -> String,
): Ditto {
    val ditto = DittoFactory.create(
        DittoConfig(
            databaseId = "YOUR_DATABASE_ID", // any UUID shared by all peers
            connect = DittoConfig.Connect.SmallPeersOnly(privateKey = readKeyFromSecureStorage()),
        ),
    )
    // Required before sync.start() in small-peers-only mode.
    ditto.setOfflineOnlyLicenseToken(readLicenseFromSecureStorage())
    ditto.sync.start() // no expiration handler is needed in this mode
    return ditto
}
```

Pass system parameters on every open (see [Applying System Parameters](../setup-and-lifecycle.md#applying-system-parameters)):

```kotlin
import android.util.Log

// ✅ GOOD: Pass settings on every open. Ditto applies them before it starts,
// and a misspelled name or a wrong type makes DittoFactory.create() throw.
suspend fun openWithSystemParameters(
    strictMode: Boolean, // true only for apps that opt into strict mode
): Ditto {
    val ditto = DittoFactory.create(
        DittoConfig(
            databaseId = "YOUR_DATABASE_ID",
            connect = DittoConfig.Connect.Server(url = "YOUR_SERVER_URL"),
            systemParameters = buildMap<String, Any> {
                if (strictMode) put("DQL_STRICT_MODE", true)
            },
        ),
    )

    // Confirm the effective value. SHOW returns one row keyed by the
    // lowercase parameter name.
    val effective = ditto.store.execute("SHOW DQL_STRICT_MODE") { result ->
        result.items.first().value["dql_strict_mode"].booleanOrNull
    }
    Log.d("App", "dql_strict_mode = $effective")
    return ditto
}
```

Pass sync scopes the same way, so that they are in effect before sync starts (see [Sync Scopes](../sync-and-subscriptions.md#sync-scopes)):

```kotlin
// ✅ GOOD: Pass sync scopes in the configuration on every open (SDK 5.2+),
// so that they are in effect before sync starts.
val scopedConfig = DittoConfig(
    databaseId = "YOUR_DATABASE_ID",
    connect = DittoConfig.Connect.Server(url = "YOUR_SERVER_URL"),
    systemParameters = mapOf(
        "USER_COLLECTION_SYNC_SCOPES" to mapOf(
            "localDrafts" to "LocalPeerOnly",
            "kitchenTickets" to "SmallPeersOnly",
        ),
    ),
)
```

```kotlin
// ❌ BAD: No privateKey means peers are not authenticated (and the SDK
// documents the mode as unencrypted); a key in source code would be visible
// to anyone who decompiles the app.
fun openUnprotectedSmallPeer(): Ditto =
    DittoFactory.create(
        DittoConfig(
            databaseId = "YOUR_DATABASE_ID",
            connect = DittoConfig.Connect.SmallPeersOnly(),
        ),
    )
```

**Encryption at rest (SDK 5.2+)**: pass a 32-byte key that your app generates and keeps in secure storage, never next to the store it protects (see [Data at Rest](../security.md#data-at-rest)). The key cannot be added to or removed from an existing store: a store created without a key fails to open with one, and the other way round.

```kotlin
// ✅ GOOD: Encrypt the local store with a key from secure storage (SDK 5.2+).
fun openEncryptedStore(loadKeyFromSecureStorage: () -> ByteArray): Ditto {
    val key = DittoEncryptionKey.raw(loadKeyFromSecureStorage()) // exactly 32 bytes
    return try {
        DittoFactory.create(
            DittoConfig(
                databaseId = "YOUR_DATABASE_ID",
                connect = DittoConfig.Connect.Server(url = "YOUR_SERVER_URL"),
                encryptionKey = key,
            ),
        )
    } catch (error: DittoException.EncryptionException) {
        // A missing, wrong, or unexpected key. Do not delete the store
        // automatically: report it, and recover the right key if you can.
        showError(error)
        throw error
    }
}
```

### One shared instance in Kotlin

`DittoFactory.create` is synchronous, so a lazily created instance in the `Application` is enough; a failed attempt is not cached, so the next caller retries (see [One instance per persistence directory](../setup-and-lifecycle.md#one-instance-per-persistence-directory)). Keep the instance in the `Application`, not in an `Activity` or `Fragment`, which Android recreates, for example when the screen rotates.

```kotlin
// ✅ GOOD: One shared instance; concurrent callers get the same one.
class DittoProvider(private val config: DittoConfig) {
    @Volatile private var ditto: Ditto? = null

    fun instance(): Ditto =
        ditto ?: synchronized(this) {
            // A failed create() throws and leaves ditto null, so the next call retries.
            ditto ?: DittoFactory.create(config).also { ditto = it }
        }
}
```

```kotlin
// ❌ BAD: Every call opens the same directory again. While the first instance
// is open, create() throws "File already locked" after about a second.
suspend fun loadOrdersByReopening(): List<String> {
    val ditto = DittoFactory.create(
        DittoConfig(databaseId = "YOUR_DATABASE_ID", connect = DittoConfig.Connect.SmallPeersOnly()),
    )
    return ditto.store.execute("SELECT * FROM orders") { result ->
        result.items.map { it.jsonString() }
    }
}
```

**Note (SDK 5.1.0 and 5.2.0):** In the same process, `DittoFactory.create` on a directory that is already open throws `DittoException.StoreException` (`File already locked, ... Multiple Ditto instances cannot run at the same time within the same working directory`) after about one second; it does not wait for the other instance (see [In Kotlin, opening an open directory again fails after about a second](../../knowledge/observations/kotlin-sdk.md#in-kotlin-opening-an-open-directory-again-fails-after-about-a-second)). Share the existing instance instead.

### App startup in Kotlin

The recommended order (see [Complete app startup](../setup-and-lifecycle.md#complete-app-startup)), as one service that owns the instance and its long-lived subscriptions. The `Application` starts it once in a scope that lives as long as the app:

```kotlin
import android.app.Application
import android.util.Log

// Most apps keep the default (strict mode off). See "Strict Mode".
const val ENABLE_STRICT_MODE = false

// fetchAuthToken() and showError() stand for your app's own code.

/** The production configuration. System parameters are not persisted, so they are passed on every open. */
fun appConfig(): DittoConfig = DittoConfig(
    databaseId = "YOUR_DATABASE_ID",
    // Copy the URL from the Ditto Portal exactly as shown.
    connect = DittoConfig.Connect.Server(url = "YOUR_SERVER_URL"),
    systemParameters = buildMap<String, Any> {
        if (ENABLE_STRICT_MODE) put("DQL_STRICT_MODE", true)
    },
)

class DittoService private constructor(
    val ditto: Ditto,
    private val subscriptions: List<DittoSyncSubscription>,
) {
    // Call only when the whole app no longer needs Ditto.
    fun close() {
        subscriptions.forEach { it.close() }
        ditto.close()
    }

    companion object {
        suspend fun start(config: DittoConfig, debug: Boolean): DittoService {
            // 1. Configure logging first, so that startup is logged with your settings.
            DittoLogger.minimumLogLevel = if (debug) DittoLogLevel.Debug else DittoLogLevel.Warning

            // 2. Create the single shared instance. Ditto applies the system
            //    parameters of the configuration before it starts (SDK 5.2+).
            val ditto = DittoFactory.create(config)

            // If a later step fails, close the instance before rethrowing, so
            // that the next attempt can open the directory again.
            try {
                // 3. Server connections require an expiration handler before sync.start().
                ditto.auth?.expirationHandler = { dittoInstance, _ ->
                    try {
                        dittoInstance.auth?.login(token = fetchAuthToken(), provider = "YOUR_PROVIDER_NAME")
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        showError(error) // login() throws on rejection; never rethrow here
                    }
                }

                // 4. Create the indexes your queries need before queries and
                //    observers run. Indexes persist, and IF NOT EXISTS makes
                //    this safe on every start.
                ditto.store.execute("CREATE INDEX IF NOT EXISTS idx_orders_storeId ON orders (storeId)")

                // 5. Register long-lived subscriptions, then start sync.
                val subscriptions = listOf(
                    ditto.sync.registerSubscription(
                        "SELECT * FROM orders WHERE storeId = :storeId",
                        mapOf("storeId" to "store-1"),
                    ),
                )
                ditto.sync.start() // throws DittoException if sync cannot start

                return DittoService(ditto, subscriptions)
            } catch (error: Throwable) {
                ditto.close()
                throw error
            }
        }
    }
}

class OrdersApplication : Application() {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Started once, on first use; every caller awaits the same instance. */
    val dittoService: Deferred<DittoService> by lazy {
        appScope.async { DittoService.start(appConfig(), debug = isDebuggable()) }
    }

    private fun isDebuggable(): Boolean =
        (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    override fun onCreate() {
        super.onCreate()
        appScope.launch {
            runCatching { dittoService.await() }.onFailure { Log.e("App", "Ditto failed to start", it) }
        }
    }
}
```

Create the indexes your queries rely on once per launch (see [Where indexes live](../indexing-and-performance.md#where-indexes-live)):

```kotlin
// ✅ GOOD: Create the indexes this app relies on, once per launch.
suspend fun ensureIndexes(ditto: Ditto) {
    val statements = listOf(
        "CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)",
        "CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)",
    )
    for (statement in statements) {
        try {
            ditto.store.execute(statement)
        } catch (error: DittoException) {
            // Without the index, queries that use it fall back to a collection
            // scan (and a JOIN on it fails): report and continue.
            showError(error)
        }
    }
}
```

## Authentication in Kotlin

`ditto.auth` is a `DittoAuthenticator?`: it is `null` in small-peers-only mode, so use `?.`. Assign the handler to `ditto.auth?.expirationHandler`. It is a suspending `(Ditto, Double) -> Unit`, so call `login` directly inside it; `timeUntilExpiration` is in seconds, and `0.0` means "not authenticated yet" or "already expired". With the default scope, Ditto calls it on the main thread. `login(token = ..., provider = ...)` returns the optional `clientInfo` JSON of your webhook as a `String?`. **It throws `DittoException.AuthenticationException` when your webhook rejects the token or the server is unreachable**; since SDK 5.2, its `failureCode` tells rejected credentials from retryable failures. A handler that throws is not called again for that expiration: the SDK logs `InternalDittoAuthenticator: Error in expirationHandler: ...` at the error level, and nothing reaches your code (see [In Kotlin, login() throws, and a throwing expiration handler is only logged](../../knowledge/observations/kotlin-sdk.md#in-kotlin-login-throws-and-a-throwing-expiration-handler-is-only-logged)). The rules are in [Authentication](../setup-and-lifecycle.md#authentication).

```kotlin
import android.util.Log

// ✅ GOOD: Production login with error reporting and no throwing.
// fetchAuthToken() and showError() stand for your app's own code.
fun configureAuthentication(ditto: Ditto) {
    ditto.auth?.expirationHandler = { dittoInstance, timeUntilExpiration ->
        if (timeUntilExpiration > 0.0) {
            Log.d("App", "Ditto credentials expire in $timeUntilExpiration s; refreshing")
        }
        try {
            dittoInstance.auth?.login(
                token = fetchAuthToken(), // from your identity provider/backend
                provider = "YOUR_PROVIDER_NAME", // as configured in the Ditto Portal
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: DittoException.AuthenticationException) {
            showError(error) // error.failureCode: rejected, or worth retrying
        } catch (error: Exception) {
            showError(error) // for example, fetchAuthToken() failed
        }
    }
}
```

```kotlin
// ✅ GOOD (development only): The development provider and Portal token.
fun configureDevelopmentAuthentication(ditto: Ditto, developmentToken: String) {
    ditto.auth?.expirationHandler = { dittoInstance, _ ->
        try {
            dittoInstance.auth?.login(
                token = developmentToken,
                provider = DittoAuthenticationProvider.development(),
            )
        } catch (error: DittoException.AuthenticationException) {
            showError(error)
        }
    }
}
```

```kotlin
// ❌ BAD: login() throws on rejection; the exception leaves the handler, the
// SDK only logs it, and the app never learns that login failed.
fun configureAuthenticationBadly(ditto: Ditto) {
    ditto.auth?.expirationHandler = { dittoInstance, _ ->
        dittoInstance.auth?.login(token = fetchAuthToken(), provider = "YOUR_PROVIDER_NAME")
    }
}
```

**Logging out**: `ditto.auth?.logout { ditto -> ... }` clears the credentials and stops sync, then calls the cleanup function. The cleanup function is not suspending, so run DQL statements after `logout` returns. `ditto.auth?.status` exposes `isAuthenticated` and `userId`, and `ditto.auth?.observeStatus()` returns a `StateFlow<DittoAuthenticationStatus>`.

### Switching users in Kotlin

The order of the steps is in [Switching users on a shared device](../setup-and-lifecycle.md#switching-users-on-a-shared-device).

```kotlin
// ✅ GOOD: Sign a user out of a shared device. waitUntilServerHas() is defined
// in "Closing Ditto in Kotlin"; OrderSync owns the subscriptions (see
// "Subscriptions in Kotlin").
suspend fun signOut(
    ditto: Ditto,
    orderSync: OrderSync,
    storeId: String,
    lastCommitId: ULong?,
): Boolean {
    if (lastCommitId != null && !waitUntilServerHas(ditto, lastCommitId)) {
        // Evicting now could discard changes that no other device has yet.
        showError("Some changes have not been uploaded yet. Try again online.")
        return false
    }
    // Screens close their own observers when the user leaves them.
    orderSync.leaveStore() // close first, or evicted documents sync back
    ditto.auth?.logout { } // stops sync; the cleanup function cannot suspend
    // EVICT is still allowed after logout.
    ditto.store.execute("EVICT FROM orders WHERE storeId = :storeId", mapOf("storeId" to storeId))
    ditto.store.execute("EVICT FROM orderItems WHERE storeId = :storeId", mapOf("storeId" to storeId))
    val left = ditto.store.execute(
        "SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId",
        mapOf("storeId" to storeId),
    ) { result -> result.items.first().value["n"].long }
    return left == 0L
}
```

## Sync and the App Lifecycle in Kotlin

`ditto.sync.start()` and `ditto.sync.stop()` are not suspending. `start()` throws a `DittoException` if sync cannot start; for a server connection without an expiration handler, it throws `DittoException.AuthenticationException` (`... an authentication expiration handler has not yet been set.`). After `ditto.close()`, `start()` returns without an error and does nothing (see [In Kotlin, calls after close() throw, except sync.start()](../../knowledge/observations/kotlin-sdk.md#in-kotlin-calls-after-close-throw-except-syncstart)). The rules are in [Starting and Stopping Sync](../setup-and-lifecycle.md#starting-and-stopping-sync).

```kotlin
// ✅ GOOD: Start sync only when it is not already running.
fun ensureSyncStarted(ditto: Ditto) {
    if (!ditto.sync.isActive) {
        ditto.sync.start() // throws if prerequisites are missing
    }
}
```

```kotlin
// ❌ BAD: For server connections, sync.start() throws because no expiration
// handler is set yet, so the handler below is never assigned.
fun startTooEarly(ditto: Ditto) {
    ditto.sync.start()
    ditto.auth?.expirationHandler = { _, _ -> }
}
```

Do not call `ditto.close()` when the app moves to the background: every later call on the instance fails. Without a foreground service, an Android app stops syncing in the background. To keep syncing, declare Ditto's foreground service in your manifest, as the [Kotlin install guide](https://docs.ditto.live/sdk/latest/install-guides/kotlin) describes; Ditto starts and stops it with `sync.start()` and `sync.stop()`:

```xml
<service
    android:name="com.ditto.kotlin.transports.DefaultDittoForegroundService"
    android:exported="false"
    android:foregroundServiceType="connectedDevice"
    android:stopWithTask="true" />
```

For apps that must not sync in the background, observe the process lifecycle (register the observer with `ProcessLifecycleOwner.get().lifecycle.addObserver(...)` from `androidx.lifecycle:lifecycle-process`):

```kotlin
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

// ✅ GOOD: Pause sync without closing Ditto, and resume only the sync that this
// class paused.
class SyncLifecycle(private val ditto: Ditto) : DefaultLifecycleObserver {
    private var pausedByLifecycle = false

    override fun onStop(owner: LifecycleOwner) { // the app went to the background
        if (ditto.sync.isActive) {
            ditto.sync.stop() // the local store stays usable
            pausedByLifecycle = true
        }
    }

    override fun onStart(owner: LifecycleOwner) { // the app came back
        if (pausedByLifecycle) {
            pausedByLifecycle = false
            try {
                ditto.sync.start()
            } catch (error: DittoException) {
                showError(error) // for example, prerequisites changed in the background
            }
        }
    }
}
```

## Closing Ditto in Kotlin

| Object | How to release | Notes |
|---|---|---|
| `Ditto` | `ditto.close()` | Closes everything below as well |
| `DittoStoreObserver` | `observer.close()` | Garbage collection does not stop it |
| A `Flow` from `store.observe` | Cancel the coroutine that collects it | Each collection registers its own observer |
| `store.collect` | Cancel the coroutine that calls it | |
| `DittoSyncSubscription` | `subscription.close()` | Required to stop syncing the data it matched; garbage collection does not stop it |
| `DittoQueryResult` from `executeRaw` | `result.close()`, or `use { }` | Results passed to an `execute` handler are closed for you |
| `store.fetchAttachment` | Cancel the coroutine that awaits it | Only needed to cancel a fetch in progress |
| `presence.observe()`, `transportCondition`, `DittoLogger.observeLogEvents()` | Cancel the collecting coroutine | |
| Connection request handler | `ditto.presence.connectionRequestHandler = null` | |

To find what is still registered, `ditto.store.observers` and `ditto.sync.subscriptions` list what has not been closed, including handles that the app no longer references; their elements are other objects than the ones that the registration returned, but `close()` on them works (see [In Kotlin, garbage-collected subscriptions and observers keep running](../../knowledge/observations/kotlin-sdk.md#in-kotlin-garbage-collected-subscriptions-and-observers-keep-running)). `ditto.store.attachmentFetchers` lists the active fetchers.

`ditto.close()` in Kotlin (see [In Kotlin, calls after close() throw, except sync.start()](../../knowledge/observations/kotlin-sdk.md#in-kotlin-calls-after-close-throw-except-syncstart)):
- **Is not suspending, and closing twice is safe.**
- **Closes** every observer and subscription (`isClosed` becomes `true`) and every query result that the app has not closed: reading an item of such a result afterwards throws `IllegalStateException: Query result item has already been closed.` Values that you read before `close()` stay readable.
- **After closing**, `execute` and `transaction` throw `DittoException.FatalException` (`... is not active, cannot proceed! Current state is Closed`), and registering an observer or a subscription throws `IllegalStateException: CDitto was already closed.` `sync.start()` returns without an error.
- **Waits for an open transaction** to finish (see [In Kotlin, close() waits for an open transaction](../../knowledge/observations/kotlin-sdk.md#in-kotlin-close-waits-for-an-open-transaction)). A transaction that never ends, such as a deadlocked one, therefore keeps `close()` from returning.
- **May not return on SDK 5.1.0 after a read of `system:data_sync_info` got stuck**: in our testing, it had not returned 20 seconds later (see [On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](../../knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)).
- **Writes in flight are not lost, but their calls can fail**: when `close()` runs while `execute` calls are still in progress, some of them throw `DittoException.FatalException` (`Couldn't create child of a closed resource`), although their writes were stored (see [In Kotlin, writes in flight when close() runs are stored even when the call throws](../../knowledge/observations/kotlin-sdk.md#in-kotlin-writes-in-flight-when-close-runs-are-stored-even-when-the-call-throws)). Await your own writes before closing, so that their results are known.

Before you close Ditto at a point where data must reach another device, wait with a timeout until Ditto Server has confirmed the last write (see [Resource Cleanup and Shutdown](../setup-and-lifecycle.md#resource-cleanup-and-shutdown)). Give each read its own deadline: on SDK 5.1.0, in our testing on a device connected to a peer in another process, a read of `system:data_sync_info` sometimes never completed, and later reads of it and `close()` did not complete either (see [On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](../../knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)). `store.execute` blocks the thread that calls it, so `withTimeoutOrNull` around a stuck call does not return; the helper below runs each read in a scope of its own and stops waiting for it at the deadline:

```kotlin
// Reads of system:data_sync_info run in this scope, not in the caller's.
// store.execute blocks the thread that calls it, and a read that stops
// responding cannot be cancelled: the caller stops waiting for it at its
// deadline, and the stuck read keeps one thread of Dispatchers.IO.
private val syncInfoReads = CoroutineScope(SupervisorJob() + Dispatchers.IO)

private suspend fun serverHas(ditto: Ditto, commitId: ULong): Boolean =
    syncInfoReads.async {
        ditto.store.execute(
            "SELECT * FROM system:data_sync_info WHERE is_ditto_server = true",
        ) { result ->
            result.items.any { item ->
                val synced = item.value["documents"].dictionaryOrNull?.get("synced_up_to_local_commit_id")?.longOrNull
                synced != null && synced.toULong() >= commitId
            }
        }
    }.await() // Cancelled at the caller's deadline, even while the read is stuck.

// ✅ GOOD: Wait (with a timeout) until Ditto Server has confirmed a write.
// Returns false after timeoutMillis, also when a read never completes.
suspend fun waitUntilServerHas(
    ditto: Ditto,
    commitId: ULong,
    timeoutMillis: Long = 10_000,
): Boolean {
    val confirmed = withTimeoutOrNull(timeoutMillis) {
        while (!serverHas(ditto, commitId)) delay(200)
        true
    }
    return confirmed ?: false // The change stays on the device and syncs later.
}

/** [lastCommitId] is the commitId of the last write that must be uploaded. */
suspend fun endShift(ditto: Ditto, lastCommitId: ULong?) {
    if (lastCommitId != null && !waitUntilServerHas(ditto, lastCommitId)) {
        showError("Some changes have not been uploaded yet.")
    }
    ditto.close()
}
```

```kotlin
import android.util.Log

// ✅ GOOD: Release resources in reverse order of creation, then close.
// This is app-level shutdown: call shutdown() only when the whole app no
// longer needs Ditto. Screens release their own observers and keep Ditto open.
class AppShutdown(private val ditto: Ditto, private val scope: CoroutineScope) {
    private var subscription: DittoSyncSubscription? = null
    private var observer: DittoStoreObserver? = null
    private var logJob: Job? = null

    fun start() {
        subscription = ditto.sync.registerSubscription("SELECT * FROM orders")
        observer = ditto.store.registerObserver("SELECT * FROM orders ORDER BY createdAt DESC") { result ->
            Log.d("App", "orders: ${result.items.size}")
        }
        logJob = scope.launch {
            DittoLogger.observeLogEvents().collect { event -> Log.d("Ditto", event.message) }
        }
    }

    suspend fun shutdown() {
        logJob?.cancelAndJoin()
        observer?.close()
        subscription?.close()
        ditto.close() // waits for an open transaction; does not wait for unsent changes
    }
}
```

To delete the local store (SDK 5.2+), close the instance first: `DittoFactory.deleteStore` throws `DittoException.StoreException` (`File already locked`) while the directory is open. After deleting, the directory opens as an empty store (see [In Kotlin, deleteStore fails while the store is open](../../knowledge/observations/kotlin-sdk.md#in-kotlin-deletestore-fails-while-the-store-is-open)):

```kotlin
// ✅ GOOD: Remove all local data of this database from the device (SDK 5.2+).
// persistenceDirectory is the one that the DittoConfig used; null for the default.
fun deleteLocalStore(ditto: Ditto, databaseId: String, persistenceDirectory: String?) {
    ditto.close()
    DittoFactory.deleteStore(databaseId, persistenceDirectory)
}
```

## Executing DQL in Kotlin

Pass each statement with its arguments as a `Map<String, Any?>`. **`ditto.store.execute(query, arguments)` without a handler returns `Unit`**: use it for writes whose result you do not need. To read the result, pass a handler, which receives the `DittoQueryResult` and returns what you extract from it; the result is closed when the handler returns.

| Call | Returns |
|---|---|
| `ditto.store.execute(query, arguments)` | `Unit` |
| `ditto.store.execute(query, arguments) { result -> ... }` | What the handler returns |
| `ditto.store.executeRaw(query, arguments)` | `DittoQueryResult`, which you close (see [Query results in Kotlin](#query-results-in-kotlin)) |
| `tx.execute(...)` and `tx.executeRaw(...)` inside `ditto.store.transaction` | The same (see [Transactions in Kotlin](#transactions-in-kotlin)) |
| `ditto.store.registerObserver`, `observe`, `collect` | See [Store Observers in Kotlin](#store-observers-in-kotlin) |
| `ditto.sync.registerSubscription(query, arguments)` | `DittoSyncSubscription` (see [Subscriptions in Kotlin](#subscriptions-in-kotlin)) |

Arguments can also be a `DittoCborSerializable.Dictionary`, or an object of a `@Serializable` class (with the `kotlinx.serialization` plugin). A statement that Ditto rejects throws a `DittoException` from the call itself: `execute`, `tx.execute`, `registerObserver`, and `registerSubscription` throw at once, and `observe` when its `Flow` is collected. The parser error is a `DittoException.StoreException` whose message names the cause (`<dql> Invalid query: ...`); an argument value that the SDK cannot convert throws `IllegalArgumentException` (`Cannot convert ... to cbor`) (see [In Kotlin, invalid DQL is reported by the call that receives it](../../knowledge/observations/kotlin-sdk.md#in-kotlin-invalid-dql-is-reported-by-the-call-that-receives-it) and [When a Statement Fails or Returns Nothing](../dql.md#when-a-statement-fails-or-returns-nothing)). The rules for parameters are in [Always pass values as parameters](../dql.md#always-pass-values-as-parameters).

```kotlin
// ✅ GOOD: Values travel as typed parameters. Order is defined in
// "Query results in Kotlin".
suspend fun findOrders(
    ditto: Ditto,
    customerId: String,
    statuses: List<String>,
    pageSize: Int,
): List<Order> =
    ditto.store.execute(
        "SELECT * FROM orders " +
            "WHERE customerId = :customerId AND status IN :statuses " +
            "ORDER BY createdAt DESC LIMIT :pageSize",
        mapOf("customerId" to customerId, "statuses" to statuses, "pageSize" to pageSize),
    ) { result -> result.items.map { Order.fromValue(it.value) } }
```

```kotlin
// ❌ BAD: Interpolated values (injection risk, broken quoting, no statement reuse)
suspend fun findOrdersUnsafe(ditto: Ditto, customerId: String) {
    ditto.store.execute("SELECT * FROM orders WHERE customerId = '$customerId'")
}
```

Validate values before you write them, then pass them as parameters (see [Input Validation and Query Parameters](../security.md#input-validation-and-query-parameters)):

```kotlin
// ✅ GOOD: Validate, then pass values as parameters.
suspend fun updateOrderStatus(ditto: Ditto, orderId: String, status: String) {
    val allowedStatuses = setOf("open", "preparing", "done")
    require(orderId.isNotEmpty() && status in allowedStatuses) { "Invalid order update" }
    ditto.store.execute(
        "UPDATE orders SET status = :status WHERE _id = :id",
        mapOf("id" to orderId, "status" to status),
    )
}
```

**A map key in a path**: a path cannot be passed as a parameter, so validate a map key against a strict pattern before you place it inside a backtick-quoted path segment, and pass every value as a parameter (see [Adding, updating, and removing map entries](../data-modeling.md#adding-updating-and-removing-map-entries)).

```kotlin
// Map keys used in paths are validated: only UUID-shaped keys are accepted.
private val uuidKey = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

/**
 * Removes one line item. A path cannot be passed as a parameter, so the key is
 * validated before it is placed inside a backtick-quoted path segment.
 */
suspend fun removeOrderItem(ditto: Ditto, orderId: String, itemId: String) {
    require(uuidKey.matches(itemId)) { "itemId must be a lowercase UUID: $itemId" }
    ditto.store.execute(
        "UPDATE orders UNSET items.`$itemId` WHERE _id = :id",
        mapOf("id" to orderId),
    )
}
```

**Handling the size error**: a write that would take a document over the hard size limit throws a `DittoException` (on SDK 5.2.0, a `DittoException.UnknownException`) whose message contains `exceeds limit of 5242880 bytes`; catch `DittoException` at the call site that may produce it (see [Document Size Limits](../data-modeling.md#document-size-limits) and [In Kotlin, an oversized document fails with an UnknownException](../../knowledge/observations/kotlin-sdk.md#in-kotlin-an-oversized-document-fails-with-an-unknownexception)).

```kotlin
// ✅ GOOD: Handle the size error at the call site that may produce it.
suspend fun saveNotes(ditto: Ditto, visitId: String, notes: String): Boolean =
    try {
        ditto.store.execute(
            "UPDATE visits SET notes = :notes WHERE _id = :id",
            mapOf("id" to visitId, "notes" to notes),
        )
        true
    } catch (error: DittoException) {
        // The message contains "exceeds limit of ... bytes" for oversized documents.
        showError(error) // your app's error UI
        false
    }
```

**Batched eviction**: `EVICT ... LIMIT ... RETURNING COUNT(*)` in a loop until the count is 0 (see [Batching evictions](../deletion-and-storage.md#batching-evictions)). First close or narrow every subscription that matches these documents.

```kotlin
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First close or narrow every subscription that matches these documents (see EVICT).
suspend fun evictInBatches(ditto: Ditto, cutoff: String): Long {
    var total = 0L
    while (true) {
        val evicted = ditto.store.execute(
            "EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 RETURNING COUNT(*) AS evicted",
            mapOf("cutoff" to cutoff),
        ) { result -> result.items.first().value["evicted"].long }
        total += evicted
        if (evicted == 0L) return total
    }
}
```

**Development helpers for `ADVISE` and `PROFILE`**: `ADVISE` returns one row whose `advice` map holds `suggestedIndexes` (or an `outcome` when there is nothing to suggest), and `PROFILE` appends a row with the key `~request_profile` after the normal results (see [ADVISE (SDK 5.1+)](../indexing-and-performance.md#advise-sdk-51) and [Measuring with PROFILE](../indexing-and-performance.md#measuring-with-profile)). Use these helpers during development only.

```kotlin
import android.util.Log

// ✅ GOOD (development only): print index suggestions for a query.
suspend fun printIndexAdvice(ditto: Ditto, query: String, arguments: Map<String, Any?>) {
    ditto.store.execute("ADVISE $query", arguments) { result ->
        val advice = result.items.first().value["advice"]
        val suggested = advice["suggestedIndexes"].listOrNull.orEmpty()
        if (suggested.isEmpty()) {
            Log.d("App", "No suggestions: ${advice["outcome"].stringOrNull}")
        }
        for (index in suggested) {
            Log.d("App", "${index["reason"].stringOrNull}\n  ${index["statement"].stringOrNull}")
        }
    }
}
```

```kotlin
import android.util.Log
import org.json.JSONObject

// ✅ GOOD (development only): separate the profile row from the results.
suspend fun profileQuery(ditto: Ditto, query: String, arguments: Map<String, Any?>) {
    ditto.store.execute("PROFILE $query", arguments) { result ->
        val rows = result.items.map { JSONObject(it.jsonString()) }
        val profile = rows.lastOrNull { it.has("~request_profile") }?.getJSONObject("~request_profile")
        val resultCount = rows.size - (if (profile == null) 0 else 1)
        Log.d("App", "rows=$resultCount times=${profile?.opt("times")}")
        Log.d("App", profile?.optJSONObject("plan")?.toString(2) ?: "no plan")
    }
}
```

**Execution model**: `execute` is a suspending function, but it does not move to a thread of its own: the query runs on the thread of the coroutine that calls it, and that thread is blocked until the query has finished, also while the statement waits for a write transaction. In our testing, a coroutine on the same single thread could not run while a query ran (see [In Kotlin, store.execute blocks the thread of its caller](../../knowledge/observations/kotlin-sdk.md#in-kotlin-storeexecute-blocks-the-thread-of-its-caller)). Call `execute` from `Dispatchers.IO` or `Dispatchers.Default`, not from the main thread, for anything but small queries (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution)).

```kotlin
// ✅ GOOD: A query called from UI code runs off the main thread.
suspend fun openOrderCount(ditto: Ditto): Long =
    withContext(Dispatchers.IO) {
        ditto.store.execute(
            "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
            mapOf("status" to "open"),
        ) { result -> result.items.first().value["n"].long }
    }
```

**One query instead of a loop**: each `execute` call has a fixed cost, so read a list of documents with one `_id IN :ids` query (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution)).

```kotlin
// ❌ BAD: one query per ID
suspend fun loadOrdersOneByOne(ditto: Ditto, ids: List<String>): List<Order> {
    val orders = mutableListOf<Order>()
    for (id in ids) {
        orders += ditto.store.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to id)) { result ->
            result.items.map { Order.fromValue(it.value) }
        }
    }
    return orders
}

// ✅ GOOD: one query, planned as an ID scan
suspend fun loadOrdersByIds(ditto: Ditto, ids: List<String>): List<Order> =
    ditto.store.execute("SELECT * FROM orders WHERE _id IN :ids", mapOf("ids" to ids)) { result ->
        result.items.map { Order.fromValue(it.value) }
    }
```

### Arguments and value types in Kotlin

Pass values that map to JSON: `String`, `Int`, `Long`, `Double`, `Boolean`, `null`, `ByteArray` (stored as binary), and `List`, `Set`, and `Map<String, Any?>` of them. Other types fail before the statement reaches the store, and some values change. In our testing with SDK 5.1.0 and 5.2.0 (see [Kotlin values that are not plain JSON fail or change when stored](../../knowledge/observations/kotlin-sdk.md#kotlin-values-that-are-not-plain-json-fail-or-change-when-stored)):

| Kotlin value | Result |
|---|---|
| `Long.MAX_VALUE`, integers above 2^53 | Stored and read back exactly |
| `Double`, `Float` | Stored as `float`; read back as a `FloatValue` when a 32-bit float holds the value exactly, and as a `DoubleValue` otherwise (see [Query results in Kotlin](#query-results-in-kotlin)) |
| `Double.NaN`, `Double.POSITIVE_INFINITY` | The write fails: `DittoException.StoreException: The provided query arguments were invalid.` |
| `java.util.Date`, `java.time.Instant`, `java.util.UUID`, `BigDecimal`, `BigInteger` | `IllegalArgumentException: Cannot convert ... to cbor`; pass a string instead (see [IDs and Timestamps in Kotlin](#ids-and-timestamps-in-kotlin)) |
| `Char`, an `enum` constant | Stored as a string (`'x'` as `"x"`, `Color.RED` as `"RED"`) |
| `Set` | Stored as an array |
| `null` as a map value | Stored as `null`, not left out, so `IS MISSING` no longer matches it |
| A string with a lone surrogate (`"a\uD800b"`) | Stored as `"a?b"` |

**Note (SDK 5.1.0):** Negative integers passed in map arguments were stored and compared as one less than the value (`-5` as `-6`), while the Kotlin SDK's own reads showed the value passed; `Int.MIN_VALUE` and `Long.MIN_VALUE` failed to write. SDK 5.2.0 stores them as passed but does not correct data written before (see [On Kotlin SDK 5.1.0, negative integers in map arguments were stored as one less](../../knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-negative-integers-in-map-arguments-were-stored-as-one-less) and [Known Issues in SDK 5.1.0](../../knowledge/upgrading.md#known-issues-in-sdk-510)).

To leave a field out, leave the key out of the map; do not put `null` in it (see [MISSING and NULL](../dql.md#missing-and-null)):

```kotlin
// ✅ GOOD: An optional field that has no value is left out, so IS MISSING still
// matches it; a null value would be stored as null.
suspend fun saveCustomer(ditto: Ditto, id: String, name: String, phone: String?) {
    val customer = buildMap<String, Any> {
        put("_id", id)
        put("name", name)
        if (phone != null) put("phone", phone)
    }
    ditto.store.execute(
        "INSERT INTO customers DOCUMENTS (:customer) ON ID CONFLICT DO UPDATE",
        mapOf("customer" to customer),
    )
}
```

Text that contains backslashes is safest as an argument written in a raw string (`"""..."""`), because a statement written inside a Kotlin string literal is unescaped twice, first by Kotlin and then by DQL (see [Literals](../dql.md#literals)).

```kotlin
// ✅ GOOD: The path is passed as data and stored exactly as given
suspend fun saveExportPath(ditto: Ditto) {
    ditto.store.execute(
        "UPDATE settings SET exportPath = :path WHERE _id = :id",
        mapOf("id" to "device", "path" to """C:\temp\exports"""),
    )
}
```

```kotlin
import java.time.Instant

// ❌ BAD: An Instant cannot be converted: the call throws IllegalArgumentException.
suspend fun markShippedWithInstant(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET shippedAt = :shippedAt WHERE _id = :id",
        mapOf("id" to orderId, "shippedAt" to Instant.now()),
    )
}

// ✅ GOOD: A fixed-precision UTC string (utcTimestamp() from "IDs and Timestamps in Kotlin").
suspend fun markShipped(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET shippedAt = :shippedAt WHERE _id = :id",
        mapOf("id" to orderId, "shippedAt" to utcTimestamp()),
    )
}
```

### Query results in Kotlin

A `DittoQueryResult` and its items are native resources: the result that an `execute` handler receives is closed when the handler returns, so extract plain Kotlin data inside the handler and never return the result or its items from it (see [Working with Query Results](../dql.md#working-with-query-results) and [In Kotlin, query results are closed when the execute handler returns, and by close()](../../knowledge/observations/kotlin-sdk.md#in-kotlin-query-results-are-closed-when-the-execute-handler-returns-and-by-close)).

| Member | Type | Description |
|---|---|---|
| `items` | `List<DittoQueryResultItem>` | The result rows |
| `item.value` | `DittoCborSerializable.Dictionary` | The row as a read-only map. Each read returns a new, equal object (see [In Kotlin, item.value returns a new read-only Dictionary on each read](../../knowledge/observations/kotlin-sdk.md#in-kotlin-itemvalue-returns-a-new-read-only-dictionary-on-each-read)) |
| `item.value["field"]` | `DittoCborSerializable` | A field. Read it with `.string`, `.long`, `.boolean`, `.dictionary`, `.list`, `.byteArray`, or `.attachmentToken`, or with the `...OrNull` forms, which return `null` for a missing value or another type; read decimal numbers with a helper such as `numberOrNull()` below |
| `item.jsonString()` | `String` | The row as a JSON string |
| `item.cborData()` | `ByteArray` | The row as CBOR |
| `mutatedDocumentIds()` | `Set<DittoCborSerializable>` | IDs of documents changed by a write |
| `commitId` | `ULong?` | ID of the local commit for a mutating statement; `null` for reads |
| `close()` | | Releases a result from `executeRaw`; results are `AutoCloseable`, so `use { }` works |

**Decimal numbers**: a floating-point value that a 32-bit float holds exactly, such as `7.5`, `7.0`, or `-0.5`, comes back as a `FloatValue`, and other values, such as `0.1`, as a `DoubleValue`. `doubleOrNull` returns `null` for a `FloatValue`, and `.double` throws, so a total of `7.5` silently reads as missing. Read decimals with a helper that accepts both, and integers too, such as `numberOrNull()` in the next example; in our testing with SDK 5.1.0 and 5.2.0, it read every value back exactly (see [In Kotlin, a decimal that a 32-bit float holds exactly comes back as a FloatValue](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-decimal-that-a-32-bit-float-holds-exactly-comes-back-as-a-floatvalue)).

**Missing and `null` fields**: `item.value["absent"]` returns a `NullValue` for a key that the row does not have, the same as for a `null` value; `item.value.containsKey("absent".toDittoCbor())` tells them apart. A typed accessor on a missing or `null` value, such as `.string`, throws `DittoException.FatalException` (`Could not deserialize String from NullValue`), so use the `...OrNull` forms for optional fields (see [In Kotlin, a missing key reads as NullValue, and a typed accessor on it throws](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-missing-key-reads-as-nullvalue-and-a-typed-accessor-on-it-throws)).

```kotlin
// Read: convert rows to plain Kotlin data right away, inside the handler.
suspend fun openOrderIds(ditto: Ditto): List<String> =
    ditto.store.execute(
        "SELECT _id, total, status FROM orders WHERE status = :status ORDER BY _id",
        mapOf("status" to "open"),
    ) { result -> result.items.map { it.value["_id"].string } }

// Write: inspect which documents changed, and the commit.
suspend fun closeOrders(ditto: Ditto, ids: List<String>): List<String> =
    ditto.store.execute(
        "UPDATE orders SET status = :status WHERE _id IN :ids",
        mapOf("status" to "closed", "ids" to ids),
    ) { result ->
        val commitId: ULong? = result.commitId // null for reads
        android.util.Log.d("App", "Committed as $commitId")
        result.mutatedDocumentIds().map { it.string }
    }

// Alternative encoding, for example to hand rows to a JSON decoder
suspend fun openOrdersAsJson(ditto: Ditto): List<String> =
    ditto.store.execute("SELECT * FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
        result.items.map { it.jsonString() }
    }
```

When you need the result object itself, for example to read it in several steps, take it with `executeRaw` and close it with `use`:

```kotlin
// ✅ GOOD: A raw result, closed when the block ends.
suspend fun openOrdersSummary(ditto: Ditto): String =
    ditto.store.executeRaw("SELECT * FROM orders WHERE status = :status", mapOf("status" to "open")).use { result ->
        val count = result.items.size
        val first = result.items.firstOrNull()?.value?.get("_id")?.stringOrNull
        "$count open orders, first: $first"
    }
```

```kotlin
// ❌ BAD: The result leaves the handler and is closed: reading an item's value
// afterwards throws IllegalStateException ("Query result item has already been closed.").
suspend fun openOrdersLeaked(ditto: Ditto): DittoQueryResult =
    ditto.store.execute("SELECT * FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
        result
    }
```

```kotlin
/**
 * Reads any number as a Double. A decimal that a 32-bit float holds exactly,
 * such as 7.5, comes back as a FloatValue, for which doubleOrNull returns null.
 */
fun DittoCborSerializable.numberOrNull(): Double? =
    doubleOrNull ?: floatOrNull?.toDouble() ?: longOrNull?.toDouble()

data class Order(val id: String, val status: String, val total: Double) {
    companion object {
        fun fromValue(value: DittoCborSerializable.Dictionary) = Order(
            id = value["_id"].string,
            status = value["status"].stringOrNull ?: "unknown",
            total = value["total"].numberOrNull() ?: 0.0,
        )
    }
}

// ✅ GOOD: One pass, plain Kotlin objects out
suspend fun loadOpenOrders(ditto: Ditto): List<Order> =
    ditto.store.execute(
        "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id",
        mapOf("status" to "open"),
    ) { result -> result.items.map { Order.fromValue(it.value) } }
```

**Deriving values at read time**: compute totals and the current status from the stored source data when you read a document, and skip entries whose required fields are missing or `null` (see [Do not store derived values that can diverge](../data-modeling.md#do-not-store-derived-values-that-can-diverge) and [Pattern 1: Audit-log map inside the document](../data-modeling.md#pattern-1-audit-log-map-inside-the-document)).

```kotlin
// ✅ GOOD: Store the source data; derive totals at read time. Entries with a
// missing or null price or quantity (an entry removed on one device while
// another device edited it) are skipped instead of crashing the screen.
fun orderSubtotalCents(order: DittoCborSerializable.Dictionary): Long {
    val items = order["items"].dictionaryOrNull ?: return 0
    var subtotal = 0L
    for (entry in items.values) {
        val price = entry["unitPriceCents"].longOrNull ?: continue
        val quantity = entry["quantity"].longOrNull ?: continue
        subtotal += price * quantity
    }
    return subtotal
}
```

```kotlin
// The workflow states, from earliest to most advanced.
private val statusOrder = listOf("created", "confirmed", "shipped", "delivered")

/**
 * Derives the current status as the most advanced state, so a late write from
 * a device that was offline cannot move the order backwards.
 */
fun currentStatus(order: DittoCborSerializable.Dictionary): String? =
    order["statusLog"].dictionaryOrNull
        ?.values
        ?.mapNotNull { it.stringOrNull }
        ?.maxByOrNull { statusOrder.indexOf(it) }
```

**Tolerating older documents**: a model class reads a field that newer app versions added with a default, because older documents do not have it (see [Prefer additive changes](../data-modeling.md#prefer-additive-changes)).

```kotlin
// ✅ GOOD: A new field, read with a default for older documents.
data class Car(val id: String, val make: String, val mileageKm: Long?) {
    companion object {
        fun fromDocument(doc: DittoCborSerializable.Dictionary) = Car(
            id = doc["_id"].string,
            make = doc["make"].string,
            mileageKm = doc["mileageKm"].longOrNull, // added in app version 2; absent in older documents
        )
    }
}
```

## Subscriptions in Kotlin

`ditto.sync.registerSubscription(query, arguments)` returns a `DittoSyncSubscription`; release it with `subscription.close()`, which does nothing if it is already closed. Registering a query that subscriptions do not accept throws `DittoException.StoreException` at once, for example `<dql> Unsupported feature: Limit or Order by` (see [Subscription Rules](../sync-and-subscriptions.md#subscription-rules)). The rules for when to register and close are in [Subscription Lifecycle](../sync-and-subscriptions.md#subscription-lifecycle).

```kotlin
// ✅ GOOD: A session-level service owns long-lived subscriptions.
class OrderSync(private val ditto: Ditto) {
    private val subscriptions = mutableListOf<DittoSyncSubscription>()
    private var storeId: String? = null

    /** Call once after login or when the user enters a store. */
    fun enterStore(storeId: String) {
        if (storeId == this.storeId) return // Already subscribed; do not re-register.
        leaveStore()
        this.storeId = storeId
        // Scope by stable partition keys; the UI filters further with local queries.
        subscriptions += ditto.sync.registerSubscription(
            "SELECT * FROM orders WHERE storeId = :storeId",
            mapOf("storeId" to storeId),
        )
        subscriptions += ditto.sync.registerSubscription(
            "SELECT * FROM orderItems WHERE storeId = :storeId",
            mapOf("storeId" to storeId),
        )
    }

    /** Call on logout or when the user leaves the store. */
    fun leaveStore() {
        subscriptions.forEach { it.close() } // No-op if already closed.
        subscriptions.clear()
        storeId = null
    }
}
```

```kotlin
// ❌ BAD: A new subscription every time a list row is bound, never closed.
// Each one keeps replicating until the Ditto instance is closed.
fun bindOrderRow(ditto: Ditto, storeId: String, showCount: (String) -> Unit) {
    ditto.sync.registerSubscription(
        "SELECT * FROM orders WHERE storeId = :storeId",
        mapOf("storeId" to storeId),
    )
    showCount(storeId)
}
```

When the user changes a filter, replace the observer, not the subscription (see [Filter locally instead of re-registering](../sync-and-subscriptions.md#filter-locally-instead-of-re-registering)). With `flatMapLatest`, a new filter cancels the collection of the previous `Flow`, which removes its observer:

```kotlin
// ✅ GOOD: The subscription (owned by OrderSync) stays stable; only the local
// observer changes. In a ViewModel, pass viewModelScope as scope.
@OptIn(ExperimentalCoroutinesApi::class)
class OrdersByStatusModel(ditto: Ditto, scope: CoroutineScope, storeId: String) {
    private val status = MutableStateFlow("open")

    val orders: StateFlow<List<Order>> = status
        .flatMapLatest { current ->
            ditto.store.observe(
                "SELECT * FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id",
                mapOf("storeId" to storeId, "status" to current),
            ) { result -> result.items.map { Order.fromValue(it.value) } }
        }
        // Observes only while the UI collects, and keeps observing for 5 s
        // across configuration changes.
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun showStatus(newStatus: String) {
        status.value = newStatus // Replacing a local observer is cheap.
    }
}
```

To switch stores, close first, then evict, then subscribe (see [Cancelling subscriptions and local data](../sync-and-subscriptions.md#cancelling-subscriptions-and-local-data)):

```kotlin
// ✅ GOOD: Switching stores: close first, then evict data the device no longer needs.
suspend fun switchStore(
    ditto: Ditto,
    currentSubscriptions: List<DittoSyncSubscription>,
    newStoreId: String,
): List<DittoSyncSubscription> {
    // 1. Stop asking for the old store's data.
    currentSubscriptions.forEach { it.close() }

    // 2. Remove the old store's documents from this device only.
    ditto.store.execute("EVICT FROM orders WHERE storeId != :storeId", mapOf("storeId" to newStoreId))
    ditto.store.execute("EVICT FROM orderItems WHERE storeId != :storeId", mapOf("storeId" to newStoreId))

    // 3. Ask for the new store's data.
    return listOf(
        ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to newStoreId)),
        ditto.sync.registerSubscription("SELECT * FROM orderItems WHERE storeId = :storeId", mapOf("storeId" to newStoreId)),
    )
}
```

`ditto.sync.subscriptions` returns the subscriptions that have not been closed; a query registered twice is listed twice. For a subscription registered without arguments, `queryArguments` and `queryArgumentsJsonString` are `null` (see [In Kotlin, a subscription without arguments has null queryArguments](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-subscription-without-arguments-has-null-queryarguments)). After `ditto.close()`, every subscription reports `isClosed == true`.

**Upload status**: one lightweight observer of `system:data_sync_info` per screen, exposed as a `StateFlow`, which emits only when the derived value changes, and the writes whose `commitId` it tracks (see [Monitoring Sync Status](../sync-and-subscriptions.md#monitoring-sync-status)):

```kotlin
// ✅ GOOD: One lightweight observer whose StateFlow changes only when the derived state changes.
// Use one instance per screen (for example, for the app bar), not one per list row.
class UploadStatus(ditto: Ditto, scope: CoroutineScope, commitId: ULong) {
    val uploaded: StateFlow<Boolean> = ditto.store
        .observe("SELECT * FROM system:data_sync_info WHERE is_ditto_server = true") { result ->
            // May run often, so keep the transform trivial.
            result.items.any { item ->
                val synced = item.value["documents"].dictionaryOrNull?.get("synced_up_to_local_commit_id")?.longOrNull
                synced != null && synced.toULong() >= commitId
            }
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), false)
}
```

```kotlin
// Obtain the commit ID from the write you want to track.
suspend fun submitOrder(ditto: Ditto, order: Map<String, Any?>): ULong? =
    ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order)) { result ->
        result.commitId // null for SELECT; set for local writes.
    }
```

```kotlin
// ✅ GOOD: Track the commitId only if the upsert actually changed the document.
suspend fun saveSettings(ditto: Ditto, settings: Map<String, Any?>): ULong? =
    ditto.store.execute(
        "INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
        mapOf("settings" to settings),
    ) { result ->
        // An unchanged document still gets a commitId, but peers confirm it only
        // with their next sync exchange (up to about 27 seconds later).
        if (result.mutatedDocumentIds().isEmpty()) null else result.commitId
    }
```

**Subscriptions for a JOIN**: a feature-level service creates the index of the join key and subscribes to every collection that the join reads (see [Separate collections with JOIN (SDK 5.1+)](../data-modeling.md#separate-collections-with-join-sdk-51)).

```kotlin
/**
 * Keeps the three collections needed by the order screens in sync.
 * Subscriptions belong to an app- or feature-level service, not to a screen.
 */
class StoreSync(private val ditto: Ditto, private val storeId: String) {
    private val subscriptions = mutableListOf<DittoSyncSubscription>()

    suspend fun start() {
        ditto.store.execute("CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)")
        subscriptions += listOf(
            ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to storeId)),
            ditto.sync.registerSubscription("SELECT * FROM orderItems WHERE storeId = :storeId", mapOf("storeId" to storeId)),
            ditto.sync.registerSubscription("SELECT * FROM products"),
        )
    }

    fun stop() {
        subscriptions.forEach { it.close() }
        subscriptions.clear()
    }
}
```

If the key of a joined observer (such as the `orderId`) can change while the screen is shown, put the key into a `MutableStateFlow` and switch with `flatMapLatest`, as `OrdersByStatusModel` does.

**Retention windows**: a long-lived service that keeps only recent documents moves the boundary of its subscription and evicts the complement in three steps: close the subscription, evict with the new cutoff, and subscribe again with the same cutoff, even if the eviction failed (see [Time-based eviction](../deletion-and-storage.md#time-based-eviction)). `utcTimestamp()` is defined in [IDs and Timestamps in Kotlin](#ids-and-timestamps-in-kotlin).

```kotlin
import java.time.Duration
import java.time.Instant

// ✅ GOOD: Keep the last 7 days of orders on this device.
class OrderRetention(private val ditto: Ditto) {
    private val retention = Duration.ofDays(7)
    private var subscription: DittoSyncSubscription? = null

    // Same fixed-precision format as createdAt (utcTimestamp() from "IDs and Timestamps in Kotlin").
    private fun cutoff(): String = utcTimestamp(Instant.now().minus(retention))

    /** Call once at startup (before ditto.sync.start()). */
    fun start() {
        subscription = subscribeFrom(cutoff())
    }

    /** Call on a schedule, for example once a day. */
    suspend fun evictExpired(): Int {
        val cutoff = cutoff()

        // 1. Stop asking peers for the documents that are about to be evicted.
        subscription?.close()

        try {
            // 2. Evict exactly the complement of the new subscription.
            return ditto.store.execute(
                "EVICT FROM orders WHERE createdAt < :cutoff",
                mapOf("cutoff" to cutoff),
            ) { result -> result.mutatedDocumentIds().size }
        } finally {
            // 3. Subscribe again with the moved boundary, even if the eviction failed.
            subscription = subscribeFrom(cutoff)
        }
    }

    private fun subscribeFrom(cutoff: String): DittoSyncSubscription =
        ditto.sync.registerSubscription(
            "SELECT * FROM orders WHERE createdAt >= :cutoff",
            mapOf("cutoff" to cutoff),
        )

    fun stop() {
        subscription?.close()
    }
}
```

The same steps keep active orders and orders soft-deleted within a retention window, and evict older soft-deleted orders (Variant B in [Soft delete, subscriptions, and cleanup](../deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)):

```kotlin
import java.time.Duration
import java.time.Instant

// ✅ GOOD (Variant B): A long-lived service keeps active orders and orders
// deleted within the retention window, and evicts older deleted orders.
class OrderSoftDeleteRetention(private val ditto: Ditto, private val storeId: String) {
    /** Longer than the longest time a device is expected to stay offline. */
    private val retention = Duration.ofDays(30)
    private var subscription: DittoSyncSubscription? = null

    // Same fixed-precision format as deletedAt (utcTimestamp() from "IDs and Timestamps in Kotlin").
    private fun cutoff(): String = utcTimestamp(Instant.now().minus(retention))

    /** Call once at startup (before ditto.sync.start()). */
    fun start() {
        subscription = subscribe(cutoff())
    }

    /** Call on a schedule, at most about once a day. */
    suspend fun evictExpired() {
        val cutoff = cutoff()

        // 1. Stop asking peers for the documents that are about to be evicted.
        subscription?.close()

        try {
            // 2. Evict only documents outside the new subscription.
            ditto.store.execute(
                "EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff",
                mapOf("storeId" to storeId, "cutoff" to cutoff),
            )
        } finally {
            // 3. Subscribe again with the moved boundary, even if the eviction failed.
            subscription = subscribe(cutoff)
        }
    }

    private fun subscribe(cutoff: String): DittoSyncSubscription =
        ditto.sync.registerSubscription(
            "SELECT * FROM orders WHERE storeId = :storeId " +
                "AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)",
            mapOf("storeId" to storeId, "cutoff" to cutoff),
        )

    fun stop() {
        subscription?.close()
    }
}
```

## Store Observers in Kotlin

The Kotlin SDK offers three observer APIs, all of which accept only `SELECT` statements and wait for your code before they deliver the next result (see [Backpressure in Kotlin](#backpressure-in-kotlin)):

| API | Returns | Released by |
|---|---|---|
| `ditto.store.observe(query, arguments) { result -> value }` | A cold `Flow` of the values that the transform returns | Cancelling the coroutine that collects it |
| `ditto.store.registerObserver(query, arguments) { result -> }` | `DittoStoreObserver` | `observer.close()` |
| `ditto.store.collect(query, arguments) { result -> }` | Suspends until cancelled | Cancelling the coroutine that calls it |

Each API also has a form whose lambda receives a `DittoDiff` as its second parameter (see [Diffing results in Kotlin](#diffing-results-in-kotlin)). For UI state, use `observe` and turn it into a `StateFlow` in the scope of the class that owns the screen's state; a `ViewModel` passes `viewModelScope`, and the UI collects the `StateFlow` with the lifecycle-aware collectors of `androidx.lifecycle`. The rules that every SDK shares are in [Observing Changes](../observers.md).

```kotlin
// ✅ GOOD: The recommended observer pattern for screen state.
// In a ViewModel, pass viewModelScope as scope.
class OpenOrdersModel(ditto: Ditto, scope: CoroutineScope) {
    val orders: StateFlow<List<Order>> = ditto.store
        .observe(
            "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
            mapOf("status" to "open"),
        ) { result ->
            // Convert inside the transform: the result is closed after it returns.
            result.items.map { Order.fromValue(it.value) }
        }
        // The observer runs only while the UI collects (plus 5 s for
        // configuration changes); the scope's cancellation removes it.
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())
}
```

**✅ DO:**
- Create observers in a class that owns the screen's state (a `ViewModel`), or in a service, never in code that runs on every recomposition or bind.
- Convert rows to plain values (your own model classes) inside the transform or handler; never let a `DittoQueryResult` or `DittoQueryResultItem` leave it (see [Query results in Kotlin](#query-results-in-kotlin)).
- Add `ORDER BY` with a tie-breaker whenever the order of results matters (see [Stable ordering](../observers.md#stable-ordering)).
- Share one `StateFlow` (`stateIn`) or `SharedFlow` (`shareIn`) between collectors: each collection of the cold `Flow` registers another observer.
- Move heavy work in a handler off the main thread, or pass a scope to `DittoFactory.create` (see [Opening Ditto in Kotlin](#opening-ditto-in-kotlin)).

**❌ DON'T:**
- Return `result` or `result.items` from the transform or handler.
- Let a `registerObserver` handler throw: the observer is closed and the error is only logged (see [Observer lifecycle in Kotlin](#observer-lifecycle-in-kotlin)).
- Create an observer per list item; observe the list once and pass values down.

**Note (SDK 5.1.0 and 5.2.0):** With the default scope of `DittoFactory.create`, every observer handler runs on the main thread, also a handler of `collect` that was called from another dispatcher (see [In Kotlin, observer handlers run on the main thread unless DittoFactory.create gets another scope](../../knowledge/observations/kotlin-sdk.md#in-kotlin-observer-handlers-run-on-the-main-thread-unless-dittofactorycreate-gets-another-scope)).

```kotlin
// ❌ BAD: The transform returns the items. They are closed when the transform
// returns, so reading them in the collector throws IllegalStateException.
fun observeOrderItemsBadly(ditto: Ditto): Flow<List<DittoQueryResultItem>> =
    ditto.store.observe("SELECT * FROM orders ORDER BY createdAt DESC") { result -> result.items }

// ✅ GOOD: The same work with plain values out of the transform.
fun observeOrderCount(ditto: Ditto): Flow<Int> =
    ditto.store.observe("SELECT * FROM orders ORDER BY createdAt DESC") { result -> result.items.size }
```

### Observer lifecycle in Kotlin

| Behavior | Consequence |
|---|---|
| `registerObserver` runs until `close()` | Keep the `DittoStoreObserver` and close it; garbage collection does not stop it, and `ditto.store.observers` still lists it (see [In Kotlin, garbage-collected subscriptions and observers keep running](../../knowledge/observations/kotlin-sdk.md#in-kotlin-garbage-collected-subscriptions-and-observers-keep-running)) |
| The `Flow` of `observe` is cold | Each collection registers its own observer, and cancelling it removes that observer (see [In Kotlin, each collection of an observe() Flow is its own observer](../../knowledge/observations/kotlin-sdk.md#in-kotlin-each-collection-of-an-observe-flow-is-its-own-observer)) |
| `collect` suspends until its coroutine is cancelled | Launch it in the scope that should own the observer |
| A `registerObserver` handler that throws | The observer is closed and never called again; the SDK logs `DittoStore: Unhandled exception in observer event handler.` at the error level, and the process does not crash (see [In Kotlin, an observer whose handler throws is closed, and the exception is only logged](../../knowledge/observations/kotlin-sdk.md#in-kotlin-an-observer-whose-handler-throws-is-closed-and-the-exception-is-only-logged)) |
| A transform of `observe`, or a handler of `collect`, that throws | The exception reaches the code that collects the `Flow` or calls `collect`, and the observer is removed |
| `ditto.close()` | Closes every observer (`isClosed == true`) |

When you need a `DittoStoreObserver` (for example, to keep observing without a collector), keep it and close it where the owner ends; in a `ViewModel`, that is `onCleared()`:

```kotlin
// ✅ GOOD: A registerObserver handle owned by a class that closes it.
// A ViewModel calls clear() from onCleared().
class OpenOrdersCounter(ditto: Ditto) {
    private val _count = MutableStateFlow(0)
    val count: StateFlow<Int> = _count

    private val observer: DittoStoreObserver = ditto.store.registerObserver(
        "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
        mapOf("status" to "open"),
    ) { result ->
        try {
            _count.value = result.items.firstOrNull()?.value?.get("n")?.intOrNull ?: 0
        } catch (error: Exception) {
            showError(error) // An exception that leaves the handler closes the observer.
        }
    }

    fun clear() {
        observer.close()
    }
}
```

```kotlin
// ❌ BAD: The handler throws for a row without a price: the observer is closed
// silently, and the screen stops updating.
fun observeTotalsFragile(ditto: Ditto, show: (Double) -> Unit): DittoStoreObserver =
    ditto.store.registerObserver("SELECT price FROM orders") { result ->
        show(result.items.sumOf { it.value["price"].numberOrNull()!! }) // throws on a missing price
    }
```

Share one observer between several collectors instead of collecting the cold `Flow` once per collector:

```kotlin
// ✅ GOOD: One observer, shared by every collector of `orders`.
class SharedOrders(ditto: Ditto, scope: CoroutineScope) {
    val orders: SharedFlow<List<Order>> = ditto.store
        .observe("SELECT * FROM orders ORDER BY createdAt DESC, _id") { result ->
            result.items.map { Order.fromValue(it.value) }
        }
        .shareIn(scope, SharingStarted.WhileSubscribed(5_000), replay = 1)
}
```

### Backpressure in Kotlin

Every Kotlin observer waits for your code: `registerObserver` and `collect` deliver the next result only after the suspending handler has returned, and the changes in between are merged into the latest state. In our testing with SDK 5.1.0 and 5.2.0, a handler that suspended for 500 ms during 10 writes 50 ms apart was called three times, one call at a time, and received the final value (see [In Kotlin, observer handlers run one at a time, and intermediate results are skipped](../../knowledge/observations/kotlin-sdk.md#in-kotlin-observer-handlers-run-one-at-a-time-and-intermediate-results-are-skipped)). The `Flow` of `observe` is one result ahead of a slow collector: add `conflate()` when only the latest state matters. There is no `signalNext()`: to wait for work that finishes elsewhere, suspend in the handler until it is done. The concept is described in [Backpressure (SDK 5.1+)](../observers.md#backpressure-sdk-51).

```kotlin
// ❌ BAD: The handler starts the upload and returns at once, so uploads
// overlap and Ditto does not wait for them.
fun uploadOnEveryChange(
    ditto: Ditto,
    scope: CoroutineScope,
    upload: suspend (List<Order>) -> Unit,
): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val orders = result.items.map { Order.fromValue(it.value) }
        scope.launch { upload(orders) }
    }
```

```kotlin
// ✅ GOOD: collect with a suspending handler: one update at a time, then the latest state.
class SensorAggregator(private val ditto: Ditto, private val scope: CoroutineScope) {
    private var job: Job? = null

    fun run(deviceId: String, persistAggregates: suspend (List<Double>) -> Unit) {
        stop() // Cancel a previous run, if any.
        job = scope.launch {
            ditto.store.collect(
                "SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100",
                mapOf("deviceId" to deviceId),
            ) { result ->
                // Ditto holds back the next update until this handler returns.
                persistAggregates(result.items.mapNotNull { it.value["value"].numberOrNull() })
            }
        }
    }

    fun stop() {
        job?.cancel() // Cancelling the coroutine removes the observer.
    }
}
```

```kotlin
// ✅ GOOD: observe + conflate: a slow consumer gets the latest state, never a queue.
class OpenOrdersUploader(
    private val ditto: Ditto,
    private val scope: CoroutineScope,
    private val upload: suspend (List<Order>) -> Unit,
) {
    private var job: Job? = null

    fun start() {
        stop() // Cancel a previous start, if any.
        job = scope.launch {
            ditto.store
                .observe("SELECT * FROM orders WHERE status = :status ORDER BY createdAt", mapOf("status" to "open")) { result ->
                    result.items.map { Order.fromValue(it.value) }
                }
                .conflate()
                .collect { orders ->
                    try {
                        upload(orders)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        showError(error) // keep collecting after a failed upload
                    }
                }
        }
    }

    fun stop() {
        job?.cancel()
    }
}
```

```kotlin
// ✅ GOOD: The work for an update finishes elsewhere (here, an external callback):
// the handler suspends until it reports completion.
fun observeWithExternalCompletion(
    ditto: Ditto,
    startWork: (rows: Int, done: () -> Unit) -> Unit,
): DittoStoreObserver =
    ditto.store.registerObserver("SELECT * FROM orders") { result ->
        val finished = CompletableDeferred<Unit>()
        startWork(result.items.size) { finished.complete(Unit) }
        finished.await() // the next update waits until the work is done
    }
```

### Diffing results in Kotlin

Pass a lambda with two parameters to `registerObserver`, `collect`, or `observe`, and the SDK passes a `DittoDiff` against the previous result of the same observer: `insertions`, `deletions`, and `updates` (`Set<Int>`) and `moves` (`List<DittoDiff.Move>` with `from` and `to`). The first result reports every row as an insertion, and moving one row to the top reports every row whose position shifted as a move (see [In Kotlin, DittoDiff reports every shifted row as a move](../../knowledge/observations/kotlin-sdk.md#in-kotlin-dittodiff-reports-every-shifted-row-as-a-move)). Apps do not create a `DittoDiffer`: its constructors take only types of the SDK's internal package, and the observer owns it (see [The differs accept only items from Ditto query results, and Kotlin apps do not create one](../../knowledge/observations/observer-behavior.md#the-differs-accept-only-items-from-ditto-query-results-and-kotlin-apps-do-not-create-one)). Project `_id` in a diffed query: on SDK 5.2.0, the rows of a query that did not project it had no `_id` in our testing (see [On SDK 5.2.0, observer rows include _id only when it is projected, except with Flutter's registerObserver](../../knowledge/observations/observer-behavior.md#on-sdk-520-observer-rows-include-_id-only-when-it-is-projected-except-with-flutters-registerobserver)). The semantics that every SDK shares are in [Diffing Results](../observers.md#diffing-results).

```kotlin
import android.util.Log

// ✅ GOOD: Logging changes between results with DittoDiff.
fun logOrderChanges(ditto: Ditto): DittoStoreObserver {
    var previousIds = emptyList<String>()
    return ditto.store.registerObserver("SELECT * FROM orders ORDER BY createdAt, _id") { result, diff ->
        val currentIds = result.items.map { it.value["_id"].string }
        for (index in diff.deletions) Log.d("App", "deleted ${previousIds[index]}") // OLD list
        for (index in diff.insertions) Log.d("App", "inserted ${currentIds[index]}") // NEW list
        for (index in diff.updates) Log.d("App", "updated ${currentIds[index]}") // NEW list
        for (move in diff.moves) Log.d("App", "moved ${move.from} -> ${move.to}")
        previousIds = currentIds
    }
}
```

A list that animates its changes (for example, a `RecyclerView` adapter that calls `notifyItemRemoved` and `notifyItemInserted`) needs the changes in the order in which it applies them: removals from the end of the old list, then insertions in ascending order of the new list. A model can deliver the rows together with those changes:

```kotlin
// One update of an animated list: the new rows and the changes to apply to the old list.
data class OrderListUpdate(
    val orders: List<Order>,
    val removedIndexes: List<Int>, // old indexes, descending
    val insertedIndexes: List<Int>, // new indexes, ascending
    val updatedIndexes: Set<Int>, // new indexes
)

// ✅ GOOD: Turn each DittoDiff into the steps a list adapter applies.
// In a ViewModel, pass viewModelScope as scope.
class AnimatedOrdersModel(ditto: Ditto, scope: CoroutineScope) {
    val updates: SharedFlow<OrderListUpdate> = ditto.store
        .observe(
            "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200",
            mapOf("status" to "open"),
        ) { result, diff ->
            OrderListUpdate(
                orders = result.items.map { Order.fromValue(it.value) },
                // A move is a removal plus an insertion.
                removedIndexes = (diff.deletions + diff.moves.map { it.from }).sortedDescending(),
                insertedIndexes = (diff.insertions + diff.moves.map { it.to }).sorted(),
                updatedIndexes = diff.updates,
            )
        }
        .shareIn(scope, SharingStarted.WhileSubscribed(5_000))
}
```

**Why:** Applying removals in descending order and insertions in ascending order keeps the adapter's positions consistent with the new list. A list that does not animate (for example, a `ListAdapter` with `DiffUtil`, or a Compose `LazyColumn` with keys) does not need `DittoDiff`.

### Partial UI updates in Kotlin

Give each region of a screen its own `StateFlow` from its own observer. A `StateFlow` emits only when the new value differs from the current one (`equals`), so a region does not update when its value is unchanged; `item.value` returns equal `Dictionary` objects for equal rows, and data classes compare by value, so mapping rows to data classes keeps that check meaningful. The rules that every SDK shares are in [Partial UI Updates](../observers.md#partial-ui-updates).

```kotlin
// ✅ GOOD: The count badge and the list each observe what they need.
// In a ViewModel, pass viewModelScope as scope.
class OrdersScreenModel(ditto: Ditto, scope: CoroutineScope) {
    /** Changes only when the count changes. */
    val openCount: StateFlow<Int> = ditto.store
        .observe("SELECT COUNT(*) AS n FROM orders WHERE status = :status", mapOf("status" to "open")) { result ->
            result.items.firstOrNull()?.value?.get("n")?.intOrNull ?: 0
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), 0)

    /** Changes only when a displayed field of a listed order changes. */
    val openOrders: StateFlow<List<Order>> = ditto.store
        .observe(
            "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
            mapOf("status" to "open"),
        ) { result -> result.items.map { Order.fromValue(it.value) } }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())
}
```

Use the Layout Inspector's recomposition counts, or a breakpoint in your adapter, to confirm which parts of the screen update before optimizing further.

## Transactions in Kotlin

Run statements through `tx.execute(...)`, never through `ditto.store.execute`. In the Kotlin SDK, a write through `ditto.store.execute` inside a transaction **deadlocks**: neither the call nor the transaction returns, and a later `ditto.close()` does not return either. A read through it returns, but it does not see the transaction's own writes. A read-write transaction started inside another one also deadlocks; a read-only transaction inside a read-write one returns (see [In Kotlin, store.execute writes inside a transaction deadlock](../../knowledge/observations/kotlin-sdk.md#in-kotlin-storeexecute-writes-inside-a-transaction-deadlock) and [In Kotlin, a read-write transaction inside a read-write transaction deadlocks](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-read-write-transaction-inside-a-read-write-transaction-deadlocks)). The rules are in [Transaction Rules](../transactions.md#transaction-rules).

`DittoStore.transaction` signature:

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `hint` | `String?` | `null` | A label written to the logs |
| `isReadOnly` | `Boolean` | `false` | Read-only transactions reject mutating statements (`StoreException: ... A mutating DQL query was attempted using a read-only transaction.`) and can run concurrently |
| `transactionBlock` (trailing lambda) | `suspend (DittoTransaction) -> DittoTransaction.Result<T>` | required | The work to do. Use only the `DittoTransaction` passed in. |

How a transaction ends (see [In Kotlin, transactions commit, roll back, and rethrow as documented](../../knowledge/observations/kotlin-sdk.md#in-kotlin-transactions-commit-roll-back-and-rethrow-as-documented)):

| Block outcome | Result |
|---|---|
| Returns `DittoTransaction.Result.Commit(value)` | Committed; `transaction` returns that `Commit`, whose `value` is your value |
| Returns `DittoTransaction.Result.Rollback` | Rolled back; no changes are applied; `transaction` returns `Rollback` |
| Throws | Rolled back; the exception is rethrown to the caller of `transaction` |
| A statement fails, but the block catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

```kotlin
// ✅ GOOD: Close an order and create its invoice atomically.
suspend fun closeOrderWithInvoice(ditto: Ditto, orderId: String, invoiceId: String) {
    ditto.store.transaction(hint = "closeOrderWithInvoice") { tx -> // The hint appears in logs.
        val total = tx.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to orderId)) { result ->
            result.items.firstOrNull()?.value?.get("total")?.numberOrNull()
        } ?: throw IllegalStateException("Order $orderId not found") // Throwing rolls back.

        tx.execute(
            "INSERT INTO invoices DOCUMENTS (:invoice)",
            mapOf(
                "invoice" to mapOf(
                    "_id" to invoiceId,
                    "orderId" to orderId,
                    "total" to total,
                    "createdAt" to utcTimestamp(), // Defined in the Timestamps section.
                ),
            ),
        )
        tx.execute(
            "UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id",
            mapOf("id" to orderId, "status" to "closed", "invoiceId" to invoiceId),
        )
        DittoTransaction.Result.Commit(Unit)
    }
}
```

```kotlin
// ✅ GOOD: Explicit rollback without throwing, and a typed return value.
suspend fun shipOrder(ditto: Ditto, orderId: String): Boolean {
    val result = ditto.store.transaction(hint = "shipOrder") { tx ->
        val paid = tx.execute(
            "SELECT * FROM orders WHERE _id = :id AND status = :status",
            mapOf("id" to orderId, "status" to "paid"),
        ) { it.items.isNotEmpty() }
        if (!paid) return@transaction DittoTransaction.Result.Rollback // Nothing to ship.
        tx.execute("UPDATE orders SET status = :status WHERE _id = :id", mapOf("id" to orderId, "status" to "shipped"))
        DittoTransaction.Result.Commit(true)
    }
    return result is DittoTransaction.Result.Commit
}

// ✅ GOOD: A read-only transaction for a consistent multi-query snapshot.
suspend fun orderCounts(ditto: Ditto): Pair<Long, Long> {
    val result = ditto.store.transaction(hint = "orderCounts", isReadOnly = true) { tx ->
        suspend fun count(status: String) = tx.execute(
            "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
            mapOf("status" to status),
        ) { it.items.first().value["n"].long }
        DittoTransaction.Result.Commit(count("open") to count("closed"))
    }
    return (result as DittoTransaction.Result.Commit).value
}
```

Using the `DittoTransaction` after its block has returned throws `IllegalStateException` (`dittoffi_transaction was already closed.`).

```kotlin
// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
suspend fun badCheckout(ditto: Ditto, orderId: String, chargeCard: suspend () -> Unit) {
    ditto.store.transaction { tx ->
        tx.execute("UPDATE orders SET status = :status WHERE _id = :id", mapOf("id" to orderId, "status" to "checkout"))
        // Network call inside the transaction: every other write, and every change
        // from other devices, waits until the transaction ends.
        chargeCard()
        // Deadlock: a write through store.execute waits for this transaction.
        ditto.store.execute("UPDATE orders SET status = :status WHERE _id = :id", mapOf("id" to orderId, "status" to "paid"))
        // Deadlock: the inner read-write transaction waits for the outer one.
        ditto.store.transaction { inner ->
            inner.execute("UPDATE orders SET paidAt = :paidAt WHERE _id = :id", mapOf("id" to orderId, "paidAt" to utcTimestamp()))
            DittoTransaction.Result.Commit(Unit)
        }
        DittoTransaction.Result.Commit(Unit)
    }
}

// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
suspend fun checkout(ditto: Ditto, orderId: String, chargeCard: suspend () -> Unit) {
    chargeCard() // Outside the transaction.
    ditto.store.transaction(hint = "recordPayment") { tx ->
        tx.execute(
            "UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id",
            mapOf("id" to orderId, "status" to "paid", "paidAt" to utcTimestamp()), // fixed-precision helper (see Timestamps)
        )
        tx.execute(
            "INSERT INTO payments DOCUMENTS (:payment)",
            mapOf("payment" to mapOf("_id" to "payment-$orderId", "orderId" to orderId)),
        )
        DittoTransaction.Result.Commit(Unit)
    }
}
```

`ditto.close()` waits for an open transaction, so you do not need to track transactions before closing; make sure that none can deadlock. **Each `execute` that waits for a write transaction holds its thread** until the transaction ends (see [Executing DQL in Kotlin](#executing-dql-in-kotlin)). In our testing with SDK 5.1.0 and 5.2.0, 200 writes launched on `Dispatchers.IO` while a transaction was suspended in `delay()` took all 64 threads of `Dispatchers.IO`, the transaction could not resume, and neither the writes, the transaction, nor `close()` returned; with the transaction on a thread of its own, all of them finished in about 1.2 seconds (see [In Kotlin, writes that wait behind a transaction each hold a thread](../../knowledge/observations/kotlin-sdk.md#in-kotlin-writes-that-wait-behind-a-transaction-each-hold-a-thread)). Keep transactions short, and write many documents with one statement instead of many concurrent calls:

```kotlin
// ❌ BAD: One coroutine per document on Dispatchers.IO. Behind a long
// transaction, each waiting write holds an IO thread; with enough of them,
// the transaction cannot resume, and everything stops.
fun importOrdersConcurrently(ditto: Ditto, scope: CoroutineScope, orders: List<Map<String, Any?>>) {
    for (order in orders) {
        scope.launch(Dispatchers.IO) {
            ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order))
        }
    }
}

// ✅ GOOD: One statement writes them all, and the caller awaits it.
suspend fun importOrders(ditto: Ditto, orders: List<Map<String, Any?>>) {
    withContext(Dispatchers.IO) {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:orders) ON ID CONFLICT DO UPDATE",
            mapOf("orders" to orders),
        )
    }
}
```

**Read, change, and write in one transaction**: replacing an array, or copying a document to a new `_id`, reads a value and writes a new one. Doing both in one transaction keeps two local calls from interleaving; a concurrent edit on another device can still win the merge (see [Working with arrays](../data-modeling.md#working-with-arrays) and [IDs are immutable](../data-modeling.md#ids-are-immutable)).

```kotlin
// The array is a register: this write replaces it as a whole. Reading and
// writing in one transaction keeps two local calls from interleaving and
// dropping a tag; a concurrent edit on another device can still win the merge.
suspend fun addTag(ditto: Ditto, productId: String, tag: String) {
    ditto.store.transaction(hint = "addTag") { tx ->
        val current = tx.execute("SELECT tags FROM products WHERE _id = :id", mapOf("id" to productId)) { result ->
            result.items.firstOrNull()?.value?.get("tags")?.listOrNull?.mapNotNull { it.stringOrNull }
        } ?: return@transaction DittoTransaction.Result.Commit(Unit) // no such product
        tx.execute(
            "UPDATE products SET tags = :tags WHERE _id = :id",
            mapOf("id" to productId, "tags" to current + tag),
        )
        DittoTransaction.Result.Commit(Unit)
    }
}
```

```kotlin
/**
 * Copies an order to a new ID and deletes the original, atomically.
 * Both statements declare the order's COUNTER, ATTACHMENT, and REGISTER
 * fields exactly as the other statements on orders do, so the copy keeps
 * their CRDT types. Undeclared objects such as shippingAddress are MAPs.
 */
suspend fun moveOrder(ditto: Ditto, oldId: String, newId: String) {
    ditto.store.transaction(hint = "moveOrder") { tx ->
        val copy = tx.execute(
            """
            SELECT * FROM COLLECTION orders
              (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
            WHERE _id = :id
            """,
            mapOf("id" to oldId),
        ) { result ->
            result.items.firstOrNull()?.value?.let { original ->
                // The value is read-only: build a new Dictionary with the new _id.
                DittoCborSerializable.Dictionary(original + ("_id".toDittoCbor() to newId.toDittoCbor()))
            }
        } ?: return@transaction DittoTransaction.Result.Commit(Unit)
        tx.execute(
            """
            INSERT INTO COLLECTION orders
              (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
            DOCUMENTS (:doc)
            """,
            mapOf("doc" to copy),
        )
        tx.execute("DELETE FROM orders WHERE _id = :id", mapOf("id" to oldId))
        DittoTransaction.Result.Commit(Unit)
    }
}
```

## Attachments in Kotlin

Create attachments with `ditto.store.newAttachment(...)`. The rules are in [Attachments](../attachments.md).

| `newAttachment` detail | Behavior |
|---|---|
| From a file | `newAttachment(path, metadata)`, not suspending. The file is copied into Ditto's store; pass an absolute path (for example, one under `context.filesDir`) |
| From bytes or a stream | `suspend newAttachment(inputStream, metadata)`; wrap bytes in a `ByteArrayInputStream` |
| Metadata | `Map<String, String>` (SDK 5.2+). The deprecated overloads with `Map<String, Any?>` throw `IllegalArgumentException` for values that are not strings |
| Result | A `DittoAttachment` with `id`, `len`, `metadata`, `getData()` (a `ByteArray`), `getInputStream()`, and `copyToPath(path)` |

```kotlin
import java.io.ByteArrayInputStream

// ✅ GOOD: Create an attachment from a file and insert it with a declared ATTACHMENT field.
suspend fun savePhoto(ditto: Ditto, photoId: String, filePath: String) {
    // The file is copied into Ditto's blob store; the original can be deleted afterwards.
    val attachment = ditto.store.newAttachment(
        filePath,
        mapOf("name" to "receipt.jpg", "mimeType" to "image/jpeg"), // String values only.
    )
    ditto.store.execute(
        "INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)",
        mapOf(
            "photo" to mapOf(
                "_id" to photoId,
                "image" to attachment,
                "createdAt" to utcTimestamp(), // Defined in the Timestamps section.
            ),
        ),
    )
}

// ✅ GOOD: Create an attachment from bytes.
suspend fun attachmentFromBytes(ditto: Ditto, bytes: ByteArray, name: String): DittoAttachment =
    ditto.store.newAttachment(ByteArrayInputStream(bytes), mapOf("name" to name))
```

`ditto.store.fetchAttachment(token) { downloadedBytes, totalBytes -> }` suspends until the attachment is available and returns a `DittoAttachmentFetchResult`: `Completed` with `attachment`, or `Deleted`. The optional second parameter is a suspending progress callback. Cancelling the coroutine that awaits it cancels the fetch. A fetch never times out on its own: while no peer delivers the blob, it waits without progress events, and a token whose blob no connected peer has ever had fails at once with `DittoException.StoreException: Attachment not found.` (see [In Kotlin, fetchAttachment waits without progress while no peer delivers the blob](../../knowledge/observations/kotlin-sdk.md#in-kotlin-fetchattachment-waits-without-progress-while-no-peer-delivers-the-blob)).

The component below starts the fetch when it is asked for an image, restarts a stall timer on every progress event, gives up with a retry state when the timer fires, and cancels the fetch when the owner clears it or asks for another token:

```kotlin
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

sealed interface AttachmentState {
    data class Loading(val progress: Double?) : AttachmentState
    class Loaded(val bytes: ByteArray) : AttachmentState
    data object Failed : AttachmentState // offer a retry
}

// ✅ GOOD: Lazy, cancellable attachment loading with a stall timeout.
// In a ViewModel, pass viewModelScope as scope.
class AttachmentLoader(private val ditto: Ditto, private val scope: CoroutineScope) {
    private val _state = MutableStateFlow<AttachmentState>(AttachmentState.Loading(null))
    val state: StateFlow<AttachmentState> = _state
    private var fetch: Job? = null

    /** Starts (or restarts) fetching [token]. Call when the image is shown. */
    fun load(token: DittoAttachmentToken, stallTimeout: Duration = 30.seconds) {
        fetch?.cancel() // A new token or a retry replaces the previous fetch.
        _state.value = AttachmentState.Loading(null)
        fetch = scope.launch {
            val fetchJob = coroutineContext.job
            val lastProgress = AtomicReference(TimeSource.Monotonic.markNow())
            // Ditto has no fetch timeout: no progress simply means no peer is delivering the blob.
            val watchdog = launch {
                while (true) {
                    delay(minOf(stallTimeout, 1.seconds))
                    if (lastProgress.get().elapsedNow() > stallTimeout) {
                        _state.value = AttachmentState.Failed
                        fetchJob.cancel() // Stops the fetch.
                    }
                }
            }
            try {
                val result = ditto.store.fetchAttachment(token) { downloaded, total ->
                    lastProgress.set(TimeSource.Monotonic.markNow()) // Progress resets the stall timer.
                    if (total > 0u) _state.value = AttachmentState.Loading(downloaded.toDouble() / total.toDouble())
                }
                _state.value = when (result) {
                    is DittoAttachmentFetchResult.Completed ->
                        AttachmentState.Loaded(withContext(Dispatchers.IO) { result.attachment.getData() })
                    is DittoAttachmentFetchResult.Deleted -> AttachmentState.Failed
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: DittoException) {
                _state.value = AttachmentState.Failed // for example, Ditto was closed
            } finally {
                watchdog.cancel()
            }
        }
    }

    /** Call when the image is no longer shown. Cancels a fetch in progress. */
    fun clear() {
        fetch?.cancel()
    }
}
```

```kotlin
// Reading the token from a document.
fun imageToken(photo: DittoCborSerializable.Dictionary): DittoAttachmentToken? =
    photo["image"].attachmentTokenOrNull
```

To replace or remove an attachment (see [Attachments Are Immutable](../attachments.md#attachments-are-immutable)):

```kotlin
// ✅ GOOD: Replace an attachment by creating a new one and updating the token field.
suspend fun replacePhoto(ditto: Ditto, photoId: String, newFilePath: String) {
    val attachment = ditto.store.newAttachment(newFilePath, mapOf("name" to "receipt-v2.jpg", "mimeType" to "image/jpeg"))
    ditto.store.execute(
        "UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id",
        mapOf("id" to photoId, "image" to attachment),
    )
}

// ✅ GOOD: Remove the reference; the blob becomes eligible for garbage collection.
suspend fun removePhoto(ditto: Ditto, photoId: String) {
    ditto.store.execute(
        "UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id",
        mapOf("id" to photoId),
    )
}
```

Thumbnails and full-size images (see [Thumbnail Pattern](../attachments.md#thumbnail-pattern)):

```kotlin
import java.io.ByteArrayInputStream

// ✅ GOOD: Insert a thumbnail attachment and a full-size attachment together.
suspend fun savePhotoWithThumbnail(
    ditto: Ditto,
    photoId: String,
    thumbnailBytes: ByteArray, // Downscaled by your app beforehand.
    fullSizePath: String,
) {
    val thumbnail = ditto.store.newAttachment(
        ByteArrayInputStream(thumbnailBytes),
        mapOf("kind" to "thumbnail", "mimeType" to "image/jpeg"),
    )
    val fullSize = ditto.store.newAttachment(fullSizePath, mapOf("kind" to "full", "mimeType" to "image/jpeg"))
    ditto.store.execute(
        "INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)",
        mapOf(
            "photo" to mapOf(
                "_id" to photoId,
                "thumbnail" to thumbnail,
                "image" to fullSize,
                "createdAt" to utcTimestamp(), // Defined in the Timestamps section.
            ),
        ),
    )
}
```

```kotlin
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

// ✅ GOOD: A row fetches only its thumbnail; the full-size image is fetched
// when the user opens it, with a longer stall timeout for the larger file.
class PhotoRowModel(ditto: Ditto, scope: CoroutineScope, photo: DittoCborSerializable.Dictionary) {
    private val thumbnailToken = photo["thumbnail"].attachmentTokenOrNull
    private val fullSizeToken = photo["image"].attachmentTokenOrNull

    val thumbnail = AttachmentLoader(ditto, scope)
    val fullSize = AttachmentLoader(ditto, scope)

    /** Call when the row is shown. */
    fun onShown() {
        thumbnailToken?.let { thumbnail.load(it, stallTimeout = 30.seconds) }
    }

    /** Call when the user opens the photo. */
    fun onOpened() {
        fullSizeToken?.let { fullSize.load(it, stallTimeout = 2.minutes) }
    }

    /** Call when the row and the detail view are gone. */
    fun clear() {
        thumbnail.clear()
        fullSize.clear()
    }
}
```

## IDs and Timestamps in Kotlin

**IDs**: generate a random (version 4) UUID for every new document with `java.util.UUID.randomUUID()`; never derive IDs from a counter or the clock. A `UUID` cannot be passed as an argument value, so pass its `toString()`. Keep human-readable numbers in a separate field. The rules are in [Document IDs](../data-modeling.md#document-ids).

```kotlin
import java.util.UUID

/** Returns a random (version 4) UUID such as "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f". */
fun newId(): String = UUID.randomUUID().toString()

suspend fun createOrder(ditto: Ditto, storeId: String): String {
    val orderId = newId()
    ditto.store.execute(
        "INSERT INTO orders DOCUMENTS (:order)",
        mapOf(
            "order" to mapOf(
                "_id" to orderId,
                "storeId" to storeId,
                "status" to "open",
                "createdAt" to utcTimestamp(), // defined below
            ),
        ),
    )
    return orderId
}
```

```kotlin
// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
fun badSequentialId(dailyCount: Int) = "order-$dailyCount"

// ❌ BAD: Collides when two devices write within the same millisecond.
fun badTimestampId() = "order-${System.currentTimeMillis()}"
```

```kotlin
/**
 * A display label, not an identifier: uniqueness is not guaranteed across
 * devices, so never use it as _id or as a lookup key.
 */
fun displayNumber(terminalCode: String, localSequence: Int): String =
    "$terminalCode-${localSequence.toString().padStart(4, '0')}"

suspend fun createOrderWithLabel(ditto: Ditto, orderId: String, terminalCode: String, localSequence: Int) {
    ditto.store.execute(
        "INSERT INTO orders DOCUMENTS (:order)",
        mapOf(
            "order" to mapOf(
                "_id" to orderId, // UUID
                "displayNumber" to displayNumber(terminalCode, localSequence),
                "createdAt" to utcTimestamp(),
            ),
        ),
    )
}
```

**Timestamps**: store UTC with a zone designator, and produce every timestamp that is sorted or compared with one fixed-precision helper (see [Timestamps](../data-modeling.md#timestamps)). Three details of the JVM and Android make this necessary:

- `Instant.toString()` writes as many fraction digits as needed: `2025-10-09T08:53:20Z` for a whole second, `.100Z` and `.123Z` for milliseconds, and six digits (`.419349Z`) for `Instant.now()` on Android 16. Such strings do not sort chronologically as text (see [In Kotlin, Instant.toString() varies its precision](../../knowledge/observations/kotlin-sdk.md#in-kotlin-instanttostring-varies-its-precision)).
- `LocalDateTime.now().toString()` has no zone designator, for which DQL date functions return `MISSING` without an error, and `Instant` and `java.util.Date` cannot be passed as argument values at all.
- `java.time` is part of Android from API level 26. With `minSdk` 24, enable core library desugaring in your Gradle file, or use epoch milliseconds (`System.currentTimeMillis()`), the compact alternative.

```kotlin
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val utcMillis: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

/**
 * Returns the time as an ISO-8601 UTC string with exactly millisecond
 * precision, e.g. "2026-10-08T10:30:00.123Z".
 */
fun utcTimestamp(time: Instant = Instant.now()): String = utcMillis.format(time)

// ✅ GOOD: Consistent UTC timestamps from the one helper.
suspend fun markReady(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET readyAt = :readyAt WHERE _id = :id",
        mapOf("id" to orderId, "readyAt" to utcTimestamp()),
    )
}
```

```kotlin
import java.time.LocalDateTime

// ❌ BAD: Local time without a zone. DQL date functions return MISSING for it,
// and values written in different time zones do not compare correctly.
suspend fun markReadyLocalTime(ditto: Ditto, orderId: String) {
    ditto.store.execute(
        "UPDATE orders SET readyAt = :readyAt WHERE _id = :id",
        mapOf("id" to orderId, "readyAt" to LocalDateTime.now().toString()), // lint-ignore
    )
}
```

## Transports and Presence in Kotlin

`DittoTransportConfig` is immutable. Change it with `ditto.updateTransportConfig { config -> ... }`, which gives you a builder initialized with the current configuration. Never assign a new `DittoTransportConfig()`: it has every transport disabled, whereas a new instance starts with Bluetooth LE, LAN, and Wi-Fi Aware enabled (see [In Kotlin, an empty DittoTransportConfig turns every transport off](../../knowledge/observations/kotlin-sdk.md#in-kotlin-an-empty-dittotransportconfig-turns-every-transport-off) and, for the other SDKs, [A new instance enables the platform's peer-to-peer transports, and an empty configuration enables none](../../knowledge/observations/connections-and-presence.md#a-new-instance-enables-the-platforms-peer-to-peer-transports-and-an-empty-configuration-enables-none)). The rules are in [Transport Configuration](../setup-and-lifecycle.md#transport-configuration).

```kotlin
// ✅ GOOD: Adjust the current configuration with the builder.
fun configureTransports(ditto: Ditto) {
    ditto.updateTransportConfig { config ->
        config.peerToPeer.lan.enabled = true
        config.peerToPeer.wifiAware.enabled = true
        config.peerToPeer.bluetoothLe.enabled = false // for example, LAN and Wi-Fi Aware only
    }
}
```

```kotlin
// ✅ GOOD: A hub device listens on TCP; other devices connect to it.
fun configureHub(ditto: Ditto) {
    ditto.updateTransportConfig { config ->
        config.listen.tcp.enabled = true
        config.listen.tcp.interfaceIp = "[::]"
        config.listen.tcp.port = 4040
    }
}

fun connectToHub(ditto: Ditto) {
    ditto.updateTransportConfig { config ->
        config.connect.tcpServers.add("192.168.1.10:4040")
        // Additional WebSocket endpoints, if you run your own:
        // config.connect.websocketUrls.add("wss://sync.example.com")
    }
}
```

```kotlin
// ✅ GOOD: A hub that serves up to 12 TCP clients. The limit is part of the
// hub's configuration, so it is applied on every open, before sync starts
// (SDK 5.2+).
fun hubConfig(connect: DittoConfig.Connect) = DittoConfig(
    databaseId = "YOUR_DATABASE_ID",
    connect = connect,
    systemParameters = mapOf("MESH_CHOOSER_MAX_WLAN_CONNECTIONS" to 12),
)

// Call with an instance created from hubConfig(), after the authentication
// handler or the offline license token is set.
fun startHub(ditto: Ditto) {
    ditto.updateTransportConfig { config ->
        config.listen.tcp.enabled = true
        config.listen.tcp.interfaceIp = "[::]"
        config.listen.tcp.port = 4040
    }
    ditto.sync.start()
}
```

**Transport conditions and permissions**: `ditto.transportCondition` is a `Flow<DittoTransportConditionEvent>` that reports why a transport is not working (`condition`, such as `NoBleCentralPermission` or `BleDisabled`, and `subsystem`); collect it in a scope that you cancel when you no longer need it. `DittoSyncPermissions(context)` reports which runtime permissions Ditto needs and which are missing; since SDK 5.2, `requiredPermissions()` and `missingPermissions()` cover only the generally available transports, and `requiredMulticastPermissions()` returns the permissions that multicast needs (see [Diagnosing transport problems (SDK 5.1+)](../setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51)).

```kotlin
import android.content.Context
import android.util.Log

// ✅ GOOD: Surface transport problems and missing permissions.
fun watchTransports(ditto: Ditto, context: Context, scope: CoroutineScope): Job {
    val permissions = DittoSyncPermissions(context)
    val missing = permissions.missingPermissions()
    if (missing.isNotEmpty()) {
        Log.w("App", "Ditto is missing Android permissions: ${missing.joinToString()}")
    }
    val multicast = permissions.missingPermissions(permissions.requiredMulticastPermissions())
    if (multicast.isNotEmpty()) {
        Log.d("App", "Multicast would also need: ${multicast.joinToString()}")
    }
    return scope.launch {
        ditto.transportCondition.collect { event ->
            if (event.condition != DittoTransportCondition.Ok) {
                Log.w("App", "Transport ${event.subsystem}: ${event.condition}")
            }
        }
    }
}
```

**Presence**: `ditto.presence.observe()` returns a `Flow<DittoPresenceGraph>`, and `ditto.presence.graph` the current graph. `graph.localPeer` is this device, and `graph.remotePeers` is a `List<DittoPeer>` with `peerKey`, `deviceName`, `os`, `dittoSdkVersion`, `isConnectedToDittoServer`, `connections` (with `peer1`, `peer2`, and `connectionType`), and `peerMetadata`. Set this device's metadata with `ditto.presence.setPeerMetadata(mapOf("role" to "cashier"))` and its name with `ditto.deviceName`; on the Android Emulator, the default name is the device model, such as `sdk_gphone64_arm64` (see [Presence](../setup-and-lifecycle.md#presence)).

```kotlin
data class PeerRow(val name: String, val route: String)

// ✅ GOOD: Show connected peers; the observation ends with the scope.
// In a ViewModel, pass viewModelScope as scope.
class PeerListModel(ditto: Ditto, scope: CoroutineScope) {
    val peers: StateFlow<List<PeerRow>> = ditto.presence.observe()
        .map { graph ->
            val localKey = graph.localPeer.peerKey
            graph.remotePeers.map { peer -> PeerRow(peer.deviceName, route(peer, localKey)) }
        }
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // A peer's connections include its links to other peers, so only the
    // connections that have this device at one end make it a direct neighbor.
    private fun route(peer: DittoPeer, localKey: String): String {
        val directTypes = peer.connections
            .filter { it.peer1 == localKey || it.peer2 == localKey }
            .map { it.connectionType.name }
            .toSet()
        val route = if (directTypes.isEmpty()) "Through other peers" else "Direct (${directTypes.joinToString()})"
        return if (peer.isConnectedToDittoServer) "$route, connected to Ditto Server" else route
    }
}
```

**Incoming connections**: `ditto.presence.connectionRequestHandler` receives each connection request in a suspending `handleConnectionRequest` and returns `DittoConnectionRequestAuthorization.Allow` or `Deny`; set it to `null` to remove it. A denied peer does not connect; in small-peers-only mode, `identityServiceMetadata` is empty (`{}`), and `peerMetadata` carries what the other device set (see [Controlling Incoming Connections](../security.md#controlling-incoming-connections) and [In Kotlin, a connection request handler that denies keeps the peer out](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-connection-request-handler-that-denies-keeps-the-peer-out)).

> **Note (SDK 5.1.0 and 5.2.0):** A connection request handler that throws ends the app. In our testing on the Android emulator, the process ended with `SIGABRT` as soon as the handler threw, in every run, also when the scope passed to `DittoFactory.create` had a `CoroutineExceptionHandler` and when the app had set `Thread.setDefaultUncaughtExceptionHandler`: neither is a safety net, so catch the exception inside the handler. A handler that has not returned after 10 seconds keeps running after Ditto has rejected the peer: Ditto logged `DANGER: onConnecting callback task blocked for longer than timeout and can't be cancelled`, the next connection attempt waited until the handler returned, and a handler that never returned kept every new peer out, while peers that were already connected kept syncing. Setting `connectionRequestHandler` to `null` then did not return, and closing Ditto, which cancels the handler's coroutine, ended the app (see [A connection request handler that does not answer within 10 seconds rejects the peer, and one that throws differs by SDK](../../knowledge/observations/connections-and-presence.md#a-connection-request-handler-that-does-not-answer-within-10-seconds-rejects-the-peer-and-one-that-throws-differs-by-sdk)). Catch every exception in the handler, as the example below does, and return well within 10 seconds.

```kotlin
import org.json.JSONObject

// ✅ GOOD: Accept only peers whose signed metadata belongs to this store.
// Requires DittoConfig.Connect.Server: identityServiceMetadata comes from your
// authentication webhook and is empty in small-peers-only mode.
fun restrictConnectionsToStore(ditto: Ditto, storeId: String) {
    ditto.presence.connectionRequestHandler = DittoPresence.ConnectionRequestHandler { request ->
        try {
            val metadata = JSONObject(request.identityServiceMetadataJsonString)
            if (metadata.optString("storeId") == storeId) {
                DittoConnectionRequestAuthorization.Allow
            } else {
                DittoConnectionRequestAuthorization.Deny
            }
        } catch (error: Exception) {
            DittoConnectionRequestAuthorization.Deny // an exception that escapes ends the app
        }
    }
}
```

## Logging in Kotlin

`DittoLogger` is an `object`. Configure it before you create Ditto, so that startup is logged with your settings; it works before the first `DittoFactory.create` (see [In Kotlin, DittoLogger works before the first create, and logs go to logcat](../../knowledge/observations/kotlin-sdk.md#in-kotlin-dittologger-works-before-the-first-create-and-logs-go-to-logcat)). The levels are `DittoLogLevel.Error`, `Warning`, `Info`, `Debug`, and `Verbose`. On Android, the SDK writes its log to logcat with the tag `Ditto`. The rules are in [Logging](../logging-and-observability.md#logging).

```kotlin
/** Call before DittoFactory.create(). */
fun configureDittoLogging(debug: Boolean) {
    DittoLogger.isEnabled = true
    DittoLogger.minimumLogLevel = if (debug) DittoLogLevel.Debug else DittoLogLevel.Warning
}
```

`DittoLogger.observeLogEvents()` returns a `Flow` of the log events (`level` and `message`) that Ditto emits. Collect it in a scope that lives as long as you want the logs forwarded, and cancel the coroutine to stop:

```kotlin
/** Forwards Ditto warnings and errors to the app's logging pipeline until the returned Job is cancelled. */
fun forwardDittoLogs(scope: CoroutineScope, report: (String) -> Unit): Job =
    scope.launch {
        DittoLogger.observeLogEvents().collect { event ->
            if (event.level == DittoLogLevel.Error || event.level == DittoLogLevel.Warning) {
                report("[ditto ${event.level}] ${event.message}")
            }
        }
    }
```

`DittoLogger.exportToFile(path)` writes the on-disk logs and returns the number of bytes it wrote; it throws `DittoException.IoException` (`File exists (os error 17)`) if the file exists (see [On-disk logs and exporting them](../logging-and-observability.md#on-disk-logs-and-exporting-them)):

```kotlin
import android.util.Log
import java.io.File

/**
 * Exports Ditto's on-disk logs, for example for a "Send diagnostics" button.
 * [directory] must exist, for example context.cacheDir.
 */
suspend fun exportDittoLogs(directory: File): File {
    val file = File(directory, "ditto-logs-${System.currentTimeMillis()}.jsonl.gz")
    val bytes = DittoLogger.exportToFile(file.absolutePath)
    Log.d("App", "Exported $bytes bytes of Ditto logs to ${file.path}")
    return file
}
```

A support bundle (SDK 5.2+) is created with DQL and fetched like any other attachment (see [Support bundles (SDK 5.2+)](../logging-and-observability.md#support-bundles-sdk-52)):

```kotlin
// ✅ GOOD: Create a support bundle and save it, for example to share it with
// Ditto support. [path] must not exist yet.
suspend fun saveSupportBundle(ditto: Ditto, path: String) {
    val token = ditto.store.execute("EXECUTE FUNCTION system_request_support_bundle()") { result ->
        result.items.single().value["file"].attachmentToken
    }
    when (val fetched = ditto.store.fetchAttachment(token)) {
        is DittoAttachmentFetchResult.Completed -> fetched.attachment.copyToPath(path)
        is DittoAttachmentFetchResult.Deleted -> showError("The support bundle was deleted")
    }
}
```

**Storage snapshot**: read `system:system_info` with `execute` when you need it, ordered by `timestamp`, and let later rows of a key overwrite earlier ones (see [Monitoring Storage](../deletion-and-storage.md#monitoring-storage)).

```kotlin
import org.json.JSONObject

// ✅ GOOD: Read the latest storage snapshot on demand (for example from a
// diagnostics screen or a daily maintenance task).
suspend fun storageSnapshot(ditto: Ditto): Map<String, Any?> =
    ditto.store.execute(
        "SELECT key, value, timestamp FROM system:system_info " +
            "WHERE key LIKE 'fs_%' OR key LIKE 'collection_num_docs%' " +
            "ORDER BY timestamp ASC",
    ) { result ->
        val snapshot = mutableMapOf<String, Any?>()
        for (item in result.items) {
            val row = JSONObject(item.jsonString())
            // Later rows overwrite earlier ones, so the newest value wins.
            snapshot[row.getString("key")] = row.opt("value")
        }
        snapshot
    }
```

## Testing in Kotlin

Tests that open Ditto need the SDK's native library, so run them as instrumented tests (`androidTest`) on an emulator or a device, with JUnit 4 and `runBlocking`. The tests below are classes that extend the helper from [A local-store test helper in Kotlin](#a-local-store-test-helper-in-kotlin), which provides `ditto`; they need `import org.junit.Test` and the `org.junit.Assert` functions they use. What each test checks is described in [Testing Strategies](../testing.md).

```kotlin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OrderMergeTest : DittoStoreTest() {
    @Test
    fun addingALineItemKeepsTheExistingItems() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:order)",
            mapOf("order" to mapOf("_id" to "order-1", "items" to mapOf("item-1" to mapOf("productId" to "p1", "quantity" to 2)))),
        )

        // The code under test: an upsert of a partial document (see "Arrays and Maps").
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            mapOf("patch" to mapOf("_id" to "order-1", "items" to mapOf("item-2" to mapOf("productId" to "p2", "quantity" to 1)))),
        )

        val items = ditto.store.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to "order-1")) { result ->
            result.items.first().value["items"].dictionaryOrNull // a map, not an array
        }
        assertEquals(setOf("item-1", "item-2"), items?.keys?.map { it.string }?.toSet())
    }

    @Test
    fun reUpsertingUnchangedDataIsANoOp() = runBlocking<Unit> {
        val product = mapOf("_id" to "p1", "name" to "Pen", "priceCents" to 250)
        val upsert = "INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF"
        ditto.store.execute(upsert, mapOf("product" to product))

        val changed = ditto.store.execute(upsert, mapOf("product" to product)) { it.mutatedDocumentIds() }
        assertTrue(changed.isEmpty())
    }

    // The code under test: the app's replaceAddress() (see "Assigning an object merges it").
    private suspend fun replaceAddress(ditto: Ditto, customerId: String, address: Map<String, Any?>) {
        ditto.store.transaction(hint = "replaceAddress") { tx ->
            tx.execute("UPDATE customers UNSET address WHERE _id = :id", mapOf("id" to customerId))
            tx.execute("UPDATE customers SET address = :address WHERE _id = :id", mapOf("id" to customerId, "address" to address))
            DittoTransaction.Result.Commit(Unit)
        }
    }

    @Test
    fun replaceAddressRemovesKeysThatAreNotInTheNewAddress() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO customers DOCUMENTS (:customer)",
            mapOf("customer" to mapOf("_id" to "c1", "address" to mapOf("city" to "Oslo", "zip" to "0150"))),
        )

        replaceAddress(ditto, "c1", mapOf("city" to "Bergen"))

        val address = ditto.store.execute("SELECT * FROM customers WHERE _id = :id", mapOf("id" to "c1")) { result ->
            result.items.first().value["address"].dictionary.mapKeys { it.key.string }.mapValues { it.value.string }
        }
        // A plain SET would keep "zip": objects merge under the default settings.
        assertEquals(mapOf("city" to "Bergen"), address)
    }
}
```

```kotlin
import org.junit.Assert.assertEquals
import org.junit.Test

class DeletionTest : DittoStoreTest() {
    @Test
    fun activeOrdersQueryTreatsAMissingOrNullFlagAsNotDeleted() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:orders)",
            mapOf(
                "orders" to listOf(
                    mapOf("_id" to "deleted", "isDeleted" to true),
                    mapOf("_id" to "active", "isDeleted" to false),
                    mapOf("_id" to "nullFlag", "isDeleted" to null),
                    mapOf("_id" to "noFlag"),
                ),
            ),
        )

        // The query used by the app's repository.
        val ids = ditto.store.execute(
            "SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id",
        ) { result -> result.items.map { it.value["_id"].string } }
        assertEquals(listOf("active", "noFlag", "nullFlag"), ids)
    }

    @Test
    fun deletingByIdRemovesExactlyTheListedDocuments() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:orders)",
            mapOf("orders" to listOf(mapOf("_id" to "o1"), mapOf("_id" to "o2"), mapOf("_id" to "o3"))),
        )

        // The statement used by the app; WHERE _id IN :ids, not USE IDS.
        val deleted = ditto.store.execute("DELETE FROM orders WHERE _id IN :ids", mapOf("ids" to listOf("o1", "o2"))) {
            it.mutatedDocumentIds().size
        }
        assertEquals(2, deleted)

        val remaining = ditto.store.execute("SELECT _id FROM orders") { result -> result.items.map { it.value["_id"].string } }
        assertEquals(listOf("o3"), remaining)
    }
}
```

```kotlin
import org.junit.Assert.assertEquals
import org.junit.Test

class ObserverTest : DittoStoreTest() {
    @Test
    fun observerSeesANewOrderAndIsRemovedWhenCancelled() = runBlocking<Unit> {
        val orders = ditto.store.observe(
            "SELECT * FROM orders WHERE status = :status ORDER BY _id",
            mapOf("status" to "open"),
        ) { result -> result.items.map { it.value["_id"].string } }

        val sawOrder = async { withTimeout(5_000) { orders.first { it == listOf("order-1") } } }
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:order)",
            mapOf("order" to mapOf("_id" to "order-1", "status" to "open")),
        )
        sawOrder.await()

        // first() cancelled the collection, which removed the observer.
        assertEquals(0, ditto.store.observers.size)
    }
}
```

For tests of classes that own observers (a `ViewModel` and its `StateFlow`), keep the query behind your own interface and pass a `Flow` that the test controls.

`registerSubscription` throws `DittoException.StoreException` for a query that subscriptions do not accept:

<!-- expect-error -->
```kotlin
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionTest : DittoStoreTest() {
    @Test
    fun subscriptionsWithOrderByOrLimitAreRejected() {
        assertThrows(DittoException.StoreException::class.java) {
            ditto.sync.registerSubscription("SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50")
        }
    }

    @Test
    fun theAppsSubscriptionsAreValid() {
        val subscriptions = listOf(
            ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to "store-1")),
            ditto.sync.registerSubscription("SELECT * FROM products"),
        )
        for (subscription in subscriptions) {
            subscription.close()
            assertTrue(subscription.isClosed)
        }
    }
}
```

```kotlin
import org.junit.Assert.assertTrue
import org.junit.Test

class StatementTest : DittoStoreTest() {
    /**
     * The app's statements with representative arguments. In a real app, keep
     * the statement strings in your repository and reference them here.
     */
    private val appStatements = mapOf(
        "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC" to mapOf("status" to "open"),
        "UPDATE orders SET status = :status WHERE _id = :id" to mapOf("status" to "closed", "id" to "order-1"),
        "DELETE FROM orders WHERE _id IN :ids" to mapOf("ids" to listOf("order-1")),
    )

    @Test
    fun everyAppStatementCanBePlanned() = runBlocking<Unit> {
        for ((statement, arguments) in appStatements) {
            // EXPLAIN throws if a statement cannot be parsed or planned.
            ditto.store.execute("EXPLAIN $statement", arguments)
        }
    }

    @Test
    fun theOpenOrdersQueryUsesItsIndex() = runBlocking<Unit> {
        // In your suite, create indexes with the same startup code as the app
        // (for example, by overriding configure() of the helper).
        ditto.store.execute(
            "CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)",
        )
        val plan = ditto.store.execute(
            "EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC",
            mapOf("status" to "open"),
        ) { result -> result.items.first().jsonString() }
        assertTrue(plan.contains("indexScan"))
    }
}
```

### A local-store test helper in Kotlin

The class below opens a small-peers-only instance in its own directory before each test and closes and deletes it after the test, also when the test fails (see [A Test Helper for a Local Store](../testing.md#a-test-helper-for-a-local-store)). Override `systemParameters` with the same map that your app passes in its `DittoConfig`, and `configure` with the indexes that your app creates at startup.

```kotlin
// app/src/androidTest/java/com/example/orders/DittoStoreTest.kt
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/** Opens a Ditto instance for each test. Sync is never started, so no license token or network is needed. */
abstract class DittoStoreTest {
    protected lateinit var ditto: Ditto
    private lateinit var directory: File

    /** The same parameters as the app's DittoConfig (SDK 5.2+). */
    protected open val systemParameters: Map<String, Any> = emptyMap()

    /** Creates the app's indexes, as at app startup. */
    protected open suspend fun configure(ditto: Ditto) {}

    @Before
    fun openStore() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        directory = File(context.cacheDir, "ditto-test-${UUID.randomUUID()}")
        ditto = DittoFactory.create(
            DittoConfig(
                // Any UUID works for local tests; each test gets its own directory.
                databaseId = "00000000-0000-4000-8000-000000000001",
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = directory.absolutePath,
                systemParameters = systemParameters,
            ),
        )
        runBlocking { configure(ditto) }
    }

    @After
    fun closeStore() {
        ditto.close()
        directory.deleteRecursively()
    }
}

// Every test starts with an empty store.
class EmptyStoreTest : DittoStoreTest() {
    @Test
    fun aNewStoreIsEmpty() = runBlocking<Unit> {
        val count = ditto.store.execute("SELECT COUNT(*) AS n FROM orders") { it.items.first().value["n"].long }
        assertEquals(0L, count)
    }
}
```

**Running the tests:** run them with `./gradlew connectedAndroidTest` on an emulator or a device. Tests that use only a fake of your own interface run as plain JVM unit tests.

### Several peers in one test in Kotlin

The helpers below open several small peers in one instrumented test process and connect them over TCP on `127.0.0.1` only, inside the emulator or device (see [Several peers in one test process](../testing.md#several-peers-in-one-test-process)). Pass the offline license token as an instrumentation argument, for example `./gradlew connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.dittoLicenseToken=...`, and never commit it.

```kotlin
// app/src/androidTest/java/com/example/orders/MultiPeerTest.kt
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Opens [count] peers in this process that sync with each other over TCP on
 * localhost only: peer 0 listens, the others connect to it. A device accepts
 * at most 6 TCP connections by default, so keep [count] at 7 or below.
 */
suspend fun openSyncedPeers(
    count: Int,
    licenseToken: String,
    port: Int = 4041,
    databaseId: String = "00000000-0000-4000-8000-000000000002",
    configure: suspend (Ditto) -> Unit = {},
): List<Ditto> {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val peers = mutableListOf<Ditto>()
    for (i in 0 until count) {
        val ditto = DittoFactory.create(
            DittoConfig(
                // All peers of a group use the same database ID; give every group
                // that can run at the same time its own ID and port.
                databaseId = databaseId,
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = File(context.cacheDir, "ditto-peer$i-${UUID.randomUUID()}").absolutePath,
            ),
        )
        peers += ditto
        ditto.setOfflineOnlyLicenseToken(licenseToken)
        ditto.updateTransportConfig { config ->
            // No Bluetooth, LAN, or Wi-Fi Aware.
            config.peerToPeer.bluetoothLe.enabled = false
            config.peerToPeer.lan.enabled = false
            config.peerToPeer.wifiAware.enabled = false
            // Every peer listens on this device only; peer 0 on the known port.
            config.listen.tcp.enabled = true
            config.listen.tcp.interfaceIp = "127.0.0.1"
            config.listen.tcp.port = if (i == 0) port else 0
            if (i > 0) config.connect.tcpServers.add("127.0.0.1:$port")
        }
        configure(ditto) // App setup after open, such as indexes.
        ditto.sync.start()
    }
    waitUntil { peers.all(::isConnected) }
    return peers
}

fun isConnected(ditto: Ditto): Boolean = ditto.presence.graph.remotePeers.isNotEmpty()

suspend fun waitUntil(timeoutMillis: Long = 15_000, condition: () -> Boolean) {
    withTimeout(timeoutMillis) {
        while (!condition()) delay(100)
    }
}

/** Stops sync on every peer, runs [writes] while they are disconnected, then reconnects them. */
suspend fun whileDisconnected(peers: List<Ditto>, writes: suspend () -> Unit) {
    peers.forEach { it.sync.stop() }
    waitUntil { peers.none(::isConnected) }
    writes()
    peers.forEach { it.sync.start() }
    waitUntil { peers.all(::isConnected) }
}

/** Waits until [query] returns the same rows on every peer and [until] holds, then returns the rows. */
suspend fun waitForConvergence(
    peers: List<Ditto>,
    query: String,
    arguments: Map<String, Any?> = emptyMap(),
    until: (List<JSONObject>) -> Boolean = { true },
    timeoutMillis: Long = 15_000,
): List<JSONObject> = withTimeout(timeoutMillis) {
    var results: List<List<JSONObject>>
    do {
        results = peers.map { peer ->
            peer.store.execute(query, arguments) { result -> result.items.map { JSONObject(it.jsonString()) } }
        }
        val first = results.first()
        val converged = results.all { rows -> rows.map(JSONObject::toString) == first.map(JSONObject::toString) } &&
            until(first)
        if (!converged) delay(100)
    } while (!converged)
    results.first()
}

open class MultiPeerTest {
    /** The offline license token; override to read it from elsewhere. */
    protected open val licenseToken: String? =
        InstrumentationRegistry.getArguments().getString("dittoLicenseToken")
    private var peers: List<Ditto> = emptyList()

    @After
    fun closePeers() {
        peers.forEach { it.close() }
    }

    @Test
    fun concurrentEditsOfDifferentLineItemsBothSurvive() = runBlocking<Unit> {
        val token = licenseToken
        assumeTrue("Needs the dittoLicenseToken instrumentation argument", !token.isNullOrEmpty())
        peers = openSyncedPeers(2, token!!)
        val (tablet, phone) = peers
        peers.forEach { it.sync.registerSubscription("SELECT * FROM orders") }
        tablet.store.execute(
            "INSERT INTO orders DOCUMENTS (:order)",
            mapOf("order" to mapOf("_id" to "order-1", "items" to mapOf("item-1" to mapOf("productId" to "p1", "quantity" to 1)))),
        )
        waitForConvergence(peers, "SELECT * FROM orders", until = { it.size == 1 })

        // The code under test would be the app's repository functions.
        whileDisconnected(peers) {
            tablet.store.execute("UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id", mapOf("id" to "order-1"))
            phone.store.execute(
                "UPDATE orders SET items.`item-2` = :item WHERE _id = :id",
                mapOf("id" to "order-1", "item" to mapOf("productId" to "p2", "quantity" to 1)),
            )
        }

        val rows = waitForConvergence(
            peers,
            "SELECT * FROM orders WHERE _id = :id",
            mapOf("id" to "order-1"),
            until = { it.single().getJSONObject("items").length() == 2 },
        )
        val items = rows.single().getJSONObject("items")
        assertEquals(3, items.getJSONObject("item-1").getInt("quantity"))
        assertEquals("p2", items.getJSONObject("item-2").getString("productId"))
    }
}
```

## Behavior Specific to the Kotlin SDK

The notes below collect what the Kotlin SDK does differently from the other SDKs, each with the observation that it is based on. Each is also described in the section where it matters.

- **Note (SDK 5.1.0 and 5.2.0):** A connection request handler that throws ends the app, and one that does not return keeps new peers out, cannot be removed, and ends the app when Ditto closes; catch every exception and return quickly ([Transports and Presence in Kotlin](#transports-and-presence-in-kotlin)). See [A connection request handler that does not answer within 10 seconds rejects the peer, and one that throws differs by SDK](../../knowledge/observations/connections-and-presence.md#a-connection-request-handler-that-does-not-answer-within-10-seconds-rejects-the-peer-and-one-that-throws-differs-by-sdk).
- **Note (SDK 5.1.0 and 5.2.0):** Observer handlers, the expiration handler, and connection request handlers run in the scope that `DittoFactory.create` received; the default scope on Android is `MainScope()`, so they run on the main thread ([In Kotlin, observer handlers run on the main thread unless DittoFactory.create gets another scope](../../knowledge/observations/kotlin-sdk.md#in-kotlin-observer-handlers-run-on-the-main-thread-unless-dittofactorycreate-gets-another-scope)).
- **Note (SDK 5.1.0 and 5.2.0):** `store.execute` blocks the thread of the coroutine that calls it while the query runs and while it waits for a write transaction, so many waiting writes can take every thread of `Dispatchers.IO` ([In Kotlin, store.execute blocks the thread of its caller](../../knowledge/observations/kotlin-sdk.md#in-kotlin-storeexecute-blocks-the-thread-of-its-caller), [In Kotlin, writes that wait behind a transaction each hold a thread](../../knowledge/observations/kotlin-sdk.md#in-kotlin-writes-that-wait-behind-a-transaction-each-hold-a-thread)).
- **Note (SDK 5.1.0 and 5.2.0):** `store.execute` without a handler returns `Unit`, and a result is closed when its handler returns; reading it afterwards throws `IllegalStateException` ([In Kotlin, query results are closed when the execute handler returns, and by close()](../../knowledge/observations/kotlin-sdk.md#in-kotlin-query-results-are-closed-when-the-execute-handler-returns-and-by-close)).
- **Note (SDK 5.1.0 and 5.2.0):** A `registerObserver` handler that throws closes its observer; the SDK logs the error, and nothing reaches your code ([In Kotlin, an observer whose handler throws is closed, and the exception is only logged](../../knowledge/observations/kotlin-sdk.md#in-kotlin-an-observer-whose-handler-throws-is-closed-and-the-exception-is-only-logged)).
- **Note (SDK 5.1.0 and 5.2.0):** A write through `store.execute` inside a transaction, and a read-write transaction inside another, deadlock without an exception, and `close()` then never returns ([In Kotlin, store.execute writes inside a transaction deadlock](../../knowledge/observations/kotlin-sdk.md#in-kotlin-storeexecute-writes-inside-a-transaction-deadlock), [In Kotlin, a read-write transaction inside a read-write transaction deadlocks](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-read-write-transaction-inside-a-read-write-transaction-deadlocks)).
- **Note (SDK 5.1.0 and 5.2.0):** `close()` waits for an open transaction; `execute` calls in flight when it runs may throw although their writes were stored ([In Kotlin, close() waits for an open transaction](../../knowledge/observations/kotlin-sdk.md#in-kotlin-close-waits-for-an-open-transaction), [In Kotlin, writes in flight when close() runs are stored even when the call throws](../../knowledge/observations/kotlin-sdk.md#in-kotlin-writes-in-flight-when-close-runs-are-stored-even-when-the-call-throws)).
- **Note (SDK 5.1.0 and 5.2.0):** Opening a directory that the process already has open throws `StoreException` after about a second ([In Kotlin, opening an open directory again fails after about a second](../../knowledge/observations/kotlin-sdk.md#in-kotlin-opening-an-open-directory-again-fails-after-about-a-second)).
- **Note (SDK 5.1.0 and 5.2.0):** Subscriptions and observers keep running after their handles are garbage-collected ([In Kotlin, garbage-collected subscriptions and observers keep running](../../knowledge/observations/kotlin-sdk.md#in-kotlin-garbage-collected-subscriptions-and-observers-keep-running)).
- **Note (SDK 5.1.0 and 5.2.0):** A decimal that a 32-bit float holds exactly, such as `7.5`, comes back as a `FloatValue`, for which `doubleOrNull` returns `null` ([In Kotlin, a decimal that a 32-bit float holds exactly comes back as a FloatValue](../../knowledge/observations/kotlin-sdk.md#in-kotlin-a-decimal-that-a-32-bit-float-holds-exactly-comes-back-as-a-floatvalue)).
- **Note (SDK 5.1.0 and 5.2.0):** `Date`, `Instant`, `UUID`, `BigDecimal`, and `BigInteger` cannot be passed as argument values, NaN and infinity fail the write, and a lone surrogate is stored as `?` ([Kotlin values that are not plain JSON fail or change when stored](../../knowledge/observations/kotlin-sdk.md#kotlin-values-that-are-not-plain-json-fail-or-change-when-stored)).
- **Note (SDK 5.1.0):** Negative integers in map arguments were stored as one less ([On Kotlin SDK 5.1.0, negative integers in map arguments were stored as one less](../../knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-negative-integers-in-map-arguments-were-stored-as-one-less)).
- **Note (SDK 5.1.0):** On a device connected to a peer in another process, a read of `system:data_sync_info` stopped responding in 14 of 45 runs, and later reads of it and `close()` did as well; on 5.2.0, no read got stuck in 41 runs. Give each read a deadline, as `waitUntilServerHas` in [Closing Ditto in Kotlin](#closing-ditto-in-kotlin) does ([On Kotlin SDK 5.1.0, a read of system:data_sync_info could stop responding](../../knowledge/observations/kotlin-sdk.md#on-kotlin-sdk-510-a-read-of-systemdata_sync_info-could-stop-responding)).
- **Note (SDK 5.2.0):** `login()` throws `AuthenticationException`, and an expiration handler that throws is only logged ([In Kotlin, login() throws, and a throwing expiration handler is only logged](../../knowledge/observations/kotlin-sdk.md#in-kotlin-login-throws-and-a-throwing-expiration-handler-is-only-logged)).
- **Documentation:** The encryption example in the Kotlin 5.2.0 release notes calls `Ditto.open(config)`, which the Kotlin SDK does not have; use `DittoFactory.create(config)`.
