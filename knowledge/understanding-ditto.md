# Understanding Ditto

## What Is Ditto?

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

The [Glossary](glossary.md) defines these and the other terms that the guide uses, such as Database ID, collection, subscription, store observer, tombstone, and eviction.

## Key Characteristics

**Offline-first operation**
- The local database is always readable and writable, with or without connectivity.
- Writes are committed locally first and synced when a connection to another peer or to Ditto Server becomes available.
- Sync is incremental: each connection carries only the changes that the other side is not known to have. In a mesh, a device can still receive the same change from several neighbors (see [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay)).

**Distributed synchronization**
- No server is required for peers to sync with each other. Ditto Server is optional.
- Each device decides what it wants to receive by registering **subscriptions**. Devices in the same mesh can relay data to each other, but a device only stores and forwards the documents that match its own subscriptions, so give devices that relay data subscriptions that cover what the devices behind them need (see [Multi-hop relay](../best-practices/sync-and-subscriptions.md#multi-hop-relay)).
- Multiple transports are used at the same time, and the SDK chooses connections automatically. Each device sends its changes over one of the connections to a peer, though. When that connection closes, sync moves to another one at once, but when it stalls without closing (for example, a Wi-Fi link that fades), sync in both directions waits until the stalled connection is dropped, even if another transport still works: in our testing with SDK 5.0.3, 5.1.0, and 5.2.0, about 7 seconds for TCP and about 15 seconds for WebSocket, and no changes were lost (see [Each device sends over one of two connections and waits when it stalls](observations/connections-and-presence.md#each-device-sends-over-one-of-two-connections-and-waits-when-it-stalls)).

**Automatic conflict resolution**
- Concurrent edits are merged at the field level according to each field's CRDT type, not by replacing whole documents.
- The data model you choose (maps, registers, counters, separate documents) determines how concurrent edits combine. See [CRDT Types and Merge Behavior](crdt-types.md).

**Capacity**
- A device running the SDK, such as a mobile device, is designed to handle up to about 2 GB of key-value data and tens of thousands of documents in a collection. Actual limits depend on data shape, query complexity, and performance requirements.

## Core Principles

### 1. Queries read the local store only

`ditto.store.execute()` and store observers never contact other peers. They return whatever is in the local store at that moment, so they work offline and return quickly, but they only see data that has already synced to the device.

### 2. Subscriptions decide what data syncs to a device

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

See [Sync and Subscriptions](../best-practices/sync-and-subscriptions.md) for subscription design.

### 3. Design for offline-first

Assume that any device can be disconnected for a long time and keep working. Write locally, show local data immediately, and let sync catch up. Do not block the UI waiting for a server response, and do not assume that a write has reached other devices just because it succeeded locally.

### 4. Conflicts are resolved automatically by the data model you choose

Multiple devices will modify the same documents while disconnected. Ditto always merges the changes without errors, but whether the result is what your users expect depends on your data model:

**✅ DO:**
- Update individual fields instead of rewriting whole documents.
- Use maps keyed by ID (not arrays) for collections of sub-items that several devices edit.
- Use counters for values that several devices increment.
- Think through what should happen when two devices edit the same field at the same time.

**❌ DON'T:**
- Assume a single writer for shared data.
- Replace entire documents or arrays when only one part changed.

**Why:** Each field type has defined merge semantics (for example, with the default `DQL_STRICT_MODE = false`, objects merge per field, while scalars and arrays use last-writer-wins). Choosing the right type for each field is what prevents lost updates. See [CRDT Types and Merge Behavior](crdt-types.md) and [Data Modeling](../best-practices/data-modeling.md).
