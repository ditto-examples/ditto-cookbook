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

Initial setup and infrastructure preparation.
