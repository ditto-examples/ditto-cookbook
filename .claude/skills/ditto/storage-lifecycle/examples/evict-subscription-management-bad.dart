// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// EVICT with Subscription Management (Anti-Patterns)
// ============================================================================
//
// This example demonstrates common mistakes when using EVICT in Ditto,
// which lead to resync loops, performance issues, and data inconsistencies.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ EVICT without canceling subscription (resync loop)
// 2. ❌ Same query for subscription and eviction
// 3. ❌ Frequent EVICT calls (performance degradation)
// 4. ❌ Subscription inside function (not at top level)
// 5. ❌ No subscription recreation after EVICT
// 6. ❌ EVICT without verification
// 7. ❌ Concurrent EVICT operations
//
// WHY THESE ARE PROBLEMS:
// - Resync loops: Evicted data immediately re-downloaded
// - Performance: Wasted bandwidth and battery
// - Data inconsistency: Subscription state confusion
// - Memory leaks: Orphaned subscriptions
//
// SOLUTION: See evict-subscription-management-good.dart for correct patterns
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: EVICT Without Canceling Subscription (Resync Loop)
// ============================================================================

/// ❌ BAD: EVICT while subscription is active
class MessageCleanupBadResyncLoop {
  final Ditto ditto;
  DittoSyncSubscription? _messageSubscription;

  MessageCleanupBadResyncLoop(this.ditto) {
    _initializeSubscription();
  }

  void _initializeSubscription() {
    // Subscribe to all messages
    _messageSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM messages',
    );
    print('✅ Subscribed to all messages');
  }

  /// ❌ BAD: EVICT without canceling subscription
  Future<void> cleanupOldMessages() async {
    print('❌ Attempting cleanup WITHOUT canceling subscription:');

    // ❌ Subscription is still active!
    // ❌ No cancellation before EVICT

    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    await ditto.store.execute(
      '''
      EVICT FROM messages
      WHERE createdAt < :cutoffDate
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    print('  EVICT completed locally...');

    // 🚨 RESYNC LOOP STARTS:
    // 1. Old messages evicted locally
    // 2. Active subscription notices missing documents
    // 3. Subscription requests old messages from peers/cloud
    // 4. Old messages re-downloaded immediately
    // 5. Storage full again, wasted bandwidth and battery
    // 6. User thinks cleanup worked, but storage still full

    print('');
    print('🚨 RESYNC LOOP:');
    print('   1. Old messages evicted locally');
    print('   2. Active subscription detects missing docs');
    print('   3. Old messages immediately re-downloaded');
    print('   4. Storage full again!');
    print('   5. Bandwidth and battery wasted');
  }

  void dispose() {
    _messageSubscription?.cancel();
  }
}

// ============================================================================
// ANTI-PATTERN 2: Same Query for Subscription and Eviction
// ============================================================================

/// ❌ BAD: Subscription and eviction use same query
class OrderCleanupBadSameQuery {
  final Ditto ditto;
  DittoSyncSubscription? _orderSubscription;

  OrderCleanupBadSameQuery(this.ditto) {
    _initializeSubscription();
  }

  void _initializeSubscription() {
    // ❌ BAD: Subscribe to old completed orders
    _orderSubscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM orders
      WHERE status = 'completed' AND completedAt < :cutoffDate
      ''',
      arguments: {
        'cutoffDate': DateTime.now()
            .subtract(const Duration(days: 90))
            .toIso8601String(),
      },
    );
    print('❌ Subscribed to: Old completed orders');
  }

  Future<void> cleanupOldOrders() async {
    print('❌ Attempting cleanup with SAME query:');

    // Cancel subscription
    _orderSubscription?.cancel();
    await Future.delayed(const Duration(milliseconds: 500));

    // ❌ BAD: EVICT query is SAME as subscription query
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    await ditto.store.execute(
      '''
      EVICT FROM orders
      WHERE status = 'completed' AND completedAt < :cutoffDate
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    print('  EVICT completed...');

    // ❌ BAD: Recreate same subscription
    _initializeSubscription();

    // 🚨 PROBLEM:
    // - Subscription immediately re-syncs what was just evicted
    // - Defeats the purpose of EVICT
    // - Wasted bandwidth and processing

    print('');
    print('🚨 PROBLEM:');
    print('   - Subscription query matches EVICT query');
    print('   - Re-subscribing immediately re-downloads evicted data');
    print('   - EVICT had no lasting effect');
  }

  void dispose() {
    _orderSubscription?.cancel();
  }
}

// ============================================================================
// ANTI-PATTERN 3: Frequent EVICT Calls (Performance Degradation)
// ============================================================================

/// ❌ BAD: Running EVICT too frequently
class FrequentCleanupBad {
  final Ditto ditto;

  FrequentCleanupBad(this.ditto);

  /// ❌ BAD: EVICT called on every data change
  Future<void> cleanupAfterEveryChange() async {
    print('❌ Running EVICT after every data change:');

    // User deletes one message
    await ditto.store.execute(
      'UPDATE messages SET isDeleted = true WHERE _id = :id',
      arguments: {'id': 'msg_123'},
    );

    // ❌ BAD: Immediately run EVICT
    await ditto.store.execute(
      'EVICT FROM messages WHERE isDeleted = true',
    );

    print('  EVICT run #1');

    // User deletes another message
    await ditto.store.execute(
      'UPDATE messages SET isDeleted = true WHERE _id = :id',
      arguments: {'id': 'msg_124'},
    );

    // ❌ BAD: Run EVICT again
    await ditto.store.execute(
      'EVICT FROM messages WHERE isDeleted = true',
    );

    print('  EVICT run #2');

    // 🚨 PROBLEMS:
    // - EVICT is expensive operation
    // - Should run max once per day
    // - Frequent EVICT degrades performance
    // - Battery drain
    // - Subscription churn (if canceled/recreated each time)

    print('');
    print('🚨 PROBLEMS:');
    print('   - EVICT run multiple times per session');
    print('   - Each EVICT is expensive operation');
    print('   - Performance degradation');
    print('   - Battery drain');
    print('   - Recommended: EVICT max once per 24 hours');
  }

  /// ❌ BAD: EVICT on app startup (every launch)
  Future<void> cleanupOnAppStart() async {
    print('❌ Running EVICT on every app launch:');

    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 7))
            .toIso8601String(),
      },
    );

    // 🚨 PROBLEM:
    // - User opens app multiple times per day
    // - EVICT runs on every launch
    // - Unnecessary overhead
    // - Should track last EVICT time and limit frequency

    print('  EVICT completed (will run again on next launch)');
    print('');
    print('🚨 PROBLEM:');
    print('   - EVICT runs on every app launch');
    print('   - User may launch app 10+ times per day');
    print('   - Should limit to once per 24 hours');
  }
}

// ============================================================================
// ANTI-PATTERN 4: Subscription Inside Function (Not Top-Level)
// ============================================================================

/// ❌ BAD: Creating subscription inside function
class DynamicSubscriptionBad {
  final Ditto ditto;

  DynamicSubscriptionBad(this.ditto);

  /// ❌ BAD: Subscription created inside cleanup function
  Future<void> cleanupWithInlineSubscription() async {
    print('❌ Creating subscription inside cleanup function:');

    // ❌ BAD: Subscription not declared at top level
    final tempSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM data WHERE important = true',
    );

    print('  Subscription created (inline)');

    // Do some work...
    await Future.delayed(const Duration(seconds: 1));

    // Cancel for EVICT
    tempSubscription.cancel();

    await ditto.store.execute(
      'EVICT FROM data WHERE important = false',
    );

    // ❌ BAD: Create another subscription inline
    final newSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM data WHERE important = true',
    );

    // 🚨 PROBLEMS:
    // - Subscriptions should be declared at top level
    // - Hard to track subscription state
    // - Easy to create subscription leaks
    // - Subscription lifecycle unclear
    // - Multiple subscriptions for same query may exist

    print('');
    print('🚨 PROBLEMS:');
    print('   - Subscriptions not at top level');
    print('   - Hard to track and manage');
    print('   - Potential subscription leaks');
    print('   - Unclear lifecycle');
  }
}

// ============================================================================
// ANTI-PATTERN 5: No Subscription Recreation After EVICT
// ============================================================================

/// ❌ BAD: Cancel subscription but never recreate
class NoRecreationBad {
  final Ditto ditto;
  DittoSyncSubscription? _dataSubscription;

  NoRecreationBad(this.ditto) {
    _initializeSubscription();
  }

  void _initializeSubscription() {
    _dataSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM data WHERE createdAt >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      },
    );
    print('✅ Subscription created');
  }

  Future<void> cleanupWithoutRecreation() async {
    print('❌ Cleanup without subscription recreation:');

    // Cancel subscription (correct)
    _dataSubscription?.cancel();
    _dataSubscription = null;
    print('  Step 1: Subscription canceled ✅');

    await Future.delayed(const Duration(milliseconds: 500));

    // Perform EVICT (correct)
    await ditto.store.execute(
      'EVICT FROM data WHERE createdAt < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 90))
            .toIso8601String(),
      },
    );
    print('  Step 2: EVICT completed ✅');

    // ❌ BAD: Never recreate subscription!
    print('  Step 3: Subscription recreation... ❌ SKIPPED');

    // 🚨 PROBLEMS:
    // - App no longer receives data updates
    // - User sees stale data
    // - No new documents synced
    // - App appears broken

    print('');
    print('🚨 PROBLEMS:');
    print('   - Subscription canceled but not recreated');
    print('   - App stops receiving updates');
    print('   - User sees stale data');
    print('   - New documents not synced');
  }

  void dispose() {
    _dataSubscription?.cancel();
  }
}

// ============================================================================
// ANTI-PATTERN 6: EVICT Without Verification
// ============================================================================

/// ❌ BAD: No verification after EVICT
class NoVerificationBad {
  final Ditto ditto;

  NoVerificationBad(this.ditto);

  Future<void> cleanupWithoutVerification() async {
    print('❌ Cleanup without verification:');

    // Perform EVICT
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 60))
        .toIso8601String();

    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('  EVICT completed (assuming success)');

    // ❌ BAD: No verification
    // - Don't check if EVICT actually removed documents
    // - Don't count before/after
    // - Don't log how many documents evicted
    // - Can't tell if EVICT worked

    // 🚨 PROBLEMS:
    // - No confirmation EVICT worked
    // - Can't troubleshoot if storage still full
    // - No metrics for monitoring
    // - Hard to debug issues

    print('');
    print('🚨 PROBLEMS:');
    print('   - No verification after EVICT');
    print('   - Unknown if EVICT succeeded');
    print('   - Can\'t troubleshoot storage issues');
    print('   - No metrics for monitoring');
  }
}

// ============================================================================
// ANTI-PATTERN 7: Concurrent EVICT Operations
// ============================================================================

/// ❌ BAD: Multiple EVICT operations running simultaneously
class ConcurrentEvictBad {
  final Ditto ditto;
  bool _cleanupInProgress = false;

  ConcurrentEvictBad(this.ditto);

  /// ❌ BAD: No guard against concurrent EVICT
  Future<void> cleanupWithoutLock() async {
    // ❌ No check if cleanup already running
    // Multiple calls can execute simultaneously

    print('❌ Starting cleanup (no concurrency guard)...');

    // Cancel subscriptions
    await Future.delayed(const Duration(milliseconds: 500));

    // EVICT (slow operation)
    await ditto.store.execute(
      'EVICT FROM data WHERE old = true',
    );

    print('  Cleanup completed');

    // Recreate subscriptions

    // 🚨 PROBLEMS if called concurrently:
    // - Subscriptions canceled multiple times
    // - EVICT runs simultaneously (undefined behavior)
    // - Subscriptions recreated multiple times
    // - Wasted resources
    // - Potential crashes or data corruption
  }

  /// ✅ GOOD: Guard against concurrent execution
  Future<void> cleanupWithLock() async {
    if (_cleanupInProgress) {
      print('⚠️ Cleanup already in progress, skipping');
      return;
    }

    _cleanupInProgress = true;
    try {
      print('✅ Starting cleanup (with concurrency guard)...');

      // Perform cleanup...
      await Future.delayed(const Duration(seconds: 2));

      print('✅ Cleanup completed');
    } finally {
      _cleanupInProgress = false;
    }
  }
}

// ============================================================================
// ANTI-PATTERN 8: Ignoring Errors During EVICT
// ============================================================================

/// ❌ BAD: No error handling during cleanup
class NoErrorHandlingBad {
  final Ditto ditto;
  DittoSyncSubscription? _subscription;

  NoErrorHandlingBad(this.ditto) {
    _initializeSubscription();
  }

  void _initializeSubscription() {
    _subscription = ditto.sync.registerSubscription(
      'SELECT * FROM data',
    );
  }

  /// ❌ BAD: No try-catch around cleanup operations
  Future<void> cleanupWithoutErrorHandling() async {
    print('❌ Cleanup without error handling:');

    // Cancel subscription
    _subscription?.cancel();
    _subscription = null;

    // ❌ No try-catch around EVICT
    await ditto.store.execute(
      'EVICT FROM data WHERE old = true',
    );

    // ❌ If EVICT fails:
    // - Subscription is canceled
    // - EVICT threw error
    // - Subscription never recreated
    // - App broken (no subscription, no data updates)

    // Should be:
    _initializeSubscription(); // But this won't run if EVICT fails!

    // 🚨 PROBLEM:
    // - If EVICT fails, subscription not restored
    // - App left in broken state
    // - Need try-catch with finally block to ensure restoration
  }

  void dispose() {
    _subscription?.cancel();
  }
}

// ============================================================================
// ANTI-PATTERN 9: Wrong Cutoff Date Calculation
// ============================================================================

/// ❌ BAD: Incorrect date math for cutoff
class WrongCutoffBad {
  final Ditto ditto;

  WrongCutoffBad(this.ditto);

  Future<void> cleanupWithWrongCutoff() async {
    print('❌ Cleanup with incorrect cutoff date:');

    // ❌ BAD: Using current time instead of date
    final wrongCutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    // Problem: This includes timestamp (hours, minutes, seconds)
    // Each EVICT run has slightly different cutoff
    // Inconsistent behavior

    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {'cutoff': wrongCutoff},
    );

    print('  Cutoff: $wrongCutoff (includes time component)');

    // ✅ BETTER: Use start of day
    final correctCutoff = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ).subtract(const Duration(days: 30)).toIso8601String();

    print('  Better cutoff: $correctCutoff (start of day)');

    // This ensures consistent behavior across multiple EVICT runs
  }
}

// ============================================================================
// ANTI-PATTERN 10: Evicting Too Much Data
// ============================================================================

/// ❌ BAD: EVICT without WHERE clause (evicts everything)
class EvictTooMuchBad {
  final Ditto ditto;

  EvictTooMuchBad(this.ditto);

  Future<void> cleanupEverything() async {
    print('❌ EVICT without proper filtering:');

    // ❌ DANGEROUS: EVICT without WHERE clause
    // This could evict ALL documents from collection!
    await ditto.store.execute(
      'EVICT FROM messages',
    );

    // 🚨 EXTREME DANGER:
    // - ALL messages evicted
    // - User loses all local data
    // - Must re-sync entire collection
    // - Massive bandwidth usage
    // - Very bad user experience

    print('');
    print('🚨 EXTREME DANGER:');
    print('   - EVICT without WHERE clause');
    print('   - ALL documents evicted');
    print('   - User loses all local data');
    print('   - Must re-download everything');
  }

  Future<void> cleanupWithBroadFilter() async {
    print('❌ EVICT with too broad filter:');

    // ❌ BAD: Filter matches too many documents
    await ditto.store.execute(
      'EVICT FROM orders WHERE status = "completed"',
    );

    // Problem: Evicts ALL completed orders (no time limit)
    // Better: Add time restriction

    // ✅ BETTER:
    await ditto.store.execute(
      '''
      EVICT FROM orders
      WHERE status = "completed" AND completedAt < :cutoff
      ''',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 90))
            .toIso8601String(),
      },
    );

    print('  Better: EVICT only old completed orders');
  }
}
