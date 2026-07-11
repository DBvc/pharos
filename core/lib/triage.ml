open Domain

let compact_body body =
  let body = String.trim body in
  if String.length body <= 240 then body else String.sub body 0 240 ^ "..."

let contains_substring haystack needle =
  let haystack_len = String.length haystack in
  let needle_len = String.length needle in
  if needle_len = 0 then true
  else if needle_len > haystack_len then false
  else
    let rec loop i =
      if i + needle_len > haystack_len then false
      else if String.sub haystack i needle_len = needle then true
      else loop (i + 1)
    in
    loop 0

let title_from_capture ~title ~body =
  match title with
  | Some t when String.trim t <> "" -> String.trim t
  | _ ->
      let body = String.trim body in
      if body = "" then "Untitled capture"
      else if String.length body <= 64 then body
      else String.sub body 0 64 ^ "..."

let classify_manual ~body =
  let lower = String.lowercase_ascii body in
  let urgent_markers = [ "urgent"; "blocker"; "blocked"; "线上"; "阻塞"; "发布"; "@"; "!" ] in
  if List.exists (contains_substring lower) urgent_markers then High else Normal

let request_summary body =
  "Manual capture queued for review: " ^ compact_body body

let entry_reason =
  "Created from manual capture. Starter triage treats manual captures as intentional work requests."

let next_step =
  "Review the generated local action, edit if needed, then approve or reject."

let local_action_body body =
  "Record this captured request as acknowledged and ready for follow-up:\n\n" ^ compact_body body

let source_reason (signal : source_signal) =
  match signal.kind with
  | GitLab -> "You were requested as reviewer."
  | FeishuChat -> "A chat message appears to need your reply."
  | FeishuProject -> "A project update appears to need a next step."
  | FeishuDocs -> "A document comment appears to need your response."
  | Manual -> entry_reason
  | UnknownSource kind -> "A " ^ kind ^ " signal was captured for review."

let source_next_step (signal : source_signal) =
  match signal.kind with
  | GitLab -> "Prepare a review summary and comment draft."
  | FeishuChat -> "Review and edit the prepared reply draft."
  | FeishuProject -> "Review the blocker summary and confirm the owner."
  | FeishuDocs -> "Review the comment context and prepare a response."
  | Manual -> next_step
  | UnknownSource _ -> "Review the prepared local next move."

let request_type (signal : source_signal) =
  match signal.kind with
  | GitLab -> "gitlab_mr_review"
  | FeishuChat -> "feishu_chat_reply"
  | FeishuProject -> "project_next_step"
  | FeishuDocs -> "doc_response"
  | Manual -> "manual_follow_up"
  | UnknownSource _ -> "source_follow_up"

let request_risk (signal : source_signal) =
  match signal.kind with
  | GitLab | FeishuChat -> L1
  | Manual | FeishuProject | FeishuDocs | UnknownSource _ -> L2

let request_priority (signal : source_signal) =
  match signal.kind with
  | Manual -> classify_manual ~body:signal.body
  | FeishuProject when contains_substring
      (String.lowercase_ascii signal.body) "blocked" -> High
  | GitLab | FeishuChat | FeishuProject | FeishuDocs | UnknownSource _ -> Normal
