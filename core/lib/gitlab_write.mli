type object_kind = MergeRequest | Issue

type target = {
  project_id : int;
  object_kind : object_kind;
  iid : int;
}

type post_result = {
  external_id : string;
  external_url : string;
}

type request = {
  target : target;
  source_url : string option;
  body : string;
  marker : string;
}

type delivery_outcome =
  | Confirmed of post_result
  | Failed_before_send of string
  | Unknown of string

type reconciliation_outcome =
  | Reconciled of post_result
  | Marker_not_found
  | Reconciliation_unknown of string

type client = {
  post : request -> delivery_outcome;
  reconcile : request -> reconciliation_outcome;
}

val parse_target : string -> string -> (target, string) result
val parse_source_external_id : string -> (target, string) result
val target_matches_source : target -> target -> bool
val marker : attempt_id:string -> payload_hash:string -> (string, string) result
val body_with_marker : body:string -> marker:string -> string
val marker_is_exact_line : string -> string -> bool
val fallback_external_url :
  base_url:string ->
  target:target ->
  source_url:string option ->
  note_id:string ->
  string
val real_client : client
