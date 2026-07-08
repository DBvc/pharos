# Local API Draft

The first transport is localhost HTTP for developer speed. Later versions should move to Unix domain socket and a local capability token.

Base URL:

```text
http://127.0.0.1:8765
```

## GET /health

Response:

```json
{"ok":true,"service":"pharosd"}
```

## POST /v0/capture

Request:

```json
{
  "title": "Optional title",
  "body": "The captured text or link",
  "url": "https://example.com/optional",
  "actor": "manual"
}
```

Response:

```json
{
  "request": {"id":"..."},
  "detail_url": "/v0/requests/..."
}
```

## GET /v0/today

Response shape:

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

`/v0/today` is the user-facing `TodaySnapshot` contract. It returns `DecisionCard` groups: `needs_decision`, `needs_input`, `watching`, `handled`, and `noise`.

The old lifecycle buckets `needs_review`, `running`, `needs_context`, `new_items`, `done_today`, and `archived_noise_count` may exist only under optional debug route `GET /v0/debug/today-internal`. Swift Today clients must consume `/v0/today` as the default product surface.

## GET /v0/requests/:id

Response shape:

```json
{
  "request": {},
  "actions": [],
  "evidence": [],
  "timeline": []
}
```

## POST /v0/actions/:id/approve

Approves the current action body.

## POST /v0/actions/:id/edit-and-approve

Request:

```json
{"body":"Edited body to execute"}
```

Approves the edited body. The core updates the action hash and creates an approval bound to that hash.

## POST /v0/actions/:id/reject

Rejects the action and records a timeline event.

## POST /v0/actions/:id/execute-local

Executes a local Pharos action after policy verification. External writeback routes will be added in Milestone 3.
