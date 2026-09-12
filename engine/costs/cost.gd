class_name AbilityCost
extends Resource

## One cost on an ability. `{T}` is TAP; mana strings live on MANA / ADDITIONAL_MANA.

var kind: StringName = &"MANA"
var mana: String = ""
var from: StringName = &""
