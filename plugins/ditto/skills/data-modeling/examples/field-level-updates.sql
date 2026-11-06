-- Ditto SDK 5.2.0 (every SDK)
--
-- Field-level updates and MAP merge semantics (default DQL_STRICT_MODE = false)
--
-- Under the default settings an object is stored as a MAP: assigning an object
-- merges it into the stored map, and only UNSET removes keys. Write only what
-- changed. DO UPDATE_LOCAL_DIFF suits upserts and re-imports of data that
-- another system owns; it does not protect a stale in-memory copy.
--
-- Guide: § Local Write Semantics You Must Know, § Document Structure,
--   § INSERT and Conflict Handling

-- ---------------------------------------------------------------------------
-- Field-level updates
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Only the changed fields are written. Concurrent edits that other
-- devices make to other fields of the order survive the merge.
-- Arguments: {"id": "order-1", "status": "ready", "updatedAt": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET status = :status, updatedAt = :updatedAt WHERE _id = :id

-- ✅ GOOD: Update one field of a nested object (a MAP). Concurrent edits to
-- other fields of shippingAddress merge cleanly.
-- Arguments: {"id": "order-1", "city": "Lisbon"}
UPDATE orders SET shippingAddress.city = :city WHERE _id = :id

-- ✅ GOOD: UNSET is the only way to remove a key from a map.
-- Arguments: {"id": "order-1"}
UPDATE orders UNSET shippingAddress.line2 WHERE _id = :id

-- ---------------------------------------------------------------------------
-- Upserting a full document
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Re-importing reference data that your backend owns.
-- DO UPDATE_LOCAL_DIFF compares the incoming document with the local one and
-- skips fields whose values are equal. Re-writing unchanged data writes
-- nothing (no mutation, no observer callback): the result lists no mutated
-- document IDs when the stored document already had the same values.
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "priceCents": 250}}
INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ❌ BAD: Writing back a whole in-memory copy after the user changed only the
-- status. If another device changed tableNumber after this copy was loaded,
-- the stale value is written back: DO UPDATE writes every supplied field, and
-- DO UPDATE_LOCAL_DIFF writes every field that differs from the stored one,
-- which includes the stale tableNumber. Use a field-level UPDATE instead.
-- Arguments: {"order": {"_id": "order-1", "status": "ready", "tableNumber": 4}}
INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ---------------------------------------------------------------------------
-- Replacing an object
-- ---------------------------------------------------------------------------

-- ❌ BAD: Expecting this to replace the address. Under the default settings
-- the object is merged into the existing map: keys missing from the new
-- address (for example, line2) remain. `SET shippingAddress = {}` clears
-- nothing either.
-- Arguments: {"id": "order-1", "address": {"line1": "Rua Augusta 10", "city": "Lisbon"}}
UPDATE orders SET shippingAddress = :address WHERE _id = :id

-- ✅ GOOD: Clear the map, then write the new object, with these two statements
-- in one transaction so no reader sees the intermediate state. The field is
-- still a map, so a nested edit that another device makes at the same time
-- can merge into the new object; only a REGISTER declaration (see
-- strict-mode-and-declarations.sql) prevents that.
-- Arguments: {"id": "order-1"}
UPDATE orders UNSET shippingAddress WHERE _id = :id

-- Arguments: {"id": "order-1", "address": {"line1": "Rua Augusta 10", "city": "Lisbon"}}
UPDATE orders SET shippingAddress = :address WHERE _id = :id
