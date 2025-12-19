---
name: query-sync
description: Validates Ditto DQL queries, subscriptions, and observer patterns. Prevents memory leaks from uncanceled subscriptions and retained QueryResultItems. Enforces current DQL API usage (SDK 4.12+ deprecates legacy builder methods in non-Flutter SDKs). Optimizes subscription scope and observer performance. Use when writing DQL queries, creating subscriptions, setting up observers, or managing query result handling.
---

# Ditto Query and Sync Patterns

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

### 4. Observer Selection (Priority: CRITICAL - Non-Flutter SDKs Only)

**Platform**: Swift, JavaScript, Kotlin (NOT applicable to Flutter SDK v4.x)

**⚠️ Flutter SDK Exception:**
Flutter SDK v4.14.0 and earlier ONLY provide `registerObserver`. This pattern does not apply to Flutter SDK v4.x, as `registerObserverWithSignalNext` is not available until Flutter SDK v5.0.

**Problem**: Using `registerObserver` instead of `registerObserverWithSignalNext` can cause memory issues and performance degradation. The wrong observer type doesn't provide backpressure control.

**Recommendation**: **Prefer `registerObserverWithSignalNext`** for all observer use cases on non-Flutter SDKs. It provides better performance through predictable backpressure control.

**Detection**:
```dart
// SUBOPTIMAL
final observer = ditto.store.registerObserver(
  'SELECT * FROM products',
  onChange: (result) {
    // No backpressure control - callbacks can accumulate
    updateUI(result.items);
  },
);
```

**✅ DO (Use registerObserverWithSignalNext)**:
```dart
// ✅ RECOMMENDED: Observer with backpressure control
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
  onChange: (result, signalNext) {
    // Extract data immediately (lightweight)
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

**❌ DON'T (Use registerObserver only for trivial cases)**:
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

**Why**: `registerObserverWithSignalNext` provides:
- **Better performance**: Explicit control prevents callback queue buildup
- **Memory safety**: Prevents crashes from uncontrolled callback accumulation
- **Predictable behavior**: You control when the next update arrives

**When in doubt, use `registerObserverWithSignalNext`** - it's the recommended pattern for most use cases.

**See**: [examples/observer-patterns-good.dart](examples/observer-patterns-good.dart)

---

### 5. Heavy Processing in Observer Callbacks (Priority: HIGH)

**Platform**: All platforms

**Problem**: Performing heavy processing (complex computations, network calls, file I/O) inside observer callbacks blocks the observer thread, degrading performance.

**Detection**:
```dart
// RED FLAGS
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();

    // ❌ Heavy computation blocks callback
    for (final order in orders) {
      final analysis = performExpensiveAnalysis(order); // BLOCKS!
      final report = generateDetailedReport(order); // BLOCKS!
      sendToAnalyticsService(report); // Network call BLOCKS!
    }

    signalNext(); // Only called after all heavy processing
  },
);
```

**✅ DO (Lightweight callback, offload heavy processing)**:
```dart
// ✅ GOOD: Lightweight callback with async offload
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

**Why**: Observer callbacks should be lightweight. Heavy processing blocks the callback, preventing `signalNext()` from being called promptly, which causes backpressure buildup and memory issues.

**Best Practice**: Extract data, update UI, call `signalNext()` quickly. Offload heavy work to async functions.

---

### 6. Broad Subscriptions (Priority: HIGH)

**Platform**: All platforms

**Problem**: Subscriptions without specific WHERE clauses sync unnecessary data, wasting bandwidth and storage.

**Detection**:
```dart
// RED FLAGS
// Too broad - syncs everything
ditto.sync.registerSubscription('SELECT * FROM orders');

// Missing useful filters
ditto.sync.registerSubscription('SELECT * FROM products');
```

**✅ DO (Specific subscriptions)**:
```dart
// ✅ GOOD: Specific WHERE clause
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status AND userId = :userId',
  arguments: {'status': 'active', 'userId': currentUserId},
);

// ✅ GOOD: Time-based filter
final cutoffDate = DateTime.now().subtract(Duration(days: 30)).toIso8601String();
final recentSub = ditto.sync.registerSubscription(
  'SELECT * FROM events WHERE createdAt >= :cutoff',
  arguments: {'cutoff': cutoffDate},
);
```

**❌ DON'T (Overly broad)**:
```dart
// ❌ BAD: No filters - syncs entire collection
ditto.sync.registerSubscription('SELECT * FROM orders');

// ❌ BAD: Minimal filtering when more specific is possible
ditto.sync.registerSubscription('SELECT * FROM products WHERE category IS NOT NULL');
```

**Why**: Broad subscriptions:
1. **Waste bandwidth**: Syncing data you don't need
2. **Waste storage**: Storing unnecessary documents locally
3. **Slow initial sync**: More data = longer sync time
4. **Battery drain**: Processing and storing extra data

**Best Practice**: Subscribe only to data you actually need. Use WHERE clauses to filter by user, date range, status, or other relevant criteria.

---

### 7. Query Without Active Subscription (Priority: HIGH)

**Platform**: All platforms

**Problem**: Running `execute()` without an active subscription returns only locally cached data - it won't fetch data from other peers.

**Detection**:
```dart
// RED FLAG
// Query runs, but no subscription means no remote sync
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
// Returns only local data - incomplete if remote peers have more
```

**✅ DO (Subscription + Query)**:
```dart
// ✅ GOOD: Start subscription first (or alongside query)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);

// Query returns local data immediately, subscription syncs remote data over time
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
final orders = result.items.map((item) => item.value).toList();

// Use observer for real-time updates as data syncs
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => Order.fromJson(item.value)).toList();
    updateUI(orders); // UI updates as remote data syncs in
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
  arguments: {'status': 'active'},
);

// Cancel when done
// subscription.cancel();
// observer.cancel();
```

**Alternative: One-time local query**:
```dart
// ✅ OK: Explicitly querying local data only
final result = await ditto.store.execute(
  'SELECT * FROM cachedConfig WHERE key = :key',
  arguments: {'key': 'appVersion'},
);
// Intentionally local-only - no remote sync needed
```

**Why**: Without a subscription, `execute()` only sees locally cached data. You won't receive updates from remote peers. Use subscriptions to enable peer-to-peer sync.

**Pattern**: Subscription (declares data needs) + Observer (receives updates) + Query (initial snapshot)

---

### 8. Missing signalNext() Call (Priority: HIGH - Non-Flutter SDKs Only)

**Platform**: Swift, JavaScript, Kotlin (NOT applicable to Flutter SDK v4.x)

**⚠️ Flutter SDK Exception:**
This anti-pattern does not apply to Flutter SDK v4.14.0 and earlier, as `signalNext` is not available. Flutter SDK v5.0 will add `signalNext` support.

**Problem**: When using `registerObserverWithSignalNext`, forgetting to call `signalNext()` prevents the observer from receiving further updates.

**Detection**:
```dart
// RED FLAG
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM products',
  onChange: (result, signalNext) {
    final products = result.items.map((item) => item.value).toList();
    updateUI(products);
    // Missing signalNext() - observer is blocked!
  },
);
```

**✅ DO (Call signalNext after render)**:
```dart
// ✅ GOOD: signalNext after render cycle
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM products',
  onChange: (result, signalNext) {
    final products = result.items.map((item) => Product.fromJson(item.value)).toList();
    updateUI(products);

    // Call signalNext after render cycle completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
);
```

**Why**: `signalNext()` tells Ditto you're ready for the next update. Without it, the observer stops receiving callbacks, and your UI won't update when data changes.

**Best Practice**: Always call `signalNext()` after your render cycle completes (use `addPostFrameCallback` in Flutter).

---

### 9. SELECT * Overuse (Priority: HIGH)

**Platform**: All platforms

**Problem**: Using `SELECT *` when you only need specific fields wastes bandwidth in P2P mesh networks. Every field syncs across peers.

**Detection**:
```dart
// RED FLAG
final result = await ditto.store.execute(
  'SELECT * FROM cars WHERE color = :color',
  arguments: {'color': 'blue'},
);
// Syncs all fields even if you only need make, model, year
```

**✅ DO (Select specific fields)**:
```dart
// ✅ GOOD: Specific fields only
final result = await ditto.store.execute(
  'SELECT make, model, year FROM cars WHERE color = :color',
  arguments: {'color': 'blue'},
);

// ✅ GOOD: Calculated fields with alias
final result = await ditto.store.execute(
  'SELECT make, model, price * 0.9 AS discounted_price FROM cars',
);
```

**❌ DON'T**:
```dart
// ❌ BAD: SELECT * in high-frequency queries
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data', // Syncs all fields unnecessarily
  onChange: (result, signalNext) {
    // Only using 'temperature' field - waste of bandwidth
    final temps = result.items.map((item) => item.value['temperature']).toList();
    updateUI(temps);
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
);
```

**Why**: On Bluetooth LE (~20 KB/s max), unnecessary fields cause significant performance degradation. Use projections to minimize synced data.

**See Also**: `.claude/guides/best-practices/ditto.md (lines 596-623: Projections - Field Selection)`

---

### 10. DISTINCT with _id (Priority: HIGH)

**Platform**: All platforms

**Problem**: Using `DISTINCT` with `_id` field is redundant (every document has unique `_id`) and wastes memory by buffering all rows.

**Detection**:
```dart
// RED FLAG
final result = await ditto.store.execute(
  'SELECT DISTINCT _id, color FROM cars',
);
// _id is already unique - DISTINCT adds no value
```

**✅ DO (Use DISTINCT appropriately)**:
```dart
// ✅ GOOD: DISTINCT on non-unique field with filter
final result = await ditto.store.execute(
  'SELECT DISTINCT color FROM cars WHERE year >= :year',
  arguments: {'year': 2020},
);

// ✅ GOOD: Omit DISTINCT when selecting _id
final result = await ditto.store.execute(
  'SELECT _id, color FROM cars WHERE year >= :year',
  arguments: {'year': 2020},
);
```

**❌ DON'T**:
```dart
// ❌ BAD: DISTINCT with _id (redundant)
final result = await ditto.store.execute(
  'SELECT DISTINCT _id, make, model FROM cars',
);

// ❌ BAD: DISTINCT on unbounded dataset (memory impact)
final result = await ditto.store.execute(
  'SELECT DISTINCT customerId FROM orders',
);
// Can crash mobile devices if millions of orders
```

**Why**: `DISTINCT` buffers all rows in memory. When `_id` is included, results are already unique—`DISTINCT` adds no value but causes high memory usage.

**Complex Object _id**:

When using complex object `_id` (composite keys), the same uniqueness guarantee applies:

```dart
// ❌ BAD: DISTINCT with complex object _id (still redundant)
final result = await ditto.store.execute(
  'SELECT DISTINCT _id, status FROM orders',
);
// _id (even as object) is still unique per document

// ✅ GOOD: Query by component without DISTINCT
final result = await ditto.store.execute(
  'SELECT _id, status FROM orders WHERE _id.locationId = :locId',
  arguments: {'locId': 'store_001'},
);

// ✅ GOOD: DISTINCT on specific _id component (if needed)
final result = await ditto.store.execute(
  'SELECT DISTINCT _id.locationId FROM orders',
);
// Returns unique location IDs
```

**See Also**: `.claude/guides/best-practices/ditto.md (lines 626-652: DISTINCT Keyword)`, `.claude/guides/best-practices/ditto.md (lines 1703-1809: Document Structure Best Practices)`, `data-modeling/examples/complex-id-patterns.dart`

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

### 12. GROUP BY Without JOIN Awareness (Priority: HIGH)

**Platform**: All platforms

**Problem**: Attempting to use `GROUP BY` as a substitute for `JOIN` operations. Ditto does not support `JOIN` across collections.

**Detection**:
```dart
// RED FLAGS
// Attempting to "join" collections
final result = await ditto.store.execute(
  '''SELECT orders.customerId, customers.name, COUNT(*) AS order_count
     FROM orders GROUP BY orders.customerId''',
);
// ERROR: No JOIN support

// Non-aggregate projection not in GROUP BY
final result = await ditto.store.execute(
  'SELECT status, customerId, COUNT(*) FROM orders GROUP BY status',
);
// ERROR: customerId not in GROUP BY
```

**✅ DO (Query separately, join in app)**:
```dart
// ✅ GOOD: GROUP BY for analytics (single collection)
final result = await ditto.store.execute(
  '''SELECT status, COUNT(*) AS count, AVG(total) AS avg_total
     FROM orders GROUP BY status''',
);

// ✅ GOOD: Query collections separately, join in application
final ordersResult = await ditto.store.execute(
  'SELECT customerId, COUNT(*) AS count FROM orders GROUP BY customerId',
);
final customerIds = ordersResult.items.map((item) => item.value['customerId']).toList();

final customersResult = await ditto.store.execute(
  'SELECT _id, name FROM customers WHERE _id IN (:ids)',
  arguments: {'ids': customerIds},
);
// Join in app code
```

**❌ DON'T**:
```dart
// ❌ BAD: Attempting JOIN with GROUP BY
final result = await ditto.store.execute(
  '''SELECT o.customerId, c.name, COUNT(*) AS order_count
     FROM orders o JOIN customers c ON o.customerId = c._id
     GROUP BY o.customerId, c.name''',
);
// ERROR: No JOIN support
```

**Why**: Ditto has no `JOIN` support. `GROUP BY` operates on single collections only. For cross-collection aggregation, query separately and join in application code. Consider denormalizing related data instead.

**See Also**: `.claude/guides/best-practices/ditto.md (lines 695-724: GROUP BY)`, `.claude/guides/best-practices/ditto.md (lines 525-556: Denormalization for Performance)`

---

### 13. Large OFFSET Values (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Large `OFFSET` values degrade performance linearly—Ditto must skip all offset documents sequentially.

**Detection**:
```dart
// RED FLAG
final result = await ditto.store.execute(
  'SELECT * FROM orders LIMIT 20 OFFSET 10000',
);
// Must skip 10,000 documents - slow!
```

**✅ DO (Use OFFSET sparingly)**:
```dart
// ✅ GOOD: Small OFFSET for pagination
final result = await ditto.store.execute(
  'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 40',
);
// Returns orders 41-60 (reasonable offset)

// ✅ GOOD: Use WHERE for deep pagination
final result = await ditto.store.execute(
  '''SELECT * FROM orders
     WHERE createdAt < :cursor
     ORDER BY createdAt DESC LIMIT 20''',
  arguments: {'cursor': lastSeenTimestamp},
);
```

**❌ DON'T**:
```dart
// ❌ BAD: Large OFFSET (linear performance degradation)
final result = await ditto.store.execute(
  'SELECT * FROM products LIMIT 50 OFFSET 5000',
);

// ❌ BAD: LIMIT without ORDER BY (unpredictable results)
final result = await ditto.store.execute(
  'SELECT * FROM cars LIMIT 10',
);
// Different runs may return different sets
```

**Why**: `OFFSET` requires sequential skipping. For deep pagination, use cursor-based approaches (WHERE with timestamp/ID). Always combine `LIMIT` with `ORDER BY` for predictable results.

**See Also**: `.claude/guides/best-practices/ditto.md (lines 778-807: LIMIT and OFFSET)`

---

### 14. Expensive Operator Usage (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Using expensive operators (object introspection, complex patterns, type checking) without WHERE filters or choosing complex operators when simpler alternatives exist.

**Detection**:
```dart
// RED FLAGS
// Object introspection without filter
await ditto.store.execute(
  'SELECT * FROM products WHERE :key IN object_keys(metadata)',
  arguments: {'key': 'someKey'},
);

// Regex when LIKE works
await ditto.store.execute(
  'SELECT * FROM users WHERE regexp_like(email, \'^admin.*\')',
);

// Type checking on full collection
await ditto.store.execute(
  'SELECT * FROM documents WHERE type(field) = :expectedType',
  arguments: {'expectedType': 'string'},
);
```

**✅ DO (Filter first, use simpler operators)**:
```dart
// Filter first, then apply expensive operators
await ditto.store.execute(
  'SELECT * FROM products WHERE category = :cat AND :key IN object_keys(metadata)',
  arguments: {'cat': 'electronics', 'key': 'someKey'},
);

// Use simpler operators
await ditto.store.execute(
  'SELECT * FROM users WHERE email LIKE :pattern',
  arguments: {'pattern': 'admin%'},
);

// Date operators for temporal queries (SDK 4.11+)
await ditto.store.execute(
  'SELECT * FROM orders WHERE createdAt >= date_sub(clock(), :days, :unit)',
  arguments: {'days': 7, 'unit': 'day'},
);

// Conditional operators for null handling
await ditto.store.execute(
  'SELECT orderId, coalesce(discount, :default) AS finalDiscount FROM orders',
  arguments: {'default': 0.0},
);
```

**❌ DON'T**:
```dart
// Expensive operators on full collection
await ditto.store.execute(
  'SELECT * FROM documents WHERE object_length(metadata) > :threshold',
  arguments: {'threshold': 10},
);

// Complex regex for simple patterns
regexp_like(name, '^Apple.*') // Use LIKE 'Apple%' instead

// SIMILAR TO when LIKE suffices
field SIMILAR TO 'prefix%' // Use LIKE 'prefix%' instead
```

**Why**: Expensive operators (object_keys, object_values, SIMILAR TO, type checking) add significant overhead. Always filter with WHERE first to reduce working set. Use simpler operators (LIKE, starts_with) when they suffice.

**Performance Hierarchy** (fast → slow):
1. Index scans with simple comparisons
2. String prefix matching (LIKE 'prefix%', starts_with)
3. IN operator with small lists
4. Date operators (date_cast, date_add, etc.)
5. Conditional operators (coalesce, nvl, decode)
6. Type checking operators (is_number, is_string, type)
7. Object introspection (object_keys, object_values)
8. Advanced patterns (SIMILAR TO, regexp_like)

**See Also**: `.claude/guides/best-practices/ditto.md (lines 820-1625: DQL Operator Expressions)`

---

## Quick Reference Checklist

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
