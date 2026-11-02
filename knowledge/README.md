# Ditto SDK Knowledge

How Ditto works, what we observed when we tested it, and the reference material that the [best practices](../best-practices/README.md) build on. These pages are part of the same guide as the best practices: they share its version and date, its conventions (such as the **Note (SDK ...)** labels), and its disclaimer, all in the [best practices overview](../best-practices/README.md).

## How These Pages Fit Together

The knowledge pages are of two kinds:

- **Concepts and reference**, the pages in this directory, explain how Ditto works and collect what you look up: the CRDT types and their merge rules, the DQL functions, the system collections and parameters, the platform differences, the changes between SDK releases, and the terms. They follow Ditto's documentation, and where our testing adds to it, they state the result in a sentence and link to the observation.
- **Observations**, the pages in [`observations/`](observations/how-we-tested.md), describe what we saw when we ran Ditto, one entry per observation, on the page of the part of Ditto that it concerns. Each entry holds the evidence in full; the best practices and the concept pages summarize it and link to the entry.

The setup, the full results, and the number of runs of an observation appear only in its entry, so that a result is stated in one place and checked in one place. A page that summarizes it quotes only the numbers it needs, as the entry gives them.

### Reading an observation

Each entry starts with a heading that states what we observed, followed by a table:

| Row | Contents |
|---|---|
| **Observed on** | The SDK releases and the number of runs on each, and whether the runs agreed |
| **Setup** | The devices, the data, and the steps |
| **Documentation** | What Ditto's documentation or release notes say about the behavior, when they describe it |

The results follow, with every number and separately for each release where they differ. **Not tested** lists what the entry does not cover, and **Used in** names the sections that rely on it ("none yet" when no section does). [How We Tested](observations/how-we-tested.md) describes the environment that all entries share and how to read their numbers.

### Where an observation belongs

An observation goes on the page of the part of Ditto that it concerns, as listed in the table of observation pages below. Two cases need a rule:

- **Differences between SDK releases** go on the page of the behavior, in the same entry as the result on the other releases. [Upgrading from SDK 5.1](upgrading.md) summarizes the differences and links to those entries.
- **Measurements of cost**, such as the time of a local operation, a write rate, memory, or CPU load, go on [Performance Measurements](observations/performance-measurements.md). Times that describe when something happens, such as how long a lost connection takes to notice, stay with the behavior.

## Concepts and Reference

| Page | Covers |
|---|---|
| [Understanding Ditto](understanding-ditto.md) | What Ditto is, key characteristics, core principles |
| [CRDT Types and Merge Behavior](crdt-types.md) | The CRDT types, how values are typed, merge semantics, what concurrent edits produce, rewriting an unchanged value, what syncs after offline edits, reordering on two devices, conditions across devices, local write semantics, choosing a type |
| [DQL Functions and Operators](dql-functions.md) | Date and time, conditional, type checking, string, object, and array functions, `ANY` and `EVERY`, transformations, arithmetic and conversion |
| [System Collections and Parameters](system-reference.md) | The `system:` virtual collections, and the system parameters with their defaults |
| [Platform Differences](platform-differences.md) | How the Flutter, JavaScript, Swift, and Kotlin APIs differ |
| [Upgrading from SDK 5.1](upgrading.md) | Changes in SDK 5.2.0, known issues of SDK 5.1.0, mixed releases, rolling back |
| [Glossary](glossary.md) | Terms as the guide uses them |
| [References](references.md) | Ditto documentation by topic |

## Observations

| Page | Covers |
|---|---|
| [How We Tested](observations/how-we-tested.md) | The test environment, how to read the results, what we did not test, the checks of the guide itself |
| [Subscriptions and Replication](observations/subscriptions-and-replication.md) | What subscriptions deliver, relays, the initial sync, the order and atomicity of changes, sync traffic, stopping and closing, the list of subscriptions, sync status |
| [Connections and Presence](observations/connections-and-presence.md) | The TCP connection limit, meshes and WebSocket, changing and retrying connections, detecting lost connections, the presence graph, peer metadata, accepting connections, shared keys |
| [Merge Behavior](observations/merge-behavior.md) | Concurrent edits on two or more devices and on different releases, conditional updates, read-modify-write, reordering, renaming, counters |
| [Clocks and Time](observations/clocks-and-time.md) | Device clocks and last-writer-wins, how a wrong clock spreads, `clock()` in subscriptions and observers |
| [Storage and Deletion](observations/storage-and-deletion.md) | Soft delete, tombstones and reaping, eviction, disk space, the write-ahead log, deleted data on disk |
| [Documents and Limits](observations/documents-and-limits.md) | The hard size limit across devices and releases, document weight, nesting depth, many fields and collections |
| [The Persistence Directory](observations/persistence-directory.md) | Copies of a directory, Database IDs, deleting parts of a directory, locks |
| [DQL Behavior](observations/dql-behavior.md) | Statements that held, writes and arguments, `USE IDS`, comparison and ordering, numbers and strings, IDs and field names, indexes and query plans, long conditions and `ANY`, differences on SDK 5.0.3, JavaScript values |
| [Transaction Behavior](observations/transaction-behavior.md) | Concurrency and reads, long transactions, transactions in JavaScript, closing Ditto in JavaScript |
| [Observer Behavior](observations/observer-behavior.md) | When observers fire, how changes are batched, observers of `system:` collections, differences between releases, observers and results in JavaScript |
| [Attachment Behavior](observations/attachment-behavior.md) | Relaying and fetching attachments, slow links, garbage collection of blobs |
| [Performance Measurements](observations/performance-measurements.md) | Statements and write rates, queries and indexes, memory, hub load |
| [Configuration and Diagnostics](observations/configuration-and-diagnostics.md) | Parameter defaults, environment variables, the offline license token, request diagnostics, logs |
