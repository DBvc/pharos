# GitLab Read-Only Adapter Contract

Apply in task 08.

## Goal

Implement the first real source adapter as read-only GitLab MR sync. It must normalize MR review work into SourceSignal, evidence, and request updates without writing to GitLab.

## Required GitLab capabilities

Use GitLab API v4. Required read paths:

1. List merge requests accessible to user with `scope=reviews_for_me` and `state=opened`.
2. For watched projects, list project merge requests with `state=opened`.
3. Fetch individual MR detail.
4. Fetch MR discussions.
5. Fetch latest pipeline status if available from MR fields or linked pipeline endpoint.

## Configuration

Development environment variables:

```text
PHAROS_GITLAB_BASE_URL=https://gitlab.example.com
PHAROS_GITLAB_TOKEN=...
PHAROS_GITLAB_USERNAME=dbvc
```

Do not store token in SQLite. For development, read credentials/base URL/username
from environment. Watched project IDs come only from the persisted GitLab
`scope_json` owned by `Source_settings`; `PHAROS_GITLAB_PROJECTS` is rejected
when present.

## OCaml structure

Add module:

```text
core/lib/adapters/gitlab_read.ml
```

If the current dune layout makes subdirectories awkward, add:

```text
core/lib/gitlab_read.ml
```

but do not put GitLab logic in `runner.ml`.

Suggested module API:

```ocaml
type config = {
  base_url : string;
  token : string;
  username : string option;
  project_ids : string list;
}

val config_from_env : project_ids:string list -> unit -> (config, string) result
val sync_once : Store.t -> config -> (int, string) result
val sync_from_settings : Store.t -> (int, string) result
```

`sync_from_settings` is the production entry point. It obtains the effective
policy and canonical project IDs from `Source_settings`, then combines them with
environment credentials into the explicit adapter config. `sync_once` also
rechecks `effective_read` and that its config matches the persisted scope before
transport. Both return the number of source signals processed.

## Normalized SourceSignal

For each MR:

```text
kind = GitLab
external_id = gitlab:project/<project_id>:mr/<iid>
actor = MR author username or "gitlab"
title = MR title
body = bounded summary string with MR state, author, reviewers, pipeline, discussion count
url = web_url
occurred_at = MR updated_at
raw_json = redacted MR JSON subset, not full token-bearing payload
```

Then call the same Runner path used by fake replay so merge identity applies.

## Evidence requirements

Each GitLab MR request must have evidence items:

1. `gitlab.mr.metadata`
2. `gitlab.mr.pipeline` if known
3. `gitlab.mr.discussions` summary if fetched

Evidence body must be bounded to avoid huge local DB entries. Maximum 4000 chars per evidence item in this task.

## API / CLI

Add dev-only CLI command:

```text
pharos sync-gitlab
```

This calls `sync_from_settings`. Disabled/read-disabled, invalid persisted scope,
legacy project env, or config failure exits non-zero before any GitLab request.
Disabled/read-disabled does not change sync status. Invalid scope/config records
a bounded, sanitized `last_error` for repair.

Optional daemon route:

```text
POST /v0/sources/gitlab/sync-once
```

This route is dev-only and should return an error if env config is missing.

## Non-goals

1. No GitLab writes.
2. No MR approval, no merge, no code changes.
3. No webhook server.
4. No persistent token storage.
5. No full diff parsing beyond a bounded diff stat or placeholder.

## Tests

Do not call real GitLab in tests.

Add a pure parser test using fixture JSON:

```text
examples/gitlab_mr_api_response.json
examples/gitlab_mr_discussions_response.json
core/test/gitlab_read_parser_test.ml
```

Assertions:

1. Fixture MR normalizes to expected `external_id`.
2. URL is preserved.
3. Evidence bodies are bounded.
4. Missing optional fields do not crash parser.
5. `{}` calls only the global `reviews_for_me` endpoint.
6. Persisted watched projects append only their project endpoints.
7. Disabled/read-disabled/invalid scope/legacy env all keep client call count at
   zero, with the specified sync-status behavior.

## Acceptance

```bash
cd core && dune build && dune runtest
PHAROS_GITLAB_BASE_URL=... PHAROS_GITLAB_TOKEN=... PHAROS_GITLAB_USERNAME=... dune exec pharos -- sync-gitlab
```

Expected in dev with real env: one or more GitLab MRs create or update request cards. No write API is called.
