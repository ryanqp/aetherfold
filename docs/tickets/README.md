# Tickets

Filed from the system audit of 2026-10-02. Fix them one at a time; change **Status** when a ticket is done.

| ID | Severity | Area | Title | Status |
|---|---|---|---|---|
| T-001 | High | Online | No version check between host and guest | fixed |
| T-002 | High | Online | Opponent leaving or disconnecting freezes the other player with no message | fixed |
| T-003 | High | Online UI | In-match Menu offers New game, Import Deck and bot difficulty during an online match | fixed |
| T-004 | High | Online | Third and later guests receive the guest's view; room cap says 6 but only 2 seats exist | fixed |
| T-005 | Medium | Engine | Guest's draw-step draw never offers dredge | fixed |
| T-006 | Medium | Online | Guest's cards to put on the bottom after a mulligan are chosen automatically | fixed |
| T-007 | Medium | Online UI | Green Next-phase button sends "pass" out of turn | fixed |
| T-008 | Medium | Network | UPnP port mapping expires after one hour | fixed |
| T-009 | Medium | Startup | Card catalog (43 MB) is parsed on the main thread at startup | fixed |
| T-010 | Low | Decks | `DeckCatalog.all_choices()` purges test decks (disk I/O) on every call | fixed |
| T-011 | Low | Menu | Settings page shows "Music: On" even when muted; mute is not remembered | fixed |
| T-012 | Low | Online | Coin-flip finish timer can fire after leaving the table | fixed |
| T-013 | Low | Performance | Host re-sends the full view on every refresh | fixed |
| T-014 | Low | Docs | CLAUDE.md / roadmap describe online play as it was a week ago | fixed |
| T-015 | Medium | Online UI | Guest has no card pick menu (kicker, alternative costs, several abilities) | fixed |
| T-016 | Low | Performance | Title backdrop redraws every frame on every menu page | fixed |

---

## T-001 — No version check between host and guest
**High · Online / network**
The host and guest must run the same build. RPC signatures changed several times this week (lobby, chat, prompts). A guest on an older copy connects, then actions and views silently fail or error.
Evidence: `scripts/net/game_net.gd` has no handshake; `_on_connected_ok` just reports "Joined room".
Fix: the guest sends its protocol number on connect; the host compares it with its own and refuses with a readable message ("Lunar is on a different version — both need to update"). Both sides show the other's build.

## T-002 — Opponent leaving or disconnecting freezes the other player with no message
**High · Online / table**
If the host or the guest closes the game or loses connection mid-match, the other table just stops. Nothing says why and the only way out is Main menu.
Evidence: the table only listens to `view_received`. `_on_server_gone` / `_on_peer_disconnected` only set a status string that the menu shows.
Fix: a `peer_left` signal; the table shows a banner "<name> left the match" with a button back to the menu.

## T-003 — In-match Menu offers New game, Import Deck and bot difficulty during an online match
**High · Online / table UI**
The Menu overlay's New game / Import Deck replace the local session with a solo game (`start_table_demo`, `start_imported`). On the host that tears down the online match without telling the guest; on the guest it creates a session that fights the net view. Bot difficulty buttons mean nothing against a person.
Evidence: `_build_menu`, `_on_new_game`, `_on_play_imported` in `scripts/table.gd` never check `AppState.is_mp()`.
Fix: hide those controls in online matches (keep Close).

## T-004 — Third and later guests receive the guest's view; cap says 6 but only 2 seats exist
**High · Online / privacy**
`GameNet.MAX_TOTAL_PLAYERS = 6`, but only the host (seat 0) and the first guest (seat 1) play. Extra guests are sent the same view as the guest, including the guest's hand, and their actions are ignored. They also have to ready up in the lobby and can block the countdown.
Fix: cap rooms at 2 players until multi-seat tables exist (the player cap of 8 stays pinned for that work) and refuse extra joins with "Table is full".

## T-005 — Guest's draw-step draw never offers dredge
**Medium · Engine / online**
The host's draw goes through `take_turn_draw` (dredge prompt). The guest's seat is not a manual-draw seat, so the engine draws for them with `draw_card` and skips the dredge question, although the lobby now makes seat 1 an interactive seat.
Fix: route the guest's draw step through the same draw-effect path when the seat is interactive.

## T-006 — Guest's cards to put on the bottom after a mulligan are chosen automatically
**Medium · Online / mulligan**
`GameSession.keep_hand` only lets seat 0 choose; seat 1 gets `_auto_put_back` (the last cards in hand). A guest who mulligans loses cards they may have wanted.
Fix: a put-back step for the guest (net action `put_back`), mirroring the host's overlay.

## T-007 — Green Next-phase button sends "pass" out of turn
**Medium · Online / table UI**
`_on_next_phase` calls `_client_net("pass")` before any `_mp_wait()` check, so a guest can press it during the host's turn. The host ignores it, but the guest gets no explanation.
Fix: guard `_on_next_phase` with `_mp_wait()`.

## T-008 — UPnP port mapping expires after one hour
**Medium · Network**
`add_port_mapping(..., 3600)` asks the router for a one-hour lease and nothing renews it. Long games can stop accepting reconnects once the lease lapses.
Fix: renew the mapping every 30 minutes while hosting.

## T-009 — Card catalog (43 MB) is parsed on the main thread at startup
**Medium · Startup**
`ScryfallCatalog._ready` reads and parses 38,000 JSON lines synchronously, so the window freezes for several seconds before the title screen appears.
Fix: parse on a worker thread; screens that need the catalog wait for a `loaded` signal and show "Loading cards…".

## T-010 — `DeckCatalog.all_choices()` purges test decks (disk I/O) on every call
**Low · Decks**
Every call runs `purge_test_decks()`, which scans and deletes files. The menu calls it for each list refresh and the lobby calls it too.
Fix: purge once at startup; `all_choices()` only reads.

## T-011 — Settings page shows "Music: On" even when muted; mute is not remembered
**Low · Menu**
`settings_music` is created with fixed text and `Music.muted` is not saved, so the label and the real state can disagree and the choice resets every launch.
Fix: read the state when the page opens; save mute in `user://audio.cfg` with the volume.

## T-012 — Coin-flip finish timer can fire after leaving the table
**Low · Online / table**
The host's 2-second timer after the flip captures the table in a lambda. If the host leaves the table before it fires, the call lands on a freed node and prints errors.
Fix: re-check the table is still in the tree before acting.

## T-013 — Host re-sends the full view on every refresh
**Low · Online / performance**
`broadcast_view` runs on every `_refresh()` and sends every card dictionary (rules text, image URLs). Busy turns mean many large reliable packets.
Fix: only send when the view's content changed (hash).

## T-014 — CLAUDE.md / roadmap describe online play as it was a week ago
**Low · Docs**
"LAN multiplayer doesn't prompt the defender to block yet", "Multiplayer is LAN-only" and the roadmap no longer match the code (internet play, lobby, chat, guest blocks).
Fix: update the known-gaps list and describe the online flow.

## T-015 — Guest has no card pick menu (kicker, alternative costs, several abilities)
**Medium · Online / table UI**
The guest's play click always sends a plain cast / play / first ability. Cards with several ways to cast or several abilities can't be used properly from the guest's side; the host's table has `card_menu`.
Fix: at minimum tell the guest why a plain cast did nothing; ideally send the menu entries to the guest in the view and let them pick.

## T-016 — Title backdrop redraws every frame on every menu page
**Low · Menu / performance**
`MagicBackdrop._process` calls `queue_redraw()` each frame (about 150 draw calls) even behind dense pages like the library, and while the window is in the background.
Fix: redraw at about 30 fps off the title screen and stop when the window loses focus.

---

## Found while fixing (open)

## T-017 — Guest can't cast from the graveyard / exile piles
**Medium · Online / table UI**
The pile click (`_on_click_pile` → `session.zone_menu`) only reads the guest's empty stand-in session, so flashback / escape / foretell casts from the guest's graveyard or exile do nothing.
Fix: same request / answer exchange as the card menu (`menu` / `menu_pick`), with a zone id.

## T-018 — Online responses are only offered for instants / abilities, not at phase boundaries
**Low · Online**
`GameSession._can_respond` stops for the other player only when a spell or ability is on the stack. A player can't act in the other's upkeep / end step with nothing on the stack (for example flash creatures at end of turn) because priority is passed for them automatically.
Fix: optional "stop at my opponent's end step" setting, or a hold-priority button.

---

## Card effects (from the 2026-10-03 audit, see ../card-effects-audit.md)

| ID | Severity | Title | Status |
|---|---|---|---|
| T-019 | High | Modal spells ("Choose one —") are not read (43 lines) | open |
| T-020 | High | Variable-size effects ("where X is ...", "equal to the number of ...") are not read (56 lines) | open |
| T-021 | Medium | Static buffs and grants ("Other artifact creatures you control get +1/+1", "can't block") (~86 lines) | open |
| T-022 | Medium | Variable tokens ("create X tokens ... where X is ...") (78 lines) | open |
| T-023 | Medium | Characteristic-defining power/toughness (8) and "enters tapped unless ..." lands (5) | open |
| T-024 | Medium | Impulse draw modes ("until end of turn you may play it") not read (21) | open |
| T-025 | Medium | Triggers with unusual conditions / amounts ("whenever a creature with power 4 or greater enters") (~160) | open |
| T-026 | Low | Destroy-all variants by mana value, copy-spell effects, gain control (33) | open |
| T-027 | Medium | Trigger target choice only asks when the trigger resolves, not when it goes on the stack | open |

Done from the same audit: ability panel crash (T-028), Mosswort Bridge self-tap payment (T-029), exile-pile casting (T-030),
deck covering the hand (T-031), trigger target picker (Deathgorge Scavenger) (T-032).

From the Endless Punishment game (all fixed, `tests/engine/test_engine_card_reports.gd`):
T-033 import dialog showed two import buttons (now "FETCH DECK", hidden after a successful fetch), T-034 "whenever an opponent
draws" triggers were not read (Fate Unraveler), T-035 an additional cost's discarded card could not be asked about ("if the
discarded card wasn't a land", Grab the Prize) and a spell with one unread sentence did nothing at all (spells now run the
sentences they understand and print "Not coded yet" for the rest), T-036 play-from-exile permissions on a permanent
(Theater of Horrors), plus life gained / lost this turn were never counted.
