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

### Use It in Your App's Repository

To give everyone who works on an app the same Ditto rules, declare the marketplace and the plugin in the app repository's project settings. From the repository root:

```bash
claude plugin marketplace add ditto-examples/ditto-cookbook --scope project
claude plugin install ditto@ditto-cookbook --scope project
```

Commit the resulting `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "ditto-cookbook": {
      "source": { "source": "github", "repo": "ditto-examples/ditto-cookbook" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "ditto@ditto-cookbook": true
  }
}
```

The settings register the marketplace for each teammate who trusts the folder, but do not download the plugin: each teammate runs the `claude plugin install` command above once per clone. `autoUpdate` is optional; without it, third-party marketplaces such as this one are not updated automatically.

### Updating

The guide and the Skills change often, and an installed copy stays at its version until you update it:

```
/plugin marketplace update ditto-cookbook
```

From a shell, `claude plugin update ditto@ditto-cookbook` updates the installed plugin. To update automatically, run `/plugin`, open the **Marketplaces** tab, select `ditto-cookbook`, and select **Enable auto-update**. `claude plugin list` shows the installed version; the [changelog](https://github.com/ditto-examples/ditto-cookbook/blob/main/CHANGELOG.md) lists what changed.

The `guide` Skill and the `§` citations of every Skill need the guide pages, which the plugin bundles through symbolic links to `best-practices/` and `knowledge/` at the repository root. A checkout that leaves those directories out, or that does not create symbolic links, installs the plugin without the guide; the `audit` and `guide` Skills say so when it is missing.

## Reviewing Ditto Code

Ask Claude to review your Ditto code or a pull request, or invoke the `audit` Skill directly:

```
/ditto:audit lib/
/ditto:audit the changes on this branch against origin/main
/ditto:audit pull request 123
```

For a diff or a pull request, the Skill scans only the changed files, checks each collection that the change touches against every place in the repository that reads or writes it, and reports what the change introduces separately from problems that were already there. It does not change code unless you ask for fixes, and it asks before a fix that would change the shape of stored data. The report starts with a verdict, the number of findings by severity, and the first actions, followed by one entry per finding with its location, the sequence of events on two devices that produces it, its impact, the fix, whether the fix changes stored data, and a link to the guide section. Severities come from the guide's [Anti-Pattern Checklist](https://github.com/ditto-examples/ditto-cookbook/blob/main/best-practices/anti-patterns.md).

When you work inside this repository, you do not need to install the plugin: `.claude/skills/` contains symbolic links to the Skills in this directory, so Claude Code loads them as project Skills. Inside the repository, the guide directories under `skills/guide/reference/` are symbolic links too: search `reference/best-practices/` and `reference/knowledge/` by name, because a search of `reference/` alone does not enter them.

## Skills

| Skill | Use it for |
|---|---|
| `query-sync` | DQL reads and writes, parameters, MISSING vs NULL, subscription rules and lifecycle, observer registration and release, upserts, JOIN, RETURNING |
| `data-modeling` | CRDT-safe documents: merge behavior, maps instead of arrays, strict mode and type declarations, relationships, counters, IDs, document size, timestamps |
| `storage-lifecycle` | DELETE vs soft delete vs EVICT, tombstones and their TTL, husk documents, eviction with complementary subscriptions |
| `transactions-attachments` | `store.transaction` rules, shutdown with transactions in flight, creating, fetching, and replacing attachments |
| `performance-observability` | Observer performance and backpressure, narrow UI updates, redundant writes, indexes and query plans, logging |
| `sdk-setup` | `DittoConfig` and `Ditto.open`, authentication, system parameters, sync start and stop, shutdown, transports, presence, production security |
| `testing` | Local-store test helper, tests for DQL, filters, merge-sensitive writes, observers, and subscriptions, multi-peer tests in one process |
| `audit` | A review workflow: a bundled scanner for known anti-patterns, triage, a cross-device review of each collection (checks used as locks, results taken as complete, queries wider than their subscriptions), a manual checklist, schema changes marked additive or breaking (in the code and in the fixes it proposes), and a severity-ranked report |
| `guide` | Search the complete best practices guide for APIs, DQL functions, system parameters, error messages, and the reasoning behind a rule |

## How the Skills Are Built for Agents

- **Short descriptions, early rules.** Claude Code lists every Skill description in a shared budget, so each description is one paragraph that names the Ditto APIs and symptoms it covers. Each `SKILL.md` stays under about 5,000 tokens and puts the CRITICAL rules first, because that is what remains attached to the conversation after context compaction.
- **Progressive disclosure.** `SKILL.md` holds the rules, a workflow, and a checklist. Longer code and edge cases are in each Skill's `reference/` files, and complete examples are in `examples/`: DQL examples that apply to every SDK as `examples/*.sql`, and code examples per SDK in `examples/flutter/`, `examples/javascript/`, `examples/kotlin/`, and `examples/swift/`, with the same base name in every SDK. Claude reads them only when needed.
- **SDK and version awareness.** Every Skill starts by identifying the project's SDK (Flutter, JavaScript, Kotlin, or Swift) and its version, and reads only the sections it needs from that SDK's page of the guide (`best-practices/platforms/<sdk>.md`). A **Note (SDK ...)** names the releases on which the behavior was observed, and is verified before it is applied to another version; issues fixed in 5.2.0 are collected in the guide's `§ Known Issues in SDK 5.1.0`.
- **The guide travels with the plugin.** `skills/guide/reference/best-practices` and `skills/guide/reference/knowledge` are symbolic links to the guide's [best practices](../../best-practices/README.md) and [knowledge](../../knowledge/README.md) pages; Claude Code copies their content into installed copies of the plugin. The Skills cite the guide as `§ Heading`, every heading is unique across its pages, and Claude finds the section by searching for the heading, offline and for the exact guide version the Skills were written against.
- **Deterministic checks.** The `audit` Skill runs [`scan.py`](skills/audit/scripts/scan.py) (Python 3.8+, no dependencies) to find candidate anti-patterns in Dart, JavaScript, TypeScript, Swift, and Kotlin before reviewing by hand. See [Running the Scanner Yourself](#running-the-scanner-yourself).

## Running the Scanner Yourself

The scanner is one file without dependencies. An installed plugin keeps it at `~/.claude/plugins/cache/ditto-cookbook/ditto/<version>/skills/audit/scripts/scan.py`; in CI, download it from this repository at the commit you have reviewed. Pass the source directories or files:

```bash
python3 scan.py lib/ test/
```

In CI, scan the source files that a pull request adds or changes, and skip the scan when there are none (exit code 2 means that nothing was scanned):

```bash
git diff --name-only --diff-filter=d origin/main...HEAD -- '*.dart' '*.js' '*.mjs' '*.cjs' '*.jsx' '*.ts' '*.tsx' '*.swift' '*.kt' '*.kts' > changed.txt
if [ -s changed.txt ]; then python3 scan.py --fail-on HIGH $(cat changed.txt); fi
```

Every hit is a candidate for review, not a confirmed defect, and its severity is that of the item it detects in the Anti-Pattern Checklist. It skips build output, dependencies, and generated files (`build`, `node_modules`, `Pods`, `*.g.dart`, `*.d.ts`, and others); `--exclude GLOB` skips more. A comment `ditto-scan: ignore[rule-id]` on the line, or on a comment line directly above it, suppresses a hit you have reviewed.

| Exit code | Meaning |
|---|---|
| 0 | The scan finished, with or without hits |
| 1 | A hit at or above the `--fail-on` severity was reported |
| 2 | A path does not exist, no source file was scanned, or the arguments are invalid |

A summary of the files scanned and the hits by severity goes to stderr, so `--json` output on stdout stays a plain array of hits. `python3 scan.py --help` lists every option, and [scanner-rules.md](skills/audit/reference/scanner-rules.md) lists the rules.

## Evals

[`evals/`](evals/) holds behavior tests for `claude plugin eval`: each case checks that the right Skill is used and that the answer follows the guide, and one case checks that the Skills stay out of unrelated SQL work. See [evals/README.md](evals/README.md).

## Maintenance

The Skills are derived from the Ditto best practices guide ([best practices](../../best-practices/README.md) and [knowledge](../../knowledge/README.md)), which is the source of truth. After changing the guide, update the Skills as described in [Synchronizing a Change to the Guide](../../CONTRIBUTING.md#synchronizing-a-change-to-the-guide), including the Skill format, the version bump, and the checks to run.

## Learn More

- [Ditto SDK best practices](../../best-practices/README.md) and [knowledge](../../knowledge/README.md)
- [Ditto documentation](https://docs.ditto.live)
- [Claude Code Skills](https://code.claude.com/docs/en/skills) and [plugins](https://code.claude.com/docs/en/plugins)
