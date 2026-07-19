type object_kind = MergeRequest | Issue

type target = {
  project_id : int;
  object_kind : object_kind;
  iid : int;
}

type post_result = {
  external_id : string;
  external_url : string;
}

type request = {
  target : target;
  source_url : string option;
  body : string;
  marker : string;
}

type delivery_outcome =
  | Confirmed of post_result
  | Failed_before_send of string
  | Unknown of string

type reconciliation_outcome =
  | Reconciled of post_result
  | Marker_not_found
  | Reconciliation_unknown of string

type client = {
  post : request -> delivery_outcome;
  reconcile : request -> reconciliation_outcome;
}

type config = {
  base_url : string;
  token : string;
}

type started_response = {
  output : string;
  response_too_large : bool;
  status : Unix.process_status;
}

type curl_outcome =
  | Before_send_error of string
  | Started of (started_response, string) result

let ( let* ) value f = Result.bind value f

let max_response_bytes = 1024 * 1024
let reconciliation_page_size = 100
let reconciliation_page_limit = 5

let normalize_optional_text = function
  | None -> None
  | Some value ->
      let trimmed = String.trim value in
      if trimmed = "" then None else Some trimmed

let strip_trailing_slashes value =
  let rec loop current =
    let length = String.length current in
    if length > 0 && current.[length - 1] = '/' then
      loop (String.sub current 0 (length - 1))
    else current
  in
  loop value

let has_header_control value =
  String.exists (function '\r' | '\n' -> true | _ -> false) value

let config_from_env () =
  match Sys.getenv_opt "PHAROS_GITLAB_BASE_URL" |> normalize_optional_text with
  | None -> Error "Missing PHAROS_GITLAB_BASE_URL"
  | Some base_url ->
      let base_url = strip_trailing_slashes base_url in
      if not (String.starts_with ~prefix:"https://" base_url) then
        Error "PHAROS_GITLAB_BASE_URL must use https for writeback"
      else
        match Sys.getenv_opt "PHAROS_GITLAB_TOKEN" |> normalize_optional_text with
        | None -> Error "Missing PHAROS_GITLAB_TOKEN"
        | Some token when has_header_control token ->
            Error "PHAROS_GITLAB_TOKEN contains invalid control characters"
        | Some token -> Ok { base_url; token }

let parse_positive_int label value =
  match int_of_string_opt value with
  | Some number when number > 0 -> Ok number
  | _ -> Error ("Invalid positive integer for " ^ label)

let value_after_prefix prefix value =
  if String.starts_with ~prefix value then
    Some
      (String.sub value (String.length prefix)
         (String.length value - String.length prefix))
  else None

let parse_target target_kind target_ref =
  match (target_kind, String.split_on_char ';' target_ref) with
  | "gitlab.mr.comment", [ project; mr ] ->
      begin
        match
          ( value_after_prefix "project_id=" project,
            value_after_prefix "mr_iid=" mr )
        with
        | Some project_id, Some iid ->
            let* project_id = parse_positive_int "project_id" project_id in
            let* iid = parse_positive_int "mr_iid" iid in
            Ok { project_id; object_kind = MergeRequest; iid }
        | _ -> Error "Invalid canonical GitLab MR target_ref"
      end
  | "gitlab.issue.comment", [ project; issue ] ->
      begin
        match
          ( value_after_prefix "project_id=" project,
            value_after_prefix "issue_iid=" issue )
        with
        | Some project_id, Some iid ->
            let* project_id = parse_positive_int "project_id" project_id in
            let* iid = parse_positive_int "issue_iid" iid in
            Ok { project_id; object_kind = Issue; iid }
        | _ -> Error "Invalid canonical GitLab issue target_ref"
      end
  | "gitlab.mr.comment", _ -> Error "Invalid canonical GitLab MR target_ref"
  | "gitlab.issue.comment", _ ->
      Error "Invalid canonical GitLab issue target_ref"
  | _ -> Error ("Unsupported GitLab writeback target kind: " ^ target_kind)

let parse_source_external_id value =
  match String.split_on_char ':' value with
  | [ "gitlab"; project; object_ref ] ->
      begin
        match value_after_prefix "project/" project with
        | None -> Error "Invalid GitLab source project identity"
        | Some project_id ->
            let* project_id =
              parse_positive_int "source project id" project_id
            in
            begin
              match
                ( value_after_prefix "mr/" object_ref,
                  value_after_prefix "issue/" object_ref )
              with
              | Some iid, None ->
                  let* iid = parse_positive_int "source MR iid" iid in
                  Ok { project_id; object_kind = MergeRequest; iid }
              | None, Some iid ->
                  let* iid = parse_positive_int "source issue iid" iid in
                  Ok { project_id; object_kind = Issue; iid }
              | _ -> Error "Invalid GitLab source object identity"
            end
      end
  | _ -> Error "Invalid GitLab source external_id"

let target_matches_source target source = target = source

let marker ~attempt_id ~payload_hash =
  if not (Domain.payload_hash_is_v2 payload_hash) then
    Error "Writeback marker requires a v2 payload hash"
  else if String.trim attempt_id = "" || has_header_control attempt_id then
    Error "Writeback marker requires a valid attempt id"
  else
    Ok
      (Printf.sprintf "<!-- pharos-writeback:%s:%s -->" attempt_id
         payload_hash)

let body_with_marker ~body ~marker = body ^ "\n\n" ^ marker

let percent_encode value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (fun ch ->
      match ch with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | '~' ->
          Buffer.add_char buffer ch
      | _ ->
          Buffer.add_string buffer (Printf.sprintf "%%%02X" (Char.code ch)))
    value;
  Buffer.contents buffer

let endpoint_path target =
  let project = percent_encode (string_of_int target.project_id) in
  match target.object_kind with
  | MergeRequest ->
      Printf.sprintf "/projects/%s/merge_requests/%d/notes" project target.iid
  | Issue -> Printf.sprintf "/projects/%s/issues/%d/notes" project target.iid

let curl_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '"' -> Buffer.add_string buffer "\\\""
      | ch -> Buffer.add_char buffer ch)
    value;
  Buffer.contents buffer

let curl_environment () =
  Unix.environment () |> Array.to_list
  |> List.filter (fun entry ->
         not (String.starts_with ~prefix:"PHAROS_GITLAB_TOKEN=" entry))
  |> Array.of_list

let read_all_bounded channel =
  let buffer = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec loop total exceeded =
    match input channel chunk 0 (Bytes.length chunk) with
    | 0 -> (Buffer.contents buffer, exceeded)
    | count ->
        let remaining = max_response_bytes - total in
        let kept = max 0 (min count remaining) in
        if kept > 0 then Buffer.add_subbytes buffer chunk 0 kept;
        loop (total + kept) (exceeded || count > kept)
  in
  loop 0 false

let curl_call config ~request ~url ~data =
  let curl = "/usr/bin/curl" in
  if not (Sys.file_exists curl) then Before_send_error "curl is required"
  else
    try
      let stdin_read, stdin_write = Unix.pipe () in
      let output_read, output_write = Unix.pipe () in
      Unix.set_close_on_exec stdin_write;
      Unix.set_close_on_exec output_read;
      let args =
        [|
          curl;
          "--disable";
          "--silent";
          "--show-error";
          "--fail-with-body";
          "--proto";
          "=https";
          "--proto-redir";
          "=https";
          "--connect-timeout";
          "15";
          "--max-time";
          "60";
          "--config";
          "-";
          "--url";
          url;
        |]
      in
      match
        Unix.create_process_env curl args (curl_environment ()) stdin_read
          output_write output_write
      with
      | exception Unix.Unix_error (error, _, _) ->
          Unix.close stdin_read;
          Unix.close stdin_write;
          Unix.close output_read;
          Unix.close output_write;
          Before_send_error ("Unable to start curl: " ^ Unix.error_message error)
      | pid ->
          Unix.close stdin_read;
          Unix.close output_write;
          let result =
            try
              let config_channel = Unix.out_channel_of_descr stdin_write in
              output_string config_channel
                ("header = \"PRIVATE-TOKEN: " ^ curl_escape config.token
               ^ "\"\n");
              output_string config_channel
                "header = \"Content-Type: application/json\"\n";
              output_string config_channel
                ("request = \"" ^ curl_escape request ^ "\"\n");
              Option.iter
                (fun value ->
                  output_string config_channel
                    ("data = \"" ^ curl_escape value ^ "\"\n"))
                data;
              close_out_noerr config_channel;
              let output_channel = Unix.in_channel_of_descr output_read in
              let output, response_too_large =
                read_all_bounded output_channel
              in
              close_in_noerr output_channel;
              let _, status = Unix.waitpid [] pid in
              Ok { output; response_too_large; status }
            with exn ->
              (try Unix.close stdin_write with _ -> ());
              (try Unix.close output_read with _ -> ());
              (try ignore (Unix.waitpid [] pid) with _ -> ());
              Error (Printexc.to_string exn)
          in
          Started result
    with Unix.Unix_error (error, _, _) ->
      Before_send_error ("Unable to prepare curl: " ^ Unix.error_message error)

let response_error response =
  if response.response_too_large then
    Some
      (Printf.sprintf "GitLab response exceeded %d bytes" max_response_bytes)
  else
    match response.status with
    | Unix.WEXITED 0 -> None
    | Unix.WEXITED code ->
        Some (Printf.sprintf "GitLab request failed with curl exit %d" code)
    | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
        Some (Printf.sprintf "GitLab request interrupted by signal %d" signal)

let response_id json =
  match Yojson.Safe.Util.member "id" json with
  | `Int value -> Some (string_of_int value)
  | `Intlit value | `String value -> normalize_optional_text (Some value)
  | _ -> None

let strip_query_and_fragment value =
  let indexes =
    [ String.index_opt value '?'; String.index_opt value '#' ]
    |> List.filter_map Fun.id
  in
  match indexes with
  | [] -> value
  | first :: rest ->
      let index = List.fold_left min first rest in
      String.sub value 0 index

let source_object_url ~base_url target source_url =
  let base_url = strip_trailing_slashes base_url in
  let source_url = strip_query_and_fragment source_url in
  let target_suffix =
    match target.object_kind with
    | MergeRequest -> Printf.sprintf "/-/merge_requests/%d" target.iid
    | Issue -> Printf.sprintf "/-/issues/%d" target.iid
  in
  if
    has_header_control source_url
    || not (String.starts_with ~prefix:(base_url ^ "/") source_url)
  then None
  else
    let path =
      String.sub source_url (String.length base_url)
        (String.length source_url - String.length base_url)
    in
    if
      String.ends_with ~suffix:target_suffix path
      && String.length path > String.length target_suffix
    then Some source_url
    else None

let fallback_external_url ~base_url ~target ~source_url ~note_id =
  match Option.bind source_url (source_object_url ~base_url target) with
  | Some object_url -> object_url ^ "#note_" ^ note_id
  | None ->
      strip_trailing_slashes base_url ^ "/api/v4" ^ endpoint_path target ^ "/"
      ^ percent_encode note_id

let result_from_note ~config ~request json =
  match response_id json with
  | None -> Error "GitLab note response is missing note id"
  | Some id ->
      let external_id = "note_" ^ id in
      let external_url =
        fallback_external_url ~base_url:config.base_url ~target:request.target
          ~source_url:request.source_url ~note_id:id
      in
      Ok { external_id; external_url }

let post request =
  match config_from_env () with
  | Error error -> Failed_before_send error
  | Ok config ->
      let url = config.base_url ^ "/api/v4" ^ endpoint_path request.target in
      let payload =
        `Assoc
          [
            ( "body",
              `String
                (body_with_marker ~body:request.body ~marker:request.marker) );
          ]
        |> Yojson.Safe.to_string
      in
      begin
        match curl_call config ~request:"POST" ~url ~data:(Some payload) with
        | Before_send_error error -> Failed_before_send error
        | Started (Error error) -> Unknown error
        | Started (Ok response) ->
            begin
              match response_error response with
              | Some error -> Unknown error
              | None ->
                  begin
                    match Yojson.Safe.from_string response.output with
                    | exception Yojson.Json_error _ ->
                        Unknown "GitLab writeback returned invalid JSON"
                    | json ->
                        begin
                          match
                            result_from_note ~config ~request json
                          with
                          | Ok result -> Confirmed result
                          | Error error -> Unknown error
                        end
                  end
            end
      end

let marker_is_exact_line body marker =
  String.split_on_char '\n' body |> List.exists (String.equal marker)

let note_with_marker marker = function
  | `Assoc _ as json ->
      begin
        match Yojson.Safe.Util.member "body" json with
        | `String body when marker_is_exact_line body marker -> Some json
        | _ -> None
      end
  | _ -> None

let reconcile request =
  match config_from_env () with
  | Error error -> Reconciliation_unknown error
  | Ok config ->
      let rec page number =
        if number > reconciliation_page_limit then Marker_not_found
        else
          let url =
            Printf.sprintf "%s/api/v4%s?per_page=%d&page=%d" config.base_url
              (endpoint_path request.target) reconciliation_page_size number
          in
          match curl_call config ~request:"GET" ~url ~data:None with
          | Before_send_error error -> Reconciliation_unknown error
          | Started (Error error) -> Reconciliation_unknown error
          | Started (Ok response) ->
              begin
                match response_error response with
                | Some error -> Reconciliation_unknown error
                | None ->
                    begin
                      match Yojson.Safe.from_string response.output with
                      | exception Yojson.Json_error _ ->
                          Reconciliation_unknown
                            "GitLab reconciliation returned invalid JSON"
                      | `List notes ->
                          begin
                            match List.find_map (note_with_marker request.marker) notes with
                            | Some note ->
                                begin
                                  match
                                    result_from_note ~config ~request note
                                  with
                                  | Ok result -> Reconciled result
                                  | Error error -> Reconciliation_unknown error
                                end
                            | None
                              when List.length notes = reconciliation_page_size ->
                                page (number + 1)
                            | None -> Marker_not_found
                          end
                      | _ ->
                          Reconciliation_unknown
                            "GitLab reconciliation expected a note list"
                    end
              end
      in
      page 1

let real_client = { post; reconcile }
