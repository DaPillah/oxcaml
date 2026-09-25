(** HW2: a pure Egyptian Rat Screw rules engine. Player IDs are zero-based.
    No network, UI, clock, global random state, or external libraries are needed. *)

module Card : sig
  type suit = Clubs | Diamonds | Hearts | Spades
  type rank = Ace | Two | Three | Four | Five | Six | Seven | Eight | Nine
            | Ten | Jack | Queen | King
  type t = { rank : rank; suit : suit }
  val rank_value : rank -> int
  val challenge_chances : rank -> int option
  val deck : t list
  val shuffled_deck : seed:int -> t list
  val to_string : t -> string
end

module Slap_pattern : sig
  type t = Doubles | Sandwich | Marriage | Divorce | Ten | Run
  (** The pile is newest/top card first. Only the top two/three cards count. *)
  val matching : Card.t list -> t list
  val to_string : t -> string
end

module Move : sig
  type t = Play_card of int | Slap of int | Collect_pile of int
end

module Phase : sig
  type t =
    | Normal of { turn : int }
    | Challenge of { challenger : int; responder : int; remaining : int }
    | Awaiting_collection of { collector : int }
    | Finished of { winner : int }
end

module Event : sig
  type t =
    | Played of { player : int; card : Card.t }
    | Slapped of { player : int; patterns : Slap_pattern.t list; cards_won : int }
    | Burned of { player : int; card : Card.t }
    | Collected of { player : int; cards_won : int }
end

module Game_state : sig
  (** Private records are readable, but callers cannot construct inconsistent states.
      Hands are next-to-play first; pile and burned cards are newest first. *)
  type t = private
    { hands : Card.t list list
    ; pile : Card.t list
    ; burned : Card.t list
    ; phase : Phase.t
    ; last_event : Event.t option
    }

  module Create_error : sig
    type t = Invalid_player_count | Empty_deck | Duplicate_card
  end

  val create : players:int -> seed:int -> (t, Create_error.t) result

  (** Deterministic scenario constructor, also used by tests and the walkthrough.
      Accepts smaller unique decks. There must be 2-4 hands and at least one card.
      The first nonempty hand starts. A sole nonempty hand has already won. *)
  val of_hands : Card.t list list -> (t, Create_error.t) result

  module Move_error : sig
    type t = Game_is_over | Invalid_player | Not_your_turn | No_cards
           | Empty_pile | No_cards_to_burn | Collection_pending
           | No_collection_pending | Not_the_collector
    val to_string : t -> string
  end

  (** Invalid actions return Error without changing the original state.
      A wrong slap with cards in hand is an accepted action: it burns one card.
      Slaps are allowed out of turn, including during Awaiting_collection.
      Submitted actions are processed sequentially; the first valid slap wins. *)
  val make_move : t -> Move.t -> (t, Move_error.t) result
  val get_all_moves : t -> Move.t list
  val is_game_over : t -> bool
  val card_count : t -> int
end
