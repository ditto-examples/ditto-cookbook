# Data Modeling Common Patterns

This reference contains HIGH priority patterns for CRDT-safe data modeling in Ditto. These patterns address frequent scenarios that affect 20-50% of users.

## Table of Contents

- [Pattern 1: Field-Level Updates vs Document Replacement](#pattern-1-field-level-updates-vs-document-replacement)
- [Pattern 2: Event History with Separate Documents](#pattern-2-event-history-with-separate-documents)
- [Pattern 3: Document Size and Relationship Modeling](#pattern-3-document-size-and-relationship-modeling)

---

## Pattern 1: Field-Level Updates vs Document Replacement

**Priority**: HIGH

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

### Solution Patterns

#### Option 1: Field-Level UPDATE (Best for single field changes)

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

#### Option 2: DO UPDATE_LOCAL_DIFF (Best for upserts with many fields)

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

#### Option 3: Check Before Updating (Best for avoiding unnecessary deltas)

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

### Why This Matters

Field-level updates only sync changed fields. Full document replacement increments CRDT counters for ALL fields, even unchanged ones.

**⚠️ CRITICAL**: Even updating with the same value is treated as a delta and synced to all peers.

### Anti-Patterns

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

### Conflict Resolution Options

| Option | Behavior | When to Use |
|--------|----------|-------------|
| `DO UPDATE` | Updates all fields, syncs all as deltas | Never (use UPDATE_LOCAL_DIFF instead) |
| `DO UPDATE_LOCAL_DIFF` (SDK 4.12+) | Only updates/syncs changed fields | Upsert operations with many unchanged fields |
| `DO NOTHING` | Ignores conflict, keeps existing document | Write-once, read-many data |
| `FAIL` | Throws error on conflict (default) | Explicit conflict handling needed |

**See Also**:
- `../examples/field-level-updates.dart`
- SKILL.md Pattern 2.5: DO NOT Store Calculated Fields

---

## Pattern 2: Event History with Separate Documents

**Priority**: HIGH

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

### Solution: Separate INSERT Documents

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

### Why Separate Documents?

Separate documents (INSERT) guarantee preservation of all events. Arrays risk data loss in concurrent scenarios. Separate documents are better for audit logs where completeness is critical.

### Anti-Pattern

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

### Trade-offs

| Approach | Event Preservation | Query Convenience | Document Count |
|----------|-------------------|-------------------|----------------|
| **Separate documents (INSERT)** | ✅ Guaranteed | ✅ Easy filtering/sorting | ⚠️ Higher count |
| **Arrays** | ❌ Risk of loss | ⚠️ Requires extraction | ✅ Fewer docs |

**See Also**:
- `../examples/event-history-good.dart`
- `../examples/event-history-bad.dart`

---

## Pattern 3: Document Size and Relationship Modeling

**Priority**: HIGH

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

### Decision Guide

#### Embed When:
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

#### Use Flat Models When:
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

### Large Binary Data: Use ATTACHMENT Type

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

### Anti-Patterns

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

### Key Considerations

- **Embed benefits**: Single-query access (critical with no JOIN support), simpler code
- **Flat benefits**: Independent sync, concurrent edits without conflicts, parallel sync efficiency
- **Choose based on**: Access patterns, growth potential, document size limits, concurrent edit likelihood

### Size Limits Reference

| Size Threshold | Impact |
|----------------|--------|
| **< 250 KB** | ✅ Optimal performance |
| **250 KB - 5 MB** | ⚠️ Warning threshold, slow sync especially over Bluetooth |
| **> 5 MB** | ❌ Hard limit, will not sync |

**Why**: Ditto has hard 5 MB limit and soft 250 KB warning. Embedded data is faster to query (single query vs sequential queries) but can exceed size limits. Choose based on access patterns and growth potential.

**See Also**:
- `../examples/document-size-optimization.dart`
- `reference/merge-scenarios.md`
- `../SKILL.md` Pattern 2: Denormalization for Query Performance
- `transactions-attachments/SKILL.md` for ATTACHMENT handling

---

## Pattern 4: PN_INCREMENT vs COUNTER Type Comparison

**Priority**: HIGH (Reference for counter implementation)

Quick reference for choosing between PN_INCREMENT (legacy) and COUNTER type (SDK 4.14.0+):

| Feature | PN_INCREMENT | COUNTER Type (SDK 4.14.0+) |
|---------|--------------|---------------------------|
| **SDK Version** | All versions | SDK 4.14.0+ |
| **Syntax** | `PN_INCREMENT BY 1.0` | `INCREMENT BY 1` |
| **Set Value** | Not supported | `RESTART WITH 100` |
| **Reset to Zero** | Not supported | `RESTART` |
| **Explicit Type** | No (inferred) | Yes (declared in collection) |
| **Use Case** | Backward compatibility | New projects on 4.14.0+ |
| **CRDT Type** | Legacy PN_COUNTER | Native COUNTER |
| **Recommended** | Existing projects | ✅ New implementations |
| **Operations** | Increment/Decrement only | Increment/Decrement/Restart |
| **Declaration** | None required | `UPDATE COLLECTION x (field COUNTER)` |

**Migration Note**: Existing projects using `PN_INCREMENT` should continue using it for backward compatibility. New projects on SDK 4.14.0+ should use `COUNTER` type for explicit type declaration and additional operations. Contact Ditto support before migrating existing counters from PN_INCREMENT to COUNTER type.

**See Also**:
- [../examples/counter-patterns.dart](../examples/counter-patterns.dart) for comprehensive examples
- `../SKILL.md` Pattern 4: Counter Patterns

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **advanced-patterns.md**: Complex scenarios (Tier 3)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
