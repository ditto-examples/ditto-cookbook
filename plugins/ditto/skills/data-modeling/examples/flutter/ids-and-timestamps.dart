// Ditto SDK: 5.2.0 (Flutter package ditto_live)
//
// UUIDs, display numbers, and fixed-precision UTC timestamps in Dart
//
// The DQL that uses these values is in ../id-generation-patterns.sql and
// ../timestamps.sql. The same helpers for the other SDKs are in
// examples/<sdk>/ids-and-timestamps.* and on each SDK page.
//
// Guide: § Document IDs, § Timestamps, § IDs and Timestamps in Flutter

import 'dart:math';

import 'package:ditto_live/ditto_live.dart';

final _random = Random.secure();

/// ISO-8601 UTC string with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". ISO strings sort chronologically as text only
/// when they share one format. Native Dart prints microseconds
/// ("...00.123456Z"), but omits them when they are zero ("...00.123Z"), and the
/// web always prints milliseconds, so use this one helper for every timestamp
/// field that is sorted or compared.
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

/// Returns a random (version 4) UUID such as
/// "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f". A maintained package (for example,
/// `uuid` on pub.dev) works equally well.
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A display label, not an identifier: never use it as _id or as a lookup key.
String displayNumber(String terminalCode, int localSequence) =>
    '$terminalCode-${localSequence.toString().padLeft(4, '0')}';

/// ✅ GOOD: UUID v4 as _id, UTC timestamp from the helper.
Future<String> createOrder(Ditto ditto, String storeId) async {
  final orderId = uuidV4();
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': orderId,
        'storeId': storeId,
        'status': 'open',
        'createdAt': utcTimestamp(),
      },
    },
  );
  return orderId;
}

/// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
String badSequentialId(int dailyCount) => 'order-$dailyCount';

/// ❌ BAD: Collides when two devices write within the same millisecond.
String badTimestampId() => 'order-${DateTime.now().millisecondsSinceEpoch}';

/// ❌ BAD: Local time without a zone (for example "2026-10-08T19:30:00.123456").
/// DQL date functions return MISSING for it. Always convert to UTC first.
Future<void> markReadyIncorrectly(Ditto ditto, String orderId) async {
  await ditto.store.execute(
    'UPDATE orders SET readyAt = :readyAt WHERE _id = :id',
    arguments: {
      'id': orderId,
      'readyAt': DateTime.now().toIso8601String(), // lint-ignore
    },
  );
}
