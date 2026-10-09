# Ditto SDK Agent Skills

This Claude Code plugin gives coding agents the Ditto SDK best practices: focused Skills for writing and reviewing Ditto code, a review workflow with an anti-pattern scanner, and the complete best practices guide for anything the Skills leave out. Everything targets Ditto SDK 5.1.0. Flutter (Dart, package `ditto_live`) is the primary platform; JavaScript, Swift, and Kotlin are covered where their APIs or behavior differ.

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

When you work inside this repository, you do not need to install the plugin: `.claude/skills/` contains symbolic links to the Skills in this directory, so Claude Code loads them as project Skills.

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
- **Version awareness.** Every Skill starts by checking the Ditto SDK version of the project. Behavior marked **Note (SDK 5.1.0)** is specific to that release and is verified before it is applied to another version.
- **The guide travels with the plugin.** `skills/guide/reference/ditto.md` links to the [best practices guide](../../best-practices/ditto.md); Claude Code copies its content into installed copies of the plugin. The Skills cite it as `§ Heading`, and Claude finds the section by searching for the heading, offline and for the exact guide version the Skills were written against.
- **Deterministic checks.** The `audit` Skill runs [`scan.py`](skills/audit/scripts/scan.py) (Python 3.8+, no dependencies) to find candidate anti-patterns in Dart, JavaScript, TypeScript, Swift, and Kotlin before reviewing by hand. You can run it yourself: `python3 skills/audit/scripts/scan.py path/to/app/lib`.

## Evals

[`evals/`](evals/) holds behavior tests for `claude plugin eval`: each case checks that the right Skill is used and that the answer follows the guide, and one case checks that the Skills stay out of unrelated SQL work. See [evals/README.md](evals/README.md).

## Maintenance

The Skills are derived from the [Ditto best practices guide](../../best-practices/ditto.md), which is the source of truth. After changing the guide, follow the [synchronization workflow](../../.claude/rules/ditto-best-practices-sync.md):

1. Update the affected Skills (`SKILL.md`, `reference/`, `examples/`), keeping the format: `name` and `description` only in the frontmatter, a description of at most about 450 characters, `SKILL.md` under 20,000 characters, and guide citations as `§ Heading`.
2. Run `python3 scripts/check-ditto-skills.py` from the repository root. It checks the format, every `§ Heading` citation, relative links, and the generated scanner rules.
3. Bump `version` in `.claude-plugin/plugin.json` and run `claude plugin validate . --strict` from the repository root.
4. For rule or description changes, run the evals.

## Learn More

- [Ditto best practices guide](../../best-practices/ditto.md)
- [Ditto documentation](https://docs.ditto.live)
- [Claude Code Skills](https://code.claude.com/docs/en/skills) and [plugins](https://code.claude.com/docs/en/plugins)
