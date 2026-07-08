# Codex Master Rules for Pharos v0.3

Use these rules for every task in this package.

## Repository

Work on `https://github.com/DBvc/pharos`.

## Non-negotiable architecture

1. OCaml core owns domain model, state transitions, triage, merge, policy, evidence, approvals, and timeline.
2. SwiftUI is a presentation and review surface only.
3. Source adapters can create `SourceSignal` values and fetch bounded context, but cannot authorize or execute external writeback by themselves.
4. Skills can generate summaries, judgments, drafts, and proposed actions, but cannot authorize them.
5. External writeback must go through policy checks in OCaml core.
6. Approval must be bound to current action payload hash.
7. L4/L5 actions are not executable in the MVP.
8. Do not log secrets, tokens, authorization headers, or full sensitive payloads.
9. Tests must not call real Feishu, GitLab, or any external network service unless the specific task explicitly says it is a manual dev acceptance step.
10. Each task must leave the repo runnable.

## Workflow for every task

1. Create the branch specified in `EXECUTION_ORDER.md`.
2. Verify expected files exist.
3. Read relevant spec file from `specs/`.
4. Make only the changes requested by the task.
5. Update docs touched by the API or behavior change.
6. Run relevant commands:

```bash
cd core && dune build
cd core && dune runtest
swift build --package-path ui/macos/PharosApp
```

7. If a command cannot run because the environment lacks a tool, report that explicitly and still provide a best-effort static review.
8. End with:

```text
Changed files:
Tests run:
Acceptance status:
Known follow-up:
```

## Stop conditions

Stop and report instead of guessing if:

1. A required file path is missing or renamed.
2. Current repo behavior contradicts a task spec.
3. Implementing the task would require external credentials not supplied.
4. A requested external write would bypass policy.
5. You cannot preserve the approval hash invariant.

## Forbidden shortcuts

1. Do not implement Today grouping only in Swift.
2. Do not make `/v0/today` return both old and new top-level fields.
3. Do not silently drop evidence or timeline to simplify models.
4. Do not hardcode request IDs or fixture paths in production code.
5. Do not use the Swift app to call GitLab/Feishu directly.
6. Do not introduce cloud services.
7. Do not auto-approve actions in tests unless the test is explicitly about no-approval-required risk levels.
