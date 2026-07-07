# Iteration Plan

## Milestone 0: Core shell and local request model

Goal: prove the unified workflow without external sources.

### Scope

- SwiftUI macOS shell.
- OCaml daemon and CLI.
- SQLite persistence.
- Manual capture.
- Work request state flow.
- Request detail.
- Local Review Gate.
- Evidence and timeline.

### Starter status

Included in this repo:

- Domain types.
- SQLite migrations.
- Manual capture path.
- Generated local action.
- Approve, edit and approve, reject.
- Policy hash check.
- Execute approved local action.
- SwiftUI shell and API client.

### Done criteria

- Manual capture is visible in Today within 3 seconds.
- The app shows request summary, reason, evidence, timeline, and proposed action.
- Approve executes the local action and marks the request done.
- Edit and approve executes the edited body.
- Reject does not execute the action.
- Restarting keeps requests, actions, approvals, evidence, and timeline.

## Milestone 1: Four source minimum read paths

Goal: real work signals enter Pharos.

### Scope

- Feishu Chat read adapter.
- Feishu Project read adapter.
- GitLab read adapter.
- Feishu Docs read adapter.
- Source settings page.
- Per-source sync status and failure isolation.

### Recommended order

1. GitLab MR read adapter.
2. Feishu Chat read adapter.
3. Feishu Project read adapter.
4. Feishu Docs read adapter.

GitLab MR has clearer shape and is useful for validating evidence, timeline, and review draft quality. Feishu Chat is likely the highest-volume source and should follow quickly.

### Done criteria

- Each source can produce at least one test `SourceSignal`.
- Source failure is visible but does not crash the daemon.
- Every request shows source link and entry reason.
- Repeated events update the same active request when identity matches.

## Milestone 2: Triage, merge, context, and skills

Goal: Pharos becomes a working cockpit rather than a passive inbox.

### Scope

- Request identity and merge logic.
- Triage rules plus model-assisted classification.
- Bounded context bundle.
- Built-in skills.
- Draft generation.
- Evidence references.
- Needs Context flow.

### Built-in skills

1. `triage_skill`.
2. `context_summary_skill`.
3. `draft_reply_skill`.
4. `gitlab_mr_review_skill`.
5. `project_next_step_skill`.
6. `doc_understanding_skill`.

### Done criteria

- At least 3 request types automatically reach summary, draft, or suggested action stage.
- Ready for Review requests contain enough evidence for most decisions.
- Skill failures are visible and retryable.
- User can request more context and trigger a new run.

## Milestone 3: Controlled writeback

Goal: close the loop after review.

### Scope

- Feishu Chat reply writeback.
- GitLab comment writeback.
- Feishu Project comment writeback.
- Feishu Docs comment writeback.
- Approval hash verification.
- Writeback result evidence.

### Recommended order

1. GitLab MR or Issue comment.
2. Feishu Chat reply.
3. Feishu Project comment.
4. Feishu Docs comment.

### Done criteria

- At least 2 external writebacks work after approval.
- Unapproved writeback attempts are blocked and logged.
- Edit and approve writes the edited payload.
- Timeline shows approval, target, content hash, adapter result, and external URL.
- L4 and L5 actions are suggestion-only.

## Milestone 4: Dogfood metrics and convergence

Goal: determine whether the MVP is useful enough to keep expanding.

### Scope

- Metrics page.
- 7-day local trends.
- JSON and Markdown export.
- False positive and false negative feedback.
- Daily subjective review template.

### Done criteria

- 10 workday dogfood is possible.
- Average daily valid requests >= 5.
- Week 2 junk request ratio <= 20%.
- At least 3 request classes auto-advance reliably.
- Unapproved external write count remains 0.

## Near-term Codex loop

Use Codex in small vertical cuts:

1. Compile the OCaml starter and fix any dependency drift.
2. Run M0 manual capture from CLI and HTTP.
3. Improve SwiftUI loading and error states.
4. Add request detail action editing.
5. Add a fake adapter that replays JSON examples.
6. Add adapter identity and merge tests.
7. Add metrics aggregation for manual requests.
8. Package `pharosd` into the app bundle.
