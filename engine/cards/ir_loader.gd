class_name IrLoader
extends RefCounted

const ABILITY_KEYS := ["ability_id", "kind", "costs", "targets", "effects", "trigger", "replacement", "restrictions", "text", "unparsed", "granted", "static"]
const COST_KEYS := ["kind", "mana", "from"]
const EFFECT_KEYS := ["kind", "params"]
const EFFECT_PARAM_KEYS := {
	"DRAW": ["n", "if_link", "who"],
	"CREATE_TOKEN": ["token", "count", "spec", "tapped", "for", "pt_x"],
	"COUNTER_SPELL": ["target"],
	"MOVE_ZONE": ["target", "to"],
	"ADD_MANA": ["mana"],
	"TAP": ["target"],
	"UNTAP": ["target"],
	"DEAL_DAMAGE": ["n", "target", "who", "trigger_object", "from_trigger_object"],
	"LOSE_LIFE": ["n", "target", "who"],
	"CREATE_CONTINUOUS_EFFECT": ["layer", "mod", "duration", "query"],
	"SCRY": ["n"],
	"LOOK": ["n"],
	"SHUFFLE": ["n"],
	"SET_CHARACTERISTICS": ["if_subtype", "subtypes", "power", "toughness", "keywords", "gain_abilities", "duration"],
	"EXILE_TOP": ["n", "who", "may_play"],
	"MAY": ["link", "prompt"],
	"CHOOSE": ["choice", "link", "options", "optional", "prompt"],
	"PUT_COUNTER": ["name", "n", "target", "self", "each", "trigger_object"],
	"GAIN_LIFE": ["n", "target", "who"],
	"DESTROY": ["target"],
	"PUMP": ["target", "power", "toughness", "keywords", "duration", "self", "each", "trigger_object"],
	"DEAL_DAMAGE_EACH": ["n", "query"],
	"SEARCH_LIBRARY": ["filter", "n", "to", "tapped", "for", "same_type"],
	"UNTAP_EACH": ["query"],
	"DESTROY_ALL": ["query"],
	"FIGHT": ["a", "b", "one_sided"],
	"ATTACH": ["target"],
	"CHOOSE_TYPE": ["auto"],
	"RETURN_FROM_GRAVEYARD": ["target", "to", "finality"],
	"EXILE_UNTIL_LEAVES": ["target"],
	"DISCOVER": ["n"],
	"HIDEAWAY": ["n"],
	"PLAY_HIDDEN": ["min_total_power"],
	"MILL": ["n", "who", "target"],
	"DISCARD": ["n", "who", "target"],
	"SURVEIL": ["n"],
	"SACRIFICE": ["n", "who", "type"],
	"PROLIFERATE": [],
	"EXPLORE": [],
	"AMASS": ["n"],
	"BOLSTER": ["n"],
	"POPULATE": [],
	"FABRICATE": ["n"],
	"CASCADE": [],
	"RETURN_SELF": ["name"],
	"BECOME_MONARCH": [],
	"CHOOSE_COLOR": ["not"],
	"ECHO": ["cost"],
	"COUNTDOWN": ["counter", "mode"],
	"CUMULATIVE_UPKEEP": ["cost", "life"],
	"EXTORT": [],
	"ENLIST": [],
	"FLANKING": [],
	"RAMPAGE": ["n"],
	"WARD": ["cost", "life", "target_stack_id"],
	"MADNESS": ["object_id"],
	"MIRACLE": ["object_id"],
	"ADAPT": ["n"],
	"CONNIVE": ["n", "target", "self"],
	"LEARN": [],
	"INCUBATE": ["n"],
	"SUPPORT": ["n"],
	"MANIFEST": ["n", "cloak"],
	"SUSPECT": ["target", "self"],
	"GOAD": ["target"],
	"FATESEAL": ["n"],
	"INCUBATOR_FLIP": [],
	"MODAL": ["choose", "repeat", "both_if_commander", "any_up_to", "modes"],
	"POWER_DAMAGE_EACH": ["source"],
	"CAST_FREE_FROM_HAND": ["max_mv"],
	"PAY_OPTIONAL": ["cost", "link"],
	"GRANT_FLASH": [],
	"GAIN_KEYWORD_CHOICE": ["options"],
	"BECOME_COPY": ["target"],
	"EXILE_CARD": ["target"],
	"GRAVEYARD_EXILED_WITH": [],
	"REVEAL_TOP_CAST_FREE": [],
	"EXILE_TOP_EACH_CAST_FREE": [],
	"RIOT": [],
	"AURA_ATTACH": ["target", "helpful"],
	"LIVING_WEAPON": [],
	"BEHOLD": ["subtype", "link"],
	"CLASH": [],
	"EMPOWER": ["name", "n"],
	"DOUBLE_PT": ["each"],
	"HAND_TO_LIBRARY": ["n", "where"],
	"REVEAL_UNTIL_PUT": ["types", "to"],
	"FLICKER": ["target"],
	"DESTROY_ALL_POWER": ["min"],
	"EMBLEM": ["power", "toughness", "keywords"],
	"RETURN_CARD_CHOICE": ["type", "to"],
	"SACRIFICE_GREATEST": ["target"],
	"PUT_FROM_HAND_ATTACKING": ["subtype"],
	"RETURN_SELF_HAND": [],
	"EXILE_ALL": ["query"],
	"DEMONSTRATE": [],
	"READ_AHEAD": ["final"],
	"GIFT": ["kind"],
	"SELF_EXILE_ON_RESOLVE": [],
	"DISCARD_ANY_DRAW": [],
	"TAP_ATTACHED": [],
	"TUCK": ["target"],
	"BOUNCE_ANY": ["target"],
	"MOVE_COUNTERS": ["target", "name"],
	"GRAFT_MOVE": [],
	"POISON": ["n"],
	"MENTOR": [],
	"MOBILIZE": ["n"],
	"FIREBEND": ["n"],
	"INCREMENT": [],
	"EXPLOIT": [],
	"BACKUP": ["target", "n"],
	"MARK": ["self", "mark"],
	"PROVOKE": ["target"],
	"AS_ENTERS": ["what", "n"],
	"CHAMPION": ["type"],
	"STORM": ["grave"],
	"RIPPLE": ["n"],
	"SOULBOND": [],
	"EQUIP_TOKEN": ["spec"],
	"TRIPLE_PT": ["target", "each", "power", "toughness"],
	"EXCHANGE_CONTROL": ["a", "b"],
	"EXCHANGE_LIFE": ["target"],
	"REGENERATE": ["target", "self", "each"],
	"TRANSFORM": ["target", "self", "each"],
	"DETAIN": ["target", "self", "each"],
	"MONSTROSITY": ["n"],
	"VOTE": ["options"],
	"EXERT": [],
	"VENTURE": ["dungeon"],
	"TAKE_INITIATIVE": [],
	"RING_TEMPTS": [],
	"VILLAINOUS_CHOICE": ["a", "b", "a_text", "b_text"],
	"TIME_TRAVEL": [],
	"FORAGE": [],
	"MANIFEST_DREAD": [],
	"ENDURE": ["n"],
	"HARNESS": [],
	"AIRBEND": ["target", "self", "each"],
	"EARTHBEND": ["target", "n"],
	"BLIGHT": ["n"],
	"HEAL": ["target", "self", "each"],
	"RECRUIT": [],
	"COPY_SPELL_N": ["n"],
	"EPIC": [],
	"CIPHER": [],
	"HAUNT": [],
	"MELD": ["partner", "into"],
	"SECTOR_PICK": ["act"],
	"PARADIGM_COPY": ["object_id"],
	"BLITZ_DRAW": [],
	"SAC_SELF": [],
	"AWAKEN": ["n"],
	"OFFSPRING_COPY": [],
	"SQUAD_COPIES": ["n"],
	"COUNTERS_X": [],
}
## Gates any effect may carry: only run if the spell was kicked / an opponent was dealt damage this turn.
const GATE_KEYS := ["if_kicked", "if_opp_damaged", "if_cast", "if_cast_from_hand", "if_link", "if_exiled_creature", "if_exiled_noncreature", "if_trigger_subtype", "if_gift", "if_defender_most_life"]
const ABILITY_KINDS := ["SPELL", "ACTIVATED", "TRIGGERED", "STATIC", "REPLACEMENT", "MANA"]
const COST_KINDS := ["MANA", "TAP", "UNTAP", "ADDITIONAL_MANA", "SACRIFICE_SELF", "LOYALTY", "PAY_LIFE", "ADD_COUNTER"]

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
	a.granted = bool(d.get("granted", false))
	var trigger: Variant = d.get("trigger", {})
	a.trigger = trigger if trigger is Dictionary else {}
	var replacement: Variant = d.get("replacement", {})
	a.replacement = replacement if replacement is Dictionary else {}
	var targets: Variant = d.get("targets", [])
	a.targets = targets if targets is Array else []
	var static_raw: Variant = d.get("static", {})
	a.static_spec = static_raw if static_raw is Dictionary else {}
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
		if not str(k) in allowed and not str(k) in GATE_KEYS:
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
