// ============================================================================
// Event History Anti-Pattern (Array-Based Event Logs)
// ============================================================================
//
// This example demonstrates why array-based event logs are problematic
// in Ditto and lead to lost events due to concurrent append conflicts.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Array-based event logs (concurrent append conflicts)
// 2. ❌ Lost events from last-write-wins
// 3. ❌ Event reordering issues
// 4. ❌ Array size limits breaking event storage
// 5. ❌ Inefficient queries requiring full document reads
// 6. ❌ Event deletion complications
// 7. ❌ Concurrent event logging from multiple devices
//
// WHY ARRAYS FAIL FOR EVENT LOGS:
// - Last-write-wins: Concurrent appends lose events
// - No merge support: Array treated as single atomic value
// - Size limits: Arrays can't grow indefinitely (5 MB document limit)
// - Performance: Must read entire array to query events
// - Inflexible: Can't efficiently filter or aggregate
//
// SOLUTION: Use separate documents per event (see event-history-good.dart)
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: Concurrent Append Conflicts
// ============================================================================

/// ❌ BAD: Appending events to array loses concurrent events
Future<void> antiPattern1_ConcurrentAppends(Ditto ditto, String userId) async {
  // Initial user activity log with array
  await ditto.store.execute(
    '''
    INSERT INTO userActivityLogs (_id, userId, events)
    VALUES (:id, :userId, :events)
    ''',
    arguments: {
      'id': 'log_$userId',
      'userId': userId,
      'events': [
        {'action': 'login', 'timestamp': DateTime.now().toIso8601String()},
      ],
    },
  );

  // ❌ Device A: User clicks button
  final resultA = await ditto.store.execute(
    'SELECT * FROM userActivityLogs WHERE _id = :id',
    arguments: {'id': 'log_$userId'},
  );
  final eventsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['events'] as List,
  );
  eventsA.add({
    'action': 'button_click',
    'buttonId': 'submit',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // ❌ Device B: User views page (almost simultaneously)
  final resultB = await ditto.store.execute(
    'SELECT * FROM userActivityLogs WHERE _id = :id',
    arguments: {'id': 'log_$userId'},
  );
  final eventsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['events'] as List,
  );
  eventsB.add({
    'action': 'page_view',
    'page': '/dashboard',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // Both devices write back
  await ditto.store.execute(
    'UPDATE userActivityLogs SET events = :events WHERE _id = :id',
    arguments: {'id': 'log_$userId', 'events': eventsA},
  );
  await ditto.store.execute(
    'UPDATE userActivityLogs SET events = :events WHERE _id = :id',
    arguments: {'id': 'log_$userId', 'events': eventsB},
  );

  // 🚨 RESULT: Last-write-wins!
  // Either button_click or page_view event is lost
  // Analytics data is incomplete and unreliable

  print('❌ Lost event: One of the concurrent events disappeared');
  print('   Expected: login, button_click, page_view');
  print('   Actual: login, [one event lost]');
}

// ============================================================================
// ANTI-PATTERN 2: Transaction History with Lost Events
// ============================================================================

/// ❌ BAD: Financial transactions in array (critical data loss)
Future<void> antiPattern2_LostTransactions(Ditto ditto, String accountId) async {
  // Account with transaction history array
  await ditto.store.execute(
    '''
    INSERT INTO accounts (_id, balance, transactions)
    VALUES (:id, :balance, :transactions)
    ''',
    arguments: {
      'id': accountId,
      'balance': 1000.00,
      'transactions': <Map<String, dynamic>>[],
    },
  );

  // ❌ Device A: User makes deposit
  final resultA = await ditto.store.execute(
    'SELECT * FROM accounts WHERE _id = :id',
    arguments: {'id': accountId},
  );
  final accountA = resultA.items.first.value;
  final transactionsA = List<Map<String, dynamic>>.from(
    accountA['transactions'] as List,
  );
  transactionsA.add({
    'type': 'deposit',
    'amount': 500.00,
    'timestamp': DateTime.now().toIso8601String(),
  });
  final balanceA = (accountA['balance'] as num) + 500.00;

  // ❌ Device B: User makes withdrawal (simultaneously on different device)
  final resultB = await ditto.store.execute(
    'SELECT * FROM accounts WHERE _id = :id',
    arguments: {'id': accountId},
  );
  final accountB = resultB.items.first.value;
  final transactionsB = List<Map<String, dynamic>>.from(
    accountB['transactions'] as List,
  );
  transactionsB.add({
    'type': 'withdrawal',
    'amount': 200.00,
    'timestamp': DateTime.now().toIso8601String(),
  });
  final balanceB = (accountB['balance'] as num) - 200.00;

  // Both devices write back
  await ditto.store.execute(
    'UPDATE accounts SET balance = :balance, transactions = :transactions WHERE _id = :id',
    arguments: {'id': accountId, 'balance': balanceA, 'transactions': transactionsA},
  );
  await ditto.store.execute(
    'UPDATE accounts SET balance = :balance, transactions = :transactions WHERE _id = :id',
    arguments: {'id': accountId, 'balance': balanceB, 'transactions': transactionsB},
  );

  // 🚨 CRITICAL ISSUE: One transaction lost!
  // Transaction history incomplete
  // Balance may be incorrect
  // Audit trail broken
  // Legal/compliance issues

  print('❌ CRITICAL: Transaction lost in financial records!');
  print('   Expected: deposit \$500, withdrawal \$200');
  print('   Actual: Only one transaction recorded');
  print('   Balance inconsistency: Cannot reconcile account');
}

// ============================================================================
// ANTI-PATTERN 3: Audit Log with Missing Entries
// ============================================================================

/// ❌ BAD: Audit log in array (compliance failure)
Future<void> antiPattern3_IncompleteAuditLog(Ditto ditto, String documentId) async {
  // Document with audit log array
  await ditto.store.execute(
    '''
    INSERT INTO documents (_id, content, auditLog)
    VALUES (:id, :content, :auditLog)
    ''',
    arguments: {
      'id': documentId,
      'content': 'Important document',
      'auditLog': <Map<String, dynamic>>[],
    },
  );

  // ❌ Device A: User edits document
  final resultA = await ditto.store.execute(
    'SELECT * FROM documents WHERE _id = :id',
    arguments: {'id': documentId},
  );
  final docA = resultA.items.first.value;
  final auditLogA = List<Map<String, dynamic>>.from(docA['auditLog'] as List);
  auditLogA.add({
    'userId': 'user_123',
    'action': 'edit',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // ❌ Device B: User shares document (simultaneously)
  final resultB = await ditto.store.execute(
    'SELECT * FROM documents WHERE _id = :id',
    arguments: {'id': documentId},
  );
  final docB = resultB.items.first.value;
  final auditLogB = List<Map<String, dynamic>>.from(docB['auditLog'] as List);
  auditLogB.add({
    'userId': 'user_456',
    'action': 'share',
    'recipientId': 'user_789',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // Both devices write back
  await ditto.store.execute(
    'UPDATE documents SET auditLog = :auditLog WHERE _id = :id',
    arguments: {'id': documentId, 'auditLog': auditLogA},
  );
  await ditto.store.execute(
    'UPDATE documents SET auditLog = :auditLog WHERE _id = :id',
    arguments: {'id': documentId, 'auditLog': auditLogB},
  );

  // 🚨 COMPLIANCE FAILURE: Audit log incomplete
  // Cannot prove who did what when
  // Regulatory requirements violated
  // Legal liability

  print('❌ COMPLIANCE FAILURE: Audit log has missing entries!');
  print('   Required: Complete audit trail');
  print('   Actual: One action not logged');
}

// ============================================================================
// ANTI-PATTERN 4: Array Size Limit Breaking Event Storage
// ============================================================================

/// ❌ BAD: Event log array grows indefinitely until hitting limit
Future<void> antiPattern4_ArraySizeLimit(Ditto ditto, String sessionId) async {
  // Session with event array
  await ditto.store.execute(
    '''
    INSERT INTO sessions (_id, events)
    VALUES (:id, :events)
    ''',
    arguments: {
      'id': sessionId,
      'events': <Map<String, dynamic>>[],
    },
  );

  // Simulate: Log many events over time
  print('❌ Logging events to array:');
  for (var i = 0; i < 10000; i++) {
    final result = await ditto.store.execute(
      'SELECT * FROM sessions WHERE _id = :id',
      arguments: {'id': sessionId},
    );

    if (result.items.isEmpty) break;

    final session = result.items.first.value;
    final events = List<Map<String, dynamic>>.from(session['events'] as List);

    events.add({
      'eventNumber': i,
      'action': 'user_action_$i',
      'timestamp': DateTime.now().toIso8601String(),
      'data': {'someData': 'value' * 100}, // Some event data
    });

    try {
      await ditto.store.execute(
        'UPDATE sessions SET events = :events WHERE _id = :id',
        arguments: {'id': sessionId, 'events': events},
      );

      if (i % 1000 == 0) {
        print('  Logged $i events...');
      }
    } catch (e) {
      print('  ❌ ERROR at event $i: $e');
      print('  Document size limit reached (5 MB)!');
      print('  Cannot log more events!');
      break;
    }
  }

  // 🚨 PROBLEM: Array size hits document limit
  // Can no longer log events
  // Event storage breaks mid-session

  print('❌ Array size limit: Event logging failed');
}

// ============================================================================
// ANTI-PATTERN 5: Inefficient Queries Requiring Full Document Read
// ============================================================================

/// ❌ BAD: Must read entire array to query recent events
Future<void> antiPattern5_InefficientQueries(Ditto ditto, String userId) async {
  // ❌ To find events from last hour, must read entire array
  final result = await ditto.store.execute(
    'SELECT * FROM userActivityLogs WHERE _id = :id',
    arguments: {'id': 'log_$userId'},
  );

  if (result.items.isEmpty) return;

  final allEvents = List<Map<String, dynamic>>.from(
    result.items.first.value['events'] as List,
  );

  print('❌ Inefficient: Read ${allEvents.length} events from array');

  // Filter in application code
  final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
  final recentEvents = allEvents.where((event) {
    final timestamp = DateTime.parse(event['timestamp'] as String);
    return timestamp.isAfter(oneHourAgo);
  }).toList();

  print('   Needed only ${recentEvents.length} recent events');
  print('   But had to read and transfer all ${allEvents.length} events');

  // 🚨 PROBLEMS:
  // - Bandwidth waste (reading unnecessary data)
  // - Memory usage (loading entire array)
  // - Performance degradation as array grows
  // - Cannot use indexes or efficient filtering
}

// ============================================================================
// ANTI-PATTERN 6: Event Deletion Complications
// ============================================================================

/// ❌ BAD: Deleting old events requires read-modify-write
Future<void> antiPattern6_EventDeletion(Ditto ditto, String userId) async {
  // ❌ To remove events older than 30 days, must read entire array
  final result = await ditto.store.execute(
    'SELECT * FROM userActivityLogs WHERE _id = :id',
    arguments: {'id': 'log_$userId'},
  );

  if (result.items.isEmpty) return;

  final allEvents = List<Map<String, dynamic>>.from(
    result.items.first.value['events'] as List,
  );

  // Filter out old events in application code
  final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
  final retainedEvents = allEvents.where((event) {
    final timestamp = DateTime.parse(event['timestamp'] as String);
    return timestamp.isAfter(cutoffDate);
  }).toList();

  // Write back filtered array
  await ditto.store.execute(
    'UPDATE userActivityLogs SET events = :events WHERE _id = :id',
    arguments: {'id': 'log_$userId', 'events': retainedEvents},
  );

  print('❌ Inefficient deletion:');
  print('   Removed ${allEvents.length - retainedEvents.length} old events');
  print('   Required reading and rewriting entire array');

  // 🚨 PROBLEMS:
  // - Read entire array to delete a few events
  // - Rewrite entire array (bandwidth waste)
  // - Concurrent append conflict during cleanup
  // - Cannot use EVICT for selective cleanup
}

// ============================================================================
// ANTI-PATTERN 7: Event Reordering Issues
// ============================================================================

/// ❌ BAD: Array order can be lost in conflicts
Future<void> antiPattern7_EventReordering(Ditto ditto, String userId) async {
  // Initial events in chronological order
  await ditto.store.execute(
    '''
    INSERT INTO userActivityLogs (_id, userId, events)
    VALUES (:id, :userId, :events)
    ''',
    arguments: {
      'id': 'log_$userId',
      'userId': userId,
      'events': [
        {'seq': 1, 'action': 'event_1', 'timestamp': '2024-01-01T10:00:00Z'},
        {'seq': 2, 'action': 'event_2', 'timestamp': '2024-01-01T10:01:00Z'},
        {'seq': 3, 'action': 'event_3', 'timestamp': '2024-01-01T10:02:00Z'},
      ],
    },
  );

  // ❌ Device A: Appends event_4
  final resultA = await ditto.store.execute(
    'SELECT * FROM userActivityLogs WHERE _id = :id',
    arguments: {'id': 'log_$userId'},
  );
  final eventsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['events'] as List,
  );
  eventsA.add({'seq': 4, 'action': 'event_4', 'timestamp': '2024-01-01T10:03:00Z'});

  // ❌ Device B: Appends event_5 (simultaneously)
  final resultB = await ditto.store.execute(
    'SELECT * FROM userActivityLogs WHERE _id = :id',
    arguments: {'id': 'log_$userId'},
  );
  final eventsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['events'] as List,
  );
  eventsB.add({'seq': 5, 'action': 'event_5', 'timestamp': '2024-01-01T10:04:00Z'});

  // Both devices write
  await ditto.store.execute(
    'UPDATE userActivityLogs SET events = :events WHERE _id = :id',
    arguments: {'id': 'log_$userId', 'events': eventsA},
  );
  await ditto.store.execute(
    'UPDATE userActivityLogs SET events = :events WHERE _id = :id',
    arguments: {'id': 'log_$userId', 'events': eventsB},
  );

  // 🚨 RESULT: One event lost, chronological order broken
  // Events: 1, 2, 3, [4 or 5] (one missing)
  // Timeline incomplete and potentially out of order

  print('❌ Event ordering broken:');
  print('   Expected: events 1, 2, 3, 4, 5');
  print('   Actual: events 1, 2, 3, [4 or 5] (one lost)');
}

// ============================================================================
// ANTI-PATTERN 8: Analytics Events with Lost Data
// ============================================================================

/// ❌ BAD: Analytics array loses concurrent events
Future<void> antiPattern8_LostAnalytics(Ditto ditto, String sessionId) async {
  // Session with analytics events array
  await ditto.store.execute(
    '''
    INSERT INTO sessions (_id, analyticsEvents)
    VALUES (:id, :events)
    ''',
    arguments: {
      'id': sessionId,
      'events': <Map<String, dynamic>>[],
    },
  );

  // Simulate: Multiple components logging events concurrently
  print('❌ Multiple components logging analytics:');

  // Component A: Video player
  final resultA = await ditto.store.execute(
    'SELECT * FROM sessions WHERE _id = :id',
    arguments: {'id': sessionId},
  );
  final eventsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['analyticsEvents'] as List,
  );
  eventsA.add({'event': 'video_play', 'videoId': 'vid_123'});

  // Component B: Ad tracking
  final resultB = await ditto.store.execute(
    'SELECT * FROM sessions WHERE _id = :id',
    arguments: {'id': sessionId},
  );
  final eventsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['analyticsEvents'] as List,
  );
  eventsB.add({'event': 'ad_impression', 'adId': 'ad_456'});

  // Component C: Navigation tracking
  final resultC = await ditto.store.execute(
    'SELECT * FROM sessions WHERE _id = :id',
    arguments: {'id': sessionId},
  );
  final eventsC = List<Map<String, dynamic>>.from(
    resultC.items.first.value['analyticsEvents'] as List,
  );
  eventsC.add({'event': 'page_view', 'page': '/home'});

  // All components write back (race condition)
  await ditto.store.execute(
    'UPDATE sessions SET analyticsEvents = :events WHERE _id = :id',
    arguments: {'id': sessionId, 'events': eventsA},
  );
  await ditto.store.execute(
    'UPDATE sessions SET analyticsEvents = :events WHERE _id = :id',
    arguments: {'id': sessionId, 'events': eventsB},
  );
  await ditto.store.execute(
    'UPDATE sessions SET analyticsEvents = :events WHERE _id = :id',
    arguments: {'id': sessionId, 'events': eventsC},
  );

  // 🚨 RESULT: Only last event survives
  // Two analytics events lost
  // Metrics incomplete and inaccurate

  print('❌ Analytics data loss:');
  print('   Expected: video_play, ad_impression, page_view');
  print('   Actual: Only one event recorded');
  print('   Impact: Incorrect metrics, lost revenue data');
}
