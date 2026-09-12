# Opponent lands looking tapped (#10)

**Date:** 2026-09-12  
**Ticket:** [#10](https://github.com/ryanqp/aetherfold/issues/10)

Playtesting reported the bot’s land “enters tapped.” The live table does **not** use `scripts/rival_ai.gd` / `MatchState.tap_player_lands`. It uses `GameSession.ai_take_turn()` → `PLAY_LAND` then often `cast_auto` in the same burst.

## What actually happens

1. **ETB:** `ZoneManager.move` onto the battlefield sets `tapped` only via `CardDefinition.enters_tapped()` (oracle “enters the battlefield tapped” / “enters tapped”, and not if “unless” is in the text). Basics do not match that. Tests: `test_island_enters_untapped`, `test_basic_land_enters_untapped`, `test_bot_island_stays_untapped_until_mana_ability`.
2. **Same turn:** Talrand’s AI plays a land, then casts Opt / Ponder / etc. with `auto_pay`, which taps that Island for `{U}`. Legal. The table only refreshes **after** the whole AI turn, so you never see the untapped frame.
3. **Real ETB-tapped cards:** Forgotten Cave (and similar) *should* come in tapped. `test_forgotten_cave_enters_tapped`.

So a tapped Island after End turn is usually “it was used for mana,” not “it entered tapped.” A tapped Forgotten Cave is printed rules.

## What we did not change

No engine tap-on-play for opponent basics. `rival_ai.gd` print-debug was the wrong file (`USE_ENGINE := true`).
