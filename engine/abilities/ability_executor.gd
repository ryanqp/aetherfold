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
			var n := _value(engine, entry, source, fx.params.get("n", 1))
			for pid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
				for _i in n:
					engine.draw_card(pid)
		"CREATE_TOKEN":
			_create_tokens(engine, entry, source, fx)
		"MOVE_ZONE":
			_move_zone(engine, entry, fx)
		"EXILE_UNTIL_LEAVES":
			_exile_until_leaves(engine, entry, source, fx)
		"COUNTER_SPELL":
			_counter_spell(engine, entry, fx)
		"ADD_MANA":
			var produced := engine.resolve_mana(entry.controller_id, ManaCost.parse(str(fx.params.get("mana", ""))))
			engine.mana.add(entry.controller_id, produced)
		"DEAL_DAMAGE":
			_deal_damage(engine, entry, source, fx)
		"DEAL_DAMAGE_EACH":
			_deal_damage_each(engine, entry, source, fx)
		"LOSE_LIFE":
			_lose_life(engine, entry, fx)
		"TAP":
			_set_tapped(engine, entry, fx, true)
		"UNTAP":
			_set_tapped(engine, entry, fx, false)
		"UNTAP_EACH":
			for obj in _each(engine, entry, source, fx.params.get("query", {})):
				obj.tapped = false
		"SET_CHARACTERISTICS":
			_set_characteristics(engine, entry, source, fx)
		"EXILE_TOP":
			_exile_top(engine, entry, fx)
		"PUT_COUNTER":
			_put_counter(engine, entry, source, fx)
		"GAIN_LIFE":
			_gain_life(engine, entry, source, fx)
		"DESTROY":
			_destroy(engine, entry, fx)
		"DESTROY_ALL":
			_destroy_all(engine, entry, source, fx)
		"PUMP":
			_pump(engine, entry, source, fx)
		"SEARCH_LIBRARY":
			_search_library(engine, entry, source, fx)
		"SCRY":
			_scry(engine, entry, fx)
		"FIGHT":
			_fight(engine, entry, source, fx)
		"ATTACH":
			_attach(engine, entry, source, fx)
		"CHOOSE_TYPE":
			_choose_type(engine, entry, source)
		"RETURN_FROM_GRAVEYARD":
			_return_from_graveyard(engine, entry, fx)
		"DISCOVER":
			_discover(engine, entry, source, fx)
		"HIDEAWAY":
			_hideaway(engine, entry, source, fx)
		"PLAY_HIDDEN":
			_play_hidden(engine, entry, source, fx)
		"MILL":
			_mill(engine, entry, fx)
		"DISCARD":
			_discard(engine, entry, fx)
		"SURVEIL":
			_surveil(engine, entry, fx)
		"BECOME_MONARCH":
			engine.state.monarch_id = entry.controller_id
		"CHOOSE_COLOR":
			_choose_color(engine, entry, source, fx)
		_:
			pass


# --- Values, players and object sets ----------------------------------------------------

## An int, or {"expr": ..., "mult": n, "add": n}: TRIGGER_TOUGHNESS / TRIGGER_POWER (the creature that
## set off the trigger), EVENT_AMOUNT (damage or life that set it off), SELF_POWER, LANDS, COUNT (+ query).
func _value(engine: RulesEngine, entry: StackEntry, source: GameObject, raw: Variant) -> int:
	if not (raw is Dictionary):
		return int(raw)
	var d := raw as Dictionary
	var base := 0
	match str(d.get("expr", "")):
		"TRIGGER_TOUGHNESS":
			base = int(entry.ctx.get("toughness", 0))
		"TRIGGER_POWER":
			base = int(entry.ctx.get("power", 0))
		"EVENT_AMOUNT":
			base = int(entry.ctx.get("amount", 0))
		"SELF_POWER":
			base = engine.power_of(source) if source != null else 0
		"LANDS":
			base = Query.count_objects(engine.state, _ref(entry, source), {"controller": "SOURCE_CONTROLLER", "type": "land"})
		"COUNT":
			base = Query.count_objects(engine.state, _ref(entry, source), d.get("query", {}))
	return base * int(d.get("mult", 1)) + int(d.get("add", 0))


## The source as a reference for queries; a stand-in with the right controller if it is gone.
func _ref(entry: StackEntry, source: GameObject) -> GameObject:
	if source != null:
		return source
	var ghost := GameObject.new()
	ghost.object_id = entry.source_id
	ghost.controller_id = entry.controller_id
	ghost.owner_id = entry.controller_id
	return ghost


func _players_for(engine: RulesEngine, entry: StackEntry, who: String) -> Array:
	var out: Array = []
	for p in engine.state.players:
		if p.lost:
			continue
		match who:
			"EACH_OPPONENT":
				if p.player_id != entry.controller_id:
					out.append(p.player_id)
			"EACH_PLAYER":
				out.append(p.player_id)
			_:
				if p.player_id == entry.controller_id:
					out.append(p.player_id)
	return out


## Battlefield objects matching a query, read from the source's side ("you control").
func _each(engine: RulesEngine, entry: StackEntry, source: GameObject, query: Variant) -> Array:
	var out: Array = []
	if not (query is Dictionary):
		return out
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	var ref := _ref(entry, source)
	for oid in bf.object_ids.duplicate():
		var obj: GameObject = engine.state.objects.get(oid)
		if obj != null and Query._matches(obj, ref, query):
			out.append(obj)
	return out


## What an effect acts on: the source itself ("self"), every object matching "each", or its target.
func _affected(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> Array:
	if bool(fx.params.get("self", false)):
		if source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
			return [source]
		return []
	if fx.params.has("each"):
		return _each(engine, entry, source, fx.params["each"])
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return []
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return []
	return [obj]


func _create_tokens(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var def: CardDefinition = null
	if fx.params.has("spec"):
		def = tokens.from_spec(fx.params["spec"])
	else:
		def = tokens.definition_for(str(fx.params.get("token", "")))
	if def == null:
		return
	var n := _value(engine, entry, source, fx.params.get("count", 1))
	for _j in n:
		var opts := {
			definition = def,
			is_token = true,
			controller_id = entry.controller_id,
		}
		if bool(fx.params.get("tapped", false)):
			opts["tapped"] = true
		var obj: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, opts)
		if obj == null:
			continue
		## Logged like any zone change so "enters" triggers and the History see tokens too.
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, entry.controller_id, {
			from_id = 0,
			to_id = obj.object_id,
			from_zone = -1,
			to_zone = EngineEnums.ZoneId.BATTLEFIELD,
			linked_from = 0,
		})


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


## CR 610.3: exile the target until the source leaves the battlefield. If the source is already gone
## when this resolves, nothing is exiled.
func _exile_until_leaves(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var moved: GameObject = engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
	if moved == null:
		return
	var linked: Array = engine.state.exile_links.get(source.object_id, [])
	linked.append(moved.object_id)
	engine.state.exile_links[source.object_id] = linked


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
	var pids: Array = []
	if fx.params.has("who"):
		pids = _players_for(engine, entry, str(fx.params["who"]))
	else:
		var idx := int(fx.params.get("target", 0))
		if idx < 0 or idx >= entry.targets.size():
			return
		var tid := int(entry.targets[idx])
		var tp := TargetingManager.decode_player(tid)
		if tp >= 0:
			pids = [tp]
		else:
			var obj: GameObject = engine.state.objects.get(tid)
			if obj != null:
				pids = [obj.controller_id]
	for pid in pids:
		if pid < 0 or pid >= engine.state.players.size():
			continue
		engine.state.players[pid].life -= n
		engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, entry.controller_id, {
			to_player = pid,
			amount = n,
		})
	if engine.sba != null:
		engine.sba.check(engine)


func _deal_damage(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 0))
	if n <= 0:
		return
	if fx.params.has("who"):
		for pid in _players_for(engine, entry, str(fx.params["who"])):
			_damage_player(engine, entry, pid, n)
		return
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var tid := int(entry.targets[idx])
	var pid2 := TargetingManager.decode_player(tid)
	if pid2 >= 0 and pid2 < engine.state.players.size():
		_damage_player(engine, entry, pid2, n)
		return
	var obj: GameObject = engine.state.objects.get(tid)
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	engine.damage_object(source if source != null else _ref(entry, null), obj, n)
	## Lethal damage is a state-based action (CR 704.5g), so indestructible is respected.
	if engine.sba != null:
		engine.sba.check(engine)


func _damage_player(engine: RulesEngine, entry: StackEntry, pid: int, n: int) -> void:
	engine.state.players[pid].life -= n
	engine.state.log.append(EngineEnums.EventType.DAMAGE, entry.controller_id, {
		to_player = pid,
		amount = n,
		object_id = entry.source_id,
	})
	if engine.sba != null:
		engine.sba.check(engine)


## "deals N damage to each other creature".
func _deal_damage_each(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 0))
	if n <= 0:
		return
	var src := source if source != null else _ref(entry, null)
	for obj in _each(engine, entry, source, fx.params.get("query", {})):
		engine.damage_object(src, obj, n)
	if engine.sba != null:
		engine.sba.check(engine)


## CR 119.3: gaining life. With no `target` the effect's controller gains it.
func _gain_life(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := _value(engine, entry, source, fx.params.get("n", 0))
	if n <= 0:
		return
	var pids: Array = [entry.controller_id]
	if fx.params.has("who"):
		pids = _players_for(engine, entry, str(fx.params["who"]))
	elif fx.params.has("target"):
		var idx := int(fx.params.get("target", 0))
		if idx < 0 or idx >= entry.targets.size():
			return
		var tid := int(entry.targets[idx])
		var tp := TargetingManager.decode_player(tid)
		if tp >= 0:
			pids = [tp]
		else:
			var obj: GameObject = engine.state.objects.get(tid)
			if obj == null:
				return
			pids = [obj.controller_id]
	for pid in pids:
		if pid < 0 or pid >= engine.state.players.size():
			continue
		engine.state.players[pid].life += n
		engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, pid, {
			to_player = pid,
			amount = n,
			gain = true,
		})


## CR 701.7: destroy puts the permanent into its owner's graveyard unless it has indestructible (CR 702.12b).
func _destroy(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	if engine.has_keyword(obj, "Indestructible"):
		return
	engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


## A temporary +X/+Y (layer 7c) and keywords (layer 6) on the affected objects (CR 611.2).
## The effect follows those objects only; a new object id after a zone change is not affected (CR 400.7).
func _pump(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var objs := _affected(engine, entry, source, fx)
	if objs.is_empty():
		return
	var effect := ContinuousEffect.new()
	for o in objs:
		effect.object_ids.append((o as GameObject).object_id)
	effect.source_id = entry.source_id
	effect.controller_id = entry.controller_id
	effect.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	effect.power = _value(engine, entry, source, fx.params.get("power", 0))
	effect.toughness = _value(engine, entry, source, fx.params.get("toughness", 0))
	effect.until_eot = str(fx.params.get("duration", "END_OF_TURN")) == "END_OF_TURN"
	var kws: Variant = fx.params.get("keywords", [])
	if kws is Array:
		for kw in kws:
			effect.add_keywords.append(str(kw))
	engine.state.effects.append(effect)
	## A negative toughness can kill it (CR 704.5f).
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


func _put_counter(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var cname := str(fx.params.get("name", "+1/+1"))
	var n := _value(engine, entry, source, fx.params.get("n", 1))
	for obj in _affected(engine, entry, source, fx):
		obj.counters[cname] = int(obj.counters.get(cname, 0)) + n


# --- Search, scry, fights, equipment -----------------------------------------------------

## "Search your library for a basic land card, put it onto the battlefield tapped, then shuffle."
## The game picks the card: for lands, a type you have fewer of, favouring your commander's colors.
func _search_library(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var filt: Dictionary = fx.params.get("filter", {})
	var want := int(fx.params.get("n", 1))
	var dest := EngineEnums.ZoneId.BATTLEFIELD if str(fx.params.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	var ref := _ref(entry, source)
	for _i in want:
		var best_id := -1
		var best_score := -1000000
		for oid in lib.object_ids:
			var cand: GameObject = engine.state.objects.get(oid)
			if cand == null or not Query._matches(cand, ref, filt):
				continue
			var sc := _search_score(engine, pid, cand)
			if sc > best_score:
				best_score = sc
				best_id = int(oid)
		if best_id < 0:
			break
		var moved: GameObject = engine.state.zones.move(best_id, dest, pid)
		if moved != null and dest == EngineEnums.ZoneId.BATTLEFIELD and bool(fx.params.get("tapped", false)):
			moved.tapped = true
	engine.shuffle_library(pid)


func _search_score(engine: RulesEngine, pid: int, cand: GameObject) -> int:
	var def := cand.definition as CardDefinition if cand.definition is CardDefinition else null
	if def == null:
		return 0
	if not def.is_land():
		return def.cmc
	var identity := engine.commander_identity(pid)
	var score := 5
	for pair in [["Plains", "W"], ["Island", "U"], ["Swamp", "B"], ["Mountain", "R"], ["Forest", "G"]]:
		if def.type_line.contains(str(pair[0])):
			if identity.has(str(pair[1])):
				score += 10
			score -= 3 * _controlled_of_type(engine, pid, str(pair[0]))
	return score


func _controlled_of_type(engine: RulesEngine, pid: int, subtype: String) -> int:
	var n := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 0
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id == pid and o.definition is CardDefinition and (o.definition as CardDefinition).type_line.contains(subtype):
			n += 1
	return n


## Scry N (CR 701.22): without a choice screen, lands go to the bottom once you have plenty of them.
func _scry(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var lands := _controlled_of_type(engine, pid, "Land")
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand != null:
		for oid in hand.object_ids:
			var h: GameObject = engine.state.objects.get(oid)
			if h != null and h.definition is CardDefinition and (h.definition as CardDefinition).is_land():
				lands += 1
	var top_ids: Array = []
	for i in mini(int(fx.params.get("n", 1)), lib.object_ids.size()):
		top_ids.append(int(lib.object_ids[i]))
	for oid in top_ids:
		var c: GameObject = engine.state.objects.get(oid)
		if c != null and c.definition is CardDefinition and (c.definition as CardDefinition).is_land() and lands >= 6:
			engine.put_library_bottom(oid, pid)


## CR 701.14: each creature deals damage equal to its power to the other. "one_sided": only `a` deals damage.
func _fight(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var a := _object_ref(engine, entry, source, fx.params.get("a", "SELF"))
	var b := _object_ref(engine, entry, source, fx.params.get("b", 0))
	if a == null or b == null or a.object_id == b.object_id:
		return
	if a.zone != EngineEnums.ZoneId.BATTLEFIELD or b.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var pa := engine.power_of(a)
	var pb := engine.power_of(b)
	engine.damage_object(a, b, pa)
	if not bool(fx.params.get("one_sided", false)):
		engine.damage_object(b, a, pb)
	if engine.sba != null:
		engine.sba.check(engine)


func _object_ref(engine: RulesEngine, entry: StackEntry, source: GameObject, ref: Variant) -> GameObject:
	if str(ref) == "SELF":
		return source
	var idx := int(ref)
	if idx < 0 or idx >= entry.targets.size():
		return null
	return engine.state.objects.get(int(entry.targets[idx]))


## Equip (CR 702.6): attach the source to the target creature.
func _attach(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var host: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if host == null or host.zone != EngineEnums.ZoneId.BATTLEFIELD or not engine.is_creature_now(host):
		return
	source.attached_to = host.object_id


## "As ~ enters, choose a creature type": the type you have most of across your cards.
func _choose_type(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null:
		return
	var pid := entry.controller_id
	var counts := {}
	for zid in [EngineEnums.ZoneId.LIBRARY, EngineEnums.ZoneId.HAND, EngineEnums.ZoneId.BATTLEFIELD, EngineEnums.ZoneId.GRAVEYARD, EngineEnums.ZoneId.COMMAND]:
		var z: Zone = engine.state.zones.get_zone(zid, pid)
		if z == null:
			continue
		for oid in z.object_ids:
			var o: GameObject = engine.state.objects.get(oid)
			if o == null or o.owner_id != pid or not (o.definition is CardDefinition):
				continue
			var def := o.definition as CardDefinition
			if not def.is_creature():
				continue
			for t in Query._subtype_words(def.type_line):
				counts[str(t)] = int(counts.get(str(t), 0)) + 1
	var best := ""
	var best_n := 0
	var names: Array = counts.keys()
	names.sort()
	for t in names:
		if int(counts[t]) > best_n:
			best_n = int(counts[t])
			best = str(t)
	source.chosen_type = best


## Discover X (CR 701.57): exile cards from the top of your library until a nonland card with mana
## value X or less; permanents go onto the battlefield, other spells to your hand (there is no free-cast
## yet), and the rest go to the bottom of the library.
func _discover(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var x := _value(engine, entry, source, fx.params.get("n", 0))
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var skipped: Array = []
	var found: GameObject = null
	var guard := 0
	while not lib.object_ids.is_empty() and guard < 200:
		guard += 1
		var top: GameObject = engine.state.objects.get(lib.object_ids[0])
		if top == null:
			lib.object_ids.remove_at(0)
			continue
		var moved: GameObject = engine.state.zones.move(top.object_id, EngineEnums.ZoneId.EXILE, pid)
		if moved == null:
			break
		var def := moved.definition as CardDefinition if moved.definition is CardDefinition else null
		if def != null and not def.is_land() and def.cmc <= x:
			found = moved
			break
		skipped.append(moved.object_id)
	if found != null:
		var fdef := found.definition as CardDefinition
		var dest := EngineEnums.ZoneId.BATTLEFIELD if fdef.is_permanent_type() else EngineEnums.ZoneId.HAND
		engine.state.zones.move(found.object_id, dest, pid)
	for oid in skipped:
		var back: GameObject = engine.state.zones.move(int(oid), EngineEnums.ZoneId.LIBRARY, pid)
		if back != null:
			lib.object_ids.erase(back.object_id)
			lib.object_ids.append(back.object_id)


## "As ~ enters, choose a color other than green": the first color of your commander's identity that fits.
func _choose_color(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null:
		return
	var avoid := str(fx.params.get("not", ""))
	for c in engine.commander_identity(entry.controller_id):
		if str(c) != avoid:
			source.chosen_color = str(c)
			return
	for c2 in ["W", "U", "B", "R", "G"]:
		if c2 != avoid:
			source.chosen_color = c2
			return


## Hideaway N (CR 702.75): look at the top N cards, exile one face down (the best nonland, else a land),
## put the rest on the bottom in a random order. The permanent remembers which card (hideaway_card).
func _hideaway(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null:
		return
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or lib.is_empty():
		return
	var ids: Array = []
	for i in mini(int(fx.params.get("n", 1)), lib.object_ids.size()):
		ids.append(int(lib.object_ids[i]))
	var best_id := -1
	var best_score := -1
	for oid in ids:
		var c: GameObject = engine.state.objects.get(oid)
		if c == null or not (c.definition is CardDefinition):
			continue
		var def := c.definition as CardDefinition
		var sc := 1 if def.is_land() else 2 + def.cmc
		if sc > best_score:
			best_score = sc
			best_id = int(oid)
	if best_id < 0:
		return
	var hidden: GameObject = engine.state.zones.move(best_id, EngineEnums.ZoneId.EXILE, pid)
	if hidden != null:
		source.hideaway_card = hidden.object_id
	ids.erase(best_id)
	engine.state.rng.shuffle(ids)
	for oid in ids:
		engine.put_library_bottom(int(oid), pid)


## "You may play the exiled card without paying its mana cost [if creatures you control have total power N
## or greater]": checked as the ability resolves. Lands are played (if a land drop is left), spells are cast.
func _play_hidden(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.hideaway_card == 0:
		return
	var pid := entry.controller_id
	var need := int(fx.params.get("min_total_power", 0))
	if need > 0:
		var total := 0
		for o in _each(engine, entry, source, {"controller": "SOURCE_CONTROLLER", "type": "creature"}):
			total += engine.power_of(o)
		if total < need:
			return
	var card: GameObject = engine.state.objects.get(source.hideaway_card)
	if card == null or card.zone != EngineEnums.ZoneId.EXILE or not (card.definition is CardDefinition):
		return
	var def := card.definition as CardDefinition
	if def.is_land():
		if bool(engine.state.land_played.get(pid, false)):
			return
		engine.state.zones.move(card.object_id, EngineEnums.ZoneId.BATTLEFIELD, pid)
		engine.state.land_played[pid] = true
		source.hideaway_card = 0
		return
	if engine.cast_free(pid, card.object_id):
		source.hideaway_card = 0


func _mill(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 1))
	for pid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
		for _i in n:
			if lib == null or lib.is_empty():
				break
			engine.state.zones.move(int(lib.object_ids[0]), EngineEnums.ZoneId.GRAVEYARD, pid)


## Discard N (CR 701.8): without a choice screen the player discards the cheapest cards (extra lands first).
func _discard(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 1))
	for pid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
		for _i in n:
			var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
			if hand == null or hand.is_empty():
				break
			var lands := _controlled_of_type(engine, pid, "Land")
			var worst := -1
			var worst_score := 1000000
			for oid in hand.object_ids:
				var c: GameObject = engine.state.objects.get(oid)
				if c == null or not (c.definition is CardDefinition):
					continue
				var def := c.definition as CardDefinition
				var sc := def.cmc * 2 + (-3 if def.is_land() and lands >= 5 else (4 if def.is_land() else 0))
				if sc < worst_score:
					worst_score = sc
					worst = int(oid)
			if worst >= 0:
				engine.state.zones.move(worst, EngineEnums.ZoneId.GRAVEYARD, pid)


## Surveil N (CR 701.46): lands beyond what you need go to the graveyard, the rest stay on top.
func _surveil(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var lands := _controlled_of_type(engine, pid, "Land")
	var top_ids: Array = []
	for i in mini(int(fx.params.get("n", 1)), lib.object_ids.size()):
		top_ids.append(int(lib.object_ids[i]))
	for oid in top_ids:
		var c: GameObject = engine.state.objects.get(oid)
		if c != null and c.definition is CardDefinition and (c.definition as CardDefinition).is_land() and lands >= 6:
			engine.state.zones.move(oid, EngineEnums.ZoneId.GRAVEYARD, pid)


func _return_from_graveyard(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var card: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if card == null or card.zone != EngineEnums.ZoneId.GRAVEYARD:
		return
	var dest := EngineEnums.ZoneId.BATTLEFIELD if str(fx.params.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	engine.state.zones.move(card.object_id, dest, card.owner_id)


## CR 701.7: destroy all permanents matching the query (indestructible ones survive).
func _destroy_all(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	for obj in _each(engine, entry, source, fx.params.get("query", {})):
		if engine.has_keyword(obj, "Indestructible"):
			continue
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func _count(engine: RulesEngine, source: GameObject, raw: Variant) -> int:
	if raw is Dictionary and (raw as Dictionary).has("query"):
		var q: Variant = (raw as Dictionary).get("query", {})
		if q is Dictionary:
			return Query.count_objects(engine.state, source, q)
	return int(raw)
