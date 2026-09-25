module Card = struct
  type suit = Clubs | Diamonds | Hearts | Spades
  type rank = Ace | Two | Three | Four | Five | Six | Seven | Eight | Nine
            | Ten | Jack | Queen | King
  type t = { rank : rank; suit : suit }

  let rank_value = function
    | Ace -> 1 | Two -> 2 | Three -> 3 | Four -> 4 | Five -> 5
    | Six -> 6 | Seven -> 7 | Eight -> 8 | Nine -> 9 | Ten -> 10
    | Jack -> 11 | Queen -> 12 | King -> 13

  let challenge_chances = function
    | Jack -> Some 1 | Queen -> Some 2 | King -> Some 3 | Ace -> Some 4
    | _ -> None

  let deck =
    let ranks = [Ace; Two; Three; Four; Five; Six; Seven; Eight; Nine;
                 Ten; Jack; Queen; King] in
    List.concat_map
      (fun suit -> List.map (fun rank -> { rank; suit }) ranks)
      [Clubs; Diamonds; Hearts; Spades]

  let shuffled_deck ~seed =
    (* Fisher-Yates: mutation is local to this fresh array; game states are immutable. *)
    let cards = Array.of_list deck in
    let random = Random.State.make [|seed|] in
    for i = Array.length cards - 1 downto 1 do
      let j = Random.State.int random (i + 1) in
      let saved = cards.(i) in
      cards.(i) <- cards.(j);
      cards.(j) <- saved
    done;
    Array.to_list cards

  let to_string { rank; suit } =
    let rank = match rank with
      | Ace -> "A" | Jack -> "J" | Queen -> "Q" | King -> "K"
      | rank -> string_of_int (rank_value rank) in
    let suit = match suit with
      | Clubs -> "C" | Diamonds -> "D" | Hearts -> "H" | Spades -> "S" in
    rank ^ suit
end

module Slap_pattern = struct
  type t = Doubles | Sandwich | Marriage | Divorce | Ten | Run

  let royal_pair a b =
    match a, b with
    | Card.King, Card.Queen | Card.Queen, Card.King -> true
    | _ -> false

  let matching pile =
    match pile with
    | (a : Card.t) :: b :: rest ->
      let av = Card.rank_value a.rank in
      let bv = Card.rank_value b.rank in
      let pairs =
        (if a.rank = b.rank then [Doubles] else [])
        @ (if royal_pair a.rank b.rank then [Marriage] else [])
        @ (if av <= 10 && bv <= 10 && av + bv = 10 then [Ten] else []) in
      let triples = match rest with
        | c :: _ ->
          let cv = Card.rank_value c.rank in
          (if a.rank = c.rank then [Sandwich] else [])
          @ (if royal_pair a.rank c.rank then [Divorce] else [])
          @ (if (av = bv + 1 && bv = cv + 1)
                || (av = bv - 1 && bv = cv - 1) then [Run] else [])
        | [] -> [] in
      pairs @ triples
    | _ -> []

  let to_string = function
    | Doubles -> "doubles" | Sandwich -> "sandwich" | Marriage -> "marriage"
    | Divorce -> "divorce" | Ten -> "ten" | Run -> "run"
end

module Move = struct
  type t = Play_card of int | Slap of int | Collect_pile of int
end

module Phase = struct
  type t =
    | Normal of { turn : int }
    | Challenge of { challenger : int; responder : int; remaining : int }
    | Awaiting_collection of { collector : int }
    | Finished of { winner : int }
end

module Event = struct
  type t =
    | Played of { player : int; card : Card.t }
    | Slapped of { player : int; patterns : Slap_pattern.t list; cards_won : int }
    | Burned of { player : int; card : Card.t }
    | Collected of { player : int; cards_won : int }
end

module Game_state = struct
  type t =
    { hands : Card.t list list
    ; pile : Card.t list
    ; burned : Card.t list
    ; phase : Phase.t
    ; last_event : Event.t option
    }

  module Create_error = struct
    type t = Invalid_player_count | Empty_deck | Duplicate_card
  end

  module Move_error = struct
    type t = Game_is_over | Invalid_player | Not_your_turn | No_cards
           | Empty_pile | No_cards_to_burn | Collection_pending
           | No_collection_pending | Not_the_collector

    let to_string = function
      | Game_is_over -> "The game is over."
      | Invalid_player -> "That player is not in this game."
      | Not_your_turn -> "It is not your turn to play a card."
      | No_cards -> "You have no cards to play, but can still slap back in."
      | Empty_pile -> "There are no face-up cards to slap."
      | No_cards_to_burn -> "That slap is wrong and you have no card to burn."
      | Collection_pending -> "The pile must be collected or slapped first."
      | No_collection_pending -> "Nobody is entitled to collect the pile yet."
      | Not_the_collector -> "Another player is entitled to collect this pile."
  end

  let hand hands player = List.nth hands player

  let replace_hand hands player cards =
    List.mapi (fun index old -> if index = player then cards else old) hands

  let active_players hands =
    List.mapi (fun index cards -> index, cards) hands
    |> List.filter_map (fun (index, cards) -> if cards = [] then None else Some index)

  (* Search only OTHER players, skipping empty hands and wrapping around. *)
  let next_player hands after =
    let count = List.length hands in
    let rec search offset =
      if offset >= count then None
      else
        let player = (after + offset) mod count in
        if hand hands player <> [] then Some player else search (offset + 1) in
    search 1

  let of_hands hands =
    let count = List.length hands in
    let cards = List.concat hands in
    if count < 2 || count > 4 then Error Create_error.Invalid_player_count
    else if cards = [] then Error Create_error.Empty_deck
    else if List.length (List.sort_uniq compare cards) <> List.length cards
    then Error Create_error.Duplicate_card
    else
      let phase = match active_players hands with
        | [winner] -> Phase.Finished { winner }
        | turn :: _ -> Phase.Normal { turn }
        | [] -> assert false in
      Ok { hands; pile = []; burned = []; phase; last_event = None }

  let create ~players ~seed =
    if players < 2 || players > 4 then Error Create_error.Invalid_player_count
    else
      let indexed = List.mapi (fun i card -> i mod players, card)
          (Card.shuffled_deck ~seed) in
      let hands = List.init players (fun player ->
        List.filter_map (fun (owner, card) ->
          if owner = player then Some card else None) indexed) in
      of_hands hands

  let is_game_over t = match t.phase with Phase.Finished _ -> true | _ -> false

  let card_count t =
    List.fold_left (fun total cards -> total + List.length cards)
      (List.length t.pile + List.length t.burned) t.hands

  let award_pile t player event =
    (* Burned cards sit face down below the face-up pile. Collect bottom first. *)
    let collected = List.rev t.burned @ List.rev t.pile in
    let hands = replace_hand t.hands player (hand t.hands player @ collected) in
    let phase = match active_players hands with
      | [winner] -> Phase.Finished { winner }
      | _ -> Phase.Normal { turn = player } in
    { hands; pile = []; burned = []; phase; last_event = Some event }

  let play_card t player =
    let expected = match t.phase with
      | Phase.Normal { turn } -> Some turn
      | Phase.Challenge { responder; _ } -> Some responder
      | _ -> None in
    match expected with
    | None -> Error Move_error.Collection_pending
    | Some turn when player <> turn -> Error Move_error.Not_your_turn
    | Some _ ->
      match hand t.hands player with
      | [] -> Error Move_error.No_cards
      | card :: remaining_hand ->
        let hands = replace_hand t.hands player remaining_hand in
        let phase = match Card.challenge_chances card.rank with
          | Some remaining ->
            (match next_player hands player with
             | Some responder -> Phase.Challenge { challenger = player; responder; remaining }
             | None -> Phase.Awaiting_collection { collector = player })
          | None ->
            (match t.phase with
             | Phase.Challenge { challenger; remaining; _ } ->
               if remaining = 1 || remaining_hand = []
               then Phase.Awaiting_collection { collector = challenger }
               else Phase.Challenge { challenger; responder = player; remaining = remaining - 1 }
             | _ ->
               match next_player hands player with
               | Some turn -> Phase.Normal { turn }
               | None -> Phase.Awaiting_collection { collector = player }) in
        Ok { t with hands; pile = card :: t.pile; phase;
                    last_event = Some (Event.Played { player; card }) }

  let burn_card t player =
    match hand t.hands player with
    | [] -> Error Move_error.No_cards_to_burn
    | card :: remaining_hand ->
      let hands = replace_hand t.hands player remaining_hand in
      (* A penalty may empty the hand of the player who was supposed to play. *)
      let phase = match t.phase with
        | Phase.Normal { turn } when turn = player && remaining_hand = [] ->
          (match next_player hands player with
           | Some turn -> Phase.Normal { turn }
           | None -> Phase.Awaiting_collection { collector = player })
        | Phase.Challenge { responder; challenger; _ }
          when responder = player && remaining_hand = [] ->
          Phase.Awaiting_collection { collector = challenger }
        | phase -> phase in
      Ok { t with hands; burned = card :: t.burned; phase;
                  last_event = Some (Event.Burned { player; card }) }

  let slap t player =
    match t.pile with
    | [] -> Error Move_error.Empty_pile
    | _ ->
      match Slap_pattern.matching t.pile with
      | [] -> burn_card t player
      | patterns ->
        let cards_won = List.length t.pile + List.length t.burned in
        Ok (award_pile t player (Event.Slapped { player; patterns; cards_won }))

  let collect t player =
    match t.phase with
    | Phase.Awaiting_collection { collector } when player = collector ->
      let cards_won = List.length t.pile + List.length t.burned in
      Ok (award_pile t player (Event.Collected { player; cards_won }))
    | Phase.Awaiting_collection _ -> Error Move_error.Not_the_collector
    | _ -> Error Move_error.No_collection_pending

  let make_move t move =
    let player = match move with
      | Move.Play_card player | Move.Slap player | Move.Collect_pile player -> player in
    if is_game_over t then Error Move_error.Game_is_over
    else if player < 0 || player >= List.length t.hands then Error Move_error.Invalid_player
    else match move with
      | Move.Play_card player -> play_card t player
      | Move.Slap player -> slap t player
      | Move.Collect_pile player -> collect t player

  let get_all_moves t =
    List.init (List.length t.hands) (fun player ->
      [Move.Play_card player; Move.Slap player; Move.Collect_pile player])
    |> List.concat
    |> List.filter (fun move -> match make_move t move with Ok _ -> true | Error _ -> false)
end
