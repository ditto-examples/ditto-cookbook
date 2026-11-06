-- Ditto SDK 5.2.0 (every SDK)
--
-- COUNTER fields
--
-- A COUNTER combines increments and decrements from all devices, so
-- concurrent changes add up instead of overwriting each other. Counter
-- operations use APPLY, not SET:
--   APPLY f INCREMENT BY n   (negative n decrements; n must be an integer)
--   APPLY f RESTART WITH n   (set a value; concurrent RESTARTs: last write wins;
--                             increments the restarting device has not received
--                             yet are discarded)
--   APPLY f RESTART          (reset to zero)
-- Declarations use the COLLECTION keyword: UPDATE COLLECTION t (f COUNTER) ...
-- This file declares the counter in every statement, which works with strict
-- mode on or off and keeps declarations consistent.
--
-- Guide: § Counters, § Writing documents that contain counters

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Declared counter
-- ---------------------------------------------------------------------------

-- An INSERT that sets an initial counter value requires the declaration.
-- Arguments: {"product": {"_id": "p1", "name": "Pen", "viewCount": 0}}
INSERT INTO COLLECTION products (viewCount COUNTER) DOCUMENTS (:product)

-- Arguments: {"id": "p1"}
UPDATE COLLECTION products (viewCount COUNTER)
APPLY viewCount INCREMENT BY 1
WHERE _id = :id

-- Read with the same declaration.
-- Arguments: {"id": "p1"}
SELECT * FROM COLLECTION products (viewCount COUNTER) WHERE _id = :id

-- ✅ GOOD: Each device records its own sales; concurrent decrements combine.
-- APPLY can be combined with SET in one statement; write APPLY first.
-- Arguments: {"id": "sku-1001", "now": "2026-10-08T10:30:00.123Z"}
UPDATE COLLECTION inventory (stockCount COUNTER)
APPLY stockCount INCREMENT BY -1
SET lastAdjustedAt = :now
WHERE _id = :id

-- ✅ GOOD: RESTART WITH for an occasional correction by one authority, such
-- as recalibrating stock after a physical count, run only while every device
-- that changes the counter is online and in sync.
--
-- Note (SDK 5.1.0 and 5.2.0): a RESTART discards every increment that this
-- device had not received when it ran the restart, including increments that
-- other devices make later (by the clock) until the restart reaches them. If
-- tills keep selling offline during a recount, store recounts and sales as
-- event documents and derive the stock instead.
-- Arguments: {"id": "sku-1001", "counted": 42}
UPDATE COLLECTION inventory (stockCount COUNTER)
APPLY stockCount RESTART WITH :counted
WHERE _id = :id

-- ✅ GOOD: A document with a counter that every device creates on its own,
-- such as an item's stock on first launch, is seeded with INITIAL DOCUMENTS.
-- A plain INSERT (or ON ID CONFLICT DO NOTHING) on a second device restarts
-- the counter and discards sales that the first device has not synced yet.
-- Arguments: {"item": {"_id": "sku-1001", "stockCount": 50}}
INSERT INTO COLLECTION inventory (stockCount COUNTER) INITIAL DOCUMENTS (:item)

-- ---------------------------------------------------------------------------
-- ❌ BAD: Counter mistakes
-- ---------------------------------------------------------------------------

-- ❌ BAD: Read-modify-write on a register. Two devices that each sell one
-- item from a stock of 10 concurrently both write 9; after sync the stock is
-- 9 instead of 8.
-- Arguments: {"id": "sku-1001"}
UPDATE inventory SET stockLevel = stockLevel - 1 WHERE _id = :id

-- ❌ BAD: An undeclared INSERT stores viewCount as a REGISTER. A later
-- `APPLY viewCount INCREMENT BY 1` starts a separate counter at 0, so the
-- value becomes 1, not 6.
-- Arguments: {"product": {"_id": "p2", "viewCount": 5}}
INSERT INTO products DOCUMENTS (:product)

-- ❌ BAD: Overwriting a counter with SET. Use APPLY ... RESTART WITH.
-- Arguments: {"id": "p1"}
UPDATE products SET viewCount = 0 WHERE _id = :id

-- Other poor fits for COUNTER (not shown as statements):
-- - Unique sequence numbers (invoice or ticket numbers): two offline devices
--   both produce the same "next" number. Use UUIDs plus a display label.
-- - Balances that must be validated ("never below zero"): a counter cannot
--   enforce a constraint. Record transactions as events and validate when you
--   derive the balance.
-- - Values derivable from stored documents: use SELECT COUNT(*) ...
-- - Fractional amounts: COUNTER is integer-only (INCREMENT BY 1.5 fails with
--   "Expected 1.5 to be an integer value"). Count in minor units such as cents.
-- - Mixing COUNTER and the legacy PN_INCREMENT operator on one field.

-- ❌ BAD: Re-importing the stock list with an upsert. The imported value
-- restarts the counter like RESTART WITH and discards the sales that offline
-- tills have not synced yet, with DO UPDATE_LOCAL_DIFF as well. Leave
-- stockCount out of imported documents and apply the difference with
-- APPLY stockCount INCREMENT BY.
-- Arguments: {"item": {"_id": "sku-1001", "name": "Paper cups", "stockCount": 40}}
INSERT INTO COLLECTION inventory (stockCount COUNTER) DOCUMENTS (:item) ON ID CONFLICT DO UPDATE
