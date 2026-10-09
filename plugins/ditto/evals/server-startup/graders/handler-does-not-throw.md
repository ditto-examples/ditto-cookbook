---
type: llm
---

PASS if the expiration handler checks `response.exception` from `ditto.auth.login(...)` and reports it (log or UI) without throwing or rethrowing, and catches errors from fetching the token inside the handler.
FAIL if the handler throws or rethrows an error, or ignores the login result entirely.
