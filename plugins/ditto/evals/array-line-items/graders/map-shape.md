---
type: llm
---

PASS if the response says the whole array is a single last-writer-wins value (register), so concurrent edits to different items cannot merge, AND recommends storing the items as a map/object keyed by a stable item ID (for example a UUID), with display order kept in a field.
FAIL if it suggests keeping the array (for example with locking, timestamps, or retries), or recommends a separate collection as the only fix without mentioning the map keyed by ID.
