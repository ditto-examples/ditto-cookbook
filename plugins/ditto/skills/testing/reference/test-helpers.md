# Test Helper for a Local Store

What a local-store test helper does, from `§ A Test Helper for a Local Store`, for every SDK. The helper for each SDK is `local-store-test-helper` in `../examples/<sdk>/` and the *A local-store test helper in <SDK>* section of its page.

## A Test Helper for a Local Store

Write one helper that every local store test uses. It:

1. Creates a new temporary directory for each test and opens a small-peers-only instance (the default connection mode) in it, with any UUID as the Database ID.
2. Passes the same system parameters that your app passes in its `DittoConfig`, and runs the same startup code that creates your app's indexes.
3. Never starts sync, so it needs no license token and no network and can run in CI.
4. Closes the instance and deletes the directory when the test ends, also when it fails (on Flutter 5.2.0, after the last test of the file: `§ A local-store test helper in Flutter`).

```sql
-- A first test: a new store is empty
SELECT COUNT(*) AS n FROM orders
-- Expected: one row, {"n": 0}
```

A real Ditto instance needs the SDK's native library, so tests that open Ditto run where the SDK runs: a desktop or device target in Flutter, a simulator or macOS in Swift, an emulator or device in Kotlin, and Node.js or a browser in JavaScript. Tests that use only a mock of your own interface run without it.

The examples in the following sections show each test as the statements it runs and the result it expects. They define the statements under test inline so that each one is complete; in your suite, call your app's repository functions instead, so that a test fails when the app code changes. The helper and the tests for each SDK: [A local-store test helper in Flutter](../../guide/reference/best-practices/platforms/flutter.md#a-local-store-test-helper-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#a-local-store-test-helper-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#a-local-store-test-helper-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#a-local-store-test-helper-in-swift).
