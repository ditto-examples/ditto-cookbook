# Ditto Cookbook

A collection of example applications and tools demonstrating best practices for building offline-first applications with the Ditto SDK.

## Overview

The Ditto Cookbook provides comprehensive examples of how to build real-world applications using Ditto's offline-first synchronization platform. Each example demonstrates proper architecture, testing, and implementation patterns that developers can learn from and adapt to their own projects.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/getditto/ditto-cookbook.git
cd ditto-cookbook

# Browse examples in apps/ and tools/ directories
```

**Want to contribute?** See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and guidelines.

## Available Examples

### Applications

Browse the [apps/](apps/) directory for example applications organized by platform:

- **Flutter**: Cross-platform mobile and desktop applications
- **[Future platforms]**: Additional platforms coming soon

Each application includes:
- Complete source code with best practices
- Architecture documentation
- Comprehensive tests
- README with setup instructions

### Tools

Browse the [tools/](tools/) directory for development utilities and helper tools that demonstrate specific Ditto patterns or simplify common tasks.

## Learning Resources

### Architecture Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Central architecture overview of all examples
- **[.claude/guides/architecture.md](.claude/guides/architecture.md)** - Complete guide to architecture documentation
- **Individual app ARCHITECTURE.md files** - Detailed architecture for each example

### How to Use This Repository

**For Learning**:
- Study architecture documentation to understand design decisions
- Review code for implementation patterns
- Check tests for validation approaches
- Use as reference when building your own applications

**For Development**:
- Follow the patterns demonstrated in examples
- Adapt examples to your specific use cases
- Learn Ditto SDK best practices from working code

## Testing

Run tests across all applications from the repository root:

```bash
./scripts/test-all.sh
```

This command:
- Discovers all testable applications automatically
- Runs tests in parallel for faster execution
- Stops on first failure (fail-fast behavior)
- Works with Flutter apps now, extensible to other platforms

For platform-specific testing instructions, see the README in each platform directory (e.g., [apps/flutter/README.md](apps/flutter/README.md)).

## Documentation

### Official Ditto Resources

- **Ditto Documentation**: https://docs.ditto.live
- **Ditto MCP Integration**: https://docs.ditto.live/home/mcp-integration
- **Ditto Support**: https://support.ditto.live/

### Platform Documentation

- **Flutter Documentation**: https://docs.flutter.dev
- **Flutter MCP Server**: https://dart.dev/tools/mcp-server

### Project Documentation

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Complete guide for contributors
- **[CLAUDE.md](CLAUDE.md)** - Development guidelines
- **[docs/README.md](docs/README.md)** - Documentation standards

## Contributing

We welcome contributions! To get started:

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed setup and guidelines
2. Check out [CLAUDE.md](CLAUDE.md) for development standards
3. Browse existing examples to understand the patterns
4. Submit your contribution following the workflow in CONTRIBUTING.md

### Quick Contribution Checklist

- ✅ Follow development guidelines in [CLAUDE.md](CLAUDE.md)
- ✅ Write showcase-quality code (clear, documented, educational)
- ✅ Target 80%+ test coverage
- ✅ Create/update architecture documentation
- ✅ Use English for all artifacts
- ✅ Ensure all checks pass

## Support

### Getting Help

- **Issue Tracker**: [GitHub Issues](https://github.com/getditto/ditto-cookbook/issues)
- **Discussions**: [GitHub Discussions](https://github.com/getditto/ditto-cookbook/discussions)
- **Ditto Support**: https://support.ditto.live/

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built by the Ditto community to help developers build better offline-first applications.

---

**Explore the examples and start building offline-first applications with Ditto!**
