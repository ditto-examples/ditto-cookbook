# Quality Check Scripts

This directory contains scripts that ensure code quality, security, and documentation standards across the repository.

## Scripts

### check-last-updated.sh

**Purpose**: Ensures best practices guides have current "Last Updated" timestamps.

**Behavior**:
- Runs automatically as part of pre-commit hook
- Non-blocking (shows warnings but doesn't prevent commits)
- Checks staged changes to `.claude/guides/best-practices/*.md` files
- Compares "Last Updated" date with today's date

**Files Checked**:
- `.claude/guides/best-practices/ditto.md`
- `.claude/guides/best-practices/flutter.md`

**How to Update**:
When you modify a best practices guide, update the "Last Updated" line at the bottom:

```markdown
**Last Updated**: YYYY-MM-DD
```

Replace `YYYY-MM-DD` with today's date.

**Why This Matters**:
Best practices guides are reference documentation consumed by Claude Code and developers. Accurate timestamps help users know when information was last verified and whether it reflects current practices.

### security-check.sh

**Purpose**: Scans for potential security issues (API keys, secrets, credentials).

**Behavior**: Blocking - prevents commits with security violations.

### language-check.sh

**Purpose**: Ensures all artifacts use English (per project guidelines).

**Behavior**: Blocking - prevents commits with non-English content in documentation/code.

### version-check.sh

**Purpose**: Verifies tool versions (Flutter, Node.js, Python) match requirements.

**Behavior**: Non-blocking - shows warnings and fixes version mismatches automatically.

---

## Integration with Git Hooks

These scripts are automatically integrated into Git hooks during setup:

1. **Pre-commit hook**: Runs `check-last-updated.sh`, `security-check.sh`, `language-check.sh`, `version-check.sh`
2. **Pre-push hook**: Runs comprehensive checks including Dart analysis and architecture validation

To set up hooks:
```bash
./.claude/scripts/setup/complete-setup.sh
```

---

## Best Practices

**For Developers**:
- Always update "Last Updated" dates when modifying best practices guides
- Don't bypass security/language checks (use `--no-verify` only in emergencies)
- If you see warnings, address them before committing

**For Maintainers**:
- Keep check scripts non-blocking unless critical (security/language are blocking)
- Document new checks in this README
- Test changes to check scripts before committing

---

**Last Updated**: 2025-12-19
