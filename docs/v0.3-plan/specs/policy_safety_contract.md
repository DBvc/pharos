# Policy Safety Contract

Apply in task 05.

## Files to edit

```text
core/lib/policy.ml
core/lib/store.ml
core/lib/migrations.ml
core/test/policy_smoke.ml
```

Optional new tests:

```text
core/test/policy_hash_test.ml
core/test/policy_rejection_test.ml
core/test/policy_risk_test.ml
```

## Required invariants

1. Executing an action that requires approval without approval returns `ApprovalRequired` or a stricter block error.
2. Edit-and-approve updates the action body and hash. Execution uses the edited body/hash.
3. Rejected actions cannot execute.
4. L4 and L5 actions cannot be approved or executed in MVP.
5. `execute-local` must never execute non-`pharos.` target kinds.
6. Blocked external-target attempts must create a timeline event and bump a metric.
7. The timeline event must not include full action body or secret-bearing payloads.

## Required policy behavior change

When `Policy.execute_local` sees an action with `target_kind` not starting with `pharos.`, it must:

1. Insert a timeline event for the action request:

```text
kind: policy_block
title: External writeback blocked by local executor
body: target_kind=<target_kind>; action_id=<action_id>; reason=external_writeback_not_available
```

2. Bump metric:

```text
unapproved_external_write_attempts
```

3. Return:

```ocaml
Error (ExternalWritebackNotImplemented action.target_kind)
```

This is intentionally conservative in M0/M1. The dedicated controlled writeback route in task 10 will use a different execution path.

## Test helper requirement

If constructing non-manual actions is verbose, add test helper functions inside test files, not production code:

```ocaml
let insert_test_request store ~status ~risk = ...
let insert_test_action store ~request_id ~risk ~target_kind ~requires_approval = ...
```

## Tests to implement

### Test 1: execution requires approval

Existing test may remain.

### Test 2: edit-and-approve writes edited payload

Steps:

1. Capture manual request.
2. Get first action.
3. Save old payload hash.
4. Call `Runner.approve ~edited_body:"edited body" ~expected_payload_hash:action.payload_hash`.
5. Reload action.
6. Assert body = `edited body`.
7. Assert payload hash changed.
8. Execute local.
9. Assert request status = `Done`.

### Test 3: rejection blocks execution

Steps:

1. Capture manual request.
2. Reject action.
3. Execute local.
4. Assert `RejectedAction`.
5. Assert request status = `Archived` or rejection-specific terminal state if added.

### Test 4: L4/L5 cannot approve or execute

Steps:

1. Insert action with risk `L4`.
2. Call approve.
3. Assert `RiskNotExecutableInMvp L4`.
4. Call execute.
5. Assert `RiskNotExecutableInMvp L4`.
6. Repeat for L5.

### Test 5: external target blocked and logged

Steps:

1. Insert action with `target_kind = "gitlab.mr.comment"`, risk `L3`, requires approval true.
2. Call `execute_local`.
3. Assert `ExternalWritebackNotImplemented "gitlab.mr.comment"`.
4. Assert request timeline includes `policy_block`.
5. Assert `metrics_daily.unapproved_external_write_attempts` increased by 1.

Add a `Store.get_metric_for_day` helper if needed for tests.

## Acceptance

```bash
cd core && dune build
cd core && dune runtest
```
