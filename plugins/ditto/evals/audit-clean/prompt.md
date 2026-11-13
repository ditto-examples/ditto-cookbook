---
description: An audit of a small TypeScript data layer that follows the guide does not invent critical or high findings.
tags: [audit, javascript, false-positive]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Please audit the Ditto data layer in `src/` before we release it. `README.md` explains how the app is deployed and what is out of scope. Report only real problems; don't change any files.
