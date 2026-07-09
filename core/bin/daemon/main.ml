open Pharos_core

let ( >>= ) = Lwt.bind

let getenv_default name default =
  match Sys.getenv_opt name with Some value -> value | None -> default

let rec parse_args args db host port =
  match args with
  | [] -> (db, host, port)
  | "--db" :: value :: rest -> parse_args rest value host port
  | "--host" :: value :: rest -> parse_args rest db value port
  | "--port" :: value :: rest -> parse_args rest db host (int_of_string value)
  | _ :: rest -> parse_args rest db host port

let json value = Dream.json (Yojson.Safe.to_string value)

let error_response ?(status=`Bad_Request) message =
  Dream.json ~status (Yojson.Safe.to_string (`Assoc [ ("error", `String message) ]))

let capture store req =
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      match Runner.capture_input_of_json payload with
      | Error e -> error_response e
      | Ok input ->
          let request = Runner.capture_manual store input in
          json (`Assoc [
            ("request", Domain.work_request_to_yojson request);
            ("detail_url", `String ("/v0/requests/" ^ request.id));
          ])

let source_signal store req =
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      match Runner.source_signal_input_of_json payload with
      | Error e -> error_response e
      | Ok input ->
          let response = Runner.ingest_source_signal store input in
          json (Runner.source_signal_response_to_yojson response)

let get_request store req =
  let id = Dream.param req "id" in
  match Runner.get_detail store id with
  | None -> error_response ~status:`Not_Found ("Request not found: " ^ id)
  | Some detail -> json (Domain.request_detail_to_yojson detail)

let approve store req =
  let id = Dream.param req "id" in
  match Runner.approve store id with
  | Ok approval -> json (`Assoc [ ("approval", Domain.approval_to_yojson approval) ])
  | Error err -> error_response (Policy.error_to_string err)

let edit_and_approve store req =
  let id = Dream.param req "id" in
  Dream.body req >>= fun body ->
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error e -> error_response ("Invalid JSON: " ^ e)
  | payload ->
      begin match Json_util.required_string "body" payload with
      | Error e -> error_response e
      | Ok edited_body ->
          match Runner.approve ~edited_body store id with
          | Ok approval -> json (`Assoc [ ("approval", Domain.approval_to_yojson approval) ])
          | Error err -> error_response (Policy.error_to_string err)
      end

let reject store req =
  let id = Dream.param req "id" in
  match Runner.reject store id with
  | Ok approval -> json (`Assoc [ ("approval", Domain.approval_to_yojson approval) ])
  | Error err -> error_response (Policy.error_to_string err)

let execute_local store req =
  let id = Dream.param req "id" in
  match Runner.execute_local store id with
  | Ok action -> json (`Assoc [ ("action", Domain.proposed_action_to_yojson action) ])
  | Error err -> error_response (Policy.error_to_string err)

let routes store =
  Dream.router [
    Dream.get "/health" (fun _ -> json (`Assoc [ ("ok", `Bool true); ("service", `String "pharosd") ]));
    Dream.post "/v0/capture" (capture store);
    Dream.post "/v0/source-signals" (source_signal store);
    Dream.get "/v0/today" (fun _ -> json (Domain.today_decision_snapshot_to_yojson (Runner.today store)));
    Dream.get "/v0/debug/today-internal" (fun _ -> json (Domain.today_snapshot_to_yojson (Runner.today_internal store)));
    Dream.get "/v0/requests/:id" (get_request store);
    Dream.post "/v0/actions/:id/approve" (approve store);
    Dream.post "/v0/actions/:id/edit-and-approve" (edit_and_approve store);
    Dream.post "/v0/actions/:id/reject" (reject store);
    Dream.post "/v0/actions/:id/execute-local" (execute_local store);
  ]

let () =
  let default_db = getenv_default "PHAROS_DB" "../var/pharos.dev.sqlite" in
  let default_host = getenv_default "PHAROS_HOST" "127.0.0.1" in
  let default_port = getenv_default "PHAROS_PORT" "8765" |> int_of_string in
  let db_path, host, port = parse_args (List.tl (Array.to_list Sys.argv)) default_db default_host default_port in
  let store = Store.connect db_path in
  Printf.printf "pharosd listening on http://%s:%d\n%!" host port;
  Dream.run ~interface:host ~port (routes store)
