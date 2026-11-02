# Contributing to Ditto Cookbook

Thank you for helping improve the Ditto Cookbook. This guide explains how the repository fits together and how to change each part.

## How the Repository Fits Together

The Ditto SDK best practices guide is the source of truth. It has two parts: [`best-practices/`](best-practices/README.md) says what to do and what to avoid, one page per topic, and [`knowledge/`](knowledge/README.md) explains how Ditto works and holds the reference material that the best practices build on. Everything else that is Ditto-specific is derived from the guide:

```
best-practices/ + knowledge/       The guide
├──> plugins/ditto/skills/         Agent Skills (the guide itself ships through symbolic links)
├──> checklist/                    Review checklist (Markdown and JSON sources → HTML)
└──> examples/simple-pos/          End-to-end Flutter example
```

A change to the guide is complete only when the derived content agrees with it. The repository covers Ditto only; general Flutter, Dart, or Claude Code material does not belong here.

## Prerequisites

- **Python 3.9 or later** for the check script
- **[uv](https://docs.astral.sh/uv/)** to build the checklist (it installs Pygments for syntax highlighting)
- **[Claude Code](https://code.claude.com)** to validate the plugin and run its evals

## Changing the Guide

### Where content belongs

- **`best-practices/`**: guidance on what to do, with ✅ DO / ❌ DON'T lists, recommended patterns, and review lists. Each page covers one topic.
- **`knowledge/`**: how Ditto behaves and reference material: concepts, merge rules, functions, system collections and parameters, platform differences, changes between SDK releases, and terms. **`knowledge/observations/`** holds what we observed in testing, one entry per observation.

Observations from testing flow in one direction: test → `knowledge/observations/` → `best-practices/` → Skills and checklist.

1. **Record the observation in `knowledge/observations/`.** Add an entry to the observation page of the part of Ditto that it concerns ([Where an observation belongs](knowledge/README.md#where-an-observation-belongs)), in the format of the existing entries ([Reading an observation](knowledge/README.md#reading-an-observation)): a heading that states the behavior; a table with "Observed on" (the SDK releases and the number of runs), "Setup", and, when Ditto's documentation or release notes describe the behavior, "Documentation"; the results with every number, separately for each release; "Not tested"; and "Used in" ("none yet" until a section uses it). Write one entry per finding: when one test shows two things that different sections use, or that hold on different releases, write two entries. A result on another release belongs in the entry for the same behavior. [How We Tested](knowledge/observations/how-we-tested.md) describes the environment that all entries share.
2. **Derive the rule in `best-practices/`.** State what to do, give the reason in a sentence or two with only the numbers that the rule needs, label release-specific behavior with **Note (SDK ...)**, and link to the knowledge entry for the evidence.
3. **Propagate the rule** to the Skills and the checklist (see [Synchronizing a Change to the Guide](#synchronizing-a-change-to-the-guide)).

The setup, the full results, and the number of runs of an observation appear only in its entry. Every other page that reports it, in `best-practices/` and on the concept and reference pages of `knowledge/`, states it in a sentence or two, quotes only the numbers that its point needs, as the entry gives them, and links to the entry; `scripts/check.py` reports a line with "in our testing" that has no such link, and an entry without "Setup" or "Used in".

When new material both explains a behavior and recommends a pattern, put the recommendation in `best-practices/` and link to the explanation in `knowledge/`. Keep each page readable on its own, and follow the conventions in [How to Use This Guide](best-practices/README.md#how-to-use-this-guide), such as the **Note (SDK ...)** labels.

### Headings and links

The Skills and the checklist cite sections by their heading text (`§ Heading`), so every heading must be unique across all pages of both directories. Renaming a heading breaks the citations that use it; `scripts/check.py` reports them. Link to another section with a relative link and its GitHub anchor, for example `[What Concurrent Edits Produce](../knowledge/crdt-types.md#what-concurrent-edits-produce)`. Write page titles and `##` headings in title case, and `###` headings, including the heading of each observation entry, in sentence case. When a section of another page links to an observation entry, add that section to the entry's "Used in", and name every entry in the "In brief" list at the top of its page; `scripts/check.py` reports what is missing.

### Version

[`best-practices/README.md`](best-practices/README.md) carries the version and date of the whole guide, including `knowledge/`, directly below its title:

```markdown
> **Version**: X.Y
> **Last Updated**: YYYY-MM-DD
```

Increase the major version for restructuring or changed recommendations, and the minor version for additions and corrections. Update both lines with every change to any page.

## Synchronizing a Change to the Guide

After you change a guide page, update the derived content that it affects:

| Changed in the guide | Update |
|---|---|
| `best-practices/dql.md`, `sync-and-subscriptions.md`, `observers.md` | `query-sync` Skill: `SKILL.md`, `examples/`, `reference/` |
| `best-practices/data-modeling.md`, `knowledge/crdt-types.md` | `data-modeling` Skill |
| `best-practices/deletion-and-storage.md` | `storage-lifecycle` Skill |
| `best-practices/transactions.md`, `attachments.md` | `transactions-attachments` Skill |
| `best-practices/observers.md`, `indexing-and-performance.md`, `logging-and-observability.md`, `knowledge/system-reference.md` | `performance-observability` Skill |
| `best-practices/setup-and-lifecycle.md`, `security.md` | `sdk-setup` Skill (`SKILL.md`, `reference/`) |
| `best-practices/testing.md` | `testing` Skill (`SKILL.md`, `reference/`) |
| A new or changed anti-pattern that can be found in source text, or a renamed heading that a scanner rule cites | `audit` Skill: `scripts/scan.py`, then regenerate `reference/scanner-rules.md` with `python3 scripts/scan.py --list-rules > reference/scanner-rules.md` |
| A new page, or a page whose scope changes | The page tables in the `guide` Skill's `SKILL.md`, and in `best-practices/README.md` or `knowledge/README.md` |
| A rule, caveat, or code example that a checklist item covers, or a renamed heading that an item names under "Best-practices guide" | `checklist/`: see [Updating content](checklist/README.md#updating-content) |
| An API, DQL statement, or pattern that the POS example uses | `examples/simple-pos/`: `simple_pos_example.dart`, `simple_pos_schema.yaml` |
| A new target SDK release (`knowledge/upgrading.md`) | The "Before You Apply" step and version notes of every Skill, the `Applies to` lines of the guide and the checklist, the POS example, and the READMEs |

For each affected Skill:

1. Update the rules (✅ DO / ❌ DON'T) in `SKILL.md`, the code in `examples/`, and the details in `reference/`, and keep them consistent with each other.
2. Keep the Skill format: only `name` and `description` in the frontmatter; a description of one paragraph and at most about 450 characters (1,024 at most); `SKILL.md` under 20,000 characters and 500 lines, with the most important rules first; details in `reference/` files. Cite guide sections as `§ Heading` with the exact heading text.
3. Bump `version` in [`plugins/ditto/.claude-plugin/plugin.json`](plugins/ditto/.claude-plugin/plugin.json) so that installed copies of the plugin receive the update: patch for fixes and wording, minor for new or revised patterns.
4. For changes to rules or descriptions, run the evals described in [plugins/ditto/evals/README.md](plugins/ditto/evals/README.md).

You can skip the synchronization for changes that do not affect any derived content: wording without a change in meaning, or background explanations without actionable patterns.

## Changing the Plugin Skills

Edit the Skills in [`plugins/ditto/skills/`](plugins/ditto/skills/). The entries in `.claude/skills/` are symbolic links to them, so do not edit through those links. The `guide` Skill bundles the guide through `skills/guide/reference/best-practices` and `skills/guide/reference/knowledge`, symbolic links that Claude Code replaces with the linked content when it installs the plugin. Follow the format and version rules above, and see [plugins/ditto/README.md](plugins/ditto/README.md) for how the Skills are built.

## Changing the Checklist

Edit the Markdown and JSON sources and rebuild the HTML, as described in [checklist/README.md](checklist/README.md). Commit the sources together with the generated `ditto-sdk-checklist.html`.

## Checks

Run these from the repository root before you finish a change to the guide, the Skills, or the checklist:

```bash
python3 scripts/check.py                  # guide headings and observation links, Skill format and citations, checklist sections, links and anchors, scanner rules
claude plugin validate . --strict         # plugin and marketplace manifests
```

After changing `scripts/check.py`, also run its tests with `python3 -m unittest discover -s scripts`.

## Standards

- **English** for all files, code comments, and commit messages. The Japanese text of the checklist lives only in its translation files.
- **Professional language** suitable for a corporate project.
- **No credentials.** Use placeholders such as `YOUR_DATABASE_ID` in examples.
- **Readable, accurate examples.** Code in this repository is copied by readers. Prefer clarity over cleverness, and mark behavior with the SDK releases on which it was observed, for example **Note (SDK 5.1.0 and 5.2.0)**.
- **Changelog.** Add user-visible changes to [CHANGELOG.md](CHANGELOG.md) under `Unreleased`.

## Pull Requests

Describe what changed and why, list the checks you ran, and keep each pull request focused on one topic. Report problems and suggestions in [GitHub Issues](https://github.com/ditto-examples/ditto-cookbook/issues).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
