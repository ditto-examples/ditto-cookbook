-- Ditto SDK 5.2.0 (every SDK)
--
-- Flag-based eviction: devices subscribe only to unflagged documents and
-- evict the flagged ones.
--
-- Guide: § Flag-based eviction
--
-- Key rules:
-- - A central component decides what is no longer needed and sets
--   evictionFlag = true. This approach works well when a Ditto Server is
--   available, because the server can make sure documents have synced before
--   they are marked (see ttl-eviction-ditto-server.sql).
-- - Devices subscribe with coalesce(evictionFlag, false) = false, so documents
--   without the field are included.
-- - Because the subscription never matches flagged documents, it does not
--   need to be cancelled and re-registered before each eviction.
-- - Do not confuse this with soft delete: an eviction flag means "this device
--   no longer needs it" and SHOULD leave the subscription; soft-deleted
--   documents stay in the subscriptions of devices that relay data, so they
--   can pass the deletion flag on (see soft-delete-relay.sql for Variant A
--   and Variant B).

-- ✅ GOOD: Subscribe to unflagged documents only. Register once at startup,
-- in a service that owns the subscription.
-- Subscription:
SELECT * FROM orders WHERE coalesce(evictionFlag, false) = false

-- ✅ GOOD: Evict the flagged documents, at most about once per day. The
-- subscription stays registered: it does not match flagged documents, so they
-- do not sync back. RETURNING COUNT(*) reports how many were evicted.
EVICT FROM orders WHERE evictionFlag = true RETURNING COUNT(*) AS evicted

-- ❌ BAD: `evictionFlag != true` excludes documents where the field is
-- missing or null, so documents written without the flag never sync to this
-- device.
-- Subscription:
SELECT * FROM orders WHERE evictionFlag != true -- lint-ignore

-- ❌ BAD: The subscription matches flagged documents, so evicting them makes
-- connected peers sync them straight back.
-- Subscription:
SELECT * FROM orders

EVICT FROM orders WHERE evictionFlag = true
