---
description: A soft-delete filter written as isDeleted != true drops documents without the flag.
tags: [storage-lifecycle, query-sync, smoke]
max_turns: 12
allowed_tools: [Read, Glob, Grep, Skill]
---

Our Flutter app uses Ditto. The task list runs `SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt`. Tasks created by an older app version never show up in the list, although they are in the local store. Why, and what should the query be?
