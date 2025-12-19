// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// Foreign-Key Relationships in Ditto
//
// This example demonstrates when and how to use foreign-key relationships
// (normalized data structure) in Ditto.
//
// Related: Pattern 2 in data-modeling/SKILL.md
// See also: .claude/guides/best-practices/ditto.md#relationship-patterns

import 'package:ditto_sdk/ditto_sdk.dart';

// ✅ GOOD: Foreign-key relationships for independent entities
//
// Use foreign-key when:
// - Independent lifecycles (entities updated separately)
// - Large reference data (product catalogs, configuration tables)
// - Separate access patterns (data accessed independently)

class ForeignKeyExamples {
  final DittoContext ditto;

  ForeignKeyExamples(this.ditto);

  // Example 1: Cars and Owners (Independent Lifecycles)
  Future<void> createCarAndOwner() async {
    // Create owner document (separate lifecycle)
    await ditto.store.execute(
      'INSERT INTO owners DOCUMENTS (:owner)',
      arguments: {
        'owner': {
          '_id': '5da42ab5-d00b-4377-8524-43e43abf9e01',
          'name': 'John Doe',
          'email': 'john@example.com',
          'phone': '+1-555-0100'
        }
      },
    );

    // Create car document with foreign key to owner
    await ditto.store.execute(
      'INSERT INTO cars DOCUMENTS (:car)',
      arguments: {
        'car': {
          '_id': '0016d749-9a9b-4ece-8794-7f3eb40bc82e',
          'owner_id': '5da42ab5-d00b-4377-8524-43e43abf9e01', // Foreign key
          'make': 'Toyota',
          'model': 'RAV4',
          'year': 2015,
          'vin': 'JTMDF4EV0FD100869'
        }
      },
    );
  }

  // Query requires 2 steps (no JOIN support in Ditto)
  Future<void> queryCarWithOwner(String carId) async {
    // Step 1: Query car
    final carResult = await ditto.store.execute(
      'SELECT * FROM cars WHERE _id = :carId',
      arguments: {'carId': carId},
    );

    if (carResult.items.isEmpty) {
      print('Car not found');
      return;
    }

    final car = carResult.items.first.value;
    print('Car: ${car['make']} ${car['model']}');

    // Step 2: Query owner using foreign key
    final ownerId = car['owner_id'];
    final ownerResult = await ditto.store.execute(
      'SELECT * FROM owners WHERE _id = :ownerId',
      arguments: {'ownerId': ownerId},
    );

    if (ownerResult.items.isNotEmpty) {
      final owner = ownerResult.items.first.value;
      print('Owner: ${owner['name']} (${owner['email']})');
    }
  }

  // Example 2: Update owner without affecting cars
  Future<void> updateOwnerInfo(String ownerId, String newEmail) async {
    await ditto.store.execute(
      'UPDATE owners SET email = :email WHERE _id = :ownerId',
      arguments: {'email': newEmail, 'ownerId': ownerId},
    );
    // ✅ Owner update doesn't affect car documents (independent update)
  }

  // Example 3: Query all cars for an owner
  Future<void> queryCarsForOwner(String ownerId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM cars WHERE owner_id = :ownerId',
      arguments: {'ownerId': ownerId},
    );

    print('Owner has ${result.items.length} cars:');
    for (final item in result.items) {
      final car = item.value;
      print('- ${car['make']} ${car['model']} (${car['year']})');
    }
  }

  // Example 4: Product catalog (large reference data)
  Future<void> createProductCatalog() async {
    // Products collection (updated independently)
    await ditto.store.execute(
      'INSERT INTO products DOCUMENTS (:product)',
      arguments: {
        'product': {
          '_id': 'prod_1',
          'name': 'Widget Pro',
          'description': 'Professional widget for enterprise use',
          'price': 99.99,
          'category': 'electronics',
          'specifications': {
            'weight': '1.2 kg',
            'dimensions': '10x10x5 cm'
          }
        }
      },
    );
  }

  // Orders reference products by ID (foreign key)
  Future<void> createOrderWithProductReferences() async {
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': 'order_123',
          'customerId': 'cust_456',
          'items': {
            'item_1': {
              'productId': 'prod_1',  // Foreign key to products
              'quantity': 2,
              'priceAtOrder': 99.99  // Snapshot price at order time
            }
          },
          'total': 199.98,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String()
        }
      },
    );
  }

  // Query order with product details
  Future<void> queryOrderWithProducts(String orderId) async {
    final orderResult = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      arguments: {'orderId': orderId},
    );

    if (orderResult.items.isEmpty) return;

    final order = orderResult.items.first.value;
    final items = order['items'] as Map<String, dynamic>;

    print('Order: ${order['_id']}');
    for (final itemEntry in items.entries) {
      final item = itemEntry.value;
      final productId = item['productId'];

      // Query product details
      final productResult = await ditto.store.execute(
        'SELECT * FROM products WHERE _id = :productId',
        arguments: {'productId': productId},
      );

      if (productResult.items.isNotEmpty) {
        final product = productResult.items.first.value;
        print('- ${product['name']}: ${item['quantity']} x \$${item['priceAtOrder']}');
      }
    }
  }
}

// Trade-offs:
//
// ✅ Advantages:
// - No data duplication (single source of truth)
// - Independent updates (owner changes don't affect cars)
// - Separate lifecycle management (delete owner, keep cars)
// - Parallel sync efficiency (sync cars and owners separately)
//
// ❌ Disadvantages:
// - Multiple sequential queries (no JOIN support)
// - Manual joining in application code
// - Performance overhead (network round trips)
// - More complex error handling (missing references)

// When to Use Foreign-Key:
//
// ✅ Independent lifecycles: Users vs orders, products vs inventory
// ✅ Large reference data: Product catalogs, configuration tables
// ✅ Separate access patterns: Data accessed independently most of the time
// ✅ Frequent independent updates: Owner info changes often, cars rarely
//
// ❌ Don't Use Foreign-Key When:
// - Data always queried together (use embedded instead)
// - Read-heavy workload (denormalization is faster)
// - Small related data (embedding is simpler)

// Best Practice: Hybrid Approach
//
// Combine foreign-key with embedded data:
// - Keep foreign key for lookups and updates
// - Embed frequently accessed data for display
//
// Example:
// {
//   "_id": "order_123",
//   "customerId": "cust_456",      // Foreign key (for lookups)
//   "customerName": "Alice",       // Embedded (for display)
//   "customerEmail": "alice@...",  // Embedded (for display)
//   "items": {...}
// }
//
// See also: embedded-relationship.dart for comparison
