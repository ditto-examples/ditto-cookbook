"""Tests for the audit Skill's scanner (plugins/ditto/skills/audit/scripts/scan.py).

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import re
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCAN_PATH = (Path(__file__).resolve().parents[1]
             / "plugins/ditto/skills/audit/scripts/scan.py")
_spec = importlib.util.spec_from_file_location("ditto_scan", SCAN_PATH)
assert _spec is not None and _spec.loader is not None
scan = importlib.util.module_from_spec(_spec)
# dataclasses look the module up in sys.modules while the module runs.
sys.modules[_spec.name] = scan
_spec.loader.exec_module(scan)


def rules(code: str, extension: str) -> set[str]:
    """The names of the rules that report the given source."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / f"Example{extension}"
        path.write_text(textwrap.dedent(code), encoding="utf-8")
        return {finding.rule for finding in scan.scan([str(path)])}


def scan_findings(code: str, extension: str) -> list:
    """The findings for the given source."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / f"Example{extension}"
        path.write_text(textwrap.dedent(code), encoding="utf-8")
        return scan.scan([str(path)])


class ScannerTestCase(unittest.TestCase):
    def assertReports(self, rule: str, code: str, extension: str) -> None:
        self.assertIn(rule, rules(code, extension), f"{rule} should report:\n{code}")

    def assertSilent(self, rule: str, code: str, extension: str) -> None:
        self.assertNotIn(rule, rules(code, extension), f"{rule} should not report:\n{code}")


class SharedRulesTest(ScannerTestCase):
    def test_fresh_transport_config(self):
        self.assertReports("fresh-transport-config",
                           "ditto.transportConfig = DittoTransportConfig()\n", ".kt")
        self.assertReports("fresh-transport-config",
                           "ditto.transportConfig = DittoTransportConfig()\n", ".swift")
        self.assertReports("fresh-transport-config",
                           "ditto.updateTransportConfig(TransportConfig());\n", ".dart")
        self.assertSilent("fresh-transport-config",
                          "ditto.updateTransportConfig { config -> config.connect.tcpServers += host }\n",
                          ".kt")

    def test_development_authentication(self):
        self.assertReports("development-authentication",
                           "auth.login(token, DittoAuthenticationProvider.development())\n", ".kt")
        self.assertReports("development-authentication",
                           'ditto.auth.login(token: token, provider: .development) { _, _ in }\n',
                           ".swift")
        self.assertSilent("development-authentication",
                          'ditto.auth.login(token: token, provider: .init(rawValue: "auth-webhook"))\n',
                          ".swift")

    def test_small_peers_without_key(self):
        self.assertReports("small-peers-without-key",
                           "val config = DittoConfig(id, DittoConfig.Connect.SmallPeersOnly())\n", ".kt")
        self.assertReports("small-peers-without-key",
                           "let config = DittoConfig(databaseID: id, connect: .smallPeersOnly())\n",
                           ".swift")
        self.assertReports("small-peers-without-key",
                           "connect: .smallPeersOnly(privateKey: nil)\n", ".swift")
        self.assertSilent("small-peers-without-key",
                          "connect: .smallPeersOnly(privateKey: provisionedKey)\n", ".swift")
        self.assertSilent("small-peers-without-key",
                          "DittoConfig.Connect.SmallPeersOnly(privateKey = provisionedKey)\n", ".kt")

    def test_verbose_logging(self):
        self.assertReports("verbose-logging",
                           "DittoLogger.minimumLogLevel = DittoLogLevel.Verbose\n", ".kt")
        self.assertReports("verbose-logging", "DittoLogger.minimumLogLevel = .verbose\n", ".swift")
        self.assertReports("verbose-logging", "DittoLogger.minimumLogLevel = LogLevel.verbose;\n",
                           ".dart")
        self.assertSilent("verbose-logging", "DittoLogger.minimumLogLevel = .debug\n", ".swift")

    def test_subscription_query_arguments_only_in_dart(self):
        code = "final args = ditto.sync.subscriptions.first.queryArguments;\n"
        self.assertReports("subscription-query-arguments", code, ".dart")
        self.assertSilent("subscription-query-arguments",
                          "let args = ditto.sync.subscriptions.first?.queryArguments\n", ".swift")
        self.assertSilent("subscription-query-arguments",
                          "val args = ditto.sync.subscriptions.first().queryArguments\n", ".kt")

    def test_transaction_without_hint(self):
        self.assertReports("transaction-without-hint",
                           "ditto.store.transaction { tx ->\n    tx.execute(query)\n}\n", ".kt")
        self.assertReports("transaction-without-hint",
                           "try await ditto.store.transaction { transaction in\n}\n", ".swift")
        self.assertReports("transaction-without-hint",
                           "try await ditto.store.transaction(isReadOnly: true) { transaction in\n}\n",
                           ".swift")
        self.assertReports("transaction-without-hint",
                           "await ditto.store.transaction((tx) async {\n});\n", ".dart")
        self.assertSilent("transaction-without-hint",
                          'ditto.store.transaction(hint = "checkout") { tx ->\n}\n', ".kt")
        self.assertSilent("transaction-without-hint",
                          'try await ditto.store.transaction(hint: "checkout") { transaction in\n}\n',
                          ".swift")

    def test_discarded_observer(self):
        self.assertReports("discarded-observer",
                           'ditto.store.registerObserver("SELECT * FROM orders") { result -> }\n', ".kt")
        self.assertReports("discarded-observer",
                           '_ = try ditto.store.registerObserver(query: "SELECT * FROM orders") { _ in }\n',
                           ".swift")
        self.assertReports("discarded-observer",
                           'try ditto.store.registerObserver(query: "SELECT * FROM orders") { _ in }\n',
                           ".swift")
        self.assertSilent("discarded-observer",
                          'observer = try ditto.store.registerObserver(query: "SELECT * FROM orders") { _ in }\n',
                          ".swift")
        self.assertSilent("discarded-observer",
                          'val observer = ditto.store.registerObserver("SELECT * FROM orders") { result -> }\n',
                          ".kt")
        self.assertSilent("discarded-observer",
                          'return ditto.store.registerObserver("SELECT * FROM orders") { result -> }\n',
                          ".kt")

    def test_discarded_observer_in_a_block(self):
        self.assertReports("discarded-observer", """\
            init {
                ditto.store.registerObserver("SELECT * FROM orders") { result -> show(result) }
            }
            """, ".kt")
        self.assertReports("discarded-observer", """\
            load();
            ditto.store.registerObserver('SELECT * FROM orders', (result) => show(result));
            """, ".js")

    def test_returned_or_collected_registrations(self):
        self.assertSilent("discarded-observer", """\
            fun observeOrders(ditto: Ditto): DittoStoreObserver =
                ditto.store.registerObserver("SELECT * FROM orders") { result ->
                    show(result)
                }
            """, ".kt")
        self.assertSilent("discarded-subscription", """\
            return listOf(
                ditto.sync.registerSubscription("SELECT * FROM orders"),
                ditto.sync.registerSubscription("SELECT * FROM customers"),
            )
            """, ".kt")
        self.assertSilent("discarded-subscription", """\
            subscriptions = [
                try ditto.sync.registerSubscription(
                    query: "SELECT * FROM orders WHERE storeId = :storeId", arguments: ["storeId": id]
                ),
                try ditto.sync.registerSubscription(query: "SELECT * FROM productCategories"),
            ]
            """, ".swift")
        self.assertSilent("discarded-subscription", """\
            subscriptions = storeIds.map { id ->
                ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :id", mapOf("id" to id))
            }
            """, ".kt")
        self.assertSilent("discarded-subscription", """\
            subscriptions = storeIDs.map { id in
                try ditto.sync.registerSubscription(query: "SELECT * FROM orders WHERE storeId = :id", arguments: ["id": id])
            }
            """, ".swift")

    def test_swift_implicit_return(self):
        self.assertSilent("discarded-subscription", """\
            func subscribeToTeamTasks(_ ditto: Ditto, teamID: String) throws -> DittoSyncSubscription {
                try ditto.sync.registerSubscription(query: "SELECT * FROM tasks WHERE teamId = :teamId", arguments: ["teamId": teamID])
            }
            """, ".swift")
        self.assertSilent("discarded-observer", """\
            var ordersObserver: DittoStoreObserver? {
                try? ditto.store.registerObserver(query: "SELECT * FROM orders") { _ in }
            }
            """, ".swift")

    def test_discarded_subscription(self):
        self.assertReports("discarded-subscription",
                           'ditto.sync.registerSubscription("SELECT * FROM orders")\n', ".kt")
        self.assertReports("discarded-subscription",
                           '_ = try ditto.sync.registerSubscription(query: "SELECT * FROM orders")\n',
                           ".swift")
        self.assertSilent("discarded-subscription",
                          'self.subscription = try ditto.sync.registerSubscription(query: "SELECT * FROM orders")\n',
                          ".swift")

    def test_execute_inside_trailing_closure_transaction(self):
        self.assertReports("execute-inside-transaction", """\
            ditto.store.transaction(hint = "checkout") { tx ->
                ditto.store.execute("UPDATE orders SET status = 'paid'")
                DittoTransaction.Result.Commit(Unit)
            }
            """, ".kt")
        self.assertReports("execute-inside-transaction", """\
            ditto.store.transaction { tx ->
                ditto.store.execute("UPDATE orders SET status = 'paid'")
                DittoTransaction.Result.Commit(Unit)
            }
            """, ".kt")
        self.assertReports("execute-inside-transaction", """\
            try await ditto.store.transaction { transaction in
                try await ditto.store.execute(query: "UPDATE orders SET status = 'paid'")
                return .commit
            }
            """, ".swift")
        self.assertReports("execute-inside-transaction", """\
            try await ditto.store.transaction(hint: "checkout") { transaction in
                try await ditto.store.execute(query: "UPDATE orders SET status = 'paid'")
                return .commit
            }
            """, ".swift")
        self.assertReports("execute-inside-transaction", """\
            try await ditto.store.transaction(hint: "outer") { transaction in
                try await ditto.store.transaction(hint: "inner") { inner in .commit }
                return .commit
            }
            """, ".swift")
        self.assertSilent("execute-inside-transaction", """\
            try await ditto.store.transaction(hint: "checkout") { transaction in
                try await transaction.execute(query: "UPDATE orders SET status = 'paid'")
                return .commit
            }
            try await ditto.store.execute(query: "SELECT * FROM orders")
            """, ".swift")


class InterpolationTest(ScannerTestCase):
    def test_interpolation_inside_the_statement(self):
        self.assertReports("dql-string-interpolation",
                           'ditto.store.execute("SELECT * FROM orders WHERE _id = \'$id\'")\n', ".kt")
        self.assertReports("dql-string-interpolation",
                           "await ditto.store.execute(`SELECT * FROM ${collection}`)\n", ".js")
        self.assertReports("dql-string-interpolation",
                           "ditto.store.execute(\"SELECT * FROM orders WHERE _id = '\" + id + \"'\")\n", ".kt")
        self.assertReports("dql-string-interpolation",
                           'try await ditto.store.execute(query: "SELECT * FROM orders WHERE _id = \'\\(id)\'")\n',
                           ".swift")

    def test_interpolation_in_an_argument_value(self):
        self.assertSilent("dql-string-interpolation",
                          'tx.execute("INSERT INTO payments DOCUMENTS (:payment)", mapOf("payment" to mapOf("_id" to "payment-$orderId")))\n',
                          ".kt")
        self.assertSilent("dql-string-interpolation",
                          "await tx.execute('INSERT INTO payments DOCUMENTS (:payment)', { payment: { _id: `payment-${orderId}` } })\n",
                          ".js")


class KotlinRulesTest(ScannerTestCase):
    def test_zone_less_timestamp(self):
        self.assertReports("zone-less-timestamp",
                           'val createdAt = LocalDateTime.now().toString()\n', ".kt")

    def test_variable_precision_timestamp(self):
        self.assertReports("variable-precision-timestamp",
                           'val createdAt = Instant.now().toString()\n', ".kt")
        self.assertSilent("variable-precision-timestamp",
                          'val createdAt = utcTimestamp(Instant.now())\n', ".kt")

    def test_unconvertible_argument(self):
        self.assertReports("unconvertible-argument",
                           'mapOf("id" to id, "createdAt" to Instant.now())\n', ".kt")
        self.assertReports("unconvertible-argument",
                           'mapOf("id" to UUID.randomUUID(), "status" to "open")\n', ".kt")
        self.assertSilent("unconvertible-argument",
                          'mapOf("id" to UUID.randomUUID().toString(), "createdAt" to utcNow())\n', ".kt")

    def test_float_read_as_double(self):
        self.assertReports("float-read-as-double",
                           'val total = item.value["total"]?.doubleOrNull\n', ".kt")
        self.assertReports("float-read-as-double",
                           'val total = item.value["total"].double\n', ".kt")
        self.assertSilent("float-read-as-double",
                          'val total = item.value["total"]?.numberOrNull()\n', ".kt")

    def test_result_leaves_handler(self):
        self.assertReports("result-leaves-handler", """\
            suspend fun openOrders(ditto: Ditto): DittoQueryResult =
                ditto.store.execute("SELECT * FROM orders", mapOf("status" to "open")) { result ->
                    result
                }
            """, ".kt")
        self.assertReports("result-leaves-handler",
                           'val items = ditto.store.execute("SELECT * FROM orders") { it.items }\n', ".kt")
        self.assertSilent("result-leaves-handler", """\
            val orders = ditto.store.execute("SELECT * FROM orders") { result ->
                result.items.map { Order.from(it.value) }
            }
            """, ".kt")

    def test_unconvertible_big_numbers(self):
        self.assertReports("unconvertible-argument",
                           'mapOf("id" to id, "amount" to BigDecimal("12.50"))\n', ".kt")

    def test_ditto_in_ui(self):
        self.assertReports("ditto-in-ui", """\
            class OrdersActivity : AppCompatActivity() {
                override fun onCreate(savedInstanceState: Bundle?) {
                    super.onCreate(savedInstanceState)
                    val ditto = DittoFactory.create(DittoConfig(databaseId = "YOUR_DATABASE_ID"))
                }
            }
            """, ".kt")
        self.assertReports("ditto-in-ui", """\
            @Composable
            fun OrdersScreen() {
                val ditto = remember { DittoFactory.create(appConfig()) }
            }
            """, ".kt")
        self.assertSilent("ditto-in-ui", """\
            class OrdersApplication : Application() {
                val ditto: Ditto by lazy { DittoFactory.create(appConfig()) }
            }
            """, ".kt")

    def test_login_uncaught(self):
        self.assertReports("login-error-unreported", """\
            ditto.auth?.expirationHandler = { dittoInstance, _ ->
                dittoInstance.auth?.login(token = fetchAuthToken(), provider = "YOUR_PROVIDER_NAME")
            }
            """, ".kt")
        self.assertSilent("login-error-unreported", """\
            ditto.auth?.expirationHandler = { dittoInstance, _ ->
                try {
                    dittoInstance.auth?.login(token = fetchAuthToken(), provider = "YOUR_PROVIDER_NAME")
                } catch (error: DittoException.AuthenticationException) {
                    showError(error)
                }
            }
            """, ".kt")

    def test_throwing_observer_handler(self):
        self.assertReports("throwing-observer-handler", """\
            val observer = ditto.store.registerObserver("SELECT price FROM orders") { result ->
                show(result.items.sumOf { it.value["price"].numberOrNull()!! })
            }
            """, ".kt")
        self.assertReports("throwing-observer-handler", """\
            val observer = ditto.store.registerObserver("SELECT * FROM orders") { result ->
                val first = result.items.firstOrNull() ?: error("no orders")
                show(first.jsonString())
            }
            """, ".kt")
        self.assertSilent("throwing-observer-handler", """\
            val observer = ditto.store.registerObserver("SELECT price FROM orders") { result ->
                try {
                    show(result.items.sumOf { it.value["price"].numberOrNull()!! })
                } catch (error: Exception) {
                    Log.e("Orders", "Could not read prices", error)
                }
            }
            """, ".kt")
        self.assertSilent("throwing-observer-handler", """\
            val observer = ditto.store.registerObserver("SELECT price FROM orders") { result ->
                show(result.items.sumOf { it.value["price"].numberOrNull() ?: 0.0 })
            }
            """, ".kt")

    def test_execute_on_main(self):
        self.assertReports("execute-on-main", """\
            viewModelScope.launch {
                val count = ditto.store.execute("SELECT COUNT(*) AS n FROM orders") { it.items.first().value["n"].long }
                _count.value = count
            }
            """, ".kt")
        self.assertSilent("execute-on-main", """\
            viewModelScope.launch {
                val count = withContext(Dispatchers.IO) {
                    ditto.store.execute("SELECT COUNT(*) AS n FROM orders") { it.items.first().value["n"].long }
                }
                _count.value = count
            }
            """, ".kt")
        self.assertSilent("execute-on-main", """\
            viewModelScope.launch(Dispatchers.IO) {
                ditto.store.execute("UPDATE orders SET status = 'open' WHERE _id = :id", mapOf("id" to id))
            }
            """, ".kt")

    def test_kotlin_rules_stay_in_kotlin(self):
        self.assertSilent("variable-precision-timestamp",
                          "let createdAt = Instant.now().toString()\n", ".swift")


class SwiftRulesTest(ScannerTestCase):
    def test_unconvertible_argument(self):
        self.assertReports("unconvertible-argument",
                           'try await ditto.store.execute(query: q, arguments: ["at": Date()])\n',
                           ".swift")
        self.assertReports("unconvertible-argument",
                           'try await ditto.store.execute(query: q, arguments: ["ratio": Double.nan])\n',
                           ".swift")
        self.assertSilent("unconvertible-argument",
                          'let now = Date()\n', ".swift")
        self.assertSilent("unconvertible-argument",
                          'try await ditto.store.execute(query: q, arguments: ["at": utcTimestamp(Date())])\n',
                          ".swift")

    def test_float_read_as_double(self):
        findings = scan_findings('let total = item.value["total"] as? Double ?? 0\n', ".swift")
        self.assertEqual([(f.rule, f.guide) for f in findings],
                         [("float-read-as-double", "Query results in Swift")])
        self.assertSilent("float-read-as-double",
                          'let total = (item.value["total"] as? NSNumber)?.doubleValue ?? 0\n', ".swift")

    def test_date_description_timestamp(self):
        self.assertReports("date-description-timestamp",
                           'let createdAt = "\\(Date())"\n', ".swift")
        self.assertReports("date-description-timestamp",
                           'let createdAt = Date().description\n', ".swift")
        self.assertSilent("date-description-timestamp",
                          'let createdAt = Date().formatted(.iso8601)\n', ".swift")

    def test_open_sync(self):
        self.assertReports("open-sync", "let ditto = try Ditto.openSync(config: config)\n", ".swift")
        self.assertSilent("open-sync", "let ditto = try await Ditto.open(config: config)\n", ".swift")

    def test_uppercase_uuid(self):
        self.assertReports("uppercase-uuid", "let id = UUID().uuidString\n", ".swift")
        self.assertSilent("uppercase-uuid", "let id = UUID().uuidString.lowercased()\n", ".swift")

    def test_observer_task_without_backpressure(self):
        self.assertReports("observer-task-without-backpressure", """\
            observer = try ditto.store.registerObserver(query: "SELECT * FROM orders") { result in
                Task {
                    await self.process(result)
                }
            }
            """, ".swift")
        self.assertSilent("observer-task-without-backpressure", """\
            observer = try ditto.store.registerObserver(query: "SELECT * FROM orders") { result, signalNext in
                Task {
                    await self.process(result)
                    signalNext()
                }
            }
            """, ".swift")
        self.assertSilent("observer-task-without-backpressure", """\
            observer = try ditto.store.registerObserver(query: "SELECT * FROM orders") { result in
                self.orders = result.items.map(Order.init)
            }
            Task { await refresh() }
            """, ".swift")
        self.assertSilent("observer-task-without-backpressure", """\
            observer = try? ditto.store.registerObserver(query: q, deliverOn: queue) { [weak self] result in
                let computed = summarize(result)
                Task { @MainActor in
                    if self?.summary != computed { self?.summary = computed }
                }
            }
            """, ".swift")


class DartRulesTest(ScannerTestCase):
    def test_subscription_query_arguments_bytes(self):
        self.assertReports("subscription-query-arguments",
                           "for (final s in ditto.sync.subscriptions) debugPrint('${s.queryArgumentsCborBytes?.length}');\n",
                           ".dart")
        self.assertSilent("subscription-query-arguments", "debugPrint(subscription.queryString);\n", ".dart")

    def test_transaction_without_hint(self):
        for code in ("  await ditto.store.transaction((tx) async {\n",
                     "  return ditto.store.transaction(isReadOnly: true, (tx) async {\n",
                     "  final n = await ditto.store.transaction<int>((tx) async {\n"):
            self.assertReports("transaction-without-hint", code, ".dart")
        for code in ("  await ditto.store.transaction(hint: 'recordPayment', (tx) async {\n",
                     "  final action = await ditto.store.transaction(\n",
                     "  return ditto.store.transaction(hint: 'orderCounts', isReadOnly: true, (tx) async {\n"):
            self.assertSilent("transaction-without-hint", code, ".dart")

    def test_unconvertible_argument(self):
        for code in ("        'createdAt': DateTime.now(),\n",
                     "      arguments: {'id': id, 'serial': BigInt.parse(serial)},\n",
                     "      arguments: {'id': id, 'ratio': double.nan},\n",
                     "        'shippedAt': DateTime.now().toUtc(),\n"):
            self.assertReports("unconvertible-argument", code, ".dart")
        for code in ("        'createdAt': utcTimestamp(),\n",
                     "        'createdAt': DateTime.now().millisecondsSinceEpoch,\n",
                     "    final started = DateTime.now();\n",
                     "        'serial': serialNumber.toString(),\n"):
            self.assertSilent("unconvertible-argument", code, ".dart")

    def test_variable_precision_timestamp(self):
        self.assertReports("variable-precision-timestamp",
                           "        'createdAt': DateTime.now().toUtc().toIso8601String(),\n", ".dart")
        self.assertSilent("variable-precision-timestamp",
                          "  return DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch, isUtc: true).toIso8601String();\n",
                          ".dart")

    def test_version_string_compare(self):
        self.assertReports("version-string-compare", "  if (Ditto.version == '5.2.0') {\n", ".dart")
        self.assertReports("version-string-compare", "  final major = Ditto.version.split('.').first;\n", ".dart")
        self.assertSilent("version-string-compare", "  debugPrint('Ditto ${Ditto.version}');\n", ".dart")

    def test_discarded_registrations(self):
        self.assertReports("discarded-subscription", "    ditto.sync.registerSubscription('SELECT * FROM orders');\n", ".dart")
        self.assertReports("discarded-observer",
                           "  b.store.registerObserver('SELECT * FROM cars').changes.listen((_) => count());\n", ".dart")
        self.assertSilent("discarded-subscription", """\
            _subscriptions
              ..add(_ditto.sync.registerSubscription('SELECT * FROM orders'))
              ..add(_ditto.sync.registerSubscription('SELECT * FROM items'));
            """, ".dart")
        self.assertSilent("discarded-subscription",
                          "retainedSubscriptions.add(peer.sync.registerSubscription('SELECT * FROM orders'));\n", ".dart")
        self.assertSilent("discarded-observer", """\
            _observer = widget.ditto.store.registerObserver(
              'SELECT * FROM orders',
            );
            """, ".dart")

    def test_ditto_in_ui(self):
        self.assertReports("ditto-in-ui", """\
            class _OrdersPageState extends State<OrdersPage> {
              Future<void> _load() async {
                final ditto = await Ditto.open(const DittoConfig(databaseID: 'YOUR_DATABASE_ID'));
              }
            }
            """, ".dart")
        self.assertSilent("ditto-in-ui", """\
            class DittoProvider {
              Future<Ditto> get instance => _opening ??= Ditto.open(_config);
            }
            """, ".dart")

    def test_close_inside_transaction(self):
        self.assertReports("close-inside-transaction", """\
            await ditto.store.transaction((tx) async {
              await tx.execute('UPDATE orders SET status = :s WHERE _id = :id', arguments: {'s': 'done', 'id': id});
              await ditto.close();
            });
            """, ".dart")
        self.assertSilent("close-inside-transaction", """\
            await ditto.store.transaction(hint: 'markDone', (tx) async {
              await tx.execute('UPDATE orders SET status = :s WHERE _id = :id', arguments: {'s': 'done', 'id': id});
              await sink.close();
            });
            await ditto.close();
            """, ".dart")

    def test_work_started_in_transaction(self):
        self.assertReports("work-started-in-transaction", """\
            await ditto.store.transaction(hint: 'saveOrder', (tx) async {
              await tx.execute('INSERT INTO orders DOCUMENTS (:o)', arguments: {'o': order});
              unawaited(Future<void>.delayed(const Duration(seconds: 1), () => ditto.store.execute('SELECT * FROM orders')));
            });
            """, ".dart")
        self.assertReports("work-started-in-transaction", """\
            await ditto.store.transaction(hint: 'openScreen', (tx) async {
              _observer = ditto.store.registerObserver('SELECT * FROM orders');
              _changes = _observer!.changes.listen(_render);
            });
            """, ".dart")
        self.assertSilent("work-started-in-transaction", """\
            await ditto.store.transaction(hint: 'recordPayment', (tx) async {
              await tx.execute('UPDATE orders SET status = :s WHERE _id = :id', arguments: {'s': 'paid', 'id': id});
            });
            _observer = ditto.store.registerObserver('SELECT * FROM orders');
            """, ".dart")

    def test_signal_next_skipped_on_error(self):
        self.assertReports("signal-next-skipped-on-error", """\
            final observer = ditto.store.registerObserverWithSignalNext('SELECT * FROM orders ORDER BY createdAt');
            observer.changes.listen((result) async {
              await upload(result.items.map((item) => item.value).toList());
              observer.signalNext(); // Never reached if upload() throws.
            });
            """, ".dart")
        self.assertSilent("signal-next-skipped-on-error", """\
            observer.changes.listen((result) async {
              try {
                await upload(result.items.map((item) => item.value).toList());
              } finally {
                observer.signalNext();
              }
            });
            """, ".dart")

    def test_await_for_without_backpressure(self):
        self.assertReports("await-for-without-backpressure", """\
            final observer = ditto.store.registerObserver('SELECT * FROM orders');
            await for (final result in observer.changes) {
              await upload(result.items.map((item) => item.value).toList());
            }
            """, ".dart")
        self.assertSilent("await-for-without-backpressure", """\
            final observer = ditto.store.registerObserverV2('SELECT * FROM orders');
            await for (final result in observer.changes) {
              await upload(result.items.map((item) => item.value).toList());
            }
            """, ".dart")


class SwiftSignalNextTest(ScannerTestCase):
    def test_signal_next_skipped_on_error(self):
        self.assertReports("signal-next-skipped-on-error", """\
            try ditto.store.registerObserver(query: "SELECT * FROM orders") { result, signalNext in
                let orders = result.items.map { $0.value }
                Task {
                    try await upload(orders)
                    signalNext()
                }
            }
            """, ".swift")
        self.assertSilent("signal-next-skipped-on-error", """\
            observer = try ditto.store.registerObserver(query: "SELECT * FROM orders") { result, signalNext in
                let orders = result.items.map { $0.value }
                Task {
                    defer { signalNext() }
                    do { try await upload(orders) } catch { showError(error) }
                }
            }
            """, ".swift")

    def test_ditto_in_swiftui_view(self):
        self.assertReports("ditto-in-ui", """\
            struct OrdersView: View {
                var body: some View {
                    Text("Orders").task {
                        let ditto = try? await Ditto.open(config: config)
                    }
                }
            }
            """, ".swift")


class ConcurrentWritesTest(ScannerTestCase):
    def test_kotlin_repeat(self):
        self.assertReports("concurrent-writes-in-loop", """\
            repeat(64) { index ->
                scope.launch(Dispatchers.IO) {
                    ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order(index)))
                }
            }
            """, ".kt")

    def test_kotlin_launch_per_write(self):
        self.assertReports("concurrent-writes-in-loop", """\
            for (order in orders) {
                scope.launch(Dispatchers.IO) {
                    ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order))
                }
            }
            """, ".kt")
        self.assertReports("concurrent-writes-in-loop", """\
            orders.forEach { order ->
                launch { ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order)) }
            }
            """, ".kt")

    def test_swift_task_per_write(self):
        self.assertReports("concurrent-writes-in-loop", """\
            for order in orders {
                Task {
                    try await ditto.store.execute(query: "INSERT INTO orders DOCUMENTS (:order)", arguments: ["order": order])
                }
            }
            """, ".swift")
        self.assertReports("concurrent-writes-in-loop", """\
            try await withThrowingTaskGroup(of: Void.self) { group in
                for order in orders {
                    group.addTask {
                        try await ditto.store.execute(query: insert, arguments: ["order": order])
                    }
                }
            }
            """, ".swift")

    def test_sequential_writes_in_loop(self):
        self.assertSilent("concurrent-writes-in-loop", """\
            for order in orders {
                try await ditto.store.execute(query: insert, arguments: ["order": order])
            }
            """, ".swift")
        self.assertSilent("concurrent-writes-in-loop", """\
            for (order in orders) {
                ditto.store.execute("INSERT INTO orders DOCUMENTS (:order)", mapOf("order" to order))
            }
            scope.launch { refresh() }
            """, ".kt")


class JavaScriptRulesTest(ScannerTestCase):
    def test_interpolation(self):
        self.assertReports("dql-string-interpolation",
                           "await ditto.store.execute('SELECT * FROM orders WHERE customerId = ' + customerId);\n", ".js")
        self.assertSilent("dql-string-interpolation", "const result = await ditto.store.execute(`ADVISE ${query}`, args);\n", ".js")
        self.assertSilent("dql-string-interpolation", "Logger.info(`Query on orders took ${ms} ms`);\n", ".js")

    def test_shared_line_rules(self):
        self.assertReports("development-authentication",
                           "const result = await ditto.auth.login(developmentToken, Authenticator.DEVELOPMENT_PROVIDER);\n", ".js")
        self.assertReports("small-peers-without-key",
                           "new DittoConfig({ databaseID: 'YOUR_DATABASE_ID', connect: { mode: 'smallPeersOnly' } })\n", ".js")
        self.assertReports("small-peers-without-key", "connect: { mode: 'smallPeersOnly', privateKey: null },\n", ".js")
        self.assertSilent("small-peers-without-key",
                          "connect: { mode: 'smallPeersOnly', privateKey: await readKeyFromSecureStorage() },\n", ".js")
        self.assertReports("verbose-logging", "Logger.minimumLogLevel = 'Verbose';\n", ".js")
        self.assertSilent("verbose-logging", "Logger.minimumLogLevel = production ? 'Warning' : 'Debug';\n", ".js")

    def test_zone_less_timestamp(self):
        for code in ("label: new Date().toLocaleString(),\n", "createdAt: new Date().toString(),\n",
                     "{ id: orderId, shippedAt: new Date(Date.UTC(2026, 0, 15)).toUTCString() }\n",
                     "createdAt: Date(),\n"):
            self.assertReports("zone-less-timestamp", code, ".js")
        for code in ("createdAt: new Date().toISOString(),\n", "readyAt: utcTimestamp(),\n",
                     "<time>{new Date(order.createdAt).toLocaleString()}</time>\n",
                     "const label = new Date().toLocaleString();\n"):
            self.assertSilent("zone-less-timestamp", code, ".jsx")

    def test_transaction_without_hint(self):
        self.assertReports("transaction-without-hint", """\
            await ditto.store.transaction(async (tx) => {
              await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id, status: 'paid' });
            });
            """, ".js")
        self.assertReports("transaction-without-hint", """\
            return ditto.store.transaction(
              async (tx) => tx.execute('SELECT COUNT(*) AS n FROM orders'),
              { isReadOnly: true },
            );
            """, ".js")
        self.assertSilent("transaction-without-hint", """\
            await ditto.store.transaction(
              async (tx) => {
                await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id, status: 'paid' });
              },
              { hint: 'markPaid' },
            );
            """, ".js")
        self.assertSilent("transaction-without-hint",
                          "return await ditto.store.transaction((tx) => migrate(tx), { hint: 'migration' });\n", ".js")

    def test_unconvertible_argument(self):
        self.assertReports("unconvertible-argument", """\
            await ditto.store.execute('UPDATE orders SET readyAt = :readyAt WHERE _id = :id', {
              id: orderId,
              readyAt: new Date(),
            });
            """, ".js")
        self.assertReports("unconvertible-argument",
                           "await ditto.store.execute('INSERT INTO orders DOCUMENTS (:order)', { order: { _id: id, tags: new Set(tags) } });\n", ".js")
        self.assertReports("unconvertible-argument",
                           "await tx.execute('UPDATE stats SET ratio = :ratio WHERE _id = :id', { id, ratio: NaN });\n", ".js")
        self.assertSilent("unconvertible-argument", """\
            await ditto.store.execute('UPDATE orders SET readyAt = :readyAt WHERE _id = :id', {
              id: orderId,
              readyAt: new Date().toISOString(),
            });
            """, ".js")
        self.assertSilent("unconvertible-argument",
                          "const [state, setState] = useState({ orders: [], changed: new Set() });\n", ".jsx")

    def test_async_observer_handler(self):
        self.assertReports("observer-task-without-backpressure", """\
            return ditto.store.registerObserver('SELECT * FROM orders WHERE status = :status', async (result) => {
              await uploadOrders(result.items.map((item) => item.value));
            }, { status: 'open' });
            """, ".js")
        self.assertReports("observer-task-without-backpressure", """\
            this.observer = ditto.store.registerObserver(
              'SELECT * FROM orders',
              async function onOrders(result) {
                for (const item of result.items) await printReceipt(item.value);
              },
            );
            """, ".js")
        self.assertSilent("observer-task-without-backpressure", """\
            const observer = ditto.store.registerObserver(
              'SELECT * FROM orders',
              (result) => setOrders(result.items.map((item) => item.value)),
            );
            """, ".js")

    def test_for_each_async_writes(self):
        self.assertReports("concurrent-writes-in-loop", """\
            await ditto.store.transaction(async (tx) => {
              ids.forEach(async (id) => {
                await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id, status: 'closed' });
              });
            }, { hint: 'closeOrders' });
            """, ".js")
        self.assertSilent("concurrent-writes-in-loop", """\
            for (const id of ids) {
              await tx.execute('UPDATE orders SET status = :status WHERE _id = :id', { id, status: 'closed' });
            }
            orders.forEach(async (order) => {
              await printReceipt(order);
            });
            """, ".js")

    def test_javascript_line_rules(self):
        self.assertReports("all-peer-to-peer-enabled",
                           "ditto.updateTransportConfig((config) => config.setAllPeerToPeerEnabled(true));\n", ".js")
        self.assertSilent("all-peer-to-peer-enabled", "config.setAvailablePeerToPeerEnabled(true);\n", ".js")
        self.assertReports("mutated-document-ids-without-v2", "return result.mutatedDocumentIDs();\n", ".js")
        self.assertSilent("mutated-document-ids-without-v2", "return result.mutatedDocumentIDsV2();\n", ".js")
        self.assertSilent("mutated-document-ids-without-v2", "final ids = result.mutatedDocumentIDs();\n", ".dart")
        self.assertReports("logout-cleanup-not-awaited", "await ditto.auth.logout(async (ditto) => {\n", ".js")
        self.assertSilent("logout-cleanup-not-awaited", "await ditto.auth.logout();\n", ".js")
        self.assertReports("observer-is-stopped-inverted", "if (!presenceObserver.isStopped) presenceObserver.stop();\n", ".js")
        self.assertSilent("observer-is-stopped-inverted", "if (!observer.isCancelled) observer.cancel();\n", ".js")

    def test_missing_signal_next(self):
        self.assertReports("missing-signal-next", """\
            return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders', (result) => {
              onCount(result.items.length);
            });
            """, ".js")
        self.assertReports("missing-signal-next", """\
            return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders', async (result, signalNext) => {
              await upload(result.items.map((item) => item.value));
            });
            """, ".js")
        self.assertSilent("missing-signal-next", """\
            ditto.store.registerObserverWithSignalNext('SELECT * FROM orders', (result, signalNext) => {
              pending = { result, signalNext };
              schedule();
            });
            """, ".js")
        self.assertSilent("missing-signal-next",
                          "this.#observer = ditto.store.registerObserverWithSignalNext(QUERY, this.#onResult);\n", ".js")

    def test_signal_next_skipped_on_error(self):
        self.assertReports("signal-next-skipped-on-error", """\
            return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders ORDER BY createdAt', async (result, signalNext) => {
              await uploadOrders(result.items.map((item) => item.value));
              signalNext(); // Never reached if uploadOrders() throws.
            });
            """, ".js")
        self.assertSilent("signal-next-skipped-on-error", """\
            return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders', async (result, signalNext) => {
              try {
                await uploadOrders(result.items.map((item) => item.value));
              } finally {
                signalNext();
              }
            });
            """, ".js")
        self.assertSilent("signal-next-skipped-on-error", """\
            return ditto.store.registerObserverWithSignalNext('SELECT * FROM orders', (result, signalNext) => {
              render(result.items.map((item) => item.value));
              signalNext();
            });
            """, ".js")

    def test_unbounded_data_sync_info_read(self):
        self.assertReports("unbounded-data-sync-info-read", """\
            const result = await ditto.store.execute(
              'SELECT * FROM system:data_sync_info WHERE is_ditto_server = true',
            );
            """, ".js")
        self.assertSilent("unbounded-data-sync-info-read", """\
            return await Promise.race([
              ditto.store.execute(query),
              new Promise((resolve) => { timer = setTimeout(() => resolve(null), ms); }),
            ]);
            const result = await executeWithin(ditto, 'SELECT * FROM system:data_sync_info WHERE is_ditto_server = true', 5000);
            """, ".js")
        self.assertSilent("unbounded-data-sync-info-read",
                          "const observer = ditto.store.registerObserver('SELECT * FROM system:data_sync_info WHERE is_ditto_server = true', onRows);\n",
                          ".js")
        self.assertReports("unbounded-data-sync-info-read", """\
            val confirmed = ditto.store.execute(
                "SELECT * FROM system:data_sync_info WHERE is_ditto_server = true",
            ) { result -> result.items.isNotEmpty() }
            """, ".kt")

    def test_kotlin_deadline_needs_its_own_scope(self):
        self.assertReports("unbounded-data-sync-info-read", """\
            val confirmed = withTimeoutOrNull(3_000) {
                ditto.store.execute("SELECT * FROM system:data_sync_info") { it.items.isNotEmpty() }
            }
            """, ".kt")
        self.assertSilent("unbounded-data-sync-info-read", """\
            private val reads = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            val read = reads.async {
                ditto.store.execute("SELECT * FROM system:data_sync_info") { it.items.isNotEmpty() }
            }
            val confirmed = withTimeoutOrNull(3_000) { read.await() }
            """, ".kt")

    def test_login_error_unreported(self):
        self.assertReports("login-error-unreported", """\
            await ditto.auth.setExpirationHandler(async (ditto) => {
              const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
              if (result.error) throw result.error;
            });
            """, ".js")
        self.assertReports("login-error-unreported", """\
            await ditto.auth.setExpirationHandler(async (ditto) => {
              await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
            });
            """, ".js")
        self.assertSilent("login-error-unreported", """\
            await ditto.auth.setExpirationHandler(async (ditto, secondsRemaining) => {
              try {
                const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
                if (result.error) showError(result.error);
              } catch (error) {
                showError(error);
              }
            });
            """, ".js")

    def test_login_error_comment(self):
        self.assertSilent("login-error-unreported", """\
            await ditto.auth.setExpirationHandler(async (ditto) => {
              // Do not throw inside the handler; the SDK only logs it. Report instead.
              try {
                const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
                if (result.error) report(`login failed: ${result.error.message}`);
              } catch (error) {
                report(`login failed: ${error}`);
              }
            });
            """, ".js")

    def test_register_in_render(self):
        self.assertReports("register-in-render", """\
            export function OrdersBadge({ ditto, storeId }) {
              ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId });
              return <span>Orders</span>;
            }
            """, ".jsx")
        self.assertReports("register-in-render", """\
            function FetchInRender({ ditto, token }) {
              const [bytes, setBytes] = useState(null);
              ditto.store.fetchAttachment(token, (event) => { if (event.type === 'Completed') setBytes(event.attachment.getData()); });
              return <img alt="" src={bytes} />;
            }
            """, ".jsx")
        self.assertSilent("register-in-render", """\
            export function OrdersList({ ditto }) {
              const [orders, setOrders] = useState([]);
              useEffect(() => {
                const observer = ditto.store.registerObserver('SELECT * FROM orders', (r) => setOrders(r.items.map((i) => i.value)));
                return () => observer.cancel();
              }, [ditto]);
              return <ul>{orders.length}</ul>;
            }
            """, ".jsx")
        self.assertSilent("register-in-render", """\
            export function subscribeToOrders(ditto) {
              return ditto.sync.registerSubscription('SELECT * FROM orders');
            }
            """, ".js")

    def test_effect_without_cleanup(self):
        self.assertReports("effect-without-cleanup", """\
            useEffect(() => {
              ditto.store.registerObserver('SELECT * FROM orders', (result) => setCount(result.items.length));
            }, [ditto]);
            """, ".jsx")
        self.assertReports("effect-without-cleanup", """\
            useEffect(() => {
              const subscription = ditto.sync.registerSubscription('SELECT * FROM orders');
            }, [ditto]);
            """, ".jsx")
        self.assertSilent("effect-without-cleanup", """\
            useEffect(() => {
              const observer = ditto.store.registerObserver('SELECT * FROM orders', (result) => setCount(result.items.length));
              return () => observer.cancel();
            }, [ditto]);
            """, ".jsx")

    def test_ditto_in_ui(self):
        self.assertReports("ditto-in-ui", """\
            export function App() {
              const [ditto, setDitto] = useState(null);
              useEffect(() => {
                Ditto.open(appConfig).then(setDitto);
              }, []);
              return <Orders ditto={ditto} />;
            }
            """, ".jsx")
        self.assertSilent("ditto-in-ui", """\
            const provider = new DittoProvider(appConfig);
            export function App() {
              const ditto = use(provider.instance());
              return <Orders ditto={ditto} />;
            }
            export async function startDitto() {
              return Ditto.open(appConfig);
            }
            """, ".jsx")


class RuleListTest(unittest.TestCase):
    def test_line_rule_names_are_unique(self):
        names = [rule.rule for rule in scan.LINE_RULES]
        self.assertEqual(len(names), len(set(names)), "line rule names must be unique")

    def test_every_reported_rule_is_listed(self):
        source = SCAN_PATH.read_text(encoding="utf-8")
        reported = set(re.findall(r'\breport\(\s*"([a-z0-9-]+)"', source))
        listed = {rule.rule for rule in scan.CONTEXT_RULES}
        self.assertTrue(reported, "no report() calls found")
        self.assertEqual(reported - listed, set(), "rules missing from CONTEXT_RULES")
        self.assertEqual(listed - reported, set(), "CONTEXT_RULES lists rules that nothing reports")

    def test_severities_come_from_the_rule_tables(self):
        source = SCAN_PATH.read_text(encoding="utf-8")
        hardcoded = re.findall(r'Finding\([^)]*"(?:CRITICAL|HIGH|MEDIUM)"', source)
        self.assertEqual(hardcoded, [], "a scanner hardcodes a severity; use report()")

    def test_context_rows_do_not_overlap(self):
        seen = set()
        for row in scan.CONTEXT_RULES:
            for language in row.languages:
                key = (row.rule, language, row.variant)
                self.assertNotIn(key, seen, f"two CONTEXT_RULES rows for {key}")
                seen.add(key)


CHECKLIST_PATH = Path(__file__).resolve().parents[1] / "best-practices/anti-patterns.md"
SEVERITY_SECTIONS = {"Critical": "CRITICAL", "High": "HIGH", "Medium": "MEDIUM"}


def checklist_items() -> list:
    """(line, severity) of every checklist item: the `##` section, or the bold label under
    `## Specific to One SDK`."""
    items = []
    section = None
    for line in CHECKLIST_PATH.read_text(encoding="utf-8").splitlines():
        heading = re.match(r"## (\w+)", line)
        if heading:
            section = SEVERITY_SECTIONS.get(heading.group(1), heading.group(1))
            continue
        if not line.startswith("- [ ] "):
            continue
        if section == "Specific":
            label = re.match(r"- \[ \] \*\*(Critical|High|Medium)\*\*:", line)
            assert label, f"SDK-specific item without a severity label: {line[:80]}"
            items.append((line, SEVERITY_SECTIONS[label.group(1)]))
        elif section in SEVERITY_SECTIONS.values():
            items.append((line, section))
    return items


def checklist_references() -> list:
    """(rule, languages, severity, substring) for every rule and per-language variant."""
    references = []
    for rule in scan.LINE_RULES:
        if isinstance(rule.checklist, dict):
            for language, substring in rule.checklist.items():
                references.append((rule.rule, language, rule.severity, substring))
        else:
            languages = ",".join(rule.languages or rule.pattern) if isinstance(rule.pattern, dict) \
                or rule.languages else "all"
            references.append((rule.rule, languages, rule.severity, rule.checklist))
    for row in scan.CONTEXT_RULES:
        name = row.rule + (f"[{row.variant}]" if row.variant else "")
        references.append((name, ",".join(row.languages), row.severity, row.checklist))
    return references


class ChecklistSeverityTest(unittest.TestCase):
    """The severity of every rule is that of the checklist item it detects."""

    # Rules that detect no checklist item keep their own severity. A new rule must
    # either cite an item or be added here.
    WITHOUT_ITEM = {
        # Ditto opened in a file that defines a screen: the checklist names this only for
        # React components (High); elsewhere the Critical item is an actual second open,
        # which one file cannot show.
        ("ditto-in-ui", "dart,kotlin,swift"),
    }

    def test_every_rule_cites_one_item_with_its_severity(self):
        items = checklist_items()
        self.assertGreater(len(items), 100)
        for name, languages, severity, substring in checklist_references():
            if substring is None:
                continue
            with self.subTest(rule=name, languages=languages):
                matches = [item for item in items if substring in item[0]]
                self.assertEqual(len(matches), 1,
                                 f"{substring!r} must occur in exactly one checklist item")
                self.assertEqual(severity, matches[0][1], f"{name} ({languages}): {substring!r}")

    def test_rules_without_item_are_listed(self):
        without = {(name, languages) for name, languages, _, substring in checklist_references()
                   if substring is None}
        self.assertEqual(without, self.WITHOUT_ITEM)

    def test_emitted_severity_follows_the_table(self):
        findings = scan_findings("""\
            val items = ditto.store.execute("SELECT * FROM orders") { it.items }
            """, ".kt")
        self.assertEqual([(f.rule, f.severity) for f in findings],
                         [("result-leaves-handler", "CRITICAL")])

    def test_raised_severities(self):
        cases = [
            ("type-equals-number", "final q = \"SELECT * FROM t WHERE type(n) = 'number'\";\n", ".dart"),
            ("is-not-null-existence", "final q = 'SELECT * FROM t WHERE x IS NOT NULL';\n", ".dart"),
            ("variable-precision-timestamp", "val at = Instant.now().toString()\n", ".kt"),
            ("float-read-as-double", 'val total = item.value["total"]?.doubleOrNull\n', ".kt"),
            ("float-read-as-double", 'let total = item.value["total"] as? Double\n', ".swift"),
            ("strict-mode-enabled", "await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = true');\n", ".dart"),
        ]
        for rule, code, extension in cases:
            with self.subTest(rule=rule, extension=extension):
                severities = {f.severity for f in scan_findings(code, extension) if f.rule == rule}
                self.assertEqual(severities, {"CRITICAL"})

    def test_kotlin_login_and_observer_severities(self):
        findings = scan_findings("""\
            ditto.auth?.expirationHandler = { dittoInstance, _ ->
                dittoInstance.auth?.login(token = fetchAuthToken(), provider = "YOUR_PROVIDER_NAME")
            }
            """, ".kt")
        self.assertEqual({(f.rule, f.severity) for f in findings},
                         {("login-error-unreported", "CRITICAL")})

    def test_javascript_login_variants(self):
        thrown = scan_findings("""\
            await ditto.auth.setExpirationHandler(async (ditto) => {
              const result = await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
              if (result.error) throw result.error;
            });
            """, ".js")
        self.assertEqual([(f.rule, f.severity) for f in thrown], [("login-error-unreported", "CRITICAL")])
        unread = scan_findings("""\
            await ditto.auth.setExpirationHandler(async (ditto) => {
              await ditto.auth.login(await fetchAuthToken(), 'YOUR_PROVIDER_NAME');
            });
            """, ".js")
        self.assertEqual([(f.rule, f.severity) for f in unread], [("login-error-unreported", "MEDIUM")])

    def test_unconvertible_argument_cites_the_sdk_page(self):
        cases = [
            ("        'createdAt': DateTime.now(),\n", ".dart", "Arguments and value types in Flutter", "HIGH"),
            ('mapOf("id" to id, "createdAt" to Instant.now())\n', ".kt", "Arguments and value types in Kotlin", "HIGH"),
            ('try await ditto.store.execute(query: q, arguments: ["at": Date()])\n', ".swift",
             "Arguments and value types in Swift", "HIGH"),
            ("await tx.execute('UPDATE stats SET ratio = :ratio WHERE _id = :id', { id, ratio: NaN });\n", ".js",
             "Arguments and value types in JavaScript", "CRITICAL"),
        ]
        for code, extension, guide, severity in cases:
            with self.subTest(extension=extension):
                findings = [f for f in scan_findings(code, extension) if f.rule == "unconvertible-argument"]
                self.assertEqual([(f.guide, f.severity) for f in findings], [(guide, severity)])


class StatementBoundaryTest(ScannerTestCase):
    def test_registration_after_a_line_without_semicolon(self):
        self.assertReports("discarded-subscription", """\
            val stores = loadStores()
            ditto.sync.registerSubscription("SELECT * FROM orders")
            """, ".kt")
        self.assertReports("discarded-observer", """\
            let config = makeConfig()
            try ditto.store.registerObserver(query: "SELECT * FROM orders") { _ in }
            """, ".swift")
        self.assertReports("discarded-subscription", """\
            const stores = loadStores()
            ditto.sync.registerSubscription('SELECT * FROM orders')
            """, ".ts")

    def test_registration_after_a_trailing_comment(self):
        self.assertReports("discarded-subscription", """\
            load(); // prepare the store
            ditto.sync.registerSubscription('SELECT * FROM orders');
            """, ".js")
        self.assertReports("discarded-observer", """\
            init {
                load() // see https://docs.ditto.live
                ditto.store.registerObserver("SELECT * FROM orders") { result -> show(result) }
            }
            """, ".kt")

    def test_registration_in_a_for_each_lambda(self):
        self.assertReports("discarded-subscription", """\
            storeIds.forEach { id ->
                ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :id", mapOf("id" to id))
            }
            """, ".kt")

    def test_continuation_lines_stay_silent(self):
        cases = [
            ("val subscription =\n    ditto.sync.registerSubscription(\"SELECT * FROM orders\")\n", ".kt"),
            ("subscriptions +=\n    ditto.sync.registerSubscription(\"SELECT * FROM orders\")\n", ".kt"),
            ("const subscribe = () =>\n  ditto.sync.registerSubscription('SELECT * FROM orders')\n", ".ts"),
            ("const subscription = enabled ?\n  ditto.sync.registerSubscription('SELECT * FROM orders') : null\n", ".ts"),
            ("return (\n  ditto.sync.registerSubscription('SELECT * FROM orders')\n)\n", ".ts"),
            ("let subscription = enabled // keep it\n    ? try ditto.sync.registerSubscription(query: q) : nil\n", ".swift"),
            ("val subscription = ditto\n    .sync.registerSubscription(\"SELECT * FROM orders\")\n", ".kt"),
            ("func subscribe() -> DittoSyncSubscription? {\n    return\n        try? ditto.sync.registerSubscription(query: q)\n}\n", ".swift"),
        ]
        for code, extension in cases:
            with self.subTest(code=code):
                self.assertSilent("discarded-subscription", code, extension)


class LogicalStatementTest(ScannerTestCase):
    def test_dart_adjacent_literals(self):
        findings = scan_findings("""\
            await ditto.store.execute(
              'CREATE INDEX IF NOT EXISTS idx_orders_storeId_createdAt '
              'ON orders (storeId, createdAt DESC)',
            );
            """, ".dart")
        hits = [f for f in findings if f.rule == "composite-index-mixed-direction"]
        self.assertEqual([f.line for f in hits], [2])
        self.assertIn("createdAt DESC", hits[0].code)

    def test_dart_interpolation_on_a_later_line(self):
        findings = scan_findings("""\
            final query = 'SELECT * FROM orders '
                'WHERE storeId = $storeId';
            """, ".dart")
        self.assertEqual([(f.rule, f.line) for f in findings], [("dql-string-interpolation", 1)])
        self.assertSilent("dql-string-interpolation", """\
            final query = 'SELECT * FROM orders '
                'WHERE storeId = :storeId';
            """, ".dart")

    def test_where_on_a_later_line(self):
        self.assertSilent("delete-evict-use-ids", """\
            await ditto.store.execute('DELETE FROM orders USE IDS :ids '
                'WHERE status = :status', arguments: args);
            """, ".dart")
        self.assertReports("delete-evict-use-ids", """\
            await ditto.store.execute('DELETE FROM orders '
                'USE IDS :ids', arguments: args);
            """, ".dart")

    def test_concatenation_across_lines(self):
        findings = scan_findings("""\
            val query = "SELECT * FROM orders WHERE storeId = '" +
                storeId + "'"
            """, ".kt")
        self.assertEqual([(f.rule, f.line) for f in findings], [("dql-string-interpolation", 1)])
        self.assertReports("dql-string-interpolation", """\
            const query = 'SELECT * FROM orders WHERE storeId = ' +
              storeId;
            """, ".js")

    def test_literals_joined_with_plus_are_not_interpolation(self):
        self.assertSilent("dql-string-interpolation", """\
            val query = "SELECT * FROM orders " +
                "WHERE storeId = :storeId"
            """, ".kt")
        self.assertSilent("dql-string-interpolation", """\
            const query = 'SELECT * FROM orders '
              + 'WHERE storeId = :storeId';
            """, ".js")

    def test_multi_line_strings(self):
        findings = scan_findings('''\
            val query = """
                DELETE FROM orders
                USE IDS :ids
            """
            ''', ".kt")
        self.assertEqual([(f.rule, f.line) for f in findings], [("delete-evict-use-ids", 1)])
        self.assertReports("composite-index-mixed-direction", '''\
            let query = """
                CREATE INDEX idx_orders ON orders (
                    storeId, createdAt DESC)
                """
            ''', ".swift")
        self.assertReports("delete-evict-use-ids", """\
            await ditto.store.execute(`
              EVICT FROM orders
              USE IDS :ids
            `);
            """, ".js")
        self.assertReports("dql-string-interpolation", """\
            await ditto.store.execute(`
              SELECT * FROM orders
              WHERE storeId = '${storeId}'
            `);
            """, ".ts")

    def test_strings_without_dql_keep_their_pairing(self):
        statement = "await ditto.store.execute('SELECT * FROM orders WHERE s = ' + status);\n"
        expected = [(f.rule, 1) for f in scan_findings(statement, ".ts")]
        self.assertEqual(expected, [("dql-string-interpolation", 1)])
        findings = scan_findings("const banner = `\n  Kitchen\n`;\n" + statement
                                 + "const footer = `\n  bye\n`;\n", ".ts")
        self.assertEqual([(f.rule, f.line) for f in findings], [("dql-string-interpolation", 4)])
        findings = scan_findings('val banner = """\n    Kitchen\n"""\n'
                                 'val q = "DELETE FROM orders USE IDS :ids"\n'
                                 'val footer = """\n    WHERE done\n"""\n', ".kt")
        self.assertEqual([(f.rule, f.line) for f in findings], [("delete-evict-use-ids", 4)])

    def test_a_string_that_holds_code_is_not_one_statement(self):
        findings = scan_findings("""\
            await writeFile(script, `
              import { Ditto } from '@dittolive/ditto';
              const ditto = await Ditto.open(${JSON.stringify(config)});
              await ditto.store.execute('INSERT INTO t DOCUMENTS (:d)', { d: { _id: 'm' } });
              const t = new TransportConfig();
            `);
            """, ".js")
        self.assertEqual([(f.rule, f.line) for f in findings], [("fresh-transport-config", 5)])

    def test_unrelated_lines_are_not_joined(self):
        findings = scan_findings("""\
            final label = 'Orders'
                'Today';
            final createdAt = DateTime.now().toIso8601String();
            """, ".dart")
        self.assertEqual([(f.rule, f.line) for f in findings], [("zone-less-timestamp", 3)])


class SubscriptionFilterTest(ScannerTestCase):
    RULE = "subscription-filter-misses-documents"

    def test_reports_not_equal_not_in_and_clock(self):
        self.assertReports(self.RULE, """\
            val subscription = ditto.sync.registerSubscription("SELECT * FROM orders WHERE status != 'closed'")
            """, ".kt")
        self.assertReports(self.RULE, """\
            _subscription = ditto.sync.registerSubscription(
              'SELECT * FROM orders WHERE status NOT IN :closed',
              arguments: {'closed': ['done', 'void']},
            );
            """, ".dart")
        self.assertReports(self.RULE, """\
            subscription = try ditto.sync.registerSubscription(
                query: "SELECT * FROM orders WHERE createdAt > clock() - :window", arguments: ["window": 86_400_000])
            """, ".swift")

    def test_silent_on_equality_and_outside_subscriptions(self):
        self.assertSilent(self.RULE, """\
            const subscription = ditto.sync.registerSubscription('SELECT * FROM orders WHERE storeId = :storeId', { storeId });
            """, ".js")
        self.assertSilent(self.RULE, """\
            val open = ditto.store.execute("SELECT * FROM orders WHERE status != 'closed'") { r -> r.items.size }
            """, ".kt")
        self.assertSilent(self.RULE, """\
            val subscription = ditto.sync.registerSubscription("SELECT * FROM orders WHERE storeId = :id", mapOf("id" to id))
            if (subscription != null) show()
            """, ".kt")

    def test_swift_forced_cast_to_double(self):
        self.assertReports("float-read-as-double", 'let total = item.value["total"] as! Double\n', ".swift")


def run_main(arguments: list) -> tuple:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = scan.main(arguments)
    return code, out.getvalue(), err.getvalue()


CRITICAL_LINE = "final q = 'SELECT * FROM t WHERE s IN (:values)';\n"
MEDIUM_LINE = "final major = Ditto.version.split('.').first;\n"


def write(root: Path, relative: str, text: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


class MissingPathTest(unittest.TestCase):
    def test_missing_path_is_reported_and_other_paths_are_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            source = write(Path(directory), "Example.dart", CRITICAL_LINE)
            missing = str(Path(directory) / "test")
            code, out, err = run_main([str(source), missing])
        self.assertEqual(code, 2)
        self.assertIn("in-parenthesized-parameter", out)
        self.assertIn(missing, err)
        self.assertIn("does not exist", err)

    def test_no_source_file_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            write(Path(directory), "README.md", "# Orders\n")
            code, out, err = run_main([directory])
        self.assertEqual(code, 2)
        self.assertIn("no source file", err)

    def test_missing_path_wins_over_fail_on(self):
        with tempfile.TemporaryDirectory() as directory:
            source = write(Path(directory), "Example.dart", CRITICAL_LINE)
            code, _, _ = run_main([str(source), str(Path(directory) / "test"), "--fail-on", "MEDIUM"])
        self.assertEqual(code, 2)


class CommandLineTest(unittest.TestCase):
    def test_exit_zero_with_hits_by_default(self):
        with tempfile.TemporaryDirectory() as directory:
            write(Path(directory), "a.dart", CRITICAL_LINE)
            code, out, _ = run_main([directory])
        self.assertEqual(code, 0)
        self.assertIn("in-parenthesized-parameter", out)

    def test_fail_on(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "medium.dart", MEDIUM_LINE)
            self.assertEqual(run_main([directory, "--fail-on", "HIGH"])[0], 0)
            self.assertEqual(run_main([directory, "--fail-on", "MEDIUM"])[0], 1)
            write(root, "critical.dart", CRITICAL_LINE)
            self.assertEqual(run_main([directory, "--fail-on", "CRITICAL"])[0], 1)
            self.assertEqual(run_main([directory, "--fail-on", "HIGH", "--json"])[0], 1)

    def test_fail_on_counts_only_reported_hits(self):
        with tempfile.TemporaryDirectory() as directory:
            write(Path(directory), "medium.dart", MEDIUM_LINE)
            code, _, _ = run_main([directory, "--fail-on", "MEDIUM", "--min-severity", "HIGH"])
        self.assertEqual(code, 0)

    def test_summary_on_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "a.dart", CRITICAL_LINE + MEDIUM_LINE)
            write(root, "b.dart", "// ditto-scan: ignore\n" + CRITICAL_LINE)
            code, out, err = run_main([directory, "--min-severity", "HIGH", "--json"])
        self.assertEqual(code, 0)
        self.assertEqual([f["rule"] for f in json.loads(out)], ["in-parenthesized-parameter"])
        self.assertIn("2 files scanned", err)
        self.assertIn("1 hit reported (1 CRITICAL, 0 HIGH, 0 MEDIUM)", err)
        self.assertIn("1 hidden by --min-severity", err)
        self.assertIn("1 suppressed", err)

    def test_summary_without_hits(self):
        with tempfile.TemporaryDirectory() as directory:
            write(Path(directory), "a.dart", "void main() {}\n")
            code, out, err = run_main([directory])
        self.assertEqual(code, 0)
        self.assertIn("No candidate anti-patterns found", out)
        self.assertIn("1 file scanned", err)
        self.assertIn("0 hits reported", err)


class ExclusionTest(unittest.TestCase):
    def scanned(self, root: Path, arguments: list = ()) -> set:
        code, out, _ = run_main([str(root), "--json", *arguments])
        return {Path(f["path"]).relative_to(root).as_posix() for f in json.loads(out)}

    def test_default_exclusions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "lib/orders.dart", CRITICAL_LINE)
            for excluded in (".dart_tool/a.dart", "build/a.dart", "node_modules/x/a.js", "Pods/a.swift",
                             ".swiftpm/a.swift", "Carthage/a.swift", "vendor/a.js", ".gradle/a.kt",
                             ".expo/a.js", "coverage/a.js", "dist/a.js", "DerivedData/a.swift",
                             ".build/a.swift", "lib/orders.g.dart", "lib/orders.freezed.dart",
                             "src/types.d.ts", "src/bundle.min.js"):
                write(root, excluded, "const q = 'SELECT * FROM t WHERE s IN (:values)';\n")
            self.assertEqual(self.scanned(root), {"lib/orders.dart"})

    def test_explicit_paths_are_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generated = write(root, "lib/orders.g.dart", CRITICAL_LINE)
            write(root, "build/a.dart", CRITICAL_LINE)
            code, out, _ = run_main([str(generated), "--json"])
            self.assertEqual(len(json.loads(out)), 1)
            code, out, _ = run_main([str(root / "build"), "--json"])
            self.assertEqual(len(json.loads(out)), 1)

    def test_exclude_option(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("lib/orders.dart", "lib/generated/api.dart", "test/orders_test.dart",
                             "lib/orders_test.dart"):
                write(root, relative, CRITICAL_LINE)
            self.assertEqual(self.scanned(root, ["--exclude", "lib/generated", "--exclude", "*_test.dart"]),
                             {"lib/orders.dart"})
            self.assertEqual(self.scanned(root, ["--exclude", "test/"]),
                             {"lib/orders.dart", "lib/generated/api.dart", "lib/orders_test.dart"})


class SuppressionTest(unittest.TestCase):
    def rules(self, code: str) -> list:
        return [f.rule for f in scan_findings(code, ".dart")]

    def test_same_line_and_line_above(self):
        self.assertEqual(self.rules(
            "final q = 'SELECT * FROM t WHERE s IN (:values)'; // ditto-scan: ignore\n"), [])
        self.assertEqual(self.rules("""\
            // ditto-scan: ignore[in-parenthesized-parameter]
            final q = 'SELECT * FROM t WHERE s IN (:values)';
            """), [])
        self.assertEqual(self.rules("""\
            // ditto-scan: ignore[zone-less-timestamp, in-parenthesized-parameter]
            final q = 'SELECT * FROM t WHERE s IN (:values)';
            """), [])

    def test_other_rules_and_other_lines_are_kept(self):
        self.assertEqual(self.rules("""\
            // ditto-scan: ignore[zone-less-timestamp]
            final q = 'SELECT * FROM t WHERE s IN (:values)';
            """), ["in-parenthesized-parameter"])
        self.assertEqual(self.rules("""\
            final a = 1; // ditto-scan: ignore
            final q = 'SELECT * FROM t WHERE s IN (:values)';
            """), ["in-parenthesized-parameter"])
        self.assertEqual(self.rules("""\
            // ditto-scan: ignore

            final q = 'SELECT * FROM t WHERE s IN (:values)';
            """), ["in-parenthesized-parameter"])

    def test_suppressed_hits_are_counted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write(Path(directory), "a.dart",
                         "final q = 'SELECT * FROM t WHERE s IN (:values)'; // ditto-scan: ignore\n")
            result = scan.scan_paths([str(path)])
        self.assertEqual((result.findings, result.suppressed, result.files), ([], 1, 1))


if __name__ == "__main__":
    unittest.main()
