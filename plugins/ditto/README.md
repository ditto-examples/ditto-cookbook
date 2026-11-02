# Ditto SDK Agent Skills

This Claude Code plugin gives coding agents the Ditto SDK best practices: focused Skills for writing and reviewing Ditto code, a review workflow with an anti-pattern scanner, and the complete best practices guide for anything the Skills leave out. Everything targets Ditto SDK 5.2.0, and issues that affect only devices still on 5.1.0 are flagged. Flutter (Dart, package `ditto_live`) is the primary platform; JavaScript, Swift, and Kotlin are covered where their APIs or behavior differ.

## Installation

This repository is a Claude Code plugin marketplace named `ditto-cookbook`. Install the plugin in Claude Code (2.1.275 or later):

```
/plugin install ditto --marketplace ditto-examples/ditto-cookbook
```

On earlier versions, add the marketplace first, then install the plugin:

```
/plugin marketplace add ditto-examples/ditto-cookbook
/plugin install ditto@ditto-cookbook
```

The Skills are namespaced by the plugin name, for example `ditto:query-sync`. Claude loads a Skill when your code or question matches its description; you can also invoke one directly, for example `/ditto:audit lib/`.

When you work inside this repository, you do not need to install the plugin: `.claude/skills/` contains symbolic links to the Skills in this directory, so Claude Code loads them as project Skills. Inside the repository, the guide directories under `skills/guide/reference/` are symbolic links too: search `reference/best-practices/` and `reference/knowledge/` by name, because a search of `reference/` alone does not enter them.

## Skills

| Skill | Use it for |
|---|---|
| `query-sync` | DQL reads and writes, parameters, MISSING vs NULL, subscription rules and lifecycle, the Flutter observer pattern, upserts, JOIN, RETURNING |
| `data-modeling` | CRDT-safe documents: merge behavior, maps instead of arrays, strict mode and type declarations, relationships, counters, IDs, document size, timestamps |
| `storage-lifecycle` | DELETE vs soft delete vs EVICT, tombstones and their TTL, husk documents, eviction with complementary subscriptions |
| `transactions-attachments` | `store.transaction` rules, shutdown with transactions in flight, creating, fetching, and replacing attachments |
| `performance-observability` | Observer performance and backpressure, Flutter rebuild scope, redundant writes, indexes and query plans, logging |
| `sdk-setup` | `DittoConfig` and `Ditto.open`, authentication, system parameters, sync start and stop, shutdown, transports, presence, production security |
| `testing` | Local-store test helper, tests for DQL, filters, merge-sensitive writes, observers, and subscriptions, multi-peer tests in one process |
| `audit` | A review workflow: a bundled scanner for known anti-patterns, triage, a manual checklist, and a severity-ranked report |
| `guide` | Search the complete best practices guide for APIs, DQL functions, system parameters, error messages, and the reasoning behind a rule |

## How the Skills Are Built for Agents

- **Short descriptions, early rules.** Claude Code lists every Skill description in a shared budget, so each description is one paragraph that names the Ditto APIs and symptoms it covers. Each `SKILL.md` stays under about 5,000 tokens and puts the CRITICAL rules first, because that is what remains attached to the conversation after context compaction.
- **Progressive disclosure.** `SKILL.md` holds the rules, a workflow, and a checklist. Longer code and edge cases are in each Skill's `reference/` files, and complete, compiled examples are in `examples/`. Claude reads them only when needed.
- **Version awareness.** Every Skill starts by checking the Ditto SDK version of the project. A **Note (SDK ...)** names the releases on which the behavior was observed, and is verified before it is applied to another version; issues fixed in 5.2.0 are collected in the guide's `§ Known Issues in SDK 5.1.0`.
- **The guide travels with the plugin.** `skills/guide/reference/best-practices` and `skills/guide/reference/knowledge` are symbolic links to the guide's [best practices](../../best-practices/README.md) and [knowledge](../../knowledge/README.md) pages; Claude Code copies their content into installed copies of the plugin. The Skills cite the guide as `§ Heading`, every heading is unique across its pages, and Claude finds the section by searching for the heading, offline and for the exact guide version the Skills were written against.
- **Deterministic checks.** The `audit` Skill runs [`scan.py`](skills/audit/scripts/scan.py) (Python 3.8+, no dependencies) to find candidate anti-patterns in Dart, JavaScript, TypeScript, Swift, and Kotlin before reviewing by hand. You can run it yourself: `python3 skills/audit/scripts/scan.py path/to/app/lib`.

## Evals

[`evals/`](evals/) holds behavior tests for `claude plugin eval`: each case checks that the right Skill is used and that the answer follows the guide, and one case checks that the Skills stay out of unrelated SQL work. See [evals/README.md](evals/README.md).

## Maintenance

The Skills are derived from the Ditto best practices guide ([best practices](../../best-practices/README.md) and [knowledge](../../knowledge/README.md)), which is the source of truth. After changing the guide, update the Skills as described in [Synchronizing a Change to the Guide](../../CONTRIBUTING.md#synchronizing-a-change-to-the-guide), including the Skill format, the version bump, and the checks to run.

## Learn More

- [Ditto SDK best practices](../../best-practices/README.md) and [knowledge](../../knowledge/README.md)
- [Ditto documentation](https://docs.ditto.live)
- [Claude Code Skills](https://code.claude.com/docs/en/skills) and [plugins](https://code.claude.com/docs/en/plugins)
