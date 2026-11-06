-- Ditto SDK 5.2.0 (every SDK)
--
-- Embedding related data (the default relationship model)
--
-- Embed a sub-entity in its parent when it is read together with the parent,
-- owned by exactly one parent, small and bounded, covered by the same
-- permissions, and edited by the same group of writers. Store embedded
-- collections as maps keyed by ID, never as arrays.
--
-- Guide: § Relationships: Embedding, Separate Collections, and JOIN

-- Order with embedded line items:
--
-- {
--   "_id": "order-1",
--   "storeId": "store-12",
--   "status": "open",
--   "createdAt": "2026-10-08T10:00:00.000Z",
--   "items": {
--     "9b2f6c1e-...": {"productId": "p1", "name": "Espresso",
--                      "unitPriceCents": 350, "quantity": 2}
--   }
-- }
--
-- - One subscription syncs the order with all of its items.
-- - Every item write is an atomic update of one document.
-- - Add-wins maps merge concurrent edits to different items, so concurrent
--   edits alone are not a reason to split items into a separate collection.

-- Subscription, registered once by an app- or feature-level service, not by
-- a screen:
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId

-- Arguments: {"order": {"_id": "order-1", "storeId": "store-12", "status": "open", "createdAt": "2026-10-08T10:00:00.000Z"}}
INSERT INTO orders DOCUMENTS (:order)

-- Adds a line item. The unit price is a snapshot copied at the time of sale,
-- so later catalog price changes do not alter this order.
-- Arguments: {"patch": {"_id": "order-1", "items": {"9b2f6c1e-2d4a-4f3b-8c5d-6e7f8a9b0c1d": {"productId": "p1", "name": "Espresso", "unitPriceCents": 350, "quantity": 2}}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- One read returns the order and all of its items.
-- Arguments: {"id": "order-1"}
SELECT * FROM orders WHERE _id = :id

-- When to split instead (see foreign-key-join.sql):
-- - The data is accessed independently of the parent.
-- - It is shared by many parents (products referenced by many orders).
-- - It grows without bound (events, readings, messages).
-- - It needs different permissions or is written by different writers.
-- Splitting only because JOIN exists is not a reason on its own.
