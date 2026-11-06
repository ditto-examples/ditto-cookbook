// Recommended subscription patterns for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// Rules:
// - Subscriptions decide what syncs to this device; observers and execute()
//   only read the local store.
// - Own long-lived subscriptions in an app- or session-level service, scoped by
//   stable partition keys, and register them again after every Ditto.open().
// - Filter screens with local observers; do not re-register subscriptions per
//   filter. Subscriptions accept only SELECT * with WHERE; a projection,
//   ORDER BY, or LIMIT throws a DittoError with code query/unsupported.
// - Cancel explicitly: a subscription whose object was garbage-collected keeps
//   syncing.
//
// Guide: § Subscriptions in JavaScript, § Subscription Lifecycle, § Filter locally instead of re-registering, § Cancelling subscriptions and local data

import { useEffect, useState } from 'react';

// ✅ GOOD: A session-level service owns the long-lived subscriptions of one
// workspace (store). Create it after login; call leaveStore() on logout.
export class OrderSync {
  #ditto;
  #subscriptions = [];
  #storeId = null;

  constructor(ditto) {
    this.#ditto = ditto;
  }

  // Call once after login or when the user enters a store.
  enterStore(storeId) {
    if (storeId === this.#storeId) return; // Already subscribed; do not re-register.
    this.leaveStore();
    this.#storeId = storeId;
    // Scope by stable partition keys; screens filter further with local queries.
    this.#subscriptions.push(
      this.#ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId }),
      this.#ditto.sync.registerSubscription('SELECT * FROM orderItems WHERE storeId = :storeId', { storeId }),
      // A small reference-data collection that every device needs may be
      // subscribed whole.
      this.#ditto.sync.registerSubscription('SELECT * FROM products'),
    );
  }

  // Call on logout or when the user leaves the store.
  leaveStore() {
    for (const subscription of this.#subscriptions) {
      subscription.cancel(); // Does nothing if already cancelled or Ditto was closed.
    }
    this.#subscriptions = [];
    this.#storeId = null;
  }
}

// ✅ GOOD: Switching stores: cancel first, evict the old store's data from this
// device, then subscribe to the new store. Evicting documents that still match
// an active subscription is futile: peers send them back.
export async function switchStore(ditto, currentSubscriptions, newStoreId) {
  for (const subscription of currentSubscriptions) subscription.cancel();
  await ditto.store.execute('EVICT FROM orders WHERE storeId != :storeId', { storeId: newStoreId });
  await ditto.store.execute('EVICT FROM orderItems WHERE storeId != :storeId', { storeId: newStoreId });
  return [
    ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId: newStoreId }),
    ditto.sync.registerSubscription('SELECT * FROM orderItems WHERE storeId = :storeId', { storeId: newStoreId }),
  ];
}

// ✅ GOOD (soft delete, Variant A): Soft-deleted documents stay in the
// subscription; local queries hide them with coalesce(isDeleted, false) = false.
// Every device stores flagged documents, so any device can relay the flag to
// one that missed it. For device-side EVICT of old flagged documents, use a
// retention-window subscription (Variant B, see the storage-lifecycle skill).
export function subscribeToTasks(ditto, teamId) {
  return ditto.sync.registerSubscription('SELECT * FROM tasks WHERE teamId = :teamId', { teamId });
}

export function observeActiveTasks(ditto, teamId, onTasks) {
  return ditto.store.registerObserver(
    'SELECT * FROM tasks WHERE teamId = :teamId AND coalesce(isDeleted, false) = false ORDER BY createdAt, _id',
    (result) => onTasks(result.items.map((item) => item.value)),
    { teamId },
  );
}

// ✅ GOOD: Subscriptions for a local JOIN: one per collection the join reads.
export function subscribeForOrderList(ditto, storeId) {
  return [
    ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId }),
    ditto.sync.registerSubscription('SELECT * FROM customers WHERE storeId = :storeId', { storeId }),
  ];
}

// ✅ GOOD: The subscription (owned by OrderSync) stays stable while the user
// switches status filters; only the local observer is replaced. The effect's
// dependencies make React cancel the old observer and register a new one.
export function OrdersByStatus({ ditto, storeId, status }) {
  const [orders, setOrders] = useState([]);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM orders WHERE storeId = :storeId AND status = :status ORDER BY createdAt DESC, _id',
      (result) => setOrders(result.items.map((item) => item.value)),
      { storeId, status },
    );
    return () => observer.cancel(); // Replacing a local observer is cheap.
  }, [ditto, storeId, status]);

  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>
          {order._id} ({order.status})
        </li>
      ))}
    </ul>
  );
}

// ✅ GOOD: Inspect active subscriptions for debugging. In JavaScript, a
// subscription registered without arguments has no queryArguments (null or
// undefined); reading it is safe. The elements are other objects than the
// registrations returned, but cancel() on them works.
export function logActiveSubscriptions(ditto) {
  for (const subscription of ditto.sync.subscriptions) {
    console.log(`${subscription.queryString} ${JSON.stringify(subscription.queryArguments ?? null)}`);
  }
}

// ✅ GOOD: Pausing sync does not require cancelling subscriptions.
// stop() pauses them; start() resumes them.
export const pauseSync = (ditto) => ditto.sync.stop();
export const resumeSync = (ditto) => ditto.sync.start();
