---
name: performance-observability
description: Validates Ditto observer performance patterns, UI optimization, and logging configuration. Prevents full-screen rebuilds, unnecessary delta sync, and missing startup diagnostics. Enforces partial UI updates, signalNext() timing (non-Flutter SDKs), value-change checks, and DO UPDATE_LOCAL_DIFF usage. Flutter SDK v4.x - signalNext not available until v5.0. Use when implementing observers, optimizing UI performance, configuring logging, or managing sync overhead.
---

# Ditto Performance and Observability

## Purpose

This Skill ensures optimal performance and observability in Ditto applications. It prevents common performance pitfalls like full-screen rebuilds in observer callbacks, unnecessary sync deltas from unchanged value updates, and missing startup diagnostics from improper logging configuration.

**Critical issues prevented**:
- Full-screen rebuilds in observer callbacks (Flutter)
- Missing signalNext() calls blocking further updates
- Heavy processing in observer callbacks blocking UI
- Unnecessary delta sync from unchanged value updates
- Missing startup diagnostics from late log level configuration
- Broad subscription scope wasting bandwidth
- Observer backpressure buildup causing memory issues

## When This Skill Applies

Use this Skill when:
- Implementing observer callbacks with `registerObserver*()`
- Optimizing UI performance and widget rebuilds (Flutter)
- Configuring logging with `DittoLogger`
- Managing subscription scope and query optimization
- Handling backpressure in observers with `signalNext()`
- Preventing unnecessary sync traffic and delta generation
- Debugging performance issues or sync overhead
- Implementing state management with Ditto data

## Platform Detection

**Automatic Detection**:
1. **Flutter/Dart**: `*.dart` files with `import 'package:ditto/ditto.dart'` → Full UI optimization patterns
2. **JavaScript**: `*.js`, `*.ts` files with `import { Ditto } from '@dittolive/ditto'` → Observer + logging patterns
3. **Swift**: `*.swift` files with `import DittoSwift'` → Observer + logging patterns
4. **Kotlin**: `*.kt` files with `import live.ditto.*` → Observer + logging patterns

**Platform-Specific**:
- **Flutter**: Full UI optimization patterns (setState, Riverpod, WidgetsBinding)
- **All platforms**: Observer patterns, logging, sync optimization

---

## Critical Patterns

### 1. Full Screen setState() in Observer (Priority: CRITICAL - Flutter)

**Platform**: Flutter/Dart only

**Problem**: Calling `setState()` on the entire screen in observer callbacks causes all widgets to rebuild, even those unaffected by data changes. This leads to poor performance, visual glitches, and battery drain.

**Detection**:
```dart
// RED FLAGS (Flutter)
class OrderListScreen extends StatefulWidget {
  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    // ⚠️ Note: This uses registerObserverWithSignalNext (NOT available in Flutter SDK v4.x)
    // Flutter SDK v4.x must use registerObserver or observer.changes Stream API
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        setState(() {
          orders = result.items.map((item) => item.value).toList();
        });
        // Entire screen rebuilds when ANY order changes!
        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
      arguments: {},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Full screen rebuild every time
    return Scaffold(
      appBar: AppBar(title: Text('Orders (${orders.length})')),
      body: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return OrderCard(order: order); // All cards rebuild!
        },
      ),
    );
  }
}
```

**✅ DO (Flutter - State Management)**:
```dart
// Use Riverpod for granular widget rebuilds
final dittoProvider = Provider<Ditto>((ref) => throw UnimplementedError());

// Provider for orders data with observer (Flutter SDK v4.x)
final ordersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final ditto = ref.watch(dittoProvider);

  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders ORDER BY createdAt DESC',
    arguments: {},
  );

  ref.onDispose(() {
    observer.cancel();
  });

  return observer.changes.map((result) {
    return result.items.map((item) => item.value).toList();
  });
});

// Provider for single order (granular selection)
final orderProvider = Provider.family<Map<String, dynamic>?, String>((ref, orderId) {
  final ordersAsync = ref.watch(ordersProvider);
  return ordersAsync.when(
    data: (orders) => orders.firstWhereOrNull((o) => o['_id'] == orderId),
    loading: () => null,
    error: (_, __) => null,
  );
});

// Screen widget (minimal rebuilds)
class OrderListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: ordersAsync.when(
          data: (orders) => Text('Orders (${orders.length})'),
          loading: () => Text('Orders'),
          error: (_, __) => Text('Orders (Error)'),
        ),
      ),
      body: ordersAsync.when(
        data: (orders) => ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final orderId = orders[index]['_id'] as String;
            // Only rebuilds if THIS order's data changes
            return OrderCard(orderId: orderId);
          },
        ),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

// Individual card widget (rebuilds only when its order changes)
class OrderCard extends ConsumerWidget {
  final String orderId;

  const OrderCard({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    if (order == null) return SizedBox.shrink();

    return Card(
      child: ListTile(
        title: Text('Order #${order['orderNumber']}'),
        subtitle: Text('Status: ${order['status']}'),
      ),
    );
  }
}
```

**❌ DON'T (Flutter)**:
```dart
// setState() on entire screen
setState(() {
  orders = result.items.map((item) => item.value).toList();
});
// All widgets rebuild unnecessarily

// No scoped rebuilds
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(...), // Rebuilds
    body: ListView.builder(...), // Rebuilds
  );
  // Entire widget tree rebuilds on every data change
}
```

**Why**: `setState()` on the root widget rebuilds the entire widget tree. When a single order changes, all 1000+ orders rebuild unnecessarily. State management (Riverpod, ValueListenableBuilder) enables granular rebuilds - only affected widgets update.

**Performance Comparison** (1000 orders, single order changes):

| Approach | Widgets Rebuilt | Performance |
|----------|----------------|-------------|
| ❌ setState() entire screen | ~1003 | High (full refresh) |
| ✅ Riverpod granular | 1 | Minimal (optimal) |

**See**: [examples/flutter-state-management-good.dart](examples/flutter-state-management-good.dart)

---

### 2. Missing signalNext() Call (Priority: CRITICAL - Non-Flutter SDKs Only)

**Platform**: Swift, JavaScript, Kotlin (NOT applicable to Flutter SDK v4.x)

**⚠️ Flutter SDK Exception:**
Flutter SDK v4.14.0 and earlier do not support `registerObserverWithSignalNext` or `signalNext` parameter. This pattern applies only to non-Flutter SDKs (Swift, JS, Kotlin). Flutter SDK v5.0 will add `signalNext` support.

For Flutter SDK v4.x:
- Use `registerObserver` (no `signalNext` parameter)
- Keep callbacks lightweight to avoid performance issues
- No manual backpressure control available

**Problem**: Not calling `signalNext()` after processing observer updates prevents observer from receiving further updates. Observer stops after first callback.

**Detection**:
```dart
// RED FLAGS
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();
    updateUI(orders);
    // Missing signalNext() - observer stops receiving updates!
  },
);
```

**✅ DO (Flutter SDK v4.x - No signalNext Available)**:
```dart
// Flutter SDK v4.14.0: Use registerObserver (no signalNext)
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE status = :status',
  onChange: (result) {
    // No signalNext parameter in Flutter SDK v4.x
    final orders = result.items.map((item) => item.value).toList();
    updateUI(orders);
    // Note: No backpressure control - keep callbacks lightweight
  },
  arguments: {'status': 'active'},
);

// Flutter SDK v5.0+: Will support registerObserverWithSignalNext
```

**✅ DO (Non-Flutter SDKs - Swift, JS, Kotlin)**:
```dart
// Non-Flutter: Use registerObserverWithSignalNext
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    const orders = result.items.map(item => item.value);
    updateUI(orders);
    signalNext(); // Ready for next update
  },
);
```

**❌ DON'T**:
```dart
// Never call signalNext()
onChange: (result, signalNext) {
  updateUI(result.items);
  // Observer blocked after first callback
}

// Call signalNext() before processing completes
onChange: (result, signalNext) {
  signalNext(); // Too early!
  updateUI(result.items); // UI update after signal
}

// Call signalNext() inside async operation without await
onChange: (result, signalNext) {
  processDataAsync(result.items); // Async, no await
  signalNext(); // Called before async completes
}
```

**Why**: `registerObserverWithSignalNext` implements backpressure control. Observer waits for `signalNext()` before delivering next update. Not calling it stops observer. Call after processing completes (Flutter: after render cycle).

**Backpressure Flow**:
1. Observer delivers update (first callback)
2. App processes data, updates UI
3. App calls `signalNext()` when ready
4. Observer delivers next update (second callback)
5. Repeat

**See**: [examples/observer-backpressure.dart](examples/observer-backpressure.dart)

---

### 3. Heavy Processing in Observer Callbacks (Priority: HIGH)

**Platform**: All platforms

**Problem**: Heavy processing (complex computations, network calls, file I/O) in observer callbacks blocks the observer thread, preventing `signalNext()` from being called promptly.

**Detection**:
```dart
// RED FLAGS
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    final orders = result.items.map((item) => item.value).toList();

    // Heavy computation blocks callback
    for (final order in orders) {
      final analysis = performExpensiveAnalysis(order); // BLOCKS!
      final report = generateDetailedReport(order); // BLOCKS!
      sendToAnalyticsService(report); // Network call BLOCKS!
    }

    signalNext(); // Only called after all heavy processing
  },
);
```

**✅ DO**:
```dart
// Lightweight callback, heavy processing offloaded
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders',
  onChange: (result, signalNext) {
    // Extract data immediately (lightweight)
    final orders = result.items.map((item) => item.value).toList();

    // Update UI immediately (lightweight)
    updateUI(orders);

    // Offload heavy processing to background async task
    _processOrdersAsync(orders); // Non-blocking

    // Signal readiness for next update immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
);

// Heavy processing runs independently
Future<void> _processOrdersAsync(List<Map<String, dynamic>> orders) async {
  // These operations run in parallel, don't block observer
  await Future.wait(orders.map((order) async {
    final analysis = await performExpensiveAnalysis(order);
    final report = await generateDetailedReport(order);
    await sendToAnalyticsService(report);
  }));
}
```

**❌ DON'T**:
```dart
// Heavy sync operations in callback
onChange: (result, signalNext) {
  final orders = result.items.map((item) => item.value).toList();

  for (var order in orders) {
    complexCalculation(order); // Blocks
    networkCall(order); // Blocks
    fileIO(order); // Blocks
  }

  signalNext(); // Delayed by heavy processing
}

// Await heavy async in callback
onChange: (result, signalNext) async {
  final orders = result.items.map((item) => item.value).toList();
  await Future.delayed(Duration(seconds: 5)); // Blocks callback
  signalNext();
}
```

**Why**: Observer callbacks should be lightweight (extract data, update UI). Heavy processing blocks `signalNext()`, preventing observer from delivering next update. Offload heavy work to async operations outside callback.

**Guidelines**:
- Extract data: ✅ Lightweight
- Update UI: ✅ Lightweight
- Complex computation: ❌ Offload
- Network calls: ❌ Offload
- File I/O: ❌ Offload

**See**: [examples/observer-backpressure.dart](examples/observer-backpressure.dart)

---

### 4. Unnecessary Delta Creation (Priority: HIGH)

**Platform**: All platforms

**Problem**: Updating fields with the same value creates deltas and sync traffic. Ditto treats even unchanged values as updates, syncing them across the mesh.

**Detection**:
```dart
// RED FLAGS
final currentStatus = 'pending';
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'pending'}, // Same value!
);
// Even though value unchanged, Ditto creates delta and syncs
```

**✅ DO**:
```dart
// Check value before updating
final orderResult = await ditto.store.execute(
  'SELECT status FROM orders WHERE _id = :orderId',
  arguments: {'orderId': orderId},
);
final currentStatus = orderResult.items.first.value['status'];
final newStatus = 'completed';

if (currentStatus != newStatus) {
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': newStatus},
  );
} // Only update if value actually changed

// Alternative: Use DO UPDATE_LOCAL_DIFF (SDK 4.12+)
// Automatically avoids syncing unchanged fields
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed - will sync
      'customerId': 'customer_456', // Unchanged - won't sync
      'items': [...],               // Unchanged - won't sync
      'completedAt': DateTime.now().toIso8601String(), // Changed - will sync
    },
  },
);
// Only 'status' and 'completedAt' sync as deltas
```

**❌ DON'T**:
```dart
// Update without checking value
await ditto.store.execute(
  'UPDATE orders SET status = :status WHERE _id = :orderId',
  arguments: {'orderId': orderId, 'status': 'pending'},
);
// Creates delta even if status already 'pending'

// Full document replacement with DO UPDATE
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed
      'customerId': 'customer_456', // Unchanged - but still synced!
      'items': [...],               // Unchanged - but still synced!
    },
  },
);
// ALL fields treated as updated (unnecessary sync traffic)
```

**Why**: Even updating a field with the same value is treated as a delta and synced to other peers. Always check if values have changed before issuing UPDATE statements. DO UPDATE_LOCAL_DIFF (SDK 4.12+) automatically handles this by comparing values before creating deltas.

**Sync Traffic Impact**:
```dart
// BAD: Update 1000 orders without checking values
// 80% already have target status
// Result: 800 unnecessary deltas synced across mesh

// GOOD: Check before update
// Only 200 orders actually change
// Result: 200 deltas synced (75% bandwidth saved)
```

**See**: [examples/unnecessary-deltas-good.dart](examples/unnecessary-deltas-good.dart)

---

### 5. DO UPDATE vs DO UPDATE_LOCAL_DIFF (Priority: HIGH - SDK 4.12+)

**Platform**: All platforms (SDK 4.12+)

**Problem**: Using `ON ID CONFLICT DO UPDATE` syncs ALL fields as deltas, even unchanged ones. `DO UPDATE_LOCAL_DIFF` only syncs fields that actually differ.

**Detection**:
```dart
// SUBOPTIMAL (SDK 4.12+)
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed
      'customerId': 'customer_456', // Unchanged
      'items': [...],               // Unchanged
      'completedAt': DateTime.now().toIso8601String(), // Changed
    },
  },
);
// ALL fields synced, even unchanged ones
```

**✅ DO (SDK 4.12+)**:
```dart
// Use DO UPDATE_LOCAL_DIFF to avoid syncing unchanged fields
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
  arguments: {
    'order': {
      '_id': 'order_123',
      'status': 'completed',        // Changed - will sync
      'customerId': 'customer_456', // Unchanged - won't sync
      'items': [...],               // Unchanged - won't sync
      'completedAt': DateTime.now().toIso8601String(), // Changed - will sync
    },
  },
);
// Only 'status' and 'completedAt' fields sync as deltas
// 'customerId' and 'items' not synced (no unnecessary deltas)
```

**❌ DON'T**:
```dart
// Use DO UPDATE when fields haven't changed
await ditto.store.execute(
  'INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE',
  arguments: {'order': {...}},
);
// All fields synced regardless of change

// Pre-SDK 4.12: No DO UPDATE_LOCAL_DIFF available
// Must check values manually before UPDATE
```

**Why**: `DO UPDATE_LOCAL_DIFF` automatically compares incoming document with existing document and only creates deltas for fields that differ. More efficient than `DO UPDATE` (syncs all fields) and easier than manual value checking.

**Conflict Resolution Options** (SDK 4.12+):

| Option | Behavior |
|--------|----------|
| `DO UPDATE` | Updates all fields, syncs all fields as deltas |
| `DO UPDATE_LOCAL_DIFF` | Only updates and syncs fields that differ |
| `DO NOTHING` | Ignores conflict, keeps existing document |
| `FAIL` | Throws error on conflict (default) |

**See**: [examples/unnecessary-deltas-good.dart](examples/unnecessary-deltas-good.dart)

---

### 6. Log Level Not Set Before Init (Priority: HIGH)

**Platform**: All platforms

**Problem**: Setting log level after `Ditto.open()` misses critical startup diagnostics (auth issues, file system errors, initialization failures).

**Detection**:
```dart
// RED FLAGS
final ditto = await Ditto.open(identity: ...);

// Log level set AFTER init - missed startup diagnostics!
DittoLogger.minimumLogLevel = DittoLogLevel.debug;
```

**✅ DO**:
```dart
// Set log level BEFORE Ditto.open()
DittoLogger.minimumLogLevel = kDebugMode
    ? DittoLogLevel.debug
    : DittoLogLevel.warning;

// Configure rotating log files (optional)
DittoLogger.setRotatingLogFileConfiguration(
  directory: await getApplicationDocumentsDirectory(),
  maxFileSize: 10 * 1024 * 1024, // 10 MB
  maxFileCount: 5,
);

// Now initialize Ditto
final ditto = await Ditto.open(identity: ...);

// Startup diagnostics captured in logs
```

**❌ DON'T**:
```dart
// Log level after init
final ditto = await Ditto.open(identity: ...);
DittoLogger.minimumLogLevel = DittoLogLevel.debug;
// Missed auth errors, file system issues, initialization failures

// No environment differentiation
DittoLogger.minimumLogLevel = DittoLogLevel.debug; // Always debug
// Production apps should use warning or error

// No rotating log configuration
// Logs grow unbounded, fill storage
```

**Why**: Ditto initialization performs critical setup (authentication, file system checks, network configuration). Setting log level before `Ditto.open()` captures startup diagnostics essential for debugging issues.

**Log Levels**:
- **debug**: Verbose logging (development only)
- **info**: Informational messages
- **warning**: Potential issues (production default)
- **error**: Errors only (production alternative)

**Development vs Production**:
```dart
DittoLogger.minimumLogLevel = kDebugMode
    ? DittoLogLevel.debug      // Development: verbose
    : DittoLogLevel.warning;   // Production: minimal
```

**See**: [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart)

---

### 7. Broad Subscription Scope (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Subscriptions without WHERE clauses or with overly broad filters waste bandwidth, storage, and battery by syncing unnecessary data.

**Balance Required**: Too broad wastes resources, too narrow breaks multi-hop relay (intermediate peers don't store/relay documents they don't subscribe to).

**Detection**:
```dart
// RED FLAGS
// Too broad - all orders
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders', // No WHERE clause
);

// Too narrow - breaks multi-hop relay
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE priority = :priority',
  arguments: {'priority': 'high'}, // Intermediate peers won't relay 'low' priority
);
```

**✅ DO**:
```dart
// Balanced: Subscribe to all user's orders
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',
  arguments: {'customerId': customerId},
);

// Filter in observer, not subscription (for display)
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE customerId = :customerId AND status = :status',
  onChange: (result, signalNext) {
    updateUI(result.items); // Only active orders displayed
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
  arguments: {'customerId': customerId, 'status': 'active'},
);

// For logical deletion: Subscribe to all, filter in observer
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM orders WHERE customerId = :customerId',
  arguments: {'customerId': customerId},
);

final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM orders WHERE customerId = :customerId AND isDeleted != true',
  onChange: (result, signalNext) {
    updateUI(result.items); // Deleted orders filtered out
    WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
  },
  arguments: {'customerId': customerId},
);
```

**❌ DON'T**:
```dart
// Too broad
final subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
// Syncs all orders from all customers - wastes bandwidth

// Too narrow with state transitions
final subscription = ditto.sync.registerSubscription(
  'SELECT * FROM tasks WHERE completed != true',
);
// When task marked complete, stops syncing updates to that task
// Better: Subscribe to all user's tasks, filter completed in observer
```

**Why**: Broad subscriptions sync unnecessary data (bandwidth, storage, battery). Too narrow subscriptions break multi-hop relay (intermediate peers don't store/relay documents outside their subscription). Balance: subscribe to reasonable scope, filter in observers for display.

**Decision Framework**:

| Question | If YES → Subscribe Broadly |
|----------|----------------------------|
| Can documents change over time? | ✓ |
| Need updates after initial creation? | ✓ |
| Documents transition between states? | ✓ |
| Use logical deletion? | ✓ |

**See**: [.claude/guides/best-practices/ditto.md lines 2362-2511](../../guides/best-practices/ditto.md)

---

### 8. Observer Backpressure Buildup (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Not calling `signalNext()` promptly causes callback queue buildup. In high-frequency scenarios (IoT sensors, real-time tracking), callbacks accumulate faster than processing, exhausting memory.

**Detection**:
```dart
// RED FLAGS
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data',
  onChange: (result, signalNext) {
    final data = result.items.map((item) => item.value).toList();

    // Heavy processing before signalNext()
    processAllData(data); // Takes 5 seconds
    updateUI(data);

    signalNext(); // Delayed by 5 seconds - callbacks accumulate
  },
);
// In high-frequency updates: 10+ callbacks accumulate = memory exhaustion
```

**✅ DO**:
```dart
// Lightweight callback, signal promptly
final observer = ditto.store.registerObserverWithSignalNext(
  'SELECT * FROM sensor_data WHERE deviceId = :deviceId',
  onChange: (result, signalNext) {
    // Extract data immediately (lightweight)
    final data = result.items.map((item) => item.value).toList();

    // Update UI immediately (lightweight)
    updateUI(data);

    // Offload heavy processing
    _processSensorDataAsync(data);

    // Signal readiness immediately (Flutter)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalNext();
    });
  },
  arguments: {'deviceId': 'sensor_123'},
);

Future<void> _processSensorDataAsync(List<Map<String, dynamic>> data) async {
  // Heavy processing runs independently, doesn't block observer
  await analyzeData(data);
  await storeToDatabase(data);
}
```

**❌ DON'T**:
```dart
// Long processing before signalNext()
onChange: (result, signalNext) {
  final data = result.items.map((item) => item.value).toList();

  // Heavy sync processing blocks signalNext()
  for (var item in data) {
    heavyComputation(item); // Blocks
  }

  signalNext(); // Delayed - callbacks accumulate
}

// No signalNext() at all
onChange: (result, signalNext) {
  updateUI(result.items);
  // Missing signalNext() - observer blocked permanently
}
```

**Why**: High-frequency updates (multiple per second) generate callbacks faster than processing in many scenarios. Not calling `signalNext()` promptly causes callback queue buildup → memory exhaustion → crashes. Keep callbacks lightweight, signal promptly.

**Guidelines**:
- Extract data: < 1ms
- Update UI: < 16ms (Flutter frame budget)
- Call signalNext(): Immediately after render (Flutter), immediately after extract (non-Flutter)

**See**: [examples/observer-backpressure.dart](examples/observer-backpressure.dart)

---

### 9. Partial UI Update Patterns (Priority: MEDIUM - Flutter)

**Platform**: Flutter/Dart only

**Problem**: Full widget tree rebuilds when only specific items changed. Use `DittoDiffer`, `ValueKey`, or state management for efficient list updates.

**Detection**:
```dart
// SUBOPTIMAL (Flutter)
class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        setState(() {
          orders = result.items.map((item) => item.value).toList();
        });
        // Full list rebuilds even if only one order changed
        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }
}
```

**✅ DO (Flutter - DittoDiffer)**:
```dart
class _OrderListScreenState extends State<OrderListScreen> {
  List<Map<String, dynamic>> orders = [];
  final differ = DittoDiffer();
  late DittoStoreObserver observer;

  @override
  void initState() {
    super.initState();
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders',
      onChange: (result, signalNext) {
        // Calculate which documents changed
        final changeSummary = differ.computeChanges(result.items);

        if (changeSummary.hasChanges) {
          setState(() {
            orders = result.items.map((item) => item.value).toList();
          });

          // Optional: Log which orders changed for debugging
          print('Inserted: ${changeSummary.insertions.length}');
          print('Updated: ${changeSummary.updates.length}');
          print('Deleted: ${changeSummary.deletions.length}');
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          // Use unique key for efficient list updates
          return OrderCard(
            key: ValueKey(order['_id']),
            order: order,
          );
        },
      ),
    );
  }
}
```

**❌ DON'T (Flutter)**:
```dart
// No ValueKey - Flutter rebuilds all items
return OrderCard(order: order); // No key

// DittoDiffer without ValueKey
final changeSummary = differ.computeChanges(result.items);
setState(() {
  orders = result.items.map((item) => item.value).toList();
});
// DittoDiffer alone doesn't help without ValueKey
```

**Why**: `DittoDiffer` tracks document versions between callbacks, identifying insertions/updates/deletions. Flutter's reconciliation uses `ValueKey` to update only changed items. Unchanged list items reuse existing widget instances (efficient).

**How It Works**:
1. DittoDiffer identifies changed documents
2. Flutter uses ValueKey to match widgets to data
3. Only new/updated/deleted items rebuild
4. Unchanged items reuse existing widgets (no rebuild)

**See**: [examples/partial-ui-updates.dart](examples/partial-ui-updates.dart)

---

### 10. Rotating Log File Configuration (Priority: LOW)

**Platform**: All platforms

**Problem**: Default log settings may not suit long-running apps. Logs grow unbounded, filling storage.

**Detection**:
```dart
// SUBOPTIMAL
DittoLogger.minimumLogLevel = DittoLogLevel.debug;
final ditto = await Ditto.open(identity: ...);
// No rotating log configuration - logs grow unbounded
```

**✅ DO**:
```dart
// Configure rotating logs before init
DittoLogger.minimumLogLevel = kDebugMode
    ? DittoLogLevel.debug
    : DittoLogLevel.warning;

// Configure rotating log files
final docsDir = await getApplicationDocumentsDirectory();
DittoLogger.setRotatingLogFileConfiguration(
  directory: docsDir,
  maxFileSize: 10 * 1024 * 1024, // 10 MB per file
  maxFileCount: 5,                // Keep 5 files max (50 MB total)
);

// Custom settings for long-running apps
DittoLogger.setRotatingLogFileConfiguration(
  directory: docsDir,
  maxFileSize: 5 * 1024 * 1024,  // 5 MB per file
  maxFileCount: 10,               // Keep 10 files (50 MB total)
);

final ditto = await Ditto.open(identity: ...);
```

**❌ DON'T**:
```dart
// No log rotation
// Logs grow indefinitely, fill storage

// Excessive log retention
DittoLogger.setRotatingLogFileConfiguration(
  directory: docsDir,
  maxFileSize: 100 * 1024 * 1024, // 100 MB per file
  maxFileCount: 100,               // 10 GB total!
);
// Wastes storage
```

**Why**: Rotating log files prevent unbounded growth. Default settings may not suit app requirements. Configure before `Ditto.open()` based on app needs (storage constraints, debug requirements).

**Recommendations**:
- **Development**: 10 MB × 5 files = 50 MB
- **Production**: 5 MB × 3 files = 15 MB
- **Long-running**: 10 MB × 10 files = 100 MB

**See**: [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart)

---

### 9. DISTINCT Memory Impact (Priority: HIGH)

**Platform**: All platforms

**Problem**: `DISTINCT` buffers all result rows in memory to enforce uniqueness. Using `DISTINCT` with `_id` (already unique) or on unbounded datasets causes high memory usage and can crash mobile devices.

**Detection**:
```dart
// RED FLAGS
// DISTINCT with _id (redundant)
final result = await ditto.store.execute(
  'SELECT DISTINCT _id, color FROM cars',
);

// DISTINCT on unbounded dataset
final result = await ditto.store.execute(
  'SELECT DISTINCT customerId FROM orders',
);
// Can crash if millions of orders
```

**✅ DO**:
```dart
// ✅ GOOD: DISTINCT on small, filtered result set
final result = await ditto.store.execute(
  'SELECT DISTINCT color FROM cars WHERE year >= :year',
  arguments: {'year': 2020},
);

// ✅ GOOD: Omit DISTINCT when selecting _id
final result = await ditto.store.execute(
  'SELECT _id, color FROM cars WHERE year >= :year',
  arguments: {'year': 2020},
);
```

**Why**: When `_id` is in projections, results are already unique—`DISTINCT` adds no value but buffers all rows in memory. On mobile devices with limited memory, this can cause crashes.

**See**: `.claude/guides/best-practices/ditto.md (lines 626-652: DISTINCT Keyword)`, `.claude/skills/ditto/query-sync/SKILL.md#10-distinct-with-_id-priority-high`

---

### 10. Aggregate Function Memory Impact (Priority: CRITICAL)

**Platform**: All platforms

**Problem**: Aggregate functions (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`) buffer all matching documents in memory before returning results. Unbounded aggregates can crash mobile devices.

**Detection**:
```dart
// RED FLAGS
// No WHERE filter - buffers all documents
await ditto.store.execute('SELECT COUNT(*) FROM orders');

// Aggregate in high-frequency observer
final observer = ditto.store.registerObserver(
  'SELECT COUNT(*) AS total FROM orders', // Buffers all on each update
  onChange: (result) {
    updateTotalCount(result.items.first.value['total']);
  },
);
```

**✅ DO**:
```dart
// ✅ GOOD: Filtered aggregate
final result = await ditto.store.execute(
  '''SELECT COUNT(*) AS count, AVG(total) AS avg
     FROM orders
     WHERE status = :status AND createdAt >= :cutoff''',
  arguments: {
    'status': 'active',
    'cutoff': DateTime.now().subtract(Duration(days: 30)).toIso8601String(),
  },
);

// ✅ GOOD: GROUP BY in observer (bounded result)
final observer = ditto.store.registerObserver(
  '''SELECT status, COUNT(*) AS count
     FROM orders
     WHERE createdAt >= :cutoff
     GROUP BY status''',
  onChange: (result) {
    // Result set bounded by unique statuses (typically small)
    updateStats(result.items);
  },
  arguments: {
    'cutoff': DateTime.now().subtract(Duration(days: 7)).toIso8601String(),
  },
);

// ✅ BETTER: Use LIMIT 1 for existence checks
final hasActive = (await ditto.store.execute(
  'SELECT _id FROM orders WHERE status = :status LIMIT 1',
  arguments: {'status': 'active'},
)).items.isNotEmpty;
```

**Why**: Aggregates create a "dam" in the pipeline—all matching documents buffer in memory before results return. For 100k+ documents, this causes crashes on mobile. `LIMIT 1` returns immediately after first match with minimal memory.

**Memory Impact**:
- `COUNT(*)` on 100k orders: ~10-50MB buffered depending on document size
- `LIMIT 1` existence check: Minimal memory, returns after first match
- `GROUP BY`: Result bounded by unique group values (typically small)

**See**: `.claude/guides/best-practices/ditto.md (lines 655-691: Aggregate Functions)`, `.claude/skills/ditto/query-sync/SKILL.md#11-unbounded-aggregates-priority-critical`

---

### 11. Large OFFSET Performance (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Large `OFFSET` values degrade performance linearly—Ditto must skip all offset documents sequentially before returning results.

**Detection**:
```dart
// RED FLAG
final result = await ditto.store.execute(
  'SELECT * FROM orders LIMIT 20 OFFSET 10000',
);
// Must skip 10,000 documents - slow!
```

**✅ DO**:
```dart
// ✅ GOOD: Small OFFSET for pagination
final result = await ditto.store.execute(
  'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 40',
);

// ✅ BETTER: Cursor-based pagination for deep pages
final result = await ditto.store.execute(
  '''SELECT * FROM orders
     WHERE createdAt < :cursor
     ORDER BY createdAt DESC
     LIMIT 20''',
  arguments: {'cursor': lastSeenTimestamp},
);
```

**Why**: `OFFSET` requires sequential skipping. For deep pagination, cursor-based approaches (WHERE with timestamp/ID) provide consistent performance regardless of depth.

**Performance**:
- OFFSET 10: ~instant
- OFFSET 100: acceptable
- OFFSET 1000: noticeable delay
- OFFSET 10000: significant degradation
- Cursor-based: consistent regardless of depth

**See**: `.claude/guides/best-practices/ditto.md (lines 778-807: LIMIT and OFFSET)`, `.claude/skills/ditto/query-sync/SKILL.md#13-large-offset-values-priority-medium`

---

### 12. Operator Performance in Observers (Priority: MEDIUM)

**Platform**: All platforms

**Problem**: Using expensive operators (object introspection, regex, type checking) in high-frequency observer queries degrades performance and causes cumulative overhead.

**Detection**:
```dart
// RED FLAGS
// Object introspection in observer
final observer = ditto.store.registerObserver(
  'SELECT * FROM products WHERE object_length(metadata) > :threshold',
  onChange: (result) {
    updateUI(result.items);
  },
  arguments: {'threshold': 10},
);

// Regex in observer
final observer = ditto.store.registerObserver(
  'SELECT * FROM users WHERE regexp_like(email, :pattern)',
  onChange: (result) {
    updateUI(result.items);
  },
  arguments: {'pattern': '^[a-z]+@.*'},
);

// Type checking on full collection
final observer = ditto.store.registerObserver(
  'SELECT * FROM documents WHERE type(field) = :expectedType',
  onChange: (result) {
    updateUI(result.items);
  },
  arguments: {'expectedType': 'string'},
);
```

**✅ DO (Simple operators in observer WHERE, filter in app)**:
```dart
// Filter with simple operators, complex logic in app
final observer = ditto.store.registerObserver(
  'SELECT * FROM products WHERE category = :category',
  onChange: (result) {
    // Complex filtering in app code if needed
    final filtered = result.items.where((item) {
      final metadata = item.value['metadata'] as Map?;
      return metadata != null && metadata.length > 10;
    }).toList();
    updateUI(filtered);
  },
  arguments: {'category': 'electronics'},
);

// Index-friendly operators in observer
final observer = ditto.store.registerObserver(
  'SELECT * FROM users WHERE email LIKE :prefix',
  onChange: (result) {
    updateUI(result.items);
  },
  arguments: {'prefix': 'admin%'},
);

// Date operators acceptable (SDK 4.11+ optimized)
final observer = ditto.store.registerObserver(
  'SELECT * FROM orders WHERE createdAt >= date_sub(clock(), :days, :unit)',
  onChange: (result) {
    updateRecentOrders(result.items);
  },
  arguments: {'days': 7, 'unit': 'day'},
);
```

**❌ DON'T**:
```dart
// Object introspection in observer (expensive)
final observer = ditto.store.registerObserver(
  'SELECT * FROM products WHERE :key IN object_keys(metadata)',
  onChange: (result) {
    updateUI(result.items);
  },
  arguments: {'key': 'someKey'},
);

// Complex patterns in observer
final observer = ditto.store.registerObserver(
  'SELECT * FROM files WHERE filename SIMILAR TO :pattern',
  onChange: (result) {
    updateUI(result.items);
  },
  arguments: {'pattern': '%(%.jpg|%.png|%.gif)'},
);
```

**Why**: Observers fire frequently on data changes. Expensive operators on every callback cause cumulative performance degradation. Keep observer queries simple with index-friendly operators, perform complex filtering in application code.

**Performance Hierarchy** (fast → slow):
1. **Index scans** with simple comparisons (=, <, >, IN with small lists)
2. **String prefix matching** (LIKE 'prefix%', starts_with)
3. **IN operator** with small lists (<50 values)
4. **Date operators** (date_cast, date_add, etc.) - SDK 4.11+ optimized
5. **Conditional operators** (coalesce, nvl, decode) - minimal overhead
6. **Type checking** operators (is_number, is_string, type)
7. **Object introspection** (object_keys, object_values) - very expensive
8. **Advanced patterns** (SIMILAR TO, regexp_like) - very expensive

**Best Practices**:
- Use WHERE filters with simple operators in observer queries
- Offload complex filtering to application code
- Prefer index-friendly operators (LIKE 'prefix%', IN, simple comparisons)
- Date operators acceptable (negligible overhead in SDK 4.11+)
- Avoid object_keys, object_values, SIMILAR TO, type() in observers

**See Also**: `.claude/guides/best-practices/ditto.md (lines 1569-1625: Operator Performance Considerations)`, `.claude/skills/ditto/query-sync/SKILL.md#14-expensive-operator-usage-priority-medium`

---

## Quick Reference Checklist

### Observer Performance (Flutter)
- [ ] Use state management (Riverpod) not setState() on entire screen
- [ ] Implement granular widget rebuilds (family providers, selectors)
- [ ] Use ValueListenableBuilder for simpler scoped rebuilds
- [ ] Use DittoDiffer with ValueKey for efficient list updates
- [ ] Avoid full screen rebuilds in observer callbacks

### Observer Performance (All Platforms)
- [ ] **Non-Flutter SDKs**: Prefer `registerObserverWithSignalNext` (better backpressure control)
- [ ] **Non-Flutter SDKs**: Always call `signalNext()` after processing observer updates
- [ ] **Flutter SDK v4.x**: Use `registerObserver` (only option until v5.0, no backpressure control)
- [ ] **Flutter SDK v5.0+**: Will support `registerObserverWithSignalNext`
- [ ] Extract data immediately from QueryResultItems (lightweight operation)
- [ ] Offload heavy processing to async operations outside callback
- [ ] Keep observer callbacks lightweight (< 16ms for Flutter)
- [ ] **Legacy observeLocal Migration**: See [Replacing observeLocal](../../guides/best-practices/ditto.md#replacing-legacy-observelocal-with-store-observers-sdk-412) for Differ pattern (non-Flutter SDKs)

### Sync Optimization
- [ ] Check value before UPDATE to avoid unnecessary deltas
- [ ] Use DO UPDATE_LOCAL_DIFF (SDK 4.12+) for upsert operations
- [ ] Use field-level UPDATE instead of document replacement
- [ ] Balance subscription scope (not too broad, not too narrow)
- [ ] Filter in observers, subscribe broadly (for multi-hop relay)

### Memory Management (Query Performance)
- [ ] Not using `DISTINCT` with `_id` field (redundant, wastes memory)
- [ ] Using `DISTINCT` only on small, filtered result sets
- [ ] Filtering with `WHERE` before aggregate functions (reduces memory buffer)
- [ ] Not using unbounded aggregates (can crash on 100k+ documents)
- [ ] Using `GROUP BY` in observers to reduce result set size
- [ ] Using `LIMIT 1` for existence checks (not `COUNT(*)`)
- [ ] Avoiding large `OFFSET` values (> 1000) - use cursor-based pagination
- [ ] Not using aggregates in high-frequency observers without filters

### Logging Configuration
- [ ] Set log level BEFORE Ditto.open() to capture startup diagnostics
- [ ] Use different log levels for development vs production
- [ ] Configure rotating log files to prevent unbounded growth
- [ ] Use descriptive log levels (debug: development, warning: production)
- [ ] Monitor log file sizes in long-running apps

### Backpressure Management (Non-Flutter SDKs Only)
- [ ] **Non-Flutter SDKs**: Call signalNext() promptly to prevent callback queue buildup
- [ ] **Flutter SDK v4.x**: No backpressure control (signalNext unavailable until v5.0)
- [ ] Don't block observer callbacks with heavy processing
- [ ] Offload heavy operations to background async tasks

---

## See Also

### Main Guide
- Observer Patterns: [.claude/guides/best-practices/ditto.md lines 1639-1848](../../guides/best-practices/ditto.md)
- Partial UI Updates: [.claude/guides/best-practices/ditto.md lines 1851-2217](../../guides/best-practices/ditto.md)
- Performance Best Practices: [.claude/guides/best-practices/ditto.md lines 2332-2511](../../guides/best-practices/ditto.md)
- Unnecessary Deltas: [.claude/guides/best-practices/ditto.md lines 1103-1129](../../guides/best-practices/ditto.md)

### Other Skills
- [query-sync](../query-sync/SKILL.md) - Observer selection and subscription patterns
- [data-modeling](../data-modeling/SKILL.md) - Field-level updates to minimize deltas
- [storage-lifecycle](../storage-lifecycle/SKILL.md) - Performance impact of storage management

### Examples
- [examples/flutter-state-management-good.dart](examples/flutter-state-management-good.dart) - Riverpod granular rebuilds
- [examples/flutter-state-management-bad.dart](examples/flutter-state-management-bad.dart) - Full screen setState anti-patterns
- [examples/unnecessary-deltas-good.dart](examples/unnecessary-deltas-good.dart) - Value checks and DO UPDATE_LOCAL_DIFF
- [examples/unnecessary-deltas-bad.dart](examples/unnecessary-deltas-bad.dart) - Delta generation anti-patterns
- [examples/logging-configuration-good.dart](examples/logging-configuration-good.dart) - Proper logging setup
- [examples/logging-configuration-bad.dart](examples/logging-configuration-bad.dart) - Logging anti-patterns
- [examples/observer-backpressure.dart](examples/observer-backpressure.dart) - Backpressure control and signalNext timing
- [examples/partial-ui-updates.dart](examples/partial-ui-updates.dart) - DittoDiffer and ValueKey usage

### Reference
- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Riverpod Documentation](https://riverpod.dev/docs/concepts/reading)
- [Ditto Read Documentation](https://docs.ditto.live/sdk/latest/crud/read)
