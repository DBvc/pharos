# Task 05: Policy safety tests and blocked-attempt timeline

Branch: `codex/policy-safety-tests`

## Goal

Harden the core safety boundary before real adapters and external writes.

## Read first

```text
specs/policy_safety_contract.md
```

## Files to change

```text
core/lib/policy.ml
core/lib/store.ml
core/lib/migrations.ml
core/test/policy_smoke.ml
```

Optional new test files are allowed under `core/test/`.

## Exact implementation steps

1. Add or update policy tests for all required invariants in `specs/policy_safety_contract.md`.
2. Add `Store.get_metric_for_day` or equivalent test helper if needed.
3. Modify `Policy.execute_local` so non-`pharos.` targets:
   - insert timeline event kind `policy_block`
   - bump `unapproved_external_write_attempts`
   - return `ExternalWritebackNotImplemented`
4. Ensure the timeline body does not include full action body.
5. Ensure edit-and-approve test proves action body and hash changed.

## Do not change

1. Do not add real external writeback.
2. Do not make L4/L5 executable.
3. Do not count successful approved local execution as external write.

## Commands

```bash
cd core && dune build
cd core && dune runtest
```

## Acceptance

All tests in the policy safety contract pass.

## Final response format

```text
Changed files:
Tests run:
Safety invariants covered:
Known follow-up:
```
