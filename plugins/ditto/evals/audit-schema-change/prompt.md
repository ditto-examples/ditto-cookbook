---
description: A review of a pull request to a released app tells breaking schema changes from additive ones, and does not propose fixes that convert stored data in place.
tags: [audit]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Review the pull request in `pr.diff` for this Ditto app and report what you find. The files in `lib/` already include the change, and `README.md` describes the app. Do not change any files.
