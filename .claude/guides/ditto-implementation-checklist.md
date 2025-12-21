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

**Code Example**:

```dart
// ✅ GOOD: Proper error handling for Ditto initialization
try {
  final ditto = await Ditto.open(
    identity: OnlinePlaygroundIdentity(appId: appId, token: token),
  );
  await ditto.startSync();
} on DittoError catch (e) {
  // Handle Ditto-specific errors (licensing, permissions, etc.)
  print('Ditto initialization failed: ${e.message}');
  showErrorDialog('Failed to initialize sync');
} catch (e) {
  // Handle unexpected errors
  print('Unexpected error: $e');
}
```

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

### ☐ Avoid ID patterns that can cause collisions across devices

**What this means:** Never use sequential counters, timestamps, or device-based patterns for document IDs when multiple devices can create documents independently. Use globally unique identifiers (UUID v4, ULID) or let Ditto auto-generate IDs. Composite keys (e.g., `{"userId": "user123", "orderId": "<uuid>"}`) are acceptable when the combination is guaranteed unique.

**Why this matters:** Sequential ID generation causes collisions when multiple offline devices create documents with the same ID pattern (e.g., "order_001"). Collisions trigger conflict resolution, potentially causing data loss or unexpected behavior. For authorization patterns using composite keys (e.g., `{"userId": "user123", "resourceId": "<uuid>"}`), ensure at least one component is globally unique.

**Code Example**:

```dart
// ❌ BAD: Sequential IDs cause collisions across offline devices
int orderCounter = 1;
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {'_id': 'order_${orderCounter++}', 'item': 'Coffee'}
  },
);
// Device A creates "order_1", Device B also creates "order_1" → Collision!

// ✅ GOOD: Let Ditto auto-generate globally unique IDs
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {'item': 'Coffee'}  // No _id → Ditto auto-generates
  },
);
```

**Note**: Composite keys are useful for authorization patterns (permissions based on `_id.userId`). See Section 10 for security patterns.

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

**Embedded (denormalized)**:
- Store related data directly within the parent document
- Requires single query to retrieve all data
- Data duplication across documents (same customer info in multiple orders)
- All related data syncs as a single unit
- Best for: Small, static data retrieved together (order items, user profile with address)

**Foreign-key (normalized)**:
- Store related data in separate documents, reference by ID
- Requires multiple sequential queries (no JOIN support in Ditto)
- No data duplication, single source of truth
- Related data syncs independently
- Best for: Large data, frequently updated data, or data accessed independently (user profiles, product catalogs)

**Why this matters:** Ditto does not support SQL-style JOINs. With embedded data, one query retrieves everything but duplicates data across documents. With foreign-keys, you need multiple sequential queries (N+1 pattern risk) but maintain a single source of truth. Choose based on: (1) how data is accessed together, (2) update frequency, (3) data size, and (4) acceptable duplication trade-offs. Embedded data optimizes read performance at the cost of write overhead and storage; foreign-keys optimize write performance and storage at the cost of multiple queries.

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

### ☐ Exclude unnecessary data from documents

**What this means:** Every field in a Ditto document syncs across all peers in the mesh network, consuming bandwidth and storage. Only include data that represents shared business state needed across devices. Don't sync:

- **UI-specific state**: Expansion/selection/hover states, scroll positions, active tab indices
- **Temporary/transient state**: Upload progress, processing flags, retry counters, loading indicators
- **Device-specific data**: Local file paths, device IDs (unless required for authorization), device capabilities
- **Cached/derived data**: Values that can be calculated from other fields or fetched from external sources
- **High-frequency ephemeral data**: Mouse cursor positions, typing indicators, real-time sensor readings that don't need persistence
- **Debug/development data**: Test flags, debug counters, development-only metadata

**Why this matters:** Syncing unnecessary data wastes network bandwidth (critical for metered connections), drains battery (continuous sync), bloats storage on all devices, and slows sync performance for important business data. Every peer must store, process, and relay this data, even though much of it is only relevant to a single device or moment in time.

**Key principle:** Only sync data that represents **business state** (the "single source of truth" needed across devices), not **presentation state** (how UI displays data), **transient state** (temporary processing status), or **device-local state** (specific to one device's environment).

**Code Example**:

```dart
// ❌ BAD: Syncing unnecessary data
{
  "_id": "task_123",
  "title": "Review PR",
  "status": "pending",
  // ❌ UI state (device-specific, not business data)
  "isExpanded": true,
  "selectedTab": 2,
  // ❌ Temporary state (transient, changes frequently)
  "uploadProgress": 67,
  "isProcessing": false,
  // ❌ Device-specific (only relevant to one device)
  "localFilePath": "/storage/cache/task_123.tmp",
  // ❌ Cached data (can be fetched from external source)
  "userAvatarUrl": "https://api.example.com/avatars/user_789.jpg"
}

// ✅ GOOD: Only business state synced, other data managed locally
{
  "_id": "task_123",
  "title": "Review PR",
  "status": "pending",
  "assignee": "user_789"  // Business data: who's responsible
}

// Store non-business state locally (ViewModel, cache, device storage):
class TaskViewModel {
  final Task task;  // Ditto business data
  bool isExpanded = false;  // UI state (local)
  double uploadProgress = 0.0;  // Temporary state (local)
  String? cachedAvatarUrl;  // Cached data (fetched as needed)
}
```

---

### ☐ Enable DQL Strict Mode for type safety across peers [SDK 4.11+]

**What this means:** Execute `ALTER SYSTEM SET DQL_STRICT_MODE = true` before `startSync()` to enforce type consistency across all fields. This prevents different devices from writing incompatible types to the same field.

**Why this matters:** Without Strict Mode, Device A can write `{"age": 30}` (number) while Device B writes `{"age": "thirty"}` (string), causing cross-peer data inconsistency and unpredictable query results. Strict Mode enforces type declarations via MAP literals, catching type errors at development time instead of runtime.

---

## Section 3: Write Operations

### ☐ Use ON ID CONFLICT DO NOTHING for safe repeated INSERTs

**What this means:** When inserting documents that should only be created once (e.g., initial setup data), use `INSERT ... ON ID CONFLICT DO NOTHING` to silently skip if the document already exists.

**Why this matters:** Prevents errors when re-running initialization code. Allows you to safely run the same INSERT statement multiple times without checking if the document already exists first.

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

**What this means:** Before executing an UPDATE statement, query the document to check if the new value differs from the current value. Skip the UPDATE if the values are identical.

**Why this matters:** Even when updating a field with the same value (e.g., setting `status = "pending"` when it's already `"pending"`), Ditto treats this as a change and creates a sync delta. This delta is transmitted to all peers across the mesh network, consuming bandwidth and triggering observer callbacks unnecessarily. The underlying CRDT counter increments regardless of whether the value actually changed, causing every peer to process the update. By checking before updating, you avoid this unnecessary network traffic, reduce sync overhead, and prevent redundant UI updates across all connected devices. This is particularly important in high-frequency update scenarios where the same value might be set repeatedly (e.g., periodic status checks, polling loops, or user interactions).

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

### ☐ Don't use counters for derived values that can be calculated

**What this means:** Avoid maintaining counter fields that represent aggregated or calculated values from other data sources. Instead, calculate these values from the source data when needed. Common anti-patterns include:

- **Inventory counters**: Don't maintain `currentStock` as a counter field—calculate it from order/transaction history
- **Relationship counts**: Don't maintain `followerCount` updated from `followers` collection—query and count when needed
- **Status tallies**: Don't maintain `completedTaskCount` from `tasks` collection—query with filters

**Why this matters:** Counters for derived values create several problems:

1. **Cross-collection synchronization complexity**: Updating source data (e.g., orders) requires also updating counters in other collections (e.g., products), creating tight coupling
2. **Data integrity risk**: Source data and counters can become inconsistent if updates fail partially or sync in wrong order
3. **Not self-correcting**: If counters drift out of sync due to bugs or data issues, they don't auto-correct. Calculated values are always accurate based on current source data.
4. **Single source of truth violation**: Maintains redundant state that must be kept synchronized

**When counters ARE appropriate:** Use counters (COUNTER type with PN_INCREMENT) for **independent, additive data** where each increment is a standalone event:
- ✅ View counts (each view is independent)
- ✅ Like counts (each like is independent)
- ✅ Usage metrics (each usage event is independent)
- ✅ Vote tallies (each vote is independent)

**Code Example**:

```dart
// ❌ BAD: Using counter for derived inventory value
// Product document maintains currentStock counter
{
  "_id": "product_123",
  "name": "Coffee Beans",
  "currentStock": 50  // ❌ Counter updated from orders collection
}

// When order is placed, must update TWO collections:
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {'order': {'_id': 'o1', 'productId': 'product_123', 'qty': 5}}
);
await ditto.store.execute(
  'UPDATE products APPLY currentStock PN_INCREMENT BY -5.0 WHERE _id = :id',
  arguments: {'id': 'product_123'}
);
// Problems: Cross-collection coupling, integrity risk, not self-correcting

// ✅ GOOD: Calculate inventory from order history
// Product document has no stock counter
{
  "_id": "product_123",
  "name": "Coffee Beans",
  "initialStock": 100  // Starting inventory (baseline)
}

// Order documents are source of truth
{'_id': 'o1', 'productId': 'product_123', 'qty': 5}
{'_id': 'o2', 'productId': 'product_123', 'qty': 10}

// Calculate current stock from orders when needed:
int calculateCurrentStock(String productId) {
  final product = getProduct(productId);
  final orders = getOrders(productId);
  final totalOrdered = orders.fold(0, (sum, order) => sum + order['qty']);
  return product['initialStock'] - totalOrdered;
}
// Benefits: Single source of truth, self-correcting, no cross-collection updates
```

**Decision guide:**
- **Use calculation** if the value is derived from existing data (aggregations, sums, counts of related documents)
- **Use COUNTER** if each increment represents an independent event that doesn't depend on other documents

### ☐ Use separate documents for event history, not arrays

**What this means:** For append-only logs (status history, audit trails), INSERT a new document for each event instead of appending to an array field.

**Why this matters:** Arrays are REGISTER CRDTs (Last-Write-Wins). Concurrent appends from offline peers result in lost events after merge. Separate documents allow all events to be preserved independently.

### ☐ Use INITIAL DOCUMENTS for device-local templates

**What this means:** For device-local default data (categories, templates, seed data), use `INSERT INTO collection INITIAL DOCUMENTS (...)` instead of regular `INSERT`.

**Why this matters:** Regular INSERT creates sync deltas that propagate to all peers unnecessarily. `INITIAL DOCUMENTS` treats data as "existing from the beginning of time," preventing sync traffic for device-local templates.

---

## Section 4: Deletion & Storage Lifecycle

### ☐ Understand the difference between Soft-Delete and DELETE queries

**What this means:** In distributed databases like Ditto, deleting data on one device doesn't automatically remove it from others. Both approaches are **deletion propagation mechanisms** with different trade-offs:

- **Soft-Delete Pattern**: Developer-implemented pattern using UPDATE operations to mark documents as deleted (e.g., `UPDATE orders SET isDeleted = true WHERE _id = :id`). Deletion flags propagate through the mesh network like any other field update. Filter deleted documents in queries/observers, then periodically remove them locally with EVICT.
- **DELETE query**: Built-in operation that physically removes documents and automatically creates Tombstones (compressed deletion markers with 30-day TTL on Cloud, configurable on Edge SDK). Tombstones propagate through the mesh to notify peers about deletions.

**Why this matters:** Both approaches eventually result in permanent data removal. The choice is about **how deletion information propagates** through the mesh:

**Soft-Delete propagation advantages:**
- ✅ No TTL dependency: Deletion flags persist until EVICT, so long-offline devices always receive deletion notifications
- ✅ CRDT-safe: UPDATE operations merge cleanly, preventing husked documents from concurrent DELETE + UPDATE conflicts
- ✅ Reliable multi-hop relay: Deletion flags propagate through intermediary peers like any other field update

**Soft-Delete propagation disadvantages:**
- ❌ Higher code complexity: Must filter `isDeleted` consistently in all queries and observers
- ❌ Implementation discipline required: Easy to forget filtering or incorrectly filter in subscriptions (breaks relay)
- ❌ Larger dataset until EVICT: Slightly slower queries as deleted documents remain in database
- ❌ Manual cleanup required: Must implement periodic EVICT to permanently remove old deleted documents

**DELETE propagation advantages:**
- ✅ Simpler implementation: Automatic Tombstone creation and propagation, no filtering logic needed
- ✅ Smaller active dataset: Documents removed immediately, faster queries after Tombstone TTL expires
- ✅ Automatic cleanup: Tombstones expire automatically after TTL period

**DELETE propagation disadvantages:**
- ❌ TTL-based propagation: Devices offline longer than TTL miss deletion notification, may resurrect deleted data (zombie data)
- ❌ CRDT conflicts possible: Concurrent DELETE + UPDATE from different peers can create husked documents (partial null fields)
- ❌ Tombstone propagation timing: Brief window during multi-hop relay before all peers receive Tombstones

**Choose based on your application's requirements:**
- **Use Soft-Delete** when: Devices may be offline longer than Tombstone TTL (>30 days Cloud, >configured Edge), concurrent DELETE + UPDATE scenarios are likely, or reliable multi-hop relay propagation is critical for your use case
- **Use DELETE** when: All devices sync regularly within Tombstone TTL period, temporary/ephemeral data with short lifecycle, simpler implementation is preferred, or concurrent DELETE + UPDATE scenarios are unlikely

### ☐ (If using Soft-Delete) Subscribe broadly, filter in observers/queries

**What this means:** When implementing Soft-Delete with an `isDeleted` flag:
- **Subscriptions**: `SELECT * FROM orders` (no `isDeleted` filter)
- **Observers**: `SELECT * FROM orders WHERE isDeleted != true`
- **Queries**: `SELECT * FROM orders WHERE isDeleted != true`

**Why this matters:** Filtering deletion flags in subscriptions breaks multi-hop relay. Intermediate devices won't store deleted documents, preventing deletion notifications from reaching indirectly connected peers. Subscribe broadly for relay, filter locally for display. This is a critical implementation pattern only for Soft-Delete—if using DELETE queries, this does not apply.

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

### ☐ (If using Soft-Delete) Periodically EVICT old deleted documents

**What this means:** After marking documents as deleted (e.g., `isDeleted: true, deletedAt: <timestamp>`), periodically run `EVICT FROM collection WHERE isDeleted = true AND deletedAt < :cutoff` to free local storage. Choose an appropriate retention period (e.g., 30-90 days).

**Why this matters:** Soft-Delete keeps documents in the database indefinitely, consuming storage. Eviction removes old deleted documents from local storage without affecting peers (EVICT is local-only, not DELETE). This prevents storage bloat while maintaining multi-hop relay during the retention period.

### ☐ (If using Soft-Delete) Use EVICT for local-only removal

**What this means:** `EVICT FROM collection WHERE ...` removes documents from local storage only. Peers retain their copies and can re-share evicted documents later.

**Why this matters:** EVICT frees local storage without affecting other devices. Useful for clearing caches, removing old data, or managing storage limits on resource-constrained devices. This is critical for Soft-Delete cleanup—EVICT removes documents locally after the retention period without affecting multi-hop relay.

### ☐ (If using Soft-Delete) Cancel subscriptions before EVICT to prevent resync loops

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

### ☐ (If using DELETE) Understand tombstones and TTL behavior

**What this means:** When you DELETE a document, Ditto creates a tombstone that propagates to peers during the TTL window (default: 30 days). After TTL expires, the tombstone is removed, and peers who were offline during the entire TTL window may re-share the document ("zombie resurrection").

**Why this matters:** Tombstones are Ditto's built-in deletion propagation mechanism that automatically notifies all peers about deletions. However, Tombstones only exist during the TTL period. If a peer is offline longer than the TTL (e.g., 35 days on Cloud), they miss the deletion notification and may resurrect deleted data when they reconnect. For applications where devices may be offline longer than the TTL period, Soft-Delete provides more reliable deletion propagation as flags persist indefinitely until EVICT.

### ☐ (If using DELETE) Understand husked documents and how to prevent them

**What this means:** "Husked documents" occur when one peer DELETEs a document while another peer concurrently UPDATEs it. After merge, the document exists but has only `_id` and the updated field(s), with all other fields set to null.

**Why this matters:** Husked documents can break application logic that assumes required fields always exist. Soft-Delete prevents husking by using UPDATE instead of DELETE.

**Code Example**:

```dart
// ❌ PROBLEM: DELETE + concurrent UPDATE = husked document
// Device A:
await ditto.store.execute('DELETE FROM cars WHERE _id = :id', arguments: {'id': 'car1'});
// Device B (offline):
await ditto.store.execute('UPDATE cars SET color = :color WHERE _id = :id', arguments: {'color': 'blue', 'id': 'car1'});
// Result after sync: {_id: "car1", color: "blue", make: null, model: null}

// ✅ SOLUTION: Soft-Delete prevents husked documents
await ditto.store.execute(
  'UPDATE cars SET isDeleted = true, deletedAt = :time WHERE _id = :id',
  arguments: {'time': DateTime.now().toIso8601String(), 'id': 'car1'},
);
```

### ☐ (If using DELETE) Use DELETE only for permanent, irreversible removal

**What this means:** `DELETE FROM collection WHERE ...` permanently removes documents from all peers in the mesh. Deletion propagates via tombstones during the TTL period (default: 30 days).

**Why this matters:** DELETE is irreversible and propagates via Tombstones to all peers. Both Soft-Delete and DELETE eventually result in permanent data removal—the difference is the propagation mechanism. DELETE works well for:
- Temporary/ephemeral data with short lifecycle
- Scenarios where all devices sync regularly within TTL period
- Simpler implementation is preferred

For applications where devices may be offline longer than Tombstone TTL, or where concurrent DELETE + UPDATE scenarios are likely, Soft-Delete provides more reliable deletion propagation through UPDATE-based flags that persist until EVICT.

---

## Section 5: Read Operations & Queries

### ☐ Filter data in queries, not in application code

**What this means:** Use DQL `WHERE` clauses to filter data at the database level instead of fetching all documents and filtering in application code.

**Why this matters:** Database-level filtering reduces memory usage, improves query performance, and minimizes data transfer overhead. When you fetch all documents and filter in application code, Ditto must:
1. Load all documents from storage into memory
2. Deserialize all documents from internal format (CBOR) to application objects
3. Allocate memory for QueryResultItems that hold references to underlying data structures

This creates unnecessary memory pressure, especially on resource-constrained devices. Database-level filtering (WHERE clauses) happens inside Ditto's storage engine before deserialization, minimizing memory allocation and processing overhead. For large collections (thousands of documents), the performance difference is significant: application-level filtering can cause memory issues or slow performance, while database filtering keeps memory usage constant regardless of collection size.

**Code Example**:

```dart
// ❌ BAD: Fetch all documents, filter in application code
final result = await ditto.store.execute('SELECT * FROM orders');
final activeOrders = result.items
  .map((item) => item.value)
  .where((order) => order['status'] == 'active')
  .toList();
// Problems: High memory usage, slow deserialization, all documents loaded

// ✅ GOOD: Filter at database level with WHERE clause
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
final activeOrders = result.items.map((item) => item.value).toList();
// Benefits: Low memory usage, fast query, only filtered documents loaded
```

### ☐ Use query result pagination for large datasets

**What this means:** For collections with thousands of documents, use `LIMIT` and `OFFSET` in queries to paginate results rather than fetching all documents at once.

**Why this matters:** Large result sets consume memory and slow down UI rendering. Pagination improves app responsiveness and reduces memory pressure.

### ☐ Don't retain QueryResultItem references long-term

**What this means:** Extract `item.value` from QueryResultItems immediately and convert to application models. Don't store QueryResultItems in state, pass them between functions, or hold references beyond the immediate callback scope.

**Why this matters:** QueryResultItems are lazy-loading database cursors, not plain data objects. They hold internal references to Ditto's storage engine and underlying CRDT data structures. Retaining QueryResultItems long-term causes:

1. **Memory leaks**: Prevents Ditto from releasing memory for internal data structures
2. **Blocked garbage collection**: Holds references that prevent cleanup of processed results
3. **Unpredictable behavior**: Cursors may become stale if underlying data changes
4. **Resource exhaustion**: Accumulating cursors consumes memory proportional to query result count

**Best practice:** Extract data immediately in observer callbacks or query handlers, convert to plain Dart objects or application models, and let QueryResultItems fall out of scope for garbage collection.

**Code Example**:

```dart
// ❌ BAD: Retaining QueryResultItem references (memory leak)
class OrdersViewModel {
  List<QueryResultItem> _orderItems = [];  // ❌ Storing cursors!

  void updateOrders(QueryResult result) {
    _orderItems = result.items.toList();  // ❌ Long-lived references
  }

  void displayOrder(int index) {
    final order = _orderItems[index].value;  // ❌ Using stale cursor
    print('Order: ${order['title']}');
  }
}
// Problem: Holds QueryResultItem cursors indefinitely, memory never released

// ✅ GOOD: Extract data immediately, store plain objects
class OrdersViewModel {
  List<Order> _orders = [];  // ✅ Plain application models

  void updateOrders(QueryResult result) {
    // Extract data immediately and convert to models
    _orders = result.items
      .map((item) => Order.fromMap(item.value))
      .toList();
    // QueryResultItems fall out of scope here, GC can clean them up
  }

  void displayOrder(int index) {
    final order = _orders[index];  // ✅ Using plain model
    print('Order: ${order.title}');
  }
}

// Application model (plain Dart class)
class Order {
  final String id;
  final String title;
  final String status;

  Order({required this.id, required this.title, required this.status});

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['_id'] as String,
      title: map['title'] as String,
      status: map['status'] as String,
    );
  }
}
```

---

## Section 6: Subscriptions & Real-time Sync

### ☐ Use long-lived subscriptions, not request/response pattern

**What this means:** Create subscriptions once during app initialization or when entering a feature, keep them active while the feature is in use, and cancel only when leaving the feature. Don't create/cancel subscriptions repeatedly for each query.

**Why this matters:** Subscriptions are not HTTP requests—they're long-lived replication contracts that tell Ditto what data to sync. Frequent create/cancel cycles cause unnecessary connection overhead, delays in data availability, and increased battery usage. Ditto is offline-first: data should be continuously synced, not fetched on-demand.

**Common mistake:** Treating Ditto like a REST API by creating a subscription, waiting briefly, querying data, and immediately canceling. This defeats the purpose of mesh sync and prevents real-time updates from reaching your device.

**When to cancel subscriptions:**
- ✅ When a feature/screen is permanently closed (not just hidden temporarily)
- ✅ Before EVICT operations to prevent resync loops
- ✅ When subscription scope needs to change (cancel old, create new with updated query)
- ✅ During app termination for proper cleanup

**When NOT to cancel:**
- ❌ Between individual queries to the same data
- ❌ During temporary UI state changes (navigation, minimize/maximize)
- ❌ After every data read operation

**Code Example**:

```dart
// ❌ BAD: Request/response pattern (treating Ditto like HTTP)
Future<List<Order>> fetchOrders() async {
  final sub = ditto.sync.registerSubscription('SELECT * FROM orders');
  await Future.delayed(Duration(seconds: 2));  // Inefficient waiting!
  final result = await ditto.store.execute('SELECT * FROM orders');
  sub.cancel();  // Defeats mesh sync benefits
  return result.items.map((item) => Order.fromMap(item.value)).toList();
}

// ✅ GOOD: Long-lived subscription with observer for real-time updates
class OrdersService {
  Subscription? _subscription;
  StoreObserver? _observer;

  void initialize() {
    // Start subscription - keep alive for feature lifetime
    _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');

    // Use observer for real-time updates
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        updateUI(result.items.map((item) => Order.fromMap(item.value)));
        signalNext();
      },
    );
  }

  void dispose() {
    _observer?.cancel();
    _subscription?.cancel();  // Cancel only when feature is done
  }
}
```

### ☐ Subscribe broadly, filter in observers (for multi-hop relay)

**What this means:** Subscriptions should have minimal WHERE filters (or none for small collections). Apply detailed filters in observers and queries instead.

**Why this matters:** Narrow subscription filters prevent relay devices from storing documents needed by indirectly connected peers. Broad subscriptions enable multi-hop relay; local filters optimize UI display.

**The multi-hop relay problem:** Consider a mesh network with Device A (source) → Device B (relay) → Device C (destination). If Device B subscribes with a narrow filter like `WHERE priority = 'high'`, it won't store low-priority documents from Device A. When Device C subscribes to all orders, it never receives the low-priority documents because Device B (the relay) doesn't have them to forward. This breaks multi-hop relay for filtered-out documents.

**Solution:** Device B subscribes broadly without priority filters, stores all documents, and can relay everything to Device C. Each device filters locally in observers/queries for UI display only.

**Code Example**:

```dart
// ❌ BAD: Narrow subscription filter breaks multi-hop relay
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE priority = :priority',
  arguments: {'priority': 'high'},
);
// Problem: This device won't store/relay low-priority orders to other peers

// ✅ GOOD: Broad subscription + local filter in observer
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // No priority filter - enables relay
);

final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE priority = :priority',  // Filter here for UI
  onChange: (result, signalNext) {
    updateUI(result.items);  // Only high-priority orders displayed
    signalNext();
  },
  arguments: {'priority': 'high'},
);
```

### ☐ Avoid subscribing to data you don't need

**What this means:** Scope subscriptions to relevant collections and use appropriate WHERE filters to limit data to what your feature actually needs. Avoid subscribing to entire collections without any filtering when only a subset is required.

**Why this matters:** Every subscription tells Ditto to sync and store matching documents locally. Overly broad subscriptions cause:
1. **Storage bloat**: Unnecessary documents consume device storage
2. **Network waste**: Syncing documents you'll never use consumes bandwidth and battery
3. **Memory pressure**: Larger local datasets increase memory usage during queries
4. **Performance degradation**: More documents to scan during queries, even if filtered in observers

**Balance with multi-hop relay:** While you should avoid unnecessary data, remember that subscriptions too narrow can break multi-hop relay (see "Subscribe broadly, filter in observers"). The goal is to subscribe to data that's relevant to your feature or needed for relay, not everything in the database.

**Examples of appropriate scoping:**
- ✅ Subscribe to orders for a specific customer: `WHERE customerId = :id`
- ✅ Subscribe to recent data: `WHERE createdAt > :cutoff`
- ✅ Subscribe to data in relevant states: `WHERE status IN ('pending', 'active', 'completed')`
- ❌ Subscribe to all orders across all customers when you only display one customer's data
- ❌ Subscribe to historical data (>1 year old) when your feature only shows recent activity

**Code Example**:

```dart
// ❌ BAD: Overly broad subscription when feature only displays current user's data
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // Syncs ALL orders from ALL users!
);

// ✅ GOOD: Scoped to relevant customer
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',
  arguments: {'customerId': currentUserId},
);
// Only syncs orders for this customer
```

### ☐ Cancel observers and subscriptions when no longer needed

**What this means:** Store references to observers and subscriptions, then call `.cancel()` when the feature is closed or the widget is disposed.

**Why this matters:** Observers and subscriptions continue running until explicitly canceled. Failing to cancel them causes:

1. **Memory leaks**: Observers hold references to callbacks, preventing garbage collection
2. **Wasted resources**: Continued processing of database changes and network updates for features no longer in use
3. **Unnecessary network traffic**: Active subscriptions keep telling peers to send updates

**When to cancel:**
- When a screen/feature is permanently closed
- When a widget is disposed (Flutter: in `dispose()` method)
- Before EVICT operations (prevents resync loops)
- During app termination

**When NOT to cancel:**
- During temporary navigation (if returning soon)
- When app goes to background (if feature remains relevant)

**Code Example**:

```dart
// ❌ BAD: No references saved, cannot cancel - memory leak
class OrdersScreen extends StatefulWidget {
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    ditto.sync.registerSubscription('SELECT * FROM orders');
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) { /* ... */ signalNext(); },
    );
  }
}

// ✅ GOOD: Save references and cancel in dispose()
class _OrdersScreenState extends State<OrdersScreen> {
  Subscription? _subscription;
  StoreObserver? _observer;

  @override
  void initState() {
    super.initState();
    _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) { /* ... */ signalNext(); },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
```

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

**What this means:** Wrap observer callbacks in try-catch blocks to handle unexpected errors (e.g., JSON deserialization failures, type mismatches, malformed data).

**Why this matters:** Unhandled observer errors can crash the app or leave UI in inconsistent state. Graceful error handling ensures app stability and prevents one malformed document from breaking the entire observer.

### ☐ Avoid heavy computation in observer callbacks

**What this means:** Keep observer callbacks lightweight. Offload heavy computation (data transformation, business logic) to background isolates or threads.

**Why this matters:** Observer callbacks block the UI thread. Heavy computation causes frame drops and unresponsive UI. Offloading ensures smooth user experience.

**Examples of heavy computation to avoid in observer callbacks:**
- Large JSON serialization/deserialization operations (e.g., `jsonEncode()` on hundreds of documents)
- Complex data transformations or aggregations across many documents
- Image processing or compression
- Network requests or file I/O operations
- Cryptographic operations (hashing, encryption)
- Sorting or filtering large datasets in memory
- Nested iterations over large collections

Instead, extract raw data from `item.value` immediately and offload processing to background isolates (Flutter: `compute()`) or worker threads.

---

## Section 7: Performance Optimization

### ☐ Use CREATE INDEX for selective queries [SDK 4.12+]

**What this means:** Create indexes on fields frequently used in WHERE clauses for queries that return a small subset of documents (high selectivity). Use `CREATE INDEX IF NOT EXISTS idx_name ON collection (field)`.

**Why this matters:** Indexes can improve query performance by up to 90% for selective queries (those returning <10% of collection). Without indexes, Ditto performs full collection scans. However, indexes have overhead for writes and storage, so only index fields used in selective queries.

**When to use indexes based on collection size:**
- **Small collections (<100 documents)**: Indexes usually not necessary—full scans are fast enough
- **Medium collections (100-1,000 documents)**: Consider indexes for frequently queried fields with high selectivity (<10% match rate)
- **Large collections (>1,000 documents)**: Indexes strongly recommended for selective queries—performance gains become significant
- **Very large collections (>10,000 documents)**: Indexes essential for acceptable query performance on selective queries

**Key principle:** Index effectiveness depends on both collection size AND query selectivity. A query returning 5% of documents benefits greatly from indexes in a 10,000-document collection (~9,500 documents skipped), but gains little in a 100-document collection (~95 documents skipped, minimal overhead difference).

### ☐ Use EXPLAIN to verify index usage [SDK 4.12+]

**What this means:** Prefix queries with `EXPLAIN` to see the execution plan and confirm indexes are used: `EXPLAIN SELECT * FROM orders WHERE status = 'pending'`.

**Why this matters:** EXPLAIN reveals whether indexes are used, scan counts, and performance bottlenecks. Helps validate that indexes are correctly applied.

### ☐ Avoid N+1 query patterns (multiple individual lookups)

**What this means:** Instead of querying for each related document individually in a loop (N queries), fetch all related documents in a single query using `WHERE _id IN (...)`.

**Why this matters:** N+1 patterns multiply query overhead. For example, fetching 100 related documents individually requires 100 queries vs 1 batch query. Batch queries reduce execution time and improve performance significantly.

---

## Section 8: Transactions

### ☐ Batch multiple operations in transactions

**What this means:** Use `ditto.store.transaction()` to batch multiple INSERT/UPDATE/DELETE operations into a single atomic transaction.

**Why this matters:** Without transactions, partial failures leave data in inconsistent state. If one operation succeeds but another fails, your data can become corrupted. Transactions ensure all operations succeed together or all fail together (atomicity), maintaining data integrity.

**Code Example**:

```dart
// ❌ BAD: Multiple separate operations without atomicity
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {'order': {'_id': 'o1', 'customerId': 'c1', 'total': 100}},
);
await ditto.store.execute(
  'UPDATE customers APPLY orderCount PN_INCREMENT BY 1.0 WHERE _id = :id',
  arguments: {'id': 'c1'},
);
// Problem: If second operation fails, order exists but customer count is wrong

// ✅ GOOD: Atomic transaction ensures all-or-nothing execution
await ditto.store.transaction(hint: 'create-order', (tx) async {
  await tx.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {'order': {'_id': 'o1', 'customerId': 'c1', 'total': 100}},
  );
  await tx.execute(
    'UPDATE customers APPLY orderCount PN_INCREMENT BY 1.0 WHERE _id = :id',
    arguments: {'id': 'c1'},
  );
});
// Benefit: Both operations succeed together or both fail, ensuring data consistency
```

### ☐ Use read-only transactions for consistent multi-query reads

**What this means:** When reading related data across multiple queries, use `ditto.store.transaction()` with `isReadOnly: true` to ensure all queries see a consistent snapshot.

**Why this matters:** Without transactions, data can change between queries, causing inconsistent reads. For example, if you first query for document IDs that match certain criteria, and then query for the details of each document, another peer might update or delete those documents in between your queries. This causes race conditions where your second query might return different data than what the first query suggested, leading to null references or inconsistent UI states.

Read-only transactions provide snapshot isolation: all queries within the transaction see the database state as it was at the moment the transaction started, ensuring consistency across multiple reads.

**Code Example**:

```dart
final results = await ditto.store.transaction(
  (tx) async {
    // First, get all order IDs for a specific customer
    final orderIds = (await tx.execute(
      'SELECT _id FROM orders WHERE customerId = :customerId',
      arguments: {'customerId': 'c1'},
    )).items.map((item) => item.value['_id'] as String).toList();

    // Then, fetch full details for each order
    // Guaranteed to see the same data state as the first query
    final orderDetails = await tx.execute(
      'SELECT * FROM orders WHERE _id IN :ids',
      arguments: {'ids': orderIds},
    );

    return orderDetails.items;
  },
  isReadOnly: true,
  hint: 'fetch-orders',
);
```

### ☐ Never nest read-write transactions (causes deadlock)

**What this means:** Don't call `ditto.store.transaction()` inside another read-write transaction. Nested read-only transactions are safe, but nested writes cause permanent deadlocks.

**Why this matters:** Nested read-write transactions create a deadlock where the inner transaction waits for the outer to complete, while the outer waits for the inner. The app freezes permanently and requires force-quit. This is a critical error that developers must avoid.

**Platform note:** Flutter SDK v4.11+ supports transactions but does not have this nesting limitation check. Non-Flutter platforms have this limitation.

**Code Example**:

```dart
// ❌ BAD: Nested read-write transaction causes permanent deadlock
await ditto.store.transaction((tx) async {
  await tx.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {'order': {'_id': 'o1', 'total': 100}},
  );

  // DEADLOCK: Inner transaction waits for outer, outer waits for inner
  await ditto.store.transaction((innerTx) async {
    await innerTx.execute(
      'UPDATE customers APPLY orderCount PN_INCREMENT BY 1.0 WHERE _id = :id',
      arguments: {'id': 'c1'},
    );
  });
});
// Result: App freezes permanently, requires force-quit
```

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

**What this means:** Write tests that simulate realistic offline scenarios:
1. Create, update, and delete data while `ditto.startSync()` is not called or network is disabled
2. Simulate multiple devices making concurrent changes while disconnected from each other
3. Verify data syncs correctly after reconnection with no data loss
4. Test that business logic invariants hold after conflict resolution

**Why this matters:** Offline-first is Ditto's core value proposition. Apps must work seamlessly while disconnected and sync correctly when connectivity returns. Multiple devices can modify the same data independently while offline, and changes must merge intelligently upon reconnection. Testing offline scenarios catches critical issues:
- Missing subscriptions that prevent data from syncing after reconnection
- Improper error handling during sync initialization
- Data loss or corruption during merge operations
- Business rule violations after conflict resolution (e.g., inventory going negative, duplicate order numbers)
- UI inconsistencies when offline changes sync to other devices

**Testing approach:**
- Test **your application's business logic** with realistic concurrent scenarios using your actual domain models
- Verify **business rules** hold after conflict resolution (e.g., "inventory never negative", "order numbers unique")
- Focus on **your data model**, not just SDK API behavior—the SDK itself is already tested

**Example test scenarios:**
- **Concurrent sales**: Two offline POS terminals sell the same product. After sync, verify inventory doesn't go negative.
- **Unique identifiers**: Two devices create orders while disconnected. After sync, verify all order numbers are unique.
- **Deletion scenarios**: Device A deletes an order while Device B updates it offline. After sync, verify the final state matches your business rules (husked document handling, logical deletion filtering).
- **Subscription lifecycle**: Create data offline, then start sync. Verify subscriptions properly request the data and observers trigger with new documents.

### ☐ Test multi-device conflict scenarios

**What this means:** Write tests that simulate concurrent modifications to the same document from multiple offline devices, then verify CRDT merge behavior after sync:
1. Create two or more test Ditto instances representing different devices
2. Disconnect them from each other (or don't call `startSync()`)
3. Have each device make conflicting updates to the same document
4. Sync the devices together and verify the merged result matches CRDT semantics

**Why this matters:** Ditto uses CRDTs (Conflict-free Replicated Data Types) for automatic conflict resolution, and different CRDT types have different merge behaviors:
- **MAP fields (objects)**: Use "add-wins" semantics—concurrent updates to different keys both persist
- **REGISTER fields (scalars, arrays)**: Use "last-write-wins" (LWW) based on Hybrid Logical Clock—one update wins, the other is discarded
- **COUNTER fields**: Use commutative addition—all increments from all devices are summed

Without testing, you won't know if your data model handles conflicts correctly. For example, if you use arrays for mutable data that multiple devices modify concurrently, the last-write-wins behavior will cause data loss. Tests validate that your data model design is conflict-safe.

**What to test:**
- **MAP field conflicts**: Device A updates `field1`, Device B updates `field2` → both updates should persist after merge
- **REGISTER field conflicts**: Device A sets `status = "shipped"`, Device B sets `status = "delivered"` → only one value wins (verify which one using HLC/timestamp)
- **Array conflicts**: Device A appends `[item3]`, Device B appends `[item4]` → last-write-wins, one array is lost (this demonstrates why arrays are problematic)
- **COUNTER conflicts**: Device A increments by 5, Device B increments by 3 → final value should be +8 (commutative addition)
- **Mixed conflicts**: Device A updates MAP field while Device B updates REGISTER field → both changes should persist (different CRDT types)

**Testing pattern:**
- Use multiple Ditto instances in tests (each represents a device)
- Simulate offline period by not syncing between instances
- Make concurrent modifications to the same document
- Manually trigger sync (or call sync methods) to merge changes
- Assert final state matches expected CRDT behavior

**Example scenarios:**
- **Inventory counter**: Two POS terminals concurrently decrement inventory. After sync, verify the total decrement is correct (not lost due to LWW).
- **Order modifications**: Device A updates `shippingAddress`, Device B updates `paymentMethod`. After sync, verify both fields are updated (MAP add-wins).
- **Status race condition**: Two devices concurrently update order status. After sync, verify the final status follows HLC ordering (last-write-wins for REGISTER).
- **Array append collision**: Two devices append items to an array field. After sync, verify you understand which array won (demonstrates why MAP is safer for concurrent modifications).

### ☐ Test deletion patterns (Soft-Delete and DELETE)

**What to test:**

1. **Soft-Delete pattern**:
   - Documents with `isDeleted: true` filter correctly in observers/queries
   - Broad subscriptions (no filter) ensure multi-hop relay
   - EVICT removes local documents without resync loops
   - Resync occurs correctly after subscription recreation

2. **DELETE pattern**:
   - DELETE queries create tombstones that propagate to all peers
   - Tombstone TTL (30-day default) works correctly
   - Zombie resurrection (re-INSERT after DELETE) behaves as expected
   - Husked documents (concurrent DELETE + UPDATE) are handled

**Why this matters:** Deletion bugs cause ghost records in UI, data inconsistencies across devices, and sync failures. See [Section 4: Deletion & Storage Lifecycle](#section-4-deletion--storage-lifecycle) for implementation patterns.

### ☐ Test application-specific business logic, not SDK behavior

**What this means:** Write tests that verify **your application's business logic and data model** under concurrent scenarios using your actual domain models (e.g., inventory management, order creation, data validation rules). Don't test basic SDK behavior (e.g., "data I inserted can be queried")—the SDK itself is already tested.

**Why this matters:** Tests that only verify SDK behavior (e.g., "INSERT then SELECT returns the document") provide no value—the SDK is already tested. What matters is testing how **your specific business logic** behaves under offline-first and concurrent scenarios. Focus on **your application's invariants** (e.g., "inventory never negative", "order numbers unique", "deleted items don't reappear").

### ☐ Test timestamp precision and clock drift tolerance

**What this means:** Write tests that simulate devices with mismatched clocks (e.g., Device A is 5 seconds ahead, Device B is 3 seconds behind). Verify that timestamp-based logic handles clock drift gracefully with appropriate tolerance ranges.

**Why this matters:** Device clocks are never perfectly synchronized. iOS typically has ~100ms drift, while Android can drift by several seconds. Timestamp-based validation (e.g., `createdAt < updatedAt`) can fail due to clock skew. Tests ensure your logic tolerates reasonable clock drift.
