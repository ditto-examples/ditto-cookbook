// Example: Observer Pattern Best Practices
// This file demonstrates proper observer usage and backpressure control
//
// ⚠️ IMPORTANT: This example uses registerObserverWithSignalNext which is NOT available
// in Flutter SDK v4.14.0 and earlier. These patterns apply to non-Flutter SDKs (Swift, JS, Kotlin).
//
// For Flutter SDK v4.x patterns, see: flutter-observer-v4-patterns.dart
// Flutter SDK v5.0 will add support for registerObserverWithSignalNext.

import 'package:ditto/ditto.dart';
import 'package:flutter/widgets.dart';

/// Example 1: registerObserverWithSignalNext (recommended for most cases)
///
/// ✅ GOOD: Backpressure control prevents observer overload
class BackpressureControlledObserver {
  final Ditto ditto;
  late final StoreObserver _observer;

  BackpressureControlledObserver(this.ditto);

  void initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'pending'},
      onChange: (result, signalNext) {
        // Extract data immediately
        final orders = result.items.map((item) => item.value).toList();

        // Process orders
        _processOrders(orders);

        // Signal ready for next batch
        // This prevents observer from being overwhelmed with updates
        signalNext();
      },
    );
  }

  void _processOrders(List<Map<String, dynamic>> orders) {
    print('Processing ${orders.length} pending orders');
    // Processing logic here
  }

  void dispose() {
    _observer.cancel();
  }
}

/// Example 2: registerObserverWithSignalNext in Flutter widget
///
/// ✅ GOOD: Signal after UI render completes
class OrdersWidget extends StatefulWidget {
  final Ditto ditto;

  const OrdersWidget({required this.ditto, Key? key}) : super(key: key);

  @override
  State<OrdersWidget> createState() => _OrdersWidgetState();
}

class _OrdersWidgetState extends State<OrdersWidget> {
  late final StoreObserver _observer;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        // Extract data
        final orders = result.items.map((item) => item.value).toList();

        // Update UI
        if (mounted) {
          setState(() {
            _orders = orders;
          });
        }

        // Signal AFTER render cycle completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
    );
  }

  @override
  void dispose() {
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        return ListTile(
          title: Text(order['customerName'] ?? 'Unknown'),
          subtitle: Text('Status: ${order['status']}'),
        );
      },
    );
  }
}

/// Example 3: registerObserver (no backpressure - use sparingly)
///
/// ✅ ACCEPTABLE: For infrequent updates or when processing is very light
class SimpleObserverWithoutBackpressure {
  final Ditto ditto;
  late final StoreObserver _observer;

  SimpleObserverWithoutBackpressure(this.ditto);

  void initialize() {
    // Use registerObserver when:
    // 1. Updates are infrequent (e.g., system settings)
    // 2. Processing is extremely lightweight
    // 3. You don't need backpressure control

    _observer = ditto.store.registerObserver(
      'SELECT * FROM appSettings',
      onChange: (result) {
        // Extract immediately
        final settings = result.items.firstOrNull?.value;

        if (settings != null) {
          // Very lightweight processing only
          _updateSettings(settings);
        }
      },
    );
  }

  void _updateSettings(Map<String, dynamic> settings) {
    // Extremely lightweight operation
    print('Settings updated: theme=${settings['theme']}');
  }

  void dispose() {
    _observer.cancel();
  }
}

/// Example 4: Async processing with signalNext
///
/// ✅ GOOD: Handle async work properly with backpressure
class AsyncProcessingObserver {
  final Ditto ditto;
  late final StoreObserver _observer;

  AsyncProcessingObserver(this.ditto);

  void initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'pending'},
      onChange: (result, signalNext) async {
        // Extract data immediately
        final orders = result.items.map((item) => item.value).toList();

        try {
          // Async processing
          await _processOrdersAsync(orders);

          // Signal after processing completes
          signalNext();
        } catch (e) {
          print('Error processing orders: $e');
          // IMPORTANT: Signal even on error to prevent blocking
          signalNext();
        }
      },
    );
  }

  Future<void> _processOrdersAsync(List<Map<String, dynamic>> orders) async {
    // Simulate async work (API calls, heavy computation, etc.)
    for (final order in orders) {
      await _validateOrder(order);
    }
  }

  Future<void> _validateOrder(Map<String, dynamic> order) async {
    // Simulate validation
    await Future.delayed(Duration(milliseconds: 10));
  }

  void dispose() {
    _observer.cancel();
  }
}

/// Example 5: Multiple observers with different update strategies
///
/// ✅ GOOD: Use appropriate observer type for each use case
class MultiObserverService {
  final Ditto ditto;
  final List<StoreObserver> _observers = [];

  MultiObserverService(this.ditto);

  void initialize() {
    // High-frequency updates: Use backpressure
    _observers.add(
      ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM products',
        onChange: (result, signalNext) {
          final products = result.items.map((item) => item.value).toList();
          _updateProductCache(products);
          signalNext();
        },
      ),
    );

    // Low-frequency updates: Simple observer acceptable
    _observers.add(
      ditto.store.registerObserver(
        'SELECT * FROM systemConfig',
        onChange: (result) {
          final config = result.items.firstOrNull?.value;
          if (config != null) {
            _applySystemConfig(config);
          }
        },
      ),
    );

    // UI updates: Signal after render
    _observers.add(
      ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM notifications WHERE isRead = false',
        onChange: (result, signalNext) {
          final notifications = result.items.map((item) => item.value).toList();
          _showNotifications(notifications);

          // Signal after UI updates
          WidgetsBinding.instance.addPostFrameCallback((_) {
            signalNext();
          });
        },
      ),
    );
  }

  void _updateProductCache(List<Map<String, dynamic>> products) {
    print('Updated product cache: ${products.length} products');
  }

  void _applySystemConfig(Map<String, dynamic> config) {
    print('Applied system config');
  }

  void _showNotifications(List<Map<String, dynamic>> notifications) {
    print('Showing ${notifications.length} unread notifications');
  }

  void dispose() {
    for (final observer in _observers) {
      observer.cancel();
    }
    _observers.clear();
  }
}

/// Example 6: Conditional signalNext based on processing outcome
///
/// ✅ GOOD: Control backpressure based on processing state
class ConditionalSignalObserver {
  final Ditto ditto;
  late final StoreObserver _observer;
  int _consecutiveErrors = 0;

  ConditionalSignalObserver(this.ditto);

  void initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'processing'},
      onChange: (result, signalNext) async {
        final orders = result.items.map((item) => item.value).toList();

        try {
          await _processOrders(orders);

          // Success: Reset error counter and signal immediately
          _consecutiveErrors = 0;
          signalNext();
        } catch (e) {
          _consecutiveErrors++;
          print('Error processing orders: $e (consecutive errors: $_consecutiveErrors)');

          // Backoff strategy: Delay signalNext on repeated errors
          if (_consecutiveErrors > 3) {
            // Wait before signaling to avoid rapid error loop
            await Future.delayed(Duration(seconds: 5));
          }

          // Always signal eventually to prevent permanent blocking
          signalNext();
        }
      },
    );
  }

  Future<void> _processOrders(List<Map<String, dynamic>> orders) async {
    // Processing logic that might fail
    for (final order in orders) {
      if (order['totalAmount'] == null) {
        throw Exception('Invalid order data');
      }
    }
  }

  void dispose() {
    _observer.cancel();
  }
}

/// Example 7: Partial UI updates to minimize re-renders
///
/// ✅ GOOD: Only update affected parts of UI
class PartialUpdateWidget extends StatefulWidget {
  final Ditto ditto;

  const PartialUpdateWidget({required this.ditto, Key? key}) : super(key: key);

  @override
  State<PartialUpdateWidget> createState() => _PartialUpdateWidgetState();
}

class _PartialUpdateWidgetState extends State<PartialUpdateWidget> {
  late final StoreObserver _observer;
  final Map<String, Map<String, dynamic>> _ordersById = {};

  @override
  void initState() {
    super.initState();

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();

        // Check what actually changed before calling setState
        bool hasChanges = false;

        for (final order in orders) {
          final id = order['_id'] as String;
          final existing = _ordersById[id];

          // Only update if changed
          if (existing == null || !_areOrdersEqual(existing, order)) {
            _ordersById[id] = order;
            hasChanges = true;
          }
        }

        // Only trigger rebuild if something changed
        if (hasChanges && mounted) {
          setState(() {});
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
    );
  }

  bool _areOrdersEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Simple equality check (could use deep equality)
    return a['status'] == b['status'] &&
        a['totalAmount'] == b['totalAmount'] &&
        a['updatedAt'] == b['updatedAt'];
  }

  @override
  void dispose() {
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = _ordersById.values.toList();

    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return ListTile(
          key: ValueKey(order['_id']),
          title: Text(order['customerName'] ?? 'Unknown'),
          subtitle: Text('Status: ${order['status']}'),
        );
      },
    );
  }
}

/// Example 8: Debouncing rapid updates
///
/// ✅ GOOD: Prevent excessive processing for rapid consecutive updates
class DebouncedObserver {
  final Ditto ditto;
  late final StoreObserver _observer;
  DateTime? _lastProcessed;
  static const _debounceDelay = Duration(milliseconds: 300);

  DebouncedObserver(this.ditto);

  void initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM products',
      onChange: (result, signalNext) async {
        final now = DateTime.now();

        // Check if enough time has passed since last processing
        if (_lastProcessed != null &&
            now.difference(_lastProcessed!) < _debounceDelay) {
          // Too soon, signal immediately without processing
          signalNext();
          return;
        }

        // Process the update
        final products = result.items.map((item) => item.value).toList();
        await _processProducts(products);

        _lastProcessed = now;
        signalNext();
      },
    );
  }

  Future<void> _processProducts(List<Map<String, dynamic>> products) async {
    print('Processing ${products.length} products');
    // Heavy processing logic
  }

  void dispose() {
    _observer.cancel();
  }
}

/// Example 9: Error recovery with automatic retry
///
/// ✅ GOOD: Graceful error handling with retry logic
class RetryingObserver {
  final Ditto ditto;
  late final StoreObserver _observer;

  RetryingObserver(this.ditto);

  void initialize() {
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'pending'},
      onChange: (result, signalNext) async {
        final orders = result.items.map((item) => item.value).toList();

        bool success = false;
        int retries = 0;
        const maxRetries = 3;

        while (!success && retries < maxRetries) {
          try {
            await _processOrders(orders);
            success = true;
          } catch (e) {
            retries++;
            print('Processing failed (attempt $retries/$maxRetries): $e');

            if (retries < maxRetries) {
              // Wait before retry
              await Future.delayed(Duration(seconds: retries));
            }
          }
        }

        if (!success) {
          print('Failed to process orders after $maxRetries attempts');
        }

        // Always signal, even if processing failed
        signalNext();
      },
    );
  }

  Future<void> _processOrders(List<Map<String, dynamic>> orders) async {
    // Processing that might fail
    await Future.delayed(Duration(milliseconds: 100));
  }

  void dispose() {
    _observer.cancel();
  }
}
