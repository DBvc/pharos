open Domain

type capability = {
  source_kind : source_kind;
  read_events : string list;
  context_types : string list;
  write_targets : string list;
  write_enabled_by_default : bool;
}

type context_limit = {
  max_items : int;
  max_bytes : int;
}

type context_request = {
  source_kind : source_kind;
  context_type : string;
  external_ref : string;
  limits : context_limit;
}

type context_fact = {
  kind : string;
  title : string;
  body : string;
  url : string option;
}

type context_response = {
  facts : context_fact list;
  truncated : bool;
  adapter_note : string option;
}

type writeback_request = {
  action_id : string;
  approval_id : string;
  target_kind : string;
  target_ref : string;
  body : string;
}

type writeback_result = {
  ok : bool;
  external_id : string option;
  url : string option;
  message : string;
}

type error = {
  source_kind : source_kind;
  message : string;
  retryable : bool;
}

module type S = sig
  val capability : capability
  val poll : unit -> (source_signal list, error) result
  val fetch_context : context_request -> (context_response, error) result
  val writeback : writeback_request -> (writeback_result, error) result
end

let capability_to_yojson c =
  Json_util.assoc [
    Json_util.str "source_kind" (source_kind_to_string c.source_kind);
    Json_util.list "read_events" (fun s -> `String s) c.read_events;
    Json_util.list "context_types" (fun s -> `String s) c.context_types;
    Json_util.list "write_targets" (fun s -> `String s) c.write_targets;
    Json_util.bool "write_enabled_by_default" c.write_enabled_by_default;
  ]

let p0_capabilities = [
  {
    source_kind = FeishuChat;
    read_events = [ "mention"; "keyword"; "thread_update"; "forwarded_to_pharos" ];
    context_types = [ "chat_thread"; "linked_docs" ];
    write_targets = [ "feishu.chat_reply" ];
    write_enabled_by_default = false;
  };
  {
    source_kind = FeishuProject;
    read_events = [ "assigned"; "comment_mention"; "status_changed"; "blocked" ];
    context_types = [ "project_item"; "project_comments"; "linked_docs" ];
    write_targets = [ "feishu.project_comment" ];
    write_enabled_by_default = false;
  };
  {
    source_kind = GitLab;
    read_events = [ "review_requested"; "mention"; "discussion"; "pipeline_failed" ];
    context_types = [ "mr_metadata"; "mr_diff_summary"; "discussion"; "pipeline_status" ];
    write_targets = [ "gitlab.mr_comment"; "gitlab.issue_comment" ];
    write_enabled_by_default = false;
  };
  {
    source_kind = FeishuDocs;
    read_events = [ "doc_comment_mention"; "manual_doc_link" ];
    context_types = [ "doc_comment"; "doc_paragraphs" ];
    write_targets = [ "feishu.doc_comment" ];
    write_enabled_by_default = false;
  };
]
