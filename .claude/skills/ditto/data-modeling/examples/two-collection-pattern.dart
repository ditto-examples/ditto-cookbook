// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Current state plus history (two collections)
//
// When you need both the latest value with low latency and a complete
// history, write each change to two collections in one transaction:
//   vehicles:         one bounded document per entity (real-time screens)
//   vehiclePositions: one append-only document per change (analysis)
//
// Guide: .claude/guides/best-practices/ditto.md#event-history-and-audit-logs
//   (Pattern 3), #transactions

import 'package:ditto_live/ditto_live.dart';

/// ✅ GOOD: Both writes in one transaction, so local observers never see one
/// without the other. The position is declared as a REGISTER in every
/// statement because latitude and longitude from two readings must never mix.
Future<void> recordPosition(
  Ditto ditto, {
  required String vehicleId,
  required String eventId, // a new UUID
  required double lat,
  required double lon,
}) async {
  final recordedAt = DateTime.now().toUtc().toIso8601String();
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'INSERT INTO vehiclePositions DOCUMENTS (:event)',
      arguments: {
        'event': {
          '_id': eventId,
          'vehicleId': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'recordedAt': recordedAt,
        },
      },
    );
    await tx.execute(
      '''
      INSERT INTO COLLECTION vehicles (position REGISTER)
      DOCUMENTS (:vehicle)
      ON ID CONFLICT DO UPDATE_LOCAL_DIFF
      ''',
      arguments: {
        'vehicle': {
          '_id': vehicleId,
          'position': {'lat': lat, 'lon': lon},
          'lastSeenAt': recordedAt,
        },
      },
    );
  }, hint: 'recordPosition');
}

/// Reads the current state with the same REGISTER declaration.
Future<List<Map<String, dynamic>>> currentPositions(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM COLLECTION vehicles (position REGISTER) ORDER BY _id',
  );
  return result.items.map((item) => item.value).toList();
}

/// History for one vehicle, oldest first.
Future<List<Map<String, dynamic>>> positionHistory(
  Ditto ditto,
  String vehicleId,
  String since,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM vehiclePositions
    WHERE vehicleId = :vehicleId AND recordedAt >= :since
    ORDER BY recordedAt ASC, _id ASC
    ''',
    arguments: {'vehicleId': vehicleId, 'since': since},
  );
  return result.items.map((item) => item.value).toList();
}

/// Devices subscribe to what they need: a live map only to vehicles; an
/// analysis tool to both. Ditto's transactions documentation
/// (https://docs.ditto.live/sdk/latest/crud/transactions) describes that a
/// peer that subscribes to only part of the documents a transaction changed
/// receives (and can relay) only that part, so peers that need both halves
/// together subscribe to both collections.
List<SyncSubscription> subscribeForAnalysis(Ditto ditto, String since) => [
      ditto.sync.registerSubscription('SELECT * FROM vehicles'),
      ditto.sync.registerSubscription(
        'SELECT * FROM vehiclePositions WHERE recordedAt >= :since',
        arguments: {'since': since},
      ),
    ];

/// ❌ BAD: Two separate writes outside a transaction. A local observer can see
/// the history entry without the matching current state. The
/// undeclared vehicles upsert also stores position as a MAP, which conflicts
/// with the REGISTER declaration used elsewhere.
Future<void> recordPositionIncorrectly(
  Ditto ditto, {
  required String vehicleId,
  required String eventId,
  required double lat,
  required double lon,
}) async {
  final recordedAt = DateTime.now().toUtc().toIso8601String();
  await ditto.store.execute(
    'INSERT INTO vehiclePositions DOCUMENTS (:event)',
    arguments: {
      'event': {
        '_id': eventId,
        'vehicleId': vehicleId,
        'position': {'lat': lat, 'lon': lon},
        'recordedAt': recordedAt,
      },
    },
  );
  await ditto.store.execute(
    'INSERT INTO vehicles DOCUMENTS (:vehicle) ON ID CONFLICT DO UPDATE',
    arguments: {
      'vehicle': {
        '_id': vehicleId,
        'position': {'lat': lat, 'lon': lon},
        'lastSeenAt': recordedAt,
      },
    },
  );
}
