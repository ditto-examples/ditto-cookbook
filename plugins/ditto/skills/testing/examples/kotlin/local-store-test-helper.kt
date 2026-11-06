// Ditto SDK: 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android)
//
// A local-store test helper and the skeleton of a test class. Tests that open
// Ditto need the SDK's native library, so they run as instrumented tests
// (app/src/androidTest) on an emulator or a device, with JUnit 4 and
// runBlocking: ./gradlew connectedAndroidTest
//
// What each test checks, as DQL and expected results, is in
// ../../reference/test-helpers.md and in the guide's Testing Strategies; the same
// tests for the other SDKs are in examples/<sdk>/ with the same base name.
//
// Guide: § A Test Helper for a Local Store, § A local-store test helper in Kotlin

// app/src/androidTest/java/com/example/orders/DittoStoreTest.kt
import androidx.test.platform.app.InstrumentationRegistry
import com.ditto.kotlin.*
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * Opens a Ditto instance for each test in its own directory, and closes and
 * deletes it after the test, also when the test fails. Sync is never started,
 * so no license token or network is needed.
 */
abstract class DittoStoreTest {
    protected lateinit var ditto: Ditto
    private lateinit var directory: File

    /** The same parameters as the app's DittoConfig (SDK 5.2+). */
    protected open val systemParameters: Map<String, Any> = emptyMap()

    /** Creates the app's indexes, as at app startup. */
    protected open suspend fun configure(ditto: Ditto) {}

    @Before
    fun openStore() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        directory = File(context.cacheDir, "ditto-test-${UUID.randomUUID()}")
        ditto = DittoFactory.create(
            DittoConfig(
                // Any UUID works for local tests; each test gets its own directory.
                databaseId = "00000000-0000-4000-8000-000000000001",
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = directory.absolutePath,
                systemParameters = systemParameters,
            ),
        )
        runBlocking { configure(ditto) }
    }

    @After
    fun closeStore() {
        ditto.close()
        directory.deleteRecursively()
    }
}

/** Every test starts with an empty store. */
class EmptyStoreTest : DittoStoreTest() {
    // Pass the settings and indexes your app uses; see "Applying System Parameters".
    override val systemParameters: Map<String, Any> = mapOf("DQL_SLOW_REQUEST_WARN_SECONDS" to 10)

    override suspend fun configure(ditto: Ditto) {
        ditto.store.execute("CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)")
    }

    @Test
    fun aNewStoreIsEmpty() = runBlocking<Unit> {
        val count = ditto.store.execute("SELECT COUNT(*) AS n FROM orders") { it.items.first().value["n"].long }
        assertEquals(0L, count)
    }

    // The tests of local-store-tests.kt extend DittoStoreTest the same way.
}
