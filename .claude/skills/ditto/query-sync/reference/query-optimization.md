# DQL Query Optimization Guide

This guide covers performance optimization techniques for Ditto Query Language (DQL) queries.

---

## Overview

DQL queries can range from milliseconds to seconds depending on:
- **Dataset size**: Number of documents in collection
- **Query complexity**: WHERE clauses, aggregations, sorting
- **Index usage**: Whether Ditto can use indexes efficiently
- **Data extraction**: How QueryResultItems are processed

---

## Query Performance Principles

### 1. Use WHERE Clauses

**Bad Performance**:
```dart
// Fetches ALL documents, filters in application
final result = await ditto.store.execute('SELECT * FROM products');
final activeProducts = result.items
  .map((item) => item.value)
  .where((p) => p['isActive'] == true)
  .toList();
```

**Good Performance**:
```dart
// Filters in database, only fetches matching documents
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE isActive = true'
);
final activeProducts = result.items.map((item) => item.value).toList();
```

**Why**: Database filtering is orders of magnitude faster than application filtering.

---

### 2. Select Only Needed Fields

**Bad Performance**:
```dart
// Fetches all fields, only uses name
final result = await ditto.store.execute('SELECT * FROM products');
final names = result.items.map((item) => item.value['name']).toList();
```

**Good Performance**:
```dart
// Only fetches name field
final result = await ditto.store.execute('SELECT name FROM products');
final names = result.items.map((item) => item.value['name']).toList();
```

**Why**: Reduces data transfer and memory usage, especially with large documents.

---

### 3. Use Parameterized Queries

**Bad Performance (and UNSAFE)**:
```dart
// Query must be re-parsed on every execution
final status = 'active';
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = "$status"' // SQL injection risk!
);
```

**Good Performance (and SAFE)**:
```dart
// Query plan cached, parameters substituted efficiently
final result = await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'active'},
);
```

**Why**: Parameterized queries are cached and reused, avoiding re-parsing.

---

### 4. Extract Data Immediately

**Bad Performance**:
```dart
// Holds QueryResultItems for entire processing duration
final result = await ditto.store.execute('SELECT * FROM orders');

for (final item in result.items) {
  await processOrder(item.value); // Slow async processing
}
```

**Good Performance**:
```dart
// Extract data first, release QueryResultItems
final result = await ditto.store.execute('SELECT * FROM orders');
final orders = result.items.map((item) => item.value).toList();
// QueryResultItems released here

for (final order in orders) {
  await processOrder(order); // Process plain data
}
```

**Why**: QueryResultItems hold database cursors, releasing them frees resources.

---

## Index Strategies

### Ditto's Automatic Indexing

Ditto automatically creates indexes for:
- `_id` field (always indexed)
- Fields used in `WHERE` clauses (over time, based on query patterns)

**Note**: Explicit index creation is not currently supported. Ditto's query optimizer learns from usage.

### Write Queries to Leverage Indexing

**Good for Indexing**:
```dart
// Simple equality on single field - easily indexed
await ditto.store.execute(
  'SELECT * FROM orders WHERE status = :status',
  arguments: {'status': 'pending'},
);
```

**Less Optimal for Indexing**:
```dart
// Complex expressions harder to index
await ditto.store.execute(
  'SELECT * FROM orders WHERE totalAmount * 1.1 > :threshold',
  arguments: {'threshold': 100},
);
```

**Better**:
```dart
// Pre-calculate field values, index directly
await ditto.store.execute(
  '''
  UPDATE orders
  SET totalWithTax = totalAmount * 1.1
  WHERE _id = :id
  ''',
  arguments: {'id': orderId},
);

// Now query indexed field
await ditto.store.execute(
  'SELECT * FROM orders WHERE totalWithTax > :threshold',
  arguments: {'threshold': 100},
);
```

---

## Aggregation Optimization

### Use Aggregation Functions in Query

**Bad Performance**:
```dart
// Fetches all documents, calculates in application
final result = await ditto.store.execute('SELECT * FROM orders');
final total = result.items
  .map((item) => item.value['totalAmount'] as num)
  .fold(0.0, (sum, amount) => sum + amount.toDouble());
```

**Good Performance**:
```dart
// Calculates in database
final result = await ditto.store.execute(
  'SELECT SUM(totalAmount) as total FROM orders'
);

final total = result.items.isNotEmpty
  ? (result.items.first.value['total'] as num?)?.toDouble() ?? 0.0
  : 0.0;
```

**Available Aggregation Functions**:
- `COUNT(*)`: Count documents
- `SUM(field)`: Sum numeric field
- `AVG(field)`: Average numeric field
- `MIN(field)`: Minimum value
- `MAX(field)`: Maximum value

---

## Pagination Patterns

### Efficient Pagination with LIMIT/OFFSET

**Pattern 1: Basic Pagination**:
```dart
Future<List<Map<String, dynamic>>> getProductsPage(
  Ditto ditto,
  int page,
  int pageSize,
) async {
  final offset = page * pageSize;

  final result = await ditto.store.execute(
    '''
    SELECT * FROM products
    WHERE isActive = true
    ORDER BY name
    LIMIT :limit OFFSET :offset
    ''',
    arguments: {
      'limit': pageSize,
      'offset': offset,
    },
  );

  return result.items.map((item) => item.value).toList();
}
```

**Pattern 2: Cursor-Based Pagination (More Efficient)**:
```dart
// First page
Future<List<Map<String, dynamic>>> getFirstPage(
  Ditto ditto,
  int pageSize,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM products
    WHERE isActive = true
    ORDER BY _id
    LIMIT :limit
    ''',
    arguments: {'limit': pageSize},
  );

  return result.items.map((item) => item.value).toList();
}

// Subsequent pages
Future<List<Map<String, dynamic>>> getNextPage(
  Ditto ditto,
  String lastId,
  int pageSize,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM products
    WHERE isActive = true AND _id > :lastId
    ORDER BY _id
    LIMIT :limit
    ''',
    arguments: {
      'lastId': lastId,
      'limit': pageSize,
    },
  );

  return result.items.map((item) => item.value).toList();
}
```

**Why Cursor-Based is Better**:
- No OFFSET calculation needed
- Consistent performance regardless of page number
- Works better with real-time data changes

---

## Subscription Optimization

### 1. Narrow Subscription Scope

**Bad Performance**:
```dart
// Subscribes to ALL products, wastes bandwidth
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM products'
);
```

**Good Performance**:
```dart
// Only subscribes to active products
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM products WHERE isActive = true'
);
```

### 2. Use Field Selection in Subscriptions

**Bad Performance**:
```dart
// Syncs entire documents, including large description field
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM products WHERE isActive = true'
);
```

**Good Performance**:
```dart
// Only syncs essential fields
final subscription = ditto.sync.registerSubscription(
  'SELECT _id, name, price, imageUrl FROM products WHERE isActive = true'
);
```

### 3. Cancel Unused Subscriptions

**Bad Performance**:
```dart
// Old subscription continues syncing
class FilterableProducts {
  Subscription? _subscription;

  void setCategory(String category) {
    // Creates new subscription without canceling old one!
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM products WHERE category = :category',
      arguments: {'category': category},
    );
  }
}
```

**Good Performance**:
```dart
// Cancel old subscription before creating new one
class FilterableProducts {
  Subscription? _subscription;

  void setCategory(String category) {
    // Cancel old subscription first
    _subscription?.cancel();

    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM products WHERE category = :category',
      arguments: {'category': category},
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
```

---

## Observer Optimization

### 1. Lightweight Observer Callbacks

**Bad Performance**:
```dart
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM products',
  onChange: (result, signalNext) async {
    final products = result.items.map((item) => item.value).toList();

    // Heavy processing in callback - blocks observer!
    for (final product in products) {
      await heavyComputation(product);
      await saveToDatabase(product);
      await notifyExternalAPI(product);
    }

    signalNext();
  },
);
```

**Good Performance**:
```dart
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM products',
  onChange: (result, signalNext) {
    final products = result.items.map((item) => item.value).toList();

    // Lightweight: Just extract and signal
    _updateProductCache(products);

    // Heavy processing offloaded to separate async task
    _processProductsAsync(products);

    signalNext(); // Signal immediately
  },
);

void _updateProductCache(List<Map<String, dynamic>> products) {
  // Fast operation: update in-memory cache
  _cache = products;
}

Future<void> _processProductsAsync(List<Map<String, dynamic>> products) async {
  // Heavy processing outside observer callback
  for (final product in products) {
    await heavyComputation(product);
  }
}
```

### 2. Debounce Rapid Updates

**Bad Performance**:
```dart
// Processes every update, even if updates come faster than processing
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM realtimeData',
  onChange: (result, signalNext) async {
    final data = result.items.map((item) => item.value).toList();

    // Heavy processing on every callback
    await processData(data);

    signalNext();
  },
);
```

**Good Performance**:
```dart
// Debounce rapid updates
DateTime? _lastProcessed;
const _debounceDelay = Duration(milliseconds: 300);

final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM realtimeData',
  onChange: (result, signalNext) async {
    final now = DateTime.now();

    // Skip if too soon since last processing
    if (_lastProcessed != null &&
        now.difference(_lastProcessed!) < _debounceDelay) {
      signalNext(); // Signal without processing
      return;
    }

    final data = result.items.map((item) => item.value).toList();
    await processData(data);

    _lastProcessed = now;
    signalNext();
  },
);
```

### 3. Partial UI Updates

**Bad Performance**:
```dart
// Full widget rebuild on every change
class ProductsList extends StatefulWidget {
  // ...
}

class _ProductsListState extends State<ProductsList> {
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM products',
      onChange: (result, signalNext) {
        // Always triggers full rebuild
        setState(() {
          _products = result.items.map((item) => item.value).toList();
        });

        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  // ...
}
```

**Good Performance**:
```dart
// Only rebuild when data actually changes
class _ProductsListState extends State<ProductsList> {
  final Map<String, Map<String, dynamic>> _productsById = {};

  @override
  void initState() {
    super.initState();

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM products',
      onChange: (result, signalNext) {
        bool hasChanges = false;

        for (final item in result.items) {
          final product = item.value;
          final id = product['_id'] as String;

          if (!_productsById.containsKey(id) ||
              _hasProductChanged(_productsById[id]!, product)) {
            _productsById[id] = product;
            hasChanges = true;
          }
        }

        // Only rebuild if changes detected
        if (hasChanges) {
          setState(() {});
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  bool _hasProductChanged(Map<String, dynamic> old, Map<String, dynamic> new_) {
    return old['name'] != new_['name'] ||
           old['price'] != new_['price'] ||
           old['isActive'] != new_['isActive'];
  }

  // ...
}
```

---

## Query Pattern Anti-Patterns

### Anti-Pattern 1: N+1 Query Problem

**Bad Performance**:
```dart
// Fetches orders, then queries customer for each order
final ordersResult = await ditto.store.execute('SELECT * FROM orders');
final orders = ordersResult.items.map((item) => item.value).toList();

for (final order in orders) {
  // N queries for N orders!
  final customerResult = await ditto.store.execute(
    'SELECT * FROM customers WHERE _id = :id',
    arguments: {'id': order['customerId']},
  );

  final customer = customerResult.items.firstOrNull?.value;
  print('Order ${order['_id']} for ${customer?['name']}');
}
```

**Good Performance**:
```dart
// Denormalize: Embed customer data in order document
final ordersResult = await ditto.store.execute(
  'SELECT * FROM orders'
);

// Order documents include embedded customer data:
// {
//   "_id": "order_123",
//   "customerName": "John Doe",  // Denormalized
//   "customerEmail": "john@example.com",  // Denormalized
//   "totalAmount": 150.00
// }

final orders = ordersResult.items.map((item) => item.value).toList();

for (final order in orders) {
  print('Order ${order['_id']} for ${order['customerName']}');
}
```

**Why**: Ditto does not support JOINs. Denormalize data to avoid multiple queries.

### Anti-Pattern 2: Fetching Entire Collection for Existence Check

**Bad Performance**:
```dart
// Fetches all products just to check if any exist
final result = await ditto.store.execute(
  'SELECT * FROM products WHERE sku = :sku',
  arguments: {'sku': 'WIDGET-001'},
);

final exists = result.items.isNotEmpty;
```

**Good Performance**:
```dart
// Only fetch _id field, use LIMIT 1
final result = await ditto.store.execute(
  'SELECT _id FROM products WHERE sku = :sku LIMIT 1',
  arguments: {'sku': 'WIDGET-001'},
);

final exists = result.items.isNotEmpty;
```

**Even Better**:
```dart
// Use COUNT
final result = await ditto.store.execute(
  'SELECT COUNT(*) as count FROM products WHERE sku = :sku',
  arguments: {'sku': 'WIDGET-001'},
);

final count = result.items.isNotEmpty
  ? result.items.first.value['count'] as int
  : 0;

final exists = count > 0;
```

---

## Performance Monitoring

### Measure Query Execution Time

```dart
Future<void> measureQueryPerformance() async {
  final stopwatch = Stopwatch()..start();

  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE isActive = true'
  );

  stopwatch.stop();

  print('Query executed in ${stopwatch.elapsedMilliseconds}ms');
  print('Returned ${result.items.length} items');
}
```

### Identify Slow Queries

**Threshold-Based Logging**:
```dart
Future<QueryResult> executeWithLogging(
  Ditto ditto,
  String query, {
  Map<String, dynamic>? arguments,
}) async {
  final stopwatch = Stopwatch()..start();

  final result = await ditto.store.execute(query, arguments: arguments);

  stopwatch.stop();

  // Log slow queries (>100ms)
  if (stopwatch.elapsedMilliseconds > 100) {
    print('SLOW QUERY (${stopwatch.elapsedMilliseconds}ms): $query');
    print('Arguments: $arguments');
    print('Results: ${result.items.length} items');
  }

  return result;
}
```

---

## Optimization Checklist

- [ ] Use WHERE clauses to filter in database, not application
- [ ] Select only needed fields with `SELECT field1, field2` instead of `SELECT *`
- [ ] Use parameterized queries (`:param`) for caching and security
- [ ] Extract QueryResultItems immediately to release cursors
- [ ] Narrow subscription scope with specific WHERE clauses
- [ ] Cancel unused subscriptions to reduce bandwidth
- [ ] Keep observer callbacks lightweight
- [ ] Debounce rapid updates in high-frequency observers
- [ ] Use cursor-based pagination for large datasets
- [ ] Denormalize data to avoid N+1 query problems
- [ ] Use aggregation functions (COUNT, SUM, AVG) in database
- [ ] Monitor query performance and identify slow queries
- [ ] Test queries with realistic dataset sizes

---

## Additional Resources

- **DQL Syntax**: [Ditto DQL Documentation](https://docs.ditto.live/dql/)
- **Query Examples**: See `examples/` directory
- **Legacy API Migration**: `reference/legacy-api-migration.md`
- **Main Best Practices**: `.claude/guides/best-practices/ditto.md`
