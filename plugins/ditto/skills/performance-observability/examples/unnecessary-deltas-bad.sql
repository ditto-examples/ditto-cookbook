-- Ditto SDK 5.2.0 (every SDK)
--
-- Unnecessary Writes (Anti-Patterns)
--
-- Guide sections (../../guide/reference/best-practices/ and knowledge/):
-- - § ON ID CONFLICT
-- - § Prefer field-level updates over whole-document rewrites
-- - § Assigning an object merges it
--
-- Each statement below runs, but writes more than it should.
-- Corrected versions are in unnecessary-deltas-good.sql.
--
-- ANTI-PATTERNS DEMONSTRATED:
-- 1. ❌ Periodic re-imports with DO UPDATE
-- 2. ❌ Read-modify-write of a whole document
-- 3. ❌ Writing a value that is already stored
-- 4. ❌ Expecting DO UPDATE to replace a document
-- 5. ❌ Expecting SET obj = {...} to replace or clear an object

-- ============================================================================
-- ANTI-PATTERN 1: Periodic re-imports with DO UPDATE
-- ============================================================================

-- ❌ BAD: DO UPDATE writes every supplied field, even if the value is
-- identical. Every run reports all documents as mutated and can wake
-- observers. Use ON ID CONFLICT DO UPDATE_LOCAL_DIFF instead.
-- Arguments: {"products": [{"_id": "p1", "name": "Pen", "priceCents": 250}]}
INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE

-- ============================================================================
-- ANTI-PATTERN 2: Read-modify-write of a whole document
-- ============================================================================

-- ❌ BAD: Only status changed, but the app reads the order, changes status in
-- memory, and writes every field again. An unchanged field written by this
-- device can win a merge against a real concurrent change made on another
-- device. Use a field-level UPDATE.
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id

-- Arguments: {"order": {"_id": "order-1", "status": "completed", "tableNumber": 4, "total": 42}}
INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE

-- ❌ BAD: A stale in-memory copy is written back with DO UPDATE. A concurrent
-- change that another device made to tableNumber can be overwritten.
-- DO UPDATE_LOCAL_DIFF does not prevent this either: the stale value differs
-- from the stored one, so it is written. Update only the changed field.
-- Arguments: {"order": {"_id": "order-1", "status": "ready", "tableNumber": 7}}
INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE

-- ============================================================================
-- ANTI-PATTERN 3: Writing a value that is already stored
-- ============================================================================

-- ❌ BAD: Run on every heartbeat. An UPDATE that sets a field to its current
-- value is still recorded as a mutation, appears in the result's mutated
-- document IDs, and can wake observers. Add a WHERE condition that skips
-- documents already in the target state.
-- Arguments: {"id": "device-1"}
UPDATE devices SET online = true WHERE _id = :id

-- ============================================================================
-- ANTI-PATTERN 4: Expecting DO UPDATE to replace a document
-- ============================================================================

-- ❌ BAD: The intent is to drop discountCode, but DO UPDATE merges: fields
-- missing from the new document stay, and nested objects are merged. Remove
-- fields with UPDATE ... UNSET instead. discountCode is NOT removed.
-- Arguments: {"order": {"_id": "order-1", "status": "open"}}
INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE

-- ============================================================================
-- ANTI-PATTERN 5: Expecting SET obj = {...} to replace or clear an object
-- ============================================================================

-- ❌ BAD: With the default strict mode, an object field is a CRDT map.
-- `SET address = :address` merges the new keys into the existing object, so
-- old keys such as zip remain. To replace, run UNSET and then SET inside
-- one transaction.
-- Arguments: {"id": "c1", "address": {"street": "Main St", "city": "Oslo"}}
UPDATE customers SET address = :address WHERE _id = :id

-- ❌ BAD: `SET address = {}` leaves the object unchanged. Use UNSET address.
-- Arguments: {"id": "c1"}
UPDATE customers SET address = {} WHERE _id = :id
