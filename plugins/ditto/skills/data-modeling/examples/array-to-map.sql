-- Ditto SDK 5.2.0 (every SDK)
--
-- Arrays vs maps keyed by ID
--
-- An array is a REGISTER: every write replaces the whole array, and when two
-- devices change it concurrently one version wins and the other change is
-- lost silently. A map keyed by a stable ID merges each entry independently.
--
-- When you convert an existing array, write the map to a new field (for
-- example, lineItems next to the old items array). Writing a map under the
-- array's field name changes its CRDT type: the old array and the new map then
-- coexist under the same key.
--
-- Generate the item keys as UUIDs, and the timestamps with one fixed-precision
-- UTC helper: see "IDs and Timestamps in <SDK>" on your SDK's page.
--
-- Guide: § Arrays and Maps

-- ---------------------------------------------------------------------------
-- ❌ BAD: Line items in an array
-- ---------------------------------------------------------------------------

-- ❌ BAD: Two devices that add different items while offline both rewrite the
-- whole array (the current items plus the new one). After sync, one device's
-- item is gone, without an error.
-- Arguments: {"id": "order-1", "items": [{"productId": "p1", "quantity": 2}, {"productId": "p3", "quantity": 1}]}
UPDATE orders SET items = :items WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Line items in a map keyed by item ID
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Each item is a map entry keyed by a UUID; display order is a field.
-- Concurrent additions, edits to different items, and edits to different
-- fields of one item all merge.
-- Arguments: {"order": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "storeId": "store-12", "status": "open", "createdAt": "2026-10-08T10:30:00.123Z", "items": {"9b2f6c1e-2d4a-4f3b-8c5d-6e7f8a9b0c1d": {"productId": "p1", "quantity": 2, "position": 0}, "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d": {"productId": "p2", "quantity": 1, "position": 1}}}}
INSERT INTO orders DOCUMENTS (:order)

-- ✅ GOOD: Add or update one entry. DQL parameters bind values, not paths, so
-- the key travels as data inside a partial document. Objects merge, and
-- DO UPDATE_LOCAL_DIFF writes only what differs.
-- Note: if the order does not exist yet, this creates it.
-- Arguments: {"patch": {"_id": "order-1", "items": {"9b2f6c1e-2d4a-4f3b-8c5d-6e7f8a9b0c1d": {"productId": "p1", "quantity": 3}}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ✅ GOOD: Remove one entry with UNSET. A path cannot be a parameter, so the
-- app validates the key against a strict pattern (only lowercase UUIDs,
-- ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$) before it
-- places it inside a backtick-quoted path segment. This prevents DQL injection.
--
-- Note (SDK 5.1.0 and 5.2.0): a removal does not win over a concurrent edit
-- of the same entry on another device; the entry stays with only the edited
-- fields (or with them set to null). Readers must skip such entries, and a
-- `removed` flag is safer when concurrent edits are likely.
-- Arguments: {"id": "order-1"}
UPDATE orders UNSET items.`9b2f6c1e-2d4a-4f3b-8c5d-6e7f8a9b0c1d` WHERE _id = :id

-- ✅ GOOD: When the key is a fixed literal, address the entry with a path.
-- Arguments: {"id": "order-1", "quantity": 4}
UPDATE orders SET items.`item-1`.quantity = :quantity WHERE _id = :id

-- ✅ GOOD: Move one entry by writing only its own position, halfway between
-- its new neighbors (previous + 1 at the end, next - 1 at the top, 0 when the
-- list is empty). Renumbering every entry would undo a reorder that another
-- device makes at the same time (guide: § Reordering on Two Devices).
-- The key is validated as in the UNSET example above.
-- Arguments: {"id": "order-1", "position": 0.5}
UPDATE orders SET items.`9b2f6c1e-2d4a-4f3b-8c5d-6e7f8a9b0c1d`.position = :position WHERE _id = :id

-- Read the items in display order in app code: sort the entries of `items` by
-- position (integers or doubles), and by key for equal positions, which two
-- devices can create by inserting into the same gap, so that every device
-- shows the same order.
-- Arguments: {"id": "order-1"}
SELECT items FROM orders WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ✅ ACCEPTABLE: An array that a single device owns or replaces wholesale
-- ---------------------------------------------------------------------------

-- Tags are a list of scalars, replaced as a whole and edited by one device.
-- DQL has no element assignment (`SET tags[0] = ...` is a parser error), so
-- the app builds the new array; the write replaces the whole register. Read
-- and write in one transaction, so that two local calls cannot interleave and
-- drop a tag; a concurrent edit on another device can still win the merge.
-- Arguments: {"id": "p1"}
SELECT tags FROM products WHERE _id = :id

-- Arguments: {"id": "p1", "tags": ["new", "sale"]}
UPDATE products SET tags = :tags WHERE _id = :id

-- Membership filter on an array field: use IN or array_contains.
-- Arguments: {"tag": "sale"}
SELECT * FROM products WHERE array_contains(tags, :tag)
