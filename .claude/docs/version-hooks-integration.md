# Version Check Integration with Git Hooks

## Overview

Version checking has been integrated into Git Hooks to automatically verify and fix tool version mismatches before commits and pushes.

## How It Works

### Pre-Commit Hook Flow

```
git commit -m "message"
   ↓
[0/2] Checking tool versions...
   ↓
✓ Flutter version correct: 3.38.5
✓ Node.js version correct: 24.12.0
✓ Python version correct: 3.14.2
   ↓
[1/2] Running security checks...
[2/2] Running language checks...
   ↓
✅ Pre-commit checks passed!
```

### Pre-Push Hook Flow

```
git push
   ↓
[0/4] Checking tool versions...
   ↓
(Version verification + automatic fixes if needed)
   ↓
[1/4] Running security checks...
[2/4] Running language checks...
[3/4] Running code analysis...
[4/4] Checking architecture documentation...
   ↓
✅ Pre-push checks passed!
```

## Automatic Version Fixing

When a version mismatch is detected:

```bash
git commit -m "Update feature"

[0/2] Checking tool versions...
⚠ Flutter version mismatch
  Expected: 3.38.5
  Actual:   3.40.0

asdf is available. Fixing versions automatically...
✓ Versions fixed automatically!
```

The hook:
1. Detects version mismatch
2. Automatically runs `asdf install`
3. Installs correct versions
4. Continues with commit/push

## Files Modified

### 1. Git Hooks (Installed)

**`.git/hooks/pre-commit`**
- Added version check as step [0/2]
- Non-blocking (always succeeds with auto-fix)

**`.git/hooks/pre-push`**
- Added version check as step [0/4]
- Non-blocking (always succeeds with auto-fix)

### 2. Hook Installation Script

**`.claude/scripts/setup/setup-git-hooks.sh`**
- Updated pre-commit template to include version check
- Updated pre-push template to include version check
- Enhanced summary to mention version management

## Developer Experience Examples

### Scenario 1: Versions Correct (Silent Success)

```bash
git commit -m "Add feature"

🔒 Running Pre-Commit Quality Checks...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[0/2] Checking tool versions...
✓ Flutter version correct: 3.38.5
✓ Node.js version correct: 24.12.0
✓ Python version correct: 3.14.2

[1/2] Running security checks...
✓ Security check passed
[2/2] Running language checks...
✓ Language check passed

✅ Pre-commit checks passed!
```

### Scenario 2: Version Mismatch (Auto-Fixed)

```bash
git commit -m "Add feature"

🔒 Running Pre-Commit Quality Checks...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[0/2] Checking tool versions...
⚠ Flutter version mismatch
  Expected: 3.38.5
  Actual:   3.40.0

asdf is available. Fixing versions automatically...
[Installing Flutter 3.38.5...]
✓ Versions fixed automatically!

Please restart your terminal: source ~/.zshrc

[1/2] Running security checks...
✓ Security check passed
[2/2] Running language checks...
✓ Language check passed

✅ Pre-commit checks passed!
```

### Scenario 3: asdf Not Available (Manual Fix Required)

```bash
git commit -m "Add feature"

🔒 Running Pre-Commit Quality Checks...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[0/2] Checking tool versions...
⚠ Flutter version mismatch
  Expected: 3.38.5
  Actual:   3.40.0

✗ asdf is not installed. Cannot fix versions automatically.

To fix this issue, run:
  ./.claude/scripts/setup/setup-versions.sh

[Commit blocked]
```

## Key Features

### Non-Blocking Design

Version checks are **non-blocking** when auto-fix succeeds:
- ✅ Versions match → Silent success
- ✅ Mismatch detected → Auto-fix → Success
- ❌ Auto-fix fails → Block with clear instructions

### Zero Configuration

No setup required by developers:
- Hooks automatically installed via setup script
- Version check included by default
- Works immediately after setup

### Seamless Integration

Fits naturally into Git workflow:
- Same UX as other quality checks
- Clear step numbering ([0/2], [1/2], etc.)
- Consistent output formatting

## Testing

### Test Hooks Manually

```bash
# Test pre-commit hook
git commit --allow-empty -m "Test commit"

# Test pre-push hook
git push --dry-run
```

### Test Version Mismatch

```bash
# Temporarily use wrong version
asdf local flutter 3.27.0

# Try to commit (version check will detect and fix)
git commit --allow-empty -m "Test mismatch"

# Verify auto-fix worked
flutter --version  # Should show 3.38.5
```

### Run Version Check Directly

```bash
# Run version check script manually
./.claude/scripts/checks/version-check.sh
```

## Maintenance

### Updating Tool Versions

When project versions change:

1. Update `.tool-versions`:
   ```
   flutter 3.40.0  # Updated
   nodejs 24.12.0
   python 3.14.2
   ```

2. Update `.fvm/fvm_config.json` (if Flutter):
   ```json
   {
     "flutterSdkVersion": "3.40.0"
   }
   ```

3. Commit changes:
   ```bash
   git add .tool-versions .fvm/fvm_config.json
   git commit -m "Update Flutter to 3.27.0"
   git push
   ```

4. All developers are notified automatically on next pull

### Reinstalling Hooks

If hooks need updates:

```bash
./.claude/scripts/setup/setup-git-hooks.sh
```

This reinstalls all hooks with latest templates.

## Troubleshooting

### Hook Not Running

```bash
# Verify hook exists
ls -la .git/hooks/pre-commit

# Make executable
chmod +x .git/hooks/pre-commit

# Reinstall
./.claude/scripts/setup/setup-git-hooks.sh
```

### Version Check Script Missing

```bash
# Verify script exists
ls -la .claude/scripts/checks/version-check.sh

# Restore from repository
git checkout HEAD -- .claude/scripts/checks/version-check.sh
chmod +x .claude/scripts/checks/version-check.sh
```

### asdf Not Found in Hook

Ensure asdf is in your shell profile:

```bash
# For Homebrew (macOS)
echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.zshrc

# For git installation
echo '. $HOME/.asdf/asdf.sh' >> ~/.zshrc

# Reload
source ~/.zshrc
```

## Benefits

### For Developers

✅ **Zero manual effort** - Version checks happen automatically
✅ **Auto-fixing** - Mismatches resolved without intervention
✅ **Clear feedback** - Know immediately if versions are wrong
✅ **No workflow disruption** - Silent when everything is correct
✅ **Helpful guidance** - Clear instructions when manual fix needed

### For Project

✅ **Version consistency** - All contributors use correct versions
✅ **Reduced errors** - Catch version issues before they cause bugs
✅ **Better CI/CD** - No version-related failures in pipelines
✅ **Automated enforcement** - No reliance on documentation
✅ **Smooth onboarding** - New contributors guided automatically

## Architecture

```
┌─────────────────────────────────────────┐
│     Developer: git commit               │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│  Git Hook: .git/hooks/pre-commit        │
│  [Runs automatically]                   │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│  Version Check Script                   │
│  .claude/scripts/checks/version-check.sh│
└────────────────┬────────────────────────┘
                 ↓
         ┌───────┴────────┐
         │                │
    ✓ Match         ✗ Mismatch
         │                │
         │                ↓
         │    ┌────────────────────┐
         │    │ asdf available?    │
         │    └─────┬───────┬──────┘
         │          │       │
         │         Yes     No
         │          │       │
         │          ↓       ↓
         │    Auto-fix   Block &
         │    Success    Show help
         │          │       │
         └──────────┴───────┘
                    ↓
            Continue commit
```

## Related Documentation

- [Version Management Overview](../../VERSION_MANAGEMENT.md) - Full version management documentation
- [Development Setup](../../docs/DEVELOPMENT.md) - Complete setup guide
- [Git Hooks Guide](../guides/git-hooks.md) - All Git Hooks documentation
- [Version Check Script](../scripts/checks/version-check.sh) - Implementation details
- [Setup Scripts](../scripts/setup/) - All setup automation

## Summary

Version checking is now **fully integrated** into Git Hooks:

1. ✅ **Automatic** - Runs on every commit/push
2. ✅ **Self-healing** - Auto-fixes mismatches via asdf
3. ✅ **Non-blocking** - Silent success when versions correct
4. ✅ **Zero setup** - Works immediately after complete-setup.sh
5. ✅ **Clear guidance** - Helpful messages when manual fix needed

**Result**: Developers never worry about version management - it just works!
