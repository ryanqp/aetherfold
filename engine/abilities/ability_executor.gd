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
		"DEAL_DAMAGE":
			_deal_damage(engine, entry, fx)
		"TAP":
			_set_tapped(engine, entry, fx, true)
		"UNTAP":
			_set_tapped(engine, entry, fx, false)
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
	var found: StackEntry = stack.remove_by_stack_id(sid)
	if found == null:
		return
	if found.object_id == 0:
		return
	var obj: GameObject = engine.state.objects.get(found.object_id)
	if obj != null and obj.zone == EngineEnums.ZoneId.STACK:
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func _deal_damage(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 0))
	if n <= 0:
		return
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var tid := int(entry.targets[idx])
	var pid := TargetingManager.decode_player(tid)
	if pid >= 0 and pid < engine.state.players.size():
		engine.state.players[pid].life -= n
		engine.state.log.append(EngineEnums.EventType.DAMAGE, entry.controller_id, {
			to_player = pid,
			amount = n,
		})
		if engine.sba != null:
			engine.sba.check(engine)
		return
	var obj: GameObject = engine.state.objects.get(tid)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	obj.damage_marked += n
	var tou := 0
	if engine.layers != null:
		tou = int(engine.layers.snapshot(engine.state, obj).get("toughness", 0))
	elif obj.definition is CardDefinition:
		var def := obj.definition as CardDefinition
		tou = int(def.toughness) if def.toughness.is_valid_int() else 0
	if obj.definition is CardDefinition and (obj.definition as CardDefinition).is_creature() and obj.damage_marked >= tou:
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
	if engine.sba != null:
		engine.sba.check(engine)


func _set_tapped(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect, tap: bool) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		obj.tapped = tap


func _count(engine: RulesEngine, source: GameObject, raw: Variant) -> int:
	if raw is Dictionary and (raw as Dictionary).has("query"):
		var q: Variant = (raw as Dictionary).get("query", {})
		if q is Dictionary:
			return Query.count_objects(engine.state, source, q)
	return int(raw)
