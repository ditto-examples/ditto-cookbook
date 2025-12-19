// SDK Version: 4.12+
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Field-Level Updates (Recommended Pattern)
// ============================================================================
//
// This example demonstrates field-level UPDATE patterns in Ditto to minimize
// merge conflicts and reduce sync overhead.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Field-level UPDATE statements
// 2. ✅ DO UPDATE_LOCAL_DIFF usage (SDK 4.12+)
// 3. ✅ Value-change checks before UPDATE
// 4. ✅ Delta sync optimization
// 5. ✅ Nested field updates
// 6. ✅ Multiple field updates in single statement
// 7. ✅ Concurrent field updates (no conflicts)
//
// WHY FIELD-LEVEL UPDATES:
// - Minimizes merge conflicts (different fields can update concurrently)
// - Reduces sync overhead (only changed fields transmitted)
// - Preserves concurrent updates from other devices
// - Better performance for large documents
//
// DO UPDATE vs DO UPDATE_LOCAL_DIFF (SDK 4.12+):
// - DO UPDATE: Transmits all fields in document (default)
// - DO UPDATE_LOCAL_DIFF: Only transmits fields that actually changed
// - Use DO UPDATE_LOCAL_DIFF to minimize bandwidth and sync traffic
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Field-Level Updates (Basic)
// ============================================================================

/// ✅ GOOD: Update specific fields only
Future<void> updateUserProfile(Ditto ditto, String userId) async {
  // Update only the displayName field
  await ditto.store.execute(
    '''
    UPDATE users
    SET displayName = :displayName
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      'displayName': 'John Smith',
    },
  );

  // ✅ BENEFIT: Concurrent updates to other fields don't conflict
  // Device A can update displayName while Device B updates email
  // Both changes merge successfully

  print('✅ Field-level update: Only displayName transmitted and synced');
}

/// Update multiple specific fields in single statement
Future<void> updateUserSettings(Ditto ditto, String userId) async {
  // Update multiple fields atomically
  await ditto.store.execute(
    '''
    UPDATE users
    SET settings.theme = :theme,
        settings.language = :language,
        settings.notifications = :notifications,
        updatedAt = :updatedAt
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      'theme': 'dark',
      'language': 'en',
      'notifications': true,
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Multiple fields updated in one statement
  // Other fields (displayName, email, etc.) untouched
  // Concurrent updates to untouched fields merge successfully

  print('✅ Multi-field update: Only specified fields synced');
}

// ============================================================================
// PATTERN 2: DO UPDATE_LOCAL_DIFF (SDK 4.12+)
// ============================================================================

/// ✅ GOOD: Use DO UPDATE_LOCAL_DIFF to sync only changed fields
Future<void> updateWithLocalDiff(Ditto ditto, String productId) async {
  // Update product description (SDK 4.12+)
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE products
    SET description = :description,
        updatedAt = :updatedAt
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'description': 'High-performance laptop with 32GB RAM and 1TB SSD',
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Only description and updatedAt fields transmitted
  // If description value didn't actually change, Ditto skips sync
  // Reduces bandwidth usage significantly

  print('✅ DO UPDATE_LOCAL_DIFF: Only changed fields synced');
}

/// ❌ BAD: DO UPDATE without LOCAL_DIFF (transmits all fields)
Future<void> updateWithoutLocalDiff(Ditto ditto, String productId) async {
  // Traditional UPDATE (transmits entire document)
  await ditto.store.execute(
    '''
    DO UPDATE
    UPDATE products
    SET description = :description
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'description': 'High-performance laptop with 32GB RAM and 1TB SSD',
    },
  );

  // ❌ PROBLEM: Entire document transmitted, even unchanged fields
  // Wastes bandwidth, especially for large documents
  // Increases sync overhead and battery usage

  print('❌ DO UPDATE: All fields transmitted (inefficient)');
}

// ============================================================================
// PATTERN 3: Value-Change Checks Before UPDATE
// ============================================================================

/// ✅ GOOD: Check if value changed before updating
Future<void> updateWithValueCheck(
  Ditto ditto,
  String taskId,
  String newStatus,
) async {
  // Step 1: Read current value
  final result = await ditto.store.execute(
    'SELECT status FROM tasks WHERE _id = :taskId',
    arguments: {'taskId': taskId},
  );

  if (result.items.isEmpty) {
    print('Task not found');
    return;
  }

  final currentStatus = result.items.first.value['status'] as String;

  // Step 2: Only update if value actually changed
  if (currentStatus == newStatus) {
    print('✅ Status unchanged, skipping UPDATE (no unnecessary delta)');
    return;
  }

  // Step 3: Perform update
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE tasks
    SET status = :status,
        statusChangedAt = :timestamp
    WHERE _id = :taskId
    ''',
    arguments: {
      'taskId': taskId,
      'status': newStatus,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Status changed from "$currentStatus" to "$newStatus", syncing delta');

  // ✅ BENEFIT: Prevents unnecessary deltas when value hasn't changed
  // Reduces sync traffic and merge overhead
  // Important for frequently-called update functions
}

/// Example: Checkbox toggle with value check
Future<void> toggleTaskDone(Ditto ditto, String taskId) async {
  // Read current done status
  final result = await ditto.store.execute(
    'SELECT done FROM tasks WHERE _id = :taskId',
    arguments: {'taskId': taskId},
  );

  if (result.items.isEmpty) return;

  final currentDone = result.items.first.value['done'] as bool? ?? false;
  final newDone = !currentDone;

  // Update with new value
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE tasks
    SET done = :done,
        doneAt = :timestamp
    WHERE _id = :taskId
    ''',
    arguments: {
      'taskId': taskId,
      'done': newDone,
      'timestamp': newDone ? DateTime.now().toIso8601String() : null,
    },
  );

  print('✅ Task ${newDone ? "marked done" : "marked undone"}');

  // ✅ BENEFIT: Toggle logic ensures value always changes
  // No unnecessary UPDATEs if user clicks checkbox twice quickly
}

// ============================================================================
// PATTERN 4: Nested Field Updates
// ============================================================================

/// ✅ GOOD: Update nested fields individually
Future<void> updateNestedFields(Ditto ditto, String orderId) async {
  // Update specific nested field
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE orders
    SET shippingAddress.city = :city,
        shippingAddress.zipCode = :zipCode,
        updatedAt = :updatedAt
    WHERE _id = :orderId
    ''',
    arguments: {
      'orderId': orderId,
      'city': 'San Francisco',
      'zipCode': '94103',
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Only city and zipCode synced
  // Other address fields (street, state, country) untouched
  // Concurrent updates to other address fields merge successfully

  print('✅ Nested field update: Only city and zipCode synced');
}

/// Update deeply nested fields
Future<void> updateDeeplyNested(Ditto ditto, String userId) async {
  // Update nested preference
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE users
    SET preferences.notifications.email.marketing = :value
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      'value': false,
    },
  );

  // ✅ BENEFIT: Field-level granularity even for deep nesting
  // Only the specific preference flag synced

  print('✅ Deep nested update: Only marketing preference synced');
}

// ============================================================================
// PATTERN 5: Concurrent Field Updates (No Conflicts)
// ============================================================================

/// Demonstrates concurrent updates to different fields
Future<void> demonstrateConcurrentUpdates(Ditto ditto, String productId) async {
  print('✅ Concurrent field updates (no conflicts):');

  // Device A: Update price
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE products
    SET price = :price
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'price': 899.99,
    },
  );
  print('  Device A: Updated price to \$899.99');

  // Device B: Update stock quantity (almost simultaneously)
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE products
    SET stockQuantity = :quantity
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'quantity': 150,
    },
  );
  print('  Device B: Updated stock quantity to 150');

  // ✅ RESULT: Both updates merge successfully
  // Final state: price = $899.99, stockQuantity = 150
  // No last-write-wins conflict because different fields updated

  final result = await ditto.store.execute(
    'SELECT * FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  if (result.items.isNotEmpty) {
    final product = result.items.first.value;
    print('  Final state: price=\$${product['price']}, stockQuantity=${product['stockQuantity']}');
    print('  ✅ Both updates preserved (field-level merge)');
  }
}

// ============================================================================
// PATTERN 6: Partial Document Updates for Large Documents
// ============================================================================

/// ✅ GOOD: Update single field in large document
Future<void> updateLargeDocument(Ditto ditto, String reportId) async {
  // Imagine: report document is 4MB (large JSON data)
  // Only need to update status field

  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE reports
    SET status = :status,
        completedAt = :completedAt
    WHERE _id = :reportId
    ''',
    arguments: {
      'reportId': reportId,
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Only status and completedAt transmitted
  // Without field-level updates, entire 4MB document would sync
  // DO UPDATE_LOCAL_DIFF dramatically reduces bandwidth

  print('✅ Large document update: Only 2 fields synced (not entire 4MB)');
}

// ============================================================================
// PATTERN 7: Timestamp Updates with Field-Level Precision
// ============================================================================

/// ✅ GOOD: Update timestamps independently
Future<void> updateTimestamps(Ditto ditto, String documentId) async {
  // Update lastViewedAt without affecting lastEditedAt
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE documents
    SET lastViewedAt = :timestamp
    WHERE _id = :documentId
    ''',
    arguments: {
      'documentId': documentId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: View tracking doesn't conflict with concurrent edits
  // Device A viewing document while Device B edits: both updates merge

  print('✅ Timestamp update: Independent field merge');
}

/// Track multiple activity timestamps
Future<void> updateActivityTimestamps(Ditto ditto, String userId) async {
  // Update lastSeenAt timestamp
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE users
    SET lastSeenAt = :timestamp
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // Concurrent update from another action: Update lastActiveAt
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE users
    SET lastActiveAt = :timestamp
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Multiple timestamp fields can update independently
  // No conflicts between presence tracking and activity tracking

  print('✅ Multiple timestamps: Independent updates merged');
}

// ============================================================================
// PATTERN 8: Field-Level Updates with WHERE Conditions
// ============================================================================

/// ✅ GOOD: Conditional field updates
Future<void> conditionalFieldUpdate(Ditto ditto) async {
  // Update only tasks with specific status
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE tasks
    SET priority = :priority,
        priorityChangedAt = :timestamp
    WHERE status = :status AND assigneeId = :assigneeId
    ''',
    arguments: {
      'priority': 'high',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
      'assigneeId': 'user_123',
    },
  );

  // ✅ BENEFIT: Bulk field update with precise targeting
  // Only matched documents updated, only specified fields changed
  // Minimal sync overhead with DO UPDATE_LOCAL_DIFF

  print('✅ Conditional field update: Only matched tasks, only specified fields');
}

// ============================================================================
// PATTERN 9: Avoiding Full Document Replacement
// ============================================================================

/// ❌ BAD: Reading and writing entire document
Future<void> fullDocumentReplacement(Ditto ditto, String userId) async {
  // Read entire document
  final result = await ditto.store.execute(
    'SELECT * FROM users WHERE _id = :userId',
    arguments: {'userId': userId},
  );

  if (result.items.isEmpty) return;

  final user = Map<String, dynamic>.from(result.items.first.value);

  // Modify single field
  user['displayName'] = 'Jane Doe';

  // Write entire document back
  await ditto.store.execute(
    '''
    UPDATE users
    SET displayName = :displayName,
        email = :email,
        settings = :settings,
        preferences = :preferences,
        createdAt = :createdAt,
        updatedAt = :updatedAt
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      ...user,
    },
  );

  // ❌ PROBLEM: Entire document transmitted
  // Concurrent updates to other fields lost (last-write-wins)
  // Inefficient for large documents

  print('❌ Full document replacement: All fields transmitted');
}

/// ✅ GOOD: Field-level update only
Future<void> fieldLevelUpdate(Ditto ditto, String userId) async {
  // Update only the field that changed
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE users
    SET displayName = :displayName,
        updatedAt = :updatedAt
    WHERE _id = :userId
    ''',
    arguments: {
      'userId': userId,
      'displayName': 'Jane Doe',
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Only 2 fields transmitted
  // Concurrent updates to other fields preserved
  // Efficient even for large documents

  print('✅ Field-level update: Only 2 fields transmitted');
}

// ============================================================================
// PATTERN 10: Optimistic UI with Field-Level Updates
// ============================================================================

/// ✅ GOOD: Optimistic UI update with minimal sync
Future<void> optimisticUIUpdate(
  Ditto ditto,
  String postId,
  void Function(int) updateUI,
) async {
  // Step 1: Read current like count
  final result = await ditto.store.execute(
    'SELECT likeCount FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );

  if (result.items.isEmpty) return;

  final currentCount = (result.items.first.value['likeCount'] as num?)?.toInt() ?? 0;
  final newCount = currentCount + 1;

  // Step 2: Update UI optimistically (immediate feedback)
  updateUI(newCount);

  // Step 3: Persist to Ditto (field-level update)
  await ditto.store.execute(
    '''
    DO UPDATE_LOCAL_DIFF
    UPDATE posts
    APPLY likeCount PN_INCREMENT BY 1.0
    WHERE _id = :postId
    ''',
    arguments: {'postId': postId},
  );

  // ✅ BENEFIT: Fast UI response + minimal sync overhead
  // PN_INCREMENT ensures correct concurrent behavior
  // DO UPDATE_LOCAL_DIFF minimizes bandwidth

  print('✅ Optimistic UI: Instant feedback, efficient sync');
}
