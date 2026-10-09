// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Event history and audit logs
//
// Record each change as a new fact instead of overwriting one field.
//   Pattern 1: audit-log map inside the document (bounded history of one record)
//   Pattern 2: append-only event documents (unbounded or independently read)
//   Pattern 3: current state plus history; see two-collection-pattern.dart
//
// Guide: § Event History and Audit Logs

import 'package:ditto_live/ditto_live.dart';

/// ISO-8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". Fixed precision keeps keys and values sortable
/// as text (native Dart omits zero microseconds, so even one device would
/// otherwise mix precisions).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

// ---------------------------------------------------------------------------
// ❌ BAD: Appending events to an array
// ---------------------------------------------------------------------------

/// ❌ BAD: Arrays are registers. If two devices append concurrently, one of the
/// appended events is lost after sync. The array also grows the document
/// without bound.
Future<void> appendEventToArray(
  Ditto ditto,
  String orderId,
  List<dynamic> currentHistory,
  Map<String, dynamic> event,
) async {
  await ditto.store.execute(
    'UPDATE orders SET history = :history WHERE _id = :id',
    arguments: {
      'id': orderId,
      'history': [...currentHistory, event],
    },
  );
}

/// ❌ BAD: Overwriting a single status field loses the history, and a late
/// write from a device that was offline can move the order backwards.
Future<void> setStatusOnly(Ditto ditto, String orderId, String status) async {
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'id': orderId, 'status': status},
  );
}

// ---------------------------------------------------------------------------
// ✅ Pattern 1: Audit-log map keyed by timestamp
// ---------------------------------------------------------------------------

/// Appends a status transition. Each device adds its own keys and the add-wins
/// map keeps every entry whose key is distinct. Two transitions recorded in the
/// same millisecond on different devices share a key and only one is kept; if
/// that matters, append a device identifier to the key
/// ("2026-10-08T10:05:12.437Z_t3"). The key is passed as data inside a partial
/// document; unchanged entries are not rewritten.
Future<void> appendStatus(Ditto ditto, String orderId, String status) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
    arguments: {
      'patch': {
        '_id': orderId,
        'statusLog': {utcTimestamp(): status},
      },
    },
  );
}

const _statusOrder = ['created', 'confirmed', 'shipped', 'delivered'];

/// Derives the current status as the most advanced state, so a late write
/// from a device that was offline cannot move the order backwards. Other
/// derivations: latest timestamp, earliest occurrence, or custom rules.
String? currentStatus(Map<String, dynamic> order) {
  final log = (order['statusLog'] as Map<String, dynamic>?) ?? const {};
  String? best;
  for (final status in log.values.whereType<String>()) {
    if (best == null ||
        _statusOrder.indexOf(status) > _statusOrder.indexOf(best)) {
      best = status;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// ✅ Pattern 2: Append-only event documents
// ---------------------------------------------------------------------------

/// Each event is its own document with a UUID `_id`. Events are never
/// updated, so there is nothing to merge, and the parent stays small.
/// storeId is copied so that subscriptions can filter events by store.
Future<void> recordOrderEvent(
  Ditto ditto, {
  required String eventId, // a new UUID
  required String orderId,
  required String storeId,
  required String type,
  required String userId,
}) async {
  await ditto.store.execute(
    'INSERT INTO orderEvents DOCUMENTS (:event)',
    arguments: {
      'event': {
        '_id': eventId,
        'orderId': orderId,
        'storeId': storeId,
        'type': type,
        'userId': userId,
        'occurredAt': utcTimestamp(),
      },
    },
  );
}

Future<List<Map<String, dynamic>>> orderTimeline(
  Ditto ditto,
  String orderId,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM orderEvents
    WHERE orderId = :orderId
    ORDER BY occurredAt ASC, _id ASC
    ''',
    arguments: {'orderId': orderId},
  );
  return result.items.map((item) => item.value).toList();
}

/// Event collections grow forever: plan cleanup from the start. EVICT removes
/// documents from this device only. Subscribe to `occurredAt >= :cutoff` and
/// evict the complement (`occurredAt < :cutoff`) with the same cutoff, so no
/// active subscription syncs the evicted events back. Evict on a schedule, at
/// most about once per day.
SyncSubscription subscribeToRecentEvents(Ditto ditto, String cutoff) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM orderEvents WHERE occurredAt >= :cutoff',
      arguments: {'cutoff': cutoff},
    );

Future<void> evictOldEvents(Ditto ditto, String cutoff) async {
  await ditto.store.execute(
    'EVICT FROM orderEvents WHERE occurredAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
}
