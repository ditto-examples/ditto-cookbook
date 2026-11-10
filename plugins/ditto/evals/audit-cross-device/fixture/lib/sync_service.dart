import 'package:ditto_live/ditto_live.dart';

class SyncService {
  SyncService(this.ditto);
  final Ditto ditto;
  SyncSubscription? _orders;

  void start(String storeId) {
    _orders = ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId AND status = :status',
      arguments: {'storeId': storeId, 'status': 'open'},
    );
    ditto.sync.start();
  }

  void stop() {
    _orders?.cancel();
    _orders = null;
  }
}
