// State management anti-patterns with Ditto observers for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// Each example runs, but shows a mistake. The fixes are in
// state-management-good.jsx and partial-ui-updates.jsx.
//
// Guide: § Observer lifecycle in JavaScript, § Store Observers in JavaScript, § Partial UI updates in JavaScript

import { useEffect, useState, useSyncExternalStore } from 'react';

// ❌ BAD: Observes the whole collection without ORDER BY or LIMIT, keeps the
// QueryResult in state, and re-renders the header and the list on every change
// to any order. Rows have no keys.
export function OrdersDashboardBad({ ditto }) {
  const [result, setResult] = useState(null);
  useEffect(() => {
    const observer = ditto.store.registerObserver('SELECT * FROM orders', (next) => setResult(next));
    return () => observer.cancel();
  }, [ditto]);
  const items = result?.items ?? [];
  return (
    <main>
      <h1>{items.length} orders</h1>
      <ul>
        {items.map((item) => (
          <li>{item.value._id}</li> // eslint-disable-line react/jsx-key
        ))}
      </ul>
    </main>
  );
}

// ❌ BAD: No cleanup. The observer keeps running after the component is gone,
// and React's Strict Mode registers it twice in development.
export function LeakyOrderList({ ditto }) {
  const [orders, setOrders] = useState([]);
  useEffect(() => {
    ditto.store.registerObserver('SELECT * FROM orders ORDER BY _id', (result) =>
      setOrders(result.items.map((item) => item.value)),
    );
  }, [ditto]);
  return <span>{orders.length}</span>;
}

// ❌ BAD: A store whose observer has no owner and no dispose(). It can never
// be released, and every new instance (for example in a test) adds another
// observer.
export class StoreWithoutDispose {
  #snapshot = [];
  #listeners = new Set();

  constructor(ditto) {
    ditto.store.registerObserver('SELECT * FROM orders ORDER BY _id', (result) => {
      // ❌ Mutating the snapshot in place: useSyncExternalStore sees the same
      // array and does not re-render.
      this.#snapshot.length = 0;
      this.#snapshot.push(...result.items.map((item) => item.value));
      for (const listener of this.#listeners) listener();
    });
  }

  subscribe = (listener) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  getSnapshot = () => this.#snapshot;
}

export function OrdersFromMutatedStore({ store }) {
  const orders = useSyncExternalStore(store.subscribe, store.getSnapshot);
  return <span>{orders.length} orders</span>;
}

// ❌ BAD: Every row registers its own observer. Observe the list once and pass
// values down to the rows instead.
export function OrderRowWithOwnObserver({ ditto, orderId }) {
  const [order, setOrder] = useState(null);
  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM orders WHERE _id = :id',
      (result) => setOrder(result.items[0]?.value ?? null),
      { id: orderId },
    );
    return () => observer.cancel();
  }, [ditto, orderId]);
  return <span>{order?.status}</span>;
}

// ❌ BAD: Each write triggers the observer again. This UPDATE has no guard (it
// rewrites the same value), so every update causes another one. Guard writes
// with a WHERE condition that skips documents already in the target state.
export function selfTriggeringObserver(ditto) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', () => {
    ditto.store.execute("UPDATE orders SET checked = true WHERE status = 'open'").catch(() => {});
  }, { status: 'open' });
}
