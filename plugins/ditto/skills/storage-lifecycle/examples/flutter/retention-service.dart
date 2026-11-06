// Ditto SDK: 5.2.0 (Flutter package ditto_live)
//
// Services that own the subscriptions and run evictions on a schedule.
//
// The DQL and the rules are in ../evict-subscription-management-good.sql,
// ../ttl-eviction-small-peer.sql, and ../soft-delete-relay.sql. The same
// services for the other SDKs are in examples/<sdk>/retention-service.*.
//
// Guide: § EVICT, § Time-based eviction, § Batching evictions,
//   § Soft delete, subscriptions, and cleanup, § Subscriptions in Flutter

import 'package:ditto_live/ditto_live.dart';

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

// ============================================================================
// Time-based retention: subscription + complementary, batched eviction
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
// Soft delete, Variant B: retention window, device-side EVICT
// ============================================================================

/// Keeps active orders and orders deleted within the retention window, and
/// evicts older deleted orders.
class OrderSoftDeleteRetention {
  OrderSoftDeleteRetention(this.ditto, this.storeId);

  final Ditto ditto;
  final String storeId;

  /// Longer than the longest time a device is expected to stay offline.
  static const retention = Duration(days: 30);

  SyncSubscription? _subscription;

  String _cutoff() => utcTimestamp(DateTime.now().subtract(retention));

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribe(_cutoff());
  }

  /// Call on a schedule, at most about once a day. The cutoff moves only here,
  /// never on screen changes.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();
    _subscription?.cancel();
    try {
      final result = await ditto.store.execute(
        'EVICT FROM orders '
        'WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );
      return result.mutatedDocumentIDs().length;
    } finally {
      _subscription = _subscribe(cutoff);
    }
  }

  SyncSubscription _subscribe(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId '
        'AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}

// ============================================================================
// Switching stores (the needed data changes)
// ============================================================================

/// Owns the store-scoped subscriptions for the app session.
class StoreSync {
  StoreSync(this.ditto);

  final Ditto ditto;
  final List<SyncSubscription> _subscriptions = [];
  String? _currentStoreId;

  /// Call after login or when the user switches to another store.
  Future<void> switchStore(String newStoreId) async {
    // 1. Stop asking for the old store's data.
    _cancelSubscriptions();

    // 2. Remove the old store's documents from this device only.
    _currentStoreId = newStoreId;
    await _evictOtherStores(newStoreId);

    // 3. Ask for the new store's data.
    _subscriptions
      ..add(ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId',
        arguments: {'storeId': newStoreId},
      ))
      ..add(ditto.sync.registerSubscription(
        'SELECT * FROM orderItems WHERE storeId = :storeId',
        arguments: {'storeId': newStoreId},
      ));
  }

  /// Data that was already being transferred when the old subscriptions were
  /// cancelled can still arrive afterwards. Call this later, for example on the
  /// next app start or from a periodic cleanup, to evict it again.
  Future<void> evictLateArrivals() async {
    final storeId = _currentStoreId;
    if (storeId != null) await _evictOtherStores(storeId);
  }

  Future<void> _evictOtherStores(String storeId) async {
    await ditto.store.execute(
      'EVICT FROM orders WHERE storeId != :storeId',
      arguments: {'storeId': storeId},
    );
    await ditto.store.execute(
      'EVICT FROM orderItems WHERE storeId != :storeId',
      arguments: {'storeId': storeId},
    );
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      subscription.cancel(); // No-op if already cancelled or Ditto was closed.
    }
    _subscriptions.clear();
  }

  /// Call on logout.
  void dispose() {
    _cancelSubscriptions();
  }
}

// ============================================================================
// Run eviction at most once per day
// ============================================================================

/// Runs the retention cleanup at most once per day, for example when the app
/// starts after hours. Persist [lastRun] in your own storage if needed.
class DailyEvictionScheduler {
  DailyEvictionScheduler(this.retention);

  final OrderRetention retention;
  DateTime? lastRun;

  Future<void> runIfDue() async {
    final now = DateTime.now().toUtc();
    final last = lastRun;
    if (last != null && now.difference(last) < const Duration(days: 1)) {
      return;
    }
    lastRun = now;
    await retention.evictExpired();
  }
}

// ============================================================================
// ❌ Anti-pattern: evicting on every screen visit
// ============================================================================

// ❌ BAD: An eviction in a widget's initState() runs on every screen visit.
// Each eviction triggers a resync with every connected peer. Use the
// scheduler above instead.
