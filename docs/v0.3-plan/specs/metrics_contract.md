# Metrics and Dogfood Contract

Apply in task 11.

## Goal

Make Pharos ready for 10 workday dogfood by recording local metrics that answer whether it reduces scanning, context hunting, missed work, and unsafe automation risk.

## Files to edit

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/migrations.ml
core/lib/metrics.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Views/MetricsView.swift
docs/DOGFOOD.md
docs/API.md
protocol/openapi.yaml
```

## Database expansion

Expand `metrics_daily` with columns:

```text
source_signals
work_requests
today_needs_decision
today_needs_input
today_watching
today_handled
noise_count
ready_for_review
auto_advanced
approvals
edit_approvals
rejects
false_positives
archives
external_writes
unapproved_external_write_attempts
signal_to_request_ms_total
signal_to_request_count
request_to_ready_ms_total
request_to_ready_count
```

Keep existing columns and add missing columns via `ALTER TABLE` if table already exists.

## API

```text
GET /v0/metrics?days=7
POST /v0/metrics/export
```

`GET /v0/metrics?days=7` response:

```json
{
  "days": [
    {
      "day": "2026-07-08",
      "source_signals": 3,
      "work_requests": 2,
      "today_needs_decision": 1,
      "today_needs_input": 0,
      "today_watching": 1,
      "today_handled": 1,
      "noise_count": 0,
      "ready_for_review": 1,
      "auto_advanced": 1,
      "approvals": 1,
      "edit_approvals": 0,
      "rejects": 0,
      "false_positives": 0,
      "archives": 0,
      "external_writes": 0,
      "unapproved_external_write_attempts": 0,
      "avg_signal_to_request_ms": null,
      "avg_request_to_ready_ms": null
    }
  ]
}
```

Export request:

```json
{ "format": "markdown", "days": 7 }
```

Response:

```json
{ "path": "var/exports/pharos-metrics-2026-07-08.md" }
```

Allowed formats:

```text
json
markdown
```

## Today group count semantics

`today_needs_decision`, `today_needs_input`, `today_watching`,
`today_handled`, and `noise_count` are daily snapshot/gauge values, not event
counters.

If `/v0/today` records these values, it must upsert/overwrite the current
day's latest snapshot. Repeated refreshes of `/v0/today` must not increment the
values. Event counters remain event counters only for real events such as
approvals, edit approvals, rejects, false positives, archives, external writes,
and blocked external write attempts.

## Swift MetricsView

Show:

1. Last 7 days table.
2. Needs Decision clarity proxy: `needs_decision / work_requests` and reject/false positive rates.
3. Safety line: `unapproved_external_write_attempts` must be zero.
4. Export JSON / Markdown buttons.

## Dogfood template update

`docs/DOGFOOD.md` must include daily subjective questions:

```text
Did Pharos reduce system-scanning or context-hunting? 0-5
Did Pharos help avoid missed work? 0-5
Did Pharos create extra burden? 0-5
Did Needs Decision contain clear decisions rather than status noise? 0-5
Most valuable request today:
Most annoying or useless request today:
One thing to improve tomorrow:
```

## Tests

1. Metrics row is created on capture.
2. Approval increments approvals.
3. Edit approval increments edit approvals.
4. Reject increments rejects.
5. Blocked external attempt increments unapproved external attempts.
6. Export writes a file under `var/exports/` and does not include secrets.
7. Generating `/v0/today` multiple times does not accumulate Today group counts; it leaves the daily snapshot at the latest observed values.

## Acceptance

```bash
cd core && dune build && dune runtest
curl -s 'http://127.0.0.1:8765/v0/metrics?days=7' | jq '.days | length'
```

Expected: length is <= 7 and >= 1 when there is local activity.
