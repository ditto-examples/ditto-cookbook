---
description: An Android ViewModel exposes live query results as a StateFlow, passes parameters, maps rows to plain data, and releases the observer with the ViewModel.
tags: [query-sync, performance-observability]
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

Write an Android ViewModel that exposes the open orders (collection `orders`, field `status` equal to `open`, newest first by `createdAt`) as a `StateFlow`, updating live as data syncs. It receives a Ditto instance in its constructor. Ditto SDK 5.2 (`com.ditto:ditto-kotlin`). Reply with the Kotlin code only.
