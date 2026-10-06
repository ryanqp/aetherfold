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
## Keyword rules that change casting and activation (kicker, flashback, cycling, ward ...).
var kw: KeywordRules
## The card database the game was built from (meld, "create a token that's a copy of <named card>").
var cards: CardDatabase = null
var _cast_extra: Dictionary = {}
var _cast_life_paid: int = 0
var _cast_plan: Dictionary = {}
var _cast_cover: Dictionary = {}
var _cast_source: int = 0
## Seats whose player answers choices on screen (targets of effects, discards, hideaway ...). Others are automatic.
var interactive_seats: Array = []
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
## The spell or ability whose cost is being checked or paid: spend-restricted mana ("only to cast a Dinosaur spell")
## is usable only toward it. `_afford_ctx` covers the "could I pay for it?" questions asked before casting.
var _afford_ctx: GameObject = null
var _afford_is_ability: bool = false
var _act_x: int = 0
## Mana sources tapped while paying for the spell or ability in progress (Path of Ancestry's scry).
var _paid_by: Array = []


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
	kw = KeywordRules.new(self)
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
	costs.bind(state)
	turn = TurnManager.new()
	turn.bind(self)
	priority = PriorityManager.new()
	executor = AbilityExecutor.new()
	targeting = TargetingManager.new()
	triggers = TriggerManager.new()
	sba = SbaManager.new()
	layers = LayerManager.new()
	kw = KeywordRules.new(self)
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
		cards = demo.db
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
		## A land exiled with "you may play it this turn" can be played from exile too.
		var xz: Zone = state.zones.get_zone(EngineEnums.ZoneId.EXILE, player_id)
		if xz != null:
			for xid in xz.object_ids:
				var xo: GameObject = state.objects.get(xid)
				if xo != null and can_play_from_exile(player_id, xo) and _is_land(xo):
					var xa := GameAction.new()
					xa.kind = GameAction.Kind.PLAY_LAND
					xa.player_id = player_id
					xa.object_id = int(xid)
					out.append(xa)
	for zone_id in [EngineEnums.ZoneId.HAND, EngineEnums.ZoneId.COMMAND, EngineEnums.ZoneId.EXILE]:
		var z: Zone = state.zones.get_zone(zone_id, player_id)
		if z == null:
			continue
		for oid in z.object_ids:
			var obj: GameObject = state.objects.get(oid)
			if obj == null or _is_land(obj) or _cast_forbidden(obj):
				continue
			if obj.zone == EngineEnums.ZoneId.EXILE and not can_play_from_exile(player_id, obj):
				## Foretold, plotted, warped and airbent cards are cast from exile in their own mode.
				if obj.exile_cast != "" and obj.owner_id == player_id:
					for xo in kw.cast_options(player_id, obj):
						var xm := str((xo.extra as Dictionary).get("mode", ""))
						if kw.timing_ok(player_id, obj, xm):
							var xc := GameAction.new()
							xc.kind = GameAction.Kind.CAST_SPELL
							xc.player_id = player_id
							xc.object_id = obj.object_id
							xc.extra = (xo.extra as Dictionary).duplicate()
							out.append(xc)
				continue
			var any_timing := kw.timing_ok(player_id, obj, "")
			if not any_timing:
				## Offering and sneak have their own timing.
				for so in kw.cast_options(player_id, obj):
					var sm := str((so.extra as Dictionary).get("mode", ""))
					if sm != "" and kw.timing_ok(player_id, obj, sm):
						var sc := GameAction.new()
						sc.kind = GameAction.Kind.CAST_SPELL
						sc.player_id = player_id
						sc.object_id = obj.object_id
						sc.extra = (so.extra as Dictionary).duplicate()
						out.append(sc)
				continue
			var c := GameAction.new()
			c.kind = GameAction.Kind.CAST_SPELL
			c.player_id = player_id
			c.object_id = obj.object_id
			out.append(c)
	## Flashback, escape and retrace: casting from the graveyard.
	for goid in state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, player_id).object_ids:
		var gobj: GameObject = state.objects.get(goid)
		if gobj == null or _is_land(gobj) or not kw.timing_ok(player_id, gobj, ""):
			continue
		for opt in kw.cast_options(player_id, gobj):
			var gc := GameAction.new()
			gc.kind = GameAction.Kind.CAST_SPELL
			gc.player_id = player_id
			gc.object_id = gobj.object_id
			gc.extra = (opt.extra as Dictionary).duplicate()
			out.append(gc)
	out.append_array(_legal_mana_abilities(player_id))
	out.append_array(_legal_activated(player_id))
	out.append_array(kw.special_actions(player_id))
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
		GameAction.Kind.SPECIAL:
			r = kw.submit_special(action)
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


## The most cards a player keeps at the end of their turn: 7, or no limit with "You have no maximum hand size" on a permanent they control.
func max_hand_size(player_id: int) -> int:
	var base := state.rules.max_hand_size if state.rules != null else 7
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return base
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o == null or o.controller_id != player_id or not (o.definition is CardDefinition) or o.face_down or o.phased_out:
			continue
		if (o.definition as CardDefinition).oracle_text.to_lower().contains("you have no maximum hand size"):
			return 1000000
	return base


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
		state.log.append(EngineEnums.EventType.DRAW, player_id, {to_id = moved.object_id, nth = state.players[player_id].draws_this_turn + 1})
		kw.on_drawn(player_id, moved)
	return moved


## The draw step card (CR 504.1), taken when a manual-draw seat clicks its library.
func take_turn_draw(player_id: int) -> GameObject:
	if state == null or not state.draw_pending or state.active_player_id != player_id:
		return null
	state.draw_pending = false
	## Dredge (CR 702.52a) may replace the draw: the question is asked by a draw effect put on the stack and resolved
	## now. The card comes back as null while the game waits for the answer.
	if interactive_seats.has(player_id) and kw != null and not kw.dredge_cards(player_id).is_empty():
		var fx := AbilityEffect.new()
		fx.kind = &"DRAW"
		fx.params = {"n": 1, "who": "CONTROLLER"}
		put_synthetic(null, player_id, [fx], {})
		finish_top_resolution()
		if state.mode == EngineEnums.EngineMode.AWAITING_DECISION:
			return null
		var hand: Zone = state.zones.get_zone(EngineEnums.ZoneId.HAND, player_id)
		return state.objects.get(int(hand.object_ids.back())) if hand != null and not hand.is_empty() else null
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


## Undaunted (CR 702.125): this spell costs {1} less for each opponent.
func _undaunted(player_id: int, spell: GameObject) -> int:
	if not has_keyword(spell, "Undaunted"):
		return 0
	var n := 0
	for p in state.players:
		if p.player_id != player_id and not p.lost:
			n += 1
	return n


## Last known power and toughness, recorded as a permanent leaves the battlefield.
## "Dinosaur spells you cast cost {1} less to cast": how much generic mana the player's permanents
## take off the cost of this spell (CR 601.2f).
func cost_reduction(player_id: int, spell: GameObject) -> int:
	if spell == null:
		return 0
	var total := _own_discount(player_id, spell) + _affinity(player_id, spell) + _undaunted(player_id, spell)
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 0
	var sources: Array = bf.object_ids.duplicate()
	## Eminence (CR 207.2c): some commanders' statics also work from the command zone.
	var cz: Zone = state.zones.get_zone(EngineEnums.ZoneId.COMMAND, player_id)
	if cz != null:
		sources.append_array(cz.object_ids)
	for oid in sources:
		var src: GameObject = state.objects.get(oid)
		if src == null or src.controller_id != player_id or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("cost_reduction"):
				continue
			if src.zone == EngineEnums.ZoneId.COMMAND and not bool(ab.static_spec.get("command_zone", false)):
				continue
			var spec: Dictionary = ab.static_spec["cost_reduction"]
			var f: Variant = spec.get("filter", {})
			if f is Dictionary and Query._matches(spell, src, f):
				## "... cost {1} less for each +1/+1 counter on ~" (Herald of War).
				var per_counter := str(spec.get("per_counter", ""))
				total += int(spec.get("amount", 1)) * (int(src.counters.get(per_counter, 0)) if per_counter != "" else 1)
	return total


## Affinity for artifacts / creatures / lands ... (CR 702.41): costs {1} less for each such permanent you control.
func _affinity(player_id: int, spell: GameObject) -> int:
	if not (spell.definition is CardDefinition):
		return 0
	var m := RegEx.create_from_string("(?im)^affinity for ([a-z ]+?)s?$").search((spell.definition as CardDefinition).oracle_text)
	if m == null:
		return 0
	var kind := m.get_string(1).strip_edges()
	var n := 0
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 0
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o != null and o.controller_id == player_id and o.definition is CardDefinition and (o.definition as CardDefinition).type_line.to_lower().contains(kind.to_lower()):
			n += 1
	return n


## "This spell costs {2} less to cast if it targets a Dinosaur you control." While you are casting it the
## chosen targets decide; before that (is it castable?) it counts when some legal target would qualify.
func _own_discount(player_id: int, spell: GameObject) -> int:
	if not (spell.definition is CardDefinition):
		return 0
	var total := 0
	for a0 in (spell.definition as CardDefinition).abilities:
		## "~ costs {3} less to cast if you've gained 3 or more life this turn" / "... for each creature you control".
		var ab0 := a0 as Ability
		if ab0 != null and ab0.kind == &"STATIC" and ab0.static_spec.has("cost_reduction_self"):
			var cs: Dictionary = ab0.static_spec["cost_reduction_self"]
			## Ghalta, Primal Hunger: "costs {X} less to cast, where X is the total power of creatures you control."
			if bool(cs.get("total_power", false)):
				var bf_tp: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
				if bf_tp != null:
					for tp_id in bf_tp.object_ids:
						var tp_o: GameObject = state.objects.get(tp_id)
						if tp_o != null and tp_o.controller_id == player_id and _is_creature_now(tp_o):
							total += maxi(0, power_of(tp_o))
				continue
			if cs.has("per"):
				total += int(cs.get("amount", 1)) * Query.count_objects(state, spell, cs["per"])
			elif layers.condition_met(state, spell, cs.get("condition", {})):
				total += int(cs.get("amount", 1))
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
	var cost := ManaCost.for_card(def.mana_cost if def else "", int(def.cmc) if def else 0)
	cost.generic += extra_generic
	cost.generic = maxi(0, cost.generic - cost_reduction(player_id, spell))
	return cost


func _lki(obj: GameObject) -> Dictionary:
	return {power = power_of(obj), toughness = toughness_of(obj), counters = obj.counters.duplicate()}


func resolve_top() -> void:
	finish_top_resolution()


func finish_top_resolution() -> void:
	if not (state.stack is MagicStack) or (state.stack as MagicStack).is_empty():
		return
	var done: bool = (state.stack as MagicStack).resolve_top(self)
	if not done:
		return
	if state.end_turn_requested:
		state.end_turn_requested = false
		process_zone_events()
		turn.end_the_turn()
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
	if triggers != null:
		triggers.check_state(self)
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
					_recover_triggers(p)
			if triggers != null:
				triggers.on_event(self, e)


## Recover (CR 702.59): when a creature is put into its owner's graveyard from the battlefield, each card with recover
## in that graveyard triggers; its owner pays the cost to return it to hand or it is exiled (KeywordActions RECOVER).
func _recover_triggers(p: Dictionary) -> void:
	if int(p.get("to_zone", -1)) != EngineEnums.ZoneId.GRAVEYARD:
		return
	var dead: GameObject = state.objects.get(int(p.get("to_id", 0)))
	if dead == null or dead.is_token or not (dead.definition is CardDefinition) or not (dead.definition as CardDefinition).is_creature():
		return
	var gy: Zone = state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, dead.owner_id)
	if gy == null:
		return
	for gid in gy.object_ids.duplicate():
		var g: GameObject = state.objects.get(int(gid))
		if g == null or not (g.definition is CardDefinition):
			continue
		var rc := str((g.definition as CardDefinition).kw().get("recover", ""))
		if rc == "":
			continue
		var fx := AbilityEffect.new()
		fx.kind = &"RECOVER"
		fx.params = {"cost": rc}
		put_synthetic(g, dead.owner_id, [fx], {})


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
	var exile_land := obj != null and obj.zone == EngineEnums.ZoneId.EXILE and can_play_from_exile(action.player_id, obj)
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
	note_land_played(action.player_id)
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
	if not _mana_restriction_ok(obj, ab):
		r.error = "restricted mana"
		return r
	costs.pay(obj, ab)
	if _cast_source != 0 and (_payment != null or _act_paying):
		_paid_by.append(obj.object_id)
	var sacrificed := ab.has_sacrifice_cost()
	for fx in ab.effects:
		if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA":
			var mana_text := str((fx as AbilityEffect).params.get("mana", ""))
			## "Add X mana ..., where X is the number of soul counters on ~" (Seance Board).
			var per_counter := str((fx as AbilityEffect).params.get("per_counter", ""))
			if per_counter != "":
				mana_text = mana_text.repeat(int(obj.counters.get(per_counter, 0)))
			if mana_text == "":
				continue
			var produced := resolve_mana(action.player_id, ManaCost.parse(mana_text))
			mana.add(action.player_id, produced)
			## "Whenever you tap a land for mana, add one mana of any type that land produced" (Mirari's Wake-style doublers).
			if obj.definition is CardDefinition and (obj.definition as CardDefinition).is_land() and _has_land_mana_doubler(action.player_id):
				for sym in ["W", "U", "B", "R", "G", "C"]:
					var have := produced.colorless if sym == "C" else int(produced.get(sym.to_lower()))
					if have > 0:
						mana.add(action.player_id, ManaCost.parse("{%s}" % sym))
						break
			## Forsaken Monument: "Whenever you tap a permanent for {C}, add an additional {C}."
			if produced.colorless > 0:
				for _x in _extra_colorless_for(action.player_id):
					mana.add(action.player_id, ManaCost.parse("{C}"))
		elif fx is AbilityEffect and (fx as AbilityEffect).kind == &"DEAL_DAMAGE":
			## Pain lands: "~ deals 1 damage to you" happens as the mana is made.
			var hurt := int((fx as AbilityEffect).params.get("n", 0))
			state.players[action.player_id].life -= hurt
			state.log.append(EngineEnums.EventType.DAMAGE, action.player_id, {to_player = action.player_id, amount = hurt, object_id = obj.object_id})
			if sba != null:
				sba.check(self)
	_monarch_land_bonus(action.player_id, obj)
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
	if _cast_forbidden(obj):
		r.error = "can't cast it now"
		return r
	var cast_mode := str(action.extra.get("mode", ""))
	var from_exile := obj.zone == EngineEnums.ZoneId.EXILE and (can_play_from_exile(action.player_id, obj) or (cast_mode in KeywordRules.EXILE_MODES and obj.owner_id == action.player_id))
	var from_graveyard := obj.zone == EngineEnums.ZoneId.GRAVEYARD and cast_mode in KeywordRules.GRAVEYARD_MODES
	if obj.zone != EngineEnums.ZoneId.HAND and obj.zone != EngineEnums.ZoneId.COMMAND and not from_exile and not from_graveyard:
		r.error = "not in hand or command"
		return r
	if from_exile and obj.controller_id != action.player_id and not can_play_from_exile(action.player_id, obj):
		r.error = "illegal spell"
		return r
	if _is_land(obj):
		r.error = "use PLAY_LAND"
		return r
	if not kw.timing_ok(action.player_id, obj, cast_mode):
		r.error = "illegal timing"
		return r
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	_cast_extra = action.extra.duplicate()
	_cast_plan = kw.plan(action.player_id, obj, _cast_extra)
	if not bool(_cast_plan.ok):
		r.error = str(_cast_plan.error)
		return r
	_cast_cover = {}
	_cast_source = obj.object_id
	_cast_from_command = obj.zone == EngineEnums.ZoneId.COMMAND
	_cast_targets = []
	_cast_queries = []
	## Overload (CR 702.96) and cleave (CR 702.148) change the spell's text: read the changed text now so its
	## targets (none, for overload) are the ones chosen.
	var variant := KeywordRules.variant_def(def, str(_cast_plan.get("mode", cast_mode)))
	if variant != null:
		_cast_plan["variant_def"] = variant
		def = variant
	var sp: Ability = def.spell_ability() if def != null else null
	if sp != null and not sp.targets.is_empty() and str(_cast_plan.get("mode", cast_mode)) != "overload":
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
	## Phyrexian life paid up front comes back when the cast is called off (CR 601.2h is undone with the cast).
	if _cast_life_paid > 0:
		state.players[action.player_id].life += _cast_life_paid
	_cast_life_paid = 0
	_cast_source = 0
	_payment = null
	_act_x = 0
	_paid_by = []
	_cast_from_command = false
	_cast_queries = []
	_cast_targets = []
	_cast_plan = {}
	_cast_cover = {}
	_cast_extra = {}
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
	var paid_by := _paid_by.duplicate()
	_paid_by = []
	kw.pay_extras(player_id, _cast_plan, _cast_cover)
	var moved: GameObject = state.zones.move(obj.object_id, EngineEnums.ZoneId.STACK)
	if moved == null:
		r.error = "stack move failed"
		return r
	kw.mark_cast(moved, _cast_plan)
	var entry: StackEntry = (state.stack as MagicStack).push_spell(
		moved, player_id, _cast_targets, state.next_stack_id, source_id
	)
	state.next_stack_id += 1
	entry.ctx = {"kicked": moved.kicked, "mode": moved.cast_mode}
	_spell_extras(entry, moved, _cast_plan)
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
	_cast_plan = {}
	_cast_cover = {}
	_cast_extra = {}
	state.passed_since_action.clear()
	_consume_flash_grant(player_id, moved)
	_spend_riders(player_id, moved, paid_by)
	if triggers != null:
		triggers.on_spell_cast(self, moved, player_id)
	kw.check_ward(entry)
	if sba != null and sba.check(self):
		r.ok = true
		return r
	state.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	state.priority_player_id = player_id
	state.awaiting = {player_id = player_id, type = &"priority"}
	r.ok = true
	return r


## What a cast choice adds to the spell on the stack: escalate's number of modes, a promised gift on an instant or
## sorcery ("they draw a card before its other effects", CR 702.174b).
func _spell_extras(entry: StackEntry, spell: GameObject, plan: Dictionary) -> void:
	if int(plan.get("escalate", 0)) > 0:
		entry.ctx["modes_n"] = 1 + int(plan["escalate"])
	## Overload (CR 702.96): no targets; the effects happen for each object the target could have been.
	if spell.cast_mode == "overload" and def0_spell(spell) != null and not def0_spell(spell).targets.is_empty():
		entry.ctx["overload"] = true
		entry.ctx["ov_spec"] = def0_spell(spell).targets[0]
		entry.targets = []
	## Entwine (CR 702.42): every mode.
	if bool(spell.marks.get("entwined", false)):
		entry.ctx["modes_n"] = 99
	## Spree / tiered (CR 702.172, 702.183): the modes were chosen and paid for as the spell was cast.
	if plan.has("modes"):
		entry.ctx["modes_fixed"] = (plan["modes"] as Array).duplicate()
	## X chosen as it was cast (CR 107.3a).
	if spell.x_paid > 0:
		entry.ctx["x"] = spell.x_paid
	var pool: ManaPool = mana.pool(entry.controller_id)
	if pool != null:
		spell.mana_spent = pool.spent_total
		spell.colors_spent = pool.spent_colors.keys()
	var def: CardDefinition = spell.definition as CardDefinition if spell.definition is CardDefinition else null
	## Fuse (CR 702.102): the other half's effects follow this half's.
	if spell.cast_mode == "fuse" and def != null and def.other_half != null:
		var osp: Ability = def.other_half.spell_ability()
		if osp != null:
			entry.effects.append_array(_untargeted(osp.effects, entry))
	## Splice onto Arcane (CR 702.47b): the spliced cards' effects are added after the spell's own.
	for sid in spell.marks.get("splice", []):
		var sc: GameObject = state.objects.get(int(sid))
		var sd: CardDefinition = sc.definition as CardDefinition if sc != null and sc.definition is CardDefinition else null
		var ssp: Ability = sd.spell_ability() if sd != null else null
		if ssp != null:
			entry.effects.append_array(_untargeted(ssp.effects, entry))
	if spell.gift_promised:
		entry.ctx["gift"] = true
		if def != null and (def.is_instant() or def.is_sorcery()):
			var g := AbilityEffect.new()
			g.kind = &"GIFT"
			g.params = {"kind": str(def.kw().get("gift", "card"))}
			entry.effects.push_front(g)
	## Awaken (CR 702.113a): the spell also has "put N +1/+1 counters on a land you control; it becomes a creature".
	if bool(spell.marks.get("awakening", false)) and def != null and def.kw().has("awaken"):
		var afx := AbilityEffect.new()
		afx.kind = &"AWAKEN"
		afx.params = {"n": int(def.kw().awaken.n)}
		entry.effects.append(afx)
	## Copies made as it is cast: replicate (CR 702.56), conspire (CR 702.78), casualty (CR 702.153).
	var copies := int(spell.marks.get("replicate", 0))
	if bool(spell.marks.get("conspired", false)):
		copies += 1
	if bool(spell.marks.get("casualty", false)):
		copies += 1
	if def != null and (def.is_instant() or def.is_sorcery()):
		for i in copies:
			PreconEffects.copy_spell(self, entry, entry.controller_id)
	elif copies > 0:
		spell.marks["copies_on_resolve"] = copies


func def0_spell(spell: GameObject) -> Ability:
	var d: CardDefinition = spell.definition as CardDefinition if spell != null and spell.definition is CardDefinition else null
	return d.spell_ability() if d != null else null


## Effects of a spliced/fused half that need no targets of their own (a targeted one is skipped: one target list).
func _untargeted(effects: Array, entry: StackEntry) -> Array:
	var out: Array = []
	for e in effects:
		var fx := e as AbilityEffect
		if fx == null:
			continue
		if JSON.stringify(fx.params).contains("TARGET") and entry.targets.is_empty():
			continue
		out.append(fx)
	return out


## Casts a card without paying its mana cost ("play the exiled card without paying its mana cost"): picks
## targets automatically, moves it to the stack and runs cast triggers. False if it has no legal target.
func cast_free(player_id: int, object_id: int, extra: Dictionary = {}) -> bool:
	return kw.cast_now(player_id, object_id, extra, true)


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


## The object a payment in progress (or a "can I afford it" question) is for, and whether it is an ability.
func _pay_ctx_object() -> GameObject:
	if _cast_source != 0 and (_payment != null or _act_paying):
		return state.objects.get(_cast_source)
	return _afford_ctx


func _pay_ctx_is_ability() -> bool:
	if _cast_source != 0 and (_payment != null or _act_paying):
		return _act_paying
	return _afford_is_ability


## Conditions printed on a mana ability: "Activate only if you control five or more lands" ({min_lands}) and
## "Spend this mana only to cast ..." ({spend_only}). Strings in `restrictions` are timing rules, checked elsewhere.
func _mana_restriction_ok(obj: GameObject, ab: Ability) -> bool:
	for r in ab.restrictions:
		if not (r is Dictionary):
			continue
		var d: Dictionary = r
		if d.has("min_lands") and Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER", "type": "land"}) < int(d.min_lands):
			return false
		if d.has("spend_only"):
			var spec: Dictionary = d.spend_only
			var target := _pay_ctx_object()
			if target == null:
				return false
			if _pay_ctx_is_ability() and not bool(spec.get("abilities", false)):
				return false
			var q: Dictionary = spec.get("query", {})
			if not Query._matches(target, obj, q):
				return false
	return true


func _legal_mana_abilities(player_id: int) -> Array:
	var out: Array = []
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	## While paying an ability whose cost includes {T}, that permanent can't also tap for the mana (Mosswort Bridge's
	## "{G}, {T}": it must not tap itself for its own {G}, or the {T} can no longer be paid).
	var own_tap_source := 0
	if _act_paying and _cast_source != 0:
		var pay_src: GameObject = state.objects.get(_cast_source)
		var pay_ab: Ability = _ability_on(pay_src, _act_ability_id) if pay_src != null else null
		if pay_ab != null and pay_ab.uses_tap_symbol_cost():
			own_tap_source = _cast_source
	for oid in bf.object_ids:
		var obj: GameObject = state.objects.get(oid)
		if obj == null or obj.controller_id != player_id:
			continue
		if own_tap_source != 0 and int(oid) == own_tap_source:
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
			if not _mana_restriction_ok(obj, ab):
				continue
			if not _mana_text_makes_mana(obj, ab):
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
	return can_play_land_now(player_id)


## Whether a land drop is still available this turn, ignoring timing.
func can_play_land_now(player_id: int) -> bool:
	if not bool(state.land_played.get(player_id, false)):
		return true
	## `land_played` is set once the normal drop is used; an extra-drop permanent can reopen it (CR 305.2a).
	var used := land_drops_used(player_id)
	return used > 0 and used < 1 + extra_land_drops(player_id)


## Land drops taken this turn (CR 305.2). Keyed by turn number so it resets by itself.
func land_drops_used(player_id: int) -> int:
	var rec: Dictionary = state.land_drops.get(player_id, {})
	return int(rec.get("n", 0)) if int(rec.get("turn", -1)) == state.turn_number else 0


## Records a land played as a land drop; `land_played` means "no drops left this turn".
func note_land_played(player_id: int) -> void:
	state.land_drops[player_id] = {"turn": state.turn_number, "n": land_drops_used(player_id) + 1}
	state.land_played[player_id] = land_drops_used(player_id) >= 1 + extra_land_drops(player_id)


## "You may play an additional land on each of your turns." (CR 305.2a), read from the permanents' Oracle text.
func extra_land_drops(player_id: int) -> int:
	var n := 0
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 0
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o == null or o.controller_id != player_id or not (o.definition is CardDefinition) or o.face_down or o.phased_out:
			continue
		var text := (o.definition as CardDefinition).oracle_text.to_lower()
		if text.contains("you may play an additional land on each of your turns"):
			n += 1
	var once: Dictionary = state.extra_land_once.get(player_id, {})
	if int(once.get("turn", -1)) == state.turn_number:
		n += int(once.get("n", 0))
	return n


## Path of Ancestry: "When that mana is spent to cast a creature spell that shares a creature type with your
## commander, scry 1." The mana ability carries {on_spend: {query, scry}} in its restrictions.
func _spend_riders(player_id: int, spell: GameObject, paid_by: Array) -> void:
	var done := {}
	for sid in paid_by:
		var src: GameObject = state.objects.get(int(sid))
		if src == null or done.has(src.object_id) or not (src.definition is CardDefinition):
			continue
		done[src.object_id] = true
		for a in (src.definition as CardDefinition).mana_abilities():
			for r in (a as Ability).restrictions:
				if not (r is Dictionary) or not (r as Dictionary).has("on_spend"):
					continue
				var rule: Dictionary = (r as Dictionary).on_spend
				var q: Dictionary = rule.get("query", {})
				if not Query._matches(spell, src, q):
					continue
				if bool(q.get("shares_type_with_commander", false)) and not shares_type_with_commander(player_id, spell):
					continue
				var fx := AbilityEffect.new()
				fx.kind = &"SCRY"
				fx.params = {"n": int(rule.get("scry", 1))}
				put_synthetic(src, player_id, [fx], {})


## Whether `spell` shares a creature type with one of the player's commanders (CR 205.3m).
func shares_type_with_commander(player_id: int, spell: GameObject) -> bool:
	if not (spell.definition is CardDefinition):
		return false
	var mine := Query._subtype_words((spell.definition as CardDefinition).type_line)
	for cid in state.players[player_id].commander_ids:
		var c: GameObject = state.objects.get(cid)
		if c == null or not (c.definition is CardDefinition):
			continue
		for t in Query._subtype_words((c.definition as CardDefinition).type_line):
			if mine.has(t):
				return true
	return false


## "The next spell of the chosen type you cast this turn can be cast as though it had flash" (Progenitor's Icon).
func _flash_granted(player_id: int, obj: GameObject) -> bool:
	## "You may cast green creature spells as though they had flash." (Yeva, Shimmer Myr)
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf != null:
		for oid in bf.object_ids:
			var src: GameObject = state.objects.get(oid)
			if src == null or src.controller_id != player_id or src.face_down or not (src.definition is CardDefinition):
				continue
			for a in (src.definition as CardDefinition).abilities:
				var ab := a as Ability
				if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("flash_for") and Query._matches(obj, src, ab.static_spec["flash_for"]):
					return true
	for g in state.flash_grants:
		if int(g.pid) == player_id and int(g.turn) == state.turn_number:
			if Query._matches(obj, null, {"type": "creature", "subtype": str(g.subtype)}):
				return true
	return false


func _consume_flash_grant(player_id: int, spell: GameObject) -> void:
	for i in state.flash_grants.size():
		var g: Dictionary = state.flash_grants[i]
		if int(g.pid) == player_id and int(g.turn) == state.turn_number and Query._matches(spell, null, {"type": "creature", "subtype": str(g.subtype)}):
			state.flash_grants.remove_at(i)
			return


func _timing_ok_to_cast(player_id: int, obj: GameObject) -> bool:
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	## CR 702.8: flash lets a permanent spell be cast any time you could cast an instant.
	if def != null and (def.is_instant() or _def_has_keyword(def, "flash")):
		return true
	if _flash_granted(player_id, obj):
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
	var spell_obj: GameObject = state.objects.get(_cast_source)
	if _cast_plan.is_empty() and spell_obj != null:
		_cast_plan = kw.plan(player_id, spell_obj, _cast_extra)
	var spent_pool: ManaPool = mana.pool(player_id)
	if spent_pool != null:
		spent_pool.reset_spent()
	_payment = (_cast_plan.cost as ManaCost).duplicate_cost() if _cast_plan.has("cost") else ManaCost.for_card(def.mana_cost if def else "", int(def.cmc) if def else 0)
	## Hybrid and Phyrexian symbols become plain pips now (CR 107.4e, 107.4f); Phyrexian life is paid up front.
	var life_to_pay := 0
	if not _payment.hybrid.is_empty():
		var chosen := resolve_hybrid(player_id, _payment)
		_payment = chosen.cost
		life_to_pay = int(chosen.life)
	## Convoke and delve cover what the mana sources can't (CR 702.51, 702.66).
	_cast_cover = {}
	if spell_obj != null and not _can_afford_plain(player_id, _payment):
		var cv: Dictionary = kw.cover(player_id, spell_obj, _payment)
		if bool(cv.ok):
			_cast_cover = cv
			_payment = cv.cost
	_cast_life_paid = life_to_pay
	if spell_obj != null:
		spell_obj.marks["phyrexian_life"] = life_to_pay
	if life_to_pay > 0:
		state.players[player_id].life -= life_to_pay
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
	## Banding (CR 702.22): attacking creatures with banding fight as one band; blocking one blocks them all.
	var band := _banding_group(cs)
	var band_blockers: Array = []
	for baid in band:
		for bbid in _blocker_ids(cs, int(baid)):
			if not band_blockers.has(int(bbid)):
				band_blockers.append(int(bbid))
	var band_blocked := not band_blockers.is_empty()
	for aid in cs.attacker_ids:
		if band_blocked and band.has(int(aid)):
			continue
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
	if band_blocked:
		_band_damage(cs, band, band_blockers, first_pass, split)


func _banding_group(cs: CombatState) -> Array:
	var group: Array = []
	for aid in cs.attacker_ids:
		var a: GameObject = state.objects.get(int(aid))
		if a != null and a.zone == EngineEnums.ZoneId.BATTLEFIELD and has_keyword(a, "Banding"):
			group.append(int(aid))
	return group if group.size() >= 2 else []


## A blocked band: each blocker's damage is assigned among the band by the attacking player, and when a blocker
## has banding the defending player assigns the attackers' damage among the blockers (CR 702.22). Both are
## assigned automatically: damage goes where it kills nothing if it can.
func _band_damage(cs: CombatState, band: Array, blocker_ids: Array, first_pass: bool, split: bool) -> void:
	var members: Array = []
	for aid in band:
		var a: GameObject = state.objects.get(int(aid))
		if a != null and a.zone == EngineEnums.ZoneId.BATTLEFIELD:
			members.append(a)
	var blockers: Array = []
	for bid in blocker_ids:
		var b: GameObject = state.objects.get(int(bid))
		if b != null and b.zone == EngineEnums.ZoneId.BATTLEFIELD:
			blockers.append(b)
	if members.is_empty() or blockers.is_empty():
		return
	for striker in blockers:
		if _deals_damage_now(striker, first_pass, split):
			var back := _power_of(striker)
			if back > 0:
				var spread := _spread_damage(back, members)
				for o in spread.keys():
					_combat_damage_to_object(striker, o, int(spread[o]))
	var blocker_banding := false
	for b2 in blockers:
		if has_keyword(b2, "Banding"):
			blocker_banding = true
	for member in members:
		if not _deals_damage_now(member, first_pass, split):
			continue
		var power := _power_of(member)
		if power <= 0:
			continue
		if blocker_banding:
			var spread2 := _spread_damage(power, blockers)
			for o2 in spread2.keys():
				_combat_damage_to_object(member, o2, int(spread2[o2]))
			continue
		var remaining := power
		for i in blockers.size():
			if remaining <= 0:
				break
			var amount := remaining if i == blockers.size() - 1 and not has_keyword(member, "Trample") else mini(remaining, _lethal_for(member, blockers[i]))
			if amount > 0:
				_combat_damage_to_object(member, blockers[i], amount)
				remaining -= amount


## Splits `amount` damage over `group` so that as little as possible is lethal. Returns {GameObject: damage}.
func _spread_damage(amount: int, group: Array) -> Dictionary:
	var order := group.duplicate()
	order.sort_custom(func(a, b) -> bool: return (_toughness_of(a) - a.damage_marked) > (_toughness_of(b) - b.damage_marked))
	var out := {}
	var left := amount
	for o in order:
		var cap := maxi(0, _toughness_of(o) - o.damage_marked - 1)
		var give := mini(left, cap)
		if give > 0:
			out[o] = give
			left -= give
	if left > 0 and not order.is_empty():
		var last: GameObject = order[order.size() - 1]
		out[last] = int(out.get(last, 0)) + left
	return out


## Damage that counts as lethal for assignment (CR 702.2c for deathtouch).
func _lethal_for(source: GameObject, target: GameObject) -> int:
	if has_keyword(source, "Deathtouch"):
		return 0 if target.deathtouch_damage else 1
	return maxi(0, _toughness_of(target) - target.damage_marked)


## Damage from a spell or ability, or a fight (CR 120.3). Deathtouch and lifelink still count.
func damage_object(source: GameObject, target: GameObject, amount: int) -> void:
	if amount <= 0 or target == null or target.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	## CR 702.16e: damage from a source with a color the target has protection from is prevented.
	if protected_from(target, source):
		return
	_mark_damage(source, target, amount)
	if source != null and has_keyword(source, "Deathtouch"):
		target.deathtouch_damage = true
	state.log.append(EngineEnums.EventType.DAMAGE, source.controller_id if source != null else 0, {
		to_object = target.object_id,
		amount = amount,
		object_id = source.object_id if source != null else 0,
	})
	if source != null:
		_apply_lifelink(source, amount)


## Damage to a creature: marked damage, or -1/-1 counters when the source has infect (CR 702.90b) or wither (CR 702.80a).
func _mark_damage(source: GameObject, target: GameObject, amount: int) -> void:
	amount = _prevent_all_but_one(target, amount)
	amount = apply_prevention(target, -1, amount)
	if amount <= 0:
		return
	## CR 120.3c: damage to a planeswalker removes that many loyalty counters from it.
	if is_planeswalker_now(target) and not _is_creature_now(target):
		target.counters["loyalty"] = maxi(0, int(target.counters.get("loyalty", 0)) - amount)
		return
	if source != null and (has_keyword(source, "Infect") or has_keyword(source, "Wither")):
		target.counters["-1/-1"] = int(target.counters.get("-1/-1", 0)) + amount
	else:
		target.damage_marked += amount


## Damage prevention shields (CR 615): what is left of `amount` after the shields that cover this target. Shields end with the turn.
func apply_prevention(target_obj: GameObject, target_player: int, amount: int) -> int:
	## "Damage can't be prevented." (Leyline of Punishment, Everlasting Torment): no shield applies.
	if amount > 0 and _battlefield_text_has("damage can't be prevented"):
		return amount
	## "Prevent all combat damage that would be dealt to ~" printed on the permanent (Seraph of the Sword).
	if amount > 0 and target_obj != null and state.step == EngineEnums.Step.COMBAT_DAMAGE and _prints_combat_prevention(target_obj):
		return 0
	if amount <= 0 or state.prevention.is_empty():
		return amount
	var combat := state.step == EngineEnums.Step.COMBAT_DAMAGE
	for sh in state.prevention:
		var d: Dictionary = sh
		if bool(d.get("combat_only", false)) and not combat:
			continue
		var covers := false
		match str(d.get("to", "ANY")):
			"ANY":
				covers = true
			"PLAYER":
				covers = target_obj == null and target_player == int(d.get("player_id", -2))
			"OBJECT":
				covers = target_obj != null and target_obj.object_id == int(d.get("object_id", -2))
			"YOUR_STUFF":
				covers = (target_obj == null and target_player == int(d.get("player_id", -2))) or (target_obj != null and target_obj.controller_id == int(d.get("player_id", -2)))
		if not covers:
			continue
		var n := int(d.get("n", -1))
		if n < 0:
			amount = 0
		else:
			var used := mini(n, amount)
			d["n"] = n - used
			amount -= used
		if amount <= 0:
			break
	var left: Array = []
	for sh2 in state.prevention:
		if int((sh2 as Dictionary).get("n", -1)) != 0:
			left.append(sh2)
	state.prevention = left
	return maxi(0, amount)


## Temple Altisaur (CR 615): "If a source would deal damage to another Dinosaur you control, prevent all but 1 of that damage."
func _prevent_all_but_one(target: GameObject, amount: int) -> int:
	if amount <= 1 or target == null or not (target.definition is CardDefinition) or target.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return amount
	if not (target.definition as CardDefinition).type_line.contains("Dinosaur"):
		return amount
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o != null and o.object_id != target.object_id and o.controller_id == target.controller_id and o.definition is CardDefinition \
				and (o.definition as CardDefinition).oracle_text.to_lower().contains("prevent all but 1 of that damage"):
			return 1
	return amount


## Destroys a permanent (CR 701.8) unless indestructible, a regeneration shield (CR 701.19) or umbra armor (CR 702.89)
## replaces it. Returns true if it left the battlefield.
func destroy_permanent(obj: GameObject) -> bool:
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return false
	if has_keyword(obj, "Indestructible"):
		return false
	## Umbra armor: an Aura with it on this permanent is destroyed instead and the damage is removed.
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var a: GameObject = state.objects.get(oid)
		if a != null and a.attached_to == obj.object_id and a.definition is CardDefinition and not layers.loses_abilities(state, a):
			var akw := (a.definition as CardDefinition).kw()
			if akw.has("umbra_armor") or akw.has("totem_armor"):
				obj.damage_marked = 0
				obj.deathtouch_damage = false
				state.zones.move(a.object_id, EngineEnums.ZoneId.GRAVEYARD, a.owner_id)
				return false
	if obj.regen_shields > 0:
		obj.regen_shields -= 1
		obj.tapped = true
		obj.damage_marked = 0
		obj.deathtouch_damage = false
		if state.combat is CombatState:
			var cs := state.combat as CombatState
			cs.attacker_ids.erase(obj.object_id)
			for k in cs.blockers.keys():
				(cs.blockers[k] as Array).erase(obj.object_id)
		return false
	return state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id) != null


## Words for the table about a permanent's status (monstrous, saddled, exerted ...); filled in as keywords add them.
func designations(obj: GameObject) -> Array:
	var out: Array = []
	if obj == null:
		return out
	if obj.gift_promised:
		out.append("gift promised")
	if obj.cast_mode == "impending" and int(obj.counters.get("time", 0)) > 0:
		out.append("impending")
	if obj.sacrifice_at_end:
		out.append("sacrificed at end")
	if obj.unearthed:
		out.append("unearthed")
	if obj.bestowed:
		out.append("bestowed")
	if not obj.merged.is_empty():
		out.append("mutated Ã%d" % (obj.merged.size() + 1))
	if obj.regen_shields > 0:
		out.append("regenerate Ã%d" % obj.regen_shields)
	if int(obj.marks.get("saddled_turn", -1)) == state.turn_number:
		out.append("saddled")
	if obj.attacked_turn == state.turn_number and int(obj.marks.get("boast_turn", -1)) != state.turn_number:
		for a in _active_abilities(obj):
			if a is Ability and (a as Ability).restrictions.has("BOAST"):
				out.append("can boast")
				break
	for d in obj.marks.keys():
		## Only yes/no marks are shown; per-turn bookkeeping and per-ability flags stay hidden.
		if obj.marks[d] is bool and obj.marks[d] and not str(d).begins_with("exhausted_") and str(d) != "stolen_by_aura":
			out.append(str(d))
	return out


func is_planeswalker_now(obj: GameObject) -> bool:
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return false
	if layers != null:
		return str(layers.snapshot(state, obj, "type").get("type_line", "")).contains("Planeswalker")
	return obj.definition is CardDefinition and (obj.definition as CardDefinition).type_line.contains("Planeswalker")


## Colors `obj` has protection from (CR 702.16): its own keyword lines ("protection from white and from blue")
## and granted keywords ("Protection from red"). Letters W U B R G.
func protection_colors(obj: GameObject) -> Array:
	var out: Array = []
	if obj == null or not (obj.definition is CardDefinition) or obj.face_down:
		return out
	var lose := layers != null and layers.loses_abilities(state, obj)
	if not lose:
		for raw in (obj.definition as CardDefinition).oracle_text.split("\n"):
			var low := str(raw).to_lower().strip_edges()
			var i := low.find("protection from ")
			if i < 0 or (i > 0 and not low.substr(0, i).strip_edges().ends_with(",")):
				continue
			for c in KeywordDb.protection_colors(low.substr(i).split("(")[0].strip_edges()):
				if not out.has(c):
					out.append(c)
	if layers != null:
		for kw in layers.snapshot(state, obj).get("keywords", PackedStringArray()):
			for c2 in KeywordDb.protection_colors(str(kw)):
				if not out.has(c2):
					out.append(c2)
	return out


## True when `obj` has protection from one of `source`'s colors.
func protected_from(obj: GameObject, source: GameObject) -> bool:
	if obj == null or source == null or not (source.definition is CardDefinition):
		return false
	## "Protection from artifacts" / "creatures" / "enchantments" (a card type, CR 702.16): damage, enchanting, blocking and targeting.
	for t in protection_types(obj):
		if (source.definition as CardDefinition).type_line.to_lower().split("—")[0].contains(str(t)):
			return true
	var prot := protection_colors(obj)
	if prot.is_empty():
		return false
	for c in (source.definition as CardDefinition).colors:
		if prot.has(str(c)):
			return true
	return false


## "~ can't be countered" on the spell itself, or "Creature spells you control can't be countered" (Rhythm of the Wild).
func cant_be_countered(spell: GameObject) -> bool:
	if spell == null or not (spell.definition is CardDefinition):
		return false
	var def := spell.definition as CardDefinition
	for line in def.oracle_text.to_lower().split("\n"):
		var l := str(line).strip_edges()
		if l.begins_with("this spell can't be countered") or l.begins_with("%s can't be countered" % def.name.to_lower()) or l == "~ can't be countered.":
			return true
	if def.is_creature():
		var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		for oid in bf.object_ids:
			var o: GameObject = state.objects.get(oid)
			if o != null and o.controller_id == spell.controller_id and o.definition is CardDefinition \
					and (o.definition as CardDefinition).oracle_text.to_lower().contains("creature spells you control can't be countered"):
				return true
	return false


## The N of a keyword line such as "Toxic 2" or "Afterlife 3" on the card, 0 if it has none.
func keyword_n(obj: GameObject, keyword: String) -> int:
	if obj == null or not (obj.definition is CardDefinition):
		return 0
	var m := RegEx.create_from_string("(?im)^" + keyword + " (\\d+)").search((obj.definition as CardDefinition).oracle_text)
	return int(m.get_string(1)) if m != null else 0


func _combat_damage_to_object(source: GameObject, target: GameObject, amount: int) -> void:
	if protected_from(target, source):
		return
	_mark_damage(source, target, amount)
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
	amount = apply_prevention(null, player_id, amount)
	## Infect (CR 702.90b): damage to a player is poison counters instead of life loss. Toxic N (CR 702.164)
	## adds N poison counters on top of normal damage.
	if has_keyword(source, "Infect"):
		state.players[player_id].poison += amount
	else:
		state.players[player_id].life -= amount
	if amount > 0:
		state.players[player_id].poison += keyword_n(source, "toxic")
		kw.note_player_damaged(player_id, source, true)
	state.log.append(EngineEnums.EventType.DAMAGE, state.active_player_id, {
		to_player = player_id,
		amount = amount,
		object_id = source.object_id,
		combat = true,
	})
	if triggers != null:
		triggers.on_combat_damage_to_player(self, source, player_id, amount)
	## CR 903.10a: combat damage from a commander (infect included) is tallied per commander; 21 from one
	## commander loses the game (SbaManager._check_commander_damage).
	if source.is_commander and amount > 0:
		var key := str(source.owner_id) + ":" + str((source.definition as CardDefinition).name if source.definition is CardDefinition else source.object_id)
		var prev := int(state.players[player_id].commander_damage_from.get(key, 0))
		state.players[player_id].commander_damage_from[key] = prev + amount
	_apply_lifelink(source, amount)


## Lifelink (CR 702.15b): the source's controller gains that much life.
func _apply_lifelink(source: GameObject, amount: int) -> void:
	if amount <= 0 or not has_keyword(source, "Lifelink"):
		return
	var pid := source.controller_id
	if pid < 0 or pid >= state.players.size() or executor.life_gain_blocked(self, pid):
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
	var legal := _legal_attacker_ids(action.player_id)
	var ids: Array = kw.with_goaded(action.player_id, action.extra.get("attackers", []), legal)
	for raw in ids:
		if not legal.has(int(raw)):
			r.error = "illegal attacker"
			return r
	## "~ attacks each combat if able" (Darksteel Juggernaut, Graaz): the creature is added to the attackers.
	for lid in legal:
		if not ids.has(int(lid)) and _must_attack(state.objects.get(int(lid))):
			ids.append(int(lid))
	## "~ can't attack or block alone" (CR 508.1c): it needs another attacker.
	if ids.size() == 1 and _printed_alone_rule(state.objects.get(int(ids[0])), true):
		r.error = "can't attack alone"
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
	ids = _pay_attack_tax(action.player_id, ids, requested_defender, assigned, use_map)
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
		if obj != null and obj.controller_id >= 0 and obj.controller_id < state.players.size():
			state.players[obj.controller_id].attacked_this_turn = true
		if obj != null:
			obj.attacked_turn = state.turn_number
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
	var block_paid := 0
	var used := {}
	for existing in next_blocks.values():
		if existing is Array:
			for bid in existing:
				used[int(bid)] = int(used.get(int(bid), 0)) + 1
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
			## "~ can block an additional creature each combat" / "any number of creatures": a blocker may be used more than once.
			if int(used.get(bid, 0)) >= 1 + _extra_blocks(state.objects.get(bid)):
				r.error = "blocker already assigned"
				return r
			if not _can_block(bid, action.player_id, attacker_id):
				r.error = "illegal blocker"
				return r
			used[bid] = int(used.get(bid, 0)) + 1
			ordered.append(bid)
		## "Creatures can't block unless their controller pays {1} for each of those creatures" (Archangel of Tithes while attacking).
		var btax := _block_tax_for(attacker_id)
		if btax > 0:
			var kept_b: Array = []
			for bid2 in ordered:
				if can_afford(action.player_id, ManaCost.parse("{%d}" % (block_paid + btax))):
					block_paid += btax
					kept_b.append(bid2)
				else:
					used.erase(int(bid2))
			ordered = kept_b
			if ordered.is_empty():
				next_blocks.erase(attacker_id)
				continue
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
		if group is Array and (group as Array).size() > 1 and single_blocker_only(state.objects.get(int(key))):
			r.error = "can't be blocked by more than one creature"
			return r
	## "~ can't attack or block alone": a lone blocker must not be it.
	var blocking_total := 0
	var lone_blocker := 0
	var blocking_ids := {}
	for bkey in next_blocks.keys():
		var bgroup: Variant = next_blocks[bkey]
		if bgroup is Array:
			for bb in (bgroup as Array):
				blocking_total += 1
				lone_blocker = int(bb)
				blocking_ids[int(bb)] = true
	if blocking_total == 1 and _printed_alone_rule(state.objects.get(lone_blocker), false):
		r.error = "can't block alone"
		return r
	## "~ must be blocked if able": some free creature of the defender has to block it.
	for must_id in cs.attacker_ids:
		var must_obj: GameObject = state.objects.get(int(must_id))
		if must_obj == null or not _printed_line(must_obj, "must be blocked if able") or (next_blocks.get(int(must_id), []) as Array).size() > 0:
			continue
		for free_id in _creature_ids_of(action.player_id):
			if not blocking_ids.has(int(free_id)) and _can_block(int(free_id), action.player_id, int(must_id)):
				r.error = "%s must be blocked if able" % (must_obj.definition as CardDefinition).name
				return r
	if block_paid > 0:
		pay_now(action.player_id, ManaCost.parse("{%d}" % block_paid))
		state.log.append(EngineEnums.EventType.NOTE, action.player_id, {"text": "Paid {%d} to block." % block_paid})
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


## "~ can't be blocked by more than one creature." (printed) or Challenger Troll's "Each creature you control with power 4 or
## greater can't be blocked by more than one creature."
func single_blocker_only(attacker: GameObject) -> bool:
	if attacker == null or not (attacker.definition is CardDefinition):
		return false
	if (attacker.definition as CardDefinition).oracle_text.to_lower().contains("can't be blocked by more than one creature") \
			and not (attacker.definition as CardDefinition).oracle_text.to_lower().contains("creature you control with power"):
		return true
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or src.controller_id != attacker.controller_id or not (src.definition is CardDefinition):
			continue
		if (src.definition as CardDefinition).oracle_text.to_lower().contains("each creature you control with power 4 or greater can't be blocked by more than one creature") and power_of(attacker) >= 4:
			return true
	return false


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
	## "Target creature can't block this turn" grants the pseudo-keyword "Can't block".
	if has_keyword(obj, "Can't block"):
		return false
	## "This token can't block." / "This creature can't block." on the card itself.
	if obj.definition is CardDefinition and not (layers != null and layers.loses_abilities(state, obj)):
		var otext := (obj.definition as CardDefinition).oracle_text.to_lower()
		if otext.contains("this token can't block") or otext.contains("this creature can't block") or otext.contains("\n~ can't block") or otext.begins_with("~ can't block"):
			return false
		if _printed_cant(obj, "block"):
			return false
	var attacker: GameObject = state.objects.get(attacker_id) if attacker_id >= 0 else null
	if attacker == null:
		return true
	## Protection (CR 702.16f): it can't be blocked by creatures of a color it has protection from.
	if protected_from(attacker, obj):
		return false
	## Flying (CR 702.9b): only creatures with flying or reach can block it.
	if has_keyword(attacker, "Flying") and not (has_keyword(obj, "Flying") or has_keyword(obj, "Reach")):
		return false
	var bdef: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	var adef: CardDefinition = attacker.definition as CardDefinition if attacker.definition is CardDefinition else null
	if bdef != null and adef != null:
		var blocker_artifact := bdef.type_line.contains("Artifact")
		## Fear (CR 702.36): only artifact and/or black creatures can block it.
		if has_keyword(attacker, "Fear") and not (blocker_artifact or bdef.colors.has("B")):
			return false
		## Intimidate (CR 702.13): only artifact creatures and creatures sharing a color can block it.
		if has_keyword(attacker, "Intimidate") and not blocker_artifact:
			var shares := false
			for c in adef.colors:
				if bdef.colors.has(c):
					shares = true
			if not shares:
				return false
	## "~ can block only creatures with flying." (Cloud Sprite): printed on the blocker.
	if bdef != null and not has_keyword(attacker, "Flying") and bdef.oracle_text.to_lower().contains("can block only creatures with flying"):
		return false
	## "~ can't be blocked by creatures with power 2 or less." printed on the attacker.
	if adef != null:
		var pw_rule := RegEx.create_from_string("(?i)can't be blocked by creatures with power (\\d+) or (less|greater)").search(adef.oracle_text)
		if pw_rule != null and (power_of(obj) <= int(pw_rule.get_string(1)) if pw_rule.get_string(2).to_lower() == "less" else power_of(obj) >= int(pw_rule.get_string(1))):
			return false
	## "Target creature can't be blocked this turn" (Rogue's Passage) grants Unblockable (CR 509.1b).
	if has_keyword(attacker, "Unblockable"):
		return false
	## Shadow (CR 702.28) and horsemanship (CR 702.31): only blocked by, and only block, creatures that have it.
	for kw in ["Shadow", "Horsemanship"]:
		if has_keyword(attacker, kw) != has_keyword(obj, kw):
			return false
	## "~ can't be blocked." (a whole sentence; "can't be blocked by ..." and "except" are conditional).
	if adef != null and RegEx.create_from_string("(?i)can't be blocked\\.").search(adef.oracle_text) != null:
		return false
	## "Juggernauts you control can't be blocked by Walls" (Graaz): a static of another permanent.
	if not _static_block_allows(attacker, obj):
		return false
	## "~ can't be blocked except by black creatures" / "can't be blocked by Walls" (read from the attacker's own text).
	if adef != null and not _block_text_allows(adef, attacker, obj):
		return false
	## Skulk (CR 702.118): can't be blocked by creatures with greater power.
	if has_keyword(attacker, "Skulk") and power_of(obj) > power_of(attacker):
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
	## Colored needs first, then generic; in each, sources that always make the same mana go first, so a
	## flexible source (any color, a dual land) is still free for whatever color is left over.
	for for_generic in [false, true]:
		if for_generic and _payment.generic <= 0:
			break
		for flexible in [false, true]:
			for a in acts:
				var ga := a as GameAction
				var raw := _produced_mana(ga.object_id, ga.ability_id, false)
				if raw == null or raw.choices.is_empty() == flexible:
					continue
				var produced := _produced_mana(ga.object_id, ga.ability_id, true)
				if produced == null:
					continue
				if for_generic:
					if produced.cmc() > 0:
						return a
					continue
				for k in ["w", "u", "b", "r", "g", "colorless"]:
					if int(need[k]) > 0 and int(produced.get(k)) > 0:
						return a
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
			var mana_text := str((fx as AbilityEffect).params.get("mana", ""))
			if mana_text.contains("{OPP}"):
				var opp := opponent_land_colors(obj.controller_id)
				mana_text = "{%s}" % "|".join(PackedStringArray(opp)) if not opp.is_empty() else ""
			if mana_text.contains("{OWN}"):
				var own_cols := own_land_colors(obj.controller_id)
				mana_text = "{%s}" % "|".join(PackedStringArray(own_cols)) if not own_cols.is_empty() else ""
			if mana_text.contains("|CHOSEN}"):
				mana_text = mana_text.replace("|CHOSEN}", ("|%s}" % obj.chosen_color) if obj.chosen_color != "" else "}")
			if mana_text.contains("{CHOSEN}"):
				mana_text = mana_text.replace("{CHOSEN}", "{%s}" % obj.chosen_color if obj.chosen_color != "" else "")
			var raw := ManaCost.parse(mana_text)
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
			## Only the five colors are counted; anything else ("c", an unresolved marker) has no pool field.
			if not key in ["w", "u", "b", "r", "g"]:
				continue
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


## "Whenever you tap a land for mana while you're the monarch, add an additional one mana of any color."
## Read from the permanents' Oracle text (Regal Behemoth); each copy adds one.
func _monarch_land_bonus(player_id: int, tapped: GameObject) -> void:
	if state.monarch_id != player_id or not (tapped.definition is CardDefinition) or not (tapped.definition as CardDefinition).is_land():
		return
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o == null or o.controller_id != player_id or not (o.definition is CardDefinition) or o.phased_out:
			continue
		if (o.definition as CardDefinition).oracle_text.to_lower().contains("whenever you tap a land for mana while you're the monarch"):
			mana.add(player_id, resolve_mana(player_id, ManaCost.parse("{W|U|B|R|G}")))


## The colors a land an opponent controls could produce ("Exotic Orchard"): W U B R G letters, no repeats.
func opponent_land_colors(player_id: int) -> Array:
	return _land_colors(player_id, false)


## The colors a land you control could produce (Reflecting Pool).
func own_land_colors(player_id: int) -> Array:
	return _land_colors(player_id, true)


func _land_colors(player_id: int, own: bool) -> Array:
	var found := {}
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf != null:
		for oid in bf.object_ids:
			var o: GameObject = state.objects.get(oid)
			if o == null or (o.controller_id == player_id) != own or not (o.definition is CardDefinition):
				continue
			var def := o.definition as CardDefinition
			if not def.is_land():
				continue
			for a in def.mana_abilities():
				for fx in (a as Ability).effects:
					if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA":
						var t := str((fx as AbilityEffect).params.get("mana", ""))
						if t.contains("OPP") or t.contains("OWN"):
							continue
						if o.chosen_color != "":
							t = t.replace("{CHOSEN}", "{%s}" % o.chosen_color).replace("|CHOSEN}", "|%s}" % o.chosen_color)
						else:
							t = t.replace("{CHOSEN}", "").replace("|CHOSEN}", "}")
						var raw := ManaCost.parse(t)
						for pair in [["W", raw.w], ["U", raw.u], ["B", raw.b], ["R", raw.r], ["G", raw.g]]:
							if int(pair[1]) > 0:
								found[pair[0]] = true
						for opt in raw.choices:
							for c in opt:
								if str(c) == "CI":
									for ci in commander_identity(o.controller_id):
										found[str(ci)] = true
								elif str(c) in ["W", "U", "B", "R", "G"]:
									found[str(c)] = true
	var out: Array = []
	for c in ["W", "U", "B", "R", "G"]:
		if found.has(c):
			out.append(c)
	return out


## False for a mana ability that would make no mana right now (Exotic Orchard with no opposing lands).
func _mana_text_makes_mana(obj: GameObject, ab: Ability) -> bool:
	for fx in ab.effects:
		if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA" and str((fx as AbilityEffect).params.get("mana", "")).contains("OPP"):
			return not opponent_land_colors(obj.controller_id).is_empty()
		if fx is AbilityEffect and (fx as AbilityEffect).kind == &"ADD_MANA" and str((fx as AbilityEffect).params.get("mana", "")).contains("OWN"):
			return not own_land_colors(obj.controller_id).is_empty()
	return true


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


## "R/G  W  C" - one group per mana the player can make now, listing the colors it can be. For tooltips.
func mana_summary(player_id: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for slot in mana_slots(player_id):
		parts.append("/".join(PackedStringArray(slot)))
	return "  ".join(parts) if not parts.is_empty() else "none"


## Every way to pay the hybrid and Phyrexian symbols of `cost` as {cost: plain ManaCost, life: int}.
## Colored options come before generic "2" before life, so the first affordable variant avoids life loss.
func hybrid_variants(cost: ManaCost) -> Array:
	var base := cost.duplicate_cost()
	base.hybrid = []
	var variants: Array = [{"cost": base, "life": 0}]
	for sym in cost.hybrid:
		var options: Array = []
		for o in (sym as Array):
			if str(o) != "2" and str(o) != "P":
				options.append(str(o))
		if (sym as Array).has("2"):
			options.append("2")
		if (sym as Array).has("P"):
			options.append("P")
		var next: Array = []
		for v in variants:
			for o in options:
				var c: ManaCost = (v.cost as ManaCost).duplicate_cost()
				var life := int(v.life)
				match o:
					"W": c.w += 1
					"U": c.u += 1
					"B": c.b += 1
					"R": c.r += 1
					"G": c.g += 1
					"C": c.colorless += 1
					"2": c.generic += 2
					"P": life += 2
				next.append({"cost": c, "life": life})
		variants = next
	return variants


## The cheapest affordable way to pay `cost`'s hybrid symbols; the first variant when none is affordable.
func resolve_hybrid(player_id: int, cost: ManaCost) -> Dictionary:
	var variants := hybrid_variants(cost)
	for v in variants:
		if _variant_ok(player_id, v):
			return v
	return variants[0]


func _variant_ok(player_id: int, v: Dictionary) -> bool:
	if int(v.life) > 0 and state.players[player_id].life < int(v.life):
		return false
	return _can_afford_plain(player_id, v.cost)


## True if the player's pool and untapped mana sources can pay `cost`, colors included.
func can_afford(player_id: int, cost: ManaCost) -> bool:
	if cost.hybrid.is_empty():
		return _can_afford_plain(player_id, cost)
	for v in hybrid_variants(cost):
		if _variant_ok(player_id, v):
			return true
	return false


func _can_afford_plain(player_id: int, cost: ManaCost) -> bool:
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


## Pays `cost` right now from the pool and untapped sources (special actions, ward, echo ...). False, with nothing
## spent, when it can't be paid.
func pay_now(player_id: int, cost: ManaCost) -> bool:
	var c := cost.duplicate_cost()
	if not c.hybrid.is_empty():
		var pick := resolve_hybrid(player_id, c)
		if int(pick.life) > 0 and state.players[player_id].life < int(pick.life):
			return false
		c = pick.cost
		if not _can_afford_plain(player_id, c):
			return false
		state.players[player_id].life -= int(pick.life)
	if not _can_afford_plain(player_id, c):
		return false
	var saved := _payment
	_payment = c
	var ok := _auto_finish_payment(player_id)
	_payment = saved
	return ok


## A triggered-ability-like stack entry made by the engine itself (ward, madness, miracle, cycling's draw ...).
func put_synthetic(source: GameObject, controller: int, effects: Array, ctx: Dictionary, source_id: int = 0) -> StackEntry:
	var entry := StackEntry.new()
	entry.stack_id = state.next_stack_id
	state.next_stack_id += 1
	entry.kind = StackEntry.Kind.TRIGGERED
	entry.object_id = 0
	entry.source_id = source.object_id if source != null else source_id
	entry.controller_id = controller
	entry.ability_id = &"keyword"
	entry.effects = effects.duplicate()
	entry.ctx = ctx.duplicate()
	(state.stack as MagicStack).push(entry)
	state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, controller, {
		object_id = entry.source_id,
		stack_id = entry.stack_id,
		trigger = true,
	})
	return entry


## A card in exile its controller may play: "you may play it this turn" (impulse draw), or a permission on a permanent
## that exiled it ("you may play lands and cast spells from among cards exiled with ~", Theater of Horrors).
func can_play_from_exile(pid: int, obj: GameObject) -> bool:
	if obj == null or obj.zone != EngineEnums.ZoneId.EXILE:
		return false
	if obj.may_play_controller == pid:
		return true
	var sid := int(obj.marks.get("exiled_with", 0))
	var src: GameObject = state.objects.get(sid) if sid != 0 else null
	if src == null or src.zone != EngineEnums.ZoneId.BATTLEFIELD or src.controller_id != pid or not (src.definition is CardDefinition):
		return false
	for a in (src.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("play_exiled_with") and layers.condition_met(state, src, ab.static_spec.get("condition", {})):
			return true
	return false


## Discarding (CR 701.8): a card with madness goes to exile and its owner may cast it (CR 702.35).
func discard_card(player_id: int, object_id: int) -> GameObject:
	var obj: GameObject = state.objects.get(object_id)
	if obj == null:
		return null
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	obj.discarded_turn = state.turn_number
	if def != null and def.kw().has("madness") and not def.is_land():
		var ex: GameObject = state.zones.move(object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
		if ex != null:
			var fx := AbilityEffect.new()
			fx.kind = &"MADNESS"
			fx.params = {"object_id": ex.object_id}
			put_synthetic(null, obj.owner_id, [fx], {}, ex.object_id)
		return ex
	var gone: GameObject = state.zones.move(object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
	if gone != null:
		gone.discarded_turn = state.turn_number
	return gone


## "Becomes an artifact creature until end of turn" (crew and friends).
func animate_until_eot(obj: GameObject, types: Array) -> void:
	var effect := ContinuousEffect.new()
	effect.object_ids = [obj.object_id]
	effect.source_id = obj.object_id
	effect.controller_id = obj.controller_id
	effect.timestamp = state.next_timestamp
	state.next_timestamp += 1
	effect.until_eot = true
	for t in types:
		effect.add_types.append(str(t))
	state.effects.append(effect)


## Removes a spell or ability from the stack without resolving it (ward, counterspells).
func counter_entry(stack_id: int) -> bool:
	var found: StackEntry = (state.stack as MagicStack).remove_by_stack_id(stack_id)
	if found == null:
		return false
	if found.object_id != 0:
		var obj: GameObject = state.objects.get(found.object_id)
		if obj != null and obj.zone == EngineEnums.ZoneId.STACK:
			state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
	return true


## The largest X an ability with `per` {X} symbols and the fixed cost `base` can be activated with right now.
func max_x_for(player_id: int, base: ManaCost, per: int = 1) -> int:
	var n := 0
	for i in range(0, 40):
		var c := base.duplicate_cost()
		c.generic += i * per
		if not _can_afford_plain(player_id, c):
			break
		n = i
	return n


## Largest X for an activated ability on the battlefield (the table lists X = 1, 2, 3 ... as menu entries).
func max_x_of_ability(player_id: int, obj: GameObject, ab: Ability) -> int:
	var base := costs.mana_cost(ab)
	if base.x <= 0:
		return 0
	var per := base.x
	base.x = 0
	var saved := _afford_ctx
	var saved_ab := _afford_is_ability
	_afford_ctx = obj
	_afford_is_ability = true
	var n := max_x_for(player_id, base, per)
	_afford_ctx = saved
	_afford_is_ability = saved_ab
	return n


## What the gold border asks: can this card be paid for right now (mana, plus convoke and delve)?
func can_afford_spell(player_id: int, obj: GameObject, cost: ManaCost) -> bool:
	return kw.afford(player_id, obj, cost)


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
		if not (obj.definition is CardDefinition) or not _is_creature_now(obj):
			continue
		if obj.summoned_this_turn and not _has_haste(obj):
			continue
		if has_keyword(obj, "Defender") or _printed_cant(obj, "attack"):
			continue
		if layers != null and layers.combat_restricted(state, obj, true):
			continue
		if not _attack_allowed_vs_defenders(obj):
			continue
		out.append(obj.object_id)
	return out


## "~ can't attack unless defending player controls an Island." (CR 508.1c): some opponent must control a permanent of that type.
func _attack_allowed_vs_defenders(obj: GameObject) -> bool:
	var def := obj.definition as CardDefinition
	if not def.oracle_text.contains("unless defending player controls"):
		return true
	var m := RegEx.create_from_string("(?i)can't attack unless defending player controls an? ([a-z]+)").search(def.oracle_text)
	if m == null:
		return true
	var need := m.get_string(1).substr(0, 1).to_upper() + m.get_string(1).substr(1).to_lower()
	for p in state.players:
		if p.player_id == obj.controller_id or p.lost:
			continue
		if Query.count_objects(state, obj, {"controller_id": p.player_id, "subtype": need}) > 0:
			return true
	return false


## "can't be blocked except by <group>" allows only that group; "can't be blocked by <group>" forbids it. A group the
## reader can't turn into a query is ignored.
func _block_text_allows(adef: CardDefinition, attacker: GameObject, blocker: GameObject) -> bool:
	var text := adef.oracle_text.to_lower()
	var except_m := RegEx.create_from_string("can't be blocked except by ([^.,]+)").search(text)
	if except_m != null:
		var q := OracleIr.new()._event_subject(except_m.get_string(1), false)
		if not q.is_empty() and not Query._matches(blocker, attacker, q):
			return false
	var by_m := RegEx.create_from_string("can't be blocked by ([^.,]+)").search(text)
	if by_m != null:
		var q2 := OracleIr.new()._event_subject(by_m.get_string(1), false)
		if not q2.is_empty() and Query._matches(blocker, attacker, q2):
			return false
	return true


## "You can't cast ~ unless an opponent lost life this turn" (Rakdos, Lord of Riots).
func _cast_forbidden(obj: GameObject) -> bool:
	if not (obj.definition is CardDefinition):
		return false
	## "Each player can't cast more than one spell each turn." (Rule of Law, Eidolon of Rhetoric): one already cast this turn.
	if obj.controller_id >= 0 and obj.controller_id < state.players.size() and state.players[obj.controller_id].spells_this_turn.size() >= 1 \
			and _battlefield_text_has("can't cast more than one spell each turn"):
		return true
	for a in (obj.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("cast_condition") and not layers.condition_met(state, obj, ab.static_spec["cast_condition"]):
			return true
	return false


## "~ can't attack." / "~ can't attack or block." as a line of the card's own text (and the same for blocking).
func _printed_cant(obj: GameObject, what: String) -> bool:
	if not (obj.definition is CardDefinition) or (layers != null and layers.loses_abilities(state, obj)):
		return false
	var t := (obj.definition as CardDefinition).oracle_text.to_lower().replace((obj.definition as CardDefinition).name.to_lower(), "~").replace("this creature", "~")
	for line in t.split("\n"):
		var l := str(line).strip_edges().trim_suffix(".")
		if l == "~ can't %s" % what or l == "~ can't attack or block" or l == "~ can't block or attack":
			return true
	return false


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
		return str(layers.snapshot(state, obj, "type").get("type_line", "")).contains("Creature")
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
	## CR 606.3: one loyalty ability of a permanent per turn, at sorcery speed.
	if ab.restrictions.has("LOYALTY"):
		if actor != state.active_player_id or not _is_main_phase() or not _stack_empty():
			return "NOT_SORCERY_SPEED"
		if obj.loyalty_turn == state.turn_number:
			return "LOYALTY_USED"
	## Channel and forecast abilities are activated from the hand (special actions), never from the battlefield.
	if ab.restrictions.has("CHANNEL") or ab.restrictions.has("FORECAST"):
		return "FROM_HAND"
	## Boast (CR 702.142a): only if it attacked this turn, and only once each turn.
	if ab.restrictions.has("BOAST") and (obj.attacked_turn != state.turn_number or int(obj.marks.get("boast_turn", -1)) == state.turn_number):
		return "NOT_BOASTABLE"
	## Exhaust (CR 702.177a): each exhaust ability once.
	if ab.restrictions.has("EXHAUST") and bool(obj.marks.get("exhausted_" + str(ab.ability_id), false)):
		return "EXHAUSTED"
	## Max speed (CR 702.178): only while its controller's speed is 4.
	if ab.restrictions.has("MAX_SPEED") and state.players[obj.controller_id].speed < 4:
		return "NOT_MAX_SPEED"
	if ab.restrictions.has("MY_TURN") and actor != state.active_player_id:
		return "NOT_YOUR_TURN"
	if ab.restrictions.has("ONCE_EACH_TURN") and int(obj.marks.get("act_turn_" + str(ab.ability_id), -1)) == state.turn_number:
		return "ALREADY_ACTIVATED"
	for cr in ab.restrictions:
		if cr is Dictionary and (cr as Dictionary).has("cond") and not layers.condition_met(state, obj, (cr as Dictionary)["cond"]):
			return "CONDITION_NOT_MET"
	if ab.restrictions.has("CITYS_BLESSING") and Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER"}) < 10:
		return "NO_CITYS_BLESSING"
	for rr in ab.restrictions:
		if rr is Dictionary and (rr as Dictionary).has("min_lands") and Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER", "type": "land"}) < int((rr as Dictionary).min_lands):
			return "NOT_ENOUGH_LANDS"
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
	_act_x = 0
	_paid_by = []
	if _payment != null and _payment.x > 0:
		## {X} in an activated ability's cost: the player names X (extra.x), else as much as can be paid.
		var per := _payment.x
		var want := int(extra.get("x", -1))
		_payment.x = 0
		_act_paying = true
		_act_x = want if want >= 0 else max_x_for(player_id, _payment, per)
		_act_paying = false
		_payment.generic += _act_x * per
	## Waterbend (CR 701.67): artifacts and creatures cover the generic mana the mana sources can't.
	var waterbend_n := costs.waterbend_amount(ab)
	if waterbend_n > 0 and _payment != null and not _can_afford_plain(player_id, _payment):
		_payment = kw.cover_waterbend(player_id, src, _payment, waterbend_n)
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
	if ab.restrictions.has("LOYALTY"):
		obj.loyalty_turn = state.turn_number
	if ab.restrictions.has("BOAST"):
		obj.marks["boast_turn"] = state.turn_number
	if ab.restrictions.has("ONCE_EACH_TURN"):
		obj.marks["act_turn_" + str(ab.ability_id)] = state.turn_number
	if ab.restrictions.has("EXHAUST"):
		obj.marks["exhausted_" + str(ab.ability_id)] = true
	var entry := StackEntry.new()
	entry.stack_id = state.next_stack_id
	state.next_stack_id += 1
	entry.ctx = {"x": _act_x}
	_act_x = 0
	_paid_by = []
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
	kw.check_ward(entry)
	if triggers != null:
		triggers.on_ability_activated(self, obj, player_id)
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
				condition = str(cond.get("text", "â")),
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
		lines.append(str(info.get("condition", "â")))
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
	return {text = "â", result = true}


## "Prevent all combat damage that would be dealt to ~" is one of the permanent's own lines (Seraph of the Sword).
func _prints_combat_prevention(obj: GameObject) -> bool:
	if not (obj.definition is CardDefinition):
		return false
	var def := obj.definition as CardDefinition
	var short := def.name.to_lower().split(",")[0]
	var t := def.oracle_text.to_lower()
	return t.contains("prevent all combat damage that would be dealt to " + short) or t.contains("prevent all combat damage that would be dealt to this creature")


## Attack costs (CR 508.1h): "creatures can't attack you unless their controller pays {1} for each of them" (Archangel of Tithes
## while untapped, Propaganda). Attackers the player can't afford stay home; the rest are paid for as they are declared.
func _pay_attack_tax(pid: int, ids: Array, requested_defender: int, assigned: Dictionary, use_map: bool) -> Array:
	var kept: Array = []
	var total := 0
	for raw in ids:
		var oid := int(raw)
		var defender := int(assigned[oid]) if use_map and assigned.has(oid) else requested_defender
		var t := _attack_tax_for(defender)
		if t > 0:
			if not can_afford(pid, ManaCost.parse("{%d}" % (total + t))):
				continue
			total += t
		kept.append(raw)
	if total > 0:
		pay_now(pid, ManaCost.parse("{%d}" % total))
		state.log.append(EngineEnums.EventType.NOTE, pid, {"text": "Paid {%d} to attack." % total})
	return kept


## The generic mana each creature attacking `defender` costs (permanents they control with an attack tax).
func _attack_tax_for(defender: int) -> int:
	var total := 0
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null or defender < 0:
		return 0
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o == null or o.controller_id != defender or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("attack_tax"):
				continue
			if str(ab.static_spec.get("while", "")) == "UNTAPPED" and o.tapped:
				continue
			total += int(ab.static_spec["attack_tax"])
	return total


## The generic mana each creature blocking `attacker_id` costs (the attacker's own "can't block unless" static).
func _block_tax_for(attacker_id: int) -> int:
	var o: GameObject = state.objects.get(attacker_id)
	if o == null or not (o.definition is CardDefinition):
		return 0
	var total := 0
	for a in (o.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("block_tax"):
			total += int(ab.static_spec["block_tax"])
	return total


## Whether a creature must attack if able: its own line "~ attacks each combat if able", or a static of a permanent that gives it.
func _must_attack(obj: GameObject) -> bool:
	if obj == null or not (obj.definition is CardDefinition):
		return false
	## "Target creature attacks this turn if able" grants the pseudo-keyword "Must attack".
	if has_keyword(obj, "Must attack"):
		return true
	var def := obj.definition as CardDefinition
	var short := def.name.to_lower().split(",")[0]
	for raw in def.oracle_text.to_lower().split("\n"):
		var l := str(raw).strip_edges().trim_suffix(".")
		if l == short + " attacks each combat if able" or l == "this creature attacks each combat if able" or l == "~ attacks each combat if able":
			return true
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("must_attack") and Query._matches(obj, src, ab.static_spec.get("query", {})):
				return true
	return false


## Statics that stop a group of attackers being blocked by a group of blockers (Graaz: Juggernauts can't be blocked by Walls).
func _static_block_allows(attacker: GameObject, blocker: GameObject) -> bool:
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return true
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("cant_be_blocked_by_group"):
				continue
			var spec: Dictionary = ab.static_spec["cant_be_blocked_by_group"]
			if Query._matches(attacker, src, spec.get("query", {})) and Query._matches(blocker, src, spec.get("by", {})):
				return false
	return true


## One entry per "add an additional {C}" static the player controls (Forsaken Monument).
func _extra_colorless_for(pid: int) -> Array:
	var out: Array = []
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o == null or o.controller_id != pid or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("extra_colorless"):
				for _n in int(ab.static_spec["extra_colorless"]):
					out.append(1)
	return out


## Whether the player controls a "whenever you tap a land for mana, add one mana of any type that land produced" permanent.
func _has_land_mana_doubler(pid: int) -> bool:
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o == null or o.controller_id != pid or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("extra_land_mana"):
				return true
	return false


## Card types the permanent has protection from, printed on it ("Protection from artifacts"): singular, lower case.
func protection_types(obj: GameObject) -> Array:
	var out: Array = []
	if obj == null or not (obj.definition is CardDefinition) or obj.face_down:
		return out
	if layers != null and layers.loses_abilities(state, obj):
		return out
	for raw in (obj.definition as CardDefinition).oracle_text.split("\n"):
		var low := str(raw).to_lower().strip_edges().split("(")[0].strip_edges()
		var i := low.find("protection from ")
		if i < 0 or (i > 0 and not low.substr(0, i).strip_edges().ends_with(",")):
			continue
		for part in low.substr(i + 16).replace(", and ", ",").replace(" and ", ",").replace(", ", ",").split(","):
			var w := str(part).strip_edges()
			for t in ["artifact", "creature", "enchantment", "land", "planeswalker", "instant", "sorcery"]:
				if w == t or w == t + "s":
					out.append(t)
	return out


## A line printed on the permanent (lower case, name as "~"), e.g. "~ must be blocked if able."
func _printed_line(obj: GameObject, fragment: String) -> bool:
	if obj == null or not (obj.definition is CardDefinition) or (layers != null and layers.loses_abilities(state, obj)):
		return false
	var def := obj.definition as CardDefinition
	var t := def.oracle_text.to_lower().replace(def.name.to_lower(), "~").replace("this creature", "~")
	return t.contains(fragment)


## "~ can't attack or block alone." / "~ can't attack alone." / "~ can't block alone."
func _printed_alone_rule(obj: GameObject, attacking: bool) -> bool:
	if attacking:
		return _printed_line(obj, "can't attack or block alone") or _printed_line(obj, "can't attack alone")
	return _printed_line(obj, "can't attack or block alone") or _printed_line(obj, "can't block alone")


## Object ids of the untapped creatures a player controls.
func _creature_ids_of(player_id: int) -> Array:
	var out: Array = []
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o != null and o.controller_id == player_id and not o.tapped and _is_creature_now(o):
			out.append(int(oid))
	return out


## A permanent anywhere on the battlefield whose printed text contains `fragment` ("damage can't be prevented").
func _battlefield_text_has(fragment: String) -> bool:
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var o: GameObject = state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).oracle_text.to_lower().contains(fragment):
			return true
	return false


## How many more attackers than one this creature can block: 1 for "can block an additional creature each combat",
## effectively unlimited for "can block any number of creatures".
func _extra_blocks(obj: GameObject) -> int:
	if _printed_line(obj, "can block any number of creatures"):
		return 99
	if _printed_line(obj, "can block an additional creature each combat"):
		return 1
	return 0
