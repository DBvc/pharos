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

let expect_unsupported_hash label ~action_id ~payload_hash = function
  | Error
      (Policy.UnsupportedPayloadHash
        { action_id = actual_action_id; payload_hash = actual_payload_hash }) ->
      expect_string (label ^ " action id") action_id actual_action_id;
      expect_string (label ^ " payload hash") payload_hash actual_payload_hash
  | Error err -> failf "%s: unexpected error %s" label (Policy.error_to_string err)
  | Ok _ -> failf "%s: legacy payload hash unexpectedly passed policy" label

let expect_payload_hash_mismatch label ~action_id ~stored_hash = function
  | Error
      (Policy.PayloadHashMismatch
        {
          action_id = actual_action_id;
          stored_hash = actual_stored_hash;
          computed_hash;
        }) ->
      expect_string (label ^ " action id") action_id actual_action_id;
      expect_string (label ^ " stored hash") stored_hash actual_stored_hash;
      if computed_hash = stored_hash then
        failf "%s: computed hash unexpectedly matched stored hash" label
  | Error err -> failf "%s: unexpected error %s" label (Policy.error_to_string err)
  | Ok _ -> failf "%s: tampered payload unexpectedly passed policy" label

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

let metric_today store = Store.get_metric_for_day store (Time.today_utc ())

let review_snapshot store request_id action_id =
  ( reload_request store request_id,
    reload_action store action_id,
    Option.get (Runner.get_detail store request_id),
    metric_today store,
    Store.get_latest_approval_for_action store action_id )

let expect_stale label ~action_id ~expected_hash ~actual_hash = function
  | Error
      (Policy.StaleAction
        {
          action_id = stale_id;
          expected_hash = stale_expected;
          actual_hash = stale_actual;
        }) ->
      expect_string (label ^ " action id") action_id stale_id;
      expect_string (label ^ " expected hash") expected_hash stale_expected;
      expect_string (label ^ " actual hash") actual_hash stale_actual
  | Error error ->
      failf "%s: unexpected error %s" label (Policy.error_to_string error)
  | Ok _ -> failf "%s: stale review unexpectedly succeeded" label

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
    ignore
      (Result.get_ok
         (Runner.approve ~edited_body
            ~expected_payload_hash:action.payload_hash store action.id));
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
    ignore
      (Result.get_ok
         (Runner.approve ~expected_payload_hash:action.payload_hash store
            action.id));
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

let test_action_field_tamper_blocks_execution label mutate =
  with_store (fun store ->
    let request = capture store ("Detect " ^ label ^ " tamper") in
    let action = first_action store request.id in
    ignore
      (Result.get_ok
         (Runner.approve ~expected_payload_hash:action.payload_hash store
            action.id));
    let approved_action = reload_action store action.id in
    Store.update_action_from_skill store (mutate approved_action);
    let before = review_snapshot store request.id action.id in
    expect_payload_hash_mismatch label ~action_id:action.id
      ~stored_hash:approved_action.payload_hash
      (Runner.execute_local store action.id);
    if before <> review_snapshot store request.id action.id then
      failf "%s tamper execution changed persisted state" label)

let test_proposed_action_cannot_reuse_matching_historical_approval () =
  with_store (fun store ->
    let request = capture store "Do not revive a stale approval" in
    let action = first_action store request.id in
    let approved_body = "User-edited payload A" in
    let approval =
      Runner.approve ~edited_body:approved_body
        ~expected_payload_hash:action.payload_hash store action.id
      |> Result.get_ok
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
    ignore
      (Result.get_ok
         (Runner.reject ~expected_payload_hash:action.payload_hash store
            action.id));
    begin match Runner.execute_local store action.id with
    | Error (Policy.RejectedAction id) -> expect_string "rejected action id" action.id id
    | Error err -> failf "unexpected error: %s" (Policy.error_to_string err)
    | Ok _ -> failf "rejected action should not execute"
    end;
    let request_after = reload_request store request.id in
    expect_status "rejected request status" Archived request_after.status)

let legacy_md5 = "0123456789abcdef0123456789abcdef"

let set_action_hash store (action : proposed_action) ~payload_hash ~status =
  Store.update_action_body_status_hash store ~action_id:action.id
    ~body:action.body ~payload_hash ~status

let test_legacy_hash_cannot_be_approved () =
  with_store (fun store ->
    let request = capture store "Legacy hash approval must fail closed" in
    let action = first_action store request.id in
    set_action_hash store action ~payload_hash:legacy_md5 ~status:ActionProposed;
    let before = review_snapshot store request.id action.id in
    expect_unsupported_hash "legacy approve" ~action_id:action.id
      ~payload_hash:legacy_md5
      (Runner.approve ~expected_payload_hash:legacy_md5 store action.id);
    if before <> review_snapshot store request.id action.id then
      failf "legacy approve changed persisted state")

let test_legacy_hash_cannot_execute_without_approval () =
  with_store (fun store ->
    let request = insert_test_request store ~status:ReadyForReview ~risk:L1 in
    let action =
      insert_test_action store ~request_id:request.id ~risk:L1
        ~target_kind:"pharos.local.complete_request" ~requires_approval:false
    in
    set_action_hash store action ~payload_hash:legacy_md5 ~status:ActionProposed;
    let before = review_snapshot store request.id action.id in
    expect_unsupported_hash "legacy execute" ~action_id:action.id
      ~payload_hash:legacy_md5 (Runner.execute_local store action.id);
    if before <> review_snapshot store request.id action.id then
      failf "legacy execute changed persisted state")

let test_legacy_approval_cannot_authorize_v2_action () =
  with_store (fun store ->
    let request = insert_test_request store ~status:Approved ~risk:L3 in
    let action =
      insert_test_action store ~request_id:request.id ~risk:L3
        ~target_kind:"pharos.local.complete_request" ~requires_approval:true
    in
    set_action_hash store action ~payload_hash:action.payload_hash
      ~status:ActionApproved;
    Store.insert_approval store
      {
        id = Ids.create "appr";
        action_id = action.id;
        action_hash = legacy_md5;
        decision = ApprovedDecision;
        approved_body = Some action.body;
        created_at = Time.now_iso ();
      };
    let before = review_snapshot store request.id action.id in
    begin match Runner.execute_local store action.id with
    | Error (Policy.ApprovalHashMismatch { action_hash; approval_hash }) ->
        expect_string "v2 action hash" action.payload_hash action_hash;
        expect_string "legacy approval hash" legacy_md5 approval_hash
    | Error err -> failf "unexpected error: %s" (Policy.error_to_string err)
    | Ok _ -> failf "legacy approval authorized a v2 action"
    end;
    if before <> review_snapshot store request.id action.id then
      failf "legacy approval execution changed persisted state")

let test_legacy_hash_can_be_rejected () =
  with_store (fun store ->
    let request = capture store "Legacy hash may still be rejected" in
    let action = first_action store request.id in
    set_action_hash store action ~payload_hash:legacy_md5 ~status:ActionProposed;
    ignore
      (Result.get_ok
         (Runner.reject ~expected_payload_hash:legacy_md5 store action.id));
    let persisted = reload_action store action.id in
    if persisted.status <> ActionRejected then
      failf "legacy reject did not reject the action")

let test_legacy_external_hash_is_blocked_and_logged () =
  with_store (fun store ->
    let request = insert_test_request store ~status:ReadyForReview ~risk:L3 in
    let action =
      insert_test_action store ~request_id:request.id ~risk:L3
        ~target_kind:"gitlab.mr.comment" ~requires_approval:true
    in
    set_action_hash store action ~payload_hash:legacy_md5 ~status:ActionProposed;
    expect_unsupported_hash "legacy external execute" ~action_id:action.id
      ~payload_hash:legacy_md5 (Runner.execute_local store action.id);
    let detail = Option.get (Runner.get_detail store request.id) in
    ignore (expect_timeline_kind detail "policy_block");
    match metric_today store with
    | Some metric when metric.unapproved_external_write_attempts = 1 -> ()
    | Some metric ->
        failf "expected 1 legacy external block, got %d"
          metric.unapproved_external_write_attempts
    | None -> failf "missing legacy external block metric")

let test_high_risk_actions_block risk =
  with_store (fun store ->
    let request = insert_test_request store ~status:ReadyForReview ~risk in
    let action =
      insert_test_action store ~request_id:request.id ~risk
        ~target_kind:"pharos.local.complete_request" ~requires_approval:true
    in
    expect_risk_error "approve high-risk action" risk
      (Runner.approve ~expected_payload_hash:action.payload_hash store action.id);
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

let test_stale_review_has_no_side_effect label review =
  with_store (fun store ->
    let request = capture store ("Stale " ^ label) in
    let shown_action = first_action store request.id in
    let refreshed_body = shown_action.body ^ " refreshed" in
    let refreshed_hash =
      payload_hash ~target_kind:shown_action.target_kind
        ~target_ref:shown_action.target_ref ~risk:shown_action.risk
        ~body:refreshed_body
    in
    Store.update_action_body_status_hash store ~action_id:shown_action.id
      ~body:refreshed_body ~payload_hash:refreshed_hash
      ~status:ActionProposed;
    let before = review_snapshot store request.id shown_action.id in
    expect_stale label ~action_id:shown_action.id
      ~expected_hash:shown_action.payload_hash ~actual_hash:refreshed_hash
      (review store shown_action);
    let after = review_snapshot store request.id shown_action.id in
    if before <> after then failf "%s: stale review changed persisted state" label)

let test_review_transaction_rolls_back label review =
  with_store (fun store ->
    let request = capture store ("Rollback " ^ label) in
    let action = first_action store request.id in
    let before = review_snapshot store request.id action.id in
    Store.exec store
      "CREATE TRIGGER fail_review_approval BEFORE INSERT ON approvals BEGIN SELECT RAISE(ABORT, 'forced review failure'); END";
    begin
      match review store action with
      | exception Failure _ -> ()
      | _ -> failf "%s: forced SQL failure did not escape" label
    end;
    let after = review_snapshot store request.id action.id in
    if before <> after then
      failf "%s: review transaction did not fully roll back" label)

let test_review_requires_proposed_status () =
  with_store (fun store ->
    let request = capture store "Double approval must be stale" in
    let action = first_action store request.id in
    ignore
      (Result.get_ok
         (Runner.approve ~expected_payload_hash:action.payload_hash store
            action.id));
    let approved_action = reload_action store action.id in
    let before = review_snapshot store request.id action.id in
    expect_stale "approved status CAS" ~action_id:action.id
      ~expected_hash:approved_action.payload_hash
      ~actual_hash:approved_action.payload_hash
      (Runner.reject ~expected_payload_hash:approved_action.payload_hash store
         action.id);
    if before <> review_snapshot store request.id action.id then
      failf "status CAS failure changed persisted state")

let () =
  Random.self_init ();
  test_execution_requires_approval ();
  test_edit_and_approve_updates_hash ();
  test_hash_mismatch_blocks_execution ();
  test_action_field_tamper_blocks_execution "body"
    (fun action -> { action with body = action.body ^ " tampered" });
  test_action_field_tamper_blocks_execution "target kind"
    (fun action -> { action with target_kind = "pharos.local.other" });
  test_action_field_tamper_blocks_execution "target ref"
    (fun action -> { action with target_ref = action.target_ref ^ "-tampered" });
  test_action_field_tamper_blocks_execution "risk"
    (fun action ->
      { action with risk = (if action.risk = L2 then L1 else L2) });
  test_proposed_action_cannot_reuse_matching_historical_approval ();
  test_rejection_blocks_execution ();
  test_legacy_hash_cannot_be_approved ();
  test_legacy_hash_cannot_execute_without_approval ();
  test_legacy_approval_cannot_authorize_v2_action ();
  test_legacy_hash_can_be_rejected ();
  test_legacy_external_hash_is_blocked_and_logged ();
  test_high_risk_actions_block L4;
  test_high_risk_actions_block L5;
  test_external_target_blocked_and_logged ();
  test_external_target_blocked_and_logged ~risk:L5 ();
  test_stale_review_has_no_side_effect "approve"
    (fun store action ->
      Runner.approve ~expected_payload_hash:action.payload_hash store action.id);
  test_stale_review_has_no_side_effect "edit-and-approve"
    (fun store action ->
      Runner.approve ~edited_body:"edited stale body"
        ~expected_payload_hash:action.payload_hash store action.id);
  test_stale_review_has_no_side_effect "reject"
    (fun store action ->
      Runner.reject ~expected_payload_hash:action.payload_hash store action.id);
  test_review_transaction_rolls_back "approve"
    (fun store action ->
      Runner.approve ~expected_payload_hash:action.payload_hash store action.id);
  test_review_transaction_rolls_back "reject"
    (fun store action ->
      Runner.reject ~expected_payload_hash:action.payload_hash store action.id);
  test_review_requires_proposed_status ()
