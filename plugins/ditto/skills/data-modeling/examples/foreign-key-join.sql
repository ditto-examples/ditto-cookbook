-- Ditto SDK 5.2.0 (every SDK)
--
-- Separate collections with foreign keys and JOIN (SDK 5.1+)
--
-- Use a separate collection when data is accessed independently, shared by
-- many parents, unbounded, governed by different permissions, or written by
-- different writers. JOIN then reads the related documents locally.
--
-- JOIN rules:
-- - Local data only: it never fetches documents from other peers, so every
--   joined collection needs its own subscription.
-- - Not allowed in subscriptions (`Unsupported feature: Joining`) and not on
--   Ditto Server.
-- - The inner collection needs an index on the join key, or the join must be
--   on its `_id`. Otherwise the query fails with
--   `Joining to "..." disallowed without appropriate index support`.
--
-- Guide: § Relationships: Embedding, Separate Collections, and JOIN,
--   § Joining Collections (SDK 5.1+)

-- Documents:
--   orders:     {"_id": "order-1", "storeId": "store-12", "status": "open"}
--   orderItems: {"_id": "item-1", "orderId": "order-1", "storeId": "store-12",
--                "productId": "p1", "quantity": 2}
--   products:   {"_id": "p1", "name": "Espresso", "priceCents": 350}
--
-- storeId is copied into orderItems because a subscription can filter only on
-- fields of its own collection.

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Index the join key, subscribe per collection
-- ---------------------------------------------------------------------------

-- At startup, in the app- or feature-level service that owns the
-- subscriptions (not in a screen). Indexes persist; IF NOT EXISTS makes this
-- idempotent at every startup.
CREATE INDEX IF NOT EXISTS idx_orderItems_orderId ON orderItems (orderId)

-- Subscriptions, one per collection, cancelled together when the user leaves
-- the store:
-- Arguments: {"storeId": "store-12"}
SELECT * FROM orders WHERE storeId = :storeId

-- Arguments: {"storeId": "store-12"}
SELECT * FROM orderItems WHERE storeId = :storeId

SELECT * FROM products

-- ✅ GOOD: Parent and children created together are written with these two
-- statements in one transaction, so local observers never see one without
-- the other.
-- Arguments: {"order": {"_id": "order-1", "storeId": "store-12", "status": "open", "createdAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO orders DOCUMENTS (:order)

-- Arguments: {"items": [{"_id": "item-1", "orderId": "order-1", "storeId": "store-12", "productId": "p1", "quantity": 2}]}
INSERT INTO orderItems DOCUMENTS (:items)

-- ✅ GOOD: One-off join. Drives from orderItems through the
-- idx_orderItems_orderId index and looks up each product by _id (no extra
-- index needed). Qualify every field with its alias and alias colliding names
-- such as _id.
-- Arguments: {"orderId": "order-1"}
SELECT i._id AS itemId, i.quantity, p.name, p.priceCents
FROM orderItems AS i
JOIN products AS p ON p._id = i.productId
WHERE i.orderId = :orderId
ORDER BY p.name

-- ✅ GOOD: LEFT JOIN keeps a parent whose children have not synced yet (or do
-- not exist). Right-side fields are MISSING for unmatched rows. orderItems is
-- the inner collection, so it uses the idx_orderItems_orderId index.
-- Arguments: {"storeId": "store-12"}
SELECT o._id AS orderId, o.status, i.productId, i.quantity
FROM orders AS o
LEFT JOIN orderItems AS i ON i.orderId = o._id
WHERE o.storeId = :storeId AND o.status = 'open'
ORDER BY o._id, i.productId

-- ✅ GOOD: A screen can observe the same join. The observer delivers a new
-- result when a change in any of the joined collections changes the joined
-- rows. Register and release it like any other observer
-- (observer-patterns-good in the query-sync Skill's examples/<sdk>/); when
-- the order ID can change while the screen is shown, register the observer
-- again for the new ID.

-- ---------------------------------------------------------------------------
-- ❌ BAD: Common JOIN mistakes
-- ---------------------------------------------------------------------------

-- ❌ BAD: A JOIN in a subscription. Subscriptions accept only
-- `SELECT * FROM <collection> [WHERE ...]`; registering this fails with
-- `Unsupported feature: Joining`. Subscribe to each collection instead.
-- Subscription:
-- Arguments: {"orderId": "order-1"}
SELECT * FROM orderItems AS i JOIN products AS p ON p._id = i.productId
WHERE i.orderId = :orderId

-- ❌ BAD: Joining to customers on a non-ID field without an index fails before
-- it runs (`Joining to "c" disallowed without appropriate index support`).
-- Fix: `CREATE INDEX IF NOT EXISTS idx_customers_email ON customers (email)`, or
-- join on c._id. Do not silence the error with `USE INDEX ''` on a large
-- collection: every outer row would then scan the whole inner collection.
SELECT o._id, c.name FROM orders AS o
JOIN customers AS c ON c.email = o.customerEmail

-- ❌ BAD: Assuming JOIN fetches related documents from other peers. Without a
-- products subscription, products that never synced to this device are simply
-- absent: inner-join rows disappear and LEFT JOIN fields are MISSING. The
-- orderLines query above is correct; the mistake is the missing subscription.
