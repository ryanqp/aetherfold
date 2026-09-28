class_name CardDefinition
extends Resource

## Printed characteristics. No art, Color, or scryfall image fields.

var oracle_id: String = ""
var name: String = ""
var mana_cost: String = ""
var cmc: int = 0
var type_line: String = ""
var oracle_text: String = ""
var power: String = ""
var toughness: String = ""
var loyalty: String = ""
var colors: PackedStringArray = PackedStringArray()
var color_identity: PackedStringArray = PackedStringArray()
var keywords: PackedStringArray = PackedStringArray()
var unimplemented_keywords: PackedStringArray = PackedStringArray()
var commander_legal: bool = true
var abilities: Array = []


static func from_catalog_row(row: Dictionary) -> CardDefinition:
	var d := CardDefinition.new()
	d.oracle_id = str(row.get("oracle_id", ""))
	d.name = str(row.get("name", ""))
	d.mana_cost = str(row.get("mana_cost", ""))
	d.cmc = int(row.get("cmc", 0))
	d.type_line = str(row.get("type_line", ""))
	d.oracle_text = str(row.get("oracle_text", ""))
	d.power = _str_or_empty(row.get("power", ""))
	d.toughness = _str_or_empty(row.get("toughness", ""))
	d.loyalty = _str_or_empty(row.get("loyalty", ""))
	d.colors = _string_array(row.get("colors", []))
	d.color_identity = _string_array(row.get("color_identity", []))
	d.keywords = _string_array(row.get("keywords", []))
	d.commander_legal = bool(row.get("commander_legal", true))
	return d


func is_land() -> bool:
	return type_line.contains("Land")


func is_creature() -> bool:
	return type_line.contains("Creature")


func is_basic_land() -> bool:
	return type_line.begins_with("Basic Land")


func enters_tapped() -> bool:
	var t := oracle_text.to_lower().replace("\n", " ")
	if t.find("enters the battlefield tapped") < 0 and t.find("enters tapped") < 0:
		return false
	if t.find("unless") >= 0:
		return false
	return true


func is_instant() -> bool:
	return type_line.contains("Instant")


func is_sorcery() -> bool:
	return type_line.contains("Sorcery")


func is_permanent_type() -> bool:
	return (
		is_creature()
		or is_land()
		or type_line.contains("Artifact")
		or type_line.contains("Enchantment")
		or type_line.contains("Planeswalker")
	)


func spell_ability() -> Ability:
	var spells := parsed_spell_abilities()
	if spells.is_empty():
		return null
	return spells[0]


func parsed_spell_abilities() -> Array:
	var out: Array = []
	for a in abilities:
		if a is Ability and (a as Ability).kind == &"SPELL" and not (a as Ability).unparsed:
			out.append(a)
	return out


## True when any parsed ability has an effect of this kind (COUNTER_SPELL, DRAW, ...).
func has_effect(effect_kind: StringName) -> bool:
	for a in abilities:
		if not (a is Ability) or (a as Ability).unparsed:
			continue
		for e in (a as Ability).effects:
			if e is AbilityEffect and (e as AbilityEffect).kind == effect_kind:
				return true
	return false


func spell_effect_param(effect_kind: StringName, param: String, fallback: Variant = null) -> Variant:
	for a in parsed_spell_abilities():
		for e in (a as Ability).effects:
			if e is AbilityEffect and (e as AbilityEffect).kind == effect_kind:
				return (e as AbilityEffect).params.get(param, fallback)
	return fallback


## A parsed spell target whose query requires a creature (Unsummon). Any-target burn is not this.
func spell_requires_creature_target() -> bool:
	for a in parsed_spell_abilities():
		for t in (a as Ability).targets:
			if not (t is Dictionary):
				continue
			var query: Variant = (t as Dictionary).get("query", {})
			if query is Dictionary and str((query as Dictionary).get("type", "")) == "creature":
				return true
	return false


func spell_moves_target_to_hand() -> bool:
	for a in parsed_spell_abilities():
		for e in (a as Ability).effects:
			if e is AbilityEffect and (e as AbilityEffect).kind == &"MOVE_ZONE":
				if str((e as AbilityEffect).params.get("to", "")) == "HAND":
					return true
	return false


func find_ability(p_ability_id: StringName) -> Ability:
	for a in abilities:
		if a is Ability and (a as Ability).ability_id == p_ability_id:
			return a
	return null


func mana_abilities() -> Array:
	var out: Array = []
	for a in abilities:
		if a is Ability and (a as Ability).is_mana():
			out.append(a)
	return out


static func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


static func _string_array(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is PackedStringArray:
		return v
	if v is Array:
		for item in v:
			out.append(str(item))
	return out
