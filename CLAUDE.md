# Aetherfold — guide for Claude

A fan **Magic: The Gathering Commander** table in **Godot 4.7** (GDScript). The goal: two friends duel with their own Commander decks (imported from Moxfield/Archidekt, later from card photos), over a room code, with the official rules deciding how cards and turns work.

## Layout

- `engine/` — headless rules kernel. **All gameplay rules live here.** Entry point `engine/engine.gd` (`RulesEngine`).
  - `zones/`, `stack/`, `priority/`, `turn/`, `combat/`, `mana/`, `costs/`, `targeting/`, `triggers/`, `replacement/`, `layers/` (CR 613), `sba/` (state-based actions, CR 704).
  - `abilities/ability_executor.gd` — runs IR effects (`DRAW`, `DEAL_DAMAGE`, `CREATE_TOKEN`, …).
  - `cards/` — `CardDefinition`, `CardDatabase`, `IrLoader`, `TokenCatalog`. `cards/ir/*.json` is per-card rules IR.
  - `import/` — deck import (Moxfield, Archidekt, Deckstats, TappedOut, plain text) + Commander legality.
  - `session/` — `GameSession` adapter between engine and UI, `TableView`, `DemoSetup`.
- `scripts/` — Godot UI: `table.gd`, `ui/main_menu.gd`, `rival_ai.gd` (bot), `net/game_net.gd` (LAN rooms, ENet + UDP beacon), autoloads `ScryfallCatalog`, `AppState`, `GameNet`.
- `scenes/` — `main_menu.tscn` (main scene), `table.tscn`.
- `tests/engine/` — `test_*.gd` suites (`extends McpTestSuite`), shared helpers in `fixtures.gd`.
- `tools/` — `run_tests.gd` (headless runner), `fetch_scryfall.py`, `fetch_card_images.py`.
- `docs/` — read before changing an area: `adding-a-card.md`, `adding-a-token.md`, `creatures-without-ir.md`, `testing.md`, `roadmap.md`, `migration-status.md`.

## Don't touch

- `addons/godot_ai/` — third-party editor plugin.
- `scripts/match_state.gd` — leftover prototype; no new gameplay there.
- `*.uid` files are Godot-generated; commit them alongside new scripts but don't hand-edit.

## Commands

Run from the repo root (folder with `project.godot`):

```
godot --headless --path . -s res://tools/run_tests.gd                         # all suites
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_combat # one suite (suite_name(), not file name)
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_combat --test=trample --verbose
```

Exit code 0 = all passed. In Claude's cloud workspace Godot 4.7 can be downloaded from GitHub releases to run the suites headless.

Scryfall catalog (optional, for real cards/art): `python tools/fetch_scryfall.py`, location from `AETHERFOLD_SCRYFALL_DIR` (default `D:\AetherfoldData\scryfall\catalog.jsonl`).

## How rules are built

- **Cards are data, the engine is procedures.** Card names, cost, type line, Oracle text, P/T and `keywords` come from the Scryfall catalog row. Only behaviour the engine can't infer goes in `engine/cards/ir/<snake_name>.json`. Never add card-name special cases to engine or UI code.
- **IR schema is strict.** `IrLoader` rejects unknown keys on abilities/costs/effects. Allowed effect kinds and params are listed in `docs/adding-a-card.md` and `engine/cards/ir_loader.gd`. Use `"unparsed": true` for text the engine can't do yet.
- **Keywords come from the catalog**, not IR. Enforced today: haste, defender, vigilance, flying/reach, menace, first/double strike, trample, deathtouch, lifelink, indestructible, hexproof/shroud/protection-from-color (table in `docs/creatures-without-ir.md`). Use `RulesEngine.has_keyword(obj, "Name")`, which respects continuous effects.
- **Current characteristics come from `LayerManager.snapshot()`**, never straight off `CardDefinition`, so effects and counters apply.
- **Creature death is a state-based action** (`SbaManager._check_creatures`): call `engine.sba.check(engine)` after dealing damage instead of moving creatures to the graveyard yourself.
- Zone changes create a new object id (CR 400.7) — re-fetch objects after a move.
- Cite Comprehensive Rules numbers (`CR 702.19`) in comments when implementing a rule.

## Adding a card or rule

1. Check whether a keyword or existing IR effect already covers it.
2. Add/extend IR per `docs/adding-a-card.md`; new tokens go in `TokenCatalog` (`docs/adding-a-token.md`).
3. Add test rows to `tests/engine/fixtures.gd` `memory_catalog()` (use `_keyword_creature()` for vanilla keyword bodies) and a test in the matching suite.
4. Update docs when you change what the engine enforces.

## Known gaps (as of 2026-10)

- ~29 cards have hand-written IR. Everything else is read from Oracle text by `engine/cards/oracle_ir.gd` (see `docs/adding-a-card.md` §6b). Lines it can't read are listed in History ("not coded"); `tools/coverage_report.gd -- --cards=<rows.json>` lists them for a deck (the 8 precons: 224 of 549 cards fully read).
- Keywords (cross-checked against the 2026-09-25 rules, see `docs/keyword-audit.md`): every CR 701/702 keyword has an entry in `engine/cards/keyword_db.gd` with a status (ENFORCED / PARTIAL / NONE for 1v1-irrelevant ones: Planechase, Archenemy, Attractions, hidden agenda, assist, companion). `keyword_lines.gd` parses the keyword lines (costed, numbered, flags, level/station bands), `keyword_rules.gd` plans casts (alternative and additional costs, cast-from-graveyard/exile modes, timing), runs special actions (cycling, suspend, ninjutsu, plot, foretell, transmute, channel/forecast, unearth, scavenge, encore/eternalize/embalm, outlast, level up, station, saddle, fortify, reconfigure, crew, turn face up) and what a permanent cast a special way does as it lands (evoke, blitz, warp, offspring, squad, sneak, bestow, mutate). Keyword actions are in `engine/abilities/keyword_actions.gd`, precon effects in `precon_effects.gd`. Day/night, speed, the initiative, the monarch and the Ring are tracked; the life box shows them.
- Commander damage (CR 903.10a): combat damage from a commander is tallied per commander in `PlayerState.commander_damage_from`; 21 from one loses the game (`SbaManager._check_commander_damage`). The table shows it under the life total (`TableView` player dict: `cmdr_damage`, `cmdr_need`, `lose_reason`), and the game-over banner (`table.gd` `_build_gameover`) names the cause.
- The table's pick menu (`GameSession.card_menu` / `zone_menu`) lists every legal cast mode and special action for a card; decisions during resolution use `ChoiceDialog`. Targets for casts are still picked automatically (`GameSession._choose_target_auto`); there is no target picker yet.
- Blocking works against the bot (you block via the table; the bot blocks with `engine/session/ai_blocks.gd`). LAN multiplayer doesn't prompt the defender to block yet.
- Combat damage assignment is automatic (no player-chosen order or split).
- Multiplayer is LAN-only; internet play by code needs a relay/matchmaking service.
- No photo-to-card scanning yet.

## Git

Branch off `main`, keep changes scoped, open a PR against `main`. Card names, art and rules text belong to Wizards of the Coast; code is MIT.
