// ✅ GOOD: Projection patterns for SELECT queries
// Demonstrates proper field selection, aliases, and calculated fields

import 'package:ditto/ditto.dart';

// ===================================================================
// PROJECTIONS: Field Selection Patterns
// ===================================================================

/// ✅ GOOD: Select only needed fields (reduces bandwidth)
Future<void> selectSpecificFields(Ditto ditto) async {
  // Select only 3 fields instead of all fields
  final result = await ditto.store.execute(
    'SELECT make, model, year FROM cars WHERE color = :color',
    arguments: {'color': 'blue'},
  );

  final cars = result.items.map((item) {
    final data = item.value;
    return {
      'make': data['make'],
      'model': data['model'],
      'year': data['year'],
    };
  }).toList();

  print('Found ${cars.length} blue cars');
}

/// ❌ BAD: SELECT * syncs unnecessary fields
Future<void> selectAllFieldsBad(Ditto ditto) async {
  // ❌ Problem: Syncs ALL fields (color, make, model, year, mileage, features, etc.)
  // even though we only use make, model, year
  final result = await ditto.store.execute(
    'SELECT * FROM cars WHERE color = :color',
    arguments: {'color': 'blue'},
  );

  // Only using 3 fields from the document
  final cars = result.items.map((item) {
    final data = item.value;
    return {
      'make': data['make'],
      'model': data['model'],
      'year': data['year'],
    };
  }).toList();

  // Wasted bandwidth syncing unused fields (features, mileage, etc.)
}

// ===================================================================
// CALCULATED FIELDS: Using Expressions and Aliases
// ===================================================================

/// ✅ GOOD: Calculated fields with aliases
Future<void> calculatedFieldsWithAliases(Ditto ditto) async {
  // Calculate discounted price in the query
  final result = await ditto.store.execute(
    'SELECT make, model, price, price * 0.9 AS discounted_price FROM cars WHERE inStock = true',
  );

  final discountedCars = result.items.map((item) {
    final data = item.value;
    return {
      'make': data['make'],
      'model': data['model'],
      'originalPrice': data['price'],
      'discountedPrice': data['discounted_price'], // Calculated in query
    };
  }).toList();

  print('Found ${discountedCars.length} cars with discounts');
}

/// ✅ GOOD: Readable aliases for clarity
Future<void> aliasesForReadability(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT
         make AS manufacturer,
         model AS car_model,
         year AS production_year
       FROM cars
       WHERE year >= :minYear''',
    arguments: {'minYear': 2020},
  );

  final recentCars = result.items.map((item) {
    final data = item.value;
    return {
      'manufacturer': data['manufacturer'], // Aliased field
      'car_model': data['car_model'], // Aliased field
      'production_year': data['production_year'], // Aliased field
    };
  }).toList();

  print('Recent cars: ${recentCars.length}');
}

// ===================================================================
// OBSERVER WITH PROJECTIONS
// ===================================================================

/// ✅ GOOD: Observer with specific field selection (reduces bandwidth)
void observerWithProjections(Ditto ditto) {
  // Flutter SDK v4.x: Use registerObserver (no signalNext)
  final observer = ditto.store.registerObserver(
    'SELECT temperature, humidity, timestamp FROM sensor_data WHERE deviceId = :deviceId',
    onChange: (result) {
      // Extract only the 3 fields we need
      final readings = result.items.map((item) {
        final data = item.value;
        return {
          'temperature': data['temperature'],
          'humidity': data['humidity'],
          'timestamp': data['timestamp'],
        };
      }).toList();

      print('Latest readings: ${readings.length}');
      // Update UI with readings
    },
    arguments: {'deviceId': 'sensor_123'},
  );

  // Cancel when done
  // observer.cancel();
}

/// ❌ BAD: Observer with SELECT * (wastes bandwidth)
void observerWithSelectAllBad(Ditto ditto) {
  // ❌ Problem: Syncs ALL sensor fields (battery, location, calibration, etc.)
  // even though we only use temperature and humidity
  final observer = ditto.store.registerObserver(
    'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
    onChange: (result) {
      // Only using 2 fields from the document
      final temps = result.items.map((item) {
        final data = item.value;
        return data['temperature'];
      }).toList();

      print('Temperatures: $temps');
      // Wasted bandwidth syncing unused fields (battery, location, etc.)
    },
    arguments: {'deviceId': 'sensor_123'},
  );
}

// ===================================================================
// MULTIPLE FIELD TYPES
// ===================================================================

/// ✅ GOOD: Selecting nested fields and arrays
Future<void> selectNestedFields(Ditto ditto) async {
  // Select nested fields explicitly
  final result = await ditto.store.execute(
    '''SELECT
         _id,
         location.city AS city,
         location.zipCode AS zipCode,
         customerName
       FROM orders
       WHERE status = :status''',
    arguments: {'status': 'pending'},
  );

  final orders = result.items.map((item) {
    final data = item.value;
    return {
      'orderId': data['_id'],
      'city': data['city'], // Aliased nested field
      'zipCode': data['zipCode'], // Aliased nested field
      'customerName': data['customerName'],
    };
  }).toList();

  print('Pending orders: ${orders.length}');
}

// ===================================================================
// PROJECTION PERFORMANCE COMPARISON
// ===================================================================

/// ✅ GOOD: Performance comparison showing bandwidth savings
Future<void> projectionPerformanceDemo(Ditto ditto) async {
  // Scenario: Fetch 1000 products

  // ❌ BAD: SELECT * (assume 50 fields, 2KB per document)
  // Total: 1000 docs × 2KB = 2MB bandwidth
  final allFieldsResult = await ditto.store.execute(
    'SELECT * FROM products WHERE category = :category LIMIT 1000',
    arguments: {'category': 'electronics'},
  );
  print('SELECT * returned ${allFieldsResult.items.length} products (~2MB bandwidth)');

  // ✅ GOOD: Select only 5 fields (0.2KB per document)
  // Total: 1000 docs × 0.2KB = 200KB bandwidth (10x improvement!)
  final specificFieldsResult = await ditto.store.execute(
    '''SELECT _id, name, price, category, inStock
       FROM products
       WHERE category = :category
       LIMIT 1000''',
    arguments: {'category': 'electronics'},
  );
  print('Specific fields returned ${specificFieldsResult.items.length} products (~200KB bandwidth)');
  print('Bandwidth savings: 90% reduction');
}

// ===================================================================
// COMMON PATTERNS
// ===================================================================

/// ✅ GOOD: Listing pattern (fetch IDs and names only)
Future<List<Map<String, dynamic>>> fetchProductList(Ditto ditto, String category) async {
  // Only fetch fields needed for list view
  final result = await ditto.store.execute(
    'SELECT _id, name, price, thumbnail FROM products WHERE category = :category',
    arguments: {'category': category},
  );

  return result.items.map((item) {
    final data = item.value;
    return {
      'id': data['_id'],
      'name': data['name'],
      'price': data['price'],
      'thumbnail': data['thumbnail'],
    };
  }).toList();
}

/// ✅ GOOD: Detail view (fetch all fields for single document)
Future<Map<String, dynamic>?> fetchProductDetails(Ditto ditto, String productId) async {
  // Detail view needs all fields - SELECT * is acceptable here
  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE _id = :id LIMIT 1',
    arguments: {'id': productId},
  );

  if (result.items.isEmpty) return null;

  return result.items.first.value;
}

// ===================================================================
// KEY TAKEAWAYS
// ===================================================================

/*
✅ DO:
- Select only the fields you need (reduces bandwidth and sync traffic)
- Use aliases for calculated fields and readability
- Use projections in observers to minimize real-time sync overhead
- SELECT * is acceptable for single-document detail views

❌ DON'T:
- Use SELECT * when you only need specific fields
- Sync unnecessary fields in high-frequency observers
- Retrieve large nested objects when you only need a few fields

WHY:
- In P2P mesh networks, every field syncs across all peers
- Bluetooth LE max ~20 KB/s - unnecessary fields cause significant delays
- 10x bandwidth reduction possible with proper projections

SEE ALSO:
- .claude/guides/best-practices/ditto.md#projections-field-selection
- .claude/guides/best-practices/ditto.md#exclude-unnecessary-fields-from-documents
*/
