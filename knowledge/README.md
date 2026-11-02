# Ditto SDK Knowledge

How Ditto works, what we observed when we tested it, and the reference material that the [best practices](../best-practices/README.md) build on. These pages are part of the same guide as the best practices: they share its version and date, its conventions (such as the **Note (SDK ...)** labels), and its disclaimer, all in the [best practices overview](../best-practices/README.md).

The best practices state what to do and why, in brief, and link here for the evidence. The observation pages hold that evidence in full: each entry names the SDK releases and the number of runs, describes the setup, gives every number, and lists what was not tested.

## Concepts and Reference

| Page | Covers |
|---|---|
| [Understanding Ditto](understanding-ditto.md) | What Ditto is, key characteristics, terminology, core principles |
| [CRDT Types and Merge Behavior](crdt-types.md) | The CRDT types, how values are typed, merge semantics, what concurrent edits produce, rewriting an unchanged value, what syncs after offline edits, reordering on two devices, local write semantics, choosing a type |
| [DQL Functions and Operators](dql-functions.md) | Date and time, conditional, type checking, string, object, and array functions, `ANY` and `EVERY`, transformations, arithmetic and conversion |
| [System Collections and Parameters](system-reference.md) | The `system:` virtual collections, and the system parameters with their defaults |
| [Platform Differences](platform-differences.md) | How the Flutter, JavaScript, Swift, and Kotlin APIs differ |
| [Upgrading from SDK 5.1](upgrading.md) | Changes in SDK 5.2.0, known issues of SDK 5.1.0, mixed releases, rolling back |
| [Glossary](glossary.md) | Terms as the guide uses them |
| [References](references.md) | Ditto documentation by topic |

## Observations

| Page | Covers |
|---|---|
| [How We Tested](how-we-tested.md) | The test environment, how to read the results, what we did not test, the checks of the guide itself |
| [Subscriptions and Replication](subscriptions-and-replication.md) | What subscriptions deliver, relays, the initial sync, the order and atomicity of changes, sync traffic, stopping and closing, sync status |
| [Connections and Presence](connections-and-presence.md) | The TCP connection limit, meshes and WebSocket, changing and retrying connections, detecting lost connections, the presence graph, peer metadata, accepting connections, shared keys |
| [Merge Behavior](merge-behavior.md) | Concurrent edits on two or more devices, conditional updates, read-modify-write, reordering, renaming, counters |
| [Clocks and Time](clocks-and-time.md) | Device clocks and last-writer-wins, how a wrong clock spreads, `clock()` in subscriptions and observers |
| [Storage and Deletion](storage-and-deletion.md) | Soft delete, tombstones and reaping, eviction, disk space, the write-ahead log, deleted data on disk |
| [Documents and Limits](documents-and-limits.md) | The hard size limit across devices, document weight, nesting depth, many fields and collections |
| [The Persistence Directory](persistence-directory.md) | Copies of a directory, Database IDs, deleting parts of a directory, locks |
| [DQL Behavior](dql-behavior.md) | Statements that held, writes and arguments, comparison and ordering, numbers and strings, IDs and field names, type declarations, limits, differences from SDK 5.0.3 |
| [Performance Measurements](performance-measurements.md) | Statements and write rates, queries and indexes, memory, hub load |
| [Transactions and Observers](transactions-and-observers.md) | Concurrency and reads, transactions in JavaScript, closing, when observers fire |
| [Attachment Behavior](attachment-behavior.md) | Relaying and fetching attachments, slow links, garbage collection of blobs |
| [Configuration and Diagnostics](configuration-and-diagnostics.md) | Parameter defaults, environment variables, the offline license token, request diagnostics, logs |
