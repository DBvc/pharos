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

## Language choice

The core is OCaml. Adapters may be OCaml or external workers. Use the language that gives the safest and fastest SDK path, but keep the protocol stable.
