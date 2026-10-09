---
description: A PostgreSQL question must not invoke the Ditto skills.
tags: [negative, smoke]
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

In PostgreSQL, how do I select the users created in the last seven days from a `users` table with a `created_at timestamptz` column? Just the SQL.
