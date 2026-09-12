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
		eng.resolve_top()
		if eng.sba != null and eng.sba.check(eng):
			return
		eng.priority.give(st, st.active_player_id)
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
		_sync_phase(st)
		st.passed_since_action.clear()
		st.log.append(EngineEnums.EventType.STEP_BEGIN, st.active_player_id, {
			step = st.step,
			phase = st.phase,
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
	for i in n:
		st.land_played[i] = false
	_clear_sickness(st, st.active_player_id)
	st.step = EngineEnums.Step.UNTAP


func _start_tba(eng: RulesEngine, st: GameState) -> void:
	match st.step:
		EngineEnums.Step.UNTAP:
			_untap(st)
		EngineEnums.Step.DRAW:
			var skip := st.turn_number == 1 and st.rules.first_player_skips_draw
			if not skip:
				eng.draw_card(st.active_player_id)
		EngineEnums.Step.COMBAT_DAMAGE:
			eng.apply_combat_damage()
		EngineEnums.Step.CLEANUP:
			if eng.layers != null:
				eng.layers.clear_until_eot(st)
			if st.combat is CombatState:
				(st.combat as CombatState).attacker_ids.clear()
		_:
			pass


func _untap(st: GameState) -> void:
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj != null and obj.controller_id == st.active_player_id:
			obj.tapped = false


func _clear_sickness(st: GameState, player_id: int) -> void:
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj != null and obj.controller_id == player_id:
			obj.summoned_this_turn = false


func _receives_priority(step: int) -> bool:
	return step != EngineEnums.Step.UNTAP and step != EngineEnums.Step.CLEANUP


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
