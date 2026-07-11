# Pharos Starter

Pharos watches your work systems, prepares the next move, and asks before it acts.

```text
Pharos 帮你看住工作系统，整理证据、准备下一步；真正行动前一定问你。
```

Pharos is a local-first AI work cockpit. It should not become another inbox. Its job is to turn scattered Feishu, GitLab, document, and manual signals into a small number of prepared decisions: approve, edit, reject, ask for more context, or archive as noise.

This repository is an initial scaffold for the Pharos MVP, not a fully finished app. The starter proves the safety loop in miniature: manual capture becomes a local request with evidence, a proposed action, review controls, policy-checked execution, and timeline records.

## Product mental model

```text
watch signals -> gather evidence -> prepare a next move -> ask for approval -> execute with an audit trail
```

In the user-facing product, Today should answer one question: what needs my attention now? Internally, the core can keep precise request, action, approval, evidence, risk, and hash records. That split is intentional: the user sees a decision cockpit, while the core preserves the audit trail and writeback safety.

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

Return to the repository root, create an ephemeral capability, and run the
daemon and Swift app from the same shell environment:

```bash
cd ..
export PHAROS_CAPABILITY_TOKEN="$(openssl rand -hex 32)"
./scripts/run-core.sh &
PHAROSD_PID=$!
trap 'kill "$PHAROSD_PID" 2>/dev/null || true' EXIT
```

The token must be exactly 64 lowercase hexadecimal characters. Keep it in the
process environment only. `run-core.sh` refuses missing or malformed values
before creating directories or opening SQLite, and never generates, persists,
or prints the capability.

To capture directly through the CLI from the repository root:

```bash
(cd core && PHAROS_DB=../var/pharos.dev.sqlite dune exec pharos -- capture "Review the GitLab MR about the billing retry logic")
```

Every `/v0/*` request requires the same capability; `/health` is public:

```bash
curl -s http://127.0.0.1:8765/health | jq
curl -s -X POST http://127.0.0.1:8765/v0/capture \
  -H 'content-type: application/json' \
  -H "Authorization: Bearer $PHAROS_CAPABILITY_TOKEN" \
  -d '{"body":"Follow up on Feishu project blocker before standup","title":"Follow up blocker"}' | jq
curl -s http://127.0.0.1:8765/v0/today \
  -H "Authorization: Bearer $PHAROS_CAPABILITY_TOKEN" | jq
```

Launch the Swift app from that same shell so it inherits the capability:

```bash
swift run --package-path ui/macos/PharosApp
```

### Optional: run from Xcode

```bash
launchctl setenv PHAROS_CAPABILITY_TOKEN "$PHAROS_CAPABILITY_TOKEN"
open ui/macos/PharosApp/Package.swift
```

Launch Xcode after `launchctl setenv`, then run the `PharosApp` target. Remove
the inherited value when finished:

```bash
launchctl unsetenv PHAROS_CAPABILITY_TOKEN
```

Do not add the token to a shared scheme or checked-in file. The app expects the
core daemon at `http://127.0.0.1:8765` and fails before network transport when
its capability is missing or malformed.

## Development philosophy

Pharos should feel like a tower cockpit, not a runaway sprinkler system. The core owns domain state, policy, evidence, and writeback safety. UI and adapters are replaceable surfaces. External writeback must travel through the policy gate, carrying approval and payload hash like a little stamped passport.

## Important documents

- [User experience](docs/USER_EXPERIENCE.md)
- [PRD v0.3](docs/PRD_v0.3.md)
- [PRD v0.2](docs/PRD_v0.2.md)
- [Architecture baseline](docs/ARCHITECTURE.md)
- [Iteration plan](docs/ITERATION_PLAN.md)
- [v0.3 execution plan](docs/v0.3-plan/EXECUTION_ORDER.md)
- [Historical Codex implementation outline](docs/CODEX_PLAN.md)
- [Security and invariants](docs/SECURITY.md)
- [Dogfood plan](docs/DOGFOOD.md)
- [Adapter protocol](docs/ADAPTER_PROTOCOL.md)
- [Local API](docs/API.md)

## Docs source of truth

Product surface source of truth: `docs/USER_EXPERIENCE.md`
MVP scope source of truth: `docs/PRD_v0.3.md`
v0.3 execution and safety source of truth: `docs/v0.3-plan/`
Architecture baseline: `docs/ARCHITECTURE.md`
Historical baselines: `docs/PRD_v0.2.md`, `docs/CODEX_PLAN.md`

## Repository status

This is a starter scaffold. Expect to iterate immediately on:

1. Real adapter implementations.
2. Stronger typed JSON and OpenAPI generation.
3. Better SwiftUI request detail UI.
4. Keychain-backed token storage.
5. Metrics aggregation and export.
6. Packaged app bundle that starts and supervises `pharosd`.
