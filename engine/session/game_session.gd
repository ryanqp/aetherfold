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
	history.clear()
	engine.manual_draw_seats = [you_seat] if manual_draw else []
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
		var chosen: SubmitResult = _choose_target_auto(player_id)
		var picked := chosen != null
		if picked:
			r = chosen
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


## There is no target picker on the table yet, so the game picks for you: harmful spells and
## abilities go at the rival (their player, else their biggest creature), helpful ones at you.
## Returns null when there is no legal target.
func _choose_target_auto(player_id: int) -> SubmitResult:
	var hostile := _pending_is_hostile()
	var best: GameAction = null
	var best_score := -1000000
	for act in engine.legal_actions(player_id):
		var ga := act as GameAction
		if ga == null or ga.kind != GameAction.Kind.CHOOSE_TARGETS or ga.targets.is_empty():
			continue
		var sc := _target_score(int(ga.targets[0]), player_id, hostile)
		if sc > best_score:
			best_score = sc
			best = ga
	if best == null:
		return null
	best.extra = {auto_pay = true}
	return submit(best)


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
		for fx in ab.effects:
			var f := fx as AbilityEffect
			if f == null:
				continue
			if f.kind == &"GAIN_LIFE" or f.kind == &"UNTAP" or f.kind == &"PUT_COUNTER":
				return false
			if f.kind == &"PUMP" and int(f.params.get("power", 0)) >= 0 and int(f.params.get("toughness", 0)) >= 0:
				return false
	return true


func _target_score(tid: int, me: int, hostile: bool) -> int:
	var pid := TargetingManager.decode_player(tid)
	if pid >= 0:
		return 50 if (pid != me) == hostile else -50
	var entries: Array = (engine.state.stack as MagicStack).entries if engine.state.stack is MagicStack else []
	for e in entries:
		var entry := e as StackEntry
		if entry != null and entry.stack_id == tid:
			return 60 if (entry.controller_id != me) == hostile else -60
	var obj: GameObject = engine.state.objects.get(tid)
	if obj == null:
		return -1000
	var power := engine.power_of(obj)
	return (30 + power * 2) if (obj.controller_id != me) == hostile else (-30 + power)


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

