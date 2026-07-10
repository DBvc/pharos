type source_kind =
  | Manual
  | FeishuChat
  | FeishuProject
  | GitLab
  | FeishuDocs
  | UnknownSource of string

type request_status =
  | New
  | Triaging
  | NeedsContext
  | Running
  | ReadyForReview
  | Waiting
  | Approved
  | Executing
  | Done
  | Failed
  | Snoozed
  | Archived

type priority = Low | Normal | High | Urgent

type risk = L0 | L1 | L2 | L3 | L4 | L5

type action_status =
  | ActionProposed
  | ActionApproved
  | ActionRejected
  | ActionExecuting
  | ActionExecuted
  | ActionFailed

type source_signal = {
  id : string;
  kind : source_kind;
  external_id : string option;
  actor : string;
  title : string;
  body : string;
  url : string option;
  occurred_at : string;
  raw_json : string option;
}

type work_request = {
  id : string;
  title : string;
  summary : string;
  status : request_status;
  priority : priority;
  risk : risk;
  source_kind : source_kind;
  source_signal_id : string;
  reason : string;
  next_step : string;
  created_at : string;
  updated_at : string;
}

type proposed_action = {
  id : string;
  request_id : string;
  title : string;
  body : string;
  target_kind : string;
  target_ref : string;
  risk : risk;
  requires_approval : bool;
  status : action_status;
  payload_hash : string;
  created_at : string;
  updated_at : string;
}

type approval_decision = ApprovedDecision | EditedAndApprovedDecision | RejectedDecision

type approval = {
  id : string;
  action_id : string;
  action_hash : string;
  decision : approval_decision;
  approved_body : string option;
  created_at : string;
}

type evidence_item = {
  id : string;
  request_id : string;
  kind : string;
  title : string;
  body : string;
  url : string option;
  created_at : string;
}

type timeline_event = {
  id : string;
  request_id : string;
  kind : string;
  title : string;
  body : string;
  created_at : string;
}

type work_request_identity = {
  identity_key : string;
  request_id : string;
  source_kind : source_kind;
  external_key : string;
  normalized_subject : string;
  created_at : string;
  updated_at : string;
}

type source_config = {
  id : string;
  kind : source_kind;
  enabled : bool;
  read_enabled : bool;
  write_enabled : bool;
  scope_json : string;
  last_sync_at : string option;
  last_error : string option;
  created_at : string;
  updated_at : string;
}

type source_config_patch = {
  enabled : bool option;
  read_enabled : bool option;
  write_enabled : bool option;
  scope_json : string option;
}

type request_detail = {
  request : work_request;
  actions : proposed_action list;
  evidence : evidence_item list;
  timeline : timeline_event list;
}

type today_snapshot = {
  needs_review : work_request list;
  running : work_request list;
  needs_context : work_request list;
  new_items : work_request list;
  done_today : work_request list;
  archived_noise_count : int;
}

type attention_group = NeedsDecision | NeedsInput | Watching | Handled | Noise

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

let source_kind_to_string = function
  | Manual -> "manual"
  | FeishuChat -> "feishu_chat"
  | FeishuProject -> "feishu_project"
  | GitLab -> "gitlab"
  | FeishuDocs -> "feishu_docs"
  | UnknownSource s -> s

let source_kind_of_string = function
  | "manual" -> Manual
  | "feishu_chat" -> FeishuChat
  | "feishu_project" -> FeishuProject
  | "gitlab" -> GitLab
  | "feishu_docs" -> FeishuDocs
  | s -> UnknownSource s

let request_status_to_string = function
  | New -> "new"
  | Triaging -> "triaging"
  | NeedsContext -> "needs_context"
  | Running -> "running"
  | ReadyForReview -> "ready_for_review"
  | Waiting -> "waiting"
  | Approved -> "approved"
  | Executing -> "executing"
  | Done -> "done"
  | Failed -> "failed"
  | Snoozed -> "snoozed"
  | Archived -> "archived"

let request_status_of_string = function
  | "new" -> New
  | "triaging" -> Triaging
  | "needs_context" -> NeedsContext
  | "running" -> Running
  | "ready_for_review" -> ReadyForReview
  | "waiting" -> Waiting
  | "approved" -> Approved
  | "executing" -> Executing
  | "done" -> Done
  | "failed" -> Failed
  | "snoozed" -> Snoozed
  | "archived" -> Archived
  | _ -> New

let priority_to_string = function
  | Low -> "low"
  | Normal -> "normal"
  | High -> "high"
  | Urgent -> "urgent"

let priority_of_string = function
  | "low" -> Low
  | "normal" -> Normal
  | "high" -> High
  | "urgent" -> Urgent
  | _ -> Normal

let risk_to_string = function
  | L0 -> "l0"
  | L1 -> "l1"
  | L2 -> "l2"
  | L3 -> "l3"
  | L4 -> "l4"
  | L5 -> "l5"

let risk_of_string = function
  | "l0" -> L0
  | "l1" -> L1
  | "l2" -> L2
  | "l3" -> L3
  | "l4" -> L4
  | "l5" -> L5
  | _ -> L1

let action_status_to_string = function
  | ActionProposed -> "proposed"
  | ActionApproved -> "approved"
  | ActionRejected -> "rejected"
  | ActionExecuting -> "executing"
  | ActionExecuted -> "executed"
  | ActionFailed -> "failed"

let action_status_of_string = function
  | "proposed" -> ActionProposed
  | "approved" -> ActionApproved
  | "rejected" -> ActionRejected
  | "executing" -> ActionExecuting
  | "executed" -> ActionExecuted
  | "failed" -> ActionFailed
  | _ -> ActionProposed

let approval_decision_to_string = function
  | ApprovedDecision -> "approved"
  | EditedAndApprovedDecision -> "edited_and_approved"
  | RejectedDecision -> "rejected"

let approval_decision_of_string = function
  | "approved" -> ApprovedDecision
  | "edited_and_approved" -> EditedAndApprovedDecision
  | "rejected" -> RejectedDecision
  | _ -> ApprovedDecision

let risk_requires_approval = function
  | L0 | L1 | L2 -> false
  | L3 | L4 | L5 -> true

let risk_is_executable_in_mvp = function
  | L0 | L1 | L2 | L3 -> true
  | L4 | L5 -> false

let attention_group_to_string = function
  | NeedsDecision -> "needs_decision"
  | NeedsInput -> "needs_input"
  | Watching -> "watching"
  | Handled -> "handled"
  | Noise -> "noise"

let attention_group_of_status = function
  | ReadyForReview -> NeedsDecision
  | NeedsContext | Failed -> NeedsInput
  | New | Triaging | Running | Waiting | Approved | Executing | Snoozed ->
      Watching
  | Done -> Handled
  | Archived -> Noise

let payload_hash ~target_kind ~target_ref ~risk ~body =
  Digest.to_hex (Digest.string (String.concat "\n" [ target_kind; target_ref; risk_to_string risk; body ]))

let source_signal_to_yojson (s : source_signal) =
  Json_util.assoc [
    Json_util.str "id" s.id;
    Json_util.str "kind" (source_kind_to_string s.kind);
    Json_util.opt_str "external_id" s.external_id;
    Json_util.str "actor" s.actor;
    Json_util.str "title" s.title;
    Json_util.str "body" s.body;
    Json_util.opt_str "url" s.url;
    Json_util.str "occurred_at" s.occurred_at;
    Json_util.opt_str "raw_json" s.raw_json;
  ]

let work_request_to_yojson (r : work_request) =
  Json_util.assoc [
    Json_util.str "id" r.id;
    Json_util.str "title" r.title;
    Json_util.str "summary" r.summary;
    Json_util.str "status" (request_status_to_string r.status);
    Json_util.str "priority" (priority_to_string r.priority);
    Json_util.str "risk" (risk_to_string r.risk);
    Json_util.str "source_kind" (source_kind_to_string r.source_kind);
    Json_util.str "source_signal_id" r.source_signal_id;
    Json_util.str "reason" r.reason;
    Json_util.str "next_step" r.next_step;
    Json_util.str "created_at" r.created_at;
    Json_util.str "updated_at" r.updated_at;
  ]

let proposed_action_to_yojson (a : proposed_action) =
  Json_util.assoc [
    Json_util.str "id" a.id;
    Json_util.str "request_id" a.request_id;
    Json_util.str "title" a.title;
    Json_util.str "body" a.body;
    Json_util.str "target_kind" a.target_kind;
    Json_util.str "target_ref" a.target_ref;
    Json_util.str "risk" (risk_to_string a.risk);
    Json_util.bool "requires_approval" a.requires_approval;
    Json_util.str "status" (action_status_to_string a.status);
    Json_util.str "payload_hash" a.payload_hash;
    Json_util.str "created_at" a.created_at;
    Json_util.str "updated_at" a.updated_at;
  ]

let approval_to_yojson (a : approval) =
  Json_util.assoc [
    Json_util.str "id" a.id;
    Json_util.str "action_id" a.action_id;
    Json_util.str "action_hash" a.action_hash;
    Json_util.str "decision" (approval_decision_to_string a.decision);
    Json_util.opt_str "approved_body" a.approved_body;
    Json_util.str "created_at" a.created_at;
  ]

let evidence_item_to_yojson (e : evidence_item) =
  Json_util.assoc [
    Json_util.str "id" e.id;
    Json_util.str "request_id" e.request_id;
    Json_util.str "kind" e.kind;
    Json_util.str "title" e.title;
    Json_util.str "body" e.body;
    Json_util.opt_str "url" e.url;
    Json_util.str "created_at" e.created_at;
  ]

let timeline_event_to_yojson (e : timeline_event) =
  Json_util.assoc [
    Json_util.str "id" e.id;
    Json_util.str "request_id" e.request_id;
    Json_util.str "kind" e.kind;
    Json_util.str "title" e.title;
    Json_util.str "body" e.body;
    Json_util.str "created_at" e.created_at;
  ]

let source_config_to_yojson (s : source_config) =
  Json_util.assoc [
    Json_util.str "id" s.id;
    Json_util.str "kind" (source_kind_to_string s.kind);
    Json_util.bool "enabled" s.enabled;
    Json_util.bool "read_enabled" s.read_enabled;
    Json_util.bool "write_enabled" s.write_enabled;
    Json_util.str "scope_json" s.scope_json;
    Json_util.opt_str "last_sync_at" s.last_sync_at;
    Json_util.opt_str "last_error" s.last_error;
    Json_util.str "created_at" s.created_at;
    Json_util.str "updated_at" s.updated_at;
  ]

let sources_response_to_yojson sources =
  Json_util.assoc [ Json_util.list "sources" source_config_to_yojson sources ]

let source_response_to_yojson source =
  Json_util.assoc [ ("source", source_config_to_yojson source) ]

let request_detail_to_yojson (d : request_detail) =
  Json_util.assoc [
    ("request", work_request_to_yojson d.request);
    Json_util.list "actions" proposed_action_to_yojson d.actions;
    Json_util.list "evidence" evidence_item_to_yojson d.evidence;
    Json_util.list "timeline" timeline_event_to_yojson d.timeline;
  ]

let today_snapshot_to_yojson (t : today_snapshot) =
  Json_util.assoc [
    Json_util.list "needs_review" work_request_to_yojson t.needs_review;
    Json_util.list "running" work_request_to_yojson t.running;
    Json_util.list "needs_context" work_request_to_yojson t.needs_context;
    Json_util.list "new_items" work_request_to_yojson t.new_items;
    Json_util.list "done_today" work_request_to_yojson t.done_today;
    Json_util.int "archived_noise_count" t.archived_noise_count;
  ]

let decision_card_to_yojson (c : decision_card) =
  Json_util.assoc
    [
      Json_util.str "request_id" c.request_id;
      Json_util.str "title" c.title;
      Json_util.str "summary" c.summary;
      Json_util.str "group" (attention_group_to_string c.group);
      Json_util.str "source_kind" (source_kind_to_string c.source_kind);
      Json_util.opt_str "source_url" c.source_url;
      Json_util.str "priority" (priority_to_string c.priority);
      Json_util.str "risk" (risk_to_string c.risk);
      Json_util.str "why_now" c.why_now;
      Json_util.opt_str "prepared_next_move" c.prepared_next_move;
      Json_util.opt_str "target_preview" c.target_preview;
      Json_util.int "evidence_count" c.evidence_count;
      Json_util.str "updated_at" c.updated_at;
      Json_util.str "debug_status" (request_status_to_string c.debug_status);
    ]

let noise_summary_to_yojson (n : noise_summary) =
  Json_util.assoc [ Json_util.int "count" n.count ]

let today_decision_snapshot_to_yojson (t : today_decision_snapshot) =
  Json_util.assoc
    [
      Json_util.list "needs_decision" decision_card_to_yojson t.needs_decision;
      Json_util.list "needs_input" decision_card_to_yojson t.needs_input;
      Json_util.list "watching" decision_card_to_yojson t.watching;
      Json_util.list "handled" decision_card_to_yojson t.handled;
      ("noise", noise_summary_to_yojson t.noise);
    ]
