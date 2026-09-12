class_name IrLoader
extends RefCounted

const ABILITY_KEYS := ["ability_id", "kind", "costs", "targets", "effects", "trigger", "replacement", "restrictions", "text", "unparsed"]
const COST_KEYS := ["kind", "mana", "from"]
const EFFECT_KEYS := ["kind", "params"]
const EFFECT_PARAM_KEYS := {
	"DRAW": ["n"],
	"CREATE_TOKEN": ["token", "count"],
	"COUNTER_SPELL": ["target"],
	"MOVE_ZONE": ["target", "to"],
	"ADD_MANA": ["mana"],
	"TAP": ["target"],
	"UNTAP": ["target"],
	"DEAL_DAMAGE": ["n", "target"],
	"CREATE_CONTINUOUS_EFFECT": ["layer", "mod", "duration", "query"],
	"SCRY": ["n"],
	"LOOK": ["n"],
	"SHUFFLE": ["n"],
}
const ABILITY_KINDS := ["SPELL", "ACTIVATED", "TRIGGERED", "STATIC", "REPLACEMENT", "MANA"]
const COST_KINDS := ["MANA", "TAP", "ADDITIONAL_MANA"]

var errors: PackedStringArray = PackedStringArray()


func from_dict(data: Dictionary) -> Array:
	return _abilities_from(data)


func load_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		errors.append("missing file: %s" % path)
		return []
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		errors.append("invalid json: %s" % path)
		return []
	return _abilities_from(parsed)


func load_dir(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		errors.append("IrLoader.load_dir: cannot open %s" % dir_path)
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.ends_with(".json") and not dir.current_is_dir():
			var path := dir_path.path_join(file_name)
			var txt := FileAccess.get_file_as_string(path)
			var parsed: Variant = JSON.parse_string(txt)
			if not (parsed is Dictionary):
				errors.append("invalid json: %s" % path)
			else:
				var abs: Array = _abilities_from(parsed)
				var key := str(parsed.get("oracle_id", ""))
				if key.is_empty():
					key = str(parsed.get("name", "")).strip_edges().to_lower()
				if key != "":
					out[key] = abs
		file_name = dir.get_next()
	return out


func _abilities_from(data: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = data.get("abilities", [])
	if not (raw is Array):
		errors.append("abilities must be an array (%s)" % str(data.get("name", "")))
		return out
	for item in raw:
		if not (item is Dictionary):
			errors.append("ability is not an object")
			continue
		var ab := _ability_from(item)
		if ab != null:
			out.append(ab)
	return out


func _ability_from(d: Dictionary) -> Ability:
	if not _keys_ok(d, ABILITY_KEYS, "ability"):
		return null
	var kind := str(d.get("kind", ""))
	if not kind in ABILITY_KINDS:
		errors.append("unknown ability kind: %s" % kind)
		return null
	var a := Ability.new()
	a.ability_id = StringName(str(d.get("ability_id", "")))
	a.kind = StringName(kind)
	a.text = str(d.get("text", ""))
	a.unparsed = bool(d.get("unparsed", false))
	var trigger: Variant = d.get("trigger", {})
	a.trigger = trigger if trigger is Dictionary else {}
	var replacement: Variant = d.get("replacement", {})
	a.replacement = replacement if replacement is Dictionary else {}
	var targets: Variant = d.get("targets", [])
	a.targets = targets if targets is Array else []
	var restrictions: Variant = d.get("restrictions", [])
	a.restrictions = restrictions if restrictions is Array else []
	var costs: Variant = d.get("costs", [])
	if costs is Array:
		for c in costs:
			if not (c is Dictionary):
				errors.append("cost is not an object")
				return null
			var cost := _cost_from(c)
			if cost == null:
				return null
			a.costs.append(cost)
	var effects: Variant = d.get("effects", [])
	if effects is Array:
		for e in effects:
			if not (e is Dictionary):
				errors.append("effect is not an object")
				return null
			var fx := _effect_from(e)
			if fx == null:
				return null
			a.effects.append(fx)
	return a


func _cost_from(d: Dictionary) -> AbilityCost:
	if not _keys_ok(d, COST_KEYS, "cost"):
		return null
	var kind := str(d.get("kind", ""))
	if not kind in COST_KINDS:
		errors.append("unknown cost kind: %s" % kind)
		return null
	var c := AbilityCost.new()
	c.kind = StringName(kind)
	c.mana = str(d.get("mana", ""))
	c.from = StringName(str(d.get("from", "")))
	return c


func _effect_from(d: Dictionary) -> AbilityEffect:
	if not _keys_ok(d, EFFECT_KEYS, "effect"):
		return null
	var kind := str(d.get("kind", ""))
	if not EFFECT_PARAM_KEYS.has(kind):
		errors.append("unknown effect kind: %s" % kind)
		return null
	var params: Variant = d.get("params", {})
	if params == null:
		params = {}
	if not (params is Dictionary):
		errors.append("effect params must be an object (%s)" % kind)
		return null
	var allowed: Array = EFFECT_PARAM_KEYS[kind]
	for k in (params as Dictionary).keys():
		if not str(k) in allowed:
			errors.append("unknown param '%s' on %s" % [str(k), kind])
			return null
	var fx := AbilityEffect.new()
	fx.kind = StringName(kind)
	fx.params = params
	return fx


func _keys_ok(d: Dictionary, allowed: Array, label: String) -> bool:
	for k in d.keys():
		if not str(k) in allowed:
			errors.append("unknown %s key: %s" % [label, str(k)])
			return false
	return true
