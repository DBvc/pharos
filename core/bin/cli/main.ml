open Pharos_core

let db_path () =
  match Sys.getenv_opt "PHAROS_DB" with
  | Some path -> path
  | None -> "../var/pharos.dev.sqlite"

let usage () =
  prerr_endline "Usage:";
  prerr_endline "  pharos capture <body> [--title <title>] [--url <url>]";
  prerr_endline "  pharos replay <path-to-json>";
  prerr_endline "  pharos sync-gitlab";
  prerr_endline "  pharos today";
  prerr_endline "  pharos today-internal";
  prerr_endline "  pharos detail <request-id>";
  prerr_endline "  pharos approve <action-id> <expected-payload-hash>";
  prerr_endline "  pharos reject <action-id> <expected-payload-hash>";
  prerr_endline "  pharos execute-local <action-id>";
  exit 2

let rec parse_options args title url body_parts =
  match args with
  | [] -> (title, url, String.concat " " (List.rev body_parts))
  | "--title" :: value :: rest -> parse_options rest (Some value) url body_parts
  | "--url" :: value :: rest -> parse_options rest title (Some value) body_parts
  | part :: rest -> parse_options rest title url (part :: body_parts)

let print_json json =
  Yojson.Safe.pretty_to_channel stdout json;
  print_newline ()

let with_store f =
  let store = Store.connect (db_path ()) in
  Fun.protect ~finally:(fun () -> Store.close store) (fun () -> f store)

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let () =
  match List.tl (Array.to_list Sys.argv) with
  | "capture" :: rest ->
      let title, url, body = parse_options rest None None [] in
      if String.trim body = "" then usage ();
      with_store (fun store ->
        let request = Runner.capture_manual store { Runner.title = title; body; url; actor = Some "cli" } in
        print_json (Domain.work_request_to_yojson request))
  | [ "replay"; path ] ->
      let body = read_file path in
      begin match Yojson.Safe.from_string body with
      | exception Yojson.Json_error e -> prerr_endline ("Invalid JSON: " ^ e); exit 1
      | payload ->
          begin match Runner.source_signal_input_of_json payload with
          | Error e -> prerr_endline e; exit 1
          | Ok input ->
              with_store (fun store ->
                let response = Runner.ingest_source_signal store input in
                print_json (Runner.source_signal_response_to_yojson response))
          end
      end
  | [ "sync-gitlab" ] ->
      with_store (fun store ->
        match Gitlab_read.config_from_env () with
        | Error error ->
            Store.record_source_sync_error store Gitlab_read.source_id error;
            prerr_endline error;
            exit 1
        | Ok config ->
            begin match Gitlab_read.sync_once store config with
            | Ok processed ->
                print_json (`Assoc [ ("processed", `Int processed) ])
            | Error error ->
                prerr_endline error;
                exit 1
            end)
  | [ "today" ] ->
      with_store (fun store -> print_json (Domain.today_decision_snapshot_to_yojson (Runner.today store)))
  | [ "today-internal" ] ->
      with_store (fun store -> print_json (Domain.today_snapshot_to_yojson (Runner.today_internal store)))
  | [ "detail"; id ] ->
      with_store (fun store ->
        match Runner.get_detail store id with
        | None -> prerr_endline ("Request not found: " ^ id); exit 1
        | Some detail -> print_json (Domain.request_detail_to_yojson detail))
  | [ "approve"; id; expected_payload_hash ] ->
      with_store (fun store ->
        match Runner.approve ~expected_payload_hash store id with
        | Ok approval -> print_json (Domain.approval_to_yojson approval)
        | Error err -> prerr_endline (Policy.error_to_string err); exit 1)
  | [ "reject"; id; expected_payload_hash ] ->
      with_store (fun store ->
        match Runner.reject ~expected_payload_hash store id with
        | Ok approval -> print_json (Domain.approval_to_yojson approval)
        | Error err -> prerr_endline (Policy.error_to_string err); exit 1)
  | [ "execute-local"; id ] ->
      with_store (fun store ->
        match Runner.execute_local store id with
        | Ok action -> print_json (Domain.proposed_action_to_yojson action)
        | Error err -> prerr_endline (Policy.error_to_string err); exit 1)
  | _ -> usage ()
