open Pharos_core.Domain

let failf fmt = Printf.ksprintf failwith fmt

let expect_equal label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label expected actual

let expect_not_equal label left right =
  if left = right then failf "%s: hashes unexpectedly matched at %s" label left

let hash ?(target_kind = "gitlab.mr.comment")
    ?(target_ref = "project_id=42;mr_iid=7") ?(risk = L3)
    ?(body = "Ship it.\né") () =
  payload_hash ~target_kind ~target_ref ~risk ~body

let test_golden_vector () =
  expect_equal "v2 golden vector"
    "sha256:6f61c67b639f2adab56d4cec560d4a18fbf805531cebdc6fd8f74d0cce6e46f4"
    (hash ());
  if not (payload_hash_is_v2 (hash ())) then
    failf "golden vector was not recognized as a v2 payload hash"

let test_field_boundaries_are_unambiguous () =
  let left = hash ~target_kind:"gitlab\nmr" ~target_ref:"comment" () in
  let right = hash ~target_kind:"gitlab" ~target_ref:"mr\ncomment" () in
  expect_not_equal "length-prefixed field boundary" left right

let test_no_op_is_stable () =
  expect_equal "no-op stability" (hash ()) (hash ())

let test_each_field_changes_identity () =
  let baseline = hash () in
  expect_not_equal "target_kind" baseline
    (hash ~target_kind:"gitlab.issue.comment" ());
  expect_not_equal "target_ref" baseline
    (hash ~target_ref:"project_id=42;mr_iid=8" ());
  expect_not_equal "risk" baseline (hash ~risk:L2 ());
  expect_not_equal "body" baseline (hash ~body:"Ship it.\né!" ())

let test_format_is_strict () =
  let valid = hash () in
  let uppercase_digest =
    "sha256:"
    ^ (String.sub valid 7 64 |> String.uppercase_ascii)
  in
  if String.length valid <> 71 then
    failf "v2 payload hash length: expected 71, got %d" (String.length valid);
  List.iter
    (fun invalid ->
      if payload_hash_is_v2 invalid then
        failf "invalid payload hash accepted: %s" invalid)
    [
      String.uppercase_ascii valid;
      uppercase_digest;
      String.sub valid 0 70;
      "md5:0123456789abcdef0123456789abcdef";
      "0123456789abcdef0123456789abcdef";
    ]

let () =
  test_golden_vector ();
  test_field_boundaries_are_unambiguous ();
  test_no_op_is_stable ();
  test_each_field_changes_identity ();
  test_format_is_strict ()
