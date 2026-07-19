# Task 09: Built-in skills v0

Branch: `codex/builtin-skills-v0`

## Goal

Add deterministic starter skills that prepare next moves from manual, GitLab, and Feishu-like fixtures without external writeback.

## Read first

```text
specs/skills_v0_contract.md
```

## Files to change

```text
core/lib/skill.ml
core/lib/triage.ml
core/lib/runner.ml
core/lib/runner.mli
core/lib/domain.ml
core/lib/store.ml
core/lib/gitlab_read.ml
core/test/skill_output_test.ml
core/test/merge_identity_test.ml
core/test/gitlab_read_parser_test.ml
examples/*.json
docs/v0.3-plan/specs/fake_adapter_replay_and_merge_contract.md
docs/v0.3-plan/specs/skills_v0_contract.md
docs/v0.3-plan/specs/controlled_writeback_contract.md
```

## Exact implementation steps

1. Define typed skill input/output records.
2. Add parsers/validators for skill outputs.
3. Implement deterministic `triage_skill`.
4. Implement deterministic `context_summary_skill`.
5. Implement deterministic `draft_reply_skill`.
6. Implement deterministic `gitlab_mr_review_skill`.
7. Make runner create proposed actions from valid skill outputs.
8. Ensure every skill-produced action has evidence reference information.
9. On invalid output, record `skill_error` timeline and set request to `NeedsContext` or `Failed`.
10. Persist each normalized source bundle atomically and run skills after bounded evidence is stored.
11. Keep one current proposal per active request and implement the exact proposal freshness rule.
12. Generate canonical GitLab MR target refs from stable source identity.
13. Use Core payload hash v2 for proposal no-op/freshness identity; skills and adapters do not recompute it.
14. Add rollback, no-op approval preservation, changed-payload invalidation, rich-evidence,
    and policy-bypass regression tests.

## Do not change

1. Do not call real models unless there is already a local fake model interface. Deterministic starter logic is enough.
2. Do not execute external writes.
3. Do not let skill output bypass policy.
4. Do not add an action supersede state/table or evidence join table for this task.
5. Do not treat every sync as an approval invalidation; only generated executable payload
   changes require review again.

## Commands

```bash
cd core && dune build && dune runtest
```

Manual smoke:

```bash
PHAROS_DB=../var/skills.sqlite dune exec pharos -- replay ../examples/gitlab_mr_signal.json
PHAROS_DB=../var/skills.sqlite dune exec pharos -- today | jq '.needs_decision[0].prepared_next_move'
```

Expected: non-null prepared next move.

## Final response format

```text
Changed files:
Tests run:
Skill smoke result:
Known follow-up:
```
