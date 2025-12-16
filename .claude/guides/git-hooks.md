# Git Hooks Guide

This guide explains how to set up and use Git Hooks to maintain code quality across all developers in the team.

## Table of Contents

1. [Overview](#overview)
2. [Quick Setup](#quick-setup)
3. [Installed Hooks](#installed-hooks)
4. [How Hooks Work](#how-hooks-work)
5. [Developer Workflow](#developer-workflow)
6. [Bypassing Hooks](#bypassing-hooks)
7. [Troubleshooting](#troubleshooting)
   - [Getting Help from Claude Code](#getting-help-from-claude-code)
   - [Hooks Not Running](#hooks-not-running)
   - [Hook Fails with Script Not Found](#hook-fails-with-script-not-found)
   - [False Positives](#false-positives)
   - [Hook Performance Issues](#hook-performance-issues)
8. [Integration with Claude Code Hooks](#integration-with-claude-code-hooks)
9. [Best Practices](#best-practices)

---

## Overview

Git Hooks are scripts that run automatically at specific points in the Git workflow. This project uses Git Hooks to enforce quality standards before code is committed or pushed to the remote repository.

### Why Git Hooks?

**For Individual Developers:**
- ✅ Catches issues before they enter version control
- ✅ Prevents accidental commits of secrets or inappropriate content
- ✅ Validates commit message quality
- ✅ Ensures consistency across the team

**For Teams:**
- ✅ Enforces standards for all developers automatically
- ✅ Reduces code review burden
- ✅ Prevents bad commits from reaching the repository
- ✅ Works even without Claude Code

### Git Hooks vs Claude Code Hooks

This project has **both** Git Hooks and Claude Code Hooks working together:

| Feature | Claude Code Hooks | Git Hooks |
|---------|------------------|-----------|
| **When they run** | During Claude Code operations | During Git operations |
| **Who uses them** | Developers using Claude Code | All developers (universal) |
| **Scope** | Real-time feedback during development | Gate before commit/push |
| **Enforcement** | Informational (non-blocking) | Blocking (prevents bad commits) |
| **Setup** | Automatic (via .claude/hooks.json) | Manual (run setup script) |

**Together they provide comprehensive quality control at every stage of development.**

---

## Quick Setup

### For New Developers

When you clone this repository, Git Hooks are **not automatically installed**. You need to run the setup script once:

```bash
# From the repository root
./.claude/scripts/setup/setup-git-hooks.sh
```

This will install three hooks:
- **pre-commit** - Runs before each commit
- **commit-msg** - Validates commit messages
- **pre-push** - Runs before pushing to remote

### Verification

After running the setup script, verify the hooks are installed:

```bash
ls -la .git/hooks/
```

You should see executable files (not .sample files):
- `pre-commit`
- `commit-msg`
- `pre-push`

---

## Installed Hooks

### 1. Pre-Commit Hook

**Runs:** Before each `git commit`

**Purpose:** Prevents committing code with security or language issues

**Checks performed:**
- 🔒 **Security check** - Scans for API keys, passwords, private keys
- 🌐 **Language check** - Ensures English-only code and documentation
- 📁 **Environment file check** - Validates .env file management

**Example output:**
```
🔒 Running Pre-Commit Quality Checks...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/2] Running security checks...
✓ Security check passed
[2/2] Running language checks...
✓ Language check passed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Pre-commit checks passed!
```

**If checks fail:**
```
❌ Pre-commit checks failed!

Please fix the issues above before committing.

💡 Need help? Ask Claude Code how to resolve these issues:
   • Open Claude Code and describe the error message
   • Claude Code can help you fix security or language violations

To bypass this check (not recommended), use: git commit --no-verify
```

---

### 2. Commit-Msg Hook

**Runs:** After entering commit message, before commit is finalized

**Purpose:** Ensures commit messages meet quality standards

**Validation rules:**
- ✅ Subject line under 72 characters (warns if longer)
- ✅ English only (no Japanese or other non-English characters)
- ✅ Professional language (no profanity)
- ✅ Proper formatting

**Example - Failed validation:**
```
✗ Commit message contains non-English characters

❌ Commit message validation failed!

Current message:
---
修正しました
---

Please revise your commit message.
```

**Good commit message examples:**
```
Add user authentication feature

Fix validation bug in login form

Update API documentation for v2.0 endpoints

Refactor database connection handling
```

---

### 3. Pre-Push Hook

**Runs:** Before `git push` sends commits to remote

**Purpose:** Comprehensive quality check before code reaches the team

**Checks performed:**
- 🔒 **Security check** - Full security scan
- 🌐 **Language check** - English-only enforcement
- 📊 **Code analysis** - Dart static analysis (if applicable)
- 📚 **Architecture documentation** - Validates ARCHITECTURE.md

**Example output:**
```
🚀 Running Pre-Push Quality Checks...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/4] Running security checks...
✓ Security check passed
[2/4] Running language checks...
✓ Language check passed
[3/4] Running code analysis...
✓ Dart analysis passed
[4/4] Checking architecture documentation...
✓ Architecture check completed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Pre-push checks passed!
```

---

## How Hooks Work

### Pre-Commit Workflow

```
Developer runs: git commit -m "message"
         ↓
    Pre-commit hook runs
         ↓
    Security check → Language check
         ↓
    ✅ Pass: Commit continues
    ❌ Fail: Commit blocked
```

### Commit-Msg Workflow

```
Developer enters commit message
         ↓
    Commit-msg hook runs
         ↓
    Validates: length, language, professionalism
         ↓
    ✅ Pass: Commit continues
    ❌ Fail: Commit blocked
```

### Pre-Push Workflow

```
Developer runs: git push
         ↓
    Pre-push hook runs
         ↓
    Full quality check (security, language, analysis, docs)
         ↓
    ✅ Pass: Push continues
    ❌ Fail: Push blocked
```

---

## Developer Workflow

### Normal Workflow (No Issues)

```bash
# 1. Make changes to code
vim src/main.dart

# 2. Stage changes
git add src/main.dart

# 3. Commit (pre-commit and commit-msg hooks run automatically)
git commit -m "Add user authentication feature"
# → Pre-commit hook: ✅ Passed
# → Commit-msg hook: ✅ Passed
# → Commit created successfully

# 4. Push (pre-push hook runs automatically)
git push
# → Pre-push hook: ✅ Passed
# → Code pushed successfully
```

### Workflow with Issues

```bash
# 1. Make changes (accidentally include API key)
vim src/config.dart

# 2. Stage and try to commit
git add src/config.dart
git commit -m "Update configuration"

# → Pre-commit hook: ❌ Failed
# → ✗ Possible API key found in: src/config.dart
# → Commit blocked
# → 💡 Need help? Ask Claude Code how to resolve these issues

# 3. Ask Claude Code for help (recommended)
# Open Claude Code and paste the error message, or simply ask:
# "The pre-commit hook found a possible API key in src/config.dart. How should I fix this?"

# 4. Fix the issue based on Claude Code's suggestions
vim src/config.dart  # Remove the API key or move to environment variable

# 5. Try again
git add src/config.dart
git commit -m "Update configuration"
# → Pre-commit hook: ✅ Passed
# → Commit created successfully
```

---

## Bypassing Hooks

### When to Bypass

Hooks can be bypassed using `--no-verify`, but this is **strongly discouraged** except in specific situations:

**Acceptable reasons:**
- Emergency hotfixes (with immediate follow-up fix)
- Working with intentional test data containing patterns that trigger false positives
- Rebasing or amending commits where checks already passed

**Never acceptable:**
- To avoid fixing real security issues
- To commit non-English content against project policy
- To skip fixing actual code quality issues

### How to Bypass

```bash
# Bypass pre-commit and commit-msg hooks
git commit --no-verify -m "Emergency hotfix"

# Bypass pre-push hook
git push --no-verify
```

**Important:** If you bypass hooks, document why in the commit message or pull request description.

---

## Troubleshooting

### Getting Help from Claude Code

**When you encounter any Git Hook warnings or errors, Claude Code can help!**

Claude Code is designed to assist with all types of development issues, including Git Hook failures. Here's how to get help:

**1. For Security Issues:**
```bash
# If you see: "✗ Possible API key found in: src/config.dart"

Ask Claude Code:
"The pre-commit hook detected a possible API key in src/config.dart.
How should I handle this securely?"

Claude Code can:
• Analyze the file to identify the security issue
• Suggest using environment variables
• Help you set up .env files properly
• Update your code to use secure practices
```

**2. For Language Issues:**
```bash
# If you see: "✗ Non-English content found in: README.md"

Ask Claude Code:
"The language check found non-English content in README.md.
Can you help me translate it to English?"

Claude Code can:
• Identify the non-English content
• Translate it to professional English
• Maintain proper technical terminology
• Preserve code formatting
```

**3. For Commit Message Issues:**
```bash
# If you see: "✗ Contains non-English characters" or "✗ Contains inappropriate language"

Ask Claude Code:
"I need help writing a proper commit message for my changes.
I modified the authentication flow to add session timeout."

Claude Code can:
• Suggest well-formatted commit messages
• Follow project conventions
• Write descriptive and professional messages
• Ensure English-only content
```

**4. For Code Analysis Issues:**
```bash
# If you see: "✗ Dart analysis found issues"

Ask Claude Code:
"The pre-push hook found Dart analysis issues.
Can you help me fix them?"

Claude Code can:
• Run analysis and identify specific issues
• Fix type errors and warnings
• Suggest best practices
• Ensure code quality
```

**Best Practices for Getting Help:**
- Copy and paste the exact error message to Claude Code
- Provide context about what you were trying to do
- Ask Claude Code to explain why the hook failed
- Request suggestions for how to fix the issue properly

**Remember:** Claude Code is here to help you understand and resolve issues, not just bypass them!

---

### Hooks Not Running

**Problem:** Git operations complete without any hook output

**Solutions:**

1. **Check if hooks are installed:**
   ```bash
   ls -la .git/hooks/
   # Should see: pre-commit, commit-msg, pre-push (without .sample extension)
   ```

2. **Run setup script:**
   ```bash
   ./.claude/scripts/setup/setup-git-hooks.sh
   ```

3. **Verify permissions:**
   ```bash
   chmod +x .git/hooks/pre-commit
   chmod +x .git/hooks/commit-msg
   chmod +x .git/hooks/pre-push
   ```

---

### Hook Fails with Script Not Found

**Problem:** Hook runs but can't find check scripts

**Error message:**
```
⚠  Security check script not found, skipping...
```

**Solution:**

Ensure scripts exist and are executable:
```bash
ls -la .claude/scripts/checks/
# Should see: security-check.sh, language-check.sh

chmod +x .claude/scripts/checks/*.sh
chmod +x .claude/scripts/documentation/*.sh
```

---

### False Positives

**Problem:** Hook incorrectly flags legitimate code

**Example:**
```
✗ Possible API key found in: test/fixtures/sample_data.dart
```

**Solutions:**

1. **Add explanatory comment in code:**
   ```dart
   // Test fixture with dummy API key (not a real credential)
   const testApiKey = "test_key_123";
   ```

2. **Document in commit message:**
   ```bash
   git commit -m "Add test fixtures

   Note: Contains dummy API keys for testing purposes only.
   These are not real credentials."
   ```

3. **Bypass if necessary (with documentation):**
   ```bash
   git commit --no-verify -m "Add test fixtures (see PR description for security review)"
   ```

---

### Hook Performance Issues

**Problem:** Hooks take too long to run

**Solutions:**

1. **Check file count:**
   ```bash
   git status
   # If many files staged, consider committing in smaller batches
   ```

2. **Skip Dart analysis in pre-commit:**
   - Dart analysis runs in pre-push, not pre-commit
   - Pre-commit should be fast (< 5 seconds)

3. **Report performance issues:**
   - If hooks consistently take > 10 seconds, report to team
   - May need optimization of check scripts

---

## Integration with Claude Code Hooks

This project uses **both** Git Hooks and Claude Code Hooks for comprehensive quality control:

### Claude Code Hooks (Real-time during development)

**Location:** `.claude/hooks.json`

**Purpose:** Immediate feedback while coding with Claude Code

**Runs:**
- `user-prompt-submit` - Before processing requests
- `tool:Write` / `tool:Edit` - After file changes (auto-format)
- `task:complete` - After task completion (quality checks)

**Behavior:** Non-blocking (informational)

**See:** [quality-checks.md](quality-checks.md) for full details

### Git Hooks (Gate before version control)

**Location:** `.git/hooks/`

**Purpose:** Enforce standards before commits/pushes

**Runs:**
- `pre-commit` - Before each commit
- `commit-msg` - After commit message entered
- `pre-push` - Before push to remote

**Behavior:** Blocking (prevents bad commits)

### How They Work Together

```
Development Flow:

1. Claude Code Changes
   ↓
   [Claude Code Hooks - Immediate feedback]
   ↓
2. Git Add
   ↓
3. Git Commit
   ↓
   [Git Hooks - Pre-commit check]
   ↓
   [Git Hooks - Commit-msg validation]
   ↓
4. Git Push
   ↓
   [Git Hooks - Pre-push check]
   ↓
5. Code in Repository
```

**Layered Defense:**
- **Claude Code Hooks:** Catch issues early, guide during development
- **Git Hooks:** Final gate, enforce standards universally

---

## Best Practices

### Do's ✅

- **Install hooks immediately** after cloning the repository
- **Read hook output carefully** when checks fail
- **Ask Claude Code for help** when you encounter warnings or errors
- **Fix issues** rather than bypassing hooks
- **Keep hooks updated** by running setup script periodically
- **Document exceptions** when bypassing is necessary
- **Share setup instructions** with new team members
- **Test hooks** after installation with a dummy commit

### Don'ts ❌

- **Don't bypass hooks routinely** - they exist for a reason
- **Don't ignore warnings** - investigate all flagged issues
- **Don't commit without reading hook output** - even if it passes
- **Don't modify hooks manually** - use setup script instead
- **Don't delete hooks** - disable in script if needed
- **Don't commit credentials** - even if you plan to remove later

---

## Team Onboarding

### For New Team Members

**Day 1 Checklist:**

1. **Clone repository**
   ```bash
   git clone <repository-url>
   cd ditto-cookbook
   ```

2. **Install Git Hooks**
   ```bash
   ./.claude/scripts/setup/setup-git-hooks.sh
   ```

3. **Verify installation**
   ```bash
   ls -la .git/hooks/
   ```

4. **Read documentation**
   - [CLAUDE.md](../../CLAUDE.md) - Development guidelines
   - [quality-checks.md](quality-checks.md) - Claude Code hooks
   - [git-hooks.md](git-hooks.md) - This guide

5. **Test with dummy commit**
   ```bash
   # Create a test file
   echo "# Test" > test.md
   git add test.md
   git commit -m "Test commit to verify hooks"
   # Hooks should run successfully
   git reset HEAD~1  # Undo test commit
   git checkout test.md  # Remove test file
   ```

### For Team Leaders

**Setup Verification:**

Ensure all team members have installed Git Hooks:

```bash
# Check if hooks exist in a team member's clone
ls -la .git/hooks/ | grep -E "pre-commit|commit-msg|pre-push"
```

**Regular Reviews:**

- **Monthly:** Check if hooks are still effective
- **Quarterly:** Update hooks based on new requirements
- **After incidents:** Add checks if patterns emerge

---

## Updating Hooks

### When to Update

Update hooks when:
- Project quality standards change
- New check scripts are added to `.claude/scripts/`
- Security requirements evolve
- Team requests new validations

### How to Update

Simply run the setup script again:

```bash
./.claude/scripts/setup/setup-git-hooks.sh
```

This will:
- ✅ Overwrite existing hooks with new versions
- ✅ Preserve any local modifications to check scripts
- ✅ Update all three hooks simultaneously

**Note:** Hooks are generated from the setup script, so any manual edits to hooks in `.git/hooks/` will be lost. Always edit the setup script instead.

---

## Summary

🎉 **Git Hooks provide universal quality enforcement for all developers!**

**What you get:**
- ✅ Automatic quality checks before commits and pushes
- ✅ Security vulnerability prevention
- ✅ Commit message quality enforcement
- ✅ English-only compliance
- ✅ Works for all developers (not just Claude Code users)
- ✅ Helpful guidance to use Claude Code when issues occur

**What's required:**
- ✅ One-time setup: Run `./.claude/scripts/setup/setup-git-hooks.sh`
- ✅ Periodic updates: Re-run script when hooks change
- ✅ Team discipline: Don't bypass hooks without good reason
- ✅ Use Claude Code for help when encountering issues

**Result:** Consistent, high-quality code in version control from all developers! 🚀

---

## Further Reading

- [CLAUDE.md](../../CLAUDE.md) - Full development guidelines
- [quality-checks.md](quality-checks.md) - Claude Code hooks guide
- [architecture.md](architecture.md) - Architecture documentation guide
- [Git Hooks Documentation](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
- [Pro Git Book - Hooks](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
