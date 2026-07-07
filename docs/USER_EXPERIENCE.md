# Pharos User Experience

Status: product/UX source of truth for aligning docs and future UI.

Pharos watches work systems, prepares the next move, and asks before it acts.

In Chinese:

```text
Pharos 帮你看住工作系统，整理证据、准备下一步；真正行动前一定问你。
```

## User Mental Model

The user-facing loop is:

```text
看住信号 -> 整理证据 -> 准备动作 -> 等我拍板 -> 执行留痕
```

This is the product surface. The internal implementation can use richer state machines, risk levels, hashes, and audit records, but the user should not need to understand those concepts to use Pharos.

The user should feel:

1. Pharos is watching the right work systems.
2. Pharos filters scattered signals into a small number of meaningful decisions.
3. Pharos explains why something matters before asking for attention.
4. Pharos prepares a concrete next move, not just another reminder.
5. Pharos will not write externally without approval.
6. Pharos leaves enough evidence to review, trust, and correct the process.

## Daily Use

Pharos should not become another inbox.

The normal day should look like this:

1. Pharos runs in the background.
2. The user continues working in Feishu, GitLab, documents, code, and other tools.
3. Pharos quietly watches configured sources and quick captures.
4. When a signal seems actionable, Pharos turns it into a small decision card.
5. When enough evidence exists, Pharos prepares the next move.
6. The user opens Today only to make decisions, provide missing input, or check what was handled.

The default user action is not "manage tasks." The default action is:

```text
approve, edit, reject, ask for more context, or archive as noise
```

## When Pharos May Interrupt

Pharos should interrupt only when attention changes the outcome.

Allowed interruption reasons:

- A high-priority or blocking work signal needs the user's attention.
- A prepared action is waiting for the user's decision.
- Pharos cannot continue without missing context, permission, or scope.
- A source or skill failed in a way that blocks important work.

Not enough to interrupt:

- A source produced a new raw event.
- A low-confidence signal exists but has no prepared next step.
- Pharos is still gathering routine context.
- A completed low-risk local action only needs passive logging.

## Today

Today answers:

```text
What needs my attention now?
```

It should be grouped by required user attention, not by the full internal lifecycle.

Recommended user-facing groups:

| User-facing group | User question | Internal examples |
|---|---|---|
| Needs Decision | Do I approve, edit, reject, or archive this? | `ReadyForReview`, reviewable `ProposedAction` |
| Needs Input | What does Pharos need from me to continue? | `NeedsContext`, failed context fetch, missing permission |
| Watching | What is Pharos still preparing or monitoring? | `New`, `Triaging`, `Running`, `Waiting` |
| Handled | What did Pharos finish today? | `Done`, executed local or external action |
| Noise | What was filtered or archived? | `Archived`, false positive, ignored signal |

The internal names can remain in the core, API, metrics, and audit logs. The main UI should prefer user-facing groups unless the user opens a detail or diagnostic surface.

## Request Detail

Request Detail answers four questions in order:

1. What is this?
2. Why did Pharos bring it to me?
3. What evidence did Pharos use?
4. What exactly will happen if I approve?

The detail view should prioritize judgment over completeness. A user should be able to decide most low- and medium-complexity requests without opening the original system from zero.

Minimum visible information before asking for approval:

- Source system and source link.
- Plain-language summary.
- Entry reason: why this became a Pharos request.
- Relevant evidence and context.
- Prepared action body or draft.
- Target system and target object.
- Whether the action writes externally.
- Risk language in human terms.
- Available choices: approve, edit and approve, reject, request more context, snooze, archive.

## Review Gate

Review Gate is not just an Approve button. It is the moment where control returns to the user.

The Review Gate must make three things clear:

```text
what Pharos will do
where Pharos will do it
why this action is justified
```

User actions:

- Approve: execute the prepared action as shown.
- Edit and Approve: execute the edited action, not the original draft.
- Reject: do not execute this action.
- Request More Context: ask Pharos to gather or wait for more information.
- Snooze: defer the decision.
- Archive: remove this as not worth action.
- Mark False Positive: teach Pharos that this should not have become a request.
- Disable Similar Automation: stop a class of future automation when trust is low.

External writes must remain review-gated. The UI may use friendly language, but the core must keep approval, payload hash, evidence, and timeline records.

## Quick Capture

Quick Capture is a supplemental path, not the main product loop.

Use it when:

- The source adapter has not captured something yet.
- The user sees a message, link, MR, project item, or idea that should enter Pharos.
- The user wants Pharos to prepare a follow-up from a small piece of context.

Captured items should go through the same product loop:

```text
capture -> evidence -> prepared next move -> user decision -> execution record
```

M0 currently demonstrates this path with manual capture and local execution only. Real Feishu/GitLab adapters, model-powered drafting, and external writeback are future MVP work, not current starter behavior.

## Trust Rules

Trust is the product.

Pharos should keep these promises:

- It will not silently write externally.
- It will show enough evidence before asking for approval.
- It will make the target of an action clear.
- It will execute edited content when the user edits and approves.
- It will record what happened after execution.
- It will make failures visible without crashing unrelated sources.
- It will make it easy to reject noise.

## Internal Model Boundary

The core can and should keep precise internal concepts:

- `SourceSignal`
- `WorkRequest`
- `Evidence`
- `ProposedAction`
- `Approval`
- `Timeline`
- risk levels
- payload hashes
- request and action statuses

Those concepts are implementation and audit tools. They should appear in architecture, API, debugging, metrics, and security documentation. They should not be the primary mental model for ordinary daily use.

Suggested mapping:

| User concept | Core concept |
|---|---|
| Signal Pharos watched | `SourceSignal` |
| Decision card | `WorkRequest` plus current review state |
| Evidence Pharos used | `Evidence` and context bundle |
| Prepared next move | `ProposedAction` |
| User decision | `Approval` or rejection decision |
| Execution record | `Timeline` and action status |
| Safety level | risk level and policy gate |
| "Ask before acting" | approval hash verification before execution |

## Current Starter Boundary

The current starter slice proves the loop in miniature:

```text
manual capture -> local request -> evidence -> proposed local action -> approve/edit/reject -> policy-checked local execution -> timeline
```

It does not yet include:

- real Feishu read adapters;
- real GitLab read adapters;
- model calls;
- external writeback;
- full source settings;
- full rules learning;
- packaged daemon supervision.

Future docs and UI should preserve this distinction: describe the intended user experience clearly, but do not present future source integrations as already implemented.
