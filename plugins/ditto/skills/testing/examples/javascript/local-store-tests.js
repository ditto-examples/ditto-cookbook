// Ditto SDK: 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, Node.js test runner)
// Local store tests: merge-sensitive writes, deletion and soft delete, observer
// lifecycle, subscription rules, and DQL validation with EXPLAIN. Run with:
//   node --test local-store-tests.js
// What each test checks, as DQL and expected results, is in § Testing Strategies.
// The helper is the one of local-store-test-helper.js, repeated here so that
// the file runs on its own.
//
// Guide: § Testing Merge-Sensitive Writes, § Testing Deletion and Soft Delete, § Testing Observer Lifecycle,
//   § Testing Subscription Rules, § Validating DQL in Tests, § Testing in JavaScript

import { Ditto, DittoConfig, DittoError } from '@dittolive/ditto';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { beforeEach, test } from 'node:test';

// Opens a Ditto instance for one test; sync is never started.
async function openTestDitto(t, { systemParameters = {}, configure } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ditto-test-'));
  const ditto = await Ditto.open(
    new DittoConfig({
      databaseID: '00000000-0000-4000-8000-000000000001',
      connect: { mode: 'smallPeersOnly' },
      persistenceDirectory: directory,
      systemParameters,
    }),
  );
  t.after(async () => {
    await ditto.close();
    await rm(directory, { recursive: true, force: true });
  });
  await configure?.(ditto);
  return ditto;
}

let ditto;
beforeEach(async (t) => {
  ditto = await openTestDitto(t);
});

test('adding a line item keeps the existing items (map keyed by ID)', async () => {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', {
    order: { _id: 'order-1', items: { 'item-1': { productId: 'p1', quantity: 2 } } },
  });
  // The code under test: an upsert of a partial document (see "Arrays and Maps").
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF', {
    patch: { _id: 'order-1', items: { 'item-2': { productId: 'p2', quantity: 1 } } },
  });
  const result = await ditto.store.execute('SELECT * FROM orders WHERE _id = :id', { id: 'order-1' });
  const items = result.items[0].value.items;
  assert.ok(!Array.isArray(items)); // not an array
  assert.deepEqual(Object.keys(items).sort(), ['item-1', 'item-2']);
});

test('re-upserting unchanged data is a no-op', async () => {
  const product = { _id: 'p1', name: 'Pen', priceCents: 250 };
  await ditto.store.execute('INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF', { product });
  const again = await ditto.store.execute('INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF', { product });
  assert.equal(again.mutatedDocumentIDsV2().length, 0);
});

// The code under test: the app's replaceAddress() (see "Assigning an object merges it").
async function replaceAddress(ditto, customerId, address) {
  await ditto.store.transaction(
    async (tx) => {
      await tx.execute('UPDATE customers UNSET address WHERE _id = :id', { id: customerId });
      await tx.execute('UPDATE customers SET address = :address WHERE _id = :id', { id: customerId, address });
    },
    { hint: 'replaceAddress' },
  );
}

test('replaceAddress removes keys that are not in the new address', async () => {
  await ditto.store.execute('INSERT INTO customers DOCUMENTS (:customer)', {
    customer: { _id: 'c1', address: { city: 'Oslo', zip: '0150' } },
  });
  await replaceAddress(ditto, 'c1', { city: 'Bergen' });
  const result = await ditto.store.execute('SELECT * FROM customers WHERE _id = :id', { id: 'c1' });
  // A plain SET would keep "zip": objects merge under the default settings.
  assert.deepEqual(result.items[0].value.address, { city: 'Bergen' });
});

test('active-orders query treats a missing or null flag as not deleted', async () => {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:a), (:b), (:c), (:d)', {
    a: { _id: 'deleted', isDeleted: true },
    b: { _id: 'active', isDeleted: false },
    c: { _id: 'nullFlag', isDeleted: null },
    d: { _id: 'noFlag' },
  });
  // The query used by the app's repository.
  const result = await ditto.store.execute('SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id');
  assert.deepEqual(result.items.map((item) => item.value._id), ['active', 'noFlag', 'nullFlag']);
});

test('deleting by ID removes exactly the listed documents', async () => {
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:a), (:b), (:c)', { a: { _id: 'o1' }, b: { _id: 'o2' }, c: { _id: 'o3' } });
  // The statement used by the app; WHERE _id IN :ids, not USE IDS.
  const deleted = await ditto.store.execute('DELETE FROM orders WHERE _id IN :ids', { ids: ['o1', 'o2'] });
  assert.equal(deleted.mutatedDocumentIDsV2().length, 2);
  const remaining = await ditto.store.execute('SELECT _id FROM orders');
  assert.deepEqual(remaining.items.map((item) => item.value._id), ['o3']);
});

test('observer sees a new order and is cancelled cleanly', async () => {
  let resolveSawOrder;
  const sawOrder = new Promise((resolve) => {
    resolveSawOrder = resolve;
  });
  const observer = ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    (result) => {
      if (result.items.length === 1) resolveSawOrder();
    },
    { status: 'open' },
  );
  await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', { order: { _id: 'order-1', status: 'open' } });
  await Promise.race([
    sawOrder,
    new Promise((_, reject) => setTimeout(() => reject(new Error('no callback within 5 s')), 5000)),
  ]);
  // The same cleanup that the component's effect performs.
  observer.cancel();
  assert.equal(observer.isCancelled, true);
  assert.equal(ditto.store.observers.length, 0);
});

test('subscriptions with projections or ORDER BY/LIMIT are rejected', () => {
  const unsupported = (error) => error instanceof DittoError && error.code === 'query/unsupported';
  assert.throws(() => ditto.sync.registerSubscription('SELECT _id, status FROM orders'), unsupported);
  assert.throws(() => ditto.sync.registerSubscription('SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50'), unsupported);
});

test("the app's subscriptions are valid", () => {
  const subscriptions = [
    ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId: 'store-1' }),
    ditto.sync.registerSubscription('SELECT * FROM products'),
  ];
  for (const subscription of subscriptions) {
    subscription.cancel();
    assert.equal(subscription.isCancelled, true);
  }
});

// The app's statements with representative arguments. In a real app, keep the
// statement strings in your repository module and import them here.
const appStatements = [
  ['SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC', { status: 'open' }],
  ['UPDATE orders SET status = :status WHERE _id = :id', { status: 'closed', id: 'order-1' }],
  ['DELETE FROM orders WHERE _id IN :ids', { ids: ['order-1'] }],
];

// Writes bigint values as strings, so that JSON.stringify accepts the plan.
const toJson = (value) => JSON.stringify(value, (key, v) => (typeof v === 'bigint' ? v.toString() : v));

test('every app statement can be planned', async () => {
  for (const [statement, args] of appStatements) {
    // EXPLAIN rejects if a statement cannot be parsed or planned.
    await ditto.store.execute(`EXPLAIN ${statement}`, args);
  }
});

test('the open-orders query uses its index', async () => {
  // In your suite, create indexes with the same startup code as the app (for
  // example, through the configure option of openTestDitto).
  await ditto.store.execute('CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)');
  const plan = await ditto.store.execute('EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC', { status: 'open' });
  assert.match(toJson(plan.items[0].value), /indexScan/);
});
