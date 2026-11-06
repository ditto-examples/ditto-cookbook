// Ditto SDK 5.2 (JavaScript, @dittolive/ditto 5.2.0): Attachment fetch timeouts
//
// Ditto has no fetch timeout and no "not available" event. While no connected
// peer has the blob, the fetcher simply reports nothing. Guard each fetch with
// a stall timer that restarts on every progress event, and stop the fetcher
// when it fires.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Stall timeout: restart a timer on every progress event
// 2. ✅ Stop the fetcher when the timer fires and report a retryable outcome
// 3. ✅ The outcome never depends on `await fetcher` (do not await a stopped fetcher)
// 4. ✅ Longer stall timeouts for larger files
// 5. ✅ Retry on user request instead of failing permanently
//
// Guide: § Attachments in JavaScript, § Fetching Attachments

// PATTERN 1-3: A fetch guarded by a stall timer.

// Outcomes of a guarded fetch: { kind: 'completed', bytes }, { kind: 'stalled' }
// (no progress within the stall timeout; a peer with the blob may connect
// later, so offer a retry), { kind: 'deleted' }, and { kind: 'cancelled' }.

// ✅ GOOD: Wraps one fetch. The promise that start() returns always settles,
// also after a stall or cancellation, because it does not await the fetcher.
export class GuardedAttachmentFetch {
  #ditto;
  #token;
  #stallTimeoutMs;
  #fetcher = null;
  #timer = null;
  #resolve = null;

  constructor(ditto, token, { stallTimeoutMs = 30_000 } = {}) {
    this.#ditto = ditto;
    this.#token = token;
    this.#stallTimeoutMs = stallTimeoutMs;
  }

  start() {
    return new Promise((resolve) => {
      this.#resolve = resolve;
      this.#restartStallTimer();
      this.#fetcher = this.#ditto.store.fetchAttachment(this.#token, async (event) => {
        if (event.type === 'Progress') {
          this.#restartStallTimer();
        } else if (event.type === 'Completed') {
          clearTimeout(this.#timer);
          try {
            this.#finish({ kind: 'completed', bytes: await event.attachment.data() });
          } catch {
            this.#finish({ kind: 'stalled' });
          }
        } else if (event.type === 'Deleted') {
          this.#finish({ kind: 'deleted' });
        }
      });
    });
  }

  // Stops an in-flight fetch. Safe to call at any time.
  cancel() {
    this.#fetcher?.stop();
    this.#finish({ kind: 'cancelled' });
  }

  #restartStallTimer() {
    clearTimeout(this.#timer);
    this.#timer = setTimeout(() => {
      this.#fetcher?.stop();
      this.#finish({ kind: 'stalled' });
    }, this.#stallTimeoutMs);
  }

  #finish(outcome) {
    clearTimeout(this.#timer);
    const resolve = this.#resolve;
    this.#resolve = null;
    resolve?.(outcome); // Only the first outcome counts.
  }
}

// PATTERN 4: Stall timeout by expected size.

// ✅ GOOD: The token's len is known before the download starts, so larger files
// can get a longer stall timeout. The thresholds are app decisions.
export function stallTimeoutFor(token) {
  const bytes = Number(token.len);
  if (bytes > 50 * 1024 * 1024) return 120_000;
  if (bytes > 5 * 1024 * 1024) return 60_000;
  return 30_000;
}

// PATTERN 5: Retry on user request.

// ✅ GOOD: A stalled fetch is not an error. Keep the token, show the metadata,
// and let the user retry. askToRetry(token) resolves to true to try again.
export async function loadWithRetry(ditto, token, askToRetry, { stallTimeoutMs = stallTimeoutFor(token) } = {}) {
  while (true) {
    const outcome = await new GuardedAttachmentFetch(ditto, token, { stallTimeoutMs }).start();
    if (outcome.kind === 'completed') return outcome.bytes;
    if (outcome.kind !== 'stalled' || !(await askToRetry(token))) return null;
  }
}
