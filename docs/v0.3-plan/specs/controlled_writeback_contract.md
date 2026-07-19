# Controlled GitLab Writeback Contract

Apply across Task 10a, Task 10a2, Task 10a3, and Task 10b. All three control
plane gates are hard prerequisites for Task 10b.

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

## Task 10a3: versioned payload identity

Core owns one payload identity for proposal freshness, review CAS, approval
verification, durable attempts, and future writeback markers. Canonical bytes
are the ASCII tag `pharos.action-payload.v2` followed by one NUL byte, then
these fields in order:

```text
uint64_be(byte_length(target_kind)) || target_kind
uint64_be(byte_length(target_ref))  || target_ref
uint64_be(byte_length(risk))        || canonical risk (l0 through l5)
uint64_be(byte_length(body))        || body
```

Lengths count bytes. SHA-256 over those bytes is stored exactly as
`sha256:<64 lowercase hex>`. API clients treat the value as opaque and echo it
unchanged. Approval and execution accept only complete v2 hashes; a legacy MD5
proposal may still be rejected. There is no silent rewrite or SQLite migration
for unreleased pre-v2 development state; rebuild the disposable dev database.

## Task 10b: durable controlled delivery

Task 09 must already provide a current action with canonical target provenance,
Task 10a must already enforce caller authentication and revision-bound review,
and Task 10a2 must make persisted source settings the single operational policy
owner. Task 10a3 must already provide the v2 payload identity used by approval,
attempt, and marker records.

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
4. Action and latest approval carry complete v2 `sha256:` hashes, and the
   approval matches the current payload hash.
5. Target kind is `gitlab.mr.comment` or `gitlab.issue.comment`.
6. GitLab source policy is valid and
   `effective_write = enabled && write_enabled` is true.
7. Body is nonblank and at most 8000 characters.
8. Target provenance matches the request's stable GitLab instance and source
   object.

The GitLab base URL is canonicalized as an HTTPS origin plus optional relative
root and may not contain userinfo, query, fragment, controls, dot segments, or
encoded slashes. Its instance id is the lowercase SHA-256 digest of
`pharos.gitlab-instance.v1\0 || canonical_base_url`. Source ids use
`gitlab:instance/<instance_sha256>:project/<id>:mr/<iid>` (or `issue`), MR
targets use `instance=<instance_sha256>;project_id=<id>;mr_iid=<iid>`, and issue
targets use `instance=<instance_sha256>;project_id=<id>;issue_iid=<iid>`.
Missing, legacy, malformed, or mismatched provenance must fail before the fake
or real client is called. Runtime config must produce the same instance id as
the approved target before curl starts.

`scope_json.projects` is an additional read-time watched-project set, not write
authorization. Preflight must not use project membership as a target gate; it
uses stable request/source provenance instead. Invalid persisted scope fails
closed before the client.

### Delivery classification

Only failures known before curl/config/spawn may become `failed_before_send`.
After a child request starts, timeout, nonzero exit, oversized or invalid JSON,
missing response id, daemon crash, and lost response all become `unknown`.
`unknown` never retries automatically and never issues a second POST.

The real client accepts HTTPS only, places curl `--disable` first, and restricts
protocols. Token and body must not appear in argv, child environment, logs,
timeline, or evidence.

A successful note response must contain a positive integer id and target-bound
`project_id`, `noteable_type`, and `noteable_iid`. Persisted external URLs use
the exact API note resource built from the canonical base and numeric target;
untrusted source URLs are not used to construct delivery results. Credential-
bearing base URLs fail before transport and are never persisted.

### Marker reconciliation and abandon

The stable marker binds attempt id and the complete v2 payload hash.
Reconciliation uses the official GitLab MR/Issue Notes list or retrieve API
with bounded pagination and exact marker matching. A match confirms the
attempt; no match leaves it `unknown` and never proves non-delivery.
Before every reconciliation client call, core re-reads source settings and
requires valid scope plus current `effective_write`.

Only an explicit capability-authenticated abandon of an `unknown` attempt may
set it to `abandoned`, write an audit timeline event, return the action to
`ActionProposed`, return the request to `ReadyForReview`, and require fresh
approval. There is no automatic retry.

Delivery ownership rejects an existing SQLite database with more than one hard
link. Swift auto-executes only local Pharos actions and the explicit GitLab
comment allowlist; unsupported external kinds remain approved-only. Swift
refreshes Today and selected request detail after writeback transport errors or
conflicts before presenting the error.

## Required tests

Task 10a tests all `/v0` routes for missing/wrong capability, public health,
loopback and token-format validation, H1-to-H2 stale approve/edit/reject with no
decision side effect, status CAS, and transaction rollback. Swift build plus
code review proves every request carries the capability and missing config
fails before URLSession transport.

Task 10a3 tests a stable golden vector, ambiguous old delimiter boundaries,
no-op stability, every identity field, legacy approval/execution rejection,
and denial of a legacy approval against a v2 action.

Task 10b uses a fake GitLab client. All policy negatives keep client call count
at zero. It also covers edited content, confirmed writeback evidence/timeline,
remote-created-but-response-lost, crash recovery from `in_flight`, marker
reconciliation, unknown with no second POST, explicit abandon plus fresh
approval, instance drift, response target mismatch, hard-link rejection,
reconciliation policy re-check, Swift routing/state refresh, and `/health`
responsiveness while the client is slow.

Legacy GitLab identities without an instance id are not migrated or silently
rewritten. Rebuild the disposable unreleased v0.3 development database.

## Non-goals

No MR merge/approval, commits, Feishu writeback, generic queue framework, or
automatic retry is part of Task 10.
