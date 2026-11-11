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

- **Sample, demo, workshop, or prototype**: the README, the directory (`examples/`, `samples/`, `demo/`), or the user says so, and nothing says it is released. A breaking change needs no rollout there. Do not report it as a defect; mention it in one line under the summary with the step it still needs: start every device from an empty store (reinstall or clear the store), because a device that still holds old documents syncs them to the others.
- **Not yet released**: the same as a sample, if the user or the project says that no version has shipped.
- **Released, or unknown**: treat the app as deployed. If nothing tells you, say "assumed deployed" in the report; do not guess that it is a demo.

## Find the Changes to Stored Data

In a diff, a pull request, or a branch, look at every changed line that touches what is stored or how stored values are read:

| Look for | Where it shows |
|---|---|
| Collection names | `FROM`, `INTO`, `UPDATE`, `COLLECTION` in DQL strings; subscriptions |
| `_id` shape or how it is made | `INSERT` arguments; ID helpers; composite `_id` objects; `_id.<field>` filters |
| Field names, types, units, meaning | `INSERT` and `UPDATE` arguments; model classes and their decoding (`fromJson`, `Codable`, `@Serializable`, `fromDocument`); `UNSET`; startup migrations |
| CRDT types and declarations | `COLLECTION t (field MAP/REGISTER/COUNTER/ATTACHMENT)`; `APPLY ... INCREMENT`; a field that changes from an array or a plain value to a map; `DQL_STRICT_MODE` |
| Values of enumerated fields | Enums and their decoding; string literals written to `status`, `type`, `kind`, `role` |
| Deletion strategy | A new soft-delete flag; `DELETE` replaced by a flag, or the reverse; `EVICT` |
| Seed content | `INITIAL DOCUMENTS` arguments |

When you review a whole codebase instead of a change, look at the same places for signs of earlier changes: a startup `UPDATE ... UNSET`, code that reads two names for one value, or a model that fails on documents without a field.

## Classify Each Change

Use the table in `§ Breaking and additive changes`:

- **Additive**: a new optional field that every reader defaults when it is `MISSING`; a new collection that older versions do not need. Not a finding. List it in the report.
- **Breaking**: a rename, a removal, a new type, unit, or meaning; a new CRDT type or declaration; a new enumerated value that older versions cannot read (check how the previous version decodes the field: `values.byName`, `valueOf`, a non-optional `Codable` enum, or a `switch` without a default fails on an unknown value); a new `_id` shape or collection name; a new deletion strategy; a field the new version requires; changed seed content. In a deployed app, report it at CRITICAL (`§ Anti-Pattern Checklist`) unless the change follows a versioning pattern and the rollout.
- **Not a schema change**: indexes, and queries, observers, and screens that read and write the same fields with the same meaning.

For each breaking change, write the scenario with a device on the previous version, as in step 6: what it writes while offline, and what the new version reads after sync. A startup migration (`UPDATE ... SET new = old UNSET old`) is part of the same finding: it runs on every device over the documents each holds, and it does not change what older versions write.

- **Not released yet**: a field, value, or collection that the change under review introduces has not been written by any released version. Changing its shape within the same change, or before the release, is free; say so when you recommend it (for example, a map instead of the array that the change adds).
- **The previous version is not in view**: whether a new enumerated value or a removed field breaks older versions depends on how they read it. If their code is not available, report the finding as conditional, state the condition ("if 1.4 reads refunded orders anywhere"), and list the check under what was not checked.
- **Problems in unchanged code**: in a diff review, report what the change introduces as findings; list problems that the unchanged code already had separately, briefly, unless the change makes them worse.

## Classify the Fixes You Recommend

Several fixes in the guide change what is stored: an array to a map, a register to a counter, a `status` field to a status log, sequential IDs to UUIDs, `DELETE` to soft delete, a timestamp format, claims under `claims.<deviceId>`. For each finding whose fix does that, in a deployed app:

- Write the fix as an additive change: a new field or collection next to the old one (for an array, a map in a new field; `§ Incremental adoption`), with readers that tolerate both, or name the rollout in `§ Rolling out a breaking change`.
- Do not write a fix that converts the stored data in place.

When the user asks you to apply fixes, apply the ones that do not change stored data, and those whose change is additive. Before a breaking one, stop and ask, with the rollout it needs; in a sample or demo, apply it and say that every device needs an empty store.

## Report

Add a `Schema` line to every finding whose problem or fix changes stored data:

```
[CRITICAL] src/stock/migrate.ts:12 - migrateStock() renames qty to quantity in place
Also: src/stock/StockItem.ts:30 (the new model reads only quantity)
Scenario: Scanner A runs 2.3 and is offline; scanner B runs 2.4. A counts bin 7 and sets qty = 5. After sync, B's migration had already copied the old qty, so B shows the old count, and A keeps writing qty, which B no longer reads.
Impact: Stock counts differ between devices without an error until every device runs 2.4, and the counts made on 2.3 in the meantime never reach 2.4.
Fix: Remove the migration and keep qty as the stored field; rename only the property in the model (quantity: doc.qty). A new stored name needs the rollout in § Rolling out a breaking change.
Schema: breaking (rename of a field that 2.3 writes)
Reference: data-modeling / § Breaking and additive changes
```

- `Schema: additive (...)` for a fix that adds a field or collection; `Schema: breaking (...)` with the rollout for one that cannot be additive. Omit the line when neither the problem nor the fix changes stored data.
- At the end of the report, list the changes to stored data that the change under review makes, each marked additive or breaking, and say whether the app was taken as deployed, unreleased, or a sample, and why.
