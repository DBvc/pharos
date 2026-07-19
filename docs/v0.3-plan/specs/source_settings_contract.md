# Source Settings Contract

Apply the persistence shell in Task 07 and the ownership/policy hardening in
Task 10a2.

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

## Task 10a2 ownership and scope rules

`Source_settings` is the single Core owner for source scope validation,
canonicalization, production config mutation, and effective policy composition.
`Store` remains a low-level persistence API and may be called directly only by
near-source persistence tests.

GitLab `scope_json` accepts exactly:

```json
{}
{"projects":[42,77]}
```

Project IDs must be positive JSON integers. Writes sort and deduplicate IDs;
`{"projects":[]}` canonicalizes to `{}`. Unknown fields, strings, zero, negative
numbers, duplicate keys, invalid JSON, and non-object values are rejected. Other
source kinds currently accept only `{}`.

The `projects` list is an additional watched-project scan set, not a read or
write target allowlist. `{}` preserves the global GitLab `reviews_for_me` query
and adds no project queries. Operational gates are:

```text
effective_read = enabled && read_enabled
effective_write = enabled && write_enabled
```

Credentials, GitLab base URL, and username remain environment-owned. Project
scope has no environment fallback; `PHAROS_GITLAB_PROJECTS` is an explicit
configuration error whenever it is present.

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

All fields are optional. Null or omission means leave unchanged. When
`scope_json` is supplied, Core validates and canonicalizes it before the low-level
Store write. Invalid scope returns HTTP 400 `invalid_source_scope` and leaves the
row unchanged. Omitting scope does not rewrite an invalid legacy value. GET keeps
that raw value visible so the caller can repair it, while external read/write
policy fails closed.

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
4. Scope parsing rejects every non-contract shape and canonicalizes project IDs.
5. Invalid PATCH leaves SQLite unchanged; invalid persisted scope remains visible
   and can be repaired.
6. Disabled/read-disabled/invalid policy paths reach no external client.

## Acceptance

```bash
cd core && dune build && dune runtest
curl -s http://127.0.0.1:8765/v0/sources | jq '.sources | length'
```

Expected: `4`.
