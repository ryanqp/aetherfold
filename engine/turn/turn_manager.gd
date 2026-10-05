class_name TurnManager
extends RefCounted

const STEPS: Array[int] = [
	EngineEnums.Step.UNTAP,
	EngineEnums.Step.UPKEEP,
	EngineEnums.Step.DRAW,
	EngineEnums.Step.PRECOMBAT_MAIN,
	EngineEnums.Step.BEGIN_COMBAT,
	EngineEnums.Step.DECLARE_ATTACKERS,
	EngineEnums.Step.DECLARE_BLOCKERS,
	EngineEnums.Step.COMBAT_DAMAGE,
	EngineEnums.Step.END_COMBAT,
	EngineEnums.Step.POSTCOMBAT_MAIN,
	EngineEnums.Step.END,
	EngineEnums.Step.CLEANUP,
]

var _engine: WeakRef


func bind(engine: RulesEngine) -> void:
	_engine = weakref(engine)


func start_turn(player_id: int) -> void:
	var eng := _eng()
	if eng == null:
		return
	var st := eng.state
	st.active_player_id = player_id
	for i in st.players.size():
		st.land_played[i] = false
	_clear_sickness(st, player_id)
	st.step = EngineEnums.Step.UNTAP
	_sync_phase(st)
	_enter_current_step()


func all_passed() -> void:
	var eng := _eng()
	if eng == null:
		return
	var st := eng.state
	if st.stack != null and st.stack is MagicStack and not (st.stack as MagicStack).is_empty():
		eng.finish_top_resolution()
		return
	_finish_step_and_enter_next()


func advance_until_decision() -> void:
	var eng := _eng()
	if eng == null:
		return
	var guard := 0
	while guard < 48 and not _needs_input(eng.state):
		guard += 1
		_finish_step_and_enter_next()


func _enter_current_step() -> void:
	var eng := _eng()
	if eng == null:
		return
	var st := eng.state
	st.passed_since_action.clear()
	_sync_phase(st)
	st.log.append(EngineEnums.EventType.STEP_BEGIN, st.active_player_id, {
		step = st.step,
		phase = st.phase,
		turn = st.turn_number,
	})
	_start_tba(eng, st)
	if _receives_priority(st.step):
		eng.priority.give(st, st.active_player_id)
	else:
		_finish_step_and_enter_next()


func _finish_step_and_enter_next() -> void:
	var eng := _eng()
	if eng == null:
		return
	var guard := 0
	while guard < 24:
		guard += 1
		var st := eng.state
		eng.mana.on_step_end()
		st.log.append(EngineEnums.EventType.STEP_END, st.active_player_id, {
			step = st.step,
			phase = st.phase,
		})
		if st.step == EngineEnums.Step.CLEANUP:
			_rotate_turn(st)
		else:
			st.step = _next_step(st.step)
			## CR 508.8: no attackers means the declare blockers and combat damage steps are skipped.
			if st.step == EngineEnums.Step.DECLARE_BLOCKERS and not _has_attackers(st):
				st.step = EngineEnums.Step.END_COMBAT
		_sync_phase(st)
		st.passed_since_action.clear()
		st.log.append(EngineEnums.EventType.STEP_BEGIN, st.active_player_id, {
			step = st.step,
			phase = st.phase,
			turn = st.turn_number,
		})
		_start_tba(eng, st)
		if _receives_priority(st.step):
			eng.priority.give(st, st.active_player_id)
			return


func _rotate_turn(st: GameState) -> void:
	var n := st.players.size()
	if n <= 0:
		return
	st.active_player_id = (st.active_player_id + 1) % n
	st.turn_number += 1
	st.draw_pending = false
	for i in n:
		st.land_played[i] = false
	_clear_sickness(st, st.active_player_id)
	var eng := _eng()
	if eng != null and eng.kw != null:
		eng.kw.on_new_turn()
	st.step = EngineEnums.Step.UNTAP


## CR 514.2: damage wears off in the cleanup step.
func _clear_damage(st: GameState) -> void:
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj != null:
			obj.damage_marked = 0
			obj.deathtouch_damage = false


func _start_tba(eng: RulesEngine, st: GameState) -> void:
	match st.step:
		EngineEnums.Step.UNTAP:
			if eng.kw != null:
				eng.kw.on_untap(st.active_player_id)
			_untap(st)
		EngineEnums.Step.DRAW:
			var skip := st.turn_number == 1 and st.rules.first_player_skips_draw
			if not skip:
				if eng.manual_draw_seats.has(st.active_player_id):
					st.draw_pending = true
				else:
					eng.draw_card(st.active_player_id)
		EngineEnums.Step.COMBAT_DAMAGE:
			eng.apply_combat_damage()
		EngineEnums.Step.CLEANUP:
			## CR 514.1: discard down to the maximum hand size (the player picks which cards).
			var over := eng.hand_size(st.active_player_id) - eng.max_hand_size(st.active_player_id)
			if over > 0:
				var dfx := AbilityEffect.new()
				dfx.kind = &"DISCARD_TO_HAND_SIZE"
				dfx.params = {}
				eng.put_synthetic(null, st.active_player_id, [dfx], {})
			_clear_may_play(st)
			_clear_damage(st)
			if eng.layers != null:
				eng.layers.clear_until_eot(st)
			if st.combat is CombatState:
				var cs := st.combat as CombatState
				cs.attacker_ids.clear()
				cs.blockers.clear()
				cs.defenders.clear()
				cs.blocks_declared = false
		_:
			pass


func _untap(st: GameState) -> void:
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	var eng := _eng()
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj != null and obj.controller_id == st.active_player_id:
			if eng != null and eng.layers != null and _held_tapped(st, eng.layers, obj):
				continue
			obj.tapped = false


## CR 502.3: "doesn't untap during its controller's untap step" (unless that player is the monarch: Fall from Favor).
func _held_tapped(st: GameState, layers: LayerManager, obj: GameObject) -> bool:
	## "~ doesn't untap during your untap step." printed on the permanent (no condition on the line).
	if obj.definition is CardDefinition:
		for raw_line in (obj.definition as CardDefinition).oracle_text.to_lower().split("\n"):
			var l := str(raw_line).strip_edges()
			if l.contains("doesn't untap during your untap step") and not l.contains(" if ") and not l.contains("unless") and not l.begins_with("enchanted") and not l.begins_with("equipped"):
				return true
	for spec in layers.attached_specs(st, obj, "doesnt_untap"):
		var sp: Dictionary = spec
		if bool(sp.get("unless_monarch", false)) and st.monarch_id == obj.controller_id:
			continue
		return true
	return false


func _clear_may_play(st: GameState) -> void:
	for id in st.objects.keys():
		var obj: GameObject = st.objects[id]
		if obj != null:
			## "Until the end of your next turn" (Light Up the Stage) outlives this turn.
			if int(obj.marks.get("keep_until", 0)) > st.turn_number:
				continue
			obj.may_play_controller = -1


func _clear_sickness(st: GameState, player_id: int) -> void:
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj != null and obj.controller_id == player_id:
			obj.summoned_this_turn = false


func _has_attackers(st: GameState) -> bool:
	return st.combat is CombatState and not (st.combat as CombatState).attacker_ids.is_empty()


func _receives_priority(step: int) -> bool:
	if step == EngineEnums.Step.CLEANUP:
		## Only while something is on the stack (the discard down to the maximum hand size).
		var eng := _eng()
		return eng != null and eng.state.stack is MagicStack and not (eng.state.stack as MagicStack).is_empty()
	return step != EngineEnums.Step.UNTAP


func _next_step(step: int) -> int:
	var idx := STEPS.find(step)
	if idx < 0 or idx >= STEPS.size() - 1:
		return EngineEnums.Step.UNTAP
	return STEPS[idx + 1]


func _sync_phase(st: GameState) -> void:
	match st.step:
		EngineEnums.Step.UNTAP:
			st.phase = EngineEnums.Phase.UNTAP
		EngineEnums.Step.UPKEEP:
			st.phase = EngineEnums.Phase.UPKEEP
		EngineEnums.Step.DRAW:
			st.phase = EngineEnums.Phase.DRAW
		EngineEnums.Step.PRECOMBAT_MAIN:
			st.phase = EngineEnums.Phase.MAIN_1
		EngineEnums.Step.POSTCOMBAT_MAIN:
			st.phase = EngineEnums.Phase.MAIN_2
		EngineEnums.Step.END, EngineEnums.Step.CLEANUP:
			st.phase = EngineEnums.Phase.ENDING
		_:
			st.phase = EngineEnums.Phase.COMBAT


func _needs_input(st: GameState) -> bool:
	match st.mode:
		EngineEnums.EngineMode.GIVING_PRIORITY, EngineEnums.EngineMode.CASTING, EngineEnums.EngineMode.ACTIVATING, EngineEnums.EngineMode.PAYING_COSTS, EngineEnums.EngineMode.CHOOSING_SBA, EngineEnums.EngineMode.CHOOSING_REPLACEMENT, EngineEnums.EngineMode.DECLARING_ATTACKERS, EngineEnums.EngineMode.DECLARING_BLOCKERS, EngineEnums.EngineMode.ASSIGNING_COMBAT_DAMAGE, EngineEnums.EngineMode.GAME_OVER:
			return true
		_:
			return false


func _eng() -> RulesEngine:
	if _engine == null:
		return null
	return _engine.get_ref() as RulesEngine
