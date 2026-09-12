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
	if ctrl == "SOURCE_OWNER" and source != null and obj.owner_id != source.owner_id:
		return false
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	var type_line := def.type_line if def else ""
	var type_need := str(spec.get("type", "")).strip_edges()
	if type_need != "" and type_line.to_lower().find(type_need.to_lower()) == -1:
		return false
	var sub := str(spec.get("subtype", "")).strip_edges()
	if sub != "" and type_line.find(sub) == -1:
		return false
	return true


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
