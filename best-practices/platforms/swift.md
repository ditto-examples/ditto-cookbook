# Ditto on Swift

This page shows how to apply the guide with the Swift SDK, DittoSwift 5.2.0: the API calls, the patterns for SwiftUI, Swift concurrency, and the app lifecycle, and the behavior that is specific to this SDK. The rules themselves, the DQL, and the reasons are on the topic pages of the guide, which apply to every SDK; each section below links to them. The same sections exist for [Flutter](flutter.md), [JavaScript](javascript.md), and [Kotlin](kotlin.md).

Every example imports the SDK with `import DittoSwift` (and `Foundation`, `SwiftUI`, or `UIKit` where it uses them). Placeholders such as `"YOUR_DATABASE_ID"`, `fetchAuthToken()`, and `showError(_:)` stand for values and code from your own app. The examples were built against DittoSwift 5.2.0 in the Swift 5 language mode and run against real stores on macOS and in the iOS simulator.

## Installing the Swift SDK

DittoSwift 5.2.0 has the following requirements:

| Item | Requirement |
|---|---|
| iOS | 15 or later |
| Mac Catalyst | 15 or later |
| macOS | 12 or later (AppKit) |
| Architectures | arm64 only: the package has `ios-arm64`, `ios-arm64-simulator`, `ios-arm64-maccatalyst`, and `macos-arm64` slices (Intel Macs and tvOS are no longer supported since SDK 5.1) |
| Package manager | Swift Package Manager, from `https://github.com/getditto/DittoSwiftPackage` (product `DittoSwift`) |

Pin the SDK version, so that every developer and CI build uses the same release. In Xcode, choose the dependency rule **Exact Version** `5.2.0`; in a `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OrdersFeature",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [
        // or from: "5.2.0" to accept compatible 5.x updates
        .package(url: "https://github.com/getditto/DittoSwiftPackage", exact: "5.2.0"),
    ],
    targets: [
        .target(name: "OrdersFeature", dependencies: [
            .product(name: "DittoSwift", package: "DittoSwiftPackage"),
        ]),
    ]
)
```

**Platform setup**: Peer-to-peer sync needs usage descriptions in `Info.plist` and, to keep syncing in the background or while the device is locked, the Bluetooth background modes **Uses Bluetooth LE accessories** and **Acts as a Bluetooth LE accessory**. Follow the [Swift install guide](https://docs.ditto.live/sdk/latest/install-guides/swift) for the current list:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Uses Bluetooth to connect and sync with nearby devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Uses Bluetooth to connect and sync with nearby devices.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Uses WiFi to connect and sync with nearby devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_http-alt._tcp.</string>
</array>
```

iOS asks the user for these permissions the first time Ditto uses Bluetooth or the local network, that is, after `ditto.sync.start()`. If you enable the Data Protection entitlement, use `NSFileProtectionCompleteUntilFirstUserAuthentication`, so that Ditto can open its files while the device is locked after the first unlock.

## Opening Ditto in Swift

- `try await Ditto.open(config:)` is the standard way to create an instance. There is no separate initialization step: `DittoLogger` and `Ditto.defaultRootDirectory` can be used before any instance exists.
- `try Ditto.openSync(config:)` opens on the calling thread and blocks it until the store is open. Use it only where you cannot `await`, never on the main thread.
- `Ditto` and the objects it hands out (`store`, `sync`, `presence`, observers, subscriptions) are `Sendable` classes. Use the same instance from any actor or thread.

```swift
import DittoSwift

// ✅ GOOD (only where you cannot await, and never on the main thread):
// openSync blocks the calling thread until the store is open.
func openFromSynchronousCode() throws -> Ditto {
    // connect is the small-peers-only mode without a key here, which does not
    // authenticate peers; see "DittoConfig in Swift".
    try Ditto.openSync(config: DittoConfig(databaseID: "YOUR_DATABASE_ID", connect: .smallPeersOnly()))
}
```

`ditto.store`, `ditto.sync`, and `ditto.presence` reference the `Ditto` instance **weakly**: holding one of them does not keep Ditto alive. Keep a strong reference to the `Ditto` instance itself for as long as any part of the app uses it (see [Closing Ditto in Swift](#closing-ditto-in-swift)).

### DittoConfig in Swift

`DittoConfig` is a `Sendable`, `Codable` struct with `var` fields. Its fields, as described in [DittoConfig](../setup-and-lifecycle.md#dittoconfig):

| Field | Type | Default | Swift specifics |
|---|---|---|---|
| `databaseID` | `String` | `DittoConfig.defaultDatabaseID()` | |
| `connect` | `DittoConfigConnect` | `.smallPeersOnly(privateKey: nil)` | `.server(url: URL)` (a `URL`, not a string) or `.smallPeersOnly(privateKey: String?)` |
| `persistenceDirectory` | `URL?` | `nil` | `nil` uses a directory inside `Ditto.defaultRootDirectory`; `ditto.absolutePersistenceDirectory` returns the directory in use |
| `encryptionKey` (SDK 5.2+) | `DittoEncryptionKey?` | `nil` | `try DittoEncryptionKey.raw(keyBytes)` with exactly 32 bytes |
| `systemParameters` (SDK 5.2+) | `[String: DittoSystemParameterValue]` | `[:]` | Literals work: `["DQL_STRICT_MODE": false]`. An unknown name makes `Ditto.open` throw `DittoError.validationError(reason: .invalidDittoConfig(...))` |
| `experimental` | `DittoConfigExperimental` | | Holds only the deprecated `passphrase` |

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Small-peers-only deployment with encryption at rest. The shared key,
// the encryption key, and the offline license token (issued by Ditto) come from
// secure provisioning such as the Keychain, never from source code.
func openProvisionedSmallPeer(
    readKeyFromKeychain: () async throws -> String,
    readEncryptionKeyFromKeychain: () async throws -> Data, // 32 bytes
    readLicenseFromKeychain: () async throws -> String
) async throws -> Ditto {
    var config = DittoConfig(
        databaseID: "YOUR_DATABASE_ID", // any UUID shared by all peers
        connect: .smallPeersOnly(privateKey: try await readKeyFromKeychain())
    )
    config.encryptionKey = try DittoEncryptionKey.raw(try await readEncryptionKeyFromKeychain())
    let ditto = try await Ditto.open(config: config)
    // Required before sync.start() in small-peers-only mode.
    try ditto.setOfflineOnlyLicenseToken(try await readLicenseFromKeychain())
    try ditto.sync.start() // no expiration handler is needed in this mode
    return ditto
}
```

Pass system parameters on every open (see [Applying System Parameters](../setup-and-lifecycle.md#applying-system-parameters)):

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Pass settings on every open. Ditto applies them before it starts,
// and a misspelled name makes Ditto.open throw.
func openWithSystemParameters(strictMode: Bool) async throws -> Ditto {
    var parameters: [String: DittoSystemParameterValue] = [:]
    if strictMode { parameters["DQL_STRICT_MODE"] = true } // only for apps that opt into strict mode
    let ditto = try await Ditto.open(config: DittoConfig(
        databaseID: "YOUR_DATABASE_ID",
        connect: .server(url: URL(string: "YOUR_SERVER_URL")!),
        systemParameters: parameters
    ))

    // Confirm the effective value. SHOW returns one row keyed by the
    // lowercase parameter name.
    let result = try await ditto.store.execute(query: "SHOW DQL_STRICT_MODE")
    print("dql_strict_mode =", result.items.first?.value["dql_strict_mode"] as Any)
    return ditto
}
```

Pass sync scopes the same way, so that they are in effect before sync starts (see [Sync Scopes](../sync-and-subscriptions.md#sync-scopes)):

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Pass sync scopes in the configuration on every open (SDK 5.2+),
// so that they are in effect before sync starts.
let scopedConfig = DittoConfig(
    databaseID: "YOUR_DATABASE_ID",
    connect: .server(url: URL(string: "YOUR_SERVER_URL")!),
    systemParameters: [
        "USER_COLLECTION_SYNC_SCOPES": [
            "localDrafts": "LocalPeerOnly",
            "kitchenTickets": "SmallPeersOnly",
        ],
    ]
)
```

```swift
import DittoSwift

// ❌ BAD: No privateKey means peers are not authenticated (and the SDK
// documents the mode as unencrypted); no encryptionKey leaves the documents
// readable on disk; a key in source code would be visible to anyone who
// inspects the app binary.
func openUnprotectedSmallPeer() async throws -> Ditto {
    try await Ditto.open(config: DittoConfig(databaseID: "YOUR_DATABASE_ID", connect: .smallPeersOnly()))
}
```

When a store cannot be opened for an encryption reason, `Ditto.open` throws `DittoError.encryptionError(reason:)` with `.keyRequired` (an encrypted store opened without a key), `.keyInvalid` (another key, or a key that is not 32 bytes), `.keyUnexpected`, `.unsupportedScheme`, or `.metadataCorrupt`. The passphrase cases and `DittoConfigExperimental.passphrase` are deprecated. Tell a missing key from a damaged store before you decide what to do:

```swift
import DittoSwift

// ✅ GOOD: Distinguish the encryption errors when the store does not open.
func openEncryptedStore(_ config: DittoConfig) async throws -> Ditto {
    do {
        return try await Ditto.open(config: config)
    } catch DittoError.encryptionError(let reason) {
        switch reason {
        case .keyRequired, .keyInvalid:
            showError("The encryption key for this device's data is missing or wrong.")
        default:
            showError("The encrypted store cannot be opened: \(reason)")
        }
        throw DittoError.encryptionError(reason: reason)
    }
}
```

### One shared instance in Swift

Let concurrent callers await the same open, and forget a failed attempt so that the next caller can retry (see [One instance per persistence directory](../setup-and-lifecycle.md#one-instance-per-persistence-directory)). An actor serializes access to the shared task.

```swift
import DittoSwift

// ✅ GOOD: One shared instance; concurrent callers await the same open.
actor DittoProvider {
    private let config: DittoConfig
    private var opening: Task<Ditto, Error>?

    init(config: DittoConfig) {
        self.config = config
    }

    var instance: Ditto {
        get async throws {
            if let opening { return try await opening.value }
            let config = self.config
            let task = Task { try await Ditto.open(config: config) }
            opening = task
            do {
                return try await task.value
            } catch {
                opening = nil // Forget the failed attempt so that the next caller can retry.
                throw error
            }
        }
    }
}
```

```swift
import DittoSwift

// ❌ BAD: Every call opens the same directory again. While the first instance
// is alive, the second open fails after about a second with
// persistenceDirectoryLocked.
func loadOrdersOpeningEachTime() async throws -> [[String: Any?]] {
    let ditto = try await Ditto.open(config: DittoConfig(databaseID: "YOUR_DATABASE_ID", connect: .smallPeersOnly()))
    let result = try await ditto.store.execute(query: "SELECT * FROM orders")
    return result.items.map { $0.value }
}
```

> **Note (SDK 5.1.0 and 5.2.0):** In our testing, `Ditto.open` and `Ditto.openSync` on a directory that the same process has open threw `DittoError.storeError(reason: .persistenceDirectoryLocked(message:))` after about 1 second, on macOS and in the iOS simulator ("File already locked ... Multiple Ditto instances cannot run at the same time within the same working directory"); see [In Swift, opening an open directory again fails after about a second](../../knowledge/observations/swift-sdk.md#in-swift-opening-an-open-directory-again-fails-after-about-a-second). After the last reference to the first instance was released, the directory opened again within about 70 ms.

**SwiftUI previews and tests**: give previews and each test their own `persistenceDirectory` (for example a new directory in `FileManager.default.temporaryDirectory`), so that they never open the directory of the running app or of another test.

### App startup in Swift

The recommended order (see [Complete app startup](../setup-and-lifecycle.md#complete-app-startup)), as one service that owns the instance and its long-lived subscriptions:

```swift
import DittoSwift
import Foundation

// Most apps keep the default (strict mode off). See "Strict Mode".
let enableStrictMode = false

// fetchAuthToken() and showError(_:) stand for your app's own code.

final class DittoService: Sendable {
    let ditto: Ditto
    private let subscriptions: [DittoSyncSubscription]

    private init(ditto: Ditto, subscriptions: [DittoSyncSubscription]) {
        self.ditto = ditto
        self.subscriptions = subscriptions
    }

    static func start() async throws -> DittoService {
        // 1. Configure logging before open, so that startup is logged with your settings.
        #if DEBUG
        DittoLogger.minimumLogLevel = .debug
        #else
        DittoLogger.minimumLogLevel = .warning
        #endif

        // 2. Open the single shared instance. System parameters are not
        //    persisted, so pass them on every open; Ditto applies them before
        //    it starts (SDK 5.2+).
        var parameters: [String: DittoSystemParameterValue] = [:]
        if enableStrictMode { parameters["DQL_STRICT_MODE"] = true }
        let ditto = try await Ditto.open(config: DittoConfig(
            databaseID: "YOUR_DATABASE_ID",
            // Copy the URL from the Ditto Portal exactly as shown.
            connect: .server(url: URL(string: "YOUR_SERVER_URL")!),
            systemParameters: parameters
        ))
        // If a later step throws, `ditto` goes out of scope here, which shuts the
        // instance down, so a retry can open the directory again.

        // 3. Server connections require an expiration handler before sync.start().
        ditto.auth?.expirationHandler = { ditto, _ in
            await refreshCredentials(ditto) // defined in "Authentication in Swift"
        }

        // 4. Create the indexes your queries need before queries and observers
        //    run. Indexes persist, and IF NOT EXISTS makes this safe on every start.
        try await ditto.store.execute(
            query: "CREATE INDEX IF NOT EXISTS idx_orders_storeId ON orders (storeId)"
        )

        // 5. Register long-lived subscriptions, then start sync.
        let subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId",
                arguments: ["storeId": "store-1"]
            ),
        ]
        try ditto.sync.start()
        return DittoService(ditto: ditto, subscriptions: subscriptions)
    }

    // Call only when the whole app no longer needs Ditto; then release the
    // service (see "Closing Ditto in Swift").
    func stop() {
        for subscription in subscriptions { subscription.cancel() }
        ditto.sync.stop()
    }
}
```

Keep the service in one place that lives as long as the app, for example a property of your `App` struct's state or of your app delegate, and pass it to the features that need it.

Create the indexes your queries rely on once per launch (see [Where indexes live](../indexing-and-performance.md#where-indexes-live)):

```swift
import DittoSwift

// ✅ GOOD: Create the indexes this app relies on, once per launch.
func ensureIndexes(_ ditto: Ditto) async {
    let statements = [
        "CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)",
        "CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)",
    ]
    for statement in statements {
        do {
            try await ditto.store.execute(query: statement)
        } catch {
            // Without the index, queries that use it fall back to a collection
            // scan (and a JOIN on it fails): report and continue.
            showError(error)
        }
    }
}
```

## Authentication in Swift

Set the handler with `ditto.auth?.expirationHandler = { ditto, timeUntilExpiration in ... }`. `ditto.auth` is `nil` in small-peers-only mode. The handler is an `async` closure that cannot throw; `timeUntilExpiration` is a `TimeInterval` in seconds, and Ditto calls the handler with `0` right after sync starts when the device is not authenticated yet. `ditto.auth?.login(token:provider:completion:)` reports its outcome to the completion handler as `(clientInfo: String?, error: DittoError?)`; **it does not throw**. When the server rejects the token or cannot be reached, `error` is `DittoError.authenticationError(reason: .failedToAuthenticate)`. Wrap it in a continuation to await it. `clientInfo` contains the optional `clientInfo` JSON returned by your webhook. The rules are in [Authentication](../setup-and-lifecycle.md#authentication).

```swift
import DittoSwift

// ✅ GOOD: Production login that reports failures. login() calls its completion
// handler; it does not throw.
func login(_ ditto: Ditto, token: String, provider: String) async -> DittoError? {
    await withCheckedContinuation { continuation in
        guard let auth = ditto.auth else {
            continuation.resume(returning: nil) // small-peers-only: nothing to log in to
            return
        }
        auth.login(token: token, provider: provider) { _, error in
            continuation.resume(returning: error)
        }
    }
}

// The expiration handler cannot throw: catch everything inside.
// fetchAuthToken() and showError(_:) stand for your app's own code.
func refreshCredentials(_ ditto: Ditto) async {
    do {
        let token = try await fetchAuthToken() // from your identity provider or backend
        if let error = await login(ditto, token: token, provider: "YOUR_PROVIDER_NAME") {
            showError(error) // the webhook rejected the token, or the server is unreachable
        }
    } catch {
        showError(error) // for example, fetchAuthToken() failed
    }
}

func configureAuthentication(_ ditto: Ditto) {
    ditto.auth?.expirationHandler = { ditto, timeUntilExpiration in
        if timeUntilExpiration > 0 {
            print("Ditto credentials expire in \(timeUntilExpiration) s; refreshing")
        }
        await refreshCredentials(ditto)
    }
}
```

```swift
import DittoSwift

// ✅ GOOD (development only): The development provider and Portal token.
func configureDevelopmentAuthentication(_ ditto: Ditto, developmentToken: String) {
    ditto.auth?.expirationHandler = { ditto, _ in
        await withCheckedContinuation { continuation in
            ditto.auth?.login(token: developmentToken, provider: .development) { _, error in
                if let error { showError(error) }
                continuation.resume()
            }
        }
    }
}
```

```swift
import DittoSwift

// ❌ BAD: The completion handler ignores the error, so a rejected token or an
// unreachable server goes unnoticed, and the app silently stops syncing.
func configureAuthenticationBadly(_ ditto: Ditto) {
    ditto.auth?.expirationHandler = { ditto, _ in
        guard let token = try? await fetchAuthToken() else { return }
        ditto.auth?.login(token: token, provider: "YOUR_PROVIDER_NAME") { _, _ in }
    }
}
```

**Logging out**: `ditto.auth?.logout(cleanup:)` clears the credentials and stops sync. The `cleanup` closure receives the `Ditto` instance and runs before `logout` returns; it is synchronous, so run asynchronous work such as `EVICT` after `logout` returns. `ditto.auth?.status` has `isAuthenticated` and `userID`; `observeStatus(_:)` returns a `DittoObserver` (call `stop()`), and `statusPublisher()` is a Combine publisher.

### Switching users in Swift

The order of the steps is in [Switching users on a shared device](../setup-and-lifecycle.md#switching-users-on-a-shared-device).

```swift
import DittoSwift

// ✅ GOOD: Sign a user out of a shared device. waitUntilServerHas(_:commitID:)
// is defined in "Closing Ditto in Swift"; OrderSync owns the subscriptions (see
// "Subscriptions in Swift").
@MainActor
func signOut(_ ditto: Ditto, orderSync: OrderSync, storeID: String, lastCommitID: UInt64?) async throws -> Bool {
    if let lastCommitID, await !waitUntilServerHas(ditto, commitID: lastCommitID) {
        // Evicting now could discard changes that no other device has yet.
        showError("Some changes have not been uploaded yet. Try again online.")
        return false
    }
    // Screens cancel their own observers when the user leaves them.
    orderSync.leaveStore() // cancel first, or evicted documents sync back
    ditto.auth?.logout() // stops sync; runs a cleanup closure, if you pass one, before it returns
    // The local store stays usable after logout.
    try await ditto.store.execute(query: "EVICT FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID])
    try await ditto.store.execute(query: "EVICT FROM orderItems WHERE storeId = :storeId", arguments: ["storeId": storeID])
    let left = try await ditto.store.execute(
        query: "SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId",
        arguments: ["storeId": storeID]
    )
    return left.items.first?.value["n"] as? Int == 0
}
```

To remove the whole local store of a signed-out user instead, cancel everything, release the last reference to the instance, and call `try Ditto.deleteStore(databaseID:persistenceDirectory:)` (SDK 5.2+); it throws `persistenceDirectoryLocked` while the store is still open (see [Closing Ditto in Swift](#closing-ditto-in-swift)).

## Sync and the App Lifecycle in Swift

`try ditto.sync.start()` throws a `DittoError` if sync cannot start, for example `.authenticationError(reason: .expirationHandlerMissing(...))` ("The operation failed because an authentication expiration handler has not yet been set.") for a server connection without an expiration handler. `ditto.sync.stop()` does not throw, and `ditto.sync.isActive` tells whether sync is running. The rules are in [Starting and Stopping Sync](../setup-and-lifecycle.md#starting-and-stopping-sync).

```swift
import DittoSwift

// ✅ GOOD: Start sync only when it is not already running.
func ensureSyncStarted(_ ditto: Ditto) throws {
    if !ditto.sync.isActive {
        try ditto.sync.start() // throws if prerequisites are missing
    }
}
```

```swift
import DittoSwift

// ❌ BAD: For server connections, sync.start() throws expirationHandlerMissing
// because no expiration handler is set yet, so the handler below is never set.
func startTooEarly(_ ditto: Ditto) throws {
    try ditto.sync.start()
    ditto.auth?.expirationHandler = { ditto, _ in await refreshCredentials(ditto) }
}
```

Do not release the `Ditto` instance when the app moves to the background: that shuts it down, and every later call through `store` or `sync` fails or ends the process (see [Closing Ditto in Swift](#closing-ditto-in-swift)). With the Bluetooth background modes from [Installing the Swift SDK](#installing-the-swift-sdk), iOS lets Ditto keep syncing over Bluetooth in the background. Apps that must not sync in the background pause sync instead:

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: For apps that must not sync in the background: pause sync without
// releasing Ditto, and resume only the sync that this object paused.
@MainActor
final class SyncLifecycle {
    private let ditto: Ditto
    private var pausedByLifecycle = false

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            if ditto.sync.isActive {
                ditto.sync.stop() // the local store stays usable
                pausedByLifecycle = true
            }
        case .active:
            guard pausedByLifecycle else { return }
            pausedByLifecycle = false
            do {
                try ditto.sync.start()
            } catch {
                showError(error) // for example, prerequisites changed in the background
            }
        default:
            break
        }
    }
}

// The scene that drives it.
struct OrdersScene: Scene {
    let lifecycle: SyncLifecycle
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Text("Orders")
        }
        .onChange(of: scenePhase) { phase in
            lifecycle.scenePhaseChanged(to: phase)
        }
    }
}
```

## Closing Ditto in Swift

**DittoSwift 5.2.0 has no `close()` method.** The 5.2.0 release notes announce `Ditto.close()` for Swift, but the SwiftPM package 5.2.0 does not contain it: `ditto.close()` and `Ditto.close(ditto)` do not compile (see [In Swift 5.2.0, Ditto has no close() method](../../knowledge/observations/swift-sdk.md#in-swift-520-ditto-has-no-close-method)). A `Ditto` instance shuts down when its **last strong reference is released**, in its `deinit`:

| Object | How to release | Notes |
|---|---|---|
| `Ditto` | Release the last strong reference (`service = nil`) | Shuts the instance down; `store`, `sync`, and `presence` do not keep it alive |
| `DittoStoreObserver` | `observer.cancel()` | Dropping the object does **not** cancel the observer |
| `DittoSyncSubscription` | `subscription.cancel()` | Dropping the object does **not** cancel the subscription |
| `DittoObserver` from `presence.observe` and `auth.observeStatus` | `observer.stop()` | |
| `DittoDiskUsageObserver` | `observer.stop()` | |
| `DittoAttachmentFetcher` | `fetcher.stop()` | Only needed to cancel a fetch in progress |
| Combine publishers (`graphPublisher()`, `statusPublisher()`, `fetchAttachmentPublisher(attachmentToken:)`) | Cancel the `AnyCancellable` | |
| Connection request handler | `ditto.presence.connectionRequestHandler = nil` | |
| Custom log callback | `DittoLogger.setCustomLogCallback(nil)` | Applies to the whole process and stays installed after an instance shuts down |

`registerObserver` and `registerSubscription` are `@discardableResult`, so code that ignores the returned object compiles without a warning, but **the registration keeps running**: in our testing with SDK 5.1.0 and 5.2.0, an observer and a subscription whose returned objects had been deallocated kept their entries in `ditto.store.observers` and `ditto.sync.subscriptions`, the observer kept being called, and the subscription kept syncing (see [In Swift, dropped observer and subscription objects keep running](../../knowledge/observations/swift-sdk.md#in-swift-dropped-observer-and-subscription-objects-keep-running)). Keep every returned object and cancel it. The elements of `ditto.store.observers` and `ditto.sync.subscriptions` are other objects than the ones that the registration returned (`==` but not `===`), and `cancel()` on them stops the registration.

What happens when the last reference to `Ditto` goes, in our testing with SDK 5.1.0 and 5.2.0 (see [In Swift, releasing the last reference shuts Ditto down at once](../../knowledge/observations/swift-sdk.md#in-swift-releasing-the-last-reference-shuts-ditto-down-at-once)):

- **The instance shuts down at once**, even while the app still holds `store`, `sync`, or `presence`.
- **The release waits for open transactions**: the thread that releases the reference blocks in `deinit` until every open transaction has finished, also beyond `Ditto.deinitTimeoutSeconds` (default `10`). A transaction that took 15 more seconds kept the release waiting for 15 seconds, and then committed, with `Ditto.shouldWaitForCleanupOnClose` at its default (`false`) and at `true`. Release on a background thread, or end transactions first, so that the main thread does not freeze.
- **The release does not wait for other in-flight calls**: on 5.2.0, 192 to 199 of 200 writes that nobody awaited threw `useAfterCloseError` instead of being stored (see [In Swift 5.2.0, writes in flight fail when the instance is released](../../knowledge/observations/swift-sdk.md#in-swift-520-writes-in-flight-fail-when-the-instance-is-released)). Await your writes first.
- **Calls afterwards fail or end the process**: `store.execute` and `store.transaction` throw `DittoError.useAfterCloseError(message:)` on 5.2.0 (on 5.1.0, `store.execute` ends the process), and `registerObserver`, `registerSubscription`, `sync.start()`, and `presence.graph` end the process with a Swift `Fatal error` (see [In Swift, calls after the instance is released throw or end the process](../../knowledge/observations/swift-sdk.md#in-swift-calls-after-the-instance-is-released-throw-or-end-the-process)). Make the object that owns `Ditto` outlive everything that uses it.
- **The directory can be opened again** within about 70 ms after the release.

Before you release Ditto at a point where data must reach another device, wait with a timeout until Ditto Server has confirmed the last write (see [Resource Cleanup and Shutdown](../setup-and-lifecycle.md#resource-cleanup-and-shutdown)). `commitID` is a `UInt64`, and `synced_up_to_local_commit_id` in the result row is an `Int`. Give each read its own deadline: in our testing on a device connected to a peer in another process, a read of `system:data_sync_info` sometimes never completed (4 of 25 runs on SDK 5.2.0, 1 of 10 on 5.1.0), and later reads of it did not complete either (see [In Swift, a read of system:data_sync_info can stop responding](../../knowledge/observations/swift-sdk.md#in-swift-a-read-of-systemdata_sync_info-can-stop-responding)). A stuck read cannot be cancelled, so the helper below stops waiting for it instead:

```swift
import DittoSwift
import Foundation

/// Resumes a continuation once, from whichever task finishes first.
final class FirstFinisher: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Returns the value of operation, or nil if it fails or has not finished after
/// seconds. The operation keeps running in the background if it does not finish.
func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
    let once = FirstFinisher()
    return await withCheckedContinuation { continuation in
        Task {
            let value = try? await operation()
            if once.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            if once.claim() { continuation.resume(returning: nil) }
        }
    }
}

// ✅ GOOD: Wait (with a timeout) until Ditto Server has confirmed a write.
func waitUntilServerHas(_ ditto: Ditto, commitID: UInt64, timeout: TimeInterval = 10) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let result = await withDeadline(deadline.timeIntervalSinceNow) {
            try await ditto.store.execute(query: "SELECT * FROM system:data_sync_info WHERE is_ditto_server = true")
        }
        let confirmed = result?.items.contains { item in
            guard let documents = item.value["documents"] as? [String: Any?],
                  let synced = documents["synced_up_to_local_commit_id"] as? Int else { return false }
            return UInt64(synced) >= commitID
        } ?? false
        if confirmed { return true }
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
    return false // The change stays on the device and syncs later.
}

/// lastCommitID is the commitID of the last write that must be uploaded.
func endShift(_ service: DittoService, lastCommitID: UInt64?) async {
    if let lastCommitID, await !waitUntilServerHas(service.ditto, commitID: lastCommitID) {
        showError("Some changes have not been uploaded yet.")
    }
    service.stop() // cancels subscriptions and stops sync; release the service afterwards
}
```

```swift
import DittoSwift

// ✅ GOOD: Release resources in reverse order of creation, then release the
// last reference to Ditto off the main thread.
// This is app-level shutdown: call shutdown() only when the whole app no longer
// needs Ditto. Screens cancel their own observers and keep Ditto alive.
final class AppShutdown: @unchecked Sendable {
    private var ditto: Ditto?
    private var subscription: DittoSyncSubscription?
    private var observer: DittoStoreObserver?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func start() throws {
        guard let ditto else { return }
        subscription = try ditto.sync.registerSubscription(query: "SELECT * FROM orders")
        observer = try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt DESC") { result in
            print("orders:", result.items.count)
        }
    }

    func shutdown() async {
        observer?.cancel()
        subscription?.cancel()
        observer = nil
        subscription = nil
        ditto?.sync.stop()
        let last = ditto
        ditto = nil
        // Dropping the last reference runs deinit, which waits for open
        // transactions: do it on a background task, not on the main thread.
        await Task.detached { withExtendedLifetime(last) {} }.value
    }
}
```

The last line keeps the instance alive until the detached task runs and lets it go there. Other strong references, such as a task that captured `ditto`, delay the shutdown until they end; the instance shuts down on whichever thread releases the last one.

## Executing DQL in Swift

Pass each statement with its arguments as a `[String: Any?]` dictionary. The four entry points take the same shape:

| Call | Returns |
|---|---|
| `try await ditto.store.execute(query:arguments:)` | `DittoQueryResult` (`@discardableResult`) |
| `try await tx.execute(query:arguments:)` inside `ditto.store.transaction` | `DittoQueryResult` (see [Transactions in Swift](#transactions-in-swift)) |
| `try ditto.store.registerObserver(query:arguments:deliverOn:handler:)` | `DittoStoreObserver` (see [Store Observers in Swift](#store-observers-in-swift)) |
| `try ditto.sync.registerSubscription(query:arguments:)` | `DittoSyncSubscription` (see [Subscriptions in Swift](#subscriptions-in-swift)) |

`execute(query:)` without arguments is a shortcut for an empty dictionary. `registerObserver` and `registerSubscription` also accept any `Codable` value as `arguments` (its encoded keys become the parameters); `execute` accepts only a dictionary. A statement that Ditto rejects makes each of these calls throw `DittoError.storeError(reason:)` at once, with `.queryInvalid(message:)` for a syntax error, an unknown function, or a missing argument, `.queryNotSupported(message:)` for what the call does not accept (an `UPDATE` in an observer, `ORDER BY` or `JOIN` in a subscription), and `.queryArgumentsInvalid` for an argument that cannot be encoded; `error.localizedDescription` is the message (see [In Swift, invalid DQL throws from the registration call](../../knowledge/observations/swift-sdk.md#in-swift-invalid-dql-throws-from-the-registration-call) and [When a Statement Fails or Returns Nothing](../dql.md#when-a-statement-fails-or-returns-nothing)). The rules for parameters are in [Always pass values as parameters](../dql.md#always-pass-values-as-parameters).

```swift
import DittoSwift

// ✅ GOOD: Values travel as typed parameters
func findOrders(_ ditto: Ditto, customerID: String, statuses: [String], pageSize: Int) async throws -> [[String: Any?]] {
    let result = try await ditto.store.execute(
        query: """
        SELECT * FROM orders
        WHERE customerId = :customerId AND status IN :statuses
        ORDER BY createdAt DESC LIMIT :pageSize
        """,
        arguments: ["customerId": customerID, "statuses": statuses, "pageSize": pageSize]
    )
    return result.items.map { $0.value }
}
```

```swift
import DittoSwift

// ❌ BAD: Interpolated values (injection risk, broken quoting, no statement reuse)
func findOrdersUnsafe(_ ditto: Ditto, customerID: String) async throws {
    try await ditto.store.execute(query: "SELECT * FROM orders WHERE customerId = '\(customerID)'")
}
```

Validate values before you write them, then pass them as parameters (see [Input Validation and Query Parameters](../security.md#input-validation-and-query-parameters)):

```swift
import DittoSwift

enum OrderUpdateError: Error { case invalid }

// ✅ GOOD: Validate, then pass values as parameters.
func updateOrderStatus(_ ditto: Ditto, orderID: String, status: String) async throws {
    let allowedStatuses: Set = ["open", "preparing", "done"]
    guard !orderID.isEmpty, allowedStatuses.contains(status) else { throw OrderUpdateError.invalid }
    try await ditto.store.execute(
        query: "UPDATE orders SET status = :status WHERE _id = :id",
        arguments: ["id": orderID, "status": status]
    )
}
```

**A map key in a path**: a path cannot be passed as a parameter, so validate a map key against a strict pattern before you place it inside a backtick-quoted path segment, and pass every value as a parameter (see [Adding, updating, and removing map entries](../data-modeling.md#adding-updating-and-removing-map-entries)).

```swift
import DittoSwift
import Foundation

enum ItemKeyError: Error { case notALowercaseUUID(String) }

/// Removes one line item. A path cannot be passed as a parameter, so the key is
/// validated before it is placed inside a backtick-quoted path segment.
func removeOrderItem(_ ditto: Ditto, orderID: String, itemID: String) async throws {
    // Only a lowercase UUID, such as the IDs from newID() in "IDs and Timestamps in Swift".
    guard UUID(uuidString: itemID) != nil, itemID == itemID.lowercased() else {
        throw ItemKeyError.notALowercaseUUID(itemID)
    }
    try await ditto.store.execute(
        query: "UPDATE orders UNSET items.`\(itemID)` WHERE _id = :id",
        arguments: ["id": orderID]
    )
}
```

**Handling the size error**: a write that would take a document over the hard size limit throws a `DittoError` whose message contains `exceeds limit of ... bytes`; handle it at the call site that may produce it (see [Document Size Limits](../data-modeling.md#document-size-limits)).

```swift
import DittoSwift

// ✅ GOOD: Handle the size error at the call site that may produce it.
func saveNotes(_ ditto: Ditto, visitID: String, notes: String) async -> Bool {
    do {
        try await ditto.store.execute(
            query: "UPDATE visits SET notes = :notes WHERE _id = :id",
            arguments: ["id": visitID, "notes": notes]
        )
        return true
    } catch let error as DittoError {
        // The message contains "exceeds limit of ... bytes" for oversized documents.
        showError(error.localizedDescription) // your app's error UI
        return false
    } catch {
        showError(error)
        return false
    }
}
```

**Batched eviction**: `EVICT ... LIMIT ... RETURNING COUNT(*)` in a loop until the count is 0 (see [Batching evictions](../deletion-and-storage.md#batching-evictions)). First cancel or narrow every subscription that matches these documents.

```swift
import DittoSwift

// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First cancel or narrow every subscription that matches these documents (see EVICT).
func evictInBatches(_ ditto: Ditto, cutoff: String) async throws -> Int {
    var total = 0
    while true {
        let result = try await ditto.store.execute(
            query: "EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 RETURNING COUNT(*) AS evicted",
            arguments: ["cutoff": cutoff]
        )
        let evicted = result.items.first?.value["evicted"] as? Int ?? 0
        total += evicted
        if evicted == 0 { return total }
    }
}
```

**Development helpers for `ADVISE` and `PROFILE`**: `ADVISE` returns one row whose `advice` map holds `suggestedIndexes` (or an `outcome` when there is nothing to suggest), and `PROFILE` appends a row with the key `~request_profile` after the normal results (see [ADVISE (SDK 5.1+)](../indexing-and-performance.md#advise-sdk-51) and [Measuring with PROFILE](../indexing-and-performance.md#measuring-with-profile)). Use these helpers during development only.

```swift
import DittoSwift

// ✅ GOOD (development only): print index suggestions for a query.
func printIndexAdvice(_ ditto: Ditto, query: String, arguments: [String: Any?]) async throws {
    let result = try await ditto.store.execute(query: "ADVISE \(query)", arguments: arguments)
    let advice = result.items.first?.value["advice"] as? [String: Any?] ?? [:]
    let suggested = advice["suggestedIndexes"] as? [Any?] ?? []
    if suggested.isEmpty {
        print("No suggestions:", advice["outcome"] as Any)
    }
    for case let entry as [String: Any?] in suggested {
        print(entry["reason"] as Any, "\n ", entry["statement"] as Any)
    }
}
```

```swift
import DittoSwift

// ✅ GOOD (development only): separate the profile row from the results.
func profileQuery(_ ditto: Ditto, query: String, arguments: [String: Any?]) async throws {
    let result = try await ditto.store.execute(query: "PROFILE \(query)", arguments: arguments)
    let profileItem = result.items.last { $0.value.keys.contains("~request_profile") }
    let profile = profileItem?.value["~request_profile"] as? [String: Any?]
    let resultCount = result.items.count - (profileItem == nil ? 0 : 1)
    print("rows=\(resultCount) times=\(profile?["times"] as Any)")
    if let profileItem {
        print(String(decoding: profileItem.jsonData(), as: UTF8.self)) // includes the plan
    }
}
```

**Execution model**: `execute` is an `async` method of a non-isolated class, so a call from the main actor suspends there, and the query runs off the main thread. A write that must wait for the write lock, however, **occupies one thread of Swift's cooperative thread pool while it waits**. In our testing with SDK 5.1.0 and 5.2.0 on a Mac with 14 cores, 14 or more writes started at once while a read-write transaction was open stopped the transaction and every task of the process; 13 were fine, and without a transaction 200 concurrent writes finished in about 50 to 210 ms (see [In Swift, 14 concurrent writes during an open transaction stop the process](../../knowledge/observations/swift-sdk.md#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process)). A device with fewer cores has a smaller pool. Write in sequence from one task, or put many writes into one transaction, instead of starting one task per write (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution) and [Transactions in Swift](#transactions-in-swift)).

```swift
import DittoSwift

// ❌ BAD: One task per write. Each write that waits for the write lock holds a
// thread of the cooperative pool; with a transaction open, enough of them stop
// every task in the process.
func importOrdersConcurrently(_ ditto: Ditto, orders: [[String: Any?]]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for order in orders {
            group.addTask {
                try await ditto.store.execute(query: "INSERT INTO orders DOCUMENTS (:order)", arguments: ["order": order])
            }
        }
        try await group.waitForAll()
    }
}

// ✅ GOOD: One statement for the whole batch, from one task.
func importOrders(_ ditto: Ditto, orders: [[String: Any?]]) async throws {
    try await ditto.store.execute(
        query: "INSERT INTO orders DOCUMENTS (:orders) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
        arguments: ["orders": orders]
    )
}
```

**One query instead of a loop**: each `execute` call has a fixed cost, so read a list of documents with one `_id IN :ids` query (see [Query Scope and Execution](../indexing-and-performance.md#query-scope-and-execution)).

```swift
import DittoSwift

// ❌ BAD: one query per ID
func loadOrdersOneByOne(_ ditto: Ditto, ids: [String]) async throws -> [[String: Any?]] {
    var orders: [[String: Any?]] = []
    for id in ids {
        let result = try await ditto.store.execute(query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": id])
        orders.append(contentsOf: result.items.map { $0.value })
    }
    return orders
}

// ✅ GOOD: one query, planned as an ID scan
func loadOrders(_ ditto: Ditto, ids: [String]) async throws -> [[String: Any?]] {
    let result = try await ditto.store.execute(query: "SELECT * FROM orders WHERE _id IN :ids", arguments: ["ids": ids])
    return result.items.map { $0.value }
}
```

### Arguments and value types in Swift

Pass Swift values that map to JSON: `String`, `Bool`, the integer types, `Double` and `Float`, `nil`, arrays, and `[String: Any?]` dictionaries, plus a `DittoAttachment` for an `ATTACHMENT` field. Text that contains backslashes is safest in a raw string literal (`#"..."#`) passed as an argument, because a statement written inside a Swift string is unescaped twice, first by Swift and then by DQL (see [Literals](../dql.md#literals)).

```swift
import DittoSwift

// ✅ GOOD: The path is passed as data and stored exactly as given
func saveExportPath(_ ditto: Ditto) async throws {
    try await ditto.store.execute(
        query: "UPDATE settings SET exportPath = :path WHERE _id = :id",
        arguments: ["id": "device", "path": #"C:\temp\exports"#]
    )
}
```

How other Swift values were stored, in our testing with SDK 5.1.0 and 5.2.0 (see [In Swift, a Date argument is stored as an object](../../knowledge/observations/swift-sdk.md#in-swift-a-date-argument-is-stored-as-an-object)):

| Swift value | Stored as | Read back as |
|---|---|---|
| `Int`, `Int64`, `UInt64` up to their limits (no 2^53 limit) | integer | `Int` (`UInt` above `Int.max`) |
| `Float(0.1)` | float | `0.10000000149011612`: convert to `Double` first if the decimal value matters |
| A `Double` that a 32-bit float represents exactly (`12.5`, `0.5`, `1.0`), and such DQL values and `SUM` results | float | **`Float`**, so `as? Double` is `nil`; read numbers with `as? NSNumber` (`doubleValue`) or decode the row with `JSONDecoder` (see [In Swift, item.value returns a Float for values that fit in 32 bits](../../knowledge/observations/swift-sdk.md#in-swift-itemvalue-returns-a-float-for-values-that-fit-in-32-bits)) |
| `nil`, `NSNull()` | `null` (the field exists) | `nil` |
| `Data` | binary | `[UInt8]`, not `Data` |
| `UUID` | string | the **uppercase** `uuidString` |
| `Date` | **object** `{"__type": "date_epoch_timestamp", "__value": 1700000000.123}` | a dictionary, not a time that DQL can compare |
| `Decimal`, `URL` | **object** of their internal fields | a dictionary |
| `Double.nan`, `Double.infinity`, `Character`, `Substring` | the write throws `.queryArgumentsInvalid` | |
| `NSNumber(value: true)` | boolean (5.2.0); **integer `1` on 5.1.0** | `Bool` (5.2.0), `Int` (5.1.0) |

`nil` in a dictionary argument is stored as `null`, so the field is present and no longer matches `IS MISSING` (see [MISSING and NULL](../dql.md#missing-and-null)). To leave a field out, leave its key out. Convert dates to an ISO 8601 string with `utcTimestamp()` (see [IDs and Timestamps in Swift](#ids-and-timestamps-in-swift)), decimals to a string or to integer cents, and URLs to `absoluteString`:

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Only JSON-shaped values, and absent fields left out.
func saveVisit(_ ditto: Ditto, id: String, note: String?, startedAt: Date, fee: Decimal, link: URL) async throws {
    var visit: [String: Any?] = [
        "_id": id,
        "startedAt": utcTimestamp(startedAt), // not the Date itself
        "feeCents": NSDecimalNumber(decimal: fee * 100).intValue, // not the Decimal itself
        "link": link.absoluteString, // not the URL itself
    ]
    if let note { visit["note"] = note } // no key when there is no note, rather than null
    try await ditto.store.execute(query: "INSERT INTO visits DOCUMENTS (:visit)", arguments: ["visit": visit])
}
```

### Query results in Swift

`ditto.store.execute` returns a `DittoQueryResult` (see [Working with Query Results](../dql.md#working-with-query-results)):

| Member | Type | Description |
|---|---|---|
| `items` | `[DittoQueryResultItem]` | The result rows |
| `item.value` | `[String: Any?]` | The row decoded into Swift values. A dictionary, so a copy: changing it changes neither the item nor the store |
| `item.jsonData()` | `Data` | The row as UTF-8 JSON, for `JSONDecoder` |
| `item.cborData()` | `Data` | The row as CBOR |
| `item.isMaterialized`, `materialize()`, `dematerialize()` | | An item decodes its row on the first read of `value` and keeps it; `dematerialize()` releases the decoded row |
| `mutatedDocumentIDs()` | `[DittoDocumentID]` | IDs of documents changed by a write; `id.stringValue` for a string ID, `id.value` for any |
| `commitID` | `UInt64?` | ID of the local commit for a mutating statement; `nil` for reads |

Values inside `item.value` are `Any?`: cast them (`as? String`, `as? Int`, `as? [String: Any?]`, `as? [Any?]`), and read nested objects as `[String: Any?]`. Read floating-point numbers with `as? NSNumber` and `doubleValue`, or decode the row with `JSONDecoder`: a value such as `12.5` comes back as `Float`, so `as? Double` returns `nil` for it, while `0.1` comes back as `Double` (see [In Swift, item.value returns a Float for values that fit in 32 bits](../../knowledge/observations/swift-sdk.md#in-swift-itemvalue-returns-a-float-for-values-that-fit-in-32-bits)). In our testing with SDK 5.1.0 and 5.2.0, results stayed readable after the instance that produced them had shut down (see [In Swift, query result values are copies that outlive the instance](../../knowledge/observations/swift-sdk.md#in-swift-query-result-values-are-copies-that-outlive-the-instance)). Still, copy what you need into your own model values and let the result go; do not keep `DittoQueryResult` or `DittoQueryResultItem` objects in view state or caches.

```swift
import DittoSwift

// Read: convert rows to plain values right away
func openOrders(_ ditto: Ditto) async throws -> [[String: Any?]] {
    let result = try await ditto.store.execute(
        query: "SELECT _id, total, status FROM orders WHERE status = :status ORDER BY _id",
        arguments: ["status": "open"]
    )
    return result.items.map { $0.value }
}

// Write: inspect which documents changed
func closeOrders(_ ditto: Ditto, ids: [String]) async throws -> [String] {
    let result = try await ditto.store.execute(
        query: "UPDATE orders SET status = :status WHERE _id IN :ids",
        arguments: ["status": "closed", "ids": ids]
    )
    print("Committed as", result.commitID as Any) // nil for reads
    return result.mutatedDocumentIDs().map { $0.stringValue }
}

// Alternative encodings, for example to hand rows to a JSON decoder or another process
func openOrdersAsJSON(_ ditto: Ditto) async throws -> [String] {
    let result = try await ditto.store.execute(
        query: "SELECT * FROM orders WHERE status = :status",
        arguments: ["status": "open"]
    )
    return result.items.map { String(decoding: $0.jsonData(), as: UTF8.self) }
}
```

`JSONDecoder` turns `jsonData()` into your own `Decodable` types. Make fields that older documents or concurrent edits can lack optional, so that one row does not fail the whole list:

```swift
import DittoSwift
import Foundation

struct Order: Decodable, Identifiable, Equatable {
    let id: String
    let status: String?
    let total: Double? // an integer total decodes too

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, total
    }
}

// ✅ GOOD: One pass, plain Swift values out; a row that does not decode is
// reported and skipped instead of failing the screen.
func loadOrderModels(_ ditto: Ditto) async throws -> [Order] {
    let result = try await ditto.store.execute(
        query: "SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id",
        arguments: ["status": "open"]
    )
    let decoder = JSONDecoder()
    return result.items.compactMap { item in
        do {
            return try decoder.decode(Order.self, from: item.jsonData())
        } catch {
            showError(error)
            return nil
        }
    }
}
```

**Deriving values at read time**: compute totals and the current status from the stored source data when you read a document, and skip entries whose required fields are missing or `null` (see [Do not store derived values that can diverge](../data-modeling.md#do-not-store-derived-values-that-can-diverge) and [Pattern 1: Audit-log map inside the document](../data-modeling.md#pattern-1-audit-log-map-inside-the-document)).

```swift
// ✅ GOOD: Store the source data; derive totals at read time. Entries with a
// missing or null price or quantity (an entry removed on one device while
// another device edited it) are skipped instead of crashing the screen.
func orderSubtotalCents(_ order: [String: Any?]) -> Int {
    let items = order["items"] as? [String: Any?] ?? [:]
    var subtotal = 0
    for case let entry as [String: Any?] in items.values {
        guard let price = entry["unitPriceCents"] as? Int,
              let quantity = entry["quantity"] as? Int else { continue }
        subtotal += price * quantity
    }
    return subtotal
}
```

```swift
// The workflow states, from earliest to most advanced.
private let statusOrder = ["created", "confirmed", "shipped", "delivered"]

/// Derives the current status as the most advanced state, so a late write from
/// a device that was offline cannot move the order backwards.
func currentStatus(_ order: [String: Any?]) -> String? {
    let log = order["statusLog"] as? [String: Any?] ?? [:]
    var best: String?
    for case let status as String in log.values {
        let rank = statusOrder.firstIndex(of: status) ?? -1
        if best == nil || rank > (statusOrder.firstIndex(of: best!) ?? -1) {
            best = status
        }
    }
    return best
}
```

**Tolerating older documents**: a model type reads a field that newer app versions added as optional, because older documents do not have it (see [Prefer additive changes](../data-modeling.md#prefer-additive-changes)).

```swift
import Foundation

// ✅ GOOD: A new field, read as optional for older documents.
struct Car: Decodable {
    let id: String
    let make: String
    let mileageKm: Int? // added in app version 2; absent in older documents

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case make, mileageKm
    }
}
```

## Subscriptions in Swift

`try ditto.sync.registerSubscription(query:arguments:)` returns a `DittoSyncSubscription`; release it with `subscription.cancel()`, and check `isCancelled`. Registering a query that subscriptions do not accept throws a `DittoError` at once (see [Subscription Rules](../sync-and-subscriptions.md#subscription-rules)). The method is `@discardableResult`, but a subscription whose object you drop keeps syncing (see [Closing Ditto in Swift](#closing-ditto-in-swift)). The rules for when to register and cancel are in [Subscription Lifecycle](../sync-and-subscriptions.md#subscription-lifecycle).

```swift
import DittoSwift

// ✅ GOOD: A session-level service owns long-lived subscriptions.
@MainActor
final class OrderSync {
    private let ditto: Ditto
    private var subscriptions: [DittoSyncSubscription] = []
    private var storeID: String?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    /// Call once after login or when the user enters a store.
    func enterStore(_ storeID: String) throws {
        guard storeID != self.storeID else { return } // Already subscribed; do not re-register.
        leaveStore()
        // Scope by stable partition keys; the UI filters further with local queries.
        subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId",
                arguments: ["storeId": storeID]
            ),
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orderItems WHERE storeId = :storeId",
                arguments: ["storeId": storeID]
            ),
        ]
        self.storeID = storeID
    }

    /// Call on logout or when the user leaves the store.
    func leaveStore() {
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions.removeAll()
        storeID = nil
    }
}
```

```swift
import DittoSwift
import SwiftUI

// ❌ BAD: A new subscription every time SwiftUI evaluates body, never cancelled.
struct OrdersBadge: View {
    let ditto: Ditto
    let storeID: String

    var body: some View {
        // body can run many times per second; each call adds a subscription that
        // keeps replicating until the Ditto instance shuts down.
        _ = try? ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE storeId = :storeId",
            arguments: ["storeId": storeID]
        )
        return Image(systemName: "list.bullet.rectangle")
    }
}
```

When the user changes a filter, replace the screen's observer, not the subscription (see [Filter locally instead of re-registering](../sync-and-subscriptions.md#filter-locally-instead-of-re-registering)). The model below owns the observer; the view tells it when the filter changes and when it disappears:

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: The subscription (owned by OrderSync) stays stable; only the local observer changes.
@MainActor
final class OrdersByStatusModel: ObservableObject {
    @Published private(set) var orders: [[String: Any?]] = []
    private let ditto: Ditto
    private var observer: DittoStoreObserver?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func observe(storeID: String, status: String) {
        observer?.cancel() // Replacing a local observer is cheap.
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id",
                arguments: ["storeId": storeID, "status": status]
            ) { [weak self] result in // delivered on the main queue
                let orders = result.items.map { $0.value }
                MainActor.assumeIsolated { self?.orders = orders }
            }
        } catch {
            showError(error)
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct OrdersByStatusView: View {
    let storeID: String
    let status: String
    @StateObject private var model: OrdersByStatusModel

    init(ditto: Ditto, storeID: String, status: String) {
        self.storeID = storeID
        self.status = status
        _model = StateObject(wrappedValue: OrdersByStatusModel(ditto: ditto))
    }

    var body: some View {
        List(model.orders.indices, id: \.self) { index in
            let order = model.orders[index]
            VStack(alignment: .leading) {
                Text(order["_id"] as? String ?? "")
                Text(order["status"] as? String ?? "").font(.caption)
            }
        }
        .onAppear { model.observe(storeID: storeID, status: status) }
        .onChange(of: status) { newStatus in model.observe(storeID: storeID, status: newStatus) }
        .onChange(of: storeID) { newStoreID in model.observe(storeID: newStoreID, status: status) }
        .onDisappear { model.stop() }
    }
}
```

To switch stores, cancel first, then evict, then subscribe (see [Cancelling subscriptions and local data](../sync-and-subscriptions.md#cancelling-subscriptions-and-local-data)):

```swift
import DittoSwift

// ✅ GOOD: Switching stores: cancel first, then evict data the device no longer needs.
func switchStore(_ ditto: Ditto, current: [DittoSyncSubscription], newStoreID: String) async throws -> [DittoSyncSubscription] {
    // 1. Stop asking for the old store's data.
    for subscription in current {
        subscription.cancel()
    }

    // 2. Remove the old store's documents from this device only.
    try await ditto.store.execute(query: "EVICT FROM orders WHERE storeId != :storeId", arguments: ["storeId": newStoreID])
    try await ditto.store.execute(query: "EVICT FROM orderItems WHERE storeId != :storeId", arguments: ["storeId": newStoreID])

    // 3. Ask for the new store's data.
    return [
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE storeId = :storeId",
            arguments: ["storeId": newStoreID]
        ),
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orderItems WHERE storeId = :storeId",
            arguments: ["storeId": newStoreID]
        ),
    ]
}
```

`ditto.sync.subscriptions` returns the active subscriptions; `queryString`, `queryArguments` (`nil` for a subscription without arguments), and `queryArgumentsJSONData` can be read from them (see [In Swift, a subscription without arguments has nil queryArguments](../../knowledge/observations/swift-sdk.md#in-swift-a-subscription-without-arguments-has-nil-queryarguments)). Two registrations of the same query and arguments are two entries, and each one must be cancelled.

**Upload status**: one lightweight observer of `system:data_sync_info` per screen, which updates the view only when the derived state changes, and the writes whose `commitID` it tracks (see [Monitoring Sync Status](../sync-and-subscriptions.md#monitoring-sync-status)):

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: One lightweight observer that only publishes when the derived state changes.
// Use one per screen (for example, in the toolbar), not one per list row.
@MainActor
final class UploadStatusModel: ObservableObject {
    @Published private(set) var uploaded = false
    private var observer: DittoStoreObserver?

    /// commitID is the commitID returned by the write you want to track.
    func start(_ ditto: Ditto, commitID: UInt64) {
        observer?.cancel()
        // May fire often, so keep the handler trivial.
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM system:data_sync_info WHERE is_ditto_server = true"
        ) { [weak self] result in
            let uploaded = result.items.contains { item in
                guard let documents = item.value["documents"] as? [String: Any?],
                      let synced = documents["synced_up_to_local_commit_id"] as? Int else { return false }
                return UInt64(synced) >= commitID
            }
            MainActor.assumeIsolated {
                if self?.uploaded != uploaded { self?.uploaded = uploaded } // Publish only a real change.
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct UploadStatusIcon: View {
    let ditto: Ditto
    let commitID: UInt64
    @StateObject private var model = UploadStatusModel()

    var body: some View {
        Image(systemName: model.uploaded ? "checkmark.icloud" : "icloud.and.arrow.up")
            .onAppear { model.start(ditto, commitID: commitID) }
            .onDisappear { model.stop() }
    }
}
```

```swift
import DittoSwift

// Obtain the commit ID from the write you want to track.
func submitOrder(_ ditto: Ditto, order: [String: Any?]) async throws -> UInt64? {
    let result = try await ditto.store.execute(query: "INSERT INTO orders DOCUMENTS (:order)", arguments: ["order": order])
    return result.commitID // nil for SELECT; set for local writes.
}
```

```swift
import DittoSwift

// ✅ GOOD: Track the commitID only if the upsert actually changed the document.
func saveSettings(_ ditto: Ditto, settings: [String: Any?]) async throws -> UInt64? {
    let result = try await ditto.store.execute(
        query: "INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
        arguments: ["settings": settings]
    )
    // An unchanged document still gets a commitID, but peers confirm it only
    // with their next sync exchange (up to about 27 seconds later).
    return result.mutatedDocumentIDs().isEmpty ? nil : result.commitID
}
```

**Subscriptions for a JOIN**: a feature-level service creates the index of the join key and subscribes to every collection that the join reads (see [Separate collections with JOIN (SDK 5.1+)](../data-modeling.md#separate-collections-with-join-sdk-51)).

```swift
import DittoSwift

/// Keeps the three collections needed by the order screens in sync.
/// Subscriptions belong to an app- or feature-level service, not to a screen.
@MainActor
final class StoreSync {
    private let ditto: Ditto
    private let storeID: String
    private var subscriptions: [DittoSyncSubscription] = []

    init(ditto: Ditto, storeID: String) {
        self.ditto = ditto
        self.storeID = storeID
    }

    func start() async throws {
        try await ditto.store.execute(query: "CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)")
        subscriptions += [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": storeID]
            ),
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orderItems WHERE storeId = :storeId", arguments: ["storeId": storeID]
            ),
            try ditto.sync.registerSubscription(query: "SELECT * FROM products"),
        ]
    }

    func stop() {
        for subscription in subscriptions { subscription.cancel() }
        subscriptions.removeAll()
    }
}
```

If the key of a joined observer (such as the `orderId`) can change while the view is on screen, replace the observer from `onChange(of:)`, as `OrdersByStatusView` does.

**Retention windows**: a long-lived service that keeps only recent documents moves the boundary of its subscription and evicts the complement in three steps: cancel the subscription, evict with the new cutoff, and subscribe again with the same cutoff, even if the eviction failed (see [Time-based eviction](../deletion-and-storage.md#time-based-eviction)). `utcTimestamp(_:)` is defined in [IDs and Timestamps in Swift](#ids-and-timestamps-in-swift).

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Keep the last 7 days of orders on this device.
@MainActor
final class OrderRetention {
    private let ditto: Ditto
    private let retention: TimeInterval = 7 * 24 * 60 * 60
    private var subscription: DittoSyncSubscription?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    // Same fixed-precision format as createdAt (utcTimestamp(_:) from "IDs and Timestamps in Swift").
    private func cutoff() -> String { utcTimestamp(Date().addingTimeInterval(-retention)) }

    /// Call once at startup (before ditto.sync.start()).
    func start() throws {
        subscription = try subscribe(from: cutoff())
    }

    /// Call on a schedule, for example once a day.
    func evictExpired() async throws -> Int {
        let cutoff = cutoff()

        // 1. Stop asking peers for the documents that are about to be evicted.
        subscription?.cancel()
        // 3. Subscribe again with the moved boundary, even if the eviction failed.
        defer { subscription = try? subscribe(from: cutoff) }

        // 2. Evict exactly the complement of the new subscription.
        let result = try await ditto.store.execute(
            query: "EVICT FROM orders WHERE createdAt < :cutoff",
            arguments: ["cutoff": cutoff]
        )
        return result.mutatedDocumentIDs().count
    }

    private func subscribe(from cutoff: String) throws -> DittoSyncSubscription {
        try ditto.sync.registerSubscription(
            query: "SELECT * FROM orders WHERE createdAt >= :cutoff",
            arguments: ["cutoff": cutoff]
        )
    }

    func stop() { subscription?.cancel() }
}
```

The same steps keep active orders and orders soft-deleted within a retention window, and evict older soft-deleted orders (Variant B in [Soft delete, subscriptions, and cleanup](../deletion-and-storage.md#soft-delete-subscriptions-and-cleanup)):

```swift
import DittoSwift
import Foundation

// ✅ GOOD (Variant B): A long-lived service keeps active orders and orders
// deleted within the retention window, and evicts older deleted orders.
@MainActor
final class OrderSoftDeleteRetention {
    private let ditto: Ditto
    private let storeID: String
    /// Longer than the longest time a device is expected to stay offline.
    private let retention: TimeInterval = 30 * 24 * 60 * 60
    private var subscription: DittoSyncSubscription?

    init(ditto: Ditto, storeID: String) {
        self.ditto = ditto
        self.storeID = storeID
    }

    // Same fixed-precision format as deletedAt (utcTimestamp(_:) from "IDs and Timestamps in Swift").
    private func cutoff() -> String { utcTimestamp(Date().addingTimeInterval(-retention)) }

    /// Call once at startup (before ditto.sync.start()).
    func start() throws {
        subscription = try subscribe(cutoff: cutoff())
    }

    /// Call on a schedule, at most about once a day.
    func evictExpired() async throws {
        let cutoff = cutoff()

        // 1. Stop asking peers for the documents that are about to be evicted.
        subscription?.cancel()
        // 3. Subscribe again with the moved boundary, even if the eviction failed.
        defer { subscription = try? subscribe(cutoff: cutoff) }

        // 2. Evict only documents outside the new subscription.
        try await ditto.store.execute(
            query: "EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff",
            arguments: ["storeId": storeID, "cutoff": cutoff]
        )
    }

    private func subscribe(cutoff: String) throws -> DittoSyncSubscription {
        try ditto.sync.registerSubscription(
            query: """
            SELECT * FROM orders WHERE storeId = :storeId
            AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)
            """,
            arguments: ["storeId": storeID, "cutoff": cutoff]
        )
    }

    func stop() { subscription?.cancel() }
}
```

## Store Observers in Swift

Let a model object own each observer: register it when the screen appears, copy plain values out of each result on the main queue, and cancel it when the screen goes away. The rules that every SDK shares are in [Observing Changes](../observers.md).

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: The recommended observer pattern for SwiftUI.
@MainActor
final class OrdersListModel: ObservableObject {
    @Published private(set) var orders: [[String: Any?]] = []
    private let ditto: Ditto
    private var observer: DittoStoreObserver?

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func start() {
        guard observer == nil else { return }
        do {
            // deliverOn defaults to .main, so the handler runs on the main thread.
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
                arguments: ["status": "open"]
            ) { [weak self] result in
                let orders = result.items.map { $0.value }
                MainActor.assumeIsolated { self?.orders = orders }
            }
        } catch {
            showError(error)
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }

    deinit {
        observer?.cancel() // also when the view never called stop()
    }
}

struct OrdersListView: View {
    @StateObject private var model: OrdersListModel

    init(ditto: Ditto) {
        _model = StateObject(wrappedValue: OrdersListModel(ditto: ditto))
    }

    var body: some View {
        List(model.orders.indices, id: \.self) { index in
            Text(model.orders[index]["_id"] as? String ?? "")
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
```

With `@Observable` (iOS 17 and macOS 14), the model works the same way: keep the observer in a property and cancel it in `stop()` and `deinit`.

**✅ DO:**
- Register observers in a model or service (from `onAppear`, `.task`, or the model's start method), never in `body`.
- Copy plain values out of the result (`item.value`, or your own `Decodable` types) before storing them in published state; do not keep `DittoQueryResult` or `DittoQueryResultItem` objects around (see [Query results in Swift](#query-results-in-swift)).
- Add `ORDER BY` with a tie-breaker whenever the order of results matters (see [Stable ordering](../observers.md#stable-ordering)).
- Keep the returned `DittoStoreObserver` and call `cancel()` when the screen goes away, and in `deinit`.
- Capture the model `weak` in the handler, so that an observer that outlives its model does not keep it alive.

**❌ DON'T:**
- Ignore the returned observer (`_ = try ditto.store.registerObserver(...)`): the observer keeps running and can no longer be cancelled except through `ditto.store.observers` (see the note below).
- Do slow work in a handler on the main queue: the next result waits for the handler, and so does the UI (see [Backpressure in Swift](#backpressure-in-swift)).
- Create an observer per list row; observe the list once and pass values down.

> **Note (SDK 5.1.0 and 5.2.0):** In our testing, an observer whose `DittoStoreObserver` object had been deallocated kept being called, and stayed in `ditto.store.observers`, until it was cancelled through that list (see [In Swift, dropped observer and subscription objects keep running](../../knowledge/observations/swift-sdk.md#in-swift-dropped-observer-and-subscription-objects-keep-running)). The registration methods are `@discardableResult`, so the compiler does not warn about the mistake below.

```swift
import DittoSwift

// ❌ BAD: The returned observer is thrown away. The observer keeps running for
// the lifetime of the Ditto instance, and every call of this function adds one.
func watchOrderCountForever(_ ditto: Ditto, onCount: @escaping @Sendable (Int) -> Void) throws {
    _ = try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt DESC") { result in
        onCount(result.items.count)
    }
}

// ✅ GOOD: The caller keeps the observer and cancels it when done.
func watchOrderCount(_ ditto: Ditto, onCount: @escaping @Sendable (Int) -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt DESC") { result in
        onCount(result.items.count)
    }
}
```

### Observer lifecycle in Swift

| Behavior (`registerObserver`) | Consequence |
|---|---|
| The observer starts at once and delivers the current result first | No separate start call; register when the screen appears |
| The handler runs on the `deliverOn` queue, `.main` by default | Update UI state directly (inside `MainActor.assumeIsolated` for the compiler); pass your own serial queue for work that must not run on the main thread |
| The handler cannot throw (`DittoStoreObservationHandler` is not `throws`) | Catch errors inside the handler; a `throw` does not compile |
| `registerObserver` throws for an invalid or non-`SELECT` statement | Wrap it in `do`/`catch` where it is registered |
| Dropping the `DittoStoreObserver` does not cancel the observer | Always call `observer.cancel()`; `isCancelled` tells whether it was |
| `ditto.store.observers` lists other objects than the registration returned (`==` but not `===`) | Compare with `==`, or use the list to cancel what was lost |

An `AsyncStream` adapts an observer to Swift concurrency. Its `onTermination` cancels the observer, so a SwiftUI `.task` that consumes the stream cancels the observer when the view disappears. `onTermination` runs when the iterating task is cancelled or when the stream is released, not when a loop merely ends with `break` or `return`, so create the stream inside the task that iterates it. In our testing with SDK 5.2.0, cancelling the consuming task cancelled the observer and removed it from `ditto.store.observers` (see [In Swift, an AsyncStream around an observer cancels it when its task ends](../../knowledge/observations/swift-sdk.md#in-swift-an-asyncstream-around-an-observer-cancels-it-when-its-task-ends)):

```swift
import DittoSwift
import Foundation
import SwiftUI

extension DittoStore {
    /// The rows of a query as an async sequence. Cancelling the task that
    /// iterates it, or releasing the stream, cancels the observer.
    func rows(query: String, arguments: [String: Any?] = [:]) -> AsyncStream<[[String: Any?]]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            do {
                let observer = try registerObserver(
                    query: query, arguments: arguments, deliverOn: DispatchQueue(label: "ditto.rows")
                ) { result in
                    continuation.yield(result.items.map { $0.value })
                }
                continuation.onTermination = { _ in observer.cancel() }
            } catch {
                showError(error)
                continuation.finish()
            }
        }
    }
}

// ✅ GOOD: The observer lives exactly as long as the view's task.
struct OpenOrdersStreamView: View {
    let ditto: Ditto
    @State private var orders: [[String: Any?]] = []

    var body: some View {
        List(orders.indices, id: \.self) { index in
            Text(orders[index]["_id"] as? String ?? "")
        }
        .task {
            // SwiftUI cancels this task when the view disappears; the stream
            // then cancels the observer.
            let stream = ditto.store.rows(
                query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id",
                arguments: ["status": "open"]
            )
            for await rows in stream {
                orders = rows
            }
        }
    }
}
```

**Why:** `.task` ties the observer to the view's lifetime without any `onDisappear` code, and `.bufferingNewest(1)` keeps only the latest result while the loop body runs. With other architectures (The Composable Architecture, view models in UIKit), let one object own each observer and cancel it when that object's lifetime ends.

### Backpressure in Swift

`registerObserver(..., handler:)` **waits for the handler to return** before it delivers the next result, and delivers the latest state then: in our testing with SDK 5.1.0 and 5.2.0, a handler that blocked its queue for 500 ms while 10 updates arrived 50 ms apart was called for 3 states (0, 4, and 10), one at a time (see [In Swift, a store observer's handler waits for the previous one](../../knowledge/observations/swift-sdk.md#in-swift-a-store-observers-handler-waits-for-the-previous-one)). A handler that starts a `Task` and returns at once gets every state, and the tasks overlap: 11 calls, up to 10 tasks at the same time. Keep handlers on the main queue short, and give asynchronous work explicit backpressure (see [Backpressure (SDK 5.1+)](../observers.md#backpressure-sdk-51)).

```swift
import DittoSwift

// ❌ BAD: A task per update without backpressure; uploads overlap, and an older
// result can finish last.
func uploadOnEveryChange(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt") { result in
        let orders = result.items.map { $0.value }
        Task { await upload(orders) }
    }
}
```

**`handlerWithSignalNext:`** delivers one result and then waits until you call `signalNext()`. Ditto then delivers the latest state; intermediate states are merged. **If you never call it, the observer stops delivering updates.** Pass a background queue, so that the work does not hold up the main thread:

```swift
import DittoSwift
import Foundation

// ✅ GOOD: handlerWithSignalNext: request the next update when the work is done.
final class OpenOrdersUploader: @unchecked Sendable {
    private let ditto: Ditto
    private let upload: @Sendable ([[String: Any?]]) async throws -> Void
    private var observer: DittoStoreObserver?

    init(ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async throws -> Void) {
        self.ditto = ditto
        self.upload = upload
    }

    func start() throws {
        stop() // Cancel a previous start, if any.
        let upload = self.upload
        observer = try ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt",
            arguments: ["status": "open"],
            deliverOn: DispatchQueue(label: "orders.upload")
        ) { result, signalNext in
            let orders = result.items.map { $0.value }
            Task {
                defer { signalNext() } // Always signal, even after an error; otherwise updates stop.
                do {
                    try await upload(orders)
                } catch {
                    showError(error)
                }
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}
```

The same backpressure in a loop: the `rows(query:arguments:)` stream from [Observer lifecycle in Swift](#observer-lifecycle-in-swift) keeps only the newest result while the loop body runs, so slow work in the body sees one update at a time and then the latest state:

```swift
import DittoSwift

// ✅ GOOD: One update at a time with a for-await loop; the stream buffers only the newest result.
func aggregateReadings(
    _ ditto: Ditto,
    deviceID: String,
    persistAggregates: ([[String: Any?]]) async throws -> Void
) async throws {
    let readings = ditto.store.rows(
        query: "SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100",
        arguments: ["deviceId": deviceID]
    )
    for await rows in readings {
        try await persistAggregates(rows) // the next iteration gets the latest state
    }
    // The loop ends, and the observer is cancelled, when the calling task is cancelled.
}
```

```swift
import DittoSwift

// ❌ BAD: signalNext is skipped when the work throws; the observer silently stops updating.
func fragileObserver(_ ditto: Ditto, upload: @escaping @Sendable ([[String: Any?]]) async throws -> Void) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT * FROM orders ORDER BY createdAt") { result, signalNext in
        let orders = result.items.map { $0.value }
        Task {
            try await upload(orders)
            signalNext() // Never reached if upload throws.
        }
    }
}
```

There is no separate experimental observer API in Swift: `handler:` and `handlerWithSignalNext:` are both forms of `registerObserver`, and both take the dictionary or a `Codable` value as `arguments`.

### Diffing results in Swift

`DittoDiffer().diff(_:)` takes `[DittoQueryResultItem]` and returns a `DittoDiff` with `insertions`, `deletions`, and `updates` (`IndexSet`s) and `moves` (`[(from: Int, to: Int)]`). Keep one `DittoDiffer` per observer: it remembers the previous result. `DittoDiffer` only accepts items produced by Ditto. The semantics that every SDK shares are in [Diffing Results](../observers.md#diffing-results).

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Logging changes between results with DittoDiffer.
// The observer delivers on one serial queue, and only that queue touches the
// state of this object.
final class OrderChangeLog: @unchecked Sendable {
    private let differ = DittoDiffer()
    private var previousIDs: [String] = []
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) throws {
        observer = try ditto.store.registerObserver(
            query: "SELECT * FROM orders ORDER BY createdAt, _id",
            deliverOn: DispatchQueue(label: "orders.diff") // serial: one result at a time
        ) { [weak self] result in
            self?.log(result)
        }
    }

    private func log(_ result: DittoQueryResult) {
        let diff = differ.diff(result.items)
        let currentIDs = result.items.map { $0.value["_id"] as? String ?? "" }
        for index in diff.deletions { print("deleted", previousIDs[index]) } // index into the OLD list
        for index in diff.insertions { print("inserted", currentIDs[index]) } // index into the NEW list
        for index in diff.updates { print("updated", currentIDs[index]) } // index into the NEW list
        for move in diff.moves { print("moved", move.from, "->", move.to) }
        previousIDs = currentIDs
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}
```

SwiftUI's `List` and `ForEach` with stable identifiers (`_id`) compute their own differences, so they do not need `DittoDiffer`. `DittoDiffer` is useful where you apply changes yourself, as in a `UITableView`:

```swift
import DittoSwift
import Foundation
import UIKit

// ✅ GOOD: Driving UITableView batch updates from DittoDiff (iOS).
final class OrdersTableController: UITableViewController {
    private let ditto: Ditto
    private let differ = DittoDiffer()
    private var observer: DittoStoreObserver?
    private var orders: [[String: Any?]] = []

    init(ditto: Ditto) {
        self.ditto = ditto
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "order")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observer = try? ditto.store.registerObserver(
            query: "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200",
            arguments: ["status": "open"]
        ) { [weak self] result in
            MainActor.assumeIsolated { self?.apply(result) }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        observer?.cancel()
        observer = nil
    }

    private func apply(_ result: DittoQueryResult) {
        let diff = differ.diff(result.items)
        let next = result.items.map { $0.value }
        tableView.performBatchUpdates {
            orders = next
            // A move is a deletion at its old index plus an insertion at its new one.
            let deleted = diff.deletions.map { IndexPath(row: $0, section: 0) }
                + diff.moves.map { IndexPath(row: $0.from, section: 0) }
            let inserted = diff.insertions.map { IndexPath(row: $0, section: 0) }
                + diff.moves.map { IndexPath(row: $0.to, section: 0) }
            tableView.deleteRows(at: deleted, with: .automatic)
            tableView.insertRows(at: inserted, with: .automatic)
        }
        // Updated rows show their new values after the batch.
        let updated = diff.updates.map { IndexPath(row: $0, section: 0) }
        if !updated.isEmpty { tableView.reloadRows(at: updated, with: .none) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { orders.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "order", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = orders[indexPath.row]["_id"] as? String
        cell.contentConfiguration = content
        return cell
    }
}
```

**Why:** `UITableView` applies the deletions against the old rows and the insertions against the new ones in one batch, which matches the index spaces of `DittoDiff`. Updates are reloaded after the batch, because their indexes refer to the new list.

### Partial UI updates in Swift

Give each region its own model with its own observer, and publish a value only when it changed: assigning an equal value to a `@Published` property still makes every observing view re-evaluate its body. Map rows to `Equatable` model types, so that SwiftUI and your own checks can compare them. The rules that every SDK shares are in [Partial UI Updates](../observers.md#partial-ui-updates).

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: The count badge and the list each observe what they need.
@MainActor
final class OpenOrdersCountModel: ObservableObject {
    @Published private(set) var count = 0
    private var observer: DittoStoreObserver?

    func start(_ ditto: Ditto) {
        guard observer == nil else { return }
        observer = try? ditto.store.registerObserver(
            query: "SELECT COUNT(*) AS n FROM orders WHERE status = :status",
            arguments: ["status": "open"]
        ) { [weak self] result in
            let n = result.items.first?.value["n"] as? Int ?? 0
            MainActor.assumeIsolated {
                if self?.count != n { self?.count = n } // Publish only a real change.
            }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }
}

struct OpenOrdersCount: View {
    let ditto: Ditto
    @StateObject private var model = OpenOrdersCountModel()

    var body: some View {
        Text("Open orders: \(model.count)")
            .onAppear { model.start(ditto) }
            .onDisappear { model.stop() }
    }
}

struct OrdersScreen: View {
    let ditto: Ditto
    let storeID: String

    var body: some View {
        // The screen itself observes nothing; each region updates independently.
        VStack {
            OpenOrdersCount(ditto: ditto)
            OrdersByStatusView(ditto: ditto, storeID: storeID, status: "open") // from "Subscriptions in Swift"
        }
    }
}
```

Use the SwiftUI template of Instruments, or `Self._printChanges()` inside `body` during development, to confirm which views update before you optimize further.

## Transactions in Swift

Run statements through `tx.execute(query:arguments:)`, never through `ditto.store.execute`: a write through `ditto.store.execute` inside a read-write transaction never returns, and blocks every later write, and a read-write transaction started inside another one never returns either. `tx.store` is `ditto.store` itself, so `tx.store.execute` is the same mistake. In our testing with SDK 5.1.0 and 5.2.0, reads through `ditto.store.execute` and read-only transactions inside a transaction did return, and saw only committed data (see [In Swift, store.execute writes and nested read-write transactions inside a transaction do not return](../../knowledge/observations/swift-sdk.md#in-swift-storeexecute-writes-and-nested-read-write-transactions-inside-a-transaction-do-not-return)). The rules are in [Transaction Rules](../transactions.md#transaction-rules).

`DittoStore.transaction` has two forms:

| Form | Scope returns | `transaction` returns |
|---|---|---|
| `transaction(hint:isReadOnly:with:) -> DittoTransactionCompletionAction` | `.commit` or `.rollback` | The action |
| `transaction<T: Sendable>(hint:isReadOnly:with:) -> T` | Any `Sendable` value | That value; the transaction commits |

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `hint` | `String?` | `nil` | A label written to the logs |
| `isReadOnly` | `Bool` | `false` | Read-only transactions reject mutating statements with `.transactionReadOnly` and can run concurrently |
| `with` (trailing closure) | `@Sendable (DittoTransaction) async throws -> ...` | required | The work to do. Use only the `DittoTransaction` passed in |

How a transaction ends:

| Scope outcome | Result |
|---|---|
| Returns `.commit` | Committed; `transaction` returns `.commit` |
| Returns `.rollback` | Rolled back; no changes are applied; `transaction` returns `.rollback` |
| Returns a value (generic form) | Committed; `transaction` returns that value |
| Returns nothing | **Does not compile**: the compiler picks the `DittoTransactionCompletionAction` form and reports "missing return". Return `.commit` |
| Throws | Rolled back; the error is rethrown to the caller of `transaction` |
| A statement fails, but the scope catches the error | The transaction **continues**; the remaining changes are committed unless you roll back (see [In Swift, a statement error caught inside a transaction does not roll it back](../../knowledge/observations/swift-sdk.md#in-swift-a-statement-error-caught-inside-a-transaction-does-not-roll-it-back)) |

```swift
import DittoSwift

struct OrderNotFound: Error { let id: String }

// ✅ GOOD: Close an order and create its invoice atomically.
func closeOrderWithInvoice(_ ditto: Ditto, orderID: String, invoiceID: String) async throws {
    try await ditto.store.transaction(hint: "closeOrderWithInvoice") { tx in // the hint appears in logs
        let result = try await tx.execute(query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": orderID])
        guard let order = result.items.first?.value else {
            throw OrderNotFound(id: orderID) // Throwing rolls back.
        }
        let invoice: [String: Any?] = [
            "_id": invoiceID,
            "orderId": orderID,
            "total": order["total"] ?? nil, // Any?? flattened to Any?
            "createdAt": utcTimestamp(), // Defined in the Timestamps section.
        ]
        try await tx.execute(query: "INSERT INTO invoices DOCUMENTS (:invoice)", arguments: ["invoice": invoice])
        try await tx.execute(
            query: "UPDATE orders SET status = :status, invoiceId = :invoiceId WHERE _id = :id",
            arguments: ["id": orderID, "status": "closed", "invoiceId": invoiceID]
        )
        return .commit
    }
}
```

```swift
import DittoSwift

// ✅ GOOD: Explicit rollback without throwing.
func shipOrder(_ ditto: Ditto, orderID: String) async throws -> Bool {
    let action = try await ditto.store.transaction(hint: "shipOrder") { tx in
        let result = try await tx.execute(
            query: "SELECT * FROM orders WHERE _id = :id AND status = :status",
            arguments: ["id": orderID, "status": "paid"]
        )
        if result.items.isEmpty {
            return .rollback // Nothing to ship.
        }
        try await tx.execute(
            query: "UPDATE orders SET status = :status WHERE _id = :id",
            arguments: ["id": orderID, "status": "shipped"]
        )
        return .commit
    }
    return action == .commit
}

// ✅ GOOD: A read-only transaction for a consistent multi-query snapshot, with a typed return value.
func orderCounts(_ ditto: Ditto) async throws -> (open: Int, closed: Int) {
    try await ditto.store.transaction(hint: "orderCounts", isReadOnly: true) { tx in
        let open = try await tx.execute(
            query: "SELECT COUNT(*) AS n FROM orders WHERE status = :status", arguments: ["status": "open"]
        )
        let closed = try await tx.execute(
            query: "SELECT COUNT(*) AS n FROM orders WHERE status = :status", arguments: ["status": "closed"]
        )
        return (open.items.first?.value["n"] as? Int ?? 0, closed.items.first?.value["n"] as? Int ?? 0)
    }
}
```

Use the `DittoTransaction` only inside its scope, and `await` every `tx.execute` in it.

```swift
import DittoSwift

// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
func badCheckout(_ ditto: Ditto, orderID: String, chargeCard: @escaping @Sendable () async throws -> Void) async throws {
    try await ditto.store.transaction { tx in
        try await tx.execute(
            query: "UPDATE orders SET status = :status WHERE _id = :id",
            arguments: ["id": orderID, "status": "checkout"]
        )
        // Network call inside the transaction: every other write, and every
        // change from other devices, waits until the transaction ends.
        try await chargeCard()
        // Never returns: a write outside the transaction waits for it to end.
        try await ditto.store.execute(
            query: "UPDATE orders SET status = :status WHERE _id = :id",
            arguments: ["id": orderID, "status": "paid"]
        )
        // Never returns: the inner read-write transaction waits for the outer one.
        try await ditto.store.transaction { inner in
            try await inner.execute(
                query: "UPDATE orders SET paidAt = :paidAt WHERE _id = :id",
                arguments: ["id": orderID, "paidAt": utcTimestamp()]
            )
            return .commit
        }
        return .commit
    }
}

// ✅ GOOD: Do the I/O first, then record the outcome in one short transaction.
func checkout(_ ditto: Ditto, orderID: String, chargeCard: () async throws -> Void) async throws {
    try await chargeCard() // Outside the transaction.
    try await ditto.store.transaction(hint: "recordPayment") { tx in
        try await tx.execute(
            query: "UPDATE orders SET status = :status, paidAt = :paidAt WHERE _id = :id",
            arguments: ["id": orderID, "status": "paid", "paidAt": utcTimestamp()] // fixed-precision helper (see Timestamps)
        )
        try await tx.execute(
            query: "INSERT INTO payments DOCUMENTS (:payment)",
            arguments: ["payment": ["_id": "payment-\(orderID)", "orderId": orderID]]
        )
        return .commit
    }
}
```

**Concurrent writes while a transaction is open**: each `store.execute` write that waits for the transaction holds a thread of Swift's cooperative pool. Once every thread of the pool waits, the transaction cannot resume after its next `await`, and every task of the process stops; in our testing on a 14-core Mac, 14 waiting writes were enough, on 5.1.0 and 5.2.0 (see [In Swift, 14 concurrent writes during an open transaction stop the process](../../knowledge/observations/swift-sdk.md#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process)). Phones have fewer cores. Do not start a task per write; write in sequence, or put the writes in the transaction:

```swift
import DittoSwift

// ❌ BAD: A transaction, and one detached task per incoming scan. If enough
// scans arrive while the transaction runs, the transaction and the app stop.
func recordScansConcurrently(_ ditto: Ditto, scans: [[String: Any?]]) {
    Task.detached {
        try await ditto.store.transaction(hint: "recount") { tx in
            try await tx.execute(query: "UPDATE stock SET counted = true WHERE _id = :id", arguments: ["id": "aisle-1"])
            return .commit
        }
    }
    for scan in scans {
        Task.detached {
            try await ditto.store.execute(query: "INSERT INTO scans DOCUMENTS (:scan)", arguments: ["scan": scan])
        }
    }
}

// ✅ GOOD: One writer task works through the scans in order.
actor ScanWriter {
    private let ditto: Ditto

    init(ditto: Ditto) {
        self.ditto = ditto
    }

    func record(_ scans: [[String: Any?]]) async throws {
        for scan in scans {
            try await ditto.store.execute(query: "INSERT INTO scans DOCUMENTS (:scan)", arguments: ["scan": scan])
        }
    }
}
```

**Shutting down with open transactions**: releasing the last reference to `Ditto` waits in `deinit` for open transactions (see [Closing Ditto in Swift](#closing-ditto-in-swift)), so a transaction cannot be cut off by the shutdown; release the reference off the main thread so that the wait does not freeze the UI.

**Read, change, and write in one transaction**: replacing an array, or copying a document to a new `_id`, reads a value and writes a new one. Doing both in one transaction keeps two local calls from interleaving; a concurrent edit on another device can still win the merge (see [Working with arrays](../data-modeling.md#working-with-arrays) and [IDs are immutable](../data-modeling.md#ids-are-immutable)).

```swift
import DittoSwift

// The array is a register: this write replaces it as a whole. Reading and
// writing in one transaction keeps two local calls from interleaving and
// dropping a tag; a concurrent edit on another device can still win the merge.
func addTag(_ ditto: Ditto, productID: String, tag: String) async throws {
    try await ditto.store.transaction(hint: "addTag") { tx in
        let result = try await tx.execute(query: "SELECT tags FROM products WHERE _id = :id", arguments: ["id": productID])
        guard let product = result.items.first?.value else { return .commit }
        let current = product["tags"] as? [Any?] ?? []
        try await tx.execute(
            query: "UPDATE products SET tags = :tags WHERE _id = :id",
            arguments: ["id": productID, "tags": current + [tag]]
        )
        return .commit
    }
}
```

```swift
import DittoSwift

/// Copies an order to a new ID and deletes the original, atomically.
/// Both statements declare the order's COUNTER, ATTACHMENT, and REGISTER
/// fields exactly as the other statements on orders do, so the copy keeps
/// their CRDT types. Undeclared objects such as shippingAddress are MAPs.
func moveOrder(_ ditto: Ditto, oldID: String, newID: String) async throws {
    try await ditto.store.transaction(hint: "moveOrder") { tx in
        let result = try await tx.execute(
            query: """
            SELECT * FROM COLLECTION orders
              (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
            WHERE _id = :id
            """,
            arguments: ["id": oldID]
        )
        guard var copy = result.items.first?.value else { return .commit }
        copy["_id"] = newID
        try await tx.execute(
            query: """
            INSERT INTO COLLECTION orders
              (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
            DOCUMENTS (:doc)
            """,
            arguments: ["doc": copy]
        )
        try await tx.execute(query: "DELETE FROM orders WHERE _id = :id", arguments: ["id": oldID])
        return .commit
    }
}
```

## Attachments in Swift

Create attachments with `try await ditto.store.newAttachment(path:metadata:)` or `newAttachment(data:metadata:)`. The rules are in [Attachments](../attachments.md).

| `newAttachment` detail | Behavior |
|---|---|
| Source | `path:` an absolute file path (`String`, for example `url.path`), or `data:` the bytes (`Data`) |
| File paths | The file is copied into Ditto's store; the original can be deleted once `newAttachment` has returned |
| Metadata | `[String: String]`; values must be strings |
| Result | A `DittoAttachment` with `id`, `len` (`UInt64`), `metadata`, `data() throws -> Data`, and `copy(toPath:) throws` |

Pass the `DittoAttachment` itself as the field value, in a statement that declares the field as `ATTACHMENT`. Reading the field back returns its token, a `[String: Any?]` with `id`, `len`, and `metadata`.

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Create an attachment from a file and insert it with a declared ATTACHMENT field.
func savePhoto(_ ditto: Ditto, photoID: String, fileURL: URL) async throws {
    // The file is copied into Ditto's blob store; the original can be deleted afterwards.
    let attachment = try await ditto.store.newAttachment(
        path: fileURL.path,
        metadata: ["name": "receipt.jpg", "mimeType": "image/jpeg"] // String values only.
    )
    try await ditto.store.execute(
        query: "INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)",
        arguments: ["photo": [
            "_id": photoID,
            "image": attachment,
            "createdAt": utcTimestamp(), // Defined in the Timestamps section.
        ]]
    )
}

// ✅ GOOD: Create an attachment from bytes, for example from the camera or a downscaled image.
func attachmentFromBytes(_ ditto: Ditto, bytes: Data, name: String) async throws -> DittoAttachment {
    try await ditto.store.newAttachment(data: bytes, metadata: ["name": name])
}
```

`ditto.store.fetchAttachment(token:deliverOn:onFetchEvent:)` returns a `DittoAttachmentFetcher` at once and reports `DittoAttachmentFetchEvent` values on the `deliverOn` queue (`.main` by default): `.progress(downloadedBytes:totalBytes:)`, `.completed(DittoAttachment)` (read the bytes with `try attachment.data()`), and `.deleted`. Call `fetcher.stop()` to cancel a fetch in progress; a completed fetcher stops by itself, and `ditto.store.attachmentFetchers` lists the active ones. `fetchAttachmentPublisher(attachmentToken:)` offers the same events as a Combine publisher.

```swift
import DittoSwift
import Foundation
import SwiftUI

// ✅ GOOD: Lazy, cancellable attachment loading with a stall timeout.
@MainActor
final class AttachmentImageModel: ObservableObject {
    @Published private(set) var data: Data?
    @Published private(set) var progress: Double?
    @Published private(set) var failed = false
    private let ditto: Ditto
    private let stallTimeout: TimeInterval
    private var fetcher: DittoAttachmentFetcher?
    private var stallTimer: Task<Void, Never>?
    private var generation = 0 // Identifies the current fetch.

    init(ditto: Ditto, stallTimeout: TimeInterval = 30) {
        self.ditto = ditto
        self.stallTimeout = stallTimeout
    }

    /// Call when the view appears or shows another token (lazy loading).
    func load(_ token: [String: Any?]) {
        stop()
        data = nil
        failed = false
        progress = nil
        generation += 1
        let current = generation
        restartStallTimer()
        do {
            fetcher = try ditto.store.fetchAttachment(token: token.compactMapValues { $0 }) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event, generation: current) }
            }
        } catch {
            failed = true
        }
    }

    private func handle(_ event: DittoAttachmentFetchEvent, generation: Int) {
        guard generation == self.generation else { return } // an event of a replaced fetch
        switch event {
        case .progress(let downloaded, let total):
            restartStallTimer() // Progress resets the stall timer.
            if total > 0 { progress = Double(downloaded) / Double(total) }
        case .completed(let attachment):
            stallTimer?.cancel()
            do {
                data = try attachment.data()
            } catch {
                failed = true
            }
        case .deleted:
            stallTimer?.cancel()
            failed = true
        @unknown default:
            break
        }
    }

    private func restartStallTimer() {
        stallTimer?.cancel()
        let timeout = stallTimeout
        // Ditto has no fetch timeout: no event simply means no peer is delivering the blob.
        stallTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.fetcher?.stop()
            self?.failed = true
        }
    }

    /// Call when the view goes away; cancels the download if it is still running.
    func stop() {
        stallTimer?.cancel()
        fetcher?.stop()
        fetcher = nil
    }
}

struct AttachmentImage: View {
    let token: [String: Any?]
    @StateObject private var model: AttachmentImageModel

    init(ditto: Ditto, token: [String: Any?], stallTimeout: TimeInterval = 30) {
        self.token = token
        _model = StateObject(wrappedValue: AttachmentImageModel(ditto: ditto, stallTimeout: stallTimeout))
    }

    var body: some View {
        content
            .onAppear { model.load(token) }
            // SwiftUI can reuse this view for another token (list updates, replaced photos).
            .onChange(of: token["id"] as? String) { _ in model.load(token) }
            .onDisappear { model.stop() }
    }

    @ViewBuilder private var content: some View {
        if let image = model.data.flatMap(platformImage) {
            image.resizable().scaledToFill()
        } else if model.failed {
            Button("Retry") { model.load(token) }
        } else {
            ProgressView(value: model.progress)
        }
    }

    private func platformImage(_ data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}
```

```swift
// Reading the token from a document.
func imageToken(_ photo: [String: Any?]) -> [String: Any?]? {
    photo["image"] as? [String: Any?]
}
```

To replace or remove an attachment (see [Attachments Are Immutable](../attachments.md#attachments-are-immutable)):

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Replace an attachment by creating a new one and updating the token field.
func replacePhoto(_ ditto: Ditto, photoID: String, newFileURL: URL) async throws {
    let attachment = try await ditto.store.newAttachment(
        path: newFileURL.path,
        metadata: ["name": "receipt-v2.jpg", "mimeType": "image/jpeg"]
    )
    try await ditto.store.execute(
        query: "UPDATE COLLECTION photos (image ATTACHMENT) SET image = :image WHERE _id = :id",
        arguments: ["id": photoID, "image": attachment]
    )
}

// ✅ GOOD: Remove the reference; the blob becomes eligible for garbage collection.
func removePhoto(_ ditto: Ditto, photoID: String) async throws {
    try await ditto.store.execute(
        query: "UPDATE COLLECTION photos (image ATTACHMENT) UNSET image WHERE _id = :id",
        arguments: ["id": photoID]
    )
}
```

Thumbnails and full-size images (see [Thumbnail Pattern](../attachments.md#thumbnail-pattern)):

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Insert a thumbnail attachment and a full-size attachment together.
func savePhotoWithThumbnail(_ ditto: Ditto, photoID: String, thumbnailBytes: Data, fullSizeURL: URL) async throws {
    let thumbnail = try await ditto.store.newAttachment(
        data: thumbnailBytes, // Downscaled by your app beforehand.
        metadata: ["kind": "thumbnail", "mimeType": "image/jpeg"]
    )
    let fullSize = try await ditto.store.newAttachment(
        path: fullSizeURL.path,
        metadata: ["kind": "full", "mimeType": "image/jpeg"]
    )
    try await ditto.store.execute(
        query: "INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, image ATTACHMENT) DOCUMENTS (:photo)",
        arguments: ["photo": [
            "_id": photoID,
            "thumbnail": thumbnail,
            "image": fullSize,
            "createdAt": utcTimestamp(), // Defined in the Timestamps section.
        ]]
    )
}
```

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: Rows fetch only thumbnails; the full-size image is fetched when opened.
struct PhotoRow: View {
    let ditto: Ditto
    let photo: [String: Any?]
    @State private var showsFullSize = false

    var body: some View {
        HStack {
            Group {
                if let thumbnail = photo["thumbnail"] as? [String: Any?] {
                    AttachmentImage(ditto: ditto, token: thumbnail, stallTimeout: 30)
                } else {
                    Image(systemName: "photo")
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            Text(photo["_id"] as? String ?? "")
        }
        .onTapGesture { showsFullSize = true }
        .sheet(isPresented: $showsFullSize) {
            if let fullSize = photo["image"] as? [String: Any?] {
                // Larger files need a longer stall timeout.
                AttachmentImage(ditto: ditto, token: fullSize, stallTimeout: 120)
            }
        }
    }
}
```

## IDs and Timestamps in Swift

**IDs**: generate a random (version 4) UUID for every new document with `UUID()`; never derive IDs from a counter or the clock. `UUID().uuidString` is uppercase, and a `UUID` passed as an argument is stored as that uppercase string (see [Arguments and value types in Swift](#arguments-and-value-types-in-swift)), while most other platforms produce lowercase UUIDs; lowercase it once, in one helper, so that IDs from every platform look the same. Keep human-readable numbers in a separate field. The rules are in [Document IDs](../data-modeling.md#document-ids).

```swift
import DittoSwift
import Foundation

/// Returns a random (version 4) UUID such as "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f".
func newID() -> String {
    UUID().uuidString.lowercased()
}

func createOrder(_ ditto: Ditto, storeID: String) async throws -> String {
    let orderID = newID()
    try await ditto.store.execute(
        query: "INSERT INTO orders DOCUMENTS (:order)",
        arguments: ["order": [
            "_id": orderID,
            "storeId": storeID,
            "status": "open",
            "createdAt": utcTimestamp(), // defined below
        ]]
    )
    return orderID
}
```

```swift
import Foundation

// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
func badSequentialID(dailyCount: Int) -> String { "order-\(dailyCount)" }

// ❌ BAD: Collides when two devices write within the same millisecond.
func badTimestampID() -> String { "order-\(Int(Date().timeIntervalSince1970 * 1000))" }
```

```swift
import DittoSwift
import Foundation

/// A display label, not an identifier: uniqueness is not guaranteed across
/// devices, so never use it as _id or as a lookup key.
func displayNumber(terminalCode: String, localSequence: Int) -> String {
    let digits = String(localSequence)
    return "\(terminalCode)-\(String(repeating: "0", count: max(0, 4 - digits.count)))\(digits)"
}

func createOrderWithLabel(_ ditto: Ditto, orderID: String, terminalCode: String, localSequence: Int) async throws {
    try await ditto.store.execute(
        query: "INSERT INTO orders DOCUMENTS (:order)",
        arguments: ["order": [
            "_id": orderID, // UUID
            "displayNumber": displayNumber(terminalCode: terminalCode, localSequence: localSequence),
            "createdAt": utcTimestamp(),
        ]]
    )
}
```

**Timestamps**: store UTC with a zone designator, and produce every timestamp that is sorted or compared with one fixed-precision helper (see [Timestamps](../data-modeling.md#timestamps)). Two details of Swift make this necessary:

- A `Date` passed as an argument is not stored as a time but as an object (`{"__type": "date_epoch_timestamp", "__value": ...}`), which DQL date functions and string comparisons cannot use (see [In Swift, a Date argument is stored as an object](../../knowledge/observations/swift-sdk.md#in-swift-a-date-argument-is-stored-as-an-object)).
- `"\(Date())"` produces `2023-11-14 22:13:20 +0000`: a space instead of `T`, no fractional seconds, and a numeric offset instead of `Z`.

`Date.ISO8601FormatStyle(includingFractionalSeconds: true)` (iOS 15 and macOS 12) formats in UTC with exactly three fractional digits, also for whole seconds (`2023-11-14T22:13:20.000Z`), so its strings sort chronologically as text. Epoch milliseconds (`Int(date.timeIntervalSince1970 * 1000)`) are the compact alternative.

```swift
import DittoSwift
import Foundation

/// Returns the time as an ISO 8601 UTC string with exactly millisecond
/// precision, e.g. "2026-10-08T10:30:00.123Z".
func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

// ✅ GOOD: Consistent UTC timestamps from the one helper.
func markReady(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.execute(
        query: "UPDATE orders SET readyAt = :readyAt WHERE _id = :id",
        arguments: ["id": orderID, "readyAt": utcTimestamp()]
    )
}
```

```swift
import DittoSwift
import Foundation

// ❌ BAD: A Date is stored as an object, not a time, and "\(Date())" is not
// ISO 8601. Neither value works with DQL date functions or in comparisons.
func markReadyBadly(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.execute(
        query: "UPDATE orders SET readyAt = :readyAt, readyLabel = :label WHERE _id = :id",
        arguments: ["id": orderID, "readyAt": Date(), "label": "\(Date())"]
    )
}
```

## Transports and Presence in Swift

`DittoTransportConfig` is a value type. Change it with `ditto.updateTransportConfig { config in ... }`, which starts from the current configuration; never assign a new `DittoTransportConfig()`, which has every transport disabled (a newly opened instance has Bluetooth LE, LAN, and AWDL enabled). The rules are in [Transport Configuration](../setup-and-lifecycle.md#transport-configuration).

```swift
import DittoSwift

// ✅ GOOD: Adjust the current configuration.
func configureTransports(_ ditto: Ditto) {
    ditto.updateTransportConfig { config in
        config.setAllPeerToPeer(enabled: true) // Bluetooth LE, LAN, AWDL
        config.peerToPeer.bluetoothLE.isEnabled = false // for example, LAN and AWDL only
    }
}
```

```swift
import DittoSwift

// ✅ GOOD: A hub device listens on TCP; other devices connect to it.
func configureHub(_ ditto: Ditto) {
    ditto.updateTransportConfig { config in
        config.listen.tcp.isEnabled = true
        config.listen.tcp.interfaceIP = "[::]"
        config.listen.tcp.port = 4040
    }
}

func connectToHub(_ ditto: Ditto) {
    ditto.updateTransportConfig { config in
        config.connect.tcpServers = ["192.168.1.10:4040"]
        // Additional WebSocket endpoints, if you run your own:
        // config.connect.webSocketURLs = ["wss://sync.example.com"]
    }
}
```

```swift
import DittoSwift

// ✅ GOOD: A hub that serves up to 12 TCP clients. The limit is part of the
// hub's configuration, so it is applied on every open, before sync starts
// (SDK 5.2+).
func hubConfig(connect: DittoConfigConnect) -> DittoConfig {
    DittoConfig(
        databaseID: "YOUR_DATABASE_ID",
        connect: connect,
        systemParameters: ["MESH_CHOOSER_MAX_WLAN_CONNECTIONS": 12]
    )
}

// Call with an instance opened from hubConfig(connect:), after the
// authentication handler or the offline license token is set.
func startHub(_ ditto: Ditto) throws {
    ditto.updateTransportConfig { config in
        config.listen.tcp.isEnabled = true
        config.listen.tcp.interfaceIP = "[::]"
        config.listen.tcp.port = 4040
    }
    try ditto.sync.start()
}
```

**Transport conditions and permissions (SDK 5.1+)**: Swift reports why a transport is not working through `DittoDelegate.dittoTransportConditionDidChange(ditto:condition:subsystem:)`, with conditions such as `.BleDisabled`, `.NoBleCentralPermission`, and `.AppInBackground`, delivered on `ditto.delegateEventQueue`. iOS shows the Bluetooth and local network prompts by itself, from the `Info.plist` descriptions (see [Diagnosing transport problems (SDK 5.1+)](../setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51)). `ditto.delegate` is a strong reference, so set it back to `nil` when the delegate's owner goes away.

```swift
import DittoSwift

// ✅ GOOD: Surface transport problems, such as a missing Bluetooth permission.
final class TransportConditionsReporter: DittoDelegate {
    func dittoTransportConditionDidChange(ditto: Ditto, condition: DittoTransportCondition, subsystem: DittoConditionSource) {
        if condition != .Ok {
            print("Transport \(subsystem): \(condition)") // for example "Bluetooth: NoBleCentralPermission"
        }
    }
}

func watchTransports(_ ditto: Ditto) -> TransportConditionsReporter {
    let reporter = TransportConditionsReporter()
    ditto.delegate = reporter // set ditto.delegate = nil to stop
    return reporter
}
```

**Presence**: `ditto.presence.observe(didChangeHandler:)` returns a `DittoObserver`; call `stop()` on it when you no longer need it. `ditto.presence.graphPublisher()` delivers the same graphs to Combine. `graph.remotePeers` is a `[DittoPeer]`, and each `DittoPeer` has `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections` (with `peer1`, `peer2`, and `type`), `os`, `dittoSDKVersion`, and `peerMetadata`. Set this device's metadata with `try ditto.presence.setPeerMetadata(["role": "cashier"])` and its name with `ditto.deviceName` (see [Presence](../setup-and-lifecycle.md#presence)).

```swift
import DittoSwift
import SwiftUI

// ✅ GOOD: Show connected peers and stop the observer when done.
@MainActor
final class PeersModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let route: String
    }

    @Published private(set) var rows: [Row] = []
    private var observer: DittoObserver?

    func start(_ ditto: Ditto) {
        guard observer == nil else { return }
        observer = ditto.presence.observe { [weak self] graph in
            let localKey = graph.localPeer.peerKey
            let rows = graph.remotePeers.map { peer in
                Row(id: peer.peerKey, name: peer.deviceName, route: Self.route(peer, localKey: localKey))
            }
            Task { @MainActor in self?.rows = rows }
        }
    }

    func stop() {
        observer?.stop()
        observer = nil
    }

    // A peer's connections include its links to other peers, so only the
    // connections that have this device at one end make it a direct neighbor.
    private nonisolated static func route(_ peer: DittoPeer, localKey: String) -> String {
        let direct = Set(peer.connections.filter { $0.peer1 == localKey || $0.peer2 == localKey }.map { $0.type.rawValue })
        let route = direct.isEmpty ? "Through other peers" : "Direct (\(direct.sorted().joined(separator: ", ")))"
        return peer.isConnectedToDittoServer ? "\(route), connected to Ditto Server" : route
    }
}

struct PeerList: View {
    let ditto: Ditto
    @StateObject private var model = PeersModel()

    var body: some View {
        List(model.rows) { row in
            VStack(alignment: .leading) {
                Text(row.name)
                Text(row.route).font(.caption)
            }
        }
        .onAppear { model.start(ditto) }
        .onDisappear { model.stop() }
    }
}
```

**Incoming connections**: `ditto.presence.connectionRequestHandler` is an `async` closure that receives each `DittoConnectionRequest` and returns `.allow` or `.deny`; set it to `nil` to remove it (see [Controlling Incoming Connections](../security.md#controlling-incoming-connections)).

```swift
import DittoSwift

// ✅ GOOD: Accept only peers whose signed metadata belongs to this store.
// Requires a .server connection: identityServiceMetadata comes from your
// authentication webhook and is empty in small-peers-only mode.
func restrictConnectionsToStore(_ ditto: Ditto, storeID: String) {
    ditto.presence.connectionRequestHandler = { request in
        // The handler cannot throw; decide now, not after the timeout.
        let metadata = request.identityServiceMetadata
        return metadata["storeId"] as? String == storeID ? .allow : .deny
    }
}
```

## Logging in Swift

`DittoLogger` is a set of static members that work before any instance is opened: `isEnabled` (default `true`), `minimumLogLevel` (`.error`, `.warning`, `.info` (the default), `.debug`, `.verbose`), `setCustomLogCallback(_:)`, and `export(to:)`. Configure it before you open Ditto, so that startup is logged with your settings. The rules are in [Logging](../logging-and-observability.md#logging).

```swift
import DittoSwift

/// Call before Ditto.open(config:).
func configureDittoLogging() {
    DittoLogger.isEnabled = true
    #if DEBUG
    DittoLogger.minimumLogLevel = .debug
    #else
    DittoLogger.minimumLogLevel = .warning
    #endif
}
```

`DittoLogger.setCustomLogCallback(_:)` receives the log events that Ditto emits. It applies to the whole process, and in our testing with SDK 5.2.0 it kept receiving lines after an instance had shut down and from the next instance (see [In Swift, the custom log callback stays installed after an instance shuts down](../../knowledge/observations/swift-sdk.md#in-swift-the-custom-log-callback-stays-installed-after-an-instance-shuts-down)). Install it once at startup, and remove it with `setCustomLogCallback(nil)`.

```swift
import DittoSwift

/// Forwards Ditto warnings and errors to the app's logging pipeline.
/// Call once at startup; the callback stays installed for the whole process.
func installDittoLogForwarding(report: @escaping @Sendable (String) -> Void) {
    DittoLogger.setCustomLogCallback { level, message in
        if level == .error || level == .warning {
            report("[ditto \(level)] \(message)")
        }
    }
}

func removeDittoLogForwarding() {
    DittoLogger.setCustomLogCallback(nil)
}
```

`try await DittoLogger.export(to:)` writes the on-disk logs and returns the number of bytes; it throws `DittoError.ioError(reason: .alreadyExists(...))` ("File exists (os error 17)") if the file exists (see [On-disk logs and exporting them](../logging-and-observability.md#on-disk-logs-and-exporting-them)):

```swift
import DittoSwift
import Foundation

/// Exports Ditto's on-disk logs, for example for a "Send diagnostics" button.
/// directory must exist, for example FileManager.default.temporaryDirectory.
func exportDittoLogs(to directory: URL) async throws -> URL {
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let file = directory.appendingPathComponent("ditto-logs-\(timestamp).jsonl.gz")
    let bytes = try await DittoLogger.export(to: file)
    print("Exported \(bytes) bytes of Ditto logs to \(file.path)")
    return file
}
```

A support bundle (SDK 5.2+) is created with DQL and fetched like any other attachment (see [Support bundles (SDK 5.2+)](../logging-and-observability.md#support-bundles-sdk-52)):

```swift
import DittoSwift
import Foundation

// ✅ GOOD: Create a support bundle and save it, for example to share it with
// Ditto support. path must not exist yet.
func saveSupportBundle(_ ditto: Ditto, to path: String) async throws {
    let result = try await ditto.store.execute(query: "EXECUTE FUNCTION system_request_support_bundle()")
    guard let token = result.items.first?.value["file"] as? [String: Any?] else { return }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        do {
            try ditto.store.fetchAttachment(token: token.compactMapValues { $0 }, deliverOn: DispatchQueue(label: "bundle")) { event in
                switch event {
                case .completed(let attachment):
                    continuation.resume(with: Result { try attachment.copy(toPath: path) })
                case .deleted:
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                case .progress:
                    break
                @unknown default:
                    break
                }
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
```

**Storage snapshot**: read `system:system_info` with `execute` when you need it, ordered by `timestamp`, and let later rows of a key overwrite earlier ones (see [Monitoring Storage](../deletion-and-storage.md#monitoring-storage)). Swift also offers `ditto.diskUsage.item` (the size of the persistence directory and its children) and `ditto.diskUsage.observe(eventHandler:)`, whose `DittoDiskUsageObserver` you `stop()`.

```swift
import DittoSwift

// ✅ GOOD: Read the latest storage snapshot on demand (for example from a
// diagnostics screen or a daily maintenance task).
func storageSnapshot(_ ditto: Ditto) async throws -> [String: Any?] {
    let result = try await ditto.store.execute(query: """
        SELECT key, value, timestamp FROM system:system_info
        WHERE key LIKE 'fs_%' OR key LIKE 'collection_num_docs%'
        ORDER BY timestamp ASC
        """)
    var snapshot: [String: Any?] = [:]
    for item in result.items {
        // Later rows overwrite earlier ones, so the newest value wins.
        if let key = item.value["key"] as? String { snapshot[key] = item.value["value"] ?? nil }
    }
    snapshot["diskUsageBytes"] = ditto.diskUsage.item.sizeInBytes
    return snapshot
}
```

## Testing in Swift

The tests below use [Swift Testing](https://developer.apple.com/documentation/testing) and the helper from [A local-store test helper in Swift](#a-local-store-test-helper-in-swift), which gives each test its own empty store. Put them in a test target that depends on `DittoSwift`. What each test checks is described in [Testing Strategies](../testing.md).

```swift
import DittoSwift
import Testing

@Test func addingALineItemKeepsTheExistingItems() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:order)",
            arguments: ["order": ["_id": "order-1", "items": ["item-1": ["productId": "p1", "quantity": 2]]]]
        )

        // The code under test: an upsert of a partial document (see "Arrays and Maps").
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["patch": ["_id": "order-1", "items": ["item-2": ["productId": "p2", "quantity": 1]]]]
        )

        let result = try await ditto.store.execute(query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": "order-1"])
        let items = try #require(result.items.first?.value["items"] as? [String: Any?]) // a map, not an array
        #expect(Set(items.keys) == ["item-1", "item-2"])
    }
}

@Test func reUpsertingUnchangedDataIsANoOp() async throws {
    try await withTestDitto { ditto in
        let product: [String: Any?] = ["_id": "p1", "name": "Pen", "priceCents": 250]
        try await ditto.store.execute(
            query: "INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["product": product]
        )
        let again = try await ditto.store.execute(
            query: "INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            arguments: ["product": product]
        )
        #expect(again.mutatedDocumentIDs().isEmpty)
    }
}

// The code under test: the app's replaceAddress() (see "Assigning an object merges it").
func replaceAddress(_ ditto: Ditto, customerID: String, address: [String: Any?]) async throws {
    try await ditto.store.transaction(hint: "replaceAddress") { tx in
        try await tx.execute(query: "UPDATE customers UNSET address WHERE _id = :id", arguments: ["id": customerID])
        try await tx.execute(
            query: "UPDATE customers SET address = :address WHERE _id = :id",
            arguments: ["id": customerID, "address": address]
        )
        return .commit
    }
}

@Test func replaceAddressRemovesKeysThatAreNotInTheNewAddress() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO customers DOCUMENTS (:customer)",
            arguments: ["customer": ["_id": "c1", "address": ["city": "Oslo", "zip": "0150"]]]
        )
        try await replaceAddress(ditto, customerID: "c1", address: ["city": "Bergen"])

        let result = try await ditto.store.execute(query: "SELECT * FROM customers WHERE _id = :id", arguments: ["id": "c1"])
        // A plain SET would keep "zip": objects merge under the default settings.
        let address = try #require(result.items.first?.value["address"] as? [String: Any?])
        #expect(address.keys.sorted() == ["city"])
        #expect(address["city"] as? String == "Bergen")
    }
}
```

```swift
import DittoSwift
import Testing

@Test func activeOrdersQueryTreatsAMissingOrNullFlagAsNotDeleted() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:orders)",
            arguments: ["orders": [
                ["_id": "deleted", "isDeleted": true],
                ["_id": "active", "isDeleted": false],
                ["_id": "nullFlag", "isDeleted": nil] as [String: Any?],
                ["_id": "noFlag"],
            ]]
        )

        // The query used by the app's repository.
        let result = try await ditto.store.execute(
            query: "SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id"
        )
        #expect(result.items.map { $0.value["_id"] as? String } == ["active", "noFlag", "nullFlag"])
    }
}

@Test func deletingByIDRemovesExactlyTheListedDocuments() async throws {
    try await withTestDitto { ditto in
        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:orders)",
            arguments: ["orders": [["_id": "o1"], ["_id": "o2"], ["_id": "o3"]]]
        )

        // The statement used by the app; WHERE _id IN :ids, not USE IDS.
        let deleted = try await ditto.store.execute(
            query: "DELETE FROM orders WHERE _id IN :ids", arguments: ["ids": ["o1", "o2"]]
        )
        #expect(deleted.mutatedDocumentIDs().count == 2)

        let remaining = try await ditto.store.execute(query: "SELECT _id FROM orders")
        #expect(remaining.items.map { $0.value["_id"] as? String } == ["o3"])
    }
}
```

```swift
import DittoSwift
import Foundation
import Testing

@Test func observerSeesANewOrderAndIsCancelledCleanly() async throws {
    try await withTestDitto { ditto in
        let sawOrder = Task {
            // Created inside the task, so that the stream is released with it.
            let stream = ditto.store.rows( // from "Observer lifecycle in Swift"
                query: "SELECT * FROM orders WHERE status = :status ORDER BY _id",
                arguments: ["status": "open"]
            )
            for await rows in stream where rows.count == 1 { return true }
            return false
        }

        try await ditto.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:order)",
            arguments: ["order": ["_id": "order-1", "status": "open"]]
        )
        let timeout = Task { try await Task.sleep(nanoseconds: 5_000_000_000); sawOrder.cancel() }
        #expect(await sawOrder.value)
        timeout.cancel()

        // The task has ended and released the stream, which cancelled the observer.
        #expect(ditto.store.observers.isEmpty)
    }
}
```

For tests of views and models that own observers, keep the observer behind your own protocol and pass a fake that yields the rows you choose. `DittoDiffer` only accepts items produced by Ditto, so code that uses it needs a real store.

`registerSubscription` throws a `DittoError` for a query that subscriptions do not accept:

```swift
import DittoSwift
import Testing

@Test func subscriptionsWithOrderByAndLimitOrJoinAreRejected() async throws {
    try await withTestDitto { ditto in
        #expect(throws: DittoError.self) {
            try ditto.sync.registerSubscription(query: "SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50")
        }
        #expect(throws: DittoError.self) {
            try ditto.sync.registerSubscription(query: "SELECT * FROM orders o JOIN customers c ON o.customerId = c._id")
        }
    }
}

@Test func theAppsSubscriptionsAreValid() async throws {
    try await withTestDitto { ditto in
        let subscriptions = [
            try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": "store-1"]
            ),
            try ditto.sync.registerSubscription(query: "SELECT * FROM products"),
        ]
        for subscription in subscriptions {
            subscription.cancel()
            #expect(subscription.isCancelled)
        }
    }
}
```

```swift
import DittoSwift
import Foundation
import Testing

/// The app's statements with representative arguments. In a real app, keep
/// the statement strings in your repository and reference them here.
let appStatements: [(statement: String, arguments: [String: Any?])] = [
    ("SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC", ["status": "open"]),
    ("UPDATE orders SET status = :status WHERE _id = :id", ["status": "closed", "id": "order-1"]),
    ("DELETE FROM orders WHERE _id IN :ids", ["ids": ["order-1"]]),
]

@Test func everyAppStatementCanBePlanned() async throws {
    try await withTestDitto { ditto in
        for (statement, arguments) in appStatements {
            // EXPLAIN throws if a statement cannot be parsed or planned.
            try await ditto.store.execute(query: "EXPLAIN \(statement)", arguments: arguments)
        }
    }
}

@Test func theOpenOrdersQueryUsesItsIndex() async throws {
    // In your suite, create indexes with the same startup code as the app
    // (for example, through the configure parameter of withTestDitto).
    try await withTestDitto(configure: { ditto in
        try await ditto.store.execute(
            query: "CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)"
        )
    }) { ditto in
        let plan = try await ditto.store.execute(
            query: "EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC",
            arguments: ["status": "open"]
        )
        let json = String(decoding: plan.items.first?.jsonData() ?? Data(), as: UTF8.self)
        #expect(json.contains("indexScan"))
    }
}
```

### A local-store test helper in Swift

The helper below opens a small-peers-only instance in its own temporary directory, passes it to the test, and afterwards releases it (which shuts it down) and deletes the directory, also when the test throws (see [A Test Helper for a Local Store](../testing.md#a-test-helper-for-a-local-store)). Pass the same `systemParameters` that your app passes in its `DittoConfig`, and a `configure` closure for the indexes that your app creates at startup. Swift Testing runs tests in parallel, and each test gets its own directory, so they do not share a store.

```swift
// Tests/OrdersTests/TestDitto.swift
import DittoSwift
import Foundation
import Testing

/// Opens a Ditto instance for one test, runs body with it, then shuts it down
/// and deletes its directory. Sync is never started, so no license token or
/// network connection is needed.
func withTestDitto<T>(
    systemParameters: [String: DittoSystemParameterValue] = [:],
    configure: ((Ditto) async throws -> Void)? = nil,
    _ body: (Ditto) async throws -> T
) async throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ditto-test-\(UUID().uuidString)")
    var ditto: Ditto? = try await Ditto.open(config: DittoConfig(
        // Any UUID works for local tests; each test gets its own directory.
        databaseID: "00000000-0000-4000-8000-000000000001",
        connect: .smallPeersOnly(),
        persistenceDirectory: directory,
        // The same parameters as the app's DittoConfig (SDK 5.2+).
        systemParameters: systemParameters
    ))
    func shutDown() {
        ditto = nil // The last reference: shuts the instance down.
        try? FileManager.default.removeItem(at: directory) // Best effort.
    }
    do {
        try await configure?(ditto!) // Create the app's indexes, as at app startup.
        let result = try await body(ditto!)
        shutDown()
        return result
    } catch {
        shutDown()
        throw error
    }
}

@Test func aNewStoreIsEmpty() async throws {
    try await withTestDitto { ditto in
        let result = try await ditto.store.execute(query: "SELECT COUNT(*) AS n FROM orders")
        #expect(result.items.first?.value["n"] as? Int == 0)
    }
}
```

**Running the tests:** add a test target that depends on `DittoSwift`, and run it with `swift test` for a package or with Xcode (`xcodebuild test`) for an app, on macOS or in an iOS simulator. Do not keep a reference to the `Ditto` passed to `body` after it returns: the helper's release would then not be the last one, and the directory would be deleted under an open store.

### Several peers in one test in Swift

The helper below opens several small peers in one test process and connects them over TCP on `127.0.0.1` only (see [Several peers in one test process](../testing.md#several-peers-in-one-test-process)). Pass the offline license token from the environment of the test run (never commit it), for example with `DITTO_LICENSE_TOKEN` in the scheme's test environment variables; the test is skipped without it.

```swift
// Tests/OrdersTests/MultiPeerTests.swift
import DittoSwift
import Foundation
import Testing

/// Offline license token from the test environment (never commit it).
let licenseToken = ProcessInfo.processInfo.environment["DITTO_LICENSE_TOKEN"] ?? ""

struct PeersTimeout: Error { let what: String }

/// Opens count peers that sync with each other over TCP on localhost only:
/// peer 0 listens, the others connect to it. A device accepts at most 6 TCP
/// connections by default, so keep count at 7 or below. The peers shut down
/// when body returns.
func withSyncedPeers<T>(
    _ count: Int,
    port: UInt16 = 4041,
    databaseID: String = "00000000-0000-4000-8000-000000000002",
    token: String = licenseToken,
    _ body: ([Ditto]) async throws -> T
) async throws -> T {
    let directories = (0..<count).map { i in
        FileManager.default.temporaryDirectory.appendingPathComponent("ditto-peer\(i)-\(UUID().uuidString)")
    }
    var peers: [Ditto] = []
    defer {
        peers.removeAll() // The last references: shuts the peers down.
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
    }
    for (i, directory) in directories.enumerated() {
        // All peers of a group use the same database ID; give every group
        // that can run at the same time its own ID and port.
        let ditto = try await Ditto.open(config: DittoConfig(
            databaseID: databaseID, connect: .smallPeersOnly(), persistenceDirectory: directory
        ))
        try ditto.setOfflineOnlyLicenseToken(token)
        ditto.updateTransportConfig { config in
            config.setAllPeerToPeer(enabled: false) // no Bluetooth, LAN, or AWDL
            if i == 0 {
                config.listen.tcp.isEnabled = true
                config.listen.tcp.interfaceIP = "127.0.0.1"
                config.listen.tcp.port = port
            } else {
                config.connect.tcpServers = ["127.0.0.1:\(port)"]
                // A device that only connects still listens on every interface,
                // so bind its listener to this machine: test peers stay off the network.
                config.listen.tcp.isEnabled = true
                config.listen.tcp.interfaceIP = "127.0.0.1"
                config.listen.tcp.port = 0
            }
        }
        try ditto.sync.start()
        peers.append(ditto)
    }
    try await waitUntil("peers connected") { peers.allSatisfy { !$0.presence.graph.remotePeers.isEmpty } }
    return try await body(peers)
}

func waitUntil(_ what: String, timeout: TimeInterval = 15, _ condition: () async throws -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while try await !condition() {
        guard Date() < deadline else { throw PeersTimeout(what: what) }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

/// Stops sync on every peer, runs writes while the peers are disconnected,
/// then reconnects them, so the writes are concurrent.
func whileDisconnected(_ peers: [Ditto], _ writes: () async throws -> Void) async throws {
    for peer in peers { peer.sync.stop() }
    try await waitUntil("peers disconnected") { peers.allSatisfy { $0.presence.graph.remotePeers.isEmpty } }
    try await writes()
    for peer in peers { try peer.sync.start() }
    try await waitUntil("peers reconnected") { peers.allSatisfy { !$0.presence.graph.remotePeers.isEmpty } }
}

/// Waits until query returns the same rows on every peer and until holds for
/// them, then returns the rows (as JSON objects, which compare reliably).
func waitForConvergence(
    _ peers: [Ditto],
    query: String,
    arguments: [String: Any?] = [:],
    until: ([[String: Any]]) -> Bool = { _ in true }
) async throws -> [[String: Any]] {
    var rows: [[String: Any]] = []
    try await waitUntil("peers converged on \(query)") {
        var results: [[[String: Any]]] = []
        for peer in peers {
            let result = try await peer.store.execute(query: query, arguments: arguments)
            results.append(try result.items.map { try JSONSerialization.jsonObject(with: $0.jsonData()) as? [String: Any] ?? [:] })
        }
        let first = results[0] as NSArray
        guard results.allSatisfy({ ($0 as NSArray).isEqual(first) }), until(results[0]) else { return false }
        rows = results[0]
        return true
    }
    return rows
}

@Test(.enabled(if: !licenseToken.isEmpty, "Needs DITTO_LICENSE_TOKEN"))
func concurrentEditsOfDifferentLineItemsBothSurvive() async throws {
    try await withSyncedPeers(2) { peers in
        let (tablet, phone) = (peers[0], peers[1])
        let subscriptions = try peers.map { try $0.sync.registerSubscription(query: "SELECT * FROM orders") }
        defer { subscriptions.forEach { $0.cancel() } }
        try await tablet.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:order)",
            arguments: ["order": ["_id": "order-1", "items": ["item-1": ["productId": "p1", "quantity": 1]]]]
        )
        _ = try await waitForConvergence(peers, query: "SELECT * FROM orders") { $0.count == 1 }

        // The code under test would be the app's repository functions.
        try await whileDisconnected(peers) {
            try await tablet.store.execute(
                query: "UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id", arguments: ["id": "order-1"]
            )
            try await phone.store.execute(
                query: "UPDATE orders SET items.`item-2` = :item WHERE _id = :id",
                arguments: ["id": "order-1", "item": ["productId": "p2", "quantity": 1]]
            )
        }

        let rows = try await waitForConvergence(
            peers, query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": "order-1"]
        ) { ($0.first?["items"] as? [String: Any])?.count == 2 }
        let items = try #require(rows.first?["items"] as? [String: [String: Any]])
        #expect(items["item-1"]?["quantity"] as? Int == 3)
        #expect(items["item-2"]?["productId"] as? String == "p2")
    }
}
```

## Behavior Specific to the Swift SDK

The behavior below differs from the other SDKs or is easy to miss. Each item links to its observation; the observations that are specific to the Swift SDK are collected on [Swift SDK Behavior](../../knowledge/observations/swift-sdk.md).

**Opening and shutting down**:
- **Note (SDK 5.2.0):** DittoSwift 5.2.0 has no `Ditto.close()`, although the 5.2.0 release notes announce it; an instance shuts down when its last strong reference is released (see [In Swift 5.2.0, Ditto has no close() method](../../knowledge/observations/swift-sdk.md#in-swift-520-ditto-has-no-close-method)).
- **Note (SDK 5.1.0 and 5.2.0):** releasing the last reference shuts the instance down at once, even while `store`, `sync`, or `presence` are still referenced, and the release waits for open transactions (see [In Swift, releasing the last reference shuts Ditto down at once](../../knowledge/observations/swift-sdk.md#in-swift-releasing-the-last-reference-shuts-ditto-down-at-once)).
- **Note (SDK 5.1.0 and 5.2.0):** after the release, some calls throw `useAfterCloseError` and others end the process with a `Fatal error`; on 5.1.0, `store.execute` also ends the process (see [In Swift, calls after the instance is released throw or end the process](../../knowledge/observations/swift-sdk.md#in-swift-calls-after-the-instance-is-released-throw-or-end-the-process)).
- **Note (SDK 5.2.0):** writes in flight when the instance is released fail with `useAfterCloseError` (see [In Swift 5.2.0, writes in flight fail when the instance is released](../../knowledge/observations/swift-sdk.md#in-swift-520-writes-in-flight-fail-when-the-instance-is-released)).
- **Note (SDK 5.1.0 and 5.2.0):** opening a directory that the same process has open throws `persistenceDirectoryLocked` after about 1 second (see [In Swift, opening an open directory again fails after about a second](../../knowledge/observations/swift-sdk.md#in-swift-opening-an-open-directory-again-fails-after-about-a-second)).

**Observers and results**:
- **Note (SDK 5.1.0 and 5.2.0):** a dropped `DittoStoreObserver` or `DittoSyncSubscription` keeps running; `registerObserver` and `registerSubscription` are `@discardableResult` (see [In Swift, dropped observer and subscription objects keep running](../../knowledge/observations/swift-sdk.md#in-swift-dropped-observer-and-subscription-objects-keep-running)).
- **Note (SDK 5.1.0 and 5.2.0):** `handler:` waits for the handler to return before the next result, so a slow handler on `.main` delays both the updates and the UI; a handler that starts a `Task` gets every result, and the tasks overlap. The default `deliverOn` is `.main`, and handlers cannot throw (see [In Swift, a store observer's handler waits for the previous one](../../knowledge/observations/swift-sdk.md#in-swift-a-store-observers-handler-waits-for-the-previous-one)).
- An `AsyncStream` around an observer cancels it when the consuming task ends (see [In Swift, an AsyncStream around an observer cancels it when its task ends](../../knowledge/observations/swift-sdk.md#in-swift-an-asyncstream-around-an-observer-cancels-it-when-its-task-ends)).
- `item.value` is a dictionary copy, and results stay readable after the instance shuts down (see [In Swift, query result values are copies that outlive the instance](../../knowledge/observations/swift-sdk.md#in-swift-query-result-values-are-copies-that-outlive-the-instance)).

**DQL and values**:
- **Note (SDK 5.1.0 and 5.2.0):** on a device connected to a peer in another process, a read of `system:data_sync_info` sometimes never completes, and later reads of it do not either; give each read a deadline (see [In Swift, a read of system:data_sync_info can stop responding](../../knowledge/observations/swift-sdk.md#in-swift-a-read-of-systemdata_sync_info-can-stop-responding)).
- `execute` and the registrations throw a `DittoError` at once for an invalid or unsupported statement (see [In Swift, invalid DQL throws from the registration call](../../knowledge/observations/swift-sdk.md#in-swift-invalid-dql-throws-from-the-registration-call)).
- **Note (SDK 5.1.0 and 5.2.0):** a float that a 32-bit float represents exactly, such as `12.5`, reads back from `item.value` as `Float`, so `as? Double` is `nil`; use `as? NSNumber` or `JSONDecoder` (see [In Swift, item.value returns a Float for values that fit in 32 bits](../../knowledge/observations/swift-sdk.md#in-swift-itemvalue-returns-a-float-for-values-that-fit-in-32-bits)).
- **Note (SDK 5.1.0 and 5.2.0):** a `Date` argument is stored as an object, `Decimal` and `URL` become objects of their fields, `UUID` becomes an uppercase string, `Data` comes back as `[UInt8]`, and `NaN`, infinity, `Character`, and `Substring` make the write throw; on 5.1.0, `NSNumber(value: true)` is stored as `1` (see [In Swift, a Date argument is stored as an object](../../knowledge/observations/swift-sdk.md#in-swift-a-date-argument-is-stored-as-an-object)).
- `queryArguments` of a subscription without arguments is `nil` (see [In Swift, a subscription without arguments has nil queryArguments](../../knowledge/observations/swift-sdk.md#in-swift-a-subscription-without-arguments-has-nil-queryarguments)).

**Transactions**:
- **Note (SDK 5.1.0 and 5.2.0):** a write through `ditto.store.execute`, and a read-write transaction, inside a read-write transaction never return, and later writes wait as well (see [In Swift, store.execute writes and nested read-write transactions inside a transaction do not return](../../knowledge/observations/swift-sdk.md#in-swift-storeexecute-writes-and-nested-read-write-transactions-inside-a-transaction-do-not-return)).
- **Note (SDK 5.1.0 and 5.2.0):** as many concurrent writes as the cooperative thread pool has threads (14 on a 14-core Mac), started while a read-write transaction is open, stop the transaction and every task of the process (see [In Swift, 14 concurrent writes during an open transaction stop the process](../../knowledge/observations/swift-sdk.md#in-swift-14-concurrent-writes-during-an-open-transaction-stop-the-process)).
- A transaction scope must return `.commit`, `.rollback`, or a value; a scope that returns nothing does not compile (see [Transactions in Swift](#transactions-in-swift)).

**Authentication and logging**:
- `login(token:provider:completion:)` reports failure to its completion handler and does not throw; `sync.start()` throws `expirationHandlerMissing` for a server connection without an expiration handler, and `logout(cleanup:)` runs its synchronous cleanup before it returns (see [In Swift, login reports failure to its completion handler](../../knowledge/observations/swift-sdk.md#in-swift-login-reports-failure-to-its-completion-handler)).
- The custom log callback stays installed for the whole process (see [In Swift, the custom log callback stays installed after an instance shuts down](../../knowledge/observations/swift-sdk.md#in-swift-the-custom-log-callback-stays-installed-after-an-instance-shuts-down)).
