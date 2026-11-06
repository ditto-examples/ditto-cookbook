// Ditto SDK: 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android)
//
// Several small peers in one instrumented test process, connected over TCP on
// 127.0.0.1 only (inside the emulator or device): writes while the peers are
// disconnected, waiting until they converge, and a test of concurrent edits.
// Pass the offline license token as an instrumentation argument and never
// commit it:
//   ./gradlew connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.dittoLicenseToken=...
//
// Guide: § Several peers in one test process, § Several peers in one test in Kotlin

// app/src/androidTest/java/com/example/orders/MultiPeerTest.kt
import androidx.test.platform.app.InstrumentationRegistry
import com.ditto.kotlin.*
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Opens [count] peers in this process that sync with each other over TCP on
 * localhost only: peer 0 listens, the others connect to it. A device accepts
 * at most 6 TCP connections by default, so keep [count] at 7 or below.
 */
suspend fun openSyncedPeers(
    count: Int,
    licenseToken: String,
    port: Int = 4041,
    databaseId: String = "00000000-0000-4000-8000-000000000002",
    configure: suspend (Ditto) -> Unit = {},
): List<Ditto> {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val peers = mutableListOf<Ditto>()
    for (i in 0 until count) {
        val ditto = DittoFactory.create(
            DittoConfig(
                // All peers of a group use the same database ID; give every group
                // that can run at the same time its own ID and port.
                databaseId = databaseId,
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = File(context.cacheDir, "ditto-peer$i-${UUID.randomUUID()}").absolutePath,
            ),
        )
        peers += ditto
        ditto.setOfflineOnlyLicenseToken(licenseToken)
        ditto.updateTransportConfig { config ->
            // No Bluetooth, LAN, or Wi-Fi Aware.
            config.peerToPeer.bluetoothLe.enabled = false
            config.peerToPeer.lan.enabled = false
            config.peerToPeer.wifiAware.enabled = false
            // Every peer listens on this device only; peer 0 on the known port.
            config.listen.tcp.enabled = true
            config.listen.tcp.interfaceIp = "127.0.0.1"
            config.listen.tcp.port = if (i == 0) port else 0
            if (i > 0) config.connect.tcpServers.add("127.0.0.1:$port")
        }
        configure(ditto) // App setup after open, such as indexes.
        ditto.sync.start()
    }
    waitUntil { peers.all(::isConnected) }
    return peers
}

fun isConnected(ditto: Ditto): Boolean = ditto.presence.graph.remotePeers.isNotEmpty()

suspend fun waitUntil(timeoutMillis: Long = 15_000, condition: () -> Boolean) {
    withTimeout(timeoutMillis) {
        while (!condition()) delay(100)
    }
}

/** Stops sync on every peer, runs [writes] while they are disconnected, then reconnects them. */
suspend fun whileDisconnected(peers: List<Ditto>, writes: suspend () -> Unit) {
    peers.forEach { it.sync.stop() }
    waitUntil { peers.none(::isConnected) }
    writes()
    peers.forEach { it.sync.start() }
    waitUntil { peers.all(::isConnected) }
}

/** Waits until [query] returns the same rows on every peer and [until] holds, then returns the rows. */
suspend fun waitForConvergence(
    peers: List<Ditto>,
    query: String,
    arguments: Map<String, Any?> = emptyMap(),
    until: (List<JSONObject>) -> Boolean = { true },
    timeoutMillis: Long = 15_000,
): List<JSONObject> = withTimeout(timeoutMillis) {
    var results: List<List<JSONObject>>
    do {
        results = peers.map { peer ->
            peer.store.execute(query, arguments) { result -> result.items.map { JSONObject(it.jsonString()) } }
        }
        val first = results.first()
        val converged = results.all { rows -> rows.map(JSONObject::toString) == first.map(JSONObject::toString) } &&
            until(first)
        if (!converged) delay(100)
    } while (!converged)
    results.first()
}

open class MultiPeerTest {
    /** The offline license token; override to read it from elsewhere. */
    protected open val licenseToken: String? =
        InstrumentationRegistry.getArguments().getString("dittoLicenseToken")
    private var peers: List<Ditto> = emptyList()

    @After
    fun closePeers() {
        peers.forEach { it.close() }
    }

    @Test
    fun concurrentEditsOfDifferentLineItemsBothSurvive() = runBlocking<Unit> {
        val token = licenseToken
        assumeTrue("Needs the dittoLicenseToken instrumentation argument", !token.isNullOrEmpty())
        peers = openSyncedPeers(2, token!!)
        val (tablet, phone) = peers
        peers.forEach { it.sync.registerSubscription("SELECT * FROM orders") }
        tablet.store.execute(
            "INSERT INTO orders DOCUMENTS (:order)",
            mapOf("order" to mapOf("_id" to "order-1", "items" to mapOf("item-1" to mapOf("productId" to "p1", "quantity" to 1)))),
        )
        waitForConvergence(peers, "SELECT * FROM orders", until = { it.size == 1 })

        // The code under test would be the app's repository functions.
        whileDisconnected(peers) {
            tablet.store.execute("UPDATE orders SET items.`item-1`.quantity = 3 WHERE _id = :id", mapOf("id" to "order-1"))
            phone.store.execute(
                "UPDATE orders SET items.`item-2` = :item WHERE _id = :id",
                mapOf("id" to "order-1", "item" to mapOf("productId" to "p2", "quantity" to 1)),
            )
        }

        val rows = waitForConvergence(
            peers,
            "SELECT * FROM orders WHERE _id = :id",
            mapOf("id" to "order-1"),
            until = { it.single().getJSONObject("items").length() == 2 },
        )
        val items = rows.single().getJSONObject("items")
        assertEquals(3, items.getJSONObject("item-1").getInt("quantity"))
        assertEquals("p2", items.getJSONObject("item-2").getString("productId"))
    }
}
