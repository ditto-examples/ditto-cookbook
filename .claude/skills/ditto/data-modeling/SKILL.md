---
name: ditto-data-modeling
description: CRDT-safe data structure design and merge safety for Ditto SDK. Triggers on: designing document schemas, using arrays in documents, modeling relationships (embed vs flat), implementing counters, event history patterns. Critical patterns: mutable arrays → MAP structures, denormalization for query performance (no JOIN support), field-level updates vs document replacement, counter patterns (PN_INCREMENT and COUNTER type in 4.14.0+), event history design. Applies to: Flutter (Dart), JavaScript, Swift, Kotlin - cross-platform CRDT rules.
---

# Ditto Data Modeling Skill

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

## Critical Patterns

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

**See Also**: `.claude/guides/best-practices/ditto.md#exclude-unnecessary-fields-from-documents`

---

### Pattern 3: Field-Level Updates vs Document Replacement (HIGH)

**Platform**: All

**Problem**: Full document replacement with `INSERT ... ON ID CONFLICT DO UPDATE` treats ALL fields as updated (even unchanged ones), causing unnecessary sync traffic. Even updating a field with the same value creates a delta and syncs to other peers.

**Detection**:
```dart
// CRITICAL: Replacing entire document
final order = await fetchOrder(orderId);
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      ...order,
      'status': 'completed',  // Only this changed
      // But ALL fields sync as deltas!
    },
  },
);
```

✅ **DO**: Use field-level UPDATE for targeted changes

```dart
// ✅ GOOD: Field-level update (only changed fields sync)
await ditto.store.execute(
  '''
  UPDATE orders
  SET status = :status, completedAt = :completedAt
  WHERE _id = :orderId
  ''',
  arguments: {
    'orderId': orderId,
    'status': 'completed',
    'completedAt': DateTime.now().toIso8601String(),
  },
);
// Only 'status' and 'completedAt' sync as deltas
```

**Better (SDK 4.12+)**: Use `DO UPDATE_LOCAL_DIFF` for upserts

```dart
// ✅ BETTER: DO UPDATE_LOCAL_DIFF only syncs changed fields (SDK 4.12+)
await ditto.store.execute(
  '''
  INSERT INTO orders DOCUMENTS (:order)
  ON ID CONFLICT DO UPDATE_LOCAL_DIFF
  ''',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed - will sync
      'customerId': 'customer_456', // Unchanged - won't sync
      'items': {...},               // Unchanged - won't sync
      'completedAt': DateTime.now().toIso8601String(), // Changed - will sync
    },
  },
);
// Automatically compares values, only syncs what changed
```

**Check before updating** to avoid unnecessary deltas:

```dart
// ✅ BEST: Check if value actually changed
final orderResult = await ditto.store.execute(
  'SELECT status FROM orders WHERE _id = :orderId',
  arguments: {'orderId': orderId},
);

final currentStatus = orderResult.items.first.value['status'];
final newStatus = 'completed';

if (currentStatus != newStatus) {
  // Only update if value changed
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': newStatus},
  );
}
```

**Why**: Field-level updates only sync changed fields. Full document replacement increments CRDT counters for ALL fields, even unchanged ones. **⚠️ CRITICAL**: Even updating with the same value is treated as a delta.

❌ **DON'T**: Replace documents when only updating specific fields

```dart
// ❌ BAD: Full document replacement
final order = await fetchOrder(orderId);
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {'order': {...order, 'status': 'completed'}},
);
// ALL fields sync, wasting bandwidth

// ❌ BAD: Updating with same value
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'pending'},
);
// If status was already 'pending', this still creates and syncs a delta!
```

**Conflict Resolution Options**:

| Option | Behavior | When to Use |
|--------|----------|-------------|
| `DO UPDATE` | Updates all fields, syncs all as deltas | Never (use UPDATE_LOCAL_DIFF instead) |
| `DO UPDATE_LOCAL_DIFF` (SDK 4.12+) | Only updates/syncs changed fields | Upsert operations with many unchanged fields |
| `DO NOTHING` | Ignores conflict, keeps existing document | Write-once, read-many data |
| `FAIL` | Throws error on conflict (default) | Explicit conflict handling needed |

**See Also**: `examples/field-level-updates.dart`

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

**See Also**: `examples/counter-patterns.dart`

---

### Pattern 5: Event History with Separate Documents (HIGH)

**Platform**: All

**Problem**: Arrays are REGISTER types with last-write-wins. Even "append-only" array operations lose data when multiple devices append concurrently.

**Detection**:
```dart
// CRITICAL: Appending to array for event history
await ditto.store.execute(
  '''
  UPDATE orders
  SET statusHistory = statusHistory || [:entry]
  WHERE _id = :orderId
  ''',
  arguments: {
    'orderId': orderId,
    'entry': {'status': 'shipped', 'timestamp': DateTime.now().toIso8601String()},
  },
);
// Concurrent appends from Device A and Device B → one is lost!
```

✅ **DO**: Use separate INSERT documents for event history

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
  '''
  SELECT * FROM order_history
  WHERE orderId = :orderId
  ORDER BY timestamp ASC
  ''',
  arguments: {'orderId': orderId},
);

final history = historyResult.items.map((item) => item.value).toList();
```

**Why**: Separate documents (INSERT) guarantee preservation of all events. Arrays risk data loss in concurrent scenarios. Separate documents are better for audit logs where completeness is critical.

❌ **DON'T**: Use arrays for append-only logs with concurrent writes

```dart
// ❌ BAD: Array with append operations
{
  "_id": "order_123",
  "statusHistory": [
    {"status": "pending", "timestamp": "2025-01-15T10:00:00Z"},
    {"status": "processing", "timestamp": "2025-01-15T11:00:00Z"}
  ]
}

// Concurrent appends:
// Device A: Append "shipped" → array = [pending, processing, shipped]
// Device B: Append "canceled" → array = [pending, processing, canceled]
// After sync: One append is lost! ❌
```

**Trade-offs**:

| Approach | Event Preservation | Query Convenience | Document Count |
|----------|-------------------|-------------------|----------------|
| **Separate documents (INSERT)** | ✅ Guaranteed | ✅ Easy filtering/sorting | ⚠️ Higher count |
| **Arrays** | ❌ Risk of loss | ⚠️ Requires extraction | ✅ Fewer docs |

**See Also**: `examples/event-history-good.dart`, `examples/event-history-bad.dart`

---

### Pattern 6: Document Size and Relationship Modeling (HIGH)

**Platform**: All

**Problem**: Documents exceeding 5 MB will not sync. Documents over 250 KB trigger warnings and perform poorly (Bluetooth LE replication maxes at ~20 KB/second, so a 250 KB document takes 10+ seconds).

**Detection**:
```dart
// CRITICAL: Unbounded embedded growth
{
  "_id": "person_123",
  "name": "Alice",
  "cars": [
    {
      "make": "Toyota",
      "maintenance": [  // Can grow to hundreds of entries!
        {"date": "2025-01-15", "type": "oil_change", "cost": 45.00},
        {"date": "2025-02-20", "type": "tire_rotation", "cost": 35.00},
        // ... hundreds more - document becomes too large!
      ],
      "photos": ["base64_encoded_large_image..."]  // Large binary data!
    }
  ]
}
// Problems: Too large, slow to sync, difficult to update concurrently
```

✅ **DO**: Balance embed vs flat based on access patterns and growth potential

**Embed when:**
- Data retrieved/updated together as a unit (avoids sequential queries)
- Small to medium size (under 250 KB combined)
- Relatively stable relationship (doesn't grow unbounded)

```dart
// ✅ GOOD: Embedded data retrieved together (single query)
{
  "_id": "order_123",
  "customerId": "cust_456",
  "shippingAddress": {  // Retrieved with order, small and stable
    "street": "123 Main St",
    "city": "Springfield",
    "zip": "12345"
  },
  "items": {  // Limited number of items per order
    "prod_1": {"quantity": 2, "price": 10.00},
    "prod_2": {"quantity": 1, "price": 25.00}
  },
  "total": 45.00
}
```

**Use flat models when:**
- Data grows unbounded over time (exceeds 250 KB limit)
- Data accessed independently (no need to retrieve together)
- Frequent concurrent modifications

```dart
// ✅ GOOD: Flat model for unbounded data
// maintenance_logs collection (grows unbounded)
{
  "_id": "log_456",
  "carId": "car_123",  // Foreign key
  "date": "2025-01-15",
  "type": "oil_change",
  "cost": 45.00
}

// cars collection (bounded size)
{
  "_id": "car_123",
  "ownerId": "person_123",
  "make": "Toyota",
  "model": "Camry",
  "year": 2020
}

// Query: 2 sequential queries needed
// But avoids document size limit and enables independent updates
```

**Store large binary data using ATTACHMENT type**:

```dart
// ✅ GOOD: Large files as ATTACHMENTs
{
  "_id": "car_123",
  "make": "Toyota",
  "photo": {
    "type": "ATTACHMENT",
    "token": "ditto_attachment_abc123..."  // Reference to attachment
  }
}
// Large binary data stored separately, lazy-loaded on demand
```

**Why**: Ditto has hard 5 MB limit and soft 250 KB warning. Embedded data is faster to query (single query vs sequential queries) but can exceed size limits. Choose based on access patterns and growth potential.

❌ **DON'T**: Embed unbounded data or large binaries directly

```dart
// ❌ BAD: Unbounded embedded array
{
  "_id": "person_123",
  "cars": [
    {"maintenance": [...hundreds of entries...]}  // Exceeds size limit!
  ]
}

// ❌ BAD: Large binary data in document
{
  "_id": "car_123",
  "photo": "data:image/png;base64,iVBORw0KGgoAAAA..."  // Huge string!
}
```

**Key Considerations**:
- **Embed benefits**: Single-query access (critical with no JOIN support), simpler code
- **Flat benefits**: Independent sync, concurrent edits without conflicts, parallel sync efficiency
- **Choose based on**: Access patterns, growth potential, document size limits, concurrent edit likelihood

**See Also**: `examples/document-size-optimization.dart`, `reference/merge-scenarios.md`

---

### Pattern 7: Two-Collection Pattern for Real-Time + Historical Data (MEDIUM)

**Platform**: All

**Problem**: Storing both real-time current state and complete historical events in a single collection causes performance issues: queries need `ORDER BY LIMIT 1`, working set grows over time, and resource usage is unpredictable.

**When to use**: Location tracking, sensor readings, order status updates—any scenario where you need both "latest value" and "full history"

✅ **DO**: Use two separate collections for different purposes

**Pattern: Dual Write**

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
    '''
    INSERT INTO aircraft DOCUMENTS (:aircraft)
    ON ID CONFLICT DO UPDATE
    ''',
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

**Consumer Patterns**:

```dart
// Real-time display (observe bounded current state)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM aircraft',
  onChange: (result, signalNext) {
    // Result set size bounded by number of aircraft (not update count)
    updateMapDisplay(result.items);
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
);

// Historical analysis (one-time query for trajectory)
final result = await ditto.store.execute(
  '''
  SELECT * FROM position_events
  WHERE aircraft_id = :id AND timestamp >= :start
  ORDER BY timestamp ASC
  ''',
  arguments: {'id': aircraftId, 'start': startTime},
);

final trajectory = result.items.map((item) => item.value).toList();
renderFlightPath(trajectory);
```

**Why separate collections**: Independent data sets that don't need to be queried together benefit from separate collections (parallel sync efficiency). Different from splitting related data (like orders and items), which would require sequential queries.

**Benefits**:
- ✅ Predictable resource usage (current state collection has bounded size)
- ✅ Automatic conflict resolution (CRDT handles concurrent updates)
- ✅ Efficient real-time queries (no `ORDER BY LIMIT 1` needed)
- ✅ Complete audit trail (events collection preserves all history)
- ✅ Differentiated sync (devices sync only what they need)

**Trade-offs**:

| Single Collection (Events Only) | Two Collections (Dual Write) |
|--------------------------------|------------------------------|
| Simpler schema | Slightly more complex |
| Storage efficient (no duplication) | Duplicates "current state" |
| Queries need `ORDER BY LIMIT 1` | Current state directly queryable |
| Working set grows over time | Current state collection has fixed size |
| App handles conflict resolution | CRDT handles conflicts automatically |

**See Also**: `examples/two-collection-pattern.dart`, `reference/crdt-types-explained.md`

---

### Pattern 8: INITIAL Documents for Device-Local Templates (MEDIUM)

**Platform**: All

**Problem**: Regular INSERT operations for device-local templates (form templates, default categories, seed data) generate unnecessary sync traffic when each device initializes the same default data.

**Detection**:
```dart
// CRITICAL: Regular INSERT for device-local defaults
final defaultCategories = [
  {'_id': 'cat_food', 'name': 'Food', 'icon': 'food'},
  {'_id': 'cat_drink', 'name': 'Drinks', 'icon': 'drink'},
];

await ditto.store.execute(
  'INSERT INTO categories DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);
// Each device's INSERT syncs to other peers → unnecessary network traffic
```

✅ **DO**: Use INITIAL DOCUMENTS for device-local templates

```dart
// ✅ GOOD: INITIAL prevents unnecessary sync
await ditto.store.execute(
  'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
  arguments: {
    'categories': [
      {'_id': 'cat_food', 'name': 'Food', 'icon': 'food'},
      {'_id': 'cat_drink', 'name': 'Drinks', 'icon': 'drink'},
      {'_id': 'cat_dessert', 'name': 'Desserts', 'icon': 'dessert'},
    ],
  },
);

// Each device initializes independently
// If '_id' already exists locally, INITIAL does nothing
// No sync traffic generated for these default templates
```

**How INITIAL works**:
- Documents inserted with INITIAL do nothing if the `_id` already exists locally
- All peers view INITIAL documents as the same INSERT operation
- Prevents sync conflicts and unnecessary network traffic for local defaults
- Cannot be overridden by `ON ID CONFLICT` policy

**Why**: INITIAL documents prevent unnecessary synchronization of device-local data, reducing network traffic and avoiding sync conflicts for data that should exist independently on each device.

❌ **DON'T**: Use regular INSERT for device-local templates

```dart
// ❌ BAD: Regular INSERT syncs unnecessarily
await ditto.store.execute(
  'INSERT INTO categories DOCUMENTS (:categories)',
  arguments: {'categories': defaultCategories},
);
// Generates sync traffic even though all devices have same defaults
```

**Use Cases**:
1. **Form Templates**: Device-local form structures that don't need sync
2. **Default Settings**: Initial configuration every device should have
3. **Category Lists**: Predefined categories for local organization
4. **UI Presets**: Default UI configurations per device

**See Also**: `examples/initial-documents.dart`

---

### Pattern 9: Type Validation in Schema-less Documents (MEDIUM)

**Platform**: All platforms

**Problem**: Schema-less documents allow any type in any field. Without validation, type mismatches cause query failures or incorrect results.

**Detection**:
```dart
// CRITICAL: No type validation
{
  "_id": "user_123",
  "age": "twenty-five" // Should be number!
}

// Query expecting number fails or returns wrong results
await ditto.store.execute(
  'SELECT * FROM users WHERE age >= :minAge',
  arguments: {'minAge': 18},
);
// String comparison instead of numeric comparison
```

**✅ DO (Validate at insert time, defensive queries)**:
```dart
// Insert-time validation
Future<void> insertUser(Map<String, dynamic> userData) async {
  // Validate types before insert
  if (userData['age'] is! int) {
    throw ArgumentError('age must be integer');
  }
  if (userData['email'] is! String || !(userData['email'] as String).contains('@')) {
    throw ArgumentError('email must be valid string');
  }

  await ditto.store.execute(
    'INSERT INTO users DOCUMENTS (:user)',
    arguments: {'user': userData},
  );
}

// Defensive querying with type checking (SDK 4.x+)
await ditto.store.execute(
  'SELECT * FROM users WHERE is_number(age) AND age >= :minAge',
  arguments: {'minAge': 18},
);

// Schema validation query (find malformed documents)
final result = await ditto.store.execute(
  '''SELECT _id, type(age) AS ageType
     FROM users
     WHERE type(age) != :expectedType OR age IS NULL''',
  arguments: {'expectedType': 'number'},
);
```

**❌ DON'T (Rely solely on query-time type checking)**:
```dart
// Type checking in every query (inefficient)
await ditto.store.execute(
  'SELECT * FROM users WHERE is_number(age) AND age >= :minAge',
  arguments: {'minAge': 18},
);
// Better: Validate at insert, then queries can assume correct types

// No validation at insert
await ditto.store.execute(
  'INSERT INTO users DOCUMENTS (:user)',
  arguments: {'user': userInput}, // No validation!
);
// Type mismatches will cause issues in all subsequent queries
```

**Use Cases**:
1. **User Input Validation**: Validate types before storing user-generated data
2. **Schema Migration**: Find and fix type mismatches in existing data
3. **Polymorphic Fields**: Query polymorphic fields with type guards
4. **Data Quality Checks**: Identify malformed documents in production

**Type Checking Operators** (SDK 4.x+):
- `is_boolean(field)` - Check if field is boolean
- `is_number(field)` - Check if field is number
- `is_string(field)` - Check if field is string
- `type(field)` - Get type name as string ('boolean', 'number', 'string', 'array', 'object', 'null')

**Why**: Type checking operators add query overhead. Validate at insert time to guarantee schema compliance without runtime checks. Use type checking only for defensive queries on untrusted data or polymorphic fields.

**See Also**: `.claude/guides/best-practices/ditto.md#type-checking-operators`

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

**✅ DO: UUID v4 (Recommended)**

```dart
import 'package:uuid/uuid.dart';

final uuid = Uuid();
final orderId = uuid.v4(); // "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': orderId,
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

**Alternative Patterns**:

**Option 2: Auto-Generated (Simplest)**
```dart
// Omit _id, Ditto auto-generates UUID
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      // No _id - Ditto generates automatically
      'orderNumber': '#42',
      'status': 'pending',
    }
  },
);
```

**⚠️ CRITICAL: `_id` Immutability**

The `_id` field cannot be changed after document creation. This is a fundamental constraint:

```dart
// ❌ BAD: Attempting to change _id after creation
await ditto.store.execute(
  'UPDATE orders SET _id = :newId WHERE _id = :oldId',
  arguments: {'newId': 'new_123', 'oldId': 'old_123'},
);
// ERROR: _id field is immutable - this operation will fail

// ✅ GOOD: Create new document with desired _id instead
final oldDoc = (await ditto.store.execute(
  'SELECT * FROM orders WHERE _id = :oldId',
  arguments: {'oldId': 'old_123'},
)).items.first.value;

// Copy data to new document with new _id
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:doc)',
  arguments: {'doc': {...oldDoc, '_id': 'new_123'}},
);

// Delete old document
await ditto.store.execute(
  'DELETE FROM orders WHERE _id = :oldId',
  arguments: {'oldId': 'old_123'},
);
```

**Why Immutability Matters**:
- **Authorization rules**: `_id` structure determines access control
- **Distributed sync**: Document identity must remain stable across all peers
- **Reference integrity**: Foreign-key relationships rely on stable IDs

**Option 3: Composite Keys (Advanced)**

Use complex object `_id` for multi-dimensional organization and hierarchical access control.

```dart
{
  "_id": {
    "locationId": "store_001",
    "orderId": "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
  },
  // Duplicate for queries (POJO/DTO pattern)
  "locationId": "store_001",
  "orderId": "7c0c20ed-b285-48a6-80cd-6dcf06d52bcc"
}
// ⚠️ IMPORTANT: Once created, this _id structure cannot be modified

// Query by component (access specific field)
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE _id.locationId = :locId',
  arguments: {'locId': 'store_001'},
);

// Query by full object (exact match)
final result = await ditto.store.execute(
  '''SELECT * FROM orders WHERE _id = :idObj''',
  arguments: {
    'idObj': {
      'locationId': 'store_001',
      'orderId': '7c0c20ed-b285-48a6-80cd-6dcf06d52bcc'
    }
  },
);
```

**When to Use Composite Keys**:
- Multi-dimensional organization (e.g., order + location, user + device)
- Authorization rules requiring hierarchical access (e.g., filter by locationId)
- Natural composite primary keys in domain model

**Trade-offs**:
- ✅ Clear hierarchical structure
- ✅ Component-level queries without string parsing
- ✅ Better alignment with authorization rules
- ❌ More verbose than simple string IDs
- ❌ Requires careful design - **immutable after creation**
- ❌ Cannot restructure `_id` if requirements change (must create new documents)

**Option 4: ULID (Time-Ordered)**
```dart
import 'package:ulid/ulid.dart';

final ulid = Ulid().toString(); // "01ARZ3NDEKTSV4RRFFQ69G5FAV"
```

**Decision Tree**:
```
Need document _id?
  ↓
Simplest approach?
  ↓ YES → Omit _id (auto-generated)
  ↓ NO
  ↓
Time-ordered sorting required?
  ↓ YES → Use ULID
  ↓ NO
  ↓
Permission scoping needed?
  ↓ YES → Use Composite Keys
  ↓ NO
  ↓
→ Use UUID v4 (general-purpose, recommended)
```

**Human-Readable Display**:
```dart
// Add display fields alongside UUID with random suffix
import 'dart:math';

final now = DateTime.now();
final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
final randomSuffix = Random().nextInt(0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
final displayId = 'ORD-$dateStr-$randomSuffix';  // "ORD-20251219-A7F3"

{
  "_id": "550e8400-e29b-41d4-a716-446655440000",  // UUID (collision-free)
  "displayId": "ORD-2025-1219-A7F3"               // Display (date + random)
}

// ⚠️ NOTE: displayId does not need to be globally unique (it's not the document ID)
// Random suffix reduces user confusion, but not required for system correctness
```

**Migration from Sequential IDs (Dual-Write Pattern)**:
```dart
final uuid = Uuid();
final newOrderId = uuid.v4();
final legacyOrderId = 'order_20250115_001';

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order)',
  arguments: {
    'order': {
      '_id': newOrderId,                // New UUID (primary)
      'legacyOrderId': legacyOrderId,   // Keep for backward compatibility
      'orderNumber': '#42',
    }
  },
);
```

**Why This Pattern?**
- Provides collision-free IDs in distributed systems
- Supports migration from legacy sequential IDs
- Balances simplicity (UUID v4) with flexibility (alternatives)

**See Also**: `examples/id-generation-patterns.dart`, `examples/complex-id-patterns.dart`, `examples/id-immutability-workaround.dart`

---

### Pattern 11: Field Naming Conventions (MEDIUM)

**Platform**: All

**Problem**: Invalid field names or inconsistent naming conventions cause query errors and maintenance issues

**Detection Triggers**:
```dart
// ❌ CRITICAL: Invalid field names (non-string keys)
{
  123: "value",        // Number as key - invalid
  true: "enabled",     // Boolean as key - invalid
  "_id": "doc_123"     // Valid (string)
}

// ⚠️ WARNING: Inconsistent naming
{
  "customerId": "user_123",     // camelCase
  "customer_name": "Alice",     // snake_case - inconsistent
  "CustomerEmail": "alice@..."  // PascalCase - inconsistent
}
```

**Root Cause**: Ditto documents are JSON-like structures with specific constraints. Field names MUST be strings (not numbers or booleans).

**✅ DO: Use consistent string field names**

```dart
// ✅ GOOD: Consistent camelCase naming
{
  "_id": "order_123",
  "customerId": "cust_456",
  "customerName": "Alice Johnson",
  "customerEmail": "alice@example.com",
  "createdAt": "2025-01-15T10:00:00Z",
  "items": {
    "item_1": {
      "productId": "prod_1",
      "productName": "Widget",
      "quantity": 2
    }
  }
}

// ✅ GOOD: Consistent snake_case naming
{
  "_id": "order_123",
  "customer_id": "cust_456",
  "customer_name": "Alice Johnson",
  "customer_email": "alice@example.com",
  "created_at": "2025-01-15T10:00:00Z"
}
```

**Why Consistent Naming?**
- **Code readability**: Clear patterns reduce cognitive load
- **Query simplicity**: Predictable field names simplify DQL queries
- **Team coordination**: Consistency enables collaboration
- **Migration ease**: Uniform naming simplifies schema changes

❌ **DON'T: Use non-string keys or inconsistent naming**

```dart
// ❌ BAD: Non-string field names (invalid)
{
  "_id": "doc_123",
  123: "numeric_key",      // ERROR: Numbers as keys not allowed
  true: "boolean_key"      // ERROR: Booleans as keys not allowed
}

// ❌ BAD: Inconsistent naming conventions
{
  "_id": "order_123",
  "customerId": "cust_456",     // camelCase
  "customer_name": "Alice",     // snake_case
  "CustomerEmail": "alice@..."  // PascalCase
}
// Harder to remember, error-prone

// ❌ BAD: Reserved DQL keywords without escaping
{
  "_id": "doc_123",
  "select": "value",    // DQL keyword - may cause parsing issues
  "from": "source",     // DQL keyword - may cause parsing issues
  "where": "condition"  // DQL keyword - may cause parsing issues
}
```

**Field Naming Best Practices**:

1. **Choose a convention and stick to it**:
   - **camelCase** (recommended for Dart/Flutter): `customerId`, `orderDate`, `totalAmount`
   - **snake_case** (common in databases): `customer_id`, `order_date`, `total_amount`
   - **Never mix conventions** within the same collection

2. **Avoid DQL reserved keywords**:
   - Keywords: `SELECT`, `FROM`, `WHERE`, `INSERT`, `UPDATE`, `DELETE`, etc.
   - If unavoidable, escape with backticks in queries: `` `select` ``

3. **Use descriptive names**:
   - ✅ `orderTotal` or `order_total`
   - ❌ `ot`, `t`, `x`

4. **Keep names concise**:
   - ✅ `createdAt` or `created_at`
   - ❌ `timestampWhenThisOrderWasCreated`

5. **Boolean prefixes**:
   - ✅ `isActive`, `hasDiscount`, `canEdit`
   - ❌ `active`, `discount`, `edit`

**Decision Guide**:

```
New project?
  ↓
Working with Dart/Flutter?
  ↓ YES → Use camelCase (aligns with Dart conventions)
  ↓ NO
  ↓
Integrating with SQL databases?
  ↓ YES → Use snake_case (aligns with SQL conventions)
  ↓ NO
  ↓
→ Choose based on team preference (be consistent!)
```

**Migration Strategy**:

If migrating from inconsistent naming:

```dart
// Dual-write pattern during migration
{
  "_id": "order_123",
  "customerId": "cust_456",        // New convention (camelCase)
  "customer_id": "cust_456",       // Legacy (snake_case) - keep temporarily
  "customerName": "Alice Johnson", // New
  "customer_name": "Alice Johnson" // Legacy - keep temporarily
}

// After all clients updated, remove legacy fields
{
  "_id": "order_123",
  "customerId": "cust_456",        // Keep
  "customerName": "Alice Johnson"  // Keep
}
```

**Why This Pattern?**
- Ensures valid JSON structure (strings-only keys)
- Improves code maintainability through consistency
- Reduces query errors from typos
- Aligns with platform conventions (Dart, SQL, etc.)

**See Also**: `.claude/guides/best-practices/ditto.md#document-structure-best-practices`

---

## Quick Reference Checklist

- [ ] **ID Generation**: Use UUID v4 (or auto-generated IDs) for distributed systems, NOT sequential IDs
- [ ] **Display IDs**: Consider random suffix for displayId fields (e.g., "ORD-20251219-A7F3") to reduce user confusion
- [ ] **NO Calculated Fields**: DO NOT store lineTotal, subtotal, total, or any value derivable from existing data
- [ ] **Arrays**: Convert mutable arrays to MAP structures (use keys instead of indices)
- [ ] **Denormalization**: Embed data that's always retrieved together (avoid sequential queries)
- [ ] **Field Updates**: Use field-level UPDATE, not full document replacement
- [ ] **DO UPDATE_LOCAL_DIFF**: Use for upserts (SDK 4.12+) to avoid syncing unchanged fields
- [ ] **Check Before Update**: Avoid updating fields with same value (creates unnecessary deltas)
- [ ] **Counters**: Use counter operations (PN_INCREMENT or COUNTER type in 4.14.0+), not SET operations
- [ ] **Event History**: Use separate INSERT documents, not arrays
- [ ] **Document Size**: Keep under 250 KB, use flat models for unbounded data
- [ ] **Large Binaries**: Use ATTACHMENT type for files >250 KB
- [ ] **Two Collections**: Consider dual-write pattern for real-time + historical data
- [ ] **INITIAL Documents**: Use for device-local templates to avoid unnecessary sync
- [ ] **No JOINs**: Design with awareness that JOINs aren't supported

---

## See Also

- **Main Guide**: `.claude/guides/best-practices/ditto.md` (Sections: Collection Design, Data Deletion, CRDT Types)
- **Other Skills**:
  - `query-sync`: Subscription lifecycle, DQL queries
  - `storage-lifecycle`: DELETE, EVICT, tombstone strategies
  - `performance-observability`: Observer optimization, delta minimization
- **Examples**: See `examples/` directory for copy-paste patterns
- **Reference**: See `reference/` for deep dives on CRDT types and merge scenarios
