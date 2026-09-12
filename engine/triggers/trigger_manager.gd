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
		var sdef := src.definition as CardDefinition
		for a in sdef.abilities:
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
	(engine.state.stack as MagicStack).push(entry)
