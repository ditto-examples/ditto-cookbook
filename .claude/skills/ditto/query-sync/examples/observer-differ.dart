// Diffing observer results with Differ in Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// An observer delivers the complete result every time. Differ compares
// successive results by _id and reports index sets:
// - insertions: indexes in the NEW list of items that were added
// - deletions:  indexes in the OLD list of items that were removed
// - updates:    indexes in the NEW list of items whose value changed
// - moves:      DiffMove(from: oldIndex, to: newIndex)
//
// Facts:
// - diff() takes a List<QueryResultItem>: pass result.items.toList().
// - The first call reports every item as an insertion.
// - Differ keeps the previous result in memory and diffing is expensive:
//   keep diffed queries bounded (LIMIT) and debounce large or busy results.
// - Differ does not return old items: keep previous values (or IDs) yourself.
// - Differ only accepts items produced by Ditto (test doubles throw).
// - A ListView.builder with ValueKey(_id) per row does not need Differ.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

/// ✅ GOOD: Logging changes between results.
StreamSubscription<QueryResult> logOrderChanges(StoreObserver observer) {
  final differ = Differ();
  var previousIds = <Object?>[];

  return observer.changes.listen((result) {
    final items = result.items.toList(); // diff() takes a List.
    final Diff diff = differ.diff(items);
    final currentIds = items.map((item) => item.value['_id']).toList();

    for (final index in diff.deletions) {
      debugPrint('deleted ${previousIds[index]}'); // Index into the OLD list.
    }
    for (final index in diff.insertions) {
      debugPrint('inserted ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final index in diff.updates) {
      debugPrint('updated ${currentIds[index]}'); // Index into the NEW list.
    }
    for (final DiffMove move in diff.moves) {
      debugPrint('moved ${move.from} -> ${move.to}');
    }
    previousIds = currentIds;
  });
}

/// ✅ GOOD: Driving an AnimatedList from Differ results. Removals are applied
/// in descending order of old indexes, insertions in ascending order of new
/// indexes; a move is treated as a removal plus an insertion.
class AnimatedOrders extends StatefulWidget {
  const AnimatedOrders({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<AnimatedOrders> createState() => _AnimatedOrdersState();
}

class _AnimatedOrdersState extends State<AnimatedOrders> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _differ = Differ();
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status '
      'ORDER BY createdAt DESC, _id LIMIT 200',
      arguments: {'status': 'open'},
    );
    _changes = _observer.changes.listen(_apply);
  }

  void _apply(QueryResult result) {
    final items = result.items.toList();
    final diff = _differ.diff(items);
    final previous = _orders;
    final next = items.map((item) => item.value).toList();
    final list = _listKey.currentState;

    if (list != null) {
      final removed = {...diff.deletions, for (final m in diff.moves) m.from}.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final index in removed) {
        final order = previous[index];
        list.removeItem(index, (context, animation) => _row(order, animation));
      }
      final inserted = {...diff.insertions, for (final m in diff.moves) m.to}.toList()
        ..sort();
      for (final index in inserted) {
        list.insertItem(index);
      }
    }
    // Updated rows are rebuilt with the new values.
    setState(() => _orders = next);
  }

  Widget _row(Map<String, dynamic> order, Animation<double> animation) =>
      SizeTransition(
        sizeFactor: animation,
        child: ListTile(
          title: Text('${order['_id']}'),
          subtitle: Text('${order['status']}'),
        ),
      );

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
        key: _listKey,
        initialItemCount: _orders.length,
        itemBuilder: (context, index, animation) => _row(_orders[index], animation),
      );
}

/// ❌ BAD: Diffing an unbounded observer of a whole collection. Differ keeps
/// the full previous result and compares every item on every change. Add a
/// WHERE filter and a LIMIT, or skip Differ when keyed rows are enough.
StreamSubscription<QueryResult> diffEverything(Ditto ditto) {
  final observer = ditto.store.registerObserver('SELECT * FROM orders ORDER BY _id');
  final differ = Differ();
  return observer.changes.listen((result) {
    final diff = differ.diff(result.items.toList());
    debugPrint('${diff.insertions.length} inserted');
  });
}
