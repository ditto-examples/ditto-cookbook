// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Composite (object) document IDs
//
// Permission rules are queries on _id and its subfields. A hierarchical
// composite _id lets you grant access at any level (a region, a location),
// and the same subfields filter subscriptions and queries and can be indexed.
// Put only immutable attributes into _id. Key order inside a composite _id
// does not matter.
//
// Guide: .claude/guides/best-practices/ditto.md
//   #composite-ids-for-permission-scoping-and-grouping, #schema-evolution

import 'package:ditto_live/ditto_live.dart';

// ---------------------------------------------------------------------------
// ✅ GOOD: Scope fields plus a UUID
// ---------------------------------------------------------------------------

Future<void> createLocationOrder(
  Ditto ditto, {
  required String region,
  required String locationId,
  required String orderId, // a new UUID
}) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': {'region': region, 'locationId': locationId, 'orderId': orderId},
        'status': 'open',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    },
  );
}

/// Index the subfield used for local queries (indexes persist; create once).
Future<void> createLocationIndex(Ditto ditto) async {
  await ditto.store.execute(
    'CREATE INDEX IF NOT EXISTS orders_locationId ON orders (_id.locationId)',
  );
}

/// Each store device syncs only its own location's orders.
SyncSubscription subscribeToLocation(Ditto ditto, String locationId) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE _id.locationId = :locationId',
      arguments: {'locationId': locationId},
    );

/// Filtering on the complete _id value uses a direct ID lookup.
Future<Map<String, dynamic>?> findOrder(
  Ditto ditto,
  Map<String, String> id,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :id',
    arguments: {'id': id},
  );
  return result.items.isEmpty ? null : result.items.first.value;
}

// ---------------------------------------------------------------------------
// ❌ BAD: Mutable attributes inside _id
// ---------------------------------------------------------------------------

/// ❌ BAD: assignedTo can change, but _id is immutable
/// (`UPDATE ... SET _id = ...` fails). Reassigning the task would require
/// copying it to a new document. Keep mutable values as regular fields.
Future<void> createTaskWithMutableId(
  Ditto ditto,
  String taskId,
  String assignedTo,
) async {
  await ditto.store.execute(
    'INSERT INTO tasks DOCUMENTS (:task)',
    arguments: {
      'task': {
        '_id': {'taskId': taskId, 'assignedTo': assignedTo},
        'title': 'Restock shelf 4',
      },
    },
  );
}

// ---------------------------------------------------------------------------
// ✅ GOOD: Schema version in a composite _id
// ---------------------------------------------------------------------------

/// Because _id is immutable, an UPDATE cannot change a document's version by
/// accident. Each app version subscribes only to the versions it understands.
SyncSubscription subscribeToCarsV2(Ditto ditto) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM cars WHERE _id.schemaVersion = :version',
      arguments: {'version': 2},
    );

Future<void> insertCarV2(Ditto ditto, String carId) async {
  await ditto.store.execute(
    'INSERT INTO cars DOCUMENTS (:car)',
    arguments: {
      'car': {
        '_id': {'id': carId, 'schemaVersion': 2},
        'make': 'Hyundai',
        'fuelEconomyMpg': 32,
      },
    },
  );
}
