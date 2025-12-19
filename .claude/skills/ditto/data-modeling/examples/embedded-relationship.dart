// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// Embedded Relationships in Ditto
//
// This example demonstrates when and how to use embedded relationships
// (denormalized data structure) in Ditto.
//
// Related: Pattern 2 in data-modeling/SKILL.md
// See also: .claude/guides/best-practices/ditto.md#relationship-patterns

import 'package:ditto_sdk/ditto_sdk.dart';

// ✅ GOOD: Embedded relationships for tightly coupled data
//
// Use embedded when:
// - Data always queried together
// - Read-heavy workload
// - Atomic updates needed

class EmbeddedRelationshipExamples {
  final DittoContext ditto;

  EmbeddedRelationshipExamples(this.ditto);

  // Example 1: Vehicle with details (deep nesting)
  Future<void> createVehicleWithEmbeddedDetails() async {
    await ditto.store.execute(
      'INSERT INTO vehicles DOCUMENTS (:vehicle)',
      arguments: {
        'vehicle': {
          '_id': 'JTMDF4EV0FD100869',
          'make': 'Toyota',
          'model': 'RAV4',
          'year': 2015,
          // Embedded engine details (always displayed together)
          'details': {
            'engine': {
              'type': 'Gasoline',
              'displacement': '1.8L',
              'horsepower': 176,
              'cylinders': 4
            },
            'interior': {
              'seats': 5,
              'color': 'Black',
              'material': 'Leather'
            },
            'features': {
              'safety': {
                'airbags': 6,
                'antilockBrakes': true,
                'stabilityControl': true
              },
              'technology': {
                'infotainment': 'Touchscreen',
                'navigation': true,
                'bluetooth': true
              }
            }
          }
        }
      },
    );
  }

  // Single query returns complete vehicle data
  Future<void> queryVehicleWithDetails(String vin) async {
    final result = await ditto.store.execute(
      'SELECT * FROM vehicles WHERE _id = :vin',
      arguments: {'vin': vin},
    );

    if (result.items.isEmpty) return;

    final vehicle = result.items.first.value;
    print('Vehicle: ${vehicle['year']} ${vehicle['make']} ${vehicle['model']}');

    // All details available immediately (no additional queries)
    final engine = vehicle['details']['engine'];
    print('Engine: ${engine['type']}, ${engine['displacement']}, ${engine['horsepower']} HP');

    final interior = vehicle['details']['interior'];
    print('Interior: ${interior['seats']} seats, ${interior['color']} ${interior['material']}');
  }

  // Example 2: Order with embedded items and customer data
  Future<void> createOrderWithEmbeddedData() async {
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': 'order_123',
          // Embedded customer data (duplicated for quick access)
          'customerId': 'cust_456',  // Keep ID for reference
          'customerName': 'Alice Johnson',
          'customerEmail': 'alice@example.com',
          'customerPhone': '+1-555-0100',
          // Embedded order items (MAP structure, not array!)
          'items': {
            'item_1': {
              'productId': 'prod_1',
              'productName': 'Widget Pro',  // Duplicated for display
              'quantity': 2,
              'price': 99.99,
              'subtotal': 199.98
            },
            'item_2': {
              'productId': 'prod_2',
              'productName': 'Gadget Plus',
              'quantity': 1,
              'price': 49.99,
              'subtotal': 49.99
            }
          },
          'total': 249.97,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String()
        }
      },
    );
  }

  // Single query returns complete order with all details
  Future<void> queryOrderWithEmbeddedData(String orderId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :orderId',
      arguments: {'orderId': orderId},
    );

    if (result.items.isEmpty) return;

    final order = result.items.first.value;
    print('Order: ${order['_id']}');
    print('Customer: ${order['customerName']} (${order['customerEmail']})');
    print('Status: ${order['status']}, Total: \$${order['total']}');

    // All items available immediately
    final items = order['items'] as Map<String, dynamic>;
    print('Items:');
    for (final itemEntry in items.entries) {
      final item = itemEntry.value;
      print('- ${item['productName']}: ${item['quantity']} x \$${item['price']}');
    }
  }

  // Example 3: User profile with embedded preferences
  Future<void> createUserWithPreferences() async {
    await ditto.store.execute(
      'INSERT INTO users DOCUMENTS (:user)',
      arguments: {
        'user': {
          '_id': 'user_123',
          'name': 'Alice Johnson',
          'email': 'alice@example.com',
          // Embedded preferences (always loaded with user)
          'preferences': {
            'theme': 'dark',
            'language': 'en',
            'notifications': {
              'email': true,
              'push': false,
              'sms': false
            },
            'privacy': {
              'profileVisible': true,
              'activityTracking': false
            }
          }
        }
      },
    );
  }

  // Update nested field in embedded structure
  Future<void> updateUserPreference(String userId) async {
    await ditto.store.execute(
      'UPDATE users SET preferences.theme = :theme WHERE _id = :userId',
      arguments: {'theme': 'light', 'userId': userId},
    );
    // ✅ Field-level update preserves other preferences
  }

  // Example 4: Hybrid approach (best of both worlds)
  Future<void> createOrderWithHybridApproach() async {
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': 'order_456',
          'customerId': 'cust_789',  // ✅ Foreign key (for lookups)
          'customerName': 'Bob Smith',  // ✅ Embedded (for display)
          'customerEmail': 'bob@example.com',  // ✅ Embedded (for display)
          'items': {
            'item_1': {
              'productId': 'prod_1',  // ✅ Foreign key (for lookups)
              'productName': 'Widget',  // ✅ Embedded (for display)
              'quantity': 1,
              'priceAtOrder': 99.99  // ✅ Snapshot (historical accuracy)
            }
          },
          'total': 99.99,
          'status': 'pending'
        }
      },
    );
  }
}

// Trade-offs:
//
// ✅ Advantages:
// - Fast query performance (single query)
// - Simple application code (no manual joining)
// - Atomic updates (all related data updated together)
// - Better offline experience (all data local)
//
// ❌ Disadvantages:
// - Data duplication (customer name in every order)
// - Larger documents (can approach 250 KB limit)
// - Update complexity (must update all duplicates)
// - Stale data risk (duplicated data may become outdated)

// When to Use Embedded:
//
// ✅ Always queried together: Order items, vehicle details
// ✅ Read-heavy workload: Display data rarely changes
// ✅ Small related data: User preferences, settings
// ✅ Atomic updates needed: All-or-nothing consistency
// ✅ Historical accuracy: Price at order time, snapshot data
//
// ❌ Don't Use Embedded When:
// - Data grows unbounded (will exceed 250 KB limit)
// - Frequently updated independently (use foreign-key)
// - Large reference data (product catalogs)
// - High concurrent edits (causes CRDT conflicts)

// Hybrid Approach (Recommended):
//
// Combine embedded and foreign-key patterns:
// - Keep foreign key for lookups and updates
// - Embed frequently accessed data for display
// - Snapshot critical data for historical accuracy
//
// Example decision tree:
// - customerId: Foreign key (for customer updates)
// - customerName: Embedded (for quick display)
// - priceAtOrder: Embedded snapshot (historical accuracy)
// - productId: Foreign key (for product catalog updates)
// - productName: Embedded (for quick display)
//
// See also: foreign-key-relationship.dart for comparison
