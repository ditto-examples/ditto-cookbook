// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter
// Last Updated: 2026-10-08
//
// ============================================================================
// Observer Backpressure in Flutter (SDK 5.1+, Experimental)
// ============================================================================
//
// Guide sections (../../guide/reference/ditto.md):
// - § Backpressure (SDK 5.1+)
// - § registerObserverV2 (Experimental)
// - § registerObserverWithSignalNext (Experimental)
// - § Choosing an observer API
//
// registerObserverV2 and registerObserverWithSignalNext are marked
// @experimental in ditto_live 5.1.0 and may change in a future release. Both
// return a StoreObserverV2. While your code is busy, Ditto holds back further
// updates and later delivers the latest state, so intermediate results are
// merged instead of queued. For widgets that only copy values and call
// setState, the stable registerObserver remains the default
// (see flutter-observer-performance.dart).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ registerObserverV2 + await for (automatic backpressure)
// 2. ✅ registerObserverV2 with a paused/resumed StreamSubscription
// 3. ✅ registerObserverWithSignalNext + signalNext() in finally
// 4. ✅ Signalling after work that completes elsewhere (next frame)
// 5. ❌ signalNext() skipped when the work throws
// 6. ❌ onChange only on registerObserverWithSignalNext (results also queued)
// 7. ❌ Pausing the stream of a signal-next observer
//
// ============================================================================

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

// ============================================================================
// PATTERN 1: registerObserverV2 + await for (Experimental)
// ============================================================================

/// ✅ GOOD: One update at a time. `await for` pauses its subscription while
/// the loop body runs, and registerObserverV2 follows pause and resume, so
/// slow async work applies backpressure without extra code.
/// While the body runs, Ditto holds back further updates and later delivers
/// the latest state, so intermediate states are merged.
class SensorAggregator {
  SensorAggregator(this._ditto);

  final Ditto _ditto;
  StoreObserverV2? _observer;

  Future<void> run(
    String deviceId,
    Future<void> Function(List<Map<String, dynamic>> readings) persistAggregates,
  ) async {
    stop(); // Cancel a previous run, if any.
    final observer = _ditto.store.registerObserverV2(
      'SELECT * FROM sensorReadings WHERE deviceId = :deviceId '
      'ORDER BY recordedAt DESC LIMIT 100',
      arguments: {'deviceId': deviceId},
    );
    _observer = observer;
    // Leaving the loop (break, return, exception) cancels the stream
    // subscription, which also cancels a StoreObserverV2.
    await for (final result in observer.changes) {
      await persistAggregates(result.items.map((item) => item.value).toList());
    }
    // The loop ends when stop() cancels the observer.
  }

  void stop() => _observer?.cancel();
}

// ============================================================================
// PATTERN 2: registerObserverV2 with an explicit pause/resume (Experimental)
// ============================================================================

/// ✅ GOOD: The same automatic backpressure without `await for`: pause the
/// subscription while work is in flight and resume it afterwards.
class OrderExporter {
  OrderExporter(this._ditto, this._export);

  final Ditto _ditto;
  final Future<void> Function(List<Map<String, dynamic>> orders) _export;
  StoreObserverV2? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    final observer = _ditto.store.registerObserverV2(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      arguments: {'status': 'completed'},
    );
    _observer = observer;
    late final StreamSubscription<QueryResult> subscription;
    subscription = observer.changes.listen((result) {
      final orders = result.items.map((item) => item.value).toList();
      subscription.pause(); // Ditto holds back further updates while paused.
      unawaited(_export(orders).catchError(showError).whenComplete(subscription.resume));
    });
    _changes = subscription;
  }

  void stop() {
    unawaited(_changes?.cancel());
    _observer?.cancel();
  }
}

// ============================================================================
// PATTERN 3: registerObserverWithSignalNext (Experimental)
// ============================================================================

/// ✅ GOOD: Consume `changes` (no onChange) and call signalNext() in finally.
/// If signalNext() is never called, the observer stops delivering updates.
class OpenOrdersUploader {
  OpenOrdersUploader(this._ditto, this._upload);

  final Ditto _ditto;
  final Future<void> Function(List<Map<String, dynamic>> orders) _upload;
  StoreObserverV2? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    stop(); // Cancel a previous start, if any.
    final observer = _ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      arguments: {'status': 'open'},
    );
    _observer = observer;
    _changes = observer.changes.listen((result) {
      final orders = result.items.map((item) => item.value).toList();
      unawaited(_handle(orders, observer.signalNext));
    });
  }

  Future<void> _handle(List<Map<String, dynamic>> orders, void Function() signalNext) async {
    try {
      await _upload(orders);
    } catch (error) {
      showError(error);
    } finally {
      signalNext(); // Always signal, even after an error; otherwise updates stop.
    }
  }

  void stop() {
    unawaited(_changes?.cancel()); // Cancelling the stream also cancels a StoreObserverV2.
    _observer?.cancel();
  }
}

// ============================================================================
// PATTERN 4: Signal after work that completes elsewhere
// ============================================================================

/// ✅ GOOD: registerObserverWithSignalNext fits work that finishes in a
/// different place than where the update arrives. Here the next update is
/// requested only after the frame showing the current one has been rendered.
class FrameSyncedOrders extends StatefulWidget {
  const FrameSyncedOrders({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<FrameSyncedOrders> createState() => _FrameSyncedOrdersState();
}

class _FrameSyncedOrdersState extends State<FrameSyncedOrders> {
  late final StoreObserverV2 _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC LIMIT 100',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen((result) {
      final orders = result.items.map((item) => item.value).toList();
      if (!mounted) return;
      setState(() => _orders = orders);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_observer.isCancelled) _observer.signalNext();
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) => ListTile(
        key: ValueKey(_orders[index]['_id']),
        title: Text('${_orders[index]['_id']}'),
      ),
    );
  }
}

// ============================================================================
// ANTI-PATTERNS
// ============================================================================

/// ❌ BAD: signalNext is skipped when the work throws; the observer silently
/// stops updating.
StoreObserverV2 fragileObserver(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  final observer = ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY createdAt',
  );
  observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
    observer.signalNext(); // Never reached if upload() throws.
  });
  return observer;
}

/// ❌ BAD: onChange only. Results passed to onChange are also queued in the
/// `changes` stream; with nothing listening, they are retained (SDK 5.1.0).
/// Consume `changes` and call observer.signalNext() instead (pattern 3).
StoreObserverV2 callbackOnlySignalNext(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  return ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY createdAt',
    onChange: (result, signalNext) async {
      try {
        await upload(result.items.map((item) => item.value).toList());
      } finally {
        signalNext();
      }
    },
  );
}

/// ❌ BAD: Do not pause and resume the stream of an observer registered with
/// registerObserverWithSignalNext; the SDK logs a warning if you do. This code
/// also never calls signalNext(), so the observer stops after the first
/// update. Use signalNext() to control delivery instead (pattern 3).
StreamSubscription<QueryResult> pausingSignalNextObserver(
  StoreObserverV2 signalNextObserver,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  late final StreamSubscription<QueryResult> subscription;
  subscription = signalNextObserver.changes.listen((result) {
    subscription.pause();
    unawaited(
      upload(result.items.map((item) => item.value).toList())
          .whenComplete(subscription.resume),
    );
  });
  return subscription;
}

/// Placeholder error reporter used by the examples above.
void showError(Object error) => debugPrint('Error: $error');
