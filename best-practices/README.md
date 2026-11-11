# Ditto SDK Best Practices

> **Version**: 5.19
> **Last Updated**: 2026-11-11
> **Applies to**: Ditto SDK 5.2.0 for Flutter (`ditto_live`), JavaScript (`@dittolive/ditto`), Kotlin (`com.ditto:ditto-kotlin`), and Swift (`DittoSwift`). Issues that affect only SDK 5.1.0 are listed in [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510).

This guide helps you build offline-first applications on the Ditto SDK that stay correct when many devices change the same data without a connection. It concentrates on two kinds of guidance:

- **Decisions that are hard to change later**: the data model, document IDs, subscription scope, deletion strategy, and security model. Mistakes here tend to surface only after release, when devices in the field already hold data that you cannot easily migrate, and a later change to what is stored must keep working with the app versions those devices still run (see [Breaking and additive changes](data-modeling.md#breaking-and-additive-changes)).
- **Mistakes that fail silently**: patterns that raise no error but lose concurrent edits, hide documents from queries, let memory grow, or cause unnecessary sync traffic.

The guide complements the [Ditto documentation](https://docs.ditto.live), which remains the reference for every API. It describes SDK 5.x behavior only; if you are upgrading an application from SDK v4, follow the [migration guides](https://docs.ditto.live/sdk/latest/v5-whats-new) first.

The guide has two parts: these best practices, which say what to do and what to avoid, and the [knowledge pages](../knowledge/README.md), which explain how Ditto works and collect the reference material that the best practices build on. The version and date above cover both parts.

The topic pages apply to every SDK: they state the rules, the reasons, and the DQL. How to apply them with one SDK, its API calls, its patterns for UI and app lifecycle, and the behavior specific to it, is on that SDK's page: [Flutter](platforms/flutter.md), [JavaScript](platforms/javascript.md), [Kotlin](platforms/kotlin.md), and [Swift](platforms/swift.md). The four SDK pages have the same sections.

## How to Use This Guide

**Who it is for**: Developers and architects who build, review, or operate applications on the Ditto SDK. The guide assumes familiarity with SQL and with your platform's asynchronous programming model. No prior knowledge of CRDTs is needed.

**Where to start**:

| If you are... | Start with |
|---|---|
| New to Ditto | [The Essentials](#the-essentials), [Understanding Ditto](../knowledge/understanding-ditto.md), then [SDK Setup and Lifecycle](setup-and-lifecycle.md) |
| Writing code with one SDK | The page of your SDK: [Flutter](platforms/flutter.md), [JavaScript](platforms/javascript.md), [Kotlin](platforms/kotlin.md), or [Swift](platforms/swift.md) |
| Designing a data model or sync scope | [Data Modeling](data-modeling.md), [Sync and Subscriptions](sync-and-subscriptions.md), and [Deletion and Storage Management](deletion-and-storage.md) |
| Reviewing code or preparing a release | [Anti-Pattern Checklist](anti-patterns.md), [Security Checklist](security.md#security-checklist), and [Testing Strategies](testing.md) |
| Upgrading from SDK 5.1, or running devices that still use 5.1.0 | [Upgrading from SDK 5.1](../knowledge/upgrading.md) |
| Looking for a condensed summary or copyable code | [Quick Reference](quick-reference.md) |
| Debugging data that does not sync, or a statement that fails or returns nothing | [When Data Does Not Sync](sync-and-subscriptions.md#when-data-does-not-sync), [When a Statement Fails or Returns Nothing](dql.md#when-a-statement-fails-or-returns-nothing), and [Diagnosing transport problems (SDK 5.1+)](setup-and-lifecycle.md#diagnosing-transport-problems-sdk-51) |
| Looking up one API, statement, or error | Search for the exact API name, DQL keyword, system parameter, or error message, and read the section to its next heading of the same level. Each section is written to be read on its own. |
| Writing or reviewing code with a coding agent | Install the [`ditto` Claude Code plugin](https://github.com/ditto-examples/ditto-cookbook/tree/main/plugins/ditto). Its Skills apply this guide while the agent writes or reviews Ditto code, and its `guide` Skill searches the complete guide. |

**Conventions**:

- **Code examples**: the topic pages show DQL in `sql` blocks, with the arguments of each statement as JSON in a comment above it (`-- Arguments: {"status": "open"}`); pass them as the arguments map of your SDK's `execute`, observer, or subscription call. Code that calls an SDK's API is on the SDK pages, which show the same examples in Flutter (Dart), JavaScript, Kotlin, and Swift. Where the SDKs' APIs or behavior differ, the topic pages say so in a table or link to the SDK pages (see also [Platform Differences](../knowledge/platform-differences.md)). A block marked `<!-- subscription -->` holds statements meant for `registerSubscription`, and one marked `<!-- expect-error -->` holds statements that fail on purpose.
- **✅ DO / ❌ DON'T**: Each topic lists recommended practices and anti-patterns, followed by examples marked `// ✅ GOOD` and `// ❌ BAD`.
- **(SDK 5.1+)** / **(SDK 5.2+)**: Marks features introduced in Ditto SDK 5.1 or 5.2. Everything else is available in 5.0 and later, apart from a few small features, such as `object_size()`, that carry the mark because SDK 5.0.3 rejected them in our testing (see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/observations/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)).
- **(Experimental)** / **(Beta)**: Marks APIs that the SDK itself marks as experimental or beta. Their signatures or behavior may change in a future release.
- **Note (SDK ...)**: Describes behavior that is easy to miss and can lead to wrong results, lost data, crashes, or hangs, together with the pattern that avoids it. The label names the releases on which we observed it: **Note (SDK 5.1.0 and 5.2.0)** was confirmed on both releases; **Note (SDK 5.1.0)** describes behavior of 5.1.0 that 5.2.0 no longer shows, and the note says what 5.2.0 does instead; **Note (SDK 5.2.0)** was observed on 5.2.0, and the note or its observation entry says whether 5.1.0 behaved differently or was not tested; a range such as **Note (SDK 5.0.3 to 5.2.0)** held on each of those releases. Search for "Note (SDK" to list them all, and review them when you upgrade the SDK: a later release may change the behavior. Issues that 5.2.0 fixed are collected in [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510).
- **Section citations**: The plugin Skills and the checklist cite a section as `§ Heading`. Every heading is unique across both parts of the guide, so a search for its text finds exactly one section.
- **Placeholders** such as `'YOUR_DATABASE_ID'`, `'YOUR_SERVER_URL'`, `'YOUR_PROVIDER_NAME'`, `fetchAuthToken()`, and `showError()` stand for values and code from your own application.

**How the content was verified**: A statement that a behavior was observed "in our testing" names the releases it was observed on and links to its observation entry, which gives the setup, every number, and what was not tested. It describes how those releases behaved, not a documented guarantee; statements whose only source is the 5.2.0 release notes say so. [How We Tested](../knowledge/observations/how-we-tested.md) describes the environment that the observations share (Ditto's own behavior mostly with the JavaScript SDK on Node.js, with peers on one machine connected over TCP, and each SDK's API with that SDK) and the checks of the guide itself: every DQL statement runs on SDK 5.1.0 and 5.2.0, and the code on each SDK page was built against SDK 5.2.0 and, where it can run without Ditto Server or a real device, run against a local store.

## The Essentials

If you take only ten things from this guide, take these. Each one links to the section that explains it.

1. **Subscriptions decide what syncs; queries read only the local store.** Register long-lived subscriptions, scoped by stable keys such as tenant, store, or user, in an app-level service, and register them again after every `Ditto.open()`. Filter screens with local queries and observers instead of re-registering subscriptions. See [Core Principles](../knowledge/understanding-ditto.md#core-principles) and [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle).
2. **Write only what changed.** Update individual fields with `UPDATE ... SET` instead of rewriting whole documents. Assigning an object, or upserting a document, merges keys into what is stored and never removes any; remove keys with `UNSET`. See [Prefer field-level updates over whole-document rewrites](dql.md#prefer-field-level-updates-over-whole-document-rewrites) and [Assigning an object merges it](dql.md#assigning-an-object-merges-it).
3. **Model every shared field for the merge you want.** Use maps keyed by ID for lists that several devices edit (an array is replaced as a whole), `COUNTER` for tallies, and values computed at read time instead of stored totals. A check before a write holds only on the device that makes it, so a local query, a conditional `UPDATE`, or a transaction is not a lock or a uniqueness check across devices. See [What Concurrent Edits Produce](../knowledge/crdt-types.md#what-concurrent-edits-produce) and [Checks and Claims across Devices](data-modeling.md#checks-and-claims-across-devices).
4. **Generate collision-free IDs.** Use UUIDs, or composite `_id` objects that contain a UUID, and never sequential numbers. Put the attributes that permissions depend on into `_id`, because `_id` cannot change. See [Document IDs](data-modeling.md#document-ids).
5. **Choose a deletion strategy per collection.** Prefer a soft delete for shared records that several devices edit, and wherever devices can stay offline longer than the tombstone TTL (7 days by default); `DELETE` is safe only when neither applies. To free storage on one device, use `EVICT` on documents that no active subscription matches. See [Choosing DELETE, Soft Delete, or EVICT](deletion-and-storage.md#choosing-delete-soft-delete-or-evict).
6. **Pass system parameters in `DittoConfig` every time you open Ditto.** System parameters are not persisted. The system parameters of `DittoConfig` (SDK 5.2+) are applied before Ditto starts, and opening Ditto fails on an unknown name or a wrong type; use `ALTER SYSTEM` only to change a value while the app runs. See [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters).
7. **Pass every value as a parameter, and account for missing fields.** Use `:name` placeholders, `IN :values` for membership, and `coalesce(flag, false) = false` for optional flags. See [Parameters and Literals](dql.md#parameters-and-literals) and [MISSING and NULL](dql.md#missing-and-null).
8. **Keep documents small.** Stay well below 256 KiB per document, store files as attachments, and fetch attachments only when they are shown. See [Document Size Limits](data-modeling.md#document-size-limits) and [Attachments](attachments.md).
9. **Release everything you register.** Cancel subscriptions and observers, and stop attachment fetchers, explicitly; garbage collection does not release them. Register each observer once per owner, in the way your SDK's page shows. See [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown) and [Observer Lifecycle](observers.md#observer-lifecycle).
10. **Secure production deployments.** Authenticate through a webhook provider (never the development token), or use a provisioned `privateKey` in small-peers-only deployments, and never hardcode keys. See [Security Checklist](security.md#security-checklist).

Before release, check your code against the [Anti-Pattern Checklist](anti-patterns.md), and cover your queries and merge-sensitive writes with tests (see [Testing Strategies](testing.md)).

## Pages

| Page | Covers |
|---|---|
| [SDK Setup and Lifecycle](setup-and-lifecycle.md) | Requirements, `DittoConfig` and one shared instance, authentication and switching users on a shared device, applying system parameters, starting and stopping sync, shutdown, transports, presence |
| [Reading and Writing Data with DQL](dql.md) | Where queries run, parameters and literals, MISSING and NULL, query results, error messages and empty results, `SELECT` (projections, aggregates, `GROUP BY`, `ORDER BY`, `LIMIT`, `USE IDS`, membership, `JOIN`), `INSERT` and `ON ID CONFLICT`, `UPDATE`, `RETURNING`, `DELETE` and `EVICT` |
| [Data Modeling](data-modeling.md) | Strict mode, arrays and maps, document structure and size, relationships, document IDs, counters, checks and claims across devices, event history, `INITIAL DOCUMENTS`, schema evolution, timestamps |
| [Sync and Subscriptions](sync-and-subscriptions.md) | Subscription rules and lifecycle, scope balancing, sync scopes, monitoring sync status, a lookup of causes when data does not sync |
| [Observing Changes](observers.md) | The observer APIs of each SDK, when observers fire, observer lifecycle, backpressure and choosing an observer API, diffing results, partial UI updates |
| [Transactions](transactions.md) | `store.transaction` in each SDK, transaction rules, concurrency and duration, sync |
| [Attachments](attachments.md) | Architecture, creating, fetching, immutability, thumbnails, availability, size |
| [Deletion and Storage Management](deletion-and-storage.md) | `DELETE` and tombstones, soft delete, `EVICT`, choosing a strategy, monitoring storage |
| [Indexing and Query Performance](indexing-and-performance.md) | Creating indexes, index usage rules, `ADVISE`, `EXPLAIN` and `PROFILE`, query scope |
| [Logging and Observability](logging-and-observability.md) | The logger of each SDK, log levels, on-disk logs, support bundles, remote diagnostics |
| [Security](security.md) | Security model, production authentication, small-peers-only deployments, permissions, certificate revocation, incoming connections, input validation, data at rest, webhooks, the security checklist |
| [Testing Strategies](testing.md) | What a local-store test helper does, tests for merge-sensitive writes, deletion, observers, subscriptions, and DQL, tests on several devices |
| [Anti-Pattern Checklist](anti-patterns.md) | Questions to ask of every collection, which find the assumptions that fail across devices, and a review list ranked by severity: mistakes possible in every SDK, then those specific to Flutter, JavaScript, Kotlin, or Swift |
| [Quick Reference](quick-reference.md) | A condensed DO list, where to look when something goes wrong, and common code shapes |

The SDK pages have the same sections: installing the SDK, opening Ditto and `DittoConfig`, authentication, sync and the app lifecycle, closing, executing DQL and value types, subscriptions, store observers (lifecycle, backpressure, diffing, partial UI updates), transactions, attachments, IDs and timestamps, transports and presence, logging, testing, and the behavior specific to the SDK.

| Page | SDK |
|---|---|
| [Ditto on Flutter](platforms/flutter.md) | `ditto_live` (Dart) on iOS, Android, macOS, Windows, Linux, and the Web |
| [Ditto on JavaScript](platforms/javascript.md) | `@dittolive/ditto` on Node.js, in browsers, and in React Native |
| [Ditto on Kotlin](platforms/kotlin.md) | `com.ditto:ditto-kotlin` on Android |
| [Ditto on Swift](platforms/swift.md) | `DittoSwift` on iOS and macOS |

## Disclaimer

This guide reflects Ditto SDK 5.2.0 as of the Last Updated date at the top of this page. We work to keep it accurate, but the SDK evolves, and the right design for your application depends on requirements that a general guide cannot know.

Before you rely on a recommendation:
- Check the [Ditto documentation](https://docs.ditto.live) and the release notes for the SDK version you use.
- Test the pattern in your own environment, with your own data and devices, before deploying it to production.
- Adapt it to your specific requirements.

This guide is provided "as is", without warranty of any kind, for educational and reference purposes, and it does not replace the Ditto documentation. You are responsible for how you apply this information in your projects.
