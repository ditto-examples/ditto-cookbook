---
type: llm
---

The fixture is a small React Native data layer on the Ditto JavaScript SDK that follows the Ditto best practices guide. In it: values are always passed as parameters; IDs come from UUID v4 and timestamps from `toISOString()`; edits are single-field `UPDATE` statements; the soft delete sets `isDeleted` and `deletedAt` (an ISO string) in one `UPDATE`; both reads filter with `coalesce(isDeleted, false) = false`; the lookup of pinned notices uses `boardId = :boardId AND _id IN :ids`, inside the board's subscription; the observer in `useNotices` has a synchronous handler, `ORDER BY createdAt DESC, _id`, and an effect cleanup that cancels it; one subscription by the stable `boardId` is cancelled in `leaveBoard()`. The README says that only a notice's author edits or archives it, that a server-side job removes archived notices after 90 days, and that opening Ditto, authentication, and sync start are out of scope.

PASS if the report has no finding ranked CRITICAL or HIGH (or the top two levels of its own scale), or if every such finding points to a real defect that the code shows, and the README does not rule out.
FAIL if the report ranks as CRITICAL or HIGH a problem that the code does not have. Examples: calling the soft-delete filter wrong, calling the observer or the subscription leaked, calling the `IN :ids` form wrong, or reporting the `UPDATE` of `body` as a lost update between devices although only the author edits a notice. Also FAIL if it ranks as CRITICAL or HIGH something that the README places outside the review, such as authentication or the retention job, as if it were a defect in this code.

MEDIUM or LOW notes, suggestions, open questions, and items listed as not checked do not fail this grader.
