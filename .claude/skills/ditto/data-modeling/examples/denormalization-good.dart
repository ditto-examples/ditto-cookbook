// ============================================================================
// Denormalization Patterns (Recommended for Ditto)
// ============================================================================
//
// This example demonstrates when and how to denormalize data in Ditto to
// avoid sequential queries, as Ditto does not support JOIN operations.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Embedded data pattern (order with items)
// 2. ✅ Denormalized product information
// 3. ✅ Single-query data access
// 4. ✅ Snapshot semantics for historical data
// 5. ✅ Selective denormalization (balance freshness vs convenience)
// 6. ✅ Denormalized aggregates (computed fields)
// 7. ✅ Reference + denormalized hybrid pattern
//
// WHY DENORMALIZATION IN DITTO:
// - No JOIN support in DQL
// - Sequential queries are expensive and error-prone
// - Offline-first: Minimize query complexity for reliability
// - Snapshot semantics: Historical records need point-in-time data
//
// WHEN TO DENORMALIZE:
// - One-to-many relationships viewed together frequently
// - Historical records (orders, invoices, snapshots)
// - Data that changes infrequently (product names, user profiles)
// - Performance-critical queries
//
// WHEN NOT TO DENORMALIZE:
// - Data that changes frequently and must be fresh
// - Large binary data (use attachments instead)
// - Data with complex update patterns across many documents
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: Embedded Order with Line Items
// ============================================================================

/// ✅ GOOD: Order document embeds all line items
/// Benefit: Single query gets complete order, snapshot semantics for history
Future<void> createOrderWithEmbeddedItems(Ditto ditto, String orderId) async {
  // Query product details for order items
  final laptopResult = await ditto.store.execute(
    'SELECT * FROM products WHERE _id = :id',
    arguments: {'id': 'prod_laptop_001'},
  );
  final mouseResult = await ditto.store.execute(
    'SELECT * FROM products WHERE _id = :id',
    arguments: {'id': 'prod_mouse_001'},
  );

  final laptop = laptopResult.items.first.value;
  final mouse = mouseResult.items.first.value;

  // Create order with denormalized product information
  await ditto.store.execute(
    '''
    INSERT INTO orders (_id, customerId, status, lineItems, totals, createdAt)
    VALUES (:orderId, :customerId, :status, :lineItems, :totals, :createdAt)
    ''',
    arguments: {
      'orderId': orderId,
      'customerId': 'cust_123',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      // Embed complete line item data (snapshot)
      'lineItems': {
        'item_1': {
          'productId': laptop['_id'],
          // Denormalize product details (snapshot at order time)
          'productName': laptop['name'],
          'productSku': laptop['sku'],
          'unitPrice': laptop['price'],
          'quantity': 1,
          'lineTotal': laptop['price'] * 1,
        },
        'item_2': {
          'productId': mouse['_id'],
          'productName': mouse['name'],
          'productSku': mouse['sku'],
          'unitPrice': mouse['price'],
          'quantity': 2,
          'lineTotal': mouse['price'] * 2,
        },
      },
      // Denormalized aggregates
      'totals': {
        'subtotal': (laptop['price'] as double) * 1 + (mouse['price'] as double) * 2,
        'tax': 0.0,
        'shipping': 0.0,
        'total': (laptop['price'] as double) * 1 + (mouse['price'] as double) * 2,
      },
    },
  );

  // ✅ BENEFIT: Retrieve complete order with single query
  final orderResult = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );

  if (orderResult.items.isNotEmpty) {
    final order = orderResult.items.first.value;
    // All data available without additional queries!
    print('Order ${order['_id']}:');
    print('  Customer: ${order['customerId']}');
    print('  Status: ${order['status']}');
    print('  Total: \$${order['totals']['total']}');

    final lineItems = order['lineItems'] as Map<String, dynamic>;
    print('  Line items: ${lineItems.length}');
    for (final item in lineItems.values) {
      print('    - ${item['productName']} x${item['quantity']} = \$${item['lineTotal']}');
    }
  }

  // ✅ SNAPSHOT SEMANTICS: Order preserves product info at purchase time
  // Even if product price changes later, order shows historical price
  print('✅ Order data is self-contained with snapshot semantics');
}

// ============================================================================
// PATTERN 2: User Profile with Denormalized Metadata
// ============================================================================

/// ✅ GOOD: Denormalize frequently-accessed user metadata
Future<void> createPostWithAuthorInfo(Ditto ditto, String postId) async {
  // Query author details
  final authorResult = await ditto.store.execute(
    'SELECT * FROM users WHERE _id = :userId',
    arguments: {'userId': 'user_123'},
  );

  if (authorResult.items.isEmpty) {
    print('User not found');
    return;
  }

  final author = authorResult.items.first.value;

  // Create post with denormalized author information
  await ditto.store.execute(
    '''
    INSERT INTO posts (_id, authorId, authorName, authorAvatar, content, createdAt)
    VALUES (:postId, :authorId, :authorName, :authorAvatar, :content, :createdAt)
    ''',
    arguments: {
      'postId': postId,
      'authorId': author['_id'],
      // Denormalize author display data
      'authorName': author['displayName'],
      'authorAvatar': author['avatarUrl'],
      // Post content
      'content': 'This is a great post about offline-first development!',
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Display posts without querying users collection
  final postsResult = await ditto.store.execute(
    'SELECT * FROM posts ORDER BY createdAt DESC LIMIT 10',
  );

  print('✅ Recent posts (no JOIN needed):');
  for (final item in postsResult.items) {
    final post = item.value;
    // Author name and avatar immediately available for UI
    print('  ${post['authorName']}: ${post['content']}');
  }

  // Note: Keep authorId reference for clicking through to full profile
}

// ============================================================================
// PATTERN 3: Comment with Nested Thread Context
// ============================================================================

/// ✅ GOOD: Denormalize parent comment context for nested threads
Future<void> createReplyWithContext(
  Ditto ditto,
  String commentId,
  String parentCommentId,
) async {
  // Query parent comment for context
  final parentResult = await ditto.store.execute(
    'SELECT * FROM comments WHERE _id = :commentId',
    arguments: {'commentId': parentCommentId},
  );

  if (parentResult.items.isEmpty) {
    print('Parent comment not found');
    return;
  }

  final parent = parentResult.items.first.value;

  // Create reply with denormalized parent context
  await ditto.store.execute(
    '''
    INSERT INTO comments (
      _id, postId, authorId, content, parentCommentId,
      parentAuthorName, parentContentPreview, createdAt
    )
    VALUES (
      :commentId, :postId, :authorId, :content, :parentCommentId,
      :parentAuthorName, :parentContentPreview, :createdAt
    )
    ''',
    arguments: {
      'commentId': commentId,
      'postId': parent['postId'],
      'authorId': 'user_456',
      'content': 'Great point! I totally agree with your perspective.',
      'parentCommentId': parent['_id'],
      // Denormalize parent comment context for display
      'parentAuthorName': parent['authorName'],
      'parentContentPreview': (parent['content'] as String).substring(
        0,
        (parent['content'] as String).length > 100 ? 100 : (parent['content'] as String).length,
      ),
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Display reply with context without additional query
  final replyResult = await ditto.store.execute(
    'SELECT * FROM comments WHERE _id = :commentId',
    arguments: {'commentId': commentId},
  );

  if (replyResult.items.isNotEmpty) {
    final reply = replyResult.items.first.value;
    print('✅ Reply with context (single query):');
    print('  Replying to ${reply['parentAuthorName']}:');
    print('    "${reply['parentContentPreview']}..."');
    print('  ${reply['content']}');
  }
}

// ============================================================================
// PATTERN 4: Selective Denormalization with Reference
// ============================================================================

/// ✅ GOOD: Hybrid approach - denormalize display data, keep reference for details
Future<void> createInvoiceWithCustomerInfo(Ditto ditto, String invoiceId) async {
  // Query customer details
  final customerResult = await ditto.store.execute(
    'SELECT * FROM customers WHERE _id = :customerId',
    arguments: {'customerId': 'cust_789'},
  );

  if (customerResult.items.isEmpty) {
    print('Customer not found');
    return;
  }

  final customer = customerResult.items.first.value;

  // Create invoice with selective denormalization
  await ditto.store.execute(
    '''
    INSERT INTO invoices (
      _id, invoiceNumber, customerId,
      billingInfo, items, totals, status, createdAt
    )
    VALUES (
      :invoiceId, :invoiceNumber, :customerId,
      :billingInfo, :items, :totals, :status, :createdAt
    )
    ''',
    arguments: {
      'invoiceId': invoiceId,
      'invoiceNumber': 'INV-2024-001',
      'customerId': customer['_id'], // Keep reference
      // Denormalize billing snapshot (point-in-time)
      'billingInfo': {
        'companyName': customer['companyName'],
        'billingAddress': customer['billingAddress'],
        'billingEmail': customer['billingEmail'],
        'taxId': customer['taxId'],
        // Do NOT denormalize: payment methods (sensitive, changes frequently)
      },
      'items': {
        'item_1': {
          'description': 'Professional Services - January 2024',
          'quantity': 40,
          'rate': 150.00,
          'amount': 6000.00,
        },
      },
      'totals': {
        'subtotal': 6000.00,
        'tax': 540.00,
        'total': 6540.00,
      },
      'status': 'draft',
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Invoice is printable without additional queries
  final invoiceResult = await ditto.store.execute(
    'SELECT * FROM invoices WHERE _id = :invoiceId',
    arguments: {'invoiceId': invoiceId},
  );

  if (invoiceResult.items.isNotEmpty) {
    final invoice = invoiceResult.items.first.value;
    print('✅ Invoice ${invoice['invoiceNumber']}:');
    print('  Bill to: ${invoice['billingInfo']['companyName']}');
    print('  Address: ${invoice['billingInfo']['billingAddress']}');
    print('  Total: \$${invoice['totals']['total']}');
  }

  // For payment processing, query fresh customer data using customerId
  // This ensures sensitive payment methods are not stale
}

// ============================================================================
// PATTERN 5: Denormalized Aggregates and Counters
// ============================================================================

/// ✅ GOOD: Store denormalized aggregates for efficient queries
Future<void> updatePostWithEngagementMetrics(
  Ditto ditto,
  String postId,
) async {
  // When user likes a post, update denormalized counter
  await ditto.store.execute(
    '''
    UPDATE posts
    APPLY likeCount PN_INCREMENT BY 1.0,
          lastLikedAt = :timestamp
    WHERE _id = :postId
    ''',
    arguments: {
      'postId': postId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // When user adds comment, update denormalized counter
  await ditto.store.execute(
    '''
    UPDATE posts
    APPLY commentCount PN_INCREMENT BY 1.0,
          lastCommentedAt = :timestamp
    WHERE _id = :postId
    ''',
    arguments: {
      'postId': postId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Query posts sorted by engagement without counting
  final trendingResult = await ditto.store.execute(
    '''
    SELECT * FROM posts
    ORDER BY likeCount DESC, commentCount DESC
    LIMIT 10
    ''',
  );

  print('✅ Trending posts (sorted by denormalized metrics):');
  for (final item in trendingResult.items) {
    final post = item.value;
    print('  ${post['content']}: ${post['likeCount']} likes, ${post['commentCount']} comments');
  }

  // No need to query likes/comments collections to get counts!
}

// ============================================================================
// PATTERN 6: Shopping Cart with Product Snapshots
// ============================================================================

/// ✅ GOOD: Cart stores product snapshot, updates on add/remove only
Future<void> addProductToCart(
  Ditto ditto,
  String cartId,
  String productId,
) async {
  // Query current product details
  final productResult = await ditto.store.execute(
    'SELECT * FROM products WHERE _id = :productId',
    arguments: {'productId': productId},
  );

  if (productResult.items.isEmpty) {
    print('Product not found');
    return;
  }

  final product = productResult.items.first.value;

  // Add to cart with denormalized product snapshot
  await ditto.store.execute(
    '''
    UPDATE carts
    SET items.$productId = :itemData
    WHERE _id = :cartId
    ''',
    arguments: {
      'cartId': cartId,
      'itemData': {
        'productId': product['_id'],
        // Snapshot product details
        'name': product['name'],
        'sku': product['sku'],
        'price': product['price'],
        'imageUrl': product['imageUrl'],
        'inStock': product['inStock'],
        // Cart-specific fields
        'quantity': 1,
        'addedAt': DateTime.now().toIso8601String(),
      },
    },
  );

  // ✅ BENEFIT: Display cart without querying products collection
  final cartResult = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :cartId',
    arguments: {'cartId': cartId},
  );

  if (cartResult.items.isNotEmpty) {
    final cart = cartResult.items.first.value;
    final items = cart['items'] as Map<String, dynamic>;

    print('✅ Cart contents (self-contained):');
    var total = 0.0;
    for (final item in items.values) {
      final lineTotal = (item['price'] as num) * (item['quantity'] as int);
      print('  ${item['name']} x${item['quantity']}: \$${lineTotal.toStringAsFixed(2)}');
      total += lineTotal;
    }
    print('  Total: \$${total.toStringAsFixed(2)}');
  }

  // Note: At checkout, re-query products to verify current price and availability
  // The cart stores a snapshot for browsing, but checkout uses fresh data
}

// ============================================================================
// PATTERN 7: Notification with Denormalized Context
// ============================================================================

/// ✅ GOOD: Notification includes all display context
Future<void> createCommentNotification(
  Ditto ditto,
  String notificationId,
  String postId,
  String commentId,
  String actorUserId,
) async {
  // Query necessary context
  final postResult = await ditto.store.execute(
    'SELECT * FROM posts WHERE _id = :postId',
    arguments: {'postId': postId},
  );
  final actorResult = await ditto.store.execute(
    'SELECT * FROM users WHERE _id = :userId',
    arguments: {'userId': actorUserId},
  );
  final commentResult = await ditto.store.execute(
    'SELECT * FROM comments WHERE _id = :commentId',
    arguments: {'commentId': commentId},
  );

  if (postResult.items.isEmpty || actorResult.items.isEmpty || commentResult.items.isEmpty) {
    print('Missing data for notification');
    return;
  }

  final post = postResult.items.first.value;
  final actor = actorResult.items.first.value;
  final comment = commentResult.items.first.value;

  // Create notification with all display context denormalized
  await ditto.store.execute(
    '''
    INSERT INTO notifications (
      _id, recipientUserId, type, isRead,
      actorUserId, actorName, actorAvatar,
      postId, postTitle, commentPreview, createdAt
    )
    VALUES (
      :notificationId, :recipientUserId, :type, :isRead,
      :actorUserId, :actorName, :actorAvatar,
      :postId, :postTitle, :commentPreview, :createdAt
    )
    ''',
    arguments: {
      'notificationId': notificationId,
      'recipientUserId': post['authorId'], // Post author gets notified
      'type': 'comment',
      'isRead': false,
      // Denormalize actor info
      'actorUserId': actor['_id'],
      'actorName': actor['displayName'],
      'actorAvatar': actor['avatarUrl'],
      // Denormalize post context
      'postId': post['_id'],
      'postTitle': post['content'].toString().substring(0, 50),
      // Denormalize comment preview
      'commentPreview': comment['content'].toString().substring(0, 100),
      'createdAt': DateTime.now().toIso8601String(),
    },
  );

  // ✅ BENEFIT: Display notification feed without multiple queries
  final notificationsResult = await ditto.store.execute(
    '''
    SELECT * FROM notifications
    WHERE recipientUserId = :userId AND isRead = false
    ORDER BY createdAt DESC
    ''',
    arguments: {'userId': post['authorId']},
  );

  print('✅ Unread notifications (self-contained):');
  for (final item in notificationsResult.items) {
    final notification = item.value;
    print('  ${notification['actorName']} commented on your post:');
    print('    "${notification['commentPreview']}"');
  }

  // User can click notification to navigate using postId/commentId references
}
