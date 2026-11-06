-- Ditto SDK 5.2.0 (every SDK)
--
-- Avoiding Unnecessary Writes (Correct Patterns)
--
-- Guide sections (../../guide/reference/best-practices/ and knowledge/):
-- - § ON ID CONFLICT
-- - § Prefer field-level updates over whole-document rewrites
-- - § Assigning an object merges it
-- - § Prefer field-level updates
--
-- Ditto syncs changes at field level. Writing only what changed keeps sync
-- deltas small and reduces the chance that an unchanged value written by this
-- device overwrites a concurrent edit from another peer. It also avoids
-- mutations that wake observers for no visible change.
--
-- | Write                                  | Values unchanged                    |
-- |----------------------------------------|-------------------------------------|
-- | ON ID CONFLICT DO UPDATE               | All supplied fields written again;  |
-- |                                        | document mutated, observers can fire|
-- | ON ID CONFLICT DO UPDATE_LOCAL_DIFF    | Nothing written                     |
-- | UPDATE ... SET f = <current value>     | Mutation recorded, observers can    |
-- |                                        | fire                                |
--
-- The result of each write lists the mutated document IDs: an empty list
-- means that nothing changed.
--
-- PATTERNS DEMONSTRATED:
-- 1. ✅ Upserts and re-imports with DO UPDATE_LOCAL_DIFF
-- 2. ✅ Field-level UPDATE for the fields that changed
-- 3. ✅ Skipping documents that are already in the target state
-- 4. ✅ Nested field updates and UNSET
-- 5. ✅ Replacing an object deliberately (UNSET, then SET)
-- 6. ✅ Saving a form: writing only the fields the user changed

-- ============================================================================
-- PATTERN 1: Upserts and re-imports
-- ============================================================================

-- ✅ GOOD: Refreshing reference data from a backend. Documents whose values
-- did not change are not written, so they do not appear in the mutated
-- document IDs and observers are not woken for them.
-- Arguments: {"products": [{"_id": "p1", "name": "Pen", "priceCents": 250}]}
INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ✅ GOOD: "Create if absent" without touching existing documents.
-- Arguments: {"settings": {"_id": "user-7", "theme": "system", "notifications": true}}
INSERT INTO settings DOCUMENTS (:settings) ON ID CONFLICT DO NOTHING

-- ============================================================================
-- PATTERN 2: Field-level UPDATE
-- ============================================================================

-- ✅ GOOD: Only the fields that changed are written.
-- Arguments: {"id": "order-1", "status": "completed", "completedAt": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET status = :status, completedAt = :completedAt WHERE _id = :id

-- ============================================================================
-- PATTERN 3: Skip documents already in the target state
-- ============================================================================

-- ✅ GOOD: The WHERE condition skips the write when the value is already
-- stored. coalesce keeps documents whose status is missing or null eligible;
-- a plain `status != :status` would skip them.
-- Arguments: {"id": "order-1", "status": "completed", "none": ""}
UPDATE orders SET status = :status
WHERE _id = :id AND coalesce(status, :none) != :status

-- ✅ GOOD: A frequent "presence" write that only touches the document when
-- the state actually changes. A missing or null value counts as the opposite
-- state (fallback = not online), so it is written.
-- Arguments: {"id": "device-1", "online": true, "fallback": false}
UPDATE devices SET online = :online
WHERE _id = :id AND coalesce(online, :fallback) != :online

-- ============================================================================
-- PATTERN 4: Nested field updates and UNSET
-- ============================================================================

-- ✅ GOOD: Update one nested field; missing intermediate objects are created.
-- Arguments: {"id": "order-1", "city": "Oslo"}
UPDATE orders SET shipping.address.city = :city WHERE _id = :id

-- ✅ GOOD: UNSET removes fields (they become MISSING). No INSERT policy and
-- no `SET obj = {...}` removes keys.
-- Arguments: {"id": "order-1"}
UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id

-- ============================================================================
-- PATTERN 5: Replacing an object deliberately
-- ============================================================================

-- ✅ GOOD: With the default strict mode, `SET address = :address` merges into
-- the existing object. To replace it completely, run UNSET and then SET
-- inside one transaction (hint: replaceAddress), so no reader sees the
-- document without an address. The field is still a map, so a nested edit
-- that another device makes at the same time can merge into the new object;
-- declare the field as REGISTER if that must never happen.
-- Arguments: {"id": "c1"}
UPDATE customers UNSET address WHERE _id = :id

-- Arguments: {"id": "c1", "address": {"street": "Main St", "city": "Oslo"}}
UPDATE customers SET address = :address WHERE _id = :id

-- ============================================================================
-- PATTERN 6: Saving a form
-- ============================================================================

-- ✅ GOOD: When the user edits a form, write only the fields the user changed.
-- Writing the whole in-memory copy back, even with DO UPDATE_LOCAL_DIFF, would
-- also write a stale value of a field that another device changed after the
-- form was loaded, because the stale value differs from the stored one.
-- Arguments: {"id": "order-1", "status": "ready", "none": ""}
UPDATE orders SET status = :status
WHERE _id = :id AND coalesce(status, :none) != :status
