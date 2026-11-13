---
description: An audit of an Android (Kotlin) repository finds five planted defects from the guide's checklist and leaves the correct code alone.
tags: [audit, kotlin]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Can you review the data layer of our Android app in `app/src/main/java` before we ship the next release? `README.md` says how the technicians use it. Just report what you find; don't change any files.
