class_name TriggerManager
extends RefCounted

func on_spell_cast(engine: RulesEngine, spell_obj: GameObject, caster_id: int) -> void:
	if spell_obj == null:
		return
	var def: CardDefinition = spell_obj.definition as CardDefinition if spell_obj.definition is CardDefinition else null
	var spell_types: PackedStringArray = PackedStringArray()
	if def != null:
		if def.is_instant():
			spell_types.append("instant")
		if def.is_sorcery():
			spell_types.append("sorcery")
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var src: GameObject = engine.state.objects.get(oid)
		if src == null or src.definition == null or not (src.definition is CardDefinition):
			continue
		for a in _abilities_of(engine, src):
			if not (a is Ability):
				continue
			var ab := a as Ability
			if ab.kind != &"TRIGGERED" or ab.unparsed:
				continue
			if not _matches_spell_cast(ab, src, caster_id, spell_types):
				continue
			_put_trigger(engine, src, ab)


func _matches_spell_cast(ab: Ability, source: GameObject, caster_id: int, spell_types: PackedStringArray) -> bool:
	var trig: Dictionary = ab.trigger
	if str(trig.get("on", "")) != "SPELL_CAST":
		return false
	var filt: Variant = trig.get("filter", {})
	if not (filt is Dictionary):
		return true
	var f: Dictionary = filt
	var ctrl := str(f.get("controller", "ANY"))
	if ctrl == "SOURCE_CONTROLLER" and source.controller_id != caster_id:
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
	return true


## "When ~ enters": the new permanent's own ENTERS_BATTLEFIELD abilities go on the stack (CR 603.6a).
func on_enter_battlefield(engine: RulesEngine, obj: GameObject) -> void:
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	for a in _abilities_of(engine, obj):
		var ab := a as Ability
		if ab == null or ab.kind != &"TRIGGERED" or ab.unparsed:
			continue
		if str(ab.trigger.get("on", "")) != "ENTERS_BATTLEFIELD":
			continue
		_put_trigger(engine, obj, ab)


func on_combat_damage_to_player(engine: RulesEngine, source: GameObject, _defender_id: int, amount: int) -> void:
	if source == null or amount <= 0:
		return
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids:
		var watcher: GameObject = engine.state.objects.get(oid)
		if watcher == null:
			continue
		for a in _abilities_of(engine, watcher):
			if not (a is Ability):
				continue
			var ab := a as Ability
			if ab.kind != &"TRIGGERED" or ab.unparsed:
				continue
			if str(ab.trigger.get("on", "")) != "COMBAT_DAMAGE_TO_PLAYER":
				continue
			if watcher.object_id != source.object_id:
				continue
			_put_trigger(engine, watcher, ab)


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


func _put_trigger(engine: RulesEngine, source: GameObject, ab: Ability) -> void:
	var entry := StackEntry.new()
	entry.stack_id = engine.state.next_stack_id
	engine.state.next_stack_id += 1
	entry.kind = StackEntry.Kind.TRIGGERED
	entry.object_id = 0
	entry.source_id = source.object_id
	entry.controller_id = source.controller_id
	entry.ability_id = ab.ability_id
	entry.effects = ab.effects.duplicate()
	## No target picker for triggers yet: harmful ones go at the opponent, helpful ones at the controller.
	var hostile := TargetingManager.effects_hostile(ab.effects)
	for slot in ab.targets:
		if slot is Dictionary and engine.targeting != null:
			var tid := engine.targeting.auto_pick(engine, slot, source.object_id, source.controller_id, hostile)
			if tid >= 0:
				entry.targets.append(tid)
	(engine.state.stack as MagicStack).push(entry)
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, source.controller_id, {
		object_id = source.object_id,
		stack_id = entry.stack_id,
		trigger = true,
	})
