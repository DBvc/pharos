# Project Context for Codex

Repository: `https://github.com/DBvc/pharos`

Current known starter shape:

```text
core/                  OCaml core, local HTTP API, SQLite persistence, policy gate
ui/macos/PharosApp/    SwiftUI macOS starter app and API client
protocol/              OpenAPI draft
config/                example TOML config
examples/              manual and future source-signal fixtures
docs/                  PRD, architecture, UX, security, dogfood, API, iteration notes
scripts/               local development helpers
```

Current product direction already present in the repo:

```text
Pharos watches your work systems, prepares the next move, and asks before it acts.
看住信号 -> 整理证据 -> 准备动作 -> 等我拍板 -> 执行留痕
```

Current mismatch to fix first:

```text
README and docs/USER_EXPERIENCE.md use the new decision-cockpit mental model.
docs/API.md, protocol/openapi.yaml, core/lib/domain.ml, core/lib/store.ml, CLI today output, and Swift TodayView still expose old lifecycle buckets.
```

The first v0.3 alignment task must remove this mismatch without deleting internal states.

## Expected existing files

Codex should verify these files exist before starting task 01:

```text
README.md
docs/USER_EXPERIENCE.md
docs/API.md
docs/ARCHITECTURE.md
docs/ITERATION_PLAN.md
docs/CODEX_PLAN.md
docs/DOGFOOD.md
protocol/openapi.yaml
core/lib/domain.ml
core/lib/store.ml
core/lib/runner.ml
core/lib/policy.ml
core/lib/migrations.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
core/test/policy_smoke.ml
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Core/AppState.swift
ui/macos/PharosApp/Sources/PharosApp/Views/TodayView.swift
ui/macos/PharosApp/Sources/PharosApp/Views/RequestDetailView.swift
```

If a file is missing or substantially renamed, Codex must stop and report the mismatch instead of guessing.

## v0.3 product delta

v0.2 PRD remains the MVP scope baseline. v0.3 updates the user-facing language and the next iteration order:

1. Today groups are attention groups: `Needs Decision`, `Needs Input`, `Watching`, `Handled`, `Noise`.
2. Internal lifecycle states remain: `New`, `Triaging`, `NeedsContext`, `Running`, `ReadyForReview`, `Waiting`, `Approved`, `Executing`, `Done`, `Failed`, `Snoozed`, `Archived`.
3. `ProposedAction` remains internal and API detail-level language; the UI calls it `Prepared next move`.
4. Request detail is organized around four user questions:
   - What is this?
   - Why did Pharos bring it to me?
   - What evidence did Pharos use?
   - What exactly will happen if I approve?
5. Merge identity is promoted before real high-volume source adapters.
6. GitLab read-only adapter comes before Feishu read adapters because MR shape is clearer for evidence, timeline, and review draft validation.
