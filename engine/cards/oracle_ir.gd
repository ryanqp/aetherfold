class_name OracleIr
extends RefCounted

## Reads plain Oracle text into IR for simple instants and sorceries, so cards with no hand-written
## `engine/cards/ir/*.json` still do something. Hand-written IR always wins (see CardDatabase).
##
## All-or-nothing: every sentence on the card must match a known pattern, otherwise this returns []
## and the card behaves as before. A card that is half understood would be worse than one that is
## clearly not implemented yet. Patterns are listed in docs/adding-a-card.md.

const NUMBER_WORDS := {
	"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
	"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
}

## Permanent types a spell can name after "target", mapped to a targeting query.
const PERMANENT_QUERIES := {
	"creature": {"type": "creature"},
	"artifact": {"type": "artifact"},
	"enchantment": {"type": "enchantment"},
	"land": {"type": "land"},
	"nonland permanent": {"not_type": "land"},
	"permanent": {},
}

const KEYWORDS := [
	"flying", "first strike", "double strike", "deathtouch", "haste", "hexproof", "indestructible",
	"lifelink", "menace", "reach", "trample", "vigilance",
]

var _targets: Array = []
var _effects: Array = []


static func translate(def: CardDefinition) -> Array:
	if def == null or not _applies(def):
		return []
	var reader := OracleIr.new()
	var ability := reader._read(def)
	if ability.is_empty():
		return []
	var loader := IrLoader.new()
	var abilities := loader.from_dict({"abilities": [ability]})
	if not loader.errors.is_empty():
		return []
	return abilities


## Only spells that are cast and then resolve once. Permanents need triggers and static abilities.
static func _applies(def: CardDefinition) -> bool:
	if def.is_land() or def.is_creature():
		return false
	return def.type_line.contains("Instant") or def.type_line.contains("Sorcery")


func _read(def: CardDefinition) -> Dictionary:
	var text := def.oracle_text.replace("\r", "")
	var paren := RegEx.create_from_string("\\([^)]*\\)")
	text = paren.sub(text, "", true)
	if def.name != "":
		text = text.replace(def.name, "~")
	if def.mana_cost.contains("{X}"):
		return {}
	var any := false
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		if line == "":
			continue
		for sentence in line.split(". "):
			var s := str(sentence).strip_edges().trim_suffix(".").strip_edges()
			if s == "":
				continue
			if not _sentence(s):
				return {}
			any = true
	if not any or _effects.is_empty():
		return {}
	var costs: Array = []
	if def.mana_cost != "":
		costs.append({"kind": "MANA", "mana": def.mana_cost})
	return {
		"ability_id": "%s_spell" % _snake(def.name),
		"kind": "SPELL",
		"costs": costs,
		"targets": _targets,
		"effects": _effects,
		"text": def.oracle_text,
	}


## Returns true when the sentence was understood and its effects were queued.
func _sentence(s: String) -> bool:
	var m: RegExMatch

	# CR 120.3: "~ deals N damage to any target / target creature / target player."
	m = _match("^~ deals (\\d+) damage to (any target|target creature|target player)$", s)
	if m != null:
		var kinds := {"any target": "ANY_TARGET", "target creature": "PERMANENT", "target player": "PLAYER"}
		var kind: String = kinds[m.get_string(2).to_lower()]
		var query: Dictionary = {"type": "creature"} if kind == "PERMANENT" else {}
		if not _add_target(kind, query):
			return false
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(1)), "target": 0}})
		return true

	# CR 701.7: destroy.
	m = _match("^destroy target (nonland permanent|permanent|creature|artifact|enchantment|land)( you don't control)?$", s)
	if m != null:
		if not _add_permanent(m.get_string(1), m.get_string(2) != ""):
			return false
		_effects.append({"kind": "DESTROY", "params": {"target": 0}})
		return true

	# CR 701.13: exile.
	m = _match("^exile target (nonland permanent|permanent|creature|artifact|enchantment|land)( you don't control)?$", s)
	if m != null:
		if not _add_permanent(m.get_string(1), m.get_string(2) != ""):
			return false
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": 0, "to": "EXILE"}})
		return true

	# Bounce.
	m = _match("^return target (nonland permanent|permanent|creature|artifact|enchantment|land)( you don't control)? to its owner's hand$", s)
	if m != null:
		if not _add_permanent(m.get_string(1), m.get_string(2) != ""):
			return false
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": 0, "to": "HAND"}})
		return true

	# CR 121: draw.
	m = _match("^draw (a|an|one|two|three|four|five) cards?$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": int(NUMBER_WORDS[m.get_string(1).to_lower()])}})
		return true

	# CR 119.3: gain life.
	m = _match("^you gain (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^target player gains (\\d+) life$", s)
	if m != null:
		if not _add_target("PLAYER", {}):
			return false
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": int(m.get_string(1)), "target": 0}})
		return true

	# CR 611.2: "Target creature gets +X/+Y [and gains <keyword>] until end of turn."
	m = _match("^target creature gets ([+-]\\d+)/([+-]\\d+)(?: and gains ([a-z ]+))? until end of turn$", s)
	if m != null:
		var kws: Array = []
		if m.get_string(3) != "":
			kws = _keywords(m.get_string(3))
			if kws.is_empty():
				return false
		if not _add_target("PERMANENT", {"type": "creature"}):
			return false
		_effects.append({"kind": "PUMP", "params": {
			"target": 0, "power": int(m.get_string(1)), "toughness": int(m.get_string(2)),
			"keywords": kws, "duration": "END_OF_TURN",
		}})
		return true
	m = _match("^target creature gains ([a-z ]+) until end of turn$", s)
	if m != null:
		var gained := _keywords(m.get_string(1))
		if gained.is_empty() or not _add_target("PERMANENT", {"type": "creature"}):
			return false
		_effects.append({"kind": "PUMP", "params": {"target": 0, "keywords": gained, "duration": "END_OF_TURN"}})
		return true

	# CR 701.5: counter.
	m = _match("^counter target spell$", s)
	if m != null:
		if not _add_target("SPELL_ON_STACK", {}):
			return false
		_effects.append({"kind": "COUNTER_SPELL", "params": {"target": 0}})
		return true

	return false


func _add_permanent(type_name: String, opponents_only: bool) -> bool:
	var query: Dictionary = (PERMANENT_QUERIES[type_name.to_lower()] as Dictionary).duplicate()
	if opponents_only:
		query["controller"] = "OPPONENT"
	return _add_target("PERMANENT", query)


## One target per card for now: the cast flow asks for a single target.
func _add_target(kind: String, query: Dictionary) -> bool:
	if not _targets.is_empty():
		return false
	var slot := {"id": 0, "kind": kind, "count": 1}
	if not query.is_empty():
		slot["query"] = query
	_targets.append(slot)
	return true


## "flying and first strike" -> ["Flying", "First strike"]. Empty if any word is unknown.
func _keywords(list_text: String) -> Array:
	var out: Array = []
	for part in list_text.replace(", and ", ",").replace(" and ", ",").split(","):
		var kw := str(part).strip_edges().to_lower()
		if not kw in KEYWORDS:
			return []
		out.append(kw.substr(0, 1).to_upper() + kw.substr(1))
	return out


static func _match(pattern: String, s: String) -> RegExMatch:
	var re := RegEx.create_from_string("(?i)" + pattern)
	return re.search(s)


static func _snake(card_name: String) -> String:
	var re := RegEx.create_from_string("[^a-z0-9]+")
	return re.sub(card_name.to_lower(), "_", true).trim_prefix("_").trim_suffix("_")
