---
name: sdk-setup
description: Ditto SDK setup, lifecycle, and production security (Flutter, JavaScript, Kotlin, Swift): DittoConfig, opening Ditto, the authentication expiration handler, system parameters, sync start and stop, close, transports, presence, keys, permissions, revocation. Use when initializing Ditto, writing login, startup, shutdown, or background code, configuring transports, preparing a security review, or when sync never starts or devices do not connect.
---

# Ditto SDK Setup, Lifecycle, and Security

Opening Ditto, authenticating, starting and stopping sync, shutting down, transports and presence, and securing a production deployment. Targets Ditto SDK 5.2.0 in every SDK; the code for each SDK is on its page.

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). These rules target SDK 5.2.0; for devices that still run 5.1.0, also apply `§ Known Issues in SDK 5.1.0`. **Note (SDK 5.1.0 and 5.2.0)** marks easy-to-miss behavior confirmed on both releases, **Note (SDK 5.1.0)** behavior seen on 5.1.0 only; each gives the safe pattern. **(SDK 5.1+)** / **(SDK 5.2+)** mark features introduced in that release.
- Read that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), for the API calls; its sections are named `<Topic> in <SDK>`, such as *App startup in Kotlin*. DQL examples are `examples/*.sql` (every SDK); API examples are in `examples/<sdk>/` with the same base name in every SDK.
- `§ <Heading>` cites the full guide: Grep the heading in `../guide/reference/best-practices/` (including `platforms/`) and `../guide/reference/knowledge/`, then read that section.

## Prevents

- A second open of an open persistence directory that never completes (Flutter, SDK 5.1.0)
- Small-peers-only without a private key in production (peers not authenticated)
- Hardcoded keys or tokens; the development token in a release build
- Errors escaping the authentication expiration handler; unchecked login results
- System parameters assumed to persist, set with `ALTER SYSTEM` after open instead of in `DittoConfig`, or changed after sync has started
- Closing Ditto when the app moves to the background
- A transport configuration built from scratch (every transport disabled)
- TCP hubs with more than six clients whose extra clients silently get no data
- Secrets or personal data in peer metadata or `identityServiceMetadata`
- Presence recorded in documents on every callback
- Access control via mutable fields, `syncGroup`, or client checks; revocation checking disabled

## Workflow

App startup order (`§ Complete app startup`; the service for each SDK: *App startup in <SDK>* on the SDK page):

```
Startup:
- [ ] 1. Configure the logger before opening (Flutter: await Ditto.init() first)
- [ ] 2. Open the single shared instance with DittoConfig(..., system parameters); share it
- [ ] 3. Server: set the expiration handler | Small peers: setOfflineOnlyLicenseToken(token)
- [ ] 4. CREATE INDEX IF NOT EXISTS ... (skip on in-memory stores)
- [ ] 5. Long-lived ditto.sync.registerSubscription(...)
- [ ] 6. ditto.sync.start()
- [ ] If a step after 2 fails: close the instance, then report the error
- [ ] SDK 5.1: ALTER SYSTEM SET ... after step 3, before step 6
```

| | Flutter | JavaScript | Kotlin | Swift |
|---|---|---|---|---|
| Open | `await Ditto.open(DittoConfig(...))` | `await Ditto.open(config)` (Web: `await init()` first) | `DittoFactory.create(config)` | `try await Ditto.open(config:)` |
| Start sync | `ditto.sync.start()` (`void`; throws) | `ditto.sync.start()` | `ditto.sync.start()` (throws) | `try ditto.sync.start()` |
| Login failure | `AuthResponse.exception`; does not throw | Result `error`; does not throw | **Throws** | Completion handler `error` |
| Release observers, subscriptions | `cancel()` | `cancel()` | `close()` | `cancel()` |

More: `§ Platform Differences`.

## Rules

### 1. Open Ditto once and share the instance (CRITICAL)

Only one `Ditto` instance can use a persistence directory at a time. What a second open of an open directory does differs by SDK; never rely on it to fail.
> **Note (SDK 5.1.0):** In Flutter, `Ditto.open()` on a directory that is already open may never complete instead of throwing.

**✅ DO**: open at app start and pass the instance through DI or a service; let concurrent callers wait for one pending open (reset it on failure); where a tool restarts your code without ending the process (Flutter hot restart), use a new `persistenceDirectory` per start in debug builds, and a fixed one in release.
**❌ DON'T**: open per screen or request; reopen before closing has completed; touch, partly delete, or copy the persistence directory (sync silently diverges).

Flutter: `Ditto.open()` initializes the SDK (SDK 5.1+); call `await Ditto.init()` first only before `Ditto.openSync()`, `DittoLogger`, or `Ditto.defaultRootDirectory`, or for custom Web asset URLs.

`§ One instance per persistence directory`, `§ Opening Ditto in Flutter` · Example: *One shared instance in <SDK>* on the SDK page

### 2. Choose the connection mode deliberately (CRITICAL)

| Connection (Flutter name) | Use for | Peer authentication |
|---|---|---|
| Server URL (`DittoConfigConnectServer(url: ...)`) | Production with real users | Webhook login; TLS |
| Small peers with a key (`DittoConfigConnectSmallPeersOnly(privateKey: key)`) | Small peers only (closed networks) | Shared key; TLS 1.3 |
| Small peers without a key (the default) | Local store tests, development | **None**; documented as unencrypted |

**✅ DO**: copy the Server URL from the Ditto Portal exactly; check no placeholder `databaseID` remains (`open()` may not reject it); in small-peers mode pass a base64 P-256 PKCS#8 DER `privateKey` from secure provisioning (MDM) and call `setOfflineOnlyLicenseToken(token)` before you start sync; roll out a new key to all devices together.
**❌ DON'T**: ship the keyless mode; hardcode keys, tokens, or API keys (binaries can be decompiled); use a shared key when you need per-user permissions or single-device revocation.

`§ DittoConfig`, `§ Small-Peers-Only Deployments` · Code: *DittoConfig in <SDK>* · Details: [reference/security.md](reference/security.md#small-peers-only-deployments)

### 3. Set a non-throwing expiration handler before sync starts (CRITICAL)

With a server connection, starting sync fails until a handler is set. It runs before the first login and when credentials near or pass expiry. How `login` reports failure differs by SDK (*Login failure* above): Kotlin **throws**.

**✅ DO**: set the handler before you start sync; fetch a fresh token inside it; check the login result the way your SDK reports it; catch your own errors.
**❌ DON'T**: let an error escape from the handler (Ditto does not receive it, and it becomes unhandled); cache one token for the app's lifetime; ship the development provider or the Portal development token.

`auth.logout()` **stops sync**; start it again after the next login. Logout with a cleanup callback (SDK 5.2+) runs after sync stops and may only `EVICT`; it swallows exceptions, so verify the result.

`§ Authentication`, `§ Authentication in Production` · Code: *Authentication in <SDK>* · Details: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#authentication)

### 4. Pass system parameters in DittoConfig on every open (CRITICAL)

System parameters are in memory only and reset on restart or reopen. The system parameters of `DittoConfig` (SDK 5.2+) are applied before Ditto starts, so startup-only parameters take effect, and an unknown name or a wrong type makes opening fail. Startup-only parameters set later with `ALTER SYSTEM` have no effect.

**✅ DO**: pass the app's settings in one map on every open; use `ALTER SYSTEM` only to change a value while the app runs; confirm with `SHOW <parameter>`. On SDK 5.1: `ALTER SYSTEM` after opening and before sync starts, queries, or observers (subscriptions may come first).
**❌ DON'T**: run `ALTER SYSTEM` once in a migration; change `DQL_STRICT_MODE` (default `false`) after sync, queries, or observers have run.

`§ Applying System Parameters`, `§ System Parameters Reference`, `§ Strict Mode` · Code: *DittoConfig in <SDK>* on the SDK page

### 5. Start sync after its prerequisites; never close on background (CRITICAL)

Starting sync fails without the expiration handler or license token; it does nothing if already active (`sync.isActive`). After `sync.stop()` the local store stays usable, connections close, subscriptions stay registered, and changes sync after `start()`. Flutter's `start()` and `stop()` return `void` (do not await).

**✅ DO**: keep Ditto open in the background; if the app must not sync there, stop sync when the app goes to the background and restart on return only the sync you paused.
**❌ DON'T**: close Ditto when the app goes to the background: closing is final, later calls fail, and every subscription and observer must be re-created.

Background sync: iOS is best-effort and needs the Bluetooth central and peripheral background modes; Android needs Ditto's foreground service in `AndroidManifest.xml`.

`§ Starting and Stopping Sync` · Code: *Sync and the App Lifecycle in <SDK>* on the SDK page

### 6. Change transports with updateTransportConfig (CRITICAL)

A new, empty transport configuration has **every transport disabled**, including the peer-to-peer transports a default instance enables. The Server URL is used automatically.

**✅ DO**: `ditto.updateTransportConfig`, changing only what you need (all peer-to-peer transports, `peerToPeer.bluetoothLE`, `listen.tcp`, `connect.tcpServers`).
**❌ DON'T**: assign a fresh transport configuration (Flutter: `TransportConfig()`); treat `global.syncGroup` as a security boundary.

Invalid values do not throw; they only log. WebSocket sync between Small Peers is off by default; enable it only with TLS. Use Multicast (Beta) (SDK 5.1+) only with Ditto support.

`§ Transport Configuration`, `§ Multicast (Beta) (SDK 5.1+)` · Code: *Transports and Presence in <SDK>* · Details: [reference/transports-and-presence.md](reference/transports-and-presence.md)

### 7. Raise the TCP connection limit on hubs with more than six clients (CRITICAL)

> **Note (SDK 5.1.0 and 5.2.0):** A device accepts 6 TCP connections by default (`MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In testing, extra clients got no data and no API error; only a `WARN` log `... at capacity for this transport`. On 5.2.0, connections it opened itself also count when it accepts one, so a hub that also dials out admits fewer.

**✅ DO**: on the hub, pass `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` (for example 12) in the system parameters of `DittoConfig` on every open (SDK 5.2+); on SDK 5.1, `ALTER SYSTEM` after opening and **before** sync starts.
**❌ DON'T**: raise it after sync started (rejected clients stayed out in testing).

`§ Transport Configuration` · Details: [reference/transports-and-presence.md](reference/transports-and-presence.md#transport-configuration)

### 8. Keep metadata non-sensitive; record presence sparingly (CRITICAL)

`ditto.presence.peerMetadata` and the webhook's `identityServiceMetadata` reach every peer in the mesh.

**✅ DO**: keep peer metadata small (max 4096 bytes encoded; larger throws), set once at startup (`{"role": "cashier"}`); `stop()` presence observers when their screen goes away.
**❌ DON'T**: put secrets, tokens, or personal data in either; treat self-set `peerMetadata` as a security check.
**Recording presence (HIGH)**: write a peer only when its stored time is older than the needed precision, in one transaction, not per callback; keep writers of one peer from writing at once (e.g. random timers); never write from the observer that reads the record.

`§ Presence`, `§ Recording presence in documents`, `§ Identity metadata is visible to the mesh` · Code: *Transports and Presence in <SDK>* · Details: [reference/transports-and-presence.md](reference/transports-and-presence.md#presence)

### 9. Enforce access with webhook permissions scoped by _id (CRITICAL)

The webhook returns per-collection `read` and `write` rules (each with `everything` and `queriesByCollection`) that can reference only `_id`, in legacy syntax (`_id.storeId == 'store-1'`; `"true"` matches all), not DQL.

**✅ DO**: encode access boundaries (user, store, organization) in a structured `_id` before shipping; grant the narrowest rules per role; reject unknown users with `{"authenticated": false}`; keep `expirationSeconds` moderate so permission changes arrive on re-authentication; account for relaying: peer-to-peer data needs mutual write permission, so read-only roles cannot relay it.
**❌ DON'T**: rely on mutable fields, `syncGroup`, sync scopes, or client checks; embed long-lived secrets to mint tokens on the device.

`§ Permissions`, ``§ Design `_id` for permission scoping``, `§ Write authority and peer-to-peer relaying` · Details: [reference/security.md](reference/security.md#permissions)

### 10. Revoke by rejecting in the webhook first (CRITICAL)

Certificate revocation (SDK 5.1+) covers server-authenticated identities only and certificates issued before it; it is permanent.

**✅ DO**: reject the identity in the webhook, then revoke via the Ditto Server HTTP API; keep `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED` enabled (default).
**❌ DON'T**: disable revocation checking in production; expect revocation with a shared key.

`§ Certificate Revocation (SDK 5.1+)` · Details: [reference/security.md](reference/security.md#certificate-revocation-sdk-51)

### 11. Shut down in order, only when the app is done with Ditto (HIGH)

Release observers, subscriptions, presence and transport-condition observers, fetchers, and the connection request handler explicitly. Closing is final, stops sync, and releases resources, but **does not** wait for unsent changes. In-flight work: Flutter fails pending `execute()` calls, and stops the isolate if a transaction is open (on 5.2.0, reopening in the same process can also stop: `§ Changes in SDK 5.2.0`); JavaScript and Kotlin wait; Swift has no `close()` (5.1.0, 5.2.0): releasing the last reference shuts Ditto down and waits for an open transaction. Flutter's `close()` also does not end `changes` streams and **resets** `DittoLogger.customLogCallback`.

**✅ DO**: await pending work (if data must reach a peer, its confirmed commit ID), release observers, then close. A growing count in `ditto.store.observers` across screens reveals observers never released.
**❌ DON'T**: rely on garbage collection; send the Flutter `Ditto` or `Store` to another isolate.

`§ Resource Cleanup and Shutdown`, `§ Forwarding logs to your own pipeline` · Code: *Closing Ditto in <SDK>* on the SDK page

### 12. Validate input, protect data at rest, secure the webhook (HIGH)

Only Swift and Kotlin can encrypt the local store at rest (SDK 5.2+): a 32-byte key in `DittoConfig.encryptionKey` on every open, kept in the Keychain or Android Keystore; switching an existing store means deleting it (`deleteStore`) and syncing again.

**✅ DO**: validate before writes and pass values as `:parameters`; treat peer documents as untrusted; without Ditto encryption, rely on OS protection and encrypt sensitive fields in the app (keys in secure storage); serve the webhook over HTTPS, validate tokens, and verify the `ditto-signature` header.
**❌ DON'T**: interpolate input into DQL; store tokens or keys in documents.

`§ Input Validation and Query Parameters`, `§ Data at Rest`, `§ Webhook Security` · Details: [reference/security.md](reference/security.md#data-at-rest)

### 13. Filter connections with a fast, non-throwing handler (MEDIUM)

`ditto.presence.connectionRequestHandler` returns `allow` or `deny` within 10 s, or the peer is rejected; catch every error (a throw ends a Kotlin app).

**✅ DO**: catch errors and return `deny` at once; keep permissions as the primary control.

`§ Controlling Incoming Connections` · Code: *Transports and Presence in <SDK>* · Details: [reference/security.md](reference/security.md#controlling-incoming-connections)

### 14. Plan for platform requirements and Web limits (MEDIUM)

Pin the exact SDK version; request Bluetooth, Wi-Fi, local network, and nearby-device permissions before sync. Android, SDK 5.2+: multicast permissions are requested separately. Flutter 5.2: the root is application support, also for a relative `persistenceDirectory`, so pass the absolute 5.1 path or 5.1 data is not found. Flutter Web and the JavaScript SDK in browsers: in-memory store, no indexes; Flutter Web syncs only over WebSocket with Ditto Server.

`§ Requirements`, `§ DittoConfig`, `§ Upgrading from SDK 5.1` · Code: *Installing the <SDK> SDK* · Details: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#requirements)

## Diagnose: Sync Never Starts or Devices Do Not Connect

| Symptom | Cause |
|---|---|
| Opening fails with system parameters | Unknown name or wrong type (rule 4) |
| `start()`: "an authentication expiration handler has not yet been set" | No handler (rule 3) |
| `start()`: "...not yet activated" | No offline license token (small peers) |
| "The license failed verification" | `setOfflineOnlyLicenseToken` fails: invalid token; a peer without a valid token is invisible |
| Server login fails silently | Unchecked login result (rule 3) |
| Sync stopped after sign-out | `logout()` stops sync |
| `WARN` `BadSignature` / `DecryptError` | Mismatched shared keys |
| `WARN` `at capacity for this transport` | Hub TCP limit (rule 7) |
| No peers, no error | Fresh transport configuration, missing permissions, radios off: observe transport conditions; check Android permissions (SDK 5.1+) |
| `TRANSPORTS_DISCOVERED_PEERS` connects nothing | LAN transport disabled; use `connect.tcpServers` |
| No relay through a middle device | It lacks write permission |

`§ Diagnosing transport problems (SDK 5.1+)`, `§ When Data Does Not Sync` · Details: [reference/transports-and-presence.md](reference/transports-and-presence.md#diagnosing-transport-problems-sdk-51)

## Checklist

- [ ] One shared instance; failed startup closes it
- [ ] Server + webhook, or small peers with provisioned `privateKey` and license token
- [ ] No keys, tokens, or development provider in release builds
- [ ] Expiration handler awaited before `sync.start()`; checks `response.exception`; never throws
- [ ] System parameters in `DittoConfig.systemParameters` on every open (5.1: `ALTER SYSTEM` before sync)
- [ ] `sync.start()` not awaited; no `close()` on `paused`
- [ ] Pending work awaited and observers cancelled before `close()`
- [ ] Transports via `updateTransportConfig()`; hub TCP limit raised before sync
- [ ] No secrets in peer or identity metadata
- [ ] Permissions scoped by `_id`, narrowest per role; revocation checking on
- [ ] Inputs parameterized; sensitive data encrypted (store key on Swift/Kotlin, or fields); webhook signatures verified

## More

- Reference: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md) - requirements, Web limits, `DittoConfig`, complete startup, auth and logout cleanup, system parameters, lifecycle, shutdown, platform differences
- Reference: [reference/transports-and-presence.md](reference/transports-and-presence.md) - transports, TCP hub and limit, known peers, diagnostics, multicast, presence
- Reference: [reference/security.md](reference/security.md) - security model, shared keys, webhook response, `_id` design, revocation, connection handler, data at rest, webhook security, checklist
- Related skills: `query-sync` (subscriptions), `performance-observability` (logging, diagnostics), `storage-lifecycle` (tombstone parameters), `testing` (local store tests), `audit` (whole-app review)
