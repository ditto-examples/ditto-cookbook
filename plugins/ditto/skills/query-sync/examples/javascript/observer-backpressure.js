// Observer backpressure in Ditto SDK 5.2.0 (JavaScript, @dittolive/ditto 5.2.0).
//
// registerObserver asks for the next result as soon as the handler returns.
// A synchronous handler gets automatic backpressure; an async handler returns
// at its first await, so calls overlap. For slow or async work per update, use
// registerObserverWithSignalNext (SDK 5.1+) and call signalNext() when done:
// changes that happen meanwhile are merged into one later call with the latest
// result. JavaScript has no registerObserverV2.
//
// Guide: § Backpressure in JavaScript, § Backpressure (SDK 5.1+)

// Placeholder: report the error to your logging or crash-reporting pipeline.
function showError(error) {
  console.error(error);
}

// ✅ GOOD: registerObserverWithSignalNext. One result at a time; signalNext()
// is called in finally, so an error cannot stop updates.
export class OpenOrdersUploader {
  #ditto;
  #uploadOrders;
  #observer = null;

  constructor(ditto, uploadOrders) {
    this.#ditto = ditto;
    this.#uploadOrders = uploadOrders;
  }

  start() {
    this.stop(); // Cancel a previous start, if any.
    this.#observer = this.#ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM orders WHERE status = :status ORDER BY createdAt',
      (result, signalNext) => {
        // Copy plain values before the slow work; do not keep the result.
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
      signalNext(); // Always signal, even after an error; otherwise updates stop.
    }
  }

  stop() {
    this.#observer?.cancel();
    this.#observer = null;
  }
}

// ✅ GOOD: One result at a time with for await. The loop body runs before
// Ditto may deliver the next result; break, return, a throw, or abort() cancel
// the observer.
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
      yield result; // The caller's loop body runs here.
      signalNext();
    }
  } finally {
    signal?.removeEventListener('abort', onAbort);
    observer.cancel();
  }
}

// ✅ GOOD: Only the latest state matters. While the slow write runs, Ditto
// holds back updates and then delivers the latest result once.
export async function exportLatestState(ditto, writeFile, signal) {
  for await (const result of observeOneAtATime(ditto, 'SELECT * FROM orders ORDER BY _id', {}, signal)) {
    await writeFile(JSON.stringify(result.items.map((item) => item.value)));
  }
}

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

// ❌ BAD: signalNext() is skipped when the work throws, so the observer
// silently stops delivering updates (and the rejection is unhandled).
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
