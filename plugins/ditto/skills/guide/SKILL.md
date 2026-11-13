---
name: guide
description: Searches the complete Ditto SDK best practices guide (SDK 5.2.0, Flutter, JavaScript, Kotlin, Swift) bundled with this plugin, for answers the focused ditto skills do not cover. Use to look up a Ditto API, DQL keyword or function, system parameter, error message, an SDK's API or behavior, or the reasoning behind a rule, or when a Ditto question spans several topics.
---

# Ditto Best Practices Guide

The full guide (SDK 5.2.0) is in two directories: [reference/best-practices/](reference/best-practices/README.md), what to do and what to avoid, one page per topic that applies to every SDK, plus one page per SDK in `reference/best-practices/platforms/` with that SDK's API calls, code, and behavior; and [reference/knowledge/](reference/knowledge/README.md), how Ditto works, the reference material (CRDT merge rules, DQL functions, system collections and parameters, platform differences, SDK releases, glossary), and, in `reference/knowledge/observations/`, the observations from our testing with their numbers, including one page per SDK for what only that SDK does. Do not read them whole: search them and read only the sections you need. The focused skills (`query-sync`, `data-modeling`, `storage-lifecycle`, `transactions-attachments`, `performance-observability`, `sdk-setup`, `testing`, `audit`) summarize the guide; use this skill for details they leave out.

## How to Search

Search `reference/best-practices/` and `reference/knowledge/` by name, one search each (or both as paths). Do not search `reference/` itself: inside the Ditto Cookbook repository the two directories are symbolic links, which a search of their parent does not enter.

1. **Exact terms first.** Grep both directories for the exact API name (`registerObserverV2`), DQL keyword (`UPDATE_LOCAL_DIFF`), system parameter (`TOMBSTONE_TTL_HOURS`), or error text (`disallowed without appropriate index support`). Use `-n` and read about 40-150 lines around the best hit.
2. **Sections by heading.** A `§ <Heading>` citation in another skill is a heading in one of the pages, and every heading is unique across the guide: Grep `^#+ <Heading>`. To see the outline of a page, Grep `^#{1,3} ` in it with line numbers.
3. **Version-specific behavior.** Grep `Note \(SDK` for every caveat: **Note (SDK 5.1.0 and 5.2.0)** was confirmed on both releases, **Note (SDK 5.1.0)** describes 5.1.0 behavior that 5.2.0 no longer shows (the note says what 5.2.0 does), and **Note (SDK 5.2.0)** was observed on 5.2.0 (the note or its observation entry says whether 5.1.0 differed or was not tested). Issues that only 5.1.0 has (fixed in 5.2.0) are listed under `§ Known Issues in SDK 5.1.0`; read it whenever a device runs 5.1.0. Grep `\(SDK 5.1\+\)` and `\(SDK 5.2\+\)` for APIs added in 5.1 and 5.2, and `Experimental|Beta` for unstable APIs. If the project uses another SDK version, treat these as items to verify, not facts.
4. **Read whole subsections.** Each section is written to be read on its own and ends with ✅ DO / ❌ DON'T lists and `✅ GOOD` / `❌ BAD` examples; read to the next heading of the same level before answering.
5. **Code for one SDK.** The topic pages show DQL with its arguments as an `-- Arguments:` JSON comment and link to the SDK pages for code. The SDK pages share their section names, `<Topic> in <SDK>` (Grep `^#+ .* in Swift` for the Swift outline), and end with *Behavior Specific to the <SDK> SDK*.

## Where Things Are

Best practices, in `reference/best-practices/`:

| Page | Covers |
|---|---|
| `README.md` | How to use the guide (audience, conventions such as (SDK 5.1+)/(SDK 5.2+), Experimental/Beta, and the Note (SDK ...) labels, how the content was verified), the ten essential rules, the disclaimer |
| `setup-and-lifecycle.md` | Requirements, DittoConfig, one shared instance, startup order, authentication, switching users, system parameters (in `DittoConfig`, `ALTER SYSTEM`), sync start/stop, shutdown, transports, presence and recording it in documents |
| `dql.md` | Where queries run, parameters and literals, MISSING vs NULL, query results, error messages and empty results (a lookup table); SELECT (projections, DISTINCT, aggregates, GROUP BY, ORDER BY, LIMIT, USE IDS, membership, JOIN); INSERT and ON ID CONFLICT, UPDATE, RETURNING, DELETE and EVICT |
| `data-modeling.md` | Strict mode, arrays vs maps, document structure and size, relationships, IDs, counters, checks and claims across devices (locks, uniqueness, sequence numbers, invariants), event history, INITIAL documents, schema evolution, timestamps |
| `sync-and-subscriptions.md` | Subscription rules and lifecycle, scope balancing, sync scopes, monitoring sync status, a lookup of causes when data does not sync |
| `observers.md` | The observer APIs of each SDK, when observers fire (by query shape), observer lifecycle, writing from observers on several devices, backpressure and choosing an observer API, diffing, partial UI updates |
| `transactions.md` | `store.transaction` in each SDK, rules, concurrency, sync |
| `attachments.md` | Architecture, creating, fetching, immutability, thumbnails, availability, size |
| `deletion-and-storage.md` | DELETE and tombstones, soft delete, EVICT, choosing a strategy, monitoring storage |
| `indexing-and-performance.md` | Creating indexes, index usage rules, ADVISE, EXPLAIN and PROFILE, query scope |
| `logging-and-observability.md` | Logging, support bundles, remote diagnostics |
| `security.md` | Authentication in production, small-peers-only keys, permissions, revocation, incoming connections, data at rest (encryption on Swift and Kotlin), webhooks, security checklist |
| `testing.md` | What a local-store test helper does; merge, deletion, observer, subscription, and DQL tests as statements and expected results; multi-peer tests |
| `anti-patterns.md` | Questions to ask of every collection (assumptions that fail across devices), then a severity-ranked review list (Critical, High, Medium), with a list per SDK |
| `quick-reference.md` | Condensed DO list, where to look when something goes wrong, common DQL shapes and the SDK sections with code |
| `platforms/flutter.md`, `platforms/javascript.md`, `platforms/kotlin.md`, `platforms/swift.md` | One page per SDK, with the same sections: installing, opening and `DittoConfig`, one shared instance, app startup, authentication, switching users, sync and the app lifecycle, closing, executing DQL, argument and value types, query results, subscriptions, store observers (lifecycle, backpressure, diffing, partial UI updates), transactions, attachments, IDs and timestamps, transports and presence, logging, testing, and the behavior specific to the SDK |

Knowledge, in `reference/knowledge/`:

| Page | Covers |
|---|---|
| `understanding-ditto.md` | What Ditto is, key characteristics, core principles |
| `crdt-types.md` | CRDT types, how values are typed, merge semantics, what concurrent edits produce, rewriting an unchanged value, what syncs after offline edits, reordering on two devices, conditions across devices, local write semantics, choosing a type |
| `dql-functions.md` | Date and time, conditional, type checking, string, object, array, ANY/EVERY, conversion functions |
| `system-reference.md` | System virtual collections, system parameters reference |
| `platform-differences.md` | The APIs and the behavior of Flutter, JavaScript, Kotlin, and Swift side by side, with links to the SDK pages |
| `upgrading.md` | Changes in SDK 5.2.0, known issues of 5.1.0 that 5.2.0 fixed (for devices that still run 5.1.0), mixed releases, rolling back |
| `glossary.md`, `references.md` | Terms and external documentation links |

Observations from our testing, in `reference/knowledge/observations/`, one entry per observation with the SDK releases, the setup, every number, and what was not tested. Read them for the evidence behind a rule, or when a question is about how Ditto behaved:

| Page | Covers |
|---|---|
| `observations/how-we-tested.md` | The test environment and its limits, how to read the results, the checks of the guide |
| `observations/subscriptions-and-replication.md` | What subscriptions deliver and what registering them costs, relays, the initial sync, order and atomicity, sync traffic, stopping and closing, the list of subscriptions, sync status |
| `observations/connections-and-presence.md` | The TCP connection limit, meshes, WebSocket hubs, retries, detecting lost connections, presence, presence written to documents, peer metadata, accepting connections, shared keys |
| `observations/merge-behavior.md` | Concurrent edits, also between SDK releases, conditional updates, read-modify-write, reordering, renaming, counters |
| `observations/clocks-and-time.md` | Device clocks and last-writer-wins, how a wrong clock spreads, `clock()` in subscriptions and observers |
| `observations/storage-and-deletion.md` | Soft delete, tombstones and reaping, eviction, disk space, the write-ahead log, deleted data on disk |
| `observations/documents-and-limits.md` | The hard size limit across devices and releases, document weight, nesting depth |
| `observations/persistence-directory.md` | Copies of a directory, Database IDs, deleting parts of a directory, locks |
| `observations/dql-behavior.md` | Statements that held, writes and arguments, `USE IDS`, comparison and ordering, IDs and field names, indexes and query plans (SDK 5.1.0 issues, migration), long conditions and `ANY`, SDK 5.0.3 differences |
| `observations/performance-measurements.md` | Statements and write rates, many fields and collections, queries and indexes, memory, hub load |
| `observations/transaction-behavior.md` | Concurrency and reads, long transactions, deadlocked transactions |
| `observations/observer-behavior.md` | When observers fire, batching of changes, observers that write on several devices, observers of `system:` collections, release differences |
| `observations/attachment-behavior.md` | Relaying and fetching attachments, slow links, garbage collection of blobs |
| `observations/flutter-sdk.md`, `observations/javascript-sdk.md`, `observations/kotlin-sdk.md`, `observations/swift-sdk.md` | What one SDK's API does: opening and shutting down, errors, login, callbacks and handles, values of the language, calls after shutdown, transactions and their threads, logging |
| `observations/configuration-and-diagnostics.md` | Parameter defaults, environment variables, the offline license token, request diagnostics, logs |

## Answering

- Quote or paraphrase the guide precisely; keep its qualifiers ("in our testing", "SDK 5.1.0", "according to the 5.2.0 release notes", "Experimental"). Statements marked "in our testing" are behavior observed on the releases the statement names (Ditto's own behavior mostly with JavaScript SDK peers on one machine, and each SDK's API with that SDK), not documented guarantees; the observation pages give the setup and the numbers.
- Cite the section you used as `§ <Heading>` so the user can find it.
- If the guide does not cover the question, say so, and point to Ditto's documentation (https://docs.ditto.live) instead of guessing.
- Answer with the code of the project's SDK: the matching section of `reference/best-practices/platforms/<sdk>.md`. Do not translate one SDK's code to another; where the SDKs differ, the topic pages say so, and `§ Platform Differences` compares them.
