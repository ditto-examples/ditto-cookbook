// Example: DQL Query Best Practices
// This file demonstrates the CURRENT, recommended DQL API patterns

import 'package:ditto/ditto.dart';

/// Example 1: Basic SELECT query with WHERE clause
///
/// ✅ GOOD: Uses DQL string-based API
Future<void> queryActiveOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'active'},
  );

  // Extract data immediately (see query-result-handling-good.dart)
  final orders = result.items.map((item) {
    return item.value; // Materialize data immediately
  }).toList();

  print('Found ${orders.length} active orders');
}

/// Example 2: Query with multiple conditions
///
/// ✅ GOOD: Clear, parameterized query
Future<void> queryRecentOrders(Ditto ditto, DateTime since) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM orders
    WHERE status = :status
      AND createdAt >= :since
    ORDER BY createdAt DESC
    ''',
    arguments: {
      'status': 'pending',
      'since': since.toIso8601String(),
    },
  );

  final recentOrders = result.items.map((item) => item.value).toList();
  print('Found ${recentOrders.length} recent pending orders');
}

/// Example 3: Query with field selection
///
/// ✅ GOOD: Select only needed fields for performance
Future<void> queryOrderSummaries(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, customerName, totalAmount FROM orders WHERE status = :status',
    arguments: {'status': 'completed'},
  );

  final summaries = result.items.map((item) => item.value).toList();
  print('Retrieved ${summaries.length} order summaries');
}

/// Example 4: COUNT query
///
/// ✅ GOOD: Efficient aggregation query
Future<int> countActiveProducts(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(*) as total FROM products WHERE isActive = true',
  );

  if (result.items.isEmpty) return 0;

  final count = result.items.first.value['total'] as int;
  return count;
}

/// Example 5: Query with LIMIT and OFFSET for pagination
///
/// ✅ GOOD: Paginated query pattern
Future<List<Map<String, dynamic>>> queryProductsPage(
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

/// Example 6: UPDATE query
///
/// ✅ GOOD: Parameterized UPDATE with WHERE clause
Future<void> updateOrderStatus(
  Ditto ditto,
  String orderId,
  String newStatus,
) async {
  await ditto.store.execute(
    '''
    UPDATE orders
    SET status = :status, updatedAt = :updatedAt
    WHERE _id = :id
    ''',
    arguments: {
      'id': orderId,
      'status': newStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );

  print('Updated order $orderId to status: $newStatus');
}

/// Example 7: INSERT query (upsert pattern)
///
/// ✅ GOOD: Use INSERT with DOCUMENTS keyword
Future<void> createNewOrder(Ditto ditto, Map<String, dynamic> orderData) async {
  await ditto.store.execute(
    '''
    INSERT INTO orders
    DOCUMENTS (:order)
    ''',
    arguments: {
      'order': {
        '_id': orderData['_id'],
        'customerName': orderData['customerName'],
        'items': orderData['items'],
        'totalAmount': orderData['totalAmount'],
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      },
    },
  );

  print('Created order: ${orderData['_id']}');
}

/// Example 8: EVICT query (remove local data)
///
/// ✅ GOOD: EVICT with specific WHERE clause
/// WARNING: Always cancel subscription first to avoid re-sync loop
Future<void> evictOldCompletedOrders(Ditto ditto, DateTime beforeDate) async {
  // IMPORTANT: Cancel related subscription before EVICT
  // See subscription-lifecycle-good.dart for full pattern

  await ditto.store.execute(
    '''
    EVICT FROM orders
    WHERE status = 'completed'
      AND completedAt < :beforeDate
    ''',
    arguments: {
      'beforeDate': beforeDate.toIso8601String(),
    },
  );

  print('Evicted completed orders before ${beforeDate.toIso8601String()}');
}

/// Example 9: Query with nested field access
///
/// ✅ GOOD: Use dot notation for nested fields
Future<void> queryOrdersByShippingCity(Ditto ditto, String city) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM orders
    WHERE shippingAddress.city = :city
      AND status != 'completed'
    ''',
    arguments: {'city': city},
  );

  final orders = result.items.map((item) => item.value).toList();
  print('Found ${orders.length} orders for city: $city');
}

/// Example 10: Transaction alternative for Flutter
///
/// ✅ GOOD: Sequential DQL with error handling (Flutter transaction alternative)
/// Note: Flutter SDK does not support transactions. Use sequential DQL instead.
Future<void> transferProductStock(
  Ditto ditto,
  String fromWarehouseId,
  String toWarehouseId,
  String productId,
  int quantity,
) async {
  try {
    // Step 1: Decrement from source warehouse
    await ditto.store.execute(
      '''
      UPDATE warehouses
      SET stock[:productId] = stock[:productId] - :quantity
      WHERE _id = :warehouseId
      ''',
      arguments: {
        'productId': productId,
        'quantity': quantity,
        'warehouseId': fromWarehouseId,
      },
    );

    // Step 2: Increment at destination warehouse
    await ditto.store.execute(
      '''
      UPDATE warehouses
      SET stock[:productId] = stock[:productId] + :quantity
      WHERE _id = :warehouseId
      ''',
      arguments: {
        'productId': productId,
        'quantity': quantity,
        'warehouseId': toWarehouseId,
      },
    );

    print('Successfully transferred $quantity units of $productId');
  } catch (e) {
    print('Stock transfer failed: $e');
    // Implement compensating logic if needed
    rethrow;
  }
}
