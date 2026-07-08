# Codex Implementation Plan

This document is written for repeated Codex iterations. Each task should leave the repo in a runnable state.

## Ground rules for Codex

1. Do not move policy enforcement into the UI.
2. Do not let adapters call external write APIs without an approval id.
3. Do not add hidden network calls in tests.
4. Do not log secrets, tokens, raw authorization headers, or full sensitive payloads.
5. Keep each iteration vertical and demoable.
6. Update docs when architecture changes.

## Task 000: Align v0.3 PRD, docs, and OpenAPI

Prompt:

```text
Align README, docs/API.md, docs/ARCHITECTURE.md, docs/ITERATION_PLAN.md, docs/CODEX_PLAN.md, and protocol/openapi.yaml with docs/PRD_v0.3.md. The user-facing Today contract is a decision cockpit: Needs Decision, Needs Input, Watching, Handled, and Noise. Preserve internal lifecycle states for audit/debugging, and allow old lifecycle buckets only under /v0/debug/today-internal. Do not change OCaml or Swift runtime code in this task.
```

Acceptance:

- README identifies docs/PRD_v0.3.md as the MVP scope source of truth.
- docs/API.md and protocol/openapi.yaml agree on the v0.3 `/v0/today` response.
- Architecture states that `/v0/today` returns `TodaySnapshot` with `DecisionCard` groups.
- This is v0.3 plan Task 01. v0.3 plan Tasks 01-03 are not releasable independently until docs/API/OpenAPI, core DTO mapping, and Swift UI consumption all agree.

## Task 001: Verify M0 build

Prompt:

```text
Inspect the OCaml core and SwiftUI starter. Make the OCaml project compile with the declared opam dependencies. Do not add external writeback. Preserve the policy-gate approval hash invariant. Add a short note to docs/CODEX_NOTES.md with any dependency or build fixes.
```

Acceptance:

- `cd core && dune build` succeeds.
- `cd core && dune runtest` succeeds.
- `scripts/run-core.sh` starts the daemon.
- `POST /v0/capture` creates a request.

## Task 002: Improve Request Detail editing

Prompt:

```text
Implement edit-and-approve in the SwiftUI Request Detail view. The UI should show the proposed action body in an editable text area, call /v0/actions/:id/edit-and-approve, then refresh the request detail. Keep plain approve as a separate path. Do not execute external writeback.
```

Acceptance:

- User can edit a proposed local action.
- Timeline records edited approval.
- Execution uses the edited body.

## Task 003: Fake adapter replay

Prompt:

```text
Add a fake adapter that reads examples/*.json and posts SourceSignal-like payloads into the core. Use it to simulate GitLab MR, Feishu chat, Feishu project, and Feishu docs events. Keep writeback disabled. Add CLI commands to replay each fixture.
```

Acceptance:

- `pharos replay examples/gitlab_mr_signal.json` creates or updates a work request.
- Source kind, actor, URL, and entry reason are visible.
- Replaying the same external id does not create duplicate active requests.

## Task 004: Merge identity

Prompt:

```text
Implement request identity and merge. Add a work_request_identity table keyed by source_kind, external_thread_or_object_id, and normalized subject. New signals from the same MR, Feishu thread, project item, or doc comment should update the active request. Add tests.
```

Acceptance:

- Duplicate test fixtures update the same request.
- Timeline records merge/update events.
- Today list does not duplicate active requests.

## Task 005: Source settings

Prompt:

```text
Implement source settings persistence and API. Add /v0/sources routes and SwiftUI Sources page. Store enabled, read_enabled, write_enabled, scope JSON, last_sync_at, and last_error. Do not implement real remote calls yet.
```

Acceptance:

- Sources page lists all four P0 sources.
- Enabling or disabling a source persists across restart.
- Write permission defaults to off.

## Task 006: GitLab read adapter

Prompt:

```text
Implement the first GitLab read adapter for private GitLab. It should support configured base_url, token from environment during dev, watched projects, assigned MRs, review requests, mentions, pipeline status, and discussions. Normalize into SourceSignal and bounded context. Never write to GitLab in this task.
```

Acceptance:

- A test MR review request creates or updates one work request.
- Detail shows MR title, author, URL, pipeline status, discussion summary, and evidence.
- Adapter errors do not crash the daemon.

## Task 007: Controlled GitLab comment writeback

Prompt:

```text
Add approved GitLab comment writeback. The adapter must accept only an action id and approval id from the core execution path. Re-read the action and approval through policy before sending. Record result URL and external id in timeline and evidence. Block unapproved attempts.
```

Acceptance:

- Approved comment is posted.
- Unapproved comment attempt is blocked.
- Edited approval posts edited content.
- Timeline contains target, approval id, action hash, and result.

## Task 008: Metrics export

Prompt:

```text
Implement daily metrics aggregation for signals, requests, review decisions, false positives, archived count, external writes, and unapproved external write attempts. Add /v0/metrics?days=7 and Markdown/JSON export.
```

Acceptance:

- Metrics page shows 7-day data.
- Export files are written locally.
- Unapproved external write attempts are counted and visible.
