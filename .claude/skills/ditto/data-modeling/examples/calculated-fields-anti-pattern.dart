// ============================================================================
// Calculated Fields Anti-Pattern (DO NOT STORE)
// ============================================================================
//
// This example demonstrates the ANTI-PATTERN of storing calculated fields
// and shows the CORRECT pattern of calculating values in the application layer.
//
// KEY PRINCIPLE: Fields derivable from existing data should NEVER be stored.
//
// ANTI-PATTERN EXAMPLES:
// - lineTotal = price × quantity
// - subtotal = sum(lineTotals)
// - total = subtotal + tax
// - averageRating = sum(ratings) / count(ratings)
// - currentStock = initialStock - sum(orderQuantities)
// - age = currentDate - birthdate
//
// WHY THIS IS CRITICAL:
// - Wastes bandwidth (multiplied by devices × sync frequency)
// - Increases document size (impacts sync performance)
// - Creates synchronization overhead (deltas for derived values)
// - Risk of stale data (calculations may not reflect current source data)
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: Storing Order Totals (❌ BAD)
// ============================================================================

/// ❌ BAD: Storing calculated lineTotal and totals fields
Future<void> createOrderWithCalculatedFieldsBad(Ditto ditto, String orderId) async {
  // ❌ ANTI-PATTERN: Storing calculated values
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'items': {
          'item_1': {
            'productId': 'prod_123',
            'name': 'Widget',
            'price': 12.99,
            'quantity': 2,
            'lineTotal': 25.98, // ❌ Calculated: price × quantity
          },
          'item_2': {
            'productId': 'prod_456',
            'name': 'Gadget',
            'price': 8.50,
            'quantity': 1,
            'lineTotal': 8.50, // ❌ Calculated
          },
        },
        'subtotal': 34.48,  // ❌ Calculated: sum of lineTotals
        'tax': 3.45,        // ❌ Calculated: subtotal × taxRate
        'total': 37.93,     // ❌ Calculated: subtotal + tax
      },
    },
  );

  // Problems:
  // 1. 4 unnecessary fields (lineTotal × 2, subtotal, tax, total) sync across all peers
  // 2. If price or quantity changes, must update both source + calculated fields
  // 3. Risk of inconsistency (calculated fields may not match source data)
  // 4. Wastes bandwidth: 4 fields × N orders × M devices = significant overhead
}

// ============================================================================
// CORRECT PATTERN 1: Calculate in Application Layer (✅ GOOD)
// ============================================================================

/// ✅ GOOD: Store only source data, calculate totals in app
Future<void> createOrderWithCalculationGood(Ditto ditto, String orderId) async {
  // ✅ Store only source data
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'items': {
          'item_1': {
            'productId': 'prod_123',
            'name': 'Widget',
            'price': 12.99,
            'quantity': 2,
          },
          'item_2': {
            'productId': 'prod_456',
            'name': 'Gadget',
            'price': 8.50,
            'quantity': 1,
          },
        },
      },
    },
  );

  // ✅ Calculate totals on-demand in app
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  if (result.items.isNotEmpty) {
    final order = result.items.first.value;
    final items = order['items'] as Map<String, dynamic>;

    // Calculate lineTotal for each item
    final itemsWithTotals = items.map((key, item) {
      final lineTotal = (item['price'] as num) * (item['quantity'] as int);
      return MapEntry(key, {...item, 'lineTotal': lineTotal});
    });

    // Calculate order totals
    final subtotal = itemsWithTotals.values.fold<double>(
      0.0,
      (sum, item) => sum + (item['lineTotal'] as num).toDouble(),
    );
    final taxRate = 0.10; // 10% tax
    final tax = subtotal * taxRate;
    final total = subtotal + tax;

    // Display calculated values
    print('Order $orderId:');
    print('  Subtotal: \$${subtotal.toStringAsFixed(2)}');
    print('  Tax: \$${tax.toStringAsFixed(2)}');
    print('  Total: \$${total.toStringAsFixed(2)}');

    // Benefits:
    // 1. Smaller document size (no calculated fields)
    // 2. Always accurate (calculated from source data)
    // 3. Less sync traffic (no deltas for calculated values)
    // 4. Simpler updates (only update source data)
  }
}

// ============================================================================
// Helper Functions for Calculating Order Totals
// ============================================================================

/// Calculate line total for a single item
double calculateLineTotal(Map<String, dynamic> item) {
  return (item['price'] as num).toDouble() * (item['quantity'] as int);
}

/// Calculate subtotal from all items
double calculateSubtotal(Map<String, dynamic> items) {
  return items.values.fold(0.0, (sum, item) {
    return sum + calculateLineTotal(item);
  });
}

/// Calculate tax from subtotal
double calculateTax(double subtotal, double taxRate) {
  return subtotal * taxRate;
}

/// Calculate total order amount
double calculateTotal(double subtotal, double tax) {
  return subtotal + tax;
}

/// Get order with calculated totals (reusable pattern)
Map<String, dynamic> getOrderWithCalculatedTotals(
  Map<String, dynamic> order,
  double taxRate,
) {
  final items = order['items'] as Map<String, dynamic>;
  final subtotal = calculateSubtotal(items);
  final tax = calculateTax(subtotal, taxRate);
  final total = calculateTotal(subtotal, tax);

  return {
    ...order,
    'calculatedSubtotal': subtotal,
    'calculatedTax': tax,
    'calculatedTotal': total,
  };
}

// ============================================================================
// ANTI-PATTERN 2: Storing Inventory Count (❌ BAD)
// ============================================================================

/// ❌ BAD: Storing currentStock as a field (requires cross-collection updates)
Future<void> updateInventoryBad(Ditto ditto, String productId, int orderedQuantity) async {
  // ❌ ANTI-PATTERN: Update inventory counter when order created
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (currentStock COUNTER)
    APPLY currentStock INCREMENT BY :delta
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'delta': -orderedQuantity,
    },
  );

  // Problems:
  // 1. Cross-collection synchronization (orders → products)
  // 2. Complex rollback logic if order cancelled
  // 3. Risk of inconsistency between orders and inventory
  // 4. Hard to debug (audit trail split across collections)
}

// ============================================================================
// CORRECT PATTERN 2: Calculate Inventory from Orders (✅ GOOD)
// ============================================================================

/// ✅ GOOD: Calculate currentStock from orders on-demand
Future<int> getCurrentStock(Ditto ditto, String productId) async {
  // Get initial stock from product
  final productResult = await ditto.store.execute(
    'SELECT initialStock FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  if (productResult.items.isEmpty) return 0;

  final initialStock = productResult.items.first.value['initialStock'] as int;

  // Calculate total ordered quantity from orders
  final ordersResult = await ditto.store.execute(
    'SELECT items FROM orders WHERE items.:productId != null',
    arguments: {'productId': productId},
  );

  final totalOrdered = ordersResult.items.fold<int>(0, (sum, item) {
    final order = item.value;
    final items = order['items'] as Map<String, dynamic>;
    final productItem = items[productId];
    if (productItem != null) {
      return sum + (productItem['quantity'] as int);
    }
    return sum;
  });

  final currentStock = initialStock - totalOrdered;

  print('Product $productId:');
  print('  Initial stock: $initialStock');
  print('  Total ordered: $totalOrdered');
  print('  Current stock: $currentStock');

  // Benefits:
  // 1. Single source of truth (orders collection)
  // 2. No cross-collection updates needed
  // 3. Self-correcting (recalculate if mismatch)
  // 4. Easy debugging (full audit trail in orders)
  // 5. No rollback logic needed (just don't count cancelled orders)

  return currentStock;
}

// ============================================================================
// ANTI-PATTERN 3: Storing Average Rating (❌ BAD)
// ============================================================================

/// ❌ BAD: Storing averageRating as a field
Future<void> updateProductRatingBad(
  Ditto ditto,
  String productId,
  int newRating,
) async {
  // ❌ ANTI-PATTERN: Calculate and store average every time
  final ratingsResult = await ditto.store.execute(
    'SELECT ratings FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  final ratings = ratingsResult.items.first.value['ratings'] as List<dynamic>;
  final updatedRatings = [...ratings, newRating];
  final average = updatedRatings.fold<double>(
    0.0,
    (sum, rating) => sum + (rating as num).toDouble(),
  ) / updatedRatings.length;

  await ditto.store.execute(
    '''
    UPDATE products
    SET ratings = :ratings, averageRating = :average
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'ratings': updatedRatings,
      'average': average,
    },
  );

  // Problems:
  // 1. averageRating syncs unnecessarily (derivable from ratings)
  // 2. Must recalculate and update on every rating change
  // 3. Risk of stale data (average may not match current ratings)
}

// ============================================================================
// CORRECT PATTERN 3: Calculate Average Rating On-Demand (✅ GOOD)
// ============================================================================

/// ✅ GOOD: Calculate average rating in app
Future<double> getAverageRating(Ditto ditto, String productId) async {
  final result = await ditto.store.execute(
    'SELECT ratings FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  if (result.items.isEmpty) return 0.0;

  final ratings = result.items.first.value['ratings'] as List<dynamic>;

  if (ratings.isEmpty) return 0.0;

  final average = ratings.fold<double>(
    0.0,
    (sum, rating) => sum + (rating as num).toDouble(),
  ) / ratings.length;

  return average;
}

/// Add rating without storing calculated average
Future<void> addProductRatingGood(
  Ditto ditto,
  String productId,
  int newRating,
) async {
  // ✅ Store only source data (ratings array)
  await ditto.store.execute(
    '''
    UPDATE products
    SET ratings = ratings || [:rating]
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'rating': newRating,
    },
  );

  // ✅ Calculate average on-demand when needed
  final average = await getAverageRating(ditto, productId);
  print('New average rating: ${average.toStringAsFixed(1)}');

  // Benefits:
  // 1. No averageRating field syncing
  // 2. Always accurate (calculated from current ratings)
  // 3. Simpler update logic
}

// ============================================================================
// ANTI-PATTERN 4: Storing Age (❌ BAD)
// ============================================================================

/// ❌ BAD: Storing age as a field (becomes stale)
Future<void> createUserWithAgeBad(Ditto ditto, String userId) async {
  final birthdate = DateTime(1990, 1, 15);
  final age = DateTime.now().year - birthdate.year;

  await ditto.store.execute(
    'INSERT INTO users DOCUMENTS (:user)',
    arguments: {
      'user': {
        '_id': userId,
        'birthdate': birthdate.toIso8601String(),
        'age': age, // ❌ Becomes stale after birthday
      },
    },
  );
}

// ============================================================================
// CORRECT PATTERN 4: Calculate Age On-Demand (✅ GOOD)
// ============================================================================

/// ✅ GOOD: Calculate age from birthdate on-demand
int calculateAge(DateTime birthdate) {
  final now = DateTime.now();
  int age = now.year - birthdate.year;

  // Adjust if birthday hasn't occurred this year
  if (now.month < birthdate.month ||
      (now.month == birthdate.month && now.day < birthdate.day)) {
    age--;
  }

  return age;
}

Future<void> createUserWithBirthdateGood(Ditto ditto, String userId) async {
  final birthdate = DateTime(1990, 1, 15);

  // ✅ Store only source data (birthdate)
  await ditto.store.execute(
    'INSERT INTO users DOCUMENTS (:user)',
    arguments: {
      'user': {
        '_id': userId,
        'birthdate': birthdate.toIso8601String(),
      },
    },
  );

  // ✅ Calculate age on-demand when needed
  final age = calculateAge(birthdate);
  print('User age: $age');

  // Benefits:
  // 1. Always accurate (calculated from current date)
  // 2. No need to update on birthdays
  // 3. Smaller document size
}

// ============================================================================
// Summary: When to Store vs Calculate
// ============================================================================

/// Decision Tree for Field Storage
///
/// Q: Can this value be calculated from existing data?
///    ↓ YES → Calculate in app (DO NOT STORE)
///    ↓ NO
///    ↓
/// Q: Is this an independent metric? (likes, views, votes)
///    ↓ YES → Use COUNTER type (store as COUNTER CRDT)
///    ↓ NO
///    ↓
/// Q: Is this snapshot data? (price at order time)
///    ↓ YES → Store (denormalization for history)
///    ↓ NO
///    ↓
/// → Store as source data

// ============================================================================
// Fields to NEVER Store (Examples)
// ============================================================================

/// ❌ Calculated totals
/// - lineTotal = price × quantity
/// - subtotal = sum(lineTotals)
/// - total = subtotal + tax
/// - amount = quantity × rate
///
/// ❌ Derived inventory
/// - currentStock = initialStock - sum(orderQuantities)
/// - availableStock = currentStock - reservedStock
///
/// ❌ Aggregates from arrays
/// - averageRating = sum(ratings) / count(ratings)
/// - totalViews = count(viewEvents)
///
/// ❌ Date calculations
/// - age = currentDate - birthdate
/// - daysUntilExpiry = expiryDate - currentDate
/// - daysSinceCreation = currentDate - createdAt
///
/// ❌ UI state
/// - isExpanded, isSelected, isHovered
/// - scrollPosition, selectedTab
///
/// ✅ Store instead:
/// - Source data: price, quantity, initialStock, birthdate
/// - Independent counters: viewCount (COUNTER), likeCount (COUNTER)
/// - Snapshot data: priceAtOrderTime (denormalized for history)
