class_name KeywordRules
extends RefCounted

## Keyword abilities that change how a card is cast or used: kicker, flashback, escape, retrace, dash, prowl,
## emerge, morph, madness, miracle, suspend, rebound, convoke, delve, cycling, ninjutsu, crew, ward, phasing.
## Card data comes from CardDefinition.kw() (see KeywordLines). Everything here runs inside RulesEngine.

var engine: RulesEngine


func _init(p_engine: RulesEngine = null) -> void:
	engine = p_engine


# --- Helpers --------------------------------------------------------------------------------

func _def(obj: GameObject) -> CardDefinition:
	return obj.definition as CardDefinition if obj != null and obj.definition is CardDefinition else null


func kw_of(obj: GameObject) -> Dictionary:
	var d := _def(obj)
	var out: Dictionary = d.kw() if d != null else {}
	## Keyword abilities an effect gives it ("is a Vehicle artifact with crew 5", Swift Reconfiguration).
	if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD and engine != null and engine.layers != null:
		var specs: Array = engine.layers.attached_specs(engine.state, obj, "grant_kw")
		if not specs.is_empty():
			out = out.duplicate()
			for sp in specs:
				var g: Dictionary = (sp as Dictionary)["grant_kw"]
				for k in g.keys():
					out[k] = g[k]
	return out


func _cost(text: String) -> ManaCost:
	return ManaCost.parse(text)


func _zone_ids(zone_id: int, pid: int) -> Array:
	var z: Zone = engine.state.zones.get_zone(zone_id, pid)
	return z.object_ids.duplicate() if z != null else []


func _obj(oid: int) -> GameObject:
	return engine.state.objects.get(oid)


func _is_creature(obj: GameObject) -> bool:
	return engine.is_creature_now(obj)


# --- Casting: costs and modes -----------------------------------------------------------------

## Works out what it takes to cast `obj` with `extra` ({mode, kicks, kick_idx, sac_id, discard_id}).
## Returns {ok, error, cost (hybrid not yet resolved), mode, kicks, exile_ids, sac_id, discard_id, face_down}.
func plan(pid: int, obj: GameObject, extra: Dictionary) -> Dictionary:
	var def := _def(obj)
	var out := {"ok": true, "error": "", "cost": ManaCost.new(), "mode": str(extra.get("mode", "")), "kicks": 0,
		"exile_ids": [], "sac_id": 0, "discard_id": 0, "face_down": false, "life": 0, "from_zone": obj.zone}
	if def == null:
		out.ok = false
		out.error = "no card"
		return out
	var kw := def.kw()
	var mode := str(out.mode)
	var base: ManaCost = ManaCost.for_card(def.mana_cost, int(def.cmc))
	match mode:
		"flashback":
			if not kw.has("flashback") or obj.zone != EngineEnums.ZoneId.GRAVEYARD:
				return _fail(out, "can't flash this back")
			base = _cost(str(kw.flashback))
		"escape":
			if not kw.has("escape") or obj.zone != EngineEnums.ZoneId.GRAVEYARD:
				return _fail(out, "can't escape")
			base = _cost(str(kw.escape.cost))
			var others: Array = []
			for oid in _zone_ids(EngineEnums.ZoneId.GRAVEYARD, pid):
				if int(oid) != obj.object_id:
					others.append(int(oid))
			var need := int(kw.escape.n)
			if others.size() < need:
				return _fail(out, "needs %d other cards in your graveyard" % need)
			others.sort_custom(func(a, b) -> bool: return _value_of(int(a)) < _value_of(int(b)))
			out.exile_ids = others.slice(0, need)
		"retrace":
			if not kw.has("retrace") or obj.zone != EngineEnums.ZoneId.GRAVEYARD:
				return _fail(out, "can't retrace")
			var land := int(extra.get("discard_id", 0))
			if land == 0:
				for oid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
					var h := _obj(int(oid))
					if h != null and _def(h) != null and _def(h).is_land():
						land = int(oid)
						break
			if land == 0:
				return _fail(out, "needs a land card to discard")
			out.discard_id = land
		"dash":
			if not kw.has("dash"):
				return _fail(out, "no dash")
			base = _cost(str(kw.dash))
		"prowl":
			if not kw.has("prowl") or not prowl_ready(pid, def):
				return _fail(out, "prowl needs a matching creature to have hurt a player this turn")
			base = _cost(str(kw.prowl))
		"emerge":
			if not kw.has("emerge"):
				return _fail(out, "no emerge")
			var sac := int(extra.get("sac_id", 0))
			if sac == 0:
				sac = _best_emerge_sac(pid)
			var victim := _obj(sac)
			if victim == null or victim.controller_id != pid or not _is_creature(victim):
				return _fail(out, "emerge needs a creature to sacrifice")
			out.sac_id = sac
			base = _cost(str(kw.emerge))
			base.generic = maxi(0, base.generic - int(_def(victim).cmc if _def(victim) != null else 0))
		"morph", "megamorph", "disguise":
			if not (kw.has("morph") or kw.has("megamorph") or kw.has("disguise")):
				return _fail(out, "no morph")
			base = _cost("{3}")
			out.face_down = true
		"madness":
			if not kw.has("madness"):
				return _fail(out, "no madness")
			base = _cost(str(kw.madness))
		"miracle":
			if not kw.has("miracle"):
				return _fail(out, "no miracle")
			base = _cost(str(kw.miracle))
		"impending":
			if not kw.has("impending"):
				return _fail(out, "no impending")
			base = _cost(str(kw.impending.cost))
		_:
			var alt := _alt_cost(pid, obj, def, kw, mode, extra, out)
			if not bool(out.ok):
				return out
			if alt != null:
				base = alt
	## Escalate (CR 702.120): the escalate cost once for each mode beyond the first.
	var extra_modes := int(extra.get("escalate", 0))
	if extra_modes > 0 and kw.has("escalate"):
		for _e in extra_modes:
			base.absorb(_cost(str(kw.escalate)))
	out["escalate"] = extra_modes if kw.has("escalate") else 0
	## Gift (CR 702.174): promising the gift is a choice made while casting; it costs nothing.
	out["gift"] = bool(extra.get("gift", false)) and kw.has("gift")
	_additional_costs(pid, obj, def, kw, extra, base, out)
	if not bool(out.ok):
		return out
	## {X} in a spell's cost (CR 107.3): the caster names X (extra.x); otherwise the largest X that can be paid.
	if base.x > 0:
		var per := base.x
		base.x = 0
		var want := int(extra.get("x", -1))
		var xv := want if want >= 0 else engine.max_x_for(pid, base, per)
		base.generic += xv * per
		out["x"] = xv
	## Kicker (CR 702.33): optional extra cost.
	var kicks := int(extra.get("kicks", 0))
	if kicks > 0:
		if kw.has("multikicker"):
			var mk := _cost(str(kw.multikicker))
			for _i in kicks:
				base.absorb(mk)
		elif kw.has("kicker"):
			var kl: Array = kw.kicker
			var idx := clampi(int(extra.get("kick_idx", 0)), 0, kl.size() - 1)
			base.absorb(_cost(str(kl[idx])))
			kicks = 1
		else:
			kicks = 0
	out.kicks = kicks
	## "Reveal a Dinosaur card from your hand or pay {1}": revealing is free, so only pay when the hand has none.
	if kw.has("reveal_or_pay"):
		var rp: Dictionary = kw.reveal_or_pay
		var have := false
		for hid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
			var hc := _obj(int(hid))
			if hc != null and hc.object_id != obj.object_id and _def(hc) != null and _def(hc).type_line.to_lower().contains(str(rp.type)):
				have = true
				break
		if not have:
			base.absorb(_cost(str(rp.cost)))
	if obj.zone == EngineEnums.ZoneId.COMMAND:
		var key := def.oracle_id if def.oracle_id != "" else def.name
		var n := int(engine.state.players[pid].commander_cast_count.get(key, 0))
		base.generic += n * engine.state.rules.commander_tax_step
	base.generic = maxi(0, base.generic - engine.cost_reduction(pid, obj))
	out.cost = base
	return out


func _fail(out: Dictionary, why: String) -> Dictionary:
	out.ok = false
	out.error = why
	return out


## Alternative costs (CR 118.9) of the keyword abilities: evoke, blitz, overload, surge, spectacle, prototype,
## freerunning, warp, sneak, mayhem, web-slinging, harmonize, awaken, bestow, mutate, disturb, more than meets the
## eye, cleave, offering, Sephara-style "tap creatures", and casting foretold / plotted / warped / airbent cards from
## exile. Returns the cost, or null when `mode` isn't one of them (then the mana cost is used). Fails `out` when the
## mode can't be used right now.
func _alt_cost(pid: int, obj: GameObject, def: CardDefinition, kw: Dictionary, mode: String, extra: Dictionary, out: Dictionary) -> ManaCost:
	if mode == "":
		return null
	var st := engine.state
	var me: PlayerState = st.players[pid]
	var key := mode.replace("-", "_")
	match mode:
		"evoke", "blitz", "overload", "prototype", "cleave", "mutate", "bestow", "web_slinging", "more_than_meets_the_eye", "warp":
			if not kw.has(key):
				_fail(out, "no %s" % mode)
				return null
			if mode == "warp" and obj.zone != EngineEnums.ZoneId.HAND:
				_fail(out, "warp is cast from your hand")
				return null
			if mode == "web_slinging":
				var tapped_id := int(extra.get("return_id", 0))
				if tapped_id == 0:
					for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
						var o := _obj(int(oid))
						if o != null and o.controller_id == pid and o.tapped and _is_creature(o):
							tapped_id = int(oid)
							break
				if tapped_id == 0:
					_fail(out, "web-slinging needs a tapped creature to return")
					return null
				out["return_ids"] = [tapped_id]
			var c := _cost(str((kw[key] as Dictionary).cost if kw[key] is Dictionary else kw[key]))
			return c
		"surge":
			if not kw.has("surge") or me.spells_this_turn.is_empty():
				_fail(out, "surge needs another spell cast this turn")
				return null
			return _cost(str(kw.surge))
		"spectacle":
			var lost := false
			for p in st.players:
				if p.player_id != pid and p.life_lost_this_turn > 0:
					lost = true
			if not kw.has("spectacle") or not lost:
				_fail(out, "spectacle needs an opponent to have lost life this turn")
				return null
			return _cost(str(kw.spectacle))
		"freerunning":
			if not kw.has("freerunning") or not (me.combat_damagers_types.has("Assassin") or me.commander_hit_this_turn):
				_fail(out, "freerunning needs an Assassin or your commander to have dealt combat damage to a player this turn")
				return null
			return _cost(str(kw.freerunning))
		"sneak":
			if not kw.has("sneak"):
				_fail(out, "no sneak")
				return null
			var ub: Array = _unblocked_attackers(pid)
			var rid := int(extra.get("return_id", ub[0] if not ub.is_empty() else 0))
			if not ub.has(rid):
				_fail(out, "sneak needs an unblocked attacker to return")
				return null
			out["return_ids"] = [rid]
			out["sneak_defender"] = engine.defender_of(rid)
			return _cost(str(kw.sneak))
		"mayhem":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or obj.discarded_turn != st.turn_number or not kw.has("mayhem"):
				_fail(out, "mayhem needs it discarded this turn")
				return null
			return _cost(str(kw.mayhem)) if not (kw.mayhem is bool) else ManaCost.for_card(def.mana_cost, def.cmc)
		"harmonize":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or not kw.has("harmonize"):
				_fail(out, "harmonize is cast from your graveyard")
				return null
			var hc := _cost(str(kw.harmonize))
			var tap_id := int(extra.get("tap_id", 0))
			var best_p := -1
			if tap_id == 0:
				for oid2 in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
					var o2 := _obj(int(oid2))
					if o2 != null and o2.controller_id == pid and not o2.tapped and _is_creature(o2) and engine.power_of(o2) > best_p:
						best_p = engine.power_of(o2)
						tap_id = int(oid2)
			if tap_id != 0:
				hc.generic = maxi(0, hc.generic - maxi(0, engine.power_of(_obj(tap_id))))
				out["tap_ids"] = [tap_id]
			return hc
		"awaken":
			if not kw.has("awaken"):
				_fail(out, "no awaken")
				return null
			return _cost(str(kw.awaken.cost))
		"disturb":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or not kw.has("disturb") or def.back_face == null:
				_fail(out, "disturb casts the back face from your graveyard")
				return null
			return _cost(str(kw.disturb))
		"jump_start":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or not kw.has("jump_start"):
				_fail(out, "jump-start is cast from your graveyard")
				return null
			var dj := int(extra.get("discard_id", 0))
			if dj == 0:
				dj = _worst_in_hand(pid, obj.object_id)
			if dj == 0:
				_fail(out, "jump-start needs a card to discard")
				return null
			out.discard_id = dj
			return ManaCost.for_card(def.mana_cost, def.cmc)
		"aftermath":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or def.other_half == null:
				_fail(out, "aftermath halves are cast from your graveyard")
				return null
			return ManaCost.for_card(def.other_half.mana_cost, def.other_half.cmc)
		"adventure", "half":
			if def.other_half == null or obj.zone != EngineEnums.ZoneId.HAND:
				_fail(out, "no other half")
				return null
			return ManaCost.for_card(def.other_half.mana_cost, def.other_half.cmc)
		"fuse":
			if not kw.has("fuse") or def.other_half == null or obj.zone != EngineEnums.ZoneId.HAND:
				_fail(out, "fuse casts both halves from your hand")
				return null
			var fc := ManaCost.for_card(def.mana_cost, def.cmc)
			fc.absorb(ManaCost.for_card(def.other_half.mana_cost, def.other_half.cmc))
			return fc
		"foretold":
			if obj.zone != EngineEnums.ZoneId.EXILE or obj.exile_cast != "foretell" or obj.foretold_turn >= st.turn_number:
				_fail(out, "a foretold card is cast on a later turn")
				return null
			return _cost(str(kw.get("foretell", def.mana_cost)))
		"plotted":
			if obj.zone != EngineEnums.ZoneId.EXILE or obj.exile_cast != "plot" or obj.plotted_turn >= st.turn_number:
				_fail(out, "a plotted card is cast on a later turn")
				return null
			return ManaCost.new()
		"warped":
			if obj.zone != EngineEnums.ZoneId.EXILE or obj.exile_cast != "warp" or obj.plotted_turn >= st.turn_number:
				_fail(out, "a warped card can be cast after the turn it was exiled")
				return null
			return ManaCost.for_card(def.mana_cost, def.cmc)
		"airbent":
			if obj.zone != EngineEnums.ZoneId.EXILE or obj.exile_cast != "airbend":
				_fail(out, "not airbent")
				return null
			return _cost("{2}")
		"offering":
			if not kw.has("offering"):
				_fail(out, "no offering")
				return null
			var sac := int(extra.get("sac_id", 0))
			if sac == 0:
				for oid3 in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
					var o3 := _obj(int(oid3))
					if o3 != null and o3.controller_id == pid and _def(o3) != null and Query._subtype_words(_def(o3).type_line).has(str(kw.offering).capitalize()):
						sac = int(oid3)
						break
			if sac == 0:
				_fail(out, "offering needs a %s to sacrifice" % str(kw.offering).capitalize())
				return null
			out.sac_id = sac
			var oc := ManaCost.for_card(def.mana_cost, def.cmc)
			oc.generic = maxi(0, oc.generic - _def(_obj(sac)).cmc)
			return oc
		"alt_tap":
			if not kw.has("alt_tap"):
				_fail(out, "no such cost")
				return null
			var need_n := int(kw.alt_tap.n)
			var flyers: Array = []
			for oid4 in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
				var o4 := _obj(int(oid4))
				if o4 != null and o4.controller_id == pid and not o4.tapped and _is_creature(o4) and engine.has_keyword(o4, str(kw.alt_tap.keyword).capitalize()):
					flyers.append(int(oid4))
			if flyers.size() < need_n:
				_fail(out, "needs %d untapped creatures with %s" % [need_n, str(kw.alt_tap.keyword)])
				return null
			out["tap_ids"] = flyers.slice(0, need_n)
			return _cost(str(kw.alt_tap.cost))
	return null


## Additional costs (CR 118.8) chosen while casting: buyback, entwine, replicate, conspire, casualty, bargain, squad,
## offspring, teamwork, collect evidence, splice, spree / tiered modes, and the printed "as an additional cost to cast
## this spell, sacrifice / discard / pay life". Adds to `base` and records what else must be paid in `out`.
func _additional_costs(pid: int, obj: GameObject, def: CardDefinition, kw: Dictionary, extra: Dictionary, base: ManaCost, out: Dictionary) -> void:
	for key in ["buyback", "entwine", "offspring"]:
		if bool(extra.get(key, false)) and kw.has(key):
			base.absorb(_cost(str(kw[key])))
			out[key] = true
	for key2 in ["replicate", "squad"]:
		var n := int(extra.get(key2, 0))
		if n > 0 and kw.has(key2):
			for _i in n:
				base.absorb(_cost(str(kw[key2])))
			out[key2] = n
	## Spree (CR 702.172) and tiered (CR 702.183): each chosen mode's extra cost.
	var picked: Array = extra.get("modes", [])
	if not picked.is_empty():
		var costs := _mode_costs(def)
		for i in picked:
			if int(i) >= 0 and int(i) < costs.size():
				base.absorb(_cost(str(costs[int(i)])))
		out["modes"] = picked.duplicate()
	if bool(extra.get("conspire", false)) and kw.has("conspire"):
		var pair := _conspirators(pid, def)
		if pair.size() < 2:
			_fail(out, "conspire needs two untapped creatures that share a color with it")
			return
		var taps: Array = out.get("tap_ids", [])
		taps.append_array(pair)
		out["tap_ids"] = taps
		out["conspire"] = true
	if bool(extra.get("casualty", false)) and kw.has("casualty"):
		var victim := int(extra.get("casualty_id", 0))
		if victim == 0:
			for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
				var o := _obj(int(oid))
				if o != null and o.controller_id == pid and _is_creature(o) and engine.power_of(o) >= int(kw.casualty) and (victim == 0 or _value_of(int(oid)) < _value_of(victim)):
					victim = int(oid)
		if victim == 0:
			_fail(out, "casualty needs a creature with power %d or more" % int(kw.casualty))
			return
		out["sac_ids"] = (out.get("sac_ids", []) as Array) + [victim]
		out["casualty"] = true
	if bool(extra.get("bargain", false)) and kw.has("bargain"):
		var bv := int(extra.get("bargain_id", 0))
		if bv == 0:
			for oid2 in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
				var o2 := _obj(int(oid2))
				if o2 != null and o2.controller_id == pid and _def(o2) != null and (o2.is_token or _def(o2).type_line.contains("Artifact") or _def(o2).type_line.contains("Enchantment")) \
						and (bv == 0 or _value_of(int(oid2)) < _value_of(bv)):
					bv = int(oid2)
		if bv == 0:
			_fail(out, "bargain needs an artifact, enchantment or token to sacrifice")
			return
		out["sac_ids"] = (out.get("sac_ids", []) as Array) + [bv]
		out["bargain"] = true
	if bool(extra.get("teamwork", false)) and kw.has("teamwork"):
		var team := crew_creatures(pid, obj, int(kw.teamwork))
		if team.is_empty():
			_fail(out, "teamwork needs creatures with total power %d" % int(kw.teamwork))
			return
		out["tap_ids"] = (out.get("tap_ids", []) as Array) + team
		out["teamwork"] = true
	if bool(extra.get("evidence", false)) and kw.has("collect_evidence"):
		var ev := _evidence(pid, obj.object_id, int(kw.collect_evidence))
		if ev.is_empty():
			_fail(out, "not enough mana value in your graveyard to collect evidence %d" % int(kw.collect_evidence))
			return
		out.exile_ids = (out.exile_ids as Array) + ev
		out["evidence"] = true
	## Splice onto Arcane (CR 702.47): reveal splice cards from your hand and pay their splice costs.
	for sid in extra.get("splice", []):
		var sc := _obj(int(sid))
		if sc == null or sc.zone != EngineEnums.ZoneId.HAND or _def(sc) == null or not _def(sc).kw().has("splice"):
			continue
		if not def.type_line.to_lower().contains(str(_def(sc).kw().splice.onto)):
			continue
		base.absorb(_cost(str(_def(sc).kw().splice.cost)))
		out["splice"] = (out.get("splice", []) as Array) + [int(sid)]
	## Waterbend (CR 701.67): "as an additional cost, [you may] waterbend {N}" adds N generic; artifacts and
	## creatures can be tapped for up to N of it (see cover()).
	if kw.has("waterbend_cost"):
		var wbc: Dictionary = kw.waterbend_cost
		if not bool(wbc.optional) or bool(extra.get("waterbend", false)):
			base.generic += int(wbc.n)
			out["waterbend"] = int(wbc.n)
	## Printed additional costs.
	if kw.has("additional_sacrifice"):
		var what := str(kw.additional_sacrifice.what)
		var need := int(kw.additional_sacrifice.n)
		var pool: Array = []
		for oid3 in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
			var o3 := _obj(int(oid3))
			if o3 != null and o3.controller_id == pid and _def(o3) != null and _matches_word(o3, what):
				pool.append(int(oid3))
		pool.sort_custom(func(a, b) -> bool: return _value_of(int(a)) < _value_of(int(b)))
		if pool.size() < need:
			_fail(out, "needs %s %s to sacrifice" % [str(need), what])
			return
		out["sac_ids"] = (out.get("sac_ids", []) as Array) + pool.slice(0, need)
	if kw.has("additional_discard"):
		var ds: Array = []
		for _j in int(kw.additional_discard.n):
			var dd := _worst_in_hand(pid, obj.object_id, ds)
			if dd == 0:
				_fail(out, "needs a card to discard")
				return
			ds.append(dd)
		out["discard_ids"] = ds
	if kw.has("additional_life"):
		if engine.state.players[pid].life < int(kw.additional_life):
			_fail(out, "not enough life")
			return
		out.life = int(out.life) + int(kw.additional_life)


func _matches_word(o: GameObject, what: String) -> bool:
	var d := _def(o)
	var w := what.to_lower().strip_edges()
	if w == "creature":
		return _is_creature(o)
	if w == "permanent":
		return true
	if w in ["artifact", "enchantment", "land", "planeswalker"]:
		return d.type_line.to_lower().contains(w)
	return Query._subtype_words(d.type_line).has(w.capitalize().trim_suffix("s"))


## The cheapest card in hand to throw away (lands beyond what's needed first), or 0.
func _worst_in_hand(pid: int, not_id: int, also_not: Array = []) -> int:
	var best := 0
	var best_v := 100000
	for hid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
		if int(hid) == not_id or also_not.has(int(hid)):
			continue
		var v := _value_of(int(hid))
		if v < best_v:
			best_v = v
			best = int(hid)
	return best


## Two untapped creatures you control that share a color with the spell (conspire, CR 702.78a).
func _conspirators(pid: int, def: CardDefinition) -> Array:
	var out: Array = []
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o == null or o.controller_id != pid or o.tapped or not _is_creature(o) or _def(o) == null:
			continue
		for c in _def(o).colors:
			if def.colors.has(c):
				out.append(int(oid))
				break
		if out.size() >= 2:
			break
	return out


## Graveyard cards (not `not_id`) with total mana value `n` or more, wasting as little as possible (CR 701.59a).
func _evidence(pid: int, not_id: int, n: int) -> Array:
	var gy: Array = []
	for gid in _zone_ids(EngineEnums.ZoneId.GRAVEYARD, pid):
		if int(gid) != not_id and _def(_obj(int(gid))) != null:
			gy.append(int(gid))
	gy.sort_custom(func(a, b) -> bool: return _def(_obj(int(a))).cmc > _def(_obj(int(b))).cmc)
	var picked: Array = []
	var total := 0
	for g in gy:
		if total >= n:
			break
		picked.append(g)
		total += _def(_obj(int(g))).cmc
	return picked if total >= n else []


## The extra costs of a spree / tiered spell's modes, in printed order ("+ {1} — ..." / "• {2} — ...").
func _mode_costs(def: CardDefinition) -> Array:
	var out: Array = []
	for line in def.oracle_text.split("\n"):
		var m := RegEx.create_from_string("^[+•]\\s*((?:\\{[^}]+\\})+)\\s*[—-]").search(str(line).strip_edges())
		if m != null:
			out.append(m.get_string(1))
	return out


func _value_of(oid: int) -> int:
	var o := _obj(oid)
	var d := _def(o)
	if d == null:
		return 0
	return d.cmc * 2 + (0 if d.is_land() else 3)


func _best_emerge_sac(pid: int) -> int:
	var best := 0
	var best_cmc := -1
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o == null or o.controller_id != pid or not _is_creature(o) or _def(o) == null:
			continue
		if _def(o).cmc > best_cmc:
			best_cmc = _def(o).cmc
			best = int(oid)
	return best


## Prowl (CR 702.76): a creature that shares a type with the card dealt combat damage to a player this turn.
func prowl_ready(pid: int, def: CardDefinition) -> bool:
	var have: Array = engine.state.players[pid].combat_damagers_types
	var parts := def.type_line.split("—")
	var words: Array = Array(parts[0].strip_edges().split(" ", false))
	if parts.size() > 1:
		words.append_array(Array(parts[1].strip_edges().split(" ", false)))
	for t in words:
		if have.has(str(t)):
			return true
	return false


# --- Paying with creatures and cards (convoke, delve) -----------------------------------------------

## Fills a shortfall in `cost` (hybrid already resolved) with tapped creatures (convoke) and exiled graveyard cards
## (delve). Returns {ok, tap_ids, exile_ids, cost (what is left to pay with mana)}.
func cover(pid: int, obj: GameObject, cost: ManaCost) -> Dictionary:
	var out := {"ok": false, "tap_ids": [], "exile_ids": [], "cost": cost}
	var kw := kw_of(obj)
	var c := cost.duplicate_cost()
	var creatures: Array = []
	var gy: Array = []
	if kw.has("convoke"):
		for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
			var o := _obj(int(oid))
			if o != null and o.controller_id == pid and not o.tapped and _is_creature(o):
				creatures.append(int(oid))
	if kw.has("delve"):
		gy = _zone_ids(EngineEnums.ZoneId.GRAVEYARD, pid)
		gy.sort_custom(func(a, b) -> bool: return _value_of(int(a)) < _value_of(int(b)))
	## Improvise (CR 702.126): each untapped artifact you tap pays for {1}. Mana rocks are kept for mana.
	var artifacts: Array = []
	if kw.has("improvise"):
		for aid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
			var ao := _obj(int(aid))
			if ao != null and ao.controller_id == pid and not ao.tapped and _def(ao) != null and _def(ao).type_line.contains("Artifact"):
				artifacts.append(int(aid))
		artifacts.sort_custom(func(a, b) -> bool: return _improvise_rank(int(a)) < _improvise_rank(int(b)))
	## Waterbend (CR 701.67b): artifacts and creatures tapped for up to N generic of the waterbend cost only.
	var wb_left := _waterbend_allowance(obj, kw)
	var wb_helpers: Array = _waterbend_helpers(pid, obj.object_id) if wb_left > 0 else []
	var guard := 0
	while not engine._can_afford_plain(pid, c) and guard < 40:
		guard += 1
		if not gy.is_empty() and c.generic > 0:
			out.exile_ids.append(int(gy.pop_front()))
			c.generic -= 1
			continue
		if not artifacts.is_empty() and c.generic > 0:
			out.tap_ids.append(int(artifacts.pop_front()))
			c.generic -= 1
			continue
		if wb_left > 0 and c.generic > 0:
			var wid := 0
			while not wb_helpers.is_empty() and wid == 0:
				var cand := int(wb_helpers.pop_front())
				if not out.tap_ids.has(cand):
					wid = cand
			if wid != 0:
				out.tap_ids.append(wid)
				c.generic -= 1
				wb_left -= 1
				continue
		if not creatures.is_empty():
			var cid := int(creatures.pop_front())
			out.tap_ids.append(cid)
			var cd := _def(_obj(cid))
			var hit := false
			if cd != null:
				for col in cd.colors:
					var key := str(col).to_lower()
					if int(c.get(key)) > 0:
						c.set(key, int(c.get(key)) - 1)
						hit = true
						break
			if not hit and c.generic > 0:
				c.generic -= 1
			elif not hit:
				out.tap_ids.pop_back()
			continue
		break
	out.ok = engine._can_afford_plain(pid, c)
	out.cost = c
	return out


# --- Dredge (CR 702.52) -------------------------------------------------------------------------------

## Cards in `pid`'s graveyard with dredge N that could replace a draw now (the library needs N cards): [{id, n}].
func dredge_cards(pid: int) -> Array:
	var out: Array = []
	var lib := engine.library_size(pid)
	for gid in _zone_ids(EngineEnums.ZoneId.GRAVEYARD, pid):
		var d := _def(_obj(int(gid)))
		if d == null:
			continue
		var n := int(d.kw().get("dredge", 0))
		if n > 0 and lib >= n:
			out.append({"id": int(gid), "n": n})
	return out


## Mills N cards and returns the dredge card to its owner's hand instead of drawing. False if it can't be dredged.
func do_dredge(pid: int, card_id: int) -> bool:
	for opt in dredge_cards(pid):
		if int(opt.id) != card_id:
			continue
		var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
		for _i in int(opt.n):
			if lib == null or lib.is_empty():
				break
			engine.state.zones.move(int(lib.object_ids[0]), EngineEnums.ZoneId.GRAVEYARD, pid)
		engine.state.zones.move(card_id, EngineEnums.ZoneId.HAND, pid)
		return true
	return false


## How much generic mana of `obj`'s cast may be paid by tapping (printed waterbend additional cost; an optional one
## only once the player chose to pay it).
func _waterbend_allowance(obj: GameObject, kw: Dictionary) -> int:
	if not kw.has("waterbend_cost"):
		return 0
	var wbc: Dictionary = kw.waterbend_cost
	if not bool(wbc.optional):
		return int(wbc.n)
	return int(wbc.n) if int(engine._cast_plan.get("waterbend", 0)) > 0 else 0


## Untapped artifacts and creatures `pid` controls that could be tapped for waterbend, best to tap first.
func _waterbend_helpers(pid: int, except_id: int) -> Array:
	var out: Array = []
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o == null or o.controller_id != pid or o.tapped or int(oid) == except_id or _def(o) == null:
			continue
		if _is_creature(o) or _def(o).type_line.contains("Artifact"):
			out.append(int(oid))
	out.sort_custom(func(a, b) -> bool: return _improvise_rank(int(a)) < _improvise_rank(int(b)))
	return out


## Waterbend {N} in an activated ability's cost: taps artifacts and creatures (other than the source) to pay up to
## N of the generic mana the player's mana sources can't. Returns the cost still to pay with mana; nothing is tapped
## unless the whole cost can then be paid.
func cover_waterbend(pid: int, src: GameObject, cost: ManaCost, n: int) -> ManaCost:
	var c := cost.duplicate_cost()
	var helpers := _waterbend_helpers(pid, src.object_id if src != null else 0)
	var taps: Array = []
	while not engine._can_afford_plain(pid, c) and c.generic > 0 and taps.size() < n and not helpers.is_empty():
		taps.append(int(helpers.pop_front()))
		c.generic -= 1
	if not engine._can_afford_plain(pid, c):
		return cost
	for tid in taps:
		_obj(int(tid)).tapped = true
	return c


## Artifacts that make mana are tapped for improvise last (CR 702.126: they could pay with mana instead).
func _improvise_rank(oid: int) -> int:
	var o := _obj(oid)
	var d := _def(o)
	if d == null:
		return 0
	var r := 0
	for a in d.abilities:
		if a is Ability and (a as Ability).kind == &"MANA":
			r += 10
	if engine.is_creature_now(o):
		r += 5
	return r


## True if `cost` can be paid for `obj` with mana, convoke and delve (what the gold border asks).
func afford(pid: int, obj: GameObject, cost: ManaCost) -> bool:
	var saved := engine._afford_ctx
	var saved_ab := engine._afford_is_ability
	engine._afford_ctx = obj
	engine._afford_is_ability = false
	var ok := _afford_inner(pid, obj, cost)
	engine._afford_ctx = saved
	engine._afford_is_ability = saved_ab
	return ok


func _afford_inner(pid: int, obj: GameObject, cost: ManaCost) -> bool:
	if engine.can_afford(pid, cost):
		return true
	var kw := kw_of(obj)
	if not (kw.has("convoke") or kw.has("delve") or kw.has("improvise") or kw.has("waterbend_cost")):
		return false
	for v in engine.hybrid_variants(cost):
		if int(v.life) > 0 and engine.state.players[pid].life < int(v.life):
			continue
		if bool(cover(pid, obj, v.cost).ok):
			return true
	return false


# --- Special cast options for the table -----------------------------------------------------------

## Every way the player could cast `obj` from where it is now: [{label, detail, extra}]. The first is the plain cast.
func cast_options(pid: int, obj: GameObject) -> Array:
	var out: Array = []
	var def := _def(obj)
	if def == null:
		return out
	var kw := def.kw()
	var zone := obj.zone
	if zone == EngineEnums.ZoneId.HAND or zone == EngineEnums.ZoneId.COMMAND:
		out.append(_opt("Cast", def.mana_cost, {}))
		if kw.has("kicker"):
			var kl: Array = kw.kicker
			for i in kl.size():
				out.append(_opt("Cast with kicker %s" % str(kl[i]), "Pay the extra cost", {"kicks": 1, "kick_idx": i}))
		if kw.has("multikicker"):
			for n in [1, 2, 3]:
				out.append(_opt("Cast kicked %d time%s" % [n, "" if n == 1 else "s"], "Multikicker %s each" % str(kw.multikicker), {"kicks": n}))
		if kw.has("waterbend_cost") and bool(kw.waterbend_cost.optional):
			out.append(_opt("Cast, waterbending {%d}" % int(kw.waterbend_cost.n), "Pay the extra cost; tap artifacts and creatures for up to %d of it" % int(kw.waterbend_cost.n), {"waterbend": true}))
		if kw.has("dash"):
			out.append(_opt("Dash %s" % str(kw.dash), "Haste; returns to hand at end of turn", {"mode": "dash"}))
		if kw.has("prowl") and prowl_ready(pid, def):
			out.append(_opt("Prowl %s" % str(kw.prowl), "A matching creature dealt combat damage this turn", {"mode": "prowl"}))
		if kw.has("emerge"):
			for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
				var o := _obj(int(oid))
				if o != null and o.controller_id == pid and _is_creature(o) and out.size() < 12:
					out.append(_opt("Emerge %s, sacrifice %s" % [str(kw.emerge), _label(o)], "Cost is reduced by its mana value", {"mode": "emerge", "sac_id": int(oid)}))
		for key in ["morph", "megamorph", "disguise"]:
			if kw.has(key):
				out.append(_opt("Cast face down {3}", "A 2/2 creature; turn up for %s" % str(kw[key]), {"mode": "morph"}))
				break
		if kw.has("impending"):
			out.append(_opt("Impending %d — %s" % [int(kw.impending.n), str(kw.impending.cost)],
				"Enters with %d time counters; not a creature until the last is removed (one each end step)" % int(kw.impending.n), {"mode": "impending"}))
		## Escalate: choose how many modes now (each one past the first costs the escalate cost).
		if kw.has("escalate"):
			var n_modes := _mode_count(def)
			for k in range(1, n_modes):
				out.append(_opt("Cast with %d modes" % (k + 1), "Escalate %s × %d" % [str(kw.escalate), k], {"escalate": k}))
		## Gift: promise the gift (the opponent gets it) for the "if the gift was promised" bonus.
		if kw.has("gift"):
			var plain := out.duplicate()
			for o in plain:
				var od: Dictionary = o
				var ex2: Dictionary = (od.extra as Dictionary).duplicate()
				ex2["gift"] = true
				out.append(_opt("%s — promise the gift" % str(od.label), "Your opponent gets the gift (%s); the gift bonus happens" % _gift_text(str(kw.gift)), ex2))
		_more_hand_options(pid, obj, def, kw, out)
	elif zone == EngineEnums.ZoneId.EXILE:
		## "You may play it this turn" (impulse draw and similar): a plain cast from exile for its controller.
		if engine.can_play_from_exile(pid, obj) and obj.exile_cast == "":
			out.append(_opt("Cast %s" % def.mana_cost, "You may play it from exile until the end of the turn", {}))
		match obj.exile_cast:
			"foretell":
				if obj.foretold_turn < engine.state.turn_number:
					out.append(_opt("Cast foretold %s" % str(kw.get("foretell", def.mana_cost)), "Foretold on an earlier turn", {"mode": "foretold"}))
			"plot":
				if obj.plotted_turn < engine.state.turn_number:
					out.append(_opt("Cast plotted (free)", "Without paying its mana cost, as a sorcery", {"mode": "plotted"}))
			"warp":
				if obj.plotted_turn < engine.state.turn_number:
					out.append(_opt("Cast %s" % def.mana_cost, "Warped earlier; cast it from exile", {"mode": "warped"}))
			"airbend":
				out.append(_opt("Cast for {2}", "Airbent: {2} instead of its mana cost", {"mode": "airbent"}))
	elif zone == EngineEnums.ZoneId.GRAVEYARD:
		if kw.has("jump_start"):
			out.append(_opt("Jump-start %s" % def.mana_cost, "Discard a card as well; exiled afterwards", {"mode": "jump_start"}))
		if kw.has("disturb") and def.back_face != null:
			out.append(_opt("Disturb %s" % str(kw.disturb), "Cast %s (its back face); exiled if it would die" % def.back_face.name, {"mode": "disturb"}))
		if kw.has("harmonize"):
			out.append(_opt("Harmonize %s" % str(kw.harmonize), "Tap a creature to reduce it by that creature's power; exiled afterwards", {"mode": "harmonize"}))
		if kw.has("mayhem") and obj.discarded_turn == engine.state.turn_number:
			out.append(_opt("Mayhem %s" % (str(kw.mayhem) if not (kw.mayhem is bool) else def.mana_cost), "You discarded it this turn", {"mode": "mayhem"}))
		if def.other_half != null and def.other_half.oracle_text.to_lower().contains("aftermath"):
			out.append(_opt("Cast %s (aftermath) %s" % [def.other_half.name, def.other_half.mana_cost], "Exiled afterwards", {"mode": "aftermath"}))
		if kw.has("flashback"):
			out.append(_opt("Flashback %s" % str(kw.flashback), "Exiled afterwards", {"mode": "flashback"}))
		if kw.has("escape"):
			out.append(_opt("Escape %s" % str(kw.escape.cost), "Exile %d other cards from your graveyard" % int(kw.escape.n), {"mode": "escape"}))
		if kw.has("retrace"):
			out.append(_opt("Retrace", "Discard a land card in addition to the mana cost", {"mode": "retrace"}))
	return out


## Cast options from hand for the keyword abilities with alternative or additional costs.
func _more_hand_options(pid: int, obj: GameObject, def: CardDefinition, kw: Dictionary, out: Array) -> void:
	var plain: Dictionary = out[0] if not out.is_empty() else _opt("Cast", def.mana_cost, {})
	var simple := {
		"evoke": ["Evoke %s", "It's sacrificed as it enters (its enters abilities still happen)"],
		"blitz": ["Blitz %s", "Haste and \"when it dies, draw a card\"; sacrificed at the end step"],
		"overload": ["Overload %s", "Every \"target\" becomes \"each\""],
		"surge": ["Surge %s", "You cast another spell this turn"],
		"spectacle": ["Spectacle %s", "An opponent lost life this turn"],
		"freerunning": ["Freerunning %s", "An Assassin or your commander dealt combat damage this turn"],
		"warp": ["Warp %s", "Exiled at the end step; you can cast it again from exile later"],
		"cleave": ["Cleave %s", "Without the words in square brackets"],
		"mutate": ["Mutate %s", "Merge it with a non-Human creature you own"],
		"bestow": ["Bestow %s", "An Aura giving its bonus; a creature again if that creature leaves"],
		"web_slinging": ["Web-slinging %s", "Also return a tapped creature you control to your hand"],
		"more_than_meets_the_eye": ["More Than Meets the Eye %s", "Cast it converted (its back face)"],
		"sneak": ["Sneak %s", "Return an unblocked attacker; it enters tapped and attacking"],
	}
	for key in simple.keys():
		if kw.has(key):
			var cost_text := str((kw[key] as Dictionary).cost if kw[key] is Dictionary else kw[key])
			out.append(_opt(str(simple[key][0]) % cost_text, str(simple[key][1]), {"mode": key}))
	if kw.has("prototype"):
		out.append(_opt("Prototype %s (%s/%s)" % [str(kw.prototype.cost), str(kw.prototype.p), str(kw.prototype.t)], "The smaller version", {"mode": "prototype"}))
	if kw.has("awaken"):
		out.append(_opt("Awaken %d — %s" % [int(kw.awaken.n), str(kw.awaken.cost)], "Also a land you control becomes a 0/0 haste Elemental with %d +1/+1 counters" % int(kw.awaken.n), {"mode": "awaken"}))
	if kw.has("offering"):
		out.append(_opt("%s offering" % str(kw.offering).capitalize(), "Sacrifice a %s: costs that much less; any time you could cast an instant" % str(kw.offering).capitalize(), {"mode": "offering"}))
	if kw.has("alt_tap"):
		out.append(_opt("Pay %s and tap %d creatures with %s" % [str(kw.alt_tap.cost), int(kw.alt_tap.n), str(kw.alt_tap.keyword)], "Instead of its mana cost", {"mode": "alt_tap"}))
	if def.other_half != null and not def.other_half.oracle_text.to_lower().contains("aftermath"):
		var lbl := "Adventure" if def.other_half.type_line.contains("Adventure") else "Cast"
		out.append(_opt("%s: %s %s" % [lbl, def.other_half.name, def.other_half.mana_cost], "The other half of the card", {"mode": "adventure" if lbl == "Adventure" else "half"}))
	if kw.has("fuse") and def.other_half != null:
		out.append(_opt("Fuse (cast both halves)", "%s + %s" % [def.mana_cost, def.other_half.mana_cost], {"mode": "fuse"}))
	## Additional costs: each adds an option on top of the plain cast.
	var adds := {
		"buyback": ["with buyback %s", "Returns to your hand as it resolves"],
		"entwine": ["entwined %s", "Choose all modes"],
		"offspring": ["with offspring %s", "A 1/1 token copy as it enters"],
		"conspire": ["and conspire", "Tap two untapped creatures sharing a color with it: copy it"],
		"bargain": ["bargained", "Sacrifice an artifact, enchantment or token"],
		"casualty": ["with casualty %s", "Sacrifice a creature with power %s or more: copy it"],
		"teamwork": ["with teamwork %s", "Tap creatures with total power %s or more"],
		"collect_evidence": ["collecting evidence %s", "Exile cards with total mana value %s or more from your graveyard"],
	}
	for key2 in adds.keys():
		if kw.has(key2):
			var v := str(kw[key2])
			var ex := (plain.extra as Dictionary).duplicate()
			ex["evidence" if key2 == "collect_evidence" else key2] = true
			out.append(_opt("Cast %s" % (str(adds[key2][0]).replace("%s", v)), str(adds[key2][1]).replace("%s", v), ex))
	for key3 in ["replicate", "squad"]:
		if kw.has(key3):
			for n in [1, 2, 3]:
				out.append(_opt("Cast with %s ×%d" % [key3, n], "%s each" % str(kw[key3]), {key3: n}))
	## Spree / tiered: the modes chosen now, each paying its extra cost.
	if kw.has("spree") or kw.has("tiered"):
		var costs := _mode_costs(def)
		var texts := _mode_texts(def)
		out.clear()
		if kw.has("tiered"):
			for i in costs.size():
				out.append(_opt("Cast: %s" % _short(str(texts[i])), "+%s" % str(costs[i]), {"modes": [i]}))
		else:
			var n_modes := costs.size()
			for mask in range(1, 1 << n_modes):
				var picks: Array = []
				var parts: PackedStringArray = []
				for j in n_modes:
					if mask & (1 << j):
						picks.append(j)
						parts.append(str(costs[j]))
				out.append(_opt("Spree: modes %s" % ", ".join(PackedStringArray(picks.map(func(x): return str(int(x) + 1)))), "+" + " +".join(parts), {"modes": picks}))
	## Splice onto Arcane: each splice card in hand that fits adds an option.
	if def.type_line.to_lower().contains("arcane"):
		for hid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
			var h := _obj(int(hid))
			if h == null or h.object_id == obj.object_id or _def(h) == null or not _def(h).kw().has("splice"):
				continue
			out.append(_opt("Cast and splice %s %s" % [_def(h).name, str(_def(h).kw().splice.cost)], "Adds its effects", {"splice": [int(hid)]}))


func _mode_texts(def: CardDefinition) -> Array:
	var out: Array = []
	for line in def.oracle_text.split("\n"):
		var l := str(line).strip_edges()
		var m := RegEx.create_from_string("^[+•]\\s*(?:\\{[^}]+\\})+\\s*[—-]\\s*(.+)$").search(l)
		if m != null:
			out.append(m.get_string(1))
	return out


func _short(t: String) -> String:
	return t if t.length() <= 60 else t.substr(0, 57) + "..."


## Timing for a cast in a given mode (CR 601.3): offering and sneak let a card be cast when it otherwise couldn't;
## plotted cards are cast as a sorcery.
func timing_ok(pid: int, obj: GameObject, mode: String) -> bool:
	match mode:
		"offering":
			return true
		"sneak":
			return pid == engine.state.active_player_id and engine.state.step == EngineEnums.Step.DECLARE_BLOCKERS
		"plotted":
			return pid == engine.state.active_player_id and engine._is_main_phase() and engine._stack_empty()
	if engine.state.players[pid].epic_locked:
		return false
	if split_second_active():
		return false
	return engine._timing_ok_to_cast(pid, obj)


## Split second (CR 702.61a): while a spell with it is on the stack, no spells or non-mana abilities.
func split_second_active() -> bool:
	for e in (engine.state.stack as MagicStack).entries:
		var se := e as StackEntry
		if se.kind != StackEntry.Kind.SPELL or se.object_id == 0:
			continue
		var o := _obj(se.object_id)
		if o != null and kw_of(o).has("split_second"):
			return true
	return false


## Modes that cast a card from the graveyard, and from exile.
const GRAVEYARD_MODES := ["flashback", "escape", "retrace", "jump_start", "disturb", "harmonize", "mayhem", "aftermath"]
const EXILE_MODES := ["foretold", "plotted", "warped", "airbent"]


## The cast options of `obj` that the player can actually pay for right now (mana colors, convoke, delve,
## Phyrexian life included). Empty means the table shows the card as not playable.
func affordable_options(pid: int, obj: GameObject) -> Array:
	var out: Array = []
	for o in cast_options(pid, obj):
		var od: Dictionary = o
		var pl := plan(pid, obj, od.extra)
		if not bool(pl.ok):
			continue
		if afford(pid, obj, pl.cost):
			out.append(od)
	return out


func _opt(label: String, detail: String, extra: Dictionary) -> Dictionary:
	return {"label": label, "detail": detail, "extra": extra}


## How many modes a modal spell has (its "•" lines).
func _mode_count(def: CardDefinition) -> int:
	var n := 0
	for line in def.oracle_text.split("\n"):
		if str(line).strip_edges().begins_with("•"):
			n += 1
	return n


func _gift_text(kind: String) -> String:
	match kind:
		"card":
			return "they draw a card"
		"extra card":
			return "they draw a card"
		_:
			return "they create a %s token" % kind.capitalize()


func _label(o: GameObject) -> String:
	var d := _def(o)
	return "face-down creature" if o.face_down else (d.name if d != null else "creature")


## Actions the player can take on `obj` besides a plain cast or its activated abilities.
func card_actions(pid: int, obj: GameObject) -> Array:
	var out: Array = []
	for a in special_actions(pid):
		var ga := a as GameAction
		if ga.object_id == obj.object_id:
			out.append({"label": str(ga.extra.get("label", "")), "detail": str(ga.extra.get("detail", "")), "special": ga})
	return out


# --- Paying the extra parts of a cast, and what a cast leaves on the spell -------------------------------

## Pays the non-mana parts of a plan (tapped convoke creatures, exiled delve/escape cards, the emerge victim,
## the retrace discard). Called as the spell goes on the stack.
func pay_extras(pid: int, plan_dict: Dictionary, covered: Dictionary) -> void:
	for cid in covered.get("tap_ids", []):
		var c := _obj(int(cid))
		if c != null:
			c.tapped = true
	for eid in covered.get("exile_ids", []):
		if _obj(int(eid)) != null:
			engine.state.zones.move(int(eid), EngineEnums.ZoneId.EXILE, pid)
	for xid in plan_dict.get("exile_ids", []):
		if _obj(int(xid)) != null:
			engine.state.zones.move(int(xid), EngineEnums.ZoneId.EXILE, pid)
	var sac := int(plan_dict.get("sac_id", 0))
	if sac != 0 and _obj(sac) != null:
		var v := _obj(sac)
		engine.state.zones.move(sac, EngineEnums.ZoneId.GRAVEYARD, v.owner_id)
	var disc := int(plan_dict.get("discard_id", 0))
	if disc != 0 and _obj(disc) != null:
		_note_paid(plan_dict, disc)
		engine.discard_card(pid, disc)
	for d2 in plan_dict.get("discard_ids", []):
		if _obj(int(d2)) != null:
			_note_paid(plan_dict, int(d2))
			engine.discard_card(pid, int(d2))
	for t in plan_dict.get("tap_ids", []):
		if _obj(int(t)) != null:
			_obj(int(t)).tapped = true
	for sv in plan_dict.get("sac_ids", []):
		var so := _obj(int(sv))
		if so != null:
			_note_paid(plan_dict, so.object_id)
			engine.state.zones.move(so.object_id, EngineEnums.ZoneId.GRAVEYARD, so.owner_id)
	for rid in plan_dict.get("return_ids", []):
		var ro := _obj(int(rid))
		if ro != null:
			if engine.state.combat is CombatState:
				(engine.state.combat as CombatState).attacker_ids.erase(ro.object_id)
			engine.state.zones.move(ro.object_id, EngineEnums.ZoneId.HAND, ro.owner_id)
	if int(plan_dict.get("life", 0)) > 0 and str(plan_dict.get("mode", "")) != "":
		pass


## What was discarded or sacrificed as an additional cost, by type line, so "if the discarded card wasn't a land" can be
## answered after the card is gone.
func _note_paid(plan_dict: Dictionary, object_id: int) -> void:
	var o := _obj(object_id)
	var d := _def(o) if o != null else null
	if d == null:
		return
	var paid: Array = plan_dict.get("paid_types", [])
	paid.append(d.type_line)
	plan_dict["paid_types"] = paid


## Marks the spell object with how it was cast (kicked, flashback, ...). The permanent keeps these.
func mark_cast(spell: GameObject, plan_dict: Dictionary) -> void:
	if spell == null:
		return
	spell.kicked = int(plan_dict.get("kicks", 0))
	spell.marks["paid_types"] = plan_dict.get("paid_types", [])
	spell.cast_from = int(plan_dict.get("from_zone", -1))
	spell.cast_mode = str(plan_dict.get("mode", ""))
	spell.face_down = bool(plan_dict.get("face_down", false))
	spell.gift_promised = bool(plan_dict.get("gift", false))
	spell.x_paid = int(plan_dict.get("x", 0))
	var m := spell.cast_mode
	for flag in ["evoke", "blitz", "warp", "prototype", "cleave", "disturb", "sneak", "mutate", "bestow", "awaken", "harmonize", "jump_start", "aftermath", "more_than_meets_the_eye"]:
		if m == flag:
			spell.marks[{"evoke": "evoked", "blitz": "blitzed", "warp": "warped", "prototype": "prototyped", "cleave": "cleaved",
				"disturb": "disturbed", "sneak": "sneaked", "mutate": "mutating", "bestow": "bestowing", "awaken": "awakening",
				"harmonize": "harmonized", "jump_start": "jump-started", "aftermath": "aftermath", "more_than_meets_the_eye": "converted"}[flag]] = true
	for k in ["buyback", "entwine", "offspring", "conspire", "casualty", "bargain", "teamwork", "evidence"]:
		if bool(plan_dict.get(k, false)):
			spell.marks[{"buyback": "buyback", "entwine": "entwined", "offspring": "offspring paid", "conspire": "conspired",
				"casualty": "casualty", "bargain": "bargained", "teamwork": "teamwork", "evidence": "evidence collected"}[k]] = true
	if int(plan_dict.get("squad", 0)) > 0:
		spell.marks["squad"] = int(plan_dict.squad)
	if int(plan_dict.get("replicate", 0)) > 0:
		spell.marks["replicate"] = int(plan_dict.replicate)
	if plan_dict.has("modes"):
		spell.marks["modes"] = plan_dict.modes
	if plan_dict.has("splice"):
		spell.marks["splice"] = plan_dict.splice
	if plan_dict.has("sneak_defender"):
		spell.marks["sneak_defender"] = int(plan_dict.sneak_defender)
	## Disturb and "converted" casts are the back face (CR 702.146a, 702.162a); halves cast their half (CR 709.3).
	var d := _def(spell)
	if d != null and (m == "disturb" or m == "more_than_meets_the_eye") and d.back_face != null:
		spell.front_def = d
		spell.definition = d.back_face
		if m == "disturb":
			spell.marks["exile instead of graveyard"] = true
	if d != null and (m == "aftermath" or m == "adventure" or m == "half") and d.other_half != null:
		spell.front_def = d
		spell.definition = d.other_half
	if m in ["flashback", "jump_start", "aftermath", "harmonize"]:
		spell.marks["exile instead of graveyard"] = true
	if plan_dict.get("variant_def") is CardDefinition and d != null:
		spell.front_def = d
		spell.definition = plan_dict["variant_def"]
		spell.marks["overloaded" if m == "overload" else "cleaved"] = true
	if spell.cast_mode == "dash":
		spell.dashed = true
	if spell.cast_mode == "suspend":
		spell.granted_haste = true


# --- Permanent spells cast with an alternative or additional cost ---------------------------------------

## What a permanent spell cast a special way does as it lands (CR 702.74 evoke, 702.152 blitz, 702.185 warp,
## 702.175 offspring, 702.157 squad, sneak, 702.103 bestow, 702.162 more than meets the eye).
func after_permanent_landed(o: GameObject) -> void:
	if o == null or o.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var pid := o.controller_id
	## Compleated (CR 702.150a): it enters with two fewer loyalty counters for each Phyrexian symbol paid with life.
	var paid_life := int(o.marks.get("phyrexian_life", 0))
	if paid_life > 0 and _def(o) != null and _def(o).kw().has("compleated") and o.counters.has("loyalty"):
		o.counters["loyalty"] = maxi(0, int(o.counters["loyalty"]) - paid_life)
	## Evoke: "When it enters, if its evoke cost was paid, its controller sacrifices it."
	if bool(o.marks.get("evoked", false)):
		var sfx := AbilityEffect.new()
		sfx.kind = &"SAC_SELF"
		engine.put_synthetic(o, pid, [sfx], {})
	if bool(o.marks.get("blitzed", false)):
		o.granted_haste = true
		o.sacrifice_at_end = true
	if bool(o.marks.get("offspring paid", false)):
		var ofx := AbilityEffect.new()
		ofx.kind = &"OFFSPRING_COPY"
		engine.put_synthetic(o, pid, [ofx], {})
	if int(o.marks.get("squad", 0)) > 0:
		var qfx := AbilityEffect.new()
		qfx.kind = &"SQUAD_COPIES"
		qfx.params = {"n": int(o.marks["squad"])}
		engine.put_synthetic(o, pid, [qfx], {"n": int(o.marks["squad"])})
	## Sneak: enters tapped and attacking the player the returned creature was attacking.
	if bool(o.marks.get("sneaked", false)) and engine.state.combat is CombatState and _is_creature(o):
		var cs := engine.state.combat as CombatState
		o.tapped = true
		cs.attacker_ids.append(o.object_id)
		cs.defenders[o.object_id] = int(o.marks.get("sneak_defender", cs.defending_player_id))
	## Bestow: it enters attached to a creature you control, as an Aura (no creature: it's a creature).
	if bool(o.marks.get("bestowing", false)):
		var best := -1
		var best_p := -1000
		for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
			var c := _obj(int(oid))
			if c == null or c.object_id == o.object_id or c.controller_id != pid or not _is_creature(c):
				continue
			if engine.power_of(c) > best_p:
				best_p = engine.power_of(c)
				best = c.object_id
		if best > 0:
			o.bestowed = true
			o.attached_to = best
	## Spells with copies to make once a permanent spell resolves (casualty on a creature spell copies it).
	var copies := int(o.marks.get("copies_on_resolve", 0))
	if copies > 0:
		var cfx := AbilityEffect.new()
		cfx.kind = &"SQUAD_COPIES"
		cfx.params = {"n": copies}
		engine.put_synthetic(o, pid, [cfx], {"n": copies})


## Mutate (CR 702.140): a mutating creature spell whose target is still a non-Human creature its owner owns merges
## with it (on top) instead of entering. Returns false when it enters on its own (CR 702.140b).
func mutate_onto(spell: GameObject) -> bool:
	if spell == null or not bool(spell.marks.get("mutating", false)):
		return false
	var host: GameObject = null
	var best_p := -1000
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var c := _obj(int(oid))
		if c == null or c.owner_id != spell.owner_id or not _is_creature(c) or c.face_down:
			continue
		if _def(c) == null or _def(c).type_line.contains("Human"):
			continue
		if engine.power_of(c) > best_p:
			best_p = engine.power_of(c)
			host = c
	if host == null:
		return false
	var top := _def(spell)
	var under := _def(host)
	var merged := top.copy_def()
	var have := {}
	for a in merged.abilities:
		have[(a as Ability).ability_id] = true
	for a in under.abilities:
		if not have.has((a as Ability).ability_id):
			merged.abilities.append(a)
	for k in under.keywords:
		if not merged.keywords.has(k):
			merged.keywords.append(k)
	host.merged.append(host.front_def if host.front_def != null else under)
	host.front_def = top
	host.definition = merged
	var st := engine.state
	var stack_zone: Zone = st.zones.get_zone(EngineEnums.ZoneId.STACK)
	if stack_zone != null:
		stack_zone.object_ids.erase(spell.object_id)
	st.objects.erase(spell.object_id)
	st.log.append(EngineEnums.EventType.ZONE_CHANGE, host.controller_id, {from_id = spell.object_id, to_id = host.object_id, from_zone = EngineEnums.ZoneId.STACK, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = spell.object_id})
	if engine.triggers != null:
		engine.triggers.fire_object_event(engine, "MUTATES", host, {player_id = host.controller_id})
	return true


## The text a spell has when cast with overload ("target" becomes "each", CR 702.96b) or cleave (the words in
## square brackets are removed, CR 702.148b), read into a definition of its own; null for other casts.
static func variant_def(def: CardDefinition, mode: String) -> CardDefinition:
	if def == null or mode != "cleave":
		return null
	var lines: Array = []
	for raw in def.oracle_text.split("\n"):
		var line := str(raw)
		var low := line.to_lower()
		if low.begins_with("overload ") or low.begins_with("cleave "):
			continue
		if mode == "overload":
			line = line.replace("any number of target ", "each ").replace("up to one target ", "each ").replace("target ", "each ").replace("Target ", "Each ")
		else:
			var re := RegEx.create_from_string("\\s*\\[[^\\]]*\\]")
			line = re.sub(line, "", true).replace("  ", " ")
		lines.append(line)
	var v := def.copy_def()
	v.oracle_text = "\n".join(PackedStringArray(lines))
	var abs := OracleIr.translate(v)
	if abs.is_empty():
		return null
	v.abilities = abs
	return v


## Where a resolved instant or sorcery goes: exile for flashback, rebound's exile, else the graveyard.
func resolved_destination(obj: GameObject) -> int:
	if obj.cast_mode == "flashback" or bool(obj.marks.get("exile instead of graveyard", false)):
		return EngineEnums.ZoneId.EXILE
	## Buyback (CR 702.27a): back to its owner's hand. An adventure goes on an adventure in exile (CR 715.4).
	if bool(obj.marks.get("buyback", false)):
		return EngineEnums.ZoneId.HAND
	if obj.cast_mode == "adventure":
		return EngineEnums.ZoneId.EXILE
	return EngineEnums.ZoneId.GRAVEYARD


## After a spell resolved into the graveyard/exile: queue its rebound.
func after_spell_resolved(obj_before: GameObject, moved: GameObject) -> void:
	if moved == null or obj_before == null:
		return
	var d := _def(obj_before)
	if d == null or not d.kw().has("rebound"):
		return
	if obj_before.cast_mode != "" and obj_before.cast_mode != "rebound_none":
		return
	if moved.zone == EngineEnums.ZoneId.GRAVEYARD:
		var ex: GameObject = engine.state.zones.move(moved.object_id, EngineEnums.ZoneId.EXILE, moved.owner_id)
		if ex != null:
			engine.state.rebound_queue.append({"owner": ex.owner_id, "object_id": ex.object_id, "turn": engine.state.turn_number})


# --- Casting right now, outside normal priority (madness, miracle, suspend, rebound) ------------------

## Casts `object_id` for `pid`, paying its plan cost with auto-tapped mana (or nothing when `free`).
## Targets are picked automatically. False when it can't be cast or paid; the card stays where it was.
func cast_now(pid: int, object_id: int, extra: Dictionary, free: bool = false) -> bool:
	var obj := _obj(object_id)
	var def := _def(obj)
	if def == null:
		return false
	var pl := plan(pid, obj, extra)
	if not bool(pl.ok):
		return false
	var variant := variant_def(def, str(pl.get("mode", "")))
	if variant != null:
		pl["variant_def"] = variant
		def = variant
	var chosen: Array = []
	var sp: Ability = def.spell_ability()
	if sp != null and not sp.targets.is_empty() and engine.targeting != null and str(pl.get("mode", "")) != "overload":
		var hostile := TargetingManager.effects_hostile(sp.effects)
		for slot in sp.targets:
			var tid := engine.targeting.auto_pick(engine, slot, object_id, pid, TargetingManager.slot_hostile(slot, hostile), chosen)
			if tid < 0:
				return false
			chosen.append(tid)
	var covered := {}
	if not free:
		var cost: ManaCost = pl.cost
		var life := 0
		if not cost.hybrid.is_empty():
			var pick := engine.resolve_hybrid(pid, cost)
			cost = pick.cost
			life = int(pick.life)
		if life > 0 and engine.state.players[pid].life < life:
			return false
		if not engine._can_afford_plain(pid, cost):
			covered = cover(pid, obj, cost)
			if not bool(covered.ok):
				return false
			cost = covered.cost
		if not engine.pay_now(pid, cost):
			return false
		if life > 0:
			engine.state.players[pid].life -= life
	pay_extras(pid, pl, covered)
	var moved: GameObject = engine.state.zones.move(object_id, EngineEnums.ZoneId.STACK)
	if moved == null:
		return false
	mark_cast(moved, pl)
	var entry: StackEntry = (engine.state.stack as MagicStack).push_spell(moved, pid, chosen, engine.state.next_stack_id, object_id)
	engine.state.next_stack_id += 1
	entry.ctx = {"kicked": moved.kicked, "mode": moved.cast_mode}
	engine._spell_extras(entry, moved, pl)
	engine.state.log.append(EngineEnums.EventType.SPELL_CAST, pid, {object_id = moved.object_id, stack_id = entry.stack_id})
	engine.state.passed_since_action.clear()
	if engine.triggers != null:
		engine.triggers.on_spell_cast(engine, moved, pid)
	return true


# --- Special actions: cycling, suspend, ninjutsu, turning face up, crew -----------------------------

func _special(pid: int, obj: GameObject, special: String, label: String, detail: String, more: Dictionary = {}) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.SPECIAL
	a.player_id = pid
	a.object_id = obj.object_id
	a.extra = {"special": special, "label": label, "detail": detail}
	for k in more.keys():
		a.extra[k] = more[k]
	return a


func special_actions(pid: int) -> Array:
	var out: Array = []
	if engine.state.mode != EngineEnums.EngineMode.GIVING_PRIORITY or int(engine.state.awaiting.get("player_id", -1)) != pid:
		return out
	for oid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
		var obj := _obj(int(oid))
		var def := _def(obj)
		if def == null:
			continue
		var kw := def.kw()
		if kw.has("cycling") and engine.can_afford(pid, _cost(str(kw.cycling.cost))):
			var ty := str(kw.cycling.type)
			var nm := "Cycling" if ty == "" else ("%scycling" % ty.capitalize())
			out.append(_special(pid, obj, "cycle", "%s %s" % [nm, str(kw.cycling.cost)], "Discard this card: " + ("draw a card" if ty == "" else "search for a %s card" % ty)))
		if kw.has("suspend") and engine._timing_ok_to_cast(pid, obj) and engine.can_afford(pid, _cost(str(kw.suspend.cost))):
			out.append(_special(pid, obj, "suspend", "Suspend %d — %s" % [int(kw.suspend.n), str(kw.suspend.cost)], "Exile with time counters; cast free when the last is removed"))
		if kw.has("ninjutsu") and engine.can_afford(pid, _cost(str(kw.ninjutsu))):
			for aid in _unblocked_attackers(pid):
				out.append(_special(pid, obj, "ninjutsu", "Ninjutsu %s (return %s)" % [str(kw.ninjutsu), _label(_obj(int(aid)))], "Put it onto the battlefield attacking", {"attacker_id": int(aid)}))
	var sorcery_ok: bool = pid == engine.state.active_player_id and engine._is_main_phase() and engine._stack_empty()
	out.append_array(_more_specials(pid, sorcery_ok))
	## From the graveyard, as a sorcery: encore (CR 702.141), eternalize (CR 702.129), embalm (CR 702.128).
	if sorcery_ok:
		for gid in _zone_ids(EngineEnums.ZoneId.GRAVEYARD, pid):
			var g := _obj(int(gid))
			var gd := _def(g)
			if gd == null:
				continue
			var gk := gd.kw()
			if gk.has("encore") and engine.can_afford(pid, _cost(str(gk.encore))):
				out.append(_special(pid, g, "encore", "Encore %s" % str(gk.encore), "Exile it: a token copy with haste attacks each opponent this turn, then is sacrificed"))
			if gk.has("eternalize") and engine.can_afford(pid, _cost(str(gk.eternalize))):
				out.append(_special(pid, g, "eternalize", "Eternalize %s" % str(gk.eternalize), "Exile it: a 4/4 black Zombie token copy with no mana cost"))
			if gk.has("embalm") and engine.can_afford(pid, _cost(str(gk.embalm))):
				out.append(_special(pid, g, "embalm", "Embalm %s" % str(gk.embalm), "Exile it: a white Zombie token copy with no mana cost"))
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o == null or o.controller_id != pid:
			continue
		var cost_text := turn_up_cost(o)
		if o.face_down and cost_text != "" and engine.can_afford(pid, _cost(cost_text)):
			out.append(_special(pid, o, "turn_up", "Turn face up %s" % cost_text, "Pay the morph or mana cost; a special action"))
		var k2 := kw_of(o)
		if k2.has("crew") and not o.face_down and crew_creatures(pid, o, int(k2.crew)).size() > 0:
			out.append(_special(pid, o, "crew", "Crew %d" % int(k2.crew), "Tap untapped creatures with total power %d or more" % int(k2.crew)))
	return out


func _unblocked_attackers(pid: int) -> Array:
	var out: Array = []
	if engine.state.step != EngineEnums.Step.DECLARE_BLOCKERS or pid != engine.state.active_player_id:
		return out
	if not (engine.state.combat is CombatState):
		return out
	var cs := engine.state.combat as CombatState
	if not cs.blocks_declared:
		return out
	for aid in cs.attacker_ids:
		var b: Variant = cs.blockers.get(aid, [])
		var a := _obj(int(aid))
		if a != null and a.controller_id == pid and (b is Array and (b as Array).is_empty()):
			out.append(int(aid))
	return out


## The cost to turn a face-down permanent up: its morph cost, or its mana cost if it was manifested/cloaked as a creature.
func turn_up_cost(o: GameObject) -> String:
	var d := _def(o)
	if d == null or not o.face_down:
		return ""
	var kw := d.kw()
	for key in ["morph", "megamorph", "disguise"]:
		if kw.has(key):
			return str(kw[key])
	if d.is_creature() and d.mana_cost != "" and (o.cast_mode == "manifest" or o.cast_mode == "cloak"):
		return d.mana_cost
	return ""


## Untapped creatures to tap for crewing, or [] if the power isn't there. Chosen to waste as little power as possible.
func crew_creatures(pid: int, vehicle: GameObject, n: int) -> Array:
	var cands: Array = []
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o != null and o.controller_id == pid and not o.tapped and o.object_id != vehicle.object_id and _is_creature(o):
			cands.append(int(oid))
	cands.sort_custom(func(a, b) -> bool: return engine.power_of(_obj(int(a))) > engine.power_of(_obj(int(b))))
	var picked: Array = []
	var total := 0
	for cid in cands:
		if total >= n:
			break
		picked.append(cid)
		total += engine.power_of(_obj(int(cid)))
	if total < n:
		return []
	var i := picked.size() - 1
	while i >= 0:
		var p := engine.power_of(_obj(int(picked[i])))
		if total - p >= n:
			total -= p
			picked.remove_at(i)
		i -= 1
	return picked


func submit_special(action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	var pid := action.player_id
	if engine.state.mode != EngineEnums.EngineMode.GIVING_PRIORITY or int(engine.state.awaiting.get("player_id", -1)) != pid:
		r.error = "not your priority"
		return r
	var obj := _obj(action.object_id)
	var def := _def(obj)
	if def == null or obj.controller_id != pid:
		r.error = "illegal source"
		return r
	var kw := def.kw()
	match str(action.extra.get("special", "")):
		"cycle":
			if obj.zone != EngineEnums.ZoneId.HAND or not kw.has("cycling"):
				r.error = "can't cycle that"
				return r
			if not engine.pay_now(pid, _cost(str(kw.cycling.cost))):
				r.error = "can't pay"
				return r
			var ty := str(kw.cycling.type)
			engine.discard_card(pid, obj.object_id)
			var fx: AbilityEffect = AbilityEffect.new()
			if ty == "":
				fx.kind = &"DRAW"
				fx.params = {"n": 1}
			else:
				fx.kind = &"SEARCH_LIBRARY"
				fx.params = {"filter": _cycling_filter(ty), "n": 1, "to": "HAND"}
			engine.put_synthetic(null, pid, [fx], {}, obj.object_id)
		"suspend":
			if obj.zone != EngineEnums.ZoneId.HAND or not kw.has("suspend") or not engine._timing_ok_to_cast(pid, obj):
				r.error = "can't suspend that"
				return r
			if not engine.pay_now(pid, _cost(str(kw.suspend.cost))):
				r.error = "can't pay"
				return r
			var ex: GameObject = engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, pid)
			if ex != null:
				ex.counters["time"] = int(kw.suspend.n)
				ex.cast_mode = "suspend"
		"ninjutsu":
			return _ninjutsu(action, obj, kw)
		"turn_up":
			var ct := turn_up_cost(obj)
			if not obj.face_down or ct == "":
				r.error = "not face down"
				return r
			if not engine.pay_now(pid, _cost(ct)):
				r.error = "can't pay"
				return r
			obj.face_down = false
			obj.ward_extra = ""
			if kw.has("megamorph"):
				obj.counters["+1/+1"] = int(obj.counters.get("+1/+1", 0)) + 1
		"encore", "eternalize", "embalm":
			var sp := str(action.extra.get("special", ""))
			var sorcery_now: bool = pid == engine.state.active_player_id and engine._is_main_phase() and engine._stack_empty()
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or not kw.has(sp) or not sorcery_now:
				r.error = "can't %s that" % sp
				return r
			if not engine.pay_now(pid, _cost(str(kw[sp]))):
				r.error = "can't pay"
				return r
			var card_def := def
			engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
			if sp == "encore":
				_encore_tokens(pid, card_def)
			else:
				_zombie_copy(pid, card_def, "B" if sp == "eternalize" else "W", sp == "eternalize")
		"crew":
			var need := int(kw.get("crew", 0))
			var pick := crew_creatures(pid, obj, need)
			if need <= 0 or pick.is_empty():
				r.error = "not enough power to crew"
				return r
			for cid in pick:
				_obj(int(cid)).tapped = true
			engine.animate_until_eot(obj, ["Artifact", "Creature"])
		_:
			var err := _submit_more(pid, obj, def, kw, action.extra)
			if err != "":
				r.error = err
				return r
	engine.state.passed_since_action.clear()
	r.ok = true
	return r


# --- More special actions and activated keyword abilities --------------------------------------------
# Plot (CR 702.170), foretell (CR 702.143), transmute (CR 702.53), channel / forecast (CR 702.57) from the hand;
# unearth (CR 702.84), scavenge (CR 702.97) from the graveyard; outlast (CR 702.107), level up (CR 702.87),
# station (CR 702.184), saddle (CR 702.171), fortify (CR 702.67), reconfigure (CR 702.151) on the battlefield.

func _more_specials(pid: int, sorcery_ok: bool) -> Array:
	var out: Array = []
	var st := engine.state
	var my_turn := pid == st.active_player_id
	for oid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
		var obj := _obj(int(oid))
		var def := _def(obj)
		if def == null:
			continue
		var kw := def.kw()
		if kw.has("plot") and sorcery_ok and engine.can_afford(pid, _cost(str(kw.plot))):
			out.append(_special(pid, obj, "plot", "Plot %s" % str(kw.plot), "Exile it; cast it free on a later turn as a sorcery"))
		if kw.has("foretell") and my_turn and engine.can_afford(pid, _cost("{2}")):
			out.append(_special(pid, obj, "foretell", "Foretell ({2})", "Exile it; cast it for %s on a later turn" % str(kw.foretell)))
		if kw.has("transmute") and sorcery_ok and engine.can_afford(pid, _cost(str(kw.transmute))):
			out.append(_special(pid, obj, "transmute", "Transmute %s" % str(kw.transmute), "Discard it: find a card with mana value %d" % def.cmc))
		for a in def.abilities:
			var ab := a as Ability
			if ab == null or not ab.is_activated():
				continue
			var hand_kind := ""
			if ab.restrictions.has("CHANNEL"):
				hand_kind = "Channel"
			elif ab.restrictions.has("FORECAST") and my_turn and st.step == EngineEnums.Step.UPKEEP and int(obj.marks.get("forecast_turn", -1)) != st.turn_number:
				hand_kind = "Forecast"
			if hand_kind == "" or not engine.can_afford(pid, _ability_mana(ab)):
				continue
			out.append(_special(pid, obj, "hand_ability", "%s %s" % [hand_kind, _ability_mana_text(ab)], _short(ab.text), {"ability_id": str(ab.ability_id)}))
	if sorcery_ok:
		for gid in _zone_ids(EngineEnums.ZoneId.GRAVEYARD, pid):
			var g := _obj(int(gid))
			var gd := _def(g)
			if gd == null:
				continue
			var gk := gd.kw()
			if gk.has("unearth") and engine.can_afford(pid, _cost(str(gk.unearth))):
				out.append(_special(pid, g, "unearth", "Unearth %s" % str(gk.unearth), "Return it with haste; exile it at end of turn or if it would leave"))
			if gk.has("scavenge") and engine.can_afford(pid, _cost(str(gk.scavenge))) and not _creatures_of(pid).is_empty():
				out.append(_special(pid, g, "scavenge", "Scavenge %s" % str(gk.scavenge), "Exile it: %s +1/+1 counters on a creature" % gd.power))
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o == null or o.controller_id != pid or o.face_down:
			continue
		var k := kw_of(o)
		## Aura swap (CR 702.65): any time you have priority; needs an Aura card in hand that fits what this one enchants.
		if k.has("aura_swap") and o.owner_id == pid and o.attached_to != 0 and engine.can_afford(pid, _cost(str(k.aura_swap))) and _aura_swap_targets(pid, o) > 0:
			out.append(_special(pid, o, "aura_swap", "Aura swap %s" % str(k.aura_swap), "Exchange it with an Aura card in your hand"))
		if not sorcery_ok:
			continue
		if k.has("transfigure") and _def(o) != null and engine.can_afford(pid, _cost(str(k.transfigure))):
			out.append(_special(pid, o, "transfigure", "Transfigure %s" % str(k.transfigure), "Sacrifice it: search for a creature with mana value %d" % _def(o).cmc))
		if k.has("outlast") and not o.tapped and not o.summoned_this_turn and engine.can_afford(pid, _cost(str(k.outlast))):
			out.append(_special(pid, o, "outlast", "Outlast %s" % str(k.outlast), "Tap: a +1/+1 counter"))
		if k.has("level_up") and engine.can_afford(pid, _cost(str(k.level_up))):
			out.append(_special(pid, o, "level_up", "Level up %s" % str(k.level_up), "A level counter (level %d now)" % int(o.counters.get("level", 0))))
		if k.has("station"):
			var helper := _station_helper(pid, o)
			if helper != null:
				out.append(_special(pid, o, "station", "Station (tap %s)" % _label(helper), "Charge counters equal to its power (%d now)" % int(o.counters.get("charge", 0))))
		if k.has("saddle") and int(o.marks.get("saddled_turn", -1)) != engine.state.turn_number and not crew_creatures(pid, o, int(k.saddle)).is_empty():
			out.append(_special(pid, o, "saddle", "Saddle %d" % int(k.saddle), "Tap creatures with total power %d: saddled this turn" % int(k.saddle)))
		if k.has("fortify") and engine.can_afford(pid, _cost(str(k.fortify))) and _best_land(pid) != null:
			out.append(_special(pid, o, "fortify", "Fortify %s" % str(k.fortify), "Attach to a land you control"))
		if k.has("reconfigure") and engine.can_afford(pid, _cost(str(k.reconfigure))):
			out.append(_special(pid, o, "reconfigure", "Reconfigure %s" % str(k.reconfigure), "Unattach" if o.attached_to != 0 else "Attach to a creature you control (it stops being a creature)"))
	return out


func _submit_more(pid: int, obj: GameObject, def: CardDefinition, kw: Dictionary, extra: Dictionary) -> String:
	var st := engine.state
	var sp := str(extra.get("special", ""))
	var sorcery_ok: bool = pid == st.active_player_id and engine._is_main_phase() and engine._stack_empty()
	var k := kw_of(obj) if obj.zone == EngineEnums.ZoneId.BATTLEFIELD else kw
	match sp:
		"plot":
			if obj.zone != EngineEnums.ZoneId.HAND or not kw.has("plot") or not sorcery_ok:
				return "can't plot that"
			if not engine.pay_now(pid, _cost(str(kw.plot))):
				return "can't pay"
			var ex: GameObject = st.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, pid)
			if ex != null:
				ex.exile_cast = "plot"
				ex.plotted_turn = st.turn_number
		"foretell":
			if obj.zone != EngineEnums.ZoneId.HAND or not kw.has("foretell") or pid != st.active_player_id:
				return "can't foretell that"
			if not engine.pay_now(pid, _cost("{2}")):
				return "can't pay"
			var fx: GameObject = st.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, pid)
			if fx != null:
				fx.exile_cast = "foretell"
				fx.foretold_turn = st.turn_number
		"transmute":
			if obj.zone != EngineEnums.ZoneId.HAND or not kw.has("transmute") or not sorcery_ok:
				return "can't transmute that"
			if not engine.pay_now(pid, _cost(str(kw.transmute))):
				return "can't pay"
			var mv := def.cmc
			engine.discard_card(pid, obj.object_id)
			for lid in _zone_ids(EngineEnums.ZoneId.LIBRARY, pid):
				var lc := _obj(int(lid))
				if _def(lc) != null and _def(lc).cmc == mv:
					st.zones.move(lc.object_id, EngineEnums.ZoneId.HAND, pid)
					break
			engine.shuffle_library(pid)
		"hand_ability":
			var ab: Ability = null
			for a in def.abilities:
				if str((a as Ability).ability_id) == str(extra.get("ability_id", "")):
					ab = a
			if ab == null or obj.zone != EngineEnums.ZoneId.HAND:
				return "no such ability"
			if not engine.pay_now(pid, _ability_mana(ab)):
				return "can't pay"
			if ab.restrictions.has("CHANNEL"):
				engine.discard_card(pid, obj.object_id)
			else:
				obj.marks["forecast_turn"] = st.turn_number
			var targets: Array = []
			var hostile := TargetingManager.effects_hostile(ab.effects)
			for slot in ab.targets:
				var tid := engine.targeting.auto_pick(engine, slot, obj.object_id, pid, TargetingManager.slot_hostile(slot, hostile), targets) if engine.targeting != null else -1
				targets.append(tid)
			var e := engine.put_synthetic(obj, pid, ab.effects.duplicate(), {}, obj.object_id)
			if e != null:
				e.targets = targets
		"unearth":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or not kw.has("unearth") or not sorcery_ok:
				return "can't unearth that"
			if not engine.pay_now(pid, _cost(str(kw.unearth))):
				return "can't pay"
			var back: GameObject = st.zones.move(obj.object_id, EngineEnums.ZoneId.BATTLEFIELD, pid)
			if back != null:
				back.unearthed = true
				back.granted_haste = true
		"scavenge":
			if obj.zone != EngineEnums.ZoneId.GRAVEYARD or not kw.has("scavenge") or not sorcery_ok:
				return "can't scavenge that"
			var who := _best_creature(pid)
			if who == null:
				return "no creature"
			if not engine.pay_now(pid, _cost(str(kw.scavenge))):
				return "can't pay"
			var n := int(def.power) if def.power.is_valid_int() else 0
			st.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, pid)
			who.counters["+1/+1"] = int(who.counters.get("+1/+1", 0)) + n
		"transfigure":
			if obj.zone != EngineEnums.ZoneId.BATTLEFIELD or not k.has("transfigure") or not sorcery_ok:
				return "can't transfigure that"
			if not engine.pay_now(pid, _cost(str(k.transfigure))):
				return "can't pay"
			## CR 702.71a: sacrifice it, then search for a creature card with the same mana value.
			var mv := def.cmc
			st.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
			var tfx := AbilityEffect.new()
			tfx.kind = &"SEARCH_LIBRARY"
			tfx.params = {"filter": {"type": "creature", "mv": mv}, "n": 1, "to": "BATTLEFIELD"}
			engine.put_synthetic(null, pid, [tfx], {}, obj.object_id)
		"aura_swap":
			if obj.zone != EngineEnums.ZoneId.BATTLEFIELD or not k.has("aura_swap") or obj.attached_to == 0:
				return "can't aura swap that"
			if _aura_swap_targets(pid, obj) <= 0:
				return "no Aura in your hand fits"
			if not engine.pay_now(pid, _cost(str(k.aura_swap))):
				return "can't pay"
			var sfx := AbilityEffect.new()
			sfx.kind = &"AURA_SWAP"
			engine.put_synthetic(obj, pid, [sfx], {})
		"outlast":
			if not k.has("outlast") or obj.tapped or not sorcery_ok:
				return "can't outlast"
			if not engine.pay_now(pid, _cost(str(k.outlast))):
				return "can't pay"
			obj.tapped = true
			obj.counters["+1/+1"] = int(obj.counters.get("+1/+1", 0)) + 1
		"level_up":
			if not k.has("level_up") or not sorcery_ok:
				return "can't level up"
			if not engine.pay_now(pid, _cost(str(k.level_up))):
				return "can't pay"
			obj.counters["level"] = int(obj.counters.get("level", 0)) + 1
		"station":
			var helper := _station_helper(pid, obj)
			if not k.has("station") or helper == null or not sorcery_ok:
				return "can't station"
			helper.tapped = true
			obj.counters["charge"] = int(obj.counters.get("charge", 0)) + maxi(0, engine.power_of(helper))
		"saddle":
			var pick := crew_creatures(pid, obj, int(k.get("saddle", 0)))
			if not k.has("saddle") or pick.is_empty() or not sorcery_ok:
				return "can't saddle"
			for cid in pick:
				_obj(int(cid)).tapped = true
			obj.marks["saddled_turn"] = st.turn_number
			if engine.triggers != null:
				engine.triggers.fire_object_event(engine, "SADDLED", obj, {player_id = pid})
		"fortify":
			var land := _best_land(pid)
			if not k.has("fortify") or land == null or not sorcery_ok:
				return "can't fortify"
			if not engine.pay_now(pid, _cost(str(k.fortify))):
				return "can't pay"
			obj.attached_to = land.object_id
		"reconfigure":
			if not k.has("reconfigure") or not sorcery_ok:
				return "can't reconfigure"
			var host: GameObject = null
			if obj.attached_to == 0:
				for c in _creatures_of(pid):
					if (c as GameObject).object_id != obj.object_id and (host == null or engine.power_of(c) > engine.power_of(host)):
						host = c
				if host == null:
					return "no creature to attach to"
			if not engine.pay_now(pid, _cost(str(k.reconfigure))):
				return "can't pay"
			obj.attached_to = host.object_id if host != null else 0
		_:
			return "unknown action"
	return ""


## How many Aura cards in `pid`'s hand could replace `aura` (aura swap, CR 702.65).
func _aura_swap_targets(pid: int, aura: GameObject) -> int:
	var host := _obj(aura.attached_to)
	if host == null or _def(host) == null:
		return 0
	var n := 0
	for hid in _zone_ids(EngineEnums.ZoneId.HAND, pid):
		var c := _def(_obj(int(hid)))
		if c != null and KeywordActions.aura_can_enchant(c, _def(host)):
			n += 1
	return n


func _ability_mana(ab: Ability) -> ManaCost:
	var c := ManaCost.new()
	for cc in ab.costs:
		if cc is AbilityCost and (cc as AbilityCost).kind == &"MANA":
			c.absorb(_cost((cc as AbilityCost).mana))
	return c


func _ability_mana_text(ab: Ability) -> String:
	for cc in ab.costs:
		if cc is AbilityCost and (cc as AbilityCost).kind == &"MANA":
			return (cc as AbilityCost).mana
	return ""


func _creatures_of(pid: int) -> Array:
	var out: Array = []
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o != null and o.controller_id == pid and _is_creature(o):
			out.append(o)
	return out


func _best_creature(pid: int) -> GameObject:
	var best: GameObject = null
	for c in _creatures_of(pid):
		if best == null or engine.power_of(c) > engine.power_of(best):
			best = c
	return best


func _best_land(pid: int) -> GameObject:
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o != null and o.controller_id == pid and _def(o) != null and _def(o).is_land():
			return o
	return null


## Station: the untapped other creature with the most power to tap.
func _station_helper(pid: int, ship: GameObject) -> GameObject:
	var best: GameObject = null
	for c in _creatures_of(pid):
		var co := c as GameObject
		if co.object_id == ship.object_id or co.tapped:
			continue
		if best == null or engine.power_of(co) > engine.power_of(best):
			best = co
	return best


## Encore (CR 702.141a): for each opponent, a token copy that attacks that opponent this turn if able, with haste,
## sacrificed at the beginning of the next end step.
func _encore_tokens(pid: int, card_def: CardDefinition) -> void:
	for p in engine.state.players:
		if p.player_id == pid or p.lost:
			continue
		var d := card_def.copy_def()
		d.type_line = "Token " + d.type_line if not d.type_line.begins_with("Token") else d.type_line
		var t: GameObject = engine.state.zones.create(pid, EngineEnums.ZoneId.BATTLEFIELD, {definition = d, is_token = true, controller_id = pid})
		if t == null:
			continue
		t.granted_haste = true
		t.sacrifice_at_end = true
		t.goaded_by = [p.player_id]
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, pid, {from_id = 0, to_id = t.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0})


## Eternalize (CR 702.129a) / embalm (CR 702.128a): a token copy that is a Zombie in addition to its types, with no
## mana cost; eternalize also makes it a black 4/4.
func _zombie_copy(pid: int, card_def: CardDefinition, color: String, four_four: bool) -> void:
	var d := card_def.copy_def()
	d.mana_cost = ""
	d.colors = PackedStringArray([color])
	var parts := d.type_line.split("—")
	var left := parts[0].strip_edges()
	var subs := parts[1].strip_edges() if parts.size() > 1 else ""
	d.type_line = "Token %s — Zombie%s" % [left, (" " + subs) if subs != "" else ""]
	if four_four:
		d.power = "4"
		d.toughness = "4"
	var t: GameObject = engine.state.zones.create(pid, EngineEnums.ZoneId.BATTLEFIELD, {definition = d, is_token = true, controller_id = pid})
	if t != null:
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, pid, {from_id = 0, to_id = t.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0})


func _cycling_filter(ty: String) -> Dictionary:
	match ty:
		"land":
			return {"type": "land"}
		"basic land":
			return {"type": "land", "basic_land": true}
		"plains", "island", "swamp", "mountain", "forest":
			return {"type": "land", "subtype": ty.capitalize()}
		_:
			return {"type": "creature", "subtype": ty.capitalize()}


func _ninjutsu(action: GameAction, ninja: GameObject, kw: Dictionary) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	var pid := action.player_id
	var aid := int(action.extra.get("attacker_id", 0))
	if ninja.zone != EngineEnums.ZoneId.HAND or not kw.has("ninjutsu") or not _unblocked_attackers(pid).has(aid):
		r.error = "no unblocked attacker"
		return r
	if not engine.pay_now(pid, _cost(str(kw.ninjutsu))):
		r.error = "can't pay"
		return r
	var cs := engine.state.combat as CombatState
	var defender := int(cs.defenders.get(aid, cs.defending_player_id))
	cs.attacker_ids.erase(aid)
	cs.defenders.erase(aid)
	var back: GameObject = engine.state.zones.move(aid, EngineEnums.ZoneId.HAND, _obj(aid).owner_id)
	var landed: GameObject = engine.state.zones.move(ninja.object_id, EngineEnums.ZoneId.BATTLEFIELD, pid)
	if landed != null:
		landed.tapped = true
		cs.attacker_ids.append(landed.object_id)
		cs.defenders[landed.object_id] = defender
	r.ok = back != null
	return r


# --- Ward (CR 702.21) -----------------------------------------------------------------------------

## {"cost": "{2}", "life": 0} for a permanent with ward, else {}.
func ward_of(o: GameObject) -> Dictionary:
	if o == null:
		return {}
	var kw := kw_of(o) if not o.face_down else {}
	if kw.has("ward"):
		return kw.ward
	if o.ward_extra != "":
		return {"cost": o.ward_extra, "life": 0}
	return {}


## Called when a spell or ability goes on the stack: each of its targets with ward gets a ward trigger.
func check_ward(entry: StackEntry) -> void:
	if entry == null:
		return
	for tid in entry.targets:
		var t := _obj(int(tid))
		## "When ~ becomes the target of a spell or ability, sacrifice it." / "... an opponent controls, ..." (CR 603.2).
		if t != null and t.zone == EngineEnums.ZoneId.BATTLEFIELD and engine.triggers != null:
			for tab in engine.triggers._triggered(engine, t, "BECOMES_TARGET"):
				if bool((tab as Ability).trigger.get("opp_only", false)) and t.controller_id == entry.controller_id:
					continue
				engine.triggers._put_trigger(engine, t, tab as Ability, {"controller_of_source": entry.controller_id})
		if t == null or t.zone != EngineEnums.ZoneId.BATTLEFIELD or t.controller_id == entry.controller_id:
			continue
		var w := ward_of(t)
		if w.is_empty():
			continue
		var fx := AbilityEffect.new()
		fx.kind = &"WARD"
		fx.params = {"cost": str(w.get("cost", "")), "life": int(w.get("life", 0)), "target_stack_id": entry.stack_id}
		engine.put_synthetic(t, t.controller_id, [fx], {})


# --- Turn hooks -------------------------------------------------------------------------------------

## Untap step, before untapping: goad wears off, permanents with phasing phase in or out.
func on_untap(pid: int) -> void:
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		if o == null:
			continue
		if o.goaded_by.has(pid):
			o.goaded_by.erase(pid)
	## Phase in what was phased out under this player's control, then phase out their permanents with phasing.
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	## Phasing in and out happens at the same time (CR 502.13): what just came in doesn't go straight back out.
	var came_in: Array = []
	for oid2 in engine.state.objects.keys():
		var p := _obj(int(oid2))
		if p != null and p.phased_out and p.controller_id == pid:
			p.phased_out = false
			came_in.append(p.object_id)
			if not bf.object_ids.has(p.object_id):
				bf.object_ids.append(p.object_id)
	for oid3 in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var q := _obj(int(oid3))
		if q != null and q.controller_id == pid and kw_of(q).has("phasing") and not q.phased_out and not came_in.has(q.object_id):
			q.phased_out = true
			bf.object_ids.erase(q.object_id)


## Upkeep and end step beginnings, called from the trigger manager.
func on_step_begin(step: int, active: int) -> void:
	if step == EngineEnums.Step.UPKEEP:
		_suspend_tick(active)
		_rebound_tick(active)
		## The initiative (CR 725.2): its holder ventures into Undercity at the beginning of their upkeep.
		if engine.state.initiative_id == active:
			var vfx := AbilityEffect.new()
			vfx.kind = &"VENTURE"
			vfx.params = {"dungeon": "undercity"}
			engine.put_synthetic(null, active, [vfx], {})
	elif step == EngineEnums.Step.END:
		for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
			var o := _obj(int(oid))
			if o != null and o.dashed and o.controller_id == active:
				engine.state.zones.move(o.object_id, EngineEnums.ZoneId.HAND, o.owner_id)
				continue
			## Encore tokens are sacrificed at the beginning of the next end step (CR 702.141a); blitz draws a card
			## when the creature dies (CR 702.152a).
			if o != null and o.sacrifice_at_end:
				var blitzed := bool(o.marks.get("blitzed", false))
				var who := o.controller_id
				var gone: GameObject = engine.state.zones.move(o.object_id, EngineEnums.ZoneId.GRAVEYARD, o.owner_id)
				if blitzed and gone != null and gone.zone == EngineEnums.ZoneId.GRAVEYARD:
					engine.draw_card(who)
				continue
			## Unearth (CR 702.84a): exiled at the beginning of the next end step.
			if o != null and o.unearthed:
				engine.state.zones.move(o.object_id, EngineEnums.ZoneId.EXILE, o.owner_id)
				continue
			## Warp (CR 702.185a): exiled at the beginning of the next end step; it may be cast from exile later.
			if o != null and bool(o.marks.get("warped", false)):
				var ex_w: GameObject = engine.state.zones.move(o.object_id, EngineEnums.ZoneId.EXILE, o.owner_id)
				if ex_w != null:
					ex_w.exile_cast = "warp"
					ex_w.plotted_turn = engine.state.turn_number
				continue
			## Impending (CR 702.176a): at the beginning of your end step, remove a time counter.
			if o != null and o.controller_id == active and o.cast_mode == "impending" and int(o.counters.get("time", 0)) > 0:
				o.counters["time"] = int(o.counters["time"]) - 1


func _suspend_tick(active: int) -> void:
	for oid in _zone_ids(EngineEnums.ZoneId.EXILE, active):
		var o := _obj(int(oid))
		if o == null or o.cast_mode != "suspend" or int(o.counters.get("time", 0)) <= 0:
			continue
		var left := int(o.counters["time"]) - 1
		o.counters["time"] = left
		if left <= 0:
			o.counters.erase("time")
			cast_now(active, o.object_id, {"mode": "suspend"}, true)


func _rebound_tick(active: int) -> void:
	var keep: Array = []
	for q in engine.state.rebound_queue:
		var qd: Dictionary = q
		if int(qd.owner) == active and int(qd.turn) < engine.state.turn_number:
			var o := _obj(int(qd.object_id))
			if o != null and o.zone == EngineEnums.ZoneId.EXILE:
				cast_now(active, o.object_id, {"mode": "rebound"}, true)
		else:
			keep.append(q)
	engine.state.rebound_queue = keep


## Damage dealt to a player (any source); combat damage also records which creature types connected (prowl).
func note_player_damaged(pid: int, source: GameObject, combat: bool) -> void:
	if pid < 0 or pid >= engine.state.players.size():
		return
	engine.state.players[pid].damaged_this_turn = true
	## Combat damage to the player with the initiative takes it (CR 725.2).
	if combat and source != null and engine.state.initiative_id == pid and source.controller_id != pid:
		KeywordActions.take_initiative(engine, source.controller_id)
	if combat and source != null and _def(source) != null:
		var mine: PlayerState = engine.state.players[source.controller_id]
		var parts := _def(source).type_line.split("—")
		var words: Array = Array(parts[0].strip_edges().split(" ", false))
		if parts.size() > 1:
			words.append_array(Array(parts[1].strip_edges().split(" ", false)))
		for w in words:
			if not mine.combat_damagers_types.has(str(w)):
				mine.combat_damagers_types.append(str(w))


## Start of a new turn: the per-turn flags reset.
func on_new_turn() -> void:
	_day_night_turn()
	engine.state.creatures_died_this_turn = 0
	if engine.state.active_player_id >= 0 and engine.state.active_player_id < engine.state.players.size():
		engine.state.players[engine.state.active_player_id].turns_taken += 1
	for p in engine.state.players:
		p.damaged_this_turn = false
		p.combat_damagers_types = []
		p.draws_this_turn = 0
		p.nonland_entered_this_turn = 0
		p.attacked_this_turn = false
		engine.state.prevention = []
		p.life_gained_this_turn = 0
		p.life_lost_this_turn = 0
		p.permanents_left_this_turn = 0
		p.spells_this_turn = []


## Day and night (CR 726): it becomes day when a daybound permanent appears and it's neither; each turn, if it's
## day and last turn's active player cast no spells it becomes night, and if it's night and they cast two or more it
## becomes day. Daybound / nightbound permanents transform to match (CR 702.145).
func _day_night_turn() -> void:
	var st := engine.state
	var n := st.players.size()
	if n == 0:
		return
	if st.day_night == "":
		if not _bound_permanents().is_empty():
			st.day_night = "day"
		return
	var prev := (st.active_player_id - 1 + n) % n
	var cast := (st.players[prev].spells_this_turn as Array).size()
	if st.day_night == "day" and cast == 0:
		st.day_night = "night"
	elif st.day_night == "night" and cast >= 2:
		st.day_night = "day"
	sync_day_night()


func _bound_permanents() -> Array:
	var out: Array = []
	for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
		var o := _obj(int(oid))
		var d := _def(o)
		var fd: CardDefinition = o.front_def if o != null and o.front_def is CardDefinition else d
		if d != null and (d.kw().has("daybound") or d.kw().has("nightbound") or (fd != null and fd.kw().has("daybound"))):
			out.append(o)
	return out


## Daybound faces up while it's day, nightbound faces up while it's night.
func sync_day_night() -> void:
	var st := engine.state
	if st.day_night == "":
		if not _bound_permanents().is_empty():
			st.day_night = "day"
		else:
			return
	for o in _bound_permanents():
		var d := _def(o)
		var is_night_face := d.kw().has("nightbound")
		if (st.day_night == "night") != is_night_face:
			KeywordActions.transform(engine, o)


## Speed (CR 702.179): a player with a "start your engines!" permanent has speed 1 or more; once each of their
## turns, when an opponent loses life, it goes up by 1 (to 4 at most). Called by state-based checks.
func update_speed() -> void:
	var st := engine.state
	for p in st.players:
		if p.speed == 0:
			for oid in _zone_ids(EngineEnums.ZoneId.BATTLEFIELD, -1):
				var o := _obj(int(oid))
				if o != null and o.controller_id == p.player_id and _def(o) != null and _def(o).kw().has("start_your_engines"):
					p.speed = 1
					break
	var me: PlayerState = st.players[st.active_player_id] if st.active_player_id >= 0 and st.active_player_id < st.players.size() else null
	if me == null or me.speed <= 0 or me.speed >= 4 or me.speed_turn == st.turn_number:
		return
	for p2 in st.players:
		if p2.player_id != me.player_id and p2.life_lost_this_turn > 0:
			me.speed += 1
			me.speed_turn = st.turn_number
			return


## The first card a player draws each turn: miracle (CR 702.94).
func on_drawn(pid: int, card: GameObject) -> void:
	if card == null:
		return
	engine.state.players[pid].draws_this_turn += 1
	if engine.state.players[pid].draws_this_turn != 1:
		return
	var d := _def(card)
	if d == null or not d.kw().has("miracle"):
		return
	var fx := AbilityEffect.new()
	fx.kind = &"MIRACLE"
	fx.params = {"object_id": card.object_id}
	engine.put_synthetic(null, pid, [fx], {}, card.object_id)


## Goaded creatures that can attack must (CR 701.15b). Returns `ids` with them added.
func with_goaded(pid: int, ids: Array, legal: Array) -> Array:
	var out := ids.duplicate()
	for oid in legal:
		var o := _obj(int(oid))
		if o != null and not o.goaded_by.is_empty() and not out.has(int(oid)):
			out.append(int(oid))
	return out
