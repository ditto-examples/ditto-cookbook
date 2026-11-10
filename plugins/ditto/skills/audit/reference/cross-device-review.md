# Cross-Device Review

How to find the defects that no single statement shows: code that is correct for one database, or for a client of a server, and wrong when several devices write the same data without a connection. Every statement in such code is valid, the scanner is silent, and a test on one device passes. Use this file in steps 5 and 6 of the audit workflow. It is the working copy of the guide's `§ Questions to Ask of Every Collection`; you do not need to read that section as well.

## Contents

- Build the inventory
- The questions
- When a question does not apply
- Reporting a cross-device finding

## Build the Inventory

The evidence is spread over files: the subscription is in a sync service, the query in a screen, the write in a repository, the cleanup in a startup job. Collect it first. Grep the source for the calls below, then write one block per collection.

| Find | Grep for |
|---|---|
| Subscriptions | `registerSubscription` |
| Observers | `registerObserver`, `observe(` |
| Reads and writes | `execute(` (also inside `transaction`), then sort by `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EVICT` |
| Collections in DQL built elsewhere | `FROM `, `INTO `, `UPDATE `, `JOIN ` in string constants |

```
Collection: orders
- Subscriptions: file:line, WHERE clause, where each argument comes from
- Reads: file:line of each query, observer, aggregate, and JOIN that reads it, with its WHERE clause
- Writes: file:line of each INSERT and UPDATE, the fields it writes, and which devices or roles run it
- Removals: file:line of each DELETE, EVICT, UNSET, and soft-delete flag
- _id: how it is generated
```

Which devices run a piece of code (every till, only the manager's tablet, a server process) is often not in the code. Infer it from roles, screens, and startup paths, and write "unknown" where you cannot; an unknown writer counts as "several devices" until the user says otherwise.

## The Questions

Ask each question of every collection in the inventory. "Look for" names the shape in code; the citations give the rule and the fix.

### 1. Which devices can write this document, and what does the merge keep?

Look for:
- A value read, changed in app code, and written back: `SET stock = :newStock`, a toggled boolean, an appended array, a recomputed total. The scanner finds only `SET x = x - 1`.
- A `save()` or form submit that writes every field, or a whole object loaded earlier. A field written again with its old value overwrites an earlier concurrent edit of that field on another device. `DO UPDATE_LOCAL_DIFF` helps only when the values do not come from a stale copy.
- Fields that are valid only together (an amount and its currency, a latitude and its longitude) in separate fields. A transaction does not keep them together across devices; one object declared as `REGISTER` does.
- One `status` field that devices overwrite in a workflow that must not go backwards, or one long text in which every person's edit must survive.
- Side effects in an observer that assume one call per change: observers skip intermediate states, and a `SELECT *` or aggregate observer is also called when no value it shows changed.

`§ What Concurrent Edits Produce`, `§ Writing a Value That Did Not Change`, `§ When Observers Fire`, `§ Prefer field-level updates over whole-document rewrites`, `§ Do not store derived values that can diverge`, `§ Pattern 1: Audit-log map inside the document` · Skill: `data-modeling`

### 2. What does a check before a write prove?

It proves something about this device at this moment. Look for a read, a condition on its result, and a write that is correct only if the condition still holds everywhere:
- A claim or lock: `UPDATE ... WHERE status = 'open'` (or a `SELECT` and an `if`) followed by code that acts on the number of changed documents: "assigned to me", "payment taken", "exactly one device wins".
- Uniqueness: a query for a login name, table number, or code, and an `INSERT` when it returns nothing.
- Sequence numbers: `COUNT(*) + 1`, `MAX(n) + 1`, or a counter used as a number that must be unique. A UUID in `_id` does not make the number unique.
- A rule: "stock never below zero", one booking per seat, a limit or budget. A transaction around the check makes it look safe; it is safe on one device only.

Recommend what the guide gives: claims under a key per device and one rule that every device uses to pick the winner (a rule that needs no clock, such as the smallest device ID, unless favoring a device whose clock is behind is acceptable); the value as `_id` only where both devices mean the same entity, otherwise duplicates resolved when read or a value assigned in one place; a display label with a device prefix; events or a `COUNTER` with the rule checked when the value is derived, or one device or service that decides. A `COUNTER` keeps every change but does not enforce a rule, so do not present it as the fix for "never below zero" on its own.

`§ Checks and Claims across Devices`, `§ Conditions and Arithmetic across Devices`, `§ Human-readable display IDs`, `§ When counters are appropriate` · Skill: `data-modeling`

### 3. What does an empty or small result mean?

That the device holds no such document. Look for:
- Branches on `items.isEmpty`, a count of 0, or `first` on a result, that create defaults, start onboarding, show "not found", or throw.
- One `execute` right after `registerSubscription`, `sync.start()`, or login, whose result is used as the data.
- "Create if absent" with a fixed `_id`: a query followed by an `INSERT`, or `ON ID CONFLICT DO NOTHING`. Both see only the local copy.

`§ Where Queries Run`, `§ Default Data with INITIAL Documents`, `§ Writing documents that contain counters` · Skill: `query-sync`

### 4. Which subscription brings every document that this query reads?

Put each read from the inventory next to the subscriptions of its collections and compare the `WHERE` clauses and the source of the arguments.
- A read of a collection with no subscription, or wider than its subscription (another status, another store, no time window): lists and totals are computed from part of the data, without an error. A `JOIN` needs a subscription for each side.
- A subscription that filters by a field that changes (`status`, `assignee`; a soft-delete or eviction flag is the documented exception, see `§ Soft delete, subscriptions, and cleanup`): a document that stops matching stays on the device as a stale copy, and neither its later edits nor its deletion arrive. Look for the local filter and the `EVICT` that deal with such copies.
- A subscription that excludes soft-deleted documents on a device that relays data, or a subscription whose filter value is personal data.
- The same subscription registered on more than one path (login, screen visit) and cancelled once.

`§ Subscription Rules`, `§ Multi-hop relay`, `§ Subscription Lifecycle`, `§ Soft delete, subscriptions, and cleanup`, `§ Input Validation and Query Parameters` · Skill: `query-sync`

### 5. What does the code assume once a write has returned?

The write is in the local store. Look for what follows an awaited `execute`:
- A message such as "sent", "received", or "synced", a call to a backend that expects the document, or a cleared retry queue.
- A close, `sync.stop()`, sign-out, `EVICT`, or deletion of the store right after a write that must reach another device (a payment, a submitted form), without waiting for its commit ID to be confirmed (with a timeout). A close or stop elsewhere is not a finding.
- Presence, or a non-empty `remotePeers`, used as proof that a peer has the data, or screens blocked until sync or a connection.

`§ Monitoring Sync Status`, `§ Resource Cleanup and Shutdown`, `§ Switching users on a shared device`, `§ Presence` · Skill: `sdk-setup`

### 6. What if one device removes the document while another edits it, or was offline for weeks?

- `DELETE` of a document that other devices can still edit (a husk), or where devices stay offline longer than the tombstone TTL (the data comes back).
- A soft-delete flag filtered in the list query and missing from another query, observer, aggregate, lookup by `_id`, or joined collection. List every read of the collection from the inventory and check each one.
- A flag set without `deletedAt`, or an `UNSET` of a map entry that another device can edit.
- An `_id` used again after `DELETE` or `EVICT` to start over (a cart, a draft, a daily document): other devices' edits and copies merge into the new document.
- `EVICT` of documents that an active subscription matches, that can hold changes that have not left the device, or, on a device that relays data, of flagged documents that devices behind it may still hold unflagged.

`§ Choosing DELETE, Soft Delete, or EVICT`, `§ Husk documents`, `§ Tombstone TTL and reaping`, `§ DELETE and Tombstones`, `§ EVICT`, `§ Flag-based eviction`, `§ Adding, updating, and removing map entries` · Skill: `storage-lifecycle`

### 7. What happens when this code runs on every device at the same time?

Startup code, timers, and "on first launch" code run once per device, each over the documents that device holds.
- Default data created with a plain `INSERT`, an upsert, or a check for existence instead of `INITIAL DOCUMENTS`.
- A cleanup `DELETE`, a closing job (`UPDATE ... WHERE` at the end of the day), or a migration that rewrites documents, run by every device instead of in one place.
- A recount that restarts a counter while other devices hold increments that have not synced.

`§ Default Data with INITIAL Documents`, `§ Conditions and Arithmetic across Devices`, `§ Soft delete, subscriptions, and cleanup`, `§ RESTART`, `§ Rolling out a breaking change` · Skills: `data-modeling`, `storage-lifecycle`

### 8. What does the screen show while related documents are on their way?

- A forced unwrap or `first` on a lookup of a referenced document, or an inner `JOIN` on a screen where a row must appear although its other side has not arrived.
- A parent shown as complete without its children. A transaction arrives whole only where the subscriptions of the device and of every relay cover all of its documents.
- An attachment assumed to be fetchable as soon as its document has arrived, or a token passed to another device outside a synced document.

`§ Transactions and Sync`, `§ Separate collections with JOIN (SDK 5.1+)`, `§ Availability` · Skills: `transactions-attachments`, `query-sync`

## When a Question Does Not Apply

Do not report a pattern where its condition cannot occur:
- **One writer.** A document that only one device ever writes (a device's own settings, a draft that is not shared) cannot lose a concurrent edit. Question 1, the claim and rule checks of question 2, and the husk check of question 6 need a second writer of the same document, and so does reusing an `_id` after `DELETE`; a user who signs in on two devices is a second writer. Uniqueness and sequence numbers (question 2) need a second device that inserts into the collection. The tombstone TTL, soft-delete filter, reuse after `EVICT`, and eviction checks (question 6) need neither.
- **A device that never works offline and has one peer** still has a window between a write and its arrival, so the written-back values of question 1 and questions 2 and 5 apply, with a lower likelihood. Say so in the finding instead of dropping it.
- **A collection without a subscription in this app** is not proof that it stays on one device: another app, another role, or Ditto Server may hold it, and a fixed `_id` or an `_id` built from a shared key (`settings-<storeId>`) suggests that it is meant to be shared. Report under question 4 that nothing brings it to the device, and keep the findings of the other questions with the condition "if this collection is meant to sync". Drop them only when the collection is clearly private to the device.

When the code does not show who writes, or how long devices stay offline, report the finding with the condition stated ("if more than one device can close an order"), and list the open question under what was not checked.

## Reporting a Cross-Device Finding

Add a `Scenario` line to the report format: the shortest sequence of events on two devices that produces the defect. It lets the reader verify the finding without knowing Ditto, and it shows you whether the finding is real: if you cannot write the sequence, do not report it.

```
[CRITICAL] src/tasks/claimTask.ts:31 - claimTask() treats a conditional UPDATE as a lock
Also: src/tasks/TaskScreen.tsx:58 (shows "Assigned to you" from the returned flag)
Scenario: Tablets A and B are offline and both hold task 7 as open. Both run claimTask(7); each UPDATE changes one document, so both show "Assigned to you". After sync, the task has one assignee, and the other tablet's user still works on it.
Impact: Two people do the same task, and no device reports it.
Fix: Write a claim under claims.<deviceId> only while no claim is visible, derive the assignee by one rule that needs no clock (the smallest device ID among the claims), and let the screen change when another winner arrives.
Reference: data-modeling / § Checks and Claims across Devices
```

- **One finding per root cause.** A cross-device defect usually spans files (a subscription here, a read there). Report it once, at the line where the fix goes, and list the other places under `Also:`. Do not report the cause and each of its consequences as separate findings; name the consequences in `Impact`.
- **Severity**: the severity of the matching item in `§ Anti-Pattern Checklist`. When one place matches items of different severity, use the higher one.
- **Defects that need no second device**, found on the way (a statement that can never match, a value that is never updated): report them as ordinary findings without a `Scenario`, ranked by the definitions in step 8.
- What these defects do cannot be reproduced with one Ditto instance, so list "confirm with a test on two devices" (the `testing` skill) under what was not checked.
