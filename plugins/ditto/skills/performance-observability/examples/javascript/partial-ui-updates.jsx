// Partial UI updates and diffing for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// An observer delivers a new result for any change that affects its query.
// Keep each observer narrow and attach it to the smallest component that needs
// the data. React bails out when a state setter receives a value that is
// Object.is equal to the current one (it may call the component once more but
// does not re-render its children). A new result creates new objects even when
// nothing changed, so compare item.jsonString() for objects.
//
// Differ facts: items are identified by _id; the first diff() reports every
// item as an insertion; deletions index the OLD list, insertions and updates
// the NEW list; every shifted item of a reorder is a move. A keyed React list
// does not need Differ.
//
// Guide: § Partial UI updates in JavaScript, § Diffing results in JavaScript, § Partial UI Updates

import { Differ } from '@dittolive/ditto';
import { useEffect, useState } from 'react';

// PATTERN 1: One observer per region.

// ✅ GOOD: The badge observes a count; React bails out when it is unchanged.
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

// PATTERN 2: A keyed list. React matches rows by key, so no Differ is needed.
export function OrdersByStatus({ ditto, status }) {
  const [orders, setOrders] = useState([]);
  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT _id, status FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      (result) => setOrders(result.items.map((item) => item.value)),
      { status },
    );
    return () => observer.cancel();
  }, [ditto, status]);
  return (
    <ul>
      {orders.map((order) => (
        <li key={order._id}>{order._id}</li>
      ))}
    </ul>
  );
}

// ✅ GOOD: The screen itself observes nothing; each region re-renders independently.
export function OrdersScreen({ ditto }) {
  return (
    <main>
      <header>
        <OpenOrdersCount ditto={ditto} />
      </header>
      <OrdersByStatus ditto={ditto} status="open" />
    </main>
  );
}

// PATTERN 3: An aggregate row as an object: set state only when its JSON changes.
export function StatusTotals({ ditto }) {
  const [totals, setTotals] = useState({ key: '', value: {} });
  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT COUNT(*) AS orders, SUM(total) AS revenue FROM orders WHERE status = :status',
      (result) => {
        const item = result.items[0];
        if (!item) return;
        const key = item.jsonString();
        setTotals((current) => (current.key === key ? current : { key, value: item.value }));
      },
      { status: 'closed' },
    );
    return () => observer.cancel();
  }, [ditto]);
  return (
    <p>
      {totals.value.orders ?? 0} closed orders, revenue {totals.value.revenue ?? 0}
    </p>
  );
}

// PATTERN 4: Logging changes with Differ.

// ✅ GOOD: Report inserted, deleted, updated, and moved documents of a bounded observer.
export function logRecentOrderChanges(ditto) {
  const differ = new Differ();
  let previousIds = [];
  return ditto.store.registerObserver(
    'SELECT _id, status FROM orders ORDER BY status, _id LIMIT 100',
    (result) => {
      const diff = differ.diff(result.items);
      const currentIds = result.items.map((item) => item.value._id);
      for (const index of diff.deletions) console.log(`deleted ${previousIds[index]}`);
      for (const index of diff.insertions) console.log(`inserted ${currentIds[index]}`);
      for (const index of diff.updates) console.log(`updated ${currentIds[index]}`);
      for (const { from, to } of diff.moves) console.log(`moved ${from} -> ${to}`);
      previousIds = currentIds;
    },
  );
}

// PATTERN 5: Differ for the kind of change.

// ✅ GOOD: Highlight rows that were inserted or updated by the latest result.
export function HighlightedOrders({ ditto }) {
  const [state, setState] = useState({ orders: [], changed: new Set() });
  useEffect(() => {
    const differ = new Differ();
    const observer = ditto.store.registerObserver(
      'SELECT _id, status FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      (result) => {
        const diff = differ.diff(result.items);
        const orders = result.items.map((item) => item.value);
        const changed = new Set([...diff.insertions, ...diff.updates].map((index) => orders[index]._id));
        setState({ orders, changed });
      },
      { status: 'open' },
    );
    return () => observer.cancel();
  }, [ditto]);
  return (
    <ul>
      {state.orders.map((order) => (
        <li key={order._id} className={state.changed.has(order._id) ? 'changed' : undefined}>
          {order._id} ({order.status})
        </li>
      ))}
    </ul>
  );
}

// ANTI-PATTERN

// ❌ BAD: The root component observes every order and re-renders the header
// and the whole list for any change. The badge is computed in JavaScript
// instead of with COUNT(*), and rows have no keys.
export function OrdersScreenBad({ ditto }) {
  const [all, setAll] = useState([]);
  useEffect(() => {
    const observer = ditto.store.registerObserver('SELECT * FROM orders', (result) =>
      setAll(result.items.map((item) => item.value)),
    );
    return () => observer.cancel();
  }, [ditto]);
  const open = all.filter((order) => order.status === 'open');
  return (
    <main>
      <h1>Open orders: {open.length}</h1>
      <ul>
        {open.map((order) => (
          <li>{order._id}</li> // eslint-disable-line react/jsx-key
        ))}
      </ul>
    </main>
  );
}
