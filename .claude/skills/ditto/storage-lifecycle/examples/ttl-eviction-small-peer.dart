// ============================================================================
// TTL-Based Eviction: Small Peer Pattern
// ============================================================================
//
// This example demonstrates device-local time-based eviction patterns for
// Small Peers (mobile/edge devices) that calculate and enforce their own TTL.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Device-local time-based eviction
// 2. ✅ Cutoff date calculation
// 3. ✅ Subscription management with time-based queries
// 4. ✅ Industry-specific TTL examples (7/30/90 days)
// 5. ✅ Rolling window pattern
// 6. ✅ Storage quota enforcement
// 7. ✅ Oldest-first eviction strategy
//
// WHEN TO USE SMALL PEER TTL:
// - No Big Peer/cloud server available
// - Device needs autonomous cleanup
// - Different TTL per device type
// - Offline-first applications
//
// TRADEOFFS:
// - Each device calculates TTL independently
// - Policy changes require app updates
// - Less centralized control than Big Peer pattern
// - More flexible for offline scenarios
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Basic Time-Based Eviction
// ============================================================================

/// Basic device-local TTL pattern
class BasicTtlEviction {
  final Ditto ditto;
  DittoSyncSubscription? _messageSubscription;

  BasicTtlEviction(this.ditto);

  /// Subscribe to recent messages only (last 30 days)
  void subscribeToRecentMessages() {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    // ✅ GOOD: Subscribe only to recent messages
    _messageSubscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM messages
      WHERE createdAt >= :cutoffDate
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    print('✅ Subscribed to messages from last 30 days');
    print('   Cutoff: $cutoffDate');
  }

  /// Evict old messages (older than 90 days)
  Future<void> evictOldMessages() async {
    print('📱 Starting time-based eviction...');

    // Step 1: Cancel subscription
    _messageSubscription?.cancel();
    _messageSubscription = null;
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Calculate cutoff (90 days ago)
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    print('  Evicting messages older than: $cutoffDate');

    // Step 3: EVICT old messages
    await ditto.store.execute(
      '''
      EVICT FROM messages
      WHERE createdAt < :cutoffDate
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    print('  ✅ Eviction completed');

    // Step 4: Recreate subscription (recent messages only)
    subscribeToRecentMessages();
  }

  void dispose() {
    _messageSubscription?.cancel();
  }
}

// ============================================================================
// PATTERN 2: Rolling Window Subscriptions
// ============================================================================

/// Subscription with rolling time window
class RollingWindowSubscription {
  final Ditto ditto;
  DittoSyncSubscription? _logsSubscription;

  RollingWindowSubscription(this.ditto);

  /// Create subscription with time-based filter
  void createTimeBoundSubscription() {
    // Subscribe to logs from last 7 days
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();

    _logsSubscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM logs
      WHERE timestamp >= :cutoffDate
      ORDER BY timestamp DESC
      ''',
      arguments: {'cutoffDate': cutoffDate},
    );

    print('✅ Rolling window subscription: Last 7 days of logs');
  }

  /// Update subscription window (called periodically)
  void refreshSubscriptionWindow() {
    print('🔄 Refreshing subscription window...');

    // Cancel old subscription
    _logsSubscription?.cancel();

    // Create new subscription with updated cutoff
    createTimeBoundSubscription();

    print('✅ Subscription window refreshed');
  }

  /// Schedule periodic window refresh (daily)
  void scheduleWindowRefresh() {
    Future.delayed(const Duration(hours: 24), () {
      refreshSubscriptionWindow();
      scheduleWindowRefresh(); // Reschedule
    });
  }

  void dispose() {
    _logsSubscription?.cancel();
  }
}

// ============================================================================
// PATTERN 3: Industry-Specific TTL Examples
// ============================================================================

/// 7-day TTL: Logs and diagnostic data
class SevenDayTtlManager {
  final Ditto ditto;

  SevenDayTtlManager(this.ditto);

  void subscribeToRecentLogs() {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();

    ditto.sync.registerSubscription(
      'SELECT * FROM logs WHERE timestamp >= :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Subscribed: Logs (7-day window)');
  }

  Future<void> evictOldLogs() async {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 14))
        .toIso8601String();

    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Evicted: Logs older than 14 days');
  }
}

/// 30-day TTL: Messages and notifications
class ThirtyDayTtlManager {
  final Ditto ditto;

  ThirtyDayTtlManager(this.ditto);

  void subscribeToRecentMessages() {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    ditto.sync.registerSubscription(
      'SELECT * FROM messages WHERE createdAt >= :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    ditto.sync.registerSubscription(
      'SELECT * FROM notifications WHERE createdAt >= :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Subscribed: Messages & notifications (30-day window)');
  }

  Future<void> evictOldContent() async {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 60))
        .toIso8601String();

    await ditto.store.execute(
      'EVICT FROM messages WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    await ditto.store.execute(
      'EVICT FROM notifications WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Evicted: Messages & notifications older than 60 days');
  }
}

/// 90-day TTL: Documents and history
class NinetyDayTtlManager {
  final Ditto ditto;

  NinetyDayTtlManager(this.ditto);

  void subscribeToRecentDocuments() {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    ditto.sync.registerSubscription(
      'SELECT * FROM documents WHERE updatedAt >= :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    ditto.sync.registerSubscription(
      'SELECT * FROM history WHERE timestamp >= :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Subscribed: Documents & history (90-day window)');
  }

  Future<void> evictOldDocuments() async {
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 180))
        .toIso8601String();

    await ditto.store.execute(
      'EVICT FROM documents WHERE updatedAt < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    await ditto.store.execute(
      'EVICT FROM history WHERE timestamp < :cutoff',
      arguments: {'cutoff': cutoffDate},
    );

    print('✅ Evicted: Documents & history older than 180 days');
  }
}

// ============================================================================
// PATTERN 4: Storage Quota Enforcement
// ============================================================================

/// Enforce storage limits with TTL-based cleanup
class StorageQuotaManager {
  final Ditto ditto;
  final int maxStorageMB;

  StorageQuotaManager(this.ditto, this.maxStorageMB);

  /// Check storage and enforce quota
  Future<void> enforceStorageQuota() async {
    print('📊 Checking storage quota...');

    // Estimate current storage usage
    final usage = await _estimateStorageUsage();

    print('  Current usage: ~${usage.toStringAsFixed(1)} MB');
    print('  Max allowed: $maxStorageMB MB');

    if (usage > maxStorageMB) {
      print('  ⚠️ Storage quota exceeded, running cleanup...');
      await _performAggressiveCleanup();
    } else if (usage > maxStorageMB * 0.8) {
      print('  ⚠️ Storage 80% full, running preventive cleanup...');
      await _performStandardCleanup();
    } else {
      print('  ✅ Storage within quota');
    }
  }

  Future<double> _estimateStorageUsage() async {
    // Rough estimation based on document counts
    var totalSizeMB = 0.0;

    final collections = {
      'messages': 10, // KB per document
      'logs': 5,
      'documents': 50,
      'media': 200,
    };

    for (final entry in collections.entries) {
      final result = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM ${entry.key}',
      );
      final count = result.items.firstOrNull?.value['count'] as int? ?? 0;
      totalSizeMB += (count * entry.value) / 1024;
    }

    return totalSizeMB;
  }

  Future<void> _performStandardCleanup() async {
    // Evict data older than 90 days
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    await ditto.store.execute(
      'EVICT FROM messages WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    print('  ✅ Standard cleanup: Evicted data >90 days');
  }

  Future<void> _performAggressiveCleanup() async {
    // Evict data older than 30 days (more aggressive)
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await ditto.store.execute(
      'EVICT FROM messages WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    print('  ✅ Aggressive cleanup: Evicted data >30 days');
  }
}

// ============================================================================
// PATTERN 5: Oldest-First Eviction Strategy
// ============================================================================

/// Evict oldest documents first when storage is low
class OldestFirstEviction {
  final Ditto ditto;

  OldestFirstEviction(this.ditto);

  /// Evict oldest N documents from collection
  Future<void> evictOldestDocuments(
    String collectionName,
    int count,
  ) async {
    print('📱 Evicting oldest $count documents from $collectionName...');

    // Query oldest documents
    final result = await ditto.store.execute(
      '''
      SELECT _id, createdAt FROM $collectionName
      ORDER BY createdAt ASC
      LIMIT :limit
      ''',
      arguments: {'limit': count},
    );

    if (result.items.isEmpty) {
      print('  No documents to evict');
      return;
    }

    // Get cutoff timestamp from oldest document
    final oldestDoc = result.items.last.value;
    final cutoffDate = oldestDoc['createdAt'] as String;

    // EVICT documents older than or equal to cutoff
    await ditto.store.execute(
      '''
      EVICT FROM $collectionName
      WHERE createdAt <= :cutoff
      ''',
      arguments: {'cutoff': cutoffDate},
    );

    print('  ✅ Evicted ~$count oldest documents');
    print('     Cutoff: $cutoffDate');
  }

  /// Progressive cleanup when storage is low
  Future<void> progressiveCleanup() async {
    print('📱 Running progressive cleanup...');

    // Step 1: Evict 100 oldest logs
    await evictOldestDocuments('logs', 100);

    // Step 2: Check if still need more space
    // (Simplified - in production, check actual storage)

    // Step 3: Evict 50 oldest messages
    await evictOldestDocuments('messages', 50);

    print('✅ Progressive cleanup complete');
  }
}

// ============================================================================
// PATTERN 6: Differential TTL by Collection
// ============================================================================

/// Different TTL for different collections
class DifferentialTtlManager {
  final Ditto ditto;
  final Map<String, DittoSyncSubscription> _subscriptions = {};

  DifferentialTtlManager(this.ditto);

  /// Initialize subscriptions with different time windows
  void initializeSubscriptions() {
    // Logs: 7-day window
    _subscriptions['logs'] = ditto.sync.registerSubscription(
      'SELECT * FROM logs WHERE timestamp >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 7))
            .toIso8601String(),
      },
    );

    // Messages: 30-day window
    _subscriptions['messages'] = ditto.sync.registerSubscription(
      'SELECT * FROM messages WHERE createdAt >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      },
    );

    // Documents: 90-day window
    _subscriptions['documents'] = ditto.sync.registerSubscription(
      'SELECT * FROM documents WHERE updatedAt >= :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 90))
            .toIso8601String(),
      },
    );

    print('✅ Subscriptions created with differential TTL:');
    print('   Logs: 7 days');
    print('   Messages: 30 days');
    print('   Documents: 90 days');
  }

  /// Run cleanup with differential TTL
  Future<void> runDifferentialCleanup() async {
    print('📱 Running differential TTL cleanup...');

    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();

    await Future.delayed(const Duration(milliseconds: 500));

    // Evict logs older than 14 days (2x subscription window)
    await ditto.store.execute(
      'EVICT FROM logs WHERE timestamp < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 14))
            .toIso8601String(),
      },
    );
    print('  ✅ Logs: Evicted data >14 days');

    // Evict messages older than 60 days (2x subscription window)
    await ditto.store.execute(
      'EVICT FROM messages WHERE createdAt < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 60))
            .toIso8601String(),
      },
    );
    print('  ✅ Messages: Evicted data >60 days');

    // Evict documents older than 180 days (2x subscription window)
    await ditto.store.execute(
      'EVICT FROM documents WHERE updatedAt < :cutoff',
      arguments: {
        'cutoff': DateTime.now()
            .subtract(const Duration(days: 180))
            .toIso8601String(),
      },
    );
    print('  ✅ Documents: Evicted data >180 days');

    // Recreate subscriptions
    initializeSubscriptions();

    print('✅ Differential cleanup complete');
  }

  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
  }
}

// ============================================================================
// PATTERN 7: Complete Production Example
// ============================================================================

/// Production-ready TTL management for Small Peer
class ProductionTtlManager {
  final Ditto ditto;
  final Map<String, DittoSyncSubscription> _subscriptions = {};
  DateTime? _lastCleanupTime;

  // Configurable TTL policies (days)
  static const _ttlPolicies = {
    'logs': 7,
    'messages': 30,
    'notifications': 30,
    'documents': 90,
    'events': 90,
  };

  // Eviction multiplier (evict data older than TTL * multiplier)
  static const _evictionMultiplier = 2;

  ProductionTtlManager(this.ditto);

  /// Initialize all subscriptions
  void initialize() {
    print('📱 Initializing TTL manager...');

    for (final entry in _ttlPolicies.entries) {
      _createSubscription(entry.key, entry.value);
    }

    // Schedule periodic cleanup
    _schedulePeriodicCleanup();

    print('✅ TTL manager initialized');
  }

  void _createSubscription(String collection, int retentionDays) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();

    _subscriptions[collection] = ditto.sync.registerSubscription(
      'SELECT * FROM $collection WHERE createdAt >= :cutoff',
      arguments: {'cutoff': cutoff},
    );

    print('  ✅ $collection: ${retentionDays}-day window');
  }

  void _schedulePeriodicCleanup() {
    // Run cleanup check every 24 hours
    Future.delayed(const Duration(hours: 24), () async {
      await _checkAndRunCleanup();
      _schedulePeriodicCleanup();
    });
  }

  Future<void> _checkAndRunCleanup() async {
    // Only run once per day
    if (_lastCleanupTime != null &&
        DateTime.now().difference(_lastCleanupTime!) < const Duration(hours: 24)) {
      print('⏱️ Cleanup not needed yet');
      return;
    }

    await performCleanup();
  }

  /// Perform full cleanup cycle
  Future<void> performCleanup() async {
    print('📱 Starting TTL-based cleanup...');

    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();

    await Future.delayed(const Duration(milliseconds: 500));

    // Evict old data from each collection
    for (final entry in _ttlPolicies.entries) {
      await _evictCollection(
        entry.key,
        entry.value * _evictionMultiplier,
      );
    }

    // Recreate all subscriptions
    for (final entry in _ttlPolicies.entries) {
      _createSubscription(entry.key, entry.value);
    }

    _lastCleanupTime = DateTime.now();

    print('✅ TTL-based cleanup complete');
  }

  Future<void> _evictCollection(String collection, int evictionDays) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: evictionDays))
        .toIso8601String();

    final beforeResult = await ditto.store.execute(
      'SELECT COUNT(*) as count FROM $collection',
    );
    final before = beforeResult.items.first.value['count'] as int;

    await ditto.store.execute(
      'EVICT FROM $collection WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    final afterResult = await ditto.store.execute(
      'SELECT COUNT(*) as count FROM $collection',
    );
    final after = afterResult.items.first.value['count'] as int;

    final evicted = before - after;
    print('  ✅ $collection: Evicted $evicted docs (>$evictionDays days)');
  }

  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
  }
}
