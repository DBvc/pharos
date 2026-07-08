# Request Detail Judgment View Contract

Apply in task 04.

## File to edit

```text
ui/macos/PharosApp/Sources/PharosApp/Views/RequestDetailView.swift
```

## Required layout order

The detail view must render sections in this order:

1. Header
2. What is this?
3. Why now?
4. Evidence used
5. Prepared next move
6. Execution record
7. Audit details

## Section requirements

### Header

Show:

```text
title
source kind
priority
risk
internal status as secondary debug metadata
```

Do not use internal status as the primary judgment label.

### What is this?

Use:

```text
detail.request.summary
source link if evidence/source url exists
```

### Why now?

Use:

```text
detail.request.reason
detail.request.nextStep
```

Copy labels:

```text
Why Pharos brought this here
Suggested next step
```

### Evidence used

Show `detail.evidence` before the action approval area.

Each evidence item shows:

```text
title
kind
body
open source link when url exists
```

### Prepared next move

For each `ProposedAction`, render:

```text
action.title
action.body editable text area
target system: action.targetKind
target object: action.targetRef
external write: yes when targetKind does not start with "pharos."
risk: action.risk
```

Button labels:

- Local target: `Approve and complete locally`
- External target: `Approve and send` or `Approve and post`
- `Edit and Approve`
- `Reject`

For M0, external targets should not be executable through `execute-local`; the UI can still show that they require future writeback.

### Execution record

Render `detail.timeline` after prepared action.

Accept either always-visible timeline or a `DisclosureGroup("Execution record")`.

### Audit details

Render under a disclosure section:

```text
payload_hash
action id
request id
internal status
```

Payload hash must not be in the main decision row.

## Required behavior

1. `Approve` path calls existing approval flow.
2. `Edit and Approve` uses edited text from the text editor.
3. `Reject` records rejection.
4. Buttons are disabled for executed or rejected actions.
5. After any action, detail refreshes.

## Non-goals

Do not implement real external writeback in this task.
Do not move policy checks into Swift.
Do not remove timeline or payload hash from detail entirely; just demote them to audit details.
