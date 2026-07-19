open Pharos_core

let ( >>= ) = Lwt.bind

let json value = Dream.json (Yojson.Safe.to_string value)

let error_response ?(status = `Bad_Request) message =
  Dream.json ~status
    (Yojson.Safe.to_string (`Assoc [ ("error", `String message) ]))

let require_capability capability_token handler req =
  match
    Capability.authorize ~expected_token:capability_token
      ~authorization:(Dream.header req "Authorization")
  with
  | Ok () -> handler req
  | Error _ -> error_response ~status:`Unauthorized "unauthorized"

let capture store req =
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      begin match Runner.capture_input_of_json payload with
      | Error e -> error_response e
      | Ok input ->
          let request = Runner.capture_manual store input in
          json
            (`Assoc
              [
                ("request", Domain.work_request_to_yojson request);
                ("detail_url", `String ("/v0/requests/" ^ request.id));
              ])
      end

let source_signal store req =
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      begin match Runner.source_signal_input_of_json payload with
      | Error e -> error_response e
      | Ok input ->
          let response = Runner.ingest_source_signal store input in
          json (Runner.source_signal_response_to_yojson response)
      end

let optional_bool name json =
  match Yojson.Safe.Util.member name json with
  | `Null -> Ok None
  | `Bool value -> Ok (Some value)
  | _ -> Error ("Expected boolean field: " ^ name)

let optional_string name json =
  match Yojson.Safe.Util.member name json with
  | `Null -> Ok None
  | `String value -> Ok (Some value)
  | _ -> Error ("Expected string field: " ^ name)

let source_patch_of_json json =
  match optional_bool "enabled" json with
  | Error e -> Error e
  | Ok enabled ->
      begin match optional_bool "read_enabled" json with
      | Error e -> Error e
      | Ok read_enabled ->
          begin match optional_bool "write_enabled" json with
          | Error e -> Error e
          | Ok write_enabled ->
              begin match optional_string "scope_json" json with
              | Error e -> Error e
              | Ok scope_json ->
                  Ok Domain.{ enabled; read_enabled; write_enabled; scope_json }
              end
          end
      end

let list_sources store _req =
  json (Domain.sources_response_to_yojson (Source_settings.list_sources store))

let patch_source store req =
  let id = Dream.param req "id" in
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      begin match source_patch_of_json payload with
      | Error e -> error_response e
      | Ok patch ->
          begin match Source_settings.patch_source store id patch with
          | Error (Source_settings.Source_not_found _) ->
              error_response ~status:`Not_Found ("Source not found: " ^ id)
          | Error (Source_settings.Invalid_source_scope _) ->
              error_response "invalid_source_scope"
          | Ok source -> json (Domain.source_response_to_yojson source)
          end
      end

let get_request store req =
  let id = Dream.param req "id" in
  match Runner.get_detail store id with
  | None -> error_response ~status:`Not_Found ("Request not found: " ^ id)
  | Some detail -> json (Domain.request_detail_to_yojson detail)

let review_input body =
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> Error ("Invalid JSON: " ^ e)
  | payload -> Json_util.required_string "expected_payload_hash" payload

let policy_error_response = function
  | Policy.StaleAction _ -> error_response ~status:`Conflict "stale_action"
  | Policy.WritebackAttemptNotFound _ ->
      error_response ~status:`Not_Found "writeback_attempt_not_found"
  | Policy.WritebackAttemptActive _ | Policy.WritebackAttemptStateMismatch _ ->
      error_response ~status:`Conflict "writeback_attempt_conflict"
  | error -> error_response (Policy.error_to_string error)

let approve store req =
  let id = Dream.param req "id" in
  Dream.body req >>= fun body ->
  match review_input body with
  | Error e -> error_response e
  | Ok expected_payload_hash ->
      begin match Runner.approve ~expected_payload_hash store id with
      | Ok approval ->
          json (`Assoc [ ("approval", Domain.approval_to_yojson approval) ])
      | Error error -> policy_error_response error
      end

let edit_and_approve store req =
  let id = Dream.param req "id" in
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      begin
        match
          ( Json_util.required_string "body" payload,
            Json_util.required_string "expected_payload_hash" payload )
        with
        | Error e, _ | _, Error e -> error_response e
        | Ok edited_body, Ok expected_payload_hash ->
            begin
              match
                Runner.approve ~edited_body ~expected_payload_hash store id
              with
              | Ok approval ->
                  json
                    (`Assoc
                      [ ("approval", Domain.approval_to_yojson approval) ])
              | Error error -> policy_error_response error
            end
      end

let reject store req =
  let id = Dream.param req "id" in
  Dream.body req >>= fun body ->
  match review_input body with
  | Error e -> error_response e
  | Ok expected_payload_hash ->
      begin match Runner.reject ~expected_payload_hash store id with
      | Ok approval ->
          json (`Assoc [ ("approval", Domain.approval_to_yojson approval) ])
      | Error error -> policy_error_response error
      end

let execute_local store req =
  let id = Dream.param req "id" in
  match Runner.execute_local store id with
  | Ok action ->
      json (`Assoc [ ("action", Domain.proposed_action_to_yojson action) ])
  | Error error -> policy_error_response error

let execute_approved store gitlab_client req =
  let id = Dream.param req "id" in
  match Runner.start_writeback store id with
  | Error error -> policy_error_response error
  | Ok operation ->
      Lwt_preemptive.detach
        (fun () ->
          try gitlab_client.Gitlab_write.post (Runner.writeback_request operation)
          with _ -> Gitlab_write.Unknown "writeback_client_exception")
        ()
      >>= fun outcome ->
      begin
        match Runner.finish_writeback store operation outcome with
        | Ok (action, attempt) ->
            json (Domain.writeback_attempt_response_to_yojson action attempt)
        | Error error -> policy_error_response error
      end

let reconcile_writeback store gitlab_client req =
  let id = Dream.param req "id" in
  match Runner.prepare_reconciliation store id with
  | Error error -> policy_error_response error
  | Ok operation ->
      Lwt_preemptive.detach
        (fun () ->
          try
            gitlab_client.Gitlab_write.reconcile
              (Runner.writeback_request operation)
          with _ ->
            Gitlab_write.Reconciliation_unknown "reconciliation_client_exception")
        ()
      >>= fun outcome ->
      begin
        match Runner.finish_reconciliation store operation outcome with
        | Ok (action, attempt) ->
            json (Domain.writeback_attempt_response_to_yojson action attempt)
        | Error error -> policy_error_response error
      end

let abandon_writeback store req =
  let id = Dream.param req "id" in
  match Runner.abandon_writeback store id with
  | Ok (action, attempt) ->
      json (Domain.writeback_attempt_response_to_yojson action attempt)
  | Error error -> policy_error_response error

let is_v0_target target =
  let path =
    match String.index_opt target '?' with
    | None -> target
    | Some index -> String.sub target 0 index
  in
  path = "/v0" || String.starts_with ~prefix:"/v0/" path

let routes ?(gitlab_client = Gitlab_write.real_client) store capability_token =
  let router =
    Dream.router
      [
        Dream.get "/health" (fun _ ->
            json (`Assoc [ ("ok", `Bool true); ("service", `String "pharosd") ]));
        Dream.post "/v0/capture" (capture store);
        Dream.post "/v0/source-signals" (source_signal store);
        Dream.get "/v0/sources" (list_sources store);
        Dream.patch "/v0/sources/:id" (patch_source store);
        Dream.get "/v0/today" (fun _ ->
            json (Domain.today_decision_snapshot_to_yojson (Runner.today store)));
        Dream.get "/v0/debug/today-internal" (fun _ ->
            json (Domain.today_snapshot_to_yojson (Runner.today_internal store)));
        Dream.get "/v0/requests/:id" (get_request store);
        Dream.post "/v0/actions/:id/approve" (approve store);
        Dream.post "/v0/actions/:id/edit-and-approve" (edit_and_approve store);
        Dream.post "/v0/actions/:id/reject" (reject store);
        Dream.post "/v0/actions/:id/execute-local" (execute_local store);
        Dream.post "/v0/actions/:id/execute-approved"
          (execute_approved store gitlab_client);
        Dream.post "/v0/writeback-attempts/:id/reconcile"
          (reconcile_writeback store gitlab_client);
        Dream.post "/v0/writeback-attempts/:id/abandon"
          (abandon_writeback store);
      ]
  in
  fun req ->
    if is_v0_target (Dream.target req) then
      require_capability capability_token router req
    else router req
