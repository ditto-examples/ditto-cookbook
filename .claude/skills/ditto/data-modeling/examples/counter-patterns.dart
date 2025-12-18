// ============================================================================
// Counter Patterns (PN_INCREMENT and COUNTER Type)
// ============================================================================
//
// This example demonstrates distributed counter patterns in Ditto using
// PN_INCREMENT operator and the new COUNTER type (Ditto 4.14.0+) to avoid
// lost updates from concurrent increments.
//
// SDK VERSION AWARENESS:
// - **Ditto <4.14.0**: Use PN_INCREMENT BY operator (legacy PN_COUNTER CRDT)
// - **Ditto 4.14.0+**: Use COUNTER type (recommended for new implementations)
//
// PATTERNS DEMONSTRATED:
// 1. ❌ SET with read-increment-write (lost updates)
// 2. ✅ PN_INCREMENT for distributed counters (all versions)
// 3. ✅ COUNTER type with INCREMENT BY (Ditto 4.14.0+)
// 4. ✅ COUNTER type with RESTART WITH (Ditto 4.14.0+)
// 5. ✅ COUNTER type with RESTART (Ditto 4.14.0+)
// 6. ✅ Like counters with PN_INCREMENT
// 7. ✅ Inventory counters with PN_INCREMENT and COUNTER type
// 8. ✅ Decrement using negative values
// 9. ✅ Multiple counter fields in single document
// 10. ✅ Counter initialization patterns
//
// WHY USE COUNTER OPERATIONS:
// - Guarantees correct count even with concurrent increments
// - No lost updates (all increments preserved during merge)
// - Works offline (increments queued, applied during sync)
// - Based on CRDT (Conflict-free Replicated Data Type)
// - COUNTER type (4.14.0+) adds RESTART WITH and RESTART operations
//
// WHEN TO USE COUNTER OPERATIONS:
// - Like/unlike counts
// - View counts
// - Inventory adjustments (stock in/out)
// - Vote tallies
// - Session metrics
// - Any counter that multiple devices modify concurrently
//
// WHEN TO USE COUNTER TYPE (4.14.0+) OVER PN_INCREMENT:
// - Need to set counter to specific value (RESTART WITH)
// - Need to reset counter to zero (RESTART)
// - Want explicit type declaration in schema
// - Inventory recalibration after physical count
// - Administrative resets (policy enforcement)
//
// WHEN NOT TO USE COUNTER OPERATIONS:
// - Non-counter fields (use field-level UPDATE instead)
// - Values that should be set absolutely without merge (use SET)
// - Counters that require exact sequential ordering (use events instead)
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN: SET with Read-Increment-Write
// ============================================================================

/// ❌ BAD: Read current count, increment, write back (lost updates)
Future<void> antiPattern_ReadIncrementWrite(Ditto ditto, String postId) async {
  print('❌ Read-increment-write pattern (loses concurrent increments):');

  // Device A: Read count, increment, write
  final resultA = await ditto.store.execute(
    'SELECT likeCount FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  final countA = (resultA.items.first.value['likeCount'] as num?)?.toInt() ?? 0;
  final newCountA = countA + 1; // Increment from 10 to 11

  // Device B: Read count, increment, write (almost simultaneously)
  final resultB = await ditto.store.execute(
    'SELECT likeCount FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  final countB = (resultB.items.first.value['likeCount'] as num?)?.toInt() ?? 0;
  final newCountB = countB + 1; // Increment from 10 to 11

  // Both devices write back their incremented values
  await ditto.store.execute(
    'UPDATE posts SET likeCount = :count WHERE _id = :postId',
    arguments: {'postId': postId, 'count': newCountA},
  );
  await ditto.store.execute(
    'UPDATE posts SET likeCount = :count WHERE _id = :postId',
    arguments: {'postId': postId, 'count': newCountB},
  );

  // 🚨 RESULT: Last-write-wins conflict
  // Both devices read 10, incremented to 11, wrote 11
  // Expected: 12 (10 + 2 increments)
  // Actual: 11 (one increment lost)

  print('  Expected likeCount: 12 (10 + 2 increments)');
  print('  Actual likeCount: 11 (one increment lost due to last-write-wins)');
  print('  ❌ Lost update: Counter is incorrect');
}

// ============================================================================
// RECOMMENDED PATTERN: PN_INCREMENT for Concurrent Safety
// ============================================================================

/// ✅ GOOD: Use PN_INCREMENT for distributed counter
Future<void> incrementLikeCount(Ditto ditto, String postId) async {
  // Increment like count using PN_INCREMENT
  await ditto.store.execute(
    '''
    UPDATE posts
    APPLY likeCount PN_INCREMENT BY 1.0
    WHERE _id = :postId
    ''',
    arguments: {'postId': postId},
  );

  print('✅ PN_INCREMENT: Increment guaranteed to be preserved');

  // ✅ BENEFIT: Even if multiple devices increment simultaneously,
  // all increments merge correctly without lost updates
}

/// Demonstrates concurrent increments with PN_INCREMENT
Future<void> demonstrateConcurrentIncrements(Ditto ditto, String postId) async {
  print('✅ Concurrent PN_INCREMENT demonstration:');

  // Initial state: likeCount = 10
  await ditto.store.execute(
    'UPDATE posts SET likeCount = :count WHERE _id = :postId',
    arguments: {'postId': postId, 'count': 10},
  );

  // Device A: Increment
  await ditto.store.execute(
    'UPDATE posts APPLY likeCount PN_INCREMENT BY 1.0 WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  print('  Device A: Incremented likeCount (+1)');

  // Device B: Increment (simultaneously)
  await ditto.store.execute(
    'UPDATE posts APPLY likeCount PN_INCREMENT BY 1.0 WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  print('  Device B: Incremented likeCount (+1)');

  // Device C: Increment (simultaneously)
  await ditto.store.execute(
    'UPDATE posts APPLY likeCount PN_INCREMENT BY 1.0 WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  print('  Device C: Incremented likeCount (+1)');

  // Query final count
  final result = await ditto.store.execute(
    'SELECT likeCount FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );

  if (result.items.isNotEmpty) {
    final finalCount = result.items.first.value['likeCount'];
    print('  Final likeCount: $finalCount (10 + 3 = 13)');
    print('  ✅ All increments preserved (no lost updates)');
  }
}

// ============================================================================
// PATTERN: Decrement Using Negative PN_INCREMENT
// ============================================================================

/// ✅ GOOD: Decrement counter using negative PN_INCREMENT
Future<void> decrementLikeCount(Ditto ditto, String postId) async {
  // Decrement like count (user unliked)
  await ditto.store.execute(
    '''
    UPDATE posts
    APPLY likeCount PN_INCREMENT BY -1.0
    WHERE _id = :postId
    ''',
    arguments: {'postId': postId},
  );

  print('✅ PN_INCREMENT BY -1.0: Decrement guaranteed to be preserved');

  // ✅ BENEFIT: Decrement merges correctly with concurrent operations
  // If Device A increments while Device B decrements, both operations merge
}

/// Toggle like/unlike pattern
Future<void> toggleLike(
  Ditto ditto,
  String postId,
  String userId,
  bool isCurrentlyLiked,
) async {
  if (isCurrentlyLiked) {
    // User is unliking
    await ditto.store.execute(
      'UPDATE posts APPLY likeCount PN_INCREMENT BY -1.0 WHERE _id = :postId',
      arguments: {'postId': postId},
    );

    // Remove from user's likes
    await ditto.store.execute(
      'DELETE FROM likes WHERE userId = :userId AND postId = :postId',
      arguments: {'userId': userId, 'postId': postId},
    );

    print('✅ Unliked: Counter decremented, like record deleted');
  } else {
    // User is liking
    await ditto.store.execute(
      'UPDATE posts APPLY likeCount PN_INCREMENT BY 1.0 WHERE _id = :postId',
      arguments: {'postId': postId},
    );

    // Add to user's likes
    await ditto.store.execute(
      '''
      INSERT INTO likes (_id, userId, postId, createdAt)
      VALUES (:id, :userId, :postId, :createdAt)
      ''',
      arguments: {
        'id': 'like_${userId}_$postId',
        'userId': userId,
        'postId': postId,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    print('✅ Liked: Counter incremented, like record created');
  }
}

// ============================================================================
// PATTERN: Inventory Counters
// ============================================================================

/// ✅ GOOD: Inventory adjustments with PN_INCREMENT
Future<void> adjustInventory(
  Ditto ditto,
  String productId,
  double quantityChange,
  String reason,
) async {
  // Adjust stock quantity (can be positive or negative)
  await ditto.store.execute(
    '''
    UPDATE products
    APPLY stockQuantity PN_INCREMENT BY :change,
          lastAdjustedAt = :timestamp
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': productId,
      'change': quantityChange,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // Log adjustment event (for audit trail)
  await ditto.store.execute(
    '''
    INSERT INTO inventoryEvents (
      _id, productId, quantityChange, reason, timestamp
    )
    VALUES (:id, :productId, :change, :reason, :timestamp)
    ''',
    arguments: {
      'id': 'event_${DateTime.now().millisecondsSinceEpoch}',
      'productId': productId,
      'change': quantityChange,
      'reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Inventory adjusted: ${quantityChange > 0 ? "+" : ""}$quantityChange ($reason)');

  // ✅ BENEFIT: Multiple warehouses can adjust inventory concurrently
  // All adjustments merge correctly (no lost stock changes)
}

/// Inventory operations examples
Future<void> inventoryOperations(Ditto ditto, String productId) async {
  // Receive shipment (add stock)
  await adjustInventory(ditto, productId, 100, 'Shipment received');

  // Process sale (remove stock)
  await adjustInventory(ditto, productId, -5, 'Sale completed');

  // Inventory correction (could be + or -)
  await adjustInventory(ditto, productId, -2, 'Physical count adjustment');

  // Query current stock
  final result = await ditto.store.execute(
    'SELECT stockQuantity FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  if (result.items.isNotEmpty) {
    final stock = result.items.first.value['stockQuantity'];
    print('✅ Current stock: $stock units');
  }
}

// ============================================================================
// PATTERN: Multiple Counter Fields
// ============================================================================

/// ✅ GOOD: Document with multiple independent counters
Future<void> updateEngagementMetrics(Ditto ditto, String postId) async {
  // Update multiple counters in single statement
  await ditto.store.execute(
    '''
    UPDATE posts
    APPLY likeCount PN_INCREMENT BY 1.0,
          viewCount PN_INCREMENT BY 1.0,
          shareCount PN_INCREMENT BY 0.0,
          updatedAt = :timestamp
    WHERE _id = :postId
    ''',
    arguments: {
      'postId': postId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Multiple counters: likeCount +1, viewCount +1 (concurrent-safe)');

  // ✅ BENEFIT: Each counter merges independently
  // Device A can increment likeCount while Device B increments viewCount
  // Both operations merge correctly
}

/// Track detailed engagement metrics
Future<void> trackEngagement(
  Ditto ditto,
  String postId, {
  bool viewed = false,
  bool liked = false,
  bool shared = false,
  bool commented = false,
}) async {
  // Build dynamic increment values
  final viewIncrement = viewed ? 1.0 : 0.0;
  final likeIncrement = liked ? 1.0 : 0.0;
  final shareIncrement = shared ? 1.0 : 0.0;
  final commentIncrement = commented ? 1.0 : 0.0;

  await ditto.store.execute(
    '''
    UPDATE posts
    APPLY viewCount PN_INCREMENT BY :viewInc,
          likeCount PN_INCREMENT BY :likeInc,
          shareCount PN_INCREMENT BY :shareInc,
          commentCount PN_INCREMENT BY :commentInc
    WHERE _id = :postId
    ''',
    arguments: {
      'postId': postId,
      'viewInc': viewIncrement,
      'likeInc': likeIncrement,
      'shareInc': shareIncrement,
      'commentInc': commentIncrement,
    },
  );

  print('✅ Engagement tracked: view=$viewed, like=$liked, share=$shared, comment=$commented');
}

// ============================================================================
// PATTERN: Counter Initialization
// ============================================================================

/// ✅ GOOD: Initialize counters when creating document
Future<void> createPostWithCounters(Ditto ditto, String postId) async {
  await ditto.store.execute(
    '''
    INSERT INTO posts (
      _id, authorId, content,
      likeCount, viewCount, shareCount, commentCount,
      createdAt
    )
    VALUES (
      :postId, :authorId, :content,
      :likeCount, :viewCount, :shareCount, :commentCount,
      :createdAt
    )
    ''',
    arguments: {
      'postId': postId,
      'authorId': 'user_123',
      'content': 'This is my first post!',
      // Initialize all counters to 0
      'likeCount': 0,
      'viewCount': 0,
      'shareCount': 0,
      'commentCount': 0,
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Post created with initialized counters (all at 0)');

  // ✅ BENEFIT: Counters initialized to known state
  // Subsequent PN_INCREMENT operations work correctly
}

/// Handle missing counter fields (defensive programming)
Future<void> safeIncrementCounter(Ditto ditto, String postId) async {
  // Query to check if counter exists
  final result = await ditto.store.execute(
    'SELECT likeCount FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );

  if (result.items.isEmpty) {
    print('⚠️ Post not found');
    return;
  }

  final likeCount = result.items.first.value['likeCount'];

  if (likeCount == null) {
    // Counter field doesn't exist, initialize it first
    await ditto.store.execute(
      'UPDATE posts SET likeCount = :count WHERE _id = :postId',
      arguments: {'postId': postId, 'count': 0},
    );
    print('✅ Initialized missing likeCount field to 0');
  }

  // Now safe to increment
  await ditto.store.execute(
    'UPDATE posts APPLY likeCount PN_INCREMENT BY 1.0 WHERE _id = :postId',
    arguments: {'postId': postId},
  );

  print('✅ Counter incremented safely');
}

// ============================================================================
// PATTERN: Vote Tallies with PN_INCREMENT
// ============================================================================

/// ✅ GOOD: Upvote/downvote counters
Future<void> vote(
  Ditto ditto,
  String commentId,
  String userId,
  String voteType, // 'up' or 'down'
) async {
  // Check if user already voted
  final existingVoteResult = await ditto.store.execute(
    'SELECT voteType FROM votes WHERE commentId = :commentId AND userId = :userId',
    arguments: {'commentId': commentId, 'userId': userId},
  );

  if (existingVoteResult.items.isNotEmpty) {
    final existingVote = existingVoteResult.items.first.value['voteType'] as String;

    if (existingVote == voteType) {
      // User clicking same vote again (remove vote)
      await ditto.store.execute(
        'DELETE FROM votes WHERE commentId = :commentId AND userId = :userId',
        arguments: {'commentId': commentId, 'userId': userId},
      );

      // Decrement counter
      final decrement = voteType == 'up' ? -1.0 : 1.0; // Downvote is negative, so negate
      await ditto.store.execute(
        'UPDATE comments APPLY score PN_INCREMENT BY :change WHERE _id = :commentId',
        arguments: {'commentId': commentId, 'change': decrement},
      );

      print('✅ Vote removed: ${voteType}vote count adjusted');
    } else {
      // User switching vote (up to down or down to up)
      await ditto.store.execute(
        'UPDATE votes SET voteType = :voteType WHERE commentId = :commentId AND userId = :userId',
        arguments: {'commentId': commentId, 'userId': userId, 'voteType': voteType},
      );

      // Adjust counter (remove old vote, add new vote)
      final change = voteType == 'up' ? 2.0 : -2.0; // Switching is +2 or -2
      await ditto.store.execute(
        'UPDATE comments APPLY score PN_INCREMENT BY :change WHERE _id = :commentId',
        arguments: {'commentId': commentId, 'change': change},
      );

      print('✅ Vote switched: score adjusted by $change');
    }
  } else {
    // New vote
    await ditto.store.execute(
      '''
      INSERT INTO votes (_id, commentId, userId, voteType, createdAt)
      VALUES (:id, :commentId, :userId, :voteType, :createdAt)
      ''',
      arguments: {
        'id': 'vote_${userId}_$commentId',
        'commentId': commentId,
        'userId': userId,
        'voteType': voteType,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );

    // Increment counter
    final increment = voteType == 'up' ? 1.0 : -1.0;
    await ditto.store.execute(
      'UPDATE comments APPLY score PN_INCREMENT BY :change WHERE _id = :commentId',
      arguments: {'commentId': commentId, 'change': increment},
    );

    print('✅ New vote: ${voteType}vote count incremented');
  }
}

// ============================================================================
// PATTERN: Counter Queries and Sorting
// ============================================================================

/// Query and sort by counter values
Future<void> queryByCounters(Ditto ditto) async {
  // Get most liked posts
  final mostLikedResult = await ditto.store.execute(
    'SELECT * FROM posts ORDER BY likeCount DESC LIMIT 10',
  );

  print('✅ Most liked posts:');
  for (final item in mostLikedResult.items) {
    final post = item.value;
    print('  ${post['content']} (${post['likeCount']} likes)');
  }

  // Get trending posts (multiple counters)
  final trendingResult = await ditto.store.execute(
    '''
    SELECT * FROM posts
    ORDER BY likeCount DESC, commentCount DESC, viewCount DESC
    LIMIT 10
    ''',
  );

  print('✅ Trending posts (sorted by engagement):');
  for (final item in trendingResult.items) {
    final post = item.value;
    print('  ${post['content']} (${post['likeCount']} likes, ${post['commentCount']} comments)');
  }

  // Filter posts by minimum like count
  final popularResult = await ditto.store.execute(
    'SELECT * FROM posts WHERE likeCount >= :minLikes ORDER BY createdAt DESC',
    arguments: {'minLikes': 100},
  );

  print('✅ Popular posts (100+ likes): ${popularResult.items.length}');
}

// ============================================================================
// NEW PATTERN: COUNTER Type (Ditto 4.14.0+)
// ============================================================================

/// ✅ GOOD: Use COUNTER type for counters with settable capabilities
Future<void> counterType_IncrementPattern(
    Ditto ditto, String productId) async {
  print('✅ COUNTER type with INCREMENT BY (Ditto 4.14.0+):');

  // Increment counter using COUNTER type
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (viewCount COUNTER)
    APPLY viewCount INCREMENT BY 1
    WHERE _id = :productId
    ''',
    arguments: {'productId': productId},
  );

  print('✅ View count incremented using COUNTER type');
}

/// ✅ GOOD: COUNTER type with RESTART WITH operation
Future<void> counterType_RestartWithPattern(
    Ditto ditto, String productId, int physicalCount) async {
  print('✅ COUNTER type with RESTART WITH (Ditto 4.14.0+):');

  // Set counter to specific value (last-write-wins)
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (stock_count COUNTER)
    APPLY stock_count RESTART WITH :physicalCount
    WHERE _id = :productId
    ''',
    arguments: {'productId': productId, 'physicalCount': physicalCount},
  );

  print('✅ Inventory recalibrated to $physicalCount units');
}

/// ✅ GOOD: COUNTER type with RESTART operation
Future<void> counterType_RestartPattern(Ditto ditto, String postId) async {
  print('✅ COUNTER type with RESTART (Ditto 4.14.0+):');

  // Reset counter to zero
  await ditto.store.execute(
    '''
    UPDATE COLLECTION posts (likes COUNTER)
    APPLY likes RESTART
    WHERE _id = :postId
    ''',
    arguments: {'postId': postId},
  );

  print('✅ Like count reset to zero');
}

// ============================================================================
// USE CASE: Inventory Management with COUNTER Type
// ============================================================================

/// ✅ GOOD: Inventory management with recalibration
class InventoryManager {
  final Ditto ditto;

  InventoryManager(this.ditto);

  /// Adjust inventory as sales occur (distributed increments)
  Future<void> adjustInventory(String productId, int change) async {
    print('✅ Adjusting inventory by $change units:');

    await ditto.store.execute(
      '''
      UPDATE COLLECTION products (stock_count COUNTER)
      APPLY stock_count INCREMENT BY :change
      WHERE _id = :productId
      ''',
      arguments: {'productId': productId, 'change': change},
    );

    print('✅ Inventory adjusted');
  }

  /// Recalibrate inventory after physical count (exact value)
  Future<void> recalibrateInventory(String productId, int physicalCount) async {
    print('✅ Recalibrating inventory to physical count: $physicalCount');

    await ditto.store.execute(
      '''
      UPDATE COLLECTION products (stock_count COUNTER)
      APPLY stock_count RESTART WITH :physicalCount
      WHERE _id = :productId
      ''',
      arguments: {'productId': productId, 'physicalCount': physicalCount},
    );

    print('✅ Inventory recalibrated to $physicalCount units');
  }
}

// ============================================================================
// USE CASE: Like Counts with Administrative Reset
// ============================================================================

/// ✅ GOOD: Like counts with administrative control
class LikeManager {
  final Ditto ditto;

  LikeManager(this.ditto);

  /// User likes a post (distributed increment)
  Future<void> likePost(String postId) async {
    await ditto.store.execute(
      '''
      UPDATE COLLECTION posts (likes COUNTER)
      APPLY likes INCREMENT BY 1
      WHERE _id = :postId
      ''',
      arguments: {'postId': postId},
    );

    print('✅ Post liked');
  }

  /// Admin resets likes due to policy violation
  Future<void> adminResetLikes(String postId) async {
    print('⚠️ Admin resetting like count due to policy violation');

    await ditto.store.execute(
      '''
      UPDATE COLLECTION posts (likes COUNTER)
      APPLY likes RESTART
      WHERE _id = :postId
      ''',
      arguments: {'postId': postId},
    );

    print('✅ Like count reset to zero by admin');
  }
}

// ============================================================================
// USE CASE: Session Metrics with Initialization
// ============================================================================

/// ✅ GOOD: Session metrics with explicit initialization
class SessionManager {
  final Ditto ditto;

  SessionManager(this.ditto);

  /// Initialize session counter to baseline
  Future<void> initializeSession(String sessionId) async {
    print('✅ Initializing session counter:');

    await ditto.store.execute(
      '''
      UPDATE COLLECTION sessions (request_count COUNTER)
      APPLY request_count RESTART WITH 0
      WHERE _id = :sessionId
      ''',
      arguments: {'sessionId': sessionId},
    );

    print('✅ Session initialized with request_count = 0');
  }

  /// Track requests (distributed increment)
  Future<void> trackRequest(String sessionId) async {
    await ditto.store.execute(
      '''
      UPDATE COLLECTION sessions (request_count COUNTER)
      APPLY request_count INCREMENT BY 1
      WHERE _id = :sessionId
      ''',
      arguments: {'sessionId': sessionId},
    );

    print('✅ Request tracked');
  }
}

// ============================================================================
// COMPARISON: PN_INCREMENT vs COUNTER Type
// ============================================================================

/// Comparison between PN_INCREMENT and COUNTER type
Future<void> compareCounterApproaches(Ditto ditto, String productId) async {
  print('📊 Comparison: PN_INCREMENT vs COUNTER Type\n');

  // PN_INCREMENT approach (all versions)
  print('1. PN_INCREMENT BY operator (all versions):');
  await ditto.store.execute(
    'UPDATE products APPLY viewCount PN_INCREMENT BY 1.0 WHERE _id = :productId',
    arguments: {'productId': productId},
  );
  print('   ✅ Increment: PN_INCREMENT BY 1.0');
  print('   ❌ No settable operations available\n');

  // COUNTER type approach (4.14.0+)
  print('2. COUNTER type (Ditto 4.14.0+):');
  await ditto.store.execute(
    '''
    UPDATE COLLECTION products (viewCount COUNTER)
    APPLY viewCount INCREMENT BY 1
    WHERE _id = :productId
    ''',
    arguments: {'productId': productId},
  );
  print('   ✅ Increment: INCREMENT BY 1');
  print('   ✅ Set value: RESTART WITH 100');
  print('   ✅ Reset: RESTART');
  print('   ✅ Explicit type declaration: (viewCount COUNTER)\n');

  print('When to use COUNTER type over PN_INCREMENT:');
  print('- Need to set counter to specific value (RESTART WITH)');
  print('- Need to reset counter to zero (RESTART)');
  print('- Want explicit type declaration in schema');
  print('- Inventory recalibration scenarios');
  print('- Administrative reset requirements');
}
