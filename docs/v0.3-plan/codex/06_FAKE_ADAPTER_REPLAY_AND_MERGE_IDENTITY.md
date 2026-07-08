# Task 06: Fake adapter replay and merge identity

Branch: `codex/fake-replay-merge-identity`

## Goal

Add fixture replay and request identity so repeated GitLab/Feishu-like events update one active request instead of duplicating cards.

## Read first

```text
specs/fake_adapter_replay_and_merge_contract.md
```

## Files to change

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/migrations.ml
core/lib/runner.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
core/test/merge_identity_test.ml
examples/gitlab_mr_signal.json
examples/feishu_chat_signal.json
examples/feishu_project_signal.json
examples/feishu_docs_signal.json
docs/API.md
protocol/openapi.yaml
```

## Exact implementation steps

1. Add source-signal input parser for external fixture payloads.
2. Add `POST /v0/source-signals`.
3. Add CLI `pharos replay <path>`.
4. Add `work_request_identities` table.
5. Implement stable external identity key exactly as specified in the contract:
   - `external_id` first.
   - canonical URL fallback second.
   - normalized subject only when no stable external object id or URL exists.
6. Implement active request update behavior.
7. Add timeline `merge` event.
8. Add source update evidence.
9. Add fixtures for four P0 source kinds.
10. Add tests proving no duplicate active card.

## Do not change

1. Do not call real GitLab or Feishu.
2. Do not implement adapter writeback.
3. Do not skip source signal insertion on merge; each external event should still be traceable.
4. Do not include mutable title/subject in the primary identity key when `external_id` exists.

## Commands

```bash
cd core && dune build
cd core && dune runtest
rm -f ../var/replay.sqlite
PHAROS_DB=../var/replay.sqlite dune exec pharos -- replay ../examples/gitlab_mr_signal.json
PHAROS_DB=../var/replay.sqlite dune exec pharos -- replay ../examples/gitlab_mr_signal.json
PHAROS_DB=../var/replay.sqlite dune exec pharos -- today | jq '.needs_decision | length'
```

Expected: `1`.

Additional required smoke/test:

```text
Replay same GitLab external_id with a changed title.
Expected: same active request id and one active Today card.
```

## Final response format

```text
Changed files:
Tests run:
Replay smoke result:
Known follow-up:
```
