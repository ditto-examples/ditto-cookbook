# Version Management Overview

This project uses **automated version management** to ensure all contributors use consistent tool versions without reading documentation.

## Quick Start

```bash
# One command to set everything up
./.claude/scripts/setup/complete-setup.sh
```

That's it! Tool versions are installed and configured automatically.

---

## How It Works

### 1. Automatic Installation

Run the setup script and it:
- ✅ Detects your operating system
- ✅ Installs `asdf` version manager
- ✅ Installs correct versions of Flutter, Node.js, and Python
- ✅ Configures your shell automatically
- ✅ Sets up version verification

**No manual configuration needed.**

### 2. Automatic Version Switching

When you `cd` into this project:
- ✅ `asdf` reads [.tool-versions](.tool-versions)
- ✅ Automatically switches to project versions
- ✅ No commands to remember

### 3. Automatic Verification

Git Hooks check versions before commits:
- ✅ Warns if versions don't match
- ✅ Offers to fix automatically
- ✅ Ensures consistency across all developers

---

## File Structure

```
ditto-cookbook/
├── .tool-versions                           # Primary version configuration (Single Source of Truth)
│
├── .fvm/fvm_config.json                     # Flutter-specific (optional)
├── .nvmrc                                    # Node.js (for nvm users)
│
├── .claude/scripts/
│   ├── setup/
│   │   ├── complete-setup.sh                # All-in-one setup
│   │   └── setup-versions.sh                # Version setup only
│   └── checks/
│       └── version-check.sh                 # Version verification
│
└── docs/
    └── DEVELOPMENT.md                        # Detailed documentation
```

---

## Required Tool Versions

All tool versions are specified in [.tool-versions](.tool-versions):

| Tool    | Included With |
|---------|---------------|
| Flutter | Dart included |
| Node.js | npm included  |
| Python  | pip included  |

**See [.tool-versions](.tool-versions) for current version numbers.**

---

## Version Manager: asdf

**Why asdf?**
- Single tool for all languages (Flutter, Node.js, Python, etc.)
- Single file (`.tool-versions`) for all versions
- Automatic version switching per directory
- Cross-platform (macOS, Linux, Windows WSL)
- Industry standard for polyglot projects

**Alternative**: FVM is also configured for Flutter-specific workflows.

---

## Automation Features

### 1. Setup Script

[`.claude/scripts/setup/setup-versions.sh`](.claude/scripts/setup/setup-versions.sh)

**What it does:**
- Detects your OS (macOS, Linux, Windows)
- Installs asdf if not present
- Installs required asdf plugins (Flutter, Node.js, Python)
- Installs correct tool versions
- Configures FVM as alternative
- Creates `.nvmrc` for nvm users
- Updates shell configuration

**Manual intervention**: Only asks yes/no for asdf installation

### 2. Version Check Hook

[`.claude/scripts/checks/version-check.sh`](.claude/scripts/checks/version-check.sh)

**What it does:**
- Runs before every commit/push
- Checks if your tool versions match requirements
- Warns if mismatch detected
- Offers to fix automatically via `asdf install`

**Manual intervention**: Only if versions need fixing

### 3. Complete Setup

[`.claude/scripts/setup/complete-setup.sh`](.claude/scripts/setup/complete-setup.sh)

**What it does:**
- Runs version setup
- Installs Git Hooks
- Verifies Claude Code
- Configures MCP servers (optional)

**One command, full setup.**

---

## Usage Examples

### First-time Setup

```bash
# Clone and setup
git clone https://github.com/getditto/ditto-cookbook.git
cd ditto-cookbook
./.claude/scripts/setup/complete-setup.sh

# Restart terminal
source ~/.zshrc  # or source ~/.bashrc

# Verify (should match .tool-versions)
flutter --version
node --version
```

### Daily Development

```bash
# Just cd into project - versions switch automatically
cd ditto-cookbook

# Tools use correct versions automatically
flutter run
npm install
```

### Version Mismatch Detected

```bash
# Git hook detects mismatch:
git commit -m "Update feature"

# Output:
# ⚠ Flutter version mismatch
#   Expected: (version from .tool-versions)
#   Actual:   (your current version)
#
# asdf is available. Fixing versions automatically...
# ✓ Versions fixed automatically!
```

### Updating Project Versions

**Option 1: Use the automated update script** (recommended)

```bash
# Update Flutter
./.claude/scripts/maintenance/update-versions.sh flutter 3.40.0

# Update Node.js
./.claude/scripts/maintenance/update-versions.sh nodejs 25.0.0

# Update Python
./.claude/scripts/maintenance/update-versions.sh python 3.15.0

# Then install and commit
asdf install
git add .tool-versions .fvm .nvmrc
git commit -m "Update Flutter to 3.40.0"
git push
```

**Option 2: Manual update** (only 3 files)

```bash
# 1. Update .tool-versions
echo "flutter 3.40.0" > .tool-versions

# 2. Update .fvm/fvm_config.json if Flutter changed
# 3. Update .nvmrc if Node.js changed

# 4. Install new versions
asdf install

# 5. Verify
flutter --version  # Should match .tool-versions

# 6. Commit and push
git add .tool-versions .fvm/fvm_config.json .nvmrc
git commit -m "Update Flutter to 3.40.0"
git push
```

---

## Per-Developer Configuration

**None required!** Everything is automatic.

But if needed:
- asdf configuration: `~/.asdfrc`
- Shell integration: `~/.zshrc` or `~/.bashrc`
- IDE: Auto-detects via asdf or FVM

---

## CI/CD Integration

GitHub Actions uses the same versions:

```yaml
- name: Install asdf
  uses: asdf-vm/actions/setup@v3

- name: Install project versions
  run: asdf install
```

No version hardcoding in CI - always uses [.tool-versions](.tool-versions).

---

## Troubleshooting

### "asdf: command not found"

Your shell isn't configured. The setup script handles this, but if needed:

```bash
# For zsh
echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.zshrc
source ~/.zshrc

# For bash
echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.bash_profile
source ~/.bash_profile
```

### "Wrong version detected"

```bash
cd <project-root>
asdf install
```

### "Git Hook failing"

```bash
# Reinstall hooks
./.claude/scripts/setup/setup-git-hooks.sh
```

---

## Platform Support

| Platform       | asdf | FVM | Status |
|----------------|------|-----|--------|
| macOS          | ✅   | ✅  | Full   |
| Linux          | ✅   | ✅  | Full   |
| Windows (WSL2) | ✅   | ✅  | Full   |
| Windows Native | ❌   | ✅  | Manual |

**Windows users**: Use WSL2 for best experience, or manually install tools.

---

## Philosophy

**Developers should code, not read documentation about tool versions.**

Our approach:
1. **Automate everything possible** - One script, full setup
2. **Verify automatically** - Git Hooks check versions
3. **Fix automatically** - Offer one-command fixes
4. **Document minimally** - Only what automation can't handle

Result: **Zero mental overhead for version management.**

---

## Documentation

- **This file**: High-level overview
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**: Detailed setup guide
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Contributor workflow
- **[CLAUDE.md](CLAUDE.md)**: Development guidelines

---

## Maintenance

### Adding New Tools

1. Update [.tool-versions](.tool-versions):
   ```
   flutter 3.38.5
   nodejs 24.12.0
   python 3.14.2
   ruby 3.3.0      # New tool
   ```

2. Update [`.claude/scripts/setup/setup-versions.sh`](.claude/scripts/setup/setup-versions.sh):
   - Add plugin installation
   - Update verification section

3. Update [`.claude/scripts/checks/version-check.sh`](.claude/scripts/checks/version-check.sh):
   - Add version check logic

4. Test and commit

### Updating Versions

**Only 3 files need updating** (no documentation changes required):

1. Update [.tool-versions](.tool-versions) - Primary version source
2. Update [.fvm/fvm_config.json](.fvm/fvm_config.json) - If Flutter changed
3. Update [.nvmrc](.nvmrc) - If Node.js changed
4. Test locally: `asdf install && flutter --version`
5. Create PR with clear communication
6. Git Hooks notify all developers automatically

---

## Summary

✅ **One command**: `./.claude/scripts/setup/complete-setup.sh`
✅ **Automatic switching**: Versions change per directory
✅ **Automatic verification**: Git Hooks check before commits
✅ **Automatic fixes**: One command to resolve mismatches
✅ **Zero documentation reading**: Everything is automated

**Version management that just works.**
