class_name AbilityExecutor
extends RefCounted

var tokens: TokenCatalog = TokenCatalog.new()


## Returns false when a player decision paused this object. The entry stays on the stack.
func resolve(engine: RulesEngine, entry: StackEntry) -> bool:
	if entry == null:
		return true
	var source: GameObject = engine.state.objects.get(entry.source_id)
	if source == null:
		source = engine.state.objects.get(entry.object_id)
	while entry.cursor < entry.effects.size():
		var raw: Variant = entry.effects[entry.cursor]
		if not (raw is AbilityEffect):
			entry.cursor += 1
			continue
		var fx := raw as AbilityEffect
		var link := str(fx.params.get("if_link", ""))
		if link != "" and not bool(entry.choices.get(link, false)):
			entry.cursor += 1
			continue
		if str(fx.kind) == "MAY":
			var may_link := str(fx.params.get("link", ""))
			if not entry.choices.has(may_link):
				_pause_yes_no(engine, entry, fx, may_link)
				return false
			entry.cursor += 1
			continue
		if str(fx.kind) == "CHOOSE":
			var choose_link := str(fx.params.get("link", "choice"))
			if not entry.choices.has(choose_link):
				_pause_choice(engine, entry, fx, choose_link)
				return false
			entry.cursor += 1
			continue
		_apply(engine, entry, source, fx)
		entry.cursor += 1
	return true


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
		"LOSE_LIFE":
			_lose_life(engine, entry, fx)
		"TAP":
			_set_tapped(engine, entry, fx, true)
		"UNTAP":
			_set_tapped(engine, entry, fx, false)
		"SET_CHARACTERISTICS":
			_set_characteristics(engine, entry, source, fx)
		"EXILE_TOP":
			_exile_top(engine, entry, fx)
		"PUT_COUNTER":
			_put_counter(engine, entry, fx)
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


func _lose_life(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 0))
	if n <= 0:
		return
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null:
		return
	var pid := obj.controller_id
	if pid < 0 or pid >= engine.state.players.size():
		return
	engine.state.players[pid].life -= n
	engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, entry.controller_id, {
		to_player = pid,
		amount = n,
	})
	if engine.sba != null:
		engine.sba.check(engine)


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
	engine.state.log.append(EngineEnums.EventType.DAMAGE, entry.controller_id, {
		to_object = obj.object_id,
		amount = n,
	})
	## Lethal damage is a state-based action (CR 704.5g), so indestructible is respected.
	if engine.sba != null:
		engine.sba.check(engine)


func _set_tapped(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect, tap: bool) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		obj.tapped = tap


func _pause_yes_no(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect, link: String) -> void:
	var dec := PlayerDecision.new()
	dec.decision_id = engine.state.next_stack_id
	dec.kind = &"OPTIONAL_YES_NO"
	dec.player_id = entry.controller_id
	dec.stack_id = entry.stack_id
	dec.link = link
	dec.prompt = str(fx.params.get("prompt", "You may."))
	dec.optional = true
	dec.min_count = 0
	dec.max_count = 1
	engine.state.pending_decision = dec
	engine.state.mode = EngineEnums.EngineMode.AWAITING_DECISION
	engine.state.awaiting = {
		player_id = entry.controller_id,
		type = &"decision",
		decision_id = dec.decision_id,
	}


func _pause_choice(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect, link: String) -> void:
	var options: Array = []
	var raw: Variant = fx.params.get("options", [])
	if raw is Array:
		options = raw
	var dec := PlayerDecision.new()
	dec.decision_id = engine.state.next_stack_id
	dec.kind = StringName(str(fx.params.get("choice", "CHOOSE")))
	dec.player_id = entry.controller_id
	dec.stack_id = entry.stack_id
	dec.link = link
	dec.prompt = str(fx.params.get("prompt", "Choose."))
	dec.optional = bool(fx.params.get("optional", false))
	dec.min_count = 0 if dec.optional else 1
	dec.max_count = 1
	dec.candidates = options.duplicate()
	engine.state.pending_decision = dec
	engine.state.mode = EngineEnums.EngineMode.AWAITING_DECISION
	engine.state.awaiting = {
		player_id = entry.controller_id,
		type = &"decision",
		decision_id = dec.decision_id,
	}


func _set_characteristics(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var need := str(fx.params.get("if_subtype", ""))
	if need != "":
		if engine.layers == null or not engine.layers.has_subtype(engine.state, source, need):
			return
	var effect := ContinuousEffect.new()
	effect.object_ids = [source.object_id]
	effect.source_id = source.object_id
	effect.controller_id = entry.controller_id
	effect.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	var duration := str(fx.params.get("duration", "PERMANENT"))
	effect.until_eot = duration == "END_OF_TURN"
	var subs: Variant = fx.params.get("subtypes", [])
	if subs is Array:
		for s in subs:
			effect.set_subtypes.append(str(s))
	if fx.params.has("power"):
		effect.sets_power = true
		effect.set_power = int(fx.params.get("power", 0))
	if fx.params.has("toughness"):
		effect.sets_toughness = true
		effect.set_toughness = int(fx.params.get("toughness", 0))
	var kws: Variant = fx.params.get("keywords", [])
	if kws is Array:
		for kw in kws:
			effect.add_keywords.append(str(kw))
	var gains: Variant = fx.params.get("gain_abilities", [])
	if gains is Array:
		effect.gain_ability_ids = (gains as Array).duplicate()
	engine.state.effects.append(effect)


func _exile_top(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 1))
	var pid := entry.controller_id
	var may_play := str(fx.params.get("may_play", ""))
	for _i in n:
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
		if lib == null or lib.is_empty():
			return
		var top_id := int(lib.object_ids[0])
		var moved: GameObject = engine.state.zones.move(top_id, EngineEnums.ZoneId.EXILE, pid)
		if moved != null and may_play == "END_OF_TURN":
			moved.may_play_controller = pid


func _put_counter(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var cname := str(fx.params.get("name", "+1/+1"))
	var n := int(fx.params.get("n", 1))
	obj.counters[cname] = int(obj.counters.get(cname, 0)) + n


func _count(engine: RulesEngine, source: GameObject, raw: Variant) -> int:
	if raw is Dictionary and (raw as Dictionary).has("query"):
		var q: Variant = (raw as Dictionary).get("query", {})
		if q is Dictionary:
			return Query.count_objects(engine.state, source, q)
	return int(raw)
