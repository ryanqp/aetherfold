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


func is_mana() -> bool:
	return kind == &"MANA" and not unparsed


func is_activated() -> bool:
	return kind == &"ACTIVATED" and not unparsed


func has_tap_cost() -> bool:
	for c in costs:
		if c is AbilityCost and (c as AbilityCost).kind == &"TAP":
			return true
	return false
