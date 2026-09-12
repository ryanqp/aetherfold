# Migration status: `engine/` vs `scripts/`

**As of 2026-09-12:** the live game runs on the **rules engine** (`engine/`), not on `MatchState`.

`docs/aetherfold-rules-engine.md` is the original design/PR plan. It still describes the *pre-migration* prototype in present tense. Trust **this file** for “what drives play today.”

## What drives a match

```
main_menu.tscn
    → table.tscn (scripts/table.gd)
        → GameSession  (engine/session/game_session.gd)
            → RulesEngine (engine/engine.gd)
            → TableView   (engine/session/table_view.gd)
```

- `scripts/table.gd` has `const USE_ENGINE := true`.
- On startup it creates a `GameSession`, calls `start_with_demo()` / `start_imported()` / `AppState.make_demo()`, and **paints from `session.view`** (`_board()`).
- Clicks (play land, cast, activate, attack, pass, end turn, keep/mulligan) go through `GameSession` → `RulesEngine.submit`.
- Opponent turns on the engine path are `GameSession.ai_take_turn()`, not `RivalAI.take_turn()`.

Do **not** add new gameplay to `scripts/match_state.gd`. That file is the old dictionary prototype (immediate spell resolution, GY as an int, name-special-cased AI). It is still constructed (`var state = MatchStateScript.new()`) and still used if someone flips `USE_ENGINE` to `false`. Shipping play never takes that branch.

## Who owns what

| Path | Role now | Edit when… |
|---|---|---|
| `engine/engine.gd` + `engine/**` | Rules: zones, stack, priority, SBA, combat, commander, IR | Changing how Magic works |
| `engine/session/game_session.gd` | Match start, mulligan, auto-pay, AI burst, import → demo | Changing table-facing game flow |
| `engine/session/table_view.gd` | Projects engine objects into chip dicts | Changing what the UI can see |
| `engine/cards/ir/*.json` | Executable abilities | Adding a card’s rules ([adding-a-card.md](adding-a-card.md)) |
| `scripts/table.gd` | UI only: layout, art, animation, input routing | Changing how the table *looks* or which session method a click calls |
| `scripts/scryfall_catalog.gd` | Card art + Oracle metadata cache | Catalog / images |
| `scripts/app_state.gd`, `scripts/ui/`, `scripts/net/` | Menu, deck picks, LAN lobby | Front-end / multiplayer lobby |
| `scripts/match_state.gd` | **Legacy.** Do not extend. | Only if fixing the `USE_ENGINE := false` rollback path |
| `scripts/rival_ai.gd` | `label()` is live (difficulty names). `take_turn(state)` is **MatchState-only**. Engine AI lives in `GameSession`. | Difficulty labels, or the dead MatchState AI |
| `tests/engine/` | Kernel + session tests | Any engine change |

## Still leftover (do not treat as “the game”)

- **`USE_ENGINE` flag** — default true. False still wires `MatchState` + `RivalAI.take_turn`. Planned delete: design-doc PR-23.
- **`MatchState` instance on the table** — allocated even when unused.
- **`rival_ai.gd` name checks** (`opt`, `ponder`, `unsummon`, `counterspell`) — only the old path.
- Design-doc “current architecture” (no `res://engine/`, main scene `table.tscn`) — **stale**. Main scene is `scenes/main_menu.tscn`.

## If you are changing rules

1. Change `engine/` (and IR JSON if it is card-specific).
2. Add/adjust `tests/engine/test_*.gd`.
3. Run `godot --headless --path . -s res://tools/run_tests.gd` ([testing.md](testing.md)).
4. Only then touch `table.gd` if the table must call a new `GameSession` method or display a new `TableView` field.

If you only change hover, chips, or the main menu, leave `engine/` alone.
