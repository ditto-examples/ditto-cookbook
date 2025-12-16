# Development Guidelines

> **Note**: This file is the authoritative source for all development guidelines in this project. The `.claude/settings.json` file references these guidelines but contains minimal configuration for maintainability.

## Table of Contents

1. [Language Policy](#language-policy)
2. [Documentation Updates](#documentation-updates)
3. [Architecture Documentation](#architecture-documentation)
4. [Best Practices and Technology Updates](#best-practices-and-technology-updates)
5. [Platform-Specific Best Practices](#platform-specific-best-practices)
6. [Security Guidelines](#security-guidelines)
7. [Code Quality Standards](#code-quality-standards)
8. [Testing Standards](#testing-standards)
9. [Dependency Management](#dependency-management)
10. [Showcase Code Standards](#showcase-code-standards)

---

# Development Guidelines

## Language Policy

All artifacts generated in this project must be written in English, including:

- Documentation files (*.md, *.txt, etc.)
- Source code comments
- Commit messages
- Code documentation (docstrings, JSDoc, etc.)
- Variable and function names
- Error messages and logs
- Configuration files
- README and other project documentation

This ensures consistency and accessibility for international collaboration.

### Professional Language Standards

This project is managed by a corporate entity. All language used must be:

- **Professional and appropriate** for a business environment
- **Respectful and inclusive** of all audiences
- **Free from offensive content** or language that violates public morals and social norms
- **Suitable for enterprise use** in documentation, code, and communications

## Documentation Updates

After completing any code changes or implementation work:

- **Always update relevant documentation** to reflect the changes made
- Update README files, API documentation, and inline comments as needed
- Ensure documentation remains synchronized with the codebase
- Do not skip documentation updates even for minor changes
- **Update architecture documentation** when making structural or significant changes

## Architecture Documentation

Every app/tool must maintain ARCHITECTURE.md using the template.

**Requirements**:
- Use [template](docs/ARCHITECTURE_TEMPLATE.md)
- Update on structural changes
- Include required sections: Overview, Tech Stack, Project Structure, Core Components, Ditto Integration, Testing Strategy
- Timestamp updates with "Last Updated: YYYY-MM-DD"

**Automation**:
- Central index: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Auto-generated summaries in `docs/architecture/`
- Validation via architecture-check hook (non-blocking)

**Best Practices**: Write for developers learning from examples. Be comprehensive. Include code snippets and file references. Explain decisions. Update immediately.

**Full guide**: [.claude/guides/architecture.md](.claude/guides/architecture.md)

## Git Hooks

This project uses Git Hooks to enforce quality standards before commits and pushes.

**Setup**: Run `./.claude/scripts/setup/complete-setup.sh` once after cloning.

**Installed Hooks**:
- **pre-commit**: Security and language checks (blocking)
- **commit-msg**: Commit message quality validation (blocking)
- **pre-push**: Comprehensive checks including Dart analysis (blocking, with non-blocking architecture validation)

**Bypassing**: Use `--no-verify` only for emergencies (e.g., broken hook, hotfix). Document the reason. All bypassed commits are still checked by CI/CD.

**Behavior**: Security/language violations block commits/pushes. Architecture warnings are informational. Hooks work for all developers.

**Full documentation**: [.claude/guides/git-hooks.md](.claude/guides/git-hooks.md)

## Best Practices and Technology Updates

When working on this project:

- **Check for latest information** about the tools and technologies being used (e.g., Ditto, Flutter SDK, platforms)
- **Consider current best practices** when implementing features or making changes
- Stay updated with official documentation and recommended patterns
- Apply the most recent and appropriate solutions for the current technology versions

## Platform-Specific Best Practices

When implementing features or fixing issues, consult the platform-specific best practices documentation:

**Flutter Development**: [.claude/guides/best-practices/flutter.md](.claude/guides/best-practices/flutter.md)
- Widget architecture patterns
- State management approaches
- Performance optimization techniques
- Testing strategies

**Ditto SDK Integration**: [.claude/guides/best-practices/ditto.md](.claude/guides/best-practices/ditto.md)
- Initialization and configuration patterns
- Collection design and schema best practices
- Query optimization and sync strategies
- Error handling and resilience patterns

**Directory Overview**: See [.claude/guides/best-practices/README.md](.claude/guides/best-practices/README.md) for structure and contribution guidelines.

**Note**: These documents are continuously evolving. Always check for the latest patterns before implementation.

## Security Guidelines

Security is a top priority:

- **Never commit** API keys, tokens, or credentials
- **Environment variables**: Never commit `.env` files. Always maintain `.env.template` with placeholders. Keep template synchronized with `.env`
- **Validate inputs** to prevent injection vulnerabilities
- **Sanitize output** to prevent XSS attacks
- **Follow OWASP guidelines** and security best practices
- **Keep dependencies updated**

## Code Quality Standards

Maintain high code quality while keeping implementations practical:

- **Follow existing code style** - Match the patterns and conventions already present in the codebase
- **Keep it simple** - Avoid over-engineering; implement what is needed, not what might be needed
- **Test critical functionality** - Ensure important features have appropriate test coverage
- **Handle errors appropriately** - Implement proper error handling for user-facing features and external dependencies

## Testing Standards

Comprehensive testing is a priority:

- **Target 80%+ coverage** across the codebase
- **Test critical paths**: Core functionality, data sync, user-facing features
- **Write unit tests** for business logic, utilities, isolated components
- **Write integration tests** for component interactions and Ditto SDK integration
- **Test error scenarios** and edge cases
- **Update tests** when modifying functionality

**Run all tests**: `./scripts/test-all.sh` (discovers all apps, runs in parallel, fail-fast)

## Dependency Management

Use `/update-deps` command to manage dependencies:

```bash
/update-deps check       # Check for outdated dependencies
/update-deps update      # Update dependencies interactively
/update-deps ditto       # Check Ditto SDK versions (HIGH PRIORITY)
```

**Ditto SDK Version Consistency** (HIGH PRIORITY):
- Check regularly with `/update-deps ditto`
- Version mismatches cause confusion for users learning from examples
- When upgrading: Review release notes, update all projects, test all apps, verify consistency

**Supported platforms**: Flutter, Node.js, Python, iOS, Android

**Best practices**: Check weekly, verify after adding apps, run tests after updates, update docs if needed

**Manual by default** - Does not run automatically via hooks (dependency updates can break code)

**Full guide**: [.claude/guides/dependency-management.md](.claude/guides/dependency-management.md)

## Showcase Code Standards

This project serves as a showcase for users to reference and learn from. Therefore, code quality and readability are paramount:

- **Prioritize readability** - Code should be clear and easy to understand for developers learning from these examples
- **Refactor proactively** - Regularly refactor code to improve clarity and maintainability
  - Simplify complex logic
  - Extract meaningful functions and components
  - Use descriptive names for variables, functions, and classes
  - Remove code duplication
- **Balance maintainability with simplicity** - When refactoring:
  - **Prefer simplicity over excessive abstraction** - Don't over-engineer for hypothetical future needs
  - **Keep it straightforward** - If a simple solution works well, don't make it complex
  - **Avoid premature optimization** - Focus on clarity first, optimize only when necessary
- **Write self-documenting code** - Use clear naming and structure so the code explains itself
- **Add helpful comments** - Explain the "why" behind non-obvious decisions, not the "what" (which should be clear from the code itself)
- **Follow platform conventions** - Use idiomatic patterns for Flutter/Dart and the Ditto SDK
- **Make examples complete** - Showcase implementations should be functional, not just conceptual snippets
