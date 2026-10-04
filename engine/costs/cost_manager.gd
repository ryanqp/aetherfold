class_name CostManager
extends RefCounted

var _state_ref: WeakRef = null


func bind(state: GameState) -> void:
	_state_ref = weakref(state)


func _state() -> GameState:
	return _state_ref.get_ref() as GameState if _state_ref != null else null

func mana_cost(ability: Ability) -> ManaCost:
	var total := ManaCost.new()
	if ability == null:
		return total
	for c in ability.costs:
		if c is AbilityCost and (c as AbilityCost).kind == &"MANA":
			total.absorb(ManaCost.parse((c as AbilityCost).mana))
	return total


func can_pay(obj: GameObject, ability: Ability) -> bool:
	if obj == null or ability == null:
		return false
	for c in ability.costs:
		if not (c is AbilityCost):
			return false
		var cost := c as AbilityCost
		if cost.kind == &"TAP" and obj.tapped:
			return false
		if cost.kind == &"UNTAP" and not obj.tapped:
			return false
		if cost.kind in [&"SACRIFICE", &"RETURN_OWN"] and sacrifice_candidates(obj, str(cost.mana)).size() < _spec_count(str(cost.mana)):
			return false
		if cost.kind == &"TAP_PERMANENTS" and _untapped_candidates(obj, str(cost.mana)).size() < _spec_count(str(cost.mana)):
			return false
		if cost.kind == &"UNTAP_PERMANENTS" and _tapped_candidates(obj, str(cost.mana)).size() < _spec_count(str(cost.mana)):
			return false
		if cost.kind == &"DISCARD" and _discard_pick(obj) == null:
			return false
		if cost.kind == &"REMOVE_COUNTER" and int(obj.counters.get(str(cost.mana), 0)) < 1:
			return false
		## CR 606.6: a loyalty cost can't remove more loyalty counters than the planeswalker has.
		if cost.kind == &"LOYALTY" and int(obj.counters.get("loyalty", 0)) + int(cost.mana) < 0:
			return false
		## CR 119.4: a player can pay life only if their life total is at least that much.
		if cost.kind == &"PAY_LIFE":
			var st := _state()
			if st == null or obj.controller_id < 0 or obj.controller_id >= st.players.size() or st.players[obj.controller_id].life < _life_amount(obj, str(cost.mana)):
				return false
	return true


func pay(obj: GameObject, ability: Ability) -> bool:
	if not can_pay(obj, ability):
		return false
	for c in ability.costs:
		var cost := c as AbilityCost
		if cost.kind == &"TAP":
			obj.tapped = true
		elif cost.kind == &"UNTAP":
			obj.tapped = false
		elif cost.kind == &"LOYALTY":
			obj.counters["loyalty"] = int(obj.counters.get("loyalty", 0)) + int(cost.mana)
		elif cost.kind == &"PAY_LIFE":
			var st := _state()
			if st != null:
				var pay_n := _life_amount(obj, str(cost.mana))
				st.players[obj.controller_id].life -= pay_n
				st.log.append(EngineEnums.EventType.LIFE_CHANGE, obj.controller_id, {to_player = obj.controller_id, amount = pay_n})
		elif cost.kind == &"ADD_COUNTER":
			obj.counters[cost.mana] = int(obj.counters.get(cost.mana, 0)) + 1
		elif cost.kind == &"REMOVE_COUNTER":
			obj.counters[str(cost.mana)] = maxi(0, int(obj.counters.get(str(cost.mana), 0)) - 1)
		elif cost.kind == &"DISCARD":
			var dc := _discard_pick(obj)
			var st3 := _state()
			if dc != null and st3 != null:
				dc.discarded_turn = st3.turn_number
				st3.zones.move(dc.object_id, EngineEnums.ZoneId.GRAVEYARD, dc.owner_id)
		elif cost.kind in [&"SACRIFICE", &"RETURN_OWN"]:
			var pick := sacrifice_candidates(obj, str(cost.mana))
			var st2 := _state()
			for k in mini(_spec_count(str(cost.mana)), pick.size()):
				if st2 == null:
					break
				var victim: GameObject = pick[k]
				st2.zones.move(victim.object_id, EngineEnums.ZoneId.HAND if cost.kind == &"RETURN_OWN" else EngineEnums.ZoneId.GRAVEYARD, victim.owner_id)
		elif cost.kind == &"UNTAP_PERMANENTS":
			var untap_list := _tapped_candidates(obj, str(cost.mana))
			for k3 in mini(_spec_count(str(cost.mana)), untap_list.size()):
				(untap_list[k3] as GameObject).tapped = false
		elif cost.kind == &"TAP_PERMANENTS":
			var tapped := _untapped_candidates(obj, str(cost.mana))
			for k2 in mini(_spec_count(str(cost.mana)), tapped.size()):
				(tapped[k2] as GameObject).tapped = true
	return true


## N of a "Waterbend {N}" cost (CR 701.67), 0 when the ability has none.
func waterbend_amount(ability: Ability) -> int:
	if ability == null:
		return 0
	var n := 0
	for c in ability.costs:
		if c is AbilityCost and (c as AbilityCost).kind == &"MANA" and (c as AbilityCost).from == &"WATERBEND":
			n += ManaCost.parse((c as AbilityCost).mana).generic
	return n


## "Sacrifice a creature" / "Sacrifice another artifact or creature" / "Sacrifice a Frog" as an ability cost. `spec` is
## "<a|another>|<type words joined with ' or '>". Candidates are the controller's matching permanents, cheapest first
## (tokens, then low mana value, then low power), which is what is sacrificed.
func sacrifice_candidates(obj: GameObject, spec: String) -> Array:
	var st := _state()
	var out: Array = []
	if st == null or obj == null or st.zones == null:
		return out
	var parts := spec.split("|")
	var other := parts.size() > 1 and parts[0] == "another"
	var words := (parts[parts.size() - 1] as String).to_lower().split(" or ", false)
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	## "black creature", "Zombie", "artifact or creature": the grammar's group query when it understands the phrase.
	var gq := OracleIr.new()._group_query(" ".join(PackedStringArray(parts.slice(parts.size() - 1))))
	for oid in bf.object_ids:
		var o: GameObject = st.objects.get(oid)
		if o == null or o.controller_id != obj.controller_id or not (o.definition is CardDefinition):
			continue
		if other and o.object_id == obj.object_id:
			continue
		var tl := (o.definition as CardDefinition).type_line
		var hit := false
		if not gq.is_empty() and not (parts[parts.size() - 1] as String).contains(" or "):
			if Query._matches(o, obj, gq):
				out.append(o)
			continue
		for w in words:
			var word := str(w).strip_edges()
			if word == "permanent" or tl.to_lower().contains(word) or Query._subtype_words(tl).has(word.capitalize()):
				hit = true
		if hit:
			out.append(o)
	out.sort_custom(func(a: GameObject, b: GameObject) -> bool:
		if a.is_token != b.is_token:
			return a.is_token
		var ca := (a.definition as CardDefinition).cmc
		var cb := (b.definition as CardDefinition).cmc
		return ca < cb)
	return out


## The card thrown away for a "Discard a card" cost: an extra land first, otherwise the cheapest card in hand.
func _discard_pick(obj: GameObject) -> GameObject:
	var st := _state()
	if st == null or st.zones == null or obj == null:
		return null
	var hand: Zone = st.zones.get_zone(EngineEnums.ZoneId.HAND, obj.controller_id)
	if hand == null:
		return null
	var best: GameObject = null
	var best_v := 1000000
	for oid in hand.object_ids:
		var c: GameObject = st.objects.get(oid)
		if c == null or not (c.definition is CardDefinition):
			continue
		var d := c.definition as CardDefinition
		var v := (-1 if d.is_land() else 0) + d.cmc * 2
		if v < best_v:
			best_v = v
			best = c
	return best


## Life paid for a PAY_LIFE cost: a number, or "ID_COLORS" = the number of colors in your commanders' color identity (War Room).
func _life_amount(obj: GameObject, spec: String) -> int:
	if spec != "ID_COLORS":
		return int(spec)
	var st := _state()
	if st == null or obj.controller_id < 0 or obj.controller_id >= st.players.size():
		return 0
	var colors := {}
	for cid in st.players[obj.controller_id].commander_ids:
		var c: GameObject = st.objects.get(int(cid))
		if c != null and c.definition is CardDefinition:
			for col in (c.definition as CardDefinition).color_identity:
				colors[str(col)] = true
	return colors.size()


## "<a|another>|<N>|<what>" (or the older "<a|another>|<what>"): how many a cost needs.
func _spec_count(spec: String) -> int:
	var parts := spec.split("|")
	return maxi(1, int(parts[1])) if parts.size() == 3 and (parts[1] as String).is_valid_int() else 1


## "Tap two untapped artifacts you control": matching untapped permanents, cheapest first (the source may tap itself).
func _untapped_candidates(obj: GameObject, spec: String) -> Array:
	var out: Array = []
	for c in sacrifice_candidates(obj, spec):
		if not (c as GameObject).tapped:
			out.append(c)
	return out


## "Untap a tapped creature you control": matching tapped permanents.
func _tapped_candidates(obj: GameObject, spec: String) -> Array:
	var out: Array = []
	for c in sacrifice_candidates(obj, spec):
		if (c as GameObject).tapped:
			out.append(c)
	return out
