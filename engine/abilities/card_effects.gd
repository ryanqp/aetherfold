class_name CardEffects
extends RefCounted

## Effects that more than one card needs but that don't fit AbilityExecutor's basic list: modal spells, optional
## payments, free casts from hand / library / exile, copy effects, riot, graveyard-exile riders.
## Called by AbilityExecutor for kinds it doesn't know (after KeywordEffects). An effect that asks the player
## something asks first and changes the game after: a paused effect runs again from its start once answered.

const KINDS := ["MODAL", "POWER_DAMAGE_EACH", "CAST_FREE_FROM_HAND", "PAY_OPTIONAL", "GRANT_FLASH",
	"GAIN_KEYWORD_CHOICE", "BECOME_COPY", "EXILE_CARD", "GRAVEYARD_EXILED_WITH", "REVEAL_TOP_CAST_FREE",
	"EXILE_TOP_EACH_CAST_FREE", "RIOT"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func apply(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	match str(fx.kind):
		"MODAL":
			_modal(ex, engine, entry, source, fx)
		"POWER_DAMAGE_EACH":
			_power_damage_each(ex, engine, entry, source, fx)
		"CAST_FREE_FROM_HAND":
			_cast_free_from_hand(ex, engine, entry, fx)
		"PAY_OPTIONAL":
			_pay_optional(ex, engine, entry, fx)
		"GRANT_FLASH":
			if source != null and source.chosen_type != "":
				engine.state.flash_grants.append({"pid": entry.controller_id, "subtype": source.chosen_type, "turn": engine.state.turn_number})
		"GAIN_KEYWORD_CHOICE":
			_gain_keyword_choice(ex, engine, entry, source, fx)
		"BECOME_COPY":
			_become_copy(ex, engine, entry, source, fx)
		"EXILE_CARD":
			_exile_card(ex, engine, entry, source, fx)
		"GRAVEYARD_EXILED_WITH":
			_graveyard_exiled_with(ex, engine, entry, source)
		"REVEAL_TOP_CAST_FREE":
			_reveal_top_cast_free(ex, engine, entry)
		"EXILE_TOP_EACH_CAST_FREE":
			_exile_top_each_cast_free(ex, engine, entry)
		"RIOT":
			_riot(ex, engine, entry)


# --- Modal spells (CR 700.2) ----------------------------------------------------------------------------

## "Choose one / three. You may choose the same mode more than once. If you control a commander, you may choose
## both instead." The modes are picked as the spell resolves (targets of a mode too), then run in printed order.
static func _modal(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var modes: Array = fx.params.get("modes", [])
	if modes.is_empty():
		return
	var choose := mini(int(fx.params.get("choose", 1)), modes.size() if not bool(fx.params.get("repeat", false)) else 99)
	## Escalate (CR 702.120): the number of modes was chosen, and paid for, as the spell was cast.
	if entry.ctx.has("modes_n"):
		choose = clampi(int(entry.ctx["modes_n"]), 1, modes.size())
	## "Choose one or more" / "one or both" with no escalate: after the first mode the rest are optional.
	var up_to := int(fx.params.get("any_up_to", 0))
	if entry.ctx.has("modes_n"):
		up_to = 0
	var picks: Array = []
	## Spree / tiered: the modes were picked as it was cast.
	if entry.ctx.has("modes_fixed"):
		for i in entry.ctx["modes_fixed"]:
			if int(i) >= 0 and int(i) < modes.size():
				picks.append(int(i))
		choose = 0
		up_to = 0
	var both := false
	if bool(fx.params.get("both_if_commander", false)) and modes.size() == 2 and _controls_commander(engine, pid):
		var yn := ex._ask_yes_no(engine, entry, pid, "both_modes", "You control a commander: choose both modes?")
		if yn.s == "paused":
			return
		both = true if yn.s == "auto" else bool(yn.value)
	if both:
		for i in modes.size():
			picks.append(i)
	else:
		for n in choose:
			var options: Array = []
			for i in modes.size():
				if picks.has(i) and not bool(fx.params.get("repeat", false)):
					continue
				options.append({"value": i, "label": _short(str((modes[i] as Dictionary).get("text", "Mode"))), "detail": str((modes[i] as Dictionary).get("text", ""))})
			if options.is_empty():
				break
			var ans := ex._ask(engine, entry, pid, "mode_%d" % n, "Choose a mode (%d of %d)." % [n + 1, choose], options)
			if ans.s == "paused":
				return
			picks.append(int(ans.value) if ans.s == "picked" else _auto_mode(modes, picks, bool(fx.params.get("repeat", false))))
		## Further optional modes ("one or both", "one or more").
		var extra_n := 0
		while up_to > picks.size() and extra_n < 6:
			extra_n += 1
			var more: Array = []
			for i2 in modes.size():
				if not picks.has(i2):
					more.append({"value": i2, "label": _short(str((modes[i2] as Dictionary).get("text", "Mode"))), "detail": str((modes[i2] as Dictionary).get("text", ""))})
			if more.is_empty():
				break
			var ans2 := ex._ask(engine, entry, pid, "mode_more_%d" % extra_n, "Choose another mode? (%d chosen)" % picks.size(), more, true)
			if ans2.s == "paused":
				return
			if ans2.s != "picked":
				break
			picks.append(int(ans2.value))
		picks.sort()
	## Targets of each chosen mode.
	var chosen_targets: Array = []
	for k in picks.size():
		var mode: Dictionary = modes[int(picks[k])]
		var specs: Array = mode.get("targets", [])
		var ids: Array = []
		var hostile := TargetingManager.effects_hostile(_effects_of(mode))
		for j in specs.size():
			var spec: Dictionary = specs[j]
			var legal: Array = engine.targeting.legal_ids(engine, spec, source.object_id if source != null else -1)
			for taken in ids:
				legal.erase(taken)
			if legal.is_empty():
				ids.append(-1)
				continue
			var slot_hostile := TargetingManager.slot_hostile(spec, hostile)
			var best := -1
			var best_score := -1000000
			var options2: Array = []
			for tid in legal:
				var sc := TargetingManager.auto_score(engine, int(tid), pid, slot_hostile)
				if sc > best_score:
					best_score = sc
					best = int(tid)
				options2.append(_target_option(ex, engine, int(tid), pid))
			var tans := ex._ask(engine, entry, pid, "mt_%d_%d" % [k, j], "Choose a target.", options2)
			if tans.s == "paused":
				return
			ids.append(int(tans.value) if tans.s == "picked" else best)
		chosen_targets.append(ids)
	## Everything is decided: run the modes.
	var saved: Array = entry.targets.duplicate()
	for k2 in picks.size():
		var mode2: Dictionary = modes[int(picks[k2])]
		entry.targets = (chosen_targets[k2] as Array).duplicate()
		for raw in mode2.get("effects", []):
			var d: Dictionary = raw
			var f := AbilityEffect.new()
			f.kind = StringName(str(d.get("kind", "")))
			f.params = (d.get("params", {}) as Dictionary).duplicate(true)
			ex._apply(engine, entry, source, f)
	entry.targets = saved


static func _effects_of(mode: Dictionary) -> Array:
	var out: Array = []
	for raw in mode.get("effects", []):
		var f := AbilityEffect.new()
		f.kind = StringName(str((raw as Dictionary).get("kind", "")))
		f.params = ((raw as Dictionary).get("params", {}) as Dictionary).duplicate(true)
		out.append(f)
	return out


static func _short(t: String) -> String:
	return t if t.length() <= 70 else t.substr(0, 67) + "..."


static func _controls_commander(engine: RulesEngine, pid: int) -> bool:
	for cid in engine.state.players[pid].commander_ids:
		var c: GameObject = engine.state.objects.get(cid)
		if c != null and c.zone == EngineEnums.ZoneId.BATTLEFIELD and c.controller_id == pid:
			return true
	return false


## The rival's pick: damage to the opponent first, then drawing, then anything else; repeats the best mode.
static func _auto_mode(modes: Array, taken: Array, repeat: bool) -> int:
	var best := 0
	var best_score := -1
	for i in modes.size():
		if taken.has(i) and not repeat:
			continue
		var score := 0
		for raw in (modes[i] as Dictionary).get("effects", []):
			var d: Dictionary = raw
			var kind := str(d.get("kind", ""))
			var params: Dictionary = d.get("params", {})
			if kind == "DEAL_DAMAGE" and str(params.get("who", "")) == "EACH_OPPONENT":
				score += 4
			elif kind == "DRAW":
				score += 3
			elif kind == "PUMP":
				score += 2
			elif kind == "DEAL_DAMAGE_EACH":
				score += 1
			else:
				score += 1
		if score > best_score:
			best_score = score
			best = i
	return best


static func _target_option(ex: AbilityExecutor, engine: RulesEngine, tid: int, me: int) -> Dictionary:
	var pid := TargetingManager.decode_player(tid)
	if pid >= 0:
		return {"value": tid, "label": "You" if pid == me else "Opponent", "detail": "Player"}
	return ex._card_option(engine, tid)


# --- One-card effects -------------------------------------------------------------------------------------

## "Target creature you control deals damage equal to its power to each other creature and each opponent."
static func _power_damage_each(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var dealer := ex._object_ref(engine, entry, source, fx.params.get("source", 0))
	if dealer == null or dealer.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var dmg := engine.power_of(dealer)
	if dmg <= 0:
		return
	var victims: Array = []
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf != null:
		for oid in bf.object_ids:
			var o: GameObject = engine.state.objects.get(oid)
			if o != null and o.object_id != dealer.object_id and engine.is_creature_now(o):
				victims.append(o)
	for v in victims:
		engine.damage_object(dealer, v, dmg)
	for p in engine.state.players:
		if p.player_id != entry.controller_id and not p.lost:
			ex._damage_player(engine, entry, p.player_id, dmg)
	if engine.sba != null:
		engine.sba.check(engine)


## "You may cast a spell with mana value N or less from your hand without paying its mana cost."
static func _cast_free_from_hand(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null:
		return
	var limit := int(fx.params.get("max_mv", 0))
	var cands: Array = []
	for oid in hand.object_ids:
		var c: GameObject = engine.state.objects.get(oid)
		if c != null and c.definition is CardDefinition:
			var d := c.definition as CardDefinition
			if not d.is_land() and d.cmc <= limit:
				cands.append(int(oid))
	if cands.is_empty():
		return
	var options: Array = []
	for oid in cands:
		options.append(ex._card_option(engine, int(oid)))
	var ans := ex._ask(engine, entry, pid, "free_hand", "Cast a spell with mana value %d or less for free?" % limit, options, true)
	if ans.s == "paused" or ans.s == "declined":
		return
	if ans.s == "picked":
		engine.cast_free(pid, int(ans.value))
		return
	## The rival casts the most expensive card it can.
	cands.sort_custom(func(a, b) -> bool: return (engine.state.objects[a].definition as CardDefinition).cmc > (engine.state.objects[b].definition as CardDefinition).cmc)
	for oid in cands:
		if engine.cast_free(pid, int(oid)):
			return


## "You may pay {G}. If you do, ...": records whether the cost was paid in entry.choices[link] for if_link effects.
static func _pay_optional(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var link := str(fx.params.get("link", "paid"))
	var cost := ManaCost.parse(str(fx.params.get("cost", "")))
	if not engine.can_afford(pid, cost):
		entry.choices[link] = false
		return
	var ans := ex._ask_yes_no(engine, entry, pid, link + "_q", "Pay %s?" % cost.to_text())
	if ans.s == "paused":
		return
	var yes := true if ans.s == "auto" else bool(ans.value)
	entry.choices[link] = yes and engine.pay_now(pid, cost)


## "{G}: ~ gains your choice of reach, trample, or haste until end of turn."
static func _gain_keyword_choice(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var opts: Array = fx.params.get("options", [])
	var options: Array = []
	for o in opts:
		options.append({"value": str(o), "label": str(o), "detail": ""})
	var ans := ex._ask(engine, entry, entry.controller_id, "kw_choice", "Choose a keyword.", options)
	if ans.s == "paused":
		return
	var pick := str(ans.value) if ans.s == "picked" else ("Trample" if opts.has("Trample") else str(opts[0]))
	var pump := AbilityEffect.new()
	pump.kind = &"PUMP"
	pump.params = {"self": true, "keywords": [pick], "duration": "END_OF_TURN"}
	ex._apply(engine, entry, source, pump)


## Layer 1 (CR 707): the source becomes a copy of the target, keeping its name and this ability.
static func _become_copy(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var target := ex._object_ref(engine, entry, source, fx.params.get("target", 0))
	if target == null or target.zone != EngineEnums.ZoneId.BATTLEFIELD or target.object_id == source.object_id or not (target.definition is CardDefinition):
		return
	var ans := ex._ask_yes_no(engine, entry, entry.controller_id, "copy_it", "Have %s become a copy of %s?" % [ex._name_of(engine, source.object_id), ex._name_of(engine, target.object_id)], [target.object_id])
	if ans.s == "paused":
		return
	if ans.s == "picked" and not bool(ans.value):
		return
	if ans.s == "auto" and engine.power_of(target) <= engine.power_of(source):
		return
	var effect := ContinuousEffect.new()
	effect.object_ids = [source.object_id]
	effect.source_id = source.object_id
	effect.controller_id = entry.controller_id
	effect.until_eot = false
	effect.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	effect.copy_def = target.definition as CardDefinition
	effect.keep_ability_ids = [str(entry.ability_id)]
	engine.state.effects.append(effect)
	if engine.sba != null:
		engine.sba.check(engine)


## Exile a card from a graveyard; remembers whether it was a creature card (Deathgorge Scavenger's riders).
static func _exile_card(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var card := ex._object_ref(engine, entry, source, fx.params.get("target", 0))
	if card == null or card.zone != EngineEnums.ZoneId.GRAVEYARD or not (card.definition is CardDefinition):
		return
	var is_creature := (card.definition as CardDefinition).is_creature()
	var moved: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.EXILE, card.owner_id)
	if moved != null:
		entry.ctx["exiled_creature"] = is_creature
		entry.ctx["exiled_noncreature"] = not is_creature


## Bronzebeak Foragers: "Put target card with mana value X exiled with ~ into its owner's graveyard. You gain X life."
## X is known only when the ability is paid for, so the card is picked as it resolves. With no such card X becomes 0.
static func _graveyard_exiled_with(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null:
		return
	var x := int(entry.ctx.get("x", 0))
	var linked: Array = engine.state.exile_links.get(source.object_id, [])
	var cands: Array = []
	for oid in linked:
		var c: GameObject = engine.state.objects.get(int(oid))
		if c != null and c.zone == EngineEnums.ZoneId.EXILE and c.definition is CardDefinition and (c.definition as CardDefinition).cmc == x:
			cands.append(int(oid))
	if cands.is_empty():
		entry.ctx["x"] = 0
		return
	var pick := int(cands[0])
	if cands.size() > 1:
		var options: Array = []
		for oid in cands:
			options.append(ex._card_option(engine, int(oid)))
		var ans := ex._ask(engine, entry, entry.controller_id, "exiled_with", "Choose a card exiled with %s." % ex._name_of(engine, source.object_id), options)
		if ans.s == "paused":
			return
		if ans.s == "picked":
			pick = int(ans.value)
	var card: GameObject = engine.state.objects.get(pick)
	linked.erase(pick)
	engine.state.exile_links[source.object_id] = linked
	engine.state.zones.move(pick, EngineEnums.ZoneId.GRAVEYARD, card.owner_id)


## Descendants' Path: reveal the top card; a creature card that shares a creature type with a creature you control
## may be cast for free; otherwise it goes to the bottom of the library.
static func _reveal_top_cast_free(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or lib.is_empty():
		return
	var top_id := int(lib.object_ids[0])
	var top: GameObject = engine.state.objects.get(top_id)
	if top == null or not (top.definition is CardDefinition):
		return
	var def := top.definition as CardDefinition
	var qualifies := false
	if def.is_creature():
		var mine := Query._subtype_words(def.type_line)
		var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf != null:
			for oid in bf.object_ids:
				var o: GameObject = engine.state.objects.get(oid)
				if o == null or o.controller_id != pid or not engine.is_creature_now(o) or not (o.definition is CardDefinition):
					continue
				var theirs: PackedStringArray = Query._subtype_words((o.definition as CardDefinition).type_line)
				for t in theirs:
					if mine.has(t):
						qualifies = true
				if Query._is_changeling(def, def.type_line) or Query._is_changeling(o.definition as CardDefinition, (o.definition as CardDefinition).type_line):
					qualifies = true
	if qualifies:
		var ans := ex._ask_yes_no(engine, entry, pid, "reveal_cast", "%s shares a creature type with one of yours. Cast it without paying its mana cost? (No puts it on the bottom of your library.)" % def.name, [top_id])
		if ans.s == "paused":
			return
		if (ans.s == "auto" or bool(ans.value)) and engine.cast_free(pid, top_id):
			return
	engine.put_library_bottom(top_id, pid)


## Etali: exile the top card of each player's library, then cast any number of the spells for free.
static func _exile_top_each_cast_free(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	if not entry.ctx.has("et_ids"):
		var ids: Array = []
		for p in engine.state.players:
			var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, p.player_id)
			if lib == null or lib.is_empty():
				continue
			var moved: GameObject = engine.state.zones.move(int(lib.object_ids[0]), EngineEnums.ZoneId.EXILE, p.player_id)
			if moved != null:
				ids.append(moved.object_id)
		entry.ctx["et_ids"] = ids
	var done: Array = entry.ctx.get("et_done", [])
	for oid in entry.ctx["et_ids"]:
		if done.has(oid):
			continue
		var c: GameObject = engine.state.objects.get(int(oid))
		if c == null or c.zone != EngineEnums.ZoneId.EXILE or not (c.definition is CardDefinition) or (c.definition as CardDefinition).is_land():
			done.append(oid)
			entry.ctx["et_done"] = done
			continue
		var ans := ex._ask_yes_no(engine, entry, pid, "et_%d" % int(oid), "Cast %s without paying its mana cost?" % (c.definition as CardDefinition).name, [int(oid)])
		if ans.s == "paused":
			return
		if ans.s == "auto" or bool(ans.value):
			engine.cast_free(pid, int(oid))
		done.append(oid)
		entry.ctx["et_done"] = done


## Riot (CR 702.136): the creature enters with your choice of a +1/+1 counter or haste.
static func _riot(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var obj: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var ans := ex._ask_yes_no(engine, entry, entry.controller_id, "riot", "Riot: put a +1/+1 counter on %s? (No: it gains haste.)" % ex._name_of(engine, obj.object_id), [obj.object_id])
	if ans.s == "paused":
		return
	if ans.s == "auto" or bool(ans.value):
		obj.counters["+1/+1"] = int(obj.counters.get("+1/+1", 0)) + 1
	else:
		obj.granted_haste = true
