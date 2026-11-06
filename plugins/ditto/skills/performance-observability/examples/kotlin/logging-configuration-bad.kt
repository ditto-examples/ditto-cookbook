// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// Logging and Diagnostics Configuration (Anti-Patterns)
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Logging
// - § Logging in Kotlin
// - § Forwarding logs to your own pipeline
// - § On-disk logs and exporting them
// - § System Virtual Collections
//
// Each function compiles, but loses diagnostics or slows the app.
// Corrected versions are in logging-configuration-good.kt.
//
// ANTI-PATTERNS DEMONSTRATED:
// 1. ❌ Log level set only after DittoFactory.create (startup logged with defaults)
// 2. ❌ Verbose logging in production
// 3. ❌ Log forwarding collected in a short-lived scope, so it silently stops
// 4. ❌ Slow, blocking work inside the log collector
// 5. ❌ Exporting logs to a fixed path that may already exist
// 6. ❌ Long-lived observer on system:system_info
// 7. ❌ Changing on-disk log rotation parameters without guidance

import com.ditto.kotlin.*
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// ANTI-PATTERN 1: Level set only after DittoFactory.create
/** ❌ BAD: Startup is logged with the default settings. Configure DittoLogger first. */
fun openThenConfigureLogging(config: DittoConfig): Ditto {
    val ditto = DittoFactory.create(config)
    DittoLogger.minimumLogLevel = DittoLogLevel.Debug
    return ditto
}

// ANTI-PATTERN 2: Verbose logging in production
/** ❌ BAD: Verbose logging can significantly slow down replication. */
fun enableVerboseForever() {
    DittoLogger.minimumLogLevel = DittoLogLevel.Verbose
}

// ANTI-PATTERN 3: Forwarding in a short-lived scope
/**
 * ❌ BAD: The collector runs in the scope of one screen, so forwarding stops
 * when the screen goes away, and warnings logged later never reach the app's
 * pipeline. Collect in a scope that lives as long as the app.
 */
fun forwardLogsFromScreen(screenScope: CoroutineScope, report: (String) -> Unit) {
    screenScope.launch {
        DittoLogger.observeLogEvents().collect { event -> report(event.message) }
    }
}

// ANTI-PATTERN 4: Slow work in the collector
/** ❌ BAD: A blocking upload per log line holds back every following event. */
fun forwardLogsSlowly(scope: CoroutineScope, uploadBlocking: (String) -> Unit): Job =
    scope.launch {
        DittoLogger.observeLogEvents().collect { event -> uploadBlocking(event.message) }
    }

// ANTI-PATTERN 5: Exporting to a fixed path
/**
 * ❌ BAD: The second export to the same path throws DittoException.IoException
 * ("File exists (os error 17)"). Use a new file name for every export.
 */
suspend fun exportLogsToFixedPath(directory: File): ULong =
    DittoLogger.exportToFile(File(directory, "ditto-logs.jsonl.gz").absolutePath)

// ANTI-PATTERN 6: Observer on system:system_info
/**
 * ❌ BAD: Observers on system: collections keep running and fire whenever the
 * collection changes. Query system collections with execute when you need them.
 */
fun observeSystemInfo(ditto: Ditto, scope: CoroutineScope): Job =
    scope.launch {
        ditto.store.observe("SELECT key, value FROM system:system_info WHERE namespace = 'core'") { it.items.size }
            .collect { count -> android.util.Log.d("Diagnostics", "core: $count") }
    }

// ANTI-PATTERN 7: Changing log rotation parameters
/** ❌ BAD: Leave the ROTATING_LOG_FILE_* parameters at their defaults unless Ditto support advises otherwise. */
suspend fun enlargeLogRotation(ditto: Ditto) {
    ditto.store.execute("ALTER SYSTEM SET ROTATING_LOG_FILE_MAX_SIZE_MB = 5")
}
