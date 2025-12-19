---
name: storage-lifecycle
description: |
  Validates Ditto data deletion strategies, EVICT operations, and storage optimization.

  CRITICAL ISSUES PREVENTED:
  - Zombie data resurrection from expired tombstone TTL
  - Resync loops from EVICT without subscription cancellation
  - Husked documents (concurrent DELETE/UPDATE)
  - Performance degradation from improper EVICT frequency
  - Data loss from tombstone sharing limitations

  TRIGGERS:
  - Performing DELETE operations
  - Implementing EVICT for local storage cleanup
  - Designing data retention or TTL policies
  - Managing subscription lifecycle around EVICT
  - Filtering logically deleted data in queries
  - Handling husked document edge cases

  PLATFORMS: Flutter (Dart), JavaScript, Swift, Kotlin (cross-platform storage rules)
---

# Ditto Storage Lifecycle Management

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Platform Detection](#platform-detection)
- [SDK Version Compatibility](#sdk-version-compatibility)
- [Common Workflows](#common-workflows)
- [Critical Patterns](#critical-patterns)
  - [1. DELETE Without Tombstone TTL Strategy](#1-delete-without-tombstone-ttl-strategy-priority-critical)
  - [2. EVICT Without Subscription Cancellation](#2-evict-without-subscription-cancellation-priority-critical)
  - [3. Logical Deletion Pattern](#3-logical-deletion-pattern-priority-critical)
  - [4. Husked Document Filtering](#4-husked-document-filtering-priority-high)
  - [5. EVICT Frequency Limits](#5-evict-frequency-limits-priority-high)
  - [6. Opposite Query Pattern for EVICT](#6-opposite-query-pattern-for-evict-priority-high)
  - [7. Top-Level Subscription Declaration](#7-top-level-subscription-declaration-priority-high)
  - [8. Batch Deletion with LIMIT](#8-batch-deletion-with-limit-priority-medium)
  - [9. Big Peer TTL Management](#9-big-peer-ttl-management-priority-medium)
  - [10. Time-Based Eviction Patterns](#10-time-based-eviction-patterns-priority-medium)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## Purpose

This Skill ensures proper data lifecycle management in Ditto's distributed environment. It prevents critical issues like zombie data resurrection from expired tombstones, EVICT-induced resync loops, and husked documents from concurrent DELETE/UPDATE operations.

**Critical issues prevented**:
- Zombie data from expired tombstone TTL
- Resync loops from EVICT without subscription cancellation
- Husked documents from concurrent DELETE/UPDATE
- Performance degradation from improper EVICT frequency
- Data loss from tombstone sharing limitations

## When This Skill Applies

Use this Skill when:
- Performing DELETE operations on collections
- Implementing EVICT for local storage cleanup
- Designing data retention policies or TTL strategies
- Managing subscription lifecycle around EVICT operations
- Handling tombstone TTL configuration (Cloud or Edge)
- Filtering logically deleted data in queries and observers
- Implementing time-based data expiration
- Testing deletion scenarios or zombie data prevention

## Platform Detection

**Automatic Detection**:
1. **Flutter/Dart**: `*.dart` files with `import 'package:ditto/ditto.dart'`
2. **JavaScript**: `*.js`, `*.ts` files with `import { Ditto } from '@dittolive/ditto'`
3. **Swift**: `*.swift` files with `import DittoSwift`
4. **Kotlin**: `*.kt` files with `import live.ditto.*`

**Platform-Specific**: Cross-platform (same storage rules apply to all SDKs)

---

## SDK Version Compatibility

This section consolidates all version-specific information referenced throughout this Skill.

### All Platforms

- **Storage Lifecycle Rules**: Universal across all platforms and SDK versions
  - DELETE creates tombstones with TTL (default: Cloud 30 days, Edge/Big Peer 1 hour)
  - EVICT removes local documents without creating tombstones
  - Husked documents occur from concurrent DELETE/UPDATE operations
  - Logical deletion (isDeleted flag) available in all versions

- **All SDK Versions**
  - DELETE, EVICT operations available
  - Tombstone TTL configuration (Cloud only, via Ditto Portal)
  - EVICT frequency recommendation: Max once per day
  - Subscription cancellation required before EVICT to prevent resync loops

**Throughout this Skill**: Storage lifecycle patterns are consistent across all SDK versions and platforms. No breaking changes or version-specific behaviors.

---

## Common Workflows

### Workflow 1: Implementing Safe Data Deletion

Copy this checklist and check off items as you complete them:

```
Safe Deletion Progress:
- [ ] Step 1: Decide deletion strategy (physical DELETE vs logical deletion)
- [ ] Step 2: If DELETE: Configure tombstone TTL (Cloud only)
- [ ] Step 3: If DELETE: Plan for devices offline > TTL duration
- [ ] Step 4: Implement deletion logic
- [ ] Step 5: Test with offline/online scenarios
```

**Step 1: Choose deletion strategy**

```dart
// Option A: Logical deletion (recommended for most cases)
await ditto.store.execute(
  'UPDATE tasks SET isDeleted = true, deletedAt = :now WHERE _id = :id',
  arguments: {'id': taskId, 'now': DateTime.now().toIso8601String()},
);

// Option B: Physical DELETE (requires tombstone TTL strategy)
await ditto.store.execute(
  'DELETE FROM tasks WHERE _id = :id',
  arguments: {'id': taskId},
);
```

**Step 2: Tombstone TTL configuration** (Cloud deployments only)

- Default: 30 days (Cloud), 1 hour (Edge/Big Peer)
- Configure via Ditto Portal for Cloud deployments
- Consider device offline duration in your use case

**Step 3: Handle zombie data prevention**

```dart
// Query excludes logically deleted items
final result = await ditto.store.execute(
  'SELECT * FROM tasks WHERE isDeleted != true OR isDeleted IS NULL',
);
```

---

### Workflow 2: Implementing EVICT Safely

```
EVICT Implementation Progress:
- [ ] Step 1: Cancel relevant subscriptions
- [ ] Step 2: Query documents to EVICT (use opposite WHERE clause)
- [ ] Step 3: Execute EVICT operation
- [ ] Step 4: Reinstate subscriptions if needed
- [ ] Step 5: Monitor EVICT frequency (max once/day)
```

**Critical**: EVICT without canceling subscriptions causes immediate resync loops.

See Pattern 2 below for complete implementation details.

---

## Critical Patterns

### 1. DELETE Without Tombstone TTL Strategy (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Using DELETE without understanding tombstone TTL can cause "zombie data" - deleted documents reappearing when long-offline devices reconnect after tombstone expiration.

**How Tombstones Work**:
- DELETE creates compressed tombstones (document ID + deletion timestamp)
- Tombstones propagate to peers so they know documents were deleted
- **Cloud TTL**: 30 days (fixed, not configurable)
- **Edge SDK TTL**: Configurable (default: 7 days)
- **CRITICAL**: Tombstones only shared with devices that saw the document before deletion

**Detection**:
```dart
// RED FLAGS
await ditto.store.execute('DELETE FROM orders WHERE _id = :id', ...);
// No documentation of TTL awareness
// No consideration of offline device duration

await ditto.store.execute('DELETE FROM logs WHERE createdAt < :date', ...);
// Batch deletion without LIMIT for 50,000+ documents
```

**✅ DO**:
```dart
// Document TTL strategy and ensure devices connect within window
// Cloud: 30 days, Edge: configurable (default 7 days)

// For temporary data with known lifecycle
final expiryDate = DateTime.now()
    .subtract(const Duration(days: 30))
    .toIso8601String();
await ditto.store.execute(
  'DELETE FROM temporary_data WHERE createdAt < :expiryDate',
  arguments: {'expiryDate': expiryDate},
);
// Note: Tombstone TTL must exceed maximum expected offline duration

// Batch deletion with LIMIT for performance (50,000+ documents)
await ditto.store.execute(
  'DELETE FROM logs WHERE createdAt < :cutoffDate LIMIT 30000',
  arguments: {'cutoffDate': cutoffDate},
);

// Document your TTL strategy in code comments
// "All devices expected to connect within 7 days for fleet management"
```

**❌ DON'T**:
```dart
// Delete without TTL awareness
await ditto.store.execute('DELETE FROM orders WHERE status = :status',
  arguments: {'status': 'completed'});
// Risk: Device offline > 30 days will reintroduce completed orders

// Batch delete 50,000+ documents without LIMIT
await ditto.store.execute('DELETE FROM logs WHERE createdAt < :date',
  arguments: {'date': oldDate});
// Performance impact: Use LIMIT 30000

// Set Edge SDK TTL larger than Cloud TTL (30 days)
// Edge devices may hold tombstones longer than Cloud expects
```

**Why**: If a device reconnects after tombstone TTL expires, its data will be treated as new inserts, causing deleted data to reappear. Tombstones only propagate to devices that have seen the document, so new devices encountering old documents will reintroduce them.

**Zombie Data Scenario**:
1. Device A DELETEs document (tombstone created)
2. Tombstone TTL expires after 30 days
3. Device B (offline for 35 days) reconnects with old document
4. Device B's document treated as new insert (no tombstone exists)
5. Deleted document reappears across mesh (zombie data)

**See**: [examples/logical-deletion-good.dart](examples/logical-deletion-good.dart) for safer alternative

---

### 2. EVICT Without Subscription Cancellation (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Executing EVICT while subscriptions are active creates resync loops - Ditto immediately re-syncs evicted documents because active subscriptions request them.

**EVICT vs DELETE**:
- **DELETE**: Soft-delete (creates tombstone, syncs to peers, keeps data locally)
- **EVICT**: Hard-delete (removes data from local disk, local-only, no tombstone)

**Detection**:
```dart
// RED FLAGS
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted != true',
);

// EVICT without canceling subscription first
await ditto.store.execute(
  'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :oldDate',
  arguments: {'oldDate': oldDate},
);
// Active subscription immediately re-syncs evicted documents!
```

**✅ DO**:
```dart
// Cancel → EVICT → Recreate pattern
class OrderService {
  Subscription? _activeOrdersSubscription;

  Future<void> performDailyEviction() async {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    // Step 1: Cancel affected subscription
    _activeOrdersSubscription?.cancel();

    // Step 2: EVICT old deleted documents (local cleanup)
    await ditto.store.execute(
      'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :cutoffDate',
      arguments: {'cutoffDate': cutoffDate},
    );

    // Step 3: Recreate subscription with updated query
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true AND createdAt > :cutoffDate',
      arguments: {'cutoffDate': cutoffDate},
    );
  }

  void dispose() => _activeOrdersSubscription?.cancel();
}
```

**❌ DON'T**:
```dart
// EVICT without subscription management
await ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
// Active subscription re-syncs evicted data immediately

// Local-scope subscription declarations
void someFunction() {
  final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
  // Can't cancel before EVICT - no reference outside function scope
}
```

**Why**: EVICT removes data locally but doesn't notify peers. Active subscriptions continue requesting evicted documents from connected peers, causing immediate re-sync and defeating the purpose of eviction. Always cancel subscriptions before EVICT.

**Resync Loop**:
1. Subscription active: `SELECT * FROM orders`
2. EVICT executes: removes orders locally
3. Ditto sees subscription still active
4. Ditto requests matching documents from peers
5. Peers send documents back
6. Evicted documents reappear (wasted bandwidth/storage)

**See**: [examples/evict-subscription-management-good.dart](examples/evict-subscription-management-good.dart)

---

### 3. Logical Deletion Pattern (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Physical DELETE with tombstones has TTL risks. Logical deletion (soft-delete with flag) is safer for critical data that must not reappear. **Multi-Hop Relay Constraint**: Subscriptions must NOT filter deletion flags, or deleted documents won't propagate through intermediate peers.

**When to Use Logical Deletion**:
- Critical data that must never reappear unexpectedly
- Documents that may be updated concurrently while deleted
- Applications with long-offline devices (> tombstone TTL)
- Data requiring undo/restore functionality

**Detection**:
```dart
// RED FLAGS for critical data
await ditto.store.execute('DELETE FROM orders WHERE status = :status',
  arguments: {'status': 'cancelled'});
// Physical deletion of business-critical orders - risky!

// Missing deletion flag in queries
final result = await ditto.store.execute('SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'});
// Will include logically deleted documents if flag not checked
```

**✅ DO**:
```dart
// 1. Mark as deleted (not actual deletion)
final deletedAt = DateTime.now().toIso8601String();
await ditto.store.execute(
  'UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'deletedAt': deletedAt},
);

// Alternative naming: isArchived, deletedFlag, archivedAt (choose one, be consistent)

// 2. Filter in execute() queries for app logic
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE isDeleted != true AND status = :status',
  arguments: {'status': 'active'},
);
final activeOrders = result.items.map((item) => item.value).toList();

// 3. Subscribe to ALL documents (CRITICAL for multi-hop relay)
// ⚠️ DO NOT filter isDeleted in subscription - breaks relay propagation
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders',  // No isDeleted filter - enables proper relay
);

// 4. Observer filters deleted items for UI display
// (but subscription above has no filter for proper relay)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE isDeleted != true ORDER BY createdAt DESC',
  onChange: (result, signalNext) {
    updateUI(result.items);
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
);

// 5. Periodically evict old deleted documents (local cleanup)
// Cancel subscription first (see Pattern 2)
final oldDate = DateTime.now()
    .subtract(const Duration(days: 90))
    .toIso8601String();
await ditto.store.execute(
  'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :oldDate',
  arguments: {'oldDate': oldDate},
);
```

**❌ DON'T**:
```dart
// ❌ BAD: Filtering deletion flag in subscription (breaks multi-hop relay!)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted != true',  // BREAKS RELAY!
);
// Problem: Deleted documents won't propagate to indirectly connected peers

// Forget to filter in observers/execute() queries
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status', // Missing isDeleted filter!
  arguments: {'status': 'active'},
);
// Includes logically deleted documents in app logic

// Use inconsistent field names
await ditto.store.execute('UPDATE orders SET isDeleted = true WHERE _id = :id1', ...);
await ditto.store.execute('UPDATE products SET deletedFlag = true WHERE _id = :id2', ...);
// Inconsistent naming makes queries error-prone

// Skip EVICT for local cleanup
// Logically deleted documents accumulate, wasting storage
```

**Why**: Logical deletion prevents zombie data by keeping documents in the system with a flag. It's safer than physical DELETE (no tombstone TTL risk), supports undo/restore, and prevents husked documents. **Critical pattern**: Subscriptions must include ALL documents (even deleted) for multi-hop relay to work. Only filter in observers (for UI) and execute() queries (for app logic). If subscriptions filter deletion flags, intermediate peers won't relay deleted documents to other peers, causing inconsistent state across the mesh network.

**Comparison**:

| Aspect | Logical Deletion | DELETE (Tombstones) |
|--------|------------------|---------------------|
| Safety | ✅ No zombie data | ⚠️ Tombstone TTL risk |
| Code Complexity | ⚠️ Filter everywhere | ✅ Automatic |
| Performance | ⚠️ Larger dataset | ✅ Smaller dataset |
| Undo Support | ✅ Easy restore | ❌ Cannot undo |

**See**: [examples/logical-deletion-good.dart](examples/logical-deletion-good.dart)

---

### 4. Husked Document Filtering (Priority: HIGH)

**Platform**: All platforms

**Problem**: Concurrent DELETE and UPDATE operations create "husked documents" - partially deleted documents with mix of null and updated fields. Queries must filter these out.

**How Husking Occurs**:
1. Device A executes DELETE (sets all fields to null)
2. Device B executes UPDATE concurrently (updates specific fields)
3. When devices sync, Ditto merges field-by-field (CRDT behavior)
4. Result: Document with some null fields and some updated fields

**Detection**:
```dart
// RED FLAGS
final result = await ditto.store.execute('SELECT * FROM cars');
final cars = result.items.map((item) => item.value).toList();

// No null checks for required fields
for (var car in cars) {
  print('${car['make']} ${car['model']}'); // NPE if fields are null!
}
```

**✅ DO**:
```dart
// Filter out husked documents in queries
final result = await ditto.store.execute(
  'SELECT * FROM cars WHERE make IS NOT NULL AND model IS NOT NULL AND isDeleted != true',
);

// Validate documents have required fields
final cars = result.items.map((item) {
  final data = item.value;
  // Check for required fields
  if (data['make'] == null || data['model'] == null) {
    return null; // Skip husked documents
  }
  return Car.fromJson(data);
}).whereType<Car>().toList();

// Prefer logical deletion to avoid husking entirely
await ditto.store.execute(
  'UPDATE cars SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
  arguments: {'deletedAt': DateTime.now().toIso8601String(), 'id': carId},
);
```

**❌ DON'T**:
```dart
// Query without null checks
final result = await ditto.store.execute('SELECT * FROM cars');
// Husked documents included

// Assume DELETE prevents concurrent updates
await ditto.store.execute('DELETE FROM cars WHERE _id = :id', ...);
// Offline device may UPDATE the same car, creating husked document

// Ignore null fields in application logic
final make = car['make']; // Null if husked!
final model = car['model']; // Null if husked!
displayCar(make, model); // Application error
```

**Why**: Ditto's CRDT performs field-level merging. DELETE sets each field to null, UPDATE sets specific fields to new values. When merging, Ditto keeps the most recent operation per field, resulting in husked documents. Logical deletion prevents husking entirely.

**Husked Document Example**:
```dart
// Device A: DELETE car
{_id: "abc123", color: null, make: null, model: null, year: null}

// Device B (offline): UPDATE car color
{_id: "abc123", color: "blue"}

// After sync - Husked document:
{_id: "abc123", color: "blue", make: null, model: null, year: null}
```

**See**: [examples/logical-deletion-good.dart](examples/logical-deletion-good.dart)

---

### 5. EVICT Frequency Limits (Priority: HIGH)

**Platform**: All platforms

**Problem**: Running EVICT more than once per day creates excessive network traffic and processing overhead as evicted data re-syncs from peers.

**Detection**:
```dart
// RED FLAGS
Timer.periodic(Duration(hours: 1), (_) {
  ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
  // Too frequent! Runs 24 times per day
});

Timer.periodic(Duration(minutes: 30), (_) {
  performEviction(); // Even worse - 48 times per day
});
```

**✅ DO**:
```dart
// Schedule once per day during low-usage period
Timer.periodic(Duration(days: 1), (_) async {
  // Run at 3 AM local time or during detected low-usage period
  if (isLowUsagePeriod()) {
    await performDailyEviction();
  }
});

// Or use cron-like scheduling
Future<void> scheduleEviction() async {
  final now = DateTime.now();
  final nextRun = DateTime(now.year, now.month, now.day + 1, 3, 0, 0);
  final delay = nextRun.difference(now);

  Timer(delay, () async {
    await performDailyEviction();
    scheduleEviction(); // Schedule next day
  });
}

Future<void> performDailyEviction() async {
  // Cancel subscriptions
  // EVICT old data
  // Recreate subscriptions
}
```

**❌ DON'T**:
```dart
// Frequent eviction
Timer.periodic(Duration(hours: 1), (_) => performEviction());
// Network overhead from resync

// Evict during peak usage
await performEviction(); // Runs during business hours
// Users experience slower performance

// Evict without scheduling strategy
// Ad-hoc eviction creates unpredictable performance
```

**Why**: Eviction can trigger resyncs with connected peers if subscriptions overlap. Running too frequently causes network churn and processing overhead. Once per day during low-usage periods balances storage cleanup with performance.

**Performance Impact**:
- **Once per day**: ~1-5 seconds processing, minimal network traffic
- **Every hour**: 24× processing overhead, potential for resync loops
- **Every 30 minutes**: Significant battery drain on mobile devices

**See**: [examples/evict-subscription-management-good.dart](examples/evict-subscription-management-good.dart)

---

### 6. Opposite Query Pattern for EVICT (Priority: HIGH)

**Platform**: All platforms

**Problem**: Using the same or overlapping query for subscription and eviction creates resync loops. Subscription and eviction queries must be opposites.

**Detection**:
```dart
// RED FLAGS
// Subscription query
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted = true',
);

// Eviction query (overlaps with subscription!)
await ditto.store.execute(
  'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :oldDate',
  arguments: {'oldDate': oldDate},
);
// Evicted documents immediately re-synced by subscription
```

**✅ DO**:
```dart
// Opposite queries - subscription and eviction don't overlap

// Subscription query (keeps non-deleted documents)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE isDeleted != true',
);

// Eviction query (removes deleted documents)
await ditto.store.execute(
  'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :oldDate',
  arguments: {'oldDate': oldDate},
);
// No overlap - no resync

// Flag-based eviction with opposite subscription
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE evictionFlag != true',
);

await ditto.store.execute(
  'EVICT FROM orders WHERE evictionFlag = true',
);
```

**❌ DON'T**:
```dart
// Same query for subscription and eviction
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE createdAt < :oldDate',
  arguments: {'oldDate': cutoffDate},
);

await ditto.store.execute(
  'EVICT FROM orders WHERE createdAt < :oldDate',
  arguments: {'oldDate': cutoffDate},
);
// Identical queries = immediate resync loop

// Overlapping queries
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders', // All orders
);

await ditto.store.execute(
  'EVICT FROM orders WHERE status = :status',
  arguments: {'status': 'completed'},
);
// Subscription includes completed orders - resync
```

**Why**: The query used for eviction must be the opposite of queries used for subscriptions. Overlapping queries cause Ditto to immediately re-sync evicted documents, defeating the purpose of eviction and creating network/storage churn.

**⚠️ Important Distinction: EVICT vs Soft-Delete Subscriptions**:
- **For EVICT operations**: The examples above are correct - use opposite queries (subscription excludes what eviction removes)
- **For soft-delete without EVICT**: Subscriptions should NOT filter deletion flags (see Pattern 3). Subscribe broadly (`SELECT * FROM orders`) to enable multi-hop relay, filter only in observers/queries
- The "opposite query" pattern applies specifically to EVICT operations where you explicitly want to avoid resyncing evicted data

**See**: [examples/flag-based-eviction.dart](examples/flag-based-eviction.dart)

---

### 7. Top-Level Subscription Declaration (Priority: HIGH)

**Platform**: All platforms

**Problem**: Declaring subscriptions in local function scope prevents access for cancellation before EVICT, causing resync loops.

**Detection**:
```dart
// RED FLAGS
void initializeOrders() {
  final subscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE isDeleted != true',
  );
  // Local scope - can't cancel outside this function
}

void performEviction() {
  // No reference to subscription - can't cancel before EVICT!
  await ditto.store.execute('EVICT FROM orders WHERE isDeleted = true');
  // Resync loop inevitable
}
```

**✅ DO**:
```dart
// Top-level (class-level) subscription management
class OrderService {
  Subscription? _activeOrdersSubscription;

  Future<void> initialize() async {
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true',
    );
  }

  Future<void> performEviction() async {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    // Can access subscription - cancel before EVICT
    _activeOrdersSubscription?.cancel();

    await ditto.store.execute(
      'EVICT FROM orders WHERE isDeleted = true AND deletedAt < :cutoffDate',
      arguments: {'cutoffDate': cutoffDate},
    );

    // Recreate subscription
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE isDeleted != true AND createdAt > :cutoffDate',
      arguments: {'cutoffDate': cutoffDate},
    );
  }

  void dispose() => _activeOrdersSubscription?.cancel();
}
```

**❌ DON'T**:
```dart
// Local scope subscriptions
void someFunction() {
  final sub = ditto.sync.registerSubscription('SELECT * FROM orders');
  // Can't cancel outside this function
}

// Global variables without structured access
Subscription? globalOrdersSubscription;

void function1() {
  globalOrdersSubscription = ditto.sync.registerSubscription(...);
}

void function2() {
  globalOrdersSubscription?.cancel(); // Fragile - may be null
}
```

**Why**: EVICT requires canceling affected subscriptions first to prevent resync loops. Top-level declaration ensures subscription references are accessible throughout the app lifecycle for proper management.

**See**: [examples/evict-subscription-management-good.dart](examples/evict-subscription-management-good.dart)

---

### 8. Batch Deletion with LIMIT (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Deleting 50,000+ documents at once without LIMIT impacts performance and may block other operations.

**Detection**:
```dart
// RED FLAGS
await ditto.store.execute(
  'DELETE FROM logs WHERE createdAt < :cutoffDate',
  arguments: {'cutoffDate': cutoffDate},
);
// No LIMIT - if 100,000 logs exist, deletes all at once
```

**✅ DO**:
```dart
// Use LIMIT for batch deletions (50,000+ documents)
await ditto.store.execute(
  'DELETE FROM logs WHERE createdAt < :cutoffDate LIMIT 30000',
  arguments: {'cutoffDate': cutoffDate},
);

// For very large datasets, delete in batches
Future<void> deleteLargeBatch(String cutoffDate) async {
  int deletedCount;
  do {
    final result = await ditto.store.execute(
      'DELETE FROM logs WHERE createdAt < :cutoffDate LIMIT 30000',
      arguments: {'cutoffDate': cutoffDate},
    );
    deletedCount = result.mutationCount;
    // Allow other operations between batches
    await Future.delayed(Duration(milliseconds: 100));
  } while (deletedCount > 0);
}
```

**❌ DON'T**:
```dart
// Delete 50,000+ documents without LIMIT
await ditto.store.execute('DELETE FROM logs WHERE createdAt < :date', ...);
// Performance impact

// Delete in tiny batches
await ditto.store.execute('DELETE FROM logs ... LIMIT 100', ...);
// Too many operations - use LIMIT 30000
```

**Why**: Large batch deletions can block other database operations. LIMIT 30000 provides good balance between efficiency and responsiveness. For datasets > 50,000 documents, batch deletions prevent performance degradation.

---

### 9. Big Peer TTL Management (Priority: MEDIUM)

**Platform**: All platforms (Big Peer HTTP API + Edge SDK)

**Problem**: Centralized TTL management via Big Peer HTTP API is more reliable than device-local eviction for preventing data loss.

**When to Use Big Peer Management**:
- Using Ditto Cloud/Server (Big Peer)
- Need centralized eviction control
- Want to ensure data syncs before eviction
- Prevent accidental data loss from premature eviction

**Detection**:
```dart
// SUBOPTIMAL: Device-local eviction without Big Peer coordination
// Risk: Device evicts data before it syncs to cloud
await ditto.store.execute(
  'EVICT FROM orders WHERE createdAt < :cutoffDate',
  arguments: {'cutoffDate': cutoffDate},
);
```

**✅ DO (Big Peer Pattern)**:
```dart
// Step 1: Big Peer HTTP API sets eviction flags
// (Run on Big Peer/Cloud, not Edge devices)
// POST /api/v1/collections/orders/documents/bulk-update
// {
//   "filter": "createdAt < '2024-01-01'",
//   "update": { "evictionFlag": true }
// }

// Step 2: Edge devices query and evict flagged documents
Future<void> evictFlaggedDocuments() async {
  // Cancel subscription
  ordersSubscription?.cancel();

  // EVICT flagged documents
  await ditto.store.execute(
    'EVICT FROM orders WHERE evictionFlag = true',
  );

  // Recreate subscription (opposite query)
  ordersSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE evictionFlag != true',
  );
}
```

**❌ DON'T**:
```dart
// Set Edge SDK TTL larger than Cloud TTL (30 days)
// Edge devices may hold tombstones longer than Cloud expects

// Device-local eviction of data that hasn't synced to cloud
// Risk: Data loss if device fails before sync
```

**Why**: Big Peer centralized management ensures data syncs to cloud before eviction. Prevents data loss from premature local eviction. Edge devices evict only after cloud confirms data is safely stored.

**See**: [examples/ttl-eviction-big-peer.dart](examples/ttl-eviction-big-peer.dart)

---

### 10. Time-Based Eviction Patterns (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Applications need industry-specific TTL strategies for time-sensitive data (flights, transactions, orders).

**Detection**:
```dart
// SUBOPTIMAL: No TTL strategy for time-sensitive data
// Data accumulates indefinitely
```

**✅ DO**:
```dart
// Industry-specific TTL examples
// Airlines: 72-hour TTL for flight data
Future<void> evictOldFlightData() async {
  final cutoffDate = DateTime.now()
      .subtract(const Duration(hours: 72))
      .toIso8601String();

  flightSubscription?.cancel();

  await ditto.store.execute(
    'EVICT FROM flights WHERE departureTime < :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  flightSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM flights WHERE departureTime >= :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}

// Retail: 7-day TTL for transaction data
Future<void> evictOldTransactions() async {
  final cutoffDate = DateTime.now()
      .subtract(const Duration(days: 7))
      .toIso8601String();

  transactionSubscription?.cancel();

  await ditto.store.execute(
    'EVICT FROM transactions WHERE createdAt < :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  transactionSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM transactions WHERE createdAt >= :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}

// Quick-service restaurants: 24-hour TTL for order data
Future<void> evictOldOrders() async {
  final cutoffDate = DateTime.now()
      .subtract(const Duration(hours: 24))
      .toIso8601String();

  orderSubscription?.cancel();

  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );

  orderSubscription = ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE createdAt >= :cutoffDate',
    arguments: {'cutoffDate': cutoffDate},
  );
}
```

**❌ DON'T**:
```dart
// Use arbitrary TTL without business justification
final cutoffDate = DateTime.now().subtract(const Duration(days: 100));
// Why 100 days? Should match business requirements

// Evict time-sensitive data without considering offline devices
// Devices offline during eviction window lose data context
```

**Why**: Different industries have different data lifecycle requirements. Airlines need recent flight data, retail needs recent transactions, QSRs need recent orders. Align TTL with business needs and ensure devices connect within the eviction window.

**See**: [examples/ttl-eviction-small-peer.dart](examples/ttl-eviction-small-peer.dart)

---

## Quick Reference Checklist

### Deletion Strategy
- [ ] Understand tombstone TTL implications (Cloud: 30 days, Edge: configurable)
- [ ] Document TTL strategy in code comments
- [ ] Ensure all devices connect within TTL window
- [ ] Use LIMIT for batch deletions (50,000+ documents)
- [ ] Consider logical deletion for critical data

### EVICT Management
- [ ] Cancel affected subscriptions before EVICT
- [ ] Recreate subscriptions after EVICT with updated query
- [ ] Use opposite queries for subscription vs eviction
- [ ] Limit EVICT frequency to once per day maximum
- [ ] Schedule EVICT during low-usage periods
- [ ] Declare subscriptions at top-level scope (class-level)

### Logical Deletion
- [ ] Use consistent field name (`isDeleted`, `isArchived`, etc.)
- [ ] **CRITICAL**: Subscriptions must include ALL documents (no deletion filter) for multi-hop relay
- [ ] Filter deleted documents in observers (for UI display)
- [ ] Filter deleted documents in execute() queries (for app logic)
- [ ] Periodically EVICT old logically deleted documents
- [ ] Cancel subscriptions before EVICT of logically deleted data

### Husked Documents
- [ ] Filter husked documents with `IS NOT NULL` checks for required fields
- [ ] Validate documents have required fields before processing
- [ ] Prefer logical deletion to avoid husking entirely
- [ ] Don't use DELETE for documents with concurrent UPDATE risk

### Storage Optimization
- [ ] Implement time-based eviction matching business requirements
- [ ] Use Big Peer management for centralized eviction control (if using Cloud)
- [ ] Never set Edge SDK TTL larger than Cloud TTL (30 days)

---

## See Also

### Main Guide
- Data Deletion Strategies: [.claude/guides/best-practices/ditto.md lines 780-1008](../../guides/best-practices/ditto.md)
- Device Storage Management: [.claude/guides/best-practices/ditto.md lines 3002-3218](../../guides/best-practices/ditto.md)
- Husked Documents: [.claude/guides/best-practices/ditto.md lines 942-1006](../../guides/best-practices/ditto.md)

### Other Skills
- [query-sync](../query-sync/SKILL.md) - Subscription lifecycle management
- [data-modeling](../data-modeling/SKILL.md) - Logical deletion field design

### Examples
- [examples/logical-deletion-good.dart](examples/logical-deletion-good.dart) - Safe deletion with flags
- [examples/evict-subscription-management-good.dart](examples/evict-subscription-management-good.dart) - Cancel → EVICT → recreate pattern
- [examples/ttl-eviction-big-peer.dart](examples/ttl-eviction-big-peer.dart) - Centralized eviction control
- [examples/ttl-eviction-small-peer.dart](examples/ttl-eviction-small-peer.dart) - Device-local eviction
- [examples/flag-based-eviction.dart](examples/flag-based-eviction.dart) - Opposite query pattern

### Reference
- [Ditto Delete Documentation](https://docs.ditto.live/sdk/latest/crud/delete)
- [Ditto Device Storage Management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)
