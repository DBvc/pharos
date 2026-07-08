open Domain

type capture_input = {
  title : string option;
  body : string;
  url : string option;
  actor : string option;
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

let timeline ~request_id ~kind ~title ~body =
  {
    id = Ids.create "evt";
    request_id;
    kind;
    title;
    body;
    created_at = Time.now_iso ();
  }

let capture_manual store input =
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

let get_detail = Store.request_detail
let today = Store.today_decision
let today_internal = Store.today_internal
let approve = Policy.approve
let reject = Policy.reject
let execute_local = Policy.execute_local
