// SDK Version: 4.12+
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Unnecessary Delta Creation Anti-Patterns
// ============================================================================
//
// This example demonstrates common mistakes that create unnecessary deltas
// in Ditto, wasting bandwidth and degrading sync performance.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ UPDATE without checking if value changed
// 2. ❌ Using DO UPDATE instead of DO UPDATE_LOCAL_DIFF
// 3. ❌ Full document replacement for single field change
// 4. ❌ High-frequency updates without throttling
// 5. ❌ Updating unchanged values
// 6. ❌ Multiple UPDATEs instead of batch
// 7. ❌ Timestamp updates on every operation
//
// WHY THESE ARE PROBLEMS:
// - Wasted bandwidth (up to 10x more sync traffic)
// - Slower sync (network congestion)
// - Increased battery drain
// - Storage bloat from tombstones
// - Poor performance on slow networks
//
// SOLUTION: See unnecessary-deltas-good.dart for correct patterns
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: UPDATE Without Checking If Value Changed
// ============================================================================

/// ❌ BAD: Always UPDATE, even if value unchanged
class NoValueCheckBad {
  final Ditto ditto;

  NoValueCheckBad(this.ditto);

  Future<void> updateUserStatus(String userId, String newStatus) async {
    print('❌ Updating user status without checking current value...');

    // ❌ BAD: UPDATE without reading current value
    await ditto.store.execute(
      'UPDATE users SET status = :status WHERE _id = :userId',
      arguments: {'userId': userId, 'status': newStatus},
    );

    print('  ❌ UPDATE executed (may be unnecessary)');

    // 🚨 PROBLEMS:
    // - Creates delta even if status didn't change
    // - Wastes bandwidth syncing unchanged value
    // - User with status "online" receives "online" update repeatedly
    // - Sync traffic 10x higher than necessary
  }

  Future<void> periodicStatusUpdate(String userId) async {
    print('❌ Periodic status update (every 30s)...');

    // ❌ BAD: Update status every 30 seconds, regardless of change
    // This is a common pattern in apps with presence indicators

    while (true) {
      await Future.delayed(const Duration(seconds: 30));

      // ❌ Always UPDATE, even if status hasn't changed
      await ditto.store.execute(
        'UPDATE users SET lastSeen = :timestamp WHERE _id = :userId',
        arguments: {
          'userId': userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      print('  ❌ Timestamp updated (creates delta every 30s)');

      // 🚨 PROBLEMS:
      // - 120 deltas per hour (2 per minute)
      // - 2,880 deltas per day
      // - Massive sync traffic for no actual status change
      // - Drains battery with constant sync
    }
  }
}

// ============================================================================
// ANTI-PATTERN 2: Using DO UPDATE Instead of DO UPDATE_LOCAL_DIFF
// ============================================================================

/// ❌ BAD: DO UPDATE syncs entire document
class NoLocalDiffBad {
  final Ditto ditto;

  NoLocalDiffBad(this.ditto);

  Future<void> updateUserProfile(
    String userId,
    String? name,
    String? email,
  ) async {
    print('❌ Updating user profile with DO UPDATE...');

    // ❌ BAD: DO UPDATE (entire document syncs)
    await ditto.store.execute(
      '''DO UPDATE
         UPDATE users
         SET name = :name,
             email = :email,
             updatedAt = :updatedAt
         WHERE _id = :userId''',
      arguments: {
        'userId': userId,
        'name': name,
        'email': email,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ DO UPDATE executed (entire document will sync)');

    // 🚨 PROBLEMS:
    // - Entire document syncs, including:
    //   • name (changed)
    //   • email (changed)
    //   • bio (unchanged, but still syncs!)
    //   • avatarUrl (unchanged, but still syncs!)
    //   • createdAt (unchanged, but still syncs!)
    //   • preferences (unchanged, but still syncs!)
    // - 10x more bandwidth than DO UPDATE_LOCAL_DIFF
    // - Wastes bandwidth for large documents
  }

  Future<void> incrementViewCount(String postId) async {
    print('❌ Incrementing view count with DO UPDATE...');

    // ❌ BAD: DO UPDATE for single field change
    await ditto.store.execute(
      '''DO UPDATE
         UPDATE posts
         APPLY viewCount PN_INCREMENT BY 1.0
         WHERE _id = :postId''',
      arguments: {'postId': postId},
    );

    print('  ❌ Entire post document syncs (title, content, author, etc.)');
    print('  Only viewCount changed, but everything syncs');

    // 🚨 PROBLEM:
    // - Post with 5KB content syncs 5KB for every view
    // - Should only sync ~10 bytes (viewCount field)
    // - 500x bandwidth waste!
  }
}

// ============================================================================
// ANTI-PATTERN 3: Full Document Replacement for Single Field
// ============================================================================

/// ❌ BAD: Replace entire document to change one field
class FullDocumentReplacementBad {
  final Ditto ditto;

  FullDocumentReplacementBad(this.ditto);

  Future<void> toggleTodoComplete(String todoId) async {
    print('❌ Toggling todo with full document replacement...');

    // ❌ Step 1: Query entire document
    final result = await ditto.store.execute(
      'SELECT * FROM todos WHERE _id = :todoId',
      arguments: {'todoId': todoId},
    );

    if (result.items.isEmpty) return;

    final todo = result.items.first.value;

    // ❌ Step 2: Modify document in memory
    final updatedTodo = {
      ...todo,
      'isCompleted': !(todo['isCompleted'] as bool? ?? false),
    };

    // ❌ Step 3: Delete and re-insert (very bad!)
    await ditto.store.execute(
      'DELETE FROM todos WHERE _id = :todoId',
      arguments: {'todoId': todoId},
    );

    await ditto.store.execute(
      '''INSERT INTO todos (
        _id, title, description, isCompleted, priority, dueDate, createdAt
      ) VALUES (
        :id, :title, :description, :isCompleted, :priority, :dueDate, :createdAt
      )''',
      arguments: updatedTodo,
    );

    print('  ❌ Entire document replaced (DELETE + INSERT)');

    // 🚨 PROBLEMS:
    // - Creates 2 deltas (DELETE + INSERT)
    // - Entire document syncs twice
    // - Changed 1 boolean, synced entire document twice
    // - Lost concurrent updates from other devices
    // - Terrible performance
  }

  Future<void> updateTaskPriority(String taskId, int newPriority) async {
    print('❌ Updating task priority with full replacement...');

    // ❌ Query full document
    final result = await ditto.store.execute(
      'SELECT * FROM tasks WHERE _id = :taskId',
      arguments: {'taskId': taskId},
    );

    if (result.items.isEmpty) return;

    final task = result.items.first.value;

    // ❌ Replace entire document using DO UPDATE
    await ditto.store.execute(
      '''DO UPDATE
         UPDATE tasks
         SET title = :title,
             description = :description,
             priority = :priority,
             status = :status,
             assignedTo = :assignedTo,
             dueDate = :dueDate,
             createdAt = :createdAt,
             updatedAt = :updatedAt
         WHERE _id = :taskId''',
      arguments: {
        'taskId': taskId,
        'title': task['title'],
        'description': task['description'],
        'priority': newPriority, // Only this changed!
        'status': task['status'],
        'assignedTo': task['assignedTo'],
        'dueDate': task['dueDate'],
        'createdAt': task['createdAt'],
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ Entire task document synced');
    print('  Changed 1 integer (priority), synced entire document');

    // 🚨 PROBLEM:
    // - Entire document syncs (title, description, etc.)
    // - Should use: UPDATE tasks SET priority = :priority WHERE _id = :taskId
    // - 100x bandwidth waste
  }
}

// ============================================================================
// ANTI-PATTERN 4: High-Frequency Updates Without Throttling
// ============================================================================

/// ❌ BAD: Update on every minor change (no throttling)
class NoThrottlingBad {
  final Ditto ditto;

  NoThrottlingBad(this.ditto);

  Future<void> updateUserLocation(double latitude, double longitude) async {
    print('❌ Updating location without throttling...');

    // ❌ BAD: Update every GPS reading (1-10 Hz)
    await ditto.store.execute(
      '''UPDATE users
         SET latitude = :lat,
             longitude = :lng,
             lastLocationUpdate = :timestamp
         WHERE _id = :userId''',
      arguments: {
        'userId': 'user_123',
        'lat': latitude,
        'lng': longitude,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ Location updated (may be 10 times per second)');

    // 🚨 PROBLEMS:
    // - GPS updates at 10 Hz = 10 deltas per second
    // - 600 deltas per minute
    // - 36,000 deltas per hour
    // - Massive bandwidth waste
    // - Battery drain from constant sync
    // - Network congestion
  }

  Future<void> updateTypingIndicator(String userId, bool isTyping) async {
    print('❌ Updating typing indicator on every keystroke...');

    // ❌ BAD: Update on every key press
    await ditto.store.execute(
      'UPDATE chatUsers SET isTyping = :isTyping WHERE _id = :userId',
      arguments: {'userId': userId, 'isTyping': isTyping},
    );

    print('  ❌ Typing indicator updated');

    // 🚨 PROBLEMS:
    // - User types 60 WPM = ~5 key presses per second
    // - 5 deltas per second while typing
    // - 300 deltas per minute
    // - Should throttle to max 1 update per second
  }

  Future<void> updateSliderValue(String controlId, double value) async {
    print('❌ Updating slider on every drag event...');

    // ❌ BAD: Update on every slider move
    await ditto.store.execute(
      'UPDATE controls SET value = :value WHERE _id = :controlId',
      arguments: {'controlId': controlId, 'value': value},
    );

    print('  ❌ Slider value updated');

    // 🚨 PROBLEMS:
    // - Slider drag events at 60 FPS = 60 deltas per second
    // - 3,600 deltas per minute of dragging
    // - Should only update on drag end, or throttle to ~5 Hz max
  }
}

// ============================================================================
// ANTI-PATTERN 5: Updating Unchanged Values
// ============================================================================

/// ❌ BAD: Always set all fields, even if unchanged
class UpdateUnchangedValuesBad {
  final Ditto ditto;

  UpdateUnchangedValuesBad(this.ditto);

  Future<void> saveUserPreferences(String userId, Map<String, dynamic> prefs) async {
    print('❌ Saving preferences without checking changes...');

    // ❌ BAD: Always UPDATE all preference fields
    await ditto.store.execute(
      '''UPDATE userPreferences
         SET theme = :theme,
             language = :language,
             notifications = :notifications,
             privacy = :privacy,
             updatedAt = :updatedAt
         WHERE userId = :userId''',
      arguments: {
        'userId': userId,
        'theme': prefs['theme'],
        'language': prefs['language'],
        'notifications': prefs['notifications'],
        'privacy': prefs['privacy'],
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ All preferences updated');

    // 🚨 PROBLEM:
    // - User changed 'theme' only
    // - But language, notifications, privacy all synced too
    // - Should check which fields actually changed
  }

  Future<void> autosaveDocument(String documentId, String content) async {
    print('❌ Autosaving document every 30s...');

    // ❌ BAD: Autosave without checking if content changed
    await ditto.store.execute(
      '''UPDATE documents
         SET content = :content,
             lastSaved = :timestamp
         WHERE _id = :documentId''',
      arguments: {
        'documentId': documentId,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ Document autosaved');

    // 🚨 PROBLEMS:
    // - Autosave timer runs every 30 seconds
    // - Creates delta even if user didn't type anything
    // - 120 deltas per hour, even with no changes
    // - Should check if content actually changed
  }
}

// ============================================================================
// ANTI-PATTERN 6: Multiple UPDATEs Instead of Batch
// ============================================================================

/// ❌ BAD: Multiple separate UPDATEs for related fields
class MultipleSeparateUpdatesBad {
  final Ditto ditto;

  MultipleSeparateUpdatesBad(this.ditto);

  Future<void> updateUserProfile(
    String userId,
    String name,
    String email,
    String bio,
  ) async {
    print('❌ Updating profile with multiple separate UPDATEs...');

    // ❌ BAD: 3 separate UPDATEs (3 deltas)
    await ditto.store.execute(
      'UPDATE users SET name = :name WHERE _id = :userId',
      arguments: {'userId': userId, 'name': name},
    );
    print('  ❌ Delta 1: name updated');

    await ditto.store.execute(
      'UPDATE users SET email = :email WHERE _id = :userId',
      arguments: {'userId': userId, 'email': email},
    );
    print('  ❌ Delta 2: email updated');

    await ditto.store.execute(
      'UPDATE users SET bio = :bio WHERE _id = :userId',
      arguments: {'userId': userId, 'bio': bio},
    );
    print('  ❌ Delta 3: bio updated');

    print('  ❌ Created 3 deltas (should be 1)');

    // 🚨 PROBLEMS:
    // - 3 deltas instead of 1
    // - 3x more sync traffic
    // - 3x more processing on receiving devices
    // - Should batch into single UPDATE
  }

  Future<void> updateOrderFields(String orderId) async {
    print('❌ Updating order with multiple UPDATEs...');

    // ❌ BAD: Multiple UPDATEs in sequence
    await ditto.store.execute(
      'UPDATE orders SET status = :status WHERE _id = :orderId',
      arguments: {'orderId': orderId, 'status': 'processing'},
    );

    await ditto.store.execute(
      'UPDATE orders SET processedAt = :timestamp WHERE _id = :orderId',
      arguments: {
        'orderId': orderId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    await ditto.store.execute(
      'UPDATE orders SET processorId = :processorId WHERE _id = :orderId',
      arguments: {'orderId': orderId, 'processorId': 'processor_1'},
    );

    print('  ❌ Created 3 deltas for single logical operation');

    // 🚨 PROBLEM:
    // - Single "process order" operation creates 3 deltas
    // - Other devices may see intermediate states
    // - Should be single UPDATE with all fields
  }
}

// ============================================================================
// ANTI-PATTERN 7: Timestamp Updates on Every Operation
// ============================================================================

/// ❌ BAD: Always update timestamp, even for queries
class UnnecessaryTimestampsBad {
  final Ditto ditto;

  UnnecessaryTimestampsBad(this.ditto);

  Future<void> getUserProfile(String userId) async {
    print('❌ Querying user profile...');

    // Query user
    final result = await ditto.store.execute(
      'SELECT * FROM users WHERE _id = :userId',
      arguments: {'userId': userId},
    );

    if (result.items.isEmpty) return;

    // ❌ BAD: Update lastAccessed timestamp on every read
    await ditto.store.execute(
      'UPDATE users SET lastAccessed = :timestamp WHERE _id = :userId',
      arguments: {
        'userId': userId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ lastAccessed timestamp updated (creates delta on every read)');

    // 🚨 PROBLEMS:
    // - Every profile view creates a delta
    // - User views profile 50 times = 50 deltas
    // - Should throttle to max once per session or hour
  }

  Future<void> logEvent(String userId, String eventType) async {
    print('❌ Logging event with user update...');

    // Insert event
    await ditto.store.execute(
      '''INSERT INTO events (
        _id, userId, eventType, timestamp
      ) VALUES (
        :eventId, :userId, :eventType, :timestamp
      )''',
      arguments: {
        'eventId': 'event_${DateTime.now().millisecondsSinceEpoch}',
        'userId': userId,
        'eventType': eventType,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // ❌ BAD: Also update user's lastEventAt
    await ditto.store.execute(
      'UPDATE users SET lastEventAt = :timestamp WHERE _id = :userId',
      arguments: {
        'userId': userId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ❌ Event logged AND user.lastEventAt updated');

    // 🚨 PROBLEM:
    // - Every event (100s per session) updates user document
    // - 100s of user deltas per session
    // - User document constantly syncing
    // - Should aggregate or throttle timestamp updates
  }
}

// ============================================================================
// Performance Impact Summary
// ============================================================================

void printPerformanceImpact() {
  print('❌ Performance Impact of Unnecessary Deltas:');
  print('');
  print('Bandwidth Waste Examples:');
  print('  • No value check: 10x more sync traffic');
  print('  • DO UPDATE instead of LOCAL_DIFF: 5-10x larger payloads');
  print('  • Full document replacement: 100x larger than field update');
  print('  • No throttling: 60-3,600x more deltas (GPS, sliders)');
  print('  • Multiple UPDATEs: 3-10x more deltas');
  print('');
  print('Real-World Impact:');
  print('  • User profile update: 5 KB instead of 50 bytes (100x)');
  print('  • GPS tracking: 360 MB/hour instead of 3.6 MB (100x)');
  print('  • Chat typing indicator: 30 KB/min instead of 600 bytes (50x)');
  print('  • Document autosave: 120 deltas/hour instead of 0-5 (24x+)');
  print('');
  print('Consequences:');
  print('  • Slow sync on cellular networks');
  print('  • Battery drain from constant sync');
  print('  • Data plan overage charges');
  print('  • Degraded user experience');
  print('  • Increased cloud sync costs');
}
