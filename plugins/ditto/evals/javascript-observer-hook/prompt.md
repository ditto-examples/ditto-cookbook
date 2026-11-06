---
description: A React hook registers one observer with parameters, uses a synchronous handler, and cancels the observer when the component unmounts.
tags: [query-sync, performance-observability]
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

Write a React hook `useOpenOrders(ditto)` that returns the open orders (collection `orders`, field `status` equal to `open`, newest first by `createdAt`) from the Ditto instance it receives, and updates live as data syncs. Ditto SDK 5.2 (`@dittolive/ditto`). Reply with the JavaScript code only.
