open Domain

module S = Sqlite3

type t = { db : S.db }

let ensure_parent_dir path =
  match Filename.dirname path with
  | "." | "" -> ()
  | dir -> if not (Sys.file_exists dir) then Unix.mkdir dir 0o755

let close t = ignore (S.db_close t.db)

let fail_sql msg rc = failwith (Printf.sprintf "%s: %s" msg (S.Rc.to_string rc))

let exec t sql =
  match S.exec t.db sql with
  | S.Rc.OK -> ()
  | rc -> fail_sql "SQLite exec failed" rc

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
    ORDER BY created_at ASC
  |} (fun stmt ->
    bind_text stmt 1 request_id;
    collect_rows stmt row_to_timeline)

let get_latest_approval_for_action t action_id =
  with_stmt t {|
    SELECT id, action_id, action_hash, decision, approved_body, created_at
    FROM approvals
    WHERE action_id = ? AND decision IN ('approved', 'edited_and_approved')
    ORDER BY created_at DESC
    LIMIT 1
  |} (fun stmt ->
    bind_text stmt 1 action_id;
    match S.step stmt with
    | S.Rc.ROW -> Some (row_to_approval stmt)
    | S.Rc.DONE -> None
    | rc -> fail_sql "SQLite get_latest_approval_for_action failed" rc)

let request_detail t request_id =
  match get_work_request t request_id with
  | None -> None
  | Some request ->
      Some {
        request;
        actions = list_actions_by_request t request_id;
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
