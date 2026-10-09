---
description: Line items stored as an array lose concurrent edits; a map keyed by ID merges.
tags: [data-modeling, smoke]
max_turns: 12
allowed_tools: [Read, Glob, Grep, Skill]
---

We store orders in Ditto like `{"_id": "o1", "items": [{"productId": "p1", "qty": 2}, {"productId": "p2", "qty": 1}]}`. Two tablets edit different line items of the same order while offline, and after they sync one tablet's change is gone. What is wrong with the model? Show the document shape you recommend.
