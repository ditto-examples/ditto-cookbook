# Query and Sync Common Patterns

This reference contains HIGH priority patterns for Ditto query optimization, observer management, and subscription patterns. These patterns address common scenarios affecting 20-50% of users.

## Table of Contents

- [Pattern 4: Observer Selection (Non-Flutter)](#pattern-4-observer-selection-non-flutter)
- [Pattern 5: Heavy Processing in Observer Callbacks](#pattern-5-heavy-processing-in-observer-callbacks)
- [Pattern 6: Broad Subscriptions](#pattern-6-broad-subscriptions)
- [Pattern 7: Query Without Active Subscription](#pattern-7-query-without-active-subscription)
- [Pattern 8: Missing signalNext() Call (Non-Flutter)](#pattern-8-missing-signalnext-call-non-flutter)
- [Pattern 9: SELECT * Overuse](#pattern-9-select--overuse)
- [Pattern 10: DISTINCT with _id](#pattern-10-distinct-with-_id)
- [Pattern 12: GROUP BY Without JOIN Awareness](#pattern-12-group-by-without-join-awareness)

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
  'SELECT * FROM products'
  onChange: (result) {
    // No backpressure control - callbacks can accumulate
    updateUI(result.items);
  }
);
```

**✅ DO (Use registerObserverWithSignalNext)**:
```dart
// ✅ RECOMMENDED: Observer with backpressure control
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId'
  onChange: (result, signalNext) {
    // Extract data immediately (lightweight)
    final data = result.items.map((item) => item.value).toList();
    updateUI(data);

    // Call signalNext after render cycle completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  }
  arguments: {'deviceId': 'sensor_123'}
);

// Later: stop observing
observer.cancel();
```

**❌ DON'T (Use registerObserver only for trivial cases)**:
```dart
// ⚠️ OK for very simple cases only
final observer = ditto.store.registerObserver(
  'SELECT * FROM simple_config'
  onChange: (result) {
    // Only for low-frequency, simple updates
    displayConfig(result.items.first.value);
  }
);
```

**Why registerObserverWithSignalNext**:
- ✅ Explicit backpressure management
- ✅ Prevents callback queue buildup
- ✅ Better performance on high-frequency updates
- ✅ Predictable memory usage

- `../SKILL.md` Pattern 2: QueryResultItems Retention
- Pattern 8: Missing signalNext() Call
- 

---

### 5. Heavy Processing in Observer Callbacks (Priority: HIGH)

**Platform**: All platforms

**Problem**: Performing heavy computations, I/O operations, or long-running tasks in observer callbacks blocks the main thread and causes UI jank.

**Detection**:
```dart
// RED FLAGS
ditto.store.registerObserver(
  'SELECT * FROM orders'
  onChange: (result) {
    // Heavy processing in callback - blocks main thread
    for (final item in result.items) {
      final order = item.value;
      final processedData = expensiveComputation(order);  // ❌ CPU-bound work
      final savedPath = saveToFile(processedData);        // ❌ I/O operation
      updateDatabase(savedPath);                          // ❌ More I/O
    }
    setState(() => _orders = result.items);
  }
);
```

**✅ DO**:
```dart
// ✅ GOOD: Lightweight callback, offload heavy work
ditto.store.registerObserver(
  'SELECT * FROM orders'
  onChange: (result) {
    // Extract data immediately (lightweight)
    final orders = result.items.map((item) => item.value).toList();

    // Update UI immediately
    setState(() => _orders = orders);

    // Offload heavy processing to background
    compute(_processOrders, orders);  // Flutter isolate
  }
);

// Background processing in isolate
Future<void> _processOrders(List<Map<String, dynamic>> orders) async {
  for (final order in orders) {
    final processedData = expensiveComputation(order);
    await saveToFile(processedData);
  }
}
```

**❌ DON'T**:
```dart
// Synchronous file I/O in callback
ditto.store.registerObserver(
  'SELECT * FROM logs'
  onChange: (result) {
    final logFile = File('logs.txt');
    for (final item in result.items) {
      logFile.writeAsStringSync(item.value.toString(), mode: FileMode.append);  // ❌ Blocks
    }
  }
);

// Network calls in callback
ditto.store.registerObserver(
  'SELECT * FROM sync_queue'
  onChange: (result) async {
    for (final item in result.items) {
      await http.post('https://api.example.com/sync', body: item.value);  // ❌ Async I/O
    }
  }
);
```

**Why Lightweight Callbacks**:
- ✅ Maintains 60 FPS UI rendering
- ✅ Prevents ANR (Application Not Responding) on Android
- ✅ Better battery life
- ✅ Responsive user experience

**Acceptable Operations in Callbacks**:
- Data extraction (map, filter)
- State updates (setState, provider updates)
- Simple transformations (date formatting, string operations)

**Offload to Background**:
- Heavy computation (image processing, data analysis)
- File I/O (read/write large files)
- Network requests (API calls, uploads)
- Database operations (external DB writes)

- `../../performance-observability/SKILL.md` Pattern 3: Heavy Processing
- 

---

### 6. Broad Subscriptions (Priority: HIGH)

**Platform**: All platforms

**Problem**: Subscriptions without WHERE clauses sync ALL documents in a collection, wasting bandwidth, storage, and sync time.

**Detection**:
```dart
// RED FLAGS
// No WHERE clause - syncs entire collection
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders'
);
// If collection has 100,000 orders, all sync to device!

// Very broad WHERE clause
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status IS NOT NULL'
);
// Still syncs nearly all orders (most have status field)
```

**✅ DO**:
```dart
// ✅ GOOD: Specific WHERE clause
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE userId = :userId AND status = :status'
  arguments: {'userId': currentUserId, 'status': 'pending'}
);
// Only syncs user's pending orders

// ✅ GOOD: Date-based filtering
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM events WHERE timestamp >= :startDate'
  arguments: {
    'startDate': DateTime.now().subtract(Duration(days: 7)).toIso8601String()
  }
);
// Only syncs events from last 7 days

// ✅ GOOD: Geospatial filtering (if applicable)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM stores WHERE city = :city'
  arguments: {'city': 'San Francisco'}
);
```

**❌ DON'T**:
```dart
// Sync everything, filter client-side
final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
final userOrders = await ditto.store.execute(
  'SELECT * FROM orders WHERE userId = :userId'
  arguments: {'userId': currentUserId}
);
// Wastes bandwidth syncing all orders just to filter locally

// Multiple overlapping subscriptions
final sub1 = ditto.sync.registerSubscription('SELECT * FROM orders WHERE status = "pending"');
final sub2 = ditto.sync.registerSubscription('SELECT * FROM orders WHERE status = "processing"');
final sub3 = ditto.sync.registerSubscription('SELECT * FROM orders WHERE status = "completed"');
// Better: Single subscription with IN clause or combine conditions
```

**Why Narrow Subscriptions**:
- ✅ Reduces initial sync time
- ✅ Minimizes storage requirements
- ✅ Improves query performance (smaller dataset)
- ✅ Saves bandwidth (especially on mobile)

**Common Filtering Patterns**:

| Use Case | Filter Pattern |
|----------|----------------|
| **User-specific data** | `WHERE userId = :userId` |
| **Time-based data** | `WHERE timestamp >= :startDate` |
| **Status-based data** | `WHERE status IN (:status1, :status2)` |
| **Geospatial data** | `WHERE region = :region` |
| **Active/archived data** | `WHERE isArchived = false` |

- `../reference/query-optimization.md` Subscription Patterns
- `../../storage-lifecycle/SKILL.md` Pattern 2: EVICT Management
- 

---

### 7. Query Without Active Subscription (Priority: HIGH)

**Platform**: All platforms

**Problem**: Executing queries without active subscription only returns local data. If data hasn't synced yet, query returns incomplete results.

**Detection**:
```dart
// RED FLAGS
// Query without subscription - may return incomplete data
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE category = :category'
  arguments: {'category': 'electronics'}
);
// If products haven't synced, result is incomplete!

// Subscription created after query
final result = await ditto.store.execute('SELECT * FROM orders');
final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
// Query executed before subscription active - too late!
```

**✅ DO**:
```dart
// ✅ GOOD: Create subscription BEFORE query
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM products WHERE category = :category'
  arguments: {'category': 'electronics'}
);

// Wait for initial sync (optional)
await Future.delayed(Duration(seconds: 1));

// Now query will return complete data
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE category = :category'
  arguments: {'category': 'electronics'}
);

// ✅ BETTER: Use observer instead of one-time query
final observer = ditto.store.registerObserver(
  'SELECT * FROM products WHERE category = :category'
  arguments: {'category': 'electronics'}
  onChange: (result) {
    // Automatically updates when data syncs
    setState(() => _products = result.items.map((item) => item.value).toList());
  }
);
```

**❌ DON'T**:
```dart
// Query without ever creating subscription
Future<List<Map<String, dynamic>>> getOrders() async {
  final result = await ditto.store.execute('SELECT * FROM orders');
  return result.items.map((item) => item.value).toList();
}
// Only returns locally available orders - may be empty or incomplete

// Subscription with different query
final subscription = ditto.sync.registerSubscription('SELECT * FROM orders WHERE status = "pending"');
final result = await ditto.store.execute('SELECT * FROM orders WHERE status = "completed"');
// Query for completed orders, but subscription only syncs pending orders!
```

**Why Subscription Before Query**:
- ✅ Ensures data is syncing
- ✅ Query returns complete dataset
- ✅ Automatic updates when new data arrives
- ✅ Consistent behavior across devices

**Best Practice Pattern**:
```dart
class OrdersService {
  DittoSyncSubscription? _subscription;
  DittoStoreObserver? _observer;

  void initialize() {
    // 1. Create subscription first
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE userId = :userId'
      arguments: {'userId': currentUserId}
    );

    // 2. Set up observer for live updates
    _observer = ditto.store.registerObserver(
      'SELECT * FROM orders WHERE userId = :userId'
      arguments: {'userId': currentUserId}
      onChange: (result) {
        // Data automatically updates as it syncs
        _ordersController.add(result.items.map((item) => item.value).toList());
      }
    );
  }

  void dispose() {
    _subscription?.cancel();
    _observer?.cancel();
  }
}
```

- `../SKILL.md` Pattern 3: Subscription Lifecycle Management
- 

---

### 8. Missing signalNext() Call (Priority: HIGH - Non-Flutter SDKs Only)

**Platform**: Swift, JavaScript, Kotlin (NOT applicable to Flutter SDK v4.x)

**⚠️ Flutter SDK Exception:**
Flutter SDK v4.14.0 and earlier do not require `signalNext()` calls. This pattern only applies to non-Flutter SDKs.

**Problem**: Not calling `signalNext()` in `registerObserverWithSignalNext` blocks further observer updates, causing backpressure buildup and memory issues.

**Detection**:
```dart
// RED FLAGS (Non-Flutter SDKs)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data'
  onChange: (result, signalNext) {
    updateUI(result.items);
    // Missing signalNext() - blocks further updates!
  }
);
```

**✅ DO**:
```dart
// ✅ GOOD: Call signalNext after UI update
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId'
  onChange: (result, signalNext) {
    // Extract data
    final data = result.items.map((item) => item.value).toList();
    updateUI(data);

    // Signal after UI renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  }
  arguments: {'deviceId': 'sensor_123'}
);
```

**❌ DON'T**:
```dart
// Never call signalNext
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM logs'
  onChange: (result, signalNext) {
    processLogs(result.items);
    // Missing signalNext() - observer stops receiving updates!
  }
);

// Call signalNext before heavy processing
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders'
  onChange: (result, signalNext) {
    signalNext();  // ❌ Too early - processing not done
    heavyProcessing(result.items);  // May cause callback queue buildup
  }
);
```

**Why signalNext() Matters**:
- ✅ Controls backpressure in observer pipeline
- ✅ Prevents memory buildup from queued updates
- ✅ Ensures predictable performance
- ❌ Without it: Updates queue indefinitely, causing OOM

**Timing Best Practices**:

| Timing | Use Case | Code Example |
|--------|----------|--------------|
| **After UI render** (Recommended) | Most UI updates | `WidgetsBinding.instance.addPostFrameCallback((_) => signalNext())` |
| **Immediate** (Use with caution) | Trivial callbacks | `signalNext()` at end of callback |
| **Debounced** (Advanced) | High-frequency updates | `Timer(Duration(milliseconds: 16), signalNext)` |

- `../../performance-observability/SKILL.md` Pattern 2: signalNext() Timing
- Pattern 4: Observer Selection
- 

---

### 9. SELECT * Overuse (Priority: HIGH)

**Platform**: All platforms

**Problem**: Using `SELECT *` retrieves all fields even when only a few are needed, wasting memory and processing time.

**Detection**:
```dart
// RED FLAGS
// Fetching all fields when only need name and price
final result = await ditto.store.execute('SELECT * FROM products');
for (final item in result.items) {
  final product = item.value;
  displayProduct(product['name'], product['price']);
  // Fetched 20 fields but only use 2!
}
```

**✅ DO**:
```dart
// ✅ GOOD: Select only needed fields
final result = await ditto.store.execute(
  'SELECT name, price FROM products WHERE category = :category'
  arguments: {'category': 'electronics'}
);
// Only retrieves 2 fields instead of all 20

// ✅ GOOD: Select specific nested fields
final result = await ditto.store.execute(
  'SELECT _id, user.name, user.email FROM orders'
);
// Only retrieves user name and email, not entire user object
```

**❌ DON'T**:
```dart
// Fetch everything, use subset
final result = await ditto.store.execute('SELECT * FROM orders');
final orderIds = result.items.map((item) => item.value['_id']).toList();
// Fetched entire order documents just to get IDs

// SELECT * in list views
final result = await ditto.store.execute('SELECT * FROM products');
ListView.builder(
  itemCount: result.items.length
  itemBuilder: (context, index) {
    final product = result.items[index].value;
    return ListTile(title: Text(product['name']));  // Only displays name!
  }
);
```

**Why Specific Fields**:
- ✅ Reduces memory usage
- ✅ Faster query execution
- ✅ Smaller result set to process
- ✅ Better performance on large documents

**When SELECT * is OK**:
- Document has few fields (< 5)
- All fields are actually used
- Full document is displayed/processed

**Optimization Examples**:

| Use Case | Bad Query | Good Query |
|----------|-----------|------------|
| **List view** | `SELECT * FROM products` | `SELECT _id, name, price FROM products` |
| **ID lookup** | `SELECT * FROM orders WHERE userId = :id` | `SELECT _id FROM orders WHERE userId = :id` |
| **Aggregation** | `SELECT * FROM logs WHERE timestamp > :date` | `SELECT timestamp, level FROM logs WHERE timestamp > :date` |

- `../reference/query-optimization.md` Field Selection
- `../../data-modeling/SKILL.md` Document Size Management

---

### 10. DISTINCT with _id (Priority: HIGH)

**Platform**: All platforms

**Problem**: Using `DISTINCT` with `_id` field is redundant because `_id` is already unique. This adds unnecessary memory overhead.

**Detection**:
```dart
// RED FLAGS
// DISTINCT on _id (redundant)
final result = await ditto.store.execute('SELECT DISTINCT _id FROM orders');
// _id is already unique - DISTINCT does nothing but waste memory

// DISTINCT when result is already unique
final result = await ditto.store.execute(
  'SELECT DISTINCT _id, customerId FROM orders WHERE _id = :id'
  arguments: {'id': orderId}
);
// WHERE _id = :id returns at most 1 document - DISTINCT is pointless
```

**✅ DO**:
```dart
// ✅ GOOD: No DISTINCT for _id
final result = await ditto.store.execute('SELECT _id FROM orders');
// _id is unique by definition

// ✅ GOOD: DISTINCT on non-unique fields
final result = await ditto.store.execute('SELECT DISTINCT category FROM products');
// category can have duplicates - DISTINCT is useful

// ✅ GOOD: DISTINCT with LIMIT to reduce memory
final result = await ditto.store.execute(
  'SELECT DISTINCT customerId FROM orders WHERE status = :status LIMIT 100'
  arguments: {'status': 'active'}
);
// Limits memory impact of DISTINCT operation
```

**❌ DON'T**:
```dart
// DISTINCT on primary key
final result = await ditto.store.execute('SELECT DISTINCT _id, name FROM products');
// _id guarantees uniqueness - DISTINCT has no effect

// DISTINCT without LIMIT on large result set
final result = await ditto.store.execute('SELECT DISTINCT customerId FROM orders');
// If orders collection has millions of records, DISTINCT uses lots of memory
```

**Why Avoid DISTINCT with _id**:
- ❌ _id is already unique (guaranteed by Ditto)
- ❌ DISTINCT adds memory overhead (hash table)
- ❌ Slower query execution
- ❌ No benefit in result set

**When DISTINCT is Useful**:
- Non-unique fields (status, category, tags)
- Combined with LIMIT to cap memory usage
- Small result sets (< 1000 unique values)

**Memory Impact of DISTINCT**:

| Result Set Size | DISTINCT Overhead |
|----------------|-------------------|
| < 1,000 unique values | ✅ Negligible |
| 1,000 - 10,000 | ⚠️ Moderate (monitor) |
| > 10,000 | ❌ High (avoid if possible) |

- `../../performance-observability/reference/optimization-patterns.md` Pattern 8: DISTINCT Memory Impact
- `../reference/query-optimization.md` DISTINCT Guidelines

---

### 12. GROUP BY Without JOIN Awareness (Priority: HIGH)

**Platform**: All platforms

**Problem**: Ditto does not support JOIN operations. Using `GROUP BY` without understanding this limitation leads to incorrect data modeling or query patterns.

**Detection**:
```dart
// RED FLAGS
// Attempting to JOIN (not supported)
final result = await ditto.store.execute(
  '''
  SELECT orders._id, customers.name
  FROM orders
  JOIN customers ON orders.customerId = customers._id
  '''
);
// Syntax error - Ditto does not support JOIN

// GROUP BY expecting normalized data
final result = await ditto.store.execute(
  'SELECT customerId, COUNT(*) FROM orders GROUP BY customerId'
);
// Works, but requires multiple queries to get customer details
```

**✅ DO**:
```dart
// ✅ GOOD: Embed related data (denormalization)
// Document structure
{
  '_id': 'order_123'
  'customerId': 'cust_456'
  'customerName': 'Alice',           // Embedded for query convenience
  'customerEmail': 'alice@example.com'
  'items': {...}
  'total': 125.00
}

// GROUP BY with embedded data
final result = await ditto.store.execute(
  'SELECT customerName, COUNT(*) as orderCount FROM orders GROUP BY customerName'
);
// Returns customer name directly, no second query needed

// ✅ GOOD: Multiple queries (when denormalization not suitable)
// Query 1: Aggregate orders
final orderCounts = await ditto.store.execute(
  'SELECT customerId, COUNT(*) as count FROM orders GROUP BY customerId'
);

// Query 2: Fetch customer details
final customerIds = orderCounts.items.map((item) => item.value['customerId']).toList();
final customers = await ditto.store.execute(
  'SELECT * FROM customers WHERE _id IN (:ids)'
  arguments: {'ids': customerIds}
);

// Combine client-side
final combined = orderCounts.items.map((item) {
  final customerId = item.value['customerId'];
  final customer = customers.items.firstWhere((c) => c.value['_id'] == customerId);
  return {
    'customerId': customerId
    'customerName': customer.value['name']
    'orderCount': item.value['count']
  };
}).toList();
```

**❌ DON'T**:
```dart
// Assume JOIN support
final result = await ditto.store.execute(
  '''
  SELECT o.*, c.name
  FROM orders o
  LEFT JOIN customers c ON o.customerId = c._id
  '''
);
// Fails - JOIN not supported

// Normalize data expecting JOIN
// orders collection
{'_id': 'order_123', 'customerId': 'cust_456'}

// customers collection
{'_id': 'cust_456', 'name': 'Alice'}

// Query orders with customer name - requires 2 queries
// Denormalization would be better for this access pattern
```

**Why No JOIN**:
- Ditto's CRDT architecture optimizes for offline-first, not relational joins
- Embedded data (denormalization) is preferred pattern
- Multiple sequential queries are acceptable alternative

**Data Modeling Strategies**:

| Access Pattern | Strategy | Trade-off |
|----------------|----------|-----------|
| **Always display together** | Embed data | ✅ Single query, ⚠️ Data duplication |
| **Independent access** | Separate collections | ⚠️ Multiple queries, ✅ No duplication |
| **Large related data** | Separate + reference | ✅ Efficient storage, ⚠️ Sequential queries |

- `../../data-modeling/SKILL.md` Pattern 2: Denormalization
- `../../data-modeling/reference/common-patterns.md` Pattern 3: Document Size and Relationship Modeling
- `../reference/query-optimization.md` JOIN Alternatives

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **advanced-patterns.md**: MEDIUM/LOW priority patterns (Tier 3)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
- **Related Skills**:
  - `data-modeling/SKILL.md`: Document design for query performance
  - `performance-observability/SKILL.md`: Observer and query optimization
