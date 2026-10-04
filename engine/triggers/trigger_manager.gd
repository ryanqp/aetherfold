class_name TriggerManager
extends RefCounted

## Triggered abilities (CR 603): "when / whenever / at the beginning of". The engine reads each new
## log event (RulesEngine.process_zone_events) and calls on_event; a matching trigger goes on the stack.
##
## An ability's `trigger` dictionary:
##   on      ENTERS_BATTLEFIELD, DIES, ATTACKS, DAMAGED, LIFE_GAINED, COMBAT_DAMAGE_TO_PLAYER,
##           BEGIN_STEP, SPELL_CAST, BLOCKS, BECOMES_BLOCKED
##   scope   SELF (default), OTHER, ANY (self or another), YOU (LIFE_GAINED / ATTACKS: it's about you)
##   filter  a Query spec the subject must match, read from the watcher's side ("you control" = the
##           watcher's controller)
##   step    UPKEEP, BEGIN_COMBAT or END (BEGIN_STEP);  whose  YOURS, OPPONENT or EACH


var _blocked_seen: Dictionary = {}


func on_spell_cast(engine: RulesEngine, spell_obj: GameObject, caster_id: int) -> void:
	if spell_obj == null:
		return
	var def: CardDefinition = spell_obj.definition as CardDefinition if spell_obj.definition is CardDefinition else null
	var spell_types := PackedStringArray()
	if def != null:
		for t in ["instant", "sorcery", "creature", "artifact", "enchantment", "land"]:
			if def.type_line.to_lower().contains(t):
				spell_types.append(t)
		if not def.is_creature():
			spell_types.append("noncreature")
	var ctx := {object_id = spell_obj.object_id, player_id = caster_id}
	## Spells cast this turn, by type ("your first noncreature spell each turn").
	if caster_id >= 0 and caster_id < engine.state.players.size():
		engine.state.players[caster_id].spells_this_turn.append(Array(spell_types))
	## "When you cast this spell" (cascade): the spell's own abilities, while it is on the stack.
	spell_obj.controller_id = caster_id
	for own in _triggered(engine, spell_obj, "SPELL_CAST"):
		if bool(own.trigger.get("scope_self", false)):
			_put_trigger(engine, spell_obj, own, ctx)
	## Demonstrate (CR 702.144): "when you cast this spell, you may copy it ...".
	if def != null and def.kw().has("demonstrate"):
		var top: StackEntry = (engine.state.stack as MagicStack).top()
		var fx := AbilityEffect.new()
		fx.kind = &"DEMONSTRATE"
		fx.params = {}
		engine.put_synthetic(spell_obj, caster_id, [fx], {"spell_stack_id": top.stack_id if top != null else 0})
	_eng_ref = engine
	for src in _battlefield(engine):
		for ab in _triggered(engine, src, "SPELL_CAST"):
			if _matches_spell_cast(ab, src, caster_id, spell_types, spell_obj):
				_put_trigger(engine, src, ab, ctx)
	_eng_ref = null


func _matches_spell_cast(ab: Ability, source: GameObject, caster_id: int, spell_types: PackedStringArray, spell_obj: GameObject) -> bool:
	if bool(ab.trigger.get("scope_self", false)):
		return false
	var filt: Variant = ab.trigger.get("filter", {})
	if not (filt is Dictionary):
		return true
	var f: Dictionary = filt
	var ctrl := str(f.get("controller", "ANY"))
	if ctrl == "SOURCE_CONTROLLER" and source.controller_id != caster_id:
		return false
	if ctrl == "OPPONENT" and source.controller_id == caster_id:
		return false
	var types: Variant = f.get("types", [])
	if types is Array and not (types as Array).is_empty():
		var ok := false
		for t in types:
			if str(t) in spell_types:
				ok = true
				break
		if not ok:
			return false
		## "Your first noncreature spell each turn": this is the nth spell of those types the caster cast this turn.
		if f.has("nth"):
			var seen := 0
			for cast_types in engine_ref_spells(source, caster_id):
				for t2 in types:
					if (cast_types as Array).has(str(t2)):
						seen += 1
						break
			if seen != int(f["nth"]):
				return false
	var q: Variant = f.get("query", {})
	if q is Dictionary and not (q as Dictionary).is_empty():
		if not Query._matches(spell_obj, source, q):
			return false
	return true


## "When ~ enters": kept for callers that hand over one object.
func on_enter_battlefield(engine: RulesEngine, obj: GameObject) -> void:
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	_fire(engine, "ENTERS_BATTLEFIELD", obj, obj, _ctx_for(engine, obj))


func on_combat_damage_to_player(engine: RulesEngine, source: GameObject, defender_id: int, amount: int) -> void:
	if source == null or amount <= 0:
		return
	## CR 724.2: combat damage to the monarch makes the attacker's controller the monarch.
	if defender_id == engine.state.monarch_id and source.controller_id != defender_id:
		engine.state.monarch_id = source.controller_id
	var ctx := _ctx_for(engine, source)
	ctx["amount"] = amount
	ctx["defender"] = defender_id
	_fire(engine, "COMBAT_DAMAGE_TO_PLAYER", source, source, ctx)


## Reads one log event. Called for every event, in order, by RulesEngine.process_zone_events.
func on_event(engine: RulesEngine, e: GameEvent) -> void:
	var p: Dictionary = e.payload
	match e.type:
		EngineEnums.EventType.ZONE_CHANGE:
			_on_zone_change(engine, p)
		EngineEnums.EventType.ATTACK:
			_on_attack(engine, e)
		EngineEnums.EventType.BLOCK:
			_on_block(engine, p)
		EngineEnums.EventType.STEP_BEGIN:
			_on_step_begin(engine, int(p.get("step", -1)), e.player_id)
		EngineEnums.EventType.DAMAGE:
			if p.has("to_player") and int(p.get("amount", 0)) > 0:
				_tally_life(engine, int(p.get("to_player", -1)), int(p.get("amount", 0)), false)
			if p.has("to_object") and int(p.get("amount", 0)) > 0:
				var hurt: GameObject = engine.state.objects.get(int(p.get("to_object", 0)))
				if hurt != null and hurt.zone == EngineEnums.ZoneId.BATTLEFIELD:
					var ctx := _ctx_for(engine, hurt)
					ctx["amount"] = int(p.get("amount", 0))
					_fire(engine, "DAMAGED", hurt, hurt, ctx)
		EngineEnums.EventType.DRAW:
			_on_draw(engine, e.player_id)
		EngineEnums.EventType.LIFE_CHANGE:
			_tally_life(engine, int(p.get("to_player", e.player_id)), int(p.get("amount", 0)), bool(p.get("gain", false)))
			if bool(p.get("gain", false)):
				_on_life_gained(engine, int(p.get("to_player", e.player_id)), int(p.get("amount", 0)))


func _on_zone_change(engine: RulesEngine, p: Dictionary) -> void:
	var from_z := int(p.get("from_zone", -1))
	var to_z := int(p.get("to_zone", -1))
	if to_z == EngineEnums.ZoneId.BATTLEFIELD:
		var obj: GameObject = engine.state.objects.get(int(p.get("to_id", 0)))
		if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
			_fire(engine, "ENTERS_BATTLEFIELD", obj, obj, _ctx_for(engine, obj))
			_on_permanent_entered(engine, obj, from_z)
	if from_z == EngineEnums.ZoneId.BATTLEFIELD and to_z != EngineEnums.ZoneId.BATTLEFIELD:
		## The permanent is gone, so it is read from what was recorded as it left (last known information).
		var ghost := GameObject.new()
		ghost.object_id = int(p.get("from_id", 0))
		ghost.definition = p.get("definition", null)
		ghost.controller_id = int(p.get("from_controller", 0))
		ghost.owner_id = ghost.controller_id
		ghost.is_token = bool(p.get("was_token", false))
		ghost.zone = EngineEnums.ZoneId.BATTLEFIELD
		if ghost.definition == null:
			return
		var self_obj: GameObject = engine.state.objects.get(int(p.get("to_id", 0)))
		if self_obj == null:
			self_obj = ghost
		var lki: Dictionary = p.get("lki", {})
		var ctx := {
			object_id = ghost.object_id,
			player_id = ghost.controller_id,
			power = int(lki.get("power", 0)),
			toughness = int(lki.get("toughness", 0)),
			counters = lki.get("counters", {}),
		}
		if to_z == EngineEnums.ZoneId.GRAVEYARD:
			_fire(engine, "DIES", ghost, self_obj, ctx)
			_enchanted_died(engine, ghost.object_id, ctx)
		## "Whenever another permanent you control leaves the battlefield" (Angelic Sleuth): any destination.
		_fire(engine, "LEAVES", ghost, self_obj, ctx)


func _on_attack(engine: RulesEngine, e: GameEvent) -> void:
	var attackers: Array = e.payload.get("attackers", [])
	for aid in attackers:
		var atk: GameObject = engine.state.objects.get(int(aid))
		if atk != null and atk.zone == EngineEnums.ZoneId.BATTLEFIELD:
			var actx := _ctx_for(engine, atk)
			actx["defender"] = engine.defender_of(atk.object_id)
			_fire(engine, "ATTACKS", atk, atk, actx)
	if attackers.is_empty():
		return
	## "Whenever another player attacks with two or more creatures" (Firemane Commando): the attacker is the trigger's player.
	for opp_src in _battlefield(engine):
		if opp_src.controller_id == e.player_id:
			continue
		for opp_ab in _triggered(engine, opp_src, "OPP_ATTACKS"):
			if attackers.size() >= int(opp_ab.trigger.get("attackers_min", 1)):
				_put_trigger(engine, opp_src, opp_ab, {player_id = e.player_id})
	for src in _battlefield(engine):
		if src.controller_id != e.player_id:
			continue
		for ab in _triggered(engine, src, "ATTACKS"):
			if str(ab.trigger.get("scope", "SELF")) == "YOU" and attackers.size() >= int(ab.trigger.get("attackers_min", 1)):
				_put_trigger(engine, src, ab, {player_id = e.player_id})
		## Exalted granted by an effect (Merchant of Truth: "Clues you control have exalted"): the same +1/+1.
		if attackers.size() == 1 and _triggered(engine, src, "ATTACKS_ALONE").is_empty() and engine.has_keyword(src, "Exalted"):
			var ex_fx := AbilityEffect.new()
			ex_fx.kind = &"PUMP"
			ex_fx.params = {"trigger_object": true, "power": 1, "toughness": 1, "duration": "END_OF_TURN"}
			engine.put_synthetic(src, e.player_id, [ex_fx], {player_id = e.player_id, object_id = int(attackers[0])})
		## Exalted (CR 702.83): "whenever a creature you control attacks alone".
		if attackers.size() == 1:
			for ab2 in _triggered(engine, src, "ATTACKS_ALONE"):
				_put_trigger(engine, src, ab2, {player_id = e.player_id, object_id = int(attackers[0])})


## Blocks: "whenever this creature blocks" (BLOCKS) and "whenever this creature becomes blocked" (BECOMES_BLOCKED,
## once per attacker; ctx has every blocker for flanking and rampage).
func _on_block(engine: RulesEngine, p: Dictionary) -> void:
	_fire_unblocked(engine)
	var bid := int(p.get("blocker_id", 0))
	var aid := int(p.get("attacker_id", 0))
	if bid == 0 or aid == 0:
		return
	var blocker: GameObject = engine.state.objects.get(bid)
	var attacker: GameObject = engine.state.objects.get(aid)
	if blocker != null and blocker.zone == EngineEnums.ZoneId.BATTLEFIELD:
		var ctx := _ctx_for(engine, blocker)
		ctx["attacker_id"] = aid
		_fire(engine, "BLOCKS", blocker, blocker, ctx)
	if attacker == null or attacker.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var key := "%d_%d" % [engine.state.turn_number, aid]
	if _blocked_seen.has(key):
		return
	_blocked_seen[key] = true
	var ids: Array = []
	if engine.state.combat is CombatState:
		ids = ((engine.state.combat as CombatState).blockers.get(aid, []) as Array).duplicate()
	var ctx2 := _ctx_for(engine, attacker)
	ctx2["blocker_ids"] = ids
	ctx2["blocker_count"] = ids.size()
	ctx2["defender"] = engine.defender_of(aid)
	_fire(engine, "BECOMES_BLOCKED", attacker, attacker, ctx2)


func _on_step_begin(engine: RulesEngine, step: int, active: int) -> void:
	engine.kw.on_step_begin(step, active)
	## CR 714.3b: as the precombat main phase begins, the active player puts a lore counter on each of their Sagas.
	if step == EngineEnums.Step.PRECOMBAT_MAIN:
		for src0 in _battlefield(engine):
			if src0.controller_id == active and (src0.definition as CardDefinition).type_line.contains("Saga") and not src0.face_down:
				add_lore(engine, src0, 1)
		return
	var step_name := ""
	match step:
		EngineEnums.Step.UPKEEP:
			step_name = "UPKEEP"
		EngineEnums.Step.DRAW:
			step_name = "DRAW"
		EngineEnums.Step.BEGIN_COMBAT:
			step_name = "BEGIN_COMBAT"
		EngineEnums.Step.END:
			step_name = "END"
		_:
			return
	_fire_delayed(engine, step_name, active)
	## CR 724.3: the monarch draws a card at the beginning of their end step.
	if step_name == "END" and engine.state.monarch_id == active:
		engine.draw_card(active)
	for src in _battlefield(engine):
		for ab in _triggered(engine, src, "BEGIN_STEP"):
			if str(ab.trigger.get("step", "")) != step_name:
				continue
			var whose := str(ab.trigger.get("whose", "YOURS"))
			if whose == "YOURS" and src.controller_id != active:
				continue
			if whose == "OPPONENT" and src.controller_id == active:
				continue
			_put_trigger(engine, src, ab, {player_id = active})


## Life gained / lost this turn ("if you gained life this turn", "if an opponent lost life this turn", spectacle).
func _tally_life(engine: RulesEngine, pid: int, amount: int, gain: bool) -> void:
	if pid < 0 or pid >= engine.state.players.size() or amount <= 0:
		return
	if gain:
		engine.state.players[pid].life_gained_this_turn += amount
	else:
		var first := engine.state.players[pid].life_lost_this_turn == 0 and engine.state.active_player_id == pid
		engine.state.players[pid].life_lost_this_turn += amount
		## "Whenever an opponent loses life for the first time during each of their turns" (Valgavoth).
		if first:
			for src in _battlefield(engine):
				if src.controller_id == pid:
					continue
				for ab in _triggered(engine, src, "OPP_LOSES_LIFE_FIRST"):
					_put_trigger(engine, src, ab, {player_id = pid})


## "Whenever you / an opponent / a player draws a card": the drawer is the trigger's player.
func _on_draw(engine: RulesEngine, drawer: int) -> void:
	for src in _battlefield(engine):
		for ab in _triggered(engine, src, "DRAWS"):
			var who := str(ab.trigger.get("who", "YOU"))
			if who == "YOU" and drawer != src.controller_id:
				continue
			if who == "OPPONENT" and drawer == src.controller_id:
				continue
			_put_trigger(engine, src, ab, {player_id = drawer})


func _on_life_gained(engine: RulesEngine, player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	for src in _battlefield(engine):
		if src.controller_id != player_id:
			continue
		for ab in _triggered(engine, src, "LIFE_GAINED"):
			## "Whenever you gain life for the first time each turn" (Vanguard Seraph).
			if bool(ab.trigger.get("first_each_turn", false)) and engine.state.players[player_id].life_gained_this_turn != amount:
				continue
			_put_trigger(engine, src, ab, {player_id = player_id, amount = amount})


## `subject` is the object the event is about; `self_obj` is the object that carries the "this
## creature" abilities (the subject itself, or what it became after leaving the battlefield).
func _fire(engine: RulesEngine, on: String, subject: GameObject, self_obj: GameObject, ctx: Dictionary) -> void:
	var watchers: Array = []
	for o in _battlefield(engine):
		if self_obj == null or o.object_id != self_obj.object_id:
			watchers.append(o)
	if self_obj != null:
		watchers.append(self_obj)
	if on == "ENTERS_BATTLEFIELD" and subject != null and self_obj != null and subject.object_id == self_obj.object_id:
		_riot_on_enter(engine, subject)
	for w in watchers:
		var same: bool = self_obj != null and w.object_id == self_obj.object_id
		for ab in _triggered(engine, w, on):
			if _scope_ok(engine, ab, w, subject, same):
				_put_trigger(engine, w, ab, ctx)
				## Wayta (CR 603.2d): a creature you control being dealt damage makes the trigger happen once more.
				if on == "DAMAGED" and subject != null and subject.controller_id == w.controller_id and _doubles_damage_triggers(engine, w.controller_id):
					_put_trigger(engine, w, ab, ctx)


func _scope_ok(engine: RulesEngine, ab: Ability, watcher: GameObject, subject: GameObject, same: bool) -> bool:
	var scope := str(ab.trigger.get("scope", "SELF"))
	if scope == "SELF":
		return same
	## "When enchanted creature dies": the Aura watches what it is attached to.
	if scope == "ENCHANTED":
		return subject != null and (watcher.attached_to == subject.object_id or watcher.aura_host_left == subject.object_id)
	if scope == "OTHER" and same:
		return false
	if scope != "OTHER" and scope != "ANY":
		return false
	## Evolve (CR 702.100): the creature that entered has greater power or toughness than the watcher.
	if bool(ab.trigger.get("greater_pt", false)):
		if engine.power_of(subject) <= engine.power_of(watcher) and engine.toughness_of(subject) <= engine.toughness_of(watcher):
			return false
	var f: Variant = ab.trigger.get("filter", {})
	if f is Dictionary and not (f as Dictionary).is_empty():
		return Query._matches(subject, watcher, f)
	return true


func _ctx_for(engine: RulesEngine, obj: GameObject) -> Dictionary:
	return {
		object_id = obj.object_id,
		player_id = obj.controller_id,
		power = engine.power_of(obj),
		toughness = engine.toughness_of(obj),
	}


func _battlefield(engine: RulesEngine) -> Array:
	var out: Array = []
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.definition is CardDefinition:
			out.append(o)
	return out


func _triggered(engine: RulesEngine, src: GameObject, on: String) -> Array:
	var out: Array = []
	for a in _abilities_of(engine, src):
		var ab := a as Ability
		if ab != null and ab.kind == &"TRIGGERED" and not ab.unparsed and str(ab.trigger.get("on", "")) == on:
			out.append(ab)
	return out


func _abilities_of(engine: RulesEngine, src: GameObject) -> Array:
	if engine.layers != null:
		return engine.layers.abilities_for(engine.state, src)
	if src == null or not (src.definition is CardDefinition):
		return []
	var out: Array = []
	for a in (src.definition as CardDefinition).abilities:
		if a is Ability and not (a as Ability).granted:
			out.append(a)
	return out


## Puts the trigger on the stack. There is no target picker for triggers yet: each slot is filled by
## TargetingManager.auto_pick (harmful at the opponent, helpful at you). A trigger whose required
## target has no legal choice is not put on the stack (CR 603.3d).
func _put_trigger(engine: RulesEngine, source: GameObject, ab: Ability, ctx: Dictionary = {}) -> void:
	## "Unless it has a ... counter" gates: renown (once ever), undying / persist (checked on what it had).
	var unless := str(ab.trigger.get("unless_counter", ""))
	if unless != "":
		var had: Dictionary = ctx.get("counters", source.counters) if ab.trigger.get("on", "") == "DIES" else source.counters
		if int(had.get(unless, 0)) > 0:
			return
	if not _intervening_if(engine, source, ab.trigger):
		return
	## "..., if it had counters on it, ...": what it had as it left (last known information).
	if bool(ab.trigger.get("if_had_counters", false)):
		var had_any := false
		for cn in (ctx.get("counters", {}) as Dictionary).values():
			if int(cn) > 0:
				had_any = true
		if not had_any:
			return
	var entry := StackEntry.new()
	entry.stack_id = engine.state.next_stack_id
	entry.kind = StackEntry.Kind.TRIGGERED
	entry.object_id = 0
	entry.source_id = source.object_id
	entry.controller_id = source.controller_id
	entry.ability_id = ab.ability_id
	entry.effects = ab.effects.duplicate()
	entry.ctx = ctx.duplicate()
	var hostile := TargetingManager.effects_hostile(ab.effects)
	for slot in ab.targets:
		if not (slot is Dictionary) or engine.targeting == null:
			continue
		## A person chooses their own trigger targets when there is a real choice (more than one legal target, or the
		## "you may" kind): that is asked when the trigger resolves (AbilityExecutor.pick_trigger_targets).
		if engine.interactive_seats.has(source.controller_id):
			var legal: Array = engine.targeting.legal_ids(engine, slot, source.object_id)
			if legal.size() > 1 or (legal.size() == 1 and bool((slot as Dictionary).get("optional", false))):
				var pend: Array = entry.ctx.get("pick_slots", [])
				pend.append(slot)
				entry.ctx["pick_slots"] = pend
				continue
		var tid := engine.targeting.auto_pick(engine, slot, source.object_id, source.controller_id,
			TargetingManager.slot_hostile(slot, hostile), entry.targets)
		if tid >= 0:
			entry.targets.append(tid)
		elif not bool((slot as Dictionary).get("optional", false)):
			return
	if bool(ab.trigger.get("once_per_turn", false)):
		if int(source.trigger_turns.get(str(ab.ability_id), -1)) == engine.state.turn_number:
			return
		source.trigger_turns[str(ab.ability_id)] = engine.state.turn_number
	engine.state.next_stack_id += 1
	(engine.state.stack as MagicStack).push(entry)
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, source.controller_id, {
		object_id = source.object_id,
		stack_id = entry.stack_id,
		trigger = true,
	})


## Riot (CR 702.136): "enters with your choice of a +1/+1 counter or haste", from the card or from a static
## "nontoken creatures you control have riot".
func _riot_on_enter(engine: RulesEngine, obj: GameObject) -> void:
	if not engine.is_creature_now(obj) or not (obj.definition is CardDefinition):
		return
	var def := obj.definition as CardDefinition
	var has_riot := RegEx.create_from_string("(?im)^riot\\b").search(def.oracle_text) != null
	if not has_riot and not obj.is_token:
		for o in _battlefield(engine):
			if o.controller_id == obj.controller_id and o.definition is CardDefinition \
					and (o.definition as CardDefinition).oracle_text.to_lower().contains("nontoken creatures you control have riot"):
				has_riot = true
				break
	if not has_riot:
		return
	var fx := AbilityEffect.new()
	fx.kind = &"RIOT"
	fx.params = {}
	engine.put_synthetic(null, obj.controller_id, [fx], {"object_id": obj.object_id}, obj.object_id)


func _doubles_damage_triggers(engine: RulesEngine, pid: int) -> bool:
	for o in _battlefield(engine):
		if o.controller_id == pid and o.definition is CardDefinition \
				and (o.definition as CardDefinition).oracle_text.to_lower().contains("being dealt damage causes a triggered ability of a permanent you control to trigger, that ability triggers an additional time"):
			return true
	return false



## Intervening "if" clauses (CR 603.4) on a trigger: checked as it would go on the stack.
##   if_gift                  the gift was promised for this permanent (CR 702.174)
##   attack_power_min n       you attacked with creatures with total power n or more this combat (pack tactics)
##   if_controls_commander    you control your commander (lieutenant)
##   if_defender_most_life    it's attacking the player with the most life or tied (Scourge of the Throne)
func _intervening_if(engine: RulesEngine, source: GameObject, trig: Dictionary) -> bool:
	if bool(trig.get("if_gift", false)) and not source.gift_promised:
		return false
	if trig.has("attack_power_min"):
		var total := 0
		if engine.state.combat is CombatState:
			for aid in (engine.state.combat as CombatState).attacker_ids:
				var a: GameObject = engine.state.objects.get(int(aid))
				if a != null and a.controller_id == source.controller_id:
					total += engine.power_of(a)
		if total < int(trig["attack_power_min"]):
			return false
	if bool(trig.get("if_controls_commander", false)):
		var mine := false
		for cid in engine.state.players[source.controller_id].commander_ids:
			var c: GameObject = engine.state.objects.get(int(cid))
			if c != null and c.zone == EngineEnums.ZoneId.BATTLEFIELD and c.controller_id == source.controller_id:
				mine = true
		if not mine:
			return false
	if bool(trig.get("if_harnessed", false)) and not bool(source.marks.get("harnessed", false)):
		return false
	if bool(trig.get("if_defender_most_life", false)) and not engine.executor.defender_has_most_life(engine, source):
		return false
	## Training (CR 702.149): it attacks along with a creature with greater power.
	if bool(trig.get("with_greater_power", false)):
		var bigger := false
		if engine.state.combat is CombatState:
			for aid2 in (engine.state.combat as CombatState).attacker_ids:
				var o2: GameObject = engine.state.objects.get(int(aid2))
				if o2 != null and o2.object_id != source.object_id and o2.controller_id == source.controller_id and engine.power_of(o2) > engine.power_of(source):
					bigger = true
		if not bigger:
			return false
	## Generic "if" conditions on a trigger (read by OracleIr): life gained this turn, monarch, more creatures ...
	if trig.has("condition") and not engine.layers.condition_met(engine.state, source, trig["condition"]):
		return false
	return true


## The spells `caster_id` cast this turn (each an Array of lower-case types).
func engine_ref_spells(_source: GameObject, caster_id: int) -> Array:
	var eng := _eng_ref
	if eng == null or caster_id < 0 or caster_id >= eng.state.players.size():
		return []
	return eng.state.players[caster_id].spells_this_turn


var _eng_ref: RulesEngine = null


## Things that happen as a permanent enters (not "when ~ enters" triggers of its own text):
##   gift: a promised gift on a permanent spell is given as it enters (CR 702.174b)
##   Sagas: a lore counter, or the chapter its controller picks for read ahead (CR 714.3a, 714.3d)
##   Probing Telepathy: a creature's own enter trigger is copied for an opponent who has it
func _on_permanent_entered(engine: RulesEngine, obj: GameObject, from_zone: int) -> void:
	if not (obj.definition is CardDefinition) or obj.face_down:
		return
	var def := obj.definition as CardDefinition
	if obj.gift_promised and from_zone == EngineEnums.ZoneId.STACK and def.kw().has("gift"):
		var gfx := AbilityEffect.new()
		gfx.kind = &"GIFT"
		gfx.params = {"kind": str(def.kw().gift)}
		engine.put_synthetic(obj, obj.controller_id, [gfx], {})
	if def.type_line.contains("Saga"):
		if def.kw().has("read_ahead"):
			var rfx := AbilityEffect.new()
			rfx.kind = &"READ_AHEAD"
			rfx.params = {"final": def.saga_final_chapter()}
			engine.put_synthetic(obj, obj.controller_id, [rfx], {})
		else:
			add_lore(engine, obj, 1)
	if engine.is_creature_now(obj):
		_probing_telepathy(engine, obj)


## Adds `n` lore counters to a Saga (or sets them, for read ahead) and triggers each chapter reached (CR 714.2c).
func add_lore(engine: RulesEngine, saga: GameObject, n: int, set_exact: bool = false) -> void:
	if saga == null or saga.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var before := int(saga.counters.get("lore", 0))
	var after := n if set_exact else before + n
	saga.counters["lore"] = after
	var from_ch := after if set_exact else before + 1
	for ab in _triggered(engine, saga, "CHAPTER"):
		var chs: Array = ab.trigger.get("chapters", [])
		for c in range(from_ch, after + 1):
			if chs.has(c):
				_put_trigger(engine, saga, ab, {player_id = saga.controller_id, chapter = c})


## Triggers about a player rather than an object: "whenever you win a clash".
func fire_player_event(engine: RulesEngine, on: String, pid: int) -> void:
	for src in _battlefield(engine):
		if src.controller_id != pid:
			continue
		for ab in _triggered(engine, src, on):
			_put_trigger(engine, src, ab, {player_id = pid})


## "When enchanted creature dies" for an Aura already put into the graveyard by state-based actions.
func _enchanted_died(engine: RulesEngine, dead_id: int, ctx: Dictionary) -> void:
	for pid in engine.state.players.size():
		var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, pid)
		if gy == null:
			continue
		for gid in gy.object_ids.duplicate():
			var aura: GameObject = engine.state.objects.get(gid)
			if aura == null or aura.aura_host_left != dead_id or not (aura.definition is CardDefinition):
				continue
			for a in (aura.definition as CardDefinition).abilities:
				var ab := a as Ability
				if ab != null and ab.kind == &"TRIGGERED" and str(ab.trigger.get("on", "")) == "DIES" and str(ab.trigger.get("scope", "")) == "ENCHANTED":
					_put_trigger(engine, aura, ab, ctx)


## Probing Telepathy (Aboleth Spawn): "Whenever a creature entering under an opponent's control causes a triggered
## ability of that creature to trigger, you may copy that ability." The copy is yours; its targets are picked for you.
func _probing_telepathy(engine: RulesEngine, entered: GameObject) -> void:
	var own: Array = []
	for ab in _triggered(engine, entered, "ENTERS_BATTLEFIELD"):
		if str(ab.trigger.get("scope", "SELF")) == "SELF":
			own.append(ab)
	if own.is_empty():
		return
	for w in _battlefield(engine):
		if w.controller_id == entered.controller_id or not (w.definition is CardDefinition):
			continue
		if not (w.definition as CardDefinition).oracle_text.to_lower().contains("whenever a creature entering under an opponent's control causes a triggered ability of that creature to trigger"):
			continue
		for ab2 in own:
			var ghost := GameObject.new()
			ghost.object_id = entered.object_id
			ghost.definition = entered.definition
			ghost.controller_id = w.controller_id
			ghost.owner_id = w.controller_id
			ghost.zone = EngineEnums.ZoneId.BATTLEFIELD
			if _intervening_if(engine, entered, (ab2 as Ability).trigger):
				_put_trigger_as(engine, ghost, ab2 as Ability, w.controller_id)


func _put_trigger_as(engine: RulesEngine, ghost: GameObject, ab: Ability, controller: int) -> void:
	var entry := StackEntry.new()
	entry.stack_id = engine.state.next_stack_id
	entry.kind = StackEntry.Kind.TRIGGERED
	entry.source_id = ghost.object_id
	entry.controller_id = controller
	entry.ability_id = ab.ability_id
	entry.effects = ab.effects.duplicate()
	entry.ctx = {player_id = controller, copy = true}
	var hostile := TargetingManager.effects_hostile(ab.effects)
	for slot in ab.targets:
		if not (slot is Dictionary) or engine.targeting == null:
			continue
		var tid := engine.targeting.auto_pick(engine, slot, 0, controller, TargetingManager.slot_hostile(slot, hostile), entry.targets)
		if tid >= 0:
			entry.targets.append(tid)
		elif not bool((slot as Dictionary).get("optional", false)):
			return
	engine.state.next_stack_id += 1
	(engine.state.stack as MagicStack).push(entry)
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, controller, {object_id = ghost.object_id, stack_id = entry.stack_id, trigger = true, copy = true})



## Once blockers are declared: "whenever this creature attacks and isn't blocked" (frenzy, CR 509.1h).
func _fire_unblocked(engine: RulesEngine) -> void:
	if not (engine.state.combat is CombatState):
		return
	var cs := engine.state.combat as CombatState
	if not cs.blocks_declared:
		return
	var key := "nb_%d" % engine.state.turn_number
	if _blocked_seen.has(key):
		return
	_blocked_seen[key] = true
	for aid in cs.attacker_ids:
		var b: Variant = cs.blockers.get(aid, [])
		var a: GameObject = engine.state.objects.get(int(aid))
		if a != null and a.zone == EngineEnums.ZoneId.BATTLEFIELD and (not (b is Array) or (b as Array).is_empty()):
			var c := _ctx_for(engine, a)
			c["defender"] = engine.defender_of(a.object_id)
			_fire(engine, "NOT_BLOCKED", a, a, c)


## Triggers about one object that aren't zone changes: "when ~ becomes monstrous", "when ~ exploits a creature" ...
func fire_object_event(engine: RulesEngine, on: String, obj: GameObject, ctx: Dictionary) -> void:
	for ab in _triggered(engine, obj, on):
		_put_trigger(engine, obj, ab, ctx)


## Delayed effects whose step has come: "at the beginning of the next end step, sacrifice it". One that was made earlier in
## this same step waits for the next one; "your" steps wait for the controller's turn.
func _fire_delayed(engine: RulesEngine, step_name: String, active: int) -> void:
	var st := engine.state
	var keep: Array = []
	for raw in st.delayed:
		var d: Dictionary = raw
		var due := str(d.get("step", "")) == step_name \
			and (int(d.get("turn", 0)) < st.turn_number or int(d.get("step_index", 0)) < int(st.step)) \
			and (str(d.get("whose", "ANY")) != "YOURS" or active == int(d.get("controller", -1)))
		if not due:
			keep.append(d)
			continue
		var fx := AbilityEffect.new()
		fx.kind = &"DELAYED_ACT"
		fx.params = {"action": str(d.get("action", "")), "object_id": int(d.get("object_id", 0))}
		engine.put_synthetic(null, int(d.get("controller", active)), [fx], {}, int(d.get("object_id", 0)))
	st.delayed = keep


## "Whenever an opponent activates an ability of an artifact, creature, or land" (Harsh Mentor): a non-mana ability was put
## on the stack by `activator`. The trigger's `types` (if any) limit which permanents count.
func on_ability_activated(engine: RulesEngine, source: GameObject, activator: int) -> void:
	if source == null or not (source.definition is CardDefinition):
		return
	var tl := (source.definition as CardDefinition).type_line.to_lower()
	for src in _battlefield(engine):
		if src.controller_id == activator:
			continue
		for ab in _triggered(engine, src, "OPP_ACTIVATES"):
			var types: Array = ab.trigger.get("types", [])
			var hit := types.is_empty()
			for t in types:
				if tl.contains(str(t)):
					hit = true
			if hit:
				_put_trigger(engine, src, ab, {player_id = activator, object_id = source.object_id})
