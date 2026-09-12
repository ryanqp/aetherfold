# Running tests

Engine tests live in `tests/engine/` as `test_*.gd` scripts. Each file extends `McpTestSuite` and exposes a `suite_name()` (for example `engine_stack`, `engine_combat`). Helpers such as `fixtures.gd` are **not** named `test_*.gd`, so they are not run as suites.

You need **Godot 4.7** (same version as the game). Put the editor binary on your `PATH` as `godot`, or replace `godot` below with the full path to `Godot_v4.7.*_win64.exe` / `Godot_v4.7.*_linux.x86_64`.

All commands are run from the **project root** (the folder that contains `project.godot`).

## Whole suite

```
godot --headless --path . -s res://tools/run_tests.gd
```

Expect a summary like `passed: N  failed: 0`. Exit code `0` means all tests passed; `1` means at least one failed; `2` means a bad `--suite` name.

Verbose (prints every test name):

```
godot --headless --path . -s res://tools/run_tests.gd -- --verbose
```

## One suite

`--suite` is the string returned by `suite_name()`, not the file name.

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack
```

`test_engine_stack.gd` → `--suite=engine_stack`  
`test_engine_combat.gd` → `--suite=engine_combat`

## One test

`--test` is a substring of the method name (`test_*` in the suite file).

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack --test=test_creature_not_in_play_while_stacked
```

Shorter substrings work too:

```
godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack --test=creature_not_in_play
```

## From the Godot editor

The `godot_ai` editor plugin discovers the same `res://tests/**/test_*.gd` files. If you are using that plugin (Grok / MCP), its `test_run` tool is the same corpus. Opening a test script and pressing Play is **not** how these suites run — they are `RefCounted` scripts, not scenes.

## Adding a test

1. Create `tests/engine/test_engine_yourthing.gd`.
2. `@tool` + `extends McpTestSuite`.
3. Implement `suite_name()` and methods named `test_*`.
4. Use `assert_eq` / `assert_true` from `McpTestSuite`.
5. Do not name helpers `test_*.gd`.
