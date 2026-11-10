---
name: audit
description: Reviews code that uses the Ditto SDK against the Ditto best practices guide: scans for known anti-patterns, triages each hit, checks per collection the assumptions that fail across devices (locks, uniqueness, empty results, subscription coverage), and reports findings by severity with fixes. Use when asked to review, audit, or check Ditto code, before a release, or when unexplained sync, merge, deletion, or memory problems need a systematic look.
---

# Ditto Code Audit

A repeatable review of an app that uses the Ditto SDK in Flutter, JavaScript, Kotlin, or Swift. It combines a fast pattern scan, a cross-device review of each collection, and a manual checklist, and relies on the topic skills for the rules. The scan finds what one line shows; assumptions carried over from a single database or a server API show in no single line, and the cross-device review looks for them. Targets Ditto SDK 5.2.0; the scanner reads Dart, JavaScript/TypeScript, Swift, and Kotlin (its DQL rules apply to all of them; the rules for API calls name the SDKs they check in [reference/scanner-rules.md](reference/scanner-rules.md)).

## Before You Apply

- Identify the project's SDK and version: Flutter (`ditto_live` in `pubspec.yaml` / `pubspec.lock`), JavaScript (`@dittolive/ditto` in `package.json`), Kotlin (`com.ditto:ditto-kotlin` in Gradle files), or Swift (`DittoSwift` in `Package.swift`, `Package.resolved`, or the Xcode project). The rules target 5.2.0. **Note (SDK 5.1.0 and 5.2.0)** marks easy-to-miss behavior confirmed on both releases; **Note (SDK 5.1.0)** marks 5.1.0 behavior that 5.2.0 no longer shows, and **Note (SDK 5.2.0)** behavior observed on 5.2.0. Issues that only 5.1.0 has are in `§ Known Issues in SDK 5.1.0`; they apply wherever any device still runs 5.1.0. On a later version, confirm a note (release notes, docs.ditto.live) before reporting it as a defect. If the version cannot be found, apply the 5.2.0 rules, say so in the report, and mark findings that rest on a **Note (SDK ...)** as version-specific. **(SDK 5.1+)** and **(SDK 5.2+)** mark features introduced in 5.1 and 5.2.
- In that SDK's page, `../guide/reference/best-practices/platforms/<sdk>.md` (`flutter`, `javascript`, `kotlin`, `swift`), read the *Behavior Specific to the <SDK> SDK* section at its end, not the whole page (Grep the heading for its line): it lists what only that SDK does. `§ Specific to One SDK` in the guide's Anti-Pattern Checklist lists the mistakes to look for in that SDK. Open the topic skills' `examples/<sdk>/` only when you write a fix.
- `§ <Heading>` cites a section of the full guide: Grep the heading text in `../guide/reference/best-practices/` (including `platforms/`) and `../guide/reference/knowledge/`.
- Review only; do not change code unless the user asks for fixes.

## Workflow

Copy this checklist and work through it:

```
Ditto audit progress:
- [ ] 1. Scope: list files that use Ditto (imports of ditto_live, @dittolive/ditto, DittoSwift, com.ditto)
- [ ] 2. Context: SDK version, platforms, connection mode (Ditto Server or small peers only)
- [ ] 3. Scan: run scripts/scan.py on the source directories
- [ ] 4. Triage: confirm or discard every scanner hit by reading the code around it
- [ ] 5. Inventory: per collection, its subscriptions, reads, writes, and removals, with file:line
- [ ] 6. Cross-device review: ask the eight questions of every collection in the inventory
- [ ] 7. Manual review: walk the table below for the areas the app uses
- [ ] 8. Report: findings by severity, then what was checked and what was not
```

Do not stop after step 4: a clean scan does not cover steps 5 to 7.

### Step 3: Scan

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/scan.py lib/ test/
```

Pass the project's source and test directories, such as `lib/ test/` (Flutter), `src/` (JavaScript), `app/src/` (Android), or `Sources/ Tests/` (Swift). (`${CLAUDE_SKILL_DIR}` is this skill's directory; if it is not substituted, use the path of this file's directory.) Options: `--json` for machine-readable output, `--min-severity HIGH` to hide MEDIUM hits. A path that does not exist is reported on stderr and skipped. The script needs only Python 3.8+. If Python is unavailable, Grep for the same patterns listed in [reference/scanner-rules.md](reference/scanner-rules.md).

Every hit is a candidate, not a finding. The scanner matches lines; it cannot tell a test fixture, a deliberate counter-example, or a validated identifier from a defect.

### Step 4: Triage

For each hit:
1. Read the surrounding function and its callers.
2. Check whether the code really breaks the rule: Grep the `§` heading that the hit names in the guide and read that section, or the rule of the same name in the skill the hit names (`query-sync`, `data-modeling`, `storage-lifecycle`, `transactions-attachments`, `performance-observability`, `sdk-setup`, `testing`).
3. For a hit whose message says it applies to SDK 5.1.0 only (fixed in 5.2.0), such as `delete-evict-use-ids` and `composite-index-mixed-direction`, check the version from step 2. If the project uses 5.1.0, or the version is unknown, report it at its severity. If it uses 5.2.0, keep it as a lower-severity note that the code breaks on devices still running 5.1.0 (the code cannot show which releases run in the field), and say so in the finding.
4. Keep confirmed hits, and report each at the severity of its item in `§ Anti-Pattern Checklist`, which can be higher than the scanner's: the scanner's severity only orders the triage. The same holds for findings from steps 6 and 7, and where a topic skill ranks a rule differently: the severity section that lists the item decides, even when that section's heading describes a different kind of problem, and where one place matches items of different severity, the higher one. For a finding with no checklist item, use the definitions in step 8 and say that you ranked it yourself. Drop false positives silently unless the pattern is worth a comment (for example a validated key spliced into a backtick identifier).

### Steps 5 and 6: Inventory and cross-device review

Read [reference/cross-device-review.md](reference/cross-device-review.md) and follow it: build the inventory (per collection: subscriptions, reads, writes, removals, and how `_id` is made, each with file:line and with which devices run it), then ask every question of every collection. The evidence for these defects is in different files, so they are found only by putting the entries side by side.

| # | Question | Typical finding |
|---|---|---|
| 1 | Which devices can write this document, and what does the merge keep? | A value read, changed in code, and written back; a `save()` that writes every field; a `status` that devices overwrite |
| 2 | What does a check before a write prove? | A conditional `UPDATE` or a transaction used as a lock; uniqueness by a local query; `COUNT(*) + 1`; "never below zero" |
| 3 | What does an empty or small result mean? | Defaults or "not found" from an empty result; `execute` right after subscribing |
| 4 | Which subscription brings every document that this query reads? | A query, total, or `JOIN` wider than the subscriptions; a subscription on a field that changes, with stale copies |
| 5 | What does the code assume once a write has returned? | "Sent" after a local write; close or sign-out before the write is confirmed; presence as proof |
| 6 | What if one device removes the document while another edits it, or was offline for weeks? | Husks, data that comes back, a soft-delete filter missing from one query, an `_id` used again |
| 7 | What happens when this code runs on every device at once? | Defaults without `INITIAL DOCUMENTS`; cleanup, closing jobs, and migrations on every device |
| 8 | What does the screen show while related documents are on their way? | A forced unwrap of a referenced document; a parent without children; an attachment not yet fetched |

For each candidate, write the shortest sequence of events on two devices that produces the defect. If you cannot, it is not a finding; if the code does not show who writes or how long devices stay offline, report it with that condition stated. Report one finding per root cause, at the line where the fix goes, with the other places it touches under `Also:`.

### Step 7: Manual review

The remaining design and lifecycle problems, by area. Walk the rows for the areas that the app uses; each row is the list to check. Open the named skill only for a row where something looks wrong, and do not report again what step 6 found:

| Area | What to look for | Skill |
|---|---|---|
| Subscriptions | Scoped by stable keys; owned by a long-lived service; registered again every time Ditto opens (also on a cold start that skips login); not re-registered per screen, filter, or search, and not registered twice with one copy left uncancelled; no `!=`, `NOT IN`, or `clock()` in their filters; no personal data as a filter value; relays subscribe to what devices behind them need; soft-deleted documents stay in scope | `query-sync` |
| Observers | Registered once per owner, outside render code; released when the owner goes away (Flutter: `changes` consumed once, stream subscription and observer cancelled in `dispose()`; Kotlin: `close()`, or cancelling the coroutine that collects `observe`); no result objects kept in state; narrow observers per screen region; backpressure for slow work; no counting, logging, or side effect per callback (intermediate states are skipped); no error escaping a callback | `query-sync`, `performance-observability` |
| Data model | Arrays edited by several devices; whole-document rewrites; stored totals; sequential or timestamp-only IDs; consistent type declarations; documents that can grow without bound; counters written by `SET`, an upsert, or `RESTART WITH`, or removed with `DELETE` or `UNSET`; `UNSET` of map entries that others edit; own timestamps that decide a winner; timestamps of varying precision; renamed or retyped fields | `data-modeling` |
| Deletion | Strategy per collection (DELETE, soft delete, EVICT); offline periods vs tombstone TTL; `DELETE` not used to free local storage; no `WHERE` built from optional filters that can end up empty; the flag and `deletedAt` set together; eviction complementary to subscriptions, at most daily | `storage-lifecycle` |
| Transactions | Only the transaction object's `execute` inside, each awaited; no nesting, including through helper methods; no I/O or dialogs inside; `isReadOnly` for transactions that only read; an error caught inside is either rolled back or continued on purpose; pending work awaited before closing | `transactions-attachments` |
| Attachments | Explicit, lazy, cancellable fetches with a stall timeout; ATTACHMENT declarations; no binaries in documents; a state for a blob that no peer can deliver yet | `transactions-attachments` |
| Startup and lifecycle | One instance per persistence directory; auth handler set before sync starts, login result checked the SDK's way, no error escaping the handler; system parameters passed in `DittoConfig` on every open (SDK 5.2+; on 5.1, `ALTER SYSTEM` after open and before sync starts); no close on background; writes that must reach another device confirmed before closing; transports changed with `updateTransportConfig` | `sdk-setup` |
| Security | No development token or keyless small-peers mode in production; no hardcoded keys; permissions in the webhook based on immutable `_id` fields; nothing sensitive in peer metadata; users signed out of shared devices as in `§ Switching users on a shared device` | `sdk-setup` |
| Indexes and queries | Indexes created at startup for hot filters, sorts, and JOIN keys; no mixed `ASC`/`DESC` composite keys while devices run 5.1.0; no functions on indexed fields; `ORDER BY` with a tie-breaker where order matters | `performance-observability` |
| Tests | Local-store tests for DQL statements, soft-delete filters, observer cleanup, and subscription registration | `testing` |
| SDK-specific behavior | The items for the app's SDK in `§ Specific to One SDK` (for example, Flutter `onChange` with an unconsumed `changes` stream, `async` observer handlers in JavaScript, Kotlin results read after their handler returns, a Swift `Ditto` instance without a strong reference), and *Behavior Specific to the <SDK> SDK* on the SDK page | `guide` |
| SDK version | Where devices still run 5.1.0: `USE IDS` in `DELETE`/`EVICT`, mixed-direction composite indexes (including ones from `ADVISE`), `ANY ... SATISFIES` on several properties, sorted index queries with projections, constants on the left of comparisons; values that Kotlin, Java, Swift, or C# stored incorrectly before 5.2 (`§ Known Issues in SDK 5.1.0`) | `guide` |

The complete severity-ranked list is the guide's `§ Anti-Pattern Checklist`, with the mistakes of each SDK in `§ Specific to One SDK`; the security-specific list is `§ Security Checklist`.

### Step 8: Report

Order findings by severity (CRITICAL: data loss, wrong results, crashes, security; HIGH: sync cost, memory, performance; MEDIUM: maintainability). For each finding:

```
[SEVERITY] file:line - <one-line problem>
Also: <other places of the same root cause, file:line each; omit if none>
Scenario: <for a finding that needs two devices: the shortest sequence of events that produces it; omit otherwise>
Impact: <what goes wrong at runtime, and when>
Fix: <the concrete change, with a short code or DQL snippet if useful>
Reference: <skill name> / § <guide heading>
```

End with: the SDK version and platforms reviewed, the inventory in compact form (per collection: subscriptions, reads, writes, removals), the areas checked with no findings, and anything not checked (for example code that was not available, which devices write a collection, how long devices stay offline, or behavior that needs a multi-device test). When a fact that the code cannot show, such as the platforms or the connection mode in step 2, is unknown, say so there instead of guessing. Mark findings that depend on a **Note (SDK ...)** behavior or on `§ Known Issues in SDK 5.1.0` as version-specific, and name the releases they apply to.

## Scanner Limits

- Line-based: a statement split across lines, or built in another function, can be missed.
- Not detectable: everything in steps 5 and 6 (checks used as locks, values written back after a read in app code, results taken as complete, queries wider than their subscriptions), nested transactions through helper methods, observers or subscriptions registered in render code, subscription scope design, array-vs-map decisions, eviction that overlaps an active subscription, missing indexes.
- Example and test code that demonstrates anti-patterns on purpose produces hits; treat them as such.

## More

- The inventory, the eight questions with what to look for in code, when a question does not apply, and how to report: [reference/cross-device-review.md](reference/cross-device-review.md)
- Scanner rules, patterns, and the guide section behind each: [reference/scanner-rules.md](reference/scanner-rules.md)
- Scanner source: [scripts/scan.py](scripts/scan.py)
- Full guide search: the `guide` skill
