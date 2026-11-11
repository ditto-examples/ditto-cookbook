import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:uuid/uuid.dart';

class TaskRepository {
  TaskRepository(this.ditto);
  final Ditto ditto;
  SyncSubscription? _subscription;
  StoreObserver? _observer;
  StreamSubscription<QueryResult>? _changes;

  void start() {
    _subscription = ditto.sync.registerSubscription('SELECT * FROM tasks');
  }

  Future<void> addTask(String name) async {
    await ditto.store.execute(
      'INSERT INTO tasks DOCUMENTS (:task)',
      arguments: {
        'task': {'_id': const Uuid().v4(), 'name': name, 'status': 'todo'},
      },
    );
  }

  /// status is 'todo', 'doing', or 'done'.
  Future<void> setStatus(String id, String status) async {
    await ditto.store.execute(
      'UPDATE tasks SET status = :status WHERE _id = :id',
      arguments: {'id': id, 'status': status},
    );
  }

  void watchTasks(void Function(List<Map<String, dynamic>>) onTasks) {
    final observer = ditto.store.registerObserver('SELECT * FROM tasks ORDER BY name');
    _observer = observer;
    _changes = observer.changes.listen((result) {
      onTasks(result.items.map((i) => i.value).toList());
    });
  }

  Future<void> dispose() async {
    await _changes?.cancel();
    _observer?.cancel();
    _subscription?.cancel();
  }
}
