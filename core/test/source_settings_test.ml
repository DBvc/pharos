open Pharos_core
open Pharos_core.Domain

let temp_db () =
  Filename.concat
    (Filename.get_temp_dir_name ())
    ("pharos_sources_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let failf fmt = Printf.ksprintf failwith fmt

let expect_bool label expected actual =
  if expected <> actual then
    failf "%s: expected %b, got %b" label expected actual

let expect_int label expected actual =
  if expected <> actual then
    failf "%s: expected %d, got %d" label expected actual

let expect_string label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label expected actual

let expect_some label = function
  | Some value -> value
  | None -> failf "%s: expected Some, got None" label

let result_or_fail label = function
  | Ok value -> value
  | Error error -> failf "%s: %s" label (Source_settings.error_to_string error)

let expect_invalid_scope label = function
  | Error (Source_settings.Invalid_source_scope _) -> ()
  | Error error ->
      failf "%s: unexpected error: %s" label
        (Source_settings.error_to_string error)
  | Ok _ -> failf "%s: expected invalid scope" label

let with_store path f =
  let store = Store.connect path in
  Fun.protect ~finally:(fun () -> Store.close store) (fun () -> f store)

let find_kind kind sources =
  sources
  |> List.find_opt (fun (source : source_config) -> source.kind = kind)
  |> expect_some ("missing source kind " ^ source_kind_to_string kind)

let patch ?enabled ?read_enabled ?write_enabled ?scope_json () =
  Domain.{ enabled; read_enabled; write_enabled; scope_json }

let test_scope_validation () =
  let scope =
    Source_settings.validate_scope GitLab {| { "projects": [77, 42, 77] } |}
    |> result_or_fail "canonical GitLab scope"
  in
  expect_string "canonical sorted projects" {|{"projects":[42,77]}|}
    scope.canonical_json;
  if scope.project_ids <> [ "42"; "77" ] then
    failf "canonical project ids were not sorted and deduplicated";
  let empty =
    Source_settings.validate_scope GitLab {|{"projects":[]}|}
    |> result_or_fail "empty GitLab projects"
  in
  expect_string "empty projects canonicalize to object" "{}" empty.canonical_json;
  List.iter
    (fun value ->
      expect_invalid_scope ("invalid GitLab scope " ^ value)
        (Source_settings.validate_scope GitLab value))
    [
      "not-json";
      "[]";
      {|{"project_ids":[42]}|};
      {|{"projects":["42"]}|};
      {|{"projects":[0]}|};
      {|{"projects":[-1]}|};
      {|{"projects":[42],"extra":true}|};
      {|{"projects":[42],"projects":[77]}|};
    ];
  ignore
    (Source_settings.validate_scope FeishuChat "{}"
     |> result_or_fail "empty non-GitLab scope");
  expect_invalid_scope "non-GitLab project scope"
    (Source_settings.validate_scope FeishuChat {|{"projects":[42]}|})

let () =
  Random.self_init ();
  test_scope_validation ();
  let path = temp_db () in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      with_store path (fun store ->
        let sources = Source_settings.list_sources store in
        expect_int "default source count" 4 (List.length sources);
        List.iter
          (fun (source : source_config) ->
            expect_bool
              ("write_enabled default for " ^ source_kind_to_string source.kind)
              false source.write_enabled)
          sources;
        let gitlab = find_kind GitLab sources in
        expect_string "gitlab source id" "src_gitlab" gitlab.id);

      with_store path (fun store ->
        let updated =
          Source_settings.patch_source store "src_gitlab"
            (patch ~enabled:true ~read_enabled:true
               ~scope_json:{|{"projects":[77,42,42]}|} ())
          |> result_or_fail "patched gitlab source"
        in
        expect_bool "patched enabled" true updated.enabled;
        expect_bool "patched read_enabled" true updated.read_enabled;
        expect_bool "write still default false" false updated.write_enabled;
        expect_string "scope canonicalized" {|{"projects":[42,77]}|}
          updated.scope_json;
        let policy =
          Source_settings.gitlab_policy store
          |> result_or_fail "effective GitLab policy"
        in
        expect_bool "effective read" true policy.effective_read;
        expect_bool "effective write" false policy.effective_write;
        if policy.project_ids <> [ "42"; "77" ] then
          failf "effective policy lost project ids";

        let before = Source_settings.get_source store "src_gitlab" in
        expect_invalid_scope "invalid PATCH"
          (Source_settings.patch_source store "src_gitlab"
             (patch ~scope_json:{|{"projects":[0]}|} ()));
        let after = Source_settings.get_source store "src_gitlab" in
        if before <> after then failf "invalid PATCH changed the database";

        ignore
          (Store.patch_source store "src_gitlab"
             (patch ~scope_json:"invalid persisted scope" ()));
        let invalid =
          Source_settings.get_source store "src_gitlab"
          |> expect_some "invalid persisted source remains readable"
        in
        expect_string "GET preserves invalid persisted scope"
          "invalid persisted scope" invalid.scope_json;
        expect_invalid_scope "invalid persisted policy fails closed"
          (Source_settings.gitlab_policy store);
        let preserved =
          Source_settings.patch_source store "src_gitlab"
            (patch ~write_enabled:true ())
          |> result_or_fail "omitted scope PATCH"
        in
        expect_string "omitted scope does not repair persisted value"
          "invalid persisted scope" preserved.scope_json;
        let repaired =
          Source_settings.patch_source store "src_gitlab"
            (patch ~scope_json:"{}" ())
          |> result_or_fail "repair invalid scope"
        in
        expect_string "repaired scope" "{}" repaired.scope_json);

      with_store path (fun store ->
        let gitlab =
          Source_settings.get_source store "src_gitlab"
          |> expect_some "reopened gitlab source"
        in
        expect_bool "enabled persists after reopen" true gitlab.enabled;
        expect_bool "read_enabled persists after reopen" true gitlab.read_enabled;
        expect_bool "write_enabled persists after reopen" true gitlab.write_enabled;
        expect_string "repaired scope persists" "{}" gitlab.scope_json;
        let policy =
          Source_settings.gitlab_policy store
          |> result_or_fail "reopened effective policy"
        in
        expect_bool "effective write composes enabled flags" true
          policy.effective_write))
