// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Event History Pattern (Separate Documents with INSERT)
// ============================================================================
//
// This example demonstrates the recommended pattern for storing event
// histories in Ditto using separate documents and INSERT operations.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Separate document per event (INSERT)
// 2. ✅ Guaranteed event preservation (no merge conflicts)
// 3. ✅ Audit log pattern
// 4. ✅ Querying event history
// 5. ✅ Time-based event queries
// 6. ✅ Event aggregation patterns
// 7. ✅ Event replay for debugging
//
// WHY SEPARATE DOCUMENTS FOR EVENTS:
// - INSERT never conflicts (each event gets unique _id)
// - Events are immutable (no UPDATE conflicts)
// - Guaranteed preservation of all events
// - Scalable (no single document size limit)
// - Efficient queries with indexes
//
// WHEN TO USE THIS PATTERN:
// - Audit logs (who did what when)
// - Activity feeds (user actions)
// - Transaction history (financial events)
// - Analytics events (user behavior tracking)
// - Any append-only event stream
//
// WHEN NOT TO USE:
// - Current state (use regular documents with UPDATE)
// - Small fixed-size lists (could use MAP if bounded)
// - Data that requires in-place updates
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: User Activity Events
// ============================================================================

/// ✅ GOOD: Log each user action as separate document
Future<void> logUserAction(
  Ditto ditto,
  String userId,
  String actionType,
  Map<String, dynamic> details,
) async {
  // Create unique event ID (timestamp + randomness ensures uniqueness)
  final eventId = 'event_${userId}_${DateTime.now().millisecondsSinceEpoch}_${_randomString(6)}';

  // Insert event (never conflicts)
  await ditto.store.execute(
    '''
    INSERT INTO userEvents (
      _id, userId, actionType, details, timestamp
    )
    VALUES (:eventId, :userId, :actionType, :details, :timestamp)
    ''',
    arguments: {
      'eventId': eventId,
      'userId': userId,
      'actionType': actionType,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Event logged: $actionType for user $userId');

  // ✅ BENEFIT: Even if multiple devices log events simultaneously,
  // all events preserved (no merge conflicts)
}

/// Helper to generate random string
String _randomString(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(length, (index) => chars[(index * 7) % chars.length]).join();
}

/// Example: Log various user actions
Future<void> logUserActivities(Ditto ditto, String userId) async {
  // User logs in
  await logUserAction(
    ditto,
    userId,
    'login',
    {'method': 'password', 'ip': '192.168.1.100'},
  );

  // User views post
  await logUserAction(
    ditto,
    userId,
    'view_post',
    {'postId': 'post_123', 'source': 'home_feed'},
  );

  // User likes post
  await logUserAction(
    ditto,
    userId,
    'like_post',
    {'postId': 'post_123'},
  );

  // User comments
  await logUserAction(
    ditto,
    userId,
    'create_comment',
    {'postId': 'post_123', 'commentId': 'comment_456'},
  );

  print('✅ All user activities logged (4 events)');
}

// ============================================================================
// PATTERN 2: Audit Log for Document Changes
// ============================================================================

/// ✅ GOOD: Audit trail for sensitive operations
Future<void> auditDocumentChange(
  Ditto ditto,
  String documentId,
  String collectionName,
  String userId,
  String changeType,
  Map<String, dynamic>? oldValue,
  Map<String, dynamic>? newValue,
) async {
  final auditId = 'audit_${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';

  await ditto.store.execute(
    '''
    INSERT INTO auditLog (
      _id, documentId, collectionName, userId, changeType,
      oldValue, newValue, timestamp
    )
    VALUES (
      :auditId, :documentId, :collectionName, :userId, :changeType,
      :oldValue, :newValue, :timestamp
    )
    ''',
    arguments: {
      'auditId': auditId,
      'documentId': documentId,
      'collectionName': collectionName,
      'userId': userId,
      'changeType': changeType, // 'create', 'update', 'delete'
      'oldValue': oldValue,
      'newValue': newValue,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Audit entry created: $changeType on $collectionName/$documentId by $userId');
}

/// Example: Update document with audit trail
Future<void> updateWithAudit(
  Ditto ditto,
  String orderId,
  String userId,
  String newStatus,
) async {
  // Read old value
  final oldResult = await ditto.store.execute(
    'SELECT status FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  final oldStatus = oldResult.items.isNotEmpty
      ? oldResult.items.first.value['status'] as String
      : null;

  // Update order
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'status': newStatus},
  );

  // Log audit event
  await auditDocumentChange(
    ditto,
    orderId,
    'orders',
    userId,
    'update',
    {'status': oldStatus},
    {'status': newStatus},
  );

  print('✅ Order status updated: $oldStatus → $newStatus (audited)');
}

// ============================================================================
// PATTERN 3: Financial Transaction History
// ============================================================================

/// ✅ GOOD: Immutable transaction records
Future<void> recordTransaction(
  Ditto ditto,
  String accountId,
  String transactionType, // 'debit' or 'credit'
  double amount,
  String description,
) async {
  final transactionId = 'txn_${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';

  // Insert transaction record (immutable)
  await ditto.store.execute(
    '''
    INSERT INTO transactions (
      _id, accountId, transactionType, amount, description, timestamp
    )
    VALUES (:txnId, :accountId, :type, :amount, :description, :timestamp)
    ''',
    arguments: {
      'txnId': transactionId,
      'accountId': accountId,
      'type': transactionType,
      'amount': amount,
      'description': description,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // Update account balance using PN_INCREMENT
  final balanceChange = transactionType == 'credit' ? amount : -amount;
  await ditto.store.execute(
    '''
    UPDATE accounts
    APPLY balance PN_INCREMENT BY :change
    WHERE _id = :accountId
    ''',
    arguments: {
      'accountId': accountId,
      'change': balanceChange,
    },
  );

  print('✅ Transaction recorded: $transactionType \$$amount for $accountId');

  // ✅ BENEFIT: Transaction history is immutable and complete
  // Can reconstruct balance by replaying transactions
}

/// Query transaction history
Future<void> getTransactionHistory(
  Ditto ditto,
  String accountId, {
  int limit = 100,
}) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM transactions
    WHERE accountId = :accountId
    ORDER BY timestamp DESC
    LIMIT :limit
    ''',
    arguments: {
      'accountId': accountId,
      'limit': limit,
    },
  );

  print('✅ Transaction history for $accountId:');
  var balance = 0.0;
  for (final item in result.items.reversed) {
    final txn = item.value;
    final amount = txn['amount'] as double;
    final type = txn['transactionType'] as String;

    balance += type == 'credit' ? amount : -amount;

    print('  ${txn['timestamp']}: $type \$$amount - ${txn['description']} (Balance: \$$balance)');
  }

  // ✅ BENEFIT: Complete audit trail for financial records
}

// ============================================================================
// PATTERN 4: Analytics Events
// ============================================================================

/// ✅ GOOD: Track analytics events for analysis
Future<void> trackAnalyticsEvent(
  Ditto ditto,
  String eventName,
  Map<String, dynamic> properties,
) async {
  final eventId = 'analytics_${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';

  await ditto.store.execute(
    '''
    INSERT INTO analyticsEvents (
      _id, eventName, properties, timestamp, sessionId
    )
    VALUES (:eventId, :eventName, :properties, :timestamp, :sessionId)
    ''',
    arguments: {
      'eventId': eventId,
      'eventName': eventName,
      'properties': properties,
      'timestamp': DateTime.now().toIso8601String(),
      'sessionId': 'session_current', // Get from session manager
    },
  );

  print('✅ Analytics event tracked: $eventName');
}

/// Example: Track user journey through app
Future<void> trackUserJourney(Ditto ditto) async {
  // Screen view
  await trackAnalyticsEvent(ditto, 'screen_view', {
    'screen_name': 'home',
    'source': 'app_launch',
  });

  // Feature interaction
  await trackAnalyticsEvent(ditto, 'button_click', {
    'button_id': 'create_post_btn',
    'screen': 'home',
  });

  // Content creation
  await trackAnalyticsEvent(ditto, 'post_created', {
    'post_id': 'post_789',
    'content_length': 280,
    'has_image': true,
  });

  // Feature usage
  await trackAnalyticsEvent(ditto, 'feature_used', {
    'feature_name': 'image_filter',
    'filter_type': 'vintage',
  });

  print('✅ User journey tracked (4 events)');

  // ✅ BENEFIT: Rich analytics data for product insights
  // Events never lost due to conflicts
}

// ============================================================================
// PATTERN 5: Time-Based Event Queries
// ============================================================================

/// Query events within time range
Future<void> queryEventsByTimeRange(
  Ditto ditto,
  String userId,
  DateTime startTime,
  DateTime endTime,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM userEvents
    WHERE userId = :userId
      AND timestamp >= :startTime
      AND timestamp <= :endTime
    ORDER BY timestamp ASC
    ''',
    arguments: {
      'userId': userId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
    },
  );

  print('✅ Events between ${startTime.toIso8601String()} and ${endTime.toIso8601String()}:');
  for (final item in result.items) {
    final event = item.value;
    print('  ${event['timestamp']}: ${event['actionType']}');
  }

  // ✅ BENEFIT: Efficient time-based queries with indexes
}

/// Get today's events
Future<void> getTodayEvents(Ditto ditto, String userId) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  await queryEventsByTimeRange(ditto, userId, startOfDay, endOfDay);
}

/// Get events in last hour
Future<void> getRecentEvents(Ditto ditto, String userId) async {
  final now = DateTime.now();
  final oneHourAgo = now.subtract(const Duration(hours: 1));

  await queryEventsByTimeRange(ditto, userId, oneHourAgo, now);
}

// ============================================================================
// PATTERN 6: Event Aggregation
// ============================================================================

/// Count events by type
Future<void> aggregateEventsByType(
  Ditto ditto,
  String userId,
  DateTime startTime,
) async {
  // Note: Ditto does not support GROUP BY
  // Must aggregate in application code

  final result = await ditto.store.execute(
    '''
    SELECT * FROM userEvents
    WHERE userId = :userId AND timestamp >= :startTime
    ORDER BY actionType
    ''',
    arguments: {
      'userId': userId,
      'startTime': startTime.toIso8601String(),
    },
  );

  // Aggregate in application code
  final counts = <String, int>{};
  for (final item in result.items) {
    final event = item.value;
    final actionType = event['actionType'] as String;
    counts[actionType] = (counts[actionType] ?? 0) + 1;
  }

  print('✅ Event counts by type:');
  for (final entry in counts.entries) {
    print('  ${entry.key}: ${entry.value}');
  }

  // ✅ BENEFIT: Flexible aggregation with preserved raw events
}

// ============================================================================
// PATTERN 7: Event Replay for Debugging
// ============================================================================

/// Replay events to debug user issue
Future<void> replayUserSession(
  Ditto ditto,
  String sessionId,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM userEvents
    WHERE details.sessionId = :sessionId
    ORDER BY timestamp ASC
    ''',
    arguments: {'sessionId': sessionId},
  );

  print('✅ Replaying session $sessionId (${result.items.length} events):');

  for (final item in result.items) {
    final event = item.value;
    final timestamp = event['timestamp'] as String;
    final actionType = event['actionType'] as String;
    final details = event['details'] as Map<String, dynamic>?;

    print('  [$timestamp] $actionType: ${details ?? {}}');
  }

  // ✅ BENEFIT: Complete event history enables debugging
  // Can reproduce user experience step-by-step
}

// ============================================================================
// PATTERN 8: Event Retention Policy
// ============================================================================

/// Clean up old events (EVICT pattern)
Future<void> cleanupOldEvents(Ditto ditto, int retentionDays) async {
  final cutoffDate = DateTime.now()
      .subtract(Duration(days: retentionDays))
      .toIso8601String();

  // EVICT old events (after canceling subscription)
  await ditto.store.execute(
    '''
    EVICT FROM userEvents
    WHERE timestamp < :cutoffDate
    ''',
    arguments: {'cutoffDate': cutoffDate},
  );

  print('✅ Cleaned up events older than $retentionDays days');

  // Note: Should cancel/recreate subscription before EVICT
  // See storage-lifecycle patterns for details
}

// ============================================================================
// PATTERN 9: Event Schema Evolution
// ============================================================================

/// Handle events with different schema versions
Future<void> logEventWithVersion(
  Ditto ditto,
  String userId,
  String actionType,
  Map<String, dynamic> details,
  int schemaVersion,
) async {
  final eventId = 'event_${userId}_${DateTime.now().millisecondsSinceEpoch}_${_randomString(6)}';

  await ditto.store.execute(
    '''
    INSERT INTO userEvents (
      _id, userId, actionType, details, schemaVersion, timestamp
    )
    VALUES (:eventId, :userId, :actionType, :details, :schemaVersion, :timestamp)
    ''',
    arguments: {
      'eventId': eventId,
      'userId': userId,
      'actionType': actionType,
      'details': details,
      'schemaVersion': schemaVersion,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Event logged with schema version $schemaVersion');

  // ✅ BENEFIT: Schema versioning enables backward-compatible evolution
}

/// Query events with schema transformation
Future<void> queryEventsWithMigration(Ditto ditto, String userId) async {
  final result = await ditto.store.execute(
    'SELECT * FROM userEvents WHERE userId = :userId ORDER BY timestamp DESC LIMIT 50',
    arguments: {'userId': userId},
  );

  print('✅ Events with schema migration:');
  for (final item in result.items) {
    final event = item.value;
    final schemaVersion = (event['schemaVersion'] as int?) ?? 1;

    // Migrate old schema to new schema
    Map<String, dynamic> migratedEvent;
    if (schemaVersion == 1) {
      // Migrate v1 to v2 format
      migratedEvent = _migrateEventV1toV2(event);
    } else {
      migratedEvent = event;
    }

    print('  ${migratedEvent['timestamp']}: ${migratedEvent['actionType']}');
  }

  // ✅ BENEFIT: Old events still queryable with schema migration
}

Map<String, dynamic> _migrateEventV1toV2(Map<String, dynamic> eventV1) {
  // Example migration logic
  return {
    ...eventV1,
    'schemaVersion': 2,
    'details': {
      ...eventV1['details'] as Map<String, dynamic>,
      'migratedAt': DateTime.now().toIso8601String(),
    },
  };
}

// ============================================================================
// PATTERN 10: Two-Collection Pattern (Events + Current State)
// ============================================================================

/// Maintain both event history and current state
Future<void> updateWithEventHistory(
  Ditto ditto,
  String orderId,
  String newStatus,
  String userId,
) async {
  // 1. Log event (immutable history)
  final eventId = 'event_${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';
  await ditto.store.execute(
    '''
    INSERT INTO orderStatusEvents (
      _id, orderId, status, userId, timestamp
    )
    VALUES (:eventId, :orderId, :status, :userId, :timestamp)
    ''',
    arguments: {
      'eventId': eventId,
      'orderId': orderId,
      'status': newStatus,
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // 2. Update current state (mutable)
  await ditto.store.execute(
    '''
    UPDATE orders
    SET status = :status, statusUpdatedAt = :timestamp
    WHERE _id = :orderId
    ''',
    arguments: {
      'orderId': orderId,
      'status': newStatus,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Order status updated: $newStatus (event logged)');

  // ✅ BENEFIT:
  // - orders collection: Fast current state queries
  // - orderStatusEvents collection: Complete audit history
  // - Best of both worlds: performance + auditability
}
