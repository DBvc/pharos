let rng = Random.State.make_self_init ()
let gen = Uuidm.v4_gen rng

let create prefix =
  prefix ^ "_" ^ Uuidm.to_string (gen ())
