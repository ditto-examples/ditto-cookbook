-- Ditto SDK 5.2.0 (every SDK)
--
-- Derived values vs snapshot values
--
-- A stored value computed from other fields (line total, order total,
-- remaining stock) is a separate register. Two devices update the inputs
-- concurrently, each recomputes from its own partial view, and after the merge
-- the stored total can match neither. Compute derived values when you read.
-- Snapshot values (the price at the time of sale) are facts, not derivations:
-- copy them into the document.
--
-- Guide: § Document Structure

-- ---------------------------------------------------------------------------
-- ❌ BAD: Storing derived totals
-- ---------------------------------------------------------------------------

-- ❌ BAD: subtotalCents and totalCents are derived from items. If another
-- device adds an item concurrently, the merged items and the stored totals
-- disagree.
-- Arguments: {"id": "order-1", "quantity": 3, "subtotal": 1050, "total": 1155}
UPDATE orders
SET items.`item-1`.quantity = :quantity,
    subtotalCents = :subtotal,
    totalCents = :total
WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Store source data, derive at read time
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Only the input changes. Totals are computed from what merged.
-- Arguments: {"id": "order-1", "quantity": 3}
UPDATE orders SET items.`item-1`.quantity = :quantity WHERE _id = :id

-- Derive the subtotal in app code when you read the order: sum
-- unitPriceCents * quantity over the entries of `items`, and skip entries
-- whose price or quantity is missing or null (an entry removed on one device
-- while another device edited it) instead of failing. The code for each SDK:
-- "Query results in <SDK>" on your SDK's page.
-- Arguments: {"id": "order-1"}
SELECT items FROM orders WHERE _id = :id

-- ✅ GOOD: Aggregates over a collection are computed in DQL instead of being
-- maintained in a stored field or counter.
-- Arguments: {"storeId": "store-12", "status": "open"}
SELECT COUNT(*) AS openOrders FROM orders
WHERE storeId = :storeId AND status = :status

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Snapshot values are copied
-- ---------------------------------------------------------------------------

-- ✅ GOOD: The unit price at the time of sale is copied into the line item,
-- so a later price change in products does not alter historical orders. Read
-- the price and write the item in one transaction; fail if the product is not
-- available locally.
-- Arguments: {"id": "p1"}
SELECT priceCents FROM products WHERE _id = :id

-- Arguments: {"patch": {"_id": "order-1", "items": {"item-2": {"productId": "p1", "quantity": 2, "unitPriceCents": 350}}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Values that should always be current (a product's name on a catalog screen)
-- are not copied: reference the product by ID and JOIN at read time
-- (see foreign-key-join.sql).
