// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Flag-Based Eviction Pattern
// ============================================================================
//
// This example demonstrates using eviction flags to control when and what
// data should be evicted, combining manual control with automated cleanup.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ evictionFlag field pattern
// 2. ✅ Opposite subscription query (NOT flagged)
// 3. ✅ Query separation importance
// 4. ✅ Manual flag setting + automated eviction
// 5. ✅ Centralized eviction control
// 6. ✅ Flag verification before eviction
// 7. ✅ Multi-criteria flagging logic
//
// WHY USE FLAGS:
// - Fine-grained control over what gets evicted
// - Manual + automated hybrid approach
// - Easy to query flagged documents
// - Audit trail of eviction decisions
// - Testable eviction logic
//
// FLAG FIELD PATTERN:
// - Add shouldEvict boolean field to documents
// - Subscribe to documents WHERE shouldEvict != true
// - Mark documents with shouldEvict = true when ready
// - EVICT documents WHERE shouldEvict = true
//
// ⚠️ CRITICAL DISTINCTION: Soft-Delete vs EVICT Filtering
//
// **Soft-Delete (logical deletion)**:
//   - Subscription: NO deletion flag filter (for multi-hop relay)
//   - Observer: YES deletion flag filter (for UI display)
//   - Pattern: `SELECT * FROM orders` (subscription)
//            + `SELECT * FROM orders WHERE isDeleted != true` (observer)
//
// **EVICT (local cleanup)**:
//   - Subscription: YES eviction flag filter (avoid resync loops)
//   - Pattern: `SELECT * FROM orders WHERE shouldEvict != true` (subscription)
//            + `EVICT FROM orders WHERE shouldEvict = true` (eviction)
//   - This is different because EVICT is meant to remove local data permanently
//
// This example demonstrates EVICT pattern, not soft-delete pattern.
// For soft-delete, see logical-deletion-relay.dart example.
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Basic Flag-Based Eviction
// ============================================================================

/// Basic eviction flag pattern
class BasicFlagEviction {
  final Ditto ditto;
  DittoSyncSubscription? _dataSubscription;

  BasicFlagEviction(this.ditto);

  /// Subscribe to active data (not flagged for eviction)
  void subscribeToActiveData() {
    // ✅ GOOD: Subscribe only to data NOT flagged for eviction
    _dataSubscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM documents
      WHERE shouldEvict != true
      ''',
    );

    print('✅ Subscribed: Documents NOT flagged for eviction');
    print('   Query: shouldEvict != true');
  }

  /// Mark document for eviction
  Future<void> markForEviction(String documentId, String reason) async {
    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = true,
          evictionReason = :reason,
          evictionMarkedAt = :timestamp
      WHERE _id = :documentId
      ''',
      arguments: {
        'documentId': documentId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Marked document for eviction:');
    print('   ID: $documentId');
    print('   Reason: $reason');
  }

  /// Evict all flagged documents
  Future<void> evictFlaggedDocuments() async {
    print('📱 Evicting flagged documents...');

    // Step 1: Cancel subscription
    _dataSubscription?.cancel();
    _dataSubscription = null;
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Count documents to evict
    final countResult = await ditto.store.execute(
      'SELECT COUNT(*) as count FROM documents WHERE shouldEvict = true',
    );
    final count = countResult.items.first.value['count'] as int;

    print('  Found $count documents flagged for eviction');

    // Step 3: EVICT flagged documents
    await ditto.store.execute(
      'EVICT FROM documents WHERE shouldEvict = true',
    );

    print('  ✅ Evicted $count documents');

    // Step 4: Recreate subscription
    subscribeToActiveData();
  }

  void dispose() {
    _dataSubscription?.cancel();
  }
}

// ============================================================================
// PATTERN 2: Multi-Criteria Flagging Logic
// ============================================================================

/// Automatically flag documents based on multiple criteria
class AutoFlagManager {
  final Ditto ditto;

  AutoFlagManager(this.ditto);

  /// Run automated flagging based on business rules
  Future<void> runAutomatedFlagging() async {
    print('🤖 Running automated flagging...');

    // Criterion 1: Old documents (>90 days)
    await _flagOldDocuments();

    // Criterion 2: Deleted documents (>30 days since deletion)
    await _flagDeletedDocuments();

    // Criterion 3: Completed tasks (>60 days)
    await _flagCompletedTasks();

    // Criterion 4: Large documents with low access count
    await _flagUnusedLargeDocuments();

    print('✅ Automated flagging complete');
  }

  Future<void> _flagOldDocuments() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = true,
          evictionReason = 'old_age',
          evictionMarkedAt = :timestamp
      WHERE createdAt < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': cutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Flagged old documents (>90 days)');
  }

  Future<void> _flagDeletedDocuments() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = true,
          evictionReason = 'deleted',
          evictionMarkedAt = :timestamp
      WHERE isDeleted = true AND deletedAt < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': cutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Flagged deleted documents (>30 days since deletion)');
  }

  Future<void> _flagCompletedTasks() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 60))
        .toIso8601String();

    await ditto.store.execute(
      '''
      UPDATE tasks
      SET shouldEvict = true,
          evictionReason = 'completed',
          evictionMarkedAt = :timestamp
      WHERE status = 'completed' AND completedAt < :cutoff AND shouldEvict != true
      ''',
      arguments: {
        'cutoff': cutoff,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Flagged completed tasks (>60 days)');
  }

  Future<void> _flagUnusedLargeDocuments() async {
    // Flag documents that are large and rarely accessed
    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = true,
          evictionReason = 'large_unused',
          evictionMarkedAt = :timestamp
      WHERE sizeBytes > 1000000 AND accessCount < 5 AND shouldEvict != true
      ''',
      arguments: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Flagged large unused documents (>1MB, <5 accesses)');
  }
}

// ============================================================================
// PATTERN 3: Query Separation Importance
// ============================================================================

/// Demonstrates importance of opposite queries
class OppositeQueryPattern {
  final Ditto ditto;

  OppositeQueryPattern(this.ditto);

  /// ✅ GOOD: Subscription and eviction use opposite queries
  void demonstrateCorrectPattern() async {
    print('✅ CORRECT: Opposite queries for subscription and eviction');

    // Subscription: Get documents NOT flagged
    final subscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM data
      WHERE shouldEvict != true
      ''',
    );
    print('  Subscription query: shouldEvict != true');

    // Eviction: Remove documents that ARE flagged
    await Future.delayed(const Duration(seconds: 1));
    subscription.cancel();

    await ditto.store.execute(
      '''
      EVICT FROM data
      WHERE shouldEvict = true
      ''',
    );
    print('  Eviction query: shouldEvict = true');

    print('  ✅ Queries are opposite - no resync loop');
  }

  /// ❌ BAD: Subscription and eviction use same query
  void demonstrateIncorrectPattern() async {
    print('❌ INCORRECT: Same queries for subscription and eviction');

    // ❌ BAD: Subscribe to flagged documents
    final subscription = ditto.sync.registerSubscription(
      '''
      SELECT * FROM data
      WHERE shouldEvict = true
      ''',
    );
    print('  Subscription query: shouldEvict = true');

    // Evict flagged documents
    await Future.delayed(const Duration(seconds: 1));
    subscription.cancel();

    await ditto.store.execute(
      '''
      EVICT FROM data
      WHERE shouldEvict = true
      ''',
    );
    print('  Eviction query: shouldEvict = true');

    // Recreate subscription
    ditto.sync.registerSubscription(
      '''
      SELECT * FROM data
      WHERE shouldEvict = true
      ''',
    );

    print('  ❌ RESYNC LOOP: Subscription re-downloads evicted data!');
  }
}

// ============================================================================
// PATTERN 4: Flag Verification Before Eviction
// ============================================================================

/// Verify flags before eviction and provide detailed reporting
class VerifiedFlagEviction {
  final Ditto ditto;

  VerifiedFlagEviction(this.ditto);

  /// Evict with detailed reporting
  Future<void> evictWithVerification() async {
    print('📊 Eviction with verification:');

    // Step 1: Query flagged documents
    final flaggedResult = await ditto.store.execute(
      '''
      SELECT _id, evictionReason, evictionMarkedAt
      FROM documents
      WHERE shouldEvict = true
      ''',
    );

    if (flaggedResult.items.isEmpty) {
      print('  No documents flagged for eviction');
      return;
    }

    // Step 2: Group by reason
    final byReason = <String, int>{};
    for (final item in flaggedResult.items) {
      final reason = item.value['evictionReason'] as String? ?? 'unknown';
      byReason[reason] = (byReason[reason] ?? 0) + 1;
    }

    print('  Documents flagged for eviction:');
    for (final entry in byReason.entries) {
      print('    ${entry.key}: ${entry.value} documents');
    }

    // Step 3: Confirm and evict
    // (In production, might ask user for confirmation here)

    await ditto.store.execute(
      'EVICT FROM documents WHERE shouldEvict = true',
    );

    print('  ✅ Evicted ${flaggedResult.items.length} documents');
  }

  /// Get eviction preview
  Future<Map<String, dynamic>> getEvictionPreview() async {
    final result = await ditto.store.execute(
      '''
      SELECT evictionReason, COUNT(*) as count
      FROM documents
      WHERE shouldEvict = true
      GROUP BY evictionReason
      ''',
    );

    // Note: Ditto doesn't support GROUP BY, so we do it in code
    final flaggedResult = await ditto.store.execute(
      'SELECT evictionReason FROM documents WHERE shouldEvict = true',
    );

    final byReason = <String, int>{};
    for (final item in flaggedResult.items) {
      final reason = item.value['evictionReason'] as String? ?? 'unknown';
      byReason[reason] = (byReason[reason] ?? 0) + 1;
    }

    return {
      'totalFlagged': flaggedResult.items.length,
      'byReason': byReason,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

// ============================================================================
// PATTERN 5: Centralized Eviction Control
// ============================================================================

/// Central manager for all flag-based eviction operations
class CentralizedEvictionController {
  final Ditto ditto;
  final Map<String, DittoSyncSubscription> _subscriptions = {};

  CentralizedEvictionController(this.ditto);

  /// Initialize subscriptions for all collections
  void initialize() {
    print('🎛️ Initializing centralized eviction controller...');

    // Subscribe to active data across all collections
    _subscriptions['documents'] = ditto.sync.registerSubscription(
      'SELECT * FROM documents WHERE shouldEvict != true',
    );

    _subscriptions['messages'] = ditto.sync.registerSubscription(
      'SELECT * FROM messages WHERE shouldEvict != true',
    );

    _subscriptions['tasks'] = ditto.sync.registerSubscription(
      'SELECT * FROM tasks WHERE shouldEvict != true',
    );

    print('✅ Controller initialized with 3 collection subscriptions');
  }

  /// Mark documents across all collections
  Future<void> markAllForEviction() async {
    print('🎛️ Running centralized eviction flagging...');

    final manager = AutoFlagManager(ditto);
    await manager.runAutomatedFlagging();

    print('✅ Centralized flagging complete');
  }

  /// Evict from all collections
  Future<void> evictAllCollections() async {
    print('🎛️ Evicting from all collections...');

    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();

    await Future.delayed(const Duration(milliseconds: 500));

    // Evict from each collection
    final collections = ['documents', 'messages', 'tasks'];
    var totalEvicted = 0;

    for (final collection in collections) {
      final countResult = await ditto.store.execute(
        'SELECT COUNT(*) as count FROM $collection WHERE shouldEvict = true',
      );
      final count = countResult.items.first.value['count'] as int;

      if (count > 0) {
        await ditto.store.execute(
          'EVICT FROM $collection WHERE shouldEvict = true',
        );
        print('  ✅ $collection: Evicted $count documents');
        totalEvicted += count;
      } else {
        print('  ℹ️ $collection: No documents to evict');
      }
    }

    // Recreate subscriptions
    initialize();

    print('✅ Total evicted: $totalEvicted documents');
  }

  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
  }
}

// ============================================================================
// PATTERN 6: User-Initiated Flag Management
// ============================================================================

/// Allow users to manually control eviction flags
class UserEvictionController {
  final Ditto ditto;

  UserEvictionController(this.ditto);

  /// User marks document as "can delete"
  Future<void> userMarkForEviction(String documentId) async {
    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = true,
          evictionReason = 'user_initiated',
          evictionMarkedAt = :timestamp
      WHERE _id = :documentId
      ''',
      arguments: {
        'documentId': documentId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('✅ User marked document for eviction: $documentId');
  }

  /// User unmarks document (keep it)
  Future<void> userUnmarkEviction(String documentId) async {
    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = false,
          evictionReason = null,
          evictionMarkedAt = null
      WHERE _id = :documentId
      ''',
      arguments: {'documentId': documentId},
    );

    print('✅ User unmarked document: $documentId');
  }

  /// Get user's flagged documents
  Future<List<Map<String, dynamic>>> getUserFlaggedDocuments(String userId) async {
    final result = await ditto.store.execute(
      '''
      SELECT * FROM documents
      WHERE userId = :userId AND shouldEvict = true
      ''',
      arguments: {'userId': userId},
    );

    return result.items.map((item) => item.value).toList();
  }

  /// Clear all user flags (user cancels cleanup)
  Future<void> clearAllUserFlags(String userId) async {
    await ditto.store.execute(
      '''
      UPDATE documents
      SET shouldEvict = false, evictionReason = null, evictionMarkedAt = null
      WHERE userId = :userId AND evictionReason = 'user_initiated'
      ''',
      arguments: {'userId': userId},
    );

    print('✅ Cleared all user eviction flags for user: $userId');
  }
}

// ============================================================================
// PATTERN 7: Production-Ready Flag-Based System
// ============================================================================

/// Complete production implementation
class ProductionFlagEvictionSystem {
  final Ditto ditto;
  final CentralizedEvictionController controller;
  final AutoFlagManager autoFlagManager;
  DateTime? _lastAutoFlagTime;
  DateTime? _lastEvictionTime;

  ProductionFlagEvictionSystem(this.ditto)
      : controller = CentralizedEvictionController(ditto),
        autoFlagManager = AutoFlagManager(ditto);

  /// Initialize system
  void initialize() {
    print('🚀 Initializing production eviction system...');

    // Set up subscriptions
    controller.initialize();

    // Schedule automated processes
    _scheduleAutomatedFlagging();
    _scheduleAutomatedEviction();

    print('✅ Production system initialized');
  }

  void _scheduleAutomatedFlagging() {
    // Run auto-flagging daily
    Future.delayed(const Duration(hours: 24), () async {
      await _runAutomatedFlagging();
      _scheduleAutomatedFlagging();
    });
  }

  void _scheduleAutomatedEviction() {
    // Run eviction daily (after flagging)
    Future.delayed(const Duration(hours: 24, minutes: 30), () async {
      await _runAutomatedEviction();
      _scheduleAutomatedEviction();
    });
  }

  Future<void> _runAutomatedFlagging() async {
    if (_lastAutoFlagTime != null &&
        DateTime.now().difference(_lastAutoFlagTime!) < const Duration(hours: 24)) {
      return;
    }

    print('🤖 Running automated flagging...');
    await autoFlagManager.runAutomatedFlagging();
    _lastAutoFlagTime = DateTime.now();
    print('✅ Automated flagging complete');
  }

  Future<void> _runAutomatedEviction() async {
    if (_lastEvictionTime != null &&
        DateTime.now().difference(_lastEvictionTime!) < const Duration(hours: 24)) {
      return;
    }

    print('🧹 Running automated eviction...');
    await controller.evictAllCollections();
    _lastEvictionTime = DateTime.now();
    print('✅ Automated eviction complete');
  }

  /// Manual cleanup trigger (from settings screen)
  Future<void> manualCleanup() async {
    print('👤 User triggered manual cleanup...');

    // Run flagging
    await autoFlagManager.runAutomatedFlagging();

    // Show preview
    final verifier = VerifiedFlagEviction(ditto);
    final preview = await verifier.getEvictionPreview();

    print('📊 Eviction preview:');
    print('   Total to evict: ${preview['totalFlagged']}');
    print('   By reason: ${preview['byReason']}');

    // (In production, show preview to user and ask for confirmation)

    // Perform eviction
    await controller.evictAllCollections();

    print('✅ Manual cleanup complete');
  }

  void dispose() {
    controller.dispose();
  }
}
