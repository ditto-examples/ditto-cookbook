// Example: Subscription and Observer Lifecycle Anti-Patterns
// This file demonstrates common mistakes that lead to memory leaks and bugs

import 'package:ditto/ditto.dart';
import 'package:flutter/widgets.dart';

/// Anti-Pattern 1: Not canceling subscriptions and observers
///
/// ❌ BAD: Memory leak - subscriptions and observers never canceled
class LeakyOrdersService {
  final Ditto ditto;

  LeakyOrdersService(this.ditto);

  void initialize() {
    // Registered but never canceled - MEMORY LEAK!
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Registered but never canceled - MEMORY LEAK!
    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        print('Orders: ${orders.length}');
        signalNext();
      },
    );
  }

  // Missing dispose() method!
  // Subscriptions and observers continue running even after service is destroyed
}

/// ✅ GOOD: Proper cleanup
class ProperOrdersService {
  final Ditto ditto;
  late final Subscription _subscription;
  late final StoreObserver _observer;

  ProperOrdersService(this.ditto);

  void initialize() {
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        print('Orders: ${orders.length}');
        signalNext();
      },
    );
  }

  void dispose() {
    _observer.cancel();
    _subscription.cancel();
  }
}

/// Anti-Pattern 2: Widget without proper lifecycle management
///
/// ❌ BAD: Subscription registered but never canceled in widget lifecycle
class LeakyOrdersWidget extends StatefulWidget {
  final Ditto ditto;

  const LeakyOrdersWidget({required this.ditto, Key? key}) : super(key: key);

  @override
  State<LeakyOrdersWidget> createState() => _LeakyOrdersWidgetState();
}

class _LeakyOrdersWidgetState extends State<LeakyOrdersWidget> {
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();

    // PROBLEM: No reference stored, can't cancel later!
    widget.ditto.sync.registerSubscription(
      'SELECT * FROM orders',
    );

    widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        setState(() {
          _orders = result.items.map((item) => item.value).toList();
        });
        signalNext();
      },
    );
  }

  // Missing dispose() - Memory leak!

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(_orders[index]['name'] ?? ''));
      },
    );
  }
}

/// Anti-Pattern 3: Canceling in wrong order
///
/// ❌ BAD: Canceling subscription before observer can cause issues
class WrongOrderCancellation {
  final Ditto ditto;
  late final Subscription _subscription;
  late final StoreObserver _observer;

  WrongOrderCancellation(this.ditto);

  void initialize() {
    _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        signalNext();
      },
    );
  }

  void dispose() {
    // WRONG ORDER: Canceling subscription first
    // Observer might still try to process data
    _subscription.cancel();
    _observer.cancel(); // Should be first!
  }
}

/// ✅ GOOD: Cancel in reverse order (observer first, subscription second)
class CorrectOrderCancellation {
  final Ditto ditto;
  late final Subscription _subscription;
  late final StoreObserver _observer;

  CorrectOrderCancellation(this.ditto);

  void initialize() {
    _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        final orders = result.items.map((item) => item.value).toList();
        signalNext();
      },
    );
  }

  void dispose() {
    // CORRECT: Cancel observer first, then subscription
    _observer.cancel();
    _subscription.cancel();
  }
}

/// Anti-Pattern 4: Re-creating subscriptions without canceling old ones
///
/// ❌ BAD: Creating new subscriptions without cleaning up old ones
class MultipleLeakySubscriptions {
  final Ditto ditto;

  MultipleLeakySubscriptions(this.ditto);

  void setFilter(String status) {
    // PROBLEM: Old subscription still active, creating new one!
    // Each call adds another subscription - LEAK!
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': status},
    );

    ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': status},
      onChange: (result, signalNext) {
        print('Orders: ${result.items.length}');
        signalNext();
      },
    );
  }
}

/// ✅ GOOD: Cancel old subscriptions before creating new ones
class ProperDynamicSubscriptions {
  final Ditto ditto;
  Subscription? _subscription;
  StoreObserver? _observer;

  ProperDynamicSubscriptions(this.ditto);

  void setFilter(String status) {
    // Cancel old subscriptions first
    _observer?.cancel();
    _subscription?.cancel();

    // Create new subscriptions
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': status},
    );

    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': status},
      onChange: (result, signalNext) {
        print('Orders: ${result.items.length}');
        signalNext();
      },
    );
  }

  void dispose() {
    _observer?.cancel();
    _subscription?.cancel();
  }
}

/// Anti-Pattern 5: Subscription without observer (or vice versa)
///
/// ❌ BAD: Subscription without observer - data syncs but never accessed
class SubscriptionWithoutObserver {
  final Ditto ditto;
  late final Subscription _subscription;

  SubscriptionWithoutObserver(this.ditto);

  void initialize() {
    // Data is syncing but we're never observing it!
    // Wastes bandwidth and storage
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Missing observer!
  }

  void dispose() {
    _subscription.cancel();
  }
}

/// ❌ BAD: Observer without subscription - only sees local data
class ObserverWithoutSubscription {
  final Ditto ditto;
  late final StoreObserver _observer;

  ObserverWithoutSubscription(this.ditto);

  void initialize() {
    // Only observes local changes, no mesh sync!
    // Won't receive updates from other devices
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) {
        print('Local orders: ${result.items.length}');
        signalNext();
      },
    );

    // Missing subscription!
  }

  void dispose() {
    _observer.cancel();
  }
}

/// ✅ GOOD: Both subscription and observer together
class ProperSubscriptionAndObserver {
  final Ditto ditto;
  late final Subscription _subscription;
  late final StoreObserver _observer;

  ProperSubscriptionAndObserver(this.ditto);

  void initialize() {
    // Subscription: Sync data from mesh
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
    );

    // Observer: React to local data changes (from sync or local updates)
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status',
      arguments: {'status': 'active'},
      onChange: (result, signalNext) {
        print('Orders (local + synced): ${result.items.length}');
        signalNext();
      },
    );
  }

  void dispose() {
    _observer.cancel();
    _subscription.cancel();
  }
}

/// Anti-Pattern 6: Storing observer in wrong scope
///
/// ❌ BAD: Observer created in method scope, can't be canceled
class WrongScopeObserver {
  final Ditto ditto;

  WrongScopeObserver(this.ditto);

  void setupOrders() {
    // PROBLEM: Local variable, can't access in dispose()!
    final observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        print('Orders: ${result.items.length}');
        signalNext();
      },
    );

    // observer goes out of scope here, can't cancel later!
  }

  void dispose() {
    // Can't cancel observer here - no reference!
  }
}

/// Anti-Pattern 7: Not handling null safety for cancellation
///
/// ❌ BAD: Potential null reference errors
class UnsafeCancellation {
  final Ditto ditto;
  late Subscription _subscription; // Not nullable, not initialized
  late StoreObserver _observer;

  UnsafeCancellation(this.ditto);

  void dispose() {
    // CRASH RISK: If dispose() called before initialize()
    _observer.cancel(); // Might crash!
    _subscription.cancel(); // Might crash!
  }
}

/// ✅ GOOD: Null-safe cancellation
class SafeCancellation {
  final Ditto ditto;
  Subscription? _subscription; // Nullable
  StoreObserver? _observer;

  SafeCancellation(this.ditto);

  void initialize() {
    _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
    _observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) => signalNext(),
    );
  }

  void dispose() {
    // Safe: Only cancel if not null
    _observer?.cancel();
    _subscription?.cancel();
  }
}

/// Anti-Pattern 8: Using setState after widget disposed
///
/// ❌ BAD: Observer continues after widget disposed, causes setState errors
class StateAfterDisposeWidget extends StatefulWidget {
  final Ditto ditto;

  const StateAfterDisposeWidget({required this.ditto, Key? key}) : super(key: key);

  @override
  State<StateAfterDisposeWidget> createState() => _StateAfterDisposeWidgetState();
}

class _StateAfterDisposeWidgetState extends State<StateAfterDisposeWidget> {
  late final StoreObserver _observer;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        // PROBLEM: This might be called after dispose()
        setState(() { // ERROR: setState called after dispose
          _orders = result.items.map((item) => item.value).toList();
        });
        signalNext();
      },
    );
  }

  @override
  void dispose() {
    // Race condition: observer callback might still fire
    super.dispose(); // Disposed too early!
    _observer.cancel(); // Should cancel BEFORE super.dispose()
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(_orders[index]['name'] ?? ''));
      },
    );
  }
}

/// ✅ GOOD: Cancel observer before dispose, check mounted
class SafeStateWidget extends StatefulWidget {
  final Ditto ditto;

  const SafeStateWidget({required this.ditto, Key? key}) : super(key: key);

  @override
  State<SafeStateWidget> createState() => _SafeStateWidgetState();
}

class _SafeStateWidgetState extends State<SafeStateWidget> {
  late final StoreObserver _observer;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();

    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        // Check if widget is still mounted
        if (mounted) {
          setState(() {
            _orders = result.items.map((item) => item.value).toList();
          });
        }
        signalNext();
      },
    );
  }

  @override
  void dispose() {
    // Cancel BEFORE super.dispose()
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(_orders[index]['name'] ?? ''));
      },
    );
  }
}
