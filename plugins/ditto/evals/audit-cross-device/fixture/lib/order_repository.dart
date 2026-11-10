import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:uuid/uuid.dart';

String nowUtc() {
  final now = DateTime.now().toUtc();
  final millis = DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch, isUtc: true);
  return millis.toIso8601String();
}

class OrderRepository {
  OrderRepository(this.ditto);
  final Ditto ditto;
  StoreObserver? _salesObserver;
  StreamSubscription<QueryResult>? _salesChanges;

  Future<int> nextOrderNumber(String storeId) async {
    final result = await ditto.store.execute(
      'SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
    return (result.items.first.value['n'] as int) + 1;
  }

  Future<String> createOrder(String storeId) async {
    final id = const Uuid().v4();
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': id,
          'storeId': storeId,
          'orderNumber': await nextOrderNumber(storeId),
          'status': 'open',
          'lines': <String, dynamic>{},
          'createdAt': nowUtc(),
        },
      },
    );
    return id;
  }

  /// Returns true when this till took the payment.
  Future<bool> closeOrder(String orderId) async {
    final result = await ditto.store.execute(
      "UPDATE orders SET status = 'paid', paidAt = :now "
      "WHERE _id = :id AND status = 'open'",
      arguments: {'id': orderId, 'now': nowUtc()},
    );
    // Exactly one till takes the payment.
    return result.mutatedDocumentIDs().isNotEmpty;
  }

  Future<void> sendToKitchen(String orderId, void Function(String) toast) async {
    await ditto.store.execute(
      'UPDATE orders SET sentToKitchenAt = :now WHERE _id = :id',
      arguments: {'id': orderId, 'now': nowUtc()},
    );
    toast('The kitchen has received the order');
  }

  void watchPaidCount(String storeId, void Function(int) onCount) {
    final observer = ditto.store.registerObserver(
      "SELECT COUNT(*) AS n FROM orders WHERE storeId = :storeId AND status = 'paid'",
      arguments: {'storeId': storeId},
    );
    _salesObserver = observer;
    _salesChanges = observer.changes.listen((result) {
      onCount(result.items.first.value['n'] as int);
    });
  }

  Future<void> dispose() async {
    await _salesChanges?.cancel();
    _salesObserver?.cancel();
  }
}
