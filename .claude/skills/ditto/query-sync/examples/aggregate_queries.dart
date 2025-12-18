// ✅ GOOD: Aggregate function patterns (COUNT, SUM, AVG, MIN, MAX, GROUP BY, HAVING)
// Demonstrates proper aggregate usage with WHERE filters and memory management

import 'package:ditto/ditto.dart';

// ===================================================================
// AGGREGATE FUNCTIONS: COUNT, SUM, AVG, MIN, MAX
// ===================================================================

/// ✅ GOOD: Filtered aggregate (reduces memory buffer)
Future<void> filteredAggregate(Ditto ditto) async {
  final cutoffDate = DateTime.now().subtract(Duration(days: 30)).toIso8601String();

  final result = await ditto.store.execute(
    '''SELECT COUNT(*) AS active_orders, AVG(total) AS avg_total
       FROM orders
       WHERE status = :status AND createdAt >= :cutoff''',
    arguments: {
      'status': 'active',
      'cutoff': cutoffDate,
    },
  );

  final stats = result.items.first.value;
  print('Active orders: ${stats['active_orders']}');
  print('Average total: \$${stats['avg_total']}');
}

/// ❌ BAD: Unbounded aggregate (buffers all documents in memory)
Future<void> unboundedAggregateBad(Ditto ditto) async {
  // ❌ Problem: No WHERE filter - buffers ALL orders in memory
  // If you have 100,000+ orders, this can crash mobile devices
  final result = await ditto.store.execute(
    'SELECT COUNT(*) FROM orders',
  );

  final count = result.items.first.value['($1)']; // Default alias for unnamed aggregate
  print('Total orders: $count');
  // High memory usage, potential crashes
}

// ===================================================================
// MULTIPLE AGGREGATE FUNCTIONS
// ===================================================================

/// ✅ GOOD: Multiple aggregates in a single query
Future<void> multipleAggregates(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT
         COUNT(*) AS total_cars,
         AVG(price) AS avg_price,
         MIN(price) AS lowest_price,
         MAX(price) AS highest_price
       FROM cars
       WHERE year >= :year''',
    arguments: {'year': 2020},
  );

  final stats = result.items.first.value;
  print('Total cars: ${stats['total_cars']}');
  print('Average price: \$${stats['avg_price']}');
  print('Lowest price: \$${stats['lowest_price']}');
  print('Highest price: \$${stats['highest_price']}');
}

// ===================================================================
// COUNT VARIANTS
// ===================================================================

/// ✅ GOOD: COUNT(*) with filter
Future<int> countWithFilter(Ditto ditto, String status) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(*) AS count FROM orders WHERE status = :status',
    arguments: {'status': status},
  );

  return result.items.first.value['count'] as int;
}

/// ✅ GOOD: COUNT(field) - counts non-null values
Future<int> countNonNull(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(discount) AS discounted_count FROM products',
  );

  // Counts only products with non-null discount field
  return result.items.first.value['discounted_count'] as int;
}

/// ✅ GOOD: COUNT(DISTINCT field) - counts unique values
Future<int> countDistinct(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(DISTINCT category) AS category_count FROM products',
  );

  return result.items.first.value['category_count'] as int;
}

// ===================================================================
// EXISTENCE CHECKS: LIMIT 1 vs COUNT(*)
// ===================================================================

/// ✅ BEST: Use LIMIT 1 for existence checks (efficient)
Future<bool> checkExistenceWithLimit(Ditto ditto, String status) async {
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE status = :status LIMIT 1',
    arguments: {'status': status},
  );

  // Returns immediately after finding first match
  return result.items.isNotEmpty;
}

/// ❌ BAD: COUNT(*) for existence check (inefficient)
Future<bool> checkExistenceWithCountBad(Ditto ditto, String status) async {
  // ❌ Problem: Buffers ALL matching documents just to check existence
  // If you have 10,000 active orders, all are buffered in memory
  final result = await ditto.store.execute(
    'SELECT COUNT(*) FROM orders WHERE status = :status',
    arguments: {'status': status},
  );

  final count = result.items.first.value['($1)'] as int;
  return count > 0;
  // Wasteful - could have returned after finding first match
}

// ===================================================================
// GROUP BY: Grouping and Aggregating
// ===================================================================

/// ✅ GOOD: GROUP BY to reduce result set size
Future<List<Map<String, dynamic>>> groupByStatus(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT status, COUNT(*) AS count, AVG(total) AS avg_total
       FROM orders
       GROUP BY status''',
  );

  // Returns one row per unique status (bounded result set)
  return result.items.map((item) => item.value).toList();
  // Example: [
  //   {'status': 'pending', 'count': 15, 'avg_total': 45.50},
  //   {'status': 'completed', 'count': 120, 'avg_total': 52.30},
  //   {'status': 'cancelled', 'count': 8, 'avg_total': 38.20}
  // ]
}

/// ✅ GOOD: Multiple GROUP BY expressions
Future<List<Map<String, dynamic>>> multipleGroupBy(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT color, make, COUNT(*) AS count
       FROM cars
       GROUP BY color, make
       ORDER BY count DESC''',
  );

  return result.items.map((item) => item.value).toList();
  // Example: [
  //   {'color': 'blue', 'make': 'Toyota', 'count': 25},
  //   {'color': 'red', 'make': 'Ford', 'count': 18},
  //   ...
  // ]
}

/// ❌ BAD: Non-aggregate projection without GROUP BY
Future<void> nonAggregateProjectionBad(Ditto ditto) async {
  // ❌ Problem: customerId is not aggregated and not in GROUP BY
  try {
    final result = await ditto.store.execute(
      'SELECT status, customerId, COUNT(*) FROM orders GROUP BY status',
    );
    // ERROR: customerId is not in GROUP BY clause
  } catch (e) {
    print('Error: $e');
    print('Solution: Either add customerId to GROUP BY or remove it from projections');
  }
}

// ===================================================================
// GROUP BY WITH NO JOIN SUPPORT
// ===================================================================

/// ❌ BAD: Attempting JOIN with GROUP BY (not supported)
Future<void> attemptJoinBad(Ditto ditto) async {
  // ❌ Problem: Ditto does not support JOIN operations
  try {
    final result = await ditto.store.execute(
      '''SELECT o.customerId, c.name, COUNT(*) AS order_count
         FROM orders o JOIN customers c ON o.customerId = c._id
         GROUP BY o.customerId, c.name''',
    );
    // ERROR: No JOIN support
  } catch (e) {
    print('Error: $e');
  }
}

/// ✅ GOOD: Query separately, join in application
Future<List<Map<String, dynamic>>> querySeparatelyAndJoin(Ditto ditto) async {
  // Step 1: Group orders by customerId
  final ordersResult = await ditto.store.execute(
    'SELECT customerId, COUNT(*) AS count FROM orders GROUP BY customerId',
  );

  final orderCounts = Map.fromEntries(
    ordersResult.items.map((item) {
      final data = item.value;
      return MapEntry(data['customerId'], data['count']);
    }),
  );

  // Step 2: Fetch customer names
  final customerIds = orderCounts.keys.toList();
  final customersResult = await ditto.store.execute(
    'SELECT _id, name FROM customers WHERE _id IN (:ids)',
    arguments: {'ids': customerIds},
  );

  // Step 3: Join in application code
  return customersResult.items.map((item) {
    final data = item.value;
    return {
      'customerId': data['_id'],
      'name': data['name'],
      'orderCount': orderCounts[data['_id']],
    };
  }).toList();
}

// ===================================================================
// HAVING: Filtering Grouped Results
// ===================================================================

/// ✅ GOOD: HAVING filters groups based on aggregate conditions
Future<List<Map<String, dynamic>>> havingFilter(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT color, COUNT(*) AS count
       FROM cars
       GROUP BY color
       HAVING COUNT(*) > 5''',
  );

  // Returns only colors with more than 5 cars
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Combine WHERE (pre-filter) and HAVING (post-filter)
Future<List<Map<String, dynamic>>> whereAndHaving(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT make, COUNT(*) AS count, AVG(price) AS avg_price
       FROM cars
       WHERE year >= :year
       GROUP BY make
       HAVING COUNT(*) >= 3 AND AVG(price) > 30000''',
    arguments: {'year': 2020},
  );

  // Pre-filter: Only cars from 2020 or newer
  // Post-filter: Only makes with 3+ cars and avg price > $30,000
  return result.items.map((item) => item.value).toList();
}

// ===================================================================
// AGGREGATES IN OBSERVERS (ANTI-PATTERN)
// ===================================================================

/// ❌ BAD: Unbounded aggregate in observer (memory buildup)
void unboundedAggregateInObserverBad(Ditto ditto) {
  // ❌ Problem: Buffers all orders on every update
  // High-frequency updates cause memory buildup
  final observer = ditto.store.registerObserver(
    'SELECT COUNT(*) AS total FROM orders', // No WHERE filter!
    onChange: (result) {
      final total = result.items.first.value['total'];
      print('Total orders: $total');
      // Memory impact: All orders buffered on each callback
    },
  );
}

/// ✅ GOOD: Filtered aggregate in observer
void filteredAggregateInObserver(Ditto ditto) {
  // ✅ Better: Filter to recent orders only
  final cutoffDate = DateTime.now().subtract(Duration(days: 7)).toIso8601String();

  final observer = ditto.store.registerObserver(
    '''SELECT COUNT(*) AS recent_orders
       FROM orders
       WHERE createdAt >= :cutoff''',
    onChange: (result) {
      final recentCount = result.items.first.value['recent_orders'];
      print('Recent orders (last 7 days): $recentCount');
      // Memory impact: Only recent orders buffered
    },
    arguments: {'cutoff': cutoffDate},
  );

  // Cancel when done
  // observer.cancel();
}

/// ✅ BEST: Use GROUP BY in observer to reduce result set
void groupByInObserver(Ditto ditto) {
  // ✅ Best: GROUP BY returns bounded result (one row per status)
  final observer = ditto.store.registerObserver(
    '''SELECT status, COUNT(*) AS count
       FROM orders
       WHERE createdAt >= :cutoff
       GROUP BY status''',
    onChange: (result) {
      final stats = result.items.map((item) => item.value).toList();
      print('Order stats by status: $stats');
      // Memory impact: Only a few rows (number of unique statuses)
    },
    arguments: {
      'cutoff': DateTime.now().subtract(Duration(days: 7)).toIso8601String(),
    },
  );

  // Cancel when done
  // observer.cancel();
}

// ===================================================================
// SUM AND AVG EXAMPLES
// ===================================================================

/// ✅ GOOD: SUM with filter
Future<double> calculateTotalRevenue(Ditto ditto, String dateFrom) async {
  final result = await ditto.store.execute(
    'SELECT SUM(total) AS revenue FROM orders WHERE status = :status AND createdAt >= :dateFrom',
    arguments: {'status': 'completed', 'dateFrom': dateFrom},
  );

  return result.items.first.value['revenue'] as double;
}

/// ✅ GOOD: AVG with filter
Future<double> calculateAverageOrderValue(Ditto ditto) async {
  final cutoffDate = DateTime.now().subtract(Duration(days: 30)).toIso8601String();

  final result = await ditto.store.execute(
    'SELECT AVG(total) AS avg_order_value FROM orders WHERE status = :status AND createdAt >= :cutoff',
    arguments: {'status': 'completed', 'cutoff': cutoffDate},
  );

  return result.items.first.value['avg_order_value'] as double;
}

/// ✅ GOOD: SUM(DISTINCT field) - sums unique values only
Future<double> sumDistinctPrices(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT SUM(DISTINCT price) AS unique_price_sum FROM products WHERE category = :category',
    arguments: {'category': 'electronics'},
  );

  return result.items.first.value['unique_price_sum'] as double;
}

// ===================================================================
// KEY TAKEAWAYS
// ===================================================================

/*
✅ DO:
- Filter with WHERE before aggregating (reduces memory buffer)
- Use GROUP BY to reduce result set size
- Use LIMIT 1 for existence checks (not COUNT(*))
- Combine WHERE (pre-filter) and HAVING (post-filter) for efficiency
- Query collections separately, join in app code (no JOIN support)

❌ DON'T:
- Use unbounded aggregates without WHERE filters
- Use COUNT(*) for existence checks (wasteful)
- Use aggregates in high-frequency observers without filters
- Attempt to use GROUP BY as a JOIN substitute
- Include non-aggregate projections not in GROUP BY clause

WHY:
- Aggregates buffer all matching documents in memory (non-streaming "dam")
- Unbounded aggregates can crash mobile devices (100k+ documents)
- LIMIT 1 returns immediately after finding first match (no buffering)
- Ditto has no JOIN support - query separately and join in app

MEMORY IMPACT:
- COUNT(*) on 100k orders: ~10-50MB buffered depending on document size
- LIMIT 1 existence check: Minimal memory, returns after first match
- GROUP BY: Result set bounded by unique group values (typically small)

SEE ALSO:
- .claude/guides/best-practices/ditto.md#aggregate-functions
- .claude/guides/best-practices/ditto.md#group-by
- .claude/guides/best-practices/ditto.md#having
*/
