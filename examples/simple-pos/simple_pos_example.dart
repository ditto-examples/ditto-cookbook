// ============================================================================
// Simple POS Example - Ditto SDK 5.1 for Flutter (ditto_live 5.1.0)
// ============================================================================
//
// A minimal Point-of-Sale (POS) and Kitchen Display System (KDS) for one
// restaurant location ("store"). Terminals and kitchen displays sync orders
// with each other and with Ditto Server.
//
// Demonstrates:
// 1. PosService     - Startup (DittoConfig + Ditto.open), authentication,
//                     indexes, long-lived subscriptions, time-based eviction,
//                     and shutdown
// 2. PosRepository  - DQL with parameters, upserts with
//                     DO UPDATE_LOCAL_DIFF, line items in a map keyed by ID,
//                     transactions, and soft delete
// 3. OpenOrdersScreen - The recommended store observer pattern
//                     (consume `changes`, cancel in dispose)
// 4. runDemoWorkflow - An end-to-end walkthrough of the repository
//
// Schema: examples/simple-pos/simple_pos_schema.yaml
// Guide:  best-practices/ditto.md
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ============================================================================
// Configuration and Placeholders
// ============================================================================

/// Copy these values from the Ditto Portal. Copy the Server URL exactly as
/// shown; do not build it from the Database ID.
const databaseId = 'YOUR_DATABASE_ID';
const serverUrl = 'YOUR_SERVER_URL';

/// The authentication provider name configured in the Ditto Portal.
const authProvider = 'YOUR_PROVIDER_NAME';

/// Returns a token from your backend or identity provider.
///
/// Replace this placeholder with a real call. During development only, you
/// can log in with the Portal's development token and
/// `Authenticator.developmentProvider` instead.
Future<String> fetchAuthToken() async {
  throw UnimplementedError('Fetch an authentication token from your backend');
}

/// Reports an error to your logging or crash reporting pipeline.
void showError(Object error) {
  debugPrint('POS error: $error');
}

// ============================================================================
// Helpers
// ============================================================================

/// Returns an ISO-8601 UTC timestamp with exactly millisecond precision,
/// e.g. "2026-10-08T10:30:00.123Z".
///
/// One fixed format keeps text comparison and ORDER BY correct across
/// platforms (native Dart prints microseconds, the web prints milliseconds).
String utcTimestamp([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

final _random = Random.secure();

/// Returns a random (version 4) UUID such as
/// "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f".
///
/// Offline devices cannot coordinate a sequence, so every document ID and
/// line item key is a random UUID.
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Map keys used in DQL paths must match this pattern (lowercase UUID).
final _uuidKey = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

// ============================================================================
// PosService - Startup, Subscriptions, Eviction, and Shutdown
// ============================================================================

/// Owns the single Ditto instance and the long-lived subscriptions of one
/// store. Create it once at app start and close it only when the whole app
/// no longer needs Ditto.
class PosService {
  PosService._(this.ditto, this.storeId, this.repository);

  /// Orders older than this are evicted from this device. They remain on
  /// Ditto Server and on every other peer that still subscribes to them.
  static const orderRetention = Duration(hours: 24);

  final Ditto ditto;
  final String storeId;
  final PosRepository repository;

  SyncSubscription? _menuSubscription;
  SyncSubscription? _ordersSubscription;
  Timer? _evictionTimer;

  static Future<PosService> start({
    required String storeId,
    required String terminalCode,
  }) async {
    // 1. Initialize explicitly because DittoLogger is configured before open.
    await Ditto.init();
    DittoLogger.minimumLogLevel =
        kReleaseMode ? LogLevel.warning : LogLevel.debug;

    // 2. Open the single shared instance (default persistence directory).
    final ditto = await Ditto.open(
      const DittoConfig(
        databaseID: databaseId,
        connect: DittoConfigConnectServer(url: serverUrl),
      ),
    );

    try {
      // 3. Server connections require an expiration handler before
      //    sync.start().
      await _configureAuthentication(ditto);

      // 4. No ALTER SYSTEM statements: this example relies on the defaults.
      //    With DQL_STRICT_MODE = false, objects are stored as CRDT maps
      //    (needed for the line item map) and the query planner uses indexes.

      // 5. Indexes persist; IF NOT EXISTS makes this safe on every start.
      await _createIndexes(ditto);

      // 6. Register long-lived subscriptions, then start sync.
      final service = PosService._(
        ditto,
        storeId,
        PosRepository(ditto, storeId: storeId, terminalCode: terminalCode),
      );
      service._menuSubscription = service._subscribeToMenu();
      service._ordersSubscription =
          service._subscribeToOrdersSince(service._orderCutoff());
      ditto.sync.start(); // returns void; do not await

      // 7. Evict expired orders at most about once a day. A production app
      //    would also persist the time of the last run across restarts.
      service._evictionTimer = Timer.periodic(
        const Duration(days: 1),
        (_) => unawaited(service._runScheduledEviction()),
      );
      return service;
    } catch (_) {
      await ditto.close();
      rethrow;
    }
  }

  static Future<void> _configureAuthentication(Ditto ditto) async {
    await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
      try {
        final response = await ditto.auth.login(
          token: await fetchAuthToken(),
          provider: authProvider,
        );
        final exception = response.exception;
        if (exception != null) {
          showError(exception); // login() reports rejection; it does not throw
        }
      } catch (error) {
        showError(error); // e.g. fetchAuthToken() failed; never rethrow here
      }
    });
  }

  static Future<void> _createIndexes(Ditto ditto) async {
    // The in-browser store on Flutter Web does not support indexes.
    if (kIsWeb) return;
    try {
      // Composite index (SDK 5.1+): equality on storeId, range and sort on
      // createdAt. Used by the recent-orders query and the KDS observer.
      await ditto.store.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_storeId_createdAt '
        'ON orders (storeId, createdAt DESC)',
      );
      await ditto.store.execute(
        'CREATE INDEX IF NOT EXISTS idx_menuItems_storeId_category '
        'ON menuItems (storeId, category)',
      );
    } catch (error) {
      // A missing index makes queries slower, not wrong: report and continue.
      showError(error);
    }
  }

  /// The menu is small reference data: subscribe to the whole store
  /// partition, including soft-deleted items, so that every device can relay
  /// the deletion flag to devices that missed it and the final DELETE on
  /// Ditto Server reaches every device. Local queries hide soft-deleted items.
  SyncSubscription _subscribeToMenu() => ditto.sync.registerSubscription(
        'SELECT * FROM menuItems WHERE storeId = :storeId',
        arguments: {'storeId': storeId},
      );

  /// Orders are scoped by store and by a retention window. The cutoff is a
  /// stable value that moves only when expired orders are evicted.
  SyncSubscription _subscribeToOrdersSince(String cutoff) =>
      ditto.sync.registerSubscription(
        'SELECT * FROM orders WHERE storeId = :storeId AND createdAt >= :cutoff',
        arguments: {'storeId': storeId, 'cutoff': cutoff},
      );

  String _orderCutoff() =>
      utcTimestamp(DateTime.now().subtract(orderRetention));

  /// Removes orders older than the retention window from this device only.
  /// Returns the number of evicted orders.
  Future<int> evictExpiredOrders() async {
    final cutoff = _orderCutoff();

    // 1. Stop asking peers for the orders that are about to be evicted.
    _ordersSubscription?.cancel();

    // 2. Evict exactly the complement of the new subscription (same cutoff,
    //    `<` instead of `>=`), so evicted orders do not sync back.
    final result = await ditto.store.execute(
      'EVICT FROM orders WHERE createdAt < :cutoff',
      arguments: {'cutoff': cutoff},
    );

    // 3. Subscribe again with the moved boundary.
    _ordersSubscription = _subscribeToOrdersSince(cutoff);
    return result.mutatedDocumentIDs().length;
  }

  Future<void> _runScheduledEviction() async {
    try {
      await evictExpiredOrders();
    } catch (error) {
      showError(error);
    }
  }

  /// Call only when the whole app no longer needs Ditto. Await your own
  /// pending writes first: close() does not wait for in-flight work.
  Future<void> close() async {
    _evictionTimer?.cancel();
    _menuSubscription?.cancel();
    _ordersSubscription?.cancel();
    await ditto.close(); // stops sync; idempotent
  }
}

// ============================================================================
// PosRepository - POS-Specific Reads and Writes
// ============================================================================

class PosRepository {
  PosRepository(this._ditto, {required this.storeId, required this.terminalCode});

  final Ditto _ditto;
  final String storeId;

  /// A short code assigned to this terminal, used only in display numbers.
  final String terminalCode;

  /// Per-terminal sequence for display numbers. A production app persists it
  /// on the device (for example, reset daily).
  int _localSequence = 0;

  // ==========================================================================
  // Menu Items
  // ==========================================================================

  /// Upserts menu items received from the back office. Unchanged items are
  /// not rewritten, so repeated imports do not create sync traffic.
  Future<void> importMenuItems(List<MenuItem> items) async {
    if (items.isEmpty) return;
    await _ditto.store.execute(
      'INSERT INTO menuItems DOCUMENTS (:items) '
      'ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
      arguments: {'items': [for (final item in items) item.toDocument()]},
    );
  }

  /// Available, not soft-deleted menu items of this store.
  Future<List<MenuItem>> getAvailableMenuItems() async {
    final result = await _ditto.store.execute(
      'SELECT * FROM menuItems '
      'WHERE storeId = :storeId AND isAvailable = true '
      'AND coalesce(isDeleted, false) = false '
      'ORDER BY category ASC, name ASC',
      arguments: {'storeId': storeId},
    );
    return result.items.map((item) => MenuItem.fromDitto(item.value)).toList();
  }

  /// Field-level update: only priceCents and updatedAt are written.
  Future<void> updateMenuItemPrice({
    required String menuItemId,
    required int priceCents,
  }) async {
    await _ditto.store.execute(
      'UPDATE menuItems SET priceCents = :priceCents, updatedAt = :updatedAt '
      'WHERE _id = :id',
      arguments: {
        'id': menuItemId,
        'priceCents': priceCents,
        'updatedAt': utcTimestamp(),
      },
    );
  }

  Future<void> setMenuItemAvailability({
    required String menuItemId,
    required bool isAvailable,
  }) async {
    await _ditto.store.execute(
      'UPDATE menuItems SET isAvailable = :isAvailable, updatedAt = :updatedAt '
      'WHERE _id = :id',
      arguments: {
        'id': menuItemId,
        'isAvailable': isAvailable,
        'updatedAt': utcTimestamp(),
      },
    );
  }

  /// Soft delete: the flag syncs like any other field and can be undone.
  /// Historical orders keep their own copy of the item's name and price.
  Future<void> removeMenuItem(String menuItemId) async {
    final now = utcTimestamp();
    await _ditto.store.execute(
      'UPDATE menuItems '
      'SET isDeleted = true, deletedAt = :deletedAt, updatedAt = :updatedAt '
      'WHERE _id = :id',
      arguments: {'id': menuItemId, 'deletedAt': now, 'updatedAt': now},
    );
  }

  // ==========================================================================
  // Orders
  // ==========================================================================

  /// Creates an order. Line items are stored in a map keyed by a UUID, so
  /// terminals that add or edit different items concurrently all keep their
  /// changes after sync.
  Future<String> createOrder({
    String? tableNumber,
    required List<OrderLine> lines,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }
    final now = utcTimestamp();
    final orderId = uuidV4();
    _localSequence++;

    await _ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': orderId,
          'storeId': storeId,
          // A label for people, not an identifier: not unique across devices.
          'displayNumber':
              '$terminalCode-${_localSequence.toString().padLeft(4, '0')}',
          'tableNumber': tableNumber,
          'status': OrderStatus.pending.name,
          'paymentStatus': PaymentStatus.unpaid.name,
          'items': {
            for (final line in lines)
              uuidV4(): OrderItem.fromMenuItem(
                line.menuItem,
                quantity: line.quantity,
                addedAt: now,
              ).toDocument(),
          },
          'createdAt': now,
          'updatedAt': now,
        },
      },
    );
    return orderId;
  }

  /// Adds a line item to an order that still accepts changes. Returns the new
  /// line item ID, or null if the order does not exist or is closed.
  Future<String?> addItemToOrder({
    required String orderId,
    required MenuItem menuItem,
    int quantity = 1,
  }) async {
    final now = utcTimestamp();
    final lineId = uuidV4();
    final item = OrderItem.fromMenuItem(
      menuItem,
      quantity: quantity,
      addedAt: now,
    );

    final action = await _ditto.store.transaction(
      hint: 'addItemToOrder',
      (tx) async {
        final result = await tx.execute(
          'SELECT status FROM orders WHERE _id = :id',
          arguments: {'id': orderId},
        );
        if (result.items.isEmpty ||
            !_acceptsItemChanges(result.items.first.value)) {
          return TransactionCompletionAction.rollback;
        }
        // The map key is passed as data, never spliced into the query.
        // Objects merge, so only the new entry and updatedAt are written.
        await tx.execute(
          'INSERT INTO orders DOCUMENTS (:patch) '
          'ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
          arguments: {
            'patch': {
              '_id': orderId,
              'items': {lineId: item.toDocument()},
              'updatedAt': now,
            },
          },
        );
        return TransactionCompletionAction.commit;
      },
    );
    return action == TransactionCompletionAction.commit ? lineId : null;
  }

  /// Changes the quantity of one existing line item. Returns false if the
  /// order is closed or the line item no longer exists.
  Future<bool> changeItemQuantity({
    required String orderId,
    required String lineId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be positive');
    }
    final action = await _ditto.store.transaction(
      hint: 'changeItemQuantity',
      (tx) async {
        final result = await tx.execute(
          'SELECT status, items FROM orders WHERE _id = :id',
          arguments: {'id': orderId},
        );
        if (result.items.isEmpty) return TransactionCompletionAction.rollback;
        final order = result.items.first.value;
        final items = (order['items'] as Map<String, dynamic>?) ?? const {};
        // Check first: the upsert below would otherwise create the entry.
        if (!_acceptsItemChanges(order) || !items.containsKey(lineId)) {
          return TransactionCompletionAction.rollback;
        }
        // Writes only the quantity of this entry; concurrent edits to other
        // entries or other fields of this entry are kept.
        await tx.execute(
          'INSERT INTO orders DOCUMENTS (:patch) '
          'ON ID CONFLICT DO UPDATE_LOCAL_DIFF',
          arguments: {
            'patch': {
              '_id': orderId,
              'items': {
                lineId: {'quantity': quantity},
              },
              'updatedAt': utcTimestamp(),
            },
          },
        );
        return TransactionCompletionAction.commit;
      },
    );
    return action == TransactionCompletionAction.commit;
  }

  /// Removes one line item. Map entries are removed with UNSET (assigning an
  /// object merges and never removes keys). A path cannot be a parameter, so
  /// the key is validated before it is placed in a backtick-quoted segment.
  Future<void> removeItemFromOrder({
    required String orderId,
    required String lineId,
  }) async {
    if (!_uuidKey.hasMatch(lineId)) {
      throw ArgumentError.value(lineId, 'lineId', 'must be a lowercase UUID');
    }
    await _ditto.store.execute(
      'UPDATE orders SET updatedAt = :updatedAt UNSET items.`$lineId` '
      'WHERE _id = :id',
      arguments: {'id': orderId, 'updatedAt': utcTimestamp()},
    );
  }

  /// Field-level status update (POS and KDS).
  Future<void> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    await _ditto.store.execute(
      'UPDATE orders SET status = :status, updatedAt = :updatedAt '
      'WHERE _id = :id',
      arguments: {
        'id': orderId,
        'status': status.name,
        'updatedAt': utcTimestamp(),
      },
    );
  }

  /// Records a payment that the payment terminal has already approved.
  /// Card data never goes into Ditto; only the outcome is stored.
  Future<void> markOrderPaid(String orderId) async {
    final now = utcTimestamp();
    await _ditto.store.execute(
      'UPDATE orders '
      'SET paymentStatus = :paymentStatus, paidAt = :paidAt, '
      'updatedAt = :updatedAt '
      'WHERE _id = :id',
      arguments: {
        'id': orderId,
        'paymentStatus': PaymentStatus.paid.name,
        'paidAt': now,
        'updatedAt': now,
      },
    );
  }

  Future<Order?> getOrderById(String orderId) async {
    final result = await _ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :id',
      arguments: {'id': orderId},
    );
    if (result.items.isEmpty) return null;
    return Order.fromDitto(result.items.first.value);
  }

  /// Orders created since [since], newest first (local store only).
  Future<List<Order>> getRecentOrders({required DateTime since}) async {
    final result = await _ditto.store.execute(
      'SELECT * FROM orders '
      'WHERE storeId = :storeId AND createdAt >= :since '
      'ORDER BY createdAt DESC, _id',
      arguments: {'storeId': storeId, 'since': utcTimestamp(since)},
    );
    return result.items.map((item) => Order.fromDitto(item.value)).toList();
  }

  bool _acceptsItemChanges(Map<String, dynamic> order) {
    final status = OrderStatus.fromName(order['status'] as String?);
    return status != null && status.acceptsItemChanges;
  }
}

// ============================================================================
// OpenOrdersScreen - Recommended Store Observer Pattern
// ============================================================================

/// Live list of the store's open orders, e.g. on a kitchen display.
///
/// The observer is registered without onChange, its `changes` stream is
/// consumed by one StreamSubscription, and both are cancelled in dispose().
/// The subscription that syncs these orders is owned by PosService.
class OpenOrdersScreen extends StatefulWidget {
  const OpenOrdersScreen({super.key, required this.ditto, required this.storeId});

  final Ditto ditto;
  final String storeId;

  @override
  State<OpenOrdersScreen> createState() => _OpenOrdersScreenState();
}

class _OpenOrdersScreenState extends State<OpenOrdersScreen> {
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;
  List<Order> _orders = const [];

  @override
  void initState() {
    super.initState();
    _observer = widget.ditto.store.registerObserver(
      'SELECT * FROM orders '
      'WHERE storeId = :storeId AND status IN :statuses '
      'ORDER BY createdAt ASC, _id',
      arguments: {
        'storeId': widget.storeId,
        'statuses': [
          for (final status in OrderStatus.values)
            if (status.isOpen) status.name,
        ],
      },
    );
    _changes = _observer.changes.listen((result) {
      // Copy plain values out of the result; do not keep QueryResult objects.
      final orders =
          result.items.map((item) => Order.fromDitto(item.value)).toList();
      setState(() => _orders = orders);
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _observer.cancel(); // cancelling the stream does not cancel the observer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open orders')),
      body: ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          final totals = order.calculateTotals();
          return ListTile(
            key: ValueKey(order.id),
            title: Text('${order.displayNumber}  ${order.tableNumber ?? ''}'),
            subtitle: Text(
              '${order.status.name} - ${order.items.length} items',
            ),
            trailing: Text(formatCents(totals.totalCents)),
          );
        },
      ),
    );
  }
}

/// Root widget. Closes Ditto when the app is torn down.
class SimplePosApp extends StatefulWidget {
  const SimplePosApp({super.key, required this.service});

  final PosService service;

  @override
  State<SimplePosApp> createState() => _SimplePosAppState();
}

class _SimplePosAppState extends State<SimplePosApp> {
  @override
  void dispose() {
    unawaited(widget.service.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: OpenOrdersScreen(
        ditto: widget.service.ditto,
        storeId: widget.service.storeId,
      ),
    );
  }
}

// ============================================================================
// Demonstration Workflow
// ============================================================================

/// Sample catalog. In production, menu items come from your back office with
/// stable IDs, and re-importing unchanged items is a no-op.
List<MenuItem> sampleMenu(String storeId) {
  const createdAt = '2026-01-15T09:00:00.000Z';
  return [
    MenuItem(
      id: '7c0c20ed-b285-48a6-80cd-6dcf06d52bcc',
      storeId: storeId,
      name: 'Classic Cheeseburger',
      category: 'mains',
      priceCents: 1299,
      isAvailable: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    MenuItem(
      id: '2f9a4c61-8e3b-4d7a-b1c5-6e0f2a9d8b34',
      storeId: storeId,
      name: 'French Fries',
      category: 'sides',
      priceCents: 449,
      isAvailable: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    MenuItem(
      id: 'c5e1b7d2-3a4f-4e6b-9c8d-1f2e3a4b5c6d',
      storeId: storeId,
      name: 'Lemonade',
      category: 'beverages',
      priceCents: 349,
      isAvailable: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
  ];
}

Future<void> runDemoWorkflow(PosRepository repository) async {
  // 1. Seed or refresh the catalog (upsert; unchanged items are not rewritten).
  await repository.importMenuItems(sampleMenu(repository.storeId));
  final menu = await repository.getAvailableMenuItems();
  if (menu.length < 3) return;

  // 2. Create an order with two line items.
  final orderId = await repository.createOrder(
    tableNumber: 'T05',
    lines: [
      OrderLine(menu[0], quantity: 2),
      OrderLine(menu[1]),
    ],
  );

  // 3. Add, change, and remove line items.
  final lineId = await repository.addItemToOrder(
    orderId: orderId,
    menuItem: menu[2],
  );
  if (lineId != null) {
    await repository.changeItemQuantity(
      orderId: orderId,
      lineId: lineId,
      quantity: 3,
    );
    await repository.removeItemFromOrder(orderId: orderId, lineId: lineId);
  }

  // 4. Move the order through the kitchen workflow and take payment.
  await repository.updateOrderStatus(
    orderId: orderId,
    status: OrderStatus.confirmed,
  );
  await repository.updateOrderStatus(
    orderId: orderId,
    status: OrderStatus.preparing,
  );
  await repository.markOrderPaid(orderId);

  // 5. Totals are derived when reading, never stored.
  final order = await repository.getOrderById(orderId);
  if (order != null) {
    final totals = order.calculateTotals();
    debugPrint('$order total=${formatCents(totals.totalCents)}');
  }

  final recent = await repository.getRecentOrders(
    since: DateTime.now().subtract(const Duration(hours: 1)),
  );
  debugPrint('Orders in the last hour: ${recent.length}');

  // 6. Take an item off the menu (soft delete).
  await repository.removeMenuItem(menu[2].id);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = await PosService.start(storeId: 'store-1', terminalCode: 'T1');
  await runDemoWorkflow(service.repository);
  runApp(SimplePosApp(service: service));
}

// ============================================================================
// Data Models
// ============================================================================

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  completed,
  cancelled;

  /// Shown on the kitchen display.
  bool get isOpen => this != completed && this != cancelled;

  /// Line items can still be added, changed, or removed.
  bool get acceptsItemChanges =>
      this == pending || this == confirmed || this == preparing;

  static OrderStatus? fromName(String? name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return null;
  }
}

enum PaymentStatus {
  unpaid,
  paid,
  refunded;

  static PaymentStatus fromName(String? name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return unpaid;
  }
}

/// Formats an amount in minor units, e.g. 1299 -> "12.99".
String formatCents(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

class MenuItem {
  const MenuItem({
    required this.id,
    required this.storeId,
    required this.name,
    required this.category,
    required this.priceCents,
    required this.isAvailable,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String storeId;
  final String name;
  final String category;

  /// Prices are integers in minor units (cents) to avoid rounding errors.
  final int priceCents;
  final bool isAvailable;
  final bool isDeleted;
  final String createdAt;
  final String updatedAt;

  factory MenuItem.fromDitto(Map<String, dynamic> doc) {
    return MenuItem(
      id: doc['_id'] as String,
      storeId: doc['storeId'] as String,
      name: doc['name'] as String,
      category: doc['category'] as String,
      priceCents: (doc['priceCents'] as num).toInt(),
      isAvailable: doc['isAvailable'] as bool? ?? false,
      // A missing or null flag means "not deleted".
      isDeleted: doc['isDeleted'] as bool? ?? false,
      createdAt: doc['createdAt'] as String,
      updatedAt: doc['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toDocument() => {
        '_id': id,
        'storeId': storeId,
        'name': name,
        'category': category,
        'priceCents': priceCents,
        'isAvailable': isAvailable,
        'isDeleted': isDeleted,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  @override
  String toString() => '$name ${formatCents(priceCents)} ($category)';
}

/// A menu item and quantity to put on a new order.
class OrderLine {
  const OrderLine(this.menuItem, {this.quantity = 1});

  final MenuItem menuItem;
  final int quantity;
}

/// One entry of an order's `items` map. Name and unit price are snapshots
/// taken when the item was added, so later menu changes do not alter
/// existing orders.
class OrderItem {
  const OrderItem({
    required this.menuItemId,
    required this.name,
    required this.unitPriceCents,
    required this.quantity,
    required this.addedAt,
  });

  factory OrderItem.fromMenuItem(
    MenuItem menuItem, {
    required int quantity,
    required String addedAt,
  }) {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be positive');
    }
    return OrderItem(
      menuItemId: menuItem.id,
      name: menuItem.name,
      unitPriceCents: menuItem.priceCents,
      quantity: quantity,
      addedAt: addedAt,
    );
  }

  factory OrderItem.fromDitto(Map<String, dynamic> doc) {
    return OrderItem(
      menuItemId: doc['menuItemId'] as String,
      name: doc['name'] as String,
      unitPriceCents: (doc['unitPriceCents'] as num).toInt(),
      quantity: (doc['quantity'] as num).toInt(),
      addedAt: doc['addedAt'] as String,
    );
  }

  final String menuItemId;
  final String name;
  final int unitPriceCents;
  final int quantity;

  /// Display order of line items (map entries have no order of their own).
  final String addedAt;

  /// Derived at read time; never stored.
  int get lineTotalCents => unitPriceCents * quantity;

  Map<String, dynamic> toDocument() => {
        'menuItemId': menuItemId,
        'name': name,
        'unitPriceCents': unitPriceCents,
        'quantity': quantity,
        'addedAt': addedAt,
      };

  @override
  String toString() => '$name x$quantity @ ${formatCents(unitPriceCents)}';
}

class Order {
  const Order({
    required this.id,
    required this.storeId,
    required this.displayNumber,
    this.tableNumber,
    required this.status,
    required this.paymentStatus,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromDitto(Map<String, dynamic> doc) {
    final rawItems = (doc['items'] as Map<String, dynamic>?) ?? const {};
    return Order(
      id: doc['_id'] as String,
      storeId: doc['storeId'] as String,
      displayNumber: doc['displayNumber'] as String? ?? '',
      tableNumber: doc['tableNumber'] as String?,
      status: OrderStatus.fromName(doc['status'] as String?) ??
          OrderStatus.pending,
      paymentStatus: PaymentStatus.fromName(doc['paymentStatus'] as String?),
      items: {
        for (final entry in rawItems.entries)
          entry.key: OrderItem.fromDitto(entry.value as Map<String, dynamic>),
      },
      createdAt: doc['createdAt'] as String,
      updatedAt: doc['updatedAt'] as String,
    );
  }

  final String id;
  final String storeId;
  final String displayNumber;
  final String? tableNumber;
  final OrderStatus status;
  final PaymentStatus paymentStatus;

  /// Line items keyed by line item ID (a CRDT map).
  final Map<String, OrderItem> items;
  final String createdAt;
  final String updatedAt;

  /// Line items in the order they were added.
  List<MapEntry<String, OrderItem>> get sortedItems =>
      items.entries.toList()
        ..sort((a, b) => a.value.addedAt.compareTo(b.value.addedAt));

  /// Totals are derived from the merged line items whenever they are read.
  /// Stored totals could disagree with the items after concurrent edits.
  OrderTotals calculateTotals({double taxRate = 0.10}) {
    var subtotalCents = 0;
    for (final item in items.values) {
      subtotalCents += item.lineTotalCents;
    }
    final taxCents = (subtotalCents * taxRate).round();
    return OrderTotals(
      subtotalCents: subtotalCents,
      taxCents: taxCents,
      totalCents: subtotalCents + taxCents,
    );
  }

  @override
  String toString() =>
      'Order $displayNumber ($id) table=$tableNumber status=${status.name} '
      'payment=${paymentStatus.name} items=${sortedItems.map((e) => e.value)}';
}

/// Calculated values; not stored in Ditto.
class OrderTotals {
  const OrderTotals({
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
  });

  final int subtotalCents;
  final int taxCents;
  final int totalCents;
}
