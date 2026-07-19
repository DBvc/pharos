open Domain

type policy_error =
  | ActionNotFound of string
  | RequestNotFound of string
  | RiskNotExecutableInMvp of risk
  | ApprovalRequired of string
  | ApprovalHashMismatch of { action_hash : string; approval_hash : string }
  | UnsupportedPayloadHash of { action_id : string; payload_hash : string }
  | PayloadHashMismatch of {
      action_id : string;
      stored_hash : string;
      computed_hash : string;
    }
  | StaleAction of {
      action_id : string;
      expected_hash : string;
      actual_hash : string;
    }
  | ExternalWritebackNotImplemented of string
  | RejectedAction of string
  | ActionNotCurrent of string
  | ActionNotExecutableState of { action_id : string; status : action_status }
  | ExternalWritebackRiskMismatch of risk
  | ExternalTargetNotAllowed of string
  | ExternalTargetInvalid of string
  | SourceSignalNotFound of string
  | SourceWriteDisabled of source_kind
  | SourcePolicyInvalid of string
  | TargetProvenanceMismatch of string
  | ActionBodyEmpty of string
  | ActionBodyTooLong of { action_id : string; length : int; maximum : int }
  | WritebackAttemptNotFound of string
  | WritebackAttemptActive of { attempt_id : string; status : writeback_status }
  | WritebackAttemptStateMismatch of {
      attempt_id : string;
      status : writeback_status;
    }

let error_to_string = function
  | ActionNotFound id -> "Action not found: " ^ id
  | RequestNotFound id -> "Request not found: " ^ id
  | RiskNotExecutableInMvp risk -> "Risk is not executable in MVP: " ^ risk_to_string risk
  | ApprovalRequired id -> "Approval required for action: " ^ id
  | ApprovalHashMismatch { action_hash; approval_hash } ->
      Printf.sprintf "Approval hash mismatch. action=%s approval=%s" action_hash approval_hash
  | UnsupportedPayloadHash { action_id; payload_hash } ->
      Printf.sprintf "Unsupported payload hash. action=%s hash=%s"
        action_id payload_hash
  | PayloadHashMismatch { action_id; stored_hash; computed_hash } ->
      Printf.sprintf
        "Payload hash does not match current action. action=%s stored=%s computed=%s"
        action_id stored_hash computed_hash
  | StaleAction { action_id; expected_hash; actual_hash } ->
      Printf.sprintf "Stale action revision. action=%s expected=%s actual=%s"
        action_id expected_hash actual_hash
  | ExternalWritebackNotImplemented target -> "External writeback is not implemented in starter: " ^ target
  | RejectedAction id -> "Action has been rejected: " ^ id
  | ActionNotCurrent id -> "Action is not the current proposal: " ^ id
  | ActionNotExecutableState { action_id; status } ->
      Printf.sprintf "Action is not executable in status %s: %s"
        (action_status_to_string status) action_id
  | ExternalWritebackRiskMismatch risk ->
      "GitLab comment writeback requires risk l3, got: "
      ^ risk_to_string risk
  | ExternalTargetNotAllowed target ->
      "External writeback target is not allowed: " ^ target
  | ExternalTargetInvalid error ->
      "Invalid external writeback target: " ^ error
  | SourceSignalNotFound id -> "Source signal not found: " ^ id
  | SourceWriteDisabled kind ->
      "External writeback is disabled for source: " ^ source_kind_to_string kind
  | SourcePolicyInvalid error -> "Invalid source policy: " ^ error
  | TargetProvenanceMismatch target ->
      "External writeback target does not match source provenance: " ^ target
  | ActionBodyEmpty id -> "Action body is empty: " ^ id
  | ActionBodyTooLong { action_id; length; maximum } ->
      Printf.sprintf "Action body is too long: %s (%d > %d)" action_id length
        maximum
  | WritebackAttemptNotFound id -> "Writeback attempt not found: " ^ id
  | WritebackAttemptActive { attempt_id; status } ->
      Printf.sprintf "Writeback attempt is already active: %s (%s)" attempt_id
        (writeback_status_to_string status)
  | WritebackAttemptStateMismatch { attempt_id; status } ->
      Printf.sprintf "Writeback attempt is not valid in status %s: %s"
        (writeback_status_to_string status) attempt_id

let timeline ~request_id ~kind ~title ~body =
  {
    id = Ids.create "evt";
    request_id;
    kind;
    title;
    body;
    created_at = Time.now_iso ();
  }

let stale_if_revision_changed (action : proposed_action) ~expected_payload_hash =
  if action.status <> ActionProposed || action.payload_hash <> expected_payload_hash then
    Error
      (StaleAction
         {
           action_id = action.id;
           expected_hash = expected_payload_hash;
           actual_hash = action.payload_hash;
         })
  else Ok ()

let require_current_payload_hash (action : proposed_action) =
  if not (payload_hash_is_v2 action.payload_hash) then
    Error
      (UnsupportedPayloadHash
         { action_id = action.id; payload_hash = action.payload_hash })
  else
    let computed_hash =
      payload_hash ~target_kind:action.target_kind ~target_ref:action.target_ref
        ~risk:action.risk ~body:action.body
    in
    if action.payload_hash = computed_hash then Ok ()
    else
      Error
        (PayloadHashMismatch
           {
             action_id = action.id;
             stored_hash = action.payload_hash;
             computed_hash;
           })

let approve ?edited_body ~expected_payload_hash store action_id =
  Store.with_transaction store (fun () ->
    match Store.get_action store action_id with
    | None -> Error (ActionNotFound action_id)
    | Some action ->
        begin match stale_if_revision_changed action ~expected_payload_hash with
        | Error _ as error -> error
        | Ok () ->
            begin match require_current_payload_hash action with
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
            end
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

let verify_approval store (action : proposed_action) =
  match require_current_payload_hash action with
  | Error _ as error -> error
  | Ok () ->
      if action.requires_approval || risk_requires_approval action.risk then
        if action.status <> ActionApproved then Error (ApprovalRequired action.id)
        else
          match Store.get_latest_approval_for_action store action.id with
          | None -> Error (ApprovalRequired action.id)
          | Some approval ->
              if approval.action_hash = action.payload_hash then Ok approval
              else
                Error
                  (ApprovalHashMismatch
                     {
                       action_hash = action.payload_hash;
                       approval_hash = approval.action_hash;
                     })
      else
        let synthetic =
          {
            id = "synthetic_no_approval_required";
            action_id = action.id;
            action_hash = action.payload_hash;
            decision = ApprovedDecision;
            approved_body = Some action.body;
            created_at = Time.now_iso ();
          }
        in
        Ok synthetic

let execute_local store action_id =
  match Store.get_action store action_id with
  | None -> Error (ActionNotFound action_id)
  | Some action ->
      if action.status = ActionRejected then Error (RejectedAction action_id)
      else if not (String.starts_with ~prefix:"pharos." action.target_kind) then
        let body =
          Printf.sprintf
            "target_kind=%s; action_id=%s; reason=external_writeback_not_available"
            action.target_kind action.id
        in
        Store.insert_timeline store
          (timeline ~request_id:action.request_id ~kind:"policy_block"
             ~title:"External writeback blocked by local executor" ~body);
        Store.bump_metric store "unapproved_external_write_attempts";
        begin match require_current_payload_hash action with
        | Error _ as error -> error
        | Ok () -> Error (ExternalWritebackNotImplemented action.target_kind)
        end
      else
        match require_current_payload_hash action with
        | Error _ as error -> error
        | Ok () ->
            if not (risk_is_executable_in_mvp action.risk) then
              Error (RiskNotExecutableInMvp action.risk)
            else
              match verify_approval store action with
              | Error err -> Error err
              | Ok approval ->
                  Store.update_action_status store ~action_id
                    ~status:ActionExecuted;
                  Store.update_request_status store
                    ~request_id:action.request_id ~status:Done;
                  Store.insert_timeline store
                    (timeline ~request_id:action.request_id ~kind:"execute"
                       ~title:"Approved local action executed"
                       ~body:
                         (Printf.sprintf
                            "Executed %s using approval %s and hash %s"
                            action.id approval.id action.payload_hash));
                  Ok action

type writeback_operation = {
  attempt : writeback_attempt;
  action : proposed_action;
  approval : approval;
  request : work_request;
  source_signal : source_signal;
  target : Gitlab_write.target;
}

let max_writeback_body_length = 8000

let utf8_character_count value =
  String.fold_left
    (fun count ch ->
      if Char.code ch land 0xc0 = 0x80 then count else count + 1)
    0 value

let allowed_gitlab_target = function
  | "gitlab.mr.comment" | "gitlab.issue.comment" -> true
  | _ -> false

let source_policy_error = function
  | Source_settings.Source_not_found _ -> SourceWriteDisabled GitLab
  | Source_settings.Invalid_source_scope error -> SourcePolicyInvalid error

let validate_source_provenance (action : proposed_action)
    (signal : source_signal) (target : Gitlab_write.target) =
  if signal.kind <> GitLab then
    Error (TargetProvenanceMismatch action.target_ref)
  else
    match signal.external_id with
    | None -> Error (TargetProvenanceMismatch action.target_ref)
    | Some external_id ->
        begin
          match Gitlab_write.parse_source_external_id external_id with
          | Ok source_target
            when Gitlab_write.target_matches_source target source_target ->
              Ok ()
          | Ok _ | Error _ ->
              Error (TargetProvenanceMismatch action.target_ref)
        end

let validate_writeback_body (action : proposed_action) =
  let length = utf8_character_count action.body in
  if String.trim action.body = "" then Error (ActionBodyEmpty action.id)
  else if length > max_writeback_body_length then
    Error
      (ActionBodyTooLong
         { action_id = action.id; length; maximum = max_writeback_body_length })
  else Ok ()

let writeback_request (operation : writeback_operation) : Gitlab_write.request =
  {
    target = operation.target;
    source_url = operation.source_signal.url;
    body = operation.action.body;
    marker = operation.attempt.marker;
  }

let prepare_writeback store action_id =
  Store.with_transaction store (fun () ->
    match Store.get_action store action_id with
    | None -> Error (ActionNotFound action_id)
    | Some action ->
        begin
          match Store.get_active_writeback_attempt_for_action store action.id with
          | Some attempt ->
              Error
                (WritebackAttemptActive
                   { attempt_id = attempt.id; status = attempt.status })
          | None ->
              if action.status = ActionRejected then
                Error (RejectedAction action_id)
              else if action.status = ActionProposed then
                Error (ApprovalRequired action.id)
              else if action.status <> ActionApproved then
                Error
                  (ActionNotExecutableState
                     { action_id; status = action.status })
              else if action.risk <> L3 then
                Error (ExternalWritebackRiskMismatch action.risk)
              else if not action.requires_approval then
                Error (ApprovalRequired action.id)
              else if not (allowed_gitlab_target action.target_kind) then
                Error (ExternalTargetNotAllowed action.target_kind)
              else
                begin
                  match require_current_payload_hash action with
                  | Error _ as error -> error
                  | Ok () ->
                      begin
                        match Store.list_actions_by_request store action.request_id with
                        | [ current ] when current.id = action.id ->
                            begin
                              match verify_approval store action with
                              | Error _ as error -> error
                              | Ok approval ->
                                  begin
                                    match validate_writeback_body action with
                                    | Error _ as error -> error
                                    | Ok () ->
                                        begin
                                          match
                                            Gitlab_write.parse_target
                                              action.target_kind action.target_ref
                                          with
                                          | Error error ->
                                              Error (ExternalTargetInvalid error)
                                          | Ok target ->
                                              begin
                                                match
                                                  Store.get_work_request store
                                                    action.request_id
                                                with
                                                | None ->
                                                    Error
                                                      (RequestNotFound
                                                         action.request_id)
                                                | Some request
                                                  when request.status <> Approved
                                                       || request.source_kind
                                                          <> GitLab ->
                                                    Error
                                                      (ActionNotCurrent action.id)
                                                | Some request ->
                                                    begin
                                                      match
                                                        Source_settings.gitlab_policy
                                                          store
                                                      with
                                                      | Error error ->
                                                          Error
                                                            (source_policy_error
                                                               error)
                                                      | Ok policy
                                                        when not
                                                               policy.effective_write ->
                                                          Error
                                                            (SourceWriteDisabled
                                                               GitLab)
                                                      | Ok _ ->
                                                          begin
                                                            match
                                                              Store
                                                              .get_source_signal
                                                                store
                                                                request
                                                                .source_signal_id
                                                            with
                                                            | None ->
                                                                Error
                                                                  (SourceSignalNotFound
                                                                     request
                                                                     .source_signal_id)
                                                            | Some signal ->
                                                                begin
                                                                  match
                                                                    validate_source_provenance
                                                                      action
                                                                      signal
                                                                      target
                                                                  with
                                                                  | Error _ as error ->
                                                                      error
                                                                  | Ok () ->
                                                                      let id =
                                                                        Ids.create
                                                                          "wb"
                                                                      in
                                                                      begin
                                                                        match
                                                                          Gitlab_write
                                                                          .marker
                                                                            ~attempt_id:
                                                                              id
                                                                            ~payload_hash:
                                                                              action
                                                                              .payload_hash
                                                                        with
                                                                        | Error error ->
                                                                            Error
                                                                              (ExternalTargetInvalid
                                                                                 error)
                                                                        | Ok marker ->
                                                                            let now =
                                                                              Time
                                                                              .now_iso
                                                                                ()
                                                                            in
                                                                            let attempt =
                                                                              {
                                                                                id;
                                                                                action_id =
                                                                                  action
                                                                                  .id;
                                                                                approval_id =
                                                                                  approval
                                                                                  .id;
                                                                                payload_hash =
                                                                                  action
                                                                                  .payload_hash;
                                                                                target_kind =
                                                                                  action
                                                                                  .target_kind;
                                                                                target_ref =
                                                                                  action
                                                                                  .target_ref;
                                                                                marker;
                                                                                status =
                                                                                  WritebackPrepared;
                                                                                external_id =
                                                                                  None;
                                                                                external_url =
                                                                                  None;
                                                                                error =
                                                                                  None;
                                                                                created_at =
                                                                                  now;
                                                                                updated_at =
                                                                                  now;
                                                                                started_at =
                                                                                  None;
                                                                                finished_at =
                                                                                  None;
                                                                              }
                                                                            in
                                                                            Store
                                                                            .insert_writeback_attempt
                                                                              store
                                                                              attempt;
                                                                            Store
                                                                            .update_action_status
                                                                              store
                                                                              ~action_id:
                                                                                action
                                                                                .id
                                                                              ~status:
                                                                                ActionExecuting;
                                                                            Store
                                                                            .update_request_status
                                                                              store
                                                                              ~request_id:
                                                                                request
                                                                                .id
                                                                              ~status:
                                                                                Executing;
                                                                            Store
                                                                            .insert_timeline
                                                                              store
                                                                              (timeline
                                                                                 ~request_id:
                                                                                   request
                                                                                   .id
                                                                                 ~kind:
                                                                                   "writeback_prepared"
                                                                                 ~title:
                                                                                   "GitLab writeback prepared"
                                                                                 ~body:
                                                                                   (Printf
                                                                                    .sprintf
                                                                                      "attempt_id=%s; action_id=%s; target_kind=%s"
                                                                                      attempt
                                                                                      .id
                                                                                      action
                                                                                      .id
                                                                                      action
                                                                                      .target_kind));
                                                                            Ok
                                                                              {
                                                                                attempt;
                                                                                action;
                                                                                approval;
                                                                                request;
                                                                                source_signal =
                                                                                  signal;
                                                                                target;
                                                                              }
                                                                      end
                                                                end
                                                          end
                                                    end
                                              end
                                        end
                                  end
                            end
                        | _ -> Error (ActionNotCurrent action.id)
                      end
                end
        end)

let writeback_block_reason = function
  | ApprovalRequired _ -> "approval_required"
  | ApprovalHashMismatch _ -> "approval_hash_mismatch"
  | UnsupportedPayloadHash _ -> "unsupported_payload_hash"
  | PayloadHashMismatch _ -> "payload_hash_mismatch"
  | ExternalWritebackRiskMismatch _ -> "risk_not_allowed"
  | ExternalTargetNotAllowed _ | ExternalTargetInvalid _ ->
      "target_not_allowed"
  | SourceWriteDisabled _ | SourcePolicyInvalid _ -> "source_write_disabled"
  | TargetProvenanceMismatch _ -> "target_provenance_mismatch"
  | ActionBodyEmpty _ | ActionBodyTooLong _ -> "invalid_body"
  | WritebackAttemptActive _ -> "active_attempt_exists"
  | _ -> "policy_preflight_failed"

let record_writeback_block store action_id error =
  match Store.get_action store action_id with
  | None -> ()
  | Some (action : proposed_action) ->
      Store.insert_timeline store
        (timeline ~request_id:action.request_id ~kind:"policy_block"
           ~title:"GitLab writeback blocked"
           ~body:
             (Printf.sprintf "action_id=%s; target_kind=%s; reason=%s"
                action.id action.target_kind (writeback_block_reason error)));
      Store.bump_metric store "unapproved_external_write_attempts"

let start_writeback store action_id =
  match prepare_writeback store action_id with
  | Error error ->
      Store.with_transaction store (fun () ->
        record_writeback_block store action_id error);
      Error error
  | Ok operation ->
      Store.with_transaction store (fun () ->
        match
          ( Store.get_writeback_attempt store operation.attempt.id,
            Store.get_action store operation.action.id,
            Store.get_latest_approval_for_action store operation.action.id )
        with
        | ( Some attempt,
            Some action,
            Some approval )
          when attempt.status = WritebackPrepared
               && action.status = ActionExecuting
               && action.payload_hash = operation.attempt.payload_hash
               && approval.id = operation.approval.id
               && approval.action_hash = operation.attempt.payload_hash ->
            Store.mark_writeback_in_flight store attempt.id;
            let attempt = Option.get (Store.get_writeback_attempt store attempt.id) in
            Ok { operation with attempt }
        | Some attempt, _, _ ->
            Error
              (WritebackAttemptStateMismatch
                 { attempt_id = attempt.id; status = attempt.status })
        | None, _, _ ->
            Error (WritebackAttemptNotFound operation.attempt.id))

let current_attempt_or_error store operation expected_status =
  match Store.get_writeback_attempt store operation.attempt.id with
  | None -> Error (WritebackAttemptNotFound operation.attempt.id)
  | Some attempt when attempt.status <> expected_status ->
      Error
        (WritebackAttemptStateMismatch
           { attempt_id = attempt.id; status = attempt.status })
  | Some attempt ->
      begin
        match Store.get_action store attempt.action_id with
        | None -> Error (ActionNotFound attempt.action_id)
        | Some action
          when action.payload_hash = attempt.payload_hash
               && action.status = ActionExecuting ->
            Ok (attempt, action)
        | Some action ->
            Error
              (ActionNotExecutableState
                 { action_id = action.id; status = action.status })
      end

let record_confirmed_writeback store operation posted =
  let attempt, action =
    Result.get_ok
      (current_attempt_or_error store operation operation.attempt.status)
  in
  Store.mark_writeback_confirmed store attempt.id
    ~external_id:posted.Gitlab_write.external_id
    ~external_url:posted.external_url;
  Store.update_action_status store ~action_id:action.id ~status:ActionExecuted;
  Store.update_request_status store ~request_id:operation.request.id ~status:Done;
  Store.insert_timeline store
    (timeline ~request_id:operation.request.id ~kind:"writeback_confirmed"
       ~title:"GitLab comment confirmed"
       ~body:
         (Printf.sprintf
            "attempt_id=%s; action_id=%s; approval_id=%s; target_kind=%s; hash=%s; external_url=%s"
            attempt.id action.id operation.approval.id action.target_kind
            action.payload_hash posted.external_url));
  Store.insert_evidence store
    {
      id = Ids.create "ev";
      request_id = operation.request.id;
      kind = "writeback.gitlab.comment";
      title = "GitLab writeback result";
      body =
        Printf.sprintf "Confirmed comment %s for %s/%s"
          posted.external_id action.target_kind action.target_ref;
      url = Some posted.external_url;
      created_at = Time.now_iso ();
    };
  Store.bump_metric store "external_writes"

let finish_writeback store operation outcome =
  Store.with_transaction store (fun () ->
    match outcome with
    | Gitlab_write.Confirmed posted ->
        begin
          match
            current_attempt_or_error store operation WritebackInFlight
          with
          | Error _ as error -> error
          | Ok _ ->
              record_confirmed_writeback store operation posted;
              Ok
                ( Option.get (Store.get_action store operation.action.id),
                  Option.get
                    (Store.get_writeback_attempt store operation.attempt.id) )
        end
    | Gitlab_write.Failed_before_send error ->
        begin
          match
            current_attempt_or_error store operation WritebackInFlight
          with
          | Error _ as error -> error
          | Ok (attempt, action) ->
              let error = Source_settings.sanitized_error error in
              Store.mark_writeback_failed_before_send store attempt.id error;
              Store.update_action_status store ~action_id:action.id
                ~status:ActionApproved;
              Store.update_request_status store ~request_id:operation.request.id
                ~status:Approved;
              Store.insert_timeline store
                (timeline ~request_id:operation.request.id
                   ~kind:"writeback_failed_before_send"
                   ~title:"GitLab writeback did not start"
                   ~body:
                     (Printf.sprintf
                        "attempt_id=%s; action_id=%s; retry_safe=true; error=%s"
                        attempt.id action.id error));
              Ok
                ( Option.get (Store.get_action store action.id),
                  Option.get (Store.get_writeback_attempt store attempt.id) )
        end
    | Gitlab_write.Unknown error ->
        begin
          match
            current_attempt_or_error store operation WritebackInFlight
          with
          | Error _ as error -> error
          | Ok (attempt, action) ->
              let error = Source_settings.sanitized_error error in
              Store.mark_writeback_unknown store attempt.id error;
              Store.insert_timeline store
                (timeline ~request_id:operation.request.id
                   ~kind:"writeback_unknown"
                   ~title:"GitLab writeback outcome unknown"
                   ~body:
                     (Printf.sprintf
                        "attempt_id=%s; action_id=%s; retry_allowed=false; error=%s"
                        attempt.id action.id error));
              Ok
                ( action,
                  Option.get (Store.get_writeback_attempt store attempt.id) )
        end)

let execute_approved ~client store action_id =
  match start_writeback store action_id with
  | Error _ as error -> error
  | Ok operation ->
      let outcome =
        try client.Gitlab_write.post (writeback_request operation)
        with _ -> Gitlab_write.Unknown "writeback_client_exception"
      in
      finish_writeback store operation outcome

let prepare_reconciliation store attempt_id =
  Store.with_transaction store (fun () ->
    match Store.get_writeback_attempt store attempt_id with
    | None -> Error (WritebackAttemptNotFound attempt_id)
    | Some attempt when attempt.status <> WritebackUnknown ->
        Error
          (WritebackAttemptStateMismatch
             { attempt_id; status = attempt.status })
    | Some attempt ->
        begin
          match
            ( Store.get_action store attempt.action_id,
              Store.get_latest_approval_for_action store attempt.action_id )
          with
          | None, _ -> Error (ActionNotFound attempt.action_id)
          | _, None -> Error (ApprovalRequired attempt.action_id)
          | Some action, Some approval
            when action.status = ActionExecuting
                 && action.payload_hash = attempt.payload_hash
                 && approval.id = attempt.approval_id
                 && approval.action_hash = attempt.payload_hash ->
              begin
                match
                  ( Gitlab_write.parse_target attempt.target_kind
                      attempt.target_ref,
                    Store.get_work_request store action.request_id )
                with
                | Error error, _ -> Error (ExternalTargetInvalid error)
                | _, None -> Error (RequestNotFound action.request_id)
                | Ok target, Some request ->
                    begin
                      match Store.get_source_signal store request.source_signal_id with
                      | None ->
                          Error (SourceSignalNotFound request.source_signal_id)
                      | Some signal ->
                          begin
                            match validate_source_provenance action signal target with
                            | Error _ as error -> error
                            | Ok () ->
                                if
                                  Store.claim_writeback_reconciliation store
                                    attempt.id
                                then
                                  let attempt =
                                    Option.get
                                      (Store.get_writeback_attempt store attempt.id)
                                  in
                                  Ok
                                    {
                                      attempt;
                                      action;
                                      approval;
                                      request;
                                      source_signal = signal;
                                      target;
                                    }
                                else
                                  let status =
                                    Store.get_writeback_attempt store attempt.id
                                    |> Option.map
                                         (fun current -> current.status)
                                    |> Option.value ~default:attempt.status
                                  in
                                  Error
                                    (WritebackAttemptStateMismatch
                                       { attempt_id; status })
                          end
                    end
              end
          | Some action, Some _ ->
              Error
                (ActionNotExecutableState
                   { action_id = action.id; status = action.status })
        end)

let finish_reconciliation store operation outcome =
  Store.with_transaction store (fun () ->
    match Store.get_writeback_attempt store operation.attempt.id with
    | None -> Error (WritebackAttemptNotFound operation.attempt.id)
    | Some attempt when attempt.status = WritebackConfirmed ->
        Ok
          ( Option.get (Store.get_action store attempt.action_id),
            attempt )
    | Some attempt when attempt.status <> WritebackInFlight ->
        Error
          (WritebackAttemptStateMismatch
             { attempt_id = attempt.id; status = attempt.status })
    | Some attempt ->
        begin
          match outcome with
          | Gitlab_write.Reconciled posted ->
              record_confirmed_writeback store operation posted;
              Ok
                ( Option.get (Store.get_action store attempt.action_id),
                  Option.get (Store.get_writeback_attempt store attempt.id) )
          | Gitlab_write.Marker_not_found ->
              Store.mark_writeback_unknown store attempt.id
                "marker_not_found_within_reconciliation_bound";
              Ok
                ( Option.get (Store.get_action store attempt.action_id),
                  Option.get (Store.get_writeback_attempt store attempt.id) )
          | Gitlab_write.Reconciliation_unknown error ->
              Store.mark_writeback_unknown store attempt.id
                (Source_settings.sanitized_error error);
              Ok
                ( Option.get (Store.get_action store attempt.action_id),
                  Option.get (Store.get_writeback_attempt store attempt.id) )
        end)

let reconcile_writeback ~client store attempt_id =
  match prepare_reconciliation store attempt_id with
  | Error _ as error -> error
  | Ok operation ->
      let outcome =
        try client.Gitlab_write.reconcile (writeback_request operation)
        with _ ->
          Gitlab_write.Reconciliation_unknown "reconciliation_client_exception"
      in
      finish_reconciliation store operation outcome

let abandon_writeback store attempt_id =
  Store.with_transaction store (fun () ->
    match Store.get_writeback_attempt store attempt_id with
    | None -> Error (WritebackAttemptNotFound attempt_id)
    | Some attempt when attempt.status <> WritebackUnknown ->
        Error
          (WritebackAttemptStateMismatch
             { attempt_id; status = attempt.status })
    | Some attempt ->
        begin
          match Store.get_action store attempt.action_id with
          | None -> Error (ActionNotFound attempt.action_id)
          | Some action
            when action.status = ActionExecuting
                 && action.payload_hash = attempt.payload_hash ->
              Store.mark_writeback_abandoned store attempt.id;
              Store.update_action_status store ~action_id:action.id
                ~status:ActionProposed;
              Store.update_request_status store ~request_id:action.request_id
                ~status:ReadyForReview;
              Store.insert_timeline store
                (timeline ~request_id:action.request_id
                   ~kind:"writeback_abandoned"
                   ~title:"Unknown GitLab writeback abandoned"
                   ~body:
                     (Printf.sprintf
                        "attempt_id=%s; action_id=%s; fresh_approval_required=true"
                        attempt.id action.id));
              Ok
                ( Option.get (Store.get_action store action.id),
                  Option.get (Store.get_writeback_attempt store attempt.id) )
          | Some action ->
              Error
                (ActionNotExecutableState
                   { action_id = action.id; status = action.status })
        end)
