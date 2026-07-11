# Controlled GitLab Writeback Contract

Apply in task 10.

## Goal

Add the first real external writeback path: approved GitLab MR/Issue comment. This is the first task allowed to write to an external system.

## Required safety path

Task 09 is a hard prerequisite. It must produce a current GitLab MR action with canonical
`target_ref = project_id=<id>;mr_iid=<iid>`, and proposal freshness must ensure that only an
approval whose hash matches the current action payload can reach this path. An approval
retained for audit after source evidence refresh is not executable authority.

External writeback must flow through this shape:

```text
ProposedAction(target_kind="gitlab.mr.comment", body, risk=L3)
  -> Review Gate displays body + target + evidence
  -> user approves or edits
  -> Approval(action_id, action_hash, approved_body)
  -> execute external route receives action_id only or action_id + approval_id
  -> core re-reads action, approval, request, source identity, and source settings
  -> policy verifies hash match, source write permission, and target provenance
  -> GitLab adapter posts comment
  -> timeline and evidence record result URL/id/hash/approval id
```

## Files to edit

```text
core/lib/policy.ml
core/lib/store.ml
core/lib/domain.ml
core/lib/gitlab_write.ml or core/lib/adapters/gitlab_write.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
ui/macos/PharosApp/Sources/PharosApp/Core/APIClient.swift
ui/macos/PharosApp/Sources/PharosApp/Core/AppState.swift
ui/macos/PharosApp/Sources/PharosApp/Views/RequestDetailView.swift
docs/API.md
protocol/openapi.yaml
```

## API

Add:

```text
POST /v0/actions/:id/execute-approved
```

Do not make Swift call adapter-specific routes directly.

Request body may be `{}`.

Response:

```json
{
  "action": {},
  "writeback": {
    "target_kind": "gitlab.mr.comment",
    "external_id": "note_123",
    "external_url": "https://gitlab.example.com/...#note_123"
  }
}
```

## Policy checks

Before calling GitLab write API:

1. Action exists.
2. Action status is not rejected or already executed.
3. Action risk is executable in MVP.
4. Action risk L3 requires approval.
5. Latest approval exists.
6. Approval hash matches current action payload hash.
   The request/action must also still represent the current proposal after the latest source
   evidence refresh; a stale audit approval is rejected even if it remains stored.
7. `target_kind` is in allowlist:

```text
gitlab.mr.comment
gitlab.issue.comment
```

8. Source setting for GitLab has `write_enabled = true`.
9. Action body is non-empty after trim.
10. Action body length <= 8000 characters for v0.
11. Target provenance matches the request's GitLab source object.

Target provenance means:

1. Re-read the action's `request_id`.
2. Re-read the corresponding `WorkRequest`.
3. Re-read its source signal and/or request identity.
4. Parse the stable GitLab source object id, for example:

```text
gitlab:project/<project_id>:mr/<iid>
gitlab:project/<project_id>:issue/<iid>
```

5. Parse `target_ref`.
6. Fail closed before calling GitLab if the target object does not match the source object for that request.

## GitLab target refs

For MR comments, use:

```text
target_kind = gitlab.mr.comment
target_ref = project_id=<id>;mr_iid=<iid>
```

For issue comments:

```text
target_kind = gitlab.issue.comment
target_ref = project_id=<id>;issue_iid=<iid>
```

Parser must fail closed if required fields are missing.

For MR comments, `target_ref` must match a source object id equivalent to:

```text
gitlab:project/<project_id>:mr/<iid>
```

For issue comments, `target_ref` must match a source object id equivalent to:

```text
gitlab:project/<project_id>:issue/<iid>
```

## Required timeline event on success

```text
kind: writeback
title: GitLab comment posted
body: action_id=<id>; approval_id=<id>; target=<target_kind>/<target_ref>; hash=<payload_hash>; external_url=<url>
```

## Required evidence item on success

```text
kind: writeback.gitlab.comment
title: GitLab writeback result
body: Posted comment <external_id> to <target_kind>/<target_ref>
url: external_url
```

## Tests

No real GitLab calls in tests. Use a fake GitLab client.

Required tests:

1. Unapproved L3 action cannot execute.
2. Edited approval posts edited content to fake client.
3. Approval hash mismatch blocks.
4. L4/L5 action blocks.
5. GitLab write disabled in source settings blocks.
6. Successful write records timeline and evidence.
7. Target provenance mismatch blocks before the fake GitLab client is called.
8. Swift action button calls `/execute-approved`, not `/execute-local`, for external target.

## Non-goals

1. Do not merge MR.
2. Do not approve MR.
3. Do not create commits.
4. Do not support Feishu writeback in this task.

## Acceptance

```bash
cd core && dune build && dune runtest
```

Manual dev acceptance with real GitLab env and write permission explicitly enabled:

1. Replay or sync a GitLab MR.
2. Generate or create an L3 GitLab comment action.
3. Try execute without approval: blocked.
4. Edit and approve.
5. Execute approved action.
6. Confirm GitLab comment body is edited body.
7. Confirm timeline contains approval id, hash, target, and external URL.
8. Manually or in fake-client tests, confirm a target_ref pointing at a different MR is blocked.
