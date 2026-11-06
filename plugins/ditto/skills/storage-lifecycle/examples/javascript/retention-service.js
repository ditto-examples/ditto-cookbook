// Ditto SDK: 5.2.0 (JavaScript, @dittolive/ditto 5.2.0)
//
// Services that own the subscriptions and run evictions on a schedule.
//
// The DQL and the rules are in ../evict-subscription-management-good.sql,
// ../ttl-eviction-small-peer.sql, and ../soft-delete-relay.sql. The same
// services for the other SDKs are in examples/<sdk>/retention-service.*.
//
// Guide: § EVICT, § Time-based eviction, § Batching evictions,
//   § Soft delete, subscriptions, and cleanup, § Subscriptions in JavaScript

const dayMs = 24 * 60 * 60 * 1000;

// ISO-8601 UTC timestamp with exactly millisecond precision, for example
// "2026-10-08T10:30:00.123Z". toISOString() always writes three fractional
// digits, so the stored values sort as text.
export function utcTimestamp(time = new Date()) {
  return time.toISOString();
}

// Time-based retention: subscription + complementary, batched eviction.

// Keeps the last `retentionMs` of orders on this device.
export class OrderRetention {
  #subscription = null;

  constructor(ditto, { retentionMs = 7 * dayMs } = {}) {
    this.ditto = ditto;
    this.retentionMs = retentionMs;
  }

  // Same fixed-precision format as the stored timestamps (utcTimestamp()).
  #cutoff() {
    return utcTimestamp(new Date(Date.now() - this.retentionMs));
  }

  // Call once at startup (before ditto.sync.start()).
  start() {
    this.#subscription = this.#subscribeFrom(this.#cutoff());
  }

  // Call on a schedule, at most about once per day, preferably at a quiet time.
  async evictExpired() {
    const cutoff = this.#cutoff();
    // 1. Stop asking peers for documents older than the new cutoff.
    this.#subscription?.cancel();
    try {
      // 2. Evict the complement in short batches.
      return await this.#evictInBatches(cutoff);
    } finally {
      // 3. Subscribe again with the moved boundary (same cutoff value), even if
      //    the eviction failed.
      this.#subscription = this.#subscribeFrom(cutoff);
    }
  }

  #subscribeFrom(cutoff) {
    return this.ditto.sync.registerSubscription('SELECT * FROM orders WHERE createdAt >= :cutoff', { cutoff });
  }

  // Batching keeps each write transaction short. It does not reduce the sync
  // cost of eviction: run the whole batched cleanup on the usual schedule, not
  // as many separate cleanups.
  async #evictInBatches(cutoff) {
    let total = 0;
    while (true) {
      const result = await this.ditto.store.execute(
        'EVICT FROM orders WHERE createdAt < :cutoff LIMIT 1000 RETURNING COUNT(*) AS evicted',
        { cutoff },
      );
      const evicted = result.items[0].value.evicted;
      total += evicted;
      if (evicted === 0) return total;
    }
  }

  dispose() {
    this.#subscription?.cancel();
  }
}

// Soft delete, Variant B: retention window, device-side EVICT.

// Keeps active orders and orders deleted within the retention window, and
// evicts older deleted orders.
export class OrderSoftDeleteRetention {
  #subscription = null;

  // retentionMs: longer than the longest time a device is expected to stay offline.
  constructor(ditto, storeId, { retentionMs = 30 * dayMs } = {}) {
    this.ditto = ditto;
    this.storeId = storeId;
    this.retentionMs = retentionMs;
  }

  #cutoff() {
    return utcTimestamp(new Date(Date.now() - this.retentionMs));
  }

  // Call once at startup (before ditto.sync.start()).
  start() {
    this.#subscription = this.#subscribe(this.#cutoff());
  }

  // Call on a schedule, at most about once a day. The cutoff moves only here,
  // never on screen changes.
  async evictExpired() {
    const cutoff = this.#cutoff();
    this.#subscription?.cancel();
    try {
      const result = await this.ditto.store.execute(
        'EVICT FROM orders WHERE storeId = :storeId AND isDeleted = true AND deletedAt < :cutoff',
        { storeId: this.storeId, cutoff },
      );
      return result.mutatedDocumentIDsV2().length;
    } finally {
      this.#subscription = this.#subscribe(cutoff);
    }
  }

  #subscribe(cutoff) {
    return this.ditto.sync.registerSubscription(
      'SELECT * FROM orders WHERE storeId = :storeId ' +
        'AND (coalesce(isDeleted, false) = false OR deletedAt >= :cutoff)',
      { storeId: this.storeId, cutoff },
    );
  }

  dispose() {
    this.#subscription?.cancel();
  }
}

// Switching stores (the needed data changes).

// Owns the store-scoped subscriptions for the app session.
export class StoreSync {
  #subscriptions = [];
  #currentStoreId = null;

  constructor(ditto) {
    this.ditto = ditto;
  }

  // Call after login or when the user switches to another store.
  async switchStore(newStoreId) {
    // 1. Stop asking for the old store's data.
    this.#cancelSubscriptions();
    // 2. Remove the old store's documents from this device only.
    this.#currentStoreId = newStoreId;
    await this.#evictOtherStores(newStoreId);
    // 3. Ask for the new store's data.
    this.#subscriptions.push(
      this.ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId: newStoreId }),
      this.ditto.sync.registerSubscription('SELECT * FROM orderItems WHERE storeId = :storeId', { storeId: newStoreId }),
    );
  }

  // Data that was already being transferred when the old subscriptions were
  // cancelled can still arrive afterwards. Call this later, for example on the
  // next app start or from a periodic cleanup, to evict it again.
  async evictLateArrivals() {
    if (this.#currentStoreId !== null) await this.#evictOtherStores(this.#currentStoreId);
  }

  async #evictOtherStores(storeId) {
    await this.ditto.store.execute('EVICT FROM orders WHERE storeId != :storeId', { storeId });
    await this.ditto.store.execute('EVICT FROM orderItems WHERE storeId != :storeId', { storeId });
  }

  #cancelSubscriptions() {
    for (const subscription of this.#subscriptions) subscription.cancel();
    this.#subscriptions = [];
  }

  // Call on logout.
  dispose() {
    this.#cancelSubscriptions();
  }
}

// Run eviction at most once per day.

// Runs the retention cleanup at most once per day, for example when the app
// starts after hours. Persist lastRun in your own storage if needed.
export class DailyEvictionScheduler {
  constructor(retention) {
    this.retention = retention;
    this.lastRun = null; // epoch milliseconds
  }

  async runIfDue(now = Date.now()) {
    if (this.lastRun !== null && now - this.lastRun < dayMs) return false;
    this.lastRun = now;
    await this.retention.evictExpired();
    return true;
  }
}

// ❌ Anti-pattern: evicting on every screen visit.

// ❌ BAD: An eviction in a component's mount effect runs on every screen visit
// (twice in development with React's Strict Mode). Each eviction triggers a
// resync with every connected peer. Use the scheduler above instead.
export async function evictOnScreenVisit(ditto) {
  await ditto.store.execute('EVICT FROM orders WHERE createdAt < :cutoff', {
    cutoff: utcTimestamp(new Date(Date.now() - 7 * dayMs)),
  });
}
