let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> failwith (Printf.sprintf "SQLite migration failed: %s" (Sqlite3.Rc.to_string rc))

let run db =
  exec db "PRAGMA journal_mode=WAL";
  exec db "PRAGMA foreign_keys=ON";
  exec db {|
    CREATE TABLE IF NOT EXISTS source_signals (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      external_id TEXT,
      actor TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      url TEXT,
      occurred_at TEXT NOT NULL,
      raw_json TEXT
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS work_requests (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      summary TEXT NOT NULL,
      status TEXT NOT NULL,
      priority TEXT NOT NULL,
      risk TEXT NOT NULL,
      source_kind TEXT NOT NULL,
      source_signal_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      next_step TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS proposed_actions (
      id TEXT PRIMARY KEY,
      request_id TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      target_kind TEXT NOT NULL,
      target_ref TEXT NOT NULL,
      risk TEXT NOT NULL,
      requires_approval INTEGER NOT NULL,
      status TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS approvals (
      id TEXT PRIMARY KEY,
      action_id TEXT NOT NULL,
      action_hash TEXT NOT NULL,
      decision TEXT NOT NULL,
      approved_body TEXT,
      created_at TEXT NOT NULL
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS evidence_items (
      id TEXT PRIMARY KEY,
      request_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      url TEXT,
      created_at TEXT NOT NULL
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS timeline_events (
      id TEXT PRIMARY KEY,
      request_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS metrics_daily (
      day TEXT PRIMARY KEY,
      source_signals INTEGER NOT NULL DEFAULT 0,
      work_requests INTEGER NOT NULL DEFAULT 0,
      ready_for_review INTEGER NOT NULL DEFAULT 0,
      approvals INTEGER NOT NULL DEFAULT 0,
      edit_approvals INTEGER NOT NULL DEFAULT 0,
      rejects INTEGER NOT NULL DEFAULT 0,
      external_writes INTEGER NOT NULL DEFAULT 0,
      unapproved_external_write_attempts INTEGER NOT NULL DEFAULT 0
    )
  |};
  exec db {|
    CREATE TABLE IF NOT EXISTS work_request_identities (
      identity_key TEXT PRIMARY KEY,
      request_id TEXT NOT NULL,
      source_kind TEXT NOT NULL,
      external_key TEXT NOT NULL,
      normalized_subject TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  |};
  exec db "CREATE INDEX IF NOT EXISTS idx_work_requests_status ON work_requests(status)";
  exec db "CREATE INDEX IF NOT EXISTS idx_actions_request_id ON proposed_actions(request_id)";
  exec db "CREATE INDEX IF NOT EXISTS idx_evidence_request_id ON evidence_items(request_id)";
  exec db "CREATE INDEX IF NOT EXISTS idx_timeline_request_id ON timeline_events(request_id)";
  exec db "CREATE INDEX IF NOT EXISTS idx_work_request_identities_request_id ON work_request_identities(request_id)"
