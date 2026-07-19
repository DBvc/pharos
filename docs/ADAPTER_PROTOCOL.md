# Adapter Protocol

Adapters are edge components. Their job is to translate external systems into Pharos concepts without owning Pharos policy.

## Adapter capabilities

An adapter declares:

```json
{
  "source_kind": "gitlab",
  "read_events": ["merge_request_review_requested", "mention", "pipeline_failed"],
  "context_types": ["mr_metadata", "mr_diff_summary", "discussion", "pipeline_status"],
  "write_targets": ["gitlab.mr_comment", "gitlab.issue_comment"],
  "write_enabled_by_default": false
}
```

## SourceSignal input shape

```json
{
  "source_kind": "gitlab",
  "external_id": "project/123!456#review-request",
  "actor": "alice",
  "title": "Review requested: billing retry logic",
  "body": "Alice requested your review on !456.",
  "url": "https://gitlab.example/group/project/-/merge_requests/456",
  "occurred_at": "2026-07-07T09:30:00Z",
  "raw": {
    "object_kind": "merge_request",
    "project_id": 123,
    "iid": 456
  }
}
```

## Context fetch contract

The core asks for bounded context:

```json
{
  "source_kind": "gitlab",
  "context_type": "mr_review_context",
  "external_ref": "project/123!456",
  "limits": {
    "max_comments": 50,
    "max_diff_files": 30,
    "max_bytes": 200000
  }
}
```

The adapter returns facts, not final decisions:

```json
{
  "facts": [
    {"kind":"pipeline_status", "title":"Pipeline failed", "body":"test_retry_policy failed"},
    {"kind":"discussion", "title":"Open discussion", "body":"Bob asked about timeout behavior"}
  ],
  "links": [
    {"label":"MR", "url":"https://gitlab.example/group/project/-/merge_requests/456"}
  ],
  "truncated": false
}
```

## Writeback contract

Adapters do not accept raw arbitrary text from UI. They accept a writeback request only from the core execution path after policy verification.

```json
{
  "action_id": "act_...",
  "approval_id": "appr_...",
  "target_kind": "gitlab.mr_comment",
  "target_ref": "project/123!456",
  "body": "Approved body from core"
}
```

The adapter returns:

```json
{
  "ok": true,
  "external_id": "note/999",
  "url": "https://gitlab.example/group/project/-/merge_requests/456#note_999",
  "message": "Comment posted"
}
```

## Failure isolation

Adapter errors should become source status and timeline events, not daemon crashes.

## GitLab read-only adapter

The first real adapter polls GitLab API v4 with `pharos sync-gitlab`. It
performs only these GET operations:

```text
GET /api/v4/merge_requests?scope=reviews_for_me&state=opened
GET /api/v4/projects/:id/merge_requests?state=opened
GET /api/v4/projects/:id/merge_requests/:iid
GET /api/v4/projects/:id/merge_requests/:iid/discussions
GET /api/v4/projects/:id/merge_requests/:iid/pipelines
```

Each MR becomes a GitLab `SourceSignal` with stable identity
`gitlab:project/<project_id>:mr/<iid>`, then enters the same Runner path as fake
replay. The adapter attaches bounded `gitlab.mr.metadata`,
`gitlab.mr.pipeline` when known, and `gitlab.mr.discussions` evidence. Every
evidence body is limited to 4000 bytes.

Base URL, credentials, and username come from environment; watched project IDs
come only from the persisted, validated `src_gitlab.scope_json`. `{}` keeps the
global `reviews_for_me` query, and configured projects only add scans. They are
not a write allowlist. `PHAROS_GITLAB_PROJECTS` is rejected when present. The
OCaml client removes the token variable from curl's child environment and passes
the private-token header over stdin, so the token does not appear in child
process arguments, logs, source signals, evidence, or SQLite. The adapter follows
no redirects and exposes no write operation. No daemon sync route is exposed.

## Language choice

The core is OCaml. Adapters may be OCaml or external workers. Use the language that gives the safest and fastest SDK path, but keep the protocol stable.
