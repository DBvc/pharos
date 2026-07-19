open Pharos_core
open Pharos_core.Domain

let failf fmt = Printf.ksprintf failwith fmt

let expect_int label expected actual =
  if expected <> actual then
    failf "%s: expected %d, got %d" label expected actual

let expect_string label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label expected actual

let expect_option_string label expected actual =
  if expected <> actual then
    failf "%s: unexpected optional string" label

let contains haystack needle =
  let haystack_len = String.length haystack in
  let needle_len = String.length needle in
  let rec loop index =
    index + needle_len <= haystack_len
    && (String.sub haystack index needle_len = needle || loop (index + 1))
  in
  needle_len = 0 || loop 0

let read_json path = Yojson.Safe.from_file path

let find_fixture_paths () =
  let mr_name = "gitlab_mr_api_response.json" in
  let discussions_name = "gitlab_mr_discussions_response.json" in
  let rec search directory =
    let examples = Filename.concat directory "examples" in
    let mr_path = Filename.concat examples mr_name in
    let discussions_path = Filename.concat examples discussions_name in
    if Sys.file_exists mr_path && Sys.file_exists discussions_path then
      (mr_path, discussions_path)
    else
      let parent = Filename.dirname directory in
      if parent = directory then failf "could not locate GitLab fixtures"
      else search parent
  in
  search (Sys.getcwd ())

let result_or_fail label = function
  | Ok value -> value
  | Error error -> failf "%s: %s" label error

let source_result_or_fail label = function
  | Ok value -> value
  | Error error ->
      failf "%s: %s" label (Source_settings.error_to_string error)

let first label = function
  | value :: _ -> value
  | [] -> failf "%s: expected at least one item" label

let find_evidence kind (items : Runner.evidence_input list) =
  match List.find_opt (fun (item : Runner.evidence_input) -> item.kind = kind) items with
  | Some item -> item
  | None -> failf "missing evidence kind: %s" kind

let remove_member name = function
  | `Assoc fields -> `Assoc (List.remove_assoc name fields)
  | json -> json

let fixture_instance =
  Gitlab_identity.instance_of_base_url "https://gitlab.example.com"
  |> Result.get_ok

let fixture_target : Gitlab_identity.target =
  {
    instance_id = fixture_instance.id;
    project_id = 42;
    object_kind = MergeRequest;
    iid = 7;
  }

let fixture_config : Gitlab_read.config = {
  base_url = fixture_instance.base_url;
  instance_id = fixture_instance.id;
  token = "fixture-token";
  username = Some "dbvc";
  project_ids = [];
}

let temp_db () =
  Filename.concat
    (Filename.get_temp_dir_name ())
    ("pharos_gitlab_read_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let source_patch ?enabled ?read_enabled ?write_enabled ?scope_json () =
  Domain.{ enabled; read_enabled; write_enabled; scope_json }

let enable_gitlab ?(scope_json="{}") store =
  Source_settings.patch_source store Gitlab_read.source_id
    (source_patch ~enabled:true ~read_enabled:true ~scope_json ())
  |> source_result_or_fail "enable GitLab source"
  |> ignore

let test_parser mr_json discussions_json =
  let merge_requests =
    Gitlab_read.parse_merge_requests mr_json
    |> result_or_fail "parse merge requests"
  in
  expect_int "fixture merge request count" 2 (List.length merge_requests);
  let mr = first "merge requests" merge_requests in
  let discussions =
    Gitlab_read.parse_discussions discussions_json
    |> result_or_fail "parse discussions"
  in
  expect_int "discussion count" 2 discussions.count;
  expect_int "unresolved discussion count" 1 discussions.unresolved_count;
  let normalized =
    Gitlab_read.normalize ~instance_id:fixture_instance.id mr discussions
  in
  expect_option_string "stable external id"
    (Some (Gitlab_identity.external_id fixture_target))
    normalized.signal.external_id;
  expect_option_string "MR URL"
    (Some "https://gitlab.example.com/acme/payments/-/merge_requests/7")
    normalized.signal.url;
  List.iter (fun (item : Runner.evidence_input) ->
    if String.length item.body > Gitlab_read.max_evidence_bytes then
      failf "%s evidence exceeded %d bytes" item.kind
        Gitlab_read.max_evidence_bytes) normalized.evidence;
  ignore (find_evidence "gitlab.mr.metadata" normalized.evidence);
  ignore (find_evidence "gitlab.mr.pipeline" normalized.evidence);
  ignore (find_evidence "gitlab.mr.discussions" normalized.evidence);
  let minimal = List.nth merge_requests 1 in
  let minimal_normalized =
    Gitlab_read.normalize ~instance_id:fixture_instance.id minimal discussions
  in
  expect_string "missing author falls back" "gitlab" minimal_normalized.signal.actor;
  expect_option_string "missing URL stays absent" None minimal_normalized.signal.url;
  let bounded = Gitlab_read.bounded_text (String.make 5000 'x') in
  expect_int "bounded evidence bytes" Gitlab_read.max_evidence_bytes
    (String.length bounded)

let test_sync_reuses_merge_identity mr_json discussions_json =
  let detail_json =
    match mr_json with
    | `List (value :: _) -> value
    | _ -> failf "MR fixture must contain a detail object"
  in
  let get_json _config path =
    match path with
    | "/merge_requests?scope=reviews_for_me&state=opened&per_page=100&page=1" ->
        Ok (`List [ detail_json ])
    | "/projects/42/merge_requests/7" -> Ok detail_json
    | "/projects/42/merge_requests/7/discussions?per_page=100&page=1" ->
        Ok discussions_json
    | unexpected -> Error ("unexpected fixture path: " ^ unexpected)
  in
  with_store (fun store ->
    enable_gitlab store;
    let first_count =
      Gitlab_read.sync_once_with ~get_json store fixture_config
      |> result_or_fail "first fake sync"
    in
    let second_count =
      Gitlab_read.sync_once_with ~get_json store fixture_config
      |> result_or_fail "second fake sync"
    in
    expect_int "first processed count" 1 first_count;
    expect_int "second processed count" 1 second_count;
    let requests = Store.list_work_requests store in
    expect_int "repeated sync keeps one request" 1 (List.length requests);
    let request = first "requests" requests in
    let detail =
      match Runner.get_detail store request.id with
      | Some value -> value
      | None -> failf "missing request detail"
    in
    let evidence = detail.evidence in
    let has_kind kind =
      List.exists (fun (item : evidence_item) -> item.kind = kind) evidence
    in
    let count_kind kind =
      evidence
      |> List.filter (fun (item : evidence_item) -> item.kind = kind)
      |> List.length
    in
    List.iter (fun kind ->
      if not (has_kind kind) then failf "detail missing %s" kind;
      expect_int (kind ^ " snapshot count") 1 (count_kind kind))
      [ "gitlab.mr.metadata"; "gitlab.mr.pipeline";
        "gitlab.mr.discussions" ];
    let action =
      match detail.actions with
      | [ value ] -> value
      | actions -> failf "expected one GitLab action, got %d" (List.length actions)
    in
    expect_string "canonical GitLab target ref"
      (Gitlab_identity.target_ref fixture_target)
      action.target_ref;
    detail.evidence
    |> List.filter (fun (item : evidence_item) ->
      String.starts_with ~prefix:"gitlab.mr." item.kind)
    |> List.iter (fun (item : evidence_item) ->
      if not (contains action.body item.id) then
        failf "GitLab action did not reference rich evidence %s" item.id);
    match Store.get_source store Gitlab_read.source_id with
    | Some source ->
        if source.last_sync_at = None then failf "last_sync_at was not recorded";
        if source.last_error <> None then failf "successful sync kept last_error"
    | None -> failf "GitLab source config missing")

let test_pipeline_failure_is_optional mr_json discussions_json =
  let detail_with_pipeline =
    match mr_json with
    | `List (value :: _) -> value
    | _ -> failf "MR fixture must contain a detail object"
  in
  let detail_without_pipeline = remove_member "head_pipeline" detail_with_pipeline in
  let pipeline_available = ref true in
  let current_detail () =
    if !pipeline_available then detail_with_pipeline else detail_without_pipeline
  in
  let get_json _config path =
    match path with
    | "/merge_requests?scope=reviews_for_me&state=opened&per_page=100&page=1" ->
        Ok (`List [ current_detail () ])
    | "/projects/42/merge_requests/7" -> Ok (current_detail ())
    | "/projects/42/merge_requests/7/discussions?per_page=100&page=1" ->
        Ok discussions_json
    | "/projects/42/merge_requests/7/pipelines?per_page=1&order_by=id&sort=desc" ->
        Error "pipeline endpoint unavailable"
    | unexpected -> Error ("unexpected fixture path: " ^ unexpected)
  in
  with_store (fun store ->
    enable_gitlab store;
    let first_processed =
      Gitlab_read.sync_once_with ~get_json store fixture_config
      |> result_or_fail "sync with pipeline evidence"
    in
    expect_int "processed with pipeline evidence" 1 first_processed;
    pipeline_available := false;
    let second_processed =
      Gitlab_read.sync_once_with ~get_json store fixture_config
      |> result_or_fail "sync without pipeline access"
    in
    expect_int "processed without pipeline access" 1 second_processed;
    let request = Store.list_work_requests store |> first "requests" in
    let detail =
      match Runner.get_detail store request.id with
      | Some value -> value
      | None -> failf "missing request detail"
    in
    let has_kind kind =
      List.exists (fun (item : evidence_item) -> item.kind = kind) detail.evidence
    in
    if not (has_kind "gitlab.mr.metadata") then failf "metadata evidence missing";
    if not (has_kind "gitlab.mr.discussions") then failf "discussion evidence missing";
    if has_kind "gitlab.mr.pipeline" then
      failf "pipeline evidence should be absent after optional fetch failure")

let test_merge_request_pagination () =
  let merge_request_json iid =
    `Assoc [
      ("project_id", `Int 42);
      ("iid", `Int iid);
      ("title", `String (Printf.sprintf "MR !%d" iid));
      ("state", `String "opened");
      ("updated_at", `String "2026-07-09T10:00:00Z");
    ]
  in
  let first_page = List.init Gitlab_read.page_size (fun index ->
    merge_request_json (index + 1))
  in
  let get_json _config path =
    match path with
    | "/merge_requests?scope=reviews_for_me&state=opened&per_page=100&page=1" ->
        Ok (`List first_page)
    | "/merge_requests?scope=reviews_for_me&state=opened&per_page=100&page=2" ->
        Ok (`List [ merge_request_json 101 ])
    | unexpected -> Error ("unexpected fixture path: " ^ unexpected)
  in
  let merge_requests =
    Gitlab_read.list_merge_requests get_json fixture_config
    |> result_or_fail "paginated merge request list"
  in
  expect_int "paginated merge request count" 101 (List.length merge_requests)

let test_curl_environment_removes_token () =
  let environment = [|
    "PATH=/usr/bin";
    "HTTPS_PROXY=http://127.0.0.1:8080";
    "PHAROS_GITLAB_TOKEN=secret";
    "PHAROS_GITLAB_BASE_URL=https://gitlab.example.com";
  |] in
  let filtered = Gitlab_read.curl_environment_from environment |> Array.to_list in
  if List.mem "PHAROS_GITLAB_TOKEN=secret" filtered then
    failf "curl child environment kept GitLab token";
  List.iter (fun expected ->
    if not (List.mem expected filtered) then
      failf "curl child environment dropped %s" expected)
    [ "PATH=/usr/bin"; "HTTPS_PROXY=http://127.0.0.1:8080";
      "PHAROS_GITLAB_BASE_URL=https://gitlab.example.com" ]

let getenv_from values name = List.assoc_opt name values

let valid_environment =
  [
    ("PHAROS_GITLAB_BASE_URL", "https://gitlab.example.com");
    ("PHAROS_GITLAB_TOKEN", "fixture-token");
    ("PHAROS_GITLAB_USERNAME", "dbvc");
  ]

let expect_error label = function
  | Error _ -> ()
  | Ok _ -> failf "%s: expected error" label

let source_status store =
  match Source_settings.get_source store Gitlab_read.source_id with
  | Some source -> (source.last_sync_at, source.last_error, source.updated_at)
  | None -> failf "GitLab source config missing"

let test_source_policy_gates_network () =
  with_store (fun store ->
    let calls = ref 0 in
    let get_json _config _path =
      incr calls;
      Error "network must not be called"
    in
    let sync getenv =
      Gitlab_read.sync_from_settings_with ~getenv ~get_json store
    in
    let valid_getenv = getenv_from valid_environment in
    ignore
      (Store.patch_source store Gitlab_read.source_id
         (source_patch ~scope_json:"invalid persisted scope" ()));
    let before = source_status store in
    expect_error "disabled source with invalid scope" (sync valid_getenv);
    expect_int "disabled invalid-scope network calls" 0 !calls;
    if before <> source_status store then
      failf "disabled invalid-scope sync changed source status";

    ignore
      (Source_settings.patch_source store Gitlab_read.source_id
         (source_patch ~enabled:true ~read_enabled:false ())
       |> source_result_or_fail "enable GitLab without read permission");
    let before = source_status store in
    expect_error "read-disabled source with invalid scope" (sync valid_getenv);
    expect_int "read-disabled invalid-scope network calls" 0 !calls;
    if before <> source_status store then
      failf "read-disabled invalid-scope sync changed source status";

    ignore
      (Store.patch_source store Gitlab_read.source_id
         (source_patch ~read_enabled:true ()));
    expect_error "invalid persisted scope" (sync valid_getenv);
    expect_int "invalid scope network calls" 0 !calls;
    begin match Source_settings.get_source store Gitlab_read.source_id with
    | Some { last_error = Some error; _ } ->
        if String.length error > 1000 then failf "last_error was not bounded";
        if contains error "invalid persisted scope" then
          failf "last_error leaked raw invalid scope"
    | _ -> failf "invalid persisted scope did not record last_error"
    end;

    ignore
      (Source_settings.patch_source store Gitlab_read.source_id
         (source_patch ~scope_json:"{}" ())
       |> source_result_or_fail "repair GitLab scope");
    let mismatched_instance =
      { fixture_config with instance_id = String.make 64 '0' }
    in
    expect_error "adapter instance mismatch"
      (Gitlab_read.sync_once_with ~get_json store mismatched_instance);
    expect_int "mismatched instance network calls" 0 !calls;
    let mismatched_config =
      { fixture_config with project_ids = [ "42" ] }
    in
    expect_error "adapter config scope mismatch"
      (Gitlab_read.sync_once_with ~get_json store mismatched_config);
    expect_int "mismatched config network calls" 0 !calls;
    let legacy_getenv name =
      if name = "PHAROS_GITLAB_PROJECTS" then Some "42"
      else valid_getenv name
    in
    expect_error "legacy project environment" (sync legacy_getenv);
    expect_int "legacy env network calls" 0 !calls;
    begin match Source_settings.get_source store Gitlab_read.source_id with
    | Some { last_error = Some error; _ } ->
        if not (contains error "PHAROS_GITLAB_PROJECTS") then
          failf "legacy env error was not explicit"
    | _ -> failf "legacy env did not record last_error"
    end)

let test_real_entry_rejects_legacy_projects () =
  with_store (fun store ->
    enable_gitlab store;
    let calls = ref 0 in
    let get_json _config _path =
      incr calls;
      Error "network must not be called"
    in
    let legacy_getenv name =
      if name = "PHAROS_GITLAB_PROJECTS" then Some "42" else None
    in
    let last_sync_before, _, _ = source_status store in
    expect_error "real sync entry legacy project environment"
      (Gitlab_read.sync_once_with ~getenv:legacy_getenv ~get_json
         store fixture_config);
    expect_int "real sync entry legacy env network calls" 0 !calls;
    begin match Source_settings.get_source store Gitlab_read.source_id with
    | Some { last_sync_at; last_error = Some error; _ } ->
        if last_sync_at <> last_sync_before then
          failf "legacy env rejection changed last_sync_at";
        if String.length error > 1000 then failf "legacy env error was not bounded";
        if not (contains error "PHAROS_GITLAB_PROJECTS") then
          failf "real sync entry legacy env error was not explicit"
    | _ -> failf "real sync entry legacy env did not record last_error"
    end)

let test_persisted_projects_drive_endpoints () =
  let expected =
    [
      "/merge_requests?scope=reviews_for_me&state=opened&per_page=100&page=1";
      "/projects/42/merge_requests?state=opened&per_page=100&page=1";
      "/projects/77/merge_requests?state=opened&per_page=100&page=1";
    ]
  in
  let run scope_json =
    with_store (fun store ->
      enable_gitlab ~scope_json store;
      let paths = ref [] in
      let get_json _config path =
        paths := path :: !paths;
        Ok (`List [])
      in
      ignore
        (Gitlab_read.sync_from_settings_with
           ~getenv:(getenv_from valid_environment) ~get_json store
         |> result_or_fail "settings-owned project list");
      List.rev !paths)
  in
  if run {|{"projects":[77,42]}|} <> expected then
    failf "persisted scope produced unexpected project endpoints";
  if run "{}" <> [ List.hd expected ] then
    failf "empty persisted scope appended project endpoints"

let () =
  Random.self_init ();
  let mr_path, discussions_path = find_fixture_paths () in
  let mr_json = read_json mr_path in
  let discussions_json = read_json discussions_path in
  test_parser mr_json discussions_json;
  test_sync_reuses_merge_identity mr_json discussions_json;
  test_pipeline_failure_is_optional mr_json discussions_json;
  test_merge_request_pagination ();
  test_curl_environment_removes_token ();
  test_source_policy_gates_network ();
  test_real_entry_rejects_legacy_projects ();
  test_persisted_projects_drive_endpoints ()
