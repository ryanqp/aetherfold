class_name Query
extends RefCounted

static func count_objects(state: GameState, source: GameObject, spec: Dictionary) -> int:
	if spec.is_empty():
		return 0
	var zone_id := _zone_id(str(spec.get("zone", "BATTLEFIELD")))
	var owner_id := EngineIds.NONE
	if not ZoneManager.is_shared(zone_id) and source != null:
		owner_id = source.controller_id
	var zone: Zone = state.zones.get_zone(zone_id, owner_id)
	if zone == null:
		return 0
	var n := 0
	for oid in zone.object_ids:
		var obj: GameObject = state.objects.get(oid)
		if obj != null and _matches(obj, source, spec):
			n += 1
	return n


static func _matches(obj: GameObject, source: GameObject, spec: Dictionary) -> bool:
	var ctrl := str(spec.get("controller", "ANY"))
	if ctrl == "SOURCE_CONTROLLER" and source != null and obj.controller_id != source.controller_id:
		return false
	if ctrl == "OPPONENT" and source != null and obj.controller_id == source.controller_id:
		return false
	if ctrl == "SOURCE_OWNER" and source != null and obj.owner_id != source.owner_id:
		return false
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	var type_line := def.type_line if def else ""
	var type_need := str(spec.get("type", "")).strip_edges()
	if type_need != "" and type_line.to_lower().find(type_need.to_lower()) == -1:
		return false
	var not_type := str(spec.get("not_type", "")).strip_edges()
	if not_type != "" and type_line.to_lower().find(not_type.to_lower()) >= 0:
		return false
	var sub := str(spec.get("subtype", "")).strip_edges()
	if sub == "$chosen":
		sub = source.chosen_type if source != null else ""
		if sub == "":
			return false
	if sub != "" and type_line.find(sub) == -1 and not _is_changeling(def, type_line):
		return false
	var not_sub := str(spec.get("not_subtype", "")).strip_edges()
	if not_sub != "" and _subtype_words(type_line).has(not_sub):
		return false
	## Any of several types ("artifact or enchantment").
	var any_types: Variant = spec.get("type_any", [])
	if any_types is Array and not (any_types as Array).is_empty():
		var hit := false
		for t in any_types:
			if type_line.to_lower().find(str(t).to_lower()) >= 0:
				hit = true
				break
		if not hit:
			return false
	## Any of several subtypes ("Plains, Island, Swamp or Mountain").
	var any_subs: Variant = spec.get("subtype_any", [])
	if any_subs is Array and not (any_subs as Array).is_empty():
		var hit2 := false
		for t2 in any_subs:
			if _subtype_words(type_line).has(str(t2)):
				hit2 = true
				break
		if not hit2:
			return false
	if bool(spec.get("basic_land", false)) and not type_line.begins_with("Basic Land"):
		return false
	if bool(spec.get("nontoken", false)) and obj.is_token:
		return false
	if bool(spec.get("token", false)) and not obj.is_token:
		return false
	if bool(spec.get("other", false)) and source != null and obj.object_id == source.object_id:
		return false
	if bool(spec.get("tapped", false)) and not obj.tapped:
		return false
	return true


## Changeling (CR 702.73): a creature with it is every creature type.
static func _is_changeling(def: CardDefinition, type_line: String) -> bool:
	if def == null or not type_line.contains("Creature"):
		return false
	return def.keywords.has("Changeling") or def.oracle_text.to_lower().begins_with("changeling")


static func _subtype_words(type_line: String) -> PackedStringArray:
	var parts := type_line.split("—")
	if parts.size() < 2:
		return PackedStringArray()
	return PackedStringArray(parts[parts.size() - 1].strip_edges().split(" ", false))


static func _zone_id(name: String) -> int:
	match name.to_upper():
		"LIBRARY":
			return EngineEnums.ZoneId.LIBRARY
		"HAND":
			return EngineEnums.ZoneId.HAND
		"GRAVEYARD":
			return EngineEnums.ZoneId.GRAVEYARD
		"EXILE":
			return EngineEnums.ZoneId.EXILE
		"STACK":
			return EngineEnums.ZoneId.STACK
		"COMMAND":
			return EngineEnums.ZoneId.COMMAND
		_:
			return EngineEnums.ZoneId.BATTLEFIELD
