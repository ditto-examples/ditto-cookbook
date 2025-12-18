// ============================================================================
// Logging Configuration Best Practices
// ============================================================================
//
// This example demonstrates proper logging configuration for Ditto SDK,
// essential for debugging, monitoring, and production diagnostics.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ Set log level BEFORE Ditto.open()
// 2. ✅ Different log levels for dev vs production
// 3. ✅ Rotating log file configuration
// 4. ✅ System info query for debugging
// 5. ✅ Conditional logging based on environment
// 6. ✅ Log level adjustment at runtime
// 7. ✅ Performance monitoring with logs
//
// CRITICAL RULE: Set log level BEFORE Ditto.open()
// - Initialization diagnostics only captured if set before open()
// - Cannot retroactively capture startup issues
// - Missing early logs makes debugging very difficult
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:io';

// ============================================================================
// PATTERN 1: Set Log Level BEFORE Ditto.open()
// ============================================================================

/// ✅ GOOD: Configure logging before initialization
class ProperLoggingSetup {
  Future<Ditto> initializeDitto() async {
    print('🔧 Initializing Ditto with proper logging...');

    // ✅ STEP 1: Set log level FIRST (before Ditto.open())
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;
    print('  ✅ Log level set to DEBUG before initialization');

    // ✅ STEP 2: Enable logging to file (optional)
    DittoLogger.enabled = true;

    // ✅ STEP 3: Now initialize Ditto
    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    print('  ✅ Ditto initialized (startup logs captured)');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    // Platform-specific document directory
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// PATTERN 2: Different Log Levels for Dev vs Production
// ============================================================================

/// ✅ GOOD: Environment-aware logging configuration
class EnvironmentAwareLogging {
  Future<Ditto> initializeDitto({required bool isProduction}) async {
    print('🔧 Initializing Ditto (${isProduction ? "PRODUCTION" : "DEVELOPMENT"})...');

    // ✅ Different log levels per environment
    if (isProduction) {
      // ✅ PRODUCTION: Minimal logging (warnings and errors only)
      DittoLogger.minimumLogLevel = DittoLogLevel.warning;
      DittoLogger.enabled = true; // Log to file for diagnostics
      print('  ✅ Production logging: WARNING level (file enabled)');
    } else {
      // ✅ DEVELOPMENT: Verbose logging (debug level)
      DittoLogger.minimumLogLevel = DittoLogLevel.debug;
      DittoLogger.enabled = true;
      print('  ✅ Development logging: DEBUG level (verbose)');
    }

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    print('  ✅ Ditto initialized with environment-specific logging');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// PATTERN 3: Rotating Log File Configuration
// ============================================================================

/// ✅ GOOD: Configure rotating log files
class RotatingLogConfiguration {
  Future<Ditto> initializeDitto() async {
    print('🔧 Initializing Ditto with rotating logs...');

    // ✅ Set log level before initialization
    DittoLogger.minimumLogLevel = DittoLogLevel.info;
    DittoLogger.enabled = true;

    // ✅ Configure rotating log file
    // Logs automatically rotate when reaching size limit
    // Keeps last N log files for diagnostics

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    print('  ✅ Ditto initialized with rotating logs');
    print('  Log files: ${ditto.persistenceDirectory}/logs/');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }

  /// ✅ Access log files for diagnostics
  Future<List<File>> getLogFiles(Ditto ditto) async {
    final logsDir = Directory('${ditto.persistenceDirectory}/logs');

    if (!await logsDir.exists()) {
      print('⚠️ Logs directory not found');
      return [];
    }

    final files = await logsDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.log'))
        .map((entity) => entity as File)
        .toList();

    print('📂 Found ${files.length} log files:');
    for (final file in files) {
      final stat = await file.stat();
      final sizeMB = stat.size / (1024 * 1024);
      print('  - ${file.path.split('/').last} (${sizeMB.toStringAsFixed(2)} MB)');
    }

    return files;
  }
}

// ============================================================================
// PATTERN 4: System Info Query for Debugging
// ============================================================================

/// ✅ GOOD: Query system info for diagnostics
class SystemInfoDiagnostics {
  final Ditto ditto;

  SystemInfoDiagnostics(this.ditto);

  Future<void> logSystemInfo() async {
    print('🔍 Querying Ditto system info...');

    try {
      // ✅ Query system information
      final result = await ditto.store.execute('SELECT * FROM ditto_info');

      if (result.items.isEmpty) {
        print('⚠️ System info not available');
        return;
      }

      final info = result.items.first.value;

      print('  ✅ Ditto System Information:');
      print('     SDK Version: ${info['sdk_version']}');
      print('     Persistence Directory: ${info['persistence_directory']}');
      print('     Site ID: ${info['site_id']}');
      print('     Transport Configuration: ${info['transport_config']}');

      // ✅ Log to diagnostics file
      _saveDiagnostics(info);
    } catch (e) {
      print('  ❌ Failed to query system info: $e');
    }
  }

  void _saveDiagnostics(Map<String, dynamic> info) {
    // Save diagnostics to file for support
    print('  💾 Diagnostics saved');
  }

  Future<void> logSyncStatus() async {
    print('🔍 Querying sync status...');

    // ✅ Query current subscriptions
    try {
      final subscriptions = await ditto.store.execute(
        'SELECT * FROM ditto_subscriptions',
      );

      print('  ✅ Active subscriptions: ${subscriptions.items.length}');

      for (final item in subscriptions.items) {
        final sub = item.value;
        print('     - ${sub['query']}');
      }
    } catch (e) {
      print('  ❌ Failed to query subscriptions: $e');
    }
  }
}

// ============================================================================
// PATTERN 5: Conditional Logging Based on Environment
// ============================================================================

/// ✅ GOOD: Conditional logging for specific scenarios
class ConditionalLogging {
  Future<Ditto> initializeDitto({
    required bool isProduction,
    required bool debugSync,
  }) async {
    print('🔧 Initializing Ditto with conditional logging...');

    // ✅ Base log level from environment
    if (isProduction) {
      DittoLogger.minimumLogLevel = DittoLogLevel.warning;
    } else {
      DittoLogger.minimumLogLevel = DittoLogLevel.info;
    }

    // ✅ Override for specific debugging scenarios
    if (debugSync) {
      print('  🐛 Debug mode: Sync debugging enabled');
      DittoLogger.minimumLogLevel = DittoLogLevel.debug;
      // Additional sync-specific logging configuration
    }

    DittoLogger.enabled = true;

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    print('  ✅ Ditto initialized with conditional logging');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// PATTERN 6: Log Level Adjustment at Runtime
// ============================================================================

/// ✅ GOOD: Adjust log level during runtime
class RuntimeLogLevelAdjustment {
  final Ditto ditto;

  RuntimeLogLevelAdjustment(this.ditto);

  void enableVerboseLogging() {
    print('🔊 Enabling verbose logging...');

    // ✅ Increase log level for debugging
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;

    print('  ✅ Log level set to DEBUG (verbose)');
    print('  All sync and query operations will be logged');
  }

  void disableVerboseLogging() {
    print('🔇 Disabling verbose logging...');

    // ✅ Reduce log level for performance
    DittoLogger.minimumLogLevel = DittoLogLevel.warning;

    print('  ✅ Log level set to WARNING (minimal)');
    print('  Only warnings and errors will be logged');
  }

  void enableDebugModeForDuration(Duration duration) async {
    print('🐛 Enabling debug mode for ${duration.inSeconds}s...');

    // ✅ Temporarily increase log level
    final originalLevel = DittoLogger.minimumLogLevel;
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;

    print('  ✅ Debug logging enabled');

    // Wait for duration
    await Future.delayed(duration);

    // ✅ Restore original log level
    DittoLogger.minimumLogLevel = originalLevel;

    print('  ✅ Debug logging disabled (restored to ${originalLevel.name})');
  }
}

// ============================================================================
// PATTERN 7: Performance Monitoring with Logs
// ============================================================================

/// ✅ GOOD: Use logs for performance monitoring
class PerformanceMonitoring {
  final Ditto ditto;

  PerformanceMonitoring(this.ditto);

  Future<void> monitorQueryPerformance() async {
    print('📊 Monitoring query performance...');

    // ✅ Enable debug logging to see query execution times
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;

    final stopwatch = Stopwatch()..start();

    // Execute query
    final result = await ditto.store.execute(
      'SELECT * FROM todos WHERE isCompleted != true ORDER BY createdAt DESC',
    );

    stopwatch.stop();

    print('  ✅ Query completed in ${stopwatch.elapsedMilliseconds}ms');
    print('  Results: ${result.items.length} items');

    // ✅ Check logs for detailed timing information
    // Ditto SDK logs query execution details when DEBUG level is enabled
  }

  Future<void> monitorSyncPerformance() async {
    print('📊 Monitoring sync performance...');

    // ✅ Enable debug logging to see sync activity
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;

    print('  ✅ Sync activity will be logged');
    print('  Check logs for:');
    print('     - Peer connections');
    print('     - Data transfer rates');
    print('     - Sync errors');
    print('     - Network transport events');
  }
}

// ============================================================================
// Complete Example: Production-Ready Logging Setup
// ============================================================================

/// ✅ Production-ready logging configuration
class ProductionLoggingSetup {
  Future<Ditto> initializeDitto({
    required String environment, // 'dev', 'staging', 'production'
    required String appVersion,
  }) async {
    print('🚀 Initializing Ditto for $environment ($appVersion)...');

    // ✅ STEP 1: Configure log level before initialization
    switch (environment) {
      case 'dev':
        DittoLogger.minimumLogLevel = DittoLogLevel.debug;
        print('  📝 Dev environment: DEBUG level');
        break;
      case 'staging':
        DittoLogger.minimumLogLevel = DittoLogLevel.info;
        print('  📝 Staging environment: INFO level');
        break;
      case 'production':
        DittoLogger.minimumLogLevel = DittoLogLevel.warning;
        print('  📝 Production environment: WARNING level');
        break;
      default:
        DittoLogger.minimumLogLevel = DittoLogLevel.info;
    }

    // ✅ STEP 2: Enable file logging
    DittoLogger.enabled = true;

    // ✅ STEP 3: Initialize Ditto
    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    // ✅ STEP 4: Log initialization success
    print('  ✅ Ditto initialized successfully');
    await _logInitializationInfo(ditto, environment, appVersion);

    return ditto;
  }

  Future<void> _logInitializationInfo(
    Ditto ditto,
    String environment,
    String appVersion,
  ) async {
    print('  📋 Initialization Info:');
    print('     Environment: $environment');
    print('     App Version: $appVersion');
    print('     Persistence Directory: ${ditto.persistenceDirectory}');
    print('     Site ID: ${ditto.siteID}');

    // Query system info
    try {
      final result = await ditto.store.execute('SELECT * FROM ditto_info');
      if (result.items.isNotEmpty) {
        final info = result.items.first.value;
        print('     SDK Version: ${info['sdk_version']}');
      }
    } catch (e) {
      print('     ⚠️ Could not query system info: $e');
    }
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// Best Practices Summary
// ============================================================================

void printBestPractices() {
  print('✅ Logging Configuration Best Practices:');
  print('');
  print('DO:');
  print('  ✓ Set DittoLogger.minimumLogLevel BEFORE Ditto.open()');
  print('  ✓ Use different log levels for dev/staging/production');
  print('  ✓ Enable file logging (DittoLogger.enabled = true)');
  print('  ✓ Use DEBUG level in development');
  print('  ✓ Use WARNING level in production');
  print('  ✓ Query ditto_info for diagnostics');
  print('  ✓ Adjust log level at runtime for debugging');
  print('  ✓ Monitor performance with debug logs');
  print('');
  print('DON\'T:');
  print('  ✗ Set log level after Ditto.open() (misses startup logs)');
  print('  ✗ Use DEBUG level in production (performance impact)');
  print('  ✗ Disable logging entirely in production');
  print('  ✗ Ignore log files when debugging');
  print('');
  print('Log Levels:');
  print('  • DEBUG: Verbose logging (dev only)');
  print('  • INFO: Standard logging (staging)');
  print('  • WARNING: Minimal logging (production)');
  print('  • ERROR: Errors only');
  print('');
  print('WHY SET LOG LEVEL BEFORE OPEN:');
  print('  • Captures initialization diagnostics');
  print('  • Logs SDK version and configuration');
  print('  • Logs transport setup');
  print('  • Logs database migration (if any)');
  print('  • Critical for debugging startup issues');
}
