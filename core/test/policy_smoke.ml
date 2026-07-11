open Pharos_core
open Pharos_core.Domain

let temp_db () =
  Filename.concat (Filename.get_temp_dir_name ()) ("pharos_policy_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let failf fmt = Printf.ksprintf failwith fmt

let expect_string label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label expected actual

let expect_status label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label
      (request_status_to_string expected)
      (request_status_to_string actual)

let expect_action_body label expected actual =
  if expected <> actual then
    failf "%s: expected %S, got %S" label expected actual

let expect_risk_error label expected = function
  | Error (Policy.RiskNotExecutableInMvp actual) when actual = expected -> ()
  | Error err -> failf "%s: unexpected error %s" label (Policy.error_to_string err)
  | Ok _ -> failf "%s: expected risk block" label

let expect_timeline_kind (detail : request_detail) kind =
  match
    List.find_opt
      (fun (event : timeline_event) -> event.kind = kind)
      detail.timeline
  with
  | Some event -> event
  | None -> failf "expected timeline kind %s" kind

let contains haystack needle =
  let haystack_len = String.length haystack in
  let needle_len = String.length needle in
  if needle_len = 0 then true
  else
    let rec loop index =
      index + needle_len <= haystack_len
      && (String.sub haystack index needle_len = needle || loop (index + 1))
    in
    loop 0

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let capture store body =
  Runner.capture_manual store
    { Runner.title = Some "Policy smoke test"; body; url = None; actor = Some "test" }

let first_action store request_id =
  match Runner.get_detail store request_id with
  | None -> failf "missing detail for %s" request_id
  | Some detail ->
      begin match detail.actions with
      | action :: _ -> action
      | [] -> failf "missing action for %s" request_id
      end

let reload_request store request_id =
  match Store.get_work_request store request_id with
  | Some request -> request
  | None -> failf "missing request %s" request_id

let reload_action store action_id =
  match Store.get_action store action_id with
  | Some action -> action
  | None -> failf "missing action %s" action_id

let insert_test_request store ~status ~risk =
  let now = Time.now_iso () in
  let request : work_request =
    {
      id = Ids.create "req";
      title = "Policy test request";
      summary = "Synthetic policy boundary test";
      status;
      priority = Normal;
      risk;
      source_kind = Manual;
      source_signal_id = "sig_policy_test";
      reason = "policy safety test";
      next_step = "exercise policy boundary";
      created_at = now;
      updated_at = now;
    }
  in
  Store.insert_work_request store request;
  request

let insert_test_action store ~request_id ~risk ~target_kind ~requires_approval =
  let now = Time.now_iso () in
  let body = "synthetic action body with secret-like token should-not-leak" in
  let target_ref = request_id in
  let action : proposed_action =
    {
      id = Ids.create "act";
      request_id;
      title = "Synthetic action";
      body;
      target_kind;
      target_ref;
      risk;
      requires_approval;
      status = ActionProposed;
      payload_hash = payload_hash ~target_kind ~target_ref ~risk ~body;
      created_at = now;
      updated_at = now;
    }
  in
  Store.insert_action store action;
  action

let test_execution_requires_approval () =
  with_store (fun store ->
    let request =
      capture store "Make sure approved local actions execute only after approval"
    in
    let action = first_action store request.id in
    begin match Runner.execute_local store action.id with
    | Ok _ -> failwith "execution should require approval"
    | Error (Policy.ApprovalRequired _) -> ()
    | Error err -> failwith ("unexpected error: " ^ Policy.error_to_string err)
    end)

let test_edit_and_approve_updates_hash () =
  with_store (fun store ->
    let request = capture store "Approve edited body" in
    let action = first_action store request.id in
    let old_hash = action.payload_hash in
    let edited_body = "edited body" in
    ignore (Result.get_ok (Runner.approve ~edited_body store action.id));
    let edited_action = reload_action store action.id in
    expect_action_body "edited action body" edited_body edited_action.body;
    if edited_action.payload_hash = old_hash then
      failf "edited payload hash should change";
    ignore (Result.get_ok (Runner.execute_local store action.id));
    let request_after = reload_request store request.id in
    expect_status "edited approval executes request" Done request_after.status)

let test_hash_mismatch_blocks_execution () =
  with_store (fun store ->
    let request = capture store "Detect stale approval hash" in
    let action = first_action store request.id in
    ignore (Result.get_ok (Runner.approve store action.id));
    let tampered_body = "tampered body" in
    let tampered_hash =
      payload_hash ~target_kind:action.target_kind ~target_ref:action.target_ref
        ~risk:action.risk ~body:tampered_body
    in
    Store.update_action_body_status_hash store ~action_id:action.id
      ~body:tampered_body ~payload_hash:tampered_hash ~status:ActionApproved;
    begin match Runner.execute_local store action.id with
    | Error (Policy.ApprovalHashMismatch { action_hash; approval_hash }) ->
        expect_string "mismatched action hash" tampered_hash action_hash;
        if approval_hash = action_hash then
          failf "approval hash should remain bound to the original approved payload"
    | Error err -> failf "unexpected error: %s" (Policy.error_to_string err)
    | Ok _ -> failf "execution should fail when approval hash is stale"
    end)

let test_proposed_action_cannot_reuse_matching_historical_approval () =
  with_store (fun store ->
    let request = capture store "Do not revive a stale approval" in
    let action = first_action store request.id in
    let approved_body = "User-edited payload A" in
    let approval =
      Runner.approve ~edited_body:approved_body store action.id |> Result.get_ok
    in
    let changed_body = "Generated payload B" in
    let changed_hash =
      payload_hash ~target_kind:action.target_kind ~target_ref:action.target_ref
        ~risk:action.risk ~body:changed_body
    in
    Store.update_action_body_status_hash store ~action_id:action.id
      ~body:changed_body ~payload_hash:changed_hash ~status:ActionProposed;
    Store.update_action_body_status_hash store ~action_id:action.id
      ~body:approved_body ~payload_hash:approval.action_hash
      ~status:ActionProposed;
    begin match Runner.execute_local store action.id with
    | Error (Policy.ApprovalRequired id) ->
        expect_string "proposed action id" action.id id
    | Error err -> failf "unexpected error: %s" (Policy.error_to_string err)
    | Ok _ -> failf "proposed action reused a matching historical approval"
    end)

let test_rejection_blocks_execution () =
  with_store (fun store ->
    let request = capture store "Reject this action" in
    let action = first_action store request.id in
    ignore (Result.get_ok (Runner.reject store action.id));
    begin match Runner.execute_local store action.id with
    | Error (Policy.RejectedAction id) -> expect_string "rejected action id" action.id id
    | Error err -> failf "unexpected error: %s" (Policy.error_to_string err)
    | Ok _ -> failf "rejected action should not execute"
    end;
    let request_after = reload_request store request.id in
    expect_status "rejected request status" Archived request_after.status)

let test_high_risk_actions_block risk =
  with_store (fun store ->
    let request = insert_test_request store ~status:ReadyForReview ~risk in
    let action =
      insert_test_action store ~request_id:request.id ~risk
        ~target_kind:"pharos.local.complete_request" ~requires_approval:true
    in
    expect_risk_error "approve high-risk action" risk
      (Runner.approve store action.id);
    expect_risk_error "execute high-risk action" risk
      (Runner.execute_local store action.id))

let test_external_target_blocked_and_logged ?(risk = L3) () =
  with_store (fun store ->
    let request = insert_test_request store ~status:ReadyForReview ~risk in
    let action =
      insert_test_action store ~request_id:request.id ~risk
        ~target_kind:"gitlab.mr.comment" ~requires_approval:true
    in
    begin match Runner.execute_local store action.id with
    | Error (Policy.ExternalWritebackNotImplemented target) ->
        expect_string "blocked target kind" "gitlab.mr.comment" target
    | Error err -> failf "unexpected error: %s" (Policy.error_to_string err)
    | Ok _ -> failf "external target should not execute-local"
    end;
    let detail = Option.get (Runner.get_detail store request.id) in
    let event = expect_timeline_kind detail "policy_block" in
    expect_string "policy block title"
      "External writeback blocked by local executor" event.title;
    if contains event.body action.body then
      failf "policy block timeline must not include full action body";
    if not (contains event.body "target_kind=gitlab.mr.comment") then
      failf "policy block timeline should include target kind";
    let metric =
      match Store.get_metric_for_day store (Time.today_utc ()) with
      | Some metric -> metric
      | None -> failf "missing metric row for today"
    in
    if metric.unapproved_external_write_attempts <> 1 then
      failf "expected 1 blocked external write attempt, got %d"
        metric.unapproved_external_write_attempts)

let () =
  Random.self_init ();
  test_execution_requires_approval ();
  test_edit_and_approve_updates_hash ();
  test_hash_mismatch_blocks_execution ();
  test_proposed_action_cannot_reuse_matching_historical_approval ();
  test_rejection_blocks_execution ();
  test_high_risk_actions_block L4;
  test_high_risk_actions_block L5;
  test_external_target_blocked_and_logged ();
  test_external_target_blocked_and_logged ~risk:L5 ()
