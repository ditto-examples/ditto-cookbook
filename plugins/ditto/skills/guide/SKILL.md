---
name: guide
description: Searches the complete Ditto SDK best practices guide (SDK 5.2.0) bundled with this plugin, for answers the focused ditto skills do not cover. Use to look up a Ditto API, DQL keyword or function, system parameter, error message, platform difference, or the reasoning behind a rule, or when a Ditto question spans several topics.
---

# Ditto Best Practices Guide

The full guide is [reference/ditto.md](reference/ditto.md) (about 8,300 lines, SDK 5.2.0). Do not read it whole: search it and read only the sections you need. The focused skills (`query-sync`, `data-modeling`, `storage-lifecycle`, `transactions-attachments`, `performance-observability`, `sdk-setup`, `testing`, `audit`) summarize it; use this skill for details they leave out.

## How to Search

1. **Exact terms first.** Grep `reference/ditto.md` for the exact API name (`registerObserverV2`), DQL keyword (`UPDATE_LOCAL_DIFF`), system parameter (`TOMBSTONE_TTL_HOURS`), or error text (`disallowed without appropriate index support`). Use `-n` and read about 40-150 lines around the best hit.
2. **Sections by heading.** A `§ <Heading>` citation in another skill is a heading in this file: Grep `^#{2,5} <Heading>`. To see the outline, Grep `^## ` (top-level sections) or `^### ` (subsections) with line numbers.
3. **Version-specific behavior.** Grep `Note \(SDK` for every caveat: **Note (SDK 5.1.0 and 5.2.0)** was confirmed on both releases, and **Note (SDK 5.1.0)** was observed on 5.1.0 and not yet repeated on 5.2.0. Issues that only 5.1.0 has (fixed in 5.2.0) are listed under `§ Known Issues in SDK 5.1.0`; read it whenever a device runs 5.1.0. Grep `\(SDK 5.1\+\)` and `\(SDK 5.2\+\)` for APIs added in 5.1 and 5.2, and `Experimental|Beta` for unstable APIs. If the project uses another SDK version, treat these as items to verify, not facts.
4. **Read whole subsections.** Each section is written to be read on its own and ends with ✅ DO / ❌ DON'T lists and `// ✅ GOOD` / `// ❌ BAD` code; read to the next heading of the same level before answering.

## Where Things Are

| Section (`^## `) | Covers |
|---|---|
| How to Use This Guide | Audience, conventions ((SDK 5.1+)/(SDK 5.2+), Experimental/Beta, the Note (SDK ...) labels), how the content was verified |
| The Essentials | The ten most important rules, each with a link |
| Understanding Ditto | What Ditto is, key characteristics, terminology, core principles |
| SDK Setup and Lifecycle | Requirements, DittoConfig, `Ditto.open`, authentication, system parameters (`DittoConfig.systemParameters`, `ALTER SYSTEM`), sync start/stop, shutdown, transports, presence, platform differences |
| DQL Fundamentals | Where queries run, parameters and literals, MISSING vs NULL, query results |
| Reading Data with SELECT | Projections, DISTINCT, aggregates, GROUP BY, ORDER BY, LIMIT, USE IDS, membership, JOIN |
| Writing Data | INSERT and ON ID CONFLICT, UPDATE, RETURNING, DELETE and EVICT |
| DQL Functions and Operators | Date and time, conditional, type checking, string, object, array, ANY/EVERY, conversion functions |
| Data Modeling | CRDT types, strict mode, arrays vs maps, document structure and size, relationships, IDs, counters, event history, INITIAL documents, schema evolution, timestamps |
| Sync and Subscriptions | Subscription rules and lifecycle, scope balancing, sync scopes, monitoring sync status |
| Observing Changes | Flutter store observers, backpressure, diffing, partial UI updates |
| Transactions | `store.transaction`, rules, concurrency, sync, other platforms |
| Attachments | Architecture, creating, fetching, immutability, thumbnails, availability, size |
| Deletion and Storage Management | DELETE and tombstones, soft delete, EVICT, choosing a strategy, monitoring storage |
| Indexing and Query Performance | Creating indexes, index usage rules, ADVISE, EXPLAIN and PROFILE, query scope |
| Logging and Observability | Logging, support bundles, system virtual collections, system parameters reference, remote diagnostics |
| Security | Authentication in production, small-peers-only keys, permissions, revocation, incoming connections, data at rest (encryption on Swift and Kotlin), webhooks, security checklist |
| Testing Strategies | Local-store test helper, merge, deletion, observer, and subscription tests, multi-peer tests |
| Upgrading from SDK 5.1 | Changes in SDK 5.2.0, known issues of 5.1.0 that 5.2.0 fixed (for devices that still run 5.1.0), rolling back |
| Anti-Pattern Checklist | Severity-ranked review list (Critical, High, Medium) |
| Quick Reference | Condensed DO list and common code shapes |
| Glossary, References | Terms and external documentation links |

## Answering

- Quote or paraphrase the guide precisely; keep its qualifiers ("in our testing", "SDK 5.1.0", "according to the 5.2.0 release notes", "Experimental"). Statements marked "in our testing" are behavior observed on the release the statement names, not documented guarantees; 5.2.0 checks were single-device runs with the JavaScript SDK.
- Cite the section you used as `§ <Heading>` so the user can find it.
- If the guide does not cover the question, say so, and point to Ditto's documentation (https://docs.ditto.live) instead of guessing.
- Code examples in the guide are Flutter (Dart) and were compiled against `ditto_live` 5.1.0; examples that use APIs added in 5.2 (such as `DittoConfig.systemParameters`) follow the `ditto_live` 5.2.0 API reference. For other platforms, use `§ Platform Differences` and the platform notes in each section.
