open Domain

module S = Sqlite3

type t = { db : S.db }

type delivery_owner = { descriptor : Unix.file_descr }

let ensure_parent_dir path =
  match Filename.dirname path with
  | "." | "" -> ()
  | dir -> if not (Sys.file_exists dir) then Unix.mkdir dir 0o755

let absolute_path path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let rec canonical_database_path path =
  let absolute = absolute_path path in
  match Unix.realpath absolute with
  | path -> path
  | exception Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR), _, _) ->
      let parent = Unix.realpath (Filename.dirname absolute) in
      let unresolved = Filename.concat parent (Filename.basename absolute) in
      begin
        match (Unix.lstat unresolved).st_kind with
        | Unix.S_LNK ->
            let target = Unix.readlink unresolved in
            let target =
              if Filename.is_relative target then Filename.concat parent target
              else target
            in
            canonical_database_path target
        | _ -> unresolved
        | exception Unix.Unix_error (Unix.ENOENT, _, _) -> unresolved
      end

let delivery_lock_path db_path =
  canonical_database_path db_path ^ "-delivery.lock"

let reject_hard_linked_database db_path =
  try
    let canonical = canonical_database_path db_path in
    match (Unix.stat canonical).st_nlink with
    | links when links > 1 ->
        Error
          (Printf.sprintf
             "GitLab delivery refuses database files with multiple hard links: %s"
             canonical)
    | _ -> Ok ()
    | exception Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ()
  with Unix.Unix_error (error, _, _) ->
    Error
      (Printf.sprintf "Unable to inspect GitLab delivery database: %s"
         (Unix.error_message error))

let acquire_delivery_owner db_path =
  try
    ensure_parent_dir db_path;
    match reject_hard_linked_database db_path with
    | Error _ as error -> error
    | Ok () ->
      let lock_path = delivery_lock_path db_path in
      ensure_parent_dir lock_path;
      let descriptor =
        Unix.openfile lock_path [ Unix.O_WRONLY; Unix.O_CREAT ] 0o600
      in
      Unix.set_close_on_exec descriptor;
      match Unix.lockf descriptor Unix.F_TLOCK 0 with
      | () ->
          begin match reject_hard_linked_database db_path with
          | Ok () -> Ok { descriptor }
          | Error _ as error ->
              Unix.lockf descriptor Unix.F_ULOCK 0;
              Unix.close descriptor;
              error
          end
      | exception Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) ->
          Unix.close descriptor;
          Error
            (Printf.sprintf
               "GitLab delivery owner is already active for database %s" db_path)
      | exception Unix.Unix_error (error, _, _) ->
          Unix.close descriptor;
          Error
            (Printf.sprintf "Unable to acquire GitLab delivery owner: %s"
               (Unix.error_message error))
  with Unix.Unix_error (error, _, _) ->
    Error
      (Printf.sprintf "Unable to open GitLab delivery owner lock: %s"
         (Unix.error_message error))

let release_delivery_owner owner =
  (try Unix.lockf owner.descriptor Unix.F_ULOCK 0 with _ -> ());
  try Unix.close owner.descriptor with _ -> ()

let close t = ignore (S.db_close t.db)

let fail_sql msg rc = failwith (Printf.sprintf "%s: %s" msg (S.Rc.to_string rc))

let exec t sql =
  match S.exec t.db sql with
  | S.Rc.OK -> ()
  | rc -> fail_sql "SQLite exec failed" rc

let with_transaction t f =
  exec t "BEGIN IMMEDIATE";
  try
    let value = f () in
    exec t "COMMIT";
    value
  with exn ->
    (try exec t "ROLLBACK" with _ -> ());
    raise exn

let bind stmt idx data =
  match S.bind stmt idx data with
  | S.Rc.OK -> ()
  | rc -> fail_sql "SQLite bind failed" rc

let bind_text stmt idx value = bind stmt idx (S.Data.TEXT value)
let bind_opt_text stmt idx = function
  | None -> bind stmt idx S.Data.NULL
  | Some value -> bind_text stmt idx value
let bind_int stmt idx value = bind stmt idx (S.Data.INT (Int64.of_int value))
let bool_int b = if b then 1 else 0
let bind_bool stmt idx value = bind_int stmt idx (bool_int value)

let finalize stmt = ignore (S.finalize stmt)

let with_stmt t sql f =
  let stmt = S.prepare t.db sql in
  Fun.protect ~finally:(fun () -> finalize stmt) (fun () -> f stmt)

let step_done stmt =
  match S.step stmt with
  | S.Rc.DONE -> ()
  | rc -> fail_sql "SQLite step expected DONE" rc

let text_col stmt i =
  match S.column stmt i with
  | S.Data.TEXT s -> s
  | S.Data.NULL -> ""
  | data -> S.Data.to_string data |> Option.value ~default:""

let opt_text_col stmt i =
  match S.column stmt i with
  | S.Data.NULL -> None
  | S.Data.TEXT s when s = "" -> None
  | S.Data.TEXT s -> Some s
  | data -> S.Data.to_string data

let int_col stmt i =
  match S.column stmt i with
  | S.Data.INT n -> Int64.to_int n
  | S.Data.FLOAT f -> int_of_float f
  | S.Data.TEXT s -> int_of_string_opt s |> Option.value ~default:0
  | _ -> 0

let bool_col stmt i = int_col stmt i <> 0

let insert_source_signal t (s : source_signal) =
  with_stmt t {|
    INSERT INTO source_signals
    (id, kind, external_id, actor, title, body, url, occurred_at, raw_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 s.id;
    bind_text stmt 2 (source_kind_to_string s.kind);
    bind_opt_text stmt 3 s.external_id;
    bind_text stmt 4 s.actor;
    bind_text stmt 5 s.title;
    bind_text stmt 6 s.body;
    bind_opt_text stmt 7 s.url;
    bind_text stmt 8 s.occurred_at;
    bind_opt_text stmt 9 s.raw_json;
    step_done stmt)

let insert_work_request t (r : work_request) =
  with_stmt t {|
    INSERT INTO work_requests
    (id, title, summary, status, priority, risk, source_kind, source_signal_id, reason, next_step, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 r.id;
    bind_text stmt 2 r.title;
    bind_text stmt 3 r.summary;
    bind_text stmt 4 (request_status_to_string r.status);
    bind_text stmt 5 (priority_to_string r.priority);
    bind_text stmt 6 (risk_to_string r.risk);
    bind_text stmt 7 (source_kind_to_string r.source_kind);
    bind_text stmt 8 r.source_signal_id;
    bind_text stmt 9 r.reason;
    bind_text stmt 10 r.next_step;
    bind_text stmt 11 r.created_at;
    bind_text stmt 12 r.updated_at;
    step_done stmt)

let insert_action t (a : proposed_action) =
  with_stmt t {|
    INSERT INTO proposed_actions
    (id, request_id, title, body, target_kind, target_ref, risk, requires_approval, status, payload_hash, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 a.id;
    bind_text stmt 2 a.request_id;
    bind_text stmt 3 a.title;
    bind_text stmt 4 a.body;
    bind_text stmt 5 a.target_kind;
    bind_text stmt 6 a.target_ref;
    bind_text stmt 7 (risk_to_string a.risk);
    bind_int stmt 8 (bool_int a.requires_approval);
    bind_text stmt 9 (action_status_to_string a.status);
    bind_text stmt 10 a.payload_hash;
    bind_text stmt 11 a.created_at;
    bind_text stmt 12 a.updated_at;
    step_done stmt)

let insert_approval t (a : approval) =
  with_stmt t {|
    INSERT INTO approvals
    (id, action_id, action_hash, decision, approved_body, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 a.id;
    bind_text stmt 2 a.action_id;
    bind_text stmt 3 a.action_hash;
    bind_text stmt 4 (approval_decision_to_string a.decision);
    bind_opt_text stmt 5 a.approved_body;
    bind_text stmt 6 a.created_at;
    step_done stmt)

let insert_writeback_attempt t (attempt : writeback_attempt) =
  with_stmt t {|
    INSERT INTO writeback_attempts
    (id, action_id, approval_id, payload_hash, target_kind, target_ref, marker,
     status, external_id, external_url, error, created_at, updated_at,
     started_at, finished_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 attempt.id;
    bind_text stmt 2 attempt.action_id;
    bind_text stmt 3 attempt.approval_id;
    bind_text stmt 4 attempt.payload_hash;
    bind_text stmt 5 attempt.target_kind;
    bind_text stmt 6 attempt.target_ref;
    bind_text stmt 7 attempt.marker;
    bind_text stmt 8 (writeback_status_to_string attempt.status);
    bind_opt_text stmt 9 attempt.external_id;
    bind_opt_text stmt 10 attempt.external_url;
    bind_opt_text stmt 11 attempt.error;
    bind_text stmt 12 attempt.created_at;
    bind_text stmt 13 attempt.updated_at;
    bind_opt_text stmt 14 attempt.started_at;
    bind_opt_text stmt 15 attempt.finished_at;
    step_done stmt)

let insert_evidence t (e : evidence_item) =
  with_stmt t {|
    INSERT INTO evidence_items
    (id, request_id, kind, title, body, url, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 e.id;
    bind_text stmt 2 e.request_id;
    bind_text stmt 3 e.kind;
    bind_text stmt 4 e.title;
    bind_text stmt 5 e.body;
    bind_opt_text stmt 6 e.url;
    bind_text stmt 7 e.created_at;
    step_done stmt)

let latest_evidence_id_by_request_kind t ~request_id ~kind =
  with_stmt t {|
    SELECT id
    FROM evidence_items
    WHERE request_id = ? AND kind = ?
    ORDER BY created_at DESC, id DESC
    LIMIT 1
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    bind_text stmt 2 kind;
    match S.step stmt with
    | S.Rc.ROW -> Some (text_col stmt 0)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite latest_evidence_id_by_request_kind failed" rc)

let upsert_evidence_by_request_kind t (e : evidence_item) =
  match latest_evidence_id_by_request_kind t ~request_id:e.request_id ~kind:e.kind with
  | None -> insert_evidence t e
  | Some existing_id ->
      with_stmt t {|
        UPDATE evidence_items
        SET title = ?, body = ?, url = ?, created_at = ?
        WHERE id = ?
      |} (fun stmt ->
        bind_text stmt 1 e.title;
        bind_text stmt 2 e.body;
        bind_opt_text stmt 3 e.url;
        bind_text stmt 4 e.created_at;
        bind_text stmt 5 existing_id;
        step_done stmt);
      with_stmt t {|
        DELETE FROM evidence_items
        WHERE request_id = ? AND kind = ? AND id <> ?
      |} (fun stmt ->
        bind_text stmt 1 e.request_id;
        bind_text stmt 2 e.kind;
        bind_text stmt 3 existing_id;
        step_done stmt)

let delete_evidence_by_request_kind t ~request_id ~kind =
  with_stmt t {|
    DELETE FROM evidence_items
    WHERE request_id = ? AND kind = ?
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    bind_text stmt 2 kind;
    step_done stmt)

let insert_timeline t (e : timeline_event) =
  with_stmt t {|
    INSERT INTO timeline_events
    (id, request_id, kind, title, body, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  |} (fun stmt ->
    bind_text stmt 1 e.id;
    bind_text stmt 2 e.request_id;
    bind_text stmt 3 e.kind;
    bind_text stmt 4 e.title;
    bind_text stmt 5 e.body;
    bind_text stmt 6 e.created_at;
    step_done stmt)

let source_config_id kind = "src_" ^ source_kind_to_string kind

let p0_source_kinds = [ FeishuChat; FeishuProject; GitLab; FeishuDocs ]

let insert_default_source t kind =
  let now = Time.now_iso () in
  with_stmt t {|
    INSERT INTO sources
    (id, kind, enabled, read_enabled, write_enabled, scope_json, last_sync_at, last_error, created_at, updated_at)
    VALUES (?, ?, 0, 0, 0, '{}', NULL, NULL, ?, ?)
    ON CONFLICT(kind) DO NOTHING
  |} (fun stmt ->
    bind_text stmt 1 (source_config_id kind);
    bind_text stmt 2 (source_kind_to_string kind);
    bind_text stmt 3 now;
    bind_text stmt 4 now;
    step_done stmt)

let ensure_default_sources t =
  List.iter (insert_default_source t) p0_source_kinds

let connect path =
  ensure_parent_dir path;
  let db = S.db_open path in
  Migrations.run db;
  let store = { db } in
  ensure_default_sources store;
  store

let upsert_work_request_identity t (identity : work_request_identity) =
  with_stmt t {|
    INSERT INTO work_request_identities
    (identity_key, request_id, source_kind, external_key, normalized_subject, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(identity_key) DO UPDATE SET
      request_id = excluded.request_id,
      source_kind = excluded.source_kind,
      external_key = excluded.external_key,
      normalized_subject = excluded.normalized_subject,
      updated_at = excluded.updated_at
  |} (fun stmt ->
    bind_text stmt 1 identity.identity_key;
    bind_text stmt 2 identity.request_id;
    bind_text stmt 3 (source_kind_to_string identity.source_kind);
    bind_text stmt 4 identity.external_key;
    bind_text stmt 5 identity.normalized_subject;
    bind_text stmt 6 identity.created_at;
    bind_text stmt 7 identity.updated_at;
    step_done stmt)

let update_request_status t ~request_id ~status =
  with_stmt t "UPDATE work_requests SET status = ?, updated_at = ? WHERE id = ?" (fun stmt ->
    bind_text stmt 1 (request_status_to_string status);
    bind_text stmt 2 (Time.now_iso ());
    bind_text stmt 3 request_id;
    step_done stmt)

let update_work_request_triage t ~request_id ~status ~priority ~risk ~reason
    ~next_step =
  with_stmt t {|
    UPDATE work_requests
    SET status = ?, priority = ?, risk = ?, reason = ?, next_step = ?, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 (request_status_to_string status);
    bind_text stmt 2 (priority_to_string priority);
    bind_text stmt 3 (risk_to_string risk);
    bind_text stmt 4 reason;
    bind_text stmt 5 next_step;
    bind_text stmt 6 (Time.now_iso ());
    bind_text stmt 7 request_id;
    step_done stmt)

let update_work_request_skill_error t ~request_id ~reason =
  with_stmt t {|
    UPDATE work_requests
    SET status = ?, reason = ?, next_step = ?, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 (request_status_to_string NeedsContext);
    bind_text stmt 2 "A built-in skill output failed validation.";
    bind_text stmt 3 reason;
    bind_text stmt 4 (Time.now_iso ());
    bind_text stmt 5 request_id;
    step_done stmt)

let update_action_status t ~action_id ~status =
  with_stmt t "UPDATE proposed_actions SET status = ?, updated_at = ? WHERE id = ?" (fun stmt ->
    bind_text stmt 1 (action_status_to_string status);
    bind_text stmt 2 (Time.now_iso ());
    bind_text stmt 3 action_id;
    step_done stmt)

let update_action_body_status_hash t ~action_id ~body ~payload_hash ~status =
  with_stmt t "UPDATE proposed_actions SET body = ?, payload_hash = ?, status = ?, updated_at = ? WHERE id = ?" (fun stmt ->
    bind_text stmt 1 body;
    bind_text stmt 2 payload_hash;
    bind_text stmt 3 (action_status_to_string status);
    bind_text stmt 4 (Time.now_iso ());
    bind_text stmt 5 action_id;
    step_done stmt)

let update_action_from_skill t (action : proposed_action) =
  with_stmt t {|
    UPDATE proposed_actions
    SET title = ?, body = ?, target_kind = ?, target_ref = ?, risk = ?,
        requires_approval = ?, status = ?, payload_hash = ?, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 action.title;
    bind_text stmt 2 action.body;
    bind_text stmt 3 action.target_kind;
    bind_text stmt 4 action.target_ref;
    bind_text stmt 5 (risk_to_string action.risk);
    bind_bool stmt 6 action.requires_approval;
    bind_text stmt 7 (action_status_to_string action.status);
    bind_text stmt 8 action.payload_hash;
    bind_text stmt 9 action.updated_at;
    bind_text stmt 10 action.id;
    step_done stmt)

let update_work_request_from_source_signal t ~request_id ~title ~summary ~source_signal_id =
  with_stmt t {|
    UPDATE work_requests
    SET title = ?, summary = ?, source_signal_id = ?, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 title;
    bind_text stmt 2 summary;
    bind_text stmt 3 source_signal_id;
    bind_text stmt 4 (Time.now_iso ());
    bind_text stmt 5 request_id;
    step_done stmt)

let update_source_config t (source : source_config) =
  with_stmt t {|
    UPDATE sources
    SET enabled = ?, read_enabled = ?, write_enabled = ?, scope_json = ?, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_bool stmt 1 source.enabled;
    bind_bool stmt 2 source.read_enabled;
    bind_bool stmt 3 source.write_enabled;
    bind_text stmt 4 source.scope_json;
    bind_text stmt 5 source.updated_at;
    bind_text stmt 6 source.id;
    step_done stmt)

let row_to_work_request stmt : work_request =
  {
    id = text_col stmt 0;
    title = text_col stmt 1;
    summary = text_col stmt 2;
    status = request_status_of_string (text_col stmt 3);
    priority = priority_of_string (text_col stmt 4);
    risk = risk_of_string (text_col stmt 5);
    source_kind = source_kind_of_string (text_col stmt 6);
    source_signal_id = text_col stmt 7;
    reason = text_col stmt 8;
    next_step = text_col stmt 9;
    created_at = text_col stmt 10;
    updated_at = text_col stmt 11;
  }

let row_to_source_signal stmt : source_signal =
  {
    id = text_col stmt 0;
    kind = source_kind_of_string (text_col stmt 1);
    external_id = opt_text_col stmt 2;
    actor = text_col stmt 3;
    title = text_col stmt 4;
    body = text_col stmt 5;
    url = opt_text_col stmt 6;
    occurred_at = text_col stmt 7;
    raw_json = opt_text_col stmt 8;
  }

let row_to_action stmt : proposed_action =
  {
    id = text_col stmt 0;
    request_id = text_col stmt 1;
    title = text_col stmt 2;
    body = text_col stmt 3;
    target_kind = text_col stmt 4;
    target_ref = text_col stmt 5;
    risk = risk_of_string (text_col stmt 6);
    requires_approval = int_col stmt 7 <> 0;
    status = action_status_of_string (text_col stmt 8);
    payload_hash = text_col stmt 9;
    created_at = text_col stmt 10;
    updated_at = text_col stmt 11;
  }

let row_to_approval stmt : approval =
  {
    id = text_col stmt 0;
    action_id = text_col stmt 1;
    action_hash = text_col stmt 2;
    decision = approval_decision_of_string (text_col stmt 3);
    approved_body = opt_text_col stmt 4;
    created_at = text_col stmt 5;
  }

let row_to_writeback_attempt stmt : writeback_attempt =
  {
    id = text_col stmt 0;
    action_id = text_col stmt 1;
    approval_id = text_col stmt 2;
    payload_hash = text_col stmt 3;
    target_kind = text_col stmt 4;
    target_ref = text_col stmt 5;
    marker = text_col stmt 6;
    status = writeback_status_of_string (text_col stmt 7);
    external_id = opt_text_col stmt 8;
    external_url = opt_text_col stmt 9;
    error = opt_text_col stmt 10;
    created_at = text_col stmt 11;
    updated_at = text_col stmt 12;
    started_at = opt_text_col stmt 13;
    finished_at = opt_text_col stmt 14;
  }

let row_to_work_request_identity stmt : work_request_identity =
  {
    identity_key = text_col stmt 0;
    request_id = text_col stmt 1;
    source_kind = source_kind_of_string (text_col stmt 2);
    external_key = text_col stmt 3;
    normalized_subject = text_col stmt 4;
    created_at = text_col stmt 5;
    updated_at = text_col stmt 6;
  }

let row_to_source_config stmt : source_config =
  {
    id = text_col stmt 0;
    kind = source_kind_of_string (text_col stmt 1);
    enabled = bool_col stmt 2;
    read_enabled = bool_col stmt 3;
    write_enabled = bool_col stmt 4;
    scope_json = text_col stmt 5;
    last_sync_at = opt_text_col stmt 6;
    last_error = opt_text_col stmt 7;
    created_at = text_col stmt 8;
    updated_at = text_col stmt 9;
  }

let row_to_evidence stmt : evidence_item =
  {
    id = text_col stmt 0;
    request_id = text_col stmt 1;
    kind = text_col stmt 2;
    title = text_col stmt 3;
    body = text_col stmt 4;
    url = opt_text_col stmt 5;
    created_at = text_col stmt 6;
  }

let row_to_timeline stmt : timeline_event =
  {
    id = text_col stmt 0;
    request_id = text_col stmt 1;
    kind = text_col stmt 2;
    title = text_col stmt 3;
    body = text_col stmt 4;
    created_at = text_col stmt 5;
  }

let collect_rows stmt decode =
  let rec loop acc =
    match S.step stmt with
    | S.Rc.ROW -> loop (decode stmt :: acc)
    | S.Rc.DONE -> List.rev acc
    | rc -> fail_sql "SQLite step expected ROW or DONE" rc
  in
  loop []

let get_source_signal t id =
  with_stmt t {|
    SELECT id, kind, external_id, actor, title, body, url, occurred_at, raw_json
    FROM source_signals
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_source_signal stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_source_signal failed" rc)

let list_work_requests t =
  with_stmt t {|
    SELECT id, title, summary, status, priority, risk, source_kind, source_signal_id, reason, next_step, created_at, updated_at
    FROM work_requests
    ORDER BY updated_at DESC
  |} (fun stmt -> collect_rows stmt row_to_work_request)

let get_work_request t id =
  with_stmt t {|
    SELECT id, title, summary, status, priority, risk, source_kind, source_signal_id, reason, next_step, created_at, updated_at
    FROM work_requests
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_work_request stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_work_request failed" rc)

let get_action t id =
  with_stmt t {|
    SELECT id, request_id, title, body, target_kind, target_ref, risk, requires_approval, status, payload_hash, created_at, updated_at
    FROM proposed_actions
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_action stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_action failed" rc)

let list_actions_by_request t request_id =
  with_stmt t {|
    SELECT id, request_id, title, body, target_kind, target_ref, risk, requires_approval, status, payload_hash, created_at, updated_at
    FROM proposed_actions
    WHERE request_id = ?
    ORDER BY created_at ASC
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    collect_rows stmt row_to_action)

let count_evidence_by_request t request_id =
  with_stmt t "SELECT COUNT(*) FROM evidence_items WHERE request_id = ?" (fun stmt ->
    bind_text stmt 1 request_id;
    match S.step stmt with
    | S.Rc.ROW -> int_col stmt 0
    | S.Rc.DONE -> 0
    | rc -> fail_sql "SQLite count_evidence_by_request failed" rc)

let latest_action_by_request t request_id =
  with_stmt t {|
    SELECT id, request_id, title, body, target_kind, target_ref, risk, requires_approval, status, payload_hash, created_at, updated_at
    FROM proposed_actions
    WHERE request_id = ?
    ORDER BY updated_at DESC, created_at DESC
    LIMIT 1
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_action stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite latest_action_by_request failed" rc)

let get_work_request_identity t identity_key =
  with_stmt t {|
    SELECT identity_key, request_id, source_kind, external_key, normalized_subject, created_at, updated_at
    FROM work_request_identities
    WHERE identity_key = ?
  |} (fun stmt ->
    bind_text stmt 1 identity_key;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_work_request_identity stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_work_request_identity failed" rc)

let list_sources t =
  with_stmt t {|
    SELECT id, kind, enabled, read_enabled, write_enabled, scope_json, last_sync_at, last_error, created_at, updated_at
    FROM sources
    ORDER BY CASE kind
      WHEN 'feishu_chat' THEN 1
      WHEN 'feishu_project' THEN 2
      WHEN 'gitlab' THEN 3
      WHEN 'feishu_docs' THEN 4
      ELSE 99
    END, kind
  |} (fun stmt -> collect_rows stmt row_to_source_config)

let get_source t id =
  with_stmt t {|
    SELECT id, kind, enabled, read_enabled, write_enabled, scope_json, last_sync_at, last_error, created_at, updated_at
    FROM sources
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_source_config stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_source failed" rc)

let patch_source t id (patch : source_config_patch) =
  match get_source t id with
  | None -> None
  | Some source ->
      let updated = {
        source with
        enabled = Option.value patch.enabled ~default:source.enabled;
        read_enabled = Option.value patch.read_enabled ~default:source.read_enabled;
        write_enabled = Option.value patch.write_enabled ~default:source.write_enabled;
        scope_json = Option.value patch.scope_json ~default:source.scope_json;
        updated_at = Time.now_iso ();
      } in
      update_source_config t updated;
      get_source t id

let record_source_sync_success t id =
  let now = Time.now_iso () in
  with_stmt t {|
    UPDATE sources
    SET last_sync_at = ?, last_error = NULL, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 now;
    bind_text stmt 2 now;
    bind_text stmt 3 id;
    step_done stmt)

let record_source_sync_error t id error =
  with_stmt t {|
    UPDATE sources
    SET last_error = ?, updated_at = ?
    WHERE id = ?
  |} (fun stmt ->
    bind_text stmt 1 error;
    bind_text stmt 2 (Time.now_iso ());
    bind_text stmt 3 id;
    step_done stmt)

let has_reviewable_action t request_id =
  with_stmt t "SELECT 1 FROM proposed_actions WHERE request_id = ? AND status = ? LIMIT 1" (fun stmt ->
    bind_text stmt 1 request_id;
    bind_text stmt 2 (action_status_to_string ActionProposed);
    match S.step stmt with
    | S.Rc.ROW -> true
    | S.Rc.DONE -> false
    | rc -> fail_sql "SQLite has_reviewable_action failed" rc)

let list_evidence_by_request t request_id =
  with_stmt t {|
    SELECT id, request_id, kind, title, body, url, created_at
    FROM evidence_items
    WHERE request_id = ?
    ORDER BY created_at ASC
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    collect_rows stmt row_to_evidence)

let list_timeline_by_request t request_id =
  with_stmt t {|
    SELECT id, request_id, kind, title, body, created_at
    FROM timeline_events
    WHERE request_id = ?
    ORDER BY created_at ASC, rowid ASC
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    collect_rows stmt row_to_timeline)

let get_latest_approval_for_action t action_id =
  with_stmt t {|
    SELECT id, action_id, action_hash, decision, approved_body, created_at
    FROM approvals
    WHERE action_id = ? AND decision IN ('approved', 'edited_and_approved')
    ORDER BY created_at DESC, rowid DESC
    LIMIT 1
  |} (fun stmt ->
    bind_text stmt 1 action_id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_approval stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_latest_approval_for_action failed" rc)

let writeback_attempt_columns =
  "id, action_id, approval_id, payload_hash, target_kind, target_ref, marker, \
   status, external_id, external_url, error, created_at, updated_at, \
   started_at, finished_at"

let get_writeback_attempt t attempt_id =
  with_stmt t
    ("SELECT " ^ writeback_attempt_columns
     ^ " FROM writeback_attempts WHERE id = ?")
    (fun stmt ->
      bind_text stmt 1 attempt_id;
      match S.step stmt with
      | S.Rc.ROW -> Some (row_to_writeback_attempt stmt)
      | S.Rc.DONE -> None
      | rc -> fail_sql "SQLite get_writeback_attempt failed" rc)

let get_active_writeback_attempt_for_action t action_id =
  with_stmt t
    ("SELECT " ^ writeback_attempt_columns
     ^ " FROM writeback_attempts WHERE action_id = ? \
        AND status IN ('prepared', 'in_flight', 'unknown') \
        ORDER BY created_at DESC, rowid DESC LIMIT 1")
    (fun stmt ->
      bind_text stmt 1 action_id;
      match S.step stmt with
      | S.Rc.ROW -> Some (row_to_writeback_attempt stmt)
      | S.Rc.DONE -> None
      | rc -> fail_sql "SQLite get_active_writeback_attempt failed" rc)

let list_writeback_attempts_by_request t request_id =
  with_stmt t
    ("SELECT " ^ writeback_attempt_columns
     ^ " FROM writeback_attempts WHERE action_id IN \
        (SELECT id FROM proposed_actions WHERE request_id = ?) \
        ORDER BY created_at ASC, rowid ASC")
    (fun stmt ->
      bind_text stmt 1 request_id;
      collect_rows stmt row_to_writeback_attempt)

let mark_writeback_in_flight t attempt_id =
  let now = Time.now_iso () in
  with_stmt t {|
    UPDATE writeback_attempts
    SET status = 'in_flight', error = NULL, updated_at = ?, started_at = ?
    WHERE id = ? AND status = 'prepared'
  |} (fun stmt ->
    bind_text stmt 1 now;
    bind_text stmt 2 now;
    bind_text stmt 3 attempt_id;
    step_done stmt)

let claim_writeback_reconciliation t attempt_id =
  with_stmt t {|
    UPDATE writeback_attempts
    SET status = 'in_flight', error = NULL, updated_at = ?
    WHERE id = ? AND status = 'unknown'
  |} (fun stmt ->
    bind_text stmt 1 (Time.now_iso ());
    bind_text stmt 2 attempt_id;
    step_done stmt;
    S.changes t.db = 1)

let mark_writeback_confirmed t attempt_id ~external_id ~external_url =
  let now = Time.now_iso () in
  with_stmt t {|
    UPDATE writeback_attempts
    SET status = 'confirmed', external_id = ?, external_url = ?, error = NULL,
        updated_at = ?, finished_at = ?
    WHERE id = ? AND status IN ('in_flight', 'unknown')
  |} (fun stmt ->
    bind_text stmt 1 external_id;
    bind_text stmt 2 external_url;
    bind_text stmt 3 now;
    bind_text stmt 4 now;
    bind_text stmt 5 attempt_id;
    step_done stmt)

let mark_writeback_unknown t attempt_id error =
  with_stmt t {|
    UPDATE writeback_attempts
    SET status = 'unknown', error = ?, updated_at = ?
    WHERE id = ? AND status IN ('in_flight', 'unknown')
  |} (fun stmt ->
    bind_text stmt 1 error;
    bind_text stmt 2 (Time.now_iso ());
    bind_text stmt 3 attempt_id;
    step_done stmt)

let mark_writeback_failed_before_send t attempt_id error =
  let now = Time.now_iso () in
  with_stmt t {|
    UPDATE writeback_attempts
    SET status = 'failed_before_send', error = ?, updated_at = ?, finished_at = ?
    WHERE id = ? AND status = 'in_flight'
  |} (fun stmt ->
    bind_text stmt 1 error;
    bind_text stmt 2 now;
    bind_text stmt 3 now;
    bind_text stmt 4 attempt_id;
    step_done stmt)

let mark_writeback_abandoned t attempt_id =
  let now = Time.now_iso () in
  with_stmt t {|
    UPDATE writeback_attempts
    SET status = 'abandoned', updated_at = ?, finished_at = ?
    WHERE id = ? AND status = 'unknown'
  |} (fun stmt ->
    bind_text stmt 1 now;
    bind_text stmt 2 now;
    bind_text stmt 3 attempt_id;
    step_done stmt)

let recover_interrupted_writebacks t =
  with_transaction t (fun () ->
    let now = Time.now_iso () in
    with_stmt t {|
      UPDATE proposed_actions SET status = ?, updated_at = ?
      WHERE id IN (
        SELECT action_id FROM writeback_attempts WHERE status = 'prepared'
      )
    |} (fun stmt ->
      bind_text stmt 1 (action_status_to_string ActionApproved);
      bind_text stmt 2 now;
      step_done stmt);
    with_stmt t {|
      UPDATE work_requests SET status = ?, updated_at = ?
      WHERE id IN (
        SELECT request_id FROM proposed_actions WHERE id IN (
          SELECT action_id FROM writeback_attempts WHERE status = 'prepared'
        )
      )
    |} (fun stmt ->
      bind_text stmt 1 (request_status_to_string Approved);
      bind_text stmt 2 now;
      step_done stmt);
    with_stmt t {|
      UPDATE writeback_attempts
      SET status = 'failed_before_send', error = 'recovered_before_send',
          updated_at = ?, finished_at = ?
      WHERE status = 'prepared'
    |} (fun stmt ->
      bind_text stmt 1 now;
      bind_text stmt 2 now;
      step_done stmt);
    with_stmt t {|
      UPDATE proposed_actions SET status = ?, updated_at = ?
      WHERE id IN (
        SELECT action_id FROM writeback_attempts WHERE status = 'in_flight'
      )
    |} (fun stmt ->
      bind_text stmt 1 (action_status_to_string ActionExecuting);
      bind_text stmt 2 now;
      step_done stmt);
    with_stmt t {|
      UPDATE work_requests SET status = ?, updated_at = ?
      WHERE id IN (
        SELECT request_id FROM proposed_actions WHERE id IN (
          SELECT action_id FROM writeback_attempts WHERE status = 'in_flight'
        )
      )
    |} (fun stmt ->
      bind_text stmt 1 (request_status_to_string Executing);
      bind_text stmt 2 now;
      step_done stmt);
    with_stmt t {|
      UPDATE writeback_attempts
      SET status = 'unknown', error = 'recovered_in_flight_after_restart',
          updated_at = ?
      WHERE status = 'in_flight'
    |} (fun stmt ->
      bind_text stmt 1 now;
      step_done stmt))

let request_detail t request_id =
  match get_work_request t request_id with
  | None -> None
  | Some request ->
      Some {
        request;
        actions = list_actions_by_request t request_id;
        writeback_attempts = list_writeback_attempts_by_request t request_id;
        evidence = list_evidence_by_request t request_id;
        timeline = list_timeline_by_request t request_id;
      }

let today t =
  let all = list_work_requests t in
  let pick status = List.filter (fun (r : work_request) -> r.status = status) all in
  let archived_noise_count = List.length (pick Archived) in
  {
    needs_review = pick ReadyForReview;
    running = pick Running;
    needs_context = pick NeedsContext;
    new_items = List.filter (fun (r : work_request) -> r.status = New || r.status = Triaging) all;
    done_today = pick Done;
    archived_noise_count;
  }

let today_internal = today

let priority_rank = function
  | Urgent -> 0
  | High -> 1
  | Normal -> 2
  | Low -> 3

let compare_decision_cards a b =
  match compare (priority_rank a.priority) (priority_rank b.priority) with
  | 0 -> String.compare b.updated_at a.updated_at
  | n -> n

let group_for_request t (request : work_request) =
  match request.status with
  | ReadyForReview ->
      if has_reviewable_action t request.id then NeedsDecision else NeedsInput
  | _ -> attention_group_of_status request.status

let option_of_non_empty value =
  let trimmed = String.trim value in
  if trimmed = "" then None else Some value

let target_preview (action : proposed_action) =
  action.target_kind ^ " / " ^ action.target_ref

let decision_card_for_request t (request : work_request) =
  let source_url =
    match get_source_signal t request.source_signal_id with
    | None -> None
    | Some signal -> signal.url
  in
  let latest_action = latest_action_by_request t request.id in
  {
    request_id = request.id;
    title = request.title;
    summary = request.summary;
    group = group_for_request t request;
    source_kind = request.source_kind;
    source_url;
    priority = request.priority;
    risk = request.risk;
    why_now = request.reason;
    prepared_next_move =
      (match latest_action with
      | Some action -> Some action.title
      | None -> option_of_non_empty request.next_step);
    target_preview = Option.map target_preview latest_action;
    evidence_count = count_evidence_by_request t request.id;
    updated_at = request.updated_at;
    debug_status = request.status;
  }

let today_decision t =
  let all = list_work_requests t in
  let cards = List.map (decision_card_for_request t) all in
  let pick group =
    cards
    |> List.filter (fun (card : decision_card) -> card.group = group)
    |> List.sort compare_decision_cards
  in
  {
    needs_decision = pick NeedsDecision;
    needs_input = pick NeedsInput;
    watching = pick Watching;
    handled = pick Handled;
    noise = { count = List.length (pick Noise) };
  }

let row_to_metric stmt : Metrics.daily =
  {
    day = text_col stmt 0;
    source_signals = int_col stmt 1;
    work_requests = int_col stmt 2;
    ready_for_review = int_col stmt 3;
    approvals = int_col stmt 4;
    edit_approvals = int_col stmt 5;
    rejects = int_col stmt 6;
    external_writes = int_col stmt 7;
    unapproved_external_write_attempts = int_col stmt 8;
  }

let get_metric_for_day t day =
  with_stmt t {|
    SELECT day, source_signals, work_requests, ready_for_review, approvals,
           edit_approvals, rejects, external_writes,
           unapproved_external_write_attempts
    FROM metrics_daily
    WHERE day = ?
  |} (fun stmt ->
    bind_text stmt 1 day;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_metric stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_metric_for_day failed" rc)

let bump_metric t column =
  let day = Time.today_utc () in
  let sql = Printf.sprintf {|
    INSERT INTO metrics_daily(day, %s) VALUES(?, 1)
    ON CONFLICT(day) DO UPDATE SET %s = %s + 1
  |} column column column in
  with_stmt t sql (fun stmt ->
    bind_text stmt 1 day;
    step_done stmt)
