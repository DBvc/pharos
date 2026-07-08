# Source Settings Contract

Apply in task 07.

## Goal

Create a persistent source-management shell before real source adapters. This keeps source status, scopes, and write permissions explicit.

## Files to edit

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/migrations.ml
core/bin/daemon/main.ml
ui/macos/PharosApp/Sources/PharosApp/Core/Models.swift
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Views/SourcesView.swift
docs/API.md
protocol/openapi.yaml
```

## Database table

```sql
CREATE TABLE IF NOT EXISTS sources (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL,
  read_enabled INTEGER NOT NULL,
  write_enabled INTEGER NOT NULL,
  scope_json TEXT NOT NULL,
  last_sync_at TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

On migration, upsert four default rows:

```text
feishu_chat
feishu_project
gitlab
feishu_docs
```

Default values:

```text
enabled = false
read_enabled = false
write_enabled = false
scope_json = {}
last_sync_at = null
last_error = null
```

## API

```text
GET /v0/sources
PATCH /v0/sources/:id
```

`GET /v0/sources` response:

```json
{
  "sources": [
    {
      "id": "src_gitlab",
      "kind": "gitlab",
      "enabled": false,
      "read_enabled": false,
      "write_enabled": false,
      "scope_json": "{}",
      "last_sync_at": null,
      "last_error": null,
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

`PATCH /v0/sources/:id` request:

```json
{
  "enabled": true,
  "read_enabled": true,
  "write_enabled": false,
  "scope_json": "{\"projects\":[42]}"
}
```

All fields optional. Null means leave unchanged except `last_error` may be set null by a future route.

## Swift UI

`SourcesView` must show one row per source with:

```text
kind label
enabled toggle
read enabled toggle
write enabled toggle, default off
last sync
last error
scope_json as text editor or plain field
```

Write permission copy:

```text
External writes still require review even when write permission is enabled.
```

## Tests

OCaml tests:

1. Default rows are created on empty DB.
2. Write permission defaults to false.
3. Updating `enabled` persists across reopen.

## Acceptance

```bash
cd core && dune build && dune runtest
curl -s http://127.0.0.1:8765/v0/sources | jq '.sources | length'
```

Expected: `4`.
