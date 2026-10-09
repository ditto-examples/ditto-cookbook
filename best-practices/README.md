# Best Practices

Guides for building applications on the Ditto SDK, and the checklist derived from them.

| Document | Description |
|----------|-------------|
| [ditto.md](ditto.md) | **Ditto SDK Best Practices.** The complete guide for Ditto SDK 5.1: data modeling, sync and subscriptions, deletion and storage, transactions and attachments, performance, setup, security, and testing. It is the source of truth for the [`ditto` Claude Code plugin](../plugins/ditto/), the checklist below, and the [POS example](../examples/simple-pos/). |
| [ditto-sdk-checklist/](ditto-sdk-checklist/) | **Ditto SDK Implementation Checklist.** An interactive English and Japanese review checklist, distributed as one self-contained HTML file ([`ditto-sdk-checklist.html`](ditto-sdk-checklist/ditto-sdk-checklist.html)). |
| [flutter.md](flutter.md) | **Flutter Best Practices.** Architecture, state management with Riverpod, performance, and testing patterns for the Flutter code in this repository. |

## Maintaining the Ditto Guide

`ditto.md` carries a version and a date directly below its title:

```markdown
> **Version**: X.Y
> **Last Updated**: YYYY-MM-DD
```

Increase the major version for restructuring or changed recommendations, and the minor version for additions and corrections. Update both lines with every change.

After editing `ditto.md`, propagate the change to the plugin Skills, the checklist, and the POS example as described in the [synchronization workflow](../.claude/rules/ditto-best-practices-sync.md).
