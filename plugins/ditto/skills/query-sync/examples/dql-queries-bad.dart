// DQL read anti-patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// Every function below compiles and runs, but returns wrong results, is
// unsafe, or wastes resources. The corrected versions are in
// dql-queries-good.dart.
//
// Statements that fail outright are described in comments only:
// - Inline object literal with unquoted keys in INSERT
//   (INSERT INTO orders DOCUMENTS ({_id: 'a'})): "Cannot convert to a literal".
// - GROUP BY or HAVING that references a projection alias: rejected with
//   "... must depend only on group keys or aggregates".
// - JOIN whose inner join key has no index (and is not _id): rejected with
//   "Joining to ... disallowed without appropriate index support".
// - SELECT *, total * 2 AS doubled: unqualified * with other projections is
//   rejected; write SELECT orders.*, ... instead.
// - Unqualified field that exists on both sides of a JOIN (SELECT name ...):
//   "Ambiguous reference to field: name". Qualify fields with their alias.
// - USE IDS with the IDs wrapped in parentheses is rejected; use
//   USE IDS 'a', 'b' or USE IDS LIST :ids.

import 'package:ditto_live/ditto_live.dart';

/// ❌ BAD: String interpolation. Injection risk, broken quoting for input that
/// contains quotes or backslashes, and no statement reuse.
Future<void> findOrdersUnsafe(Ditto ditto, String customerId) async {
  await ditto.store.execute(
    "SELECT * FROM orders WHERE customerId = '$customerId'",
  );
}

/// ❌ BAD: IN (:statuses) wraps the array in a one-element list, so no
/// document matches. Use IN :statuses.
Future<List<Map<String, dynamic>>> findByStatusesWrong(
  Ditto ditto,
  List<String> statuses,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status IN (:statuses)',
    arguments: {'statuses': statuses},
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: ANY ... SATISFIES over a parameter in WHERE returns no rows in
/// SDK 5.1.0. Use status IN :statuses.
Future<List<Map<String, dynamic>>> findByStatusesWithAny(
  Ditto ditto,
  List<String> statuses,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE ANY s IN :statuses SATISFIES s = status END', // lint-ignore
    arguments: {'statuses': statuses},
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Unquoted keys in a SELECT object literal produce no error, but the
/// object is returned as {} (the key is evaluated as a field reference).
Future<Map<String, dynamic>> unquotedKeysInSelect(Ditto ditto) async {
  final result = await ditto.store.execute('SELECT {a: 1} AS o FROM system:dual');
  return result.items.first.value; // {o: {}}
}

/// ❌ BAD: This filter drops documents where isDeleted is null or missing.
/// Use coalesce(isDeleted, false) = false.
Future<List<Map<String, dynamic>>> activeTasksWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt', // lint-ignore
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: The null check is also true for a missing field, so this does not
/// test existence. Use IS NOT MISSING (plus the null check if null values
/// must be excluded as well).
Future<List<Map<String, dynamic>>> assignedTasksWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE assignee IS NOT NULL ORDER BY _id', // lint-ignore
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: LIMIT without ORDER BY. The page contents are not well defined.
Future<List<Map<String, dynamic>>> firstOrdersUnordered(Ditto ditto) async {
  final result = await ditto.store.execute('SELECT * FROM orders LIMIT 20');
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Expecting matching documents first. In ascending order false sorts
/// before true, so urgent tasks come last. Use DESC or an explicit CASE.
Future<List<Map<String, dynamic>>> urgentFirstWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT * FROM tasks ORDER BY priority = 'urgent', dueAt",
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Loading every document to count or test existence in Dart.
/// Use SELECT COUNT(*) ... or SELECT _id ... LIMIT 1.
Future<int> countOpenOrdersWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'open'},
  );
  return result.items.length;
}

/// ❌ BAD: Filtering in Dart instead of WHERE materializes the whole collection.
Future<List<Map<String, dynamic>>> openOrdersFilteredInDart(Ditto ditto) async {
  final result = await ditto.store.execute('SELECT * FROM orders');
  return result.items
      .map((item) => item.value)
      .where((order) => order['status'] == 'open')
      .toList();
}

/// ❌ BAD: One query per ID (N+1). Use WHERE _id IN :ids.
Future<List<Map<String, dynamic>>> loadOrdersOneByOne(
  Ditto ditto,
  List<String> ids,
) async {
  final orders = <Map<String, dynamic>>[];
  for (final id in ids) {
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': id},
    );
    orders.addAll(result.items.map((item) => item.value));
  }
  return orders;
}

/// ❌ BAD: USE IDS with an array parameter treats the whole array as a single
/// ID and returns nothing. Use USE IDS LIST :ids or WHERE _id IN :ids.
Future<List<Map<String, dynamic>>> useIdsWithArray(
  Ditto ditto,
  List<String> ids,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders USE IDS :orderIds',
    arguments: {'orderIds': ids},
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: COUNT(field) skips false values, so this does not count documents
/// that have the field. SUM over zero rows returns MISSING, so 'revenue' is
/// absent from the row. Use COUNT(isPaid IS NOT MISSING) and
/// ifmissing(SUM(total), 0).
Future<Map<String, dynamic>> paymentStatsWrong(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(isPaid) AS withFlag, SUM(total) AS revenue '
    'FROM orders WHERE customerId = :customerId',
    arguments: {'customerId': 'customer-without-orders'},
  );
  return result.items.first.value;
}

/// ❌ BAD: DISTINCT together with _id. Every document is already unique, so
/// DISTINCT only keeps every row in memory.
Future<List<Map<String, dynamic>>> distinctWithId(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT DISTINCT _id, status FROM orders',
  );
  return result.items.map((item) => item.value).toList();
}
