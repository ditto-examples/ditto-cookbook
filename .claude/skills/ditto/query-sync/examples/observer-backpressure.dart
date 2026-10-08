// Observer backpressure in Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// registerObserver (stable) has no backpressure: results are delivered as soon
// as they are ready, even while an async listener is still busy. For slow or
// asynchronous per-update work, SDK 5.1+ adds two (Experimental) APIs that
// return a StoreObserverV2. While your code is busy, Ditto holds back further
// updates and later delivers the latest state, so intermediate results are
// merged instead of queued.
//
// | Situation                                        | API                                        |
// |--------------------------------------------------|--------------------------------------------|
// | Updating widgets                                 | registerObserver + changes (stable)        |
// | Slow async work that fits a loop                 | registerObserverV2 + await for (Experimental) |
// | Work finishes elsewhere (animation, callback)    | registerObserverWithSignalNext (Experimental) |
//
// The experimental APIs may change in a future release.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

void showError(Object error) {
  // Report the error to your logging or crash-reporting pipeline.
}

/// ✅ GOOD: registerObserverV2 (Experimental) with await for. While the loop
/// body runs, the stream is paused and Ditto holds back the next update.
class SensorAggregator {
  SensorAggregator(this._ditto);

  final Ditto _ditto;
  StoreObserverV2? _observer;

  Future<void> run(
    String deviceId,
    Future<void> Function(List<Map<String, dynamic>> readings) persistAggregates,
  ) async {
    final observer = _ditto.store.registerObserverV2(
      'SELECT * FROM sensorReadings WHERE deviceId = :deviceId '
      'ORDER BY recordedAt DESC LIMIT 100',
      arguments: {'deviceId': deviceId},
    );
    _observer = observer;
    await for (final result in observer.changes) {
      // Copy plain values before the slow work; do not keep the result.
      await persistAggregates(result.items.map((item) => item.value).toList());
    }
    // The loop ends when stop() cancels the observer. Leaving the loop
    // (break, return, exception) also cancels the observer.
  }

  // signalNext() has no effect on registerObserverV2 observers.
  void stop() => _observer?.cancel();
}

/// ✅ GOOD: registerObserverWithSignalNext (Experimental). One result is
/// delivered, then Ditto waits until signalNext() is called. Results are
/// consumed through the changes stream (no onChange), and signalNext() is
/// called in finally so an error cannot stop updates.
class OpenOrdersUploader {
  OpenOrdersUploader(this._ditto, this._upload);

  final Ditto _ditto;
  final Future<void> Function(List<Map<String, dynamic>> orders) _upload;
  StoreObserverV2? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    final observer = _ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt, _id',
      arguments: {'status': 'open'},
    );
    _observer = observer;
    // Do not pause/resume this stream; signalNext() controls delivery.
    _changes = observer.changes.listen((result) {
      final orders = result.items.map((item) => item.value).toList();
      unawaited(_handle(orders, observer.signalNext));
    });
  }

  Future<void> _handle(
    List<Map<String, dynamic>> orders,
    void Function() signalNext,
  ) async {
    try {
      await _upload(orders);
    } catch (error) {
      showError(error);
    } finally {
      signalNext(); // Always signal, even after an error.
    }
  }

  void stop() {
    unawaited(_changes?.cancel()); // Also cancels a StoreObserverV2.
    _observer?.cancel();
  }
}

/// ✅ GOOD: Only the latest state matters. A slow consumer on
/// registerObserverV2 merges intermediate states automatically.
class LatestStateExporter {
  LatestStateExporter(this._ditto);

  final Ditto _ditto;
  StoreObserverV2? _observer;

  Future<void> run(Future<void> Function(String json) writeFile) async {
    final observer = _ditto.store.registerObserverV2(
      'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id',
      arguments: {'status': 'open'},
    );
    _observer = observer;
    await for (final result in observer.changes) {
      final json = '[${result.items.map((item) => item.jsonString).join(',')}]';
      await writeFile(json);
    }
  }

  void stop() => _observer?.cancel();
}

/// ❌ BAD: signalNext() is skipped when the work throws, so the observer
/// silently stops delivering updates. Call it in a finally block.
StoreObserverV2 fragileObserver(
  Ditto ditto,
  Future<void> Function(List<Map<String, dynamic>> orders) upload,
) {
  final observer = ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY createdAt, _id',
  );
  observer.changes.listen((result) async {
    await upload(result.items.map((item) => item.value).toList());
    observer.signalNext(); // Never reached if upload() throws.
  });
  return observer;
}

/// ❌ BAD: Never calling signalNext(). After the first result, no further
/// updates arrive.
StreamSubscription<QueryResult> neverSignals(Ditto ditto) {
  final observer = ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM orders ORDER BY _id',
  );
  return observer.changes.listen((result) {
    debugPrint('received ${result.items.length} orders');
  });
}

/// ❌ BAD: registerObserverV2 with onChange only. As with registerObserver,
/// results are also queued in the unconsumed changes stream and retained
/// (Note (SDK 5.1.0)). Consume changes instead.
StoreObserverV2 v2WithCallbackOnly(Ditto ditto, void Function(int) onCount) {
  return ditto.store.registerObserverV2(
    'SELECT * FROM orders ORDER BY _id',
    onChange: (result) => onCount(result.items.length),
  );
}

/// ❌ BAD: Pausing the changes stream of a stable StoreObserver does not slow
/// Ditto down; results queue up in the stream instead.
Future<void> pauseStableObserver(StoreObserver observer) async {
  final subscription = observer.changes.listen((_) {});
  subscription.pause();
  await Future<void>.delayed(const Duration(seconds: 5));
  subscription.resume();
  await subscription.cancel();
}
