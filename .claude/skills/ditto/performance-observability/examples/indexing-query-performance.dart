// SDK Version: Ditto SDK 5.1.0 (ditto_live 5.1.0)
// Platform: Flutter (DQL applies to all platforms)
// Last Updated: 2026-10-08
//
// ============================================================================
// Indexing and Query Performance
// ============================================================================
//
// Guide sections (.claude/guides/best-practices/ditto.md):
// - #creating-indexes
// - #index-usage-rules
// - #composite-indexes-and-key-order-sdk-51
// - #strict-mode-and-data-types
// - #advise-sdk-51
// - #explain-and-profile
// - #query-scope-and-execution
//
// Facts:
// - Indexes are local to each device, persist across restarts, and are used by
//   execute and store observers (not by subscriptions; not on Ditto Server).
// - In-memory stores (Flutter Web) do not support indexes.
// - With DQL_STRICT_MODE = true the planner uses no index scans at all.
//   Keep the default (false) if you rely on indexes.
// - CREATE INDEX IF NOT EXISTS checks only the name, not the field list.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Creating indexes once at startup (composite index, SDK 5.1+)
// 2. ✅ Index-friendly predicates vs predicates that force a collection scan
// 3. ✅ ADVISE for index suggestions (development only, SDK 5.1+)
// 4. ✅ EXPLAIN to check the access path, PROFILE to measure
// 5. ✅ One IN :ids query instead of one query per ID
// 6. ✅ Index-friendly soft-delete filter
//
// ============================================================================

import 'dart:convert';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// PATTERN 1: Indexes at startup
// ============================================================================

/// ✅ GOOD: Create the indexes this app relies on, once per launch, after
/// Ditto.open and before queries and observers start.
Future<void> ensureIndexes(Ditto ditto) async {
  // In-memory stores (Flutter Web) do not support indexes.
  if (kIsWeb) return;

  try {
    // Composite index (SDK 5.1+): equality field first, then range/sort field.
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt '
      'ON orders (status, createdAt DESC)',
    );
    await ditto.store.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_customer_createdAt '
      'ON orders (customerId, createdAt DESC)',
    );
    await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products (name)');
  } catch (error) {
    // A missing index makes queries slower, not wrong: report and continue.
    debugPrint('Index creation failed: $error');
  }
}

/// ❌ BAD: Creating an index right before a query. Creation scans the whole
/// collection; create indexes at startup instead.
Future<List<Map<String, dynamic>>> searchWithOnDemandIndex(Ditto ditto, String customerId) async {
  await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders (customerId)');
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE customerId = :customerId',
    arguments: {'customerId': customerId},
  );
  return result.items.map((item) => item.value).toList();
}

// ============================================================================
// PATTERN 2: Index-friendly predicates
// ============================================================================

/// ✅ GOOD: Equality on the leading key, range and sort on the second key,
/// sort direction matching idx_orders_customer_createdAt.
Future<List<Map<String, dynamic>>> recentOrdersForCustomer(
  Ditto ditto,
  String customerId,
  String sinceUtcIso,
) async {
  final result = await ditto.store.execute(
    'SELECT _id, status, total, createdAt FROM orders '
    'WHERE customerId = :customerId AND createdAt >= :since '
    'ORDER BY createdAt DESC LIMIT 50',
    arguments: {'customerId': customerId, 'since': sinceUtcIso},
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: The sort direction does not match the index (createdAt DESC), so
/// an extra sort step is needed.
Future<List<Map<String, dynamic>>> oldestOrdersFirst(Ditto ditto, String customerId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE customerId = :customerId ORDER BY createdAt ASC',
    arguments: {'customerId': customerId},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: A constant, case-sensitive LIKE prefix uses an index range scan.
Future<List<Map<String, dynamic>>> productsStartingWithPen(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT _id, name FROM products WHERE name LIKE 'Pen%' ORDER BY name",
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Functions applied to the field force a collection scan, even with
/// an index on `name`. (Functions on the value side, such as `= :param`, are
/// fine.) Expression indexes such as `(lower(name))` do not exist.
Future<List<Map<String, dynamic>>> productsByFunction(Ditto ditto) async {
  final byPrefix = await ditto.store.execute(
    "SELECT _id, name FROM products WHERE starts_with(name, 'Pen')",
  );
  final byLower = await ditto.store.execute(
    'SELECT _id, name FROM products WHERE lower(name) = :name',
    arguments: {'name': 'pen'},
  );
  return [
    ...byPrefix.items.map((item) => item.value),
    ...byLower.items.map((item) => item.value),
  ];
}

/// ❌ BAD: Every OR branch must be indexable. `notes` has no index, so the
/// whole query becomes a collection scan. Element lookups such as
/// array_contains(tags, 'x') cannot use an index either.
Future<int> countUrgentOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT COUNT(*) AS n FROM orders WHERE status = 'urgent' OR notes = 'urgent'",
  );
  return result.items.first.value['n'] as int;
}

// ============================================================================
// PATTERN 3: ADVISE (development only, SDK 5.1+)
// ============================================================================

/// ✅ GOOD: ADVISE plans the statement without executing it and suggests
/// CREATE INDEX statements. Copy the suggestions into ensureIndexes().
/// Do not run ADVISE AND PROVISION in production code paths; it creates
/// indexes as a side effect.
Future<void> printOrderIndexAdvice(Ditto ditto) async {
  final result = await ditto.store.execute(
    'ADVISE SELECT * FROM orders WHERE status = :status AND isDeleted = false '
    'ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  final advice = result.items.first.value['advice'] as Map<String, dynamic>;
  final suggested = (advice['suggestedIndexes'] as List<dynamic>?) ?? const [];
  if (suggested.isEmpty) {
    debugPrint('No suggestions: ${advice['outcome']}');
  }
  for (final index in suggested) {
    final entry = index as Map<String, dynamic>;
    debugPrint('${entry['reason']}\n  ${entry['statement']}');
  }
}

// ============================================================================
// PATTERN 4: EXPLAIN vs PROFILE (development only)
// ============================================================================

/// ✅ GOOD: EXPLAIN parses and plans the statement but never runs it. Use it to
/// check the access path: `indexScan`, `idScan`, or `countScan` is good; a
/// `scan` on a large collection is a warning sign. Do not use it to measure.
Future<void> explainOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC',
    arguments: {'status': 'open'},
  );
  final plan = jsonEncode(result.items.first.value['plan']);
  final usesCollectionScan = plan.contains('"#operator":"scan"');
  debugPrint(usesCollectionScan ? 'Collection scan: consider an index' : 'Plan: $plan');
}

/// ✅ GOOD: PROFILE runs the SELECT and appends one row keyed
/// `~request_profile`. Compare documentsIn and documentsOut of each step:
/// a filter that discards most of its input usually needs an index.
Future<void> profileOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'PROFILE SELECT * FROM orders WHERE status = :status',
    arguments: {'status': 'open'},
  );
  final rows = result.items.map((item) => item.value).toList();
  final profile = rows.lastWhere(
    (row) => row.containsKey('~request_profile'),
    orElse: () => const {},
  )['~request_profile'] as Map<String, dynamic>?;
  final resultCount = rows.length - (profile == null ? 0 : 1);
  debugPrint('rows=$resultCount times=${profile?['times']}');
  debugPrint(const JsonEncoder.withIndent('  ').convert(profile?['plan']));
}

// ============================================================================
// PATTERN 5: Query scope
// ============================================================================

/// ❌ BAD: One query per ID.
Future<List<Map<String, dynamic>>> loadOrdersOneByOne(Ditto ditto, List<String> ids) async {
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

/// ✅ GOOD: One query, planned as an ID scan. The query string stays constant,
/// so the prepared-statement cache is reused.
Future<List<Map<String, dynamic>>> loadOrders(Ditto ditto, List<String> ids) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id IN :ids',
    arguments: {'ids': ids},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: A full-collection COUNT(*) is answered by a count scan without
/// reading documents (SDK 5.1+). For existence checks, LIMIT 1 is simplest.
Future<bool> hasOpenOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT _id FROM orders WHERE status = :status LIMIT 1',
    arguments: {'status': 'open'},
  );
  return result.items.isNotEmpty;
}

// ============================================================================
// PATTERN 6: Index-friendly soft-delete filter
// ============================================================================

/// ✅ GOOD: `coalesce(isDeleted, false) = false` alone is a collection scan.
/// Combine it with a selective, indexed predicate (here `status`, the leading
/// key of idx_orders_status_createdAt); the coalesce condition is then applied
/// as a filter after the index scan.
Future<List<Map<String, dynamic>>> visibleOrders(Ditto ditto, String status) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE status = :status AND coalesce(isDeleted, false) = false '
    'ORDER BY createdAt DESC',
    arguments: {'status': status},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Index-friendly equivalent of coalesce(isDeleted, false) = false
/// when an index on `isDeleted` exists.
Future<List<Map<String, dynamic>>> allVisibleOrders(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders '
    'WHERE isDeleted IS MISSING OR isDeleted IS NULL OR isDeleted = false',
  );
  return result.items.map((item) => item.value).toList();
}
