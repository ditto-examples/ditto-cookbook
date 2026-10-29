---
name: audit
description: Reviews code that uses the Ditto SDK against the Ditto best practices guide: runs a bundled scanner for known anti-patterns, triages each hit in context, walks the manual review checklist, and reports findings by severity with fixes. Use when asked to review, audit, or check Ditto code, before a release, or when unexplained sync, merge, deletion, or memory problems need a systematic look.
---

# Ditto Code Audit

A repeatable review of an app that uses the Ditto SDK. It combines a fast pattern scan with a manual checklist, and relies on the topic skills for the rules. Targets Ditto SDK 5.2.0; the scanner reads Dart, JavaScript/TypeScript, Swift, and Kotlin.

## Before You Apply

- Check the Ditto SDK version the project uses (`ditto_live` in `pubspec.lock`, `@dittolive/ditto` in `package-lock.json`, `DittoSwift` in `Package.resolved`, `com.ditto` in Gradle files). The rules target 5.2.0, checked on one device with the JavaScript SDK (system parameters, DQL, observers, diagnostics); Flutter and multi-peer behavior were observed with 5.1.0. **Note (SDK 5.1.0 and 5.2.0)** marks easy-to-miss behavior confirmed on both releases; **Note (SDK 5.1.0)** marks behavior observed on 5.1.0 and not yet repeated on 5.2.0. Issues that only 5.1.0 has are in `§ Known Issues in SDK 5.1.0`; they apply wherever any device still runs 5.1.0. On a later version, confirm a note (release notes, docs.ditto.live) before reporting it as a defect. **(SDK 5.1+)** and **(SDK 5.2+)** mark features introduced in 5.1 and 5.2.
- `§ <Heading>` cites a section of the full guide: find it with Grep for the heading text in `../guide/reference/ditto.md`.
- Review only; do not change code unless the user asks for fixes.

## Workflow

Copy this checklist and work through it:

```
Ditto audit progress:
- [ ] 1. Scope: list files that use Ditto (imports of ditto_live, @dittolive/ditto, DittoSwift, com.ditto)
- [ ] 2. Context: SDK version, platforms, connection mode (Ditto Server or small peers only)
- [ ] 3. Scan: run scripts/scan.py on the source directories
- [ ] 4. Triage: confirm or discard every scanner hit by reading the code around it
- [ ] 5. Manual review: walk the checklist below for what a scan cannot see
- [ ] 6. Report: findings by severity, then what was checked and what was not
```

### Step 3: Scan

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/scan.py lib/ test/
```

(`${CLAUDE_SKILL_DIR}` is this skill's directory; if it is not substituted, use the path of this file's directory.) Options: `--json` for machine-readable output, `--min-severity HIGH` to hide MEDIUM hits. The script needs only Python 3.8+. If Python is unavailable, Grep for the same patterns listed in [reference/scanner-rules.md](reference/scanner-rules.md).

Every hit is a candidate, not a finding. The scanner matches lines; it cannot tell a test fixture, a deliberate counter-example, or a validated identifier from a defect.

### Step 4: Triage

For each hit:
1. Read the surrounding function and its callers.
2. Open the rule in the skill the hit names (`query-sync`, `data-modeling`, `storage-lifecycle`, `transactions-attachments`, `performance-observability`, `sdk-setup`, `testing`) and check whether the code really breaks it.
3. For a hit whose message says it applies to SDK 5.1.0 only (fixed in 5.2.0), such as `delete-evict-use-ids` and `composite-index-mixed-direction`, check the version from step 2. If the project uses 5.1.0, or the version is unknown, report it at its severity. If it uses 5.2.0, keep it as a lower-severity note that the code breaks on devices still running 5.1.0 (the code cannot show which releases run in the field), and say so in the finding.
4. Keep confirmed hits; drop false positives silently unless the pattern is worth a comment (for example a validated key spliced into a backtick identifier).

### Step 5: Manual review

The scanner cannot see design and lifecycle problems. Check each area that the app uses, with the named skill's checklist:

| Area | What to look for | Skill |
|---|---|---|
| Subscriptions | Scoped by stable keys; owned by a long-lived service; not re-registered per screen, filter, or search; relays subscribe to what devices behind them need; soft-deleted documents stay in scope | `query-sync` |
| Observers | Registered outside `build()`; `changes` consumed once; stream subscription and observer cancelled in `dispose()`; no `QueryResult` kept in state; narrow observers per screen region | `query-sync`, `performance-observability` |
| Data model | Arrays edited by several devices; whole-document rewrites; stored totals; sequential or timestamp-only IDs; consistent type declarations; documents that can grow without bound | `data-modeling` |
| Deletion | Strategy per collection (DELETE, soft delete, EVICT); offline periods vs tombstone TTL; eviction complementary to subscriptions, at most daily | `storage-lifecycle` |
| Transactions | Only `tx.execute` inside; no nesting, including through helper methods; no I/O or dialogs inside; pending work awaited before `close()` | `transactions-attachments` |
| Attachments | Explicit, lazy, cancellable fetches with a stall timeout; ATTACHMENT declarations; no binaries in documents | `transactions-attachments` |
| Startup and lifecycle | One instance per persistence directory; auth handler set before `sync.start()` and never throwing; system parameters passed in `DittoConfig.systemParameters` on every open (SDK 5.2+; on 5.1, `ALTER SYSTEM` after open and before `sync.start()`); no `close()` on background; transports changed with `updateTransportConfig()` | `sdk-setup` |
| Security | No development token or keyless small-peers mode in production; no hardcoded keys; permissions in the webhook based on immutable `_id` fields; nothing sensitive in peer metadata | `sdk-setup` |
| Indexes and queries | Indexes created at startup for hot filters, sorts, and JOIN keys; no mixed `ASC`/`DESC` composite keys while devices run 5.1.0; no functions on indexed fields; `ORDER BY` with a tie-breaker where order matters | `performance-observability` |
| Tests | Local-store tests for DQL statements, soft-delete filters, observer cleanup, and subscription registration | `testing` |
| SDK version | Where devices still run 5.1.0: `USE IDS` in `DELETE`/`EVICT`, mixed-direction composite indexes (including ones from `ADVISE`), `ANY ... SATISFIES` on several properties, sorted index queries with projections, constants on the left of comparisons; values that Kotlin, Java, Swift, or C# stored incorrectly before 5.2 (`§ Known Issues in SDK 5.1.0`) | `guide` |

The complete severity-ranked list is the guide's `§ Anti-Pattern Checklist`; the security-specific list is `§ Security Checklist`.

### Step 6: Report

Order findings by severity (CRITICAL: data loss, wrong results, crashes, security; HIGH: sync cost, memory, performance; MEDIUM: maintainability). For each finding:

```
[SEVERITY] file:line - <one-line problem>
Impact: <what goes wrong at runtime, and when>
Fix: <the concrete change, with a short code or DQL snippet if useful>
Reference: <skill name> / § <guide heading>
```

End with: the SDK version and platforms reviewed, the areas checked with no findings, and anything not checked (for example code that was not available, or behavior that needs a multi-device test). Mark findings that depend on a **Note (SDK ...)** behavior or on `§ Known Issues in SDK 5.1.0` as version-specific, and name the releases they apply to.

## Scanner Limits

- Line-based: a statement split across lines, or built in another function, can be missed.
- Not detectable: nested transactions through helper methods, observers or subscriptions registered in `build()`, subscription scope design, array-vs-map decisions, eviction that overlaps an active subscription, missing indexes.
- Example and test code that demonstrates anti-patterns on purpose produces hits; treat them as such.

## More

- Scanner rules, patterns, and the guide section behind each: [reference/scanner-rules.md](reference/scanner-rules.md)
- Scanner source: [scripts/scan.py](scripts/scan.py)
- Full guide search: the `guide` skill
