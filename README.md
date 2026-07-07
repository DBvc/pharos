# Pharos Starter

Local-first AI work cockpit for collecting work signals, running safe automation, and pausing for human review.

This repository is an initial scaffold for the Pharos MVP. It is designed to be a practical starting point for Codex-driven iteration, not a fully finished app. The first slice keeps the safety architecture visible from day one: every request, action, approval, evidence item, and timeline event is represented in the core model.

## What is included

```text
core/                  OCaml core, local HTTP API, SQLite persistence, policy gate
ui/macos/PharosApp/    SwiftUI macOS starter app and API client
protocol/              OpenAPI draft for the local API
docs/                  PRD, architecture, roadmap, security notes, dogfood plan
examples/              Example capture payloads and future source-signal shapes
scripts/               Bootstrap and local development helpers
```

## Current starter slice

The starter implements Milestone 0 shape:

1. Manual capture from CLI or local HTTP API.
2. A persisted `SourceSignal` and `WorkRequest`.
3. A generated local `ProposedAction` with evidence and timeline events.
4. Review operations: approve, edit and approve, reject.
5. A policy gate that verifies approval hashes before executing approved local actions.
6. A SwiftUI shell that can load Today, capture text, inspect a request, and approve or reject a proposed action.

The external Feishu and GitLab adapters are intentionally stubs. Their protocol boundaries are documented so they can be implemented without letting adapters bypass triage, evidence, risk, or review.

## Quick start

### 1. OCaml core

```bash
cd core
opam switch create . 5.1.1 --deps-only --with-test -y
opam install . --deps-only --with-test -y
eval $(opam env)
dune build
```

Start the local daemon:

```bash
../scripts/run-core.sh
```

Capture a manual request from another terminal:

```bash
PHAROS_DB=var/pharos.dev.sqlite dune exec pharos -- capture "Review the GitLab MR about the billing retry logic"
```

Or via HTTP:

```bash
curl -s http://127.0.0.1:8765/health | jq
curl -s -X POST http://127.0.0.1:8765/v0/capture \
  -H 'content-type: application/json' \
  -d '{"body":"Follow up on Feishu project blocker before standup","title":"Follow up blocker"}' | jq
curl -s http://127.0.0.1:8765/v0/today | jq
```

### 2. SwiftUI shell

```bash
cd ui/macos/PharosApp
open Package.swift
```

Run the `PharosApp` target in Xcode. The app expects the core daemon at `http://127.0.0.1:8765`.

## Development philosophy

Pharos should feel like a tower cockpit, not a runaway sprinkler system. The core owns domain state, policy, evidence, and writeback safety. UI and adapters are replaceable surfaces. External writeback must travel through the policy gate, carrying approval and payload hash like a little stamped passport.

## Important documents

- [PRD v0.2](docs/PRD_v0.2.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Iteration plan](docs/ITERATION_PLAN.md)
- [Codex implementation plan](docs/CODEX_PLAN.md)
- [Security and invariants](docs/SECURITY.md)
- [Dogfood plan](docs/DOGFOOD.md)
- [Adapter protocol](docs/ADAPTER_PROTOCOL.md)
- [Local API](docs/API.md)

## Repository status

This is a starter scaffold. Expect to iterate immediately on:

1. Real adapter implementations.
2. Stronger typed JSON and OpenAPI generation.
3. Better SwiftUI request detail UI.
4. Keychain-backed token storage.
5. Metrics aggregation and export.
6. Packaged app bundle that starts and supervises `pharosd`.
