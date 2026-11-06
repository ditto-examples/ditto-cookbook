-- Ditto SDK 5.2.0 (every SDK)
--
-- Default data with INITIAL DOCUMENTS
--
-- `INSERT ... INITIAL DOCUMENTS` seeds default data that every peer may create
-- independently. Ditto's INSERT documentation describes initial documents as
-- inserted "at the beginning of time" and viewed by all peers as the same
-- insert (https://docs.ditto.live/dql/insert).
-- Behavior on a device:
--   - No local document with that _id: inserted.
--   - A document exists (even an edited one): nothing happens, no error.
--   - Deleted earlier on this device: the deletion wins. With a seed identical
--     to the INITIAL insert that created the document, it stays deleted; with
--     different content, or if the document was created with a regular
--     INSERT, a document with null fields remains.
--   - Evicted earlier on this device: inserted again.
--   - Combined with ON ID CONFLICT: parser error.
-- Across devices (SDK 5.1.0 tests):
--   - The deletion rule also applies to deletions received from other devices,
--     and a document with null fields then appears on every device (also when
--     a newly installed device seeds before it first connects).
--   - Different seeds for the same _id merge field by field; a field set by
--     both is decided by its value, not by which device seeded later. Keep
--     seed content identical across app versions.
-- Initial documents are regular documents: whether they sync is decided by
-- subscriptions, not by INITIAL.
--
-- Guide: § Default Data with INITIAL Documents,
--   § INSERT and Conflict Handling

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Seed shared defaults on every launch
-- ---------------------------------------------------------------------------

-- Fixed, well-known _id values, so every device creates the same documents.
-- Ship identical seed content in every app version that seeds these IDs.
-- Running this on every launch is safe: existing documents, including edited
-- ones, are untouched.
-- Arguments: {"categories": [{"_id": "food", "name": "Food", "sortOrder": 1, "isArchived": false}, {"_id": "drinks", "name": "Drinks", "sortOrder": 2, "isArchived": false}, {"_id": "desserts", "name": "Desserts", "sortOrder": 3, "isArchived": false}]}
INSERT INTO categories INITIAL DOCUMENTS (:categories)

-- Users "remove" a seed document with a flag (soft delete), because a later
-- app version may seed different content, and seeding a deleted ID with
-- different content leaves a document with null fields.
-- Arguments: {"id": "desserts"}
UPDATE categories SET isArchived = true WHERE _id = :id

SELECT * FROM categories WHERE coalesce(isArchived, false) = false
ORDER BY sortOrder

-- Counters can be seeded too, with a declaration.
-- Arguments: {"item": {"_id": "sku-1001", "name": "Paper cups", "stockCount": 0}}
INSERT INTO COLLECTION inventory (stockCount COUNTER) INITIAL DOCUMENTS (:item)

-- ---------------------------------------------------------------------------
-- ❌ BAD: Seeding with a regular INSERT
-- ---------------------------------------------------------------------------

-- ❌ BAD: The second launch fails with an ID conflict (default FAIL policy).
-- Arguments: {"defaults": {"_id": "app", "theme": "light", "currency": "USD"}}
INSERT INTO settings DOCUMENTS (:defaults)

-- ❌ BAD: DO UPDATE on every launch overwrites the user's edits (for example,
-- a theme changed to dark) with the defaults.
-- Arguments: {"defaults": {"_id": "app", "theme": "light", "currency": "USD"}}
INSERT INTO settings DOCUMENTS (:defaults) ON ID CONFLICT DO UPDATE

-- Also avoid INITIAL DOCUMENTS for data that only one device should create
-- (orders, events): use a regular INSERT with a new UUID.
