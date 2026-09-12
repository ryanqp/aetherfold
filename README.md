# Aetherfold

A 1v1 **Magic: The Gathering Commander** table for Godot 4.7. You play Krenko (or an imported Commander deck) against a **Talrand bot**.

This is a rules-engine prototype, not a complete MTG client. You can keep/mulligan, play lands, cast spells, attack, activate Krenko, and take turns against the AI.

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

- **Vs. AI** — pick your deck, the bot’s deck, and difficulty, then Start Match.
- **Multiplayer** — create or join a 6-character room code (LAN). Host starts the match.
- **Library Builder** — import a URL/list, build a deck, or browse the gallery.
- **Menu** — audio / fullscreen.
- **Exit Game** — quits.

At the table:

- **Keep** or **Mulligan** your opening 7.
- Click a card in hand to play a land or cast it.
- **Attack** sends every creature that can attack.
- **Pass** advances a step / resolves the stack.
- **End turn** — Talrand takes his turn, then you draw.
- **Menu** → difficulty (how hard the bot plays) or **New game**.
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

## Requirements

- Godot **4.7** (project feature tag is `4.7`)
- Windows is what we test on. Linux/macOS should open the same project.

## What the bot does

Talrand is a scripted opponent: it plays lands, casts cheap instants/sorceries (and can Counterspell), and attacks. Difficulty is in **Menu**.

## License

The Aetherfold **code** in this repository is licensed under the [MIT License](LICENSE).

Card names, rules text, and imagery are property of Wizards of the Coast. This is a fan project for personal play, not an official product.
