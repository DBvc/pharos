# OCaml Implementation Contract for v0.3 Today

Apply in task 02.

## Files to edit

```text
core/lib/domain.ml
core/lib/store.ml
core/lib/runner.ml
core/bin/daemon/main.ml
core/bin/cli/main.ml
protocol/openapi.yaml
docs/API.md
```

## Domain additions

Add these types to `core/lib/domain.ml` without removing existing types:

```ocaml
type attention_group =
  | NeedsDecision
  | NeedsInput
  | Watching
  | Handled
  | Noise

type decision_card = {
  request_id : string;
  title : string;
  summary : string;
  group : attention_group;
  source_kind : source_kind;
  source_url : string option;
  priority : priority;
  risk : risk;
  why_now : string;
  prepared_next_move : string option;
  target_preview : string option;
  evidence_count : int;
  updated_at : string;
  debug_status : request_status;
}

type noise_summary = { count : int }

type today_decision_snapshot = {
  needs_decision : decision_card list;
  needs_input : decision_card list;
  watching : decision_card list;
  handled : decision_card list;
  noise : noise_summary;
}
```

Add converters:

```ocaml
val attention_group_to_string : attention_group -> string
val attention_group_of_status : request_status -> attention_group
val decision_card_to_yojson : decision_card -> Yojson.Safe.t
val noise_summary_to_yojson : noise_summary -> Yojson.Safe.t
val today_decision_snapshot_to_yojson : today_decision_snapshot -> Yojson.Safe.t
```

Required string values:

```text
NeedsDecision -> needs_decision
NeedsInput    -> needs_input
Watching      -> watching
Handled       -> handled
Noise         -> noise
```

Keep the existing `today_snapshot` and `today_snapshot_to_yojson` only if adding `/v0/debug/today-internal`. Do not make Swift consume them.

## Store additions

Add helpers in `core/lib/store.ml`:

```ocaml
val get_source_signal : t -> string -> source_signal option
val list_actions_by_request : t -> string -> proposed_action list  (* already exists; reuse it *)
val count_evidence_by_request : t -> string -> int
val latest_action_by_request : t -> string -> proposed_action option
val has_reviewable_action : t -> string -> bool
val today_decision : t -> today_decision_snapshot
val today_internal : t -> today_snapshot  (* optional alias for old today *)
```

Implementation rules:

1. `get_source_signal` selects by `source_signals.id`.
2. `count_evidence_by_request` counts rows in `evidence_items`.
3. `latest_action_by_request` orders by `updated_at DESC, created_at DESC LIMIT 1`.
4. `has_reviewable_action` returns true when any action for the request has `status = ActionProposed`.
5. `source_url` in `DecisionCard` comes from `SourceSignal.url` when found, else null.
6. `prepared_next_move` comes from latest action title if action exists, otherwise `WorkRequest.next_step` if non-empty, otherwise null.
7. `target_preview` is `target_kind ^ " / " ^ target_ref` for latest action, else null.
8. `debug_status` is the raw internal `request_status`.

## Mapping function

Implement a function equivalent to:

```ocaml
let group_for_request store request =
  match request.status with
  | ReadyForReview ->
      if has_reviewable_action store request.id then NeedsDecision else NeedsInput
  | NeedsContext | Failed -> NeedsInput
  | New | Triaging | Running | Waiting | Approved | Executing | Snoozed -> Watching
  | Done -> Handled
  | Archived -> Noise
```

Do not implement this mapping in Swift.

## Sorting

Sort each card list by:

1. priority rank: Urgent = 0, High = 1, Normal = 2, Low = 3.
2. `updated_at` descending.

If date parsing is not implemented, string descending is acceptable for ISO timestamps.

## Runner changes

Change:

```ocaml
let today = Store.today
```

to:

```ocaml
let today = Store.today_decision
let today_internal = Store.today_internal   (* optional *)
```

## Daemon changes

Change `/v0/today` to:

```ocaml
Dream.get "/v0/today" (fun _ -> json (Domain.today_decision_snapshot_to_yojson (Runner.today store)))
```

Optional debug route:

```ocaml
Dream.get "/v0/debug/today-internal" (fun _ -> json (Domain.today_snapshot_to_yojson (Runner.today_internal store)))
```

## CLI changes

`pharos today` must print the new v0.3 snapshot.

Optional command:

```text
pharos today-internal
```

may print old buckets.

## Tests required

Add or update OCaml tests so these assertions pass:

1. Manual capture appears in `needs_decision` because starter creates a `ReadyForReview` request with a proposed action.
2. After approve and execute-local, the same request appears in `handled`.
3. Archived request increments `noise.count` and does not appear in `needs_decision`.
4. `DecisionCard.debug_status` remains the internal status string.

## Acceptance

```bash
cd core && dune build
cd core && dune runtest
PHAROS_DB=../var/pharos.dev.sqlite dune exec pharos -- capture "test v0.3 today"
PHAROS_DB=../var/pharos.dev.sqlite dune exec pharos -- today | jq '.needs_decision[0].request_id'
```

Expected: `.needs_decision[0].request_id` is a string.
