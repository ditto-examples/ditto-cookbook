// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// _id Immutability Workaround for Ditto
//
// This example demonstrates the proper way to "change" a document's _id
// since _id fields are immutable after creation.
//
// Related: Pattern 10 in data-modeling/SKILL.md
// See also: .claude/guides/best-practices/ditto.md#document-structure-best-practices

import 'package:ditto_sdk/ditto_sdk.dart';

// ⚠️ CRITICAL: _id is immutable - cannot be changed after document creation
//
// Why Immutability Matters:
// - Authorization rules: _id structure determines access control
// - Distributed sync: Document identity must remain stable across all peers
// - Reference integrity: Foreign-key relationships rely on stable IDs

class IdImmutabilityExamples {
  final DittoContext ditto;

  IdImmutabilityExamples(this.ditto);

  // ❌ BAD: Attempting to change _id after creation
  Future<void> badAttemptToChangeId() async {
    try {
      await ditto.store.execute(
        'UPDATE orders SET _id = :newId WHERE _id = :oldId',
        arguments: {'newId': 'new_123', 'oldId': 'old_123'},
      );
    } catch (e) {
      // ERROR: _id field is immutable - this operation will fail
      print('Error: Cannot update _id field - $e');
    }
  }

  // ✅ GOOD: Workaround - Create new document with desired _id
  Future<void> changeDocumentId(String oldId, String newId) async {
    // Step 1: Retrieve old document
    final result = await ditto.store.execute(
      'SELECT * FROM orders WHERE _id = :oldId',
      arguments: {'oldId': oldId},
    );

    if (result.items.isEmpty) {
      print('Document with _id $oldId not found');
      return;
    }

    final oldDoc = result.items.first.value;
    print('Found document: $oldDoc');

    // Step 2: Create new document with desired _id
    // Copy all fields except _id
    final newDoc = Map<String, dynamic>.from(oldDoc);
    newDoc['_id'] = newId;

    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:doc)',
      arguments: {'doc': newDoc},
    );
    print('Created new document with _id: $newId');

    // Step 3: Delete old document
    await ditto.store.execute(
      'DELETE FROM orders WHERE _id = :oldId',
      arguments: {'oldId': oldId},
    );
    print('Deleted old document with _id: $oldId');
  }

  // ✅ GOOD: Complex object _id "change" (e.g., moving order to different location)
  Future<void> changeComplexId({
    required String oldOrderId,
    required String oldLocationId,
    required String newLocationId,
  }) async {
    // Step 1: Retrieve old document
    final result = await ditto.store.execute(
      '''SELECT * FROM orders WHERE _id = :idObj''',
      arguments: {
        'idObj': {
          'orderId': oldOrderId,
          'locationId': oldLocationId
        }
      },
    );

    if (result.items.isEmpty) {
      print('Document not found');
      return;
    }

    final oldDoc = result.items.first.value;

    // Step 2: Create new document with new _id structure
    final newDoc = Map<String, dynamic>.from(oldDoc);
    newDoc['_id'] = {
      'orderId': oldOrderId,  // Keep same orderId
      'locationId': newLocationId  // New locationId
    };

    await ditto.store.execute(
      'INSERT INTO orders DOCUMENTS (:doc)',
      arguments: {'doc': newDoc},
    );
    print('Created document at new location: $newLocationId');

    // Step 3: Delete old document
    await ditto.store.execute(
      '''DELETE FROM orders WHERE _id = :idObj''',
      arguments: {
        'idObj': {
          'orderId': oldOrderId,
          'locationId': oldLocationId
        }
      },
    );
    print('Deleted document at old location: $oldLocationId');
  }

  // ⚠️ CAUTION: Foreign-key updates required
  //
  // If other documents reference this document's _id, you must update them too.
  Future<void> changeIdWithForeignKeyUpdates(String oldId, String newId) async {
    // Step 1: Find documents referencing old _id
    final referencingDocs = await ditto.store.execute(
      'SELECT * FROM order_items WHERE orderId = :oldId',
      arguments: {'oldId': oldId},
    );

    print('Found ${referencingDocs.items.length} documents referencing old _id');

    // Step 2: Change the document _id (copy + delete)
    await changeDocumentId(oldId, newId);

    // Step 3: Update all foreign-key references
    for (final item in referencingDocs.items) {
      final doc = item.value;
      await ditto.store.execute(
        'UPDATE order_items SET orderId = :newId WHERE _id = :itemId',
        arguments: {
          'newId': newId,
          'itemId': doc['_id']
        },
      );
    }

    print('Updated ${referencingDocs.items.length} foreign-key references');
  }

  // Alternative: Use displayId instead of changing _id
  //
  // Better approach: Keep _id stable, use separate display field
  Future<void> updateDisplayIdInstead(String docId, String newDisplayId) async {
    // ✅ BETTER: Update display field, keep _id stable
    await ditto.store.execute(
      'UPDATE orders SET displayId = :displayId WHERE _id = :id',
      arguments: {'displayId': newDisplayId, 'id': docId},
    );
    print('Updated displayId to $newDisplayId (kept _id stable)');
  }
}

// Best Practices:
//
// 1. Design _id carefully upfront (cannot change later)
// 2. Use UUID v4 or ULID for _id (collision-free, immutable)
// 3. Use separate displayId field for human-readable IDs
// 4. If you must "change" _id:
//    - Create new document with desired _id
//    - Copy data from old document
//    - Update foreign-key references (if any)
//    - Delete old document
// 5. Consider if you really need to change _id, or just update display field

// When _id "change" is necessary:
// ✅ Migrating from legacy ID system to UUID
// ✅ Fixing incorrect composite key structure
// ✅ Moving documents between partitions (time-based, location-based)
// ❌ Don't change _id for display purposes (use displayId field instead)
