class_name AbilityExecutor
extends RefCounted

var tokens: TokenCatalog = TokenCatalog.new()


## Returns false when a player decision paused this object. The entry stays on the stack.
func resolve(engine: RulesEngine, entry: StackEntry) -> bool:
	if entry == null:
		return true
	if bool(entry.ctx.get("overload", false)):
		return _resolve_overload(engine, entry)
	return _resolve_once(engine, entry)


## Overload (CR 702.96b): "target" became "each", so the spell's effects run once for every object its target
## could have been, in turn. A decision pauses on the current object and picks up there.
func _resolve_overload(engine: RulesEngine, entry: StackEntry) -> bool:
	if not entry.ctx.has("ov_ids"):
		var spec: Dictionary = entry.ctx.get("ov_spec", {})
		var ids: Array = []
		if engine.targeting != null and not spec.is_empty():
			ids = engine.targeting.legal_ids(engine, spec, entry.object_id)
		entry.ctx["ov_ids"] = ids
		entry.ctx["ov_i"] = 0
	var all: Array = entry.ctx["ov_ids"]
	while int(entry.ctx["ov_i"]) < all.size():
		entry.targets = [all[int(entry.ctx["ov_i"])]]
		if not _resolve_once(engine, entry):
			return false
		entry.ctx["ov_i"] = int(entry.ctx["ov_i"]) + 1
		entry.cursor = 0
		entry.choices = {}
	return true


func _resolve_once(engine: RulesEngine, entry: StackEntry) -> bool:
	var source: GameObject = engine.state.objects.get(entry.source_id)
	if source == null:
		source = engine.state.objects.get(entry.object_id)
	## Targets a person still has to choose (see TriggerManager._put_trigger) are asked first.
	if entry.ctx.has("pick_slots") and not bool(entry.ctx.get("picked_targets", false)):
		if not _pick_trigger_targets(engine, entry, source):
			return false
		entry.ctx["picked_targets"] = true
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
		## "If it's an Angel, put two +1/+1 counters on it": the card just returned has the subtype.
		if fx.params.has("if_moved_subtype"):
			var mo: GameObject = engine.state.objects.get(int(entry.ctx.get("last_moved", 0)))
			if mo == null or not (mo.definition is CardDefinition) or not (mo.definition as CardDefinition).type_line.contains(str(fx.params["if_moved_subtype"])):
				entry.cursor += 1
				continue
		## "... unless you pay {U}": this effect happens only when the payment was not made.
		var not_link := str(fx.params.get("if_not_link", ""))
		if not_link != "" and bool(entry.choices.get(not_link, false)):
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
		## "If it was kicked" / "if an opponent was dealt damage this turn" gates (kicker, bloodthirst).
		if bool(fx.params.get("if_kicked", false)) and _kicked_count(entry, source) <= 0:
			entry.cursor += 1
			continue
		if bool(fx.params.get("if_cast", false)) and (source == null or source.cast_from < 0):
			entry.cursor += 1
			continue
		if bool(fx.params.get("if_cast_from_hand", false)) and (source == null or source.cast_from != EngineEnums.ZoneId.HAND):
			entry.cursor += 1
			continue
		if bool(fx.params.get("if_opp_damaged", false)) and not _opponent_damaged(engine, entry):
			entry.cursor += 1
			continue
		if fx.params.has("if_exiled_creature") and bool(entry.ctx.get("exiled_creature", false)) != bool(fx.params["if_exiled_creature"]) \
				or fx.params.has("if_exiled_noncreature") and (not entry.ctx.has("exiled_creature") or bool(entry.ctx.get("exiled_creature", false)) == bool(fx.params["if_exiled_noncreature"])):
			entry.cursor += 1
			continue
		if fx.params.has("if_trigger_subtype") and not _trigger_object_has_subtype(engine, entry, str(fx.params["if_trigger_subtype"])):
			entry.cursor += 1
			continue
		## Gift (CR 702.174): "if the gift was promised".
		if bool(fx.params.get("if_gift", false)) and not (bool(entry.ctx.get("gift", false)) or (source != null and source.gift_promised)):
			entry.cursor += 1
			continue
		## Dethrone (CR 702.105): the creature is attacking the player with the most life or tied for most.
		if bool(fx.params.get("if_defender_most_life", false)) and not defender_has_most_life(engine, source):
			entry.cursor += 1
			continue
		## Generic condition (ability words, "if you control ...", "if it's your turn"): see LayerManager.condition_met.
		if fx.params.has("if_cond") and not engine.layers.condition_met(engine.state, source, fx.params["if_cond"] as Dictionary):
			entry.cursor += 1
			continue
		_apply(engine, entry, source, fx)
		## An effect that needs a player's pick leaves a decision open: wait, and run this effect again after.
		if engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION and engine.state.pending_decision is PlayerDecision \
				and (engine.state.pending_decision as PlayerDecision).stack_id == entry.stack_id:
			return false
		entry.cursor += 1
	return true


## True when `attacker` is attacking a player whose life total is the highest (ties count), CR 702.105a.
func defender_has_most_life(engine: RulesEngine, attacker: GameObject) -> bool:
	if attacker == null:
		return false
	var d := engine.defender_of(attacker.object_id)
	if d < 0 or d >= engine.state.players.size():
		return false
	var life := engine.state.players[d].life
	for p in engine.state.players:
		if not p.lost and p.life > life:
			return false
	return true


## "If a Dinosaur is dealt damage this way": the creature that set the trigger off has that subtype.
func _trigger_object_has_subtype(engine: RulesEngine, entry: StackEntry, subtype: String) -> bool:
	var o: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
	if o == null or o.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return false
	return Query._subtype_words((o.definition as CardDefinition).type_line if o.definition is CardDefinition else "").has(subtype) \
		or engine.has_keyword(o, "Changeling")


func _kicked_count(entry: StackEntry, source: GameObject) -> int:
	if entry.ctx.has("kicked"):
		return int(entry.ctx["kicked"])
	return source.kicked if source != null else 0


func _opponent_damaged(engine: RulesEngine, entry: StackEntry) -> bool:
	for p in engine.state.players:
		if p.player_id != entry.controller_id and p.damaged_this_turn:
			return true
	return false


func _apply(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	match str(fx.kind):
		## A sentence of the card the reader could not turn into an effect: the rest of the spell still happens.
		"NOTE_UNREAD":
			_note(engine, entry.controller_id, "Not coded yet: \"%s\" - apply it by hand." % str(fx.params.get("text", "")))
		"DRAW":
			var n := _value(engine, entry, source, fx.params.get("n", 1))
			for pid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
				if not _draw_cards(engine, entry, int(pid), n):
					return
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
		"UNTAP_CHOICE":
			_untap_choice(engine, entry, fx)
		"REORDER_TOP":
			_reorder_top(engine, entry, source, fx)
		"EXILE_IF_DIES":
			var edx := int(fx.params.get("target", 0))
			if edx >= 0 and edx < entry.targets.size():
				var edo: GameObject = engine.state.objects.get(int(entry.targets[edx]))
				if edo != null and edo.zone == EngineEnums.ZoneId.BATTLEFIELD:
					edo.marks["exile_if_dies_turn"] = engine.state.turn_number
		"EXTRA_TURN":
			## "Take an extra turn after this one" (CR 500.7): the most recent extra turn is taken first.
			for _t in int(fx.params.get("n", 1)):
				engine.state.extra_turns.insert(0, {"pid": entry.controller_id, "lose": bool(fx.params.get("lose", false))})
		"COPY_EACH":
			## Rhys the Redeemed: "For each creature token you control, create a token that's a copy of that creature."
			for co in _each(engine, entry, source, fx.params.get("query", {})):
				var cdef: CardDefinition = (co as GameObject).definition as CardDefinition if (co as GameObject).definition is CardDefinition else null
				if cdef == null:
					continue
				var cobj: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, {definition = cdef, is_token = true, controller_id = entry.controller_id})
				if cobj != null:
					engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, entry.controller_id, {from_id = 0, to_id = cobj.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0})
		"PILES":
			## Fact or Fiction: reveal the top N; an opponent splits them into two piles (the game balances them by card value); the
			## caster takes one pile into hand and the other goes to the graveyard (or the bottom).
			var pplayer := entry.controller_id
			var plib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pplayer)
			if plib == null or plib.object_ids.is_empty():
				return
			var ptop: Array = []
			for pi in mini(int(fx.params.get("n", 5)), plib.object_ids.size()):
				ptop.append(int(plib.object_ids[pi]))
			var worth := func(oid: int) -> int:
				var po: GameObject = engine.state.objects.get(oid)
				return ((po.definition as CardDefinition).cmc + 1) if po != null and po.definition is CardDefinition else 1
			var ordered := ptop.duplicate()
			ordered.sort_custom(func(x: int, y: int) -> bool: return worth.call(x) > worth.call(y))
			var pile_a: Array = []
			var pile_b: Array = []
			var va := 0
			var vb := 0
			for pid2 in ordered:
				if va <= vb:
					pile_a.append(pid2)
					va += int(worth.call(pid2))
				else:
					pile_b.append(pid2)
					vb += int(worth.call(pid2))
			var names_a: Array = []
			for oa in pile_a:
				names_a.append(_name_of(engine, int(oa)))
			var names_b: Array = []
			for ob in pile_b:
				names_b.append(_name_of(engine, int(ob)))
			var pans := _ask(engine, entry, pplayer, "piles", "Your opponent split the cards into two piles. Which pile goes to your hand?",
				[{"value": "A", "label": "Pile A: " + (", ".join(PackedStringArray(names_a)) if not names_a.is_empty() else "(empty)")},
				 {"value": "B", "label": "Pile B: " + (", ".join(PackedStringArray(names_b)) if not names_b.is_empty() else "(empty)")}])
			if pans.s == "paused":
				return
			var take_a2 := (str(pans.value) == "A") if pans.s == "picked" else va >= vb
			var keep: Array = pile_a if take_a2 else pile_b
			var toss: Array = pile_b if take_a2 else pile_a
			for ko in keep:
				engine.state.zones.move(int(ko), EngineEnums.ZoneId.HAND, pplayer)
			for to_ in toss:
				if str(fx.params.get("rest", "GRAVEYARD")) == "BOTTOM":
					engine.put_library_bottom(int(to_), pplayer)
				else:
					engine.state.zones.move(int(to_), EngineEnums.ZoneId.GRAVEYARD, pplayer)
		"EXILE_BY_PARITY":
			## Extinction Event: choose odd or even, then exile each creature with a mana value of that kind.
			var pans := _ask(engine, entry, entry.controller_id, "parity", "Choose odd or even: exile each creature with that mana value.",
				[{"value": "odd", "label": "Odd"}, {"value": "even", "label": "Even"}])
			if pans.s == "paused":
				return
			var odd_total := 0
			var even_total := 0
			var all_creatures := _each(engine, entry, source, {"type": "creature"})
			for pc in all_creatures:
				var pcd := (pc as GameObject).definition as CardDefinition
				var sign_v := -1 if (pc as GameObject).controller_id == entry.controller_id else 1
				if pcd.cmc % 2 == 1:
					odd_total += sign_v
				else:
					even_total += sign_v
			var take_odd := (str(pans.value) == "odd") if pans.s == "picked" else odd_total >= even_total
			for pc2 in all_creatures:
				var pcd2 := (pc2 as GameObject).definition as CardDefinition
				if (pcd2.cmc % 2 == 1) == take_odd:
					engine.state.zones.move((pc2 as GameObject).object_id, EngineEnums.ZoneId.EXILE, (pc2 as GameObject).owner_id)
		"END_TURN":
			## Exile every other spell and ability on the stack, then end the turn once this resolves (CR 723.1).
			var stk := engine.state.stack as MagicStack
			for other in stk.entries.duplicate():
				var oe := other as StackEntry
				if oe == null or oe.stack_id == entry.stack_id:
					continue
				if oe.kind == StackEntry.Kind.SPELL and engine.state.objects.has(oe.object_id):
					engine.state.zones.move(oe.object_id, EngineEnums.ZoneId.EXILE, (engine.state.objects[oe.object_id] as GameObject).owner_id)
				stk.remove_by_stack_id(oe.stack_id)
			entry.ctx["exile_self"] = true
			engine.state.end_turn_requested = true
		"GET_ENERGY":
			## "You get {E}{E}" (CR 107.14).
			engine.state.players[entry.controller_id].energy += int(fx.params.get("n", 1))
		"BECOME_CREATURE":
			## Creature lands (Restless Prairie ...): the source becomes a creature with set power / toughness for the duration.
			if source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
				var bc := ContinuousEffect.new()
				bc.object_ids = [source.object_id]
				bc.source_id = source.object_id
				bc.controller_id = entry.controller_id
				bc.until_eot = str(fx.params.get("duration", "END_OF_TURN")) == "END_OF_TURN"
				bc.add_types.append("Creature")
				bc.sets_power = true
				bc.set_power = int(fx.params.get("power", 0))
				bc.sets_toughness = true
				bc.set_toughness = int(fx.params.get("toughness", 0))
				var bkws: Variant = fx.params.get("keywords", [])
				if bkws is Array:
					for bkw in bkws:
						bc.add_keywords.append(str(bkw))
				bc.timestamp = engine.state.next_timestamp
				engine.state.next_timestamp += 1
				engine.state.effects.append(bc)
		"COMMANDER_TO_HAND":
			## Command Beacon: "Put your commander into your hand from the command zone."
			var cz: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, entry.controller_id)
			if cz != null:
				for coid in cz.object_ids.duplicate():
					engine.state.zones.move(int(coid), EngineEnums.ZoneId.HAND, entry.controller_id)
		"COMMANDERS_TO_COMMAND":
			## Leadership Vacuum: the target player's commanders go from the battlefield to the command zone.
			for cpid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
				for cobj in _each(engine, entry, source, {"controller_id": int(cpid), "commander": true}):
					engine.state.zones.move((cobj as GameObject).object_id, EngineEnums.ZoneId.COMMAND, (cobj as GameObject).owner_id)
		"SELF_TO_LIBRARY":
			## "Put it into your library third from the top." (Enigma Sphinx)
			if source != null and not source.is_token and (source.zone == EngineEnums.ZoneId.GRAVEYARD or source.zone == EngineEnums.ZoneId.BATTLEFIELD):
				var back: GameObject = engine.state.zones.move(source.object_id, EngineEnums.ZoneId.LIBRARY, source.owner_id)
				var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, source.owner_id)
				if back != null and lib != null and lib.object_ids.has(back.object_id):
					lib.object_ids.erase(back.object_id)
					lib.object_ids.insert(mini(maxi(0, int(fx.params.get("from_top", 1)) - 1), lib.object_ids.size()), back.object_id)
		"REMOVE_FROM_COMBAT":
			## Reconnaissance: "Remove target attacking creature you control from combat and untap it."
			var ridx := int(fx.params.get("target", 0))
			if ridx >= 0 and ridx < entry.targets.size() and engine.state.combat is CombatState:
				var rid := int(entry.targets[ridx])
				var rcs := engine.state.combat as CombatState
				if rcs.attacker_ids.has(rid):
					rcs.attacker_ids.erase(rid)
					rcs.defenders.erase(rid)
					rcs.blockers.erase(rid)
					var robj: GameObject = engine.state.objects.get(rid)
					if robj != null:
						robj.tapped = false
		"CHAOS_WARP":
			_chaos_warp(engine, entry, fx)
		"FREEZE":
			## "It doesn't untap during its controller's next untap step": the mark is spent by that untap step (TurnManager._untap).
			var fidx := int(fx.params.get("target", 0))
			if fidx >= 0 and fidx < entry.targets.size():
				var fobj: GameObject = engine.state.objects.get(int(entry.targets[fidx]))
				if fobj != null and fobj.zone == EngineEnums.ZoneId.BATTLEFIELD:
					fobj.marks["frozen"] = true
		"SELF_TO_HAND":
			## "When ~ dies, return it to its owner's hand." / "return ~ to its owner's hand": from the graveyard or the battlefield.
			if source != null and not source.is_token and (source.zone == EngineEnums.ZoneId.GRAVEYARD or source.zone == EngineEnums.ZoneId.BATTLEFIELD):
				engine.state.zones.move(source.object_id, EngineEnums.ZoneId.HAND, source.owner_id)
				if engine.sba != null:
					engine.sba.check(engine)
		"TAP_EACH":
			for obj in _each(engine, entry, source, fx.params.get("query", {})):
				obj.tapped = true
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
		"SACRIFICE":
			_sacrifice(engine, entry, source, fx)
		"PROLIFERATE":
			_proliferate(engine, entry)
		"COUNTER_UNLESS_PAY":
			_counter_unless_pay(engine, entry, fx)
		"DISCARD_CHOSEN":
			_discard_chosen(engine, entry, fx)
		"REVEAL_HAND":
			_reveal_hand(engine, entry, fx)
		"LOOK_TOP":
			_look_top(engine, entry, source, fx)
		"DELAY":
			_delay(engine, entry, source, fx)
		"DISCARD_TO_HAND_SIZE":
			_discard_to_hand_size(engine, entry)
		"EXTRA_LAND":
			_extra_land(engine, entry, fx)
		"SET_LIFE":
			engine.state.players[entry.controller_id].life = _value(engine, entry, source, fx.params.get("n", 0))
		"OPP_DRAW_OR_MILL":
			_opp_draw_or_mill(engine, entry, source, fx)
		"MOVE_ALL":
			_move_all(engine, entry, source, fx)
		"EXILE_GRAVEYARD":
			_exile_graveyards(engine, entry, fx)
		"DISCARD_ALT":
			_discard_alt(engine, entry, fx)
		"PUT_FROM_HAND":
			_put_from_hand(engine, entry, source, fx)
		"UNLESS_SAC":
			_unless_sacrifice(engine, entry, source, fx)
		"SHUFFLE":
			engine.shuffle_library(entry.controller_id)
		"PUT_BACK":
			_put_back(engine, entry, fx)
		"PREVENT":
			_prevent(engine, entry, source, fx)
		"GAIN_CONTROL":
			_gain_control(engine, entry, source, fx)
		"DELAYED_ACT":
			_delayed_act(engine, entry, fx)
		"EXPLORE":
			_explore(engine, entry, source)
		"AMASS":
			_amass(engine, entry, source, fx)
		"BOLSTER":
			_bolster(engine, entry, source, fx)
		"POPULATE":
			_populate(engine, entry)
		"FABRICATE":
			_fabricate(engine, entry, source, fx)
		"CASCADE":
			_cascade(engine, entry, source)
		"RETURN_SELF":
			_return_self(engine, entry, source, fx)
		"SURVEIL":
			_surveil(engine, entry, fx)
		"BECOME_MONARCH":
			engine.state.monarch_id = entry.controller_id
		"CHOOSE_COLOR":
			_choose_color(engine, entry, source, fx)
		_:
			if KeywordEffects.handles(str(fx.kind)):
				KeywordEffects.apply(self, engine, entry, source, fx)
			elif CardEffects.handles(str(fx.kind)):
				CardEffects.apply(self, engine, entry, source, fx)
			elif KeywordActions.handles(str(fx.kind)):
				KeywordActions.apply(self, engine, entry, source, fx)
			elif PreconEffects.handles(str(fx.kind)):
				PreconEffects.apply(self, engine, entry, source, fx)


# --- Values, players and object sets ----------------------------------------------------

## An int, or {"expr": ..., "mult": n, "add": n}: TRIGGER_TOUGHNESS / TRIGGER_POWER (the creature that
## set off the trigger), EVENT_AMOUNT (damage or life that set it off), SELF_POWER, LANDS, COUNT (+ query).
func _value(engine: RulesEngine, entry: StackEntry, source: GameObject, raw: Variant) -> int:
	if not (raw is Dictionary):
		return int(raw)
	var d := raw as Dictionary
	var base := 0
	## {"query": ...} on its own means COUNT (Krenko: "the number of Goblins you control").
	var expr := str(d.get("expr", "COUNT" if d.has("query") else ""))
	match expr:
		"TRIGGER_TOUGHNESS":
			base = int(entry.ctx.get("toughness", 0))
		"TRIGGER_POWER":
			base = int(entry.ctx.get("power", 0))
		"EVENT_AMOUNT":
			base = int(entry.ctx.get("amount", 0))
		"SELF_POWER":
			base = engine.power_of(source) if source != null else 0
		"X":
			base = int(entry.ctx.get("x", 0))
		"TARGET_POWER":
			var tidx := int(d.get("target", 0))
			if tidx >= 0 and tidx < entry.targets.size():
				var tobj: GameObject = engine.state.objects.get(int(entry.targets[tidx]))
				if tobj != null and tobj.zone == EngineEnums.ZoneId.BATTLEFIELD:
					base = engine.power_of(tobj)
				else:
					base = int(entry.ctx.get("target_power", 0))
		"GREATEST_POWER":
			var gbf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
			if gbf != null:
				for gid in gbf.object_ids:
					var go: GameObject = engine.state.objects.get(gid)
					if go != null and go.controller_id == entry.controller_id and engine.is_creature_now(go):
						base = maxi(base, engine.power_of(go))
		"LANDS":
			base = Query.count_objects(engine.state, _ref(entry, source), {"controller": "SOURCE_CONTROLLER", "type": "land"})
		## Hit the Mother Lode: N minus the discovered card's mana value (0 if it was N or more).
		"DISCOVER_DIFF":
			base = maxi(0, int(d.get("n", 0)) - int(entry.ctx.get("dc_mv", int(d.get("n", 0)))))
		"EXILED_COUNT":
			base = int(entry.ctx.get("exiled_count", 0))
		"DISCARDED_COUNT":
			base = int(entry.ctx.get("discarded", 0))
		"COUNT":
			var cq: Dictionary = d.get("query", {})
			if cq.has("power_min"):
				## "with power 4 or greater" needs current power, so it is counted here (CR 208.3).
				var plain := cq.duplicate()
				plain.erase("power_min")
				for o in _each(engine, entry, source, plain):
					if engine.power_of(o) >= int(cq["power_min"]):
						base += 1
			else:
				base = Query.count_objects(engine.state, _ref(entry, source), cq)
		## Domain: the number of basic land types among lands you control.
		"DOMAIN":
			var kinds := {}
			for lo in _each(engine, entry, source, {"controller": "SOURCE_CONTROLLER", "type": "land"}):
				var ltl := (lo.definition as CardDefinition).type_line if lo.definition is CardDefinition else ""
				for bt in ["Plains", "Island", "Swamp", "Mountain", "Forest"]:
					if ltl.contains(bt):
						kinds[bt] = true
			base = kinds.size()
		## Gray Merchant: your devotion to a color (CR 700.5): its mana symbols among permanents you control.
		"DEVOTION":
			var sym := "{%s}" % str(d.get("color", "B"))
			var hyb := "/%s}" % str(d.get("color", "B"))
			for po in _permanents_of(engine, entry.controller_id):
				var mc := (po.definition as CardDefinition).mana_cost
				base += mc.count(sym) + mc.count(hyb) + mc.count("{" + str(d.get("color", "B")) + "/")
		## "You gain life equal to the life lost this way".
		"LIFE":
			base = engine.state.players[entry.controller_id].life
		"LIBRARY":
			var libz: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, entry.controller_id)
			base = libz.size() if libz != null else 0
		"SPELLS_THIS_TURN":
			base = engine.state.players[entry.controller_id].spells_this_turn.size()
		"OPPONENTS":
			for opp in engine.state.players:
				if opp.player_id != entry.controller_id and not opp.lost:
					base += 1
		## Wojek Investigator: opponents with more cards in hand than you.
		"OPP_MORE_HAND":
			var my_hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, entry.controller_id)
			var mine_n := my_hand.size() if my_hand != null else 0
			for opp2 in engine.state.players:
				if opp2.player_id == entry.controller_id or opp2.lost:
					continue
				var oh: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, opp2.player_id)
				if oh != null and oh.size() > mine_n:
					base += 1
		"LIFE_LOST":
			base = int(entry.ctx.get("life_lost", 0))
		## Kaervek: the mana value of the spell that was cast.
		"SPELL_MV":
			var spo: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
			if spo != null and spo.definition is CardDefinition:
				base = (spo.definition as CardDefinition).cmc
		"TARGET_MV":
			var mi := int(d.get("target", 0))
			if mi >= 0 and mi < entry.targets.size():
				var mo: GameObject = engine.state.objects.get(int(entry.targets[mi]))
				if mo != null and mo.definition is CardDefinition:
					base = (mo.definition as CardDefinition).cmc
				elif entry.ctx.has("target_mv"):
					base = int(entry.ctx["target_mv"])
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
	## "TARGET_<n>": the player chosen for target slot n ("target player draws two cards").
	## "CONTROLLER_OF_TARGET_<n>": whoever controls the permanent chosen for target slot n (Star Athlete, Enchanter's Bane).
	if who.begins_with("CONTROLLER_OF_TARGET_"):
		var cslot := int(who.substr(21))
		if cslot >= 0 and cslot < entry.targets.size():
			var cobj: GameObject = engine.state.objects.get(int(entry.targets[cslot]))
			if cobj != null and cobj.controller_id >= 0 and cobj.controller_id < engine.state.players.size() and not engine.state.players[cobj.controller_id].lost:
				out.append(cobj.controller_id)
		return out
	## "that player" after a target was chosen and affected: its controller (Suspended Sentence: "that player loses 3 life").
	if who == "TARGET_CONTROLLER":
		var tcp := int(entry.ctx.get("target_controller", -1))
		if tcp >= 0 and tcp < engine.state.players.size() and not engine.state.players[tcp].lost:
			out.append(tcp)
		return out
	## "that player": the player whose event set the trigger off (a draw, a life change).
	if who == "TRIGGER_PLAYER":
		var tpid := int(entry.ctx.get("player_id", -1))
		if tpid >= 0 and tpid < engine.state.players.size() and not engine.state.players[tpid].lost:
			out.append(tpid)
		return out
	if who.begins_with("TARGET_"):
		var slot := int(who.substr(7))
		if slot >= 0 and slot < entry.targets.size():
			var tp := TargetingManager.decode_player(int(entry.targets[slot]))
			if tp >= 0 and tp < engine.state.players.size() and not engine.state.players[tp].lost:
				out.append(tp)
		return out
	for p in engine.state.players:
		if p.lost:
			continue
		match who:
			"DEFENDER":
				## The player the source is attacking or dealt combat damage to (afflict, ingest, poisonous).
				var dfd := int(entry.ctx.get("defender", engine.defender_of(entry.source_id)))
				if p.player_id == dfd:
					out.append(p.player_id)
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
## "Players can't gain life" / "Your opponents can't gain life" (Rampaging Ferocidon, The Lord of Pain).
## "If you would gain life, you gain that much life plus 1 instead." (Angel of Vitality): the extra life from your replacements.
func life_gain_bonus(engine: RulesEngine, pid: int) -> int:
	var bonus := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 0
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != pid or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("life_gain_plus"):
				bonus += int(ab.static_spec["life_gain_plus"])
	return bonus


## "If you would gain life, you gain twice that much life instead" (Hatsune Miku's lifegain doublers).
func life_gain_mult(engine: RulesEngine, pid: int) -> int:
	var mult := 1
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return 1
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != pid or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("life_gain_mult"):
				mult *= int(ab.static_spec["life_gain_mult"])
	return mult


func life_gain_blocked(engine: RulesEngine, pid: int) -> bool:
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("no_life_gain"):
				continue
			var who := str(ab.static_spec["no_life_gain"])
			if who == "ALL" or (who == "OPPONENTS" and o.controller_id != pid):
				return true
	return false


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
			if bool((query as Dictionary).get("attacking", false)) and not _is_attacking(engine, obj):
				continue
			out.append(obj)
	return out


func _is_attacking(engine: RulesEngine, obj: GameObject) -> bool:
	return engine.state.combat is CombatState and (engine.state.combat as CombatState).attacker_ids.has(obj.object_id)


## What an effect acts on: the source itself ("self"), every object matching "each", or its target.
func _affected(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> Array:
	if bool(fx.params.get("self", false)):
		if source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
			return [source]
		return []
	if fx.params.has("each"):
		return _each(engine, entry, source, fx.params["each"])
	## "Enchanted creature gets +1/+1 until end of turn" on an Aura or Equipment: what the source is attached to.
	if bool(fx.params.get("attached", false)):
		var host: GameObject = engine.state.objects.get(source.attached_to) if source != null and source.attached_to != 0 else null
		return [host] if host != null and host.zone == EngineEnums.ZoneId.BATTLEFIELD else []
	## The card just put onto the battlefield by an earlier effect of this ability ("If it's an Angel, put two counters on it").
	if bool(fx.params.get("moved", false)):
		var mv_obj: GameObject = engine.state.objects.get(int(entry.ctx.get("last_moved", 0)))
		return [mv_obj] if mv_obj != null and mv_obj.zone == EngineEnums.ZoneId.BATTLEFIELD else []
	## The creature that set the trigger off (exalted: the lone attacker).
	if bool(fx.params.get("trigger_object", false)):
		var trig: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
		return [trig] if trig != null and trig.zone == EngineEnums.ZoneId.BATTLEFIELD else []
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return []
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return []
	return [obj]


## Who does the effect: its controller, or "the target's controller" for "Its controller creates / may search".
func _acting_player(entry: StackEntry, fx: AbilityEffect) -> int:
	if str(fx.params.get("for", "")) == "TARGET_CONTROLLER":
		return int(entry.ctx.get("target_controller", entry.controller_id))
	## "Target player creates two Treasure tokens": the player chosen in target slot n.
	var forp := str(fx.params.get("for", ""))
	if forp.begins_with("TARGET_PLAYER_"):
		var tslot := int(forp.substr(14))
		if tslot >= 0 and tslot < entry.targets.size() and TargetingManager.decode_player(int(entry.targets[tslot])) >= 0:
			return TargetingManager.decode_player(int(entry.targets[tslot]))
	return entry.controller_id


func _create_tokens(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var def: CardDefinition = null
	## "Create a token that's a copy of ~ / target creature / it" (CR 707.2): the token has the copiable values of the original.
	if fx.params.has("copy_of"):
		var cref := str(fx.params["copy_of"])
		var cid := 0
		if cref == "SELF":
			cid = entry.source_id
		elif cref == "TRIGGER_OBJECT":
			cid = int(entry.ctx.get("object_id", 0))
		elif cref.begins_with("TARGET_"):
			var cslot := int(cref.substr(7))
			if cslot >= 0 and cslot < entry.targets.size():
				cid = int(entry.targets[cslot])
		var csrc: GameObject = engine.state.objects.get(cid)
		if csrc != null and csrc.definition is CardDefinition:
			def = csrc.definition as CardDefinition
	elif fx.params.has("spec"):
		def = tokens.from_spec(fx.params["spec"])
	else:
		def = tokens.definition_for(str(fx.params.get("token", "")))
	if def == null:
		return
	var n := _value(engine, entry, source, fx.params.get("count", 1))
	var maker := _acting_player(entry, fx)
	## Token with X/X: the size is X (Mirror-style "X 1/1"), set from the spell's X.
	var x_size := int(entry.ctx.get("x", 0))
	for _j in n:
		var opts := {
			definition = def,
			is_token = true,
			controller_id = maker,
		}
		if bool(fx.params.get("tapped", false)):
			opts["tapped"] = true
		var obj: GameObject = engine.state.zones.create(maker, EngineEnums.ZoneId.BATTLEFIELD, opts)
		if obj == null:
			continue
		entry.ctx["last_created"] = obj.object_id
		if bool(fx.params.get("pt_x", false)) and x_size > 0:
			obj.counters["+1/+1"] = int(obj.counters.get("+1/+1", 0)) + x_size
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
	entry.ctx["target_controller"] = obj.controller_id
	entry.ctx["target_power"] = engine.power_of(obj)
	var moved: GameObject = engine.state.zones.move(target_id, dest, obj.owner_id)
	## Imprint: a permanent remembers the cards it exiled (Duplicant reads the last creature card).
	if moved != null and dest == EngineEnums.ZoneId.EXILE:
		var src: GameObject = engine.state.objects.get(entry.source_id)
		if src != null and src.zone == EngineEnums.ZoneId.BATTLEFIELD:
			src.imprinted.append(moved.object_id)


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
	for pending in stack.entries:
		if (pending as StackEntry).stack_id == sid and engine.cant_be_countered(engine.state.objects.get((pending as StackEntry).object_id)):
			return
	var found: StackEntry = stack.remove_by_stack_id(sid)
	if found == null:
		return
	if found.object_id == 0:
		return
	var obj: GameObject = engine.state.objects.get(found.object_id)
	if obj != null and obj.zone == EngineEnums.ZoneId.STACK:
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func _lose_life(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := _value(engine, entry, engine.state.objects.get(entry.source_id), fx.params.get("n", 0))
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
		entry.ctx["life_lost"] = int(entry.ctx.get("life_lost", 0)) + n
		engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, entry.controller_id, {
			to_player = pid,
			amount = n,
		})
	if engine.sba != null:
		engine.sba.check(engine)


func _deal_damage(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := _value(engine, entry, source, fx.params.get("n", 0))
	if n <= 0:
		return
	## "~ deals 2 damage to it" (the creature that set the trigger off).
	if bool(fx.params.get("trigger_object", false)):
		var hit: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
		if hit != null and hit.zone == EngineEnums.ZoneId.BATTLEFIELD:
			engine.damage_object(source if source != null else _ref(entry, null), hit, n)
			if engine.sba != null:
				engine.sba.check(engine)
		return
	## Wayta-style "deals that much damage": the damage comes from the creature that was dealt it.
	if bool(fx.params.get("from_trigger_object", false)):
		var dealer: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
		if dealer != null:
			source = dealer
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
	n = engine.apply_prevention(null, pid, n)
	if n <= 0:
		return
	engine.state.players[pid].life -= n
	engine.kw.note_player_damaged(pid, engine.state.objects.get(entry.source_id), false)
	engine.state.log.append(EngineEnums.EventType.DAMAGE, entry.controller_id, {
		to_player = pid,
		amount = n,
		object_id = entry.source_id,
	})
	if engine.sba != null:
		engine.sba.check(engine)


## "deals N damage to each other creature".
func _deal_damage_each(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := _value(engine, entry, source, fx.params.get("n", 0))
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
		if life_gain_blocked(engine, pid):
			continue
		var gained := n * life_gain_mult(engine, pid) + life_gain_bonus(engine, pid)
		engine.state.players[pid].life += gained
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
	entry.ctx["target_controller"] = obj.controller_id
	if obj.definition is CardDefinition:
		entry.ctx["target_mv"] = (obj.definition as CardDefinition).cmc
	engine.destroy_permanent(obj)


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
	if bool(fx.params.get("self", false)):
		var me: GameObject = engine.state.objects.get(entry.source_id)
		if me != null and me.zone == EngineEnums.ZoneId.BATTLEFIELD:
			me.tapped = tap
		return
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
	## "Target creature has base power and toughness 1/1 until end of turn": the subject is the chosen target.
	if fx.params.has("target"):
		var tidx := int(fx.params["target"])
		source = engine.state.objects.get(int(entry.targets[tidx])) if tidx >= 0 and tidx < entry.targets.size() else null
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
	if fx.params.has("who"):
		var whos := _players_for(engine, entry, str(fx.params["who"]))
		if whos.is_empty():
			return
		pid = int(whos[0])
	var may_play := str(fx.params.get("may_play", ""))
	for _i in n:
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
		if lib == null or lib.is_empty():
			return
		var top_id := int(lib.object_ids[0])
		var moved: GameObject = engine.state.zones.move(top_id, EngineEnums.ZoneId.EXILE, pid)
		if moved != null and may_play in ["END_OF_TURN", "NEXT_TURN"]:
			moved.may_play_controller = pid
			if may_play == "NEXT_TURN":
				moved.marks["keep_until"] = engine.state.turn_number + engine.state.players.size() + 1
		## "cards exiled with ~": remembered so a later permission (Theater of Horrors) can find them.
		if moved != null and bool(fx.params.get("link", false)):
			moved.marks["exiled_with"] = entry.source_id


func _put_counter(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var cname := str(fx.params.get("name", "+1/+1"))
	var n := _value(engine, entry, source, fx.params.get("n", 1))
	for obj in _affected(engine, entry, source, fx):
		obj.counters[cname] = int(obj.counters.get(cname, 0)) + n
		## "Whenever you put one or more +1/+1 counters on ~" (Exemplar of Light).
		if cname == "+1/+1" and n > 0 and engine.triggers != null:
			engine.triggers.fire_object_event(engine, "COUNTERS_PUT", obj, {player_id = obj.controller_id})


## Draws `n` cards for `pid`. A card with dredge in their graveyard may replace each draw (CR 702.52a): the player
## is asked first. Returns false while the game waits for the answer; progress is kept in entry.choices so the effect
## picks up where it stopped.
func _draw_cards(engine: RulesEngine, entry: StackEntry, pid: int, n: int) -> bool:
	var key := "drawn_%d_%d" % [entry.cursor, pid]
	var done := int(entry.choices.get(key, 0))
	while done < n:
		var opts := dredge_options(engine, pid)
		if not opts.is_empty():
			var ans := _ask(engine, entry, pid, "dredge_%d_%d_%d" % [entry.cursor, pid, done], "Dredge instead of drawing? Pick a card to return (or decline to draw).", opts, true)
			if ans.s == "paused":
				entry.choices[key] = done
				return false
			if ans.s == "picked":
				engine.kw.do_dredge(pid, int(ans.value))
				done += 1
				continue
		engine.draw_card(pid)
		done += 1
	entry.choices[key] = done
	return true


## Choices {value, label, detail} for dredging in place of a draw; empty when the seat isn't a person.
func dredge_options(engine: RulesEngine, pid: int) -> Array:
	var out: Array = []
	if not engine.interactive_seats.has(pid):
		return out
	for opt in engine.kw.dredge_cards(pid):
		var o := _card_option(engine, int(opt.id))
		o["label"] = "Dredge %d: %s" % [int(opt.n), str(o.get("label", "card"))]
		o["detail"] = "Mill %d cards, then return it to your hand instead of drawing.\n%s" % [int(opt.n), str(o.get("detail", ""))]
		out.append(o)
	return out


# --- Asking the player ---------------------------------------------------------------------
## Asks `pid` to pick one of `options` ({value, label, detail}). Returns {"s": status, "value": v}:
##   "picked"   the player chose `value`
##   "declined" the player passed on an optional choice
##   "paused"   the game now waits for the answer; the effect must return before changing anything
##   "auto"     nobody to ask (rival or no options): the effect decides itself
## Answers are kept in entry.choices under `link`, so running the effect again after the answer finds them.
func _ask(engine: RulesEngine, entry: StackEntry, pid: int, link: String, prompt: String, options: Array, optional: bool = false, kind: String = "PICK") -> Dictionary:
	if entry.choices.has(link):
		var got: Variant = entry.choices[link]
		if got is bool:
			return {"s": "picked" if got else "declined", "value": got}
		return {"s": "picked", "value": got}
	if options.is_empty() or not engine.interactive_seats.has(pid):
		return {"s": "auto"}
	var dec := PlayerDecision.new()
	dec.decision_id = engine.state.next_stack_id
	dec.kind = StringName(kind)
	dec.player_id = pid
	dec.stack_id = entry.stack_id
	dec.link = link
	dec.prompt = prompt
	dec.optional = optional
	dec.min_count = 0 if optional else 1
	dec.max_count = 1
	for o in options:
		dec.candidates.append(o.get("value"))
		dec.info[str(o.get("value"))] = {"label": str(o.get("label", o.get("value"))), "detail": str(o.get("detail", ""))}
	engine.state.pending_decision = dec
	engine.state.mode = EngineEnums.EngineMode.AWAITING_DECISION
	engine.state.awaiting = {player_id = pid, type = &"decision", decision_id = dec.decision_id}
	return {"s": "paused"}


func _ask_yes_no(engine: RulesEngine, entry: StackEntry, pid: int, link: String, prompt: String, show_ids: Array = []) -> Dictionary:
	if entry.choices.has(link):
		return {"s": "picked", "value": bool(entry.choices[link])}
	if not engine.interactive_seats.has(pid):
		return {"s": "auto"}
	var dec := PlayerDecision.new()
	dec.decision_id = engine.state.next_stack_id
	dec.kind = &"OPTIONAL_YES_NO"
	dec.player_id = pid
	dec.stack_id = entry.stack_id
	dec.link = link
	dec.prompt = prompt
	dec.show_ids = show_ids.duplicate()
	dec.optional = true
	dec.min_count = 0
	dec.max_count = 1
	engine.state.pending_decision = dec
	engine.state.mode = EngineEnums.EngineMode.AWAITING_DECISION
	engine.state.awaiting = {player_id = pid, type = &"decision", decision_id = dec.decision_id}
	return {"s": "paused"}


## {value, label, detail} for choosing a card.
func _card_option(engine: RulesEngine, oid: int) -> Dictionary:
	var c: GameObject = engine.state.objects.get(oid)
	var def := c.definition as CardDefinition if c != null and c.definition is CardDefinition else null
	if def == null:
		return {"value": oid, "label": "Card", "detail": ""}
	var rules := def.oracle_text.replace("\n", " ")
	if rules.length() > 170:
		rules = rules.substr(0, 167) + "..."
	return {"value": oid, "label": def.name, "detail": ("%s  %s\n%s" % [def.mana_cost, def.type_line, rules]).strip_edges()}


func _name_of(engine: RulesEngine, oid: int) -> String:
	var c: GameObject = engine.state.objects.get(oid)
	return (c.definition as CardDefinition).name if c != null and c.definition is CardDefinition else "the card"


# --- Keyword actions ------------------------------------------------------------------------

func _spawn_token(engine: RulesEngine, pid: int, def: CardDefinition) -> GameObject:
	var obj: GameObject = engine.state.zones.create(pid, EngineEnums.ZoneId.BATTLEFIELD, {definition = def, is_token = true, controller_id = pid})
	if obj != null:
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, pid, {
			from_id = 0, to_id = obj.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0,
		})
	return obj


func _permanents_of(engine: RulesEngine, pid: int, kind: String = "") -> Array:
	var out: Array = []
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != pid or not (o.definition is CardDefinition):
			continue
		if kind != "" and not (o.definition as CardDefinition).type_line.to_lower().contains(kind.to_lower()):
			continue
		out.append(o)
	return out


## Sacrifice N (CR 701.17): each affected player picks their own. The rival gives up its cheapest first.
func _sacrifice(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 1))
	if bool(fx.params.get("self", false)):
		## "Sacrifice ~" as an effect.
		if source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
			engine.state.zones.move(source.object_id, EngineEnums.ZoneId.GRAVEYARD, source.owner_id)
			if engine.sba != null:
				engine.sba.check(engine)
		return
	var plan := {}
	for pid in _players_for(engine, entry, str(fx.params.get("who", "EACH_OPPONENT"))):
		var mine := _permanents_of(engine, int(pid), str(fx.params.get("type", "")))
		## A full query ("another artifact or creature") narrows what can be sacrificed.
		var sq: Variant = fx.params.get("query", null)
		if sq is Dictionary:
			mine = mine.filter(func(o: GameObject) -> bool: return Query._matches(o, source, sq as Dictionary))
		var chosen: Array = []
		for i in mini(n, mine.size()):
			var options: Array = []
			for o in mine:
				if not chosen.has(o.object_id):
					options.append(_card_option(engine, o.object_id))
			var ans := _ask(engine, entry, int(pid), "sac_%d_%d" % [pid, i], "Sacrifice a permanent (%d of %d)." % [i + 1, n], options)
			if ans.s == "paused":
				return
			if ans.s == "picked":
				chosen.append(int(ans.value))
			else:
				var worst: GameObject = null
				var worst_score := 1000000
				for o2 in mine:
					if chosen.has(o2.object_id):
						continue
					var d2 := o2.definition as CardDefinition
					var sc := -1 if o2.is_token else d2.cmc * 2 + engine.power_of(o2) + (6 if d2.is_land() else 0)
					if sc < worst_score:
						worst_score = sc
						worst = o2
				if worst != null:
					chosen.append(worst.object_id)
		plan[pid] = chosen
	for pid in plan.keys():
		for oid in plan[pid]:
			var o3: GameObject = engine.state.objects.get(int(oid))
			if o3 != null and o3.zone == EngineEnums.ZoneId.BATTLEFIELD:
				engine.state.zones.move(o3.object_id, EngineEnums.ZoneId.HAND if str(fx.params.get("to", "")) == "HAND" else (EngineEnums.ZoneId.EXILE if str(fx.params.get("to", "")) == "EXILE" else EngineEnums.ZoneId.GRAVEYARD), o3.owner_id)
	if engine.sba != null:
		engine.sba.check(engine)


## Proliferate (CR 701.34): your good counters and your opponents' bad ones grow by one.
func _proliferate(engine: RulesEngine, entry: StackEntry) -> void:
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf != null:
		for oid in bf.object_ids:
			var o: GameObject = engine.state.objects.get(oid)
			if o == null:
				continue
			var mine := o.controller_id == entry.controller_id
			for k in o.counters.keys():
				if int(o.counters[k]) <= 0 or str(k) == "renowned":
					continue
				if mine != (str(k) == "-1/-1"):
					o.counters[k] = int(o.counters[k]) + 1
	for p in engine.state.players:
		if p.player_id != entry.controller_id and p.poison > 0:
			p.poison += 1


## Explore (CR 701.44): reveal the top card. A land goes to your hand; otherwise the creature gets a
## +1/+1 counter and you may put the card into your graveyard.
func _explore(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or lib.is_empty():
		return
	var top_id := int(lib.object_ids[0])
	var top: GameObject = engine.state.objects.get(top_id)
	var def := top.definition as CardDefinition if top != null and top.definition is CardDefinition else null
	if def == null:
		return
	if def.is_land():
		engine.state.zones.move(top_id, EngineEnums.ZoneId.HAND, pid)
		return
	var ans := _ask_yes_no(engine, entry, pid, "explore_gy", "Explore: %s is not a land. Put it into your graveyard? (No leaves it on top.)" % def.name, [top_id])
	if ans.s == "paused":
		return
	source.counters["+1/+1"] = int(source.counters.get("+1/+1", 0)) + 1
	if ans.s == "picked" and bool(ans.value):
		engine.state.zones.move(top_id, EngineEnums.ZoneId.GRAVEYARD, pid)


## Amass N (CR 701.47): +N counters on your Army, making a 0/0 Army token first if you have none.
func _amass(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := _value(engine, entry, source, fx.params.get("n", 1))
	var army: GameObject = null
	for o in _permanents_of(engine, entry.controller_id, "Army"):
		army = o
		break
	if army == null:
		army = _spawn_token(engine, entry.controller_id, tokens.from_spec({"subtypes": ["Army"], "colors": ["B"], "p": "0", "t": "0"}))
	if army != null:
		army.counters["+1/+1"] = int(army.counters.get("+1/+1", 0)) + n


## Bolster N (CR 701.39): +N counters on the creature you control with the least toughness.
func _bolster(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := _value(engine, entry, source, fx.params.get("n", 1))
	var weakest: GameObject = null
	for o in _permanents_of(engine, entry.controller_id, "Creature"):
		if weakest == null or engine.toughness_of(o) < engine.toughness_of(weakest):
			weakest = o
	if weakest != null:
		weakest.counters["+1/+1"] = int(weakest.counters.get("+1/+1", 0)) + n


## Populate (CR 701.36): a copy of your token with the most power.
func _populate(engine: RulesEngine, entry: StackEntry) -> void:
	var best: GameObject = null
	for o in _permanents_of(engine, entry.controller_id, "Creature"):
		if o.is_token and (best == null or engine.power_of(o) > engine.power_of(best)):
			best = o
	if best != null:
		_spawn_token(engine, entry.controller_id, best.definition as CardDefinition)


## Fabricate N (CR 702.123): N +1/+1 counters on it, or N 1/1 Servo artifact creatures.
func _fabricate(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 1))
	var pid := entry.controller_id
	var nm := (source.definition as CardDefinition).name if source != null and source.definition is CardDefinition else "it"
	var ans := _ask_yes_no(engine, entry, pid, "fabricate", "Fabricate %d: put %d +1/+1 counter(s) on %s? (No creates %d Servo token(s).)" % [n, n, nm, n])
	if ans.s == "paused":
		return
	var counters := true if ans.s == "auto" else bool(ans.value)
	if counters and source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
		source.counters["+1/+1"] = int(source.counters.get("+1/+1", 0)) + n
		return
	for _i in n:
		_spawn_token(engine, pid, tokens.from_spec({"subtypes": ["Servo"], "colors": [], "p": "1", "t": "1", "artifact": true}))


## Cascade (CR 702.85): exile cards from the top until a nonland card with lesser mana value, cast it free.
func _cascade(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	var pid := entry.controller_id
	var spell: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
	var limit := (spell.definition as CardDefinition).cmc if spell != null and spell.definition is CardDefinition else (source.definition as CardDefinition).cmc if source != null and source.definition is CardDefinition else 0
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	if not entry.ctx.has("cas_done"):
		var skipped: Array = []
		var found_id := -1
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
			if def != null and not def.is_land() and def.cmc < limit:
				found_id = moved.object_id
				break
			skipped.append(moved.object_id)
		engine.state.rng.shuffle(skipped)
		for oid in skipped:
			engine.put_library_bottom(int(oid), pid)
		entry.ctx["cas_done"] = true
		entry.ctx["cas_found"] = found_id
	var fid := int(entry.ctx.get("cas_found", -1))
	var found: GameObject = engine.state.objects.get(fid)
	if found == null or found.zone != EngineEnums.ZoneId.EXILE:
		return
	var ans := _ask_yes_no(engine, entry, pid, "cascade_cast", "Cascade: cast %s without paying its mana cost? (No puts it on the bottom of your library.)" % _name_of(engine, fid), [fid])
	if ans.s == "paused":
		return
	var cast_it := true if ans.s == "auto" else bool(ans.value)
	if cast_it and engine.cast_free(pid, fid):
		return
	engine.put_library_bottom(fid, pid)


## Undying / persist (CR 702.93, 702.79): the creature that just died comes back with a counter.
func _return_self(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.GRAVEYARD or source.is_token:
		return
	var back: GameObject = engine.state.zones.move(source.object_id, EngineEnums.ZoneId.BATTLEFIELD, source.owner_id)
	if back != null:
		var cname := str(fx.params.get("name", "+1/+1"))
		back.counters[cname] = int(back.counters.get(cname, 0)) + 1


# --- Search, scry, fights, equipment -----------------------------------------------------

## "Search your library for a basic land card, put it onto the battlefield tapped, then shuffle."
## The game picks the card: for lands, a type you have fewer of, favouring your commander's colors.
func _search_library(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	## Several different cards ("a Forest card and a Plains card"): one search for each filter.
	if fx.params.has("filters"):
		var fi := 0
		for one_filter in fx.params["filters"]:
			var sub := AbilityEffect.new()
			sub.kind = fx.kind
			sub.params = fx.params.duplicate()
			sub.params.erase("filters")
			sub.params["filter"] = one_filter
			sub.params["n"] = 1
			sub.params["link_prefix"] = "f%d_" % fi
			sub.params["no_shuffle"] = fi < (fx.params["filters"] as Array).size() - 1
			_search_library(engine, entry, source, sub)
			if engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION:
				return
			fi += 1
		return
	var pid := _acting_player(entry, fx)
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var filt: Dictionary = fx.params.get("filter", {})
	var want := int(fx.params.get("n", 1))
	var dest := EngineEnums.ZoneId.BATTLEFIELD if str(fx.params.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	var put_top := str(fx.params.get("to", "HAND")) == "TOP"
	var top_ids: Array = []
	var lprefix := str(fx.params.get("link_prefix", ""))
	var ref := _ref(entry, source)
	var shared_type := ""
	## A person at the table picks the card (one entry per card name; they may also decline to find one).
	if engine.interactive_seats.has(pid) and not bool(fx.params.get("same_type", false)):
		var picked: Array = []
		for i in want:
			var options: Array = []
			var seen := {}
			for oid in lib.object_ids:
				var cand0: GameObject = engine.state.objects.get(oid)
				if cand0 == null or picked.has(int(oid)) or not Query._matches(cand0, ref, filt):
					continue
				var nm := _name_of(engine, int(oid))
				if seen.has(nm):
					continue
				seen[nm] = true
				options.append(_card_option(engine, int(oid)))
			if options.is_empty():
				break
			var ans := _ask(engine, entry, pid, "%ssearch_%d" % [lprefix, i], "Search your library: choose a card (or decline to find nothing).", options, true)
			if ans.s == "paused":
				return
			if ans.s != "picked":
				break
			picked.append(int(ans.value))
		for pid_card in picked:
			if put_top:
				top_ids.append(int(pid_card))
				continue
			var got: GameObject = engine.state.zones.move(int(pid_card), dest, pid)
			if got != null and dest == EngineEnums.ZoneId.BATTLEFIELD and bool(fx.params.get("tapped", false)):
				got.tapped = true
		if not bool(fx.params.get("no_shuffle", false)):
			engine.shuffle_library(pid)
		_put_on_top(lib, top_ids)
		return
	for _i in want:
		var best_id := -1
		var best_score := -1000000
		for oid in lib.object_ids:
			var cand: GameObject = engine.state.objects.get(oid)
			if cand == null or top_ids.has(int(oid)) or not Query._matches(cand, ref, filt):
				continue
			## "that share a land type": the second land must share a basic land type with the first.
			if bool(fx.params.get("same_type", false)) and shared_type != "" and not (cand.definition as CardDefinition).type_line.contains(shared_type):
				continue
			var sc := _search_score(engine, pid, cand)
			if sc > best_score:
				best_score = sc
				best_id = int(oid)
		if best_id < 0:
			break
		var found_def := (engine.state.objects[best_id] as GameObject).definition as CardDefinition
		if bool(fx.params.get("same_type", false)) and shared_type == "":
			for bt in ["Plains", "Island", "Swamp", "Mountain", "Forest"]:
				if found_def.type_line.contains(bt):
					shared_type = bt
					break
		if put_top:
			top_ids.append(best_id)
			continue
		var moved: GameObject = engine.state.zones.move(best_id, dest, pid)
		if moved != null and dest == EngineEnums.ZoneId.BATTLEFIELD and bool(fx.params.get("tapped", false)):
			moved.tapped = true
	if not bool(fx.params.get("no_shuffle", false)):
		engine.shuffle_library(pid)
	_put_on_top(lib, top_ids)


## Cards a search found stay in the library; after the shuffle they go on top (the first found ends up topmost).
func _put_on_top(lib: Zone, ids: Array) -> void:
	for i in range(ids.size() - 1, -1, -1):
		if lib.object_ids.has(int(ids[i])):
			lib.object_ids.erase(int(ids[i]))
			lib.object_ids.insert(0, int(ids[i]))


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


## Scry N (CR 701.22): see _look_at_top.
func _scry(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	_look_at_top(engine, entry, int(fx.params.get("n", 1)), false)


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


## "As ~ enters, choose a creature type": the player picks (the rival takes the type it has most of).
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
	var names: Array = counts.keys()
	names.sort_custom(func(a, b) -> bool: return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and str(a) < str(b)))
	var options: Array = []
	for t in names:
		options.append({"value": str(t), "label": str(t), "detail": "%d of your cards" % int(counts[t])})
	var ans := _ask(engine, entry, pid, "chosen_type", "Choose a creature type.", options)
	if ans.s == "paused":
		return
	if ans.s == "picked":
		source.chosen_type = str(ans.value)
	elif not names.is_empty():
		source.chosen_type = str(names[0])


## Discover X (CR 701.57): exile cards from the top of your library until a nonland card with mana
## value X or less. You may cast it without paying its mana cost; if you don't (or can't) it goes to
## your hand. The rest go to the bottom of the library in a random order.
func _discover(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var x := _value(engine, entry, source, fx.params.get("n", 0))
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	## The exile step runs once; a pause for the cast question re-runs this effect afterwards.
	if not entry.ctx.has("dc_done"):
		var skipped: Array = []
		var found_id := -1
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
				found_id = moved.object_id
				break
			skipped.append(moved.object_id)
		engine.state.rng.shuffle(skipped)
		for oid in skipped:
			var back: GameObject = engine.state.zones.move(int(oid), EngineEnums.ZoneId.LIBRARY, pid)
			if back != null:
				lib.object_ids.erase(back.object_id)
				lib.object_ids.append(back.object_id)
		entry.ctx["dc_done"] = true
		entry.ctx["dc_found"] = found_id
		var fd: GameObject = engine.state.objects.get(found_id)
		entry.ctx["dc_mv"] = (fd.definition as CardDefinition).cmc if fd != null and fd.definition is CardDefinition else x
	var fid := int(entry.ctx.get("dc_found", -1))
	var found: GameObject = engine.state.objects.get(fid)
	if found == null or found.zone != EngineEnums.ZoneId.EXILE:
		return
	var ans := _ask_yes_no(engine, entry, pid, "discover_cast", "Discover: cast %s without paying its mana cost? (No puts it into your hand.)" % _name_of(engine, fid), [fid])
	if ans.s == "paused":
		return
	var cast_it := true if ans.s == "auto" else bool(ans.value)
	if cast_it and engine.cast_free(pid, fid):
		return
	engine.state.zones.move(fid, EngineEnums.ZoneId.HAND, pid)


## "As ~ enters, choose a color other than green": the player picks; the rival takes the first fitting
## color of its commander's identity.
func _choose_color(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null:
		return
	var avoid := str(fx.params.get("not", ""))
	var names := {"W": "White", "U": "Blue", "B": "Black", "R": "Red", "G": "Green"}
	var order: Array = []
	for c in engine.commander_identity(entry.controller_id):
		if str(c) != avoid:
			order.append(str(c))
	for c2 in ["W", "U", "B", "R", "G"]:
		if c2 != avoid and not order.has(c2):
			order.append(c2)
	var options: Array = []
	for c3 in order:
		options.append({"value": c3, "label": names[c3], "detail": ""})
	var ans := _ask(engine, entry, entry.controller_id, "chosen_color", "Choose a color.", options)
	if ans.s == "paused":
		return
	source.chosen_color = str(ans.value) if ans.s == "picked" else str(order[0])


## Hideaway N (CR 702.75): look at the top N cards, exile one face down, put the rest on the bottom in a
## random order. The permanent remembers which card (hideaway_card). The player picks; the rival takes the best.
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
	var options: Array = []
	for oid in ids:
		options.append(_card_option(engine, int(oid)))
	var ans := _ask(engine, entry, pid, "hideaway", "Hideaway: choose a card to exile face down. The rest go to the bottom.", options)
	if ans.s == "paused":
		return
	var best_id := -1
	if ans.s == "picked":
		best_id = int(ans.value)
	else:
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
			_note(engine, pid, "%s: creatures you control have total power %d, and you need %d to play the exiled card." % [_name_of(engine, source.object_id), total, need])
			return
	var card: GameObject = engine.state.objects.get(source.hideaway_card)
	if card == null or card.zone != EngineEnums.ZoneId.EXILE or not (card.definition is CardDefinition):
		return
	var def := card.definition as CardDefinition
	var yn := _ask_yes_no(engine, entry, pid, "play_hidden", "Play %s from exile without paying its mana cost?" % def.name, [card.object_id])
	if yn.s == "paused":
		return
	if yn.s == "picked" and not bool(yn.value):
		return
	if def.is_land():
		if not engine.can_play_land_now(pid):
			_note(engine, pid, "You can't play another land this turn, so %s stays exiled." % def.name)
			return
		engine.state.zones.move(card.object_id, EngineEnums.ZoneId.BATTLEFIELD, pid)
		engine.note_land_played(pid)
		source.hideaway_card = 0
		return
	if engine.cast_free(pid, card.object_id):
		source.hideaway_card = 0
	else:
		_note(engine, pid, "%s couldn't be cast right now, so it stays exiled." % def.name)


func _mill(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var n := int(fx.params.get("n", 1))
	for pid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
		for _i in n:
			if lib == null or lib.is_empty():
				break
			engine.state.zones.move(int(lib.object_ids[0]), EngineEnums.ZoneId.GRAVEYARD, pid)


## Discard N (CR 701.8): the player picks the cards; the rival throws away its cheapest (extra lands first).
func _discard(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	## "Discard your hand" / "Each player discards their hand": no choices; the controller's count feeds "draw that many cards".
	if bool(fx.params.get("all", false)):
		for hpid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
			var hz: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, int(hpid))
			var count := 0
			if hz != null:
				for hoid in hz.object_ids.duplicate():
					engine.discard_card(int(hpid), int(hoid))
					count += 1
			if int(hpid) == entry.controller_id:
				entry.ctx["discarded"] = count
		return
	var n := int(fx.params.get("n", 1))
	var plan := {}
	for pid in _players_for(engine, entry, str(fx.params.get("who", "CONTROLLER"))):
		var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
		var chosen: Array = []
		for i in n:
			var left: Array = []
			if hand != null:
				for oid in hand.object_ids:
					if not chosen.has(int(oid)):
						left.append(int(oid))
			if left.is_empty():
				break
			var options: Array = []
			for oid in left:
				options.append(_card_option(engine, int(oid)))
			var ans := _ask(engine, entry, int(pid), "discard_%d_%d" % [pid, i], "Discard a card (%d of %d)." % [i + 1, n], options)
			if ans.s == "paused":
				return
			if ans.s == "picked":
				chosen.append(int(ans.value))
			else:
				chosen.append(_cheapest_in_hand(engine, int(pid), chosen))
		plan[pid] = chosen
	for pid in plan.keys():
		for oid in plan[pid]:
			if int(oid) >= 0 and engine.state.objects.has(int(oid)):
				engine.discard_card(int(pid), int(oid))


func _cheapest_in_hand(engine: RulesEngine, pid: int, exclude: Array) -> int:
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	var lands := _controlled_of_type(engine, pid, "Land")
	var worst := -1
	var worst_score := 1000000
	if hand == null:
		return -1
	for oid in hand.object_ids:
		if exclude.has(int(oid)):
			continue
		var c: GameObject = engine.state.objects.get(oid)
		if c == null or not (c.definition is CardDefinition):
			continue
		var def := c.definition as CardDefinition
		var sc := def.cmc * 2 + (-3 if def.is_land() and lands >= 5 else (4 if def.is_land() else 0))
		if sc < worst_score:
			worst_score = sc
			worst = int(oid)
	return worst


## Surveil N (CR 701.46): for each of the top N cards the player chooses graveyard or stay on top.
## The rival puts spare lands (once it has six) into the graveyard.
func _surveil(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	_look_at_top(engine, entry, int(fx.params.get("n", 1)), true)


## Shared by surveil (to the graveyard) and scry (to the bottom).
func _look_at_top(engine: RulesEngine, entry: StackEntry, n: int, to_graveyard: bool) -> void:
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
	for i in mini(n, lib.object_ids.size()):
		top_ids.append(int(lib.object_ids[i]))
	var away: Array = []
	for i in top_ids.size():
		var oid := int(top_ids[i])
		var word := "graveyard" if to_graveyard else "bottom of your library"
		var ans := _ask_yes_no(engine, entry, pid, "look_%d" % i, "%s: put %s into the %s? (No keeps it on top.)" % ["Surveil" if to_graveyard else "Scry", _name_of(engine, oid), word], [oid])
		if ans.s == "paused":
			return
		if ans.s == "picked":
			if bool(ans.value):
				away.append(oid)
		else:
			var c: GameObject = engine.state.objects.get(oid)
			if c != null and c.definition is CardDefinition and (c.definition as CardDefinition).is_land() and lands >= 6:
				away.append(oid)
	for oid in away:
		if to_graveyard:
			engine.state.zones.move(int(oid), EngineEnums.ZoneId.GRAVEYARD, pid)
		else:
			engine.put_library_bottom(int(oid), pid)


func _return_from_graveyard(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var card: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if card == null or card.zone != EngineEnums.ZoneId.GRAVEYARD:
		return
	var dest := EngineEnums.ZoneId.BATTLEFIELD if str(fx.params.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	if card.definition is CardDefinition:
		entry.ctx["target_mv"] = (card.definition as CardDefinition).cmc
	var back: GameObject = engine.state.zones.move(card.object_id, dest, card.owner_id)
	## Finality counter (CR 122.1g): if it would die, it is exiled instead (see ZoneManager).
	if back != null:
		entry.ctx["last_moved"] = back.object_id
	if back != null and bool(fx.params.get("finality", false)) and dest == EngineEnums.ZoneId.BATTLEFIELD:
		back.counters["finality"] = 1


## CR 701.7: destroy all permanents matching the query (indestructible ones survive).
func _destroy_all(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	for obj in _each(engine, entry, source, fx.params.get("query", {})):
		engine.destroy_permanent(obj)


func _count(engine: RulesEngine, source: GameObject, raw: Variant) -> int:
	if raw is Dictionary and (raw as Dictionary).has("query"):
		var q: Variant = (raw as Dictionary).get("query", {})
		if q is Dictionary:
			return Query.count_objects(engine.state, source, q)
	return int(raw)


## A message in the History panel (why something did nothing).
func _note(engine: RulesEngine, pid: int, text: String) -> void:
	engine.state.log.append(EngineEnums.EventType.NOTE, pid, {"text": text})


## Asks the controller to choose each target a trigger left open. Returns false while the game waits for an answer.
## A "you may" slot can be skipped. The answers are added to entry.targets in slot order.
func _pick_trigger_targets(engine: RulesEngine, entry: StackEntry, source: GameObject) -> bool:
	var slots: Array = entry.ctx.get("pick_slots", [])
	var pid := entry.controller_id
	var chosen: Array = []
	var src_name := _name_of(engine, source.object_id) if source != null else "the ability"
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var options: Array = []
		for tid in engine.targeting.legal_ids(engine, slot, entry.source_id):
			if chosen.has(int(tid)) or entry.targets.has(int(tid)):
				continue
			options.append(_target_option(engine, int(tid)))
		if options.is_empty():
			continue
		var optional := bool(slot.get("optional", false))
		var prompt := "%s: choose a target%s." % [src_name, " (or skip it)" if optional else ""]
		var ans := _ask(engine, entry, pid, "trigger_target_%d" % i, prompt, options, optional)
		if ans.s == "paused":
			return false
		if ans.s == "picked":
			chosen.append(int(ans.value))
		elif ans.s == "auto" and not options.is_empty():
			chosen.append(int((options[0] as Dictionary).value))
	entry.targets.append_array(chosen)
	return true


## {value, label, detail} for choosing a target: a player, a card (with its rules text) or a spell on the stack.
func _target_option(engine: RulesEngine, tid: int) -> Dictionary:
	var player := TargetingManager.decode_player(tid)
	if player >= 0:
		return {"value": tid, "label": str(engine.state.players[player].name), "detail": "Player · %d life" % int(engine.state.players[player].life)}
	var obj: GameObject = engine.state.objects.get(tid)
	if obj != null and obj.definition is CardDefinition:
		var o := _card_option(engine, tid)
		var where := ""
		if obj.zone == EngineEnums.ZoneId.GRAVEYARD:
			where = "  (in %s's graveyard)" % str(engine.state.players[obj.owner_id].name)
		elif obj.zone == EngineEnums.ZoneId.EXILE:
			where = "  (in exile)"
		o["detail"] = str(o.get("detail", "")) + where
		return o
	return {"value": tid, "label": "Spell on the stack", "detail": ""}


## "Look at the top N cards of your library. You may put a X card from among them into your hand / onto the battlefield.
## Put the rest on the bottom (in a random order) / into your graveyard." The pick is asked of a person; the rival takes
## the best card. Nothing moves until every question is answered, so the effect can pause and run again.
func _look_top(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var n := _value(engine, entry, source, fx.params.get("n", 1))
	var top: Array = []
	for k in mini(n, lib.object_ids.size()):
		top.append(int(lib.object_ids[k]))
	var taken: Array = []
	var take: Dictionary = fx.params.get("take", {})
	if not take.is_empty():
		var ref := _ref(entry, source)
		var flt: Dictionary = take.get("filter", {})
		for i in int(take.get("count", 1)):
			var options: Array = []
			for oid in top:
				var c: GameObject = engine.state.objects.get(oid)
				if c != null and not taken.has(oid) and Query._matches(c, ref, flt):
					options.append(_card_option(engine, oid))
			if options.is_empty():
				break
			var ans := _ask(engine, entry, pid, "look_%d_%d" % [entry.cursor, i], "Choose a card from the top %d of your library." % n, options, bool(take.get("optional", true)))
			if ans.s == "paused":
				return
			if ans.s == "picked":
				taken.append(int(ans.value))
			elif ans.s == "auto":
				var best := -1
				var best_score := -1000000
				for o in options:
					var sc := _search_score(engine, pid, engine.state.objects[int(o.value)])
					if sc > best_score:
						best_score = sc
						best = int(o.value)
				if best >= 0:
					taken.append(best)
			else:
				break
	var to := EngineEnums.ZoneId.BATTLEFIELD if str(take.get("to", "HAND")) == "BATTLEFIELD" else EngineEnums.ZoneId.HAND
	for oid in taken:
		var moved: GameObject = engine.state.zones.move(int(oid), to, pid)
		if moved != null and to == EngineEnums.ZoneId.BATTLEFIELD and bool(take.get("tapped", false)):
			moved.tapped = true
	var rest: Array = []
	for oid in top:
		if not taken.has(oid):
			rest.append(oid)
	match str(fx.params.get("rest", "")):
		"GRAVEYARD":
			for oid in rest:
				engine.state.zones.move(int(oid), EngineEnums.ZoneId.GRAVEYARD, pid)
		"BOTTOM", "BOTTOM_RANDOM":
			if str(fx.params.get("rest", "")) == "BOTTOM_RANDOM":
				engine.state.rng.shuffle(rest)
			for oid in rest:
				lib.object_ids.erase(oid)
				lib.object_ids.append(oid)


## "At the beginning of the next end step, sacrifice it": remember what "it" is now (the source, a chosen target or the
## token just made) and let TriggerManager._fire_delayed ask for the action when the step comes.
func _delay(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var ref := str(fx.params.get("ref", "SELF"))
	var oid := 0
	if ref == "SELF":
		oid = entry.source_id
	elif ref == "LAST_CREATED":
		oid = int(entry.ctx.get("last_created", 0))
	elif ref.begins_with("TARGET_"):
		var slot := int(ref.substr(7))
		if slot >= 0 and slot < entry.targets.size():
			oid = int(entry.targets[slot])
	if oid == 0:
		return
	engine.state.delayed.append({
		"step": str(fx.params.get("step", "END")), "whose": str(fx.params.get("whose", "ANY")),
		"turn": engine.state.turn_number, "step_index": int(engine.state.step),
		"controller": entry.controller_id, "object_id": oid, "action": str(fx.params.get("action", "SACRIFICE")),
	})


## "Look at the top N cards of your library, then put them back in any order" (Sensei's Divining Top, Soothsaying): the
## player picks the new top card, then the next one, and so on (the last card is forced). A bot keeps the order.
func _reorder_top(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null:
		return
	var total := mini(_value(engine, entry, source, fx.params.get("n", 1)), lib.object_ids.size())
	if total <= 1:
		return
	var remaining: Array = []
	for i in total:
		remaining.append(int(lib.object_ids[i]))
	var order: Array = []
	while remaining.size() > 1:
		var options: Array = []
		for oid in remaining:
			options.append(_card_option(engine, int(oid)))
		var ans := _ask(engine, entry, pid, "reorder_%d" % order.size(), "Put back on top, card %d of %d (first pick is the new top card)." % [order.size() + 1, total], options)
		if ans.s == "paused":
			return
		var pick := int(ans.value) if ans.s == "picked" else int(remaining[0])
		order.append(pick)
		remaining.erase(pick)
	order.append_array(remaining)
	for i in total:
		lib.object_ids[i] = order[i]


## Chaos Warp: the owner shuffles the permanent into their library, then reveals the top card; a permanent card enters.
func _chaos_warp(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var obj: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var owner := obj.owner_id
	engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.LIBRARY, owner)
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, owner)
	if lib == null or lib.object_ids.is_empty():
		return
	lib.object_ids.shuffle()
	var top: GameObject = engine.state.objects.get(int(lib.object_ids[0]))
	if top != null and top.definition is CardDefinition:
		var d := top.definition as CardDefinition
		if not (d.is_instant() or d.is_sorcery()):
			engine.state.zones.move(top.object_id, EngineEnums.ZoneId.BATTLEFIELD, owner)


## "You may choose not to untap ~ during your untap step": ask once; a bot (or an unanswered question) untaps it.
func _untap_choice(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var obj: GameObject = engine.state.objects.get(int(fx.params.get("object_id", 0)))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD or not obj.tapped:
		return
	var ans := _ask_yes_no(engine, entry, entry.controller_id, "untap_%d" % obj.object_id,
		"Untap %s? (Say no to keep it tapped.)" % _name_of(engine, obj.object_id), [obj.object_id])
	if ans.s == "paused":
		return
	if ans.s != "picked" or bool(ans.value):
		obj.tapped = false


func _delayed_act(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	## "Draw a card at the beginning of the next turn's upkeep": the player draws, whatever became of the source.
	if str(fx.params.get("action", "")) == "DRAW":
		engine.draw_card(entry.controller_id)
		return
	var obj: GameObject = engine.state.objects.get(int(fx.params.get("object_id", 0)))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	match str(fx.params.get("action", "")):
		"EXILE":
			engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
		"RETURN_HAND":
			engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.HAND, obj.owner_id)
		"RETURN_CONTROL":
			obj.controller_id = obj.owner_id
			obj.summoned_this_turn = true
		"DESTROY":
			engine.destroy_permanent(obj)
		_:
			engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
	if engine.sba != null:
		engine.sba.check(engine)


## Gain control of target permanent (CR 108.4 / 613.1b), for good or until end of turn (returned at the end step).
func _gain_control(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	for obj in _affected(engine, entry, source, fx):
		var o := obj as GameObject
		if o.controller_id == entry.controller_id:
			continue
		o.controller_id = entry.controller_id
		o.summoned_this_turn = true
		if str(fx.params.get("duration", "")) == "END_OF_TURN":
			engine.state.delayed.append({"step": "END", "whose": "ANY", "turn": engine.state.turn_number, "step_index": int(engine.state.step),
				"controller": o.owner_id, "object_id": o.object_id, "action": "RETURN_CONTROL"})


## "Counter target spell unless its controller pays {1}": the spell's controller is asked (the rival pays when it can).
func _counter_unless_pay(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var w := AbilityEffect.new()
	w.kind = &"WARD"
	w.params = {"cost": str(fx.params.get("cost", "")), "life": 0, "target_stack_id": int(entry.targets[idx])}
	KeywordEffects._ward(self, engine, entry, w)


## "Target opponent reveals their hand" (shown in History).
func _reveal_hand(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	for pid in _players_for(engine, entry, "TARGET_%d" % int(fx.params.get("target", 0))):
		var names: Array = []
		var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, int(pid))
		if hand != null:
			for oid in hand.object_ids:
				names.append(_name_of(engine, int(oid)))
		_note(engine, entry.controller_id, "%s reveals their hand: %s." % [engine.state.players[int(pid)].name, ", ".join(PackedStringArray(names)) if not names.is_empty() else "(empty)"])


## "Target opponent reveals their hand. You choose a nonland card from it. That player discards that card." (Duress,
## Thoughtseize ...). You choose; the rival chooses its most expensive match.
func _discard_chosen(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var source := engine.state.objects.get(entry.source_id) as GameObject
	var flt: Dictionary = fx.params.get("filter", {})
	for pid in _players_for(engine, entry, "TARGET_%d" % int(fx.params.get("target", 0))):
		var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, int(pid))
		if hand == null:
			continue
		var options: Array = []
		for oid in hand.object_ids:
			var c: GameObject = engine.state.objects.get(oid)
			if c != null and Query._matches(c, _ref(entry, source), flt):
				options.append(_card_option(engine, int(oid)))
		if options.is_empty():
			continue
		var ans := _ask(engine, entry, entry.controller_id, "discard_chosen_%d" % int(pid), "Choose a card to make them discard.", options)
		if ans.s == "paused":
			return
		var pick := -1
		if ans.s == "picked":
			pick = int(ans.value)
		else:
			var best := -1
			for o in options:
				var cd: GameObject = engine.state.objects[int(o.value)]
				var mv := (cd.definition as CardDefinition).cmc if cd.definition is CardDefinition else 0
				if mv > best:
					best = mv
					pick = int(o.value)
		if pick >= 0:
			engine.discard_card(int(pid), pick)


## "Prevent the next 3 damage that would be dealt to any target this turn" / "Prevent all combat damage that would be dealt
## this turn": adds a shield (see RulesEngine.apply_prevention).
func _prevent(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var to := str(fx.params.get("to", "ANY"))
	var shield := {"to": "ANY", "combat_only": bool(fx.params.get("combat_only", false)), "n": int(_value(engine, entry, source, fx.params.get("n", -1)))}
	if to == "YOU":
		shield["to"] = "PLAYER"
		shield["player_id"] = entry.controller_id
	elif to == "YOUR_STUFF":
		shield["to"] = "YOUR_STUFF"
		shield["player_id"] = entry.controller_id
	elif to == "SELF":
		shield["to"] = "OBJECT"
		shield["object_id"] = entry.source_id
	elif to.begins_with("TARGET_"):
		var slot := int(to.substr(7))
		if slot < 0 or slot >= entry.targets.size():
			return
		var tp := TargetingManager.decode_player(int(entry.targets[slot]))
		if tp >= 0:
			shield["to"] = "PLAYER"
			shield["player_id"] = tp
		else:
			shield["to"] = "OBJECT"
			shield["object_id"] = int(entry.targets[slot])
	engine.state.prevention.append(shield)


## "Put two cards from your hand on top of your library in any order" (Brainstorm, Ponder): you pick them; the rival puts
## back what it wants least. The last card picked ends up on top.
func _put_back(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null:
		return
	var chosen: Array = []
	for i in int(fx.params.get("n", 1)):
		var options: Array = []
		for oid in hand.object_ids:
			if not chosen.has(int(oid)):
				options.append(_card_option(engine, int(oid)))
		if options.is_empty():
			break
		var ans := _ask(engine, entry, pid, "putback_%d_%d" % [entry.cursor, i], "Put a card from your hand on top of your library (%d of %d)." % [i + 1, int(fx.params.get("n", 1))], options)
		if ans.s == "paused":
			return
		if ans.s == "picked":
			chosen.append(int(ans.value))
		else:
			var worst := -1
			var worst_score := 1000000
			for o in options:
				var cd := (engine.state.objects[int(o.value)] as GameObject).definition as CardDefinition
				var sc := cd.cmc * 2 + (-3 if cd.is_land() else 0)
				if sc < worst_score:
					worst_score = sc
					worst = int(o.value)
			chosen.append(worst)
	for oid2 in chosen:
		engine.state.zones.move(int(oid2), EngineEnums.ZoneId.LIBRARY, pid)


## "~ deals 2 damage to that player unless they sacrifice a creature of their choice" (Mogis), "Its controller may sacrifice it.
## If they don't, ~ deals 5 damage to that player" (Star Athlete), "target enchantment deals damage equal to its mana value to
## its controller unless that player sacrifices it" (Enchanter's Bane). The player is asked; a rival pays with a token or a cheap
## permanent when the damage would hurt, otherwise takes it.
func _unless_sacrifice(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var ref := _ref(entry, source)
	for pid in _players_for(engine, entry, str(fx.params.get("who", "TRIGGER_PLAYER"))):
		var cands: Array = []
		if fx.params.has("sac_target"):
			var slot := int(fx.params["sac_target"])
			if slot >= 0 and slot < entry.targets.size():
				var tobj: GameObject = engine.state.objects.get(int(entry.targets[slot]))
				if tobj != null and tobj.zone == EngineEnums.ZoneId.BATTLEFIELD and tobj.controller_id == int(pid):
					cands.append(tobj)
		else:
			var q: Dictionary = fx.params.get("query", {})
			for o in _permanents_of(engine, int(pid)):
				if q.is_empty() or Query._matches(o, ref, q):
					cands.append(o)
		var dmg := _value(engine, entry, source, fx.params.get("n", 0))
		var gave := false
		if not cands.is_empty():
			var prompt := "Sacrifice %s to avoid %d damage?" % [_name_of(engine, (cands[0] as GameObject).object_id) if cands.size() == 1 else "a permanent", dmg]
			var ans := _ask_yes_no(engine, entry, int(pid), "unless_sac_%d" % int(pid), prompt)
			if ans.s == "paused":
				return
			var yes := false
			if ans.s == "picked":
				yes = bool(ans.value)
			else:
				## The rival gives up a token or a one-mana permanent when the damage is real.
				var cheap := false
				for c in cands:
					var cd := (c as GameObject).definition as CardDefinition
					if (c as GameObject).is_token or (cd != null and cd.cmc <= 1):
						cheap = true
				yes = cheap and dmg >= 2
			if yes:
				var victim: GameObject = cands[0]
				if cands.size() > 1:
					var options: Array = []
					for c2 in cands:
						options.append(_card_option(engine, (c2 as GameObject).object_id))
					var pick := _ask(engine, entry, int(pid), "unless_sac_pick_%d" % int(pid), "Choose what to sacrifice.", options)
					if pick.s == "paused":
						return
					if pick.s == "picked":
						victim = engine.state.objects.get(int(pick.value))
					else:
						var best_score := 1000000
						for c3 in cands:
							var cd3 := (c3 as GameObject).definition as CardDefinition
							var sc := -1 if (c3 as GameObject).is_token else (cd3.cmc if cd3 != null else 0)
							if sc < best_score:
								best_score = sc
								victim = c3
				if victim != null:
					engine.state.zones.move(victim.object_id, EngineEnums.ZoneId.GRAVEYARD, victim.owner_id)
					gave = true
					if engine.sba != null:
						engine.sba.check(engine)
		if not gave and dmg > 0:
			_damage_player(engine, entry, int(pid), dmg)


## "Discard two cards unless you discard an artifact card" (Thirst for Knowledge): you may give up one card of the type instead.
func _discard_alt(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null:
		return
	var utype := str(fx.params.get("unless_type", "")).to_lower()
	var n := int(fx.params.get("n", 1))
	var matching: Array = []
	for oid in hand.object_ids:
		var c: GameObject = engine.state.objects.get(oid)
		if c != null and c.definition is CardDefinition and (c.definition as CardDefinition).type_line.to_lower().contains(utype):
			matching.append(int(oid))
	var use_alt := false
	if not matching.is_empty():
		var ans := _ask_yes_no(engine, entry, pid, "discard_alt", "Discard one %s card instead of %d cards?" % [utype, n])
		if ans.s == "paused":
			return
		use_alt = true if ans.s == "auto" else bool(ans.value)
	if use_alt:
		var pick: int = int(matching[0])
		if matching.size() > 1:
			var options: Array = []
			for mid in matching:
				options.append(_card_option(engine, int(mid)))
			var pa := _ask(engine, entry, pid, "discard_alt_pick", "Choose the %s card to discard." % utype, options)
			if pa.s == "paused":
				return
			if pa.s == "picked":
				pick = int(pa.value)
			else:
				var cheapest := 1000000
				for mid2 in matching:
					var cd := (engine.state.objects[int(mid2)] as GameObject).definition as CardDefinition
					if cd.cmc < cheapest:
						cheapest = cd.cmc
						pick = int(mid2)
		engine.discard_card(pid, int(pick))
		return
	var plain := AbilityEffect.new()
	plain.kind = &"DISCARD"
	plain.params = {"n": n, "who": "CONTROLLER"}
	_discard(engine, entry, plain)


## "You may put an artifact card from your hand onto the battlefield" (Master Transmuter): you pick; the rival puts its best.
func _put_from_hand(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null:
		return
	var ref := _ref(entry, source)
	var q: Dictionary = fx.params.get("query", {})
	var options: Array = []
	for oid in hand.object_ids:
		var c: GameObject = engine.state.objects.get(oid)
		if c != null and Query._matches(c, ref, q):
			options.append(_card_option(engine, int(oid)))
	if options.is_empty():
		return
	var ans := _ask(engine, entry, pid, "put_from_hand_%d" % entry.cursor, "Choose a card from your hand to put onto the battlefield.", options, bool(fx.params.get("optional", true)))
	if ans.s == "paused":
		return
	var pick := -1
	if ans.s == "picked":
		pick = int(ans.value)
	elif ans.s == "auto":
		var best := -1
		for o in options:
			var cd := (engine.state.objects[int(o.value)] as GameObject).definition as CardDefinition
			if cd.cmc > best:
				best = cd.cmc
				pick = int(o.value)
	if pick < 0:
		return
	var moved: GameObject = engine.state.zones.move(pick, EngineEnums.ZoneId.BATTLEFIELD, pid)
	if moved != null and bool(fx.params.get("tapped", false)):
		moved.tapped = true


## "Return all attacking creatures to their owners' hands" (Aetherize), "Each player sacrifices all permanents they control that
## are one or more colors" (All Is Dust, `to` = GRAVEYARD): every permanent matching the query changes zone.
func _move_all(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var dest := Query._zone_id(str(fx.params.get("to", "HAND")))
	for obj in _each(engine, entry, source, fx.params.get("query", {})):
		var o := obj as GameObject
		if o.zone == EngineEnums.ZoneId.BATTLEFIELD:
			engine.state.zones.move(o.object_id, dest, o.owner_id)
	if engine.sba != null:
		engine.sba.check(engine)


## "Exile each opponent's graveyard" (Soul-Guide Lantern).
func _exile_graveyards(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	for pid in _players_for(engine, entry, str(fx.params.get("who", "EACH_OPPONENT"))):
		var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, int(pid))
		if gy == null:
			continue
		for oid in gy.object_ids.duplicate():
			engine.state.zones.move(int(oid), EngineEnums.ZoneId.EXILE, int(pid))


## Combustible Gearhulk: the chosen opponent decides whether you draw three cards; if not you mill three and ~ deals damage to them
## equal to the total mana value of the milled cards.
func _opp_draw_or_mill(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var pids := _players_for(engine, entry, "TARGET_%d" % int(fx.params.get("target", 0)))
	if pids.is_empty():
		return
	var opp := int(pids[0])
	var me := entry.controller_id
	var ans := _ask_yes_no(engine, entry, opp, "gearhulk", "Let %s draw three cards? (If not, they mill three cards and you take damage equal to their total mana value.)" % engine.state.players[me].name)
	if ans.s == "paused":
		return
	## The rival lets you draw only when the milling could hurt more than the cards help.
	var let_draw := bool(ans.value) if ans.s == "picked" else (engine.state.players[opp].life <= 20)
	if let_draw:
		for _i in 3:
			engine.draw_card(me)
		return
	var total := 0
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, me)
	for _j in 3:
		if lib == null or lib.is_empty():
			break
		var top: GameObject = engine.state.objects.get(int(lib.object_ids[0]))
		if top != null and top.definition is CardDefinition:
			total += (top.definition as CardDefinition).cmc
		engine.state.zones.move(int(lib.object_ids[0]), EngineEnums.ZoneId.GRAVEYARD, me)
	if total > 0:
		_damage_player(engine, entry, opp, total)


## "You may play an additional land this turn": adds to this turn's extra land drops.
func _extra_land(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var prev: Dictionary = engine.state.extra_land_once.get(entry.controller_id, {})
	var have := int(prev.get("n", 0)) if int(prev.get("turn", -1)) == engine.state.turn_number else 0
	engine.state.extra_land_once[entry.controller_id] = {"turn": engine.state.turn_number, "n": have + int(fx.params.get("n", 1))}


## Cleanup step (CR 514.1): the active player discards until they have no more than their maximum hand size. A person chooses
## each card; the rival discards its cheapest (extra lands first).
func _discard_to_hand_size(engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var over := engine.hand_size(pid) - engine.max_hand_size(pid)
	if over <= 0:
		return
	var plain := AbilityEffect.new()
	plain.kind = &"DISCARD"
	plain.params = {"n": over, "who": "CONTROLLER"}
	_discard(engine, entry, plain)
