# Platform Differences

The concepts are the same on every platform, but some APIs behave differently. Keep these differences in mind when you port code or read samples for another SDK:

| Topic | Flutter | JavaScript | Swift | Kotlin |
|---|---|---|---|---|
| Create / open | `await Ditto.open(DittoConfig(...))` | `await Ditto.open(new DittoConfig(id, { mode: 'server', url }))`, or `new DittoConfig({ databaseID, connect, ... })` (SDK 5.2+); on the Web, call `await init()` first | `try await Ditto.open(config:)` | `DittoFactory.create(config)` |
| System parameters at open (SDK 5.2+) | `DittoConfig(systemParameters: {...})` | `systemParameters` in the `DittoConfig` options | `DittoConfig(..., systemParameters: [...])` | `DittoConfig(..., systemParameters = mapOf(...))` |
| Start sync | `ditto.sync.start()` (`void`, throws on failure) | `ditto.sync.start()` | `try ditto.sync.start()` | `ditto.sync.start()` (throws on failure) |
| Close | `await ditto.close()` | `await ditto.close()` | `Ditto.close()` (SDK 5.2+). In 5.1 there is no public `close()`: release all references, and the instance shuts down when deallocated | `ditto.close()` |
| Delete the local store (SDK 5.2+) | No API; after `close()`, delete the persistence directory (evicted values stay in the files) | No API; after `close()`, delete the persistence directory | `Ditto.deleteStore(databaseID:persistenceDirectory:)` | `DittoFactory.deleteStore(databaseId, persistenceDirectory)` |
| Encryption at rest (SDK 5.2+) | Not available | Not available | `DittoConfig.encryptionKey` | `DittoConfig.encryptionKey` |
| Login failure | Returns `AuthResponse` with `exception`; does not throw | Returns a result with `error`; does not throw | Reported to the completion handler as `error` | **Throws** |
| Observer backpressure | `registerObserver`: none. `registerObserverV2` (automatic) and `registerObserverWithSignalNext` (manual), both (Experimental) (SDK 5.1+) | `registerObserver` signals the next update when a synchronous handler returns (async handlers are not awaited); use `registerObserverWithSignalNext` for async work | `registerObserver(... handler:)` signals automatically; `handlerWithSignalNext:` is manual | No `signalNext`: suspend handlers and `collect` wait for the handler; `observe` returns a `Flow` |
| Release observers and subscriptions | `cancel()` | `cancel()` | `cancel()` | `close()` |
| Transaction completion | Return a value to commit; throw or return `TransactionCompletionAction.rollback` to roll back | Return a value to commit, or `'rollback'` | Return a value to commit, or `.rollback` | Must return `DittoTransaction.Result.Commit(value)` or `DittoTransaction.Result.Rollback` |
| `ditto.store.execute` inside a transaction | Throws `DittoException` | Writes deadlock without an error, and reads do not see the transaction's writes; never do it | Can deadlock; never do it | Can deadlock; never do it |
| Read-write transaction nested inside a read-write transaction | Deadlocks (the SDK does not detect it); never do it | Deadlocks; never do it | Can deadlock; never do it | Can deadlock; never do it |

See [Observing Changes](../best-practices/observers.md) and [Transactions](../best-practices/transactions.md) for details on each platform's patterns. In the JavaScript SDK, values that are not plain JSON need care (in our testing with SDK 5.1.0 and 5.2.0): a `Date` is stored as `{}`, `undefined` as `null`, `NaN` and `Infinity` make the write fail, a `Uint8Array` round-trips as bytes, and integers above 2^53 − 1 come back as `BigInt`, which `JSON.stringify` cannot serialize.

Other behavior of the JavaScript SDK, in our testing with SDK 5.0.3, 5.1.0, and 5.2.0:

- An exception thrown in an observer callback is discarded: the observer keeps being called, and neither `uncaughtException` nor `unhandledRejection` reports it. Catch and log errors inside the callback.
- `item.value` returns the same object every time, and changes to it are kept in that object but never reach the store. Copy the value before you modify it for display. The `value` and `jsonString()` of a result could still be read after `ditto.close()`, also for items that had not been read before.
- `ditto.store.observers` exists since 5.0 and also counts observers from `registerObserverWithSignalNext`, but its elements are not the objects that the registration returned; compare counts, not objects.
- `ditto.close()` waits for open transactions and other running operations (see [Concurrency and Duration](../best-practices/transactions.md#concurrency-and-duration)). Kotlin, Java, Swift, and C# stored some values incorrectly before SDK 5.2, and the stored data is not corrected by the upgrade; see [Known Issues in SDK 5.1.0](upgrading.md#known-issues-in-sdk-510).
