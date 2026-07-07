let assoc fields = `Assoc fields
let str name value = (name, `String value)
let int name value = (name, `Int value)
let bool name value = (name, `Bool value)
let opt_str name = function
  | None -> (name, `Null)
  | Some value -> (name, `String value)

let list name encode values = (name, `List (List.map encode values))

let member_string ?default name json =
  match Yojson.Safe.Util.member name json with
  | `String s -> Some s
  | `Null -> default
  | _ -> default

let required_string name json =
  match member_string name json with
  | Some s when String.trim s <> "" -> Ok s
  | _ -> Error (Printf.sprintf "Missing required string field: %s" name)

let optional_string name json = member_string name json
