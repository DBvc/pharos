open Domain

let ( let* ) value f = Result.bind value f

type error =
  | Source_not_found of string
  | Invalid_source_scope of string

type effective_policy = {
  source : source_config;
  project_ids : string list;
  effective_read : bool;
  effective_write : bool;
}

type validated_scope = {
  canonical_json : string;
  project_ids : string list;
}

let invalid_scope kind =
  Invalid_source_scope
    (match kind with
     | GitLab ->
         "GitLab scope_json must be {} or {\"projects\":[positive integers]}"
     | _ ->
         Printf.sprintf "%s scope_json must be {}"
           (source_kind_to_string kind))

let positive_project_id = function
  | `Int value when value > 0 -> Some value
  | _ -> None

let rec collect_project_ids acc = function
  | [] -> Some (List.rev acc)
  | value :: rest ->
      begin match positive_project_id value with
      | Some project_id -> collect_project_ids (project_id :: acc) rest
      | None -> None
      end

let canonical_project_scope project_ids =
  match List.sort_uniq Int.compare project_ids with
  | [] -> { canonical_json = "{}"; project_ids = [] }
  | project_ids ->
      let values = List.map string_of_int project_ids in
      {
        canonical_json =
          Printf.sprintf "{\"projects\":[%s]}" (String.concat "," values);
        project_ids = values;
      }

let validate_scope kind value =
  let* json =
    match Yojson.Safe.from_string value with
    | json -> Ok json
    | exception Yojson.Json_error _ -> Error (invalid_scope kind)
  in
  match kind, json with
  | GitLab, `Assoc [] ->
      Ok { canonical_json = "{}"; project_ids = [] }
  | GitLab, `Assoc [ ("projects", `List values) ] ->
      begin match collect_project_ids [] values with
      | Some project_ids -> Ok (canonical_project_scope project_ids)
      | None -> Error (invalid_scope kind)
      end
  | GitLab, _ -> Error (invalid_scope kind)
  | _, `Assoc [] -> Ok { canonical_json = "{}"; project_ids = [] }
  | _, _ -> Error (invalid_scope kind)

let error_to_string = function
  | Source_not_found id -> "Source not found: " ^ id
  | Invalid_source_scope message -> message

let list_sources = Store.list_sources
let get_source = Store.get_source

let patch_source store id (patch : source_config_patch) =
  match Store.get_source store id with
  | None -> Error (Source_not_found id)
  | Some source ->
      let* scope_json =
        match patch.scope_json with
        | None -> Ok None
        | Some value ->
            let* scope = validate_scope source.kind value in
            Ok (Some scope.canonical_json)
      in
      let patch = { patch with scope_json } in
      begin match Store.patch_source store id patch with
      | Some source -> Ok source
      | None -> Error (Source_not_found id)
      end

let effective_policy store id =
  match Store.get_source store id with
  | None -> Error (Source_not_found id)
  | Some source ->
      let* scope = validate_scope source.kind source.scope_json in
      Ok {
        source;
        project_ids = scope.project_ids;
        effective_read = source.enabled && source.read_enabled;
        effective_write = source.enabled && source.write_enabled;
      }

let gitlab_policy store =
  effective_policy store (Store.source_config_id GitLab)

let utf8_prefix max_bytes value =
  if String.length value <= max_bytes then value
  else
    let stop = ref max_bytes in
    while !stop > 0 && Char.code value.[!stop] land 0xc0 = 0x80 do
      decr stop
    done;
    String.sub value 0 !stop

let sanitized_error value =
  let value =
    String.map
      (fun ch ->
        let code = Char.code ch in
        if code < 0x20 || code = 0x7f then ' ' else ch)
      value
  in
  let max_bytes = 1000 in
  utf8_prefix max_bytes value

let record_sync_success store id =
  Store.record_source_sync_success store id

let record_sync_error store id error =
  Store.record_source_sync_error store id (sanitized_error error)
