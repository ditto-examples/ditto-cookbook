// ============================================================================
// Over-Normalization Anti-Patterns (Requires Multiple Queries)
// ============================================================================
//
// This example demonstrates problems that arise from over-normalizing data
// in Ditto, which lacks JOIN support and requires sequential queries.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Normalized order requiring multiple queries
// 2. ❌ Sequential query waterfall pattern
// 3. ❌ Reference chains requiring N+1 queries
// 4. ❌ Missing snapshot semantics for historical data
// 5. ❌ Over-normalized data causing offline unavailability
// 6. ❌ Complex aggregation requiring many queries
// 7. ❌ Performance degradation from query multiplication
//
// WHY NORMALIZATION IS PROBLEMATIC IN DITTO:
// - No JOIN support in DQL (must query sequentially)
// - Each query has latency and potential failure points
// - Offline scenarios: Referenced data might not be available
// - Historical records: Data changes over time, losing context
//
// SOLUTION: Denormalize strategically (see denormalization-good.dart)
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: Over-Normalized Order (Multiple Queries Required)
// ============================================================================

/// ❌ BAD: Order only stores references, requires multiple queries
Future<void> antiPattern1_NormalizedOrder(Ditto ditto, String orderId) async {
  // Normalized order structure (only references)
  await ditto.store.execute(
    '''
    INSERT INTO orders (_id, customerId, status, createdAt)
    VALUES (:orderId, :customerId, :status, :createdAt)
    ''',
    arguments: {
      'orderId': orderId,
      'customerId': 'cust_123',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  // Order items in separate collection (normalized)
  await ditto.store.execute(
    '''
    INSERT INTO orderItems (_id, orderId, productId, quantity)
    VALUES (:itemId, :orderId, :productId, :quantity)
    ''',
    arguments: {
      'itemId': 'item_001',
      'orderId': orderId,
      'productId': 'prod_laptop_001',
      'quantity': 1,
    },
  );

  await ditto.store.execute(
    '''
    INSERT INTO orderItems (_id, orderId, productId, quantity)
    VALUES (:itemId, :orderId, :productId, :quantity)
    ''',
    arguments: {
      'itemId': 'item_002',
      'orderId': orderId,
      'productId': 'prod_mouse_001',
      'quantity': 2,
    },
  );

  // ❌ PROBLEM: Displaying order requires sequential queries (no JOIN)
  print('❌ Displaying order requires multiple sequential queries:');

  // Query 1: Get order
  final orderResult = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );
  if (orderResult.items.isEmpty) {
    print('Order not found');
    return;
  }
  final order = orderResult.items.first.value;
  print('  Query 1: Retrieved order ${order['_id']}');

  // Query 2: Get customer info
  final customerResult = await ditto.store.execute(
    'SELECT * FROM customers WHERE _id = :customerId',
    arguments: {'customerId': order['customerId']},
  );
  if (customerResult.items.isEmpty) {
    print('  ⚠️ Customer not found (offline issue?)');
    return;
  }
  final customer = customerResult.items.first.value;
  print('  Query 2: Retrieved customer ${customer['name']}');

  // Query 3: Get order items
  final itemsResult = await ditto.store.execute(
    'SELECT * FROM orderItems WHERE orderId = :orderId',
    arguments: {'orderId': orderId},
  );
  print('  Query 3: Retrieved ${itemsResult.items.length} order items');

  // Query 4, 5, ...: Get product details for each item (N+1 query problem!)
  var totalQueries = 3;
  for (final itemDoc in itemsResult.items) {
    final item = itemDoc.value;
    totalQueries++;
    final productResult = await ditto.store.execute(
      'SELECT * FROM products WHERE _id = :productId',
      arguments: {'productId': item['productId']},
    );
    if (productResult.items.isEmpty) {
      print('  ⚠️ Product ${item['productId']} not found (data inconsistency!)');
      continue;
    }
    final product = productResult.items.first.value;
    print('  Query $totalQueries: Retrieved product ${product['name']}');
  }

  print('❌ Total queries: $totalQueries (should be 1 with denormalization)');

  // 🚨 ISSUES:
  // - Multiple network round-trips (latency)
  // - Multiple potential failure points
  // - Offline: Referenced data might not be synced
  // - Complex error handling for each query
}

// ============================================================================
// ANTI-PATTERN 2: Sequential Query Waterfall
// ============================================================================

/// ❌ BAD: Post → Author → Comments → Comment Authors (waterfall)
Future<void> antiPattern2_QueryWaterfall(Ditto ditto, String postId) async {
  print('❌ Query waterfall to display post with comments:');

  // Query 1: Get post
  final postResult = await ditto.store.execute(
    'SELECT * FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  if (postResult.items.isEmpty) return;
  final post = postResult.items.first.value;
  print('  Query 1: Retrieved post ${post['_id']}');

  // Query 2: Get post author
  final authorResult = await ditto.store.execute(
    'SELECT * FROM users WHERE _id = :userId',
    arguments: {'userId': post['authorId']},
  );
  if (authorResult.items.isEmpty) {
    print('  ⚠️ Post author not found');
    return;
  }
  final author = authorResult.items.first.value;
  print('  Query 2: Retrieved post author ${author['displayName']}');

  // Query 3: Get comments
  final commentsResult = await ditto.store.execute(
    'SELECT * FROM comments WHERE postId = :postId ORDER BY createdAt DESC',
    arguments: {'postId': postId},
  );
  print('  Query 3: Retrieved ${commentsResult.items.length} comments');

  // Query 4, 5, ...: Get each comment author (N+1 query problem)
  var totalQueries = 3;
  for (final commentDoc in commentsResult.items) {
    final comment = commentDoc.value;
    totalQueries++;
    final commentAuthorResult = await ditto.store.execute(
      'SELECT * FROM users WHERE _id = :userId',
      arguments: {'userId': comment['authorId']},
    );
    if (commentAuthorResult.items.isEmpty) {
      print('  ⚠️ Comment author ${comment['authorId']} not found');
      continue;
    }
    final commentAuthor = commentAuthorResult.items.first.value;
    print('  Query $totalQueries: Retrieved comment author ${commentAuthor['displayName']}');
  }

  print('❌ Total queries: $totalQueries (exponential growth with more comments)');

  // 🚨 ISSUES:
  // - Query count grows linearly with comment count
  // - Slow page load (each query has latency)
  // - Poor offline experience (missing author data breaks UI)
  // - Error handling complexity
}

// ============================================================================
// ANTI-PATTERN 3: Reference Chain (Nested Lookups)
// ============================================================================

/// ❌ BAD: Team → Department → Company → Address (reference chain)
Future<void> antiPattern3_ReferenceChain(Ditto ditto, String teamId) async {
  print('❌ Reference chain requiring sequential lookups:');

  // Query 1: Get team
  final teamResult = await ditto.store.execute(
    'SELECT * FROM teams WHERE _id = :teamId',
    arguments: {'teamId': teamId},
  );
  if (teamResult.items.isEmpty) return;
  final team = teamResult.items.first.value;
  print('  Query 1: Retrieved team ${team['name']}');

  // Query 2: Get department
  final deptResult = await ditto.store.execute(
    'SELECT * FROM departments WHERE _id = :deptId',
    arguments: {'deptId': team['departmentId']},
  );
  if (deptResult.items.isEmpty) {
    print('  ⚠️ Department not found');
    return;
  }
  final dept = deptResult.items.first.value;
  print('  Query 2: Retrieved department ${dept['name']}');

  // Query 3: Get company
  final companyResult = await ditto.store.execute(
    'SELECT * FROM companies WHERE _id = :companyId',
    arguments: {'companyId': dept['companyId']},
  );
  if (companyResult.items.isEmpty) {
    print('  ⚠️ Company not found');
    return;
  }
  final company = companyResult.items.first.value;
  print('  Query 3: Retrieved company ${company['name']}');

  // Query 4: Get company address
  final addressResult = await ditto.store.execute(
    'SELECT * FROM addresses WHERE _id = :addressId',
    arguments: {'addressId': company['addressId']},
  );
  if (addressResult.items.isEmpty) {
    print('  ⚠️ Address not found');
    return;
  }
  final address = addressResult.items.first.value;
  print('  Query 4: Retrieved address ${address['city']}');

  print('❌ Total queries: 4 (should be 1 with selective denormalization)');
  print('   Full path: ${company['name']} / ${dept['name']} / ${team['name']} (${address['city']})');

  // 🚨 ISSUES:
  // - Deep reference chains are fragile
  // - One missing document breaks the entire chain
  // - Latency multiplied by chain depth
  // - Complex error recovery
}

// ============================================================================
// ANTI-PATTERN 4: Lost Historical Context
// ============================================================================

/// ❌ BAD: Invoice references customer/products, loses historical pricing
Future<void> antiPattern4_LostHistory(Ditto ditto, String invoiceId) async {
  // Create invoice with only references (no snapshot)
  await ditto.store.execute(
    '''
    INSERT INTO invoices (_id, invoiceNumber, customerId, createdAt)
    VALUES (:id, :number, :customerId, :createdAt)
    ''',
    arguments: {
      'id': invoiceId,
      'number': 'INV-2024-001',
      'customerId': 'cust_456',
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  // Invoice items with product references only
  await ditto.store.execute(
    '''
    INSERT INTO invoiceItems (_id, invoiceId, productId, quantity)
    VALUES (:id, :invoiceId, :productId, :quantity)
    ''',
    arguments: {
      'id': 'invitem_001',
      'invoiceId': invoiceId,
      'productId': 'prod_service_001',
      'quantity': 40, // 40 hours of service
    },
  );

  // Simulate: Product price changes after invoice creation
  await ditto.store.execute(
    '''
    UPDATE products
    SET price = :newPrice, updatedAt = :updatedAt
    WHERE _id = :productId
    ''',
    arguments: {
      'productId': 'prod_service_001',
      'newPrice': 175.00, // Increased from $150 to $175
      'updatedAt': DateTime.now().toIso8601String(),
    },
  );

  // ❌ PROBLEM: Retrieving invoice shows CURRENT price, not historical price
  final invoiceResult = await ditto.store.execute(
    'SELECT * FROM invoices WHERE _id = :id',
    arguments: {'id': invoiceId},
  );
  if (invoiceResult.items.isEmpty) return;
  final invoice = invoiceResult.items.first.value;

  final itemsResult = await ditto.store.execute(
    'SELECT * FROM invoiceItems WHERE invoiceId = :id',
    arguments: {'id': invoiceId},
  );

  for (final itemDoc in itemsResult.items) {
    final item = itemDoc.value;
    final productResult = await ditto.store.execute(
      'SELECT * FROM products WHERE _id = :id',
      arguments: {'id': item['productId']},
    );
    if (productResult.items.isNotEmpty) {
      final product = productResult.items.first.value;
      final total = (product['price'] as num) * (item['quantity'] as int);
      print('❌ Invoice shows: ${product['name']} x${item['quantity']} @ \$${product['price']} = \$${total}');
      print('   (This is CURRENT price, not the price at invoice time!)');
    }
  }

  // 🚨 ISSUES:
  // - Invoice total changes when product prices change
  // - Historical accuracy lost (accounting problem!)
  // - Legal issues (invoice must show actual charged amount)
  // - Auditing impossible (can't reconstruct past state)
}

// ============================================================================
// ANTI-PATTERN 5: Offline Data Unavailability
// ============================================================================

/// ❌ BAD: Cart references products, unavailable offline
Future<void> antiPattern5_OfflineUnavailability(Ditto ditto, String cartId) async {
  // Cart stores only product IDs (normalized)
  await ditto.store.execute(
    '''
    INSERT INTO carts (_id, userId, items)
    VALUES (:id, :userId, :items)
    ''',
    arguments: {
      'id': cartId,
      'userId': 'user_789',
      'items': {
        'item_1': {'productId': 'prod_laptop_001', 'quantity': 1},
        'item_2': {'productId': 'prod_mouse_001', 'quantity': 2},
      },
    },
  );

  // ❌ PROBLEM: Displaying cart offline requires product data
  final cartResult = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :id',
    arguments: {'id': cartId},
  );
  if (cartResult.items.isEmpty) return;
  final cart = cartResult.items.first.value;

  print('❌ Displaying cart offline:');
  final items = cart['items'] as Map<String, dynamic>;
  for (final item in items.values) {
    final productId = item['productId'];
    final quantity = item['quantity'];

    // Query product details
    final productResult = await ditto.store.execute(
      'SELECT * FROM products WHERE _id = :id',
      arguments: {'id': productId},
    );

    if (productResult.items.isEmpty) {
      print('  ⚠️ Product $productId not available offline!');
      print('     Can\'t display name, price, or image');
      print('     User sees: "Unknown product (ID: $productId) x$quantity"');
    } else {
      final product = productResult.items.first.value;
      print('  ✓ ${product['name']} x$quantity');
    }
  }

  // 🚨 ISSUES:
  // - Cart UI broken if products collection not synced
  // - Subscription management: Must subscribe to products + cart
  // - Storage: Must keep product catalog synced for cart to work
  // - Poor offline UX (can't show cart contents)
}

// ============================================================================
// ANTI-PATTERN 6: Complex Aggregation Requiring Many Queries
// ============================================================================

/// ❌ BAD: Dashboard metrics require querying multiple collections
Future<void> antiPattern6_ComplexAggregation(Ditto ditto, String userId) async {
  print('❌ Dashboard metrics requiring multiple queries:');

  // Metric 1: Total posts by user
  final postsResult = await ditto.store.execute(
    'SELECT COUNT(*) as count FROM posts WHERE authorId = :userId',
    arguments: {'userId': userId},
  );
  final postCount = postsResult.items.first.value['count'];
  print('  Query 1: Post count = $postCount');

  // Metric 2: Total likes (must query likes collection)
  final likesResult = await ditto.store.execute(
    '''
    SELECT COUNT(*) as count FROM likes
    WHERE postId IN (SELECT _id FROM posts WHERE authorId = :userId)
    ''',
    arguments: {'userId': userId},
  );
  // ❌ Note: Subquery might not be efficient or supported
  print('  Query 2: Total likes (complex subquery)');

  // Metric 3: Total comments (must query comments collection)
  final commentsResult = await ditto.store.execute(
    '''
    SELECT COUNT(*) as count FROM comments
    WHERE postId IN (SELECT _id FROM posts WHERE authorId = :userId)
    ''',
    arguments: {'userId': userId},
  );
  print('  Query 3: Total comments (complex subquery)');

  // Metric 4: Follower count (must query followers collection)
  final followersResult = await ditto.store.execute(
    'SELECT COUNT(*) as count FROM followers WHERE followingUserId = :userId',
    arguments: {'userId': userId},
  );
  final followerCount = followersResult.items.first.value['count'];
  print('  Query 4: Follower count = $followerCount');

  print('❌ Total queries: 4 (should be 1 with denormalized user stats)');

  // 🚨 ISSUES:
  // - Dashboard slow to load (multiple queries)
  // - Counts can be stale or inconsistent
  // - Offline: Metrics unavailable
  // - No atomic consistency across counts
}

// ============================================================================
// ANTI-PATTERN 7: N+1 Query Problem in Lists
// ============================================================================

/// ❌ BAD: Listing posts with author info requires N+1 queries
Future<void> antiPattern7_NPlusOneQuery(Ditto ditto) async {
  print('❌ N+1 query problem in post feed:');

  // Query 1: Get posts
  final postsResult = await ditto.store.execute(
    'SELECT * FROM posts ORDER BY createdAt DESC LIMIT 20',
  );
  print('  Query 1: Retrieved ${postsResult.items.length} posts');

  // Query 2, 3, ..., N+1: Get author for each post
  var totalQueries = 1;
  for (final postDoc in postsResult.items) {
    final post = postDoc.value;
    totalQueries++;

    final authorResult = await ditto.store.execute(
      'SELECT * FROM users WHERE _id = :userId',
      arguments: {'userId': post['authorId']},
    );

    if (authorResult.items.isEmpty) {
      print('  Query $totalQueries: Author ${post['authorId']} not found');
    } else {
      final author = authorResult.items.first.value;
      print('  Query $totalQueries: Retrieved author ${author['displayName']}');
    }
  }

  print('❌ Total queries: $totalQueries (1 + N) where N = number of posts');

  // 🚨 ISSUES:
  // - Query count grows with list size (20 posts = 21 queries)
  // - Feed loading is very slow
  // - Offline: Missing author data breaks feed
  // - Same author queried multiple times (inefficient)
}

// ============================================================================
// ANTI-PATTERN 8: Performance Degradation from Query Multiplication
// ============================================================================

/// ❌ BAD: Rendering list of orders with full details
Future<void> antiPattern8_PerformanceDegradation(Ditto ditto) async {
  print('❌ Performance test: Rendering 50 orders');

  final startTime = DateTime.now();

  // Query orders
  final ordersResult = await ditto.store.execute(
    'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50',
  );

  var totalQueries = 1;

  for (final orderDoc in ordersResult.items) {
    final order = orderDoc.value;

    // Query customer (1 query per order)
    totalQueries++;
    await ditto.store.execute(
      'SELECT * FROM customers WHERE _id = :id',
      arguments: {'id': order['customerId']},
    );

    // Query order items (1 query per order)
    totalQueries++;
    final itemsResult = await ditto.store.execute(
      'SELECT * FROM orderItems WHERE orderId = :id',
      arguments: {'id': order['_id']},
    );

    // Query products (1 query per item)
    for (final itemDoc in itemsResult.items) {
      final item = itemDoc.value;
      totalQueries++;
      await ditto.store.execute(
        'SELECT * FROM products WHERE _id = :id',
        arguments: {'id': item['productId']},
      );
    }
  }

  final endTime = DateTime.now();
  final duration = endTime.difference(startTime);

  print('❌ Total queries: $totalQueries');
  print('   Duration: ${duration.inMilliseconds}ms');
  print('   Average: ${duration.inMilliseconds / totalQueries}ms per query');
  print('   (With denormalization: 1 query, ~${duration.inMilliseconds / totalQueries}ms total)');

  // 🚨 ISSUES:
  // - Exponential query growth (50 orders × 3+ queries each = 150+ queries)
  // - Unacceptable load time for users
  // - Bandwidth waste (same products queried repeatedly)
  // - Battery drain on mobile devices
}
