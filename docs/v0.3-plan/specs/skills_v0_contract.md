# Built-in Skills v0 Contract

Apply in task 09.

## Goal

Pharos should stop being a passive catcher and start preparing useful next moves. Skills must produce typed outputs with evidence references and never execute external writes.

## Files to edit

```text
core/lib/skill.ml
core/lib/triage.ml
core/lib/runner.ml
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

## Parser rule

Every skill output must be parsed and validated before it can create a `ProposedAction`.

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

## Tests

1. Valid triage skill output parses.
2. Invalid priority/risk is rejected.
3. GitLab fixture creates a `gitlab.mr.comment` action requiring approval.
4. No skill function can execute external writeback.

## Acceptance

```bash
cd core && dune build && dune runtest
pharos replay examples/gitlab_mr_signal.json
pharos detail <request-id>
```

Expected: detail shows a prepared GitLab review next move with evidence.
