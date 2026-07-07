# Project Blueprint

This blueprint turns the product PRD into an implementation-shaped starter plan.

## Product goal

Pharos collects work signals, turns useful signals into work requests, gathers enough context, runs safe automation, pauses at Review Gate, then continues only after approval.

## Implementation goal for this starter

Create a repo that can grow by vertical slices:

```text
Manual capture
  → persisted source signal
  → persisted work request
  → evidence
  → proposed action
  → review decision
  → policy-checked execution
  → timeline
```

This is the smallest useful version of the whole product loop.

## Directory ownership

```text
core/
  Owner: domain truth and safety.
  Language: OCaml.
  Contains: state machine, persistence, policy, skills, adapters, local API, CLI.

ui/macos/PharosApp/
  Owner: macOS cockpit surface.
  Language: SwiftUI.
  Contains: Today, detail, capture, Review Gate UI, sources/rules/metrics shells.

protocol/
  Owner: local API contract.
  Format: OpenAPI now, generated types later.

docs/
  Owner: product and engineering memory.
  Contains: PRD, architecture, iteration plan, security, dogfood, Codex task plan.

examples/
  Owner: repeatable source simulations.
  Format: JSON fixtures for manual, GitLab, Feishu Chat, Feishu Project, Feishu Docs.
```

## Core module responsibilities

```text
domain.ml
  All major domain types and JSON encoders.

time.ml / ids.ml
  Time and id helpers.

migrations.ml
  SQLite schema.

store.ml
  Persistence API. No UI logic. No adapter network calls.

triage.ml
  Starter triage rules. Later becomes rules plus model-assisted typed output.

runner.ml
  Orchestrates capture, triage, action creation, and review flows.

policy.ml
  Approval hash checks and execution authorization.

adapter.ml
  Adapter protocol and P0 capability declarations.

skill.ml
  Skill protocol and MVP built-in skill list.

rules.ml
  Rule domain placeholder.

metrics.ml
  Metrics domain placeholder.
```

## UI responsibilities

```text
RootView
  Sidebar and page routing.

TodayView
  Main queue grouped by status.

RequestDetailView
  Header, summary, actions, evidence, timeline, Review Gate controls.

CaptureView
  Manual capture entry.

SourcesView
  Stub source management page.

RulesView
  Placeholder for M2.

MetricsView
  Placeholder for M4.

APIClient
  Local HTTP client with snake_case encoding and decoding.

AppState
  Thin async state container.
```

## First execution path

```text
POST /v0/capture
  → Runner.capture_manual
  → Store.insert_source_signal
  → Store.insert_work_request
  → Store.insert_evidence
  → Store.insert_action
  → Store.insert_timeline x3
  → Today shows Ready for Review
```

Review path:

```text
POST /v0/actions/:id/approve
  → Policy.approve
  → hash current or edited body
  → Store.insert_approval
  → Store.update_action_status Approved
  → Store.update_request_status Approved
  → Store.insert_timeline approval
```

Execution path:

```text
POST /v0/actions/:id/execute-local
  → Policy.execute_local
  → verify risk is executable
  → verify target is local for starter
  → verify approval exists if required
  → verify approval hash equals action hash
  → mark action executed
  → mark request done
  → timeline records result
```

## What must not move

Do not move these into SwiftUI:

- Risk classification enforcement.
- Approval hash computation.
- External writeback authorization.
- Source merge identity.
- Evidence requirement checks.
- Metrics around unapproved write attempts.

The UI is allowed to display the cockpit and ask for actions. The core decides what is legal.
