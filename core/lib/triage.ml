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
