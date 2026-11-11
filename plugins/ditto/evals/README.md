# Ditto Plugin Evals

Behavior tests for the `ditto` plugin, run with [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals) (Claude Code v2.1.269 or later). Each case sends a realistic request, then checks that the right skill was invoked and that the answer follows the Ditto best practices guide. `no-trigger-postgres` checks that the skills stay out of unrelated SQL work.

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
| `audit-schema-change` | audit | A pull request to a released app: a field renamed in place and a new `status` value reported as breaking, an optional field as additive, and the map fix for a new array as free to change before release |
| `audit-schema-demo` | audit | A field rename in a workshop demo is not held to the versioning and rollout of a released app |
| `no-trigger-postgres` | none | No Ditto skill for a PostgreSQL question |

Run from `plugins/ditto/`. Runs use your Claude credentials and count against your usage.

```bash
# Quick check while editing skills: one run per case, no baseline arm
claude plugin eval . --runs 1 --ablation none --scaffold --allow-tools "Bash(python3 *)"

# Full run with the no-plugin baseline (default: 3 runs per case and arm)
claude plugin eval . --scaffold --allow-tools "Bash(python3 *)" --max-cost-usd 20
```

`--scaffold` runs the `scaffold.sh` of the `audit-*` cases, each of which only copies its fixture into the run's workspace; `Bash(python3 *)` lets the audit skill run its scanner. Results are written to `evals/results/`, which is ignored by git. Add a case whenever a skill change fixes a behavior that an eval did not catch.
