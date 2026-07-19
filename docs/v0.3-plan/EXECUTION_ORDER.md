# Execution Order

Run these tasks in order. Each task is a vertical slice and must leave the repository runnable.

| Order | Task file | Branch name | Main result |
|---:|---|---|---|
| 00 | `codex/00_MASTER_RULES.md` | none | Codex operating contract |
| 01 | `codex/01_CREATE_PRD_V03_AND_DOCS_ALIGNMENT.md` | `codex/v03-docs-alignment` | `docs/PRD_v0.3.md`, docs priority, API docs aligned |
| 02 | `codex/02_DECISION_CARD_API_AND_CORE_MAPPING.md` | `codex/decision-card-api` | `/v0/today` returns v0.3 attention groups |
| 03 | `codex/03_SWIFT_TODAY_DECISION_COCKPIT.md` | `codex/swift-today-decision-cockpit` | Swift Today consumes `DecisionCard` groups |
| 04 | `codex/04_REQUEST_DETAIL_JUDGMENT_VIEW.md` | `codex/request-detail-judgment-view` | Detail page is organized by the four decision questions |
| 05 | `codex/05_POLICY_SAFETY_TESTS_AND_FAILURE_TIMELINE.md` | `codex/policy-safety-tests` | safety invariants covered by tests and blocked attempts logged |
| 06 | `codex/06_FAKE_ADAPTER_REPLAY_AND_MERGE_IDENTITY.md` | `codex/fake-replay-merge-identity` | fixture replay + no duplicate active requests |
| 07 | `codex/07_SOURCE_SETTINGS_SHELL.md` | `codex/source-settings-shell` | persistent source settings API + Swift shell |
| 08 | `codex/08_GITLAB_READ_ONLY_ADAPTER.md` | `codex/gitlab-read-adapter` | GitLab MR read-only sync into SourceSignal + Evidence |
| 09 | `codex/09_BUILTIN_SKILLS_V0.md` | `codex/builtin-skills-v0` | typed skill outputs for triage/context/drafts/MR review |
| 10a | `codex/10_CONTROLLED_GITLAB_WRITEBACK.md` | `codex/local-auth-approval-cas` | loopback local API auth + revision-bound review CAS |
| 10a2 | `codex/07_SOURCE_SETTINGS_SHELL.md` + `codex/08_GITLAB_READ_ONLY_ADAPTER.md` | `codex/source-settings-owner` | persisted source scope owner + effective read/write policy |
| 10b | `codex/10_CONTROLLED_GITLAB_WRITEBACK.md` | `codex/durable-gitlab-writeback` | durable, reconcilable approved GitLab comment delivery |
| 11 | `codex/11_METRICS_DOGFOOD.md` | `codex/metrics-dogfood` | 7-day metrics, export, dogfood readiness |

## Dependency notes

- Tasks 01-03 are one v0.3 Today alignment release batch. Each task must leave the repository runnable, but the v0.3 `/v0/today` contract is not releasable until Task 03 is complete.
- Task 02 must happen before task 03.
- Task 05 can be done immediately after task 02 or 03, but do not start external writeback before task 05 is green.
- Task 06 must happen before task 08. Do not connect real GitLab before stable external merge identity exists.
- Task 08 is read-only. No external writes.
- Task 10a must complete before Task 10b. It authenticates every local `/v0/*` route, leaves only `/health` public, and binds review decisions to the displayed payload hash; it must not add a real GitLab write route.
- Task 10a2 must complete after Task 10a and before Task 10b. Persisted source
  rows own scope and operational permissions; `effective_read` and
  `effective_write` are composed in Core, while GitLab environment config owns
  only base URL, token, and username. Watched projects are not a write allowlist.
- Task 10b is the first task allowed to add a real external write route. It must verify target provenance, persist a durable attempt before the client call, and keep ambiguous outcomes `unknown` until reconciliation or explicit abandon.
- Task 11 metrics Today group counts are daily snapshot/gauge values, not refresh counters.

## Build and test commands every task should run when relevant

```bash
cd core && dune build
cd core && dune runtest
swift build --package-path ui/macos/PharosApp
```

If SwiftPM is unavailable in the environment, Codex must still update Swift code carefully and report that Swift build was not run.
