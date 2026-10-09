---
description: Subscriptions should not be re-registered when the user changes a UI filter.
tags: [query-sync]
max_turns: 12
allowed_tools: [Read, Glob, Grep, Skill]
---

In our Ditto Flutter app, each time the user switches the status tab (open / packed / shipped) we cancel the current subscription and call `ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId AND status = :status', ...)` with the new status. Is that a good approach? If not, what should we do instead?
