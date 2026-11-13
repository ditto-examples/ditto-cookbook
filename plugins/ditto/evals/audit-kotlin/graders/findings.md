---
type: llm
---

The fixture is an Android app on the Ditto Kotlin SDK. Paraphrase is fine; the report only has to make each problem recognizable.

PASS if the report identifies all five of these problems:
1. `forSite` in WorkOrderRepository.kt puts `siteId` into the DQL string with Kotlin string interpolation (`'$siteId'`) instead of passing it as a parameter such as `:siteId`.
2. `watchOpenCount` registers an observer with `registerObserver` and drops the returned `DittoStoreObserver`, so it can never be closed and keeps running (garbage collection does not stop it), and each call adds another observer.
3. `openRows` returns `result.items` (`DittoQueryResultItem`s) out of the `execute` handler; the result is closed when the handler returns, so reading `it.value` afterwards in `openTitles` throws (`IllegalStateException`).
4. `workOrderFromValue` reads `technicianNote` with the typed accessor `.string`, but the field is missing on work orders without a note (`createWorkOrder` does not write it; only `addNote` does), so the accessor throws (`DittoException`), which breaks the list that the ViewModel observes; the fix is `stringOrNull` with a default.
5. `addPart` reads the `parts` array, appends in app code, and writes the whole array back, while several technicians add parts to the same work order offline: the array is one last-writer-wins value, so one technician's parts are lost; the fix is a map keyed by a unique ID per part entry, written with a field-level `UPDATE` (the report may introduce it as a new field with a staged rollout, or otherwise treat the change of stored shape as breaking for released versions).

FAIL if any of the five is missing. Other findings in the report do not matter.
