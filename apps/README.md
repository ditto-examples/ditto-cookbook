# Ditto Cookbook - Sample Applications

This directory contains sample applications demonstrating various Ditto SDK integration patterns and use cases. Each app showcases best practices for building offline-first, real-time sync applications using [Ditto](https://docs.ditto.live).

## Purpose

The applications in this directory serve as:

- **Reference Implementations**: Production-ready examples of Ditto SDK integration
- **Learning Resources**: Educational code demonstrating common patterns and best practices
- **Starting Points**: Templates for building your own Ditto-powered applications
- **Testing Ground**: Environments for experimenting with Ditto features

## Directory Structure

### [flutter/](flutter/)

Flutter applications demonstrating Ditto integration for mobile (iOS/Android) platforms. Includes examples of:

- Real-time data synchronization
- Offline-first architecture
- Complex state management with Ditto
- Platform-specific implementations
- Testing strategies for sync-enabled apps

See [flutter/README.md](flutter/README.md) for Flutter-specific setup instructions and requirements.

## Getting Started

### Prerequisites

1. **Ditto Account**: Sign up at [Ditto Portal](https://portal.ditto.live)
2. **Environment Setup**: Copy `.env.template` to `.env` and fill in your credentials
3. **Platform Tools**: Install required SDKs for your target platform (see platform-specific READMEs)

### Environment Configuration

All apps require Ditto credentials configured via environment variables:

```bash
# Copy the template
cp ../.env.template ../.env

# Edit .env with your credentials
# NEVER commit .env to version control
```

Required variables:
- `DITTO_DATABASE_ID`: Your Ditto database identifier
- `DITTO_AUTH_URL`: Authentication endpoint
- `DITTO_WEBSOCKET_URL`: WebSocket endpoint for sync
- `DITTO_ONLINE_PLAYGROUND_TOKEN`: Playground mode token

See [.env.template](../.env.template) for complete documentation.

## Requirements and Standards

All applications in this repository follow these standards:

### Documentation
- **ARCHITECTURE.md**: Required for each app (see [ARCHITECTURE_TEMPLATE.md](../docs/ARCHITECTURE_TEMPLATE.md))
- **README.md**: Getting started guide and setup instructions
- **Code Comments**: English-only, explaining "why" not "what"

### Code Quality
- **Test Coverage**: Target 80%+ coverage
- **Code Style**: Follow platform-specific conventions and best practices
- **Security**: No hardcoded credentials, proper input validation
- **Readability**: Showcase-quality code suitable for learning

### Testing
- Unit tests for business logic
- Integration tests for Ditto sync operations
- Platform-specific tests (widget tests for Flutter, etc.)

## Architecture Documentation

Each app maintains detailed architecture documentation. See:

- [Central Architecture Index](../docs/ARCHITECTURE.md) - Overview of all apps
- [Architecture Template](../docs/ARCHITECTURE_TEMPLATE.md) - Template for new apps
- [Architecture Guide](../.claude/guides/architecture.md) - Complete architecture documentation guide

## Common Patterns

### Offline-First Architecture

All apps demonstrate offline-first design:
- Local-first data access
- Background synchronization
- Conflict resolution strategies
- Network resilience

### Real-Time Sync

Examples include:
- Live queries and observers
- Reactive UI updates
- Multi-device synchronization
- Peer-to-peer mesh networking

### State Management

Platform-appropriate state management integrated with Ditto:
- Flutter: Riverpod, Provider, or Bloc
- Separation of sync layer from UI state
- Testable architecture

## Resources

- [Ditto Documentation](https://docs.ditto.live)
- [Ditto Portal](https://portal.ditto.live)
- [Project Guidelines](../CLAUDE.md)
- [Architecture Guides](../docs/)

## Contributing

When adding new applications:

1. Follow the directory structure of existing apps
2. Create ARCHITECTURE.md using the template
3. Include comprehensive tests (80%+ coverage)
4. Document all Ditto integration patterns
5. Use English for all documentation and code
6. Follow security best practices (no exposed credentials)

See [CLAUDE.md](../CLAUDE.md) for complete development guidelines.
