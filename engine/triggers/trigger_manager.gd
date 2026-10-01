class_name TriggerManager
extends RefCounted

## Triggered abilities (CR 603): "when / whenever / at the beginning of". The engine reads each new
## log event (RulesEngine.process_zone_events) and calls on_event; a matching trigger goes on the stack.
##
## An ability's `trigger` dictionary:
##   on      ENTERS_BATTLEFIELD, DIES, ATTACKS, DAMAGED, LIFE_GAINED, COMBAT_DAMAGE_TO_PLAYER,
##           BEGIN_STEP, SPELL_CAST
##   scope   SELF (default), OTHER, ANY (self or another), YOU (LIFE_GAINED / ATTACKS: it's about you)
##   filter  a Query spec the subject must match, read from the watcher's side ("you control" = the
##           watcher's controller)
##   step    UPKEEP, BEGIN_COMBAT or END (BEGIN_STEP);  whose  YOURS, OPPONENT or EACH


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
	for src in _battlefield(engine):
		for ab in _triggered(engine, src, "SPELL_CAST"):
			if _matches_spell_cast(ab, src, caster_id, spell_types, spell_obj):
				_put_trigger(engine, src, ab, ctx)


func _matches_spell_cast(ab: Ability, source: GameObject, caster_id: int, spell_types: PackedStringArray, spell_obj: GameObject) -> bool:
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
	_fire(engine, "COMBAT_DAMAGE_TO_PLAYER", source, source, ctx)


## Reads one log event. Called for every event, in order, by RulesEngine.process_zone_events.
func on_event(engine: RulesEngine, e: GameEvent) -> void:
	var p: Dictionary = e.payload
	match e.type:
		EngineEnums.EventType.ZONE_CHANGE:
			_on_zone_change(engine, p)
		EngineEnums.EventType.ATTACK:
			_on_attack(engine, e)
		EngineEnums.EventType.STEP_BEGIN:
			_on_step_begin(engine, int(p.get("step", -1)), e.player_id)
		EngineEnums.EventType.DAMAGE:
			if p.has("to_object") and int(p.get("amount", 0)) > 0:
				var hurt: GameObject = engine.state.objects.get(int(p.get("to_object", 0)))
				if hurt != null and hurt.zone == EngineEnums.ZoneId.BATTLEFIELD:
					var ctx := _ctx_for(engine, hurt)
					ctx["amount"] = int(p.get("amount", 0))
					_fire(engine, "DAMAGED", hurt, hurt, ctx)
		EngineEnums.EventType.LIFE_CHANGE:
			if bool(p.get("gain", false)):
				_on_life_gained(engine, int(p.get("to_player", e.player_id)), int(p.get("amount", 0)))


func _on_zone_change(engine: RulesEngine, p: Dictionary) -> void:
	var from_z := int(p.get("from_zone", -1))
	var to_z := int(p.get("to_zone", -1))
	if to_z == EngineEnums.ZoneId.BATTLEFIELD:
		var obj: GameObject = engine.state.objects.get(int(p.get("to_id", 0)))
		if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
			_fire(engine, "ENTERS_BATTLEFIELD", obj, obj, _ctx_for(engine, obj))
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
		}
		if to_z == EngineEnums.ZoneId.GRAVEYARD:
			_fire(engine, "DIES", ghost, self_obj, ctx)


func _on_attack(engine: RulesEngine, e: GameEvent) -> void:
	var attackers: Array = e.payload.get("attackers", [])
	for aid in attackers:
		var atk: GameObject = engine.state.objects.get(int(aid))
		if atk != null and atk.zone == EngineEnums.ZoneId.BATTLEFIELD:
			_fire(engine, "ATTACKS", atk, atk, _ctx_for(engine, atk))
	if attackers.is_empty():
		return
	for src in _battlefield(engine):
		if src.controller_id != e.player_id:
			continue
		for ab in _triggered(engine, src, "ATTACKS"):
			if str(ab.trigger.get("scope", "SELF")) == "YOU":
				_put_trigger(engine, src, ab, {player_id = e.player_id})


func _on_step_begin(engine: RulesEngine, step: int, active: int) -> void:
	var step_name := ""
	match step:
		EngineEnums.Step.UPKEEP:
			step_name = "UPKEEP"
		EngineEnums.Step.BEGIN_COMBAT:
			step_name = "BEGIN_COMBAT"
		EngineEnums.Step.END:
			step_name = "END"
		_:
			return
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


func _on_life_gained(engine: RulesEngine, player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	for src in _battlefield(engine):
		if src.controller_id != player_id:
			continue
		for ab in _triggered(engine, src, "LIFE_GAINED"):
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
	for w in watchers:
		var same: bool = self_obj != null and w.object_id == self_obj.object_id
		for ab in _triggered(engine, w, on):
			if _scope_ok(ab, w, subject, same):
				_put_trigger(engine, w, ab, ctx)


func _scope_ok(ab: Ability, watcher: GameObject, subject: GameObject, same: bool) -> bool:
	var scope := str(ab.trigger.get("scope", "SELF"))
	if scope == "SELF":
		return same
	if scope == "OTHER" and same:
		return false
	if scope != "OTHER" and scope != "ANY":
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
