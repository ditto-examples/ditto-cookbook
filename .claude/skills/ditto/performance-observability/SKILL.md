---
name: performance-observability
description: |
  Validates Ditto observer performance patterns, UI optimization, and logging configuration.

  CRITICAL ISSUES PREVENTED:
  - Full-screen rebuilds in observer callbacks (Flutter)
  - Missing signalNext() calls blocking further updates (non-Flutter)
  - Heavy processing in observer callbacks blocking UI
  - Unnecessary delta sync from unchanged value updates
  - Missing startup diagnostics from late log level configuration
  - Observer backpressure buildup causing memory issues
  - Aggregate function memory impact (unbounded COUNT, SUM)

  TRIGGERS:
  - Implementing observer callbacks (registerObserver*)
  - Optimizing UI performance and widget rebuilds (Flutter)
  - Configuring logging with DittoLogger
  - Managing subscription scope and query optimization
  - Handling backpressure with signalNext() (non-Flutter)
  - Preventing unnecessary sync traffic and delta generation

  PLATFORMS: Flutter (Dart - UI patterns), JavaScript, Swift, Kotlin (observer + logging)
---

# Ditto Performance and Observability

## Table of Contents

- [Purpose](#purpose)
- [When This Skill Applies](#when-this-skill-applies)
- [Platform Detection](#platform-detection)
- [SDK Version Compatibility](#sdk-version-compatibility)
- [Common Workflows](#common-workflows)
- [Critical Patterns](#critical-patterns)
  - [1. Full Screen setState() in Observer](#1-full-screen-setstate-in-observer-critical---flutter)
  - [2. Missing signalNext() Call](#2-missing-signalnext-call-critical---non-flutter-sdks-only)
  - [3. Heavy Processing in Observer Callbacks](#3-heavy-processing-in-observer-callbacks-high)
  - [4. Aggregate Function Memory Impact](#4-aggregate-function-memory-impact-critical)
- [Quick Reference Checklist](#quick-reference-checklist)
- [See Also](#see-also)

---

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

## SDK Version Compatibility

This section consolidates all version-specific information referenced throughout this Skill.

### Observer Patterns

**Flutter SDK**:
- **v4.x** (current stable)
  - `registerObserver` only (no `signalNext` support)
  - Stream-based API via `observer.changes` (recommended)
  - `onChange` callback API available
  - WidgetsBinding.addPostFrameCallback() for UI updates

- **v5.0+** (upcoming)
  - `registerObserverWithSignalNext` support added
  - All v4.x patterns continue to work

**Non-Flutter SDKs**:
- **All versions**: `registerObserverWithSignalNext` recommended
  - Backpressure control via `signalNext()` callback
  - Call `signalNext()` after processing each update
  - Missing `signalNext()` call blocks further updates

### Performance Features

**SDK 4.12+**:
- `DO UPDATE_LOCAL_DIFF` available for efficient updates
- Only changed fields create sync deltas (vs full document replacement)
- Recommended for frequent field updates

**All SDK Versions**:
- Log level configuration: Must be set before Ditto init
- Observer callback performance: Keep lightweight (all platforms)
- Aggregate functions (COUNT, SUM, AVG): Memory impact considerations
- DISTINCT operator: Memory overhead for large result sets

**Throughout this Skill**: Observer patterns differ between Flutter (Stream-based, v4.x) and non-Flutter (signalNext-based). Performance optimizations are universal.

---

## Common Workflows

### Workflow 1: Optimizing Observer Performance (Flutter)

```
Flutter Observer Optimization:
- [ ] Step 1: Use partial UI updates (not full screen setState())
- [ ] Step 2: Keep observer callbacks lightweight
- [ ] Step 3: Use WidgetsBinding.addPostFrameCallback() for setState()
- [ ] Step 4: Consider state management (Riverpod/Provider)
- [ ] Step 5: Profile UI performance
```

```dart
// ✅ GOOD: Partial UI update with Riverpod
final ordersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final observer = ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'pending'},
  );

  return observer.changes.map((result) =>
    result.items.map((item) => item.value).toList()
  );
});

// Widget automatically rebuilds only when data changes
class OrdersList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return orders.when(
      data: (data) => ListView.builder(...),
      loading: () => CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }
}
```

---

### Workflow 2: Configuring Logging for Debugging

```
Logging Configuration:
- [ ] Step 1: Set log level BEFORE Ditto.open()
- [ ] Step 2: Choose appropriate level (debug, info, warning, error)
- [ ] Step 3: Enable rotating log files (optional)
- [ ] Step 4: Test with verbose logging
- [ ] Step 5: Reduce to warning/error for production
```

```dart
// CRITICAL: Set log level BEFORE Ditto.open()
DittoLogger.minimumLogLevel = DittoLogLevel.debug;

// Optional: Enable file logging
DittoLogger.enabled = true;
DittoLogger.setLogFileURL('/path/to/logs');

final ditto = await Ditto.open(identity);
```

---

## Critical Patterns

This section contains only the most critical (Tier 1) patterns that prevent performance issues and memory problems. For additional optimization patterns, see:
- **[reference/optimization-patterns.md](reference/optimization-patterns.md)**: Additional HIGH/MEDIUM/LOW priority patterns (delta creation, DO UPDATE_LOCAL_DIFF, log configuration, subscription scope, backpressure, UI updates, DISTINCT, OFFSET, operator performance)

### 1. Full Screen setState() in Observer (CRITICAL - Flutter)

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

**See**: [examples/observer-backpressure.dart](examples/observer-backpressure.dart), [reference/optimization-patterns.md](reference/optimization-patterns.md) for additional patterns

---

### 4. Aggregate Function Memory Impact (CRITICAL)

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
