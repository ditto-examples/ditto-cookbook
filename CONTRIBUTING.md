# Contributing to Ditto Cookbook

Thank you for your interest in contributing to the Ditto Cookbook! This guide will help you get started with development and ensure your contributions meet our quality standards.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Development Guidelines](#development-guidelines)
- [Development Workflow](#development-workflow)
- [Quality Standards](#quality-standards)
- [Automated Quality Checks](#automated-quality-checks)
- [Creating a New Example](#creating-a-new-example)
- [Submission Guidelines](#submission-guidelines)
- [Code Review Process](#code-review-process)

## Getting Started

### Prerequisites

Before you begin, ensure you have:

- **Git**: For version control
- **Claude Code**: Required for AI-assisted development with access to Ditto documentation
- **Tool versions**: Automatically managed (see Development Setup below)

### Development Setup

#### 1. Clone the Repository

```bash
git clone https://github.com/getditto/ditto-cookbook.git
cd ditto-cookbook
```

#### 2. Automated Setup (Recommended)

**Run the complete setup script** to configure everything automatically:

```bash
./.claude/scripts/setup/complete-setup.sh
```

This single command:
- ✅ Installs correct tool versions (Flutter, Node.js, Python)
- ✅ Sets up Git Hooks for quality checks
- ✅ Verifies Claude Code installation
- ✅ Configures MCP servers (optional)

**Time required**: ~5 minutes

**No need to read documentation** - everything is automated!

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for detailed information.

#### 3. Manual Setup (If Needed)

If you prefer manual setup or need to run individual steps:

```bash
# Tool versions only
./.claude/scripts/setup/setup-versions.sh

# Git Hooks only
./.claude/scripts/setup/setup-git-hooks.sh

# MCP servers only
./.claude/scripts/setup/setup-mcp-servers.sh
```

See [.claude/guides/MCP-SETUP.md](.claude/guides/MCP-SETUP.md) for MCP details.
See [.claude/guides/git-hooks.md](.claude/guides/git-hooks.md) for Git Hooks details.

#### 4. Verify Setup

Check that everything is configured correctly:

```bash
# Verify tool versions match .tool-versions
flutter --version
node --version

# Run verification script
./.claude/scripts/setup/verify-setup.sh
```

Tool versions are specified in [.tool-versions](.tool-versions) and managed automatically.

#### 5. Read Development Guidelines

Familiarize yourself with our standards:

- **[CLAUDE.md](CLAUDE.md)** - Development guidelines (authoritative source)
- **[.claude/guides/MCP-SETUP.md](.claude/guides/MCP-SETUP.md)** - MCP servers setup guide
- **[.claude/guides/git-hooks.md](.claude/guides/git-hooks.md)** - Git Hooks setup and usage
- **[.claude/guides/quality-checks.md](.claude/guides/quality-checks.md)** - Quality checks and hooks
- **[.claude/guides/architecture.md](.claude/guides/architecture.md)** - Architecture documentation guide
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - Development environment setup
- **[docs/README.md](docs/README.md)** - Documentation standards

## Development Guidelines

All contributions must follow the guidelines in [CLAUDE.md](CLAUDE.md). Key principles:

### Language Policy

- **English-only**: All code, comments, documentation, and commit messages in English
- **Professional standards**: Business-appropriate and respectful language

### Security Guidelines

- **No exposed credentials**: Never commit API keys, tokens, or credentials
- **Environment variable management**: Use `.env.template` with placeholders
- **Secure coding practices**: Prevent injection vulnerabilities, XSS, etc.

### Code Quality Standards

- **Follow existing code style**: Match patterns in the codebase
- **Keep it simple**: Avoid over-engineering
- **Handle errors appropriately**: Proper error handling for user-facing features
- **Showcase quality**: Clean, readable, educational code

### Testing Standards

- **Target 80%+ test coverage**: Comprehensive testing is a priority
- **Test critical paths**: Core functionality, data sync, user-facing features
- **Unit and integration tests**: Test both isolated components and interactions
- **Test error scenarios**: Ensure edge cases are covered

### Documentation Standards

- **Update documentation**: Always update relevant docs after code changes
- **Architecture documentation**: Create and maintain ARCHITECTURE.md for each example
- **Keep docs current**: Update immediately when making changes

## Development Workflow

### Creating a New Example

1. **Choose a directory**: `apps/` for applications, `tools/` for utilities
2. **Copy architecture template**:
   ```bash
   cp docs/ARCHITECTURE_TEMPLATE.md <your-app-dir>/ARCHITECTURE.md
   ```
3. **Implement your example** following guidelines in [CLAUDE.md](CLAUDE.md)
4. **Document as you build**: Update ARCHITECTURE.md with each significant change
5. **Test thoroughly**: Target 80%+ code coverage
6. **Verify quality**: Automated checks run after each task

### Standard Workflow

1. **Create a branch** for your example or improvement
   ```bash
   git checkout -b feature/your-example-name
   ```
2. **Implement** following project standards
3. **Test** comprehensively
4. **Document** in ARCHITECTURE.md
5. **Verify** automated checks pass
   ```bash
   ./.claude/scripts/checks/post-task-check.sh
   ```
6. **Commit** with clear messages (Git Hooks will validate)
7. **Push** to your branch (pre-push checks will run)
8. **Submit PR** with clear description

## Quality Standards

This project maintains high quality standards as it serves as a showcase for developers:

- ✅ **English-only**: All code, comments, and documentation in English
- ✅ **Professional language**: Business-appropriate and respectful
- ✅ **Security-first**: No exposed credentials, proper input validation
- ✅ **Well-tested**: 80%+ test coverage target
- ✅ **Documented**: Current architecture documentation for all examples
- ✅ **Showcase quality**: Clean, readable, refactored code
- ✅ **Best practices**: Following latest Ditto and platform patterns

### Code Quality Principles

This is showcase code - prioritize:
- **Clarity over cleverness** - Code should be easy to understand
- **Simplicity over abstraction** - Don't over-engineer for hypothetical needs
- **Documentation over assumptions** - Explain the "why" behind decisions
- **Testing over hoping** - Validate critical functionality
- **Refactoring over technical debt** - Keep code clean and maintainable

## Automated Quality Checks

Git Hooks run automatically before commit/push. They check:

**Blocking**: Security (no exposed credentials), language (English-only), commit messages, code analysis (Dart)
**Non-blocking**: Architecture documentation

**Manual checks** (if needed):
```bash
./.claude/scripts/checks/post-task-check.sh          # All checks
./.claude/scripts/checks/security-check.sh           # Security only
./.claude/scripts/checks/language-check.sh           # Language only
./.claude/scripts/documentation/architecture-check.sh # Architecture only
```

**Full details**: [.claude/guides/git-hooks.md](.claude/guides/git-hooks.md)

## Submission Guidelines

### Pull Request Requirements

Your PR must include:

1. **Complete implementation**: Feature/example fully implemented
2. **Comprehensive tests**: 80%+ coverage, critical paths tested
3. **Architecture documentation**: ARCHITECTURE.md created/updated
4. **README updates**: If adding new example or changing structure
5. **Clean commit history**: Clear commit messages following standards
6. **Passing checks**: All automated checks pass

### PR Description Template

```markdown
## Description
Brief description of the example or improvement

## Type of Change
- [ ] New example application
- [ ] New tool/utility
- [ ] Bug fix
- [ ] Documentation update
- [ ] Other (please describe)

## Checklist
- [ ] Follows [CLAUDE.md](CLAUDE.md) guidelines
- [ ] Architecture documentation complete
- [ ] Tests added/updated (80%+ coverage)
- [ ] Security checks pass
- [ ] Language checks pass
- [ ] All documentation updated
- [ ] MCP servers used during development

## Testing
Describe how you tested this change

## Screenshots (if applicable)
Add screenshots for UI changes
```

## Code Review Process

### What Reviewers Check

Reviewers will verify:
- ✅ Adherence to [CLAUDE.md](CLAUDE.md) guidelines
- ✅ Architecture documentation completeness
- ✅ Test coverage (80%+ target)
- ✅ Security best practices
- ✅ Code quality and readability
- ✅ English-only compliance
- ✅ Professional standards

### Review Timeline

- Initial review: Within 3-5 business days
- Follow-up reviews: Within 2 business days after updates

### Addressing Feedback

- Respond to all review comments
- Make requested changes in separate commits
- Re-request review when ready
- Be patient and professional in discussions

## Resources for Contributors

### Documentation

- **[CLAUDE.md](CLAUDE.md)** - Development guidelines (authoritative source)
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - Development environment setup
- **[.claude/guides/MCP-SETUP.md](.claude/guides/MCP-SETUP.md)** - MCP servers setup
- **[.claude/guides/git-hooks.md](.claude/guides/git-hooks.md)** - Git Hooks guide
- **[.claude/guides/quality-checks.md](.claude/guides/quality-checks.md)** - Quality checks
- **[.claude/guides/architecture.md](.claude/guides/architecture.md)** - Architecture docs
- **[docs/README.md](docs/README.md)** - Documentation standards
- **[docs/ARCHITECTURE_TEMPLATE.md](docs/ARCHITECTURE_TEMPLATE.md)** - Architecture template

### External Resources

- **Ditto Documentation**: https://docs.ditto.live
- **Ditto MCP Integration**: https://docs.ditto.live/home/mcp-integration
- **Ditto Support**: https://support.ditto.live/
- **Flutter Documentation**: https://docs.flutter.dev
- **Flutter MCP Server**: https://dart.dev/tools/mcp-server
- **Flutter MCP Blog**: https://blog.flutter.dev/supercharge-your-dart-flutter-development-experience-with-the-dart-mcp-server-2edcc8107b49

### Getting Help

- **Issue Tracker**: [GitHub Issues](https://github.com/getditto/ditto-cookbook/issues)
- **Discussions**: [GitHub Discussions](https://github.com/getditto/ditto-cookbook/discussions)
- **Team Communication**: Check your team's communication channel

## Tips for Success

1. **Run complete setup first**: `./.claude/scripts/setup/complete-setup.sh` - saves time and ensures consistency
2. **Let automation help**: Tool versions and quality checks are handled automatically
3. **Start small**: Begin with a simple example to learn the workflow
4. **Use MCP servers**: They dramatically improve development experience
5. **Ask questions early**: Don't hesitate to open a discussion
6. **Test thoroughly**: Target 80%+ coverage from the start
7. **Document as you go**: Don't leave documentation for the end
8. **Follow the checklist**: Use the PR template to ensure completeness
9. **Be responsive**: Address review feedback promptly
10. **Learn from existing examples**: Study the codebase before starting

## Recognition

Contributors are recognized in:
- PR acknowledgments
- Release notes
- Project contributors list

Thank you for helping make the Ditto Cookbook a valuable resource for the community!

## License

By contributing to this project, you agree that your contributions will be licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

**Questions?** Open a [GitHub Discussion](https://github.com/getditto/ditto-cookbook/discussions) or reach out to the team.
