// Diffing observer results with Differ in Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// An observer delivers the complete result every time. new Differ().diff(items)
// compares it with the items passed to the same Differ before and returns
// insertions, deletions, and updates (arrays of indexes) and moves
// ({ from, to }). Facts:
// - Items are identified by _id, so project _id (on SDK 5.2.0, rows of a query
//   that does not project _id have none).
// - The first diff() reports every item as an insertion.
// - Deletions index the OLD list; insertions and updates index the NEW list.
// - Every item whose position shifts because of a reorder is reported as a
//   move, not only the item that moved. An insertion alone does not move rows.
// - A write to a field the query does not project is not an update.
// - A Differ has no release call; it is released with garbage collection.
//
// Guide: § Diffing results in JavaScript, § Diffing Results

import { Differ } from '@dittolive/ditto';
import { useEffect, useState } from 'react';

// ✅ GOOD: Logging changes between results. The query orders by status, so a
// status change moves rows.
export function logOrderChanges(ditto) {
  const differ = new Differ();
  let previousIds = [];
  return ditto.store.registerObserver('SELECT _id, status FROM orders ORDER BY status, _id', (result) => {
    const diff = differ.diff(result.items);
    const currentIds = result.items.map((item) => item.value._id);
    for (const index of diff.deletions) console.log(`deleted ${previousIds[index]}`); // OLD list
    for (const index of diff.insertions) console.log(`inserted ${currentIds[index]}`); // NEW list
    for (const index of diff.updates) console.log(`updated ${currentIds[index]}`); // NEW list
    for (const { from, to } of diff.moves) console.log(`moved ${from} -> ${to}`);
    previousIds = currentIds;
  });
}

// ✅ GOOD: A keyed React list needs no Differ. Use Differ when the UI reacts to
// the kind of change, here to highlight rows that were added or changed.
export function HighlightedOrders({ ditto }) {
  const [state, setState] = useState({ orders: [], changed: new Set() });

  useEffect(() => {
    const differ = new Differ(); // one per observer
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

// ❌ BAD: Diffing an unbounded observer of a whole collection. Differ keeps
// the previous result and compares every item on every change. Add a WHERE
// filter and a LIMIT, or skip Differ when keyed rows are enough.
export function diffEverything(ditto, onDiff) {
  const differ = new Differ();
  return ditto.store.registerObserver('SELECT * FROM orders', (result) => onDiff(differ.diff(result.items)));
}
