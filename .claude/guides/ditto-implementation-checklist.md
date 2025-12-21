# Ditto SDK Implementation Checklist

> **Version**: 1.0
> **Last Updated**: 2025-12-21
>
> **Official Documentation**: [https://docs.ditto.live](https://docs.ditto.live)

## Section 1: Initialization & API Basics

### ☐ Initialize Ditto with appropriate authentication mode

**What this means:** Choose the correct identity mode:
- **Development**: `OnlinePlaygroundIdentity` (for testing only, no access controls)
- **Production**: `OnlineWithAuthenticationIdentity` with authentication delegate
- **Air-gapped/Offline**: `SharedKeyIdentity` (no cloud sync)

**Why this matters:** Authentication mode determines security model and sync capabilities. OnlinePlayground is insecure for production. OnlineWithAuthentication provides proper access controls. SharedKey is for fully offline deployments.

### ☐ Handle Ditto initialization errors gracefully

**What this means:** Wrap `Ditto.open()`, `startSync()`, and `execute()` in try-catch blocks. Handle cases like invalid license, network unavailability, permission issues, or query errors.

**Why this matters:** Ditto initialization and operations can fail due to licensing, network, platform issues, or invalid queries. Graceful error handling prevents app crashes and provides user feedback.

### ☐ Use DQL API (current), not legacy builder API

**What this means:** Use `ditto.store.execute('SELECT * FROM collection ...')` and related DQL methods. Avoid deprecated builder APIs like `ditto.store.collection('name').find()`.

**Why this matters:** Builder API is deprecated and lacks features like transactions, optimizations, and v5 forward compatibility. DQL API is the current standard (SDK 4.12+) and will be maintained going forward.

### ☐ Always await ALTER SYSTEM SET before startSync()

**What this means:** When configuring system settings like `DQL_STRICT_MODE`, always use `await` before calling `startSync()` or other operations.

**Why this matters:** `store.execute()` is async. Proceeding without awaiting can cause settings to not be applied before sync starts, leading to inconsistent behavior across peers.

**Code Example**:

```dart
// ❌ BAD: Missing await (settings might not apply before sync)
ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false'); // No await!
await ditto.startSync(); // May start with wrong settings

// ✅ GOOD: Always await ALTER SYSTEM SET
await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
await ditto.startSync(); // Settings guaranteed to be applied
```

---

## Section 2: Data Modeling Fundamentals

### ☐ Use UUID v4 or auto-generated IDs, not sequential IDs

**What this means:** Generate globally unique IDs using UUID v4, ULID, or omit `_id` to let Ditto auto-generate (recommended). Never use sequential numbers, timestamps, or device-based counters.

**Why this matters:** Sequential ID generation causes collisions when multiple offline devices create documents with the same ID pattern (e.g., "order_001"). Collisions trigger conflict resolution, potentially causing data loss or unexpected behavior. Ditto's auto-generated IDs are globally unique and collision-free.

**Note**: `package:uuid/uuid.dart` is Flutter/Dart specific. Equivalent UUID libraries are available for all platforms.

### ☐ Use MAP instead of arrays for mutable data

**What this means:** Arrays use Last-Write-Wins (REGISTER CRDT), causing merge conflicts when multiple peers update concurrently. Use MAP (object) structures with unique keys for data that can be modified by multiple devices.

**Why this matters:** Concurrent array updates from offline peers result in lost data, duplicates, or inconsistent state after sync. MAP structures use "add-wins" semantics, automatically merging concurrent updates to different keys without conflicts.

**Code Example**:

```dart
// ❌ BAD: Array with concurrent updates (Last-Write-Wins)
{
  "_id": "order_123",
  "items": [{"id": "item1", "qty": 2}]  // Merge conflicts!
}

// ✅ GOOD: MAP structure for concurrent updates
{
  "_id": "order_123",
  "items": {"item1": {"qty": 2, "productId": "p1"}}  // Merge-safe
}
```

### ☐ Use embedded vs foreign-key relationships appropriately

**What this means:** Decide whether to embed related data in a single document or use separate documents with foreign-key references:
- **Embedded**: Single query, data duplication, better for small static data
- **Foreign-key**: Multiple queries, normalized data, better for large or frequently updated data

**Why this matters:** Ditto does not support SQL-style JOINs. Choice affects query complexity, data duplication, and sync efficiency. Embedded data syncs together; foreign-key data syncs independently.

### ☐ Avoid storing large binary data directly in documents

**What this means:** Don't store images, videos, or large files as base64 strings in document fields. Use Ditto attachments instead.

**Why this matters:** Large binary data in documents bloats sync traffic and storage. Attachments are lazy-loaded and fetched on-demand, optimizing bandwidth and storage.

### ☐ Don't store calculated/derived fields in documents

**What this means:** Avoid storing fields that can be calculated from existing data (e.g., `lineTotal = price × quantity`, `subtotal = sum(items)`, `total = subtotal + tax`). Calculate these values in application code when needed.

**Why this matters:** Storing calculated fields wastes bandwidth (syncs unnecessary data), creates risk of stale data (source changes but calculated field doesn't update), and adds synchronization overhead. Calculate on-demand instead.

**Code Example**:

```dart
// ❌ BAD: Storing calculated values (wastes bandwidth, risk of stale data)
{
  "_id": "order_123",
  "items": {
    "item_1": {"price": 12.99, "quantity": 2, "lineTotal": 25.98}  // ❌ Calculated!
  },
  "subtotal": 25.98,  // ❌ Calculated!
  "tax": 2.60,        // ❌ Calculated!
  "total": 28.58      // ❌ Calculated!
}

// ✅ GOOD: Store only source data, calculate in app
{
  "_id": "order_123",
  "items": {
    "item_1": {"price": 12.99, "quantity": 2}  // Source data only
  }
}

// Calculate on-demand in application
double calculateLineTotal(Map<String, dynamic> item) {
  return item['price'] * item['quantity'];
}

double calculateTotal(Map<String, dynamic> items, double taxRate) {
  final subtotal = items.values.fold(0.0,
    (sum, item) => sum + (item['price'] * item['quantity']));
  return subtotal + (subtotal * taxRate);
}
```

---

### ☐ Enable DQL Strict Mode for type safety across peers [SDK 4.11+]

**What this means:** Execute `ALTER SYSTEM SET DQL_STRICT_MODE = true` before `startSync()` to enforce type consistency across all fields. This prevents different devices from writing incompatible types to the same field.

**Why this matters:** Without Strict Mode, Device A can write `{"age": 30}` (number) while Device B writes `{"age": "thirty"}` (string), causing cross-peer data inconsistency and unpredictable query results. Strict Mode enforces type declarations via MAP literals, catching type errors at development time instead of runtime.

---

## Section 3: Write Operations

### ☐ Use ON ID CONFLICT DO NOTHING for idempotent INSERTs

**What this means:** When inserting documents that should only be created once (e.g., initial setup data), use `INSERT ... ON ID CONFLICT DO NOTHING` to silently skip if the document already exists.

**Why this matters:** Prevents errors when re-running initialization code. Ensures idempotency without requiring explicit checks before INSERT.

### ☐ Use field-level UPDATE instead of full document replacement

**What this means:** Update only specific fields using `UPDATE collection SET field = :value WHERE ...` instead of re-inserting entire documents with `INSERT ... ON ID CONFLICT DO UPDATE`.

**Why this matters:** Full document replacement treats all fields as changed, creating unnecessary sync deltas even for unchanged values. Field-level updates minimize sync traffic and reduce conflict potential.

**Code Example**:

```dart
// ❌ BAD: Full document replacement (unnecessary sync traffic)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {'_id': 'o1', 'status': 'done', 'customer': 'c1', 'items': [...]}
  },
);

// ✅ GOOD: Field-level update (only changed field syncs)
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :id',
  arguments: {'id': 'o1', 'status': 'done'},
);
```

### ☐ Avoid updating fields with the same value unnecessarily

**What this means:** Before executing an UPDATE, check if the new value differs from the current value. Skip the UPDATE if values are identical.

**Why this matters:** Updating a field with the same value still creates a sync delta and triggers observers, causing unnecessary network traffic and UI updates. Checking before updating optimizes performance.

### ☐ Use DO UPDATE_LOCAL_DIFF for efficient upserts [SDK 4.12+]

**What this means:** When upserting documents with `ON ID CONFLICT`, use `DO UPDATE_LOCAL_DIFF` instead of `DO UPDATE` to avoid syncing unchanged field values.

**Why this matters:** `DO UPDATE` treats all fields as changed and syncs them as deltas, even if values are identical. `DO UPDATE_LOCAL_DIFF` compares incoming vs existing documents and only syncs fields that actually differ, reducing network traffic.

**Code Example**:

```dart
// ❌ BAD: DO UPDATE syncs ALL fields (even unchanged)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {'_id': 'o1', 'status': 'done', 'customer': 'c1'}
  },
);

// ✅ GOOD: DO UPDATE_LOCAL_DIFF only syncs changed fields (SDK 4.12+)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {'_id': 'o1', 'status': 'done', 'customer': 'c1'}
  },
);
```

### ☐ Use COUNTER type for distributed counters [SDK 4.14.0+]

**What this means:** For counters that may be updated concurrently by multiple peers, use `COUNTER` type with `INCREMENT BY` operation instead of SET operations.

**Why this matters:** SET operations perform read-modify-write, causing lost updates when devices are disconnected. COUNTER operations merge correctly across concurrent updates using commutative CRDT semantics.

**Code Example**:

```dart
// ❌ BAD: SET operation for counters (lost updates)
final product = (await ditto.store.execute(
  'SELECT * FROM products WHERE _id = :id', arguments: {'id': 'p1'}
)).items.first.value;
await ditto.store.execute(
  'UPDATE products SET viewCount = :count WHERE _id = :id',
  arguments: {'count': (product['viewCount'] ?? 0) + 1, 'id': 'p1'},
);

// ✅ GOOD: COUNTER type for distributed counters (SDK 4.14.0+)
await ditto.store.execute(
  'UPDATE products APPLY viewCount COUNTER INCREMENT BY 1.0 WHERE _id = :id',
  arguments: {'id': 'p1'},
);
```

### ☐ Use separate documents for event history, not arrays

**What this means:** For append-only logs (status history, audit trails), INSERT a new document for each event instead of appending to an array field.

**Why this matters:** Arrays are REGISTER CRDTs (Last-Write-Wins). Concurrent appends from offline peers result in lost events after merge. Separate documents allow all events to be preserved independently.

### ☐ Use INITIAL DOCUMENTS for device-local templates

**What this means:** For device-local default data (categories, templates, seed data), use `INSERT INTO collection INITIAL DOCUMENTS (...)` instead of regular `INSERT`.

**Why this matters:** Regular INSERT creates sync deltas that propagate to all peers unnecessarily. `INITIAL DOCUMENTS` treats data as "existing from the beginning of time," preventing sync traffic for device-local templates.

---

## Section 4: Deletion & Storage Lifecycle

### ☐ Understand the difference between Soft-Delete (Logical Deletion) and DELETE queries

**What this means:**
- **Soft-Delete (Logical Deletion)**: Mark documents as deleted using a flag (e.g., `UPDATE collection SET isDeleted = true WHERE _id = :id`). Documents remain in the database and sync across peers.
- **DELETE query**: Permanently remove documents from the database using `DELETE FROM collection WHERE _id = :id`. Deletion propagates to all peers via tombstones.

**Why this matters:** These two approaches have fundamentally different behaviors:
- **Soft-Delete** allows documents to relay through intermediate peers (multi-hop sync works), enables "undo" functionality, preserves audit trails, and prevents husked documents. However, it requires periodic cleanup (EVICT) to free storage.
- **DELETE query** permanently removes data across the mesh, frees storage automatically after tombstone TTL, but breaks multi-hop relay if peers are offline during the TTL window, and can cause husked documents when concurrent with UPDATEs.

**When to use each:**
- Use **Soft-Delete** for user-facing deletions (trash, archive), when multi-hop relay is critical, when you need audit trails, or when "undo" functionality is required.
- Use **DELETE query** only for permanent data removal (GDPR compliance, sensitive data cleanup), internal/system data that doesn't need relay, or when storage constraints are critical.

### ☐ Use logical deletion pattern: subscribe broadly, filter in observers/queries

**What this means:**
- **Subscriptions**: `SELECT * FROM orders` (no `isDeleted` filter)
- **Observers**: `SELECT * FROM orders WHERE isDeleted != true`
- **Queries**: `SELECT * FROM orders WHERE isDeleted != true`

**Why this matters:** Filtering deletion flags in subscriptions breaks multi-hop relay. Intermediate devices won't store deleted documents, preventing deletion notifications from reaching indirectly connected peers. Subscribe broadly for relay, filter locally for display.

**Code Example**:

```dart
// ❌ WRONG: Filtering deletion flags in subscriptions
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted != true',  // Blocks relay!
);

// ✅ CORRECT: Subscribe broadly, filter in observer
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // No filter - allows multi-hop relay
);
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE isDeleted != true',  // Filter here
  onChange: (result, signalNext) {
    updateUI(result.items);
    signalNext();
  },
);
```

### ☐ Understand husked documents and how to prevent them

**What this means:** "Husked documents" occur when one peer DELETEs a document while another peer concurrently UPDATEs it. After merge, the document exists but has only `_id` and the updated field(s), with all other fields set to null.

**Why this matters:** Husked documents can break application logic that assumes required fields always exist. Logical deletion prevents husking by using UPDATE instead of DELETE.

**Code Example**:

```dart
// ❌ PROBLEM: DELETE + concurrent UPDATE = husked document
// Device A:
await ditto.store.execute('DELETE FROM cars WHERE _id = :id', arguments: {'id': 'car1'});
// Device B (offline):
await ditto.store.execute('UPDATE cars SET color = :color WHERE _id = :id', arguments: {'color': 'blue', 'id': 'car1'});
// Result after sync: {_id: "car1", color: "blue", make: null, model: null}

// ✅ SOLUTION: Logical deletion prevents husked documents
await ditto.store.execute(
  'UPDATE cars SET isDeleted = true, deletedAt = :time WHERE _id = :id',
  arguments: {'time': DateTime.now().toIso8601String(), 'id': 'car1'},
);
```

### ☐ Periodically EVICT old logically deleted documents

**What this means:** After marking documents as deleted (e.g., `isDeleted: true, deletedAt: <timestamp>`), periodically run `EVICT FROM collection WHERE isDeleted = true AND deletedAt < :cutoff` to free local storage. Choose an appropriate retention period (e.g., 30-90 days).

**Why this matters:** Logical deletion keeps documents in the database indefinitely, consuming storage. Eviction removes old deleted documents from local storage without affecting peers (EVICT is local-only, not DELETE). This prevents storage bloat while maintaining multi-hop relay during the retention period.

### ☐ Avoid mixing DELETE and UPDATE on the same documents

**What this means:** Don't use DELETE for some scenarios and logical deletion (UPDATE with `isDeleted: true`) for others within the same collection. Choose one deletion strategy and apply it consistently.

**Why this matters:** Mixed strategies create confusion and make it difficult to query for all "deleted" documents. Consistent logical deletion simplifies code and prevents husked documents.

### ☐ Use EVICT for local-only removal (doesn't affect peers)

**What this means:** `EVICT FROM collection WHERE ...` removes documents from local storage only. Peers retain their copies and can re-share evicted documents later.

**Why this matters:** EVICT frees local storage without affecting other devices. Useful for clearing caches, removing old data, or managing storage limits on resource-constrained devices.

### ☐ Cancel subscriptions before EVICT to prevent resync loops

**What this means:** When evicting documents from local storage, cancel the corresponding subscription first, then EVICT, then recreate the subscription with an updated filter if needed.

**Why this matters:** Evicting documents while a subscription is active causes Ditto to immediately request them again from peers, creating an infinite resync loop that wastes network bandwidth and battery.

**Code Example**:

```dart
// ❌ BAD: EVICT without canceling subscription (resync loop!)
await ditto.store.execute(
  'EVICT FROM orders WHERE deletedAt < :cutoff',
  arguments: {'cutoff': cutoffDate},
);

// ✅ GOOD: Cancel subscription → EVICT → Recreate with updated filter
orderSubscription?.cancel();  // Step 1: Cancel first
await ditto.store.execute(
  'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :cutoff',
  arguments: {'cutoff': cutoffDate},
);
orderSubscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted != true',
);
```

### ☐ Use DELETE only for permanent removal (affects all peers)

**What this means:** `DELETE FROM collection WHERE ...` permanently removes documents from all peers in the mesh. Deletion propagates via tombstones during the TTL period (default: 30 days).

**Why this matters:** DELETE is irreversible and affects all peers. Use it only for:
- GDPR compliance (user requests data deletion)
- Permanent removal of sensitive data
- Internal/system data that doesn't need relay

For user-facing deletions (trash, archive), prefer logical deletion (Soft-Delete) to enable multi-hop relay and "undo" functionality.

### ☐ Understand tombstones and TTL behavior

**What this means:** When you DELETE a document, Ditto creates a tombstone that propagates to peers during the TTL window (default: 30 days). After TTL expires, the tombstone is removed, and peers who were offline during the entire TTL window may re-share the document ("zombie resurrection").

**Why this matters:** Tombstones enable deletion to propagate across the mesh, but only during the TTL period. If a peer is offline longer than the TTL (e.g., 35 days), they may resurrect deleted data when they reconnect because the tombstone has expired. This is why logical deletion (soft-delete) is preferred for user-facing data—it doesn't rely on TTL windows and works reliably in multi-hop scenarios even with long disconnection periods.

---

## Section 5: Read Operations & Queries

### ☐ Filter data in queries, not in application code

**What this means:** Use DQL `WHERE` clauses to filter data at the database level instead of fetching all documents and filtering in Dart/JavaScript/Swift code.

**Why this matters:** Database-level filtering reduces memory usage, improves query performance, and minimizes data transfer overhead.

### ☐ Use query result pagination for large datasets

**What this means:** For collections with thousands of documents, use `LIMIT` and `OFFSET` in queries to paginate results rather than fetching all documents at once.

**Why this matters:** Large result sets consume memory and slow down UI rendering. Pagination improves app responsiveness and reduces memory pressure.

### ☐ Don't retain QueryResultItem references long-term

**What this means:** Extract `item.value` from QueryResultItems immediately and convert to application models. Don't store QueryResultItems in state, pass them between functions, or hold references beyond the immediate callback scope.

**Why this matters:** QueryResultItems are database cursors that hold internal references to underlying data structures. Retaining them long-term prevents Ditto from releasing memory, causes memory leaks, and blocks database cleanup. Always extract data immediately and let QueryResultItems be garbage collected.

---

## Section 6: Subscriptions & Real-time Sync

### ☐ Use long-lived subscriptions, not request/response pattern

**What this means:** Create subscriptions once during app initialization or when entering a feature, keep them active while the feature is in use, and cancel only when leaving the feature. Don't create/cancel subscriptions repeatedly for each query.

**Why this matters:** Subscriptions are not HTTP requests—they're long-lived replication contracts that tell Ditto what data to sync. Frequent create/cancel cycles cause unnecessary connection overhead, delays in data availability, and increased battery usage. Ditto is offline-first: data should be continuously synced, not fetched on-demand.

### ☐ Subscribe broadly, filter in observers (for multi-hop relay)

**What this means:** Subscriptions should have minimal WHERE filters (or none for small collections). Apply detailed filters in observers and queries instead.

**Why this matters:** Narrow subscription filters prevent relay devices from storing documents needed by indirectly connected peers. Broad subscriptions enable multi-hop relay; local filters optimize UI display.

### ☐ Avoid subscribing to data you don't need

**What this means:** Don't create overly broad subscriptions like `SELECT * FROM *` unless absolutely necessary. Scope subscriptions to relevant collections and filters.

**Why this matters:** Subscriptions consume storage, network bandwidth, and battery. Over-subscription causes unnecessary data sync and degrades performance.

### ☐ Cancel observers and subscriptions when no longer needed

**What this means:** Store references to observers and subscriptions, then call `.cancel()` when the feature is closed or the widget is disposed.

**Why this matters:** Active observers and subscriptions consume resources (CPU, memory, network). Canceling them prevents memory leaks and reduces unnecessary processing.

### ☐ Use registerObserverWithSignalNext for backpressure control

**What this means:** Use `registerObserverWithSignalNext()` instead of `registerObserver()` to control when the next observer event is delivered. Call `signalNext()` after processing each event.

**Why this matters:** Prevents observer events from overwhelming the UI when rapid changes occur. Backpressure control ensures UI updates complete before the next batch arrives, improving responsiveness and preventing frame drops.

**Platform availability:**
- **Non-Flutter platforms** (iOS, Android, JavaScript, etc.): Recommended pattern available in SDK 4.x
- **Flutter**: Not available in SDK 4.x. Will be available in future SDK version. Use `registerObserver()` with manual debouncing if needed.

**Code Example** (Non-Flutter):

```dart
// ✅ GOOD: Observer with backpressure control
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
  arguments: {'deviceId': deviceId},
  onChange: (result, signalNext) {
    updateUI(result.items.map((item) => item.value).toList());
    // Call signalNext() when ready for next batch
    signalNext();
  },
);
```

### ☐ Handle observer errors gracefully

**What this means:** Wrap observer callbacks in try-catch blocks to handle unexpected errors (e.g., null values, malformed data).

**Why this matters:** Unhandled observer errors can crash the app or leave UI in inconsistent state. Graceful error handling ensures app stability.

### ☐ Avoid heavy computation in observer callbacks

**What this means:** Keep observer callbacks lightweight. Offload heavy computation (data transformation, business logic) to background isolates or threads.

**Why this matters:** Observer callbacks block the UI thread. Heavy computation causes frame drops and unresponsive UI. Offloading ensures smooth user experience.

---

## Section 7: Performance Optimization

### ☐ Use CREATE INDEX for selective queries [SDK 4.12+]

**What this means:** Create indexes on fields frequently used in WHERE clauses for queries that return a small subset of documents (high selectivity). Use `CREATE INDEX IF NOT EXISTS idx_name ON collection (field)`.

**Why this matters:** Indexes can improve query performance by up to 90% for selective queries (those returning <10% of collection). Without indexes, Ditto performs full collection scans. However, indexes have overhead for writes and storage, so only index fields used in selective queries.

### ☐ Use EXPLAIN to verify index usage [SDK 4.12+]

**What this means:** Prefix queries with `EXPLAIN` to see the execution plan and confirm indexes are used: `EXPLAIN SELECT * FROM orders WHERE status = 'pending'`.

**Why this matters:** EXPLAIN reveals whether indexes are used, scan counts, and performance bottlenecks. Helps validate that indexes are correctly applied.

### ☐ Avoid N+1 query patterns (multiple individual lookups)

**What this means:** Instead of querying for each related document individually in a loop (N queries), fetch all related documents in a single query using `WHERE _id IN (...)`.

**Why this matters:** N+1 patterns multiply query overhead. For example, fetching 100 related documents individually requires 100 queries vs 1 batch query. Batch queries reduce execution time and improve performance significantly.

### ☐ Batch multiple operations in transactions [SDK 4.11+]

**What this means:** Use `ditto.store.transaction()` to batch multiple INSERT/UPDATE/DELETE operations into a single atomic transaction.

**Why this matters:** Transactions reduce sync overhead by batching deltas and ensure atomicity. Multiple separate operations create individual deltas and lack transactional guarantees.

---

## Section 8: Transactions

### ☐ Use transactions for multi-step atomic operations [SDK 4.11+]

**What this means:** Wrap related INSERT/UPDATE/DELETE operations in `ditto.store.transaction()` to ensure they execute atomically (all succeed or all fail).

**Why this matters:** Without transactions, partial failures leave data in inconsistent state. Transactions provide atomicity and rollback on errors, ensuring data integrity.

**Code Example**:

```dart
// ✅ GOOD: Atomic transaction for order processing
await ditto.store.transaction(hint: 'process-order', (tx) async {
  final order = (await tx.execute(
    'SELECT * FROM orders WHERE _id = :id', arguments: {'id': orderId},
  )).items.first.value;

  await tx.execute('UPDATE orders SET status = :s WHERE _id = :id',
    arguments: {'id': orderId, 's': 'shipped'});
  await tx.execute('UPDATE inventory APPLY qty COUNTER INCREMENT BY -1.0 WHERE _id = :itemId',
    arguments: {'itemId': order['itemId']});
});
```

### ☐ Use read-only transactions for consistent multi-query reads

**What this means:** When reading related data across multiple queries, use `ditto.store.transaction()` (without writes) to ensure all queries see a consistent snapshot.

**Why this matters:** Without transactions, data can change between queries, causing inconsistent reads. Read-only transactions provide snapshot isolation.

### ☐ Never nest read-write transactions (causes deadlock)

**What this means:** Don't call `ditto.store.transaction()` inside another read-write transaction. Nested read-only transactions are safe, but nested writes cause permanent deadlocks.

**Why this matters:** Nested read-write transactions create a deadlock where the inner transaction waits for the outer to complete, while the outer waits for the inner. The app freezes permanently and requires force-quit. This is a critical error that developers must avoid.

**Platform note:** Flutter SDK v4.11+ supports transactions but does not have this nesting limitation check. Non-Flutter platforms have this limitation.

### ☐ Keep transactions short and focused

**What this means:** Minimize the number of operations and execution time inside transactions. Avoid heavy computation, network calls, or long-running logic.

**Why this matters:** Long transactions hold locks, blocking other operations and reducing concurrency. Short transactions improve throughput and responsiveness.

### ☐ (Flutter-specific) Always await pending transactions before ditto.close()

**What this means:** In Flutter SDK, track all pending transactions and use `await Future.wait(pendingTransactions)` before calling `ditto.close()`. Unlike other platforms, Flutter SDK does not wait for transactions automatically.

**Why this matters:** Closing Ditto before transactions complete causes data loss. Transactions may be incomplete or corrupted. You must manually track and await all transaction futures before closing the Ditto instance.

**Platform note:** This limitation is specific to Flutter SDK v4.11+. Other platforms automatically wait for transaction completion.

---

## Section 9: Attachments

### ☐ Use attachments for large binary data (images, videos, files)

**What this means:** Store large binary data (typically >100KB) as Ditto attachments, not as base64 strings in document fields. Store attachment tokens in document fields to reference the binary data.

**Why this matters:** Embedding binary data in documents bloats sync traffic and storage, as every document change syncs the entire binary blob. Attachments are lazy-loaded and fetched on-demand only when needed, dramatically reducing bandwidth usage and improving sync performance.

### ☐ Handle attachment fetch errors gracefully

**What this means:** Wrap `fetchAttachment()` in try-catch blocks to handle cases like peer unavailability, network timeout, or corrupted data.

**Why this matters:** Attachment fetches can fail due to network issues or missing peers. Graceful error handling provides user feedback and retry options.

### ☐ Set attachment fetch timeouts appropriately

**What this means:** Use `fetchAttachment()` timeout parameter to limit wait time for slow or unavailable peers: `fetchAttachment(token, timeout: Duration(seconds: 30))`.

**Why this matters:** Without timeouts, attachment fetches can hang indefinitely when peers are offline. Timeouts ensure responsive UX.

### ☐ Understand attachment availability constraints (immediate peers only)

**What this means:** Attachments can only be fetched from **immediate peers** (directly connected devices) that have already fetched the attachment. In a multi-hop scenario where Device A has the attachment and Device C wants it, Device C cannot fetch from Device A if Device B (the intermediary) hasn't fetched it yet.

**Why this matters:** Unlike documents that sync through multi-hop relay, attachments require direct peer connection. Users may see document metadata but be unable to download the attachment until an intermediate peer fetches it first. Design UI to show attachment availability status (e.g., "Available from 2 peers").

### ☐ Implement timeout detection for stalled attachment fetches

**What this means:** Ditto's attachment fetch does not raise errors when connections stall—it simply stops making progress. Implement a progress monitoring wrapper that detects when no progress has occurred for a timeout period (e.g., 5 minutes).

**Why this matters:** If all source peers disconnect during a fetch, Ditto will not report an error but the fetch will stall indefinitely, consuming resources. Timeout detection allows you to cancel stalled fetches, notify users, or retry gracefully.

### ☐ Clean up orphaned attachment tokens periodically

**What this means:** When deleting documents with attachments, consider removing attachment references. Periodically scan for attachment tokens with no corresponding documents.

**Why this matters:** Orphaned attachments consume storage without serving any purpose. Cleanup frees storage on resource-constrained devices.

### ☐ Consider attachment size limits for Bluetooth LE transport

**What this means:** On mobile devices relying on Bluetooth LE, limit attachment sizes (e.g., <5MB for images, use thumbnails for larger). Test sync performance over Bluetooth.

**Why this matters:** Bluetooth LE has lower bandwidth than WiFi/LAN. Large attachments over Bluetooth are slow and impact user experience.

---

## Section 10: Security

### ☐ Use OnlineWithAuthenticationIdentity for production apps

**What this means:** Configure Ditto with `OnlineWithAuthenticationIdentity` and implement an authentication delegate to integrate with your auth system (OAuth, JWT, custom).

**Why this matters:** OnlinePlaygroundIdentity has no access controls and is insecure for production. OnlineWithAuthentication enforces proper permissions via Ditto Big Peer.

### ☐ Never commit API keys, tokens, or credentials

**What this means:** Use environment variables or secure storage for Ditto App ID, authentication tokens, and API keys. Never hardcode or commit them to version control.

**Why this matters:** Exposed credentials allow unauthorized access to your Ditto app and data. Use `.env` files (excluded from git) or platform-specific secure storage.

### ☐ Implement proper authentication delegate callbacks

**What this means:** Implement `onAuthenticationExpiringSoon()` and `onAuthenticationRequired()` callbacks to refresh tokens before expiry and prompt re-authentication.

**Why this matters:** Expired tokens cause sync failures. Proactive token refresh ensures continuous sync and prevents user disruption.

### ☐ Use SharedKeyIdentity only for fully offline deployments

**What this means:** SharedKeyIdentity (offline mode) disables cloud sync and uses a shared secret for mesh authentication. Use only when cloud connectivity is not available.

**Why this matters:** SharedKey lacks cloud-based access controls and audit trails. Suitable for air-gapped deployments but not for internet-connected apps.

### ☐ Never hardcode SharedKey in application code (security risk)

**What this means:** Don't hardcode SharedKey values directly in mobile app source code. Use MDM (Mobile Device Management) for secure key distribution, or secure platform-specific storage with runtime provisioning.

**Why this matters:** Hardcoded keys in mobile apps are vulnerable to reverse engineering. Attackers can decompile APK/IPA files to extract the SharedKey, compromising the entire mesh network. A single leaked key grants unauthorized access to all mesh data. Use controlled distribution mechanisms like MDM.

### ☐ Validate and sanitize user inputs before inserting into Ditto

**What this means:** Apply input validation (length limits, format checks, injection prevention) before inserting user-provided data into documents.

**Why this matters:** Malicious inputs can cause injection vulnerabilities or data corruption. Validation ensures data integrity and security.

### ☐ Avoid storing sensitive data (PII, passwords) in Ditto documents

**What this means:** Don't store passwords, credit card numbers, SSNs, or highly sensitive PII directly in Ditto. Use references to secure external storage or encrypt before storing.

**Why this matters:** Ditto syncs data across devices and peers. Sensitive data exposure increases risk. Use encryption or external secure storage for highly sensitive data.

---

## Section 11: Observability & Testing

### ☐ Enable minimum logging level in production

**What this means:** Set Ditto's minimum log level to `warning` or `error` in production using `setMinimumLogLevel()`. Use `debug` only during development.

**Why this matters:** Verbose logging (`debug`) creates large log files, consumes storage, and may expose sensitive data. Production apps should log errors only.

### ☐ Query system info for debugging (SDK 4.13+)

**What this means:** Use `SELECT * FROM SYSTEM_INFO` to retrieve SDK version, platform, device ID, and configuration for support tickets.

**Why this matters:** System info helps support teams diagnose environment-specific issues. Include it in bug reports.

### ☐ Monitor sync health with observability callbacks

**What this means:** Implement transport condition callbacks to monitor network connectivity and peer availability.

**Why this matters:** Sync health visibility helps diagnose connectivity issues and provides user feedback (e.g., "offline mode").

### ☐ Use presence to track connected peers

**What this means:** Use Ditto Presence API to observe which peers are currently connected and available for sync.

**Why this matters:** Presence data enables features like "online user" lists and helps debug sync issues by showing peer connectivity.

### ☐ Test offline-first behavior (create data while offline)

**What this means:** Write tests that create, update, and delete data while `ditto.startSync()` is not called or network is disabled. Verify data syncs correctly after reconnection and no data loss occurs.

**Why this matters:** Offline-first is Ditto's core value proposition. Apps must work seamlessly while disconnected and sync correctly when connectivity returns. Testing offline scenarios catches issues like missing subscriptions, improper error handling, or data loss during reconnection.

### ☐ Test multi-device conflict scenarios

**What this means:** Simulate concurrent updates to the same document from multiple devices while offline (e.g., both devices update different fields). Verify CRDT merge behavior produces expected results after sync.

**Why this matters:** Conflict resolution is CRDT-dependent (MAP uses add-wins, REGISTER uses last-write-wins). Tests ensure data integrity under concurrent modifications and validate that your data model merges correctly. For example, concurrent updates to MAP fields should both persist, while concurrent array updates use last-write-wins.

### ☐ Test logical deletion and filtering patterns

**What this means:** Verify that logically deleted documents (e.g., `isDeleted: true`) are filtered correctly in observers/queries and still sync to all peers via subscriptions.

**Why this matters:** Incorrect logical deletion patterns break multi-hop relay. Tests ensure subscriptions remain broad while observers filter locally. See [Section 4: Deletion & Storage Lifecycle](#section-4-deletion--storage-lifecycle) for implementation patterns.

### ☐ Test EVICT and resync behavior

**What this means:** Test that evicted documents don't resync immediately if subscriptions are still active. Verify resync occurs after subscription recreation with updated filters.

**Why this matters:** Improper EVICT patterns cause resync loops. Tests prevent bandwidth waste and battery drain. See [Section 4: Deletion & Storage Lifecycle](#section-4-deletion--storage-lifecycle) for implementation patterns.

### ☐ Write integration tests for Ditto SDK initialization

**What this means:** Test that `Ditto.open()`, `startSync()`, and authentication flow complete successfully under various network conditions.

**Why this matters:** Initialization failures cause app-wide issues. Integration tests catch configuration errors early.

### ☐ Test timestamp precision and clock drift tolerance

**What this means:** Write tests that simulate devices with mismatched clocks (e.g., Device A is 5 seconds ahead, Device B is 3 seconds behind). Verify that timestamp-based logic handles clock drift gracefully with appropriate tolerance ranges.

**Why this matters:** Device clocks are never perfectly synchronized. iOS typically has ~100ms drift, while Android can drift by several seconds. Timestamp-based validation (e.g., `createdAt < updatedAt`) can fail due to clock skew. Tests ensure your logic tolerates reasonable clock drift.
