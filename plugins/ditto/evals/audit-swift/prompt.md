---
description: An audit of a Swift package finds five planted defects from the guide's checklist and leaves the correct code alone.
tags: [audit, swift]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

We keep getting crash reports and wrong stock values from our iPad counting app. Please audit the Ditto code in `Sources/` and tell me what's wrong and how bad each problem is. `README.md` describes how the app is used. Don't change any files.
