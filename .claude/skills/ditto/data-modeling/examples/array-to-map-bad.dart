// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Array-Based Anti-Patterns (Before MAP Migration)
// ============================================================================
//
// This example demonstrates common anti-patterns when using arrays for
// mutable data in Ditto, showing why arrays cause merge conflicts.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Array updates causing lost changes
// 2. ❌ Last-write-wins conflicts with arrays
// 3. ❌ Read-modify-write race conditions
// 4. ❌ Array item reordering conflicts
// 5. ❌ Concurrent append operations
// 6. ❌ Array-based "add/remove" operations
// 7. ❌ Complex array queries requiring full document reads
//
// WHY ARRAYS ARE PROBLEMATIC:
// - Arrays are treated as single values in CRDTs
// - Entire array is replaced on update (last-write-wins)
// - No field-level merging for array elements
// - Concurrent modifications cause data loss
//
// SOLUTION: Use MAP structures instead (see array-to-map-migration.dart)
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// ANTI-PATTERN 1: Lost Changes from Concurrent Updates
// ============================================================================

/// ❌ BAD: Updating array items loses concurrent changes
Future<void> antiPattern1_LostUpdates(Ditto ditto) async {
  const orderId = 'order_001';

  // Initial order with array of line items
  await ditto.store.execute(
    '''
    INSERT INTO orders (_id, customerId, lineItems, status)
    VALUES (:orderId, :customerId, :lineItems, :status)
    ''',
    arguments: {
      'orderId': orderId,
      'customerId': 'cust_123',
      'status': 'pending',
      'lineItems': [
        {'sku': 'LAPTOP-001', 'quantity': 1, 'price': 999.99},
        {'sku': 'MOUSE-001', 'quantity': 2, 'price': 29.99},
        {'sku': 'KEYBOARD-001', 'quantity': 1, 'price': 79.99},
      ],
    },
  );

  // ❌ Device A: Warehouse updates LAPTOP quantity
  final resultA = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );
  final lineItemsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['lineItems'] as List,
  );
  // Find and update LAPTOP
  final laptopIndex = lineItemsA.indexWhere((item) => item['sku'] == 'LAPTOP-001');
  if (laptopIndex != -1) {
    lineItemsA[laptopIndex]['quantity'] = 2; // Customer ordered 1 more
  }

  // ❌ Device B: Sales updates MOUSE price (price drop)
  final resultB = await ditto.store.execute(
    'SELECT * FROM orders WHERE _id = :orderId',
    arguments: {'orderId': orderId},
  );
  final lineItemsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['lineItems'] as List,
  );
  // Find and update MOUSE
  final mouseIndex = lineItemsB.indexWhere((item) => item['sku'] == 'MOUSE-001');
  if (mouseIndex != -1) {
    lineItemsB[mouseIndex]['price'] = 24.99; // Price drop
  }

  // Both devices write back their modified arrays
  await ditto.store.execute(
    'UPDATE orders SET lineItems = :lineItems WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'lineItems': lineItemsA},
  );

  await ditto.store.execute(
    'UPDATE orders SET lineItems = :lineItems WHERE _id = :orderId',
    arguments: {'orderId': orderId, 'lineItems': lineItemsB},
  );

  // 🚨 RESULT: Last write wins!
  // Device B's write overwrites Device A's quantity update
  // LAPTOP quantity change is LOST
  // Only MOUSE price update survives
  print('❌ Lost update: LAPTOP quantity change disappeared due to last-write-wins');
}

// ============================================================================
// ANTI-PATTERN 2: Concurrent Append Operations
// ============================================================================

/// ❌ BAD: Concurrent appends to array lose items
Future<void> antiPattern2_ConcurrentAppends(Ditto ditto) async {
  const cartId = 'cart_002';

  // Initial cart with one item
  await ditto.store.execute(
    '''
    INSERT INTO carts (_id, userId, items)
    VALUES (:cartId, :userId, :items)
    ''',
    arguments: {
      'cartId': cartId,
      'userId': 'user_456',
      'items': [
        {'productId': 'prod_1', 'name': 'Laptop', 'quantity': 1},
      ],
    },
  );

  // ❌ Device A: User adds Mouse to cart
  final resultA = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :cartId',
    arguments: {'cartId': cartId},
  );
  final itemsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['items'] as List,
  );
  itemsA.add({'productId': 'prod_2', 'name': 'Mouse', 'quantity': 1});

  // ❌ Device B: User adds Keyboard to cart (almost simultaneously)
  final resultB = await ditto.store.execute(
    'SELECT * FROM carts WHERE _id = :cartId',
    arguments: {'cartId': cartId},
  );
  final itemsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['items'] as List,
  );
  itemsB.add({'productId': 'prod_3', 'name': 'Keyboard', 'quantity': 1});

  // Both devices write back
  await ditto.store.execute(
    'UPDATE carts SET items = :items WHERE _id = :cartId',
    arguments: {'cartId': cartId, 'items': itemsA},
  );
  await ditto.store.execute(
    'UPDATE carts SET items = :items WHERE _id = :cartId',
    arguments: {'cartId': cartId, 'items': itemsB},
  );

  // 🚨 RESULT: One item is lost!
  // Final cart has: [Laptop, Keyboard]
  // Mouse is LOST because Device B's write overwrites Device A's append
  print('❌ Lost item: Mouse disappeared from cart due to concurrent append conflict');
}

// ============================================================================
// ANTI-PATTERN 3: Array Item Removal Conflicts
// ============================================================================

/// ❌ BAD: Removing items from array causes conflicts
Future<void> antiPattern3_RemovalConflicts(Ditto ditto) async {
  const todoListId = 'todolist_003';

  // Initial todo list
  await ditto.store.execute(
    '''
    INSERT INTO todolists (_id, userId, todos)
    VALUES (:id, :userId, :todos)
    ''',
    arguments: {
      'id': todoListId,
      'userId': 'user_789',
      'todos': [
        {'id': 'todo_1', 'text': 'Buy groceries', 'done': false},
        {'id': 'todo_2', 'text': 'Call dentist', 'done': false},
        {'id': 'todo_3', 'text': 'Fix bug #123', 'done': false},
        {'id': 'todo_4', 'text': 'Write report', 'done': false},
      ],
    },
  );

  // ❌ Device A: User marks todo_2 as done and removes it
  final resultA = await ditto.store.execute(
    'SELECT * FROM todolists WHERE _id = :id',
    arguments: {'id': todoListId},
  );
  final todosA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['todos'] as List,
  );
  todosA.removeWhere((todo) => todo['id'] == 'todo_2');

  // ❌ Device B: User marks todo_3 as done
  final resultB = await ditto.store.execute(
    'SELECT * FROM todolists WHERE _id = :id',
    arguments: {'id': todoListId},
  );
  final todosB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['todos'] as List,
  );
  final todo3Index = todosB.indexWhere((todo) => todo['id'] == 'todo_3');
  if (todo3Index != -1) {
    todosB[todo3Index]['done'] = true;
  }

  // Both devices write back
  await ditto.store.execute(
    'UPDATE todolists SET todos = :todos WHERE _id = :id',
    arguments: {'id': todoListId, 'todos': todosA},
  );
  await ditto.store.execute(
    'UPDATE todolists SET todos = :todos WHERE _id = :id',
    arguments: {'id': todoListId, 'todos': todosB},
  );

  // 🚨 RESULT: Device A's removal is lost
  // Device B's write restores the entire array including todo_2
  // The "done" status for todo_3 is preserved, but todo_2 reappears
  print('❌ Removal lost: Deleted todo reappeared due to array overwrite');
}

// ============================================================================
// ANTI-PATTERN 4: Array Reordering Conflicts
// ============================================================================

/// ❌ BAD: Reordering array items causes conflicts
Future<void> antiPattern4_ReorderingConflicts(Ditto ditto) async {
  const playlistId = 'playlist_004';

  // Initial playlist
  await ditto.store.execute(
    '''
    INSERT INTO playlists (_id, userId, songs)
    VALUES (:id, :userId, :songs)
    ''',
    arguments: {
      'id': playlistId,
      'userId': 'user_999',
      'songs': [
        {'songId': 'song_1', 'title': 'Song A', 'order': 1},
        {'songId': 'song_2', 'title': 'Song B', 'order': 2},
        {'songId': 'song_3', 'title': 'Song C', 'order': 3},
        {'songId': 'song_4', 'title': 'Song D', 'order': 4},
      ],
    },
  );

  // ❌ Device A: User reorders playlist (moves Song C to top)
  final resultA = await ditto.store.execute(
    'SELECT * FROM playlists WHERE _id = :id',
    arguments: {'id': playlistId},
  );
  final songsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['songs'] as List,
  );
  // Move song_3 to position 0
  final songC = songsA.removeAt(2);
  songsA.insert(0, songC);

  // ❌ Device B: User adds new song to end
  final resultB = await ditto.store.execute(
    'SELECT * FROM playlists WHERE _id = :id',
    arguments: {'id': playlistId},
  );
  final songsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['songs'] as List,
  );
  songsB.add({'songId': 'song_5', 'title': 'Song E', 'order': 5});

  // Both devices write back
  await ditto.store.execute(
    'UPDATE playlists SET songs = :songs WHERE _id = :id',
    arguments: {'id': playlistId, 'songs': songsA},
  );
  await ditto.store.execute(
    'UPDATE playlists SET songs = :songs WHERE _id = :id',
    arguments: {'id': playlistId, 'songs': songsB},
  );

  // 🚨 RESULT: Device A's reordering is lost
  // Device B's write restores original order + new song
  // Song C is back in position 3, not at top
  print('❌ Reorder lost: Playlist order change disappeared due to array overwrite');
}

// ============================================================================
// ANTI-PATTERN 5: Complex Read-Modify-Write Patterns
// ============================================================================

/// ❌ BAD: Complex array queries require reading entire document
Future<void> antiPattern5_InefficientQueries(Ditto ditto) async {
  const inventoryId = 'inventory_005';

  // Initial inventory with array of products
  await ditto.store.execute(
    '''
    INSERT INTO inventories (_id, warehouseId, products)
    VALUES (:id, :warehouseId, :products)
    ''',
    arguments: {
      'id': inventoryId,
      'warehouseId': 'warehouse_1',
      'products': [
        {'sku': 'PROD-001', 'quantity': 100, 'lowStockThreshold': 20},
        {'sku': 'PROD-002', 'quantity': 50, 'lowStockThreshold': 10},
        {'sku': 'PROD-003', 'quantity': 5, 'lowStockThreshold': 10}, // Low stock!
        {'sku': 'PROD-004', 'quantity': 200, 'lowStockThreshold': 50},
      ],
    },
  );

  // ❌ BAD: To find low-stock items, must read entire document
  final result = await ditto.store.execute(
    'SELECT * FROM inventories WHERE _id = :id',
    arguments: {'id': inventoryId},
  );

  if (result.items.isNotEmpty) {
    final products = List<Map<String, dynamic>>.from(
      result.items.first.value['products'] as List,
    );

    // Must filter in application code
    final lowStockProducts = products.where((product) {
      final quantity = product['quantity'] as int;
      final threshold = product['lowStockThreshold'] as int;
      return quantity <= threshold;
    }).toList();

    print('❌ Inefficient: Must read entire array and filter in app code');
    print('   Low stock products: ${lowStockProducts.length}');
  }

  // ❌ BAD: To update single product quantity, must read and write entire array
  final updateResult = await ditto.store.execute(
    'SELECT * FROM inventories WHERE _id = :id',
    arguments: {'id': inventoryId},
  );

  if (updateResult.items.isNotEmpty) {
    final products = List<Map<String, dynamic>>.from(
      updateResult.items.first.value['products'] as List,
    );

    // Find and update specific product
    final prodIndex = products.indexWhere((p) => p['sku'] == 'PROD-001');
    if (prodIndex != -1) {
      products[prodIndex]['quantity'] = 95; // Sold 5 units
    }

    // Must write entire array back
    await ditto.store.execute(
      'UPDATE inventories SET products = :products WHERE _id = :id',
      arguments: {'id': inventoryId, 'products': products},
    );

    print('❌ Inefficient: Updated 1 product but wrote entire array');
  }
}

// ============================================================================
// ANTI-PATTERN 6: Array-Based Event Logs
// ============================================================================

/// ❌ BAD: Using arrays for event logs causes lost events
Future<void> antiPattern6_EventLogConflicts(Ditto ditto) async {
  const sessionId = 'session_006';

  // Initial user session with event log
  await ditto.store.execute(
    '''
    INSERT INTO sessions (_id, userId, events)
    VALUES (:id, :userId, :events)
    ''',
    arguments: {
      'id': sessionId,
      'userId': 'user_123',
      'events': [
        {'type': 'login', 'timestamp': DateTime.now().toIso8601String()},
      ],
    },
  );

  // ❌ Device A: User clicks button
  final resultA = await ditto.store.execute(
    'SELECT * FROM sessions WHERE _id = :id',
    arguments: {'id': sessionId},
  );
  final eventsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['events'] as List,
  );
  eventsA.add({
    'type': 'button_click',
    'buttonId': 'submit_btn',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // ❌ Device B: User navigates to another page (almost simultaneously)
  final resultB = await ditto.store.execute(
    'SELECT * FROM sessions WHERE _id = :id',
    arguments: {'id': sessionId},
  );
  final eventsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['events'] as List,
  );
  eventsB.add({
    'type': 'navigation',
    'page': '/dashboard',
    'timestamp': DateTime.now().toIso8601String(),
  });

  // Both devices write back
  await ditto.store.execute(
    'UPDATE sessions SET events = :events WHERE _id = :id',
    arguments: {'id': sessionId, 'events': eventsA},
  );
  await ditto.store.execute(
    'UPDATE sessions SET events = :events WHERE _id = :id',
    arguments: {'id': sessionId, 'events': eventsB},
  );

  // 🚨 RESULT: One event is lost!
  // Either button_click or navigation event disappears
  // Critical for analytics and audit logs
  print('❌ Lost event: Analytics data incomplete due to array conflict');
}

// ============================================================================
// ANTI-PATTERN 7: Nested Array Updates
// ============================================================================

/// ❌ BAD: Nested arrays multiply the conflict problem
Future<void> antiPattern7_NestedArrayConflicts(Ditto ditto) async {
  const projectId = 'project_007';

  // Project with nested arrays (teams with members)
  await ditto.store.execute(
    '''
    INSERT INTO projects (_id, name, teams)
    VALUES (:id, :name, :teams)
    ''',
    arguments: {
      'id': projectId,
      'name': 'Project Phoenix',
      'teams': [
        {
          'teamId': 'team_1',
          'name': 'Backend Team',
          'members': [
            {'userId': 'user_1', 'role': 'lead'},
            {'userId': 'user_2', 'role': 'developer'},
          ],
        },
        {
          'teamId': 'team_2',
          'name': 'Frontend Team',
          'members': [
            {'userId': 'user_3', 'role': 'lead'},
            {'userId': 'user_4', 'role': 'developer'},
          ],
        },
      ],
    },
  );

  // ❌ Device A: Add member to Backend Team
  final resultA = await ditto.store.execute(
    'SELECT * FROM projects WHERE _id = :id',
    arguments: {'id': projectId},
  );
  final teamsA = List<Map<String, dynamic>>.from(
    resultA.items.first.value['teams'] as List,
  );
  final backendTeam = teamsA.firstWhere((t) => t['teamId'] == 'team_1');
  final backendMembers = List<Map<String, dynamic>>.from(backendTeam['members'] as List);
  backendMembers.add({'userId': 'user_5', 'role': 'developer'});
  backendTeam['members'] = backendMembers;

  // ❌ Device B: Add member to Frontend Team
  final resultB = await ditto.store.execute(
    'SELECT * FROM projects WHERE _id = :id',
    arguments: {'id': projectId},
  );
  final teamsB = List<Map<String, dynamic>>.from(
    resultB.items.first.value['teams'] as List,
  );
  final frontendTeam = teamsB.firstWhere((t) => t['teamId'] == 'team_2');
  final frontendMembers = List<Map<String, dynamic>>.from(frontendTeam['members'] as List);
  frontendMembers.add({'userId': 'user_6', 'role': 'developer'});
  frontendTeam['members'] = frontendMembers;

  // Both devices write back
  await ditto.store.execute(
    'UPDATE projects SET teams = :teams WHERE _id = :id',
    arguments: {'id': projectId, 'teams': teamsA},
  );
  await ditto.store.execute(
    'UPDATE projects SET teams = :teams WHERE _id = :id',
    arguments: {'id': projectId, 'teams': teamsB},
  );

  // 🚨 RESULT: One team's new member is lost
  // Nested arrays amplify the conflict problem
  print('❌ Nested conflict: One team member addition lost due to nested array overwrite');
}
