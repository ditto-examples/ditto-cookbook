// Handling QueryResult and QueryResultItem in Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0).
//
// Rules:
// - result.items is an array of QueryResultItem. item.value decodes the row on
//   first access and then returns THE SAME object on every read. Changes to it
//   stay in that object but never reach the store: write with UPDATE.
// - Convert rows to plain values or models right away; do not keep results or
//   items in caches or state.
// - result.mutatedDocumentIDsV2() builds a new array on every call; call it once.
//   There is no mutatedDocumentIDs() in JavaScript. IDs are strings, or objects
//   for composite IDs.
// - result.commitID is a bigint for local writes and null for reads.
// - Integers of 2^53 or more come back as bigint, which JSON.stringify cannot
//   write without a replacer; item.jsonString() writes exact integers.
//
// Guide: § Query results in JavaScript, § Working with Query Results

// A plain model built from a result row.
export class Order {
  constructor({ id, status, total }) {
    this.id = id;
    this.status = status;
    this.total = total;
  }

  static fromValue(value) {
    return new Order({
      id: value._id,
      status: typeof value.status === 'string' ? value.status : 'unknown',
      total: typeof value.total === 'number' ? value.total : 0,
    });
  }
}

// ✅ GOOD: Project only the needed fields, iterate once, return models.
export async function loadOpenOrders(ditto) {
  const result = await ditto.store.execute(
    'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY _id',
    { status: 'open' },
  );
  return result.items.map((item) => Order.fromValue(item.value));
}

// ✅ GOOD: Read a single row and keep the model, not the item.
export async function loadOrder(ditto, id) {
  const result = await ditto.store.execute('SELECT _id, status, total FROM orders WHERE _id = :id', { id });
  const item = result.items[0];
  return item ? Order.fromValue(item.value) : null;
}

// ✅ GOOD: Inspect which documents changed, calling mutatedDocumentIDsV2() once.
export async function closeOrders(ditto, ids) {
  const result = await ditto.store.execute('UPDATE orders SET status = :status WHERE _id IN :ids', {
    status: 'closed',
    ids,
  });
  const changedIds = result.mutatedDocumentIDsV2();
  // Nothing to track when no document changed (for example, unknown IDs).
  return { changedIds, commitId: changedIds.length === 0 ? null : result.commitID };
}

// ✅ GOOD: Alternative encoding, for example to send rows to a worker or a
// server as plain strings with exact 64-bit integers.
export async function openOrdersAsJson(ditto) {
  const result = await ditto.store.execute('SELECT * FROM orders WHERE status = :status', { status: 'open' });
  return result.items.map((item) => item.jsonString());
}

// ✅ GOOD: Writes bigint values as strings, so that JSON.stringify accepts any row.
export const jsonReplacer = (key, value) => (typeof value === 'bigint' ? value.toString() : value);

// ✅ GOOD: A cache holds plain models, never query results.
export class OrderCache {
  #orders = new Map();

  update(result) {
    this.#orders = new Map(result.items.map((item) => [item.value._id, Order.fromValue(item.value)]));
    // The QueryResult goes out of scope after this method returns.
  }

  get(id) {
    return this.#orders.get(id) ?? null;
  }
}

// ❌ BAD: Keeping QueryResultItem objects alive. They keep the decoded rows in
// memory, and they are not plain values to compare or send elsewhere.
export class RetainingCache {
  #items = [];

  update(result) {
    this.#items = result.items;
  }

  get count() {
    return this.#items.length;
  }
}

// ❌ BAD: Editing item.value to change a document. The change stays in the
// result object and never reaches the store; calling mutatedDocumentIDsV2()
// twice builds the array twice.
export async function wastefulAccess(ditto, id) {
  const result = await ditto.store.execute('SELECT * FROM orders WHERE _id = :id', { id });
  if (result.items.length > 0) result.items[0].value.status = 'closed'; // never stored
  const write = await ditto.store.execute("UPDATE orders SET seen = true WHERE _id = :id", { id });
  if (write.mutatedDocumentIDsV2().length > 0) console.log(write.mutatedDocumentIDsV2());
}
