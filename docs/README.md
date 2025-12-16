# Documentation

This directory contains centralized documentation for the ditto-cookbook repository.

## Quick Start

### For Contributors

See [../CONTRIBUTING.md](../CONTRIBUTING.md) for complete setup instructions including:
- Repository cloning
- MCP servers configuration
- Git Hooks installation
- Development workflow

### For Learning

Browse the examples in [apps/](../apps/) and [tools/](../tools/) directories. Each example includes its own README with setup instructions.

### Architecture Documentation

New to architecture documentation? Start here:

**[../.claude/guides/architecture.md](../.claude/guides/architecture.md)** - Complete guide to architecture documentation, including quick start.

## Contents

### [ARCHITECTURE.md](ARCHITECTURE.md)

Central architecture documentation index that provides:
- Overview of repository structure
- Links to individual app/tool architecture documentation
- Cross-cutting concerns (Ditto integration, security, testing)
- Auto-generated summaries of all applications and tools

### [ARCHITECTURE_TEMPLATE.md](ARCHITECTURE_TEMPLATE.md)

Template for creating architecture documentation for new apps or tools:
- Comprehensive structure with all recommended sections
- Examples and guidance for each section
- Copy this template when creating a new app/tool

### `architecture/` Directory

Contains auto-generated summaries of each application and tool:
- Extracted from individual `ARCHITECTURE.md` files
- Automatically updated by architecture check hook
- Provides quick overview of each component

## Creating Architecture Documentation

When creating a new app or tool:

1. **Copy the template**:
   ```bash
   cp docs/ARCHITECTURE_TEMPLATE.md <your-app-dir>/ARCHITECTURE.md
   ```

2. **Fill in the sections** as you build:
   - Overview and technology stack
   - Project structure
   - Core components
   - Ditto integration details
   - Testing strategy

3. **Keep it updated** with each significant change

See [.claude/guides/architecture.md](../.claude/guides/architecture.md) for detailed instructions.

## Documentation Standards

All documentation in this repository must follow the guidelines in [CLAUDE.md](../CLAUDE.md):

- **Language**: English only
- **Professional tone**: Suitable for enterprise use
- **Always current**: Update with code changes
- **Showcase quality**: Clear, complete, and educational

## Automated Checks

The architecture check hook runs automatically after task completion to:
- Verify documentation exists and is current
- Check for required sections
- Update central index and summaries
- Report any issues or outdated documentation

Run manually:
```bash
bash .claude/scripts/architecture-check.sh
```

## Questions or Issues?

- See [architecture guide](../.claude/guides/architecture.md) for detailed guidance
- Refer to [CLAUDE.md](../CLAUDE.md) for development guidelines
- Check existing architecture documentation for examples

---
> **Last Updated:** 2025-12-16
