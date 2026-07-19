open Domain

type skill_id = string

type evidence_ref = {
  evidence_id : string;
  note : string;
}

type triage_output = {
  should_create_request : bool;
  request_type : string;
  priority : priority;
  risk : risk;
  reason : string;
  next_step : string;
  needs_context : bool;
  notify_user : bool;
  evidence_refs : string list;
}

type context_summary_output = {
  facts : string list;
  inferences : string list;
  unknowns : string list;
  evidence_refs : string list;
}

type draft_reply_output = {
  draft_body : string;
  target_kind : string;
  target_ref : string;
  risk : risk;
  requires_approval : bool;
  evidence_refs : string list;
}

type gitlab_mr_review_output = {
  summary : string;
  risk_points : string list;
  test_gaps : string list;
  draft_comment : string;
  target_kind : string;
  target_ref : string;
  risk : risk;
  requires_approval : bool;
  evidence_refs : string list;
}

type proposed_output = {
  title : string;
  body : string;
  target_kind : string;
  target_ref : string;
  risk : risk;
  requires_approval : bool;
  evidence_refs : evidence_ref list;
}

type input = {
  request : work_request;
  source_signal : source_signal;
  evidence : evidence_item list;
  timeline : timeline_event list;
}

let ( let* ) = Result.bind

let required_bool name json =
  match Yojson.Safe.Util.member name json with
  | `Bool value -> Ok value
  | _ -> Error ("Missing required boolean field: " ^ name)

let required_string_list name json =
  match Yojson.Safe.Util.member name json with
  | `List values ->
      let rec parse acc = function
        | [] -> Ok (List.rev acc)
        | `String value :: rest when String.trim value <> "" ->
            parse (value :: acc) rest
        | _ -> Error ("Invalid string list field: " ^ name)
      in
      parse [] values
  | _ -> Error ("Missing required list field: " ^ name)

let required_evidence_refs json =
  let* refs = required_string_list "evidence_refs" json in
  if refs = [] then Error "evidence_refs must contain at least one evidence id"
  else Ok refs

let required_priority json =
  let* value = Json_util.required_string "priority" json in
  priority_of_string_strict value

let required_risk json =
  let* value = Json_util.required_string "risk" json in
  risk_of_string_strict value

let parse_triage_output json =
  let* should_create_request = required_bool "should_create_request" json in
  let* request_type = Json_util.required_string "request_type" json in
  let* priority = required_priority json in
  let* risk = required_risk json in
  let* reason = Json_util.required_string "reason" json in
  let* next_step = Json_util.required_string "next_step" json in
  let* needs_context = required_bool "needs_context" json in
  let* notify_user = required_bool "notify_user" json in
  let* evidence_refs = required_evidence_refs json in
  Ok {
    should_create_request;
    request_type;
    priority;
    risk;
    reason;
    next_step;
    needs_context;
    notify_user;
    evidence_refs;
  }

let parse_context_summary_output json =
  let* facts = required_string_list "facts" json in
  let* inferences = required_string_list "inferences" json in
  let* unknowns = required_string_list "unknowns" json in
  let* evidence_refs = required_evidence_refs json in
  Ok { facts; inferences; unknowns; evidence_refs }

let parse_draft_reply_output json =
  let* draft_body = Json_util.required_string "draft_body" json in
  let* target_kind = Json_util.required_string "target_kind" json in
  let* target_ref = Json_util.required_string "target_ref" json in
  let* risk = required_risk json in
  let* requires_approval = required_bool "requires_approval" json in
  let* evidence_refs = required_evidence_refs json in
  if target_kind <> "feishu.chat.reply" then
    Error ("Invalid draft reply target_kind: " ^ target_kind)
  else if risk <> L3 then Error "draft reply risk must be l3"
  else if not requires_approval then Error "draft reply must require approval"
  else
    Ok {
      draft_body;
      target_kind;
      target_ref;
      risk;
      requires_approval;
      evidence_refs;
    }

let parse_gitlab_mr_review_output json =
  let* summary = Json_util.required_string "summary" json in
  let* risk_points = required_string_list "risk_points" json in
  let* test_gaps = required_string_list "test_gaps" json in
  let* draft_comment = Json_util.required_string "draft_comment" json in
  let* target_kind = Json_util.required_string "target_kind" json in
  let* target_ref = Json_util.required_string "target_ref" json in
  let* risk = required_risk json in
  let* requires_approval = required_bool "requires_approval" json in
  let* evidence_refs = required_evidence_refs json in
  if target_kind <> "gitlab.mr.comment" then
    Error ("Invalid GitLab review target_kind: " ^ target_kind)
  else if risk <> L3 then Error "GitLab review risk must be l3"
  else if not requires_approval then Error "GitLab review must require approval"
  else
    Ok {
      summary;
      risk_points;
      test_gaps;
      draft_comment;
      target_kind;
      target_ref;
      risk;
      requires_approval;
      evidence_refs;
    }

let json_string_list values = `List (List.map (fun value -> `String value) values)

let evidence_ids (input : input) =
  List.map (fun (item : evidence_item) -> item.id) input.evidence

let external_target_ref (signal : source_signal) =
  match signal.external_id with
  | Some value when String.trim value <> "" -> Some (String.trim value)
  | _ -> None

let gitlab_mr_target_ref_of_external_id external_id =
  match external_id with
  | None -> Error "GitLab MR source is missing a stable external_id"
  | Some value ->
      begin match Gitlab_identity.parse_external_id value with
      | Ok ({ object_kind = MergeRequest; _ } as target) ->
          Ok (Gitlab_identity.target_ref target)
      | Ok _ -> Error "GitLab MR external_id identifies an issue"
      | Error error -> Error error
      end

let triage_skill (input : input) =
  let signal = input.source_signal in
  let target_error =
    match signal.kind with
    | GitLab ->
        begin match gitlab_mr_target_ref_of_external_id signal.external_id with
        | Ok _ -> None
        | Error error -> Some error
        end
    | FeishuChat ->
        if Option.is_some (external_target_ref signal) then None
        else Some "Feishu reply source is missing a stable external_id"
    | Manual | FeishuProject | FeishuDocs | UnknownSource _ -> None
  in
  let needs_context = Option.is_some target_error in
  let next_step =
    Option.value target_error ~default:(Triage.source_next_step signal)
  in
  `Assoc [
    ("should_create_request", `Bool true);
    ("request_type", `String (Triage.request_type signal));
    ("priority", `String (priority_to_string (Triage.request_priority signal)));
    ("risk", `String (risk_to_string (Triage.request_risk signal)));
    ("reason", `String (Triage.source_reason signal));
    ("next_step", `String next_step);
    ("needs_context", `Bool needs_context);
    ("notify_user", `Bool false);
    ("evidence_refs", json_string_list (evidence_ids input));
  ]

let context_summary_skill (input : input) =
  let signal = input.source_signal in
  let facts = [ signal.actor ^ " provided: " ^ Triage.compact_body signal.body ] in
  let inferences = [ Triage.source_reason signal ] in
  let unknowns =
    match signal.kind with
    | GitLab -> [ "The full diff and complete test results are not present in this signal." ]
    | FeishuChat -> [ "The final rollout commitment is not yet confirmed." ]
    | FeishuProject -> [ "The owner and unblock date are not yet confirmed." ]
    | FeishuDocs -> [ "The expected response and owner are not yet confirmed." ]
    | Manual | UnknownSource _ -> [ "The final owner and completion criteria are not yet confirmed." ]
  in
  `Assoc [
    ("facts", json_string_list facts);
    ("inferences", json_string_list inferences);
    ("unknowns", json_string_list unknowns);
    ("evidence_refs", json_string_list (evidence_ids input));
  ]

let draft_reply_skill (input : input) =
  let signal = input.source_signal in
  let draft_body =
    "Thanks for the note. I have captured this and will confirm the next step after reviewing the available context."
  in
  `Assoc [
    ("draft_body", `String draft_body);
    ("target_kind", `String "feishu.chat.reply");
    ("target_ref", `String (Option.value (external_target_ref signal) ~default:""));
    ("risk", `String "l3");
    ("requires_approval", `Bool true);
    ("evidence_refs", json_string_list (evidence_ids input));
  ]

let gitlab_mr_review_skill (input : input) =
  let signal = input.source_signal in
  let lower = String.lowercase_ascii signal.body in
  let pipeline_failing = Triage.contains_substring lower "fail" in
  let risk_points =
    if pipeline_failing then [ "The signal reports a failing pipeline." ]
    else [ "The change has not been reviewed against the full diff." ]
  in
  let test_gaps = [ "Confirm the affected tests and pipeline result before approval." ] in
  let draft_comment =
    if pipeline_failing then
      "The pipeline is currently failing. Please resolve the reported test failure and share the updated result before merge."
    else
      "I reviewed the available signal. Please confirm the affected test coverage before merge."
  in
  let target_ref =
    gitlab_mr_target_ref_of_external_id signal.external_id
    |> Result.value ~default:""
  in
  `Assoc [
    ("summary", `String signal.title);
    ("risk_points", json_string_list risk_points);
    ("test_gaps", json_string_list test_gaps);
    ("draft_comment", `String draft_comment);
    ("target_kind", `String "gitlab.mr.comment");
    ("target_ref", `String target_ref);
    ("risk", `String "l3");
    ("requires_approval", `Bool true);
    ("evidence_refs", json_string_list (evidence_ids input));
  ]

let refs values =
  List.map (fun evidence_id -> { evidence_id; note = "skill input" }) values

let draft_reply_to_proposed (output : draft_reply_output) =
  {
    title = "Review prepared reply draft";
    body = output.draft_body;
    target_kind = output.target_kind;
    target_ref = output.target_ref;
    risk = output.risk;
    requires_approval = output.requires_approval;
    evidence_refs = refs output.evidence_refs;
  }

let gitlab_review_to_proposed (output : gitlab_mr_review_output) =
  let section label values =
    label ^ "\n" ^ String.concat "\n" (List.map (fun value -> "- " ^ value) values)
  in
  {
    title = "Review prepared GitLab MR comment";
    body = String.concat "\n\n" [
      output.summary;
      section "Risk points" output.risk_points;
      section "Test gaps" output.test_gaps;
      "Draft comment\n" ^ output.draft_comment;
    ];
    target_kind = output.target_kind;
    target_ref = output.target_ref;
    risk = output.risk;
    requires_approval = output.requires_approval;
    evidence_refs = refs output.evidence_refs;
  }

let local_next_move_to_proposed ~target_ref
    (context : context_summary_output) =
  let section label values =
    label ^ "\n" ^ String.concat "\n" (List.map (fun value -> "- " ^ value) values)
  in
  {
    title = "Review prepared local next move";
    body = String.concat "\n\n" [
      section "Facts" context.facts;
      section "Inferences" context.inferences;
      section "Unknowns" context.unknowns;
    ];
    target_kind = "pharos.local.complete_request";
    target_ref;
    risk = L2;
    requires_approval = true;
    evidence_refs = refs context.evidence_refs;
  }

let builtin_skill_ids = [
  "triage_skill";
  "context_summary_skill";
  "draft_reply_skill";
  "gitlab_mr_review_skill";
  "project_next_step_skill";
  "doc_understanding_skill";
]
