class_name CostManager
extends RefCounted

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
	return true
