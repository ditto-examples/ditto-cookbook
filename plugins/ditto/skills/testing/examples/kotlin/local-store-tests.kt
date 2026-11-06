// Ditto SDK: 5.2.0 (Kotlin, com.ditto:ditto-kotlin 5.2.0, Android)
//
// Tests for a local store: merge-sensitive writes, missing and null flags,
// deletion, the observer lifecycle, subscription rules, and DQL validation.
// Each class extends DittoStoreTest from local-store-test-helper.kt and runs as
// an instrumented test. The statements under test are inline so that each test
// is complete; in your suite, call your app's repository functions instead.
//
// Guide: § Testing Merge-Sensitive Writes, § Testing Deletion and Soft Delete, § Testing Observer Lifecycle,
//   § Testing Subscription Rules, § Validating DQL in Tests, § Testing in Kotlin

import com.ditto.kotlin.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class OrderMergeTest : DittoStoreTest() {
    @Test
    fun addingALineItemKeepsTheExistingItems() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:order)",
            mapOf("order" to mapOf("_id" to "order-1", "items" to mapOf("item-1" to mapOf("productId" to "p1", "quantity" to 2)))),
        )
        // The code under test: an upsert of a partial document.
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:patch) ON ID CONFLICT DO UPDATE_LOCAL_DIFF",
            mapOf("patch" to mapOf("_id" to "order-1", "items" to mapOf("item-2" to mapOf("productId" to "p2", "quantity" to 1)))),
        )
        val items = ditto.store.execute("SELECT * FROM orders WHERE _id = :id", mapOf("id" to "order-1")) { result ->
            result.items.first().value["items"].dictionaryOrNull // a map, not an array
        }
        assertEquals(setOf("item-1", "item-2"), items?.keys?.map { it.string }?.toSet())
    }

    @Test
    fun reUpsertingUnchangedDataIsANoOp() = runBlocking<Unit> {
        val product = mapOf("_id" to "p1", "name" to "Pen", "priceCents" to 250)
        val upsert = "INSERT INTO products DOCUMENTS (:product) ON ID CONFLICT DO UPDATE_LOCAL_DIFF"
        ditto.store.execute(upsert, mapOf("product" to product))
        val changed = ditto.store.execute(upsert, mapOf("product" to product)) { it.mutatedDocumentIds() }
        assertTrue(changed.isEmpty())
    }

    @Test
    fun replacingAnObjectRemovesKeysThatAreNotInTheNewValue() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO customers DOCUMENTS (:customer)",
            mapOf("customer" to mapOf("_id" to "c1", "address" to mapOf("city" to "Oslo", "zip" to "0150"))),
        )
        // The code under test: UNSET, then SET, in one transaction.
        ditto.store.transaction(hint = "replaceAddress") { tx ->
            tx.execute("UPDATE customers UNSET address WHERE _id = :id", mapOf("id" to "c1"))
            tx.execute("UPDATE customers SET address = :address WHERE _id = :id", mapOf("id" to "c1", "address" to mapOf("city" to "Bergen")))
            DittoTransaction.Result.Commit(Unit)
        }
        val address = ditto.store.execute("SELECT * FROM customers WHERE _id = :id", mapOf("id" to "c1")) { result ->
            result.items.first().value["address"].dictionary.mapKeys { it.key.string }.mapValues { it.value.string }
        }
        // A plain SET would keep "zip": objects merge under the default settings.
        assertEquals(mapOf("city" to "Bergen"), address)
    }
}

class DeletionTest : DittoStoreTest() {
    @Test
    fun activeOrdersQueryTreatsAMissingOrNullFlagAsNotDeleted() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:orders)",
            mapOf(
                "orders" to listOf(
                    mapOf("_id" to "deleted", "isDeleted" to true),
                    mapOf("_id" to "active", "isDeleted" to false),
                    mapOf("_id" to "nullFlag", "isDeleted" to null),
                    mapOf("_id" to "noFlag"),
                ),
            ),
        )
        val ids = ditto.store.execute(
            "SELECT _id FROM orders WHERE coalesce(isDeleted, false) = false ORDER BY _id",
        ) { result -> result.items.map { it.value["_id"].string } }
        assertEquals(listOf("active", "noFlag", "nullFlag"), ids)
    }

    @Test
    fun deletingByIdRemovesExactlyTheListedDocuments() = runBlocking<Unit> {
        ditto.store.execute(
            "INSERT INTO orders DOCUMENTS (:orders)",
            mapOf("orders" to listOf(mapOf("_id" to "o1"), mapOf("_id" to "o2"), mapOf("_id" to "o3"))),
        )
        // WHERE _id IN :ids, not USE IDS.
        val deleted = ditto.store.execute("DELETE FROM orders WHERE _id IN :ids", mapOf("ids" to listOf("o1", "o2"))) {
            it.mutatedDocumentIds().size
        }
        assertEquals(2, deleted)
        val remaining = ditto.store.execute("SELECT _id FROM orders") { result -> result.items.map { it.value["_id"].string } }
        assertEquals(listOf("o3"), remaining)
    }
}

class ObserverTest : DittoStoreTest() {
    @Test
    fun observerSeesANewOrderAndIsRemovedWhenCancelled() = runBlocking<Unit> {
        val orders = ditto.store.observe(
            "SELECT * FROM orders WHERE status = :status ORDER BY _id",
            mapOf("status" to "open"),
        ) { result -> result.items.map { it.value["_id"].string } }
        val sawOrder = async { withTimeout(5_000) { orders.first { it == listOf("order-1") } } }
        ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to mapOf("_id" to "order-1", "status" to "open")))
        sawOrder.await()
        // first() cancelled the collection, which removed the observer.
        assertEquals(0, ditto.store.observers.size)
    }

    @Test
    fun aRegisteredObserverIsReleasedByClose() {
        val observer = ditto.store.registerObserver("SELECT * FROM orders") { }
        observer.close()
        assertTrue(observer.isClosed)
        assertEquals(0, ditto.store.observers.size)
    }
}

class SubscriptionTest : DittoStoreTest() {
    @Test
    fun subscriptionsWithOrderByOrLimitAreRejected() {
        assertThrows(DittoException.StoreException::class.java) {
            ditto.sync.registerSubscription("SELECT * FROM orders ORDER BY createdAt DESC LIMIT 50")
        }
    }

    @Test
    fun theAppsSubscriptionsAreValid() {
        val subscriptions = listOf(
            ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :storeId", mapOf("storeId" to "store-1")),
            ditto.sync.registerSubscription("SELECT * FROM products"),
        )
        for (subscription in subscriptions) {
            subscription.close()
            assertTrue(subscription.isClosed)
        }
    }
}

class StatementTest : DittoStoreTest() {
    /** The app's statements with representative arguments; in a real app, reference the repository's strings. */
    private val appStatements = mapOf(
        "SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC" to mapOf("status" to "open"),
        "UPDATE orders SET status = :status WHERE _id = :id" to mapOf("status" to "closed", "id" to "order-1"),
        "DELETE FROM orders WHERE _id IN :ids" to mapOf("ids" to listOf("order-1")),
    )

    @Test
    fun everyAppStatementCanBePlanned() = runBlocking<Unit> {
        for ((statement, arguments) in appStatements) {
            ditto.store.execute("EXPLAIN $statement", arguments) // throws if it cannot be parsed or planned
        }
    }

    @Test
    fun theOpenOrdersQueryUsesItsIndex() = runBlocking<Unit> {
        ditto.store.execute("CREATE INDEX IF NOT EXISTS idx_orders_status_createdAt ON orders (status, createdAt DESC)")
        val plan = ditto.store.execute(
            "EXPLAIN SELECT * FROM orders WHERE status = :status ORDER BY createdAt DESC",
            mapOf("status" to "open"),
        ) { result -> result.items.first().jsonString() }
        assertTrue(plan.contains("indexScan"))
    }
}
