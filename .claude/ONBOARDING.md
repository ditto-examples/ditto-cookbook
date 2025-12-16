# New Developer Onboarding

> **Purpose**: Quick reference for Claude Code to help onboard new developers. For detailed information, refer to linked guides.

---

## 15-Minute Setup

### 1. Clone & Setup (5 min)

```bash
git clone https://github.com/getditto/ditto-cookbook.git
cd ditto-cookbook
./.claude/scripts/setup/complete-setup.sh
```

This installs Git Hooks, checks Claude Code, and optionally configures MCP servers.

### 2. Verify (2 min)

```bash
./.claude/scripts/setup/verify-setup.sh
```

### 3. Read Guidelines (10 min)

**Required**: [CLAUDE.md](../CLAUDE.md) - The authoritative development guidelines

Focus on: Language Policy, Security, Git Hooks, Architecture Documentation, Testing Standards

---

## Essential Rules

### Language Policy
- **English only** in all code, comments, and documentation
- **Professional language** standards
- **Enforced by Git Hooks**

### Security
- **Never commit `.env` files**
- **Always maintain `.env.template`** with placeholders
- **No hardcoded credentials** - Pre-commit hook blocks these

### Git Hooks
- **Run automatically** before commit/push
- **Three hooks**: pre-commit (security/language), commit-msg (validation), pre-push (comprehensive checks)
- **Cannot skip** without `--no-verify` (document reason if used)

**Full details**: [.claude/guides/git-hooks.md](guides/git-hooks.md)

### Testing Standards
- **Target 80%+ coverage**
- **Test critical paths**, unit tests, integration tests, error scenarios

### Architecture Documentation
- **Every app/tool must have ARCHITECTURE.md**
- **Use**: [docs/ARCHITECTURE_TEMPLATE.md](../docs/ARCHITECTURE_TEMPLATE.md)
- **Update** on structural changes

**Full guide**: [.claude/guides/architecture.md](guides/architecture.md)

---

## Reference Documentation

| File | Purpose | Priority |
|------|---------|----------|
| [CLAUDE.md](../CLAUDE.md) | Development rules (authoritative) | HIGH |
| [.claude/README.md](README.md) | Setup overview and quick start | MEDIUM |
| [.claude/guides/git-hooks.md](guides/git-hooks.md) | Git Hooks details | HIGH |
| [.claude/guides/quality-checks.md](guides/quality-checks.md) | Claude Code hooks | MEDIUM |
| [.claude/guides/architecture.md](guides/architecture.md) | Architecture documentation | HIGH |
| [.claude/guides/dependency-management.md](guides/dependency-management.md) | Dependency management | MEDIUM |
| [.claude/guides/MCP-SETUP.md](guides/MCP-SETUP.md) | MCP servers setup | LOW |

---

## Common Questions

### Q: Can I skip Git Hooks?
**A: No.** Required for all developers. Enforce quality standards and prevent security issues.

### Q: What if checks fail?
**A: Fix the issues.** Common fixes:
- **Security**: Remove keys, use environment variables
- **Language**: Translate to English
- **Dart analysis**: Run `flutter pub get`, fix type errors

Only bypass with `--no-verify` if absolutely necessary (document reason).

### Q: Do I need MCP servers?
**A: Optional but recommended** for Claude Code users. Provides real-time documentation access.
Setup: `./.claude/scripts/setup/setup-mcp-servers.sh`

### Q: Where do I start?
**A: After setup:**
1. Browse `apps/` directory
2. Read app ARCHITECTURE.md files
3. Study implementation patterns
4. Adapt examples to your use case

### Q: How do I create a new app?
**A:**
1. Choose directory: `apps/` or `tools/`
2. Copy template: `cp docs/ARCHITECTURE_TEMPLATE.md <dir>/ARCHITECTURE.md`
3. Implement following CLAUDE.md
4. Document as you build
5. Test thoroughly (80%+ coverage)

### Q: How do I run checks manually?
**A:**
```bash
./.claude/scripts/checks/post-task-check.sh          # All checks
./.claude/scripts/checks/security-check.sh           # Security only
./.claude/scripts/checks/language-check.sh           # Language only
./.claude/scripts/documentation/architecture-check.sh # Architecture
```

---

## Development Workflow

### Creating New Example
1. Choose `apps/` or `tools/`
2. Copy ARCHITECTURE_TEMPLATE.md
3. Implement following guidelines
4. Document as you build
5. Test thoroughly
6. Verify checks pass

### Making Changes
1. Read existing ARCHITECTURE.md
2. Make changes following CLAUDE.md
3. Update ARCHITECTURE.md if structural changes
4. Update tests
5. Commit with descriptive message (10+ chars, English)

### Before Committing
- [ ] Follows CLAUDE.md guidelines
- [ ] English-only content
- [ ] No hardcoded credentials
- [ ] Tests updated (80%+ coverage)
- [ ] ARCHITECTURE.md updated
- [ ] Quality checks pass

---

## Troubleshooting

### Git Hooks Not Running
1. Verify: `ls -la .git/hooks/`
2. Re-run: `./.claude/scripts/setup/setup-git-hooks.sh`
3. Fix permissions: `chmod +x .git/hooks/pre-commit`

### MCP Servers Not Working
1. Restart Claude Code
2. Re-run: `./.claude/scripts/setup/setup-mcp-servers.sh`
3. See [guides/MCP-SETUP.md](guides/MCP-SETUP.md)

### Security Check Failed
- API key detected: Use environment variables
- `.env` tracked: `git rm --cached .env`, check .gitignore
- Private key found: Remove, add to .gitignore

### Language Check Failed
- Translate comments to English
- Rename variables to English

### Dart Analysis Failed
- Run `flutter pub get`
- Fix type errors
- Check pubspec.yaml for conflicts

---

## Key Concepts

### Two-Layer Quality Control
1. **Git Hooks** (universal, blocking) - All developers, during Git operations
2. **Claude Code Hooks** (real-time, non-blocking) - Claude Code users, during development

### Showcase Code Standards
This repository is for developers to learn from:
- Prioritize readability
- Refactor proactively
- Keep it simple (don't over-engineer)
- Use clear naming and structure
- Follow platform conventions (Flutter/Dart, Ditto SDK)

---

## Next Steps

1. Explore examples in `apps/` and `tools/`
2. Read existing ARCHITECTURE.md files
3. Review code and tests
4. Start building following guidelines

---

## Getting Help

1. **Check documentation**: [CLAUDE.md](../CLAUDE.md), [guides/](guides/)
2. **Run diagnostics**: `./.claude/scripts/setup/verify-setup.sh`
3. **Review error messages** - they indicate the fix
4. **Ask Claude Code** - Reference this guide and docs
5. **Contact team** via communication channels

---

## Summary

**Setup**: 15 minutes (clone, setup, verify, read CLAUDE.md)

**Key Rules**: English-only, no credentials, Git Hooks enforce quality, 80%+ test coverage, ARCHITECTURE.md required

**Quality Control**: Two-layer (Git Hooks + Claude Code Hooks)

**Resources**: [CLAUDE.md](../CLAUDE.md) (authoritative), [.claude/guides/](guides/) (detailed guides)

**Goal**: Build showcase-quality code for developers to learn from
