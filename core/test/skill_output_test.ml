open Pharos_core
open Pharos_core.Domain

let failf fmt = Printf.ksprintf failwith fmt

let contains haystack needle =
  let haystack_len = String.length haystack in
  let needle_len = String.length needle in
  let rec loop index =
    index + needle_len <= haystack_len
    && (String.sub haystack index needle_len = needle || loop (index + 1))
  in
  needle_len = 0 || loop 0

let expect_error_containing label needle = function
  | Error error when contains error needle -> ()
  | Error error -> failf "%s: unexpected error %S" label error
  | Ok _ -> failf "%s: expected validation error" label

let temp_db () =
  Filename.concat (Filename.get_temp_dir_name ())
    ("pharos_skills_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let valid_triage_json ?(priority = "normal") ?(risk = "l1") () =
  `Assoc [
    ("should_create_request", `Bool true);
    ("request_type", `String "gitlab_mr_review");
    ("priority", `String priority);
    ("risk", `String risk);
    ("reason", `String "You were requested as reviewer.");
    ("next_step", `String "Prepare a review summary and comment draft.");
    ("needs_context", `Bool false);
    ("notify_user", `Bool false);
    ("evidence_refs", `List [ `String "ev_fixture" ]);
  ]

let test_triage_parser () =
  let output = Result.get_ok (Skill.parse_triage_output (valid_triage_json ())) in
  if output.priority <> Normal then failf "valid triage priority did not parse";
  if output.risk <> L1 then failf "valid triage risk did not parse";
  expect_error_containing "invalid priority" "Invalid priority"
    (Skill.parse_triage_output (valid_triage_json ~priority:"critical" ()));
  expect_error_containing "invalid risk" "Invalid risk"
    (Skill.parse_triage_output (valid_triage_json ~risk:"l9" ()))

let gitlab_input () : Runner.source_signal_input =
  {
    kind = GitLab;
    external_id = Some "gitlab:project/123:mr/456";
    actor = "alice";
    title = "Review requested: billing retry logic";
    body = "Alice requested your review. Pipeline is failing in retry policy tests.";
    url = Some "https://gitlab.example/group/project/-/merge_requests/456";
    occurred_at = "2026-07-07T09:30:00Z";
    raw_json = Some {|{"object_kind":"merge_request","project_id":123,"iid":456}|};
  }

let only_action store request_id =
  match Runner.get_detail store request_id with
  | None -> failf "missing request detail"
  | Some detail ->
      begin match detail.actions with
      | [ action ] -> action
      | actions -> failf "expected one action, got %d" (List.length actions)
      end

let test_gitlab_skill_prepares_but_cannot_execute () =
  with_store (fun store ->
    let response = Runner.ingest_source_signal store (gitlab_input ()) in
    let action = only_action store response.request.id in
    if action.target_kind <> "gitlab.mr.comment" then
      failf "unexpected GitLab target kind: %s" action.target_kind;
    if action.target_ref <> "project_id=123;mr_iid=456" then
      failf "unexpected GitLab target ref: %s" action.target_ref;
    if not action.requires_approval then
      failf "GitLab comment draft must require approval";
    if not (contains action.body "Evidence refs: ev_") then
      failf "GitLab action body must expose evidence refs";
    begin match Runner.execute_local store action.id with
    | Error (Policy.ExternalWritebackNotImplemented "gitlab.mr.comment") -> ()
    | Error error -> failf "unexpected policy error: %s" (Policy.error_to_string error)
    | Ok _ -> failf "a built-in skill action executed an external writeback"
    end)

let test_feishu_chat_skill_prepares_reply_draft () =
  with_store (fun store ->
    let input : Runner.source_signal_input = {
      kind = FeishuChat;
      external_id = Some "feishu:chat/oc_abc:message/msg_123";
      actor = "bob";
      title = "Bob asked about rollout timing";
      body = "Can we confirm the rollout window today?";
      url = Some "https://feishu.example/messages/msg_123";
      occurred_at = "2026-07-07T10:05:00Z";
      raw_json = Some {|{"chat_id":"oc_abc","message_id":"msg_123"}|};
    } in
    let response = Runner.ingest_source_signal store input in
    let action = only_action store response.request.id in
    if action.target_kind <> "feishu.chat.reply" then
      failf "unexpected Feishu target kind: %s" action.target_kind;
    if action.target_ref <> "feishu:chat/oc_abc:message/msg_123" then
      failf "unexpected Feishu target ref: %s" action.target_ref;
    if action.risk <> L3 || not action.requires_approval then
      failf "Feishu reply draft must be l3 and require approval")

let test_missing_gitlab_provenance_needs_context () =
  with_store (fun store ->
    let input = { (gitlab_input ()) with external_id = None } in
    let response = Runner.ingest_source_signal store input in
    let detail = Option.get (Runner.get_detail store response.request.id) in
    if detail.request.status <> NeedsContext then
      failf "missing GitLab provenance should need context";
    if detail.actions <> [] then
      failf "missing GitLab provenance created an action")

let insert_invalid_output_fixture store =
  let now = Time.now_iso () in
  let request : work_request = {
    id = Ids.create "req";
    title = "Invalid skill output";
    summary = "Parser failure fixture";
    status = Triaging;
    priority = Normal;
    risk = L1;
    source_kind = GitLab;
    source_signal_id = "sig_invalid_skill";
    reason = "testing invalid output";
    next_step = "validate output";
    created_at = now;
    updated_at = now;
  } in
  Store.insert_work_request store request;
  Store.insert_evidence store {
    id = "ev_invalid_skill";
    request_id = request.id;
    kind = "source.gitlab";
    title = "Invalid output fixture";
    body = "Fixture evidence";
    url = None;
    created_at = now;
  };
  request

let invalid_gitlab_output =
  `Assoc [
    ("summary", `String "summary");
    ("risk_points", `List []);
    ("test_gaps", `List []);
    ("draft_comment", `String "draft");
    ("target_kind", `String "gitlab.mr.comment");
    ("target_ref", `String "project_id=123;mr_iid=456");
    ("risk", `String "l9");
    ("requires_approval", `Bool true);
    ("evidence_refs", `List [ `String "ev_invalid_skill" ]);
  ]

let test_invalid_output_records_visible_error_without_action () =
  with_store (fun store ->
    let request = insert_invalid_output_fixture store in
    let result =
      Runner.apply_gitlab_mr_review_output_json store ~request
        invalid_gitlab_output
    in
    if Option.is_some result then failf "invalid skill output created an action";
    let detail = Option.get (Runner.get_detail store request.id) in
    if detail.actions <> [] then failf "invalid skill output persisted an action";
    if detail.request.status <> NeedsContext then
      failf "invalid skill output should move request to needs_context";
    match List.find_opt
      (fun (event : timeline_event) -> event.kind = "skill_error") detail.timeline
    with
    | None -> failf "invalid skill output did not create skill_error timeline"
    | Some event when contains event.body "Invalid risk: l9" -> ()
    | Some event -> failf "skill_error reason is not visible: %S" event.body)

let invalid_policy_gitlab_output request_id =
  `Assoc [
    ("summary", `String "Bypass review");
    ("risk_points", `List []);
    ("test_gaps", `List []);
    ("draft_comment", `String "Complete without review");
    ("target_kind", `String "pharos.local.complete_request");
    ("target_ref", `String request_id);
    ("risk", `String "l2");
    ("requires_approval", `Bool false);
    ("evidence_refs", `List [ `String "ev_invalid_skill" ]);
  ]

let test_invalid_policy_output_is_rejected () =
  with_store (fun store ->
    let request = insert_invalid_output_fixture store in
    let result =
      Runner.apply_gitlab_mr_review_output_json store ~request
        (invalid_policy_gitlab_output request.id)
    in
    if Option.is_some result then failf "invalid policy output was accepted";
    let detail = Option.get (Runner.get_detail store request.id) in
    if detail.actions <> [] then failf "policy bypass persisted an action";
    if detail.request.status <> NeedsContext then
      failf "policy bypass should fail closed to needs_context")

let test_source_bundle_rolls_back_on_action_failure () =
  with_store (fun store ->
    Store.exec store {|
      CREATE TRIGGER fail_skill_action_insert
      BEFORE INSERT ON proposed_actions
      BEGIN
        SELECT RAISE(ABORT, 'forced action insert failure');
      END
    |};
    begin match Runner.ingest_source_signal store (gitlab_input ()) with
    | _ -> failf "forced action insert failure did not abort ingestion"
    | exception Failure _ -> ()
    end;
    Store.exec store "DROP TRIGGER fail_skill_action_insert";
    if Store.list_work_requests store <> [] then
      failf "failed source bundle left a work request";
    if Option.is_some
        (Store.get_work_request_identity store
          "gitlab:gitlab:project/123:mr/456") then
      failf "failed source bundle left an identity binding";
    if Option.is_some (Store.get_metric_for_day store (Time.today_utc ())) then
      failf "failed source bundle left metric writes";
    let retry = Runner.ingest_source_signal store (gitlab_input ()) in
    if retry.merged then failf "retry after rollback should create a new request";
    ignore (only_action store retry.request.id))

let () =
  Random.self_init ();
  test_triage_parser ();
  test_gitlab_skill_prepares_but_cannot_execute ();
  test_feishu_chat_skill_prepares_reply_draft ();
  test_missing_gitlab_provenance_needs_context ();
  test_invalid_output_records_visible_error_without_action ();
  test_invalid_policy_output_is_rejected ();
  test_source_bundle_rolls_back_on_action_failure ()
