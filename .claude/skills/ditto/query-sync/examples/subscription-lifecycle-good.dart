// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// Example: Subscription and Observer Lifecycle Best Practices
// This file demonstrates proper lifecycle management to prevent memory leaks

import 'package:ditto/ditto.dart';
import 'package:flutter/widgets.dart';

/// Example 1: Service-based lifecycle management
///
/// ✅ GOOD: Centralized subscription management with proper cleanup
class OrdersService {
  final Ditto ditto;

  // Store references to cancel later
  Subscription? _activeOrdersSubscription;
  StoreObserver? _activeOrdersObserver;

  OrdersService(this.ditto);

  /// Initialize subscriptions and observers
  void initialize() {
    // Step 1: Register subscription (mesh sync)
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Step 2: Register observer (local data changes)
    _activeOrdersObserver = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) {
        // Extract data immediately
        final orders = result.items.map((item) => item.value).toList();

        // Process orders
        print('Active orders updated: ${orders.length}');

        // Signal ready for next batch
        signalNext();
      },
    );
  }

  /// Clean up resources
  void dispose() {
    // CRITICAL: Always cancel in reverse order
    _activeOrdersObserver?.cancel();
    _activeOrdersSubscription?.cancel();
  }
}

/// Example 2: Flutter widget lifecycle integration
///
/// ✅ GOOD: Subscribe in initState, cancel in dispose
class OrdersListWidget extends StatefulWidget {
  final Ditto ditto;

  const OrdersListWidget({required this.ditto, Key? key}) : super(key: key);

  @override
  State<OrdersListWidget> createState() => _OrdersListWidgetState();
}

class _OrdersListWidgetState extends State<OrdersListWidget> {
  late final Subscription _subscription;
  late final StoreObserver _observer;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _setupDittoSync();
  }

  void _setupDittoSync() {
    // Register subscription
    _subscription = widget.ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'pending'},
    );

    // Register observer with backpressure control
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'pending'},
      onChange: (result, signalNext) {
        // Extract data immediately
        final orders = result.items.map((item) => item.value).toList();

        // Update state
        setState(() {
          _orders = orders;
        });

        // Signal after UI update completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          signalNext();
        });
      },
    );
  }

  @override
  void dispose() {
    // CRITICAL: Cancel before dispose
    _observer.cancel();
    _subscription.cancel();
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
          subtitle: Text('Total: \$${order['totalAmount']}'),
        );
      },
    );
  }
}

/// Example 3: Multiple subscriptions with coordinated lifecycle
///
/// ✅ GOOD: Manage multiple subscriptions together
class DashboardService {
  final Ditto ditto;

  // Track all subscriptions and observers
  final List<Subscription> _subscriptions = [];
  final List<StoreObserver> _observers = [];

  DashboardService(this.ditto);

  void initialize() {
    // Products subscription
    _subscriptions.add(
      ditto.sync.registerSubscription(
        'SELECT * FROM products WHERE isActive = true',
      ),
    );

    _observers.add(
      ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM products WHERE isActive = true',
        onChange: _handleProductsChange,
      ),
    );

    // Orders subscription
    _subscriptions.add(
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE status IN (:statuses)',
        arguments: {
          'statuses': ['pending', 'processing'],
        },
      ),
    );

    _observers.add(
      ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM orders WHERE status IN (:statuses)',
        arguments: {
          'statuses': ['pending', 'processing'],
        },
        onChange: _handleOrdersChange,
      ),
    );

    // Analytics subscription
    _subscriptions.add(
      ditto.sync.registerSubscription(
        'SELECT * FROM analytics WHERE date >= :date',
        arguments: {
          'date': DateTime.now().subtract(Duration(days: 7)).toIso8601String(),
        },
      ),
    );

    _observers.add(
      ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM analytics WHERE date >= :date',
        arguments: {
          'date': DateTime.now().subtract(Duration(days: 7)).toIso8601String(),
        },
        onChange: _handleAnalyticsChange,
      ),
    );
  }

  void dispose() {
    // Cancel all observers first
    for (final observer in _observers) {
      observer.cancel();
    }
    _observers.clear();

    // Then cancel all subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _handleProductsChange(QueryResult result, Function signalNext) {
    final products = result.items.map((item) => item.value).toList();
    print('Products updated: ${products.length}');
    signalNext();
  }

  void _handleOrdersChange(QueryResult result, Function signalNext) {
    final orders = result.items.map((item) => item.value).toList();
    print('Orders updated: ${orders.length}');
    signalNext();
  }

  void _handleAnalyticsChange(QueryResult result, Function signalNext) {
    final analytics = result.items.map((item) => item.value).toList();
    print('Analytics updated: ${analytics.length}');
    signalNext();
  }
}

/// Example 4: Dynamic subscription management (conditional subscriptions)
///
/// ✅ GOOD: Manage subscriptions that change based on application state
class FilterableOrdersService {
  final Ditto ditto;

  Subscription? _currentSubscription;
  StoreObserver? _currentObserver;
  String? _currentFilter;

  FilterableOrdersService(this.ditto);

  /// Update filter and re-subscribe
  void setFilter(String status) {
    // If filter hasn't changed, don't re-subscribe
    if (_currentFilter == status) return;

    // Cancel existing subscription
    _cancelCurrentSubscription();

    // Register new subscription with new filter
    _currentFilter = status;
    _currentSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': status},
    );

    _currentObserver = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': status},
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        print('Orders with status "$status": ${orders.length}');
        signalNext();
      },
    );
  }

  void _cancelCurrentSubscription() {
    _currentObserver?.cancel();
    _currentSubscription?.cancel();
    _currentObserver = null;
    _currentSubscription = null;
  }

  void dispose() {
    _cancelCurrentSubscription();
    _currentFilter = null;
  }
}

/// Example 5: One-time query (no subscription needed)
///
/// ✅ GOOD: Use execute() for one-time queries without subscription
/// Only use subscriptions when you need continuous sync
Future<List<Map<String, dynamic>>> getCompletedOrders(Ditto ditto) async {
  // No subscription needed for one-time historical data
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'completed'},
  );

  // Extract and return
  return result.items.map((item) => item.value).toList();
}

/// Example 6: Subscription with error handling
///
/// ✅ GOOD: Gracefully handle errors in observer callbacks
class RobustOrdersService {
  final Ditto ditto;

  Subscription? _subscription;
  StoreObserver? _observer;

  RobustOrdersService(this.ditto);

  void initialize() {
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) {
        try {
          // Extract data
          final orders = result.items.map((item) => item.value).toList();

          // Process orders (might throw)
          _processOrders(orders);

          // Success: signal next
          signalNext();
        } catch (e, stackTrace) {
          // Log error but still signal to prevent blocking
          print('Error processing orders: $e');
          print('Stack trace: $stackTrace');

          // IMPORTANT: Still call signalNext() to prevent blocking
          signalNext();
        }
      },
    );
  }

  void _processOrders(List<Map<String, dynamic>> orders) {
    // Processing logic that might throw
    for (final order in orders) {
      // Validate and process
      if (order['totalAmount'] == null) {
        throw Exception('Invalid order: missing totalAmount');
      }
    }
  }

  void dispose() {
    _observer?.cancel();
    _subscription?.cancel();
  }
}

/// Example 7: Delayed subscription cancellation (graceful shutdown)
///
/// ✅ GOOD: Give pending operations time to complete
class GracefulOrdersService {
  final Ditto ditto;

  Subscription? _subscription;
  StoreObserver? _observer;
  bool _isProcessing = false;

  GracefulOrdersService(this.ditto);

  void initialize() {
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) async {
        _isProcessing = true;

        try {
          final orders = result.items.map((item) => item.value).toList();

          // Async processing
          await _processOrdersAsync(orders);

          signalNext();
        } finally {
          _isProcessing = false;
        }
      },
    );
  }

  Future<void> _processOrdersAsync(List<Map<String, dynamic>> orders) async {
    // Simulate async work
    await Future.delayed(Duration(milliseconds: 100));
  }

  Future<void> dispose() async {
    // Wait for processing to complete
    while (_isProcessing) {
      await Future.delayed(Duration(milliseconds: 50));
    }

    // Now safe to cancel
    _observer?.cancel();
    _subscription?.cancel();
  }
}
