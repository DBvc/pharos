# Pharos Architecture

## North star

Pharos is a local-first work cockpit. Its core job is to turn scattered work signals into review-gated executable work. The architectural priority is not maximum automation. The priority is controlled automation with evidence.

```text
SwiftUI macOS app
  ↕ local HTTP first, Unix socket later
OCaml core daemon
  ↕ adapter protocol
SQLite + file store + Keychain-owned secrets
```

## Non-negotiable boundaries

1. The OCaml core owns the domain model and state transitions.
2. The policy gate is the only path to external writeback.
3. Source adapters can create `SourceSignal` values, but cannot directly create final approvals or execute external actions.
4. Skills can propose actions, but cannot authorize them.
5. UI can request approval, editing, rejection, snooze, archive, or more context, but cannot directly write external systems.
6. Every reviewable action must have evidence and a timeline.
7. Approval is bound to an action payload hash.

## Concept boundary

Pharos has two related models, and this concept boundary is a product and architecture contract.

### User-facing model

The user-facing model is the product surface:

```text
watch signals -> gather evidence -> prepare a next move -> ask for approval -> execute with an audit trail
```

Today and Request Detail should speak in attention and decision terms:

- Needs Decision.
- Needs Input.
- Watching.
- Handled.
- Noise.
- Evidence used.
- Prepared next move.
- Approval target and result.

The SwiftUI app can show internal status as secondary metadata when useful, but the main UI does not need to expose audit and storage concepts such as `payload_hash`, `SourceSignal`, raw adapter payloads, policy internals, or database table names.

### Core internal model

The core internal model is the audit and safety substrate:

| User-facing concept | Core internal model |
|---|---|
| Signal Pharos watched | `SourceSignal` |
| Decision card | `WorkRequest` plus review state |
| Prepared next move | `ProposedAction` |
| User approval or rejection | approval records and action status |
| Evidence used | evidence items and context bundle |
| Execution record | timeline events |
| Ask before acting | policy gate plus approval `payload_hash` check |

The OCaml core owns domain entities, state transitions, risk policy, approval binding, evidence, timeline, and writeback authorization. UI, adapters, and skills may present, submit, or propose data, but they do not become the source of truth for domain state or policy decisions.

## Runtime components

### 1. SwiftUI macOS app

Responsibilities:

- Main cockpit window.
- Menu bar entry.
- Quick capture.
- Local notification entry points.
- Review Gate UI.
- Source, rules, and metrics pages.
- Keychain integration for future source credentials.

The Swift app should stay thin. It should not contain triage rules, writeback policy, merge logic, or source-specific business logic.

### 2. OCaml core daemon

Responsibilities:

- Domain model.
- SQLite store.
- Local HTTP API.
- Source signal capture.
- Triage and merge pipeline.
- Context bundle creation.
- Skill routing.
- Proposed action generation.
- Review Gate decisions.
- Policy enforcement.
- Evidence and timeline.
- Metrics aggregation.

The daemon should be usable without the Swift app. CLI and future tools should talk to the same API or core library.

### 3. SQLite store

The starter uses SQLite with an append-friendly schema. The shape favors auditability over cleverness.

Core tables:

```text
source_signals
work_requests
proposed_actions
approvals
evidence_items
timeline_events
rules
metrics_daily
```

The first version stores JSON-ish payloads as text fields where appropriate. Later iterations can split richer normalized tables.

### 4. Adapters

Adapters are source-specific edge workers. They may be implemented in OCaml, TypeScript, Python, Go, or another language if that improves SDK support. The contract matters more than the adapter language.

Allowed:

- Poll or receive external events.
- Normalize into `SourceSignal`.
- Fetch bounded context.
- Execute approved writeback when invoked by the policy-controlled core.

Not allowed:

- Directly creating approvals.
- Directly writing external systems outside the policy gate.
- Silently mutating work request state.
- Writing secrets into logs or metrics.

### 5. Skills

MVP skills are built-ins:

- Triage and request summarization.
- Context summarization.
- Reply or comment draft generation.
- GitLab MR read-only review draft.
- Project progress suggestion.
- Document understanding.

Skills produce typed outputs. They can fail visibly. They cannot bypass policy.

## Request lifecycle

```text
Capture
  → Normalize
  → Detect
  → Merge
  → Classify
  → Gather Context
  → Plan / Execute Safe Steps
  → Gate
  → User Review
  → Continue
  → Complete
```

The starter implements a simplified manual path:

```text
Manual capture
  → source signal
  → work request
  → evidence
  → proposed local action
  → ready for review
  → approve / edit / reject
  → execute approved local action
  → done
```

## Module map

```text
core/lib/domain.ml       Types and JSON encoders.
core/lib/migrations.ml   SQLite schema.
core/lib/store.ml        Persistence API.
core/lib/triage.ml       Starter triage rules.
core/lib/policy.ml       Approval and execution checks.
core/lib/runner.ml       Orchestrates capture and review flows.
core/bin/daemon          Local HTTP API.
core/bin/cli             Direct local CLI.
```

## API shape

P0 local API:

```text
GET  /health
POST /v0/capture
GET  /v0/today -> TodaySnapshot with DecisionCard groups
GET  /v0/debug/today-internal -> optional internal lifecycle buckets
GET  /v0/requests/:id
POST /v0/actions/:id/approve
POST /v0/actions/:id/edit-and-approve
POST /v0/actions/:id/reject
POST /v0/actions/:id/execute-local
```

The OCaml core maps internal lifecycle states into the user-facing Today groups. Swift consumes the `TodaySnapshot` contract and should not become the implementation site for Today grouping rules.

Future API:

```text
GET  /v0/events/stream
POST /v0/requests/:id/request-more-context
POST /v0/requests/:id/snooze
POST /v0/requests/:id/archive
POST /v0/requests/:id/false-positive
GET  /v0/sources
PATCH /v0/sources/:id
GET  /v0/metrics?days=7
POST /v0/metrics/export
```

## Data flow for approved writeback

```text
ProposedAction(body, target, risk)
  → payload_hash = hash(target + body + risk)
  → Review Gate displays body, target, evidence
  → user approves or edits
  → approval(action_id, action_hash, approved_body)
  → execute checks current action hash == approval hash
  → adapter writeback only after check passes
  → timeline records result
```

This prevents the classic sneak-through bug where the UI approves one payload but the executor sends another.

## Why OCaml core and SwiftUI UI

OCaml is a strong fit for the core because the most important part of Pharos is a typed state machine with hard safety invariants. SwiftUI is a strong fit for a macOS-first local cockpit because the app needs menu bar presence, notifications, local app lifecycle, and future Keychain integration.

## Future packaging

M0 can run the core daemon separately. M1 should let the Swift app start, supervise, and stop `pharosd`. M2 should package the daemon binary inside the app bundle and communicate over a Unix domain socket with a per-install capability token.
