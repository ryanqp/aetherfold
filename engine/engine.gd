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
	for zone_id in [EngineEnums.ZoneId.HAND, EngineEnums.ZoneId.COMMAND]:
		var z: Zone = state.zones.get_zone(zone_id, player_id)
		if z == null:
			continue
		for oid in z.object_ids:
			var obj: GameObject = state.objects.get(oid)
			if obj == null or _is_land(obj):
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
			if r.ok:
				priority.note_action(state, action.player_id)
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
	if state.stack == null or not (state.stack is MagicStack):
		return
	var stack := state.stack as MagicStack
	var entry: StackEntry = stack.pop()
	if entry == null:
		return
	if executor != null:
		executor.resolve(self, entry)
	if entry.kind != StackEntry.Kind.SPELL:
		return
	var obj: GameObject = state.objects.get(entry.object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.STACK:
		return
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	if def != null and def.is_permanent_type():
		state.zones.move(obj.object_id, EngineEnums.ZoneId.BATTLEFIELD)
	else:
		state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func _submit_pass(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	if state.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		r.error = "not in priority"
		return r
	if action.player_id != int(state.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	var wrapped := priority.pass_from(state, action.player_id)
	if wrapped:
		turn.all_passed()
	r.ok = true
	return r


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
	if obj == null or obj.zone != EngineEnums.ZoneId.HAND or obj.controller_id != action.player_id:
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
	var def := obj.definition as CardDefinition
	var ab: Ability = null
	if action.ability_id != &"":
		ab = def.find_ability(action.ability_id)
	else:
		var mas: Array = def.mana_abilities()
		if not mas.is_empty():
			ab = mas[0]
	if ab == null or not ab.is_mana():
		r.error = "not a mana ability"
		return r
	if def.is_creature() and ab.has_tap_cost() and obj.summoned_this_turn:
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
	if obj.zone != EngineEnums.ZoneId.HAND and obj.zone != EngineEnums.ZoneId.COMMAND:
		r.error = "not in hand or command"
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
	var moved: GameObject = state.zones.move(obj.object_id, EngineEnums.ZoneId.STACK)
	if moved == null:
		r.error = "stack move failed"
		return r
	var entry := StackEntry.new()
	entry.stack_id = state.next_stack_id
	state.next_stack_id += 1
	entry.kind = StackEntry.Kind.SPELL
	entry.object_id = moved.object_id
	entry.source_id = obj.object_id
	entry.controller_id = player_id
	var def: CardDefinition = moved.definition as CardDefinition if moved.definition is CardDefinition else null
	if def != null:
		var sp: Ability = def.spell_ability()
		if sp != null:
			entry.ability_id = sp.ability_id
			entry.effects = sp.effects.duplicate()
	entry.targets = _cast_targets.duplicate()
	(state.stack as MagicStack).push(entry)
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
		var def := obj.definition as CardDefinition
		for a in def.mana_abilities():
			var ab := a as Ability
			if def.is_creature() and ab.has_tap_cost() and obj.summoned_this_turn:
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
	var r := SubmitResult.new()
	r.ok = false
	var dest := int(action.extra.get("dest_zone", EngineEnums.ZoneId.COMMAND))
	if state.replacement == null or not state.replacement.apply_choice(self, action.player_id, dest):
		r.error = "illegal replacement"
		return r
	r.ok = true
	return r


func _legal_choose_replacement(player_id: int) -> Array:
	var out: Array = []
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	var options: Array = state.awaiting.get("options", [])
	for dest in options:
		var a := GameAction.new()
		a.kind = GameAction.Kind.CHOOSE_REPLACEMENT
		a.player_id = player_id
		a.object_id = int(state.awaiting.get("object_id", 0))
		a.extra = {dest_zone = int(dest)}
		out.append(a)
	return out


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
	if targeting == null or not targeting.is_legal(self, q, tid):
		r.error = "illegal target"
		return r
	_cast_targets = action.targets.duplicate()
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
	for tid in targeting.legal_ids(self, q):
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
	var defender := (state.active_player_id + 1) % n
	cs.defending_player_id = defender
	for aid in cs.attacker_ids:
		var obj: GameObject = state.objects.get(int(aid))
		if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
			continue
		var snap: Dictionary = layers.snapshot(state, obj) if layers != null else {power = 0}
		var dmg := int(snap.get("power", 0))
		if dmg <= 0:
			continue
		state.players[defender].life -= dmg
		state.log.append(EngineEnums.EventType.DAMAGE, state.active_player_id, {
			to_player = defender,
			amount = dmg,
			object_id = obj.object_id,
		})
		if obj.is_commander:
			var key := str(obj.owner_id) + ":" + str((obj.definition as CardDefinition).name if obj.definition is CardDefinition else obj.object_id)
			var prev := int(state.players[defender].commander_damage_from.get(key, 0))
			state.players[defender].commander_damage_from[key] = prev + dmg
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
	if not (state.combat is CombatState):
		state.combat = CombatState.new()
	var cs := state.combat as CombatState
	cs.attacker_ids.clear()
	for raw in ids:
		var oid := int(raw)
		cs.attacker_ids.append(oid)
		var obj: GameObject = state.objects.get(oid)
		if obj != null:
			obj.tapped = true
	r.ok = true
	return r


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
		if obj.summoned_this_turn:
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
	if obj.definition == null or not (obj.definition is CardDefinition):
		r.error = "no definition"
		return r
	var def := obj.definition as CardDefinition
	var ab: Ability = def.find_ability(action.ability_id)
	if ab == null or not ab.is_activated():
		r.error = "not an activated ability"
		return r
	if def.is_creature() and ab.has_tap_cost() and obj.summoned_this_turn:
		r.error = "summoning sickness"
		return r
	if not costs.can_pay(obj, ab):
		r.error = "cannot pay"
		return r
	costs.pay(obj, ab)
	var entry := StackEntry.new()
	entry.stack_id = state.next_stack_id
	state.next_stack_id += 1
	entry.kind = StackEntry.Kind.ACTIVATED
	entry.object_id = 0
	entry.source_id = obj.object_id
	entry.controller_id = action.player_id
	entry.ability_id = ab.ability_id
	entry.effects = ab.effects.duplicate()
	(state.stack as MagicStack).push(entry)
	state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, action.player_id, {
		object_id = obj.object_id,
		ability_id = str(ab.ability_id),
		stack_id = entry.stack_id,
	})
	state.passed_since_action.clear()
	state.priority_player_id = action.player_id
	state.awaiting = {player_id = action.player_id, type = &"priority"}
	r.ok = true
	return r


func _legal_activated(player_id: int) -> Array:
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
		var def := obj.definition as CardDefinition
		for a in def.abilities:
			if not (a is Ability):
				continue
			var ab := a as Ability
			if not ab.is_activated():
				continue
			if def.is_creature() and ab.has_tap_cost() and obj.summoned_this_turn:
				continue
			if not costs.can_pay(obj, ab):
				continue
			var act := GameAction.new()
			act.kind = GameAction.Kind.ACTIVATE_ABILITY
			act.player_id = player_id
			act.object_id = obj.object_id
			act.ability_id = ab.ability_id
			out.append(act)
	return out
