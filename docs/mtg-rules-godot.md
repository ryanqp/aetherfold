# MTG rules to Godot

Authority is the Comprehensive Rules at [magic.wizards.com/en/rules](https://magic.wizards.com/en/rules). This page maps those systems onto the live kernel: `GameSession` calls `RulesEngine` in `engine/engine.gd`. `scripts/match_state.gd` is not the game. Card meaning lives in IR under `engine/cards/ir/`, not in a name check.

The longer wording catalog is [mtg-effects-cheatsheet.md](mtg-effects-cheatsheet.md). New effect keys are listed in [adding-a-card.md](adding-a-card.md).

## How a card becomes a procedure

| Step | Where |
|---|---|
| Printed card | `CardDefinition` from the catalog. Power, toughness, and types on this object stay printed. |
| Executable text | IR `Ability`: kind `SPELL`, `ACTIVATED`, `TRIGGERED`, `STATIC`, `REPLACEMENT`, or `MANA`. `granted: true` is printed but inactive until a continuous effect gains it. |
| Clause shape | `OracleStructure.clauses` labels a `{cost}:` line as activated, and When/Whenever/At as triggered. It does not resolve cards. |
| Cost | `AbilityCost` (`MANA`, `TAP`, `UNTAP`, `ADDITIONAL_MANA`). `CostManager.can_pay` checks tap and untap only. Mana is paid after the ability is announced. |
| Effect | `AbilityEffect` plus params. Unlisted keys fail to load. |
| Object | `GameObject` in a real zone. Moving it retires the old id (CR 400.7). |
| Stack | `StackEntry`: kind, source, controller, targets, choices, effects, cursor. |
| Decision | `PlayerDecision`. The mode becomes `AWAITING_DECISION` and resolution stays on that entry. |
| Characteristics | `LayerManager.snapshot`. Layer 4 sets subtypes, layer 6 adds abilities and keywords, layer 7b sets power/toughness, layer 7c adds modifiers, layer 7d applies `+1/+1` and `-1/-1` counters. |

## Activation

Selecting a permanent does not run its text.

1. `activation_report` lists activated abilities from `LayerManager.abilities_for`.
2. A legal ability is one whose cost can be paid and whose restrictions pass. A subtype such as "if this is a Scout" is checked when the effect resolves, so the ability can still be activated.
3. Summoning sickness (`summoning_sickness_blocks`) is only a `{T}` or `{Q}` cost on a creature that has not been controlled since the controller's most recent turn began, unless it has haste.
4. The player picks one ability. The table calls `GameSession.activate_ability`. Several legal abilities produce "Choose an ability."
5. Targets, if any, are chosen, then mana is paid (`PAYING_COSTS`). A cost with no mana, such as Krenko's `{T}`, goes on the stack in that same action.
6. `_put_activated_on_stack` pays the tap or untap cost and pushes an `ACTIVATED` entry. The permanent stays on the battlefield.
7. Players receive priority. `both_pass` resolves the top entry. Effects run in order. A `MAY` or `CHOOSE` effect stops there until `SUBMIT_DECISION` or `DECLINE_DECISION`.

The selection overlay prints `=== ABILITY DEBUG ===` while match debug is on.

## Decisions and targets

`MAY` and `CHOOSE` do not pick the first option, a random option, or a default creature type. The human gets Yes/No or one button per listed option. The opponent's policy may answer its own decisions; that answer is not a rules default.

`TargetingManager` treats target, "any target" (players and creatures), and a permanent query as different. Hexproof blocks opponents. Shroud blocks everyone. "Protection from {color}" blocks a source of that color. Ward does not make a target illegal.

"You may play that card this turn" is `EXILE_TOP` with `may_play: END_OF_TURN`. The exiled card stays in exile with `may_play_controller` set. Casting it is a later action and still costs mana. Cleanup clears the permission.

## What is still incomplete

Layers 1–3, 5, 7a, and 7e. First strike and double strike are stored as keywords; combat still has one damage step. Damage is marked during the damage event, and lethal creatures are still moved inside that event rather than by state-based actions. Ward triggers, protection beyond color, and hexproof-from are not implemented. Replacement effects exist for the command zone, not as a general system. Trigger order is the battlefield order, not a player-chosen APNAP batch. Costs other than mana, tap, and untap (life, sacrifice, discard, exile, mill, remove a counter) are not payable yet. Scry, surveil, and search load as data and do not open a choice UI. Most keyword actions (explore, connive, cascade, mutate, foretell, and the rest) are not procedures yet. Poison, energy, experience, and loyalty-zero state-based actions are not checked.
