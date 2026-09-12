class_name AbilityExecutor
extends RefCounted

var tokens: TokenCatalog = TokenCatalog.new()


func resolve(engine: RulesEngine, entry: StackEntry) -> void:
	if entry == null:
		return
	var source: GameObject = engine.state.objects.get(entry.source_id)
	if source == null:
		source = engine.state.objects.get(entry.object_id)
	for fx in entry.effects:
		if fx is AbilityEffect:
			_apply(engine, entry, source, fx as AbilityEffect)


func _apply(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	match str(fx.kind):
		"DRAW":
			var n := int(fx.params.get("n", 1))
			for _i in n:
				engine.draw_card(entry.controller_id)
		"CREATE_TOKEN":
			var token_id := str(fx.params.get("token", ""))
			var n := _count(engine, source, fx.params.get("count", 1))
			var def: CardDefinition = tokens.definition_for(token_id)
			for _j in n:
				engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, {
					definition = def,
					is_token = true,
					controller_id = entry.controller_id,
				})
		"MOVE_ZONE":
			_move_zone(engine, entry, fx)
		"COUNTER_SPELL":
			_counter_spell(engine, entry, fx)
		"ADD_MANA":
			var produced := ManaCost.parse(str(fx.params.get("mana", "")))
			engine.mana.add(entry.controller_id, produced)
		_:
			pass


func _move_zone(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var dest := Query._zone_id(str(fx.params.get("to", "HAND")))
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var target_id := int(entry.targets[idx])
	var obj: GameObject = engine.state.objects.get(target_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	engine.state.zones.move(target_id, dest, obj.owner_id)


func _counter_spell(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var sid := int(entry.targets[idx])
	if not (engine.state.stack is MagicStack):
		return
	var stack := engine.state.stack as MagicStack
	var found_i := -1
	var found: StackEntry = null
	for i in stack.entries.size():
		var e: StackEntry = stack.entries[i]
		if e != null and e.stack_id == sid:
			found_i = i
			found = e
			break
	if found == null:
		return
	stack.entries.remove_at(found_i)
	if found.object_id == 0:
		return
	var obj: GameObject = engine.state.objects.get(found.object_id)
	if obj != null and obj.zone == EngineEnums.ZoneId.STACK:
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func _count(engine: RulesEngine, source: GameObject, raw: Variant) -> int:
	if raw is Dictionary and (raw as Dictionary).has("query"):
		var q: Variant = (raw as Dictionary).get("query", {})
		if q is Dictionary:
			return Query.count_objects(engine.state, source, q)
	return int(raw)
