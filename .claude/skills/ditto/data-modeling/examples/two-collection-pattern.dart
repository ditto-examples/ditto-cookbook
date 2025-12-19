// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Two-Collection Pattern (Events + Current State)
// ============================================================================
//
// This example demonstrates the two-collection pattern where you maintain
// both an event history (immutable append-only) and current state (mutable).
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Dual write pattern (events + current state)
// 2. ✅ Real-time + historical data separation
// 3. ✅ Atomic dual writes (when possible)
// 4. ✅ Differentiated sync subscriptions
// 5. ✅ Event replay for state reconstruction
// 6. ✅ Audit trail with performance
// 7. ✅ Cleanup strategies for each collection
//
// WHY TWO COLLECTIONS:
// - Events: Complete audit history, immutable, append-only
// - Current State: Fast queries, mutable, optimized for reads
// - Performance: Query current state without scanning events
// - History: Replay events for debugging or reconstruction
//
// WHEN TO USE:
// - Need both current state AND full history
// - Performance-critical current state queries
// - Audit requirements for historical data
// - Event sourcing patterns
//
// TRADEOFFS:
// - Storage: Duplicates some data
// - Complexity: Must keep both collections in sync
// - Consistency: Requires careful dual-write handling
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Order Status with Event History
// ============================================================================

/// ✅ GOOD: Maintain both current state and status history
Future<void> updateOrderStatusWithHistory(
  Ditto ditto,
  String orderId,
  String newStatus,
  String userId,
) async {
  // 1. Log status change event (immutable history)
  final eventId = 'status_event_${DateTime.now().millisecondsSinceEpoch}';
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

  // 2. Update current order state (mutable)
  await ditto.store.execute(
    '''
    UPDATE orders
    SET status = :status, statusUpdatedAt = :timestamp, statusUpdatedBy = :userId
    WHERE _id = :orderId
    ''',
    arguments: {
      'orderId': orderId,
      'status': newStatus,
      'timestamp': DateTime.now().toIso8601String(),
      'userId': userId,
    },
  );

  print('✅ Order status updated in both collections:');
  print('   orders: Current state = $newStatus');
  print('   orderStatusEvents: New event logged');
}

/// Query current order status (fast)
Future<void> getCurrentOrderStatus(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    'SELECT status FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  if (result.items.isNotEmpty) {
    final status = result.items.first.value['status'];
    print('✅ Current status (fast query): $status');
  }
}

/// Query full order status history
Future<void> getOrderStatusHistory(Ditto ditto, String orderId) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM orderStatusEvents
    WHERE orderId = :orderId
    ORDER BY timestamp ASC
    ''',
    arguments: {'orderId': orderId},
  );

  print('✅ Order status history (${result.items.length} events):');
  for (final item in result.items) {
    final event = item.value;
    print('   ${event['timestamp']}: ${event['status']} by ${event['userId']}');
  }
}

// ============================================================================
// PATTERN 2: User Balance with Transaction History
// ============================================================================

/// ✅ GOOD: Current balance + complete transaction history
Future<void> processTransaction(
  Ditto ditto,
  String accountId,
  String transactionType,
  double amount,
  String description,
) async {
  // 1. Log transaction event (immutable)
  final transactionId = 'txn_${DateTime.now().millisecondsSinceEpoch}';
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

  // 2. Update current account balance (mutable)
  final balanceChange = transactionType == 'credit' ? amount : -amount;
  await ditto.store.execute(
    '''
    UPDATE accounts
    APPLY balance PN_INCREMENT BY :change,
          lastTransactionAt = :timestamp
    WHERE _id = :accountId
    ''',
    arguments: {
      'accountId': accountId,
      'change': balanceChange,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Transaction processed:');
  print('   transactions: Event logged ($transactionType \$$amount)');
  print('   accounts: Balance updated (${balanceChange > 0 ? "+" : ""}\$$balanceChange)');
}

/// Query current balance (instant)
Future<double?> getCurrentBalance(Ditto ditto, String accountId) async {
  final result = await ditto.store.execute(
    'SELECT balance FROM accounts WHERE _id = :accountId',
    arguments: {'accountId': accountId},
  );

  if (result.items.isEmpty) return null;

  final balance = result.items.first.value['balance'] as double?;
  print('✅ Current balance (instant query): \$$balance');
  return balance;
}

/// Reconstruct balance from transaction history (for verification)
Future<double> reconstructBalanceFromHistory(
  Ditto ditto,
  String accountId,
) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM transactions
    WHERE accountId = :accountId
    ORDER BY timestamp ASC
    ''',
    arguments: {'accountId': accountId},
  );

  var reconstructedBalance = 0.0;
  for (final item in result.items) {
    final txn = item.value;
    final amount = txn['amount'] as double;
    final type = txn['transactionType'] as String;

    reconstructedBalance += type == 'credit' ? amount : -amount;
  }

  print('✅ Balance reconstructed from ${result.items.length} transactions: \$$reconstructedBalance');
  return reconstructedBalance;
}

// ============================================================================
// PATTERN 3: Inventory with Adjustment Log
// ============================================================================

/// ✅ GOOD: Current stock + adjustment history
Future<void> adjustInventoryWithLog(
  Ditto ditto,
  String productId,
  double quantityChange,
  String reason,
  String userId,
) async {
  // 1. Log inventory adjustment event
  final eventId = 'inv_event_${DateTime.now().millisecondsSinceEpoch}';
  await ditto.store.execute(
    '''
    INSERT INTO inventoryEvents (
      _id, productId, quantityChange, reason, userId, timestamp
    )
    VALUES (:eventId, :productId, :change, :reason, :userId, :timestamp)
    ''',
    arguments: {
      'eventId': eventId,
      'productId': productId,
      'change': quantityChange,
      'reason': reason,
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // 2. Update current stock quantity
  await ditto.store.execute(
    '''
    UPDATE products
    APPLY stockQuantity PN_INCREMENT BY :change,
          lastInventoryAdjustmentAt = :timestamp
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'change': quantityChange,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Inventory adjusted:');
  print('   inventoryEvents: Logged ${quantityChange > 0 ? "+" : ""}$quantityChange ($reason)');
  print('   products: Stock quantity updated');
}

/// Audit inventory discrepancies
Future<void> auditInventory(Ditto ditto, String productId) async {
  // Get current stock quantity
  final productResult = await ditto.store.execute(
    'SELECT stockQuantity FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  if (productResult.items.isEmpty) {
    print('⚠️ Product not found');
    return;
  }

  final currentStock = (productResult.items.first.value['stockQuantity'] as num?)?.toDouble() ?? 0.0;

  // Reconstruct stock from events
  final eventsResult = await ditto.store.execute(
    '''
    SELECT * FROM inventoryEvents
    WHERE productId = :productId
    ORDER BY timestamp ASC
    ''',
    arguments: {'productId': productId},
  );

  var reconstructedStock = 0.0;
  for (final item in eventsResult.items) {
    final event = item.value;
    final change = (event['quantityChange'] as num).toDouble();
    reconstructedStock += change;
  }

  print('✅ Inventory audit for product $productId:');
  print('   Current stock: $currentStock');
  print('   Reconstructed from events: $reconstructedStock');
  if ((currentStock - reconstructedStock).abs() > 0.001) {
    print('   ⚠️ DISCREPANCY DETECTED: ${currentStock - reconstructedStock}');
  } else {
    print('   ✅ Stock matches event history');
  }
}

// ============================================================================
// PATTERN 4: Differentiated Sync Subscriptions
// ============================================================================

/// ✅ GOOD: Subscribe to current state with high priority
Future<void> setupDifferentiatedSubscriptions(Ditto ditto, String userId) async {
  // Subscription 1: Current orders (high priority, always synced)
  final currentOrdersSub = ditto.sync.registerSubscription(
    '''
    SELECT * FROM orders
    WHERE customerId = :userId AND status IN ('pending', 'processing', 'shipped')
    ''',
    arguments: {'userId': userId},
  );

  print('✅ Subscribed to current orders (high priority)');

  // Subscription 2: Order history events (lower priority, sync when needed)
  final orderHistorySub = ditto.sync.registerSubscription(
    '''
    SELECT * FROM orderStatusEvents
    WHERE orderId IN (
      SELECT _id FROM orders WHERE customerId = :userId
    )
    ''',
    arguments: {'userId': userId},
  );

  print('✅ Subscribed to order history events (lower priority)');

  // ✅ BENEFIT:
  // - Current state syncs immediately (small, critical)
  // - History syncs when bandwidth available (larger, less urgent)
  // - User sees current data fast, history loads progressively
}

// ============================================================================
// PATTERN 5: Event Replay for State Reconstruction
// ============================================================================

/// ✅ GOOD: Replay events to rebuild current state
Future<void> rebuildCurrentStateFromEvents(Ditto ditto, String orderId) async {
  print('✅ Rebuilding order state from events:');

  // Get all status events
  final eventsResult = await ditto.store.execute(
    '''
    SELECT * FROM orderStatusEvents
    WHERE orderId = :orderId
    ORDER BY timestamp ASC
    ''',
    arguments: {'orderId': orderId},
  );

  if (eventsResult.items.isEmpty) {
    print('   No events found');
    return;
  }

  // Replay events to determine current state
  String? currentStatus;
  String? lastUserId;
  String? lastTimestamp;

  for (final item in eventsResult.items) {
    final event = item.value;
    currentStatus = event['status'] as String;
    lastUserId = event['userId'] as String;
    lastTimestamp = event['timestamp'] as String;

    print('   Replaying: $lastTimestamp - $currentStatus by $lastUserId');
  }

  // Update current state document
  if (currentStatus != null) {
    await ditto.store.execute(
      '''
      UPDATE orders
      SET status = :status,
          statusUpdatedAt = :timestamp,
          statusUpdatedBy = :userId,
          rebuiltFromEvents = true
      WHERE _id = :orderId
      ''',
      arguments: {
        'orderId': orderId,
        'status': currentStatus,
        'timestamp': lastTimestamp!,
        'userId': lastUserId!,
      },
    );

    print('   ✅ Current state rebuilt: $currentStatus');
  }
}

// ============================================================================
// PATTERN 6: Cleanup Strategies
// ============================================================================

/// ✅ GOOD: Different retention policies for each collection
Future<void> cleanupWithDifferentPolicies(Ditto ditto) async {
  // Current state: Keep all active orders
  // No cleanup needed (orders are deleted when complete)

  // Event history: Keep 90 days, then EVICT old events
  final cutoffDate = DateTime.now()
      .subtract(const Duration(days: 90))
      .toIso8601String();

  // EVICT old order status events
  await ditto.store.execute(
    '''
    EVICT FROM orderStatusEvents
    WHERE timestamp < :cutoffDate
    ''',
    arguments: {'cutoffDate': cutoffDate},
  );

  print('✅ Cleanup complete:');
  print('   orders: All active orders retained');
  print('   orderStatusEvents: Events older than 90 days evicted');

  // ✅ BENEFIT:
  // - Current state: Comprehensive, always available
  // - Event history: Trimmed to retention window
  // - Storage: Optimized without losing critical data
}

// ============================================================================
// PATTERN 7: Versioned State Changes
// ============================================================================

/// ✅ GOOD: Track state version with each change
Future<void> updateWithVersion(
  Ditto ditto,
  String documentId,
  Map<String, dynamic> newData,
  String userId,
) async {
  // Get current version
  final result = await ditto.store.execute(
    'SELECT version FROM documents WHERE _id = :id',
    arguments: {'id': documentId},
  );

  final currentVersion = (result.items.firstOrNull?.value['version'] as int?) ?? 0;
  final newVersion = currentVersion + 1;

  // 1. Log version change event
  final eventId = 'version_event_${DateTime.now().millisecondsSinceEpoch}';
  await ditto.store.execute(
    '''
    INSERT INTO documentVersionEvents (
      _id, documentId, version, data, userId, timestamp
    )
    VALUES (:eventId, :documentId, :version, :data, :userId, :timestamp)
    ''',
    arguments: {
      'eventId': eventId,
      'documentId': documentId,
      'version': newVersion,
      'data': newData,
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // 2. Update current document
  await ditto.store.execute(
    '''
    UPDATE documents
    SET data = :data, version = :version, updatedAt = :timestamp
    WHERE _id = :documentId
    ''',
    arguments: {
      'documentId': documentId,
      'data': newData,
      'version': newVersion,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Document updated to version $newVersion');
  print('   documentVersionEvents: Version $newVersion logged');
  print('   documents: Current version updated');
}

/// Get document version history
Future<void> getVersionHistory(Ditto ditto, String documentId) async {
  final result = await ditto.store.execute(
    '''
    SELECT * FROM documentVersionEvents
    WHERE documentId = :documentId
    ORDER BY version ASC
    ''',
    arguments: {'documentId': documentId},
  );

  print('✅ Document version history (${result.items.length} versions):');
  for (final item in result.items) {
    final event = item.value;
    print('   v${event['version']}: ${event['timestamp']} by ${event['userId']}');
  }
}

// ============================================================================
// PATTERN 8: Aggregated Metrics with Event Source
// ============================================================================

/// ✅ GOOD: Maintain aggregated metrics + raw events
Future<void> trackUserActivityMetrics(
  Ditto ditto,
  String userId,
  String actionType,
) async {
  // 1. Log individual activity event
  final eventId = 'activity_${DateTime.now().millisecondsSinceEpoch}';
  await ditto.store.execute(
    '''
    INSERT INTO userActivityEvents (
      _id, userId, actionType, timestamp
    )
    VALUES (:eventId, :userId, :actionType, :timestamp)
    ''',
    arguments: {
      'eventId': eventId,
      'userId': userId,
      'actionType': actionType,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // 2. Update aggregated metrics
  await ditto.store.execute(
    '''
    UPDATE userMetrics
    APPLY totalActions PN_INCREMENT BY 1.0,
          lastActiveAt = :timestamp
    WHERE userId = :userId
    ''',
    arguments: {
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Activity tracked:');
  print('   userActivityEvents: Individual event logged');
  print('   userMetrics: Aggregated counter incremented');

  // ✅ BENEFIT:
  // - userMetrics: Fast dashboard queries (pre-aggregated)
  // - userActivityEvents: Detailed drill-down available
}

// ============================================================================
// PATTERN 9: Eventual Consistency Handling
// ============================================================================

/// Handle eventual consistency between collections
Future<void> verifyConsistency(Ditto ditto, String orderId) async {
  // Query current state
  final orderResult = await ditto.store.execute(
    'SELECT status FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  if (orderResult.items.isEmpty) {
    print('⚠️ Order not found in current state');
    return;
  }

  final currentStatus = orderResult.items.first.value['status'] as String;

  // Query latest event
  final eventsResult = await ditto.store.execute(
    '''
    SELECT status FROM orderStatusEvents
    WHERE orderId = :orderId
    ORDER BY timestamp DESC
    LIMIT 1
    ''',
    arguments: {'orderId': orderId},
  );

  if (eventsResult.items.isEmpty) {
    print('⚠️ No events found for order');
    return;
  }

  final latestEventStatus = eventsResult.items.first.value['status'] as String;

  print('✅ Consistency check:');
  print('   Current state: $currentStatus');
  print('   Latest event: $latestEventStatus');

  if (currentStatus != latestEventStatus) {
    print('   ⚠️ INCONSISTENCY: Current state differs from latest event');
    print('   Consider rebuilding state from events');
  } else {
    print('   ✅ Consistent: State matches latest event');
  }
}
