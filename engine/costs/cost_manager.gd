class_name CostManager
extends RefCounted

func can_pay(obj: GameObject, ability: Ability) -> bool:
	if obj == null or ability == null:
		return false
	for c in ability.costs:
		if not (c is AbilityCost):
			return false
		var cost := c as AbilityCost
		if cost.kind == &"TAP" and obj.tapped:
			return false
	return true


func pay(obj: GameObject, ability: Ability) -> bool:
	if not can_pay(obj, ability):
		return false
	for c in ability.costs:
		var cost := c as AbilityCost
		if cost.kind == &"TAP":
			obj.tapped = true
	return true
