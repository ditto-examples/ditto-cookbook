# Schema Changes

Devices that run different app versions read and write the same documents, often for months, and nothing in Ditto rejects a write of the old shape. A change to what the app stores is therefore a release decision, not a refactoring. Classify every change to stored data, in the code under review and in the fixes you recommend, so that the reader can tell a fix they can ship today from one that needs a rollout plan. The rules are in `§ Breaking and additive changes` and `§ Rolling out a breaking change`.

## Contents

- [Is the App Deployed?](#is-the-app-deployed)
- [Find the Changes to Stored Data](#find-the-changes-to-stored-data)
- [Classify Each Change](#classify-each-change)
- [Classify the Fixes You Recommend](#classify-the-fixes-you-recommend)
- [Report](#report)

## Is the App Deployed?

Decide this first, from evidence, and state it in the report:

- **Sample, demo, or workshop app**: the README or the user says so, nothing says it is released, and it does not share its database (the database ID, or a Ditto Server) with a released app. A directory name such as `examples/` or `demo/` alone is not enough: a monorepo can ship what it holds. A breaking change needs no rollout there. Do not report it as a defect; mention it in one line under the summary with the step it still needs: start every peer from an empty store, including the Ditto Server if there is one, because a peer that still holds old documents syncs them to the others. If devices may run builds from before and after the change at the same time (attendees on different commits), say that those devices will show each other's documents with missing fields.
- **Not yet released**: the same as a sample, if the user or the project says that no version has shipped and the app shares its database with no released app.
- **Released, or unknown**: treat the app as deployed. If nothing tells you, say "assumed deployed" in the report; do not guess that it is a demo.

## Find the Changes to Stored Data

In a diff, a pull request, or a branch, look at every changed line that touches what is stored or how stored values are read:

| Look for | Where it shows |
|---|---|
| Collection names | `FROM`, `INTO`, `UPDATE`, `COLLECTION` in DQL strings; subscriptions |
| `_id` shape or how it is made | `INSERT` arguments; ID helpers; composite `_id` objects; `_id.<field>` filters |
| Field names, types, units, meaning | `INSERT` and `UPDATE` arguments; model classes and their decoding (`fromJson`, `Codable`, `@Serializable`, `fromDocument`); `UNSET`; startup migrations |
| CRDT types and declarations | A declaration (`COLLECTION t (field MAP/REGISTER/COUNTER/ATTACHMENT)`) or an `APPLY ... INCREMENT` that differs from how the field is already stored; a field that changes from an array or a plain value to a map; a new key inside a `REGISTER` object or an array element; `DQL_STRICT_MODE` |
| Values of enumerated fields | Enums and their decoding; string literals written to `status`, `type`, `kind`, `role` |
| Deletion strategy | A new soft-delete flag; `DELETE` replaced by a flag, or the reverse (a new local `EVICT` or retention job is not a schema change) |
| Seed content | `INITIAL DOCUMENTS` arguments |

When you review a whole codebase instead of a change, look at the same places for signs of earlier changes: a startup `UPDATE ... UNSET`, code that reads two names for one value, or a model that fails on documents without a field.

## Classify Each Change

Use the table in `§ Breaking and additive changes`:

- **Additive**: a new optional top-level field, or a new key in a map (default `DQL_STRICT_MODE`), that holds new data older versions do not need (it does not replace an old field or change which documents are valid, visible, or counted), that every reader defaults when it is `MISSING`, where the previous version's model accepts unknown keys (kotlinx.serialization's default `Json` rejects them) and its code never replaces the object with `UNSET` and `SET`; a new collection that holds only new data older versions do not need; new documents with a new kind of `_id` where older versions treat `_id` as opaque. Not a finding. List it in the report.
- **Breaking**: a rename, a removal, a new type, unit, or meaning; a new CRDT type or a declaration that differs from how the field is stored; a new key inside a `REGISTER` object, an object written in strict mode, or an array element; a new `DQL_STRICT_MODE`; a new enumerated value that older versions cannot read, map to a known value, or overwrite, or that changes which documents they should show or count, such as a `voided` that older totals include (check how the previous version decodes the field: `values.byName`, `valueOf`, a non-optional `Codable` enum, or a `switch` without a default fails on an unknown value; a fallback such as `orElse: () => OrderStatus.open`, or a write-back of the whole model, also breaks); a new field that replaces an old one (a change that follows a stage of `§ A field that replaces another` is not a finding: list it with the next stage; a change that skips a stage, such as writing only the new field, reading it without the fallback to the old one, or not filling it from the old one, is CRITICAL unless the user confirms that the earlier stage runs on every device; a counter that replaces a register needs its starting value as that section says); a new collection that replaces an old one (`§ Rolling out a breaking change`); a new `_id` shape that older versions filter, subscribe, check permissions, or parse by; a renamed collection, or documents moved into a new one; a new deletion strategy, or a flag that changes which documents count; changed seed content. In a deployed app, report it at CRITICAL (`§ Anti-Pattern Checklist`) unless the change follows a versioning pattern and the rollout.
- **A field that the new version requires** (reads without a default, or filters, sorts, or subscribes on): older versions keep creating documents without it. The fix is to read it with a default, and to filter, sort, or subscribe on it only once every device writes it, not a rollout; rank it by what the missing documents cause (a crash or a hidden document is CRITICAL).
- **Not a schema change**: indexes, and queries, observers, and screens that read and write the same fields with the same meaning.

For each breaking change, write the scenario with a device on the previous version, as in step 6: what it writes while offline, and what the new version reads after sync. A startup migration (`UPDATE ... SET new = old UNSET old`) is part of the same finding: it runs on every device over the documents each holds, and it does not change what older versions write. If it runs at every launch, it also copies what older versions wrote later (including a `null` that the `UNSET` left) over newer edits of the new field; this follows from the merge rules and was not tested.

- **Not released yet**: a field, value, or collection that the change under review introduces has not been written by any released version. Changing its shape within the same change, or before the release, is free; say so when you recommend it (for example, a map instead of the array that the change adds).
- **The previous version's code**: the removed and context lines of the diff show it for the files they cover. If an older read that is in view filters out the new value (`WHERE status = 'open'`), the break depends on reads that are not in view.
- **The previous version is not in view**: whether a new enumerated value or a removed field breaks older versions depends on how they read it. If their code is not available, report the finding as conditional, state the condition ("if 1.4 reads refunded orders anywhere"), and list the check under what was not checked.
- **Problems in unchanged code**: in a diff review, report what the change introduces as findings; list problems that the unchanged code already had separately, briefly, unless the change makes them worse.

## Classify the Fixes You Recommend

Several fixes in the guide change what is stored, for example an array to a map, a register to a counter, a `status` field to a status log, sequential IDs to UUIDs, `DELETE` to soft delete, a timestamp format, claims under `claims.<deviceId>`. For each finding whose fix does that, in a deployed app:

- Write the fix as a new field or collection next to the old one (for an array, a map in a new field; `§ Incremental adoption`), never as a conversion in place, and mark it breaking with its rollout: `§ A field that replaces another` for a field (the bridge version writes both, fills the new one from the old one, and reads the old one), `§ Rolling out a breaking change` for a collection. A soft-delete flag is breaking too (older versions do not filter it).
- Only a fix that adds data older versions do not need, or new documents with a new kind of `_id` that older versions treat as opaque, is additive.
- Do not write a fix that converts the stored data in place.

When the user asks you to apply fixes, apply the ones that do not change stored data, and those whose change is additive. Before a breaking one, stop and ask, with the rollout it needs; in a sample or demo, apply it and say that every device needs an empty store.

## Report

Add a `Schema` line to every finding whose problem or fix changes stored data:

```
[CRITICAL] src/stock/migrate.ts:12 - migrateStock() renames qty to quantity in place
Also: src/stock/StockItem.ts:30 (the new model reads only quantity)
Scenario: Scanner A runs 2.3 and is offline; scanner B runs 2.4. A counts bin 7 and sets qty = 5. After sync, B's migration had already copied the old qty, so B shows the old count, and A keeps writing qty, which B no longer reads.
Impact: Stock counts differ between devices without an error until every device runs 2.4. Counts made on 2.3 after a one-time migration never reach 2.4, and a count made before it, depending on the order, is gone on every device.
Fix: Remove the migration and keep qty as the stored field; rename only the property in the model (quantity: doc.qty). A new stored name needs the rollout in § Rolling out a breaking change.
Schema: breaking (rename of a field that 2.3 writes)
Reference: data-modeling / § Breaking and additive changes
```

- `Schema: additive (...)` for a fix that adds only data older versions do not need; `Schema: breaking (...)` with the rollout for one that cannot be additive. Omit the line when neither the problem nor the fix changes stored data.
- At the end of the report, list the changes to stored data that the change under review makes, each marked additive or breaking, and say whether the app was taken as deployed, unreleased, or a sample, and why.
