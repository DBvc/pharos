type object_kind = MergeRequest | Issue

type target = {
  instance_id : string;
  project_id : int;
  object_kind : object_kind;
  iid : int;
}

type instance = {
  base_url : string;
  id : string;
}

val instance_of_base_url : string -> (instance, string) result
val external_id : target -> string
val target_ref : target -> string
val parse_external_id : string -> (target, string) result
val parse_target_ref : target_kind:string -> string -> (target, string) result
val matches : target -> target -> bool
val endpoint_path : target -> string
