# Ditto SDK Agent Skills

This directory contains Agent Skills for Ditto SDK best practices across multiple platforms: Flutter (Dart), JavaScript, Swift, and Kotlin.

## Overview

These Skills help Claude Code provide real-time guidance while you write offline-first applications with Ditto. They cover critical patterns for:
- Distributed data synchronization
- CRDT-safe data modeling
- Memory leak prevention
- Platform-specific API differences

## Available Skills

### 1. query-sync

**Focus**: DQL queries, subscriptions, observer patterns

**Priority**: CRITICAL - Prevents memory leaks and API compatibility issues

**Triggers**:
- Writing DQL queries (`ditto.store.execute()`)
- Creating subscriptions (`registerSubscription()`)
- Setting up observers (`registerObserver*()`)
- Using legacy builder methods (non-Flutter: deprecated SDK 4.12+, removed v5)

**Key patterns**:
- Legacy API detection (non-Flutter platforms)
- QueryResultItems retention → memory leaks
- Subscription lifecycle management
- Observer selection: `registerObserverWithSignalNext` (non-Flutter) vs `registerObserver` (Flutter v4.x, non-Flutter simple cases)
- Flutter SDK v4.x: Only `registerObserver` available (no `signalNext` until v5.0)
- Broad subscriptions without WHERE clauses

**Platform-specific**:
- **Flutter SDK v4.x**: Only `registerObserver` available (no `signalNext` support until v5.0)
- **Non-Flutter** (JS, Swift, Kotlin): Warn about deprecated builders, use `registerObserverWithSignalNext`

[View Skill →](query-sync/SKILL.md)

---

### 2. data-modeling

**Focus**: CRDT-safe data structures and merge safety

**Priority**: CRITICAL - Prevents data corruption and merge conflicts

**Triggers**:
- Designing document schemas
- Using arrays in documents
- Modeling relationships (embed vs flat)
- Implementing counters or event logs

**Key patterns**:
- Mutable arrays → MAP structures
- Over-normalization warnings (no JOIN support)
- Field-level updates vs document replacement
- Counter patterns (PN_INCREMENT and COUNTER type in 4.14.0+)
- Event history design

**Platform-specific**:
- Cross-platform (same CRDT rules apply to all SDKs)

[View Skill →](data-modeling/SKILL.md)

---

### 3. storage-lifecycle

**Focus**: Data deletion, EVICT, storage optimization

**Priority**: HIGH - Ensures data integrity and storage efficiency

**Triggers**:
- DELETE operations
- EVICT operations
- Storage management discussions
- Long-running app considerations

**Key patterns**:
- DELETE without tombstone strategy
- EVICT without subscription cancellation → resync loops
- Husked documents (concurrent DELETE/UPDATE)
- Logical deletion patterns
- EVICT frequency limits (max once/day)

**Platform-specific**:
- Cross-platform (same storage rules apply)

[View Skill →](storage-lifecycle/SKILL.md)

---

### 4. transactions-attachments

**Focus**: Transaction handling and attachment operations

**Priority**: CRITICAL - Prevents platform-specific bugs

**Triggers**:
- Using `ditto.store.transaction()`
- Atomic multi-step operations
- Attachment storage/fetching
- Large binary data handling

**Key patterns**:
- **Flutter**: Transaction API supported, must await all transactions before close()
- **All platforms**: Nested transaction deadlocks
- Attachment lazy-loading
- Attachment immutability
- Large binary data → use ATTACHMENT type

**Platform-specific**:
- **Flutter**: "Transactions supported, must await all transactions before closing Ditto instance"
- **All platforms**: Transaction rules, deadlock prevention

[View Skill →](transactions-attachments/SKILL.md)

---

### 5. performance-observability

**Focus**: Performance optimization and observability

**Priority**: HIGH - Improves user experience and resource efficiency

**Triggers**:
- Observer callback implementation
- Performance concerns
- Memory management patterns
- Logging configuration

**Key patterns**:
- Lightweight observer callbacks
- `signalNext()` timing (non-Flutter SDKs: after render cycle)
- Flutter SDK v4.x limitation: No `signalNext` support (available in v5.0)
- Partial UI updates (avoid full screen refresh)
- Unnecessary delta prevention (same-value updates)
- `DO UPDATE_LOCAL_DIFF` usage (SDK 4.12+)
- Log level configuration (before Ditto init)

**Platform-specific**:
- **Flutter SDK v4.x**: No `signalNext` support (available in v5.0), use `registerObserver` only
- **Non-Flutter SDKs**: Use `registerObserverWithSignalNext` with backpressure control
- Cross-platform with Flutter-specific UI patterns (WidgetsBinding, Riverpod)

[View Skill →](performance-observability/SKILL.md)

---

## How Skills Work Together

### Complementary Coverage

Each Skill focuses on a specific concern, but they work together:

```
data-modeling → Design your document structure
     ↓
query-sync → Subscribe to and observe data
     ↓
storage-lifecycle → Manage data lifecycle (delete/evict)
     ↓
performance-observability → Optimize performance

transactions-attachments (as needed for specific features)
```

### Example Workflow

**Scenario**: Building an offline-first task app

1. **data-modeling**: Design task document structure
   ```dart
   {
     "_id": "task_123",
     "title": "Buy groceries",
     "done": false,
     "tags": {"urgent": true, "personal": true}  // MAP, not array
   }
   ```

2. **query-sync**: Set up subscription and observer
   ```dart
   final subscription = ditto.sync.registerSubscription(
     'SELECT * FROM tasks WHERE done = :done',
     arguments: {'done': false},
   );

   final observer = ditto.store.registerObserverWithSignalNext(...);
   ```

3. **storage-lifecycle**: Implement logical deletion
   ```dart
   await ditto.store.execute(
     'UPDATE tasks SET isDeleted = true WHERE _id = :id',
     arguments: {'id': taskId},
   );
   ```

4. **performance-observability**: Optimize observer
   ```dart
   onChange: (result, signalNext) {
     final tasks = result.items.map((item) => item.value).toList();
     updateUI(tasks);
     WidgetsBinding.instance.addPostFrameCallback((_) => signalNext());
   }
   ```

## Platform Support Matrix

| Skill | Flutter | JavaScript | Swift | Kotlin |
|-------|---------|------------|-------|--------|
| query-sync | ✅ | ✅ | ✅ | ✅ |
| data-modeling | ✅ | ✅ | ✅ | ✅ |
| storage-lifecycle | ✅ | ✅ | ✅ | ✅ |
| transactions-attachments | ✅ (limited) | ✅ | ✅ | ✅ |
| performance-observability | ✅ | ✅ | ✅ | ✅ |

**Notes**:
- **Flutter**: No legacy builder API warnings (never existed in Flutter SDK)
- **Flutter**: No transaction support (use sequential DQL with error handling)
- **Non-Flutter**: Legacy API fully deprecated (SDK 4.12+), removed in v5
- **Non-Flutter**: Transaction deadlock risks

## Relationship to Main Guide

**Source of Truth**: `.claude/guides/best-practices/ditto.md` (4269 lines)

**Skills' Role**:
- Extract critical, automatable patterns from main guide
- Focus on common issues Claude can detect during coding
- Provide immediate, actionable guidance

**Division of Labor**:

| Artifact | Purpose | Audience | Maintenance |
|----------|---------|----------|-------------|
| Main guide | Comprehensive reference | Human developers | Continuous (source of truth) |
| Skills | Autonomous detection | Claude Code AI | Quarterly + SDK updates |

**Update workflow**:
1. New patterns discovered → Update main guide
2. Quarterly → Extract critical patterns into Skills
3. SDK updates → Update both immediately

## Getting Started

**For Developers**:
Just write Ditto code - Claude will automatically use Skills when relevant.

**For Contributors**:
See [../README.md](../README.md) for Skill authoring best practices.

## Learn More

- [Main Ditto Best Practices Guide](../../guides/best-practices/ditto.md)
- [Ditto SDK Documentation](https://docs.ditto.live/sdk/latest/)
- [Agent Skills Overview](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
