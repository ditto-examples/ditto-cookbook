// Ditto SDK: 5.2.0 (Swift, DittoSwift 5.2.0, Swift Testing)
//
// Several peers in one test process over TCP on 127.0.0.1, and a concurrent-edit
// test. Pass the offline license token in DITTO_LICENSE_TOKEN (for example in the
// test environment variables of the scheme; never commit it); the test is
// skipped without it. The peers shut down when withSyncedPeers returns.
//
// What each test checks, as DQL and expected results, is in
// ../../reference/multi-peer-tests.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § Several peers in one test process, § Several peers in one test in Swift

// Tests/OrdersTests/MultiPeerTests.swift
import DittoSwift
import Foundation
import Testing

/// Offline license token from the test environment (never commit it).
let licenseToken = ProcessInfo.processInfo.environment["DITTO_LICENSE_TOKEN"] ?? ""

struct PeersTimeout: Error { let what: String }

/// Opens count peers that sync with each other over TCP on localhost only:
/// peer 0 listens, the others connect to it. A device accepts at most 6 TCP
/// connections by default, so keep count at 7 or below. The peers shut down
/// when body returns.
func withSyncedPeers<T>(
    _ count: Int,
    port: UInt16 = 4041,
    databaseID: String = "00000000-0000-4000-8000-000000000002",
    token: String = licenseToken,
    _ body: ([Ditto]) async throws -> T
) async throws -> T {
    let directories = (0..<count).map { i in
        FileManager.default.temporaryDirectory.appendingPathComponent("ditto-peer\(i)-\(UUID().uuidString)")
    }
    var peers: [Ditto] = []
    defer {
        peers.removeAll() // The last references: shuts the peers down.
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
    }
    for (i, directory) in directories.enumerated() {
        // All peers of a group use the same database ID; give every group
        // that can run at the same time its own ID and port.
        let ditto = try await Ditto.open(config: DittoConfig(
            databaseID: databaseID, connect: .smallPeersOnly(), persistenceDirectory: directory
        ))
        try ditto.setOfflineOnlyLicenseToken(token)
        ditto.updateTransportConfig { config in
            config.setAllPeerToPeer(enabled: false) // no Bluetooth, LAN, or AWDL
            if i == 0 {
                config.listen.tcp.isEnabled = true
                config.listen.tcp.interfaceIP = "127.0.0.1"
                config.listen.tcp.port = port
            } else {
                config.connect.tcpServers = ["127.0.0.1:\(port)"]
                // A device that only connects still listens on every interface,
                // so bind its listener to this machine: test peers stay off the network.
                config.listen.tcp.isEnabled = true
                config.listen.tcp.interfaceIP = "127.0.0.1"
                config.listen.tcp.port = 0
            }
        }
        try ditto.sync.start()
        peers.append(ditto)
    }
    try await waitUntil("peers connected") { peers.allSatisfy { !$0.presence.graph.remotePeers.isEmpty } }
    return try await body(peers)
}

func waitUntil(_ what: String, timeout: TimeInterval = 15, _ condition: () async throws -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while try await !condition() {
        guard Date() < deadline else { throw PeersTimeout(what: what) }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

/// Stops sync on every peer, runs writes while the peers are disconnected,
/// then reconnects them, so the writes are concurrent.
func whileDisconnected(_ peers: [Ditto], _ writes: () async throws -> Void) async throws {
    for peer in peers { peer.sync.stop() }
    try await waitUntil("peers disconnected") { peers.allSatisfy { $0.presence.graph.remotePeers.isEmpty } }
    try await writes()
    for peer in peers { try peer.sync.start() }
    try await waitUntil("peers reconnected") { peers.allSatisfy { !$0.presence.graph.remotePeers.isEmpty } }
}

/// Waits until query returns the same rows on every peer and until holds for
/// them, then returns the rows (as JSON objects, which compare reliably).
func waitForConvergence(
    _ peers: [Ditto],
    query: String,
    arguments: [String: Any?] = [:],
    until: ([[String: Any]]) -> Bool = { _ in true }
) async throws -> [[String: Any]] {
    var rows: [[String: Any]] = []
    try await waitUntil("peers converged on \(query)") {
        var results: [[[String: Any]]] = []
        for peer in peers {
            let result = try await peer.store.execute(query: query, arguments: arguments)
            results.append(try result.items.map { try JSONSerialization.jsonObject(with: $0.jsonData()) as? [String: Any] ?? [:] })
        }
        let first = results[0] as NSArray
        guard results.allSatisfy({ ($0 as NSArray).isEqual(first) }), until(results[0]) else { return false }
        rows = results[0]
        return true
    }
    return rows
}

@Test(.enabled(if: !licenseToken.isEmpty, "Needs DITTO_LICENSE_TOKEN"))
func concurrentEditsOfDifferentLineItemsBothSurvive() async throws {
    try await withSyncedPeers(2) { peers in
        let (tablet, phone) = (peers[0], peers[1])
        let subscriptions = try peers.map { try $0.sync.registerSubscription(query: "SELECT * FROM orders") }
        defer { subscriptions.forEach { $0.cancel() } }
        try await tablet.store.execute(
            query: "INSERT INTO orders DOCUMENTS (:order)",
            arguments: ["order": ["_id": "order-1", "items": ["item-1": ["productId": "p1", "quantity": 1]]]]
        )
        _ = try await waitForConvergence(peers, query: "SELECT * FROM orders") { $0.count == 1 }

        // The code under test would be the app's repository functions.
        try await whileDisconnected(peers) {
            try await tablet.store.execute(
                query: "UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id", arguments: ["id": "order-1"]
            )
            try await phone.store.execute(
                query: "UPDATE orders SET items.`item-2` = :item WHERE _id = :id",
                arguments: ["id": "order-1", "item": ["productId": "p2", "quantity": 1]]
            )
        }

        let rows = try await waitForConvergence(
            peers, query: "SELECT * FROM orders WHERE _id = :id", arguments: ["id": "order-1"]
        ) { ($0.first?["items"] as? [String: Any])?.count == 2 }
        let items = try #require(rows.first?["items"] as? [String: [String: Any]])
        #expect(items["item-1"]?["quantity"] as? Int == 3)
        #expect(items["item-2"]?["productId"] as? String == "p2")
    }
}
