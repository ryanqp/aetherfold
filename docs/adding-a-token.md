# How to add a token

Tokens are created by a spell or ability. They are not cards in `engine/cards/ir/` by themselves.

## 1. Register the token

Edit `engine/cards/token_catalog.gd`.

1. Add a constant id, lowercase with underscores: `soldier_1_1_w`.
2. Add a `match` arm in `definition_for()` that fills `name`, `type_line`, `power`, `toughness`, and colors.

The id is the string you will put in JSON. It is not a file name.

## 2. Point a spell at it

In the spell's IR file, use `CREATE_TOKEN`:

```json
{ "kind": "CREATE_TOKEN", "params": { "token": "soldier_1_1_w", "count": 2 } }
```

`count` may be an integer or a query object. Krenko uses a query. Raise the Alarm uses `2`. See [adding-a-card.md](adding-a-card.md).

## 3. Cover it with a test

Spawn the spell, pay, let both players pass, and assert the battlefield has that many tokens with the printed stats. `tests/engine/test_engine_new_cards.gd` does this for Raise the Alarm.

Ids that exist today:

- `goblin_1_1_r` — 1/1 red Goblin
- `drake_2_2_u_flying` — 2/2 blue Drake with flying
- `soldier_1_1_w` — 1/1 white Soldier
