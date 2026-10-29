// SDK Version: ditto_live 5.2.0
// Platform: Flutter (the DQL applies to all SDKs)
// Last Updated: 2026-10-30
//
// Device-local, time-based retention on a Small Peer, plus tombstone TTL
// settings passed when Ditto opens.
//
// Guide: § Time-based eviction
//        § Batching evictions
//        § Tombstone TTL and reaping
//
// Two different "TTLs" appear here:
// - Retention window (app logic): how long documents stay on this device.
//   Implemented with a time-scoped subscription and EVICT of the complement.
// - Tombstone TTL (system parameter TOMBSTONE_TTL_HOURS, default 168 = 7 days):
//   how long DELETE tombstones are kept before reaping. It is set in
//   DittoConfig.systemParameters (SDK 5.2+; on SDK 5.1, with ALTER SYSTEM
//   after every open and before sync.start()). There is no SDK method for it,
//   it is not persisted, and it must never exceed the Ditto Server tombstone
//   TTL.

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

/// ISO-8601 UTC timestamp with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z". Fixed precision keeps values sortable as text
/// (native Dart omits zero microseconds, so even one device would otherwise
/// mix precisions).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

/// Replace with your own token retrieval.
Future<String> fetchAuthToken() async => 'YOUR_AUTH_TOKEN';

// ============================================================================
// Startup: pass system parameters on every open (SDK 5.2+)
// ============================================================================

/// Example only: raise the tombstone TTL to 14 days because devices in this
/// deployment may stay offline for up to two weeks. Keep it at or below the
/// Ditto Server TTL; changes on the server side go through Ditto support.
/// System parameters are not persisted, so this configuration is used for
/// every open; Ditto applies them before it starts.
const storageConfig = DittoConfig(
  databaseID: 'YOUR_DATABASE_ID',
  connect: DittoConfigConnectServer(url: 'YOUR_SERVER_URL'),
  systemParameters: {'TOMBSTONE_TTL_HOURS': 336},
);

Future<(Ditto, OrderRetention)> startDitto() async {
  final ditto = await Ditto.open(storageConfig);

  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    final response = await ditto.auth.login(
      token: await fetchAuthToken(),
      provider: 'YOUR_PROVIDER_NAME',
    );
    if (response.exception != null) {
      // Report the failure; do not throw inside the handler.
      debugPrint('Login failed: ${response.exception}');
    }
  });

  final retention = OrderRetention(ditto)..start();
  ditto.sync.start();
  return (ditto, retention);
}

// ============================================================================
// Retention: time-scoped subscription + complementary, batched eviction
// ============================================================================

/// Keeps the last [retention] of orders on this device.
class OrderRetention {
  OrderRetention(this.ditto, {this.retention = const Duration(days: 7)});

  final Ditto ditto;
  final Duration retention;
  SyncSubscription? _subscription;

  // Same fixed-precision format as the stored timestamps (utcTimestamp()).
  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, at most about once per day, preferably at a quiet
  /// time.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for documents older than the new cutoff.
    _subscription?.cancel();

    try {
      // 2. Evict the complement in short batches.
      return await _evictInBatches(cutoff);
    } finally {
      // 3. Subscribe again with the moved boundary (same cutoff value), even if
      //    the eviction failed.
      _subscription = _subscribeFrom(cutoff);
    }
  }

  SyncSubscription _subscribeFrom(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE createdAt >= :cutoff',
        arguments: {'cutoff': cutoff},
      );

  /// Batching keeps each write transaction short. It does not reduce the sync
  /// cost of eviction: run the whole batched cleanup on the usual schedule,
  /// not as many separate cleanups.
  Future<int> _evictInBatches(String cutoff) async {
    var total = 0;
    while (true) {
      final result = await ditto.store.execute(
        'EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 '
        'RETURNING COUNT(*) AS evicted',
        arguments: {'cutoff': cutoff},
      );
      final evicted = result.items.first.value['evicted'] as int;
      total += evicted;
      if (evicted == 0) return total;
    }
  }

  void dispose() => _subscription?.cancel();
}

// ============================================================================
// Checking the effect
// ============================================================================

/// Reads the newest document count for orders from system:system_info.
/// The values are collected periodically and can lag behind recent writes.
Future<Object?> localOrderCount(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT key, value, timestamp FROM system:system_info "
    "WHERE key LIKE 'collection_num_docs%' "
    "ORDER BY timestamp ASC",
  );
  Object? latest;
  for (final item in result.items) {
    if (item.value['key'] == 'collection_num_docs[orders]') {
      latest = item.value['value'];
    }
  }
  return latest;
}
