# Controlled GitLab Writeback Contract

Apply in Task 10a and Task 10b. Task 10a is a hard prerequisite for Task 10b.

## Goal

Close the local mutation control plane before enabling the first real external
side effect, then deliver approved GitLab MR/Issue comments through a durable,
reconcilable core-owned state machine.

## Task 10a: local control plane and review CAS

### Runtime boundary

1. `pharosd` accepts only `127.0.0.1` or `::1`; other hosts fail startup.
2. `PHAROS_CAPABILITY_TOKEN` is exactly 64 lowercase hexadecimal characters and
   is validated before SQLite is opened.
3. `/health` is public. Every registered `/v0/*` route validates
   `Authorization: Bearer ...` using fixed-time comparison.
4. Missing or malformed daemon configuration stops startup. Missing or invalid
   caller authorization returns HTTP 401 before the route handler runs.
5. Capability and GitLab tokens never enter SQLite, timeline, metrics, exports,
   API examples, test snapshots, or logs.

The v0.3 threat model protects against non-loopback exposure, unauthenticated
network calls, browser or accidental local calls, and other OS users. It does
not protect against malicious software that already controls the same user
account or process environment. Unix socket and Keychain lifecycle hardening
remain future work.

### Revision-bound review gate

Approve, edit-and-approve, and reject receive the action id plus the
`expected_payload_hash` shown by the UI. The core re-reads the action inside one
SQLite transaction and accepts the decision only when the action exists, is
still `ActionProposed`, and its current hash matches the expected hash.

The hash/status check, optional body and hash update, action/request status,
approval or rejection record, decision timeline, and metric are one atomic
transaction. A stale hash or status returns HTTP 409
`{"error":"stale_action"}` with no decision side effect. Swift refreshes the
detail and requires review of the new revision; it must not execute after a
stale response. Direct CLI review commands require the expected hash too.

Task 10a does not add a GitLab write client, delivery route, or delivery state.

## Task 10b: durable controlled delivery

Task 09 must already provide a current action with canonical target provenance,
and Task 10a must already enforce caller authentication and revision-bound
review.

External writeback flows through this shape:

```text
current ProposedAction(target_kind="gitlab.*.comment", risk=L3)
  -> user reviews body, target, evidence and current payload hash
  -> approval CAS creates Approval bound to current hash
  -> execute-approved re-reads action/approval/request/source/settings
  -> policy transaction creates one durable writeback attempt
  -> GitLab client runs outside SQLite transaction and Dream event loop
  -> finalize confirmed, failed_before_send, or unknown
  -> unknown can only reconcile or be explicitly abandoned
```

### Durable attempt source of truth

`writeback_attempts` owns delivery state; timeline and action status do not.
Typed states are:

```text
prepared
in_flight
confirmed
unknown
failed_before_send
abandoned
```

An attempt binds attempt id, action id, approval id, payload hash, target,
stable marker, optional external id/url, sanitized error, and timestamps. One
action may have only one active `prepared`, `in_flight`, or `unknown` attempt.

### Policy preflight

Before any client call, core re-reads and verifies:

1. Current action and request exist.
2. Action is approved, not rejected or already executed.
3. Risk is executable in v0.3; L4/L5 always fail closed.
4. Latest approval exists and matches the current payload hash.
5. Target kind is `gitlab.mr.comment` or `gitlab.issue.comment`.
6. GitLab source `write_enabled` is true.
7. Body is nonblank and at most 8000 characters.
8. Target provenance matches the request's stable GitLab source object.

MR targets use `project_id=<id>;mr_iid=<iid>` and issue targets use
`project_id=<id>;issue_iid=<iid>`. Missing, malformed, or mismatched provenance
must fail before the fake or real client is called.

### Delivery classification

Only failures known before curl/config/spawn may become `failed_before_send`.
After a child request starts, timeout, nonzero exit, oversized or invalid JSON,
missing response id, daemon crash, and lost response all become `unknown`.
`unknown` never retries automatically and never issues a second POST.

The real client accepts HTTPS only, places curl `--disable` first, and restricts
protocols. Token and body must not appear in argv, child environment, logs,
timeline, or evidence.

### Marker reconciliation and abandon

The stable marker binds attempt id and payload hash. Reconciliation uses the
official GitLab MR/Issue Notes list or retrieve API with bounded pagination and
exact marker matching. A match confirms the attempt; no match leaves it
`unknown` and never proves non-delivery.

Only an explicit capability-authenticated abandon of an `unknown` attempt may
set it to `abandoned`, write an audit timeline event, return the action to
`ActionProposed`, return the request to `ReadyForReview`, and require fresh
approval. There is no automatic retry.

## Required tests

Task 10a tests all `/v0` routes for missing/wrong capability, public health,
loopback and token-format validation, H1-to-H2 stale approve/edit/reject with no
decision side effect, status CAS, and transaction rollback. Swift build plus
code review proves every request carries the capability and missing config
fails before URLSession transport.

Task 10b uses a fake GitLab client. All policy negatives keep client call count
at zero. It also covers edited content, confirmed writeback evidence/timeline,
remote-created-but-response-lost, crash recovery from `in_flight`, marker
reconciliation, unknown with no second POST, explicit abandon plus fresh
approval, and `/health` responsiveness while the client is slow.

## Non-goals

No MR merge/approval, commits, Feishu writeback, generic queue framework, or
automatic retry is part of Task 10.
