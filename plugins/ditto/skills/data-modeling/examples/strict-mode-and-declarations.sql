-- Ditto SDK 5.2.0 (every SDK)
--
-- Strict mode and type declarations
--
-- The default is DQL_STRICT_MODE = false: objects are inferred as MAPs that
-- merge field by field. Keep the default for new apps. When only a few fields
-- need whole-object replacement, declare those fields as REGISTER in every
-- statement that touches them.
--
-- Guide: § Strict Mode, § Keep type declarations consistent

-- ---------------------------------------------------------------------------
-- ✅ GOOD: A REGISTER object with consistent declarations
-- ---------------------------------------------------------------------------

-- Keep every statement that touches customers.shippingAddress in one place
-- (a repository), so the `(shippingAddress REGISTER)` declaration cannot drift
-- apart. A concurrent edit can never produce a mix of two addresses (the
-- street of one and the city of the other): one whole address wins.
-- Arguments: {"customer": {"_id": "c1", "name": "Ana", "shippingAddress": {"street": "Rua Augusta 10", "city": "Lisbon"}}}
INSERT INTO COLLECTION customers (shippingAddress REGISTER)
DOCUMENTS (:customer)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Replaces the address as a whole: keys absent from the new address
-- disappear. To change one part of a REGISTER object, write the whole object
-- again; a nested `SET shippingAddress.city = ...` fails with
-- `Unsupported DML operation on REGISTER field`.
-- Arguments: {"id": "c1", "address": {"street": "Rua do Ouro 5", "city": "Lisbon"}}
UPDATE COLLECTION customers (shippingAddress REGISTER)
SET shippingAddress = :address
WHERE _id = :id

-- Arguments: {"id": "c1"}
SELECT * FROM COLLECTION customers (shippingAddress REGISTER)
WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ❌ BAD: Mixed declarations for one field
-- ---------------------------------------------------------------------------

-- ❌ BAD: The insert declares `obj` as REGISTER, the update leaves it
-- undeclared (so it is inferred as a MAP). Both CRDT values now exist under
-- the same key. An undeclared SELECT returns `"obj": {"a": 11}`, and `b`
-- seems to have vanished, even on a single device.
-- Arguments: {"doc": {"_id": "cfg", "obj": {"a": 1, "b": 2}}}
INSERT INTO COLLECTION settings (obj REGISTER) DOCUMENTS (:doc)

-- Arguments: {"id": "cfg"}
UPDATE settings SET obj.a = 11 WHERE _id = :id

-- ---------------------------------------------------------------------------
-- Opting in to strict mode (rarely)
-- ---------------------------------------------------------------------------

-- Choose DQL_STRICT_MODE = true only when whole-object replacement is needed
-- for almost every object and you will declare every MAP, COUNTER, and
-- ATTACHMENT field in every statement. Trade-offs:
-- - Undeclared MAP/COUNTER/ATTACHMENT fields are invisible to SELECT/WHERE.
-- - Note (SDK 5.1.0 and 5.2.0): with strict mode on, the query planner
--   does not use secondary indexes (EXPLAIN shows a collection scan); ID
--   lookups and full-collection COUNT(*) are not affected.
-- - Each peer interprets data with its own setting: use the same value on
--   every peer.
--
-- System parameters are not persisted: pass {"DQL_STRICT_MODE": true} in the
-- system parameters of DittoConfig on every open (SDK 5.2+), so that strict
-- mode is in effect before any query, observer, or sync runs ("DittoConfig in
-- <SDK>" on your SDK's page). On SDK 5.1, run this after every open, before
-- you start sync and before queries and observers:
ALTER SYSTEM SET DQL_STRICT_MODE = true

-- With strict mode on, a nested update requires a MAP declaration.
-- Arguments: {"id": "order-1", "source": "kiosk"}
UPDATE COLLECTION orders (metadata MAP) SET metadata.source = :source
WHERE _id = :id

-- Reads the current setting.
SHOW DQL_STRICT_MODE
