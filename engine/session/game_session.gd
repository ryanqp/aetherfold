class_name GameSession
extends RefCounted

enum MatchStart {
	PRE_GAME,
	SHUFFLING,
	DRAWING_OPENING_HAND,
	MULLIGAN_DECISION,
	PUT_BACK,
	MAIN_GAME,
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
	match_start = MatchStart.SHUFFLING
	engine.setup_demo(demo, FormatRules.commander_1v1_table(), seed)
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
	match_start = MatchStart.DRAWING_OPENING_HAND
	engine.draw_n(0, 7)
	engine.draw_n(1, 7)
	dbg("Opening draw: 7")
	dbg("Library remaining: %d" % engine.library_size(0))
	dbg("Rival library remaining: %d" % engine.library_size(1))
	kept[1] = not skip_ai
	match_start = MatchStart.MULLIGAN_DECISION
	rebuild_view()


func submit(action: GameAction) -> SubmitResult:
	if engine == null or action == null:
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "no engine"
		last_error = bad.error
		return bad
	var r: SubmitResult = engine.submit(action)
	last_error = r.error if not r.ok else ""
	if r.ok:
		for ev in r.events:
			if ev is GameEvent and (ev as GameEvent).type == EngineEnums.EventType.DRAW and (ev as GameEvent).player_id == 0:
				pending_draw_anim = true
				var to_id := int((ev as GameEvent).payload.get("to_id", 0))
				rebuild_view()
				pending_draw_card = view.find_card(str(to_id))
				var nm := str(pending_draw_card.get("name", "?"))
				dbg("Drew: %s" % nm)
				dbg("Hand size: %d" % engine.hand_size(0))
				dbg("Library remaining: %d" % engine.library_size(0))
				return r
	rebuild_view()
	return r


func rebuild_view() -> void:
	view = TableView.from_engine(engine, self)


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


func play_land(object_id: int) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	var a := GameAction.new()
	a.kind = GameAction.Kind.PLAY_LAND
	a.player_id = 0
	a.object_id = object_id
	var r: SubmitResult = submit(a)
	if r.ok:
		resolve_stack_then_yield()
	return r


func cast_auto(player_id: int, object_id: int) -> SubmitResult:
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
	var r := submit(a)
	if not r.ok:
		return r
	if engine.state.mode == EngineEnums.EngineMode.CASTING:
		var picked := false
		for act in engine.legal_actions(player_id):
			if (act as GameAction).kind == GameAction.Kind.CHOOSE_TARGETS:
				(act as GameAction).extra = {auto_pay = true}
				r = submit(act)
				picked = true
				break
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


func activate_auto(object_id: int) -> SubmitResult:
	if not can_play():
		var bad := SubmitResult.new()
		bad.ok = false
		bad.error = "Keep or mulligan first."
		last_error = bad.error
		return bad
	var legal: Array = engine.legal_actions(0)
	for act in legal:
		var ga := act as GameAction
		if ga.kind == GameAction.Kind.ACTIVATE_ABILITY and ga.object_id == object_id:
			var r: SubmitResult = submit(ga)
			if r.ok:
				resolve_stack_then_yield()
			return r
	var none := SubmitResult.new()
	none.ok = false
	none.error = "Nothing to activate (sick, tapped, or no ability)."
	last_error = none.error
	return none


func attack_all() -> SubmitResult:
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
		rebuild_view()
		return bad2
	var ids: Array = engine.legal_attacker_ids(0)
	var a := GameAction.new()
	a.kind = GameAction.Kind.DECLARE_ATTACKERS
	a.player_id = 0
	a.extra = {attackers = ids}
	var r: SubmitResult = submit(a)
	if r.ok:
		_pass_through_combat()
	rebuild_view()
	return r


func pass_once() -> void:
	if not can_play() or engine == null:
		return
	if _awaiting_id() == 0:
		pass_priority(0)
	var n := 0
	while n < 32 and engine != null and not engine.is_over():
		n += 1
		if _resolve_choice_if_needed():
			continue
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
		if _resolve_choice_if_needed():
			continue
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
		if _resolve_choice_if_needed():
			continue
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
		if _resolve_choice_if_needed():
			continue
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


func ack_draw() -> Dictionary:
	var card := pending_draw_card.duplicate()
	pending_draw_anim = false
	pending_draw_card = {}
	rebuild_view()
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


func _resolve_choice_if_needed() -> bool:
	var st := engine.state
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
		if _resolve_choice_if_needed():
			continue
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


func ai_take_turn(player_id: int) -> void:
	var n := 0
	var skip_cast: Dictionary = {}
	while n < 48 and engine != null and not engine.is_over() and engine.state.active_player_id == player_id:
		n += 1
		if _resolve_choice_if_needed():
			continue
		var pid := _awaiting_id()
		if pid != player_id:
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
				var nm := def.name if def else ""
				var stack_empty := engine.state.stack == null or (engine.state.stack as MagicStack).is_empty()
				if stack_empty and (nm == "Counterspell" or nm == "Cancel"):
					continue
				if nm == "Unsummon" and not _ai_has_creature_target(player_id):
					continue
				if spell == null:
					spell = ga
			elif ga.kind == GameAction.Kind.DECLARE_ATTACKERS:
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
	if not can_play():
		return
	var other := 1 if you_seat == 0 else 0
	pass_until_active(other)
	if engine.is_over():
		return
	if skip_ai:
		return
	ai_take_turn(other)
	pass_until_active(you_seat)

