# Task 01: Create PRD v0.3 and align docs

Branch: `codex/v03-docs-alignment`

## Goal

Make docs agree that v0.3 user-facing Pharos is a decision cockpit using `Needs Decision / Needs Input / Watching / Handled / Noise`, while internal states remain available for audit and debugging.

## Read first

```text
docs/USER_EXPERIENCE.md
docs/API.md
docs/ARCHITECTURE.md
docs/ITERATION_PLAN.md
docs/CODEX_PLAN.md
specs/today_decision_card_contract.md
docs/PRD_v0.3.md from this plan package
```

## Files to change

```text
docs/PRD_v0.3.md
README.md
docs/API.md
docs/ARCHITECTURE.md
docs/ITERATION_PLAN.md
docs/CODEX_PLAN.md
protocol/openapi.yaml
```

## Exact changes

1. Add `docs/PRD_v0.3.md` using the content from this package.
2. In `README.md`, add a short `Docs source of truth` section:

```text
Product surface source of truth: docs/USER_EXPERIENCE.md
MVP scope source of truth: docs/PRD_v0.3.md
Architecture source of truth: docs/ARCHITECTURE.md
Codex task source of truth: docs/CODEX_PLAN.md
Historical baseline: docs/PRD_v0.2.md
```

3. In `docs/API.md`, replace the `/v0/today` response example with the v0.3 shape from `specs/today_decision_card_contract.md`.
4. In `docs/API.md`, explicitly state that old lifecycle buckets may exist only under `/v0/debug/today-internal`.
5. In `docs/ARCHITECTURE.md`, ensure API shape mentions:

```text
GET /v0/today -> TodaySnapshot with DecisionCard groups
GET /v0/debug/today-internal -> optional internal lifecycle buckets
```

6. In `docs/ITERATION_PLAN.md`, make `DecisionCard DTO and Today mapping` the next implementation slice before real source adapters.
7. In `docs/CODEX_PLAN.md`, add new Task 000 or Task 001 for v0.3 alignment before build hardening.
8. In `protocol/openapi.yaml`, update `/v0/today` schemas to the v0.3 fragment. Preserve other routes.

## Do not change

1. Do not remove `docs/PRD_v0.2.md`.
2. Do not remove internal statuses from docs.
3. Do not change OCaml or Swift code in this task unless docs build tooling requires it.

## Acceptance

1. Searching docs for `Needs Review` may still find historical PRD v0.2 or internal-state references, but not as the default Today section in v0.3 docs.
2. README clearly tells Codex which docs to follow.
3. `docs/API.md` and `protocol/openapi.yaml` agree on `/v0/today`.
4. No product doc says Swift should implement Today grouping by itself.

## Final response format

```text
Changed files:
- ...
Tests/docs checks:
- grep/manual review ...
Acceptance status:
- ...
```
