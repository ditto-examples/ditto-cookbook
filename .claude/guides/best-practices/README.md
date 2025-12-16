# Best Practices and Anti-Patterns

This directory contains platform-specific best practices and anti-pattern documentation for the Ditto Cookbook project. These guides help Claude Code and developers implement high-quality, maintainable code by providing clear patterns and examples.

## Overview

The best practices documentation serves as a reference for:
- **Claude Code**: Primary consumer during code implementation
- **Developers**: Secondary reference for learning and code reviews
- **Contributors**: Guidelines for documenting new patterns

Each document focuses on platform-specific or technology-specific patterns, with emphasis on DO/DON'T examples and practical code snippets.

## File Structure

- **[flutter.md](flutter.md)**: Flutter development best practices
  - Widget architecture and composition
  - State management patterns (Riverpod, Provider, Bloc)
  - Async programming and performance optimization
  - Testing strategies and platform integration

- **[ditto.md](ditto.md)**: Ditto SDK integration best practices
  - Initialization and configuration patterns
  - Collection design and schema best practices
  - Query optimization and sync strategies
  - Error handling and resilience patterns

## How to Use

### For Claude Code

When implementing features or fixing issues:
1. Check the relevant platform-specific file before writing code
2. Reference patterns that match the current task
3. Apply DO patterns and avoid DON'T patterns
4. Suggest new patterns when encountering novel situations

### For Developers

When adding content to these files:
1. Identify a recurring pattern or anti-pattern from code reviews, issues, or discussions
2. Document the pattern using the format below
3. Include clear DO/DON'T examples with code
4. Update this README if adding new platform files

## Pattern Documentation Guidelines

When adding patterns to these files, follow this structure:

```markdown
### [Pattern Name]

**Category**: [e.g., Architecture, State Management, Performance, Testing, etc.]

**Priority**: [Critical | High | Medium | Low]

**Context**: When and why this pattern applies

**Description**: Clear explanation of the pattern

**✅ DO (Best Practice):**
[Explanation of the recommended approach]

\`\`\`dart
// Good example code
\`\`\`

**❌ DON'T (Anti-Pattern):**
[Explanation of what to avoid]

\`\`\`dart
// Bad example code
\`\`\`

**Why**: Detailed rationale explaining benefits of DO and risks of DON'T

**Migration Guide**: If applicable, how to refactor from DON'T to DO

**Related Patterns**: Links to complementary patterns

**See Also**: References to relevant files or documentation
```

### Pattern Priorities

- **Critical**: Prevents security issues, data loss, or major bugs
- **High**: Significantly impacts code quality, performance, or maintainability
- **Medium**: Improves code clarity and consistency
- **Low**: Nice-to-have optimizations or stylistic improvements

### Categories

Common categories include:
- Architecture & Design
- State Management
- Performance & Optimization
- Testing & Quality Assurance
- Security & Data Protection
- Error Handling & Resilience
- Code Style & Readability
- Platform Integration

## Contributing Patterns

Patterns should come from:
1. **Code Reviews**: Common feedback and suggestions
2. **Issues & PRs**: Problems and solutions discovered during development
3. **Official Documentation**: Best practices from Flutter, Ditto, and platform docs
4. **Community**: Discussions on forums, Stack Overflow, and communities
5. **Experience**: Lessons learned from production issues

## Maintenance

- Update patterns when SDKs or frameworks change
- Remove outdated patterns and add deprecation notices if needed
- Keep examples current with the latest API versions
- Review and refine patterns based on feedback

## References

- [Ditto Documentation](https://docs.ditto.live/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Style Guide](https://dart.dev/guides/language/effective-dart)
- [CLAUDE.md](../../../CLAUDE.md) - Project development guidelines

---

**Note**: These documents are continuously evolving. Always check for the latest patterns before implementation.
