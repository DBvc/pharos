open Pharos_core
open Pharos_core.Domain

let temp_db () =
  Filename.concat
    (Filename.get_temp_dir_name ())
    ("pharos_today_" ^ string_of_int (Random.int 1_000_000) ^ ".sqlite")

let failf fmt = Printf.ksprintf failwith fmt

let expect_int label expected actual =
  if expected <> actual then
    failf "%s: expected %d, got %d" label expected actual

let expect_string label expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s" label expected actual

let capture store body =
  Runner.capture_manual store
    { Runner.title = Some body; body; url = None; actor = Some "test" }

let first_action store request_id =
  match Runner.get_detail store request_id with
  | None -> failf "missing request detail for %s" request_id
  | Some detail ->
      begin match detail.actions with
      | action :: _ -> action
      | [] -> failf "missing action for %s" request_id
      end

let card_debug_status card =
  let json = Domain.decision_card_to_yojson card in
  Yojson.Safe.Util.member "debug_status" json |> Yojson.Safe.Util.to_string

let () =
  Random.self_init ();
  let path = temp_db () in
  let store = Store.connect path in
  Fun.protect
    ~finally:(fun () ->
      Store.close store;
      if Sys.file_exists path then Sys.remove path)
    (fun () ->
      let review_request = capture store "Review the billing retry MR" in
      let today_after_capture = Runner.today store in
      expect_int "manual capture needs_decision count" 1
        (List.length today_after_capture.needs_decision);
      let review_card = List.hd today_after_capture.needs_decision in
      expect_string "needs_decision request_id" review_request.id
        review_card.request_id;
      expect_string "needs_decision group" "needs_decision"
        (Domain.attention_group_to_string review_card.group);
      expect_int "manual capture evidence count" 1 review_card.evidence_count;
      expect_string "debug_status" "ready_for_review"
        (card_debug_status review_card);

      let action = first_action store review_request.id in
      ignore
        (Result.get_ok
           (Runner.approve ~expected_payload_hash:action.payload_hash store
              action.id));
      ignore (Result.get_ok (Runner.execute_local store action.id));
      let today_after_execute = Runner.today store in
      expect_int "needs_decision after execute" 0
        (List.length today_after_execute.needs_decision);
      expect_int "handled after execute" 1
        (List.length today_after_execute.handled);
      let handled_card = List.hd today_after_execute.handled in
      expect_string "handled request_id" review_request.id
        handled_card.request_id;
      expect_string "handled debug_status" "done"
        (card_debug_status handled_card);

      let rejected_request = capture store "Reject this noisy follow-up" in
      let rejected_action = first_action store rejected_request.id in
      ignore
        (Result.get_ok
           (Runner.reject
              ~expected_payload_hash:rejected_action.payload_hash store
              rejected_action.id));
      let today_after_reject = Runner.today store in
      expect_int "noise count after reject" 1 today_after_reject.noise.count;
      if
        List.exists
          (fun card -> card.request_id = rejected_request.id)
          today_after_reject.needs_decision
      then
        failf "rejected request %s should not remain in needs_decision"
          rejected_request.id)
