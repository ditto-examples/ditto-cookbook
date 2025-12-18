// ============================================================================
// EVICT with Subscription Management (Recommended Pattern)
// ============================================================================
//
// This example demonstrates the correct pattern for using EVICT in Ditto,
// which requires careful subscription management to avoid resync loops.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Top-level subscription declaration
// 2. ✅ Cancel → EVICT → recreate pattern
// 3. ✅ Opposite query for subscription/eviction
// 4. ✅ Scheduled daily eviction
// 5. ✅ EVICT frequency limits (max once/day)
// 6. ✅ Error handling for EVICT operations
// 7. ✅ Verification after EVICT
//
// CRITICAL RULES FOR EVICT:
// 1. MUST cancel subscription before EVICT
// 2. MUST use opposite query (subscription != eviction query)
// 3. MUST recreate subscription after EVICT
// 4. SHOULD limit EVICT frequency (once per day max)
// 5. MUST declare subscriptions at top level (not inside functions)
//
// WHY THESE RULES:
// - EVICT with active subscription → immediate resync loop
// - Same query → EVICT removes what subscription re-syncs
// - No subscription cancellation → documents immediately re-downloaded
// - Frequent EVICT → performance degradation
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Top-Level Subscription Declaration
// ============================================================================

/// ✅ GOOD: Declare subscription at top level (not inside function)
class MessageManager {
  final Ditto ditto;
  DittoSyncSubscription? _messageSubscription;

  MessageManager(this.ditto);

  /// Initialize subscription (called once at app start)
  void initializeSubscription() {
    // ✅ GOOD: Subscribe to recent messages only (last 30 days)
    _messageSubscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM messages
      WHERE createdAt >= :cutoffDate
      ORDER BY createdAt DESC
      ''',
      arguments: {
        'cutoffDate': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      },
    );

    print('✅ Subscription created: Recent messages (last 30 days)');
    print('   This subscription stays active until explicitly canceled');
  }

  /// Cancel subscription before EVICT
  void cancelSubscription() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    print('✅ Subscription canceled (preparing for EVICT)');
  }

  /// Recreate subscription after EVICT
  void recreateSubscription() {
    initializeSubscription();
    print('✅ Subscription recreated (after EVICT)');
  }

  void dispose() {
    _messageSubscription?.cancel();
  }
}

// ============================================================================
// PATTERN 2: Cancel → EVICT → Recreate Pattern
// ============================================================================

/// ✅ GOOD: Proper EVICT lifecycle
class MessageCleanupManager {
  final Ditto ditto;
  final MessageManager messageManager;

  MessageCleanupManager(this.ditto, this.messageManager);

  /// Clean up old messages (correct pattern)
  Future<void> cleanupOldMessages() async {
    print('✅ Starting cleanup process:');

    // Step 1: Cancel active subscription
    print('  Step 1: Canceling subscription...');
    messageManager.cancelSubscription();

    // Step 2: Wait a moment to ensure subscription fully canceled
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: EVICT old messages (opposite query from subscription)
    print('  Step 2: Evicting old messages...');
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

    print('  Step 3: EVICT completed (messages older than 90 days removed)');

    // Step 4: Recreate subscription
    print('  Step 4: Recreating subscription...');
    messageManager.recreateSubscription();

    print('✅ Cleanup complete:');
    print('   - Old messages evicted locally');
    print('   - Subscription re-established for recent messages');
  }
}

// ============================================================================
// PATTERN 3: Opposite Query for Subscription/Eviction
// ============================================================================

/// ✅ GOOD: Subscription and eviction use opposite queries
class OrderManager {
  final Ditto ditto;
  DittoSyncSubscription? _activeOrdersSubscription;

  OrderManager(this.ditto);

  /// Subscribe to active orders
  void subscribeToActiveOrders() {
    // ✅ GOOD: Subscribe to active orders (status NOT completed)
    _activeOrdersSubscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM orders
      WHERE status IN ('pending', 'processing', 'shipped')
      ''',
    );

    print('✅ Subscribed to: Active orders (pending/processing/shipped)');
  }

  /// Clean up completed orders
  Future<void> cleanupCompletedOrders() async {
    print('✅ Cleaning up completed orders:');

    // Step 1: Cancel subscription
    _activeOrdersSubscription?.cancel();
    _activeOrdersSubscription = null;
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: EVICT completed orders (opposite query)
    // ✅ GOOD: Eviction query is OPPOSITE of subscription
    // Subscription: status IN ('pending', 'processing', 'shipped')
    // Eviction: status = 'completed' AND older than 90 days
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

    print('  Evicted: Completed orders older than 90 days');

    // Step 3: Recreate subscription
    subscribeToActiveOrders();

    print('✅ Cleanup complete:');
    print('   - Subscription: Active orders (NOT affected by EVICT)');
    print('   - Evicted: Old completed orders (NOT covered by subscription)');
    print('   - No resync loop because queries are opposite');
  }

  void dispose() {
    _activeOrdersSubscription?.cancel();
  }
}

// ============================================================================
// PATTERN 4: Scheduled Daily Eviction
// ============================================================================

/// ✅ GOOD: Schedule EVICT to run once per day
class ScheduledCleanupManager {
  final Ditto ditto;
  DateTime? _lastCleanupTime;
  static const _cleanupInterval = Duration(hours: 24);

  ScheduledCleanupManager(this.ditto) {
    _scheduleCleanup();
  }

  void _scheduleCleanup() {
    // Run cleanup check every hour
    Future.delayed(const Duration(hours: 1), () {
      _checkAndRunCleanup();
      _scheduleCleanup(); // Reschedule
    });
  }

  Future<void> _checkAndRunCleanup() async {
    final now = DateTime.now();

    // Check if 24 hours passed since last cleanup
    if (_lastCleanupTime == null ||
        now.difference(_lastCleanupTime!) >= _cleanupInterval) {
      print('✅ Running scheduled cleanup (24 hours elapsed)');
      await _performCleanup();
      _lastCleanupTime = now;
    } else {
      final timeUntilNext = _cleanupInterval - now.difference(_lastCleanupTime!);
      print('⏱️ Next cleanup in ${timeUntilNext.inHours} hours');
    }
  }

  Future<void> _performCleanup() async {
    // Cancel subscriptions
    // (Assuming subscription management is handled elsewhere)

    await Future.delayed(const Duration(milliseconds: 500));

    // EVICT old data
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await ditto.store.execute(
      '''
      EVICT FROM logs
      WHERE timestamp < :cutoffDate
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    print('✅ Scheduled cleanup completed');

    // Recreate subscriptions
    // (Assuming subscription management is handled elsewhere)
  }

  /// Manual cleanup (respects frequency limit)
  Future<void> requestManualCleanup() async {
    final now = DateTime.now();

    if (_lastCleanupTime != null &&
        now.difference(_lastCleanupTime!) < _cleanupInterval) {
      print('⚠️ Cleanup requested too frequently');
      print('   Last cleanup: ${_lastCleanupTime}');
      print('   Next allowed: ${_lastCleanupTime!.add(_cleanupInterval)}');
      return;
    }

    print('✅ Running manual cleanup (frequency limit respected)');
    await _performCleanup();
    _lastCleanupTime = now;
  }
}

// ============================================================================
// PATTERN 5: EVICT with Error Handling
// ============================================================================

/// ✅ GOOD: Robust error handling for EVICT operations
class RobustCleanupManager {
  final Ditto ditto;

  RobustCleanupManager(this.ditto);

  Future<void> safeCleanup({
    required void Function() cancelSubscriptions,
    required void Function() recreateSubscriptions,
  }) async {
    bool subscriptionsCanceled = false;
    bool evictCompleted = false;

    try {
      // Step 1: Cancel subscriptions
      print('✅ Step 1: Canceling subscriptions...');
      cancelSubscriptions();
      subscriptionsCanceled = true;
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Perform EVICT
      print('✅ Step 2: Running EVICT...');
      final cutoffDate = DateTime.now()
          .subtract(const Duration(days: 60))
          .toIso8601String();

      await ditto.store.execute(
        '''
        EVICT FROM documents
        WHERE isDeleted = true AND deletedAt < :cutoffDate
        ''',
        arguments: {'cutoffDate': cutoffDate},
      );

      evictCompleted = true;
      print('✅ Step 3: EVICT completed successfully');

      // Step 3: Recreate subscriptions
      print('✅ Step 4: Recreating subscriptions...');
      recreateSubscriptions();
      print('✅ Cleanup completed successfully');

    } catch (e) {
      print('❌ Error during cleanup: $e');

      // Recovery: Recreate subscriptions even if EVICT failed
      if (subscriptionsCanceled && !evictCompleted) {
        print('⚠️ EVICT failed, restoring subscriptions...');
        try {
          recreateSubscriptions();
          print('✅ Subscriptions restored after error');
        } catch (restoreError) {
          print('❌ Failed to restore subscriptions: $restoreError');
          // Critical error: App may need restart
        }
      }

      rethrow;
    }
  }
}

// ============================================================================
// PATTERN 6: Verification After EVICT
// ============================================================================

/// ✅ GOOD: Verify EVICT operation completed correctly
class VerifiedCleanupManager {
  final Ditto ditto;

  VerifiedCleanupManager(this.ditto);

  Future<void> cleanupWithVerification() async {
    // Count documents before EVICT
    final beforeResult = await ditto.store.execute(
      'SELECT COUNT(*) as count FROM messages',
    );
    final beforeCount = beforeResult.items.first.value['count'] as int;
    print('✅ Documents before EVICT: $beforeCount');

    // Cancel subscriptions (assuming managed elsewhere)
    await Future.delayed(const Duration(milliseconds: 500));

    // Perform EVICT
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await ditto.store.execute(
      '''
      EVICT FROM messages
      WHERE createdAt < :cutoffDate
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    // Count documents after EVICT
    final afterResult = await ditto.store.execute(
      'SELECT COUNT(*) as count FROM messages',
    );
    final afterCount = afterResult.items.first.value['count'] as int;
    print('✅ Documents after EVICT: $afterCount');

    // Verify EVICT worked
    final evictedCount = beforeCount - afterCount;
    print('✅ Evicted documents: $evictedCount');

    if (evictedCount > 0) {
      print('✅ EVICT verification: SUCCESS');
    } else {
      print('⚠️ EVICT verification: No documents evicted (expected?)');
    }

    // Recreate subscriptions (assuming managed elsewhere)
  }
}

// ============================================================================
// PATTERN 7: Multi-Collection Cleanup
// ============================================================================

/// ✅ GOOD: Clean up multiple collections in single operation
class MultiCollectionCleanupManager {
  final Ditto ditto;
  final Map<String, DittoSyncSubscription> _subscriptions = {};

  MultiCollectionCleanupManager(this.ditto);

  void initializeSubscriptions() {
    // Messages subscription
    _subscriptions['messages'] = ditto.sync.registerSubscription(
      'SELECT * FROM messages WHERE createdAt >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      },
    );

    // Logs subscription
    _subscriptions['logs'] = ditto.sync.registerSubscription(
      'SELECT * FROM logs WHERE timestamp >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 7))
            .toIso8601String(),
      },
    );

    // Events subscription
    _subscriptions['events'] = ditto.sync.registerSubscription(
      'SELECT * FROM events WHERE timestamp >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 90))
            .toIso8601String(),
      },
    );

    print('✅ Initialized subscriptions for 3 collections');
  }

  Future<void> cleanupAllCollections() async {
    print('✅ Starting multi-collection cleanup:');

    // Step 1: Cancel all subscriptions
    print('  Step 1: Canceling all subscriptions...');
    for (final entry in _subscriptions.entries) {
      entry.value.cancel();
      print('    Canceled: ${entry.key}');
    }
    _subscriptions.clear();
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: EVICT from all collections
    print('  Step 2: Evicting from all collections...');

    // Messages (keep 60 days)
    await ditto.store.execute(
      'EVICT FROM messages WHERE createdAt < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 60))
            .toIso8601String(),
      },
    );
    print('    Evicted: messages older than 60 days');

    // Logs (keep 14 days)
    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 14))
            .toIso8601String(),
      },
    );
    print('    Evicted: logs older than 14 days');

    // Events (keep 180 days)
    await ditto.store.execute(
      'EVICT FROM events WHERE timestamp < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 180))
            .toIso8601String(),
      },
    );
    print('    Evicted: events older than 180 days');

    // Step 3: Recreate all subscriptions
    print('  Step 3: Recreating subscriptions...');
    initializeSubscriptions();

    print('✅ Multi-collection cleanup complete');
  }

  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}

// ============================================================================
// PATTERN 8: Complete Example with All Best Practices
// ============================================================================

/// ✅ GOOD: Production-ready cleanup implementation
class ProductionCleanupManager {
  final Ditto ditto;
  DittoSyncSubscription? _dataSubscription;
  DateTime? _lastCleanupTime;
  bool _isCleanupInProgress = false;

  ProductionCleanupManager(this.ditto);

  void initialize() {
    _createSubscription();
    _schedulePeriodicCleanup();
  }

  void _createSubscription() {
    // Subscribe to recent data only (last 30 days)
    _dataSubscription = ditto.sync.registerSubscription(
      'SELECT * FROM data WHERE createdAt >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      },
    );
    print('✅ Subscription created: Recent data (30 days)');
  }

  void _schedulePeriodicCleanup() {
    // Check for cleanup every 6 hours
    Future.delayed(const Duration(hours: 6), () {
      _checkAndRunCleanup();
      _schedulePeriodicCleanup();
    });
  }

  Future<void> _checkAndRunCleanup() async {
    if (_isCleanupInProgress) {
      print('⏳ Cleanup already in progress, skipping');
      return;
    }

    final now = DateTime.now();
    if (_lastCleanupTime != null &&
        now.difference(_lastCleanupTime!) < const Duration(hours: 24)) {
      print('⏱️ Cleanup not needed yet (last run: ${_lastCleanupTime})');
      return;
    }

    await performCleanup();
  }

  Future<void> performCleanup() async {
    if (_isCleanupInProgress) {
      print('⚠️ Cleanup already in progress');
      return;
    }

    _isCleanupInProgress = true;

    try {
      print('✅ Starting cleanup process:');

      // 1. Cancel subscription
      print('  1/4: Canceling subscription...');
      _dataSubscription?.cancel();
      _dataSubscription = null;
      await Future.delayed(const Duration(milliseconds: 500));

      // 2. Count before EVICT
      final beforeResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM data',
      );
      final beforeCount = beforeResult.items.first.value['count'] as int;
      print('  2/4: Current document count: $beforeCount');

      // 3. Perform EVICT
      print('  3/4: Evicting old data...');
      final cutoffDate = DateTime.now()
          .subtract(const Duration(days: 90))
          .toIso8601String();

      await ditto.store.execute(
        'EVICT FROM data WHERE createdAt < :cutoff',
        arguments: {'cutoff': cutoffDate},
      );

      // 4. Verify and recreate subscription
      final afterResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM data',
      );
      final afterCount = afterResult.items.first.value['count'] as int;
      print('  4/4: Recreating subscription...');
      _createSubscription();

      _lastCleanupTime = DateTime.now();

      print('✅ Cleanup completed successfully:');
      print('   - Before: $beforeCount documents');
      print('   - After: $afterCount documents');
      print('   - Evicted: ${beforeCount - afterCount} documents');

    } catch (e) {
      print('❌ Cleanup failed: $e');

      // Recovery: Restore subscription
      if (_dataSubscription == null) {
        print('⚠️ Restoring subscription after error...');
        _createSubscription();
      }

      rethrow;
    } finally {
      _isCleanupInProgress = false;
    }
  }

  void dispose() {
    _dataSubscription?.cancel();
  }
}
