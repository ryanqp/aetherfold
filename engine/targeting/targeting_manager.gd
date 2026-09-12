class_name TargetingManager
extends RefCounted

const PLAYER_ID_BASE := 1000000


static func encode_player(player_id: int) -> int:
	return PLAYER_ID_BASE + player_id


static func decode_player(target_id: int) -> int:
	if target_id < PLAYER_ID_BASE:
		return -1
	return target_id - PLAYER_ID_BASE


func legal_ids(engine: RulesEngine, query: Dictionary) -> Array:
	var kind := str(query.get("kind", ""))
	var out: Array = []
	if kind == "PLAYER" or kind == "ANY_TARGET":
		for i in engine.state.players.size():
			out.append(encode_player(i))
		if kind == "PLAYER":
			return out
	if kind == "SPELL_ON_STACK":
		if engine.state.stack is MagicStack:
			for e in (engine.state.stack as MagicStack).entries:
				var entry := e as StackEntry
				if entry != null and entry.kind == StackEntry.Kind.SPELL:
					out.append(entry.stack_id)
	elif kind == "PERMANENT":
		var q: Dictionary = query.get("query", {})
		if not (q is Dictionary):
			q = {}
		var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf == null:
			return out
		for oid in bf.object_ids:
			var obj: GameObject = engine.state.objects.get(oid)
			if obj != null and Query._matches(obj, null, q):
				out.append(obj.object_id)
	elif kind == "ANY_TARGET":
		var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf != null:
			for oid in bf.object_ids:
				var obj: GameObject = engine.state.objects.get(oid)
				if obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).is_creature():
					out.append(obj.object_id)
	return out


func is_legal(engine: RulesEngine, query: Dictionary, target_id: int) -> bool:
	return legal_ids(engine, query).has(target_id)
