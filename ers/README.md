# Egyptian Rat Screw - HW2 game logic

This is Justin's ERS implementation for Lesson 2: represent the game with OCaml
types and implement `make_move`. It supports 2-4 players and a standard 52-card
deck. It contains a rules engine, tests, and a scripted walkthrough. There is no
graphical interface or multiplayer server in this homework milestone.

The code follows the course's `Card` / `Move` / `Game_state` module style and
returns `Ok new_state` or `Error reason`. It uses the OCaml standard library
rather than Core/PPX so this homework can build without the later UI dependencies.
The original Tic-Tac-Toe course files remain in the parent repository.

## Run in Codespaces

Use your fork: <https://github.com/DaPillah/oxcaml>.

1. Select **Code > Codespaces > ... > New with options**.
2. Select branch **gh-pages** and the **ERS HW2 - OCaml game logic** configuration
   (`.devcontainer/ers/devcontainer.json`). Choose the smallest available machine.
3. Create the Codespace. Its editor opens the repository; setup builds ERS and
   runs the tests automatically.
4. In the terminal:

```sh
cd ers
dune build
dune runtest
dune exec example/walkthrough.exe
```

From the repository root instead, use:

```sh
dune build --root ers
dune runtest --root ers
dune exec --root ers example/walkthrough.exe
```

The lightweight container supplies OCaml 4.13 and Dune 2.9 from Ubuntu 22.04.
This project also works with the course's OCaml 4.14.0 environment. Its own
`dune-project` keeps ERS independent of the parent project's UI build and legacy
`jbuild` file. If you use the original course container, finish its OPAM setup
and then run the `--root ers` commands above. The lightweight container does not
install the original Tic-Tac-Toe UI's Core/Bonsai packages or the optional OCaml
language server; compiling and testing work from the terminal.

## Agreed rules

- Player IDs in code are `0`, `1`, `2`, and `3`. Players keep face-down hands;
  they can only play the next card, not choose a card from their hand.
- Shuffle once using a supplied seed and deal round-robin. For three players,
  hand sizes are 18, 17, and 17; for two/four, the deal is even.
- Number cards normally pass play to the next player with cards.
- J/Q/K/A start a challenge of 1/2/3/4 chances for the next player with cards.
  A response of J/Q/K/A replaces the challenge and passes it to the next player.
  Other responses consume a chance. A failed challenge gives the challenger
  the right to collect the pile.
- Anyone can slap out of turn, including a player with no cards. A valid slap
  wins the entire pile and burned cards, cancels any challenge, and lets the
  slapper lead.
- A wrong slap burns one card from the top of that player's hand, face down
  beneath the pile. Burned cards do not participate in slap patterns.
- The winner owns all cards after collecting/slapping a pile. Empty-handed
  players can slap back in until the game is actually over.

Only the top two or three **face-up** cards count for a slap. Suits do not matter.
In the examples below, cards are shown in the order they were played.

| Pattern | Rule | Examples |
| --- | --- | --- |
| Doubles | Same rank on the top two cards | 7, 7 |
| Sandwich | Same rank with exactly one card between | 4, 9, 4 |
| Marriage | Adjacent King and Queen, either order | K, Q or Q, K |
| Divorce | King and Queen with exactly one card between | K, 5, Q or Q, 5, K |
| Ten | Top two total 10; Ace is 1, number cards only | A, 9; 4, 6; 5, 5 |
| Run | Top three consecutive ranks ascending or descending | A, 2, 3; 4, 3, 2; J, Q, K |

For runs, Ace is low, J=11, Q=12, K=13, and there is no wrapping from King to Ace.
Multiple patterns can match at once (5, 5 is both a double and a ten).

## Edge-case choices used in this implementation

These choices make the homework deterministic and can be changed if desired:

- **Collection is a separate action.** After the final failed response, the
  phase becomes `Awaiting_collection`. Anyone can slap before the entitled
  player submits `Collect_pile`. No extra card can be played in this phase.
  The engine has no timer: a future interface decides when to submit collection.
- **First submitted valid slap wins.** Actions are processed sequentially.
  Another slap after the pile was taken is rejected because the pile is empty
  (or the game has ended). Real online timing/fairness is outside HW2.
- **Running out during a challenge ends that challenge.** If a responder uses
  or burns their last card without playing a new J/Q/K/A, the challenger may
  collect. The unused chances do not transfer to a third player.
- **A wrong slap with no cards is rejected.** It does not remove that player's
  future ability to slap back in. A future real-time UI may need input throttling.
- **Burning does not use a challenge chance or reveal a new face-up card.** If it
  empties the hand of the player who should play, their turn is skipped or their
  challenge fails. Burning an empty pile is not allowed.
- **Collection preserves order.** Existing hand first, then burned cards from
  oldest to newest, then face-up cards from oldest to newest. No reshuffle.
- **Last player with cards still resolves the pile.** If nobody else can respond
  after a card is played, that player may collect, while others can still slap.
  If all hands become empty, the last player to play/burn may collect. A winner
  is not declared while there are still cards in the middle.

## Where to read the code

1. [`lib/ers_logic.mli`](lib/ers_logic.mli): public types and function signatures.
2. [`lib/ers_logic.ml`](lib/ers_logic.ml): all rule implementations; begin at
   `Game_state.make_move`, then follow `play_card`, `slap`, and `collect`.
3. [`WALKTHROUGH.md`](WALKTHROUGH.md): a guided explanation of the implementation.
4. [`test/ers_logic_test.ml`](test/ers_logic_test.ml): concrete scenarios,
   exhaustive rank-pattern checks, and seeded game simulations.

`of_hands` is a deterministic scenario constructor used for demonstrations and
tests. It permits smaller decks but rejects duplicate physical cards and invalid
player counts. Normal games should use `create ~players ~seed`, which always
deals all 52 cards. The seed makes games reproducible for debugging; it is not
intended as a secure shuffle for online competitive play.

## Example API

```ocaml
open Ers_logic

let start = Game_state.create ~players:3 ~seed:42

let after_first_card =
  match start with
  | Error _ -> failwith "Invalid player count"
  | Ok state -> Game_state.make_move state (Move.Play_card 0)
```

All game-state updates are immutable. Hands are stored next-to-play first; the
face-up pile is stored newest/top first. `get_all_moves` returns actions that the
engine will accept, including wrong slaps that burn a card. It is not a strategy
recommendation. The state exposes card identities for homework testing; a future
multiplayer server must send clients only the public pile and their permitted
view, rather than other players' hidden cards.
