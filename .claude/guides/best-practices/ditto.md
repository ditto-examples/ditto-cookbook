# Ditto SDK Best Practices

This document provides comprehensive best practices and anti-patterns for Ditto SDK integration, focused on offline-first architecture and distributed data synchronization.

## Understanding Ditto

### What is Ditto?

Ditto is an **offline-first local database SDK** with built-in **P2P mesh networking capabilities**:

- **Local Database**: Schema-less document database that works without internet
- **P2P Mesh Network**: Synchronizes via Bluetooth, P2P Wi-Fi (AWDL/Wi-Fi Aware), and LAN using multiple transports
- **Cloud Sync**: Syncs with Ditto Server (cloud) when internet is available
- **Distributed Architecture**: Designed as a distributed database using CRDTs (Conflict-free Replicated Data Types)

**Architecture:**
- **Edge Peers (Small Peers)**: Devices running Ditto SDK (mobile devices, IoT devices, edge devices)
- **Ditto Cloud/Server**: Optional cloud cluster providing cloud sync, identity management, and monitoring

### Key Characteristics

**Offline-First Operation:**
- Apps continue to function without connectivity
- Database remains fully readable and writable offline
- Data automatically merges when devices reconnect

**Distributed Synchronization:**
- No central server required for basic operation
- Each peer operates independently (a device can run multiple peers via multiple apps or instances)
- Peers subscribe to and share data when in proximity or connected
- Uses multiple transports: Bluetooth LE (L2CAP/GATT), P2P Wi-Fi (AWDL/Wi-Fi Aware), LAN, and WebSockets

**Conflict Resolution:**
- Built-in CRDT implementation handles conflicts automatically
- Data from disconnected devices merges intelligently upon reconnection
- Uses Hybrid Logical Clocks (HLC) to track mutation timestamps
- Each peer has a unique Actor identifier (SiteID + Epoch) to track mutation sources

---

## Critical Design Principle

**⚠️ MOST IMPORTANT: Design for Distributed Data Merge**

When designing data models and app specifications, always consider:
- Multiple devices will modify the same data while disconnected
- Changes will merge when devices reconnect
- Your data structure must support safe merging without data loss

**✅ DO:**
- Design data models that merge well (append-only, increment counters, etc.)
- Use field-level updates rather than document replacement
- Consider how concurrent edits should be resolved

**❌ DON'T:**
- Design data models that assume single-writer scenarios
- Replace entire documents when only updating specific fields
- Ignore the distributed nature of Ditto

**Why**: Ditto's CRDT implementation ensures eventual consistency, but your data model determines whether merges produce the intended result.

---

## API Version Awareness (CRITICAL)

**⚠️ MOST IMPORTANT: Always Use Current Ditto API**

Ditto has evolved significantly, and using outdated APIs will cause implementation failures:

**Current API (v4.x+): DQL String-Based Queries**
- All operations use `ditto.store.execute(query, args)` with SQL-like DQL strings
- Subscriptions: `ditto.sync.registerSubscription(query)`
- Observers: `ditto.store.registerObserverWithSignalNext(query, callback, args)`

**Legacy API (DEPRECATED - Applicable to non-Flutter SDKs only):**
- Builder methods: `.collection()`, `.find()`, `.findById()`, `.update()`, `.upsert()`, `.remove()`, `.exec()`
- **Flutter SDK users**: This legacy API was never provided in Flutter SDK, so no concern
- **Other SDK users** (JavaScript, Swift, Kotlin, etc.): These methods are **fully deprecated in SDK 4.12+** and will be removed in SDK v5

**✅ DO:**
- Reference official Ditto documentation before writing code
- Use DQL string queries exclusively
- Check SDK version to understand available features

```dart
// ✅ CURRENT API: DQL string queries (all SDKs including Flutter)
await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
```

**❌ DON'T (non-Flutter SDKs only):**
- Use builder API methods (legacy, **fully deprecated in SDK 4.12+, will be removed in SDK v5**)
- Assume API patterns from older documentation

```dart
// ❌ LEGACY API (DEPRECATED - REMOVED IN SDK v5): Builder methods
// Note: Flutter SDK never had this API
final orders = await ditto.store
  .collection('orders')
  .find("status == 'active'")
  .exec();
// This API is fully deprecated as of SDK 4.12 and will be removed in v5
// Migration to DQL required before upgrading to SDK v5
```

---

## Ditto Query Language (DQL)

### Overview

Ditto uses **DQL (Ditto Query Language)**, a SQL-like query language with important differences:

**Characteristics:**
- SQL-like string syntax for familiarity
- Schema-less (no rigid table definitions)
- Document-oriented (JSON-like structure)
- All operations use `ditto.store.execute()` with DQL strings

**Important Limitations:**
- **No JOIN operations** (current Ditto versions do not support JOIN)
- Normalized (split) collections require multiple queries
- Complex cross-collection operations can impact performance

### Query Best Practices

**✅ DO:**
- Use denormalized data structures for related data that needs to be queried together
- Keep related data together in single documents to avoid multiple queries
- Separate independent data into different collections for parallel synchronization efficiency
- Limit query complexity for performance
- Use DQL string queries with parameterized arguments

```dart
// ✅ GOOD: Denormalized structure (single query)
{
  "_id": "order_123",
  "items": [
    { "productId": "p1", "name": "Widget", "price": 10.00 },
    { "productId": "p2", "name": "Gadget", "price": 20.00 }
  ],
  "total": 30.00
}

// Query with DQL string
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
final orders = result.items.map((item) => item.value).toList();
```

**❌ DON'T:**
- Split related data that needs to be queried together into separate collections
- Over-normalize data without considering the performance cost of multiple serial queries
- Assume SQL patterns work identically in DQL
- Use legacy builder API methods (non-Flutter SDKs only; Flutter SDK never had this API)

```dart
// ❌ BAD: Normalized structure requiring multiple queries (no JOIN)
// Collection: orders
{ "_id": "order_123", "itemIds": ["item_1", "item_2"] }

// Collection: orderItems
{ "_id": "item_1", "productId": "p1", "quantity": 2 }
{ "_id": "item_2", "productId": "p2", "quantity": 1 }

// Requires multiple queries and manual joining in code
final orderResult = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :id',
  arguments: {'id': 'order_123'},
);
final order = orderResult.items.first.value;

final itemResults = await Future.wait(
  (order['itemIds'] as List).map((id) =>
    ditto.store.execute(
      'SELECT * FROM orderItems WHERE _id = :id',
      arguments: {'id': id},
    ),
  ),
);
final items = itemResults.map((r) => r.items.first.value).toList();
```

**Why**: Without JOIN support (current Ditto versions), splitting related data into multiple collections requires multiple serial queries and complex application-level merging, severely impacting performance. However, independent data (e.g., users vs. products, current state vs. historical events) benefits from being in separate collections as they can synchronize in parallel. DQL has Ditto-specific behaviors that differ from standard SQL.

---

### Query Result Handling

**⚠️ CRITICAL: Treat QueryResults as Database Cursors**

Query results and QueryResultItems should be treated like database cursors that manage memory carefully. They use lazy-loading for memory efficiency: items materialize into memory only when accessed.

**How It Works:**
- `result.items` returns a collection of QueryResultItem objects
- `item.value` accesses the materialized item data (loads into memory)
- `item.isMaterialized` checks if data is currently in memory
- `item.materialize()` / `item.dematerialize()` provide explicit memory control

**✅ DO:**
- Extract needed data immediately from query results
- Convert to your model objects right away
- Dematerialize items after extracting data
- Store only identifiers (not live references) between observer callbacks

```dart
// ✅ GOOD: Extract data immediately and dematerialize
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

// Extract to model objects immediately
final orders = result.items.map((item) {
  final data = item.value; // Materialize
  return Order.fromJson(data); // Convert to model
}).toList();

// QueryResultItems are automatically cleaned up when result goes out of scope
```

**✅ GOOD: Proper observer pattern with data extraction**

```dart
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM products WHERE category = :category',
  onChange: (result, signalNext) {
    // Extract data immediately - don't retain QueryResultItems
    final products = result.items.map((item) {
      return Product.fromJson(item.value);
    }).toList();

    updateUI(products); // Use extracted data
    signalNext(); // Signal readiness for next update
    // QueryResultItems are cleaned up after this callback
  },
  arguments: {'category': 'electronics'},
);
```

**❌ DON'T:**
- Retain QueryResultItems between observer callbacks
- Store live references to result.items
- Keep QueryResults in memory longer than necessary
- Access item.value multiple times (cache the result instead)

```dart
// ❌ BAD: Retaining QueryResultItems
class ProductsState {
  List<QueryResultItem> items = []; // Don't store QueryResultItems!

  void onQueryResult(QueryResult result) {
    items = result.items.toList(); // Memory leak!
  }
}

// ❌ BAD: Multiple materializations
final result = await ditto.store.execute('SELECT * FROM orders');
for (var item in result.items) {
  print(item.value); // First materialization
  processOrder(item.value); // Second materialization - wasteful!
}
```

**Why**: QueryResultItems are database cursors that hold references to underlying data. Retaining them causes memory bloat and prevents garbage collection. To avoid this, extract your data immediately and let the items be cleaned up automatically.

### Alternative Data Formats

QueryResultItem supports multiple serialization formats:

```dart
final item = result.items.first;
final data = item.value;              // Map<String, dynamic> (default)
final cborBytes = item.cborData();    // Uint8List for network/storage
final jsonString = item.jsonString(); // String for logging/APIs
```

**Note**: CBOR and JSON formats are uncached - each call performs new serialization.

### Diffing Query Results

`DittoDiffer` tracks changes between query emissions—including insertions, deletions, updates, and moves—enabling efficient UI updates. Use this when you need granular change information rather than full dataset reloads. For large datasets, debounce the diffing operation to maintain performance.

**Official Reference**: [Ditto Read Documentation](https://docs.ditto.live/sdk/latest/crud/read)

---

## Document Model and Data Types

### Supported Data Types

Ditto documents support JSON-like data types with CRDT backing:

**Scalar Types:**
- Strings, numbers, booleans
- Dates and timestamps

**Complex Types:**
- Objects (nested documents) - stored as MAP CRDT
- Arrays - see critical warning below
- Attachments (large binary files)

**Important**: Each field value is stored as a specific CRDT type (MAP, REGISTER, etc.) for automatic conflict resolution.

### ⚠️ CRITICAL: Array Limitations

**Arrays have significant limitations in Ditto due to CRDT merge conflicts:**

**❌ DON'T:**
- Use arrays for data that multiple peers may modify concurrently
- Store mutable items in arrays that need to be updated individually

```dart
// ❌ BAD: Array with concurrent updates causes conflicts
{
  "_id": "order_123",
  "items": [
    {"id": "item1", "quantity": 2},  // Multiple peers updating quantity
    {"id": "item2", "quantity": 1}
  ]
}
// When offline peers reconnect, array merge conflicts can occur
```

**Why Arrays Are Problematic:**
When multiple offline peers make concurrent updates to the same array index, Ditto cannot reliably merge changes. This can lead to:
- Lost updates
- Duplicate entries
- Inconsistent array state across peers

**✅ DO:**
- Use MAP (object) structures instead of arrays for mutable data
- Use separate documents (INSERT) for event logs and audit trails
- Embed simple read-only arrays that never change after creation

```dart
// ✅ GOOD: Use MAP (object) for concurrent field-level updates
// With DQL_STRICT_MODE=false (default in 4.11+), objects are treated as MAPs
{
  "_id": "order_123",
  "metadata": {
    "updatedAt": "2025-01-15T10:00:00Z",  // MAP uses "add-wins" strategy
    "updatedBy": "user_456"                // Different fields can be updated independently
  }
  // If Peer A updates "updatedAt" and Peer B updates "updatedBy" concurrently,
  // both changes are preserved after sync (field-level merging)
}

// ✅ GOOD: Use keyed MAP structure instead of arrays for items that need concurrent updates
{
  "_id": "order_123",
  "items": {
    "item1": {"quantity": 2, "productId": "p1"},  // Each key is independently mergeable
    "item2": {"quantity": 1, "productId": "p2"}   // Avoids last-write-wins conflicts
  }
}

// ⚠️ ARRAYS ARE REGISTERS (Last-Write-Wins)
// Scalars and arrays are treated as registers when DQL_STRICT_MODE=false
// Arrays use "last-write-wins" - the entire array is atomically replaced

// ⚠️ CAUTION: Small read-only array (acceptable if never modified after creation)
{
  "_id": "order_123",
  "statusHistory": [
    {"status": "created", "timestamp": "2025-01-15T10:00:00Z"},
    {"status": "shipped", "timestamp": "2025-01-16T14:30:00Z"}
  ]  // If this array is modified concurrently by multiple peers, last-write-wins
  // Better approach: use separate documents for event history (see Event History section)
}

// ✅ GOOD: Static read-only array
{
  "_id": "product_456",
  "tags": ["electronics", "gadget", "bestseller"]  // Never modified after creation
}

// ❌ BAD: Array for concurrent updates (last-write-wins causes data loss)
{
  "_id": "cart_789",
  "items": [
    {"productId": "p1", "quantity": 2},
    {"productId": "p2", "quantity": 1}
  ]  // If Peer A adds item and Peer B removes item concurrently, one change is lost
}
```

**Why MAP is Better:**
MAP (object) CRDT types use "add-wins" strategy, automatically merging concurrent updates to different keys without conflicts.

### Document Structure Best Practices

**Document Identity:**
- Every document must have a unique `_id` field (primary key)
- Ditto auto-generates `_id` if omitted
- `_id` cannot be changed after creation
- Supports composite keys (objects as `_id` values) for complex hierarchies

```dart
// ✅ GOOD: Composite key for multi-dimensional organization
{
  "_id": {
    "storeId": "store_001",
    "orderId": "order_123"
  },
  "total": 45.50
}
```

**Field Naming:**
- Only strings allowed for field names
- Use consistent naming conventions

**CRDT Type Behaviors:**
- **REGISTER**: Last-write-wins for scalar values
- **MAP**: Add-wins for object properties (concurrent updates merge)
- **Attachments**: Must be explicitly fetched (not auto-synced)

**Nested Field Updates:**
To update nested fields in a REGISTER (scalar/object field), you must replace the entire object. Use field-level UPDATE statements when possible.

---

### Exclude Unnecessary Fields from Documents

**⚠️ CRITICAL**: Every field in a document syncs across the mesh. Including unnecessary fields degrades performance for all peers.

#### Fields That Should NOT Be in Documents

**1. UI-Only State**

```dart
// ❌ BAD: UI state in synced document
{
  "_id": "order_123",
  "status": "active",
  "isExpanded": true,        // UI state - don't sync!
  "selectedForBatch": false, // UI state - don't sync!
  "scrollPosition": 234      // UI state - don't sync!
}

// ✅ GOOD: UI state in local component state
final order = result.items.first.value; // Only sync-worthy data
final isExpanded = useState(false);     // UI-only state
```

**2. Computed/Derived Values**

```dart
// ❌ BAD: Computed values in document
{
  "_id": "order_123",
  "items": [
    {"price": 10.0, "quantity": 2},
    {"price": 15.0, "quantity": 1}
  ],
  "subtotal": 35.0,  // Derived from items - don't sync!
  "tax": 3.5,        // Derived - don't sync!
  "total": 38.5      // Derived - don't sync!
}

// ✅ GOOD: Compute on read
{
  "_id": "order_123",
  "items": [
    {"price": 10.0, "quantity": 2},
    {"price": 15.0, "quantity": 1}
  ]
}
// Calculate totals in UI layer
final subtotal = items.fold(0.0, (sum, item) => sum + item.price * item.quantity);
```

**3. Temporary Processing State**

```dart
// ❌ BAD: Processing state in document
{
  "_id": "photo_123",
  "imageAttachment": attachmentToken,
  "uploadProgress": 0.75,      // Temporary - don't sync!
  "isProcessing": true,        // Temporary - don't sync!
  "processingStartedAt": "..." // Temporary - don't sync!
}

// ✅ GOOD: Processing state in local memory
final photo = result.items.first.value;
final uploadProgress = useState(0.0); // Local state only
```

**4. Device-Specific Data**

```dart
// ❌ BAD: Device-specific paths in document
{
  "_id": "file_123",
  "localCachePath": "/var/mobile/...", // Device-specific - don't sync!
  "downloadedOn": "Device A"           // Device-specific - don't sync!
}

// ✅ GOOD: Store only universal identifiers
{
  "_id": "file_123",
  "attachmentToken": token // Universal reference
}
// Manage local cache paths per-device
```

#### Performance Impact

**Sync Overhead Example**:

```dart
// ❌ BAD: 500 bytes per document (80% waste)
{
  "_id": "task_001",
  "title": "Buy groceries",        // 20 bytes - needed
  "done": false,                   // 10 bytes - needed
  // ... 470 bytes of unnecessary UI state, computed values, temp data
}

// ✅ GOOD: 30 bytes per document
{
  "_id": "task_001",
  "title": "Buy groceries",  // 20 bytes
  "done": false              // 10 bytes
}

// Impact with 1000 tasks across 10 devices:
// Bad:  500 KB × 10 = 5 MB sync traffic
// Good:  30 KB × 10 = 300 KB sync traffic
// Savings: 94% less bandwidth, storage, and processing
```

#### Best Practices

**✅ DO:**
- Only include fields that need to be shared across devices
- Store UI state in component/widget state
- Compute derived values on read
- Use local device storage for device-specific data
- Review document schemas regularly for bloat

**❌ DON'T:**
- Include UI state (expanded, selected, hovered, focused)
- Include computed/derived values (totals, counts, aggregates)
- Include temporary processing state (progress, loading flags)
- Include device-specific paths or identifiers
- Include debug/development fields in production

**Why**: Every unnecessary field multiplies bandwidth × devices × sync frequency. A 500-byte field in 1000 documents syncing to 10 devices = 5 MB of wasted traffic per sync cycle. Mesh performance degrades as unnecessary data floods the network.

---

### DQL Strict Mode (v4.11+)

**What is Strict Mode:**
DQL Strict Mode enforces structure and CRDT type safety in collections. It determines how nested objects are treated during synchronization.

**Default Behavior (Strict Mode = true):**
- All fields are treated as REGISTER by default
- Nested objects default to REGISTER (whole-object replacement on update)
- Requires explicit collection definitions for MAP CRDT types
- Provides predictable behavior and type safety

**Configuration:**
```dart
// Disable strict mode (must be done BEFORE startSync)
await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
await ditto.startSync();
```

**⚠️ CRITICAL: Always await ALTER SYSTEM SET**
`store.execute()` is async, and proceeding without awaiting can cause unexpected behavior:
- System settings may not be applied before subsequent operations
- Starting sync before settings are applied can lead to inconsistent behavior
- **Always use `await`** before calling `startSync()` or other store operations

```dart
// ✅ CORRECT: await ensures settings are applied before sync starts
await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
await ditto.startSync();

// ❌ WRONG: Settings might not be applied when startSync runs
ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false'); // Missing await!
await ditto.startSync(); // May start with wrong settings
```

**⚠️ CRITICAL: Cross-Peer Consistency**
**All peers must use the same DQL_STRICT_MODE setting.** When peers have different settings:
- Data will sync between peers successfully
- However, behavior changes unpredictably
- Nested field updates may appear missing if strict mode peers lack explicit MAP definitions

**Strict Mode Disabled (false):**
- Automatic CRDT type inference based on document shape
- Objects automatically treated as MAPs (field-level merging)
- Useful for dynamic key-value data without predefined schemas

**Example: Updating Nested Fields with Strict Mode Disabled**
```dart
// With strict mode disabled, nested fields can be updated individually
await ditto.store.execute(
  '''UPDATE orders
     SET metadata.updatedAt = :date,
         metadata.updatedBy = :userId
     WHERE _id = :id''',
  arguments: {
    'date': DateTime.now().toIso8601String(),
    'userId': currentUserId,
    'id': orderId,
  },
);

// Delete nested field
await ditto.store.execute(
  'UPDATE orders UNSET items.abc WHERE _id = :id',
  arguments: {'id': orderId},
);
```

**Recommendation:**
- Keep strict mode enabled (default) for production environments
- Use explicit collection definitions when you need MAP behavior
- Only disable strict mode if you need legacy compatibility or fully dynamic schemas
- **Never mix strict mode settings across peers in production**

### Document Size and Performance Guidelines

**Size Limits:**
- **Hard limit**: Documents exceeding 5 MB will not sync with peers
- **Warning threshold**: Documents over 250 KB trigger console warnings
- **Performance impact**: On Bluetooth LE, replication maxes at ~20 KB/second
  - A 250 KB document takes 10+ seconds for initial sync
  - Larger documents cause significant delays on mobile/IoT devices

**✅ DO:**
- Keep documents under 250 KB for optimal performance
- **Balance embed vs flat based on access patterns** (see Relationship Modeling section)
- Embed related data when retrieved together (avoids sequential queries due to no JOIN support)
- Use flat models for data that grows unbounded or is accessed independently
- Store large binary files (>250 KB) using ATTACHMENT data type

```dart
// ✅ GOOD: Embedded when data is retrieved together
{
  "_id": "order_123",
  "customerId": "cust_456",
  "items": [  // Embed items - avoids sequential queries
    {"productId": "prod_1", "quantity": 2, "price": 10.00},
    {"productId": "prod_2", "quantity": 1, "price": 25.00}
  ],
  "total": 45.00
}

// ✅ GOOD: Flat when data is accessed independently
// people collection
{
  "_id": "person_123",
  "name": "Alice",
  "email": "alice@example.com"
}

// cars collection (accessed independently from people)
{
  "_id": "car_456",
  "ownerId": "person_123",  // Foreign key reference
  "make": "Toyota",
  "model": "Camry"
}
```

**❌ DON'T:**
- Embed data that grows unbounded (exceeds size limits)
- Use deeply nested maps (3+ levels) without good reason
- Store large binary data directly in documents (use ATTACHMENT type)

```dart
// ❌ BAD: Unbounded growth in embedded structure
{
  "_id": "person_123",
  "name": "Alice",
  "cars": [
    {
      "make": "Toyota",
      "model": "Camry",
      "maintenance": [  // Can grow to hundreds of entries!
        {"date": "2025-01-15", "type": "oil_change", "cost": 45.00},
        {"date": "2025-02-20", "type": "tire_rotation", "cost": 35.00},
        // ... hundreds more entries - document becomes too large!
      ],
      "photos": ["base64_encoded_large_image..."]  // Large binary data!
    }
  ]
}
// Problems: Too large, slow to sync, difficult to update concurrently
// Solution: Use separate maintenance_logs collection with foreign key
```

**Key Considerations:**
- **Embed benefits**: Single-query access (important with no JOIN support), simpler code
- **Flat benefits**: Independent sync, concurrent edits without conflicts, parallel sync efficiency
- **Choose based on**: Access patterns, growth potential, document size limits, concurrent edit likelihood

### Relationship Modeling: Embedded vs Flat

**⚠️ CRITICAL: No JOIN Support**
Ditto does not currently support JOIN operations. This has major implications for data modeling:
- **Foreign key references require sequential queries** (fetch order → fetch items), causing significant performance overhead
- **Embedded data enables single-query access**, which is much faster when data needs to be retrieved together
- Choose your model based on access patterns and whether data needs to be retrieved together

**When to Embed (nested objects):**
- **Data retrieved/updated together as a unit** (MOST IMPORTANT: avoids sequential queries)
- Related data that logically belongs together (order items, shipping address, etc.)
- Relatively stable relationship that doesn't grow unbounded
- Small to medium size (under 250 KB combined)
- Low likelihood of concurrent edits while offline

```dart
// ✅ GOOD: Embedded data retrieved together (single query)
{
  "_id": "order_123",
  "customerId": "cust_456",
  "shippingAddress": {  // Retrieved with order, no extra query
    "street": "123 Main St",
    "city": "Springfield",
    "zip": "12345"
  },
  "items": [  // Order items retrieved with order
    {"productId": "prod_1", "quantity": 2, "price": 10.00},
    {"productId": "prod_2", "quantity": 1, "price": 25.00}
  ],
  "total": 45.00
}
```

**When to Use Flat Models (foreign keys):**
- **Data accessed independently** (items rarely need parent data)
- Data that grows unbounded over time (can exceed document size limits)
- Frequent concurrent modifications from multiple peers
- **Independent data sets that sync separately** (parallel sync efficiency)

```dart
// ✅ GOOD: Flat model when data is accessed independently
// products collection (accessed independently from orders)
{
  "_id": "prod_789",
  "name": "Widget",
  "price": 19.99,
  "inventory": 100
}

// orders collection (only references product ID)
{
  "_id": "order_123",
  "customerId": "cust_456",
  "items": [
    {"productId": "prod_789", "quantity": 2}  // Foreign key reference
  ],
  "total": 39.98
}

// ⚠️ WARNING: To display product details with order, you need sequential queries:
// 1. Query order
// 2. Extract productId
// 3. Query product by productId
// This is slower than embedding but necessary when products change frequently
```

**Performance Trade-offs:**
- **Embedded**:
  - ✅ **Much faster when data is retrieved together** (single query vs sequential queries)
  - ✅ Simpler data access (no manual joining)
  - ❌ Potential size limits if data grows unbounded
  - ❌ Concurrent edit conflicts if multiple peers modify same document
- **Flat (foreign keys)**:
  - ✅ Better for accessing isolated portions independently
  - ✅ Parallel sync efficiency for independent data sets
  - ✅ Concurrent updates without conflicts
  - ❌ **Significant performance overhead** when data needs to be retrieved together (sequential queries)
  - ❌ Manual joining required in application code

**Decision Guide:**
1. **Will this data always be retrieved together?** → Embed (avoids sequential query overhead)
2. **Will this data grow unbounded?** → Use flat (avoids document size limits)
3. **Are they truly independent data sets?** → Use flat (parallel sync benefits)
4. **High concurrent edits on same document?** → Use flat (reduces conflicts)

---

## Data Deletion Strategies

### The Deletion Challenge

**⚠️ CRITICAL: Deletion in distributed systems is complex**

In distributed databases like Ditto:
- Deletion is not instantaneous across all devices (no centralized enforcement at the moment of deletion)
- Devices may be offline when deletion occurs
- Deleted data may reappear from previously disconnected devices (zombie data problem)

### DELETE and Tombstones

**What are Tombstones:**
Tombstones are compressed deletion records containing only the document ID and deletion timestamp. They ensure all peers learn about deleted documents.

**How it works:**
- `DELETE` DQL statement marks documents as deleted and creates tombstones
- Tombstones propagate to other peers so they know the document was deleted
- Tombstones have TTL (Time To Live) - default 30 days on Cloud, configurable on Edge SDK
- Documents are eventually evicted after TTL expires
- **CRITICAL LIMITATION**: Tombstones are only shared with devices that have seen the document before deletion

**⚠️ CRITICAL: Tombstone Sharing Limitation**
If a device encounters a document for the first time AFTER its tombstone has been removed, that device will reintroduce the document to the system as if it's new data.

**TTL Configuration:**
- **Cloud**: Deleted documents persist for 30 days before permanent removal (fixed, not configurable)
- **Edge SDK** (configurable):
  - `TOMBSTONE_TTL_ENABLED`: Enable automatic tombstone cleanup (default: false)
  - `TOMBSTONE_TTL_HOURS`: Expiration threshold in hours (default: 168 hours = 7 days)
  - `DAYS_BETWEEN_REAPING`: Reaping frequency (default: 1 day)
- **Critical**: Never set Edge SDK TTL larger than Cloud Server TTL (30 days), or Edge devices may hold tombstones longer than Cloud expects

**Batch Deletion Performance:**
- For batch deletions of 50,000+ documents, use `LIMIT 30000` to avoid performance impact

**✅ DO:**
- Understand tombstone TTL implications
- Document your TTL strategy
- Ensure all devices connect within the TTL window
- Use `LIMIT` for large batch deletions (50,000+ documents)
- Consider data lifecycle in your design

```dart
// ✅ GOOD: Physical deletion with awareness of TTL
final expiryDate = DateTime.now()
    .subtract(const Duration(days: 30))
    .toIso8601String();
await ditto.store.execute(
  'DELETE FROM temporary_data WHERE createdAt < :expiryDate',
  arguments: {'expiryDate': expiryDate},
);

// ✅ GOOD: Batch deletion with LIMIT for performance
await ditto.store.execute(
  'DELETE FROM logs WHERE createdAt < :cutoffDate LIMIT 30000',
  arguments: {'cutoffDate': cutoffDate},
);

// Note: Tombstone TTL must exceed maximum expected offline duration
// Otherwise, data from offline devices may reappear as new documents
```

**❌ DON'T:**
- Use DELETE without understanding tombstone TTL implications
- Delete data that may sync from long-offline devices
- Delete 50,000+ documents at once without LIMIT
- Set Edge SDK TTL larger than Cloud TTL

**Risk**: If a device reconnects after tombstone TTL expires, its data will be treated as new inserts, causing "zombie data" to reappear.

### Logical Deletion

**How it works:**
- Add a deletion flag field to documents (commonly named `isDeleted`, `isArchived`, `deletedFlag`, etc.)
- Filter out deleted documents in queries using the flag
- Periodically evict old deleted documents locally with EVICT

**✅ DO:**
- Implement logical deletion for critical data
- Filter deleted documents consistently in queries and observers
- Periodically clean up with EVICT
- Choose a clear, consistent field name for your deletion flag (e.g., `isDeleted`, `isArchived`)

```dart
// ✅ GOOD: Logical deletion implementation
// Note: Using 'isDeleted' as an example - you can use any field name

// 1. Mark as deleted (not actual deletion)
final deletedAt = DateTime.now().toIso8601String();
await ditto.store.execute(
  'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'deletedAt': deletedAt},
);

// Alternative naming examples:
// 'UPDATE orders SET isArchived = true, archivedAt = :archivedAt ...'
// 'UPDATE orders SET deletedFlag = true, deletedTimestamp = :timestamp ...'

// 2. Filter in queries and observers (use your chosen field name consistently)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE isDeleted != true AND status = :status',
  arguments: {'status': 'active'},
);
final activeOrders = result.items.map((item) => item.value).toList();

// 3. Subscribe with same filter (optional optimization)
// With logical deletion, documents still exist even when isDeleted=true
// Filtering in subscription is SAFE and reduces bandwidth
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted != true',
);

// 4. Observer filters deleted items for UI display
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE isDeleted != true ORDER BY createdAt DESC',
  onChange: (result, signalNext) {
    updateUI(result.items);
    signalNext();
  },
);

// 5. Periodically evict old deleted documents (local cleanup)
// EVICT removes data locally without syncing the removal to other peers
final oldDate = DateTime.now()
    .subtract(const Duration(days: 90))
    .toIso8601String();
await ditto.store.execute(
  'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :oldDate',
  arguments: {'oldDate': oldDate},
);
```

**❌ DON'T:**
- Forget to filter deleted documents in queries
- Use inconsistent field names across your codebase
- Skip EVICT for local cleanup
- Make logical deletion too complex

```dart
// ❌ BAD: Forgetting to filter in some queries
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status', // Missing deletion flag filter!
  arguments: {'status': 'active'},
);
// This will include logically deleted documents!
```

**Trade-offs:**

| Aspect | Logical Deletion | DELETE (with Tombstones) |
|--------|-----------------|--------------------------|
| Safety | ✅ Safer (no zombie data) | ⚠️ Risky (tombstone TTL) |
| Code Complexity | ⚠️ Higher (filter everywhere) | ✅ Lower (automatic) |
| Performance | ⚠️ Slightly slower (larger dataset) | ✅ Faster (smaller dataset) |
| Readability | ⚠️ Requires discipline | ✅ More intuitive |

**Why**: Logical deletion prevents "zombie data" from reappearing but requires consistent filtering across all queries and observers. DELETE with tombstones is simpler but has TTL risks.

---

### The Husked Document Problem

**⚠️ CRITICAL: Concurrent DELETE and UPDATE Conflicts**

When DELETE and UPDATE operations occur concurrently on the same document, Ditto's CRDT merge behavior combines them field-by-field, resulting in "husked documents" - partially deleted documents with some fields set to null and others containing updated values.

**How it Happens:**
1. Device A executes DELETE (sets all fields to null)
2. Device B executes UPDATE concurrently (updates specific fields)
3. When devices reconnect, Ditto merges field-by-field
4. Result: Document with mix of null and updated fields

**Example Scenario:**

```dart
// Device A: DELETE car
await ditto.store.execute(
  'DELETE FROM cars WHERE _id = :id',
  arguments: {'id': 'abc123'},
);
// Internally: {_id: "abc123", color: null, make: null, model: null, year: null}

// Device B (offline): UPDATE car color
await ditto.store.execute(
  'UPDATE cars SET color = :color WHERE _id = :id',
  arguments: {'color': 'blue', 'id': 'abc123'},
);
// Result: {_id: "abc123", color: "blue"}

// After sync - Husked document:
// {_id: "abc123", color: "blue", make: null, model: null, year: null}
```

**Why This Happens:**
Ditto's CRDT performs field-level merging: DELETE sets each field to null, while UPDATE sets specific fields to new values. When merging, Ditto keeps the most recent operation for each individual field.

**Mitigation Strategies:**

**✅ DO:**
- Use logical deletion (soft-delete with `isDeleted` flag) to avoid husked documents
- Reserve DELETE for permanent system-wide removal via Cloud API
- Use EVICT for Edge SDK local data management (doesn't create tombstones)
- Coordinate operations to prevent simultaneous deletes/updates
- Filter husked documents in queries by checking for null required fields

```dart
// ✅ GOOD: Logical deletion prevents husked documents
await ditto.store.execute(
  'UPDATE cars SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
  arguments: {'deletedAt': DateTime.now().toIso8601String(), 'id': 'abc123'},
);

// ✅ GOOD: Filter out husked documents in queries
final result = await ditto.store.execute(
  'SELECT * FROM cars WHERE make IS NOT NULL AND model IS NOT NULL AND isDeleted != true',
);
```

**❌ DON'T:**
- Use DELETE for documents that may be updated concurrently
- Assume DELETE operations prevent all future updates
- Ignore null fields in query results without validation

**Why**: Husked documents can cause application errors when code expects complete document structures. Logical deletion avoids this problem entirely by preserving document integrity.

**Official Reference**: [Ditto Delete Documentation](https://docs.ditto.live/sdk/latest/crud/delete)

---

## Collection Design Patterns

### Denormalization for Performance

**Context: No JOIN Support Makes Denormalization Critical**
Without JOIN operations, fetching related data from multiple collections requires sequential queries with manual joining in application code. This creates significant performance overhead. Denormalization (embedding and duplicating data) avoids this problem.

**✅ DO:**
- **Embed related data that needs to be queried together** (MOST IMPORTANT: avoids sequential queries)
- Duplicate frequently accessed data when it simplifies queries and avoids cross-collection lookups
- Design for read-heavy workloads (optimize for query performance)
- Separate truly independent data into different collections for parallel sync efficiency

```javascript
// ✅ GOOD: Denormalized order with embedded items
{
  "_id": "order_123",
  "customerId": "customer_456",
  "customerName": "Alice Johnson", // Duplicated for quick access
  "items": [
    {
      "productId": "prod_1",
      "productName": "Widget", // Duplicated
      "quantity": 2,
      "price": 10.00
    }
  ],
  "total": 20.00,
  "status": "pending",
  "createdAt": "2025-01-15T10:00:00Z"
}
// Single query returns complete order with customer name and item details
```

**Why Denormalization Is Critical:**
- **Avoids sequential query overhead**: Without JOIN, fetching order + customer + products would require 3+ sequential queries
- **Simpler application code**: No manual joining logic needed
- **Better user experience**: Faster data access, especially on mobile/offline devices
- **Trade-off**: Data duplication vs query performance (in distributed systems, denormalization is often the right choice)

**When to Separate Collections:**
Independent data sets that sync separately benefit from separate collections (parallel sync efficiency). For example:
- Products catalog (updated independently)
- User profiles (rarely accessed with orders)
- System configuration (separate lifecycle)

---

### Field-Level Updates

**✅ DO:**
- Update specific fields rather than replacing documents
- Check if values have actually changed before issuing UPDATE statements
- Preserve CRDT merge behavior
- Use UPDATE statements for targeted field changes

```dart
// ✅ GOOD: Field-level update
final completedAt = DateTime.now().toIso8601String();
await ditto.store.execute(
  'UPDATE orders SET status = :status, completedAt = :completedAt WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'completed', 'completedAt': completedAt},
);
```

**❌ DON'T:**
- Replace entire documents unnecessarily using INSERT with conflict policy
- Update fields with the same value (Ditto treats this as a change and syncs it as a delta)

```dart
// ❌ BAD: Full document replacement
final orderResult = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :orderId',
  arguments: {'orderId': orderId},
);
final order = orderResult.items.first.value;

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      ...order,
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    },
  },
);
// Ditto treats ALL fields as updated (CRDT counter increments),
// causing unnecessary sync traffic even for unchanged field values
```

```dart
// ❌ BAD: Updating with the same value creates unnecessary delta
final currentStatus = 'pending';
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'pending'}, // Same value!
);
// Even though the value hasn't changed, Ditto treats this as an update
// and syncs it as a delta to other peers (unnecessary network traffic)

// ✅ GOOD: Check before updating to avoid unnecessary deltas
final orderResult = await ditto.store.execute(
  'SELECT status FROM orders WHERE _id = :orderId',
  arguments: {'orderId': orderId},
);
final currentStatus = orderResult.items.first.value['status'];
final newStatus = 'completed';

if (currentStatus != newStatus) {
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': newStatus},
  );
} // Only update if value actually changed
```

**Why**: Field-level UPDATE statements only sync changed fields. Full document replacement treats ALL fields as updated (even unchanged ones) due to CRDT counter increments, causing unnecessary network traffic and sync overhead across devices. **⚠️ CRITICAL**: Even updating a field with the same value is treated as a delta and synced to other peers—always check if values have changed before issuing UPDATE statements to avoid unnecessary sync traffic.

---

### DO UPDATE_LOCAL_DIFF for Efficient Upserts (SDK 4.12+)

**⚠️ RECOMMENDED**: Use `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` instead of `DO UPDATE` to automatically avoid syncing unchanged field values.

**What it does:**
- Compares the incoming document with the existing document
- Only updates fields whose values actually differ
- Prevents unnecessary replication of unchanged values
- More efficient than `DO UPDATE` when you want to avoid unnecessary deltas

**✅ DO:**
- Use `DO UPDATE_LOCAL_DIFF` for upsert operations where some fields may not have changed
- Prefer this over manual value checking when upserting entire documents

```dart
// ✅ GOOD: DO UPDATE_LOCAL_DIFF only syncs changed fields (SDK 4.12+)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed
      'customerId': 'customer_456', // Unchanged - won't sync
      'items': [...],               // Unchanged - won't sync
      'completedAt': DateTime.now().toIso8601String(), // Changed
    },
  },
);
// Only 'status' and 'completedAt' fields sync as deltas
// 'customerId' and 'items' are not synced (no unnecessary deltas)
```

**❌ DON'T:**
- Use `DO UPDATE` when you have many unchanged fields

```dart
// ❌ BAD: DO UPDATE syncs ALL fields, even unchanged ones
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed
      'customerId': 'customer_456', // Unchanged - but still synced!
      'items': [...],               // Unchanged - but still synced!
      'completedAt': DateTime.now().toIso8601String(), // Changed
    },
  },
);
// ALL fields treated as updated and synced (unnecessary network traffic)
```

**Conflict Resolution Options:**

| Option | Behavior |
|--------|----------|
| `DO UPDATE` | Updates all fields, syncs all fields as deltas |
| `DO UPDATE_LOCAL_DIFF` (SDK 4.12+) | Only updates and syncs fields that differ from existing document |
| `DO NOTHING` | Ignores conflict, keeps existing document |
| `FAIL` | Throws error on conflict (default) |

**Why**: `DO UPDATE_LOCAL_DIFF` automatically handles the "same value update" problem by comparing values before creating deltas. This is more efficient than manually checking each field and prevents unnecessary sync traffic.

---

### INITIAL Documents for Default Data

**⚠️ CRITICAL: Use INITIAL for Device-Local Templates and Seed Data**

The `INITIAL DOCUMENTS` keyword in INSERT statements creates documents that are treated as "default data from the beginning of time" across all peers, preventing unnecessary synchronization of device-local templates.

**When to Use INITIAL:**
- Device-local templates (e.g., form templates, category lists, default settings)
- Seed data that every peer should initialize independently
- Data that should exist from the start but never sync between devices

**How It Works:**
- Documents inserted with INITIAL do nothing if the `_id` already exists locally
- All peers view INITIAL documents as the same INSERT operation
- Prevents sync conflicts and unnecessary network traffic for local defaults
- Cannot be overridden by ON ID CONFLICT policy

**✅ DO:**
- Use INITIAL for device-local templates that don't need synchronization

```dart
// ✅ GOOD: Insert default templates as INITIAL (won't sync unnecessarily)
final defaultCategories = [
  {'_id': 'cat_food', 'name': 'Food', 'icon': 'food'},
  {'_id': 'cat_drink', 'name': 'Drinks', 'icon': 'drink'},
  {'_id': 'cat_dessert', 'name': 'Desserts', 'icon': 'dessert'},
];

await ditto.store.execute(
  'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);

// Each device initializes these categories independently
// If a device already has 'cat_food', the INITIAL insert does nothing
// No sync traffic generated for these default templates
```

**❌ DON'T:**
- Use regular INSERT for device-local templates (causes unnecessary sync)

```dart
// ❌ BAD: Regular INSERT for templates (causes sync traffic)
await ditto.store.execute(
  'INSERT INTO categories DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);
// Each device's INSERT operation syncs to other peers
// Generates unnecessary network traffic for local templates
```

**Use Cases:**

1. **Form Templates**: Device-local form structures that don't need synchronization
2. **Default Settings**: Initial configuration that every device should have
3. **Category Lists**: Predefined categories for local organization
4. **UI Presets**: Default UI configurations per device

**Why**: INITIAL documents prevent unnecessary synchronization of device-local data, reducing network traffic and avoiding sync conflicts for data that should exist independently on each device.

**Official Reference**: [DQL INSERT Documentation](https://docs.ditto.live/dql/insert)

---

### Counter Patterns

**✅ DO:**
- Use counter increment operations for distributed counters
- Design for merge-friendly updates with PN_INCREMENT

```dart
// ✅ GOOD: Increment counter (CRDT-friendly)
await ditto.store.execute(
  'UPDATE products APPLY viewCount PN_INCREMENT BY 1.0 WHERE _id = :productId',
  arguments: {'productId': productId},
);
```

**❌ DON'T:**
- Use SET operations for counters that may be updated concurrently

```dart
// ❌ BAD: Set counter (conflicts on concurrent updates)
final productResult = await ditto.store.execute(
  'SELECT * FROM products WHERE _id = :productId',
  arguments: {'productId': productId},
);
final product = productResult.items.first.value;

await ditto.store.execute(
  'UPDATE products SET viewCount = :newCount WHERE _id = :productId',
  arguments: {
    'productId': productId,
    'newCount': (product['viewCount'] ?? 0) + 1, // Lost updates from other devices!
  },
);
```

**Why**: Counter increment operations (PN_INCREMENT) merge correctly across concurrent updates; SET operations can cause lost updates when devices are disconnected.

---

### Event History and Audit Logs

**✅ DO:**
- Use separate documents (INSERT) for event history and audit logs
- Avoid arrays for append-only logs in concurrent environments

```dart
// ✅ GOOD: Insert event as separate document (recommended for audit logs)
await ditto.store.execute(
  'INSERT INTO order_history DOCUMENTS (:historyDoc)',
  arguments: {
    'historyDoc': {
      '_id': '${orderId}_${DateTime.now().millisecondsSinceEpoch}',
      'orderId': orderId,
      'status': 'shipped',
      'timestamp': DateTime.now().toIso8601String(),
      'userId': currentUserId,
    },
  },
);

// Query history for an order
final historyResult = await ditto.store.execute(
  'SELECT * FROM order_history WHERE orderId = :orderId ORDER BY timestamp ASC',
  arguments: {'orderId': orderId},
);
```

**❌ DON'T:**
- Use arrays for append-only logs that may be updated concurrently

```dart
// ❌ BAD: Arrays are REGISTERS (last-write-wins)
// If two devices append concurrently, one append will be lost
await ditto.store.execute(
  'UPDATE orders SET statusHistory = statusHistory || [:entry] WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'entry': historyEntry},
);
```

**Why**: Arrays in Ditto are REGISTERS with last-write-wins semantics. Even "append-only" array operations can lose data when multiple devices append concurrently. Using separate INSERT documents ensures all events are preserved.

**Trade-offs:**
- **Separate documents (INSERT)**: Guaranteed preservation of all events, better for audit logs, easier to query/filter
- **Arrays**: Fewer total documents, but risk of data loss in concurrent scenarios

---

### Two-Collection Pattern for Real-Time + Historical Data

When you need both **real-time current state** (low latency) and **historical event data** (complete audit trail), use two separate collections with different purposes.

**Use Case**: Location tracking, sensor readings, order status updates, any scenario where you need both "latest value" and "full history"

**Why Separate Collections**: These are **independent data sets** that don't need to be queried together. Separate collections allow parallel synchronization—devices can sync current state and historical events simultaneously, improving overall sync efficiency. This is in contrast to splitting related data (like orders and order items), which would require serial queries and hurt performance.

#### Pattern: Dual Write

Write each event to two collections simultaneously:

1. **Events collection**: Append-only, grows over time, complete history
2. **Current state collection**: One document per entity, CRDT-managed, bounded size

```dart
// ✅ GOOD: Dual write pattern for location tracking
Future<void> onPositionUpdate(String aircraftId, Position position) async {
  final timestamp = DateTime.now().toIso8601String();
  final eventId = '${aircraftId}_${DateTime.now().millisecondsSinceEpoch}';

  // Write 1: Historical event (append-only)
  await ditto.store.execute(
    'INSERT INTO position_events DOCUMENTS (:event)',
    arguments: {
      'event': {
        '_id': eventId,
        'aircraft_id': aircraftId,
        'timestamp': timestamp,
        'position': {'lat': position.lat, 'lon': position.lon},
        'sensor_id': 'satellite_03',
      },
    },
  );

  // Write 2: Current position (CRDT last-write-wins)
  await ditto.store.execute(
    'INSERT INTO aircraft DOCUMENTS (:aircraft) ON ID CONFLICT DO UPDATE',
    arguments: {
      'aircraft': {
        '_id': aircraftId,
        'position': {'lat': position.lat, 'lon': position.lon},
        'last_seen': timestamp,
        'last_sensor_id': 'satellite_03',
      },
    },
  );
}
```

#### Atomic Dual Writes with Transactions

Use transactions to ensure both writes sync together atomically:

```dart
// ✅ GOOD: Atomic dual write with transaction
await ditto.store.transaction((tx) async {
  // Both operations commit together
  await tx.execute(
    'INSERT INTO position_events DOCUMENTS (:event)',
    arguments: {'event': eventData},
  );

  await tx.execute(
    'INSERT INTO aircraft DOCUMENTS (:aircraft) ON ID CONFLICT DO UPDATE',
    arguments: {'aircraft': currentStateData},
  );

  return; // Automatic commit
});
```

**⚠️ CRITICAL Trade-off**: Transactions vs. Differentiated Subscriptions

| Approach                         | Consistency                    | Bandwidth Optimization              |
|----------------------------------|--------------------------------|-------------------------------------|
| **With transactions**            | Atomic updates, no partial state | All devices must subscribe to both collections |
| **Without transactions**         | Updates may arrive separately  | Devices can subscribe to only what they need |

**Choose based on your priorities:**
- **Atomic consistency**: Use transactions, subscribe to both collections on all devices
- **Bandwidth optimization**: Skip transactions, allow differentiated subscriptions

#### Consumer Patterns

**Real-time display** (observe current state):

```dart
// ✅ GOOD: Observe bounded current state collection
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM aircraft',
  onChange: (result, signalNext) {
    // Result set size bounded by number of aircraft (not update count)
    updateMapDisplay(result.items);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
);
```

**Historical analysis** (query events):

```dart
// ✅ GOOD: One-time query for trajectory
final result = await ditto.store.execute(
  'SELECT * FROM position_events WHERE aircraft_id = :id AND timestamp >= :start ORDER BY timestamp ASC',
  arguments: {'id': aircraftId, 'start': startTime},
);

final trajectory = result.items.map((item) => item.value).toList();
renderFlightPath(trajectory);
```

#### Differentiated Sync Subscriptions

Different devices can subscribe to different data based on their needs:

```dart
// Real-time dashboard (small, fast)
await ditto.sync.registerSubscription(
  'SELECT * FROM aircraft',
);

// Historical analysis tool (specific aircraft only)
await ditto.sync.registerSubscription(
  'SELECT * FROM position_events WHERE aircraft_id IN (:tracked)',
  arguments: {'tracked': ['N12345', 'N67890']},
);
```

**⚠️ Important**: If using transactions for atomic writes, both collections must be subscribed together—devices subscribing only to `aircraft` won't receive updates until they also subscribe to `position_events`.

#### Benefits

| Benefit                          | Explanation                                                             |
|----------------------------------|-------------------------------------------------------------------------|
| **Predictable resource usage**   | Current state collection has bounded size (one doc per entity)          |
| **Automatic conflict resolution**| CRDT handles concurrent updates to current state (no app logic needed)  |
| **Efficient real-time queries**  | No `ORDER BY` or `LIMIT` needed for current state                       |
| **Complete audit trail**         | Events collection preserves all historical data                         |
| **Differentiated sync**          | Devices sync only what they need (if not using transactions)            |

#### Trade-offs vs. Single Collection

| Single Collection (Events Only)  | Two Collections (Dual Write)                                           |
|----------------------------------|-------------------------------------------------------------------------|
| Simpler schema                   | Slightly more complex (two collections)                                 |
| Storage efficient (no duplication)| Duplicates "current state" in both collections                         |
| Queries need `ORDER BY LIMIT 1`  | Current state directly queryable                                        |
| Working set grows over time      | Current state collection has fixed size                                 |
| App handles conflict resolution  | CRDT handles conflicts automatically                                    |

**When to use this pattern:**
- Real-time "current value" is a primary use case
- Multiple sources may update the same entity concurrently
- You need predictable, bounded resource usage
- Different consumers have different latency requirements

**Official Reference**: [Real-Time Location Tracking](https://docs.ditto.live/guides/real-time-location-tracking)

---

## Subscription Patterns

### How Ditto Syncs Data

**Event-Driven Synchronization:**
Ditto uses an event-driven model (not polling). Devices express data needs through subscription queries, and Ditto automatically syncs matching documents across the mesh network.

**Subscription Lifecycle:**
1. Device creates subscription with DQL query
2. Ditto broadcasts subscription query to all connected peers
3. Peers with matching data sync it to the subscribing device
4. Continuous updates: When data changes on any peer, incremental changes sync automatically

**Delta Sync Optimization:**
Ditto transmits only field-level changes (not entire documents), minimizing bandwidth usage. **⚠️ Important**: Even updating a field with the same value is treated as a change and synced as a delta—avoid unnecessary updates to minimize sync traffic. This optimization is especially important for:
- Battery-constrained mobile devices
- Low-bandwidth connections (Bluetooth LE)
- Frequent small updates

**Version Vectors:**
Each document has a version vector tracking its state across peers. When a change occurs, the document version increments. Peers use version vectors to determine if incoming changes are new or already seen.

### Understanding Subscriptions and Queries

**How Subscriptions Work:**
Subscriptions are replication queries that tell Ditto which data to request and sync from connected peers. When you query without an active subscription, `execute()` returns only locally cached data—it won't fetch data from other peers.

**Key Principle: Appropriate Subscription Lifecycle**
Subscriptions should be maintained for as long as you need the data. **Avoid frequent, unnecessary start/stop cycles**—this creates mesh network overhead. Think of subscriptions as declaring "I need this data" rather than "fetch this data once."

**When to Cancel Subscriptions:**
- **When the feature is disposed**: Cancel when a screen/service is permanently closed to notify other peers they don't need to send data anymore
- **Before EVICT operations**: Prevent resync loops where evicted data gets re-synced
- **When subscription scope changes**: Cancel and recreate with updated query parameters
- **App termination**: Ensure proper cleanup to notify peers

**When NOT to Cancel:**
- **Between individual queries**: Don't cancel/recreate for each data access
- **Temporary UI state changes**: Keep subscriptions alive across navigation or minor UI updates
- **Short time periods**: Avoid rapid on/off toggling

**Recommended Pattern: Long-Lived Subscription + Local Store Observer**

```dart
// ✅ GOOD: Long-lived subscription with observer
class OrdersService {
  late final Subscription _subscription;
  late final StoreObserver _observer;

  void initialize() {
    // Start subscription - keep it alive for the lifetime of the feature
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Observer receives initial local data + updates as remote data syncs
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        updateOrdersUI(orders);  // Update UI with initial + synced data

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
      arguments: {'status': 'active'},
    );
  }

  void dispose() {
    // Cancel only when the feature is completely done (e.g., screen disposed)
    _observer.cancel();
    _subscription.cancel();
  }
}
```

**Alternative: One-Time Query (Local Data Only)**

If you only need a snapshot of local data without remote sync:

```dart
// ✅ GOOD: One-time query for local data only
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
final orders = result.items.map((item) => item.value).toList();
// Returns only local data - no remote sync
```

**❌ ANTI-PATTERNS:**

```dart
// ❌ ANTI-PATTERN: Frequent start/stop of subscriptions
// This creates unnecessary mesh network overhead
void loadOrders() {
  final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
  final result = await ditto.store.execute('SELECT * FROM orders');
  subscription.cancel();  // DON'T DO THIS on every request!
}

// ❌ ANTI-PATTERN: Request/response thinking (treating Ditto like HTTP)
Future<List<Order>> fetchOrders() async {
  final sub = ditto.sync.registerSubscription('SELECT * FROM orders');
  await Future.delayed(Duration(seconds: 2));  // Waiting is inefficient!
  final result = await ditto.store.execute('SELECT * FROM orders');
  sub.cancel();  // Canceling immediately defeats mesh sync benefits
  return result.items.map((item) => item.value).toList();
}

// ❌ BAD: Subscription leak (never cancelled)
final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
// Never cancelled when feature is disposed - memory leak!
```

**Key Points:**
- **Maintain subscriptions appropriately**: Start when a feature needs data, cancel when permanently done or before EVICT
- **Use observers for real-time updates**: Observers receive initial local data and notifications as remote data syncs in
- **Avoid unnecessary start/stop cycles**: Frequent toggling creates mesh network overhead—cancel only when needed
- **One-time queries return local data only**: Without a subscription, you only see cached local data
- **Don't think request/response**: Ditto is peer-to-peer mesh, not a client-server API
- **Proper cleanup matters**: Canceling subscriptions notifies other peers they can stop sending data

---

### Observe for Real-Time Updates

**What is an Observer?**
An observer monitors database changes matching a query over time, delivering updates as data changes locally or syncs from other peers.

**When to Use Observers vs One-Time Reads:**

| Scenario | Recommended Approach | Method | Notes |
|----------|---------------------|--------|-------|
| **One-time local data read** (check if data exists locally, read cached config) | ✅ One-time read | `store.execute("SELECT ...")` | Returns local data only—no remote sync |
| **Real-time UI updates** (display live order status, sync data across devices, show live inventory) | ✅ Observer + Subscription | `registerObserverWithSignalNext` | Observer gets initial local data + synced updates |
| **High-frequency updates** (sensor data, real-time tracking, streaming data) | ✅ Observer with backpressure + Subscription | `registerObserverWithSignalNext` | Use `signalNext()` for flow control |
| **Infrequent manual updates** (user profile changes, settings updates) | ✅ Observer + Subscription | `registerObserverWithSignalNext` | Observer notified on changes |

```dart
// ✅ GOOD: One-time read for LOCAL data only (no remote sync)
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE category = :category',
  arguments: {'category': 'electronics'},
);
final products = result.items.map((item) => item.value).toList();
displayProducts(products);
// Note: Without an active subscription, this returns only locally cached data

// ✅ GOOD: Observer + Subscription for real-time UI updates with remote sync
// Start subscription first (or alongside observer)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

// Observer receives initial local data + updates as remote data syncs
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();
    updateOrdersUI(orders);  // UI reflects changes in real-time

    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();  // Ready for next update
    });
  },
  arguments: {'status': 'active'},
);

// Cancel both when feature is disposed
// observer.cancel();
// subscription.cancel();
```

**Understanding Backpressure:**
Callbacks fire every time matching data changes in the local store. In high-frequency scenarios—such as IoT sensors or real-time tracking that generate multiple updates per second—callbacks can accumulate faster than your application processes them. This leads to memory exhaustion and potential crashes.

### Observer Methods

#### registerObserverWithSignalNext (RECOMMENDED)

**Prefer `registerObserverWithSignalNext`** as the recommended pattern for observer scenarios - it provides better performance through predictable backpressure control and prevents memory issues regardless of update frequency.

**Use for:**
- All real-time UI updates (recommended for most use cases)
- High-frequency sensor data (multiple updates per second)
- UI render-cycle synchronization
- Async processing operations
- User profile changes and configuration updates
- Any scenario where performance and memory safety matter

**Why it's better:**
- **Better performance**: Explicit control prevents callback queue buildup
- **Memory safety**: Prevents crashes from uncontrolled callback accumulation
- **Predictable behavior**: You control when the next update arrives

**✅ DO:**
- Extract data from QueryResultItems immediately (lightweight operation)
- Keep callback processing lightweight to avoid blocking
- Offload heavy processing (complex computations, network calls, file I/O) to async operations outside the callback
- Use `signalNext()` to control backpressure explicitly
- Call `signalNext()` after your render cycle completes
- Use for most observer scenarios (default choice)

```dart
// ✅ GOOD: Observer with backpressure control
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
  onChange: (result, signalNext) {
    final data = result.items.map((item) => item.value).toList();
    updateUI(data);

    // Call signalNext after render cycle completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
  arguments: {'deviceId': 'sensor_123'},
);

// Later: stop observing
observer.cancel();
```

**❌ BAD: Heavy processing inside callback blocks observer**

```dart
// ❌ BAD: Blocking callback with heavy processing
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();

    // ❌ BAD: Heavy computation blocks callback
    for (final order in orders) {
      final complexCalculation = performExpensiveAnalysis(order); // BLOCKS!
      final reportData = generateDetailedReport(order); // BLOCKS!
      sendToAnalyticsService(reportData); // Network call BLOCKS!
    }

    signalNext(); // Only called after all heavy processing completes
  },
);
```

**✅ GOOD: Offload heavy processing to async operations**

```dart
// ✅ GOOD: Lightweight callback, heavy processing offloaded
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    // Extract data immediately (lightweight)
    final orders = result.items.map((item) => item.value).toList();

    // Update UI immediately (lightweight)
    updateUI(orders);

    // Offload heavy processing to background async task
    _processOrdersAsync(orders); // Non-blocking

    // Signal readiness for next update immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
);

// Heavy processing runs independently
Future<void> _processOrdersAsync(List<Map<String, dynamic>> orders) async {
  // These heavy operations run in parallel, don't block observer
  await Future.wait(orders.map((order) async {
    final analysis = await performExpensiveAnalysis(order);
    final report = await generateDetailedReport(order);
    await sendToAnalyticsService(report);
  }));
}
```

#### registerObserver (Simple Data Processing Only)

**Use only for:**
- Very simple, synchronous data processing
- Scenarios where backpressure control is explicitly not needed

**⚠️ Limitations:**
- **Lower performance**: No backpressure control can lead to callback queue buildup
- **Memory risk**: Callbacks can accumulate faster than processing in many scenarios
- **Less predictable**: No control over update timing

```dart
// ⚠️ OK for very simple cases only
final observer = ditto.store.registerObserver(
  'SELECT * FROM simple_config',
  onChange: (result) {
    // Only use for trivial, synchronous processing
    final config = result.items.first.value;
    updateSimpleValue(config);
  },
);
```

**When in doubt, use `registerObserverWithSignalNext`** - it provides better performance and is the recommended pattern for most use cases.

### Observer Lifecycle Management

**✅ DO:**
- Prefer `registerObserverWithSignalNext` for all observers (better performance, recommended pattern)
- Maintain observers for the lifetime of the feature that needs real-time updates
- Cancel observers when the feature is disposed (e.g., screen closed, service stopped)
- Pair observers with subscriptions for remote data sync
- Access registered observers via `ditto.store.observers`
- Call `signalNext()` to control backpressure explicitly

**❌ DON'T:**
- Use `registerObserver` for most use cases (worse performance, use only for very simple data processing)
- Cancel and recreate observers frequently (avoid unnecessary churn)
- Perform heavy processing (complex computations, network calls, file I/O) inside observer callbacks
- Block the callback thread with synchronous heavy operations
- Leave observers running after feature disposal (causes memory leaks)

**When to Cancel Observers:**
- **Feature disposal**: When a screen/service is permanently closed
- **Component unmounting**: When a widget is disposed in Flutter
- **App termination**: During cleanup before app shutdown
- **Scope changes**: When the query needs to change (cancel old, create new)

**When NOT to Cancel:**
- **Temporary navigation**: Keep alive if returning to the same screen
- **Background state**: Don't cancel just because the app goes to background
- **Short intervals**: Avoid rapid start/stop cycles

**Why**: Observers enable real-time UI updates as data changes locally or syncs from other devices. Using `registerObserverWithSignalNext` provides better performance and memory safety. Heavy processing in callbacks blocks the observer thread, degrading performance—offload such work to async operations. Proper lifecycle management (similar to subscriptions) prevents memory leaks while maintaining efficient real-time updates.

---

### Partial UI Updates (Avoid Full Screen Refreshes)

**The Problem:**
Observer callbacks trigger when data changes, but poorly designed UI updates can cause the entire screen or widget tree to rebuild unnecessarily. This leads to:
- **Performance degradation**: Rendering components that didn't change
- **Unnecessary CPU/GPU usage**: Battery drain on mobile devices
- **Visual glitches**: Flickering, scrolling resets, lost input focus
- **Poor user experience**: Sluggish UI, especially with frequent updates

**Common Anti-Pattern:**

```dart
// ❌ BAD: Full screen refresh on every data change
class OrderListScreen extends StatefulWidget {
  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        setState(() {
          orders = result.items.map((item) => item.value).toList();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Entire screen rebuilds when ANY order changes!
    return Scaffold(
      appBar: AppBar(title: Text('Orders (${orders.length})')),
      body: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return OrderCard(order: order);  // All cards rebuild!
        },
      ),
    );
  }
}
```

**Problem**: When a single order's status changes (e.g., "pending" → "shipped"), `setState()` causes:
1. Entire `OrderListScreen` widget rebuilds
2. `AppBar` rebuilds (even though title didn't change)
3. `ListView` rebuilds
4. **All** `OrderCard` widgets rebuild (even for unchanged orders)

---

#### Solution 1: State Management with Granular Observation (Recommended)

Use Riverpod providers to separate data management from UI, allowing selective widget rebuilds.

**✅ GOOD: Riverpod with granular observation**

```dart
// 1. Provider for Ditto store
final dittoProvider = Provider<Ditto>((ref) => throw UnimplementedError());

// 2. Provider for orders data with observer
final ordersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final ditto = ref.watch(dittoProvider);
  final controller = StreamController<List<Map<String, dynamic>>>();

  final observer = ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    onChange: (result, signalNext) {
      final orders = result.items.map((item) => item.value).toList();
      controller.add(orders);
      WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
    },
  );

  ref.onDispose(() {
    observer.cancel();
    controller.close();
  });

  await for (final orders in controller.stream) {
    yield orders;
  }
});

// 3. Provider for single order (granular selection)
final orderProvider = Provider.family<Map<String, dynamic>?, String>((ref, orderId) {
  final ordersAsync = ref.watch(ordersProvider);
  return ordersAsync.when(
    data: (orders) => orders.firstWhereOrNull((o) => o['_id'] == orderId),
    loading: () => null,
    error: (_, __) => null,
  );
});

// 4. Screen widget (minimal rebuilds)
class OrderListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) => Text('Orders (${orders.length})'),
          loading: () => Text('Orders'),
          error: (_, __) => Text('Orders (Error)'),
        ),
      ),
      body: ordersAsync.when(
        data: (orders) => ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final orderId = orders[index]['_id'] as String;
            // Each card only rebuilds if ITS data changes
            return OrderCard(orderId: orderId);
          },
        ),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

// 5. Individual card widget (rebuilds only when its order changes)
class OrderCard extends ConsumerWidget {
  final String orderId;

  const OrderCard({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watches THIS order's data
    final order = ref.watch(orderProvider(orderId));

    if (order == null) return SizedBox.shrink();

    return Card(
      child: ListTile(
        title: Text('Order #${order['orderNumber']}'),
        subtitle: Text('Status: ${order['status']}'),
        trailing: Text('\$${order['total']}'),
      ),
    );
  }
}
```

**How This Works:**
1. `ordersProvider` manages observer lifecycle and provides data stream
2. `orderProvider.family` creates granular selectors for each order ID
3. When order `order_123` changes:
   - Only `OrderCard(orderId: 'order_123')` rebuilds
   - Other cards remain untouched
   - AppBar only rebuilds if order count changes

**Benefits:**
- **Minimal rebuilds**: Only affected widgets update
- **Automatic optimization**: Riverpod handles change detection
- **Clean separation**: Data management separate from UI
- **Testable**: Providers can be mocked in tests

---

#### Solution 2: ValueListenableBuilder for Simple Cases

For simpler scenarios without full state management, use `ValueNotifier` with `ValueListenableBuilder`.

**✅ GOOD: ValueNotifier for targeted updates**

```dart
class OrderListScreen extends StatefulWidget {
  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final ordersNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        ordersNotifier.value = result.items.map((item) => item.value).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  void dispose() {
    observer.cancel();
    ordersNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: ordersNotifier,
          builder: (context, orders, child) {
            // Only AppBar title rebuilds when order count changes
            return Text('Orders (${orders.length})');
          },
        ),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: ordersNotifier,
        builder: (context, orders, child) {
          // Only ListView rebuilds (not entire Scaffold)
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return OrderCard(order: order);
            },
          );
        },
      ),
    );
  }
}
```

**Benefits:**
- **Simpler than full state management**: No external dependencies
- **Scoped rebuilds**: Only `ValueListenableBuilder` subtrees rebuild
- **Built-in to Flutter**: No additional packages required

**Limitations:**
- Still rebuilds entire list when any order changes
- Doesn't provide granular per-item optimization
- Less suitable for complex apps with many data dependencies

---

#### Solution 3: Using Ditto's DittoDiffer (Advanced)

For maximum optimization, use `DittoDiffer` to detect exactly which documents changed and update only those UI elements.

**✅ GOOD: DittoDiffer for surgical updates**

```dart
class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];
  final differ = DittoDiffer();
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        // Calculate which documents changed
        final changeSummary = differ.computeChanges(result.items);

        if (changeSummary.hasChanges) {
          setState(() {
            orders = result.items.map((item) => item.value).toList();
          });

          // Optional: Log which orders changed for debugging
          print('Inserted: ${changeSummary.insertions.length}');
          print('Updated: ${changeSummary.updates.length}');
          print('Deleted: ${changeSummary.deletions.length}');
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          // Use unique key for efficient list updates
          return OrderCard(
            key: ValueKey(order['_id']),
            order: order,
          );
        },
      ),
    );
  }
}
```

**How This Works:**
1. `DittoDiffer` tracks document versions between callbacks
2. `computeChanges()` identifies insertions, updates, deletions
3. Flutter's reconciliation uses `ValueKey` to update only changed items
4. Unchanged list items reuse existing widget instances

**Benefits:**
- **Efficient list updates**: Flutter knows exactly which items changed
- **Minimal rebuilds**: Only new/updated/deleted items rebuild
- **Built into Ditto**: No external dependencies

**When to Use:**
- Large lists (hundreds or thousands of items)
- High-frequency updates
- Performance-critical applications

---

#### Performance Comparison

**Test Scenario**: 1000 orders displayed, single order's status changes

| Approach                          | Widgets Rebuilt | Performance Impact |
|-----------------------------------|-----------------|--------------------|
| ❌ `setState()` on entire screen  | ~1003           | High (full refresh)|
| ✅ `ValueListenableBuilder`       | ~1001           | Medium (scoped)    |
| ✅ Riverpod granular providers    | 1               | Minimal (optimal)  |
| ✅ `DittoDiffer` with keys        | 1               | Minimal (optimal)  |

---

#### Best Practices Summary

**✅ DO:**
- Use state management (Riverpod) for complex apps with multiple data dependencies
- Use `ValueListenableBuilder` for simpler apps or isolated components
- Use `DittoDiffer` with `ValueKey` for large lists with frequent updates
- Profile your app with Flutter DevTools to identify rebuild bottlenecks
- Scope rebuilds to the smallest widget subtree possible

**❌ DON'T:**
- Call `setState()` on the entire screen in observer callbacks
- Rebuild widgets that don't depend on changed data
- Ignore performance implications of full screen refreshes
- Assume Flutter automatically optimizes all rebuilds

**Why This Matters:**
- **Better UX**: Smooth, responsive UI without glitches
- **Battery efficiency**: Less CPU/GPU usage extends battery life
- **Scalability**: App remains performant as data and complexity grow
- **Professional quality**: Users expect fluid experiences, especially in real-time sync scenarios

**Official References:**
- Flutter Performance Best Practices: https://docs.flutter.dev/perf/best-practices
- Riverpod Documentation: https://riverpod.dev/docs/concepts/reading
- Flutter DevTools: https://docs.flutter.dev/tools/devtools/performance

---

## Testing Strategies

### Test Business Logic Under Concurrent Scenarios

**✅ DO:**
- Test **application-specific business logic** with realistic concurrent scenarios
- Focus on **your data model**, not SDK behavior
- Verify **business rules** hold after conflict resolution

```dart
// ✅ GOOD: Test business logic (inventory management)
test('concurrent product sales do not oversell inventory', () async {
  final store1 = createTestDitto('store1');
  final store2 = createTestDitto('store2');

  // Initialize product inventory
  final productId = 'product_123';
  await store1.repository.createProduct(productId, initialStock: 10);
  await syncStores(store1, store2);

  // Simulate concurrent sales at two locations
  await store1.repository.sellProduct(productId, quantity: 7);
  await store2.repository.sellProduct(productId, quantity: 5);

  await syncStores(store1, store2);

  // Verify: Either sale fails OR business rule enforced
  final product1 = await store1.repository.getProduct(productId);
  final product2 = await store2.repository.getProduct(productId);

  // Both stores should see consistent state
  expect(product1.stock, product2.stock);

  // Business rule: stock should never go negative
  expect(product1.stock, greaterThanOrEqualTo(0));

  // If using PN_INCREMENT: stock = 10 - 7 - 5 = -2 (WRONG!)
  // If using validation logic: one sale should be rejected
});

// ✅ GOOD: Test business logic (order numbering)
test('concurrent order creation generates unique order numbers', () async {
  final pos1 = createTestDitto('pos1');
  final pos2 = createTestDitto('pos2');

  await syncStores(pos1, pos2);

  // Create orders concurrently at two POS terminals
  final order1 = await pos1.repository.createOrder(items: [/*...*/]);
  final order2 = await pos2.repository.createOrder(items: [/*...*/]);

  await syncStores(pos1, pos2);

  // Verify: Order numbers must be unique
  expect(order1.orderNumber, isNot(equals(order2.orderNumber)));

  // Verify: Both orders exist in both stores
  final allOrders1 = await pos1.repository.getAllOrders();
  final allOrders2 = await pos2.repository.getAllOrders();
  expect(allOrders1.length, 2);
  expect(allOrders2.length, 2);
});
```

**❌ DON'T:**
- Test only SDK API calls without your app's data model and business logic
- Use generic/fake data models (counters, todos) instead of your actual domain models
- Test scenarios irrelevant to your app's business logic

**Why**: Tests that only verify SDK API behavior (without your app's data model and logic) provide no value—the SDK itself is already tested. What matters is testing how **your specific data model and business logic** behave under concurrent scenarios. Focus on **your application's invariants** (e.g., "inventory never negative", "order numbers unique") using your actual domain models.

---

### Test Deletion Scenarios

**✅ DO:**
- Test tombstone TTL behavior
- Verify logical deletion filtering
- Test "zombie data" scenarios

```dart
// ✅ GOOD: Test logical deletion
test('deleted items do not appear in queries', () async {
  // Create and mark as deleted
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:doc)',
    arguments: {
      'doc': {
        '_id': 'order_1',
        'status': 'active',
        'isDeleted': false,
      },
    },
  );

  await ditto.store.execute(
    'UPDATE orders SET isDeleted = true WHERE _id = :id',
    arguments: {'id': 'order_1'},
  );

  // Query should exclude deleted
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE isDeleted != true',
  );

  final orderIds = result.items.map((i) => i.value['_id']).toList();
  expect(orderIds, isNot(contains('order_1')));
});
```

**Why**: Deletion behavior is complex in distributed systems and must be thoroughly tested.

---

## Performance Best Practices

### Optimize Query Scope

**✅ DO:**
- Use specific queries with WHERE clauses
- Limit subscription scope to needed data
- Use parameterized queries

```dart
// ✅ GOOD: Specific query with parameters
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId AND status = :status',
  arguments: {'customerId': customerId, 'status': 'active'},
);
```

**❌ DON'T:**
- Subscribe to entire collections without filtering

```dart
// ❌ BAD: Overly broad subscription
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // All documents!
);
```

**Why**: Broad subscriptions sync and store unnecessary data, impacting performance and storage.

---

### Subscription Scope Balancing: Too Broad vs Too Narrow

**⚠️ CRITICAL**: Finding the right subscription scope requires balancing two competing risks:

| Risk                          | Cause                          | Impact                                                          |
|-------------------------------|--------------------------------|-----------------------------------------------------------------|
| **Performance degradation**   | Overly broad subscriptions     | Sync unnecessary data, consume storage/bandwidth/memory         |
| **Missing data in multi-hop** | Overly narrow subscriptions    | Intermediate peers don't relay documents they don't store       |

#### The Multi-Hop Relay Problem

**How Ditto Multi-Hop Works:**
Ditto can relay documents through intermediate devices (multi-hop sync). However, **an intermediate device can only relay documents it has in its local store**. If a device's subscription is too narrow, it won't store certain documents, and therefore cannot relay them to other devices.

**Problem Scenario:**

```dart
// Network topology: Device A ← → Device B ← → Device C
// (Device B acts as relay between A and C)

// Device A (creates orders):
// - Has order_1 (priority='high')
// - Has order_2 (priority='low')

// Device B (intermediate relay):
// ⚠️ RISKY: Too narrow subscription
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE priority = :priority',
  arguments: {'priority': 'high'},
);
// Device B only stores order_1 in its local store

// Device C (end user):
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // Wants all orders
);

// PROBLEM:
// 1. Device B receives subscription query from Device C: "SELECT * FROM orders"
// 2. Device B only has order_1 in its store (due to narrow subscription)
// 3. Device B syncs order_1 to Device C
// 4. Device C NEVER receives order_2 (Device B doesn't have it to relay)
// 5. Device C has incomplete data (missing order_2)
```

**Why This Happens:**
When Device B receives a subscription query from Device C, it can only respond with documents that:
1. Match Device C's subscription query
2. **AND exist in Device B's local store**

Since Device B's narrow subscription (`priority='high'`) excludes `order_2`, Device B never stores it, and therefore cannot relay it to Device C—even though Device C's subscription would match it.

**Visualization:**

```
Device A (source)          Device B (relay)           Device C (destination)
─────────────────          ────────────────           ──────────────────────
order_1 (high)      →→     order_1 (high)      →→     order_1 (high) ✅
order_2 (low)       ✗✗     [not stored]        ✗✗     [missing!] ❌
                           ↑
                           Too narrow subscription
                           blocks storage & relay
```

#### Best Practices for Scope Balancing

**1. Subscribe Broadly, Filter Narrowly in Observers**

```dart
// ✅ GOOD: Broad subscription ensures all updates received
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',
  arguments: {'customerId': customerId},
);

// ✅ GOOD: Narrow observer filter for UI display
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE customerId = :customerId AND status = :status',
  onChange: (result, signalNext) {
    updateUI(result.items); // Only active orders
    signalNext();
  },
  arguments: {'customerId': customerId, 'status': 'active'},
);
```

**2. Include State Transition Fields in Subscriptions**

If documents can transition between states, subscribe to all relevant states:

```dart
// ✅ GOOD: Subscribe to all order states user might see
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId AND status IN (:statuses)',
  arguments: {
    'customerId': customerId,
    'statuses': ['pending', 'active', 'completed', 'cancelled'],
  },
);
```

**3. Consider Subscription Lifetime vs Data Lifetime**

```dart
// ⚠️ RISKY: Subscription narrower than data lifetime
// User creates task → marks complete → task disappears from their view
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM tasks WHERE completed != true',
);

// ✅ BETTER: Subscribe to all user's tasks
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM tasks WHERE userId = :userId',
  arguments: {'userId': userId},
);

// Filter completed tasks in observer, not subscription
```

**4. Use Logical Deletion with Broad Subscriptions**

For deleted items, subscribe broadly to ensure deletion updates sync:

```dart
// ✅ GOOD: Subscribe to all (including deleted)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',
  arguments: {'customerId': customerId},
);

// Observer filters deleted items for UI
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE customerId = :customerId AND isDeleted != true',
  ...
);
```

**Decision Framework**:

| Question                                          | If YES → Subscribe Broadly  | If NO → Can Filter Narrowly |
|---------------------------------------------------|-----------------------------|------------------------------|
| Can this document's fields change over time?      | ✓                           |                              |
| Do I need to see updates after initial creation?  | ✓                           |                              |
| Can documents transition between states?          | ✓                           |                              |
| Do I use logical deletion?                        | ✓                           |                              |
| Is this data truly immutable after creation?      |                             | ✓                            |

**Why**: Missing data due to broken multi-hop relay is extremely hard to debug (non-obvious topology dependencies). Performance issues are much easier to identify and fix. When in doubt, subscribe broadly and filter in observers.

---

### Handle Attachments Explicitly

**⚠️ CRITICAL: Attachments are not auto-synced**

Attachments use the ATTACHMENT data type to store binary data separately from documents. Unlike documents which are always readily accessible, attachments require explicit fetching.

### Attachment Architecture

**Two Components:**
1. **Metadata**: Stored with the document (filename, size, type, description)
2. **Blob Data**: Stored externally and fetched on demand

**Storage Locations:**
- **Small Peers (Edge devices)**: RAM (browser/server), filesystem (mobile devices)
- **Ditto Server**: AWS S3 cloud object storage

**Blob Sync Protocol:**
Attachment sync operates asynchronously via a separate protocol from document sync. Peers may hold attachment tokens without the corresponding blob data.

### Best Practices

**✅ DO:**
- **Lazy-Load Pattern**: Fetch attachments only when needed to reduce resource usage
- **Add Metadata**: Include descriptive metadata (filename, type, description) to facilitate efficient fetching
- **Handle Errors**: Wrap fetches in try-catch blocks to handle network failures gracefully
- **Keep Fetchers Active**: Attachment fetchers must remain active until completion
- **Consider Deleting Source Files**: After creating attachments with `newAttachment()`, you can delete the original files to avoid storage duplication (unless your app needs quick local access or maintains backups)

```dart
// ✅ GOOD: Lazy-load with metadata
final doc = await ditto.store.execute(
  'SELECT * FROM products WHERE _id = :id',
  arguments: {'id': productId},
);

if (doc.items.isNotEmpty) {
  final docValue = doc.items.first.value;
  final attachmentToken = docValue['imageAttachment'];
  final metadata = docValue['imageMetadata']; // filename, size, type

  if (attachmentToken != null) {
    try {
      // Fetch only when user needs to view the image
      final attachment = await ditto.store.fetchAttachment(attachmentToken);
      displayImage(attachment, metadata);
    } catch (e) {
      // Handle fetch failure (network error, missing blob, etc.)
      showError('Failed to load image: $e');
    }
  }
}
```

**✅ GOOD: Store attachment with metadata**

```dart
// Create attachment and store with metadata
final attachmentToken = await ditto.store.newAttachment(
  imageBytes,
  metadata: {'filename': 'image.jpg', 'mime_type': 'image/jpeg'},
);

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageAttachment': attachmentToken,
      'imageMetadata': {'size': imageBytes.length, 'description': 'Product photo'},
    },
  },
);

// ✅ OPTIONAL: Delete source file to avoid storage duplication
await imageFile.delete();
// Consider keeping if: app needs quick access, maintaining backups, or file used elsewhere
```

**❌ DON'T:**
- Store large binary data inline with documents
- Assume attachments sync automatically with subscriptions
- Modify existing attachments (they're immutable - replace the token instead)
- Cancel fetchers before completion

```dart
// ❌ BAD: Inline binary data
await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product)',
  arguments: {
    'product': {
      '_id': productId,
      'imageData': base64EncodedLargeImage, // Bloats document size!
    },
  },
);
```

### Attachment Immutability and Updates

**⚠️ Important**: Attachments become immutable once created.

**To Update:**
1. Create new attachment
2. Replace the token in the document using UPDATE

```dart
// ✅ GOOD: Replace attachment
final newImageBytes = await File('new_image.jpg').readAsBytes();
final newToken = await ditto.store.newAttachment(newImageBytes);

await ditto.store.execute(
  'UPDATE products SET imageAttachment = :token, imageMetadata = :metadata WHERE _id = :id',
  arguments: {
    'token': newToken,
    'metadata': {
      'filename': 'new_image.jpg',
      'size': newImageBytes.length,
      'type': 'image/jpeg',
    },
    'id': productId,
  },
);
```

### Garbage Collection

**Automatic Cleanup:**
- Small Peers run garbage collection on a 10-minute cadence
- Unreferenced attachments are automatically removed

**Why Explicit Fetching:**
- **Bandwidth efficiency**: Prevents automatic transfer of large files
- **Resource control**: Apps fetch only when needed
- **Battery conservation**: Reduces unnecessary data transfer on mobile devices
- **Storage management**: Lazy-loading reduces local storage pressure

---

### The Thumbnail Pattern for Photos and Large Files

When sharing photos or large files in bandwidth-constrained mesh networks, use the **thumbnail-first** pattern: automatically sync a small preview while making the full resolution available on-demand.

**Problem**: A 5MB photo takes ~6 minutes over Bluetooth LE at 100 Kbps, starving other critical data.

**Solution**: Store two attachments per photo:
1. **Thumbnail** (~50KB): Auto-fetched, provides immediate preview
2. **Full resolution** (~5MB): On-demand fetch when user requests

```dart
// ✅ GOOD: Thumbnail + full resolution pattern
Future<void> sharePhoto(Uint8List imageData, String caption) async {
  // 1. Generate thumbnail (resize to 200x200, quality 70%)
  final thumbnailData = await generateThumbnail(imageData);

  // 2. Create both attachments
  final thumbnailToken = await ditto.store.newAttachment(
    thumbnailData,
    metadata: {'name': 'photo_thumb.jpg', 'mime_type': 'image/jpeg'},
  );

  final fullResToken = await ditto.store.newAttachment(
    imageData,
    metadata: {'name': 'photo_full.jpg', 'mime_type': 'image/jpeg'},
  );

  // 3. Insert document with BOTH attachment tokens
  // ⚠️ CRITICAL: Declare ATTACHMENT types in COLLECTION clause
  await ditto.store.execute(
    'INSERT INTO COLLECTION photos (thumbnail ATTACHMENT, full_resolution ATTACHMENT) DOCUMENTS (:photo)',
    arguments: {
      'photo': {
        '_id': photoId,
        'caption': caption,
        'thumbnail': thumbnailToken,
        'full_resolution': fullResToken,
        'created_at': DateTime.now().toIso8601String(),
      },
    },
  );
}
```

**Size-Based Auto-Download Strategy**:

Use the `len` field from attachment tokens to decide whether to auto-fetch:

```dart
// ✅ GOOD: Auto-fetch thumbnails, manual fetch for full resolution
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM photos ORDER BY created_at DESC',
  onChange: (result, signalNext) {
    for (final item in result.items) {
      final photo = item.value;
      final thumbnailToken = photo['thumbnail'];
      final thumbnailSize = thumbnailToken['len'];

      // Auto-fetch thumbnails if small enough (e.g., < 100KB)
      if (thumbnailSize < 100 * 1024 && !_alreadyFetched(thumbnailToken)) {
        ditto.store.fetchAttachment(thumbnailToken, (event) {
          if (event is AttachmentFetchEventCompleted) {
            updateThumbnailInUI(photo['_id'], event.attachment);
          }
        });
      }
    }

    signalNext();
  },
);

// User-initiated full resolution download
Future<void> downloadFullResolution(String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );

  final fullResToken = result.items.first.value['full_resolution'];

  ditto.store.fetchAttachment(fullResToken, (event) {
    if (event is AttachmentFetchEventProgress) {
      updateDownloadProgress(event.downloadedBytes, event.totalBytes);
    } else if (event is AttachmentFetchEventCompleted) {
      displayFullResolutionImage(event.attachment);
    }
  });
}
```

**Benefits**:

| Metric                | Full Resolution Only | Thumbnail + On-Demand |
|-----------------------|----------------------|-----------------------|
| Initial sync          | 5 MB                 | 50 KB                 |
| Time over BLE         | ~6 minutes           | ~4 seconds            |
| User feedback         | Delayed              | Immediate             |
| Mesh impact           | High                 | Minimal               |

**Official Reference**: [Photo Sharing Guide](https://docs.ditto.live/guides/photo-sharing)

---

### Attachment Availability Constraints

**⚠️ CRITICAL**: Attachments can only be fetched from **immediate peers** (directly connected devices) that have already fetched the attachment themselves.

**Scenario**:
```
Device A (has full res) ← connected → Device B (has thumbnail only) ← connected → Device C (wants full res)
```

In this mesh:
- Device C **cannot** fetch the full resolution from Device A (not directly connected)
- Device C can only see the document and thumbnail
- Device B must first download the full resolution before C can access it

**Mitigation Strategies**:
- Use thumbnails to reduce the impact of this limitation
- Consider having relay/hub devices that always fetch attachments
- Design UI to show availability status ("Available from 2 peers")
- Implement retry logic when attachments become available

```dart
// ✅ GOOD: Show attachment availability in UI
Future<void> checkAttachmentAvailability(String photoId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM photos WHERE _id = :id',
    arguments: {'id': photoId},
  );

  final fullResToken = result.items.first.value['full_resolution'];
  final peerCount = ditto.store.getAttachmentPeerCount(fullResToken);

  if (peerCount == 0) {
    showUI('Full resolution not available yet');
  } else {
    showUI('Available from $peerCount peer(s) - Download now?');
  }
}
```

---

### Attachment Fetch Timeout Handling

Attachment fetches can be interrupted by connectivity changes. Ditto handles this gracefully:
- **Progress is preserved**: If interrupted, it resumes from where it left off
- **Multiple sources**: If a peer disconnects, another peer can continue
- **No error on stall**: If all sources disconnect, the fetch simply stalls—no error is raised

**Implement timeout wrapper to detect stalled fetches**:

```dart
// ✅ GOOD: Timeout wrapper for attachment fetch
Future<Attachment> fetchAttachmentWithTimeout(
  AttachmentToken token,
  Duration timeout,
) async {
  final completer = Completer<Attachment>();
  DateTime lastProgress = DateTime.now();
  Timer? timer;

  timer = Timer.periodic(Duration(seconds: 5), (t) {
    if (DateTime.now().difference(lastProgress) > timeout) {
      t.cancel();
      fetcher?.cancel();
      completer.completeError('Fetch stalled: no progress for ${timeout.inSeconds}s');
    }
  });

  final fetcher = ditto.store.fetchAttachment(token, (event) {
    lastProgress = DateTime.now();
    if (event is AttachmentFetchEventCompleted) {
      timer?.cancel();
      completer.complete(event.attachment);
    } else if (event is AttachmentFetchEventDeleted) {
      timer?.cancel();
      completer.completeError('Attachment deleted during fetch');
    }
  });

  return completer.future;
}

// Usage
try {
  final attachment = await fetchAttachmentWithTimeout(token, Duration(minutes: 5));
  displayImage(attachment);
} catch (e) {
  showError('Download failed: $e');
}
```

**Why**: Stalled fetches tie up resources indefinitely. Timeout detection allows you to retry, notify users, or abandon the fetch gracefully.

---

### Transactions

**⚠️ CRITICAL: Understanding Ditto Transactions**

Transactions group multiple DQL operations into a single atomic database commit with serializable isolation level, providing the strongest consistency guarantees.

**⚠️ Flutter SDK Limitation:**
The Flutter SDK does not currently support the full transactions API in current versions. The `ditto.store.transaction()` method shown in other platform documentation is **not available in current Flutter SDK versions**. Flutter applications must use individual DQL statements and handle atomicity at the application level if needed.

**For Non-Flutter Platforms (iOS, Android Native, Node.js, etc.):**

**What Transactions Provide:**
- **Atomicity**: All operations complete or none execute
- **Consistency**: All statements see identical data snapshots within the transaction
- **Serializable isolation**: Strongest consistency level
- **Implicit rollback**: Errors automatically rollback the entire transaction

**Critical Limitations:**
- **Single read-write transaction at a time**: Only one read-write transaction executes concurrently; others must wait
- **NEVER nest read-write transactions**: Creates deadlock where inner waits for outer, outer waits for inner
- **Complete quickly**: Long-running transactions block all other read-write transactions
- **Warning thresholds**: Ditto logs warnings after 10 seconds, escalating every 5 seconds

**✅ DO (Non-Flutter Platforms):**
- Use transactions for multi-step operations requiring atomicity
- Set descriptive `hint` parameters for debugging
- Keep transaction blocks minimal and fast
- Use read-only mode when mutation isn't needed
- Return values directly (automatic commit) or explicitly return `.commit`
- Handle specific errors within the block if transaction should continue

```dart
// ✅ GOOD: Read-write transaction with atomicity (NOT AVAILABLE IN FLUTTER)
await ditto.store.transaction(hint: 'process-order', (tx) async {
  // All statements see the same data snapshot
  final orderResult = await tx.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  if (orderResult.items.isEmpty) {
    throw Exception('Order not found');
  }

  final order = orderResult.items.first.value;

  // Update order status
  await tx.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': 'shipped'},
  );

  // Decrement inventory
  await tx.execute(
    'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId',
    arguments: {'itemId': order['itemId']},
  );

  return; // Automatic commit
});

// ✅ GOOD: Read-only transaction (concurrent execution allowed)
await ditto.store.transaction(
  hint: 'read-order-summary',
  isReadOnly: true,
  (tx) async {
    final orders = await tx.execute('SELECT * FROM orders');
    final items = await tx.execute('SELECT * FROM order_items');

    return calculateSummary(orders, items); // Automatic commit with return value
  },
);
```

**❌ DON'T (Non-Flutter Platforms):**
- Nest read-write transactions (causes permanent deadlock)
- Execute operations outside transaction object within block
- Use transactions for long-running operations

```dart
// ❌ BAD: Nested read-write transaction (DEADLOCK!)
await ditto.store.transaction((outerTx) async {
  await outerTx.execute('UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'status': 'processing', 'id': orderId});

  // DEADLOCK: Inner transaction waits for outer, outer waits for inner
  await ditto.store.transaction((innerTx) async {
    await innerTx.execute('UPDATE inventory SET quantity = :qty WHERE _id = :id',
      arguments: {'qty': 0, 'id': itemId});
  });
});
```

**Flutter Alternative Pattern:**

Since Flutter SDK doesn't support transactions in current versions, use sequential DQL statements with error handling:

```dart
// ✅ FLUTTER: Sequential updates with error handling
Future<void> processOrder(String orderId) async {
  try {
    // Step 1: Fetch order
    final orderResult = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      arguments: {'orderId': orderId},
    );

    if (orderResult.items.isEmpty) {
      throw Exception('Order not found');
    }

    final order = orderResult.items.first.value;

    // Step 2: Update order status
    await ditto.store.execute(
      'UPDATE orders SET status = :status WHERE _id = :orderId',
      arguments: {'orderId': orderId, 'status': 'shipped'},
    );

    // Step 3: Decrement inventory
    await ditto.store.execute(
      'UPDATE inventory APPLY quantity PN_INCREMENT BY -1.0 WHERE _id = :itemId',
      arguments: {'itemId': order['itemId']},
    );
  } catch (e) {
    // Handle error - note: no automatic rollback in Flutter
    // Consider using status flags to track partial updates
    print('Error processing order: $e');
    rethrow;
  }
}
```

**Why Transactions Matter (Where Supported):**
- Ensures multi-step operations complete atomically (all or nothing)
- Provides consistent view of data across multiple queries
- Prevents partial updates that could corrupt data
- But: Only one read-write transaction runs at a time, so keep them fast

**Read-Only Transactions (Where Supported):**
Multiple read-only transactions can execute concurrently, even alongside read-write transactions. Use `isReadOnly: true` for operations that only query data.

**Performance Guidelines (Where Supported):**
- Complete transactions in milliseconds, not seconds
- Move heavy computation outside transaction blocks
- Use read-only transactions when possible
- Monitor transaction duration warnings in logs

**Official Reference**: [Ditto Transactions Documentation](https://docs.ditto.live/sdk/latest/crud/transactions)

---

## Device Storage Management

**⚠️ CRITICAL: Why Storage Management Matters**

Data storage management is essential for preventing unnecessary resource usage, which affects not only performance but also battery life and overall end-user experience. In Ditto's distributed system, deletion uses a soft-delete pattern - documents flagged as deleted remain in storage until explicitly evicted to ensure network synchronization across devices.

### Understanding EVICT vs DELETE

**DELETE (Soft Delete):**
- Flags document as deleted
- Creates tombstone for synchronization
- Document remains in local storage
- Tombstone propagates to other peers
- Subject to tombstone TTL

**EVICT (Hard Delete):**
- Actually removes data from local disk
- Local-only operation (does not sync to other peers)
- No tombstone created
- Immediately frees disk space
- Cannot be undone

**Key Principle**: Use DELETE for mesh-wide deletion that needs to propagate. Use EVICT for local storage cleanup.

### EVICT Best Practices

**✅ DO:**
- Run EVICT automatically on a regular schedule
- Execute during periods of minimal disruption (e.g., after hours, at night)
- Limit frequency to once per day maximum (recommended)
- Cancel affected subscriptions before eviction
- Recreate subscriptions after eviction completes
- Use with logical deletion pattern for safe cleanup

```dart
// ✅ GOOD: Scheduled eviction with subscription management
Future<void> performDailyEviction() async {
  // Step 1: Cancel subscriptions that might be affected
  orderSubscription?.cancel();

  // Step 2: Evict old deleted documents (local cleanup)
  final cutoffDate = DateTime.now()
      .subtract(const Duration(days: 90))
      .toIso8601String();

  await ditto.store.execute(
    'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  // Step 3: Recreate subscription with updated query
  orderSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE isDeleted != true AND createdAt > :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}

// Schedule once per day during low-usage period
Timer.periodic(Duration(days: 1), (_) {
  // Run at 3 AM local time or during detected low-usage period
  if (isLowUsagePeriod()) {
    performDailyEviction();
  }
});
```

**❌ DON'T:**
- Run EVICT more than once per day
- Evict during peak usage hours
- Forget to cancel subscriptions before evicting
- Use same query for eviction and subscription (causes resync loop)

```dart
// ❌ BAD: Frequent eviction causing excessive network traffic
Timer.periodic(Duration(hours: 1), (_) {
  // Too frequent! Causes network overhead
  ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
});

// ❌ BAD: Eviction without subscription management
await ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
// Active subscription will immediately resync evicted data!
```

**Why Limit Frequency**: Eviction can trigger resyncs with connected peers if subscriptions overlap with evicted data, potentially creating network traffic and processing overhead. Running EVICT conservatively (once per day during low-usage periods) prevents performance degradation.

### Time-to-Live (TTL) Eviction Strategy

**Two Primary Approaches:**

#### 1. Big Peer (Cloud) Management (RECOMMENDED)

Centralized TTL management where Ditto Server sets eviction flags via HTTP API, and Small Peers evict locally based on those flags.

**Advantages:** Centralized control, prevents data loss (documents sync before eviction), consistent policy across peers.

**Implementation:** Big Peer uses HTTP API to set `evictionFlag = true` on old documents, Small Peers then execute `EVICT FROM orders WHERE evictionFlag = true`.

#### 2. Small Peer Local Management

Each device manages its own TTL-based evictions:

**When to Use:**
- Not using Ditto Server (Big Peer)
- Confident devices won't remain offline longer than eviction cycle
- Need device-specific eviction policies

**Implementation:**
```dart
// ✅ GOOD: Time-based eviction with proper subscription handling
Future<void> evictOldDocuments({required int ttlDays}) async {
  final cutoffDate = DateTime.now()
      .subtract(Duration(days: ttlDays))
      .toIso8601String();

  // Cancel affected subscription
  oldOrdersSubscription?.cancel();

  // Evict old documents
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt <= :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  // Create new subscription excluding evicted timeframe
  oldOrdersSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE createdAt > :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}

// Example: 72-hour TTL for flight ordering system
await evictOldDocuments(ttlDays: 3);
```

### Flag-Based Eviction Pattern

**Use Case**: Centralized eviction control with fine-grained document targeting.

**Step 1**: Declare eviction flag via HTTP API (Big Peer sets flag)
**Step 2**: Query for eviction on Small Peers
**Step 3**: Execute local eviction

```dart
// ✅ GOOD: Flag-based eviction with distinct queries
// Subscription query (opposite of eviction query)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE evictionFlag != true',
);

// Eviction query (targets flagged documents)
await ditto.store.execute(
  'EVICT FROM orders WHERE evictionFlag = true',
);
```

**Critical**: The query used for eviction must be the opposite of the query used for subscription. Using overlapping queries creates a resync loop where Ditto continuously evicts documents and then automatically re-syncs them.

### Storage Management Patterns

**Industry-Specific TTL Examples:**
- Airlines: 72-hour TTL for flight data
- Retail: 7-day TTL for transaction data
- Quick-service restaurants: 24-hour TTL for order data

### Subscription Lifecycle Management

**⚠️ CRITICAL: Top-Level Subscription Declaration**

Declare subscription objects from the top-most scope of your app to ensure access throughout the app lifecycle:

```dart
// ✅ GOOD: Top-level subscription management
class OrderService {
  Subscription? _activeOrdersSubscription;

  Future<void> initialize() async {
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true',
    );
  }

  Future<void> performEviction() async {
    _activeOrdersSubscription?.cancel();
    await ditto.store.execute(
      'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :date',
      arguments: {'date': getOldDate()},
    );
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true',
    );
  }

  void dispose() => _activeOrdersSubscription?.cancel();
}
```

**Why**: Top-level declaration enables subscription access throughout the app lifecycle, essential for canceling before EVICT to prevent resync loops.

### Performance Impact

**Benefits of Proper Storage Management:**
- Faster load times
- Improved battery life
- More responsive UI
- Reduced network usage
- Lower memory footprint

**Risks of Poor Management:**
- Excessive disk usage
- Slower queries
- Battery drain
- Unnecessary network traffic from resync loops
- Performance degradation over time

**Official Reference**: [Ditto Device Storage Management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)

---

## Timestamp Best Practices

### The Timestamp Challenge in Distributed Systems

In Ditto's mesh architecture, **each device operates on its own independent time**, creating significant synchronization challenges. Documents created simultaneously on different devices will have different timestamps, and clock drift can cause seemingly impossible scenarios.

### Clock Drift Reality

**Device Time Accuracy:**
- **iOS devices**: Typically deviate within **100 milliseconds**
- **Android devices**: Can drift by **several seconds** in either direction
- System clock synchronization doesn't guarantee precision
- Even with clock sync enabled, precise accuracy is not guaranteed

**⚠️ CRITICAL**: Never assume device timestamps are reliable in applications requiring precision.

### Recommended Approaches

#### 1. Store Timestamps as ISO-8601 Strings (Recommended)

**Recommended approach**: Use **ISO-8601 formatted date strings** for consistency across platforms and proper querying.

```dart
// ✅ GOOD: Store timestamp as ISO-8601 string
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,
      'createdAt': DateTime.now().toIso8601String(),  // "2025-01-15T10:30:45.123Z"
      'updatedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    },
  },
);

// ✅ GOOD: Query by timestamp range
final result = await ditto.store.execute(
  "SELECT * FROM orders WHERE createdAt >= '2025-01-01T00:00:00Z' AND createdAt < '2025-02-01T00:00:00Z'",
);
```

**Benefits of ISO-8601:**
- International standard format
- Lexicographically sortable (alphabetical sort = chronological sort)
- Platform-independent (no integer overflow concerns across different platforms)
- Human-readable and debugging-friendly
- DQL query-friendly with string comparison

**Alternative: UNIX Timestamps (Epoch Seconds)**
UNIX timestamps (seconds since epoch) are also valid and avoid ISO-8601's platform parsing differences:

```dart
// ✅ ALSO GOOD: UNIX timestamp (seconds since epoch)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,
      'createdAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,  // 1705314645
      'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'status': 'pending',
    },
  },
);

// Query by UNIX timestamp range
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= :start AND createdAt < :end',
  arguments: {
    'start': DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
    'end': DateTime(2025, 2, 1).millisecondsSinceEpoch ~/ 1000,
  },
);
```

**UNIX Timestamp Benefits:**
- No platform parsing differences
- Straightforward numerical sorting and comparison
- Compact storage (integer vs string)
- No timezone ambiguity (always UTC)

**Choose Based On:**
- **ISO-8601**: Prefer for human readability, debugging, and when working with date strings
- **UNIX Timestamp**: Prefer for numerical operations, sorting reliability, and compact storage

#### 2. Anticipate and Handle Time Discrepancies

Build error tolerance into your logic to handle clock drift scenarios.

```dart
// ✅ GOOD: Handle time discrepancies gracefully
class OrderValidator {
  bool isValidOrder(Map<String, dynamic> order) {
    final createdAt = DateTime.parse(order['createdAt']);
    final updatedAt = DateTime.parse(order['updatedAt']);
    final now = DateTime.now();

    // Allow for reasonable clock drift (e.g., 5 minutes)
    const maxClockDrift = Duration(minutes: 5);

    // Check if timestamps are "impossible" (future timestamps)
    if (createdAt.isAfter(now.add(maxClockDrift))) {
      // Device clock is ahead - log warning but accept document
      logger.warning('Order created in future due to clock drift: $orderId');
      return true; // Accept with tolerance
    }

    // Check if updatedAt is before createdAt
    if (updatedAt.isBefore(createdAt.subtract(maxClockDrift))) {
      // Significant clock drift detected
      logger.warning('UpdatedAt before createdAt due to clock drift: $orderId');
      return true; // Accept with tolerance
    }

    return true;
  }
}
```

#### 3. Use Network Time Protocol (NTP) for Critical Applications

For applications demanding high accuracy, synchronize device clocks with authoritative time servers.

```dart
// ✅ GOOD: Use NTP for accurate time
class AccurateTimeService {
  DateTime? _offset;

  Future<void> syncWithNTP() async {
    try {
      final ntpTime = await NTP.now();
      _offset = ntpTime.difference(DateTime.now());
    } catch (e) {
      _offset = null; // Fall back to device time
    }
  }

  DateTime getNow() => _offset != null
    ? DateTime.now().add(_offset!)
    : DateTime.now();

  // Use corrected time in documents
  String getTimestamp() => getNow().toIso8601String();
}
```

#### 4. Alternative Approaches

**Logical Timestamps**: Use sequence numbers instead of wall-clock time for ordering events.
```dart
'sequenceNumber': getNextSequence(), // Monotonic counter
'timestamp': DateTime.now().toIso8601String(), // Reference only
```

**Relative Time**: Calculate durations from known reference points.
```dart
'startTime': startTime.toIso8601String(),
'durationSeconds': DateTime.now().difference(startTime).inSeconds,
```

**Server-Side Timestamping**: Let Ditto Cloud/Big Peer assign authoritative timestamps.
```dart
'clientTimestamp': DateTime.now().toIso8601String(),
// Server adds 'serverTimestamp' during sync
```

### Best Practices

**✅ DO:**
- **Recommended**: Use ISO-8601 formatted timestamps (`DateTime.now().toIso8601String()`) for human readability
- **Alternative**: Use UNIX timestamps (seconds since epoch) for numerical reliability and compact storage
- Anticipate time discrepancies and build error tolerance
- Use NTP synchronization for time-critical applications
- Document your timing assumptions and tolerance ranges
- Choose timestamp format based on your use case (readability vs numerical operations)
- Consider logical ordering (sequence numbers) for event streams
- Store both client and server timestamps for audit trails

**❌ DON'T:**
- Assume device clocks are synchronized across the mesh
- Reject documents solely based on timestamp validation
- Use platform-specific timestamp formats (Unix epoch, platform Date objects)
- Rely on timestamp precision for conflict resolution (use Ditto's CRDT semantics instead)
- Store timestamps as numbers (use ISO-8601 strings)

**Platform-Specific Implementations:**

```dart
// Dart/Flutter
final timestamp = DateTime.now().toIso8601String();

// Swift (iOS)
// let timestamp = ISO8601DateFormatter().string(from: Date())

// Kotlin (Android)
// val timestamp = Instant.now().toString()

// JavaScript/TypeScript
// const timestamp = new Date().toISOString()
```

**Why**: In distributed systems, devices have independent clocks with varying degrees of accuracy. Building time-awareness into your application logic prevents data inconsistencies and handles clock drift gracefully. ISO-8601 ensures cross-platform compatibility and proper query behavior.

**Official Reference**: [Ditto Timestamp Best Practices](https://docs.ditto.live/best-practices/timestamps)

---

## Security Best Practices

### Validate All Inputs

**✅ DO:**
- Validate data before inserting into Ditto
- Sanitize user inputs
- Check data types and ranges

```dart
// ✅ GOOD: Input validation
Future<void> createOrder(String? customerId, List<dynamic>? items) async {
  if (customerId == null || customerId.isEmpty) {
    throw ArgumentError('Invalid customerId');
  }
  if (items == null || items.isEmpty) {
    throw ArgumentError('Invalid items');
  }

  final order = {
    '_id': generateId(),
    'customerId': customerId,
    'items': items.map((item) => {
      'productId': item['productId'].toString(),
      'quantity': max(1, (item['quantity'] as num).floor()),
    }).toList(),
    'createdAt': DateTime.now().toIso8601String(),
  };

  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {'order': order},
  );
}
```

**Why**: Ditto is schema-less, so application-level validation is critical.

---

### Authentication and Authorization

Ditto provides three authentication mechanisms for different deployment scenarios. Choosing the correct authentication mode is critical for security and proper data access control.

#### Authentication Modes

**1. Online Playground (Development Only)**

**Purpose**: Development, testing, demos, hackathons

**How it works**:
- Devices connect via Ditto Server using shared app ID and Playground token
- Functions like a static API key shared by all clients
- No per-user identity or differentiation

**Security level**: ⚠️ **NOT SECURE** - Unsuitable for production or sensitive data

```dart
// ✅ GOOD: Online Playground for development only
final ditto = await Ditto.open(
  identity: OnlinePlaygroundIdentity(
    appId: 'your-app-id',
    token: 'your-playground-token',
  ),
);
```

**⚠️ Limitations**:
- All clients have identical access
- No user-level permissions
- Shared static token (anyone with token has full access)
- Should NEVER be used with sensitive data

---

**2. Online with Authentication (Recommended for Production)**

**Purpose**: Production deployments requiring user identity verification and granular permissions

**How it works**:
1. Client authenticates with your identity system (e.g., your backend API)
2. Client retrieves a secret token (often JWT format)
3. Token passed to Ditto's `authenticator` callback
4. Authentication webhook validates and decodes token
5. Server returns user identity and permission information

**Security level**: ✅ **Enterprise-grade** with fine-grained access control

```dart
// ✅ GOOD: Online with Authentication for production
final ditto = await Ditto.open(
  identity: OnlineWithAuthenticationIdentity(
    authenticationDelegate: MyAuthenticationDelegate(),
    appId: 'your-app-id',
  ),
);

class MyAuthenticationDelegate extends DittoAuthenticationDelegate {
  @override
  Future<String?> authenticationRequired(DittoAuthenticator authenticator) async {
    // 1. Authenticate with your backend
    final token = await myBackend.login(username, password);

    // 2. Pass token to Ditto
    await authenticator.loginWithToken(token);

    return null;
  }

  @override
  Future<void> authenticationExpiringSoon(
    DittoAuthenticator authenticator,
    int secondsRemaining,
  ) async {
    // Refresh token before expiration
    final newToken = await myBackend.refreshToken();
    await authenticator.loginWithToken(newToken);
  }
}
```

**Permission Structure**:

Permissions are expressed as collection-level DQL queries with read/write capabilities:

```json
{
  "authenticated": true,
  "userID": "user_123",
  "expirationSeconds": 28800,
  "permissions": {
    "read": {
      "queriesByCollection": {
        "orders": ["_id.userId == 'user_123'"],
        "products": ["true"]
      }
    },
    "write": {
      "queriesByCollection": {
        "orders": ["_id.userId == 'user_123'"]
      }
    }
  }
}
```

**⚠️ CRITICAL Permission Constraint**: Permissions can **only** be specified on the immutable `_id` field

**Key Benefits**:
- Each user/device has distinct identity
- Fine-grained authorization rules per user
- Role-based access control (viewer, editor, admin)
- Token expiration and refresh mechanism
- Server-side permission enforcement

---

**3. Offline Shared Key (Air-Gapped Environments)**

**Purpose**: Closed, controlled environments without cloud connectivity

**How it works**:
- All peers share a single secret cryptographic key
- Self-signed TLS certificates using supplied private key
- Trust model: Any peer with the shared key is trusted

**Security level**: ⚠️ **Requires controlled key distribution** (recommend MDM)

```dart
// ✅ GOOD: Offline Shared Key for air-gapped deployments
final ditto = await Ditto.open(
  identity: SharedKeyIdentity(
    appId: 'your-app-id',
    sharedKey: 'your-shared-key',
  ),
);
```

**Ideal for**:
- Air-gapped deployments
- Managed device fleets (MDM distribution)
- Offline-first operations
- Closed, controlled networks

**⚠️ Limitations**:
- No peer-level revocation capability
- Single leaked key compromises entire system
- **Key leakage risk**: Keys hardcoded in applications can be extracted via reverse engineering (decompiling APK/IPA files)
- No granular security controls
- Requires offline-only license token (contact: [email protected])

---

#### Best Practices

**✅ DO:**
- **Use Online with Authentication for production** with real users and sensitive data
- Model data so access-controlled fields exist in `_id` (e.g., `_id.userId`, `_id.organizationId`)
- Implement webhook validation in your authentication service
- Use token expiration and refresh mechanisms
- Validate permissions at application level as additional security layer
- Use MDM for Shared Key distribution in managed environments

**❌ DON'T:**
- Use Online Playground in production or with sensitive data
- Use Shared Key without controlled distribution mechanism
- **Hardcode Shared Keys in application code** (vulnerable to reverse engineering attacks)
- Rely solely on client-side permission checks
- Store sensitive data without proper authentication mode
- Specify permissions on mutable fields (only `_id` is allowed)

**Security Notes**:
- **Transport encryption**: All authentication modes use TLS 1.3 (mTLS) by default to encrypt data in transit between peers
- **Storage encryption**: Data in the local Ditto store is **not encrypted at rest in current versions** by default. For sensitive data, consider implementing application-level encryption before storing in Ditto, or use platform-specific storage encryption (e.g., iOS Data Protection, Android Full Disk Encryption)
- **Shared Key security risk**: Hardcoded keys in mobile apps are vulnerable to reverse engineering. Attackers can decompile APK/IPA files to extract keys. Use MDM or secure key provisioning for controlled distribution
- Permissions enforced by both Ditto Server and participating devices
- Unauthorized documents won't synchronize across mesh
- Generate shared keys using `ditto-authtool` utility or OpenSSL

**Why**: Proper authentication ensures authorized access to synced data. Online Playground provides no security and is only suitable for development/testing. Production apps require Online with Authentication for user identity and fine-grained permissions.

---

## Query Optimization & Indexing

### DQL Indexes (SDK 4.12.0+)

Ditto SDK 4.12.0+ supports **simple indexes on single fields** to dramatically improve query performance for large datasets.

**Availability:**
- ✅ SDK `execute` API (SDK 4.12+)
- ✅ SDK `registerObserver` API (SDK 4.12+)
- ❌ SDK `registerSubscription` API (not supported in current versions)
- ❌ Ditto Server HTTP API (not supported in current versions)
- ❌ In-memory storage SDKs (not supported in current versions)

### Creating and Managing Indexes

**Basic Syntax:**

```dart
// ✅ GOOD: Create index with IF NOT EXISTS for idempotent operations
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)');

// Create index on nested field (dot notation)
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_user_location ON users (address.city)');

// Drop index safely
await ditto.store.execute('DROP INDEX IF EXISTS idx_orders_status');

// View all indexes
final result = await ditto.store.execute('SELECT * FROM system:indexes');
```

**✅ DO:**
- Create indexes during application initialization (batch creation at startup)
- Use `IF NOT EXISTS` clause to prevent errors in initialization scripts
- Index frequently queried fields in WHERE clauses
- Index fields used in ORDER BY clauses
- Monitor indexes using `system:indexes` collection
- Remove unused indexes to improve write performance

**❌ DON'T:**
- Create indexes on-demand during runtime (performance impact from full collection scans)
- Create duplicate indexes with same name (query `system:indexes` first to check)
- Index fields that are rarely queried
- Create indexes without measuring actual performance benefits

### Performance Impact and Query Selectivity

Index effectiveness is **inversely related to query selectivity** (percentage of documents returned):

**Highly Selective Queries** (return <10% of documents):
- ~90% faster with appropriate indexes
- Index allows skipping 90% of documents entirely
- Best use case for indexing

**Less Selective Queries** (return >50% of documents):
- Minimal performance benefit
- Most documents still require examination
- Index overhead may not be justified

**Example:**

```dart
// ✅ GOOD: Highly selective query benefits from index
// If only 5% of orders have status 'pending':
await ditto.store.execute(
  'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)',
);
final result = await ditto.store.execute(
  "SELECT * FROM orders WHERE status = 'pending'",
); // ~90% faster with index

// ⚠️ CAUTION: Less selective query - limited benefit
// If 60% of users have isActive = true:
await ditto.store.execute(
  'CREATE INDEX IF NOT EXISTS idx_users_active ON users (isActive)',
);
final result = await ditto.store.execute(
  "SELECT * FROM users WHERE isActive = true",
); // Minimal performance gain
```

### Advanced Index Usage (SDK 4.13.0+)

**Union and Intersect Scans** enable multiple indexes to be used simultaneously:

**Union Scans** (OR, IN operators):

```dart
// Create indexes for both fields
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)');
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_priority ON orders (priority)');

// Query uses BOTH indexes via union scan
final result = await ditto.store.execute(
  "SELECT * FROM orders WHERE status = 'active' OR priority = 'high'",
); // Combines results from both index scans - much faster than full collection scan
```

**Intersect Scans** (AND operators):

```dart
// Create indexes for both fields
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks (category)');
await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON tasks (assignee)');

// Query uses BOTH indexes via intersect scan
final result = await ditto.store.execute(
  "SELECT * FROM tasks WHERE category = 'urgent' AND assignee = 'user123'",
); // Intersects results from both indexes - efficiently narrows matches
```

### Query Plan Analysis with EXPLAIN

Use `EXPLAIN` to verify index usage:

```dart
// ✅ GOOD: Use EXPLAIN to verify query plan
final result = await ditto.store.execute(
  "EXPLAIN SELECT * FROM orders WHERE status = 'pending'",
);
// Check for "indexScan", "unionScan", or "intersectScan" operators in plan
```

### Index Limitations and Considerations

**Current Limitations:**

| Limitation | Description |
|------------|-------------|
| **Single field only** | Composite indexes on multiple fields not supported in current versions |
| **No partial indexes** | Cannot create indexes with WHERE conditions in current versions |
| **No functional indexes** | Cannot index computed values or expressions in current versions |
| **OR queries unsupported (4.12)** | SDK 4.12 cannot use indexes with OR; requires 4.13+ for union scans |
| **NOT operations** | Queries with NOT operators cannot use indexes in current versions |
| **Non-deterministic functions** | Cannot index results of functions like `CURRENT_TIMESTAMP()` in current versions |

**Supported Index Types:**
- ✅ Simple fields: `orders (status)`
- ✅ Nested fields: `users (address.city)`
- ✅ LIKE prefix patterns: `products (name LIKE 'Apple%')` (effective)
- ❌ LIKE suffix patterns: `products (name LIKE '%Phone')` (ineffective)

**Not Yet Supported** (potential future features):
- Composite indexes (multiple fields)
- Partial indexes with WHERE conditions
- Functional indexes
- Tombstone indexing
- Array and object field indexing

### Index Usage Best Practices

**✅ DO:**
- Create indexes on fields used in WHERE clauses for highly selective queries (<10% of documents)
- Create indexes on fields used in ORDER BY clauses
- Use `IF NOT EXISTS` during initialization for idempotent operations
- Batch index creation during application startup
- Monitor query performance with `EXPLAIN` before and after indexing
- Remove unused indexes to optimize write performance and storage

**❌ DON'T:**
- Create indexes without measuring performance impact
- Over-index collections (each index adds write overhead and storage cost)
- Create indexes on fields that return >50% of documents (minimal benefit)
- Assume indexes automatically improve all queries (measure with `EXPLAIN`)
- Create indexes in response to individual slow queries (analyze query patterns first)

**Why**: Indexes dramatically improve read performance for selective queries but add write overhead and storage cost. Strategic indexing based on actual query patterns and selectivity provides optimal balance.

**Official Reference**: [Ditto DQL Indexing Documentation](https://docs.ditto.live/dql/indexing)

---

## Logging & Observability

### Log Levels

Ditto SDK provides four log levels for controlling console output and disk logging:

| Level | Use Case | Console | Disk (File Logging) |
|-------|----------|---------|---------------------|
| **DEBUG** | Development, troubleshooting | Configurable | Always enabled (default) |
| **INFO** | Normal operation, health monitoring | Configurable | Always enabled |
| **WARN** | Potential issues, recoverable errors | Configurable (default) | Always enabled |
| **ERROR** | Critical errors requiring attention | Configurable | Always enabled |

**Key Principle**: Console log level is configurable, but disk logging **always logs at DEBUG level** regardless of console settings, ensuring comprehensive diagnostics for remote troubleshooting.

### Configuring Log Levels

**✅ DO:**
- Set log level **before** initializing Ditto to capture startup issues (authentication, file system access)
- Use WARN level for production console output (default)
- Use DEBUG level temporarily for troubleshooting specific issues
- Enable DEBUG console logging during development for immediate feedback

```dart
// ✅ GOOD: Set log level before Ditto initialization (Flutter/Dart)
import 'package:ditto_flutter/ditto_flutter.dart';

void main() async {
  // Set log level BEFORE opening Ditto
  DittoLogger.minimumLogLevel = DittoLogLevel.debug;

  final ditto = await Ditto.open(
    identity: OnlinePlayground(appId: appId, token: token),
  );

  await ditto.startSync();
}
```

**❌ DON'T:**
- Set log level after Ditto initialization (may miss critical startup errors)
- Leave DEBUG console logging enabled in production (performance impact, log noise)
- Ignore log output during development

### Rotating File Logs

Ditto SDK includes **automatic log file rotation and compression** for disk-based logging:

**Configuration Parameters:**

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| `rotating_log_file_max_size_mb` | 1MB | 1MB-1GB | Triggers rotation when file reaches size limit |
| `rotating_log_file_max_age_h` | 24 hours | 1+ hours | Triggers rotation based on file age |
| `rotating_log_file_max_files_on_disk` | 15 files | 3-64 files | Maximum number of compressed log files retained |

**Features:**
- **Automatic compression**: Rotated files compress from `.log` to `.log.gz` (reduces disk usage by ~90%)
- **Background processing**: Compression occurs on separate thread without blocking operations
- **Crash recovery**: Uncompressed files from crashes are automatically compressed on next startup
- **Consistent DEBUG logging**: Disk logs always at DEBUG level, independent of console settings
- **File naming**: `ditto-logs-YYYY-MM-DD-HH-MM-SS.microseconds.log`

**Default Configuration Impact:**
- Disk usage: ~15MB (15 files × 1MB compressed)
- Retention: 24-hour rolling window per file

### Logging Best Practices

**Development:**

```dart
// ✅ GOOD: DEBUG console logging for development
DittoLogger.minimumLogLevel = DittoLogLevel.debug;
```

**Production:**

```dart
// ✅ GOOD: WARN/ERROR console logging for production
DittoLogger.minimumLogLevel = DittoLogLevel.warning;
// Note: Disk logging remains at DEBUG for diagnostics
```

**✅ DO:**
- Monitor INFO-level logs in production to understand SDK health and state
- Collect and analyze disk logs from devices for remote troubleshooting
- Use centralized log aggregation for production deployments
- Temporarily increase console log level to DEBUG when investigating specific issues
- Review connection lifecycle logs (transport started/ended, physical connections)

**❌ DON'T:**
- Run production with DEBUG console logging (performance overhead, excessive output)
- Ignore rotating log configuration in long-running applications
- Disable logging entirely (removes critical diagnostic capability)
- Log sensitive data (credentials, PII) in application code

**Why**: Ditto's logging system is designed for **remote observability and device diagnostics**. Disk logs at DEBUG level enable comprehensive troubleshooting of deployed devices, while configurable console logging reduces noise during normal operation.

### System Information Query

Ditto SDK 4.13.0+ provides a read-only `system:system_info` collection for runtime diagnostics:

```dart
// ✅ GOOD: Query current logging configuration
final result = await ditto.store.execute(
  "SELECT * FROM system:system_info WHERE namespace = 'logs'",
);

// Returns:
// - enabled: Whether logging is enabled
// - minimum_level: Current console log level (DEBUG, INFO, WARN, ERROR)
```

**⚠️ Note**: Observers on `system:system_info` execute every 500ms regardless of data changes. Consider performance implications on resource-constrained devices.

**Official Reference**: [Ditto SDK Logging Documentation](https://docs.ditto.live/sdk/latest/deployment/logging)

---

## Anti-Pattern Detection Checklist

### Immediate Rejection (CRITICAL)

- [ ] **Using mutable arrays for concurrent updates** (use MAP/object structures instead)
- [ ] Modifying individual array elements after creation (arrays should be append-only or read-only)
- [ ] Using DELETE without tombstone TTL strategy
- [ ] Forgetting to filter `isDeleted` in queries (if using logical deletion)
- [ ] Querying without active subscription (subscription = replication query)
- [ ] Full document replacement instead of field updates
- [ ] Using DO UPDATE instead of DO UPDATE_LOCAL_DIFF for upserts (SDK 4.12+) - causes unnecessary sync of unchanged fields
- [ ] Subscriptions/observers without cancel/cleanup (causes memory leaks)
- [ ] Using Online Playground identity in production environments
- [ ] Assuming attachments auto-sync (they require explicit fetch)
- [ ] **Using `registerObserver` for most use cases** (prefer `registerObserverWithSignalNext` for better performance - use `registerObserver` only for very simple data processing)
- [ ] Not calling `signalNext()` in `registerObserverWithSignalNext` callbacks
- [ ] Storing large binary data inline with documents (use ATTACHMENT type)
- [ ] Modifying existing attachments (they're immutable - replace token instead)
- [ ] **Retaining QueryResultItems in state/storage** (treat as database cursors, extract data immediately)
- [ ] **Nesting read-write transactions** (causes permanent deadlock - non-Flutter platforms only)
- [ ] Using `ditto.store` instead of transaction object within transaction blocks (non-Flutter platforms)
- [ ] **Running EVICT without canceling affected subscriptions** (causes resync loop)

### High-Priority Issues

- [ ] Over-normalized data structures requiring foreign key lookups (no JOIN support = sequential query overhead)
- [ ] Counter updates using set instead of increment
- [ ] Broad subscriptions without WHERE clauses
- [ ] No conflict testing in test suite
- [ ] Missing input validation before upsert
- [ ] Zombie data scenarios not considered
- [ ] Not handling attachment fetch errors gracefully
- [ ] Missing metadata when storing attachments
- [ ] Canceling attachment fetchers before completion
- [ ] Using DELETE for documents that may be updated concurrently (causes husked documents)
- [ ] Deleting 50,000+ documents at once without LIMIT (performance impact)
- [ ] Setting Edge SDK TTL larger than Cloud TTL (30 days)
- [ ] Not filtering out husked documents (null required fields) in queries
- [ ] Long-running operations inside transaction blocks (blocks other transactions - non-Flutter platforms)
- [ ] Using `ditto.store.transaction()` in Flutter (not supported in current versions - use sequential DQL statements)
- [ ] Running EVICT more than once per day (causes excessive network traffic)
- [ ] Using same query for eviction and subscription (causes resync loop)
- [ ] Declaring subscriptions in local scope instead of top-level (cannot manage lifecycle)

### Medium-Priority Issues

- [ ] Updating fields with the same value (creates unnecessary deltas and sync traffic)
- [ ] Not using batch operations for related updates
- [ ] Inefficient query patterns
- [ ] Missing error handling for sync failures
- [ ] No strategy for large document handling
- [ ] Insufficient logging for sync events
- [ ] No storage management strategy (EVICT) for long-running apps
- [ ] Running EVICT during peak usage hours

---

## Quick Reference

**When implementing Ditto features:**

### API Usage (CRITICAL)
1. ✅ **Use DQL string queries**: `ditto.store.execute(query, args)`
2. ✅ **Avoid legacy builder API** (deprecated SDK 4.12+, removed in v5): `.collection()`, `.find()`, `.findById()`, `.update()`, `.upsert()`, `.remove()`, `.exec()` — **Note: Flutter SDK never had this legacy API**
3. ✅ Use `ditto.sync.registerSubscription(query, args)` for subscriptions
4. ✅ Prefer `ditto.store.registerObserverWithSignalNext(query, callback, args)` for observers (better performance, recommended for most use cases)
5. ✅ Reference official Ditto documentation before writing code

### Core Principles
6. ✅ Design data models for distributed merge (CRDT-friendly)
7. ✅ Understand offline-first: devices work independently and sync later
8. ✅ Always consider how concurrent edits will merge

### Data Operations
9. ✅ Use field-level UPDATE statements, not INSERT with DO UPDATE
10. ✅ **CRITICAL: Check if values changed before UPDATE** - updating with the same value creates unnecessary deltas and sync traffic
11. ✅ **RECOMMENDED: Use DO UPDATE_LOCAL_DIFF (SDK 4.12+)** for upserts - only syncs fields that differ from existing document
12. ✅ **Use INITIAL DOCUMENTS for device-local templates and seed data** - prevents unnecessary sync traffic
13. ✅ **CRITICAL: Use logical deletion for critical data** (avoid husked documents from concurrent DELETE/UPDATE)
14. ✅ Understand tombstone TTL risks: ensure all devices connect within TTL window (Cloud: 30 days)
15. ✅ **Warning: Tombstones only shared with devices that have seen the document before deletion**
16. ✅ Use `LIMIT 30000` for batch deletions of 50,000+ documents (performance)
17. ✅ Use PN_INCREMENT for counters
18. ✅ **CRITICAL: Use separate documents (INSERT) for event logs and audit trails** - arrays are REGISTERS (last-write-wins)
19. ✅ **Embed related data retrieved together** (no JOIN support = sequential query overhead); use flat models only for data accessed independently or growing unbounded
20. ✅ **CRITICAL: Avoid mutable arrays** - use MAP (object) structures instead for concurrent updates
21. ✅ Only embed read-only arrays that never change after creation
22. ✅ Fetch attachments explicitly (they don't auto-sync with subscriptions)
23. ✅ Keep documents under 250 KB (hard limit: 5 MB)
24. ✅ Store large binary files (>250 KB) as ATTACHMENT type
25. ✅ Balance embed vs flat based on access patterns: embed for data retrieved together, flat for independent access or unbounded growth
26. ✅ Filter out husked documents by checking null required fields in queries

### Queries & Subscriptions
27. ✅ Understand that queries without subscriptions return only local data (subscriptions tell peers what data to sync)
28. ✅ Maintain subscriptions appropriately: avoid frequent start/stop cycles, but cancel when feature is disposed or before EVICT
29. ✅ Use Local Store Observers for real-time updates (observers receive initial local data + synced updates)
30. ✅ Filter out logically deleted documents in all queries (e.g., `isDeleted != true`, `isArchived != true`)
31. ✅ Use specific WHERE clauses with parameterized arguments
32. ✅ Cancel subscriptions and observers when feature is disposed to prevent memory leaks and notify peers

### Query Optimization & Indexing (SDK 4.12+)
33. ✅ **Create indexes for highly selective queries** (<10% of documents) - ~90% faster performance
34. ✅ Index fields used in WHERE and ORDER BY clauses
35. ✅ Use `IF NOT EXISTS` when creating indexes during initialization (idempotent)
36. ✅ Batch index creation during application startup, not on-demand at runtime
37. ✅ Monitor indexes with `SELECT * FROM system:indexes`
38. ✅ Use `EXPLAIN` to verify query plans and index usage
39. ✅ Remove unused indexes (each index adds write overhead and storage cost)
40. ✅ **SDK 4.13+**: Leverage union scans (OR, IN) and intersect scans (AND) with multiple indexes
41. ✅ **CRITICAL: Treat QueryResults as database cursors** - extract data immediately, don't retain QueryResultItems
42. ✅ Use `value` property for default format, `cborData()` for binary, `jsonString()` for JSON serialization
43. ✅ Understand lazy-loading: items materialize only when accessed (memory efficiency)
44. ✅ Use `DittoDiffer` to track changes (insertions, deletions, updates, moves) between query results
45. ✅ **CRITICAL: Prefer `registerObserverWithSignalNext` for all observers** (better performance, recommended for most use cases)
46. ✅ **CRITICAL: Keep observer callbacks lightweight** - extract data and update UI only; offload heavy processing to async operations
47. ✅ Call `signalNext()` after render cycle completes to control backpressure
48. ✅ Use `registerObserver()` only for very simple, synchronous data processing (worse performance)
49. ✅ Understand delta sync: only field-level changes are transmitted

### Testing
50. ✅ Test with multiple Ditto stores to simulate conflicts
51. ✅ Test deletion scenarios (tombstones, logical deletion, zombie data, husked documents)
52. ✅ Verify concurrent edits merge correctly
53. ✅ Test array merge scenarios if using arrays

### Performance & Transactions
54. ✅ **Transactions**: Use `ditto.store.transaction()` for atomic multi-step operations (not available in current Flutter SDK versions - use sequential DQL)
55. ✅ **CRITICAL (non-Flutter)**: Never nest read-write transactions (causes deadlock), keep transaction blocks fast (milliseconds, not seconds)
56. ✅ Optimize subscription scope with WHERE clauses
57. ✅ Leverage delta sync for bandwidth efficiency

### Storage Management
58. ✅ **CRITICAL: Cancel subscriptions before EVICT** - prevents resync loop where evicted data immediately resyncs
59. ✅ Run EVICT once per day maximum (recommended) during low-usage periods (e.g., after hours)
60. ✅ Use opposite queries for eviction and subscription (prevents conflicts)
61. ✅ Declare subscriptions at top-level scope (enables lifecycle management)
62. ✅ Use Big Peer (Cloud) TTL management when possible (centralized, prevents data loss)
63. ✅ Implement time-based eviction for time-sensitive data (airlines: 72hr, retail: 7 days, QSR: 24hr)

### Attachments
64. ✅ **CRITICAL: Fetch attachments explicitly** (they don't auto-sync with subscriptions)
65. ✅ Use lazy-load pattern: fetch only when needed
66. ✅ Store metadata with attachments (filename, size, type, description)
67. ✅ Keep attachment fetchers active until completion
68. ✅ Replace immutable attachments by creating new token and updating document

### Security
69. ✅ Validate all inputs (Ditto is schema-less)
70. ✅ Use proper identity configuration (Online with Authentication for production, not Online Playground)
71. ✅ Define granular permissions using DQL-based permission queries
72. ✅ Validate permissions at application level as additional security layer

### Logging & Observability
73. ✅ **CRITICAL: Set log level BEFORE Ditto initialization** - captures authentication and file system startup issues
74. ✅ Use WARN/ERROR console logging in production (default), DEBUG for development/troubleshooting
75. ✅ Disk logging always runs at DEBUG level (independent of console settings) for remote diagnostics
76. ✅ Monitor INFO-level logs in production to understand SDK health and connection state
77. ✅ Collect and centralize disk logs from deployed devices for troubleshooting
78. ✅ Review rotating log configuration for long-running applications (~15MB default)
79. ✅ **CRITICAL: Balance subscription query scope** - too broad wastes resources, too narrow breaks multi-hop relay (intermediate peers can't relay documents they don't store)
80. ✅ **CRITICAL: Exclude unnecessary fields from documents** - UI state, computed values, temp state shouldn't sync
81. ✅ **CRITICAL: Design partial UI updates** - Observer callbacks should update only affected UI components, not entire screen

---

## Glossary

This glossary defines key Ditto-specific terms and concepts. For comprehensive definitions, see the [official Ditto glossary](https://docs.ditto.live/home/glossary).

### Core Concepts

**Application**: A logical namespace containing all data associated with your app. In Ditto, this is the top-level container for your documents and collections.

**Collection**: A grouping of documents under a name. Loosely equivalent to a table in SQL terms.

**Document**: A schema-flexible unit of data contained in a collection; analogous to a row in a table.

**Peer**: An instance of Ditto SDK running within an application. Each peer has a unique identity and participates in the mesh network independently.

**Device**: A physical hardware unit (smartphone, tablet, IoT device, etc.). A single device can host multiple peers when running multiple Ditto-enabled applications or multiple Ditto instances within one application.

**Small Peer**: A peer running on edge devices (mobile devices, IoT devices, embedded systems), as opposed to cloud infrastructure.

**Ditto Server**: Cloud cluster augmenting SDK capabilities with cloud sync, identity management, and monitoring features. Formerly called "Big Peer."

### CRDTs and Conflict Resolution

**CRDT (Conflict-Free Replicated Data Type)**: Data structure enabling concurrent updates across distributed peers without consensus requirements. CRDTs automatically merge conflicting changes based on mathematical properties.

**CRDT Types in Ditto:**
- **REGISTER**: Stores scalar values (strings, numbers, booleans) using last-write-wins strategy
- **MAP**: Stores object properties using add-wins strategy for automatic concurrent merge
- **Array**: Limited CRDT support - avoid for mutable data due to merge conflicts

**Actor**: An identifier used by CRDTs to track the source of data mutations, composed of a SiteID and the site's current epoch.

**Hybrid Logical Clock (HLC)**: Used to track when mutations occurred to a CRDT, combining a physical clock portion with a logical portion for ordering events.

**Version Vector**: Tracking mechanism for document state across peers. Each change increments the document version, enabling peers to determine if incoming changes are new.

**SiteID**: Unique peer identifier for CRDT document mutations, being phased out in favor of Peer Key.

**Peer Key**: A P-256 private key generated and persisted for each Ditto peer instance, serving as the primary unique identifier for that peer.

**Epoch**: A version identifier for peer CRDT knowledge, changing when peers perform data eviction.

### Sync and Networking

**Subscription**: Query expressing which data a peer requests from others for synchronization. Subscriptions tell Ditto what to sync.

**Local Store Observer**: Object monitoring database changes in the local store matching a given query over time, enabling real-time UI updates.

**Replication Query**: Query running on connected peers transmitting relevant changes back to the initiating peer.

**Delta Sync**: Bandwidth optimization technique where only field-level changes (not entire documents) are transmitted. ⚠️ Important: Even updating a field with the same value is treated as a change and synced as a delta. Minimizes network usage, especially important for battery-constrained devices and low-bandwidth connections.

**Transports**: Physical transport mechanisms (Bluetooth, WebSockets, AWDL, LAN) establishing secured peer connections.

**Mesh**: A network topology where peers connect directly to each other (peer-to-peer) without requiring a central server.

**Link**: Encrypted connection between non-directly-connected peers routed through intermediaries for multihop sync and Ditto Bus.

**Multiplexer**: Synchronous machine performing packet fragmentation and reassembly across multiple Physical Connections.

### Data Lifecycle

**Eviction**: Process for peers to deliberately forget data rather than permanently deleting it. Eviction is local-only and does not sync.

**Tombstone**: A deletion marker created when documents are deleted with `DELETE` DQL statements. Tombstones have TTL (Time To Live) and eventually expire.

**Logical Deletion**: Soft delete pattern where documents are marked as deleted (e.g., `isDeleted: true`) but not physically removed, avoiding zombie data problems.

**Zombie Data**: Deleted data that reappears from previously disconnected devices after tombstone TTL has expired.

### Identity and Security

**Identity**: Complex startup parameter defining authentication, peer verification, and Application identity confirmation modes.

**Certificate Authority (CA)**: The cryptographic root of trust for all identities and certificates within a Ditto Application.

**Identity Service**: Part of Ditto Server handling login requests and generating cryptographic authentication material.

**Online Playground**: Identity type where peers require no unique credentials and everyone has universal read-write access. Only for development/testing.

**Permission**: Specification of readable or writable documents for a peer, presented as collection names with DQL query lists.

**Authentication WebHook**: An HTTP service receiving credentials and responding with user metadata and permission information for dynamic certificate generation.

### Storage and Attachments

**Backend**: The underlying key-value store providing database-like persistence for Ditto.

**Attachment**: Component handling large binary file storage associated with documents, requiring explicit download separate from regular replication.

**Blob Store**: Internal component offering general blob storage for Ditto's persistent file needs.

### Advanced Features

**Bus**: Public service enabling raw byte streams between peers via the Ditto mesh for applications beyond document replication.

**Channel**: Bidirectional message-oriented data flow over Virtual Connections offering reliable or lossy delivery characteristics.

**Service**: Handles Channels providing specific functionality, with Replication Service performing document sync.

**Change Data Capture (CDC)**: System tracking data modifications for integration purposes.

**Presence Viewer**: Component building a picture of surrounding mesh peers including SDK versions and active transports.

### Deployment Models

**BYOC (Bring Your Own Cloud)**: Deployment model where customers share responsibility over their cloud account with Ditto.

**Portal**: Self-service website at https://portal.ditto.live for creating and managing cloud Applications.

### Protocols and Technologies

**DQL (Ditto Query Language)**: SQL-like query language for interacting with Ditto documents. See the [Query Language](#ditto-query-language-dql) section for details.

**AWDL (Apple Wireless Direct Link)**: A proprietary Apple-developed technology that establishes a point-to-point Wi-Fi connection between two Apple devices.

**Peer-to-Peer Wi-Fi**: Direct WiFi mechanisms between devices without routers, including AWDL and WiFi Aware technologies.

**L2CAP (Logical Link Control Adaptation Protocol)**: Faster Bluetooth LE transport mode at lower complexity than GATT, supporting ~20 kB/s speeds.

**GATT (Generic ATTribute Profile)**: An older, slower mode of Bluetooth LE data transfer which has typical speed of 3 to 6 kB/s.

**Ditto Routing Protocol**: Custom OSPF-like shortest-path-first interior routing protocol for multi-hop mesh packets.

---

## References

- [Ditto Official Documentation](https://docs.ditto.live/)
- [Ditto Glossary](https://docs.ditto.live/home/glossary)
- [Ditto Document Model](https://docs.ditto.live/key-concepts/document-model)
- [Ditto Syncing Data](https://docs.ditto.live/key-concepts/syncing-data)
- [Ditto CRUD: Read](https://docs.ditto.live/sdk/latest/crud/read)
- [Ditto CRUD: Delete](https://docs.ditto.live/sdk/latest/crud/delete)
- [Ditto CRUD: Transactions](https://docs.ditto.live/sdk/latest/crud/transactions)
- [Ditto CRUD: Working with Attachments](https://docs.ditto.live/sdk/latest/crud/working-with-attachments)
- [Ditto CRUD: Observing Data Changes](https://docs.ditto.live/sdk/v5/crud/observing-data-changes)
- [Ditto Sync: Device Storage Management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)
- [Ditto Query Language (DQL)](https://docs.ditto.live/sdk/latest/query-language)
- [Ditto DQL Strict Mode](https://docs.ditto.live/dql/strict-mode)
- [Ditto Best Practices: Data Modeling](https://docs.ditto.live/best-practices/data-modeling)
- [Ditto SDK Reference](https://docs.ditto.live/sdk/latest/)
- [Understanding CRDTs](https://crdt.tech/)

---

## Disclaimer

This document provides best practices and recommendations based on our experience and understanding of Ditto SDK. While we strive to keep this information accurate and up-to-date, technology evolves rapidly, and your specific use case may differ.

We encourage you to:
- Always refer to the [official Ditto documentation](https://docs.ditto.live/) for the most current information
- Test thoroughly in your own environment before deploying to production
- Adapt these patterns to fit your specific requirements

This guide is provided "as is" for educational and reference purposes. We are not responsible for any issues that may arise from implementing these patterns in your projects. Your use of this information is at your own discretion and risk.

---

**Last Updated**: 2025-12-16
