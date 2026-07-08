# Task 04: Request Detail judgment view

Branch: `codex/request-detail-judgment-view`

## Goal

Rework Request Detail so a user can make a decision quickly: what it is, why it matters, what evidence exists, and what happens if they approve.

## Read first

```text
specs/request_detail_contract.md
```

## Files to change

```text
ui/macos/PharosApp/Sources/PharosApp/Views/RequestDetailView.swift
```

Optional supporting UI component files may be added under:

```text
ui/macos/PharosApp/Sources/PharosApp/Components/
```

## Exact implementation steps

1. Keep `RequestDetailView(detail:)` public interface unchanged.
2. Reorder body sections:
   - Header
   - What is this?
   - Why now?
   - Evidence used
   - Prepared next move
   - Execution record
   - Audit details
3. Rename `Proposed Actions` heading to `Prepared next move`.
4. Move evidence before action buttons.
5. Show target system, target object, external write yes/no, and risk before buttons.
6. Button labels:
   - local target: `Approve and complete locally`
   - external target: `Approve and send` or `Approve and post`
   - `Edit and Approve`
   - `Reject`
7. Move payload hash into `DisclosureGroup("Audit details")`.
8. Timeline goes under `Execution record` after prepared action.
9. Keep existing approve/edit/reject behavior.

## Do not change

1. Do not implement external writeback.
2. Do not remove payload hash entirely.
3. Do not hide evidence.
4. Do not add policy decisions to Swift.

## Commands

```bash
swift build --package-path ui/macos/PharosApp
```

## Acceptance

Manual review of UI code must show the four questions in order:

1. What is this?
2. Why now?
3. Evidence used
4. Prepared next move

A manual M0 request can still be approved, edited and approved, and rejected.

## Final response format

```text
Changed files:
Swift build:
Acceptance status:
Known follow-up:
```
