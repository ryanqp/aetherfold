class_name LayerManager
extends RefCounted

## CR 613. Printed values stay on CardDefinition. This snapshot is the current characteristics.

func snapshot(state: GameState, obj: GameObject) -> Dictionary:
	var printed_p := 0
	var printed_t := 0
	var type_line := ""
	var keywords := PackedStringArray()
	var subtypes := PackedStringArray()
	if obj != null and obj.definition is CardDefinition:
		var def := obj.definition as CardDefinition
		printed_p = int(def.power) if def.power.is_valid_int() else 0
		printed_t = int(def.toughness) if def.toughness.is_valid_int() else 0
		type_line = def.type_line
		keywords = def.keywords.duplicate()
		subtypes = _subtypes_of(def.type_line)
		## Face-down permanents (CR 708.2): a 2/2 with no name, types beyond creature, subtypes or abilities.
		if obj.face_down:
			printed_p = 2
			printed_t = 2
			type_line = "Creature"
			keywords = PackedStringArray()
			subtypes = PackedStringArray()
			if obj.ward_extra != "":
				keywords.append("Ward")
		## Level up / station bands (CR 711.2, 721.2): the band's P/T and keywords; a Spacecraft with a P/T band
		## reached is an artifact creature.
		elif obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
			var band := KeywordLines.band_for(def, obj.counters)
			if not band.is_empty():
				if int(band.power) >= 0:
					printed_p = int(band.power)
					printed_t = int(band.toughness)
					if not type_line.contains("Creature"):
						type_line = type_line.replace("Artifact", "Artifact Creature")
				for bk in band.keywords:
					if not keywords.has(str(bk)):
						keywords.append(str(bk))
	## Characteristic-changing statics (CR 613.1d-f, 613.4b): Auras such as "enchanted creature loses all abilities and
	## is a green Elk creature with base power and toughness 3/3", imprint copies, celebration, impending.
	if obj != null and not obj.face_down and state != null:
		for spec in _char_specs(state, obj):
			var sp: Dictionary = spec
			if bool(sp.get("lose_abilities", false)):
				keywords = PackedStringArray()
			if sp.has("set_type_line"):
				type_line = str(sp["set_type_line"])
				subtypes = _subtypes_of(type_line)
			if sp.has("set_subtypes"):
				subtypes = PackedStringArray(sp["set_subtypes"])
				type_line = _with_subtypes(type_line, subtypes)
			if sp.has("add_subtypes"):
				for st_name in sp["add_subtypes"]:
					if not subtypes.has(str(st_name)):
						subtypes.append(str(st_name))
				type_line = _with_subtypes(type_line, subtypes)
			if sp.has("base_pt"):
				printed_p = int((sp["base_pt"] as Array)[0])
				printed_t = int((sp["base_pt"] as Array)[1])
			if bool(sp.get("imprint_pt", false)):
				var card := _imprinted_creature(state, obj)
				if card != null:
					var cd := card.definition as CardDefinition
					printed_p = int(cd.power) if cd.power.is_valid_int() else 0
					printed_t = int(cd.toughness) if cd.toughness.is_valid_int() else 0
					var subs := _subtypes_of(cd.type_line)
					if not subs.has("Shapeshifter"):
						subs.append("Shapeshifter")
					subtypes = subs
					type_line = _with_subtypes(type_line, subtypes)
			for kw0 in sp.get("char_keywords", []):
				keywords.append(str(kw0))
		## Reconfigure (CR 702.151b): an Equipment creature attached to a creature isn't a creature.
		if obj.attached_to != 0 and obj.definition is CardDefinition and (obj.definition as CardDefinition).kw().has("reconfigure"):
			type_line = type_line.replace("Creature ", "").replace(" Creature", "").strip_edges()
		## Living metal (CR 702.161a): during its controller's turn this Vehicle is also an artifact creature.
		if obj.zone == EngineEnums.ZoneId.BATTLEFIELD and obj.controller_id == state.active_player_id \
				and obj.definition is CardDefinition and (obj.definition as CardDefinition).kw().has("living_metal") \
				and not type_line.contains("Creature"):
			type_line = type_line.replace("Artifact", "Artifact Creature")
		## Bestowed (CR 702.103b): an Aura with enchant creature, not a creature, while attached.
		if obj.bestowed and obj.attached_to != 0:
			type_line = type_line.replace("Creature ", "").replace(" Creature", "").replace("Creature", "").strip_edges()
			if not type_line.contains("Aura"):
				type_line = type_line + (" Aura" if type_line.contains("—") else " — Aura")
		## Impending (CR 702.176a): not a creature while it has a time counter.
		if obj.cast_mode == "impending" and int(obj.counters.get("time", 0)) > 0:
			type_line = type_line.replace("Creature ", "").replace(" Creature", "").replace("Creature", "").strip_edges()
	var power := printed_p
	var toughness := printed_t
	var subtype_sets: Array = []
	var pt_sets: Array = []
	var mod_p := 0
	var mod_t := 0
	if state != null:
		for e in state.effects:
			if not (e is ContinuousEffect):
				continue
			var fx := e as ContinuousEffect
			if not _affects(state, fx, obj):
				continue
			if not fx.set_subtypes.is_empty():
				subtype_sets.append(fx)
			if fx.sets_power or fx.sets_toughness:
				pt_sets.append(fx)
			mod_p += fx.power
			mod_t += fx.toughness
			for kw in fx.add_keywords:
				keywords.append(kw)
			for t in fx.add_types:
				if not type_line.split("—")[0].contains(t):
					var lp := type_line.split("—")
					type_line = ("%s %s" % [lp[0].strip_edges(), t]).strip_edges() + ((" — " + lp[1].strip_edges()) if lp.size() > 1 else "")
	## Static abilities of permanents ("creatures you control get +1/+1", equipment). CR 613.4c, 613.1f.
	var statics := _static_mods(state, obj)
	mod_p += int(statics["power"])
	mod_t += int(statics["toughness"])
	for kw in statics["keywords"]:
		keywords.append(str(kw))
	if not subtype_sets.is_empty():
		subtype_sets.sort_custom(func(a, b) -> bool:
			return (a as ContinuousEffect).timestamp < (b as ContinuousEffect).timestamp
		)
		subtypes = (subtype_sets[subtype_sets.size() - 1] as ContinuousEffect).set_subtypes.duplicate()
		type_line = _with_subtypes(type_line, subtypes)
	if not pt_sets.is_empty():
		pt_sets.sort_custom(func(a, b) -> bool:
			return (a as ContinuousEffect).timestamp < (b as ContinuousEffect).timestamp
		)
		var last := pt_sets[pt_sets.size() - 1] as ContinuousEffect
		if last.sets_power:
			power = last.set_power
		if last.sets_toughness:
			toughness = last.set_toughness
	## Status effects that give a keyword: dash and suspend haste, suspect's menace.
	if obj != null:
		if obj.dashed or obj.granted_haste:
			keywords.append("Haste")
		if obj.suspected:
			keywords.append("Menace")
	power += mod_p
	toughness += mod_t
	if obj != null and _is_creature_line(type_line):
		power += _counter_delta(obj)
		toughness += _counter_delta(obj)
	return {
		power = power,
		toughness = toughness,
		printed_power = printed_p,
		printed_toughness = printed_t,
		type_line = type_line,
		subtypes = subtypes,
		keywords = keywords,
	}


func power(state: GameState, obj: GameObject) -> int:
	return int(snapshot(state, obj).get("power", 0))


func has_subtype(state: GameState, obj: GameObject, subtype_name: String) -> bool:
	var subs: Variant = snapshot(state, obj).get("subtypes", PackedStringArray())
	if subs is PackedStringArray:
		return (subs as PackedStringArray).has(subtype_name)
	return false


func has_keyword(state: GameState, obj: GameObject, keyword: String) -> bool:
	var kws: Variant = snapshot(state, obj).get("keywords", PackedStringArray())
	if not (kws is PackedStringArray):
		return false
	var want := keyword.to_lower()
	for kw in kws:
		if str(kw).to_lower() == want:
			return true
	return false


func abilities_for(state: GameState, obj: GameObject) -> Array:
	var out: Array = []
	if obj == null or not (obj.definition is CardDefinition) or obj.face_down:
		return out
	## "Loses all abilities" (CR 613.1f): nothing printed is left; a granted "{T}: Add {C}." may be.
	if state != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		var lost := false
		for spec in _char_specs(state, obj):
			if bool((spec as Dictionary).get("lose_abilities", false)):
				lost = true
				if str((spec as Dictionary).get("grant_mana", "")) != "":
					out.append(_tap_for_mana(str((spec as Dictionary)["grant_mana"])))
		if lost:
			return out
	var gained := {}
	if state != null:
		for e in state.effects:
			if not (e is ContinuousEffect):
				continue
			var fx := e as ContinuousEffect
			if not _affects(state, fx, obj):
				continue
			for id in fx.gain_ability_ids:
				gained[str(id)] = true
			for extra_ab in fx.add_abilities:
				if not out.has(extra_ab):
					out.append(extra_ab)
		## Granted by the card's own conditional static ("as long as ..., ~ has '{R}: ...'", celebration).
		for a0 in (obj.definition as CardDefinition).abilities:
			var sab := a0 as Ability
			if sab == null or sab.kind != &"STATIC" or not sab.static_spec.has("grant_ability_ids"):
				continue
			if obj.zone == EngineEnums.ZoneId.BATTLEFIELD and static_applies(state, obj, sab.static_spec, obj):
				for gid in sab.static_spec["grant_ability_ids"]:
					gained[str(gid)] = true
	for a in (obj.definition as CardDefinition).abilities:
		if not (a is Ability):
			continue
		var ab := a as Ability
		if ab.unparsed:
			continue
		if ab.granted:
			if gained.has(str(ab.ability_id)):
				out.append(ab)
		else:
			out.append(ab)
	return out


## Statics on the battlefield with key `key` that apply to `obj` (Auras on it: doesn't untap, can't attack or block).
func attached_specs(state: GameState, obj: GameObject, key: String) -> Array:
	var out: Array = []
	if state == null or obj == null or state.zones == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return out
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or src.face_down or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and not ab.unparsed and ab.static_spec.has(key) and static_applies(state, src, ab.static_spec, obj):
				out.append(ab.static_spec)
	return out


## Total +P/+T and granted keywords from static abilities on the battlefield that apply to `obj`.
func _static_mods(state: GameState, obj: GameObject) -> Dictionary:
	var mods := {"power": 0, "toughness": 0, "keywords": []}
	if state == null or obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD or state.zones == null:
		return mods
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return mods
	var sources: Array = bf.object_ids.duplicate()
	## Statics that work from a graveyard ("as long as ~ is in your graveyard", Anger).
	for pid in state.players.size():
		var gy: Zone = state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, pid)
		if gy != null:
			for gid in gy.object_ids:
				var gobj: GameObject = state.objects.get(gid)
				if gobj != null and gobj.definition is CardDefinition and (gobj.definition as CardDefinition).oracle_text.to_lower().contains("is in your graveyard"):
					sources.append(gid)
	for oid in sources:
		var src: GameObject = state.objects.get(oid)
		if src == null or src.face_down or not (src.definition is CardDefinition):
			continue
		var in_gy := src.zone == EngineEnums.ZoneId.GRAVEYARD
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or ab.unparsed or ab.static_spec.is_empty():
				continue
			var spec: Dictionary = ab.static_spec
			if in_gy != bool(spec.get("from_graveyard", false)):
				continue
			if not (spec.has("power") or spec.has("toughness") or spec.has("keywords")):
				continue
			if not static_applies(state, src, spec, obj):
				continue
			var mult := 1
			## "+1/+1 for each artifact you control", "+X/+X where X is the greatest mana value among your commanders".
			if spec.has("per"):
				mult = Query.count_objects(state, src, spec["per"])
			elif bool(spec.get("x_commander_mv", false)):
				mult = _commander_max_mv(state, src.controller_id)
			mods["power"] = int(mods["power"]) + int(spec.get("power", 0)) * mult
			mods["toughness"] = int(mods["toughness"]) + int(spec.get("toughness", 0)) * mult
			var kws: Variant = spec.get("keywords", [])
			if kws is Array:
				for kw in kws:
					(mods["keywords"] as Array).append(str(kw))
	return mods


## Does the static ability `spec` of permanent `src` apply to `obj`?
func static_applies(state: GameState, src: GameObject, spec: Dictionary, obj: GameObject) -> bool:
	var cond: Variant = spec.get("condition", {})
	if cond is Dictionary and not condition_met(state, src, cond):
		return false
	var scope := str(spec.get("scope", "SELF"))
	match scope:
		"SELF":
			return src.object_id == obj.object_id
		"EQUIPPED":
			if src.attached_to != obj.object_id:
				return false
			return obj.zone == EngineEnums.ZoneId.BATTLEFIELD and _is_creature_line(_type_line_of(obj))
		"ENCHANTED":
			return src.attached_to == obj.object_id and obj.zone == EngineEnums.ZoneId.BATTLEFIELD
		"OTHERS":
			if src.object_id == obj.object_id:
				return false
		"ALL":
			pass
		_:
			return false
	var q: Variant = spec.get("query", {})
	if q is Dictionary and not (q as Dictionary).is_empty():
		return Query._matches(obj, src, q)
	return true


## "This creature can't attack or block unless you control seven or more lands."
func combat_restricted(state: GameState, obj: GameObject) -> bool:
	if obj == null or not (obj.definition is CardDefinition):
		return false
	## "Enchanted creature can't attack or block." from an Aura on it.
	for spec in attached_specs(state, obj, "cant_attack_block"):
		return true
	for a in (obj.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("cant_attack_block_unless"):
			continue
		var need: Dictionary = ab.static_spec["cant_attack_block_unless"]
		if need.has("lands"):
			var lands := Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER", "type": "land"})
			if lands < int(need["lands"]):
				return true
		if need.has("permanents"):
			var perms := Query.count_objects(state, obj, {"controller": "SOURCE_CONTROLLER"})
			if perms < int(need["permanents"]):
				return true
	return false


func _type_line_of(obj: GameObject) -> String:
	return (obj.definition as CardDefinition).type_line if obj.definition is CardDefinition else ""


func clear_until_eot(state: GameState) -> void:
	var kept: Array = []
	for e in state.effects:
		if e is ContinuousEffect and (e as ContinuousEffect).until_eot:
			continue
		kept.append(e)
	state.effects = kept


func _affects(state: GameState, fx: ContinuousEffect, obj: GameObject) -> bool:
	if obj == null:
		return false
	if fx.object_ids.is_empty() and fx.query.is_empty():
		return true
	if fx.object_ids.has(obj.object_id):
		return true
	if not fx.query.is_empty():
		var source: GameObject = state.objects.get(fx.source_id) as GameObject
		return Query._matches(obj, source, fx.query)
	return false


func _counter_delta(obj: GameObject) -> int:
	return int(obj.counters.get("+1/+1", 0)) - int(obj.counters.get("-1/-1", 0))


func _is_creature_line(type_line: String) -> bool:
	return type_line.contains("Creature")


func _subtypes_of(type_line: String) -> PackedStringArray:
	var parts := type_line.split("—")
	if parts.size() < 2:
		return PackedStringArray()
	var right := parts[parts.size() - 1].strip_edges()
	if right == "":
		return PackedStringArray()
	return PackedStringArray(right.split(" ", false))


func _with_subtypes(type_line: String, subtypes: PackedStringArray) -> String:
	var parts := type_line.split("—")
	var left := parts[0].strip_edges() if not parts.is_empty() else type_line
	if subtypes.is_empty():
		return left
	return "%s — %s" % [left, " ".join(subtypes)]



## Conditions a static ability can have (CR 611.3a "as long as ..."):
##   controls {query}, min n          you control at least n matching permanents
##   celebration n                    n or more nonland permanents entered under your control this turn
##   opp_poison_min n                 an opponent has n or more poison counters (corrupted)
##   monarch true / false             you are (are not) the monarch
func condition_met(state: GameState, src: GameObject, cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	var pid := src.controller_id if src != null else -1
	if cond.has("controls"):
		var need := int(cond.get("min", 1))
		if Query.count_objects(state, src, cond["controls"]) < need:
			return false
	if cond.has("celebration"):
		if pid < 0 or pid >= state.players.size() or state.players[pid].nonland_entered_this_turn < int(cond["celebration"]):
			return false
	if cond.has("opp_poison_min"):
		var hit := false
		for p in state.players:
			if p.player_id != pid and not p.lost and p.poison >= int(cond["opp_poison_min"]):
				hit = true
		if not hit:
			return false
	if cond.has("monarch") and (state.monarch_id == pid) != bool(cond["monarch"]):
		return false
	return _more_conditions(state, src, pid, cond)


## The rest of the condition vocabulary (the ability-word family: threshold, delirium, metalcraft, hellbent, raid, morbid,
## revolt, formidable, ferocious, coven, descend, spell mastery ...). Every key present must hold.
##   max n (with controls)            at most n matching (0 = "you don't control any ...")
##   my_turn bool                     it is (is not) your turn
##   life_min / life_max n            your life total
##   hand_min / hand_max n            cards in your hand (hellbent: hand_max 0)
##   graveyard_types_min n            card types among cards in your graveyard (delirium)
##   attacked bool                    you attacked with a creature this turn (raid)
##   creature_died bool               a creature died this turn (morbid)
##   permanent_left bool              a permanent you controlled left the battlefield this turn (revolt)
##   gained_life bool                 you gained life this turn
##   power_total_min n                creatures you control have total power n or more (formidable)
##   power_any_min n                  you control a creature with power n or greater (ferocious)
##   distinct_powers_min n            creatures you control with different powers (coven)
##   paid_has / paid_lacks "Land"      the card discarded or sacrificed as an additional cost was (wasn't) of that type
##   not {cond}                       the nested condition does not hold
func _more_conditions(state: GameState, src: GameObject, pid: int, cond: Dictionary) -> bool:
	if cond.has("controls") and cond.has("max") and Query.count_objects(state, src, cond["controls"]) > int(cond["max"]):
		return false
	if cond.has("my_turn") and (state.active_player_id == pid) != bool(cond["my_turn"]):
		return false
	var me: PlayerState = state.players[pid] if pid >= 0 and pid < state.players.size() else null
	if me != null:
		if cond.has("life_min") and me.life < int(cond["life_min"]):
			return false
		if cond.has("life_max") and me.life > int(cond["life_max"]):
			return false
		if cond.has("attacked") and me.attacked_this_turn != bool(cond["attacked"]):
			return false
		if cond.has("permanent_left") and (me.permanents_left_this_turn > 0) != bool(cond["permanent_left"]):
			return false
		if cond.has("gained_life") and (me.life_gained_this_turn > 0) != bool(cond["gained_life"]):
			return false
	if cond.has("paid_has") or cond.has("paid_lacks"):
		var paid: Array = src.marks.get("paid_types", []) if src != null else []
		var hit := false
		for tl in paid:
			if str(tl).contains(str(cond.get("paid_has", cond.get("paid_lacks", "")))):
				hit = true
		if cond.has("paid_has") and not hit:
			return false
		if cond.has("paid_lacks") and (hit or paid.is_empty()):
			return false
	if cond.has("opp_lost_life"):
		var lost := false
		for op in state.players:
			if op.player_id != pid and op.life_lost_this_turn > 0:
				lost = true
		if lost != bool(cond["opp_lost_life"]):
			return false
	if cond.has("creature_died") and (state.creatures_died_this_turn > 0) != bool(cond["creature_died"]):
		return false
	if cond.has("hand_min") or cond.has("hand_max"):
		var hand := Query.count_objects(state, src, {"zone": "HAND"})
		if cond.has("hand_min") and hand < int(cond["hand_min"]):
			return false
		if cond.has("hand_max") and hand > int(cond["hand_max"]):
			return false
	if cond.has("graveyard_types_min"):
		var kinds := {}
		var gy: Zone = state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, pid)
		if gy != null:
			for oid in gy.object_ids:
				var g: GameObject = state.objects.get(oid)
				if g != null and g.definition is CardDefinition:
					for t in ["Artifact", "Battle", "Creature", "Enchantment", "Instant", "Kindred", "Land", "Planeswalker", "Sorcery"]:
						if (g.definition as CardDefinition).type_line.contains(t):
							kinds[t] = true
		if kinds.size() < int(cond["graveyard_types_min"]):
			return false
	if cond.has("power_total_min") or cond.has("power_any_min") or cond.has("distinct_powers_min"):
		var total := 0
		var best := 0
		var seen := {}
		var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf != null:
			for oid2 in bf.object_ids:
				var c: GameObject = state.objects.get(oid2)
				if c == null or c.controller_id != pid or not (c.definition is CardDefinition) or not (c.definition as CardDefinition).is_creature():
					continue
				var pw := int((c.definition as CardDefinition).power) if str((c.definition as CardDefinition).power).is_valid_int() else 0
				total += pw
				best = maxi(best, pw)
				seen[pw] = true
		if cond.has("power_total_min") and total < int(cond["power_total_min"]):
			return false
		if cond.has("power_any_min") and best < int(cond["power_any_min"]):
			return false
		if cond.has("distinct_powers_min") and seen.size() < int(cond["distinct_powers_min"]):
			return false
	if cond.has("not") and cond["not"] is Dictionary and condition_met(state, src, cond["not"]):
		return false
	return true


## True when an effect makes `obj` lose all its abilities (Kenrith's Transformation, Imprisoned in the Moon).
func loses_abilities(state: GameState, obj: GameObject) -> bool:
	for spec in _char_specs(state, obj):
		if bool((spec as Dictionary).get("lose_abilities", false)):
			return true
	return false


## Statics on the battlefield that change `obj`'s characteristics (not just +N/+N or keywords).
const CHAR_KEYS := ["lose_abilities", "set_type_line", "set_subtypes", "add_subtypes", "base_pt", "imprint_pt", "char_keywords"]


func _char_specs(state: GameState, obj: GameObject) -> Array:
	var out: Array = []
	if state == null or obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD or state.zones == null:
		return out
	var bf: Zone = state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var src: GameObject = state.objects.get(oid)
		if src == null or src.face_down or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or ab.unparsed:
				continue
			var spec: Dictionary = ab.static_spec
			var any := false
			for k in CHAR_KEYS:
				if spec.has(k):
					any = true
					break
			if any and static_applies(state, src, spec, obj):
				out.append(spec)
	return out


## The newest creature card exiled with an imprint ability of `obj` (Duplicant), or null.
func _imprinted_creature(state: GameState, obj: GameObject) -> GameObject:
	for i in range(obj.imprinted.size() - 1, -1, -1):
		var c: GameObject = state.objects.get(int(obj.imprinted[i]))
		if c != null and c.zone == EngineEnums.ZoneId.EXILE and c.definition is CardDefinition and (c.definition as CardDefinition).is_creature():
			return c
	return null


## The greatest mana value among `pid`'s commanders, wherever they are (Tangleweave Armor).
func _commander_max_mv(state: GameState, pid: int) -> int:
	var best := 0
	for oid in state.objects.keys():
		var o: GameObject = state.objects[oid]
		if o != null and o.is_commander and o.owner_id == pid and o.definition is CardDefinition:
			best = maxi(best, (o.definition as CardDefinition).cmc)
	return best


var _mana_abilities: Dictionary = {}


## A "{T}: Add {C}." mana ability given by an effect (Imprisoned in the Moon).
func _tap_for_mana(mana: String) -> Ability:
	if _mana_abilities.has(mana):
		return _mana_abilities[mana]
	var ab := Ability.new()
	ab.ability_id = StringName("granted_tap_%s" % mana.to_lower().replace("{", "").replace("}", ""))
	ab.kind = &"MANA"
	ab.text = "{T}: Add %s." % mana
	var tap := AbilityCost.new()
	tap.kind = &"TAP"
	ab.costs.append(tap)
	var fx := AbilityEffect.new()
	fx.kind = &"ADD_MANA"
	fx.params = {"mana": mana}
	ab.effects.append(fx)
	_mana_abilities[mana] = ab
	return ab
