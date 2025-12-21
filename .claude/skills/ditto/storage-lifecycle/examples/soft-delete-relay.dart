// SDK Version: All
// Platform: All
// Last Updated: 2025-12-19
//
// ============================================================================
// Soft-Delete Pattern with Multi-Hop Relay Support
// ============================================================================
//
// This example demonstrates the CORRECT Soft-Delete pattern that supports
// multi-hop relay in Ditto's mesh network.
//
// CRITICAL LEARNING: Subscriptions Must Include ALL Documents (Even Deleted)
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Correct Pattern: Broad subscription (no deletion filter)
// 2. ✅ Observer filters deleted items for UI display
// 3. ✅ execute() filters deleted items for app logic
// 4. ❌ Incorrect Pattern: Filtered subscription (breaks relay)
// 5. ✅ Multi-device simulation showing propagation
// 6. ✅ Relay failure scenario demonstration
//
// WHY THIS MATTERS:
// - Ditto peers can relay data through intermediate devices (multi-hop sync)
// - If Device A's subscription filters `isDeleted = true`, it won't store deleted docs
// - Device A cannot relay what it doesn't have to Device B
// - Result: Device B never receives deletion updates (inconsistent state)
//
// KEY PRINCIPLE:
// - Subscriptions declare data needs to the mesh network
// - Observers control local UI display
// - Keep them separate for Soft-Delete to work in multi-hop scenarios
//
// OFFICIAL QUOTE:
// "we need to be careful to distinguish between the subscription and the store
// query. The subscription must not have WHERE deleted or the soft-delete flag
// will not be propagated to other clients. The queries used for observers +
// execute commands MUST have the WHERE NOT deleted clause. This is definitely
// a footgun that I imagine is a common issue hit with new users"
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: ✅ CORRECT - Broad Subscription with Filtered Observer
// ============================================================================

/// ✅ GOOD: Correct Soft-Delete pattern for multi-hop relay
class CorrectSoftDeletePattern {
  final Ditto ditto;
  DittoSyncSubscription? subscription;
  DittoStoreObserver? observer;

  CorrectLogicalDeletionPattern(this.ditto);

  Future<void> setupCorrectPattern() async {
    print('✅ CORRECT PATTERN: Broad subscription + filtered observer\n');

    // ✅ STEP 1: Subscribe to ALL tasks (including deleted)
    // CRITICAL: No isDeleted filter in subscription
    print('1️⃣ Setting up subscription (no deletion filter)...');
    subscription = ditto.sync.registerSubscription(
      'SELECT * FROM tasks',  // No isDeleted filter - enables proper relay
    );
    print('   ✅ Subscription includes ALL documents (even isDeleted=true)\n');

    // ✅ STEP 2: Observer filters deleted tasks for UI display
    print('2️⃣ Setting up observer (with deletion filter for UI)...');
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        final activeTasks = result.items
            .map((item) => item.value)
            .toList();

        print('   📊 Observer callback: ${activeTasks.length} active tasks');
        print('   (Deleted tasks are filtered out for UI)\n');

        // Update UI with active tasks only
        // updateUI(activeTasks);

        signalNext();
      },
    );
    print('   ✅ Observer filters isDeleted=true for UI display\n');

    print('✅ Pattern setup complete!\n');
    print('📝 Summary:');
    print('   - Subscription: SELECT * FROM tasks (no filter)');
    print('   - Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   - Result: Deleted docs stored locally + relayed to peers\n');
  }

  Future<void> markTaskAsDeleted(String taskId) async {
    print('🗑️ Marking task as deleted...\n');

    final deletedAt = DateTime.now().toIso8601String();
    await ditto.store.execute(
      'UPDATE tasks SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
      arguments: {'id': taskId, 'deletedAt': deletedAt},
    );

    print('   ✅ Task marked as deleted (isDeleted=true)');
    print('   📦 Document stored locally (even though deleted)');
    print('   🔄 Deletion will relay to other peers via subscription\n');
  }

  Future<void> queryActiveTasks() async {
    print('📋 Querying active tasks for app logic...\n');

    // ✅ execute() queries filter deleted tasks
    final result = await ditto.store.execute(
      'SELECT * FROM tasks WHERE isDeleted != true AND status = :status',
      arguments: {'status': 'pending'},
    );

    final activeTasks = result.items.map((item) => item.value).toList();
    print('   📊 Found ${activeTasks.length} active pending tasks');
    print('   (Deleted tasks excluded from app logic)\n');
  }

  void cleanup() {
    subscription?.cancel();
    observer?.cancel();
    print('🧹 Cleaned up subscription and observer\n');
  }
}

// ============================================================================
// PATTERN 2: ❌ INCORRECT - Filtered Subscription (Breaks Relay)
// ============================================================================

/// ❌ BAD: Incorrect pattern that breaks multi-hop relay
class IncorrectLogicalDeletionPattern {
  final Ditto ditto;
  DittoSyncSubscription? subscription;
  DittoStoreObserver? observer;

  IncorrectLogicalDeletionPattern(this.ditto);

  Future<void> setupIncorrectPattern() async {
    print('❌ INCORRECT PATTERN: Filtered subscription (BREAKS RELAY!)\n');

    // ❌ STEP 1: Subscribe with deletion filter (WRONG!)
    print('1️⃣ Setting up subscription (with deletion filter - WRONG!)...');
    subscription = ditto.sync.registerSubscription(
      'SELECT * FROM tasks WHERE isDeleted != true',  // BREAKS RELAY!
    );
    print('   ❌ Subscription filters isDeleted=true documents\n');
    print('   ⚠️  Problem: Deleted docs not stored locally');
    print('   ⚠️  Problem: Cannot relay deleted docs to other peers\n');

    // STEP 2: Observer (same as correct pattern, but doesn't matter)
    print('2️⃣ Setting up observer...');
    observer = ditto.store.registerObserverWithSignalNext(
      'SELECT * FROM tasks WHERE isDeleted != true ORDER BY createdAt DESC',
      onChange: (result, signalNext) {
        final activeTasks = result.items
            .map((item) => item.value)
            .toList();

        print('   📊 Observer callback: ${activeTasks.length} active tasks\n');

        signalNext();
      },
    );

    print('❌ Pattern setup complete (but BROKEN for multi-hop!)\n');
    print('📝 Summary:');
    print('   - Subscription: SELECT * FROM tasks WHERE isDeleted != true (WRONG!)');
    print('   - Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   - Result: Deleted docs NOT stored → Cannot relay to peers!\n');
  }

  Future<void> markTaskAsDeleted(String taskId) async {
    print('🗑️ Marking task as deleted...\n');

    final deletedAt = DateTime.now().toIso8601String();
    await ditto.store.execute(
      'UPDATE tasks SET isDeleted = true, deletedAt = :deletedAt WHERE _id = :id',
      arguments: {'id': taskId, 'deletedAt': deletedAt},
    );

    print('   ✅ Task marked as deleted (isDeleted=true)');
    print('   ⚠️  Subscription no longer matches this document!');
    print('   ⚠️  Document may not be stored or relayed properly');
    print('   ❌ Other peers may never receive this deletion update\n');
  }

  void cleanup() {
    subscription?.cancel();
    observer?.cancel();
    print('🧹 Cleaned up subscription and observer\n');
  }
}

// ============================================================================
// PATTERN 3: Multi-Device Relay Simulation
// ============================================================================

/// Simulates multi-hop relay scenario with 3 devices
class MultiHopRelaySimulation {
  late Ditto dittoA;
  late Ditto dittoB;
  late Ditto dittoC;

  Future<void> demonstrateCorrectPattern() async {
    print('═══════════════════════════════════════════════════════════════════');
    print('SIMULATION: Correct Pattern with Multi-Hop Relay');
    print('═══════════════════════════════════════════════════════════════════\n');

    print('Network Topology: Device A ←→ Device B ←→ Device C');
    print('(Device B acts as relay between A and C)\n');

    print('📱 Device A (source): Creates and deletes tasks');
    print('📱 Device B (relay): Relays data between A and C');
    print('📱 Device C (destination): Receives all updates\n');

    // Initialize devices (simplified - in real app, use proper initialization)
    // dittoA = await Ditto.open(...);
    // dittoB = await Ditto.open(...);
    // dittoC = await Ditto.open(...);

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 1: All devices set up CORRECT subscriptions\n');

    print('Device A: Subscription with NO deletion filter');
    print('   SELECT * FROM tasks\n');

    print('Device B: Subscription with NO deletion filter');
    print('   SELECT * FROM tasks\n');

    print('Device C: Subscription with NO deletion filter');
    print('   SELECT * FROM tasks\n');

    print('✅ All devices can receive AND relay ALL documents\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 2: Device A creates a task\n');

    print('Device A: INSERT task_1 (title="Buy groceries")');
    print('   ✅ Task stored in Device A');
    print('   🔄 Syncs to Device B');
    print('   ✅ Task stored in Device B');
    print('   🔄 Device B relays to Device C');
    print('   ✅ Task stored in Device C\n');

    print('Result: All devices have task_1 ✅\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 3: Device A marks task as deleted\n');

    print('Device A: UPDATE task_1 SET isDeleted=true');
    print('   ✅ Deletion update stored in Device A (still matches subscription)');
    print('   🔄 Syncs to Device B');
    print('   ✅ Deletion update stored in Device B (still matches subscription)');
    print('   🔄 Device B relays to Device C');
    print('   ✅ Deletion update stored in Device C\n');

    print('Result: All devices know task_1 is deleted ✅\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 4: Observers on each device\n');

    print('Device A Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   📊 Result: 0 tasks (task_1 filtered out)\n');

    print('Device B Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   📊 Result: 0 tasks (task_1 filtered out)\n');

    print('Device C Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   📊 Result: 0 tasks (task_1 filtered out)\n');

    print('✅ All devices show consistent UI (no deleted tasks displayed)\n');

    print('═══════════════════════════════════════════════════════════════════');
    print('CONCLUSION: Correct pattern works perfectly! ✅');
    print('═══════════════════════════════════════════════════════════════════\n');
  }

  Future<void> demonstrateIncorrectPattern() async {
    print('═══════════════════════════════════════════════════════════════════');
    print('SIMULATION: Incorrect Pattern with Multi-Hop Relay (BROKEN)');
    print('═══════════════════════════════════════════════════════════════════\n');

    print('Network Topology: Device A ←→ Device B ←→ Device C');
    print('(Device B acts as relay between A and C)\n');

    print('📱 Device A (source): Creates and deletes tasks');
    print('📱 Device B (relay): Relays data between A and C');
    print('📱 Device C (destination): Receives all updates\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 1: All devices set up INCORRECT subscriptions\n');

    print('Device A: Subscription WITH deletion filter (WRONG!)');
    print('   SELECT * FROM tasks WHERE isDeleted != true\n');

    print('Device B: Subscription WITH deletion filter (WRONG!)');
    print('   SELECT * FROM tasks WHERE isDeleted != true\n');

    print('Device C: Subscription WITH deletion filter (WRONG!)');
    print('   SELECT * FROM tasks WHERE isDeleted != true\n');

    print('⚠️  Problem: Devices won\'t store deleted documents\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 2: Device A creates a task\n');

    print('Device A: INSERT task_1 (title="Buy groceries")');
    print('   ✅ Task stored in Device A');
    print('   🔄 Syncs to Device B');
    print('   ✅ Task stored in Device B');
    print('   🔄 Device B relays to Device C');
    print('   ✅ Task stored in Device C\n');

    print('Result: All devices have task_1 ✅\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 3: Device A marks task as deleted\n');

    print('Device A: UPDATE task_1 SET isDeleted=true');
    print('   ⚠️  Deletion update NO LONGER matches Device A\'s subscription!');
    print('   ⚠️  Device A may not store the update properly');
    print('   ❌ Deletion update NOT synced to Device B (doesn\'t match subscription)');
    print('   ❌ Device B doesn\'t receive deletion update');
    print('   ❌ Device B cannot relay what it doesn\'t have to Device C');
    print('   ❌ Device C never receives deletion update\n');

    print('Result: Inconsistent state across devices! ❌\n');

    print('─────────────────────────────────────────────────────────────────\n');
    print('STEP 4: Observers on each device\n');

    print('Device A Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   📊 Result: 0 tasks (task_1 is deleted)\n');

    print('Device B Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   📊 Result: 1 task (task_1 STILL ACTIVE!) ❌');
    print('   ⚠️  Device B never received deletion update\n');

    print('Device C Observer: SELECT * FROM tasks WHERE isDeleted != true');
    print('   📊 Result: 1 task (task_1 STILL ACTIVE!) ❌');
    print('   ⚠️  Device C never received deletion update\n');

    print('❌ Devices show INCONSISTENT UI:');
    print('   - Device A: 0 tasks (correct)');
    print('   - Device B: 1 task (WRONG - shows deleted task)');
    print('   - Device C: 1 task (WRONG - shows deleted task)\n');

    print('═══════════════════════════════════════════════════════════════════');
    print('CONCLUSION: Incorrect pattern causes data inconsistency! ❌');
    print('═══════════════════════════════════════════════════════════════════\n');

    print('🔧 FIX: Change subscriptions to include ALL documents:');
    print('   SELECT * FROM tasks (no isDeleted filter)');
    print('   Filter only in observers for UI display\n');
  }
}

// ============================================================================
// PATTERN 4: Comparison Table
// ============================================================================

class PatternComparison {
  static void printComparison() {
    print('═══════════════════════════════════════════════════════════════════');
    print('COMPARISON: Correct vs Incorrect Soft-Delete Patterns');
    print('═══════════════════════════════════════════════════════════════════\n');

    print('┌─────────────────────────────────────────────────────────────────┐');
    print('│ Component          │ Correct Pattern       │ Incorrect Pattern │');
    print('├─────────────────────────────────────────────────────────────────┤');
    print('│ Subscription       │ No deletion filter    │ With deletion     │');
    print('│                    │ SELECT * FROM tasks   │ filter (WRONG!)   │');
    print('│                    │                       │                   │');
    print('│ Observer (UI)      │ With deletion filter  │ With deletion     │');
    print('│                    │ WHERE isDeleted!=true │ filter            │');
    print('│                    │                       │                   │');
    print('│ execute() (logic)  │ With deletion filter  │ With deletion     │');
    print('│                    │ WHERE isDeleted!=true │ filter            │');
    print('│                    │                       │                   │');
    print('│ Deleted docs       │ Stored locally ✅     │ Not stored ❌     │');
    print('│ stored?            │                       │                   │');
    print('│                    │                       │                   │');
    print('│ Relay to peers?    │ Yes ✅                │ No ❌             │');
    print('│                    │                       │                   │');
    print('│ Multi-hop sync?    │ Works ✅              │ Broken ❌         │');
    print('│                    │                       │                   │');
    print('│ Data consistency?  │ Consistent ✅         │ Inconsistent ❌   │');
    print('└─────────────────────────────────────────────────────────────────┘\n');

    print('KEY TAKEAWAY:');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('Subscriptions declare data needs to the mesh network.');
    print('Filter deleted docs ONLY in observers (UI) and execute() (logic).');
    print('NEVER filter deletion flags in subscriptions!\n');
  }
}

// ============================================================================
// Main Example
// ============================================================================

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Soft-Delete Pattern with Multi-Hop Relay - Best Practices');
  print('═══════════════════════════════════════════════════════════════════\n');

  // Initialize Ditto (simplified)
  final ditto = await Ditto.open(
    identity: DittoIdentity.onlinePlayground(
      appID: 'your-app-id',
      token: 'your-token',
    ),
    persistenceDirectory: '/tmp/ditto',
  );

  print('PART 1: Correct Pattern Demonstration\n');
  print('═══════════════════════════════════════════════════════════════════\n');

  final correctPattern = CorrectLogicalDeletionPattern(ditto);
  await correctPattern.setupCorrectPattern();
  await correctPattern.markTaskAsDeleted('task_123');
  await correctPattern.queryActiveTasks();
  correctPattern.cleanup();

  print('\n═══════════════════════════════════════════════════════════════════\n');
  print('PART 2: Incorrect Pattern Demonstration\n');
  print('═══════════════════════════════════════════════════════════════════\n');

  final incorrectPattern = IncorrectLogicalDeletionPattern(ditto);
  await incorrectPattern.setupIncorrectPattern();
  await incorrectPattern.markTaskAsDeleted('task_456');
  incorrectPattern.cleanup();

  print('\n═══════════════════════════════════════════════════════════════════\n');
  print('PART 3: Multi-Hop Relay Simulations\n');
  print('═══════════════════════════════════════════════════════════════════\n');

  final simulation = MultiHopRelaySimulation();
  await simulation.demonstrateCorrectPattern();
  await Future.delayed(Duration(seconds: 2));
  await simulation.demonstrateIncorrectPattern();

  print('\n═══════════════════════════════════════════════════════════════════\n');
  print('PART 4: Pattern Comparison\n');
  print('═══════════════════════════════════════════════════════════════════\n');

  PatternComparison.printComparison();

  // Cleanup
  await ditto.close();

  print('═══════════════════════════════════════════════════════════════════');
  print('KEY TAKEAWAYS:');
  print('═══════════════════════════════════════════════════════════════════');
  print('1. ✅ Subscriptions: NO deletion flag filter (enables relay)');
  print('2. ✅ Observers: YES deletion flag filter (UI display)');
  print('3. ✅ execute(): YES deletion flag filter (app logic)');
  print('4. ⚠️  Common mistake: Filtering isDeleted in subscription');
  print('5. ❌ Result: Deleted docs don\'t propagate through mesh');
  print('6. ✅ Fix: Subscribe broadly, filter only in observers/queries');
  print('═══════════════════════════════════════════════════════════════════\n');
}
