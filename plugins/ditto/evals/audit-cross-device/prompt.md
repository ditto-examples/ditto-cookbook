---
description: An audit finds four planted defects that no single statement shows, each an assumption that fails across devices.
tags: [audit]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Audit the Ditto code in `lib/` for best-practice problems and report what you find. Several tills use this app in one store, and they are often offline. Do not change any files.
