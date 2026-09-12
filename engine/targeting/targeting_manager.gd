class_name TargetingManager
extends RefCounted

func legal_ids(engine: RulesEngine, query: Dictionary) -> Array:
	var kind := str(query.get("kind", ""))
	var out: Array = []
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
	return out


func is_legal(engine: RulesEngine, query: Dictionary, target_id: int) -> bool:
	return legal_ids(engine, query).has(target_id)
