class_name TargetingManager
extends RefCounted

const PLAYER_ID_BASE := 1000000


static func encode_player(player_id: int) -> int:
	return PLAYER_ID_BASE + player_id


static func decode_player(target_id: int) -> int:
	if target_id < PLAYER_ID_BASE:
		return -1
	return target_id - PLAYER_ID_BASE


func legal_ids(engine: RulesEngine, query: Dictionary, source_id: int = -1) -> Array:
	var kind := str(query.get("kind", ""))
	var out: Array = []
	var src := source_id
	if src <= 0 and engine != null:
		src = engine._cast_source
	if kind == "PLAYER" or kind == "ANY_TARGET":
		for i in engine.state.players.size():
			out.append(encode_player(i))
		if kind == "PLAYER":
			return out
	if kind == "SPELL_ON_STACK":
		var spec: Dictionary = {}
		var qv: Variant = query.get("query", {})
		if qv is Dictionary:
			spec = qv
		if engine.state.stack is MagicStack:
			for e in (engine.state.stack as MagicStack).entries:
				var entry := e as StackEntry
				if entry == null or entry.kind != StackEntry.Kind.SPELL:
					continue
				if not spec.is_empty():
					var spell: GameObject = engine.state.objects.get(entry.object_id)
					if spell == null or not Query._matches(spell, null, spec):
						continue
				out.append(entry.stack_id)
	elif kind == "PERMANENT":
		var src_obj: GameObject = engine.state.objects.get(src) if src > 0 else null
		var q: Dictionary = query.get("query", {})
		if not (q is Dictionary):
			q = {}
		var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf == null:
			return out
		for oid in bf.object_ids:
			var obj: GameObject = engine.state.objects.get(oid)
			if obj != null and Query._matches(obj, src_obj, q) and not _cant_be_targeted(engine, obj, src):
				out.append(obj.object_id)
	elif kind == "ANY_TARGET":
		var bf2: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf2 != null:
			for oid2 in bf2.object_ids:
				var creature: GameObject = engine.state.objects.get(oid2)
				if creature == null or not (creature.definition is CardDefinition):
					continue
				if not (creature.definition as CardDefinition).is_creature():
					continue
				if _cant_be_targeted(engine, creature, src):
					continue
				out.append(creature.object_id)
	return out


func is_legal(engine: RulesEngine, query: Dictionary, target_id: int, source_id: int = -1) -> bool:
	return legal_ids(engine, query, source_id).has(target_id)


## Hexproof stops opponents. Shroud stops everyone. Ward is a triggered ability, not an illegal target.
## Protection here covers "protection from {color}" against the source's colors (CR 702.16).
func _cant_be_targeted(engine: RulesEngine, obj: GameObject, source_id: int) -> bool:
	if obj == null or engine == null or engine.layers == null:
		return false
	var kws: Variant = engine.layers.snapshot(engine.state, obj).get("keywords", PackedStringArray())
	if not (kws is PackedStringArray):
		return false
	var src: GameObject = engine.state.objects.get(source_id) if source_id > 0 else null
	for kw in kws:
		var low := str(kw).to_lower()
		if low == "shroud":
			return true
		if low == "hexproof":
			if src != null and src.controller_id != obj.controller_id:
				return true
		elif low.begins_with("protection from "):
			if src != null and _protection_matches(low, src):
				return true
	return false


func _protection_matches(keyword: String, source: GameObject) -> bool:
	if source == null or not (source.definition is CardDefinition):
		return false
	var quality := keyword.trim_prefix("protection from ").strip_edges()
	var letter := ""
	match quality:
		"white":
			letter = "W"
		"blue":
			letter = "U"
		"black":
			letter = "B"
		"red":
			letter = "R"
		"green":
			letter = "G"
		_:
			return false
	return (source.definition as CardDefinition).colors.has(letter)
