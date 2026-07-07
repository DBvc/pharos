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
  "needs_review": [],
  "running": [],
  "needs_context": [],
  "new_items": [],
  "done_today": [],
  "archived_noise_count": 0
}
```

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
