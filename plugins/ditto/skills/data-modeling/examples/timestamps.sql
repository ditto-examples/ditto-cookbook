-- Ditto SDK 5.2.0 (every SDK)
--
-- Timestamps
--
-- Store UTC with a zone designator (ISO-8601 string) or epoch milliseconds,
-- consistently within a field. A zone-less ISO string makes DQL date
-- functions return MISSING, without an error. Device clocks drift: treat
-- stored timestamps as approximate, never as the deciding factor between
-- conflicting writes.
--
-- ISO strings sort chronologically as text only when they share one format.
-- Produce every timestamp that is sorted or compared with one helper that
-- writes UTC with exactly millisecond precision ("2026-10-08T10:30:00.123Z").
-- Some standard formatters vary the precision: native Dart prints
-- microseconds but omits them when they are zero. The helper for each SDK:
-- "IDs and Timestamps in <SDK>" on your SDK's page.
--
-- Guide: § Timestamps

-- ✅ GOOD: UTC with a zone designator, from the fixed-precision helper.
-- Arguments: {"id": "order-1", "readyAt": "2026-10-08T10:30:00.123Z"}
UPDATE orders SET readyAt = :readyAt WHERE _id = :id

-- ❌ BAD: Local time without a zone. DQL date functions return MISSING for
-- it, and values written in different time zones do not compare correctly.
-- Convert to UTC first.
-- Arguments: {"id": "order-1", "readyAt": "2026-10-08T19:30:00.123456"}
UPDATE orders SET readyAt = :readyAt WHERE _id = :id

-- ✅ GOOD: Range filters compare with parameters in the same format and can
-- use an index on the timestamp field.
-- Arguments: {"since": "2026-10-01T00:00:00.000Z"}
SELECT * FROM orders WHERE createdAt >= :since ORDER BY createdAt DESC

-- ✅ GOOD: date_diff(date1, date2, part) returns date1 - date2 in the unit.
-- Arguments: {"now": "2026-10-08T10:30:00.123Z"}
SELECT _id, date_diff(:now, createdAt, 'minute') AS ageMinutes
FROM orders
WHERE status = 'open'

-- ❌ BAD: Picking the "winner" of two conflicting edits by comparing your own
-- timestamp fields (updatedAt) in app code. A device with a fast clock always
-- wins. Ditto already resolves concurrent register writes with its own Hybrid
-- Logical Clock; where order matters, model the data so the merge cannot go
-- wrong (a counter, a map keyed by ID, or an audit log with a derivation such
-- as "most advanced state").
