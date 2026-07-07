open Pharos_core

let temp_db () =
  Filename.concat (Filename.get_temp_dir_name ()) ("pharos_policy_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let () =
  Random.self_init ();
  let path = temp_db () in
  let store = Store.connect path in
  let request = Runner.capture_manual store {
    Runner.title = Some "Policy smoke test";
    body = "Make sure approved local actions execute only after approval";
    url = None;
    actor = Some "test";
  } in
  let detail = Option.get (Runner.get_detail store request.id) in
  let action = List.hd detail.actions in
  begin match Runner.execute_local store action.id with
  | Ok _ -> failwith "execution should require approval"
  | Error (Policy.ApprovalRequired _) -> ()
  | Error err -> failwith ("unexpected error: " ^ Policy.error_to_string err)
  end;
  ignore (Result.get_ok (Runner.approve store action.id));
  ignore (Result.get_ok (Runner.execute_local store action.id));
  let detail_after = Option.get (Runner.get_detail store request.id) in
  assert (detail_after.request.status = Domain.Done);
  Store.close store;
  Sys.remove path
