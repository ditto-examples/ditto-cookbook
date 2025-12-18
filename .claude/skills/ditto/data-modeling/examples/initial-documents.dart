// ============================================================================
// INITIAL DOCUMENTS Pattern
// ============================================================================
//
// This example demonstrates the INITIAL DOCUMENTS feature in Ditto, which
// allows creating device-local default documents that don't sync to other devices.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ INITIAL DOCUMENTS usage for templates
// 2. ✅ Device-local seed data
// 3. ✅ No sync traffic for defaults
// 4. ✅ User settings defaults
// 5. ✅ App configuration templates
// 6. ✅ Onboarding data patterns
// 7. ✅ Initial vs regular document lifecycle
//
// WHAT IS INITIAL DOCUMENTS:
// - Documents created with INITIAL DOCUMENTS exist only on local device
// - Never synced to other devices or peers
// - Perfect for device-specific defaults and templates
// - Can be overwritten with regular INSERT/UPDATE (which WILL sync)
//
// WHEN TO USE:
// - Default user settings/preferences
// - Onboarding templates
// - Device-local configuration
// - Seed data for new users
// - Application defaults
//
// WHEN NOT TO USE:
// - Data that should sync across devices
// - Shared data between users
// - Data that changes frequently
//
// ============================================================================

import 'package:ditto/ditto.dart';

// ============================================================================
// PATTERN 1: User Settings Defaults
// ============================================================================

/// ✅ GOOD: Create default user settings with INITIAL DOCUMENTS
Future<void> initializeUserSettings(Ditto ditto, String userId) async {
  // Create default settings (device-local, no sync)
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO userSettings (
      _id, userId, theme, language, notifications, initialized
    )
    VALUES (:id, :userId, :theme, :language, :notifications, :initialized)
    ''',
    arguments: {
      'id': 'settings_$userId',
      'userId': userId,
      'theme': 'light',
      'language': 'en',
      'notifications': {
        'email': true,
        'push': true,
        'sms': false,
      },
      'initialized': true,
    },
  );

  print('✅ Default user settings initialized (device-local only)');
  print('   No sync traffic generated');
  print('   Settings created: theme=light, language=en');
}

/// User can update settings, which WILL sync
Future<void> updateUserSettings(
  Ditto ditto,
  String userId,
  String theme,
  String language,
) async {
  // Regular UPDATE syncs to other devices
  await ditto.store.execute(
    '''
    UPDATE userSettings
    SET theme = :theme, language = :language
    WHERE _id = :id
    ''',
    arguments: {
      'id': 'settings_$userId',
      'theme': theme,
      'language': language,
    },
  );

  print('✅ User settings updated (this WILL sync to other devices)');
  print('   Settings: theme=$theme, language=$language');
}

// ============================================================================
// PATTERN 2: App Configuration Templates
// ============================================================================

/// ✅ GOOD: Device-local app configuration
Future<void> initializeAppConfig(Ditto ditto) async {
  // Create app configuration (device-local)
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO appConfig (
      _id, maxCacheSize, syncInterval, offlineMode, version
    )
    VALUES (:id, :maxCacheSize, :syncInterval, :offlineMode, :version)
    ''',
    arguments: {
      'id': 'app_config',
      'maxCacheSize': 100 * 1024 * 1024, // 100 MB
      'syncInterval': 30, // 30 seconds
      'offlineMode': false,
      'version': '1.0.0',
    },
  );

  print('✅ App configuration initialized (device-local)');
  print('   No bandwidth used for default configuration');
}

// ============================================================================
// PATTERN 3: Onboarding Templates
// ============================================================================

/// ✅ GOOD: Create onboarding tasks for new users
Future<void> createOnboardingTasks(Ditto ditto, String userId) async {
  // Task 1: Complete profile
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO tasks (
      _id, userId, title, description, done, isOnboarding
    )
    VALUES (:id, :userId, :title, :description, :done, :isOnboarding)
    ''',
    arguments: {
      'id': 'onboarding_task_1_$userId',
      'userId': userId,
      'title': 'Complete your profile',
      'description': 'Add your name, photo, and bio',
      'done': false,
      'isOnboarding': true,
    },
  );

  // Task 2: Connect with friends
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO tasks (
      _id, userId, title, description, done, isOnboarding
    )
    VALUES (:id, :userId, :title, :description, :done, :isOnboarding)
    ''',
    arguments: {
      'id': 'onboarding_task_2_$userId',
      'userId': userId,
      'title': 'Connect with friends',
      'description': 'Find and follow your friends',
      'done': false,
      'isOnboarding': true,
    },
  );

  // Task 3: Create first post
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO tasks (
      _id, userId, title, description, done, isOnboarding
    )
    VALUES (:id, :userId, :title, :description, :done, :isOnboarding)
    ''',
    arguments: {
      'id': 'onboarding_task_3_$userId',
      'userId': userId,
      'title': 'Create your first post',
      'description': 'Share something with your network',
      'done': false,
      'isOnboarding': true,
    },
  );

  print('✅ Onboarding tasks created (device-local, not synced)');
  print('   User sees tasks immediately without network request');
}

/// Mark onboarding task as done (this WILL sync)
Future<void> completeOnboardingTask(Ditto ditto, String taskId) async {
  // Regular UPDATE syncs to cloud (for progress tracking)
  await ditto.store.execute(
    '''
    UPDATE tasks
    SET done = true, completedAt = :completedAt
    WHERE _id = :taskId
    ''',
    arguments: {
      'taskId': taskId,
      'completedAt': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Onboarding task completed (synced to cloud for tracking)');
}

// ============================================================================
// PATTERN 4: Placeholder/Template Documents
// ============================================================================

/// ✅ GOOD: Create placeholder documents for empty states
Future<void> createPlaceholderPosts(Ditto ditto, String userId) async {
  // Placeholder post for empty feed
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO posts (
      _id, authorId, content, isPlaceholder
    )
    VALUES (:id, :authorId, :content, :isPlaceholder)
    ''',
    arguments: {
      'id': 'placeholder_post_1_$userId',
      'authorId': 'system',
      'content': 'Welcome to the app! Your feed will show posts from people you follow.',
      'isPlaceholder': true,
    },
  );

  print('✅ Placeholder post created (device-local, not synced)');
  print('   User sees helpful message on first launch');
}

// ============================================================================
// PATTERN 5: Feature Discovery Prompts
// ============================================================================

/// ✅ GOOD: Feature discovery cards (device-local hints)
Future<void> createFeatureDiscoveryCards(Ditto ditto, String userId) async {
  // Feature 1: Search
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO featureCards (
      _id, userId, featureName, title, description, dismissed
    )
    VALUES (:id, :userId, :featureName, :title, :description, :dismissed)
    ''',
    arguments: {
      'id': 'feature_search_$userId',
      'userId': userId,
      'featureName': 'search',
      'title': 'Discover Content',
      'description': 'Tap the search icon to find posts, users, and topics',
      'dismissed': false,
    },
  );

  // Feature 2: Offline Mode
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO featureCards (
      _id, userId, featureName, title, description, dismissed
    )
    VALUES (:id, :userId, :featureName, :title, :description, :dismissed)
    ''',
    arguments: {
      'id': 'feature_offline_$userId',
      'userId': userId,
      'featureName': 'offline',
      'title': 'Works Offline',
      'description': 'This app works even without internet connection',
      'dismissed': false,
    },
  );

  print('✅ Feature discovery cards created (device-local)');
  print('   No sync traffic for UI hints');
}

/// Dismiss feature card (sync this to prevent showing on other devices)
Future<void> dismissFeatureCard(Ditto ditto, String cardId) async {
  // Regular UPDATE syncs dismissal state
  await ditto.store.execute(
    '''
    UPDATE featureCards
    SET dismissed = true, dismissedAt = :dismissedAt
    WHERE _id = :cardId
    ''',
    arguments: {
      'cardId': cardId,
      'dismissedAt': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Feature card dismissed (synced to other devices)');
}

// ============================================================================
// PATTERN 6: Local Cache Priming
// ============================================================================

/// ✅ GOOD: Pre-populate frequently used data
Future<void> primeLocalCache(Ditto ditto) async {
  // Common categories (device-local, reduce initial load time)
  final categories = [
    {'id': 'cat_tech', 'name': 'Technology', 'icon': 'tech_icon'},
    {'id': 'cat_health', 'name': 'Health', 'icon': 'health_icon'},
    {'id': 'cat_travel', 'name': 'Travel', 'icon': 'travel_icon'},
    {'id': 'cat_food', 'name': 'Food', 'icon': 'food_icon'},
  ];

  for (final category in categories) {
    await ditto.store.execute(
      '''
      INITIAL DOCUMENTS
      INSERT INTO categories (_id, name, icon, isDefault)
      VALUES (:id, :name, :icon, :isDefault)
      ''',
      arguments: {
        'id': category['id']!,
        'name': category['name']!,
        'icon': category['icon']!,
        'isDefault': true,
      },
    );
  }

  print('✅ Local cache primed with ${categories.length} categories');
  print('   App shows categories immediately, syncs updates later');
}

// ============================================================================
// PATTERN 7: Tutorial Progress Tracking
// ============================================================================

/// ✅ GOOD: Track tutorial progress locally first
Future<void> initializeTutorialProgress(Ditto ditto, String userId) async {
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO tutorialProgress (
      _id, userId, currentStep, totalSteps, completed, skipped
    )
    VALUES (:id, :userId, :currentStep, :totalSteps, :completed, :skipped)
    ''',
    arguments: {
      'id': 'tutorial_$userId',
      'userId': userId,
      'currentStep': 0,
      'totalSteps': 5,
      'completed': false,
      'skipped': false,
    },
  );

  print('✅ Tutorial progress initialized (device-local)');
}

/// Update tutorial progress (sync for cross-device resume)
Future<void> updateTutorialProgress(
  Ditto ditto,
  String userId,
  int currentStep,
) async {
  await ditto.store.execute(
    '''
    UPDATE tutorialProgress
    SET currentStep = :currentStep, lastUpdatedAt = :timestamp
    WHERE _id = :id
    ''',
    arguments: {
      'id': 'tutorial_$userId',
      'currentStep': currentStep,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print('✅ Tutorial progress updated (synced for cross-device resume)');
}

// ============================================================================
// PATTERN 8: Sample Data for Empty States
// ============================================================================

/// ✅ GOOD: Show sample data until real data syncs
Future<void> createSampleProjects(Ditto ditto, String userId) async {
  // Sample project 1
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO projects (
      _id, userId, name, description, isSample
    )
    VALUES (:id, :userId, :name, :description, :isSample)
    ''',
    arguments: {
      'id': 'sample_project_1_$userId',
      'userId': userId,
      'name': 'My First Project',
      'description': 'This is a sample project. Create your own or delete this one.',
      'isSample': true,
    },
  );

  // Sample project 2
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO projects (
      _id, userId, name, description, isSample
    )
    VALUES (:id, :userId, :name, :description, :isSample)
    ''',
    arguments: {
      'id': 'sample_project_2_$userId',
      'userId': userId,
      'name': 'Example Tasks',
      'description': 'Sample project with tasks to help you get started.',
      'isSample': true,
    },
  );

  print('✅ Sample projects created (device-local)');
  print('   User sees content immediately, avoiding empty state');
}

/// Delete sample data when user creates real data
Future<void> cleanupSampleData(Ditto ditto, String userId) async {
  // Delete sample projects
  await ditto.store.execute(
    'DELETE FROM projects WHERE userId = :userId AND isSample = true',
    arguments: {'userId': userId},
  );

  print('✅ Sample data cleaned up');
  print('   User has created real data, samples removed');
}

// ============================================================================
// PATTERN 9: Device-Specific Preferences
// ============================================================================

/// ✅ GOOD: Device-specific settings (never sync)
Future<void> initializeDevicePreferences(Ditto ditto, String deviceId) async {
  await ditto.store.execute(
    '''
    INITIAL DOCUMENTS
    INSERT INTO devicePreferences (
      _id, deviceId, soundEnabled, hapticEnabled, brightness
    )
    VALUES (:id, :deviceId, :soundEnabled, :hapticEnabled, :brightness)
    ''',
    arguments: {
      'id': 'device_prefs_$deviceId',
      'deviceId': deviceId,
      'soundEnabled': true,
      'hapticEnabled': true,
      'brightness': 0.8,
    },
  );

  print('✅ Device preferences initialized (device-local only)');
  print('   These settings stay on this device');
}

// ============================================================================
// PATTERN 10: Lifecycle Comparison: INITIAL vs Regular
// ============================================================================

/// Demonstrate lifecycle differences
Future<void> demonstrateLifecycleDifference(Ditto ditto, String userId) async {
  print('');
  print('✅ INITIAL DOCUMENTS vs Regular Documents:');
  print('');
  print('Feature               | INITIAL DOCUMENTS    | Regular INSERT');
  print('----------------------|----------------------|------------------');
  print('Sync to other devices | NO                   | YES');
  print('Sync traffic          | Zero                 | Full document');
  print('Can be overwritten    | YES (with UPDATE)    | YES (with UPDATE)');
  print('Visible to other users| NO                   | YES (if queried)');
  print('Use case              | Defaults, templates  | Real user data');
  print('');
  print('Example workflow:');
  print('1. App first launch → INITIAL DOCUMENTS creates defaults');
  print('2. User sees defaults immediately (no network wait)');
  print('3. User modifies settings → Regular UPDATE syncs to cloud');
  print('4. User opens app on Device 2 → Synced settings downloaded');
  print('5. Device 2 shows synced settings (not initial defaults)');
}

// ============================================================================
// PATTERN 11: Querying INITIAL vs Synced Documents
// ============================================================================

/// Query shows both initial and synced documents
Future<void> queryAllDocuments(Ditto ditto, String userId) async {
  // Query returns both INITIAL DOCUMENTS and synced documents
  final result = await ditto.store.execute(
    'SELECT * FROM userSettings WHERE userId = :userId',
    arguments: {'userId': userId},
  );

  if (result.items.isEmpty) {
    print('⚠️ No settings found (neither initial nor synced)');
    return;
  }

  final settings = result.items.first.value;
  print('✅ Current settings:');
  print('   Theme: ${settings['theme']}');
  print('   Language: ${settings['language']}');
  print('   (Could be from INITIAL DOCUMENTS or synced from other device)');
}

// ============================================================================
// BEST PRACTICES SUMMARY
// ============================================================================

void printBestPractices() {
  print('');
  print('✅ INITIAL DOCUMENTS Best Practices:');
  print('');
  print('DO:');
  print('  ✓ Use for device-local defaults and templates');
  print('  ✓ Use for onboarding content');
  print('  ✓ Use to reduce initial load time');
  print('  ✓ Combine with regular INSERT/UPDATE for sync');
  print('  ✓ Mark initial docs with flags (e.g., isSample: true)');
  print('');
  print('DON\'T:');
  print('  ✗ Use for data that must sync across devices');
  print('  ✗ Use for shared data between users');
  print('  ✗ Rely on INITIAL DOCUMENTS existing on other devices');
  print('  ✗ Store critical user data as INITIAL DOCUMENTS');
  print('');
  print('Common Pattern:');
  print('  1. INITIAL DOCUMENTS on first launch (local defaults)');
  print('  2. User modifies data → Regular UPDATE (syncs to cloud)');
  print('  3. Other devices receive synced data (not initial defaults)');
}
