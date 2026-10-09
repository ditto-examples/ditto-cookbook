---
description: Startup code sets the expiration handler before sync.start, does not throw from it, and does not await sync.start.
tags: [sdk-setup]
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

Write the Dart startup code for a Flutter app that opens Ditto (SDK 5.1, `ditto_live`), connects to Ditto Server, authenticates with our webhook provider named `my-auth` using a token from `Future<String> fetchToken()`, and starts sync. Reply with the code and at most five lines of explanation.
