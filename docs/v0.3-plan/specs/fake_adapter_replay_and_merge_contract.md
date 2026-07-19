# Fake Adapter Replay and Merge Identity Contract

Apply in task 06.

## Goal

Before real GitLab or Feishu signals enter Pharos, the core must prove that repeated events update the same active request instead of turning Today into confetti.

## Files to edit

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/migrations.ml
core/lib/runner.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
examples/gitlab_mr_signal.json
examples/feishu_chat_signal.json
examples/feishu_project_signal.json
examples/feishu_docs_signal.json
docs/API.md
protocol/openapi.yaml
```

## New API

```text
POST /v0/source-signals
```

Request body:

```json
{
  "kind": "gitlab",
  "external_id": "gitlab:instance/839098c2ddad1e0534ea90cda97af9a522cf080e83d9579eb0125b395baa06fe:project/42:mr/123",
  "actor": "alice",
  "title": "Review retry logic",
  "body": "MR !123 requested your review.",
  "url": "https://gitlab.example.com/group/project/-/merge_requests/123",
  "occurred_at": "2026-07-08T00:00:00Z",
  "raw_json": "{}"
}
```

Response body:

```json
{
  "request": { "id": "req_..." },
  "merged": false,
  "detail_url": "/v0/requests/req_..."
}
```

Second replay of same identity returns same request id and `merged: true`.

## CLI

Add:

```text
pharos replay <path-to-json>
```

Behavior:

1. Read JSON file.
2. Parse as source signal input.
3. Insert/update through the same runner path used by `/v0/source-signals`.
4. Print response JSON.

## Database migration

Add table:

```sql
CREATE TABLE IF NOT EXISTS work_request_identities (
  identity_key TEXT PRIMARY KEY,
  request_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  external_key TEXT NOT NULL,
  normalized_subject TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_work_request_identities_request_id
  ON work_request_identities(request_id);
```

## Identity function

Use stable external identity whenever the source provides one. The subject is
stored for review/debugging and fallback matching, but it must not be part of
the primary identity key when a stable external object id exists.

Implement in core:

```ocaml
external_key =
  if source_signal.external_id is Some x then x
  else if source_signal.url is Some u then canonicalize_url u
  else source_signal.id

normalized_subject =
  source_signal.title
  |> lowercase ASCII
  |> trim
  |> replace all runs of whitespace with one space
  |> remove leading/trailing punctuation chars .,!?:;#[](){}
  |> truncate to 120 chars

identity_key =
  if source_signal.external_id is Some _ then source_kind_to_string kind ^ ":" ^ external_key
  else if source_signal.url is Some _ then source_kind_to_string kind ^ ":" ^ external_key
  else source_kind_to_string kind ^ ":" ^ external_key ^ ":" ^ normalized_subject
```

`canonicalize_url` for this task should be conservative:

1. trim leading/trailing whitespace;
2. remove a trailing slash;
3. remove obvious tracking query parameters when parsing is easy;
4. otherwise keep the URL unchanged rather than guessing.

Known adapters should prefer canonical `external_id` values over URL fallback.
For GitLab MR fixtures, use:

```text
gitlab:instance/<instance_sha256>:project/<project_id>:mr/<iid>
```

## Active request rule

If identity exists and linked request status is not `Done` and not `Archived`, update that request.

If identity does not exist, or linked request is `Done` or `Archived`, create a new request and bind identity to the new request.

## Merge update behavior

On merge update:

1. Insert new `SourceSignal` row.
2. Update `work_requests.updated_at`.
3. Update summary with a short line: `Updated from <source_kind> signal: <title>`.
4. Preserve existing request status unless it is `Done` or `Archived`.
5. Insert an evidence item of kind `source.update`.
6. Insert a timeline event:

```text
kind: merge
title: Source signal merged into existing request
body: signal_id=<signal_id>; identity_key=<identity_key>
```

Task 06 defines merge identity before source-specific proposed actions exist. Once Task 09
adds built-in skills, the same merge path must also apply the Task 09 proposal freshness
contract after all bounded evidence is persisted:

1. keep one current proposal for the active request;
2. recompute from the latest material source context;
3. preserve an existing approval when the generated executable payload is unchanged;
4. refresh the current action and require approval again when body, target, risk, or payload
   hash changes;
5. keep the old approval as audit history, but never let it authorize the refreshed hash.

This extension must preserve the same-request and one-active-card guarantees above.

## Fixture requirements

Add or normalize fixtures:

```text
examples/gitlab_mr_signal.json
examples/feishu_chat_signal.json
examples/feishu_project_signal.json
examples/feishu_docs_signal.json
```

Each fixture must include `kind`, `external_id`, `actor`, `title`, `body`, `url`, and `occurred_at`.

## Tests

Add OCaml test:

```text
core/test/merge_identity_test.ml
```

Assertions:

1. Replaying same GitLab fixture twice returns same request id.
2. Today has one active card, not two.
3. Timeline has one `capture` and one `merge` event.
4. Replaying same identity after request is `Done` creates a new request.
5. Replaying the same stable external identity with a changed title still merges into the same active request.

## Acceptance

```bash
cd core && dune build
cd core && dune runtest
PHAROS_DB=../var/replay.sqlite dune exec pharos -- replay ../examples/gitlab_mr_signal.json
PHAROS_DB=../var/replay.sqlite dune exec pharos -- replay ../examples/gitlab_mr_signal.json
PHAROS_DB=../var/replay.sqlite dune exec pharos -- today | jq '.needs_decision | length'
```

Expected: length is `1`.
