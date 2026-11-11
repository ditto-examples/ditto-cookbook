import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:uuid/uuid.dart';

import 'models/order.dart';

class OrderRepository {
  OrderRepository(this.ditto, this.storeId);
  final Ditto ditto;
  final String storeId;
  SyncSubscription? _subscription;
  StoreObserver? _observer;
  StreamSubscription<QueryResult>? _changes;

  Future<void> start() async {
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_store ON orders (storeId)',
    );
    // "tableNumber" replaces "tableNo" from 1.5 on.
    await ditto.store.execute(
      'UPDATE orders SET tableNumber = tableNo UNSET tableNo '
      'WHERE storeId = :storeId AND tableNo IS NOT MISSING',
      arguments: {'storeId': storeId},
    );
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId',
      arguments: {'storeId': storeId},
    );
  }

  Future<String> createOrder(int tableNumber) async {
    final id = const Uuid().v4();
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': id,
          'storeId': storeId,
          'tableNumber': tableNumber,
          'status': 'open',
          'items': <Map<String, dynamic>>[],
        },
      },
    );
    return id;
  }

  Future<void> moveTable(String orderId, int tableNumber) async {
    await ditto.store.execute(
      'UPDATE orders SET tableNumber = :tableNumber WHERE _id = :id',
      arguments: {'id': orderId, 'tableNumber': tableNumber},
    );
  }

  /// Any till at the table can add an item to the order.
  Future<void> addItem(String orderId, String productId, int quantity) async {
    final result = await ditto.store.execute(
      'SELECT items FROM orders WHERE _id = :id',
      arguments: {'id': orderId},
    );
    final items = List<Map<String, dynamic>>.from(
        (result.items.first.value['items'] as List?) ?? const []);
    items.add({'productId': productId, 'quantity': quantity});
    await ditto.store.execute(
      'UPDATE orders SET items = :items WHERE _id = :id',
      arguments: {'id': orderId, 'items': items},
    );
  }

  Future<void> setNote(String orderId, String note) async {
    await ditto.store.execute(
      'UPDATE orders SET note = :note WHERE _id = :id',
      arguments: {'id': orderId, 'note': note},
    );
  }

  Future<void> markPaid(String orderId) async {
    await ditto.store.execute(
      "UPDATE orders SET status = 'paid' WHERE _id = :id",
      arguments: {'id': orderId},
    );
  }

  Future<void> refund(String orderId) async {
    await ditto.store.execute(
      "UPDATE orders SET status = 'refunded' WHERE _id = :id",
      arguments: {'id': orderId},
    );
  }

  void watchOpenOrders(void Function(List<Order>) onOrders) {
    final observer = ditto.store.registerObserver(
      "SELECT * FROM orders WHERE storeId = :storeId AND status = 'open'",
      arguments: {'storeId': storeId},
    );
    _observer = observer;
    _changes = observer.changes.listen((result) {
      onOrders(result.items.map((i) => Order.fromDocument(i.value)).toList());
    });
  }

  Future<void> dispose() async {
    await _changes?.cancel();
    _observer?.cancel();
    _subscription?.cancel();
  }
}
