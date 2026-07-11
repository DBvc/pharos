# Built-in Skills v0 Contract

Apply in task 09.

## Goal

Pharos should stop being a passive catcher and start preparing useful next moves. Skills must produce typed outputs with evidence references and never execute external writes.

## Files to edit

```text
core/lib/skill.ml
core/lib/triage.ml
core/lib/runner.ml
core/lib/runner.mli
core/lib/domain.ml
core/lib/store.ml
core/test/skill_output_test.ml
```

## Required skills

### 1. triage_skill

Input:

```json
{
  "source_signal_id": "sig_...",
  "kind": "gitlab",
  "title": "...",
  "body": "...",
  "url": "..."
}
```

Output:

```json
{
  "should_create_request": true,
  "request_type": "gitlab_mr_review",
  "priority": "normal",
  "risk": "l1",
  "reason": "You were requested as reviewer.",
  "next_step": "Prepare a review summary and comment draft.",
  "needs_context": false,
  "notify_user": false,
  "evidence_refs": ["ev_..."]
}
```

### 2. context_summary_skill

Output must distinguish:

```json
{
  "facts": [],
  "inferences": [],
  "unknowns": [],
  "evidence_refs": []
}
```

### 3. draft_reply_skill

Output:

```json
{
  "draft_body": "...",
  "target_kind": "feishu.chat.reply",
  "target_ref": "thread id or message id",
  "risk": "l3",
  "requires_approval": true,
  "evidence_refs": []
}
```

### 4. gitlab_mr_review_skill

Output:

```json
{
  "summary": "...",
  "risk_points": [],
  "test_gaps": [],
  "draft_comment": "...",
  "target_kind": "gitlab.mr.comment",
  "target_ref": "project_id=123;mr_iid=456",
  "risk": "l3",
  "requires_approval": true,
  "evidence_refs": []
}
```

## Implementation mode for v0

No model calls are required in this task. Implement deterministic starter skills using rules and fixtures.

Examples:

1. GitLab MR signal -> MR review summary/action.
2. Feishu chat signal -> reply draft action.
3. Manual capture -> local completion action.

`project_next_step_skill` and `doc_understanding_skill` remain roadmap skill ids. Task 09
does not invent output contracts or implementations for them.

## Parser rule

Every skill output must be parsed and validated before it can create a `ProposedAction`.

The persistence path is closed over the built-in skill policy. It must not accept an
arbitrary `skill_id + target_kind + risk + requires_approval` combination. In v0:

1. local context action is `pharos.local.complete_request`, L2, approval required;
2. Feishu reply is `feishu.chat.reply`, L3, approval required, target bound to source id;
3. GitLab review is `gitlab.mr.comment`, L3, approval required, target derived from the
   stable GitLab MR external id.

Invalid output must:

1. Not create an action.
2. Insert timeline event `skill_error`.
3. Put request in `NeedsContext` or `Failed` with visible reason.

## Evidence rule

Every proposed action created by a skill must have at least one evidence reference. If the current schema has no join table, encode evidence refs in the timeline body or action metadata placeholder, but do not fake the existence of evidence.

Future schema can add:

```sql
proposed_action_evidence(action_id TEXT, evidence_id TEXT)
```

## Source bundle and transaction rule

Adapters fetch and normalize remote data before opening a SQLite transaction. Runner then
receives the `SourceSignal` plus its bounded evidence as one source bundle. Within one local
transaction it must persist signal, identity, request, evidence, skill result, action,
timeline, and metrics.

1. A SQL/process exception rolls back the entire local bundle.
2. A validly observed skill parse/validation failure is business state, not a transaction
   exception: commit `NeedsContext` plus a visible `skill_error`.
3. Skills run only after all evidence in the bundle is persisted.
4. Audit evidence such as `source.update` may be retained without becoming unstable skill
   input; material evidence ids used by actions must remain stable across no-op refreshes.

## Proposal freshness rule

Each active request has at most one current proposal.

1. Recompute the deterministic generated action when material source context changes.
2. Track the material context fingerprint and generated payload hash in timeline metadata;
   do not add a schema solely for this task.
3. If context is unchanged, preserve the current action exactly, including a user-edited
   approved body.
4. If context changed but the newly generated executable payload is unchanged, preserve the
   current action and approval.
5. If generated body, target, risk, evidence references, or payload hash changes, update the
   same action id, set it to `ActionProposed`, and return the request to `ReadyForReview`.
6. Keep old approvals for audit. Their old hash must not authorize the refreshed action.
7. `Done` and `Archived` requests continue to create a new request on replay.

For GitLab MR comments, parse a stable source id equivalent to
`gitlab:project/<project_id>:mr/<iid>` and generate exactly:

```text
project_id=<project_id>;mr_iid=<iid>
```

Missing or malformed provenance must fail closed to `NeedsContext`; an internal request or
signal id is not a valid external target.

## Tests

1. Valid triage skill output parses.
2. Invalid priority/risk is rejected.
3. GitLab fixture creates a `gitlab.mr.comment` action requiring approval.
4. No skill function can execute external writeback.
5. GitLab metadata, pipeline, and discussions evidence are visible before review generation.
6. A forced action insert failure rolls back the whole source bundle.
7. A no-op replay preserves an edited approval and payload hash.
8. A material replay refreshes the same action id and invalidates the old approval hash.
9. Generic no-approval or mismatched-target skill actions are rejected.

## Acceptance

```bash
cd core && dune build && dune runtest
pharos replay examples/gitlab_mr_signal.json
pharos detail <request-id>
```

Expected: detail shows a prepared GitLab review next move with evidence.
