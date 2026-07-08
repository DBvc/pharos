# Task 02: DecisionCard API and OCaml core mapping

Branch: `codex/decision-card-api`

## Goal

Change `/v0/today` from internal lifecycle buckets to user-facing attention groups, implemented in OCaml core.

## Read first

```text
specs/today_decision_card_contract.md
specs/ocaml_implementation_contract.md
```

## Files to change

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/runner.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
core/test/*
docs/API.md
protocol/openapi.yaml
```

## Exact implementation steps

1. Add `attention_group`, `decision_card`, `noise_summary`, and `today_decision_snapshot` to `core/lib/domain.ml`.
2. Add JSON encoders exactly matching `specs/today_decision_card_contract.md`.
3. Add Store helpers:
   - `get_source_signal`
   - `count_evidence_by_request`
   - `latest_action_by_request`
   - `has_reviewable_action`
   - `today_decision`
   - optional `today_internal`
4. Implement grouping in OCaml core using the required mapping table.
5. Change `Runner.today` to return `today_decision_snapshot`.
6. Change daemon `/v0/today` to encode `today_decision_snapshot`.
7. Optional: add `/v0/debug/today-internal` for old buckets.
8. Change CLI `pharos today` to print new shape.
9. Optional: add CLI `pharos today-internal` for old shape.
10. Update tests.

## Required tests

Add or update tests so these pass:

1. Manual capture appears in `.needs_decision`.
2. Approve + execute-local moves request to `.handled`.
3. Reject or archive increments `.noise.count`.
4. `debug_status` equals internal status string.

## Do not change

1. Do not remove internal `request_status`.
2. Do not make Swift do the mapping.
3. Do not return old and new buckets together from `/v0/today`.

## Commands

```bash
cd core && dune build
cd core && dune runtest
```

Manual smoke:

```bash
rm -f ../var/v03.sqlite
PHAROS_DB=../var/v03.sqlite dune exec pharos -- capture "Review the billing retry MR"
PHAROS_DB=../var/v03.sqlite dune exec pharos -- today | jq '.needs_decision | length'
```

Expected: `1`.

## Final response format

```text
Changed files:
Tests run:
Manual smoke result:
Acceptance status:
Known follow-up:
```
