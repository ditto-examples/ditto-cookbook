Check and update third-party dependencies across all apps and tools in the Ditto Cookbook repository.

## Usage

```bash
/update-deps check              # Check for outdated dependencies (all platforms)
/update-deps check --json       # Check with JSON output (for CI/CD)
/update-deps update             # Update dependencies interactively
/update-deps update --all       # Update all dependencies automatically
/update-deps ditto              # Check Ditto SDK versions across projects
```

### Exit Codes (CI/CD Integration)

The command returns different exit codes for automated workflows:

- **Exit 0**: All dependencies up to date, or update completed successfully
- **Exit 1**: Outdated dependencies found (check mode), or update failed

### Environment Variables

The command detects CI environments automatically:

- `CI=true` - Detects CI environment
- `GITHUB_ACTIONS` - Detects GitHub Actions environment

## What This Command Does

This skill helps you keep third-party libraries and SDKs up to date across all applications and tools in the repository.

### Features

1. **Multi-Platform Discovery**: Automatically discovers apps and tools by platform:
   - Flutter (pubspec.yaml)
   - Node.js (package.json)
   - Python (requirements.txt)
   - iOS (Podfile)
   - Android (build.gradle / build.gradle.kts)

2. **Dependency Checking**: Uses appropriate package managers to check for outdated dependencies:
   - `flutter pub outdated` for Flutter apps
   - `npm outdated` for Node.js apps
   - `pip list --outdated` for Python tools
   - `pod outdated` for iOS apps
   - Gradle dependency checks for Android apps

3. **Ditto SDK Version Consistency** (HIGH PRIORITY):
   - Scans all projects for Ditto SDK references
   - Reports version mismatches across projects
   - Suggests unified upgrade paths
   - Provides links to Ditto SDK release notes and migration guides

4. **Update Modes**:
   - **check**: Non-destructive, reports outdated dependencies only
   - **update**: Interactive mode with user prompts for each update
   - **update --all**: Automatic update mode (updates all dependencies)
   - **ditto**: Special mode focused on Ditto SDK versions

5. **Safety Features**:
   - Parallel execution for efficiency
   - Color-coded output (green=up-to-date, yellow=minor updates, red=major updates)
   - Comprehensive error handling
   - Gracefully handles empty directories (ready for future apps)

## Examples

### Check all dependencies across the repository
```bash
/update-deps check
```

### Update dependencies interactively
```bash
/update-deps update
```

### Automatically update all dependencies
```bash
/update-deps update --all
```

### Check Ditto SDK versions specifically
```bash
/update-deps ditto
```

## What Happens After Updates

If dependencies are updated:
1. The skill will report which dependencies were updated
2. Documentation may be updated to reflect changes (if applicable)
3. You should run tests to verify compatibility: `./scripts/test-all.sh`

## Notes

- This is a **manual command** - it will not run automatically via git hooks
- The skill works with zero apps (gracefully handles empty directories)
- All platforms are supported (Flutter, Node.js, Python, iOS, Android)
- Ditto SDK version checking is a high-priority feature for this cookbook project
- Follow the project's testing standards (80%+ coverage target) after updates
