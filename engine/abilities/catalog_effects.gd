class_name CatalogEffects
extends RefCounted

## Effects added while bringing the whole card catalog under the Oracle reader. Each is small and general: moving a target card
## out of a graveyard, acting on the permanent an Aura or Equipment is attached to, coin flips, "tap or untap", blinking a Saga
## back transformed, protection from a chosen colour, and the like. AbilityExecutor hands these kinds here.

const KINDS := ["GRAVE_CARD_MOVE", "ATTACHED_ACT", "RETURN_SELF_FROM_GY", "RETURN_EXILED", "TAP_OR_UNTAP", "FLIP_COIN",
	"BLINK_TRANSFORM", "PROTECT_COLOR_CHOICE", "TOP_CARD_DECIDE", "PEEK_TOP", "PREVENT_NEXT_FROM_SOURCE", "GET_EXPERIENCE"]

const COLOR_NAMES := {"W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green"}


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func apply(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var p: Dictionary = fx.params
	match str(fx.kind):
		"GRAVE_CARD_MOVE":
			_grave_card_move(ex, engine, entry, source, p)
		"ATTACHED_ACT":
			_attached_act(engine, source, str(p.get("act", "")))
		"RETURN_SELF_FROM_GY":
			## "Return ~ from your graveyard to the battlefield [tapped]" / "... to your hand".
			if source == null or source.zone != EngineEnums.ZoneId.GRAVEYARD:
				return
			var to := EngineEnums.ZoneId.HAND if str(p.get("to", "BATTLEFIELD")) == "HAND" else EngineEnums.ZoneId.BATTLEFIELD
			var back: GameObject = engine.state.zones.move(source.object_id, to, source.owner_id)
			if back != null and to == EngineEnums.ZoneId.BATTLEFIELD and bool(p.get("tapped", false)):
				back.tapped = true
		"RETURN_EXILED":
			_return_exiled(engine, source, str(p.get("to", "BATTLEFIELD")))
		"TAP_OR_UNTAP":
			_tap_or_untap(ex, engine, entry, source, p)
		"FLIP_COIN":
			## CR 705: win or lose; what follows is gated on the link (if_link = won, if_not_link = lost).
			var won := engine.state.rng.randi_range(0, 1) == 1
			entry.choices[str(p.get("link", "coin"))] = won
			engine.state.log.append(EngineEnums.EventType.NOTE, entry.controller_id, {text = "Coin flip: %s." % ("won" if won else "lost")})
		"BLINK_TRANSFORM":
			## A Saga's last chapter: "Exile ~, then return it to the battlefield transformed." Done in place: it turns to its back
			## face as a new permanent (no counters, summoning sick, untapped).
			if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
				return
			KeywordActions.transform(engine, source)
			source.counters.clear()
			source.tapped = false
			source.summoned_this_turn = true
			if str(p.get("control", "")) == "OWNER":
				source.controller_id = source.owner_id
		"PROTECT_COLOR_CHOICE":
			_protect_color_choice(ex, engine, entry, source, p)
		"TOP_CARD_DECIDE":
			_top_card_decide(ex, engine, entry, source, p)
		"PEEK_TOP":
			## "Look at the top card of your library." Only its owner learns what it is (a private History note).
			var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, entry.controller_id)
			if lib != null and not lib.is_empty():
				engine.state.log.append(EngineEnums.EventType.NOTE, entry.controller_id, {text = "Top card of your library: %s." % ex._name_of(engine, int(lib.object_ids[0])), private_to = entry.controller_id})
		"PREVENT_NEXT_FROM_SOURCE":
			_prevent_next_from_source(ex, engine, entry, p)
		"GET_EXPERIENCE":
			engine.state.players[entry.controller_id].experience += int(p.get("n", 1))


## Circle of Protection: "The next time a red source of your choice would deal damage to you this turn, prevent that damage."
## The player picks a permanent or spell (of that colour); the bot picks the opponents' hardest hitter. One shield, used once.
static func _prevent_next_from_source(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var pid := entry.controller_id
	var color := str(p.get("color", ""))
	var options: Array = []
	var best := 0
	var best_power := -1
	var ids: Array = []
	ids.append_array((engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD) as Zone).object_ids)
	for se in (engine.state.stack as MagicStack).entries:
		if (se as StackEntry).stack_id != entry.stack_id and engine.state.objects.has((se as StackEntry).source_id):
			ids.append((se as StackEntry).source_id)
	for oid in ids:
		var o: GameObject = engine.state.objects.get(int(oid))
		if o == null or not (o.definition is CardDefinition) or options.any(func(x) -> bool: return int(x.value) == int(oid)):
			continue
		if color != "" and not (o.definition as CardDefinition).colors.has(color):
			continue
		options.append(ex._card_option(engine, int(oid)))
		if o.controller_id != pid and o.zone == EngineEnums.ZoneId.BATTLEFIELD and engine.is_creature_now(o) and engine.power_of(o) > best_power:
			best_power = engine.power_of(o)
			best = int(oid)
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "cop_source", "Choose a source: the next damage it would deal to you this turn is prevented.", options, true)
	if ans.s == "paused":
		return
	var pick := int(ans.value) if ans.s == "picked" else (best if ans.s == "auto" else 0)
	if pick == 0:
		return
	engine.state.prevention.append({"to": "PLAYER", "player_id": pid, "n": -1, "source_id": pick, "once": true})


static func _grave_card_move(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var card := ex._object_ref(engine, entry, source, p.get("target", 0))
	if card == null or card.zone != EngineEnums.ZoneId.GRAVEYARD:
		return
	match str(p.get("to", "EXILE")):
		"EXILE":
			var gone: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.EXILE, card.owner_id)
			if gone != null and source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
				source.imprinted.append(gone.object_id)
		"HAND":
			engine.state.zones.move(card.object_id, EngineEnums.ZoneId.HAND, card.owner_id)
		"BATTLEFIELD":
			var back: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.BATTLEFIELD, card.owner_id)
			if back != null and bool(p.get("under_my_control", false)):
				back.controller_id = entry.controller_id
		"LIBRARY_TOP":
			engine.state.zones.move(card.object_id, EngineEnums.ZoneId.LIBRARY, card.owner_id)
		"LIBRARY_BOTTOM":
			var low: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.LIBRARY, card.owner_id)
			if low != null:
				engine.put_library_bottom(low.object_id, card.owner_id)


## "Regenerate / untap / tap / exile / destroy / sacrifice / return enchanted creature": the permanent this is attached to.
static func _attached_act(engine: RulesEngine, source: GameObject, act: String) -> void:
	if source == null:
		return
	var host_id := source.attached_to if source.attached_to != 0 else source.aura_host_left
	var host: GameObject = engine.state.objects.get(host_id)
	if host == null or host.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	match act:
		"regenerate":
			host.regen_shields += 1
		"untap":
			host.tapped = false
		"tap":
			host.tapped = true
		"exile":
			engine.state.zones.move(host.object_id, EngineEnums.ZoneId.EXILE, host.owner_id)
		"destroy":
			engine.destroy_permanent(host)
		"sacrifice":
			engine.state.zones.move(host.object_id, EngineEnums.ZoneId.GRAVEYARD, host.owner_id)
		"bounce":
			engine.state.zones.move(host.object_id, EngineEnums.ZoneId.HAND, host.owner_id)
	if engine.sba != null:
		engine.sba.check(engine)


## "Return the exiled card to the battlefield under its owner's control" (the older Oblivion Ring wording): every card this
## permanent exiled comes back.
static func _return_exiled(engine: RulesEngine, source: GameObject, to: String) -> void:
	if source == null:
		return
	var ids: Array = source.imprinted.duplicate()
	ids.append_array(engine.state.exile_links.get(source.object_id, []))
	for oid in ids:
		var card: GameObject = engine.state.objects.get(int(oid))
		if card == null or card.zone != EngineEnums.ZoneId.EXILE:
			continue
		engine.state.zones.move(card.object_id, EngineEnums.ZoneId.HAND if to == "HAND" else EngineEnums.ZoneId.BATTLEFIELD, card.owner_id)
	source.imprinted.clear()


static func _tap_or_untap(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var obj := ex._object_ref(engine, entry, source, p.get("target", 0))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var options := [{"value": "tap", "label": "Tap it", "detail": ""}, {"value": "untap", "label": "Untap it", "detail": ""}]
	var ans := ex._ask(engine, entry, entry.controller_id, "tap_or_untap", "Tap or untap %s?" % ex._name_of(engine, obj.object_id), options)
	if ans.s == "paused":
		return
	var tap: bool
	if ans.s == "picked":
		tap = str(ans.value) == "tap"
	else:
		tap = obj.controller_id != entry.controller_id  ## the bot taps the rival's things and untaps its own
	obj.tapped = tap


## "Look at / reveal the top card of your library. If it's a creature card, you may put it into your hand. If you don't, put it
## on the bottom of your library." p: filter (Query on the card), to, tapped, may, else_to, else_may.
static func _top_card_decide(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or lib.is_empty():
		return
	var card: GameObject = engine.state.objects.get(int(lib.object_ids[0]))
	if card == null:
		return
	var fits := true
	var flt: Variant = p.get("filter", {})
	if flt is Dictionary and not (flt as Dictionary).is_empty():
		fits = Query._matches(card, source, flt as Dictionary)
	var name := ex._name_of(engine, card.object_id)
	if bool(p.get("reveal", false)):
		engine.state.log.append(EngineEnums.EventType.NOTE, pid, {text = "Revealed from the top of the library: %s." % name})
	var done := false
	if fits:
		var go := true
		if bool(p.get("may", true)):
			var ans := ex._ask_yes_no(engine, entry, pid, "top_main", "%s: %s?" % [name, _where_text(str(p.get("to", "HAND")))], [card.object_id])
			if ans.s == "paused":
				return
			go = bool(ans.value) if ans.s == "picked" else _bot_wants(engine, card, str(p.get("to", "HAND")))
		if go:
			_move_top(engine, card, str(p.get("to", "HAND")), bool(p.get("tapped", false)), pid)
			done = true
	if done or str(p.get("else_to", "")) == "":
		return
	var go_else := true
	if bool(p.get("else_may", false)):
		var ans2 := ex._ask_yes_no(engine, entry, pid, "top_else", "%s: %s?" % [name, _where_text(str(p.get("else_to", "")))], [card.object_id])
		if ans2.s == "paused":
			return
		go_else = bool(ans2.value) if ans2.s == "picked" else _bot_wants(engine, card, str(p.get("else_to", "")))
	if go_else:
		_move_top(engine, card, str(p.get("else_to", "")), false, pid)


static func _where_text(to: String) -> String:
	return {"HAND": "put it into your hand", "BATTLEFIELD": "put it onto the battlefield", "GRAVEYARD": "put it into your graveyard",
		"BOTTOM": "put it on the bottom of your library", "EXILE": "exile it"}.get(to, "move it")


## What the bot does with a top card it may move: keep good cards, bin lands it doesn't need on top.
static func _bot_wants(engine: RulesEngine, card: GameObject, to: String) -> bool:
	var is_land := card.definition is CardDefinition and (card.definition as CardDefinition).is_land()
	if to == "HAND" or to == "BATTLEFIELD":
		return true
	return is_land


static func _move_top(engine: RulesEngine, card: GameObject, to: String, tapped: bool, pid: int) -> void:
	match to:
		"HAND":
			engine.state.zones.move(card.object_id, EngineEnums.ZoneId.HAND, pid)
		"BATTLEFIELD":
			var bo: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.BATTLEFIELD, pid)
			if bo != null and tapped:
				bo.tapped = true
		"GRAVEYARD":
			engine.state.zones.move(card.object_id, EngineEnums.ZoneId.GRAVEYARD, pid)
		"EXILE":
			engine.state.zones.move(card.object_id, EngineEnums.ZoneId.EXILE, pid)
		"BOTTOM":
			engine.put_library_bottom(card.object_id, pid)


## "Target creature you control gains protection from the color of your choice until end of turn."
static func _protect_color_choice(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var obj := ex._object_ref(engine, entry, source, p.get("target", 0)) if p.has("target") else source
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	## The bot picks the colour the rival's creatures and spells use most.
	var tally := {}
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id != entry.controller_id and o.definition is CardDefinition:
			for c in (o.definition as CardDefinition).colors:
				tally[str(c)] = int(tally.get(str(c), 0)) + 1
	var best := "R"
	for c2 in tally.keys():
		if int(tally[c2]) > int(tally.get(best, 0)):
			best = str(c2)
	var options: Array = []
	for c3 in ["W", "U", "B", "R", "G"]:
		options.append({"value": c3, "label": COLOR_NAMES[c3], "detail": ""})
	var ans := ex._ask(engine, entry, entry.controller_id, "protect_color", "Protection from which color?", options)
	if ans.s == "paused":
		return
	var color := str(ans.value) if ans.s == "picked" else best
	var pump := AbilityEffect.new()
	pump.kind = &"PUMP"
	pump.params = {"keywords": ["Protection from %s" % COLOR_NAMES[color].to_lower()], "duration": str(p.get("duration", "END_OF_TURN"))}
	if obj == source:
		pump.params["self"] = true
	else:
		pump.params["target"] = p.get("target", 0)
	ex._apply(engine, entry, source, pump)
