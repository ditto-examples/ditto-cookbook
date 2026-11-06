// State management with Ditto observers for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// One store object owns each observer, keeps immutable snapshots of plain
// values, notifies only when the visible data changed, and is disposed by its
// owner. React reads it with useSyncExternalStore. The same shape works with
// state libraries (Redux, Zustand, MobX): the module that holds the state owns
// the observer and cancels it when it is torn down.
//
// Guide: § Store Observers in JavaScript, § Partial UI updates in JavaScript, § Observer lifecycle in JavaScript, § Subscriptions in JavaScript

import { useEffect, useState, useSyncExternalStore } from 'react';

// PATTERN 1 + 2: A store that owns one observer.

// ✅ GOOD: Exposes frozen plain values and notifies only when the rows changed.
export class OrdersStore {
  #observer;
  #snapshot = Object.freeze([]);
  #key = null;
  #listeners = new Set();

  constructor(ditto, status) {
    this.#observer = ditto.store.registerObserver(
      'SELECT _id, status, total FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      (result) => {
        const key = result.items.map((item) => item.jsonString()).join('\n');
        if (key === this.#key) return; // The visible data did not change.
        this.#key = key;
        this.#snapshot = Object.freeze(result.items.map((item) => Object.freeze({ ...item.value })));
        for (const listener of this.#listeners) listener();
      },
      { status },
    );
  }

  subscribe = (listener) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  getSnapshot = () => this.#snapshot;

  dispose() {
    this.#observer.cancel();
    this.#listeners.clear();
  }
}

// ✅ GOOD: A separate, tiny observer for a summary value: COUNT(*) instead of
// loading the list to read its length.
export class OpenOrderCountStore {
  #observer;
  #count = 0;
  #listeners = new Set();

  constructor(ditto) {
    this.#observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      (result) => {
        const n = result.items[0]?.value.n ?? 0;
        if (n === this.#count) return;
        this.#count = n;
        for (const listener of this.#listeners) listener();
      },
      { status: 'open' },
    );
  }

  subscribe = (listener) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  getSnapshot = () => this.#count;

  dispose() {
    this.#observer.cancel();
    this.#listeners.clear();
  }
}

// PATTERN 3 + 4: Scoped re-renders.

function OpenOrderBadge({ store }) {
  const count = useSyncExternalStore(store.subscribe, store.getSnapshot);
  return <span>Open orders: {count}</span>;
}

function OrderList({ store }) {
  const orders = useSyncExternalStore(store.subscribe, store.getSnapshot);
  return (
    <ul>
      {orders.map((order) => (
        // The key keeps row state attached to the right document.
        <li key={order._id}>
          {order._id}: {order.total}
        </li>
      ))}
    </ul>
  );
}

// ✅ GOOD: The screen creates its stores in an effect and disposes them in the
// cleanup (so Strict Mode's second mount gets new ones). The badge and the
// list re-render independently.
export function OrdersScreen({ ditto }) {
  const [stores, setStores] = useState(null);
  useEffect(() => {
    const created = { orders: new OrdersStore(ditto, 'open'), count: new OpenOrderCountStore(ditto) };
    setStores(created);
    return () => {
      created.orders.dispose();
      created.count.dispose();
    };
  }, [ditto]);
  if (stores === null) return null;
  return (
    <main>
      <header>
        <OpenOrderBadge store={stores.count} />
      </header>
      <OrderList store={stores.orders} />
    </main>
  );
}

// PATTERN 5: Subscriptions at feature scope.

// ✅ GOOD: Subscriptions live longer than screens. Observers never sync data;
// the subscription decides what reaches this device.
export class OrdersFeature {
  #subscription = null;

  constructor(ditto, storeId) {
    this.ditto = ditto;
    this.storeId = storeId;
  }

  start() {
    this.#subscription ??= this.ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', {
      storeId: this.storeId,
    });
  }

  stop() {
    this.#subscription?.cancel();
    this.#subscription = null;
  }
}
