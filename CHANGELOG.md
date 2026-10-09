# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Publish the Ditto Agent Skills as the `ditto` Claude Code plugin through a `ditto-cookbook` marketplace (`.claude-plugin/marketplace.json`).
- Add four Skills to the `ditto` plugin (1.1.0): `sdk-setup` (DittoConfig, `Ditto.open`, authentication, system parameters, sync start and stop, shutdown, transports, presence, production security), `testing` (local-store and multi-peer tests), `audit` (a review workflow with `scan.py`, a dependency-free scanner for known anti-patterns in Dart, JavaScript, TypeScript, Swift, and Kotlin), and `guide` (searches the complete best practices guide, which now ships with the plugin through a symbolic link that Claude Code copies into installed plugins).
- Add an eval suite for `claude plugin eval` (`plugins/ditto/evals/`) that checks Skill triggering, answers, and that the Skills stay out of unrelated SQL work.
- Add `.claude/scripts/checks/check-ditto-skills.py`, which checks the Skill format, every `§ Heading` citation against the guide, relative links, and the generated scanner rules.

### Changed

- Move the Ditto Agent Skills from `.claude/skills/ditto/` to `plugins/ditto/skills/`. `.claude/skills/` now holds one symbolic link per Skill, which also fixes discovery: Claude Code only loads Skills one level below `.claude/skills/`.
- Link the Skills to the best practices guide with absolute GitHub URLs so that the links work in installed copies of the plugin.
- Rename the `ditto-data-modeling` Skill to `data-modeling` to match its directory and the other Skills.
- Sync the `ditto` plugin Skills with version 2.6 of the best practices guide (plugin 1.0.1): the `ANY ... SATISFIES` caveat as a known 5.1.0 issue, the reason behind the 15-minute subscription guideline, `system:data_sync_info` observer timing, husk fields that read as missing or `null`, and attachment relay observations.
- Restructure the `ditto` plugin Skills for coding agents, following the current Agent Skills guidance: one-paragraph descriptions of at most 450 characters (previously 1,200 to 1,600, above the 1,024-character limit of the open standard), `SKILL.md` bodies under about 5,000 tokens (previously 6,800 to 7,800) with the critical rules first, details moved to `reference/` files, a "Before You Apply" step that checks the project's SDK version and platform, and guide citations as `§ Heading` that resolve against the bundled guide instead of GitHub URLs.
- Restructure the repository around its content. The best practices guides and the checklist move from `.claude/guides/best-practices/` to `best-practices/` (`human-friendly-docs/ditto-sdk-checklist/` becomes `best-practices/ditto-sdk-checklist/`), the POS example moves from `.claude/examples/ditto/simple_pos/` to `examples/simple-pos/`, and `check-ditto-skills.py` moves to `scripts/`. `.claude/` now holds only Claude Code configuration: the synchronization rule (now `.claude/rules/ditto-best-practices-sync.md`) and the Skills.
- Rewrite `README.md`, `CONTRIBUTING.md`, and `CLAUDE.md` to describe the actual contents and maintenance workflows, and point all GitHub links to `ditto-examples/ditto-cookbook`.

### Fixed

- Correct the soft-delete guidance in version 2.7 of the best practices guide, verified with licensed peers syncing over localhost TCP (JavaScript SDK 5.1.0 on Node.js). A device whose subscription excludes soft-deleted documents does receive a restore, together with the edits made while the document was flagged; the guide said that restores never arrive. The real risks are now stated instead: such a device cannot relay the flag for documents it did not already hold, and a `DELETE` of a flagged document does not reach it. The guide also adds the observed merge results (a soft delete keeps concurrent edits; between a delete and a restore, the later write wins), the subscribe-to-active-documents design that Ditto's documentation describes and when to use it, and the requirement to set `isDeleted` and `deletedAt` in the same `UPDATE`. The `storage-lifecycle`, `query-sync`, and `testing` Skills (plugin 1.2.0), the checklist (2.8), and the POS example comments follow.

### Removed

- Remove the scaffolding for example applications that did not exist yet: the `apps/` and `tools/` placeholders, `docs/` (architecture template and index), the test, dependency, tool-version, MCP, Git Hooks, and architecture-check scripts in `.claude/scripts/`, their guides in `.claude/guides/`, the `/update-deps` command, `VERSION_MANAGEMENT.md`, `.tool-versions`, `.nvmrc`, `.fvm/`, and `.env.template`. They can be restored from the Git history when an application is added.
- Remove `.claude/hooks.json` and `.claude/settings.json`, which used a format and keys that Claude Code does not read, and `.claude/rules/README.md`, which Claude Code loaded into every session as a rule.

Initial setup and infrastructure preparation.
