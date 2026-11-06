-- Ditto SDK 5.2.0 (every SDK)
--
-- Composite (object) document IDs
--
-- Permission rules are queries on _id and its subfields. A hierarchical
-- composite _id lets you grant access at any level (a region, a store),
-- and the same subfields filter subscriptions and queries and can be indexed.
-- Put only immutable attributes into _id. Key order inside a composite _id
-- does not matter.
--
-- Guide: § Composite IDs for permission scoping and grouping,
--   § Schema Evolution

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Scope fields plus a UUID
-- ---------------------------------------------------------------------------

-- Arguments: {"order": {"_id": {"region": "emea", "storeId": "store-12", "orderId": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f"}, "status": "open", "createdAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO orders DOCUMENTS (:order)

-- Index the subfield used for local queries (indexes persist; create once).
CREATE INDEX IF NOT EXISTS idx_orders_id_storeId ON orders (_id.storeId)

-- Subscription: each store device syncs only its own store's orders. The
-- caller owns the subscription and cancels it when it is no longer needed.
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE _id.storeId = :storeId

-- Filtering on the complete _id value uses a direct ID lookup.
-- Arguments: {"id": {"region": "emea", "storeId": "store-12", "orderId": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f"}}
SELECT * FROM orders WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ❌ BAD: Mutable attributes inside _id
-- ---------------------------------------------------------------------------

-- ❌ BAD: assignedTo can change, but _id is immutable
-- (`UPDATE ... SET _id = ...` fails). Reassigning the task would require
-- copying it to a new document. Keep mutable values as regular fields.
-- Arguments: {"task": {"_id": {"taskId": "task-1", "assignedTo": "user-7"}, "title": "Restock shelf 4"}}
INSERT INTO tasks DOCUMENTS (:task)

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Schema version in a composite _id
-- ---------------------------------------------------------------------------

-- Subscription: because _id is immutable, an UPDATE cannot change a document's
-- version by accident. Each app version subscribes only to the versions it
-- understands.
-- Arguments: {"version": 2}
SELECT * FROM cars WHERE _id.schemaVersion = :version

-- Arguments: {"car": {"_id": {"id": "car-1", "schemaVersion": 2}, "make": "Hyundai", "fuelEconomyMpg": 32}}
INSERT INTO cars DOCUMENTS (:car)
