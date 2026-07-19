# Local API

The v0.3 transport is loopback HTTP. `pharosd` refuses any `--host` other than
`127.0.0.1` or `::1`.

The bundled Swift app uses `127.0.0.1`; the `::1` bind is available for custom
CLI or curl use and is not a second Swift endpoint.

Base URL:

```text
http://127.0.0.1:8765
```

## Capability authentication

Set the same `PHAROS_CAPABILITY_TOKEN` in the daemon and Swift app environment.
It must be exactly 64 lowercase hexadecimal characters. Every `/v0/*` route
requires:

```text
Authorization: Bearer <runtime capability>
```

Missing or malformed daemon configuration stops startup before SQLite is
opened. A missing header or invalid caller capability returns HTTP 401 with
`{"error":"unauthorized"}` before the route handler runs. `/health` is the only
public route. Capability and GitLab credentials are environment-managed runtime
values and must not be persisted, exported, included in examples, or logged.

The revision-bound review request body is an intentional breaking change inside
the unreleased v0.3 starter. `pharosd`, the bundled Swift client, and the CLI
must be upgraded together. Empty approve/reject POSTs and the old one-argument
CLI approve command are not supported because they cannot prove which action
revision the user reviewed.

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

## POST /v0/source-signals

Ingests a source-adapter signal or replay fixture. Replaying the same stable
external object updates one active request instead of creating duplicate Today
cards.

Request:

```json
{
  "kind": "gitlab",
  "external_id": "gitlab:project/123:mr/456",
  "actor": "alice",
  "title": "Review requested: billing retry logic",
  "body": "Alice requested your review on MR !456.",
  "url": "https://gitlab.example/group/project/-/merge_requests/456",
  "occurred_at": "2026-07-07T09:30:00Z",
  "raw_json": {}
}
```

Response:

```json
{
  "request": {"id":"..."},
  "merged": true,
  "detail_url": "/v0/requests/..."
}
```

Identity uses `external_id` first, then canonical URL, and only falls back to a
normalized subject when no stable external object id or URL exists.

## GET /v0/sources

Returns persisted source settings. Empty databases initialize the four P0
sources with read and write permissions disabled.

Response:

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

## PATCH /v0/sources/:id

Updates explicit source settings fields. Omitted fields stay unchanged.

Request:

```json
{
  "enabled": true,
  "read_enabled": true,
  "write_enabled": false,
  "scope_json": "{\"projects\":[42]}"
}
```

Response:

```json
{
  "source": {"id":"src_gitlab"}
}
```

`write_enabled` only records source permission. External writes still require
the Review Gate and policy checks. GitLab `scope_json` accepts only `{}` or
`{"projects":[<positive integer>,...]}`. Project IDs are sorted and deduplicated
on write, and an empty project list canonicalizes to `{}`. Other source kinds
currently accept only `{}`.

An omitted `scope_json` remains byte-for-byte unchanged. Invalid scope returns
HTTP 400 with `{"error":"invalid_source_scope"}` and does not update the row.
`GET /v0/sources` still returns an invalid legacy value so the caller can repair
it; external reads and writes fail closed until it is repaired.

## GitLab read-only sync CLI

`pharos sync-gitlab` runs one development-only, read-only GitLab MR sync using
environment configuration. It reads merge requests awaiting review plus open
merge requests from configured projects, then refreshes bounded metadata,
pipeline, and discussion evidence.

Required environment variables:

```text
PHAROS_GITLAB_BASE_URL=https://gitlab.example.com
PHAROS_GITLAB_TOKEN=...
```

Optional environment variable:

```text
PHAROS_GITLAB_USERNAME=dbvc
```

GitLab must be enabled for reading in the persisted `src_gitlab` row. `{}` keeps
the global `reviews_for_me` query and adds no project queries. To scan extra
projects, PATCH `scope_json` with `{"projects":[42,77]}`. This watched-project
set is not a write authorization allowlist. `PHAROS_GITLAB_PROJECTS` is rejected
when present; project scope has no environment fallback.

Successful output:

```json
{"processed":2}
```

Disabled or read-disabled sources exit non-zero before transport without changing
`last_sync_at` or `last_error`. Invalid persisted scope, legacy project env,
missing credentials, or an upstream GitLab/parser failure exits non-zero and
updates a bounded `src_gitlab.last_error`. A successful run updates
`last_sync_at` and clears the prior error. The token is never persisted and the
command never calls a GitLab write endpoint.

```bash
pharos sync-gitlab
```

The daemon does not expose a GitLab sync route in v0.3.

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
  "writeback_attempts": [],
  "evidence": [],
  "timeline": []
}
```

## POST /v0/actions/:id/approve

Request:

```json
{"expected_payload_hash":"payload-hash-shown-to-the-user"}
```

Approves only the current proposed action revision.

## POST /v0/actions/:id/edit-and-approve

Request:

```json
{
  "body":"Edited body to execute",
  "expected_payload_hash":"payload-hash-shown-to-the-user"
}
```

Approves the edited body only if the displayed revision is still current. The
core updates the action hash and creates an approval bound to the new hash.

## POST /v0/actions/:id/reject

Request:

```json
{"expected_payload_hash":"payload-hash-shown-to-the-user"}
```

Rejects only the current proposed action revision and records a timeline event.

For approve, edit-and-approve, and reject, the hash comparison, action/request
status changes, approval decision, timeline, and metric are one SQLite
transaction. A changed hash or no-longer-proposed action returns HTTP 409 with
`{"error":"stale_action"}` and records no decision side effect. Clients must
refresh the request detail and ask the user to review again.

`expected_payload_hash` is an opaque revision value returned by the API. Clients
must echo the displayed value and must not infer or recompute its algorithm.

New v0.3 actions expose `payload_hash` as `sha256:` followed by exactly 64
lowercase hexadecimal characters. Core derives it from the fixed ASCII version
tag `pharos.action-payload.v2` plus a NUL byte, followed in order by
`target_kind`, `target_ref`, canonical risk (`l0` through `l5`), and `body`.
Each field is encoded as an unsigned 8-byte big-endian byte length followed by
its raw bytes. Approval and execution fail closed for legacy 32-character MD5
action hashes; rejection may still be used to dispose of a legacy proposal.

There is no schema or data migration for pre-v2 development databases in this
unreleased version. Stop the daemon and rebuild disposable dev state with
`rm -f var/pharos.dev.sqlite`. Do not reset a database whose data must be
preserved; that requires a separately planned migration.

## POST /v0/actions/:id/execute-local

Executes a local Pharos action after policy verification. GitLab comment actions
must use `execute-approved`; the local executor continues to reject external
targets.

## POST /v0/actions/:id/execute-approved

Starts the approved GitLab MR or issue comment represented by the current
action. The body is `{}`. Before transport, core re-reads the action, latest
approval, request provenance, and persisted source settings and validates the
complete v2 payload hash, L3 risk, target allowlist, nonblank body of at most
8000 characters, valid GitLab scope, and `enabled && write_enabled`.

Response:

```json
{
  "action": {"id":"act_...","status":"executed"},
  "attempt": {
    "id":"wba_...",
    "action_id":"act_...",
    "approval_id":"appr_...",
    "payload_hash":"sha256:...",
    "target_kind":"gitlab.mr.comment",
    "target_ref":"project_id=123;mr_iid=456",
    "marker":"<!-- pharos-writeback:wba_...:sha256:... -->",
    "status":"confirmed",
    "external_id":"note_123",
    "external_url":"https://gitlab.example/group/project/-/merge_requests/456#note_123",
    "error":null,
    "created_at":"...",
    "updated_at":"...",
    "started_at":"...",
    "finished_at":"..."
  }
}
```

`writeback_attempts` is the delivery source of truth. Only failures known
before the HTTP child starts become `failed_before_send` and may be retried by
calling this route again. Any ambiguous post-start result becomes `unknown`;
calling `execute-approved` again must not issue a second POST.

The daemon and delivery CLI commands share one advisory delivery-owner lock
derived from the SQLite path. Ownership is established before opening SQLite
or recovering interrupted attempts and is held for the process operation;
lock contention fails before writeback state is changed.

The real client uses `PHAROS_GITLAB_BASE_URL` and `PHAROS_GITLAB_TOKEN`, accepts
only HTTPS, and never persists either credential. GitLab
`scope_json.projects` remains a read-time watched-project set and is not a
write target allowlist; write target authority comes from stable request
provenance.

## POST /v0/writeback-attempts/:id/reconcile

Reconciles an `unknown` attempt by listing a bounded number of GitLab Notes
pages and matching the complete stable marker exactly. A match changes the
attempt to `confirmed` without another POST. No match is not proof of
non-delivery and leaves the attempt `unknown`.

Before contacting GitLab, reconciliation atomically claims the attempt by
moving `unknown` to `in_flight`. Concurrent reconcile and abandon calls then
fail closed. Marker-not-found and reconciliation errors restore `unknown`, as
does startup recovery if the owner stops while holding the claim.

The response has the same `action` and `attempt` shape as
`execute-approved`.

## POST /v0/writeback-attempts/:id/abandon

Explicitly abandons an `unknown` attempt without contacting GitLab. The attempt
becomes `abandoned`, the action returns to `proposed`, and the request returns
to `ready_for_review`. A fresh approval is required before any new attempt.
There is no automatic retry.

## Review CLI

Direct local CLI review commands also require the hash displayed to the caller:

```bash
pharos approve <action-id> <expected-payload-hash>
pharos reject <action-id> <expected-payload-hash>
pharos execute-approved <action-id>
pharos reconcile-writeback <attempt-id>
pharos abandon-writeback <attempt-id>
```
