// Store observer anti-patterns for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// Every example runs, but leaks observers, ends a Node.js process, re-renders
// far more UI than needed, or never cleans up. The corrected versions are in
// observer-patterns-good.jsx and observer-backpressure.js.
//
// Guide: § Observer lifecycle in JavaScript, § Store Observers in JavaScript, § Behavior Specific to the JavaScript SDK

import { useEffect, useState } from 'react';

// ❌ BAD: An async handler that can reject. The SDK neither awaits nor handles
// the promise, so every failure is an unhandled rejection, which ends a
// Node.js process by default.
export function observeAndPrintBadly(ditto, printReceipt) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    async (result) => {
      for (const item of result.items) await printReceipt(item.value);
    },
    { status: 'ready' },
  );
}

// ❌ BAD: Registered in the component body, never cancelled. Every render adds
// another observer that keeps running until Ditto is closed.
export function OrdersInRender({ ditto }) {
  const [count, setCount] = useState(0);
  ditto.store.registerObserver('SELECT * FROM orders ORDER BY createdAt DESC, _id', (result) =>
    setCount(result.items.length),
  );
  return <span>{count} orders</span>;
}

// ❌ BAD: The effect returns no cleanup. The observer outlives the component,
// and React's Strict Mode registers a second one in development.
export function MissingCleanup({ ditto }) {
  const [count, setCount] = useState(0);
  useEffect(() => {
    ditto.store.registerObserver('SELECT _id FROM orders ORDER BY _id', (result) =>
      setCount(result.items.length),
    );
  }, [ditto]);
  return <span>{count}</span>;
}

// ❌ BAD: Dropping the handle and relying on garbage collection. A StoreObserver
// whose object was garbage-collected keeps running; the only ways to stop it
// are ditto.store.observers and close().
export function observeAndForget(ditto, onCount) {
  ditto.store.registerObserver('SELECT * FROM orders', (result) => onCount(result.items.length));
}

// ❌ BAD: Keeping the QueryResult in state. Copy item.value (or models) instead.
export function RetainsResult({ ditto }) {
  const [lastResult, setLastResult] = useState(null);
  useEffect(() => {
    const observer = ditto.store.registerObserver('SELECT * FROM orders ORDER BY _id', (result) =>
      setLastResult(result),
    );
    return () => observer.cancel();
  }, [ditto]);
  return <span>{lastResult?.items.length ?? 0} rows</span>;
}

// ❌ BAD: No ORDER BY. Rows may change position between updates.
export function observeTasksUnordered(ditto, onTasks) {
  return ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false', (result) =>
    onTasks(result.items.map((item) => item.value)),
  );
}

// ❌ BAD: Slow async work in a registerObserver handler. The next result
// arrives as soon as the handler returns, at its first await, so uploads
// overlap and an older upload can finish after a newer one. Use
// registerObserverWithSignalNext.
export function uploadOnEveryChange(ditto, uploadOrders) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', async (result) => {
    try {
      await uploadOrders(result.items.map((item) => item.value));
    } catch {
      // The error is swallowed, and the overlap remains.
    }
  }, { status: 'open' });
}

// ❌ BAD: Writing to the observed collection from its own observer without a
// guard. Each write triggers the observer again.
// Comparing with the stored time does not help: each device writes its own, so devices that
// run this observer keep overwriting each other (guide: Writing from Observers).
export function touchOnEveryChange(ditto) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', () => {
    ditto.store
      .execute('UPDATE orders SET lastSeenAt = :now WHERE status = :status', {
        now: new Date().toISOString(),
        status: 'open',
      })
      .catch(() => {});
  }, { status: 'open' });
}

// ❌ BAD: Editing item.value to change the document. The value is the same
// object on every read, so the edit seems to stick, but it never reaches the
// store. Write changes with UPDATE.
export function markShownBadly(result) {
  for (const item of result.items) item.value.shown = true;
}

// ❌ BAD: One observer per list item. Observe the list once and pass values
// down to the rows.
export function OrderRow({ ditto, orderId }) {
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

// ❌ BAD: Observing a whole collection at the root and re-rendering the entire
// screen (header, filters, list) on every change. Use one small observer per
// region instead.
export function WholeScreenObserver({ ditto }) {
  const [orders, setOrders] = useState([]);
  useEffect(() => {
    const observer = ditto.store.registerObserver('SELECT * FROM orders', (result) =>
      setOrders(result.items.map((item) => item.value)),
    );
    return () => observer.cancel();
  }, [ditto]);
  const open = orders.filter((order) => order.status === 'open');
  return (
    <main>
      <h1>Open orders: {open.length}</h1>
      <ul>
        {open.map((order) => (
          <li key={order._id}>{order._id}</li>
        ))}
      </ul>
    </main>
  );
}
