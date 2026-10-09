# Ditto SDK Best Practices

> **Version**: 2.5
> **Last Updated**: 2026-10-09
> **Applies to**: Ditto SDK 5.1.0 (Flutter `ditto_live` 5.1.0; notes for JavaScript, Swift, and Kotlin where behavior differs)

This guide collects best practices and anti-patterns for building offline-first applications with the Ditto SDK. It focuses on decisions that are hard to change later (data modeling, sync scope, deletion strategy) and on mistakes that silently cause data loss, unexpected merges, memory growth, or excessive sync traffic.

Upgrading an existing application from SDK v4? Follow the [migration guides](https://docs.ditto.live/sdk/latest/v5-whats-new) first. This guide describes SDK 5.x behavior only.

## How to Use This Guide

- **Primary platform**: Code examples use Flutter (Dart) with `import 'package:ditto_live/ditto_live.dart';`. JavaScript, Swift, and Kotlin are covered where their APIs or behavior differ (see [Platform Differences](#platform-differences)).
- **✅ DO / ❌ DON'T**: Each topic lists recommended practices and anti-patterns, followed by examples marked `// ✅ GOOD` and `// ❌ BAD`.
- **(SDK 5.1+)**: Marks features introduced in Ditto SDK 5.1. Everything else is available in 5.0 and later.
- **(Experimental)** / **(Beta)**: Marks APIs that the SDK itself marks as experimental or beta. Their signatures or behavior may change in a future release.
- **Note (SDK 5.1.0)**: Describes SDK 5.1.0 behavior that can silently produce wrong results, crash, or block, together with the recommended pattern that avoids it.
- **Verification**: The Dart examples in this guide were compiled against `ditto_live` 5.1.0, and the DQL statements were validated against Ditto SDK 5.1.0. Statements about what happens between devices (merges of concurrent edits, deletions, relay, subscriptions) that say "in tests" were observed with two or more SDK 5.1.0 peers syncing over TCP on one machine (JavaScript SDK on Node.js; the key cases also with Flutter on macOS); they describe 5.1.0 behavior, not a documented guarantee. Placeholders such as `'YOUR_DATABASE_ID'`, `'YOUR_SERVER_URL'`, `'YOUR_PROVIDER_NAME'`, `fetchAuthToken()`, and `showError()` stand for values and code from your own application.
- **Finding topics**: Start from the [Quick Reference](#quick-reference) or the [Anti-Pattern Checklist](#anti-pattern-checklist), which link to the detailed sections; each section is written to be read on its own. To jump to a topic directly, search for the exact API name, DQL keyword, system parameter, or error message, or for "Note (SDK 5.1.0)" to find behavior that needs a specific pattern.

## Table of Contents

- [Understanding Ditto](#understanding-ditto)
  - [What Is Ditto?](#what-is-ditto)
  - [Key Characteristics](#key-characteristics)
  - [Terminology](#terminology)
  - [Core Principles](#core-principles)
- [SDK Setup and Lifecycle](#sdk-setup-and-lifecycle)
  - [Requirements](#requirements)
  - [Initializing Ditto](#initializing-ditto)
  - [Authentication](#authentication)
  - [Applying System Parameters](#applying-system-parameters)
  - [Starting and Stopping Sync](#starting-and-stopping-sync)
  - [Resource Cleanup and Shutdown](#resource-cleanup-and-shutdown)
  - [Transport Configuration](#transport-configuration)
  - [Presence](#presence)
  - [Platform Differences](#platform-differences)
- [DQL Fundamentals](#dql-fundamentals)
  - [Where Queries Run](#where-queries-run)
  - [Parameters and Literals](#parameters-and-literals)
  - [MISSING and NULL](#missing-and-null)
  - [Working with Query Results](#working-with-query-results)
- [Reading Data with SELECT](#reading-data-with-select)
  - [Projections and Aliases](#projections-and-aliases)
  - [DISTINCT](#distinct)
  - [Aggregates](#aggregates)
  - [GROUP BY and HAVING](#group-by-and-having)
  - [ORDER BY](#order-by)
  - [LIMIT and OFFSET](#limit-and-offset)
  - [USE IDS](#use-ids)
  - [Filtering by Membership](#filtering-by-membership)
  - [Joining Collections (SDK 5.1+)](#joining-collections-sdk-51)
- [Writing Data](#writing-data)
  - [INSERT and Conflict Handling](#insert-and-conflict-handling)
  - [UPDATE](#update)
  - [RETURNING (SDK 5.1+)](#returning-sdk-51)
  - [DELETE and EVICT](#delete-and-evict)
- [DQL Functions and Operators](#dql-functions-and-operators)
  - [Date and Time](#date-and-time)
  - [Conditional Functions](#conditional-functions)
  - [Type Checking](#type-checking)
  - [String Functions](#string-functions)
  - [Object Functions](#object-functions)
  - [Arrays and Collection Operators](#arrays-and-collection-operators)
  - [ANY and EVERY](#any-and-every)
  - [ARRAY and OBJECT Transformations](#array-and-object-transformations)
  - [Arithmetic, Conversion, and Other Functions](#arithmetic-conversion-and-other-functions)
- [Data Modeling](#data-modeling)
  - [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior)
  - [Strict Mode](#strict-mode)
  - [Arrays and Maps](#arrays-and-maps)
  - [Document Structure](#document-structure)
  - [Document Size Limits](#document-size-limits)
  - [Relationships: Embedding, Separate Collections, and JOIN](#relationships-embedding-separate-collections-and-join)
  - [Document IDs](#document-ids)
  - [Counters](#counters)
  - [Event History and Audit Logs](#event-history-and-audit-logs)
  - [Default Data with INITIAL Documents](#default-data-with-initial-documents)
  - [Schema Evolution](#schema-evolution)
  - [Timestamps](#timestamps)
- [Sync and Subscriptions](#sync-and-subscriptions)
  - [Subscription Rules](#subscription-rules)
  - [Subscription Lifecycle](#subscription-lifecycle)
  - [Scope Balancing](#scope-balancing)
  - [Sync Scopes](#sync-scopes)
  - [Monitoring Sync Status](#monitoring-sync-status)
- [Observing Changes](#observing-changes)
  - [Store Observers in Flutter](#store-observers-in-flutter)
  - [Backpressure (SDK 5.1+)](#backpressure-sdk-51)
  - [Diffing Results](#diffing-results)
  - [Partial UI Updates](#partial-ui-updates)
- [Transactions](#transactions)
  - [Using store.transaction](#using-storetransaction)
  - [Transaction Rules](#transaction-rules)
  - [Concurrency and Duration](#concurrency-and-duration)
  - [Transactions and Sync](#transactions-and-sync)
  - [Transactions on Other Platforms](#transactions-on-other-platforms)
- [Attachments](#attachments)
  - [Attachment Architecture](#attachment-architecture)
  - [Creating and Inserting Attachments](#creating-and-inserting-attachments)
  - [Fetching Attachments](#fetching-attachments)
  - [Attachments Are Immutable](#attachments-are-immutable)
  - [Thumbnail Pattern](#thumbnail-pattern)
  - [Availability](#availability)
  - [Size Guidance](#size-guidance)
- [Deletion and Storage Management](#deletion-and-storage-management)
  - [DELETE and Tombstones](#delete-and-tombstones)
  - [Soft Delete](#soft-delete)
  - [EVICT](#evict)
  - [Choosing DELETE, Soft Delete, or EVICT](#choosing-delete-soft-delete-or-evict)
  - [Monitoring Storage](#monitoring-storage)
- [Indexing and Query Performance](#indexing-and-query-performance)
  - [Creating Indexes](#creating-indexes)
  - [Index Usage Rules](#index-usage-rules)
  - [ADVISE (SDK 5.1+)](#advise-sdk-51)
  - [EXPLAIN and PROFILE](#explain-and-profile)
  - [Query Scope and Execution](#query-scope-and-execution)
- [Logging and Observability](#logging-and-observability)
  - [Logging](#logging)
  - [System Virtual Collections](#system-virtual-collections)
  - [System Parameters Reference](#system-parameters-reference)
  - [Remote Diagnostics](#remote-diagnostics)
- [Security](#security)
  - [Security Model Overview](#security-model-overview)
  - [Authentication in Production](#authentication-in-production)
  - [Small-Peers-Only Deployments](#small-peers-only-deployments)
  - [Permissions](#permissions)
  - [Certificate Revocation (SDK 5.1+)](#certificate-revocation-sdk-51)
  - [Controlling Incoming Connections](#controlling-incoming-connections)
  - [Input Validation and Query Parameters](#input-validation-and-query-parameters)
  - [Data at Rest](#data-at-rest)
  - [Webhook Security](#webhook-security)
  - [Security Checklist](#security-checklist)
- [Testing Strategies](#testing-strategies)
  - [A Test Helper for a Local Store](#a-test-helper-for-a-local-store)
  - [Testing Merge-Sensitive Writes](#testing-merge-sensitive-writes)
  - [Testing Deletion and Soft Delete](#testing-deletion-and-soft-delete)
  - [Testing Observer Lifecycle](#testing-observer-lifecycle)
  - [Testing Subscription Rules](#testing-subscription-rules)
  - [Validating DQL in Tests](#validating-dql-in-tests)
  - [Testing on Multiple Devices](#testing-on-multiple-devices)
- [Anti-Pattern Checklist](#anti-pattern-checklist)
  - [Critical (data loss, wrong results, crashes, security)](#critical-data-loss-wrong-results-crashes-security)
  - [High (sync cost, memory, performance)](#high-sync-cost-memory-performance)
  - [Medium (maintainability)](#medium-maintainability)
- [Quick Reference](#quick-reference)
  - [DO](#do)
  - [Common Code Shapes](#common-code-shapes)
- [Glossary](#glossary)
- [References](#references)
- [Disclaimer](#disclaimer)

---

## Understanding Ditto

### What Is Ditto?

Ditto is an **offline-first edge sync platform**. The **Ditto Edge SDK** embeds a local document database in your application and keeps it in sync with other devices, whether or not an internet connection is available.

- **Small Peers**: Every instance of the SDK embedded in an application is a Small Peer. Small Peers are usually mobile or edge devices, but a Small Peer can also run on a desktop or a server.
- **Peer-to-peer mesh**: Small Peers discover each other and sync directly over Bluetooth LE, peer-to-peer Wi-Fi (AWDL on Apple platforms, Wi-Fi Aware on Android), and the local network (LAN). Together they form a mesh that keeps working without any infrastructure.
- **Ditto Server (formerly Big Peer)**: An optional cluster, hosted by Ditto or run by you, that Small Peers reach over WebSocket when they have connectivity. It connects separate meshes, handles authentication, and integrates with backend systems.
- **Conflict-free merging**: Documents are stored as CRDTs (Conflict-free Replicated Data Types). Changes made independently on different devices merge deterministically when the devices reconnect, without a central coordinator.

```text
  Ditto Server (optional, over WebSocket)
          |                 |
     Small Peer A      Small Peer D
       /      \             |
 Small Peer B--Small Peer C  Small Peer E
   (Bluetooth LE, P2P Wi-Fi, LAN mesh)
```

### Key Characteristics

**Offline-first operation**
- The local database is always readable and writable, with or without connectivity.
- Writes are committed locally first and synced when a connection to another peer or to Ditto Server becomes available.
- Sync is incremental: peers exchange only the changes the other side has not seen yet.

**Distributed synchronization**
- No server is required for peers to sync with each other. Ditto Server is optional.
- Each device decides what it wants to receive by registering **subscriptions**. Devices in the same mesh can relay data to each other, but a device only stores and forwards the documents that match its own subscriptions, so give devices that relay data subscriptions that cover what the devices behind them need (see [Multi-hop relay](#multi-hop-relay)).
- Multiple transports are used at the same time, and the SDK chooses connections automatically.

**Automatic conflict resolution**
- Concurrent edits are merged at the field level according to each field's CRDT type, not by replacing whole documents.
- The data model you choose (maps, registers, counters, separate documents) determines how concurrent edits combine. See [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior).

**Capacity**
- A device running the SDK, such as a mobile device, is designed to handle up to about 2 GB of key-value data and tens of thousands of documents in a collection. Actual limits depend on data shape, query complexity, and performance requirements.

### Terminology

The terms below are used throughout this guide. The [Glossary](#glossary) at the end defines further terms.

| Term | Meaning |
|---|---|
| **Database ID** | The UUID that identifies a Ditto database. All peers that sync together use the same Database ID. Copy it from the Ditto Portal (or choose your own UUID for small-peers-only deployments). |
| **Small Peer** | An instance of the Ditto SDK embedded in an application. |
| **Ditto Server** | The optional server-side cluster (formerly called Big Peer) that Small Peers connect to over WebSocket. |
| **Collection** | A named group of documents, similar to a table. Collections do not need to be created in advance. |
| **Document** | A JSON-like object identified by its `_id` field. Each field is merged according to its CRDT type. |
| **Subscription** | A `SELECT * FROM <collection> [WHERE ...]` query registered with `ditto.sync.registerSubscription()`. It tells connected peers which documents to send to this device. |
| **Store observer** | A DQL query registered with `ditto.store.registerObserver()` that delivers new results whenever matching data in the local store changes. |
| **Tombstone** | The marker left behind by `DELETE` so that the deletion syncs to other peers. Tombstones are removed after a TTL (7 days by default on Small Peers, set with `TOMBSTONE_TTL_HOURS`; see [Tombstone TTL and reaping](#tombstone-ttl-and-reaping)). |
| **Eviction** | Removing documents from the local store only (`EVICT`). Eviction does not sync to other peers. |
| **Mesh** | The network of peers connected to each other over peer-to-peer transports, optionally bridged to Ditto Server. |

### Core Principles

#### 1. Queries read the local store only

`ditto.store.execute()` and store observers never contact other peers. They return whatever is in the local store at that moment, so they work offline and return quickly, but they only see data that has already synced to the device.

#### 2. Subscriptions decide what data syncs to a device

A device receives a document only if one of its subscriptions matches it. Register subscriptions for the data the device needs, keep them stable, and filter further with local queries.

```dart
// Tells connected peers to send matching documents to this device.
// Register it once (for example at startup), not before every query, and
// keep the returned object so you can cancel the subscription later.
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE storeId = :storeId',
  arguments: {'storeId': 'store-1'},
);

// Reads only what has already arrived in the local store.
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE storeId = :storeId AND status = :status',
  arguments: {'storeId': 'store-1', 'status': 'open'},
);
debugPrint('Open orders on this device: ${result.items.length}');
```

See [Sync and Subscriptions](#sync-and-subscriptions) for subscription design.

#### 3. Design for offline-first

Assume that any device can be disconnected for a long time and keep working. Write locally, show local data immediately, and let sync catch up. Do not block the UI waiting for a server response, and do not assume that a write has reached other devices just because it succeeded locally.

#### 4. Conflicts are resolved automatically by the data model you choose

Multiple devices will modify the same documents while disconnected. Ditto always merges the changes without errors, but whether the result is what your users expect depends on your data model:

**✅ DO:**
- Update individual fields instead of rewriting whole documents.
- Use maps keyed by ID (not arrays) for collections of sub-items that several devices edit.
- Use counters for values that several devices increment.
- Think through what should happen when two devices edit the same field at the same time.

**❌ DON'T:**
- Assume a single writer for shared data.
- Replace entire documents or arrays when only one part changed.

**Why:** Each field type has defined merge semantics (for example, with the default `DQL_STRICT_MODE = false`, objects merge per field, while scalars and arrays use last-writer-wins). Choosing the right type for each field is what prevents lost updates. See [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior) and [Data Modeling](#data-modeling).

---

## SDK Setup and Lifecycle

### Requirements

Ditto SDK 5.1.0 for Flutter (`ditto_live` 5.1.0) has the following requirements:

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
  ditto_live: 5.1.0   # or ^5.1.0 to accept compatible 5.x updates
```

**Platform setup**: Peer-to-peer sync needs platform permissions and configuration, such as Bluetooth and local network usage descriptions in `Info.plist` on iOS and macOS, and Bluetooth, Wi-Fi, and nearby-device permissions in `AndroidManifest.xml` on Android. Follow the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter) for the current list, and request runtime permissions (for example with the `permission_handler` package) before starting sync.

**Flutter Web limitations**:
- Data is stored **in memory only** and is lost when the page reloads.
- Sync works **only over WebSocket** with Ditto Server. Peer-to-peer transports are not available, and `setOfflineOnlyLicenseToken()` and `setAllPeerToPeerEnabled()` have no effect.
- The in-browser store does not support indexes. Skip `CREATE INDEX` on the Web, for example with `if (!kIsWeb)` from `package:flutter/foundation.dart` (or `Ditto.currentPlatform != SupportedPlatform.web`).
- Only the default Flutter Web build mode is supported, and the development server must be restarted after source changes.
- The WebAssembly assets can be served from a CDN with `Ditto.init(wasmUrl: ..., wasmShimUrl: ...)`.

### Initializing Ditto

#### DittoConfig

A Ditto instance is created from an immutable `DittoConfig`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `databaseID` | `String?` | All-zero UUID | Your Database ID. It must be a valid UUID. Do not rely on `Ditto.open()` to reject an invalid value; check that no placeholder is left in your configuration. |
| `connect` | `DittoConfigConnect` | `DittoConfigConnectSmallPeersOnly()` | `DittoConfigConnectServer(url: ...)` or `DittoConfigConnectSmallPeersOnly(privateKey: ...)`. |
| `persistenceDirectory` | `String?` | `null` | `null` uses `ditto-<databaseID>` inside `Ditto.defaultRootDirectory` (the app documents directory). A relative path is resolved against the same directory. |

There are two connection modes:

| Mode | Use it when | Authentication | Encryption in transit |
|---|---|---|---|
| `DittoConfigConnectServer(url: ...)` | Devices sync through Ditto Server (and with each other) | Required: set an expiration handler and log in (see [Authentication](#authentication)) | TLS |
| `DittoConfigConnectSmallPeersOnly(privateKey: key)` | Devices sync only with each other using a shared key | Shared key: every peer that holds the key is trusted (no server) | TLS 1.3 |
| `DittoConfigConnectSmallPeersOnly()` | Local store tests, and development with an offline license token | **None**: any device with the SDK, the Database ID, and a license token can connect | **Not to rely on**: the SDK documents it as unencrypted (see below) |

**✅ DO:**
- Copy the Server URL from the Ditto Portal exactly as shown. Do not build it from the Database ID.
- Use `DittoConfigConnectSmallPeersOnly(privateKey: ...)` with a provisioned key for production small-peers-only deployments. The key is a base64-encoded P-256 (prime256v1) private key in PKCS#8 DER format, and `Ditto.open()` throws if the key is not valid.
- Obtain an **offline license token** from Ditto for small-peers-only deployments and set it with `ditto.setOfflineOnlyLicenseToken(token)` before calling `ditto.sync.start()`.

**❌ DON'T:**
- Ship `DittoConfigConnectSmallPeersOnly()` without a `privateKey` to production. Peers do not authenticate each other in that mode: any device that runs the SDK with the same Database ID (and a valid offline license token) can connect, read, and write. The SDK's API documentation describes the mode as using no encryption in transit; in SDK 5.1.0 tests over TCP the traffic was still TLS-wrapped, but without a secret, so it gives no protection you can rely on.
- Hardcode the shared key in the app binary (see [Small-Peers-Only Deployments](#small-peers-only-deployments)).

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

For generating, distributing, and storing the shared key, see [Small-Peers-Only Deployments](#small-peers-only-deployments).

#### Ditto.open, Ditto.openSync, and Ditto.init

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

#### One instance per persistence directory

Only one `Ditto` instance can use a persistence directory at a time, and only one app can use a database at the same time. Open Ditto once at app start, share the instance (for example through your app's dependency injection or a service object), and close it only when the app no longer needs it.

> **Note (SDK 5.1.0):** In the Flutter SDK, calling `Ditto.open()` on a persistence directory that is already open may never complete instead of throwing. Do not open a directory that is already open; share the instance that is already open instead.

**✅ DO:**
- Open Ditto once and pass the instance to the parts of the app that need it.
- Guard against concurrent opens by sharing a single in-flight `Future`.
- In debug builds, use a randomized `persistenceDirectory` to avoid lock conflicts after a Flutter hot restart, as described in the [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter). Each hot restart then starts with an empty local store. Keep a fixed directory in release builds, where the local data must survive restarts. Hot reload works normally.

**❌ DON'T:**
- Open a new instance per screen or per request.
- Open the same directory twice, or reopen it before `close()` has completed.
- Read or write files inside the persistence directory yourself.

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

#### Complete app startup

The following example shows the recommended order: initialize, configure logging, open, set the authentication handler, apply system parameters, create indexes, register long-lived subscriptions, and start sync.

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

    // 3. Open the single shared instance.
    final ditto = await Ditto.open(
      const DittoConfig(
        databaseID: 'YOUR_DATABASE_ID',
        // Copy the URL from the Ditto Portal exactly as shown.
        connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
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
          showError(error); // e.g. fetchAuthToken() failed; never rethrow here
        }
      });

      // 5. System parameters are not persisted: apply them on every open,
      //    before sync starts.
      if (enableStrictMode) {
        await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = true');
      }

      // 6. Create the indexes your queries need before queries and observers
      //    run. Indexes persist, and IF NOT EXISTS makes this safe on every
      //    start. The in-browser store on the Web does not support indexes.
      if (!kIsWeb) {
        await ditto.store.execute(
          'CREATE INDEX IF NOT EXISTS idx_orders_storeId ON orders (storeId)',
        );
      }

      // 7. Register long-lived subscriptions, then start sync.
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

Step 6 creates one index as an example; see [Creating Indexes](#creating-indexes) for which indexes to create.

### Authentication

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

**Why:** Credentials are issued by Ditto Server after your webhook validates the token (see [Authentication in Production](#authentication-in-production)), and they expire after the `expirationSeconds` your webhook returns. The handler is the single place where the SDK asks your app for a new token, so it must be reliable and must not crash.

**Logging out**: `await ditto.auth.logout()` clears the credentials and **stops sync**. Call `ditto.sync.start()` again after the next successful login if the device should resume syncing. `ditto.auth.status` exposes `isAuthenticated` and `userID`.

### Applying System Parameters

System parameters (`ALTER SYSTEM SET ...`) change SDK behavior at runtime. **They are kept in memory only and are not persisted**: after the app restarts, or after closing and reopening Ditto, every parameter is back at its default value.

**✅ DO:**
- Apply your system parameters every time you open Ditto, after `Ditto.open()` and before `ditto.sync.start()`, running queries, or registering observers (subscriptions may be registered first).
- Keep them in one function that runs as part of startup.
- Read the current value with `SHOW <parameter>` when you need to confirm a setting.

**❌ DON'T:**
- Run `ALTER SYSTEM` once (for example in a migration) and assume it stays in effect.
- Change parameters such as `DQL_STRICT_MODE` after sync has started or after queries and observers have run.

`DQL_STRICT_MODE` defaults to `false`. Apply it only if your app deliberately opts into strict mode; see [Strict Mode](#strict-mode) for the trade-offs.

```dart
// ✅ GOOD: Apply settings on every open, before sync starts.
Future<void> applySystemParameters(
  Ditto ditto, {
  required bool strictMode, // true only for apps that opt into strict mode
}) async {
  if (strictMode) {
    await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = true');
  }

  // Confirm the effective value. SHOW returns one row keyed by the
  // lowercase parameter name.
  final result = await ditto.store.execute('SHOW DQL_STRICT_MODE');
  debugPrint('dql_strict_mode = ${result.items.first.value['dql_strict_mode']}');
}
```

To restore a default, use `ALTER SYSTEM RESET <parameter>`. To list everything, use `SHOW ALL` (optionally filtered, for example `SHOW ALL LIKE 'dql%'`). The parameters most relevant to app developers are listed in [System Parameters Reference](#system-parameters-reference); others are described in the section that uses them.

### Starting and Stopping Sync

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

### Resource Cleanup and Shutdown

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

`ditto.close()` behavior:
- **Idempotent**: calling it twice is safe. Use `ditto.isClosed` to check.
- **Stops sync** and releases observers, subscriptions, and other resources. Afterwards, observers and subscriptions report `isCancelled == true`, `cancel()` and `stop()` do nothing, and every other API call throws `DittoClosedException`.
- **Does not wait** for your pending work. In-flight `execute()` calls and transactions can fail with `DittoClosedException`, so await your own pending work before closing.
- **Resets `DittoLogger.customLogCallback`** to `null` for the whole process. If you reopen Ditto, set it again after `Ditto.init()` and before `Ditto.open()` (see [Forwarding logs to your own pipeline](#forwarding-logs-to-your-own-pipeline)).
- **Does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2`**: an `await for` loop over it does not end when Ditto closes, and `cancel()` does nothing once Ditto is closed. Cancel observers and your `StreamSubscription`s (or break out of the loop) before closing.

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
    await ditto.close(); // stops sync; does not wait for in-flight queries
  }
}
```

### Transport Configuration

A new Ditto instance enables the peer-to-peer transports that are stable on the current platform (Bluetooth LE, LAN, and AWDL or Wi-Fi Aware). When you connect with `DittoConfigConnectServer`, the Server URL is used automatically; you do not need to add it to the transport configuration.

`TransportConfig` is immutable. Change it with `ditto.updateTransportConfig()`, which gives you a builder initialized with the current configuration.

**✅ DO:**
- Use `updateTransportConfig()` and change only the settings you need.
- Enable or disable all peer-to-peer transports at once with `setAllPeerToPeerEnabled()`, or individual transports through `peerToPeer`.
- Observe transport conditions to detect missing permissions or disabled radios.

**❌ DON'T:**
- Build a `TransportConfig()` from scratch and assign it: a new `TransportConfig` has **every transport disabled**, including the peer-to-peer transports that a default instance enables.
- Treat `global.syncGroup` as a security boundary. It is an optimization only: in tests, devices in different sync groups still synced when they were connected explicitly (`connect.tcpServers` or `TRANSPORTS_DISCOVERED_PEERS`).

```dart
// ✅ GOOD: Adjust the current configuration with the builder.
void configureTransports(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.setAllPeerToPeerEnabled(true); // BLE, LAN, AWDL / Wi-Fi Aware
    config.peerToPeer.bluetoothLE.isEnabled = false; // e.g. LAN and P2P Wi-Fi only
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

> **Note (SDK 5.1.0):** A device accepts a limited number of connections per transport. For TCP, the limit is 6 by default (system parameter `MESH_CHOOSER_MAX_WLAN_CONNECTIONS`). In tests with a TCP hub and 8 clients, the hub accepted 6, and the other 2 received no data at all. No API reported this; only the log showed a `WARN` line, `failed to connect to peer error=... at capacity for this transport`. Rejected devices retry with an increasing backoff. Ditto does not document the parameter, so treat the value as subject to change.
>
> If more than six devices connect to one hub, raise the limit **on the hub** after `Ditto.open` and **before** `ditto.sync.start()`. Raising it while sync was already running did not let the rejected clients in within 60 s.

```dart
// ✅ GOOD: A hub that serves up to 12 TCP clients. Apply on every open,
// before ditto.sync.start() (system parameters are not persisted).
Future<void> startHub(Ditto ditto) async {
  await ditto.store.execute(
    'ALTER SYSTEM SET MESH_CHOOSER_MAX_WLAN_CONNECTIONS = 12',
  );
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = '[::]'
      ..port = 4040;
  });
  ditto.sync.start();
}
```

Configuration changes are applied asynchronously while sync is running, and invalid values do not throw: an invalid `connect.tcpServers` entry or listen address only produces a log line (for example `Failed to start TCP server error=Bind address could not be parsed`). You can also point devices at a known peer with the `TRANSPORTS_DISCOVERED_PEERS` system parameter, which can be set before or after `ditto.sync.start()` and is validated (`type` is optional and must be `'force'` or `'candidate'`). It works only while the LAN transport (`peerToPeer.lan`) is enabled on the device that sets it, which is the default; with peer-to-peer transports disabled, the value is stored but nothing connects, so use `connect.tcpServers` instead. Like every system parameter, it is not persisted, so apply it again after each open:

```dart
Future<void> connectToKnownPeer(Ditto ditto) async {
  await ditto.store.execute(
    "ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS = [{'address': 'tcp://192.168.1.10:4040', 'type': 'force'}]",
  );
}
```

**WebSocket sync between Small Peers** (accepting WebSocket connections on the HTTP listener) is **off by default** (`listen.http.websocketSync = false`). Enable it only when you need it and configure TLS (`tlsKeyPath` and `tlsCertificatePath`); without them the listener uses plain HTTP.

#### Diagnosing transport problems (SDK 5.1+)

Because configuration changes do not throw, `ditto.observeTransportConditions()` is the way to see why a transport is not working: missing Bluetooth permissions, Bluetooth or Wi-Fi turned off, no BLE hardware, the app being in the background, mDNS or TCP listen failures, and so on. Call `stop()` on the returned observer when you no longer need it.

On Android, `DittoSyncPermissions` reports which runtime permissions Ditto needs and which are missing. It returns empty lists on other platforms. Request the permissions with a package such as `permission_handler`.

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

#### Multicast (Beta) (SDK 5.1+)

Multicast is an opt-in transport that sends each update once to a multicast group instead of once per connection, which reduces connection overhead in dense deployments. It is a private beta feature: **use it only in coordination with Ditto support**. It is configured through `peerToPeer.multicastBeta`, requires additional platform entitlements and permissions (for example the multicast entitlement on iOS and `CHANGE_WIFI_MULTICAST_STATE` on Android), is not available on the Web or on Windows, and changes made while sync is active take effect only after sync is stopped and started again.

### Presence

`ditto.presence` shows which peers this device can see and how it is connected to them, which is useful for connection indicators and diagnostics.

- `ditto.presence.observe((graph) { ... })` returns a `PresenceObserver`. The callback is called with the current graph shortly after `observe()` returns (asynchronously), and again whenever peers appear, disappear, or change their connections. Updates are batched: in tests, a change reached the callback after about 0.5–1 second, and one callback can cover several changes. Call `stop()` on the observer when you no longer need it.
- `graph.localPeer` describes this device, and `graph.remotePeers` is a `Set<Peer>` of the other known peers, including peers that are reachable only through other peers. Each `Peer` has `peerKey`, `deviceName`, `isConnectedToDittoServer`, `connections`, and `peerMetadata`. To tell direct neighbors apart, check whether one of a peer's `connections` has this device's `peerKey` as `peer1` or `peer2`.
- `ditto.presence.graph` returns the current graph once, without observing.
- `ditto.presence.peerMetadata` sets metadata for this device (a JSON object of at most 4096 bytes when encoded; larger values throw). It reaches every peer in the mesh, but a peer that has just appeared can show empty `peerMetadata` until its metadata arrives.

**✅ DO:**
- Stop presence observers when the screen or feature that uses them goes away.
- Keep peer metadata small and non-sensitive, such as a role or a display name.
- Set peer metadata once at startup (for example `ditto.presence.peerMetadata = {'role': 'cashier'};`), not from individual screens.

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

  @override
  void initState() {
    super.initState();
    _presence = widget.ditto.presence.observe((graph) {
      if (!mounted) return;
      setState(() => _peers = graph.remotePeers.toList());
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
              subtitle: Text(peer.isConnectedToDittoServer
                  ? 'Connected to Ditto Server'
                  : '${peer.connections.length} connections'),
            ),
        ],
      );
}
```

### Platform Differences

The concepts are the same on every platform, but some APIs behave differently. Keep these differences in mind when you port code or read samples for another SDK:

| Topic | Flutter | JavaScript | Swift | Kotlin |
|---|---|---|---|---|
| Create / open | `await Ditto.open(DittoConfig(...))` | `await Ditto.open(new DittoConfig(id, { mode: 'server', url }))`; on the Web, call `await init()` first | `try await Ditto.open(config:)` | `DittoFactory.create(config)` |
| Start sync | `ditto.sync.start()` (`void`, throws on failure) | `ditto.sync.start()` | `try ditto.sync.start()` | `ditto.sync.start()` (throws on failure) |
| Close | `await ditto.close()` | `await ditto.close()` | No public `close()`; release all references and the instance shuts down when deallocated | `ditto.close()` |
| Login failure | Returns `AuthResponse` with `exception`; does not throw | Returns a result with `error`; does not throw | Reported to the completion handler as `error` | **Throws** |
| Observer backpressure | `registerObserver`: none. `registerObserverV2` (automatic) and `registerObserverWithSignalNext` (manual), both (Experimental) (SDK 5.1+) | `registerObserver` signals the next update when a synchronous handler returns (async handlers are not awaited); use `registerObserverWithSignalNext` for async work | `registerObserver(... handler:)` signals automatically; `handlerWithSignalNext:` is manual | No `signalNext`: suspend handlers and `collect` wait for the handler; `observe` returns a `Flow` |
| Release observers and subscriptions | `cancel()` | `cancel()` | `cancel()` | `close()` |
| Transaction completion | Return a value to commit; throw or return `TransactionCompletionAction.rollback` to roll back | Return a value to commit, or `'rollback'` | Return a value to commit, or `.rollback` | Must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |
| `ditto.store.execute` inside a transaction | Throws `DittoException` | Can deadlock; never do it | Can deadlock; never do it | Can deadlock; never do it |
| Read-write transaction nested inside a read-write transaction | Deadlocks (the SDK does not detect it); never do it | Deadlocks; never do it | Can deadlock; never do it | Can deadlock; never do it |

See [Observing Changes](#observing-changes) and [Transactions](#transactions) for details on each platform's patterns.

---

## DQL Fundamentals

DQL (Ditto Query Language) is the SQL-like language you use to read, write, and observe documents in Ditto. It looks familiar if you know SQL, but it works on schemaless JSON-like documents, distinguishes a missing field from a `null` field, and has Ditto-specific statements for conflict handling, CRDT types, and local eviction.

| Statement | Purpose | Covered in |
|---|---|---|
| `SELECT` | Read documents: projections, aggregates, `GROUP BY`, `ORDER BY`, `LIMIT`, `JOIN` (SDK 5.1+) | [Reading Data with SELECT](#reading-data-with-select) |
| `INSERT` | Create documents, upsert with `ON ID CONFLICT`, seed defaults with `INITIAL DOCUMENTS` | [INSERT and Conflict Handling](#insert-and-conflict-handling) |
| `UPDATE` | Change individual fields with `SET` / `UNSET`, counters with `APPLY` | [UPDATE](#update) |
| `DELETE` / `EVICT` | Delete everywhere (tombstone) / remove from this device only | [Deletion and Storage Management](#deletion-and-storage-management) |
| `CREATE INDEX` / `DROP INDEX`, `EXPLAIN`, `PROFILE`; `ADVISE` (SDK 5.1+) | Indexing and query diagnostics | [Indexing and Query Performance](#indexing-and-query-performance) |
| `ALTER SYSTEM` / `SHOW` | Runtime system parameters | [Applying System Parameters](#applying-system-parameters) |

There is no `CREATE COLLECTION` or `DROP COLLECTION` statement: a collection exists as soon as a document is written to it. <!-- lint-ignore -->

### Where Queries Run

DQL statements always run against the **local store** of the device. Which API you pass a statement to decides what happens with it:

| API (Flutter) | What it does |
|---|---|
| `ditto.store.execute(query, arguments: {...})` | Runs one statement against the local store and returns a `QueryResult`. Never contacts other peers. |
| `tx.execute(query, arguments: {...})` | Same, inside `ditto.store.transaction(...)`. See [Transactions](#transactions). |
| `ditto.store.registerObserver(query, arguments: {...})` | Re-runs a `SELECT` whenever matching local data changes. See [Observing Changes](#observing-changes). |
| `ditto.sync.registerSubscription(query, arguments: {...})` | Tells connected peers which documents this device wants. Only `SELECT * FROM c [WHERE ...]` is accepted. See [Sync and Subscriptions](#sync-and-subscriptions). |

Queries never fetch data from other peers: a `SELECT` sees only documents that were created on this device or that a subscription has already brought to it. See [Core Principles](#core-principles) for how queries and subscriptions work together.

```dart
// ✅ GOOD: A long-lived subscription (owned by an app-level service) brings
// matching documents to this device; execute() reads whatever has arrived so far.
SyncSubscription subscribeToOpenOrders(Ditto ditto) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'open'},
    );

Future<List<Map<String, dynamic>>> loadOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}
```

### Parameters and Literals

#### Always pass values as parameters

Reference values with `:name` placeholders and pass them in `arguments`. Parameter names are case-sensitive (`:Status` and `:status` are different), and a placeholder without a matching argument fails with `Parameter Status was not provided`.

**✅ DO:**
- Use parameters for every value that comes from your app: IDs, user input, dates, limits, whole documents.
- Pass whole documents to `INSERT` as a single parameter: `INSERT INTO orders DOCUMENTS (:order)`.
- Pass arrays for membership tests: `WHERE status IN :statuses`.

**❌ DON'T:**
- Build DQL strings with string interpolation or concatenation.
- Write `IN (:statuses)` with an array parameter. The parentheses turn it into a one-element list whose only element is the array, so nothing matches.

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

// ❌ BAD: The array becomes a single list element, so no document matches
Future<void> findByStatusesWrong(Ditto ditto) async {
  await ditto.store.execute(
    'SELECT * FROM orders WHERE status IN (:statuses)',
    arguments: {'statuses': ['open', 'pending']},
  );
}
```

**Why:**
- **Security**: Interpolated input can change the meaning of the statement (DQL injection).
- **Correctness**: DQL string literals interpret backslash escapes (see below), so user text containing `\` or quotes can be silently altered or break the statement. Parameters keep their exact value and type (an `int` stays an integer, a `bool` stays a boolean).
- **Performance**: The statement text stays identical between calls, so Ditto's shared statement cache can reuse the prepared plan instead of planning the query again.

#### Literals

When you do write values inline (constants such as `'open'`, or examples in the DQL console), these rules apply:

| Literal | Syntax | Notes |
|---|---|---|
| String | `'open'` or `"open"` | Single and double quotes both delimit strings. Double quotes never refer to a field. |
| Escapes in strings | `'line1\nline2'`, `'it\'s'`, `'caf\u00e9'` | JSON escape sequences are interpreted in both quote styles. `'it''s'` (doubled quote) is a syntax error. An unknown escape such as `\q` drops the backslash. A literal backslash must be written `\\`. This changed in 5.1.0: on 5.0.x, `''` was the escape for `'` and backslashes were not interpreted, so string literals written for 5.0.x can fail or change meaning after an upgrade. |
| Identifier | `` `my field` ``, `` `collection` `` | Backticks quote field names, aliases, and collection names that contain special characters or are reserved words. |
| Number | `42`, `-1`, `2.5`, `1e3` | `1e3` is a float. Integer division stays integer: `5 / 2` is `2`, `5.0 / 2` is `2.5`. |
| Hexadecimal | `0xFF` | Integer constant (`255`). |
| Boolean / null | `true`, `FALSE`, `null` | Case-insensitive keywords. |
| Array | `[1, 'a']` | JSON-style. |
| Object | `{'status': 'open', 'total': 10}` | Every key must be a quoted string (see below). |

```sql
SELECT 'it\'s' AS a, "double quoted" AS b, `my field` AS c, 0xFF AS d
FROM orders
```

Backslashes are interpreted twice when the statement is written inside a Dart string: first by Dart, then by DQL. This is another reason to pass text as a parameter.

```dart
// ✅ GOOD: The path is passed as data and stored exactly as given
Future<void> saveExportPath(Ditto ditto) async {
  await ditto.store.execute(
    'UPDATE settings SET exportPath = :path WHERE _id = :id',
    arguments: {'id': 'device', 'path': r'C:\temp\exports'},
  );
}
```

#### Quote every key in inline object literals

Object literals written inside a statement must use quoted keys. Unquoted keys fail in `INSERT` and, worse, are silently evaluated as field references in `SELECT` (usually producing an empty object).

<!-- expect-error -->
```sql
-- ❌ BAD: Unquoted keys are rejected: "Cannot convert to a literal"
INSERT INTO orders DOCUMENTS ({_id: 'order-1', status: 'open'})
```

```sql
-- ❌ BAD: No error, but o is returned as {} (the unquoted key is evaluated as a field reference)
SELECT {a: 1} AS o FROM system:dual
```

```sql
-- ✅ GOOD: Quoted keys
INSERT INTO orders DOCUMENTS ({'_id': 'order-1', 'status': 'open'})

SELECT {'a': 1} AS o FROM system:dual
```

The recommended form is to avoid inline objects entirely and pass the document as a parameter (`DOCUMENTS (:order)`).

#### Reserved words

DQL keywords cannot be used as bare identifiers. A collection named `collection` is the most common trap: `SELECT * FROM collection` is a parser error (`expected identifier`). Aliases such as `all` fail the same way.

**✅ DO:**
- Choose collection and field names that are not DQL keywords (`orders`, `tasks`, `createdAt`).
- Quote an existing reserved name with backticks if you cannot rename it: ``SELECT * FROM `collection` ``.

The full keyword list is in the [DQL identifiers, paths, strings, and keywords](https://docs.ditto.live/dql/ids-paths-strings-keywords) reference.

#### Comments

Statements may contain `-- line comments` and `/* block comments */`. Comments that start with `/*+` or `--+` are query directives (see [Indexing and Query Performance](#indexing-and-query-performance)), so do not use those prefixes for ordinary comments.

### MISSING and NULL

Ditto documents are schemaless, so a field can be absent from a document (**MISSING**) or present with the value `null` (**NULL**). DQL treats them differently, and most surprises come from the fact that a comparison involving a missing or null field is neither true nor false. In a `WHERE` clause such a row is simply not returned.

Results for a field `isDeleted` holding `true`, `false`, `null`, or missing:

| `WHERE` expression | `true` | `false` | `null` | missing |
|---|---|---|---|---|
| `isDeleted = false` | | ✓ | | |
| `isDeleted != true` / `NOT isDeleted` | | ✓ | | | <!-- lint-ignore -->
| `coalesce(isDeleted, false) = false` | | ✓ | ✓ | ✓ |
| `isDeleted IS NULL` | | | ✓ | |
| `isDeleted IS NOT NULL` | ✓ | ✓ | | ✓ | <!-- lint-ignore -->
| `isDeleted IS MISSING` | | | | ✓ |
| `isDeleted IS NOT MISSING` | ✓ | ✓ | ✓ | |
| `isDeleted IS NOT MISSING AND isDeleted IS NOT NULL` | ✓ | ✓ | | | <!-- lint-ignore -->
| `ismissingornull(isDeleted)` | | | ✓ | ✓ |

Note that `IS NOT NULL` is true for a missing field, and that `!= true` drops both `null` and missing rows. <!-- lint-ignore -->

**✅ DO:**
- Filter optional booleans with `coalesce(field, default)`: `coalesce(isDeleted, false) = false`.
- Test for field existence with `IS MISSING` / `IS NOT MISSING`.
- Test "has a real value" with `field IS NOT MISSING AND field IS NOT NULL`. <!-- lint-ignore -->
- Remove a field with `UNSET` (see [UPDATE](#update)) when you want it to become missing; writing `null` keeps the field present with a null value.

**❌ DON'T:**
- Use `field != true` or `NOT field` to mean "false or not set". <!-- lint-ignore -->
- Use `IS NOT NULL` to check that a field exists. <!-- lint-ignore -->

```dart
// ✅ GOOD: Treat a missing or null isDeleted flag as "not deleted"
Future<List<Map<String, dynamic>>> activeTasks(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false ORDER BY createdAt',
  );
  return result.items.map((item) => item.value).toList();
}

// ❌ BAD: Tasks that never had isDeleted set (or have null) are silently excluded
Future<List<Map<String, dynamic>>> activeTasksWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt',
  );
  return result.items.map((item) => item.value).toList();
}
```

**Why:** Documents written by older app versions, by other platforms, or created before a field was introduced often lack the field entirely. A filter that ignores MISSING hides those documents without any error. The [Soft Delete](#soft-delete) pattern depends on getting this right.

Related behavior:
- In projections, an expression that evaluates to MISSING is omitted from the result row (the key is absent from `item.value`), while `null` appears as a `null` value.
- Comparing values of different types, including with `=` and `!=` (`1 = 'a'`, `1 != 'a'`, `1 < 'a'`), also evaluates to MISSING, as do operators applied to the wrong types (`'a' || 1`). Integers and floats compare normally (`1 = 1.0` is `true`). <!-- lint-ignore -->
- `ORDER BY` sorts `null` and missing values after all other values in ascending order (see [ORDER BY](#order-by)).
- Aggregates other than `COUNT` return MISSING, not `0`, over zero matching documents (see [Aggregates](#aggregates)).

### Working with Query Results

`ditto.store.execute` returns a `QueryResult`:

| Member (Flutter) | Type | Description |
|---|---|---|
| `items` | `Iterable<QueryResultItem>` | The result rows. An `Iterable`, not a `List`: use `map`, `first`, `length`, or `toList()`. |
| `item.value` | `Map<String, dynamic>` | The row decoded into Dart values. Decoded on first access and cached on that item object. |
| `item.jsonString` | `String` | The row as a JSON string (a property, not a method). |
| `item.cborBytes` | `Uint8List` | The row as CBOR bytes (a property, not a method). |
| `mutatedDocumentIDs()` | `List<dynamic>` | IDs of documents changed by an `INSERT` / `UPDATE` / `DELETE` / `EVICT`. A method that builds a new list on every call; call it once and keep the list. IDs are raw values (a `String`, or a `Map` for composite IDs). |
| `commitID` | `int?` | ID of the local commit for a mutating statement; `null` for reads. Inside a transaction it is only available after the transaction commits. |

In the JavaScript SDK, the `QueryResult` equivalents are `items[i].value`, `items[i].jsonString()` (a method), and `mutatedDocumentIDsV2()`. Arguments are passed as the second positional parameter: `ditto.store.execute(query, { status: 'open' })`. <!-- lint-ignore -->

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

#### Materialize values, then let the result go

**✅ DO:**
- Convert each row to a `Map` or to your own model class once, then work with those objects.
- Iterate `items` once. Each pass over `items` creates new `QueryResultItem` wrappers, so `result.items.first.value` evaluated twice decodes the row twice.
- Keep only the data you need; let the `QueryResult` go out of scope.

**❌ DON'T:**
- Store `QueryResult` or `QueryResultItem` objects in state, caches, or across observer callbacks. They reference native memory that is released only when the Dart object is garbage-collected.

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

#### Large results

Every row of a `SELECT` is materialized in the result. On mobile devices:

- **Project** only the fields you need (`SELECT _id, title, status ...`). Projections do not change what syncs, but they reduce decoding work and memory.
- **Filter** in `WHERE` rather than in Dart.
- **Page** with `ORDER BY ... LIMIT` (see [LIMIT and OFFSET](#limit-and-offset)).
- **Count** with `SELECT COUNT(*)` instead of loading documents to call `.length`.
- **Check existence** with `LIMIT 1`.

---

## Reading Data with SELECT

```text
SELECT [DISTINCT] projection
FROM collection [[AS] alias] [USE IDS ...]
  [[INNER | LEFT [OUTER] | RIGHT [OUTER]] JOIN collection2 [[AS] alias2] ON condition] ...
[WHERE condition]
[GROUP BY expression, ...]
[HAVING condition]
[ORDER BY expression [ASC | DESC], ...]
[LIMIT n]
[OFFSET m]
```

### Projections and Aliases

| Projection | Example | Result |
|---|---|---|
| All fields | `SELECT * FROM orders` | Whole documents |
| Fields | `SELECT _id, status FROM orders` | Only those fields |
| Expressions with aliases | `SELECT _id, total * 1.1 AS gross FROM orders` | Computed field `gross` |
| All fields plus expressions | `SELECT orders.*, total * 1.1 AS gross FROM orders` | Qualify `*` with the collection name or alias |
| All fields except some | `SELECT orders.*, MISSING notes FROM orders` | Every field but `notes` |

**✅ DO:**
- Select only the fields you need in `execute` and observers.
- Give every computed expression an explicit alias with `AS`. Without one, Ditto names the column after its position in the projection list, such as `($2)` for the second element.
- Qualify `*` when combining it with other projections: `SELECT orders.*, ...`. An unqualified `SELECT *, total * 2 AS doubled` fails with `unqualified * with other projection elements is not supported`.

```dart
// ✅ GOOD: Only the fields the list screen shows, with readable aliases
Future<List<Map<String, dynamic>>> orderSummaries(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, customerName, total * 1.1 AS totalWithTax '
    'FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}
```

**Why:** A projection shapes the local result only. Synchronization works on whole documents and is controlled by subscriptions, which always use `SELECT *`. Smaller projections mean less decoding and memory, and an index that contains every projected field can answer the query without fetching documents (see [Indexing and Query Performance](#indexing-and-query-performance)).

### DISTINCT

`SELECT DISTINCT` removes duplicate result rows. To guarantee uniqueness Ditto keeps every distinct row it has produced in memory, so memory grows with the number of unique rows.

**✅ DO:**
- Use `DISTINCT` on a few low-cardinality fields: `SELECT DISTINCT status FROM orders`.

**❌ DON'T:**
- Use `DISTINCT` together with `_id` or `*`. Every document is already unique, so it only adds memory use.

```sql
SELECT DISTINCT status FROM orders ORDER BY status
```

### Aggregates

| Function | Result |
|---|---|
| `COUNT(*)` | Number of rows |
| `COUNT(expr)` | Number of rows where `expr` is **not** `null`, missing, **or `false`** |
| `COUNT(DISTINCT expr)` | Number of distinct values of `expr`, with the same exclusions |
| `SUM(expr)` / `AVG(expr)` | Sum / average of numeric values; other types are ignored |
| `MIN(expr)` / `MAX(expr)` | Smallest / largest value in Ditto's type order |
| `MEDIAN(expr)` | Positional median of numeric values |
| `MID(expr)` | `(MIN + MAX) / 2`, the midpoint between the extremes (not the median) |

`SUM`, `AVG`, `MEDIAN`, and `MID` also accept `DISTINCT`.

`COUNT` behavior on a field `isPaid` holding `true`, `false`, `null`, missing, `true`:

| Expression | Result |
|---|---|
| `COUNT(*)` | 5 |
| `COUNT(isPaid)` | 2 (only `true`) |
| `COUNT(isPaid = false)` | 1 |

**✅ DO:**
- Use `COUNT(*)` to count documents. A full-collection `COUNT(*)` is answered from a dedicated fast path (SDK 5.1+).
- Count values that exist with `COUNT(field IS NOT MISSING)` when the field can be `false`.
- Wrap aggregates that may see zero rows: `ifmissing(SUM(total), 0)`. With no matching rows, every aggregate other than `COUNT` (`SUM`, `AVG`, `MIN`, `MAX`, `MEDIAN`, `MID`) returns MISSING (the alias is absent from the row), while `COUNT(*)` and `COUNT(expr)` return `0`.
- Use `LIMIT 1` to check whether at least one matching document exists.

**❌ DON'T:**
- Use `COUNT(field)` to count "documents that have the field" when the field is a boolean: `false` values are not counted.
- Use `MID` when you need the median.

```dart
// ✅ GOOD: Aggregates with explicit aliases and a default for empty sets
Future<Map<String, dynamic>> orderStats(Ditto ditto, String customerId) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(*) AS orderCount, '
    'ifmissing(SUM(total), 0) AS revenue, '
    'ifmissing(AVG(total), 0) AS averageOrder '
    'FROM orders WHERE customerId = :customerId',
    arguments: {'customerId': customerId},
  );
  return result.items.first.value;
}

// ✅ GOOD: Existence check stops at the first match
Future<bool> hasOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE status = :status LIMIT 1',
    arguments: {'status': 'open'},
  );
  return result.items.isNotEmpty;
}
```

**Why:** Aggregates must process every matching document before they return (they act as a "dam" in the query pipeline). Memory grows with the number of groups, not with the number of documents, but the work still grows with the number of matching documents. Keep `WHERE` selective and avoid running expensive aggregates in observers that fire frequently.

### GROUP BY and HAVING

Every non-aggregate projection must be a `GROUP BY` key. `GROUP BY` and `HAVING` **cannot reference projection aliases**: repeat the expression instead. `ORDER BY` can use aliases.

<!-- expect-error -->
```sql
-- ❌ BAD: GROUP BY uses the alias "day":
-- Projection "day" must depend only on group keys or aggregates
SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue
FROM orders
GROUP BY day
```

<!-- expect-error -->
```sql
-- ❌ BAD: HAVING uses the alias "revenue":
-- HAVING clause terms must depend only on group keys or aggregates
SELECT customerId, SUM(total) AS revenue
FROM orders
GROUP BY customerId
HAVING revenue > 1000
```

```sql
-- ✅ GOOD: Repeat the expressions in GROUP BY and HAVING; ORDER BY may use aliases
SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue
FROM orders
WHERE createdAt >= :since
GROUP BY date_format(createdAt, 'YYYY-MM-DD')
HAVING SUM(total) > 1000
ORDER BY day
```

```dart
// ✅ GOOD: Revenue per customer, highest first
Future<List<Map<String, dynamic>>> revenueByCustomer(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT customerId, COUNT(*) AS orderCount, SUM(total) AS revenue '
    'FROM orders WHERE status = :status '
    'GROUP BY customerId '
    'HAVING COUNT(*) >= :minOrders '
    'ORDER BY revenue DESC',
    arguments: {'status': 'completed', 'minOrders': 2},
  );
  return result.items.map((item) => item.value).toList();
}
```

### ORDER BY

Results have no guaranteed order unless you specify `ORDER BY`. The default direction is `ASC`. When values of different types are sorted together, the ascending order is:

`false` < `true` < numbers < binary < strings < arrays < objects < `null` < missing

`DESC` reverses the whole sequence, so documents with a missing sort field come **first** in descending order.

**✅ DO:**
- Add `ORDER BY` to every observer query whose order matters in the UI. Observers do not guarantee a stable order without it.
- Add a unique tie-breaker such as `_id` when the sort key can repeat: `ORDER BY createdAt DESC, _id`.
- Store sortable values in one consistent type (for example, all timestamps as ISO-8601 UTC strings produced by one helper with a fixed precision; see [Timestamps](#timestamps)).

**❌ DON'T:**
- Rely on insertion order.
- Expect `ORDER BY status = 'urgent'` to put matching documents first in ascending order: `false` sorts before `true`. Use `DESC` (and keep in mind that missing values then come first) or an explicit `CASE`.

```sql
-- Urgent tasks first, then by due date
SELECT * FROM tasks
WHERE coalesce(isDeleted, false) = false
ORDER BY CASE WHEN priority = 'urgent' THEN 0 ELSE 1 END, dueAt, _id
```

Sorting large result sets costs memory and time unless an index provides the order; see [Index Usage Rules](#index-usage-rules).

### LIMIT and OFFSET

`LIMIT` and `OFFSET` accept parameters. Always combine them with `ORDER BY`, otherwise the page contents are not well defined.

**✅ DO:**
- Prefer keyset pagination (`WHERE sortKey < :lastValue ORDER BY sortKey DESC LIMIT n`) for long lists; use a unique sort key or add a tie-breaker.
- Use `LIMIT` in `execute` and observers to cap memory.

**❌ DON'T:**
- Put `LIMIT` or `ORDER BY` in a subscription. Subscriptions reject them by default, and a subscription defines which documents sync, not how a screen pages through them. See [Subscription Rules](#subscription-rules).

```dart
// ✅ GOOD: Keyset pagination: continue after the last row of the previous page.
// _id breaks ties between rows that share the same createdAt.
// Load the first page with the same query without the WHERE clause.
Future<List<Map<String, dynamic>>> nextPage(
  Ditto ditto, {
  required String afterCreatedAt,
  required String afterId,
  int pageSize = 50,
}) async {
  final result = await ditto.store.execute(
    'SELECT _id, title, createdAt FROM tasks '
    'WHERE createdAt < :after OR (createdAt = :after AND _id < :afterId) '
    'ORDER BY createdAt DESC, _id DESC LIMIT :pageSize',
    arguments: {
      'after': afterCreatedAt,
      'afterId': afterId,
      'pageSize': pageSize,
    },
  );
  return result.items.map((item) => item.value).toList();
}

// Works, but every page re-reads and skips all earlier rows.
// _id makes the order unique, so rows are not repeated or skipped across pages.
Future<List<Map<String, dynamic>>> pageByOffset(Ditto ditto, int page) async {
  const pageSize = 50;
  final result = await ditto.store.execute(
    'SELECT _id, title, createdAt FROM tasks '
    'ORDER BY createdAt DESC, _id DESC LIMIT :pageSize OFFSET :offset',
    arguments: {'pageSize': pageSize, 'offset': page * pageSize},
  );
  return result.items.map((item) => item.value).toList();
}
```

### USE IDS

`USE IDS` reads documents by ID directly:

```sql
SELECT * FROM orders USE IDS 'order-1', 'order-2'

SELECT * FROM orders USE IDS LIST :ids
```

| Form | Behavior |
|---|---|
| `USE IDS 'a', 'b'` | ✅ Literal IDs, comma-separated, no parentheses |
| `USE IDS LIST :ids` | ✅ Array parameter |
| `USE IDS ('a', 'b')` | ❌ Error: `('a', 'b') is not supported` | <!-- lint-ignore -->
| `USE IDS :ids` with an array | ❌ Treats the whole array as a single ID and returns nothing |

A `WHERE _id = :id` or `WHERE _id IN :ids` filter is also planned as a direct ID lookup, so for most code the `WHERE` form is the simplest choice. For `DELETE` and `EVICT`, always use the `WHERE` form (see [DELETE and EVICT](#delete-and-evict)).

```dart
// ✅ GOOD: Direct ID lookup with an array parameter
Future<List<Map<String, dynamic>>> ordersByIds(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

### Filtering by Membership

| Goal | Expression | Notes |
|---|---|---|
| Field equals one of several values | `status IN :statuses` | ✅ Array parameter; can use an index on `status` |
| Field equals none of several values | `status NOT IN :statuses` | Documents where `status` is missing are not returned |
| Literal list | `status IN ('open', 'pending')` | ✅ |
| Array field contains a value | `:tag IN tags` or `array_contains(tags, :tag)` | ✅ Element lookups cannot use an index |
| Array parameter, wrapped in parentheses | `status IN (:statuses)` | ❌ Matches nothing |

```dart
// ✅ GOOD: Membership against an array parameter
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

// ✅ GOOD: Documents whose tags array contains a value
Future<List<Map<String, dynamic>>> tasksTagged(Ditto ditto, String tag) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE :tag IN tags ORDER BY _id',
    arguments: {'tag': tag},
  );
  return result.items.map((item) => item.value).toList();
}
```

> **Note (SDK 5.1.0):** An `ANY ... SATISFIES ... END` expression in a `WHERE` clause that iterates over a parameter or a literal array, such as `WHERE ANY s IN :statuses SATISFIES s = status END`, returns no rows. Use `status IN :statuses` (or `array_contains(:statuses, status)`) for membership filters. This is a 5.1.0 regression; 5.0.x returned the matching documents. A subscription with the same `WHERE` clause syncs the right documents, so the usual "subscribe and observe with the same query" pattern receives the data but shows an empty list. See [ANY and EVERY](#any-and-every). <!-- lint-ignore -->

### Joining Collections (SDK 5.1+)

`SELECT` can combine documents from several collections with `JOIN`. Joins run on the documents that are already in the local store.

#### Join types

| Join | Rows returned | Unmatched right side |
|---|---|---|
| `JOIN` / `INNER JOIN` | Only pairs that satisfy `ON` | Row dropped |
| `LEFT [OUTER] JOIN` | Every left row, matched or not | Right-side fields are MISSING |
| `RIGHT [OUTER] JOIN` | Every right row, matched or not | Left-side fields are MISSING; allowed only as the first join |

`FULL OUTER JOIN`, `CROSS JOIN`, comma joins (`FROM a, b`), and joins in `UPDATE` / `DELETE` are not supported.

The `ON` clause can be any condition over the aliases introduced so far, including `AND` / `OR` and filters on one side:

```sql
-- Every customer with their orders; customers without orders are kept
-- (requires an index on orders.customerId; see Index requirement below)
SELECT c.name, o._id AS orderId, o.total
FROM customers c
LEFT JOIN orders o ON o.customerId = c._id AND o.status = 'open'
ORDER BY c.name, o.total
```

```sql
-- Customers without any order (unmatched LEFT JOIN rows)
-- (requires an index on orders.customerId; see Index requirement below)
SELECT c._id, c.name
FROM customers c
LEFT JOIN orders o ON o.customerId = c._id
WHERE o._id IS MISSING
```

#### Index requirement

Ditto executes joins as nested loops: for each row of the outer collection it looks up matching rows in the inner (joined) collection. This lookup must use an index or an ID lookup unless you explicitly allow a scan with `USE INDEX ''` (see below). Without one, the query fails before it runs:

<!-- expect-error -->
```sql
-- ❌ BAD: No index on customers.email
SELECT o._id, c.name
FROM orders o
JOIN customers c ON c.email = o.customerEmail
```

```text
Query failed: `Joining to "c" disallowed without appropriate index support. Please run ADVISE for recommendations.`
```

The fix is to index the join key of the inner collection (here `CREATE INDEX IF NOT EXISTS idx_customers_email ON customers (email)`). The same pattern for orders joined by `customerId`:

```sql
-- ✅ GOOD: Index the join key of the inner collection
CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)
```

```sql
SELECT c.name, o._id AS orderId, o.total
FROM customers c
JOIN orders o ON o.customerId = c._id
WHERE c.tier = 'gold'
ORDER BY c.name, o.total DESC
```

Joining **on `_id`** of the inner collection needs no extra index, because Ditto looks documents up by ID:

```sql
-- ✅ GOOD: Inner side is looked up by _id
SELECT o._id, o.total, c.name AS customerName
FROM orders o
JOIN customers c ON c._id = o.customerId
WHERE o.status = 'open'
ORDER BY o._id
```

For a small collection, you can explicitly allow a full scan of one join term with `USE INDEX ""` (or `USE INDEX ''`) placed before `ON`. Other join terms in the same statement still need an index.

```sql
-- Explicitly accept a collection scan of a small lookup collection
SELECT o._id, r.label
FROM orders o
JOIN regions r USE INDEX '' ON r.code = o.regionCode
```

Run `ADVISE` on a join query to get the `CREATE INDEX` statements it needs; see [ADVISE (SDK 5.1+)](#advise-sdk-51). Indexes persist across app restarts, so create them once (for example with `CREATE INDEX IF NOT EXISTS` at startup).

#### Result shape

| Projection | Result row |
|---|---|
| `SELECT *` | One nested object per alias: `{"c": {...}, "o": {...}}` |
| `SELECT c.*, o.total` | Flat: all customer fields plus `total` |
| `SELECT _id` | A composite ID per joined row: `{"c": "c1", "o": "o1"}` |
| `SELECT name` (field exists on both sides) | Error: `Ambiguous reference to field: name` |

Always qualify fields with their alias (`c.name`, `o.total`) and alias projected fields that would otherwise collide (`o._id AS orderId`).

#### Restrictions

- **Local data only**: A join reads only documents already in the local store. It never fetches missing documents from peers, so every joined collection needs its own subscription.
- **Not in subscriptions**: `registerSubscription` rejects joins (`Unsupported feature: Joining`). Subscribe to each collection separately with `SELECT * FROM c WHERE ...`.
- **Not on Ditto Server**: Joins are a Small Peer feature; Ditto Server queries (including the HTTP API) do not support them.
- **`RIGHT JOIN` only as the first join**: A later `RIGHT JOIN` fails with `RIGHT OUTER join that isn't the first join is not supported`. Because Ditto rewrites a `RIGHT JOIN` as a `LEFT JOIN` with the sides swapped, the collection written on the left then becomes the inner side and needs the index (or the `_id` join).
- **At most 10 joins per statement** by default (directive `#max_joins`; see [Directives](#directives)). More fail with `Too many joins: the number of joined terms exceeds the maximum permitted.`

#### Joins in observers

`registerObserver` accepts joins, and the observer delivers a new result when a change in any of the joined collections changes the joined rows. Each row delivered to the observer carries a composite `_id` (for example `{"c": "c1", "o": "o1"}`) that you can use as a stable key when diffing. Subscribe to each collection the join reads.

```dart
// ✅ GOOD: Subscribe per collection (app or feature scope), join locally
List<SyncSubscription> subscribeForOrderList(Ditto ditto) => [
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE status = :status',
        arguments: {'status': 'open'},
      ),
      ditto.sync.registerSubscription('SELECT * FROM customers'),
    ];

// ✅ GOOD: Observe the join (screen scope); call dispose() when the screen goes away
class OpenOrdersWithCustomers {
  OpenOrdersWithCustomers(
    Ditto ditto,
    void Function(List<Map<String, dynamic>> rows) onRows,
  ) : _observer = ditto.store.registerObserver(
          'SELECT o._id AS orderId, o.total, c.name AS customerName '
          'FROM orders o JOIN customers c ON c._id = o.customerId '
          'WHERE o.status = :status ORDER BY o.createdAt DESC, o._id',
          arguments: {'status': 'open'},
        ) {
    _changes = _observer.changes.listen(
      (result) => onRows(result.items.map((item) => item.value).toList()),
    );
  }

  final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;

  void dispose() {
    _changes.cancel();
    _observer.cancel();
  }
}
```

For a complete widget lifecycle (register in `initState`, cancel the stream subscription and the observer in `dispose`), follow [Store Observers in Flutter](#store-observers-in-flutter).

#### Join or embed?

Joins make separate, normalized collections practical to query, but they do not change the main data modeling trade-offs: embedded data is updated atomically in one document and syncs as one unit, while separate collections let you sync, secure, and update parts independently. Ditto's guidance remains to embed by default and to split data when access patterns, permissions, or document size call for it. See [Relationships: Embedding, Separate Collections, and JOIN](#relationships-embedding-separate-collections-and-join).

#### Performance tips

**✅ DO:**
- Index the join key of every inner collection, or join on `_id`.
- Start from the most selective collection and filter it in `WHERE` (for example `WHERE o.status = 'open'`), so fewer outer rows drive lookups.
- Qualify every field with its alias.
- Check the plan with `EXPLAIN` during development (a join appears as `nlJoin`) and run `ADVISE` before release. See [EXPLAIN and PROFILE](#explain-and-profile).

**❌ DON'T:**
- Use `USE INDEX ''` on large collections to silence the index error: every outer row then scans the whole inner collection.
- Rely on a join to pull related documents onto a device: subscribe to them explicitly.

---

## Writing Data

### INSERT and Conflict Handling

Insert documents by passing them as parameters. Each document needs a unique `_id` (or Ditto generates one; see [Document IDs](#document-ids)).

```dart
// ✅ GOOD: One document as a parameter
Future<void> createOrder(Ditto ditto, String id, String customerId) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': id,
        'customerId': customerId,
        'status': 'open',
        'total': 0,
        // createdAt is sorted and compared, so it uses the fixed-precision
        // helper. utcTimestamp() is defined in the Timestamps section.
        'createdAt': utcTimestamp(),
      },
    },
  );
}

// ✅ GOOD: Several documents in one statement, as an array parameter
Future<void> importProducts(Ditto ditto, List<Map<String, dynamic>> products) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'products': products},
  );
}
```

You can also list several parameters: `DOCUMENTS (:first), (:second)`. A multi-document insert is atomic: if one document fails (for example with an ID conflict under `FAIL`), none of them is inserted. Two documents with the same `_id` in one statement fail with `Expected unique document identifiers`.

#### ON ID CONFLICT

| Policy | When the `_id` already exists locally |
|---|---|
| `FAIL` (default when omitted) | The statement fails: `Identifier conflict on document "...": using FAIL conflict policy` |
| `DO NOTHING` | The existing document is left unchanged; no error |
| `DO UPDATE` | Fields from the new document are written into the existing one. Fields you do not supply are kept, and nested objects are merged. Every supplied field is written, even if the value is identical, so the document is reported as mutated and observers can fire again (a `SELECT *` observer on the collection does). |
| `DO UPDATE_LOCAL_DIFF` | Same merge, but only fields whose values differ from the local document are written. If nothing changed, nothing is written and `mutatedDocumentIDs()` is empty. |

**✅ DO:**
- Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts and re-imports (for example when refreshing reference data from your backend).
- Use `DO NOTHING` for "create if absent" logic.
- Use `UNSET` (see [UPDATE](#update)) to remove fields. No `INSERT` policy deletes fields.

**❌ DON'T:**
- Use `DO UPDATE` to "replace" a document. It merges; fields missing from the new document stay.
- Use `DO UPDATE` for periodic re-upserts of unchanged data. Every run rewrites all supplied fields, records a mutation, and can wake observers.

```dart
// ✅ GOOD: Re-upserting unchanged data is a no-op
Future<bool> syncCatalogItem(Ditto ditto, Map<String, dynamic> item) async {
  final result = await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:item) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'item': item},
  );
  // Empty when the stored document already had the same values
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

Merge behavior, starting from `{"_id": "p1", "name": "Pen", "price": 5, "address": {"city": "Oslo", "zip": "0150"}}`:

```dart
Future<void> doUpdateMerges(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO products DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE',
    arguments: {
      'doc': {
        '_id': 'p1',
        'price': 6,
        'address': {'street': 'Main St'},
      },
    },
  );
  // Stored document afterwards:
  // {"_id": "p1", "name": "Pen", "price": 6,
  //  "address": {"city": "Oslo", "zip": "0150", "street": "Main St"}}
}
```

**Why:** With the default `DQL_STRICT_MODE = false`, objects are stored as CRDT maps that merge field by field (see [Strict Mode](#strict-mode) and [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior)). Writing only what changed keeps sync deltas small and reduces the chance that an unchanged value overwrites a concurrent edit from another peer.

#### INITIAL DOCUMENTS

`INSERT INTO c INITIAL DOCUMENTS (...)` seeds default data, such as default settings or a starter catalog, that every peer may create independently. The syntax is the same as for `DOCUMENTS`: pass each document as a parameter.

- If no document with that `_id` exists locally, it is inserted; if one exists, nothing happens and no error is raised.
- `ON ID CONFLICT` cannot be combined with `INITIAL DOCUMENTS` (parser error), and the source cannot be a `SELECT`.

How initial documents merge across peers, and what happens after a seeded document is deleted or evicted, is described in [Default Data with INITIAL Documents](#default-data-with-initial-documents).

```dart
// ✅ GOOD: Seed defaults on every launch; existing (possibly edited) data is kept
Future<void> seedDefaults(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO settings INITIAL DOCUMENTS (:defaults)',
    arguments: {
      'defaults': {
        '_id': 'app',
        'theme': 'light',
        'currency': 'USD',
      },
    },
  );
}
```

**❌ DON'T:** Use `INITIAL DOCUMENTS` to keep data off the network. Whether data syncs is decided by subscriptions.

#### INSERT ... SELECT (SDK 5.1+)

Copy or derive documents from a query. Each result row becomes a document, and projection aliases become field names. If the projection includes `_id`, it is used as the document ID; otherwise a new ID is generated.

```sql
-- Copy closed orders into an archive collection; safe to re-run
INSERT INTO archivedOrders
SELECT * FROM orders WHERE status = 'closed'
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
-- Build one summary document per status
INSERT INTO orderStats
SELECT status AS _id, COUNT(*) AS orderCount FROM orders GROUP BY status
ON ID CONFLICT DO UPDATE
```

The `SELECT` follows `INSERT INTO c` directly. Wrapping it in parentheses or in `DOCUMENTS (...)` is a syntax error, and `INITIAL DOCUMENTS` cannot be combined with a `SELECT` source.

### UPDATE

```text
UPDATE collection [USE IDS ...]
[APPLY counterField INCREMENT BY n, ...]
[SET field = value, nested.path = value, ...]
[UNSET field, nested.path, ...]
[WHERE condition]
[RETURNING projection]
```

At least one of `APPLY`, `SET`, or `UNSET` is required. Without `WHERE`, every document in the collection is updated. The clauses must appear in this order: `APPLY` (counters) before `SET`, and `UNSET` after `SET`. Counter updates are covered in [Counters](#counters).

```dart
// ✅ GOOD: Change only the fields that changed
Future<void> completeOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status, completedAt = :completedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'status': 'completed',
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

// ✅ GOOD: Nested paths; missing intermediate objects are created automatically
Future<void> setShippingCity(Ditto ditto, String orderId, String city) async {
  await ditto.store.execute(
    'UPDATE orders SET shipping.address.city = :city WHERE _id = :id',
    arguments: {'id': orderId, 'city': city},
  );
}

// ✅ GOOD: UNSET removes fields (they become MISSING)
Future<void> clearDiscount(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id',
    arguments: {'id': orderId},
  );
}
```

Errors to expect:
- `SET _id = ...` fails: ``The document id `_id` cannot be modified``.
- Setting the same path twice in one statement fails: `More than one modification specified for the path ...`.
- Array elements cannot be assigned (`SET items[0] = ...` is a syntax error). Replace the whole array, or model the collection as a map keyed by ID (see [Arrays and Maps](#arrays-and-maps)).

#### Assigning an object merges it

With the default strict mode (`DQL_STRICT_MODE = false`), an object field is a CRDT map. `SET obj = {...}` **merges** the new keys into the existing object instead of replacing it, and `SET obj = {}` leaves the object unchanged.

Keys are removed only by `UNSET`, so replacing an object takes `UNSET` followed by `SET` in one transaction. The full table of local write semantics for maps, including upserts and scalar overwrites, is in [Local write semantics you must know](#local-write-semantics-you-must-know).

**✅ DO:**
- Update nested fields individually: `SET address.city = :city`.
- Remove keys with `UNSET address.zip`.
- To replace an object completely, run `UNSET` and then `SET` inside one transaction, or declare the field as a `REGISTER` so it is always replaced as a whole (see [Strict Mode](#strict-mode)).

**❌ DON'T:**
- Expect `SET obj = {...}` to remove keys that are not in the new value.
- Use `SET obj = {}` to clear an object.

```dart
// ✅ GOOD: Replace an object: remove the old map, then write the new one,
// in one transaction so that no observer sees the object missing
Future<void> replaceAddress(
  Ditto ditto,
  String customerId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.transaction(hint: 'replaceAddress', (tx) async {
    await tx.execute(
      'UPDATE customers UNSET address WHERE _id = :id',
      arguments: {'id': customerId},
    );
    await tx.execute(
      'UPDATE customers SET address = :address WHERE _id = :id',
      arguments: {'id': customerId, 'address': newAddress},
    );
  });
}
```

#### Prefer field-level updates over whole-document rewrites

**✅ DO:**
- Use `UPDATE ... SET` for the fields that changed.
- Skip writes that would not change anything, for example with a condition in `WHERE`, or use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts (it skips unchanged fields but does not protect a stale in-memory copy; see [Prefer field-level updates](#prefer-field-level-updates)).

**❌ DON'T:**
- Read a document, modify it in Dart, and write the whole map back with `INSERT ... ON ID CONFLICT DO UPDATE`.
- Write values that are already stored. An `UPDATE` that sets a field to its current value is still recorded as a mutation, appears in `mutatedDocumentIDs()`, and can wake observers (a `SELECT *` observer fires again with an identical result). It is also synced: in tests, a `SELECT *` observer on another device fired for it as well.

```dart
// ❌ BAD: Read-modify-write of the whole document
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

// ✅ GOOD: Single field-level update that skips unchanged documents
Future<bool> setStatus(Ditto ditto, String orderId, String status) async {
  final result = await ditto.store.execute(
    'UPDATE orders SET status = :status '
    'WHERE _id = :id AND coalesce(status, :none) != :status',
    arguments: {'id': orderId, 'status': status, 'none': ''},
  );
  return result.mutatedDocumentIDs().isNotEmpty;
}
```

The `coalesce` in the condition keeps documents whose `status` is missing or `null` eligible for the update; a plain `status != :status` would skip them (see [MISSING and NULL](#missing-and-null)).

**Why:** Ditto syncs changes at field level. Rewriting a whole document writes every field again: it makes the change larger, and an unchanged field written by this device can win a merge against a real concurrent change made on another device. Field-level updates touch only what the user actually changed.

### RETURNING (SDK 5.1+)

Add `RETURNING` to `INSERT`, `UPDATE`, `DELETE`, or `EVICT` to get the affected documents back in `items`, in the same statement.

| Statement | Rows in `items` |
|---|---|
| `INSERT ... RETURNING` | The documents written (documents skipped by `DO NOTHING` or left unchanged by `DO UPDATE_LOCAL_DIFF` are not returned) |
| `UPDATE ... RETURNING` | The documents **after** the update |
| `DELETE ... RETURNING` / `EVICT ... RETURNING` | The documents **before** they were removed |

`commitID` is populated as usual when `RETURNING` is used, and so is `mutatedDocumentIDs()`. Treat `items` as the result of a statement with `RETURNING`: include `_id` in the `RETURNING` projection when you need the IDs, rather than making that code depend on `mutatedDocumentIDs()`.

```dart
// ✅ GOOD: Update and read the new values in one statement
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

// ✅ GOOD: Keep a copy of what was deleted (for an undo banner or an audit log)
Future<List<Map<String, dynamic>>> deleteDrafts(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'DELETE FROM drafts WHERE _id IN :ids RETURNING *',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}
```

The projection syntax is the same as in `SELECT`, including aliases and expressions. Aggregates summarize all affected documents:

```sql
DELETE FROM sessions WHERE expiresAt < :now RETURNING COUNT(*) AS removed
```

**Why:** `RETURNING` replaces the "write, then query again" pattern with one statement, so the values you read are exactly the ones you wrote, and for `DELETE` it returns the removed content from the same atomic statement.

### DELETE and EVICT

| Statement | Effect |
|---|---|
| `DELETE FROM c WHERE ...` | Deletes the documents on all peers. Leaves a tombstone that syncs the deletion. |
| `EVICT FROM c WHERE ...` | Removes the documents from this device only. Other peers keep them, and they can be synced back while a matching subscription is active (see [EVICT](#evict)). |

Choosing between them, tombstone lifetime, soft delete, and storage cleanup are covered in [Deletion and Storage Management](#deletion-and-storage-management).

> **Note (SDK 5.1.0):** `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`), such as `DELETE FROM orders USE IDS 'a'`, completes without an error but removes nothing. Select documents by ID with `WHERE _id = :id` or `WHERE _id IN :ids` instead.

`RETURNING` (SDK 5.1+) on `DELETE` and `EVICT` returns the documents as they were before removal; see [DELETE and Tombstones](#delete-and-tombstones) for examples.

---

## DQL Functions and Operators

This section lists DQL functions from the [DQL operators and expressions](https://docs.ditto.live/dql/operator-expressions) reference and how they behave. Two rules apply to all of them:

- **Wrong argument types give MISSING, not an error.** `concat('a', 1)`, `'a' || 1`, `lower(1)`, a date string without a time zone, or swapped arguments to `date_add` all evaluate to MISSING silently. In a projection the alias disappears from the row; in `WHERE` the row is excluded. Test new expressions against real data.
- **Functions applied to a field usually prevent index use.** Compare the stored field directly where possible. See [Index Usage Rules](#index-usage-rules).

### Date and Time

Date functions accept either **ISO-8601 strings with a time zone** (`2026-03-15T10:30:45.123Z` or `...+09:00`) or **epoch milliseconds** (integers). `date_add`, `date_sub`, `date_trunc`, and `date_range` return strings for string input and epoch milliseconds for numeric input.

> **Note:** An ISO-8601 string **without** a zone designator, such as the output of Dart's `DateTime.now().toIso8601String()` for a local time, is not accepted by date functions unless you pass an explicit format to `date_cast`: the result is MISSING. Store timestamps in UTC, where `DateTime.now().toUtc().toIso8601String()` ends in `Z` (use the `utcTimestamp()` helper from [Timestamps](#timestamps) for values that are sorted or compared), or as `millisecondsSinceEpoch`. <!-- lint-ignore -->

| Function | Description | Example → result |
|---|---|---|
| `clock([format[, tz]])` | Current time on **this device**: epoch ms, or a string when a format is given (`''` = ISO-8601) | `clock()` → `1791454108090`; `clock('')` → `'2026-10-08T10:08:28.090+00:00'` |
| `date_add(date, part, count[, format[, tz]])` | Add `count` parts (negative to subtract) | `date_add('2026-03-15T10:30:45.123Z', 'day', 7)` → `'2026-03-22T10:30:45.123+00:00'` |
| `date_sub(date, part, count[, format[, tz]])` | Subtract `count` parts | `date_sub('2026-03-15T10:30:45.123Z', 'hour', 2)` → `'2026-03-15T08:30:45.123+00:00'` |
| `date_diff(date1, date2, part)` | Whole `part`s from `date2` to `date1` (`date1 - date2`) | `date_diff('2026-03-20T00:00:00Z', '2026-03-15T10:30:45Z', 'day')` → `4` |
| `date_part(date, part)` | One component | `date_part('2026-03-15T10:30:45Z', 'weekday')` → `7` (Sunday) |
| `date_trunc(date, part)` | Truncate to `part` | `date_trunc('2026-03-15T10:30:45Z', 'day')` → `'2026-03-15T00:00:00+00:00'` |
| `date_format(date, format[, tz])` | Format, optionally converting to a time zone | `date_format('2026-03-15T10:30:45Z', 'YYYY-MM-DD hh:mm', 'Asia/Tokyo')` → `'2026-03-15 19:30'` |
| `date_cast(string[, format])` | Parse to epoch ms; date-only strings need a format | `date_cast('15/03/2026', '%d/%m/%Y')` → `1773532800000` |
| `date_range(start, end, part, count[, format[, tz]])` | Array of dates from `start` (inclusive) to `end` (exclusive) | `date_range('2026-03-01T00:00:00Z', '2026-03-04T00:00:00Z', 'day', 1)` → 3 dates |
| `tz_offset(string[, format])` | The time zone offset **in minutes** of a date string, or of a zone name when the format `'TZN'` is passed (it does not convert dates) | `tz_offset('2026-03-15T10:30:45+09:00')` → `540`; `tz_offset('Asia/Tokyo', 'TZN')` → `540`. With `'TZN'`, the result is the offset in force on **1970-01-01**, not today's: `tz_offset('America/New_York', 'TZN')` → `-300` even during daylight saving time, and `tz_offset('Asia/Kathmandu', 'TZN')` → `330` (today +345) |

**Parts** for `date_add`, `date_sub`, `date_diff`, and `date_trunc`: `year`, `mon`/`month`, `day`, `hour`, `min`/`minute`, `sec`/`second`, `ms`/`millis`/`millisecond`. `date_part` additionally accepts `weekday` (ISO-8601: Monday = 1, Sunday = 7), `monthname`, and `tz`/`timezone`. Other part names (`week`, `quarter`, `dow`, `doy`) return MISSING.

**Formats** use either SQL-like sequences (`YYYY-MM-DD hh:mm:ss.sss TZD`) or `%`-style specifiers (`%Y-%m-%d`); an empty string means ISO-8601.

**✅ DO:**
- Keep the argument order `date_add(date, part, count)`. Swapped arguments return MISSING without an error.
- Compare stored timestamps against parameters of the same type: ISO strings against ISO strings in the same format and precision (produce both with one helper, see [Timestamps](#timestamps)), epoch ms against numbers.
- Compute time windows such as "last 7 days" in Dart and pass the boundary as a parameter. The comparison stays index-friendly and does not depend on `clock()`.

**❌ DON'T:**
- Compare an ISO string field with `clock()` (a number); values of different types are never equal or ordered against each other.
- Mix ISO strings with different fractional precision in one field. String comparison then does not match chronological order (`'...45Z' < '...45.123Z'` is false). Dart's `toIso8601String()` alone produces such mixed values on native platforms (see [Timestamps](#timestamps) for why); produce compared values with the fixed-precision helper `utcTimestamp()` from that section. <!-- lint-ignore -->
- Expect `clock()` to give a trusted time: it is the clock of the device running the query.

```dart
// ✅ GOOD: Boundary computed in Dart and formatted with the same fixed-precision
// helper that writes createdAt (utcTimestamp() from the Timestamps section)
Future<List<Map<String, dynamic>>> recentOrders(Ditto ditto) async {
  final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE createdAt >= :since ORDER BY createdAt DESC',
    arguments: {'since': utcTimestamp(since)},
  );
  return result.items.map((item) => item.value).toList();
}

// ✅ GOOD: Daily totals since a boundary (format it with utcTimestamp() as in
// recentOrders); the GROUP BY repeats the expression
Future<List<Map<String, dynamic>>> dailyRevenue(Ditto ditto, String since) async {
  final result = await ditto.store.execute(
    "SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue "
    'FROM orders WHERE createdAt >= :since '
    "GROUP BY date_format(createdAt, 'YYYY-MM-DD') "
    'ORDER BY day',
    arguments: {'since': since},
  );
  return result.items.map((item) => item.value).toList();
}
```

```sql
-- ❌ BAD: Arguments in the wrong order: returns MISSING, no error
SELECT date_add(createdAt, 7, 'day') AS dueAt FROM orders

-- ✅ GOOD
SELECT date_add(createdAt, 'day', 7) AS dueAt FROM orders
```

Durations are handled by `duration_cast(str[, unit])` (`duration_cast('1h30m')` → `5400000` ms) and `duration_format(value[, unit])` (`duration_format(5400000)` → `'1h30m0s'`).

### Conditional Functions

| Function | Returns | Example → result |
|---|---|---|
| `coalesce(v1, v2, ...)` | First value that is neither `null` nor missing (same as `ifmissingornull`) | `coalesce(nickname, name, 'Guest')` |
| `nvl(v, r)` | `v` if it is not `null`, otherwise `r` (a missing `v` is also replaced) | `nvl(discount, 0)` |
| `nvl(v, r1, r2)` | `r1` if `v` is not `null`, otherwise `r2` | `nvl(paidAt, 'paid', 'unpaid')` |
| `ifmissing(v, ...)` / `ifnull(v, ...)` | `ifmissing` returns the first value that is not missing, which can be `null` (`ifmissing(null, 0)` is `null`). `ifnull` returns the first value that is not `null`, but returns MISSING when it reaches a missing value first (`ifnull(missingField, 0)` is MISSING). `coalesce` skips both | `ifmissing(SUM(total), 0)` |
| `ismissing(v)` / `isnull(v)` / `ismissingornull(v)` | Boolean tests | `ismissingornull(email)` |
| `nullif(v1, v2)` / `missingif(v1, v2)` | `null` / MISSING when `v1 = v2`, otherwise `v1` | `nullif(status, '')` |
| `decode(input, c1, r1, [c2, r2, ...] [, default])` | `r` of the first `c` matching `input` without type conversion (a string never matches a number; integers and floats compare numerically); `default` (or `null`) otherwise | `decode(level, 1, 'low', 2, 'high', 'other')` |
| `CASE WHEN cond THEN r ... [ELSE d] END` | Result of the first true condition; `null` without `ELSE` | see below |
| `CASE expr WHEN v THEN r ... [ELSE d] END` | Result of the first matching value; `null` without `ELSE` | see below |

```sql
SELECT _id,
  coalesce(nickname, name, 'Guest') AS displayName,
  CASE
    WHEN total >= 1000 THEN 'large'
    WHEN total >= 100 THEN 'medium'
    ELSE 'small'
  END AS sizeClass,
  CASE status WHEN 'open' THEN 1 WHEN 'packed' THEN 2 ELSE 3 END AS statusRank
FROM orders
ORDER BY statusRank, _id
```

**✅ DO:**
- Use `coalesce` for defaults; it handles both `null` and missing fields.
- Always add `ELSE` to `CASE` when `null` is not an acceptable result.
- Remember that `decode` compares types: `decode('2', 1, 'one', 2, 'two', 'other')` returns `'other'` because `'2'` is a string.

### Type Checking

| Function | Returns |
|---|---|
| `type(x)` | `'boolean'`, `'string'`, `'integer'`, `'float'`, `'object'`, `'array'`, `'binary'`, `'null'`, `'missing'` |
| `json_type(x)` | `'boolean'`, `'string'`, `'number'`, `'object'`, `'array'`, `'binary'`, `'null'` (also `'null'` for missing) |
| `is_number(x)` / `is_string(x)` / `is_boolean(x)` | `true` or `false` for non-null values; `null` for `null` and MISSING for a missing `x` |

**✅ DO:**
- Use `is_number(x)` or `json_type(x) = 'number'` to accept both integers and floats.
- Use `type(x) = 'missing'` or `x IS MISSING` to find absent fields; `json_type` reports them as `'null'`.

**❌ DON'T:**
- Compare `type(x)` with `'number'`. `type()` never returns `'number'`, so `type(x) = 'number'` matches nothing and `type(x) != 'number'` matches everything.

```sql
-- Find documents whose price was stored with the wrong type
SELECT _id, price, type(price) AS storedAs
FROM products
WHERE price IS NOT MISSING AND NOT is_number(price)
```

Numbers keep their integer or float type: `type(1)` is `'integer'`, `type(1.5)` is `'float'`, and arithmetic between integers stays integer (`5 / 2` is `2`). Cast when you need a different type: `cast(x AS float)`, `cast(x AS string)`, `cast(x AS integer)`. A cast that cannot convert returns MISSING.

### String Functions

| Function / operator | Description | Example → result |
|---|---|---|
| `a \|\| b`, `concat(a, b, ...)` | Concatenation (strings only; other types give MISSING) | `'n' \|\| cast(1 AS string)` → `'n1'` |
| `starts_with(s, prefix)` / `ends_with(s, suffix)` | Prefix / suffix test | `ends_with(email, '@example.com')` |
| `contains(s, sub)` | Substring test | `contains(title, 'urgent')` |
| `s LIKE pattern` / `s ILIKE pattern` | `%` matches any sequence, `_` one character; `ILIKE` ignores case | `sku LIKE 'AB-%'` |
| `s SIMILAR TO pattern` | `LIKE` wildcards plus `\|` alternatives, `[chars]` lists, grouping, and the repetition operators `*`, `+`, `?`, `{n}` | `code SIMILAR TO '(A\|B)%'` |
| `regexp_like(s, pattern[, flags])` | Regular expression match; `'i'` for case-insensitive | `regexp_like(code, '^[a-z]-[0-9]{3}$', 'i')` |
| `char_length(s)` / `character_length(s)` | Number of characters | `char_length('café')` → `4` |
| `byte_length(s)` | Number of UTF-8 bytes | `byte_length('café')` → `5` |
| `lower(s)` / `upper(s)` | Case conversion | `lower(email) = :email` |
| `substr(s, start[, len])` | Substring; `start` is zero-based | `substr('abcdef', 1, 3)` → `'bcd'` |
| `pos(s, sub)` / `POSITION(sub IN s)` | Zero-based index, `-1` if not found | `pos('abc', 'c')` → `2` |
| `split(s, delim)` / `joinstr(sep, values...)` | Split into an array / join with a separator (separator first) | `joinstr(', ', tags)` |
| `ltrim`, `rtrim`, `` `trim` ``, `TRIM(BOTH x FROM s)`, `lpad`, `rpad`, `repeat` | Trimming and padding (call `trim` with backticks) | `lpad(code, 6, '0')` |

**✅ DO:**
- Use `LIKE 'prefix%'` for prefix searches. It is the form that can use an index; see [Index Usage Rules](#index-usage-rules).
- Use `byte_length` (not `char_length`) when checking against byte-based limits.
- Escape `%` or `_` in `LIKE` with an `ESCAPE` character such as `'!'`: `discount LIKE '50!%' ESCAPE '!'`. A backslash works too, but must be written `'\\'` because backslashes are escape characters in DQL strings.
- Normalize case when writing (for example store `emailLower`) instead of calling `lower()` on the field in every query.

**❌ DON'T:**
- Concatenate numbers without `cast(... AS string)`.
- Use `SIMILAR TO` like a full regular expression: `.` matches only a literal dot there (`'abc' SIMILAR TO 'a.c'` is `false`), and the pattern must match the whole string. Use `regexp_like` for full regular expressions.

```dart
// ✅ GOOD: Prefix search with a parameter
// If prefix comes from user input, escape % and _ first (see below).
Future<List<Map<String, dynamic>>> productsBySkuPrefix(Ditto ditto, String prefix) async {
  final result = await ditto.store.execute(
    'SELECT _id, sku, name FROM products WHERE sku LIKE :pattern ORDER BY sku LIMIT 20',
    arguments: {'pattern': '$prefix%'},
  );
  return result.items.map((item) => item.value).toList();
}
```

If user input can contain `%` or `_`, escape them before building the pattern, or use `starts_with(sku, :prefix)`, which treats the prefix literally but cannot use an index.

### Object Functions

| Function | Returns | Example → result |
|---|---|---|
| `object_keys(o)` / `object_values(o)` | Top-level keys / values as an array | `object_keys({'a': 1, 'b': 2})` → `['a', 'b']` |
| `object_length(o)` | Number of top-level keys (`0` for `{}`) | `object_length(items) = 0` finds empty maps |
| `object_set(o, key, value[, replace])` | Copy with a key added; pass `true` to overwrite an existing key (without it, an existing key gives MISSING) | `object_set(o, 'b', 2)` |
| `object_unset(o, key[, ignoreMissing])` | Copy without a key; pass `true` to ignore a key that does not exist (without it, the result is MISSING) | `object_unset(o, 'b')` |
| `object_concat(o1, o2, ...)` | Shallow merge; the last object wins | `object_concat({'a': 1}, {'a': 3, 'b': 2})` → `{'a': 3, 'b': 2}` |
| `object_rename(o, old, new)` | Copy with a key renamed | `object_rename(o, 'a', 'z')` |
| `object_size(o)` | Approximate size in bytes, for comparisons | `object_size(orders) > 200000` |

These functions shape query **results**; they do not modify stored documents. Use `UPDATE ... SET` / `UNSET` to change data.

```sql
-- Documents whose items map is empty, and documents that are getting large
SELECT _id, object_length(items) AS itemCount, object_size(orders) AS approxBytes
FROM orders
WHERE object_length(items) = 0 OR object_size(orders) > 200000
```

`object_size(alias)` with the collection name or alias (as in `object_size(orders)` above) measures the whole document and helps you find documents approaching the size limits described in [Document Size Limits](#document-size-limits) (soft limit 256 KiB). An empty object `{}` is not `null`: test it with `object_length(o) = 0`, not `IS NULL`.

### Arrays and Collection Operators

| Operator / function | Description | Example → result |
|---|---|---|
| `x IN :values` / `x IN (a, b, ...)` | Membership in a parameter array or a literal list | `status IN :statuses` |
| `x NOT IN :values` | Non-membership; missing `x` never matches | `status NOT IN ('archived')` |
| `v IN arrayField` | Array field contains `v` | `:tag IN tags` |
| `array_contains(array, v)` | Same test as a function | `array_contains(tags, 'red')` |
| `array_contains_null(array)` | Array contains a `null` element | `array_contains_null(scores)` |
| `array_length(array)` | Number of elements | `array_length(tags) > 0` |
| `x BETWEEN low AND high` | `x >= low AND x <= high` (inclusive) | `10 BETWEEN 1 AND 10` → `true` |
| `x NOT BETWEEN low AND high` | Outside the inclusive range | `5 NOT BETWEEN 1 AND 3` → `true` |

**✅ DO:**
- Write `BETWEEN` bounds in ascending order. `x BETWEEN 10 AND 1` is always false; the bounds are not swapped for you.
- Use `IN :values` with an array parameter for "one of" filters.

**❌ DON'T:**
- Expect an index to speed up element lookups such as `:tag IN tags` or `array_contains(tags, :tag)`. An index on an array field only matches the whole array value.

```dart
// ✅ GOOD: Inclusive range with parameters
Future<List<Map<String, dynamic>>> ordersInPriceRange(
  Ditto ditto,
  num min,
  num max,
) async {
  final result = await ditto.store.execute(
    'SELECT _id, total FROM orders WHERE total BETWEEN :min AND :max ORDER BY total',
    arguments: {'min': min, 'max': max},
  );
  return result.items.map((item) => item.value).toList();
}
```

### ANY and EVERY

`ANY` and `EVERY` test the elements of an array (or the values of an object):

```text
ANY [index:]value IN|WITHIN source SATISFIES condition END
EVERY [index:]value IN|WITHIN source SATISFIES condition END
ANY AND EVERY [index:]value IN|WITHIN source SATISFIES condition END
```

`IN` looks at direct elements; `WITHIN` searches nested arrays and objects recursively. `EVERY` is `true` for an empty array, `ANY AND EVERY` is `false` for an empty array.

Use them in projections to compute flags over embedded arrays:

```sql
SELECT _id,
  ANY line IN lines SATISFIES line.quantity = 0 END AS hasEmptyLine,
  EVERY line IN lines SATISFIES line.picked = true END AS fullyPicked
FROM orders
WHERE status = 'open'
```

> **Note (SDK 5.1.0):** Do not use `ANY` or `EVERY` over a parameter or literal array in a `WHERE` clause, such as `WHERE ANY s IN :statuses SATISFIES s = status END`: it returns no rows. Use `status IN :statuses` instead. `ANY` and `EVERY` over a document's own array field work in `WHERE`; for a plain element test, `:value IN arrayField` or `array_contains(arrayField, :value)` is the simpler choice. The bug affects local queries and observers; subscriptions with the same predicate sync correctly, so the data arrives but an observer with the same statement stays empty. 5.0.x was not affected. <!-- lint-ignore -->

### ARRAY and OBJECT Transformations

Build new arrays or objects from an array or object in the result:

```text
ARRAY valueExpr FOR [index:]value IN|WITHIN source [WHEN condition] END
OBJECT nameExpr : valueExpr FOR [name:]value IN|WITHIN source [WHEN condition] END
```

```sql
SELECT _id,
  ARRAY line.sku FOR line IN lines WHEN line.quantity > 0 END AS skusToPick,
  OBJECT line.sku : line.quantity FOR line IN lines END AS quantityBySku,
  ARRAY price * 1.1 FOR price IN unitPrices END AS grossPrices
FROM orders
WHERE _id = :id
```

- Elements whose `valueExpr` evaluates to MISSING are skipped.
- In `OBJECT`, `nameExpr` must be a string; when two elements produce the same name, the later one wins.
- A missing `source` yields MISSING; a `source` that is neither an array nor an object yields `null`.

Use transformations to shape data for the UI in the query instead of post-processing in Dart, particularly in observers where the work repeats on every change.

### Arithmetic, Conversion, and Other Functions

| Function / operator | Description | Example → result |
|---|---|---|
| `+ - * / %` | Arithmetic; integer operands give integer results | `7 % 3` → `1`; `5 / 2` → `2` |
| `abs(x)`, `ceil(x)`, `floor(x)` | Absolute value, round up, round down | `ceil(1.2)` → `2.0` (a float) |
| `cast(v AS type)` / `cast(v, 'type')` | Convert to `string`, `integer`, `float`, `boolean`, or `binary`; MISSING if not possible | `cast('42' AS integer)` → `42` |
| `serialize_json(v)` | JSON text of a value | `serialize_json({'a': [1]})` → `'{"a":[1]}'` |
| `deserialize_json(s)` | Parse JSON text (also usable in `INSERT` and `UPDATE`) | `deserialize_json(:json)` |
| `request_info()` | Metadata about the running request (`app_id`, `request_id`, `start_time`) | `SELECT request_info() FROM system:dual` |

`deserialize_json` lets you insert a JSON payload received from a backend without decoding it in Dart first. In app code, pass the text as a parameter, `DOCUMENTS (deserialize_json(:json))`; with a literal it looks like this:

```sql
INSERT INTO products
DOCUMENTS (deserialize_json('{"_id": "p1", "name": "Pen", "price": 2}'))
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

`system:dual` is a built-in collection with a single document. Use it to try out expressions: `SELECT date_add(:now, 'day', 1) AS tomorrow FROM system:dual`.

---

## Data Modeling

Ditto is a schemaless document database, but every value you write is stored as a CRDT (conflict-free replicated data type). The CRDT type of a field decides what happens when two devices change it while they are disconnected and then sync. Data modeling in Ditto is therefore mostly about one question: **when concurrent edits meet, does the merge produce the result your business needs?**

This section covers the CRDT types and how documents map to them, strict mode, the choice between arrays and maps, document structure and size, relationships (including JOIN, SDK 5.1+), document IDs, counters, event history, default data, schema evolution, and timestamps.

**Design checklist:**

- Multiple devices will modify the same data while offline. Model every field for the merge you want.
- Prefer field-level updates over whole-document writes.
- Use maps keyed by ID (not arrays) for collections of items that several devices edit.
- Keep documents well under 256 KiB and store binary data as attachments.
- Use UUIDs or other collision-free IDs, never sequential numbers.
- Store timestamps in UTC with a zone designator, produced by one fixed-precision helper when they are sorted or compared.

### CRDT Types and Merge Behavior

Each field value in a document is stored as one of the following CRDT types:

| Type | What it holds | Merge rule for concurrent writes |
|---|---|---|
| `REGISTER` | Any single value: string, number, boolean, null, array, or an object kept as one value | Last-writer-wins (LWW), decided by a Hybrid Logical Clock (HLC) timestamp |
| `MAP` | An object whose keys merge independently | Add-wins: concurrent additions of different keys are all kept; each nested value merges by its own type |
| `COUNTER` | An integer | Increments and decrements from all peers are combined; `RESTART` operations are last-writer-wins, and a `RESTART` discards concurrent increments (see [RESTART](#restart)) |
| `ATTACHMENT` | A token that references binary data stored outside the document | Last-writer-wins |

`PN_COUNTER` also exists as a legacy counter type. Use `COUNTER` for all new fields (see [Counters](#counters)).

#### How values are typed with the default settings

With the default `DQL_STRICT_MODE = false` (see [Strict Mode](#strict-mode)), Ditto infers the type from the value and the operation:

| You write | Stored as | Consequence |
|---|---|---|
| A scalar (string, number, boolean, null) | `REGISTER` | Concurrent writes: one value wins |
| An array | `REGISTER` | The **whole array** is one value. Concurrent edits keep one version of the array |
| An object | `MAP` | Each key merges independently; nested objects are nested maps |
| `APPLY f INCREMENT BY n` / `RESTART` | `COUNTER` | Concurrent increments are added together |
| An attachment token | `ATTACHMENT` | Inferred from the attachment value |
| An object in a statement that declares `(f REGISTER)` | `REGISTER` | The object is replaced as a whole |

#### Merge semantics in detail

Ditto's [CRDT documentation](https://docs.ditto.live/key-concepts/syncing-data#crdts) and [conflict resolution patterns](https://docs.ditto.live/best-practices/conflict-resolution-patterns) describe how concurrent writes from different devices merge:

- **REGISTER (last-writer-wins).** When two devices write the same register concurrently, the write with the later HLC timestamp wins on every device. The losing write is discarded silently: there is no error and no notification.
- **MAP (add-wins).** When two devices add different keys to the same map, both keys survive. Each scalar inside a map entry is its own register, so two devices that edit *different fields* of the same entry both keep their changes. Two devices that edit the *same* field fall back to last-writer-wins for that field.
- **Arrays.** An array is a register. If one device appends an element and another device removes a different element at the same time, the merged document contains one of the two arrays, not a combination.
- **COUNTER.** Increments and decrements from every device are combined. Concurrent `RESTART` operations resolve by last-writer-wins. A `RESTART` also discards every increment that the restarting device had not yet received, even increments made later by the clock (see [RESTART](#restart)).
- **Consistency guarantee.** Ditto guarantees causal consistency across documents and collections within the same database.

Because a MAP merges at every level, a single document can hold many independently editable sub-entities. Nesting carries no special performance penalty; CRDT maps work the same way at every level.

#### What concurrent edits produce

The table shows how two devices' edits to the same document merged in tests with SDK 5.1.0. Both devices were offline when they wrote, and they synced afterwards. Every result was the same on both devices and did not depend on which device wrote first unless the table says so. Use it to check a data model before you ship it: if a row's result is not what your users expect, change the model rather than the merge.

| Device A | Device B | Result after sync |
|---|---|---|
| `SET status = 'A'` | `SET status = 'B'` (later) | `'B'`: the later write wins on every device, even milliseconds apart |
| `SET obj.a = 2` | `SET obj.b = 3` | `{"a": 2, "b": 3}`: different keys of a map both survive |
| `SET obj = {'a': 10}` | `SET obj.b = 20` | `{"a": 10, "b": 20}`: assigning an object merges; it does not replace (see [Assigning an object merges it](#assigning-an-object-merges-it)) |
| `UNSET obj` | `SET obj.c = 5` | `{"c": 5}`: the removed keys stay removed, the new key survives |
| `` UNSET items.`item-1` `` | `` SET items.`item-1`.quantity = 5 `` | The entry survives: `{"quantity": 5}` if the removal was first, `{"quantity": null}` if it was later (see [Arrays and Maps](#arrays-and-maps)) |
| `SET tags = [1, 2, 3]` | `SET tags = [0, 1, 2]` (later) | `[0, 1, 2]`: the whole array is one value; A's change is lost |
| `APPLY n INCREMENT BY 5` | `APPLY n INCREMENT BY 7` | Both are added |
| `APPLY n RESTART WITH 100` | `APPLY n INCREMENT BY 5` (before or after) | `100`: the increment is discarded (see [RESTART](#restart)) |
| `DELETE` | `UPDATE ... SET color = 'blue'` (later) | The document survives with `color = 'blue'`; other fields are missing (see [Husk documents](#husk-documents)) |
| `UPDATE ... SET color = 'blue'` | `DELETE` (later) | The document survives with `color = null`; other fields are missing |
| `INSERT` of a new document | `INSERT` with the same `_id` (for example, a sequential ID) | One document with combined fields; a field both set keeps the later value (see [Document IDs](#document-ids)) |
| Adds a 3 MiB field | Adds another 3 MiB field | A 6 MiB document on both devices, above the hard limit; every later `UPDATE` of it fails (see [Document Size Limits](#document-size-limits)) |
| `INSERT ... INITIAL DOCUMENTS` | Same `_id`, different content | Fields are combined; a field both set is decided by its value, not by time (see [Default Data with INITIAL Documents](#default-data-with-initial-documents)) |

#### Local write semantics you must know

Several MAP behaviors differ from what developers expect from a JSON document store. With the default settings:

| Statement on an existing object `{"a": 1, "b": 2}` | Result | Why |
|---|---|---|
| `UPDATE ... SET obj.a = 10` | `{"a": 10, "b": 2}` | Field-level update |
| `UPDATE ... SET obj = {'c': 3}` | `{"a": 1, "b": 2, "c": 3}` | Assigning an object to a MAP **merges**; it does not replace |
| `UPDATE ... SET obj = {}` | `{"a": 1, "b": 2}` | An empty object adds nothing (the document is still reported as mutated) |
| `UPDATE ... UNSET obj.b` | `{"a": 1}` | `UNSET` is the only way to remove a key |
| `SET obj = 5`, then later `SET obj = {'w': 1}` | `{"a": 1, "b": 2, "w": 1}` | The old map keys come back: overwriting with a scalar does not clear the map |
| `UNSET obj`, then `SET obj = {'w': 1}`, in one transaction | `{"w": 1}` | Clearing first, then writing, replaces the object |
| `INSERT ... ON ID CONFLICT DO UPDATE` with `{"obj": {"c": 3}}` | `{"a": 1, "b": 2, "c": 3}` | Upserts merge too; omitted keys and fields remain |

**✅ DO:**
- Update individual fields with `UPDATE ... SET obj.field = :value`.
- Remove keys explicitly with `UNSET`.
- When an object must be replaced as a whole, either declare it as a register (`COLLECTION orders (shippingAddress REGISTER)`) or run `UNSET` followed by `SET` in one transaction. Only the register guarantees that concurrent edits never mix two versions: with `UNSET` and `SET` the field is still a map, so a nested edit that another device made at the same time can merge into the new object. It can even bring back a key that the replacement removed: in tests, replacing `{street, city, zip}` with `{street, city}` while another device set `zip` kept `zip`.

**❌ DON'T:**
- Assume `SET obj = {...}` or `ON ID CONFLICT DO UPDATE` removes keys that you left out.
- Clear a map with `SET obj = {}` or by assigning a scalar.

```dart
// ✅ GOOD: Update one field of a nested object. Concurrent edits to other
// fields of shippingAddress merge cleanly.
await ditto.store.execute(
  'UPDATE orders SET shippingAddress.city = :city WHERE _id = :id',
  arguments: {'city': 'Lisbon', 'id': 'order-1'},
);

// ✅ GOOD: Remove one key from a map.
await ditto.store.execute(
  'UPDATE orders UNSET shippingAddress.line2 WHERE _id = :id',
  arguments: {'id': 'order-1'},
);
```

To replace a whole MAP value, clear it and then write the new object in one transaction, so no reader sees the intermediate state: see `replaceAddress()` in [Assigning an object merges it](#assigning-an-object-merges-it).

```dart
// ❌ BAD: Expecting this to replace the address. Under the default settings the
// object is merged into the existing map: keys missing from newAddress remain.
Future<void> replaceShippingAddressIncorrectly(
  Ditto ditto,
  String orderId,
  Map<String, dynamic> newAddress,
) async {
  await ditto.store.execute(
    'UPDATE orders SET shippingAddress = :address WHERE _id = :id',
    arguments: {'id': orderId, 'address': newAddress},
  );
}
```

**Why:** The add-wins MAP is what lets offline edits from many devices merge without data loss. The price is that removal must be explicit: Ditto needs to distinguish "this key was not part of my write" from "this key was intentionally removed".

> **Note:** `UNSET` creates removal metadata. Unsetting a very large number of dynamically generated keys over time can degrade performance; unsetting the parent field (or deleting the document) mitigates the accumulation.

#### Choosing a type or shape

| What you want | Use | Example |
|---|---|---|
| A single value where the latest write should win | Scalar field (REGISTER) | `status`, `displayName`, `updatedAt` |
| A group of fields that different devices edit independently | Object (MAP, the default) | `shippingAddress.city`, `settings.theme` |
| An object that must always be replaced as one consistent unit | Object declared as `REGISTER` in every statement | GPS `position: {lat, lon}` |
| A collection of items that several devices add, edit, or remove | Map keyed by item ID | `items: {"<itemId>": {...}}` |
| An ordered list written by a single device, or a list replaced wholesale | Array (REGISTER) | `tags`, a route's `waypoints` |
| A status history or multi-writer ordered list | Timestamp-keyed map (audit log) | `statusLog: {"2026-10-08T10:00:00.000Z": "created"}` |
| A tally that many devices change concurrently | `COUNTER` | `likeCount`, `viewCount` |
| Binary content (images, PDFs) | `ATTACHMENT` | `photo` |
| Unbounded, independently accessed records | A separate collection | `orderEvents`, `orderItems` |

### Strict Mode

`DQL_STRICT_MODE` controls how Ditto types values that a statement does not declare explicitly. **The default is `false`**, and the rest of this guide assumes it. You can check the current value:

```sql
SHOW DQL_STRICT_MODE
```

#### What strict mode changes

| Behavior | `DQL_STRICT_MODE = false` (default) | `DQL_STRICT_MODE = true` |
|---|---|---|
| Undeclared objects | Inferred as `MAP` (field-level merge) | Stored as `REGISTER` (whole-object replacement) |
| Nested update `SET obj.a = 1` on an undeclared object | Merges the single field | Fails with `Unsupported DML operation on REGISTER field` |
| `MAP`, `COUNTER`, `ATTACHMENT` fields | Inferred from the value or operation | Must be declared in every statement, for example `UPDATE COLLECTION orders (metadata MAP) SET metadata.a = 1` |
| `SELECT` / `WHERE` on fields stored as MAP, COUNTER, or ATTACHMENT without a declaration | Values are visible | **Fields are invisible**: `SELECT *` omits them and `WHERE` conditions on them do not match |
| Index use | Indexes are used | Indexes are not used (see the note below) |

> **Note:** With `DQL_STRICT_MODE = true`, the SDK 5.1.0 query planner does not use indexes: `EXPLAIN` shows a full collection scan even for a query on an indexed field (ID lookups are not affected; see [Strict mode and data types](#strict-mode-and-data-types)). Keep the default (`false`) if you rely on indexes for query performance.

#### When to choose strict mode

Choose `DQL_STRICT_MODE = true` **rarely**: only when whole-object replacement semantics are required for almost every object in your data model and you are prepared to declare every MAP, COUNTER, and ATTACHMENT field in every statement. For new applications, keep the default.

If only a few fields need replacement semantics, keep the default and declare those fields as `REGISTER` in each statement that touches them:

```sql
INSERT INTO COLLECTION customers (shippingAddress REGISTER)
DOCUMENTS (:customer)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

```sql
UPDATE COLLECTION customers (shippingAddress REGISTER)
SET shippingAddress = :address
WHERE _id = :id
```

```sql
SELECT * FROM COLLECTION customers (shippingAddress REGISTER)
WHERE _id = :id
```

With the declaration, an upsert or `SET` replaces the address as a whole: keys that are absent from the new value disappear. A nested update such as `SET shippingAddress.city = :city` fails with `Unsupported DML operation on REGISTER field "shippingAddress"`; to change one part of a register object, write the whole object again.

```dart
// ✅ GOOD: The address is a REGISTER, so a concurrent edit can never produce a
// mix of two different addresses (for example, the street of one and the city
// of the other). The declaration appears in every statement.
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

#### Keep type declarations consistent

A field can hold more than one CRDT value at the same time when statements disagree about its type. Each statement reads or writes the value of the type it declares (or infers), and an undeclared `SELECT` shows the most recently written type. Mixed declarations therefore produce results that look like data loss, even on a single device:

| Sequence (default settings) | Result |
|---|---|
| `INSERT INTO COLLECTION o2 (obj REGISTER) ... {"obj": {"a": 1, "b": 2}}`, then an undeclared `UPDATE o2 SET obj.a = 11` | Undeclared `SELECT` returns `"obj": {"a": 11}`: `b` seems to have vanished. The REGISTER value `{"a": 1, "b": 2}` still exists beside a new MAP value |
| Undeclared `INSERT ... {"cnt": 10}`, then `APPLY cnt INCREMENT BY 1` | `cnt` becomes `1`, not `11`: the increment created a new COUNTER that started at 0 |
| `APPLY pn PN_INCREMENT BY 4` twice, then `APPLY pn INCREMENT BY 1` | `pn` becomes `1`: the COUNTER hides the legacy PN_COUNTER value |

**✅ DO:**
- Use the same declaration for a field in **every** `INSERT`, `UPDATE`, and `SELECT` that touches it.
- Keep these statements in one place in your code (for example, a repository class) so they cannot drift apart.

**❌ DON'T:**
- Declare a field as `REGISTER` in one statement and leave it undeclared in another.
- Write a counter field with `SET`, or initialize it with an undeclared `INSERT`.

#### Changing the setting

`ALTER SYSTEM` settings are not persisted. If you choose `DQL_STRICT_MODE = true`, apply it **every time** you open Ditto, after `Ditto.open` and before `ditto.sync.start()`, running queries, or registering observers (subscriptions may be registered before it). See [Applying System Parameters](#applying-system-parameters) for the full startup sequence.

```dart
// Apply on every launch: the value resets to the default when Ditto is reopened.
Future<void> applyDataModelSettings(Ditto ditto) async {
  await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = true');
}
```

#### Peers with different settings

Strict mode is a local setting of each peer. Data syncs between peers regardless of their settings, but **each peer interprets the data with its own setting**. A peer with `DQL_STRICT_MODE = true` does not show undeclared objects that another peer wrote as maps, so nested updates from a `false` peer appear to be missing on the `true` peer, although they have synced correctly. In SDK 5.1.0 tests with one strict and one non-strict peer, the effects were these:
- A nested update such as `SET obj.a = 2` on the strict peer failed with `Unsupported DML operation on REGISTER field "obj"` when `obj` had been written as an object by a strict peer.
- After concurrent edits, an undeclared `SELECT *` kept showing different values for the same document on the two peers.

The remedies are to use the same setting on all peers (recommended) or to declare the fields as `MAP` on the strict peers.

**✅ DO:**
- Use the same `DQL_STRICT_MODE` value on every peer, in every app and backend integration that writes to the same database.
- If a backend writes through the HTTP API, use the `/api/v5/store/execute` endpoint, which supports `DQL_STRICT_MODE = false`.

**❌ DON'T:**
- Mix settings across peers unless every statement on the strict peers declares the map fields it reads.

### Arrays and Maps

Arrays are registers: the whole array is replaced on every write, and when two devices change the same array concurrently, one version wins and the other change is lost silently. Maps keyed by ID merge each entry independently. Choose the shape as follows:

| Use a **map keyed by ID** when | Use an **array** when |
|---|---|
| Several devices may add, edit, or remove items | Only one device writes; others read |
| Items have a natural or synthetic unique ID | Order matters and the list is never edited concurrently |
| You want to update or index individual items | It is a simple list of scalars that you replace wholesale |

**✅ DO:**
- Store collections of editable items as maps keyed by a stable ID (a natural key such as a SKU, or a UUID).
- Keep the item's own data inside the entry, and store any display order as a field (for example, `position`).
- Use arrays for immutable lists or lists that a single device owns.

**❌ DON'T:**
- Store line items, participants, or checklist entries that several devices edit in an array.
- Expect concurrent array edits to merge or to produce duplicates: one device's change disappears without an error.

#### Shapes

```json
// ❌ BAD: Two devices that change different items concurrently both rewrite the
// whole array. After sync, one device's change is gone.
{
  "_id": "order-1",
  "items": [
    { "productId": "p1", "quantity": 2 },
    { "productId": "p2", "quantity": 1 }
  ]
}
```

```json
// ✅ GOOD: Each item is a map entry keyed by its ID. Concurrent additions,
// edits to different items, and edits to different fields of one item merge.
{
  "_id": "order-1",
  "items": {
    "9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87": { "productId": "p1", "quantity": 2, "position": 0 },
    "e41c7a90-2b3d-4c5e-9f60-7a8b9c0d1e2f": { "productId": "p2", "quantity": 1, "position": 1 }
  }
}
```

```json
// ✅ ACCEPTABLE: A list of scalars that is replaced as a whole and usually
// edited by one device.
{
  "_id": "product-42",
  "tags": ["electronics", "gadget"]
}
```

#### Adding, updating, and removing map entries

When the key is known when you write the query, address the entry with a path. Quote keys that contain characters such as `-` with backticks:

```sql
UPDATE orders
SET items.`item-3` = :item
WHERE _id = :id
```

```sql
UPDATE orders
SET items.`item-1`.quantity = :quantity
WHERE _id = :id
```

```sql
UPDATE orders
UNSET items.`item-2`
WHERE _id = :id
```

DQL parameters bind **values**, not field paths, and DQL has no bracket syntax for dynamic keys (`items[:key]` is a parser error). In application code the key is usually a variable. Two patterns cover this without building queries from untrusted strings:

1. **Add or update an entry** by upserting a partial document with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`. Because objects merge, only the entry you pass is written, and unchanged values are not rewritten.
2. **Remove an entry** with `UNSET`, after validating that the key matches a strict pattern (for example, a UUID), and only then placing it inside backticks.

```dart
/// Adds or updates one line item. The key is passed as data, never spliced
/// into the query. Note: if the order does not exist yet, this creates it.
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

> **Note (SDK 5.1.0):** Removing an entry does not win over a concurrent edit of that entry. In tests, one device ran `` UNSET items.`item-1` `` while another device changed `` items.`item-1`.quantity ``:
> - **Removal first, edit later:** the entry stays with only the edited fields, for example `{"quantity": 5}`.
> - **Edit first, removal later:** the entry stays with the edited fields set to `null`, for example `{"quantity": null}`.
> - **Whole entry rewritten after the removal** (`` SET items.`item-1` = :item `` or `DO UPDATE`): the full entry comes back.
>
> These are "husk" entries, like [husk documents](#husk-documents). When devices may edit an entry while another removes it, mark it removed instead (`` SET items.`item-1`.removed = true ``). Either way, make readers skip entries whose required fields are missing or `null` (see `orderSubtotalCents` in [Do not store derived values that can diverge](#do-not-store-derived-values-that-can-diverge)).

**Why:** Splicing unchecked input into a query enables DQL injection. A strict allow-list pattern for map keys keeps the path safe, and all other values still travel as parameters (see [Parameters and Literals](#parameters-and-literals)).

#### Working with arrays

DQL has no element-level assignment (`SET tags[0] = ...` is a parser error). Build the new array in Dart and rewrite the array with the new value; the write replaces the whole register:

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

To find documents whose array contains a value, use `IN` with the array field or `array_contains`:

```sql
SELECT * FROM products WHERE :tag IN tags
```

```sql
SELECT * FROM products WHERE array_contains(tags, :tag)
```

An index on an array field matches only the complete array value, so element lookups such as these scan the collection. Scalar fields inside map entries, by contrast, can be indexed with their full path (see [Creating Indexes](#creating-indexes)).

#### Incremental adoption

You do not have to convert every array at once. Start with the simple shape, and convert an array to a map as soon as you know that more than one device writes it. Keep the collection name and `_id` structure unchanged so that documents stay compatible, but write the map to a **new field** (for example, `lineItems` next to the old `items` array). Writing a map under the array's field name changes its CRDT type: the old array and the new map then coexist under the same key, and app versions that still write the array make the field switch back and forth (see [Changing CRDT types](#changing-crdt-types)).

### Document Structure

#### Prefer field-level updates

Write only what changed: update only the fields that the user changed, so concurrent edits to other fields survive. The rule and its examples are in [Prefer field-level updates over whole-document rewrites](#prefer-field-level-updates-over-whole-document-rewrites); this subsection covers the one case that an upsert does not make safe, a stale in-memory copy.

`ON ID CONFLICT DO UPDATE_LOCAL_DIFF` compares the incoming document with the local document and skips fields whose values are equal (those fields keep their timestamps); every field that differs is written. That suits upserts and re-imports of data that another system owns, but it does not protect a stale copy: if a change from another device has already reached the local store and your in-memory copy still holds the old value, the old value differs from the stored one and is written back. (`DO UPDATE` writes every field you pass, even unchanged ones, which gives those fields new timestamps and can override a concurrent change from another device.) See [INSERT and Conflict Handling](#insert-and-conflict-handling) for all conflict policies.

**❌ DON'T:**
```dart
// ❌ BAD: Writing back a whole in-memory copy after the user changed only the
// status. If another device changed tableNumber to 12 after this copy was
// loaded, the stale value 7 is written back. DO UPDATE_LOCAL_DIFF does not
// prevent this, because 7 differs from the stored 12 (and DO UPDATE would also
// rewrite every unchanged field).
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {'_id': 'order-1', 'status': 'ready', 'tableNumber': 7},
  },
);
```

#### Flat or nested

Both shapes are valid; choose by how the data is edited and read:

- **Group related fields in an object** when they belong together but may be edited separately (for example, `customer.name` and `customer.phone`). Under the default settings each nested field merges independently, and nesting has no special performance cost.
- **Keep fields at the top level** when they are queried and indexed on their own; paths such as `customer.phone` are indexable too, so this is a readability choice more than a performance one.
- **Use a REGISTER object** only when the parts must never mix (see [Strict Mode](#strict-mode)).
- **Avoid unbounded growth** inside one document: a map that keeps receiving new entries forever belongs in its own collection (see [Document Size Limits](#document-size-limits)).

#### Do not store derived values that can diverge

A stored value computed from other fields (a line total, an order total, a remaining stock level) is a separate register. Two devices can update the inputs concurrently, and each recomputes the total from its own partial view. After the merge, the stored total keeps one device's partial result and disagrees with the merged inputs. In tests, the line items merged to 800 while the stored subtotal stayed at 600. Compute derived values when you read them.

```json
// ❌ BAD: subtotal and total are derived. After concurrent edits to items they
// can disagree with the items that actually merged.
{
  "_id": "order-1",
  "items": {
    "item-1": { "unitPriceCents": 1299, "quantity": 2 }
  },
  "subtotalCents": 2598,
  "totalCents": 2858
}
```

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

Aggregates over a collection can be computed in DQL instead of maintained in a stored field or counter:

```sql
SELECT COUNT(*) AS openOrders FROM orders WHERE status = 'open'
```

Distinguish derived values from **snapshot values**. The unit price at the time of sale is a fact about the order, not a derivation: copy it into the line item (`unitPriceCents`) when the item is added, so a later price change in `products` does not alter historical orders.

#### Exclude transient and unnecessary fields

Ditto syncs only the fields that change once a document has replicated, but every stored field still costs storage and memory on every device that holds the document, adds to the initial replication of new documents, and adds to merge cost. Keep documents to durable, shared business data.

**❌ DON'T store in synced documents:**
- UI state: `isExpanded`, `isSelected`, scroll positions.
- Temporary progress flags: `isSaving`, `uploadProgress`.
- Device-local data: local file paths, cache locations.
- Derived values: totals, averages, ages, "days until" values.

**✅ DO:**
- Keep UI and device-local state in widget state, a state-management layer, or local preferences.
- Initialize flags you will filter on when you create the document (for example, `isDeleted: false`), or filter with `coalesce(isDeleted, false) = false`. A missing field is `MISSING`, not `false` (see [MISSING and NULL](#missing-and-null)).

#### Field names

- Field names are always strings. Use one convention (this guide uses camelCase).
- If a field name collides with a DQL keyword or contains special characters, quote it with backticks in queries (for example, `` `value` ``).
- Never name a collection `collection`; it is a DQL keyword.

### Document Size Limits

Ditto enforces two thresholds on the **size of each stored document**:

| Threshold | Default | System parameter | Behavior |
|---|---|---|---|
| Soft limit | 256 KiB (262,144 bytes) | `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` | The write succeeds and a warning is logged |
| Hard limit | 5 MiB (5,242,880 bytes) | `DOCUMENT_SIZE_HARD_LIMIT_BYTES` | `INSERT` and `UPDATE` statements on this device that would exceed it **fail**; the stored document is unchanged. Merges from other devices are not checked (see below) |

Log and error messages:

```text
[Warning] Document `_id = "s300k"` size is 307.4 KB exceeds recommended limit of 262.1 KB bytes and might have reduced performance

Query failed: DQL Internal execution error: Insert failed: <store> Document `_id = "s5m1"` size is 5243067 bytes and exceeds limit of 5242880 bytes
```

In Flutter, a failed statement throws a `DittoException`; catch it like any other DQL error.

> **Note (SDK 5.1.0):** The hard limit is checked only when a device writes, not when changes from other devices merge. In tests, two devices each added a 3 MiB field to the same document while offline. After sync, both devices stored the 6 MiB document; nothing reported an error, and no log line mentioned the merged size. From then on, **every `UPDATE` of that document failed on every device** with `exceeds limit of 5242880 bytes`, until an `UNSET` removed enough data. The same happens when devices use different hard limits: a device with a lower limit receives larger documents from other devices but cannot update them. Keep large or growing data out of documents (attachments, separate collections), so that even combined offline additions stay far below the limit.

**Why the limits matter:** Size affects local storage and memory on every device holding the document, serialization time, CRDT merge cost (which scales with document size, not change size), and initial replication. Over Bluetooth LE (roughly 20 KB/s in practice), a 256 KiB document takes more than 10 seconds to replicate the first time. Later edits sync only the changed fields.

**✅ DO:**
- Design documents to stay well below 256 KiB.
- Store images, PDFs, and other binary content as attachments; attachments are fetched separately and do not count toward the document size (see [Attachments](#attachments)).
- Move data that grows without bound (order history, readings, comments) into its own collection.
- Leave both limits at their defaults. If you change them, change them on every peer in the same release: a device with a lower hard limit cannot update documents that arrive larger than its limit. (A hard limit set below the soft limit was not enforced in 5.1.0.)

**❌ DON'T:**
- Embed base64-encoded files in documents.
- Append to a nested map forever.
- Raise the hard limit to make a large document fit.

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

#### Monitoring size

- Search application logs for `exceeds recommended limit` to find documents above the soft limit.
- Estimate the size of a document with `object_size()`. It returns an approximate size in bytes of the value, which can differ from the stored size, so leave headroom:

```sql
SELECT _id, object_size(o) AS approxBytes
FROM orders AS o
WHERE _id = :id
```

#### Splitting strategies

| Cause of growth | Fix |
|---|---|
| A nested map that keeps receiving entries (history, comments, readings) | Move the entries to their own collection with a reference to the parent (`orderId`) |
| Binary data in a field | Move it to an `ATTACHMENT` field |
| One document that holds data for many unrelated users or locations | Split by owner or location; this usually also simplifies permissions |
| Status history | Keep a bounded audit-log map, or move events to an event collection (see [Event History and Audit Logs](#event-history-and-audit-logs)) |

To bring an oversized document back under the limits, remove the data that made it grow: move large values to attachments or to a separate collection, and remove them from the document with `UNSET`.

### Relationships: Embedding, Separate Collections, and JOIN

Embedding related data in one document remains the default recommendation. JOIN (SDK 5.1+) removes the main read-side cost of separate collections, which makes normalized models practical when one of the criteria below calls for them:

- **Embed when** sub-entities belong to one parent and are read and written with it. Store them as maps keyed by ID: a single write is atomic, the whole document syncs as one unit, and add-wins maps merge concurrent edits to different sub-entities.
- **Use separate collections when** a sub-entity has independent permission scopes, is accessed independently at scale, is shared by many parents, or would push the parent toward the size limits. Product catalogs, order histories, and task assignments can then live in separate collections, and a `JOIN` reads them together without several sequential queries.

JOIN does not change the other trade-offs: a separate collection is a separate sync unit, needs its own subscription, and needs an index on the join key.

#### Decision guide

| Embed in the parent document when the data is... | Use a separate collection when the data is... |
|---|---|
| Read together with the parent (an order and its line items on one screen) | Accessed independently of the parent (a fleet view across all vehicles) |
| Owned by exactly one parent | Shared by many parents (products referenced by many orders) |
| Small and bounded (tens of entries) | Unbounded (events, readings, messages) |
| Covered by the same permissions as the parent | Governed by different permissions (a mechanic may see the car, not the owner's profile) |
| Edited by the same group of writers | Written by different writers or systems (a catalog maintained centrally, orders created in stores) |

Concurrent edits are **not** by themselves a reason to split: a map keyed by ID merges concurrent edits to different entries.

#### Embedding example

```json
{
  "_id": "order-1",
  "storeId": "store-12",
  "status": "open",
  "createdAt": "2026-10-08T10:00:00.000Z",
  "items": {
    "9b2f6c1e-4d0a-4f7e-8a51-3c2d1e0f9a87": {
      "productId": "p1",
      "name": "Espresso",
      "unitPriceCents": 350,
      "quantity": 2
    }
  }
}
```

```dart
// One subscription syncs the order with all of its items, and every write to an
// item is an atomic update of the order document. Register it once in a
// long-lived service and cancel it when it is no longer needed (see StoreSync below).
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE storeId = :storeId',
  arguments: {'storeId': 'store-12'},
);
```

#### Separate collections with JOIN (SDK 5.1+)

`JOIN` works only on data that is already in the local store. It never fetches missing documents from other peers, and it is not allowed in subscriptions (or on Ditto Server). Each joined collection must therefore be synced by its own subscription, and the inner collection needs an index on the join key (a join on `_id` uses an ID lookup and needs no extra index). See [Joining Collections (SDK 5.1+)](#joining-collections-sdk-51) for the full syntax and limits.

```json
// orders
{ "_id": "order-1", "storeId": "store-12", "status": "open" }

// orderItems: storeId is copied from the order so the subscription can filter on it
{ "_id": "item-1", "orderId": "order-1", "storeId": "store-12", "productId": "p1", "quantity": 2 }

// products
{ "_id": "p1", "name": "Espresso", "priceCents": 350 }
```

Create the index once at startup (`IF NOT EXISTS` makes this idempotent):

```sql
CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)
```

Subscribe to each collection separately. A subscription reads a single collection with `SELECT *` (no JOIN or projection), so a child collection cannot be filtered by a field of its parent: copy the filter key (`storeId`) into the child documents when you create them.

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

Join locally, in a one-off query or an observer. Qualify every field with its alias and project the fields you need: with `SELECT *`, each collection's fields are nested under its alias, and an unqualified `_id` in the result is a composite such as `{"i": ..., "p": ...}`.

```sql
SELECT i._id AS itemId, i.quantity, p.name, p.priceCents
FROM orderItems AS i
JOIN products AS p ON p._id = i.productId
WHERE i.orderId = :orderId
ORDER BY p.name
```

```sql
SELECT o._id AS orderId, o.status, i.productId, i.quantity
FROM orders AS o
JOIN orderItems AS i ON i.orderId = o._id
WHERE o._id = :orderId
ORDER BY i.productId
```

The first query drives from `orderItems` through the `idx_orderItems_orderId` index and looks up each product by `_id`. The second needs the same index because `orderItems` is the inner collection. Without a usable index, the statement fails with `Joining to "i" disallowed without appropriate index support`, unless you explicitly allow a scan of that join term with `USE INDEX ""` (see [Joining Collections (SDK 5.1+)](#joining-collections-sdk-51)).

Observe the join with the standard observer pattern (see [Joins in observers](#joins-in-observers) and [Store Observers in Flutter](#store-observers-in-flutter)); an observer registered for one `orderId` must be re-registered in `didUpdateWidget` if that ID can change while the widget is mounted (see [Filter locally instead of re-registering](#filter-locally-instead-of-re-registering)).

**✅ DO:**
- Subscribe to every collection a JOIN reads, and copy the subscription filter key into child documents.
- Index the inner join key, or join on `_id`. Check plans with `EXPLAIN` and suggestions with `ADVISE` (see [ADVISE (SDK 5.1+)](#advise-sdk-51)).
- Treat a missing joined document as normal: the other side may not have synced yet. Use `LEFT JOIN` when the parent must appear without its children.
- When parent and children are created together, write them in one transaction (see [Transactions](#transactions)).

**❌ DON'T:**
- Put a JOIN in `registerSubscription`; it is rejected with `Unsupported feature: Joining`.
- Assume JOIN fetches data from other peers.
- Split a small, bounded, single-owner sub-entity into its own collection only because JOIN now exists.

**Why:** A separate collection is a separate unit of sync. The parent can arrive before its children, permissions apply per document, and a peer can receive only part of a multi-document transaction when it, or a peer it receives the data through, does not subscribe to all of the documents involved (see [Transactions](#transactions)). Embedding avoids all three concerns; JOIN makes the separate-collection model pleasant to read when one of the decision criteria calls for it.

#### Copying values versus embedding

Embedding (the order owns its items) is different from copying another entity's values into a document. Copy a value only when it is a snapshot that must not change with the source (the price at the time of sale), or when a subscription needs it as a filter key (`storeId` in `orderItems`). For values that should always be current (a product's name in a catalog screen), reference the other document by ID and JOIN at read time.

### Document IDs

Every document has an `_id` that is unique within its collection. If you omit `_id`, Ditto generates one. Do not depend on the format of generated IDs; generate your own when other code needs to know or construct the ID.

#### Allowed values

| `_id` value | Accepted |
|---|---|
| String | ✅ Recommended |
| Object (composite key), for example `{"storeId": "s1", "orderId": "..."}` | ✅ Recommended when you need scoping or grouping |
| Integer, boolean, array | ✅ Accepted, but not recommended |
| Floating-point number | ❌ `Floats are not supported in document IDs` |
| `null` | ❌ `Null document ID not allowed` |

Key order inside a composite `_id` does not matter: `{"storeId": "s1", "orderId": "o1"}` and `{"orderId": "o1", "storeId": "s1"}` identify the same document.

#### IDs are immutable

`UPDATE orders SET _id = ...` fails with ``The document id `_id` cannot be modified``. To "change" an ID, copy the document to a new `_id` and remove the old one, in one transaction. Removing the old document has the usual deletion trade-offs (see [DELETE and Tombstones](#delete-and-tombstones) and [Soft Delete](#soft-delete)), and every reference to the old ID must be updated, so choose IDs carefully up front.

A query result contains plain values, not CRDT types. Declare in the `SELECT` and in the `INSERT` the same types that every other statement on the collection uses (see [Keep type declarations consistent](#keep-type-declarations-consistent)); otherwise the copy stores a counter as a plain number and an attachment token as a map, and a field read with a different declaration (for example, a MAP read as a `REGISTER`) is missing from the copy. With `DQL_STRICT_MODE = true`, declare the `MAP` fields as well.

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

#### Generation strategies

| Strategy | Use when | Notes |
|---|---|---|
| **UUID v4** (primary recommendation) | Almost always | 122 random bits; independent devices never coordinate. Use a maintained package (for example, `uuid` on pub.dev) or the helper below |
| **ULID** or another time-ordered random ID | You want IDs that sort roughly by creation time | Ordering follows each device's clock, so it is only approximate across devices; the ID reveals its creation time |
| **Composite object** | Permissions or subscriptions are scoped by owner, location, or tenant; you group documents by a parent | Combine stable scope fields with a UUID: `{"storeId": "s1", "orderId": "<uuid>"}` |
| **Natural key** | The domain already has a globally unique, immutable key (a SKU, an email address used as an account key) | Two devices that create the same entity intentionally end up with one document whose fields merge |
| **Generated by Ditto** (omit `_id`) | Nothing else needs to know the ID before the insert | Read it back with `result.mutatedDocumentIDs()` |

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
        // utcTimestamp() is defined in the Timestamps section.
        'createdAt': utcTimestamp(),
      },
    },
  );
  return orderId;
}
```

#### Composite IDs for permission scoping and grouping

Ditto permission rules are queries on `_id` and its subfields. A hierarchical composite `_id` lets you grant access at any level, for example a whole region (`"_id.region == 'eu'"`) or a single store (`"_id.storeId == 'store-12'"`); see [Design `_id` for permission scoping](#design-_id-for-permission-scoping) for the rule format. The same subfields can filter subscriptions and queries (`WHERE _id.storeId = :storeId`), and they can be indexed. Filtering on the complete `_id` value uses a direct ID lookup.

```dart
Future<void> createStoreOrder(
  Ditto ditto, {
  required String region,
  required String storeId,
  required String orderId,
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': {'region': region, 'storeId': storeId, 'orderId': orderId},
        'status': 'open',
      },
    },
  );
}

// Each store device syncs only its own store's orders. The caller owns the
// returned subscription and cancels it when it is no longer needed.
SyncSubscription subscribeToStore(Ditto ditto, String storeId) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE _id.storeId = :storeId',
      arguments: {'storeId': storeId},
    );
```

```sql
CREATE INDEX IF NOT EXISTS idx_orders_id_storeId ON orders (_id.storeId)
```

Put only **immutable** attributes into a composite `_id`. A store that might move to another region, or an order that might be reassigned to another store, needs those values as regular fields instead.

#### Never use sequential or timestamp-only IDs

Devices that are offline cannot coordinate a sequence. Two of them will generate the same "next" ID, and after sync the two documents become one document whose fields merge: data from different orders ends up mixed together. Timestamp-only IDs fail the same way whenever two devices create a record in the same millisecond, and device clocks are not reliable anyway (see [Timestamps](#timestamps)).

```dart
// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
String badSequentialId(int dailyCount) => 'order-$dailyCount';

// ❌ BAD: Collides when two devices write within the same millisecond.
String badTimestampId() => 'order-${DateTime.now().millisecondsSinceEpoch}';
```

#### Human-readable display IDs

Customers and staff need short numbers such as "#A-0042". Keep them **separate from `_id`**, and treat them as labels rather than unique keys. One approach that avoids coordination is to prefix with a stable device or terminal code that you assign, and to show the date alongside the number:

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
        'createdAt': utcTimestamp(), // see the Timestamps section
      },
    },
  );
}
```

### Counters

A `COUNTER` field holds an integer that any device can increment or decrement. Increments and decrements from all devices are combined, so concurrent changes add up instead of overwriting each other. Counter operations use the `APPLY` clause, not `SET`:

| Operation | Statement |
|---|---|
| Increment or decrement | `APPLY f INCREMENT BY n` (use a negative `n` to decrement; `n` must be an integer) |
| Set to a specific value | `APPLY f RESTART WITH n` |
| Reset to zero | `APPLY f RESTART` |

Type declarations use the `COLLECTION` keyword: `UPDATE COLLECTION products (viewCount COUNTER) ...`. Writing `UPDATE products (viewCount COUNTER) ...` without `COLLECTION` is a parser error (`Missing SET and/or UNSET clause`).

#### Declarations

With the default settings:

| Statement | Declaration `(f COUNTER)` |
|---|---|
| `INSERT` that sets an initial value | **Required**. An undeclared `INSERT` stores the number as a REGISTER; a later `INCREMENT` then starts a separate counter at 0 (5, then `INCREMENT BY 1`, gives 1) |
| `UPDATE ... APPLY` | Optional. `APPLY` creates the counter if the field does not exist yet |
| `SELECT` | Optional. The current value is returned as a number |

With `DQL_STRICT_MODE = true`, the declaration is required in every statement. This guide declares the counter in every statement so that the code works in both modes and follows [Keep type declarations consistent](#keep-type-declarations-consistent).

```sql
INSERT INTO COLLECTION products (viewCount COUNTER)
DOCUMENTS (:product)
```

```sql
UPDATE COLLECTION products (viewCount COUNTER)
APPLY viewCount INCREMENT BY 1
WHERE _id = :id
```

```sql
SELECT * FROM COLLECTION products (viewCount COUNTER)
WHERE _id = :id
```

```dart
Future<void> createProduct(Ditto ditto, String productId, String name) async {
  await ditto.store.execute(
    'INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)',
    arguments: {
      'product': {'_id': productId, 'name': name, 'viewCount': 0},
    },
  );
}

Future<void> recordView(Ditto ditto, String productId) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (viewCount COUNTER)
    APPLY viewCount INCREMENT BY 1
    WHERE _id = :id
    ''',
    arguments: {'id': productId},
  );
}
```

`APPLY` can be combined with `SET` in one statement; write `APPLY` first:

```sql
UPDATE COLLECTION inventory (stockCount COUNTER)
APPLY stockCount INCREMENT BY :delta
SET lastAdjustedAt = :now
WHERE _id = :id
```

#### RESTART

`RESTART WITH n` sets the counter to a specific value and `RESTART` sets it to zero. When devices perform `RESTART` operations concurrently, the last write wins.

> **Note (SDK 5.1.0):** A `RESTART` discards **every increment that the restarting device had not received when it ran the restart**. That includes increments that other devices make *after* the restart (by the clock) until the restart reaches them. Only increments made after a device has received the restart are added to the new value. In tests with two peers, a counter at 10 was restarted with 100 on one peer while the other peer incremented it by 5. The result was 100 in every order and role (32 trials). When the restart had already synced before the increment, the result was 105.

A typical consequence: a stock recount with `RESTART WITH :counted` silently erases the sales that offline devices record until they receive the recount.

Use `RESTART` only for occasional corrections made by one authority while no other device is incrementing the same counter unsynced, for example a recount done while every till is online and in sync. If devices keep recording changes offline during a recount, keep the recounts and the changes as separate event documents and derive the stock from them (see [When counters are appropriate](#when-counters-are-appropriate)).

```dart
// Run only while every device that increments stockCount is online and in
// sync; increments that this device has not received yet are discarded.
Future<void> recordStockCount(Ditto ditto, String itemId, int counted) async {
  await ditto.store.execute(
    '''
    UPDATE COLLECTION inventory (stockCount COUNTER)
    APPLY stockCount RESTART WITH :counted
    WHERE _id = :id
    ''',
    arguments: {'id': itemId, 'counted': counted},
  );
}
```

#### When counters are appropriate

| ✅ Good fit | ❌ Poor fit, and what to use instead |
|---|---|
| Likes, votes, view counts | **Unique sequence numbers** (invoice or ticket numbers): two offline devices both read 41 and both produce 42. Use UUIDs plus a display label (see [Document IDs](#document-ids)) |
| Usage metrics and tallies from many devices | **Balances that must be validated** (account balances, "never below zero"): a counter cannot enforce a constraint, and concurrent decrements can drive it negative. Record transactions as events and validate when you derive the balance |
| Inventory adjustments where every device records its own sales or receipts | **Values derivable from documents you already store** (number of open orders): compute them with a query such as `SELECT COUNT(*) ...` |
| Values recalibrated occasionally with `RESTART WITH`, while all devices that change them are in sync | **Fractional amounts**: `COUNTER` is integer-only (`INCREMENT BY 1.5` fails with `Expected 1.5 to be an integer value`). Count in minor units such as cents |

**❌ DON'T:**
- Initialize a counter with an undeclared `INSERT`.
- Overwrite a counter with `SET`; use `RESTART WITH`.
- Mix `COUNTER` and the legacy `PN_INCREMENT` operator on one field.
- Use `RESTART WITH` to recalibrate a counter that other devices keep changing while offline.

**Why:** Counters (`COUNTER`, and the legacy `PN_COUNTER`) are the only CRDT types that add concurrent changes together. Everything else (registers, map entries) keeps one of the concurrent values, so `SET stock = stock - 1` on two devices loses one of the decrements.

```dart
// ❌ BAD: Read-modify-write on a register. Two devices that each sell one item
// while the stock is 10 both write 9; after sync the stock is 9 instead of 8.
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

### Event History and Audit Logs

When every change matters (status transitions, adjustments, sensor readings), record each change as a new fact instead of overwriting one field. Three patterns cover most needs.

#### Pattern 1: Audit-log map inside the document

For a bounded history that belongs to one document, such as an order's status transitions, store a **map keyed by a millisecond-precision ISO-8601 UTC timestamp**. Each device adds its own keys, and add-wins merge keeps every entry whose key is distinct. Two transitions recorded in the same millisecond on different devices share a key, and only one of them is kept; if that matters, append a device identifier to the key (for example, `2026-10-08T10:05:12.437Z_t3`), which keeps the keys sortable by time. Derive the current status when you read the document.

```json
{
  "_id": "order-1",
  "statusLog": {
    "2026-10-08T10:00:00.000Z": "created",
    "2026-10-08T10:05:12.437Z": "confirmed",
    "2026-10-08T10:30:45.891Z": "shipped"
  }
}
```

```dart
/// Appends a status transition. The timestamp key is passed as data inside a
/// partial document; unchanged entries are not rewritten.
Future<void> appendStatus(Ditto ditto, String orderId, String status) async {
  final now = DateTime.now().toUtc();
  // Millisecond precision keeps keys consistent across platforms.
  final key = DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': orderId,
        'statusLog': {key: status},
      },
    },
  );
}

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

Common derivation strategies are: the latest timestamp (simple linear workflows), the **most advanced state** (progressions that must not regress), the earliest occurrence ("when did this first happen?"), or custom rules that combine entries. A variant uses the status as the key and the timestamp as the value; it records "did this state happen, and when" but keeps only the latest time for a state that is entered more than once.

#### Pattern 2: Append-only event documents

When history is unbounded, accessed independently, or needed by other devices without the parent, write each event as its **own document** with a UUID `_id`. Events are never updated, so there is nothing to merge, and the parent document stays small.

```dart
Future<void> recordOrderEvent(
  Ditto ditto, {
  required String eventId, // a new UUID
  required String orderId,
  required String storeId,
  required String type,
  required String userId,
}) async {
  await ditto.store.execute(
    'INSERT INTO orderEvents DOCUMENTS (:event)',
    arguments: {
      'event': {
        '_id': eventId,
        'orderId': orderId,
        'storeId': storeId,
        'type': type,
        'userId': userId,
        // utcTimestamp() is defined in the Timestamps section.
        'occurredAt': utcTimestamp(),
      },
    },
  );
}
```

`utcTimestamp()` (see [Timestamps](#timestamps)) gives every `occurredAt` value the same millisecond precision, so `ORDER BY occurredAt` sorts chronologically:

```sql
SELECT * FROM orderEvents
WHERE orderId = :orderId
ORDER BY occurredAt ASC, _id ASC
```

```dart
// ❌ BAD: Appending to an array. Arrays are registers: if two devices append
// concurrently, one of the appended events is lost after sync.
Future<void> appendEventToArray(
  Ditto ditto,
  String orderId,
  List<dynamic> currentHistory,
  Map<String, dynamic> event,
) async {
  await ditto.store.execute(
    'UPDATE orders SET history = :history WHERE _id = :id',
    arguments: {
      'id': orderId,
      'history': [...currentHistory, event],
    },
  );
}
```

Event collections grow forever; plan their cleanup from the start with eviction (see [EVICT](#evict)).

#### Pattern 3: Current state plus history (two collections)

When you need both the latest value with low latency and a complete history, write each change to two collections:

1. **Current state** (`vehicles`): one document per entity, bounded in size. Real-time screens observe this collection.
2. **History** (`vehiclePositions`): one append-only document per change. Analysis queries read this collection.

Write both in one transaction so that local observers never see one without the other (see [Transactions](#transactions)). The position is declared as a `REGISTER` because latitude and longitude from two different readings must never be mixed.

```dart
Future<void> recordPosition(
  Ditto ditto, {
  required String vehicleId,
  required String eventId, // a new UUID
  required double lat,
  required double lon,
}) async {
  // utcTimestamp() is defined in the Timestamps section.
  final recordedAt = utcTimestamp();
  await ditto.store.transaction(hint: 'recordPosition', (tx) async {
    await tx.execute(
      'INSERT INTO vehiclePositions DOCUMENTS (:event)',
      arguments: {
        'event': {
          '_id': eventId,
          'vehicleId': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'recordedAt': recordedAt,
        },
      },
    );
    await tx.execute(
      '''
      INSERT INTO COLLECTION vehicles (position REGISTER)
      DOCUMENTS (:vehicle)
      ON ID CONFLICT DO UPDATE_LOCAL_DIFF
      ''',
      arguments: {
        'vehicle': {
          '_id': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'lastSeenAt': recordedAt,
        },
      },
    );
  });
}
```

Devices can subscribe to what they need: a live map subscribes only to `vehicles`, and an analysis tool also subscribes to `vehiclePositions`. Keep in mind how transactions replicate: a peer that subscribes to only part of the documents a transaction changed receives only that part, and it can relay only that part to other peers (see [Transactions and Sync](#transactions-and-sync)). Peers that need both halves together should subscribe to both collections.

| | Audit-log map | Event documents | Current state + history |
|---|---|---|---|
| Size | Grows the parent document | Parent unaffected | Current state bounded; history grows |
| Atomic with the parent | Yes (one document) | Only with a transaction | Only with a transaction |
| Readable without the parent | No | Yes | Yes |
| Best for | Status and workflow history of one record | Unbounded logs, analytics, compliance trails | Live dashboards plus history |

### Default Data with INITIAL Documents

`INSERT ... INITIAL DOCUMENTS` inserts default data that every peer can create independently, such as built-in categories or default settings. Ditto's [INSERT documentation](https://docs.ditto.live/dql/insert) describes initial documents as inserted "at the beginning of time" and viewed by all peers as the same insert, so several devices can initialize the same default data without overwriting later edits. Initial documents are regular documents: they sync like any other document that a subscription matches. See [INITIAL DOCUMENTS](#initial-documents) for the syntax.

Behavior on a device:

| Situation | Result |
|---|---|
| No document with that `_id` exists locally | The document is inserted |
| A document with that `_id` already exists (including one changed after it was created) | Nothing happens; the existing values are kept |
| The document was deleted earlier on this device | The deletion wins. If the seed is identical to the `INITIAL` insert that created the document, the document stays deleted. If the content differs, or the document was originally created with a regular `INSERT`, a document remains whose fields are `null` (for example, `{"_id": "cfg", "theme": null}`) |
| The document was evicted earlier on this device | The document is inserted again |
| Combined with `ON ID CONFLICT ...` | Parser error; the conflict policy cannot be changed |

Across devices, the same rules apply when the deletion came from another device. In SDK 5.1.0 tests, the effects were these:
- **A seed for an `_id` that another device deleted** stays deleted if its content is identical. If its content differs, it becomes a document with `null` fields **on every device**. This also happens when a newly installed device seeds before it first connects.
- **Two devices that seed the same `_id` with different content** are merged field by field: `{v: 'A', onlyA: 1}` and `{v: 'B', onlyB: 1}` became `{v: 'B', onlyA: 1, onlyB: 1}`. A field that both seeds set is decided by its value, not by which device seeded later. A regular `INSERT` of the same `_id` wins over the seed.

```dart
// Default categories that every device creates at startup. Running this on
// every launch is safe: existing documents, including edited ones, are untouched.
Future<void> seedDefaultCategories(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
    arguments: {
      'categories': [
        {'_id': 'food', 'name': 'Food', 'sortOrder': 1},
        {'_id': 'drinks', 'name': 'Drinks', 'sortOrder': 2},
        {'_id': 'desserts', 'name': 'Desserts', 'sortOrder': 3},
      ],
    },
  );
}
```

Counters can be seeded the same way, with a declaration:

```sql
INSERT INTO COLLECTION inventory (stockCount COUNTER)
INITIAL DOCUMENTS (:item)
```

**✅ DO:**
- Use fixed, well-known `_id` values for seed data so that every device creates the same documents.
- Ship identical seed content in every app version that seeds the same IDs. Do not rely on how peers reconcile initial documents with *different* content for the same `_id`: a key removed from the seed in a new version comes back from devices that still run the old version, and a changed seed turns IDs deleted elsewhere into documents with `null` fields.
- Use soft delete (an `isArchived` flag) for seed documents that users may remove if the seed content may change in a later app version: seeding a deleted ID with different content leaves a document with `null` fields.

**❌ DON'T:**
- Use a regular `INSERT` for shared defaults on every device: the second run fails with `Identifier conflict on document "...": using FAIL conflict policy`, and `ON ID CONFLICT DO UPDATE` would overwrite users' edits.
- Use `INITIAL DOCUMENTS` for data that only one device should create (orders, events); use a regular `INSERT` with a new UUID.
- Use `INITIAL DOCUMENTS` to keep data off the network. Whether data syncs is decided by subscriptions.

### Schema Evolution

Ditto is schemaless: documents in a collection can have different fields, and sync stores and replicates them without validation. In a mesh, however, devices run different app versions for weeks or months, so a schema change must work while old and new versions read and write the same data.

#### Prefer additive changes

Adding a field needs no special pattern. Old app versions ignore fields they do not know; new versions must tolerate documents that do not have the field yet (`MISSING`).

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

Instead of changing the meaning or unit of a field (`mileage` from miles to kilometers), **add a new field** (`mileageKm`) and let each version read the field it understands.

**❌ DON'T** change a field's type, remove it, or rename it without a versioning pattern. Old peers may crash or show wrong data. A change of CRDT type on an **indexed** field (for example, from a REGISTER to a MAP) can also make queries return wrong results, because only the most recently written CRDT type of a field is indexed (see [Strict mode and data types](#strict-mode-and-data-types)).

#### Pattern 1: Schema version in a composite `_id`

Store the schema version as a subfield of `_id`. Because `_id` is immutable, an `UPDATE` cannot change a document's version by accident, and a new-version document is a new record that coexists with the old one. Each app version subscribes only to the versions it understands:

```dart
SyncSubscription subscribeToCarsV2(Ditto ditto) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM cars WHERE _id.schemaVersion = :version',
      arguments: {'version': 2},
    );

Future<void> insertCarV2(Ditto ditto, String carId) async {
  await ditto.store.execute(
    'INSERT INTO cars DOCUMENTS (:car)',
    arguments: {
      'car': {
        '_id': {'id': carId, 'schemaVersion': 2},
        'make': 'Hyundai',
        'fuelEconomyMpg': 32,
      },
    },
  );
}
```

#### Pattern 2: A separate collection per breaking version

Write the new schema to a new collection (`cars` to `carsV2`). Subscriptions are per collection, so peers that do not subscribe to `carsV2` never receive it. Prefer this pattern when you change the CRDT type of an indexed field, because each version's index stays isolated.

| | Pattern 1: version in `_id` | Pattern 2: new collection |
|---|---|---|
| Collection name | Unchanged | New per version |
| Subscription | `WHERE _id.schemaVersion = 2` | `SELECT * FROM carsV2` |
| References from other collections | Unchanged | Must point at the new collection |
| CRDT type change on an indexed field | Risky while both versions coexist locally | Safe (separate indexes) |

#### Rolling out a breaking change

1. **Ship a bridge version** that reads both versions (subscriptions for v1 and v2) but still writes v1.
2. **Wait** until the bridge version has reached every deployed device. A v2 write made earlier is invisible to devices that subscribe only to v1.
3. **Ship the writer version** that writes v2 and still reads both.
4. **Retire v1**: once old documents have been removed from the mesh, drop the v1 subscription and model.

Remove old-version documents with `EVICT` (local only, per device) or `DELETE` (propagates as a tombstone); see [Deletion and Storage Management](#deletion-and-storage-management). **Do not backfill** (reading every v1 document and writing a v2 copy): devices that are offline during the backfill reintroduce v1 documents when they reconnect, so you need the cleanup anyway.

#### Changing CRDT types

Changing how a field is typed (an array or a REGISTER object to a MAP, or a number to a COUNTER) is a breaking change too: the old and new values coexist under the same key and statements see different values depending on their declarations (see [Keep type declarations consistent](#keep-type-declarations-consistent)). In tests, an old app version wrote `SET stock = 9` while a new version concurrently ran `APPLY stock INCREMENT BY -1` as a COUNTER. After sync, an undeclared `SELECT` returned a stock of `-1` on both versions, because the new counter started at 0; only a statement that declared the field as `REGISTER` still returned `9`. Introduce a new field with the new type instead (`stockCount` as a COUNTER next to the old `stock` register) and migrate readers as described above.

### Timestamps

Every device stamps documents with its own clock, and device clocks disagree. Store timestamps in a format that DQL date functions understand, and design so that clock differences cannot corrupt your data.

#### Store UTC with a zone designator

Use one of two representations consistently within a field:

| Format | Dart | Notes |
|---|---|---|
| ISO-8601 string in UTC with a zone designator (recommended) | `utcTimestamp()` below (fixed millisecond precision, for example `2026-10-08T10:30:00.123Z`) for values that are sorted or compared; otherwise `DateTime.now().toUtc().toIso8601String()`, whose precision differs by platform (see below) | Human-readable; compares as text when every value uses the same precision |
| Epoch milliseconds (integer) | `DateTime.now().millisecondsSinceEpoch` | Compact; DQL date functions accept epoch milliseconds, and `date_add`, `date_sub`, and `date_trunc` return them for numeric input |

> **Note:** In Dart, `DateTime.now().toIso8601String()` returns local time **without** a zone designator (for example, `2026-10-08T19:30:00.123456`). DQL date functions return `MISSING` for such strings (`date_part`, `date_diff`, `date_add`, `date_cast`, and the others), and no error is raised. Always call `toUtc()` first. <!-- lint-ignore -->

**Use one fixed-precision helper for timestamps that are sorted or compared.** On native platforms (iOS, Android, and desktop), Dart's `toIso8601String()` includes microseconds only when they are non-zero, so one device produces both `.123456Z` and `.123Z`; on the Web it includes only milliseconds (`.123Z`). ISO strings sort chronologically as text only when they share the same format: `'2026-10-08T10:30:45.123456Z'` sorts before `'2026-10-08T10:30:45.123Z'` although it is later, because `4` comes before `Z` in string order, and `'2026-10-08T10:30:45Z'` sorts after `'2026-10-08T10:30:45.123Z'` because `Z` comes after `.`. When a field is used in `ORDER BY`, range filters, or comparisons, produce every value with one helper that fixes the precision, such as `utcTimestamp()` below. Other examples in this guide inline `DateTime.now().toUtc().toIso8601String()` for brevity; use the helper in their place wherever the field is sorted or compared.

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

#### Querying by time

Compare stored timestamps with parameters in the same format. Range filters on a timestamp field can use an index:

```sql
SELECT * FROM orders
WHERE createdAt >= :since
ORDER BY createdAt DESC
```

DQL date functions work with zoned ISO strings and epoch milliseconds. For example, `date_diff(date1, date2, part)` returns `date1 - date2` in the given unit, and `date_format(:epochMs, '')` converts epoch milliseconds to an ISO string. See [DQL Functions and Operators](#dql-functions-and-operators) for the signatures.

```sql
SELECT _id, date_diff(:now, createdAt, 'minute') AS ageMinutes
FROM orders
WHERE status = 'open'
```

#### Clock drift

Device clocks drift and can be set wrong. iOS clocks are usually within 100 ms of accurate time, while Android devices can deviate by several seconds; a device whose time was set manually can be off by much more. Expect timestamps that appear to be in the future, and records created at the same moment on two devices with timestamps seconds apart.

**✅ DO:**
- Treat stored timestamps as approximate information for display, filtering, and retention, not as a source of truth for ordering.
- If precise time is critical, query a time server (NTP) and keep a correction offset in your app.
- Tolerate small negative durations (an "ended" time slightly before a "started" time written by another device).

**❌ DON'T:**
- Rely on your own timestamp fields to decide which of two conflicting writes should win. Ditto resolves concurrent register writes with its own Hybrid Logical Clock, independently of your fields; and if you compare your own timestamps at read time, a device with a fast clock always wins. Where order matters, model the data so that the merge cannot go wrong: a counter, a map keyed by ID, or an audit log with a derivation such as "most advanced state" (see [Event History and Audit Logs](#event-history-and-audit-logs)).
- Use timestamps as document IDs (see [Document IDs](#document-ids)).

---

## Sync and Subscriptions

Ditto uses **query-based sync**: subscriptions tell other peers which documents to send to this device, while `execute`, store observers, and transactions work on the **local store only**.

| API | Reads from | Causes data to sync to this device? |
|---|---|---|
| `ditto.sync.registerSubscription(query)` | Remote peers ("what I want other peers to send me") | ✅ Yes, while sync is running |
| `ditto.store.execute(query)` | Local store | ❌ No |
| `ditto.store.registerObserver(query)` | Local store (live) | ❌ No |
| `ditto.store.transaction(...)` | Local store | ❌ No |

Showing synced data therefore needs both a long-lived subscription, owned by an app-level or feature-level service (see [Subscription Lifecycle](#subscription-lifecycle)), and a local query or observer on the screen (see [Core Principles](#core-principles) and [Where Queries Run](#where-queries-run)).

### Subscription Rules

A subscription query selects whole documents from one collection: `SELECT * FROM <collection> [WHERE <condition>]`. When you call `registerSubscription`, the SDK rejects the features below with an error, even before sync starts. Subscriptions on `system:` collections (such as `system:data_sync_info`) are accepted but have no effect.

| Query feature | Accepted in a subscription? | Error message |
|---|---|---|
| `SELECT * FROM orders` | ✅ Yes | — |
| `SELECT * FROM orders WHERE storeId = :storeId` | ✅ Yes (use parameters) | — |
| Projection (`SELECT _id, status ...`) or aggregate (`COUNT(*)`) | ❌ No | `Unsupported feature: A projection other than wildcard (*)` |
| `DISTINCT` (`SELECT DISTINCT * ...`) | ❌ No | `Unsupported feature: DISTINCT` |
| `GROUP BY` | ❌ No | `Unsupported feature: Grouping` |
| `JOIN` | ❌ No | `Unsupported feature: Joining` |
| `USE IDS` | ❌ No | `Unsupported feature: USE IDS` |
| `LIMIT`, `ORDER BY` | ❌ No (by default) | `Unsupported feature: Limit or Order by` |
| Non-`SELECT` statements | ❌ No | `Unsupported feature: non-SELECT statement in sync subscription` |

Consequences for your design:

- **Subscriptions always sync whole documents.** There is no way to subscribe to some fields of a document. To reduce what a device receives, split rarely needed data into a separate collection or move large binary data into [Attachments](#attachments).
- **Subscriptions cannot join.** If a child collection must be filtered by a key that lives on the parent (for example, `orderItems` by `storeId`), copy that key into the child documents so that the child collection can be subscribed to on its own. `JOIN` remains available for local queries (see [Joining Collections (SDK 5.1+)](#joining-collections-sdk-51)).
- **Use parameters**, never string interpolation, for values in the `WHERE` clause (see [Parameters and Literals](#parameters-and-literals)).

<!-- expect-error -->
```dart
// ❌ BAD: Each of these subscriptions is rejected when it is registered.
void registerInvalidSubscriptions(Ditto ditto) {
  // Projection: subscriptions always sync whole documents.
  ditto.sync.registerSubscription('SELECT _id, status FROM orders');
  // Aggregate.
  ditto.sync.registerSubscription('SELECT COUNT(*) AS n FROM orders');
  // LIMIT / ORDER BY are rejected by default (see below).
  ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId ORDER BY createdAt DESC LIMIT 50',
    arguments: {'storeId': 'store-1'},
  );
  // USE IDS.
  ditto.sync.registerSubscription("SELECT * FROM orders USE IDS 'order-1', 'order-2'");
}
```

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

#### LIMIT and ORDER BY in subscriptions

`LIMIT` and `ORDER BY` are rejected in subscriptions as long as the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` (plural, case-insensitive) has its default value `true`. Setting it to `false` (for example, `ALTER SYSTEM SET DQL_RESTRICT_SUBSCRIPTIONS = false`) allows only `LIMIT` and `ORDER BY`; projections, aggregates, `DISTINCT`, `JOIN`, and `USE IDS` remain rejected.

**Keep the default.** A subscription with `LIMIT` (or `LIMIT` with `ORDER BY`) is a *stateful subscription*: the sync engine must track which documents currently fall inside the limit boundary. Whenever a document inside the boundary is deleted, stops matching the `WHERE` clause, or moves under the `ORDER BY`, Ditto has to invalidate its cache and re-evaluate the query, which degrades sync performance. If you must use one, avoid filtering (`WHERE`) or sorting (`ORDER BY`) on mutable fields when `LIMIT` is used. In most apps, a subscription scoped by a stable key plus a local `ORDER BY ... LIMIT` query gives the same UI without these costs.

> **Note (SDK 5.1.0):** `LIMIT` in a subscription bounds **only the initial download**. In tests, the first sync delivered exactly the top N documents. After that, every new or changed document that matched the `WHERE` clause was synced, whether or not it ranked inside the window, including documents that never did. Documents already received stayed and kept receiving updates. Only documents that existed but were not changed after the subscription started stayed away. A "sync only the latest 50 orders" subscription therefore ends up syncing every matching order that is created or edited later. Bound the synced set with a `WHERE` on a stable key or a time window instead, keep `ORDER BY ... LIMIT` in the local query, and evict what the device no longer needs (see [EVICT](#evict)). `DQL_RESTRICT_SUBSCRIPTIONS` is checked only on the device that registers the subscription; the setting on the device that serves the data makes no difference.

#### Scope subscriptions to what the device needs

**✅ DO:**
- Filter subscriptions by the dimensions that partition your data: tenant, store, region, team, or user.
- Use the same subscription shape on peers in the same role; when peers run the same subscription, any peer with matching documents can serve any other peer.
- Keep subscription predicates simple (flat comparisons such as `storeId = :storeId`); deeply nested `AND`/`OR` trees and deep object paths add server-side processing, and overly complex subscription queries are a likely cause of `503 Service Unavailable` errors from Ditto Server.

**❌ DON'T:**
- Subscribe to an entire large collection on every device "just in case".
- Generate subscription predicates dynamically from arrays or nested structures without reviewing the resulting query strings.

```dart
// ❌ BAD: Every device receives and stores every order of every tenant.
SyncSubscription subscribeToEverything(Ditto ditto) {
  return ditto.sync.registerSubscription('SELECT * FROM orders');
}

// ✅ GOOD: Each device receives only the orders of its own store.
SyncSubscription subscribeToStore(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}
```

**Why:** Subscriptions decide what crosses the network and what each device stores. A well-scoped subscription reduces bandwidth, storage, and CPU on every device in the mesh, and lets the sync engine prioritize the data that matters. An unfiltered subscription is acceptable only for a small reference-data collection that every device needs (for example, a short list of product categories).

### Subscription Lifecycle

Registering, cancelling, or changing a subscription makes peers across the mesh re-evaluate what they owe the device. Ditto advises against doing this often. **Avoid changing subscriptions more often than about every 15 minutes.** In SDK 5.1.0 tests, the network cost of a change itself was small: documents the device already held were not downloaded again. An identical second registration transferred nothing, and re-registering after a cancel fetched only what had changed in between (1.6 KB, against 210 KB for the first download). Each registration is a separate object, though: data keeps syncing until **every** copy of an identical subscription is cancelled.

**✅ DO:**
- Register subscriptions when the data first becomes relevant: at app start, after login, or when the user enters a workspace (store, region, team).
- Own subscriptions in an app-level or feature-level service, not in individual widgets.
- Keep a reference to every subscription you register, and call `cancel()` when its data is no longer relevant (logout, leaving a workspace) or when you register a replacement; subscriptions stay active until cancelled or until the `Ditto` instance is closed.
- Filter what the user sees with local queries and observers on top of a stable subscription.

**❌ DON'T:**
- Register subscriptions in `build()` or on every screen visit.
- Re-register a subscription with new arguments whenever the user changes a filter, search term, or sort order.
- Drop the reference to a subscription without cancelling it. Always release these objects explicitly; do not rely on garbage collection to cancel them.

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

#### Filter locally instead of re-registering

When the user changes a filter, change the **observer**, not the subscription. Observers are local and cheap to replace; subscriptions are mesh-wide.

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

**When re-registering is right:** Change a subscription when the set of data the device *needs* changes, for example when the user switches to a different store or tenant. That happens rarely and fits the 15-minute guideline. Search boxes, tabs, filters, and sort orders should never change subscriptions.

#### Cancelling subscriptions and local data

- **Cancelling does not delete local data.** Documents already received stay in the local store and remain visible to local queries. They stop receiving updates, new documents, and **deletions** from other peers, so a document deleted elsewhere after the cancel stays on this device. To free storage, evict them explicitly (see [EVICT](#evict)).
- **Overlapping subscriptions add up.** A device receives the union of all its active subscriptions. Cancelling one of them leaves the documents that another one still matches in sync.
- **Cancel before you evict.** Evicting documents that still match an active subscription is futile: connected peers notice that the device is missing documents it subscribes to and send them back. Stop the affected subscriptions *before* calling `EVICT`, including every overlapping subscription that also matches the documents: in tests, a document that another active subscription still matched was synced back right after the `EVICT`.
- **Late arrivals:** Data that was already being transferred when you cancelled can still arrive afterwards. If the device must not keep the old store's data, run the eviction again later (for example, on the next app start or in a periodic cleanup).

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

#### Sync stop, close, and inspection

- `ditto.sync.stop()` disconnects from all peers and **pauses** all subscriptions. You do not need to cancel subscriptions to stop syncing; they resume when you call `ditto.sync.start()` again.
- `await ditto.close()` stops sync and marks every subscription as cancelled (`isCancelled == true`); calling `cancel()` afterwards is a safe no-op (see [Resource Cleanup and Shutdown](#resource-cleanup-and-shutdown)).
- `ditto.sync.subscriptions` returns the currently active subscriptions. Use it for debugging (for example, logging `queryString`), but manage subscriptions through the references you keep yourself.

> **Note (SDK 5.1.0):** Do not read `queryArguments` or `queryArgumentsJsonString` from the elements of `ditto.sync.subscriptions`; for subscriptions registered without arguments this can terminate the app. Read only `queryString` and `isCancelled` there, and keep your own references (as `OrderSync` does) when you need the arguments.

### Scope Balancing

Subscription scope is a trade-off. Too broad wastes resources; too narrow can leave devices without data they need, especially in peer-to-peer meshes.

| | Too broad | Too narrow |
|---|---|---|
| Symptoms | High storage use, long initial sync, battery and bandwidth drain | Missing data on devices that are not directly connected to the source, data appearing late |
| Typical cause | Unfiltered subscriptions on large collections | Filters on fields that change often, or relay devices that subscribe to less than the devices behind them |
| Fix | Filter by stable partition keys (tenant, store, region) | Subscribe to the full partition; filter further with local queries |

#### Multi-hop relay

Ditto can relay documents through intermediate devices that are not directly connected to each other. Ditto's [multi-hop sync documentation](https://docs.ditto.live/home/glossary#multi-hop-sync) describes that an intermediate device **can only relay documents it has in its local store**: if its subscription is too narrow, it does not store certain documents and cannot pass them on.

The same limit applies to transactions: a device connected only through a relay with narrower subscriptions can receive only part of a multi-document transaction (see [Transactions and Sync](#transactions-and-sync) for an example).

**✅ DO:**
- Give devices in the same role the same subscriptions, so that each of them can serve the others.
- On devices that act as relays or hubs (for example, a fixed tablet that many handhelds connect to), subscribe to at least everything the devices behind them need.
- On a hub that more than six devices connect to over TCP, raise the per-transport connection limit before starting sync (see [Transport Configuration](#transport-configuration)).
- Filter subscriptions on stable fields that do not change during a document's lifetime (`storeId`, `tenantId`, `region`).
- Ensure sufficient connectivity with peers that have broader subscription sets.

**❌ DON'T:**
- Give a relay device a narrower subscription than the devices that depend on it.
- Filter subscriptions on fields that change often (`status`, `assignee`) and expect every device to follow each document through all of its states (soft-delete flags are a special case; see the next paragraph).

> **Note (SDK 5.1.0):** A document that stops matching a subscription becomes a **frozen copy** on the device. In tests, the device received the change that made the document stop matching (for example `status: 'closed'`), and then nothing more: later edits, and even the deletion of the document, did not arrive. Local queries keep returning the stale copy. When the document matches again, it arrives in its latest state. Filter such documents out locally, and evict them when the device no longer needs them.

**Soft delete:** Keep soft-deleted documents inside the subscription at least until every device has received the flag, and filter them out in local queries. See [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup) for the two subscription variants and how each affects cleanup.

### Sync Scopes

Sync scopes control, per collection, **where a device sends** its documents. They are configured with the system parameter `USER_COLLECTION_SYNC_SCOPES`, which maps collection names to one of these values:

| Sync scope | Behavior |
|---|---|
| `"AllPeers"` (default) | Sync with Ditto Server and with other Small Peers |
| `"BigPeerOnly"` | Sync only with Ditto Server, not with other Small Peers |
| `"SmallPeersOnly"` | Sync only with other Small Peers, not with Ditto Server |
| `"LocalPeerOnly"` | Do not sync this collection at all |

```sql
ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = {'localDrafts': 'LocalPeerOnly', 'kitchenTickets': 'SmallPeersOnly'}
```

```dart
// ✅ GOOD: Apply sync scopes after every Ditto.open and before sync.start().
Future<void> applySyncScopesAndStart(Ditto ditto) async {
  await ditto.store.execute(
    "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = {'localDrafts': 'LocalPeerOnly', 'kitchenTickets': 'SmallPeersOnly'}",
  );
  ditto.sync.start();
}
```

**✅ DO:**
- Set `USER_COLLECTION_SYNC_SCOPES` after every `Ditto.open` and **before** `ditto.sync.start()`; `ALTER SYSTEM` settings are not persisted, and setting scopes late can let data sync unintentionally (see [Applying System Parameters](#applying-system-parameters)).
- Apply the same sync scopes on **every** device that can store the collection (devices that write it, subscribe to it, or relay it); a scope is checked by the device that sends the data, so a device without the setting can send the collection to Ditto Server. A scope also does not stop a device from *receiving* the collection from devices without it.
- Remember that a scope set while sync is running applies to later changes immediately, without a restart. Copies that other devices already received stay there as frozen copies: in tests, they received no further updates.
- Quote the collection names (map keys) in the literal, or build the statement from a reviewed constant.
- List every scoped collection in one statement: each `ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES` replaces the whole map, so collections left out of a later statement lose their scope.

**❌ DON'T:**
- Treat sync scopes as an access-control mechanism; they control what *this* device sends, not what other devices are allowed to read (use permissions for that, see [Security](#security)).
- Apply sync scopes to system collections (names starting with `__`); the update fails.
- Rely on sync scopes for remote query requests; they are not enforced there.

**Why:** Sync scopes and subscriptions are complementary. Subscriptions decide what a device *receives*; sync scopes limit where a device *sends* data, even if another peer subscribes to it. Typical uses are device-local drafts and caches (`LocalPeerOnly`) and high-frequency, mesh-local data such as kitchen display tickets (`SmallPeersOnly`).

### Monitoring Sync Status

Ditto is offline-first, so there is no single "synced" state. You can still show users useful progress information with two building blocks:

1. **Commit IDs:** every local `INSERT`, `UPDATE`, `DELETE`, or `EVICT` returns a `commitID` on its `QueryResult` (`int?` in Flutter). Commit IDs are device-specific and increase monotonically. `SELECT` returns `null`, and inside a transaction the value is only assigned after the commit.
2. **`system:data_sync_info`:** a local-only virtual collection with one document per peer connection.

| Field | Meaning |
|---|---|
| `_id` | Peer identifier |
| `is_ditto_server` | `true` for Ditto Server connections |
| `documents.sync_session_status` | `"Connected"`, `"Not Connected"`, or `"Disabled"` |
| `documents.synced_up_to_local_commit_id` | Highest local commit ID that this peer has confirmed |
| `documents.last_update_received_time` | Unix timestamp of the last data received from this peer |

A local write has reached a peer when that peer's `synced_up_to_local_commit_id` is greater than or equal to the write's `commitID`.

> **Note (SDK 5.1.0):** A statement that changes nothing still returns a `commitID`. Examples are `ON ID CONFLICT DO NOTHING` or `DO UPDATE_LOCAL_DIFF` on an existing document, and an `UPDATE` whose `WHERE` matches nothing. Peers do not confirm such an empty commit by itself; `synced_up_to_local_commit_id` passes it only with the next commit that syncs. Besides your own writes, Ditto makes an internal commit about every 30 seconds, so a wait on such an ID ends after up to about 30 seconds instead of immediately. Track a `commitID` only when `mutatedDocumentIDs()` is not empty.

> **Note (SDK 5.1.0):** `sync_session_status` reacts slowly to disconnections. In tests, a peer's row stayed `"Connected"` for about 73 seconds after the other peer had closed Ditto or called `ditto.sync.stop()`, on both devices, while the presence graph dropped the peer immediately. Use `sync_session_status` for upload progress, and use [Presence](#presence) for "connected now" indicators.

```sql
SELECT * FROM system:data_sync_info WHERE is_ditto_server = true
```

**✅ DO:**
- Use sync status to **enhance** the user experience (an "uploaded" check mark, a pending-changes badge), never to block the user from working.
- Query `system:data_sync_info` with `execute` when you need a snapshot (for example, when the user opens a status screen).
- Keep observer callbacks on `system:data_sync_info` trivial and update the UI only when the derived value actually changes.
- Track only the commit IDs that matter (payments, submitted forms) and forget them once confirmed.
- Check `mutatedDocumentIDs()` before tracking a `commitID`; skip statements that changed nothing.

**❌ DON'T:**
- Register observers on `system:data_sync_info` in many widgets. Each one re-reads the sync state of every connection, and Ditto's documentation describes them as firing on a fixed 500 ms interval. (In SDK 5.1.0 tests on Flutter and JavaScript, an idle observer fired only when the rows changed, about once in 10 seconds, so do not rely on either a timer or a quiet observer.)
- Do heavy work (JSON decoding of large structures, database writes, network calls) in such an observer.
- Register subscriptions on `system:data_sync_info`; it is local-only, so such a subscription is accepted but has no effect.
- Expect `system:data_sync_info` on platforms with in-memory storage such as web browsers.
- Expect attachment transfer progress here; `system:data_sync_info` does not report it (use the fetch events, see [Attachments](#attachments)).

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
    // May fire often (documented as every 500 ms), so keep the callback trivial.
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
// ✅ GOOD: An upsert may change nothing; only then is there nothing to track.
Future<int?> saveSettings(Ditto ditto, Map<String, dynamic> settings) async {
  final result = await ditto.store.execute(
    'INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {'settings': settings},
  );
  // An unchanged document still gets a commitID, but peers confirm it only
  // with a later commit (up to about 30 seconds later).
  return result.mutatedDocumentIDs().isEmpty ? null : result.commitID;
}
```

**Why:** `system:data_sync_info` is cheap to read, but Ditto documents observers on it as timer-driven. A single small observer per relevant screen is fine; dozens of observers that may rebuild widgets twice per second are not. For connectivity information (which peers are nearby, whether Ditto Server is connected), use the presence API instead (see [Presence](#presence)).

---

## Observing Changes

A **store observer** is a live local query. Ditto re-runs it whenever a local write or an incoming sync changes its result, and delivers the new result to your code. Observers never cause data to sync; pair them with a subscription (see [Sync and Subscriptions](#sync-and-subscriptions)).

Changes that arrive through sync are delivered in batches, not one callback per remote write. In SDK 5.1.0 tests, 20 documents written one by one on another device arrived in two callbacks, and 20 quick updates of one document arrived in two or three, ending at the latest value. A transaction from another device arrived as one callback that contained all of its documents, never a partial state. Do not use observer callbacks to count or log every remote change; intermediate states can be skipped.

Flutter offers three ways to register an observer:

| API | Status | Returns | Backpressure | Use for |
|---|---|---|---|---|
| `registerObserver` | Stable | `StoreObserver` | None (results are delivered as soon as they are ready) | UI updates and other fast, synchronous work (**default**) |
| `registerObserverV2` | **(Experimental)** (SDK 5.1+) | `StoreObserverV2` | Automatic: follows pause/resume of the `changes` stream | Slow or asynchronous per-update work with `await for` |
| `registerObserverWithSignalNext` | **(Experimental)** (SDK 5.1+) | `StoreObserverV2` | Manual: call `signalNext()` when ready | Explicit control over when the next update may arrive |

All three accept only `SELECT` queries and take parameters through `arguments:`.

### Store Observers in Flutter

The recommended pattern registers the observer **without** `onChange`, consumes the `changes` stream with a single `StreamSubscription`, and cancels both in `dispose()`:

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
- Copy plain values out of the result (`item.value`, or your own model objects) before storing them in state; do not keep `QueryResult` or `QueryResultItem` objects around (see [Working with Query Results](#working-with-query-results)).
- Add `ORDER BY` whenever the order of results matters; without it, the order of observer results is not guaranteed.
- Cancel the stream subscription **and** the observer in `dispose()`.

**❌ DON'T:**
- Pass `onChange` and leave the `changes` stream unconsumed (see the note below).
- Listen to `changes` twice; it is a single-subscription stream.
- Create an observer per list item; observe the list once and pass values down.

> **Note (SDK 5.1.0):** When an observer is registered with `onChange`, every result is **also** queued in its `changes` stream. If nothing listens to `changes`, those queued results stay in memory for the lifetime of the observer, so memory use grows with every update. The same applies to `registerObserverV2`, which starts observing as soon as it is registered, with or without `onChange`: listen to its `changes` stream right after registering it, never later. Use the pattern above (no `onChange`, consume `changes`). If you need `onChange`, also drain the stream, for example with `observer.changes.listen((_) {})`.

```dart
// ❌ BAD: onChange only; the unconsumed changes stream keeps every result in memory (SDK 5.1.0).
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

#### Stable ordering

Observer results have no guaranteed order unless the query has an `ORDER BY` clause. Lists that re-order randomly on every update are a common symptom. Produce the timestamp you sort by with one fixed-precision helper (see [Timestamps](#timestamps)).

```dart
// ❌ BAD: No ORDER BY; rows may change position between updates.
StoreObserver observeTasksUnordered(Ditto ditto) =>
    ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false');

// ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps.
StoreObserver observeTasksOrdered(Ditto ditto) => ditto.store.registerObserver(
      'SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id',
    );
```

#### Observer lifecycle and cleanup

| Behavior (`registerObserver`) | Consequence |
|---|---|
| Without `onChange`, the observer starts querying only when `changes` is first listened to | An observer that is registered but never listened to produces no events and does no query work, but still holds resources until cancelled |
| With `onChange`, the observer starts immediately | Results are delivered to `onChange` and also buffered in `changes` until something listens (see the note above); listen right after registering |
| `changes` is a single-subscription stream | A second `listen()` throws a `StateError` (`Bad state: Stream has already been listened to.`), including after the first subscription was cancelled |
| Cancelling the `StreamSubscription` does not cancel a `StoreObserver` | Always call `observer.cancel()` as well |
| `observer.cancel()` closes the `changes` stream | A pending `await for` loop over `changes` ends |
| `await ditto.close()` marks observers as cancelled (`isCancelled == true`) but does not close the `changes` stream of a `StoreObserver` or `StoreObserverV2` | Do not rely on `close()` to end an `await for` loop over observer results; cancel observers explicitly before closing |

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

#### Keep observer callbacks fast

`registerObserver` has no backpressure: Ditto never waits for your code before delivering the next result. Pausing the `changes` stream of a `StoreObserver` does not slow Ditto down; results queue up in the stream instead.

**✅ DO:**
- Keep the listener synchronous and short: copy values, map them to model objects, call `setState`.
- Move expensive decoding or computation off the UI isolate (for example, with Flutter's `compute()` on plain values copied out of the result).
- Use `registerObserverV2` or `registerObserverWithSignalNext` when each update triggers slow or asynchronous work (see [Backpressure (SDK 5.1+)](#backpressure-sdk-51)).
- Throttle UI updates for very busy collections if the user cannot perceive every intermediate state.

**❌ DON'T:**
- `await` network calls, file I/O, or database writes inside a `registerObserver` listener; the next results keep arriving while you wait.
- Write to the same collection from inside its observer without a guard; each write triggers the observer again.

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

### Backpressure (SDK 5.1+)

Two experimental observer APIs (SDK 5.1+) let your code control when the next result is delivered. Both return a `StoreObserverV2`. While your code is busy, Ditto holds back further updates and then delivers the latest state, so intermediate results are merged instead of queued. The exact delivery rules for each API are listed below.

#### registerObserverV2 (Experimental)

`registerObserverV2` signals readiness automatically after each result has been added to the `changes` stream, and it follows the stream's pause and resume. Because `await for` pauses its subscription while the loop body runs, slow `async` work in the loop body applies backpressure without extra code.

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

Behavior:

- While the stream is paused, Ditto stops delivering after the update that arrived right at the pause. On resume, that held update and the latest state are delivered; intermediate states are merged.
- Leaving the loop (`break`, `return`, or an exception) cancels the stream subscription, and cancelling the stream subscription of a `StoreObserverV2` also cancels the observer.
- `observer.cancel()` closes the stream and ends the loop; `ditto.close()` does not, so cancel the observer before closing.
- `signalNext()` has no effect on observers registered with `registerObserverV2`.

#### registerObserverWithSignalNext (Experimental)

`registerObserverWithSignalNext` delivers one result and then waits until you call `signalNext()` (the callback parameter or `observer.signalNext()`). **If you never call it, the observer stops delivering updates.** Do not use pause and resume on the `changes` stream of such an observer; the SDK logs a warning if you do.

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

The `onChange` callback of `registerObserverWithSignalNext` receives the `signalNext` function as its second parameter, but results passed to `onChange` are also queued in `changes`, so the note in [Store Observers in Flutter](#store-observers-in-flutter) applies here too. Consuming `changes` and calling `observer.signalNext()`, as above, avoids the issue.

#### Choosing an observer API

| Situation | Recommended API |
|---|---|
| Updating widgets from a query result | `registerObserver` + `changes` (stable) |
| Each update triggers slow or `async` work (upload, file export, heavy aggregation) and you can write it as a loop | `registerObserverV2` + `await for` **(Experimental)** |
| The work for an update finishes in a different place than where the update arrives (for example, after an animation or an external callback) | `registerObserverWithSignalNext` **(Experimental)** |
| Very frequent updates where only the latest state matters | `registerObserverV2` with a slow consumer (intermediate states are merged), or throttle a `registerObserver` listener |

The experimental APIs may change in a future release; the stable `registerObserver` remains the default choice for UI code.

#### Backpressure on other platforms

Backpressure works differently on each platform. Do not port Flutter code one-to-one.

| Platform | Default observer | Backpressure |
|---|---|---|
| Flutter | `registerObserver(query, arguments:)` + `changes`; no backpressure | `registerObserverV2` (auto, follows pause/resume) or `registerObserverWithSignalNext` (manual); both experimental |
| JavaScript | `registerObserver(query, handler, args)` signals the next update automatically when the handler **returns**; an `async` handler is not awaited | `registerObserverWithSignalNext(query, (result, signalNext) => {...}, args)` for asynchronous work |
| Swift | `registerObserver(query:arguments:deliverOn:handler:)` signals automatically when the handler returns; delivered on the main queue by default | `handlerWithSignalNext:` for manual `signalNext()`; pass `deliverOn:` to move heavy work off the main queue |
| Kotlin | `registerObserver(query, args) { result -> }` with a suspending handler, or `observe(...)` returning a `Flow` (use `.conflate()` for slow collectors). Observers and subscriptions are released with `close()` | No `signalNext`; `collect(query, args) { result -> }` requests the next event only after the suspending handler returns |

### Diffing Results

An observer delivers the complete result every time. When you need to know **what** changed (for list animations, or to process only new items), use `Differ`. It compares successive results by `_id` and reports index sets:

| `Diff` field | Contents |
|---|---|
| `insertions` | Indexes in the **new** list of items that were added |
| `deletions` | Indexes in the **old** list of items that were removed |
| `updates` | Indexes in the **new** list of items whose value changed |
| `moves` | `DiffMove(from: oldIndex, to: newIndex)` for items that changed position |

Facts to keep in mind:

- `diff()` takes a `List<QueryResultItem>`; pass `result.items.toList()` (`items` is an `Iterable`).
- The first call reports every item as an insertion.
- Identity is `_id`; values are compared deeply. A value that changed and changed back between two results is not reported as an update; the observer may still deliver the unchanged result, which then produces an empty diff.
- `moves` can list every item whose position shifted, not just the one that was moved: in tests, moving one item to the top reported three moves for a three-item list, plus an update for the moved item.
- `Differ` keeps the previous result in memory and diffing is computationally expensive. Debounce updates for large or busy result sets, and keep diffed queries bounded (for example, with `LIMIT`).
- `Differ` does not give you the old items. Keep the previous values (or at least their IDs) yourself.
- `Differ` only accepts items produced by Ditto; passing test doubles throws an `ArgumentError`.

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

#### Animated lists

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

### Partial UI Updates

An observer delivers a new result for **any** change that affects its query. If that result triggers `setState` at the top of a large screen, the whole screen rebuilds, which can cause dropped frames, lost scroll position, or lost input focus on busy collections.

**✅ DO:**
- Give each screen region its own small observer and its own widget, so a change rebuilds only that region.
- Use lazy list builders (`ListView.builder`) with a `ValueKey(_id)` per row; only visible rows are built, and keys preserve row state across updates.
- Use aggregate queries for summary widgets (a badge needs `COUNT(*)`, not the full list).
- With state management libraries (Riverpod, Bloc, Provider), let one provider or controller own each observer, cancel it in the provider's dispose hook, and remember that `changes` can only be listened to once.
- Map results to immutable model classes that implement `==` if you rely on equality checks to skip rebuilds; `item.value` creates a new `Map` for every result, so two maps with identical contents are never `==` to each other.

**❌ DON'T:**
- Observe a whole collection in the root widget and rebuild the entire screen on every change.
- Rebuild an app bar, filters, and list together when only one row changed.

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

  /// A list widget with its own observer, such as OrdersByStatus from
  /// "Filter locally instead of re-registering" (Subscription Lifecycle).
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

**Why:** Several narrow observers (one per region) often cost less than rebuilding the entire screen for every change, and they make each widget self-contained. Each observer re-runs its query when its data changes, so keep the number of observers on busy collections reasonable. Use Flutter DevTools to confirm which widgets rebuild before optimizing further.

---

## Transactions

A transaction runs several DQL statements against the local store **atomically**: either all of their changes are committed, or none are. Transactions are a local concept; they do not lock anything on other peers, and concurrent edits from other devices are still merged with CRDT rules (see [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior)).

**When to use a transaction:**
- Changes that span several documents and must never be visible half-done, such as closing an order and creating its invoice, or moving an item between two lists (dual writes)
- Read-check-write sequences on the local store, where the write depends on what you just read
- Several reads that must see one consistent snapshot (read-only transaction)

**When not to use one:** A single `INSERT`, `UPDATE`, or `DELETE` statement is already atomic. Wrapping it in a transaction adds nothing.

### Using store.transaction

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

`Store.transaction` signature (Flutter):

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `callback` (positional) | `Future<T> Function(Transaction)` | required | The work to do. Use only the `Transaction` passed in. |
| `isReadOnly` | `bool` | `false` | Read-only transactions reject mutating statements and can run concurrently |
| `hint` | `String?` | `null` | A label written to the logs (for example, in messages about long-running transactions) |

How a transaction ends:

| Callback outcome | Result |
|---|---|
| Returns `TransactionCompletionAction.commit` | Committed; `transaction()` returns `TransactionCompletionAction.commit` |
| Returns `TransactionCompletionAction.rollback` | Rolled back; no changes are applied; `transaction()` returns `TransactionCompletionAction.rollback` |
| Returns any other value (including nothing) | Committed; `transaction()` returns that value |
| Throws | Rolled back; the error is rethrown to the caller of `transaction()` |
| A statement fails, but the callback catches the error | The transaction **continues**; the remaining changes are committed unless you roll back |

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

### Transaction Rules

**✅ DO:**
- Use **only** `tx.execute(...)` inside the callback.
- Keep transactions short: read, decide, write, return.
- Prepare everything that needs I/O (network responses, files, user input, attachments created with `newAttachment`) **before** starting the transaction.
- Give every transaction a `hint`.
- Use `isReadOnly: true` for transactions that only read.
- Await all pending transactions before calling `ditto.close()`; closing does not wait for them.

**❌ DON'T:**
- Call `ditto.store.execute(...)` inside the callback. In Flutter it throws a `DittoException` ("Attempting to use `ditto.store.execute` while in a transaction scope. Use `transaction.execute` instead ..."). In JavaScript, Swift, and Kotlin the SDKs do not throw; a write through `store.execute` inside a transaction can deadlock, so the same rule applies.
- Start a read-write transaction inside another read-write transaction. Only one read-write transaction runs at a time, so the inner one waits for the outer one forever (deadlock). Flutter has no guard against this.
- Make network calls, show dialogs, wait for user input, or `await` timers inside a transaction.
- Store the `Transaction` object or use it after the callback returns; Flutter throws a `DittoException` when it is used outside its scope.
- Read `commitID` inside the transaction to track sync status; it is `null` until the transaction commits. Keep the `QueryResult` of the write (for example, return it from the callback) and read its `commitID` after `transaction()` completes.

```dart
// ❌ BAD: Mixing store.execute into a transaction, nesting, and doing network I/O.
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

### Concurrency and Duration

- **One read-write transaction at a time:** Any other read-write transaction started meanwhile waits until the current one commits or rolls back. A plain `store.execute` write issued meanwhile also waits.
- **Read-only transactions** can run concurrently with each other and with the active read-write transaction. A mutating statement inside a read-only transaction throws (`A mutating DQL query was attempted using a read-only transaction.`).
- **Arrival order (SDK 5.1+):** Small Peer write transactions are processed in arrival order, which prevents a write from being starved indefinitely by competing operations.
- **Long transactions are logged:** After a transaction has run for 10 seconds, Ditto logs a message about it (including the `hint`) every 5 seconds, starting at debug level and escalating to higher levels. The thresholds are configurable with the system parameters `TRANSACTION_DURATION_BEFORE_LOGGING_MS` and `TRANSACTION_TRACE_INTERVAL_MS`.
- **Closing:** `ditto.close()` in Flutter does not wait for in-flight transactions. Track pending transactions yourself and await them before closing (see [Resource Cleanup and Shutdown](#resource-cleanup-and-shutdown)).

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

### Transactions and Sync

Atomicity is guaranteed on the device that commits the transaction. In SDK 5.1.0 tests, receiving devices also applied a transaction all at once when their subscriptions (and those of every relay in between) covered all of its documents. That held for transactions of up to 10,000 documents, both directly and through a relay. Neither an observer nor a read on the receiving device ever saw part of a transaction. A device that had been offline received the backlog of several transactions as one step, so its observers saw the latest state, not each transaction. For replication, the [transactions documentation](https://docs.ditto.live/sdk/latest/crud/transactions) describes two limits, and both were confirmed in tests:

- A peer whose subscriptions cover only part of a transaction's documents receives only that part. If it later broadens its subscriptions, the remaining changes arrive only when replication catches up.
- A peer that relays changes can forward only what it has. A device connected only through a relay with narrower subscriptions may receive an incomplete transaction (see [Multi-hop relay](#multi-hop-relay)). For example, Peer 1 changes documents A and B in one transaction, Peer 2 subscribes only to A, and Peer 3 is connected only to Peer 2 but subscribes to both A and B. Peer 3 receives only the change to A, because Peer 2 never had the change to B.

Keep documents that are changed together in the same subscription scope (for example, both carry the same `storeId`), give relay devices subscriptions that cover what the devices behind them need, and ensure sufficient connectivity with peers that have broader subscription sets.

### Transactions on Other Platforms

| Platform | API | Explicit rollback | Notes |
|---|---|---|---|
| Flutter | `ditto.store.transaction(hint:, isReadOnly:, (tx) async {...})` | Return `TransactionCompletionAction.rollback` | Any other return value commits; `store.execute` inside throws |
| JavaScript | `ditto.store.transaction(async (tx) => {...}, { isReadOnly, hint })` | Return `'rollback'` | `store.execute` writes or nested read-write transactions inside can deadlock |
| Swift | `try await ditto.store.transaction(hint:isReadOnly:) { tx in ... }` | Return `.rollback` | Return `.commit` (or a value) to commit |
| Kotlin | `ditto.store.transaction(hint, isReadOnly) { tx -> ... }` | Return `DittoTransaction.Result.Rollback` | The block must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |

---

## Attachments

Use attachments for binary data such as photos, signatures, PDFs, and audio. Documents themselves are limited in size (see [Document Size Limits](#document-size-limits)), and every change to a document is synced to every subscriber; large binary values do not belong in documents.

### Attachment Architecture

An attachment has two parts that sync differently:

| Part | Where it lives | How it syncs |
|---|---|---|
| **Token** (`{id, len, metadata}`) | In a document field (the `ATTACHMENT` type) | Like any other document data, through subscriptions |
| **Blob** (the bytes) | In a separate blob store on each device (object storage on Ditto Server) | Only when a device explicitly **fetches** it, with a separate, resumable transfer protocol |

Key properties:

- **Subscriptions never download blobs.** A device that receives a document gets only the token. It must call `fetchAttachment` to download the bytes.
- **Content-addressed:** The attachment `id` is a cryptographic hash of the contents. Identical blobs are stored once, and several documents can reference the same blob.
- **Resumable:** If a transfer is interrupted, progress is not lost; the transfer resumes when connectivity returns or when another peer that has the blob is available.
- **Metadata** is a map of string values (file name, MIME type, dimensions) that syncs with the token, so you can show information about an attachment before fetching it.

### Creating and Inserting Attachments

Create the attachment with `ditto.store.newAttachment(pathOrBytes, [metadata])`, then store the returned `Attachment` object in a document field. Declare the field as `ATTACHMENT` in the statement:

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

| `newAttachment` detail | Behavior |
|---|---|
| First argument | A file path (`String`) or the raw bytes (`Uint8List`) |
| File paths | The file is copied into Ditto's store. Pass an absolute path (for example, one built from `path_provider`). Not supported in web browsers (throws). |
| Metadata | Optional positional `AttachmentMetadata(Map<String, String>)`; values must be strings |
| Result | An `Attachment` with `id`, `len`, `metadata`, `data` (a `Future<Uint8List>`) and `copyToPath(destination)` (native platforms only) |

**✅ DO:**
- Declare attachment fields in the statement: `INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)`; the `COLLECTION` keyword is required when you declare types.
- Pass the `Attachment` object as part of a parameter; never build tokens by hand.
- Create the attachment **before** starting a transaction that stores it (see [Transactions](#transactions)).

**❌ DON'T:**
- Store base64-encoded files in regular document fields; they count toward the document size limit and are re-sent with the document.
- Put non-string values into `AttachmentMetadata`.

**Why declare the type:** With the default `DQL_STRICT_MODE = false`, an attachment inserted without the declaration is still stored as an attachment. With strict mode enabled, the declaration is required, and fields written as `ATTACHMENT` are not visible to queries that do not declare them (see [Strict Mode](#strict-mode)). With strict mode enabled, statements that do not declare the field, including `UNSET`, leave the attachment value unchanged without an error. Declaring the type works in both modes.

### Fetching Attachments

Read the token from the document, then call `ditto.store.fetchAttachment(token, onFetchEvent)`. It returns an `AttachmentFetcher` immediately and reports progress through events:

| Event | Delivered | Contents |
|---|---|---|
| `AttachmentFetchEventProgress` | Zero or more times | `downloadedBytes`, `totalBytes` |
| `AttachmentFetchEventCompleted` | At most once | `attachment` (read the bytes with `await attachment.data`) |
| `AttachmentFetchEventDeleted` | At most once (instead of Completed) | The attachment was deleted while being fetched (not observed in SDK 5.1.0 tests: when the referencing document was deleted while no peer could deliver the blob, the fetch simply stayed pending, so keep a stall timeout) |

| `AttachmentFetcher` member | Meaning |
|---|---|
| `stop()` | Cancels an in-flight fetch. Not required after completion; a completed fetcher stops itself. |
| `isStopped` | `true` after `stop()` or after the fetch completed |
| `attachment` | A `Future<Attachment?>` that completes with the attachment, or with an error if it was deleted. It never completes after `stop()`, so do not await it once you have stopped the fetcher. |

`AttachmentFetchEvent` is not a sealed class, so add a `default` branch to `switch` statements. `ditto.store.attachmentFetchers` lists the fetchers that are still active. Attachments that are already in the local blob store (for example, ones the device created) complete right away, typically without progress events.

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

**✅ DO:**
- Fetch attachments **lazily**, when the widget that shows them is built (for example, inside a row of `ListView.builder`, which only builds visible rows).
- Keep the `AttachmentFetcher` until the fetch completes, and call `stop()` when the user navigates away first.
- Implement your own timeout: restart a timer on every progress event, and stop the fetcher and offer a retry when it fires.
- Show `len` and metadata from the token (size, file name) before the download starts.

**❌ DON'T:**
- Fetch every attachment of every document as soon as it syncs; this downloads data the user may never look at.
- Start a new fetch for the same token on every rebuild or observer update; keep one fetcher per token.
- Treat a fetch that has not made progress as an error immediately; peers that have the blob may connect later.

### Attachments Are Immutable

Once created, an attachment's contents never change. To "edit" a file, create a new attachment and replace the token in the document. The old blob is removed by garbage collection once no document on the device references it (in tests, on the device that replaced it and on the devices that had fetched it). An `Attachment` object your app still holds in memory also kept its blob from being collected (observed in the JavaScript SDK), so do not cache `Attachment` objects longer than you need them.

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

**Deleting and garbage collection:**
- Attachments cannot be deleted directly. Remove the token from the document (`UPDATE ... UNSET`, or set a new token), delete the document with `DELETE` (for every peer), or evict the whole document from this device with `EVICT`.
- On Small Peers, blobs that are no longer referenced are garbage-collected automatically every 10 minutes. Garbage collection runs only on Small Peers, not on Ditto Server.

### Thumbnail Pattern

Lists of photos should not download full-size images. Store a small preview next to the full-size attachment and fetch the full-size file only when the user opens it.

| Preview option | Pros | Cons |
|---|---|---|
| Small **attachment** (for example, a downscaled JPEG) | Keeps documents small; only fetched where shown | Needs an explicit fetch, like any attachment |
| Small inline value in the document (for example, a tiny base64 preview) | Arrives with the document; no fetch needed | Counts toward the document size limit (256 KiB soft limit) and is re-sent with the document; keep it very small |

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

**Why:** Every device that subscribes to `photos` receives both tokens, but downloads only the thumbnails that are actually displayed. Full-size blobs cross the network only for the photos users open, which matters most on slow peer-to-peer transports such as Bluetooth LE.

### Availability

An attachment can only be fetched while a peer that **holds the blob** is reachable. Documents and blobs travel separately, so a device can have a token for an attachment that no reachable peer can deliver at the moment.

- A blob exists on a device only if that device created it or fetched it. Ditto's [attachment documentation](https://docs.ditto.live/sdk/latest/crud/working-with-attachments) describes that Ditto Server can hold a document with an attachment token but not the blob, for example when Small Peers replicate the document among themselves without fetching the attachment.
- An interrupted transfer resumes from where it stopped, from the same peer or from another peer that has the blob.
- The fetch API has no "not available" event: while no peer can deliver the blob, the fetch simply makes no progress. Handle this with a timeout and a retry in the UI (see the `AttachmentImage` example).
- Do not design workflows that depend on a particular relay behavior for blobs across multiple hops; if a blob must be widely available (for example, a product image), make sure a well-connected device or Ditto Server fetches it. In SDK 5.1.0 tests with three devices in a line (A–B–C), C could not fetch a blob that only A held until B had fetched it itself. That held for 1 KB and 300 KB attachments and a 60-second wait, although B subscribed to the documents. Once B had the blob, C's fetch completed in milliseconds.

**✅ DO:**
- Show a placeholder with the attachment's metadata while the blob is unavailable.
- Let devices that act as hubs, or a backend connected to Ditto Server, fetch attachments that many devices will need.

**❌ DON'T:**
- Assume that receiving a document means its attachment can be downloaded right away.
- Delete the original file on the creating device before the attachment is stored with `newAttachment` (afterwards, the copy in Ditto's store is what matters).

### Size Guidance

| Item | Guidance |
|---|---|
| Individual attachment | No fixed maximum in the SDK; practical limits are device storage and network bandwidth |
| Blob storage | Stored outside the document database; does not count toward the per-device key-value storage guidance (about 2 GB; see [Key Characteristics](#key-characteristics)) |
| Uploads through the HTTP API | A separate 1 MB request body limit applies (can be raised on request) |
| Documents | 256 KiB soft limit (warning) and 5 MiB hard limit (writes that exceed it fail); see [Document Size Limits](#document-size-limits) |
| Transfer progress | Reported only through fetch events; `system:data_sync_info` does not include attachments |

**✅ DO:**
- Store images, documents, audio, and other binary files as attachments rather than inside documents.
- Compress and downscale media on the creating device before calling `newAttachment`.
- Consider the slowest transport your users rely on (Bluetooth LE is much slower than Wi-Fi) when deciding what to fetch automatically and what to fetch on demand.

**❌ DON'T:**
- Fetch large attachments automatically on devices that may only be connected over Bluetooth LE.
- Keep many versions of large files alive by referencing old tokens from history documents unless you need them; every referenced blob stays on the device.

---

## Deletion and Storage Management

Removing data from a database that syncs across an offline mesh is fundamentally different from removing a row in a central server database. There is no single place where a deletion "happens": every Small Peer holds its own copy, devices can be offline for days, and any device that still holds a document can share it again with peers that have already removed it.

Keep these properties in mind before choosing a removal strategy:

- **Deletions propagate like any other change.** A deletion only reaches a device when that device connects to a peer that knows about it.
- **Offline devices can reintroduce data.** A device that missed the deletion and reconnects later may still hold the old document and sync it back to the mesh.
- **Concurrent edits merge.** A delete on one device and an update on another are merged by the CRDT rules, not ordered by a central authority.
- **Local storage is finite.** Edge devices usually need only a subset of the data, so they must also be able to drop data locally without affecting anyone else.

Ditto offers three tools for these needs:

| Tool | What it does | Scope |
|---|---|---|
| `DELETE` | Removes the document's values and leaves a tombstone that propagates the deletion to other peers | Mesh-wide |
| Soft delete | An `UPDATE` that sets a flag such as `isDeleted`; queries filter flagged documents out | Mesh-wide (it is an ordinary update) |
| `EVICT` | Removes documents from the local store only; the removal is not propagated to other peers | This device only |

In deployments with a Ditto Server (formerly Big Peer), use `DELETE` for permanent removal (typically on the Ditto Server) and `EVICT` to manage storage on edge devices. If you plan to use `DELETE` in a deployment with Small Peers only, contact Ditto support to review the design. See [Choosing DELETE, Soft Delete, or EVICT](#choosing-delete-soft-delete-or-evict) for a decision table.

### DELETE and Tombstones

`DELETE` permanently removes documents from the user's perspective:

```sql
DELETE FROM orders WHERE _id = :orderId
```

What happens when a document is deleted:

- **The values are removed.** Ditto keeps a small *tombstone* that consists of the document ID, metadata such as the deletion time, and the field names the document had at the time of deletion. All values are removed. Tombstones are internal and cannot be queried.
- **The tombstone propagates.** Peers learn about the deletion through the tombstone. Tombstones are only shared with peers that have seen the document before it was deleted; a peer never receives a tombstone for a document it never knew about. As a consequence, in tests a device that never had the document accepted a stale copy from a device that had been offline, and passed it on, until it met a peer that held the tombstone.
- **The document disappears locally at once.** After `DELETE`, the document no longer appears in `SELECT`, is not counted by `COUNT(*)`, and an `UPDATE` no longer matches it.
- **The ID can be reused.** A later `INSERT` with the same `_id` creates a new document; fields of the deleted document do not reappear, unless another device edited the old document concurrently: in tests, such offline edits merged into the new document (see [Husk documents](#husk-documents)).

**✅ DO:**
- Target documents by ID with `WHERE _id = :id` or `WHERE _id IN :ids` (both are planned as an ID scan).
- Use `RETURNING` (SDK 5.1+) when you need the content of the deleted documents, for example for an undo message or an audit record.
- Make sure every device connects within the tombstone TTL (7 days by default; see [Tombstone TTL and reaping](#tombstone-ttl-and-reaping)), or use a soft delete instead.

**❌ DON'T:**
- Use `DELETE ... USE IDS ...` without a `WHERE` clause (see the note below).
- Use `DELETE` for data that is updated concurrently on other devices (see [Husk documents](#husk-documents)).
- Use `DELETE` to free space on one device; it removes the data for every peer. Use [EVICT](#evict) instead.

> **Note (SDK 5.1.0):** `DELETE` and `EVICT` statements that use `USE IDS` without a `WHERE` predicate (no `WHERE` clause, or `WHERE true`) complete without an error but remove nothing. Use `WHERE _id IN :ids` instead; it is planned as an ID scan, so it is just as efficient.

```dart
// ✅ GOOD: Delete several documents by ID and capture what was removed (SDK 5.1+).
Future<List<Map<String, dynamic>>> deleteOrders(
  Ditto ditto,
  List<String> orderIds,
) async {
  final result = await ditto.store.execute(
    'DELETE FROM orders WHERE _id IN :ids RETURNING _id, status, total',
    arguments: {'ids': orderIds},
  );
  // With RETURNING, each item holds the document as it was before deletion.
  return result.items.map((item) => item.value).toList();
}
```

```sql
-- ❌ BAD (SDK 5.1.0): completes without an error but deletes nothing
DELETE FROM orders USE IDS LIST :ids

-- ✅ GOOD: planned as an ID scan, deletes the listed documents
DELETE FROM orders WHERE _id IN :ids
```

**Why:** The ID-based `WHERE` form is the reliable way to target specific documents for removal, and `RETURNING` is the only way to read a document's content after `DELETE`, because the tombstone keeps no values.

#### Capturing deleted content with RETURNING (SDK 5.1+)

`RETURNING` on `DELETE` (and `EVICT`) returns the documents as they were **before** removal. Aggregates are allowed, which is convenient for counting:

```sql
DELETE FROM orders WHERE status = 'cancelled' AND createdAt < :cutoff RETURNING COUNT(*) AS removed
```

`mutatedDocumentIDs()` is still populated when `RETURNING` is used, but include `_id` in the `RETURNING` projection when you need the IDs. See [RETURNING (SDK 5.1+)](#returning-sdk-51) for the full syntax.

#### Tombstone TTL and reaping

Tombstones do not live forever. Each device removes expired tombstones in a periodic process called *reaping*, controlled by these system parameters:

| System parameter | Default | Meaning |
|---|---|---|
| `TOMBSTONE_TTL_ENABLED` | `true` | Expired tombstones are removed automatically |
| `TOMBSTONE_TTL_HOURS` | `168` (7 days) | Age after which a tombstone is considered expired on this device |
| `DAYS_BETWEEN_REAPING` | `1` | Days between reaping runs (the first run happens shortly after the instance starts) |
| `TOMBSTONE_REAP_BATCH_SIZE` (SDK 5.1+) | `10000` | Expired tombstones are removed in bounded batches to limit peak memory |

```sql
SHOW ALL LIKE '%tombstone%'
```

Consequences for your design:

- **A device that is offline for longer than the TTL can resurrect deleted data.** If it reconnects after every other peer has already reaped the tombstone, nobody can tell it the document was deleted, and it shares its old copy again. This is known as "zombie data".
- **The TTL is measured from the deleting device's clock.** A device with an inaccurate clock can make tombstones expire earlier or later than expected.
- **Very short TTLs can make deletions fail to propagate**, because the tombstone may expire before it reaches the other peers. (`TOMBSTONE_TTL_HOURS` accepts values from 1 hour; `ALTER SYSTEM` rejects 0.)
- **Never configure the Edge TTL (`TOMBSTONE_TTL_HOURS` on Small Peers) to exceed the Ditto Server TTL.** The Ditto Server always syncs documents, so a Small Peer tombstone that outlives the Ditto Server's own tombstone is sent back to the server repeatedly, which wastes resources. The Ditto Server tombstone TTL defaults to 30 days; changes to the server side go through Ditto support. <!-- lint-ignore -->

If devices can legitimately stay offline longer than 7 days, you can raise `TOMBSTONE_TTL_HOURS` (staying at or below the Ditto Server TTL), or prefer a soft delete for that data. `ALTER SYSTEM` settings are not persisted, so apply them after every open (see [Applying System Parameters](#applying-system-parameters)):

```sql
-- Example: keep tombstones for 14 days on this device (must not exceed the Ditto Server TTL)
ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 336
```

Reaping can be expensive on devices with very many tombstones. The parameters `ENABLE_REAPER_PREFERRED_HOUR_SCHEDULING` and `REAPER_PREFERRED_HOUR` schedule reaping during off-hours. They must be set before Ditto starts, through environment variables (`ALTER SYSTEM` accepts new values at runtime, but they are not applied), and WASM-based platforms (JavaScript Web and Flutter Web) do not support them. Contact Ditto support before relying on these parameters.

#### Husk documents

When one device deletes a document while another device concurrently updates it, the add-wins CRDT merges both operations field by field. The result is a *husk document*, and the document is **not** deleted. In SDK 5.1.0, the husk's shape depends on which operation was written first:

```text
Initial:            {"_id": "abc123", "color": "red", "make": "Toyota", "year": 2020}

Device A:           DELETE FROM cars WHERE _id = 'abc123'
Device B (offline, later): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": "blue"}      // make, year: MISSING

Device B (offline): UPDATE cars SET color = 'blue' WHERE _id = 'abc123'
Device A (later):   DELETE FROM cars WHERE _id = 'abc123'
After merge:        {"_id": "abc123", "color": null}        // make, year: MISSING
```

- **The document survives even when the DELETE is the later write.** In that case, the updated fields are `null` too, so the document is visible but holds no values.
- **Fields the update did not touch are MISSING, not `null`.** `make IS NULL` is `false` and `make IS MISSING` is `true`. Ditto's [deletion documentation](https://docs.ditto.live/sdk/latest/crud/delete) shows them as `null`, which does not match 5.1.0.
- Husks count in `SELECT COUNT(*)`, but a value filter such as `WHERE year >= 2000` excludes them.
- Running the `DELETE` again after the merge removes the husk on every device.

Tests with two peers produced these shapes in every trial, whichever device deleted. The test covered both orders, with 3 trials each in two runs.

A related effect can occur on a single device: inserting a document with `INITIAL DOCUMENTS` for an `_id` that was previously deleted can produce a document whose fields are all `null`, because the tombstone is newer than the "initial" data (see [Default Data with INITIAL Documents](#default-data-with-initial-documents) for when this happens).

To avoid husk documents:

1. Use a [soft delete](#soft-delete) for data that may be edited concurrently.
2. Manage edge storage with [EVICT](#evict) and perform permanent deletion on the Ditto Server (for example through its HTTP API).
3. Coordinate your workflow so that the same document is not deleted and updated at the same time.

If husk documents are possible in your data, make your UI tolerate documents whose fields are `null` **or missing**. To keep husks out of lists, filter on a field that every live document has, and test for both cases: `WHERE make IS NOT MISSING AND make IS NOT NULL`. `IS NOT NULL` alone is `true` for a missing field (see [MISSING and NULL](#missing-and-null)). <!-- lint-ignore -->

#### Deleting on the Ditto Server

`DELETE` statements sent through the Ditto Server HTTP API run as a single atomic operation. Delete in batches of 30,000 documents or fewer to avoid slowing down sync for connected devices:

```sql
DELETE FROM orders WHERE status = 'archived' LIMIT 30000
```

There is no `DROP COLLECTION` statement. `DELETE FROM orders` without a `WHERE` clause deletes every document in the collection, but the collection itself remains.

### Soft Delete

A soft delete marks a document as deleted with an ordinary `UPDATE` instead of removing it. Because the flag is just a field, it syncs like any other change and has none of the tombstone limitations:

- **No TTL dependency:** the flag stays on the document, so a device that was offline for weeks still learns that the document is deleted.
- **No husk documents:** a concurrent update merges with the flag instead of resurrecting a partially deleted document.
- **Recoverable:** setting the flag back to `false` restores the document.

The trade-off is that soft-deleted documents still occupy storage and must be filtered out of every query, so you need a cleanup step (see [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup)).

**✅ DO:**
- Set both a flag and a timestamp: `isDeleted = true` and `deletedAt` as a UTC ISO-8601 string written by the same timestamp helper everywhere (see [Timestamps](#timestamps)).
- Write `isDeleted: false` when you create documents.
- Filter with `coalesce(isDeleted, false) = false`, which also matches documents where the field is missing or `null`.
- Keep soft-deleted documents inside your subscriptions at least until every device has received the flag, and filter them out in local queries and observers.

**❌ DON'T:**
- Filter with `isDeleted != true` or `NOT isDeleted`; both silently exclude documents where `isDeleted` is missing or `null`.
- Remove soft-deleted documents from a subscription the moment they are flagged.

```dart
// ✅ GOOD: Soft delete, restore, and query helpers for an orders collection.
Future<void> softDeleteOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      // utcTimestamp() is defined in the Timestamps section; deletedAt is
      // compared with cleanup cutoffs, so it needs the fixed-precision helper.
      'deletedAt': utcTimestamp(),
    },
  );
}

Future<void> restoreOrder(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET isDeleted = false UNSET deletedAt WHERE _id = :id',
    arguments: {'id': orderId},
  );
}

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

```sql
-- ❌ BAD: misses documents where isDeleted is missing or null
SELECT * FROM orders WHERE isDeleted != true

-- ✅ GOOD: treats missing and null as "not deleted"
SELECT * FROM orders WHERE coalesce(isDeleted, false) = false
```

**Why:** In DQL, a comparison with a missing or `null` field does not evaluate to `true`, so it never passes a `WHERE` clause. Which documents each soft-delete filter matches, when `isDeleted` is `true`, `false`, `null`, or missing:

| Filter | Matches |
|---|---|
| `isDeleted != true` | `false` only |
| `NOT isDeleted` | `false` only |
| `coalesce(isDeleted, false) = false` | `false`, `null`, missing |

See [MISSING and NULL](#missing-and-null) for the general rules.

#### Indexing soft-delete filters

`coalesce(isDeleted, false) = false` applies a function to the field, so it cannot use an index on `isDeleted` by itself (the planner falls back to a collection scan). Alternatives:

| Approach | Plan |
|---|---|
| `coalesce(isDeleted, false) = false` alone | Collection scan |
| `status = :status AND coalesce(isDeleted, false) = false` with an index that starts with `status` | Index scan on `status`; the `coalesce` condition is applied as a filter |
| `(isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false)` with an index on `isDeleted` | Index scan (returns the same documents as the `coalesce` form) |
| `isDeleted = false` with an index on `isDeleted`, when every document is guaranteed to have the field | Index scan |

In most screens, the soft-delete condition is combined with a more selective predicate (a status, a customer ID, a date range). Index that predicate, keep the `coalesce` form for correctness, and confirm the plan with [ADVISE](#advise-sdk-51) or [EXPLAIN](#explain-and-profile).

```sql
-- Index-friendly equivalent of coalesce(isDeleted, false) = false
SELECT * FROM orders
WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false
```

#### Soft delete, subscriptions, and cleanup

The deletion flag is itself a change that every device must receive. A subscription that excludes soft-deleted documents (for example `WHERE coalesce(isDeleted, false) = false`) stops requesting a document as soon as it is flagged. In SDK 5.1.0 tests, the update that set the flag still reached such devices, even after they had been offline. Later changes to the flagged document did not, and that includes a **restore** (`isDeleted = false`). Keep in mind:

- The flagged document is **not removed** from the devices that already have it; cancelling or narrowing a subscription never deletes local data.
- If flagged documents can be restored or edited, keep them inside the subscription; otherwise devices that hold the flagged version never see the restore.
- A subscription filter does not hide documents in local results. Every local query and observer must filter flagged documents itself, for example with `coalesce(isDeleted, false) = false`.

Therefore keep soft-deleted documents inside the subscription at least until every device has received the flag. Two subscription designs meet this requirement; they differ in how soft-deleted documents are eventually removed:

| | Variant A: whole-collection subscription | Variant B: retention-window subscription |
|---|---|---|
| Subscription | Every document of the collection (or of the device's partition, such as one store), including soft-deleted ones | Active documents plus documents deleted within a retention window |
| Cleanup | A `DELETE` after the retention period, executed on the Ditto Server or by another authorized peer, that syncs to every device | Each device evicts documents deleted before the cutoff; the record stays on the Ditto Server until it is deleted there |
| Device-side `EVICT` of old soft-deleted documents | ❌ They still match the subscription and sync back | ✅ They are outside the subscription |
| Subscription changes | None | Re-registered when the cutoff moves (for example once a day) |
| Trade-offs | Simplest design. Soft-deleted documents use storage on every device until the `DELETE` runs, and the `DELETE` is subject to the tombstone rules (see [DELETE and Tombstones](#delete-and-tombstones)) | More moving parts. Choose a window longer than the longest expected offline period, so that every device receives the flag while the document is still inside its subscription |

**Variant A:** subscribe to the whole collection (here, one store's partition of it) and filter locally.

```dart
// ✅ GOOD (Variant A): The subscription (owned by a long-lived service such as
// OrderSync) includes soft-deleted orders; local queries hide them.
SyncSubscription subscribeToStoreOrders(Ditto ditto, String storeId) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
}

StoreObserver observeActiveOrders(Ditto ditto, String storeId) {
  // coalesce() treats a missing or null isDeleted field as false.
  return ditto.store.registerObserver(
    'SELECT * FROM orders '
    'WHERE storeId = :storeId AND coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
    arguments: {'storeId': storeId},
  );
}
```

Cleanup then runs on the Ditto Server (for example through its HTTP API) once the retention period has passed and flagged documents are no longer edited (see [Husk documents](#husk-documents)):

```sql
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000
```

**Variant B:** subscribe to active documents plus documents deleted within the retention window, and evict exactly the complement.

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

  // Same fixed-precision format as deletedAt (utcTimestamp() from "Timestamps").
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

**Why:** In Variant B, the eviction condition (`isDeleted = true AND deletedAt < :cutoff`) never matches a document that the new subscription covers, so evicted documents do not sync back. In Variant A, every soft-deleted document stays inside the subscription, so devices cannot evict them; the `DELETE` removes them everywhere instead. Because the cutoff is part of the Variant B subscription, move it only when you run cleanup, not on every screen change (see [Subscription Lifecycle](#subscription-lifecycle)).

### EVICT

`EVICT` removes documents from the **local** store only. It has the same shape as `DELETE`, including `WHERE`, `LIMIT`, and `RETURNING` (SDK 5.1+):

```sql
EVICT FROM orders WHERE createdAt < :cutoff
```

What eviction does and does not do:

- The documents are removed from this device immediately and disappear from local queries.
- The removal is not propagated to other peers and no tombstone is created. The documents remain on every other peer, including the Ditto Server. (Each eviction still triggers a resync with every connected peer; see the **Why** below.)
- The same `_id` can be inserted again later without a conflict. The new insert is not a new document across the mesh: in tests, it merged with the copies that other peers still held, so fields from both appeared.
- **If an active subscription on this device still matches an evicted document, connected peers notice that it is missing and sync it back.** This can turn into a loop of evicting and re-syncing.

**✅ DO:**
- Cancel or narrow the affected subscriptions **before** evicting, and evict only documents that are outside the scope of every remaining subscription.
- Make the eviction query the complement of the subscription query (for example, subscribe to `createdAt >= :cutoff` and evict `createdAt < :cutoff` with the same cutoff value). Produce the timestamp with one fixed-precision helper (see [Timestamps](#timestamps)).
- Run eviction on a schedule, at most about once per day, preferably at a quiet time.
- Evict by ID with `WHERE _id IN :ids`.

**❌ DON'T:**
- Evict documents and then register a subscription that matches them again (for example `SELECT * FROM orders`): the evicted data syncs straight back.
- Evict frequently (for example on every screen change).
- Use `EVICT ... USE IDS ...` without a `WHERE` clause (it removes nothing in SDK 5.1.0, as described in [DELETE and Tombstones](#delete-and-tombstones)).

```dart
// ❌ BAD: The new subscription matches the evicted documents again,
// so connected peers sync them straight back.
Future<SyncSubscription> evictAndResubscribeEverything(
  Ditto ditto,
  SyncSubscription subscription,
  String cutoff,
) async {
  subscription.cancel();
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
  return ditto.sync.registerSubscription('SELECT * FROM orders');
}
```

**Why:** Each eviction triggers a resync with every connected peer, which costs network traffic and processing. If the subscription still covers the evicted documents, that resync simply sends them back, and you pay the cost without freeing any space.

#### Time-based eviction

Keep only recent data on the device by scoping the subscription to a time window and evicting everything older than the same boundary:

```dart
// ✅ GOOD: Keep the last 7 days of orders on this device.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  static const retention = Duration(days: 7);
  SyncSubscription? _subscription;

  // Same fixed-precision format as createdAt (utcTimestamp() from "Timestamps").
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

**Why:** The subscription and the eviction use the same cutoff with complementary operators (`>=` and `<`), so no evicted document matches an active subscription.

Documents that were already in flight through the cancelled subscription can still arrive shortly after the eviction. If your boundary changes significantly (for example when the user switches stores), run the same `EVICT` again in the next scheduled cleanup or at the next app start, rather than immediately, so that evictions stay infrequent.

#### Flag-based eviction

When a central component decides what is no longer needed, it can mark documents with a flag. Ditto's [device storage management documentation](https://docs.ditto.live/sdk/latest/sync/device-storage-management) describes this flag-based eviction: devices evict the flagged documents and subscribe only to unflagged ones. This approach works well when a Ditto Server is available, because the server can make sure documents have synced before they are marked:

```sql
-- Executed on the Ditto Server (for example through the HTTP API) or by an authorized device
UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff
```

```dart
// ✅ GOOD: Devices subscribe to unflagged documents and evict flagged ones.
SyncSubscription subscribeToUnflaggedOrders(Ditto ditto) {
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE coalesce(evictionFlag, false) = false',
  );
}

Future<void> evictFlaggedOrders(Ditto ditto) async {
  await ditto.store.execute('EVICT FROM orders WHERE evictionFlag = true');
}
```

Because the subscription never matches flagged documents, the device does not need to cancel and re-register it before each eviction.

#### Batching evictions

`EVICT` supports `LIMIT`, so a large cleanup can be split into smaller transactions. Combine it with `RETURNING COUNT(*)` to know when to stop:

```dart
// ✅ GOOD: Evict in batches of 1,000 until nothing is left to evict.
// First cancel or narrow every subscription that matches these documents (see the EVICT section).
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

Batching keeps individual write transactions short. It does not reduce the sync cost of eviction: run the whole batched cleanup on the usual schedule (see [Eviction frequency](#eviction-frequency)), not as many separate cleanups.

#### Eviction frequency

- Evict on a regular schedule, but no more than about once per day, during periods of minimal disruption such as after hours.
- (SDK 5.1+) Ditto writes a warning-level log entry when post-eviction session cleanup runs too frequently within a sliding window, signaling that excessive evictions may cause sync overhead on connected peers. Treat this warning as a sign to evict less often.
- Local `DELETE` and `EVICT` execution is fast, but the sync cost of each eviction on connected peers still applies.

> **Advanced:** The system parameter `DISABLE_REPLICATION_GC_ON_EVICT` (default `false`) stops each eviction from triggering immediate per-peer replication metadata cleanup; the periodic background garbage collection still reclaims metadata for disconnected peers once they exceed its TTL (about 7 days by default). It is an opt-in setting for deployments where eviction-time filesystem work contributes to write latency. Leave it at the default unless profiling shows that problem.

### Choosing DELETE, Soft Delete, or EVICT

| Requirement | `DELETE` | Soft delete | `EVICT` |
|---|---|---|---|
| Remove data for every peer | ✅ (tombstone) | ✅ (flag, then cleanup) | ❌ (local only) |
| Safe when devices stay offline longer than the tombstone TTL (7 days by default) | ❌ (data can be resurrected) | ✅ | ✅ (other peers are unaffected) |
| Safe with concurrent updates on other devices | ❌ (husk documents) | ✅ | ✅ |
| Can be undone | ❌ | ✅ | ✅ (data syncs back if a subscription matches it again) |
| Frees local storage | ✅ (values immediately; tombstones after reaping) | ❌ (until cleanup) | ✅ (immediately) |
| Extra query complexity | None | Every query filters the flag | Subscription and eviction scopes must be complementary |

Typical choices:

- **Data owned by one user and rarely edited concurrently** (for example a draft that the user discards), in a deployment where devices sync regularly: `DELETE`.
- **Shared business records** (orders, tasks, inventory) that several devices edit, or deployments with long offline periods: soft delete, with cleanup as described in [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup).
- **Storage management on edge devices** (old history, data for other locations): `EVICT` with complementary subscriptions.

### Monitoring Storage

`system:system_info` reports storage usage and document counts for the local device. The values are collected periodically, so they can lag behind recent writes:

```sql
SELECT key, value FROM system:system_info WHERE key LIKE 'fs_usage%'

SELECT key, value FROM system:system_info WHERE key LIKE 'collection_num_docs%'
```

Keys include `fs_usage_total`, `fs_usage_store`, `fs_usage_replication`, `fs_usage_attachment`, `fs_usage_auth`, `fs_device_available`, and `fs_device_total` (namespace `core`), and `collection_num_docs[<collection>]` (namespace `store`). Each key can appear more than once with different timestamps; read the newest row.

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

**❌ DON'T** register a long-lived observer on `system:system_info`: such observers run every 500 ms regardless of whether anything changed. Query it with `execute` when you need it.

To keep storage under control, combine monitoring with a retention policy ([EVICT](#evict)) and keep individual documents small (see [Document Size Limits](#document-size-limits)).

---

## Indexing and Query Performance

Indexes let the query engine find matching documents without scanning a whole collection. They speed up `WHERE` filters, `ORDER BY` clauses, and the inner side of a JOIN (see [Joining Collections (SDK 5.1+)](#joining-collections-sdk-51)). Every index also has a cost: it is updated on every write to the collection, uses storage, and creating it scans the whole collection.

Indexes help most when a query returns a small fraction of a collection, because the engine can skip the documents that do not match. For queries that return most of a collection, an index adds little.

### Creating Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)

CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)

CREATE INDEX IF NOT EXISTS idx_orders_city ON orders (address.city)
```

Syntax:

```text
CREATE INDEX [IF NOT EXISTS] <name> ON <collection> (<field> [ASC|DESC], ...)
DROP INDEX [IF EXISTS] <name> ON <collection>
```

- **Single-field indexes** cover one field. `ASC` is the default.
- **Composite indexes (SDK 5.1+)** cover several fields in order. Put equality fields first and range or sort fields last (see [Index Usage Rules](#index-usage-rules)).
- **Nested paths** use dot notation, for example `address.city`.
- **Array and object values (SDK 5.1+)** can be indexed, but only as whole values: an index on `tags` speeds up `tags = ['x', 'y']`, not "contains `'x'`", and an index on `address` does not help a filter on `address.city`. Index the full path you filter on.
- **Expression indexes do not exist.** `CREATE INDEX ... (lower(name))` is a parser error. Partial and functional indexes are not supported.
- Documents that do not contain the indexed field are still covered by SDK indexes, so `IS MISSING` and `!=` filters return correct results through an index.

`IF NOT EXISTS` checks only the **name**. If an index with the same name already exists on the collection, the statement succeeds and changes nothing, even when the field list differs. To change an index definition, create it under a new name (and drop the old one), or drop and recreate it. Without `IF NOT EXISTS`, a duplicate name fails with `an index with the given name already exists on the given collection`. Index names are scoped to a collection.

```sql
-- ✅ GOOD: DROP INDEX requires ON <collection>
DROP INDEX IF EXISTS idx_orders_city ON orders
```

<!-- expect-error -->
```sql
-- ❌ BAD: parser error (expected ON)
DROP INDEX idx_orders_city
```

<!-- expect-error -->
```sql
-- ❌ BAD: expression indexes are not supported (parser error)
CREATE INDEX idx_orders_name_lower ON orders (lower(name))
```

#### Listing indexes

`system:indexes` lists the indexes on this device:

```sql
SELECT * FROM system:indexes WHERE collection = :collection
```

Example output for the indexes created above:

```json
{"_id": "orders.idx_orders_status", "collection": "orders", "fields": [{"direction": "asc", "key": ["status"]}]}
{"_id": "orders.idx_orders_status_createdAt", "collection": "orders",
 "fields": [{"direction": "asc", "key": ["status"]}, {"direction": "desc", "key": ["createdAt"]}]}
```

#### Where indexes live

- **Indexes persist.** After closing Ditto and reopening the same persistence directory, all indexes are still present and used by the planner.
- **Indexes are local to each device.** `CREATE INDEX` and `DROP INDEX` run on the local SDK. Create the indexes your queries need on every device, as part of startup.
- **`CREATE INDEX` / `DROP INDEX` run only through `execute`.**
- **Indexes speed up `execute` and store observers;** subscriptions and Ditto Server queries do not use them, and custom indexes are not supported on the Ditto Server.
- **In-memory stores do not support indexes.** On the Web (Flutter Web and JavaScript Web), where the store is in memory, skip index creation; `CREATE INDEX` fails there with `the database implementation does not support indexing`.

**✅ DO:**
- Create indexes at startup with `CREATE INDEX IF NOT EXISTS`, which is idempotent and needs no extra query.
- Create indexes after `Ditto.open` and before your queries and observers start, so the first queries already benefit.
- Use [ADVISE](#advise-sdk-51) during development to decide which indexes to create.
- Drop indexes that no queries use any more; every index costs write time and storage.

**❌ DON'T:**
- Create indexes on demand right before a query; creation scans the collection.
- Index every field "just in case".
- Rely on indexes when [strict mode](#strict-mode) is enabled (see [Strict mode and data types](#strict-mode-and-data-types)).

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

#### Upgrading and downgrading

SDK 5.1 uses a new on-disk index format and migrates existing indexes automatically the first time an app starts with it. If you ever need to downgrade an app from 5.1, go through SDK 5.0.2 or later, which converts the format back and replaces each composite index with one single-field index per key. See the [indexing documentation](https://docs.ditto.live/dql/indexing#migration) and the migration guides.

### Index Usage Rules

The query planner chooses indexes by rules, not by statistics about your data. `EXPLAIN` shows these plans:

| Predicate | Plan | Notes |
|---|---|---|
| `status = :status` | Index scan | |
| `status IN :statuses` (array parameter) | Index scan, one span per value | Write `IN :statuses`; `IN (:statuses)` matches nothing (see [Parameters and Literals](#parameters-and-literals)) |
| `total > 100`, `total >= :min AND total < :max` | Index scan over a range | |
| `name LIKE 'abc%'` | Index scan over a range | Case-sensitive prefix without a leading wildcard; works with a literal or a parameter |
| `starts_with(name, 'abc')` | Collection scan | Use `LIKE 'abc%'` instead |
| `lower(name) = 'abc'`, any function applied to the field | Collection scan | Functions on the value side (for example `= :param`) are fine |
| `status != 'open'`, `NOT (status = 'open')` | Index scan over two ranges | |
| `flag IS MISSING` | Index scan | SDK indexes include documents without the field |
| `coalesce(isDeleted, false) = false` | Collection scan | See [Indexing soft-delete filters](#indexing-soft-delete-filters) |
| `_id = :id`, `_id IN :ids`, `USE IDS` | ID scan | No index needed |
| `a = 1 OR b = 2` (both indexed) | Union scan | |
| `a = 1 OR b = 2` (`b` not indexed) | **Collection scan** | Every `OR` branch must be indexable |
| `a = 1 AND b = 2` (separate indexes) | Intersect scan | A composite index on `(a, b)` is generally better |
| `address.city = 'Tokyo'` (index on `address.city`) | Index scan | Index the full path you filter on |
| `tags = ['x', 'y']` (index on `tags`) | Index scan | Whole-value match only |
| `array_contains(tags, 'x')`, `:tag IN tags` | Collection scan | Element lookups cannot use an index |
| `SELECT COUNT(*) FROM orders` (no `WHERE`) | Count scan | Does not read documents |

#### Composite indexes and key order (SDK 5.1+)

A composite index works like a phone book sorted by last name, then first name: it is efficient when the query fixes the leading fields with equality and then filters or sorts by the next one.

- Put **equality** fields first, then the **range** or **sort** field.
- Match the **sort direction**: with an index on `(status, total DESC)`, `WHERE status = 'open' ORDER BY total DESC` uses the index without a separate sort, while `ORDER BY total ASC` needs an extra sort step.
- Queries that do not constrain the leading field benefit less, and the planner may choose a different index.

```sql
CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt ON orders (customerId, createdAt DESC)

-- ✅ GOOD: equality on the leading key, range and sort on the second key
SELECT * FROM orders
WHERE customerId = :customerId AND createdAt >= :since
ORDER BY createdAt DESC
```

```sql
-- ❌ BAD: the sort direction does not match the index, so an extra sort step is needed
SELECT * FROM orders
WHERE customerId = :customerId
ORDER BY createdAt ASC
```

**Why:** The planner can read a composite index in key order and stop early. When the sort direction or key order does not match, it has to collect all matching documents and sort them, which costs memory and time on large results.

#### Covering scans

When a query projects only fields that are in the index (plus `_id`), the planner can answer it from the index without fetching documents. `EXPLAIN` shows `"covering": true` and no `fetch` step:

```sql
-- Answered from idx_orders_status alone
SELECT _id, status FROM orders WHERE status = :status
```

Projecting only the fields a screen needs therefore helps twice: less data is materialized, and some queries avoid document fetches entirely.

#### Strict mode and data types

- **Strict mode:** with `DQL_STRICT_MODE` set to `true`, the SDK 5.1.0 query planner does not use secondary indexes: queries that would use an index scan fall back to a collection scan, both for existing indexes and for indexes created while strict mode is enabled. ID lookups and full-collection `COUNT(*)` are not affected, and `ADVISE` returns no suggestions. Keep the default (`false`) if you rely on indexes. See [Strict Mode](#strict-mode).
- **Mixed CRDT types:** only the most recently written CRDT type of a field is indexed. If the same field is written with different type declarations (for example once as `REGISTER` and once as `MAP`), an index on it can return incorrect or mis-ordered results for queries that request the other type. Keep type declarations consistent (see [Keep type declarations consistent](#keep-type-declarations-consistent)), and do not index fields that are written with more than one type.

### ADVISE (SDK 5.1+)

Prefix a statement with `ADVISE` to get index recommendations for it. The statement is planned but **not executed**, and no documents are read or written. `ADVISE` is available on Small Peers for `SELECT`, `UPDATE`, `DELETE`, `EVICT`, and `INSERT ... SELECT`.

```sql
ADVISE SELECT * FROM orders WHERE status = :status AND isDeleted = false ORDER BY createdAt DESC
```

This statement filters with `isDeleted = false`, which is correct only when every document has the field; otherwise keep the `coalesce` form (see [Indexing soft-delete filters](#indexing-soft-delete-filters)).

Example output (one row, formatted for readability):

```json
{
  "advice": {
    "statement": "SELECT * FROM orders WHERE status = :status AND isDeleted = false ORDER BY createdAt DESC",
    "suggestedIndexes": [
      {
        "collection": "orders",
        "reason": "equality predicates on `isDeleted`, `status`; order by on `createdAt`",
        "statement": "CREATE INDEX IF NOT EXISTS adv_orders_isDeleted_status_createdAt ON default:`orders` (`isDeleted` ASC, `status` ASC, `createdAt` DESC)"
      }
    ]
  }
}
```

When related indexes already exist, they are listed in `existingIndexes`, and the suggestion builds on the query's predicates:

```json
{
  "advice": {
    "existingIndexes": [
      {"collection": "orders", "statement": "CREATE INDEX IF NOT EXISTS ix_cust ON default:`orders` (`cust` ASC)"}
    ],
    "statement": "SELECT * FROM orders WHERE cust = 'c1' AND total > 10",
    "suggestedIndexes": [
      {
        "collection": "orders",
        "reason": "equality predicates on `cust`; range predicates on `total`",
        "statement": "CREATE INDEX IF NOT EXISTS adv_orders_cust_total ON default:`orders` (`cust` ASC, `total` ASC)"
      }
    ]
  }
}
```

The `outcome` field explains when there is nothing to suggest. Values include `optimal indexes already exist`, `no advice available for statement` (for example for `INSERT ... DOCUMENTS` or a query that is already answered by an ID scan), and `no keys to advise on` (for example when every condition applies a function to the field, such as `coalesce(isDeleted, false) = false`).

`ADVISE AND PROVISION` returns the same advice **and creates** the suggested indexes, listing them in `createdIndexes` (and any failures in `failedIndexes`).

**✅ DO:**
- Run `ADVISE` for each important query during development and review the suggestions.
- Copy the suggested `CREATE INDEX IF NOT EXISTS` statements (you may rename them) into your startup code, so every device creates the same indexes.
- Rerun `ADVISE` when you add or change queries.

**❌ DON'T:**
- Run `ADVISE AND PROVISION` from production code paths; it creates indexes as a side effect, and the result depends on whichever queries happen to run.

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

### EXPLAIN and PROFILE

`EXPLAIN` and `PROFILE` answer different questions:

| | `EXPLAIN` | `PROFILE` |
|---|---|---|
| Executes the statement | ❌ (parse and plan only) | ✅ |
| Returns | The query plan | The normal results, followed by one extra profile row |
| Use it to | Check which access path and indexes are used | Measure where time is spent and how many documents flow through each step |
| Statements | `SELECT`, mutations, `CREATE INDEX` / `DROP INDEX`, and `ADVISE` (not `SHOW` or `ALTER SYSTEM`) | `SELECT` and mutations (`INSERT`, `UPDATE`, `DELETE`, `EVICT`); mutations are executed |

**❌ DON'T** use `EXPLAIN` to measure performance; it never runs the query. Use `PROFILE`.

#### Reading an EXPLAIN plan

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'open'
```

Example output (formatted):

```json
{"plan": {"#operator": "sequence", "children": [
  {"#operator": "indexScan", "collection": "orders", "desc": {"index": "idx_orders_status",
    "spans": [[{"index_key": {"direction": "asc", "include_missing": true, "key": ["status"]},
                "range": {"low": {"expr": "\"open\"", "included": true}, "high": {"expr": "\"open\"", "included": true}}}]]}},
  {"#operator": "fetch", "collection": "orders"},
  {"#operator": "filter", "condition": "(`orders`.`status` = \"open\")"},
  {"#operator": "finalProjection"}
]}}
```

Read the plan from top to bottom, in the order data flows. The operators you will see most often:

| Operator | Meaning |
|---|---|
| `scan` | Collection scan: every document is read. Expected for small collections, a warning sign for large ones |
| `indexScan` | Reads an index; `desc.index` names it, `spans` show the ranges, `covering: true` means the filter can be evaluated from the index (if no `fetch` step follows, the whole query is answered from the index) |
| `idScan` | Direct lookup by `_id` |
| `unionScan` / `intersectScan` | Combines several index scans for `OR` / `AND` |
| `countScan` | Answers `COUNT(*)` without reading documents |
| `fetch` | Loads the documents found by a scan |
| `filter` | Applies the full `WHERE` condition (always reapplied after an index scan) |
| `sort` / `limit` / `projection` | Ordering, row limit, and the `SELECT` list |
| `nlJoin` | Nested-loop JOIN (SDK 5.1+) |

#### Measuring with PROFILE

`PROFILE` runs the statement and appends a row with the key `~request_profile` after the normal results (for mutations without `RETURNING`, the profile row is the only row). Each operator in its `plan` carries `#stats` with `documentsIn`, `documentsOut`, and `phaseTimes`; `times` holds the overall `elapsed`, `parse`, and `plan` times (in nanoseconds).

```sql
PROFILE SELECT * FROM orders WHERE total = 5
```

Example profile row (abridged):

```json
{"~request_profile": {
  "plan": {"#operator": "sequence", "children": [
    {"#operator": "indexScan", "#stats": {"documentsOut": 1, "phaseTimes": {"exec": 21226, "recv": 41893, "send": 167}},
     "desc": {"index": "adv_orders_total"}},
    {"#operator": "fetch", "#stats": {"documentsIn": 1, "documentsOut": 1, "phaseTimes": {"exec": 1792, "recv": 61036, "send": 2976, "stor": 31309}}},
    {"#operator": "filter", "#stats": {"documentsIn": 1, "documentsOut": 1, "phaseTimes": {"exec": 1500, "send": 1268}}},
    {"#operator": "finalProjection", "#stats": {"documentsIn": 1, "documentsOut": 1}}
  ]},
  "queryType": "select", "resultCount": 1, "state": "completed",
  "times": {"elapsed": 196690, "parse": 9583, "plan": 31935}
}}
```

What to look for:

- A `filter` whose `documentsIn` is much larger than its `documentsOut`: many documents are read and then discarded. An index on the filtered field usually helps.
- A `scan` or `fetch` with a high document count on a large collection.
- `sort` or grouping steps on large inputs: they must collect all input before producing output, which costs memory.

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

#### Directives

Directives let you override the planner for a single statement. Use them only after `EXPLAIN` and `PROFILE` have shown that the planner's choice is wrong for your data:

```sql
-- Force a specific index (silently ignored if the index does not exist or cannot serve the query)
SELECT * FROM orders USE INDEX 'idx_orders_customerId' WHERE customerId = :customerId
```

- `USE INDEX ''` explicitly requests a collection scan (also used to allow a JOIN without an index on the inner collection).
- Comment-style directives (`/*+ {...} */`) and `USE DIRECTIVES` give finer control. Place them after `SELECT` or after the collection name; a directive comment after `WHERE` is ignored.
- The system parameter `DQL_DEFAULT_DIRECTIVES` sets default directives for every statement.
- Do not put directives in subscription queries; indexes and directives only affect local query execution.

See the [DQL directives documentation](https://docs.ditto.live/dql/directives) for the available directives.

### Query Scope and Execution

Indexes are only part of query performance. How much data a query touches and how often it runs matter just as much.

**✅ DO:**
- **Filter narrowly.** Put every condition you can into `WHERE` instead of filtering in Dart after the query.
- **Project only what you need.** `SELECT _id, status, total` materializes less data than `SELECT *` and can enable covering scans. (Subscriptions are different: they always sync whole documents and only accept `SELECT *`; see [Subscription Rules](#subscription-rules).)
- **Use `LIMIT` for local queries** that only need the first rows (for example the latest 50 orders), together with `ORDER BY`.
- **Keep query strings constant and pass values as parameters.** Ditto caches prepared statements; building a new string for every value defeats that cache and is unsafe (see [Parameters and Literals](#parameters-and-literals)).
- **Keep observer result sets small.** A store observer re-runs its query and delivers the full result set whenever relevant data changes. Prefer several focused observers with `WHERE` and `LIMIT` over one observer of a whole collection (see [Store Observers in Flutter](#store-observers-in-flutter)).

**❌ DON'T:**
- Observe an entire large collection and filter or paginate in Dart.
- Run queries in a tight loop when one query with `IN :ids` can return the same data.

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

#### Counting documents

A full-collection `COUNT(*)` is answered by a dedicated count scan (SDK 5.1+) without reading documents, so it is cheap enough for badges and dashboard totals. Ditto's 5.1 benchmark reported a full-collection `COUNT(*)` going from 149.03 ms to 0.89 ms (about 167x faster), and a filtered count improving from 60.85 ms to 13.89 ms (about 4.4x). These figures compare median runtimes of SDK 5.0.3 and 5.1.0 on a single Android device (Orion O6) with one retail dataset of about 93,000 documents. Performance depends on the device, data shape, indexes, and query mix, so test representative workloads on your target hardware.

A filtered `COUNT(*)` still has to evaluate the filter, so index the filtered fields. To check whether any matching document exists, `SELECT _id ... LIMIT 1` remains the simplest query.

#### Long-running requests (SDK 5.1+)

Two system parameters help you detect and contain slow DQL requests:

| Parameter | Default | Effect |
|---|---|---|
| `DQL_SLOW_REQUEST_WARN_SECONDS` | `60` | Logs a warning with the request details (the same information as `system:active_requests`) once a request has run this long, and repeats it at the same interval. `0` disables the warning |
| `DQL_REQUEST_TIMEOUT_SECONDS` | `0` (disabled) | Cancels requests that run longer than this and fails them with a timeout error. Cancellation is cooperative, so execution can continue briefly past the limit |

```sql
ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 10

ALTER SYSTEM SET DQL_REQUEST_TIMEOUT_SECONDS = 30
```

A lower warning threshold during development surfaces slow queries early. Apply these settings after every open (see [Applying System Parameters](#applying-system-parameters)). Before enabling a timeout in production, make sure your code handles the resulting error for every query.

#### Flutter execution model

On native platforms, `ditto.store.execute` runs the query on a long-lived worker isolate (one per `Ditto` instance), so a slow query does not block the UI isolate.

> **Advanced:** `Store.experimentalSkipExecuteIsolateOffload` (Experimental, default `false`) runs `execute` inline on the calling isolate instead. It avoids the per-call dispatch cost for tight loops of very small queries, but any slow query then blocks the calling isolate (usually the UI). The setting applies to every `Store` in the current isolate, persists across `Ditto.open` and `close` for the lifetime of the isolate, does not propagate to isolates you spawn, and has no effect on Web. Avoid toggling it while `execute` calls are in flight. Use it only after measuring a real throughput problem.

```dart
// Advanced (Experimental): only when queries are known to be short and
// throughput of many small queries matters more than UI responsiveness.
void enableInlineExecute() {
  Store.experimentalSkipExecuteIsolateOffload = true;
}
```

---

## Logging and Observability

Ditto provides three complementary sources of diagnostic information: SDK logs, local system virtual collections that describe the state of the device and the query engine, and remote diagnostics through the Ditto Portal.

### Logging

#### Configuring logging in Flutter

`DittoLogger` is a set of static members. Every member throws `Ditto not initialized` until the SDK is initialized, and `Ditto.open` initializes it implicitly. To configure logging **before** opening Ditto (recommended, so that startup is logged with your settings), call `await Ditto.init()` first:

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

**✅ DO:**
- Call `await Ditto.init()` before touching `DittoLogger` while Ditto is not open.
- Use `LogLevel.warning` in production and `LogLevel.debug` while debugging.
- Use `LogLevel.verbose` only for short, targeted investigations.

**❌ DON'T:**
- Leave `LogLevel.verbose` enabled in production; verbose logging can significantly slow down replication.
- Set `DittoLogger` properties before `Ditto.init()` (or `Ditto.open`) has completed; they throw.

#### Log levels

`LogLevel` has five values, from most to least severe:

| `LogLevel` | Typical use |
|---|---|
| `error` | Failures that need attention |
| `warning` | Unexpected situations Ditto handled (recommended for production) |
| `info` | High-level lifecycle events |
| `debug` | Detailed diagnostics (recommended while debugging) |
| `verbose` | Very detailed tracing; can slow down replication |

Defaults: `DittoLogger.isEnabled` is `true`, `DittoLogger.minimumLogLevel` is `LogLevel.info`, and `customLogCallback` is `null`. Set the level explicitly instead of relying on the default.

`DittoLogger.isEnabled` and `minimumLogLevel` control the logs Ditto emits at runtime. They do not affect the on-disk logs described below.

#### Forwarding logs to your own pipeline

`DittoLogger.customLogCallback` receives the log events that Ditto emits. Use it to forward Ditto logs to your logging or crash-reporting tool.

`ditto.close()` resets `customLogCallback` to `null` for the whole process, even if other `Ditto` instances are still open. If your app closes and reopens Ditto (for example when the user signs out and in again), set the callback again before each `Ditto.open()`, after `Ditto.init()`, so that logs emitted while Ditto opens are forwarded too.

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

Keep the callback fast and non-blocking; it is called for every log event.

In Flutter, `DittoLogger.isDevtoolsLoggingEnabled = true` additionally sends Ditto logs to Flutter DevTools through `dart:developer`.

#### On-disk logs and exporting them

Independently of `isEnabled` and `minimumLogLevel`, Ditto always collects a limited amount of logs at `LogLevel.debug` and above in the persistence directory of the most recently created `Ditto` instance. By default, Ditto retains about 15 MB of compressed logs or 15 days of logs, and periodically discards older entries once one of these limits is reached.

On-disk logs rotate in files of up to 1 MB or 24 hours each, and at most 15 files are kept (`ROTATING_LOG_FILE_MAX_SIZE_MB`, `ROTATING_LOG_FILE_MAX_AGE_H`, `ROTATING_LOG_FILE_MAX_FILES_ON_DISK`). Leave these at their defaults unless Ditto support advises otherwise.

The on-disk logs can be retrieved in two ways:

- **From the Ditto Portal:** request logs from a device on the device dashboard (see [Remote Diagnostics](#remote-diagnostics)).
- **From the app:** `DittoLogger.exportLogs(path)` writes them to a gzip-compressed JSON Lines file and returns the number of bytes written. The file must not already exist (otherwise it throws a `DittoError`) and its directory must exist. The recommended extension is `.jsonl.gz`. Only logs of the most recently created `Ditto` instance are exported.

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

Because the on-disk logs always include debug-level entries, setting the console level to `warning` in production does not reduce what you can retrieve later for support.

#### Configuration snapshots in data bundles (SDK 5.1+)

Data bundles requested through the Ditto Portal (see [Remote Diagnostics](#remote-diagnostics)) include a `config_snapshot.json` file with the device's effective configuration. This gives Ditto support the device's configuration at the start of every investigation.

### System Virtual Collections

The `system:` namespace contains virtual collections that describe the local device and its query engine. They are queried with ordinary `SELECT` statements and have these properties:

- **Local only:** they describe this device and are never synced. Use [Remote Diagnostics](#remote-diagnostics) to query other devices.
- **Read only:** `INSERT` and `UPDATE` on the `system` namespace are rejected. The one exception is `DELETE FROM system:request_history`, which clears the request history.
- **Snapshots:** values such as storage usage are collected periodically.

| Collection | Purpose |
|---|---|
| `system:system_info` | Key/value rows about the device: SDK version, database ID, peer key, storage usage, document counts per collection, local subscriptions, log settings, non-default system parameters (storage keys: see [Monitoring Storage](#monitoring-storage)) |
| `system:indexes` | Indexes defined on this device (see [Listing indexes](#listing-indexes)) |
| `system:data_sync_info` | One row per sync connection with its sync status (see [Monitoring Sync Status](#monitoring-sync-status)) |
| `system:active_requests` | DQL requests that are executing right now, with their plan and timings |
| `system:request_history` | Recently completed DQL requests that matched the history qualifiers (in memory, not persisted) |
| `system:shared_statements` | The prepared-statement cache, with per-statement execution statistics |
| `system:metrics` | SDK metrics. Disabled by default (`METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED` is `false`); when disabled, it returns a single row with `"status": "disabled"`. The parameter takes effect only at process start: `ALTER SYSTEM` after `Ditto.open` sets it but does not enable the collection. Setting the environment variable `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED=true` before the process starts works (verified with the JavaScript SDK on Node.js) |

`system:vitals` (query engine summary statistics) and `system:collections` (collection list) also exist.

**✅ DO:**
- Query system collections with `execute` when you need the information (a diagnostics screen, a support action, a periodic health log).
- Project only the keys you need from `system:system_info`.

**❌ DON'T:**
- Register long-lived observers on `system:system_info` (they fire every 500 ms regardless of whether anything changed; 20 callbacks in 10 idle seconds in tests), or observers on `system:data_sync_info` in many places. For live sync status, use a single observer with a trivial callback, as shown in [Monitoring Sync Status](#monitoring-sync-status).

#### system:system_info

Each row has `namespace`, `key`, `value`, and `timestamp`. Namespaces include `core`, `store`, `logs`, `replication`, `sync_scopes`, and `backend_sqlite3`.

```sql
-- SDK version, database ID, peer key, storage usage
SELECT key, value FROM system:system_info WHERE namespace = 'core'

-- Current log configuration: {"key": "enabled", ...}, {"key": "minimum_level", "value": "INFO"}
SELECT key, value FROM system:system_info WHERE namespace = 'logs'

-- Subscriptions registered on this device (value contains query and params)
SELECT key, value FROM system:system_info WHERE key LIKE 'local_subscriptions%'

-- System parameters that differ from their defaults
SELECT key, value FROM system:system_info WHERE key LIKE 'non_default_system_parameter%'
```

The last query is a convenient way to confirm that your `ALTER SYSTEM` settings were applied; for example, after `ALTER SYSTEM SET TOMBSTONE_TTL_HOURS = 120` it returns `{"key": "non_default_system_parameter[tombstone_ttl_hours]", "value": 120}`.

#### Request diagnostics

`system:active_requests` and `system:request_history` contain, per request, the statement `text`, its `state`, the executed `plan` with `#stats`, `queryType`, `requestType`, `resultCount`, and `times`.

```sql
SELECT _id, text, state, times FROM system:active_requests

SELECT text, state, times, `~qualifier` AS qualifier FROM system:request_history
```

- `system:request_history` is held in memory and is not persisted across restarts. Its size is controlled by `DQL_REQUEST_HISTORY_SIZE` (default `4096` entries).
- Which requests are recorded is controlled by `DQL_REQUEST_HISTORY_QUALIFIERS`, for example failed requests and requests slower than a threshold. Setting this parameter replaces the whole qualifier object; see the [virtual collections documentation](https://docs.ditto.live/dql/virtual-collections) for the available qualifiers.
- On Small Peers, querying `system:active_requests` at exactly the right moment is often impractical; the slow-request warning (see [Long-running requests (SDK 5.1+)](#long-running-requests-sdk-51)) writes the same details to the log.

```dart
// ✅ GOOD: Collect a small diagnostics snapshot on demand.
Future<Map<String, Object?>> diagnosticsSnapshot(Ditto ditto) async {
  Future<List<Map<String, dynamic>>> rows(String query) async {
    final result = await ditto.store.execute(query);
    return result.items.map((item) => item.value).toList();
  }

  return {
    'core': await rows(
      "SELECT key, value FROM system:system_info "
      "WHERE namespace = 'core' AND key LIKE 'ditto_sdk%'",
    ),
    'nonDefaultParameters': await rows(
      "SELECT key, value FROM system:system_info "
      "WHERE key LIKE 'non_default_system_parameter%'",
    ),
    'syncConnections': await rows('SELECT * FROM system:data_sync_info'),
    'indexes': await rows('SELECT _id FROM system:indexes'),
    'activeRequests': await rows(
      'SELECT _id, text, state, times FROM system:active_requests',
    ),
  };
}
```

### System Parameters Reference

System parameters tune the behavior of the local Ditto instance. Read them with `SHOW` and change them with `ALTER SYSTEM`:

```sql
SHOW TOMBSTONE_TTL_HOURS

SHOW ALL LIKE 'dql_slow%'

ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 30

ALTER SYSTEM RESET DQL_SLOW_REQUEST_WARN_SECONDS
```

- `ALTER SYSTEM SET <name> = <value>` and `ALTER SYSTEM SET <name> TO <value>` are equivalent; `SET <name> TO DEFAULT` and `RESET <name>` restore the default (`RESET ALL` restores every parameter).
- `SHOW ALL` returns a single row with every parameter; `SHOW ALL LIKE '<pattern>'` (or `ILIKE`) narrows it.
- Parameter names are case-insensitive (`DQL_STRICT_MODE` and `dql_strict_mode` are the same parameter).
- Unknown names fail with `unknown parameter '<name>'`, and values of the wrong type fail with a type error.
- **Settings are not persisted.** After closing and reopening Ditto, every parameter is back at its default. Apply your settings after every `Ditto.open`, before `ditto.sync.start()` and before queries or observers run; see [Applying System Parameters](#applying-system-parameters).

Parameters most relevant to app developers:

| Parameter | Default | Purpose | See |
|---|---|---|---|
| `DQL_STRICT_MODE` | `false` | When `true`, objects are treated as registers unless declared; in 5.1.0 the planner then does not use secondary indexes | [Strict Mode](#strict-mode) |
| `DQL_RESTRICT_SUBSCRIPTIONS` | `true` | Rejects `LIMIT` and `ORDER BY` in subscription queries | [Subscription Rules](#subscription-rules) |
| `USER_COLLECTION_SYNC_SCOPES` | `{}` | Per-collection sync scopes; set before `ditto.sync.start()` | [Sync Scopes](#sync-scopes) |
| `TOMBSTONE_TTL_ENABLED` | `true` | Automatic removal of expired tombstones | [Tombstone TTL and reaping](#tombstone-ttl-and-reaping) |
| `TOMBSTONE_TTL_HOURS` | `168` | Tombstone TTL on this device (never above the Ditto Server TTL) | [Tombstone TTL and reaping](#tombstone-ttl-and-reaping) |
| `DAYS_BETWEEN_REAPING` | `1` | Days between tombstone reaping runs | [Tombstone TTL and reaping](#tombstone-ttl-and-reaping) |
| `TOMBSTONE_REAP_BATCH_SIZE` (SDK 5.1+) | `10000` | Batch size for removing expired tombstones | [Tombstone TTL and reaping](#tombstone-ttl-and-reaping) |
| `DISABLE_REPLICATION_GC_ON_EVICT` | `false` | Skips immediate per-peer metadata cleanup on eviction (advanced) | [Eviction frequency](#eviction-frequency) |
| `DQL_SLOW_REQUEST_WARN_SECONDS` (SDK 5.1+) | `60` | Warning log for requests running longer than this; `0` disables | [Long-running requests (SDK 5.1+)](#long-running-requests-sdk-51) |
| `DQL_REQUEST_TIMEOUT_SECONDS` (SDK 5.1+) | `0` | Request timeout in seconds; `0` disables | [Long-running requests (SDK 5.1+)](#long-running-requests-sdk-51) |
| `DQL_REQUEST_HISTORY_SIZE` | `4096` | Number of entries kept in `system:request_history` | [Request diagnostics](#request-diagnostics) |
| `DQL_DEFAULT_DIRECTIVES` | `{}` | Default directives for every statement | [Directives](#directives) |
| `DOCUMENT_SIZE_SOFT_LIMIT_BYTES` | `262144` (256 KiB) | Documents above this size log a warning | [Document Size Limits](#document-size-limits) |
| `DOCUMENT_SIZE_HARD_LIMIT_BYTES` | `5242880` (5 MiB) | Writes that make a document larger than this fail | [Document Size Limits](#document-size-limits) |
| `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED` (SDK 5.1+) | `true` | Certificate revocation checks for peer connections | [Certificate Revocation (SDK 5.1+)](#certificate-revocation-sdk-51) |
| `METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED` | `false` | Enables the `system:metrics` virtual collection; only at process start (environment variable `DITTO_METRICS_EXPORTER_VIRTUAL_COLLECTION_ENABLED`) | [System Virtual Collections](#system-virtual-collections) |
| `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` | `6` | Connections a device accepts over TCP (other transports were not tested); set it on a hub before `ditto.sync.start()` | [Transport Configuration](#transport-configuration) |
| `ROTATING_LOG_FILE_MAX_SIZE_MB` / `ROTATING_LOG_FILE_MAX_AGE_H` / `ROTATING_LOG_FILE_MAX_FILES_ON_DISK` | `1` / `24` / `15` | On-disk log rotation; leave at defaults unless Ditto support advises otherwise | [On-disk logs and exporting them](#on-disk-logs-and-exporting-them) |

`SHOW ALL` lists several hundred parameters. Most of them are internal tuning knobs for transports, sync, and storage. Do not change parameters that are not documented for your use case without guidance from Ditto support.

#### Applying parameters at startup

Because settings are not persisted, keep them in one place and apply them each time Ditto is opened. A compact way to verify the result is to read back the non-default parameters:

```dart
/// Applies this app's system parameters. Call after every Ditto.open()
/// and before ditto.sync.start().
Future<void> applyDiagnosticsParameters(Ditto ditto) async {
  await ditto.store.execute('ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 30');

  final result = await ditto.store.execute(
    "SELECT key, value FROM system:system_info "
    "WHERE key LIKE 'non_default_system_parameter%'",
  );
  for (final item in result.items) {
    debugPrint('${item.value['key']} = ${item.value['value']}');
  }
}
```

See [Applying System Parameters](#applying-system-parameters) for the complete startup sequence.

### Remote Diagnostics

The Ditto Portal complements on-device diagnostics. The [device dashboard](https://docs.ditto.live/cloud/portal/capturing-small-peer-info), which is populated from the Small Peer Info system collection, shows each device's mesh connection status, the time it was last seen by Ditto Server, its name and peer key, its operating system, its latest logs, and custom metadata that your app sets through `ditto.smallPeerInfo`. From a device's detail page you can request its logs or a data bundle (logs and other diagnostic data). Requests and uploads travel through sync, so a device does not need to be online when you make the request; it uploads the data when it next connects. See the [Ditto Portal troubleshooting documentation](https://docs.ditto.live/cloud/portal/troubleshooting) for the steps and required Portal permissions, and [Remote Observability](https://docs.ditto.live/sdk/latest/deployment/device-observability-and-ditto-logs) for the SDK side.

---

## Security

Ditto syncs data directly between devices, so security decisions apply to every peer in the mesh, not only to a server. This section covers authentication, authorization, transport and storage protection, and input handling.

### Security Model Overview

| Layer | How Ditto protects it |
|---|---|
| Peer identity | Each authenticated peer holds a certificate issued for its identity. With a shared key, each peer issues a self-signed certificate with the shared private key. |
| Encryption in transit | TLS 1.3 between peers (mutual TLS) and TLS between peers and Ditto Server. **Exception:** `DittoConfigConnectSmallPeersOnly()` without a `privateKey` has no secret: peers do not authenticate each other, and the SDK documents the mode as unencrypted (see [Small-Peers-Only Deployments](#small-peers-only-deployments)). |
| Authorization | Read and write permissions returned by your authentication webhook, enforced by Ditto Server and by every participating device. |
| Revocation | Certificates issued to server-authenticated peers can be revoked centrally (SDK 5.1+). |
| Data at rest | Not encrypted by Ditto. Rely on OS protections and application-level encryption (see [Data at Rest](#data-at-rest)). |

### Authentication in Production

For production apps with real users, connect with `DittoConfigConnectServer` and authenticate through an **authentication webhook** that you operate:

1. Your app signs the user in with your own identity system and receives a token (often a JWT).
2. In the expiration handler, the app calls `ditto.auth.login(token: ..., provider: 'YOUR_PROVIDER_NAME')`.
3. Ditto Server forwards the token to your webhook, which validates it and returns the user's ID, session lifetime, and permissions.
4. Ditto Server issues credentials to the device, and the device can sync within those permissions.

**✅ DO:**
- Use a webhook-based authentication provider for production.
- Issue short-lived tokens from your backend and fetch a fresh token every time the expiration handler runs.
- Keep `expirationSeconds` moderate (the example in [Webhook response](#webhook-response) uses 28800 seconds, 8 hours): permissions are issued together with the credentials, so changes in your webhook reach a device when it re-authenticates.
- Reject unknown or disabled users in the webhook with `{"authenticated": false}`.

**❌ DON'T:**
- Ship the development provider (`Authenticator.developmentProvider`) or the development token from the Ditto Portal in a production build. Anyone who has the development token gets the same access.
- Embed long-lived secrets or API keys in the app to mint tokens on the device.
- Rely only on client-side checks to restrict data access.

The client-side setup (expiration handler, `login`, `AuthResponse.exception`, `logout`) is described in [Authentication](#authentication).

### Small-Peers-Only Deployments

`DittoConfigConnectSmallPeersOnly(privateKey: key)` lets devices sync without Ditto Server, for example in air-gapped or closed networks. All peers share one private key and trust any peer that holds it.

**✅ DO:**
- Always pass a `privateKey` in production. Without it, peers do not authenticate each other: any device that runs the SDK with your Database ID (and a valid offline license token) can join the mesh and read and write all data. The SDK's API documentation describes this mode as using no encryption in transit. In SDK 5.1.0 tests over TCP, the bytes were still TLS-wrapped, but with no secret involved, so treat the mode as unprotected.
- Roll out a new key to all devices together. Peers with different keys, or a peer with a key and one without, never connect. No API reports this; only `WARN` log lines appear on every retry (`invalid peer certificate: BadSignature`, or `DecryptError`).
- Distribute the key through a controlled channel, such as mobile device management (MDM) or secure provisioning, and keep it in secure storage on the device.
- Generate the key with Ditto's `ditto-authtool` or OpenSSL as described in the [authentication documentation](https://docs.ditto.live/key-concepts/authentication-and-authorization).
- Set the offline license token from Ditto with `ditto.setOfflineOnlyLicenseToken()` before `ditto.sync.start()`.

**❌ DON'T:**
- Hardcode the shared key in source code. Keys in an app binary can be extracted by decompiling the app.
- Use a shared key when you need per-user permissions or the ability to revoke a single device.

**Why:** Shared-key mode has no per-user identity. Every holder of the key has full access, individual devices cannot be revoked, and a leaked key compromises the whole deployment. If you need per-user access control or revocation, use a server connection with an authentication webhook.

```dart
// ✅ GOOD: The key and license token come from secure provisioning.
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

### Permissions

Your authentication webhook returns the user's permissions together with the authentication result. Permissions are expressed per collection as lists of queries for `read` and `write`.

#### Webhook response

The webhook response must contain these fields (see the [authentication provider documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication) for the full schema):
- `authenticated`
- when `authenticated` is `true`: `userID`, `expirationSeconds`, and `permissions`
- in each of `permissions.read` and `permissions.write`: both `everything` (boolean) and `queriesByCollection`

Use the response format and the permission query syntax shown in Ditto's [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) for the Ditto Server version you use.

```json
{
  "authenticated": true,
  "userID": "user-123",
  "expirationSeconds": 28800,
  "permissions": {
    "read": {
      "everything": false,
      "queriesByCollection": {
        "orders": ["_id.storeId == 'store-1'"],
        "products": ["true"]
      }
    },
    "write": {
      "everything": false,
      "queriesByCollection": {
        "orders": ["_id.storeId == 'store-1'"]
      }
    }
  }
}
```

Express permission rules as simple comparisons on `_id` fields, as in the example above. Permission queries use Ditto's legacy query syntax, not DQL: compare with `==` (as in `_id.storeId == 'store-1'`), not with the DQL `=`. Note that `"true"` is a query string that matches every document (not a boolean). See the [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) before using more complex rules.

#### Design `_id` for permission scoping

Permission queries can only reference the document's `_id`. Permissions on other (mutable) fields are not supported. Put every attribute you need for access control into a structured `_id`:

```dart
// ✅ GOOD: The store that owns the order is part of the immutable _id,
// so a permission rule such as "_id.storeId == 'store-1'" can match it.
Future<void> createOrder(Ditto ditto, String storeId, String orderId) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': {'storeId': storeId, 'orderId': orderId},
        'status': 'open',
        // utcTimestamp() is defined in the Timestamps section.
        'createdAt': utcTimestamp(),
      },
    },
  );
}
```

**✅ DO:**
- Decide on permission boundaries (user, store, organization) before shipping, and encode them in `_id`.
- Grant the narrowest `read` and `write` rules each role needs.

**❌ DON'T:**
- Plan to restrict access by a mutable field such as `status` or `ownerId`.
- Change the structure of `_id` later; document IDs cannot be changed after creation. See [Document IDs](#document-ids).

#### Write authority and peer-to-peer relaying

Ditto's [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) describes how write permissions affect relaying: a device accepts a document from another peer only if that peer is authorized to write the document. As a result, data that must travel peer-to-peer requires mutual write permissions: a peer with read-only access to a document cannot relay it to a third device, even if both are subscribed. Take this into account for read-only roles (for example, customers who read messages written by staff); the same page describes the read-only model and its trade-offs.

#### Identity metadata is visible to the mesh

The optional `identityServiceMetadata` returned by your webhook is signed and shared with every peer in the mesh, not only with directly connected peers (for example, through presence and connection requests). Keep it small and never put secrets or personal data in it that other peers should not see. The same applies to peer metadata you set through presence (see [Presence](#presence)).

### Certificate Revocation (SDK 5.1+)

With server authentication, you can revoke the certificates of users or devices that should lose access, for example after offboarding or when a device is lost. Revocations are created through the Ditto Server HTTP API with a filter on `userID` or `identityServiceMetadata` fields, signed, and propagated from Ditto Server to Small Peers and from peer to peer. Each peer verifies the revocation, refuses new connections from revoked peers, and drops existing ones.

**✅ DO:**
- **Reject the identity in your authentication webhook first**, then create the revocation. A revocation only applies to certificates issued before it was created; if the webhook still accepts the user, the device re-authenticates and regains access with a new certificate.
- Expect a delay for peers that are fully offline: they learn about the revocation when they next connect to a peer that has it.
- Treat revocations as permanent; they cannot be deleted.

**❌ DON'T:**
- Disable revocation checking in production.
- Expect revocation to work in shared-key deployments; it applies only to server-authenticated identities.

Revocation checking is **enabled by default** and controlled by the system parameter `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED`:

```sql
SHOW PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED
```

See the [revocations documentation](https://docs.ditto.live/cloud/revocations) for the HTTP API.

### Controlling Incoming Connections

You can decide per connection whether to accept a peer, for example based on the signed `identityServiceMetadata`. The handler must return `allow` or `deny`. A handler that does not respond within about 10 seconds denies the connection, so keep it fast.

In SDK 5.1.0 tests, the handler behaved as follows:
- **Both directions:** despite the section title, the handler also runs for connections that this device initiates, and `deny` blocks them too.
- **New connections only:** switching the handler to `deny` does not drop existing connections. Setting it back to `null` lets peers in again.
- **Retries:** a denied peer retries about once per second, so the handler runs about once per second for each rejected peer. The rejected peer gets no API signal; only an error appears in its log.
- **Errors:** a handler that throws, or whose `Future` fails, denies the connection, but only after the 10-second timeout (observed in the JavaScript SDK). Catch errors and return `deny` explicitly.
- **Small-peers-only mode:** `identityServiceMetadata` is always empty, because there is no authentication webhook. `peerMetadata` is available, but each peer sets its own, so it is not a security check.

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
      return ConnectionRequestAuthorization.deny; // decide now, not after the timeout
    }
  };
}
```

Permissions remain the primary access control; a connection handler is an additional filter. `global.syncGroup` in the transport configuration is an optimization, not a security boundary.

### Input Validation and Query Parameters

Ditto collections are schema-free, so the application is responsible for validating data before writing it. Always pass values to DQL as parameters.

**✅ DO:**
- Validate required fields, types, and ranges before `INSERT` or `UPDATE`.
- Pass every value through `arguments` (`:name` placeholders), including documents (`INSERT INTO orders DOCUMENTS (:order)`).
- Treat documents received from other peers as untrusted input when you render or process them.

**❌ DON'T:**
- Build DQL strings by interpolating user input.

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

```dart
// ❌ BAD: User input becomes part of the query text (DQL injection).
Future<void> findOrdersByName(Ditto ditto, String name) async {
  await ditto.store.execute("SELECT * FROM orders WHERE customerName = '$name'");
}
```

**Why:** Parameters keep values separate from the query text, so input cannot change the meaning of a statement. See [Parameters and Literals](#parameters-and-literals).

### Data at Rest

The Ditto SDK does **not** encrypt its local database at rest, and there is no supported API to enable it.

**✅ DO:**
- Rely on OS-level protection (iOS Data Protection, Android file-based encryption). These require a passcode or screen lock, and with the default settings they protect data mainly while the device is powered off or has not been unlocked since it started; they do not protect data on a device that has been unlocked since boot.
- For regulated or sensitive data, encrypt sensitive field values in your application before writing them to Ditto, and keep the keys in the platform's secure storage.
- On managed devices, enforce device encryption and screen locks through MDM.

**❌ DON'T:**
- Assume that apps installed from a public app store run on devices with encryption enabled; your app cannot enforce it.
- Store secrets such as tokens or keys in Ditto documents.

In Flutter Web apps, data is kept in memory only and is not written to disk.

### Webhook Security

Your authentication webhook decides who can access your data, so protect it like any other authentication endpoint:

- Serve it over HTTPS only, and validate the token's signature, issuer, audience, and expiry before returning `"authenticated": true`.
- Enable **webhook signatures** in the Ditto Portal or HTTP API. Ditto then sends a `ditto-signature` header (`t=<timestamp>,v1=<signature>`), an HMAC-SHA256 of `<timestamp>.<raw request body>` computed with your base64-decoded secret.
- Verify the signature against the **raw** request body (not re-serialized JSON), compare signatures in constant time, and reject requests whose timestamp is more than 300 seconds old.
- Accept any of the `v1` signatures during secret rotation, and rotate secrets periodically.

See the [webhook security documentation](https://docs.ditto.live/cloud/webhook-security) for reference implementations.

### Security Checklist

**✅ DO:**
- Use a server connection with a webhook-based authentication provider in production.
- Fetch fresh tokens from your backend in the expiration handler, and check `AuthResponse.exception`.
- Return `everything` and `queriesByCollection` for both `read` and `write` in webhook responses, in the format shown in the data authorization documentation, with the narrowest rules each role needs.
- Model access-control attributes in `_id`.
- Reject identities in the webhook before creating a revocation, and keep revocation checking enabled.
- Always use a `privateKey` in small-peers-only deployments, and provision it securely.
- Validate input and pass all values as DQL parameters.
- Protect sensitive data at rest with OS protections and application-level encryption.
- Verify webhook signatures.

**❌ DON'T:**
- Ship the development provider or development token.
- Hardcode shared keys, tokens, or API keys in the app.
- Use `DittoConfigConnectSmallPeersOnly()` without a key outside development and tests.
- Rely on mutable fields, `syncGroup`, sync scopes, or client-side checks for access control.
- Put sensitive information in `identityServiceMetadata` or peer metadata.
- Store secrets such as tokens or keys in Ditto documents.
- Interpolate user input into DQL strings.

---

## Testing Strategies

Many problems in Ditto apps come from the data model and the queries: a write that replaces a map instead of updating one entry, a soft-delete filter that hides documents without the flag, an observer that is never cancelled. These are cheap to catch in automated tests that run against a **real local Ditto store** on a single device. Multi-device behavior (concurrent edits, deletions that meet updates, multi-hop relay) needs a separate, smaller set of tests with real sync; most of them can run as several Ditto instances in one test process (see [Several peers in one test process](#several-peers-in-one-test-process)).

| Test layer | What it covers | Ditto instance | License or server needed |
|---|---|---|---|
| Unit tests with a mock | UI and business logic that only needs your repository interface | None (mock your own interface) | No |
| Local store tests | Your DQL statements, write shapes, soft-delete filters, observer and subscription lifecycle | Real, small-peers-only, sync never started | No |
| Multi-peer tests in one process | Concurrent edits and merges, deletion propagation, relay, attachments across peers | Several real instances syncing over TCP on localhost | Yes: an offline license token |
| Tests on real devices | Transports (Bluetooth LE, P2P Wi-Fi, LAN), permissions, Ditto Server, real clocks | Your app on devices | An offline license token, or a Ditto Server test database |

**✅ DO:**
- Keep Ditto behind a repository or service interface in your app, so widgets and business logic can be unit-tested with a mock.
- Test every DQL statement your app uses against a real local store, with a fresh temporary persistence directory per test.
- Apply the same system parameters in tests as in the app (for example `DQL_STRICT_MODE`), because they change how statements behave and are not persisted (see [Applying System Parameters](#applying-system-parameters)).
- Close every instance in `tearDown` (or `addTearDown`) so that no persistence directory stays open.

**❌ DON'T:**
- Share one persistence directory between tests or open it twice; in Flutter, a second `Ditto.open()` on an open directory may never complete (see [One instance per persistence directory](#one-instance-per-persistence-directory)).
- Start sync in local store tests. It is not needed, and in small-peers-only mode `ditto.sync.start()` throws without an offline license token (see [Initializing Ditto](#initializing-ditto)).
- Write tests that only re-check SDK behavior. Test your own repository functions, your data model, and your business rules.

### A Test Helper for a Local Store

The test file below contains a helper that opens a small-peers-only instance (the default `connect` mode) in its own temporary directory and closes it automatically when the test ends. Because sync is never started, it needs no license token and no network, so it can run in CI. Pass a `configure` callback to apply the same system parameters and indexes that your app applies at startup. As your suite grows, move the helper into a shared file under `integration_test/`.

```dart
// integration_test/orders_test.dart
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Opens a Ditto instance for one test. Sync is never started, so no
/// license token or network connection is needed.
Future<Ditto> openTestDitto({
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  final ditto = await Ditto.open(
    DittoConfig(
      // Any UUID works for local tests; each test gets its own directory.
      databaseID: '00000000-0000-4000-8000-000000000001',
      persistenceDirectory: directory.path,
    ),
  );

  // Runs after the test, even when it fails.
  addTearDown(() async {
    await ditto.close();
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort: the OS removes temporary directories eventually.
    }
  });

  // Apply the app's system parameters and indexes, as at app startup.
  await configure?.call(ditto);
  return ditto;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Every test starts with an empty store.
  late Ditto ditto;
  setUp(() async {
    // Pass `configure:` with the setup your app runs after Ditto.open
    // (system parameters, indexes); see "Applying System Parameters".
    ditto = await openTestDitto();
  });

  test('a new store is empty', () async {
    final result = await ditto.store.execute('SELECT COUNT(*) AS n FROM orders');
    expect(result.items.first.value['n'], 0);
  });

  // The tests in the following sections go here.
}
```

**Running the tests:** A real `Ditto` instance needs the SDK's native library, which is packaged with your app build for each platform. Run tests that open Ditto with the `integration_test` package on a supported desktop or device target, for example `flutter test integration_test/orders_test.dart -d macos`. Tests that use only a mock of your own interface run with a plain `flutter test`. On Flutter Web the store is in memory and does not support indexes (see [Requirements](#requirements)), so skip index assertions there.

The following examples are written as `test(...)` calls (and, in one case, a helper function) that go inside `main()` of such a file, with `ditto` provided by `setUp`. Their `import` lines belong at the top of the file. The examples define the statements and functions under test inline so that each one is complete; in your suite, call your app's repository functions instead, so that a test fails when the app code changes.

### Testing Merge-Sensitive Writes

A single device cannot reproduce a concurrent merge, but it can verify that your code produces the **write shape** that merges well: field-level updates instead of whole-document rewrites, maps keyed by ID instead of arrays, and upserts that skip unchanged values (see [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior) and [Arrays and Maps](#arrays-and-maps)). Assert the local semantics your code relies on, so that a refactoring that switches to a whole-document write or an array is caught.

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

If your app declares types (`REGISTER`, `COUNTER`, `ATTACHMENT`) or enables strict mode, test those statements with the same declarations and settings; mixed declarations produce results that look like data loss (see [Keep type declarations consistent](#keep-type-declarations-consistent)).

### Testing Deletion and Soft Delete

Deletion logic fails silently: a filter that excludes documents without the flag, or a statement that completes without removing anything. Insert documents in every state your data can be in (flag `true`, `false`, `null`, and missing) and assert exactly which ones your queries return (see [Soft Delete](#soft-delete) and [MISSING and NULL](#missing-and-null)).

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

Assertions on the number of removed documents also catch the 5.1.0 behavior where `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) removes nothing (see [DELETE and Tombstones](#delete-and-tombstones)). Tombstone expiry, husk documents, and "zombie data" from devices that were offline longer than the tombstone TTL involve several peers; cover them in multi-device tests (see [Testing on Multiple Devices](#testing-on-multiple-devices)).

### Testing Observer Lifecycle

Test that your observers deliver updates, and that your cleanup code cancels both the stream subscription and the observer (see [Observer lifecycle and cleanup](#observer-lifecycle-and-cleanup)). Wait for a specific result with a timeout instead of a fixed delay, and do not assert on the number of callbacks; it is not guaranteed.

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

For widget tests of screens that own observers, keep the observer behind your own interface and inject a stream you control. `Differ` only accepts items produced by Ditto, so code that uses it needs a real store (see [Diffing Results](#diffing-results)).

### Testing Subscription Rules

`registerSubscription` validates the query when it is called and throws a `DittoException` for projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, `USE IDS`, and (while the system parameter `DQL_RESTRICT_SUBSCRIPTIONS` has its default value `true`) `ORDER BY` and `LIMIT`, even before sync starts; `WHERE` filters are allowed (see [Subscription Rules](#subscription-rules)). A test that registers every subscription your app uses catches invalid subscription queries without a network. You can also assert that the forms your app must not use are rejected:

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

The positive counterpart registers the app's real subscriptions and cancels them:

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

### Validating DQL in Tests

Keep the DQL statements of your app as constants in one place (for example, a repository class), and run each of them through `EXPLAIN` with representative arguments. `EXPLAIN` parses and plans a statement without executing it (see [EXPLAIN and PROFILE](#explain-and-profile)), so the test catches syntax errors and other statements that cannot be planned without touching data. For hot queries, also assert that the plan uses the index you created; a later change to the query or to strict mode (which disables index scans in 5.1.0, see [Strict Mode](#strict-mode)) then fails the test.

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

During development, `ADVISE` (SDK 5.1+) suggests the indexes these statements need (see [ADVISE (SDK 5.1+)](#advise-sdk-51)).

### Testing on Multiple Devices

Concurrent edits, merges, deletion propagation, multi-hop relay, and attachment fetching across peers can only be tested with sync running between real Ditto instances. Most of these tests do not need several physical devices: several instances in one test process can sync with each other over TCP on localhost (see the next section).

- **Small-peers-only sync** requires an **offline license token** from Ditto: `ditto.sync.start()` throws until `ditto.setOfflineOnlyLicenseToken(token)` has been called with a valid token (see [Initializing Ditto](#initializing-ditto)). Without a token, tests are limited to a single local store. Keep the token out of source control; pass it to tests from a CI secret.
- **Sync through Ditto Server** requires a Ditto Server database for testing. Use separate databases (apps) for development, staging, and production, or one database per developer; developers who share a database can prefix collection names to isolate their test data. There is no Ditto Server mock for CI, so run these tests against a test database.
- **Offline scenarios**: To simulate a Ditto Server outage while keeping peer-to-peer sync, let the app authenticate first and then block the Ditto Server host at the network level; blocking it before authentication makes sync fail entirely.

#### Several peers in one test process

The helpers below open several small peers in one `integration_test` process and connect them over TCP on `127.0.0.1` only:
- Each peer has its own persistence directory, and all peers share one database ID.
- Peer-to-peer transports are disabled, so a test never connects to devices nearby.
- `whileDisconnected` stops sync on every peer, runs the writes, and reconnects the peers. Writes made inside it are concurrent, like edits on devices that are offline at the same time. Writes made while the peers are connected reach the other peers within milliseconds and do not test a merge.
- `waitForConvergence` waits, with a timeout, until every peer returns the same rows.

The file was verified with `ditto_live` 5.1.0 and `flutter test integration_test/multipeer_test.dart -d macos --dart-define-from-file=license.json`, where `license.json` (not committed) contains `{"DITTO_LICENSE_TOKEN": "..."}`.

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

/// Opens [count] peers in this process that sync with each other over TCP on
/// localhost only: peer 0 listens, the others connect to it. A device accepts
/// at most 6 TCP connections by default, so keep [count] at 7 or below.
Future<List<Ditto>> openSyncedPeers(
  int count, {
  int port = 4041,
  Future<void> Function(Ditto ditto)? configure,
}) async {
  final peers = <Ditto>[];
  for (var i = 0; i < count; i++) {
    final directory = await Directory.systemTemp.createTemp('ditto_peer${i}_');
    final ditto = await Ditto.open(
      DittoConfig(
        // All peers must use the same database ID to sync.
        databaseID: '00000000-0000-4000-8000-000000000002',
        persistenceDirectory: directory.path,
      ),
    );
    addTearDown(() async {
      await ditto.close();
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    });
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
      }
    });
    await configure?.call(ditto); // system parameters, as in the app
    ditto.sync.start();
    peers.add(ditto);
  }
  await _waitUntil(() => peers.every(_isConnected));
  return peers;
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

What this setup does not cover, so keep a few tests on real devices:
- All peers share one clock. Clock skew between devices is not simulated.
- Only TCP is exercised. Bluetooth LE, P2P Wi-Fi, LAN discovery, permissions, and app lifecycle need real devices.
- A listening peer accepts at most 6 TCP connections by default (see [Transport Configuration](#transport-configuration)). For a relay test, chain the peers: A listens, B listens and connects to A, and C connects to B.

Scenarios worth covering (with the helpers above, or on real devices):
- Two devices edit **different fields** and the **same field** of one document while offline, then reconnect.
- Two devices add, edit, and remove entries of the same map (and, for comparison, the same array) while offline.
- One device deletes a document while another updates it (expect a [husk document](#husk-documents)), and the same with a soft delete.
- A counter that one device recounts with `RESTART WITH` while another keeps incrementing it (see [RESTART](#restart)).
- A device behind a relay with narrower subscriptions (see [Multi-hop relay](#multi-hop-relay)).
- Attachments created offline and fetched by other peers later (see [Availability](#availability)).
- Each transport your users rely on, including Bluetooth LE only (real devices).

See the [testing guide](https://docs.ditto.live/sdk/latest/deployment/testing) for environment setup and offline simulation.

---

## Anti-Pattern Checklist

Use this list in code reviews. Each item links to the section that explains the problem and the recommended pattern.

### Critical (data loss, wrong results, crashes, security)

- [ ] Reading a whole document, changing it in memory, and writing it back with `ON ID CONFLICT DO UPDATE` for data that other devices edit → [Prefer field-level updates over whole-document rewrites](#prefer-field-level-updates-over-whole-document-rewrites)
- [ ] Arrays for line items, participants, or other lists that several devices edit (one device's change is lost) → [Arrays and Maps](#arrays-and-maps)
- [ ] Expecting `SET obj = {...}` or `ON ID CONFLICT DO UPDATE` to remove keys that were left out → [Assigning an object merges it](#assigning-an-object-merges-it)
- [ ] `SET stock = stock - 1` on values that several devices change instead of a `COUNTER` → [Counters](#counters)
- [ ] `RESTART WITH` to recalibrate a counter that other devices keep changing while offline (their unsynced increments are discarded, even later ones) → [RESTART](#restart)
- [ ] Sequential or timestamp-only document IDs (offline devices create the same ID, and the documents merge) → [Never use sequential or timestamp-only IDs](#never-use-sequential-or-timestamp-only-ids)
- [ ] Soft-delete filters written as `isDeleted != true` or `NOT isDeleted` (documents without the flag disappear) → [Soft Delete](#soft-delete) <!-- lint-ignore -->
- [ ] `IN (:values)` with an array parameter (matches nothing) → [Parameters and Literals](#parameters-and-literals)
- [ ] `ANY` or `EVERY ... SATISFIES ... END` over a parameter or literal array in `WHERE`, such as `ANY s IN :statuses SATISFIES s = status END` (returns no rows in local queries and observers in 5.1.0, although the subscription syncs the documents; use `status IN :statuses`) → [Filtering by Membership](#filtering-by-membership) <!-- lint-ignore -->
- [ ] `DELETE` or `EVICT` with `USE IDS` and no `WHERE` predicate (no `WHERE` clause, or `WHERE true`) (removes nothing in 5.1.0; use `WHERE _id IN :ids`) → [DELETE and EVICT](#delete-and-evict)
- [ ] `DELETE` for documents that other devices may update concurrently (husk documents: not deleted even when the `DELETE` is later; untouched fields become missing) → [Husk documents](#husk-documents)
- [ ] `DELETE` when devices can stay offline longer than the tombstone TTL (deleted data comes back) → [Tombstone TTL and reaping](#tombstone-ttl-and-reaping)
- [ ] `DELETE` used to free storage on one device (it removes the documents for every peer; use `EVICT`) → [DELETE and Tombstones](#delete-and-tombstones), [EVICT](#evict)
- [ ] A plain `INSERT` or `ON ID CONFLICT DO UPDATE` for default data that every device creates (the second run fails with an ID conflict, or users' edits are overwritten) → [Default Data with INITIAL Documents](#default-data-with-initial-documents)
- [ ] Different `INITIAL DOCUMENTS` content for the same `_id` across app versions (removed keys come back from old versions; IDs deleted elsewhere become documents with `null` fields) → [Default Data with INITIAL Documents](#default-data-with-initial-documents)
- [ ] `DQL_STRICT_MODE = true` without understanding the consequences: fields written as MAP, COUNTER, or ATTACHMENT become invisible unless declared, and the SDK 5.1.0 planner does not use secondary indexes → [Strict Mode](#strict-mode)
- [ ] Different type declarations (or none) for the same field in different statements → [Keep type declarations consistent](#keep-type-declarations-consistent)
- [ ] Assuming `ALTER SYSTEM` settings persist (strict mode, sync scopes, and TTLs silently revert after a restart), or changing parameters such as `DQL_STRICT_MODE` after sync has started or queries and observers have run → [Applying System Parameters](#applying-system-parameters)
- [ ] Timestamps without a zone designator, such as Dart's local `DateTime.now().toIso8601String()` (date functions return MISSING) → [Timestamps](#timestamps) <!-- lint-ignore -->
- [ ] ISO timestamp strings with different fractional precision in one field that is sorted or compared, for example `.123456Z` and `.123Z`, which Dart's `toIso8601String()` produces even on one device (string order no longer matches time order; use one fixed-precision helper) → [Timestamps](#timestamps), [Date and Time](#date-and-time)
- [ ] `IS NOT NULL` used to test that a field exists (it is also true for a missing field; use `IS NOT MISSING`) → [MISSING and NULL](#missing-and-null) <!-- lint-ignore -->
- [ ] Documents that can grow toward the 5 MiB hard limit (writes fail) → [Document Size Limits](#document-size-limits)
- [ ] Throwing inside the authentication expiration handler, including rethrowing `response.exception` → [Authentication](#authentication)
- [ ] The development provider or development token in a production build → [Authentication in Production](#authentication-in-production)
- [ ] `DittoConfigConnectSmallPeersOnly()` without a `privateKey` outside development and tests (peers are not authenticated; documented as unencrypted) → [Small-Peers-Only Deployments](#small-peers-only-deployments)
- [ ] Shared keys, tokens, or API keys hardcoded in the app → [Small-Peers-Only Deployments](#small-peers-only-deployments)
- [ ] Secrets, tokens, or personal data in peer metadata or in the `identityServiceMetadata` returned by the authentication webhook (shared with every peer in the mesh) → [Presence](#presence), [Identity metadata is visible to the mesh](#identity-metadata-is-visible-to-the-mesh)
- [ ] Revocation checking (`PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED`) disabled in production → [Certificate Revocation (SDK 5.1+)](#certificate-revocation-sdk-51)
- [ ] DQL built with string interpolation or concatenation → [Always pass values as parameters](#always-pass-values-as-parameters)
- [ ] Unquoted keys in inline DQL object literals (rejected in `INSERT`, silently `{}` in `SELECT`) → [Quote every key in inline object literals](#quote-every-key-in-inline-object-literals)
- [ ] A `JOIN` whose inner collection has no index (or `_id` lookup) for the join key (the query fails) → [Index requirement](#index-requirement)
- [ ] `ditto.store.execute` inside a transaction callback (throws in Flutter, can deadlock on other platforms), or a read-write transaction nested inside another (deadlock) → [Transaction Rules](#transaction-rules)
- [ ] A second `Ditto.open()` on a persistence directory that is already open (in Flutter, may never complete) → [One instance per persistence directory](#one-instance-per-persistence-directory)
- [ ] `ditto.close()` when the app moves to the background (`AppLifecycleState.paused`) (every later call on that instance throws `DittoClosedException`) → [Starting and Stopping Sync](#starting-and-stopping-sync)
- [ ] A `TransportConfig()` built from scratch and assigned (every transport, including peer-to-peer, is disabled; use `updateTransportConfig()`) → [Transport Configuration](#transport-configuration)
- [ ] A hub that more than six devices connect to over TCP without raising `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` before `ditto.sync.start()` (the extra devices get no data and no error) → [Transport Configuration](#transport-configuration)
- [ ] Reading `queryArguments` or `queryArgumentsJsonString` from elements of `ditto.sync.subscriptions` for subscriptions registered without arguments (can terminate the app in 5.1.0) → [Sync stop, close, and inspection](#sync-stop-close-and-inspection)
- [ ] Access control that relies on mutable fields, `syncGroup`, sync scopes, or client-side checks → [Permissions](#permissions), [Sync Scopes](#sync-scopes)

### High (sync cost, memory, performance)

- [ ] Subscriptions or observers that are never cancelled, or are registered in `build()` → [Subscription Lifecycle](#subscription-lifecycle), [Observer lifecycle and cleanup](#observer-lifecycle-and-cleanup)
- [ ] Flutter observers registered with `onChange` while the `changes` stream is never listened to, or `registerObserverV2` observers whose `changes` stream is not listened to right after registration (memory grows with every update in 5.1.0) → [Store Observers in Flutter](#store-observers-in-flutter)
- [ ] Unfiltered subscriptions on large collections on every device → [Scope subscriptions to what the device needs](#scope-subscriptions-to-what-the-device-needs)
- [ ] Re-registering subscriptions when the user changes a filter, search term, or sort order, or changing subscriptions more often than about every 15 minutes → [Filter locally instead of re-registering](#filter-locally-instead-of-re-registering), [Subscription Lifecycle](#subscription-lifecycle)
- [ ] Projections, aggregates, `DISTINCT`, `GROUP BY`, `JOIN`, or `USE IDS` in subscriptions (rejected), or disabling `DQL_RESTRICT_SUBSCRIPTIONS` to use `LIMIT` and `ORDER BY` (stateful subscriptions; `LIMIT` bounds only the initial download) → [Subscription Rules](#subscription-rules)
- [ ] Subscription filters on mutable fields (`status`, `assignee`), or relay devices with narrower subscriptions than the devices behind them → [Multi-hop relay](#multi-hop-relay)
- [ ] Soft-deleted documents dropped from the subscription before every device has received the flag, or evicted while the subscription still matches them → [Soft delete, subscriptions, and cleanup](#soft-delete-subscriptions-and-cleanup)
- [ ] Evicting documents that an active subscription still matches (they sync straight back) → [EVICT](#evict)
- [ ] Evicting more than about once per day → [Eviction frequency](#eviction-frequency)
- [ ] A Small Peer tombstone TTL (`TOMBSTONE_TTL_HOURS`) above the Ditto Server tombstone TTL → [Tombstone TTL and reaping](#tombstone-ttl-and-reaping)
- [ ] Binary data or base64 files in document fields instead of attachments → [Attachments](#attachments)
- [ ] Fetching every attachment as soon as its document syncs → [Fetching Attachments](#fetching-attachments)
- [ ] `ON ID CONFLICT DO UPDATE` for periodic re-upserts of unchanged data, or `UPDATE` statements that write values already stored → [ON ID CONFLICT](#on-id-conflict)
- [ ] Long transactions, or network calls, dialogs, and timers inside a transaction → [Transaction Rules](#transaction-rules), [Concurrency and Duration](#concurrency-and-duration)
- [ ] Closing Ditto in Flutter without awaiting pending queries and transactions → [Resource Cleanup and Shutdown](#resource-cleanup-and-shutdown)
- [ ] Missing indexes on the filter and sort fields of hot queries → [Index Usage Rules](#index-usage-rules)
- [ ] `USE INDEX ''` on a large inner collection to silence the JOIN index error (every outer row scans the whole inner collection) → [Performance tips](#performance-tips)
- [ ] Functions applied to indexed fields in `WHERE` (for example `lower(name) = :name`), or `OR` branches without indexes → [Index Usage Rules](#index-usage-rules)
- [ ] Storing `QueryResult` or `QueryResultItem` objects in state or caches → [Materialize values, then let the result go](#materialize-values-then-let-the-result-go)
- [ ] Slow or asynchronous work inside a `registerObserver` listener → [Keep observer callbacks fast](#keep-observer-callbacks-fast)
- [ ] Writes to the observed collection from inside its own observer without a guard (each write triggers the observer again) → [Keep observer callbacks fast](#keep-observer-callbacks-fast)
- [ ] One observer of a whole collection that rebuilds the entire screen → [Partial UI Updates](#partial-ui-updates)
- [ ] Observers on `system:data_sync_info` in many widgets, or long-lived observers on `system:system_info` (it fires every 500 ms, even when nothing changed) → [Monitoring Sync Status](#monitoring-sync-status), [System Virtual Collections](#system-virtual-collections)
- [ ] Waiting on the `commitID` of a statement that changed nothing (`mutatedDocumentIDs()` is empty; confirmation takes up to about 30 s), or `sync_session_status` used as a live connection indicator (it lags about 73 s) → [Monitoring Sync Status](#monitoring-sync-status)
- [ ] `LogLevel.verbose` in production → [Log levels](#log-levels)

### Medium (maintainability)

- [ ] No `ORDER BY` in observer queries whose order matters → [Stable ordering](#stable-ordering)
- [ ] Stored derived values (totals, counts) that can diverge after merges → [Do not store derived values that can diverge](#do-not-store-derived-values-that-can-diverge)
- [ ] UI state, progress flags, or device-local paths in synced documents → [Exclude transient and unnecessary fields](#exclude-transient-and-unnecessary-fields)
- [ ] A collection named `collection` or other DQL keywords as bare identifiers → [Reserved words](#reserved-words)
- [ ] Projection aliases in `GROUP BY` or `HAVING` → [GROUP BY and HAVING](#group-by-and-having)
- [ ] `type(x) = 'number'` (never matches) → [Type Checking](#type-checking)
- [ ] Swapped arguments to `date_add` and other date functions (MISSING, no error) → [Date and Time](#date-and-time)
- [ ] Own timestamp fields used to decide which concurrent write wins → [Clock drift](#clock-drift)
- [ ] Field type changes, renames, or removals without a versioning pattern → [Schema Evolution](#schema-evolution)
- [ ] `CREATE INDEX` on demand before a query, or `ADVISE AND PROVISION` in production code → [Creating Indexes](#creating-indexes), [ADVISE (SDK 5.1+)](#advise-sdk-51)
- [ ] Transactions without a `hint` → [Transaction Rules](#transaction-rules)
- [ ] `await ditto.sync.start()` (a compile error in Dart; `start()` and `stop()` return `void`) → [Starting and Stopping Sync](#starting-and-stopping-sync) <!-- lint-ignore -->
- [ ] No tests for the app's DQL statements, soft-delete filters, and observer cleanup → [Testing Strategies](#testing-strategies)

---

## Quick Reference

A condensed summary of the main recommendations. Follow the links for the reasoning and complete examples.

### DO

**Setup and lifecycle** ([SDK Setup and Lifecycle](#sdk-setup-and-lifecycle))
- ✅ Open one `Ditto` instance per persistence directory and share it.
- ✅ For Ditto Server connections, set the expiration handler before `ditto.sync.start()`; check `response.exception` and never throw in the handler.
- ✅ Apply `ALTER SYSTEM` settings after every `Ditto.open()`, before `ditto.sync.start()` and before queries or observers run.
- ✅ Configure `DittoLogger` after `await Ditto.init()` and before `Ditto.open()`.
- ✅ Cancel observers and subscriptions, stop fetchers, and await pending work before `await ditto.close()`.

**Data modeling** ([Data Modeling](#data-modeling))
- ✅ Update fields, not whole documents; use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` for upserts.
- ✅ Use maps keyed by ID for items that several devices edit; use `COUNTER` for concurrent tallies, and recalibrate with `RESTART WITH` only while every device that changes the counter is in sync.
- ✅ Use UUIDs (or composite IDs with a UUID) for `_id`; put permission scopes in `_id`.
- ✅ Keep documents well below 256 KiB; store binary data as attachments.
- ✅ Store timestamps as UTC ISO-8601 strings with `Z` produced by one fixed-precision helper, or as epoch milliseconds.
- ✅ Keep the default `DQL_STRICT_MODE = false` unless you have a specific reason.

**Queries** ([DQL Fundamentals](#dql-fundamentals))
- ✅ Pass every value as a parameter (`:name`); use `IN :values` for membership.
- ✅ Filter optional flags with `coalesce(flag, false) = false`; test whether a field is absent with `IS MISSING` (present: `IS NOT MISSING`).
- ✅ Project only the fields you need, and add `ORDER BY` (with a tie-breaker) to observer queries.
- ✅ Create indexes at startup with `CREATE INDEX IF NOT EXISTS`; check plans with `EXPLAIN` and `ADVISE` (SDK 5.1+).

**Sync and observers** ([Sync and Subscriptions](#sync-and-subscriptions), [Observing Changes](#observing-changes))
- ✅ Scope subscriptions by stable partition keys (tenant, store, user), keep them stable and owned by an app- or feature-level service, and filter UI views locally instead of re-registering.
- ✅ Use `SELECT * FROM <collection> [WHERE ...]` for subscriptions; subscribe to every collection a JOIN reads. Bound what syncs with `WHERE`, not `LIMIT`.
- ✅ On a TCP hub with more than six clients, raise `MESH_CHOOSER_MAX_WLAN_CONNECTIONS` before `ditto.sync.start()`.
- ✅ In Flutter, register observers without `onChange`, consume `changes`, and cancel both in `dispose()`.

**Writes, deletion, and storage** ([Transactions](#transactions), [Deletion and Storage Management](#deletion-and-storage-management))
- ✅ Keep transactions short, use only `tx.execute`, and give them a `hint`.
- ✅ Track a `commitID` for upload progress only when `mutatedDocumentIDs()` is not empty; use presence for live connection status.
- ✅ Prefer soft delete for shared records, keep soft-deleted documents in the subscription until every device has the flag, and target deletions with `WHERE _id IN :ids`.
- ✅ Cancel or narrow subscriptions before `EVICT`, and evict at most about once per day.

**Security** ([Security](#security))
- ✅ Use a webhook authentication provider in production, and a provisioned `privateKey` in small-peers-only deployments.
- ✅ Validate input, and encrypt sensitive fields at the application level.

### Common Code Shapes

**Startup sequence** (condensed; the full version in [Complete app startup](#complete-app-startup) also closes the instance when a step after `Ditto.open()` fails):

```dart
import 'package:flutter/foundation.dart';

Future<Ditto> startDitto(List<SyncSubscription> subscriptions) async {
  await Ditto.init();
  DittoLogger.minimumLogLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug;

  final ditto = await Ditto.open(
    const DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
    ),
  );

  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    try {
      final response = await ditto.auth.login(
        token: await fetchAuthToken(),
        provider: 'YOUR_PROVIDER_NAME',
      );
      if (response.exception != null) showError(response.exception!);
    } catch (error) {
      showError(error); // never rethrow here
    }
  });

  // Not persisted: apply on every open, before sync starts.
  await ditto.store.execute('ALTER SYSTEM SET DQL_SLOW_REQUEST_WARN_SECONDS = 30');
  if (!kIsWeb) {
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)',
    );
  }

  subscriptions.add(ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': 'store-1'},
  ));
  ditto.sync.start(); // void: do not await
  return ditto;
}
```

**Subscription** ([Subscription Lifecycle](#subscription-lifecycle)):

```dart
/// Owns the subscriptions for the store the user works in.
class OrderSync {
  OrderSync(this._ditto);

  final Ditto _ditto;
  SyncSubscription? _orders;
  String? _storeId;

  void enterStore(String storeId) {
    if (storeId == _storeId) return; // Already subscribed; do not re-register.
    _orders?.cancel();
    _storeId = storeId;
    _orders = _ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
  }

  /// On logout or when the user leaves the store.
  void leaveStore() {
    _orders?.cancel();
    _orders = null;
    _storeId = null;
  }
}
```

**Observer** ([Store Observers in Flutter](#store-observers-in-flutter)):

```dart
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
  arguments: {'status': 'open'},
);
final changes = observer.changes.listen((result) {
  final orders = result.items.map((item) => item.value).toList();
  debugPrint('open orders: ${orders.length}');
});
// In dispose() (synchronous; do not await there):
changes.cancel();
observer.cancel();
```

**Transaction** ([Using store.transaction](#using-storetransaction)):

```dart
await ditto.store.transaction(hint: 'closeOrder', (tx) async {
  await tx.execute(
    'UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'id': 'order-1', 'status': 'closed'},
  );
  await tx.execute(
    'INSERT INTO invoices DOCUMENTS (:invoice)',
    arguments: {
      'invoice': {'_id': 'invoice-1', 'orderId': 'order-1'},
    },
  );
});
```

**Attachment** ([Creating and Inserting Attachments](#creating-and-inserting-attachments), [Fetching Attachments](#fetching-attachments)):

```dart
final attachment = await ditto.store.newAttachment(
  '/path/to/photo.jpg',
  AttachmentMetadata({'name': 'photo.jpg', 'mimeType': 'image/jpeg'}),
);
await ditto.store.execute(
  'INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:photo)',
  arguments: {
    'photo': {'_id': 'photo-1', 'image': attachment},
  },
);

// Later, when the image is shown: fetch the blob from the token.
final result = await ditto.store.execute(
  'SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE _id = :id',
  arguments: {'id': 'photo-1'},
);
final token = result.items.first.value['image'] as Map<String, dynamic>;
final fetcher = ditto.store.fetchAttachment(token, (event) async {
  if (event is AttachmentFetchEventCompleted) {
    final bytes = await event.attachment.data;
    debugPrint('fetched ${bytes.length} bytes');
  }
});
// If the screen closes before the fetch completes:
fetcher.stop();
```

**Upsert with DO UPDATE_LOCAL_DIFF** ([INSERT and Conflict Handling](#insert-and-conflict-handling)):

```dart
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'product': {'_id': 'p1', 'name': 'Pen', 'priceCents': 250},
  },
);
```

**COUNTER update** ([Counters](#counters)):

```dart
await ditto.store.execute(
  'UPDATE COLLECTION products (viewCount COUNTER) '
  'APPLY viewCount INCREMENT BY 1 WHERE _id = :id',
  arguments: {'id': 'p1'},
);
```

**Soft delete and its filter** ([Soft Delete](#soft-delete)):

```dart
await ditto.store.execute(
  'UPDATE orders SET isDeleted = true, deletedAt = :now WHERE _id = :id',
  arguments: {
    'id': 'order-1',
    'now': utcTimestamp(), // fixed-precision helper (see Timestamps)
  },
);
final active = await ditto.store.execute(
  'SELECT * FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY createdAt DESC',
);
```

**Index creation** ([Creating Indexes](#creating-indexes)):

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)
```

**Logging** ([Logging](#logging)):

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

---

## Glossary

Definitions as used in this guide. For the complete list of Ditto terms, see the [Ditto glossary](https://docs.ditto.live/home/glossary).

| Term | Definition |
|---|---|
| **ADVISE** (SDK 5.1+) | A DQL prefix that returns index recommendations for a statement without executing it. `ADVISE AND PROVISION` also creates the suggested indexes. See [ADVISE (SDK 5.1+)](#advise-sdk-51). |
| **Attachment** | Binary data (photos, PDFs, audio) referenced from a document field of type `ATTACHMENT` by a token. The token syncs with the document; the bytes (blob) are transferred only when a device fetches them. See [Attachments](#attachments). |
| **AttachmentFetcher** | The object returned by `ditto.store.fetchAttachment()`. It reports progress through events; `stop()` cancels a fetch in progress. See [Fetching Attachments](#fetching-attachments). |
| **Authentication webhook** | An HTTP service you operate that validates a user's token for Ditto Server and returns the user ID, session lifetime, and permissions. See [Authentication in Production](#authentication-in-production). |
| **Backpressure** | Control over when the next observer result is delivered. In Flutter, provided by `registerObserverV2` and `registerObserverWithSignalNext`, both (Experimental) (SDK 5.1+). See [Backpressure (SDK 5.1+)](#backpressure-sdk-51). |
| **Big Peer** | The former name of Ditto Server. |
| **Collection** | A named group of documents, similar to a table. A collection exists as soon as a document is written to it. |
| **Commit ID** | A device-specific, increasing number returned in `QueryResult.commitID` for local writes. Comparing it with a peer's `synced_up_to_local_commit_id` tells you whether that peer has the write. See [Monitoring Sync Status](#monitoring-sync-status). |
| **Composite index** (SDK 5.1+) | An index over several fields in order, for example `(status, createdAt DESC)`. See [Creating Indexes](#creating-indexes). |
| **COUNTER** | A CRDT type for integers that combines increments and decrements from all devices. Changed with `APPLY ... INCREMENT BY` or `RESTART`. See [Counters](#counters). |
| **CRDT** | Conflict-free replicated data type: a data structure whose concurrent changes on different devices merge deterministically without a coordinator. Every field in a Ditto document is stored as a CRDT. See [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior). |
| **Database ID** | The UUID that identifies a Ditto database. All peers that sync together use the same Database ID. |
| **Differ** | A Flutter class that compares successive observer results by `_id` and reports insertions, deletions, updates, and moves. See [Diffing Results](#diffing-results). |
| **Ditto Server** | The optional server-side cluster, hosted by Ditto or run by you, that Small Peers reach over WebSocket. It connects separate meshes, handles authentication, and integrates with backend systems. Formerly called Big Peer. |
| **Document** | A JSON-like object in a collection, identified by its immutable `_id`. |
| **DQL** | Ditto Query Language, the SQL-like language for reading, writing, and observing documents. See [DQL Fundamentals](#dql-fundamentals). |
| **Edge device** | A device at the edge of the network, such as a phone, tablet, or kiosk, that runs a Small Peer. |
| **EVICT** | A DQL statement that removes documents from the local store only. The removal is not propagated to other peers, and no tombstone is created. See [EVICT](#evict). |
| **Expiration handler** | The callback registered with `ditto.auth.setExpirationHandler()` that logs the device in to Ditto Server when it needs to authenticate and when credentials are about to expire. See [Authentication](#authentication). |
| **EXPLAIN / PROFILE** | DQL prefixes that show a statement's query plan without running it (`EXPLAIN`) or run it and report timings per step (`PROFILE`). See [EXPLAIN and PROFILE](#explain-and-profile). |
| **Husk document** | The result of a deletion on one device merging with a concurrent update on another: the document is not deleted; the updated fields keep their values (or become `null` if the deletion was later), all other fields are missing. See [Husk documents](#husk-documents). |
| **Hybrid Logical Clock (HLC)** | The clock Ditto uses to decide which of two concurrent register writes is the latest. |
| **Index** | A per-device data structure that lets queries find documents without scanning the whole collection. Indexes persist, but are not synced. See [Indexing and Query Performance](#indexing-and-query-performance). |
| **INITIAL DOCUMENTS** | An `INSERT` form for default data that every peer may create independently; existing documents are never overwritten. See [Default Data with INITIAL Documents](#default-data-with-initial-documents). |
| **JOIN** (SDK 5.1+) | Combining documents from several collections in one local `SELECT`. Not allowed in subscriptions; the inner collection needs an index or an `_id` join. See [Joining Collections (SDK 5.1+)](#joining-collections-sdk-51). |
| **MAP** | A CRDT type for objects whose keys merge independently (add-wins). Objects are stored as maps by default. See [Arrays and Maps](#arrays-and-maps). |
| **Mesh** | The network of peers connected to each other over peer-to-peer transports, optionally bridged to Ditto Server. |
| **MISSING** | The state of a field that is absent from a document, distinct from a field whose value is `null`. Test it with `IS MISSING`. See [MISSING and NULL](#missing-and-null). |
| **Multi-hop sync** | Relaying documents through intermediate peers that are not directly connected to each other. A peer can relay only documents it stores itself. See [Multi-hop relay](#multi-hop-relay). |
| **Observer** (store observer) | A live local query registered with `ditto.store.registerObserver()` that delivers a new result whenever matching local data changes. Observers never cause data to sync. See [Observing Changes](#observing-changes). |
| **Offline license token** | A token issued by Ditto that activates an instance in small-peers-only mode. `ditto.sync.start()` throws until it is set; the local store works without it. See [Initializing Ditto](#initializing-ditto). |
| **Peer** | An instance of the Ditto SDK, or Ditto Server, that participates in sync. |
| **REGISTER** | A CRDT type that holds a single value (a scalar, an array, or an object declared as `REGISTER`); concurrent writes resolve by last-writer-wins. See [CRDT Types and Merge Behavior](#crdt-types-and-merge-behavior). |
| **RETURNING** (SDK 5.1+) | A clause that returns the affected documents from `INSERT`, `UPDATE`, `DELETE`, or `EVICT`. See [RETURNING (SDK 5.1+)](#returning-sdk-51). |
| **Shared key** | The `privateKey` that all peers of a small-peers-only deployment use to authenticate each other and encrypt traffic. See [Small-Peers-Only Deployments](#small-peers-only-deployments). |
| **Small Peer** | An instance of the Ditto SDK embedded in an application. |
| **Soft delete** | Marking a document as deleted with an ordinary `UPDATE` of a flag such as `isDeleted`, instead of `DELETE`. See [Soft Delete](#soft-delete). |
| **Strict mode** | The `DQL_STRICT_MODE` system parameter (default `false`). When `true`, undeclared objects are stored as registers and MAP, COUNTER, and ATTACHMENT fields must be declared in every statement. See [Strict Mode](#strict-mode). |
| **Subscription** | A `SELECT * FROM <collection> [WHERE ...]` query registered with `ditto.sync.registerSubscription()` that tells connected peers which documents to send to this device. See [Sync and Subscriptions](#sync-and-subscriptions). |
| **Sync scope** | A per-collection setting (`USER_COLLECTION_SYNC_SCOPES`) that limits where a device sends its documents. See [Sync Scopes](#sync-scopes). |
| **System parameter** | A runtime setting read with `SHOW` and changed with `ALTER SYSTEM`. Settings are not persisted. See [System Parameters Reference](#system-parameters-reference). |
| **Tombstone** | The marker that `DELETE` leaves behind so that the deletion syncs to other peers. Tombstones expire after a TTL (7 days by default on Small Peers) and are then removed by reaping. See [DELETE and Tombstones](#delete-and-tombstones). |
| **Transaction** | A group of DQL statements executed atomically against the local store with `ditto.store.transaction()`. See [Transactions](#transactions). |
| **Transport** | A connection technology used for sync: Bluetooth LE, peer-to-peer Wi-Fi (AWDL, Wi-Fi Aware), LAN, and WebSocket. See [Transport Configuration](#transport-configuration). |
| **Virtual collection** | A local-only collection in the `system:` namespace that describes the device and its query engine, such as `system:system_info` or `system:indexes`. Read-only, except that `DELETE FROM system:request_history` clears the request history. See [System Virtual Collections](#system-virtual-collections). |
| **Zombie data** | Deleted data that reappears when a device that missed the deletion reconnects after the tombstones have expired. See [Tombstone TTL and reaping](#tombstone-ttl-and-reaping). |

---

## References

Ditto documentation and resources, grouped by topic.

**General**
- [Ditto documentation](https://docs.ditto.live)
- [What's new in Ditto SDK v5](https://docs.ditto.live/sdk/latest/v5-whats-new)
- [Glossary](https://docs.ditto.live/home/glossary)
- [FAQ](https://docs.ditto.live/home/faq)
- [Ditto SDK 5.1 announcement (blog)](https://www.ditto.com/blog/ditto-sdk-v5-1)

**Flutter SDK**
- [Flutter install guide](https://docs.ditto.live/sdk/latest/install-guides/flutter)
- [Flutter quickstart](https://docs.ditto.live/sdk/latest/quickstarts/flutter)
- [Flutter release notes](https://docs.ditto.live/sdk/latest/release-notes/flutter)
- [`ditto_live` on pub.dev](https://pub.dev/packages/ditto_live)
- [`ditto_live` API reference](https://pub.dev/documentation/ditto_live/latest/)

**DQL**
- [DQL overview](https://docs.ditto.live/dql/dql)
- [SELECT](https://docs.ditto.live/dql/select)
- [INSERT](https://docs.ditto.live/dql/insert)
- [UPDATE](https://docs.ditto.live/dql/update)
- [DELETE](https://docs.ditto.live/dql/delete)
- [EVICT](https://docs.ditto.live/dql/evict)
- [RETURNING](https://docs.ditto.live/dql/returning)
- [Types and definitions](https://docs.ditto.live/dql/types-and-definitions)
- [Strict mode](https://docs.ditto.live/dql/strict-mode)
- [Operators and expressions](https://docs.ditto.live/dql/operator-expressions)
- [Identifiers, paths, strings, and keywords](https://docs.ditto.live/dql/ids-paths-strings-keywords)
- [Virtual collections](https://docs.ditto.live/dql/virtual-collections)
- [ALTER SYSTEM](https://docs.ditto.live/dql/alter-system)
- [SHOW](https://docs.ditto.live/dql/show)

**Indexing and query performance**
- [Indexing](https://docs.ditto.live/dql/indexing)
- [ADVISE](https://docs.ditto.live/dql/advise)
- [EXPLAIN](https://docs.ditto.live/dql/explain)
- [PROFILE](https://docs.ditto.live/dql/profile)
- [Directives](https://docs.ditto.live/dql/directives)

**Reading, writing, and observing data**
- [Observing data changes](https://docs.ditto.live/sdk/latest/crud/observing-data-changes)
- [Transactions](https://docs.ditto.live/sdk/latest/crud/transactions)
- [Working with attachments](https://docs.ditto.live/sdk/latest/crud/working-with-attachments)
- [Delete](https://docs.ditto.live/sdk/latest/crud/delete)

**Sync and storage**
- [Syncing data (subscriptions)](https://docs.ditto.live/sdk/latest/sync/syncing-data)
- [Sync handling best practices](https://docs.ditto.live/best-practices/sync-handling)
- [Sync scopes](https://docs.ditto.live/sdk/latest/sync/sync-scopes)
- [Monitoring sync status](https://docs.ditto.live/sdk/latest/sync/monitoring-sync-status)
- [Customizing transport configurations](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations)
- [Device storage management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)

**Data modeling**
- [Data modeling best practices](https://docs.ditto.live/best-practices/data-modeling)
- [Syncing data and CRDTs](https://docs.ditto.live/key-concepts/syncing-data)
- [Conflict resolution patterns](https://docs.ditto.live/best-practices/conflict-resolution-patterns)
- [Document size limits](https://docs.ditto.live/best-practices/document-size-limits)
- [Timestamps](https://docs.ditto.live/best-practices/timestamps)
- [Schema versioning](https://docs.ditto.live/best-practices/schema-versioning)

**Authentication and security**
- [Authentication and authorization](https://docs.ditto.live/key-concepts/authentication-and-authorization)
- [Cloud authentication (webhook providers)](https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication)
- [Data authorization (permissions)](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization)
- [Certificate revocations](https://docs.ditto.live/cloud/revocations)
- [Webhook security](https://docs.ditto.live/cloud/webhook-security)

**Testing, logging, and troubleshooting**
- [Testing](https://docs.ditto.live/sdk/latest/deployment/testing)
- [Logging](https://docs.ditto.live/sdk/latest/deployment/logging)
- [Troubleshooting](https://docs.ditto.live/sdk/latest/deployment/troubleshooting)
- [Ditto Portal troubleshooting](https://docs.ditto.live/cloud/portal/troubleshooting)
- [Device dashboard](https://docs.ditto.live/cloud/portal/capturing-small-peer-info)
- [Remote observability](https://docs.ditto.live/sdk/latest/deployment/device-observability-and-ditto-logs)
- [Getting system information](https://docs.ditto.live/sdk/latest/deployment/getting-system-information)

---

## Disclaimer

This guide provides best practices and recommendations for the Ditto SDK. It reflects Ditto SDK 5.1.0 as of the Last Updated date at the top of this document. While we strive to keep this information accurate and up to date, the SDK evolves, and your specific use case may differ.

We encourage you to:
- Refer to the [Ditto documentation](https://docs.ditto.live) and the release notes for your SDK version for the most current information.
- Test thoroughly in your own environment before deploying to production.
- Adapt these patterns to fit your specific requirements.

This guide is provided "as is" for educational and reference purposes. We are not responsible for any issues that may arise from implementing these patterns in your projects. Your use of this information is at your own discretion and risk.
