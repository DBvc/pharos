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

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let gitlab_input ?(title = "Review requested: billing retry logic") () :
    Runner.source_signal_input =
  {
    kind = GitLab;
    external_id = Some "gitlab:project/123:mr/456";
    actor = "alice";
    title;
    body = "Alice requested your review on MR !456.";
    url = Some "https://gitlab.example/group/project/-/merge_requests/456?utm_source=test";
    occurred_at = "2026-07-08T00:00:00Z";
    raw_json = Some {|{"project_id":123,"iid":456}|};
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

let count_timeline kind detail =
  detail.timeline
  |> List.filter (fun event -> event.kind = kind)
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

let test_done_request_replay_creates_new_active_request () =
  with_store (fun store ->
    let first = Runner.ingest_source_signal store (gitlab_input ()) in
    let action = first_action (detail store first.request.id) in
    ignore (Result.get_ok (Runner.approve store action.id));
    ignore (Result.get_ok (Runner.execute_local store action.id));
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
  test_done_request_replay_creates_new_active_request ();
  test_blank_external_identity_does_not_collapse_signals ();
  test_url_fallback_canonicalizes_tracking_and_trailing_slash ()
