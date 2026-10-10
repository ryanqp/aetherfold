# Aetherfold — Full App Audit & Repair Checklist

Audit date: 2026-10-09. Repository: `ryanqp/aetherfold`, local branch `new-playmat` (commit `fcbc3fe`), **plus uncommitted working-tree changes** (10 modified files, 2 new test files — Oracle/engine work from the previous session; listed in §6). Unless a finding says otherwise, it applies to both the committed `HEAD` and the working tree.

No application file was modified. All runtime checks ran in scratch copies of the project with their own `user://` folder (`custom_user_dir_name`), so the real saved decks were not touched. The only file added to the repository is this report (untracked).

---

## Project health summary

| Question | Answer | Evidence |
|---|---|---|
| Overall condition | A deep, well-tested 1v1 rules engine with a working desktop table, deck import, and 2-player online play. **Not shippable to Android/iOS as configured**, and card-data and data-safety defects affect imported decks. | §1–§8 |
| Does it build? | **Desktop pack: yes** (a scratch `--export-pack` with Godot 4.7.2 succeeded). **Android/iOS: no preset exists**, so it cannot be built as configured. The exported pack also **contains no card catalog or card images** (AUDIT-001). | `/audit_export` pack test; `export_presets.cfg` absent (git-ignored) |
| Does it launch? | **Yes, headless** — `main_menu.tscn` and `table.tscn` each ran 900 frames under Godot 4.7.2 with **0 script errors**. I did not see it on screen (no visual or interactive check). | headless launch logs |
| Do automated tests pass? | **Yes.** Working tree: **524/524 in 46 suites** (Godot 4.7.2, `tools/run_tests.gd`). Committed `HEAD`: **507/507 in 45 suites**, matching GitHub CI run 37515649403 (507 passed). | §6 |
| Is core Commander gameplay functional? | **Yes, for 1v1** (you vs bot, host vs one guest). Two bot-vs-bot games with the *Tramplesaurus Rex* precon ran to a winner with 0 script errors and no stalls. However, **only 45.3% of a 7,957-card catalog sample is fully read** by the Oracle reader, and the unread text **fails silently** (AUDIT-007). Multi-face cards from the shipped catalog have **no rules at all** (AUDIT-003). | sim log, coverage tool |
| Does deck storage work? | **Yes, with data-loss risks.** Save/load works (round-trip test; 10 decks on disk). A deck named "Mono Red…" is **deleted at every launch** (AUDIT-004). Delete has no confirmation, and saves are non-atomic and fail silently. | probe, code |
| Does card scanning work? | **No — not implemented.** No camera, OCR, or recognition code exists anywhere in `scripts/` or `engine/`. | AUDIT-018 |
| Does real multiplayer work? | **Real ENet networking exists for exactly 2 players** (host plus one guest; LAN beacon or direct IP with UPnP). I could not test it across two machines. 3–4 player Commander is not supported, and there is no reconnect. | `scripts/net/game_net.gd`, AUDIT-016/017 |

**The five most important findings**
1. **AUDIT-001** — An exported build ships **without the 38,633-card catalog and all card art**. The data folder holds a `.gdignore`, and the code falls back to `D:/AetherfoldData`. On a phone the app would have no cards beyond the precon decklists.
2. **AUDIT-003** — **825 Commander-legal double-faced, split and adventure cards have no rules text** in the shipped catalog. Importing *Delver of Secrets* resolves to an **Art Series** collectible. This hits every imported deck that contains such a card.
3. **AUDIT-004** — Every launch **deletes any saved deck whose name starts with "Mono Red"** (a test-cleanup routine in production code; reproduced).
4. **AUDIT-007** — Card text the engine can't read **does nothing and tells the player nothing**. It is printed only to the Godot developer console.
5. **AUDIT-005 / AUDIT-006** — Deck import **freezes the app** (synchronous HTTP on the main thread; 2.9–4.2 s observed, up to 25 s per request), and **Archidekt imports silently drop real cards** (a live 100-card deck imported as 92).

**Biggest blockers to a usable release:** the mobile build and data packaging (AUDIT-001, -002), the correctness of card data for imported decks (AUDIT-003, -006, -012), data safety (AUDIT-004, -011, -013), a touch-friendly UI (AUDIT-019), and visible handling of unsupported cards (AUDIT-007).

---

## Architecture map (verified against the code)

```
 main_menu.tscn ─ scripts/ui/main_menu.gd ──┬─ Vs AI page ──► AppState.player_deck_id / rival_deck_id ─┐
   (autoloads: ScryfallCatalog, AppState,   ├─ Library: ImportOverlay ─► ImportPipeline               │
    GameNet, Music, Sfx, _mcp_game_helper)  │      importers (Moxfield/Archidekt/TappedOut/Deckstats/ │
                                            │      text) ─► ScryfallResolver (catalog ─► Scryfall API │
                                            │      /cards/collection ─► user://scryfall_card_cache)   │
                                            │      ─► CommanderValidator ─► DeckStore                  │
                                            │         (user://imported_decks/*.json)                  │
                                            ├─ PreconDecks.install(): res://data/precons ─► DeckStore │
                                            └─ Online page ─► GameNet lobby (ENet :27777, UDP beacon) │
                                                                                                      ▼
 table.tscn ─ scripts/table.gd (4,288 lines, USE_ENGINE := true)
     │  _start_from_app_state(): AppState.make_demo() ─► DeckCatalog ─► DemoSetup (CardDatabase from rows)
     ▼
 GameSession (engine/session/game_session.gd)  ── single source of truth on the host/solo
     │   bot: _ai_* + ai_blocks.gd        view: TableView.from_engine() ─► table.gd renders
     ▼
 RulesEngine (engine/engine.gd) ─ zones, stack, priority, turn, combat, mana, costs, targeting,
     triggers, replacement, layers (CR 613), SBA (CR 704), AbilityExecutor (+ CardEffects,
     KeywordEffects, KeywordActions, PreconEffects)
     ▲
 CardDatabase ◄─ CatalogSource.Memory (deck rows) ; abilities = 29 hand-written IR JSON files, else
                 OracleIr (5,018-line Oracle-text reader) ; KeywordDb/KeywordLines/KeywordRules

 Online: host runs GameSession ─► GameNet.broadcast_view(TableView.to_plain_for_remote) ─► guest
         renders the view only;  guest input ─► GameNet.send_action ─► host table.apply_net_action
         ─► session.as_seat(1, …) ─► RulesEngine (validated by the engine).

 Card art: ScryfallCatalog.texture_for() ─► <data_dir>/images/<id>_<kind>.jpg, else HTTPRequest
           download from cards.scryfall.io (one at a time).

 Legacy (still instantiated): scripts/match_state.gd (MatchState) + scripts/rival_ai.gd — the
 pre-engine prototype. Every `if USE_ENGINE … else` branch in table.gd is dead code because
 USE_ENGINE is a const true, but `_board()` still falls back to MatchState (AUDIT-021).
```

**Historical claims, checked:**
- `scripts/table.gd` has `const USE_ENGINE := true` — **true** (line 3).
- `GameSession → RulesEngine` is the live path — **true**. Table UI code makes no direct state writes; every game action goes through `GameSession`/`RulesEngine`.
- `match_state.gd` is unused — **partly false**. It is preloaded and instantiated by `table.gd` (lines 9, 40, 3836) and is the fallback board in `_board()` (AUDIT-021).
- Commit `198a916` — **exists** ("Move stack, priority, layers, and replacement out of engine.gd", 2026-09-12).
- Tests run via `godot --headless --path . -s res://tools/run_tests.gd` — **true**. They ran successfully here with Godot 4.7.2.

---

## 1. Critical blockers (P0)
- **AUDIT-001** — Exported builds contain no card catalog or card art; the app silently depends on a `D:` drive.
- **AUDIT-002** — No Android/iOS export configuration exists; the app cannot be built for its primary platform.

## 2. High-priority bugs (P1)
- **AUDIT-003** — Multi-face cards from the shipped catalog have no rules text; face-name lookups can hit Art Series rows.
- **AUDIT-004** — Every launch deletes user decks named "Mono Red…".
- **AUDIT-005** — Deck import blocks the main thread (freeze; risk of an Android "app not responding" kill).
- **AUDIT-006** — The Archidekt importer drops real cards and ignores the deck's own in-deck flags.
- **AUDIT-007** — Unsupported card text fails silently in play.
- **AUDIT-008** — Face-down permanents reveal their name and text.
- **AUDIT-009** — A privately peeked library top card is sent to the remote player.

## 3. Medium-priority bugs (P2)
AUDIT-010 (Menu "New game" ignores the chosen decks), -011 (Delete has no confirmation), -012 (unresolved cards become definition-less objects), -013 (non-atomic and silent-failure saves), -014 (unauthenticated join, room code not checked on direct IP), -015 (guest-supplied card text overrides the host's), -019 (touch/mobile UX), -020 (image cache and download behaviour), -023 (generated starter decks with invented filler cards), -024 (illegal decks playable without warning), -027 (bot turn cost and object leaks), -028 (test suite weaknesses).

## 4. Low-priority issues (P3)
AUDIT-021 (legacy MatchState path), -022 (hard-coded "Talrand"/"Krenko" labels), -025 (commander-pairing rule gaps), -029 (keyword status table inaccurate), -030 (editor AI addon shipped in exports), -031 (debug mode on in production), -032 (documentation drift), -033 (dead code), -034 (repository size and runtime downloads into the source tree), -035 (`quit()` and desktop-only settings on mobile), -036 (GameLog O(n) trimming).

## 5. Missing features
- **AUDIT-016** — No reconnect or match recovery.
- **AUDIT-017** — Only two seats; no 3–4 player Commander.
- **AUDIT-018** — Card scanning is not implemented.
- **AUDIT-026** — Deck management: edit, duplicate, and export are missing.
- **AUDIT-037** — No player-chosen combat damage assignment and no "divided as you choose" damage.
- Also missing (each named inside another item): an Android/iOS build pipeline (AUDIT-002); a deck-legality gate and explanation at match start (AUDIT-024).

---

## 6. Test failures and untested areas

**What I ran (all in scratch copies with an isolated `user://`):**

| Run | Tool | Result |
|---|---|---|
| Working tree, all suites | Godot 4.7.2 `tools/run_tests.gd -- --verbose` | **524 passed, 0 failed, 0 skipped**, 46 suites, 53 s |
| Committed `HEAD` (`git archive`) | same | **507 passed, 0 failed**, 45 suites |
| GitHub CI (latest `main` push) | `.github/workflows/tests.yml`, Godot 4.7.0 | success, 507 passed |
| Editor import | `--headless --editor --quit` | 0 script errors |
| Headless launch | main menu, table scene, 900 frames each | 0 script errors; leak warnings at exit (table: 32 resources, CanvasItem RIDs) |
| Export | scratch Windows preset, `--export-pack` | built; **catalog and images absent from the pack** |
| Bot-vs-bot | `tools/sim_games.gd`, *Tramplesaurus Rex*, 2 games, max 25 turns | both finished (turn 11 and turn 13), 0 script errors, no stalls; slowest turn 921 ms; **3,331 ObjectDB instances leaked at exit** |
| Reproduction probe | scratch `tools/audit_probe.gd` | reproduced AUDIT-004, -008, -009, -012; live Moxfield import OK (100 cards); live Archidekt import 92 of 100 cards (AUDIT-006) |
| Catalog coverage | `tools/catalog_coverage.gd --step=4` | 7,957 cards sampled, 3,607 fully read (**45.3%**), 5,171 unread lines |
| Saved-deck audit | `tools/deck_audit.gd` on the 10 saved decks | fully read: 69/69, 68/86, 75/88, 64/67, 58/74, 58/91, 50/69, 59/69, 87/87, 55/68 |

**Suites and test counts:** bug_report 5, engine_activation 21, engine_ai 5, engine_attacking 11, engine_blocking 11, engine_card_face 3, engine_card_reports 86, engine_cards 10, engine_combat 13, engine_commander 6, engine_conditions 4, engine_cr_keywords 27, engine_deck_legal 3, engine_demo 3, engine_import 23, engine_ir 2, engine_ir_batch 9, engine_keyword_audit 7, engine_keywords 16, engine_keywords_more 47, engine_krenko 2, engine_land 8, engine_layers 1, engine_mana 7, engine_menu 5, engine_mulligan 12, engine_new_cards 12, engine_no_nodes 2, engine_oracle_batch 15 *(uncommitted)*, engine_oracle_ir 25, engine_oracle_permanents 20, engine_play 4, engine_precon_keywords 26, engine_priority 2, engine_sba 2, engine_session 6, engine_stack 2, engine_state 5, engine_table_ux 24, engine_table_view 2, engine_targets 3, engine_triggers 1, engine_turn 5, engine_zones 9, net_address 4, online_session 8.

**Uncommitted working-tree changes covered by these runs:** `engine/abilities/ability_executor.gd`, `card_effects.gd`, `engine/cards/ir_loader.gd`, `oracle_ir.gd`, `token_catalog.gd`, `engine/engine.gd`, `engine/layers/layer_manager.gd`, `engine/targeting/query.gd`, `engine/triggers/trigger_manager.gd`, `tests/engine/test_engine_card_reports.gd`, plus the new `tests/engine/test_engine_oracle_batch.gd`.

**Untested critical paths (no automated test exists):**
- An exported or Android build (no preset).
- A real two-process network game: `test_online_session.gd` tests the session layer only; there are no ENet/RPC transport tests.
- The table and menu UI flows (`scripts/table.gd` and `main_menu.gd` are exercised only through helper functions).
- Image download and caching.
- Multi-face cards resolved from the lean catalog.
- Deck persistence across a real app restart.
- Interrupted or corrupt save files.
- Performance on mobile hardware.

**Thin coverage:** the dedicated suites for layers (1 test), triggers (1), stack (2), priority (2), and SBA (2) are small. These systems are exercised indirectly by the card suites.

**Tooling limitations I hit:**
- I could not test on an Android or iOS device, run an Android export (no preset; `java_sdk_path` is empty in the editor settings), or play a two-machine network game.
- I did not visually inspect the UI.
- Godot 4.4.1 (used earlier in this session) is wrong for this project: it fails on the 4.5+ `Logger` API used by the `godot_ai` addon. Use **4.7.x**.

---

## 7. Architecture and technical debt
- **One source of truth:** confirmed. Solo and host games run through `GameSession → RulesEngine`; the guest renders host views. There is no second simulation. The leftover prototype (`MatchState`) is still instantiated and is the `_board()` fallback (AUDIT-021).
- **Root cause behind AUDIT-001, -003, -034:** card data comes from a *lean, dev-machine-oriented* catalog (`data/scryfall/catalog.jsonl`, `.gdignore`d, multi-face text stripped, art and token rows mixed in) instead of a packaged, game-ready card store. Fixing the catalog pipeline once fixes all three.
- **Root cause behind AUDIT-004, -013, -028:** `DeckStore` is a thin, unguarded file writer shared by production code and tests on the same `user://` path.
- **Root cause behind AUDIT-008, -009, -014, -015:** the network layer trusts both sides. The host redacts by hand-picked fields (hand, hideaway) rather than by a visibility rule, and the host accepts the guest's deck data as truth.
- **Large files:** `oracle_ir.gd` (5,018 lines), `table.gd` (4,288), `engine.gd` (3,571), `ability_executor.gd` (2,673). Each is a single regex reader or a god object; changes there have repeatedly caused regressions in this project (see the previous sessions' fixes).

---

## 8. Repair checklist

### AUDIT-001 — Exported builds contain no card catalog or card art; runtime depends on `D:/AetherfoldData`
- **Priority:** P0
- **Status:** CONFIRMED
- **Category:** Cards
- **Evidence:** `data/scryfall/.gdignore` (empty file — Godot excludes the folder from import *and export*). `scripts/scryfall_catalog.gd` `data_dir()`: `ProjectSettings.globalize_path("res://data/scryfall")`, else `const DATA_DIR := "D:/AetherfoldData/scryfall"`. In a scratch pack export (include filter `*.json, *.jsonl, *.txt`), the pack contains `data/precons/01-multiverse-reforged.json` but **0** occurrences of `data/scryfall/catalog.jsonl` or `data/scryfall/images/`. Running that pack logged `Scryfall catalog loaded: 38633 cards from D:/AetherfoldData/scryfall/catalog.jsonl` — it only worked because this PC happens to have that folder.
- **Problem:** Any distributed build (Android, iOS, a friend's PC without `D:\AetherfoldData`) has no catalog: deck import cannot resolve cards offline, the Library Builder can't search, starter decks fall back to placeholder cards, and art can't be cached (the image path points at `D:`).
- **Expected behavior:** The packaged app carries (or downloads on first run into `user://`) a game-ready card catalog and writes art to `user://`.
- **Reproduction:** Remove or rename `D:\AetherfoldData`, export any preset, run the build → the menu logs "Catalog missing at D:/AetherfoldData/scryfall/catalog.jsonl".
- **Root cause:** A `.gdignore` used to keep the 42 MB JSONL out of the import step also removes it from exports; the path logic assumes a desktop dev layout.
- **Recommended repair:** Move the catalog to a format and location that exports (for example a compressed `.json.gz` read with `FileAccess.open_compressed`, or a Godot resource), read it via `res://` with `FileAccess` (not `globalize_path`), and add `*.jsonl`/`*.gz` to the preset's include filter. Put downloaded art under `user://card_art/`. Remove the `D:` fallback (keep only the env override for dev). Consider a first-run download of Scryfall bulk data into `user://` to keep the APK small.
- **Dependencies:** AUDIT-002 (a preset is needed to verify). Coordinate with AUDIT-003 (catalog format).
- **Regression tests:** Assert `data_dir()` never returns a drive-letter path. Assert the catalog loads from `res://` with `globalize_path` unavailable. Add a CI export-pack step that lists the pack contents and checks the catalog is inside.
- **Acceptance criteria:** An exported build on a machine without `D:\AetherfoldData` logs a loaded catalog with ≥38,000 cards, and downloaded art lands in `user://`.

### AUDIT-002 — No Android/iOS export configuration
- **Priority:** P0
- **Status:** FEATURE GAP
- **Category:** Other (Build)
- **Evidence:** No `export_presets.cfg` in the repository, and `.gitignore` lists `export_presets.cfg`. Editor settings: `export/android/java_sdk_path = ""`. Android and iOS export templates for 4.7.2 *are* installed (`editor_data/export_templates/4.7.2.stable`). No code sets Android permissions (INTERNET, ACCESS_NETWORK_STATE, CHANGE_WIFI_MULTICAST_STATE for the UDP LAN beacon).
- **Problem:** The Android-first app cannot be built for Android or iOS from the repository; the network permissions the app needs are not declared anywhere.
- **Expected behavior:** Versioned export presets for Android (and later iOS) with the required permissions, the include filters, and a signing setup documented outside the repository.
- **Reproduction:** `godot --headless --export-debug "Android" out.apk` → "invalid export preset name" (no presets).
- **Root cause:** Presets are git-ignored (they can hold keystore passwords), so none were ever committed.
- **Recommended repair:** Commit a preset without secrets (keystore paths and passwords via environment variables or `export_credentials.cfg`, which Godot keeps out of the preset). Enable INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, and CHANGE_WIFI_MULTICAST_STATE. Set orientation to landscape. Set the JDK path. Add an Android export step in CI (debug APK).
- **Dependencies:** None (first item to unblock device testing).
- **Regression tests:** A CI job that exports a debug APK and fails on errors.
- **Acceptance criteria:** A debug APK builds in CI and installs and launches on a physical Android device to the main menu.

### AUDIT-003 — Multi-face cards from the shipped catalog have no rules; face names can resolve to Art Series cards
- **Priority:** P1
- **Status:** CONFIRMED
- **Category:** Cards
- **Evidence:** `data/scryfall/catalog.jsonl`: **3,212 rows** have `"faces":["…"]` (names only) and `"oracle_text":""`; **825** of them are `commander_legal:true` (transform 401, modal_dfc 100, split 137, adventure 170, flip 26, meld 21, prototype 21 rows in total). `engine/cards/card_definition.gd:56–78` builds faces only when `faces[1] is Dictionary`. Scratch probe (`ScryfallResolver._from_catalog` → `CardDatabase.definition_for`):
  - "Delver of Secrets" → `layout=art_series cost='' text_len=0 abilities=0`
  - "Fire // Ice" → `cost='{1}{R} // {1}{U}' text_len=0 abilities=0`
  - "Bonecrusher Giant" → `text_len=0 abilities=0`
  - "Valki, God of Lies" → `art_series`

  `scripts/scryfall_catalog.gd` `_index_name(..., allow_replace=false)` indexes face names first-come, so non-game layouts can claim a real card's face name.
- **Problem:** Every imported deck (Moxfield, Archidekt, text, Builder) and every generated starter deck containing these cards gets blank cards: no abilities, no back face, the combined "A // B" cost, and possibly an Art Series object instead of the card. The bundled precons are *not* affected (their rows carry full face data from the API).
- **Expected behavior:** Each multi-face card has both faces with their cost, type, text, and P/T; casting picks a face or half; name lookups only ever return playable game cards.
- **Reproduction:** Import a text list containing `1 Delver of Secrets` → its definition has no text and an `art_series` layout.
- **Root cause:** `tools/fetch_scryfall.py` strips `card_faces` to names. The catalog also keeps non-game layouts (`art_series`, `token`, `double_faced_token`, stickers…).
- **Recommended repair:** Regenerate the catalog keeping `card_faces` (name, mana_cost, type_line, oracle_text, power, toughness, loyalty, image_uris). Drop non-game layouts from the name index. Prefer game layouts and exact names in `_name_score`. Add a one-time migration that re-resolves saved decks whose stored rows have string-only `faces` (saved decks embed rows at import time).
- **Dependencies:** AUDIT-001 (same catalog pipeline).
- **Regression tests:** Catalog-level tests — "Delver of Secrets", "Fire // Ice", "Bonecrusher Giant", and "Valki" resolve to the playable layout with two faces and non-empty text. Add an engine test that transforms Delver and casts Fire or Ice.
- **Acceptance criteria:** 0 Commander-legal rows with empty `oracle_text` *and* empty structured faces, and a probe over all 825 shows `back_face`/`other_half` set.

### AUDIT-004 — Every launch deletes user decks named "Mono Red…"
- **Priority:** P1
- **Status:** CONFIRMED
- **Category:** Decks
- **Evidence:** `engine/import/deck_store.gd` `purge_test_decks()` deletes every saved deck whose lower-cased name begins with `mono red`. It is called from `scripts/ui/main_menu.gd:62` (every launch) and `:826` (every Gallery refresh). Probe in an isolated `user://`: saved "Mono Red Burn" → `removed=1 still_exists=false`.
- **Problem:** Production code deletes real user data to clean up after tests.
- **Expected behavior:** User decks are never deleted without an explicit user action.
- **Reproduction:** Import or build a deck named "Mono Red Aggro", restart the app → it's gone.
- **Root cause:** The tests write to the real `user://imported_decks` (AUDIT-028), and this purge was added to clean up after them (T-010).
- **Recommended repair:** Delete the purge calls. Make tests use a separate store directory (inject `DeckStore.DIR` or a constructor argument). One-off: purge only records carrying an explicit `test_fixture: true` marker.
- **Dependencies:** AUDIT-028.
- **Regression tests:** "A deck named 'Mono Red Burn' survives `_ready()` of the main menu and a Gallery refresh."
- **Acceptance criteria:** No code path deletes a deck except the Gallery's Delete action (plus the documented retired-starter cleanup).

### AUDIT-005 — Deck import blocks the main thread
- **Priority:** P1
- **Status:** CONFIRMED (freeze); Android "not responding" kill is LIKELY (not tested on a device)
- **Category:** Decks
- **Evidence:** `scripts/import_overlay.gd:173` calls `ImportPipeline.run()` synchronously. `engine/import/deck_http.gd` `get_sync`/`post_sync` poll in loops with `OS.delay_msec` and a 20–25 s timeout. `ScryfallResolver._fetch_collection` adds `OS.delay_msec(550)` per failed batch. Measured in the scratch probe: Archidekt **4,188 ms** and Moxfield **2,907 ms** blocked per import on desktop broadband.
- **Problem:** The window freezes during every import; on slow or mobile networks it can freeze for tens of seconds, which Android treats as "app not responding" after ~5 s.
- **Expected behavior:** Import runs in the background with live progress and a Cancel button.
- **Reproduction:** Library → Import from URL → paste a Moxfield URL → the UI stops repainting until the import finishes.
- **Root cause:** Synchronous `HTTPClient` polling on the UI thread.
- **Recommended repair:** Run `ImportPipeline.run` on `WorkerThreadPool` (it touches no nodes except the catalog lookups — pass in a plain catalog reference), or rewrite it with `HTTPRequest` and `await`. Stream progress through `call_deferred`.
- **Dependencies:** None.
- **Regression tests:** A test that `ImportPipeline` runs to completion on a worker thread with a stubbed HTTP client. A UI test that the overlay stays responsive (a frame counter advances during import).
- **Acceptance criteria:** No frame longer than 100 ms during an import on desktop; a Cancel button works.

### AUDIT-006 — Archidekt importer drops real cards and ignores the deck's in-deck flags
- **Priority:** P1
- **Status:** CONFIRMED
- **Category:** Decks
- **Evidence:** `engine/import/importers/archidekt_importer.gd` `parse()` skips any card carrying a category named `maybeboard`, `sideboard`, `considering`, or **`tokens`**, and never reads the deck's `categories[].includedInDeck`. Live deck 22685587 ("Goblin Storm"): by Archidekt's primary-category rule it holds **100** cards; the importer kept **92** and dropped **15** in-deck cards (e.g. Krenko's Command, Siege-Gang Commander, Empty the Warrens, Krenko, Mob Boss, Swiftfoot Boots), while keeping some cards that are not in the deck.
- **Problem:** Imported Archidekt decks are wrong, and the validator then reports "add N cards".
- **Expected behavior:** A card is in the deck if and only if its primary (first) category has `includedInDeck: true`; quantities are kept.
- **Reproduction:** Import `https://archidekt.com/decks/22685587` → 92 cards.
- **Root cause:** Hard-coded category names instead of the deck's own category settings; "Tokens" is a common *user* tag for token-making cards.
- **Recommended repair:** Build a map from category name to `includedInDeck` from `json.categories`, use each card's first category, and treat `Commander` (or `isPremier`) as the commander.
- **Dependencies:** None.
- **Regression tests:** A fixture JSON with custom categories ("Tokens" included, "Tokens & Extras" excluded, multi-category cards) → the exact expected counts.
- **Acceptance criteria:** Deck 22685587 imports as 100 cards with Zada as commander.

### AUDIT-007 — Unsupported card text fails silently during play
- **Priority:** P1
- **Status:** CONFIRMED
- **Category:** Gameplay
- **Evidence:** `engine/session/game_session.gd:83–109` `_note_unread_cards()` prints "UNIMPLEMENTED_MECHANIC …" to the Godot Output panel only ("Not shown in History any more"). Only effects of kind `UNPARSED` write a History note (`ability_executor.gd:162`). Coverage: 45.3% of 7,957 sampled cards fully read (5,171 unread lines). In the 10 saved decks, 125 of 768 cards (16.3%) still have at least one unread line.
- **Problem:** A static, trigger, or replacement line the reader doesn't understand simply does nothing, and the player isn't told. This is what made cards seem "not working" in earlier sessions.
- **Expected behavior:** Players can see which cards have unsupported text (a badge on the card, the inspector, and a History note when such a card enters or resolves), and can apply it by hand where sensible.
- **Reproduction:** Play Rishkar, Peema Renegade (precon *Tramplesaurus Rex*) → its mana-ability grant never happens and there is no message.
- **Root cause:** A design decision to keep History clean.
- **Recommended repair:** Add an `unsupported` list to each card dict in `TableView._card_dict` from `db.unread_lines(def)` (cached per definition), show a small "!" badge and the lines in the inspector, and write one History note the first time each such card is cast or enters.
- **Dependencies:** None.
- **Regression tests:** A TableView test: a card with an unread line has `unsupported` non-empty; a History test: one note when it enters.
- **Acceptance criteria:** Every card with unread text is visibly marked on the table; the bug report already lists them.

### AUDIT-008 — Face-down permanents reveal their identity
- **Priority:** P1
- **Status:** CONFIRMED
- **Category:** Gameplay / Multiplayer
- **Evidence:** `engine/session/table_view.gd` `_card_dict()` sets `name`, `text`, `mana_cost`, and `cardId` from `obj.definition` even when `obj.face_down`; only the badge adds "face down". Probe: face-down card → `name_shown=Hidden Morph Creature text_shown=Morph {3} power=2`. These dicts go to the opponent's screen and over the network.
- **Problem:** Morph, manifest, disguise, cloak, and foretold or face-down exile reveal the hidden card (CR 708.2, 708.5).
- **Expected behavior:** For anyone but the controller, a face-down permanent shows as a nameless 2/2 with no text; its controller may see the real card.
- **Reproduction:** Cast a creature face down (morph) → the opponent's table, and the network payload, show its name.
- **Root cause:** Visibility is not modelled per viewer; the card dict is built once for both seats.
- **Recommended repair:** Build card dicts per viewing seat; for face-down objects not controlled by the viewer, emit `{name:"", text:"", face_down:true, power:"2", toughness:"2"}`.
- **Dependencies:** AUDIT-009 (shared per-viewer visibility).
- **Regression tests:** A TableView test with a face-down permanent viewed from each seat; a `to_plain_for_remote` test.
- **Acceptance criteria:** No face-down object's real name or text appears in the rival's view or in `to_plain_for_remote()` output.

### AUDIT-009 — A privately peeked library top card is sent to the remote player
- **Priority:** P1
- **Status:** CONFIRMED
- **Category:** Multiplayer
- **Evidence:** `TableView._revealed_top()` fills `library_top` when the player has "You may look at the top card of your library any time" (private) or "Play with the top card … revealed" (public). `to_plain_for_remote()` → `_redacted_player()` redacts only `hand` and hideaway exile. Probe: `library_top_sent=Secret Top Card` with `library_top_public=false`.
- **Problem:** The guest's client receives the host's private top card, so a modified client could read it.
- **Expected behavior:** Only public information (and the viewer's own private information) leaves the host.
- **Reproduction:** The host controls Bolas's Citadel or Vizier of the Menagerie → inspect the `receive_view` payload on the guest.
- **Root cause:** Redaction lists specific fields instead of whitelisting public ones.
- **Recommended repair:** In `_redacted_player`, drop `library_top` unless `library_top_public`. Long term, build the remote view through the same per-viewer builder as AUDIT-008.
- **Dependencies:** None.
- **Regression tests:** A `to_plain_for_remote` test for both private and public top cards.
- **Acceptance criteria:** A private top card is never present in the remote payload.

### AUDIT-010 — In-match Menu → "New game" ignores the chosen decks
- **Priority:** P2
- **Status:** CONFIRMED
- **Category:** Gameplay / UI
- **Evidence:** `scripts/table.gd:3827` `_on_new_game()` creates a new `GameSession` and calls `session.start_table_demo()` → `start_with_demo(null)` → `DemoSetup.table_demo()` (generated Krenko vs Talrand). Compare "Play again" (`_on_play_again`), which reloads the scene and uses `AppState`. The button is hidden in online matches (`menu_solo_nodes`).
- **Problem:** A player who picked, for example, *Calling All Angels* vs *Reign of Dragons* and chooses "New game" gets the generated starter decks instead.
- **Expected behavior:** "New game" restarts with the same deck selection.
- **Reproduction:** Vs AI → pick two precons → in-match Menu → New game → the commanders are Krenko and Talrand.
- **Root cause:** A leftover from the demo-only era.
- **Recommended repair:** Route `_on_new_game` through `_start_from_app_state()` (or `reload_current_scene()` as Play again does).
- **Dependencies:** None.
- **Regression tests:** A UI-level test: after `_on_new_game`, `session.engine.state.players[0]` commanders match `AppState.player_deck_id`.
- **Acceptance criteria:** New game keeps both chosen decks.

### AUDIT-011 — Deleting a deck has no confirmation or undo
- **Priority:** P2
- **Status:** CONFIRMED
- **Category:** Decks / UI
- **Evidence:** `scripts/ui/main_menu.gd:891–896` — the Gallery's "Delete" button calls `DeckStore.delete_path(path)` immediately.
- **Problem:** One mis-tap (likely on a phone) permanently deletes a 100-card deck.
- **Expected behavior:** A confirmation dialog, or a short undo window or trash folder.
- **Reproduction:** Library → Gallery → Delete.
- **Root cause:** Not designed.
- **Recommended repair:** A `ConfirmationDialog` naming the deck. Optionally, move the file to `user://imported_decks/.trash/` and restore it on Undo.
- **Dependencies:** None.
- **Regression tests:** Deleting goes through the confirmation; a cancelled confirmation leaves the file.
- **Acceptance criteria:** No single tap deletes a deck.

### AUDIT-012 — Unresolved card names become definition-less objects in play
- **Priority:** P2
- **Status:** CONFIRMED
- **Category:** Cards / Gameplay
- **Evidence:** `engine/session/demo_setup.gd` `_deal()` creates a library object with `definition = db.definition_for(name)`, which returns `null` for unknown names (`card_database.gd:20–28`). Probe: a deck with "Totally Not A Real Card" → `null_definition_objects=1`. The import overlay's "Ignore" button (`_on_ignore`) saves decks that still contain unresolved names; the validator treats unresolved cards as *warnings* only.
- **Problem:** Misspelled or unknown cards turn into blank, unplayable cards in hand (empty name), silently shrinking the playable deck.
- **Expected behavior:** Either block the match with a clear list of unresolved cards, or substitute a visible placeholder that explains itself.
- **Reproduction:** Import a text list with a typo, choose Ignore, start Vs AI.
- **Root cause:** There is no gate between "saved" and "playable".
- **Recommended repair:** Re-resolve at match start; if any card is unresolved, show the list and let the player fix or remove the cards; never create objects with a null definition.
- **Dependencies:** AUDIT-003, AUDIT-024.
- **Regression tests:** `DemoSetup.apply` with an unknown card → error result or placeholder definition, never null.
- **Acceptance criteria:** No `GameObject` with `definition == null` can be created by deck setup.

### AUDIT-013 — Saves are non-atomic and failures are ignored
- **Priority:** P2
- **Status:** CONFIRMED (code); interrupted-write corruption not reproduced
- **Category:** Decks
- **Evidence:** `engine/import/deck_store.gd` `save`, `save_record`, and `rename` open the final path with `FileAccess.WRITE` and write in place. `scripts/import_overlay.gd` `_commit()` and `main_menu.gd` `_on_save_builder()` ignore the `""` failure return and navigate away as if saved. `list_decks()` silently skips unparsable files. `AppState._save_profile` uses `ConfigFile.save` in place.
- **Problem:** A crash or kill during a save (common on Android) corrupts the deck, which then silently disappears from the lists; a failed save shows no error.
- **Expected behavior:** Write to a temporary file then rename; report failures to the user; list unreadable files as "damaged" instead of hiding them.
- **Reproduction:** Not reproduced (needs fault injection). The code path is clear.
- **Root cause:** Minimal file layer.
- **Recommended repair:** `_atomic_write(path, text)`: write `path + ".tmp"`, `flush`, `DirAccess.rename_absolute`. Check every return. Add a "damaged decks" section with a delete option.
- **Dependencies:** None.
- **Regression tests:** Simulate a failed open (read-only dir) → error surfaced. A corrupt JSON file is listed as damaged.
- **Acceptance criteria:** No code path writes deck JSON directly to its final name; every failure is visible.

### AUDIT-014 — Online join is unauthenticated; the room code isn't checked on direct-IP joins
- **Priority:** P2
- **Status:** CONFIRMED (code)
- **Category:** Multiplayer
- **Evidence:** `scripts/net/game_net.gd`: `join_room(code, ip)` with an IP calls `_connect_to(ip)` directly; the host's `_on_peer_connected`/`announce_version` check only the protocol version, never the room code. `host_room()` opens UDP 27777 on the router via UPnP. `announce_profile(player_name, deck_name, rec)` accepts an unbounded `rec`.
- **Problem:** Anyone who can reach the host's public IP and port can take the guest seat or flood the lobby with a large record; the room code is cosmetic outside LAN discovery.
- **Expected behavior:** The host admits only peers presenting the room code (or a pairing token), and payload sizes are bounded.
- **Reproduction:** Not reproduced (needs two machines); the code path is clear.
- **Root cause:** The code was only ever used for the LAN beacon filter.
- **Recommended repair:** Have the client send the code with `announce_version`, disconnect on a mismatch, cap the `rec` size and card count, and reject malformed records.
- **Dependencies:** None.
- **Regression tests:** A unit test of the admit/reject logic with a wrong code; an oversize-record rejection.
- **Acceptance criteria:** A peer with the wrong code is disconnected before being seated.

### AUDIT-015 — The guest's card data is trusted and overrides the host's
- **Priority:** P2
- **Status:** CONFIRMED (code)
- **Category:** Multiplayer / Cards
- **Evidence:** `engine/import/deck_catalog.gd` `_side_of_rec()` uses `rec.cards` rows exactly as sent by the guest. `_pair_of_sides()` adds the host rows, then the guest rows, into one `CatalogSource.Memory`, whose `add()` overwrites by name (`catalog_source.gd:18–26`).
- **Problem:** A guest can send altered Oracle text or P/T, and for any card both players use, the guest's version also becomes the host's card.
- **Expected behavior:** The host resolves both decks' card names against its own catalog; remote rows are only a fallback for cards the host doesn't know, flagged as such.
- **Reproduction:** Not reproduced (needs a modified client).
- **Root cause:** Decks carry their rows for offline robustness, and nothing re-validates them.
- **Recommended repair:** On the host, re-resolve remote deck names through `ScryfallResolver` (the catalog first); keep the two seats' rows separate or prefer the host's.
- **Dependencies:** AUDIT-001, AUDIT-003 (the host needs a complete catalog).
- **Regression tests:** A remote rec with modified text for a card the host knows → the host's text is used.
- **Acceptance criteria:** No remote-supplied text replaces a host catalog card.

### AUDIT-016 — No reconnect or match recovery
- **Priority:** P2
- **Status:** FEATURE GAP
- **Category:** Multiplayer
- **Evidence:** `game_net.gd` `_on_peer_disconnected` removes the guest from `_lobby`; `table.gd` `_on_peer_left` shows "MATCH ENDED". No rejoin path exists, and no save or restore of a match.
- **Problem:** A brief Wi-Fi drop (very common on phones) ends the game permanently.
- **Expected behavior:** The guest can rejoin the same seat within a grace period, and the host resends the full view.
- **Reproduction:** Disconnect the guest's network mid-match.
- **Root cause:** Not designed.
- **Recommended repair:** Keep the seat reserved for N minutes keyed by a session token; on rejoin, re-seat and `broadcast_view` with the hash reset. Optionally serialize `GameState` for host restarts.
- **Dependencies:** AUDIT-014 (the token).
- **Regression tests:** A session-level test: seat reserved, rejoin with the token, view resent.
- **Acceptance criteria:** A guest who drops for under 2 minutes resumes the same match.

### AUDIT-017 — Only two seats: no 3–4 player Commander
- **Priority:** P2
- **Status:** FEATURE GAP
- **Category:** Multiplayer / UI
- **Evidence:** `game_net.gd:22` `MAX_TOTAL_PLAYERS := 2`; `broadcast_view` comments "until #19/#20 add real per-seat routing"; `table.gd` draws two sides (`you`/`rival`); `GameSession` uses `FormatRules.commander_1v1_table()`. The engine itself supports 4 players (`FormatRules.commander_4p`, `Fixtures.empty_engine_4p`). `docs/roadmap.md` says "LAN room for up to six players" (stale).
- **Problem:** Commander's normal 3–4 player game isn't possible.
- **Expected behavior:** 3–4 seats with per-seat views and turn order.
- **Reproduction:** n/a.
- **Root cause:** The UI and network were built 1v1-first.
- **Recommended repair:** Per-seat `TableView` (also fixes AUDIT-008/009), routing views by peer to seat, an N-opponent table layout, and multiplayer attack targets (the engine already chooses a defender).
- **Dependencies:** AUDIT-008, -009, -014, -016.
- **Regression tests:** A 4-seat session test; network routing tests.
- **Acceptance criteria:** Four players on four devices can finish a game.

### AUDIT-018 — Card scanning is not implemented
- **Priority:** P2
- **Status:** FEATURE GAP
- **Category:** Scanning
- **Evidence:** Searching `scripts/` and `engine/` for camera, CameraServer, OCR, scan, photo, or recognize finds no scanning code. `CLAUDE.md`: "No photo-to-card scanning yet." No accuracy claims exist in the code.
- **Problem:** The project goal (about 10, later 50, cards per photo) has no implementation.
- **Expected behavior:** A camera or photo import that detects cards, matches them to Scryfall records, and lets the user correct matches before adding them to a deck.
- **Reproduction:** n/a.
- **Root cause:** Not started.
- **Recommended repair:** Prototype outside Godot first: card-rectangle detection, then name-line OCR or an image hash against Scryfall art crops, then fuzzy matching against the catalog, then a review UI. Godot's `CameraServer` support on Android is limited, so plan for a native plugin or a platform image picker. 50 cards per photo needs high-resolution input and per-card crops of at least ~150 px tall; treat it as a research goal.
- **Dependencies:** AUDIT-001, AUDIT-003 (a reliable catalog), AUDIT-002 (Android build).
- **Regression tests:** A fixed photo set with ground-truth card lists; precision and recall measured per release.
- **Acceptance criteria:** At least 95% correct identification on 10-card photos in good light, and every uncertain match shown for review.

### AUDIT-019 — Core table interactions assume a mouse, a keyboard, and a large screen
- **Priority:** P2
- **Status:** LIKELY (code); not tested on a device
- **Category:** UI
- **Evidence:** `scripts/table.gd`:
  - Attacking uses a left **double-click** or a **right-click** menu (`_on_chip_input` at 4054, which also says "right-click one and choose Attack").
  - Card enlargement and help rely on hover and `tooltip_text` (30 tooltips in `table.gd`).
  - Shortcuts are keyboard keys (Space, Enter, F8, F3, `_unhandled_input`).
  - Board chips are `48×68` at a 1600×900 base (`BOARD_CHIP`), with `stretch/aspect="expand"`.
- **Problem:** On Android there is no hover, no right-click, and no keyboard; the board chips render at roughly 20–25 dp, well under the 48 dp touch-target guidance.
- **Expected behavior:** Every action is reachable by tap or long-press with targets of at least 48 dp; card zoom works on long-press.
- **Reproduction:** Run on a phone, or with "Emulate touch from mouse" and no right-click.
- **Root cause:** A desktop-first UI.
- **Recommended repair:** Long-press for the card menu and zoom; an explicit Attack-mode toggle with single taps; larger chip sizes on small screens (a scale factor from `DisplayServer.screen_get_dpi()`); on-screen buttons for the keyboard shortcuts.
- **Dependencies:** AUDIT-002 (device build).
- **Regression tests:** A table UX test with touch events only (InputEventScreenTouch) covering cast, attack, block, the card menu, and zoom.
- **Acceptance criteria:** A full game is playable on a phone with touch only.

### AUDIT-020 — Card-art cache: source-tree writes, unbounded memory, repeated failed downloads
- **Priority:** P2
- **Status:** CONFIRMED (source-tree writes, unbounded cache, re-queue in code); memory impact UNVERIFIED
- **Category:** Performance
- **Evidence:** `scripts/scryfall_catalog.gd`:
  - `image_dir()` = `<data_dir>/images`, which during development is the project's own `data/scryfall/images`. 178 untracked downloaded images are in `git status` now.
  - `_textures` is never evicted.
  - After a failed download, the next `texture_for()` re-queues the same URL (only queued items are de-duplicated).
  - `texture_for()` loads JPEGs from disk synchronously on the main thread.
- **Problem:** Offline play repeats failed requests on every refresh; memory grows with every card ever shown (a full-art `normal` texture is about 1.3 MB in RGBA); the repository gets polluted; first display of art stutters.
- **Expected behavior:** Art cached in `user://`, an LRU-bounded texture cache, failure back-off, and threaded loading.
- **Reproduction:** Go offline and open a match → the HTTP queue cycles; watch memory over several matches.
- **Root cause:** A dev-machine design.
- **Recommended repair:** A `user://card_art` cache; an LRU of about 200 textures; a negative cache with a timestamp; `ResourceLoader.load_threaded_request` or `WorkerThreadPool` decoding.
- **Dependencies:** AUDIT-001.
- **Regression tests:** A failed URL isn't requested again within N minutes; the cache stays at or under its limit.
- **Acceptance criteria:** No writes under `res://` at runtime; texture memory bounded.

### AUDIT-021 — The legacy prototype path is still live code
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** Architecture
- **Evidence:** `scripts/table.gd` preloads `match_state.gd` and `rival_ai.gd` and does `var state = MatchStateScript.new()`. `_board()` returns `state` when there is no session view (for example a guest before the first host view). `_paint_turn_border()` reads `state.active_is_you` in engine mode. Every `else` branch of `if USE_ENGINE` (lines 154–171, 1232, 1962, 2219, 2543, 2606, 2714, 3836) is unreachable. `tests/engine/test_engine_ai.gd` still tests `MatchState` and `RivalAI`.
- **Problem:** Dead code that can briefly display prototype "Krenko vs Talrand" data and confuses maintenance.
- **Expected behavior:** One board model.
- **Reproduction:** A guest's table before the first `receive_view` renders MatchState data (LIKELY; not observed).
- **Root cause:** Incremental migration (see `docs/migration-status.md`).
- **Recommended repair:** Remove `USE_ENGINE`, MatchState, RivalAI, and their test; make `_board()` return an empty `TableView`.
- **Dependencies:** None.
- **Regression tests:** The existing suites; a guest table with no view shows a "Waiting for host…" state.
- **Acceptance criteria:** `match_state.gd` and `rival_ai.gd` deleted; no `USE_ENGINE` references remain.

### AUDIT-022 — Hard-coded "Talrand" and "Krenko" labels in engine-mode UI
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** UI
- **Evidence:** `scripts/table.gd` line 634 (`_life_block("You", "Krenko")` / `("Rival", "Talrand")`), line 1877 (`rival_title_label.text = "Talrand"` for every non-online match), lines 2603 and 2621 ("Talrand lost %d life."), lines 3394 and 3406 (coin flip "Talrand goes first"), line 3846. `scripts/ui/main_menu.gd:273`.
- **Problem:** The rival is called Talrand whatever deck the bot plays.
- **Expected behavior:** Use the seat's player or commander name from the view.
- **Reproduction:** Vs AI with any precon as the bot deck → the header shows "Talrand".
- **Root cause:** Leftovers from the demo.
- **Recommended repair:** Replace them with `b.rival.name`.
- **Dependencies:** None.
- **Regression tests:** A table UX test that the rival title equals the bot deck's name.
- **Acceptance criteria:** No literal "Talrand" or "Krenko" in `table.gd` outside the builtin deck definitions.

### AUDIT-023 — Built-in starter decks are random and padded with invented cards
- **Priority:** P2
- **Status:** CONFIRMED
- **Category:** Decks / Cards
- **Evidence:** `engine/session/demo_setup.gd` `from_scryfall()` fills Krenko and Talrand with a random 73/70 commander-legal cards from the catalog (time-based seed via `DeckCatalog._builtin_pair`) and pads them to 99 with **"Goblin Volunteer NN"** / **"Merfolk Volunteer NN"**, which are not real cards. `_build_krenko()`/`_build_talrand()` (offline) use 68/67 such fillers. These decks are listed as "Starters" in Vs AI.
- **Problem:** Test data presented as playable decks: different every game, not real Commander decks, and containing made-up cards.
- **Expected behavior:** Starters are fixed, real 100-card lists (like the precons), or are removed.
- **Reproduction:** Vs AI → Krenko (starter) → the library contains "Goblin Volunteer" cards.
- **Root cause:** An early demo scaffold.
- **Recommended repair:** Replace them with two real decklists shipped like `data/precons`, or drop the builtins now that eight precons ship.
- **Dependencies:** None.
- **Regression tests:** The builtin decks validate as legal Commander decks with no unknown names.
- **Acceptance criteria:** No "Volunteer" placeholder can reach a game.

### AUDIT-024 — Illegal or incomplete decks are playable without warning
- **Priority:** P2
- **Status:** CONFIRMED (code)
- **Category:** Decks / Gameplay
- **Evidence:** `DeckCatalog.all_choices()` lists every stored record regardless of `validation.ok`. `_on_start_vs()` doesn't check legality. `_on_save_builder()` saves invalid Builder decks and jumps to the Gallery without showing the errors. The Gallery card shows only "N cards". `DeckCatalog._side()` silently falls back to Krenko if a saved deck file is missing.
- **Problem:** The player isn't told a deck is illegal (wrong size, colour identity, duplicates) before or after starting; a deleted deck silently becomes Krenko.
- **Expected behavior:** A validation badge in the lists, a warning or confirmation before starting with an illegal deck, and a clear error if the deck file is gone.
- **Reproduction:** Builder → a commander plus 10 cards → Save → Vs AI → it starts with a 10-card library.
- **Root cause:** Validation is shown only in the import preview.
- **Recommended repair:** Store and refresh `validation` and show it in the Gallery and Vs lists. Use a start gate with "Play anyway" for casual games, and an error instead of the fallback.
- **Dependencies:** AUDIT-012.
- **Regression tests:** `_side()` with a missing path returns an error; the list shows an invalid badge.
- **Acceptance criteria:** Every deck in a list shows legal or illegal with its reasons.

### AUDIT-025 — Commander pairing and Builder rule gaps
- **Priority:** P3
- **Status:** CONFIRMED (code)
- **Category:** Decks
- **Evidence:** `engine/import/commander_validator.gd`:
  - `_pair_legal()` accepts a Background with *any* commander-capable creature (CR 702.124k requires "Choose a Background").
  - `_has_partner()` treats any text containing "partner" (Partner—X variants, "Friends forever" missing) as universal Partner.
  - Doctor's companion is not handled.
  - `main_menu.gd` `_on_cmd_search()` offers any Legendary or Background card without checking `commander_legal`.
- **Problem:** Some illegal pairs validate and some legal ones don't.
- **Expected behavior:** Follow CR 702.124 variants exactly.
- **Reproduction:** Validate a Background plus a creature without "Choose a Background" → reported legal.
- **Root cause:** Simplified rules.
- **Recommended repair:** Parse the partner variants from keywords and Oracle text; require "Choose a Background"; filter the Builder search by `commander_legal`.
- **Dependencies:** None.
- **Regression tests:** A table of legal and illegal pairs.
- **Acceptance criteria:** All pairing tests pass.

### AUDIT-026 — Deck management features missing: edit, duplicate, export
- **Priority:** P3
- **Status:** FEATURE GAP
- **Category:** Decks
- **Evidence:** The Gallery (`main_menu.gd:838–900`) offers rename (committed only on Enter via `text_submitted`), Vs AI, and Delete. The Builder only creates new decks. There is no export or share.
- **Problem:** A saved deck can't be changed or copied, and renaming is lost if the field loses focus.
- **Expected behavior:** Edit in the Builder, duplicate, export as a text list, and rename on focus loss.
- **Reproduction:** n/a.
- **Root cause:** Not built.
- **Recommended repair:** Load a record into the Builder; a "Save as copy" option; export via `DisplayServer.clipboard_set` of a text list.
- **Dependencies:** AUDIT-013.
- **Regression tests:** Round-trip edit and export.
- **Acceptance criteria:** A user can modify, duplicate, and export any saved deck.

### AUDIT-027 — Bot turn cost grows with the board; objects leak across games
- **Priority:** P2
- **Status:** LIKELY (cost measured on desktop; mobile not measured); leak CONFIRMED at exit
- **Category:** Performance
- **Evidence:** `tools/sim_games.gd` (2 games, *Tramplesaurus Rex*): per-turn time rose from 69 ms (turn 1) to 831–921 ms (turns 9–11, 19–20 permanents), dominated by `bot legal_actions` and `engine.submit`. Godot reported "**3331 ObjectDB instances were leaked at exit**" after two games.
- **Problem:** Phone CPUs are several times slower, so late-game bot turns could take seconds. Leaked objects (likely RefCounted cycles between engine, state, and objects) accumulate over a session of several matches.
- **Expected behavior:** A bot turn under 300 ms on a mid-range phone; no growth in object count between matches.
- **Reproduction:** Run the command above; for the leak, run with `--verbose`.
- **Root cause:** `legal_actions` re-enumerates everything per decision; the cycles are unknown.
- **Recommended repair:** Profile with `--verbose` to find the leaked classes; break cycles (`weakref` for back-references, an explicit `engine.dispose()` at match end). Cache `legal_actions` per state version for the bot.
- **Dependencies:** AUDIT-002 (device measurement).
- **Regression tests:** A sim test asserting `Performance.OBJECT_COUNT` returns to baseline after a game.
- **Acceptance criteria:** Object count stable across 5 sim games; turn time budget met on the target device.

### AUDIT-028 — Test-suite weaknesses: shared real user data, network-dependent tests that can't fail
- **Priority:** P2
- **Status:** CONFIRMED
- **Category:** Testing
- **Evidence:**
  - `tests/engine/test_engine_import.gd` (`test_saved_deck_roundtrip`, `test_deck_store_finds_by_source_key…`, `test_precon_install_replaces_retired_starters`), `test_engine_menu.gd` `test_store_rename_delete`, and `test_bug_report.gd` write to the same `user://` as the app. Running them from the project folder writes into the player's real deck folder; a `bug_reports_test` folder from earlier runs is in the real user folder now.
  - `test_live_archidekt_if_network` and `test_live_moxfield_if_network` **pass when the import fails** (they only assert an error string exists), so they would not have caught AUDIT-006.
  - No ENet transport test; no UI end-to-end test.
- **Problem:** Tests can damage user data (the root of AUDIT-004), and import tests give false confidence.
- **Expected behavior:** Tests use an isolated store; network tests are separated and assert real content when they run.
- **Reproduction:** Run the suites from the project; list `%APPDATA%/Godot/app_userdata/Aetherfold/`.
- **Root cause:** `DeckStore.DIR` is a constant.
- **Recommended repair:** An injectable store directory (`DeckStore.new(dir)`) defaulting to `user://imported_decks`; tests use `user://test_tmp/<suite>`, cleaned up in `suite_teardown`. Mark live tests `@network` and skip them by default; when run, assert card counts. Add saved Archidekt and Moxfield JSON fixtures.
- **Dependencies:** None.
- **Regression tests:** —
- **Acceptance criteria:** A test run leaves the real `user://` byte-identical.

### AUDIT-029 — The keyword status table misstates some keywords
- **Priority:** P3
- **Status:** CONFIRMED (code)
- **Category:** Cards
- **Evidence:** `engine/cards/keyword_db.gd`: `ascend` is `NONE` ("has no effect the engine needs"), yet city's blessing matters. The reader approximates it per check as "ten permanents" (`oracle_ir.gd:271`, `:1184`), but the blessing is permanent once gained (CR 702.131c). The file documents a `MISSING` status that is never used (139 ENFORCED, 19 NONE).
- **Problem:** Status labels overstate support, and city's blessing is lost when permanents drop below ten.
- **Expected behavior:** Accurate statuses; a city's blessing designation stored on `PlayerState`.
- **Reproduction:** Get to ten permanents, sacrifice one → ascend effects turn off.
- **Root cause:** Approximation.
- **Recommended repair:** Add `citys_blessing: bool` to `PlayerState`, set by an SBA-style check, and mark ascend ENFORCED.
- **Dependencies:** None.
- **Regression tests:** The blessing persists after dropping below ten.
- **Acceptance criteria:** The keyword DB's statuses match behaviour, verified by `test_engine_keyword_audit`.

### AUDIT-030 — The editor AI addon ships inside exported builds
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** Other (Security / Build)
- **Evidence:** `project.godot` autoload `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"`. The scratch export pack contains `addons/godot_ai/**/*.gdc` (for example `addons/godot_ai/testing/script_error_capture.gdc`). The helper supports in-game evaluation and screenshots over the debugger channel (inactive without a debugger, per its own comments).
- **Problem:** Dev-only code and an always-on logger in production; larger package; attack surface if a debug build is distributed.
- **Expected behavior:** Editor tooling excluded from exports.
- **Reproduction:** Export → inspect the pack.
- **Root cause:** The plugin registers a project autoload.
- **Recommended repair:** Add `addons/godot_ai/*` to the preset's exclude filter, and register the autoload only for editor runs (or guard `_ready()` with `OS.has_feature("editor")`).
- **Dependencies:** AUDIT-002.
- **Regression tests:** A CI pack-content check.
- **Acceptance criteria:** No `addons/godot_ai` files in release packs.

### AUDIT-031 — Debug mode is on in production
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** Other
- **Evidence:** `scripts/table.gd:8` `const DEBUG_MATCH := true` → `session.debug_enabled`; F3 toggles a debug overlay (`_unhandled_input`).
- **Problem:** Extra logging cost and a developer overlay available to players.
- **Expected behavior:** Debug on only in debug builds.
- **Reproduction:** Press F3 in a match.
- **Root cause:** A constant.
- **Recommended repair:** `DEBUG_MATCH = OS.is_debug_build()`.
- **Dependencies:** None.
- **Regression tests:** —
- **Acceptance criteria:** Release builds produce no debug lines and no overlay.

### AUDIT-032 — Documentation drift
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** Other
- **Evidence:**
  - `CLAUDE.md` says "there is no target picker yet", but `GameSession._open_target_prompt` exists.
  - `CLAUDE.md` says unread lines "are listed in History", but they go to the Output panel only (AUDIT-007).
  - `docs/roadmap.md` says "LAN room for up to six players", but `MAX_TOTAL_PLAYERS := 2`.
  - `CLAUDE.md` says "the 8 precons: 224 of 549 cards fully read", but the current audit gives different numbers (§6).
- **Problem:** Contributors and AI assistants act on wrong facts.
- **Expected behavior:** The docs match the code.
- **Reproduction:** n/a.
- **Root cause:** No doc-update step.
- **Recommended repair:** Update them; add a "docs touched?" item to the PR template.
- **Dependencies:** After the related fixes.
- **Regression tests:** —
- **Acceptance criteria:** Each listed statement corrected.

### AUDIT-033 — Dead code
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** Architecture
- **Evidence:**
  - `engine/import/edhrec_decks.gd` (322 lines, referenced only by itself).
  - `engine/import/moxfield_starters.gd` ("Retired… safe to delete").
  - `engine/game_view.gd` ("Filled in later PRs" stub).
  - `engine/costs/restriction.gd` (no references).
  - `scenes/playmat_demo.tscn` plus `scripts/playmat/playmat_demo.gd` (dev scene).
  - The MatchState and RivalAI files covered by AUDIT-021.
- **Problem:** Maintenance noise; these files ship in exports.
- **Expected behavior:** Removed, or moved to `tools/`.
- **Reproduction:** grep for references.
- **Root cause:** Retired features.
- **Recommended repair:** Delete them after confirming no data files reference them.
- **Dependencies:** AUDIT-021.
- **Regression tests:** The full suite.
- **Acceptance criteria:** The files are gone and tests are green.

### AUDIT-034 — Repository size and runtime downloads into the source tree
- **Priority:** P3
- **Status:** CONFIRMED
- **Category:** Other
- **Evidence:** 693 card images and the 42 MB `catalog.jsonl` are tracked (`data/` is 92 MB); 178 untracked images appeared from runtime downloads (AUDIT-020).
- **Problem:** Slow clones and accidental commits of runtime data.
- **Expected behavior:** Generated or downloaded data outside git (or in Git LFS), with runtime caches in `user://`.
- **Reproduction:** `git status`.
- **Root cause:** Shipping art for online parity (commit `baa22db`).
- **Recommended repair:** After AUDIT-001 and -020: LFS or a release asset for the catalog; `.gitignore` `data/scryfall/images/`.
- **Dependencies:** AUDIT-001, AUDIT-020.
- **Regression tests:** —
- **Acceptance criteria:** A runtime session leaves `git status` clean.

### AUDIT-035 — `quit()` and desktop-only settings on mobile
- **Priority:** P3
- **Status:** CONFIRMED (code); impact UNVERIFIED
- **Category:** UI
- **Evidence:** `main_menu.gd:1098` Exit calls `get_tree().quit()` (Apple discourages programmatic quitting); "Toggle fullscreen" (`_toggle_fullscreen`) is meaningless on phones; `project.godot` sets `rendering_device/driver.windows="d3d12"` only (fine) and a 1600×900 desktop window.
- **Problem:** Desktop assumptions in the mobile UI.
- **Expected behavior:** Hide Exit and Fullscreen on mobile (`OS.has_feature("mobile")`).
- **Reproduction:** n/a.
- **Root cause:** Desktop-first.
- **Recommended repair:** Feature-gate both buttons.
- **Dependencies:** AUDIT-002.
- **Regression tests:** —
- **Acceptance criteria:** Neither button appears on Android or iOS.

### AUDIT-036 — The game log trims and scans in O(n)
- **Priority:** P3
- **Status:** LIKELY
- **Category:** Performance
- **Evidence:** `engine/game_log.gd`: `events.remove_at(0)` once over `CAP := 10000` (each append shifts ~10k entries), and `since(after_seq)` scans all events linearly.
- **Problem:** Late, long games pay O(10k) per event appended and per `since` call.
- **Expected behavior:** O(1) append and trim.
- **Reproduction:** Not measured separately (part of the AUDIT-027 timings).
- **Root cause:** Array used as a queue.
- **Recommended repair:** A ring buffer with a start index; `since` via binary search on `seq`.
- **Dependencies:** None.
- **Regression tests:** A GameLog unit test at the cap.
- **Acceptance criteria:** Append time constant at the cap.

### AUDIT-037 — Combat damage assignment and "divided as you choose" are automatic or unsupported
- **Priority:** P2
- **Status:** FEATURE GAP
- **Category:** Gameplay
- **Evidence:** `engine/engine.gd:1407` and `:1521–1522`: "Both are assigned automatically: damage goes where it kills nothing if it can." `CLAUDE.md`: "Combat damage assignment is automatic (no player-chosen order or split)." "~ deals X damage divided as you choose among any number of target creatures" is in the unread list (for example Monstrous Onslaught in the sim log).
- **Problem:** CR 510.1c–d (the attacking player orders and divides damage among blockers) and divided-damage spells can't be played as written.
- **Expected behavior:** The attacker chooses the damage division (with the lethal-damage ordering rule); divided damage asks for the split at casting (CR 601.2d).
- **Reproduction:** Attack into two blockers → the split is chosen for you.
- **Root cause:** No UI for multi-value choices.
- **Recommended repair:** A `ChoiceDialog` variant for distributing N among targets; engine actions `ASSIGN_COMBAT_DAMAGE` and `DIVIDE_DAMAGE`.
- **Dependencies:** AUDIT-019 (touch-friendly input).
- **Regression tests:** Double-block split; trample with an assigned order; Arc Lightning-style division.
- **Acceptance criteria:** The player chooses every damage split the rules give them.

---

## 9. Recommended repair order

| Stage | Goal | AUDIT-IDs |
|---|---|---|
| 1 | Prevent crashes and protect existing data | **004**, 028 (isolate tests first so 004's fix can be verified), 011, 013, 012 |
| 2 | Reliable build and test baseline | **002**, **001**, 030, 031, plus a CI export step |
| 3 | One source of truth, remove the conflicting path | 021, 033, 022, 010 |
| 4 | Card data, card identity, deck persistence | **003**, **006**, 024, 023, 025, 026, 020, 034 |
| 5 | Core Commander rules and game state | **008**, **009** (per-viewer visibility), 037, 029 |
| 6 | Card abilities and keywords | **007** (make gaps visible first), then continue Oracle coverage against the saved decks (§6 numbers) |
| 7 | Scanning and Scryfall integration | 005 (async import), 018 (scanning prototype) |
| 8 | Multiplayer | 014, 015, 016, 017 |
| 9 | UI, performance, mobile | **019**, 027, 035, 036 |
| 10 | Regression and release validation | Re-run §6, device tests, the §10 checklists |

I moved AUDIT-005 (async import) into stage 7 alongside the Scryfall work. If phone testing starts early, move it to stage 2, because it can kill the app on Android.

---

## 10. Release readiness

**Local development testing (desktop)** — *essential*
- [ ] `tools/run_tests.gd` green on Godot 4.7.x, and tests no longer touch the real `user://` (AUDIT-028).
- [ ] AUDIT-004 fixed (no automatic deck deletion).
- [x] Headless launch of the menu and table with 0 script errors (verified 2026-10-09).

**Android testing** — *essential*
- [ ] A committed export preset with permissions; CI builds a debug APK (AUDIT-002).
- [ ] The catalog and art load from inside the package or `user://` on a device with no `D:` drive (AUDIT-001).
- [ ] Import runs without freezing (AUDIT-005).
- [ ] Every table action is possible by touch (AUDIT-019).
- [ ] A bot turn under about 1 s on the target phone (AUDIT-027).

**A complete local Commander game** — *essential*
- [ ] Imported decks resolve fully, including multi-face cards (AUDIT-003, -006, -012).
- [ ] Unsupported card text is visible to the player (AUDIT-007).
- [ ] Deck legality is shown before the match (AUDIT-024).
- [x] Turn structure, priority, stack, combat, commander tax and damage, the command-zone replacement, and SBA covered by the passing suites; bot-vs-bot games finish without errors (verified).

**Network multiplayer testing** — *essential for the online goal*
- [ ] No hidden-information leaks (AUDIT-008, -009).
- [ ] Join requires the room code; payloads are bounded (AUDIT-014).
- [ ] The host re-validates the guest's cards (AUDIT-015).
- [ ] A two-device match played to completion over LAN and over the internet (not yet verified by me).
- [ ] Reconnect within a grace period (AUDIT-016).

**Public beta** — *essential*
- [ ] All P0 and P1 items closed.
- [ ] Atomic saves and visible save errors (AUDIT-013); delete confirmation (AUDIT-011).
- [ ] Release builds strip the dev addon and debug mode (AUDIT-030, -031).
- [ ] Crash reporting or bug-report export reachable on mobile (the bug report saves to `user://bug_reports`; it needs a share or export path on Android).

**Production release** — *essential*
- [ ] All P2 items closed or explicitly deferred with notes.
- [ ] Memory stable across 10 consecutive matches (AUDIT-027).
- [ ] Store-policy review (Wizards of the Coast fan-content policy for names and art; Apple and Google guidelines).

**Long-term goals (not release blockers):** 3–4 player Commander (AUDIT-017), card scanning at 10 and then 50 cards per photo (AUDIT-018), iOS build, Oracle coverage well above 45%, manual damage assignment (AUDIT-037).

---

## Final quality check
- 37 unique IDs (AUDIT-001 … AUDIT-037), no duplicates; root causes are grouped in §7.
- Every CONFIRMED item cites code, and a probe, test, or tool result where marked.
- Missing functionality is labelled FEATURE GAP (002, 016, 017, 018, 026, 037) and kept separate from broken functionality.
- Not marked as working because not verified: Android or iOS behaviour, two-machine online play, visual layout, scanning (absent), and performance on phones.
- **Most important unknowns to test next:** (1) a real APK on a phone (launch, memory, touch); (2) a two-device internet match (UPnP, NAT, latency, disconnects); (3) how many of the saved decks' cards resolve correctly after the catalog fix; (4) which classes leak per match.
- **No application files were modified during the audit.** `git status` before and after shows the same 10 modified and 4 untracked files from earlier work, plus the 178 untracked downloaded images. This report is the only new file. All runtime checks used scratch copies with an isolated `user://` folder.

---

## Repair log

### Stages 1–2 (2026-10-09) — working tree, not yet committed

| ID | Result | How it was verified |
|---|---|---|
| AUDIT-004 | **Fixed.** `purge_test_decks()` and both calls are gone; a deck named "Mono Red Burn" is kept. | `test_a_deck_named_mono_red_is_kept` |
| AUDIT-028 | **Fixed for the deck, import and bug-report tests.** `DeckStore` takes a folder (`DeckStore.scratch(label)` / `wipe()`); every test that wrote to the real `user://imported_decks` or `bug_reports_test` now uses a throw-away folder. *Still open:* the two live-network import tests still pass when the fetch fails (needs saved JSON fixtures, stage 4). | full run left no files in the scratch `user://` |
| AUDIT-013 | **Fixed.** Saves write `*.tmp` then rename; failures return `""` with `last_error`; the Builder and Import window show the reason and stay open; unreadable deck files are listed by `list_damaged()`; renaming also commits on focus loss and reverts a name that can't be saved. *Not yet shown in the UI:* the damaged-deck list. | `test_saves_are_atomic_and_damaged_files_are_listed`, `test_a_failed_save_says_why` |
| AUDIT-011 | **Fixed.** Delete asks "Delete \"<name>\"? This can't be undone." (Keep / Delete). *Not exercised by an automated UI test.* | code review only |
| AUDIT-012 | **Fixed.** Cards the database doesn't know (and missing commanders) are left out of the game instead of being dealt blank; History says which. | `test_unknown_cards_are_left_out_not_dealt_blank` |
| AUDIT-001 | **Fixed in the project, verified on Windows only.** The `.gdignore` moved from `data/scryfall/` to `data/scryfall/images/`; the catalog loads from `res://data/scryfall/catalog.jsonl` (no `D:` fallback); art downloads to `user://card_art` and failed downloads are not retried for 5 minutes. A scratch export pack now contains the catalog and, run on its own, logged `Scryfall catalog loaded: 38633 cards from res://data/scryfall/catalog.jsonl`. | `engine_packaging` suite; `--export-pack` + run |
| AUDIT-002 | **Partly fixed.** `export_presets.cfg` (now committed) has Windows and Android presets: arm64, landscape, INTERNET / ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE / CHANGE_WIFI_MULTICAST_STATE, no secrets. The Android preset is recognised by Godot, but **no APK was built or run**: this PC has no Android SDK or JDK. | `--export-debug "Android"` stops only on the missing SDK/JDK |
| AUDIT-030 | **Fixed in the presets.** `addons/godot_ai`, `tests/`, `tools/`, `docs/` and the loose card pictures are excluded; the pack runs without the addon and without errors. | pack contents + run |
| AUDIT-031 | **Fixed.** `DEBUG_MATCH = OS.is_debug_build()`; the F3 overlay only works in debug builds. | code review only |
| AUDIT-020 (part) | Art no longer written into the project folder; failed downloads back off. *Still open:* texture cache has no size limit; JPEGs still load on the main thread. | code review |
| AUDIT-032 (part) | README and CLAUDE.md describe the shipped catalog, art cache, presets and test-store rule. | — |

**Test result after these changes (Godot 4.7.2, scratch copy, isolated `user://`):** 533 passed, 0 failed, 47 suites (was 524 / 46). New: `engine_packaging` (5 tests) plus 4 tests in `engine_import`.

**Not done yet in stages 1–2:** the CI export check (needs templates in CI and could not be tried here); an Android build on a device (AUDIT-002); the damaged-deck list in the Gallery.

### Stage 3 (2026-10-09) — working tree, not yet committed

| ID | Result | How it was verified |
|---|---|---|
| AUDIT-021 | **Fixed.** `scripts/match_state.gd`, `scripts/rival_ai.gd`, the `USE_ENGINE` switch, `var state` and every dead `else` branch in `table.gd` are removed. Before the first host view a guest now draws `TableView.waiting()` ("Waiting for the host…") instead of prototype data. The legacy `RivalAI` unit test was deleted with it. | full suite; headless launch of menu and table; a scripted guest table with no view drew without errors |
| AUDIT-022 | **Fixed.** The rival is named from the seat's name (the deck it plays); "Talrand"/"Krenko" literals are gone from `table.gd` (`_rival_name()`). The menu's intro text still says "Krenko against a Talrand bot". | `test_a_new_game_keeps_the_chosen_decks_and_names_the_rival` |
| AUDIT-010 | **Fixed.** Menu → New game restarts from the chosen decks (`_start_from_app_state()`), not the generated demo. *Checked at the session level; the button itself was not clicked.* | same test (session level) |
| AUDIT-033 | **Partly fixed.** Deleted `engine/import/edhrec_decks.gd` and `moxfield_starters.gd`. `engine/costs/restriction.gd`, `engine/game_view.gd` (still referenced by `engine.gd`) and the `playmat_demo` test bench were kept. | grep for references |
| AUDIT-032 (part) | CLAUDE.md, CONTRIBUTING.md, README and `docs/migration-status.md` no longer point at the deleted prototype. The 2,000-line design document `docs/aetherfold-rules-engine.md` still describes it as history. | — |

**Test result:** 534 passed, 0 failed, 47 suites (Godot 4.7.2, scratch copy, isolated `user://`).

### Stage 4, first part (2026-10-09) — working tree, not yet committed

| ID | Result | How it was verified |
|---|---|---|
| AUDIT-003 | **Fixed for the shipped catalog and old saved decks.** New `tools/build_catalog.gd` rebuilds `data/scryfall/catalog.jsonl` from the Scryfall bulk file that was already on `D:` (needs only Godot, no Python): every face keeps its cost, type, text and P/T; 3,737 art / token / emblem / plane / scheme / vanguard rows are dropped, so a real card's name can no longer find an art card. 34,896 cards (35.8 MB, was 38,633 cards / 43.8 MB), 889 of them multi-face. Double-faced cards also get front-face colours and pictures (the network resolver had left DFC pictures empty). Old saved decks with bare face names are refreshed from the catalog when a match starts (`DeckCatalog.refresh_rows`; the only one of your 10 saved decks affected was *Endless Punishment*, 1 card). | `engine_catalog` suite (8 tests: Delver, Fire // Ice, Bonecrusher Giant, Valki, art, old-deck refresh) |
| AUDIT-006 | **Fixed.** The Archidekt importer uses the deck's own `includedInDeck` category flags and each card's first category; companions stay outside the 100. The live deck that came in as 92 cards now imports as exactly 100. | fixture test + the live-network test (now asserts 100 cards) |
| AUDIT-028 (rest) | **Fixed.** The two live-network import tests now *skip* with the reason when the site can't be reached, and assert the card count when it can (they used to pass on failure). | `engine_import` |

**Test result:** 543 passed, 0 failed, 48 suites (Godot 4.7.2).

**Open from this stage:** the new catalog is 35.8 MB replacing a 43.8 MB file, so the next commit adds a large changed blob (git stores a compressed copy). Layout `prepare` (55 Secrets of Strixhaven cards) is not played as an adventure — I could not confirm its rules, so it is left alone. Many double-faced cards (Delver of Secrets, for example) are now complete in the data but still have rules lines the Oracle reader cannot act on (AUDIT-007).

### Stage 4, second part (2026-10-09) — working tree, not yet committed

| ID | Result | How it was verified |
|---|---|---|
| AUDIT-024 | **Fixed.** Deck lists and the Gallery mark decks that aren't legal Commander decks and say why (from the validation saved with the deck, including cards that couldn't be found). Starting a match with such a deck asks "Play anyway?"; a deck that was deleted or can't be read is reported and the match does not start (it used to become Krenko silently). | `DeckCatalog.problems_of` / `playable` tests; the real menu driven by a script in the scratch copy: missing-deck notice, illegal-deck confirmation, Gallery warning, delete confirmation |
| AUDIT-025 | **Fixed.** Commander pairing follows CR 702.124: plain Partner with plain Partner; the same "Partner — X" variant only; "Partner with" must name each other; Friends forever; Choose a Background with a Background (a plain legend no longer pairs with one); a Doctor with a Doctor's companion. The Builder's commander search lists only Commander-legal cards. | `test_commander_pairs_follow_the_partner_rules` (11 cases) |
| AUDIT-026 | **Mostly fixed.** The Gallery has **Copy deck** (an independent deck "… (copy)" that is never mistaken for a precon or an import) and **Copy list** (the decklist as text on the clipboard; the importer reads it back). *Not done:* opening a saved deck in the Builder to edit it. | `test_a_deck_copy_is_independent_and_the_list_reads_back`; menu probe |
| AUDIT-023 | **Partly fixed.** The two built-in starters are now labelled "Random starter: a new mix of cards every game". They are still random card piles, and without the catalog they still use invented "Volunteer" cards; the real fix is replacing them with shipped decklists like the precons. | label only |

**Test result:** 546 passed, 0 failed, 48 suites (Godot 4.7.2).

### Stage 6 (2026-10-09) — Oracle reader coverage for your saved decks, working tree, not yet committed

Goal: cards the engine could not read (the ones marked "!" at the table) should be read and played. Starting point: 103 cards across the 10 saved decks had at least one unread line.

| Area | Result | How it was verified |
|---|---|---|
| Readers added | Several dozen rules lines now read and played, among them: temporary copies (a land that becomes a copy until end of turn), Kalitas's exile replacement, casting from the graveyard on a condition or this turn (Gravecrawler, Zul Ashur), land freeze and stun counters, "each player chooses", fights between token and creature groups, life-total swaps, mana per tapped land, cycling triggers, modal triggers on two events (Elder Gargaroth, Tectonic Giant), once-per-turn mode choices (Parapet Thrasher), Void Winnower, Darksteel Angel, Leyline Tyrant, Syr Konrad, Gruff Triplets, Archfiend of Despair, free casts with a commander, convoke granted to creature spells. | 40 behaviour tests in `engine_deck_lines`, each driving the rules engine (not just the parser) |
| Result | 103 → 86 cards with an unread line. Two decks are fully read (Calling All Angels, Veloci-RAMP-Tor). | `tools/deck_audit.gd` on every saved deck |
| Approximations | Restless Spire's "During your turn, ~ has first strike" is read as plain first strike while animated. Vial Smasher the Fierce always burns the opponent chosen at random (never one of their planeswalkers). The Dragon-targeted trigger in Thunderbreak Regent fires for any opponent's spell or ability. | noted in code comments |
| Still unread | About 85 cards, each with its own mechanic (phasing, Class levels, sectors, "choose a card type", reveal-until-cast, delayed triggers, restricted mana, text swapping, extra combats, turn-order reversal). | `/c/audit_decks5.txt` list |

**Test result:** 596 passed, 0 failed, 49 suites (Godot 4.7.2).

### Stages 5–9 follow-ups and bug reports (2026-10-10) — working tree, not yet committed

| ID | Result | How it was verified |
|---|---|---|
| AUDIT-029 | **Fixed.** The city's blessing is stored on the player (`PlayerState.citys_blessing`), set by ascend once they control ten permanents and kept for the rest of the game. `ascend` is marked ENFORCED. | `engine_perf_and_blessing` (blessing survives losing permanents; the other player never gets it) |
| AUDIT-036 | **Fixed.** The game log trims in chunks (amortised O(1) appends) and `since()` is a binary search. | `engine_perf_and_blessing` (order, gaps, `since` at and after the cap) |
| AUDIT-020 | **Mostly fixed.** The art cache keeps at most 200 pictures in memory, least-recently-used out first (disk cache in `user://card_art` and the failed-download back-off were done in stage 4). *Not done:* decoding on a worker thread. | picture-cache test |
| AUDIT-027 | **Leak fixed; speed not re-measured.** `KeywordRules` held the engine strongly while the engine held it, so every finished game's objects stayed alive (about 720 objects per game); it now holds the engine weakly. Dropping 5 engines grew the object count by 3,615 before and by 0 after. Bot turn time (late-game ~0.9 s) was not worked on. | `test_a_finished_engine_leaves_no_objects_behind` |
| Bug report (Temple of the False God) | **Fixed.** "Activate only if you control five or more lands" was ignored for mana abilities, so it made mana with four lands. It now needs five. | `engine_bug_reports` |
| Bug report (Lifecrafter's Bestiary) | **Fixed.** "You may pay {G}" in a trigger could never tap a land (it isn't a moment of priority), so nothing was ever drawn. This affected every "you may pay ..." trigger. | `engine_bug_reports` (cast a creature, pay {G}, draw) |
| Bug report (Myr Superion) | **Fixed.** "Spend only mana produced by creatures to cast this spell" is now enforced: lands and floating mana can't pay for it, for you or the bot. | `engine_bug_reports` |
| Bug report (deck stops flashing after a scry) | **Not reproduced.** Upkeep scry → pass → draw step flashed correctly in the real table window. As a precaution the flash now reads the game's own draw state rather than a copy refreshed earlier. | in-window run |

**Test result:** 632 passed, 0 failed, 52 suites (Godot 4.7.2).

**Still open from the checklist:** AUDIT-037 (choose combat-damage splits and "divided as you choose"), AUDIT-017 (3–4 player games), AUDIT-018 (card scanning), bot turn speed (AUDIT-027), and the paused Android items (002, 019, 035).

### AUDIT-037 (2026-10-10) — working tree, not yet committed

| Part | Result | How it was verified |
|---|---|---|
| Combat damage | **Fixed.** When a person's attacker is blocked by two or more creatures (or has trample), the game stops before damage and asks how to divide it. With trample the player only gets damage once every blocker has lethal; an illegal split is refused with the reason; "Split it for me" (or declining) takes the automatic split. The bot, banded attackers and single blockers are still split automatically. First strike / double strike are two separate questions. | `engine_damage_split` (4 combat tests) + the dividing screen in the real window |
| Divided-damage spells | **Fixed (with one deviation).** "N damage divided as you choose among one, two, or three targets" (Arc Lightning, Forked Bolt) and "X damage divided as you choose among any number of target creatures" (Monstrous Onslaught, X = greatest power) are read and played. The targets and the split are chosen together **as the spell resolves**; the rules want the targets chosen when it is cast. The bot puts damage where it kills, leftover at the rival. | `engine_damage_split` (4 spell tests) |
| Screen | New `DistributeDialog`: a counter per row, "Lethal (N)" shortcuts, a count of points left, Confirm only when every point is placed and no more targets than allowed are used. Works online (the guest answers over the network like any other pick). | dialog tests; not run over a real network |

**Test result:** 643 passed, 0 failed, 53 suites (Godot 4.7.2).
