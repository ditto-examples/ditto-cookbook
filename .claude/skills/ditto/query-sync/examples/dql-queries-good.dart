// Recommended DQL read patterns for Ditto SDK 5.1.0 (Flutter, ditto_live 5.1.0).
//
// Covers: parameters, membership filters, quoted object keys, MISSING/NULL,
// ORDER BY / LIMIT / keyset pagination, projections, aggregates, GROUP BY,
// and JOIN (SDK 5.1+) with an index on the inner collection.
//
// All statements read the local store only. Subscriptions decide which
// documents are on the device (see subscription-lifecycle-good.dart).

import 'package:ditto_live/ditto_live.dart';

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

/// ✅ GOOD: Every value from the app is passed as a typed parameter.
/// The statement text stays constant, so the prepared plan can be reused.
Future<List<Map<String, dynamic>>> findOrders(
  Ditto ditto, {
  required String customerId,
  required List<String> statuses,
  int pageSize = 50,
}) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE customerId = :customerId AND status IN :statuses '
    'ORDER BY createdAt DESC, _id LIMIT :pageSize',
    arguments: {
      'customerId': customerId,
      'statuses': statuses, // Array parameter: IN :statuses, no parentheses
      'pageSize': pageSize,
    },
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Text containing backslashes or quotes is passed as data.
Future<void> saveExportPath(Ditto ditto) async {
  await ditto.store.execute(
    'UPDATE settings SET exportPath = :path WHERE _id = :id',
    arguments: {'id': 'device', 'path': r'C:\temp\exports'},
  );
}

// ---------------------------------------------------------------------------
// Inline object literals
// ---------------------------------------------------------------------------

/// ✅ GOOD (preferred): Pass the whole document as one parameter.
Future<void> createOrder(Ditto ditto, String id, String customerId) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': id,
        'customerId': customerId,
        'status': 'open',
        'total': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}

/// ✅ GOOD: If an object literal is written inline, every key is quoted.
Future<void> seedSampleOrder(Ditto ditto) async {
  await ditto.store.execute(
    "INSERT INTO orders DOCUMENTS ({'_id': 'sample-order', 'status': 'open'}) "
    'ON ID CONFLICT DO NOTHING',
  );
}

// ---------------------------------------------------------------------------
// MISSING and NULL
// ---------------------------------------------------------------------------

/// ✅ GOOD: coalesce() treats a missing or null isDeleted flag as false.
Future<List<Map<String, dynamic>>> activeTasks(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false '
    'ORDER BY createdAt, _id',
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: IS MISSING / IS NOT MISSING test whether a field exists.
Future<List<Map<String, dynamic>>> tasksWithoutAssignee(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, title FROM tasks WHERE assignee IS MISSING ORDER BY _id',
  );
  return result.items.map((item) => item.value).toList();
}

// ---------------------------------------------------------------------------
// Membership
// ---------------------------------------------------------------------------

/// ✅ GOOD: A field equals one of several values.
Future<List<Map<String, dynamic>>> tasksWithStatus(
  Ditto ditto,
  List<String> statuses,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE status IN :statuses ORDER BY _id',
    arguments: {'statuses': statuses},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: An array field contains a value (element lookups cannot use an index).
Future<List<Map<String, dynamic>>> tasksTagged(Ditto ditto, String tag) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE :tag IN tags ORDER BY _id',
    arguments: {'tag': tag},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Several documents by ID in one query (planned as an ID scan).
Future<List<Map<String, dynamic>>> ordersByIds(
  Ditto ditto,
  List<String> ids,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}

// ---------------------------------------------------------------------------
// Projections, ORDER BY, LIMIT
// ---------------------------------------------------------------------------

/// ✅ GOOD: Only the fields the screen shows, computed fields aliased,
/// deterministic order with an _id tie-breaker.
Future<List<Map<String, dynamic>>> orderSummaries(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id, customerName, total * 1.1 AS totalWithTax '
    'FROM orders WHERE status = :status '
    'ORDER BY createdAt DESC, _id LIMIT 100',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Keyset pagination continues after the last row of the previous page.
Future<List<Map<String, dynamic>>> nextPage(
  Ditto ditto, {
  required String afterCreatedAt,
  int pageSize = 50,
}) async {
  final result = await ditto.store.execute(
    'SELECT _id, title, createdAt FROM tasks '
    'WHERE createdAt < :after '
    'ORDER BY createdAt DESC LIMIT :pageSize',
    arguments: {'after': afterCreatedAt, 'pageSize': pageSize},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Put urgent tasks first explicitly (false sorts before true in ASC).
Future<List<Map<String, dynamic>>> tasksUrgentFirst(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM tasks WHERE coalesce(isDeleted, false) = false '
    "ORDER BY CASE WHEN priority = 'urgent' THEN 0 ELSE 1 END, dueAt, _id",
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: An existence check stops at the first match.
Future<bool> hasOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE status = :status LIMIT 1',
    arguments: {'status': 'open'},
  );
  return result.items.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Aggregates and GROUP BY
// ---------------------------------------------------------------------------

/// ✅ GOOD: COUNT(*) instead of loading documents; empty sets defaulted.
Future<Map<String, dynamic>> orderStats(Ditto ditto, String customerId) async {
  final result = await ditto.store.execute(
    'SELECT COUNT(*) AS orderCount, '
    'ifmissing(SUM(total), 0) AS revenue, '
    'ifmissing(AVG(total), 0) AS averageOrder '
    'FROM orders WHERE customerId = :customerId',
    arguments: {'customerId': customerId},
  );
  return result.items.first.value;
}

/// ✅ GOOD: GROUP BY and HAVING repeat the expressions; ORDER BY may use aliases.
Future<List<Map<String, dynamic>>> dailyRevenue(Ditto ditto, String since) async {
  final result = await ditto.store.execute(
    "SELECT date_format(createdAt, 'YYYY-MM-DD') AS day, SUM(total) AS revenue "
    'FROM orders WHERE createdAt >= :since '
    "GROUP BY date_format(createdAt, 'YYYY-MM-DD') "
    'HAVING SUM(total) > :minRevenue '
    'ORDER BY day',
    arguments: {'since': since, 'minRevenue': 1000},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: DISTINCT on a low-cardinality field.
Future<List<String>> knownStatuses(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT DISTINCT status FROM orders ORDER BY status',
  );
  return result.items
      .map((item) => item.value['status'])
      .whereType<String>()
      .toList();
}

// ---------------------------------------------------------------------------
// JOIN (SDK 5.1+)
// ---------------------------------------------------------------------------

/// ✅ GOOD: Create the index the join needs once per launch, at startup.
/// Indexes persist, and IF NOT EXISTS makes this idempotent.
Future<void> ensureJoinIndexes(Ditto ditto) async {
  await ditto.store.execute(
    'CREATE INDEX IF NOT EXISTS ix_orders_customerId ON orders (customerId)',
  );
}

/// ✅ GOOD: The inner collection (orders) is looked up through
/// ix_orders_customerId. Fields are qualified and colliding names aliased.
Future<List<Map<String, dynamic>>> goldCustomerOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT c.name, o._id AS orderId, o.total '
    'FROM customers c '
    'JOIN orders o ON o.customerId = c._id '
    'WHERE c.tier = :tier '
    'ORDER BY c.name, o.total DESC',
    arguments: {'tier': 'gold'},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Joining on the inner collection's _id needs no extra index.
Future<List<Map<String, dynamic>>> openOrdersWithCustomerName(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT o._id, o.total, c.name AS customerName '
    'FROM orders o '
    'JOIN customers c ON c._id = o.customerId '
    'WHERE o.status = :status '
    'ORDER BY o._id',
    arguments: {'status': 'open'},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Customers without any order (unmatched LEFT JOIN rows).
Future<List<Map<String, dynamic>>> customersWithoutOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT c._id, c.name '
    'FROM customers c '
    'LEFT JOIN orders o ON o.customerId = c._id '
    'WHERE o._id IS MISSING',
  );
  return result.items.map((item) => item.value).toList();
}
