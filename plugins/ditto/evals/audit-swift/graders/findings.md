---
type: llm
---

The fixture is an iPad app on the Ditto Swift SDK (DittoSwift 5.2.0). Paraphrase is fine; the report only has to make each problem recognizable.

PASS if the report identifies all five of these problems:
1. `AppEnvironment.make(config:)` keeps only `ditto.store` and `ditto.sync` and lets the `Ditto` instance itself go out of scope. `store` and `sync` reference `Ditto` weakly, so the instance shuts down as soon as `make` returns, and later calls fail (`useAfterCloseError`) or end the process (a fatal error). The fix is a strong reference to `Ditto` kept for as long as the app uses it.
2. `countedStockValue` reads `unitPrice` with `as? Double`. A price such as `12.5` that a 32-bit float holds exactly comes back as a `Float`, so the cast is `nil`, the price counts as 0, and the total is wrong. The fix is `as? NSNumber` with `doubleValue`, or `JSONDecoder`.
3. `items(withIDs:)` uses `IN (:ids)` with an array parameter, which matches nothing. It should be `IN :ids`.
4. `LowStockMonitor.start` registers an observer that is never cancelled. There is no `cancel()`, `stop`, or `deinit`, and each call from `onAppear` replaces the stored observer without cancelling the previous one, so the old observers keep running (dropping a `DittoStoreObserver` does not cancel it).
5. `recordCount` passes `Date()` as an argument. A Swift `Date` is stored as an object, not as a time that DQL can compare or sort. The fix is an ISO 8601 UTC string from the existing `utcTimestamp()` helper.

FAIL if any of the five is missing. Other findings in the report do not matter.
