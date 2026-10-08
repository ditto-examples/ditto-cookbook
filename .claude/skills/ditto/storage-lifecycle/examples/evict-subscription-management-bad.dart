// SDK Version: ditto_live 5.1.0
// Platform: Flutter (the DQL applies to all SDKs)
// Last Updated: 2026-10-08
//
// EVICT anti-patterns. Every function below compiles and runs, but defeats
// the purpose of eviction or removes nothing.
//
// Guide: .claude/guides/best-practices/ditto.md#evict
//        .claude/guides/best-practices/ditto.md#eviction-frequency
//
// Corrected versions: evict-subscription-management-good.dart

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';

String cutoffDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

// ============================================================================
// ❌ Anti-pattern 1: Evicting while a matching subscription is active
// ============================================================================

class OrderCleanupStillSubscribed {
  OrderCleanupStillSubscribed(this.ditto)
      : _subscription = ditto.sync.registerSubscription('SELECT * FROM orders');

  final Ditto ditto;
  final SyncSubscription _subscription;

  /// ❌ BAD: The subscription still matches the evicted documents, so connected
  /// peers notice they are missing and sync them back.
  Future<void> evictOld() async {
    await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDaysAgo(7)},
    );
  }

  void dispose() => _subscription.cancel();
}

// ============================================================================
// ❌ Anti-pattern 2: Evict, then re-subscribe to everything
// ============================================================================

/// ❌ BAD: Cancelling first is not enough. The new subscription matches the
/// evicted documents again, so they sync straight back.
/// ✅ FIX: Subscribe with `createdAt >= :cutoff` using the same cutoff.
Future<SyncSubscription> evictAndResubscribeEverything(
  Ditto ditto,
  SyncSubscription subscription,
  String cutoff,
) async {
  subscription.cancel();
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoff},
  );
  return ditto.sync.registerSubscription('SELECT * FROM orders');
}

// ============================================================================
// ❌ Anti-pattern 3: Subscription and eviction boundaries do not match
// ============================================================================

/// ❌ BAD: The subscription keeps 30 days, the eviction removes everything
/// older than 7 days. Documents between 7 and 30 days old are evicted and
/// synced back on every run.
/// ✅ FIX: Use one cutoff value for both statements (`>=` and `<`).
Future<SyncSubscription> mismatchedBoundaries(
  Ditto ditto,
  SyncSubscription subscription,
) async {
  subscription.cancel();
  await ditto.store.execute(
    'EVICT FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoffDaysAgo(7)},
  );
  return ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE createdAt >= :cutoff',
    arguments: {'cutoff': cutoffDaysAgo(30)},
  );
}

// ============================================================================
// ❌ Anti-pattern 4: Evicting on every screen visit
// ============================================================================

/// ❌ BAD: Each eviction triggers a resync with every connected peer. Evicting
/// on every screen visit overloads them. (SDK 5.1+) Ditto logs a warning when
/// post-eviction cleanup runs too frequently.
/// ✅ FIX: Evict on a schedule, at most about once per day.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.ditto});

  final Ditto ditto;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    widget.ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDaysAgo(7)},
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ============================================================================
// ❌ Anti-pattern 5: USE IDS without WHERE
// ============================================================================

/// ❌ BAD (SDK 5.1.0): Completes without an error but evicts nothing.
/// ✅ FIX: `EVICT FROM orders WHERE _id IN :ids`.
Future<void> evictWithUseIds(Ditto ditto, List<String> orderIds) async {
  await ditto.store.execute(
    'EVICT FROM orders USE IDS LIST :ids',
    arguments: {'ids': orderIds},
  );
}

// ============================================================================
// ❌ Anti-pattern 6: Losing the subscription reference
// ============================================================================

/// ❌ BAD: Without a reference, the subscription cannot be cancelled before
/// eviction. Do not rely on garbage collection to cancel it.
/// ✅ FIX: Keep subscriptions in a long-lived service and cancel them there.
void subscribeAndForget(Ditto ditto) {
  ditto.sync.registerSubscription('SELECT * FROM orders');
}

// ============================================================================
// ❌ Anti-pattern 7: Using DELETE to free local storage
// ============================================================================

/// ❌ BAD: DELETE removes the documents for every peer and leaves tombstones.
/// ✅ FIX: Use EVICT (local only) with a complementary subscription.
Future<void> freeSpaceWithDelete(Ditto ditto) async {
  await ditto.store.execute(
    'DELETE FROM orders WHERE createdAt < :cutoff',
    arguments: {'cutoff': cutoffDaysAgo(7)},
  );
}

// ============================================================================
// ❌ Anti-pattern 8: Evicting soft-deleted documents that the subscription
// still covers
// ============================================================================

/// ❌ BAD: With a whole-collection subscription (Variant A), soft-deleted
/// documents still match it, so evicted documents sync straight back.
/// ✅ FIX: Either clean up with a DELETE on the Ditto Server that syncs to every
/// device (Variant A), or subscribe with a retention window and evict its exact
/// complement (Variant B). See soft-delete-relay.dart.
Future<void> evictSoftDeletedWhileSubscribed(Ditto ditto, String storeId) async {
  ditto.sync.registerSubscription(
    'SELECT * FROM orders WHERE storeId = :storeId',
    arguments: {'storeId': storeId},
  );
  await ditto.store.execute(
    'EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true',
    arguments: {'storeId': storeId},
  );
}
