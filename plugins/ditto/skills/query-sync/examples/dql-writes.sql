-- DQL write patterns for Ditto SDK 5.2.0 (every SDK).
--
-- Covers: INSERT with parameters, ON ID CONFLICT policies, field-level UPDATE,
-- UNSET, object merge semantics (default DQL_STRICT_MODE = false),
-- RETURNING (SDK 5.1+), and DELETE / EVICT by ID.
--
-- Statements that fail outright are described in comments only:
-- - SET _id = ... : "The document id `_id` cannot be modified".
-- - Setting the same path twice in one statement: "More than one modification
--   specified for the path ...".
-- - SET items[0] = ... : array elements cannot be assigned (syntax error).
--
-- Every timestamp that is sorted or compared comes from one fixed-precision
-- UTC helper ("IDs and Timestamps in <SDK>" on your SDK's page).
--
-- Guide: § INSERT and Conflict Handling, § ON ID CONFLICT, § UPDATE,
--   § Assigning an object merges it, § RETURNING (SDK 5.1+), § DELETE and EVICT

-- ---------------------------------------------------------------------------
-- INSERT and ON ID CONFLICT
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Several documents in one atomic statement, as an array parameter.
-- DO UPDATE_LOCAL_DIFF writes only fields that differ; unchanged documents
-- are a no-op (no mutation, observers do not fire). Read the result's mutated
-- document IDs once and keep them.
-- Arguments: {"products": [{"_id": "p1", "name": "Pen", "priceCents": 250}, {"_id": "p2", "name": "Ink", "priceCents": 900}]}
INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ✅ GOOD: "Create if absent" leaves an existing document unchanged.
-- Arguments: {"draft": {"_id": "draft-1", "createdAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO drafts DOCUMENTS (:draft) ON ID CONFLICT DO NOTHING

-- ✅ GOOD: Seed defaults on every launch; existing (possibly edited) data is kept.
-- Arguments: {"defaults": {"_id": "app", "theme": "light", "currency": "USD"}}
INSERT INTO settings INITIAL DOCUMENTS (:defaults)

-- ❌ BAD: Periodic re-upsert with DO UPDATE. Every supplied field is
-- rewritten even when identical, a mutation is recorded, and observers can
-- fire again.
-- Arguments: {"products": [{"_id": "p1", "name": "Pen", "priceCents": 250}]}
INSERT INTO products DOCUMENTS (:products) ON ID CONFLICT DO UPDATE

-- ❌ BAD: Expecting DO UPDATE to replace the document. It merges: fields
-- missing from the new document (here name) stay, nested objects merge.
-- Starting from {"_id": "p1", "name": "Pen", "price": 5,
--                "address": {"city": "Oslo", "zip": "0150"}}, the stored document is:
-- {"_id": "p1", "name": "Pen", "price": 6,
--  "address": {"city": "Oslo", "zip": "0150", "street": "Main St"}}
-- Arguments: {"doc": {"_id": "p1", "price": 6, "address": {"street": "Main St"}}}
INSERT INTO products DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE

-- ---------------------------------------------------------------------------
-- UPDATE
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Change only the fields that changed, and skip documents that
-- already have the value. coalesce() keeps missing/null status eligible. The
-- result's mutated document IDs tell whether anything changed.
-- Arguments: {"id": "order-1", "status": "completed", "none": "", "now": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET status = :status, updatedAt = :now
WHERE _id = :id AND coalesce(status, :none) != :status

-- ✅ GOOD: Nested paths; missing intermediate objects are created.
-- Arguments: {"id": "order-1", "city": "Oslo"}
UPDATE orders SET shipping.address.city = :city WHERE _id = :id

-- ✅ GOOD: UNSET removes fields (they become MISSING). Writing null would
-- keep the field present with a null value.
-- Arguments: {"id": "order-1"}
UPDATE orders UNSET discountCode, pricing.discount WHERE _id = :id

-- ✅ GOOD: Replace an object: UNSET it, then SET the new value, as two
-- statements inside one transaction (with a hint such as
-- replaceCustomerAddress). A single SET address = :address would merge into
-- the existing object. The field is still a map, so a nested edit that another
-- device makes at the same time can merge into the new object; declare the
-- field as REGISTER if that must never happen.
-- Arguments: {"id": "c1"}
UPDATE customers UNSET address WHERE _id = :id

-- Arguments: {"id": "c1", "address": {"street": "Main St", "city": "Oslo"}}
UPDATE customers SET address = :address WHERE _id = :id

-- ❌ BAD: SET obj = {} does not clear an object (the merge adds no keys and
-- removes none). Use UNSET address.
-- Arguments: {"id": "c1"}
UPDATE customers SET address = {} WHERE _id = :id

-- ❌ BAD: Read-modify-write of the whole document: read it, change status in
-- app code, and write every field back. Every field is written again, which
-- enlarges the change and lets unchanged values win merges against concurrent
-- edits on other devices. Use a field-level UPDATE.
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id

-- Arguments: {"order": {"_id": "order-1", "customerId": "c-1", "status": "completed", "total": 42}}
INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE

-- ---------------------------------------------------------------------------
-- RETURNING (SDK 5.1+)
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Update and read the new values in one statement (rows reflect the
-- documents after the update). Read the affected documents from the result's
-- items rather than from its mutated document IDs.
-- Arguments: {"ids": ["order-1"], "status": "shipped", "expected": "packed", "now": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET status = :status, shippedAt = :now
WHERE _id IN :ids AND status = :expected
RETURNING _id, status, shippedAt

-- ✅ GOOD: Keep a copy of what was deleted (rows reflect the documents
-- before removal), for an undo banner or an audit log.
-- Arguments: {"ids": ["draft-1"]}
DELETE FROM drafts WHERE _id IN :ids RETURNING *

-- ✅ GOOD: Aggregates in RETURNING summarize all affected documents; treat a
-- missing row or value as 0.
-- Arguments: {"now": "2026-10-08T10:30:00.123Z"}
DELETE FROM sessions WHERE expiresAt < :now RETURNING COUNT(*) AS removed

-- ❌ BAD: Write, then query again to read what was written. Use RETURNING.
-- Arguments: {"id": "order-1", "status": "shipped"}
UPDATE orders SET status = :status WHERE _id = :id

-- Arguments: {"id": "order-1"}
SELECT _id, status FROM orders WHERE _id = :id

-- ---------------------------------------------------------------------------
-- DELETE and EVICT by ID
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Select documents by ID with WHERE.
-- Arguments: {"ids": ["order-1", "order-2"]}
DELETE FROM orders WHERE _id IN :ids

-- ❌ BAD while any device runs SDK 5.1.0: there, DELETE (or EVICT) with
-- USE IDS and no WHERE predicate (no WHERE clause, or WHERE true) completes
-- without an error but removes nothing (SDK 5.2.0 removes the listed
-- documents). WHERE _id IN :ids works on every release.
DELETE FROM orders USE IDS 'order-1'
