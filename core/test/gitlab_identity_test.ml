open Pharos_core

let failf fmt = Printf.ksprintf failwith fmt

let expect_error label = function
  | Error _ -> ()
  | Ok _ -> failf "%s: expected error" label

let test_instance_canonicalization () =
  let instance =
    Gitlab_identity.instance_of_base_url
      " HTTPS://GitLab.Example:443/root/ "
    |> Result.get_ok
  in
  if instance.base_url <> "https://gitlab.example/root" then
    failf "unexpected canonical base URL: %s" instance.base_url;
  if
    instance.id
    <> "06c772611bb7867402fb03b12d4c0b7ff5f1b9fbac9e1c11af3f4d674f470d4f"
  then failf "GitLab instance fingerprint changed: %s" instance.id;
  let same =
    Gitlab_identity.instance_of_base_url "https://gitlab.example/root"
    |> Result.get_ok
  in
  if same <> instance then failf "equivalent instance URLs did not canonicalize";
  let other_root =
    Gitlab_identity.instance_of_base_url "https://gitlab.example/other"
    |> Result.get_ok
  in
  if other_root.id = instance.id then failf "relative roots shared an identity"

let test_invalid_instance_urls () =
  List.iter
    (fun (label, value) ->
      Gitlab_identity.instance_of_base_url value |> expect_error label)
    [
      ("plain HTTP", "http://gitlab.example");
      ("userinfo", "https://user:secret@gitlab.example");
      ("query", "https://gitlab.example?tenant=one");
      ("fragment", "https://gitlab.example#root");
      ("dot segment", "https://gitlab.example/root/../other");
      ("encoded slash", "https://gitlab.example/root%2Fother");
      ("malformed percent encoding", "https://gitlab.example/root%ZZ");
      ("control", "https://gitlab.example\n.evil");
      ("encoded NUL in host", "https://%00gitlab.example");
      ("encoded newline in host", "https://%0Agitlab.example");
    ]

let test_identity_round_trip () =
  let instance =
    Gitlab_identity.instance_of_base_url "https://gitlab.example"
    |> Result.get_ok
  in
  List.iter
    (fun object_kind ->
      let target : Gitlab_identity.target =
        { instance_id = instance.id; project_id = 123; object_kind; iid = 456 }
      in
      let source_identity = Gitlab_identity.external_id target in
      let parsed_external =
        Gitlab_identity.parse_external_id source_identity |> Result.get_ok
      in
      if parsed_external <> target then failf "external identity did not round-trip";
      let target_kind =
        match object_kind with
        | Gitlab_identity.MergeRequest -> "gitlab.mr.comment"
        | Gitlab_identity.Issue -> "gitlab.issue.comment"
      in
      let target_ref = Gitlab_identity.target_ref target in
      let parsed_target =
        Gitlab_identity.parse_target_ref ~target_kind target_ref
        |> Result.get_ok
      in
      if parsed_target <> target then failf "target identity did not round-trip")
    [ Gitlab_identity.MergeRequest; Gitlab_identity.Issue ];
  expect_error "legacy source identity"
    (Gitlab_identity.parse_external_id "gitlab:project/123:mr/456");
  expect_error "legacy target identity"
    (Gitlab_identity.parse_target_ref ~target_kind:"gitlab.mr.comment"
       "project_id=123;mr_iid=456")

let () =
  test_instance_canonicalization ();
  test_invalid_instance_urls ();
  test_identity_round_trip ()
