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
core/lib/domain.ml
core/lib/store.ml
core/test/skill_output_test.ml
examples/*.json
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
10. Add tests.

## Do not change

1. Do not call real models unless there is already a local fake model interface. Deterministic starter logic is enough.
2. Do not execute external writes.
3. Do not let skill output bypass policy.

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
