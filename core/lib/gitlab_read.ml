open Domain

let ( let* ) value f = Result.bind value f

type config = {
  base_url : string;
  token : string;
  username : string option;
  project_ids : string list;
}

type merge_request = {
  project_id : string;
  iid : int;
  title : string;
  state : string;
  author : string;
  reviewers : string list;
  web_url : string option;
  updated_at : string;
  pipeline_status : string option;
}

type discussion_note = {
  author : string;
  body : string;
}

type discussions = {
  count : int;
  unresolved_count : int;
  notes : discussion_note list;
}

type normalized = {
  signal : Runner.source_signal_input;
  evidence : Runner.evidence_input list;
}

type get_json = config -> string -> (Yojson.Safe.t, string) result

let source_id = Store.source_config_id GitLab
let max_evidence_bytes = 4000
let max_response_bytes = 10 * 1024 * 1024
let page_size = 100

let normalize_optional_text = function
  | None -> None
  | Some value ->
      let trimmed = String.trim value in
      if trimmed = "" then None else Some trimmed

let string_member name json =
  match Yojson.Safe.Util.member name json with
  | `String value -> Some value
  | _ -> None

let int_member name json =
  match Yojson.Safe.Util.member name json with
  | `Int value -> Some value
  | `Intlit value | `String value -> int_of_string_opt value
  | _ -> None

let id_member name json =
  match Yojson.Safe.Util.member name json with
  | `Int value -> Some (string_of_int value)
  | `Intlit value | `String value -> normalize_optional_text (Some value)
  | _ -> None

let bool_member name json =
  match Yojson.Safe.Util.member name json with
  | `Bool value -> Some value
  | _ -> None

let user_name json =
  match string_member "username" json with
  | Some value -> Some value
  | None -> string_member "name" json

let user_member name json =
  match Yojson.Safe.Util.member name json with
  | `Assoc _ as user -> user_name user
  | _ -> None

let user_list_member name json =
  match Yojson.Safe.Util.member name json with
  | `List users -> List.filter_map user_name users
  | _ -> []

let nested_status name json =
  match Yojson.Safe.Util.member name json with
  | `Assoc _ as value -> string_member "status" value
  | _ -> None

let pipeline_status json =
  match nested_status "head_pipeline" json with
  | Some value -> Some value
  | None -> nested_status "pipeline" json

let parse_merge_request json =
  match id_member "project_id" json, int_member "iid" json with
  | None, _ -> Error "GitLab merge request is missing project_id"
  | _, None -> Error "GitLab merge request is missing iid"
  | Some project_id, Some iid ->
      let title =
        string_member "title" json
        |> Option.value ~default:(Printf.sprintf "GitLab MR !%d" iid)
      in
      Ok {
        project_id;
        iid;
        title;
        state = string_member "state" json |> Option.value ~default:"unknown";
        author = user_member "author" json |> Option.value ~default:"gitlab";
        reviewers = user_list_member "reviewers" json;
        web_url = string_member "web_url" json |> normalize_optional_text;
        updated_at =
          string_member "updated_at" json
          |> Option.value ~default:"1970-01-01T00:00:00Z";
        pipeline_status = pipeline_status json;
      }

let parse_merge_requests json =
  match json with
  | `List values ->
      let rec loop index acc = function
        | [] -> Ok (List.rev acc)
        | value :: rest ->
            begin match parse_merge_request value with
            | Ok mr -> loop (index + 1) (mr :: acc) rest
            | Error error ->
                Error (Printf.sprintf "GitLab merge request %d: %s" index error)
            end
      in
      loop 0 [] values
  | _ -> Error "GitLab merge request response must be a JSON array"

let note_of_json json =
  match string_member "body" json |> normalize_optional_text with
  | None -> None
  | Some body ->
      Some {
        author = user_member "author" json |> Option.value ~default:"gitlab";
        body;
      }

let discussion_is_unresolved json =
  match Yojson.Safe.Util.member "notes" json with
  | `List notes ->
      List.exists (fun note ->
        bool_member "resolvable" note = Some true
        && bool_member "resolved" note <> Some true) notes
  | _ -> false

let discussion_notes json =
  match Yojson.Safe.Util.member "notes" json with
  | `List notes -> List.filter_map note_of_json notes
  | _ -> []

let parse_discussions json =
  match json with
  | `List values ->
      Ok {
        count = List.length values;
        unresolved_count =
          List.fold_left
            (fun count value ->
              if discussion_is_unresolved value then count + 1 else count)
            0 values;
        notes = List.concat_map discussion_notes values;
      }
  | _ -> Error "GitLab discussions response must be a JSON array"

let utf8_prefix max_bytes value =
  if String.length value <= max_bytes then value
  else
    let stop = ref max_bytes in
    while !stop > 0 && Char.code value.[!stop] land 0xc0 = 0x80 do
      decr stop
    done;
    String.sub value 0 !stop

let bounded_text ?(max_bytes=max_evidence_bytes) value =
  if String.length value <= max_bytes then value
  else if max_bytes <= 3 then utf8_prefix max_bytes value
  else utf8_prefix (max_bytes - 3) value ^ "..."

let take count values =
  let rec loop remaining acc = function
    | _ when remaining <= 0 -> List.rev acc
    | [] -> List.rev acc
    | value :: rest -> loop (remaining - 1) (value :: acc) rest
  in
  loop count [] values

let reviewers_text = function
  | [] -> "none"
  | values -> String.concat ", " values

let pipeline_text = function
  | None -> "unknown"
  | Some value -> value

let metadata_body mr =
  String.concat "\n" [
    "Project: " ^ mr.project_id;
    Printf.sprintf "Merge request: !%d" mr.iid;
    "State: " ^ mr.state;
    "Author: " ^ mr.author;
    "Reviewers: " ^ reviewers_text mr.reviewers;
    "Updated at: " ^ mr.updated_at;
  ]
  |> bounded_text

let discussions_body discussions =
  let header = [
    Printf.sprintf "Discussions: %d" discussions.count;
    Printf.sprintf "Unresolved: %d" discussions.unresolved_count;
  ] in
  let notes =
    discussions.notes
    |> take 20
    |> List.map (fun note ->
      "- " ^ note.author ^ ": " ^ bounded_text ~max_bytes:500 note.body)
  in
  String.concat "\n" (header @ notes) |> bounded_text

let redacted_raw_subset mr pipeline =
  `Assoc [
    ("project_id", `String mr.project_id);
    ("iid", `Int mr.iid);
    ("state", `String mr.state);
    ("author", `String mr.author);
    ("reviewers", `List (List.map (fun value -> `String value) mr.reviewers));
    ("pipeline_status",
      match pipeline with None -> `Null | Some value -> `String value);
  ]
  |> Yojson.Safe.to_string

let normalize ?pipeline_status:latest_pipeline mr discussions =
  let pipeline =
    match latest_pipeline with
    | Some _ as value -> value
    | None -> mr.pipeline_status
  in
  let body =
    String.concat "; " [
      "State: " ^ mr.state;
      "Author: " ^ mr.author;
      "Reviewers: " ^ reviewers_text mr.reviewers;
      "Pipeline: " ^ pipeline_text pipeline;
      Printf.sprintf "Discussions: %d (%d unresolved)"
        discussions.count discussions.unresolved_count;
    ]
    |> bounded_text
  in
  let metadata : Runner.evidence_input = {
    kind = "gitlab.mr.metadata";
    title = Printf.sprintf "GitLab MR !%d metadata" mr.iid;
    body = metadata_body mr;
    url = mr.web_url;
  } in
  let discussion_evidence : Runner.evidence_input = {
    kind = "gitlab.mr.discussions";
    title = Printf.sprintf "GitLab MR !%d discussions" mr.iid;
    body = discussions_body discussions;
    url = mr.web_url;
  } in
  let evidence =
    match pipeline with
    | None -> [ metadata; discussion_evidence ]
    | Some status ->
        let pipeline_evidence : Runner.evidence_input = {
          kind = "gitlab.mr.pipeline";
          title = Printf.sprintf "GitLab MR !%d pipeline" mr.iid;
          body = bounded_text ("Status: " ^ status);
          url = mr.web_url;
        } in
        [ metadata; pipeline_evidence; discussion_evidence ]
  in
  {
    signal = {
      kind = GitLab;
      external_id =
        Some (Printf.sprintf "gitlab:project/%s:mr/%d" mr.project_id mr.iid);
      actor = mr.author;
      title = mr.title;
      body;
      url = mr.web_url;
      occurred_at = mr.updated_at;
      raw_json = Some (redacted_raw_subset mr pipeline);
    };
    evidence;
  }

let strip_trailing_slashes value =
  let rec loop value =
    let length = String.length value in
    if length > 0 && value.[length - 1] = '/' then
      loop (String.sub value 0 (length - 1))
    else value
  in
  loop value

let split_projects value =
  value
  |> String.split_on_char ','
  |> List.filter_map (fun item -> normalize_optional_text (Some item))
  |> List.sort_uniq String.compare

let has_header_control value =
  String.exists (function '\r' | '\n' -> true | _ -> false) value

let config_from_env () =
  match Sys.getenv_opt "PHAROS_GITLAB_BASE_URL" |> normalize_optional_text with
  | None -> Error "Missing PHAROS_GITLAB_BASE_URL"
  | Some base_url ->
      let base_url = strip_trailing_slashes base_url in
      if not (String.starts_with ~prefix:"https://" base_url
              || String.starts_with ~prefix:"http://" base_url) then
        Error "PHAROS_GITLAB_BASE_URL must use http or https"
      else
        match Sys.getenv_opt "PHAROS_GITLAB_TOKEN" |> normalize_optional_text with
        | None -> Error "Missing PHAROS_GITLAB_TOKEN"
        | Some token when has_header_control token ->
            Error "PHAROS_GITLAB_TOKEN contains invalid control characters"
        | Some token ->
            Ok {
              base_url;
              token;
              username =
                Sys.getenv_opt "PHAROS_GITLAB_USERNAME"
                |> normalize_optional_text;
              project_ids =
                Sys.getenv_opt "PHAROS_GITLAB_PROJECTS"
                |> Option.value ~default:""
                |> split_projects;
            }

let percent_encode value =
  let buffer = Buffer.create (String.length value) in
  String.iter (fun ch ->
    match ch with
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | '~' ->
        Buffer.add_char buffer ch
    | _ -> Buffer.add_string buffer (Printf.sprintf "%%%02X" (Char.code ch))) value;
  Buffer.contents buffer

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

let curl_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter (function
    | '\\' -> Buffer.add_string buffer "\\\\"
    | '"' -> Buffer.add_string buffer "\\\""
    | ch -> Buffer.add_char buffer ch) value;
  Buffer.contents buffer

let curl_environment_from environment =
  environment
  |> Array.to_list
  |> List.filter (fun entry ->
    not (String.starts_with ~prefix:"PHAROS_GITLAB_TOKEN=" entry))
  |> Array.of_list

let curl_environment () = curl_environment_from (Unix.environment ())

let curl_get_json config path =
  let url = config.base_url ^ "/api/v4" ^ path in
  let curl = "/usr/bin/curl" in
  if not (Sys.file_exists curl) then Error "curl is required for GitLab sync"
  else
    let stdin_read, stdin_write = Unix.pipe () in
    let output_read, output_write = Unix.pipe () in
    Unix.set_close_on_exec stdin_write;
    Unix.set_close_on_exec output_read;
    let args = [|
      curl;
      "--silent";
      "--show-error";
      "--fail-with-body";
      "--get";
      "--connect-timeout"; "15";
      "--max-time"; "60";
      "--config"; "-";
      "--url"; url;
    |] in
    match Unix.create_process_env curl args (curl_environment ())
      stdin_read output_write output_write with
    | exception Unix.Unix_error (error, _, _) ->
        Unix.close stdin_read;
        Unix.close stdin_write;
        Unix.close output_read;
        Unix.close output_write;
        Error ("Unable to start curl: " ^ Unix.error_message error)
    | pid ->
        Unix.close stdin_read;
        Unix.close output_write;
        let config_channel = Unix.out_channel_of_descr stdin_write in
        output_string config_channel
          ("header = \"PRIVATE-TOKEN: " ^ curl_escape config.token ^ "\"\n");
        close_out_noerr config_channel;
        let output_channel = Unix.in_channel_of_descr output_read in
        let output, response_too_large = read_all_bounded output_channel in
        close_in_noerr output_channel;
        let _, status = Unix.waitpid [] pid in
        begin match status with
        | Unix.WEXITED 0 when response_too_large ->
            Error (Printf.sprintf "GitLab response exceeded %d bytes"
              max_response_bytes)
        | Unix.WEXITED 0 ->
            begin match Yojson.Safe.from_string output with
            | json -> Ok json
            | exception Yojson.Json_error _ ->
                Error ("GitLab returned invalid JSON for GET " ^ path)
            end
        | Unix.WEXITED code ->
            Error (Printf.sprintf "GitLab GET failed with curl exit %d" code)
        | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
            Error (Printf.sprintf "GitLab GET interrupted by signal %d" signal)
        end

let merge_request_key mr =
  Printf.sprintf "%s:%d" mr.project_id mr.iid

let deduplicate_merge_requests values =
  let seen = Hashtbl.create (List.length values) in
  List.filter (fun mr ->
    let key = merge_request_key mr in
    if Hashtbl.mem seen key then false
    else begin
      Hashtbl.add seen key ();
      true
    end) values

let path_with_page path page =
  let separator = if String.contains path '?' then "&" else "?" in
  path ^ separator ^ "page=" ^ string_of_int page

let get_json_pages get_json config path =
  let rec loop page acc =
    let* json = get_json config (path_with_page path page) in
    match json with
    | `List values ->
        let acc = List.rev_append values acc in
        if List.length values < page_size then Ok (`List (List.rev acc))
        else loop (page + 1) acc
    | _ -> Error "GitLab paginated response must be a JSON array"
  in
  loop 1 []

let list_merge_requests get_json config =
  let* review_json =
    get_json_pages get_json config
      "/merge_requests?scope=reviews_for_me&state=opened&per_page=100"
  in
  let* review_mrs = parse_merge_requests review_json in
  let rec add_projects acc = function
    | [] -> Ok (deduplicate_merge_requests acc)
    | project_id :: rest ->
        let path =
          "/projects/" ^ percent_encode project_id
          ^ "/merge_requests?state=opened&per_page=100"
        in
        let* project_json = get_json_pages get_json config path in
        let* project_mrs = parse_merge_requests project_json in
        add_projects (acc @ project_mrs) rest
  in
  add_projects review_mrs config.project_ids

let pipeline_status_from_response json =
  match json with
  | `List ((`Assoc _ as pipeline) :: _) -> Ok (string_member "status" pipeline)
  | `List [] -> Ok None
  | _ -> Error "GitLab pipeline response must be a JSON array"

let fetch_pipeline_status get_json config mr =
  match mr.pipeline_status with
  | Some _ as value -> value
  | None ->
      let path =
        Printf.sprintf
          "/projects/%s/merge_requests/%d/pipelines?per_page=1&order_by=id&sort=desc"
          (percent_encode mr.project_id) mr.iid
      in
      begin match get_json config path with
      | Error _ -> None
      | Ok json ->
          begin match pipeline_status_from_response json with
          | Ok status -> status
          | Error _ -> None
          end
      end

let fetch_and_process_merge_request get_json store config listed_mr =
  let base_path =
    Printf.sprintf "/projects/%s/merge_requests/%d"
      (percent_encode listed_mr.project_id) listed_mr.iid
  in
  let* detail_json = get_json config base_path in
  let* mr = parse_merge_request detail_json in
  let* discussions_json =
    get_json_pages get_json config (base_path ^ "/discussions?per_page=100")
  in
  let* discussions = parse_discussions discussions_json in
  let pipeline_status = fetch_pipeline_status get_json config mr in
  let normalized = normalize ?pipeline_status mr discussions in
  let response = Runner.ingest_source_signal store normalized.signal in
  Runner.attach_evidence store ~request_id:response.request.id
    ~managed_kinds:[
      "gitlab.mr.metadata";
      "gitlab.mr.pipeline";
      "gitlab.mr.discussions";
    ] normalized.evidence;
  Ok ()

let redact_token token message =
  if token = "" then message
  else
    let token_length = String.length token in
    let message_length = String.length message in
    let buffer = Buffer.create message_length in
    let rec loop index =
      if index >= message_length then ()
      else if index + token_length <= message_length
              && String.sub message index token_length = token then begin
        Buffer.add_string buffer "[REDACTED]";
        loop (index + token_length)
      end else begin
        Buffer.add_char buffer message.[index];
        loop (index + 1)
      end
    in
    loop 0;
    Buffer.contents buffer

let sync_once_with ~get_json store config =
  let run () =
    let* merge_requests = list_merge_requests get_json config in
    let rec process count = function
      | [] -> Ok count
      | mr :: rest ->
          let* () = fetch_and_process_merge_request get_json store config mr in
          process (count + 1) rest
    in
    process 0 merge_requests
  in
  let sanitize error =
    redact_token config.token error |> bounded_text ~max_bytes:1000
  in
  let record_error error =
    try Store.record_source_sync_error store source_id error
    with _ -> ()
  in
  let result =
    match run () with
    | result -> result
    | exception exn -> Error ("GitLab sync failed: " ^ Printexc.to_string exn)
  in
  match result with
  | Ok count ->
      begin match Store.record_source_sync_success store source_id with
      | () -> Ok count
      | exception exn ->
          let error =
            sanitize ("GitLab sync status update failed: " ^ Printexc.to_string exn)
          in
          record_error error;
          Error error
      end
  | Error error ->
      let error = sanitize error in
      record_error error;
      Error error

let sync_once store config = sync_once_with ~get_json:curl_get_json store config
