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
## Log position up to which zone changes have been checked for enters-the-battlefield triggers.
var _zone_seq: int = 0
var _payment: ManaCost
var _cast_queries: Array = []
var _cast_targets: Array = []
var _cast_from_command: bool = false
## Seats that click their library to take the draw-step card (CR 504.1). Others draw automatically.
var manual_draw_seats: Array = []
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
	state.zones.lki_fn = Callable(self, "_lki")
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
	_zone_seq = state.log.seq()


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
	process_zone_events()
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


## The draw step card (CR 504.1), taken when a manual-draw seat clicks its library.
func take_turn_draw(player_id: int) -> GameObject:
	if state == null or not state.draw_pending or state.active_player_id != player_id:
		return null
	state.draw_pending = false
	return draw_card(player_id)


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


## Last known power and toughness, recorded as a permanent leaves the battlefield.
## "Dinosaur spells you cast cost {1} less to cast": how much generic mana the player's permanents
## take off the cost of this spell (CR 601.2f).
func cost_reduction(player_id: int, spell: GameObject) -> int:
	if spell == null:
		return 0
	var total := _own_discount(player_id, spell)
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 0
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or src.controller_id != player_id or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("cost_reduction"):
				continue
			var spec: Dictionary = ab.static_spec["cost_reduction"]
			var f: Variant = spec.get("filter", {})
			if f is Dictionary and Query._matches(spell, src, f):
				total += int(spec.get("amount", 1))
	return total


## "This spell costs {2} less to cast if it targets a Dinosaur you control." While you are casting it the
## chosen targets decide; before that (is it castable?) it counts when some legal target would qualify.
func _own_discount(player_id: int, spell: GameObject) -> int:
	if not (spell.definition is CardDefinition):
		return 0
	var total := 0
	for a in (spell.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("cost_reduction_if_target"):
			continue
		var spec: Dictionary = ab.static_spec["cost_reduction_if_target"]
		var q: Dictionary = spec.get("query", {})
		var hit := false
		if _cast_source == spell.object_id and not _cast_targets.is_empty():
			for tid in _cast_targets:
				var t: GameObject = state.objects.get(int(tid))
				if t != null and Query._matches(t, spell, q):
					hit = true
		elif _cast_source != spell.object_id:
			var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
			if bf != null:
				for oid in bf.object_ids:
					var t2: GameObject = state.objects.get(oid)
					if t2 != null and t2.controller_id == player_id and Query._matches(t2, spell, q):
						hit = true
						break
		if hit:
			total += int(spec.get("amount", 0))
	return total


## The generic-and-colored cost to cast `spell` right now (commander tax and reductions included).
func effective_cost(player_id: int, spell: GameObject, extra_generic: int = 0) -> ManaCost:
	var def: CardDefinition = spell.definition as CardDefinition if spell != null and spell.definition is CardDefinition else null
	var cost := ManaCost.parse(def.mana_cost if def else "")
	## Hybrid, X and similar symbols aren't parsed; the printed total beyond the parsed symbols counts as generic.
	if def != null:
		cost.generic += maxi(0, def.cmc - cost.cmc())
	cost.generic += extra_generic
	cost.generic = maxi(0, cost.generic - cost_reduction(player_id, spell))
	return cost


func _lki(obj: GameObject) -> Dictionary:
	return {power = power_of(obj), toughness = toughness_of(obj)}


func resolve_top() -> void:
	finish_top_resolution()


func finish_top_resolution() -> void:
	if not (state.stack is MagicStack) or (state.stack as MagicStack).is_empty():
		return
	var done: bool = (state.stack as MagicStack).resolve_top(self)
	if not done:
		return
	process_zone_events()
	var sba_pending: bool = sba != null and sba.check(self)
	process_zone_events()
	if sba_pending:
		return
	priority.give(state, state.active_player_id)


## Looks at zone changes since the last check: permanents that entered the battlefield fire their
## "when ~ enters" triggers (CR 603.6a), and a permanent that left returns what it exiled "until it
## leaves the battlefield" (CR 610.3). Run after every action and every resolution.
func process_zone_events() -> void:
	if state == null or state.log == null:
		return
	var guard := 0
	while guard < 20:
		guard += 1
		var events: Array = state.log.since(_zone_seq)
		if events.is_empty():
			return
		_zone_seq = state.log.seq()
		for ev in events:
			var e := ev as GameEvent
			if e == null:
				continue
			if e.type == EngineEnums.EventType.ZONE_CHANGE:
				var p: Dictionary = e.payload
				if int(p.get("from_zone", -1)) == EngineEnums.ZoneId.BATTLEFIELD:
					_release_exiled_with(int(p.get("from_id", 0)))
			if triggers != null:
				triggers.on_event(self, e)


## Cards a permanent exiled until it leaves the battlefield come back under their owner's control.
func _release_exiled_with(source_id: int) -> void:
	if not state.exile_links.has(source_id):
		return
	var ids: Array = state.exile_links[source_id]
	state.exile_links.erase(source_id)
	for oid in ids:
		var obj: GameObject = state.objects.get(int(oid))
		if obj != null and obj.zone == EngineEnums.ZoneId.EXILE:
			state.zones.move(obj.object_id, EngineEnums.ZoneId.BATTLEFIELD, obj.owner_id)


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
	var sacrificed := ab.has_sacrifice_cost()
	for fx in ab.effects:
		if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA":
			var produced := resolve_mana(action.player_id, ManaCost.parse(str((fx as AbilityEffect).params.get("mana", ""))))
			mana.add(action.player_id, produced)
	state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, action.player_id, {
		object_id = obj.object_id,
		ability_id = str(ab.ability_id),
	})
	if sacrificed:
		state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
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
	## CR 702.8: flash lets a permanent spell be cast any time you could cast an instant.
	if def != null and (def.is_instant() or _def_has_keyword(def, "flash")):
		return true
	if player_id != state.active_player_id:
		return false
	if not _is_main_phase():
		return false
	return _stack_empty()


func _def_has_keyword(def: CardDefinition, keyword: String) -> bool:
	for kw in def.keywords:
		if str(kw).to_lower() == keyword:
			return true
	return false


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
	var spell_obj: GameObject = state.objects.get(_cast_source)
	_payment.generic = maxi(0, _payment.generic - cost_reduction(player_id, spell_obj))
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
	## Targets are chosen one slot at a time; a choice that doesn't fill the last slot waits for the next.
	var chosen: Array = _cast_targets.duplicate()
	for raw in action.targets:
		var slot := chosen.size()
		if slot >= _cast_queries.size():
			break
		var q: Dictionary = _cast_queries[slot] if _cast_queries[slot] is Dictionary else {}
		var tid := int(raw)
		if chosen.has(tid) or targeting == null or not targeting.is_legal(self, q, tid, _cast_source):
			r.error = "illegal target"
			return r
		chosen.append(tid)
	_cast_targets = chosen
	if _cast_targets.size() < _cast_queries.size():
		state.passed_since_action.clear()
		r.ok = true
		return r
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
	var slot := _cast_targets.size()
	if slot >= _cast_queries.size():
		return out
	var q: Dictionary = _cast_queries[slot] if _cast_queries[slot] is Dictionary else {}
	for tid in targeting.legal_ids(self, q, _cast_source):
		if _cast_targets.has(tid):
			continue
		var a := GameAction.new()
		a.kind = GameAction.Kind.CHOOSE_TARGETS
		a.player_id = player_id
		a.object_id = _cast_source
		a.targets = [tid]
		out.append(a)
	return out


func _is_land(obj: GameObject) -> bool:
	return obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).is_land()


## Combat damage step (CR 510). With first or double strike in combat there are two
## damage steps (CR 510.4); both run here, with state-based actions in between.
## Damage is assigned automatically: lethal to each blocker in declared order, the rest
## to the last blocker, or to the player when the attacker has trample (CR 510.1c, 702.19).
func apply_combat_damage() -> void:
	if not (state.combat is CombatState):
		return
	if state.players.is_empty():
		return
	var cs := state.combat as CombatState
	var split := _combat_has_first_strike(cs)
	if split:
		_combat_damage_pass(cs, true, true)
		if sba != null:
			sba.check(self)
	_combat_damage_pass(cs, false, split)
	if sba != null:
		sba.check(self)


func _combat_has_first_strike(cs: CombatState) -> bool:
	for aid in cs.attacker_ids:
		var obj: GameObject = state.objects.get(int(aid))
		if _strikes_first(obj):
			return true
		for bid in _blocker_ids(cs, int(aid)):
			if _strikes_first(state.objects.get(int(bid))):
				return true
	return false


func _strikes_first(obj: GameObject) -> bool:
	return has_keyword(obj, "First strike") or has_keyword(obj, "Double strike")


## Whether obj deals damage in this pass. first_pass: the first-strike step.
func _deals_damage_now(obj: GameObject, first_pass: bool, split: bool) -> bool:
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return false
	if not split:
		return true
	if first_pass:
		return _strikes_first(obj)
	return has_keyword(obj, "Double strike") or not has_keyword(obj, "First strike")


func _blocker_ids(cs: CombatState, attacker_id: int) -> Array:
	var raw: Variant = cs.blockers.get(attacker_id, [])
	return raw if raw is Array else []


func _combat_damage_pass(cs: CombatState, first_pass: bool, split: bool) -> void:
	for aid in cs.attacker_ids:
		var attacker: GameObject = state.objects.get(int(aid))
		if attacker == null or attacker.zone != EngineEnums.ZoneId.BATTLEFIELD:
			continue
		var defender := _attacker_defender(cs, int(aid))
		var declared := _blocker_ids(cs, int(aid))
		var live: Array = []
		for bid in declared:
			var candidate: GameObject = state.objects.get(int(bid))
			if candidate != null and candidate.zone == EngineEnums.ZoneId.BATTLEFIELD:
				live.append(candidate)
		## Blockers strike back.
		for striker in live:
			if _deals_damage_now(striker, first_pass, split):
				var back := _power_of(striker)
				if back > 0:
					_combat_damage_to_object(striker, attacker, back)
		if not _deals_damage_now(attacker, first_pass, split):
			continue
		var power := _power_of(attacker)
		if power <= 0:
			continue
		if declared.is_empty():
			if defender >= 0:
				_combat_damage_to_player(attacker, defender, power)
			continue
		var trample := has_keyword(attacker, "Trample")
		var remaining := power
		for i in live.size():
			if remaining <= 0:
				break
			var target_blocker: GameObject = live[i]
			var amount := remaining
			if trample or i < live.size() - 1:
				amount = mini(remaining, _lethal_for(attacker, target_blocker))
			if amount > 0:
				_combat_damage_to_object(attacker, target_blocker, amount)
				remaining -= amount
		## A blocked creature with no blockers left deals no damage unless it has trample (CR 509.1h).
		if trample and remaining > 0 and defender >= 0:
			_combat_damage_to_player(attacker, defender, remaining)


## Damage that counts as lethal for assignment (CR 702.2c for deathtouch).
func _lethal_for(source: GameObject, target: GameObject) -> int:
	if has_keyword(source, "Deathtouch"):
		return 0 if target.deathtouch_damage else 1
	return maxi(0, _toughness_of(target) - target.damage_marked)


## Damage from a spell or ability, or a fight (CR 120.3). Deathtouch and lifelink still count.
func damage_object(source: GameObject, target: GameObject, amount: int) -> void:
	if amount <= 0 or target == null or target.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	target.damage_marked += amount
	if source != null and has_keyword(source, "Deathtouch"):
		target.deathtouch_damage = true
	state.log.append(EngineEnums.EventType.DAMAGE, source.controller_id if source != null else 0, {
		to_object = target.object_id,
		amount = amount,
		object_id = source.object_id if source != null else 0,
	})
	if source != null:
		_apply_lifelink(source, amount)


func _combat_damage_to_object(source: GameObject, target: GameObject, amount: int) -> void:
	target.damage_marked += amount
	if has_keyword(source, "Deathtouch"):
		target.deathtouch_damage = true
	state.log.append(EngineEnums.EventType.DAMAGE, source.controller_id, {
		to_object = target.object_id,
		amount = amount,
		object_id = source.object_id,
		combat = true,
	})
	_apply_lifelink(source, amount)


func _combat_damage_to_player(source: GameObject, player_id: int, amount: int) -> void:
	if player_id < 0 or player_id >= state.players.size():
		return
	state.players[player_id].life -= amount
	state.log.append(EngineEnums.EventType.DAMAGE, state.active_player_id, {
		to_player = player_id,
		amount = amount,
		object_id = source.object_id,
		combat = true,
	})
	if triggers != null:
		triggers.on_combat_damage_to_player(self, source, player_id, amount)
	if source.is_commander:
		var key := str(source.owner_id) + ":" + str((source.definition as CardDefinition).name if source.definition is CardDefinition else source.object_id)
		var prev := int(state.players[player_id].commander_damage_from.get(key, 0))
		state.players[player_id].commander_damage_from[key] = prev + amount
	_apply_lifelink(source, amount)


## Lifelink (CR 702.15b): the source's controller gains that much life.
func _apply_lifelink(source: GameObject, amount: int) -> void:
	if amount <= 0 or not has_keyword(source, "Lifelink"):
		return
	var pid := source.controller_id
	if pid < 0 or pid >= state.players.size():
		return
	state.players[pid].life += amount
	state.log.append(EngineEnums.EventType.LIFE_CHANGE, pid, {
		to_player = pid,
		amount = amount,
		gain = true,
		object_id = source.object_id,
	})


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
	cs.blocks_declared = false
	for raw in ids:
		var oid := int(raw)
		cs.attacker_ids.append(oid)
		var obj: GameObject = state.objects.get(oid)
		if obj != null and not has_keyword(obj, "Vigilance"):
			obj.tapped = true
		if use_map:
			cs.defenders[oid] = int(assigned[oid])
		else:
			cs.defenders[oid] = requested_defender
	if use_map and not cs.attacker_ids.is_empty():
		cs.defending_player_id = int(cs.defenders[cs.attacker_ids[0]])
	else:
		cs.defending_player_id = requested_defender
	if not ids.is_empty():
		state.log.append(EngineEnums.EventType.ATTACK, action.player_id, {
			attackers = ids.duplicate(),
			to_player = cs.defending_player_id,
		})
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
		if bids.is_empty():
			next_blocks.erase(attacker_id)
			continue
		var ordered: Array = []
		for raw_bid in bids:
			var bid := int(raw_bid)
			if used.has(bid):
				r.error = "blocker already assigned"
				return r
			if not _can_block(bid, action.player_id, attacker_id):
				r.error = "illegal blocker"
				return r
			used[bid] = true
			ordered.append(bid)
		next_blocks[attacker_id] = ordered
	if (raw as Dictionary).is_empty() and not _player_is_defender(cs, action.player_id):
		r.error = "not the defending player"
		return r
	## Menace (CR 702.110b): blocked only by two or more creatures.
	for key in next_blocks.keys():
		var group: Variant = next_blocks[key]
		if group is Array and (group as Array).size() == 1 and has_keyword(state.objects.get(int(key)), "Menace"):
			r.error = "menace needs two blockers"
			return r
	cs.blockers = next_blocks
	cs.blocks_declared = true
	var any_block := false
	for akey in next_blocks.keys():
		var group_v: Variant = next_blocks[akey]
		if group_v is Array:
			for bid in (group_v as Array):
				any_block = true
				state.log.append(EngineEnums.EventType.BLOCK, action.player_id, {
					blocker_id = int(bid), attacker_id = int(akey),
				})
	if not any_block:
		state.log.append(EngineEnums.EventType.BLOCK, action.player_id, {blocker_id = 0, attacker_id = 0})
	r.ok = true
	return r


## The player an attacker is attacking, or -1.
func defender_of(attacker_id: int) -> int:
	if not (state.combat is CombatState):
		return -1
	return _attacker_defender(state.combat as CombatState, attacker_id)


## Whether blocker_id could legally block attacker_id right now (untapped creature of the
## defending player, flying/reach). Menace is checked on the whole declaration, not here.
func can_block_attacker(blocker_id: int, attacker_id: int) -> bool:
	var defender := defender_of(attacker_id)
	if defender < 0:
		return false
	return _can_block(blocker_id, defender, attacker_id)


## Like can_block_attacker, for an attacker that hasn't been declared yet.
func can_block_as(blocker_id: int, defender_id: int, attacker_id: int) -> bool:
	return _can_block(blocker_id, defender_id, attacker_id)


func power_of(obj: GameObject) -> int:
	return _power_of(obj)


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


func _can_block(object_id: int, defender_id: int, attacker_id: int = -1) -> bool:
	var obj: GameObject = state.objects.get(object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return false
	if obj.controller_id != defender_id or obj.tapped:
		return false
	if not _is_creature_now(obj):
		return false
	if layers != null and layers.combat_restricted(state, obj):
		return false
	var attacker: GameObject = state.objects.get(attacker_id) if attacker_id >= 0 else null
	if attacker == null:
		return true
	## Flying (CR 702.9b): only creatures with flying or reach can block it.
	if has_keyword(attacker, "Flying") and not (has_keyword(obj, "Flying") or has_keyword(obj, "Reach")):
		return false
	return true


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
	## Colors still missing once what is already floating in the pool is counted.
	var pool: ManaPool = mana.pool(player_id)
	var need := {}
	for k in ["w", "u", "b", "r", "g", "colorless"]:
		need[k] = maxi(0, int(_payment.get(k)) - (int(pool.get(k)) if pool != null else 0))
	## Sources that always make the same mana go first, so a flexible source (any color, a dual land)
	## is still free for whatever color is left over.
	for flexible in [false, true]:
		var best: GameAction = null
		for a in acts:
			var ga := a as GameAction
			var raw := _produced_mana(ga.object_id, ga.ability_id, false)
			if raw == null or raw.choices.is_empty() == flexible:
				continue
			var produced := _produced_mana(ga.object_id, ga.ability_id, true)
			if produced == null:
				continue
			for k in ["w", "u", "b", "r", "g", "colorless"]:
				if int(need[k]) > 0 and int(produced.get(k)) > 0:
					return a
			if _payment.generic > 0 and produced.cmc() > 0 and best == null:
				best = a
		if best != null:
			return best
	return null


## What a mana ability makes. With `resolve` the "any color" choices are turned into real colors.
func _produced_mana(object_id: int, ability_id: StringName, resolve: bool = true) -> ManaCost:
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
			var raw := ManaCost.parse(str((fx as AbilityEffect).params.get("mana", "")))
			return resolve_mana(obj.controller_id, raw) if resolve else raw
	return null


## Picks the colors for "one mana of any color" style mana as it is produced (CR 106.5). Prefers a color
## the payment in progress still needs. "{CI}" means a color in the player's commander's color identity;
## with no such color nothing is produced.
func resolve_mana(player_id: int, produced: ManaCost) -> ManaCost:
	if produced == null or produced.choices.is_empty():
		return produced
	var out := produced.duplicate_cost()
	out.choices = []
	var pool: ManaPool = mana.pool(player_id)
	var identity := commander_identity(player_id)
	for opt in produced.choices:
		var allowed: Array = []
		for c in opt:
			if str(c) == "CI":
				allowed.append_array(identity)
			else:
				allowed.append(str(c))
		if allowed.is_empty():
			continue
		var pick := str(allowed[0])
		for c in allowed:
			var key := str(c).to_lower()
			var have: int = int(out.get(key))
			if pool != null:
				have += int(pool.get(key))
			if _payment != null and int(_payment.get(key)) > have:
				pick = str(c)
				break
		var pk := pick.to_lower()
		if pk in ["w", "u", "b", "r", "g"]:
			out.set(pk, int(out.get(pk)) + 1)
		else:
			out.colorless += 1
	return out


## Colors (W, U, B, R, G) in the color identity of the player's commander(s).
func commander_identity(player_id: int) -> Array:
	var found := {}
	if player_id >= 0 and player_id < state.players.size():
		for cid in state.players[player_id].commander_ids:
			var obj: GameObject = state.objects.get(cid)
			if obj != null and obj.definition is CardDefinition:
				for c in (obj.definition as CardDefinition).color_identity:
					found[str(c)] = true
	var out: Array = []
	for c in ["W", "U", "B", "R", "G"]:
		if found.has(c):
			out.append(c)
	return out


## One entry per mana the player could make right now: the pool plus every untapped source. Each entry
## lists the colors that mana can be ("C" is colorless).
func mana_slots(player_id: int) -> Array:
	var slots: Array = []
	var pool: ManaPool = mana.pool(player_id)
	if pool != null:
		for key in ["w", "u", "b", "r", "g", "colorless"]:
			for _i in int(pool.get(key)):
				slots.append([key.to_upper() if key != "colorless" else "C"])
	var by_object := {}
	for a in _legal_mana_abilities(player_id):
		var ga := a as GameAction
		var raw := _produced_mana(ga.object_id, ga.ability_id, false)
		if raw != null:
			if not by_object.has(ga.object_id):
				by_object[ga.object_id] = []
			(by_object[ga.object_id] as Array).append(raw)
	var identity := commander_identity(player_id)
	for oid in by_object.keys():
		var list: Array = by_object[oid]
		if list.size() > 1:
			## One land with several abilities (a dual-type land) taps for just one of them.
			var union: Array = []
			for raw in list:
				for slot in _slots_of(raw, identity):
					for c in slot:
						if not union.has(c):
							union.append(c)
			slots.append(union)
		else:
			slots.append_array(_slots_of(list[0], identity))
	return slots


func _slots_of(raw: ManaCost, identity: Array) -> Array:
	var out: Array = []
	for pair in [["W", raw.w], ["U", raw.u], ["B", raw.b], ["R", raw.r], ["G", raw.g], ["C", raw.colorless + raw.generic]]:
		for _i in int(pair[1]):
			out.append([pair[0]])
	for opt in raw.choices:
		var allowed: Array = []
		for c in opt:
			if str(c) == "CI":
				allowed.append_array(identity)
			else:
				allowed.append(str(c))
		if not allowed.is_empty():
			out.append(allowed)
	return out


## True if the player's pool and untapped mana sources can pay `cost`, colors included.
func can_afford(player_id: int, cost: ManaCost) -> bool:
	var slots := mana_slots(player_id)
	var pips: Array = []
	for pair in [["W", cost.w], ["U", cost.u], ["B", cost.b], ["R", cost.r], ["G", cost.g], ["C", cost.colorless]]:
		for _i in int(pair[1]):
			pips.append(pair[0])
	if pips.size() + cost.generic > slots.size():
		return false
	var used: Array = []
	used.resize(slots.size())
	used.fill(false)
	return _assign_pips(pips, 0, slots, used, cost.generic)


func _assign_pips(pips: Array, i: int, slots: Array, used: Array, generic: int) -> bool:
	if i >= pips.size():
		var free := 0
		for u in used:
			if not u:
				free += 1
		return free >= generic
	var seen := {}
	for j in slots.size():
		if used[j] or not (slots[j] as Array).has(pips[i]):
			continue
		var key := ",".join(PackedStringArray(slots[j]))
		if seen.has(key):
			continue
		seen[key] = true
		used[j] = true
		var ok := _assign_pips(pips, i + 1, slots, used, generic)
		used[j] = false
		if ok:
			return true
	return false


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
		if has_keyword(obj, "Defender"):
			continue
		if layers != null and layers.combat_restricted(state, obj):
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
	return has_keyword(obj, "Haste")


## Current keywords (after continuous effects) when layers exist, printed keywords otherwise.
func has_keyword(obj: GameObject, keyword: String) -> bool:
	if obj == null:
		return false
	if layers != null:
		return layers.has_keyword(state, obj, keyword)
	if obj.definition is CardDefinition:
		var want := keyword.to_lower()
		for kw in (obj.definition as CardDefinition).keywords:
			if str(kw).to_lower() == want:
				return true
	return false


func is_creature_now(obj: GameObject) -> bool:
	return _is_creature_now(obj)


func toughness_of(obj: GameObject) -> int:
	return _toughness_of(obj)


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
	if ab.restrictions.has("SORCERY_SPEED"):
		if actor != state.active_player_id or not _is_main_phase() or not _stack_empty():
			return "NOT_SORCERY_SPEED"
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
	if ab.has_sacrifice_cost():
		state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
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
