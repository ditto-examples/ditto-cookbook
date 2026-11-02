# Ditto SDK Knowledge

How Ditto works, and the reference material that the [best practices](../best-practices/README.md) build on: how concurrent edits merge, the DQL functions, the local system collections and parameters, the differences between the SDKs, and what changed between SDK releases. These pages are part of the same guide as the best practices: they share its version and date, its conventions (such as the **Note (SDK ...)** labels), and its disclaimer, all in the [best practices overview](../best-practices/README.md).

| Page | Covers |
|---|---|
| [Understanding Ditto](understanding-ditto.md) | What Ditto is, key characteristics, terminology, core principles |
| [CRDT Types and Merge Behavior](crdt-types.md) | The CRDT types, how values are typed, merge semantics, what concurrent edits produce, local write semantics, choosing a type |
| [DQL Functions and Operators](dql-functions.md) | Date and time, conditional, type checking, string, object, and array functions, `ANY` and `EVERY`, transformations, arithmetic and conversion |
| [System Collections and Parameters](system-reference.md) | The `system:` virtual collections, and the system parameters with their defaults |
| [Platform Differences](platform-differences.md) | How the Flutter, JavaScript, Swift, and Kotlin APIs differ |
| [Upgrading from SDK 5.1](upgrading.md) | Changes in SDK 5.2.0, known issues of SDK 5.1.0, rolling back |
| [Glossary](glossary.md) | Terms as the guide uses them |
| [References](references.md) | Ditto documentation by topic |
