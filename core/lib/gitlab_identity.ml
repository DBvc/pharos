type object_kind = MergeRequest | Issue

type target = {
  instance_id : string;
  project_id : int;
  object_kind : object_kind;
  iid : int;
}

type instance = {
  base_url : string;
  id : string;
}

let ( let* ) value f = Result.bind value f

let has_control value =
  String.exists
    (fun ch ->
      let code = Char.code ch in
      code < 0x20 || code = 0x7f)
    value

let strip_trailing_slashes value =
  let rec loop current =
    let length = String.length current in
    if length > 0 && current.[length - 1] = '/' then
      loop (String.sub current 0 (length - 1))
    else current
  in
  loop value

let valid_percent_encoding value =
  let is_hex = function
    | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
    | _ -> false
  in
  let rec loop index =
    if index >= String.length value then true
    else if value.[index] <> '%' then loop (index + 1)
    else
      index + 2 < String.length value
      && is_hex value.[index + 1]
      && is_hex value.[index + 2]
      && loop (index + 3)
  in
  loop 0

let validate_root_path path =
  if not (valid_percent_encoding path) then
    Error "PHAROS_GITLAB_BASE_URL has malformed percent encoding"
  else
  let segments = String.split_on_char '/' path in
  let invalid_segment segment =
    let decoded = Uri.pct_decode segment in
    decoded = "." || decoded = ".." || String.contains decoded '/'
    || has_control decoded
  in
  if List.exists invalid_segment segments then
    Error "PHAROS_GITLAB_BASE_URL has an invalid relative root"
  else Ok ()

let canonical_base_url_unchecked value =
  let value = String.trim value in
  if value = "" then Error "Missing PHAROS_GITLAB_BASE_URL"
  else if has_control value then
    Error "PHAROS_GITLAB_BASE_URL contains control characters"
  else if not (valid_percent_encoding value) then
    Error "PHAROS_GITLAB_BASE_URL has malformed percent encoding"
  else
    let uri = Uri.of_string value in
    match Uri.scheme uri, Uri.host uri with
    | Some scheme, Some host when String.lowercase_ascii scheme = "https" ->
        let decoded_host = Uri.pct_decode host in
        if String.trim decoded_host = "" || has_control decoded_host then
          Error "PHAROS_GITLAB_BASE_URL has an invalid host"
        else if Option.is_some (Uri.userinfo uri) then
          Error "PHAROS_GITLAB_BASE_URL must not contain userinfo"
        else if Option.is_some (Uri.verbatim_query uri) then
          Error "PHAROS_GITLAB_BASE_URL must not contain a query"
        else if Option.is_some (Uri.fragment uri) then
          Error "PHAROS_GITLAB_BASE_URL must not contain a fragment"
        else
          let* () = validate_root_path (Uri.path uri) in
          let canonical = Uri.canonicalize uri in
          let path = Uri.path canonical |> strip_trailing_slashes in
          Ok (Uri.with_path canonical path |> Uri.to_string)
    | Some _, Some _ ->
        Error "PHAROS_GITLAB_BASE_URL must use https"
    | _ -> Error "PHAROS_GITLAB_BASE_URL must be an absolute HTTPS URL"

let canonical_base_url value =
  match canonical_base_url_unchecked value with
  | result -> result
  | exception (Invalid_argument _ | Failure _) ->
      Error "PHAROS_GITLAB_BASE_URL is not a valid HTTPS URL"

let instance_of_base_url value =
  let* base_url = canonical_base_url value in
  let canonical = "pharos.gitlab-instance.v1\000" ^ base_url in
  let id =
    Digestif.SHA256.(to_hex (digest_string canonical))
  in
  Ok { base_url; id }

let positive_int label value =
  match int_of_string_opt value with
  | Some number when number > 0 && string_of_int number = value -> Ok number
  | _ -> Error ("Invalid positive integer for " ^ label)

let valid_instance_id value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let require_instance_id value =
  if valid_instance_id value then Ok value
  else Error "Invalid GitLab instance identity"

let external_id target =
  let object_ref =
    match target.object_kind with
    | MergeRequest -> Printf.sprintf "mr/%d" target.iid
    | Issue -> Printf.sprintf "issue/%d" target.iid
  in
  Printf.sprintf "gitlab:instance/%s:project/%d:%s" target.instance_id
    target.project_id object_ref

let target_ref target =
  let object_ref =
    match target.object_kind with
    | MergeRequest -> Printf.sprintf "mr_iid=%d" target.iid
    | Issue -> Printf.sprintf "issue_iid=%d" target.iid
  in
  Printf.sprintf "instance=%s;project_id=%d;%s" target.instance_id
    target.project_id object_ref

let after_prefix prefix value =
  if String.starts_with ~prefix value then
    Some
      (String.sub value (String.length prefix)
         (String.length value - String.length prefix))
  else None

let parse_external_id value =
  match String.split_on_char ':' value with
  | [ "gitlab"; instance; project; object_ref ] ->
      begin
        match after_prefix "instance/" instance, after_prefix "project/" project with
        | Some instance_id, Some project_id ->
            let* instance_id = require_instance_id instance_id in
            let* project_id = positive_int "source project id" project_id in
            begin
              match after_prefix "mr/" object_ref, after_prefix "issue/" object_ref with
              | Some iid, None ->
                  let* iid = positive_int "source MR iid" iid in
                  Ok { instance_id; project_id; object_kind = MergeRequest; iid }
              | None, Some iid ->
                  let* iid = positive_int "source issue iid" iid in
                  Ok { instance_id; project_id; object_kind = Issue; iid }
              | _ -> Error "Invalid GitLab source object identity"
            end
        | _ -> Error "Invalid GitLab source identity"
      end
  | _ -> Error "Invalid GitLab source external_id"

let parse_target_ref ~target_kind value =
  match target_kind, String.split_on_char ';' value with
  | "gitlab.mr.comment", [ instance; project; mr ] ->
      begin
        match
          after_prefix "instance=" instance,
          after_prefix "project_id=" project,
          after_prefix "mr_iid=" mr
        with
        | Some instance_id, Some project_id, Some iid ->
            let* instance_id = require_instance_id instance_id in
            let* project_id = positive_int "project_id" project_id in
            let* iid = positive_int "mr_iid" iid in
            Ok { instance_id; project_id; object_kind = MergeRequest; iid }
        | _ -> Error "Invalid canonical GitLab MR target_ref"
      end
  | "gitlab.issue.comment", [ instance; project; issue ] ->
      begin
        match
          after_prefix "instance=" instance,
          after_prefix "project_id=" project,
          after_prefix "issue_iid=" issue
        with
        | Some instance_id, Some project_id, Some iid ->
            let* instance_id = require_instance_id instance_id in
            let* project_id = positive_int "project_id" project_id in
            let* iid = positive_int "issue_iid" iid in
            Ok { instance_id; project_id; object_kind = Issue; iid }
        | _ -> Error "Invalid canonical GitLab issue target_ref"
      end
  | "gitlab.mr.comment", _ -> Error "Invalid canonical GitLab MR target_ref"
  | "gitlab.issue.comment", _ ->
      Error "Invalid canonical GitLab issue target_ref"
  | _ -> Error ("Unsupported GitLab writeback target kind: " ^ target_kind)

let matches left right = left = right

let percent_encode value = Uri.pct_encode ~component:`Path value

let endpoint_path target =
  let project = percent_encode (string_of_int target.project_id) in
  match target.object_kind with
  | MergeRequest ->
      Printf.sprintf "/projects/%s/merge_requests/%d/notes" project target.iid
  | Issue -> Printf.sprintf "/projects/%s/issues/%d/notes" project target.iid
