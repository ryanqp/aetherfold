# MTG Card Effects → Godot Implementation Cheat Sheet

Use this beside `engine/` while authoring `engine/cards/ir/*.json` and while debugging `RulesEngine`.

Oracle text is a description of **game procedures**. A number in that text is often the result of a choice, a count, a cost, or a duration. It is not an instruction to mutate a stat immediately.

This document is Commander rules as the Comprehensive Rules define them, written as engine behavior. It is not an RPG combat layer. Life, damage, toughness, counters, and “+1/+1” are different objects.

Aetherfold today:

| Already in the kernel | Still a gap this sheet is meant to close |
|---|---|
| Zones on `EngineEnums.ZoneId`, and `ZoneManager.move()` retires the old object id (CR 400.7) | Mid-resolution choices. `AbilityExecutor.resolve()` runs the whole effect list in one call |
| Cast-time targets: `EngineMode.CASTING` + `GameAction.CHOOSE_TARGETS` | Scry, surveil, search, discard choice, sacrifice choice, “you may”, modal choices on resolution |
| Payment pause: `EngineMode.PAYING_COSTS` | Additional costs other than mana and `{T}` |
| Legend-rule pause: `EngineMode.CHOOSING_SBA` and `state.awaiting` | Most other state-based actions (toughness 0, lethal damage, token cease-to-exist, poison) |
| Replacement pause: `EngineMode.CHOOSING_REPLACEMENT` | A general replacement list (command-zone move is the pattern to copy) |
| `GameObject.counters` dictionary, unused by rules | Counter rules, +1/+1 vs −1/−1 annihilation |
| `ContinuousEffect` with power, toughness, `until_eot`, and a query | Layers 1–6 and layer 7a/7b/7d/7e. Do not write the result back onto `CardDefinition` |
| Effect kinds the loader accepts: `DRAW`, `CREATE_TOKEN`, `COUNTER_SPELL`, `MOVE_ZONE`, `ADD_MANA`, `TAP`, `UNTAP`, `DEAL_DAMAGE`, `LOSE_LIFE`, `CREATE_CONTINUOUS_EFFECT`, `SCRY`, `LOOK`, `SHUFFLE` | Most of those keyword actions are accepted as names. Opt’s Scry is still `unparsed: true` because the decision UI does not exist |
| `TriggerManager` matches `on: "SPELL_CAST"` only | The rest of the trigger list below |
| Tokens are real `GameObject`s from `TokenCatalog` | Copy tokens, predefined tokens beyond Goblin / Drake / Soldier, token cease-to-exist |

`unparsed: true` means “store the Oracle line and do not pretend to resolve it.” That is the correct behavior for a choice the engine cannot ask yet. Inventing a creature type, a target, or a mode is the bug.

---

## 1. Eight stages, kept separate

These are different functions. One card’s Oracle text walks through several of them. None of them may pick a value the card says a player chooses.

```
ORACLE TEXT
  → 1. PARSE            recognize instructions; do not touch GameState
  → 2. EFFECT IR        Ability + AbilityEffect + decision specs + target specs
  → 3. DECISIONS        build a PlayerDecision when the instruction needs a player
  → 4. VALIDATE         filter legal targets / legal payments / legal objects
  → 5. STACK            spell, activated, or triggered ability sits on MagicStack
  → 6. RESOLVE          walk effect instructions; pause when a decision is still open
  → 7. MODIFY STATE     zone moves, damage events, counters, life, continuous effects
  → 8. AFTER            state-based actions, then triggers, then priority
```

Continuous effects are not step 7. They are a separate evaluation (`LayerManager.snapshot`) that runs whenever characteristics are read. They are not baked into the card.

| Stage | Owns | Must not |
|---|---|---|
| Parse | Turn Oracle into IR. Unknown text stays `unparsed: true` | Choose “Elf”, pick a target, draw cards |
| Effect generation | `Ability.effects`, costs, targets, trigger, duration | Read the live board and freeze a count that is supposed to be checked later |
| Player decisions | `PlayerDecision` pushed to `state.awaiting`; `EngineMode` leaves `GIVING_PRIORITY` | Default the choice to index 0, a random option, or the only creature |
| Target validation | Legal set for a target spec right now (hexproof, shroud, protection, zone, type, controller) | Treat “choose a creature you control” as a target |
| Stack resolution | `StackEntry` cursor. One instruction at a time | Apply instruction N+1 before instruction N’s decision returns |
| State modification | `ZoneManager`, damage events, life events, counter maps, `ContinuousEffect` list | Set toughness as if it were hit points. Destroy by setting life to 0 |
| Trigger generation | Watch events. Put `StackEntry.Kind.TRIGGERED` on the stack in APNAP order | Resolve the trigger in the same call that noticed the event |
| Continuous evaluation | Recompute characteristics from printed values + layers | Write the pumped power back onto `CardDefinition.power` |

---

## 2. When the player is asked

The same English word “choose” happens at different times. The engine asks at the time the rules require, then stores the answer on the spell, the permanent, or the effect.

| Instruction | When | Uses the stack? | Where the answer lives |
|---|---|---|---|
| Modal “Choose one —” on a spell or activated ability | While putting it on the stack, before targets (CR 601.2b) | The spell does. The choice does not | `StackEntry.modes` |
| Targets (“target creature”, “any target”, “up to one”) | While putting it on the stack, after modes, before costs | Yes | `StackEntry.targets` |
| X in a mana cost | While putting it on the stack | Yes | `StackEntry.x` |
| “Divided as you choose” | While putting it on the stack | Yes | `StackEntry.division` |
| Additional cost, kicker, convoke, delve, casualty cost | While paying, before the spell becomes cast | The spell is not cast until payment finishes | `StackEntry.costs_paid` |
| “You may”, “you may pay”, sacrifice/discard as an **effect**, scry, surveil, search, “choose a creature” with no word **target** | As that instruction is reached **on resolution** | The spell is already on the stack. Priority does not pass during the choice | `StackEntry.resolution` |
| “As ~ enters, choose …” | During the zone change, before the permanent is on the battlefield, before ETB triggers | No | `GameObject.choices` on the new object |
| Static “creatures you control get +1/+1” | Never. Reevaluated whenever something asks for power | No | A `ContinuousEffect` |
| “Whenever” / “When” / “At the beginning of” | The event creates a trigger object. It resolves later, after priority passes | Yes | A new `StackEntry` |
| “If you would …, … instead” | Replaces the event. No stack | No | `ReplacementManager` |
| Random (“at random”) | The engine draws from `RngStream` | No | The resulting object id |
| State-based (0 life, lethal damage, legend) | Before the next priority, no player can respond to the check itself | Legend rule already pauses in `CHOOSING_SBA` | `SbaManager` |

Casting order the engine must keep (CR 601.2):

```
ANNOUNCE
→ CHOOSE MODES
→ CHOOSE X / ALTERNATIVE COST / ADDITIONAL COST OPTIONS
→ CHOOSE TARGETS
→ CHOOSE DIVISION
→ DETERMINE TOTAL COST
→ ACTIVATE MANA ABILITIES (they do not use the stack)
→ PAY COSTS
→ SPELL BECOMES CAST
→ TRIGGERS FROM THE CAST GO ON THE STACK ABOVE IT
→ PRIORITY
```

`RulesEngine._submit_cast_spell` already splits **casting** from **paying**. Mode and target choices belong in `EngineMode.CASTING` before `_begin_payment`. Resolution choices do not belong there. Once `MagicStack.push` has happened, those choices are frozen.

If every target is illegal when the spell would resolve, the spell does not resolve (CR 608.2b). It leaves the stack and goes to the graveyard. A spell for which zero targets were chosen (“up to one”, and the player took zero) still resolves.

---

## 3. How a choice pauses Godot

Copy the legend-rule pause. `SbaManager` sets `state.mode = CHOOSING_SBA`, fills `state.awaiting`, and returns. The table reads the view and later submits `GameAction.CHOOSE_SBA`. Nothing else is legal until that action arrives.

Resolution choices use the same shape:

```
RESOLVE instruction
→ instruction.needs_player
→ state.mode = AWAITING_DECISION
→ state.awaiting = PlayerDecision
→ StackEntry.cursor stays on this instruction
→ return          # AbilityExecutor must return, not finish the effect list

# later
SUBMIT_DECISION
→ validate against decision.candidates and min/max
→ store the answer on the StackEntry
→ advance the cursor
→ continue resolve, or pause again
```

`legal_actions()` while `AWAITING_DECISION` returns only `SUBMIT_DECISION` and, if `optional` or `min_count == 0`, a decline action. Pass, cast, and activate are illegal in that mode.

Cancelling a **cast** (`CANCEL_CAST`) rewinds the spell before it becomes cast: cards move back, mana is unspent, no “cast” trigger happens. Cancelling a **resolution choice** is only legal when the instruction is optional or “up to”. A mandatory “choose a creature type” has no cancel. If the legal set is empty, apply the empty-set rule for that instruction (section 4), do not invent an option.

The UI never receives the full game and a string of Oracle text. It receives a `PlayerDecision`:

```gdscript
class_name PlayerDecision
extends RefCounted

var decision_id: int
var kind: int                 # DecisionKind
var player_id: int            # who must answer
var source_id: int
var stack_id: int
var prompt: String            # "Choose a creature type"
var min_count: int
var max_count: int            # -1 = no cap ("any number")
var optional: bool            # "you may" / up to
var distinct: bool = true
var candidates: Array         # already filtered. UI lists these, nothing else
var hidden_from: Array        # player ids who must not see candidates (look, search)
var allows_fail: bool         # search may fail to find when the rules allow it
```

`candidates` for a creature-type choice is the legal type list, not a board of creatures. `candidates` for a target is object ids and player ids that passed validation **at the moment of the choice**.

---

## 4. Effect catalog

Each entry is one Oracle pattern. “Ask” is a `PlayerDecision`. “Automatic” is work the engine does with no UI. “State” is the mutation after a legal answer. “Empty / cancel” is the rule when the player declines or nothing is legal.

Proposed effect names below are the IR to grow into. Names already accepted by `IrLoader` are marked **loads today**.

### 4.1 Choose a creature type

Oracle: `Choose a creature type. Creatures of the chosen type get +1/+1.`

Rules: A creature type is a creature **subtype** (Elf, Goblin, Drake), not a card type and not “Creature”. The player picks one. The effect uses that string for as long as its duration says. Later creatures of that type are included if the effect is continuous.

Ask: `DecisionKind.CREATURE_TYPE`, `min_count = 1`, `max_count = 1`. Candidates are the format’s creature-type list (the comprehensive subtype list), not “whatever is on the battlefield,” unless the card says “a creature type among creatures you control” or similar.

Automatic: Nothing until the answer exists. Then build the continuous effect or one-shot using the stored string.

State: Store `chosen_subtype` on the `StackEntry` or, for “as ~ enters,” on `GameObject.choices`. Apply with a query `{ "type": "creature", "subtype": chosen }`. Do not write the type into `CardDefinition`.

UI: A type menu. Not the battlefield.

Empty / cancel: Mandatory. No cancel. The list is never empty because the type list is a game constant. Do not pick index 0.

```
CARD EFFECT
→ REQUIRE_PLAYER_CHOICE
→ CHOICE_TYPE = CREATURE_TYPE
→ SHOW_CREATURE_TYPE_MENU
→ PLAYER_SELECTS_TYPE
→ STORE_SELECTED_TYPE
→ APPLY_EFFECT_TO_MATCHING_CREATURES
```

Wrong: `CARD EFFECT → subtype = "Elf" → pump`.

Mistake: Using the first creature’s subtype. Using card types (`Creature`, `Instant`). Applying only to creatures that existed at choice time when the effect is continuous. Forgetting the choice when the permanent blinks (zone change creates a new object; “as this enters, choose” happens again).

### 4.2 Choose a player

Oracle: `Choose a player. That player discards a card.`

Rules: “Choose a player” is not “target player” unless the word target is printed. Hexproof and shroud do not apply. Range of influence in Commander is the whole table. The chosen player then makes their **own** decisions (they choose which card to discard).

Ask: `DecisionKind.PLAYER`, candidates = player ids who match the filter (`opponent`, `any`, `another`). Then, if the effect says that player discards, a **second** decision is issued to that player.

Automatic: None.

State: `StackEntry.chosen_player_id`. Life, discard, and draw then use that id.

UI: Seat picker. Then, if needed, that seat’s hand picker, visible only to them.

Empty / cancel: Mandatory one player. With only one opponent in 1v1 the UI can show that one seat, but the engine still records a choice action. It does not skip the decision type. “Up to one player” may be declined.

Mistake: Always picking `player_id + 1`. Targeting through hexproof. Letting the caster pick which card the opponent discards.

### 4.3 Choose a creature

Oracle: `Choose a creature you control. It gets +1/+1 until end of turn.`

Rules: Not a target. Chosen on resolution (or as the permanent enters, if printed that way). Can choose a creature with hexproof or shroud. “You control” filters controller. Protection does not stop a non-targeting choice.

Ask: `DecisionKind.OBJECT`, query `{ zone: BATTLEFIELD, type: creature, controller: YOU }`, min 1, max 1.

Automatic: None before the answer. After it, add a continuous effect affecting that object id, or the new object id if a later zone change matters. A one-shot pump stores the object id and a duration.

State: `ContinuousEffect` or a one-shot modifier. Not `CardDefinition.power`.

UI: Battlefield highlights of legal creatures only.

Empty / cancel: If no legal creature, the instruction does nothing. Mandatory when one exists: the player must pick. Optional only if the card says “you may” or “up to one.”

Mistake: Calling `TargetingManager` and applying hexproof. Calling `randi() % creatures.size()`. Pumping every creature because the filter was reused as the affected set.

### 4.4 Choose any target

Oracle: `~ deals 3 damage to any target.`

Rules: “Any target” means a creature, player, planeswalker, or battle (CR 115.4). It **is** a target. Chosen as the spell is put on the stack. On resolution, re-check legality. Illegal target → that target is skipped; if it was the only target, the spell does not resolve.

Ask: At **cast**, `DecisionKind.TARGET`, candidates = legal creatures + players + planeswalkers + battles, minus hexproof from the caster’s opponents, shroud, protection from the spell’s qualities, and the spell itself.

Automatic: On resolution, deal damage to the stored target if still legal. Damage is an event (4.32), not a toughness write.

State: `StackEntry.targets[slot] = object_id or encoded player id`. `TargetingManager.decode_player` already distinguishes players from objects.

UI: Board plus player frames. Illegal objects are not selectable.

Empty / cancel: Zero legal targets → the spell cannot be cast. The player may `CANCEL_CAST` before payment completes. They may not decline a required target.

Loads today: `DEAL_DAMAGE` plus a `targets` entry. The target kind must be `ANY_TARGET`, not a bare `PERMANENT`, or players can never be hit. Shock’s sample IR uses `PERMANENT`, which is narrower than “any target.”

Mistake: Picking a random creature. Subtracting 3 from toughness. Treating the player as a `GameObject`. Including artifacts that are not creatures.

### 4.5 Target creature

Oracle: `Destroy target creature.`

Rules: The word **target** means CR 115. Chosen at cast. Must be a creature permanent (on the battlefield) unless the card names another zone. Re-checked on resolution. “Another target creature” excludes the source. “Target creature you control” filters controller. “Target creature an opponent controls” likewise.

Ask: Cast-time `DecisionKind.TARGET`, query type creature plus controller / color / power filters. One instance of the word “target” cannot be the same object twice (CR 115.3).

Automatic: On resolution, if still a legal creature, perform the verb (destroy, pump, bounce).

State: Target slot on the `StackEntry`. The verb’s own state change (4.21–4.24).

UI: Legal creatures highlighted. Hover explains why others are illegal (hexproof, protection, wrong controller).

Empty / cancel: No legal creature → cannot cast. All targets illegal on resolution → spell does not resolve and goes to the graveyard. No “pick a new one” unless another spell changes targets.

Mistake: Destroying a random creature. Destroying at cast time. Ignoring hexproof. Using the battlefield list from cast time without a resolution check. Implementing destroy as `damage_marked = 999`.

### 4.6 Up to one target

Oracle: `Up to one target creature gets +2/+2 until end of turn.`

Rules: Min 0, max 1. Choosing zero is legal even when a creature exists. The spell is targeted only if a target was chosen (CR 115.6). With zero targets it still resolves, and it is not countered by “counter target spell” effects that require the spell to have targets only when it actually has them. On resolution, a chosen illegal target causes a full fizzle only when every chosen target is illegal.

Ask: Cast-time target decision, `min_count = 0`, `max_count = 1`, `optional = true`.

Automatic: If the array is empty, skip the verb. If it holds an id, apply the verb when legal.

State: `targets[slot] = []` or `[id]`.

UI: Legal creatures, plus an explicit “Choose none” control. Closing the window is not “choose none” unless the button says so.

Empty / cancel: Choose none is success. Cancel cast is a different action and rewinds the spell.

Mistake: Requiring one creature because `count: 1` was copied from Murder. Auto-selecting the only creature.

### 4.7 Any number of targets

Oracle: `Any number of target creatures you control each get +1/+1 until end of turn.`

Rules: Min 0, max = every object that is legal **right now**, all distinct. Chosen at cast. Each is re-checked on resolution. Illegal ones are dropped; the rest still get the effect. Zero is legal.

A different sentence, “one or more target creatures,” has min 1.

Ask: `min_count = 0`, `max_count = -1`, `distinct = true`. Confirm button required so the player can stop selecting.

Automatic: On resolution, filter the stored list to those still legal, then apply per object.

State: `targets[slot] = Array[int]`.

UI: Multi-select with a count, a confirm, and a “none” path.

Empty / cancel: Confirming an empty list is legal for “any number.” It is illegal for “one or more.”

Mistake: Assuming exactly one. Capping at a hard-coded 5. Applying the pump once to the whole battlefield because the list was non-empty.

### 4.8 Choose one —

Oracle: `Choose one — • Draw a card. • ~ deals 2 damage to any target.`

Rules: Modes are chosen at cast (or at activation), before targets. Only chosen modes happen. Targets exist only for chosen modes. The player cannot change the mode on resolution.

Ask: `DecisionKind.MODE`, `min_count = 1`, `max_count = 1`, candidates = the printed modes.

Automatic: Resolve only the chosen mode’s effect list, in order.

State: `StackEntry.modes = [mode_id]`. Untaken modes are not executed and their targets were never chosen.

UI: Modal card UI. If the chosen mode has a target, the target UI opens next, still inside `CASTING`.

Empty / cancel: Must pick one to continue the cast. `CANCEL_CAST` aborts the whole cast. There is no “resolve with no mode.”

Mistake: Resolving both modes. Picking the first mode in the JSON. Asking for targets of every mode.

### 4.9 Choose two —

Oracle: `Choose two —` with three or more modes.

Rules: Two **different** modes unless the card says the same mode may be chosen more than once. Both modes resolve, in the printed order, not the order selected. Targets for both are chosen at cast.

“Choose one or more —” is min 1, max = all modes, distinct.
“Choose one or both —” is min 1, max 2 on a two-mode card.

Ask: `DecisionKind.MODE`, `min_count = 2`, `max_count = 2`, `distinct = true`.

Automatic: Execute chosen modes in printed order.

State: `StackEntry.modes` as a set, iterated in card order.

UI: Multi-select locked at 2, then target steps for each chosen mode that targets.

Empty / cancel: Fewer than two does not confirm. Cancel cast rewinds.

Mistake: Resolving in click order when the card’s order matters (a mode that draws, then a mode that cares about hand size). Allowing the same mode twice by default.

### 4.10 You may

Oracle: `You may draw a card.` / `You may sacrifice a creature. If you do, draw a card.`

Rules: The controller (or the player named by the effect) makes a yes/no decision as the instruction resolves. “If you do” gates the following instruction on that yes. A bare “you may A. You may B.” is two decisions. Declining is not a cancel of the spell; earlier instructions still happened.

Ask: `DecisionKind.MAY`, `optional = true`. If yes and the verb itself needs a choice (which creature), that choice comes next and is mandatory inside the accepted may.

Automatic: No → skip this instruction and skip an “if you do” tail. Yes → perform the verb.

State: A bool on the resolution cursor, `did = true/false`, consumed by the next `IF_YOU_DO` link.

UI: “Draw a card?” with Yes and No. Not a dismissible popup that defaults to Yes.

Empty / cancel: No is a legal answer. If the verb is impossible (library empty, no creature to sacrifice), the may is not offered and `did` stays false. Do not ask “may” and then fail.

Mistake: Always accepting the may. Treating “you may” as a cast-time kicker. Drawing before the answer.

### 4.11 You may pay [cost]

Oracle: `You may pay {2}. If you do, draw a card.`

Rules: Asked on resolution unless the card makes it an additional cost. The engine checks the player **can** pay (mana, life, sacrifice, discard) before offering the may. Paying happens immediately, as a cost, if they say yes. Mana abilities may be activated during that payment the same way as `PAYING_COSTS`.

Ask: `DecisionKind.MAY_PAY`. Yes opens the existing payment mode with this cost as the bill. No skips.

Automatic: If the pool and available permanents cannot pay, skip without a prompt.

State: Mana pool, sacrificed objects, discarded cards, plus `did = true` only after payment succeeds.

UI: Cost prompt, then the mana / object picker already used for casting. A clear No.

Empty / cancel: No → don’t pay, don’t do the “if you do” clause. Starting to pay and then cancelling the payment is a No, provided nothing was paid yet. Partial payment must rewind.

Mistake: Paying automatically because the mana is sitting in the pool. Drawing even when they decline. Treating this as kicker (kicker is chosen at cast, not now).

### 4.12 As an additional cost

Oracle: `As an additional cost to cast this spell, sacrifice a creature.`

Rules: This is part of **casting**, after targets and before the spell becomes cast. The spell is not cast if the cost is not paid. No “cast” trigger, no tax increment, the card returns to the zone it came from. Commander tax is an additional mana cost the engine already adds; it is not written on the card.

Ask: During `PAYING_COSTS`. `DecisionKind.PAY_COST` with a `CostType.SACRIFICE` (or discard, exile, pay life, tap). The player chooses which legal object pays the cost.

Automatic: Mana and `{T}` already resolve through `AbilityCost`. The spell object stays off the stack until `CONFIRM_PAY`.

State: Cost objects leave the battlefield (sacrifice) or hand (discard) as the cost is paid. Then `_put_spell_on_stack`.

UI: “Choose a creature to sacrifice” before the spell appears on the stack. Cancel returns everything.

Empty / cancel: No legal creature → the cast is illegal; do not enter payment. `CANCEL_CAST` rewinds. There is no version of this spell that resolves without the cost.

Mistake: Sacrificing on resolution. Sacrificing a random creature. Putting the spell on the stack and then discovering the cost cannot be paid.

### 4.13 Sacrifice a creature

Oracle: `Sacrifice a creature.` as an effect, not a cost.

Rules: The instructing player sacrifices a creature **they control**. They choose which. Sacrifice is its own verb: the permanent moves battlefield → its owner’s graveyard. It is not destroyed. Indestructible does not stop it. “Cannot be sacrificed” does. Dies triggers see a battlefield → graveyard move. The choice and the sacrifice happen on resolution without passing priority in between.

Ask: `DecisionKind.SACRIFICE`, query creatures the **instructed player** controls, min 1, max 1.

Automatic: `ZoneManager.move` to `GRAVEYARD` of `owner_id`. Then the normal after-event loop (SBA, dies triggers).

State: Old object id retired. New object in graveyard, or the command-zone replacement if it is a commander and the owner chooses that replacement.

UI: That player’s creatures.

Empty / cancel: No creature → instruction does nothing. If this was “you may sacrifice,” do not ask. Mandatory sacrifice cannot be declined when a creature exists.

Mistake: Calling the destroy path. Sacrificing an opponent’s creature. Letting indestructible fizzle the sacrifice. Removing the creature with no zone-change event, which skips dies triggers.

### 4.14 Discard a card

Oracle: `Discard a card.` / `Target player discards a card.`

Rules: Discard means from hand to graveyard. A card discarded from hand is revealed as it is discarded. The player who discards chooses which card, unless the effect says random, says “discard your hand,” or names a specific card. “Target player discards” targets the player at cast; the **target** chooses the card on resolution.

Ask: If the set is not determined, `DecisionKind.DISCARD` to the discarding player, candidates = their hand, hidden from everyone else. Min 1 max 1 unless a number is printed.

Automatic: If the hand is empty, nothing happens. The move itself is automatic after the choice. Reveal to all players as the card hits the graveyard.

State: `move(id, GRAVEYARD, owner_id)`. Discard event for triggers (“whenever you discard”). Commander replacement may send it to the command zone instead; in that case it was not discarded to the graveyard.

UI: Hand picker for the discarding player only. Other players see the reveal after the choice.

Empty / cancel: Empty hand → no discard, no decision. Mandatory when a card exists.

Mistake: Discarding index 0. Discarding face-down. Letting the caster pick the opponent’s card. Using mill (library → graveyard) for a discard.

### 4.15 Discard a card at random

Oracle: `Discard a card at random.`

Rules: No player choice. Uniform pick from that player’s hand using the game RNG. The discarded card is still revealed. “At random” never opens a picker.

Ask: Nothing.

Automatic: `RngStream` picks one object id in the hand. Then the same discard move as 4.14.

State: Graveyard object + discard event + log line that includes the rng step so tests can replay a seed.

UI: Show the revealed card. No selection.

Empty / cancel: Empty hand → no action, and it is not a random event.

Mistake: Asking the player “which card?”. Using `randi()` outside `RngStream`, which breaks deterministic tests. Discarding the top of the library.

### 4.16 Reveal a card

Oracle: `Reveal a card from your hand.`

Rules: Reveal means every player may see the card’s front face. The card **does not move** unless a later instruction moves it. Reveal is not draw, not play, not “show the inspector only to the owner.”

Ask: Which card, if the effect does not specify one (`DecisionKind.REVEAL` on the hand). If the effect reveals a determined card (the one just tutored, the top card), no choice.

Automatic: Mark the object revealed-to-all until the effect says the reveal ends (usually as this instruction finishes, or “until end of turn” if printed).

State: A visibility flag. Zone unchanged.

UI: All seats see the face. The owner picks first when a choice exists.

Empty / cancel: No card in hand → reveal nothing. “You may reveal” can be declined, and “if you do” stays false.

Mistake: Moving the revealed card to exile or the stack “so the UI can show it.” Revealing only to the searching player (that is “look”).

### 4.17 Reveal cards from the top

Oracle: `Reveal the top five cards of your library. You may put a creature card from among them into your hand. Put the rest on the bottom in a random order.`

Rules: Those cards leave the unknown library top as a **revealed set**, in order, still tracked. They are not in hand, graveyard, or exile yet. Each later sentence consumes that set. Unmentioned cards follow the “put the rest” sentence. If the effect forgets them, the rules text will say where they go; do not leave them in limbo.

Ask: A decision whose candidates are **only the revealed set**, filtered (`type: creature` for the may). Then, if the player orders the bottom, that is a separate order decision. “Random order” is not a decision.

Automatic: Take the top N without showing them to anyone until the reveal actually happens. RNG-permute the remainder when the text says random. Move each card once, to its final zone.

State: A `RevealedSet` on the `StackEntry`: ordered object ids, face up to all. Then zone moves.

UI: All players see the five. The caster gets “put this creature into your hand” or “decline,” then sees only an animation if the rest are randomized.

Empty / cancel: Library shorter than N → reveal what exists. No creature in the set → the may is declined automatically. Decline with a creature present is legal because of “you may.”

Mistake: Drawing the five (draw triggers, hand). Milling the five. Letting the player order a pile the card says is random. Putting the rest on top.

### 4.18 Search your library

Oracle: `Search your library for a creature card, reveal it, put it into your hand, then shuffle.`

Rules: The searching player looks at their whole library. Other players do not, unless the effect reveals. A search for specific characteristics **must** find a matching card if one exists, except when the effect says “up to,” “you may search,” or “you may find.” After a search that touched the library, shuffle if the text says so (almost every tutor does). Fail-to-find still shuffles when the shuffle instruction is unconditional.

Ask: `DecisionKind.SEARCH`. Candidates = library cards matching the filter, visible only to the searching player. `allows_fail` is true only for up-to / may-find.

Automatic: Shuffle via `RngStream` when instructed, even if they failed to find. Reveal the found card if the text says reveal, at the moment it says (usually as it moves to the public zone).

State: One `move` of the chosen card to the destination zone. Then `shuffle_library`. Library order after the search is invalid until the shuffle.

UI: Private library browser with a filter. Public seats see “searching…” and then the revealed card.

Empty / cancel: No match → fail to find, no card moves, then shuffle if instructed. “You may search” can skip the search entirely; if skipped, do **not** shuffle unless the text shuffles anyway. A mandatory search with matches cannot confirm empty.

Mistake: Searching only the top card. Revealing the whole library to the table. Forgetting the shuffle. Auto-taking the first match. Tutoring into play when the text says hand.

### 4.19 Shuffle

Oracle: `Shuffle your library.`

Rules: The library’s order becomes a uniform random permutation. Every card in it is included. Face-down foretold cards in exile are not in the library. Shuffle is automatic. Players do not order the result.

Ask: Nothing.

Automatic: `RulesEngine.shuffle_library(player_id)` through `RngStream`.

State: New order of ids in `ZoneId.LIBRARY`.

UI: A shuffle animation. No picker.

Empty / cancel: A library of 0 or 1 card still “shuffles” and does not error.

Mistake: Reversing the array and calling it shuffled. Shuffling only the cards just tutored. Letting the player stack the deck. Using a fresh random seed per shuffle so tests cannot replay.

### 4.20 Put a card into your hand

Oracle: `Put that card into your hand.`

Rules: Zone change to its **owner’s** hand unless the effect names a different player (“into your hand” = the controller of the resolving effect, which for a normal spell is the caster; “its owner’s hand” is the owner). This is not a draw. Draw triggers do not happen. The new hand object is a new id (CR 400.7). Hidden zone: other players know a card moved if it came from a public zone, and know the face if it was revealed.

Ask: Which card, only if a previous instruction did not already determine it.

Automatic: `zones.move(id, HAND, owner)`.

State: New `GameObject` in hand. Counters, damage, taps do not come along (122.2, 400.7).

UI: The card appears in that player’s hand. Other players see a face-down card enter hand if it was not revealed.

Empty / cancel: No determined card (failed search) → do not move anything.

Loads today: `MOVE_ZONE` with `to: HAND`, and it currently requires the object to be on the battlefield. A tutor from the library needs a move that is legal from the source zone named by the effect.

Mistake: Calling `draw_card`. Keeping the battlefield object id. Putting it into the caster’s hand when the text says “its owner’s hand.”

### 4.21 Put onto the battlefield

Oracle: `Put a creature card from your hand onto the battlefield.`

Rules: Zone change to battlefield under the effect controller’s control unless “under its owner’s control” or “under target opponent’s control.” This is not casting. Cast triggers do not happen. ETB triggers do. “As ~ enters” choices and replacement effects (“enters tapped”) happen **during** the move, before ETB triggers are put on the stack. Auras entering this way are not cast, so they do not target; the controller chooses a legal attachment as they enter, or the aura stays where it was if none exists. Tokens enter the same way.

Ask: Which card, if not determined. “Enters tapped” is not a choice. “You may have it enter tapped” is a may. Aura attachment is `DecisionKind.OBJECT`.

Automatic: `zones.create` or `move` into `BATTLEFIELD`. `summoned_this_turn = true`. Apply enters-tapped from the effect or from a static. Then queue ETB triggers. Do not give the caster priority inside the move.

State: New battlefield object. Controller may differ from owner.

UI: The permanent appears. If a choice is required (“you may pay {2} as this enters” is usually a replacement), pause before it is visible as entered.

Empty / cancel: No card → nothing enters. Optional “you may put” can be declined.

Mistake: Going through the cast/stack path, which adds commander tax and cast triggers. Skipping ETB. Entering untapped when the effect says tapped. Resolving ETB immediately inside `create()`.

### 4.22 Exile

Oracle: `Exile target creature.`

Rules: Move to the exile zone. Not destroy, not sacrifice, not graveyard. Indestructible does not stop exile. Dies triggers do not happen, because it did not go to the graveyard. “Exile until ~ leaves” links the exiled objects to the source; they return when the duration ends, and that link has to survive on the source. Commander: if a commander would be exiled, its owner may put it in the command zone instead. That replacement is a player choice.

Ask: The target was chosen at cast. The command-zone replacement is `CHOOSING_REPLACEMENT` for the owner, and only for a commander.

Automatic: `move` to `EXILE` owned by the card’s owner. Tokens will then cease to exist as a state-based action (4.39).

State: New object in `ZoneId.EXILE`. If the effect exiles face-down, set face-down and restrict who may look.

UI: Exile pile, face up by default.

Empty / cancel: Illegal target on resolution → fizzle rules. No legal replacement choice other than the two zones when it is a commander.

Loads today: `MOVE_ZONE` only from the battlefield, and only to a named zone. Exile as a destination must be allowed. The command-zone replacement is not yet a general replacement.

Mistake: Moving to the graveyard “because it’s gone.” Incrementing an exile counter and deleting the object. Exiling during cast. Skipping the commander replacement.

### 4.23 Destroy

Oracle: `Destroy target creature.`

Rules: “Destroy” is a keyword action. If the permanent is indestructible, or a destruction-replacement (regeneration, totem armor) replaces the event, it is not destroyed. Otherwise it moves battlefield → owner’s graveyard. Destroy is not damage and does not change toughness. Lethal damage destroys via state-based actions; that path is separate, and indestructible stops it too. Toughness 0 or less is **not** destroy; indestructible does not stop it.

Ask: Target at cast, if targeted.

Automatic: If the permanent can be destroyed, `move` to graveyard. Emit a destroy event so replacements can see it before the move.

State: Graveyard object. Dies triggers (“died” means went to the graveyard from the battlefield, including destroy).

UI: The permanent leaves and the card shows in the graveyard.

Empty / cancel: Indestructible → the destroy event does nothing, spell still resolved. Illegal target → fizzle.

Mistake: `damage_marked += toughness`. Setting power/toughness to 0. Using sacrifice. Ignoring indestructible. Checking toughness inside the destroy function.

### 4.24 Sacrifice is not destroy

Same physical result (battlefield → graveyard) can come from three verbs with different shields:

| Verb | Indestructible | “Can’t be sacrificed” | Dies trigger | Typical cause |
|---|---|---|---|---|
| Destroy | Stops it | Does not apply | Yes, if it reaches the graveyard | “Destroy”, lethal damage SBA |
| Sacrifice | Does not stop it | Stops it | Yes | Cost or “sacrifice a creature” |
| Toughness ≤ 0 | Does not stop it | Does not apply | Yes | `-X/-X` effects, -1/-1 counters |
| Exile | Does not stop it | Does not apply | No | “Exile” |

State-based actions that put a permanent into a graveyard for the legend rule are not destroy either. Indestructible does not save a legend.

### 4.25 Return target…

Oracle: `Return target creature to its owner's hand.` / `Return target card from your graveyard to the battlefield.`

Rules: “Return” is a zone change from the named origin to the named destination. The target is chosen at cast and must be in that origin zone. On resolution the object must still be in that zone (last known information if it left). “Its owner’s hand” uses `owner_id`, not `controller_id`. A creature returned to hand arrives untapped, undamaged, with no counters, as a new object. A commander returned to hand may be sent to the command zone instead.

Ask: Cast-time target filtered by zone and type.

Automatic: `move` to the destination under the owner, unless the effect sets a controller (“under your control”).

State: New object in the destination. `MOVE_ZONE` is the verb.

UI: Object highlights in the named zone (graveyard browser, battlefield).

Empty / cancel: Target left the zone → that target fails. Only target → spell does not resolve.

Loads today: `MOVE_ZONE` from battlefield only. Graveyard → battlefield and battlefield → hand both need the origin checked against the target’s current zone, not hard-coded as battlefield.

Mistake: Bouncing to the controller’s hand. Keeping counters. Treating the return as a new cast. Failing to retarget-check the zone.

### 4.26 Create a token

Oracle: `Create a 1/1 red Goblin creature token.`

Rules: A token is a permanent created by an effect. It is not a card. It enters the battlefield, so ETB triggers and “enters tapped” apply. Its characteristics are exactly what the effect lists: name, colors, types, subtypes, power, toughness, abilities, and sometimes counters or tapped status. Controller is the effect’s controller unless stated. Owner of a token is that same player as it is created.

Ask: Only if the effect offers a choice (“create a red or white” is not standard; “choose a creature type” before creating “a 1/1 of that type” uses 4.1 first).

Automatic: `TokenCatalog.definition_for`, then `zones.create` on the battlefield with `is_token = true`, once per token.

State: A real `GameObject` with its own id, controller, owner, tapped, summoned_this_turn, keywords, counters.

UI: A permanent on the battlefield, marked as a token.

Empty / cancel: “Create zero” creates nothing. No cancel if the effect is mandatory.

Loads today: `CREATE_TOKEN` with `token` id and `count`. Catalog ids: `goblin_1_1_r`, `drake_2_2_u_flying`, `soldier_1_1_w`.

Mistake: Appending a dictionary to a UI list that is not a `GameObject`. Sharing one object for “two tokens.” Leaving the token in the graveyard after it dies (see 4.39).

### 4.27 Create a token that’s a copy of…

Oracle: `Create a token that's a copy of target creature.`

Rules: Copiable values (CR 707) are copied: name, mana cost, color, card types, subtypes, supertypes, rules text, abilities, power, toughness, loyalty. Not copied: counters, damage, tap status, “this turn” flags, controller (the token’s controller is the effect controller), face-down status unless the copy effect copies a face-down object. “Except it has flying” / “except it’s an artifact” / “except its power is 1” modify the copy as it is created. The token then enters the battlefield. It is a token even though it has a card’s characteristics.

Ask: The target is cast-time if it says target. “A copy of a creature you control” with no target is a resolution choice (4.3).

Automatic: Build a `CardDefinition` (or a copy record) from layer-1 copiable values of the source, apply exceptions, `zones.create` with `is_token = true`.

State: New token object. A later change to the original does not update the copy. A later copy effect copies the token’s copiable values, including exceptions that were part of how it was created (those exceptions are copiable).

UI: A token with the copied name and art identity, flagged as a token.

Empty / cancel: Illegal or missing target → normal target rules. Do not create a blank token.

Mistake: Cloning the live `GameObject` including damage and counters. Creating a generic “Copy” token with 0/0. Copying continuous pumps that are not copiable (a Giant Growth on the original is not copied).

### 4.28 Create X tokens

Oracle: `Create X 1/1 red Goblin creature tokens, where X is the number of Goblins you control.`

Rules: Compute X when the effect **resolves**, unless X was chosen as a mana-cost X at cast. Then create that many distinct tokens. X = 0 creates nothing. Each token enters separately and each triggers ETB. “Twice X” is arithmetic on the computed X, still one instruction.

Ask: Mana-cost X is a cast-time numeric choice (`DecisionKind.NUMBER`, min 0, no max other than what they can pay). “Where X is the number of …” is not a choice.

Automatic: `Query.count_objects` for a count query, or read `StackEntry.x`. Loop `create`.

State: N objects. Krenko’s IR already uses `count: { query: ... }`. `_count` handles that.

UI: If X is paid, a number stepper during casting, then the tokens appear on resolution. If X is a count, no stepper.

Empty / cancel: X = 0 is a successful resolution. Cancelling a paid X cancels the cast, not the resolution.

Mistake: Creating one token named “X Goblins.” Computing X at cast time for Krenko, so Goblins that enter in response are missed. Computing X inside the UI.

### 4.29 Give [creature] +X/+X

Oracle variants and the object each one is:

| Printed | Object | Layer | Expires | Counters? |
|---|---|---|---|---|
| `gets +3/+3 until end of turn` | `ContinuousEffect` power +3 toughness +3, duration `END_OF_TURN` | 7c | Cleanup | No |
| `gets +1/+1` on a static “creatures you control” | `ContinuousEffect`, duration `STATIC`, query reevaluated | 7c | While the source is on the battlefield and the condition holds | No |
| `base power and toughness become 3/3` | Set effect | 7b | As printed | No |
| `power is equal to the number of cards in your hand` | Characteristic-defining ability | 7a | While the ability exists | No |
| `put a +1/+1 counter` | `GameObject.counters` | 7d | Until removed or the object changes zone | Yes |
| `switch power and toughness` | Switch effect | 7e | As printed | No |

“Target creature gets +3/+3 until end of turn” adds a layer-7c effect. It does not add three +1/+1 counters. It does not change `CardDefinition.power`. Cleanup removes `until_eot` effects and damage.

Ask: Who gets it, according to target vs choose vs each vs all (section 5).

Automatic: Insert the effect with a timestamp. `LayerManager.snapshot` adds it when power or toughness is read.

State: An entry in the continuous-effect list. Affected objects are either a fixed id list (one-shot on targets) or a query (static “creatures you control”).

UI: A temporary modifier badge, not a counter icon.

Empty / cancel: No legal object → nothing is added.

Loads today: `CREATE_CONTINUOUS_EFFECT` is accepted by the loader. `ContinuousEffect` only stores power, toughness, `until_eot`, query, and controller. Extend that class; do not store the sum on the definition.

Mistake: `counters["+1/+1"] += 3`. `definition.power = str(int(power) + 3)`. Applying the bonus inside `AbilityExecutor` by editing `damage_marked`.

### 4.30 +1/+1 counter

Oracle: `Put a +1/+1 counter on target creature.`

Rules: A counter is a marker on that object. It modifies power and toughness in layer 7d, after continuous +N/+N. It stays through turns. It is removed if an effect removes it, if it annihilates with a −1/−1 counter (state-based), or if the object changes zone. A new object in the new zone does not have it. Tokens can have counters. Putting a counter is not damage and not a continuous effect.

Ask: Target or choice, per the verb. The counter itself is not a choice.

Automatic: `obj.counters["+1/+1"] = int(obj.counters.get("+1/+1", 0)) + n`. Then SBA: cancel +1/+1 with −1/−1 in pairs. Then toughness check.

State: `GameObject.counters` string → int. Any name is legal (`+1/+1`, `charge`, `lore`, `ki`).

UI: Counter pips on the permanent, distinct from a pump badge.

Empty / cancel: Illegal target → no counter. “Up to one” may place zero.

Mistake: Adding a `ContinuousEffect` of +1/+1. Removing the counter at cleanup. Keeping counters in `ZoneManager.move` (the new object starts clean unless the effect says counters move, which is rare and explicit).

### 4.31 Gets −X/−X until end of turn

Oracle: `Target creature gets -3/-3 until end of turn.`

Rules: Layer 7c continuous effect, duration end of turn. It can drop toughness to 0 or less. State-based actions then put that creature into the graveyard. That death is **not** “destroy,” so indestructible does not save it. The effect still expires at cleanup if the creature survived (other buffs, or a later anthem).

Ask: Cast-time target if it says target.

Automatic: Add the effect. Do not move the creature inside the effect applicator. Call `SbaManager` after the spell finishes resolving, before priority.

State: `ContinuousEffect` with negative power and toughness, `until_eot = true`.

UI: Temporary minus badge. If the snapshot toughness is ≤ 0, the permanent leaves as an SBA, and the log should say toughness, not destroy.

Empty / cancel: Normal target fizzle.

Mistake: Dealing 3 damage. Giving −1/−1 counters. Checking `indestructible` and skipping the death. Setting base toughness to 0 permanently.

### 4.32 Gain life

Oracle: `You gain 3 life.`

Rules: The named player’s life total increases by 3. Life gain is an event. It is not damage. It triggers “whenever you gain life.” It does not remove damage marked on creatures. Commander life starts at 40 (`PlayerState.life`). Replacement effects can replace the gain.

Ask: “You” is the controller of the resolving effect. “Target player” was chosen at cast. No numeric choice.

Automatic: `players[pid].life += n`, log `LIFE_CHANGE` with cause `gain`.

State: `PlayerState.life`.

UI: Life total ticks up.

Empty / cancel: N computed as 0 → no event (do not trigger life-gain on a zero).

Mistake: Calling it damage prevention. Routing through `LOSE_LIFE` with a negative number so “lose life” triggers fire.

### 4.33 Lose life

Oracle: `You lose 2 life.` / `Each opponent loses 1 life.`

Rules: Life total decreases. Loss of life is **not** damage. It does not trigger “whenever you’re dealt damage.” It does not cause lifelink. It is not prevented by damage prevention. Paying life as a cost is also loss of life, but it happens during payment, not as a spell effect. 0 or less life causes a loss as a state-based action, not inside the subtraction.

Ask: “Each opponent” is automatic. “Target player loses life” uses the target.

Automatic: `life -= n`, log `LIFE_CHANGE` with cause `loss`. Then SBA.

State: `PlayerState.life`.

UI: Life ticks down.

Empty / cancel: No opponents → each-opponent does nothing.

Loads today: `LOSE_LIFE` subtracts from the **controller of the targeted object**. That matches “enchanted player” style effects only when the target is a permanent that player controls. “Target player loses N” must address a player id directly.

Mistake: `DEAL_DAMAGE` to the player. Checking protection (protection stops damage, not “lose life”). Ending the game inside the effect instead of via SBA.

### 4.34 Deals X damage

Oracle: `~ deals 3 damage to any target.` / combat damage.

Rules: Damage is an event with a source, an amount, and a recipient.

- Creature recipient: mark that much damage on the object. Do not change toughness. State-based actions destroy the creature if marked damage ≥ toughness, or if the source had deathtouch and damage ≥ 1, unless indestructible. Toughness is read from `LayerManager.snapshot`.
- Player or planeswalker or battle: the player loses that much life (planeswalkers also lose loyalty; battles lose defense). This loss **is** damage, so “dealt damage” triggers and lifelink see it. Commander damage from a commander source is also added to `commander_damage_from`.
- Prevention and replacement effects see the event before marks and life change.
- Lifelink causes the source’s controller to gain life equal to the damage dealt, as part of the event, not as a trigger.
- Damage to a player by a source with infect is poison counters instead. Normal damage is not poison.

Ask: Targets at cast. Combat damage assignment is its own decision in `ASSIGNING_COMBAT_DAMAGE`.

Automatic: Emit `DamageEvent`. Run prevention. Then mark or life-loss. Then lifelink gain. Then, after the spell resolves, SBA. Do not move the creature to the graveyard inside the damage function.

State: `GameObject.damage_marked` and/or `PlayerState.life` and `commander_damage_from`. Log `EventType.DAMAGE`.

UI: Damage numbers, then a death only after SBA.

Empty / cancel: Illegal target → no damage from that target slot. Prevention of all of it → amount dealt is 0, lifelink gains 0.

Loads today: `_deal_damage` subtracts player life immediately and, for creatures, adds `damage_marked` and moves to the graveyard in the same function if damage ≥ snapshot toughness. The graveyard move belongs in `SbaManager`, after indestructible, deathtouch, and prevention exist. There is no prevention step yet.

Mistake: `toughness -= n`. `life -= n` with cause `loss` for a burn spell (wrong event type). Destroying through indestructible. Forgetting commander damage. Dealing damage at cast time.

### 4.35 Prevent X damage

Oracle: `Prevent the next 3 damage that would be dealt to any target this turn.`

Rules: A prevention shield is a continuous prevention effect (CR 615). It sits and waits. When a `DamageEvent` would be dealt to the shielded object or player, the shield reduces the amount, down to zero, and is consumed by the amount it prevented. “Prevent all damage that would be dealt to you this turn” is a shield with no numeric pool and duration end of turn. Prevention is not life gain. The damage that is prevented was not dealt.

Ask: The target of the prevention spell is chosen at cast. The later damage needs no ask.

Automatic: On each `DamageEvent`, `ReplacementManager` / prevention layer offers shields. If several apply, the affected player chooses the order (`CHOOSING_REPLACEMENT` already exists as a mode).

State: A `PreventionEffect` `{ shielded_id, remaining: 3, duration: END_OF_TURN }`. `remaining` drops as damage is prevented.

UI: A shield badge. Incoming damage shows the reduced amount.

Empty / cancel: No damage later → the shield expires unused. Illegal target at cast → cannot cast.

Mistake: `life += 3`. Subtracting 3 from the next creature’s power. Marking −3 damage.

### 4.36 Draw a card

Oracle: `Draw a card.`

Rules: The top card of that player’s library moves to their hand. That is one draw event. Draw triggers (“whenever you draw a card”) wait and go on the stack after this spell finishes resolving. If the library is empty, the player does not draw, and they lose the game as a state-based action (CR 704.5b). Replacements (dredge and similar) can replace the draw; the card then does not move library → hand, and it is not a draw.

Ask: Nothing for a plain draw. “You may draw” is 4.10.

Automatic: `RulesEngine.draw_card(player_id)`. One event per card.

State: New object in `HAND`. Library loses the top id. Log `EventType.DRAW`.

UI: A card arrives in hand, face up to its owner, hidden to others.

Empty / cancel: Empty library → failed draw → SBA loss. Do not crash and do not skip the SBA.

Loads today: `DRAW` with `n`, and `draw_card` exists.

Mistake: Moving the top card with no draw event. Drawing inside a search. Milling and also putting a copy in hand.

### 4.37 Draw X cards

Oracle: `Draw three cards.` / `Draw X cards.`

Rules: X separate draw events, one after another, not one event of size X. Each can be replaced on its own. “Whenever you draw a card” sees each. X from a mana cost was chosen at cast. X from “draw cards equal to …” is counted on resolution.

Ask: None, unless a may wraps it.

Automatic: `for i in n: draw_card`. If a draw fails because the library is empty, stop; the player loses at SBA. Do not keep looping.

State: Up to N new hand objects.

UI: N cards, in order.

Empty / cancel: N = 0 → no draws and no empty-library loss.

Loads today: `DRAW` already loops `n`.

Mistake: One `DRAW` event with `n = 3` that triggers “you drew a card” once. Pre-moving three cards and skipping the empty-library check on the second.

### 4.38 Mill X

Oracle: `Mill three cards.` / `Target player mills a card.`

Rules: Mill means the top X cards of that library move to that player’s graveyard. No player looks or chooses or reorders. It is not a draw (empty library does not lose on mill). It is not a discard (discard triggers do not fire; mill triggers do). Each card is milled. Faces are public in the graveyard. Shorter than X → mill the rest, no extra penalty.

Ask: Nothing. “Target player” was chosen at cast.

Automatic: For each of X, if library is non-empty, `move` top to `GRAVEYARD`.

State: N new graveyard objects, bottom of the old library unchanged.

UI: Cards arrive in the graveyard face up, in order.

Empty / cancel: Empty library → mill zero. Not a game loss.

Mistake: `draw_n` plus discard. A search UI. Shuffling afterward. One graveyard counter instead of objects.

### 4.39 Scry X

Oracle: `Scry 2.`

Rules: Look at the top X cards. Put any number of them on the bottom of the library in any order, and the rest on top in any order. “Look” means only that player sees the faces. Other players see how many went to the bottom, not which cards, because the library stays hidden. Scry 0 is not a scry event.

Ask: `DecisionKind.SCRY`. Two ordered lists (top, bottom) whose union is the X cards. Every card must be placed. This is mandatory to complete, but every split is legal, including all top or all bottom.

Automatic: Take the top X into a private set without revealing. After the answer, write the top list back to the top in the chosen order and the bottom list to the bottom in the chosen order.

State: Library order only. No zone change.

UI: Private two-column orderer: “Top, in order” and “Bottom, in order.”

Empty / cancel: X greater than library size → scry the existing cards. The player must confirm a placement. There is no “skip” on a mandatory scry. Closing the window does not default to “leave on top” unless a house timeout rule says so; the engine waits.

Loads today: `SCRY` is a legal effect kind. Opt still marks it `unparsed: true`. Leave it unparsed until this decision exists. Do not auto-leave the cards on top and call that a scry.

Mistake: Revealing the cards to the table. Milling the bottom cards. Drawing them. Always bottoming the first card. Treating scry as surveil.

### 4.40 Surveil X

Oracle: `Surveil 2.`

Rules: Look at the top X. Put any number of them into the **graveyard**, the rest on top in any order. Graveyard cards are public. Surveil triggers (“whenever you surveil”) fire once per surveil instruction, not once per card. Cards put in the graveyard were not milled and were not discarded, unless a card specifically bridges those. Surveil 0 does nothing and is not a surveil event.

Ask: `DecisionKind.SURVEIL`. Private look. The player marks a subset for the graveyard and orders the remainder on top.

Automatic: Move the graveyard subset with a surveil-to-graveyard cause. Rewrite the top.

State: Some objects in `GRAVEYARD`, library reordered, one surveil event.

UI: Private cards, each with “Graveyard” or “Top,” plus an order for the top pile. After confirm, the table sees the graveyard cards.

Empty / cancel: Same as scry for library size. Any subset, including none, is legal.

Mistake: Using the scry “bottom of library” destination. Drawing. Skipping the public graveyard update. Firing a mill trigger.

### 4.41 Look at…

Oracle: `Look at the top card of your library.` / `Look at target player's hand.`

Rules: The looking player learns those faces. Other players do not. The cards do not move unless a later sentence moves them. Look is not reveal.

Ask: Nothing if the set is determined (top card, that player’s hand).

Automatic: Attach a visibility grant: `player_id may see object_ids until this instruction ends` (or until end of turn, if printed).

State: No zone change. A view permission the table UI honors. `GameView` for other players must not include those faces.

UI: A private panel. Spectators and opponents see “Player looked at a card,” not the face.

Empty / cancel: Empty library or empty hand → look at nothing.

Loads today: `LOOK` is accepted and often unparsed. Implementing it as a reveal is worse than leaving it unparsed.

Mistake: Adding the card to the public log. Moving it to exile “temporarily.”

### 4.42 Reveal…

Covered in 4.16 and 4.17. The contrast:

| Word | Who sees the face | Default zone change |
|---|---|---|
| Look | The instructed player, plus anyone the effect names | None |
| Reveal | Every player | None |
| Search | The searching player | None until the “put” sentence; library is shuffled when instructed |
| Reveal the top, then put | Everyone, for the revealed set | As the following sentences say |

### 4.43 Choose a card type

Oracle: `Choose a card type.` / `Choose a nonland card type.`

Rules: Card types are the types in CR 205, not subtypes. For Commander gameplay the set that matters is:

`Artifact`, `Creature`, `Enchantment`, `Instant`, `Land`, `Planeswalker`, `Sorcery`, `Kindred`, `Battle`.

“Nonland card type” removes Land. This choice is not a creature type. Tribal/Kindred is a card type; Elf is not.

Ask: `DecisionKind.CARD_TYPE`. Candidates are that fixed list, minus exclusions printed on the card.

Automatic: Store the type word. Later queries use card type, not subtype.

State: `chosen_card_type` on the effect or permanent.

UI: A short type list. Not the creature-type menu.

Empty / cancel: Mandatory. The list is a constant.

Mistake: Offering Elf, Goblin, Equipment. Offering supertypes (Legendary) as if they were card types.

### 4.44 Supertype, card type, subtype

Store these as separate fields on characteristics. `CardDefinition.type_line` is the printed string (“Legendary Creature — Goblin”). The engine also needs the parsed lists, because continuous effects add and remove them in layer 4.

| Class | Examples | “Choose a …” menu | Query field |
|---|---|---|---|
| Supertype | Basic, Legendary, Snow, World, Ongoing | “Choose a supertype” (rare) | `supertypes` |
| Card type | Artifact, Creature, Enchantment, Instant, Land, Planeswalker, Sorcery, Kindred, Battle | Card type | `card_types` |
| Creature subtype | Goblin, Elf, Drake, Human | Creature type | `subtypes` while the object is a creature (or Kindred) |
| Land subtype | Plains, Island, Swamp, Mountain, Forest, Gate, Desert, Locus | Land type | `subtypes` while the object is a land |
| Artifact subtype | Equipment, Vehicle, Clue, Food, Treasure, Blood, Fortification | Artifact type | `subtypes` while the object is an artifact |
| Enchantment subtype | Aura, Saga, Class, Background, Role, Curse, Shrine, Case | Enchantment type | `subtypes` while the object is an enchantment |
| Planeswalker subtype | Jace, Chandra, Vraska | Planeswalker type | `subtypes` while the object is a planeswalker |
| Instant/sorcery subtype | Arcane, Trap | Spell type, when a card asks | `subtypes` |
| Battle subtype | Siege | Battle type | `subtypes` |

A Goblin token’s card type is Creature (and the printed line may say Token, which is not a card type). Its subtype is Goblin. Its color is red, stored as color, not as a type.

Color is not a type. “Choose a color” is `DecisionKind.COLOR` with candidates `W, U, B, R, G`. Color identity is a deckbuilding property (`color_identity`). Effects that say “color” use the object’s colors after layer 5. Effects that say “shares a color with your commander” use the commander’s colors, not identity, unless the card says “color identity.” Commander **deck legality** uses color identity. Do not mix them in queries.

“Choose a creature type” candidates come from the creature-subtype list even if no creature of that type is on the battlefield, unless the card restricts the choice (“a creature type among creatures on the battlefield”).

Parsing `type_line` by `contains("Creature")` is only safe for the printed line. Once layer 4 can add the type Creature, readers must use the snapshot’s `card_types`, or a Vehicle that crewed will not count as a creature.

---

## 5. Targeting system

### 5.1 Eight different meanings

| Printed | Kind | When the set is chosen | Who picks | Legality |
|---|---|---|---|---|
| `Target creature gets +2/+2` | `TARGET` | Cast / activate | Caster | CR 115, hexproof, shroud, protection, zone. Re-check on resolution |
| `Choose a creature. It gets +2/+2` | `CHOICE` | Resolution or as-enters | Named player | Filter only. Hexproof does not apply. Not re-checked as a target. The chosen object can gain hexproof in response and still be affected |
| `Choose a player` | `PLAYER_CHOICE` | Resolution, unless it is “target player” | Caster or instructed player | The filter (opponent, another). Not a target |
| `Creatures you control get +2/+2` | `NON_TARGET` continuous | Nobody | Nobody | Query, reevaluated. New creatures get it. Opponent’s creatures do not |
| `Each creature gets +2/+2 until end of turn` | `EACH` one-shot | The set is locked as the spell resolves | Nobody | Every object that matches **now**. A creature that enters later does not get this one-shot |
| `All creatures get +2/+2 until end of turn` | `ALL` | Same as each, for this kind of one-shot | Nobody | Same lock-in. “All” and “each” are the same engine object when the verb is a one-shot pump |
| `Discard a card at random` | `RANDOM` | Resolution | `RngStream` | The set (the hand), uniform |
| `Up to one target` | `UP_TO` | Cast | Caster | Min 0 max 1, still a target if one is chosen |
| `Any number of target creatures` | `ANY_NUMBER` | Cast | Caster | Min 0, distinct, still targets |

“Each” on a trigger condition (“whenever you cast a spell, each opponent loses 1 life”) is not a target and is not a continuous effect. On resolution the engine enumerates opponents and emits a life-loss event per opponent.

Godot representation:

```gdscript
# On the Ability, known before the game starts
{ "selector": "TARGET", "min": 1, "max": 1,
  "query": { "zone": "BATTLEFIELD", "card_types": ["Creature"] } }

{ "selector": "UP_TO", "min": 0, "max": 1,
  "query": { "zone": "BATTLEFIELD", "card_types": ["Creature"] } }

{ "selector": "ANY_NUMBER", "min": 0, "max": -1, "distinct": true,
  "query": { "zone": "BATTLEFIELD", "card_types": ["Creature"], "controller": "YOU" } }

{ "selector": "CHOOSE", "when": "RESOLVE", "min": 1, "max": 1,
  "query": { "zone": "BATTLEFIELD", "card_types": ["Creature"], "controller": "YOU" } }

{ "selector": "EACH", "when": "RESOLVE",
  "query": { "zone": "BATTLEFIELD", "card_types": ["Creature"] } }

{ "selector": "QUERY", "duration": "STATIC",
  "query": { "zone": "BATTLEFIELD", "card_types": ["Creature"], "controller": "SOURCE_CONTROLLER" } }

{ "selector": "RANDOM", "zone": "HAND", "count": 1 }
```

`EACH` and `QUERY` never construct a `PlayerDecision`. `TARGET`, `UP_TO`, and `ANY_NUMBER` construct one during `CASTING`. `CHOOSE` constructs one during resolution. `RANDOM` calls `RngStream`.

### 5.2 What makes a target illegal

Apply all of these when building `candidates`, and again when the spell resolves:

- Wrong zone. Battlefield creatures are not in the graveyard.
- Wrong type, subtype, supertype, color, controller, power, or toughness, per the text, using the **snapshot**, not the printed line.
- Hexproof: an opponent of the permanent’s controller cannot target it. Its controller can. Hexproof from blue stops blue sources only.
- Shroud: nobody can target it, including its controller.
- Protection from a quality the source has (color, card type, name): cannot target, and also cannot damage, enchant/equip, or block.
- Ward does **not** make the target illegal. The spell can target it. Ward triggers and may counter the spell unless the cost is paid.
- A spell cannot target itself (CR 115.5).
- “Another” excludes the source object.
- An already chosen object cannot fill a second slot of the same “target” word (CR 115.3).

### 5.3 Fizzle

On resolution, before any effect:

```
if the spell has one or more chosen targets
    and every one of them is now illegal:
        move the spell to the graveyard
        do not run effects
        do not "you may"
else:
        drop the illegal ones
        run effects on the legal ones
```

A mode that was not chosen does not exist for this check.

---

## 6. Modal spells and the ability record

One `Ability` is one spell face, one activated ability, or one triggered ability. Modes are data on that ability. They are not separate cards.

```gdscript
# Target shape. StringNames match the JSON IR.
# Ability (exists)
#   kind: SPELL | ACTIVATED | TRIGGERED | STATIC | REPLACEMENT | MANA
#   costs: Array[AbilityCost]
#   targets: Array[Dictionary]     # only slots used by chosen modes are filled
#   effects: Array[AbilityEffect]  # or per-mode lists
#   modes: Array[ModeSpec]
#   choose: { min, max, distinct, entwine }
#   trigger: Dictionary
#   replacement: Dictionary

# ModeSpec
#   mode_id: StringName
#   text: String
#   targets: Array
#   effects: Array[AbilityEffect]
#   requires: Array[Condition]   # "if you control a Goblin", checked when?

# StackEntry (exists) gains:
#   modes: Array[StringName]
#   x: int
#   cursor: int
#   did: bool
#   choices: Dictionary
#   costs_paid: Dictionary
```

### 6.1 How common scaffolds map

| Printed | `choose` | When | Resolution |
|---|---|---|---|
| Choose one — | min 1 max 1 distinct | Cast or activate | Run that mode’s effects only |
| Choose two — | min 2 max 2 distinct | Cast or activate | Run chosen modes in **printed** order |
| Choose one or more — | min 1 max -1 distinct | Cast or activate | Printed order |
| Choose one or both — | min 1 max 2 | Cast or activate | Printed order |
| Entwine {cost} | min 1 max 1, unless entwine paid, then all modes | The entwine payment is an optional additional cost at cast | If paid, every mode is chosen and all of those targets are chosen |
| “You may” | not a mode | Resolution | `MAY` decision, sets `did` |
| “Unless you pay {2}” | not a mode | Resolution | The **affected** player gets `MAY_PAY`. If they pay, the bad instruction is skipped |
| “Instead” | not a mode | Replacement, no stack | The original event does not happen. `did` is not used |
| “Then” | sequence link | Resolution | Next instruction runs even if the previous one affected nothing |
| “If you do” | sequence link gated on `did` | Resolution | Next instruction runs only if the previous may/payment/verb happened |
| “Otherwise” | else link | Resolution | Runs if the condition instruction did not |
| Kicker / multikicker | not modes | Cast, optional additional cost | Store `kicked: bool` or `kicker_count: int`. Later instructions read it. They do not ask again |

JSON sketch for a modal burn/draw:

```json
{
  "ability_id": "modal_example",
  "kind": "SPELL",
  "choose": { "min": 1, "max": 1, "distinct": true },
  "modes": [
    {
      "mode_id": "draw",
      "effects": [{ "kind": "DRAW", "params": { "n": 1 } }]
    },
    {
      "mode_id": "burn",
      "targets": [{ "id": 0, "selector": "TARGET", "kind": "ANY_TARGET", "min": 1, "max": 1 }],
      "effects": [{ "kind": "DEAL_DAMAGE", "params": { "n": 2, "target": 0 } }]
    }
  ]
}
```

“If you do” sketch:

```json
"effects": [
  { "kind": "MAY", "params": { "then": "sacrifice" } },
  { "kind": "SACRIFICE", "params": { "query": { "card_types": ["Creature"], "controller": "YOU" }, "link": "sacrifice" } },
  { "kind": "DRAW", "params": { "n": 1, "if_you_do": "sacrifice" } }
]
```

The executor refuses to run `DRAW` unless the sacrifice instruction set `did` for link `sacrifice`. It also refuses to run `SACRIFICE` until the `MAY` returns yes.

---

## 7. Conditions

Not every “if” is a trigger, and not every trigger is an “if.”

| Wording | Engine object | Checked | Stack? |
|---|---|---|---|
| If [condition], [effect] | `Condition` gate on an instruction, checked as the spell resolves | Once, on resolution | Already on the stack |
| Whenever [event], [effect] | `TRIGGERED` ability | When the event happens, and again on resolution if an intervening “if” exists | A new stack object |
| When [event], [effect] | Same as whenever | Same | Same |
| At the beginning of [step] | `TRIGGERED` with `on: STEP_BEGIN` | As the step begins, before priority | Yes. The step does not “do the ability” in place |
| As long as [condition] | Static `ContinuousEffect` or a static permission, with a condition | Every time something reads the characteristic or asks if the permission is on | No |
| While [condition] | Same as as long as | Continuously | No |
| Until end of turn | `DurationType.END_OF_TURN` | Removed in cleanup | No |
| Until your next turn | `DurationType.UNTIL_YOUR_NEXT_TURN` | Removed as that player’s next turn begins | No |
| Unless [player pays / does] | `MAY_PAY` or `MAY` offered to that player. Success skips the instruction | On resolution | Already on the stack |
| If you control a Goblin | `Condition` counting a query | On resolution, or continuously if it is “as long as” | Depends on the parent |
| If you cast it from your hand | Cast-zone flag on the `StackEntry` | The spell knows its origin zone | The spell is on the stack |
| If this creature attacked this turn | Flag `attacked_this_turn` on the `GameObject`, set at declare attackers | When the ability resolves or when the static is evaluated | Depends |
| If a creature died this turn | Game log / turn flag “a creature died”, set by a battlefield → graveyard event | On resolution | Depends |
| Intervening if: “Whenever you draw a card, if you have no cards in hand, …” | The if is part of the trigger condition | Once to put the trigger on the stack, again as it resolves. False the second time → remove it, no effect | Yes |

“As long as you control a Goblin, creatures you control get +1/+1” is one static continuous effect whose query is active only while `Query.count` of Goblins you control is ≥ 1. It updates without a stack object when the last Goblin leaves.

“At the beginning of your upkeep, if you control a Goblin, draw a card” is a trigger with an intervening if. No Goblin as upkeep starts → the trigger is not put on the stack. Goblin dies in response → on resolution the if fails and the draw does not happen.

Store conditions as data:

```gdscript
{ "op": "CONTROL", "query": { "card_types": ["Creature"], "subtype": "Goblin" }, "n": 1 }
{ "op": "CAST_FROM", "zone": "HAND" }
{ "op": "ATTACKED_THIS_TURN", "object": "SOURCE" }
{ "op": "EVENT_THIS_TURN", "event": "CREATURE_DIED" }
{ "op": "LIFE_AT_LEAST", "who": "YOU", "n": 30 }
{ "op": "NOT", "cond": { } }
```

The executor evaluates `op`. Cards do not ship their own GDScript.

---

## 8. Triggers

A trigger is an ability that waits for an event. The event does not resolve the ability. The ability becomes a `StackEntry` of kind `TRIGGERED`, then players get priority, then it resolves.

```
EVENT
→ collect matching abilities (source must be in the right zone to see the event)
→ the next time a player would get priority:
     state-based actions
     put pending triggers on the stack, APNAP
     if one player has several, THAT PLAYER orders them (a PlayerDecision)
→ active player gets priority
→ later, on resolution, run the ability's effects (which may pause for choices)
```

`TriggerManager._put_trigger` currently pushes immediately inside `on_spell_cast`. The rules-correct place is a pending list that flushes at the priority gate. Ordering is a player choice when one player owns two or more triggers from the same event. Do not use ability-id sort as the rules.

| Name | Event the engine must emit | Source usually in | Notes |
|---|---|---|---|
| ETB | `ZONE_CHANGE` into `BATTLEFIELD` | The entering object, or “another creature enters” watchers already on the battlefield | “As ~ enters” is not this. It is a replacement during the move |
| LTB | `ZONE_CHANGE` leaving `BATTLEFIELD` to anywhere | Last known information of the leaving object | Includes exile, bounce, graveyard, command zone |
| Dies | `ZONE_CHANGE` battlefield → graveyard | Last known information | Exile is not death. Command-zone replacement means it did not die. Tokens do die, then cease to exist |
| Attacks | `DECLARE_ATTACKER` | Battlefield | “Whenever ~ attacks” sees this creature declared as an attacker. It does not wait for damage |
| Blocks | `DECLARE_BLOCKER` | Battlefield | The blocker or “becomes blocked” |
| Deals combat damage | `DAMAGE` with `combat = true` | Battlefield, using last known info if it left in between | First strike and regular are separate events. Lifelink is not this trigger |
| Deals damage | `DAMAGE` combat or not | As printed | Burn spells use this |
| Casts a spell | `SPELL_CAST` after the spell becomes cast | Battlefield watchers | Already implemented. Copies of spells also cast when the copy is created by an effect that says “you may cast” |
| Casts a creature spell | `SPELL_CAST` filtered to snapshot card type Creature | Battlefield | A creature spell is a spell on the stack, not a permanent |
| Draws a card | `DRAW` | Battlefield, or “whenever you draw” on a permanent you control | One event per card |
| Discards | `DISCARD` | As printed | Mill does not match |
| Gains life | `LIFE_CHANGE` cause gain | As printed | Lifelink gain counts |
| Loses life | `LIFE_CHANGE` cause loss | As printed | Damage to a player is also loss of life, so both “dealt damage” and “loses life” see it |
| Takes damage | `DAMAGE` to that player or permanent | As printed | “Lose life” does not match |
| Creature dies | Dies, filtered to creature | Watchers on the battlefield | The dying creature’s own “when this dies” also matches, from last known info |
| Permanent enters | ETB, any permanent type | Watchers | Not only creatures |
| Permanent leaves | LTB | Watchers | |
| Beginning of upkeep | `STEP_BEGIN` step `UPKEEP` | Battlefield as the step begins | Goes on the stack. The untap step has already happened with no priority |
| Beginning of draw step | `STEP_BEGIN` step `DRAW`, before the turn-based draw | Battlefield | Then the player draws, which is another event |
| Beginning of combat | `STEP_BEGIN` step `BEGIN_COMBAT` | Battlefield | Before attackers are declared |
| End step | `STEP_BEGIN` step `END` | Battlefield | “At the beginning of the next end step” is a delayed trigger created earlier, not a static duration |

Delayed trigger: “at the beginning of the next end step, exile ~” is created by the resolving effect as a pending trigger bound to a specific object and a specific future step. It is not an `until_eot` continuous effect. Unearth uses this.

“This ability triggers only once each turn” is a flag on the source object, cleared in cleanup.

Intervening-if and “only once” are properties of the trigger record:

```json
"trigger": {
  "on": "DRAW",
  "filter": { "player": "SOURCE_CONTROLLER" },
  "intervening_if": { "op": "HAND_SIZE", "who": "YOU", "n": 0, "cmp": "EQ" },
  "once_per_turn": true
}
```

---

## 9. Stack and resolution

The loop the engine has to run after every submitted action that might have changed state:

```
PLAYER ACTION
→ if the action is a choice the engine is waiting on:
     store it, continue the paused cast or the paused resolution
→ otherwise the action may put a STACK OBJECT on MagicStack
→ STATE-BASED ACTIONS
→ flush TRIGGERS onto the stack (APNAP, player order choice)
→ PRIORITY to the active player
→ RESPONSE (cast, activate, or pass)
→ if someone did something, back to STATE-BASED ACTIONS
→ if every player passed in succession:
     if the stack is empty:
         the turn manager advances the step (some steps have a turn-based action first)
     else:
         RESOLUTION of the top StackEntry, instruction by instruction
         a PlayerDecision pauses this and does not pass priority
         when the entry finishes, it leaves the stack
         STATE-BASED ACTIONS
         TRIGGERS
         PRIORITY to the active player
```

Priority order is turn order starting with the active player (APNAP). In 1v1 that is active, then the other, then repeat. A pass is `GameAction.PASS_PRIORITY`. One pass does not resolve the spell. All players must pass with the stack untouched.

What must not happen: `AbilityExecutor.resolve()` walking every effect and mutating `GameState` in the same call that noticed the spell, while a `MAY`, a scry, or a sacrifice choice is still unanswered.

Mana abilities are the exception that does not use the stack (CR 605). They resolve inside payment or inside priority without a `StackEntry`. They cannot be responded to. `ACTIVATE_MANA_ABILITY` already exists.

Turn-based actions that are not stack objects: untap, draw for the turn, declare attackers, declare blockers, combat damage. Each of those can require a `PlayerDecision` (which attackers, which blockers, how damage is assigned) and then emit events that create triggers.

Cleanup: remove marked damage, expire `END_OF_TURN` effects, then if the hand is over the maximum (normally 7) that player chooses discards (`DecisionKind.DISCARD`) until the hand is at maximum. If any SBA or trigger happens during cleanup, players get priority and there is another cleanup afterward. “Until end of turn” is still active during the end step and expires in cleanup.

---

## 10. Continuous effects

Printed characteristics live on `CardDefinition` and do not change. Everything else is an effect with a layer, a timestamp, a duration, and either a fixed object list or a query.

CR 613 order, applied inside `LayerManager.snapshot`:

| Layer | What | Example |
|---|---|---|
| 1 | Copy | “Copy of target creature”, mutate’s printed face |
| 2 | Control | “Gain control until end of turn” |
| 3 | Text | “Gain all creature types” is not text; text change is “has ‘{T}: draw a card’” style word replacement |
| 4 | Type, supertype, subtype | Crew adds Creature. “Becomes an artifact” |
| 5 | Color | “Becomes red” |
| 6 | Add or remove abilities | “Gains flying”, “loses all abilities” |
| 7a | Characteristic-defining power/toughness | `*/*` equal to cards in hand |
| 7b | Set power/toughness | “Base power and toughness become 3/3” |
| 7c | Modify power/toughness | “Gets +3/+3”, “gets -3/-3” |
| 7d | Counters | +1/+1 and −1/−1 counters |
| 7e | Switch | “Switch power and toughness” |

Within a layer, timestamps order the effects. Dependencies exist (a later effect changes what an earlier effect applies to); the snapshot must handle the common case “lose all abilities” removing the ability that would have generated another effect.

Durations:

| DurationType | Removed when |
|---|---|
| `STATIC` | The source leaves the battlefield or its static ability no longer applies |
| `END_OF_TURN` | Cleanup of the current turn |
| `UNTIL_YOUR_NEXT_TURN` | The controller’s next turn begins |
| `UNTIL_SOURCE_LEAVES` | That object leaves |
| `WHILE_CONDITION` | The condition is false. The effect object can stay and report inactive |
| `PERMANENT` | A one-shot that created a new base state which itself has no expiry. Still not a write to `CardDefinition`, because zone change drops it with the object. Counters are the usual “permanent” marker |
| `END_STEP_DELAYED` | This is a delayed trigger, not a continuous effect |

Control-changing effects are layer 2. They change `controller_id` as seen by the game, and they expire on their duration. The object’s `owner_id` does not change. A zone change still goes to the **owner’s** graveyard or hand.

“Gain flying until end of turn” is layer 6, duration end of turn. Combat looks at the snapshot’s keywords, not `CardDefinition.keywords`.

“Creatures you control get +1/+1” uses a query and `STATIC`. The set is not frozen. “Each creature gets +1/+1 until end of turn” freezes the object ids that matched on resolution, and those objects keep the bonus even if control changes, until cleanup. Those are different `ContinuousEffect` values: `query` versus `object_ids`.

Read path for power:

```
printed = definition.power, or copiable power if this is a copy
apply layer 7a if a CDA exists
apply 7b sets in timestamp order
apply 7c modifiers in timestamp order
apply 7d counters
apply 7e switch
that integer is the power
```

Damage is not in this list. Damage is `damage_marked`, compared to snapshot toughness by SBA.

---

## 11. Zones

`EngineEnums.ZoneId`: `LIBRARY`, `HAND`, `BATTLEFIELD`, `GRAVEYARD`, `EXILE`, `STACK`, `COMMAND`.

| Zone | Whose | Public face | Order matters |
|---|---|---|---|
| Library | Player | No | Yes. Top and bottom are real |
| Hand | Player | Owner only | No |
| Battlefield | Shared | Yes | No, except timestamps |
| Graveyard | Player | Yes | Yes. Top is the most recent |
| Exile | Player | Yes, unless face-down | No, except linked exile groups |
| Stack | Shared | Yes | Yes. Top resolves |
| Command | Player | Yes | No |

`ZoneManager.move` creates a new `object_id` and drops the old one. That is correct (CR 400.7). Callers must not keep using the old id after a move.

What carries onto the new object:

| Carries | Does not carry |
|---|---|
| Owner | Controller, unless the destination sets it (battlefield under the effect’s controller) |
| Commander flag, so command-zone and commander-damage still know | Damage marked |
| Face-down status only if the move says it stays face-down | Tap status |
| | Counters |
| | Attachments (they unattach; auras then die as SBA if they are on the battlefield unattached) |
| | “Summoned this turn”, attacked this turn, targets pointing at the old id |
| | Continuous effects that named the old id, unless the effect says it tracks the object across zones (rare, and explicit) |

`linked_from` can record the previous id for “return the exiled card” links. The link is data on the effect, not an excuse to reuse the id.

Legal moves are whatever the effect says. There is no general “cards may move from hand to graveyard” permission outside a verb (discard, cycle cost, discard cost). Casting a spell is hand (or command, or graveyard for flashback) → stack. Resolving a permanent spell is stack → battlefield. Resolving an instant or sorcery is stack → graveyard. Countering a spell is stack → graveyard (or exile, if the counter says exile).

Command zone, Commander format:

- The commander starts there.
- Casting it from the command zone is a real cast. Additional cost `{2}` times previous casts from the command zone (`commander_cast_count`).
- If a commander would move to hand, graveyard, library, or exile from anywhere, its owner may choose the command zone instead. That choice is a replacement decision. If they take it, the commander did not go to the graveyard and did not die.
- Command-zone objects are not on the battlefield and do not apply static abilities.

Tokens that are not on the battlefield cease to exist as a state-based action (next section). The move to graveyard or exile still happens first, so dies triggers can see a token death, and then the token object is removed from that zone.

---

## 12. Token system

A token is a `GameObject` with `is_token = true` and a `CardDefinition` that holds its characteristics. It is not a sprite and not a counter.

Creation:

1. Resolve the effect far enough to know the token’s copiable values (catalog id, or copy-of).
2. Apply “except” modifiers to those values.
3. `zones.create` on `BATTLEFIELD` with controller, owner, tapped flag, `is_token`, and any counters the effect puts on as it enters.
4. Apply “enters tapped” / “enters with counters” during the create.
5. ETB triggers of the token and of other permanents go to the pending trigger list.
6. The creating spell then continues to its next instruction.

Copying: section 4.27. The token’s definition is the copied characteristics plus exceptions. Do not store “copy of object 41” and read object 41 later for power.

Stats and abilities: on the token’s definition and keywords, then modified by layers like any permanent. A 1/1 Goblin that gets Giant Growth is still a 1/1 in the definition and +3/+3 in layer 7c.

Controller: the effect’s controller unless “under an opponent’s control.” Owner: the player under whose control it entered. If control changes later, owner stays.

Entering: a normal battlefield entry. Summoning sickness applies. Haste on the token skips it. “Create a tapped token” sets `tapped` before anyone can activate a tap ability.

Dying: battlefield → graveyard is a real zone change. “When a creature dies” sees the token. “When a creature card is put into a graveyard” does **not**, because a token is not a card.

Leaving: battlefield → anywhere else is an LTB. Bounce of a token still causes the zone change and then cease-to-exist.

Cease to exist: state-based action. A token in any zone other than the battlefield is removed from the game. It does not stay in exile for “cards in exile” counts. It does not return from the graveyard. There is no object left to target.

Triggers on tokens use the same `TriggerManager` as cards. The token’s definition needs its abilities in `CardDefinition.abilities` (the Drake’s flying is a keyword; a Clue’s draw ability is an activated ability on the token definition).

Predefined tokens (Investigate, Food, Treasure, Blood, Clue) are catalog entries plus those activated abilities, not special UI widgets. See section 14.

---

## 13. Counters

`GameObject.counters: Dictionary` maps a counter name to an integer. Absence and zero are the same. The dictionary is on the object, so `ZoneManager.move` leaves it behind by creating a new object.

| Counter | Effect | Not the same as |
|---|---|---|
| `+1/+1` | Layer 7d +1 power +1 toughness each | A continuous +1/+1 |
| `-1/-1` | Layer 7d −1/−1 each | A continuous −1/−1. Annihilation SBA: remove one +1/+1 and one −1/−1 together until one side is zero |
| `loyalty` | Planeswalker loyalty. 0 loyalty → graveyard as SBA. Loyalty abilities cost `+N` or `−N` as a cost, not as damage | Life |
| `charge` | No rules meaning except what cards say. Store the int | Mana |
| `quest` | Same, storage only | |
| Named counters (`lore`, `ki`, `time`, …) | Storage only, plus whatever ability looks them up | Keywords |
| `poison` on a **player** | 10 poison → that player loses as SBA. Poison is not a creature counter. Player state needs `poison: int` | Damage |
| `energy` on a **player** | `{E}` counters. Pay energy is a cost that removes them. Not life | Mana |

Putting, removing, doubling, and moving counters are instructions:

```
PUT_COUNTER   { name, n, objects }
REMOVE_COUNTER { name, n, objects }  # cannot go below zero; "remove all" is a separate op
MOVE_COUNTER  # take from one object and put on another, as one instruction
```

“Remove a counter” when several kinds are present is a player choice (`DecisionKind.COUNTER_KIND`) unless the card names the kind.

Do not put counters in `ContinuousEffect`. Do not put “gets +1/+1 until end of turn” in `counters`. Snapshot reads both, at different sublayers.

Proliferate, if added later: the player chooses any number of permanents and players with a counter, then each chosen one gets another counter of each kind already on it. That is a decision plus a put per kind. It is not “+1 to everything.”

---

## 14. Keywords

Keywords are behavior the engine tracks, not reminder text. A keyword can come from the printed card, a token definition, or a layer-6 effect. Readers use the snapshot.

“What to track” means extra state beyond “the object has this keyword right now.”

| Keyword | Behavior | Track | Decision |
|---|---|---|---|
| Flying | Can be blocked only by creatures with flying or reach | Keyword on the snapshot. Combat legality reads it | Blocker declaration rejects illegal blockers |
| Reach | Can block flying. Does not grant flying | Keyword | None |
| Trample | When assigning combat damage, lethal damage must be assigned to blockers before the rest can be assigned to the attacked player or planeswalker or battle. More than lethal may be assigned to blockers | Keyword. Assignment uses snapshot toughness, marked damage, deathtouch | `ASSIGNING_COMBAT_DAMAGE` |
| Haste | Ignores summoning sickness for attacking and for activating abilities with `{T}` in the cost | Keyword. `summoned_this_turn` still set, haste exempts | None |
| Vigilance | Attacking does not tap it | Keyword. Declare-attackers does not set `tapped` | None |
| Lifelink | Damage it deals causes its controller to gain that much life as part of the damage event | Keyword read by the damage event | None |
| Deathtouch | Any amount ≥ 1 dealt to a creature is lethal. For trample assignment, 1 is lethal | Keyword read by SBA and by assignment | None |
| First strike | Deals combat damage in the first-strike step only | Keyword. Turn manager runs that step only if any creature in combat has first or double strike | Assignment in that step |
| Double strike | Deals in the first-strike step and the regular step | Keyword | Two assignments |
| Menace | Must be blocked by two or more creatures if it would be blocked | Keyword. Block declaration legality | Blockers |
| Defender | Cannot attack | Keyword. Attacker legality | None |
| Flash | This spell may be cast any time an instant could | Keyword on the **spell** characteristics. Cast timing in `_timing_ok_to_cast` | None |
| Ward {cost} | When this permanent becomes the target of a spell or ability an opponent controls, that spell or ability is countered unless its controller pays {cost}. The ward ability triggers and goes on the stack above the spell | Keyword plus the cost. Trigger on “became the target” | `MAY_PAY` for the spell’s controller. Decline → counter the spell (stack → graveyard) |
| Hexproof | Opponents cannot target it. Does not stop non-targeting effects, sacrifice, or its controller’s targets | Keyword in target validation | None. Validation just excludes it |
| Shroud | Nothing can target it | Keyword in target validation | None |
| Indestructible | “Destroy” and lethal damage do not destroy it. Toughness ≤ 0, sacrifice, exile, and the legend rule still remove it | Keyword checked by destroy and by the lethal-damage SBA | None |
| Protection from [quality] | Cannot be targeted, dealt damage, enchanted, or equipped by that quality, and cannot be blocked by creatures of that quality | The quality (color, type, name, “everything”). Damage prevention plus target filter plus block filter plus attach filter | None |
| Prowess | Whenever you cast a noncreature spell, this gets +1/+1 until end of turn | Trigger `SPELL_CAST` filtered to noncreature. Effect is a 7c `END_OF_TURN` +1/+1, not a counter | None |
| Exalted | Whenever a creature you control attacks alone, that creature gets +1/+1 until end of turn | Trigger on attack, condition “exactly one attacker you control” | None |
| Convoke | While casting, you may tap untapped creatures you control. Each pays for `{1}` or for one mana of a color it is | Payment option inside `PAYING_COSTS` | Which creatures to tap |
| Delve | While casting, you may exile cards from your graveyard. Each pays for `{1}` | Payment option. Exiled cards leave the graveyard as a cost | Which cards to exile |
| Cycling {cost} | Activated ability usable from the hand: pay {cost}, discard this card: draw a card. Discard is the cost. Draw is the effect, on the stack | Activated ability, zone restriction hand | Only if the cost itself chooses (a mana color, a sacrifice) |
| Equip {cost} | Activated ability, sorcery timing: pay {cost}, attach to target creature you control. Unattaches from the previous creature | Attachment id list on both objects. Target at activation | Target creature you control |
| Enchant [quality] | Aura spell targets a legal object as it is cast. An aura put onto the battlefield without being cast chooses a legal object as it enters, and that choice is not a target. Unattached aura on the battlefield goes to the graveyard as SBA | Attachment. `enchant` restriction on the definition | Cast target, or an enters choice |
| Crew N | Activated: tap any number of creatures you control with total power ≥ N: this Vehicle becomes an artifact creature until end of turn. Printed power and toughness start applying | Layer 4 add Creature, duration end of turn. Power used to pay is the snapshot at payment | Which creatures to tap |
| Mutate {cost} | Cast alternative from hand onto a non-Human creature you own. The spell merges into that permanent instead of entering as a separate object. Top component’s copiable values show; abilities of every component apply | A component list on the permanent, order, which is on top. Not a single overwritten definition | Which creature to mutate onto, at cast. Human is illegal |
| Disturb {cost} | Cast the back face from the graveyard for the disturb cost. If it would leave the battlefield, exile it instead | `face_id`. Replacement on LTB | None beyond paying |
| Transform | The same battlefield object flips `face_id`. Not a zone change, so it keeps counters, damage, and id. Characteristics swap to the other face | `face_id` plus a two-face definition. “Whenever this transforms” is a trigger | Only if a cost or a “you may transform” is printed |
| Adventure | The card has an instant/sorcery adventure and a permanent. Cast the adventure from hand; on resolution exile it (do not put it in the graveyard). While exiled after an adventure resolved, it may be cast as the permanent | A flag “on adventure exile, castable as the creature” on the exile object | Which face to cast, from hand |
| Foretell {cost} | Special action on your turn: pay {2}, exile this from hand face-down. Later cast it from exile for its foretell cost, revealed as it is cast. Only its owner may look at it while foretold | Face-down exile, owner permission, foretell cost. Not a stack object for the foretell action itself | None at foretell time. Casting later is a normal cast |
| Kicker {cost} | Optional additional cost at cast. “If this spell was kicked” reads the flag on resolution. Multikicker stores a count | `kicked` or `kicker_count` on the `StackEntry`, and on the permanent if a permanent spell needs it later | Whether to pay, and how many times for multikicker, during `PAYING_COSTS` |
| Flashback {cost} | Cast from graveyard for the flashback cost. If it would leave the stack, exile it instead of putting it in the graveyard | Origin zone and a replacement on stack → anywhere | None beyond paying |
| Escape {cost} | Cast from graveyard. Additional cost: exile N **other** cards from the graveyard, plus mana | Those exiles are costs before the spell is cast | Which other graveyard cards |
| Unearth {cost} | From graveyard: return this to the battlefield. It gains haste. Exile it at the beginning of the next end step, or if it would leave the battlefield | Delayed end-step trigger + LTB replacement to exile. Haste is layer 6 while that object exists | None beyond paying |
| Cascade | When you cast this, exile from the top until you exile a nonland card with lesser mana value. You may cast that card without paying its mana cost. Put the exiled cards on the bottom in a random order | Trigger on cast. A temporary exile set. `MAY` cast. RNG for the bottom | Whether to cast the discovered spell. If it has targets or modes, those are a new cast |
| Cascade-like | Discover, “cascade, but …” , “you may cast that card and if you don’t put it into your hand.” Read the printed difference. Do not alias them to Cascade | Same machinery, different destination if they decline, different filter (mana value ≤ N for discover) | The may, plus the cast’s own choices |
| Investigate | Create a Clue token | A token create | None |
| Clue | Artifact token. `{2}, Sacrifice this artifact: Draw a card.` Sacrifice is a cost | Token definition + activated ability | None beyond paying |
| Food | `{2}, {T}, Sacrifice this artifact: You gain 3 life.` | Token + activated ability. Tap and sacrifice are costs. Gain life is the effect | None |
| Treasure | `{T}, Sacrifice this artifact: Add one mana of any color.` Mana ability | Token + mana ability | Which color, during the mana ability (a real choice, then mana is added immediately) |
| Blood | `{1}, {T}, Discard a card, Sacrifice this artifact: Draw a card.` | Token + activated ability | Which card to discard, as a cost |
| Explore | Reveal the top card. Land → put it into the hand. Nonland → put a +1/+1 counter on the exploring permanent, and that player **may** put the revealed card into the graveyard. If they do not, it stays on top. Explore still happened if parts were impossible | Reveal (public), then a branch, then `MAY` for the graveyard only. The counter on a nonland is not optional | Only the graveyard may, and only for a nonland |

Flying on the Drake token is already `keywords: ["Flying"]` in `TokenCatalog`. Combat must read that array (plus layer 6). A keyword that combat ignores is still unimplemented: leave related card text `unparsed` rather than resolving a partial combat trick that skips the keyword.

---

## 15. DO NOT AUTOMATE PLAYER CHOICES

If the instruction matches a row, the engine stops and builds a `PlayerDecision`. It does not roll, it does not take the first legal object, and it does not skip the prompt because only one candidate exists. One candidate still requires a submitted action, so the log shows who chose it. The only silent paths are the ones marked automatic in section 4 (`RANDOM`, `EACH`, `ALL`, computed X, plain draw, mill, shuffle).

| Wording | DecisionKind | Who answers | Candidates | Min / max | Decline |
|---|---|---|---|---|---|
| Choose | The kind named after it (type, player, object, color, mode) | The player the effect names, usually the controller | The legal set for that kind | As printed, default 1/1 | Only with “up to”, “may”, or “any number” |
| Select | Same as choose. Cards use both words | Same | Same | Same | Same |
| Target / targets | `TARGET` | Caster or activator, at cast time | Objects and players passing CR 115 | The printed count | Only “up to” / “any number” include 0 |
| May / you may | `MAY` | The player allowed to | Yes and No | 1 | No is the decline |
| Up to N | The underlying target or choice | That player | Legal set | 0 / N | Choosing fewer than N, including 0, is legal |
| Any number | The underlying target or choice | That player | Legal set | 0 / unlimited, distinct unless the card allows repeats | Empty confirm is legal |
| One of / choose one | `MODE` or object | That player | The printed options | 1 / 1 | Cancel cast only, if still casting |
| Two of / choose two | `MODE` or object | That player | Printed options | 2 / 2 distinct | Cannot confirm with one |
| A card | `OBJECT` in the named zone | The player who owns the decision | That zone, filtered | 1 / 1 | If none, the instruction fails rather than picking |
| A creature | `OBJECT` or `TARGET` | See the word target | Battlefield creatures, filtered | As printed | As printed |
| A player | `PLAYER` or target player | Caster, unless “that player” then acts | Seats matching the filter | 1 / 1 | “Up to one player” may decline |
| A permanent | `OBJECT` or `TARGET` | Same split | Battlefield, any permanent type | As printed | As printed |
| A spell | `TARGET` usually, on the stack | Caster | Spells on the stack matching the filter | 1 / 1 | Cannot cast the counter with no legal spell |
| A type / creature type / card type / land type | `CREATURE_TYPE` or `CARD_TYPE` or the matching subtype list | The choosing player | The type list, not the board, unless restricted | 1 / 1 | No |
| A color | `COLOR` | The choosing player | W U B R G, minus exclusions | 1 / 1, or N if “one or more colors” | Only if optional |
| A mode | `MODE` | Caster or activator | `ModeSpec` list | The choose record | Cancel the cast |
| A cost / you may pay | `MAY_PAY` or a payment inside `PAYING_COSTS` | The player who would pay | Their mana, life, and legal cost objects | The cost | Optional costs may be declined. Mandatory additional costs cannot; the cast fails |
| A value / X / “any number” as a number | `NUMBER` | The player | Integers from min to max | One number | X = 0 is often legal. Declining the whole cast is `CANCEL_CAST` |
| Order | `ORDER` | The player | The set to order (triggers, top cards, attackers’ damage) | A full permutation | Must place every element |
| Reorder | `ORDER` on a known set (scry top and bottom) | The looking player | Those cards | Full placement | Must place every card |
| Reveal and choose | `REVEAL` is automatic if the set is determined; the choose is `OBJECT` inside the revealed set | The player told to choose | Only the revealed cards, filtered | As printed | “You may” can take none |
| Search | `SEARCH` | The searching player | Library, filtered, private | 1 unless “up to” or “any number” | Fail to find only when allowed or when no match |
| Sacrifice | `SACRIFICE` | The player told to sacrifice | Permanents they control matching the filter | The printed count | No legal permanent → the instruction does nothing. “You may sacrifice” can decline |
| Discard | `DISCARD` | The player who discards | Their hand, private until revealed | The printed count | Empty hand → nothing. Not optional unless “you may” |
| Discard at random | No decision | `RngStream` | The hand | 1 or N | Empty hand → nothing |
| Pay | `PAY_COST` | The player paying | Mana and cost objects | The bill | Mandatory: cancel the parent action. Optional: decline |
| Name (a card, a type) | `NAME` or a type decision | The naming player | Card-name catalog, or the type list. Not the battlefield | 1 | No, unless “you may name” |
| Declare attackers | `ATTACK` | Active player | Legal creatures, legal attack targets (opponent, planeswalker, battle) | Any number of legal attackers, including zero | Declaring none is legal |
| Declare blockers | `BLOCK` | Defending player | Legal blockers for each attacker | Zero or more, respecting menace, flying, reach | Blocking nothing is legal |
| Assign damage | `DAMAGE_ASSIGNMENT` | The controller of the dealing creature | The creatures it is in combat with, and the attacked player if trample or direct | A distribution of its power that respects lethal-before-trample | Must assign the full power |

`DECLARE` in attack and block steps is the same rule. `EngineMode.DECLARING_ATTACKERS` and `DECLARING_BLOCKERS` already exist. They must stay decisions. “Attack all legal” can be a **UI button** that fills the decision and still submits a `DECLARE_ATTACKERS` action. It must not be the engine’s default when the player has not chosen.

Special cases that look like choices and are not:

| Wording | Why it is silent |
|---|---|
| Each, every, all | The set is a query at resolution time |
| At random | `RngStream` |
| The top card | Determined position |
| You gain N / you lose N / draw N / mill N | Determined player and number |
| Shuffle | `RngStream` permutation |
| Gets +N/+N | No selection if the object was already determined |
| Where X is the number of … | `Query.count_objects` |

If a card mixes them (“each opponent chooses a creature they control”), the engine emits one decision **per opponent**, in turn order, and does not choose for them.

---

## 16. Recommended architecture

Keep one kernel. Extend the types that already exist rather than adding a second resolver.

```
CardDefinition          printed values, abilities, keywords     engine/cards/card_definition.gd
Ability                 one spell / activated / triggered       engine/abilities/ability.gd
AbilityEffect           one instruction                          engine/abilities/effect.gd
AbilityCost             one payment                              engine/costs/cost.gd
StackEntry              one object on MagicStack                 engine/stack/stack_entry.gd
PlayerDecision          one paused question     (add)
ContinuousEffect        one layer modifier                       engine/layers/continuous_effect.gd
GameObject              one zone object, counters, flags         engine/game_object.gd
PlayerState             life, poison, energy, commander damage   engine/player_state.gd
Query                   filters                                  engine/targeting/query.gd
```

### 16.1 Enums

Put shared enums on `EngineEnums` (`engine/enums.gd`). Effect and choice kinds can stay `StringName` in JSON so `IrLoader` remains data-driven; the enum is the closed set the loader checks.

```gdscript
enum ZoneId {
    LIBRARY, HAND, BATTLEFIELD, GRAVEYARD, EXILE, STACK, COMMAND,
}

enum EngineMode {
    GIVING_PRIORITY,
    CASTING,              # modes, targets, X, division
    ACTIVATING,
    PAYING_COSTS,         # mana, additional costs, kicker, convoke, delve
    AWAITING_DECISION,    # resolution-time and enters-time choices
    DECLARING_ATTACKERS,
    DECLARING_BLOCKERS,
    ASSIGNING_COMBAT_DAMAGE,
    CHOOSING_SBA,
    CHOOSING_REPLACEMENT,
    GAME_OVER,
}

enum EffectType {
    DRAW, MILL, GAIN_LIFE, LOSE_LIFE, DEAL_DAMAGE, PREVENT_DAMAGE,
    MOVE_ZONE, DESTROY, SACRIFICE, EXILE, DISCARD, REVEAL, LOOK,
    SCRY, SURVEIL, SEARCH, SHUFFLE, TAP, UNTAP,
    CREATE_TOKEN, CREATE_COPY_TOKEN, PUT_COUNTER, REMOVE_COUNTER,
    CREATE_CONTINUOUS_EFFECT, CREATE_PREVENTION, CREATE_DELAYED_TRIGGER,
    COUNTER_SPELL, ADD_MANA,
    MAY, MAY_PAY, IF_YOU_DO, BRANCH,
}

enum DecisionKind {
    MODE, TARGET, OBJECT, PLAYER, CREATURE_TYPE, CARD_TYPE,
    SUBTYPE, COLOR, NAME, NUMBER, ORDER,
    MAY, MAY_PAY, PAY_COST, SACRIFICE, DISCARD, SEARCH,
    SCRY, SURVEIL, COUNTER_KIND,
    ATTACK, BLOCK, DAMAGE_ASSIGNMENT,
}

enum Selector {
    TARGET, UP_TO, ANY_NUMBER, CHOOSE, EACH, ALL, QUERY, RANDOM, DETERMINED,
}

enum DurationType {
    INSTANT,          # one-shot, no leftover
    END_OF_TURN,
    UNTIL_YOUR_NEXT_TURN,
    STATIC,
    WHILE_CONDITION,
    UNTIL_SOURCE_LEAVES,
    PERMANENT,
}

enum TriggerType {
    SPELL_CAST, ZONE_CHANGE, ENTERS, LEAVES, DIES,
    ATTACKS, BLOCKS, DAMAGE, DRAW, DISCARD, MILL,
    LIFE_GAIN, LIFE_LOSS, COUNTER_ADDED,
    STEP_BEGIN, STEP_END, TURN_BEGIN,
}

enum ConditionOp {
    CONTROL, COUNT, CAST_FROM, ATTACKED_THIS_TURN,
    EVENT_THIS_TURN, LIFE, HAND_SIZE, KICKED, NOT, AND, OR,
}

enum CostType {
    MANA, TAP, UNTAP, SACRIFICE, DISCARD, EXILE, PAY_LIFE,
    REMOVE_COUNTER, PAY_ENERGY, LOYALTY, ADDITIONAL_MANA,
}

enum Keyword {
    FLYING, REACH, TRAMPLE, HASTE, VIGILANCE, LIFELINK, DEATHTOUCH,
    FIRST_STRIKE, DOUBLE_STRIKE, MENACE, DEFENDER, FLASH,
    WARD, HEXPROOF, SHROUD, INDESTRUCTIBLE, PROTECTION,
    PROWESS, EXALTED, CONVOKE, DELVE, CYCLING,
    EQUIP, ENCHANT, CREW, MUTATE, DISTURB, TRANSFORM,
    ADVENTURE, FORETELL, KICKER, FLASHBACK, ESCAPE, UNEARTH, CASCADE,
}

enum ResolutionStep {
    CHECK_TARGETS,     # fizzle before effects
    NEXT_INSTRUCTION,  # AbilityExecutor cursor
    WAITING_DECISION,
    FINISHED,
}
```

`ZoneId` and most of `EngineMode` already exist. `AWAITING_DECISION` is the addition that stops `resolve()` from finishing a choice spell in one call.

### 16.2 PlayerDecision and the action

```gdscript
# GameAction.Kind gains:
#   SUBMIT_DECISION
#   DECLINE_DECISION
# existing: CHOOSE_TARGETS, CONFIRM_PAY, CANCEL_CAST, CHOOSE_SBA, CHOOSE_REPLACEMENT

# state.awaiting while AWAITING_DECISION:
{
  "decision_id": 12,
  "kind": DecisionKind.SACRIFICE,
  "player_id": 0,
  "stack_id": 4,
  "min_count": 1,
  "max_count": 1,
  "optional": false,
  "candidates": [101, 102, 108],
  "hidden_from": [],
}

# SUBMIT_DECISION extra:
{ "decision_id": 12, "chosen": [102] }
```

Validation rejects a `chosen` id that is not in `candidates`, a count outside min/max, or a duplicate when `distinct` is true. On success the executor stores the ids and advances `StackEntry.cursor`.

### 16.3 StackEntry fields to add

```gdscript
var modes: Array[StringName] = []
var x: int = 0
var cursor: int = 0
var step: int = ResolutionStep.CHECK_TARGETS
var did_links: Dictionary = {}      # link id -> bool
var choices: Dictionary = {}        # "creature_type" -> "Goblin"
var waiting_decision: int = -1
```

`resolve_top()` becomes “resolve the next instruction of the top entry, or pause.” It only pops the entry at `FINISHED`.

### 16.4 Effect params that stay data

Every new `AbilityEffect.kind` gets an allow-list in `IrLoader`, the same way `DRAW` only allows `n`. A card file that needs a choice it cannot express stays `unparsed: true`.

Minimum params:

| Effect | Required params | Decision? |
|---|---|---|
| `DRAW` | `n` or `n_query` | No |
| `MILL` | `n`, `who` | No |
| `DEAL_DAMAGE` | `n`, `target` or `who` | Only if the recipient is not already a target slot |
| `LOSE_LIFE` / `GAIN_LIFE` | `n`, `who` | No |
| `CREATE_CONTINUOUS_EFFECT` | `layer`, `mod`, `duration`, and either `query` or `target` | No |
| `PUT_COUNTER` | `name`, `n`, `target` or `query` | No |
| `MAY` | `link` | Yes |
| `SACRIFICE` | `query`, `count` | Yes, unless count is “all” |
| `DISCARD` | `count`, `who`, `random` | Yes iff `random` is false and count is not “all” |
| `SCRY` / `SURVEIL` | `n` | Yes |
| `SEARCH` | `query`, `destination`, `shuffle`, `reveal` | Yes |
| `CREATE_TOKEN` | `token` or `copy_of`, `count` | Only for the copy target or a preceding type choice |
| `DESTROY` | `target` | No at resolution |
| `MOVE_ZONE` | `target` or `objects`, `to`, `controller` | No if the object is determined |

### 16.5 Who calls whom

```
submit(GameAction)
  legal for the current EngineMode only
  cast path:    CASTING decisions → PAYING_COSTS → push StackEntry → cast triggers
  activate path: same, mana abilities short-circuit
  decision path: fill StackEntry.choices / targets, resume cursor
  pass path:    priority_manager

resolve instruction
  match EffectType
  if PlayerDecision needed: set AWAITING_DECISION and return
  else: ZoneManager / damage / layers / counters
  do not call TriggerManager.on_* inline to resolve abilities
  enqueue events

after any event batch
  SbaManager.check          # may set CHOOSING_SBA and return
  TriggerManager.flush      # may set AWAITING_DECISION for trigger order
  PriorityManager.give
```

`GameView` exposes `awaiting` so the table can render the prompt. The table does not parse Oracle text and does not call `ZoneManager` itself.

### 16.6 Worked paths

**Giant Growth** — “Target creature gets +3/+3 until end of turn.”

```
CASTING: TARGET, one creature, hexproof applied
PAYING: {G}
STACK
both players pass
RESOLVE: targets still legal?
  CREATE_CONTINUOUS_EFFECT layer 7c, +3/+3, END_OF_TURN, object id
SBA
priority
```

No counters. No `definition.power` write.

**Choose a creature type anthem** — “As ~ enters, choose a creature type. Creatures of the chosen type get +1/+1.”

```
The permanent spell resolves and starts to enter
AWAITING_DECISION CREATURE_TYPE
store choices["creature_type"] on the new GameObject
then ETB triggers
STATIC ContinuousEffect, layer 7c, query subtype == chosen, duration STATIC
```

The choice is not a target and is not random.

**Diabolic Tutor** — search, reveal, hand, shuffle.

```
STACK (no targets)
RESOLVE:
  AWAITING_DECISION SEARCH, private library, filter none, allows_fail false if the card says "a card"
  reveal the chosen card to all
  MOVE_ZONE to HAND
  SHUFFLE
```

**Murder** — “Destroy target creature.”

```
CASTING: TARGET creature
RESOLVE: if illegal, fizzle to graveyard
  else DESTROY event
    indestructible → nothing
    else battlefield → owner graveyard
SBA, dies triggers, priority
```

**Dragon Fodder** — already the right shape. `CREATE_TOKEN` count 2, no decision. Two `GameObject`s.

**Krenko** — X is a query at resolution, not a choice. `CREATE_TOKEN` count query Goblins you control.

**Bone Splinters style** — “As an additional cost to cast this spell, sacrifice a creature. Destroy target creature.”

```
CASTING: target creature
PAYING: SACRIFICE decision, then mana
only then the spell is cast
RESOLVE: DESTROY the target
```

The sacrificed creature is already in the graveyard before anyone can respond. Its dies trigger goes on the stack **above** Bone Splinters.

**Opt** — “Scry 1, then draw a card.”

```
RESOLVE instruction 0: AWAITING_DECISION SCRY n=1
after submit: library order updated, no reveal
instruction 1: DRAW 1
```

Until that decision exists, the Scry ability stays `unparsed: true`. Do not implement Scry as “leave the card on top.”

---

## 17. Review checklist for a new card

Before an IR file is allowed to run:

1. Every “choose / target / may / up to / search / sacrifice / discard / pay / name / order” is either a `PlayerDecision` or `unparsed: true`.
2. Targets are chosen in `CASTING`, not inside `AbilityExecutor`.
3. Resolution choices pause `AWAITING_DECISION` and do not pass priority.
4. `+N/+N until end of turn` is layer 7c. `+1/+1 counter` is `counters`.
5. Damage, life loss, destroy, sacrifice, exile, and toughness ≤ 0 are different paths.
6. Zone changes go through `ZoneManager.move` / `create`. The old id is not reused.
7. Triggers are queued, not resolved inside the event.
8. Continuous effects are not written onto `CardDefinition`.
9. Tokens are `GameObject`s with `is_token`.
10. Random uses `RngStream`. Determined sets do not open a UI. Player sets always do.
