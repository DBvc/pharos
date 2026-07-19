type capture_input = {
  title : string option;
  body : string;
  url : string option;
  actor : string option;
}

type source_signal_input = {
  kind : Domain.source_kind;
  external_id : string option;
  actor : string;
  title : string;
  body : string;
  url : string option;
  occurred_at : string;
  raw_json : string option;
}

type source_signal_response = {
  request : Domain.work_request;
  merged : bool;
  detail_url : string;
}

type evidence_input = {
  kind : string;
  title : string;
  body : string;
  url : string option;
}

val capture_input_of_json : Yojson.Safe.t -> (capture_input, string) result
val source_signal_input_of_json : Yojson.Safe.t -> (source_signal_input, string) result
val source_signal_response_to_yojson : source_signal_response -> Yojson.Safe.t

val capture_manual : Store.t -> capture_input -> Domain.work_request

val ingest_source_signal :
  ?evidence:evidence_input list ->
  ?managed_evidence_kinds:string list ->
  Store.t ->
  source_signal_input ->
  source_signal_response

val apply_gitlab_mr_review_output_json :
  Store.t ->
  request:Domain.work_request ->
  Yojson.Safe.t ->
  Domain.proposed_action option

val get_detail : Store.t -> string -> Domain.request_detail option
val today : Store.t -> Domain.today_decision_snapshot
val today_internal : Store.t -> Domain.today_snapshot

val approve :
  ?edited_body:string ->
  expected_payload_hash:string ->
  Store.t ->
  string ->
  (Domain.approval, Policy.policy_error) result

val reject :
  expected_payload_hash:string ->
  Store.t ->
  string ->
  (Domain.approval, Policy.policy_error) result

val execute_local :
  Store.t ->
  string ->
  (Domain.proposed_action, Policy.policy_error) result

val start_writeback :
  Store.t -> string -> (Policy.writeback_operation, Policy.policy_error) result

val writeback_request : Policy.writeback_operation -> Gitlab_write.request

val finish_writeback :
  Store.t ->
  Policy.writeback_operation ->
  Gitlab_write.delivery_outcome ->
  ((Domain.proposed_action * Domain.writeback_attempt), Policy.policy_error)
  result

val execute_approved :
  client:Gitlab_write.client ->
  Store.t ->
  string ->
  ((Domain.proposed_action * Domain.writeback_attempt), Policy.policy_error)
  result

val prepare_reconciliation :
  Store.t -> string -> (Policy.writeback_operation, Policy.policy_error) result

val finish_reconciliation :
  Store.t ->
  Policy.writeback_operation ->
  Gitlab_write.reconciliation_outcome ->
  ((Domain.proposed_action * Domain.writeback_attempt), Policy.policy_error)
  result

val reconcile_writeback :
  client:Gitlab_write.client ->
  Store.t ->
  string ->
  ((Domain.proposed_action * Domain.writeback_attempt), Policy.policy_error)
  result

val abandon_writeback :
  Store.t ->
  string ->
  ((Domain.proposed_action * Domain.writeback_attempt), Policy.policy_error)
  result

val recover_interrupted_writebacks : Store.t -> unit
