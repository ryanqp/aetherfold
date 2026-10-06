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
## Filled by LayerManager the first time the card is looked at: its static abilities sorted by what they change, so each
## characteristics lookup does not rescan every ability of every permanent. Never serialised.
var layer_cache: Dictionary = {}
## The other face of a double-faced card (transform, disturb, daybound, craft, MDFC back), or null.
var back_face: CardDefinition = null
## A split card's second half or an adventure / aftermath half, castable on its own; null if none.
var other_half: CardDefinition = null
var _kw: Dictionary = {}
var _kw_ready: bool = false


## Keyword abilities that carry costs or numbers, read from the Oracle text (see KeywordLines).
func kw() -> Dictionary:
	if not _kw_ready:
		_kw = KeywordLines.parse(self)
		_kw_ready = true
	return _kw


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
	## The second face (CR 709 split / adventure halves, CR 712 double-faced cards).
	var faces: Variant = row.get("faces", [])
	if faces is Array and (faces as Array).size() >= 2 and (faces as Array)[1] is Dictionary:
		var f1: Dictionary = (faces as Array)[1]
		var other := CardDefinition.new()
		other.oracle_id = d.oracle_id
		other.name = str(f1.get("name", d.name))
		other.mana_cost = str(f1.get("mana_cost", ""))
		other.cmc = ManaCost.parse(other.mana_cost).cmc()
		other.type_line = str(f1.get("type_line", ""))
		other.oracle_text = str(f1.get("oracle_text", ""))
		other.power = _str_or_empty(f1.get("power", ""))
		other.toughness = _str_or_empty(f1.get("toughness", ""))
		other.loyalty = _str_or_empty(f1.get("loyalty", ""))
		other.colors = _string_array(f1.get("colors", row.get("colors", [])))
		other.color_identity = d.color_identity.duplicate()
		other.commander_legal = d.commander_legal
		var layout := str(row.get("layout", ""))
		if layout in ["split", "adventure", "aftermath"]:
			d.other_half = other
		else:
			d.back_face = other
		## A split card's front half keeps its own name for casting; the whole card's name stays on `d`.
		var f0: Variant = (faces as Array)[0]
		if f0 is Dictionary and layout in ["split", "aftermath"] and str(d.oracle_text) == "":
			d.oracle_text = str((f0 as Dictionary).get("oracle_text", ""))
	return d


## A Saga's last chapter number (CR 714.2b): the highest chapter of its chapter abilities, 0 if none.
func saga_final_chapter() -> int:
	var best := 0
	for a in abilities:
		if a is Ability and str((a as Ability).trigger.get("on", "")) == "CHAPTER":
			for c in (a as Ability).trigger.get("chapters", []):
				best = maxi(best, int(c))
	return best


## A copy of the printed card (token copies: encore, eternalize, embalm). Abilities are shared, not re-read.
func copy_def() -> CardDefinition:
	var d := CardDefinition.new()
	d.oracle_id = oracle_id
	d.name = name
	d.mana_cost = mana_cost
	d.cmc = cmc
	d.type_line = type_line
	d.oracle_text = oracle_text
	d.power = power
	d.toughness = toughness
	d.loyalty = loyalty
	d.colors = colors.duplicate()
	d.color_identity = color_identity.duplicate()
	d.keywords = keywords.duplicate()
	d.commander_legal = commander_legal
	d.abilities = abilities.duplicate()
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
	if t.find("unless") >= 0 or t.find("if you don't") >= 0:
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
