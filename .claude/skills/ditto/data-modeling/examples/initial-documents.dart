// Ditto SDK: 5.1.0 (Flutter package ditto_live)
//
// Default data with INITIAL DOCUMENTS
//
// `INSERT ... INITIAL DOCUMENTS` seeds default data that every peer may create
// independently. Ditto's INSERT documentation describes initial documents as
// inserted "at the beginning of time" and viewed by all peers as the same
// insert (https://docs.ditto.live/dql/insert).
// Behavior on a device:
//   - No local document with that _id: inserted.
//   - A document exists (even an edited one): nothing happens, no error.
//   - Deleted earlier on this device: the deletion wins; a document with
//     null fields remains.
//   - Evicted earlier on this device: inserted again.
//   - Combined with ON ID CONFLICT: parser error.
// Initial documents are regular documents: whether they sync is decided by
// subscriptions, not by INITIAL.
//
// Guide: .claude/guides/best-practices/ditto.md
//   #default-data-with-initial-documents, #insert-and-conflict-handling

import 'package:ditto_live/ditto_live.dart';

// ---------------------------------------------------------------------------
// ✅ GOOD: Seed shared defaults on every launch
// ---------------------------------------------------------------------------

/// Fixed, well-known _id values, so every device creates the same documents.
/// Ship identical seed content in every app version that seeds these IDs.
/// Running this on every launch is safe: existing documents, including edited
/// ones, are untouched.
Future<void> seedDefaultCategories(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO categories INITIAL DOCUMENTS (:categories)',
    arguments: {
      'categories': [
        {'_id': 'food', 'name': 'Food', 'sortOrder': 1, 'isArchived': false},
        {'_id': 'drinks', 'name': 'Drinks', 'sortOrder': 2, 'isArchived': false},
        {
          '_id': 'desserts',
          'name': 'Desserts',
          'sortOrder': 3,
          'isArchived': false,
        },
      ],
    },
  );
}

/// Users "remove" a seed document with a flag (soft delete), because seeding
/// an ID that was deleted leaves a document with null fields.
Future<void> archiveCategory(Ditto ditto, String categoryId) async {
  await ditto.store.execute(
    'UPDATE categories SET isArchived = true WHERE _id = :id',
    arguments: {'id': categoryId},
  );
}

Future<List<Map<String, dynamic>>> visibleCategories(Ditto ditto) async {
  final result = await ditto.store.execute(
    'SELECT * FROM categories WHERE coalesce(isArchived, false) = false '
    'ORDER BY sortOrder',
  );
  return result.items.map((item) => item.value).toList();
}

/// Counters can be seeded too, with a declaration.
Future<void> seedInventory(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO COLLECTION inventory (stockCount COUNTER) '
    'INITIAL DOCUMENTS (:item)',
    arguments: {
      'item': {'_id': 'sku-1001', 'name': 'Paper cups', 'stockCount': 0},
    },
  );
}

// ---------------------------------------------------------------------------
// ❌ BAD: Seeding with a regular INSERT
// ---------------------------------------------------------------------------

/// ❌ BAD: The second launch fails with an ID conflict (default FAIL policy).
Future<void> seedWithPlainInsert(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO settings DOCUMENTS (:defaults)',
    arguments: {
      'defaults': {'_id': 'app', 'theme': 'light', 'currency': 'USD'},
    },
  );
}

/// ❌ BAD: DO UPDATE on every launch overwrites the user's edits (for example,
/// a theme changed to dark) with the defaults.
Future<void> seedWithUpsert(Ditto ditto) async {
  await ditto.store.execute(
    'INSERT INTO settings DOCUMENTS (:defaults) ON ID CONFLICT DO UPDATE',
    arguments: {
      'defaults': {'_id': 'app', 'theme': 'light', 'currency': 'USD'},
    },
  );
}

// Also avoid INITIAL DOCUMENTS for data that only one device should create
// (orders, events): use a regular INSERT with a new UUID.
