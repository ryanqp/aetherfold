# Which creatures need no IR file

**Ticket:** [#44](https://github.com/ryanqp/aetherfold/issues/44)

Printed name, mana cost, type line, power, and toughness come from the catalog (Scryfall, or the in-memory rows tests use). `engine/cards/ir/*.json` is only the rules the engine executes.

## No IR file

Skip the JSON when the creature does nothing except exist:

- Vanilla creatures. **Goblin Piker** (2/1) is the test example. There is no `goblin_piker.json`. Power and toughness are read off `CardDefinition`.
- Creatures whose only extra text is a keyword the engine does not run yet (flying on a real card, for example). The keyword can sit on the catalog row. It will not change combat until a later rules change.
- Basic lands. Mountain, Island, Plains, Swamp, and Forest get `{T}: Add {M}` from `CardDatabase._infer_basic_mana`. They do not have JSON files.

Summoning sickness, tapping to attack, and lethal damage from combat are engine rules. They do not belong in a card file.

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
