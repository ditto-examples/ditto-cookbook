// Ditto SDK: 5.2.0 (Swift, DittoSwift 5.2.0)
//
// UUIDs, display numbers, and fixed-precision UTC timestamps in Swift
//
// The DQL that uses these values is in ../id-generation-patterns.sql and
// ../timestamps.sql. The same helpers for the other SDKs are in
// examples/<sdk>/ids-and-timestamps.* and on each SDK page.
//
// Swift details (Note (SDK 5.1.0 and 5.2.0)):
// - UUID().uuidString is uppercase, and a UUID passed as an argument is stored
//   as that uppercase string; most other platforms produce lowercase UUIDs.
// - A Date passed as an argument is stored as an object
//   ({"__type": "date_epoch_timestamp", "__value": ...}), not as a time that DQL
//   date functions or string comparisons can use. Pass a string.
//
// Guide: § Document IDs, § Timestamps, § IDs and Timestamps in Swift

import DittoSwift
import Foundation

/// ISO 8601 UTC string with exactly millisecond precision, for example
/// "2026-10-08T10:30:00.123Z", also for whole seconds ("...00.000Z").
/// ISO strings sort chronologically as text only when they share one format,
/// so use this one helper for every timestamp field that is sorted or compared.
func utcTimestamp(_ date: Date = Date()) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

/// A random (version 4) UUID in lowercase, such as
/// "3f0c9a8e-5b1d-4c2a-9e7f-1a2b3c4d5e6f".
func newID() -> String {
    UUID().uuidString.lowercased()
}

/// A display label, not an identifier: uniqueness is not guaranteed across
/// devices, so never use it as _id or as a lookup key.
func displayNumber(terminalCode: String, localSequence: Int) -> String {
    let digits = String(localSequence)
    return "\(terminalCode)-\(String(repeating: "0", count: max(0, 4 - digits.count)))\(digits)"
}

/// ✅ GOOD: UUID v4 as _id, UTC timestamp from the helper.
func createOrder(_ ditto: Ditto, storeID: String) async throws -> String {
    let orderID = newID()
    try await ditto.store.execute(
        query: "INSERT INTO orders DOCUMENTS (:order)",
        arguments: ["order": [
            "_id": orderID,
            "storeId": storeID,
            "status": "open",
            "createdAt": utcTimestamp(),
        ]]
    )
    return orderID
}

/// ✅ GOOD: A human-readable number next to the UUID.
func createOrderWithLabel(_ ditto: Ditto, terminalCode: String, localSequence: Int) async throws {
    try await ditto.store.execute(
        query: "INSERT INTO orders DOCUMENTS (:order)",
        arguments: ["order": [
            "_id": newID(),
            "displayNumber": displayNumber(terminalCode: terminalCode, localSequence: localSequence),
            "createdAt": utcTimestamp(),
        ]]
    )
}

/// ❌ BAD: Collides when two offline devices create the 42nd order of the day.
func badSequentialID(dailyCount: Int) -> String { "order-\(dailyCount)" }

/// ❌ BAD: Collides when two devices write within the same millisecond.
func badTimestampID() -> String { "order-\(Int(Date().timeIntervalSince1970 * 1000))" }

/// ❌ BAD: The Date is stored as an object, and "\(Date())" is not ISO 8601
/// ("2026-10-08 10:30:00 +0000"): neither works with DQL date functions or in
/// comparisons.
func markReadyIncorrectly(_ ditto: Ditto, orderID: String) async throws {
    try await ditto.store.execute(
        query: "UPDATE orders SET readyAt = :readyAt, readyLabel = :label WHERE _id = :id",
        arguments: ["id": orderID, "readyAt": Date(), "label": "\(Date())"]
    )
}
