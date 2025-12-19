// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// TTL-Based Eviction: Big Peer Pattern
// ============================================================================
//
// This example demonstrates using Big Peer (cloud server) to control
// eviction of data across Small Peers (mobile/edge devices).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Big Peer sets eviction flags via HTTP API
// 2. ✅ Centralized eviction control
// 3. ✅ Small Peers query and evict based on flags
// 4. ✅ Time-to-live (TTL) management from server
// 5. ✅ Scheduled cleanup jobs on Big Peer
// 6. ✅ Flag-based eviction pattern
// 7. ✅ Industry-specific TTL policies
//
// BIG PEER vs SMALL PEER:
// - Big Peer: Cloud server with HTTP API, unlimited storage
// - Small Peer: Mobile/edge device with limited storage
//
// WHY USE BIG PEER FOR EVICTION CONTROL:
// - Centralized policy management
// - Consistent TTL across all devices
// - Server controls what devices should evict
// - Devices don't need to calculate TTL independently
// - Policy changes propagate automatically
//
// PATTERN OVERVIEW:
// 1. Big Peer marks documents with shouldEvict flag
// 2. Flag syncs to Small Peers
// 3. Small Peers query for shouldEvict = true
// 4. Small Peers EVICT locally (Big Peer keeps data)
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:convert';

// ============================================================================
// PATTERN 1: Big Peer Sets Eviction Flags
// ============================================================================

/// Big Peer: Server-side eviction flag management
class BigPeerEvictionManager {
  final Ditto ditto;

  BigPeerEvictionManager(this.ditto);

  /// Scheduled job: Mark old documents for eviction (runs daily on server)
  Future<void> markDocumentsForEviction() async {
    print('🌐 [Big Peer] Running eviction flag job...');

    // Calculate cutoff dates for different collections
    final messageCutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    final logCutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();

    final eventCutoff = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    // Mark old messages for eviction
    await ditto.store.execute(
      '''
      UPDATE messages
      SET shouldEvict = true, evictMarkedAt = :timestamp
      WHERE createdAt < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': messageCutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    print('  ✅ Marked old messages (>30 days) for eviction');

    // Mark old logs for eviction
    await ditto.store.execute(
      '''
      UPDATE logs
      SET shouldEvict = true, evictMarkedAt = :timestamp
      WHERE timestamp < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': logCutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    print('  ✅ Marked old logs (>7 days) for eviction');

    // Mark old events for eviction
    await ditto.store.execute(
      '''
      UPDATE events
      SET shouldEvict = true, evictMarkedAt = :timestamp
      WHERE timestamp < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': eventCutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    print('  ✅ Marked old events (>90 days) for eviction');

    print('🌐 [Big Peer] Eviction flags set (will sync to Small Peers)');
  }

  /// HTTP API endpoint: Manually mark specific document for eviction
  Future<void> markDocumentForEvictionApi(
    String collectionName,
    String documentId,
  ) async {
    await ditto.store.execute(
      '''
      UPDATE $collectionName
      SET shouldEvict = true, evictMarkedAt = :timestamp
      WHERE _id = :documentId
      ''',
      arguments: {
        'documentId': documentId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('🌐 [Big Peer] Marked $collectionName/$documentId for eviction');
  }

  /// HTTP API endpoint: Set custom TTL policy
  Future<void> setTtlPolicy(
    String collectionName,
    int retentionDays,
  ) async {
    // Store policy in dedicated collection
    await ditto.store.execute(
      '''
      INSERT INTO ttlPolicies (_id, collectionName, retentionDays, updatedAt)
      VALUES (:id, :collectionName, :retentionDays, :updatedAt)
      ON CONFLICT DO UPDATE SET
        retentionDays = :retentionDays,
        updatedAt = :updatedAt
      ''',
      arguments: {
        'id': 'policy_$collectionName',
        'collectionName': collectionName,
        'retentionDays': retentionDays,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('🌐 [Big Peer] Set TTL policy: $collectionName = $retentionDays days');

    // Apply policy immediately
    await _applyTtlPolicy(collectionName, retentionDays);
  }

  Future<void> _applyTtlPolicy(String collectionName, int retentionDays) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();

    await ditto.store.execute(
      '''
      UPDATE $collectionName
      SET shouldEvict = true, evictMarkedAt = :timestamp
      WHERE createdAt < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': cutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Applied TTL policy to $collectionName');
  }
}

// ============================================================================
// PATTERN 2: Small Peer Queries and Evicts Flagged Documents
// ============================================================================

/// Small Peer: Device-side eviction based on Big Peer flags
class SmallPeerEvictionManager {
  final Ditto ditto;
  DateTime? _lastEvictionTime;

  SmallPeerEvictionManager(this.ditto);

  /// Subscribe to active data (NOT marked for eviction)
  DittoSyncSubscription createActiveDataSubscription() {
    // ✅ GOOD: Subscribe only to data NOT marked for eviction
    final subscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM messages
      WHERE shouldEvict != true
      ''',
    );

    print('📱 [Small Peer] Subscribed: Messages NOT marked for eviction');
    return subscription;
  }

  /// Periodic cleanup: Evict flagged documents (runs daily)
  Future<void> evictFlaggedDocuments() async {
    // Check if eviction needed (max once per day)
    if (_lastEvictionTime != null &&
        DateTime.now().difference(_lastEvictionTime!) < const Duration(hours: 24)) {
      print('📱 [Small Peer] Eviction not needed (last run: $_lastEvictionTime)');
      return;
    }

    print('📱 [Small Peer] Starting eviction of flagged documents...');

    // Cancel subscriptions (if needed)
    // Assuming subscription management handled separately

    await Future.delayed(const Duration(milliseconds: 500));

    // Evict documents marked by Big Peer
    await _evictCollection('messages');
    await _evictCollection('logs');
    await _evictCollection('events');

    _lastEvictionTime = DateTime.now();

    // Recreate subscriptions
    // Assuming subscription management handled separately

    print('📱 [Small Peer] Eviction complete');
  }

  Future<void> _evictCollection(String collectionName) async {
    // Count documents to evict
    final countResult = await ditto.store.execute(
      'SELECT COUNT(*) as count FROM $collectionName WHERE shouldEvict = true',
    );
    final count = countResult.items.first.value['count'] as int;

    if (count == 0) {
      print('  📱 $collectionName: No documents to evict');
      return;
    }

    // EVICT flagged documents
    await ditto.store.execute(
      'EVICT FROM $collectionName WHERE shouldEvict = true',
    );

    print('  ✅ $collectionName: Evicted $count documents');
  }

  /// Check storage usage and trigger eviction if needed
  Future<void> checkStorageAndEvict({
    required int maxStorageMB,
  }) async {
    // Get current storage usage (approximate)
    final collectionsResult = await ditto.store.execute(
      'SELECT COUNT(*) as messageCount FROM messages',
    );
    final messageCount = collectionsResult.items.first.value['messageCount'] as int;

    // Rough estimate: 10 KB per message
    final estimatedStorageMB = (messageCount * 10) ~/ 1024;

    print('📱 [Small Peer] Storage check:');
    print('   Estimated usage: $estimatedStorageMB MB');
    print('   Max allowed: $maxStorageMB MB');

    if (estimatedStorageMB > maxStorageMB) {
      print('   ⚠️ Storage limit exceeded, triggering eviction...');
      await evictFlaggedDocuments();
    } else {
      print('   ✅ Storage within limits');
    }
  }
}

// ============================================================================
// PATTERN 3: Complete Big Peer + Small Peer Workflow
// ============================================================================

/// Example: Complete workflow for Big Peer server
class BigPeerServer {
  final Ditto ditto;

  BigPeerServer(this.ditto);

  /// Server startup: Schedule periodic eviction flag jobs
  void startEvictionScheduler() {
    print('🌐 [Big Peer] Starting eviction scheduler...');

    // Run eviction flag job daily at 2 AM
    _scheduleDaily(() async {
      print('🌐 [Big Peer] Running scheduled eviction flag job...');
      final manager = BigPeerEvictionManager(ditto);
      await manager.markDocumentsForEviction();
    });

    print('🌐 [Big Peer] Eviction scheduler started');
  }

  void _scheduleDaily(Future<void> Function() job) {
    // Simplified scheduling (in production, use cron or scheduled task)
    Future.delayed(const Duration(hours: 24), () async {
      await job();
      _scheduleDaily(job); // Reschedule
    });
  }

  /// HTTP API: Manual eviction trigger
  Future<Map<String, dynamic>> handleEvictionRequest(
    String collectionName,
    String documentId,
  ) async {
    try {
      final manager = BigPeerEvictionManager(ditto);
      await manager.markDocumentForEvictionApi(collectionName, documentId);

      return {
        'success': true,
        'message': 'Document marked for eviction',
        'collection': collectionName,
        'documentId': documentId,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// HTTP API: Get eviction statistics
  Future<Map<String, dynamic>> getEvictionStats() async {
    final stats = <String, dynamic>{};

    for (final collection in ['messages', 'logs', 'events']) {
      final totalResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM $collection',
      );
      final markedResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM $collection WHERE shouldEvict = true',
      );

      final total = totalResult.items.first.value['count'] as int;
      final marked = markedResult.items.first.value['count'] as int;

      stats[collection] = {
        'total': total,
        'markedForEviction': marked,
        'percentageMarked': total > 0 ? (marked / total * 100).toStringAsFixed(1) : '0',
      };
    }

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'collections': stats,
    };
  }
}

/// Example: Complete workflow for Small Peer device
class SmallPeerDevice {
  final Ditto ditto;
  final SmallPeerEvictionManager _evictionManager;
  final Map<String, DittoSyncSubscription> _subscriptions = {};

  SmallPeerDevice(this.ditto) : _evictionManager = SmallPeerEvictionManager(ditto);

  /// Device startup: Initialize subscriptions and eviction scheduler
  void initialize() {
    print('📱 [Small Peer] Initializing device...');

    // Create subscriptions (exclude documents marked for eviction)
    _subscriptions['messages'] = _evictionManager.createActiveDataSubscription();

    // Schedule periodic eviction check (daily)
    _scheduleEvictionCheck();

    print('📱 [Small Peer] Device initialized');
  }

  void _scheduleEvictionCheck() {
    Future.delayed(const Duration(hours: 24), () async {
      await _runEvictionIfNeeded();
      _scheduleEvictionCheck(); // Reschedule
    });
  }

  Future<void> _runEvictionIfNeeded() async {
    print('📱 [Small Peer] Checking if eviction needed...');

    // Cancel subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();

    await Future.delayed(const Duration(milliseconds: 500));

    // Run eviction
    await _evictionManager.evictFlaggedDocuments();

    // Recreate subscriptions
    _subscriptions['messages'] = _evictionManager.createActiveDataSubscription();
  }

  /// Manual cleanup trigger (e.g., from settings screen)
  Future<void> triggerManualCleanup() async {
    print('📱 [Small Peer] Manual cleanup triggered...');
    await _runEvictionIfNeeded();
  }

  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
  }
}

// ============================================================================
// PATTERN 4: Industry-Specific TTL Policies
// ============================================================================

/// Healthcare: HIPAA-compliant data retention
class HealthcareTtlPolicy {
  final BigPeerEvictionManager manager;

  HealthcareTtlPolicy(this.manager);

  Future<void> applyHealthcarePolicies() async {
    print('🏥 Applying healthcare TTL policies (HIPAA compliant):');

    // Patient records: Keep 7 years
    await manager.setTtlPolicy('patientRecords', 7 * 365);

    // Audit logs: Keep 6 years
    await manager.setTtlPolicy('auditLogs', 6 * 365);

    // Session data: Keep 90 days
    await manager.setTtlPolicy('sessionData', 90);

    // Temporary files: Keep 30 days
    await manager.setTtlPolicy('tempFiles', 30);

    print('🏥 Healthcare policies applied');
  }
}

/// Financial: SOX/PCI-compliant data retention
class FinancialTtlPolicy {
  final BigPeerEvictionManager manager;

  FinancialTtlPolicy(this.manager);

  Future<void> applyFinancialPolicies() async {
    print('💰 Applying financial TTL policies (SOX/PCI compliant):');

    // Transactions: Keep 7 years
    await manager.setTtlPolicy('transactions', 7 * 365);

    // Account statements: Keep 7 years
    await manager.setTtlPolicy('statements', 7 * 365);

    // Session logs: Keep 1 year
    await manager.setTtlPolicy('sessionLogs', 365);

    // Chat logs: Keep 3 years
    await manager.setTtlPolicy('chatLogs', 3 * 365);

    print('💰 Financial policies applied');
  }
}

/// Retail: GDPR-compliant data retention
class RetailTtlPolicy {
  final BigPeerEvictionManager manager;

  RetailTtlPolicy(this.manager);

  Future<void> applyRetailPolicies() async {
    print('🛍️ Applying retail TTL policies (GDPR compliant):');

    // Orders: Keep 3 years
    await manager.setTtlPolicy('orders', 3 * 365);

    // Customer profiles: Keep while active + 2 years
    await manager.setTtlPolicy('customerProfiles', 2 * 365);

    // Analytics events: Keep 1 year
    await manager.setTtlPolicy('analyticsEvents', 365);

    // Session data: Keep 30 days
    await manager.setTtlPolicy('sessionData', 30);

    print('🛍️ Retail policies applied');
  }
}

// ============================================================================
// PATTERN 5: Monitoring and Alerting
// ============================================================================

/// Monitor eviction flag propagation
class EvictionMonitor {
  final Ditto ditto;

  EvictionMonitor(this.ditto);

  /// Big Peer: Check how many documents are marked for eviction
  Future<void> monitorBigPeer() async {
    print('🌐 [Big Peer] Eviction monitoring:');

    for (final collection in ['messages', 'logs', 'events']) {
      final result = await ditto.store.execute(
        '''
        SELECT
          COUNT(*) as total,
          COUNT(CASE WHEN shouldEvict = true THEN 1 END) as marked
        FROM $collection
        ''',
      );

      if (result.items.isNotEmpty) {
        final item = result.items.first.value;
        final total = item['total'] as int;
        final marked = item['marked'] as int;
        final percentage = total > 0 ? (marked / total * 100).toStringAsFixed(1) : '0';

        print('  $collection: $marked/$total ($percentage%) marked for eviction');
      }
    }
  }

  /// Small Peer: Check local storage and eviction status
  Future<void> monitorSmallPeer() async {
    print('📱 [Small Peer] Eviction monitoring:');

    for (final collection in ['messages', 'logs', 'events']) {
      final totalResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM $collection',
      );
      final markedResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM $collection WHERE shouldEvict = true',
      );

      final total = totalResult.items.first.value['count'] as int;
      final marked = markedResult.items.first.value['count'] as int;

      print('  $collection: $total total, $marked flagged (can be evicted)');

      if (marked > 100) {
        print('    ⚠️ Many documents flagged, consider running cleanup');
      }
    }
  }
}
