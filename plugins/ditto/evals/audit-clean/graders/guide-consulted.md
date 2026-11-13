---
type: llm
---

This grader checks that the review ran with the plugin's bundled material available, not the quality of its findings.

FAIL if the report says that it could not do any of the following:
- read, open, or search the bundled Ditto best practices guide, or the reference files of the audit skill
- run the audit scanner (`scan.py`, "the scanner", "the pattern scan")

It fails for any stated reason: the tool, command, file access, or search was denied or refused; Bash, Python, or shell access was not available; or the guide is not installed or missing.

It also fails if the report says that its severities or citations rest on its own knowledge instead of the guide because the guide was unavailable.

PASS otherwise. A section that lists what was not checked does not fail this grader when its items are about the app, such as code outside the repository, the SDK version, how devices are deployed, or behavior that needs a test on real devices.
