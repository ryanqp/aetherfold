class_name LayerManager
extends RefCounted

func snapshot(state: GameState, obj: GameObject) -> Dictionary:
	var printed_p := 0
	var printed_t := 0
	if obj != null and obj.definition is CardDefinition:
		var def := obj.definition as CardDefinition
		printed_p = int(def.power) if def.power.is_valid_int() else 0
		printed_t = int(def.toughness) if def.toughness.is_valid_int() else 0
	var power := printed_p
	var toughness := printed_t
	for e in state.effects:
		if not (e is ContinuousEffect):
			continue
		var fx := e as ContinuousEffect
		power += fx.power
		toughness += fx.toughness
	return {
		power = power,
		toughness = toughness,
		printed_power = printed_p,
		printed_toughness = printed_t,
	}


func power(state: GameState, obj: GameObject) -> int:
	return int(snapshot(state, obj).get("power", 0))


func clear_until_eot(state: GameState) -> void:
	var kept: Array = []
	for e in state.effects:
		if e is ContinuousEffect and (e as ContinuousEffect).until_eot:
			continue
		kept.append(e)
	state.effects = kept
