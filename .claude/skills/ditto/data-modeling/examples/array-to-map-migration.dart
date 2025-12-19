// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Array to MAP Migration Pattern
// ============================================================================
//
// This example demonstrates how to migrate from mutable arrays to MAP
// structures in Ditto to avoid CRDT merge conflicts.
//
// PATTERNS DEMONSTRATED:
// 1. ❌ Arrays with mutable items (concurrent update conflicts)
// 2. ✅ MAP structure for concurrent-safe updates
// 3. ✅ Migration helper functions
// 4. ✅ "Add-wins" semantics with MAP
// 5. ✅ Before/after comparison with concurrent updates
// 6. ✅ Item removal patterns in MAP
// 7. ✅ Querying MAP structures
//
// PROBLEM:
// Arrays in Ditto use "last-write-wins" semantics. If two devices modify
// the same array concurrently, one device's changes will be lost during merge.
//
// SOLUTION:
// Use MAP structures where keys are unique identifiers. MAPs support
// field-level merging with "add-wins" semantics, preserving concurrent updates.
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN: Array-Based Structure (Before Migration)
// ============================================================================

/// ❌ BAD: Using array for shopping cart items
/// Problem: Concurrent updates to the same item will conflict
Future<void> arrayBasedCartBad(Ditto ditto, String cartId) async {
  // Initial cart with array of items
  await ditto.store.execute(
    '''
    INSERT INTO carts (_id, userId, items)
    VALUES (:cartId, :userId, :items)
    ''',
    arguments: {
      'cartId': cartId,
      'userId': 'user_123',
      'items': [
        {
          'productId': 'prod_1',
          'name': 'Laptop',
          'quantity': 1,
          'price': 999.99,
        },
        {
          'productId': 'prod_2',
          'name': 'Mouse',
          'quantity': 2,
          'price': 29.99,
        },
      ],
    },
  );

  // ❌ Problem: Updating array item requires reading entire array,
  // modifying it, and writing it back
  final result = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :cartId',
    arguments: {'cartId': cartId},
  );

  if (result.items.isNotEmpty) {
    final cart = result.items.first.value;
    final items = List<Map<String, dynamic>>.from(cart['items'] as List);

    // Update quantity for product
    final itemIndex = items.indexWhere((item) => item['productId'] == 'prod_1');
    if (itemIndex != -1) {
      items[itemIndex]['quantity'] = 2; // Increment from 1 to 2
    }

    // Write entire array back
    await ditto.store.execute(
      'UPDATE carts SET items = :items WHERE _id = :cartId',
      arguments: {'cartId': cartId, 'items': items},
    );
  }

  // 🚨 CONFLICT SCENARIO:
  // If Device A and Device B both read the array, make different changes,
  // and write back concurrently, one device's changes will be lost!
  //
  // Device A: Updates quantity for prod_1 to 2
  // Device B: Updates quantity for prod_2 to 3
  // Result after merge: Only one update survives (last-write-wins)
}

// ============================================================================
// RECOMMENDED PATTERN: MAP-Based Structure (After Migration)
// ============================================================================

/// ✅ GOOD: Using MAP for shopping cart items
/// Benefit: Field-level merging with "add-wins" semantics
Future<void> mapBasedCartGood(Ditto ditto, String cartId) async {
  // Use MAP where key = productId, value = item details
  await ditto.store.execute(
    '''
    INSERT INTO carts (_id, userId, items)
    VALUES (:cartId, :userId, :items)
    ''',
    arguments: {
      'cartId': cartId,
      'userId': 'user_123',
      'items': {
        'prod_1': {
          'productId': 'prod_1',
          'name': 'Laptop',
          'quantity': 1,
          'price': 999.99,
          'addedAt': DateTime.now().toIso8601String(),
        },
        'prod_2': {
          'productId': 'prod_2',
          'name': 'Mouse',
          'quantity': 2,
          'price': 29.99,
          'addedAt': DateTime.now().toIso8601String(),
        },
      },
    },
  );

  // ✅ Update specific item without reading entire cart
  await ditto.store.execute(
    '''
    UPDATE carts
    SET items.prod_1.quantity = :quantity
    WHERE _id = :cartId
    ''',
    arguments: {'cartId': cartId, 'quantity': 2},
  );

  // ✅ CONCURRENT UPDATE SCENARIO:
  // Device A: Updates items.prod_1.quantity to 2
  // Device B: Updates items.prod_2.quantity to 3
  // Result after merge: Both updates preserved! (field-level merge)
}

// ============================================================================
// Migration Helper Functions
// ============================================================================

/// Converts array-based cart to MAP-based cart
Future<void> migrateCartToMap(Ditto ditto, String cartId) async {
  // Step 1: Read existing cart with array
  final result = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :cartId',
    arguments: {'cartId': cartId},
  );

  if (result.items.isEmpty) {
    print('Cart not found: $cartId');
    return;
  }

  final cart = result.items.first.value;
  final items = cart['items'];

  // Step 2: Check if already using MAP structure
  if (items is Map) {
    print('Cart $cartId already uses MAP structure');
    return;
  }

  // Step 3: Convert array to MAP
  if (items is List) {
    final itemsMap = <String, dynamic>{};

    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final productId = item['productId'] as String?;
        if (productId != null) {
          // Use productId as key
          itemsMap[productId] = {
            ...item,
            'migratedAt': DateTime.now().toIso8601String(),
          };
        }
      }
    }

    // Step 4: Update document with MAP structure
    await ditto.store.execute(
      'UPDATE carts SET items = :items WHERE _id = :cartId',
      arguments: {'cartId': cartId, 'items': itemsMap},
    );

    print('✅ Migrated cart $cartId from array to MAP (${itemsMap.length} items)');
  }
}

/// Batch migration for all carts
Future<void> migrateAllCartsToMap(Ditto ditto) async {
  // Query all carts
  final result = await ditto.store.execute('SELECT * FROM carts');

  print('Found ${result.items.length} carts to check for migration');

  int migratedCount = 0;
  int alreadyMigratedCount = 0;

  for (final item in result.items) {
    final cart = item.value;
    final cartId = cart['_id'] as String;
    final items = cart['items'];

    if (items is List) {
      await migrateCartToMap(ditto, cartId);
      migratedCount++;
    } else if (items is Map) {
      alreadyMigratedCount++;
    }
  }

  print('Migration complete:');
  print('  - Migrated: $migratedCount carts');
  print('  - Already using MAP: $alreadyMigratedCount carts');
}

// ============================================================================
// Common Operations with MAP Structure
// ============================================================================

/// Add item to cart (MAP structure)
Future<void> addItemToCart(
  Ditto ditto,
  String cartId,
  String productId,
  Map<String, dynamic> itemData,
) async {
  await ditto.store.execute(
    '''
    UPDATE carts
    SET items.$productId = :itemData
    WHERE _id = :cartId
    ''',
    arguments: {
      'cartId': cartId,
      'itemData': {
        ...itemData,
        'productId': productId,
        'addedAt': DateTime.now().toIso8601String(),
      },
    },
  );
}

/// Update item quantity (field-level update)
Future<void> updateItemQuantity(
  Ditto ditto,
  String cartId,
  String productId,
  int newQuantity,
) async {
  await ditto.store.execute(
    '''
    UPDATE carts
    SET items.$productId.quantity = :quantity,
        items.$productId.updatedAt = :updatedAt
    WHERE _id = :cartId
    ''',
    arguments: {
      'cartId': cartId,
      'quantity': newQuantity,
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );
}

/// Remove item from cart (set to null)
Future<void> removeItemFromCart(
  Ditto ditto,
  String cartId,
  String productId,
) async {
  // In Ditto, setting a MAP field to null removes it
  await ditto.store.execute(
    '''
    UPDATE carts
    SET items.$productId = null
    WHERE _id = :cartId
    ''',
    arguments: {'cartId': cartId},
  );
}

/// Get cart with MAP structure
Future<Map<String, dynamic>?> getCart(Ditto ditto, String cartId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :cartId',
    arguments: {'cartId': cartId},
  );

  if (result.items.isEmpty) return null;

  final cart = result.items.first.value;
  final items = cart['items'] as Map<String, dynamic>?;

  // Convert MAP to list for UI display if needed
  final itemsList = items?.entries.map((entry) {
    return {
      'productId': entry.key,
      ...entry.value as Map<String, dynamic>,
    };
  }).toList();

  return {
    '_id': cart['_id'],
    'userId': cart['userId'],
    'items': itemsList ?? [],
    'itemCount': items?.length ?? 0,
  };
}

// ============================================================================
// Concurrent Update Demonstration
// ============================================================================

/// Simulates concurrent updates with array (loses changes)
Future<void> demonstrateConcurrentArrayConflict(Ditto ditto) async {
  const cartId = 'cart_conflict_demo_array';

  // Create cart with array
  await ditto.store.execute(
    'INSERT INTO carts (_id, userId, items) VALUES (:id, :userId, :items)',
    arguments: {
      'id': cartId,
      'userId': 'user_123',
      'items': [
        {'productId': 'prod_1', 'quantity': 1},
        {'productId': 'prod_2', 'quantity': 1},
      ],
    },
  );

  // Simulate Device A: Read, modify prod_1, write
  final resultA = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :id',
    arguments: {'id': cartId},
  );
  final itemsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['items'] as List,
  );
  itemsA[0]['quantity'] = 5; // Update prod_1

  // Simulate Device B: Read, modify prod_2, write
  final resultB = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :id',
    arguments: {'id': cartId},
  );
  final itemsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['items'] as List,
  );
  itemsB[1]['quantity'] = 3; // Update prod_2

  // Both devices write back
  await ditto.store.execute(
    'UPDATE carts SET items = :items WHERE _id = :id',
    arguments: {'id': cartId, 'items': itemsA},
  );
  await ditto.store.execute(
    'UPDATE carts SET items = :items WHERE _id = :id',
    arguments: {'id': cartId, 'items': itemsB},
  );

  // Result: Only Device B's changes survived (last-write-wins)
  // Device A's update to prod_1.quantity is LOST
  print('❌ Array approach: One device\'s changes lost due to last-write-wins');
}

/// Simulates concurrent updates with MAP (preserves changes)
Future<void> demonstrateConcurrentMapSuccess(Ditto ditto) async {
  const cartId = 'cart_conflict_demo_map';

  // Create cart with MAP
  await ditto.store.execute(
    'INSERT INTO carts (_id, userId, items) VALUES (:id, :userId, :items)',
    arguments: {
      'id': cartId,
      'userId': 'user_123',
      'items': {
        'prod_1': {'productId': 'prod_1', 'quantity': 1},
        'prod_2': {'productId': 'prod_2', 'quantity': 1},
      },
    },
  );

  // Device A: Update prod_1 directly
  await ditto.store.execute(
    'UPDATE carts SET items.prod_1.quantity = :qty WHERE _id = :id',
    arguments: {'id': cartId, 'qty': 5},
  );

  // Device B: Update prod_2 directly
  await ditto.store.execute(
    'UPDATE carts SET items.prod_2.quantity = :qty WHERE _id = :id',
    arguments: {'id': cartId, 'qty': 3},
  );

  // Result: BOTH updates preserved (field-level merge)
  // prod_1.quantity = 5 (from Device A)
  // prod_2.quantity = 3 (from Device B)
  print('✅ MAP approach: Both devices\' changes preserved via field-level merge');
}
