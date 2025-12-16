# Dependency Management Guide

This guide explains how to manage third-party dependencies across all applications and tools in the Ditto Cookbook repository.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Command Reference](#command-reference)
4. [Platform Support](#platform-support)
5. [Ditto SDK Management](#ditto-sdk-management)
6. [Workflow Best Practices](#workflow-best-practices)
7. [Troubleshooting](#troubleshooting)
8. [Integration with Development Workflow](#integration-with-development-workflow)

---

## Overview

The Ditto Cookbook provides a unified dependency management system that:

- **Auto-discovers** apps and tools by platform
- **Checks** for outdated dependencies across all platforms
- **Updates** dependencies automatically or interactively
- **Monitors Ditto SDK versions** for consistency (HIGH PRIORITY)
- **Works seamlessly** with zero apps (ready for future growth)

### Supported Platforms

- Flutter (Dart)
- Node.js (npm, yarn, pnpm)
- Python (pip)
- iOS (CocoaPods)
- Android (Gradle)

### Key Features

- **Multi-platform discovery**: Automatically finds all apps/tools
- **Safe by default**: Check mode is non-destructive
- **Flexible updates**: Interactive or automatic modes
- **Ditto SDK focus**: Special tracking for Ditto SDK versions
- **Parallel execution**: Efficient checking of multiple projects

---

## Quick Start

### Check all dependencies

```bash
/update-deps check
```

This will scan all apps and tools, report outdated dependencies, and exit without making changes.

### Update dependencies interactively

```bash
/update-deps update
```

This will prompt you for each project whether to update its dependencies.

### Update all dependencies automatically

```bash
/update-deps update --all
```

This will update all dependencies across all projects without prompting.

### Check Ditto SDK versions

```bash
/update-deps ditto
```

This will scan for Ditto SDK references and report version consistency across projects (HIGH PRIORITY feature).

---

## Command Reference

### `/update-deps check`

**Purpose**: Check for outdated dependencies (non-destructive)

**Behavior**:
- Discovers all apps and tools
- Runs platform-specific check commands
- Reports outdated dependencies
- Does NOT modify any files

**Exit codes**:
- 0: All dependencies are up to date or check completed successfully
- 1: Error occurred during check

**Example output**:
```
ℹ Found 3 project(s) with dependencies:

  • my-flutter-app (flutter)
  • my-web-app (node)
  • my-tool (python)

Checking dependencies...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking my-flutter-app (flutter)...

✓ my-flutter-app is up to date

Checking my-web-app (node)...

⚠ my-web-app has outdated dependencies

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ Some dependencies are outdated. Run './update-dependencies.sh update' to update them.
```

---

### `/update-deps update`

**Purpose**: Update dependencies interactively

**Behavior**:
- Discovers all apps and tools
- Prompts for each project whether to update
- Updates dependencies if confirmed
- Shows summary at the end

**Example interaction**:
```
Update my-flutter-app? (y/N): y
✓ my-flutter-app updated successfully

Update my-web-app? (y/N): n
ℹ Skipped my-web-app
```

---

### `/update-deps update --all`

**Purpose**: Update all dependencies automatically

**Behavior**:
- Discovers all apps and tools
- Updates ALL dependencies without prompting
- Reports success/failure for each project
- Shows summary at the end

**Use cases**:
- CI/CD pipelines
- Batch updates
- When you trust all updates

**Warning**: This updates ALL dependencies. Review changes before committing.

---

### `/update-deps ditto`

**Purpose**: Check Ditto SDK versions across all projects (HIGH PRIORITY)

**Behavior**:
- Scans all dependency files for Ditto SDK references
- Reports versions by platform
- Checks for version consistency
- Provides upgrade recommendations
- Links to Ditto documentation

**Example output**:
```
ℹ Ditto SDK Version Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ Platform: flutter

  • task-app: 4.12.4 (latest)
  • chat-app: 4.12.3 (outdated)

⚠ Version Inconsistency Detected!

Found 2 different Ditto SDK versions across projects.

ℹ Recommendation:
  • Consider standardizing on Ditto SDK v4.12.4 (stable)
  • Or use v5.0.0-preview.3 (preview) for all projects
```

---

## Platform Support

### Flutter (Dart)

**Detection**: Presence of `pubspec.yaml`

**Check command**: `flutter pub outdated`

**Update command**: `flutter pub upgrade`

**Dependency file**: `pubspec.yaml`

**Example**:
```yaml
dependencies:
  ditto_flutter: ^4.12.4
  http: ^1.2.0
```

---

### Node.js (npm/yarn/pnpm)

**Detection**: Presence of `package.json`

**Package manager auto-detection**:
- `pnpm-lock.yaml` → pnpm
- `yarn.lock` → yarn
- Otherwise → npm

**Check commands**:
- npm: `npm outdated`
- yarn: `yarn outdated`
- pnpm: `pnpm outdated`

**Update commands**:
- npm: `npm update`
- yarn: `yarn upgrade`
- pnpm: `pnpm update`

**Dependency file**: `package.json`

**Example**:
```json
{
  "dependencies": {
    "@dittolive/ditto": "^4.12.4",
    "react": "^18.2.0"
  }
}
```

---

### Python (pip)

**Detection**: Presence of `requirements.txt`

**Check command**: `pip list --outdated`

**Update strategy**:
1. Upgrade each package: `pip install --upgrade <package>`
2. Regenerate `requirements.txt` with new versions

**Dependency file**: `requirements.txt`

**Example**:
```
ditto==4.12.4
requests==2.31.0
```

---

### iOS (CocoaPods)

**Detection**: Presence of `Podfile`

**Check command**: `pod outdated`

**Update command**: `pod update`

**Dependency file**: `Podfile`

**Requirements**: macOS only

**Example**:
```ruby
pod 'Ditto', '~> 4.12.4'
pod 'Alamofire', '~> 5.8'
```

---

### Android (Gradle)

**Detection**: Presence of `build.gradle` or `build.gradle.kts`

**Check strategy**:
- Looks for `dependencyUpdates` task (if gradle-versions-plugin is installed)
- Falls back to `dependencies` task (manual review required)

**Update strategy**: Manual (Gradle doesn't have automatic updates)

**Recommendation**: Use [Gradle Versions Plugin](https://github.com/ben-manes/gradle-versions-plugin)

**Dependency file**: `build.gradle` or `build.gradle.kts`

**Example (build.gradle)**:
```gradle
dependencies {
    implementation 'live.ditto:ditto:4.12.4'
    implementation 'androidx.core:core-ktx:1.12.0'
}
```

---

## Ditto SDK Management

### Why Ditto SDK Version Consistency Matters

The Ditto Cookbook is a showcase repository for Ditto SDK examples. Version consistency across projects is **critical** because:

1. **User Confusion**: Inconsistent versions confuse users learning from examples
2. **Compatibility**: Different versions may have different APIs
3. **Testing**: Ensures all examples work with the same SDK version
4. **Documentation**: Simplifies documentation and troubleshooting

### Checking Ditto SDK Versions

Use the dedicated Ditto SDK checker:

```bash
/update-deps ditto
```

This will:
- Scan all projects for Ditto SDK references
- Report versions by platform
- Detect inconsistencies
- Provide upgrade recommendations
- Link to Ditto documentation

### Ditto SDK Version Strategy

**Stable Release (Recommended for Production)**:
- SDK v4.12.x (latest: 4.12.4)
- Full production support
- All platforms: Flutter, iOS, Android, JavaScript, Python

**Preview Release (Public Preview)**:
- SDK v5.0.0-preview.x (latest: 5.0.0-preview.3)
- Subject to changes
- Limited platform support

### Upgrading Ditto SDK

**Step 1**: Check current versions
```bash
/update-deps ditto
```

**Step 2**: Review Ditto release notes
- [v4 Release Notes](https://docs.ditto.live/sdk/latest/release-notes)
- [v5 Preview Documentation](https://docs.ditto.live/sdk/v5)

**Step 3**: Update dependency files

For Flutter (`pubspec.yaml`):
```yaml
dependencies:
  ditto_flutter: ^4.12.4
```

For Node.js (`package.json`):
```json
{
  "dependencies": {
    "@dittolive/ditto": "^4.12.4"
  }
}
```

For iOS (`Podfile`):
```ruby
pod 'Ditto', '~> 4.12.4'
```

For Android (`build.gradle`):
```gradle
implementation 'live.ditto:ditto:4.12.4'
```

For Python (`requirements.txt`):
```
ditto==4.12.4
```

**Step 4**: Run updates
```bash
/update-deps update
```

**Step 5**: Test all applications
```bash
./scripts/test-all.sh
```

**Step 6**: Verify consistency
```bash
/update-deps ditto
```

### Version Compatibility

From Ditto's documentation:

- **v4 can sync with v3 or v5** (but not both simultaneously)
- **Upgrade path**: Ensure all devices are on v4 before deploying v5
- **Ditto Server**: v4.0 and higher are supported

---

## Workflow Best Practices

### Regular Dependency Checks

Run dependency checks regularly (e.g., weekly or monthly):

```bash
/update-deps check
```

### Before Major Releases

1. Check all dependencies:
   ```bash
   /update-deps check
   ```

2. Check Ditto SDK consistency:
   ```bash
   /update-deps ditto
   ```

3. Update if needed:
   ```bash
   /update-deps update
   ```

4. Run tests:
   ```bash
   ./scripts/test-all.sh
   ```

5. Review and commit changes

### After Adding New Apps

When you add a new app:

1. Check if it uses the correct Ditto SDK version:
   ```bash
   /update-deps ditto
   ```

2. Update if inconsistent:
   ```bash
   /update-deps update
   ```

### Version Pinning

For **showcase code** (like this repository), consider:

- **Pinning exact versions** for reproducibility
- **Using version ranges** for flexibility

Example (Flutter):
```yaml
# Pinned (exact version)
dependencies:
  ditto_flutter: 4.12.4

# Range (allows patch updates)
dependencies:
  ditto_flutter: ^4.12.4
```

---

## CI/CD Integration

### GitHub Actions Integration

The dependency management system is designed for CI/CD integration with proper exit codes and JSON output.

#### Exit Codes

- `exit 0` - All dependencies up to date, or update successful
- `exit 1` - Outdated dependencies found (check mode), or update failed

#### JSON Output

Use `--json` flag for machine-readable output:

```bash
./.claude/scripts/maintenance/update-dependencies.sh check --json
```

Output format:
```json
{
  "status": "checking",
  "projects": [
    {"name": "my-app", "platform": "flutter", "status": "up-to-date"},
    {"name": "my-tool", "platform": "python", "status": "outdated"}
  ],
  "summary": {
    "total": 2,
    "outdated": 1,
    "up_to_date": 1
  },
  "ci_environment": true
}
```

#### Environment Detection

The system automatically detects CI environments:

- `CI=true` - Generic CI environment
- `GITHUB_ACTIONS` - GitHub Actions specifically

#### Example GitHub Actions Workflow

```yaml
name: Check Dependencies

on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday
  workflow_dispatch:

jobs:
  check-deps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.38.5'

      - name: Check dependencies
        id: check
        run: |
          ./.claude/scripts/maintenance/update-dependencies.sh check --json > deps.json
          echo "result=$(cat deps.json)" >> $GITHUB_OUTPUT
        continue-on-error: true

      - name: Check Ditto SDK versions
        run: ./.claude/scripts/maintenance/check-ditto-versions.sh

      - name: Comment on outdated dependencies
        if: failure()
        run: |
          echo "Outdated dependencies found!"
          cat deps.json
```

#### Future: Automated PR Creation

For automated PR creation (future enhancement), consider:

1. Use Dependabot-style workflow
2. Create branch with updates
3. Run tests automatically
4. Create PR with formatted changelog
5. Auto-merge if tests pass (optional)

---

## Troubleshooting

### "No projects with dependencies found"

**Cause**: No apps or tools exist yet, or dependency files are missing.

**Solution**: This is expected for empty repositories. The system is ready for future apps.

### "Flutter is not installed or not in PATH"

**Cause**: Flutter SDK is not installed or not in system PATH.

**Solution**:
1. Install Flutter: https://flutter.dev/docs/get-started/install
2. Ensure Flutter is in PATH
3. Verify: `flutter --version`

### "CocoaPods is not installed"

**Cause**: CocoaPods is not installed (macOS only).

**Solution**:
```bash
sudo gem install cocoapods
```

### "gradlew not found"

**Cause**: Gradle wrapper is not set up in Android project.

**Solution**:
1. Run `gradle wrapper` in the Android project directory
2. Or install Gradle system-wide

### "npm outdated exits with 1"

**Note**: `npm outdated` exits with code 1 when outdated packages exist. This is **expected behavior**, not an error.

### Version Consistency Issues

**Problem**: Different Ditto SDK versions across projects.

**Solution**:
1. Run `/update-deps ditto` to see all versions
2. Choose a target version (e.g., 4.12.4)
3. Manually update all dependency files
4. Run `/update-deps update` to install
5. Run `/update-deps ditto` to verify

---

## Integration with Development Workflow

### Manual Command Only

The dependency management system is **manual by default**. It will NOT run automatically via git hooks.

**Reason**: Dependency updates can break code, so explicit user action is required.

### Testing After Updates

Always run tests after updating dependencies:

```bash
./scripts/test-all.sh
```

This runs tests for all applications in parallel with fail-fast behavior.

### Documentation Updates

If dependency updates require code changes, update:

1. **ARCHITECTURE.md** files for affected apps
2. **README.md** files with new setup instructions
3. **CLAUDE.md** if new best practices emerge

### Commit Messages

When committing dependency updates, use clear messages:

```bash
# Good commit messages
git commit -m "Update Ditto SDK to v4.12.4 across all projects"
git commit -m "Update Flutter dependencies for task-app"
git commit -m "Upgrade Node.js packages in web-dashboard"

# Bad commit messages
git commit -m "Update deps"
git commit -m "WIP"
```

### Pull Request Template

When creating PRs with dependency updates:

1. **Title**: Clear indication of what was updated
2. **Description**:
   - List of updated packages
   - Reason for update (security, features, bug fixes)
   - Breaking changes (if any)
   - Testing performed
3. **Checklist**:
   - [ ] Dependencies updated
   - [ ] Tests pass
   - [ ] Documentation updated
   - [ ] Ditto SDK version consistent (if applicable)

---

## Advanced Usage

### Scripting with update-dependencies.sh

The underlying script can be called directly:

```bash
# From project root
./.claude/scripts/maintenance/update-dependencies.sh check
./.claude/scripts/maintenance/update-dependencies.sh update
./.claude/scripts/maintenance/update-dependencies.sh update --all
./.claude/scripts/maintenance/update-dependencies.sh ditto

# Or with absolute path
/path/to/ditto-cookbook/.claude/scripts/maintenance/update-dependencies.sh check
```

### Platform-Specific Dependency Management

You can call platform-specific managers directly:

```bash
# Flutter
./.claude/scripts/maintenance/dependency-managers/flutter-deps.sh check /path/to/flutter/app
./.claude/scripts/maintenance/dependency-managers/flutter-deps.sh update /path/to/flutter/app

# Node.js
./.claude/scripts/maintenance/dependency-managers/node-deps.sh check /path/to/node/app

# Python
./.claude/scripts/maintenance/dependency-managers/python-deps.sh check /path/to/python/tool

# iOS
./.claude/scripts/maintenance/dependency-managers/ios-deps.sh check /path/to/ios/app

# Android
./.claude/scripts/maintenance/dependency-managers/android-deps.sh check /path/to/android/app
```

### CI/CD Integration

While the system is manual by default, you can integrate it into CI/CD:

```yaml
# Example GitHub Actions workflow
name: Check Dependencies

on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday
  workflow_dispatch:

jobs:
  check-deps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check dependencies
        run: ./.claude/scripts/maintenance/update-dependencies.sh check
      - name: Check Ditto SDK versions
        run: ./.claude/scripts/maintenance/check-ditto-versions.sh
```

---

## Resources

### Official Documentation

- [Ditto SDK Documentation](https://docs.ditto.live/)
- [Ditto SDK v4 Release Notes](https://docs.ditto.live/sdk/latest/release-notes)
- [Ditto SDK v5 Preview](https://docs.ditto.live/sdk/v5)

### Package Manager Documentation

- [Flutter pub](https://dart.dev/tools/pub/cmd)
- [npm](https://docs.npmjs.com/)
- [yarn](https://yarnpkg.com/)
- [pnpm](https://pnpm.io/)
- [pip](https://pip.pypa.io/)
- [CocoaPods](https://cocoapods.org/)
- [Gradle](https://gradle.org/)

### Related Guides

- [Git Hooks Guide](git-hooks.md) - Quality checks and automation
- [Architecture Guide](architecture.md) - Project structure
- [Quality Checks](quality-checks.md) - Security and language checks

---

## Changelog

### 2025-12-16 (Initial Release)

- Created dependency management system
- Added support for Flutter, Node.js, Python, iOS, Android
- Implemented Ditto SDK version checker (HIGH PRIORITY)
- Comprehensive documentation
- Manual command-only (no git hook integration)

---

## Contributing

If you find issues or have suggestions for the dependency management system:

1. Check existing issues: https://github.com/anthropics/ditto-cookbook/issues
2. Create a new issue with detailed description
3. Follow the project's contribution guidelines

---

**Last Updated**: 2025-12-16
