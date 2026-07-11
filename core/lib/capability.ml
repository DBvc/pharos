type auth_error =
  | MissingAuthorization
  | InvalidAuthorization

let is_loopback_host = function
  | "127.0.0.1" | "::1" -> true
  | _ -> false

let token_bytes = 64

let valid_token value =
  let is_lower_hex = function
    | '0' .. '9' | 'a' .. 'f' -> true
    | _ -> false
  in
  if String.length value = token_bytes && String.for_all is_lower_hex value then
    Some value
  else None

let bearer_token authorization =
  let prefix = "Bearer " in
  if String.starts_with ~prefix authorization then
    String.sub authorization (String.length prefix)
      (String.length authorization - String.length prefix)
    |> valid_token
  else None

let fixed_time_equal left right =
  let left_len = String.length left in
  let right_len = String.length right in
  let diff = ref (left_len lxor right_len) in
  for index = 0 to token_bytes - 1 do
    let left_byte = if index < left_len then Char.code left.[index] else 0 in
    let right_byte = if index < right_len then Char.code right.[index] else 0 in
    diff := !diff lor (left_byte lxor right_byte)
  done;
  !diff = 0

let authorize ~expected_token ~authorization =
  match valid_token expected_token with
  | None -> Error InvalidAuthorization
  | Some expected ->
      begin match Option.bind authorization bearer_token with
      | None -> Error MissingAuthorization
      | Some actual when fixed_time_equal expected actual -> Ok ()
      | Some _ -> Error InvalidAuthorization
      end
