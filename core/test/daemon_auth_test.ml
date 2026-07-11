open Pharos_core
open Pharos_core.Domain

let failf fmt = Printf.ksprintf failwith fmt

let capability_token = String.make 64 'a'
let wrong_capability_token = String.make 64 'b'
let authorization = "Bearer " ^ capability_token

let temp_db () =
  Filename.concat (Filename.get_temp_dir_name ())
    ("pharos_auth_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let with_store f =
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () -> f store)

let capture store title =
  Runner.capture_manual store
    { Runner.title = Some title; body = title; url = None; actor = Some "test" }

let first_action store request_id =
  match Runner.get_detail store request_id with
  | Some { actions = action :: _; _ } -> action
  | _ -> failf "missing action for request %s" request_id

let database_snapshot store =
  let requests = Store.list_work_requests store in
  let details =
    List.filter_map
      (fun (request : work_request) -> Runner.get_detail store request.id)
      requests
  in
  (requests, details, Store.list_sources store,
   Store.get_metric_for_day store (Time.today_utc ()))

let call handler ?authorization ~method_ ~target body =
  let headers =
    match authorization with
    | None -> []
    | Some value -> [ ("Authorization", value) ]
  in
  Dream.request ~method_ ~target ~headers body |> Dream.test handler

let environment_with_capability capability =
  let prefix = "PHAROS_CAPABILITY_TOKEN=" in
  let base =
    Unix.environment () |> Array.to_list
    |> List.filter (fun value -> not (String.starts_with ~prefix value))
  in
  match capability with
  | None -> Array.of_list base
  | Some token -> Array.of_list ((prefix ^ token) :: base)

let wait_for_exit pid =
  let rec loop remaining =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ when remaining = 0 ->
        Unix.kill pid Sys.sigkill;
        ignore (Unix.waitpid [] pid);
        Error "daemon did not fail startup within one second"
    | 0, _ ->
        Unix.sleepf 0.01;
        loop (remaining - 1)
    | _, status -> Ok status
  in
  loop 100

let test_daemon_rejects_config_before_sqlite () =
  let daemon = "../bin/daemon/main.exe" in
  let cases =
    [
      ("missing capability", "127.0.0.1", None);
      ("malformed capability", "127.0.0.1", Some "short");
      ("non-loopback host", "0.0.0.0", Some capability_token);
    ]
  in
  List.iter
    (fun (label, host, token) ->
      let db_path = temp_db () in
      if Sys.file_exists db_path then Sys.remove db_path;
      let sink = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
      let argv =
        [| daemon; "--db"; db_path; "--host"; host; "--port"; "0" |]
      in
      let result =
        Fun.protect
          ~finally:(fun () -> Unix.close sink)
          (fun () ->
            let pid =
              Unix.create_process_env daemon argv
                (environment_with_capability token)
                Unix.stdin sink sink
            in
            wait_for_exit pid)
      in
      let created_db = Sys.file_exists db_path in
      if created_db then Sys.remove db_path;
      begin match result with
      | Ok (Unix.WEXITED 2) -> ()
      | Ok (Unix.WEXITED code) ->
          failf "%s exited %d instead of 2" label code
      | Ok (Unix.WSIGNALED signal) ->
          failf "%s was killed by signal %d" label signal
      | Ok (Unix.WSTOPPED signal) ->
          failf "%s stopped on signal %d" label signal
      | Error error -> failf "%s: %s" label error
      end;
      if created_db then failf "%s created SQLite before rejecting startup" label)
    cases

let expect_unauthorized store handler request =
  let before = database_snapshot store in
  let response = request handler in
  let status = Dream.status response |> Dream.status_to_int in
  if status <> 401 then failf "expected 401, got %d" status;
  let body = Lwt_main.run (Dream.body response) in
  if body <> {|{"error":"unauthorized"}|} then
    failf "unexpected unauthorized response: %s" body;
  if before <> database_snapshot store then
    failf "unauthorized request changed SQLite"

let protected_requests request_id (proposed_action : proposed_action)
    (approved_action : proposed_action) authorization =
  let review_body =
    Printf.sprintf {|{"expected_payload_hash":"%s"}|}
      proposed_action.payload_hash
  in
  [
    (fun handler ->
      call handler ?authorization ~method_:`GET ~target:"/v0/future-route" "");
    (fun handler ->
      call handler ?authorization ~method_:`GET ~target:"/v0/sources" "");
    (fun handler ->
      call handler ?authorization ~method_:`GET ~target:"/v0/today" "");
    (fun handler ->
      call handler ?authorization ~method_:`GET
        ~target:"/v0/debug/today-internal" "");
    (fun handler ->
      call handler ?authorization ~method_:`GET
        ~target:("/v0/requests/" ^ request_id) "");
    (fun handler ->
      call handler ?authorization ~method_:`POST ~target:"/v0/capture"
        {|{"body":"unauthorized capture"}|});
    (fun handler ->
      call handler ?authorization ~method_:`POST ~target:"/v0/source-signals"
        {|{"kind":"manual","actor":"test","title":"signal","body":"body","occurred_at":"2026-07-11T00:00:00Z"}|});
    (fun handler ->
      call handler ?authorization ~method_:`PATCH
        ~target:"/v0/sources/src_gitlab" {|{"enabled":true}|});
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:("/v0/actions/" ^ proposed_action.id ^ "/approve")
        review_body);
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:("/v0/actions/" ^ proposed_action.id ^ "/edit-and-approve")
        (Printf.sprintf
           {|{"body":"edited","expected_payload_hash":"%s"}|}
           proposed_action.payload_hash));
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:("/v0/actions/" ^ proposed_action.id ^ "/reject")
        review_body);
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:("/v0/actions/" ^ approved_action.id ^ "/execute-local")
        "{}");
  ]

let test_all_v0_routes_require_capability () =
  with_store (fun store ->
    let proposed_request = capture store "proposed auth action" in
    let proposed_action = first_action store proposed_request.id in
    let approved_request = capture store "approved auth action" in
    let approved_action = first_action store approved_request.id in
    ignore
      (Result.get_ok
         (Runner.approve ~expected_payload_hash:approved_action.payload_hash
            store approved_action.id));
    let approved_action = Option.get (Store.get_action store approved_action.id) in
    let handler = App.routes store capability_token in
    List.iter
      (expect_unauthorized store handler)
      (protected_requests proposed_request.id proposed_action approved_action None);
    List.iter
      (expect_unauthorized store handler)
      (protected_requests proposed_request.id proposed_action approved_action
         (Some ("Bearer " ^ wrong_capability_token))))

let test_health_is_public () =
  with_store (fun store ->
    let handler = App.routes store capability_token in
    let response = call handler ~method_:`GET ~target:"/health" "" in
    let status = Dream.status response |> Dream.status_to_int in
    if status <> 200 then failf "public health returned %d" status)

let test_valid_capability_reaches_v0_routes () =
  with_store (fun store ->
    let handler = App.routes store capability_token in
    let read_response =
      call handler ~authorization ~method_:`GET ~target:"/v0/today" ""
    in
    let read_status = Dream.status read_response |> Dream.status_to_int in
    if read_status <> 200 then
      failf "authorized read returned %d" read_status;
    let response =
      call handler ~authorization ~method_:`POST
        ~target:"/v0/capture" {|{"body":"authorized capture"}|}
    in
    let status = Dream.status response |> Dream.status_to_int in
    if status <> 200 then failf "authorized mutation returned %d" status;
    if List.length (Store.list_work_requests store) <> 1 then
      failf "authorized mutation did not reach core")

let test_stale_review_routes_return_conflict () =
  with_store (fun store ->
    let request = capture store "stale route action" in
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
    let handler = App.routes store capability_token in
    let review_body =
      Printf.sprintf {|{"expected_payload_hash":"%s"}|}
        shown_action.payload_hash
    in
    let mutations =
      [
        ("approve", review_body);
        ( "edit-and-approve",
          Printf.sprintf
            {|{"body":"stale edit","expected_payload_hash":"%s"}|}
            shown_action.payload_hash );
        ("reject", review_body);
      ]
    in
    List.iter
      (fun (suffix, body) ->
        let before = database_snapshot store in
        let response =
          call handler ~authorization ~method_:`POST
            ~target:("/v0/actions/" ^ shown_action.id ^ "/" ^ suffix)
            body
        in
        let status = Dream.status response |> Dream.status_to_int in
        if status <> 409 then
          failf "stale %s expected 409, got %d" suffix status;
        let response_body = Lwt_main.run (Dream.body response) in
        if response_body <> {|{"error":"stale_action"}|} then
          failf "stale %s returned %s" suffix response_body;
        if before <> database_snapshot store then
          failf "stale %s changed SQLite" suffix)
      mutations)

let test_capability_primitives () =
  if not (Capability.is_loopback_host "127.0.0.1") then
    failf "IPv4 loopback rejected";
  if not (Capability.is_loopback_host "::1") then failf "IPv6 loopback rejected";
  List.iter
    (fun host ->
      if Capability.is_loopback_host host then
        failf "non-loopback host accepted: %s" host)
    [ "0.0.0.0"; "localhost"; "192.168.1.10" ];
  if Capability.valid_token capability_token <> Some capability_token then
    failf "valid 64-character lowercase hex capability rejected";
  List.iter
    (fun token ->
      if Capability.valid_token token <> None then
        failf "invalid configured capability accepted")
    [
      "";
      String.make 63 'a';
      String.make 65 'a';
      String.make 64 'A';
      String.make 64 'g';
      (" " ^ String.make 63 'a');
    ];
  begin
    match
      Capability.authorize ~expected_token:capability_token
        ~authorization:(Some authorization)
    with
    | Ok () -> ()
    | Error _ -> failf "matching capability rejected"
  end;
  List.iter
    (fun authorization ->
      match
        Capability.authorize ~expected_token:capability_token ~authorization
      with
      | Error _ -> ()
      | Ok () -> failf "invalid capability accepted"
    )
    [
      None;
      Some capability_token;
      Some ("Bearer " ^ wrong_capability_token);
      Some "Bearer ";
      Some ("Bearer " ^ capability_token ^ " ");
    ]

let () =
  Random.self_init ();
  test_capability_primitives ();
  test_daemon_rejects_config_before_sqlite ();
  test_all_v0_routes_require_capability ();
  test_health_is_public ();
  test_valid_capability_reaches_v0_routes ();
  test_stale_review_routes_return_conflict ()
