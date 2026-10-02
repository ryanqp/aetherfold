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
	"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
	"fourteen": 14, "fifteen": 15, "twenty": 20,
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
	"celebration", "corrupted", "eminence", "imprint", "pack tactics", "probing telepathy", "coven", "max speed",
]

const COLOR_LETTERS := {
	"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G",
}

var _targets: Array = []
var _pay_links: int = 0
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
	var in_band := false
	var re_band := RegEx.create_from_string("^(LEVEL|STATION) \\d+(-\\d+|\\+)$")
	for raw in normalize(def).split("\n"):
		var line := strip_ability_word(str(raw).strip_edges())
		if line == "":
			continue
		## A level / station band's abilities only count in that band (read by LayerManager), not always.
		if re_band.search(line) != null:
			in_band = true
			continue
		if in_band:
			continue
		## Prefixed activated abilities: boast, exhaust, max speed limit when; channel and forecast are activated
		## from the hand (the "discard ~" / "reveal ~" part is done by the special action).
		var prefix := ""
		var praw := str(raw).strip_edges()
		var pm := RegEx.create_from_string("^(?i)(boast|exhaust|max speed|channel|forecast) — (.+)$").search(praw)
		if pm != null:
			prefix = pm.get_string(1).to_upper().replace(" ", "_")
			line = pm.get_string(2)
			if prefix == "CHANNEL" or prefix == "FORECAST":
				line = RegEx.create_from_string("(?i),? (discard|reveal) ~(?: from your hand)?(?=:)").sub(line, "", true)
				if line.begins_with(":") or line.begins_with(", "):
					line = "{0}" + line.trim_prefix(",")
		var found: Array = _read_whole_or_by_sentence(def, line)
		if prefix != "":
			for f in found:
				if str((f as Dictionary).get("kind", "")) == "ACTIVATED":
					var rs: Array = (f as Dictionary).get("restrictions", [])
					rs.append(prefix)
					(f as Dictionary)["restrictions"] = rs
		for item in found:
			var d: Dictionary = item
			n += 1
			d["ability_id"] = "%s_%s%d" % [_snake(def.name), str(d.get("kind", "x")).to_lower(), n]
			d["text"] = line
			## A quoted ability the permanent has only while a condition holds (celebration): read it as a granted ability.
			var st_spec: Dictionary = d.get("static", {})
			if st_spec.has("grant_text"):
				var gtext := str(st_spec["grant_text"])
				st_spec.erase("grant_text")
				var granted: Array = OracleIr.new()._read_line(def, gtext)
				if granted.size() != 1:
					continue
				var g: Dictionary = granted[0]
				g["ability_id"] = "%s_granted%d" % [_snake(def.name), n]
				g["granted"] = true
				g["text"] = gtext
				var gl := IrLoader.new()
				var gparsed := gl.from_dict({"abilities": [g]})
				if not gl.errors.is_empty():
					continue
				st_spec["grant_ability_ids"] = [g["ability_id"]]
				out.append_array(gparsed)
			var loader := IrLoader.new()
			var parsed := loader.from_dict({"abilities": [d]})
			if loader.errors.is_empty():
				out.append_array(parsed)
	return out


static func _read_whole_or_by_sentence(def: CardDefinition, line: String) -> Array:
	var found := _read_clean(def, line)
	if not found.is_empty() or not line.contains(". "):
		return found
	## A mana ability with extra sentences ("Spend this mana only to cast ...") is read whole or not at all:
	## reading just its first sentence would drop the restriction.
	if line.to_lower().begins_with("{t}: add") or line.to_lower().contains(": add "):
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

	# Infinity (CR 702.186b): "∞ — [ability]" is that ability only while the permanent is harnessed (CR 701.64).
	m = _match("^∞ — (.+)$", line)
	if m != null:
		var inner := _read_line(def, m.get_string(1))
		var gated: Array = []
		for ab in inner:
			if ab is Dictionary and str((ab as Dictionary).get("kind", "")) == "TRIGGERED":
				((ab as Dictionary).trigger as Dictionary)["if_harnessed"] = true
				gated.append(ab)
		return gated if gated.size() == inner.size() else []

	# Saga chapter abilities (CR 714.2): "I — ...", "I, II — ...". They trigger as lore counters are added.
	m = _match("^((?:i|ii|iii|iv|v|vi)(?:, (?:i|ii|iii|iv|v|vi))*) — (.+)$", line)
	if m != null and def.type_line.contains("Saga"):
		var chapters: Array = []
		for c in m.get_string(1).to_lower().split(", "):
			chapters.append(["i", "ii", "iii", "iv", "v", "vi"].find(str(c)) + 1)
		var ch := _trigger_with({"on": "CHAPTER", "chapters": chapters}, m.get_string(2))
		return [ch] if not ch.is_empty() else []

	# Enchant (CR 702.5, 303.4a): an Aura spell targets what it will enchant; it enters attached to it.
	m = _match("^enchant ([a-z ,]+)$", line)
	if m != null:
		var eq := _enchant_query(m.get_string(1).to_lower())
		if eq.is_empty():
			return []
		var low_text := def.oracle_text.to_lower()
		var helpful := low_text.contains("enchanted creature gets +") or low_text.contains("enchanted creature has ")
		return [{
			"kind": "SPELL", "costs": [{"kind": "MANA", "mana": def.mana_cost}] if def.mana_cost != "" else [],
			"targets": [{"id": 0, "kind": "PERMANENT", "count": 1, "query": eq}],
			"effects": [{"kind": "AURA_ATTACH", "params": {"target": 0, "helpful": helpful}}],
		}]

	# Pain lands: "{T}: Add {R} or {G}. ~ deals 1 damage to you." (still a mana ability, CR 605.1a).
	m = _match("^\\{T\\}: add (.+?)\\. ~ deals (\\d+) damage to you$", line)
	if m != null:
		var pain_mana := _mana_text(m.get_string(1))
		if pain_mana != "":
			return [{
				"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": pain_mana}}, {"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(2)), "who": "CONTROLLER"}}],
				"restrictions": [],
			}]

	# "Spend this mana only to cast a Dinosaur spell or activate an ability of a Dinosaur source." (CR 106.6)
	m = _match("^\\{T\\}: add (.+?)\\. spend this mana only to cast (?:an? )?([a-z]+) spells?( of the chosen type)?(?: or activate an abilit(?:y|ies) of an? ([a-z]+) sources?( of the chosen type)?)?$", line)
	if m != null:
		var rmana := _mana_text(m.get_string(1))
		if rmana != "":
			var rq := {}
			var noun := m.get_string(2).to_lower()
			if noun == "creature":
				rq["type"] = "creature"
			else:
				rq["subtype"] = _cap(noun)
			if m.get_string(3) != "":
				rq["subtype"] = "$chosen"
			return [{
				"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": rmana}}],
				"restrictions": [{"spend_only": {"query": rq, "abilities": line.to_lower().contains("activate an abilit")}}],
			}]

	# Path of Ancestry: the scry rider rides on the mana ability.
	if _match("^\\{T\\}: add one mana of any color in your commander's color identity\\. when that mana is spent to cast a creature spell that shares a creature type with your commander, scry 1$", line) != null:
		return [{
			"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
			"effects": [{"kind": "ADD_MANA", "params": {"mana": "{CI}"}}],
			"restrictions": [{"on_spend": {"query": {"type": "creature", "shares_type_with_commander": true}, "scry": 1}}],
		}]

	# Temple of the False God: "{T}: Add {C}{C}. Activate only if you control five or more lands."
	m = _match("^\\{T\\}: add (.+?)\\. activate only if you control (\\w+) or more lands$", line)
	if m != null and _num(m.get_string(2)) > 0:
		var tmana := _mana_text(m.get_string(1))
		if tmana != "":
			return [{
				"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": tmana}}],
				"restrictions": [{"min_lands": _num(m.get_string(2))}],
			}]

	# Progenitor's Icon: "{T}: The next spell of the chosen type you cast this turn can be cast as though it had flash."
	if _match("^\\{T\\}: the next spell of the chosen type you cast this turn can be cast as though it had flash$", line) != null:
		return [{
			"kind": "ACTIVATED", "costs": [{"kind": "TAP"}], "targets": [],
			"effects": [{"kind": "GRANT_FLASH", "params": {}}], "restrictions": [],
		}]

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
	var km := _keyword_multi(line)
	if not km.is_empty():
		return km
	var kt := _keyword_trigger(line)
	if not kt.is_empty():
		return [kt]

	var st := _static_line(line)
	if not st.is_empty():
		return [st]

	# Thriving lands: "As ~ enters, choose a color other than green." / "{T}: Add one mana of the chosen color."
	m = _match("^as (?:~|it) enters, choose a color other than (white|blue|black|red|green)$", line)
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

	# "Whenever ~ enters or attacks, ..." is two triggers with the same effect.
	m = _match("^(?:when|whenever) ~ enters or attacks, (.+)$", line)
	if m != null:
		var both: Array = []
		for on in ["ENTERS_BATTLEFIELD", "ATTACKS"]:
			var one := _trigger_with({"on": on}, m.get_string(1))
			if one.is_empty():
				return []
			both.append(one)
		return both

	var trig := _trigger_line(line)
	if not trig.is_empty():
		return [trig]

	# Planeswalker loyalty abilities (CR 606): "+1: ...", "−3: ...", "0: ...". Once per turn, as a sorcery.
	m = _match("^([+−-]?)(\\d+): (.+)$", line)
	if m != null:
		var lr := OracleIr.new()
		if not lr._read_effects(m.get_string(3)):
			return []
		var sign := m.get_string(1)
		var amount := int(m.get_string(2))
		if sign == "−" or sign == "-":
			amount = -amount
		return [{
			"kind": "ACTIVATED", "costs": [{"kind": "LOYALTY", "mana": str(amount)}], "targets": lr._targets,
			"effects": lr._effects, "restrictions": ["LOYALTY"],
		}]

	# Activated: "{1}, {T}: effect" or "Sacrifice ~: effect".
	m = _match("^((?:\\{[^}]+\\}|waterbend \\{\\d+\\}|sacrifice ~|pay \\d+ life|put an? [a-z0-9+/-]+ counter on ~|, )+): (.+)$", line)
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
	## CR 702.92: living weapon - a 0/0 black Phyrexian Germ token, then attach this Equipment to it.
	if low == "living weapon":
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "LIVING_WEAPON", "params": {}}])
	## CR 702.163 For Mirrodin! (2/2 red Rebel), CR 702.182 job select (1/1 colorless Hero): token, then attach.
	if low == "for mirrodin!":
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "EQUIP_TOKEN", "params": {"spec": {"subtypes": ["Rebel"], "colors": ["R"], "p": "2", "t": "2"}}}])
	if low == "job select":
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "EQUIP_TOKEN", "params": {"spec": {"subtypes": ["Hero"], "colors": [], "p": "1", "t": "1"}}}])
	## CR 702.70 poisonous N, CR 702.115 ingest: combat damage to a player.
	m = _match("^poisonous (\\d+)$", low)
	if m != null:
		return _kw("COMBAT_DAMAGE_TO_PLAYER", {}, [{"kind": "POISON", "params": {"n": int(m.get_string(1))}}])
	if low == "ingest":
		return _kw("COMBAT_DAMAGE_TO_PLAYER", {}, [{"kind": "EXILE_TOP", "params": {"n": 1, "who": "DEFENDER"}}])
	## CR 702.68 frenzy N: whenever it attacks and isn't blocked, +N/+0.
	m = _match("^frenzy (\\d+)$", low)
	if m != null:
		return _kw("NOT_BLOCKED", {}, [{"kind": "PUMP", "params": {"self": true, "power": int(m.get_string(1)), "toughness": 0, "duration": "END_OF_TURN"}}])
	## CR 702.130 afflict N: whenever it becomes blocked, defending player loses N life.
	m = _match("^afflict (\\d+)$", low)
	if m != null:
		return _kw("BECOMES_BLOCKED", {}, [{"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "DEFENDER"}}])
	## CR 702.121 melee: +1/+1 for each opponent you attacked this combat (one in a duel).
	if low == "melee":
		return _kw("ATTACKS", {}, [{"kind": "PUMP", "params": {"self": true, "power": 1, "toughness": 1, "duration": "END_OF_TURN"}}])
	## CR 702.134 mentor: +1/+1 counter on target attacking creature with lesser power.
	if low == "mentor":
		return _kw("ATTACKS", {}, [{"kind": "MENTOR", "params": {}}])
	## CR 702.149 training: attacks with another creature with greater power: +1/+1 counter.
	if low == "training":
		return _kw("ATTACKS", {"with_greater_power": true}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "+1/+1", "n": 1}}])
	## CR 702.181 mobilize N.
	m = _match("^mobilize (\\d+)$", low)
	if m != null:
		return _kw("ATTACKS", {}, [{"kind": "MOBILIZE", "params": {"n": int(m.get_string(1))}}])
	## CR 702.189 firebending N.
	m = _match("^firebending (\\d+)$", low)
	if m != null:
		return _kw("ATTACKS", {}, [{"kind": "FIREBEND", "params": {"n": int(m.get_string(1))}}])
	## CR 702.191 increment.
	if low == "increment":
		return _kw("SPELL_CAST", {"filter": {"controller": "SOURCE_CONTROLLER"}}, [{"kind": "INCREMENT", "params": {}}])
	## CR 702.110 exploit.
	if low == "exploit":
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "EXPLOIT", "params": {}}])
	## CR 702.165 backup N.
	m = _match("^backup (\\d+)$", low)
	if m != null:
		return {"kind": "TRIGGERED", "trigger": {"on": "ENTERS_BATTLEFIELD"}, "costs": [], "restrictions": [],
			"targets": [{"id": 0, "kind": "PERMANENT", "count": 1, "query": {"type": "creature", "controller": "SOURCE_CONTROLLER"}}],
			"effects": [{"kind": "BACKUP", "params": {"target": 0, "n": int(m.get_string(1))}}]}
	## CR 702.147 decayed: when it attacks, sacrifice it at end of combat.
	if low == "decayed":
		return _kw("ATTACKS", {}, [{"kind": "MARK", "params": {"self": true, "mark": "sacrifice at end of combat"}}])
	## CR 702.39 provoke: target creature defending player controls untaps and blocks it if able.
	if low == "provoke":
		return {"kind": "TRIGGERED", "trigger": {"on": "ATTACKS"}, "costs": [], "restrictions": [],
			"targets": [{"id": 0, "kind": "PERMANENT", "count": 1, "optional": true, "query": {"type": "creature", "controller": "OPPONENT"}}],
			"effects": [{"kind": "PROVOKE", "params": {"target": 0}}]}
	## CR 702.98 unleash, CR 702.104 tribute N, CR 702.38 amplify N, CR 702.82 devour N, CR 702.44 sunburst,
	## CR 702.156 ravenous, CR 702.72 champion: decided as it enters.
	for kw_enter in ["unleash", "sunburst", "ravenous"]:
		if low == kw_enter:
			return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "AS_ENTERS", "params": {"what": kw_enter}}])
	m = _match("^(tribute|amplify|devour) (\\d+)$", low)
	if m != null:
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "AS_ENTERS", "params": {"what": m.get_string(1), "n": int(m.get_string(2))}}])
	m = _match("^champion an? ([a-z]+)$", low)
	if m != null:
		return _kw("ENTERS_BATTLEFIELD", {}, [{"kind": "CHAMPION", "params": {"type": m.get_string(1)}}])
	## CR 702.40 storm, 702.69 gravestorm, 702.60 ripple N, 702.50 epic: when you cast it.
	if low == "storm" or low == "gravestorm":
		return _kw("SPELL_CAST", {"scope_self": true}, [{"kind": "STORM", "params": {"grave": low == "gravestorm"}}])
	m = _match("^ripple (\\d+)$", low)
	if m != null:
		return _kw("SPELL_CAST", {"scope_self": true}, [{"kind": "RIPPLE", "params": {"n": int(m.get_string(1))}}])
	## CR 702.95 soulbond: pair as this or another creature enters.
	if low == "soulbond":
		return _kw("ENTERS_BATTLEFIELD", {"scope": "ANY", "filter": {"type": "creature", "controller": "SOURCE_CONTROLLER"}}, [{"kind": "SOULBOND", "params": {}}])
	## CR 702.105: dethrone - attacking the player with the most life (or tied) puts a +1/+1 counter on it.
	if low == "dethrone":
		return _kw("ATTACKS", {}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "+1/+1", "n": 1, "if_defender_most_life": true}}])
	return {}


## Keyword lines that turn into several abilities: echo, vanishing, fading, cumulative upkeep, extort,
## bloodthirst, bushido, flanking, rampage, enlist. A comma list of them ("flanking, bushido 1") is read part by part.
func _keyword_multi(line: String) -> Array:
	var low := line.to_lower().strip_edges()
	var out: Array = _keyword_one(low)
	if not out.is_empty():
		return out
	if not low.contains(", ") or low.contains(":"):
		return []
	for part in low.split(", "):
		var got := _keyword_one(str(part).strip_edges())
		if got.is_empty():
			if not KeywordDb.line_is_handled(str(part)):
				return []
			continue
		out.append_array(got)
	return out


func _keyword_one(low: String) -> Array:
	var m: RegExMatch
	## CR 702.43 modular N: enters with N +1/+1 counters; when it dies, you may put them on target artifact creature.
	m = _match("^modular (\\d+)$", low)
	if m != null:
		return [
			_kw("ENTERS_BATTLEFIELD", {}, [{"kind": "AS_ENTERS", "params": {"what": "modular", "n": int(m.get_string(1))}}]),
			{"kind": "TRIGGERED", "trigger": {"on": "DIES"}, "costs": [], "restrictions": [],
				"targets": [{"id": 0, "kind": "PERMANENT", "count": 1, "optional": true, "query": {"type": "artifact"}}],
				"effects": [{"kind": "MOVE_COUNTERS", "params": {"target": 0, "name": "+1/+1"}}]},
		]
	## CR 702.58 graft N: enters with N counters; whenever another creature enters, you may move one onto it.
	m = _match("^graft (\\d+)$", low)
	if m != null:
		return [
			_kw("ENTERS_BATTLEFIELD", {}, [{"kind": "AS_ENTERS", "params": {"what": "graft", "n": int(m.get_string(1))}}]),
			_kw("ENTERS_BATTLEFIELD", {"scope": "OTHER", "filter": {"type": "creature"}}, [{"kind": "GRAFT_MOVE", "params": {}}]),
		]
	## CR 702.46 soulshift N.
	m = _match("^soulshift (\\d+)$", low)
	if m != null:
		return [{"kind": "TRIGGERED", "trigger": {"on": "DIES"}, "costs": [], "restrictions": [],
			"targets": [{"id": 0, "kind": "CARD_IN_ZONE", "count": 1, "optional": true, "query": {"zone": "GRAVEYARD", "controller": "SOURCE_CONTROLLER", "subtype": "Spirit", "mv_max": int(m.get_string(1))}}],
			"effects": [{"kind": "RETURN_FROM_GRAVEYARD", "params": {"target": 0, "to": "HAND"}}]}]
	var upkeep := {"on": "BEGIN_STEP", "step": "UPKEEP", "whose": "YOURS"}
	m = _match("^echo[ —-]+((?:\\{[^}]+\\})+)$", low)
	if m != null:
		return [
			_kw("ENTERS_BATTLEFIELD", {}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "echo", "n": 1}}]),
			_kw_trig(upkeep, [{"kind": "ECHO", "params": {"cost": m.get_string(1).to_upper()}}]),
		]
	m = _match("^vanishing (\\d+)$", low)
	if m != null:
		return [
			_kw("ENTERS_BATTLEFIELD", {}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "time", "n": int(m.get_string(1))}}]),
			_kw_trig(upkeep, [{"kind": "COUNTDOWN", "params": {"counter": "time", "mode": "vanishing"}}]),
		]
	m = _match("^fading (\\d+)$", low)
	if m != null:
		return [
			_kw("ENTERS_BATTLEFIELD", {}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "fade", "n": int(m.get_string(1))}}]),
			_kw_trig(upkeep, [{"kind": "COUNTDOWN", "params": {"counter": "fade", "mode": "fading"}}]),
		]
	m = _match("^cumulative upkeep[ —-]+((?:\\{[^}]+\\})+)$", low)
	if m != null:
		return [_kw_trig(upkeep, [{"kind": "CUMULATIVE_UPKEEP", "params": {"cost": m.get_string(1).to_upper(), "life": 0}}])]
	m = _match("^cumulative upkeep[ —-]+pay (\\d+) life$", low)
	if m != null:
		return [_kw_trig(upkeep, [{"kind": "CUMULATIVE_UPKEEP", "params": {"cost": "", "life": int(m.get_string(1))}}])]
	if low == "extort":
		return [_kw("SPELL_CAST", {"filter": {"controller": "SOURCE_CONTROLLER"}}, [{"kind": "EXTORT", "params": {}}])]
	m = _match("^bloodthirst (\\d+)$", low)
	if m != null:
		return [_kw("ENTERS_BATTLEFIELD", {}, [{"kind": "PUT_COUNTER", "params": {"self": true, "name": "+1/+1", "n": int(m.get_string(1)), "if_opp_damaged": true}}])]
	m = _match("^bushido (\\d+)$", low)
	if m != null:
		var n := int(m.get_string(1))
		var pump := [{"kind": "PUMP", "params": {"self": true, "power": n, "toughness": n, "duration": "END_OF_TURN"}}]
		return [_kw("BLOCKS", {}, pump), _kw("BECOMES_BLOCKED", {}, pump.duplicate(true))]
	if low == "flanking":
		return [_kw("BECOMES_BLOCKED", {}, [{"kind": "FLANKING", "params": {}}])]
	m = _match("^rampage (\\d+)$", low)
	if m != null:
		return [_kw("BECOMES_BLOCKED", {}, [{"kind": "RAMPAGE", "params": {"n": int(m.get_string(1))}}])]
	if low == "enlist":
		return [_kw("ATTACKS", {}, [{"kind": "ENLIST", "params": {}}])]
	return []


func _kw_trig(trig: Dictionary, effects: Array) -> Dictionary:
	return {"kind": "TRIGGERED", "trigger": trig.duplicate(), "costs": [], "targets": [], "effects": effects, "restrictions": []}


func _kw(on: String, extra: Dictionary, effects: Array) -> Dictionary:
	var trig := {"on": on}
	for k in extra.keys():
		trig[k] = extra[k]
	return {"kind": "TRIGGERED", "trigger": trig, "costs": [], "targets": [], "effects": effects, "restrictions": []}



func _st(spec: Dictionary) -> Dictionary:
	return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": spec}


const TYPE_WORDS := ["artifact", "creature", "enchantment", "land", "planeswalker"]


## Statics the Commander precons use: Auras ("enchanted creature ..."), equipment that counts, conditional
## abilities (celebration, corrupted, eminence), imprint, graveyard statics, flash grants. {} when not one of them.
func _precon_static(line: String) -> Dictionary:
	var m: RegExMatch
	var low := line.to_lower().strip_edges().trim_suffix(".")
	# "Enchanted creature gets +4/+4, has flying and first strike, and is an Angel in addition to its other types."
	m = _match("^enchanted (creature|permanent) (.+)$", low)
	if m != null:
		var spec := _attached_clauses(m.get_string(2), "ENCHANTED")
		if not spec.is_empty():
			return _st(spec)
	# "Equipped creature gets +1/+1 for each artifact and/or enchantment you control."
	m = _match("^equipped creature gets \\+1/\\+1 for each (artifact and/or enchantment|artifact|creature|enchantment|land|equipment)s? you control$", low)
	if m != null:
		var per := {"controller": "SOURCE_CONTROLLER"}
		if m.get_string(1) == "artifact and/or enchantment":
			per["type_any"] = ["artifact", "enchantment"]
		elif m.get_string(1) == "equipment":
			per["subtype"] = "Equipment"
		else:
			per["type"] = m.get_string(1)
		return _st({"scope": "EQUIPPED", "power": 1, "toughness": 1, "per": per})
	# "Equipped creature gets +X/+X, where X is the greatest mana value among your commanders."
	if _match("^equipped creature gets \\+x/\\+x, where x is the greatest mana value among your commanders$", low) != null:
		return _st({"scope": "EQUIPPED", "power": 1, "toughness": 1, "x_commander_mv": true})
	# Celebration: "As long as two or more nonland permanents entered the battlefield under your control this turn,
	# ~ is a Dragon with base power and toughness 4/4, flying, and "{R}: Dragons you control get +1/+0 until end of turn.""
	m = _match("^as long as (two|three|\\d+) or more nonland permanents entered the battlefield under your control this turn, ~ (.+)$", line.strip_edges().trim_suffix("."))
	if m != null:
		var cspec := _self_becomes(m.get_string(2))
		if not cspec.is_empty():
			(cspec["static"] as Dictionary)["condition"] = {"celebration": _num(m.get_string(1))}
			return cspec
	# Corrupted: "As long as an opponent has three or more poison counters, creatures you control with toxic have lifelink."
	m = _match("^as long as an opponent has (three|\\d+) or more poison counters, creatures you control with ([a-z]+) have ([a-z ,]+)$", low)
	if m != null:
		var kwc := _keywords(m.get_string(3))
		if not kwc.is_empty():
			return _st({"scope": "ALL", "query": {"controller": "SOURCE_CONTROLLER", "type": "creature", "keyword": _cap(m.get_string(2))},
				"keywords": kwc, "condition": {"opp_poison_min": _num(m.get_string(1))}})
	# Eminence: "As long as ~ is in the command zone or on the battlefield, other Sphinx spells you cast cost {1} less to cast."
	m = _match("^as long as ~ is in the command zone or on the battlefield, (other )?([a-z]+) spells you cast cost \\{(\\d)\\} less to cast$", low)
	if m != null:
		var ef := {"type": "creature"} if m.get_string(2) == "creature" else {"subtype": _cap(m.get_string(2))}
		if m.get_string(1) != "":
			ef["other"] = true
		return _st({"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(3)), "filter": ef}, "command_zone": true})
	# Imprint (Duplicant): it has the power, toughness and creature types of the last creature card exiled with it.
	if _match("^as long as a card exiled with ~ is a creature card, ~ has the power, toughness, and creature types of the last creature card exiled with (?:it|~)\\. it's still an? [a-z]+$", low) != null:
		return _st({"scope": "SELF", "imprint_pt": true})
	# "Other nontoken creatures you control get +1/+1 and have vigilance." / "Other creatures you control with flying have indestructible."
	m = _match("^(other )?(nontoken )?creatures you control( with [a-z]+)? (?:get ([+-]\\d+)/([+-]\\d+)(?: and (?:have|gain) ([a-z ,]+?))?|(?:have|gain) ([a-z ,]+?))$", low)
	if m != null and (m.get_string(2) != "" or m.get_string(3) != ""):
		var kt := m.get_string(6) if m.get_string(6) != "" else m.get_string(7)
		var kws := _keywords(kt) if kt != "" else []
		if kt != "" and kws.is_empty():
			return {}
		var q := {"controller": "SOURCE_CONTROLLER", "type": "creature"}
		if m.get_string(2) != "":
			q["nontoken"] = true
		if m.get_string(3) != "":
			q["keyword"] = _cap(m.get_string(3).trim_prefix(" with "))
		var sp := {"scope": "OTHERS" if m.get_string(1) != "" else "ALL", "query": q}
		if m.get_string(4) != "":
			sp["power"] = int(m.get_string(4))
			sp["toughness"] = int(m.get_string(5))
		if not kws.is_empty():
			sp["keywords"] = kws
		return _st(sp)
	# Anger: "As long as ~ is in your graveyard and you control a Mountain, creatures you control have haste."
	m = _match("^as long as ~ is in your graveyard and you control an? ([a-z]+), creatures you control have ([a-z ,]+)$", low)
	if m != null:
		var kwg := _keywords(m.get_string(2))
		if not kwg.is_empty():
			return _st({"scope": "ALL", "query": {"controller": "SOURCE_CONTROLLER", "type": "creature"}, "keywords": kwg,
				"from_graveyard": true, "condition": {"controls": {"controller": "SOURCE_CONTROLLER", "subtype": _cap(m.get_string(1))}}})
	# "You may cast green creature spells as though they had flash." (CR 702.8 via a static, Yeva / Shimmer Myr)
	m = _match("^you may cast (?:(white|blue|black|red|green) )?(creature|artifact|enchantment|instant|sorcery) spells as though they had flash$", low)
	if m != null:
		var fq := {"type": m.get_string(2)}
		if m.get_string(1) != "":
			fq["color"] = COLOR_LETTERS[m.get_string(1)]
		return _st({"scope": "SELF", "flash_for": fq})
	return {}


## The clauses after "enchanted creature" / "equipped creature": "gets +4/+4, has flying and first strike, and is an
## Angel in addition to its other types", "loses all abilities and is a green Elk creature with base power and
## toughness 3/3", "is a colorless land with "{T}: Add {C}" and loses all other card types and abilities",
## "is a Vehicle artifact with crew 5 and it loses all other card types", "doesn't untap during its controller's untap
## step unless that player is the monarch". {} when a clause isn't understood.
func _attached_clauses(text: String, scope: String) -> Dictionary:
	var t := text.strip_edges().trim_suffix(".")
	var spec := {"scope": scope}
	var m: RegExMatch
	m = _match("^loses all abilities and is an? (white |blue |black |red |green |colorless )?([a-z]+) creature with base power and toughness (\\d+)/(\\d+)$", t)
	if m != null:
		spec["lose_abilities"] = true
		spec["set_type_line"] = "Creature — %s" % _cap(m.get_string(2))
		spec["base_pt"] = [int(m.get_string(3)), int(m.get_string(4))]
		return spec
	m = _match("^is a colorless land with \"\\{t\\}: add (\\{[wubrgc]\\})\" and loses all other card types and abilities$", t)
	if m != null:
		spec["lose_abilities"] = true
		spec["set_type_line"] = "Land"
		spec["grant_mana"] = m.get_string(1).to_upper()
		return spec
	m = _match("^is a vehicle artifact with crew (\\d+) and it loses all other card types$", t)
	if m != null:
		spec["set_type_line"] = "Artifact — Vehicle"
		spec["grant_kw"] = {"crew": int(m.get_string(1))}
		return spec
	if _match("^doesn't untap during its controller's untap step unless that player is the monarch$", t) != null:
		spec["doesnt_untap"] = true
		spec["unless_monarch"] = true
		return spec
	if _match("^doesn't untap during its controller's untap step$", t) != null:
		spec["doesnt_untap"] = true
		return spec
	if _match("^can't attack or block$", t) != null:
		spec["cant_attack_block"] = true
		return spec
	## A list of "gets +N/+N", "has <keywords>", "is a <Type> in addition to its other types".
	var parts: Array = []
	for p in t.replace(", and ", ", ").split(", "):
		var ps := str(p).strip_edges()
		if ps.begins_with("and "):
			ps = ps.substr(4)
		parts.append(ps)
	for part in parts:
		var pt := str(part)
		var g := _match("^gets ([+-]\\d+)/([+-]\\d+)(?: and has ([a-z ]+))?$", pt)
		if g != null:
			spec["power"] = int(g.get_string(1))
			spec["toughness"] = int(g.get_string(2))
			if g.get_string(3) != "":
				var k0 := _keywords(g.get_string(3))
				if k0.is_empty():
					return {}
				spec["keywords"] = k0
			continue
		var h := _match("^(?:has|gains) ([a-z ]+)$", pt)
		if h != null:
			var k1 := _keywords(h.get_string(1))
			if k1.is_empty():
				return {}
			var have: Array = spec.get("keywords", [])
			have.append_array(k1)
			spec["keywords"] = have
			continue
		var ty := _match("^is an? ([a-z]+) in addition to its other types$", pt)
		if ty != null:
			spec["add_subtypes"] = [_cap(ty.get_string(1))]
			continue
		return {}
	return spec if spec.size() > 1 else {}


## "~ is a Dragon with base power and toughness 4/4, flying, and "{R}: Dragons you control get +1/+0 until end of turn.""
## -> a SELF static (and the quoted ability, granted while the condition holds). {} when not understood.
func _self_becomes(text: String) -> Dictionary:
	var m := _match("^is an? ([a-z]+) with base power and toughness (\\d+)/(\\d+)(?:, ([a-z ]+?))?(?:,? and \"(.+)\")?$", text.strip_edges().trim_suffix("."))
	if m == null:
		return {}
	var spec := {"scope": "SELF", "set_subtypes": [_cap(m.get_string(1))], "base_pt": [int(m.get_string(2)), int(m.get_string(3))]}
	if m.get_string(4) != "":
		var k := _keywords(m.get_string(4))
		if k.is_empty():
			return {}
		spec["char_keywords"] = k
	if m.get_string(5) != "":
		spec["grant_text"] = m.get_string(5).trim_suffix(".")
	return _st(spec)


func _static_line(line: String) -> Dictionary:
	var m: RegExMatch
	var st0 := _precon_static(line)
	if not st0.is_empty():
		return st0
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

	# "As long as your devotion to red and green is less than seven, ~ isn't a creature."
	m = _match("^as long as your devotion to (white|blue|black|red|green) and (white|blue|black|red|green) is less than (\\w+), ~ isn't a creature$", line)
	if m != null and _num(m.get_string(3)) > 0:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {
			"scope": "SELF", "lose_types": ["Creature"],
			"condition": {"devotion_lt": {"colors": [COLOR_LETTERS[m.get_string(1).to_lower()], COLOR_LETTERS[m.get_string(2).to_lower()]], "n": _num(m.get_string(3))}},
		}}
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
	m = _match("^at the beginning of combat on your turn, (.+)$", line)
	if m != null:
		return _trigger_with({"on": "BEGIN_STEP", "step": "BEGIN_COMBAT", "whose": "YOURS"}, m.get_string(1))
	m = _match("^at the beginning of each combat, (.+)$", line)
	if m != null:
		return _trigger_with({"on": "BEGIN_STEP", "step": "BEGIN_COMBAT", "whose": "EACH"}, m.get_string(1))
	m = _match("^(?:when|whenever) (.+?), ((?:you may |if |[a-z~]).+)$", line)
	if m == null:
		return {}
	var header := m.get_string(1)
	var trig := _header(header)
	if trig.is_empty():
		return {}
	var rest := m.get_string(2)
	## Intervening "if" clauses (CR 603.4): checked when the trigger would go on the stack.
	var gm := _match("^if the gift was promised, (.+)$", rest)
	if gm != null:
		trig["if_gift"] = true
		rest = gm.get_string(1)
	var pm := _match("^if you attacked with creatures with total power (\\d+) or greater this combat, (.+)$", rest)
	if pm != null:
		trig["attack_power_min"] = int(pm.get_string(1))
		rest = pm.get_string(2)
	var lm := _match("^if (?:you control|it's attacking) (?:your commander|the player with the most life or tied for most life), (.+)$", rest)
	if lm != null:
		if rest.to_lower().contains("commander"):
			trig["if_controls_commander"] = true
		else:
			trig["if_defender_most_life"] = true
		rest = lm.get_string(1)
	return _trigger_with(trig, rest)


func _trigger_with(trig: Dictionary, effect_text: String) -> Dictionary:
	var reader := OracleIr.new()
	reader._self_it = str(trig.get("scope", "SELF")) == "SELF"
	if not reader._read_effects(effect_text):
		return {}
	return {"kind": "TRIGGERED", "trigger": trig, "costs": [], "targets": reader._targets, "effects": reader._effects, "restrictions": []}


## The trigger condition: "~ enters", "another Dinosaur you control enters", "~ dies", ...
func _header(h: String) -> Dictionary:
	var m: RegExMatch
	## "When enchanted creature dies" (Angelic Destiny): watched by the Aura, even from the graveyard.
	if _match("^enchanted creature dies$", h) != null:
		return {"on": "DIES", "scope": "ENCHANTED"}
	## "Whenever this creature mutates" (CR 702.140d).
	if _match("^(?:~|this creature) mutates$", h) != null:
		return {"on": "MUTATES"}
	if _match("^you win a clash$", h) != null:
		return {"on": "CLASH_WON", "scope": "YOU"}
	## "Whenever you cast your first noncreature spell each turn" (CR 603.2): only the first such spell counts.
	m = _match("^you cast your first (noncreature|creature|instant or sorcery|instant|sorcery|artifact|enchantment) spell each turn$", h)
	if m != null:
		var cf := _cast_filter(m.get_string(1))
		if not cf.is_empty():
			(cf["filter"] as Dictionary)["nth"] = 1
			return cf
	m = _match("^an opponent casts an? (instant or sorcery|creature|noncreature|instant|sorcery|artifact|enchantment) spell$", h)
	if m != null:
		var of := _cast_filter(m.get_string(1))
		if not of.is_empty():
			(of["filter"] as Dictionary)["controller"] = "OPPONENT"
			return of
	if _match("^a commander you control enters(?: the battlefield)?(?: or attacks)?$", h) != null:
		return {"on": "ENTERS_BATTLEFIELD", "scope": "ANY", "filter": {"controller": "SOURCE_CONTROLLER", "commander": true}}
	m = _match("^another nontoken ([a-z]+) you control enters(?: the battlefield)?$", h)
	if m != null:
		var nf := _noun_filter(m.get_string(1))
		nf["nontoken"] = true
		return {"on": "ENTERS_BATTLEFIELD", "scope": "OTHER", "filter": nf}
	m = _match("^an? nontoken ([a-z]+) you control dies$", h)
	if m != null:
		var df := _noun_filter(m.get_string(1))
		df["nontoken"] = true
		return {"on": "DIES", "scope": "ANY", "filter": df}
	if _match("^a creature attacks you or a planeswalker you control$", h) != null:
		return {"on": "ATTACKS", "scope": "ANY", "filter": {"controller": "OPPONENT", "type": "creature"}}
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
	m = _match("^an? ([a-z]+) you control is dealt damage$", h)
	if m != null:
		return {"on": "DAMAGED", "scope": "ANY", "filter": _noun_filter(m.get_string(1))}
	if _match("^one or more creatures you control with trample deal combat damage to a player$", h) != null:
		return {"on": "TRAMPLE_DAMAGE"}
	if _match("^an opponent activates an ability of a creature or land that isn't a mana ability$", h) != null:
		return {"on": "OPP_ACTIVATES"}
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

## Whole-text effects that don't split into sentences: reveal-and-cast, exile-and-cast.
func _whole(effect_text: String) -> bool:
	var t := effect_text.strip_edges().trim_suffix(".")
	if _match("^reveal the top card of your library\\. if it's a creature card that shares a creature type with a creature you control, you may cast it without paying its mana cost\\. if you don't cast it, put it on the bottom of your library$", t) != null:
		_effects.append({"kind": "REVEAL_TOP_CAST_FREE", "params": {}})
		return true
	if _match("^exile the top card of each player's library, then you may cast any number of spells from among those cards without paying their mana costs$", t) != null:
		_effects.append({"kind": "EXILE_TOP_EACH_CAST_FREE", "params": {}})
		return true
	return false


## "Choose one — • ... • ..." spells: each bullet is read as a mode; the choice is made as the spell resolves.
func _read_modal(def: CardDefinition, text: String) -> Dictionary:
	var header := ""
	var bullets: Array = []
	for raw in text.split("\n"):
		var l := str(raw).strip_edges()
		if l == "":
			continue
		if l.begins_with("•"):
			bullets.append(l.substr(1).strip_edges())
		elif KeywordLines.is_keyword_line(l) or KeywordDb.line_is_handled(l):
			continue  ## "Escalate {G}" / "Gift a card" above the modes are cast options, not effects
		elif header == "" and bullets.is_empty():
			header = l
		else:
			return {}
	var hm := _match("^choose (one or more|one or both|one|two|three)\\b(.*)$", header)
	if hm == null or bullets.size() < 2:
		return {}
	var how := hm.get_string(1).to_lower()
	var count := 2 if how == "one or both" else (bullets.size() if how == "one or more" else _num(hm.get_string(1)))
	var rest := hm.get_string(2).to_lower()
	var modes: Array = []
	for b in bullets:
		var rd := OracleIr.new()
		if not rd._read_effects(str(b)):
			return {}
		modes.append({"text": str(b), "effects": rd._effects, "targets": rd._targets})
	var params := {"choose": 1 if how == "one or both" or how == "one or more" else count, "modes": modes}
	if how == "one or both" or how == "one or more":
		params["any_up_to"] = count
	if rest.contains("same mode more than once"):
		params["repeat"] = true
	if rest.contains("you control a commander"):
		params["both_if_commander"] = true
	var costs: Array = []
	if def.mana_cost != "":
		costs.append({"kind": "MANA", "mana": def.mana_cost})
	return {
		"ability_id": "%s_spell" % _snake(def.name),
		"kind": "SPELL",
		"costs": costs,
		"targets": [],
		"effects": [{"kind": "MODAL", "params": params}],
		"text": def.oracle_text,
	}


## Reads each sentence of an ability's effect text. False if any is not understood or nothing was read.
func _read_effects(effect_text: String) -> bool:
	if _whole(effect_text):
		return true
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
		if s.to_lower().begins_with("you may "):
			s = s.substr(8)
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
		## "Waterbend {N}" (CR 701.67): N generic, payable by tapping artifacts and creatures you control.
		var wm := _match("^waterbend \\{(\\d+)\\}$", p.to_lower())
		if wm != null:
			costs.append({"kind": "MANA", "mana": "{%s}" % wm.get_string(1), "from": "WATERBEND"})
			continue
		var lm := _match("^pay (\\d+) life$", p)
		if lm != null:
			costs.append({"kind": "PAY_LIFE", "mana": lm.get_string(1)})
			continue
		var cm := _match("^put an? ([a-z0-9+/-]+) counter on ~$", p)
		if cm != null:
			costs.append({"kind": "ADD_COUNTER", "mana": cm.get_string(1).to_lower()})
			continue
		if _match("^(\\{[0-9WUBRGCX/]+\\})+$", p) == null:
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
	if text.contains("•"):
		return _read_modal(def, text)
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
			## Keyword lines (flashback, kicker, convoke ...) are cast options, not effects.
			if KeywordDb.line_is_handled(s) or KeywordLines.is_keyword_line(s):
				continue
			## "..., then shuffle" ends many searches; the shuffle is part of the search itself.
			if s.to_lower().begins_with("search your library") and s.to_lower().ends_with(", then shuffle"):
				s = s.substr(0, s.length() - 14)
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


## What an Aura can enchant ("creature", "creature or Vehicle", "creature, land, or planeswalker") as a target query.
func _enchant_query(what: String) -> Dictionary:
	var w := what.strip_edges()
	var ctrl := ""
	if w.ends_with(" you control"):
		ctrl = "SOURCE_CONTROLLER"
		w = w.trim_suffix(" you control")
	elif w.ends_with(" an opponent controls") or w.ends_with(" you don't control"):
		ctrl = "OPPONENT"
		w = w.trim_suffix(" an opponent controls").trim_suffix(" you don't control")
	var q := {}
	if w == "permanent":
		pass
	elif w in TYPE_WORDS:
		q["type"] = w
	else:
		var types: Array = []
		var any: Array = []
		for part in w.replace(", or ", ",").replace(" or ", ",").split(","):
			var t := str(part).strip_edges()
			if t in TYPE_WORDS:
				types.append(t)
				any.append({"type": t})
			elif t == "vehicle":
				any.append({"subtype": "Vehicle"})
			else:
				return {}
		q["any"] = any
	if ctrl != "":
		q["controller"] = ctrl
	return q


## Effect sentences of the precon keywords and keyword actions (behold, clash, empower, double, gift, loyalty
## abilities ...). False when the sentence is none of them.
func _precon_sentence(s: String) -> bool:
	var m: RegExMatch
	var low := s.to_lower().strip_edges()
	if _action_sentence(low):
		return true
	# Behold (CR 701.4): "behold a Dragon" - choose one you control or reveal one from your hand. "If you do" follows.
	m = _match("^behold an? ([a-z]+)$", low)
	if m != null:
		_pay_links += 1
		_effects.append({"kind": "BEHOLD", "params": {"subtype": _cap(m.get_string(1)), "link": "paid_%d" % _pay_links}})
		return true
	# Clash (CR 701.23).
	if _match("^clash with (?:defending player|an opponent|target opponent)$", low) != null:
		_effects.append({"kind": "CLASH", "params": {}})
		return true
	# Empower <name> N (Reality Fracture): loyalty counters on your <name> token, made first if you have none.
	m = _match("^empower ([a-z]+) (\\d+)$", low)
	if m != null:
		_effects.append({"kind": "EMPOWER", "params": {"name": _cap(m.get_string(1)), "n": int(m.get_string(2))}})
		return true
	# Double (CR 701.10): "double the power and toughness of each creature you control until end of turn".
	if _match("^double the power and toughness of each creature you control until end of turn$", low) != null:
		_effects.append({"kind": "DOUBLE_PT", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature"}}})
		return true
	# "Put a card from your hand on the bottom (top) of your library." (after drawing, Jace / Aminatou)
	m = _match("^put (a|one|two) cards? from your hand on (?:the )?(top|bottom) of your library$", low)
	if m != null:
		_effects.append({"kind": "HAND_TO_LIBRARY", "params": {"n": _num(m.get_string(1)), "where": m.get_string(2)}})
		return true
	# Jace, Multiverse Architect -3: "Reveal cards from the top of your library until you reveal a creature or
	# planeswalker card." then "Put that card onto the battlefield (into your hand) and the rest on the bottom ..."
	m = _match("^reveal cards from the top of your library until you reveal an? ((?:creature|planeswalker|artifact|land|nonland)(?: or (?:creature|planeswalker|artifact|land))?) card$", low)
	if m != null:
		var tys: Array = []
		for t in m.get_string(1).split(" or "):
			tys.append(str(t))
		_effects.append({"kind": "REVEAL_UNTIL_PUT", "params": {"types": tys, "to": "HAND"}})
		return true
	m = _match("^put that card (onto the battlefield|into your hand) and the rest on the bottom of your library in a random order$", low)
	if m != null and not _effects.is_empty() and str((_effects[_effects.size() - 1] as Dictionary).get("kind", "")) == "REVEAL_UNTIL_PUT":
		((_effects[_effects.size() - 1] as Dictionary)["params"] as Dictionary)["to"] = "BATTLEFIELD" if m.get_string(1).contains("battlefield") else "HAND"
		return true
	# "Exile another target permanent you own, then return it to the battlefield under your control." (blink)
	m = _match("^exile (another target (?:nonland )?permanent you own|another target creature you control|target creature you control), then return (?:it|that card) to the battlefield under (?:your|its owner's) control$", low)
	if m != null:
		var bt := _target(m.get_string(1).replace(" you own", " you control"))
		if bt < 0:
			return false
		_effects.append({"kind": "FLICKER", "params": {"target": bt}})
		return true
	# "Exile another target planeswalker or creature you control." (Jace -3 first sentence)
	m = _match("^exile another target (planeswalker or creature|creature or planeswalker) you control$", low)
	if m != null:
		var et := _add_target("PERMANENT", {"type_any": ["creature", "planeswalker"], "controller": "SOURCE_CONTROLLER", "other": true})
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": et, "to": "EXILE"}})
		return true
	# Elspeth -3: "Destroy all creatures with power 4 or greater."
	m = _match("^destroy all creatures with power (\\d+) or greater$", low)
	if m != null:
		_effects.append({"kind": "DESTROY_ALL_POWER", "params": {"min": int(m.get_string(1))}})
		return true
	# Emblems (CR 114): "You get an emblem with "Creatures you control get +2/+2 and have flying.""
	m = _match("^you get an emblem with \"creatures you control get \\+(\\d+)/\\+(\\d+)(?: and have ([a-z ,]+))?\\.?\"$", low)
	if m != null:
		var ek := _keywords(m.get_string(3)) if m.get_string(3) != "" else []
		if m.get_string(3) != "" and ek.is_empty():
			return false
		_effects.append({"kind": "EMBLEM", "params": {"power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "keywords": ek}})
		return true
	# Gift: "If the gift was promised, <effect>" inside a spell.
	m = _match("^if the gift was promised, return target creature card from your graveyard to your hand$", low)
	if m != null:
		_effects.append({"kind": "RETURN_CARD_CHOICE", "params": {"type": "creature", "to": "HAND", "if_gift": true}})
		return true
	m = _match("^if the gift was promised, (.+)$", s)
	if m != null:
		var ge := _effects.size()
		if not _clause(m.get_string(1)):
			return false
		for gi in range(ge, _effects.size()):
			((_effects[gi] as Dictionary)["params"] as Dictionary)["if_gift"] = true
		return true
	# Consumed by Greed: "Target opponent sacrifices a creature with the greatest power among creatures they control."
	if _match("^target opponent sacrifices a creature with the greatest power among creatures they control$", low) != null:
		var op := _add_target("PLAYER", {"opponent": true})
		_effects.append({"kind": "SACRIFICE_GREATEST", "params": {"target": op}})
		return true
	# Pack tactics payoff: "put a Dragon creature card from your hand onto the battlefield tapped and attacking".
	m = _match("^(?:you may )?put an? ([a-z]+) creature card from your hand onto the battlefield tapped and attacking$", low)
	if m != null:
		_effects.append({"kind": "PUT_FROM_HAND_ATTACKING", "params": {"subtype": _cap(m.get_string(1))}})
		return true
	# Angelic Destiny: "return ~ to its owner's hand" (from the graveyard, after what it enchanted died).
	if _match("^return ~ to its owner's hand$", low) != null:
		_effects.append({"kind": "RETURN_SELF_HAND", "params": {}})
		return true
	# Hit the Mother Lode: "If the discovered card's mana value is less than 10, create a number of tapped Treasure
	# tokens equal to the difference."
	m = _match("^if the discovered card's mana value is less than (\\d+), create a number of tapped treasure tokens equal to the difference$", low)
	if m != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": "treasure", "tapped": true, "count": {"expr": "DISCOVER_DIFF", "n": int(m.get_string(1))}}})
		return true
	# Sunfall: "Exile all creatures." / "Incubate X, where X is the number of creatures exiled this way."
	if _match("^exile all creatures$", low) != null:
		_effects.append({"kind": "EXILE_ALL", "params": {"query": {"type": "creature"}}})
		return true
	if _match("^incubate x, where x is the number of creatures exiled this way$", low) != null:
		_effects.append({"kind": "INCUBATE", "params": {"n": {"expr": "EXILED_COUNT"}}})
		return true
	# "<Dragons> you control get +1/+0 until end of turn." (a creature type)
	m = _match("^([a-z]+)s you control get ([+-]\\d+)/([+-]\\d+) until end of turn$", low)
	if m != null and m.get_string(1) != "creature":
		_effects.append({"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature", "subtype": _cap(m.get_string(1))},
			"power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "duration": "END_OF_TURN"}})
		return true
	# "Attacking creatures with flying get +1/+1 until end of turn." (Inniaz)
	m = _match("^attacking creatures( with [a-z]+)? get ([+-]\\d+)/([+-]\\d+) until end of turn$", low)
	if m != null:
		var aq := {"type": "creature", "attacking": true}
		if m.get_string(1) != "":
			aq["keyword"] = _cap(m.get_string(1).trim_prefix(" with "))
		_effects.append({"kind": "PUMP", "params": {"each": aq, "power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "duration": "END_OF_TURN"}})
		return true
	# "Its controller creates two Treasure tokens." / "Its controller investigates." (the target's controller)
	m = _match("^its controller creates (a|an|one|two|three|four|\\d+) (treasure|food|clue) tokens?$", low)
	if m != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": m.get_string(2), "count": _num(m.get_string(1)), "for": "TARGET_CONTROLLER"}})
		return true
	if _match("^its controller investigates$", low) != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": "clue", "count": 1, "for": "TARGET_CONTROLLER"}})
		return true
	# "Mill two cards." (no subject: you)
	m = _match("^mill (a|an|one|two|three|four|five|six|seven|eight|nine|ten|\\d+) cards?$", low)
	if m != null:
		_effects.append({"kind": "MILL", "params": {"n": _num(m.get_string(1)), "who": "CONTROLLER"}})
		return true
	# "Return target card from your graveyard to your hand." (any card)
	if _match("^return target card from your graveyard to your hand$", low) != null:
		var rc := _add_target("CARD_IN_ZONE", {"zone": "GRAVEYARD", "controller": "SOURCE_CONTROLLER"})
		_effects.append({"kind": "RETURN_FROM_GRAVEYARD", "params": {"target": rc, "to": "HAND"}})
		return true
	# "You gain life equal to that card's mana value." (after returning it)
	if _match("^you gain life equal to that card's mana value$", low) != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "TARGET_MV", "target": 0}}})
		return true
	# "Exile ~." at the end of a spell: it goes to exile as it resolves.
	if _match("^exile ~$", low) != null:
		_effects.append({"kind": "SELF_EXILE_ON_RESOLVE", "params": {}})
		return true
	# "~ deals N damage to each creature and each opponent." (The Elder Dragon War I)
	m = _match("^~ deals (\\d+) damage to each creature and each opponent$", low)
	if m != null:
		_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": int(m.get_string(1)), "query": {"type": "creature"}}})
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(1)), "who": "EACH_OPPONENT"}})
		return true
	# "Discard any number of cards, then draw that many cards." (The Elder Dragon War II)
	if _match("^discard any number of cards, then draw that many cards$", low) != null:
		_effects.append({"kind": "DISCARD_ANY_DRAW", "params": {}})
		return true
	# "Tap enchanted creature." (Fall from Favor)
	if _match("^tap enchanted (?:creature|permanent)$", low) != null:
		_effects.append({"kind": "TAP_ATTACHED", "params": {}})
		return true
	# "Draw a card for each creature you control." / Ferocious "You gain 4 life for each creature you control with power 4 or greater."
	m = _match("^(?:you )?draw a card for each creature you control$", low)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": {"query": {"controller": "SOURCE_CONTROLLER", "type": "creature"}}}})
		return true
	m = _match("^you gain (\\d+) life for each creature you control with power (\\d+) or greater$", low)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"query": {"controller": "SOURCE_CONTROLLER", "type": "creature", "power_min": int(m.get_string(2))}, "mult": int(m.get_string(1))}}})
		return true
	# Skrelv's Hive: "create a 1/1 colorless Phyrexian Mite artifact creature token with toxic 1 and "~ can't block.""
	m = _match("^create (a|an|one|two) (\\d+)/(\\d+) (colorless|white|blue|black|red|green) ([a-z ]+?) (artifact )?creature tokens? with toxic (\\d+) and \"(?:~|this token|this creature) can't block\\.?\"$", low)
	if m != null:
		var colors_m := [] if m.get_string(4) == "colorless" else [COLOR_LETTERS[m.get_string(4)]]
		var subs_m: Array = []
		for w in m.get_string(5).split(" "):
			subs_m.append(_cap(str(w)))
		_effects.append({"kind": "CREATE_TOKEN", "params": {"count": _num(m.get_string(1)), "spec": {"subtypes": subs_m, "colors": colors_m,
			"p": m.get_string(2), "t": m.get_string(3), "artifact": m.get_string(6) != "", "toxic": int(m.get_string(7)), "cant_block": true}}})
		return true
	# Plan for All Outcomes: "the owner of up to one other target nonland permanent puts it on their choice of the top or
	# bottom of their library"
	if _match("^the owner of up to one other target nonland permanent puts it on their choice of the top or bottom of their library$", low) != null:
		var tk := _target("up to one another target nonland permanent")
		if tk < 0:
			tk = _add_target("PERMANENT", {"not_type": "land", "other": true})
			_targets[tk]["optional"] = true
		_effects.append({"kind": "TUCK", "params": {"target": tk}})
		return true
	# Fatehold Charm: "Return target spell or creature to its owner's hand."
	if _match("^return target spell or creature to its owner's hand$", low) != null:
		var sc := _add_target("SPELL_OR_PERMANENT", {"type": "creature"})
		_effects.append({"kind": "BOUNCE_ANY", "params": {"target": sc}})
		return true
	# "Each player mills N cards." / gift-free mills.
	m = _match("^each player mills (a|an|one|two|three|four|five|six|seven|eight|nine|ten|\\d+) cards?$", low)
	if m != null:
		_effects.append({"kind": "MILL", "params": {"n": _num(m.get_string(1)), "who": "EACH_PLAYER"}})
		return true
	return false


## Returns true when the sentence was understood and its effects were queued.
## Keyword actions (CR 701) written as a sentence: venture, the initiative, the Ring, triple, exchange, regenerate,
## transform, detain, monstrosity, exert, time travel, forage, manifest dread, endure, harness, airbend, earthbend,
## blight.
func _action_sentence(low: String) -> bool:
	var m: RegExMatch
	m = _match("^venture into (the dungeon|undercity)$", low)
	if m != null:
		_effects.append({"kind": "VENTURE", "params": {"dungeon": "undercity" if m.get_string(1) == "undercity" else ""}})
		return true
	if _match("^(?:you )?take the initiative$", low) != null:
		_effects.append({"kind": "TAKE_INITIATIVE", "params": {}})
		return true
	if _match("^the ring tempts you$", low) != null:
		_effects.append({"kind": "RING_TEMPTS", "params": {}})
		return true
	m = _match("^triple (?:the power and toughness of|~'s power and toughness|its power and toughness)(?: (target [a-z ]+?))?(?: until end of turn)?$", low)
	if m != null:
		if m.get_string(1) != "":
			var tt := _target(m.get_string(1))
			if tt < 0:
				return false
			_effects.append({"kind": "TRIPLE_PT", "params": {"target": tt, "power": true, "toughness": true}})
			return true
	m = _match("^exchange control of (target [a-z ]+?) and (target [a-z ]+)$", low)
	if m != null:
		var a := _target(m.get_string(1))
		var b := _target(m.get_string(2))
		if a < 0 or b < 0:
			return false
		_effects.append({"kind": "EXCHANGE_CONTROL", "params": {"a": a, "b": b}})
		return true
	m = _match("^exchange life totals with (target (?:player|opponent))$", low)
	if m != null:
		var lt := _target(m.get_string(1))
		if lt < 0:
			return false
		_effects.append({"kind": "EXCHANGE_LIFE", "params": {"target": lt}})
		return true
	m = _match("^(regenerate|transform|detain|heal|airbend) (~|target [a-z ]+)$", low)
	if m != null:
		var kind := m.get_string(1).to_upper()
		if m.get_string(2) == "~":
			_effects.append({"kind": kind, "params": {"self": true}})
			return true
		var t := _target(m.get_string(2))
		if t < 0:
			return false
		_effects.append({"kind": kind, "params": {"target": t}})
		return true
	m = _match("^monstrosity (\\d+|x)$", low)
	if m != null:
		_effects.append({"kind": "MONSTROSITY", "params": {"n": {"expr": "X"} if m.get_string(1) == "x" else int(m.get_string(1))}})
		return true
	if _match("^(?:you may )?exert ~$", low) != null:
		_effects.append({"kind": "EXERT", "params": {}})
		return true
	for word in ["time travel", "forage", "manifest dread", "harness ~"]:
		if low == word:
			_effects.append({"kind": word.replace(" ~", "").replace(" ", "_").to_upper(), "params": {}})
			return true
	m = _match("^~ endures (\\d+)$", low)
	if m != null:
		_effects.append({"kind": "ENDURE", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^earthbend (\\d+)$", low)
	if m != null:
		var et := _add_target("PERMANENT", {"type": "land", "controller": "SOURCE_CONTROLLER"})
		_effects.append({"kind": "EARTHBEND", "params": {"target": et, "n": int(m.get_string(1))}})
		return true
	m = _match("^blight (\\d+)$", low)
	if m != null:
		_effects.append({"kind": "BLIGHT", "params": {"n": int(m.get_string(1))}})
		return true
	return false


func _sentence(s: String) -> bool:
	var m: RegExMatch
	if _precon_sentence(s):
		return true

	# --- Cards that need their own effects (see engine/abilities/card_effects.gd) ---
	m = _match("^(target creature you control) deals damage equal to its power to each other creature and each opponent$", s)
	if m != null:
		var ci_slot := _target(m.get_string(1))
		if ci_slot < 0:
			return false
		_effects.append({"kind": "POWER_DAMAGE_EACH", "params": {"source": ci_slot}})
		return true
	m = _match("^(?:you )?draw cards equal to the greatest power among (non-human )?creatures you control$", s)
	if m != null:
		var gq := {"controller": "SOURCE_CONTROLLER", "type": "creature"}
		if m.get_string(1) != "":
			gq["not_subtype"] = "Human"
		_effects.append({"kind": "DRAW", "params": {"n": {"expr": "GREATEST_POWER", "query": gq}}})
		return true
	m = _match("^cast a spell with mana value (\\d+) or less from your hand without paying its mana cost$", s)
	if m != null:
		_effects.append({"kind": "CAST_FREE_FROM_HAND", "params": {"max_mv": int(m.get_string(1))}})
		return true
	m = _match("^pay (\\{[0-9WUBRGC]+\\}(?:\\{[0-9WUBRGC]+\\})*)$", s)
	if m != null:
		_pay_links += 1
		_effects.append({"kind": "PAY_OPTIONAL", "params": {"cost": m.get_string(1).to_upper(), "link": "paid_%d" % _pay_links}})
		return true
	m = _match("^(?:if you do|when you do), (.+)$", s)
	if m != null and _pay_links > 0:
		var pe := _effects.size()
		if not _clause(m.get_string(1)):
			return false
		for i3 in range(pe, _effects.size()):
			((_effects[i3] as Dictionary)["params"] as Dictionary)["if_link"] = "paid_%d" % _pay_links
		return true
	m = _match("^(target creature) can't be blocked this turn$", s)
	if m != null:
		var ub := _target(m.get_string(1))
		if ub < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": ub, "keywords": ["Unblockable"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^(target .+?) gets \\+x/\\+0 and gains ([a-z ,]+) until end of turn$", s)
	if m != null:
		var xk := _keywords(m.get_string(2))
		var xs := _target(m.get_string(1))
		if xk.is_empty() or xs < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": xs, "power": {"expr": "X"}, "toughness": 0, "keywords": xk, "duration": "END_OF_TURN"}})
		return true
	m = _match("^search your library for up to two basic land cards that share a land type, put them onto the battlefield tapped(?:, then shuffle)?$", s)
	if m != null:
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filter": {"basic_land": true}, "n": 2, "to": "BATTLEFIELD", "tapped": true, "same_type": true}})
		return true
	m = _match("^~ gains your choice of ([a-z]+), ([a-z]+), or ([a-z]+) until end of turn$", s)
	if m != null:
		var opts: Array = []
		for gi in [1, 2, 3]:
			var w := m.get_string(gi).to_lower()
			if not w in KEYWORDS:
				return false
			opts.append(_cap(w))
		_effects.append({"kind": "GAIN_KEYWORD_CHOICE", "params": {"options": opts}})
		return true
	m = _match("^return target creature card of the chosen type from your graveyard to the battlefield with a finality counter on it$", s)
	if m != null:
		var fi := _targets.size()
		_targets.append({"id": fi, "kind": "CARD_IN_ZONE", "count": 1, "query": {"zone": "GRAVEYARD", "controller": "SOURCE_CONTROLLER", "type": "creature", "subtype": "$chosen"}})
		_effects.append({"kind": "RETURN_FROM_GRAVEYARD", "params": {"target": fi, "to": "BATTLEFIELD", "finality": true}})
		return true
	m = _match("^(another target creature you control) gains haste and gets \\+x/\\+x until end of turn, where x is that creature's power$", s)
	if m != null:
		var xs2 := _target(m.get_string(1))
		if xs2 < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": xs2, "power": {"expr": "TARGET_POWER", "target": xs2}, "toughness": {"expr": "TARGET_POWER", "target": xs2}, "keywords": ["Haste"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^have it become a copy of (another target .+?), except its name is ~ and it has this ability$", s)
	if m != null:
		var cs := _target(m.get_string(1))
		if cs < 0:
			return false
		_effects.append({"kind": "BECOME_COPY", "params": {"target": cs}})
		return true
	m = _match("^(?:~|it) deals that much damage to any target that isn't an? ([a-z]+)$", s)
	if m != null:
		var nd := _add_target("ANY_TARGET", {"not_subtype": _cap(m.get_string(1))})
		if nd < 0:
			return false
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": {"expr": "EVENT_AMOUNT"}, "target": nd, "from_trigger_object": true}})
		return true
	m = _match("^(?:~|it) deals (\\d+) damage to it$", s)
	if m != null:
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(1)), "trigger_object": true}})
		return true
	m = _match("^if a ([a-z]+) is dealt damage this way, ~ gets ([+-]\\d+)/([+-]\\d+) until end of turn$", s)
	if m != null:
		_effects.append({"kind": "PUMP", "params": {"self": true, "power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "duration": "END_OF_TURN", "if_trigger_subtype": _cap(m.get_string(1))}})
		return true
	m = _match("^(?:you may )?exile target card from a graveyard$", s)
	if m != null:
		var gs := _targets.size()
		_targets.append({"id": gs, "kind": "CARD_IN_ZONE", "count": 1, "optional": true, "query": {"zone": "GRAVEYARD"}})
		_effects.append({"kind": "EXILE_CARD", "params": {"target": gs}})
		return true
	m = _match("^if an? (creature|noncreature) card is exiled this way, (.+)$", s)
	if m != null:
		var ge := _effects.size()
		if not _clause(m.get_string(2)):
			return false
		for i4 in range(ge, _effects.size()):
			((_effects[i4] as Dictionary)["params"] as Dictionary)["if_exiled_creature" if m.get_string(1).to_lower() == "creature" else "if_exiled_noncreature"] = true
		return true
	m = _match("^put target card with mana value x exiled with ~ into its owner's graveyard$", s)
	if m != null:
		_effects.append({"kind": "GRAVEYARD_EXILED_WITH", "params": {}})
		return true
	m = _match("^you gain x life$", s)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "X"}}})
		return true
	m = _match("^create an? x/x ([a-z ]+?) ([a-z ]+?) creature token with ([a-z]+), where x is the amount of damage those creatures dealt to that player$", s)
	if m != null:
		var colors1 := m.get_string(1).to_lower()
		if not COLOR_LETTERS.has(colors1):
			return false
		var subs1: Array = []
		for w2 in m.get_string(2).split(" ", false):
			subs1.append(_cap(w2))
		var kw1 := _keywords(m.get_string(3))
		if kw1.is_empty():
			return false
		_effects.append({"kind": "CREATE_TOKEN", "params": {"count": 1, "pt_x": true, "spec": {"p": "0", "t": "0", "colors": [COLOR_LETTERS[colors1]], "subtypes": subs1, "keywords": kw1, "artifact": false}}})
		return true

	m = _match("^creatures you control gain lifelink, indestructible, and protection from each color until end of turn$", s)
	if m != null:
		_effects.append({"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature"},
			"keywords": ["Lifelink", "Indestructible", "Protection from white", "Protection from blue", "Protection from black", "Protection from red", "Protection from green"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^non-human creatures you control get ([+-]\\d+)/([+-]\\d+) until end of turn$", s)
	if m != null:
		_effects.append({"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature", "not_subtype": "Human"},
			"power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "duration": "END_OF_TURN"}})
		return true


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
	# Keyword actions: connive, adapt, learn, incubate, support, manifest, cloak, suspect, goad, fateseal.
	if _match("^(?:~|it) connives$|^connive$", s) != null:
		_effects.append({"kind": "CONNIVE", "params": {"n": 1, "self": true}})
		return true
	m = _match("^(target [a-z ]+?) connives$", s)
	if m != null:
		var cslot := _target(m.get_string(1))
		if cslot < 0:
			return false
		_effects.append({"kind": "CONNIVE", "params": {"n": 1, "target": cslot}})
		return true
	m = _match("^adapt (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "ADAPT", "params": {"n": int(m.get_string(1))}})
		return true
	if _match("^learn$", s) != null:
		_effects.append({"kind": "LEARN", "params": {}})
		return true
	m = _match("^incubate (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "INCUBATE", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^support (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "SUPPORT", "params": {"n": int(m.get_string(1))}})
		return true
	if _match("^manifest the top card of your library$", s) != null:
		_effects.append({"kind": "MANIFEST", "params": {"n": 1}})
		return true
	if _match("^cloak the top card of your library$", s) != null:
		_effects.append({"kind": "MANIFEST", "params": {"n": 1, "cloak": true}})
		return true
	m = _match("^suspect (target [a-z ]+)$", s)
	if m != null:
		var sslot := _target(m.get_string(1))
		if sslot < 0:
			return false
		_effects.append({"kind": "SUSPECT", "params": {"target": sslot}})
		return true
	if _match("^suspect (?:~|it)$|^(?:~|it) becomes suspected$", s) != null:
		_effects.append({"kind": "SUSPECT", "params": {"self": true}})
		return true
	m = _match("^goad (target [a-z ]+)$", s)
	if m != null:
		var gslot := _target(m.get_string(1))
		if gslot < 0:
			return false
		_effects.append({"kind": "GOAD", "params": {"target": gslot}})
		return true
	m = _match("^fateseal (\\d+)$", s)
	if m != null:
		_effects.append({"kind": "FATESEAL", "params": {"n": int(m.get_string(1))}})
		return true
	# "If you cast it [from your hand], ..." (CR 601.2): only when the permanent came from a spell.
	m = _match("^if you cast (?:it|~)( from your hand)?, (.+)$", s)
	if m != null:
		var ec := _effects.size()
		if not _clause(m.get_string(2)):
			return false
		for i2 in range(ec, _effects.size()):
			((_effects[i2] as Dictionary)["params"] as Dictionary)["if_cast_from_hand" if m.get_string(1) != "" else "if_cast"] = true
		return true
	# Kicker: "If this spell was kicked, ..." (CR 702.33).
	m = _match("^if (?:~|it|he|she|this spell) was kicked, (.+)$", s)
	if m != null:
		var e0 := _effects.size()
		if not _clause(m.get_string(1)):
			return false
		for i in range(e0, _effects.size()):
			((_effects[i] as Dictionary)["params"] as Dictionary)["if_kicked"] = true
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

	# Draw a card for each other Dinosaur you control (Earthshaker Dreadmaw).
	m = _match("^(?:you )?draw a card for each (other )?([a-z]+) you control$", s)
	if m != null:
		var dq := {"controller": "SOURCE_CONTROLLER", "subtype": _cap(m.get_string(2))}
		if m.get_string(1) != "":
			dq["other"] = true
		_effects.append({"kind": "DRAW", "params": {"n": {"query": dq}}})
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
	var token_for := ""
	if s.to_lower().begins_with("its controller creates "):
		token_for = "TARGET_CONTROLLER"
		s = "create " + s.substr(23)
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
		var tparams := {"spec": spec, "count": x_count if x_count != null else _num(m.get_string(1)), "tapped": m.get_string(2) != ""}
		if token_for != "":
			tparams["for"] = token_for
		_effects.append({"kind": "CREATE_TOKEN", "params": tparams})
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

	# "Its controller may search their library for a basic land card, put that card onto the battlefield tapped, then shuffle."
	if _match("^its controller may search their library for a basic land card, put that card onto the battlefield tapped(?:, then shuffle)?$", s) != null:
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filter": {"basic_land": true}, "n": 1, "to": "BATTLEFIELD", "tapped": true, "for": "TARGET_CONTROLLER"}})
		return true

	# Search your library.
	m = _match("^search your library for (?:(a|an|one|two|three)|up to (one|two|three)) (basic land|land|[a-z, ]+?) cards?, (?:reveal (?:it|them|those cards), )?put (?:it|them|that card|those cards) (onto the battlefield tapped|onto the battlefield|into your hand)$", s)
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
	if w == "~" or w == "it":
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
	elif _match("^target (artifact|creature|enchantment|land|planeswalker) or (artifact|creature|enchantment|land|planeswalker)( you control| you don't control| an opponent controls| that player controls)?$", s) != null:
		var m2 := _match("^target (artifact|creature|enchantment|land|planeswalker) or (artifact|creature|enchantment|land|planeswalker)( you control| you don't control| an opponent controls| that player controls)?$", s)
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
		var m := _match("^target (nontoken )?(nonland permanent|permanent|creature|artifact|enchantment|land|planeswalker|[a-z]+)( you control| you don't control| an opponent controls| that player controls)?$", s)
		if m == null:
			return -1
		var noun := m.get_string(2).to_lower()
		var q: Dictionary
		if PERMANENT_QUERIES.has(noun):
			q = (PERMANENT_QUERIES[noun] as Dictionary).duplicate()
		elif noun == "planeswalker":
			q = {"type": "planeswalker"}
		else:
			q = {"type": "creature", "subtype": _cap(noun)}
		if m.get_string(1) != "":
			q["nontoken"] = true
		var who := m.get_string(3).strip_edges().to_lower()
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
	if low == "one mana of any color that a land an opponent controls could produce":
		return "{OPP}"
	if low == "one mana of the chosen color":
		return "{CHOSEN}"
	## Thriving lands: "{R} or one mana of the chosen color" (CR 106.5).
	var thr := _match("^\\{([WUBRGC])\\} or one mana of the chosen color$", t)
	if thr != null:
		return "{%s|CHOSEN}" % thr.get_string(1)
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
