# Architecture Documentation

> **Note**: This file provides an overview of the architecture for all applications and tools in this repository. Each app and tool should maintain its own `ARCHITECTURE.md` in its respective directory with detailed implementation specifics.

## Purpose

This documentation serves as a central reference for:
- Understanding the overall system architecture
- Learning implementation patterns used in showcase applications
- Onboarding new developers
- Maintaining consistency across applications

## Repository Structure

```
ditto-cookbook/
├── apps/           # Sample applications demonstrating Ditto features
├── tools/          # Development and utility tools
├── docs/           # Centralized documentation
│   └── architecture/  # Individual app/tool architecture summaries
└── CLAUDE.md       # Development guidelines
```

## Architecture Documentation Index

### Applications

<!-- Applications will be listed here automatically as they are added -->

### Tools

<!-- Tools will be listed here automatically as they are added -->

## Cross-Cutting Concerns

### Ditto SDK Integration

All applications and tools in this repository integrate with the Ditto SDK for data synchronization capabilities.

**Common Patterns**:
- SDK initialization and configuration
- Data model definitions
- Sync operations and conflict resolution
- Offline-first architecture

### Security

All applications follow the security guidelines defined in [CLAUDE.md](../CLAUDE.md#security-guidelines):
- No hardcoded credentials
- Environment variable management with templates
- Input validation and sanitization
- Secure dependency management

### Testing

All applications target 80%+ test coverage as defined in [CLAUDE.md](../CLAUDE.md#testing-standards):
- Unit tests for business logic
- Integration tests for SDK interactions
- Error scenario testing

### Code Quality

All code serves as showcase examples following [CLAUDE.md](../CLAUDE.md#showcase-code-standards):
- Prioritizing readability
- Proactive refactoring
- Self-documenting code
- Complete, functional examples

## Updating This Documentation

When adding or modifying applications or tools:

1. Create or update `ARCHITECTURE.md` in the app/tool directory
2. Run the architecture documentation hook (automatically triggered)
3. The hook will update this central documentation and summaries in `docs/architecture/`

See [Architecture Documentation Guidelines](../CLAUDE.md#architecture-documentation) for details.

---
> **Last Updated:** 2025-12-16
