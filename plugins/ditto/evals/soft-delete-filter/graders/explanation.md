---
type: llm
---

PASS if the response explains that documents without an isDeleted field (missing or null) do not satisfy `isDeleted != true` because a comparison with a missing or null value is not true, and recommends `coalesce(isDeleted, false) = false` (or an equivalent IS MISSING / IS NULL / = false form).
FAIL if the response blames sync, subscriptions, or indexes, or recommends keeping `!= true` or `NOT isDeleted`.
