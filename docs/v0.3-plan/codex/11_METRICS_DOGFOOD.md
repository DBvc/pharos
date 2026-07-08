# Task 11: Metrics and dogfood readiness

Branch: `codex/metrics-dogfood`

## Goal

Add metrics API, export, Swift Metrics view, and dogfood tracking so the MVP can be evaluated over 10 workdays.

## Read first

```text
specs/metrics_contract.md
```

## Files to change

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/migrations.ml
core/lib/metrics.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
core/test/metrics_test.ml
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Views/MetricsView.swift
docs/DOGFOOD.md
docs/API.md
protocol/openapi.yaml
```

## Exact implementation steps

1. Expand metrics schema with v0.3 fields.
2. Add safe migration for existing DBs.
3. Record Today group counts as daily snapshot/gauge values when `/v0/today` is generated or via explicit metrics refresh.
4. Record approval/edit/reject/archive/false-positive/writeback counters.
5. Add `GET /v0/metrics?days=7`.
6. Add `POST /v0/metrics/export` with JSON and Markdown.
7. Ensure export writes under `var/exports/`.
8. Ensure export does not include tokens, headers, or full raw payloads.
9. Add Swift Metrics models, API functions, and view.
10. Update `docs/DOGFOOD.md` with daily subjective questions and continue/pause criteria.
11. Add tests.

## Do not change

1. Do not add cloud analytics.
2. Do not include secrets or raw authorization headers in export.
3. Do not count blocked attempts as successful external writes.
4. Do not increment Today group counts on every `/v0/today` refresh; upsert the latest daily snapshot instead.

## Commands

```bash
cd core && dune build && dune runtest
swift build --package-path ui/macos/PharosApp
```

Manual smoke:

```bash
curl -s 'http://127.0.0.1:8765/v0/metrics?days=7' | jq
curl -s -X POST 'http://127.0.0.1:8765/v0/metrics/export' \
  -H 'content-type: application/json' \
  -d '{"format":"markdown","days":7}' | jq
```

## Acceptance

1. 7-day metrics response works.
2. Markdown and JSON export files are created.
3. Unapproved external attempts are visible and distinct from external writes.
4. Swift Metrics view compiles.
5. `docs/DOGFOOD.md` gives a usable 10-day procedure.
6. Repeated `/v0/today` generation does not inflate `today_needs_decision`, `today_needs_input`, `today_watching`, `today_handled`, or `noise_count`.

## Final response format

```text
Changed files:
Tests run:
Metric/export smoke result:
Known follow-up:
```
