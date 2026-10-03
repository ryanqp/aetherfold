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
		if cost.kind == &"SACRIFICE" and sacrifice_candidates(obj, str(cost.mana)).is_empty():
			return false
		## CR 606.6: a loyalty cost can't remove more loyalty counters than the planeswalker has.
		if cost.kind == &"LOYALTY" and int(obj.counters.get("loyalty", 0)) + int(cost.mana) < 0:
			return false
		## CR 119.4: a player can pay life only if their life total is at least that much.
		if cost.kind == &"PAY_LIFE":
			var st := _state()
			if st == null or obj.controller_id < 0 or obj.controller_id >= st.players.size() or st.players[obj.controller_id].life < int(cost.mana):
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
				st.players[obj.controller_id].life -= int(cost.mana)
				st.log.append(EngineEnums.EventType.LIFE_CHANGE, obj.controller_id, {to_player = obj.controller_id, amount = int(cost.mana)})
		elif cost.kind == &"ADD_COUNTER":
			obj.counters[cost.mana] = int(obj.counters.get(cost.mana, 0)) + 1
		elif cost.kind == &"SACRIFICE":
			var pick := sacrifice_candidates(obj, str(cost.mana))
			var st2 := _state()
			if not pick.is_empty() and st2 != null:
				var victim: GameObject = pick[0]
				st2.zones.move(victim.object_id, EngineEnums.ZoneId.GRAVEYARD, victim.owner_id)
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
	for oid in bf.object_ids:
		var o: GameObject = st.objects.get(oid)
		if o == null or o.controller_id != obj.controller_id or not (o.definition is CardDefinition):
			continue
		if other and o.object_id == obj.object_id:
			continue
		var tl := (o.definition as CardDefinition).type_line
		var hit := false
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
