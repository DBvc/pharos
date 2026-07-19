open Pharos_core

let getenv_default name default =
  match Sys.getenv_opt name with Some value -> value | None -> default

let rec parse_args args db host port =
  match args with
  | [] -> (db, host, port)
  | "--db" :: value :: rest -> parse_args rest value host port
  | "--host" :: value :: rest -> parse_args rest db value port
  | "--port" :: value :: rest -> parse_args rest db host (int_of_string value)
  | _ :: rest -> parse_args rest db host port

let () =
  let default_db = getenv_default "PHAROS_DB" "../var/pharos.dev.sqlite" in
  let default_host = getenv_default "PHAROS_HOST" "127.0.0.1" in
  let default_port = getenv_default "PHAROS_PORT" "8765" |> int_of_string in
  let db_path, host, port =
    parse_args (List.tl (Array.to_list Sys.argv)) default_db default_host
      default_port
  in
  if not (Capability.is_loopback_host host) then begin
    prerr_endline "pharosd refuses non-loopback --host; use 127.0.0.1 or ::1";
    exit 2
  end;
  let capability_token =
    match Option.bind (Sys.getenv_opt "PHAROS_CAPABILITY_TOKEN") Capability.valid_token with
    | Some token -> token
    | None ->
        prerr_endline
          "pharosd requires a valid PHAROS_CAPABILITY_TOKEN before startup";
        exit 2
  in
  match Store.acquire_delivery_owner db_path with
  | Error error ->
      prerr_endline error;
      exit 2
  | Ok owner ->
      Fun.protect
        ~finally:(fun () -> Store.release_delivery_owner owner)
        (fun () ->
          let store = Store.connect db_path in
          Fun.protect
            ~finally:(fun () -> Store.close store)
            (fun () ->
              Runner.recover_interrupted_writebacks store;
              Printf.printf "pharosd listening on http://%s:%d\n%!" host port;
              Dream.run ~interface:host ~port
                (App.routes store capability_token)))
