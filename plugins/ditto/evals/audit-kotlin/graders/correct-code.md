---
type: llm
---

The fixture also contains code that follows the Ditto best practices guide. Judge only the findings that the report ranks CRITICAL or HIGH (or the equivalent top two levels it uses).

FAIL if any CRITICAL or HIGH finding claims one of these is a defect:
- `WorkOrdersViewModel.workOrders`: `ditto.store.observe(...)` turned into a `StateFlow` with `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ...)`. Its observer ends with the ViewModel's scope; it is not leaked or unreleased. (The report may still say that the list breaks because of `workOrderFromValue` reading `technicianNote`; that is a correct finding about the mapper, not about the observer's lifecycle.)
- `WorkOrderSync`: one subscription by the stable `siteId`, closed in `leaveSite()`.
- `loadByIds`: one query with `_id IN :ids`, which is the right form for an array parameter.
- `createWorkOrder`'s `_id` from `UUID.randomUUID().toString()` and `createdAt` from the fixed-precision `utcTimestamp()` helper.
- Repository calls to `store.execute` running inside `withContext(Dispatchers.IO)`.

PASS otherwise. MEDIUM or LOW notes about these places, and suggestions that are not ranked as defects, do not fail this grader.
