# Player-count audit (multiplayer prep)

**Date:** 2026-09-12  
**Ticket:** [#8](https://github.com/ryanqp/aetherfold/issues/8)  
**Scope:** `engine/` kernel (plus the 1v1 table adapter, called out separately).  
**This ticket is investigation only.** Fixes belong in follow-ups.

Commander at the table is 2–6 players. The kernel already *constructs* N seats. A few combat/session paths still behave as 1v1.

## Verdict

| Layer | N-player ready? |
|---|---|
| Setup / zones / turn rotation / priority pass | **Yes** — loops `rules.player_count` / `players.size()`, wrap with `% n` |
| SBA (life, commander damage, legend) | **Yes** — iterates every `PlayerState` |
| Combat damage | **No** — always hits the **next seat**, not a chosen defender |
| `GameSession` / `TableView` | **No** — hard 1v1 (`you` vs one `rival`, seats 0 and 1) |

The engine default is **4-player Commander** (`FormatRules.commander_4p()`). The shipping table passes **`commander_1v1_table()`** (`player_count = 2`). Tests cover both 2-seat and 4-seat **construction**, not 4-seat combat.

## Kernel: already N-player

**Turn** (`engine/turn/turn_manager.gd`)

- `_rotate_turn`: `active_player_id = (active_player_id + 1) % players.size()`
- Land-drop flags and sickness clear iterate all seats
- Draw TBA uses `active_player_id`, not a hardcoded opponent

**Priority** (`engine/priority/priority_manager.gd`)

- `next_apnap`: `(from_id + 1) % n` — seat-order clockwise for any N
- All-passed when unique passers `>= players.size()`
- Step start gives priority to **active** player, then the ring

This is clockwise APNAP-by-seat-index, not “player 0 then player 1.” Fine for 2–6 as long as seats are 0..N-1 in table order.

**Setup** (`engine/engine.gd` `setup`, `zones/zone_manager.gd`)

- Players and per-player zones created with `rules.player_count`
- Default 4; 1v1 is an explicit format flag

**SBA** (`engine/sba/sba_manager.gd`)

- Life loss and commander-damage 21 check every player
- Game over when `alive.size() <= 1` and more than one seat existed

## Kernel: still 1v1-shaped

### Combat damage always hits the next seat

```gdscript
# engine/engine.gd apply_combat_damage()
var defender := (state.active_player_id + 1) % n
```

In 1v1 that is the only opponent. With 3+ players it is **only the next player in turn order**. There is no:

- choosing a defending player
- attacking multiple opponents in one combat
- per-attacker defender map

`CombatState.defending_player_id` defaults to **`1`**, which is “the 1v1 rival.” Declare-attackers does not set it; damage overwrites it with `active+1`.

Declare-attackers itself is N-safe (legal creatures you control). Blockers / multi-defender assignment are not implemented (v1 “attack all legal, unblocked”).

**Follow-up:** pick defending player(s) when declaring attackers; store them on `CombatState`; damage those ids. Needed before 1v2+ play.

## Table adapter: intentionally 1v1

Not the kernel, but it will block 3–6 player UI even after combat is fixed:

| Site | Assumption |
|---|---|
| `GameSession` | Human is seat `you_seat` (0); “other” is `1 if you_seat == 0 else 0` |
| `end_you_turn` | One other player, then `ai_take_turn(other)` |
| `prompt_text` | Seat 0 vs “Talrand” |
| `TableView` | Exactly two piles: `you` and `rival` |
| `DemoSetup.apply` | Deals **two** lists |

LAN multiplayer currently hosts **one** guest (`create_server(..., 1)`). That matches 1v1, not 1v5.

**Follow-up (after combat):** session/view that project N seats; AI or humans for seats 1..N-1.

## What not to “fix” in this ticket

- Tests using `players[1]` in a 1v1 fixture — correct for those tests
- `FormatRules.player_count = 2` on the table format — explicit 1v1, not a hidden assume-2 in the kernel
- Partner/Background “two commanders” in `CommanderValidator` — card rules, not player count
