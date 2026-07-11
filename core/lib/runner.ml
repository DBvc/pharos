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

type evidence_input = {
  kind : string;
  title : string;
  body : string;
  url : string option;
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

let make_source_request (signal : source_signal) =
  let now = Time.now_iso () in
  {
    id = Ids.create "req";
    title = signal.title;
    summary = source_summary signal;
    status = Triaging;
    priority = Normal;
    risk = L2;
    source_kind = signal.kind;
    source_signal_id = signal.id;
    reason = "Source signal from " ^ source_kind_to_string signal.kind ^ " by " ^ signal.actor;
    next_step = "Prepare a validated next move from the captured evidence.";
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

type builtin_action_kind =
  | LocalNextMove
  | FeishuReply of string
  | GitlabMrComment of string

type generation_state = {
  skill_id : string;
  context_hash : string;
  generated_payload_hash : string;
  action_id : string;
  evidence_refs : string list;
}

let skill_id_of_kind = function
  | LocalNextMove -> "context_summary_skill"
  | FeishuReply _ -> "draft_reply_skill"
  | GitlabMrComment _ -> "gitlab_mr_review_skill"

let evidence_ref_ids (output : Skill.proposed_output) =
  output.evidence_refs
  |> List.map (fun (reference : Skill.evidence_ref) -> reference.evidence_id)
  |> List.sort_uniq String.compare

let invalidate_approved_action store request_id =
  match Store.list_actions_by_request store request_id with
  | [ action ] when action.status = ActionApproved ->
      let marker = "\n\nProposal invalidated: source context requires regeneration." in
      let body = action.body ^ marker in
      let hash = payload_hash ~target_kind:action.target_kind
        ~target_ref:action.target_ref ~risk:action.risk ~body in
      Store.update_action_body_status_hash store ~action_id:action.id ~body
        ~payload_hash:hash ~status:ActionProposed
  | _ -> ()

let record_skill_error store ~request_id ~skill_id error =
  let reason = skill_id ^ ": " ^ error in
  invalidate_approved_action store request_id;
  Store.update_work_request_skill_error store ~request_id ~reason;
  Store.insert_timeline store
    (timeline ~request_id ~kind:"skill_error" ~title:"Built-in skill output rejected"
      ~body:reason)

let validate_evidence_refs store ~request_id refs =
  let available =
    Store.list_evidence_by_request store request_id
    |> List.map (fun (item : evidence_item) -> item.id)
  in
  match refs with
  | [] -> Error "proposed action must reference at least one evidence item"
  | _ ->
      begin match List.find_opt (fun id -> not (List.mem id available)) refs with
      | Some id -> Error ("unknown evidence reference for request: " ^ id)
      | None -> Ok ()
      end

let validate_builtin_action (request : work_request) kind
    (output : Skill.proposed_output) =
  if not output.requires_approval then
    Error "all built-in skill actions must require approval"
  else
    match kind with
    | LocalNextMove ->
        if output.target_kind <> "pharos.local.complete_request"
            || output.target_ref <> request.id || output.risk <> L2 then
          Error "context_summary_skill produced an invalid local action policy"
        else Ok ()
    | FeishuReply expected_target ->
        if output.target_kind <> "feishu.chat.reply"
            || output.target_ref <> expected_target || output.risk <> L3 then
          Error "draft_reply_skill produced an invalid Feishu action policy"
        else Ok ()
    | GitlabMrComment expected_target ->
        if output.target_kind <> "gitlab.mr.comment"
            || output.target_ref <> expected_target || output.risk <> L3 then
          Error "gitlab_mr_review_skill produced an invalid GitLab action policy"
        else Ok ()

let action_from_output (request : work_request) (output : Skill.proposed_output) =
  let refs = evidence_ref_ids output in
  let now = Time.now_iso () in
  let evidence_line = "Evidence refs: " ^ String.concat ", " refs in
  let body = output.body ^ "\n\n" ^ evidence_line in
  {
    id = Ids.create "act";
    request_id = request.id;
    title = output.title;
    body;
    target_kind = output.target_kind;
    target_ref = output.target_ref;
    risk = output.risk;
    requires_approval = output.requires_approval;
    status = ActionProposed;
    payload_hash = payload_hash ~target_kind:output.target_kind
      ~target_ref:output.target_ref ~risk:output.risk ~body;
    created_at = now;
    updated_at = now;
  }

let generation_event_body ~skill_id ~action_id ~context_hash
    ~generated_payload_hash ~refs ~result =
  `Assoc [
    ("skill_id", `String skill_id);
    ("action_id", `String action_id);
    ("context_hash", `String context_hash);
    ("generated_payload_hash", `String generated_payload_hash);
    ("evidence_refs", `List (List.map (fun value -> `String value) refs));
    ("result", `String result);
  ]
  |> Yojson.Safe.to_string

let generation_state_of_event (event : timeline_event) =
  if event.kind <> "skill" then None
  else
    match Yojson.Safe.from_string event.body with
    | exception Yojson.Json_error _ -> None
    | json ->
        let evidence_refs =
          match Yojson.Safe.Util.member "evidence_refs" json with
          | `List values -> List.filter_map (function `String value -> Some value | _ -> None) values
          | _ -> []
        in
        begin match Json_util.member_string "skill_id" json,
          Json_util.member_string "context_hash" json,
          Json_util.member_string "generated_payload_hash" json,
          Json_util.member_string "action_id" json with
        | Some skill_id, Some context_hash, Some generated_payload_hash,
            Some action_id ->
            Some { skill_id; context_hash; generated_payload_hash; action_id;
              evidence_refs }
        | _ -> None
        end

let latest_generation_state store request_id =
  Store.list_timeline_by_request store request_id
  |> List.rev
  |> List.find_map generation_state_of_event

let material_evidence store request_id =
  Store.list_evidence_by_request store request_id
  |> List.filter (fun (item : evidence_item) -> item.kind <> "source.update")

let context_hash (input : Skill.input) =
  let signal = input.source_signal in
  let evidence =
    input.evidence
    |> List.sort (fun (a : evidence_item) (b : evidence_item) ->
      compare (a.kind, a.title, a.body, a.url) (b.kind, b.title, b.body, b.url))
    |> List.map (fun (item : evidence_item) ->
      `Assoc [
        ("kind", `String item.kind);
        ("title", `String item.title);
        ("body", `String item.body);
        ("url", match item.url with None -> `Null | Some value -> `String value);
      ])
  in
  let body =
    `Assoc [
      ("kind", `String (source_kind_to_string signal.kind));
      ("external_id", match signal.external_id with
        | None -> `Null | Some value -> `String value);
      ("actor", `String signal.actor);
      ("title", `String signal.title);
      ("body", `String signal.body);
      ("url", match signal.url with None -> `Null | Some value -> `String value);
      ("raw_json", match signal.raw_json with
        | None -> `Null | Some value -> `String value);
      ("evidence", `List evidence);
    ]
    |> Yojson.Safe.to_string
  in
  payload_hash ~target_kind:"pharos.skill.context"
    ~target_ref:input.request.id ~risk:L0 ~body

let persist_skill_action store (request : work_request) kind ~context_hash
    (output : Skill.proposed_output) =
  let skill_id = skill_id_of_kind kind in
  let refs = evidence_ref_ids output in
  match validate_evidence_refs store ~request_id:request.id refs with
  | Error error -> Error error
  | Ok () ->
      begin match validate_builtin_action request kind output with
      | Error error -> Error error
      | Ok () ->
          let candidate = action_from_output request output in
          begin match Store.list_actions_by_request store request.id with
          | [] ->
              Store.insert_action store candidate;
              Store.update_request_status store ~request_id:request.id
                ~status:ReadyForReview;
              Store.insert_timeline store
                (timeline ~request_id:request.id ~kind:"skill"
                  ~title:"Built-in skill prepared an action"
                  ~body:(generation_event_body ~skill_id
                    ~action_id:candidate.id ~context_hash
                    ~generated_payload_hash:candidate.payload_hash ~refs
                    ~result:"created"));
              Store.bump_metric store "ready_for_review";
              Ok candidate
          | [ existing ] when existing.status = ActionExecuting
              || existing.status = ActionExecuted
              || existing.status = ActionRejected ->
              Error "current action cannot be refreshed in its terminal/executing state"
          | [ existing ] ->
              let previous_generated_hash =
                latest_generation_state store request.id
                |> Option.map (fun state -> state.generated_payload_hash)
                |> Option.value ~default:existing.payload_hash
              in
              if previous_generated_hash = candidate.payload_hash then begin
                let request_status =
                  if existing.status = ActionApproved then Approved
                  else ReadyForReview
                in
                Store.update_request_status store ~request_id:request.id
                  ~status:request_status;
                Store.insert_timeline store
                  (timeline ~request_id:request.id ~kind:"skill"
                    ~title:"Built-in skill kept the current action"
                    ~body:(generation_event_body ~skill_id
                      ~action_id:existing.id ~context_hash
                      ~generated_payload_hash:candidate.payload_hash ~refs
                      ~result:"unchanged"));
                Ok existing
              end else begin
                let refreshed = {
                  candidate with
                  id = existing.id;
                  created_at = existing.created_at;
                  status = ActionProposed;
                } in
                Store.update_action_from_skill store refreshed;
                Store.update_request_status store ~request_id:request.id
                  ~status:ReadyForReview;
                Store.insert_timeline store
                  (timeline ~request_id:request.id ~kind:"skill"
                    ~title:"Built-in skill refreshed the current action"
                    ~body:(generation_event_body ~skill_id
                      ~action_id:refreshed.id ~context_hash
                      ~generated_payload_hash:refreshed.payload_hash ~refs
                      ~result:"refreshed"));
                Store.bump_metric store "ready_for_review";
                Ok refreshed
              end
          | _ -> Error "request has more than one action; refusing to guess the current proposal"
          end
      end

let apply_skill_action store (request : work_request) kind ~context_hash = function
  | Error error ->
      record_skill_error store ~request_id:request.id
        ~skill_id:(skill_id_of_kind kind) error;
      None
  | Ok output ->
      begin match persist_skill_action store request kind ~context_hash output with
      | Ok action -> Some action
      | Error error ->
          record_skill_error store ~request_id:request.id
            ~skill_id:(skill_id_of_kind kind) error;
          None
      end

let gitlab_target_ref store (request : work_request) =
  match Store.get_source_signal store request.source_signal_id with
  | None -> Error "request source signal is missing"
  | Some signal -> Skill.gitlab_mr_target_ref_of_external_id signal.external_id

let apply_gitlab_mr_review_output store ~(request : work_request)
    ~context_hash parsed =
  let target = gitlab_target_ref store request in
  let output =
    match parsed with
    | Error error -> Error error
    | Ok parsed ->
        begin match target with
        | Error error -> Error error
        | Ok _ -> Ok (Skill.gitlab_review_to_proposed parsed)
        end
  in
  let kind = GitlabMrComment (Result.value target ~default:"invalid") in
  apply_skill_action store request kind ~context_hash output

let apply_gitlab_mr_review_output_json store ~(request : work_request) json =
  let current_context_hash =
    match Store.get_source_signal store request.source_signal_id with
    | None -> "missing-source-context"
    | Some source_signal ->
        context_hash {
          Skill.request;
          source_signal;
          evidence = material_evidence store request.id;
          timeline = Store.list_timeline_by_request store request.id;
        }
  in
  apply_gitlab_mr_review_output store ~request
    ~context_hash:current_context_hash
    (Skill.parse_gitlab_mr_review_output json)

let apply_draft_reply_output_json store ~(request : work_request)
    ~expected_target ~context_hash json =
  Skill.parse_draft_reply_output json
  |> Result.map Skill.draft_reply_to_proposed
  |> apply_skill_action store request (FeishuReply expected_target) ~context_hash

let current_request store (fallback : work_request) =
  Store.get_work_request store fallback.id |> Option.value ~default:fallback

let run_builtin_skills store (request : work_request) (signal : source_signal) =
  let input () : Skill.input = {
    request = current_request store request;
    source_signal = signal;
    evidence = material_evidence store request.id;
    timeline = Store.list_timeline_by_request store request.id;
  } in
  let initial_input = input () in
  let current_context_hash = context_hash initial_input in
  let existing_action =
    match Store.list_actions_by_request store request.id with
    | [ action ] -> Some action
    | _ -> None
  in
  let previous_generation = latest_generation_state store request.id in
  let unchanged_generation =
    match existing_action, previous_generation with
    | Some action, Some state when state.action_id = action.id
        && state.context_hash = current_context_hash -> Some (action, state)
    | _ -> None
  in
  match unchanged_generation with
  | Some (action, state) ->
    Store.insert_timeline store
      (timeline ~request_id:request.id ~kind:"skill"
        ~title:"Source context unchanged; current action preserved"
        ~body:(generation_event_body ~skill_id:state.skill_id
          ~action_id:action.id ~context_hash:current_context_hash
          ~generated_payload_hash:state.generated_payload_hash
          ~refs:state.evidence_refs ~result:"context_unchanged"))
  | None -> match Skill.parse_triage_output (Skill.triage_skill initial_input) with
  | Error error ->
      record_skill_error store ~request_id:request.id ~skill_id:"triage_skill" error
  | Ok triage when not triage.should_create_request ->
      invalidate_approved_action store request.id;
      Store.update_work_request_triage store ~request_id:request.id ~status:Archived
        ~priority:triage.priority ~risk:triage.risk ~reason:triage.reason
        ~next_step:triage.next_step;
      Store.insert_timeline store
        (timeline ~request_id:request.id ~kind:"skill"
          ~title:"Triage did not create a review action"
          ~body:"skill_id=triage_skill; should_create_request=false")
  | Ok triage when triage.needs_context ->
      invalidate_approved_action store request.id;
      Store.update_work_request_triage store ~request_id:request.id
        ~status:NeedsContext ~priority:triage.priority ~risk:triage.risk
        ~reason:triage.reason ~next_step:triage.next_step;
      Store.insert_timeline store
        (timeline ~request_id:request.id ~kind:"skill"
          ~title:"Triage requested more context"
          ~body:("skill_id=triage_skill; evidence_refs="
            ^ String.concat "," triage.evidence_refs))
  | Ok triage ->
      let request = current_request store request in
      Store.update_work_request_triage store ~request_id:request.id
        ~status:request.status ~priority:triage.priority ~risk:triage.risk
        ~reason:triage.reason ~next_step:triage.next_step;
      begin match
        Skill.parse_context_summary_output (Skill.context_summary_skill (input ()))
      with
      | Error error ->
          record_skill_error store ~request_id:request.id
            ~skill_id:"context_summary_skill" error
      | Ok context ->
          let request = current_request store request in
          begin match signal.kind with
          | GitLab ->
              ignore (apply_gitlab_mr_review_output store ~request
                ~context_hash:current_context_hash
                (Skill.parse_gitlab_mr_review_output
                  (Skill.gitlab_mr_review_skill (input ()))))
          | FeishuChat ->
              let expected_target =
                Option.value (Skill.external_target_ref signal) ~default:"invalid"
              in
              ignore (apply_draft_reply_output_json store ~request ~expected_target
                ~context_hash:current_context_hash (Skill.draft_reply_skill (input ())))
          | Manual | FeishuProject | FeishuDocs | UnknownSource _ ->
              ignore (
                apply_skill_action store request LocalNextMove
                  ~context_hash:current_context_hash
                  (Ok (Skill.local_next_move_to_proposed
                    ~target_ref:request.id context)))
          end
      end

let reconcile_evidence ?(managed_kinds=[]) store ~request_id
    (items : evidence_input list) =
  let now = Time.now_iso () in
  List.iter (fun kind ->
    if not (List.exists (fun (item : evidence_input) -> item.kind = kind) items)
    then Store.delete_evidence_by_request_kind store ~request_id ~kind)
    managed_kinds;
  List.iter (fun (item : evidence_input) ->
    Store.upsert_evidence_by_request_kind store {
      id = Ids.create "ev";
      request_id;
      kind = item.kind;
      title = item.title;
      body = item.body;
      url = item.url;
      created_at = now;
    }) items;
  if items <> [] || managed_kinds <> [] then
    Store.insert_timeline store
      (timeline ~request_id ~kind:"context" ~title:"Source context refreshed"
        ~body:(Printf.sprintf "%d evidence items attached" (List.length items)))

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
    status = Triaging;
    priority = Triage.classify_manual ~body:input.body;
    risk = L2;
    source_kind = Manual;
    source_signal_id = signal.id;
    reason = Triage.entry_reason;
    next_step = Triage.next_step;
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
  Store.with_transaction store (fun () ->
    Store.insert_source_signal store signal;
    Store.insert_work_request store request;
    Store.insert_evidence store evidence;
    Store.insert_timeline store (timeline ~request_id:request.id ~kind:"capture" ~title:"Manual signal captured" ~body:("Source signal " ^ signal.id));
    Store.insert_timeline store (timeline ~request_id:request.id ~kind:"triage" ~title:"Request created" ~body:request.reason);
    Store.bump_metric store "source_signals";
    Store.bump_metric store "work_requests";
    run_builtin_skills store request signal;
    current_request store request)

let create_request_from_source_signal store (signal : source_signal)
    ~evidence ~managed_evidence_kinds =
  let request = make_source_request signal in
  Store.insert_work_request store request;
  let source_evidence =
    make_source_evidence ~kind:("source." ^ source_kind_to_string signal.kind)
      ~title:"Source signal" signal request.id
  in
  Store.insert_evidence store source_evidence;
  reconcile_evidence store ~request_id:request.id
    ~managed_kinds:managed_evidence_kinds evidence;
  let identity_key = bind_identity store ~request_id:request.id signal in
  Store.insert_timeline store
    (timeline ~request_id:request.id ~kind:"capture" ~title:"Source signal captured"
      ~body:("signal_id=" ^ signal.id ^ "; identity_key=" ^ identity_key));
  Store.bump_metric store "work_requests";
  run_builtin_skills store request signal;
  current_request store request

let merge_source_signal_into_request store (signal : source_signal) identity_key
    (request : work_request) ~evidence ~managed_evidence_kinds =
  let summary = source_summary signal in
  Store.update_work_request_from_source_signal store ~request_id:request.id
    ~title:signal.title ~summary ~source_signal_id:signal.id;
  ignore (bind_identity store ~request_id:request.id signal);
  Store.upsert_evidence_by_request_kind store
    (make_source_evidence ~kind:("source." ^ source_kind_to_string signal.kind)
      ~title:"Source signal" signal request.id);
  Store.insert_evidence store
    (make_source_evidence ~kind:"source.update" ~title:"Source signal update"
      signal request.id);
  reconcile_evidence store ~request_id:request.id
    ~managed_kinds:managed_evidence_kinds evidence;
  Store.insert_timeline store
    (timeline ~request_id:request.id ~kind:"merge"
      ~title:"Source signal merged into existing request"
      ~body:("signal_id=" ^ signal.id ^ "; identity_key=" ^ identity_key));
  let updated = current_request store request in
  run_builtin_skills store updated signal;
  current_request store updated

let ingest_source_signal ?(evidence=[]) ?(managed_evidence_kinds=[]) store
    (input : source_signal_input) =
  let signal = source_signal_from_input input in
  Store.with_transaction store (fun () ->
    Store.insert_source_signal store signal;
    Store.bump_metric store "source_signals";
    let identity_key, _, _ = identity_parts signal in
    let request, merged =
      match Store.get_work_request_identity store identity_key with
      | Some identity ->
          begin match Store.get_work_request store identity.request_id with
          | Some request when request.status <> Done && request.status <> Archived ->
              (merge_source_signal_into_request store signal identity_key request
                ~evidence ~managed_evidence_kinds, true)
          | _ ->
              (create_request_from_source_signal store signal ~evidence
                ~managed_evidence_kinds, false)
          end
      | None ->
          (create_request_from_source_signal store signal ~evidence
            ~managed_evidence_kinds, false)
    in
    {
      request;
      merged;
      detail_url = "/v0/requests/" ^ request.id;
    })

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
