---
type: llm
---

PASS if the report identifies all four of these problems in orders_repository.dart: (1) `IN (:statuses)` with an array parameter matches nothing (should be `IN :statuses`); (2) customerId is interpolated into the DQL string instead of passed as a parameter; (3) `DELETE ... USE IDS` without a WHERE predicate removes nothing in SDK 5.1.0 (use `WHERE _id IN :ids`); (4) the observer uses onChange without consuming the changes stream, so results accumulate in memory (and/or it is never cancelled).
FAIL if any of the four is missing.
