# Aetherfold

A 1v1 **Magic: The Gathering Commander** table for Godot 4.7. You play Krenko (or an imported Commander deck) against a **Talrand bot**.

This is a rules-engine prototype, not a complete MTG client. You can keep/mulligan, play lands, cast spells, attack, block, activate Krenko, and take turns against the AI.

The executable rules are the JSON files in `engine/cards/ir/` (28 cards today: cantrips, burn, counters, token makers, mana creatures, and the two commanders). Anything else in a Scryfall catalog still shows its name and art, and plays as a vanilla body unless it has an IR file. Basic lands do not need one. Details: [docs/creatures-without-ir.md](docs/creatures-without-ir.md).

## Play against the bot (Windows)

### 1. Install Godot 4.7

Download **Godot 4.7** (Standard, not .NET) from:

https://godotengine.org/download

Unzip it somewhere easy, e.g. `C:\Godot\`.

### 2. Get this project

```
git clone https://github.com/ryanqp/aetherfold.git
```

Or on GitHub: **Code → Download ZIP**, then unzip.

### 3. Open and run

1. Launch Godot 4.7.
2. **Import** → select the `aetherfold` folder (the one with `project.godot`).
3. Open the project.
4. Press **Play** (F5). The main scene is `scenes/main_menu.tscn`.

### 4. How to play

From the main menu:

- **Vs. AI** — pick your deck and the bot's deck, then Start Match. The bot is a single, fixed-strength opponent; it mulligans hands without 2 to 5 lands.
- **Multiplayer** — create or join a 6-character room code (LAN). Host starts the match.
- **Library Builder** — import a URL/list, build a deck, or browse the gallery.
- **Menu** — audio / fullscreen.
- **Exit Game** — quits.

At the table:

- **Keep** or **Mulligan** your opening 7.
- Click a card in hand to play a land or cast it.
- **Your turn starts with a draw.** Your deck (bottom right) flashes and the turn will not move on until you click it. Nothing is handed to you.
- The bar under the header shows the turn: Upkeep, Draw, Main 1, Combat, Main 2, End. Draw, Combat and End are clickable.
- A **gold border** on a card in your hand (or your commander) means you can play it right now: the timing is legal and you have enough untapped mana sources for its cost, commander tax included. Light-blue border = selected.
- Your **commander** and the rival's sit in the **Command zone** panel in the sidebar. Click yours to cast it; its tax shows underneath.
- **Attack** moves to combat. Click the creatures you want to send (red outline), then press **Attack (N)** — or **No attack** to skip combat. Creatures that came in this turn are dimmed: they have summoning sickness and can attack on your next turn. The bot then decides its blocks.
- When the bot attacks you, the game pauses for blocks: click one of your untapped creatures, then the attacker it should block (repeat for more), then **Confirm blocks** — or **No blocks**. Click an assigned blocker again to take it back. Attackers have a red border, blockers blue.
- **Pass** advances a step / resolves the stack.
- **End turn** — Talrand takes his turn, then you draw.
- **Menu** → **New game**.
- **Menu → Import Deck** to paste a Moxfield/Archidekt URL or a text decklist (optional).

Without a local Scryfall catalog, the demo still runs (Krenko vs Talrand). Card art downloads from Scryfall when names resolve.

### Optional: full card catalog (better art)

The game looks for a catalog at `D:\AetherfoldData\scryfall\catalog.jsonl`.

To put it somewhere else:

```
set AETHERFOLD_SCRYFALL_DIR=C:\path\to\scryfall
```

Then run:

```
python tools/fetch_scryfall.py
```

That only downloads metadata + image URLs, not every card image. Images cache as you play.

## Running tests

Engine tests are GDScript suites under `tests/engine/` (`test_*.gd`). Run them with Godot **4.7** from the project root (the folder that contains `project.godot`). If `godot` is not on your PATH, use the full path to your Godot 4.7 binary.

Whole suite:

```
godot --headless --path . -s res://tools/run_tests.gd
```

One suite (the `suite_name()` string, not the file name):

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack
```

One test (substring of the `test_*` method name):

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack --test=test_creature_not_in_play
```

Add `--verbose` after `--` to print every test name. Exit code `0` = all passed.

More detail, including how to add a suite: [docs/testing.md](docs/testing.md).

To give a card real rules (draw, tokens, counters, …) add JSON under `engine/cards/ir/`. Walkthrough and a copy-paste template: [docs/adding-a-card.md](docs/adding-a-card.md).

**Live rules live in `engine/`, not `scripts/match_state.gd`.** What to edit: [docs/migration-status.md](docs/migration-status.md).

Player-count / 1v1 vs N-player notes (before bigger multiplayer): [docs/player-count-audit.md](docs/player-count-audit.md).

If a bot land looks like it entered tapped: [docs/land-tap-investigation.md](docs/land-tap-investigation.md).

## Requirements

- Godot **4.7** (project feature tag is `4.7`)
- Windows is what we test on. Linux/macOS should open the same project.

## What the bot does

Talrand is a scripted opponent: it plays lands, casts cheap instants/sorceries (and can Counterspell), and attacks. Difficulty is in **Menu**.

Want to change the engine or UI? See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/first-contribution.md](docs/first-contribution.md). Where the project is headed: [docs/roadmap.md](docs/roadmap.md). Words the table uses: [docs/glossary.md](docs/glossary.md).

## License

The Aetherfold **code** in this repository is licensed under the [MIT License](LICENSE).

Card names, rules text, and imagery are property of Wizards of the Coast. This is a fan project for personal play, not an official product.
