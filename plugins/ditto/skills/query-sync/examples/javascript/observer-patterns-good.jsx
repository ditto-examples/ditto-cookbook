// Recommended store observer patterns for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// registerObserver(query, handler, args) returns a StoreObserver. Register it
// in an effect (or in a service), keep only plain values in state, and cancel
// it in the effect's cleanup. The first callback comes after registerObserver
// has returned. Keep the handler synchronous: the SDK does not await an async
// handler, and a rejected promise from one is an unhandled rejection, which
// ends a Node.js process by default.
//
// Observers read the local store only. Pair them with a long-lived
// subscription (see subscription-lifecycle-good.jsx).
//
// Guide: § Store Observers in JavaScript, § Observer lifecycle in JavaScript, § Stable ordering, § Partial UI updates in JavaScript

import { useEffect, useState } from 'react';

// ✅ GOOD: The recommended observer pattern for components.
export function OrdersList({ ditto }) {
  const [orders, setOrders] = useState([]);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
      (result) => setOrders(result.items.map((item) => item.value)),
      { status: 'open' },
    );
    return () => observer.cancel();
  }, [ditto]);

  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>{order._id}</li>
      ))}
    </ul>
  );
}

// ✅ GOOD: A keyed list with a deterministic order (_id breaks ties), only the
// fields the rows show, and a LIMIT that keeps the observer's result small.
// The arguments are dependencies of the effect, so a new team replaces the observer.
export function TaskList({ ditto, teamId }) {
  const [tasks, setTasks] = useState([]);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT _id, title, createdAt FROM tasks ' +
        'WHERE teamId = :teamId AND coalesce(isDeleted, false) = false ' +
        'ORDER BY createdAt DESC, _id LIMIT 200',
      // Keep the handler synchronous and short: copy values, then set state.
      (result) => setTasks(result.items.map((item) => item.value)),
      { teamId },
    );
    return () => observer.cancel();
  }, [ditto, teamId]);

  return (
    <ul>
      {tasks.map((task) => (
        <li key={task._id}>{task.title}</li>
      ))}
    </ul>
  );
}

// ✅ GOOD: A hook that owns one observer per component and returns plain rows
// (null until the first result). It re-registers only when the JSON of the
// arguments changes, so callers can pass a new object on every render.
export function useDittoQuery(ditto, query, args = {}) {
  const argsKey = JSON.stringify(args);
  const [rows, setRows] = useState(null);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      query,
      (result) => setRows(result.items.map((item) => item.value)),
      JSON.parse(argsKey),
    );
    return () => observer.cancel();
  }, [ditto, query, argsKey]);

  return rows;
}

export function OpenOrdersWithHook({ ditto }) {
  const orders = useDittoQuery(
    ditto,
    'SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC, _id',
    { status: 'open' },
  );
  if (orders === null) return <p>Loading…</p>;
  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>{order._id}</li>
      ))}
    </ul>
  );
}

// ✅ GOOD: Partial UI updates. The badge observes COUNT(*) on its own; React
// bails out when the count is unchanged.
export function OpenOrdersCount({ ditto }) {
  const [count, setCount] = useState(0);

  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      (result) => {
        const n = result.items[0]?.value.n;
        setCount(typeof n === 'number' ? n : 0);
      },
      { status: 'open' },
    );
    return () => observer.cancel();
  }, [ditto]);

  return <span>Open orders: {count}</span>;
}

// ✅ GOOD: The screen observes nothing itself; each region has its own
// observer and re-renders independently.
export function OrdersScreen({ ditto }) {
  return (
    <main>
      <header>
        <OpenOrdersCount ditto={ditto} />
      </header>
      <OrdersList ditto={ditto} />
    </main>
  );
}

// ✅ GOOD: An observer owned by a non-component controller (for example, a
// store module that a state library or a context provider uses). The owner
// calls dispose(). The observed JOIN (SDK 5.1+) fires when either collection
// changes. Project the keys of each row (o._id AS orderId): on SDK 5.2.0,
// joined rows carry no _id of their own. Subscribe to both collections
// separately.
export class OpenOrdersWithCustomers {
  #observer;

  constructor(ditto, onRows) {
    this.#observer = ditto.store.registerObserver(
      'SELECT o._id AS orderId, o.total, c.name AS customerName ' +
        'FROM orders o JOIN customers c ON c._id = o.customerId ' +
        'WHERE o.status = :status ORDER BY o.createdAt DESC, o._id',
      (result) => onRows(result.items.map((item) => item.value)),
      { status: 'open' },
    );
  }

  dispose() {
    this.#observer.cancel();
  }
}

// ✅ GOOD (scripts and tests, SDK 5.1+): `using` cancels the observer when the
// block ends. In components, cancel in the effect's cleanup instead.
export async function countOpenOrdersOnce(ditto) {
  const counts = [];
  {
    using observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS n FROM orders WHERE status = :status',
      (result) => counts.push(result.items[0].value.n),
      { status: 'open' },
    );
    await new Promise((resolve) => setTimeout(resolve, 100)); // let the first result arrive
    void observer; // cancelled when the block ends
  }
  return counts.at(-1) ?? 0;
}

// ✅ GOOD: Async work started from a handler is caught, so a failure never
// becomes an unhandled rejection. For work that must not overlap, use
// registerObserverWithSignalNext (see observer-backpressure.js).
export function observeAndPrint(ditto, printReceipt, showError) {
  return ditto.store.registerObserver(
    'SELECT * FROM orders WHERE status = :status ORDER BY _id',
    (result) => {
      const orders = result.items.map((item) => item.value);
      Promise.all(orders.map((order) => printReceipt(order))).catch((error) => showError(error));
    },
    { status: 'ready' },
  );
}
