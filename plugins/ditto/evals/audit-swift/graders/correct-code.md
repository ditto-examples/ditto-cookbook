---
type: llm
---

The fixture also contains code that follows the Ditto best practices guide. Judge only the findings that the report ranks CRITICAL or HIGH, or the equivalent top two levels of its own scale.

FAIL if any CRITICAL or HIGH finding claims that one of these is a defect in its own right:
- `ItemsListModel`: it keeps the `DittoStoreObserver`, cancels it in `stop()` (from `onDisappear`) and in `deinit`, captures `self` weakly, filters by `warehouseId` and `location` (inside the warehouse's subscription), uses `ORDER BY sku, _id`, and decodes rows with `JSONDecoder`.
- `InventorySync`: one subscription by the stable `warehouseId`, cancelled in `leaveWarehouse()`.
- `newID()` (a lowercased `UUID().uuidString`) and `utcTimestamp()` (`Date.ISO8601FormatStyle(includingFractionalSeconds: true)`).
- `moveItem`: a single-field `UPDATE` with validated parameters.

A finding that these types stop working because the `Ditto` instance in `AppEnvironment` is released is the correct finding about `AppEnvironment`, not a defect in them. Neither is a finding about another function, such as `countedStockValue` or `LowStockMonitor`, that only mentions one of these types among the places it affects. A finding that two devices can create documents for the same SKU is about `createItem`, not about `newID()`.

PASS otherwise. MEDIUM or LOW notes about these places, and suggestions that are not ranked as defects, do not fail this grader.
