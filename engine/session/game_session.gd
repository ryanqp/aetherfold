class_name GameSession
extends RefCounted

const AiBlocks := preload("res://engine/session/ai_blocks.gd")

enum MatchStart {
	PRE_GAME,
	SHUFFLING,
	DRAWING_OPENING_HAND,
	MULLIGAN_DECISION,
	PUT_BACK,
	MAIN_GAME,
	## Before the opening hands: call heads or tails to decide who goes first (CR 103.1).
	COIN_FLIP,
}

var engine: RulesEngine
var db: CardDatabase
var view: TableView
var selected_id: String = ""
var difficulty: int = 1
var pending_draw_anim: bool = false
var pending_draw_card: Dictionary = {}
var last_error: String = ""
var match_start: int = MatchStart.PRE_GAME
var put_back_remaining: int = 0
var kept: Dictionary = {}
var debug_enabled: bool = false
var debug_lines: PackedStringArray = PackedStringArray()
var last_seed: int = 1
var skip_ai: bool = false
var you_seat: int = 0
## True while the bot's attack is paused for you to declare blockers.
var awaiting_blocks: bool = false
## True while you are picking which creatures attack.
var choosing_attackers: bool = false
## When true you click your library to take the draw-step card instead of getting it automatically.
var manual_draw: bool = false
## When on, a coin flip decides who goes first before the opening hands are drawn.
var coin_flip: bool = false
var first_player: int = 0
var flip_called: bool = false
var coin_heads: bool = true
var you_called_heads: bool = true
## Play-by-play shown in the History panel.
var history := GameHistory.new()


func dbg(msg: String) -> void:
	debug_lines.append(msg)
	if debug_lines.size() > 40:
		debug_lines.remove_at(0)


func can_play() -> bool:
	return match_start == MatchStart.MAIN_GAME


func start_table_demo(seed: int = -1) -> void:
	start_with_demo(null, seed)


func start_imported(deck: NormalizedDeck, rows: Dictionary, seed: int = -1) -> void:
	start_with_demo(DemoSetup.imported_vs_talrand(deck, rows), seed)


## Prints (to the Godot Output panel, not History) the cards in your deck that have rules text the engine doesn't act on yet.
## A question the table is showing before something happens (see table.gd): target choices and the
## optional reveal / life payment of a land. Empty when there is none.
var target_prompt: Dictionary = {}
var land_prompt: Dictionary = {}
var target_pending: bool = false


func _note_unread_cards() -> void:
	if db == null or engine == null:
		return
	var seen := {}
	var lines: Array = []
	for oid in engine.state.objects.keys():
		var obj: GameObject = engine.state.objects[oid]
		if obj == null or obj.owner_id != you_seat or obj.is_token or not (obj.definition is CardDefinition):
			continue
		var def := obj.definition as CardDefinition
		if seen.has(def.name):
			continue
		seen[def.name] = true
		var unread: Array = db.unread_lines(def)
		if not unread.is_empty():
			var first := str(unread[0])
			if first.length() > 70:
				first = first.substr(0, 67) + "..."
			lines.append("UNIMPLEMENTED_MECHANIC: %s — %s%s" % [def.name, first, " (+%d more)" % (unread.size() - 1) if unread.size() > 1 else ""])
	lines.sort()
	if lines.is_empty():
		return
	## Not shown in History any more (it buried the game log); the Godot Output panel has the list.
	print("[Aetherfold] %d cards have lines the engine doesn't read yet:" % lines.size())
	for l in lines:
		print("  " + str(l))


func start_with_demo(demo: DemoSetup, seed: int = -1) -> void:
	if seed < 0:
		seed = int(Time.get_unix_time_from_system()) ^ Time.get_ticks_usec()
		if seed == 0:
			seed = Time.get_ticks_msec()
	if demo == null:
		demo = DemoSetup.table_demo(seed)
	last_seed = seed
	debug_lines = PackedStringArray()
	db = demo.db
	engine = RulesEngine.new()
	engine.interactive_seats = [0]  ## you answer your own choices on screen; the rival decides for itself
	match_start = MatchStart.SHUFFLING
	history.clear()
	engine.manual_draw_seats = [you_seat] if manual_draw else []
	engine.setup_demo(demo, FormatRules.commander_1v1_table(), seed)
	_note_unread_cards()
	selected_id = ""
	pending_draw_anim = false
	pending_draw_card = {}
	put_back_remaining = 0
	kept = {0: false, 1: false}
	for p in engine.state.players:
		p.mulligan_count = 0
	var lib0: int = engine.library_size(0)
	var lib1: int = engine.library_size(1)
	dbg("Deck created: %d (library %d + commander 1)" % [lib0 + 1, lib0])
	dbg("Deck shuffled: true (seed %d)" % seed)
	if DemoSetup._scryfall() != null and bool(DemoSetup._scryfall().get("loaded")):
		dbg("Card source: Scryfall catalog")
	else:
		dbg("Card source: in-memory volunteer fallback")
	dbg("Rival library: %d + commander" % lib1)
	first_player = 0
	flip_called = false
	if coin_flip and not skip_ai:
		match_start = MatchStart.COIN_FLIP
		rebuild_view()
		return
	_deal_opening_hands()


## Seven cards each, then the keep-or-mulligan step.
func _deal_opening_hands() -> void:
	match_start = MatchStart.DRAWING_OPENING_HAND
	engine.draw_n(0, 7)
	engine.draw_n(1, 7)
	dbg("Opening draw: 7")
	dbg("Library remaining: %d" % engine.library_size(0))
	dbg("Rival library remaining: %d" % engine.library_size(1))
	kept[1] = not skip_ai
	match_start = MatchStart.MULLIGAN_DECISION
	rebuild_view()


## You call heads or tails; the coin decides who goes first (CR 103.1).
func call_coin(heads: bool) -> void:
	if match_start != MatchStart.COIN_FLIP or flip_called:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = last_seed ^ 0x51ED
	coin_heads = rng.randf() < 0.5
	you_called_heads = heads
	first_player = you_seat if coin_heads == heads else (1 if you_seat == 0 else 0)
	flip_called = true
	dbg("Coin: %s, you called %s, %s goes first" % ["heads" if coin_heads else "tails", "heads" if heads else "tails", "you" if first_player == you_seat else "Talrand"])
	rebuild_view()


## After the flip is shown: the winner takes the first turn, then the opening hands are drawn.
func finish_coin_flip() -> void:
	if match_start != MatchStart.COIN_FLIP or not flip_called:
		return
	if first_player != 0:
		var st := engine.state
		st.active_player_id = first_player
		st.priority_player_id = first_player
		st.awaiting = {player_id = first_player, type = &"priority"}
	_deal_opening_hands()


## Set when a permanent has several activated abilities and the table should show its pick menu.
var ability_menu_pending: int = 0


func submit(action: GameAction) -> SubmitResult:
	if engine == null or action == null:
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "no engine"
		last_error = bad.error
		return bad
	var r: SubmitResult = engine.submit(action)
	last_error = r.error if not r.ok else ""
	rebuild_view()
	return r


func rebuild_view() -> void:
	pending_draw_anim = draw_waiting()
	history.pump(engine, you_seat, match_start == MatchStart.MAIN_GAME)
	view = TableView.from_engine(engine, self)


## True while it is your turn and you still have to click your library for the turn's card.
func draw_waiting() -> bool:
	return engine != null and engine.state != null and engine.state.draw_pending and engine.state.active_player_id == you_seat


func keep_hand(player_id: int) -> void:
	if match_start != MatchStart.MULLIGAN_DECISION:
		return
	var n := 0
	if player_id >= 0 and player_id < engine.state.players.size():
		n = engine.state.players[player_id].mulligan_count
	if n > 0:
		if player_id == 0:
			put_back_remaining = n
			match_start = MatchStart.PUT_BACK
			dbg("Keep after %d mulligan(s): put %d on bottom" % [n, n])
			rebuild_view()
			return
		_auto_put_back(player_id, n)
	_mark_kept(player_id)


func take_mulligan(player_id: int) -> void:
	if match_start != MatchStart.MULLIGAN_DECISION:
		return
	if player_id < 0 or player_id >= engine.state.players.size():
		return
	engine.return_hand_to_library(player_id)
	engine.state.players[player_id].mulligan_count += 1
	engine.draw_n(player_id, 7)
	dbg("Mulligan %d" % engine.state.players[player_id].mulligan_count)
	dbg("Drew new 7. Library remaining: %d" % engine.library_size(player_id))
	rebuild_view()


func put_back_card(object_id: int) -> void:
	if match_start != MatchStart.PUT_BACK or put_back_remaining <= 0:
		return
	var moved: GameObject = engine.put_library_bottom(object_id, 0)
	if moved == null:
		return
	put_back_remaining -= 1
	dbg("Bottom: %s. Remaining to put back: %d" % [
		(moved.definition as CardDefinition).name if moved.definition is CardDefinition else "?",
		put_back_remaining,
	])
	if put_back_remaining <= 0:
		_mark_kept(0)
	else:
		rebuild_view()


func _auto_put_back(player_id: int, n: int) -> void:
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, player_id)
	if hand == null:
		return
	var ids: Array = hand.object_ids.duplicate()
	var put := mini(n, ids.size())
	for i in put:
		engine.put_library_bottom(int(ids[ids.size() - 1 - i]), player_id)


func _mark_kept(player_id: int) -> void:
	kept[player_id] = true
	if bool(kept.get(0, false)) and bool(kept.get(1, false)):
		match_start = MatchStart.MAIN_GAME
		dbg("GAME_READY. Hand %d, library %d" % [engine.hand_size(0), engine.library_size(0)])
		## The rival won the flip: it plays its first turn before you get yours.
		if first_player != you_seat and not skip_ai and engine.state.active_player_id == first_player:
			history.add_note("Talrand won the flip and goes first.", "info")
			rebuild_view()
			_finish_bot_turn(first_player)
	rebuild_view()


func prompt_text() -> String:
	if engine == null or engine.state == null:
		return ""
	if engine.is_over():
		if engine.state.winners.has(0):
			return "You won."
		return "You lost."
	if not can_play():
		return "Keep or Mulligan first."
	if choosing_attackers:
		return "Declare attackers — click creatures to send in (summoning-sick ones can't attack). Confirm when ready."
	if awaiting_blocks:
		return "Blocking — click one of your creatures, then the attacker it should block. Confirm blocks when done."
	if engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION:
		if engine.state.pending_decision is PlayerDecision:
			var asked := (engine.state.pending_decision as PlayerDecision).prompt
			if asked != "":
				return asked
		return "A choice is waiting."
	if engine.state.stack != null and engine.state.stack is MagicStack and not (engine.state.stack as MagicStack).is_empty():
		if _awaiting_id() == 0:
			return "Something is on the stack. Pass to resolve, or cast an instant."
		return "Waiting on the opponent."
	if engine.state.step == EngineEnums.Step.DECLARE_ATTACKERS and engine.state.active_player_id == 0:
		var n: int = engine.legal_attacker_ids(0).size()
		if n > 0:
			return "Combat — Attack with %d creature(s), or Pass to skip." % n
		return "Combat — no one can attack. Pass."
	if engine.state.active_player_id == 0 and (
		engine.state.phase == EngineEnums.Phase.MAIN_1 or engine.state.phase == EngineEnums.Phase.MAIN_2
	):
		return "Your turn. Play a land, cast, Attack, or End turn."
	if engine.state.active_player_id != 0:
		return "Talrand's turn."
	return "Pass to continue."


func play_land(object_id: int, etb_choice: int = -1) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	## Lands with "you may reveal a card / pay N life, otherwise it enters tapped": ask first.
	if etb_choice < 0:
		var q := _land_question(object_id)
		if not q.is_empty():
			land_prompt = q
			var wait := SubmitResult.new()
			wait.ok = true
			target_pending = true
			return wait
	var a := GameAction.new()
	a.kind = GameAction.Kind.PLAY_LAND
	a.player_id = 0
	a.object_id = object_id
	engine.state.zones.etb_choice = etb_choice
	var r: SubmitResult = submit(a)
	engine.state.zones.etb_choice = -1
	if r.ok:
		resolve_stack_then_yield()
	return r


func _land_question(object_id: int) -> Dictionary:
	var obj: GameObject = engine.state.objects.get(object_id)
	if obj == null or not (obj.definition is CardDefinition):
		return {}
	var def := obj.definition as CardDefinition
	var rule := EtbRules.parse(def)
	var kind := str(rule.get("kind", ""))
	if kind == "REVEAL":
		var hand: Array = []
		for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).object_ids:
			if int(oid) != object_id:
				hand.append(engine.state.objects.get(oid))
		if not EtbRules._any_has(hand, rule.get("types", [])):
			return {}
		return {"object_id": object_id, "name": def.name, "kind": kind,
			"text": "Reveal a %s card from your hand so %s enters untapped?" % [" or ".join(PackedStringArray(rule.get("types", []))), def.name],
			"yes": "Reveal", "no": "Enter tapped"}
	if kind == "PAY_LIFE":
		var n := int(rule.get("n", 0))
		if int(engine.state.players[0].life) <= n:
			return {}
		return {"object_id": object_id, "name": def.name, "kind": kind,
			"text": "Pay %d life so %s enters untapped? (You have %d.)" % [n, def.name, int(engine.state.players[0].life)],
			"yes": "Pay %d life" % n, "no": "Enter tapped"}
	return {}


func answer_land(accept: bool) -> SubmitResult:
	var q := land_prompt
	land_prompt = {}
	target_pending = false
	if q.is_empty():
		return SubmitResult.new()
	return play_land(int(q.get("object_id", 0)), 1 if accept else 0)


func cast_auto(player_id: int, object_id: int, extra: Dictionary = {}) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = player_id
	a.object_id = object_id
	a.extra = {auto_pay = true}
	for k in extra.keys():
		a.extra[k] = extra[k]
	var r := submit(a)
	if not r.ok:
		return r
	if engine.state.mode == EngineEnums.EngineMode.CASTING:
		var chosen: SubmitResult = _choose_target_auto(player_id)
		var picked := chosen != null
		if picked:
			r = chosen
		if target_pending:
			rebuild_view()
			return r
		if not picked:
			var cancel_t := GameAction.new()
			cancel_t.kind = GameAction.Kind.CANCEL_CAST
			cancel_t.player_id = player_id
			submit(cancel_t)
			r.ok = false
			r.error = "no legal target"
			return r
	if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		var cancel := GameAction.new()
		cancel.kind = GameAction.Kind.CANCEL_CAST
		cancel.player_id = player_id
		submit(cancel)
		r.ok = false
		r.error = "Can't pay that."
		return r
	if r.ok and player_id == 0:
		resolve_stack_then_yield()
	return r


## Everything the player can do with one card right now, for the table's pick menu:
## [{label, detail, kind: "cast"|"special"|"ability", extra | action | ability_id}].
## Casting ways are only listed when payable (mana colors, convoke, delve, life for Phyrexian symbols).
func card_menu(object_id: int) -> Array:
	var out: Array = []
	if engine == null or not can_play():
		return out
	var obj: GameObject = engine.state.objects.get(object_id)
	if obj == null:
		return out
	var castable_now := false
	for act in engine.legal_actions(0):
		var ga := act as GameAction
		if ga != null and ga.kind == GameAction.Kind.CAST_SPELL and ga.object_id == object_id:
			castable_now = true
	if castable_now:
		for o in engine.kw.affordable_options(0, obj):
			var od: Dictionary = o
			out.append({"label": str(od.label), "detail": str(od.detail), "kind": "cast", "extra": od.extra})
	for act2 in engine.kw.special_actions(0):
		var sa := act2 as GameAction
		if sa != null and sa.object_id == object_id:
			out.append({"label": str(sa.extra.get("label", "Action")), "detail": str(sa.extra.get("detail", "")), "kind": "special", "action": sa})
	if obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		for act3 in engine.legal_actions(0):
			var aa := act3 as GameAction
			if aa != null and aa.kind == GameAction.Kind.ACTIVATE_ABILITY and aa.object_id == object_id:
				var ab: Ability = engine._ability_on(obj, aa.ability_id)
				out.append({"label": ab.text if ab != null and ab.text != "" else str(aa.ability_id), "detail": "Activate", "kind": "ability", "ability_id": str(aa.ability_id)})
	return out


## Runs one entry from card_menu().
func run_card_entry(object_id: int, entry: Dictionary) -> SubmitResult:
	match str(entry.get("kind", "")):
		"cast":
			return cast_auto(0, object_id, entry.get("extra", {}))
		"special":
			var r: SubmitResult = submit(entry.action as GameAction)
			if r.ok:
				resolve_stack_then_yield()
			return r
		"ability":
			return activate_ability(object_id, StringName(str(entry.get("ability_id", ""))))
	var bad := SubmitResult.new()
	bad.ok = false
	bad.error = "Unknown choice."
	return bad


## Cards in your graveyard or exile that can be cast (flashback, escape, retrace, suspend-style plays), each with its ways.
func zone_menu(zone_id: int) -> Array:
	var out: Array = []
	if engine == null or not can_play():
		return out
	var z: Zone = engine.state.zones.get_zone(zone_id, 0)
	if z == null:
		return out
	var legal := {}
	for act in engine.legal_actions(0):
		var ga := act as GameAction
		if ga != null and ga.kind == GameAction.Kind.CAST_SPELL:
			legal[ga.object_id] = true
	for oid in z.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		var d: CardDefinition = obj.definition as CardDefinition if obj != null and obj.definition is CardDefinition else null
		if legal.has(oid):
			for o in engine.kw.affordable_options(0, obj):
				var od: Dictionary = o
				out.append({"label": "%s — %s" % [d.name if d != null else "Card", str(od.label)], "detail": str(od.detail), "kind": "cast", "extra": od.extra, "object_id": oid})
		## Special actions from this zone: encore, eternalize, embalm, unearth, scavenge, plot casts ...
		for act in engine.kw.special_actions(0):
			var sa := act as GameAction
			if sa != null and sa.object_id == oid:
				out.append({"label": "%s — %s" % [d.name if d != null else "Card", str(sa.extra.get("label", "Action"))], "detail": str(sa.extra.get("detail", "")), "kind": "special", "action": sa, "object_id": oid})
	return out


## There is no target picker on the table yet, so the game picks for you: harmful spells and
## abilities go at the rival (their player, else their biggest creature), helpful ones at you.
## Returns null when there is no legal target.
func _choose_target_auto(player_id: int) -> SubmitResult:
	var hostile := _pending_is_hostile()
	var last: SubmitResult = null
	## One slot per pass: a spell with two targets ("fights another target creature") asks again.
	var guard := 0
	while engine.state.mode == EngineEnums.EngineMode.CASTING and guard < 4:
		guard += 1
		var slot := engine._cast_targets.size()
		var slot_dict: Dictionary = {}
		if slot < engine._cast_queries.size() and engine._cast_queries[slot] is Dictionary:
			slot_dict = engine._cast_queries[slot]
		var slot_hostile := TargetingManager.slot_hostile(slot_dict, hostile)
		var best: GameAction = null
		var best_score := -1000000
		var cand_ids: Array = []
		for act in engine.legal_actions(player_id):
			var ga := act as GameAction
			if ga == null or ga.kind != GameAction.Kind.CHOOSE_TARGETS or ga.targets.is_empty():
				continue
			cand_ids.append(int(ga.targets[0]))
			var sc := _target_score(int(ga.targets[0]), player_id, slot_hostile)
			if sc > best_score:
				best_score = sc
				best = ga
		if best == null:
			return null
		## You choose your own targets; with a single legal one there is nothing to choose.
		if player_id == 0 and cand_ids.size() > 1:
			_open_target_prompt(cand_ids, slot, slot_hostile)
			var wait := SubmitResult.new()
			wait.ok = true
			return wait
		best.extra = {auto_pay = true}
		last = submit(best)
		if last == null or not last.ok:
			return last
	return last


func _open_target_prompt(cand_ids: Array, slot: int, hostile: bool) -> void:
	var src: GameObject = engine.state.objects.get(engine._cast_source)
	var src_name := (src.definition as CardDefinition).name if src != null and src.definition is CardDefinition else "the ability"
	var options: Array = []
	cand_ids.sort_custom(func(a, b) -> bool: return _target_score(int(a), 0, hostile) > _target_score(int(b), 0, hostile))
	for tid in cand_ids:
		options.append(_target_option(int(tid)))
	var total: int = engine._cast_queries.size()
	target_prompt = {
		"title": "Choose a target for %s" % src_name,
		"sub": "Target %d of %d" % [slot + 1, total] if total > 1 else "",
		"options": options,
	}
	target_pending = true


func _target_option(tid: int) -> Dictionary:
	var pid := TargetingManager.decode_player(tid)
	if pid >= 0:
		var you := pid == 0
		return {"id": tid, "label": "You" if you else "Talrand (rival)", "detail": "Player · %d life" % int(engine.state.players[pid].life), "kind": "player", "mine": you}
	if engine.state.stack is MagicStack:
		for e in (engine.state.stack as MagicStack).entries:
			var entry := e as StackEntry
			if entry != null and entry.stack_id == tid:
				var so: GameObject = engine.state.objects.get(entry.object_id)
				var nm := (so.definition as CardDefinition).name if so != null and so.definition is CardDefinition else "Spell"
				return {"id": tid, "label": nm, "detail": "Spell on the stack", "kind": "spell", "mine": entry.controller_id == 0}
	var obj: GameObject = engine.state.objects.get(tid)
	if obj == null or not (obj.definition is CardDefinition):
		return {"id": tid, "label": "Unknown", "detail": "", "kind": "card", "mine": false}
	var def := obj.definition as CardDefinition
	var detail := def.type_line
	if engine.is_creature_now(obj):
		detail += "  %d/%d" % [engine.power_of(obj), engine.toughness_of(obj)]
	if obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		detail += "  (in a graveyard)"
	return {"id": tid, "label": def.name, "detail": detail, "kind": "card", "mine": obj.controller_id == 0, "object_id": obj.object_id}


## The player clicked a target in the picker.
func choose_target(tid: int) -> SubmitResult:
	target_prompt = {}
	target_pending = false
	var a := GameAction.new()
	a.kind = GameAction.Kind.CHOOSE_TARGETS
	a.player_id = 0
	a.object_id = engine._cast_source
	a.targets = [tid]
	a.extra = {auto_pay = true}
	var r: SubmitResult = submit(a)
	if not r.ok:
		last_error = r.error
		_cancel_pending_cast()
		rebuild_view()
		return r
	if engine.state.mode == EngineEnums.EngineMode.CASTING:
		_choose_target_auto(0)
		if target_pending:
			rebuild_view()
			return r
	if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS or engine.state.mode == EngineEnums.EngineMode.CASTING:
		_cancel_pending_cast()
		r.ok = false
		r.error = "Can't pay that."
		last_error = r.error
		rebuild_view()
		return r
	resolve_stack_then_yield()
	return r


func cancel_target() -> void:
	target_prompt = {}
	target_pending = false
	_cancel_pending_cast()
	rebuild_view()


func _cancel_pending_cast() -> void:
	var c := GameAction.new()
	c.kind = GameAction.Kind.CANCEL_CAST
	c.player_id = 0
	submit(c)


func _pending_is_hostile() -> bool:
	var obj: GameObject = engine.state.objects.get(engine._cast_source)
	if obj == null or not (obj.definition is CardDefinition):
		return true
	var activating: bool = engine._act_ability_id != &""
	for a in (obj.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab == null:
			continue
		if activating and ab.ability_id != engine._act_ability_id:
			continue
		if not activating and ab.kind != &"SPELL":
			continue
		return TargetingManager.effects_hostile(ab.effects)
	return true


func _target_score(tid: int, me: int, hostile: bool) -> int:
	return TargetingManager.auto_score(engine, tid, me, hostile)


func activate_ability(object_id: int, ability_id: StringName) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	for act in engine.legal_actions(0):
		var ga := act as GameAction
		if ga.kind != GameAction.Kind.ACTIVATE_ABILITY or ga.object_id != object_id:
			continue
		if ga.ability_id != ability_id:
			continue
		ga.extra["auto_pay"] = true
		var r: SubmitResult = submit(ga)
		if not r.ok:
			last_error = r.error
			rebuild_view()
			return r
		if engine.state.mode == EngineEnums.EngineMode.CASTING and _awaiting_id() == 0:
			## Targeted ability: pick the target for you (see _choose_target_auto).
			var picked: SubmitResult = _choose_target_auto(0)
			if picked == null:
				var cancel_t := GameAction.new()
				cancel_t.kind = GameAction.Kind.CANCEL_CAST
				cancel_t.player_id = 0
				submit(cancel_t)
				r.ok = false
				r.error = "No legal target."
				last_error = r.error
				rebuild_view()
				return r
			r = picked
			if target_pending:
				rebuild_view()
				return r
			if not r.ok:
				last_error = r.error
				rebuild_view()
				return r
		if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS or engine.state.mode == EngineEnums.EngineMode.CASTING:
			if _awaiting_id() == 0:
				var cancel := GameAction.new()
				cancel.kind = GameAction.Kind.CANCEL_CAST
				cancel.player_id = 0
				submit(cancel)
				r.ok = false
				r.error = "Can't pay that."
				last_error = r.error
				rebuild_view()
				return r
		resolve_stack_then_yield()
		return r
	var missing := SubmitResult.new()
	missing.ok = false
	missing.error = _no_activation_reason(object_id)
	last_error = missing.error
	return missing


func activate_auto(object_id: int) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	var matches: Array = []
	for act in engine.legal_actions(0):
		var ga := act as GameAction
		if ga.kind == GameAction.Kind.ACTIVATE_ABILITY and ga.object_id == object_id:
			matches.append(ga)
	if matches.size() > 1:
		var choose := SubmitResult.new()
		choose.ok = false
		choose.error = "Choose an ability."
		ability_menu_pending = object_id
		last_error = choose.error
		return choose
	if matches.size() == 1:
		return activate_ability(object_id, (matches[0] as GameAction).ability_id)
	var none := SubmitResult.new()
	none.ok = false
	none.error = _no_activation_reason(object_id)
	last_error = none.error
	return none


func _no_activation_reason(object_id: int) -> String:
	if engine == null:
		return "No activated ability."
	var report: Dictionary = engine.activation_report(object_id)
	var rows: Array = report.get("abilities", [])
	if rows.is_empty():
		return "No activated ability."
	var parts: PackedStringArray = PackedStringArray()
	for row in rows:
		if row is Dictionary:
			parts.append("%s: %s" % [str((row as Dictionary).get("cost", "")), str((row as Dictionary).get("reason", ""))])
	if parts.is_empty():
		return "No activated ability."
	return "\n".join(parts)


## Moves to the declare attackers step and lets you pick attackers (CR 508.1).
func begin_attack() -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if not can_play():
		r.error = "Keep or mulligan first."
		last_error = r.error
		return r
	if draw_waiting():
		r.error = "Draw your card first: click your deck."
		last_error = r.error
		rebuild_view()
		return r
	_advance_to_attackers()
	if engine.state.step != EngineEnums.Step.DECLARE_ATTACKERS or engine.state.active_player_id != 0:
		r.error = "Can't attack now."
		last_error = r.error
		rebuild_view()
		return r
	if engine.legal_attacker_ids(0).is_empty():
		r.error = "No creature can attack right now (summoning sick, tapped, or defender)."
		last_error = r.error
		rebuild_view()
		return r
	choosing_attackers = true
	r.ok = true
	rebuild_view()
	return r


## Declares exactly these attackers (an empty array means no attack), then plays out combat.
func attack_with(ids: Array) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	_advance_to_attackers()
	if engine.state.step != EngineEnums.Step.DECLARE_ATTACKERS or engine.state.active_player_id != 0:
		var bad2 := SubmitResult.new()
		bad2.ok = false
		bad2.error = "Can't attack now."
		last_error = bad2.error
		choosing_attackers = false
		rebuild_view()
		return bad2
	var a := GameAction.new()
	a.kind = GameAction.Kind.DECLARE_ATTACKERS
	a.player_id = 0
	a.extra = {attackers = ids}
	var r: SubmitResult = submit(a)
	if r.ok:
		choosing_attackers = false
		_pass_through_combat()
	rebuild_view()
	return r


## Every creature that can attack does. Used by LAN clients and quick play.
func attack_all() -> SubmitResult:
	if not can_play():
		return attack_with([])
	_advance_to_attackers()
	return attack_with(engine.legal_attacker_ids(0))


func pass_once() -> void:
	if not can_play() or engine == null:
		return
	choosing_attackers = false
	if _awaiting_id() == 0:
		pass_priority(0)
	var n := 0
	while n < 32 and engine != null and not engine.is_over():
		n += 1
		if engine.state.draw_pending:
			rebuild_view()
			return
		if _resolve_choice_if_needed():
			continue
		if _stop_for_human_decision():
			rebuild_view()
			return
		if _awaiting_id() == 0:
			rebuild_view()
			return
		_ai_respond()
	rebuild_view()


func resolve_stack_then_yield() -> void:
	if engine == null or not can_play():
		return
	var n := 0
	while n < 80 and engine != null and not engine.is_over():
		n += 1
		if engine.state.draw_pending:
			rebuild_view()
			return
		if _resolve_choice_if_needed():
			continue
		if _stop_for_human_decision():
			rebuild_view()
			return
		if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS or engine.state.mode == EngineEnums.EngineMode.CASTING:
			if _awaiting_id() == 0:
				rebuild_view()
				return
			var cancel := GameAction.new()
			cancel.kind = GameAction.Kind.CANCEL_CAST
			cancel.player_id = _awaiting_id()
			submit(cancel)
			continue
		var empty := engine.state.stack == null or (engine.state.stack as MagicStack).is_empty()
		var pid: int = _awaiting_id()
		if empty and pid == 0:
			rebuild_view()
			return
		if empty and pid == 1 and engine.state.active_player_id == 1:
			rebuild_view()
			return
		if pid == 0:
			pass_priority(0)
			continue
		_ai_respond()
	rebuild_view()


func _advance_to_attackers() -> void:
	var n := 0
	while n < 40 and engine != null and not engine.is_over():
		n += 1
		if engine.state.draw_pending:
			rebuild_view()
			return
		if _resolve_choice_if_needed():
			continue
		if _stop_for_human_decision():
			rebuild_view()
			return
		if engine.state.active_player_id != 0:
			return
		if engine.state.step == EngineEnums.Step.DECLARE_ATTACKERS:
			return
		if _awaiting_id() == 0:
			pass_priority(0)
		else:
			_ai_respond()


func _pass_through_combat() -> void:
	var n := 0
	while n < 40 and engine != null and not engine.is_over():
		n += 1
		if engine.state.draw_pending:
			rebuild_view()
			return
		if _resolve_choice_if_needed():
			continue
		if _stop_for_human_decision():
			rebuild_view()
			return
		if engine.state.active_player_id != 0:
			return
		if engine.state.phase != EngineEnums.Phase.COMBAT:
			return
		if _awaiting_id() == 0:
			pass_priority(0)
		else:
			_ai_respond()


func _ai_respond() -> void:
	var pid: int = _awaiting_id()
	if pid != 1:
		pass_priority(pid)
		return
	if not skip_ai and blocks_needed(pid):
		var blocks := GameAction.new()
		blocks.kind = GameAction.Kind.DECLARE_BLOCKERS
		blocks.player_id = pid
		blocks.extra = {blockers = AiBlocks.choose(engine, pid)}
		var br: SubmitResult = submit(blocks)
		if not br.ok:
			dbg("Bot block rejected: %s" % br.error)
			blocks.extra = {blockers = {}}
			submit(blocks)
		return
	if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS or engine.state.mode == EngineEnums.EngineMode.CASTING:
		var cancel := GameAction.new()
		cancel.kind = GameAction.Kind.CANCEL_CAST
		cancel.player_id = pid
		submit(cancel)
		return
	var empty := engine.state.stack == null or (engine.state.stack as MagicStack).is_empty()
	if not empty:
		var legal: Array = engine.legal_actions(1)
		for act in legal:
			var ga := act as GameAction
			if ga.kind != GameAction.Kind.CAST_SPELL:
				continue
			var obj: GameObject = engine.state.objects.get(ga.object_id)
			var def: CardDefinition = obj.definition as CardDefinition if obj != null and obj.definition is CardDefinition else null
			var nm := def.name if def else ""
			if nm == "Counterspell" or nm == "Cancel":
				var cr: SubmitResult = cast_auto(1, ga.object_id)
				if cr.ok:
					return
		pass_priority(1)
		return
	pass_priority(1)


## You click your library: take the draw-step card (CR 504.1). Returns the card, or {} if there is nothing to take.
func ack_draw() -> Dictionary:
	if not draw_waiting():
		return {}
	var obj: GameObject = engine.take_turn_draw(you_seat)
	pending_draw_anim = false
	pending_draw_card = {}
	if obj == null:
		## A dredge question is open: the table shows it, and the draw is finished by the answer.
		if engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION:
			dbg("Draw: dredge choice open")
			rebuild_view()
			return {}
		dbg("Draw from empty library")
		last_error = "Library is empty."
		rebuild_view()
		return {}
	## Nothing else happens in the draw step, so move on to Main 1 where cards can be played.
	## (Anything that does happen, like a trigger, still stops the loop in pass_once.)
	var stack_empty := engine.state.stack == null or (engine.state.stack as MagicStack).is_empty()
	if engine.state.step == EngineEnums.Step.DRAW and _awaiting_id() == you_seat and stack_empty:
		pass_once()
	rebuild_view()
	var card: Dictionary = view.find_card(str(obj.object_id)) if view != null else {}
	dbg("Drew: %s" % str(card.get("name", "?")))
	dbg("Hand size: %d" % engine.hand_size(you_seat))
	dbg("Library remaining: %d" % engine.library_size(you_seat))
	return card


func draw_from_library(player_id: int = 0) -> Dictionary:
	if not can_play() or engine == null:
		return {}
	var obj: GameObject = engine.draw_card(player_id)
	if obj == null:
		dbg("Draw from empty library")
		last_error = "Library is empty."
		rebuild_view()
		return {}
	rebuild_view()
	var card: Dictionary = view.find_card(str(obj.object_id)) if view != null else {}
	var nm := str(card.get("name", "?"))
	dbg("Drew: %s" % nm)
	dbg("Hand size: %d" % engine.hand_size(player_id))
	dbg("Library remaining: %d" % engine.library_size(player_id))
	return card


func pass_priority(player_id: int) -> SubmitResult:
	var a := GameAction.new()
	a.kind = GameAction.Kind.PASS_PRIORITY
	a.player_id = player_id
	return submit(a)


func _awaiting_id() -> int:
	if engine == null or engine.state == null:
		return 0
	return int(engine.state.awaiting.get("player_id", 0))


func _stop_for_human_decision() -> bool:
	if engine == null or engine.state == null:
		return false
	if engine.state.mode != EngineEnums.EngineMode.AWAITING_DECISION:
		return false
	return _awaiting_id() == 0


func _ai_answer_decision() -> bool:
	var dec: PlayerDecision = engine.state.pending_decision as PlayerDecision
	var a := GameAction.new()
	a.player_id = _awaiting_id()
	if dec != null and dec.kind == &"OPTIONAL_YES_NO":
		a.kind = GameAction.Kind.SUBMIT_DECISION
		submit(a)
		return true
	if dec != null and not dec.candidates.is_empty():
		a.kind = GameAction.Kind.SUBMIT_DECISION
		a.extra = {choice = dec.candidates[0]}
		submit(a)
		return true
	a.kind = GameAction.Kind.DECLINE_DECISION
	submit(a)
	return true


func _resolve_choice_if_needed() -> bool:
	var st := engine.state
	if st.mode == EngineEnums.EngineMode.AWAITING_DECISION:
		if _awaiting_id() == 0:
			return false
		return _ai_answer_decision()
	if st.mode == EngineEnums.EngineMode.CHOOSING_REPLACEMENT:
		var a := GameAction.new()
		a.kind = GameAction.Kind.CHOOSE_REPLACEMENT
		a.player_id = _awaiting_id()
		a.extra = {dest_zone = EngineEnums.ZoneId.COMMAND}
		submit(a)
		return true
	if st.mode == EngineEnums.EngineMode.CHOOSING_SBA:
		var ids: Array = st.awaiting.get("object_ids", [])
		if not ids.is_empty():
			var a := GameAction.new()
			a.kind = GameAction.Kind.CHOOSE_SBA
			a.player_id = _awaiting_id()
			a.object_id = int(ids[0])
			submit(a)
			return true
	return false


func pass_until_active(player_id: int, max_steps: int = 80) -> void:
	var n := 0
	while n < max_steps and engine != null and not engine.is_over():
		n += 1
		if engine.state.draw_pending:
			rebuild_view()
			return
		if _resolve_choice_if_needed():
			continue
		if _stop_for_human_decision():
			return
		if engine.state.active_player_id == player_id:
			if engine.state.phase == EngineEnums.Phase.MAIN_1 or engine.state.phase == EngineEnums.Phase.MAIN_2:
				if engine.state.stack == null or (engine.state.stack as MagicStack).is_empty():
					if engine.state.mode != EngineEnums.EngineMode.GIVING_PRIORITY or _awaiting_id() != player_id:
						engine.priority.give(engine.state, player_id)
					return
		var pid := _awaiting_id()
		if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS or engine.state.mode == EngineEnums.EngineMode.CASTING:
			var cancel := GameAction.new()
			cancel.kind = GameAction.Kind.CANCEL_CAST
			cancel.player_id = pid
			submit(cancel)
			continue
		pass_priority(pid)


## Skip a cast that cannot do anything: a counter with an empty stack, or a
## creature-only spell with no creature on the battlefield. Uses effect kinds, not names.
static func ai_should_skip_cast(def: CardDefinition, stack_empty: bool, battlefield_has_creature: bool) -> bool:
	if def == null:
		return false
	if stack_empty and def.has_effect(&"COUNTER_SPELL"):
		return true
	if not battlefield_has_creature and def.spell_requires_creature_target():
		return true
	return false


func ai_take_turn(player_id: int) -> void:
	var n := 0
	var skip_cast: Dictionary = {}
	var declared_attack := false
	while n < 48 and engine != null and not engine.is_over() and engine.state.active_player_id == player_id:
		n += 1
		if engine.state.draw_pending:
			rebuild_view()
			return
		if _resolve_choice_if_needed():
			continue
		if _stop_for_human_decision():
			return
		var pid := _awaiting_id()
		if pid != player_id:
			if pid == you_seat and blocks_needed(you_seat):
				awaiting_blocks = true
				rebuild_view()
				return
			pass_priority(pid)
			continue
		if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS or engine.state.mode == EngineEnums.EngineMode.CASTING:
			var cancel := GameAction.new()
			cancel.kind = GameAction.Kind.CANCEL_CAST
			cancel.player_id = pid
			submit(cancel)
			continue
		var legal: Array = engine.legal_actions(player_id)
		var land: GameAction = null
		var spell: GameAction = null
		var attack: GameAction = null
		for act in legal:
			var ga := act as GameAction
			if ga.kind == GameAction.Kind.PLAY_LAND:
				land = ga
			elif ga.kind == GameAction.Kind.CAST_SPELL:
				if skip_cast.has(ga.object_id):
					continue
				var obj: GameObject = engine.state.objects.get(ga.object_id)
				var def: CardDefinition = obj.definition as CardDefinition if obj != null and obj.definition is CardDefinition else null
				var stack_empty := engine.state.stack == null or (engine.state.stack as MagicStack).is_empty()
				if ai_should_skip_cast(def, stack_empty, _ai_has_creature_target(player_id)):
					continue
				if spell == null:
					spell = ga
			elif ga.kind == GameAction.Kind.DECLARE_ATTACKERS and not declared_attack:
				attack = ga
		if land != null:
			submit(land)
			continue
		if spell != null:
			var cr := cast_auto(player_id, spell.object_id)
			if not cr.ok:
				skip_cast[spell.object_id] = true
			continue
		if attack != null:
			var foe := 1 if player_id == 0 else 0
			attack.extra = {attackers = AiBlocks.choose_attackers(engine, player_id, foe)}
			declared_attack = true
			submit(attack)
			continue
		pass_priority(player_id)
		if engine.state.active_player_id != player_id:
			return


func _ai_has_creature_target(_player_id: int) -> bool:
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		if obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).is_creature():
			return true
	return false


func end_you_turn() -> void:
	if not can_play() or awaiting_blocks:
		return
	if draw_waiting():
		last_error = "Draw your card first: click your deck."
		rebuild_view()
		return
	choosing_attackers = false
	var other := 1 if you_seat == 0 else 0
	pass_until_active(other)
	if engine.is_over():
		return
	if skip_ai:
		return
	_finish_bot_turn(other)


## Runs the bot's turn to the end, unless it stops for your blockers.
func _finish_bot_turn(bot_id: int) -> void:
	ai_take_turn(bot_id)
	if awaiting_blocks or engine.is_over():
		return
	pass_until_active(you_seat)


## True when player_id is being attacked, hasn't declared blockers yet this combat,
## and has at least one creature that could legally block (CR 509.1).
func blocks_needed(player_id: int) -> bool:
	if engine == null or engine.state == null:
		return false
	if engine.state.step != EngineEnums.Step.DECLARE_BLOCKERS:
		return false
	if not (engine.state.combat is CombatState):
		return false
	var cs := engine.state.combat as CombatState
	if cs.blocks_declared:
		return false
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for aid in cs.attacker_ids:
		if engine.defender_of(int(aid)) != player_id:
			continue
		for oid in bf.object_ids:
			var obj: GameObject = engine.state.objects.get(oid)
			if obj != null and obj.controller_id == player_id and engine.can_block_attacker(obj.object_id, int(aid)):
				return true
	return false


## Your blockers while the bot attacks: {attacker_id: [blocker ids]}. Empty = no blocks.
## On success the bot's turn carries on.
func declare_blocks(blocks: Dictionary) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if not awaiting_blocks:
		r.error = "Nothing to block right now."
		last_error = r.error
		return r
	var a := GameAction.new()
	a.kind = GameAction.Kind.DECLARE_BLOCKERS
	a.player_id = you_seat
	a.extra = {blockers = blocks}
	r = submit(a)
	if not r.ok:
		last_error = r.error
		rebuild_view()
		return r
	awaiting_blocks = false
	_finish_bot_turn(1 if you_seat == 0 else 0)
	rebuild_view()
	return r

