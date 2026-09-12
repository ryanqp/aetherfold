# Contributing to Aetherfold

Thanks for helping. This is a Godot **4.7** Commander table: a real rules kernel plus a 1v1 UI.

## Repo layout

- `engine/` — rules engine (zones, stack, priority, combat, card IR). **This is what the live game uses.**
- `scripts/` — Godot UI: table, main menu, Scryfall art, import overlay, LAN lobby.
- `scenes/` — `main_menu.tscn` (F5) and `table.tscn` (the match).
- `tests/engine/` — headless `McpTestSuite` scripts (`test_*.gd`).
- `docs/` — how to run tests, add a card, migration status.
- `addons/godot_ai/` — third-party editor plugin. **Do not edit it** unless you are fixing the plugin itself.

`scripts/match_state.gd` is leftover prototype code. Do not add new gameplay there. See [docs/migration-status.md](docs/migration-status.md).

## Run the game

1. Install Godot 4.7 (Standard, not .NET).
2. Clone this repo and **Import** the folder that contains `project.godot`.
3. Press **Play** (F5). Main scene: `scenes/main_menu.tscn`.

More play notes: [README.md](README.md).

## Run tests

From the project root (see [README — Running tests](README.md#running-tests) and [docs/testing.md](docs/testing.md)):

```
godot --headless --path . -s res://tools/run_tests.gd
```

One suite / one test:

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack --test=test_creature_not_in_play
```

Exit code `0` means all passed. Add `--verbose` after `--` to print every test name.

If you add a card’s rules, follow [docs/adding-a-card.md](docs/adding-a-card.md) and add a test under `tests/engine/`.

## Branches and PRs

1. Branch off `main` (`git checkout -b your-change`).
2. Keep the change scoped to the issue.
3. Run the test suite locally and keep it green.
4. Open a pull request against `main`.
5. In the PR body, mention the issue (`Closes #N` if it fully fixes it).

Use your own GitHub name and email in `git config` — do not copy someone else’s identity.

## License

Code is [MIT](LICENSE). Card names, rules text, and imagery belong to Wizards of the Coast.
