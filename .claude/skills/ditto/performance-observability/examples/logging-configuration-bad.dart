// ============================================================================
// Logging Configuration Anti-Patterns
// ============================================================================
//
// This example demonstrates common logging configuration mistakes that make
// debugging difficult and miss critical diagnostic information.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Setting log level AFTER Ditto.open()
// 2. ❌ No environment differentiation
// 3. ❌ Logging disabled in production
// 4. ❌ Wrong log level for environment
// 5. ❌ No log file access for diagnostics
// 6. ❌ Verbose logging in production
//
// WHY THESE ARE PROBLEMS:
// - Missing startup diagnostics
// - Cannot debug production issues
// - Performance degradation
// - Wasted resources
//
// SOLUTION: See logging-configuration-good.dart for correct patterns
//
// ============================================================================

import 'package:ditto/ditto.dart';
import 'dart:io';

// ============================================================================
// ANTI-PATTERN 1: Setting Log Level AFTER Ditto.open()
// ============================================================================

/// ❌ BAD: Configure logging after initialization
class LogLevelAfterInitBad {
  Future<Ditto> initializeDitto() async {
    print('❌ Initializing Ditto...');

    // ❌ BAD: Initialize Ditto FIRST
    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    print('  ✅ Ditto initialized');

    // ❌ BAD: Set log level AFTER initialization
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;
    DittoLogger.enabled = true;

    print('  ❌ Log level set AFTER initialization (too late!)');

    // 🚨 PROBLEMS:
    // - Initialization logs NOT captured
    // - SDK version not logged
    // - Transport configuration not logged
    // - Database migration not logged
    // - Startup errors not captured
    // - Cannot debug initialization issues

    print('');
    print('🚨 Missing from logs:');
    print('   • SDK version');
    print('   • Persistence directory setup');
    print('   • Database initialization');
    print('   • Transport configuration');
    print('   • Initial peer discovery');
    print('   • Subscription setup');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// ANTI-PATTERN 2: No Environment Differentiation
// ============================================================================

/// ❌ BAD: Same log level for all environments
class NoEnvironmentDifferentiationBad {
  Future<Ditto> initializeDitto(bool isProduction) async {
    print('❌ Initializing Ditto (${isProduction ? "PRODUCTION" : "DEV"})...');

    // ❌ BAD: Always DEBUG level (regardless of environment)
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;
    DittoLogger.enabled = true;

    print('  ❌ Using DEBUG level in PRODUCTION');

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    // 🚨 PROBLEMS:
    // - Verbose logging in production (performance hit)
    // - Large log files (storage waste)
    // - Potential PII leakage in logs
    // - Increased battery drain
    // - Log files grow quickly (disk space issues)

    print('');
    print('🚨 Production issues with DEBUG level:');
    print('   • Every query logged (performance impact)');
    print('   • Every sync event logged (battery drain)');
    print('   • Log files grow to 100s of MB per day');
    print('   • May log sensitive data');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// ANTI-PATTERN 3: Logging Disabled in Production
// ============================================================================

/// ❌ BAD: No logging in production
class NoProductionLoggingBad {
  Future<Ditto> initializeDitto(bool isProduction) async {
    print('❌ Initializing Ditto (${isProduction ? "PRODUCTION" : "DEV"})...');

    if (isProduction) {
      // ❌ BAD: Disable logging entirely in production
      DittoLogger.enabled = false;
      print('  ❌ Logging DISABLED in production');
    } else {
      DittoLogger.minimumLogLevel = DittoLogLevel.debug;
      DittoLogger.enabled = true;
      print('  ✅ Logging enabled in development');
    }

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    // 🚨 PROBLEMS:
    // - ZERO logs in production
    // - Cannot diagnose production issues
    // - User reports bugs, no logs to investigate
    // - Critical errors go unnoticed
    // - Support team blind to issues

    print('');
    print('🚨 Consequences of no production logging:');
    print('   • User: "App crashes on startup"');
    print('   • Support: "Please reproduce in dev environment"');
    print('   • User: "It only happens in production!"');
    print('   • Support: "We have no logs, cannot help"');
    print('   • Result: Lost user, unresolved bug');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// ANTI-PATTERN 4: Wrong Log Level for Environment
// ============================================================================

/// ❌ BAD: Inappropriate log levels
class WrongLogLevelBad {
  Future<Ditto> initializeDittoDevelopment() async {
    print('❌ Initializing Ditto (DEVELOPMENT)...');

    // ❌ BAD: ERROR level in development (too restrictive)
    DittoLogger.minimumLogLevel = DittoLogLevel.error;
    DittoLogger.enabled = true;

    print('  ❌ Using ERROR level in DEVELOPMENT');

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    // 🚨 PROBLEMS:
    // - Cannot see query execution
    // - Cannot see sync events
    // - Cannot see peer discovery
    // - Difficult to debug issues
    // - Defeats purpose of development environment

    print('');
    print('🚨 Development issues with ERROR level:');
    print('   • Query not working? No logs to debug');
    print('   • Sync not happening? No logs to investigate');
    print('   • Peer not connecting? No logs to diagnose');
    print('   • Developer blind to what\'s happening');

    return ditto;
  }

  Future<Ditto> initializeDittoProduction() async {
    print('❌ Initializing Ditto (PRODUCTION)...');

    // ❌ BAD: DEBUG level in production (too verbose)
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;
    DittoLogger.enabled = true;

    print('  ❌ Using DEBUG level in PRODUCTION');

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    // 🚨 PROBLEMS:
    // - Performance degradation (10-20% slower)
    // - Large log files (100s of MB per day)
    // - Battery drain
    // - Storage issues
    // - May leak sensitive data in logs

    print('');
    print('🚨 Production issues with DEBUG level:');
    print('   • App feels sluggish (logging overhead)');
    print('   • Log files: 500 MB after 1 week');
    print('   • Users complain about battery drain');
    print('   • Logs may contain user data (privacy issue)');

    return ditto;
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// ANTI-PATTERN 5: No Log File Access for Diagnostics
// ============================================================================

/// ❌ BAD: No way to access log files
class NoLogFileAccessBad {
  final Ditto ditto;

  NoLogFileAccessBad(this.ditto);

  Future<void> getUserReportsBug() async {
    print('❌ User reports: "App crashes randomly"');
    print('');

    // ❌ BAD: No log file access implemented
    print('Support team response:');
    print('  "Can you send us the logs?"');
    print('');

    print('Problem:');
    print('  ❌ No log file export feature');
    print('  ❌ Logs buried in app directory');
    print('  ❌ User cannot access logs');
    print('  ❌ Support cannot diagnose issue');
    print('');

    print('Result:');
    print('  • User frustrated');
    print('  • Bug unresolved');
    print('  • Reputation damaged');

    // 🚨 PROBLEMS:
    // - No log export functionality
    // - Users cannot send logs to support
    // - Support team cannot diagnose issues
    // - Bugs remain unresolved
    // - Poor user experience
  }

  Future<void> debugProductionIssue() async {
    print('❌ Debugging production issue...');

    // ❌ BAD: Cannot access log files
    print('  Where are the logs?');
    print('  ❌ No idea (log directory not documented)');
    print('  ❌ Cannot find log files');
    print('  ❌ Cannot read logs');
    print('');

    print('🚨 Cannot diagnose issue without logs');
  }
}

// ============================================================================
// ANTI-PATTERN 6: Verbose Logging in Production
// ============================================================================

/// ❌ BAD: Excessive logging that degrades performance
class VerboseProductionLoggingBad {
  Future<Ditto> initializeDitto() async {
    print('❌ Initializing Ditto with verbose production logging...');

    // ❌ BAD: DEBUG level in production
    DittoLogger.minimumLogLevel = DittoLogLevel.debug;
    DittoLogger.enabled = true;

    final ditto = await Ditto.open(
      identity: DittoIdentity.onlinePlayground(
        appID: 'your-app-id',
        token: 'your-token',
      ),
      persistenceDirectory: await getApplicationDocumentsDirectory(),
    );

    // Simulate production usage
    await _simulateProductionUsage(ditto);

    return ditto;
  }

  Future<void> _simulateProductionUsage(Ditto ditto) async {
    print('');
    print('📱 Simulating production usage with DEBUG logging:');
    print('');

    // Query todos (logs every query)
    await ditto.store.execute('SELECT * FROM todos');
    print('  ❌ Query logged (10+ log lines)');

    // Update todo (logs entire operation)
    await ditto.store.execute(
      'UPDATE todos SET isCompleted = true WHERE _id = :id',
      arguments: {'id': 'todo_1'},
    );
    print('  ❌ Update logged (15+ log lines)');

    // Sync event (logs extensively)
    print('  ❌ Sync event logged (20+ log lines)');

    // Peer discovery (logs every peer)
    print('  ❌ Peer discovery logged (50+ log lines per peer)');

    print('');
    print('🚨 After 1 hour of usage:');
    print('   • 10,000+ log lines generated');
    print('   • 5 MB of log data');
    print('   • Noticeable performance impact');
    print('   • Battery drain');
    print('');

    print('🚨 After 1 week of usage:');
    print('   • 1,000,000+ log lines');
    print('   • 500 MB of log data');
    print('   • App runs out of storage');
    print('   • User complains about slow app');
  }

  Future<String> getApplicationDocumentsDirectory() async {
    return Directory.systemTemp.path;
  }
}

// ============================================================================
// ANTI-PATTERN 7: No Runtime Log Level Adjustment
// ============================================================================

/// ❌ BAD: Cannot adjust log level for debugging
class NoRuntimeAdjustmentBad {
  final Ditto ditto;

  NoRuntimeAdjustmentBad(this.ditto);

  Future<void> userReportsIssue() async {
    print('❌ User reports: "Sync not working"');
    print('');

    print('Support team wants to enable debug logging:');
    print('  ❌ No way to enable debug logging at runtime');
    print('  ❌ Must restart app to change log level');
    print('  ❌ Issue may not reproduce after restart');
    print('  ❌ Cannot capture logs during issue');
    print('');

    print('Result:');
    print('  • Cannot diagnose issue');
    print('  • User must live with broken sync');
    print('  • Poor user experience');

    // 🚨 PROBLEMS:
    // - Cannot enable verbose logging on demand
    // - Must restart app to change log level
    // - Issue may not be reproducible after restart
    // - Missing diagnostic capability
  }
}

// ============================================================================
// Real-World Consequences
// ============================================================================

void printRealWorldConsequences() {
  print('❌ Real-World Consequences of Poor Logging:');
  print('');

  print('SCENARIO 1: Startup Crash (No Startup Logs)');
  print('  • User: "App crashes on launch"');
  print('  • Developer: "Cannot reproduce in dev"');
  print('  • Problem: Log level set AFTER Ditto.open()');
  print('  • Result: No initialization logs, cannot diagnose');
  print('  • Outcome: Bug unresolved, 1-star reviews');
  print('');

  print('SCENARIO 2: Production Sync Issue (No Production Logs)');
  print('  • User: "Data not syncing across devices"');
  print('  • Support: "Send us logs"');
  print('  • Problem: Logging disabled in production');
  print('  • Result: No logs available');
  print('  • Outcome: Issue undiagnosed, user churns');
  print('');

  print('SCENARIO 3: Performance Degradation (Verbose Logging)');
  print('  • Users: "App is slow and drains battery"');
  print('  • Analysis: DEBUG logging in production');
  print('  • Problem: 10-20% performance overhead');
  print('  • Result: App feels sluggish');
  print('  • Outcome: Users switch to competitor');
  print('');

  print('SCENARIO 4: Storage Issues (Large Log Files)');
  print('  • User: "App says storage full"');
  print('  • Investigation: Log files are 2 GB');
  print('  • Problem: DEBUG logging for weeks');
  print('  • Result: App unusable');
  print('  • Outcome: User uninstalls app');
  print('');

  print('CORRECT APPROACH:');
  print('  1. Set log level BEFORE Ditto.open()');
  print('  2. Use WARNING level in production');
  print('  3. Enable file logging for diagnostics');
  print('  4. Provide log export for user support');
  print('  5. Allow runtime log level adjustment');
  print('  6. Use DEBUG only in development');
}

// ============================================================================
// Performance Impact Measurement
// ============================================================================

void printPerformanceImpact() {
  print('❌ Performance Impact of Verbose Logging:');
  print('');

  print('DEBUG Level (Verbose):');
  print('  • CPU overhead: 10-20%');
  print('  • I/O operations: 100s per second');
  print('  • Log file growth: 50-100 MB/day');
  print('  • Battery impact: 5-10% extra drain');
  print('  • User perception: Noticeable lag');
  print('');

  print('WARNING Level (Recommended for Production):');
  print('  • CPU overhead: <1%');
  print('  • I/O operations: Minimal');
  print('  • Log file growth: 1-5 MB/day');
  print('  • Battery impact: Negligible');
  print('  • User perception: No impact');
  print('');

  print('CONCLUSION:');
  print('  • DEBUG level: Development only');
  print('  • WARNING level: Production');
  print('  • INFO level: Staging/beta');
  print('  • Adjust at runtime for debugging specific issues');
}
