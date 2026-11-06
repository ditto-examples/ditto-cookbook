-- Ditto SDK 5.2.0 (every SDK)
--
-- Event history and audit logs
--
-- Record each change as a new fact instead of overwriting one field.
--   Pattern 1: audit-log map inside the document (bounded history of one record)
--   Pattern 2: append-only event documents (unbounded or independently read)
--   Pattern 3: current state plus history; see two-collection-pattern.sql
-- Timestamps used as keys and sort values come from one fixed-precision UTC
-- helper ("IDs and Timestamps in <SDK>" on your SDK's page).
--
-- Guide: § Event History and Audit Logs

-- ---------------------------------------------------------------------------
-- ❌ BAD: Appending events to an array
-- ---------------------------------------------------------------------------

-- ❌ BAD: Arrays are registers. If two devices append concurrently, one of the
-- appended events is lost after sync. The array also grows the document
-- without bound.
-- Arguments: {"id": "order-1", "history": [{"type": "created"}, {"type": "confirmed"}]}
UPDATE orders SET history = :history WHERE _id = :id

-- ❌ BAD: Overwriting a single status field loses the history, and a late
-- write from a device that was offline can move the order backwards.
-- Arguments: {"id": "order-1", "status": "confirmed"}
UPDATE orders SET status = :status WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ✅ Pattern 1: Audit-log map keyed by timestamp
-- ---------------------------------------------------------------------------

-- Appends a status transition. Each device adds its own keys and the add-wins
-- map keeps every entry whose key is distinct. Two transitions recorded in the
-- same millisecond on different devices share a key and only one is kept; if
-- that matters, append a device identifier to the key
-- ("2026-10-08T10:05:12.437Z_t3"). The key is passed as data inside a partial
-- document; unchanged entries are not rewritten.
-- Arguments: {"patch": {"_id": "order-1", "statusLog": {"2026-10-08T10:05:12.437Z": "shipped"}}}
INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Derive the current status in app code as the most advanced state (in the
-- order created, confirmed, shipped, delivered) over the values of statusLog,
-- so a late write from a device that was offline cannot move the order
-- backwards. Other derivations: latest timestamp, earliest occurrence, or
-- custom rules.
-- Arguments: {"id": "order-1"}
SELECT statusLog FROM orders WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ✅ Pattern 2: Append-only event documents
-- ---------------------------------------------------------------------------

-- Each event is its own document with a UUID _id. Events are never updated,
-- so there is nothing to merge, and the parent stays small. storeId is copied
-- so that subscriptions can filter events by store.
-- Arguments: {"event": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "orderId": "order-1", "storeId": "store-12", "type": "shipped", "userId": "user-7", "occurredAt": "2026-10-08T10:05:12.437Z"}}
INSERT INTO orderEvents DOCUMENTS (:event)

-- Arguments: {"orderId": "order-1"}
SELECT * FROM orderEvents
WHERE orderId = :orderId
ORDER BY occurredAt ASC, _id ASC

-- Event collections grow forever: plan cleanup from the start. EVICT removes
-- documents from this device only. Subscribe to `occurredAt >= :cutoff` and
-- evict the complement (`occurredAt < :cutoff`) with the same cutoff, so no
-- active subscription syncs the evicted events back. Evict on a schedule, at
-- most about once per day.
-- Subscription:
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
SELECT * FROM orderEvents WHERE occurredAt >= :cutoff

-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
EVICT FROM orderEvents WHERE occurredAt < :cutoff
