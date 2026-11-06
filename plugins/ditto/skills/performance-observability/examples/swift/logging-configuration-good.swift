// Logging and diagnostics configuration for Ditto SDK 5.2.0 (Swift, DittoSwift 5.2.0).
//
// Facts:
// - DittoLogger is a set of static members that work before any Ditto
//   instance exists: configure it before Ditto.open(config:), so that startup
//   is logged with your settings. There is no separate initialization step.
// - DittoLogLevel values: .error, .warning, .info, .debug, .verbose. Defaults:
//   isEnabled = true, minimumLogLevel = .info.
// - setCustomLogCallback(_:) applies to the whole process and stays installed
//   after an instance shuts down; remove it with setCustomLogCallback(nil).
// - export(to:) writes the on-disk logs and throws
//   DittoError.ioError(reason: .alreadyExists(...)) if the file exists.
//
// Patterns: 1. logging before open; 2. forwarding warnings and errors;
// 3. exporting on-disk logs; 4. temporary verbose logging; 5. system
// parameters in DittoConfig on every open (SDK 5.2+); 6. an on-demand
// diagnostics snapshot; 7. a support bundle (SDK 5.2+).
//
// Guide: § Logging in Swift, § Logging, § Forwarding logs to your own pipeline, § On-disk logs and exporting them, § Support bundles (SDK 5.2+), § DittoConfig in Swift, § System Virtual Collections, § Long-running requests (SDK 5.1+)

import DittoSwift
import Foundation

private func fetchAuthToken() async throws -> String { "token" } // your backend

// PATTERN 1: Startup order

/// ✅ GOOD: Call before Ditto.open(config:).
func configureDittoLogging() {
    DittoLogger.isEnabled = true
    // .warning in production, .debug while debugging; never .verbose in production.
    #if DEBUG
    DittoLogger.minimumLogLevel = .debug
    #else
    DittoLogger.minimumLogLevel = .warning
    #endif
}

/// ✅ GOOD: Logging and log forwarding first, then open with the app's system
/// parameters, then everything that depends on the instance (auth, sync).
func startDitto(report: @escaping @Sendable (String) -> Void) async throws -> Ditto {
    configureDittoLogging()
    installDittoLogForwarding(report: report) // Forwards logs emitted while Ditto opens.
    let ditto = try await Ditto.open(config: DittoConfig(
        databaseID: "YOUR_DATABASE_ID",
        connect: .server(url: URL(string: "YOUR_SERVER_URL")!),
        // Not persisted: pass on every open; applied before Ditto starts.
        systemParameters: appSystemParameters()
    ))
    #if DEBUG
    try await logNonDefaultParameters(ditto)
    #endif
    ditto.auth?.expirationHandler = { ditto, _ in
        guard let token = try? await fetchAuthToken() else { return report("No token for Ditto") }
        ditto.auth?.login(token: token, provider: "YOUR_PROVIDER_NAME") { _, error in
            if let error { report("Ditto login failed: \(error.localizedDescription)") } // report, do not crash
        }
    }
    try ditto.sync.start()
    return ditto
}

// PATTERN 2: Forwarding logs to your own pipeline

/// ✅ GOOD: Forwards Ditto warnings and errors. The callback is fast and does
/// not block, because it runs for every log event it receives. Install it once:
/// it stays installed for the whole process.
func installDittoLogForwarding(report: @escaping @Sendable (String) -> Void) {
    DittoLogger.setCustomLogCallback { level, message in
        if level == .error || level == .warning {
            report("[ditto \(level)] \(message)")
        }
    }
}

// PATTERN 3: Exporting on-disk logs

/// ✅ GOOD: Exports the on-disk logs to a new, timestamped file in an existing
/// directory, for example for a "Send diagnostics" action.
func exportDittoLogs(to directory: URL) async throws -> URL {
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let file = directory.appendingPathComponent("ditto-logs-\(timestamp).jsonl.gz")
    let bytes = try await DittoLogger.export(to: file)
    print("Exported \(bytes) bytes of Ditto logs to \(file.path)")
    return file
}

// PATTERN 4: Temporary verbose logging

/// ✅ GOOD: Verbose logging can significantly slow down replication. Enable it
/// only for a short, targeted investigation and restore the previous level.
func withVerboseLogging<T>(_ investigate: () async throws -> T) async rethrows -> T {
    let previous = DittoLogger.minimumLogLevel
    DittoLogger.minimumLogLevel = .verbose
    defer { DittoLogger.minimumLogLevel = previous }
    return try await investigate()
}

// PATTERN 5: System parameters and slow-request warnings

/// ✅ GOOD: This app's system parameters, passed in DittoConfig.systemParameters
/// on every open (SDK 5.2+). They are not persisted; Ditto applies them before
/// it starts, and an unknown name makes Ditto.open throw. Use ALTER SYSTEM on 5.2
/// only to change a value while the app runs.
func appSystemParameters() -> [String: DittoSystemParameterValue] {
    var parameters: [String: DittoSystemParameterValue] = [:]
    #if DEBUG
    // Default is 60 seconds; a lower threshold surfaces slow queries early (SDK 5.1+).
    parameters["DQL_SLOW_REQUEST_WARN_SECONDS"] = 10
    #endif
    return parameters
}

/// ✅ GOOD: Logs the parameters that differ from their defaults, for example
/// after Ditto.open(config:) in debug builds, to confirm the configuration.
func logNonDefaultParameters(_ ditto: Ditto) async throws {
    let result = try await ditto.store.execute(
        query: "SELECT key, value FROM system:system_info WHERE key LIKE 'non_default_system_parameter%'"
    )
    for item in result.items {
        print(item.value["key"] as Any, "=", item.value["value"] as Any)
    }
}

// PATTERN 6: On-demand diagnostics snapshot

/// ✅ GOOD: Query system: virtual collections with execute when needed (a
/// diagnostics screen or a support action). They are local to this device,
/// read only, and never synced. Do not keep observers on system:system_info.
func diagnosticsSnapshot(_ ditto: Ditto) async throws -> [String: [[String: Any?]]] {
    func values(_ query: String) async throws -> [[String: Any?]] {
        try await ditto.store.execute(query: query).items.map { $0.value }
    }
    return [
        "core": try await values("SELECT key, value FROM system:system_info WHERE namespace = 'core' AND key LIKE 'ditto_sdk%'"),
        "logs": try await values("SELECT key, value FROM system:system_info WHERE namespace = 'logs'"),
        "indexes": try await values("SELECT _id FROM system:indexes"),
        "activeRequests": try await values("SELECT _id, text, state, times FROM system:active_requests"),
        // Documents that stopped syncing on this device (SDK 5.2+), for example
        // because a change would have pushed them over the hard size limit.
        "syncDegradations": try await values("SELECT * FROM system:sync_degradations"),
    ]
}

// PATTERN 7: Support bundle (SDK 5.2+)

/// ✅ GOOD: Create a support bundle (on-disk logs, effective configuration, and
/// runtime telemetry in one archive) and save it, for example to share it with
/// Ditto support. SUPPORT_BUNDLE_REQUEST_RATE limits requests (3 per rolling 10
/// minutes by default). The archive contains peer keys of other devices and
/// absolute file paths: review it before sharing it beyond Ditto support.
/// path must not exist yet.
func saveSupportBundle(_ ditto: Ditto, to path: String) async throws {
    let result = try await ditto.store.execute(query: "EXECUTE FUNCTION system_request_support_bundle()")
    guard let token = result.items.first?.value["file"] as? [String: Any?] else { return }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        do {
            try ditto.store.fetchAttachment(token: token.compactMapValues { $0 }, deliverOn: DispatchQueue(label: "bundle")) { event in
                switch event {
                case .completed(let attachment):
                    continuation.resume(with: Result { try attachment.copy(toPath: path) })
                case .deleted:
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                case .progress:
                    break
                @unknown default:
                    break
                }
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
