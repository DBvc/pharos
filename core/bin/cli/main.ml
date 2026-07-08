open Pharos_core

let db_path () =
  match Sys.getenv_opt "PHAROS_DB" with
  | Some path -> path
  | None -> "../var/pharos.dev.sqlite"

let usage () =
  prerr_endline "Usage:";
  prerr_endline "  pharos capture <body> [--title <title>] [--url <url>]";
  prerr_endline "  pharos today";
  prerr_endline "  pharos today-internal";
  prerr_endline "  pharos detail <request-id>";
  prerr_endline "  pharos approve <action-id>";
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

let () =
  match List.tl (Array.to_list Sys.argv) with
  | "capture" :: rest ->
      let title, url, body = parse_options rest None None [] in
      if String.trim body = "" then usage ();
      with_store (fun store ->
        let request = Runner.capture_manual store { Runner.title = title; body; url; actor = Some "cli" } in
        print_json (Domain.work_request_to_yojson request))
  | [ "today" ] ->
      with_store (fun store -> print_json (Domain.today_decision_snapshot_to_yojson (Runner.today store)))
  | [ "today-internal" ] ->
      with_store (fun store -> print_json (Domain.today_snapshot_to_yojson (Runner.today_internal store)))
  | [ "detail"; id ] ->
      with_store (fun store ->
        match Runner.get_detail store id with
        | None -> prerr_endline ("Request not found: " ^ id); exit 1
        | Some detail -> print_json (Domain.request_detail_to_yojson detail))
  | [ "approve"; id ] ->
      with_store (fun store ->
        match Runner.approve store id with
        | Ok approval -> print_json (Domain.approval_to_yojson approval)
        | Error err -> prerr_endline (Policy.error_to_string err); exit 1)
  | [ "execute-local"; id ] ->
      with_store (fun store ->
        match Runner.execute_local store id with
        | Ok action -> print_json (Domain.proposed_action_to_yojson action)
        | Error err -> prerr_endline (Policy.error_to_string err); exit 1)
  | _ -> usage ()
