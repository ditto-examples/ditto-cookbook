---
type: llm
---

PASS if the response advises against re-registering subscriptions per tab, recommends one long-lived subscription scoped by a stable key such as storeId (not by the frequently changing status), and filtering by status in the local query or observer instead.
FAIL if it endorses re-registering on each tab change, or keeps status in the subscription filter.
