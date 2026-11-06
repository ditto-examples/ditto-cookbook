// SDK Version: Ditto SDK 5.2.0 (com.ditto:ditto-kotlin 5.2.0)
// Platform: Kotlin (Android)
// Last Updated: 2026-11-06
//
// Logging and Diagnostics Configuration (Correct Patterns)
//
// Guide sections (../../../guide/reference/best-practices/ and knowledge/):
// - § Logging
// - § Logging in Kotlin
// - § Forwarding logs to your own pipeline
// - § On-disk logs and exporting them
// - § System Virtual Collections
// - § Long-running requests (SDK 5.1+)
// - § DittoConfig in Kotlin
// - § Support bundles (SDK 5.2+)
//
// Facts:
// - DittoLogger is an object. It works before the first DittoFactory.create, so
//   configure it first and startup is logged with your settings.
// - On Android, the SDK writes its log to logcat with the tag "Ditto".
// - DittoLogger.observeLogEvents() is a Flow of log events; collect it in a
//   scope that lives as long as you want logs forwarded.
// - DittoLogger.exportToFile(path) throws DittoException.IoException
//   ("File exists (os error 17)") when the file exists.
//
// PATTERNS DEMONSTRATED:
// 1. ✅ DittoLogger -> DittoFactory.create startup order
// 2. ✅ Forwarding warnings and errors to the app's pipeline
// 3. ✅ Exporting on-disk logs for a "Send diagnostics" action
// 4. ✅ Temporary verbose logging for a targeted investigation
// 5. ✅ System parameters passed in DittoConfig on every open, and checked
// 6. ✅ On-demand diagnostics snapshot from system: virtual collections
// 7. ✅ Support bundle created on the device (SDK 5.2+)

import android.util.Log
import com.ditto.kotlin.*
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.json.JSONObject

// ============================================================================
// PATTERN 1: Startup order
// ============================================================================

/** ✅ GOOD: Call before DittoFactory.create(). */
fun configureDittoLogging(debug: Boolean) {
    DittoLogger.isEnabled = true
    DittoLogger.minimumLogLevel = if (debug) DittoLogLevel.Debug else DittoLogLevel.Warning
}

// ============================================================================
// PATTERN 2: Forwarding logs
// ============================================================================

/** ✅ GOOD: Forwards warnings and errors until the returned Job is cancelled. Keep the collector short. */
fun forwardDittoLogs(scope: CoroutineScope, report: (String) -> Unit): Job =
    scope.launch {
        DittoLogger.observeLogEvents().collect { event ->
            if (event.level == DittoLogLevel.Error || event.level == DittoLogLevel.Warning) {
                report("[ditto ${event.level}] ${event.message}")
            }
        }
    }

// ============================================================================
// PATTERN 3: Exporting on-disk logs
// ============================================================================

/** ✅ GOOD: A new file name for every export; [directory] must exist (for example context.cacheDir). */
suspend fun exportDittoLogs(directory: File): File {
    val file = File(directory, "ditto-logs-${System.currentTimeMillis()}.jsonl.gz")
    val bytes = DittoLogger.exportToFile(file.absolutePath)
    Log.d("Diagnostics", "Exported $bytes bytes of Ditto logs to ${file.path}")
    return file
}

// ============================================================================
// PATTERN 4: Temporary verbose logging
// ============================================================================

/**
 * ✅ GOOD: Verbose logging can significantly slow down replication. Enable it
 * only for a short, targeted investigation and restore the previous level.
 */
suspend fun <T> withVerboseLogging(investigate: suspend () -> T): T {
    val previous = DittoLogger.minimumLogLevel
    DittoLogger.minimumLogLevel = DittoLogLevel.Verbose
    try {
        return investigate()
    } finally {
        DittoLogger.minimumLogLevel = previous
    }
}

// ============================================================================
// PATTERN 5: System parameters and slow-request warnings
// ============================================================================

/**
 * ✅ GOOD: This app's system parameters, passed in DittoConfig.systemParameters
 * on every open (SDK 5.2+). They are not persisted; Ditto applies them before it
 * starts, and an unknown name or a wrong type makes DittoFactory.create() throw
 * DittoException.ValidationException. Use ALTER SYSTEM only to change a value
 * while the app runs, for example during a support session.
 */
fun appSystemParameters(debug: Boolean): Map<String, Any> = buildMap {
    // Default is 60 seconds; a lower threshold surfaces slow queries early (SDK 5.1+).
    if (debug) put("DQL_SLOW_REQUEST_WARN_SECONDS", 10)
}

fun openWithAppParameters(debug: Boolean): Ditto =
    DittoFactory.create(
        DittoConfig(
            databaseId = "YOUR_DATABASE_ID",
            connect = DittoConfig.Connect.Server(url = "YOUR_SERVER_URL"),
            systemParameters = appSystemParameters(debug),
        ),
    )

/** ✅ GOOD: Confirm an effective value; SHOW returns one row keyed by the lowercase name. */
suspend fun logEffectiveParameter(ditto: Ditto, name: String) {
    val row = ditto.store.execute("SHOW $name") { result -> result.items.first().jsonString() }
    Log.d("Diagnostics", row)
}

// ============================================================================
// PATTERN 6: On-demand diagnostics snapshot
// ============================================================================

/**
 * ✅ GOOD: Query system: virtual collections with execute when you need them
 * (a diagnostics screen, a daily task); later rows of a key overwrite earlier ones.
 */
suspend fun storageSnapshot(ditto: Ditto): Map<String, Any?> =
    ditto.store.execute(
        "SELECT key, value, timestamp FROM system:system_info " +
            "WHERE key LIKE 'fs_%' OR key LIKE 'collection_num_docs%' ORDER BY timestamp ASC",
    ) { result ->
        val snapshot = mutableMapOf<String, Any?>()
        for (item in result.items) {
            val row = JSONObject(item.jsonString())
            snapshot[row.getString("key")] = row.opt("value")
        }
        snapshot
    }

// ============================================================================
// PATTERN 7: Support bundle (SDK 5.2+)
// ============================================================================

/** ✅ GOOD: Create a support bundle and save it; [path] must not exist yet. */
suspend fun saveSupportBundle(ditto: Ditto, path: String) {
    val token = ditto.store.execute("EXECUTE FUNCTION system_request_support_bundle()") { result ->
        result.items.single().value["file"].attachmentToken
    }
    when (val fetched = ditto.store.fetchAttachment(token)) {
        is DittoAttachmentFetchResult.Completed -> fetched.attachment.copyToPath(path)
        is DittoAttachmentFetchResult.Deleted -> Log.w("Diagnostics", "The support bundle was deleted")
    }
}
