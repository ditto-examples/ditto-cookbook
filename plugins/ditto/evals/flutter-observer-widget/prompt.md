---
description: A live Flutter list uses the changes stream and cancels both the stream subscription and the observer.
tags: [query-sync, performance-observability]
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

Write a Flutter StatefulWidget that shows the open orders (collection `orders`, field `status` equal to `open`, newest first by `createdAt`) from a Ditto instance it receives as a constructor parameter, updating live as data syncs. Ditto SDK 5.1 (`ditto_live`). Reply with the Dart code only.
