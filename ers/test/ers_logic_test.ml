open Ers_logic
open Card
open Move
module G = Game_state
module E = G.Move_error

let check message condition = if not condition then failwith message
let ok = function Ok x -> x | Error _ -> failwith "Expected Ok"
let expect_error expected result = check "Wrong error" (result = Error expected)
let cards_of t = List.sort compare (List.concat t.G.hands @ t.pile @ t.burned)

(* Assign different suits to repeated ranks so every fixture uses unique cards. *)
let hands ranks =
  let used = Hashtbl.create 13 in
  List.map (List.map (fun rank ->
    let count = Option.value (Hashtbl.find_opt used rank) ~default:0 in
    let suit = List.nth [Clubs; Diamonds; Hearts; Spades] count in
    Hashtbl.replace used rank (count + 1);
    { rank; suit })) ranks

let state ranks = G.of_hands (hands ranks) |> ok

let step state move =
  let before = Marshal.to_string state [] in
  let next = G.make_move state move |> ok in
  check "Input state mutated" (Marshal.to_string state [] = before);
  check "A card was lost or duplicated" (cards_of next = cards_of state);
  next

let steps state moves = List.fold_left step state moves
let normal player t = check "Wrong normal turn" (t.G.phase = Phase.Normal { turn = player })
let pending player t =
  check "Wrong collector" (t.G.phase = Phase.Awaiting_collection { collector = player })
let challenge challenger responder remaining t =
  check "Wrong challenge" (t.G.phase = Phase.Challenge { challenger; responder; remaining })
let ranks cards = List.map (fun c -> c.rank) cards
let pattern ranks = Slap_pattern.matching (List.hd (hands [ranks]))
let has p ranks = List.mem p (pattern ranks)

let tests = ref []
let test name f = tests := !tests @ [name, f]

let () =
  test "52 unique shuffled cards and deterministic seeds" (fun () ->
    check "Deck size" (List.length Card.deck = 52);
    check "Deck contents" (List.sort compare (Card.shuffled_deck ~seed:42) =
                           List.sort compare Card.deck);
    check "Seed not reproducible" (Card.shuffled_deck ~seed:42 = Card.shuffled_deck ~seed:42);
    check "Different seeds should shuffle differently"
      (Card.shuffled_deck ~seed:42 <> Card.shuffled_deck ~seed:43));
  test "2, 3, and 4 players receive fair round-robin deals" (fun () ->
    List.iter (fun (players, counts) ->
      let t = G.create ~players ~seed:17 |> ok in
      check "Deal count" (List.map List.length t.hands = counts);
      check "Total" (G.card_count t = 52);
      normal 0 t;
      let deck = Card.shuffled_deck ~seed:17 in
      List.iteri (fun player hand ->
        let expected = List.mapi (fun i c -> i, c) deck
          |> List.filter_map (fun (i, c) -> if i mod players = player then Some c else None) in
        check "Not round robin" (hand = expected)) t.hands)
      [2, [26;26]; 3, [18;17;17]; 4, [13;13;13;13]]);
  test "Creation rejects invalid player counts" (fun () ->
    List.iter (fun players -> expect_error G.Create_error.Invalid_player_count
      (G.create ~players ~seed:0)) [-1;0;1;5;100]);
  test "Scenario constructor validates empty and duplicate decks" (fun () ->
    expect_error G.Create_error.Empty_deck (G.of_hands [[];[]]);
    let c = {rank = Five; suit = Clubs} in
    expect_error G.Create_error.Duplicate_card (G.of_hands [[c];[c]]));
  test "Ordinary cards rotate and wrap across four players" (fun () ->
    let t = state [[Two;Six];[Four;Eight];[Seven;Nine];[Ten;Three]] in
    let t = steps t [Play_card 0;Play_card 1;Play_card 2;Play_card 3] in
    normal 0 t;
    check "Pile order" (ranks t.pile = [Ten;Seven;Four;Two]));
  test "Empty hands are skipped" (fun () ->
    let t = state [[Two;Six];[];[Seven;Nine];[]] |> fun t -> step t (Play_card 0) in
    normal 2 t);
  test "Wrong turn, player, empty pile and premature collection errors" (fun () ->
    let t = state [[Two];[Four]] in
    expect_error E.Not_your_turn (G.make_move t (Play_card 1));
    List.iter (fun m -> expect_error E.Invalid_player (G.make_move t m))
      [Play_card (-1);Slap 2;Collect_pile 5];
    expect_error E.Empty_pile (G.make_move t (Slap 0));
    expect_error E.No_collection_pending (G.make_move t (Collect_pile 0)));
  List.iter (fun (rank, chances) ->
    test ("Challenge for " ^ Card.to_string {rank; suit=Clubs}) (fun () ->
      let t = state [[rank;Five];[Two;Four;Six;Eight;Ten]] in
      let t = step t (Play_card 0) in
      challenge 0 1 chances t;
      let rec respond t left =
        let t = step t (Play_card 1) in
        if left = 1 then pending 0 t
        else (challenge 0 1 (left - 1) t; respond t (left - 1)) in
      respond t chances)) [Jack,1;Queen,2;King,3;Ace,4];
  test "A responding face card replaces the old challenge" (fun () ->
    let t = state [[King;Five];[Jack;Seven];[Two;Nine]]
      |> fun t -> steps t [Play_card 0;Play_card 1] in
    challenge 1 2 1 t);
  test "Challenge skips an empty player" (fun () ->
    let t = state [[King;Five];[];[Two;Nine]] |> fun t -> step t (Play_card 0) in
    challenge 0 2 3 t);
  test "Exhausted responder loses challenge immediately" (fun () ->
    let t = state [[Ace;Five];[Six];[Eight;Nine]]
      |> fun t -> steps t [Play_card 0;Play_card 1] in
    pending 0 t);
  test "Playing a final face card still transfers the challenge" (fun () ->
    let t = state [[King;Five];[Jack];[Two;Nine]]
      |> fun t -> steps t [Play_card 0;Play_card 1] in
    challenge 1 2 1 t);
  test "Collection has explicit ownership and blocks more card play" (fun () ->
    let t = state [[Jack;Five];[Six;Two]]
      |> fun t -> steps t [Play_card 0;Play_card 1] in
    expect_error E.Collection_pending (G.make_move t (Play_card 0));
    expect_error E.Not_the_collector (G.make_move t (Collect_pile 1));
    let t = step t (Collect_pile 0) in
    normal 0 t;
    check "Collection goes below existing hand" (ranks (List.hd t.hands) = [Five;Jack;Six]);
    check "Cleared pile" (t.pile = []));
  List.iter (fun (name, p, cards) -> test name (fun () -> check name (has p cards)))
    ["Doubles", Slap_pattern.Doubles, [Four;Four];
     "Sandwich", Slap_pattern.Sandwich, [Two;Nine;Two];
     "Marriage K Q", Slap_pattern.Marriage, [King;Queen];
     "Marriage Q K", Slap_pattern.Marriage, [Queen;King];
     "Divorce K x Q", Slap_pattern.Divorce, [King;Four;Queen];
     "Divorce Q x K", Slap_pattern.Divorce, [Queen;Four;King];
     "Ten 4 + 6", Slap_pattern.Ten, [Four;Six];
     "Ten A + 9", Slap_pattern.Ten, [Ace;Nine];
     "Ten 5 + 5", Slap_pattern.Ten, [Five;Five];
     "Ascending run A 2 3", Slap_pattern.Run, [Three;Two;Ace];
     "Descending run 4 3 2", Slap_pattern.Run, [Two;Three;Four];
     "Face-card run J Q K", Slap_pattern.Run, [King;Queen;Jack]];
  test "Nonpatterns, short piles, and no rank wrapping" (fun () ->
    List.iter (fun cards -> check "Unexpected slap pattern" (pattern cards = []))
      [[];[Five];[Two;Four];[Two;Four;Seven];[Two;Ace;King];[Ace;King;Jack]]);
  test "Tens uses only top two; buried patterns do not count" (fun () ->
    check "Buried ten" (not (has Slap_pattern.Ten [Three;Four;Six]));
    check "Buried double" (not (has Slap_pattern.Doubles [Two;Four;Four]));
    check "Buried run" (not (has Slap_pattern.Run [Eight;Three;Two;Ace])));
  test "Every ordered rank pair and triple matches the rule definitions" (fun () ->
    let rank n = (List.nth Card.deck (n - 1)).rank in
    let royal a b = (a=12 && b=13) || (a=13 && b=12) in
    for a = 1 to 13 do for b = 1 to 13 do for c = 1 to 13 do
      let found = pattern [rank a;rank b;rank c] in
      List.iter (fun (p, expected) -> check "Pattern truth table" (List.mem p found = expected))
        [Slap_pattern.Doubles, a=b; Sandwich, a=c; Marriage, royal a b;
         Divorce, royal a c; Ten, a+b=10;
         Run, ((b-a=1 && c-b=1) || (a-b=1 && b-c=1))]
    done done done);
  test "Out-of-turn slap awards pile and next turn" (fun () ->
    let t = state [[Two;Six];[Two;Eight];[Nine;Ten]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Slap 0] in
    normal 0 t;
    check "Won cards appended" (ranks (List.hd t.hands) = [Six;Two;Two]));
  test "Slapping during a challenge cancels it" (fun () ->
    let t = state [[King;Six];[Queen;Eight];[Nine;Ten]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Slap 2] in
    normal 2 t);
  test "Last response sandwich can beat collection" (fun () ->
    let t = state [[King;Five];[Four;Nine;Four;Eight];[Two;Ten]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Play_card 1;Play_card 1] in
    pending 0 t;
    check "Sandwich absent" (has Slap_pattern.Sandwich (ranks t.pile));
    let t = step t (Slap 1) in
    normal 1 t;
    expect_error E.No_collection_pending (G.make_move t (Collect_pile 0)));
  test "Pending collection retains a real run slap" (fun () ->
    let t = state [[King;Five];[Four;Three;Two;Eight];[Nine;Ten]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Play_card 1;Play_card 1] in
    pending 0 t;
    check "Run absent" (has Slap_pattern.Run (ranks t.pile));
    let t = step t (Slap 2) in
    normal 2 t;
    expect_error E.No_collection_pending (G.make_move t (Collect_pile 0)));
  test "Wrong slap burns under pile without creating a pattern" (fun () ->
    let t = state [[Four;Seven];[Six;Eight];[Nine;Ten]]
      |> fun t -> steps t [Play_card 0;Slap 1] in
    normal 1 t;
    check "Penalty" (ranks t.burned = [Six]);
    check "Face-up unchanged" (ranks t.pile = [Four]);
    check "Burned card must not form ten" (Slap_pattern.matching t.pile = []));
  test "Wrong slap does not use a challenge chance" (fun () ->
    let t = state [[King;Five];[Six;Eight;Ten]]
      |> fun t -> steps t [Play_card 0;Slap 1] in
    challenge 0 1 3 t);
  test "Burning the responder's last card ends the challenge" (fun () ->
    let t = state [[King;Five];[Six];[Eight;Ten]]
      |> fun t -> steps t [Play_card 0;Slap 1] in
    pending 0 t);
  test "Burning current player's last card advances their turn" (fun () ->
    let t = state [[Four;Five];[Six];[Eight;Ten]]
      |> fun t -> steps t [Play_card 0;Slap 1] in
    normal 2 t);
  test "Burned cards are included in subsequent collection, bottom first" (fun () ->
    let t = state [[Jack;Five];[Six;Eight;Ten];[Four;Seven]]
      |> fun t -> steps t [Play_card 0;Slap 1;Slap 2;Play_card 1;Collect_pile 0] in
    check "Burn collection order" (ranks (List.hd t.hands) = [Five;Six;Four;Jack;Eight]);
    check "Burn pile cleared" (t.burned = []));
  test "Empty-handed player can slap back in" (fun () ->
    let t = state [[Two];[Two;Eight];[Nine;Ten]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Slap 0] in
    normal 0 t;
    check "Returned hand" (List.length (List.hd t.hands) = 2));
  test "Empty-handed wrong slap is rejected" (fun () ->
    let t = state [[Two];[Four;Eight]] |> fun t -> step t (Play_card 0) in
    expect_error E.No_cards_to_burn (G.make_move t (Slap 0)));
  test "First valid slap wins; next slap sees an empty pile" (fun () ->
    let t = state [[Two;Six];[Two;Eight];[Nine;Ten]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Slap 2] in
    expect_error E.Empty_pile (G.make_move t (Slap 0)));
  test "No early victory while the final pile is contested" (fun () ->
    let t = state [[Two];[Two]] |> fun t -> steps t [Play_card 0;Play_card 1] in
    check "Premature win" (not (G.is_game_over t));
    pending 1 t;
    let t = step t (Slap 0) in
    check "Expected winner 0" (t.phase = Phase.Finished {winner=0});
    check "No moves after victory" (G.get_all_moves t = []);
    List.iter (fun move -> expect_error E.Game_is_over (G.make_move t move))
      [Play_card 0;Slap 1;Collect_pile 0]);
  test "Final non-slappable pile can be collected" (fun () ->
    let t = state [[Two];[Four]]
      |> fun t -> steps t [Play_card 0;Play_card 1;Collect_pile 1] in
    check "Expected winner 1" (t.phase = Phase.Finished {winner=1}));
  test "Burning the final held card does not deadlock" (fun () ->
    let t = state [[Two];[Four]]
      |> fun t -> steps t [Play_card 0;Slap 1;Collect_pile 1] in
    check "Expected winner" (t.phase = Phase.Finished {winner=1}));
  test "Legal moves include wrong slaps that can pay the penalty" (fun () ->
    let t = state [[Two;Six];[Four;Eight]] |> fun t -> step t (Play_card 0) in
    check "Missing penalty slap" (List.mem (Slap 0) (G.get_all_moves t));
    check "Wrong player allowed to play" (not (List.mem (Play_card 0) (G.get_all_moves t))));
  test "Seeded simulations conserve all 52 cards and never deadlock" (fun () ->
    for players = 2 to 4 do
      for seed = 0 to 49 do
        let random = Random.State.make [|seed;players|] in
        let rec play t turns =
          check "52 cards" (G.card_count t = 52);
          check "Physical deck changed" (cards_of t = List.sort compare Card.deck);
          if not (G.is_game_over t) && turns > 0 then (
            let moves = G.get_all_moves t in
            check "Deadlocked state" (moves <> []);
            let good = List.filter (function
              | Slap _ -> Slap_pattern.matching t.pile <> []
              | _ -> true) moves in
            let choices = if Random.State.int random 10 = 0 then moves else good in
            let move = List.nth choices (Random.State.int random (List.length choices)) in
            play (step t move) (turns - 1)) in
        play (G.create ~players ~seed |> ok) 2000
      done
    done);
  let failures = ref 0 in
  List.iter (fun (name, run) ->
    try run (); Printf.printf "PASS %s\n%!" name
    with exn -> incr failures; Printf.eprintf "FAIL %s: %s\n%!" name (Printexc.to_string exn)) !tests;
  Printf.printf "\n%d tests, %d failures\n" (List.length !tests) !failures;
  if !failures > 0 then exit 1
