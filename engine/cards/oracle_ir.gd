class_name OracleIr
extends RefCounted

## Reads plain Oracle text into IR, so cards with no hand-written `engine/cards/ir/*.json` still do
## something. Hand-written IR always wins (see CardDatabase).
##
## Instants and sorceries are all-or-nothing: every sentence must match a known pattern, otherwise
## this returns [] and the card behaves as before (a half understood spell would be worse than one
## that is clearly not implemented yet). On permanents each line stands alone: a line that isn't
## understood is skipped and the card keeps its other abilities. Patterns are listed in
## docs/adding-a-card.md.
##
## What it reads: mana abilities, Equip, activated abilities, triggered abilities ("When ~ enters",
## "Whenever ~ attacks", "When ~ dies", "At the beginning of your upkeep", "Whenever you cast ...",
## landfall, enrage, ...), static abilities ("Creatures you control get +1/+1", "Equipped creature
## gets ...", cost reductions) and the effects those use (damage, destroy, exile, bounce, draw, life,
## tokens, counters, pump, search your library, scry, fights, return from graveyard, untap, ...).

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

## "Enrage — ...", "Landfall — ...": the word only labels the ability that follows.
const ABILITY_WORDS := [
	"landfall", "enrage", "constellation", "heroic", "raid", "revolt", "morbid", "undergrowth",
	"delirium", "metalcraft", "threshold", "magecraft", "alliance", "eerie", "survival", "valiant",
	"fateful hour", "formidable", "ferocious", "hellbent", "spell mastery", "kinship", "radiance",
	"rally", "inspired", "lieutenant", "tempting offer", "council's dilemma", "will of the council",
]

const COLOR_LETTERS := {
	"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G",
}

var _targets: Array = []
var _effects: Array = []
## Extra abilities a spell comes with (its own cost discount).
var _extra: Array = []
## Set while reading a trigger on "this creature": a leading "it" means the creature itself.
var _self_it: bool = false


# --- Entry points ------------------------------------------------------------------------

static func translate(def: CardDefinition) -> Array:
	if def == null or not _applies(def):
		return []
	var reader := OracleIr.new()
	var ability := reader._read(def)
	if ability.is_empty():
		return []
	var loader := IrLoader.new()
	var all: Array = [ability]
	all.append_array(reader._extra)
	var abilities := loader.from_dict({"abilities": all})
	if not loader.errors.is_empty():
		return []
	return abilities


## Abilities on permanents. Each line is read on its own; a line that isn't understood is skipped.
## A line of several sentences that doesn't read whole is read one sentence at a time.
static func translate_permanent(def: CardDefinition) -> Array:
	if def == null or _applies(def):
		return []
	var out: Array = []
	var n := 0
	for raw in normalize(def).split("\n"):
		var line := strip_ability_word(str(raw).strip_edges())
		if line == "":
			continue
		var found: Array = _read_whole_or_by_sentence(def, line)
		for item in found:
			var d: Dictionary = item
			n += 1
			d["ability_id"] = "%s_%s%d" % [_snake(def.name), str(d.get("kind", "x")).to_lower(), n]
			d["text"] = line
			var loader := IrLoader.new()
			var parsed := loader.from_dict({"abilities": [d]})
			if loader.errors.is_empty():
				out.append_array(parsed)
	return out


static func _read_whole_or_by_sentence(def: CardDefinition, line: String) -> Array:
	var found := _read_clean(def, line)
	if not found.is_empty() or not line.contains(". "):
		return found
	for part in line.split(". "):
		found.append_array(_read_clean(def, str(part)))
	return found


## Drops the sentences that only add a condition or a discount we handle apart, trims the final period, reads the line.
static func _read_clean(def: CardDefinition, line: String) -> Array:
	var text := line.strip_edges()
	var restrictions: Array = []
	var once := false
	var re_cost := RegEx.create_from_string("(?i)\\.?\\s*this ability costs \\{[^}]+\\} less to activate[^.]*\\.?")
	text = re_cost.sub(text, "", true)
	var re_city := RegEx.create_from_string("(?i)\\.?\\s*activate only if you have the city's blessing\\.?")
	if re_city.search(text) != null:
		restrictions.append("CITYS_BLESSING")
		text = re_city.sub(text, "", true)
	var re_once := RegEx.create_from_string("(?i)\\.?\\s*do this only once each turn\\.?")
	if re_once.search(text) != null:
		once = true
		text = re_once.sub(text, "", true)
	text = text.strip_edges().trim_suffix(".").strip_edges()
	if text == "":
		return []
	var out: Array = OracleIr.new()._read_line(def, text)
	for item in out:
		var d: Dictionary = item
		if not restrictions.is_empty():
			var r: Array = d.get("restrictions", [])
			r.append_array(restrictions)
			d["restrictions"] = r
		if once and d.has("trigger"):
			(d["trigger"] as Dictionary)["once_per_turn"] = true
	return out


## Oracle text with reminder text removed and the card's own name (and "this creature") as "~".
static func normalize(def: CardDefinition) -> String:
	var text := def.oracle_text.replace("\r", "").replace("’", "'")
	text = RegEx.create_from_string("\\([^)]*\\)").sub(text, "", true)
	if def.name != "":
		text = text.replace(def.name, "~")
		var front := def.name.split(" // ")[0]
		if front != def.name:
			text = text.replace(front, "~")
		if front.contains(", "):
			var short := front.split(", ")[0]
			if short.length() >= 3:
				text = text.replace(short, "~")
	text = RegEx.create_from_string("(?i)\\bthis (creature|artifact|enchantment|land|permanent|equipment|aura|vehicle|saga|spell|card|token)\\b").sub(text, "~", true)
	return text


static func strip_ability_word(line: String) -> String:
	var low := line.to_lower()
	for w in ABILITY_WORDS:
		if low.begins_with(str(w) + " — "):
			return line.substr(str(w).length() + 3).strip_edges()
	return line


# --- Lines on permanents -------------------------------------------------------------------

## One Oracle line -> zero or more IR ability dictionaries (no ability_id or text yet).
func _read_line(def: CardDefinition, line: String) -> Array:
	var m: RegExMatch

	# CR 605.1a: "{T}: Add ..." is a mana ability (no stack, no targets).
	m = _match("^\\{T\\}: add (.+)$", line)
	if m != null:
		var produced := _mana_text(m.get_string(1))
		if produced != "":
			return [{
				"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": produced}}], "restrictions": [],
			}]
		return []

	# CR 702.6: Equip {N}.
	m = _match("^equip (\\{[0-9WUBRGC]+\\}(?:\\{[0-9WUBRGC]+\\})*)\\.?$", line)
	if m != null:
		return [{
			"kind": "ACTIVATED",
			"costs": [{"kind": "MANA", "mana": m.get_string(1)}],
			"targets": [{"id": 0, "kind": "PERMANENT", "count": 1, "query": {"type": "creature", "controller": "SOURCE_CONTROLLER"}}],
			"effects": [{"kind": "ATTACH", "params": {"target": 0}}],
			"restrictions": ["SORCERY_SPEED"],
		}]

	# CR 702.108: prowess.
	if _match("^prowess$", line) != null:
		return [{
			"kind": "TRIGGERED",
			"trigger": {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "types": ["noncreature"]}},
			"costs": [], "targets": [],
			"effects": [{"kind": "PUMP", "params": {"self": true, "power": 1, "toughness": 1, "duration": "END_OF_TURN"}}],
			"restrictions": [],
		}]

	# Keyword abilities that are triggers (CR 702): exalted, battle cry, afterlife, annihilator, evolve,
	# undying, persist, renown, fabricate, cascade.
	var kt := _keyword_trigger(line)
	if not kt.is_empty():
		return [kt]

	var st := _static_line(line)
	if not st.is_empty():
		return [st]

	# Thriving lands: "As ~ enters, choose a color other than green." / "{T}: Add one mana of the chosen color."
	m = _match("^as ~ enters, choose a color other than (white|blue|black|red|green)$", line)
	if m != null:
		return [{
			"kind": "TRIGGERED", "trigger": {"on": "ENTERS_BATTLEFIELD"}, "costs": [], "targets": [],
			"effects": [{"kind": "CHOOSE_COLOR", "params": {"not": COLOR_LETTERS[m.get_string(1).to_lower()]}}], "restrictions": [],
		}]
	if _match("^\\{T\\}: add one mana of the chosen color$", line) != null:
		return [{
			"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
			"effects": [{"kind": "ADD_MANA", "params": {"mana": "{CHOSEN}"}}], "restrictions": [],
		}]

	# CR 702.75: Hideaway N.
	m = _match("^hideaway (\\d+)$", line)
	if m != null:
		return [{
			"kind": "TRIGGERED", "trigger": {"on": "ENTERS_BATTLEFIELD"}, "costs": [], "targets": [],
			"effects": [{"kind": "HIDEAWAY", "params": {"n": int(m.get_string(1))}}], "restrictions": [],
		}]

	# "As ~ enters, choose a creature type."
	m = _match("^as ~ enters, choose a creature type$", line)
	if m != null:
		return [{
			"kind": "TRIGGERED", "trigger": {"on": "ENTERS_BATTLEFIELD"}, "costs": [], "targets": [],
			"effects": [{"kind": "CHOOSE_TYPE", "params": {"auto": true}}], "restrictions": [],
		}]

	# "~ enters with two +1/+1 counters on it."
	m = _match("^~ enters with (a|an|one|two|three|four|five|\\d+) \\+1/\\+1 counters? on it$", line)
	if m != null:
		return [{
			"kind": "TRIGGERED", "trigger": {"on": "ENTERS_BATTLEFIELD"}, "costs": [], "targets": [],
			"effects": [{"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": _num(m.get_string(1)), "self": true}}],
			"restrictions": [],
		}]

	var trig := _trigger_line(line)
	if not trig.is_empty():
		return [trig]

	# Activated: "{1}, {T}: effect" or "Sacrifice ~: effect".
	m = _match("^((?:\\{[^}]+\\}|sacrifice ~|, )+): (.+)$", line)
	if m == null:
		return []
	var reader := OracleIr.new()
	var costs := reader._costs(m.get_string(1))
	if costs.is_empty() or not reader._read_effects(m.get_string(2)):
		return []
	return [{
		"kind": "ACTIVATED", "costs": costs, "targets": reader._targets, "effects": reader._effects,
		"restrictions": [],
	}]


## "Creatures you control get +1/+1", "Equipped creature gets +2/+2 and has menace", cost reductions.
## One keyword line that is really a triggered ability, or {}.
func _keyword_trigger(line: String) -> Dictionary:
	var low := line.to_lower().strip_edges()
	var m: RegExMatch
	if low == "exalted":
		return _kw("ATTACKS_ALONE", {}, [{"kind": "PUMP", "params": {"trigger_object": true, "power": 1, "toughness": 1, "duration": "END_OF_TURN"}}])
	if low == "battle cry":
		return _kw("ATTACKS", {}, [{"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "attacking": true, "other": true, "type": "creature"}, "power": 1, "toughness": 0, "duration": "END_OF_TURN"}}])
	m = _match("^afterlife (\\d+)$", low)
	if m != null:
		return _kw("DIES", {}, [{"kind": "CREATE_TOKEN", "params": {"count": int(m.get_string(1)), "spec": {"subtypes": ["Spirit"], "colors": ["W", "B"], "p": "1", "t": "1", "keywords": ["Flying"]}}}])
	m = _match("^annihilator (\\d+)$", low)
	if m != null:
		return _kw("ATTACKS", {}, [{"kind": "SACRIFICE", "params": {"n": int(m.get_string(1)), "who": "EACH_OPPONENT"}}])
	if low == "evolve":
		return _kw("ENTERS_BATTLEFIELD", {"scope": "OTHER", "greater_pt": true, "filter": {"controller": "SOURCE_CONTROLLER", "type": "creature"}}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "+1/+1", "n": 1}}])
	if low == "undying":
		return _kw("DIES", {"unless_counter": "+1/+1"}, [{"kind": "RETURN_SELF", "params": {"name": "+1/+1"}}])
	if low == "persist":
		return _kw("DIES", {"unless_counter": "-1/-1"}, [{"kind": "RETURN_SELF", "params": {"name": "-1/-1"}}])
	m = _match("^renown (\\d+)$", low)
	if m != null:
		return _kw("COMBAT_DAMAGE_TO_PLAYER", {"unless_counter": "renowned"}, [
			{"kind": "PUT_COUNTER", "params": {"self": true, "name": "+1/+1", "n": int(m.get_string(1))}},
			{"kind": "PUT_COUNTER", "params": {"self": true, "name": "renowned", "n": 1}}])
	m = _match("^fabricate (\\d+)$", low)
	if m != null:
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "FABRICATE", "params": {"n": int(m.get_string(1))}}])
	if low == "cascade":
		return _kw("SPELL_CAST", {"scope_self": true}, [{"kind": "CASCADE", "params": {}}])
	return {}


func _kw(on: String, extra: Dictionary, effects: Array) -> Dictionary:
	var trig := {"on": on}
	for k in extra.keys():
		trig[k] = extra[k]
	return {"kind": "TRIGGERED", "trigger": trig, "costs": [], "targets": [], "effects": effects, "restrictions": []}



func _static_line(line: String) -> Dictionary:
	var m: RegExMatch
	# Equipment / auras that boost or grant.
	m = _match("^equipped creature (?:gets ([+-]\\d+)/([+-]\\d+)(?: and has ([a-z ,]+?))?|has ([a-z ,]+?))$", line)
	if m != null:
		var kws := _keywords(m.get_string(3) if m.get_string(3) != "" else m.get_string(4))
		if (m.get_string(3) != "" or m.get_string(4) != "") and kws.is_empty():
			return {}
		var spec := {"scope": "EQUIPPED"}
		if m.get_string(1) != "":
			spec["power"] = int(m.get_string(1))
			spec["toughness"] = int(m.get_string(2))
		if not kws.is_empty():
			spec["keywords"] = kws
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": spec}

	# "Other Dinosaurs you control get +1/+1", "Creatures you control of the chosen type get +1/+1".
	m = _match("^(other )?(creatures|[a-z]+s) you control( of the chosen type)? (?:get ([+-]\\d+)/([+-]\\d+)(?: and (?:have|gain) ([a-z ,]+?))?|(?:have|gain) ([a-z ,]+?))$", line)
	if m != null:
		var kw_text := m.get_string(6) if m.get_string(6) != "" else m.get_string(7)
		var kws2 := _keywords(kw_text) if kw_text != "" else []
		if kw_text != "" and kws2.is_empty():
			return {}
		var q := {"controller": "SOURCE_CONTROLLER", "type": "creature"}
		var noun := m.get_string(2).to_lower()
		if noun != "creatures":
			q["subtype"] = _singular_type(noun)
		if m.get_string(3) != "":
			q["subtype"] = "$chosen"
		var spec2 := {"scope": "OTHERS" if m.get_string(1) != "" else "ALL", "query": q}
		if m.get_string(4) != "":
			spec2["power"] = int(m.get_string(4))
			spec2["toughness"] = int(m.get_string(5))
		if not kws2.is_empty():
			spec2["keywords"] = kws2
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": spec2}

	# "~ gets +2/+2 as long as you control a Dinosaur."
	m = _match("^~ gets ([+-]\\d+)/([+-]\\d+) as long as you control an? ([a-z]+)$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {
			"scope": "SELF", "power": int(m.get_string(1)), "toughness": int(m.get_string(2)),
			"condition": {"controls": {"controller": "SOURCE_CONTROLLER", "subtype": _cap(m.get_string(3))}},
		}}

	# "~ can't attack or block unless you control seven or more lands."
	m = _match("^~ can't attack or block unless you control (\\w+) or more lands$", line)
	if m != null and _num(m.get_string(1)) > 0:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cant_attack_block_unless": {"lands": _num(m.get_string(1))}}}
	m = _match("^~ can't attack or block unless you have the city's blessing$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cant_attack_block_unless": {"permanents": 10}}}

	# "Dinosaur spells you cast cost {1} less to cast."
	m = _match("^(creature|[a-z]+) spells you cast( of the chosen type)? cost \\{(\\d)\\} less to cast$", line)
	if m != null:
		var f := {"type": "creature"} if m.get_string(1).to_lower() == "creature" else {"type": "creature", "subtype": _cap(m.get_string(1))}
		if m.get_string(2) != "":
			f["subtype"] = "$chosen"
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(3)), "filter": f}}}
	return {}


## "When ~ enters, ...", "Whenever ~ attacks, ...", "At the beginning of your upkeep, ...".
func _trigger_line(line: String) -> Dictionary:
	var m: RegExMatch
	m = _match("^at the beginning of (your|each|each opponent's) (upkeep|end step|combat on your turn), (.+)$", line)
	if m != null:
		var step := "UPKEEP" if m.get_string(2).to_lower() == "upkeep" else ("END" if m.get_string(2).to_lower() == "end step" else "BEGIN_COMBAT")
		var whose := "YOURS" if m.get_string(1).to_lower() == "your" else ("EACH" if m.get_string(1).to_lower() == "each" else "OPPONENT")
		return _trigger_with({"on": "BEGIN_STEP", "step": step, "whose": whose}, m.get_string(3))
	m = _match("^(?:when|whenever) (.+?), ((?:you may |[a-z]).+)$", line)
	if m == null:
		return {}
	var header := m.get_string(1)
	var trig := _header(header)
	if trig.is_empty():
		return {}
	return _trigger_with(trig, m.get_string(2))


func _trigger_with(trig: Dictionary, effect_text: String) -> Dictionary:
	var reader := OracleIr.new()
	reader._self_it = str(trig.get("scope", "SELF")) == "SELF"
	if not reader._read_effects(effect_text):
		return {}
	return {"kind": "TRIGGERED", "trigger": trig, "costs": [], "targets": reader._targets, "effects": reader._effects, "restrictions": []}


## The trigger condition: "~ enters", "another Dinosaur you control enters", "~ dies", ...
func _header(h: String) -> Dictionary:
	var m: RegExMatch
	if _match("^~ enters(?: the battlefield)?$", h) != null:
		return {"on": "ENTERS_BATTLEFIELD"}
	m = _match("^~ or another ([a-z]+) you control enters(?: the battlefield)?$", h)
	if m != null:
		return {"on": "ENTERS_BATTLEFIELD", "scope": "ANY", "filter": _noun_filter(m.get_string(1))}
	m = _match("^another ([a-z]+) you control enters(?: the battlefield)?$", h)
	if m != null:
		return {"on": "ENTERS_BATTLEFIELD", "scope": "OTHER", "filter": _noun_filter(m.get_string(1))}
	m = _match("^another ([a-z]+) enters(?: the battlefield)? under your control$", h)
	if m != null:
		return {"on": "ENTERS_BATTLEFIELD", "scope": "OTHER", "filter": _noun_filter(m.get_string(1))}
	m = _match("^an? ([a-z]+) you control enters(?: the battlefield)?$", h)
	if m != null:
		return {"on": "ENTERS_BATTLEFIELD", "scope": "ANY", "filter": _noun_filter(m.get_string(1))}
	if _match("^~ attacks$", h) != null:
		return {"on": "ATTACKS"}
	if _match("^you attack$", h) != null:
		return {"on": "ATTACKS", "scope": "YOU"}
	m = _match("^an? ([a-z]+) you control attacks$", h)
	if m != null:
		return {"on": "ATTACKS", "scope": "ANY", "filter": _noun_filter(m.get_string(1))}
	if _match("^~ dies$", h) != null:
		return {"on": "DIES"}
	m = _match("^another ([a-z]+) you control dies$", h)
	if m != null:
		return {"on": "DIES", "scope": "OTHER", "filter": _noun_filter(m.get_string(1))}
	m = _match("^an? ([a-z]+) you control dies$", h)
	if m != null:
		return {"on": "DIES", "scope": "ANY", "filter": _noun_filter(m.get_string(1))}
	if _match("^~ deals combat damage to a player$", h) != null:
		return {"on": "COMBAT_DAMAGE_TO_PLAYER"}
	m = _match("^an? ([a-z]+) you control deals combat damage to a player$", h)
	if m != null:
		return {"on": "COMBAT_DAMAGE_TO_PLAYER", "scope": "ANY", "filter": _noun_filter(m.get_string(1))}
	if _match("^~ is dealt damage$", h) != null:
		return {"on": "DAMAGED"}
	if _match("^you gain life$", h) != null:
		return {"on": "LIFE_GAINED", "scope": "YOU"}
	if _match("^you cast a creature spell of the chosen type$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "query": {"type": "creature", "subtype": "$chosen"}}}
	if _match("^you cast a spell$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER"}}
	m = _match("^you cast (?:an? )?(.+?) spell$", h)
	if m != null:
		return _cast_filter(m.get_string(1))
	return {}


func _cast_filter(what: String) -> Dictionary:
	var types: Array = []
	for part in what.to_lower().replace(", or ", ",").replace(" or ", ",").split(","):
		var w := str(part).strip_edges()
		if w in ["instant", "sorcery", "creature", "artifact", "enchantment", "noncreature"]:
			types.append(w)
		else:
			## A creature type: "Whenever you cast a Dinosaur spell".
			if types.is_empty() and not what.contains(" or "):
				return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "query": {"type": "creature", "subtype": _cap(w)}}}
			return {}
	return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "types": types}}


## "Dinosaur" -> creatures of that type you control; "creature" and "land" as such.
func _noun_filter(noun: String) -> Dictionary:
	var n := noun.to_lower()
	if n == "creature" or n == "permanent":
		return {"type": "creature", "controller": "SOURCE_CONTROLLER"} if n == "creature" else {"controller": "SOURCE_CONTROLLER"}
	if n == "land":
		return {"type": "land", "controller": "SOURCE_CONTROLLER"}
	if n == "artifact":
		return {"type": "artifact", "controller": "SOURCE_CONTROLLER"}
	return {"type": "creature", "subtype": _cap(n), "controller": "SOURCE_CONTROLLER"}


# --- Effects ------------------------------------------------------------------------------

## Reads each sentence of an ability's effect text. False if any is not understood or nothing was read.
func _read_effects(effect_text: String) -> bool:
	for sentence in effect_text.split(". "):
		var s := str(sentence).strip_edges().trim_suffix(".").strip_edges()
		if s != "" and not _clause(s):
			return false
	return not _effects.is_empty()


## One sentence, or two joined by ", then " / " and ". Anything half-read is rolled back.
func _clause(s: String) -> bool:
	if s.to_lower().begins_with("you may "):
		s = s.substr(8)
	if _self_it and s.to_lower().begins_with("it "):
		s = "~ " + s.substr(3)
	if _try(s):
		return true
	for sep in [", then ", " and "]:
		var i := s.to_lower().find(sep)
		if i < 0:
			continue
		var t0 := _targets.size()
		var e0 := _effects.size()
		var left := s.substr(0, i)
		var right := s.substr(i + sep.length())
		if _try(left) and _try(right):
			return true
		_targets.resize(t0)
		_effects.resize(e0)
	return false


func _try(s: String) -> bool:
	var t0 := _targets.size()
	var e0 := _effects.size()
	if s.to_lower().begins_with("then "):
		s = s.substr(5)
	## "draw a card and gain 1 life": the second half has no subject.
	for verb in ["gain ", "lose ", "draw "]:
		if s.to_lower().begins_with(verb):
			s = "you " + s
			break
	if _self_it and s.to_lower().begins_with("it "):
		s = "~ " + s.substr(3)
	if _sentence(s):
		return true
	_targets.resize(t0)
	_effects.resize(e0)
	return false


## "{1}, {T}" -> [MANA {1}, TAP]. Empty when the cost has anything else in it (discard, X, pay life).
func _costs(cost_text: String) -> Array:
	var costs: Array = []
	var mana := ""
	for part in cost_text.split(", "):
		var p := str(part).strip_edges()
		if p == "{T}":
			costs.append({"kind": "TAP"})
			continue
		if p.to_lower() == "sacrifice ~":
			costs.append({"kind": "SACRIFICE_SELF"})
			continue
		if _match("^(\\{[0-9WUBRGC]+\\})+$", p) == null:
			return []
		mana += p
	if mana != "":
		costs.push_front({"kind": "MANA", "mana": mana})
	return costs


## Only spells that are cast and then resolve once. Permanents need triggers and static abilities.
static func _applies(def: CardDefinition) -> bool:
	if def.is_land() or def.is_creature():
		return false
	return def.type_line.contains("Instant") or def.type_line.contains("Sorcery")


func _read(def: CardDefinition) -> Dictionary:
	var text := normalize(def)
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
			## "~ costs {2} less to cast if it targets a Dinosaur you control." (CR 601.2f)
			var disc := _match("^~ costs \\{(\\d+)\\} less to cast if it targets an? ([a-z]+) you control$", s)
			if disc != null:
				_extra.append({
					"ability_id": "%s_discount" % _snake(def.name), "kind": "STATIC", "costs": [], "targets": [],
					"effects": [], "restrictions": [],
					"static": {"scope": "SELF", "cost_reduction_if_target": {
						"amount": int(disc.get_string(1)),
						"query": {"type": "creature", "subtype": _cap(disc.get_string(2)), "controller": "SOURCE_CONTROLLER"},
					}},
				})
				continue
			if not _clause(s):
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

	# Keyword actions as sentences: investigate, proliferate, explore, amass, bolster, populate.
	if _match("^investigate$", s) != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": "clue", "count": 1}})
		return true
	if _match("^proliferate$", s) != null:
		_effects.append({"kind": "PROLIFERATE", "params": {}})
		return true
	if _match("^(?:~|it) explores$|^explore$", s) != null:
		_effects.append({"kind": "EXPLORE", "params": {}})
		return true
	m = _match("^amass (?:[a-z]+ )?(\\d+)$", s)
	if m != null:
		_effects.append({"kind": "AMASS", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^bolster (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "BOLSTER", "params": {"n": int(m.get_string(1))}})
		return true
	if _match("^populate$", s) != null:
		_effects.append({"kind": "POPULATE", "params": {}})
		return true

	# CR 120.3: damage.
	m = _match("^(?:~|it) deals (\\d+) damage to (.+)$", s)
	if m != null:
		return _damage(int(m.get_string(1)), m.get_string(2))

	# CR 701.7: destroy.
	m = _match("^destroy all (?:non-?([a-z]+) )?creatures$", s)
	if m != null:
		var q := {"type": "creature"}
		if m.get_string(1) != "":
			q["not_subtype"] = _cap(m.get_string(1))
		_effects.append({"kind": "DESTROY_ALL", "params": {"query": q}})
		return true
	m = _match("^destroy (target .+)$", s)
	if m != null:
		var slot := _target(m.get_string(1))
		if slot < 0:
			return false
		_effects.append({"kind": "DESTROY", "params": {"target": slot}})
		return true

	# CR 701.13: exile.
	m = _match("^exile (target .+)$", s)
	if m != null:
		var slot2 := _target(m.get_string(1))
		if slot2 < 0:
			return false
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": slot2, "to": "EXILE"}})
		return true

	# Bounce.
	m = _match("^return (target .+?) to its owner's hand$", s)
	if m != null:
		var slot3 := _target(m.get_string(1))
		if slot3 < 0:
			return false
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": slot3, "to": "HAND"}})
		return true

	# Back from the graveyard.
	m = _match("^return target (.+?) card from your graveyard to (your hand|the battlefield)(?: tapped)?$", s)
	if m != null:
		var gq := {"zone": "GRAVEYARD", "controller": "SOURCE_CONTROLLER"}
		var noun := m.get_string(1).to_lower()
		if noun in ["creature", "artifact", "enchantment", "land"]:
			gq["type"] = noun
		elif noun != "permanent":
			gq["subtype"] = _cap(noun)
		var idx := _targets.size()
		_targets.append({"id": idx, "kind": "CARD_IN_ZONE", "count": 1, "query": gq})
		_effects.append({"kind": "RETURN_FROM_GRAVEYARD", "params": {"target": idx, "to": "HAND" if m.get_string(2) == "your hand" else "BATTLEFIELD"}})
		return true

	# CR 121: draw.
	m = _match("^(?:you )?draw (a|an|one|two|three|four|five|\\d+) cards?$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1))}})
		return true

	# CR 119: life.
	m = _match("^you gain (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^you gain life equal to that creature's (toughness|power)$", s)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "TRIGGER_TOUGHNESS" if m.get_string(1).to_lower() == "toughness" else "TRIGGER_POWER"}}})
		return true
	m = _match("^target player gains (\\d+) life$", s)
	if m != null:
		var pslot := _add_target("PLAYER", {})
		if pslot < 0:
			return false
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": int(m.get_string(1)), "target": pslot}})
		return true
	m = _match("^each opponent loses (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "EACH_OPPONENT"}})
		return true
	m = _match("^you lose (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "CONTROLLER"}})
		return true
	m = _match("^target opponent loses (\\d+) life$", s)
	if m != null:
		var oslot := _add_target("PLAYER", {"opponent": true})
		if oslot < 0:
			return false
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "target": oslot}})
		return true

	# CR 701.22: scry.
	m = _match("^scry (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "SCRY", "params": {"n": int(m.get_string(1))}})
		return true

	# Tokens.
	m = _match("^create (a|an|one|two|three|four|five|\\d+) (tapped )?(treasure|food|clue) tokens?$", s)
	if m != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": m.get_string(3).to_lower(), "count": _num(m.get_string(1)), "tapped": m.get_string(2) != ""}})
		return true
	var x_count: Variant = null
	var xm := _match("^(create x .+?), where x is (?:its|that creature's|~'s) (power|toughness)$", s)
	if xm != null:
		s = RegEx.create_from_string("(?i)^create x ").sub(xm.get_string(1), "create one ")
		x_count = {"expr": "TRIGGER_POWER" if xm.get_string(2).to_lower() == "power" else "TRIGGER_TOUGHNESS"}
	m = _match("^create (a|an|one|two|three|four|five|\\d+) (tapped )?(\\d+)/(\\d+) ((?:white|blue|black|red|green|colorless)(?:(?:,| and|, and) (?:white|blue|black|red|green))*) ([a-z' -]+?) (artifact )?creature tokens?(?: with ([a-z ,]+))?$", s)
	if m != null:
		var colors: Array = []
		for word in m.get_string(5).to_lower().replace(",", " ").replace(" and ", " ").split(" ", false):
			if COLOR_LETTERS.has(word):
				colors.append(COLOR_LETTERS[word])
		var subs: Array = []
		for word2 in m.get_string(6).split(" ", false):
			subs.append(_cap(word2))
		var kws: Array = []
		if m.get_string(8) != "":
			kws = _keywords(m.get_string(8))
			if kws.is_empty():
				return false
		var spec := {"p": m.get_string(3), "t": m.get_string(4), "colors": colors, "subtypes": subs, "keywords": kws, "artifact": m.get_string(7) != ""}
		_effects.append({"kind": "CREATE_TOKEN", "params": {"spec": spec, "count": x_count if x_count != null else _num(m.get_string(1)), "tapped": m.get_string(2) != ""}})
		return true

	# Counters.
	m = _match("^put (a|an|one|two|three|four|five|\\d+) \\+1/\\+1 counters? on (.+)$", s)
	if m != null:
		return _counters(_num(m.get_string(1)), m.get_string(2))

	# Pump and keywords until end of turn.
	m = _match("^~ gets ([+-]\\d+)/([+-]\\d+) until end of turn( for each land you control)?$", s)
	if m != null:
		var p: Variant = int(m.get_string(1))
		var t: Variant = int(m.get_string(2))
		if m.get_string(3) != "":
			p = {"expr": "LANDS", "mult": int(m.get_string(1))}
			t = {"expr": "LANDS", "mult": int(m.get_string(2))}
		_effects.append({"kind": "PUMP", "params": {"self": true, "power": p, "toughness": t, "duration": "END_OF_TURN"}})
		return true
	m = _match("^~ gains ([a-z ,]+) until end of turn$", s)
	if m != null:
		var own := _keywords(m.get_string(1))
		if own.is_empty():
			return false
		_effects.append({"kind": "PUMP", "params": {"self": true, "keywords": own, "duration": "END_OF_TURN"}})
		return true
	m = _match("^creatures you control get ([+-]\\d+)/([+-]\\d+)(?: and gain ([a-z ,]+))? until end of turn$", s)
	if m != null:
		var all_kws: Array = []
		if m.get_string(3) != "":
			all_kws = _keywords(m.get_string(3))
			if all_kws.is_empty():
				return false
		_effects.append({"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature"},
			"power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "keywords": all_kws, "duration": "END_OF_TURN"}})
		return true
	m = _match("^creatures you control gain ([a-z ,]+) until end of turn$", s)
	if m != null:
		var each_kws := _keywords(m.get_string(1))
		if each_kws.is_empty():
			return false
		_effects.append({"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature"},
			"keywords": each_kws, "duration": "END_OF_TURN"}})
		return true
	m = _match("^(target .+?) gets ([+-]\\d+)/([+-]\\d+)(?: and gains ([a-z ,]+))? until end of turn$", s)
	if m != null:
		var tk: Array = []
		if m.get_string(4) != "":
			tk = _keywords(m.get_string(4))
			if tk.is_empty():
				return false
		var ps := _target(m.get_string(1))
		if ps < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {
			"target": ps, "power": int(m.get_string(2)), "toughness": int(m.get_string(3)),
			"keywords": tk, "duration": "END_OF_TURN",
		}})
		return true
	m = _match("^((?:another )?target .+?) gains ([a-z ,]+) until end of turn$", s)
	if m != null:
		var gk := _keywords(m.get_string(2))
		if gk.is_empty():
			return false
		var gs := _target(m.get_string(1))
		if gs < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": gs, "keywords": gk, "duration": "END_OF_TURN"}})
		return true

	# Untap.
	m = _match("^untap all lands you control$", s)
	if m != null:
		_effects.append({"kind": "UNTAP_EACH", "params": {"query": {"controller": "SOURCE_CONTROLLER", "type": "land"}}})
		return true
	m = _match("^untap each creature you control$", s)
	if m != null:
		_effects.append({"kind": "UNTAP_EACH", "params": {"query": {"controller": "SOURCE_CONTROLLER", "type": "creature"}}})
		return true
	m = _match("^untap (target .+)$", s)
	if m != null:
		var us := _target(m.get_string(1))
		if us < 0:
			return false
		_effects.append({"kind": "UNTAP", "params": {"target": us}})
		return true

	# Search your library.
	m = _match("^search your library for (?:(a|an|one|two|three)|up to (one|two|three)) (basic land|land|[a-z, ]+?) cards?, (?:reveal (?:it|them|those cards), )?put (?:it|them) (onto the battlefield tapped|onto the battlefield|into your hand)$", s)
	if m != null:
		return _search(m)
	m = _match("^search your library for up to two basic land cards, reveal those cards, put one onto the battlefield tapped and the other into your hand$", s)
	if m != null:
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filter": {"basic_land": true}, "n": 1, "to": "BATTLEFIELD", "tapped": true}})
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filter": {"basic_land": true}, "n": 1, "to": "HAND"}})
		return true
	if _match("^(?:then )?shuffle(?: your library)?$", s) != null:
		return true

	# CR 701.14: fights, and "deals damage equal to its power".
	m = _match("^(?:~|it) fights (.+)$", s)
	if m != null:
		var fs := _target(m.get_string(1))
		if fs < 0:
			return false
		_effects.append({"kind": "FIGHT", "params": {"a": "SELF", "b": fs}})
		return true
	m = _match("^that creature fights (target .+)$", s)
	if m != null and not _targets.is_empty():
		var fs2 := _target(m.get_string(1))
		if fs2 < 0:
			return false
		_effects.append({"kind": "FIGHT", "params": {"a": 0, "b": fs2}})
		return true
	m = _match("^(target creature you control) fights ((?:another )?target .+)$", s)
	if m != null:
		var a1 := _target(m.get_string(1))
		var b1 := _target(m.get_string(2))
		if a1 < 0 or b1 < 0:
			return false
		_effects.append({"kind": "FIGHT", "params": {"a": a1, "b": b1}})
		return true
	m = _match("^(target creature you control) deals damage equal to its power to ((?:another )?target .+)$", s)
	if m != null:
		var a2 := _target(m.get_string(1))
		var b2 := _target(m.get_string(2))
		if a2 < 0 or b2 < 0:
			return false
		_effects.append({"kind": "FIGHT", "params": {"a": a2, "b": b2, "one_sided": true}})
		return true

	# Rituals and "add {G}".
	m = _match("^add (.+)$", s)
	if m != null:
		var produced := _mana_text(m.get_string(1))
		if produced == "":
			return false
		_effects.append({"kind": "ADD_MANA", "params": {"mana": produced}})
		return true

	# Counter.
	m = _match("^counter target spell$", s)
	if m != null:
		var cs := _add_target("SPELL_ON_STACK", {})
		if cs < 0:
			return false
		_effects.append({"kind": "COUNTER_SPELL", "params": {"target": cs}})
		return true

	# Hideaway payoff: "play the exiled card without paying its mana cost [if creatures you control have total power N or greater]".
	m = _match("^play the exiled card without paying its mana cost(?: if creatures you control have total power (\\d+) or greater)?$", s)
	if m != null:
		var hp := {}
		if m.get_string(1) != "":
			hp["min_total_power"] = int(m.get_string(1))
		_effects.append({"kind": "PLAY_HIDDEN", "params": hp})
		return true

	# Mill, discard, surveil.
	m = _match("^(?:you )?surveil (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "SURVEIL", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^(each opponent|you) mills? (a|an|one|two|three|four|five|six|seven|eight|nine|ten|\\d+) cards?$", s)
	if m != null:
		_effects.append({"kind": "MILL", "params": {"n": _num(m.get_string(2)), "who": "EACH_OPPONENT" if m.get_string(1).to_lower() == "each opponent" else "CONTROLLER"}})
		return true
	m = _match("^(each opponent|you) discards? (a|an|one|two|three|four|five|\\d+) cards?$", s)
	if m != null:
		_effects.append({"kind": "DISCARD", "params": {"n": _num(m.get_string(2)), "who": "EACH_OPPONENT" if m.get_string(1).to_lower() == "each opponent" else "CONTROLLER"}})
		return true

	# CR 724: the monarch.
	if _match("^you become the monarch$", s) != null:
		_effects.append({"kind": "BECOME_MONARCH", "params": {}})
		return true

	# CR 701.57: discover.
	m = _match("^(?:you may )?discover (\\d+|x)(?:, where x is (?:that creature's|its|~'s) (toughness|power))?$", s)
	if m != null:
		var dn: Variant = int(m.get_string(1)) if m.get_string(1).is_valid_int() else 0
		if not m.get_string(1).is_valid_int():
			if m.get_string(2) == "":
				return false
			dn = {"expr": "TRIGGER_TOUGHNESS" if m.get_string(2).to_lower() == "toughness" else "TRIGGER_POWER"}
		_effects.append({"kind": "DISCOVER", "params": {"n": dn}})
		return true

	# Choose a creature type (the "As ~ enters" line wraps this).
	if _match("^choose a creature type$", s) != null:
		_effects.append({"kind": "CHOOSE_TYPE", "params": {"auto": true}})
		return true

	# "for each opponent, exile up to one target nonland permanent that player controls until ~ leaves."
	m = _match("^for each opponent, exile up to one target (nonland permanent|permanent|creature|artifact|enchantment|land) that player controls until ~ leaves the battlefield$", s)
	if m != null:
		var es := _add_permanent(m.get_string(1), true)
		if es < 0:
			return false
		_targets[es]["optional"] = true
		_effects.append({"kind": "EXILE_UNTIL_LEAVES", "params": {"target": es}})
		return true

	return false


func _damage(n: int, rest: String) -> bool:
	var r := rest.to_lower().strip_edges()
	if r == "each opponent":
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": n, "who": "EACH_OPPONENT"}})
		return true
	if r == "each other creature":
		_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": n, "query": {"type": "creature", "other": true}}})
		return true
	if r == "each creature":
		_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": n, "query": {"type": "creature"}}})
		return true
	var slot := _target(rest)
	if slot < 0:
		return false
	_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": n, "target": slot}})
	return true


func _counters(n: int, where: String) -> bool:
	var w := where.to_lower().strip_edges()
	if w == "~":
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": n, "self": true}})
		return true
	if w == "each other creature you control":
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": n, "each": {"controller": "SOURCE_CONTROLLER", "type": "creature", "other": true}}})
		return true
	if w == "each creature you control":
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": n, "each": {"controller": "SOURCE_CONTROLLER", "type": "creature"}}})
		return true
	var slot := _target(where)
	if slot < 0:
		return false
	_effects.append({"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": n, "target": slot}})
	return true


## "...a Plains, Island, Swamp, or Mountain card" / "a basic land card" / "up to two basic land cards".
func _search(m: RegExMatch) -> bool:
	var count := _num(m.get_string(1)) if m.get_string(1) != "" else _num(m.get_string(2))
	var what := m.get_string(3).to_lower().strip_edges()
	var filt := {}
	if what == "basic land":
		filt = {"basic_land": true}
	elif what == "land":
		filt = {"type": "land"}
	else:
		var subs: Array = []
		for part in what.replace(", or ", ",").replace(" or ", ",").split(","):
			var w := str(part).strip_edges()
			if not (w in ["plains", "island", "swamp", "mountain", "forest"]):
				return false
			subs.append(_cap(w))
		if subs.is_empty():
			return false
		filt = {"subtype_any": subs}
	var dest := m.get_string(4).to_lower()
	_effects.append({"kind": "SEARCH_LIBRARY", "params": {
		"filter": filt, "n": count,
		"to": "HAND" if dest == "into your hand" else "BATTLEFIELD",
		"tapped": dest == "onto the battlefield tapped",
	}})
	return true


# --- Targets --------------------------------------------------------------------------------

## "target creature you don't control", "another target Dinosaur you control", "any target",
## "up to one target creature" -> a target slot. Returns its index, or -1 if the phrase isn't understood.
func _target(phrase: String) -> int:
	var s := phrase.strip_edges()
	var optional := false
	if s.to_lower().begins_with("up to one "):
		optional = true
		s = s.substr(10)
	var other := false
	if s.to_lower().begins_with("another "):
		other = true
		s = s.substr(8)
	var low := s.to_lower()
	var idx := -1
	if low == "any target":
		idx = _add_target("ANY_TARGET", {})
	elif low == "target player":
		idx = _add_target("PLAYER", {})
	elif low == "target opponent":
		idx = _add_target("PLAYER", {"opponent": true})
	elif _match("^target (artifact|creature|enchantment|land) or (artifact|creature|enchantment|land)( you control| you don't control| an opponent controls)?$", s) != null:
		var m2 := _match("^target (artifact|creature|enchantment|land) or (artifact|creature|enchantment|land)( you control| you don't control| an opponent controls)?$", s)
		var q2 := {"type_any": [m2.get_string(1).to_lower(), m2.get_string(2).to_lower()]}
		var who2 := m2.get_string(3).strip_edges().to_lower()
		if who2 == "you control":
			q2["controller"] = "SOURCE_CONTROLLER"
		elif who2 != "":
			q2["controller"] = "OPPONENT"
		if other:
			q2["other"] = true
		idx = _add_target("PERMANENT", q2)
	else:
		var m := _match("^target (nonland permanent|permanent|creature|artifact|enchantment|land|[a-z]+)( you control| you don't control| an opponent controls)?$", s)
		if m == null:
			return -1
		var noun := m.get_string(1).to_lower()
		var q: Dictionary
		if PERMANENT_QUERIES.has(noun):
			q = (PERMANENT_QUERIES[noun] as Dictionary).duplicate()
		else:
			q = {"type": "creature", "subtype": _cap(noun)}
		var who := m.get_string(2).strip_edges().to_lower()
		if who == "you control":
			q["controller"] = "SOURCE_CONTROLLER"
		elif who != "":
			q["controller"] = "OPPONENT"
		if other:
			q["other"] = true
		idx = _add_target("PERMANENT", q)
	if idx >= 0 and optional:
		_targets[idx]["optional"] = true
	return idx


func _add_permanent(type_name: String, opponents_only: bool) -> int:
	var query: Dictionary = (PERMANENT_QUERIES[type_name.to_lower()] as Dictionary).duplicate()
	if opponents_only:
		query["controller"] = "OPPONENT"
	return _add_target("PERMANENT", query)


## Adds a target slot and returns its index.
func _add_target(kind: String, query: Dictionary) -> int:
	if _targets.size() >= 3:
		return -1
	var slot := {"id": _targets.size(), "kind": kind, "count": 1}
	if not query.is_empty():
		slot["query"] = query
	_targets.append(slot)
	return _targets.size() - 1


# --- Small helpers --------------------------------------------------------------------------

## "flying and first strike" -> ["Flying", "First strike"]. Empty if any word is unknown.
func _keywords(list_text: String) -> Array:
	var out: Array = []
	for part in list_text.replace(", and ", ",").replace(" and ", ",").split(","):
		var kw := str(part).strip_edges().to_lower()
		if not kw in KEYWORDS:
			return []
		out.append(kw.substr(0, 1).to_upper() + kw.substr(1))
	return out


## "{R}{G}" stays as is; "{R} or {G}" becomes "{R|G}"; "one mana of any color" becomes "{W|U|B|R|G}";
## "...in your commander's color identity" becomes "{CI}". "" when the text says anything else
## (extra sentences such as pain damage, conditions, "any type a land could produce").
static func _mana_text(t: String) -> String:
	t = t.strip_edges().trim_suffix(".").strip_edges()
	var low := t.to_lower()
	if low == "one mana of any color":
		return "{W|U|B|R|G}"
	if low == "one mana of any color in your commander's color identity":
		return "{CI}"
	if _match("^(\\{[WUBRGC]\\})+$", t) != null:
		return t
	var letters: Array = []
	for part in t.replace(", or ", ",").replace(" or ", ",").split(","):
		var p := str(part).strip_edges()
		if _match("^\\{[WUBRGC]\\}$", p) == null:
			return ""
		letters.append(p.substr(1, 1).to_upper())
	if letters.size() >= 2:
		return "{%s}" % "|".join(PackedStringArray(letters))
	return ""


static func _num(word: String) -> int:
	var w := word.to_lower()
	if w.is_valid_int():
		return int(w)
	return int(NUMBER_WORDS.get(w, 0))


static func _cap(word: String) -> String:
	var w := word.strip_edges()
	return w.substr(0, 1).to_upper() + w.substr(1).to_lower() if w != "" else w


## "dinosaurs" -> "Dinosaur", "elves" -> "Elf".
static func _singular_type(plural: String) -> String:
	var w := plural.to_lower()
	if w.ends_with("ves"):
		return _cap(w.trim_suffix("ves") + "f")
	if w.ends_with("s"):
		return _cap(w.trim_suffix("s"))
	return _cap(w)


static func _match(pattern: String, s: String) -> RegExMatch:
	var re := RegEx.create_from_string("(?i)" + pattern)
	return re.search(s)


static func _snake(card_name: String) -> String:
	var re := RegEx.create_from_string("[^a-z0-9]+")
	return re.sub(card_name.to_lower(), "_", true).trim_prefix("_").trim_suffix("_")
