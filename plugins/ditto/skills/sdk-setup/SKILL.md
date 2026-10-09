---
name: sdk-setup
description: Ditto SDK setup, lifecycle, and production security: DittoConfig, Ditto.open, the authentication expiration handler, system parameters, sync start and stop, close, transports, presence, keys, tokens, permissions, revocation. Use when initializing Ditto, writing login, startup, shutdown, or background code, configuring TCP hubs or transports, preparing a release or security review, or when sync never starts or devices do not connect.
---

# Ditto SDK Setup, Lifecycle, and Security

Opening Ditto, authenticating, starting and stopping sync, shutting down, transports and presence, and securing a production deployment. Targets Ditto SDK 5.1.0; examples are Flutter (Dart).

## Before You Apply

- Check the project's Ditto SDK version (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files); these rules were verified with 5.1.0. **Note (SDK 5.1.0)** marks easy-to-miss 5.1.0 behavior (wrong results, lost data, crashes, hangs) and its safe pattern; on another version, confirm it (release notes, docs.ditto.live) first. **(SDK 5.1+)** marks features introduced in 5.1.
- Examples are Dart. For JavaScript, Swift, or Kotlin, translate with `§ Platform Differences` and do not port Flutter observer or transaction code one-to-one.
- `§ <Heading>` cites a section of the full guide: Grep the heading in `../guide/reference/ditto.md` and read it for the reasoning or a complete example.

## Prevents

- A second `Ditto.open()` on an open persistence directory that never completes (Flutter, SDK 5.1.0)
- Keyless `DittoConfigConnectSmallPeersOnly()` in production (peers not authenticated)
- Hardcoded keys or tokens; the development provider or token in a release build
- Throwing inside the authentication expiration handler
- `ALTER SYSTEM` settings assumed to persist, or changed after sync has started
- `ditto.close()` on `AppLifecycleState.paused`
- A `TransportConfig()` built from scratch (every transport disabled)
- TCP hubs with more than six clients whose extra clients silently get no data
- Secrets or personal data in peer metadata or `identityServiceMetadata`
- Access control via mutable fields, `syncGroup`, or client checks; revocation checking disabled

## Workflow

App startup order (complete `DittoService`: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#complete-app-startup)):

```
Startup:
- [ ] 1. await Ditto.init() - only if DittoLogger or Ditto.openSync is used before open
- [ ] 2. DittoLogger settings (after init, before open)
- [ ] 3. await Ditto.open(DittoConfig(...)) once; share the instance
- [ ] 4. Server: await ditto.auth.setExpirationHandler(...) | Small peers: ditto.setOfflineOnlyLicenseToken(token)
- [ ] 5. ALTER SYSTEM SET ... for every system parameter (not persisted)
- [ ] 6. CREATE INDEX IF NOT EXISTS ... (skip on the Web)
- [ ] 7. Long-lived ditto.sync.registerSubscription(...)
- [ ] 8. ditto.sync.start() - returns void; do not await
- [ ] If a step after 3 fails: await ditto.close(), then rethrow
```

## Rules

### 1. Open Ditto once and share the instance (CRITICAL)

Only one `Ditto` instance can use a persistence directory at a time.
> **Note (SDK 5.1.0):** In Flutter, `Ditto.open()` on a directory that is already open may never complete instead of throwing.

**✅ DO**: open at app start and pass the instance through DI or a service; share one in-flight `Future` for concurrent callers (reset it on failure); in debug builds use a randomized `persistenceDirectory` to avoid lock conflicts after a hot restart (each starts empty), and a fixed one in release.
**❌ DON'T**: open per screen or request; reopen before `close()` completes; touch files in the persistence directory.

`Ditto.open()` initializes the SDK (SDK 5.1+). Call `await Ditto.init()` first only before `Ditto.openSync()`, `DittoLogger`, or `Ditto.defaultRootDirectory` (otherwise "Ditto not initialized"), or for custom Web asset URLs.

`§ One instance per persistence directory`, `§ Ditto.open, Ditto.openSync, and Ditto.init` · Example: `DittoProvider` in [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#one-instance-per-persistence-directory)

### 2. Choose the connection mode deliberately (CRITICAL)

| `connect` | Use for | Peer authentication |
|---|---|---|
| `DittoConfigConnectServer(url: ...)` | Production with real users | Webhook login; TLS |
| `DittoConfigConnectSmallPeersOnly(privateKey: key)` | Small peers only (closed networks) | Shared key; TLS 1.3 |
| `DittoConfigConnectSmallPeersOnly()` (default) | Local store tests, development | **None**; documented as unencrypted |

**✅ DO**: copy the Server URL from the Ditto Portal exactly; check no placeholder `databaseID` remains (`open()` may not reject it); in small-peers mode pass a base64 P-256 PKCS#8 DER `privateKey` from secure provisioning (MDM) and call `ditto.setOfflineOnlyLicenseToken(token)` before `sync.start()`; roll out a new key to all devices together.
**❌ DON'T**: ship the keyless mode; hardcode keys, tokens, or API keys (binaries can be decompiled); use a shared key when you need per-user permissions or single-device revocation.

`§ DittoConfig`, `§ Small-Peers-Only Deployments` · Details: [reference/security.md](reference/security.md#small-peers-only-deployments)

### 3. Set a non-throwing expiration handler before sync starts (CRITICAL)

With a server connection, `sync.start()` throws until a handler is set. It runs before the first login and when credentials near or pass expiry (`timeUntilExpiration == Duration.zero`: not authenticated or expired). `login()` **does not throw** on webhook rejection or an unreachable server; it returns `AuthResponse.exception` (it can still throw for other reasons, such as `DittoClosedException` after `close()`).

**✅ DO**: `await` the handler before `sync.start()`; fetch a fresh token inside it; check `response.exception`; catch your own errors.
**❌ DON'T**: throw or rethrow `response.exception` (the handler returns `void`, so the error is unhandled); cache one token for the app's lifetime; ship `Authenticator.developmentProvider` or the Portal development token.

```dart
await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
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
```

`await ditto.auth.logout()` **stops sync**; call `sync.start()` after the next login. `ditto.auth.status` has `isAuthenticated` and `userID`.

`§ Authentication`, `§ Authentication in Production` · Details: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#authentication)

### 4. Apply system parameters on every open, before sync starts (CRITICAL)

`ALTER SYSTEM SET` values are in memory only and reset on restart or reopen.

**✅ DO**: apply them in one startup function after `Ditto.open()` and before `sync.start()`, queries, or observers (subscriptions may come first); confirm with `SHOW <parameter>`; reset with `ALTER SYSTEM RESET`.
**❌ DON'T**: run `ALTER SYSTEM` once in a migration; change `DQL_STRICT_MODE` (default `false`) after sync, queries, or observers have run.

`§ Applying System Parameters`, `§ System Parameters Reference`, `§ Strict Mode`

### 5. Start sync after its prerequisites; never close on background (CRITICAL)

`sync.start()` and `stop()` return `void` (do not await). `start()` throws without the expiration handler or license token; it does nothing if already active (`ditto.sync.isActive`). After `stop()` the local store stays usable, connections close, subscriptions stay registered, and changes sync after `start()`.

**✅ DO**: keep Ditto open in the background; if the app must not sync there, `stop()` on `paused` and restart on `resumed` only the sync you paused.
**❌ DON'T**: call `ditto.close()` on `paused`: it is final, later calls throw `DittoClosedException`, and every subscription and observer must be re-created.

Background sync: iOS is best-effort and needs the Bluetooth central and peripheral background modes; Android needs Ditto's foreground service in `AndroidManifest.xml`.

`§ Starting and Stopping Sync` · Example: `SyncLifecycle` in [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#app-lifecycle)

### 6. Change transports with updateTransportConfig (CRITICAL)

A new `TransportConfig()` has **every transport disabled**, including the peer-to-peer transports a default instance enables. The `DittoConfigConnectServer` URL is used automatically.

**✅ DO**: `ditto.updateTransportConfig((config) { ... })`, changing only what you need (`setAllPeerToPeerEnabled()`, `peerToPeer.bluetoothLE.isEnabled`, `listen.tcp`, `connect.tcpServers`).
**❌ DON'T**: assign a fresh `TransportConfig()`; treat `global.syncGroup` as a security boundary.

Invalid values do not throw; they only log. WebSocket sync between Small Peers is off by default; enable it only with TLS. Use Multicast (Beta) (SDK 5.1+) only with Ditto support.

`§ Transport Configuration`, `§ Multicast (Beta) (SDK 5.1+)` · Details: [reference/transports-and-presence.md](reference/transports-and-presence.md)

### 7. Raise the TCP connection limit on hubs with more than six clients (CRITICAL)

> **Note (SDK 5.1.0):** A device accepts 6 TCP connections by default (`MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In testing, extra clients got no data and no API error; only a `WARN` log `... at capacity for this transport`. The parameter is undocumented; confirm it with Ditto support before relying on it in production.

**✅ DO**: on the hub, `ALTER SYSTEM SET MESH_CHOOSER_MAX_WLAN_CONNECTIONS = 12` (or as needed) after `Ditto.open` and **before** `sync.start()`, on every open.
**❌ DON'T**: raise it after sync started (rejected clients stayed out in testing).

`§ Transport Configuration` · Example: `startHub` in [reference/transports-and-presence.md](reference/transports-and-presence.md#tcp-connection-limit-per-hub)

### 8. Keep peer metadata and identity metadata non-sensitive (CRITICAL)

`ditto.presence.peerMetadata` and the webhook's `identityServiceMetadata` reach every peer in the mesh.

**✅ DO**: keep peer metadata small (max 4096 bytes encoded; larger throws), set once at startup (`{'role': 'cashier'}`); `stop()` presence observers when their screen goes away.
**❌ DON'T**: put secrets, tokens, or personal data in either; treat self-set `peerMetadata` as a security check.

`§ Presence`, `§ Identity metadata is visible to the mesh` · Example: `PeerList` in [reference/transports-and-presence.md](reference/transports-and-presence.md#presence)

### 9. Enforce access with webhook permissions scoped by _id (CRITICAL)

The webhook returns per-collection `read` and `write` rules (each with `everything` and `queriesByCollection`) that can reference only `_id`, in legacy syntax (`_id.storeId == 'store-1'`; `"true"` matches all), not DQL.

**✅ DO**: encode access boundaries (user, store, organization) in a structured `_id` before shipping; grant the narrowest rules per role; reject unknown users with `{"authenticated": false}`; keep `expirationSeconds` moderate so permission changes arrive on re-authentication; account for relaying: data travelling peer-to-peer requires mutual write permission, so read-only roles cannot relay it (see Ditto's data authorization docs).
**❌ DON'T**: rely on mutable fields, `syncGroup`, sync scopes, or client checks; embed long-lived secrets to mint tokens on the device.

`§ Permissions`, ``§ Design `_id` for permission scoping``, `§ Write authority and peer-to-peer relaying` · Details: [reference/security.md](reference/security.md#permissions)

### 10. Revoke by rejecting in the webhook first (CRITICAL)

Certificate revocation (SDK 5.1+) covers server-authenticated identities only and certificates issued before it; it is permanent.

**✅ DO**: reject the identity in the webhook, then revoke via the Ditto Server HTTP API; keep `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED` enabled (default).
**❌ DON'T**: disable revocation checking in production; expect revocation with a shared key.

`§ Certificate Revocation (SDK 5.1+)` · Details: [reference/security.md](reference/security.md#certificate-revocation-sdk-51)

### 11. Shut down in order, only when the app is done with Ditto (HIGH)

Release explicitly: `cancel()` observers and subscriptions, `stop()` presence and transport-condition observers and fetchers, `connectionRequestHandler = null`. `ditto.close()` is idempotent, stops sync, and releases resources (later calls throw `DittoClosedException`), but it **does not** wait for in-flight `execute()` or transactions, **does not** end `changes` streams, and **resets** `DittoLogger.customLogCallback`.

**✅ DO**: await pending work, cancel `StreamSubscription`s and observers, then `close()`; set the log callback again before reopening.
**❌ DON'T**: rely on garbage collection; send `Ditto` or `Store` to another isolate.

`§ Resource Cleanup and Shutdown`, `§ Forwarding logs to your own pipeline` · Example: `AppShutdown` in [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#resource-cleanup-and-shutdown)

### 12. Validate input, protect data at rest, secure the webhook (HIGH)

The local database is **not** encrypted at rest.

**✅ DO**: validate before writes and pass values as `:parameters`; treat peer documents as untrusted; rely on OS protection and encrypt sensitive fields in the app (keys in secure storage); serve the webhook over HTTPS, validate tokens, and verify the `ditto-signature` header.
**❌ DON'T**: interpolate input into DQL; store tokens or keys in documents.

`§ Input Validation and Query Parameters`, `§ Data at Rest`, `§ Webhook Security` · Details: [reference/security.md](reference/security.md#data-at-rest)

### 13. Filter connections with a fast, non-throwing handler (MEDIUM)

`ditto.presence.connectionRequestHandler` returns `allow` or `deny`; no answer in about 10 seconds denies. In testing with SDK 5.1.0, it also ran for connections this device initiated and did not drop existing ones; `identityServiceMetadata` was empty in small-peers-only mode.

**✅ DO**: catch errors and return `deny` at once; keep permissions as the primary control.

`§ Controlling Incoming Connections` · Example: [reference/security.md](reference/security.md#controlling-incoming-connections)

### 14. Plan for platform requirements and Web limits (MEDIUM)

Pin `ditto_live` in `pubspec.yaml`; request Bluetooth, Wi-Fi, local network, and nearby-device permissions before sync. Flutter Web: memory-only store, WebSocket sync to Ditto Server only, no peer-to-peer or license token effect, no indexes (`if (!kIsWeb)`).

`§ Requirements` · Details: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md#requirements)

## Diagnose: Sync Never Starts or Devices Do Not Connect

| Symptom | Cause |
|---|---|
| `start()`: "an authentication expiration handler has not yet been set" | No handler (rule 3) |
| `start()`: "...not yet activated" | No offline license token (small peers) |
| "The license failed verification" | `setOfflineOnlyLicenseToken()` throws: invalid token; a peer without a valid token is invisible |
| Server login fails silently | Unchecked `response.exception` |
| Sync stopped after sign-out | `logout()` stops sync |
| `WARN` `BadSignature` / `DecryptError` | Mismatched shared keys |
| `WARN` `at capacity for this transport` | Hub TCP limit (rule 7) |
| No peers, no error | Fresh `TransportConfig()`, missing permissions, radios off: `ditto.observeTransportConditions()`, `DittoSyncPermissions` (Android, SDK 5.1+) |
| `TRANSPORTS_DISCOVERED_PEERS` connects nothing | LAN transport disabled; use `connect.tcpServers` |
| No relay through a middle device | It lacks write permission |

`§ Diagnosing transport problems (SDK 5.1+)` · Details: [reference/transports-and-presence.md](reference/transports-and-presence.md#diagnosing-transport-problems-sdk-51)

## Checklist

- [ ] One shared instance; failed startup closes it
- [ ] Server + webhook, or small peers with provisioned `privateKey` and license token
- [ ] No keys, tokens, or development provider in release builds
- [ ] Expiration handler awaited before `sync.start()`; checks `response.exception`; never throws
- [ ] System parameters applied on every open, before sync
- [ ] `sync.start()` not awaited; no `close()` on `paused`
- [ ] Pending work awaited and observers cancelled before `close()`
- [ ] Transports via `updateTransportConfig()`; hub TCP limit raised before sync
- [ ] No secrets in peer or identity metadata
- [ ] Permissions scoped by `_id`, narrowest per role; revocation checking on
- [ ] Inputs parameterized; sensitive fields encrypted; webhook signatures verified

## More

- Reference: [reference/startup-and-lifecycle.md](reference/startup-and-lifecycle.md) - requirements, Web limits, `DittoConfig`, complete startup, auth, system parameters, lifecycle, shutdown, platform differences
- Reference: [reference/transports-and-presence.md](reference/transports-and-presence.md) - transports, TCP hub and limit, known peers, diagnostics, multicast, presence
- Reference: [reference/security.md](reference/security.md) - security model, shared keys, webhook response, `_id` design, revocation, connection handler, data at rest, webhook security, checklist
- Related skills: `query-sync` (subscriptions, parameters), `performance-observability` (logging details), `storage-lifecycle` (tombstone system parameters), `testing` (local store tests), `audit` (whole-app review)
