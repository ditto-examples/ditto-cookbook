import 'package:ditto_live/ditto_live.dart';

class OrdersRepository {
  OrdersRepository(this.ditto);

  final Ditto ditto;

  Future<List<Map<String, dynamic>>> byStatuses(List<String> statuses) async {
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE status IN (:statuses)',
      arguments: {'statuses': statuses},
    );
    return result.items.map((item) => item.value).toList();
  }

  Future<List<Map<String, dynamic>>> forCustomer(String customerId) async {
    final result = await ditto.store.execute(
      "SELECT * FROM orders WHERE customerId = '$customerId'",
    );
    return result.items.map((item) => item.value).toList();
  }

  Future<void> remove(List<String> ids) async {
    await ditto.store.execute(
      'DELETE FROM orders USE IDS LIST :ids',
      arguments: {'ids': ids},
    );
  }

  StoreObserver watchCount(void Function(int) onCount) {
    return ditto.store.registerObserver(
      'SELECT * FROM orders',
      onChange: (result) => onCount(result.items.length),
    );
  }
}
