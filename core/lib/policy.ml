open Domain

type policy_error =
  | ActionNotFound of string
  | RequestNotFound of string
  | RiskNotExecutableInMvp of risk
  | ApprovalRequired of string
  | ApprovalHashMismatch of { action_hash : string; approval_hash : string }
  | StaleAction of {
      action_id : string;
      expected_hash : string;
      actual_hash : string;
    }
  | ExternalWritebackNotImplemented of string
  | RejectedAction of string

let error_to_string = function
  | ActionNotFound id -> "Action not found: " ^ id
  | RequestNotFound id -> "Request not found: " ^ id
  | RiskNotExecutableInMvp risk -> "Risk is not executable in MVP: " ^ risk_to_string risk
  | ApprovalRequired id -> "Approval required for action: " ^ id
  | ApprovalHashMismatch { action_hash; approval_hash } ->
      Printf.sprintf "Approval hash mismatch. action=%s approval=%s" action_hash approval_hash
  | StaleAction { action_id; expected_hash; actual_hash } ->
      Printf.sprintf "Stale action revision. action=%s expected=%s actual=%s"
        action_id expected_hash actual_hash
  | ExternalWritebackNotImplemented target -> "External writeback is not implemented in starter: " ^ target
  | RejectedAction id -> "Action has been rejected: " ^ id

let timeline ~request_id ~kind ~title ~body =
  {
    id = Ids.create "evt";
    request_id;
    kind;
    title;
    body;
    created_at = Time.now_iso ();
  }

let stale_if_revision_changed action ~expected_payload_hash =
  if action.status <> ActionProposed || action.payload_hash <> expected_payload_hash then
    Error
      (StaleAction
         {
           action_id = action.id;
           expected_hash = expected_payload_hash;
           actual_hash = action.payload_hash;
         })
  else Ok ()

let approve ?edited_body ~expected_payload_hash store action_id =
  Store.with_transaction store (fun () ->
    match Store.get_action store action_id with
    | None -> Error (ActionNotFound action_id)
    | Some action ->
        begin match stale_if_revision_changed action ~expected_payload_hash with
        | Error _ as error -> error
        | Ok () ->
            if not (risk_is_executable_in_mvp action.risk) then
              Error (RiskNotExecutableInMvp action.risk)
            else
              let body = Option.value edited_body ~default:action.body in
              let decision =
                match edited_body with
                | None -> ApprovedDecision
                | Some _ -> EditedAndApprovedDecision
              in
              let hash =
                payload_hash ~target_kind:action.target_kind
                  ~target_ref:action.target_ref ~risk:action.risk ~body
              in
              let now = Time.now_iso () in
              Store.update_action_body_status_hash store ~action_id ~body
                ~payload_hash:hash ~status:ActionApproved;
              let approval =
                {
                  id = Ids.create "appr";
                  action_id;
                  action_hash = hash;
                  decision;
                  approved_body = Some body;
                  created_at = now;
                }
              in
              Store.insert_approval store approval;
              Store.update_request_status store ~request_id:action.request_id
                ~status:Approved;
              Store.insert_timeline store
                (timeline ~request_id:action.request_id ~kind:"approval"
                   ~title:
                     (match decision with
                     | ApprovedDecision -> "Action approved"
                     | EditedAndApprovedDecision -> "Action edited and approved"
                     | RejectedDecision -> "Action rejected")
                   ~body:("Approval " ^ approval.id ^ " is bound to hash " ^ hash));
              Store.bump_metric store
                (match decision with
                | ApprovedDecision -> "approvals"
                | EditedAndApprovedDecision -> "edit_approvals"
                | RejectedDecision -> "rejects");
              Ok approval
        end)

let reject ~expected_payload_hash store action_id =
  Store.with_transaction store (fun () ->
    match Store.get_action store action_id with
    | None -> Error (ActionNotFound action_id)
    | Some action ->
        begin match stale_if_revision_changed action ~expected_payload_hash with
        | Error _ as error -> error
        | Ok () ->
            Store.update_action_status store ~action_id ~status:ActionRejected;
            Store.update_request_status store ~request_id:action.request_id
              ~status:Archived;
            let approval =
              {
                id = Ids.create "appr";
                action_id;
                action_hash = action.payload_hash;
                decision = RejectedDecision;
                approved_body = None;
                created_at = Time.now_iso ();
              }
            in
            Store.insert_approval store approval;
            Store.insert_timeline store
              (timeline ~request_id:action.request_id ~kind:"review"
                 ~title:"Action rejected"
                 ~body:("Rejected action " ^ action_id));
            Store.bump_metric store "rejects";
            Ok approval
        end)

let verify_approval store action =
  if action.requires_approval || risk_requires_approval action.risk then
    if action.status <> ActionApproved then Error (ApprovalRequired action.id)
    else
      match Store.get_latest_approval_for_action store action.id with
      | None -> Error (ApprovalRequired action.id)
      | Some approval ->
          if approval.action_hash = action.payload_hash then Ok approval
          else Error (ApprovalHashMismatch { action_hash = action.payload_hash; approval_hash = approval.action_hash })
  else
    let synthetic = {
      id = "synthetic_no_approval_required";
      action_id = action.id;
      action_hash = action.payload_hash;
      decision = ApprovedDecision;
      approved_body = Some action.body;
      created_at = Time.now_iso ();
    } in
    Ok synthetic

let execute_local store action_id =
  match Store.get_action store action_id with
  | None -> Error (ActionNotFound action_id)
  | Some action ->
      if action.status = ActionRejected then Error (RejectedAction action_id)
      else if not (String.starts_with ~prefix:"pharos." action.target_kind) then
        let body = Printf.sprintf
          "target_kind=%s; action_id=%s; reason=external_writeback_not_available"
          action.target_kind action.id
        in
        Store.insert_timeline store (timeline
          ~request_id:action.request_id
          ~kind:"policy_block"
          ~title:"External writeback blocked by local executor"
          ~body);
        Store.bump_metric store "unapproved_external_write_attempts";
        Error (ExternalWritebackNotImplemented action.target_kind)
      else if not (risk_is_executable_in_mvp action.risk) then Error (RiskNotExecutableInMvp action.risk)
      else
        match verify_approval store action with
        | Error err -> Error err
        | Ok approval ->
            Store.update_action_status store ~action_id ~status:ActionExecuted;
            Store.update_request_status store ~request_id:action.request_id ~status:Done;
            Store.insert_timeline store (timeline
              ~request_id:action.request_id
              ~kind:"execute"
              ~title:"Approved local action executed"
              ~body:(Printf.sprintf "Executed %s using approval %s and hash %s" action.id approval.id action.payload_hash));
            Ok action
