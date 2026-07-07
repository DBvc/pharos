type rule_kind =
  | SourcePriority
  | KeywordPriority
  | AlwaysReview
  | SuppressFromToday

type rule = {
  id : string;
  kind : rule_kind;
  enabled : bool;
  pattern : string;
  value : string;
  created_at : string;
}

let rule_kind_to_string = function
  | SourcePriority -> "source_priority"
  | KeywordPriority -> "keyword_priority"
  | AlwaysReview -> "always_review"
  | SuppressFromToday -> "suppress_from_today"

let rule_to_yojson r =
  Json_util.assoc [
    Json_util.str "id" r.id;
    Json_util.str "kind" (rule_kind_to_string r.kind);
    Json_util.bool "enabled" r.enabled;
    Json_util.str "pattern" r.pattern;
    Json_util.str "value" r.value;
    Json_util.str "created_at" r.created_at;
  ]
