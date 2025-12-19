# Architecture Documentation Guide

This guide explains how to create and maintain architecture documentation for applications and tools in the ditto-cookbook repository.

## Table of Contents

1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Documentation Structure](#documentation-structure)
4. [Creating Architecture Documentation](#creating-architecture-documentation)
5. [Updating Documentation](#updating-documentation)
6. [Automated Checks](#automated-checks)
7. [Best Practices](#best-practices)
8. [Examples](#examples)

## Overview

Every application and tool in this repository must have an `ARCHITECTURE.md` file that documents:

- System design and structure
- Core components and their responsibilities
- Ditto SDK integration patterns
- Data models and synchronization strategies
- Testing approach and coverage

This ensures that developers can:
- Quickly understand how each app/tool works
- Learn implementation patterns and best practices
- Maintain and extend the codebase effectively
- Use these examples as reference for their own projects

## Getting Started

### For a New App or Tool

1. **Copy the template**:
   ```bash
   cp docs/ARCHITECTURE_TEMPLATE.md <your-app-dir>/ARCHITECTURE.md
   ```

2. **Fill in the sections**:
   - Start with Overview, Technology Stack, and Project Structure
   - Document Core Components as you build them
   - Add Ditto Integration details as you implement sync features
   - Update Testing Strategy as you write tests

3. **Keep it updated**:
   - Update the "Last Updated" date (at the beginning of the document) with each change
   - Modify sections as your architecture evolves
   - Add new sections if needed for your specific use case

### For an Existing App or Tool

1. **Check if ARCHITECTURE.md exists**:
   ```bash
   ls <your-app-dir>/ARCHITECTURE.md
   ```

2. **If missing, create one**:
   - Review the codebase to understand current architecture
   - Use the template and fill in all sections
   - Document what exists today, not what was planned

3. **If exists but outdated**:
   - Review recent changes
   - Update affected sections
   - Update the "Last Updated" date (at the beginning of the document)

## Documentation Structure

### Central Documentation

- **`docs/ARCHITECTURE.md`**: Central index listing all apps and tools
- **`docs/ARCHITECTURE_TEMPLATE.md`**: Template for creating new documentation
- **`docs/architecture/`**: Auto-generated summaries of each app/tool

### Per-App/Tool Documentation

Each app or tool should have:

```
app-name/
├── ARCHITECTURE.md       # Main architecture documentation
├── README.md            # Getting started and overview
├── lib/                 # Source code
│   └── ...
└── test/               # Tests
    └── ...
```

## Creating Architecture Documentation

### Required Sections

These sections must be included in every `ARCHITECTURE.md`:

#### 1. Overview

Brief description (2-3 paragraphs) covering:
- What the app/tool does
- Primary use case or problem it solves
- Key features or capabilities

```markdown
## Overview

This application demonstrates real-time data synchronization using Ditto SDK
in a Flutter mobile app. It showcases offline-first architecture with a
task management interface.

Key features include automatic conflict resolution, peer-to-peer sync, and
seamless online/offline transitions.
```

#### 2. Technology Stack

List all major technologies:

```markdown
## Technology Stack

- **Platform**: Flutter (Mobile - iOS & Android)
- **Language**: Dart 3.2+
- **Ditto SDK**: 4.5.0
- **Key Dependencies**:
  - provider (6.1.1) - State management
  - uuid (4.2.0) - Unique ID generation
```

#### 3. Project Structure

Show directory organization with descriptions:

```markdown
## Project Structure

\`\`\`
app-name/
├── lib/
│   ├── models/        # Data models and Ditto document schemas
│   ├── services/      # Business logic and Ditto integration
│   ├── providers/     # State management providers
│   ├── ui/           # Screens and widgets
│   └── main.dart     # App entry point
├── test/             # Unit and integration tests
└── pubspec.yaml      # Dependencies
\`\`\`
```

#### 4. Core Components

Document major architectural components:

```markdown
## Core Components

### DittoService

**Purpose**: Manages Ditto SDK initialization and data operations

**Responsibilities**:
- Initialize Ditto with appropriate configuration
- Manage collections and subscriptions
- Handle CRUD operations
- Provide sync status information

**Key Files**:
- [`lib/services/ditto_service.dart`](lib/services/ditto_service.dart)
```

#### 5. Ditto Integration

Explain how Ditto SDK is used:

```markdown
## Ditto Integration

### Initialization

Ditto is initialized in the `DittoService` constructor with online playground
configuration:

\`\`\`dart
_ditto = await Ditto.open(
  identity: await OnlinePlaygroundIdentity.create(
    appId: appId,
    token: token,
  ),
);
\`\`\`

### Sync Strategy

- **Sync Mode**: Online with observers for real-time updates
- **Conflict Resolution**: Last-write-wins (automatic)
- **Subscriptions**: Subscribe to entire collections with observers
```

#### 6. Testing Strategy

Document testing approach:

```markdown
## Testing Strategy

### Test Coverage

Current coverage: 85%

### Test Types

- **Unit Tests**: Business logic, data models, utilities
  - Location: `test/unit/`
  - Coverage: 90%

- **Widget Tests**: UI components and user interactions
  - Location: `test/widget/`
  - Coverage: 80%

### Running Tests

\`\`\`bash
flutter test
flutter test --coverage
\`\`\`
```

### Optional Sections

Add these if relevant to your app/tool:

- **Architecture Diagram**: Visual representation of system structure
- **Data Model**: Detailed schema definitions
- **State Management**: How app state is managed
- **User Interface**: Screen/component structure
- **Business Logic**: Key workflows and processes
- **Error Handling**: How errors are caught and handled
- **Performance Considerations**: Optimization strategies
- **Security Considerations**: Security measures implemented
- **Configuration**: Environment variables and settings
- **Deployment**: How to deploy or distribute
- **Known Issues**: Current limitations
- **Future Enhancements**: Planned improvements

## Updating Documentation

### When to Update

Update `ARCHITECTURE.md` when you:

1. **Add/remove major components**
   - New services, models, or core classes
   - Removal of deprecated components

2. **Change system structure**
   - Reorganize directories
   - Split or merge modules
   - Change architectural patterns

3. **Modify Ditto integration**
   - Change sync strategy
   - Update data models
   - Add/remove collections

4. **Update technology stack**
   - Upgrade Ditto SDK version
   - Add/remove major dependencies
   - Change frameworks or libraries

5. **Implement new features**
   - Add new screens or workflows
   - Introduce new architectural patterns

### How to Update

1. **Open the file**:
   ```bash
   open <your-app-dir>/ARCHITECTURE.md
   ```

2. **Update relevant sections**:
   - Modify only what changed
   - Keep it concise but complete
   - Add code examples if helpful

3. **Update timestamp** (at the beginning of the document, right after the title):
   ```markdown
   > **Last Updated**: 2025-12-16
   ```

4. **Verify completeness**:
   - Check all required sections are present
   - Ensure links to code are correct
   - Verify code examples work

## Automated Checks

The architecture check hook runs automatically after task completion.

### What It Checks

1. **Documentation existence**: Verifies `ARCHITECTURE.md` exists
2. **Freshness**: Warns if source files are newer than documentation
3. **Structure**: Checks for required sections
4. **Central index**: Updates `docs/ARCHITECTURE.md` and summaries

### Understanding Check Results

#### ✓ Green (Success)
```
✓ ARCHITECTURE.md exists
✓ Generated summary for app: task-manager
```
Documentation is present and up-to-date.

#### ⚠ Yellow (Warning)
```
⚠ Warning: ARCHITECTURE.md in apps/task-manager may be outdated
```
Consider updating documentation, but not critical.

#### ℹ Blue (Info)
```
ℹ Checking if central architecture index needs updating...
```
Informational message about ongoing checks.

### Manual Check

Run the architecture check manually:

```bash
bash .claude/scripts/architecture-check.sh
```

## Best Practices

### Write for Your Audience

- **Assume intermediate developers**: Explain patterns but not basics
- **Focus on decisions**: Explain why choices were made
- **Be specific**: Link to actual code, not general concepts
- **Use examples**: Show code snippets for key patterns

### Keep It Current

- **Update immediately**: Don't wait for "documentation day"
- **Small changes count**: Even minor updates should be documented
- **Timestamp everything**: Always update "Last Updated" date (at the beginning of the document)
- **Review regularly**: Quarterly check for accuracy

### Make It Useful

- **Complete but concise**: Include necessary details, skip obvious ones
- **Visual when helpful**: Add diagrams for complex architectures
- **Link generously**: Reference code files and line numbers
- **Organize logically**: Follow the template structure

### Showcase Quality

Remember this is reference material:

- **Prioritize clarity**: Make it easy to understand
- **Show best practices**: Demonstrate good patterns
- **Explain trade-offs**: Why this approach over alternatives
- **Be honest**: Document limitations and known issues

## Examples

### Good Overview Section

```markdown
## Overview

This tool generates Ditto data model definitions from JSON schemas. It
automates the creation of Dart classes with proper Ditto annotations,
reducing boilerplate and ensuring consistency across collections.

The tool accepts JSON Schema v7 as input and outputs Dart files with:
- Class definitions with typed properties
- Ditto annotations for document structure
- Serialization/deserialization methods
- Validation logic for required fields

Primary use case: Quickly scaffold Ditto models for new projects or features.
```

### Good Core Component Section

```markdown
## Core Components

### TaskRepository

**Purpose**: Provides data access layer for task entities with Ditto sync

**Responsibilities**:
- CRUD operations for tasks using Ditto collections
- Subscribe to task changes and emit updates
- Handle conflict resolution for concurrent edits
- Maintain local cache for offline access

**Key Files**:
- [`lib/repositories/task_repository.dart:15-120`](lib/repositories/task_repository.dart#L15-L120) - Main repository implementation
- [`lib/models/task.dart:8-45`](lib/models/task.dart#L8-L45) - Task data model

**Dependencies**:
- `DittoService` - For Ditto SDK operations
- `TaskModel` - Data structure definition

**Usage Example**:

\`\`\`dart
final repository = TaskRepository(dittoService);

// Create a task
final task = await repository.create(
  title: 'Complete documentation',
  dueDate: DateTime.now().add(Duration(days: 1)),
);

// Listen for changes
repository.watchAll().listen((tasks) {
  print('Tasks updated: ${tasks.length}');
});
\`\`\`
```

### Good Ditto Integration Section

```markdown
## Ditto Integration

### Initialization

Ditto is initialized in `DittoService.initialize()` using environment-based
configuration. For development, we use Online Playground identity:

\`\`\`dart
final appId = dotenv.env['DITTO_APP_ID']!;
final token = dotenv.env['DITTO_TOKEN']!;

_ditto = await Ditto.open(
  identity: await OnlinePlaygroundIdentity.create(
    appId: appId,
    token: token,
  ),
);

await _ditto.startSync();
\`\`\`

See [`lib/services/ditto_service.dart:28-42`](lib/services/ditto_service.dart#L28-L42)

### Sync Strategy

**Mode**: Online with real-time observers

**Conflict Resolution**: Last-write-wins with timestamp tracking
- Each document includes `_updatedAt` timestamp
- Ditto automatically selects most recent version
- No custom conflict resolution needed for current use cases

**Subscriptions**:
We subscribe to entire collections rather than individual documents to ensure
all data is available offline:

\`\`\`dart
final subscription = _ditto.store
  .collection('tasks')
  .findAll()
  .subscribe();
\`\`\`

**Observers**:
Real-time updates use observers with stream controllers:

\`\`\`dart
final observer = _ditto.store
  .collection('tasks')
  .findAll()
  .observe((docs) {
    _controller.add(docs.map((d) => Task.fromDitto(d)).toList());
  });
\`\`\`

### Data Models

All models follow this pattern for Ditto integration:

1. **fromDitto factory**: Deserialize from DittoDocument
2. **toDitto method**: Serialize to Map for Ditto
3. **Unique IDs**: Use UUID v4 for document IDs
4. **Timestamps**: Include created/updated timestamps

See [`lib/models/task.dart`](lib/models/task.dart) for reference implementation.
```

## References

- [CLAUDE.md](../../CLAUDE.md) - Development guidelines
- [docs/ARCHITECTURE_TEMPLATE.md](../../docs/ARCHITECTURE_TEMPLATE.md) - Template file
- [Ditto Documentation](https://docs.ditto.live/) - Ditto SDK reference
- [Architecture Check Script](../scripts/documentation/architecture-check.sh) - Validation script

---

**Questions or suggestions?** Update this guide or discuss in team meetings.
