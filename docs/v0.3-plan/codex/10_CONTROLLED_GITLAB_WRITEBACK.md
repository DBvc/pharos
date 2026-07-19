# Task 10: Authenticated and durable GitLab writeback

Task 10 is executed through review-gated control-plane prerequisites followed
by the delivery slice. Do not combine payload identity or delivery work.

## Read first

```text
specs/controlled_writeback_contract.md
docs/DECISIONS.md (ADR-003)
docs/API.md
```

## Task 10a: local auth and approval CAS

### Goal

Close the local API surface and ensure a decision can apply only to the
exact action revision the user reviewed.

### Implementation

1. Reject daemon startup unless host is exactly `127.0.0.1` or `::1`.
2. Require `PHAROS_CAPABILITY_TOKEN` to be exactly 64 lowercase hexadecimal
   characters and validate it before opening SQLite.
3. Keep only `/health` public and protect every registered `/v0/*` route with
   fixed-time Bearer validation.
4. Require `expected_payload_hash` for approve/edit/reject API and CLI calls.
5. In one transaction, re-read action id/status/hash and apply the complete
   review decision only when it is still current.
6. Return HTTP 409 `stale_action` with no decision side effect on mismatch.
7. Swift carries the capability on every request, fails before transport when
   it is missing or malformed, carries the displayed hash, refreshes on stale,
   and does not execute after stale approval.
8. Align ADR, API, OpenAPI, tests, and this Task 10 contract.

### Acceptance

```bash
cd core && dune build
cd core && dune runtest
swift build --package-path ui/macos/PharosApp
```

Tests must prove loopback/config validation, public health, every `/v0` route's
401 behavior, H1-to-H2 stale decisions, status CAS, and transaction rollback.

### Stop line

Do not add `execute-approved`, a GitLab write client, writeback-attempt schema,
or delivery/reconciliation code in Task 10a.

## Task 10a3: payload hash v2

### Goal

Replace delimiter-concatenated MD5 action identity with one versioned,
length-prefixed SHA-256 identity before any durable writeback marker exists.

### Implementation

1. Encode `pharos.action-payload.v2\0`, then byte-length-prefixed
   `target_kind`, `target_ref`, canonical risk, and body.
2. Prefix the 64-character lowercase SHA-256 digest with `sha256:`.
3. Reuse this Core identity for proposal freshness, review CAS, approval
   verification, and Task 10b attempt/marker binding.
4. Fail approval and execution closed for legacy MD5 action hashes. Legacy
   rejection may remain available.
5. Use `digestif`; do not add custom cryptography or a data migration.
6. Document the disposable pre-v2 development database rebuild path.

### Acceptance

```bash
cd core && dune build
cd core && dune runtest
```

Tests cover a golden vector, boundary ambiguity, no-op stability, every payload
field, legacy approve/execute denial, and old approval denial against v2.

### Stop line

Do not add durable attempts, GitLab delivery, reconciliation, or Swift changes
in Task 10a3.

## Task 10b: durable GitLab comment delivery

### Goal

Implement approved GitLab MR/Issue comment delivery with durable attempt state,
unknown-result safety, marker reconciliation, and explicit abandon.

### Implementation

1. Add typed/persisted `writeback_attempts` states from the contract.
2. Add policy preflight that re-reads action, latest approval, request, source
   identity, and source settings and validates hash/risk/allowlist/body/target,
   valid v2 payload hashes, valid source policy, and
   `enabled && write_enabled` through Task 10a2's `Source_settings` owner.
3. Atomically create one active prepared attempt before network work.
4. Run the GitLab client outside SQLite transactions and Dream's event loop.
5. Classify only pre-spawn certainty as `failed_before_send`; all ambiguous
   post-start outcomes become `unknown`.
6. Confirm successful delivery with external id/url, timeline, evidence, and
   metric.
7. Bind markers to the complete v2 payload hash and reconcile unknown attempts
   through exact stable-marker matching with bounded GitLab Notes pagination.
8. Add capability-authenticated explicit abandon; require fresh review and
   approval afterward.
9. Add Swift attempt state and core execution UI without direct GitLab calls.

### Acceptance

```bash
cd core && dune build
cd core && dune runtest
swift build --package-path ui/macos/PharosApp
```

Fake tests must prove every policy negative calls the client zero times,
confirmed delivery, response-loss unknown, crash recovery, reconciliation,
unknown no-second-POST, abandon plus fresh approval, and health responsiveness
during a slow client.

Disabled source, write-disabled source, and invalid persisted scope are policy
negatives. `scope_json.projects` is not a write target membership allowlist.

### Non-goals

No automatic retry, generic queue, Feishu writeback, MR merge/approval, or
commit creation.
