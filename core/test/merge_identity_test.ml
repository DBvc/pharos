open Pharos_core
open Pharos_core.Domain

let temp_db () =
  Filename.concat
    (Filename.get_temp_dir_name ())
    ("pharos_merge_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let failf fmt = Printf.ksprintf failwith fmt

let expect_bool label expected actual =
  if expected <> actual then
    failf "%s: expected %b, got %b" label expected actual

let expect_int label expected actual =
  if expected <> actual then
    failf "%s: expected %d, got %d" label expected actual

let expect_string label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label expected actual

let contains haystack needle =
  let haystack_len = String.length haystack in
  let needle_len = String.length needle in
  let rec loop index =
    index + needle_len <= haystack_len
    && (String.sub haystack index needle_len = needle || loop (index + 1))
  in
  needle_len = 0 || loop 0

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let gitlab_input ?(title = "Review requested: billing retry logic")
    ?(body = "Alice requested your review on MR !456.")
    ?(raw_json = {|{"project_id":123,"iid":456}|}) () :
    Runner.source_signal_input =
  {
    kind = GitLab;
    external_id = Some "gitlab:project/123:mr/456";
    actor = "alice";
    title;
    body;
    url = Some "https://gitlab.example/group/project/-/merge_requests/456?utm_source=test";
    occurred_at = "2026-07-08T00:00:00Z";
    raw_json = Some raw_json;
  }

let feishu_url_input ?external_id ?url
    ?(title = "Doc comment needs owner response") () :
    Runner.source_signal_input =
  {
    kind = FeishuDocs;
    external_id;
    actor = "dana";
    title;
    body = "Dana mentioned you in a product spec comment asking for the owner response.";
    url;
    occurred_at = "2026-07-08T01:00:00Z";
    raw_json = Some {|{"doc_id":"doc_123"}|};
  }

let detail store request_id =
  match Runner.get_detail store request_id with
  | Some detail -> detail
  | None -> failf "missing detail for %s" request_id

let first_action detail =
  match detail.actions with
  | action :: _ -> action
  | [] -> failf "missing action for %s" detail.request.id

let count_timeline kind (detail : request_detail) =
  detail.timeline
  |> List.filter (fun (event : timeline_event) -> event.kind = kind)
  |> List.length

let test_replay_merges_same_identity () =
  with_store (fun store ->
    let first = Runner.ingest_source_signal store (gitlab_input ()) in
    let second = Runner.ingest_source_signal store (gitlab_input ()) in
    expect_bool "first replay merged" false first.merged;
    expect_bool "second replay merged" true second.merged;
    expect_string "same request id" first.request.id second.request.id;
    let today = Runner.today store in
    expect_int "one active decision card" 1 (List.length today.needs_decision);
    let detail = detail store first.request.id in
    expect_int "one capture event" 1 (count_timeline "capture" detail);
    expect_int "one merge event" 1 (count_timeline "merge" detail))

let test_changed_title_keeps_stable_external_identity () =
  with_store (fun store ->
    let first = Runner.ingest_source_signal store (gitlab_input ()) in
    let changed =
      Runner.ingest_source_signal store
        (gitlab_input ~title:"Review requested: billing retry logic v2" ())
    in
    expect_bool "changed title replay merged" true changed.merged;
    expect_string "changed title same request id" first.request.id changed.request.id;
    expect_string "request title updates without changing identity"
      "Review requested: billing retry logic v2" changed.request.title;
    let today = Runner.today store in
    expect_int "changed title one active decision card" 1
      (List.length today.needs_decision))

let test_noop_replay_preserves_approval_but_changed_payload_invalidates_it () =
  with_store (fun store ->
    let first = Runner.ingest_source_signal store (gitlab_input ()) in
    let initial_action = first_action (detail store first.request.id) in
    let approved_body = "User-edited approved MR comment" in
    let approval =
      Runner.approve ~edited_body:approved_body store initial_action.id
      |> Result.get_ok
    in
    let approved_action = Option.get (Store.get_action store initial_action.id) in
    if approved_action.status <> ActionApproved then
      failf "edited action was not approved";

    let noop = Runner.ingest_source_signal store (gitlab_input ()) in
    expect_bool "no-op replay merged" true noop.merged;
    let after_noop = first_action (detail store first.request.id) in
    expect_string "no-op keeps action id" initial_action.id after_noop.id;
    expect_string "no-op keeps approved edit" approved_body after_noop.body;
    expect_string "no-op keeps approved hash" approval.action_hash
      after_noop.payload_hash;
    if after_noop.status <> ActionApproved then
      failf "no-op replay revoked approval";
    let request_after_noop = Option.get (Store.get_work_request store first.request.id) in
    if request_after_noop.status <> Approved then
      failf "no-op replay should preserve approved request";

    let new_context_same_payload =
      Runner.ingest_source_signal store
        (gitlab_input
          ~raw_json:{|{"project_id":123,"iid":456,"sync_revision":2}|} ())
    in
    expect_bool "new context with same payload merged" true
      new_context_same_payload.merged;
    let after_same_payload = first_action (detail store first.request.id) in
    expect_string "same generated payload keeps approved edit" approved_body
      after_same_payload.body;
    expect_string "same generated payload keeps approved hash" approval.action_hash
      after_same_payload.payload_hash;
    if after_same_payload.status <> ActionApproved then
      failf "new context with same generated payload revoked approval";

    let changed =
      Runner.ingest_source_signal store
        (gitlab_input
          ~body:"Alice requested your review. Pipeline is now failing."
          ~raw_json:{|{"project_id":123,"iid":456,"pipeline":"failed"}|} ())
    in
    expect_bool "changed replay merged" true changed.merged;
    let refreshed = first_action (detail store first.request.id) in
    expect_string "changed replay keeps action id" initial_action.id refreshed.id;
    if refreshed.status <> ActionProposed then
      failf "changed replay should return action to proposed";
    if refreshed.payload_hash = approval.action_hash then
      failf "changed replay kept the old approved hash";
    if not (contains refreshed.body "pipeline") then
      failf "changed replay did not regenerate the action body";
    let request_after_change =
      Option.get (Store.get_work_request store first.request.id)
    in
    if request_after_change.status <> ReadyForReview then
      failf "changed replay should return request to ready_for_review";
    let latest_approval =
      Option.get (Store.get_latest_approval_for_action store refreshed.id)
    in
    expect_string "old approval remains audit evidence" approval.id
      latest_approval.id;
    if latest_approval.action_hash = refreshed.payload_hash then
      failf "old approval unexpectedly authorizes refreshed payload";
    expect_int "changed replay keeps one action" 1
      (List.length (detail store first.request.id).actions))

let test_done_request_replay_creates_new_active_request () =
  with_store (fun store ->
    let first = Runner.ingest_source_signal store (gitlab_input ()) in
    ignore (first_action (detail store first.request.id));
    Store.update_request_status store ~request_id:first.request.id ~status:Done;
    let second = Runner.ingest_source_signal store (gitlab_input ()) in
    expect_bool "done replay creates new request" false second.merged;
    if first.request.id = second.request.id then
      failf "done request replay should bind identity to a new request";
    let today = Runner.today store in
    expect_int "new request is active decision card" 1
      (List.length today.needs_decision);
    expect_int "old done request remains handled" 1
      (List.length today.handled))

let test_blank_external_identity_does_not_collapse_signals () =
  with_store (fun store ->
    let first =
      Runner.ingest_source_signal store
        (feishu_url_input ~external_id:" " ~url:" " ~title:"First unkeyed signal" ())
    in
    let second =
      Runner.ingest_source_signal store
        (feishu_url_input ~external_id:" " ~url:" " ~title:"Second unkeyed signal" ())
    in
    expect_bool "first blank identity merged" false first.merged;
    expect_bool "second blank identity merged" false second.merged;
    if first.request.id = second.request.id then
      failf "blank external identity should not collapse unrelated signals";
    let today = Runner.today store in
    expect_int "blank identity creates separate active cards" 2
      (List.length today.needs_decision))

let test_url_fallback_canonicalizes_tracking_and_trailing_slash () =
  with_store (fun store ->
    let first =
      Runner.ingest_source_signal store
        (feishu_url_input
          ~url:" https://feishu.example/docs/doc_123/?utm_source=test " ())
    in
    let second =
      Runner.ingest_source_signal store
        (feishu_url_input ~url:"https://feishu.example/docs/doc_123" ())
    in
    expect_bool "url fallback second replay merged" true second.merged;
    expect_string "canonical url fallback same request id" first.request.id
      second.request.id;
    let today = Runner.today store in
    expect_int "canonical url fallback one active card" 1
      (List.length today.needs_decision))

let () =
  Random.self_init ();
  test_replay_merges_same_identity ();
  test_changed_title_keeps_stable_external_identity ();
  test_noop_replay_preserves_approval_but_changed_payload_invalidates_it ();
  test_done_request_replay_creates_new_active_request ();
  test_blank_external_identity_does_not_collapse_signals ();
  test_url_fallback_canonicalizes_tracking_and_trailing_slash ()
