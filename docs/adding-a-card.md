# Adding a card to `engine/cards/ir`

Printed name, mana cost, type line, and Oracle text come from the **catalog** (Scryfall / `CatalogSource`).  
`engine/cards/ir/*.json` is only the **rules IR**: what the engine actually does when you cast, tap, or trigger the card.

You do **not** need an IR file for:

- Basic lands (Mountain / Island / … get `{T}: Add {M}` automatically)
- Vanilla permanents that just sit on the battlefield

You **do** need an IR file if the card should draw, make tokens, counter, bounce, tap for non-basic mana, or fire a trigger.

There are a handful of authored cards today (`opt.json`, `dragon_fodder.json`, `krenko_mob_boss.json`, …). This is how you add the next one.

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
| `DRAW` | `n` | Draw that many cards |
| `CREATE_TOKEN` | `token`, `count` | `token` is a `TokenCatalog` id. `count` is an int **or** a `{ "query": { … } }` |
| `COUNTER_SPELL` | `target` | Index into this ability’s `targets` array |
| `MOVE_ZONE` | `target`, `to` | `to` is a zone name (`HAND`, `GRAVEYARD`, …) |
| `ADD_MANA` | `mana` | e.g. `"{R}"` |
| `TAP` | `target` | |
| `UNTAP` | `target` | |
| `DEAL_DAMAGE` | `n`, `target` | |
| `CREATE_CONTINUOUS_EFFECT` | `layer`, `mod`, `duration`, `query` | |
| `SCRY` | `n` | Loader accepts it; Opt still marks Scry `unparsed` |
| `LOOK` | `n` | |
| `SHUFFLE` | `n` | |

### Tokens

`CREATE_TOKEN` `token` values that exist today in `engine/cards/token_catalog.gd`:

- `goblin_1_1_r` — 1/1 red Goblin
- `drake_2_2_u_flying` — 2/2 blue Drake with flying

A new token type needs a new branch in `TokenCatalog.definition_for()` **and** the IR id.

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
