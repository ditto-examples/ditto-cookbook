// ============================================================================
// Simple POS Example - Ditto SDK Flutter
// ============================================================================
//
// Demonstrates Ditto SDK best practices for a Point-of-Sale system:
// 1. DittoManager - Lifecycle and transaction management
// 2. DittoDataSource - Generic Ditto API wrapper
// 3. POSRepository - POS-specific business logic
// 4. SimplePOSApp - Demonstration workflow
//
// Schema: .claude/examples/ditto/simple_pos/simple_pos_schema.yaml
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:dittolive_ditto/dittolive_ditto.dart';
import 'package:uuid/uuid.dart';

// ============================================================================
// DittoManager - Lifecycle and Transaction Management
// ============================================================================

class DittoManager {
  Ditto? _ditto;

  /// Get Ditto instance (must call initialize() first)
  Ditto get instance {
    if (_ditto == null) {
      throw StateError(
        'DittoManager not initialized. Call initialize() first.',
      );
    }
    return _ditto!;
  }

  /// Initialize Ditto (get credentials from https://portal.ditto.live)
  Future<void> initialize({
    required String appId,
    required String token,
    String? persistenceDirectory,
  }) async {
    if (_ditto != null) {
      return;
    }

    try {
      final identity = await DittoIdentity.onlinePlayground(
        appID: appId,
        token: token,
      );

      _ditto = await Ditto.open(
        identity: identity,
        persistenceDirectory: persistenceDirectory,
      );

      // Disable strict mode: objects are inferred as MAPs
      await _ditto!.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');

      // Start mesh networking
      await _ditto!.startSync();
    } catch (e) {
      _ditto = null;
      rethrow;
    }
  }

  /// Close Ditto
  Future<void> close() async {
    if (_ditto == null) {
      return;
    }

    try {
      await _ditto!.close();
    } catch (e) {
      // Log error but still clean up state
      print('Warning: Error during Ditto close: $e');
    } finally {
      _ditto = null;
    }
  }
}

// ============================================================================
// DittoDataSource - Generic Ditto API Wrapper (Reusable)
// ============================================================================

class DittoDataSource {
  final DittoManager _dittoManager;

  DittoDataSource(this._dittoManager);

  Ditto get _ditto => _dittoManager.instance;

  /// Generic SELECT query (extracts item.value immediately)
  Future<List<Map<String, dynamic>>> query({
    required String query,
    Map<String, Object?>? arguments,
  }) async {
    try {
      final result = await _ditto.store.execute(query, arguments: arguments);

      // CRITICAL: Extract immediately (QueryResultItems should not be retained)
      return result.items?.map((item) => item.value).toList() ?? [];
    } catch (e) {
      throw Exception('Query execution failed: $e');
    }
  }

  /// Generic INSERT operation
  Future<String> insert({
    required String collection,
    required Map<String, dynamic> document,
  }) async {
    try {
      final result = await _ditto.store.execute(
        'INSERT INTO $collection DOCUMENTS (:doc)',
        arguments: {'doc': document},
      );

      final items = result.items;
      if (items == null || items.isEmpty) {
        throw Exception('Insert succeeded but no document ID was returned');
      }
      return items.first.value['_id'] as String;
    } catch (e) {
      throw Exception(
        'Insert operation failed for collection "$collection": $e',
      );
    }
  }

  /// Generic UPDATE operation
  Future<void> update({
    required String query,
    Map<String, Object?>? arguments,
  }) async {
    try {
      await _ditto.store.execute(query, arguments: arguments);
    } catch (e) {
      throw Exception('Update operation failed: $e');
    }
  }

  /// Generic EVICT operation (local storage only, not mesh)
  Future<void> evict({
    required String query,
    Map<String, Object?>? arguments,
  }) async {
    try {
      await _ditto.store.execute(query, arguments: arguments);
    } catch (e) {
      throw Exception('Evict operation failed: $e');
    }
  }

  /// Register Observer (keep callback lightweight)
  DittoStoreObserver registerObserver({
    required String query,
    Map<String, Object?>? arguments,
    required void Function(DittoQueryResult) onChange,
  }) {
    try {
      return _ditto.store.registerObserver(
        query,
        arguments: arguments,
        onChange: onChange,
      );
    } catch (e) {
      throw Exception('Failed to register observer: $e');
    }
  }

  /// Register Subscription for mesh sync
  DittoSyncSubscription registerSubscription({
    required String query,
    Map<String, Object?>? arguments,
  }) {
    try {
      return _ditto.sync.registerSubscription(query, arguments: arguments);
    } catch (e) {
      throw Exception('Failed to register subscription: $e');
    }
  }
}

// ============================================================================
// POSRepository - POS-Specific Business Logic
// ============================================================================

class POSRepository {
  final DittoDataSource _dataSource;
  final Uuid _uuid = const Uuid();

  // Observer and Subscription references for lifecycle management
  DittoStoreObserver? _orderObserver;
  DittoSyncSubscription? _orderSubscription;

  // Scheduler for EVICT operations (pseudo-implementation)
  Timer? _evictionTimer;

  POSRepository(this._dataSource);

  // ==========================================================================
  // Menu Item Operations
  // ==========================================================================

  /// Get available menu items
  Future<List<MenuItem>> getAvailableMenuItems() async {
    final docs = await _dataSource.query(query: MenuItem.availableItemsQuery);

    return docs.map((doc) => MenuItem.fromDitto(doc)).toList();
  }

  /// Update menu item price (field-level update)
  Future<void> updateMenuItemPrice({
    required String menuItemId,
    required double newPrice,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _dataSource.update(
      query: '''UPDATE menuItems
                SET price = :price, updatedAt = :updatedAt
                WHERE _id = :id''',
      arguments: {'price': newPrice, 'updatedAt': now, 'id': menuItemId},
    );
  }

  /// Toggle menu item availability (field-level update)
  Future<void> toggleMenuItemAvailability({
    required String menuItemId,
    required bool isAvailable,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _dataSource.update(
      query: '''UPDATE menuItems
                SET isAvailable = :isAvailable, updatedAt = :updatedAt
                WHERE _id = :id''',
      arguments: {
        'isAvailable': isAvailable,
        'updatedAt': now,
        'id': menuItemId,
      },
    );
  }

  // ==========================================================================
  // Order Operations
  // ==========================================================================

  /// Create order with MAP items structure (denormalized menu data)
  Future<String> createOrder({
    required String? tableNumber,
    required List<MenuItem> menuItems,
    Map<String, int>? quantities,
  }) async {
    if (menuItems.isEmpty) {
      throw ArgumentError('Order must contain at least one menu item');
    }

    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();

    final items = <String, OrderItem>{};
    for (final menuItem in menuItems) {
      final quantity = quantities?[menuItem.id] ?? 1;

      if (quantity <= 0) {
        throw ArgumentError(
          'Quantity must be positive for item: ${menuItem.name}',
        );
      }

      final itemKey = 'item_${_uuid.v4()}';
      items[itemKey] = OrderItem(
        menuItemId: menuItem.id,
        name: menuItem.name,
        price: menuItem.price,
        quantity: quantity,
      );
    }

    final orderDoc = {
      'tableNumber': tableNumber,
      'status': 'pending',
      'items': items.map((key, value) => MapEntry(key, value.toMap())),
      'paymentStatus': 'unpaid',
      'createdAt': nowIso,
      'updatedAt': nowIso,
    };

    final orderId = await _dataSource.insert(
      collection: 'orders',
      document: orderDoc,
    );

    return orderId;
  }

  /// Add item to order (MAP field insertion)
  Future<void> addItemToOrder({
    required String orderId,
    required MenuItem menuItem,
    int quantity = 1,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Quantity must be positive');
    }

    final now = DateTime.now().toUtc().toIso8601String();

    // Use UUID for item key to avoid race conditions in distributed environments
    final itemKey = 'item_${_uuid.v4()}';

    final orderItem = OrderItem(
      menuItemId: menuItem.id,
      name: menuItem.name,
      price: menuItem.price,
      quantity: quantity,
    );

    // Insert new item into MAP
    await _dataSource.update(
      query:
          '''UPDATE orders
                SET items.$itemKey = :item, updatedAt = :updatedAt
                WHERE _id = :id''',
      arguments: {'item': orderItem.toMap(), 'updatedAt': now, 'id': orderId},
    );
  }

  /// Update order status (field-level update)
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _dataSource.update(
      query: '''UPDATE orders
                SET status = :status, updatedAt = :updatedAt
                WHERE _id = :id''',
      arguments: {'status': status, 'updatedAt': now, 'id': orderId},
    );
  }

  /// Get recent orders (24-hour window)
  Future<List<Order>> getRecentOrders() async {
    final docs = await _dataSource.query(
      query: Order.recentOrdersQuery,
      arguments: Order.timeWindowArgs,
    );

    return docs.map((doc) => Order.fromDitto(doc)).toList();
  }

  /// Get order by ID
  Future<Order?> getOrderById(String orderId) async {
    final docs = await _dataSource.query(
      query: Order.findByIdQuery,
      arguments: {'id': orderId},
    );

    return docs.isEmpty ? null : Order.fromDitto(docs.first);
  }

  // ==========================================================================
  // Observer/Subscription Management
  // ==========================================================================

  /// Start observing recent orders (24-hour window)
  void startObservingRecentOrders({
    required void Function(List<Order>) onOrdersChanged,
  }) {
    if (_orderObserver != null) {
      stopObserving();
    }

    _orderObserver = _dataSource.registerObserver(
      query: Order.recentOrdersQuery,
      arguments: Order.timeWindowArgs,
      onChange: (result) {
        final orderDocs = result.items?.map((item) => item.value).toList() ?? <Map<String, dynamic>>[];
        final orders = orderDocs.map((doc) => Order.fromDitto(doc)).toList();
        onOrdersChanged(orders);
      },
    );
  }

  /// Start subscription for recent orders (24-hour window)
  void startSubscription() {
    if (_orderSubscription != null) {
      stopSubscription();
    }

    _orderSubscription = _dataSource.registerSubscription(
      query: Order.recentOrdersQuery,
      arguments: Order.timeWindowArgs,
    );
  }

  /// Stop observing orders
  void stopObserving() {
    _orderObserver?.cancel();
    _orderObserver = null;
  }

  /// Stop subscription
  void stopSubscription() {
    _orderSubscription?.cancel();
    _orderSubscription = null;
  }

  // ==========================================================================
  // Storage Management (EVICT)
  // ==========================================================================

  /// EVICT orders older than 24 hours (local storage only)
  Future<void> evictOldOrders() async {
    await _dataSource.evict(
      query: Order.evictOldOrdersQuery,
      arguments: Order.timeWindowArgs,
    );
  }

  /// Start eviction scheduler (pseudo-implementation for demonstration)
  void startEvictionScheduler() {
    // Production implementation (commented for demonstration):
    // _evictionTimer = Timer.periodic(Duration(hours: 24), (_) async {
    //   await evictOldOrders();
    // });
  }

  /// Stop eviction scheduler
  void stopEvictionScheduler() {
    _evictionTimer?.cancel();
    _evictionTimer = null;
  }

  /// Dispose (clean shutdown)
  void dispose() {
    stopObserving();
    stopSubscription();
    stopEvictionScheduler();
  }
}

// ============================================================================
// SimplePOSApp - Demonstration Workflow
// ============================================================================

class SimplePOSApp {
  late DittoManager _dittoManager;
  late DittoDataSource _dataSource;
  late POSRepository _repository;

  Future<void> run() async {
    try {
      await _initializeDitto();

      final menuItems = await _queryMenuItems();

      _startObserverAndSubscription();

      final orderId = await _createSampleOrder(menuItems);

      await _displayRecentOrders();

      await _updateOrderStatus(orderId);

      await _calculateAndDisplayTotals(orderId);

      await _demonstrateEvict();

      await _cleanShutdown();
    } catch (e) {
      await _cleanShutdown();
      rethrow;
    }
  }

  Future<void> _initializeDitto() async {
    _dittoManager = DittoManager();
    await _dittoManager.initialize(
      appId: 'YOUR_APP_ID', // Replace with your app ID
      token: 'YOUR_TOKEN', // Replace with your token
      persistenceDirectory: '/tmp/ditto_pos_demo',
    );

    _dataSource = DittoDataSource(_dittoManager);
    _repository = POSRepository(_dataSource);
  }

  Future<List<MenuItem>> _queryMenuItems() async {
    final menuItems = await _repository.getAvailableMenuItems();

    if (menuItems.isEmpty) {
      return [];
    }

    return menuItems;
  }

  void _startObserverAndSubscription() {
    _repository.startObservingRecentOrders(
      onOrdersChanged: (orders) {
        // Handle order changes
      },
    );

    _repository.startSubscription();
    _repository.startEvictionScheduler();
  }

  Future<String> _createSampleOrder(List<MenuItem> menuItems) async {
    if (menuItems.isEmpty) {
      throw Exception('Cannot create order: no menu items available');
    }

    final orderItems = <MenuItem>[];
    final quantities = <String, int>{};

    for (int i = 0; i < menuItems.length && i < 2; i++) {
      orderItems.add(menuItems[i]);
      quantities[menuItems[i].id] = i == 0 ? 2 : 1;
    }

    final orderId = await _repository.createOrder(
      tableNumber: 'T05',
      menuItems: orderItems,
      quantities: quantities,
    );

    return orderId;
  }

  Future<void> _displayRecentOrders() async {
    await _repository.getRecentOrders();
  }

  Future<void> _updateOrderStatus(String orderId) async {
    await _repository.updateOrderStatus(orderId: orderId, status: 'confirmed');
    await _repository.updateOrderStatus(orderId: orderId, status: 'preparing');
  }

  Future<void> _calculateAndDisplayTotals(String orderId) async {
    final order = await _repository.getOrderById(orderId);
    if (order == null) {
      return;
    }

    order.calculateTotals();
  }

  Future<void> _demonstrateEvict() async {
    await _repository.evictOldOrders();
  }

  Future<void> _cleanShutdown() async {
    _repository.dispose();
    await _dittoManager.close();
  }
}

void main() async {
  final app = SimplePOSApp();
  await app.run();
}

// ============================================================================
// Data Models
// ============================================================================

/// MenuItem data class with Ditto conversion methods
class MenuItem {
  final String id;
  final String name;
  final String category;
  final double price;
  final bool isAvailable;
  final String createdAt;
  final String updatedAt;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.isAvailable,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create MenuItem from Ditto document
  factory MenuItem.fromDitto(Map<String, dynamic> doc) {
    return MenuItem(
      id: doc['_id'] as String,
      name: doc['name'] as String,
      category: doc['category'] as String,
      price: (doc['price'] as num).toDouble(),
      isAvailable: doc['isAvailable'] as bool,
      createdAt: doc['createdAt'] as String,
      updatedAt: doc['updatedAt'] as String,
    );
  }

  /// Convert MenuItem to Map for Ditto storage
  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
      'category': category,
      'price': price,
      'isAvailable': isAvailable,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  // Query definitions
  static const String availableItemsQuery = '''
    SELECT * FROM menuItems
    WHERE isAvailable = true
    ORDER BY category ASC, name ASC
  ''';

  @override
  String toString() {
    return '$name - \$$price ($category) - Available: $isAvailable';
  }
}

/// OrderItem data class with denormalized menu item data
class OrderItem {
  final String menuItemId;
  final String name;
  final double price;
  final int quantity;

  OrderItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  /// Create OrderItem from Ditto MAP field
  factory OrderItem.fromDitto(Map<String, dynamic> doc) {
    return OrderItem(
      menuItemId: doc['menuItemId'] as String,
      name: doc['name'] as String,
      price: (doc['price'] as num).toDouble(),
      quantity: (doc['quantity'] as num).toInt(),
    );
  }

  /// Convert OrderItem to Map for Ditto storage
  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItemId,
      'name': name,
      'price': price,
      'quantity': quantity,
    };
  }

  /// Calculate line total (not stored)
  double get lineTotal => price * quantity;

  @override
  String toString() {
    return '$name x$quantity @ \$$price';
  }
}

/// Order data class with MAP structure for CRDT-safe concurrent updates
class Order {
  final String id;
  final String? tableNumber;
  final String status;
  final Map<String, OrderItem> items; // MAP structure (CRDT-safe)
  final String paymentStatus;
  final String createdAt;
  final String updatedAt;

  Order({
    required this.id,
    this.tableNumber,
    required this.status,
    required this.items,
    required this.paymentStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create Order from Ditto document
  factory Order.fromDitto(Map<String, dynamic> doc) {
    final itemsMap = doc['items'] as Map<String, dynamic>? ?? {};
    final items = <String, OrderItem>{};

    itemsMap.forEach((key, value) {
      items[key] = OrderItem.fromDitto(value as Map<String, dynamic>);
    });

    return Order(
      id: doc['_id'] as String,
      tableNumber: doc['tableNumber'] as String?,
      status: doc['status'] as String,
      items: items,
      paymentStatus: doc['paymentStatus'] as String,
      createdAt: doc['createdAt'] as String,
      updatedAt: doc['updatedAt'] as String,
    );
  }

  /// Calculate order totals (not stored, compute on-demand)
  OrderTotals calculateTotals({double taxRate = 0.10}) {
    double subtotal = 0.0;

    items.forEach((_, item) {
      subtotal += item.lineTotal;
    });

    final tax = subtotal * taxRate;
    final total = subtotal + tax;

    return OrderTotals(
      subtotal: subtotal,
      tax: tax,
      taxRate: taxRate,
      total: total,
    );
  }

  // Query definitions
  static const String recentOrdersQuery = '''
    SELECT * FROM orders
    WHERE createdAt >= date_sub(clock(), :hours, :unit)
    ORDER BY createdAt DESC
  ''';

  static const String findByIdQuery = '''
    SELECT * FROM orders WHERE _id = :id
  ''';

  static const String evictOldOrdersQuery = '''
    EVICT FROM orders
    WHERE createdAt < date_sub(clock(), :hours, :unit)
  ''';

  static const Map<String, Object?> timeWindowArgs = {
    'hours': 24,
    'unit': 'hour',
  };

  @override
  String toString() {
    return 'Order $id - Table: $tableNumber - Status: $status - Payment: $paymentStatus - Items: ${items.length}';
  }
}

/// OrderTotals data class (calculated, not stored)
class OrderTotals {
  final double subtotal;
  final double tax;
  final double taxRate;
  final double total;

  OrderTotals({
    required this.subtotal,
    required this.tax,
    required this.taxRate,
    required this.total,
  });
}
