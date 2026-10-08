// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Timestamps
//
// Store UTC with a zone designator (ISO-8601 string) or epoch milliseconds,
// consistently within a field. A zone-less ISO string makes DQL date
// functions return MISSING, without an error. Device clocks drift: treat
// stored timestamps as approximate, never as the deciding factor between
// conflicting writes.
//
// Guide: .claude/guides/best-practices/ditto.md#timestamps

import 'package:ditto_live/ditto_live.dart';

/// ISO-8601 UTC string with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". ISO strings sort chronologically as text only
/// when they share one format. Native Dart prints microseconds
/// ("...00.123456Z"), but omits them when they are zero ("...00.123Z"), and the
/// web always prints milliseconds, so use
/// this one helper for every timestamp field that is sorted or compared.
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

/// ✅ GOOD: UTC with a zone designator.
Future<void> markReady(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
    arguments: {'id': orderId, 'readyAt': utcTimestamp()},
  );
}

/// ❌ BAD: Local time without a zone (for example "2026-10-08T19:30:00.123456").
/// DQL date functions return MISSING for it, and values written in different
/// time zones do not compare correctly. Always call toUtc() first.
Future<void> markReadyIncorrectly(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'readyAt': DateTime.now().toIso8601String(), // lint-ignore
    },
  );
}

/// ✅ GOOD: Range filters compare with parameters in the same format and can
/// use an index on the timestamp field.
Future<List<Map<String, dynamic>>> ordersSince(
  Ditto ditto,
  DateTime since,
) async {
  final result = await ditto.store.execute(
    'SELECT * FROM orders WHERE createdAt >= :since ORDER BY createdAt DESC',
    arguments: {'since': utcTimestamp(since)},
  );
  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: date_diff(date1, date2, part) returns date1 - date2 in the unit.
Future<List<Map<String, dynamic>>> openOrderAges(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''
    SELECT _id, date_diff(:now, createdAt, 'minute') AS ageMinutes
    FROM orders
    WHERE status = 'open'
    ''',
    arguments: {'now': utcTimestamp()},
  );
  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Picking the "winner" of two conflicting edits by comparing your own
/// timestamp fields. A device with a fast clock always wins. Ditto already
/// resolves concurrent register writes with its own Hybrid Logical Clock;
/// where order matters, model the data so the merge cannot go wrong (a
/// counter, a map keyed by ID, or an audit log with a derivation such as
/// "most advanced state").
Map<String, dynamic> pickLatestByUpdatedAt(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) =>
    (a['updatedAt'] as String).compareTo(b['updatedAt'] as String) >= 0 ? a : b;
