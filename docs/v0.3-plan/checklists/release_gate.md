# v0.3 Release Gate

A v0.3 alignment release is acceptable when all items are true.

## Product alignment

- [ ] Tasks 01-03 were completed as one v0.3 Today alignment release batch.
- [ ] README names docs source of truth.
- [ ] `docs/PRD_v0.3.md` exists.
- [ ] `docs/USER_EXPERIENCE.md` and `docs/PRD_v0.3.md` agree on Today groups.
- [ ] `docs/API.md` and `protocol/openapi.yaml` agree on `/v0/today`.
- [ ] `docs/ITERATION_PLAN.md` puts merge identity before real high-volume sources.

## API

- [ ] `/v0/today` returns `needs_decision`, `needs_input`, `watching`, `handled`, `noise`.
- [ ] Old lifecycle buckets are not top-level fields on `/v0/today`.
- [ ] Optional `/v0/debug/today-internal` is not consumed by Swift.

## Core

- [ ] Internal request statuses still exist.
- [ ] DecisionCard mapping lives in OCaml.
- [ ] Manual capture appears under Needs Decision.
- [ ] Done request appears under Handled.
- [ ] Archived request increments Noise count.

## Swift

- [ ] Today uses `DecisionCard`.
- [ ] Request Detail still loads full `RequestDetail`.
- [ ] Request Detail is organized by user judgment questions.

## Safety

- [ ] No approval means no external write.
- [ ] Edit-and-approve executes edited content.
- [ ] L4/L5 cannot execute.
- [ ] Blocked attempts are visible.
- [ ] GitLab writeback verifies target provenance before calling the GitLab write client.
- [ ] Tokens/secrets are not logged or exported.

## Source identity

- [ ] Merge identity uses stable external ids before URL fallback.
- [ ] Mutable title/subject is not part of the primary identity key when `external_id` exists.
- [ ] Replaying a changed-title event with the same stable external id does not create a duplicate active request.

## Metrics

- [ ] Today group metrics are daily snapshot/gauge values, not `/v0/today` refresh counters.
