# Keyword audit against the Comprehensive Rules (effective 2026-09-25)

Every keyword ability (CR 702) and keyword action (CR 701) in the rules was matched by name against
`engine/cards/keyword_db.gd`, then checked for code that actually uses it (not just a table row).
Every keyword now has a row, and none is marked MISSING. Rule numbers in older rows may have drifted (Menace is now 702.111).

## Added in the audit
| Keyword | CR | Where | Player choice / UI |
|---|---|---|---|
| Wither | 702.80 | `RulesEngine._mark_damage`: -1/-1 counters | none |
| Undaunted | 702.125 | `RulesEngine._undaunted` (in `cost_reduction`) | none |
| Living metal | 702.161 | `LayerManager.snapshot`: creature on its controller's turn | none |
| Dredge | 702.52 | `AbilityExecutor._draw_cards`, `KeywordRules.dredge_cards/do_dredge`, `RulesEngine.take_turn_draw` | Asked in place of each draw (draw step and draw effects) through `ChoiceDialog`; decline to draw |
| Recover | 702.59 | `RulesEngine._recover_triggers`, `KeywordActions._recover` | Yes/no: pay the cost or exile |
| Aura swap | 702.65 | special action (card menu) -> `KeywordActions._aura_swap` | Pick the Aura from your hand |
| Transfigure | 702.71 | special action (card menu), sorcery speed, then `SEARCH_LIBRARY` | Pick the creature card |
| Waterbend | 701.67 | `KeywordRules.cover`, `cover_waterbend`; parsed in `OracleIr._costs` and `KeywordLines` | Optional additional cost is a cast-menu entry; which permanents tap is automatic |
| Compleated | 702.150 | `KeywordRules.after_permanent_landed` (life paid is remembered as the `phyrexian_life` mark) | none |
| Storied | 702.195 | `SbaManager._check_storied`; "Enduring story" shows in the life box | none |
| Infinity / harness | 702.186, 701.64 | `∞ — <trigger>` is read as a trigger gated by `if_harnessed` | none |
| Disguise | 702.168 | already worked with morph; the table row was missing | existing cast menu |

Library searches (`SEARCH_LIBRARY`) now ask the person at the table which card to take (duplicates by name are
listed once, and they may decline). The bot still picks for itself.

## Not read yet
- `waterbend {X}` costs and "unless you waterbend {N}" (Foggy Swamp Visions, Waterbending Lesson ...).
- "As long as you have an enduring story ..." conditions on the storied cards; only the designation is tracked.
- `∞ —` abilities that aren't triggers (activated or static).
- The ability to choose *which* artifacts and creatures to tap for waterbend.

## Choices still automatic (no player prompt)
Target selection for casts (`GameSession._choose_target_auto`), combat damage assignment order/split, and
defender blocks in LAN games. These are listed in `CLAUDE.md`.
