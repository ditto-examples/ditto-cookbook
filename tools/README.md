# Development Tools

This directory contains development utilities and tools used to support the Ditto Cookbook examples.

## Overview

Tools in this directory provide common functionality that can be shared across multiple applications, such as testing utilities, code generators, or helper scripts.

## Structure

```
tools/
├── README.md                    # This file
└── [tool-name]/                 # Individual tool directories
    ├── README.md                # Tool-specific documentation
    ├── ARCHITECTURE.md          # Tool architecture (if applicable)
    └── [tool implementation]    # Tool source code
```

## Standards

All tools must:
- Have a comprehensive README.md explaining purpose and usage
- Include ARCHITECTURE.md if the tool has significant complexity
- Follow the project's coding standards from [CLAUDE.md](../CLAUDE.md)
- Include tests where applicable
- Be documented in English only

## Adding a New Tool

When creating a new tool:

1. **Create directory structure**:
   ```bash
   mkdir -p tools/my-tool
   ```

2. **Add README.md** with usage instructions:
   ```bash
   cp docs/ARCHITECTURE_TEMPLATE.md tools/my-tool/README.md
   # Edit to describe the tool
   ```

3. **Add ARCHITECTURE.md** if complex:
   ```bash
   cp docs/ARCHITECTURE_TEMPLATE.md tools/my-tool/ARCHITECTURE.md
   # Document the architecture
   ```

4. **Update this file** to list the new tool below

5. **Ensure all code follows project guidelines** from [CLAUDE.md](../CLAUDE.md)

## Available Tools

Currently no tools are implemented. This section will be updated as tools are added.

### Future Tool Ideas

Potential tools for the Ditto Cookbook:
- **Code Generator**: Generate boilerplate for Ditto applications
- **Data Migration Tool**: Migrate data between Ditto SDK versions
- **Performance Profiler**: Profile Ditto sync performance
- **Schema Validator**: Validate Ditto data schemas

---
> **Last Updated:** 2025-12-16
