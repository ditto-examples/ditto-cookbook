// Ditto SDK: 5.2.0 (JavaScript, @dittolive/ditto 5.2.0)
// UUIDs, display numbers, and fixed-precision UTC timestamps in JavaScript.
//
// The DQL that uses these values is in ../id-generation-patterns.sql and
// ../timestamps.sql.
//
// - crypto.randomUUID() returns a random (version 4) UUID; Node.js and
//   browsers provide it, React Native needs a polyfill or a package.
// - Date.prototype.toISOString() returns UTC with a Z and exactly three
//   fractional digits, so one helper keeps every timestamp sortable as text.
// - Never pass a Date object as an argument: it is stored as an empty object {}.
//
// Guide: § Document IDs, § Timestamps, § IDs and Timestamps in JavaScript

// ISO-8601 UTC string with exactly millisecond precision, for example
// "2026-10-08T10:30:00.123Z". Use it for every timestamp field that is sorted
// or compared.
export function utcTimestamp(time = new Date()) {
  return time.toISOString();
}

// A display label, not an identifier: never use it as _id or as a lookup key.
export const displayNumber = (terminalCode, localSequence) =>
  `${terminalCode}-${String(localSequence).padStart(4, '0')}`;

// ✅ GOOD: UUID v4 as _id, UTC timestamp from the helper.
export async function createOrder(ditto, storeId) {
  const orderId = crypto.randomUUID();
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: orderId, storeId, status: 'open', createdAt: utcTimestamp() },
  });
  return orderId;
}

// ✅ GOOD: The human-readable number in its own field, next to a UUID _id.
export async function createOrderWithLabel(ditto, { terminalCode, localSequence }) {
  const orderId = crypto.randomUUID();
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: orderId, displayNumber: displayNumber(terminalCode, localSequence), createdAt: utcTimestamp() },
  });
  return orderId;
}

// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
export const badSequentialId = (dailyCount) => `order-${dailyCount}`;

// ❌ BAD: Collides when two devices write within the same millisecond.
export const badTimestampId = () => `order-${Date.now()}`;

// ❌ BAD: A Date object is stored as {} (the time is lost), and
// toLocaleString() is local time without a zone, for which DQL date functions
// return MISSING. Always store utcTimestamp().
export async function markReadyIncorrectly(ditto, orderId) {
  await ditto.store.execute('UPDATE orders SET readyAt = :readyAt, readyLabel = :label WHERE _id = :id', {
    id: orderId,
    readyAt: new Date(),
    label: new Date().toLocaleString(),
  });
}
