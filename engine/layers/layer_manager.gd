class_name LayerManager
extends RefCounted

## CR 613. Printed values stay on CardDefinition. This snapshot is the current characteristics.

func snapshot(state: GameState, obj: GameObject) -> Dictionary:
	var printed_p := 0
	var printed_t := 0
	var type_line := ""
	var keywords := PackedStringArray()
	var subtypes := PackedStringArray()
	if obj != null and obj.definition is CardDefinition:
		var def := obj.definition as CardDefinition
		printed_p = int(def.power) if def.power.is_valid_int() else 0
		printed_t = int(def.toughness) if def.toughness.is_valid_int() else 0
		type_line = def.type_line
		keywords = def.keywords.duplicate()
		subtypes = _subtypes_of(def.type_line)
	var power := printed_p
	var toughness := printed_t
	var subtype_sets: Array = []
	var pt_sets: Array = []
	var mod_p := 0
	var mod_t := 0
	if state != null:
		for e in state.effects:
			if not (e is ContinuousEffect):
				continue
			var fx := e as ContinuousEffect
			if not _affects(state, fx, obj):
				continue
			if not fx.set_subtypes.is_empty():
				subtype_sets.append(fx)
			if fx.sets_power or fx.sets_toughness:
				pt_sets.append(fx)
			mod_p += fx.power
			mod_t += fx.toughness
			for kw in fx.add_keywords:
				keywords.append(kw)
	## Static abilities of permanents ("creatures you control get +1/+1", equipment). CR 613.4c, 613.1f.
	var statics := _static_mods(state, obj)
	mod_p += int(statics["power"])
	mod_t += int(statics["toughness"])
	for kw in statics["keywords"]:
		keywords.append(str(kw))
	if not subtype_sets.is_empty():
		subtype_sets.sort_custom(func(a, b) -> bool:
			return (a as ContinuousEffect).timestamp < (b as ContinuousEffect).timestamp
		)
		subtypes = (subtype_sets[subtype_sets.size() - 1] as ContinuousEffect).set_subtypes.duplicate()
		type_line = _with_subtypes(type_line, subtypes)
	if not pt_sets.is_empty():
		pt_sets.sort_custom(func(a, b) -> bool:
			return (a as ContinuousEffect).timestamp < (b as ContinuousEffect).timestamp
		)
		var last := pt_sets[pt_sets.size() - 1] as ContinuousEffect
		if last.sets_power:
			power = last.set_power
		if last.sets_toughness:
			toughness = last.set_toughness
	power += mod_p
	toughness += mod_t
	if obj != null and _is_creature_line(type_line):
		power += _counter_delta(obj)
		toughness += _counter_delta(obj)
	return {
		power = power,
		toughness = toughness,
		printed_power = printed_p,
		printed_toughness = printed_t,
		type_line = type_line,
		subtypes = subtypes,
		keywords = keywords,
	}


func power(state: GameState, obj: GameObject) -> int:
	return int(snapshot(state, obj).get("power", 0))


func has_subtype(state: GameState, obj: GameObject, subtype_name: String) -> bool:
	var subs: Variant = snapshot(state, obj).get("subtypes", PackedStringArray())
	if subs is PackedStringArray:
		return (subs as PackedStringArray).has(subtype_name)
	return false


func has_keyword(state: GameState, obj: GameObject, keyword: String) -> bool:
	var kws: Variant = snapshot(state, obj).get("keywords", PackedStringArray())
	if not (kws is PackedStringArray):
		return false
	var want := keyword.to_lower()
	for kw in kws:
		if str(kw).to_lower() == want:
			return true
	return false


func abilities_for(state: GameState, obj: GameObject) -> Array:
	var out: Array = []
	if obj == null or not (obj.definition is CardDefinition):
		return out
	var gained := {}
	if state != null:
		for e in state.effects:
			if not (e is ContinuousEffect):
				continue
			var fx := e as ContinuousEffect
			if not _affects(state, fx, obj):
				continue
			for id in fx.gain_ability_ids:
				gained[str(id)] = true
	for a in (obj.definition as CardDefinition).abilities:
		if not (a is Ability):
			continue
		var ab := a as Ability
		if ab.unparsed:
			continue
		if ab.granted:
			if gained.has(str(ab.ability_id)):
				out.append(ab)
		else:
			out.append(ab)
	return out


## Total +P/+T and granted keywords from static abilities on the battlefield that apply to `obj`.
func _static_mods(state: GameState, obj: GameObject) -> Dictionary:
	var mods := {"power": 0, "toughness": 0, "keywords": []}
	if state == null or obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD or state.zones == null:
		return mods
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return mods
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or ab.unparsed or ab.static_spec.is_empty():
				continue
			var spec: Dictionary = ab.static_spec
			if not (spec.has("power") or spec.has("toughness") or spec.has("keywords")):
				continue
			if not static_applies(state, src, spec, obj):
				continue
			mods["power"] = int(mods["power"]) + int(spec.get("power", 0))
			mods["toughness"] = int(mods["toughness"]) + int(spec.get("toughness", 0))
			var kws: Variant = spec.get("keywords", [])
			if kws is Array:
				for kw in kws:
					(mods["keywords"] as Array).append(str(kw))
	return mods


## Does the static ability `spec` of permanent `src` apply to `obj`?
func static_applies(state: GameState, src: GameObject, spec: Dictionary, obj: GameObject) -> bool:
	var cond: Variant = spec.get("condition", {})
	if cond is Dictionary and (cond as Dictionary).has("controls"):
		var need := int((cond as Dictionary).get("min", 1))
		if Query.count_objects(state, src, (cond as Dictionary)["controls"]) < need:
			return false
	var scope := str(spec.get("scope", "SELF"))
	match scope:
		"SELF":
			return src.object_id == obj.object_id
		"EQUIPPED":
			if src.attached_to != obj.object_id:
				return false
			return obj.zone == EngineEnums.ZoneId.BATTLEFIELD and _is_creature_line(_type_line_of(obj))
		"OTHERS":
			if src.object_id == obj.object_id:
				return false
		"ALL":
			pass
		_:
			return false
	var q: Variant = spec.get("query", {})
	if q is Dictionary and not (q as Dictionary).is_empty():
		return Query._matches(obj, src, q)
	return true


## "This creature can't attack or block unless you control seven or more lands."
func combat_restricted(state: GameState, obj: GameObject) -> bool:
	if obj == null or not (obj.definition is CardDefinition):
		return false
	for a in (obj.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("cant_attack_block_unless"):
			continue
		var need: Dictionary = ab.static_spec["cant_attack_block_unless"]
		if need.has("lands"):
			var lands := Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER", "type": "land"})
			if lands < int(need["lands"]):
				return true
		if need.has("permanents"):
			var perms := Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER"})
			if perms < int(need["permanents"]):
				return true
	return false


func _type_line_of(obj: GameObject) -> String:
	return (obj.definition as CardDefinition).type_line if obj.definition is CardDefinition else ""


func clear_until_eot(state: GameState) -> void:
	var kept: Array = []
	for e in state.effects:
		if e is ContinuousEffect and (e as ContinuousEffect).until_eot:
			continue
		kept.append(e)
	state.effects = kept


func _affects(state: GameState, fx: ContinuousEffect, obj: GameObject) -> bool:
	if obj == null:
		return false
	if fx.object_ids.is_empty() and fx.query.is_empty():
		return true
	if fx.object_ids.has(obj.object_id):
		return true
	if not fx.query.is_empty():
		var source: GameObject = state.objects.get(fx.source_id) as GameObject
		return Query._matches(obj, source, fx.query)
	return false


func _counter_delta(obj: GameObject) -> int:
	return int(obj.counters.get("+1/+1", 0)) - int(obj.counters.get("-1/-1", 0))


func _is_creature_line(type_line: String) -> bool:
	return type_line.contains("Creature")


func _subtypes_of(type_line: String) -> PackedStringArray:
	var parts := type_line.split("—")
	if parts.size() < 2:
		return PackedStringArray()
	var right := parts[parts.size() - 1].strip_edges()
	if right == "":
		return PackedStringArray()
	return PackedStringArray(right.split(" ", false))


func _with_subtypes(type_line: String, subtypes: PackedStringArray) -> String:
	var parts := type_line.split("—")
	var left := parts[0].strip_edges() if not parts.is_empty() else type_line
	if subtypes.is_empty():
		return left
	return "%s — %s" % [left, " ".join(subtypes)]
