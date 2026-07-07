type daily = {
  day : string;
  source_signals : int;
  work_requests : int;
  ready_for_review : int;
  approvals : int;
  edit_approvals : int;
  rejects : int;
  external_writes : int;
  unapproved_external_write_attempts : int;
}

let daily_to_yojson m =
  Json_util.assoc [
    Json_util.str "day" m.day;
    Json_util.int "source_signals" m.source_signals;
    Json_util.int "work_requests" m.work_requests;
    Json_util.int "ready_for_review" m.ready_for_review;
    Json_util.int "approvals" m.approvals;
    Json_util.int "edit_approvals" m.edit_approvals;
    Json_util.int "rejects" m.rejects;
    Json_util.int "external_writes" m.external_writes;
    Json_util.int "unapproved_external_write_attempts" m.unapproved_external_write_attempts;
  ]
