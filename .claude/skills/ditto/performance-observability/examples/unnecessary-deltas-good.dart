// SDK Version: 4.12+
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Preventing Unnecessary Delta Creation (Correct Patterns)
// ============================================================================
//
// This example demonstrates how to prevent unnecessary delta creation in Ditto,
// which reduces sync traffic, saves bandwidth, and improves performance.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Value-change check before UPDATE
// 2. ✅ DO UPDATE_LOCAL_DIFF (SDK 4.12+)
// 3. ✅ Field-level updates instead of full document
// 4. ✅ Conditional updates only when needed
// 5. ✅ Batch updates with single transaction
// 6. ✅ Timestamp-based update skipping
// 7. ✅ Delta reduction strategies
//
// WHY PREVENT UNNECESSARY DELTAS:
// - Reduces sync traffic across mesh
// - Saves bandwidth (critical for cellular)
// - Improves battery life
// - Reduces storage overhead
// - Faster sync for actual changes
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Value-Change Check Before UPDATE
// ============================================================================

/// ✅ GOOD: Check if value actually changed before updating
class ValueChangeCheck {
  final Ditto ditto;

  ValueChangeCheck(this.ditto);

  Future<void> updateUserStatus(String userId, String newStatus) async {
    print('📝 Updating user status...');

    // ✅ STEP 1: Query current value
    final result = await ditto.store.execute(
      'SELECT status FROM users WHERE _id = :userId',
      arguments: {'userId': userId},
    );

    if (result.items.isEmpty) {
      print('❌ User not found');
      return;
    }

    final doc = result.items.first.value;
    final currentStatus = doc['status'] as String?;

    // ✅ STEP 2: Check if value actually changed
    if (currentStatus == newStatus) {
      print('  ⏭️ Status unchanged ("$currentStatus"), skipping UPDATE');
      print('  ✅ No delta created, no sync traffic');
      return;
    }

    // ✅ STEP 3: Only update if value changed
    await ditto.store.execute(
      'UPDATE users SET status = :status WHERE _id = :userId',
      arguments: {'userId': userId, 'status': newStatus},
    );

    print('  ✅ Status updated: "$currentStatus" → "$newStatus"');
    print('  Delta created and will sync');
  }
}

// ============================================================================
// PATTERN 2: DO UPDATE_LOCAL_DIFF (SDK 4.12+)
// ============================================================================

/// ✅ GOOD: DO UPDATE_LOCAL_DIFF only syncs changed fields
class LocalDiffUpdate {
  final Ditto ditto;

  LocalDiffUpdate(this.ditto);

  Future<void> updateUserProfile(
    String userId,
    String? name,
    String? email,
    String? phone,
  ) async {
    print('📝 Updating user profile with DO UPDATE_LOCAL_DIFF...');

    // ✅ DO UPDATE_LOCAL_DIFF: Only changed fields sync
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE users
         SET name = :name,
             email = :email,
             phone = :phone,
             updatedAt = :updatedAt
         WHERE _id = :userId''',
      arguments: {
        'userId': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Profile updated with LOCAL_DIFF');
    print('  Only modified fields will sync (not entire document)');

    // BENEFIT:
    // - If only 'name' changed, only 'name' field syncs
    // - Significantly reduces sync payload
    // - Works seamlessly with CRDT merge
  }

  Future<void> updateUserWithoutDiff(
    String userId,
    String? name,
    String? email,
    String? phone,
  ) async {
    print('📝 Updating user profile WITHOUT DO UPDATE_LOCAL_DIFF...');

    // ❌ DO UPDATE: Entire document syncs (less efficient)
    await ditto.store.execute(
      '''DO UPDATE
         UPDATE users
         SET name = :name,
             email = :email,
             phone = :phone,
             updatedAt = :updatedAt
         WHERE _id = :userId''',
      arguments: {
        'userId': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );

    print('  ⚠️ Profile updated with DO UPDATE');
    print('  Entire document will sync (even unchanged fields)');
  }
}

// ============================================================================
// PATTERN 3: Field-Level Updates Instead of Full Document
// ============================================================================

/// ✅ GOOD: Update only specific fields
class FieldLevelUpdate {
  final Ditto ditto;

  FieldLevelUpdate(this.ditto);

  Future<void> incrementViewCount(String postId) async {
    print('📝 Incrementing view count (field-level)...');

    // ✅ GOOD: Update only viewCount field
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE posts
         APPLY viewCount PN_INCREMENT BY 1.0
         WHERE _id = :postId''',
      arguments: {'postId': postId},
    );

    print('  ✅ View count incremented (only viewCount field syncs)');

    // BENEFIT:
    // - Only viewCount field syncs
    // - Title, content, author, etc. NOT synced
    // - Minimal bandwidth usage
  }

  Future<void> updateLastActiveTimestamp(String userId) async {
    print('📝 Updating lastActiveAt timestamp...');

    // ✅ Query current timestamp
    final result = await ditto.store.execute(
      'SELECT lastActiveAt FROM users WHERE _id = :userId',
      arguments: {'userId': userId},
    );

    if (result.items.isEmpty) return;

    final doc = result.items.first.value;
    final lastActiveAt = doc['lastActiveAt'] as String?;
    final now = DateTime.now().toIso8601String();

    // ✅ Check if timestamp significantly changed (avoid frequent updates)
    if (lastActiveAt != null) {
      final lastActive = DateTime.parse(lastActiveAt);
      final diff = DateTime.now().difference(lastActive);

      if (diff.inMinutes < 5) {
        print('  ⏭️ Last active recent (<5 min), skipping UPDATE');
        return;
      }
    }

    // ✅ Update only lastActiveAt field
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE users
         SET lastActiveAt = :timestamp
         WHERE _id = :userId''',
      arguments: {'userId': userId, 'timestamp': now},
    );

    print('  ✅ lastActiveAt updated (only timestamp field syncs)');
  }
}

// ============================================================================
// PATTERN 4: Conditional Updates Only When Needed
// ============================================================================

/// ✅ GOOD: Update only when condition met
class ConditionalUpdate {
  final Ditto ditto;

  ConditionalUpdate(this.ditto);

  Future<void> updateTaskStatusIfChanged(String taskId, String newStatus) async {
    print('📝 Conditionally updating task status...');

    // ✅ Single query with WHERE clause (efficient)
    final result = await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE tasks
         SET status = :newStatus,
             statusChangedAt = :timestamp
         WHERE _id = :taskId AND status != :newStatus''',
      arguments: {
        'taskId': taskId,
        'newStatus': newStatus,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    if (result.mutatedDocumentIDs.isEmpty) {
      print('  ⏭️ Status unchanged, no UPDATE performed');
      print('  ✅ No delta created');
    } else {
      print('  ✅ Status updated (delta created only because status changed)');
    }

    // BENEFIT:
    // - Conditional UPDATE in single query (no read-then-write)
    // - No delta if condition not met
    // - Efficient and atomic
  }

  Future<void> incrementCounterIfBelowLimit(String documentId, int limit) async {
    print('📝 Conditionally incrementing counter...');

    // ✅ Increment only if below limit
    final result = await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE counters
         APPLY count PN_INCREMENT BY 1.0
         WHERE _id = :id AND count < :limit''',
      arguments: {'id': documentId, 'limit': limit},
    );

    if (result.mutatedDocumentIDs.isEmpty) {
      print('  ⏭️ Counter at limit, no increment');
    } else {
      print('  ✅ Counter incremented');
    }
  }
}

// ============================================================================
// PATTERN 5: Batch Updates with Single Transaction (Non-Flutter)
// ============================================================================

/// ✅ GOOD: Batch related updates together (Non-Flutter platforms only)
class BatchUpdate {
  final Ditto ditto;

  BatchUpdate(this.ditto);

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    print('📝 Batch updating order status...');

    // ✅ Query current status first
    final result = await ditto.store.execute(
      'SELECT status FROM orders WHERE _id = :orderId',
      arguments: {'orderId': orderId},
    );

    if (result.items.isEmpty) return;

    final doc = result.items.first.value;
    final currentStatus = doc['status'] as String?;

    if (currentStatus == newStatus) {
      print('  ⏭️ Status unchanged, skipping batch update');
      return;
    }

    // ✅ Batch multiple related updates in single transaction
    // Note: This example shows the pattern, but transactions are NOT supported in Flutter
    // For Flutter, use sequential updates with careful ordering

    // Non-Flutter platforms can use:
    // await ditto.store.transaction(async (tx) => {
    //   await tx.execute('UPDATE orders SET status = :status WHERE _id = :orderId', {...});
    //   await tx.execute('INSERT INTO orderEvents (_id, orderId, eventType) VALUES (...)', {...});
    // }, ['orders', 'orderEvents']);

    // Flutter alternative:
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE orders
         SET status = :status,
             statusChangedAt = :timestamp
         WHERE _id = :orderId''',
      arguments: {
        'orderId': orderId,
        'status': newStatus,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    await ditto.store.execute(
      '''INSERT INTO orderEvents (
        _id, orderId, eventType, oldStatus, newStatus, timestamp
      ) VALUES (
        :eventId, :orderId, :eventType, :oldStatus, :newStatus, :timestamp
      )''',
      arguments: {
        'eventId': 'event_${DateTime.now().millisecondsSinceEpoch}',
        'orderId': orderId,
        'eventType': 'status_changed',
        'oldStatus': currentStatus,
        'newStatus': newStatus,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Order status and event created (2 deltas, both necessary)');
  }
}

// ============================================================================
// PATTERN 6: Timestamp-Based Update Skipping
// ============================================================================

/// ✅ GOOD: Skip frequent updates with timestamp throttling
class TimestampThrottling {
  final Ditto ditto;

  TimestampThrottling(this.ditto);

  Future<void> updateUserLocation(
    String userId,
    double latitude,
    double longitude,
  ) async {
    print('📍 Updating user location...');

    // ✅ Query last update timestamp
    final result = await ditto.store.execute(
      'SELECT lastLocationUpdate FROM users WHERE _id = :userId',
      arguments: {'userId': userId},
    );

    if (result.items.isNotEmpty) {
      final doc = result.items.first.value;
      final lastUpdate = doc['lastLocationUpdate'] as String?;

      if (lastUpdate != null) {
        final lastUpdateTime = DateTime.parse(lastUpdate);
        final diff = DateTime.now().difference(lastUpdateTime);

        // ✅ Throttle: Only update if >30 seconds since last update
        if (diff.inSeconds < 30) {
          print('  ⏭️ Location updated recently (<30s), skipping UPDATE');
          print('  ✅ No delta created (throttled)');
          return;
        }
      }
    }

    // ✅ Update location with new timestamp
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE users
         SET latitude = :lat,
             longitude = :lng,
             lastLocationUpdate = :timestamp
         WHERE _id = :userId''',
      arguments: {
        'userId': userId,
        'lat': latitude,
        'lng': longitude,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Location updated (throttled to 30s intervals)');

    // BENEFIT:
    // - Reduces location update frequency
    // - Saves bandwidth for high-frequency GPS updates
    // - Still provides reasonably fresh location data
  }

  Future<void> updatePresenceStatus(String userId, String status) async {
    print('👤 Updating presence status...');

    // ✅ Debounce: Only update if status actually changed
    final result = await ditto.store.execute(
      'SELECT presenceStatus, lastPresenceUpdate FROM users WHERE _id = :userId',
      arguments: {'userId': userId},
    );

    if (result.items.isNotEmpty) {
      final doc = result.items.first.value;
      final currentStatus = doc['presenceStatus'] as String?;
      final lastUpdate = doc['lastPresenceUpdate'] as String?;

      // ✅ Skip if status unchanged
      if (currentStatus == status) {
        print('  ⏭️ Presence status unchanged ("$status"), skipping UPDATE');
        return;
      }

      // ✅ Throttle rapid status changes
      if (lastUpdate != null) {
        final lastUpdateTime = DateTime.parse(lastUpdate);
        final diff = DateTime.now().difference(lastUpdateTime);

        if (diff.inSeconds < 5) {
          print('  ⏭️ Presence updated very recently (<5s), skipping UPDATE');
          return;
        }
      }
    }

    // ✅ Update presence status
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE users
         SET presenceStatus = :status,
             lastPresenceUpdate = :timestamp
         WHERE _id = :userId''',
      arguments: {
        'userId': userId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Presence status updated (throttled and debounced)');
  }
}

// ============================================================================
// PATTERN 7: Delta Reduction Strategies
// ============================================================================

/// ✅ GOOD: Strategies to minimize delta creation
class DeltaReductionStrategies {
  final Ditto ditto;

  DeltaReductionStrategies(this.ditto);

  /// Strategy 1: Coalesce multiple field updates
  Future<void> coalesceUpdates(String userId, Map<String, dynamic> updates) async {
    print('📝 Coalescing multiple field updates...');

    // ✅ Instead of multiple UPDATEs, batch into single UPDATE
    final setClause = updates.keys.map((key) => '$key = :$key').join(', ');

    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE users
         SET $setClause
         WHERE _id = :userId''',
      arguments: {'userId': userId, ...updates},
    );

    print('  ✅ ${updates.length} fields updated in single UPDATE (1 delta)');
    print('  Better than ${updates.length} separate UPDATEs (${updates.length} deltas)');
  }

  /// Strategy 2: Use meaningful threshold for numeric updates
  Future<void> updateTemperatureIfSignificant(String sensorId, double newTemp) async {
    print('🌡️ Updating temperature reading...');

    // ✅ Query current temperature
    final result = await ditto.store.execute(
      'SELECT temperature FROM sensors WHERE _id = :sensorId',
      arguments: {'sensorId': sensorId},
    );

    if (result.items.isNotEmpty) {
      final doc = result.items.first.value;
      final currentTemp = doc['temperature'] as double?;

      if (currentTemp != null) {
        // ✅ Only update if change is significant (>0.5°C)
        final diff = (newTemp - currentTemp).abs();

        if (diff < 0.5) {
          print('  ⏭️ Temperature change insignificant (<0.5°C), skipping UPDATE');
          return;
        }
      }
    }

    // ✅ Update temperature
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE sensors
         SET temperature = :temp,
             lastReading = :timestamp
         WHERE _id = :sensorId''',
      arguments: {
        'sensorId': sensorId,
        'temp': newTemp,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('  ✅ Temperature updated (significant change)');
  }

  /// Strategy 3: Aggregate before persisting
  Future<void> aggregateMetricsBeforeUpdate(String userId) async {
    print('📊 Aggregating metrics before update...');

    // ✅ Collect metrics in memory (not Ditto)
    final metrics = <String, int>{};

    // Simulate collecting metrics over time
    metrics['pageViews'] = 42;
    metrics['clicks'] = 15;
    metrics['sessions'] = 3;

    // ✅ Single UPDATE with aggregated data
    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE userMetrics
         APPLY pageViews PN_INCREMENT BY :pageViews,
               clicks PN_INCREMENT BY :clicks,
               sessions PN_INCREMENT BY :sessions
         WHERE userId = :userId''',
      arguments: {'userId': userId, ...metrics},
    );

    print('  ✅ Metrics updated in single batch (1 delta instead of 60)');
    print('  Avoided 60 individual UPDATEs (42 + 15 + 3)');
  }
}

// ============================================================================
// Complete Example: Optimized Update Pattern
// ============================================================================

/// Production-ready update pattern minimizing delta creation
class OptimizedUpdateManager {
  final Ditto ditto;

  OptimizedUpdateManager(this.ditto);

  Future<void> updateUserProfile({
    required String userId,
    String? name,
    String? email,
    String? bio,
    String? avatarUrl,
  }) async {
    print('📝 Optimized user profile update...');

    // Step 1: Query current values
    final result = await ditto.store.execute(
      'SELECT name, email, bio, avatarUrl FROM users WHERE _id = :userId',
      arguments: {'userId': userId},
    );

    if (result.items.isEmpty) {
      print('❌ User not found');
      return;
    }

    final doc = result.items.first.value;

    // Step 2: Build map of only changed fields
    final updates = <String, dynamic>{};

    if (name != null && doc['name'] != name) {
      updates['name'] = name;
    }
    if (email != null && doc['email'] != email) {
      updates['email'] = email;
    }
    if (bio != null && doc['bio'] != bio) {
      updates['bio'] = bio;
    }
    if (avatarUrl != null && doc['avatarUrl'] != avatarUrl) {
      updates['avatarUrl'] = avatarUrl;
    }

    // Step 3: Skip if no changes
    if (updates.isEmpty) {
      print('  ⏭️ No fields changed, skipping UPDATE');
      print('  ✅ No delta created');
      return;
    }

    // Step 4: Update only changed fields
    final setClause = updates.keys.map((key) => '$key = :$key').join(', ');

    await ditto.store.execute(
      '''DO UPDATE_LOCAL_DIFF
         UPDATE users
         SET $setClause, updatedAt = :updatedAt
         WHERE _id = :userId''',
      arguments: {
        'userId': userId,
        'updatedAt': DateTime.now().toIso8601String(),
        ...updates,
      },
    );

    print('  ✅ Updated ${updates.length} field(s): ${updates.keys.join(', ')}');
    print('  Delta created only for changed fields');
  }
}

// ============================================================================
// Best Practices Summary
// ============================================================================

void printBestPractices() {
  print('✅ Delta Reduction Best Practices:');
  print('');
  print('DO:');
  print('  ✓ Check if value changed before UPDATE');
  print('  ✓ Use DO UPDATE_LOCAL_DIFF (SDK 4.12+)');
  print('  ✓ Update only specific fields (not full document)');
  print('  ✓ Use conditional UPDATEs (WHERE clause)');
  print('  ✓ Throttle high-frequency updates');
  print('  ✓ Batch related updates together');
  print('  ✓ Use meaningful thresholds for numeric data');
  print('  ✓ Aggregate before persisting');
  print('');
  print('DON\'T:');
  print('  ✗ UPDATE without checking current value');
  print('  ✗ Use DO UPDATE for every update');
  print('  ✗ Update full document when only 1 field changed');
  print('  ✗ Update on every minor change');
  print('  ✗ Create deltas for unchanged values');
  print('');
  print('BENEFITS:');
  print('  • Reduced sync traffic (up to 90% reduction)');
  print('  • Lower bandwidth usage');
  print('  • Better battery life');
  print('  • Faster sync');
  print('  • Reduced storage overhead');
}
