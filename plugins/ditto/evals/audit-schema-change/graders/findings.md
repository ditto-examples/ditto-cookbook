---
type: llm
---

PASS if the report does all of the following for the change in pr.diff: (1) reports the rename of `tableNo` to `tableNumber` (with the startup `UPDATE ... UNSET tableNo`) as a breaking change to stored data, because tills that still run 1.4 keep reading and writing `tableNo`, and does not recommend shipping it in place; (2) reports the new `refunded` status as a change that older versions may not be able to read (1.4 decodes `status` with `OrderStatus.values.byName`), or as conditional on how 1.4 reads it; (3) treats the new optional `note` field, read with a default, as additive and does not report it as a breaking change; (4) for the `items` array that several tills edit, recommends a map keyed by an ID and makes clear that the shape can still change because no released version writes `items`, or otherwise recommends the map as a new field rather than a conversion in place.
FAIL if any of the four is missing, or if the report calls the `idx_orders_store` index a schema change.
