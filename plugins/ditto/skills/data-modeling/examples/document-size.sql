-- Ditto SDK 5.2.0 (every SDK)
--
-- Document size limits
--
-- Limits apply to the size of each stored document:
--   Soft limit 256 KiB (DOCUMENT_SIZE_SOFT_LIMIT_BYTES): write succeeds,
--     warning "exceeds recommended limit" is logged.
--   Hard limit 5 MiB (DOCUMENT_SIZE_HARD_LIMIT_BYTES): INSERT/UPDATE fails,
--     the stored document is unchanged. It is checked only for local writes:
--     concurrent offline additions on two devices can merge into a larger
--     document, after which every UPDATE of it fails until UNSET removes data
--     (SDK 5.1.0). On 5.2.0, a receiving device instead drops a change that
--     would exceed its hard limit and lists the document in
--     system:sync_degradations: the devices keep different versions, and
--     evicting the document on one of them discards that device's changes.
-- Design documents to stay well below 256 KiB; leave both limits at their
-- defaults.
--
-- Guide: § Document Size Limits

-- ---------------------------------------------------------------------------
-- ❌ BAD: Unbounded growth and binary data inside a document
-- ---------------------------------------------------------------------------

-- ❌ BAD: A nested map that receives a new reading forever. The document
-- eventually exceeds the soft limit and then the hard limit, and merge cost
-- grows with the document, not with the change.
-- Arguments: {"patch": {"_id": "device-1", "readings": {"reading-981": {"value": 21.5, "recordedAt": "2026-10-08T10:30:00.123Z"}}}}
INSERT INTO devices DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF

-- ❌ BAD: Base64-encoded files in a document field.
-- Arguments: {"id": "visit-1", "photo": "/9j/4AAQSkZJRgABAQ..."}
UPDATE visits SET photoBase64 = :photo WHERE _id = :id

-- ---------------------------------------------------------------------------
-- ✅ GOOD: Separate collection, attachments, error handling
-- ---------------------------------------------------------------------------

-- ✅ GOOD: Each reading is its own document with a reference to its parent.
-- Arguments: {"reading": {"_id": "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f", "deviceId": "device-1", "value": 21.5, "recordedAt": "2026-10-08T10:30:00.123Z"}}
INSERT INTO readings DOCUMENTS (:reading)

-- ✅ GOOD: Binary content goes into an ATTACHMENT field: create the attachment
-- with newAttachment and pass the returned object. Attachments are fetched
-- separately and do not count toward the document size.
-- Arguments: {"id": "visit-1", "photo": "<the attachment object>"}
UPDATE COLLECTION visits (photo ATTACHMENT) SET photo = :photo WHERE _id = :id

-- ✅ GOOD: Handle the hard-limit error at the call site that may produce it:
-- catch the SDK's error type around this execute, and report it in the app's
-- error UI. Its message contains "exceeds limit of ... bytes" for oversized
-- documents. The code for each SDK: "Executing DQL in <SDK>" on your SDK's page.
-- Arguments: {"id": "visit-1", "notes": "Customer asked for a follow-up visit."}
UPDATE visits SET notes = :notes WHERE _id = :id

-- ✅ GOOD: Estimate size with object_size(). It returns an approximate size of
-- the value, which can differ from the stored size, so leave headroom.
-- Arguments: {"id": "order-1"}
SELECT _id, object_size(o) AS approxBytes FROM orders AS o WHERE _id = :id

-- ✅ GOOD: To bring an oversized document back under the limits, remove the
-- data that made it grow: move the nested readings to their own collection
-- and remove them from the device document with UNSET, in one transaction.
-- The app turns each entry of `readings` into a document with the entry's key
-- as _id and the parent's ID as deviceId.
-- Arguments: {"id": "device-1"}
SELECT readings FROM devices WHERE _id = :id

-- Arguments: {"documents": [{"_id": "reading-981", "deviceId": "device-1", "value": 21.5, "recordedAt": "2026-10-08T10:30:00.123Z"}]}
INSERT INTO readings DOCUMENTS (:documents) ON ID CONFLICT DO NOTHING

-- Arguments: {"id": "device-1"}
UPDATE devices UNSET readings WHERE _id = :id
