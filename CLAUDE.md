# Development Guidelines

This file is the authoritative source for the development guidelines of this project. [CONTRIBUTING.md](CONTRIBUTING.md) describes the same workflows for human contributors.

## Repository Layout

| Path | Contents |
|------|----------|
| `best-practices/ditto.md` | Ditto SDK best practices guide: the **source of truth** for everything Ditto-specific |
| `best-practices/ditto-sdk-checklist/` | Customer-facing checklist (sources, build script, generated HTML) derived from the guide |
| `best-practices/flutter.md` | Flutter best practices |
| `examples/simple-pos/` | Flutter POS example that applies the guide |
| `plugins/ditto/` | The `ditto` Claude Code plugin: Skills derived from the guide, and evals |
| `.claude-plugin/marketplace.json` | Marketplace that publishes the plugin |
| `scripts/check-ditto-skills.py` | Checks the plugin Skills against the guide |
| `.claude/rules/` | Path-specific rules for Claude Code |
| `.claude/skills/` | Symbolic links to the plugin Skills, and the `claude-skills` authoring Skill |

Edit the Ditto Skills in `plugins/ditto/skills/`, never through the links in `.claude/skills/`.

## Ditto Best Practices Synchronization (CRITICAL)

After editing `best-practices/ditto.md`, you **must** propagate the change to the plugin Skills, the checklist, and the POS example, and bump the plugin version when Skills change. Follow [.claude/rules/ditto-best-practices-sync.md](.claude/rules/ditto-best-practices-sync.md). Skip only for purely conceptual changes without actionable patterns.

Before finishing a change to the guide or the Skills, run:

```bash
python3 scripts/check-ditto-skills.py
claude plugin validate . --strict
```

## Language Policy

All artifacts in this project must be written in English: documentation, code and comments, commit messages, identifiers, error messages, and configuration. The only exception is the Japanese translation data of the checklist (`translations.json` and `code-translations.json`).

This project is managed by a corporate entity. All language must be professional, respectful, inclusive, and suitable for enterprise use.

## Documentation Updates

- Update the relevant documentation (READMEs, the guide, inline comments) together with every change, including minor ones.
- Record user-visible changes in `CHANGELOG.md` under `Unreleased`.
- Keep `Version` and `Last Updated` current in versioned documents (`best-practices/ditto.md`, the checklist Markdown).

## Best Practices and Technology Updates

- Check the latest official documentation for Ditto, Flutter, and Claude Code before writing guidance or code; the guide and the Skills target Ditto SDK 5.1.0.
- Consult [best-practices/ditto.md](best-practices/ditto.md) for Ditto code and [best-practices/flutter.md](best-practices/flutter.md) for Flutter code.
- Mark behavior that is specific to one SDK release, for example **Note (SDK 5.1.0)**.

## Security Guidelines

- Never commit API keys, tokens, or credentials. Examples use placeholders such as `YOUR_DATABASE_ID`.
- Validate inputs and sanitize output in example code, following OWASP guidance.

## Showcase Code Standards

This repository is a reference that readers copy from, so code quality and readability come first:

- **Prioritize readability**: clear names and structure that explain the code; comments explain the "why", not the "what".
- **Keep it simple**: no abstraction for hypothetical needs, no premature optimization.
- **Follow platform conventions**: idiomatic Dart, Flutter, and Ditto SDK patterns.
- **Make examples complete**: functional code, not conceptual fragments.
- **Follow existing style**: match the conventions already present in the file you edit.
