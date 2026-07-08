# v0.3 docs alignment

## Objective

Create PRD v0.3 and align README/API/architecture/iteration docs so Today uses attention groups.

## Instructions

Use `codex/01_CREATE_PRD_V03_AND_DOCS_ALIGNMENT.md` as the exact execution prompt. Also provide `codex/00_MASTER_RULES.md` in the same Codex session.

## Acceptance checklist

- [ ] Required files changed only as specified.
- [ ] Product language remains aligned with v0.3.
- [ ] OCaml build passes, if core changed.
- [ ] OCaml tests pass, if core changed.
- [ ] Swift build passes, if Swift changed or environment supports SwiftPM.
- [ ] No external writeback added unless this is issue 10.
- [ ] Safety invariants preserved.

## Notes for reviewer

Review the final Codex response for:

```text
Changed files:
Tests run:
Acceptance status:
Known follow-up:
```
