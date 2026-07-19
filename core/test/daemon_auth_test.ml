open Pharos_core
open Pharos_core.Domain

let ( >>= ) = Lwt.bind

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

let gitlab_input () : Runner.source_signal_input =
  {
    kind = GitLab;
    external_id = Some "gitlab:project/123:mr/456";
    actor = "alice";
    title = "Review requested";
    body = "Alice requested review.";
    url = Some "https://gitlab.example/group/project/-/merge_requests/456";
    occurred_at = "2026-07-19T00:00:00Z";
    raw_json = Some {|{"project_id":123,"iid":456}|};
  }

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

let test_delivery_owner_blocks_recovery_until_lock_acquired () =
  let db_path = temp_db () in
  let alias_path = db_path ^ ".alias" in
  let dotted_path =
    Filename.concat (Filename.dirname db_path)
      (Filename.concat "." (Filename.basename db_path))
  in
  let lock_path = Store.delivery_lock_path db_path in
  let cleanup () =
    List.iter
      (fun path -> if Sys.file_exists path then Sys.remove path)
      [
        alias_path;
        db_path;
        db_path ^ "-shm";
        db_path ^ "-wal";
        lock_path;
        alias_path ^ "-delivery.lock";
      ]
  in
  Fun.protect ~finally:cleanup (fun () ->
    Unix.symlink (Filename.basename db_path) alias_path;
    let alias_lock_path = Store.delivery_lock_path alias_path in
    if alias_lock_path <> lock_path then
      failf "dangling database symlink derived a different delivery lock: %s <> %s"
        alias_lock_path lock_path;
    let dotted_lock_path = Store.delivery_lock_path dotted_path in
    if dotted_lock_path <> lock_path then
      failf "dotted database path derived a different delivery lock: %s <> %s"
        dotted_lock_path lock_path;
    let owner = Store.acquire_delivery_owner alias_path |> Result.get_ok in
    let attempt_id =
      Fun.protect
        ~finally:(fun () -> Store.release_delivery_owner owner)
        (fun () ->
          let attempt_id =
            let store = Store.connect alias_path in
            Fun.protect
              ~finally:(fun () -> Store.close store)
              (fun () ->
                let response =
                  Runner.ingest_source_signal store (gitlab_input ())
                in
                let action = first_action store response.request.id in
                ignore
                  (Source_settings.patch_source store
                     (Store.source_config_id GitLab)
                     {
                       enabled = Some true;
                       read_enabled = None;
                       write_enabled = Some true;
                       scope_json = Some "{}";
                     }
                  |> Result.get_ok);
                ignore
                  (Runner.approve ~expected_payload_hash:action.payload_hash
                     store action.id
                  |> Result.get_ok);
                let operation =
                  Runner.start_writeback store action.id |> Result.get_ok
                in
                operation.attempt.id)
          in
          let alias_lock_path_after_create =
            Store.delivery_lock_path alias_path
          in
          if alias_lock_path_after_create <> lock_path then
            failf
              "database creation changed the symlink delivery lock: %s <> %s"
              alias_lock_path_after_create lock_path;
          let daemon = "../bin/daemon/main.exe" in
          let sink = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
          let result =
            Fun.protect
              ~finally:(fun () -> Unix.close sink)
              (fun () ->
                let argv =
                  [|
                    daemon;
                    "--db";
                    db_path;
                    "--host";
                    "127.0.0.1";
                    "--port";
                    "0";
                  |]
                in
                let pid =
                  Unix.create_process_env daemon argv
                    (environment_with_capability (Some capability_token))
                    Unix.stdin sink sink
                in
                wait_for_exit pid)
          in
          begin
            match result with
            | Ok (Unix.WEXITED 2) -> ()
            | Ok (Unix.WEXITED code) ->
                failf "lock-contended daemon exited %d instead of 2" code
            | Ok (Unix.WSIGNALED signal) ->
                failf "lock-contended daemon was killed by signal %d" signal
            | Ok (Unix.WSTOPPED signal) ->
                failf "lock-contended daemon stopped on signal %d" signal
            | Error error -> failf "lock-contended daemon: %s" error
          end;
          let store = Store.connect db_path in
          Fun.protect
            ~finally:(fun () -> Store.close store)
            (fun () ->
              let attempt =
                Option.get (Store.get_writeback_attempt store attempt_id)
              in
              if attempt.status <> WritebackInFlight then
                failf "lock contention recovered writeback before ownership");
          attempt_id)
    in
    let recovery_owner = Store.acquire_delivery_owner db_path |> Result.get_ok in
    Fun.protect
      ~finally:(fun () -> Store.release_delivery_owner recovery_owner)
      (fun () ->
        let store = Store.connect dotted_path in
        Fun.protect
          ~finally:(fun () -> Store.close store)
          (fun () ->
            Runner.recover_interrupted_writebacks store;
            let attempt =
              Option.get (Store.get_writeback_attempt store attempt_id)
            in
            if attempt.status <> WritebackUnknown then
              failf "owned recovery did not restore unknown writeback")))

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
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:("/v0/actions/" ^ approved_action.id ^ "/execute-approved")
        "{}");
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:"/v0/writeback-attempts/wba_auth/reconcile" "{}");
    (fun handler ->
      call handler ?authorization ~method_:`POST
        ~target:"/v0/writeback-attempts/wba_auth/abandon" "{}");
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

let test_slow_writeback_does_not_block_health () =
  with_store (fun store ->
    let response = Runner.ingest_source_signal store (gitlab_input ()) in
    let action = first_action store response.request.id in
    ignore
      (Source_settings.patch_source store (Store.source_config_id GitLab)
         {
           enabled = Some true;
           read_enabled = None;
           write_enabled = Some true;
           scope_json = Some "{}";
         }
      |> Result.get_ok);
    ignore
      (Runner.approve ~expected_payload_hash:action.payload_hash store action.id
      |> Result.get_ok);
    let slow_client : Gitlab_write.client =
      {
        post =
          (fun _ ->
            Unix.sleepf 0.5;
            Gitlab_write.Confirmed
              {
                external_id = "note_123";
                external_url =
                  "https://gitlab.example/group/project/-/merge_requests/456#note_123";
              });
        reconcile = (fun _ -> Gitlab_write.Marker_not_found);
      }
    in
    let handler = App.routes ~gitlab_client:slow_client store capability_token in
    let execute_request =
      Dream.request ~method_:`POST
        ~target:("/v0/actions/" ^ action.id ^ "/execute-approved")
        ~headers:[ ("Authorization", authorization) ] "{}"
    in
    let health_request = Dream.request ~method_:`GET ~target:"/health" "" in
    let execute_response, (health_response, health_latency) =
      Lwt_main.run
        (Lwt.both (handler execute_request)
           (Lwt_unix.sleep 0.05 >>= fun () ->
            let started_at = Unix.gettimeofday () in
            handler health_request >>= fun response ->
            Lwt.return (response, Unix.gettimeofday () -. started_at)))
    in
    let execute_status =
      Dream.status execute_response |> Dream.status_to_int
    in
    if execute_status <> 200 then
      failf "slow writeback returned %d" execute_status;
    let health_status = Dream.status health_response |> Dream.status_to_int in
    if health_status <> 200 then failf "health returned %d" health_status;
    if health_latency >= 0.3 then
      failf "slow writeback blocked health for %.3fs" health_latency)

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

let test_source_scope_api_validation_and_repair () =
  with_store (fun store ->
    let handler = App.routes store capability_token in
    let before = Store.get_source store "src_gitlab" in
    let response =
      call handler ~authorization ~method_:`PATCH
        ~target:"/v0/sources/src_gitlab"
        {|{"enabled":true,"scope_json":"{\"projects\":[0]}"}|}
    in
    let status = Dream.status response |> Dream.status_to_int in
    if status <> 400 then failf "invalid source scope returned %d" status;
    let body = Lwt_main.run (Dream.body response) in
    if body <> {|{"error":"invalid_source_scope"}|} then
      failf "invalid source scope returned %s" body;
    if before <> Store.get_source store "src_gitlab" then
      failf "invalid source scope PATCH changed SQLite";

    ignore
      (Store.patch_source store "src_gitlab"
         Domain.{
           enabled = None;
           read_enabled = None;
           write_enabled = None;
           scope_json = Some "invalid persisted scope";
         });
    let get_response =
      call handler ~authorization ~method_:`GET ~target:"/v0/sources" ""
    in
    if Dream.status get_response |> Dream.status_to_int <> 200 then
      failf "GET sources rejected repairable persisted scope";
    let get_json =
      Lwt_main.run (Dream.body get_response) |> Yojson.Safe.from_string
    in
    let gitlab =
      Yojson.Safe.Util.member "sources" get_json
      |> Yojson.Safe.Util.to_list
      |> List.find (fun source ->
        Yojson.Safe.Util.member "id" source |> Yojson.Safe.Util.to_string
        = "src_gitlab")
    in
    let scope =
      Yojson.Safe.Util.member "scope_json" gitlab |> Yojson.Safe.Util.to_string
    in
    if scope <> "invalid persisted scope" then
      failf "GET sources hid invalid persisted scope";

    let repair_response =
      call handler ~authorization ~method_:`PATCH
        ~target:"/v0/sources/src_gitlab" {|{"scope_json":"{}"}|}
    in
    if Dream.status repair_response |> Dream.status_to_int <> 200 then
      failf "valid source scope repair failed";
    match Store.get_source store "src_gitlab" with
    | Some { scope_json = "{}"; _ } -> ()
    | _ -> failf "valid source scope repair did not persist")

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
  test_delivery_owner_blocks_recovery_until_lock_acquired ();
  test_all_v0_routes_require_capability ();
  test_health_is_public ();
  test_slow_writeback_does_not_block_health ();
  test_valid_capability_reaches_v0_routes ();
  test_stale_review_routes_return_conflict ();
  test_source_scope_api_validation_and_repair ()
