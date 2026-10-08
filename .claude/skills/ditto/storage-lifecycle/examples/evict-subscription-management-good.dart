// SDK Version: ditto_live 5.1.0
// Platform: Flutter (the DQL applies to all SDKs)
// Last Updated: 2026-10-08
//
// EVICT with correct subscription management.
//
// Guide: .claude/guides/best-practices/ditto.md#evict
//        .claude/guides/best-practices/ditto.md#cancelling-subscriptions-and-local-data
//
// Key rules:
// - EVICT removes documents from this device only. If an active subscription
//   still matches them, connected peers sync them back.
// - Cancel or narrow the affected subscriptions BEFORE evicting.
// - Evict exactly the complement of the remaining subscriptions (same cutoff,
//   `>=` in the subscription, `<` in the eviction).
// - Keep subscription references in a long-lived service so they can be
//   cancelled.
// - Evict on a schedule, at most about once per day.
// - Target documents by ID with `WHERE _id IN :ids`, never `USE IDS` alone.

import 'dart:async';

import 'package:ditto_live/ditto_live.dart';

// ============================================================================
// Pattern 1: Time-based retention with complementary queries
// ============================================================================

/// Keeps the last 7 days of orders on this device.
class OrderRetention {
  OrderRetention(this.ditto);

  final Ditto ditto;
  static const retention = Duration(days: 7);
  SyncSubscription? _subscription;

  String _cutoff() =>
      DateTime.now().toUtc().subtract(retention).toIso8601String();

  /// Call once at startup (before ditto.sync.start()).
  void start() {
    _subscription = _subscribeFrom(_cutoff());
  }

  /// Call on a schedule, for example once a day.
  Future<int> evictExpired() async {
    final cutoff = _cutoff();

    // 1. Stop asking peers for the documents that are about to be evicted.
    _subscription?.cancel();

    // 2. Evict exactly the complement of the new subscription.
    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    // 3. Subscribe again with the moved boundary.
    _subscription = _subscribeFrom(cutoff);
    return result.mutatedDocumentIDs().length;
  }

  SyncSubscription _subscribeFrom(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE createdAt >= :cutoff',
        arguments: {'cutoff': cutoff},
      );

  void dispose() => _subscription?.cancel();
}

// ============================================================================
// Pattern 2: Switching stores (the needed data changes)
// ============================================================================

/// Owns the store-scoped subscriptions for the app session.
class StoreSync {
  StoreSync(this.ditto);

  final Ditto ditto;
  final List<SyncSubscription> _subscriptions = [];
  Timer? _lateArrivalCleanup;

  /// Call after login or when the user switches to another store.
  Future<void> switchStore(String newStoreId) async {
    // 1. Stop asking for the old store's data.
    _cancelSubscriptions();

    // 2. Remove the old store's documents from this device only.
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

    // 4. Documents that were in flight through the cancelled subscriptions can
    //    still arrive, so run the same eviction again after a short delay.
    _lateArrivalCleanup?.cancel();
    _lateArrivalCleanup = Timer(const Duration(seconds: 5), () {
      unawaited(_evictOtherStores(newStoreId));
    });
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
    _lateArrivalCleanup?.cancel();
    _cancelSubscriptions();
  }
}

// ============================================================================
// Pattern 3: Evicting specific documents by ID
// ============================================================================

/// ✅ GOOD: `WHERE _id IN :ids` is planned as an ID scan. Only evict IDs that
/// no active subscription on this device still matches.
Future<List<String>> evictOrdersById(Ditto ditto, List<String> orderIds) async {
  final result = await ditto.store.execute(
    'EVICT FROM orders WHERE _id IN :ids RETURNING _id',
    arguments: {'ids': orderIds},
  );
  return [for (final item in result.items) item.value['_id'] as String];
}

// ============================================================================
// Pattern 4: Run eviction at most once per day
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
