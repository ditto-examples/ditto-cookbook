# Ditto Cookbook

Knowledge, best practices, a review checklist, example code, and Claude Code Agent Skills for building offline-first applications with the [Ditto SDK](https://docs.ditto.live). Everything targets Ditto SDK 5.2. Flutter (Dart) is the primary platform, with notes for JavaScript, Swift, and Kotlin where they differ.

## Contents

| Path | What it is |
|------|------------|
| [`best-practices/`](best-practices/README.md) | **Ditto SDK Best Practices**: what to do and what to avoid, one page per topic: setup and lifecycle, DQL, data modeling, sync and subscriptions, observers, transactions, attachments, deletion and storage, indexing, logging, security, testing, and a review list of anti-patterns. Start here. |
| [`knowledge/`](knowledge/README.md) | **Ditto SDK Knowledge**: how Ditto works, and the reference material that the best practices build on: CRDT merge rules, DQL functions, system collections and parameters, platform differences, changes between SDK releases, and a glossary. `knowledge/observations/` holds what we observed in testing, with the SDK releases, the setup, and every number. |
| [`checklist/`](checklist/) | **Ditto SDK Implementation Checklist**: an interactive English and Japanese review checklist in one self-contained HTML file. |
| [`examples/simple-pos/`](examples/simple-pos/) | **Simple POS**: a Point-of-Sale and Kitchen Display example that applies the guide end to end, with its data model. |
| [`plugins/ditto/`](plugins/ditto/) | **`ditto` Claude Code plugin**: Agent Skills that help coding agents write and review Ditto code, an anti-pattern scanner, and the bundled guide. |

The best practices and the knowledge pages together form the guide. The checklist, the example, and the Skills are derived from it.

## Claude Code Plugin

This repository is a Claude Code plugin marketplace named `ditto-cookbook`. Install the `ditto` plugin with:

```
/plugin install ditto --marketplace ditto-examples/ditto-cookbook
```

See [plugins/ditto/README.md](plugins/ditto/README.md) for the list of Skills and the install steps on earlier Claude Code versions.

## Repository Layout

```
ditto-cookbook/
├── best-practices/           # The guide: best practices, one page per topic
├── knowledge/                # The guide: how Ditto works, reference material
│   └── observations/         # What we observed in testing, one entry per observation
├── checklist/                # Checklist sources, build script, generated HTML
├── examples/
│   └── simple-pos/           # Flutter POS example and its schema
├── plugins/
│   └── ditto/                # Claude Code plugin: skills/, evals/
├── .claude-plugin/
│   └── marketplace.json      # Plugin marketplace definition
├── scripts/
│   └── check.py              # Checks the guide, the Skills, the checklist, and links
└── .claude/
    └── skills/               # Links to the plugin Skills, for working in this repository
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Coding agents also follow [AGENTS.md](AGENTS.md).

## Resources

- [Ditto documentation](https://docs.ditto.live)
- [Ditto support](https://support.ditto.com/)
- [Issues](https://github.com/ditto-examples/ditto-cookbook/issues)

## License

MIT. See [LICENSE](LICENSE).
