"""Tests for the audit Skill's scanner (plugins/ditto/skills/audit/scripts/scan.py).

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
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
        reported = set(re.findall(r'"(?:CRITICAL|HIGH|MEDIUM)",\s*"([a-z0-9-]+)"', source))
        listed = {rule.rule for rule in scan.LINE_RULES} | {rule[0] for rule in scan.CONTEXT_RULES}
        self.assertTrue(reported, "no Finding calls found")
        self.assertEqual(reported - listed, set(), "rules missing from CONTEXT_RULES")


class MissingPathTest(unittest.TestCase):
    def run_main(self, arguments: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = scan.main(arguments)
        return code, out.getvalue(), err.getvalue()

    def test_missing_path_is_reported_and_other_paths_are_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Example.dart"
            source.write_text("final q = 'SELECT * FROM t WHERE s IN (:values)';\n",
                              encoding="utf-8")
            missing = str(Path(directory) / "test")
            code, out, err = self.run_main([str(source), missing])
        self.assertEqual(code, 0)
        self.assertIn("in-parenthesized-parameter", out)
        self.assertIn(missing, err)
        self.assertIn("does not exist", err)

    def test_existing_paths_report_nothing_on_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            code, out, err = self.run_main([directory])
        self.assertEqual(code, 0)
        self.assertEqual(err, "")


if __name__ == "__main__":
    unittest.main()
