# Ditto Cookbook

Best practices, a review checklist, example code, and Claude Code Agent Skills for building offline-first applications with the [Ditto SDK](https://docs.ditto.live). Everything targets Ditto SDK 5.1. Flutter (Dart) is the primary platform, with notes for JavaScript, Swift, and Kotlin where they differ.

## Contents

| Path | What it is |
|------|------------|
| [`best-practices/ditto.md`](best-practices/ditto.md) | **Ditto SDK Best Practices**: the complete guide to data modeling, sync and subscriptions, deletion and storage, transactions and attachments, performance, setup, security, and testing. The rest of this repository is derived from it. |
| [`best-practices/ditto-sdk-checklist/`](best-practices/ditto-sdk-checklist/) | **Ditto SDK Implementation Checklist**: an interactive English and Japanese review checklist in one self-contained HTML file. |
| [`best-practices/flutter.md`](best-practices/flutter.md) | **Flutter Best Practices**: architecture, Riverpod state management, performance, and testing patterns. |
| [`examples/simple-pos/`](examples/simple-pos/) | **Simple POS**: a Point-of-Sale and Kitchen Display example that applies the guide end to end, with its data model. |
| [`plugins/ditto/`](plugins/ditto/) | **`ditto` Claude Code plugin**: Agent Skills that help coding agents write and review Ditto code, an anti-pattern scanner, and the bundled guide. |

## Claude Code Plugin

This repository is a Claude Code plugin marketplace named `ditto-cookbook`. Install the `ditto` plugin with:

```
/plugin install ditto --marketplace ditto-examples/ditto-cookbook
```

See [plugins/ditto/README.md](plugins/ditto/README.md) for the list of Skills and the install steps on earlier Claude Code versions.

## Repository Layout

```
ditto-cookbook/
├── best-practices/           # Guides and the checklist (customer-facing)
│   ├── ditto.md              # Source of truth for everything Ditto-specific
│   ├── flutter.md
│   └── ditto-sdk-checklist/  # Checklist sources, build script, generated HTML
├── examples/
│   └── simple-pos/           # Flutter POS example and its schema
├── plugins/
│   └── ditto/                # Claude Code plugin: skills/, evals/
├── .claude-plugin/
│   └── marketplace.json      # Plugin marketplace definition
├── scripts/
│   └── check-ditto-skills.py # Checks the plugin Skills against the guide
└── .claude/                  # Claude Code configuration for working in this repository
    ├── rules/                # Synchronization workflow for the guide and its derivatives
    └── skills/               # Links to the plugin Skills, and a Skill-authoring Skill
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Contributors using Claude Code also follow [CLAUDE.md](CLAUDE.md).

## Resources

- [Ditto documentation](https://docs.ditto.live)
- [Ditto support](https://support.ditto.live/)
- [Issues](https://github.com/ditto-examples/ditto-cookbook/issues)

## License

MIT. See [LICENSE](LICENSE).
