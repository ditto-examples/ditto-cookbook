---
type: llm
---

`src/ditto/orderQueries.ts` is not part of the pull request (pr.diff does not touch it). Its `ordersForTable` already built DQL with string interpolation (`'${tableId}'`) before this change.

PASS if the report either does not mention that interpolation, or presents it as a problem that the existing code already had, outside the change, for example under a separate "pre-existing" or "outside this PR" heading, or with words saying that the PR did not introduce it.
FAIL if the report presents the interpolation in `orderQueries.ts` as something this pull request introduced or changed, or lists it among the PR's findings with no indication that it predates the change.

The report may say that `ordersForTable` also lacks the new soft-delete filter, so archived orders still appear on the table screen. That is a consequence of this change, and saying so does not fail this grader.
