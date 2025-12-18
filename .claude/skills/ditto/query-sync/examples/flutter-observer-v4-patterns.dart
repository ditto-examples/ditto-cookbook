// ============================================================================
// Flutter SDK v4.x Observer Patterns
// ============================================================================
//
// This example demonstrates proper observer usage in Flutter SDK v4.14.0 and earlier.
//
// CRITICAL: Flutter SDK v4.x does NOT support registerObserverWithSignalNext.
// Only registerObserver (without signalNext) is available.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Basic registerObserver usage (Flutter v4.x)
// 2. ✅ Flutter widget integration with setState
// 3. ✅ Riverpod integration pattern
// 4. ✅ Lightweight callback pattern
// 5. ✅ Performance considerations (no backpressure control)
// 6. ℹ️ Migration notes for v5.0
//
// WHY THIS MATTERS:
// - Flutter SDK v4.14.0 ONLY has registerObserver
// - No signalNext parameter (no manual backpressure control)
// - Callbacks fire for EVERY data change
// - Must keep callbacks lightweight to avoid performance issues
// - Flutter SDK v5.0 will add registerObserverWithSignalNext
//
// OFFICIAL DOCS:
// Flutter SDK Store API: https://pub.dev/documentation/ditto_live/latest/ditto_live/Store-class.html
// Methods: registerObserver (exists), registerObserverWithSignalNext (does NOT exist in v4.x)
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// PATTERN 1: Basic registerObserver Usage (Flutter SDK v4.x)
// ============================================================================

/// ✅ GOOD: Proper registerObserver usage in Flutter SDK v4.x
class BasicObserverExample {
  final Ditto ditto;
  DittoStoreObserver? observer;

  BasicObserverExample(this.ditto);

  void startObserving() {
    print('📡 Starting observer (Flutter SDK v4.x - no signalNext)\\n');

    // ✅ Flutter SDK v4.14.0: Use registerObserver (only available method)
    observer = ditto.store.registerObserver(
      'SELECT * FROM products WHERE category = :category',
      onChange: (result) {
        // ⚠️ No signalNext parameter in Flutter SDK v4.x
        // Callbacks fire automatically for every change

        print('  📦 Observer callback fired');
        print('  📊 Products count: ${result.items.length}');

        // Extract data immediately (lightweight operation)
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // Update UI or state
        print('  ✅ Extracted ${products.length} products\\n');

        // Note: No backpressure control available in Flutter v4.x
        // Callback will fire again for next change automatically
      },
      arguments: {'category': 'electronics'},
    );

    print('✅ Observer registered successfully\\n');
  }

  void stopObserving() {
    observer?.cancel();
    print('🛑 Observer canceled\\n');
  }
}

// ============================================================================
// PATTERN 2: Flutter Widget Integration with setState
// ============================================================================

/// ✅ GOOD: Observer integrated with Flutter StatefulWidget
class ProductListWidget extends StatefulWidget {
  final Ditto ditto;

  const ProductListWidget({Key? key, required this.ditto}) : super(key: key);

  @override
  State<ProductListWidget> createState() => _ProductListWidgetState();
}

class _ProductListWidgetState extends State<ProductListWidget> {
  DittoStoreObserver? _observer;
  List<Product> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _startObserving();
  }

  void _startObserving() {
    print('🎨 Setting up observer in Flutter widget\\n');

    // ✅ Flutter SDK v4.x: Use registerObserver
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM products WHERE inStock = true',
      onChange: (result) {
        // ⚠️ No signalNext parameter in Flutter SDK v4.x

        print('  🔄 Data changed, updating UI');

        // Extract data immediately
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // Update widget state (triggers rebuild)
        if (mounted) {
          setState(() {
            _products = products;
            _isLoading = false;
          });
        }

        print('  ✅ UI updated with ${products.length} products\\n');

        // No signalNext() call needed - callbacks fire automatically
      },
    );

    print('✅ Widget observer registered\\n');
  }

  @override
  void dispose() {
    print('🧹 Disposing widget, canceling observer\\n');
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        return ListTile(
          title: Text(product.name),
          subtitle: Text('\$${product.price}'),
        );
      },
    );
  }
}

// ============================================================================
// PATTERN 3: Riverpod Integration Pattern
// ============================================================================

/// ✅ GOOD: Observer with Riverpod StateNotifier (Flutter v4.x)
class ProductsNotifier extends StateNotifier<List<Product>> {
  final Ditto ditto;
  DittoStoreObserver? _observer;

  ProductsNotifier(this.ditto) : super([]) {
    _startObserving();
  }

  void _startObserving() {
    print('🎯 Setting up observer with Riverpod StateNotifier\\n');

    // ✅ Flutter SDK v4.x: Use registerObserver
    _observer = ditto.store.registerObserver(
      'SELECT * FROM products ORDER BY name ASC',
      onChange: (result) {
        // No signalNext parameter in Flutter SDK v4.x

        print('  🔄 Data changed, updating Riverpod state');

        // Extract data immediately
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // Update Riverpod state (triggers listener rebuilds)
        state = products;

        print('  ✅ Riverpod state updated with ${products.length} products\\n');
      },
    );

    print('✅ Riverpod observer registered\\n');
  }

  @override
  void dispose() {
    print('🧹 Disposing StateNotifier, canceling observer\\n');
    _observer?.cancel();
    super.dispose();
  }
}

// Riverpod provider
final productsProvider =
    StateNotifierProvider<ProductsNotifier, List<Product>>((ref) {
  final ditto = ref.watch(dittoProvider);
  return ProductsNotifier(ditto);
});

// Example Ditto provider (simplified)
final dittoProvider = Provider<Ditto>((ref) {
  throw UnimplementedError('Provide your Ditto instance');
});

// Widget consuming Riverpod provider
class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ListTile(
            title: Text(product.name),
            subtitle: Text('\$${product.price}'),
          );
        },
      ),
    );
  }
}

// ============================================================================
// PATTERN 4: Lightweight Callback Pattern
// ============================================================================

/// ✅ GOOD: Keeping observer callbacks lightweight (Flutter v4.x)
class LightweightObserverExample {
  final Ditto ditto;
  DittoStoreObserver? observer;

  LightweightObserverExample(this.ditto);

  void startObserving() {
    print('⚡ Setting up lightweight observer (Flutter SDK v4.x)\\n');

    observer = ditto.store.registerObserver(
      'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
      onChange: (result) {
        // ⚠️ No signalNext parameter in Flutter SDK v4.x
        // Callbacks fire for EVERY change - keep lightweight!

        print('  📊 Sensor data update received');

        // ✅ Extract data immediately (lightweight)
        final sensorData = result.items
            .map((item) => item.value)
            .toList();

        print('  📈 Received ${sensorData.length} sensor readings');

        // ✅ Update UI immediately (lightweight)
        _updateUI(sensorData);

        // ✅ Offload heavy processing to background
        _processSensorDataAsync(sensorData);

        print('  ✅ Callback completed quickly\\n');

        // No signalNext() available - callback will fire again automatically
      },
      arguments: {'deviceId': 'sensor_123'},
    );

    print('✅ Lightweight observer registered\\n');
  }

  void _updateUI(List<Map<String, dynamic>> data) {
    // Lightweight UI update
    print('    🎨 UI updated');
  }

  Future<void> _processSensorDataAsync(List<Map<String, dynamic>> data) async {
    // Heavy processing runs in background, doesn't block observer
    print('    ⚙️ Background processing started');
    // Simulate heavy processing
    await Future.delayed(Duration(milliseconds: 100));
    print('    ✅ Background processing completed');
  }

  void stopObserving() {
    observer?.cancel();
    print('🛑 Lightweight observer canceled\\n');
  }
}

// ============================================================================
// PATTERN 5: Performance Considerations (No Backpressure Control)
// ============================================================================

/// ⚠️ Important: Performance implications in Flutter SDK v4.x
class PerformanceConsiderationsExample {
  final Ditto ditto;
  DittoStoreObserver? observer;

  PerformanceConsiderationsExample(this.ditto);

  void demonstratePerformanceConsiderations() {
    print('⚠️ Performance Considerations (Flutter SDK v4.x)\\n');

    observer = ditto.store.registerObserver(
      'SELECT * FROM high_frequency_data',
      onChange: (result) {
        // ⚠️ No signalNext parameter = No backpressure control

        print('  📊 Callback fired (no way to pause)');

        // In high-frequency scenarios (e.g., IoT sensors updating multiple times per second):
        // - Callbacks fire for EVERY change
        // - No way to pause/throttle updates
        // - Must keep callbacks VERY lightweight
        // - Heavy processing → callback accumulation → performance issues

        // ✅ Best Practices for Flutter SDK v4.x:
        // 1. Extract data immediately (always lightweight)
        final data = result.items.map((item) => item.value).toList();

        // 2. Update UI immediately (keep lightweight)
        _quickUIUpdate(data);

        // 3. Offload ALL heavy processing to background
        _heavyProcessingAsync(data); // Non-blocking

        print('  ✅ Callback completed quickly\\n');

        // ⚠️ Without signalNext, callbacks will keep firing
        // Solution: Keep callbacks < 16ms to maintain 60 FPS
      },
    );

    print('✅ Performance-aware observer registered\\n');
    print('📌 Remember: Flutter SDK v4.x has no backpressure control\\n');
    print('📌 Keep callbacks lightweight (<16ms for 60 FPS)\\n');
  }

  void _quickUIUpdate(List<Map<String, dynamic>> data) {
    // Lightweight UI update
    print('    🎨 Quick UI update');
  }

  Future<void> _heavyProcessingAsync(List<Map<String, dynamic>> data) async {
    // Heavy processing runs independently
    // Does not block observer callbacks
    await Future.delayed(Duration(milliseconds: 100));
    print('    ⚙️ Heavy processing completed in background');
  }

  void stopObserving() {
    observer?.cancel();
  }
}

// ============================================================================
// MIGRATION NOTES: Preparing for Flutter SDK v5.0
// ============================================================================

/// ℹ️ Migration notes for Flutter SDK v5.0
class MigrationNotes {
  static void printMigrationGuidance() {
    print('═══════════════════════════════════════════════════════════════════');
    print('MIGRATION NOTES: Flutter SDK v4.x → v5.0');
    print('═══════════════════════════════════════════════════════════════════\\n');

    print('📌 Current State (Flutter SDK v4.14.0):');
    print('   - Only registerObserver available');
    print('   - No signalNext parameter');
    print('   - No manual backpressure control');
    print('   - Callbacks fire automatically for every change\\n');

    print('🎉 Future State (Flutter SDK v5.0):');
    print('   - registerObserverWithSignalNext will be available');
    print('   - Manual backpressure control via signalNext()');
    print('   - Can pause observer updates');
    print('   - Better performance for high-frequency scenarios\\n');

    print('🔧 Migration Path:');
    print('   1. Current code using registerObserver will continue to work');
    print('   2. When v5.0 is available, optionally migrate to:');
    print('      - registerObserverWithSignalNext for better performance');
    print('      - Add signalNext() calls to control update timing');
    print('      - Use WidgetsBinding.addPostFrameCallback for signalNext\\n');

    print('📝 Example Migration:');
    print('   // Flutter SDK v4.x (current)');
    print('   observer = ditto.store.registerObserver(');
    print('     query,');
    print('     onChange: (result) {');
    print('       updateUI(result.items);');
    print('     },');
    print('   );\\n');

    print('   // Flutter SDK v5.0+ (future)');
    print('   observer = ditto.store.registerObserverWithSignalNext(');
    print('     query,');
    print('     onChange: (result, signalNext) {');
    print('       updateUI(result.items);');
    print('       WidgetsBinding.instance.addPostFrameCallback((_) {');
    print('         signalNext();');
    print('       });');
    print('     },');
    print('   );\\n');

    print('═══════════════════════════════════════════════════════════════════\\n');
  }
}

// ============================================================================
// Example Model
// ============================================================================

class Product {
  final String id;
  final String name;
  final double price;
  final bool inStock;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.inStock,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      inStock: json['inStock'] as bool? ?? true,
    );
  }
}

// ============================================================================
// Main Example
// ============================================================================

void main() async {
  print('═══════════════════════════════════════════════════════════════════\\n');
  print('Flutter SDK v4.x Observer Patterns - Best Practices\\n');
  print('═══════════════════════════════════════════════════════════════════\\n\\n');

  // Initialize Ditto (simplified)
  final ditto = await Ditto.open(
    identity: DittoIdentity.onlinePlayground(
      appID: 'your-app-id',
      token: 'your-token',
    ),
    persistenceDirectory: '/tmp/ditto',
  );

  // Pattern 1: Basic Observer
  print('PATTERN 1: Basic registerObserver Usage');
  print('─────────────────────────────────────────\\n');
  final basic = BasicObserverExample(ditto);
  basic.startObserving();
  await Future.delayed(Duration(seconds: 1));
  basic.stopObserving();

  // Pattern 4: Lightweight Callback
  print('\\nPATTERN 4: Lightweight Callback Pattern');
  print('─────────────────────────────────────────\\n');
  final lightweight = LightweightObserverExample(ditto);
  lightweight.startObserving();
  await Future.delayed(Duration(seconds: 1));
  lightweight.stopObserving();

  // Pattern 5: Performance Considerations
  print('\\nPATTERN 5: Performance Considerations');
  print('─────────────────────────────────────────\\n');
  final performance = PerformanceConsiderationsExample(ditto);
  performance.demonstratePerformanceConsiderations();
  await Future.delayed(Duration(seconds: 1));
  performance.stopObserving();

  // Migration Notes
  print('\\n');
  MigrationNotes.printMigrationGuidance();

  // Cleanup
  await ditto.close();

  print('\\n═══════════════════════════════════════════════════════════════════');
  print('KEY TAKEAWAYS:');
  print('═══════════════════════════════════════════════════════════════════');
  print('1. ✅ Flutter SDK v4.x: Use registerObserver (only option)');
  print('2. ⚠️  No signalNext parameter (no backpressure control)');
  print('3. ✅ Keep callbacks lightweight (<16ms for 60 FPS)');
  print('4. ✅ Offload heavy processing to background async tasks');
  print('5. ✅ Extract data immediately from QueryResultItems');
  print('6. 🎉 Flutter SDK v5.0: Will add registerObserverWithSignalNext');
  print('═══════════════════════════════════════════════════════════════════\\n');
}
