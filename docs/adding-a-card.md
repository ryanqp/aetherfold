# Adding a card to `engine/cards/ir`

Printed name, mana cost, type line, and Oracle text come from the **catalog** (Scryfall / `CatalogSource`).  
`engine/cards/ir/*.json` is only the **rules IR**: what the engine actually does when you cast, tap, or trigger the card.

You do **not** need an IR file for:

- Basic lands (Mountain / Island / … get `{T}: Add {M}` automatically)
- Vanilla permanents that just sit on the battlefield

You **do** need an IR file if the card should draw, make tokens, counter, bounce, tap for non-basic mana, or fire a trigger.

Authored IR lives in `engine/cards/ir/` (Opt, Dragon Fodder, Krenko, burn, rituals, Sol Ring, …). This is how you add the next one.

## 1. Create the file

Put a JSON object in:

```
engine/cards/ir/<snake_name>.json
```

The file name is only for humans. The engine indexes the file by:

1. `"oracle_id"` if present, else
2. `"name"` lowercased (`"Dragon Fodder"` → `"dragon fodder"`)

`CardDatabase` looks up a catalog card the same way: oracle id first, then printed name. **The `"name"` field must match the catalog name exactly.**

`IrLoader.load_dir("res://engine/cards/ir")` runs at `CardDatabase.setup()`. Unknown keys on an **ability / cost / effect** object fail the load — do not invent fields.

## 2. Top-level object

| Field | Required | Meaning |
|---|---|---|
| `name` | yes (unless `oracle_id`) | Printed English name |
| `oracle_id` | optional | Scryfall oracle id; preferred if you have it |
| `abilities` | yes | Array of ability objects (may be empty) |

Anything else at the top level is ignored. `abilities` must be an array.

## 3. Ability object

Allowed keys (anything else is an error):

`ability_id`, `kind`, `costs`, `targets`, `effects`, `trigger`, `replacement`, `restrictions`, `text`, `unparsed`

| Field | Meaning |
|---|---|
| `ability_id` | Unique string for this ability (`"opt_draw"`) |
| `kind` | One of `SPELL`, `ACTIVATED`, `TRIGGERED`, `STATIC`, `REPLACEMENT`, `MANA` |
| `costs` | Array of cost objects |
| `targets` | Array of target slots (see below) |
| `effects` | Array of effect objects, resolved in order |
| `trigger` | Object used by `TRIGGERED` abilities |
| `replacement` | Object used by `REPLACEMENT` abilities |
| `restrictions` | Array (timing / “only as a sorcery”, etc.; often `[]`) |
| `text` | Oracle reminder; not executed |
| `unparsed` | `true` = store the text, **do not** run it |

Use `unparsed: true` when the reminder exists but the engine cannot do it yet (Opt’s Scry, Ponder’s reorder, Forgotten Cave cycling).

### Kinds you will actually use

- **`SPELL`** — the card’s spell ability (what happens when it resolves). Instants/sorceries need this. The `MANA` cost here should match the printed mana cost.
- **`MANA`** — `{T}: Add {R}.` (Forgotten Cave). Distinct from `ACTIVATED`.
- **`ACTIVATED`** — `{T}: …` that is not a mana ability (Krenko).
- **`TRIGGERED`** — “Whenever …, …” (Talrand). Needs a `trigger` object.

`STATIC` / `REPLACEMENT` are accepted by the loader; keep them `unparsed` unless you are extending those systems.

## 4. Cost object

Allowed keys: `kind`, `mana`, `from`

`kind` is one of:

| `kind` | Fields |
|---|---|
| `MANA` | `mana` — Scryfall-style string, e.g. `"{1}{R}"`, `"{U}{U}"` |
| `TAP` | no mana (the `{T}` symbol) |
| `ADDITIONAL_MANA` | extra mana (commander tax uses the engine, not this file) |

Example: tap plus nothing else:

```json
{ "kind": "TAP" }
```

## 5. Effect object

Allowed keys: `kind`, `params`

`params` must be an object. **Only the params listed for that kind are allowed.**

| `kind` | `params` | Notes |
|---|---|---|
| `DRAW` | `n`, `if_link` | Draw that many cards. `if_link` runs only after that decision was accepted |
| `SET_CHARACTERISTICS` | `if_subtype`, `subtypes`, `power`, `toughness`, `keywords`, `gain_abilities`, `duration` | Continuous effect on the source. `if_subtype` is checked when the effect resolves. `duration` is `PERMANENT` or `END_OF_TURN`. Does not rewrite the printed card |
| `EXILE_TOP` | `n`, `who`, `may_play` | Exile that many cards from the top of the effect controller's library. `may_play` `END_OF_TURN` lets that player play them until cleanup |
| `MAY` | `link`, `prompt` | Pause for a yes/no. Does not pick an answer |
| `CHOOSE` | `choice`, `link`, `options`, `optional`, `prompt` | Pause for one of `options`. Does not invent an option |
| `PUT_COUNTER` | `name`, `n`, `target` | Add counters on the targeted object. A `+1/+1` counter is not a power change |
| `CREATE_TOKEN` | `token`, `count` | `token` is a `TokenCatalog` id. `count` is an int **or** a `{ "query": { … } }` |
| `COUNTER_SPELL` | `target` | Index into this ability’s `targets` array |
| `MOVE_ZONE` | `target`, `to` | `to` is a zone name (`HAND`, `GRAVEYARD`, …) |
| `ADD_MANA` | `mana` | e.g. `"{R}"`. Choices: `"{R|G}"` (one of), `"{W|U|B|R|G}"` (any color), `"{CI}"` (a color in your commander's identity) |
| `TAP` | `target` | |
| `UNTAP` | `target` | |
| `DEAL_DAMAGE` | `n`, `target` | |
| `LOSE_LIFE` | `n`, `target` | That object's controller loses `n` life. Not damage. |
| `GAIN_LIFE` | `n`, `target` | Omit `target` and the effect's controller gains `n` life. With `target`, that player (or that object's controller) does |
| `DESTROY` | `target` | CR 701.7. Goes to the owner's graveyard unless indestructible. Not a regenerate or "can't be destroyed" check beyond that |
| `PUMP` | `target`, `power`, `toughness`, `keywords`, `duration` | Temporary +X/+Y and keywords on one creature. `duration` defaults to `END_OF_TURN` |
| `CREATE_CONTINUOUS_EFFECT` | `layer`, `mod`, `duration`, `query` | |
| `SCRY` | `n` | Loader accepts it; Opt still marks Scry `unparsed` |
| `LOOK` | `n` | |
| `SHUFFLE` | `n` | |

### Tokens

`CREATE_TOKEN` `token` values that exist today in `engine/cards/token_catalog.gd`:

- `goblin_1_1_r` — 1/1 red Goblin
- `drake_2_2_u_flying` — 2/2 blue Drake with flying
- `soldier_1_1_w` — 1/1 white Soldier

A token is not its own IR file. Add a branch in `TokenCatalog.definition_for()`, then point a spell's `CREATE_TOKEN` effect at that id. Step by step: [adding-a-token.md](adding-a-token.md).

Krenko’s `count` is a query, not a number:

```json
"count": {
  "query": {
    "zone": "BATTLEFIELD",
    "controller": "SOURCE_CONTROLLER",
    "type": "creature",
    "subtype": "Goblin"
  }
}
```

## 6. Targets

Each entry is an object. Common shape:

```json
{ "id": 0, "kind": "SPELL_ON_STACK", "count": 1 }
```

```json
{ "id": 0, "kind": "PERMANENT", "count": 1, "query": { "type": "creature" } }
```

`id` is the slot index. Effects refer to it with `"target": 0`.

Known `kind` values in the authored cards:

- `SPELL_ON_STACK` — Counterspell / Cancel
- `PERMANENT` — Unsummon (`query.type = "creature"`)

Target `query` accepts `type`, `not_type`, `subtype`, and `controller`: `SOURCE_CONTROLLER`, `OPPONENT` ("you don't control"), or `ANY`.

## 6b. Cards you don't have to write

`engine/cards/oracle_ir.gd` (`OracleIr`) reads plain Oracle text into IR when a card has no `ir/*.json`. Hand-written IR always wins. Cards from any source (Moxfield, Archidekt, Scryfall) work this way: the engine finds the wording and responds.

**Instants and sorceries** are all-or-nothing: every sentence must match or the card stays unimplemented. **Permanents** are read line by line; a line that isn't understood is skipped and listed under "not coded" in History, and the card keeps its other abilities. Reminder text is ignored, the card's name / "this creature" becomes `~`, and ability words ("Landfall —") are stripped.

| Oracle wording | Becomes |
| --- | --- |
| `{T}: Add {G}.` / `{R} or {G}` / `one mana of any color` | mana ability |
| `Equip {N}` + `Equipped creature gets +X/+Y and has <keywords>` | `ATTACH` (sorcery speed) + static boost |
| `Other Dinosaurs you control get +1/+1`, `... of the chosen type` | static `STATIC` |
| `Dinosaur spells you cast cost {1} less` | static cost reduction |
| `When ~ enters / dies / attacks / deals combat damage to a player / is dealt damage` | trigger |
| `Whenever another Dinosaur you control enters / dies / attacks`, `you cast a <type> spell`, `you gain life` | trigger with a filter |
| `At the beginning of your upkeep / end step / combat` | step trigger |
| `deals N damage to <target / each opponent / each other creature>` | `DEAL_DAMAGE` / `DEAL_DAMAGE_EACH` |
| `Destroy target …`, `Destroy all creatures` | `DESTROY` / `DESTROY_ALL` |
| `Exile target …`, `Return target … to its owner's hand` | `MOVE_ZONE` |
| `Return target <type> card from your graveyard to your hand / the battlefield` | `RETURN_FROM_GRAVEYARD` |
| `Draw N cards`, `You gain / lose N life`, `Each opponent loses N life` | `DRAW`, `GAIN_LIFE`, `LOSE_LIFE` |
| `Create a Treasure / Food / Clue`, `Create a 3/3 green Dinosaur creature token [with trample]` | `CREATE_TOKEN` |
| `Put N +1/+1 counters on <~ / target / each creature you control>` | `PUT_COUNTER` |
| `<target> gets +X/+Y [and gains <keywords>] until end of turn` | `PUMP` |
| `Search your library for a basic land card, put it onto the battlefield tapped` | `SEARCH_LIBRARY` |
| `Scry N`, `Untap …`, `Counter target spell`, `~ fights target …` | `SCRY`, `UNTAP`, `COUNTER_SPELL`, `FIGHT` |
| `Prowess`, `As ~ enters, choose a creature type`, `~ enters with N +1/+1 counters` | built in |

| `~ costs {2} less to cast if it targets a Dinosaur you control` | spell discount (`cost_reduction_if_target`) |
| `enters tapped unless you control …`, "reveal a Mountain or Forest", "pay 2 life" | `EtbRules`, applied as the land arrives |

Keywords are looked up in `engine/cards/keyword_db.gd` (`KeywordDb`): each has a status (ENFORCED, READ, NONE or MISSING). Missing ones show in History as "(ward: not enforced yet)". When you implement one, change its status there. Reveal and pay-life choices have no prompt yet: revealing always happens when you can, life is paid while you have 8 or more.

Up to three targets per card; each is chosen one at a time. Targets are picked automatically (see CLAUDE.md). Not read yet: Auras, kicker, cycling, flashback, crew, ward, convoke, X costs, modal "choose one", conditional ("if ...") triggers, discover / explore / monarch. To teach it a new wording, add the pattern to `OracleIr._sentence` (or `_header` for triggers) and a row to `tests/engine/fixtures.gd`; to cover a card it can't read, write IR as below.

## 7. Triggers

Used when `kind` is `TRIGGERED`. Talrand:

```json
"trigger": {
  "on": "SPELL_CAST",
  "filter": {
    "controller": "SOURCE_CONTROLLER",
    "types": ["instant", "sorcery"]
  }
}
```

`TriggerManager` currently matches `on: "SPELL_CAST"` only.

## 8. Worked example: Dragon Fodder

This is a complete, executable spell — copy this shape for “do X on resolve”.

```json
{
  "name": "Dragon Fodder",
  "abilities": [
    {
      "ability_id": "dragon_fodder_spell",
      "kind": "SPELL",
      "costs": [{ "kind": "MANA", "mana": "{1}{R}" }],
      "targets": [],
      "effects": [{
        "kind": "CREATE_TOKEN",
        "params": { "token": "goblin_1_1_r", "count": 2 }
      }],
      "text": "Create two 1/1 red Goblin creature tokens."
    }
  ]
}
```

Opt shows a **partial** card: draw is implemented, Scry is `unparsed`:

```json
{
  "ability_id": "opt_scry",
  "kind": "SPELL",
  "unparsed": true,
  "text": "Scry 1."
}
```

## 9. Copy-paste template

Save as `engine/cards/ir/shock.json` (rename everything):

```json
{
  "name": "Shock",
  "abilities": [
    {
      "ability_id": "shock",
      "kind": "SPELL",
      "costs": [{ "kind": "MANA", "mana": "{R}" }],
      "targets": [{ "id": 0, "kind": "PERMANENT", "count": 1 }],
      "effects": [{ "kind": "DEAL_DAMAGE", "params": { "n": 2, "target": 0 } }],
      "text": "Shock deals 2 damage to any target."
    }
  ]
}
```

Then:

1. Make sure the catalog (or `DemoSetup` / `Fixtures` memory db) contains a card named **Shock**.
2. If you need a new token, add it to `token_catalog.gd`.
3. Add a test in `tests/engine/` (see `test_engine_ir.gd` for Fodder / Opt).
4. Run:

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_ir
```

A load error from `IrLoader` (unknown key / unknown effect kind) means the JSON does not match the tables above — fix the file, don’t special-case the loader.

### Hideaway, mill, discard, surveil (BF-42)

| Oracle wording | Effect kind |
| --- | --- |
| `Hideaway N` | trigger on enter: `HIDEAWAY {n}` (exiles the best of the top N, rest to the bottom) |
| `play the exiled card without paying its mana cost [if creatures you control have total power N or greater]` | `PLAY_HIDDEN {min_total_power}` |
| `each opponent mills N cards` / `you mill N cards` | `MILL {n, who}` |
| `each opponent discards N cards` / `you discard N cards` | `DISCARD {n, who}` (auto-picks the cheapest) |
| `surveil N` | `SURVEIL {n}` (spare lands go to the graveyard) |

Fear, intimidate and skulk are enforced when blocking. Unread lines print as `UNIMPLEMENTED_MECHANIC: <Card> — <line>` in the Godot Output panel.
