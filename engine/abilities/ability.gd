class_name Ability
extends Resource

var ability_id: StringName = &""
var kind: StringName = &"SPELL"
var costs: Array = []
var targets: Array = []
var effects: Array = []
var trigger: Dictionary = {}
var replacement: Dictionary = {}
var restrictions: Array = []
var text: String = ""
var unparsed: bool = false
## Printed on the card but not active until a continuous effect grants it (CR 113.3d / 611.2c).
var granted: bool = false


func is_mana() -> bool:
	return kind == &"MANA" and not unparsed


func is_activated() -> bool:
	return kind == &"ACTIVATED" and not unparsed


func has_tap_cost() -> bool:
	return _has_cost(&"TAP")


func has_untap_cost() -> bool:
	return _has_cost(&"UNTAP")


## CR 302.6: summoning sickness stops {T} and {Q} in the activation cost, not the ability as a whole.
func uses_tap_symbol_cost() -> bool:
	return has_tap_cost() or has_untap_cost()


func _has_cost(kind: StringName) -> bool:
	for c in costs:
		if c is AbilityCost and (c as AbilityCost).kind == kind:
			return true
	return false
