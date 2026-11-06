-- Ditto SDK 5.2.0 (every SDK)
--
-- Current state plus history (two collections)
--
-- When you need both the latest value with low latency and a complete
-- history, write each change to two collections in one transaction:
--   vehicles:         one bounded document per entity (real-time screens)
--   vehiclePositions: one append-only document per change (analysis)
--
-- Guide: § Event History and Audit Logs, § Transactions

-- ✅ GOOD: Both writes, with these two statements, in one transaction, so
-- local observers never see one without the other. The position is declared
-- as a REGISTER in every statement because latitude and longitude from two
-- readings must never mix. recordedAt is sorted and range-filtered, so it
-- comes from the fixed-precision helper, and both documents use one value.
-- Arguments: {"event": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "vehicleId": "truck-7", "position": {"lat": 38.71, "lon": -9.14}, "recordedAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO vehiclePositions DOCUMENTS (:event)

-- Arguments: {"vehicle": {"_id": "truck-7", "position": {"lat": 38.71, "lon": -9.14}, "lastSeenAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO COLLECTION vehicles (position REGISTER)
DOCUMENTS (:vehicle)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- Reads the current state with the same REGISTER declaration.
SELECT * FROM COLLECTION vehicles (position REGISTER) ORDER BY _id

-- History for one vehicle, oldest first.
-- Arguments: {"vehicleId": "truck-7", "since": "2026-10-08T00:00:00.000Z"}
SELECT * FROM vehiclePositions
WHERE vehicleId = :vehicleId AND recordedAt >= :since
ORDER BY recordedAt ASC, _id ASC

-- Devices subscribe to what they need: a live map only to vehicles; an
-- analysis tool to both. Ditto's transactions documentation
-- (https://docs.ditto.live/sdk/latest/crud/transactions) describes that a
-- peer that subscribes to only part of the documents a transaction changed
-- receives (and can relay) only that part, so peers that need both halves
-- together subscribe to both collections.
-- Subscriptions:
SELECT * FROM vehicles

-- Arguments: {"since": "2026-10-08T00:00:00.000Z"}
SELECT * FROM vehiclePositions WHERE recordedAt >= :since

-- ❌ BAD: The same two writes as separate statements outside a transaction. A
-- local observer can see the history entry without the matching current
-- state. The undeclared vehicles upsert also stores position as a MAP, which
-- conflicts with the REGISTER declaration used elsewhere.
-- Arguments: {"vehicle": {"_id": "truck-7", "position": {"lat": 38.71, "lon": -9.14}, "lastSeenAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO vehicles DOCUMENTS (:vehicle) ON ID CONFLICT DO UPDATE
