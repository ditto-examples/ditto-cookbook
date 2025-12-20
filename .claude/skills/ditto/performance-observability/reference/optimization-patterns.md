# Performance Optimization Patterns

This reference contains HIGH and MEDIUM priority patterns for Ditto performance optimization. These patterns address common performance issues and optimization techniques.

## Table of Contents

- [Pattern 1: Unnecessary Delta Creation](#pattern-1-unnecessary-delta-creation)
- [Pattern 2: DO UPDATE vs DO UPDATE_LOCAL_DIFF](#pattern-2-do-update-vs-do-update_local_diff)
- [Pattern 3: Log Level Configuration](#pattern-3-log-level-configuration)
- [Pattern 4: Broad Subscription Scope](#pattern-4-broad-subscription-scope)
- [Pattern 5: Observer Backpressure Buildup](#pattern-5-observer-backpressure-buildup)
- [Pattern 6: Partial UI Update Patterns (Flutter)](#pattern-6-partial-ui-update-patterns-flutter)
- [Pattern 7: Rotating Log File Configuration](#pattern-7-rotating-log-file-configuration)
- [Pattern 8: DISTINCT Memory Impact](#pattern-8-distinct-memory-impact)
- [Pattern 9: Large OFFSET Performance](#pattern-9-large-offset-performance)
- [Pattern 10: Operator Performance in Observers](#pattern-10-operator-performance-in-observers)

---

## Pattern 1: Unnecessary Delta Creation

**Priority**: HIGH

**Problem**: Updating a field with the same value still creates and syncs a delta to all peers, wasting bandwidth and processing.

**Detection**:
```dart
// Unnecessary update (value unchanged)
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :id'
  arguments: {'id': orderId, 'status': 'pending'}
);
// If status was already 'pending', this still syncs a delta!
```

### Solution: Check Before Updating

```dart
// ✅ GOOD: Check if value changed
final currentDoc = await ditto.store.execute(
  'SELECT status FROM orders WHERE _id = :id'
  arguments: {'id': orderId}
);

final currentStatus = currentDoc.items.first.value['status'];
final newStatus = 'completed';

if (currentStatus != newStatus) {
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :id'
    arguments: {'id': orderId, 'status': newStatus}
  );
}
```

### Why This Matters

Every UPDATE operation increments CRDT counters, even if the value doesn't change. This generates deltas that sync across all peers.

### Benefits

- ✅ Reduces unnecessary network traffic
- ✅ Minimizes delta generation and storage
- ✅ Improves battery life on mobile devices
- ✅ Reduces server-side processing overhead

- `../SKILL.md` Pattern 4: Unnecessary Delta Creation
- `../../data-modeling/reference/common-patterns.md` Field-Level Updates

---

## Pattern 2: DO UPDATE vs DO UPDATE_LOCAL_DIFF

**Priority**: HIGH (SDK 4.12+)

**Problem**: `DO UPDATE` syncs ALL fields as deltas, even unchanged ones. `DO UPDATE_LOCAL_DIFF` only syncs fields that actually changed.

**Detection**:
```dart
// ❌ BAD: DO UPDATE syncs all fields
await ditto.store.execute(
  '''
  INSERT INTO orders DOCUMENTS (:order)
  ON ID CONFLICT DO UPDATE
  '''
  arguments: {
    'order': {
      '_id': 'order_123'
      'status': 'completed',        // Changed
      'customerId': 'cust_456',     // Unchanged - but still syncs!
      'items': {...},               // Unchanged - but still syncs!
    }
  }
);
```

### Solution: Use DO UPDATE_LOCAL_DIFF

```dart
// ✅ GOOD: DO UPDATE_LOCAL_DIFF only syncs changed fields (SDK 4.12+)
await ditto.store.execute(
  '''
  INSERT INTO orders DOCUMENTS (:order)
  ON ID CONFLICT DO UPDATE_LOCAL_DIFF
  '''
  arguments: {
    'order': {
      '_id': 'order_123'
      'status': 'completed',        // Changed - will sync
      'customerId': 'cust_456',     // Unchanged - won't sync
      'items': {...},               // Unchanged - won't sync
    }
  }
);
```

### Why UPDATE_LOCAL_DIFF?

- ✅ Automatically compares values before creating deltas
- ✅ Only syncs fields that actually changed
- ✅ Ideal for upsert operations with many unchanged fields
- ✅ Reduces bandwidth and delta storage

**When to Use**:
- Upsert operations where most fields don't change
- Periodic background sync of large documents
- State reconciliation from external sources

- `../../data-modeling/reference/common-patterns.md` Pattern 1: Field-Level Updates

---

## Pattern 3: Log Level Configuration

**Priority**: HIGH

**Problem**: Setting log level after `Ditto()` initialization misses critical startup diagnostics.

**Detection**:
```dart
// ❌ BAD: Log level set after init
final ditto = await Ditto.open(store);
await ditto.startSync();
DittoLogger.minimumLogLevel = DittoLogLevel.debug;  // Too late!
```

### Solution: Set Log Level Before Init

```dart
// ✅ GOOD: Log level before init
DittoLogger.minimumLogLevel = DittoLogLevel.debug;  // First!
final ditto = await Ditto.open(store);
await ditto.startSync();
```

### Why This Matters

Ditto performs initialization work (auth, transport setup, mesh discovery) before `Ditto.open()` returns. Setting log level after init misses these critical logs.

### Recommended Log Levels

**Development**:
- `DittoLogLevel.debug` - Full diagnostics

**Staging**:
- `DittoLogLevel.info` - Key operations only

**Production**:
- `DittoLogLevel.warning` - Errors and warnings only

- `../SKILL.md` Pattern 6: Log Level Configuration
- Pattern 7: Rotating Log File Configuration

---

## Pattern 4: Broad Subscription Scope

**Priority**: MEDIUM

**Problem**: Subscriptions without WHERE clauses sync ALL documents in a collection, wasting bandwidth and storage.

**Detection**:
```dart
// ❌ BAD: No WHERE clause (syncs all orders)
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders'
);
```

### Solution: Use Specific WHERE Clauses

```dart
// ✅ GOOD: Specific WHERE clause
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE status = :status'
  arguments: {'status': 'pending'}
);
```

### Why Narrow Subscriptions?

- ✅ Reduces initial sync time
- ✅ Minimizes storage requirements
- ✅ Improves query performance (smaller working set)
- ✅ Reduces ongoing sync traffic

### Common Patterns

**User-Specific Data**:
```dart
'SELECT * FROM orders WHERE userId = :userId'
```

**Date-Based Data**:
```dart
'SELECT * FROM events WHERE timestamp >= :startDate'
```

**Status-Based Data**:
```dart
'SELECT * FROM tasks WHERE completed = false'
```

- `../../query-sync/SKILL.md` Pattern 5: Broad Subscriptions
- `../../query-sync/reference/query-optimization.md`

---

## Pattern 5: Observer Backpressure Buildup

**Priority**: MEDIUM (Non-Flutter SDKs)

**Problem**: Not calling `signalNext()` blocks observer updates, causing backpressure buildup and memory issues.

**Detection**:
```dart
// ❌ BAD: Missing signalNext()
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders'
  (result, signalNext) {
    updateUI(result);
    // Missing signalNext() - blocks further updates!
  }
);
```

### Solution: Always Call signalNext()

```dart
// ✅ GOOD: signalNext() after render
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders'
  (result, signalNext) {
    updateUI(result);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();  // After frame rendered
    });
  }
);
```

### Why signalNext() is Critical

- Controls backpressure in observer pipeline
- Without it, Ditto queues updates in memory
- Can cause out-of-memory errors on high-frequency updates
- Flutter SDK v4.x doesn't have `signalNext` (automatic backpressure)

### Timing Best Practices

**After UI Render** (Recommended):
```dart
WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
```

**Immediate** (Use with caution):
```dart
signalNext();  // Can cause frame drops if updates are rapid
```

**Debounced** (Advanced):
```dart
Timer(Duration(milliseconds: 16), signalNext);  // ~60fps
```

- `../SKILL.md` Pattern 2: Missing signalNext() Call
- 

---

## Pattern 6: Partial UI Update Patterns (Flutter)

**Priority**: MEDIUM (Flutter-specific)

**Problem**: Full-screen `setState()` in observer callbacks causes unnecessary widget rebuilds.

**Detection**:
```dart
// ❌ BAD: Full-screen setState
class OrdersScreen extends StatefulWidget {
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  void _setupObserver() {
    _observer = ditto.store.registerObserver(
      'SELECT * FROM orders'
      onChange: (result) {
        setState(() {  // Rebuilds ENTIRE screen!
          _orders = result.items.map((item) => item.value).toList();
        });
      }
    );
  }
}
```

### Solution Options

#### Option 1: Targeted setState (Simple)

```dart
// ✅ BETTER: setState only in data-owning widget
class OrdersScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OrdersListWidget(),  // Only this rebuilds
        StaticHeader(),      // Not rebuilt
        StaticFooter(),      // Not rebuilt
      ]
    );
  }
}

class OrdersListWidget extends StatefulWidget {
  @override
  State<OrdersListWidget> createState() => _OrdersListWidgetState();
}

class _OrdersListWidgetState extends State<OrdersListWidget> {
  void _setupObserver() {
    _observer = ditto.store.registerObserver(
      'SELECT * FROM orders'
      onChange: (result) {
        setState(() {  // Only rebuilds OrdersListWidget
          _orders = result.items.map((item) => item.value).toList();
        });
      }
    );
  }
}
```

#### Option 2: State Management (Riverpod - Recommended)

```dart
// ✅ BEST: Riverpod for granular updates
final ordersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final controller = StreamController<List<Map<String, dynamic>>>();

  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders'
    onChange: (result) {
      final orders = result.items.map((item) => item.value).toList();
      controller.add(orders);
    }
  );

  ref.onDispose(() {
    observer.cancel();
    controller.close();
  });

  return controller.stream;
});

// In widget - only OrdersList rebuilds when data changes
class OrdersScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return Column(
      children: [
        ordersAsync.when(
          data: (orders) => OrdersList(orders: orders)
          loading: () => CircularProgressIndicator()
          error: (err, stack) => Text('Error: $err')
        )
        StaticHeader(),   // Never rebuilds
        StaticFooter(),   // Never rebuilds
      ]
    );
  }
}
```

### Benefits of Targeted Updates

- ✅ Reduces unnecessary widget rebuilds
- ✅ Improves frame rate and responsiveness
- ✅ Better battery life
- ✅ Cleaner separation of concerns

- `../SKILL.md` Pattern 1: Full Screen setState
- 

---

## Pattern 7: Rotating Log File Configuration

**Priority**: LOW

**Problem**: Default file logging can consume unlimited disk space over time.

### Solution: Configure Rotating Logs

```dart
// ✅ GOOD: Rotating log files (5 files × 5 MB each = 25 MB max)
DittoLogger.setLogFileURL('/path/to/logs/ditto.log');
DittoLogger.minimumLogLevel = DittoLogLevel.info;
```

### Configuration Options

**File Location**:
- iOS: `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first`
- Android: `context.filesDir`
- Desktop: User-specific app data directory

**Rotation Strategy**:
- Ditto automatically rotates logs
- Default: 5 files, 5 MB each
- Cannot be customized via public API

**Production Best Practices**:
- Use `DittoLogLevel.warning` or `info` in production
- Monitor disk usage with platform tools
- Implement external log aggregation for analytics

- Pattern 3: Log Level Configuration
- `.claude/guides/best-practices/ditto.md` Logging Best Practices

---

## Pattern 8: DISTINCT Memory Impact

**Priority**: HIGH

**Problem**: `DISTINCT` maintains in-memory hash table of unique values, causing memory issues on large result sets.

**Detection**:
```dart
// ⚠️ CAUTION: DISTINCT on large dataset
final result = await ditto.store.execute(
  'SELECT DISTINCT customerId FROM orders'
);
// Memory usage: O(unique customerIds)
```

### Solution: Use DISTINCT Sparingly

```dart
// ✅ BETTER: Limit DISTINCT scope
final result = await ditto.store.execute(
  '''
  SELECT DISTINCT customerId FROM orders
  WHERE createdAt >= :recentDate
  LIMIT 100
  '''
  arguments: {'recentDate': recentTimestamp}
);
```

### Memory Impact

| Result Set Size | DISTINCT Overhead |
|----------------|-------------------|
| < 1,000 unique values | ✅ Negligible |
| 1,000 - 10,000 | ⚠️ Moderate (monitor) |
| > 10,000 | ❌ High (avoid if possible) |

### Alternatives to DISTINCT

**Option 1: Client-Side Deduplication**:
```dart
final result = await ditto.store.execute('SELECT customerId FROM orders');
final uniqueIds = result.items.map((item) => item.value['customerId']).toSet();
```

**Option 2: Normalized Data Model**:
```dart
// Separate collection for unique customers
'SELECT * FROM customers'
```

- `../SKILL.md` Pattern 11: DISTINCT Memory Impact
- `../../query-sync/reference/query-optimization.md`

---

## Pattern 9: Large OFFSET Performance

**Priority**: MEDIUM

**Problem**: Large OFFSET values force Ditto to scan and discard many documents, causing performance degradation.

**Detection**:
```dart
// ❌ BAD: Large OFFSET (scans 10,000 documents)
final result = await ditto.store.execute(
  'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 10000'
);
```

### Solution: Cursor-Based Pagination

```dart
// ✅ GOOD: Cursor-based pagination
var lastTimestamp = DateTime.now().toIso8601String();

// First page
var result = await ditto.store.execute(
  '''
  SELECT * FROM orders
  WHERE createdAt < :cursor
  ORDER BY createdAt DESC
  LIMIT 20
  '''
  arguments: {'cursor': lastTimestamp}
);

// Next page (use last item's timestamp as cursor)
if (result.items.isNotEmpty) {
  lastTimestamp = result.items.last.value['createdAt'];
  result = await ditto.store.execute(
    '''
    SELECT * FROM orders
    WHERE createdAt < :cursor
    ORDER BY createdAt DESC
    LIMIT 20
    '''
    arguments: {'cursor': lastTimestamp}
  );
}
```

### Performance Comparison

| Pagination Method | Performance | Memory |
|-------------------|-------------|--------|
| OFFSET 10000 | ❌ Scans 10,000 rows | ❌ High |
| Cursor-based | ✅ Direct seek | ✅ Constant |

- `../SKILL.md` Pattern 13: Large OFFSET Performance
- `../../query-sync/reference/query-optimization.md` Pagination Patterns

---

## Pattern 10: Operator Performance in Observers

**Priority**: MEDIUM

**Problem**: Complex DQL operators in observer queries can cause performance issues on frequent updates.

### Expensive Operators

**Type Checking** (SDK 4.x+):
```dart
// ⚠️ EXPENSIVE: Type checking on every update
'SELECT * FROM orders WHERE is_number(priority) AND priority > 5'
```

**String Operations**:
```dart
// ⚠️ EXPENSIVE: LIKE with leading wildcard
'SELECT * FROM users WHERE email LIKE :pattern'  // '%@example.com'
```

**JSON Path Traversal**:
```dart
// ⚠️ EXPENSIVE: Deep nested access
'SELECT * FROM orders WHERE items.product_123.options.color = :color'
```

### Optimization Strategies

**Option 1: Pre-validate Data**:
```dart
// ✅ Validate at insert time, remove type checks from queries
if (orderData['priority'] is! int) {
  throw ArgumentError('priority must be integer');
}
```

**Option 2: Denormalize for Query Performance**:
```dart
// ✅ Store commonly queried fields at top level
{
  "_id": "order_123"
  "email": "user@example.com",           // Top-level (fast)
  "emailDomain": "example.com",          // Pre-computed (fast)
  "customerDetails": {                    // Nested (slow to query)
    "email": "user@example.com"
  }
}
```

**Option 3: Index Design** (Future SDK feature):
- Currently Ditto doesn't support custom indexes
- Design schema to optimize common query patterns

- `../SKILL.md` Pattern 14: Operator Performance
- `../../data-modeling/SKILL.md` Pattern 2: Denormalization
- `../../query-sync/reference/query-optimization.md`

---

## Further Reading

- **SKILL.md**: Critical patterns (Tier 1)
- **Main Guide**: `.claude/guides/best-practices/ditto.md`
- **Related Skills**:
  - `query-sync/SKILL.md`: Query optimization, subscription scope
  - `data-modeling/SKILL.md`: Denormalization for query performance
