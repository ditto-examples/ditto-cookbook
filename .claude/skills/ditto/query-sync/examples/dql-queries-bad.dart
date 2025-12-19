// SDK Version: 4.12+
// Platform: Flutter
// Last Updated: 2025-12-19
//
// Example: DQL Query Anti-Patterns
// This file demonstrates DEPRECATED and problematic query patterns to AVOID

import 'package:ditto/ditto.dart';

/// Anti-Pattern 1: NOT APPLICABLE TO FLUTTER
///
/// ❌ The legacy builder API (collection, find, exec) NEVER existed in Flutter SDK
/// This example is only relevant for JavaScript, Swift, and Kotlin platforms
///
/// For reference, here's what the legacy API looks like in non-Flutter platforms:
///
/// // JavaScript/Swift/Kotlin DEPRECATED (SDK 4.12+, removed in v5):
/// // const orders = await ditto.store
/// //   .collection('orders')
/// //   .find("status == 'active'")
/// //   .exec();
///
/// Flutter SDK has ALWAYS used the DQL string-based API:
Future<void> queryActiveOrders_Correct(Ditto ditto) async {
  // ✅ CORRECT: Use DQL string-based API (always been the Flutter way)
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'active'},
  );

  final orders = result.items.map((item) => item.value).toList();
}

/// Anti-Pattern 2: Query without parameterization (SQL injection risk)
///
/// ❌ BAD: String concatenation in queries
Future<void> queryUserByName_Unsafe(Ditto ditto, String userName) async {
  // DANGER: Potential injection vulnerability
  final result = await ditto.store.execute(
    'SELECT * FROM users WHERE name = "$userName"',
  );

  // If userName contains: " OR 1=1 --
  // This could expose all users!
}

/// ✅ GOOD: Use parameterized queries
Future<void> queryUserByName_Safe(Ditto ditto, String userName) async {
  final result = await ditto.store.execute(
    'SELECT * FROM users WHERE name = :name',
    arguments: {'name': userName},
  );

  final users = result.items.map((item) => item.value).toList();
}

/// Anti-Pattern 3: SELECT * when only few fields needed
///
/// ❌ BAD: Fetching unnecessary data
Future<void> getProductNames_Wasteful(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products', // Fetches all fields
  );

  // Only using name and price, but retrieved everything
  final names = result.items.map((item) {
    return item.value['name'];
  }).toList();
}

/// ✅ GOOD: Select only needed fields
Future<void> getProductNames_Efficient(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT name, price FROM products', // Only fetch what we need
  );

  final products = result.items.map((item) => item.value).toList();
}

/// Anti-Pattern 4: Broad query without WHERE clause
///
/// ❌ BAD: No filtering, wastes bandwidth and processing
Future<void> getAllProducts_Wasteful(Ditto ditto) async {
  // Fetches ALL products, even inactive/deleted ones
  final result = await ditto.store.execute(
    'SELECT * FROM products',
  );

  // Then filters in application code
  final activeProducts = result.items
      .map((item) => item.value)
      .where((product) => product['isActive'] == true)
      .toList();
}

/// ✅ GOOD: Filter in the query
Future<void> getActiveProducts_Efficient(Ditto ditto) async {
  // Only fetch active products
  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE isActive = true',
  );

  final activeProducts = result.items.map((item) => item.value).toList();
}

/// Anti-Pattern 5: Not handling empty results
///
/// ❌ BAD: Assumes results exist
Future<String> getFirstProductName_Unsafe(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT name FROM products LIMIT 1',
  );

  // CRASH RISK: What if no products exist?
  return result.items.first.value['name'] as String;
}

/// ✅ GOOD: Handle empty results
Future<String?> getFirstProductName_Safe(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT name FROM products LIMIT 1',
  );

  if (result.items.isEmpty) return null;

  return result.items.first.value['name'] as String?;
}

/// Anti-Pattern 6: Performing heavy processing on query results
///
/// ❌ BAD: Complex processing while holding QueryResultItems
Future<void> processProducts_Inefficient(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products',
  );

  // Heavy processing while holding QueryResultItems (inefficient)
  for (final item in result.items) {
    final product = item.value; // Still holding item reference

    // Expensive operations
    await performComplexCalculation(product);
    await saveToExternalSystem(product);
  }
}

/// ✅ GOOD: Extract data first, then process
Future<void> processProducts_Efficient(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products',
  );

  // Extract data immediately
  final products = result.items.map((item) => item.value).toList();
  // QueryResultItems are now released

  // Process extracted data
  for (final product in products) {
    await performComplexCalculation(product);
    await saveToExternalSystem(product);
  }
}

/// Anti-Pattern 7: Using wrong UPDATE syntax
///
/// ❌ BAD: Trying to use SET with nested syntax
Future<void> updateNestedField_Wrong(Ditto ditto, String orderId) async {
  // This syntax doesn't work as expected
  await ditto.store.execute(
    '''
    UPDATE orders
    SET shipping = { city: :city }
    WHERE _id = :id
    ''',
    arguments: {
      'id': orderId,
      'city': 'Tokyo',
    },
  );
}

/// ✅ GOOD: Use bracket notation for nested updates
Future<void> updateNestedField_Correct(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    '''
    UPDATE orders
    SET shipping.city = :city
    WHERE _id = :id
    ''',
    arguments: {
      'id': orderId,
      'city': 'Tokyo',
    },
  );
}

/// Anti-Pattern 8: EVICT without canceling subscription
///
/// ❌ BAD: EVICT while subscription is active
Future<void> cleanupOldData_Problematic(Ditto ditto, DateTime beforeDate) async {
  // PROBLEM: If subscription is still active, data will be re-synced immediately!
  await ditto.store.execute(
    '''
    EVICT FROM orders
    WHERE completedAt < :beforeDate
    ''',
    arguments: {
      'beforeDate': beforeDate.toIso8601String(),
    },
  );

  // Result: Wasted bandwidth, re-syncing data we just evicted
}

/// ✅ GOOD: Cancel subscription first, then EVICT
Future<void> cleanupOldData_Correct(
  Ditto ditto,
  Subscription subscription,
  DateTime beforeDate,
) async {
  // Step 1: Cancel subscription to prevent re-sync
  subscription.cancel();

  // Step 2: Now safe to EVICT
  await ditto.store.execute(
    '''
    EVICT FROM orders
    WHERE completedAt < :beforeDate
    ''',
    arguments: {
      'beforeDate': beforeDate.toIso8601String(),
    },
  );
}

/// Anti-Pattern 9: Not using ORDER BY with LIMIT
///
/// ❌ BAD: Unpredictable results with LIMIT
Future<void> getRecentOrders_Unpredictable(Ditto ditto) async {
  // Which 10 orders? Results are non-deterministic
  final result = await ditto.store.execute(
    'SELECT * FROM orders LIMIT 10',
  );

  final orders = result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Always use ORDER BY with LIMIT
Future<void> getRecentOrders_Predictable(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM orders
    ORDER BY createdAt DESC
    LIMIT 10
    ''',
  );

  final orders = result.items.map((item) => item.value).toList();
}

/// Anti-Pattern 10: Trying to use JOINs
///
/// ❌ BAD: Ditto DQL does not support JOINs
Future<void> getOrdersWithCustomers_Wrong(Ditto ditto) async {
  // This will FAIL - JOINs are not supported
  // final result = await ditto.store.execute(
  //   '''
  //   SELECT * FROM orders
  //   JOIN customers ON orders.customerId = customers._id
  //   ''',
  // );
}

/// ✅ GOOD: Denormalize data or use multiple queries
Future<void> getOrdersWithCustomers_Correct(Ditto ditto) async {
  // Option 1: Denormalize (embed customer data in order)
  final result = await ditto.store.execute(
    '''
    SELECT * FROM orders
    WHERE customerName = :name
    ''',
    arguments: {'name': 'John Doe'},
  );

  // Option 2: Multiple queries (if needed)
  final ordersResult = await ditto.store.execute('SELECT * FROM orders');
  final orders = ordersResult.items.map((item) => item.value).toList();

  for (final order in orders) {
    final customerId = order['customerId'];
    final customerResult = await ditto.store.execute(
      'SELECT * FROM customers WHERE _id = :id',
      arguments: {'id': customerId},
    );
    // Process customer data...
  }
}

// Mock functions for examples
Future<void> performComplexCalculation(Map<String, dynamic> product) async {
  await Future.delayed(Duration(milliseconds: 100));
}

Future<void> saveToExternalSystem(Map<String, dynamic> product) async {
  await Future.delayed(Duration(milliseconds: 50));
}
