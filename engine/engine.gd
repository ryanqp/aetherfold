class_name RulesEngine
extends RefCounted

## Headless Commander-first rules kernel.

var state: GameState
var mana: ManaManager
var costs: CostManager
var turn: TurnManager
var priority: PriorityManager
var executor: AbilityExecutor
var targeting: TargetingManager
var triggers: TriggerManager
var sba: SbaManager
var layers: LayerManager
var _cast_source: int = 0
var _payment: ManaCost
var _cast_queries: Array = []
var _cast_targets: Array = []
var _cast_from_command: bool = false
var _act_ability_id: StringName = &""
var _act_paying: bool = false


func _init() -> void:
	state = GameState.new()
	mana = ManaManager.new()
	costs = CostManager.new()
	turn = TurnManager.new()
	priority = PriorityManager.new()
	executor = AbilityExecutor.new()
	targeting = TargetingManager.new()
	triggers = TriggerManager.new()
	sba = SbaManager.new()
	layers = LayerManager.new()
	state.replacement = ReplacementManager.new()
	turn.bind(self)


func setup(rules: FormatRules, seed: int = 1) -> void:
	if rules == null:
		rules = FormatRules.commander_4p()
	state = GameState.new()
	state.rules = rules
	state.rng_seed = seed
	state.rng = RngStream.new()
	state.rng.setup(seed)
	state.log = GameLog.new()
	state.players.clear()
	for i in rules.player_count:
		var p := PlayerState.new()
		p.player_id = i
		p.name = "Player %d" % (i + 1)
		p.life = rules.starting_life
		p.commander_ids = []
		p.mana = ManaPool.new()
		state.players.append(p)
		state.land_played[i] = false
	state.zones = ZoneManager.new()
	state.zones.bind(state)
	state.zones.setup(rules.player_count)
	state.stack = MagicStack.new()
	mana = ManaManager.new()
	mana.bind(state)
	costs = CostManager.new()
	turn = TurnManager.new()
	turn.bind(self)
	priority = PriorityManager.new()
	executor = AbilityExecutor.new()
	targeting = TargetingManager.new()
	triggers = TriggerManager.new()
	sba = SbaManager.new()
	layers = LayerManager.new()
	state.replacement = ReplacementManager.new()
	state.combat = CombatState.new()
	_cast_source = 0
	_payment = null
	_cast_queries = []
	_cast_targets = []
	_act_ability_id = &""
	_act_paying = false
	state.active_player_id = 0
	state.priority_player_id = 0
	state.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	state.awaiting = {player_id = 0, type = &"priority"}
	state.phase = EngineEnums.Phase.MAIN_1
	state.step = EngineEnums.Step.PRECOMBAT_MAIN
	state.ended = false
	state.winners.clear()
	state.log.append(EngineEnums.EventType.GAME_START, 0, {
		player_count = rules.player_count,
		seed = seed,
		starting_life = rules.starting_life,
	})


func setup_demo(demo: DemoSetup, rules: FormatRules = null, seed: int = 1) -> void:
	if rules == null:
		rules = FormatRules.commander_1v1_table()
	setup(rules, seed)
	if demo != null:
		demo.apply(self)


func legal_actions(player_id: int) -> Array:
	var out: Array = []
	if state == null or player_id < 0 or player_id >= state.players.size():
		return out
	if state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		return _legal_paying(player_id)
	if state.mode == EngineEnums.EngineMode.CASTING:
		return _legal_choose_targets(player_id)
	if state.mode == EngineEnums.EngineMode.CHOOSING_SBA:
		return _legal_choose_sba(player_id)
	if state.mode == EngineEnums.EngineMode.CHOOSING_REPLACEMENT:
		return _legal_choose_replacement(player_id)
	if state.mode == EngineEnums.EngineMode.AWAITING_DECISION:
		return _legal_decision(player_id)
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		return out
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	var pass_act := GameAction.new()
	pass_act.kind = GameAction.Kind.PASS_PRIORITY
	pass_act.player_id = player_id
	out.append(pass_act)
	if _can_play_land(player_id):
		var hand: Zone = state.zones.get_zone(EngineEnums.ZoneId.HAND, player_id)
		if hand != null:
			for oid in hand.object_ids:
				var obj: GameObject = state.objects.get(oid)
				if obj != null and _is_land(obj):
					var a := GameAction.new()
					a.kind = GameAction.Kind.PLAY_LAND
					a.player_id = player_id
					a.object_id = int(oid)
					out.append(a)
	for zone_id in [EngineEnums.ZoneId.HAND, EngineEnums.ZoneId.COMMAND, EngineEnums.ZoneId.EXILE]:
		var z: Zone = state.zones.get_zone(zone_id, player_id)
		if z == null:
			continue
		for oid in z.object_ids:
			var obj: GameObject = state.objects.get(oid)
			if obj == null or _is_land(obj):
				continue
			if obj.zone == EngineEnums.ZoneId.EXILE and obj.may_play_controller != player_id:
				continue
			if not _timing_ok_to_cast(player_id, obj):
				continue
			var c := GameAction.new()
			c.kind = GameAction.Kind.CAST_SPELL
			c.player_id = player_id
			c.object_id = obj.object_id
			out.append(c)
	out.append_array(_legal_mana_abilities(player_id))
	out.append_array(_legal_activated(player_id))
	if state.step == EngineEnums.Step.DECLARE_ATTACKERS and player_id == state.active_player_id:
		var dec := GameAction.new()
		dec.kind = GameAction.Kind.DECLARE_ATTACKERS
		dec.player_id = player_id
		dec.extra = {attackers = _legal_attacker_ids(player_id)}
		out.append(dec)
	return out


func submit(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	r.mode = state.mode if state else 0
	r.awaiting = state.awaiting if state else {}
	if action == null:
		r.error = "null action"
		return r
	var start: int = state.log.seq() if state and state.log else 0
	match action.kind:
		GameAction.Kind.PLAY_LAND:
			r = _submit_play_land(action)
			if r.ok:
				priority.note_action(state, action.player_id)
		GameAction.Kind.ACTIVATE_MANA_ABILITY:
			r = _submit_activate_mana(action)
			if r.ok:
				priority.note_action(state, action.player_id)
		GameAction.Kind.PASS_PRIORITY:
			r = _submit_pass(action)
		GameAction.Kind.CAST_SPELL:
			r = _submit_cast_spell(action)
		GameAction.Kind.PAY_MANA:
			r = _submit_pay_mana(action)
		GameAction.Kind.CONFIRM_PAY:
			r = _submit_confirm_pay(action)
		GameAction.Kind.CANCEL_CAST:
			r = _submit_cancel_cast(action)
		GameAction.Kind.ACTIVATE_ABILITY:
			r = _submit_activate_ability(action)
			if r.ok and state.mode == EngineEnums.EngineMode.GIVING_PRIORITY:
				priority.note_action(state, action.player_id)
		GameAction.Kind.SUBMIT_DECISION:
			r = _submit_decision(action, true)
		GameAction.Kind.DECLINE_DECISION:
			r = _submit_decision(action, false)
		GameAction.Kind.CHOOSE_TARGETS:
			r = _submit_choose_targets(action)
		GameAction.Kind.CHOOSE_SBA:
			r = _submit_choose_sba(action)
		GameAction.Kind.CHOOSE_REPLACEMENT:
			r = _submit_choose_replacement(action)
		GameAction.Kind.DECLARE_ATTACKERS:
			r = _submit_declare_attackers(action)
			if r.ok:
				priority.note_action(state, action.player_id)
		GameAction.Kind.DECLARE_BLOCKERS:
			r = _submit_declare_blockers(action)
			if r.ok:
				priority.note_action(state, action.player_id)
		_:
			r.error = "not implemented"
	r.mode = state.mode if state else 0
	r.awaiting = state.awaiting if state else {}
	if r.ok and state and state.log:
		r.events = state.log.since(start)
	return r


func view() -> GameView:
	var v := GameView.new()
	if state == null:
		return v
	v.player_count = state.players.size()
	v.turn_number = state.turn_number
	v.mode = state.mode
	return v


func is_over() -> bool:
	return state != null and state.ended


func library_size(player_id: int) -> int:
	var lib: Zone = state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, player_id)
	return 0 if lib == null else lib.size()


func hand_size(player_id: int) -> int:
	var hand: Zone = state.zones.get_zone(EngineEnums.ZoneId.HAND, player_id)
	return 0 if hand == null else hand.size()


func shuffle_library(player_id: int) -> void:
	var lib: Zone = state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, player_id)
	if lib != null and lib.object_ids.size() > 1:
		state.rng.shuffle(lib.object_ids)


func draw_card(player_id: int) -> GameObject:
	var lib: Zone = state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, player_id)
	if lib == null or lib.is_empty():
		return null
	var top_id := int(lib.object_ids[0])
	if state.objects.has(top_id):
		var top_obj: GameObject = state.objects[top_id]
		if top_obj.zone != EngineEnums.ZoneId.LIBRARY:
			return null
	var moved: GameObject = state.zones.move(top_id, EngineEnums.ZoneId.HAND, player_id)
	if moved != null:
		state.log.append(EngineEnums.EventType.DRAW, player_id, {to_id = moved.object_id})
	return moved


func draw_n(player_id: int, n: int) -> Array:
	var out: Array = []
	for _i in n:
		var c := draw_card(player_id)
		if c == null:
			break
		out.append(c)
	return out


func return_hand_to_library(player_id: int) -> void:
	var hand: Zone = state.zones.get_zone(EngineEnums.ZoneId.HAND, player_id)
	if hand == null:
		return
	var ids: Array = hand.object_ids.duplicate()
	for oid in ids:
		state.zones.move(int(oid), EngineEnums.ZoneId.LIBRARY, player_id)
	shuffle_library(player_id)


func put_library_bottom(object_id: int, player_id: int) -> GameObject:
	var moved: GameObject = state.zones.move(object_id, EngineEnums.ZoneId.LIBRARY, player_id)
	if moved == null:
		return null
	var lib: Zone = state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, player_id)
	if lib != null and lib.object_ids.has(moved.object_id):
		lib.object_ids.erase(moved.object_id)
		lib.object_ids.append(moved.object_id)
	return moved


func resolve_top() -> void:
	finish_top_resolution()


func finish_top_resolution() -> void:
	if not (state.stack is MagicStack) or (state.stack as MagicStack).is_empty():
		return
	var done: bool = (state.stack as MagicStack).resolve_top(self)
	if not done:
		return
	if sba != null and sba.check(self):
		return
	priority.give(state, state.active_player_id)


func _submit_pass(action: GameAction) -> SubmitResult:
	return priority.submit_pass(self, action)


func _submit_play_land(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		r.error = "not in priority"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	if not _can_play_land(action.player_id):
		r.error = "cannot play a land"
		return r
	var obj: GameObject = state.objects.get(action.object_id)
	var land_ok := obj != null and obj.controller_id == action.player_id and obj.zone == EngineEnums.ZoneId.HAND
	var exile_land := obj != null and obj.zone == EngineEnums.ZoneId.EXILE and obj.may_play_controller == action.player_id
	if not land_ok and not exile_land:
		r.error = "land not in hand"
		return r
	if not _is_land(obj):
		r.error = "not a land"
		return r
	var moved: GameObject = state.zones.move(obj.object_id, EngineEnums.ZoneId.BATTLEFIELD)
	if moved == null:
		r.error = "move failed"
		return r
	state.land_played[action.player_id] = true
	r.ok = true
	return r


func _submit_activate_mana(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY and state.mode != EngineEnums.EngineMode.PAYING_COSTS:
		r.error = "mana ability not legal now"
		return r
	if state.mode == EngineEnums.EngineMode.GIVING_PRIORITY and action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	if state.mode == EngineEnums.EngineMode.PAYING_COSTS and action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your payment"
		return r
	var obj: GameObject = state.objects.get(action.object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD or obj.controller_id != action.player_id:
		r.error = "illegal source"
		return r
	if obj.definition == null or not (obj.definition is CardDefinition):
		r.error = "no definition"
		return r
	var ab: Ability = null
	if action.ability_id != &"":
		ab = _ability_on(obj, action.ability_id)
	else:
		for candidate in _active_abilities(obj):
			if candidate is Ability and (candidate as Ability).is_mana():
				ab = candidate
				break
	if ab == null or not ab.is_mana():
		r.error = "not a mana ability"
		return r
	if summoning_sickness_blocks(obj, ab):
		r.error = "summoning sickness"
		return r
	if not costs.can_pay(obj, ab):
		r.error = "cannot pay"
		return r
	costs.pay(obj, ab)
	for fx in ab.effects:
		if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA":
			var produced := ManaCost.parse(str((fx as AbilityEffect).params.get("mana", "")))
			mana.add(action.player_id, produced)
	state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, action.player_id, {
		object_id = obj.object_id,
		ability_id = str(ab.ability_id),
	})
	r.ok = true
	return r


func _submit_cast_spell(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		r.error = "not in priority"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	var obj: GameObject = state.objects.get(action.object_id)
	if obj == null or obj.controller_id != action.player_id:
		r.error = "illegal spell"
		return r
	var from_exile := obj.zone == EngineEnums.ZoneId.EXILE and obj.may_play_controller == action.player_id
	if obj.zone != EngineEnums.ZoneId.HAND and obj.zone != EngineEnums.ZoneId.COMMAND and not from_exile:
		r.error = "not in hand or command"
		return r
	if from_exile and obj.controller_id != action.player_id and obj.may_play_controller != action.player_id:
		r.error = "illegal spell"
		return r
	if _is_land(obj):
		r.error = "use PLAY_LAND"
		return r
	if not _timing_ok_to_cast(action.player_id, obj):
		r.error = "illegal timing"
		return r
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	_cast_source = obj.object_id
	_cast_from_command = obj.zone == EngineEnums.ZoneId.COMMAND
	_cast_targets = []
	_cast_queries = []
	var sp: Ability = def.spell_ability() if def != null else null
	if sp != null and not sp.targets.is_empty():
		_cast_queries = sp.targets.duplicate()
		state.mode = EngineEnums.EngineMode.CASTING
		state.awaiting = {player_id = action.player_id, type = &"targets", source_id = obj.object_id}
		state.passed_since_action.clear()
		r.ok = true
		return r
	return _begin_payment(action.player_id, def, action.extra)


func _submit_pay_mana(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.PAYING_COSTS:
		r.error = "not paying"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your payment"
		return r
	if _payment == null:
		r.error = "no remaining cost"
		return r
	var pool: ManaPool = mana.pool(action.player_id)
	if pool == null or not pool.can_pay(_payment):
		r.error = "cannot pay"
		return r
	pool.pay(_payment)
	_payment = ManaCost.new()
	r.ok = true
	return r


func _submit_confirm_pay(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.PAYING_COSTS:
		r.error = "not paying"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your payment"
		return r
	if _payment == null or not _payment.is_zero():
		r.error = "cost remaining"
		return r
	if _act_paying:
		return _put_activated_on_stack()
	return _put_spell_on_stack(action.player_id)


func _submit_cancel_cast(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.PAYING_COSTS and state.mode != EngineEnums.EngineMode.CASTING:
		r.error = "not paying"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your payment"
		return r
	_cast_source = 0
	_payment = null
	_cast_from_command = false
	_cast_queries = []
	_cast_targets = []
	_act_paying = false
	_act_ability_id = &""
	priority.give(state, action.player_id)
	state.passed_since_action.clear()
	r.ok = true
	return r


func _put_spell_on_stack(player_id: int) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	var obj: GameObject = state.objects.get(_cast_source)
	if obj == null:
		r.error = "source gone"
		return r
	var source_id: int = obj.object_id
	var moved: GameObject = state.zones.move(obj.object_id, EngineEnums.ZoneId.STACK)
	if moved == null:
		r.error = "stack move failed"
		return r
	var entry: StackEntry = (state.stack as MagicStack).push_spell(
		moved, player_id, _cast_targets, state.next_stack_id, source_id
	)
	state.next_stack_id += 1
	var def: CardDefinition = moved.definition as CardDefinition if moved.definition is CardDefinition else null
	state.log.append(EngineEnums.EventType.SPELL_CAST, player_id, {
		object_id = moved.object_id,
		stack_id = entry.stack_id,
	})
	if _cast_from_command and def != null:
		var key := def.oracle_id if def.oracle_id != "" else def.name
		var prev := int(state.players[player_id].commander_cast_count.get(key, 0))
		state.players[player_id].commander_cast_count[key] = prev + 1
	_cast_source = 0
	_payment = null
	_cast_from_command = false
	state.passed_since_action.clear()
	if triggers != null:
		triggers.on_spell_cast(self, moved, player_id)
	if sba != null and sba.check(self):
		r.ok = true
		return r
	state.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	state.priority_player_id = player_id
	state.awaiting = {player_id = player_id, type = &"priority"}
	r.ok = true
	return r


func _legal_paying(player_id: int) -> Array:
	var out: Array = []
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	out.append_array(_legal_mana_abilities(player_id))
	if _payment != null and not _payment.is_zero():
		var pool: ManaPool = mana.pool(player_id)
		if pool != null and pool.can_pay(_payment):
			var pay := GameAction.new()
			pay.kind = GameAction.Kind.PAY_MANA
			pay.player_id = player_id
			out.append(pay)
	if _payment == null or _payment.is_zero():
		var conf := GameAction.new()
		conf.kind = GameAction.Kind.CONFIRM_PAY
		conf.player_id = player_id
		out.append(conf)
	var cancel := GameAction.new()
	cancel.kind = GameAction.Kind.CANCEL_CAST
	cancel.player_id = player_id
	out.append(cancel)
	return out


func _legal_mana_abilities(player_id: int) -> Array:
	var out: Array = []
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var obj: GameObject = state.objects.get(oid)
		if obj == null or obj.controller_id != player_id:
			continue
		if obj.definition == null or not (obj.definition is CardDefinition):
			continue
		for a in _active_abilities(obj):
			var ab := a as Ability
			if ab == null or not ab.is_mana():
				continue
			if summoning_sickness_blocks(obj, ab):
				continue
			if not costs.can_pay(obj, ab):
				continue
			var act := GameAction.new()
			act.kind = GameAction.Kind.ACTIVATE_MANA_ABILITY
			act.player_id = player_id
			act.object_id = obj.object_id
			act.ability_id = ab.ability_id
			out.append(act)
	return out


func _can_play_land(player_id: int) -> bool:
	if player_id != state.active_player_id:
		return false
	if not _is_main_phase():
		return false
	if not _stack_empty():
		return false
	return not bool(state.land_played.get(player_id, false))


func _timing_ok_to_cast(player_id: int, obj: GameObject) -> bool:
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	if def != null and def.is_instant():
		return true
	if player_id != state.active_player_id:
		return false
	if not _is_main_phase():
		return false
	return _stack_empty()


func _is_main_phase() -> bool:
	return state.phase == EngineEnums.Phase.MAIN_1 or state.phase == EngineEnums.Phase.MAIN_2


func _stack_empty() -> bool:
	if state.stack == null:
		return true
	if state.stack is MagicStack:
		return (state.stack as MagicStack).is_empty()
	return true


func _submit_choose_replacement(action: GameAction) -> SubmitResult:
	if state.replacement == null:
		var r := SubmitResult.new()
		r.ok = false
		r.error = "illegal replacement"
		return r
	return state.replacement.submit(self, action)


func _legal_choose_replacement(player_id: int) -> Array:
	if state.replacement == null:
		return []
	return state.replacement.legal_actions(state, player_id)


func _submit_choose_sba(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if sba == null or not sba.apply_choose(self, action.player_id, action.object_id):
		r.error = "illegal sba choice"
		return r
	r.ok = true
	return r


func _legal_choose_sba(player_id: int) -> Array:
	var out: Array = []
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	var ids: Array = state.awaiting.get("object_ids", [])
	for oid in ids:
		var a := GameAction.new()
		a.kind = GameAction.Kind.CHOOSE_SBA
		a.player_id = player_id
		a.object_id = int(oid)
		out.append(a)
	return out


func _begin_payment(player_id: int, def: CardDefinition, extra: Dictionary) -> SubmitResult:
	var r := SubmitResult.new()
	_payment = ManaCost.parse(def.mana_cost if def else "")
	if _cast_from_command:
		var key := def.oracle_id if def != null and def.oracle_id != "" else (def.name if def else "")
		var n := int(state.players[player_id].commander_cast_count.get(key, 0))
		_payment.generic += n * state.rules.commander_tax_step
	state.mode = EngineEnums.EngineMode.PAYING_COSTS
	state.awaiting = {player_id = player_id, type = &"pay", source_id = _cast_source}
	state.passed_since_action.clear()
	if bool(extra.get("auto_pay", false)) and _auto_finish_payment(player_id):
		return _put_spell_on_stack(player_id)
	r.ok = true
	return r


func _submit_choose_targets(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.CASTING:
		r.error = "not targeting"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your choice"
		return r
	if _cast_queries.is_empty() or action.targets.is_empty():
		r.error = "no target"
		return r
	var q: Dictionary = _cast_queries[0] if _cast_queries[0] is Dictionary else {}
	var tid := int(action.targets[0])
	if targeting == null or not targeting.is_legal(self, q, tid, _cast_source):
		r.error = "illegal target"
		return r
	_cast_targets = action.targets.duplicate()
	if _act_ability_id != &"":
		var src: GameObject = state.objects.get(_cast_source)
		var ab: Ability = _ability_on(src, _act_ability_id)
		return _begin_ability_payment(action.player_id, src, ab, action.extra)
	var obj: GameObject = state.objects.get(_cast_source)
	var def: CardDefinition = obj.definition as CardDefinition if obj != null and obj.definition is CardDefinition else null
	return _begin_payment(action.player_id, def, action.extra)


func _legal_choose_targets(player_id: int) -> Array:
	var out: Array = []
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	if _cast_queries.is_empty() or targeting == null:
		return out
	var q: Dictionary = _cast_queries[0] if _cast_queries[0] is Dictionary else {}
	for tid in targeting.legal_ids(self, q, _cast_source):
		var a := GameAction.new()
		a.kind = GameAction.Kind.CHOOSE_TARGETS
		a.player_id = player_id
		a.object_id = _cast_source
		a.targets = [tid]
		out.append(a)
	return out


func _is_land(obj: GameObject) -> bool:
	return obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).is_land()


func apply_combat_damage() -> void:
	if not (state.combat is CombatState):
		return
	var cs := state.combat as CombatState
	var n := state.players.size()
	if n <= 0:
		return
	var pending_lethal: Array[int] = []
	for aid in cs.attacker_ids:
		var attacker: GameObject = state.objects.get(int(aid))
		if attacker == null or attacker.zone != EngineEnums.ZoneId.BATTLEFIELD:
			continue
		var defender := _attacker_defender(cs, int(aid))
		if defender < 0:
			continue
		var atk_dmg := _power_of(attacker)
		var blocker := _assigned_blocker(cs, int(aid))
		if blocker == null:
			if atk_dmg <= 0:
				continue
			state.players[defender].life -= atk_dmg
			state.log.append(EngineEnums.EventType.DAMAGE, state.active_player_id, {
				to_player = defender,
				amount = atk_dmg,
				object_id = attacker.object_id,
				combat = true,
			})
			if triggers != null:
				triggers.on_combat_damage_to_player(self, attacker, defender, atk_dmg)
			if attacker.is_commander:
				var key := str(attacker.owner_id) + ":" + str((attacker.definition as CardDefinition).name if attacker.definition is CardDefinition else attacker.object_id)
				var prev := int(state.players[defender].commander_damage_from.get(key, 0))
				state.players[defender].commander_damage_from[key] = prev + atk_dmg
			continue
		if atk_dmg > 0:
			_mark_combat_damage(attacker, blocker, atk_dmg, pending_lethal)
		var blk_dmg := _power_of(blocker)
		if blk_dmg > 0:
			_mark_combat_damage(blocker, attacker, blk_dmg, pending_lethal)
	for oid in pending_lethal:
		_bury_if_lethal(oid)
	if sba != null:
		sba.check(self)


func _submit_declare_attackers(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.step != EngineEnums.Step.DECLARE_ATTACKERS:
		r.error = "not declare attackers"
		return r
	if action.player_id != state.active_player_id:
		r.error = "not active"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	var ids: Array = action.extra.get("attackers", [])
	var legal := _legal_attacker_ids(action.player_id)
	for raw in ids:
		if not legal.has(int(raw)):
			r.error = "illegal attacker"
			return r
	var requested_defender := int(action.extra.get("defending_player_id", -1))
	if not _is_legal_defender(action.player_id, requested_defender):
		requested_defender = _default_defender(action.player_id)
	var per: Variant = action.extra.get("defenders", {})
	var assigned := {}
	var use_map := per is Dictionary and not (per as Dictionary).is_empty()
	if use_map:
		for raw in ids:
			var oid := int(raw)
			var chosen := int((per as Dictionary).get(oid, (per as Dictionary).get(str(oid), requested_defender)))
			if not _is_legal_defender(action.player_id, chosen):
				r.error = "illegal defender"
				return r
			assigned[oid] = chosen
	if not (state.combat is CombatState):
		state.combat = CombatState.new()
	var cs := state.combat as CombatState
	cs.attacker_ids.clear()
	cs.blockers.clear()
	cs.defenders.clear()
	for raw in ids:
		var oid := int(raw)
		cs.attacker_ids.append(oid)
		var obj: GameObject = state.objects.get(oid)
		if obj != null:
			obj.tapped = true
		if use_map:
			cs.defenders[oid] = int(assigned[oid])
		else:
			cs.defenders[oid] = requested_defender
	if use_map and not cs.attacker_ids.is_empty():
		cs.defending_player_id = int(cs.defenders[cs.attacker_ids[0]])
	else:
		cs.defending_player_id = requested_defender
	r.ok = true
	return r


func _submit_declare_blockers(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.step != EngineEnums.Step.DECLARE_BLOCKERS:
		r.error = "not declare blockers"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	if not (state.combat is CombatState):
		r.error = "no combat"
		return r
	var cs := state.combat as CombatState
	var raw: Variant = action.extra.get("blockers", {})
	if not (raw is Dictionary):
		r.error = "blockers must be a dictionary"
		return r
	var next_blocks: Dictionary = cs.blockers.duplicate()
	var used := {}
	for existing in next_blocks.values():
		if existing is Array:
			for bid in existing:
				used[int(bid)] = true
	for key in (raw as Dictionary).keys():
		var attacker_id := int(key)
		if not cs.attacker_ids.has(attacker_id):
			r.error = "not an attacker"
			return r
		if _attacker_defender(cs, attacker_id) != action.player_id:
			r.error = "not the defending player"
			return r
		var entry: Variant = (raw as Dictionary)[key]
		var bids: Array = []
		if entry is Array:
			bids = entry
		elif typeof(entry) == TYPE_INT or typeof(entry) == TYPE_FLOAT or str(entry).is_valid_int():
			bids = [int(entry)]
		else:
			r.error = "bad blocker assignment"
			return r
		if bids.size() > 1:
			r.error = "one blocker per attacker"
			return r
		if bids.is_empty():
			next_blocks.erase(attacker_id)
			continue
		var bid := int(bids[0])
		if used.has(bid):
			r.error = "blocker already assigned"
			return r
		if not _can_block(bid, action.player_id):
			r.error = "illegal blocker"
			return r
		used[bid] = true
		next_blocks[attacker_id] = [bid]
	if (raw as Dictionary).is_empty() and not _player_is_defender(cs, action.player_id):
		r.error = "not the defending player"
		return r
	cs.blockers = next_blocks
	r.ok = true
	return r


func _player_is_defender(cs: CombatState, player_id: int) -> bool:
	if cs.defending_player_id == player_id:
		return true
	for v in cs.defenders.values():
		if int(v) == player_id:
			return true
	return false


func _attacker_defender(cs: CombatState, attacker_id: int) -> int:
	if cs.defenders.has(attacker_id):
		var chosen := int(cs.defenders[attacker_id])
		if _is_legal_defender(state.active_player_id, chosen):
			return chosen
	if _is_legal_defender(state.active_player_id, cs.defending_player_id):
		return cs.defending_player_id
	var fallback := _default_defender(state.active_player_id)
	if fallback >= 0:
		cs.defending_player_id = fallback
	return fallback


func _can_block(object_id: int, defender_id: int) -> bool:
	var obj: GameObject = state.objects.get(object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return false
	if obj.controller_id != defender_id or obj.tapped:
		return false
	return obj.definition is CardDefinition and (obj.definition as CardDefinition).is_creature()


func _assigned_blocker(cs: CombatState, attacker_id: int) -> GameObject:
	var raw: Variant = cs.blockers.get(attacker_id, [])
	if not (raw is Array) or (raw as Array).is_empty():
		return null
	var blocker: GameObject = state.objects.get(int((raw as Array)[0]))
	if blocker == null or blocker.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return null
	return blocker


func _power_of(obj: GameObject) -> int:
	if layers != null:
		return layers.power(state, obj)
	if obj.definition is CardDefinition and (obj.definition as CardDefinition).power.is_valid_int():
		return int((obj.definition as CardDefinition).power)
	return 0


func _toughness_of(obj: GameObject) -> int:
	if layers != null:
		return int(layers.snapshot(state, obj).get("toughness", 0))
	if obj.definition is CardDefinition and (obj.definition as CardDefinition).toughness.is_valid_int():
		return int((obj.definition as CardDefinition).toughness)
	return 0


func _mark_combat_damage(source: GameObject, target: GameObject, amount: int, pending_lethal: Array[int]) -> void:
	target.damage_marked += amount
	state.log.append(EngineEnums.EventType.DAMAGE, source.controller_id, {
		to_object = target.object_id,
		amount = amount,
		object_id = source.object_id,
	})
	if target.definition is CardDefinition and (target.definition as CardDefinition).is_creature():
		if target.damage_marked >= _toughness_of(target) and not pending_lethal.has(target.object_id):
			pending_lethal.append(target.object_id)


func _bury_if_lethal(object_id: int) -> void:
	var obj: GameObject = state.objects.get(object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	if not (obj.definition is CardDefinition) or not (obj.definition as CardDefinition).is_creature():
		return
	if obj.damage_marked >= _toughness_of(obj):
		state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func _is_legal_defender(attacking_player_id: int, defender_id: int) -> bool:
	if defender_id < 0 or defender_id == attacking_player_id:
		return false
	for p in state.players:
		if p.player_id == defender_id:
			return not p.lost
	return false


func _default_defender(attacking_player_id: int) -> int:
	var n := state.players.size()
	if n <= 0:
		return -1
	for step in range(1, n):
		var candidate := (attacking_player_id + step) % n
		if _is_legal_defender(attacking_player_id, candidate):
			return candidate
	return -1


func _auto_finish_payment(player_id: int) -> bool:
	if _payment == null:
		return true
	var guard := 0
	while not _payment.is_zero() and guard < 24:
		guard += 1
		var pool: ManaPool = mana.pool(player_id)
		if pool != null and pool.can_pay(_payment):
			pool.pay(_payment)
			_payment = ManaCost.new()
			return true
		var pick: GameAction = _pick_auto_mana(player_id)
		if pick == null:
			break
		var tap_r := _submit_activate_mana(pick)
		if not tap_r.ok:
			break
	var pool2: ManaPool = mana.pool(player_id)
	if pool2 != null and _payment != null and pool2.can_pay(_payment):
		pool2.pay(_payment)
		_payment = ManaCost.new()
		return true
	return _payment != null and _payment.is_zero()


func _pick_auto_mana(player_id: int) -> GameAction:
	var acts: Array = _legal_mana_abilities(player_id)
	var best: GameAction = null
	for a in acts:
		var produced := _produced_mana(int((a as GameAction).object_id), (a as GameAction).ability_id)
		if produced == null:
			continue
		if _payment.r > 0 and produced.r > 0:
			return a
		if _payment.u > 0 and produced.u > 0:
			return a
		if _payment.w > 0 and produced.w > 0:
			return a
		if _payment.b > 0 and produced.b > 0:
			return a
		if _payment.g > 0 and produced.g > 0:
			return a
		if _payment.generic > 0 and produced.cmc() > 0:
			best = a
	return best


func _produced_mana(object_id: int, ability_id: StringName) -> ManaCost:
	var obj: GameObject = state.objects.get(object_id)
	if obj == null or not (obj.definition is CardDefinition):
		return null
	var ab: Ability = (obj.definition as CardDefinition).find_ability(ability_id)
	if ab == null:
		var mas: Array = (obj.definition as CardDefinition).mana_abilities()
		ab = mas[0] if not mas.is_empty() else null
	if ab == null:
		return null
	for fx in ab.effects:
		if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA":
			return ManaCost.parse(str((fx as AbilityEffect).params.get("mana", "")))
	return null


func legal_attacker_ids(player_id: int) -> Array:
	return _legal_attacker_ids(player_id)


func _legal_attacker_ids(player_id: int) -> Array:
	var out: Array = []
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var obj: GameObject = state.objects.get(oid)
		if obj == null or obj.controller_id != player_id:
			continue
		if obj.tapped:
			continue
		if not (obj.definition is CardDefinition) or not (obj.definition as CardDefinition).is_creature():
			continue
		if obj.summoned_this_turn and not _has_haste(obj):
			continue
		out.append(obj.object_id)
	return out


func _submit_activate_ability(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		r.error = "not in priority"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	var obj: GameObject = state.objects.get(action.object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD or obj.controller_id != action.player_id:
		r.error = "illegal source"
		return r
	var ab: Ability = _ability_on(obj, action.ability_id)
	if ab == null or not ab.is_activated():
		r.error = "not an activated ability"
		return r
	var why := _activation_reason(obj, ab)
	if why != "LEGAL":
		r.error = why.to_lower().replace("_", " ")
		return r
	_cast_targets = []
	_cast_queries = []
	_act_ability_id = ab.ability_id
	_cast_source = obj.object_id
	if not ab.targets.is_empty():
		_cast_queries = ab.targets.duplicate()
		state.mode = EngineEnums.EngineMode.CASTING
		state.awaiting = {player_id = action.player_id, type = &"targets", source_id = obj.object_id}
		state.passed_since_action.clear()
		r.ok = true
		return r
	return _begin_ability_payment(action.player_id, obj, ab, action.extra)


func _legal_activated(player_id: int) -> Array:
	var out: Array = []
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var obj: GameObject = state.objects.get(oid)
		if obj == null or obj.controller_id != player_id:
			continue
		for a in _active_abilities(obj):
			var ab := a as Ability
			if ab == null or not ab.is_activated():
				continue
			if _activation_reason(obj, ab) != "LEGAL":
				continue
			var act := GameAction.new()
			act.kind = GameAction.Kind.ACTIVATE_ABILITY
			act.player_id = player_id
			act.object_id = obj.object_id
			act.ability_id = ab.ability_id
			out.append(act)
	return out


## CR 302.6 and 602.5a: summoning sickness stops a tap or untap symbol in the cost.
## It does not turn off the rest of a creature's activated abilities. Haste (702.10) removes it.
func summoning_sickness_blocks(obj: GameObject, ab: Ability) -> bool:
	if obj == null or ab == null:
		return false
	if not ab.uses_tap_symbol_cost():
		return false
	if not _is_creature_now(obj):
		return false
	if not obj.summoned_this_turn:
		return false
	if _has_haste(obj):
		return false
	return true


func _has_haste(obj: GameObject) -> bool:
	if obj == null:
		return false
	if layers != null:
		return layers.has_keyword(state, obj, "Haste")
	if obj.definition is CardDefinition:
		for kw in (obj.definition as CardDefinition).keywords:
			if str(kw).to_lower() == "haste":
				return true
	return false


func _is_creature_now(obj: GameObject) -> bool:
	if obj == null:
		return false
	if layers != null:
		return str(layers.snapshot(state, obj).get("type_line", "")).contains("Creature")
	return obj.definition is CardDefinition and (obj.definition as CardDefinition).is_creature()


func _active_abilities(obj: GameObject) -> Array:
	if obj == null:
		return []
	if layers != null:
		return layers.abilities_for(state, obj)
	if not (obj.definition is CardDefinition):
		return []
	var out: Array = []
	for a in (obj.definition as CardDefinition).abilities:
		if a is Ability and not (a as Ability).granted:
			out.append(a)
	return out


func _ability_on(obj: GameObject, ability_id: StringName) -> Ability:
	if obj == null or ability_id == &"":
		return null
	for a in _active_abilities(obj):
		if a is Ability and (a as Ability).ability_id == ability_id:
			return a
	return null


func _activation_reason(obj: GameObject, ab: Ability) -> String:
	if obj == null or ab == null:
		return "NO_ABILITY"
	if obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return "NOT_BATTLEFIELD"
	var actor := int(state.awaiting.get("player_id", -1))
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		return "NOT_YOUR_PRIORITY"
	if actor != obj.controller_id:
		return "NOT_CONTROLLER"
	if ab.has_tap_cost() and obj.tapped:
		return "TAPPED"
	if ab.has_untap_cost() and not obj.tapped:
		return "CANNOT_PAY"
	if summoning_sickness_blocks(obj, ab):
		return "SUMMONING_SICKNESS"
	if costs != null and not costs.can_pay(obj, ab):
		return "CANNOT_PAY"
	return "LEGAL"


func _begin_ability_payment(player_id: int, src: GameObject, ab: Ability, extra: Dictionary) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if src == null or ab == null:
		r.error = "illegal source"
		return r
	_payment = costs.mana_cost(ab)
	_act_ability_id = ab.ability_id
	_cast_source = src.object_id
	if _payment == null or _payment.is_zero():
		_act_paying = false
		return _put_activated_on_stack()
	_act_paying = true
	state.mode = EngineEnums.EngineMode.PAYING_COSTS
	state.awaiting = {player_id = player_id, type = &"pay", source_id = src.object_id}
	state.passed_since_action.clear()
	if bool(extra.get("auto_pay", false)):
		if _auto_finish_payment(player_id):
			return _put_activated_on_stack()
		_act_paying = false
		_act_ability_id = &""
		_payment = null
		_cast_source = 0
		_cast_targets = []
		_cast_queries = []
		priority.give(state, player_id)
		r.error = "cannot pay"
		return r
	r.ok = true
	return r


func _put_activated_on_stack() -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	var obj: GameObject = state.objects.get(_cast_source)
	var ab: Ability = _ability_on(obj, _act_ability_id)
	if obj == null or ab == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		r.error = "source gone"
		return r
	if _payment != null and not _payment.is_zero():
		r.error = "cost remaining"
		return r
	if summoning_sickness_blocks(obj, ab):
		r.error = "summoning sickness"
		return r
	if not costs.can_pay(obj, ab):
		r.error = "cannot pay"
		return r
	var player_id := obj.controller_id
	costs.pay(obj, ab)
	var entry := StackEntry.new()
	entry.stack_id = state.next_stack_id
	state.next_stack_id += 1
	entry.kind = StackEntry.Kind.ACTIVATED
	entry.object_id = 0
	entry.source_id = obj.object_id
	entry.controller_id = player_id
	entry.ability_id = ab.ability_id
	entry.effects = ab.effects.duplicate()
	entry.targets = _cast_targets.duplicate()
	(state.stack as MagicStack).push(entry)
	state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, player_id, {
		object_id = obj.object_id,
		ability_id = str(ab.ability_id),
		stack_id = entry.stack_id,
	})
	_cast_source = 0
	_payment = null
	_cast_targets = []
	_cast_queries = []
	_act_paying = false
	_act_ability_id = &""
	state.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	state.priority_player_id = player_id
	state.awaiting = {player_id = player_id, type = &"priority"}
	state.passed_since_action.clear()
	r.ok = true
	return r


func _legal_decision(player_id: int) -> Array:
	var out: Array = []
	if state.mode != EngineEnums.EngineMode.AWAITING_DECISION:
		return out
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	if not (state.pending_decision is PlayerDecision):
		return out
	var dec := state.pending_decision as PlayerDecision
	if dec.kind == &"OPTIONAL_YES_NO":
		var yes := GameAction.new()
		yes.kind = GameAction.Kind.SUBMIT_DECISION
		yes.player_id = player_id
		out.append(yes)
		var no := GameAction.new()
		no.kind = GameAction.Kind.DECLINE_DECISION
		no.player_id = player_id
		out.append(no)
		return out
	for cand in dec.candidates:
		var pick := GameAction.new()
		pick.kind = GameAction.Kind.SUBMIT_DECISION
		pick.player_id = player_id
		pick.extra = {choice = cand}
		out.append(pick)
	if dec.optional:
		var decline := GameAction.new()
		decline.kind = GameAction.Kind.DECLINE_DECISION
		decline.player_id = player_id
		out.append(decline)
	return out


func _submit_decision(action: GameAction, accept: bool) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.AWAITING_DECISION:
		r.error = "no decision"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your choice"
		return r
	if not (state.pending_decision is PlayerDecision):
		r.error = "no decision"
		return r
	var dec := state.pending_decision as PlayerDecision
	if not (state.stack is MagicStack):
		r.error = "no stack"
		return r
	var stack := state.stack as MagicStack
	var entry: StackEntry = stack.top()
	if entry == null or entry.stack_id != dec.stack_id:
		r.error = "decision expired"
		return r
	var link := dec.link if dec.link != "" else "choice"
	if dec.kind == &"OPTIONAL_YES_NO":
		entry.choices[link] = accept
	elif not accept:
		if not dec.optional:
			r.error = "required choice"
			return r
		entry.choices[link] = false
	else:
		var chosen: Variant = action.extra.get("choice", null)
		if not dec.candidates.is_empty() and not dec.candidates.has(chosen):
			r.error = "illegal choice"
			return r
		if chosen == null:
			r.error = "no choice"
			return r
		entry.choices[link] = chosen
	state.pending_decision = null
	finish_top_resolution()
	r.ok = true
	return r


## Temporary selection report. Disable by ignoring the returned text.
func activation_report(object_id: int) -> Dictionary:
	var obj: GameObject = state.objects.get(object_id) if state != null else null
	var source_name := "Unknown"
	var sick := false
	var tapped := false
	var rows: Array = []
	if obj != null:
		sick = obj.summoned_this_turn
		tapped = obj.tapped
		if obj.definition is CardDefinition:
			source_name = (obj.definition as CardDefinition).name
		for a in _active_abilities(obj):
			var ab := a as Ability
			if ab == null or not ab.is_activated():
				continue
			var cond := _resolution_condition(obj, ab)
			var reason := _activation_reason(obj, ab)
			var mana_cost := costs.mana_cost(ab) if costs != null else ManaCost.new()
			var pool: ManaPool = mana.pool(obj.controller_id) if mana != null else null
			rows.append({
				ability_id = str(ab.ability_id),
				type = "ACTIVATED",
				cost = _cost_text(ab),
				requires_tap = ab.uses_tap_symbol_cost(),
				mana_available = pool == null or pool.can_pay(mana_cost),
				condition = str(cond.get("text", "—")),
				condition_result = bool(cond.get("result", true)),
				can_activate = reason == "LEGAL",
				reason = reason,
			})
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== ABILITY DEBUG ===")
	lines.append("Source:")
	lines.append(source_name)
	lines.append("Summoning Sick:")
	lines.append("TRUE" if sick else "FALSE")
	lines.append("Tapped:")
	lines.append("TRUE" if tapped else "FALSE")
	lines.append("Abilities Found:")
	lines.append(str(rows.size()))
	var n := 1
	for row in rows:
		var info: Dictionary = row
		if n > 1:
			lines.append("")
		lines.append("ABILITY %d" % n)
		lines.append("Type:")
		lines.append(str(info.get("type", "ACTIVATED")))
		lines.append("Cost:")
		lines.append(str(info.get("cost", "")))
		lines.append("Requires Tap:")
		lines.append("TRUE" if bool(info.get("requires_tap", false)) else "FALSE")
		lines.append("Mana Available:")
		lines.append("TRUE" if bool(info.get("mana_available", false)) else "FALSE")
		lines.append("Condition:")
		lines.append(str(info.get("condition", "—")))
		lines.append("Condition Result:")
		lines.append("TRUE" if bool(info.get("condition_result", false)) else "FALSE")
		lines.append("Can Activate:")
		lines.append("TRUE" if bool(info.get("can_activate", false)) else "FALSE")
		lines.append("Reason:")
		lines.append(str(info.get("reason", "")))
		n += 1
	lines.append("====================")
	return {
		text = "\n".join(lines),
		source = source_name,
		summoning_sick = sick,
		tapped = tapped,
		abilities = rows,
	}


## Oracle text uses the name before the comma for a legendary card.
func _card_subject(card_name: String) -> String:
	var comma := card_name.find(",")
	if comma > 0:
		return card_name.substr(0, comma)
	return card_name


func _cost_text(ab: Ability) -> String:
	if ab == null:
		return ""
	var s := ""
	if ab.has_tap_cost():
		s += "{T}"
	if ab.has_untap_cost():
		s += "{Q}"
	if costs != null:
		s += costs.mana_cost(ab).to_text()
	return s


func _resolution_condition(obj: GameObject, ab: Ability) -> Dictionary:
	var source_name := "It"
	if obj != null and obj.definition is CardDefinition:
		source_name = _card_subject((obj.definition as CardDefinition).name)
	for raw in ab.effects:
		if not (raw is AbilityEffect):
			continue
		var fx := raw as AbilityEffect
		if str(fx.kind) != "SET_CHARACTERISTICS":
			continue
		var sub := str(fx.params.get("if_subtype", ""))
		if sub == "":
			continue
		var result := false
		if layers != null and obj != null:
			result = layers.has_subtype(state, obj, sub)
		return {text = "%s is a %s" % [source_name, sub], result = result}
	return {text = "—", result = true}
