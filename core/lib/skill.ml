open Domain

type skill_id = string

type evidence_ref = {
  evidence_id : string;
  note : string;
}

type proposed_output = {
  title : string;
  body : string;
  target_kind : string;
  target_ref : string;
  risk : risk;
  requires_approval : bool;
  evidence_refs : evidence_ref list;
}

type outcome = {
  summary : string;
  facts : string list;
  inferences : string list;
  unknowns : string list;
  proposed_actions : proposed_output list;
  needs_context : bool;
}

type input = {
  request : work_request;
  evidence : evidence_item list;
  timeline : timeline_event list;
}

module type S = sig
  val id : skill_id
  val can_handle : work_request -> bool
  val run : input -> (outcome, string) result
end

let builtin_skill_ids = [
  "triage_skill";
  "context_summary_skill";
  "draft_reply_skill";
  "gitlab_mr_review_skill";
  "project_next_step_skill";
  "doc_understanding_skill";
]
