-- Ditto SDK 5.2.0 (every SDK)
--
-- Server-driven retention with a Ditto Server (formerly Big Peer).
--
-- Guide: § Flag-based eviction
--        § Deleting on the Ditto Server
--        § Soft delete, subscriptions, and cleanup
--
-- Division of work documented by the guide:
-- - The Ditto Server (for example through its HTTP API) or an authorized
--   device marks documents that devices no longer need with
--   evictionFlag = true. The server can make sure documents have synced
--   before they are marked.
-- - Devices subscribe to unflagged documents and EVICT the flagged ones
--   locally. The Ditto Server keeps the data.
-- - Permanent removal (for example of soft-deleted records after the
--   retention period, Variant A in soft-delete-relay.sql) runs as DELETE on
--   the Ditto Server, in batches of 30,000 documents or fewer. The DELETE
--   syncs to every device that has the documents.
--
-- The HTTP API endpoint and its authentication are described in the Ditto
-- Server documentation; this file only shows the DQL.

-- ============================================================================
-- Statements executed on the Ditto Server (for example through the HTTP API)
-- ============================================================================

-- Marks documents older than :cutoff so devices evict them.
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff

-- Permanently removes soft-deleted orders after the retention period
-- (Variant A soft-delete cleanup). Repeat until no documents are affected.
-- Run it only once flagged documents are no longer edited (husk documents).
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
DELETE FROM orders WHERE isDeleted = true AND deletedAt < :cutoff LIMIT 30000

-- ============================================================================
-- Optional: an authorized device marks the documents instead of the server
-- ============================================================================

-- Run on a device whose permissions allow writing evictionFlag, for example a
-- back-office tablet. Queries run against the local store, so the device can
-- only mark documents it already has. The cutoff (now minus the retention
-- period) uses the same fixed-precision format as createdAt.
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
UPDATE orders SET evictionFlag = true WHERE createdAt < :cutoff

-- ============================================================================
-- Device side: subscribe to unflagged documents, evict flagged ones
-- ============================================================================

-- Register once at startup, before sync starts. coalesce() includes documents
-- that do not have the flag yet.
-- Subscription:
SELECT * FROM orders WHERE coalesce(evictionFlag, false) = false

-- On a schedule, at most about once per day. The subscription never matches
-- flagged documents, so it does not need to be cancelled first.
EVICT FROM orders WHERE evictionFlag = true RETURNING COUNT(*) AS evicted

-- ============================================================================
-- ❌ Anti-pattern: permanent deletion from every device
-- ============================================================================

-- ❌ BAD: DELETE removes the records for every peer, including the Ditto
-- Server, and risks husk documents when other devices still edit them.
-- Use it only when the records must disappear from the whole system.
-- ✅ FIX: Flag on the server and EVICT on devices; DELETE on the Ditto Server.
-- Arguments: {"cutoff": "2026-09-08T00:00:00.000Z"}
DELETE FROM orders WHERE createdAt < :cutoff
