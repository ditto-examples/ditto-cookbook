# Contributing to Ditto Cookbook

Thank you for helping improve the Ditto Cookbook. This guide explains how the repository fits together and how to change each part.

## How the Repository Fits Together

[`best-practices/ditto.md`](best-practices/ditto.md) is the source of truth. Everything Ditto-specific is derived from it:

```
best-practices/ditto.md
├──> plugins/ditto/skills/              Agent Skills (the guide itself ships through a symbolic link)
├──> best-practices/ditto-sdk-checklist/ Review checklist (Markdown and JSON sources → HTML)
└──> examples/simple-pos/                End-to-end Flutter example
```

A change to the guide is complete only when the derived content agrees with it. The [synchronization workflow](.claude/rules/ditto-best-practices-sync.md) lists which files each kind of change affects.

## Prerequisites

- **Python 3.9 or later** for the check scripts
- **[uv](https://docs.astral.sh/uv/)** to build the checklist (it installs Pygments for syntax highlighting)
- **[Claude Code](https://code.claude.com)** to validate the plugin and run its evals

## Common Tasks

### Changing the Ditto Guide

1. Edit [`best-practices/ditto.md`](best-practices/ditto.md) and update `Version` and `Last Updated` below its title (see [best-practices/README.md](best-practices/README.md)).
2. Follow the [synchronization workflow](.claude/rules/ditto-best-practices-sync.md) to update the affected Skills, checklist items, and example code.
3. Run the checks below.

### Changing the Plugin Skills

Edit the Skills in [`plugins/ditto/skills/`](plugins/ditto/skills/). The entries in `.claude/skills/` are symbolic links to them, so do not edit through those links. Then:

```bash
python3 scripts/check-ditto-skills.py   # format, § Heading citations, links, scanner rules
claude plugin validate . --strict       # plugin and marketplace manifests
```

Bump `version` in [`plugins/ditto/.claude-plugin/plugin.json`](plugins/ditto/.claude-plugin/plugin.json) for every change that users should receive: patch for fixes and wording, minor for new or revised patterns. For changes to rules or descriptions, run the evals described in [plugins/ditto/evals/README.md](plugins/ditto/evals/README.md).

### Changing the Checklist

Edit the Markdown and JSON sources and rebuild the HTML, as described in [best-practices/ditto-sdk-checklist/README.md](best-practices/ditto-sdk-checklist/README.md). Commit the sources together with the generated `ditto-sdk-checklist.html`.

## Standards

- **English** for all files, code comments, and commit messages. The Japanese text of the checklist lives only in its translation files.
- **Professional language** suitable for a corporate project.
- **No credentials.** Use placeholders such as `YOUR_DATABASE_ID` in examples.
- **Readable, accurate examples.** Code in this repository is copied by readers. Prefer clarity over cleverness, and mark behavior specific to one SDK release, for example **Note (SDK 5.1.0)**.
- **Changelog.** Add user-visible changes to [CHANGELOG.md](CHANGELOG.md) under `Unreleased`.

## Pull Requests

Describe what changed and why, list the checks you ran, and keep each pull request focused on one topic. Report problems and suggestions in [GitHub Issues](https://github.com/ditto-examples/ditto-cookbook/issues).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
