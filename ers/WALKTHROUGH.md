# How your ERS logic works

Start by running `dune exec example/walkthrough.exe` from `ers/`. It demonstrates
a King challenge, three responses (4, 3, 2), and a third player slapping the run
before the challenger collects.

## 1. A state is a complete snapshot of the game

The `Game_state.t` record stores:

```ocaml
{ hands; pile; burned; phase; last_event }
```

- `hands`: one list per player. The first card of a hand is the next to play.
- `pile`: face-up cards with the newest card first.
- `burned`: penalty cards, kept separate so they cannot form slap patterns.
- `phase`: what is happening and who can play or collect.
- `last_event`: what just happened, useful for explanations and a later UI.

For example, if 4, 3, then 2 were played, the pile starts `[2; 3; 4]`. Adding a
card is simply `card :: pile`. The reversed storage order does not change the
run rule, because both ascending and descending runs count.

The interface declares a **private record**: other modules can inspect a state,
but must use our constructors and moves to create or change it. This prevents a
caller from accidentally inventing a challenge with zero remaining chances.

## 2. Variants represent the possible situations

`Phase.t` is a variant with four cases:

```ocaml
Normal of { turn : int }
Challenge of { challenger : int; responder : int; remaining : int }
Awaiting_collection of { collector : int }
Finished of { winner : int }
```

Unlike storing many booleans, this makes the current situation explicit. A game
cannot simultaneously be both finished and waiting for a challenge response.

## 3. A move says both what happened and who did it

```ocaml
Play_card of int
Slap of int
Collect_pile of int
```

`Play_card 0` means player 0 plays. `Slap 2` means player 2 tries to slap.
Player IDs are necessary because a slapper may not be the player whose turn it is.

`Collect_pile` models the pause between the last failed response and picking up
the pile. For this homework, the caller submits that action. No real-time clock
or server is needed to test whether a slap can happen first.

## 4. make_move is the entry point

Its signature follows the same idea as the lesson:

```ocaml
val make_move : t -> Move.t -> (t, Move_error.t) result
```

Read that as: **given a state and a move, return either a new state or an error**.

It first rejects moves after game over and invalid player IDs. It then uses
pattern matching to send the action to `play_card`, `slap`, or `collect`.

A rejected action returns `Error`. The old state remains unchanged.
A wrong slap with a payable penalty returns `Ok` with a burned card: the attempt
was processed and had an effect under the rules, even though the slap was wrong.

## 5. Playing a card has two layers

First, check that the player is allowed to play and has a card. Remove their
first card and add it to the face-up pile.

Then decide what the card does:

- J/Q/K/A creates a new challenge for the next player with cards.
- A number card during a challenge reduces the remaining chances.
- The final unsuccessful chance, or an exhausted responder, permits collection.
- A number card during normal play advances the turn, skipping empty hands.

These decisions use `match` expressions, just like the lesson's Tic-Tac-Toe code.

## 6. Slap recognition is a small independent function

`Slap_pattern.matching pile` inspects the top two and three cards and returns all
matching rules. It does not alter the game or care who slapped.

For example:

```text
top-first pile [5; 5]       -> [Doubles; Ten]
top-first pile [2; 3; 4]    -> [Run]
top-first pile [K; 7; Q]    -> [Divorce]
```

If the list is nonempty, `slap` awards the pile. Otherwise it burns one card.
Keeping pattern detection separate makes it easy to test all 13 x 13 x 13
possible rank triples without having to play full games.

## 7. Winning the pile decides the next turn

Both a successful slap and collection call `award_pile`. It appends the collected
cards to the winner's hand, clears the center piles, and gives that player the
next turn. If everyone else's hand is empty, the game is now finished.

Checking victory after collection is important: a player with an empty hand
must still have the chance to slap the last pile and return to the game.

## 8. How we check correctness

The tests cover each slap rule, challenge lengths, turn order, illegal actions,
penalties, collection, re-entry, and victory. They also enumerate all rank triples
and simulate seeded games for 2-4 players.

After every successful simulated action, the tests check that:

- The old state has not changed.
- The exact same physical cards still exist, with none lost or duplicated.
- Every unfinished reachable state has at least one accepted move.

Simulations use a step limit because ERS can cycle; these tests do not claim
that every game must finish within a fixed number of turns.

To experiment, change the small hands or move list in `example/walkthrough.ml`,
rerun the example, and compare the resulting `phase` and hand counts.
