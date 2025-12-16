# Quality Checks and Hooks Guide

This guide explains the automated quality check system in this project, including hooks, scripts, and best practices for maintaining consistent code quality across the team.

## Table of Contents

1. [Overview](#overview)
2. [For Quick Reference](#for-quick-reference)
3. [How Hooks Work](#how-hooks-work)
4. [Enabled Hooks](#enabled-hooks)
5. [Manual Script Execution](#manual-script-execution)
6. [Developer Workflow](#developer-workflow)
7. [Understanding Check Results](#understanding-check-results)
8. [Team Guide](#team-guide)
9. [Customization](#customization)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

---

## Overview

This project uses automated hooks that run at specific events during Claude Code operation. They ensure consistent quality checks across all team members without manual intervention.

### What Gets Checked

**Security** ✅
- API keys and secrets
- Hardcoded passwords
- Private keys in repository
- Insecure patterns (eval, exec, innerHTML)
- `.env` file management and template synchronization

**Language** ✅
- Non-English comments
- Non-English documentation
- Appropriate exceptions (test data, i18n)

**Code Quality** ✅
- Dart static analysis
- Format consistency
- Documentation presence
- TODO tracking
- Git status awareness

**Architecture** ✅
- ARCHITECTURE.md existence
- Documentation freshness
- Required sections present
- Central index updates

### Key Benefits

**For Individual Developers**:
- ✅ No manual checklists needed
- ✅ Immediate feedback after changes
- ✅ Learning tool for best practices
- ✅ Auto-formatting for Dart files
- ✅ Security safety nets

**For Teams**:
- ✅ Consistent standards for everyone
- ✅ No quality variations between developers
- ✅ Faster onboarding for new team members
- ✅ Issues caught before code review
- ✅ Automated compliance enforcement

---

## For Quick Reference

### When Hooks Run

```
User Request → [user-prompt-submit] → Claude processes → [Write/Edit files] → Task completes → [task:complete]
      ↓                                                           ↓                           ↓
Guidelines reminder                                     Auto-format Dart           Quality + architecture checks
```

### Quick Commands

```bash
# Run all quality checks
./.claude/scripts/checks/post-task-check.sh

# Security check only (blocking)
./.claude/scripts/checks/security-check.sh

# Language check only (blocking)
./.claude/scripts/checks/language-check.sh

# Architecture check only (non-blocking)
./.claude/scripts/documentation/architecture-check.sh
```

---

## How Hooks Work

### Automatic Triggers

Hooks run automatically at specific events:

#### 1. Before Processing (`user-prompt-submit` hook)
**Trigger**: Before Claude processes your request
**Purpose**: Remind about project guidelines

Shows:
```
📋 Project Guidelines Active:
  • English-only artifacts
  • Security-first approach
  • Documentation updates required
  • Professional tone mandatory
  • Architecture documentation required
```

#### 2. After File Operations (`tool:Write` and `tool:Edit` hooks)
**Trigger**: After creating or editing files
**Purpose**: Auto-format and validate

- Confirms file was written/edited
- Auto-formats Dart files with `dart format`
- Non-blocking (continues even if format fails)

#### 3. After Task Completion (`task:complete` hook)
**Trigger**: After Claude completes a task
**Purpose**: Comprehensive quality check

Runs two main scripts:
1. `post-task-check.sh` - Quality and security checks
2. `architecture-check.sh` - Documentation validation

---

## Enabled Hooks

### 1. User Prompt Submit Hook

**When it runs**: Before processing each request

**What it does**: Displays reminder about project guidelines

**Benefit**: Keeps guidelines top-of-mind for every request

---

### 2. File Write Hook

**When it runs**: After creating a new file

**What it does**:
- Confirms file was written
- Auto-formats Dart files with `dart format`
- Non-blocking (continues even if format fails)

**Benefit**: Consistent code formatting without manual work

---

### 3. File Edit Hook

**When it runs**: After editing an existing file

**What it does**:
- Confirms file was edited
- Auto-formats Dart files with `dart format`
- Non-blocking (continues even if format fails)

**Benefit**: Maintains code style consistency

---

### 4. Task Complete Hook

**When it runs**: After Claude completes a task

**What it does**: Runs comprehensive quality checks

```
🔍 Running Post-Task Quality Checks...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1/6] Checking git status...
[2/6] Scanning for potential secrets...
[3/6] Checking for non-English content...
[4/6] Running Flutter/Dart checks...
[5/6] Checking documentation...
[6/6] Code quality checklist...

=== Architecture Documentation Check ===
```

**Checks performed**:

1. **Git Status** - Shows uncommitted changes
2. **Security Scan**:
   - API keys and secrets
   - Hardcoded passwords
   - Private keys
   - Insecure patterns (eval, exec, innerHTML)
   - `.env` file changes and template synchronization
3. **Language Compliance** - Detects non-English content
4. **Dart Analysis** - Static code analysis (if Dart project)
5. **Documentation**:
   - README exists and has content
   - New TODO comments tracked
6. **Quality Reminders**:
   - Error handling
   - Input validation
   - Test coverage
   - Simple implementations
7. **Architecture Check**:
   - ARCHITECTURE.md existence
   - Documentation freshness
   - Required sections present

**Benefit**: Catches issues immediately after changes

---

## Manual Script Execution

You can run quality checks manually anytime:

### Post-Task Check (Non-blocking)
```bash
./.claude/scripts/checks/post-task-check.sh
```
**Returns**: Always exit code 0 (informational only)

### Security Check (Blocking)
```bash
./.claude/scripts/checks/security-check.sh
```
**Returns**: Exit code 1 if issues found (blocking)

### Language Check (Blocking)
```bash
./.claude/scripts/checks/language-check.sh
```
**Returns**: Exit code 1 if non-English content found (blocking)

### Architecture Check (Non-blocking)
```bash
./.claude/scripts/documentation/architecture-check.sh
```
**Returns**: Always exit code 0 (informational only)

### Hook Behavior: Non-Blocking vs Blocking

**Non-Blocking** (Post-task and architecture checks):
- Reports issues but continues workflow
- Shows warnings and suggestions
- Always returns exit code 0
- Educational and informative

**Blocking** (Manual security and language checks):
- Stops on critical issues
- Returns exit code 1 on failure
- Use in CI/CD or pre-commit hooks
- Enforces compliance

---

## Developer Workflow

### Normal Development Workflow

```
1. Make request to Claude Code
   ↓
2. [Hook] Guidelines reminder shows
   ↓
3. Claude creates/edits files
   ↓
4. [Hook] Dart files auto-formatted
   ↓
5. Task completes
   ↓
6. [Hook] Comprehensive quality checks run
   ↓
7. Review output for warnings/issues
   ↓
8. Address any issues found
   ↓
9. Commit with confidence
```

### Common Scenarios

#### Scenario 1: Adding New Feature
```
1. Request: "Add user authentication"
2. [user-prompt-submit] → Reminder about guidelines
3. Claude creates files → [tool:Write] → Auto-format
4. Claude edits files → [tool:Edit] → Auto-format
5. Task completes → [task:complete] → Quality check
6. Review results and commit
```

#### Scenario 2: Bug Fix
```
1. Request: "Fix login validation"
2. [user-prompt-submit] → Reminder about guidelines
3. Claude edits files → [tool:Edit] → Auto-format
4. Task completes → [task:complete] → Quality check
5. Review security scan for validation issues
6. Commit with confidence
```

#### Scenario 3: Documentation Update
```
1. Request: "Update API documentation"
2. [user-prompt-submit] → Reminder about English-only
3. Claude edits README → [tool:Edit]
4. Task completes → [task:complete] → Language check
5. Verify no non-English content
6. Commit documentation
```

---

## Understanding Check Results

### Output Indicators

**✓ Green (Success)**
```
✓ No uncommitted changes
✓ No obvious secrets detected
✓ All files use English
```
Everything is good - no action needed.

**⚠ Yellow (Warning)**
```
⚠ Uncommitted changes detected
⚠ Warning: ARCHITECTURE.md may be outdated
⚠ TODO comments added
```
Review the warning - may need action but not critical.

**✗ Red (Error)**
```
✗ Possible API key found in: src/config.js
✗ .env file is tracked in git!
✗ Possible hardcoded password in: auth.py
```
Action required - fix before committing.

**ℹ Blue (Info)**
```
ℹ Checking if central architecture index needs updating...
[1/6] Checking git status...
```
Informational message about ongoing checks.

### Common Warnings and What to Do

#### "Uncommitted changes detected"
- **What it means**: You have changes not yet committed
- **What to do**: Review changes and commit when ready
- **It's OK if**: You're still working on the feature

#### "Possible API key found"
- **What it means**: Pattern matches potential credential
- **What to do**: Review immediately - may be false positive
- **Action required**: Remove if real, document if test data

#### ".env file changes detected"
- **What it means**: Environment variable files have been modified
- **What to do**: Ensure `.env.template` is updated to match
- **Action required**: Sync `.env.template` with any new keys, never commit actual `.env` values

#### ".env file is tracked in git!"
- **What it means**: Your `.env` file is committed to the repository
- **What to do**: Run: `git rm --cached .env && echo '.env' >> .gitignore`
- **Action required**: Remove immediately and verify no secrets exposed

#### "Non-English content found"
- **What it means**: Japanese or other non-English text detected
- **What to do**: Review - acceptable for test data, i18n strings
- **Action required**: Change to English if code/comments/docs

#### "ARCHITECTURE.md is outdated"
- **What it means**: Source code modified after documentation
- **What to do**: Update ARCHITECTURE.md to reflect changes
- **Action required**: Update relevant sections and timestamp

#### "README.md is empty"
- **What it means**: Project documentation missing
- **What to do**: Add project documentation
- **It's OK if**: Project is brand new

#### "TODO comments added"
- **What it means**: New TODO comments in code
- **What to do**: Consider creating issues for tracking
- **It's OK if**: Quick reminders for current work

---

## Team Guide

### For Team Leaders / Project Managers

#### What This Setup Provides

This project has automated quality checks that run for every developer using Claude Code. No manual intervention needed - the system ensures consistency automatically.

#### Key Points to Share with Team

1. **Automatic Checks** - Quality gates run automatically
2. **No Extra Work** - Developers don't need to do anything special
3. **Consistent Standards** - Everyone gets the same checks
4. **Immediate Feedback** - Issues caught right after changes
5. **Educational** - System teaches best practices

#### When to Review This Setup

- **Monthly**: Check if hooks are effective
- **Quarterly**: Update based on team feedback
- **When onboarding**: Brief new developers
- **After issues**: Add new checks if patterns emerge

### For New Team Members

#### Getting Started

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ditto-cookbook
   ```

2. **Verify hooks are ready**
   ```bash
   ls -la .claude/
   # Should see: hooks.json, scripts/, guides/, *.md files
   ```

3. **Read the guides**
   - [quality-checks.md](.claude/guides/quality-checks.md) - This comprehensive guide
   - [architecture.md](.claude/guides/architecture.md) - Architecture documentation guide
   - [CLAUDE.md](../CLAUDE.md) - Development guidelines

4. **Test with a simple change**
   ```bash
   # Use Claude Code to make a small change
   # Watch the hooks run
   # Review the output
   ```

#### First Week Checklist

- [ ] Read [CLAUDE.md](../CLAUDE.md) - Development guidelines
- [ ] Read [quality-checks.md](.claude/guides/quality-checks.md) - This guide
- [ ] Read [architecture.md](.claude/guides/architecture.md) - Architecture guide
- [ ] Make a test change with Claude Code
- [ ] See hooks run automatically
- [ ] Run manual security check: `./.claude/scripts/checks/security-check.sh`
- [ ] Run manual language check: `./.claude/scripts/checks/language-check.sh`
- [ ] Ask questions if anything is unclear

#### Common Questions

**Q: Do I need to install anything?**
A: No. If you have Claude Code and git, you're ready.

**Q: Will hooks slow down my work?**
A: No. Checks run in 1-2 seconds and are informational only.

**Q: What if I disagree with a warning?**
A: Review it, discuss with team, document exceptions if needed.

**Q: Can I disable hooks?**
A: Yes, but discuss with team first. Set `"enabled": false` in [hooks.json](../hooks.json).

**Q: What if hooks find a false positive?**
A: Document it in code comments and continue. Report to team if frequent.

### For Code Reviewers

#### Using Hook Output in Reviews

When reviewing PRs, ask developers:

1. **Did hooks run?** - Should see output in PR description
2. **Were warnings addressed?** - Check if issues resolved
3. **Are exceptions documented?** - If warnings ignored, why?

#### Red Flags

Watch for:
- ❌ Security warnings ignored without explanation
- ❌ `.env` changes without corresponding `.env.template` updates
- ❌ Actual `.env` values committed to repository
- ❌ Non-English content in code/docs (unless i18n)
- ❌ Multiple TODOs without corresponding issues
- ❌ Analysis errors not addressed
- ❌ ARCHITECTURE.md not updated with code changes

#### Green Flags

Good signs:
- ✅ Hook output included in PR
- ✅ Warnings addressed or explained
- ✅ Tests added for new features
- ✅ Documentation updated
- ✅ Clean security scan
- ✅ Architecture documentation current

---

## Customization

### Disable Specific Checks

Edit [hooks.json](../hooks.json):

```json
{
  "hooks": {
    "user-prompt-submit": {
      "description": "Disabled",
      "command": "echo 'Skipping reminder'"
    }
  }
}
```

### Add Project-Specific Checks

Edit [scripts/checks/post-task-check.sh](../scripts/checks/post-task-check.sh):

```bash
# Add after existing checks
echo ""
echo -e "${BLUE}[7/7]${NC} Running custom Ditto checks..."

# Your custom logic here
if command -v ditto &> /dev/null; then
    echo "→ Validating Ditto configuration..."
    # Add Ditto-specific validation
fi
```

### Disable All Hooks

Set `enabled: false` in [hooks.json](../hooks.json):

```json
{
  "hooks": {
    ...
  },
  "enabled": false
}
```

### Integration with Git Hooks

This project also uses **Git Hooks** for universal quality enforcement across all developers (not just Claude Code users).

**See [git-hooks.md](git-hooks.md) for full details on Git Hooks setup and usage.**

Git Hooks provide:
- **pre-commit** - Security and language checks before commit (blocking)
- **commit-msg** - Commit message validation (blocking)
- **pre-push** - Comprehensive checks before push (blocking)

To install Git Hooks:
```bash
./.claude/scripts/setup/setup-git-hooks.sh
```

**Difference between Claude Code Hooks and Git Hooks:**
- **Claude Code Hooks**: Real-time feedback during development (non-blocking)
- **Git Hooks**: Final quality gate before version control (blocking)

---

## Troubleshooting

### Hooks Not Running

**Problem**: No hook output after Claude Code tasks

**Solutions**:
1. Check `.claude/hooks.json` has `"enabled": true`
2. Verify scripts are executable: `ls -l .claude/scripts/**/*.sh`
3. Test manually: `./.claude/scripts/checks/post-task-check.sh`
4. Check Claude Code version is up to date

### Script Errors

**Problem**: Hook script fails with error

**Solutions**:
1. Check script syntax: `bash -n .claude/scripts/checks/post-task-check.sh`
2. Verify dependencies: `command -v git dart grep`
3. Check file permissions: `ls -l .claude/scripts/`
4. Review full error in Claude Code console

### Too Many False Positives

**Problem**: Hooks flag too many non-issues

**Solutions**:
1. Review patterns in scripts - may need adjustment
2. Document common exceptions in code comments
3. Update script to skip known patterns
4. Discuss with team - may need refinement

### Hooks Too Strict

**Problem**: Hooks block legitimate work

**Solutions**:
1. Remember: Hooks are informational, not blocking
2. Manual scripts (security-check.sh, language-check.sh) are blocking
3. Adjust blocking scripts if too strict
4. Discuss with team - may need loosening

---

## Best Practices

### Do's ✅

- **Review hook output** after each task
- **Run manual checks** before commits (security, language)
- **Update scripts** as project evolves
- **Document exceptions** for false positives
- **Share results** with team for learning
- **Address warnings** - Investigate all issues
- **Keep documentation current** - Update ARCHITECTURE.md with code changes

### Don'ts ❌

- **Don't ignore warnings** - Investigate all issues
- **Don't disable hooks** without team agreement
- **Don't bypass checks** for "quick fixes"
- **Don't commit** without reviewing hook output
- **Don't skip** manual security checks for sensitive changes
- **Don't commit .env files** - Always use templates

---

## Benefits for Teams

### Consistency
- Same checks for all developers
- No variation in quality standards
- Automated enforcement of guidelines

### Efficiency
- Catches issues immediately
- No manual checklist needed
- Auto-formatting saves time

### Education
- Reminds about best practices
- Teaches security awareness
- Reinforces coding standards

### Quality
- Prevents common mistakes
- Ensures documentation updates
- Maintains code style

### Security
- Detects credential exposure
- Identifies injection risks
- Prevents XSS vulnerabilities
- Validates environment variable management

---

## Summary

🎉 **This project has comprehensive automated quality checks!**

**What you have**:
- ✅ Automated quality checks via hooks
- ✅ Security vulnerability scanning
- ✅ English-only enforcement
- ✅ Architecture documentation validation
- ✅ Comprehensive documentation
- ✅ Team consistency guaranteed

**What's different**:
- 🚫 No manual checklists needed
- 🚫 No quality variations between developers
- 🚫 No missed security issues
- 🚫 No language policy violations
- 🚫 No outdated documentation

**Result**: Professional, secure, consistent development experience for all team members! 🚀

---

## Further Reading

- [Claude Code Documentation](https://github.com/anthropics/claude-code)
- [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [CLAUDE.md](../CLAUDE.md) - Full development guidelines
- [Architecture Guide](.claude/guides/architecture.md) - Architecture documentation guide
- [README.md](../README.md) - Configuration overview
