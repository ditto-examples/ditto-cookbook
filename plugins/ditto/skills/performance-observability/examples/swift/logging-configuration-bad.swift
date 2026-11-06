// Logging and diagnostics anti-patterns for Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0).
//
// Each function compiles, but logs startup with the wrong settings, slows the
// app down, or loses diagnostics. The corrected versions are in
// logging-configuration-good.swift.
//
// Anti-patterns: 1. the level set only after open; 2. verbose logging in
// production; 3. a callback that captures a session, as if it ended with the
// instance; 4. blocking work in the log callback; 5. exporting to a fixed path;
// 6. a long-lived observer on system:system_info; 7. changing log rotation.
//
// Guide: § Logging in Swift, § Logging, § Log levels, § Forwarding logs to your own pipeline, § On-disk logs and exporting them, § System Virtual Collections

import DittoSwift
import Foundation

private let config = DittoConfig(databaseID: "YOUR_DATABASE_ID", connect: .smallPeersOnly())

/// ❌ BAD: The level is set after Ditto.open(config:), so startup is logged
/// with the default level (.info) instead of your settings. Configure
/// DittoLogger first; it works before any instance exists.
func configureLoggingTooLate() async throws -> Ditto {
    let ditto = try await Ditto.open(config: config)
    DittoLogger.minimumLogLevel = .debug
    return ditto
}

/// ❌ BAD: Verbose logging can significantly slow down replication. Use
/// .warning in production; the on-disk logs already contain debug-level entries
/// for support.
func verboseEverywhere() {
    DittoLogger.minimumLogLevel = .verbose
}

/// ❌ BAD: The callback is process-wide and stays installed after the session's
/// instance shuts down. This one keeps the session (and its pipeline) alive
/// after sign-out and keeps reporting into it. Install one callback for the app,
/// or remove it with setCustomLogCallback(nil).
final class SessionWithCapturedCallback {
    var lines: [String] = []
    var ditto: Ditto?

    func signIn() async throws {
        DittoLogger.setCustomLogCallback { _, message in self.lines.append(message) } // captures self
        ditto = try await Ditto.open(config: config)
    }

    func signOut() {
        ditto = nil // the instance shuts down; the callback, and self, stay
    }
}

/// ❌ BAD: The callback runs for every log event it receives. Synchronous file
/// I/O per event blocks the thread that logs. Filter by level and hand lines to
/// a buffered logger.
func installBlockingCallback(logFile: URL) {
    DittoLogger.setCustomLogCallback { level, message in
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data("\(level) \(message)\n".utf8))
            try? handle.synchronize()
            try? handle.close()
        }
    }
}

/// ❌ BAD: export(to:) throws "File exists (os error 17)" when the file already
/// exists, so the second export fails. Use a new, timestamped path.
func exportToFixedPath(directory: URL) async throws -> UInt64 {
    try await DittoLogger.export(to: directory.appendingPathComponent("ditto-logs.jsonl.gz"))
}

/// ❌ BAD: Observers on system:system_info fire often even when nothing
/// changed. Query system collections with execute when you need them.
func observeSystemInfo(_ ditto: Ditto) throws -> DittoStoreObserver {
    try ditto.store.registerObserver(query: "SELECT key, value FROM system:system_info WHERE namespace = 'core'") { result in
        print("core:", result.items.count)
    }
}

/// ❌ BAD: Leave the ROTATING_LOG_FILE_* parameters at their defaults unless
/// Ditto support advises otherwise.
func enlargeLogRotation(_ ditto: Ditto) async throws {
    try await ditto.store.execute(query: "ALTER SYSTEM SET ROTATING_LOG_FILE_MAX_SIZE_MB = 5")
}
