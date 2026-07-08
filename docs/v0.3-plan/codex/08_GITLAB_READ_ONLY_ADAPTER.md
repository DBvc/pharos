# Task 08: GitLab read-only adapter

Branch: `codex/gitlab-read-adapter`

## Goal

Implement read-only GitLab MR sync using bounded context, evidence, source signals, and merge identity. No writes.

## Read first

```text
specs/gitlab_read_adapter_contract.md
```

## Files to change

```text
core/lib/gitlab_read.ml or core/lib/adapters/gitlab_read.ml
core/lib/runner.ml
core/bin/cli/main.ml
core/bin/daemon/main.ml
core/test/gitlab_read_parser_test.ml
examples/gitlab_mr_api_response.json
examples/gitlab_mr_discussions_response.json
docs/API.md
docs/ADAPTER_PROTOCOL.md
```

## Exact implementation steps

1. Add GitLab read module with `config_from_env` and `sync_once`.
2. Add pure JSON normalization functions and test them with fixtures.
3. Normalize MRs into `SourceSignal` using the same path as fake replay.
4. Insert MR metadata, pipeline, and discussions as evidence.
5. Add CLI `pharos sync-gitlab`.
6. Optional dev route `POST /v0/sources/gitlab/sync-once`.
7. Ensure adapter errors do not crash daemon.
8. Ensure no write API is called.

## Do not change

1. Do not post comments.
2. Do not approve, merge, or modify MRs.
3. Do not store GitLab token in SQLite.
4. Do not call real GitLab in tests.

## Commands

```bash
cd core && dune build && dune runtest
```

Manual dev command with real env is allowed but not required for tests:

```bash
PHAROS_GITLAB_BASE_URL=... PHAROS_GITLAB_TOKEN=... PHAROS_GITLAB_USERNAME=... dune exec pharos -- sync-gitlab
```

## Acceptance

1. Parser tests pass without network.
2. With real env, `sync-gitlab` creates or updates GitLab request cards.
3. Repeated sync updates the same active request.
4. Detail shows GitLab URL and evidence.

## Final response format

```text
Changed files:
Tests run:
Network/manual sync status:
Known follow-up:
```
