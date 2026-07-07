# Technical PRD for Starter v0.1

## Purpose

Create the first Pharos project skeleton so future Codex iterations can implement the MVP from a stable structure.

## Primary user

DBvc.

## Starter success criteria

1. The repo can be cloned and understood from README plus docs.
2. OCaml is clearly the core owner.
3. SwiftUI is clearly the macOS UI owner.
4. Manual capture demonstrates the full product loop in miniature.
5. Policy Gate exists before external writeback exists.
6. Adapter and skill extension seams are present.
7. Codex can continue from documented task slices.

## Functional scope in starter

### Included

- Manual capture.
- SQLite persistence.
- Today snapshot.
- Request detail.
- Proposed local action.
- Evidence and timeline.
- Approve.
- Edit and approve.
- Reject.
- Execute approved local action.
- SwiftUI shell.
- Source, Rules, and Metrics placeholder surfaces.

### Not included yet

- Real Feishu APIs.
- Real GitLab APIs.
- Model calls.
- Full source settings persistence.
- Full rules system.
- Metrics charts and export.
- App bundle packaging with embedded daemon.
- Keychain credential flow.

## Safety requirements in starter

1. Generated actions have risk levels.
2. Review decisions are persisted.
3. Approval is bound to action hash.
4. Local execution checks approval hash.
5. External writeback is not implemented in M0.
6. L4 and L5 actions are not executable.

## User-facing M0 demo

1. Start `pharosd`.
2. Open SwiftUI app.
3. Capture a manual request.
4. See it in Needs Review.
5. Open detail.
6. Inspect summary, reason, evidence, timeline, and proposed action.
7. Edit and approve.
8. See request become Done.

## Engineering demo

```bash
./scripts/run-core.sh
curl -s -X POST http://127.0.0.1:8765/v0/capture \
  -H 'content-type: application/json' \
  -d @examples/manual_capture.json | jq
curl -s http://127.0.0.1:8765/v0/today | jq
```

## Next product decisions

1. Whether the Swift app should supervise `pharosd` in M1 or M2.
2. Whether Feishu adapters should be OCaml or external workers.
3. Whether GitLab read adapter starts with polling or webhook relay.
4. Which model API or local agent bridge should power draft generation.
5. Whether DB encryption is needed before real source context is stored.
