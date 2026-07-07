# Project Risks

## Technical risks

### SwiftUI app packaging with OCaml daemon

Risk: packaging and supervising an OCaml binary inside a SwiftUI app may take more iteration than expected.

Mitigation: run daemon separately for M0, then package once the API stabilizes.

### Feishu API complexity

Risk: Feishu Chat, Project, and Docs may each require different auth, event, and comment APIs.

Mitigation: start with read-only polling or fixture replay. Add writeback only after one read path is stable.

### Triage quality

Risk: noisy sources can turn Pharos into a second inbox.

Mitigation: rules first, user feedback visible, source scopes tight, junk ratio metric in dogfood.

### Approval bypass regression

Risk: future adapter or UI code accidentally writes externally.

Mitigation: tests around policy gate, no direct adapter write routes from UI, code review checklist.

## Product risks

### Not enough valuable requests

Mitigation: dogfood continuation criteria. If average valid requests < 3 per day, narrow to GitLab MR and Feishu @ only.

### Evidence not useful enough

Mitigation: require evidence before Ready for Review, measure Review可判断率, improve context bundle before adding more sources.

### Too much babysitting

Mitigation: keep M0 focused, add source scopes, make false-positive actions one-click, prefer fewer high-confidence cards.
