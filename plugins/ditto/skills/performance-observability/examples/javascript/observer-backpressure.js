// Observer backpressure for Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0).
//
// registerObserver asks for the next result as soon as the handler returns, so
// a synchronous handler has backpressure and an async one does not: it returns
// at its first await, and calls overlap. registerObserverWithSignalNext (SDK
// 5.1+) delivers one result, then waits until signalNext() is called; changes
// that happen meanwhile are merged into one later call with the latest result.
// If signalNext() is never called, the observer stops delivering updates.
// JavaScript has no registerObserverV2.
//
// Guide: § Backpressure in JavaScript, § Backpressure (SDK 5.1+), § Store Observers in JavaScript

// Placeholder: report the error to your logging or crash-reporting pipeline.
function showError(error) {
  console.error(error);
}

// PATTERN 1: for await over an async generator (the counterpart of
// registerObserverV2 with await for in other SDKs).

// ✅ GOOD: One result at a time; the loop body runs before the next result is
// requested. break, return, a throw, or abort() cancel the observer.
export async function* observeOneAtATime(ditto, query, args, signal) {
  let pending = null; // { result, signalNext }
  let wake = null;
  const observer = ditto.store.registerObserverWithSignalNext(
    query,
    (result, signalNext) => {
      pending = { result, signalNext };
      wake?.();
    },
    args,
  );
  const onAbort = () => {
    observer.cancel();
    wake?.();
  };
  signal?.addEventListener('abort', onAbort, { once: true });
  try {
    while (!signal?.aborted && !observer.isCancelled) {
      if (pending === null) {
        await new Promise((resolve) => {
          wake = resolve;
        });
        wake = null;
        continue;
      }
      const { result, signalNext } = pending;
      pending = null;
      yield result;
      signalNext();
    }
  } finally {
    signal?.removeEventListener('abort', onAbort);
    observer.cancel();
  }
}

// ✅ GOOD: Slow async work per update; intermediate states are merged.
export async function aggregateReadings(ditto, deviceId, persistAggregates, signal) {
  const query = 'SELECT * FROM sensorReadings WHERE deviceId = :deviceId ORDER BY recordedAt DESC LIMIT 100';
  for await (const result of observeOneAtATime(ditto, query, { deviceId }, signal)) {
    // Copy plain values before the slow work; do not keep the result.
    await persistAggregates(result.items.map((item) => item.value));
  }
}

// PATTERN 2: registerObserverWithSignalNext with signalNext() in finally.

// ✅ GOOD: One upload at a time, and an error cannot stop updates.
export class OpenOrdersUploader {
  #ditto;
  #uploadOrders;
  #observer = null;

  constructor(ditto, uploadOrders) {
    this.#ditto = ditto;
    this.#uploadOrders = uploadOrders;
  }

  start() {
    this.stop();
    this.#observer = this.#ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      (result, signalNext) => {
        const orders = result.items.map((item) => item.value);
        this.#handle(orders, signalNext);
      },
      { status: 'open' },
    );
  }

  async #handle(orders, signalNext) {
    try {
      await this.#uploadOrders(orders);
    } catch (error) {
      showError(error);
    } finally {
      signalNext();
    }
  }

  stop() {
    this.#observer?.cancel();
    this.#observer = null;
  }
}

// PATTERN 3: Signal after work that completes elsewhere.

// ✅ GOOD: The next update is requested only after the current one has been
// shown, for example when a render callback reports that it is done.
export function observeRenderedOrders(ditto, render) {
  return ditto.store.registerObserverWithSignalNext(
    'SELECT _id, status FROM orders WHERE status = :status ORDER BY createdAt DESC, _id LIMIT 100',
    (result, signalNext) => {
      const orders = result.items.map((item) => item.value);
      render(orders, () => signalNext()); // render() calls the second argument when the frame is shown
    },
    { status: 'open' },
  );
}

// ANTI-PATTERNS

// ❌ BAD: An async registerObserver handler. Uploads overlap, and an older one
// can finish after a newer one.
export function uploadOnEveryChange(ditto, uploadOrders) {
  return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', async (result) => {
    try {
      await uploadOrders(result.items.map((item) => item.value));
    } catch (error) {
      showError(error);
    }
  }, { status: 'open' });
}

// ❌ BAD: signalNext() is skipped when the work throws; the observer silently
// stops updating, and the rejection is unhandled.
export function fragileObserver(ditto, uploadOrders) {
  return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders ORDER BY createdAt', async (result, signalNext) => {
    await uploadOrders(result.items.map((item) => item.value));
    signalNext(); // Never reached if uploadOrders() throws.
  });
}

// ❌ BAD: Never calling signalNext(). After the first result, no further
// updates arrive.
export function neverSignals(ditto, onCount) {
  return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders', (result) => {
    onCount(result.items.length);
  });
}
