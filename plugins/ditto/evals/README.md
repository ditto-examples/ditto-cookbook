# Ditto Plugin Evals

Behavior tests for the `ditto` plugin, run with [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals) (Claude Code v2.1.269 or later). Each case sends a realistic request, then checks that the right skill was invoked and that the answer follows the Ditto best practices guide. The `no-trigger-*` cases check that the skills stay out of unrelated database work.

| Case | Skill | Checks |
|---|---|---|
| `soft-delete-filter` | storage-lifecycle / query-sync | `coalesce(isDeleted, false) = false` instead of `!= true` |
| `array-line-items` | data-modeling | Map keyed by ID instead of an array edited on several devices |
| `flutter-observer-widget` | query-sync | `changes` stream, no `onChange`, observer cancelled, parameters |
| `javascript-observer-hook` | query-sync | React hook: synchronous handler, observer cancelled, parameters |
| `kotlin-observer-viewmodel` | query-sync | ViewModel: `StateFlow`, observer released with the ViewModel, parameters |
| `swift-observer-model` | query-sync | SwiftUI model: observer kept and cancelled, arguments, parameters |
| `subscription-per-filter` | query-sync | Stable subscription; filter locally |
| `transaction-review` | transactions-attachments | `store.execute` and network I/O inside a transaction |
| `server-startup` | sdk-setup | Expiration handler before `sync.start()`, no throwing, no `await` on `start()` |
| `audit-fixture` | audit | Finds four planted anti-patterns in a scaffolded `lib/` |
| `audit-cross-device` | audit | Finds four planted defects that no single statement shows: a conditional `UPDATE` used as a lock, an order number from `COUNT(*) + 1`, a total wider than its subscription, and "received" after a local write |
| `audit-schema-change` | audit | A pull request to a released app: a field renamed in place reported as breaking, a new `status` value as breaking or conditional on how 1.4 reads it, an optional field as additive, and the map fix for a new array as free to change before release |
| `audit-schema-demo` | audit | A field rename in a workshop demo is not held to the versioning and rollout of a released app |
| `audit-kotlin` | audit | Android repository: DQL built with string interpolation, a dropped `registerObserver` handle, `DittoQueryResultItem`s returned from the `execute` handler, `.string` on a field that can be missing, and a `parts` array that several devices rewrite; correct code (`observe` with `stateIn`, `_id IN :ids`, `Dispatchers.IO`) is not ranked CRITICAL or HIGH |
| `audit-swift` | audit | Swift package: only `ditto.store` and `ditto.sync` kept (no strong `Ditto` reference), `as? Double` on a price, `IN (:ids)`, an observer that is never cancelled, and a `Date` argument; the correct model and subscription service are not ranked CRITICAL or HIGH |
| `audit-typescript-pr` | audit | A React Native pull request, requested without the word "Ditto": an `async` observer handler that can reject, a `useEffect` without cleanup, `isDeleted != true`, and a `Date` argument; an interpolated query in a file outside the diff is not presented as introduced by the change |
| `audit-clean` | audit | A TypeScript data layer that follows the guide: no invented CRITICAL or HIGH finding (notes and "not checked" items are fine) |
| `no-trigger-postgres` | none | No Ditto skill for a PostgreSQL question |
| `no-trigger-prisma-soft-delete` | none | No Ditto skill for soft delete with an `isDeleted` flag in a Prisma model |

Every `audit-*` case also has a `guide-consulted` grader, which fails when the report says that the bundled guide, the skill's reference files, or the scanner could not be used. A review written from the model's own knowledge can still find the planted defects, so without this grader a run that lacked the guide would pass.

## Running

Run from `plugins/ditto/`. Runs use your Claude credentials and count against your usage.

```bash
# Copy the plugin with the guide's symbolic links resolved (see below)
rm -rf "$TMPDIR/ditto-eval" && rsync -aL --exclude evals/results ./ "$TMPDIR/ditto-eval/"

# Quick check while editing skills: one run per case, no baseline arm
claude plugin eval "$TMPDIR/ditto-eval" --trust-plugin --runs 1 --ablation none --scaffold --allow-tools "Bash(python3 *)" --output-dir "evals/results/$(date -u +%Y-%m-%dT%H-%M-%SZ)"

# Full run with the no-plugin baseline (default: 3 runs per case and arm)
claude plugin eval "$TMPDIR/ditto-eval" --trust-plugin --scaffold --allow-tools "Bash(python3 *)" --max-cost-usd 20 --output-dir "evals/results/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
```

Copy the plugin again after every change to it. Add `--case <name>` to run one case. `--trust-plugin` confirms that you trust the copy, which is new after every copy and cannot be trusted in advance; without it, a run that cannot ask, such as one started with `!` in Claude Code, stops.

Why the plugin is copied, and why each flag is needed:

- **The guide must be inside the plugin directory.** In this repository, `skills/guide/reference/best-practices` and `skills/guide/reference/knowledge` are symbolic links to the guide at the repository root. Runs of `claude plugin eval .` reported that the guide could not be searched; their traces show `Permission to use Grep has been denied because Claude Code is running in don't ask mode` for every search through these links. Reads of the audit skill's own `reference/` files succeeded in the same runs, and the sandbox settings of a run allow reads of the plugin directory. `rsync -aL` copies the link targets into the copy as ordinary files, so the guide is read from inside the plugin directory. The traces did not show a read of another skill's real file, so after changing this setup, confirm it with one run (`--case audit-fixture --runs 1 --ablation none`) and check that its `guide-consulted` grader passes.
- **`--scaffold`** runs the `scaffold.sh` of the `audit-*` cases. Each script only copies its fixture into the run's workspace.
- **`--allow-tools "Bash(python3 *)"`** lets the audit skill run `scripts/scan.py`. A run never asks for permission: Bash is removed unless you grant it, and a shell command outside the grant is refused. The command runs in the OS sandbox, which can read the plugin directory. On macOS, `/usr/bin/python3` prints `xcrun` cache warnings in the sandbox, but the scan still completes. `Read`, `Glob`, and `Grep` need no grant: the cases list them in `allowed_tools`, and the skill searches the guide with them. `audit-kotlin`, `audit-swift`, `audit-typescript-pr`, and `audit-clean` also list `Bash` in `allowed_tools`, so a run without the grant shows it as `not granted` in the progress output.
- **`--output-dir`** writes the results to `evals/results/` of this repository instead of the copy. That directory is ignored by git.

Add a case whenever a skill change fixes a behavior that an eval did not catch.
