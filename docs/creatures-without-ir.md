# Which creatures need no IR file

**Ticket:** [#44](https://github.com/ryanqp/aetherfold/issues/44)

Printed name, mana cost, type line, power, and toughness come from the catalog (Scryfall, or the in-memory rows tests use). `engine/cards/ir/*.json` is only the rules the engine executes.

## No IR file

Skip the JSON when the creature does nothing except exist:

- Vanilla creatures. **Goblin Piker** (2/1) is the test example. There is no `goblin_piker.json`. Power and toughness are read off `CardDefinition`.
- Creatures whose only extra text is a keyword. Keywords come from the catalog row's `keywords` list (Scryfall fills it in), not from IR. See the table below for which ones the engine enforces.
- Basic lands. Mountain, Island, Plains, Swamp, and Forest get `{T}: Add {M}` from `CardDatabase._infer_basic_mana`. They do not have JSON files.

Summoning sickness, tapping to attack, and lethal damage are engine rules. They do not belong in a card file.

## Keywords the engine enforces

| Keyword | Where |
|---|---|
| Haste | `RulesEngine._legal_attacker_ids`, activation |
| Defender | can't attack (`_legal_attacker_ids`) |
| Vigilance | attacking doesn't tap it (`_submit_declare_attackers`) |
| Flying / Reach | blocking legality (`_can_block`) |
| Menace | needs two or more blockers (`_submit_declare_blockers`) |
| First strike / Double strike | two combat damage steps (`apply_combat_damage`) |
| Trample | excess damage goes to the player |
| Deathtouch | 1 damage is lethal; destroyed by `SbaManager._check_creatures` |
| Lifelink | controller gains life equal to the damage |
| Indestructible | survives lethal damage and deathtouch (not 0 toughness) |
| Hexproof / Shroud / Protection from a color | targeting (`TargetingManager`) |

Turn structure follows CR 500–514; with no attackers declared, the declare blockers and combat damage steps are skipped (CR 508.8). Combat damage is assigned automatically: lethal to each blocker in the order they were declared, the rest to the last blocker, or to the player with trample. Any other keyword on a catalog row (ward, flash, prowess, …) is shown but not run yet.

## An IR file is required

Add JSON when the card should do something the type line cannot say:

| What it does | Example in `engine/cards/ir/` |
|---|---|
| Mana ability | `llanowar_elves.json`, `elvish_mystic.json`, `fyndhorn_elves.json` |
| Activated ability that is not mana | `krenko_mob_boss.json` |
| Triggered ability | `talrand_sky_summoner.json` (makes a Drake when you cast an instant or sorcery) |

A creature spell does **not** need a `SPELL` ability just to be cast. The engine charges `CardDefinition.mana_cost` and moves the object onto the battlefield. The IR file, when it exists, holds the abilities that work after that.

## How to check a new creature

1. If the Oracle text is empty, or only restates power/toughness, do not add a file.
2. If the text is `{T}: Add …`, `Whenever …`, or another activated ability, add a file. Follow [adding-a-card.md](adding-a-card.md).
3. If you are unsure, search `engine/cards/ir/` for the printed name. No file means the engine is treating it as a vanilla body.
