open Pharos_core
open Pharos_core.Domain

let failf fmt = Printf.ksprintf failwith fmt

let temp_db () =
  Filename.concat (Filename.get_temp_dir_name ())
    ("pharos_writeback_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let gitlab_input () : Runner.source_signal_input =
  {
    kind = GitLab;
    external_id = Some "gitlab:project/123:mr/456";
    actor = "alice";
    title = "Review requested: billing retry logic";
    body = "Alice requested your review. Pipeline is passing.";
    url = Some "https://gitlab.example/group/project/-/merge_requests/456";
    occurred_at = "2026-07-11T00:00:00Z";
    raw_json = Some {|{"project_id":123,"iid":456}|};
  }

let only_action store request_id =
  match Runner.get_detail store request_id with
  | Some { actions = [ action ]; _ } -> action
  | Some detail -> failf "expected one action, got %d" (List.length detail.actions)
  | None -> failf "missing request detail"

let prepare store =
  let response = Runner.ingest_source_signal store (gitlab_input ()) in
  (response.request, only_action store response.request.id)

let patch_gitlab_source store ~enabled ~write_enabled ~scope_json =
  Source_settings.patch_source store (Store.source_config_id GitLab)
    {
      enabled = Some enabled;
      read_enabled = None;
      write_enabled = Some write_enabled;
      scope_json = Some scope_json;
    }
  |> Result.get_ok |> ignore

let enable_write store =
  patch_gitlab_source store ~enabled:true ~write_enabled:true ~scope_json:"{}"

let approve store (action : proposed_action) =
  Runner.approve ~expected_payload_hash:action.payload_hash store action.id
  |> Result.get_ok

let update_action store (action : proposed_action) ?(body = action.body)
    ?(target_kind = action.target_kind) ?(target_ref = action.target_ref)
    ?(risk = action.risk) ?(status = ActionProposed) () =
  let updated =
    {
      action with
      body;
      target_kind;
      target_ref;
      risk;
      status;
      payload_hash = payload_hash ~target_kind ~target_ref ~risk ~body;
      updated_at = Time.now_iso ();
    }
  in
  Store.update_action_from_skill store updated;
  updated

let insert_matching_approval store (action : proposed_action) =
  let approval =
    {
      id = Ids.create "appr";
      action_id = action.id;
      action_hash = action.payload_hash;
      decision = ApprovedDecision;
      approved_body = Some action.body;
      created_at = Time.now_iso ();
    }
  in
  Store.insert_approval store approval;
  Store.update_action_status store ~action_id:action.id ~status:ActionApproved;
  Store.update_request_status store ~request_id:action.request_id ~status:Approved;
  approval

type fake = {
  posts : Gitlab_write.request list ref;
  reconciliations : Gitlab_write.request list ref;
  post_outcome : Gitlab_write.delivery_outcome ref;
  reconciliation_outcome : Gitlab_write.reconciliation_outcome ref;
}

let confirmed =
  Gitlab_write.Confirmed
    {
      external_id = "note_123";
      external_url =
        "https://gitlab.example/group/project/-/merge_requests/456#note_123";
    }

let make_fake ?(post_outcome = confirmed)
    ?(reconciliation_outcome = Gitlab_write.Marker_not_found) () =
  let fake =
    {
      posts = ref [];
      reconciliations = ref [];
      post_outcome = ref post_outcome;
      reconciliation_outcome = ref reconciliation_outcome;
    }
  in
  let client : Gitlab_write.client =
    {
      post =
        (fun request ->
          fake.posts := request :: !(fake.posts);
          !(fake.post_outcome));
      reconcile =
        (fun request ->
          fake.reconciliations := request :: !(fake.reconciliations);
          !(fake.reconciliation_outcome));
    }
  in
  (fake, client)

let post_count fake = List.length !(fake.posts)
let reconciliation_count fake = List.length !(fake.reconciliations)

let expect_error label predicate = function
  | Error error when predicate error -> ()
  | Error error ->
      failf "%s: unexpected error %s" label (Policy.error_to_string error)
  | Ok _ -> failf "%s: expected policy error" label

let expect_no_post label fake =
  if post_count fake <> 0 then failf "%s called the GitLab POST client" label

let expect_preflight_block label
    (prepare_case : Store.t -> proposed_action -> proposed_action) predicate =
  with_store (fun store ->
    let _, action = prepare store in
    let action = prepare_case store action in
    let fake, client = make_fake () in
    Runner.execute_approved ~client store action.id
    |> expect_error label predicate;
    expect_no_post label fake)

let test_unapproved_blocks_before_client () =
  expect_preflight_block "unapproved"
    (fun store action ->
      enable_write store;
      action)
    (function Policy.ApprovalRequired _ -> true | _ -> false)

let test_stale_approval_blocks_before_client () =
  expect_preflight_block "stale approval"
    (fun store action ->
      enable_write store;
      ignore (approve store action);
      update_action store action ~body:"Changed after approval"
        ~status:ActionApproved ())
    (function Policy.ApprovalHashMismatch _ -> true | _ -> false)

let test_legacy_hash_blocks_before_client () =
  expect_preflight_block "legacy hash"
    (fun store action ->
      enable_write store;
      let action = update_action store action ~status:ActionApproved () in
      let legacy = "0123456789abcdef0123456789abcdef" in
      Store.update_action_body_status_hash store ~action_id:action.id
        ~body:action.body ~payload_hash:legacy ~status:ActionApproved;
      ignore
        (insert_matching_approval store { action with payload_hash = legacy });
      { action with payload_hash = legacy })
    (function Policy.UnsupportedPayloadHash _ -> true | _ -> false)

let test_risk_blocks_before_client risk =
  expect_preflight_block ("risk " ^ risk_to_string risk)
    (fun store action ->
      enable_write store;
      let action = update_action store action ~risk ~status:ActionApproved () in
      ignore (insert_matching_approval store action);
      action)
    (function
      | Policy.ExternalWritebackRiskMismatch actual -> actual = risk
      | _ -> false)

let test_source_policy_blocks_before_client () =
  expect_preflight_block "source disabled"
    (fun store action ->
      patch_gitlab_source store ~enabled:false ~write_enabled:false
        ~scope_json:"{}";
      ignore (approve store action);
      Option.get (Store.get_action store action.id))
    (function Policy.SourceWriteDisabled GitLab -> true | _ -> false);
  expect_preflight_block "write disabled"
    (fun store action ->
      patch_gitlab_source store ~enabled:true ~write_enabled:false
        ~scope_json:"{}";
      ignore (approve store action);
      Option.get (Store.get_action store action.id))
    (function Policy.SourceWriteDisabled GitLab -> true | _ -> false);
  expect_preflight_block "enabled false write true"
    (fun store action ->
      patch_gitlab_source store ~enabled:false ~write_enabled:true
        ~scope_json:"{}";
      ignore (approve store action);
      Option.get (Store.get_action store action.id))
    (function Policy.SourceWriteDisabled GitLab -> true | _ -> false);
  expect_preflight_block "invalid persisted scope"
    (fun store action ->
      ignore
        (Store.patch_source store (Store.source_config_id GitLab)
           {
             enabled = Some true;
             read_enabled = None;
             write_enabled = Some true;
             scope_json = Some "invalid";
           });
      ignore (approve store action);
      Option.get (Store.get_action store action.id))
    (function Policy.SourcePolicyInvalid _ -> true | _ -> false)

let test_body_blocks_before_client body predicate =
  expect_preflight_block "invalid body"
    (fun store action ->
      enable_write store;
      let action = update_action store action ~body () in
      ignore (approve store action);
      Option.get (Store.get_action store action.id))
    predicate

let test_target_blocks_before_client ~target_kind ~target_ref predicate =
  expect_preflight_block "invalid target"
    (fun store action ->
      enable_write store;
      let action = update_action store action ~target_kind ~target_ref () in
      ignore (approve store action);
      Option.get (Store.get_action store action.id))
    predicate

let test_preflight_negatives () =
  test_unapproved_blocks_before_client ();
  test_stale_approval_blocks_before_client ();
  test_legacy_hash_blocks_before_client ();
  test_risk_blocks_before_client L4;
  test_risk_blocks_before_client L5;
  test_source_policy_blocks_before_client ();
  test_body_blocks_before_client "   " (function
    | Policy.ActionBodyEmpty _ -> true
    | _ -> false);
  test_body_blocks_before_client (String.make 8001 'x') (function
    | Policy.ActionBodyTooLong _ -> true
    | _ -> false);
  test_target_blocks_before_client ~target_kind:"gitlab.mr.approve"
    ~target_ref:"project_id=123;mr_iid=456" (function
    | Policy.ExternalTargetNotAllowed _ -> true
    | _ -> false);
  test_target_blocks_before_client ~target_kind:"gitlab.mr.comment"
    ~target_ref:"project_id=123" (function
    | Policy.ExternalTargetInvalid _ -> true
    | _ -> false);
  test_target_blocks_before_client ~target_kind:"gitlab.mr.comment"
    ~target_ref:"project_id=123;mr_iid=999" (function
    | Policy.TargetProvenanceMismatch _ -> true
    | _ -> false);
  test_target_blocks_before_client ~target_kind:"gitlab.issue.comment"
    ~target_ref:"project_id=123;issue_iid=456" (function
    | Policy.TargetProvenanceMismatch _ -> true
    | _ -> false)

let test_confirmed_writeback_and_watched_projects () =
  with_store (fun store ->
    let request, action = prepare store in
    patch_gitlab_source store ~enabled:true ~write_enabled:true
      ~scope_json:{|{"projects":[999]}|};
    let edited_body = "Edited review approved by the user." in
    let approval =
      Runner.approve ~edited_body ~expected_payload_hash:action.payload_hash
        store action.id
      |> Result.get_ok
    in
    let fake, client = make_fake () in
    let action, attempt =
      Runner.execute_approved ~client store action.id |> Result.get_ok
    in
    if post_count fake <> 1 then failf "confirmed writeback POST count was not 1";
    if action.status <> ActionExecuted then failf "confirmed action not executed";
    if attempt.status <> WritebackConfirmed then
      failf "confirmed attempt has wrong status";
    if attempt.approval_id <> approval.id then failf "attempt approval id mismatch";
    let expected_marker =
      Gitlab_write.marker ~attempt_id:attempt.id
        ~payload_hash:action.payload_hash
      |> Result.get_ok
    in
    if attempt.marker <> expected_marker then
      failf "marker does not bind attempt id and complete payload hash";
    begin
      match !(fake.posts) with
      | [ posted ] ->
          if posted.body <> edited_body then failf "client received wrong body";
          if
            not
              (Gitlab_write.body_with_marker ~body:posted.body
                 ~marker:posted.marker
              |> String.ends_with ~suffix:posted.marker)
          then failf "marker did not round-trip as an exact final line"
      | _ -> failf "missing confirmed fake request"
    end;
    let detail = Option.get (Runner.get_detail store request.id) in
    if List.length detail.writeback_attempts <> 1 then
      failf "request detail omitted durable attempt";
    if
      not
        (List.exists
           (fun (event : timeline_event) ->
             event.kind = "writeback_confirmed")
           detail.timeline)
    then failf "confirmed timeline missing";
    if
      not
        (List.exists
           (fun (item : evidence_item) ->
             item.kind = "writeback.gitlab.comment")
           detail.evidence)
    then failf "confirmed evidence missing";
    let metric = Option.get (Store.get_metric_for_day store (Time.today_utc ())) in
    if metric.external_writes <> 1 then failf "external write metric not bumped";
    Runner.execute_approved ~client store action.id
    |> expect_error "confirmed action second execute" (function
      | Policy.ActionNotExecutableState { status = ActionExecuted; _ } -> true
      | _ -> false);
    if post_count fake <> 1 then failf "confirmed action posted twice")

let test_failed_before_send_is_retryable () =
  with_store (fun store ->
    let _, action = prepare store in
    enable_write store;
    ignore (approve store action);
    let fake, client =
      make_fake ~post_outcome:(Gitlab_write.Failed_before_send "missing config")
        ()
    in
    let action, failed =
      Runner.execute_approved ~client store action.id |> Result.get_ok
    in
    if failed.status <> WritebackFailedBeforeSend then
      failf "pre-send failure has wrong status";
    if action.status <> ActionApproved then
      failf "pre-send failure did not restore approved action";
    fake.post_outcome := confirmed;
    let _, retried =
      Runner.execute_approved ~client store action.id |> Result.get_ok
    in
    if retried.status <> WritebackConfirmed then failf "safe retry not confirmed";
    if post_count fake <> 2 then failf "safe retry client count was not 2")

let unknown_outcome = Gitlab_write.Unknown "response lost after remote create"

let prepare_unknown store =
  let _, action = prepare store in
  enable_write store;
  let approval = approve store action in
  let fake, client = make_fake ~post_outcome:unknown_outcome () in
  let action, attempt =
    Runner.execute_approved ~client store action.id |> Result.get_ok
  in
  (action, approval, attempt, fake, client)

let test_unknown_never_posts_twice () =
  with_store (fun store ->
    let action, _, attempt, fake, client = prepare_unknown store in
    if attempt.status <> WritebackUnknown then failf "unknown status not persisted";
    if action.status <> ActionExecuting then failf "unknown action not executing";
    Runner.execute_approved ~client store action.id
    |> expect_error "unknown second execute" (function
      | Policy.WritebackAttemptActive
          { status = WritebackUnknown; _ } -> true
      | _ -> false);
    if post_count fake <> 1 then failf "unknown attempt issued a second POST")

let test_reconciliation_confirms_without_second_post () =
  with_store (fun store ->
    let _, _, attempt, fake, client = prepare_unknown store in
    fake.reconciliation_outcome :=
      Gitlab_write.Reconciled
        {
          external_id = "note_123";
          external_url =
            "https://gitlab.example/group/project/-/merge_requests/456#note_123";
        };
    let action, reconciled =
      Runner.reconcile_writeback ~client store attempt.id |> Result.get_ok
    in
    if action.status <> ActionExecuted then failf "reconciled action not executed";
    if reconciled.status <> WritebackConfirmed then
      failf "reconciled attempt not confirmed";
    if post_count fake <> 1 then failf "reconciliation issued another POST";
    if reconciliation_count fake <> 1 then
      failf "reconciliation GET count was not 1")

let test_reconciliation_claim_blocks_competitors_and_can_confirm () =
  with_store (fun store ->
    let _, _, attempt, fake, _ = prepare_unknown store in
    let operation =
      Runner.prepare_reconciliation store attempt.id |> Result.get_ok
    in
    let claimed = Option.get (Store.get_writeback_attempt store attempt.id) in
    if claimed.status <> WritebackInFlight then
      failf "reconciliation did not claim unknown attempt";
    Runner.prepare_reconciliation store attempt.id
    |> expect_error "concurrent reconciliation claim" (function
      | Policy.WritebackAttemptStateMismatch
          { status = WritebackInFlight; _ } -> true
      | _ -> false);
    Runner.abandon_writeback store attempt.id
    |> expect_error "abandon during reconciliation" (function
      | Policy.WritebackAttemptStateMismatch
          { status = WritebackInFlight; _ } -> true
      | _ -> false);
    let action, reconciled =
      Runner.finish_reconciliation store operation
        (Gitlab_write.Reconciled
           {
             external_id = "note_123";
             external_url =
               "https://gitlab.example/group/project/-/merge_requests/456#note_123";
           })
      |> Result.get_ok
    in
    if action.status <> ActionExecuted then
      failf "claimed reconciliation did not execute action";
    if reconciled.status <> WritebackConfirmed then
      failf "claimed reconciliation did not confirm attempt";
    if post_count fake <> 1 then
      failf "claimed reconciliation issued another POST")

let test_marker_not_found_remains_unknown () =
  with_store (fun store ->
    let _, _, attempt, fake, client = prepare_unknown store in
    let _, reconciled =
      Runner.reconcile_writeback ~client store attempt.id |> Result.get_ok
    in
    if reconciled.status <> WritebackUnknown then
      failf "missing marker guessed non-delivery";
    if post_count fake <> 1 then failf "missing marker issued another POST")

let test_reconciliation_error_remains_unknown () =
  with_store (fun store ->
    let _, _, attempt, fake, client = prepare_unknown store in
    fake.reconciliation_outcome :=
      Gitlab_write.Reconciliation_unknown "connection interrupted";
    let _, reconciled =
      Runner.reconcile_writeback ~client store attempt.id |> Result.get_ok
    in
    if reconciled.status <> WritebackUnknown then
      failf "reconciliation error did not restore unknown";
    if post_count fake <> 1 then
      failf "reconciliation error issued another POST")

let test_reconciliation_claim_recovery_becomes_unknown () =
  with_store (fun store ->
    let _, _, attempt, _, _ = prepare_unknown store in
    ignore (Runner.prepare_reconciliation store attempt.id |> Result.get_ok);
    Runner.recover_interrupted_writebacks store;
    let recovered = Option.get (Store.get_writeback_attempt store attempt.id) in
    if recovered.status <> WritebackUnknown then
      failf "reconciliation claim recovery did not become unknown")

let test_in_flight_recovery_becomes_unknown () =
  with_store (fun store ->
    let _, action = prepare store in
    enable_write store;
    ignore (approve store action);
    let operation = Runner.start_writeback store action.id |> Result.get_ok in
    Runner.recover_interrupted_writebacks store;
    let attempt =
      Option.get (Store.get_writeback_attempt store operation.attempt.id)
    in
    if attempt.status <> WritebackUnknown then
      failf "in-flight recovery did not become unknown";
    let fake, client = make_fake () in
    Runner.execute_approved ~client store action.id
    |> expect_error "recovered unknown execute" (function
      | Policy.WritebackAttemptActive
          { status = WritebackUnknown; _ } -> true
      | _ -> false);
    expect_no_post "recovered unknown execute" fake)

let test_prepared_recovery_is_retryable () =
  with_store (fun store ->
    let _, action = prepare store in
    enable_write store;
    ignore (approve store action);
    let operation = Policy.prepare_writeback store action.id |> Result.get_ok in
    Runner.recover_interrupted_writebacks store;
    let attempt =
      Option.get (Store.get_writeback_attempt store operation.attempt.id)
    in
    let action = Option.get (Store.get_action store action.id) in
    if attempt.status <> WritebackFailedBeforeSend then
      failf "prepared recovery was not retry-safe";
    if action.status <> ActionApproved then
      failf "prepared recovery did not restore approval")

let test_abandon_requires_fresh_approval () =
  with_store (fun store ->
    let _action, old_approval, attempt, fake, client = prepare_unknown store in
    let action, abandoned =
      Runner.abandon_writeback store attempt.id |> Result.get_ok
    in
    if abandoned.status <> WritebackAbandoned then failf "attempt not abandoned";
    if action.status <> ActionProposed then failf "abandon did not repropose action";
    Runner.execute_approved ~client store action.id
    |> expect_error "abandon without fresh approval" (function
      | Policy.ApprovalRequired _ -> true
      | _ -> false);
    if post_count fake <> 1 then failf "abandon retried before approval";
    let fresh = approve store action in
    if fresh.id = old_approval.id then failf "abandon reused old approval";
    fake.post_outcome := confirmed;
    let _, retried =
      Runner.execute_approved ~client store action.id |> Result.get_ok
    in
    if retried.status <> WritebackConfirmed then
      failf "freshly approved abandon retry not confirmed";
    if post_count fake <> 2 then failf "fresh approval did not issue one new POST")

let with_environment name value f =
  let previous = Sys.getenv_opt name in
  Unix.putenv name value;
  Fun.protect
    ~finally:(fun () -> Unix.putenv name (Option.value previous ~default:""))
    f

let test_real_client_rejects_plain_http_before_send () =
  with_environment "PHAROS_GITLAB_BASE_URL" "http://gitlab.example" (fun () ->
    with_environment "PHAROS_GITLAB_TOKEN" "test-token" (fun () ->
      let target =
        Gitlab_write.{ project_id = 123; object_kind = MergeRequest; iid = 456 }
      in
      let marker_value =
        Gitlab_write.marker ~attempt_id:"wb_test"
          ~payload_hash:
            "sha256:6f61c67b639f2adab56d4cec560d4a18fbf805531cebdc6fd8f74d0cce6e46f4"
        |> Result.get_ok
      in
      let request : Gitlab_write.request =
        {
          target;
          source_url = None;
          body = "review";
          marker = marker_value;
        }
      in
      match Gitlab_write.real_client.post request with
      | Failed_before_send error
        when String.starts_with ~prefix:"PHAROS_GITLAB_BASE_URL" error -> ()
      | Failed_before_send error -> failf "unexpected config error: %s" error
      | Confirmed _ | Unknown _ -> failf "plain HTTP reached a send outcome"))

let test_marker_matching_requires_an_exact_line () =
  let marker =
    Gitlab_write.marker ~attempt_id:"wb_test"
      ~payload_hash:
        "sha256:6f61c67b639f2adab56d4cec560d4a18fbf805531cebdc6fd8f74d0cce6e46f4"
    |> Result.get_ok
  in
  let body = Gitlab_write.body_with_marker ~body:"review" ~marker in
  if not (Gitlab_write.marker_is_exact_line body marker) then
    failf "complete marker line was not found";
  List.iter
    (fun candidate ->
      if Gitlab_write.marker_is_exact_line candidate marker then
        failf "partial marker matched: %s" candidate)
    [ "prefix " ^ marker; marker ^ " suffix"; "`" ^ marker ^ "`" ]

let test_fallback_external_url_is_target_bound () =
  let target =
    Gitlab_write.{ project_id = 123; object_kind = MergeRequest; iid = 456 }
  in
  let fallback source_url =
    Gitlab_write.fallback_external_url
      ~base_url:"https://gitlab.example" ~target ~source_url ~note_id:"123"
  in
  let source =
    "https://gitlab.example/group/project/-/merge_requests/456?view=diffs#old"
  in
  let expected_source =
    "https://gitlab.example/group/project/-/merge_requests/456#note_123"
  in
  if fallback (Some source) <> expected_source then
    failf "matching source URL was not used for note fallback";
  let expected_api =
    "https://gitlab.example/api/v4/projects/123/merge_requests/456/notes/123"
  in
  List.iter
    (fun untrusted ->
      let actual = fallback (Some untrusted) in
      if actual <> expected_api then
        failf "untrusted source URL produced %s" actual)
    [
      "https://gitlab.example.evil/group/project/-/merge_requests/456";
      "https://other.example/group/project/-/merge_requests/456";
      "https://gitlab.example/group/project/-/merge_requests/999";
      "https://gitlab.example/group/project/-/issues/456";
      "https://gitlab.example/group/project/-/merge_requests/456/notes";
    ];
  if fallback None <> expected_api then
    failf "missing source URL did not produce exact note API resource"

let () =
  Random.self_init ();
  test_preflight_negatives ();
  test_confirmed_writeback_and_watched_projects ();
  test_failed_before_send_is_retryable ();
  test_unknown_never_posts_twice ();
  test_reconciliation_confirms_without_second_post ();
  test_reconciliation_claim_blocks_competitors_and_can_confirm ();
  test_marker_not_found_remains_unknown ();
  test_reconciliation_error_remains_unknown ();
  test_reconciliation_claim_recovery_becomes_unknown ();
  test_in_flight_recovery_becomes_unknown ();
  test_prepared_recovery_is_retryable ();
  test_abandon_requires_fresh_approval ();
  test_real_client_rejects_plain_http_before_send ();
  test_marker_matching_requires_an_exact_line ();
  test_fallback_external_url_is_target_bound ()
