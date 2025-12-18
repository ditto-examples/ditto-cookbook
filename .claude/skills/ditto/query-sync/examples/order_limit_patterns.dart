// ✅ GOOD: ORDER BY, LIMIT, and OFFSET patterns
// Demonstrates proper sorting, pagination, and top-N queries

import 'package:ditto/ditto.dart';

// ===================================================================
// ORDER BY: Basic Sorting
// ===================================================================

/// ✅ GOOD: Basic ascending/descending sort
Future<void> basicSorting(Ditto ditto) async {
  // Sort by year descending (newest first), then by mileage ascending
  final result = await ditto.store.execute(
    'SELECT * FROM cars ORDER BY year DESC, mileage ASC',
  );

  final cars = result.items.map((item) => item.value).toList();
  print('Cars sorted by year (newest) and mileage (lowest): ${cars.length}');
}

/// ❌ BAD: LIMIT without ORDER BY (unpredictable results)
Future<void> limitWithoutOrderByBad(Ditto ditto) async {
  // ❌ Problem: Result order is undefined without ORDER BY
  // Different runs may return different sets of 10 documents
  final result = await ditto.store.execute(
    'SELECT * FROM cars LIMIT 10',
  );

  final cars = result.items.map((item) => item.value).toList();
  print('Cars (unpredictable order): ${cars.length}');
  // Solution: Always combine LIMIT with ORDER BY
}

// ===================================================================
// ORDER BY: Expression-Based Sorting
// ===================================================================

/// ✅ GOOD: Expression-based sorting (conditional ordering)
Future<void> expressionBasedSorting(Ditto ditto) async {
  // Blue cars first (true > false in DESC order), then sort others by make
  final result = await ditto.store.execute(
    'SELECT * FROM cars ORDER BY color = \'blue\' DESC, make ASC',
  );

  final cars = result.items.map((item) => item.value).toList();
  print('Cars with blue first: ${cars.length}');
  // Blue cars appear first, followed by others sorted by make
}

/// ✅ GOOD: Multiple condition ordering
Future<void> multipleConditionOrdering(Ditto ditto) async {
  // Priority: featured > discount > alphabetical
  final result = await ditto.store.execute(
    '''SELECT * FROM products
       ORDER BY featured = true DESC, hasDiscount = true DESC, name ASC''',
  );

  final products = result.items.map((item) => item.value).toList();
  print('Products sorted by priority: ${products.length}');
}

// ===================================================================
// ORDER BY: Type Hierarchy
// ===================================================================

/// ✅ GOOD: Understanding type hierarchy in sorting
Future<void> typeHierarchySorting(Ditto ditto) async {
  // Documents with mixed types in a field
  // Ascending order: boolean → number → string → null → missing
  final result = await ditto.store.execute(
    'SELECT * FROM mixed_types ORDER BY value ASC',
  );

  final items = result.items.map((item) => item.value).toList();
  print('Mixed types sorted (ASC): $items');
  // Example order:
  // boolean (true) → number (42) → string ('text') → null → missing
}

// ===================================================================
// LIMIT: Top-N Queries
// ===================================================================

/// ✅ GOOD: Top 10 most expensive products
Future<List<Map<String, dynamic>>> top10MostExpensive(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT make, model, price FROM cars ORDER BY price DESC LIMIT 10',
  );

  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Top 5 recent orders per user
Future<List<Map<String, dynamic>>> recentOrdersByUser(Ditto ditto, String userId) async {
  final result = await ditto.store.execute(
    '''SELECT _id, total, createdAt FROM orders
       WHERE userId = :userId
       ORDER BY createdAt DESC
       LIMIT 5''',
    arguments: {'userId': userId},
  );

  return result.items.map((item) => item.value).toList();
}

// ===================================================================
// LIMIT: Existence Checks
// ===================================================================

/// ✅ GOOD: Check existence with LIMIT 1 (efficient)
Future<bool> hasActiveOrders(Ditto ditto, String userId) async {
  final result = await ditto.store.execute(
    '''SELECT _id FROM orders
       WHERE userId = :userId AND status = :status
       LIMIT 1''',
    arguments: {'userId': userId, 'status': 'active'},
  );

  // Returns immediately after finding first match
  return result.items.isNotEmpty;
}

/// ✅ GOOD: Find first matching document
Future<Map<String, dynamic>?> findFirstMatch(Ditto ditto, String category) async {
  final result = await ditto.store.execute(
    '''SELECT * FROM products
       WHERE category = :category AND inStock = true
       ORDER BY price ASC
       LIMIT 1''',
    arguments: {'category': category},
  );

  if (result.items.isEmpty) return null;
  return result.items.first.value;
}

// ===================================================================
// OFFSET: Pagination Patterns
// ===================================================================

/// ✅ GOOD: Small OFFSET for pagination
Future<List<Map<String, dynamic>>> paginateResults(
  Ditto ditto,
  int page,
  int pageSize,
) async {
  final offset = page * pageSize;

  final result = await ditto.store.execute(
    '''SELECT * FROM orders
       ORDER BY createdAt DESC
       LIMIT :limit OFFSET :offset''',
    arguments: {'limit': pageSize, 'offset': offset},
  );

  return result.items.map((item) => item.value).toList();
}

/// ❌ BAD: Large OFFSET (performance degrades linearly)
Future<void> largeOffsetBad(Ditto ditto) async {
  // ❌ Problem: Must skip 10,000 documents sequentially
  // Performance degrades linearly with offset size
  final result = await ditto.store.execute(
    'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 10000',
  );

  final orders = result.items.map((item) => item.value).toList();
  print('Orders at offset 10000: ${orders.length}');
  // Slow performance - had to skip 10,000 documents
}

/// ✅ BETTER: Cursor-based pagination (efficient for deep pagination)
Future<List<Map<String, dynamic>>> cursorBasedPagination(
  Ditto ditto,
  String? lastSeenTimestamp,
  int limit,
) async {
  if (lastSeenTimestamp == null) {
    // First page
    final result = await ditto.store.execute(
      'SELECT * FROM orders ORDER BY createdAt DESC LIMIT :limit',
      arguments: {'limit': limit},
    );
    return result.items.map((item) => item.value).toList();
  } else {
    // Subsequent pages using cursor
    final result = await ditto.store.execute(
      '''SELECT * FROM orders
         WHERE createdAt < :cursor
         ORDER BY createdAt DESC
         LIMIT :limit''',
      arguments: {'cursor': lastSeenTimestamp, 'limit': limit},
    );
    return result.items.map((item) => item.value).toList();
  }
}

// ===================================================================
// PAGINATION: Complete Example
// ===================================================================

class PaginationState {
  final List<Map<String, dynamic>> items;
  final int currentPage;
  final bool hasMore;
  final String? cursor; // For cursor-based pagination

  PaginationState({
    required this.items,
    required this.currentPage,
    required this.hasMore,
    this.cursor,
  });
}

/// ✅ GOOD: Offset-based pagination for small offsets
Future<PaginationState> fetchOrdersPageOffset(
  Ditto ditto,
  int page,
  int pageSize,
) async {
  final offset = page * pageSize;

  final result = await ditto.store.execute(
    '''SELECT * FROM orders
       ORDER BY createdAt DESC
       LIMIT :limit OFFSET :offset''',
    arguments: {'limit': pageSize + 1, 'offset': offset}, // Fetch one extra to check hasMore
  );

  final items = result.items.take(pageSize).map((item) => item.value).toList();
  final hasMore = result.items.length > pageSize;

  return PaginationState(
    items: items,
    currentPage: page,
    hasMore: hasMore,
  );
}

/// ✅ BETTER: Cursor-based pagination for deep pagination
Future<PaginationState> fetchOrdersPageCursor(
  Ditto ditto,
  String? cursor,
  int pageSize,
) async {
  final query = cursor == null
      ? 'SELECT * FROM orders ORDER BY createdAt DESC LIMIT :limit'
      : '''SELECT * FROM orders
           WHERE createdAt < :cursor
           ORDER BY createdAt DESC
           LIMIT :limit''';

  final args = cursor == null
      ? {'limit': pageSize + 1}
      : {'cursor': cursor, 'limit': pageSize + 1};

  final result = await ditto.store.execute(query, arguments: args);

  final items = result.items.take(pageSize).map((item) => item.value).toList();
  final hasMore = result.items.length > pageSize;

  // Extract cursor from last item
  String? nextCursor;
  if (hasMore && items.isNotEmpty) {
    nextCursor = items.last['createdAt'] as String;
  }

  return PaginationState(
    items: items,
    currentPage: -1, // Not applicable for cursor-based
    hasMore: hasMore,
    cursor: nextCursor,
  );
}

// ===================================================================
// PERFORMANCE COMPARISON
// ===================================================================

/// Demonstrates performance differences between OFFSET and cursor-based pagination
Future<void> paginationPerformanceDemo(Ditto ditto) async {
  print('=== Pagination Performance Demo ===');

  // ❌ BAD: Large OFFSET (slow)
  final offsetStopwatch = Stopwatch()..start();
  await ditto.store.execute(
    'SELECT * FROM orders ORDER BY createdAt DESC LIMIT 20 OFFSET 5000',
  );
  offsetStopwatch.stop();
  print('OFFSET 5000: ${offsetStopwatch.elapsedMilliseconds}ms (slow - had to skip 5000 docs)');

  // ✅ GOOD: Cursor-based (fast)
  final cursorStopwatch = Stopwatch()..start();
  await ditto.store.execute(
    '''SELECT * FROM orders
       WHERE createdAt < :cursor
       ORDER BY createdAt DESC
       LIMIT 20''',
    arguments: {'cursor': '2025-01-01T00:00:00Z'},
  );
  cursorStopwatch.stop();
  print('Cursor-based: ${cursorStopwatch.elapsedMilliseconds}ms (fast - direct jump to cursor)');
}

// ===================================================================
// DISTINCT WITH ORDER BY
// ===================================================================

/// ✅ GOOD: DISTINCT with ORDER BY
Future<List<String>> distinctColorsOrdered(Ditto ditto) async {
  final result = await ditto.store.execute(
    '''SELECT DISTINCT color FROM cars
       WHERE year >= :year
       ORDER BY color ASC''',
    arguments: {'year': 2020},
  );

  return result.items.map((item) => item.value['color'] as String).toList();
}

/// ❌ BAD: DISTINCT with _id (redundant)
Future<void> distinctWithIdBad(Ditto ditto) async {
  // ❌ Problem: _id is already unique - DISTINCT adds no value
  // Buffers all rows in memory unnecessarily
  final result = await ditto.store.execute(
    'SELECT DISTINCT _id, make, model FROM cars ORDER BY make ASC',
  );

  final cars = result.items.map((item) => item.value).toList();
  print('Cars (redundant DISTINCT): ${cars.length}');
  // Solution: Omit DISTINCT when selecting _id
}

// ===================================================================
// REAL-WORLD USE CASES
// ===================================================================

/// ✅ GOOD: Leaderboard (top scorers)
Future<List<Map<String, dynamic>>> fetchLeaderboard(Ditto ditto, int limit) async {
  final result = await ditto.store.execute(
    '''SELECT userId, username, score FROM game_scores
       ORDER BY score DESC, createdAt ASC
       LIMIT :limit''',
    arguments: {'limit': limit},
  );

  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Recent activity feed
Future<List<Map<String, dynamic>>> fetchRecentActivity(Ditto ditto, String userId) async {
  final result = await ditto.store.execute(
    '''SELECT * FROM activities
       WHERE userId = :userId
       ORDER BY timestamp DESC
       LIMIT 50''',
    arguments: {'userId': userId},
  );

  return result.items.map((item) => item.value).toList();
}

/// ✅ GOOD: Product search with sorting options
Future<List<Map<String, dynamic>>> searchProducts(
  Ditto ditto, {
  required String query,
  required String sortBy, // 'price', 'name', 'popularity'
  required String sortOrder, // 'ASC', 'DESC'
  int limit = 50,
}) async {
  final orderClause = 'ORDER BY $sortBy $sortOrder';

  final result = await ditto.store.execute(
    '''SELECT * FROM products
       WHERE name LIKE :query
       $orderClause
       LIMIT :limit''',
    arguments: {'query': '%$query%', 'limit': limit},
  );

  return result.items.map((item) => item.value).toList();
}

// ===================================================================
// KEY TAKEAWAYS
// ===================================================================

/*
✅ DO:
- Always combine LIMIT with ORDER BY for predictable results
- Use LIMIT 1 for existence checks and "find first" queries
- Use cursor-based pagination for deep pagination (avoids large OFFSET)
- Use expression-based ORDER BY for conditional sorting
- Keep OFFSET values small (< 100) for acceptable performance

❌ DON'T:
- Use LIMIT without ORDER BY (unpredictable results)
- Use large OFFSET values (> 1000) - linear performance degradation
- Use DISTINCT with _id (redundant, wastes memory)
- Use OFFSET for infinite scroll - prefer cursor-based pagination

WHY:
- OFFSET requires sequential skipping (performance degrades linearly)
- LIMIT 1 returns immediately after first match (no buffering)
- Cursor-based pagination scales better for deep pages
- ORDER BY ensures consistent, predictable result ordering

PERFORMANCE:
- OFFSET 10: ~instant
- OFFSET 100: acceptable
- OFFSET 1000: noticeable delay
- OFFSET 10000: significant degradation
- Cursor-based: consistent performance regardless of depth

SEE ALSO:
- .claude/guides/best-practices/ditto.md#order-by
- .claude/guides/best-practices/ditto.md#limit-and-offset
- .claude/guides/best-practices/ditto.md#distinct-keyword
*/
