# Today Decision Card Contract

This is the exact v0.3 contract for `/v0/today`.

## Endpoint

```text
GET /v0/today
```

## Response JSON

```json
{
  "needs_decision": [
    {
      "request_id": "req_...",
      "title": "Review retry logic MR",
      "summary": "A GitLab MR is waiting for review.",
      "group": "needs_decision",
      "source_kind": "gitlab",
      "source_url": "https://gitlab.example.com/group/project/-/merge_requests/123",
      "priority": "normal",
      "risk": "l2",
      "why_now": "You were requested as reviewer.",
      "prepared_next_move": "Review the prepared comment draft.",
      "target_preview": "pharos.local.complete_request / req_...",
      "evidence_count": 3,
      "updated_at": "2026-07-08T00:00:00Z",
      "debug_status": "ready_for_review"
    }
  ],
  "needs_input": [],
  "watching": [],
  "handled": [],
  "noise": {
    "count": 0
  }
}
```

## Required schemas

### AttentionGroup

Allowed values:

```text
needs_decision
needs_input
watching
handled
noise
```

### DecisionCard

| Field | Type | Required | Source |
|---|---|---:|---|
| `request_id` | string | yes | `WorkRequest.id` |
| `title` | string | yes | `WorkRequest.title` |
| `summary` | string | yes | `WorkRequest.summary` |
| `group` | AttentionGroup | yes | mapping function |
| `source_kind` | string | yes | `WorkRequest.source_kind` |
| `source_url` | string or null | yes | source signal url if available |
| `priority` | string | yes | `WorkRequest.priority` |
| `risk` | string | yes | `WorkRequest.risk` |
| `why_now` | string | yes | `WorkRequest.reason` |
| `prepared_next_move` | string or null | yes | latest reviewable action title, else `WorkRequest.next_step`, else null |
| `target_preview` | string or null | yes | latest action target kind/ref, else null |
| `evidence_count` | integer | yes | count of evidence items for request |
| `updated_at` | string | yes | `WorkRequest.updated_at` |
| `debug_status` | string | yes | `WorkRequest.status` string |

### NoiseSummary

```json
{ "count": 0 }
```

No noise items are required in v0.3. A future `/v0/noise` or `?include_noise=true` can list them.

## Internal lifecycle mapping

Mapping must be implemented in OCaml core, not Swift.

| Internal status | Required user group |
|---|---|
| `ReadyForReview` with at least one `ActionProposed` action | `NeedsDecision` |
| `ReadyForReview` without a proposed action | `NeedsInput` |
| `NeedsContext` | `NeedsInput` |
| `Failed` | `NeedsInput` |
| `New` | `Watching` |
| `Triaging` | `Watching` |
| `Running` | `Watching` |
| `Waiting` | `Watching` |
| `Approved` | `Watching` |
| `Executing` | `Watching` |
| `Snoozed` | `Watching` |
| `Done` | `Handled` |
| `Archived` | `Noise` |

## Sorting

Within each list:

1. `Urgent` before `High` before `Normal` before `Low`.
2. Then newest `updated_at` first.

Noise is only a count in v0.3.

## Backward compatibility

The old shape must not be returned by `/v0/today` after task 02.

Allowed optional compatibility route:

```text
GET /v0/debug/today-internal
```

This route may return the old buckets and must not be used by Swift `TodayView`.
