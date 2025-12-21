---
name: ditto-data-modeling
description: |
  CRDT-safe data structure design and merge safety for Ditto SDK.

  CRITICAL ISSUES PREVENTED:
  - Data loss from mutable arrays (last-write-wins conflicts)
  - Counter race conditions (incorrect increment/decrement)
  - Over-normalization causing query performance issues
  - Calculated field storage (violates single source of truth)
  - Document size limit violations (250 KB)

  TRIGGERS:
  - Designing document schemas
  - Using arrays with mutable objects
  - Modeling relationships (embed vs flat)
  - Implementing counters (likes, views, inventory)
  - Creating event history or audit logs
  - Generating IDs for distributed systems

  PLATFORMS: Flutter (Dart), JavaScript, Swift, Kotlin (cross-platform CRDT rules)
---

# Ditto Data Modeling Skill

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Platform Detection](#platform-detection)
- [SDK Version Compatibility](#sdk-version-compatibility)
- [Common Workflows](#common-workflows)
- [Critical Patterns](#critical-patterns)
  - [Pattern 1: Mutable Arrays → MAP Structures](#pattern-1-mutable-arrays--map-structures-critical)
  - [Pattern 2: Denormalization for Query Performance](#pattern-2-denormalization-for-query-performance-critical)
  - [Pattern 2.5: DO NOT Store Calculated Fields](#pattern-25-do-not-store-calculated-fields-critical)
  - [Pattern 4: Counter Patterns](#pattern-4-counter-patterns-counter-type-and-pn_increment-critical)
  - [Pattern 10: ID Generation](#pattern-10-id-generation-for-distributed-systems-critical)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## Purpose

This Skill helps you design CRDT-safe data structures for Ditto SDK that prevent merge conflicts and data corruption in distributed, offline-first environments. It covers critical patterns for document schema design, relationship modeling, and merge-safe operations.

---

## When This Skill Applies

**Trigger when you see:**
1. **Document schema design**: Designing or reviewing document structure for Ditto collections
2. **Array usage**: Documents with arrays containing mutable objects
3. **Relationship modeling**: Deciding between embedded (nested) vs flat (foreign key) data structures
4. **Counter fields**: Fields that increment/decrement (views, likes, inventory count)
5. **Event history**: Audit logs, status history, activity feeds, timeline data
6. **Document size concerns**: Large documents or nested structures approaching 250 KB limit
7. **Concurrent updates**: Multiple devices updating same data while offline
8. **Data duplication**: Copying data across collections

---

## Platform Detection

**Automatic Detection**:
1. **Flutter/Dart**: `*.dart` files, `import 'package:ditto/ditto.dart'`
2. **JavaScript**: `*.js` files, `import { Ditto } from '@dittolive/ditto'`
3. **Swift**: `*.swift` files, `import DittoSwift`
4. **Kotlin**: `*.kt` files, `import live.ditto.*`

**Platform-Specific Patterns**:
- **All platforms**: CRDT rules are universal (same patterns apply everywhere)
- **No platform-specific differences** for data modeling (unlike query-sync Skill)

---

## SDK Version Compatibility

This section consolidates all version-specific information referenced throughout this Skill.

### All Platforms

- **CRDT Rules**: Universal across all platforms and SDK versions
  - Arrays are REGISTER types (last-write-wins)
  - MAPs provide field-level CRDT merging
  - Document size limit: 250 KB (all versions)
  - PN_INCREMENT operator available in all SDK versions

- **SDK 4.14.0+**
  - COUNTER type introduced for high-frequency counter operations
  - PN_INCREMENT remains available and recommended for most counters
  - COUNTER type benefits: automatic conflict resolution, no manual delta tracking

- **SDK 4.11+**
  - DATE operators available for timestamp comparisons
  - ULID recommended for distributed ID generation

**Throughout this Skill**: Data modeling patterns and CRDT rules are consistent across all SDK versions and platforms. Version references primarily relate to newer features (COUNTER type, DATE operators) rather than breaking changes.

---

## Common Workflows

### Workflow 1: Designing a New Document Schema

Copy this checklist and check off items as you complete them:

```
Schema Design Progress:
- [ ] Step 1: Identify mutable vs immutable collections
- [ ] Step 2: Check for arrays with mutable objects → convert to MAPs
- [ ] Step 3: Design counter fields (use PN_INCREMENT or COUNTER type)
- [ ] Step 4: Decide relationship modeling (embed vs flat/denormalize)
- [ ] Step 5: Validate document size (<250 KB)
- [ ] Step 6: Plan ID generation strategy (ULID recommended)
```

**Step 1: Identify mutable vs immutable collections**

Determine which fields will be modified after creation.

```dart
// Immutable: Arrays are OK
{
  "_id": "user_123",
  "tags": ["premium", "verified"]  // ✅ OK: Never modified after creation
}

// Mutable: Use MAP instead
{
  "_id": "order_123",
  "items": {...}  // Use MAP for items that can be updated
}
```

**Step 2: Convert mutable arrays to MAP structures**

```dart
// ❌ BAD: Mutable array
{
  "items": [
    {"productId": "prod_1", "quantity": 2},
    {"productId": "prod_2", "quantity": 1}
  ]
}

// ✅ GOOD: MAP structure
{
  "items": {
    "prod_1": {"quantity": 2, "price": 10.00},
    "prod_2": {"quantity": 1, "price": 25.00}
  }
}
```

**Step 3: Design counter fields**

```dart
// ✅ GOOD: PN_INCREMENT for simple counters
await ditto.store.execute(
  'UPDATE posts SET viewCount = viewCount PN_INCREMENT :delta WHERE _id = :id',
  arguments: {'id': postId, 'delta': 1},
);

// ✅ GOOD: COUNTER type for high-frequency updates (SDK 4.14.0+)
{
  "_id": "product_123",
  "inventory": {"type": "COUNTER", "value": 100}
}
```

**Step 4: Relationship modeling**

Denormalize data (no JOIN support):

```dart
// ✅ GOOD: Embed frequently accessed data
{
  "_id": "order_123",
  "customerId": "user_456",
  "customerName": "John Doe",  // Denormalized for query performance
  "customerEmail": "john@example.com",
  "items": {...}
}
```

**Step 5: Validate document size**

Ensure documents stay under 250 KB limit. For large data, use separate collections or attachments.

**Step 6: ID generation strategy**

```dart
import 'package:ulid/ulid.dart';

final id = Ulid().toUuid();  // ULID recommended for distributed systems
```

---

### Workflow 2: Converting Arrays to MAP Structures

```
Conversion Progress:
- [ ] Step 1: Identify array fields with mutable items
- [ ] Step 2: Choose appropriate MAP key (unique identifier)
- [ ] Step 3: Transform existing data structure
- [ ] Step 4: Update queries to use MAP syntax
- [ ] Step 5: Test concurrent updates
```

See [examples/array-to-map-migration.dart](examples/array-to-map-migration.dart) for complete implementation.

---

## Critical Patterns

This section contains only the most critical (Tier 1) patterns that prevent data loss and corruption. For additional patterns, see:
- **[reference/common-patterns.md](reference/common-patterns.md)**: HIGH priority patterns (field-level updates, event history, document size)
- **[reference/advanced-patterns.md](reference/advanced-patterns.md)**: MEDIUM/LOW priority patterns (two-collection pattern, INITIAL documents, type validation, naming conventions)

### Pattern 1: Mutable Arrays → MAP Structures (CRITICAL)

**Platform**: All

**Problem**: Arrays in Ditto are REGISTER types with last-write-wins semantics. When two devices modify an array concurrently (add/update/remove items), one device's changes will be lost.

**Detection**:
```dart
// CRITICAL: Arrays with mutable objects
{
  "_id": "order_123",
  "items": [  // ❌ Array of mutable objects
    {"productId": "prod_1", "quantity": 2},  // Can change
    {"productId": "prod_2", "quantity": 1}   // Can change
  ]
}
```

✅ **DO**: Use MAP structures (dictionary/object) for mutable collections

```dart
// ✅ GOOD: MAP structure with product IDs as keys
{
  "_id": "order_123",
  "items": {
    "prod_1": {"quantity": 2, "price": 10.00},  // Individual CRDT merging
    "prod_2": {"quantity": 1, "price": 25.00}
  },
  "total": 45.00
}

// Update single item without conflict
await ditto.store.execute(
  '''
  UPDATE orders
  SET items.prod_1.quantity = :quantity
  WHERE _id = :orderId
  ''',
  arguments: {'orderId': 'order_123', 'quantity': 3},
);
```

**Why**: MAP structures allow field-level CRDT merging. Two devices can update different keys simultaneously without conflicts.

❌ **DON'T**: Use arrays for data that will be modified after creation

```dart
// ❌ BAD: Array with mutable items
{
  "items": [
    {"id": "prod_1", "quantity": 2}
  ]
}

// Concurrent updates lose data
// Device A: Add prod_2 → ["prod_1", "prod_2"]
// Device B: Update prod_1 quantity → ["prod_1" with qty=3]
// After sync: One change is lost!
```

**When Arrays ARE Safe**:
- **Immutable lists**: Tags, category IDs (write-once, read-many)
- **Append-only from single source**: Transaction IDs added by server only
- **Low concurrent modification likelihood**: Status history when only one device writes

**Migration Pattern**:
```dart
// Before: Array of items
{"items": [{"id": "1", "qty": 2}, {"id": "2", "qty": 1}]}

// After: MAP with IDs as keys
{"items": {"1": {"qty": 2}, "2": {"qty": 1}}}

// Conversion code
Map<String, dynamic> convertArrayToMap(List<dynamic> items) {
  final map = <String, dynamic>{};
  for (final item in items) {
    final id = item['id'] as String;
    map[id] = Map<String, dynamic>.from(item)..remove('id');
  }
  return map;
}
```

**See Also**: `examples/array-to-map-migration.dart`, `examples/array-to-map-bad.dart`

---

### Pattern 2: Denormalization for Query Performance (CRITICAL)

**Platform**: All

**Problem**: Ditto does NOT support JOIN operations. Foreign key references require sequential queries (fetch order → extract productId → fetch product), causing significant performance overhead.

**Detection**:
```dart
// CRITICAL: Normalized structure requiring JOINs
// orders collection
{"_id": "order_123", "customerId": "cust_456"}

// customers collection
{"_id": "cust_456", "name": "Alice"}

// To display order with customer name: 2 sequential queries!
```

✅ **DO**: Embed/duplicate data that needs to be retrieved together

```dart
// ✅ GOOD: Denormalized order with embedded customer data
{
  "_id": "order_123",
  "customerId": "cust_456",        // Keep for reference
  "customerName": "Alice Johnson",  // Duplicated for quick access
  "customerEmail": "alice@example.com",
  "items": {
    "prod_1": {
      "productId": "prod_1",
      "productName": "Widget",  // Duplicated product info
      "quantity": 2,
      "price": 10.00
    }
  },
  "total": 20.00,
  "status": "pending"
}

// Single query returns complete order
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :id',
  arguments: {'id': 'order_123'},
);
// Has customer name and product details immediately!
```

**Why**: Denormalization avoids sequential query overhead. Single query is **orders of magnitude faster** than multiple sequential queries.

❌ **DON'T**: Normalize data that's always retrieved together

```dart
// ❌ BAD: Over-normalized structure
// Must make 3+ queries to display single order:
// 1. Query order
// 2. Query customer by customerId
// 3. Query each product by productId
// Result: Slow, complex, poor user experience
```

**Trade-offs**:

| Aspect | Embedded (Denormalized) | Flat (Normalized) |
|--------|-------------------------|-------------------|
| **Query Performance** | ✅ Fast (single query) | ❌ Slow (sequential queries) |
| **Code Simplicity** | ✅ Simple (no joining) | ❌ Complex (manual joins) |
| **Data Freshness** | ⚠️ May be stale if source changes | ✅ Always current |
| **Storage** | ⚠️ Duplicated data | ✅ No duplication |
| **Document Size** | ⚠️ Can exceed 250 KB limit | ✅ Smaller documents |
| **Concurrent Edits** | ⚠️ Conflicts if same doc edited | ✅ Independent editing |

**Decision Guide**:
1. **Will this data always be retrieved together?** → Embed (avoids sequential queries)
2. **Will this data grow unbounded?** → Use flat (avoids 250 KB limit)
3. **Are they truly independent data sets?** → Use flat (parallel sync benefits)
4. **High concurrent edits on same document?** → Use flat (reduces conflicts)

**Foreign-Key Relationships (When to Use)**:

While denormalization is often preferred, foreign-key relationships make sense for:
- **Independent lifecycles**: Entities updated separately (e.g., users vs orders, products vs inventory)
- **Large reference data**: Product catalogs, configuration tables
- **Separate access patterns**: Data accessed independently most of the time

```dart
// ✅ ACCEPTABLE: Foreign-key for independent entities
// Cars collection
{
  "_id": "0016d749-9a9b-4ece-8794-7f3eb40bc82e",
  "owner_id": "5da42ab5-d00b-4377-8524-43e43abf9e01", // Foreign key
  "make": "Toyota",
  "model": "RAV4"
}

// Owners collection (separate lifecycle)
{
  "_id": "5da42ab5-d00b-4377-8524-43e43abf9e01",
  "name": "John Doe",
  "email": "john@example.com"
}

// Query requires 2 steps (no JOIN support)
final car = (await ditto.store.execute(
  'SELECT * FROM cars WHERE _id = :carId',
  arguments: {'carId': carId},
)).items.first.value;

final owner = (await ditto.store.execute(
  'SELECT * FROM owners WHERE _id = :ownerId',
  arguments: {'ownerId': car['owner_id']},
)).items.first.value;
```

**Foreign-Key Trade-offs**:
- ✅ No data duplication
- ✅ Independent updates (owner changes don't affect cars)
- ✅ Separate lifecycle management
- ❌ Multiple sequential queries (performance overhead)
- ❌ Manual joining in application code
- ❌ More complex error handling

**Hybrid Approach (Best of Both)**:

Combine embedded and foreign-key patterns:

```dart
// ✅ BEST: Hybrid approach
{
  "_id": "order_123",
  "customerId": "cust_456",          // Foreign key (for lookups)
  "customerName": "Alice Johnson",    // Embedded (for display)
  "items": {...}                      // Embedded (always displayed together)
}
```

**When to Use Each Pattern**:

| Use Case | Pattern | Rationale |
|----------|---------|-----------|
| Order with items | Embed | Always displayed together |
| Order with customer name | Hybrid | Embed name for display, reference ID for updates |
| Product catalog | Foreign-key | Updated independently, large dataset |
| User profile in order | Hybrid | Embed name/email, reference full profile |
| System configuration | Foreign-key | Separate lifecycle, rarely accessed |

**See Also**: `examples/denormalization-good.dart`, `examples/denormalization-bad.dart`, `examples/foreign-key-relationship.dart`, `examples/embedded-relationship.dart`, `reference/crdt-types-explained.md`

---

### Pattern 2.5: DO NOT Store Calculated Fields (CRITICAL)

**Platform**: All

**Problem**: Fields that can be calculated from existing data waste bandwidth, increase sync traffic, and add unnecessary document size.

**Detection**:
```dart
// CRITICAL: Storing calculated values
{
  "_id": "order_123",
  "items": {
    "item_1": {
      "price": 12.99,
      "quantity": 2,
      "lineTotal": 25.98  // ❌ Calculated: price × quantity
    }
  },
  "subtotal": 25.98,  // ❌ Calculated: sum of lineTotals
  "tax": 2.60,        // ❌ Calculated: subtotal × taxRate
  "total": 28.58      // ❌ Calculated: subtotal + tax
}
```

✅ **DO**: Calculate derived values in application layer

```dart
// ✅ GOOD: Store only source data
{
  "_id": "order_123",
  "items": {
    "item_1": {
      "price": 12.99,
      "quantity": 2
    }
  }
}

// Calculate on-demand in app
double calculateLineTotal(Map<String, dynamic> item) {
  return item['price'] * item['quantity'];
}

double calculateSubtotal(Map<String, dynamic> items) {
  return items.values.fold(0.0, (sum, item) =>
    sum + (item['price'] * item['quantity']));
}

double calculateTotal(double subtotal, double taxRate) {
  final tax = subtotal * taxRate;
  return subtotal + tax;
}

// Use in UI
final order = result.items.first.value;
final items = order['items'] as Map<String, dynamic>;
final subtotal = calculateSubtotal(items);
final total = calculateTotal(subtotal, 0.1); // 10% tax
```

**Why**: Calculated fields multiply bandwidth × devices × sync frequency. Every field update creates deltas that sync across all peers, even if the underlying source data hasn't changed.

❌ **DON'T**: Store values derivable from existing data

```dart
// ❌ BAD: Storing calculated inventory
{
  "_id": "product_123",
  "initialStock": 100,
  "currentStock": 85  // ❌ Calculated from orders
}

// ❌ BAD: Storing calculated age
{
  "_id": "user_456",
  "birthdate": "1990-01-15",
  "age": 35  // ❌ Calculated: currentDate - birthdate
}

// ❌ BAD: Storing calculated average
{
  "_id": "product_789",
  "ratings": [5, 4, 5, 3, 4],
  "averageRating": 4.2  // ❌ Calculated: sum(ratings) / count(ratings)
}
```

**Common Calculated Fields to Avoid**:
- `lineTotal = price × quantity`
- `subtotal = sum(lineTotals)`
- `total = subtotal + tax`
- `averageRating = sum(ratings) / count(ratings)`
- `currentStock = initialStock - sum(orderQuantities)` (see Pattern 4 counter anti-patterns)
- `age = currentDate - birthdate`
- `daysUntilExpiry = expiryDate - currentDate`

**Benefits of Calculating in App**:
- ✅ Reduces document size (faster sync, lower bandwidth)
- ✅ Eliminates stale data risk (calculations always current)
- ✅ Avoids synchronization overhead (no deltas for derived values)
- ✅ Simplifies updates (update source data only)

**When to Store vs Calculate**:

| Field Type | Store or Calculate? |
|------------|---------------------|
| Source data (price, quantity, birthdate) | ✅ Store |
| Derived values (lineTotal, age, average) | ✅ Calculate in app |
| Snapshot data (price at order time) | ✅ Store (denormalization for history) |
| Aggregates (sum, count, average) | ✅ Calculate in app |
| UI state (isExpanded, selected) | ❌ Never store (local state only) |

**See Also**: `.claude/guides/best-practices/ditto.md (lines 1812-1892: Exclude Unnecessary Fields from Documents)`

---

### Pattern 4: Counter Patterns (COUNTER Type and PN_INCREMENT) (CRITICAL)

**⚠️ FIRST: Do You Even Need a Counter?**

Before using any counter pattern, determine if the value can be calculated from existing data:

**Decision Tree**:
```
Need numeric value?
  ↓
Derivable from other documents? (sum orders, count items, etc.)
  ↓ YES → Calculate in app (no counter needed) ← PREFERRED
  ↓ NO
  ↓
Independent metric? (views, likes, votes)
  ↓ YES → Use counter pattern below
```

**Example: Inventory Management**
- ❌ DON'T use counter: `currentStock COUNTER` (requires cross-collection updates)
- ✅ DO calculate: `initialStock - SUM(order quantities)` (app-side calculation)

**Rationale**: Avoids cross-collection synchronization complexity, single source of truth, no JOIN needed

---

**Platform**: All (CRDT rules universal)

**SDK Version Detection:**
- **SDK 4.14.0+**: Use `COUNTER` type (RECOMMENDED)
- **SDK <4.14.0**: Use `PN_INCREMENT BY` operator (legacy)

**Problem**: Using SET operations for counters causes lost updates when devices update concurrently while offline. Last-write-wins semantics discard concurrent increments.

**Detection**:
```dart
// CRITICAL: Counter updated with SET
final product = await fetchProduct(productId);
await ditto.store.execute(
  'UPDATE products SET viewCount = :newCount WHERE _id = :productId',
  arguments: {
    'productId': productId,
    'newCount': (product['viewCount'] ?? 0) + 1, // Lost updates!
  },
);
```

✅ **DO**: Use counter operations (COUNTER type or PN_INCREMENT) for distributed counters

**Option 1: COUNTER Type (SDK 4.14.0+) ← RECOMMENDED**
```dart
// ✅ GOOD: COUNTER type with explicit declaration (4.14.0+)
await ditto.store.execute(
  '''
  UPDATE COLLECTION products (viewCount COUNTER)
  APPLY viewCount INCREMENT BY 1
  WHERE _id = :productId
  ''',
  arguments: {'productId': productId},
);

// Additional COUNTER type operations:
// Set counter to specific value (last-write-wins)
await ditto.store.execute(
  '''
  UPDATE COLLECTION products (viewCount COUNTER)
  APPLY viewCount RESTART WITH 100
  WHERE _id = :productId
  ''',
  arguments: {'productId': productId},
);

// Reset counter to zero
await ditto.store.execute(
  '''
  UPDATE COLLECTION products (viewCount COUNTER)
  APPLY viewCount RESTART
  WHERE _id = :productId
  ''',
  arguments: {'productId': productId},
);

// Concurrent increments merge correctly:
// Device A: +1 → viewCount = 101
// Device B: +1 → viewCount = 101
// After sync: viewCount = 102 ✅
```

**Option 2: PN_INCREMENT Operator (Legacy/Backward Compatibility)**
```dart
// ✅ ACCEPTABLE: PN_INCREMENT (for SDK <4.14.0 or legacy compatibility)
await ditto.store.execute(
  '''
  UPDATE products
  APPLY viewCount PN_INCREMENT BY 1.0
  WHERE _id = :productId
  ''',
  arguments: {'productId': productId},
);

// Note: Use this only when:
// - SDK version < 4.14.0
// - Maintaining compatibility with older peers
// - For new projects on SDK 4.14.0+, use COUNTER type instead
```

**Decrement Pattern**:
```dart
// ✅ GOOD: Decrement with COUNTER type (SDK 4.14.0+)
await ditto.store.execute(
  '''
  UPDATE COLLECTION products (inventory COUNTER)
  APPLY inventory INCREMENT BY -1
  WHERE _id = :productId
  ''',
  arguments: {'productId': productId},
);

// ✅ ACCEPTABLE: Decrement with PN_INCREMENT (legacy)
await ditto.store.execute(
  '''
  UPDATE products
  APPLY inventory PN_INCREMENT BY -1.0
  WHERE _id = :productId
  ''',
  arguments: {'productId': productId},
);
```

**Why**: `COUNTER` type and `PN_INCREMENT` use CRDT (Conflict-free Replicated Data Type) semantics that merge concurrent increments/decrements correctly. SET operations use last-write-wins, losing concurrent updates. COUNTER type (4.14.0+) is recommended for new projects, providing `RESTART WITH` and `RESTART` operations for controlled value setting.

❌ **DON'T**: Use SET for counters that may be updated concurrently

```dart
// ❌ BAD: SET operation (lost updates)
final product = await fetchProduct(productId);
await ditto.store.execute(
  'UPDATE products SET viewCount = :count WHERE _id = :productId',
  arguments: {
    'productId': productId,
    'count': (product['viewCount'] ?? 0) + 1,
  },
);

// Concurrent scenario:
// Device A: Reads viewCount=100, sets to 101
// Device B: Reads viewCount=100, sets to 101
// After sync: viewCount = 101 (lost one increment!) ❌
```

**See Also**: `examples/counter-patterns.dart`, `reference/common-patterns.md` (field-level updates, event history, document size), `reference/advanced-patterns.md` (two-collection pattern, INITIAL documents, type validation)

---

### Pattern 10: ID Generation for Distributed Systems (CRITICAL)

**Platform**: All (ID generation is universal concern in distributed systems)

**Problem**: Sequential IDs cause collisions when multiple devices create documents offline independently

**Detection Triggers**:
```dart
// ❌ CRITICAL: Sequential ID patterns (collision risk!)
final orderId = 'order_${DateTime.now()}_001';
final itemId = 'item_${category}_${count}';
final userId = 'user_${timestamp}_${incrementalCounter}';

// Common sequential patterns to avoid:
// - Date-based: 'order_20250115_001', 'item_2025_001'
// - Counter-based: 'product_001', 'user_123'
// - Timestamp-based: 'event_1705334400_001'
// - displayId without random: 'ORD-2025-0115-001'
```

**Root Cause**: Distributed P2P systems allow multiple devices to write independently. Sequential ID generation assumes single writer, causing collisions when offline devices sync.

**Collision Scenario**:
```
Device A (offline) → generates 'order_20250115_001'
Device B (offline) → generates 'order_20250115_001'
Both devices sync → COLLISION → data loss or undefined behavior
```

**⚠️ IMPORTANT: Auto-Generated IDs**

If you **omit the `_id` field** when inserting a document, Ditto automatically assigns a UUID (128-bit universally unique identifier).

```dart
// ✅ GOOD: Omit _id - Ditto auto-generates UUID
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      // No _id field - Ditto generates UUID automatically
      'orderNumber': '#42',
      'status': 'pending',
    }
  },
);
```

**When Auto-Generated IDs Are Appropriate:**
- ✅ Internal documents where ID format doesn't matter
- ✅ Simplest implementation (no external library needed)
- ✅ No coordination required across devices

**When Explicit IDs Are Required:**
- ⚠️ Authorization rules depend on `_id` structure (composite keys for access control)
- ⚠️ Intentional ID unification across devices (see "Intentional ID Unification" in main guide)
- ⚠️ External system integration requiring specific ID format

**✅ DO: UUID v4 (Explicit ID Generation)**

```dart
import 'package:uuid/uuid.dart';

final uuid = Uuid();
final orderId = uuid.v4(); // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,  // Explicit UUID
      'orderNumber': '#42',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    }
  },
);
```

**Why UUID v4?**
- **Collision-free**: ~1 in 2^61 for 1 billion IDs
- **No coordination required**: Devices generate IDs independently
- **Aligns with Ditto**: Native auto-generated IDs are 128-bit UUIDs
- **Platform-agnostic**: UUID libraries available on all platforms

**⚠️ Intentional ID Unification (Advanced Pattern)**

**When NOT to use random IDs**: In some distributed scenarios, multiple devices should **intentionally create the same document with the same `_id`** to ensure data merges instead of creating duplicates.

**Use Case: Shared Reference Data (Product Catalog)**

```dart
// ✅ GOOD: Unified ID for shared product data
// Device A and Device B both add same product → merge, not duplicate

await ditto.store.execute(
  'INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'product': {
      '_id': 'product_apple_iphone_15_pro',  // Deterministic ID from SKU
      'name': 'iPhone 15 Pro',
      'price': 999.99,
      'category': 'Electronics',
    }
  },
);
```

**Decision Matrix: Random vs Unified IDs**

| Scenario | ID Strategy | Example |
|----------|-------------|---------|
| **User transactions** (orders, invoices) | UUID v4 (unique per transaction) | `_id: uuid.v4()` |
| **Shared reference data** (products, menus) | Deterministic ID (unified) | `_id: 'product_${sku}'` |
| **Device-specific settings** | Device-based ID | `_id: 'device_${deviceId}'` |
| **Event logs** (time-series) | ULID (time-ordered unique) | `_id: ulid.toString()` |

**Conflict Resolution Strategies**:
- `DO UPDATE`: Replace entire document, sync all fields as deltas (even unchanged)
- `DO UPDATE_LOCAL_DIFF`: Sync only changed fields (recommended for unified IDs)
- `DO NOTHING`: Keep existing document, ignore new data (first-write-wins)
- `DO FAIL`: Error on conflict (debugging scenarios)

**⚠️ CRITICAL: `_id` Immutability**

The `_id` field **cannot be changed** after document creation. To change an ID, you must create a new document with the desired `_id` and delete the old one.

**Why This Pattern?**
- Provides collision-free IDs in distributed systems (UUID v4)
- Auto-generated IDs work for most scenarios (simplest approach)
- Unified IDs enable intentional merging for reference data (advanced pattern)
- No coordination required between devices

**Advanced ID Patterns**: See [reference/advanced-patterns.md](reference/advanced-patterns.md) for:
- Composite keys (multi-dimensional organization)
- ULID (time-ordered IDs)
- Human-readable display IDs
- Migration from sequential IDs
- Detailed intentional ID unification patterns

**See Also**: Main guide "ID Generation Strategies" section, `examples/id-generation-patterns.dart`, `examples/complex-id-patterns.dart`, `examples/id-immutability-workaround.dart`, `reference/advanced-patterns.md` (ID patterns, field naming)

---

## Quick Reference Checklist

**Critical (Tier 1) - Keep in SKILL.md:**
- [ ] **ID Generation**: Use UUID v4 (or auto-generated IDs) for distributed systems, NOT sequential IDs
- [ ] **Display IDs**: Consider random suffix for displayId fields (e.g., "ORD-20251219-A7F3") to reduce user confusion
- [ ] **NO Calculated Fields**: DO NOT store lineTotal, subtotal, total, or any value derivable from existing data
- [ ] **Arrays**: Convert mutable arrays to MAP structures (use keys instead of indices)
- [ ] **Denormalization**: Embed data that's always retrieved together (avoid sequential queries)
- [ ] **No JOINs**: Design with awareness that JOINs aren't supported
- [ ] **Counters**: Use counter operations (PN_INCREMENT or COUNTER type in 4.14.0+), not SET operations

**Common Patterns (Tier 2) - See [reference/common-patterns.md](reference/common-patterns.md):**
- [ ] **Field Updates**: Use field-level UPDATE, not full document replacement
- [ ] **DO UPDATE_LOCAL_DIFF**: Use for upserts (SDK 4.12+) to avoid syncing unchanged fields
- [ ] **Check Before Update**: Avoid updating fields with same value (creates unnecessary deltas)
- [ ] **Event History**: Use separate INSERT documents, not arrays
- [ ] **Document Size**: Keep under 250 KB, use flat models for unbounded data
- [ ] **Large Binaries**: Use ATTACHMENT type for files >250 KB

**Advanced Patterns (Tier 3) - See [reference/advanced-patterns.md](reference/advanced-patterns.md):**
- [ ] **Two Collections**: Consider dual-write pattern for real-time + historical data
- [ ] **INITIAL Documents**: Use for device-local templates to avoid unnecessary sync
- [ ] **Type Validation**: Validate at insert time, use defensive queries for untrusted data
- [ ] **Field Naming**: Choose consistent convention (camelCase or snake_case)

---

## See Also

- **This Skill's Additional Patterns**:
  - **[reference/common-patterns.md](reference/common-patterns.md)**: Field-level updates, event history, document size (HIGH priority)
  - **[reference/advanced-patterns.md](reference/advanced-patterns.md)**: Two-collection pattern, INITIAL documents, type validation, field naming (MEDIUM/LOW priority)
- **Main Guide**: `.claude/guides/best-practices/ditto.md` (Sections: Collection Design, Data Deletion, CRDT Types)
- **Other Skills**:
  - `query-sync/SKILL.md`: Subscription lifecycle, DQL queries
  - `storage-lifecycle/SKILL.md`: DELETE, EVICT, tombstone strategies
  - `performance-observability/SKILL.md`: Observer optimization, delta minimization
  - `transactions-attachments/SKILL.md`: ATTACHMENT handling for large files
- **Examples**: See `examples/` directory for copy-paste patterns
- **Reference**: See `reference/` for deep dives on CRDT types and merge scenarios
