# Development Environment Setup

## Automated Setup (Recommended)

The fastest way to get started is to use our automated setup script:

```bash
# Run from project root
./.claude/scripts/setup/complete-setup.sh
```

This single script automatically:
- ✅ Installs and configures correct tool versions
- ✅ Sets up Git Hooks for quality checks
- ✅ Verifies Claude Code installation
- ✅ Configures MCP servers (optional)

**Time required**: ~5 minutes (including tool installation)

---

## What Gets Installed

### 1. Tool Version Management

The setup installs **asdf** to automatically manage tool versions.

**Required tools** (versions specified in [.tool-versions](../.tool-versions)):
- **Flutter** (includes Dart)
- **Node.js**
- **Python**

**Why asdf?**
- Automatic version switching per directory
- Single configuration file ([.tool-versions](../.tool-versions))
- Works across all platforms (macOS, Linux, Windows WSL)
- Manages all languages in one tool

**Alternative**: FVM (Flutter Version Management) is also configured as a Flutter-specific option.

### 2. Git Hooks

Automated quality checks run before commits/pushes: security, language, code analysis, documentation validation.

**Full guide**: [../.claude/guides/git-hooks.md](../.claude/guides/git-hooks.md)

---

## Manual Setup (If Needed)

If you prefer manual setup or need to troubleshoot:

### Install Tool Versions Only

```bash
./.claude/scripts/setup/setup-versions.sh
```

### Verify Your Setup

```bash
# Check installed versions match .tool-versions
flutter --version
node --version
python --version

# Run version check manually
./.claude/scripts/checks/version-check.sh
```

### Update Tool Versions

When project versions change:

1. Versions are updated in [.tool-versions](.tool-versions)
2. Run: `asdf install` to install new versions
3. Restart your terminal

---

## How Version Management Works

### Automatic Version Switching

When you `cd` into this project directory:
- asdf reads [.tool-versions](.tool-versions)
- Automatically switches to project-specified versions
- No manual intervention needed

### Per-Project Isolation

Each project can have different tool versions:
- ✅ Each project has its own `.tool-versions` file
- ✅ Versions switch automatically when changing directories
- ✅ No manual intervention needed

### Version Verification

Git Hooks verify versions match [.tool-versions](../.tool-versions) before commit/push.

If versions don't match:
```bash
# Hook warns and offers to fix:
# ⚠ Flutter version mismatch
#   Expected: (version from .tool-versions)
#   Actual:   (your current version)
#
# Fix automatically? (y/n)
```

---

## Platform-Specific Notes

### macOS
- Uses Homebrew for asdf installation
- Works with both zsh and bash shells
- Automatic PATH configuration

### Linux
- Direct git clone installation
- Supports bash and zsh
- Manual PATH configuration in shell profile

### Windows
- Use WSL2 (Windows Subsystem for Linux)
- Or manually install tools:
  - Flutter: https://docs.flutter.dev/get-started/install/windows
  - Node.js: https://nodejs.org/
  - FVM: `dart pub global activate fvm`

---

## IDE Configuration

### VS Code

asdf works automatically - no configuration needed.

For FVM (Flutter-specific):
1. Install Flutter extension
2. Extension auto-detects `.fvm/fvm_config.json`
3. Uses correct Flutter version automatically

### Android Studio / IntelliJ

asdf works automatically - no configuration needed.

For FVM (Flutter-specific):
1. Set Flutter SDK path to: `<project>/.fvm/flutter_sdk`
2. Restart IDE

---

## Troubleshooting

### "asdf: command not found"

Your shell profile isn't configured:

```bash
# For zsh (macOS default)
echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.zshrc
source ~/.zshrc

# For bash
echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.bash_profile
source ~/.bash_profile
```

### "Wrong Flutter version detected"

Reinstall project versions:

```bash
cd <project-root>
asdf install
```

### "Git Hooks not working"

Reinstall hooks:

```bash
./.claude/scripts/setup/setup-git-hooks.sh
```

### "Version check fails during commit"

The hook detected version mismatch. Options:

1. **Fix automatically** (recommended):
   ```bash
   # Hook will offer to fix - just answer 'y'
   ```

2. **Fix manually**:
   ```bash
   cd <project-root>
   asdf install
   ```

3. **Bypass** (not recommended):
   ```bash
   git commit --no-verify
   ```

---

## CI/CD Integration

GitHub Actions automatically uses versions from [.tool-versions](.tool-versions):

```yaml
- name: Install asdf
  uses: asdf-vm/actions/setup@v3

- name: Install tools
  run: asdf install
```

All CI checks use the same versions as local development.

---

## Updating Project Versions

When updating tool versions for all contributors, you only need to update **3 files**:

1. **[.tool-versions](../.tool-versions)** - Primary version source
2. **[.fvm/fvm_config.json](../.fvm/fvm_config.json)** - For Flutter FVM
3. **[.nvmrc](../.nvmrc)** - For Node.js nvm

**Option 1: Use automated script** (recommended)

```bash
# Update specific tool
./.claude/scripts/maintenance/update-versions.sh flutter 3.40.0
./.claude/scripts/maintenance/update-versions.sh nodejs 25.0.0

# Install and commit
asdf install
git add .tool-versions .fvm .nvmrc
git commit -m "Update tool versions"
git push
```

**Option 2: Update manually**

```bash
# 1. Edit .tool-versions, .fvm/fvm_config.json, .nvmrc
# 2. Install new versions
asdf install

# 3. Verify
flutter --version
node --version
python --version

# 4. Commit
git add .tool-versions .fvm .nvmrc
git commit -m "Update tool versions"
git push
```

**Note**: No documentation updates needed! All docs reference `.tool-versions` automatically.

---

## Additional Resources

- **asdf Documentation**: https://asdf-vm.com/
- **FVM Documentation**: https://fvm.app/
- **Git Hooks Guide**: [../.claude/guides/git-hooks.md](../.claude/guides/git-hooks.md)
- **Project Guidelines**: [../CLAUDE.md](../CLAUDE.md)

---

## Quick Reference

```bash
# Complete setup (first time)
./.claude/scripts/setup/complete-setup.sh

# Install/update versions only
./.claude/scripts/setup/setup-versions.sh

# Check versions manually
./.claude/scripts/checks/version-check.sh

# Verify setup
./.claude/scripts/setup/verify-setup.sh

# Install all versions from .tool-versions
asdf install

# List all available versions
asdf list all flutter
asdf list all nodejs

# Use FVM (Flutter alternative)
fvm install
fvm use
fvm flutter run
```

---

**Questions?** See [CONTRIBUTING.md](../CONTRIBUTING.md) or open a [GitHub Discussion](https://github.com/getditto/ditto-cookbook/discussions).
