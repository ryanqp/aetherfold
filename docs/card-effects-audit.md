# Card effects audit (2026-10-03)

Method: every card in the 8 bundled precon decks (549 distinct cards) was read by the Oracle reader (`OracleIr`) and
compared with its Oracle text, with `CardDatabase.unread_lines()`. Cards from imported decks use the same reader.
The full list of what is not read is in [card-effects-unread.txt](card-effects-unread.txt).

**Result:** 325 of 549 cards have at least one Oracle line the engine cannot read (503 lines in all). A line that is not
read is shown in History as "not coded" and does nothing. 66 of those are instants/sorceries whose whole spell is unread.

## Bugs found while playing (fixed)
| Symptom | Cause | Fix |
|---|---|---|
| Activating Zacama's {2}{W}: gain 3 life crashed the game; Mosswort Bridge's ability never worked | The ability buttons in the sidebar were deleted with `free()` while the pressed button was still running its click handler ("Attempted to free a locked object"). Any permanent with two or more abilities hit it | `queue_free()` in `_refresh_ability_panel` |
| Mosswort Bridge: "{G}, {T}" could tap the Bridge for its own {G}, then its {T} was unpayable | Auto-payment offered the ability's own permanent as a mana source | The source is excluded while its own {T} ability is paid |
| Deathgorge Scavenger exiled a card but you never chose which | Triggers had no target picker, the game picked | You now choose trigger targets (or skip a "you may") when there is a real choice |
| Cards exiled with "you may play it this turn" couldn't be cast or played from the exile pile | No cast option / no land play for exile | Added both |
| The deck pile covered cards in hand | The hand row ran under the deck and chat box | The hand now ends before them and scrolls |

## What is still not read (by kind, lines counted from the unread list)
| Kind | Lines | Examples |
|---|---|---|
| Triggered abilities with unusual conditions or effects ("Whenever ...", "At the beginning of ...") | ~160 | "Whenever a creature you control with power 4 or greater enters, draw a card." |
| Token creation with variable size or extras ("create X ... where X is ...") | ~78 | Vampire tokens with lifelink, X = other attackers |
| Draw / card advantage variants | ~79 | "Draw a card." inside a mode, draw N then discard |
| Variable amounts ("where X is ...", "equal to the number of ...") | ~56 | damage and life equal to your Swamps |
| Static power/toughness and keyword grants | ~58 | "Other artifact creatures you control get +1/+1." |
| Modal spells ("Choose one —" with bullets) | ~43 | most commander wraths and utility spells |
| Restrictions ("can't block", "can't lose the game") | ~28 | |
| Impulse draw ("until end of turn you may play it") | ~21 | Khans / Jeskai mode lines |
| Destroy / exile all | ~18 | wrath variants by mana value |
| Characteristic-defining P/T ("power and toughness are each equal to ...") | 8 | number of artifacts / Forests / your life |
| Enters tapped unless ... | 5 | land conditions on opponents / lands controlled |
| Copy effects | 10 | copy target instant or sorcery |

## How to re-run
```
godot --headless --path . -s res://tools/coverage_report.gd -- --cards=<json array of Scryfall rows>
```
For the bundled precons, collect the `cards` rows from `data/precons/*.json` (see tools/coverage_report.gd).

## Tickets
T-019 .. T-026 in [tickets/README.md](tickets/README.md).
