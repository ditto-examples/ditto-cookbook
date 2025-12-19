// SDK Version: All
// Platform: Flutter
// Last Updated: 2025-12-19
//
// ============================================================================
// Flutter SDK v4.x Observer Performance Patterns
// ============================================================================
//
// This example demonstrates performance optimization patterns for Flutter SDK v4.14.0 and earlier.
//
// CRITICAL: Flutter SDK v4.x does NOT support signalNext (no backpressure control).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Keeping callbacks lightweight
// 2. ✅ Partial UI updates with Riverpod
// 3. ✅ Avoiding full screen rebuilds
// 4. ℹ️ Performance comparison: v4.x vs v5.0 (planned)
// 5. ℹ️ Migration preparation for v5.0
//
// WHY THIS MATTERS:
// - Flutter SDK v4.x has NO backpressure control
// - Callbacks fire for EVERY data change
// - Must keep callbacks extremely lightweight
// - Heavy processing → callback accumulation → performance degradation
// - Flutter SDK v5.0 will add signalNext for better control
//
// PERFORMANCE TARGETS:
// - Observer callbacks: < 16ms (60 FPS)
// - Extract data: < 1ms
// - UI updates: Partial rebuilds only
// - Heavy processing: Offloaded to background
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// PATTERN 1: Lightweight Callback (< 16ms Target)
// ============================================================================

/// ✅ GOOD: Extremely lightweight observer callback
class LightweightCallbackExample {
  final Ditto ditto;
  DittoStoreObserver? observer;
  int callbackCount = 0;

  LightweightCallbackExample(this.ditto);

  void startObserving() {
    print('⚡ Starting lightweight observer (Flutter SDK v4.x)\\n');

    final stopwatch = Stopwatch();

    observer = ditto.store.registerObserver(
      'SELECT * FROM products WHERE category = :category',
      onChange: (result) {
        stopwatch.reset();
        stopwatch.start();

        callbackCount++;
        print('  📊 Callback #$callbackCount fired');

        // ✅ Extract data immediately (< 1ms)
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // ✅ Update UI immediately (< 5ms)
        _updateUI(products);

        // ✅ Offload heavy processing to background
        _processInBackground(products);

        stopwatch.stop();
        final elapsed = stopwatch.elapsedMicroseconds / 1000; // Convert to ms

        print('  ⏱️  Callback completed in ${elapsed.toStringAsFixed(2)}ms');

        // Performance check
        if (elapsed > 16) {
          print('  ⚠️  WARNING: Callback took > 16ms (target for 60 FPS)');
        } else {
          print('  ✅ Good: Callback under 16ms target');
        }

        print('');

        // Note: No signalNext() available in Flutter v4.x
        // Callback will fire again automatically for next change
      },
      arguments: {'category': 'electronics'},
    );

    print('✅ Lightweight observer registered\\n');
  }

  void _updateUI(List<Product> products) {
    // Simulate lightweight UI update
    // In real app: setState(), Riverpod state update, etc.
    print('    🎨 UI updated (lightweight)');
  }

  Future<void> _processInBackground(List<Product> products) async {
    // Heavy processing runs independently
    // Does not block observer callback
    await Future.delayed(Duration(milliseconds: 50));
    print('    ⚙️  Background processing completed');
  }

  void stopObserving() {
    observer?.cancel();
    print('🛑 Lightweight observer stopped');
    print('📊 Total callbacks fired: $callbackCount\\n');
  }
}

// ============================================================================
// PATTERN 2: Partial UI Updates with Riverpod
// ============================================================================

/// ✅ GOOD: Granular rebuilds with Riverpod (Flutter SDK v4.x)
class Product {
  final String id;
  final String name;
  final double price;
  final int stock;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      stock: json['stock'] as int? ?? 0,
    );
  }
}

// ✅ State Notifier with granular updates
class ProductsNotifier extends StateNotifier<Map<String, Product>> {
  final Ditto ditto;
  DittoStoreObserver? _observer;

  ProductsNotifier(this.ditto) : super({}) {
    _startObserving();
  }

  void _startObserving() {
    print('🎯 Setting up Riverpod observer (Flutter SDK v4.x)\\n');

    _observer = ditto.store.registerObserver(
      'SELECT * FROM products',
      onChange: (result) {
        // No signalNext parameter in Flutter SDK v4.x

        print('  🔄 Products changed, updating Riverpod state');

        // Extract data immediately
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // Update state (Map for granular access)
        state = {
          for (var product in products) product.id: product,
        };

        print('  ✅ Riverpod state updated with ${products.length} products');
        print('');

        // Riverpod will trigger rebuilds only for widgets watching specific products
      },
    );

    print('✅ Riverpod observer registered\\n');
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }
}

// Riverpod providers
final dittoProvider = Provider<Ditto>((ref) {
  throw UnimplementedError('Provide your Ditto instance');
});

final productsProvider =
    StateNotifierProvider<ProductsNotifier, Map<String, Product>>((ref) {
  final ditto = ref.watch(dittoProvider);
  return ProductsNotifier(ditto);
});

// ✅ Granular product provider (only rebuilds when specific product changes)
final productProvider = Provider.family<Product?, String>((ref, productId) {
  final productsMap = ref.watch(productsProvider);
  return productsMap[productId];
});

// ✅ Widget that only rebuilds when its specific product changes
class ProductCard extends ConsumerWidget {
  final String productId;

  const ProductCard({Key? key, required this.productId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Only watches this specific product
    final product = ref.watch(productProvider(productId));

    if (product == null) {
      return const SizedBox.shrink();
    }

    print('  🔨 Rebuilding ProductCard for: ${product.name}');

    return Card(
      child: ListTile(
        title: Text(product.name),
        subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
        trailing: Text('Stock: ${product.stock}'),
      ),
    );
  }
}

// ✅ Product list that uses granular rebuilds
class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsMap = ref.watch(productsProvider);
    final productIds = productsMap.keys.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: ListView.builder(
        itemCount: productIds.length,
        itemBuilder: (context, index) {
          // ✅ Each ProductCard rebuilds independently
          return ProductCard(productId: productIds[index]);
        },
      ),
    );
  }
}

// ============================================================================
// PATTERN 3: Avoiding Full Screen Rebuilds
// ============================================================================

/// ❌ BAD: Full screen rebuild in observer callback
class BadFullScreenRebuildExample extends StatefulWidget {
  final Ditto ditto;

  const BadFullScreenRebuildExample({Key? key, required this.ditto})
      : super(key: key);

  @override
  State<BadFullScreenRebuildExample> createState() =>
      _BadFullScreenRebuildExampleState();
}

class _BadFullScreenRebuildExampleState
    extends State<BadFullScreenRebuildExample> {
  DittoStoreObserver? _observer;
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();

    // ❌ BAD: Calling setState on entire screen
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM products',
      onChange: (result) {
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // ❌ BAD: Triggers rebuild of ENTIRE screen
        setState(() {
          _products = products;
        });

        // Problem: Every widget in this screen rebuilds, even if unchanged
        // Performance impact: Wasted CPU cycles, dropped frames
      },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ❌ Entire screen rebuilds on every observer callback
    return Scaffold(
      appBar: AppBar(title: const Text('Products')), // Rebuilds unnecessarily
      body: Column(
        children: [
          // All these widgets rebuild unnecessarily
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Static Header'), // Rebuilds unnecessarily!
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _products.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_products[index].name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ GOOD: Scoped rebuild using ValueListenableBuilder
class GoodScopedRebuildExample extends StatefulWidget {
  final Ditto ditto;

  const GoodScopedRebuildExample({Key? key, required this.ditto})
      : super(key: key);

  @override
  State<GoodScopedRebuildExample> createState() =>
      _GoodScopedRebuildExampleState();
}

class _GoodScopedRebuildExampleState extends State<GoodScopedRebuildExample> {
  DittoStoreObserver? _observer;
  final ValueNotifier<List<Product>> _productsNotifier = ValueNotifier([]);

  @override
  void initState() {
    super.initState();

    // ✅ GOOD: Update ValueNotifier, not setState
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM products',
      onChange: (result) {
        final products = result.items
            .map((item) => Product.fromJson(item.value))
            .toList();

        // ✅ GOOD: Only updates ValueNotifier
        _productsNotifier.value = products;

        // Only widgets listening to this notifier will rebuild
      },
    );
  }

  @override
  void dispose() {
    _observer?.cancel();
    _productsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ This build() only runs once, not on every observer callback
    return Scaffold(
      appBar: AppBar(title: const Text('Products')), // ✅ Never rebuilds
      body: Column(
        children: [
          // ✅ Static widget - never rebuilds
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Static Header'),
          ),
          // ✅ Only this part rebuilds when products change
          Expanded(
            child: ValueListenableBuilder<List<Product>>(
              valueListenable: _productsNotifier,
              builder: (context, products, child) {
                return ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(products[index].name),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PATTERN 4: Performance Comparison (v4.x vs v5.0 Planned)
// ============================================================================

/// ℹ️ Performance comparison notes
class PerformanceComparison {
  static void printComparison() {
    print('═══════════════════════════════════════════════════════════════════');
    print('PERFORMANCE COMPARISON: Flutter SDK v4.x vs v5.0 (Planned)');
    print('═══════════════════════════════════════════════════════════════════\\n');

    print('📊 Flutter SDK v4.x (Current):');
    print('   - registerObserver only');
    print('   - No backpressure control');
    print('   - Callbacks fire for EVERY change');
    print('   - Target: < 16ms per callback for 60 FPS');
    print('   - Risk: Callback accumulation in high-frequency scenarios\\n');

    print('🎯 Performance Strategies for v4.x:');
    print('   1. Extract data immediately (< 1ms)');
    print('   2. Update UI with scoped rebuilds (< 5ms)');
    print('   3. Offload all heavy processing to background');
    print('   4. Use Riverpod for granular updates');
    print('   5. Avoid full screen setState()\\n');

    print('🎉 Flutter SDK v5.0 (Planned):');
    print('   - registerObserverWithSignalNext available');
    print('   - Manual backpressure control via signalNext()');
    print('   - Can pause updates during heavy processing');
    print('   - Better performance in high-frequency scenarios');
    print('   - Callback queue control\\n');

    print('🔧 Migration Benefits (v4.x → v5.0):');
    print('   - Opt-in to signalNext for high-frequency data');
    print('   - Existing registerObserver code continues to work');
    print('   - Better control over callback timing');
    print('   - Reduced risk of callback accumulation\\n');

    print('═══════════════════════════════════════════════════════════════════\\n');
  }
}

// ============================================================================
// PATTERN 5: Migration Preparation for v5.0
// ============================================================================

/// ℹ️ Preparing your code for Flutter SDK v5.0
class MigrationPreparation {
  static void printMigrationGuide() {
    print('═══════════════════════════════════════════════════════════════════');
    print('MIGRATION PREPARATION: Flutter SDK v4.x → v5.0');
    print('═══════════════════════════════════════════════════════════════════\\n');

    print('✅ Current Best Practices (v4.x):');
    print('   1. Keep observer callbacks < 16ms');
    print('   2. Use Riverpod or ValueListenableBuilder for scoped rebuilds');
    print('   3. Offload heavy processing to background');
    print('   4. Extract data immediately from QueryResultItems\\n');

    print('🎯 These patterns will continue to work in v5.0!\\n');

    print('🎉 Optional Enhancements in v5.0:');
    print('   1. Add signalNext() for backpressure control');
    print('   2. Use WidgetsBinding.addPostFrameCallback for timing');
    print('   3. Opt-in to registerObserverWithSignalNext for high-frequency data\\n');

    print('📝 Example Migration Path:\\n');

    print('   // v4.x code (will continue to work)');
    print('   observer = ditto.store.registerObserver(');
    print('     query,');
    print('     onChange: (result) {');
    print('       final data = result.items.map((i) => i.value).toList();');
    print('       updateUI(data);');
    print('     },');
    print('   );\\n');

    print('   // v5.0 enhancement (optional, for high-frequency scenarios)');
    print('   observer = ditto.store.registerObserverWithSignalNext(');
    print('     query,');
    print('     onChange: (result, signalNext) {');
    print('       final data = result.items.map((i) => i.value).toList();');
    print('       updateUI(data);');
    print('       WidgetsBinding.instance.addPostFrameCallback((_) {');
    print('         signalNext(); // Control timing');
    print('       });');
    print('     },');
    print('   );\\n');

    print('═══════════════════════════════════════════════════════════════════\\n');
  }
}

// ============================================================================
// Main Example
// ============================================================================

void main() async {
  print('═══════════════════════════════════════════════════════════════════\\n');
  print('Flutter SDK v4.x Observer Performance - Best Practices\\n');
  print('═══════════════════════════════════════════════════════════════════\\n\\n');

  // Initialize Ditto (simplified)
  final ditto = await Ditto.open(
    identity: DittoIdentity.onlinePlayground(
      appID: 'your-app-id',
      token: 'your-token',
    ),
    persistenceDirectory: '/tmp/ditto',
  );

  // Pattern 1: Lightweight Callback
  print('PATTERN 1: Lightweight Callback (< 16ms Target)');
  print('─────────────────────────────────────────────────\\n');
  final lightweight = LightweightCallbackExample(ditto);
  lightweight.startObserving();
  await Future.delayed(Duration(seconds: 1));
  lightweight.stopObserving();

  // Performance Comparison
  print('\\n');
  PerformanceComparison.printComparison();

  // Migration Preparation
  MigrationPreparation.printMigrationGuide();

  // Cleanup
  await ditto.close();

  print('\\n═══════════════════════════════════════════════════════════════════');
  print('KEY TAKEAWAYS:');
  print('═══════════════════════════════════════════════════════════════════');
  print('1. ⚡ Keep callbacks < 16ms for 60 FPS (Flutter SDK v4.x)');
  print('2. 🎯 Use Riverpod for granular rebuilds (better performance)');
  print('3. ❌ Avoid full screen setState() in observer callbacks');
  print('4. ✅ Offload heavy processing to background async tasks');
  print('5. 📊 Extract data immediately from QueryResultItems');
  print('6. 🎉 Flutter SDK v5.0: Will add signalNext for backpressure control');
  print('7. ✅ Current best practices will continue to work in v5.0');
  print('═══════════════════════════════════════════════════════════════════\\n');
}
