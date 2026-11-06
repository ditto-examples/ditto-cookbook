-- Ditto SDK 5.2.0 (every SDK)
--
-- Changing a document ID
--
-- `_id` is immutable: `UPDATE orders SET _id = ...` fails with
-- "The document id `_id` cannot be modified". To "change" an ID, copy the
-- document to a new _id and remove the old one in one transaction. Removing
-- the old document has the usual deletion trade-offs (tombstones, or a soft
-- delete flag), and every reference must be updated, so choose IDs carefully
-- up front.
--
-- A query result contains plain values, not CRDT types. Declare the same types
-- in the SELECT and in the INSERT that every other statement on the collection
-- uses; otherwise the copy stores a counter as a plain number and an attachment
-- token as a map, and a field read with a different declaration (for example,
-- a MAP read as a REGISTER) is missing from the copy. (With
-- DQL_STRICT_MODE = true, declare the MAP fields too.)
--
-- Guide: § IDs are immutable, § DELETE and Tombstones, § Soft Delete

-- ✅ GOOD: Copy an order to a new ID, repoint its events, and delete the
-- original, with these four statements in one transaction. The app reads the
-- old document, replaces its _id in the copy, and inserts it. Both the SELECT
-- and the INSERT declare the order's COUNTER, ATTACHMENT, and REGISTER fields
-- exactly as the other statements on orders do, so the copy keeps their CRDT
-- types. Undeclared objects such as shippingAddress are MAPs.
-- Arguments: {"id": "order-1"}
SELECT * FROM COLLECTION orders
  (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
WHERE _id = :id

-- Arguments: {"doc": {"_id": "order-1-moved", "status": "open", "printCount": 2}}
INSERT INTO COLLECTION orders
  (printCount COUNTER, receipt ATTACHMENT, deliveryLocation REGISTER)
DOCUMENTS (:doc)

-- Arguments: {"newId": "order-1-moved", "oldId": "order-1"}
UPDATE orderEvents SET orderId = :newId WHERE orderId = :oldId

-- Arguments: {"id": "order-1"}
DELETE FROM orders WHERE _id = :id

-- Variant for shared records that several devices edit: soft-delete the old
-- document (a flag plus a UTC timestamp) instead of deleting it, so devices
-- that stay offline longer than the tombstone TTL still learn about it. The
-- copy carries isDeleted = false. In one transaction, after the same SELECT
-- and INSERT:
-- Arguments: {"id": "order-1", "deletedAt": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id

-- Readers then exclude soft-deleted documents; a missing flag counts as
-- "not deleted".
SELECT * FROM orders WHERE coalesce(isDeleted, false) = false
ORDER BY createdAt DESC
