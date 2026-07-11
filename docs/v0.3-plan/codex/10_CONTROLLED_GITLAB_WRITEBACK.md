# Task 10: Authenticated and durable GitLab writeback

Task 10 is executed as two review-gated slices. Do not combine them.

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

## Task 10b: durable GitLab comment delivery

### Goal

Implement approved GitLab MR/Issue comment delivery with durable attempt state,
unknown-result safety, marker reconciliation, and explicit abandon.

### Implementation

1. Add typed/persisted `writeback_attempts` states from the contract.
2. Add policy preflight that re-reads action, latest approval, request, source
   identity, and source settings and validates hash/risk/allowlist/body/target.
3. Atomically create one active prepared attempt before network work.
4. Run the GitLab client outside SQLite transactions and Dream's event loop.
5. Classify only pre-spawn certainty as `failed_before_send`; all ambiguous
   post-start outcomes become `unknown`.
6. Confirm successful delivery with external id/url, timeline, evidence, and
   metric.
7. Reconcile unknown attempts through exact stable-marker matching with bounded
   GitLab Notes pagination.
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

### Non-goals

No automatic retry, generic queue, Feishu writeback, MR merge/approval, or
commit creation.
