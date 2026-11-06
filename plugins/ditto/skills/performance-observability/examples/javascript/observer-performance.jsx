// Store observer performance for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0, React 19).
//
// - Register observers in an effect or a service, never during render, and
//   cancel them in the cleanup. React's Strict Mode runs effects twice in
//   development; the cleanup keeps it from leaking.
// - Keep handlers synchronous and short: copy plain values, set state.
// - Add ORDER BY with an _id tie-breaker, project the fields the view shows,
//   and keep results small with WHERE and LIMIT.
// - On Node.js, building a large result and reading its values run on the
//   JavaScript thread; heavy work on copied values belongs in a worker.
// For slow or async per-update work, see observer-backpressure.js.
//
// Guide: § Store Observers in JavaScript, § Observer lifecycle in JavaScript, § Executing DQL in JavaScript, § Stable ordering

import { useEffect, useRef, useState } from 'react';

// PATTERN 1: The recommended observer pattern.

// ✅ GOOD: Register in an effect, copy values, cancel in the cleanup.
export function OrdersList({ ditto }) {
  const [orders, setOrders] = useState([]);
  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT _id, status, createdAt FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 200',
      // Copy plain values; never keep QueryResult or QueryResultItem in state.
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

// PATTERN 2: Heavy work off the handler.

// ✅ GOOD: The handler only copies values; the expensive part runs afterwards
// (here asynchronously; in a browser, in a Web Worker). Results that finish
// out of order, or after unmount, are dropped.
export function SalesSummaryView({ ditto, summarize }) {
  const [summary, setSummary] = useState(null);
  useEffect(() => {
    let generation = 0;
    let mounted = true;
    const observer = ditto.store.registerObserver(
      'SELECT _id, total, createdAt FROM sales WHERE createdAt >= :since',
      (result) => {
        const values = result.items.map((item) => item.value);
        const current = ++generation;
        summarize(values)
          .then((next) => {
            if (mounted && current === generation) setSummary(next);
          })
          .catch(() => {}); // Report failures in your app's error pipeline.
      },
      { since: '2026-01-01T00:00:00.000Z' },
    );
    return () => {
      mounted = false;
      observer.cancel();
    };
  }, [ditto, summarize]);
  return <p>{summary ? `Total ${summary.total}` : 'Calculating…'}</p>;
}

// PATTERN 3: Throttling UI updates for very busy collections.

// ✅ GOOD: Keep only the latest values and render at most every 250 ms when
// the user cannot perceive every intermediate state.
export function ThrottledReadings({ ditto, intervalMs = 250 }) {
  const [readings, setReadings] = useState([]);
  const pending = useRef(null);
  useEffect(() => {
    const observer = ditto.store.registerObserver(
      'SELECT _id, value, recordedAt FROM sensorReadings ORDER BY recordedAt DESC, _id LIMIT 50',
      (result) => {
        pending.current = result.items.map((item) => item.value);
      },
    );
    const timer = setInterval(() => {
      if (pending.current !== null) {
        setReadings(pending.current);
        pending.current = null;
      }
    }, intervalMs);
    return () => {
      clearInterval(timer);
      observer.cancel();
    };
  }, [ditto, intervalMs]);
  return (
    <ul>
      {readings.map((reading) => (
        <li key={reading._id}>{reading.value}</li>
      ))}
    </ul>
  );
}

// ✅ GOOD: Deterministic order; _id breaks ties between equal timestamps.
export function observeTasksOrdered(ditto, onTasks) {
  return ditto.store.registerObserver(
    'SELECT * FROM tasks WHERE done = false ORDER BY createdAt DESC, _id',
    (result) => onTasks(result.items.map((item) => item.value)),
  );
}

// ANTI-PATTERNS

// ❌ BAD: No ORDER BY; rows may change position between updates.
export function observeTasksUnordered(ditto, onTasks) {
  return ditto.store.registerObserver('SELECT * FROM tasks WHERE done = false', (result) =>
    onTasks(result.items.map((item) => item.value)),
  );
}

// ❌ BAD: Registered during render. Every render registers a new observer that
// is never cancelled.
export function LeakyOrdersBadge({ ditto }) {
  const [count, setCount] = useState(0);
  ditto.store.registerObserver('SELECT COUNT(*) AS n FROM orders', (result) => setCount(result.items[0].value.n));
  return <span>{count}</span>;
}

// ❌ BAD: Heavy synchronous work in the handler blocks the event loop on every
// update; reading every value of a large result does too.
export function heavyHandler(ditto, onTotals) {
  return ditto.store.registerObserver('SELECT * FROM sales', (result) => {
    const totals = {};
    for (const item of result.items) {
      const sale = item.value;
      for (let i = 0; i < 10_000; i += 1) totals[sale._id] = (totals[sale._id] ?? 0) + sale.total / 10_000;
    }
    onTotals(totals);
  });
}
