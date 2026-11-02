# Ditto SDK Best Practices

> **Version**: 4.2
> **Last Updated**: 2026-11-02
> **Applies to**: Ditto SDK 5.2.0 (Flutter `ditto_live` 5.2.0; notes for JavaScript, Swift, and Kotlin where behavior differs). Issues that affect only SDK 5.1.0 are listed in [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510).

This guide helps you build offline-first applications on the Ditto SDK that stay correct when many devices change the same data without a connection. It concentrates on two kinds of guidance:

- **Decisions that are hard to change later**: the data model, document IDs, subscription scope, deletion strategy, and security model. Mistakes here tend to surface only after release, when devices in the field already hold data that you cannot easily migrate.
- **Mistakes that fail silently**: patterns that raise no error but lose concurrent edits, hide documents from queries, let memory grow, or cause unnecessary sync traffic.

The guide complements the [Ditto documentation](https://docs.ditto.live), which remains the reference for every API. It describes SDK 5.x behavior only; if you are upgrading an application from SDK v4, follow the [migration guides](https://docs.ditto.live/sdk/latest/v5-whats-new) first.

The guide has two parts: these best practices, which say what to do and what to avoid, and the [knowledge pages](../knowledge/README.md), which explain how Ditto works and collect the reference material that the best practices build on. The version and date above cover both parts.

## How to Use This Guide

**Who it is for**: Developers and architects who build, review, or operate applications on the Ditto SDK. The guide assumes familiarity with SQL and with your platform's asynchronous programming model. No prior knowledge of CRDTs is needed.

**Where to start**:

| If you are... | Start with |
|---|---|
| New to Ditto | [The Essentials](#the-essentials), [Understanding Ditto](../knowledge/understanding-ditto.md), then [SDK Setup and Lifecycle](setup-and-lifecycle.md) |
| Designing a data model or sync scope | [Data Modeling](data-modeling.md), [Sync and Subscriptions](sync-and-subscriptions.md), and [Deletion and Storage Management](deletion-and-storage.md) |
| Reviewing code or preparing a release | [Anti-Pattern Checklist](anti-patterns.md), [Security Checklist](security.md#security-checklist), and [Testing Strategies](testing.md) |
| Upgrading from SDK 5.1, or running devices that still use 5.1.0 | [Upgrading from SDK 5.1](../knowledge/upgrading.md) |
| Looking for a condensed summary or copyable code | [Quick Reference](quick-reference.md) |
| Looking up one API, statement, or error | Search for the exact API name, DQL keyword, system parameter, or error message. Each section is written to be read on its own. |

**Conventions**:

- **Code examples** use Flutter (Dart) with `import 'package:ditto_live/ditto_live.dart';`. The DQL statements, the data modeling guidance, and the sync behavior apply to every SDK; where the JavaScript, Swift, or Kotlin APIs or behavior differ, the guide says so (see [Platform Differences](../knowledge/platform-differences.md)).
- **✅ DO / ❌ DON'T**: Each topic lists recommended practices and anti-patterns, followed by examples marked `// ✅ GOOD` and `// ❌ BAD`.
- **(SDK 5.1+)** / **(SDK 5.2+)**: Marks features introduced in Ditto SDK 5.1 or 5.2 (a few small features, such as `object_size()`, carry the mark because SDK 5.0.3 did not support them in our testing; see [Some features that are not marked SDK 5.1+ fail on 5.0.3](../knowledge/dql-behavior.md#some-features-that-are-not-marked-sdk-51-fail-on-503)). Everything else is available in 5.0 and later.
- **(Experimental)** / **(Beta)**: Marks APIs that the SDK itself marks as experimental or beta. Their signatures or behavior may change in a future release.
- **Note (SDK ...)**: Describes behavior that is easy to miss and can lead to wrong results, lost data, crashes, or hangs, together with the pattern that avoids it. The label names the releases on which we observed it: **Note (SDK 5.1.0 and 5.2.0)** was confirmed on both releases, and **Note (SDK 5.1.0)** was observed on 5.1.0 and has not yet been repeated on 5.2.0 (the 5.2.0 release notes describe no change unless the note says so). Search for "Note (SDK" to list them all, and review them when you upgrade the SDK: a later release may change the behavior. Issues that 5.2.0 fixed are collected in [Known Issues in SDK 5.1.0](../knowledge/upgrading.md#known-issues-in-sdk-510).
- **Placeholders** such as `'YOUR_DATABASE_ID'`, `'YOUR_SERVER_URL'`, `'YOUR_PROVIDER_NAME'`, `fetchAuthToken()`, and `showError()` stand for values and code from your own application.

**How the content was verified**: Statements that say a behavior was observed "in our testing" summarize observations that the knowledge pages describe in full, with the SDK releases, the setup, every number, and what was not tested; [How We Tested](../knowledge/how-we-tested.md) describes the environment they share (mostly the JavaScript SDK on Node.js, with peers on one machine connected over TCP) and the checks that run on every change of the guide, such as running every DQL statement on SDK 5.1.0 and 5.2.0. Each such statement, and each **Note (SDK ...)**, names the releases on which we observed it; one that names only 5.1.0 has not yet been repeated on 5.2.0. These observations describe how those releases behaved, not a documented guarantee. Statements that the 5.2.0 release notes are the only source for say so.

## The Essentials

If you take only ten things from this guide, take these. Each one links to the section that explains it.

1. **Subscriptions decide what syncs; queries read only the local store.** Register long-lived subscriptions, scoped by stable keys such as tenant, store, or user, in an app-level service. Filter screens with local queries and observers instead of re-registering subscriptions. See [Core Principles](../knowledge/understanding-ditto.md#core-principles) and [Subscription Lifecycle](sync-and-subscriptions.md#subscription-lifecycle).
2. **Write only what changed.** Update individual fields with `UPDATE ... SET` instead of rewriting whole documents. Assigning an object, or upserting a document, merges keys into what is stored and never removes any; remove keys with `UNSET`. See [Prefer field-level updates over whole-document rewrites](dql.md#prefer-field-level-updates-over-whole-document-rewrites) and [Assigning an object merges it](dql.md#assigning-an-object-merges-it).
3. **Model every shared field for the merge you want.** Use maps keyed by ID for lists that several devices edit (an array is replaced as a whole), `COUNTER` for tallies, and values computed at read time instead of stored totals. See [What concurrent edits produce](../knowledge/crdt-types.md#what-concurrent-edits-produce).
4. **Generate collision-free IDs.** Use UUIDs, or composite `_id` objects that contain a UUID, and never sequential numbers. Put the attributes that permissions depend on into `_id`, because `_id` cannot change. See [Document IDs](data-modeling.md#document-ids).
5. **Choose a deletion strategy per collection.** Prefer a soft delete for shared records that several devices edit, and wherever devices can stay offline longer than the tombstone TTL (7 days by default); `DELETE` is safe only when neither applies. To free storage on one device, use `EVICT` on documents that no active subscription matches. See [Choosing DELETE, Soft Delete, or EVICT](deletion-and-storage.md#choosing-delete-soft-delete-or-evict).
6. **Pass system parameters in `DittoConfig` every time you open Ditto.** System parameters are not persisted. `DittoConfig.systemParameters` (SDK 5.2+) applies them before Ditto starts and makes `Ditto.open()` fail on an unknown name or a wrong type; use `ALTER SYSTEM` only to change a value while the app runs. See [Applying System Parameters](setup-and-lifecycle.md#applying-system-parameters).
7. **Pass every value as a parameter, and account for missing fields.** Use `:name` placeholders, `IN :values` for membership, and `coalesce(flag, false) = false` for optional flags. See [Parameters and Literals](dql.md#parameters-and-literals) and [MISSING and NULL](dql.md#missing-and-null).
8. **Keep documents small.** Stay well below 256 KiB per document, store files as attachments, and fetch attachments only when they are shown. See [Document Size Limits](data-modeling.md#document-size-limits) and [Attachments](attachments.md).
9. **Release everything you register.** Cancel subscriptions and observers, and stop attachment fetchers, explicitly. In Flutter, consume an observer's `changes` stream instead of passing only `onChange`. See [Resource Cleanup and Shutdown](setup-and-lifecycle.md#resource-cleanup-and-shutdown) and [Store Observers in Flutter](observers.md#store-observers-in-flutter).
10. **Secure production deployments.** Authenticate through a webhook provider (never the development token), or use a provisioned `privateKey` in small-peers-only deployments, and never hardcode keys. See [Security Checklist](security.md#security-checklist).

Before release, check your code against the [Anti-Pattern Checklist](anti-patterns.md), and cover your queries and merge-sensitive writes with tests (see [Testing Strategies](testing.md)).

## Pages

| Page | Covers |
|---|---|
| [SDK Setup and Lifecycle](setup-and-lifecycle.md) | Requirements, `DittoConfig` and `Ditto.open`, authentication, applying system parameters, starting and stopping sync, shutdown, transports, presence |
| [Reading and Writing Data with DQL](dql.md) | Where queries run, parameters and literals, MISSING and NULL, query results, `SELECT` (projections, aggregates, `GROUP BY`, `ORDER BY`, `LIMIT`, `USE IDS`, membership, `JOIN`), `INSERT` and `ON ID CONFLICT`, `UPDATE`, `RETURNING`, `DELETE` and `EVICT` |
| [Data Modeling](data-modeling.md) | Strict mode, arrays and maps, document structure and size, relationships, document IDs, counters, event history, `INITIAL DOCUMENTS`, schema evolution, timestamps |
| [Sync and Subscriptions](sync-and-subscriptions.md) | Subscription rules and lifecycle, scope balancing, sync scopes, monitoring sync status |
| [Observing Changes](observers.md) | Store observers in Flutter, backpressure, diffing results, partial UI updates |
| [Transactions](transactions.md) | `store.transaction`, transaction rules, concurrency and duration, sync, other platforms |
| [Attachments](attachments.md) | Architecture, creating, fetching, immutability, thumbnails, availability, size |
| [Deletion and Storage Management](deletion-and-storage.md) | `DELETE` and tombstones, soft delete, `EVICT`, choosing a strategy, monitoring storage |
| [Indexing and Query Performance](indexing-and-performance.md) | Creating indexes, index usage rules, `ADVISE`, `EXPLAIN` and `PROFILE`, query scope |
| [Logging and Observability](logging-and-observability.md) | Logging, support bundles, remote diagnostics |
| [Security](security.md) | Security model, production authentication, small-peers-only deployments, permissions, certificate revocation, incoming connections, input validation, data at rest, webhooks, the security checklist |
| [Testing Strategies](testing.md) | A local-store test helper, tests for merge-sensitive writes, deletion, observers, subscriptions, and DQL, tests on several devices |
| [Anti-Pattern Checklist](anti-patterns.md) | A review list ranked by severity |
| [Quick Reference](quick-reference.md) | A condensed DO list and common code shapes |

## Disclaimer

This guide reflects Ditto SDK 5.2.0 as of the Last Updated date at the top of this page. We work to keep it accurate, but the SDK evolves, and the right design for your application depends on requirements that a general guide cannot know.

Before you rely on a recommendation:
- Check the [Ditto documentation](https://docs.ditto.live) and the release notes for the SDK version you use.
- Test the pattern in your own environment, with your own data and devices, before deploying it to production.
- Adapt it to your specific requirements.

This guide is provided "as is", without warranty of any kind, for educational and reference purposes, and it does not replace the Ditto documentation. You are responsible for how you apply this information in your projects.
