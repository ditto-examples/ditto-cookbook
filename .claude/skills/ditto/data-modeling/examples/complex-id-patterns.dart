// Complex Object _id Patterns for Ditto
//
// This example demonstrates using complex object _id (composite keys) for
// multi-dimensional organization and hierarchical access control.
//
// Related: Pattern 10 in data-modeling/SKILL.md
// See also: .claude/guides/best-practices/ditto.md#document-structure-best-practices

import 'package:ditto_sdk/ditto_sdk.dart';

// ✅ GOOD: Complex object _id for multi-dimensional organization
class ComplexIdExamples {
  final DittoContext ditto;

  ComplexIdExamples(this.ditto);

  // Example 1: Order with location hierarchy
  Future<void> createOrderWithLocationId() async {
    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {
        'order': {
          '_id': {
            'orderId': '0016d749-9a9b-4ece-8794-7f3eb40bc82e',
            'locationId': '5da42ab5-d00b-4377-8524-43e43abf9e01'
          },
          'total': 45.50,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String(),
        }
      },
    );
    // ⚠️ IMPORTANT: Once created, this _id structure cannot be modified
  }

  // Query by component (access specific field in _id)
  Future<void> queryByLocationId(String locationId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id.locationId = :locId',
      arguments: {'locId': locationId},
    );

    print('Orders at location $locationId: ${result.items.length}');
    for (final item in result.items) {
      final order = item.value;
      print('Order ID: ${order['_id']['orderId']}, Total: ${order['total']}');
    }
  }

  // Query by full object (exact match)
  Future<void> queryByFullId(String orderId, String locationId) async {
    final result = await ditto.store.execute(
      '''SELECT * FROM orders WHERE _id = :idObj''',
      arguments: {
        'idObj': {
          'orderId': orderId,
          'locationId': locationId
        }
      },
    );

    if (result.items.isNotEmpty) {
      final order = result.items.first.value;
      print('Found order: ${order['_id']}, Total: ${order['total']}');
    } else {
      print('Order not found');
    }
  }

  // Example 2: User with device hierarchy (multi-device sync)
  Future<void> createUserSession() async {
    await ditto.store.execute(
      'INSERT INTO user_sessions DOCUMENTS (:session)',
      arguments: {
        'session': {
          '_id': {
            'userId': 'user_123',
            'deviceId': 'device_abc'
          },
          'lastActiveAt': DateTime.now().toIso8601String(),
          'preferences': {
            'theme': 'dark',
            'notifications': true
          }
        }
      },
    );
  }

  // Query all sessions for a user across devices
  Future<void> queryUserSessions(String userId) async {
    final result = await ditto.store.execute(
      'SELECT * FROM user_sessions WHERE _id.userId = :userId',
      arguments: {'userId': userId},
    );

    print('User $userId has ${result.items.length} active sessions');
    for (final item in result.items) {
      final session = item.value;
      print('Device: ${session['_id']['deviceId']}, Last active: ${session['lastActiveAt']}');
    }
  }

  // Example 3: Time-partitioned data (for analytics)
  Future<void> createAnalyticsEvent() async {
    final now = DateTime.now();
    final yearMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    await ditto.store.execute(
      'INSERT INTO analytics_events DOCUMENTS (:event)',
      arguments: {
        'event': {
          '_id': {
            'eventId': '7c0c20ed-b285-48a6-80cd-6dcf06d52bcc',
            'yearMonth': yearMonth  // Enables partitioning/cleanup by time
          },
          'eventType': 'page_view',
          'userId': 'user_456',
          'timestamp': now.toIso8601String()
        }
      },
    );
  }

  // Query events for specific time period
  Future<void> queryEventsByMonth(String yearMonth) async {
    final result = await ditto.store.execute(
      'SELECT * FROM analytics_events WHERE _id.yearMonth = :yearMonth',
      arguments: {'yearMonth': yearMonth},
    );

    print('Events in $yearMonth: ${result.items.length}');
  }
}

// When to Use Complex _id:
// ✅ Multi-dimensional organization (order + location, user + device)
// ✅ Authorization rules requiring hierarchical access (filter by locationId)
// ✅ Natural composite primary keys in domain model
// ✅ Time-based partitioning for data lifecycle management

// Trade-offs:
// ✅ Clear hierarchical structure
// ✅ Component-level queries without string parsing
// ✅ Better alignment with authorization rules
// ❌ More verbose than simple string IDs
// ❌ Requires careful design - immutable after creation
// ❌ Cannot restructure _id if requirements change (must create new documents)

// ⚠️ CRITICAL: _id is immutable
// You CANNOT change _id after document creation. If you need to change the ID:
// 1. Create new document with desired _id
// 2. Copy data from old document
// 3. Delete old document
// See: id-immutability-workaround.dart
