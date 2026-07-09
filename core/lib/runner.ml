open Domain

type capture_input = {
  title : string option;
  body : string;
  url : string option;
  actor : string option;
}

type source_signal_input = {
  kind : source_kind;
  external_id : string option;
  actor : string;
  title : string;
  body : string;
  url : string option;
  occurred_at : string;
  raw_json : string option;
}

type source_signal_response = {
  request : work_request;
  merged : bool;
  detail_url : string;
}

let capture_input_of_json json =
  match Json_util.required_string "body" json with
  | Error e -> Error e
  | Ok body ->
      Ok {
        title = Json_util.optional_string "title" json;
        body;
        url = Json_util.optional_string "url" json;
        actor = Json_util.optional_string "actor" json;
      }

let optional_member_as_raw_json name json =
  match Yojson.Safe.Util.member name json with
  | `Null -> None
  | `String s -> Some s
  | raw -> Some (Yojson.Safe.to_string raw)

let normalize_optional_text = function
  | None -> None
  | Some value ->
      let trimmed = String.trim value in
      if trimmed = "" then None else Some trimmed

let optional_non_empty_string name json =
  Json_util.optional_string name json |> normalize_optional_text

let source_signal_input_of_json json =
  let kind_string =
    match Json_util.member_string "kind" json with
    | Some value -> Some value
    | None -> Json_util.member_string "source_kind" json
  in
  match kind_string with
  | None -> Error "Missing required string field: kind"
  | Some kind ->
      match Json_util.required_string "actor" json with
      | Error e -> Error e
      | Ok actor ->
          match Json_util.required_string "title" json with
          | Error e -> Error e
          | Ok title ->
              match Json_util.required_string "body" json with
              | Error e -> Error e
              | Ok body ->
                  match Json_util.required_string "occurred_at" json with
                  | Error e -> Error e
                  | Ok occurred_at ->
                      let raw_json =
                        match optional_member_as_raw_json "raw_json" json with
                        | Some value -> Some value
                        | None -> optional_member_as_raw_json "raw" json
                      in
                      Ok {
                        kind = source_kind_of_string kind;
                        external_id = optional_non_empty_string "external_id" json;
                        actor;
                        title;
                        body;
                        url = optional_non_empty_string "url" json;
                        occurred_at;
                        raw_json;
                      }

let timeline ~request_id ~kind ~title ~body =
  {
    id = Ids.create "evt";
    request_id;
    kind;
    title;
    body;
    created_at = Time.now_iso ();
  }

let is_tracking_query key =
  let key = String.lowercase_ascii key in
  String.starts_with ~prefix:"utm_" key
  || key = "fbclid"
  || key = "gclid"
  || key = "mc_cid"
  || key = "mc_eid"

let canonicalize_url url =
  let trimmed = String.trim url in
  let trim_trailing_slash value =
    let len = String.length value in
    if len > 1 && value.[len - 1] = '/' then String.sub value 0 (len - 1)
    else value
  in
  match String.split_on_char '?' trimmed with
  | [ base ] -> trim_trailing_slash base
  | [ base; query ] ->
      let base = trim_trailing_slash base in
      let kept =
        query
        |> String.split_on_char '&'
        |> List.filter (fun part ->
          match String.split_on_char '=' part with
          | key :: _ -> not (is_tracking_query key)
          | [] -> false)
      in
      if kept = [] then base else base ^ "?" ^ String.concat "&" kept
  | _ -> trimmed

let is_subject_boundary = function
  | ' ' | '\t' | '\n' | '\r' -> true
  | _ -> false

let normalize_whitespace value =
  let buffer = Buffer.create (String.length value) in
  let rec loop index previous_space =
    if index >= String.length value then ()
    else
      let ch = value.[index] in
      if is_subject_boundary ch then begin
        if not previous_space then Buffer.add_char buffer ' ';
        loop (index + 1) true
      end else begin
        Buffer.add_char buffer ch;
        loop (index + 1) false
      end
  in
  loop 0 true;
  Buffer.contents buffer |> String.trim

let is_trim_punctuation = function
  | '.' | ',' | '!' | '?' | ':' | ';' | '#' | '[' | ']' | '(' | ')' | '{' | '}' -> true
  | _ -> false

let trim_subject_punctuation value =
  let len = String.length value in
  let rec first index =
    if index >= len then len
    else if is_trim_punctuation value.[index] then first (index + 1)
    else index
  in
  let rec last index =
    if index < 0 then -1
    else if is_trim_punctuation value.[index] then last (index - 1)
    else index
  in
  let start = first 0 in
  let stop = last (len - 1) in
  if stop < start then "" else String.sub value start (stop - start + 1)

let truncate max_len value =
  if String.length value <= max_len then value else String.sub value 0 max_len

let normalized_subject title =
  title
  |> String.lowercase_ascii
  |> String.trim
  |> normalize_whitespace
  |> trim_subject_punctuation
  |> truncate 120

let source_signal_from_input (input : source_signal_input) : source_signal =
  {
    id = Ids.create "sig";
    kind = input.kind;
    external_id = normalize_optional_text input.external_id;
    actor = input.actor;
    title = input.title;
    body = input.body;
    url = normalize_optional_text input.url;
    occurred_at = input.occurred_at;
    raw_json = input.raw_json;
  }

let identity_parts (signal : source_signal) =
  let source_kind = source_kind_to_string signal.kind in
  let external_key, stable =
    match signal.external_id with
    | Some value -> (value, true)
    | None ->
        begin match signal.url with
        | Some url -> (canonicalize_url url, true)
        | None -> (signal.id, false)
        end
  in
  let normalized_subject = normalized_subject signal.title in
  let identity_key =
    if stable then source_kind ^ ":" ^ external_key
    else source_kind ^ ":" ^ external_key ^ ":" ^ normalized_subject
  in
  (identity_key, external_key, normalized_subject)

let source_summary (signal : source_signal) =
  "Updated from " ^ source_kind_to_string signal.kind ^ " signal: " ^ signal.title

let local_source_action_body (signal : source_signal) =
  "Review source signal: " ^ signal.title ^ "\n\n" ^ signal.body

let make_source_request (signal : source_signal) =
  let now = Time.now_iso () in
  {
    id = Ids.create "req";
    title = signal.title;
    summary = Triage.request_summary signal.body;
    status = ReadyForReview;
    priority = Normal;
    risk = L2;
    source_kind = signal.kind;
    source_signal_id = signal.id;
    reason = "Source signal from " ^ source_kind_to_string signal.kind ^ " by " ^ signal.actor;
    next_step = "Review the source signal and complete it locally if no follow-up is needed.";
    created_at = now;
    updated_at = now;
  }

let make_source_action (request : work_request) (signal : source_signal) =
  let now = Time.now_iso () in
  let target_kind = "pharos.local.complete_request" in
  let target_ref = request.id in
  let risk = L2 in
  let body = local_source_action_body signal in
  {
    id = Ids.create "act";
    request_id = request.id;
    title = "Acknowledge and complete source signal locally";
    body;
    target_kind;
    target_ref;
    risk;
    requires_approval = true;
    status = ActionProposed;
    payload_hash = payload_hash ~target_kind ~target_ref ~risk ~body;
    created_at = now;
    updated_at = now;
  }

let make_source_evidence ~kind ~title (signal : source_signal) request_id =
  {
    id = Ids.create "ev";
    request_id;
    kind;
    title;
    body = signal.body;
    url = signal.url;
    created_at = Time.now_iso ();
  }

let bind_identity store ~request_id (signal : source_signal) =
  let identity_key, external_key, normalized_subject = identity_parts signal in
  let now = Time.now_iso () in
  Store.upsert_work_request_identity store {
    identity_key;
    request_id;
    source_kind = signal.kind;
    external_key;
    normalized_subject;
    created_at = now;
    updated_at = now;
  };
  identity_key

let capture_manual store (input : capture_input) =
  let now = Time.now_iso () in
  let title = Triage.title_from_capture ~title:input.title ~body:input.body in
  let signal = {
    id = Ids.create "sig";
    kind = Manual;
    external_id = None;
    actor = Option.value input.actor ~default:"manual";
    title;
    body = input.body;
    url = input.url;
    occurred_at = now;
    raw_json = None;
  } in
  let request = {
    id = Ids.create "req";
    title;
    summary = Triage.request_summary input.body;
    status = ReadyForReview;
    priority = Triage.classify_manual ~body:input.body;
    risk = L2;
    source_kind = Manual;
    source_signal_id = signal.id;
    reason = Triage.entry_reason;
    next_step = Triage.next_step;
    created_at = now;
    updated_at = now;
  } in
  let action_body = Triage.local_action_body input.body in
  let target_kind = "pharos.local.complete_request" in
  let target_ref = request.id in
  let risk = L2 in
  let action = {
    id = Ids.create "act";
    request_id = request.id;
    title = "Acknowledge and complete locally";
    body = action_body;
    target_kind;
    target_ref;
    risk;
    requires_approval = true;
    status = ActionProposed;
    payload_hash = payload_hash ~target_kind ~target_ref ~risk ~body:action_body;
    created_at = now;
    updated_at = now;
  } in
  let evidence = {
    id = Ids.create "ev";
    request_id = request.id;
    kind = "source.manual_capture";
    title = "Manual capture";
    body = input.body;
    url = input.url;
    created_at = now;
  } in
  Store.insert_source_signal store signal;
  Store.insert_work_request store request;
  Store.insert_evidence store evidence;
  Store.insert_action store action;
  Store.insert_timeline store (timeline ~request_id:request.id ~kind:"capture" ~title:"Manual signal captured" ~body:("Source signal " ^ signal.id));
  Store.insert_timeline store (timeline ~request_id:request.id ~kind:"triage" ~title:"Request created" ~body:request.reason);
  Store.insert_timeline store (timeline ~request_id:request.id ~kind:"action" ~title:"Proposed local action" ~body:("Action " ^ action.id ^ " requires review in starter flow"));
  Store.bump_metric store "source_signals";
  Store.bump_metric store "work_requests";
  Store.bump_metric store "ready_for_review";
  request

let create_request_from_source_signal store (signal : source_signal) =
  let request = make_source_request signal in
  let action = make_source_action request signal in
  Store.insert_work_request store request;
  Store.insert_evidence store
    (make_source_evidence ~kind:("source." ^ source_kind_to_string signal.kind)
      ~title:"Source signal" signal request.id);
  Store.insert_action store action;
  let identity_key = bind_identity store ~request_id:request.id signal in
  Store.insert_timeline store
    (timeline ~request_id:request.id ~kind:"capture" ~title:"Source signal captured"
      ~body:("signal_id=" ^ signal.id ^ "; identity_key=" ^ identity_key));
  Store.insert_timeline store
    (timeline ~request_id:request.id ~kind:"action" ~title:"Proposed local source action"
      ~body:("Action " ^ action.id ^ " requires review in starter flow"));
  Store.bump_metric store "work_requests";
  Store.bump_metric store "ready_for_review";
  request

let merge_source_signal_into_request store (signal : source_signal) identity_key
    (request : work_request) =
  let summary = source_summary signal in
  Store.update_work_request_from_source_signal store ~request_id:request.id
    ~title:signal.title ~summary ~source_signal_id:signal.id;
  ignore (bind_identity store ~request_id:request.id signal);
  Store.insert_evidence store
    (make_source_evidence ~kind:"source.update" ~title:"Source signal update"
      signal request.id);
  Store.insert_timeline store
    (timeline ~request_id:request.id ~kind:"merge"
      ~title:"Source signal merged into existing request"
      ~body:("signal_id=" ^ signal.id ^ "; identity_key=" ^ identity_key));
  match Store.get_work_request store request.id with
  | Some updated -> updated
  | None -> request

let ingest_source_signal store (input : source_signal_input) =
  let signal = source_signal_from_input input in
  Store.insert_source_signal store signal;
  Store.bump_metric store "source_signals";
  let identity_key, _, _ = identity_parts signal in
  let request, merged =
    match Store.get_work_request_identity store identity_key with
    | Some identity ->
        begin match Store.get_work_request store identity.request_id with
        | Some request when request.status <> Done && request.status <> Archived ->
            (merge_source_signal_into_request store signal identity_key request, true)
        | _ -> (create_request_from_source_signal store signal, false)
        end
    | None -> (create_request_from_source_signal store signal, false)
  in
  {
    request;
    merged;
    detail_url = "/v0/requests/" ^ request.id;
  }

let source_signal_response_to_yojson (response : source_signal_response) =
  Json_util.assoc [
    ("request", Json_util.assoc [ Json_util.str "id" response.request.id ]);
    Json_util.bool "merged" response.merged;
    Json_util.str "detail_url" response.detail_url;
  ]

let get_detail = Store.request_detail
let today = Store.today_decision
let today_internal = Store.today_internal
let approve = Policy.approve
let reject = Policy.reject
let execute_local = Policy.execute_local
