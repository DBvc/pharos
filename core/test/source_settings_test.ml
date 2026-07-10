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

let with_store path f =
  let store = Store.connect path in
  Fun.protect ~finally:(fun () -> Store.close store) (fun () -> f store)

let find_kind kind sources =
  sources
  |> List.find_opt (fun (source : source_config) -> source.kind = kind)
  |> expect_some ("missing source kind " ^ source_kind_to_string kind)

let () =
  Random.self_init ();
  let path = temp_db () in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      with_store path (fun store ->
        let sources = Store.list_sources store in
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
          Store.patch_source store "src_gitlab"
            Domain.
              {
                enabled = Some true;
                read_enabled = Some true;
                write_enabled = None;
                scope_json = Some {|{"projects":[42]}|};
              }
          |> expect_some "patched gitlab source"
        in
        expect_bool "patched enabled" true updated.enabled;
        expect_bool "patched read_enabled" true updated.read_enabled;
        expect_bool "write still default false" false updated.write_enabled);

      with_store path (fun store ->
        let gitlab =
          Store.get_source store "src_gitlab"
          |> expect_some "reopened gitlab source"
        in
        expect_bool "enabled persists after reopen" true gitlab.enabled;
        expect_bool "read_enabled persists after reopen" true gitlab.read_enabled;
        expect_bool "write_enabled persists false" false gitlab.write_enabled;
        expect_string "scope_json persists" {|{"projects":[42]}|}
          gitlab.scope_json))
