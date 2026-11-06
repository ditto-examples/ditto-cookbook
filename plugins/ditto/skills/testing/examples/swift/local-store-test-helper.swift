// Ditto SDK: 5.2.0 (Swift, DittoSwift 5.2.0, Swift Testing)
//
// A local-store test helper and a first test. Put it in a test target that
// depends on DittoSwift, and run it with `swift test` or `xcodebuild test`.
// withTestDitto opens a small-peers-only instance in a new temporary directory,
// never starts sync, passes the instance to the test, and afterwards releases
// it (which shuts it down: DittoSwift 5.2.0 has no close()) and deletes the
// directory, also when the test throws. Do not keep a reference to the Ditto
// passed to body after it returns.
//
// What each test checks, as DQL and expected results, is in
// ../../reference/test-helpers.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § A Test Helper for a Local Store, § A local-store test helper in Swift

// Tests/OrdersTests/TestDitto.swift
import DittoSwift
import Foundation
import Testing

/// Opens a Ditto instance for one test, runs body with it, then shuts it down
/// and deletes its directory. Sync is never started, so no license token or
/// network connection is needed.
func withTestDitto<T>(
    systemParameters: [String: DittoSystemParameterValue] = [:],
    configure: ((Ditto) async throws -> Void)? = nil,
    _ body: (Ditto) async throws -> T
) async throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ditto-test-\(UUID().uuidString)")
    var ditto: Ditto? = try await Ditto.open(config: DittoConfig(
        // Any UUID works for local tests; each test gets its own directory.
        databaseID: "00000000-0000-4000-8000-000000000001",
        connect: .smallPeersOnly(),
        persistenceDirectory: directory,
        // The same parameters as the app's DittoConfig (SDK 5.2+).
        systemParameters: systemParameters
    ))
    func shutDown() {
        ditto = nil // The last reference: shuts the instance down.
        try? FileManager.default.removeItem(at: directory) // Best effort.
    }
    do {
        try await configure?(ditto!) // Create the app's indexes, as at app startup.
        let result = try await body(ditto!)
        shutDown()
        return result
    } catch {
        shutDown()
        throw error
    }
}

@Test func aNewStoreIsEmpty() async throws {
    try await withTestDitto { ditto in
        let result = try await ditto.store.execute(query: "SELECT COUNT(*) AS n FROM orders")
        #expect(result.items.first?.value["n"] as? Int == 0)
    }
}
