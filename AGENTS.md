# Development Guidelines

Instructions for coding agents that work in this repository. [CONTRIBUTING.md](CONTRIBUTING.md) describes the workflows in detail; follow it.

## Repository Layout

| Path | Contents |
|------|----------|
| `best-practices/` | The Ditto SDK best practices guide: what to do and what to avoid, one page per topic that applies to every SDK, and one page per SDK (Flutter, JavaScript, Kotlin, Swift) in `best-practices/platforms/` with its code. `README.md` holds the guide's version, conventions, and essentials |
| `knowledge/` | The guide's knowledge pages: how Ditto works and the reference material that the best practices build on; `knowledge/observations/` holds what we observed in testing, with the releases, setup, and numbers |
| `checklist/` | Customer-facing checklist (sources, build script, generated HTML) derived from the guide |
| `examples/simple-pos/` | Flutter POS example that applies the guide |
| `plugins/ditto/` | The `ditto` Claude Code plugin: Skills derived from the guide, and evals |
| `.claude-plugin/marketplace.json` | Marketplace that publishes the plugin |
| `scripts/check.py` | Checks the guide, the Skills, the checklist, and Markdown links (tests in `scripts/test_check.py`; the tests of the `audit` Skill's scanner are in `scripts/test_scan.py`) |
| `.claude/skills/` | Symbolic links to the plugin Skills |

`best-practices/` and `knowledge/` together are the **source of truth** for everything Ditto-specific. The repository covers Ditto only: do not add general material about Flutter, JavaScript, Kotlin, Swift, or Claude Code.

Edit the Ditto Skills in `plugins/ditto/skills/`, never through the links in `.claude/skills/`.

## Guide Synchronization (CRITICAL)

After editing any page in `best-practices/` or `knowledge/`, you **must**:

1. Update the guide's `Version` and `Last Updated` in `best-practices/README.md`.
2. Propagate the change to the plugin Skills, the checklist, and the POS example as described in [Synchronizing a Change to the Guide](CONTRIBUTING.md#synchronizing-a-change-to-the-guide), and bump the plugin version when Skills change. Skip only for changes that do not affect any derived content.

Record what testing shows in `knowledge/observations/` first, one entry per observation with its releases, setup, every number, and what was not tested; then state the rule in `best-practices/` with a short reason and a link to that entry. Do not put measurements or procedures in `best-practices/` alone. See [Where content belongs](CONTRIBUTING.md#where-content-belongs).

Keep every heading of the guide unique across both directories: the Skills and the checklist cite sections by their heading text.

Before finishing a change to the guide, the Skills, or the checklist, run:

```bash
python3 scripts/check.py
claude plugin validate . --strict
```

After changing `scripts/check.py` or `plugins/ditto/skills/audit/scripts/scan.py`, also run `python3 -m unittest discover -s scripts`.

## Language Policy

All artifacts in this project must be written in English: documentation, code and comments, commit messages, identifiers, error messages, and configuration. The only exception is the Japanese translation data of the checklist (`translations.json` and `code-translations.json`).

This project is managed by a corporate entity. All language must be professional, respectful, inclusive, and suitable for enterprise use.

## Documentation Updates

- Update the relevant documentation (READMEs, the guide, inline comments) together with every change, including minor ones.
- Record user-visible changes in `CHANGELOG.md` under `Unreleased`.
- Keep `Version` and `Last Updated` current in versioned documents (`best-practices/README.md` for the guide, the checklist Markdown).

## Best Practices and Technology Updates

- Check the latest official documentation for Ditto, the SDK's platform (Flutter, JavaScript, Kotlin, or Swift), and Claude Code before writing guidance or code; the guide and the Skills target Ditto SDK 5.2.0.
- Consult the guide (`best-practices/` and `knowledge/`) for Ditto code. For the platform itself, follow its official documentation, such as Flutter and Dart, Node.js and the Web platform, Kotlin and Android, or Swift and Apple's frameworks.
- Keep the topic pages free of SDK code: state the rule for every SDK, show DQL with its arguments, and put each SDK's code on its page in `best-practices/platforms/`, in the section of the same name on all four pages. Behavior of one SDK's API goes on that SDK's observation page (`knowledge/observations/<sdk>-sdk.md`).
- Mark behavior with the SDK releases on which it was observed, for example **Note (SDK 5.1.0 and 5.2.0)**, and collect issues that a later release fixed in "Known Issues in SDK 5.1.0" (`knowledge/upgrading.md`).

## Security Guidelines

- Never commit API keys, tokens, or credentials. Examples use placeholders such as `YOUR_DATABASE_ID`.
- Validate inputs and sanitize output in example code, following OWASP guidance.

## Showcase Code Standards

This repository is a reference that readers copy from, so code quality and readability come first:

- **Prioritize readability**: clear names and structure that explain the code; comments explain the "why", not the "what".
- **Keep it simple**: no abstraction for hypothetical needs, no premature optimization.
- **Follow platform conventions**: idiomatic code in each SDK's language and UI framework, and Ditto SDK patterns.
- **Make examples complete**: functional code, not conceptual fragments.
- **Follow existing style**: match the conventions already present in the file you edit.
