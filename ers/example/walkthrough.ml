open Ers_logic

let card rank suit = { Card.rank; suit }
let show t =
  let counts = List.mapi (fun player cards ->
    Printf.sprintf "P%d=%d" (player + 1) (List.length cards)) t.Game_state.hands in
  let pile = String.concat " " (List.map Card.to_string t.pile) in
  let phase = match t.phase with
    | Phase.Normal {turn} -> Printf.sprintf "P%d plays next" (turn + 1)
    | Phase.Challenge {challenger;responder;remaining} ->
      Printf.sprintf "P%d challenges P%d: %d chances left"
        (challenger + 1) (responder + 1) remaining
    | Phase.Awaiting_collection {collector} ->
      Printf.sprintf "P%d may collect; anyone may still slap" (collector + 1)
    | Phase.Finished {winner} -> Printf.sprintf "P%d wins" (winner + 1) in
  Printf.printf "%s | pile (top first): [%s] | %s\n"
    (String.concat " " counts) pile phase

let () =
  let initial = Game_state.of_hands
    [[card King Clubs;card Five Clubs];
     [card Four Clubs;card Three Clubs;card Two Clubs;card Eight Clubs];
     [card Nine Clubs;card Ten Clubs]] in
  match initial with
  | Error _ -> failwith "Invalid walkthrough fixture"
  | Ok initial ->
    print_endline "Small deterministic example: King challenge, run, then an out-of-turn slap.";
    print_endline "Printed players are P1/P2/P3; code uses IDs 0/1/2.\n";
    show initial;
    ignore (List.fold_left (fun t (description, move) ->
      Printf.printf "\n%s\n" description;
      match Game_state.make_move t move with
      | Error error -> failwith (Game_state.Move_error.to_string error)
      | Ok next -> show next; next)
      initial
      ["P1 plays a King", Move.Play_card 0;
       "P2 responds with a 4", Move.Play_card 1;
       "P2 responds with a 3", Move.Play_card 1;
       "P2 responds with a 2; challenge fails, but 4-3-2 is slappable", Move.Play_card 1;
       "P3 slaps the run before P1 collects", Move.Slap 2])
