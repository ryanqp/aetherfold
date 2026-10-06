class_name PreconEffects
extends RefCounted

## Effects for the keywords and keyword actions of the Commander precon decks: Auras attaching, living weapon,
## behold, clash, empower, double, demonstrate, gift, read ahead (Sagas), loyalty-ability effects (put cards back,
## reveal until, blink, emblems), pack tactics and Angelic Destiny's return. Called by AbilityExecutor for kinds it
## doesn't know. An effect that asks the player something asks first and changes the game after: a paused effect
## runs again from its start once answered (answers are kept in entry.choices).

const KINDS := ["AURA_ATTACH", "LIVING_WEAPON", "BEHOLD", "CLASH", "EMPOWER", "DOUBLE_PT", "HAND_TO_LIBRARY",
	"REVEAL_UNTIL_PUT", "FLICKER", "DESTROY_ALL_POWER", "EMBLEM", "RETURN_CARD_CHOICE", "SACRIFICE_GREATEST",
	"PUT_FROM_HAND_ATTACKING", "RETURN_SELF_HAND", "EXILE_ALL", "DEMONSTRATE", "READ_AHEAD", "GIFT",
	"SELF_EXILE_ON_RESOLVE", "DISCARD_ANY_DRAW", "TAP_ATTACHED", "TUCK", "BOUNCE_ANY"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func apply(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	match str(fx.kind):
		"AURA_ATTACH":
			_aura_attach(engine, entry, source, fx)
		"LIVING_WEAPON":
			_living_weapon(engine, entry, source)
		"BEHOLD":
			_behold(ex, engine, entry, fx)
		"CLASH":
			_clash(ex, engine, entry, source)
		"EMPOWER":
			empower(engine, entry.controller_id, str(fx.params.get("name", "Jace")), int(fx.params.get("n", 1)))
		"DOUBLE_PT":
			_double_pt(ex, engine, entry, source, fx)
		"HAND_TO_LIBRARY":
			_hand_to_library(ex, engine, entry, fx)
		"REVEAL_UNTIL_PUT":
			_reveal_until_put(engine, entry, fx)
		"FLICKER":
			_flicker(engine, entry, fx)
		"DESTROY_ALL_POWER":
			_destroy_all_power(engine, fx)
		"EMBLEM":
			_emblem(engine, entry, fx)
		"RETURN_CARD_CHOICE":
			_return_card_choice(ex, engine, entry, fx)
		"SACRIFICE_GREATEST":
			_sacrifice_greatest(ex, engine, entry, fx)
		"PUT_FROM_HAND_ATTACKING":
			_put_from_hand_attacking(ex, engine, entry, source, fx)
		"RETURN_SELF_HAND":
			_return_self_hand(engine, source)
		"EXILE_ALL":
			_exile_all(ex, engine, entry, source, fx)
		"DEMONSTRATE":
			_demonstrate(ex, engine, entry)
		"READ_AHEAD":
			_read_ahead(ex, engine, entry, source, fx)
		"GIFT":
			_gift(engine, entry, fx)
		"SELF_EXILE_ON_RESOLVE":
			entry.ctx["exile_self"] = true
		"DISCARD_ANY_DRAW":
			_discard_any_draw(ex, engine, entry)
		"TAP_ATTACHED":
			if source != null and engine.state.objects.has(source.attached_to):
				(engine.state.objects[source.attached_to] as GameObject).tapped = true
		"TUCK":
			_tuck(ex, engine, entry, fx)
		"BOUNCE_ANY":
			_bounce_any(engine, entry, fx)


static func _def(o: GameObject) -> CardDefinition:
	return o.definition as CardDefinition if o != null and o.definition is CardDefinition else null


static func _bf_ids(engine: RulesEngine) -> Array:
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	return bf.object_ids.duplicate() if bf != null else []


static func _log_enter(engine: RulesEngine, pid: int, obj: GameObject) -> void:
	engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, pid, {
		from_id = 0, to_id = obj.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0,
	})


# --- Auras (CR 303.4, 702.5) --------------------------------------------------------------------------

## The Aura spell resolves: it will enter attached to its target if that is still legal; otherwise the spell
## doesn't resolve (CR 608.3b) and goes to the graveyard. MagicStack.resolve_top does the attaching.
static func _aura_attach(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	var host: GameObject = null
	if idx >= 0 and idx < entry.targets.size():
		host = engine.state.objects.get(int(entry.targets[idx]))
	if host == null or host.zone != EngineEnums.ZoneId.BATTLEFIELD or (source != null and engine.protected_from(host, source)):
		entry.ctx["aura_fizzle"] = true
		return
	entry.ctx["aura_target"] = host.object_id


# --- Living weapon (CR 702.92) ------------------------------------------------------------------------

static func _living_weapon(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var def := TokenCatalog.new().from_spec({"subtypes": ["Phyrexian", "Germ"], "colors": ["B"], "p": "0", "t": "0"})
	def.name = "Phyrexian Germ"
	var germ: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, {
		definition = def, is_token = true, controller_id = entry.controller_id})
	if germ == null:
		return
	_log_enter(engine, entry.controller_id, germ)
	source.attached_to = germ.object_id


# --- Behold (CR 701.4) --------------------------------------------------------------------------------

## "You may behold a Dragon": choose a Dragon you control or reveal a Dragon card from your hand. Whether you did
## is kept under the link for the "if you do" effects that follow.
static func _behold(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var link := str(fx.params.get("link", "paid"))
	var sub := str(fx.params.get("subtype", ""))
	var options: Array = []
	for oid in _bf_ids(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id == pid and (engine.layers.has_subtype(engine.state, o, sub) or engine.has_keyword(o, "Changeling")):
			var opt := ex._card_option(engine, o.object_id)
			opt["label"] = "Choose %s (on the battlefield)" % str(opt.label)
			options.append(opt)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand != null:
		for hid in hand.object_ids:
			var h: GameObject = engine.state.objects.get(hid)
			if h != null and _def(h) != null and (Query._subtype_words(_def(h).type_line).has(sub) or Query._is_changeling(_def(h), _def(h).type_line)):
				var opt2 := ex._card_option(engine, h.object_id)
				opt2["label"] = "Reveal %s from your hand" % str(opt2.label)
				options.append(opt2)
	if options.is_empty():
		entry.choices[link] = false
		return
	var ans := ex._ask(engine, entry, pid, link + "_pick", "Behold a %s?" % sub, options, true)
	if ans.s == "paused":
		return
	entry.choices[link] = ans.s != "declined"


# --- Clash (CR 701.23) --------------------------------------------------------------------------------

## Each clashing player reveals their top card and puts it on the top or bottom; you win if yours had the greater
## mana value. Winning sets off "whenever you win a clash".
static func _clash(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	var me := entry.controller_id
	var opp := -1
	if source != null:
		opp = engine.defender_of(source.object_id)
	if opp < 0:
		for p in engine.state.players:
			if p.player_id != me and not p.lost:
				opp = p.player_id
				break
	if opp < 0:
		return
	var tops := {}
	for pid in [me, opp]:
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
		tops[pid] = int(lib.object_ids[0]) if lib != null and not lib.object_ids.is_empty() else -1
	## Each player decides where their revealed card goes (the rival keeps spells and bottoms lands).
	for pid2 in [me, opp]:
		var tid := int(tops[pid2])
		if tid < 0:
			continue
		var link := "clash_bottom_%d" % pid2
		var bottom := false
		var ans := ex._ask_yes_no(engine, entry, pid2, link, "Clash: put %s on the bottom of your library? (No keeps it on top.)" % ex._name_of(engine, tid), [tid])
		if ans.s == "paused":
			return
		if ans.s == "picked":
			bottom = bool(ans.value)
		else:
			var d := _def(engine.state.objects.get(tid))
			bottom = d != null and d.is_land()
		entry.choices[link] = bottom
	var mv := {}
	for pid3 in [me, opp]:
		var t3 := int(tops[pid3])
		var d3 := _def(engine.state.objects.get(t3)) if t3 >= 0 else null
		mv[pid3] = d3.cmc if d3 != null else -1
		if t3 >= 0 and bool(entry.choices.get("clash_bottom_%d" % pid3, false)):
			engine.put_library_bottom(t3, pid3)
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, me, {clash = true, object_id = source.object_id if source != null else 0})
	if int(mv[me]) > int(mv[opp]) and engine.triggers != null:
		engine.triggers.fire_player_event(engine, "CLASH_WON", me)
	if int(mv[opp]) > int(mv[me]) and engine.triggers != null:
		engine.triggers.fire_player_event(engine, "CLASH_WON", opp)


# --- Empower (Reality Fracture) -----------------------------------------------------------------------

## "Empower Jace N": put N loyalty counters on a Jace token you control. If you don't control one, first create a
## blue Jace planeswalker token with "[−1]: Surveil 1" and "[−3]: Draw a card."
static func empower(engine: RulesEngine, pid: int, walker: String, n: int) -> GameObject:
	var token: GameObject = null
	for oid in _bf_ids(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.is_token and o.controller_id == pid and _def(o) != null and _def(o).type_line.contains("Planeswalker") \
				and Query._subtype_words(_def(o).type_line).has(walker):
			token = o
			break
	if token == null:
		var d := CardDefinition.new()
		d.name = walker
		d.type_line = "Token Planeswalker — %s" % walker
		d.oracle_text = "−1: Surveil 1.\n−3: Draw a card."
		d.loyalty = "0"
		d.colors = PackedStringArray(["U"])
		d.color_identity = PackedStringArray(["U"])
		d.abilities = OracleIr.translate_permanent(d)
		token = engine.state.zones.create(pid, EngineEnums.ZoneId.BATTLEFIELD, {definition = d, is_token = true, controller_id = pid})
		if token == null:
			return null
		_log_enter(engine, pid, token)
	token.counters["loyalty"] = int(token.counters.get("loyalty", 0)) + n
	return token


# --- Double (CR 701.10) -------------------------------------------------------------------------------

static func _double_pt(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	for o in ex._each(engine, entry, source, fx.params.get("each", {})):
		var obj: GameObject = o
		if not engine.is_creature_now(obj):
			continue
		var eff := ContinuousEffect.new()
		eff.object_ids = [obj.object_id]
		eff.source_id = source.object_id if source != null else 0
		eff.controller_id = entry.controller_id
		eff.timestamp = engine.state.next_timestamp
		engine.state.next_timestamp += 1
		eff.until_eot = true
		## Doubling gives +X/+X where X is its current power (and toughness) (CR 701.10e).
		eff.power = engine.power_of(obj)
		eff.toughness = engine.toughness_of(obj)
		engine.state.effects.append(eff)


# --- Loyalty-ability effects --------------------------------------------------------------------------

## "Put a card from your hand on the bottom (top) of your library": you choose; the rival puts back its worst card.
static func _hand_to_library(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var n := int(fx.params.get("n", 1))
	var where := str(fx.params.get("where", "bottom"))
	for i in n:
		var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
		if hand == null or hand.object_ids.is_empty():
			return
		var link := "h2l_%d" % i
		if entry.choices.has(link + "_done"):
			continue
		var options: Array = []
		for hid in hand.object_ids:
			options.append(ex._card_option(engine, int(hid)))
		var ans := ex._ask(engine, entry, pid, link, "Put a card from your hand on the %s of your library." % where, options)
		if ans.s == "paused":
			return
		var pick := int(ans.value) if ans.s == "picked" else ex._cheapest_in_hand(engine, pid, [])
		var card: GameObject = engine.state.objects.get(pick)
		if card != null and card.zone == EngineEnums.ZoneId.HAND:
			if where == "top":
				engine.state.zones.move(pick, EngineEnums.ZoneId.LIBRARY, pid)
			else:
				engine.put_library_bottom(pick, pid)
		entry.choices[link + "_done"] = true


## "Reveal cards from the top of your library until you reveal a creature or planeswalker card. Put that card onto
## the battlefield and the rest on the bottom of your library in a random order."
static func _reveal_until_put(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var types: Array = fx.params.get("types", ["creature"])
	var rest: Array = []
	var found := -1
	var guard := 0
	while not lib.object_ids.is_empty() and guard < 300:
		guard += 1
		var top_id := int(lib.object_ids[0])
		var d := _def(engine.state.objects.get(top_id))
		var hit := false
		if d != null:
			for t in types:
				var tt := str(t).to_lower()
				if (tt == "nonland" and not d.is_land()) or d.type_line.to_lower().contains(tt):
					hit = true
		lib.object_ids.remove_at(0)
		if hit:
			found = top_id
			break
		rest.append(top_id)
	engine.state.rng.shuffle(rest)
	for rid in rest:
		lib.object_ids.append(rid)
	if found < 0:
		return
	## Back in the library for a moment so the move below is an ordinary zone change.
	lib.object_ids.push_front(found)
	var to := EngineEnums.ZoneId.BATTLEFIELD if str(fx.params.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	engine.state.zones.move(found, to, pid)


## Exile a permanent, then return it to the battlefield under your control (CR 400.7: it's a new object).
static func _flicker(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var gone: GameObject = engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
	if gone == null:
		return
	engine.state.zones.move(gone.object_id, EngineEnums.ZoneId.BATTLEFIELD, entry.controller_id)


static func _destroy_all_power(engine: RulesEngine, fx: AbilityEffect) -> void:
	var need := int(fx.params.get("min", 4))
	for oid in _bf_ids(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or not engine.is_creature_now(o) or engine.power_of(o) < need:
			continue
		engine.destroy_permanent(o)


## An emblem (CR 114) that says "Creatures you control get +N/+N and have <keywords>": a continuous effect that
## never ends.
static func _emblem(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var eff := ContinuousEffect.new()
	eff.until_eot = false
	eff.controller_id = entry.controller_id
	eff.source_id = 0
	eff.query = {"type": "creature", "controller_id": entry.controller_id}
	eff.power = int(fx.params.get("power", 0))
	eff.toughness = int(fx.params.get("toughness", 0))
	for k in fx.params.get("keywords", []):
		eff.add_keywords.append(str(k))
	eff.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	engine.state.effects.append(eff)
	engine.state.emblems.append({"player_id": entry.controller_id, "text": "Creatures you control get +%d/+%d%s." % [eff.power, eff.toughness, (" and have " + ", ".join(eff.add_keywords).to_lower()) if not eff.add_keywords.is_empty() else ""]})


# --- Gift (CR 702.174) --------------------------------------------------------------------------------

## The promised gift: the opponent draws a card (gift a card) or gets the token.
static func _gift(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var kind := str(fx.params.get("kind", "card"))
	for p in engine.state.players:
		if p.player_id == entry.controller_id or p.lost:
			continue
		match kind:
			"card", "extra card":
				engine.draw_card(p.player_id)
			"treasure", "food", "clue":
				var d := TokenCatalog.new().definition_for(kind)
				var t: GameObject = engine.state.zones.create(p.player_id, EngineEnums.ZoneId.BATTLEFIELD, {definition = d, is_token = true, controller_id = p.player_id})
				if t != null:
					_log_enter(engine, p.player_id, t)
		break


## "Return target creature card from your graveyard to your hand" when the gift was promised (Consumed by Greed).
## The card is picked as the spell resolves, so a cast without the gift needs no graveyard target.
static func _return_card_choice(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, pid)
	if gy == null:
		return
	var ty := str(fx.params.get("type", "creature"))
	var options: Array = []
	var best := -1
	var best_mv := -1
	for gid in gy.object_ids:
		var d := _def(engine.state.objects.get(gid))
		if d != null and d.type_line.to_lower().contains(ty):
			options.append(ex._card_option(engine, int(gid)))
			if d.cmc > best_mv:
				best_mv = d.cmc
				best = int(gid)
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "return_card", "Return a %s card from your graveyard to your hand." % ty, options)
	if ans.s == "paused":
		return
	var pick := int(ans.value) if ans.s == "picked" else best
	var to := EngineEnums.ZoneId.BATTLEFIELD if str(fx.params.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	if engine.state.objects.has(pick):
		engine.state.zones.move(pick, to, pid)


## "Target opponent sacrifices a creature with the greatest power among creatures they control." They pick among tied.
static func _sacrifice_greatest(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	var opp := -1
	if idx >= 0 and idx < entry.targets.size():
		opp = TargetingManager.decode_player(int(entry.targets[idx]))
	if opp < 0:
		return
	var top := -1000
	var tied: Array = []
	for oid in _bf_ids(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != opp or not engine.is_creature_now(o):
			continue
		var pw := engine.power_of(o)
		if pw > top:
			top = pw
			tied = [o.object_id]
		elif pw == top:
			tied.append(o.object_id)
	if tied.is_empty():
		return
	var pick := int(tied[0])
	if tied.size() > 1:
		var options: Array = []
		for t in tied:
			options.append(ex._card_option(engine, int(t)))
		var ans := ex._ask(engine, entry, opp, "sac_greatest", "Sacrifice one of your creatures with the greatest power.", options)
		if ans.s == "paused":
			return
		if ans.s == "picked":
			pick = int(ans.value)
	var victim: GameObject = engine.state.objects.get(pick)
	if victim != null and victim.zone == EngineEnums.ZoneId.BATTLEFIELD:
		engine.state.zones.move(pick, EngineEnums.ZoneId.GRAVEYARD, victim.owner_id)


# --- Pack tactics payoff, Angelic Destiny, Sunfall ------------------------------------------------------

## "You may put a Dragon creature card from your hand onto the battlefield tapped and attacking." (CR 506.3)
static func _put_from_hand_attacking(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var sub := str(fx.params.get("subtype", ""))
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null:
		return
	var options: Array = []
	var best := -1
	var best_mv := -1
	for hid in hand.object_ids:
		var d := _def(engine.state.objects.get(hid))
		if d != null and d.is_creature() and (sub == "" or Query._subtype_words(d.type_line).has(sub)):
			options.append(ex._card_option(engine, int(hid)))
			if d.cmc > best_mv:
				best_mv = d.cmc
				best = int(hid)
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "put_attacking", "Put a %s from your hand onto the battlefield tapped and attacking?" % (sub if sub != "" else "creature"), options, true)
	if ans.s == "paused" or ans.s == "declined":
		return
	var pick := int(ans.value) if ans.s == "picked" else best
	var landed: GameObject = engine.state.zones.move(pick, EngineEnums.ZoneId.BATTLEFIELD, pid)
	if landed == null:
		return
	landed.tapped = true
	if engine.state.combat is CombatState:
		var cs := engine.state.combat as CombatState
		cs.attacker_ids.append(landed.object_id)
		var defender := cs.defending_player_id
		if source != null and cs.defenders.has(source.object_id):
			defender = int(cs.defenders[source.object_id])
		cs.defenders[landed.object_id] = defender


## Angelic Destiny: back from the graveyard to its owner's hand.
static func _return_self_hand(engine: RulesEngine, source: GameObject) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.GRAVEYARD:
		return
	engine.state.zones.move(source.object_id, EngineEnums.ZoneId.HAND, source.owner_id)


static func _exile_all(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := 0
	for o in ex._each(engine, entry, source, fx.params.get("query", {})):
		var obj: GameObject = o
		if engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id) != null or obj.is_token:
			n += 1
	entry.ctx["exiled_count"] = n


# --- Demonstrate (CR 702.144) -------------------------------------------------------------------------

## "When you cast this spell, you may copy it. If you do, choose an opponent to also copy it."
static func _demonstrate(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var spell_id := int(entry.ctx.get("spell_stack_id", 0))
	var spell: StackEntry = null
	for e in (engine.state.stack as MagicStack).entries:
		if (e as StackEntry).stack_id == spell_id:
			spell = e
	if spell == null:
		return
	var pid := entry.controller_id
	var ans := ex._ask_yes_no(engine, entry, pid, "demonstrate", "Demonstrate: copy %s? (If you do, your opponent copies it too.)" % ex._name_of(engine, spell.object_id), [spell.object_id])
	if ans.s == "paused":
		return
	if ans.s == "picked" and not bool(ans.value):
		return
	var opp := -1
	for p in engine.state.players:
		if p.player_id != pid and not p.lost:
			opp = p.player_id
			break
	## The opponent's copy goes on the stack first, so yours resolves first (CR 702.144a, 707.10).
	if opp >= 0:
		copy_spell(engine, spell, opp)
	copy_spell(engine, spell, pid)


## Puts a copy of a spell on the stack under `controller` (CR 707.10), with targets picked for that player.
static func copy_spell(engine: RulesEngine, spell: StackEntry, controller: int) -> StackEntry:
	var obj: GameObject = engine.state.objects.get(spell.object_id)
	var def := _def(obj)
	var copy := StackEntry.new()
	copy.stack_id = engine.state.next_stack_id
	engine.state.next_stack_id += 1
	copy.kind = StackEntry.Kind.SPELL
	copy.object_id = 0
	copy.source_id = spell.object_id
	copy.controller_id = controller
	copy.ability_id = spell.ability_id
	copy.effects = spell.effects.duplicate()
	copy.ctx = spell.ctx.duplicate()
	copy.ctx["copy"] = true
	var sp: Ability = def.spell_ability() if def != null else null
	if sp != null and engine.targeting != null:
		var hostile := TargetingManager.effects_hostile(sp.effects)
		for slot in sp.targets:
			var tid := engine.targeting.auto_pick(engine, slot, spell.object_id, controller, TargetingManager.slot_hostile(slot, hostile), copy.targets)
			if tid < 0 and not bool((slot as Dictionary).get("optional", false)):
				return null
			copy.targets.append(tid)
	(engine.state.stack as MagicStack).push(copy)
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, controller, {object_id = spell.object_id, stack_id = copy.stack_id, copy = true})
	return copy


# --- Sagas: read ahead (CR 714.3d) --------------------------------------------------------------------

## As a read-ahead Saga enters, its controller chooses a chapter; it gets that many lore counters and only that
## chapter triggers.
static func _read_ahead(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var final := int(fx.params.get("final", 3))
	var options: Array = []
	var numerals := ["I", "II", "III", "IV", "V", "VI"]
	for c in range(1, final + 1):
		var text := ""
		for a in _def(source).abilities:
			var ab := a as Ability
			if ab != null and str(ab.trigger.get("on", "")) == "CHAPTER" and (ab.trigger.get("chapters", []) as Array).has(c):
				text = ab.text
		options.append({"value": c, "label": "Chapter %s" % numerals[c - 1], "detail": text})
	var ans := ex._ask(engine, entry, entry.controller_id, "read_ahead", "Read ahead: start %s at which chapter?" % ex._name_of(engine, source.object_id), options)
	if ans.s == "paused":
		return
	var chosen := int(ans.value) if ans.s == "picked" else 1
	engine.triggers.add_lore(engine, source, chosen, true)


# --- More precon effects --------------------------------------------------------------------------------

## "Discard any number of cards, then draw that many cards." Cards are picked one at a time; "Done" stops.
static func _discard_any_draw(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var n := int(entry.ctx.get("dad_n", 0))
	var guard := 0
	while guard < 20:
		guard += 1
		var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
		if hand == null or hand.object_ids.is_empty():
			break
		var link := "dad_%d" % n
		var options: Array = []
		for hid in hand.object_ids:
			options.append(ex._card_option(engine, int(hid)))
		var ans := ex._ask(engine, entry, pid, link, "Discard a card to draw one? (%d discarded so far)" % n, options, true)
		if ans.s == "paused":
			return
		if ans.s == "auto":
			## The rival trades away its lands beyond the fifth and nothing else.
			var lands := Query.count_objects(engine.state, ex._ref(entry, null), {"controller": "SOURCE_CONTROLLER", "type": "land"})
			var pick := -1
			if lands >= 5:
				for hid2 in hand.object_ids:
					var d := _def(engine.state.objects.get(hid2))
					if d != null and d.is_land():
						pick = int(hid2)
						break
			if pick < 0:
				break
			engine.discard_card(pid, pick)
			n += 1
			entry.ctx["dad_n"] = n
			continue
		if ans.s != "picked":
			break
		engine.discard_card(pid, int(ans.value))
		n += 1
		entry.ctx["dad_n"] = n
	for _i in n:
		engine.draw_card(pid)
	entry.ctx["dad_n"] = 0


## "The owner of target nonland permanent puts it on their choice of the top or bottom of their library."
static func _tuck(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var obj: GameObject = null
	if bool(fx.params.get("self", false)):
		obj = engine.state.objects.get(entry.source_id)
	else:
		var idx := int(fx.params.get("target", 0))
		if idx < 0 or idx >= entry.targets.size() or int(entry.targets[idx]) < 0:
			return
		obj = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var owner := obj.owner_id
	var where := str(fx.params.get("where", ""))
	if where == "":
		var ans := ex._ask(engine, entry, owner, "tuck", "Put %s on the top or the bottom of your library?" % ex._name_of(engine, obj.object_id),
			[{"value": "top", "label": "Top of library"}, {"value": "bottom", "label": "Bottom of library"}])
		if ans.s == "paused":
			return
		where = str(ans.value) if ans.s == "picked" else "top"
	var moved: GameObject = engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.LIBRARY, owner)
	if moved != null and where == "bottom":
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, owner)
		lib.object_ids.erase(moved.object_id)
		lib.object_ids.append(moved.object_id)


## "Return target spell or creature to its owner's hand."
static func _bounce_any(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var tid := int(entry.targets[idx])
	if tid >= TargetingManager.STACK_ID_BASE:
		var sid := tid - TargetingManager.STACK_ID_BASE
		for e in (engine.state.stack as MagicStack).entries:
			var se := e as StackEntry
			if se.stack_id == sid and se.object_id != 0:
				var spell: GameObject = engine.state.objects.get(se.object_id)
				(engine.state.stack as MagicStack).remove_by_stack_id(sid)
				if spell != null:
					engine.state.zones.move(spell.object_id, EngineEnums.ZoneId.HAND, spell.owner_id)
				return
		return
	var obj: GameObject = engine.state.objects.get(tid)
	if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		engine.state.zones.move(tid, EngineEnums.ZoneId.HAND, obj.owner_id)
