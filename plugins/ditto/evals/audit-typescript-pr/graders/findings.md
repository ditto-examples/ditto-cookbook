---
type: llm
---

The fixture is a React Native app on the Ditto JavaScript SDK (`@dittolive/ditto` 5.2.0). The pull request in pr.diff adds kitchen ticket printing and order archiving. Paraphrase is fine; the report only has to make each problem recognizable.

PASS if the report identifies all four of these problems that the pull request introduces:
1. In `useKitchenPrinter.ts`, the handler passed to `registerObserver` is `async` and awaits `printTicket`, which rejects when the printer fails. The SDK does not handle the promise that the handler returns, so a rejection becomes an unhandled rejection (in Node.js, that ends the process). Calls can also overlap. The fix is a synchronous handler that catches the work it starts, or the backpressure API.
2. In `useKitchenPrinter.ts`, the `useEffect` registers the observer but returns no cleanup and drops the `StoreObserver`. The observer keeps running after the screen unmounts or `stationId` changes, and observers pile up. The fix is to return `() => observer.cancel()`.
3. The new soft-delete filter `isDeleted != true` (in `listOrders` and/or `OrdersScreen`) drops every order that has no `isDeleted` field. That is every order written before this change, and every order that has not been archived, so the lists go empty. The fix is `coalesce(isDeleted, false) = false`.
4. `archiveOrder` passes `new Date()` as the `deletedAt` argument. A JavaScript `Date` is stored as an empty object `{}`, so the time is lost. The fix is an ISO 8601 UTC string such as `new Date().toISOString()`, or epoch milliseconds.

FAIL if any of the four is missing. Other findings in the report do not matter.
