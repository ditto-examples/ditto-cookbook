# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Publish the Ditto Agent Skills as the `ditto` Claude Code plugin through a `ditto-cookbook` marketplace (`.claude-plugin/marketplace.json`).

### Changed

- Move the Ditto Agent Skills from `.claude/skills/ditto/` to `plugins/ditto/skills/`. `.claude/skills/` now holds one symbolic link per Skill, which also fixes discovery: Claude Code only loads Skills one level below `.claude/skills/`.
- Link the Skills to the best practices guide with absolute GitHub URLs so that the links work in installed copies of the plugin.
- Rename the `ditto-data-modeling` Skill to `data-modeling` to match its directory and the other Skills.
- Sync the `ditto` plugin Skills with version 2.6 of the best practices guide (plugin 1.0.1): the `ANY ... SATISFIES` caveat as a known 5.1.0 issue, the reason behind the 15-minute subscription guideline, `system:data_sync_info` observer timing, husk fields that read as missing or `null`, and attachment relay observations.

Initial setup and infrastructure preparation.
