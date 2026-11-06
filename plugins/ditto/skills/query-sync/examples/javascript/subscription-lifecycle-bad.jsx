// Subscription anti-patterns for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// Every example runs, but wastes bandwidth and storage, churns subscriptions
// across the mesh, or never cleans up. The corrected versions are in
// subscription-lifecycle-good.jsx.
//
// Subscription queries that are rejected when registerSubscription is called
// (a DittoError with code query/unsupported, thrown at once): a projection
// (SELECT _id, status ...), ORDER BY, LIMIT, JOIN, GROUP BY, DISTINCT, or a
// non-SELECT statement. Subscribe with SELECT * FROM c WHERE ... and sort,
// limit, project, or join in local queries.
//
// Guide: § Subscriptions in JavaScript, § Subscription Rules, § Subscription Lifecycle, § Filter locally instead of re-registering

import { useEffect } from 'react';

// ❌ BAD: A new subscription on every render, never cancelled. A component can
// render many times per second; each render adds a subscription that keeps
// replicating until the Ditto instance is closed.
export function OrdersBadge({ ditto, storeId }) {
  ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId });
  return <span className="orders-badge">Orders</span>;
}

// ❌ BAD: A subscription owned by a screen. Every visit registers and cancels
// it, making peers across the mesh re-evaluate what they owe the device and
// interrupting transfers. Own it in an app or feature service.
export function OrdersScreen({ ditto, storeId }) {
  useEffect(() => {
    const subscription = ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId });
    return () => subscription.cancel();
  }, [ditto, storeId]);
  return <main>Orders</main>;
}

// ❌ BAD: Re-registering the subscription whenever the user changes a filter
// or search term. Change the local observer instead.
export class OrderSearchSync {
  #subscription = null;

  constructor(ditto) {
    this.ditto = ditto;
  }

  onSearchChanged(storeId, status, customerName) {
    this.#subscription?.cancel();
    this.#subscription = this.ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId AND status = :status AND customerName = :customerName',
      { storeId, status, customerName },
    );
  }
}

// ❌ BAD: The reference is dropped without cancelling. A subscription whose
// object was garbage-collected keeps syncing; only ditto.sync.subscriptions or
// close() can stop it.
export function subscribeAndForget(ditto, storeId) {
  ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId });
}

// ❌ BAD: Every device receives and stores every order of every tenant.
// Filter by stable partition keys (tenant, store, region, team).
export const subscribeToEverything = (ditto) => ditto.sync.registerSubscription('SELECT * FROM orders');

// ❌ BAD: Filtering the subscription on a field that changes often. Documents
// leave the subscription's scope when they change state, so devices and relays
// stop following them. Excluding soft-deleted documents has a similar effect;
// keep them in the subscription (Variant A) or use a retention window (Variant B).
export const subscribeToOpenOrders = (ditto) =>
  ditto.sync.registerSubscription("SELECT * FROM orders WHERE status = 'open' AND coalesce(isDeleted, false) = false");

// ❌ BAD: Values interpolated into the subscription string. Use parameters.
export const subscribeInterpolated = (ditto, storeId) =>
  ditto.sync.registerSubscription(`SELECT * FROM orders WHERE storeId = '${storeId}'`);

// ❌ BAD: Evicting while the matching subscription is still active. Connected
// peers notice the missing documents and send them back. Cancel first.
export async function evictWhileSubscribed(ditto, oldStoreId) {
  await ditto.store.execute('EVICT FROM orders WHERE storeId = :storeId', { storeId: oldStoreId });
}

// ❌ BAD: Expecting execute() to fetch data from peers. Without a matching
// subscription it only sees what is already stored locally, and an empty
// result does not mean that no data exists.
export async function orderExistsAnywhere(ditto, orderId) {
  const result = await ditto.store.execute('SELECT * FROM orders WHERE _id = :id', { id: orderId });
  return result.items.length > 0;
}
