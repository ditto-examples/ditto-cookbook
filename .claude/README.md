# Claude Code Configuration

This directory contains configuration files for Claude Code, the AI-powered development assistant.

## Directory Structure

- **settings.json** - Core configuration (points to CLAUDE.md)
- **hooks.json** - Automated quality check triggers
- **settings.local.json** - Personal settings (gitignored, optional)
- **guides/** - Comprehensive documentation
  - git-hooks.md - Git Hooks setup and usage (universal quality enforcement)
  - quality-checks.md - Claude Code hooks and workflows
  - architecture.md - Architecture documentation guide
  - dependency-management.md - Dependency management and Ditto SDK versioning
  - MCP-SETUP.md - MCP servers setup guide
- **commands/** - Claude Code slash commands
  - update-deps.md - Dependency management command
- **scripts/** - Hook scripts organized by purpose
  - checks/ - Quality and security check scripts
  - documentation/ - Documentation validation scripts
  - setup/ - Setup and installation scripts
  - maintenance/ - Dependency management scripts
    - update-dependencies.sh - Main dependency orchestrator
    - check-ditto-versions.sh - Ditto SDK version checker (HIGH PRIORITY)
    - dependency-managers/ - Platform-specific managers (Flutter, Node.js, Python, iOS, Android)
  - testing/ - Test automation infrastructure
    - test-orchestrator.sh - Main test coordinator
    - utils/ - Shared helper functions
    - runners/ - Platform-specific test runners

## Quick Start

### One-Time Setup (All Developers)

**Recommended** - Run complete setup:
```bash
./.claude/scripts/setup/complete-setup.sh
```
This installs Git Hooks, checks Claude Code, and optionally configures MCP servers.

**Alternative** - Individual steps:
```bash
# Required for all developers
./.claude/scripts/setup/setup-git-hooks.sh

# Verify installation
./.claude/scripts/setup/verify-setup.sh

# Optional: MCP servers (Claude Code users only)
./.claude/scripts/setup/setup-mcp-servers.sh  # Then restart Claude Code
```

### What You Get

After setup, these checks run automatically:

**When you commit:** Security scan, language check, commit message validation
**When you push:** All commit checks + code analysis + architecture validation

### Example Workflow

```bash
# Make changes and commit
git add src/main.dart
git commit -m "Add user authentication feature"
# → Hooks run automatically. If checks pass, commit is created.

# Push to remote
git push
# → Pre-push checks run. If checks pass, code is pushed.
```

### If Checks Fail

- **Security issue**: Remove API key/secret, use environment variables
- **Language issue**: Replace non-English text with English
- **Commit message**: Write more descriptive message (10+ chars)

**Emergency bypass** (rare cases only):
```bash
git commit --no-verify -m "Emergency hotfix"  # Document reason!
```

### Common Questions

- **Need Claude Code?** No. Git Hooks work for all developers.
- **Slow commits?** No. Checks complete in 1-3 seconds.
- **False positive?** Bypass with `--no-verify` and document reason.
- **Check status?** Run: `./.claude/scripts/setup/verify-setup.sh`

### Essential Reading

- [../CLAUDE.md](../CLAUDE.md) - Development guidelines (start here)
- [guides/git-hooks.md](guides/git-hooks.md) - Complete Git Hooks guide
- [guides/quality-checks.md](guides/quality-checks.md) - Claude Code hooks
- [guides/architecture.md](guides/architecture.md) - Architecture documentation
- [guides/dependency-management.md](guides/dependency-management.md) - Dependency management

### Key Commands

```bash
# Complete setup (recommended, run once after cloning)
./.claude/scripts/setup/complete-setup.sh

# Verify setup status
./.claude/scripts/setup/verify-setup.sh

# Setup Git Hooks only
./.claude/scripts/setup/setup-git-hooks.sh

# Run tests for all applications
./scripts/test-all.sh

# Check dependencies across all apps/tools
/update-deps check

# Update dependencies interactively
/update-deps update

# Update all dependencies automatically
/update-deps update --all

# Check Ditto SDK versions (HIGH PRIORITY)
/update-deps ditto

# Run all quality checks manually
./.claude/scripts/checks/post-task-check.sh

# Run security check only
./.claude/scripts/checks/security-check.sh

# Run language check only
./.claude/scripts/checks/language-check.sh

# Run architecture check only
./.claude/scripts/documentation/architecture-check.sh
```

---

## Configuration Files

**settings.json**: Minimal config, references CLAUDE.md (authoritative source)

**hooks.json**: Automated hooks (user-prompt-submit, tool:Write/Edit, task:complete). See [guides/quality-checks.md](guides/quality-checks.md)

**../CLAUDE.md**: Authoritative development guidelines. Read this first.

---

## Comprehensive Guides

**[guides/git-hooks.md](guides/git-hooks.md)**: Git Hooks setup and usage (essential for all developers)

**[guides/quality-checks.md](guides/quality-checks.md)**: Claude Code hooks guide

**[guides/architecture.md](guides/architecture.md)**: Architecture documentation guide

**[guides/dependency-management.md](guides/dependency-management.md)**: Dependency and Ditto SDK management

**[guides/MCP-SETUP.md](guides/MCP-SETUP.md)**: MCP servers setup

---

## Claude Code Commands

### /update-deps
Dependency management command for checking and updating dependencies across all apps and tools.

**Usage**:
```bash
/update-deps check              # Check for outdated dependencies
/update-deps update             # Update dependencies interactively
/update-deps update --all       # Update all dependencies automatically
/update-deps ditto              # Check Ditto SDK versions (HIGH PRIORITY)
```

**See**: [commands/update-deps.md](commands/update-deps.md) and [guides/dependency-management.md](guides/dependency-management.md)

---

## Hook Scripts

**Setup**: `complete-setup.sh` (recommended), `verify-setup.sh`, `setup-git-hooks.sh`, `setup-mcp-servers.sh`

**Quality Checks**: `post-task-check.sh` (non-blocking), `security-check.sh` (blocking), `language-check.sh` (blocking)

**Documentation**: `architecture-check.sh` (non-blocking)

**Testing**: `./scripts/test-all.sh` (main entry), `test-orchestrator.sh` (discovers and runs all tests in parallel)

---

## How Hooks Work

**Two types of hooks**:

1. **Git Hooks** (universal, blocking) - All developers, during Git operations. See [guides/git-hooks.md](guides/git-hooks.md)
2. **Claude Code Hooks** (real-time, non-blocking) - Claude Code users, during development. See [guides/quality-checks.md](guides/quality-checks.md)

**Benefits**: Automated quality enforcement, immediate feedback, consistent standards

---

## Customization

**Custom checks**: Edit scripts in `scripts/checks/` or `scripts/documentation/`

**Disable hooks**: Set `"enabled": false` in [hooks.json](hooks.json)

**Personal settings**: Create `.claude/settings.local.json` (gitignored)

---

## Troubleshooting

**Hooks not running**: Check `hooks.json` enabled, verify script permissions, test manually

**Script errors**: Check syntax with `bash -n`, review console output

**MCP issues**: See [guides/MCP-SETUP.md](guides/MCP-SETUP.md)

---

## References

**Guides**: [git-hooks.md](guides/git-hooks.md), [quality-checks.md](guides/quality-checks.md), [architecture.md](guides/architecture.md), [dependency-management.md](guides/dependency-management.md), [MCP-SETUP.md](guides/MCP-SETUP.md)

**Development**: [../CLAUDE.md](../CLAUDE.md) (authoritative)

**External**: [Claude Code Docs](https://github.com/anthropics/claude-code), [MCP Protocol](https://modelcontextprotocol.io)

---

## Summary

**Two-Layer Quality Control**:
1. **Git Hooks** (universal, blocking) - Before commit/push
2. **Claude Code Hooks** (real-time, non-blocking) - During development

**Features**: Security scanning, language enforcement, architecture validation, automated checks

**Remember**: [../CLAUDE.md](../CLAUDE.md) is authoritative. Check guides for details.
