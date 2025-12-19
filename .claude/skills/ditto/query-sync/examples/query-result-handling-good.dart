// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// Example: Query Result Handling Best Practices
// This file demonstrates proper QueryResultItem extraction to prevent memory leaks

import 'package:ditto/ditto.dart';

/// Example 1: Immediate data extraction (most important pattern)
///
/// ✅ GOOD: Extract data from QueryResultItems immediately
Future<void> queryAndExtractImmediately(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE isActive = true',
  );

  // CRITICAL: Extract data immediately, don't retain QueryResultItems
  final products = result.items.map((item) {
    final data = item.value; // Materialize the data
    return data; // Return the plain Map
  }).toList();

  // Now safe to use products - QueryResultItems are released
  print('Found ${products.length} active products');

  for (final product in products) {
    print('Product: ${product['name']}');
  }
}

/// Example 2: Extract to model objects
///
/// ✅ GOOD: Transform QueryResultItems to domain models immediately
class Product {
  final String id;
  final String name;
  final double price;
  final bool isActive;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

Future<List<Product>> queryProducts(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE isActive = true',
  );

  // Extract to model objects immediately
  final products = result.items.map((item) {
    final data = item.value;
    return Product.fromJson(data);
  }).toList();

  // QueryResultItems released, we have type-safe models
  return products;
}

/// Example 3: Extract in observer callback
///
/// ✅ GOOD: Never store QueryResultItems in state
class ProductsState {
  // Store plain data, NOT QueryResultItems
  List<Map<String, dynamic>> products = [];

  void updateFromObserver(QueryResult result) {
    // Extract immediately in the callback
    products = result.items.map((item) {
      return item.value; // Materialize each item
    }).toList();

    // QueryResultItems are now released
  }
}

/// Example 4: Partial field extraction
///
/// ✅ GOOD: Extract only needed fields for efficiency
Future<List<String>> getProductNames(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT name FROM products WHERE isActive = true',
  );

  // Extract just the names
  final names = result.items.map((item) {
    return item.value['name'] as String;
  }).toList();

  return names;
}

/// Example 5: Aggregation with immediate extraction
///
/// ✅ GOOD: Extract aggregated results immediately
Future<Map<String, dynamic>> getOrderStats(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''
    SELECT
      COUNT(*) as totalOrders,
      SUM(totalAmount) as revenue,
      AVG(totalAmount) as avgOrderValue
    FROM orders
    WHERE status = 'completed'
    ''',
  );

  if (result.items.isEmpty) {
    return {
      'totalOrders': 0,
      'revenue': 0.0,
      'avgOrderValue': 0.0,
    };
  }

  // Extract aggregated data immediately
  final stats = result.items.first.value;

  return {
    'totalOrders': stats['totalOrders'] as int,
    'revenue': (stats['revenue'] as num?)?.toDouble() ?? 0.0,
    'avgOrderValue': (stats['avgOrderValue'] as num?)?.toDouble() ?? 0.0,
  };
}

/// Example 6: Conditional extraction with filtering
///
/// ✅ GOOD: Extract and filter in one pass
Future<List<Map<String, dynamic>>> getHighValueOrders(
  Ditto ditto,
  double minValue,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'pending'},
  );

  // Extract and filter in single operation
  final highValueOrders = result.items
      .map((item) => item.value) // Extract first
      .where((order) => (order['totalAmount'] as num) >= minValue)
      .toList();

  return highValueOrders;
}

/// Example 7: Grouping after extraction
///
/// ✅ GOOD: Extract data, then group by key
Future<Map<String, List<Map<String, dynamic>>>> getOrdersByStatus(
  Ditto ditto,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders',
  );

  // Extract all orders first
  final orders = result.items.map((item) => item.value).toList();

  // Group by status (now working with plain Maps)
  final ordersByStatus = <String, List<Map<String, dynamic>>>{};

  for (final order in orders) {
    final status = order['status'] as String? ?? 'unknown';
    ordersByStatus.putIfAbsent(status, () => []);
    ordersByStatus[status]!.add(order);
  }

  return ordersByStatus;
}

/// Example 8: Transform and reduce
///
/// ✅ GOOD: Extract, transform, and aggregate
Future<double> calculateTotalRevenue(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'completed'},
  );

  // Extract and reduce in one operation
  final totalRevenue = result.items
      .map((item) => item.value['totalAmount'] as num)
      .fold<double>(0.0, (sum, amount) => sum + amount.toDouble());

  return totalRevenue;
}

/// Example 9: Pagination with extraction
///
/// ✅ GOOD: Extract paginated results immediately
class PaginatedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final bool hasMore;

  PaginatedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });
}

Future<PaginatedResult<Map<String, dynamic>>> getProductsPage(
  Ditto ditto,
  int page,
  int pageSize,
) async {
  final offset = page * pageSize;

  // Query with extra item to check if more exist
  final result = await ditto.store.execute(
    '''
    SELECT * FROM products
    WHERE isActive = true
    ORDER BY name
    LIMIT :limit OFFSET :offset
    ''',
    arguments: {
      'limit': pageSize + 1,
      'offset': offset,
    },
  );

  // Extract immediately
  final allItems = result.items.map((item) => item.value).toList();

  // Check if more pages exist
  final hasMore = allItems.length > pageSize;

  // Take only requested page size
  final items = hasMore ? allItems.take(pageSize).toList() : allItems;

  return PaginatedResult(
    items: items,
    page: page,
    pageSize: pageSize,
    hasMore: hasMore,
  );
}

/// Example 10: Streaming extraction for large datasets
///
/// ✅ GOOD: Process large result sets efficiently
Future<void> processLargeDataset(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM largeCollection',
  );

  // Extract in batches to avoid memory spike
  const batchSize = 100;
  final totalItems = result.items.length;

  for (int i = 0; i < totalItems; i += batchSize) {
    final end = (i + batchSize < totalItems) ? i + batchSize : totalItems;

    // Extract batch
    final batch = result.items
        .skip(i)
        .take(batchSize)
        .map((item) => item.value)
        .toList();

    // Process batch
    await _processBatch(batch);

    print('Processed ${end}/${totalItems} items');
  }
}

Future<void> _processBatch(List<Map<String, dynamic>> batch) async {
  // Process batch logic
  await Future.delayed(Duration(milliseconds: 10));
}

/// Example 11: Null-safe extraction
///
/// ✅ GOOD: Handle missing fields gracefully
Future<List<Map<String, dynamic>>> getOrdersWithDefaults(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders',
  );

  // Extract with default values for missing fields
  final orders = result.items.map((item) {
    final data = item.value;

    return {
      '_id': data['_id'] as String,
      'customerName': data['customerName'] as String? ?? 'Unknown',
      'totalAmount': (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      'status': data['status'] as String? ?? 'pending',
      'createdAt': data['createdAt'] as String? ?? DateTime.now().toIso8601String(),
    };
  }).toList();

  return orders;
}

/// Example 12: Extraction with validation
///
/// ✅ GOOD: Validate during extraction
class ValidationError {
  final String itemId;
  final String message;

  ValidationError(this.itemId, this.message);
}

Future<({List<Map<String, dynamic>> valid, List<ValidationError> errors})>
    extractAndValidate(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders',
  );

  final validOrders = <Map<String, dynamic>>[];
  final errors = <ValidationError>[];

  // Extract and validate in one pass
  for (final item in result.items) {
    final data = item.value;
    final id = data['_id'] as String? ?? 'unknown';

    // Validate required fields
    if (data['customerName'] == null) {
      errors.add(ValidationError(id, 'Missing customerName'));
      continue;
    }

    if (data['totalAmount'] == null) {
      errors.add(ValidationError(id, 'Missing totalAmount'));
      continue;
    }

    validOrders.add(data);
  }

  return (valid: validOrders, errors: errors);
}

/// Example 13: Extract with field mapping/transformation
///
/// ✅ GOOD: Transform field names during extraction
Future<List<Map<String, dynamic>>> getOrdersWithMappedFields(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders',
  );

  // Extract and map field names
  final orders = result.items.map((item) {
    final data = item.value;

    return {
      'id': data['_id'],
      'customer': data['customerName'],
      'total': data['totalAmount'],
      'orderStatus': data['status'],
      'timestamp': data['createdAt'],
    };
  }).toList();

  return orders;
}

/// Example 14: Single item extraction with null check
///
/// ✅ GOOD: Safe extraction of single result
Future<Map<String, dynamic>?> getOrderById(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': orderId},
  );

  // Safe extraction with null check
  if (result.items.isEmpty) {
    return null;
  }

  return result.items.first.value;
}

/// Example 15: Memory-efficient extraction for computed values
///
/// ✅ GOOD: Compute during extraction without storing intermediate data
Future<Map<String, int>> getProductCountByCategory(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE isActive = true',
  );

  // Compute directly during extraction
  final countByCategory = <String, int>{};

  for (final item in result.items) {
    final category = item.value['category'] as String? ?? 'uncategorized';
    countByCategory[category] = (countByCategory[category] ?? 0) + 1;
  }

  // No intermediate list created, memory-efficient
  return countByCategory;
}
