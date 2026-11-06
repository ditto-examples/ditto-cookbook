---
description: A SwiftUI model registers one observer with parameters, keeps a reference to it, and cancels it when the model goes away.
tags: [query-sync, performance-observability]
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

Write a SwiftUI view and the observable model behind it that show the open orders (collection `orders`, field `status` equal to `open`, newest first by `createdAt`) from a Ditto instance it receives, updating live as data syncs. Ditto SDK 5.2 (`DittoSwift`). Reply with the Swift code only.
