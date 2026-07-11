# Task 10: Controlled GitLab writeback

Branch: `codex/gitlab-controlled-writeback`

## Goal

Implement approved GitLab comment writeback through core policy only.

Precondition from Task 09: the action is the current proposal, its target ref is canonical,
and its approval hash still matches after the latest source-evidence refresh.

## Read first

```text
specs/controlled_writeback_contract.md
```

## Files to change

```text
core/lib/policy.ml
core/lib/store.ml
core/lib/domain.ml
core/lib/gitlab_write.ml or core/lib/adapters/gitlab_write.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
core/test/gitlab_writeback_policy_test.ml
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Core/AppState.swift
ui/macos/PharosApp/Sources/PharosApp/Views/RequestDetailView.swift
docs/API.md
protocol/openapi.yaml
```

## Exact implementation steps

1. Add `POST /v0/actions/:id/execute-approved`.
2. Add policy function that re-reads action and latest approval.
3. Check hash match, risk, target allowlist, body length, GitLab source write permission, and target provenance.
4. Add GitLab target ref parser.
5. Add fake GitLab client for tests.
6. Add real GitLab client for manual dev only.
7. On success, update action status and request status.
8. Insert writeback timeline event.
9. Insert writeback evidence item.
10. Swift: external targets use `execute-approved`, not `execute-local`.
11. Local targets may continue using `execute-local` or may also use `execute-approved` if core supports both.

## Do not change

1. Do not call GitLab directly from Swift.
2. Do not execute unapproved L3 actions.
3. Do not support MR merge or approval.
4. Do not support Feishu writeback in this task.
5. Do not execute a GitLab action whose `target_ref` does not match the request's GitLab source identity.
6. Do not execute an approval retained only as audit history after Task 09 refreshed the action payload.

## Commands

```bash
cd core && dune build && dune runtest
swift build --package-path ui/macos/PharosApp
```

## Acceptance

1. Unapproved GitLab comment action is blocked.
2. Edited approval posts edited body to fake client in tests.
3. Hash mismatch blocks.
4. Write permission off blocks.
5. Target provenance mismatch blocks before fake GitLab client is called.
6. Successful fake writeback records timeline and evidence.
7. Swift calls only core API for execution.

## Final response format

```text
Changed files:
Tests run:
Swift build:
Safety acceptance:
Known follow-up:
```
