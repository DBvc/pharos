# Dogfood Plan

## Goal

Determine whether Pharos reduces context switching and missed work without creating a new babysitting chore.

Dogfood should test the user experience in `docs/USER_EXPERIENCE.md`: Today is a decision cockpit, not a new inbox. The main question is whether Pharos creates fewer, clearer user decisions instead of another place to manage statuses.

## Before MVP dogfood

For 3 workdays, manually record:

```text
Date:
Feishu chat checks:
Feishu project checks:
GitLab checks:
Feishu docs checks:
Important @ or review requests:
Missed or delayed important items:
Estimated time spent finding context:
Notes:
```

## 10-day dogfood

Use Pharos every workday. At end of day, answer:

```text
Date:
Did Pharos reduce system-scanning or context-hunting? 0-5
Did Pharos help avoid missed work? 0-5
Did Pharos create extra burden? 0-5
Did Needs Decision contain clear decisions rather than status noise? 0-5
Most valuable request today:
Most annoying or useless request today:
One thing to improve tomorrow:
```

## Automatic metrics

Track locally:

- Source signals.
- Work requests.
- Today entries by user-facing group.
- Needs Decision entries.
- Needs Input entries.
- Ready for Review entries as the internal state behind reviewable decisions.
- Auto-advanced requests.
- Approvals.
- Edit approvals.
- Rejects.
- False positives.
- Archived requests.
- External writes.
- Blocked unapproved writes.
- Time from signal to request.
- Time from request to Ready for Review.

## Continue criteria

Continue investing if:

1. Used every workday for 10 days.
2. Average valid requests per day >= 5.
3. At least 3 request types auto-advance reliably.
4. Week 2 junk ratio <= 20%.
5. Blocked or successful unapproved external writes do not occur in normal flow.
6. Subjective reduction in context switching averages >= 4/5.
7. Needs Decision clarity averages >= 4/5 without increasing babysitting.

## Scope reduction criteria

Reduce scope if:

1. Average valid requests per day < 3.
2. Junk ratio > 40% for several days.
3. Review evidence is too weak and external systems still need to be opened from zero.
4. Source integration upkeep costs more than saved time.
5. Writeback safety cannot be proven with tests.
