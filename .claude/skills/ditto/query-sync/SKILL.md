---
name: query-sync
description: |
  Validates Ditto DQL queries, subscriptions, and observer patterns.

  CRITICAL ISSUES PREVENTED:
  - Memory leaks from uncanceled subscriptions and QueryResultItems
  - Legacy API usage (non-Flutter: deprecated SDK 4.12+, removed v5)
  - Broad subscriptions causing bandwidth waste
  - Incorrect observer selection and backpressure management

  TRIGGERS:
  - Writing DQL queries (execute())
  - Creating subscriptions (registerSubscription())
  - Setting up observers (registerObserver*)
  - Managing QueryResult/QueryResultItem handling
  - Using legacy builder methods (.collection(), .find(), .upsert())

  PLATFORMS: Flutter (Dart), JavaScript, Swift, Kotlin
---

# Ditto Query and Sync Patterns

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Platform Detection](#platform-detection)
- [SDK Version Compatibility](#sdk-version-compatibility)
- [Common Workflows](#common-workflows)
- [Critical Patterns](#critical-patterns)
  - [1. Legacy API Usage](#1-legacy-api-usage-priority-critical)
  - [2. QueryResultItems Retention](#2-queryresultitems-retention-priority-critical)
  - [3. Subscription Lifecycle Management](#3-subscription-lifecycle-management-priority-critical)
  - [4. Observer Selection](#4-observer-selection-priority-critical---non-flutter-sdks-only)
  - [5. Heavy Processing in Observer Callbacks](#5-heavy-processing-in-observer-callbacks-priority-high)
  - [6. Broad Subscriptions](#6-broad-subscriptions-priority-high)
  - [7. Query Without Active Subscription](#7-query-without-active-subscription-priority-high)
  - [8. Missing signalNext() Call](#8-missing-signalnext-call-priority-high---non-flutter-sdks-only)
  - [9. SELECT * Overuse](#9-select--overuse-priority-high)
  - [10. DISTINCT with _id](#10-distinct-with-_id-priority-high)
  - [11. Unbounded Aggregates](#11-unbounded-aggregates-priority-critical)
  - [12. GROUP BY Without JOIN Awareness](#12-group-by-without-join-awareness-priority-high)
  - [13. Large OFFSET Values](#13-large-offset-values-priority-medium)
  - [14. Expensive Operator Usage](#14-expensive-operator-usage-priority-medium)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

## Purpose

This Skill ensures proper usage of Ditto's query and synchronization APIs. It prevents memory leaks, API compatibility issues, and performance problems related to DQL queries, subscriptions, and observers.

**Critical issues prevented**:
- Memory leaks from QueryResultItems retention
- Memory leaks from uncanceled subscriptions/observers
- Legacy API usage (non-Flutter: deprecated SDK 4.12+, removed v5)
- Broad subscriptions causing bandwidth waste
- Incorrect observer selection and backpressure management

## When This Skill Applies

Use this Skill when:
- Writing DQL queries with `ditto.store.execute()`
- Creating subscriptions with `ditto.sync.registerSubscription()`
- Setting up observers with `ditto.store.registerObserver*()`
- Managing query result handling (`QueryResult`, `QueryResultItem`)
- Using legacy builder methods: `.collection()`, `.find()`, `.upsert()` (DEPRECATED)
- Optimizing query performance or subscription scope
- Implementing subscription/observer lifecycle management

## Platform Detection

**Automatic Detection**:
1. **Flutter/Dart**: `*.dart` files with `import 'package:ditto/ditto.dart'`
2. **JavaScript**: `*.js`, `*.ts` files with `import { Ditto } from '@dittolive/ditto'`
3. **Swift**: `*.swift` files with `import DittoSwift`
4. **Kotlin**: `*.kt` files with `import live.ditto.*`

**Platform-Specific Warnings**:
- **Flutter SDK v4.x**: Only `registerObserver` available (no `signalNext` support until v5.0)
  - **Recommended**: Use `observer.changes` Stream API (Dart-idiomatic, works with StreamBuilder)
  - **Alternative**: Use `onChange` callback for simple cases
- **Flutter SDK v5.0+**: Will support `registerObserverWithSignalNext`
- **Non-Flutter** (Swift, JS, Kotlin): `registerObserverWithSignalNext` recommended (SDK 4.12+)
- **All platforms**: DQL query patterns, subscription management

---

## SDK Version Compatibility

This section consolidates all version-specific information referenced throughout this Skill.

### Flutter SDK

- **v4.x** (current stable)
  - `registerObserver` only (no `signalNext` support)
  - Stream-based API via `observer.changes` (recommended for Flutter UI)
  - `onChange` callback API available for simple cases
  - DQL query API fully supported
  - No legacy builder API (never existed in Flutter SDK)

- **v5.0+** (upcoming)
  - `registerObserverWithSignalNext` support added
  - All v4.x APIs remain supported
  - Stream-based and callback APIs continue to work

### Non-Flutter SDKs (JavaScript, Swift, Kotlin)

- **SDK 4.8 - 4.11**
  - DQL API introduced but legacy builder API still recommended
  - `registerObserver` and `registerObserverWithSignalNext` available

- **SDK 4.12+** (current)
  - Legacy builder methods (.collection(), .find(), .upsert()) **fully deprecated**
  - DQL API is the recommended and supported method
  - `registerObserverWithSignalNext` recommended for most use cases
  - `registerObserver` available for simple cases

- **SDK v5.0+** (upcoming)
  - Legacy builder methods **completely removed**
  - DQL API is the only supported method
  - All observer patterns continue to work

**Throughout this Skill**: When patterns reference "deprecated SDK 4.12+" or "Flutter v4.x limitation", refer back to this section for full context.

---

## Common Workflows

### Workflow 1: Setting Up a New Query with Observer

Copy this checklist and check off items as you complete them:

```
Query Setup Progress:
- [ ] Step 1: Write DQL query with specific WHERE clause
- [ ] Step 2: Create subscription with registerSubscription()
- [ ] Step 3: Set up observer (platform-appropriate pattern)
- [ ] Step 4: Store subscription/observer references
- [ ] Step 5: Implement cancellation in dispose()/cleanup
```

**Step 1: Write DQL query with specific WHERE clause**

Avoid broad subscriptions. Use WHERE to filter data at the source.

```dart
// ✅ GOOD: Specific WHERE clause
'SELECT * FROM orders WHERE status = :status'

// ❌ BAD: No WHERE clause (syncs all data)
'SELECT * FROM orders'
```

**Step 2: Create subscription**

```dart
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'pending'},
);
```

**Step 3: Set up observer (platform-appropriate)**

**Flutter SDK v4.x** - Use `registerObserver` with Stream or callback:

```dart
// Option A: Stream-based (recommended for Flutter UI)
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'pending'},
);

observer.changes.listen((result) {
  setState(() {
    _orders = result.items.map((item) => item.value).toList();
  });
});
```

```dart
// Option B: Callback-based (simple cases)
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'pending'},
  onChange: (result) {
    setState(() {
      _orders = result.items.map((item) => item.value).toList();
    });
  },
);
```

**Non-Flutter SDKs** - Use `registerObserverWithSignalNext`:

```javascript
const observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = $args.status',
  { args: { status: 'pending' } },
  (result, signalNext) => {
    updateUI(result);
    setTimeout(signalNext, 0);  // Call after processing
  }
);
```

**Step 4: Store references**

```dart
class OrdersState {
  DittoSyncSubscription? _subscription;
  DittoStoreObserver? _observer;
}
```

**Step 5: Implement cancellation**

```dart
@override
void dispose() {
  _subscription?.cancel();
  _observer?.cancel();
  super.dispose();
}
```

---

### Workflow 2: Migrating from Legacy API to DQL

**Non-Flutter platforms only** - See [reference/legacy-api-migration.md](reference/legacy-api-migration.md) for complete migration guide.

```
Migration Progress:
- [ ] Step 1: Identify all legacy API usage
- [ ] Step 2: Replace with DQL equivalents
- [ ] Step 3: Update observer patterns if needed
- [ ] Step 4: Test thoroughly
- [ ] Step 5: Remove legacy imports/references
```

---

## Critical Patterns

### 1. Legacy API Usage (Priority: CRITICAL)

**Platform**: Non-Flutter only (JavaScript, Swift, Kotlin)

**Flutter Status**: ✅ Flutter SDK never provided legacy builder API - no concern

**Problem**: Builder methods (`.collection()`, `.find()`, `.findById()`, `.update()`, `.upsert()`, `.remove()`, `.exec()`) are **fully deprecated as of SDK 4.12** and will be **removed in SDK v5**. Code using these methods cannot upgrade to v5 without migration.

**Detection**:
```javascript
// RED FLAGS (non-Flutter platforms)
ditto.store.collection('orders')
ditto.store.collection('users').find("status == 'active'")
  .upsert({...})
  .exec()
```

**✅ DO (All platforms - Current API)**:
```dart
// Dart/Flutter
await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'pending',
      'items': [...],
    },
  },
);
```

```javascript
// JavaScript
await ditto.store.execute(
  'SELECT * FROM orders WHERE status = $args.status',
  { args: { status: 'active' } }
);

await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS ($args.order) ON ID CONFLICT DO UPDATE',
  { args: { order: { _id: 'order_123', status: 'pending' } } }
);
```

**❌ DON'T (Non-Flutter platforms - Deprecated)**:
```javascript
// LEGACY API - FULLY DEPRECATED SDK 4.12+, REMOVED IN SDK v5
const orders = await ditto.store
  .collection('orders')
  .find("status == 'active'")
  .exec();

await ditto.store
  .collection('orders')
  .upsert({ _id: 'order_123', status: 'completed' });
```

**Why**: SDK 4.12+ fully deprecates the builder API in preparation for removal in v5. Migration to DQL required for v5 compatibility. Flutter developers never had this API so no migration needed.

**Migration**: See [reference/legacy-api-migration.md](reference/legacy-api-migration.md)

---

### 2. QueryResultItems Retention (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Retaining QueryResultItems in state, storage, or between observer callbacks causes memory leaks. QueryResultItems are database cursors with lazy-loading that must be extracted immediately.

**Detection**:
```dart
// RED FLAGS
class OrdersState {
  List<QueryResultItem> items = []; // Storing live cursors!
  QueryResult lastResult; // Storing live query result!
}

observer = ditto.store.registerObserver('SELECT * FROM orders', onChange: (result) {
  cachedResult = result; // Retaining result reference!
});
```

**✅ DO**:
```dart
// Extract data immediately from query results
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

// Convert to your model objects right away
final orders = result.items.map((item) {
  final data = item.value; // Materialize once
  return Order.fromJson(data); // Extract to model
}).toList();
// QueryResultItems automatically cleaned up when result goes out of scope

// ✅ Observer pattern - extract in callback
// ⚠️ Note: This uses registerObserverWithSignalNext which is NOT available in Flutter SDK v4.x
// Flutter SDK v4.14.0 and earlier must use registerObserver (without signalNext)
// See Flutter v4.x alternative below

observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM products WHERE category = :category',
  onChange: (result, signalNext) {
    // Extract data immediately - don't retain QueryResultItems
    final products = result.items
      .map((item) => Product.fromJson(item.value))
      .toList();

    updateUI(products); // Use extracted data

    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext(); // Signal readiness after render
    });
    // QueryResultItems cleaned up after callback exits
  },
  arguments: {'category': 'electronics'},
);

// ✅ Flutter SDK v4.x Alternative (No signalNext support):
observer = ditto.store.registerObserver(
  'SELECT * FROM products WHERE category = :category',
  onChange: (result) {
    // No signalNext parameter in Flutter SDK v4.x
    final products = result.items
      .map((item) => Product.fromJson(item.value))
      .toList();
    updateUI(products);
    // No backpressure control available in Flutter v4.x
  },
  arguments: {'category': 'electronics'},
);

// ✅ Flutter SDK v4.x Stream-Based Pattern (Recommended for Flutter):
observer = ditto.store.registerObserver(
  'SELECT * FROM products WHERE category = :category',
  arguments: {'category': 'electronics'},
);

// Listen using Stream API (Dart-idiomatic)
final subscription = observer.changes.listen((result) {
  final products = result.items
    .map((item) => Product.fromJson(item.value))
    .toList();
  updateUI(products);
});

// Cleanup
subscription.cancel();
observer.cancel();
```

**❌ DON'T**:
```dart
// Retaining live QueryResultItems
class ProductsState {
  List<QueryResultItem> items = []; // MEMORY LEAK!

  void onQueryResult(QueryResult result) {
    items = result.items.toList(); // Retains database cursors
  }

  String getProductName(int index) {
    return items[index].value['name']; // Accessing retained cursor
  }
}

// Multiple materializations (inefficient)
final result = await ditto.store.execute('SELECT * FROM orders');
for (var item in result.items) {
  print(item.value); // First materialization
  processOrder(item.value); // Second materialization - wasteful!
  // Should cache item.value in a variable
}
```

**Why**: QueryResultItems are database cursors that hold references to underlying storage. Retaining them prevents garbage collection, causes memory bloat, and keeps database resources locked. Extract data immediately and let Ditto clean up cursors automatically.

**Memory Impact**: Each retained QueryResultItem keeps ~1-10KB in memory depending on document size. In a list of 1000 items, that's 1-10MB of unnecessary memory usage.

**See**: [examples/query-result-handling-good.dart](examples/query-result-handling-good.dart)

---

### 3. Subscription Lifecycle Management (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Uncanceled subscriptions cause memory leaks and unnecessary network traffic. Observers and subscriptions must be canceled when no longer needed.

**Detection**:
```dart
// RED FLAGS
void loadOrders() {
  ditto.sync.registerSubscription('SELECT * FROM orders');
  // No reference stored - can't cancel later!
}

void dispose() {
  // Forgot to cancel subscription and observer - MEMORY LEAK
}

void fetchOnce() {
  final sub = ditto.sync.registerSubscription(...);
  // ... fetch data ...
  sub.cancel(); // Too quick - no time to sync!
}
```

**✅ DO**:
```dart
// Long-lived subscription with proper lifecycle
class OrdersService {
  late final Subscription _subscription;
  late final StoreObserver _observer;

  void initialize() {
    // Start subscription - keep alive for feature lifetime
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Observer receives initial local data + continuous updates as sync occurs
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      onChange: (result, signalNext) {
        final orders = result.items
          .map((item) => Order.fromJson(item.value))
          .toList();

        updateOrdersUI(orders); // Update UI with initial + synced data

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext(); // Ready for next update
        });
      },
      arguments: {'status': 'active'},
    );
  }

  void dispose() {
    // Cancel when feature completely done (e.g., screen disposed)
    _observer.cancel();
    _subscription.cancel();
  }
}
```

**❌ DON'T**:
```dart
// Frequent start/stop (mesh network overhead)
void loadOrders() {
  final sub = ditto.sync.registerSubscription('SELECT * FROM orders');
  // ... fetch data ...
  sub.cancel(); // Creates unnecessary churn
}

// Missing lifecycle management
class OrdersWidget extends StatefulWidget {
  @override
  _OrdersWidgetState createState() => _OrdersWidgetState();
}

class _OrdersWidgetState extends State<OrdersWidget> {
  @override
  void initState() {
    super.initState();

    // No reference stored!
    ditto.sync.registerSubscription('SELECT * FROM orders');
    ditto.store.registerObserver('SELECT * FROM orders', onChange: (result) {
      // Process orders
    });
    // Can't cancel in dispose() - MEMORY LEAK
  }

  @override
  void dispose() {
    // Missing: Cancel subscription and observer
    super.dispose();
  }
}
```

**Why**: Subscriptions tell connected peers what data to sync. Uncanceled subscriptions:
1. **Memory leaks**: Observer callbacks retain references that aren't garbage collected
2. **Network overhead**: Peers continue syncing data you no longer need
3. **Battery drain**: Continuous sync processing for unused data

Frequent start/stop creates mesh network churn (peers constantly updating what data to share).

**Best Practice**: Keep subscriptions alive for the lifetime of the feature (screen, service), cancel on dispose.

**See**: [examples/subscription-lifecycle-good.dart](examples/subscription-lifecycle-good.dart)

---


### 11. Unbounded Aggregates (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Aggregate functions (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`) buffer all matching documents in memory. Unbounded aggregates can crash mobile devices.

**Detection**:
```dart
// RED FLAGS
// No WHERE filter - buffers all documents
await ditto.store.execute('SELECT COUNT(*) FROM orders');

// COUNT(*) for existence check (inefficient)
final count = (await ditto.store.execute(
  'SELECT COUNT(*) FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
)).items.first.value['($1)'];
final hasActive = count > 0;
```

**✅ DO (Filter before aggregating)**:
```dart
// ✅ GOOD: Filtered aggregate
final result = await ditto.store.execute(
  '''SELECT COUNT(*) AS active_orders, AVG(total) AS avg_total
     FROM orders WHERE status = :status AND createdAt >= :cutoff''',
  arguments: {
    'status': 'active',
    'cutoff': DateTime.now().subtract(Duration(days: 30)).toIso8601String(),
  },
);

// ✅ GOOD: GROUP BY reduces result set size
final result = await ditto.store.execute(
  'SELECT status, COUNT(*) AS count FROM orders GROUP BY status',
);

// ✅ BETTER: Use LIMIT 1 for existence checks
final hasActive = (await ditto.store.execute(
  'SELECT _id FROM orders WHERE status = :status LIMIT 1',
  arguments: {'status': 'active'},
)).items.isNotEmpty;
```

**❌ DON'T**:
```dart
// ❌ BAD: Unbounded aggregate in observer (memory buildup)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT COUNT(*) AS total FROM orders', // Buffers all orders
  onChange: (result, signalNext) {
    updateTotalCount(result.items.first.value['total']);
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
);

// ❌ BAD: Aggregate without WHERE (can crash if 100k+ docs)
final avgPrice = (await ditto.store.execute(
  'SELECT AVG(price) FROM products',
)).items.first.value['($1)'];
```

**Why**: Aggregates create a "dam" in the pipeline—all matching documents buffer in memory before returning results. Use `WHERE` filters to reduce buffer size. For existence checks, `LIMIT 1` avoids buffering entirely.

**See Also**: `.claude/guides/best-practices/ditto.md (lines 655-691: Aggregate Functions)`

---




This section contains only the most critical (Tier 1) patterns that prevent data loss, memory leaks, and API deprecation issues. For additional patterns, see:
- **[reference/common-patterns.md](reference/common-patterns.md)**: HIGH priority patterns for observer selection, heavy processing, subscriptions, signalNext(), SELECT optimization, DISTINCT, and GROUP BY
- **[reference/advanced-patterns.md](reference/advanced-patterns.md)**: MEDIUM priority patterns for OFFSET optimization and expensive operator usage

---

### API Usage
- [ ] Using DQL string queries with `ditto.store.execute()` (all platforms)
- [ ] **Non-Flutter**: Not using legacy builder API (`.collection()`, `.find()` - fully deprecated SDK 4.12+, removed v5)
- [ ] **Flutter**: Legacy API warnings don't apply (Flutter SDK never had builder API)
- [ ] Parameterized arguments in queries (`:paramName` for Dart, `$args.paramName` for JS/Swift/Kotlin)
- [ ] **Migration Reference**: See [Legacy API to DQL Quick Reference](.claude/guides/best-practices/ditto.md#legacy-api-to-dql-quick-reference) for systematic CRUD operation mapping

### Memory Management
- [ ] Not retaining QueryResultItems in state, storage, or between callbacks
- [ ] Extracting data immediately from query results with `item.value`
- [ ] Storing subscriptions and observers as class members for lifecycle management
- [ ] Canceling observers and subscriptions in dispose()/cleanup

### Subscription Patterns
- [ ] Active subscriptions for data that needs remote sync
- [ ] Specific WHERE clauses (not broad `SELECT *`)
- [ ] Long-lived subscriptions (not frequent start/stop)
- [ ] Subscriptions canceled only when feature disposed

### Observer Patterns
- [ ] **Non-Flutter SDKs**: Prefer `registerObserverWithSignalNext` (better performance)
- [ ] **Non-Flutter SDKs**: Calling `signalNext()` after render cycle completes (e.g., `addPostFrameCallback`)
- [ ] **Flutter SDK v4.x**: Use `registerObserver` (only option until v5.0)
  - [ ] **Recommended**: Use `observer.changes` Stream API for Dart-idiomatic pattern
  - [ ] **Alternative**: Use `onChange` callback for simple synchronous processing
- [ ] **Flutter SDK v5.0+**: Will support `registerObserverWithSignalNext`
- [ ] Lightweight observer callbacks (extract data only, offload heavy processing)
- [ ] **Legacy observeLocal Migration**: See [Replacing observeLocal](.claude/guides/best-practices/ditto.md#replacing-legacy-observelocal-with-store-observers-sdk-412) for Differ pattern (non-Flutter SDKs)

### Query Optimization
- [ ] Subscriptions have specific WHERE clauses (avoid broad queries)
- [ ] Query + Subscription + Observer pattern for real-time data
- [ ] One-time queries for local-only data (no subscription needed)
- [ ] Using specific field projections instead of `SELECT *` (reduces bandwidth)
- [ ] Not using `DISTINCT` with `_id` field (redundant, wastes memory)
- [ ] Filtering with `WHERE` before aggregates (reduces memory buffer)
- [ ] Using `LIMIT 1` for existence checks (not `COUNT(*)`)
- [ ] Avoiding large `OFFSET` values (linear performance degradation)
- [ ] Combining `LIMIT` with `ORDER BY` (predictable results)
- [ ] Aware that `GROUP BY` doesn't support `JOIN` across collections

## See Also

### Main Guide
- **API Version Awareness**: `.claude/guides/best-practices/ditto.md` lines 64-108
- **SELECT Statements**: `.claude/guides/best-practices/ditto.md#select-statements`
- **Projections**: `.claude/guides/best-practices/ditto.md (lines 596-623: Projections - Field Selection)`
- **DISTINCT**: `.claude/guides/best-practices/ditto.md (lines 626-652: DISTINCT Keyword)`
- **Aggregate Functions**: `.claude/guides/best-practices/ditto.md (lines 655-691: Aggregate Functions)`
- **GROUP BY**: `.claude/guides/best-practices/ditto.md (lines 695-724: GROUP BY)`
- **ORDER BY**: `.claude/guides/best-practices/ditto.md#order-by`
- **LIMIT/OFFSET**: `.claude/guides/best-practices/ditto.md (lines 778-807: LIMIT and OFFSET)`
- **Subscription Patterns**: `.claude/guides/best-practices/ditto.md` lines 1782+
- **Query Result Handling**: `.claude/guides/best-practices/ditto.md#query-result-handling`

### Other Skills
- **data-modeling**: Data structure design, denormalization
- **storage-lifecycle**: EVICT patterns, deletion strategies
- **performance-observability**: Observer performance, UI updates

### Examples
- [examples/dql-queries-good.dart](examples/dql-queries-good.dart)
- [examples/dql-queries-bad.dart](examples/dql-queries-bad.dart)
- [examples/subscription-lifecycle-good.dart](examples/subscription-lifecycle-good.dart)
- [examples/subscription-lifecycle-bad.dart](examples/subscription-lifecycle-bad.dart)
- [examples/observer-patterns-good.dart](examples/observer-patterns-good.dart)
- [examples/observer-patterns-bad.dart](examples/observer-patterns-bad.dart)
- [examples/query-result-handling-good.dart](examples/query-result-handling-good.dart)

### Reference
- [reference/legacy-api-migration.md](reference/legacy-api-migration.md) (non-Flutter platforms)
- [reference/query-optimization.md](reference/query-optimization.md)
