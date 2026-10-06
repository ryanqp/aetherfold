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
	"lifelink", "menace", "reach", "trample", "vigilance", "exalted", "shroud", "defender", "fear", "intimidate", "skulk", "infect", "wither",
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
## What "X" means in the sentence being read ("..., where X is the number of creatures you control"), or null for the X paid.
var _x_override: Variant = null


# --- Entry points ------------------------------------------------------------------------

## While a card is being loaded for play, a sentence the reader can't turn into an effect becomes a "Not coded yet" note
## and the rest of the ability still works. The coverage tool leaves this off so it counts only what is truly read.
static var lenient: bool = false


static func translate(def: CardDefinition) -> Array:
	lenient = true
	var out := _translate(def)
	lenient = false
	return out


static func _translate(def: CardDefinition) -> Array:
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
	lenient = true
	var out := _translate_permanent(def)
	lenient = false
	return out


static func _translate_permanent(def: CardDefinition) -> Array:
	if def == null or _applies(def):
		return []
	var out: Array = []
	var n := 0
	var in_band := false
	var band := {}
	var class_level := 1
	var re_band := RegEx.create_from_string("^(LEVEL|STATION) \\d+(-\\d+|\\+)$")
	var raw_lines: PackedStringArray = normalize(def).split("\n")
	var modal_found: Array = []
	var li := -1
	while li + 1 < raw_lines.size():
		li += 1
		var raw := raw_lines[li]
		var line := strip_ability_word(str(raw).strip_edges())
		if line == "":
			continue
		## "When ~ enters, choose one —" followed by its bullet lines: one triggered / activated ability with the modes.
		modal_found = []
		if line.ends_with("—") and line.to_lower().contains("choose "):
			var bullets: Array = []
			while li + 1 < raw_lines.size() and str(raw_lines[li + 1]).strip_edges().begins_with("•"):
				li += 1
				bullets.append(str(raw_lines[li]).strip_edges().substr(1).strip_edges())
			modal_found = OracleIr.new()._modal_permanent_line(def, line, bullets)
			if modal_found.is_empty():
				continue
		elif line.begins_with("•"):
			continue
		## A level / station band's abilities only count in that band (read by LayerManager), not always.
		if re_band.search(line) != null:
			in_band = true
			var bmm := RegEx.create_from_string("^(LEVEL|STATION) (\\d+)(?:-(\\d+)|(\\+))$").search(line)
			band = {"name": "level" if bmm.get_string(1) == "LEVEL" else "charge", "min": int(bmm.get_string(2)),
				"max": int(bmm.get_string(3)) if bmm.get_string(3) != "" else -1}
			continue
		if in_band:
			## The band's P/T and keywords are applied by LayerManager (KeywordLines.read_bands); other lines are abilities
			## that only work while the counters are in the band.
			if RegEx.create_from_string("^\\d+/\\d+$").search(line) != null or _band_keyword_line(line):
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
		## Class (CR 716): "{2}{G}: Level 2" gains the next level at sorcery speed; the lines below it count from that level.
		var cl := RegEx.create_from_string("^((?:\\{[^}]+\\})+): Level (\\d+)$").search(line) if def.type_line.contains("Class") else null
		if cl != null:
			var lvl := int(cl.get_string(2))
			class_level = lvl
			n += 1
			var lvl_ab := {"ability_id": "%s_level_%d" % [_snake(def.name), lvl], "kind": "ACTIVATED",
				"costs": [{"kind": "MANA", "mana": cl.get_string(1)}], "targets": [],
				"effects": [{"kind": "PUT_COUNTER", "params": {"name": "level", "n": 1, "self": true}}],
				"restrictions": ["SORCERY_SPEED", {"cond": {"class_level_is": lvl - 1}}], "text": line}
			var lvl_loader := IrLoader.new()
			var lvl_parsed := lvl_loader.from_dict({"abilities": [lvl_ab]})
			if lvl_loader.errors.is_empty():
				out.append_array(lvl_parsed)
			continue
		var found: Array = modal_found if not modal_found.is_empty() else _read_whole_or_by_sentence(def, line)
		if class_level > 1:
			for f in found:
				_gate_class_level(f as Dictionary, class_level)
		if in_band and not band.is_empty():
			for f in found:
				_gate_with(f as Dictionary, {"counter_band": band})
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


## A Class level's ability only works once that level is reached: triggers and statics carry a condition, activations a restriction.
static func _gate_class_level(ab: Dictionary, level: int) -> void:
	_gate_with(ab, {"class_level": level})


## Adds a LayerManager.condition_met condition to an ability: triggers and statics carry it, activations a restriction.
static func _gate_with(ab: Dictionary, cond: Dictionary) -> void:
	match str(ab.get("kind", "")):
		"TRIGGERED":
			var trig: Dictionary = ab.get("trigger", {})
			var old_c: Dictionary = trig.get("condition", {})
			old_c.merge(cond, true)
			trig["condition"] = old_c
			ab["trigger"] = trig
		"STATIC":
			var sp: Dictionary = ab.get("static", {})
			var old_s: Dictionary = sp.get("condition", {})
			old_s.merge(cond, true)
			sp["condition"] = old_s
			ab["static"] = sp
		_:
			var rs: Array = ab.get("restrictions", [])
			rs.append({"cond": cond})
			ab["restrictions"] = rs


## A band line made only of keywords ("Flying", "First strike, vigilance"): applied by LayerManager from KeywordLines.read_bands.
static func _band_keyword_line(line: String) -> bool:
	for part in line.trim_suffix(".").split(", "):
		if KeywordDb.lookup(str(part).strip_edges().to_lower()).is_empty():
			return false
	return line.strip_edges() != ""


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
	var re_once := RegEx.create_from_string("(?i)\\.?\\s*(?:do this only once each turn|this ability triggers only once each turn)\\.?")
	if re_once.search(text) != null:
		once = true
		text = re_once.sub(text, "", true)
	## "Activate only as a sorcery." / "Activate only during your turn." / "Activate only once each turn." /
	## "Activate only if <condition>.": timing and condition restrictions on an activated ability.
	var re_act := RegEx.create_from_string("(?i)\\.?\\s*activate (?:this ability )?only (as a sorcery|during your turn|once each turn|if (?:[^.]+))\\.?")
	var am := re_act.search(text)
	if am != null:
		var what := am.get_string(1).to_lower()
		if what == "as a sorcery":
			restrictions.append("SORCERY_SPEED")
		elif what == "during your turn":
			restrictions.append("MY_TURN")
		elif what == "once each turn":
			restrictions.append("ONCE_EACH_TURN")
		else:
			var cond := OracleIr.new()._condition(what.trim_prefix("if "))
			if cond.is_empty():
				return []
			restrictions.append({"cond": cond})
		text = re_act.sub(text, "", true)
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
		## "Kaervek the Merciless" / "Gray Merchant of Asphodel" are written "Kaervek" / "Gray Merchant" in their own text.
		for sep in [" the ", " of "]:
			if front.contains(sep) and not front.contains(", "):
				var short2 := front.split(sep)[0]
				if short2.length() >= 4:
					text = text.replace(short2, "~")
	text = RegEx.create_from_string("(?i)\\bthis (creature|artifact|enchantment|land|permanent|equipment|aura|vehicle|saga|spell|card|token)\\b").sub(text, "~", true)
	## "~ is put into a graveyard from the battlefield" is "~ dies" (CR 700.4).
	text = text.replace(" is put into a graveyard from the battlefield", " dies").replace(" is put into your graveyard from the battlefield", " dies")
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
	m = _match("^\\{T\\}: add (.+?)\\. spend this mana only to cast (?:an? )?([a-z]+)(?: creature)? spells?( of the chosen type)?(?: or activate an abilit(?:y|ies) of an? ([a-z]+) sources?( of the chosen type)?)?$", line)
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
			if noun != "creature" and line.to_lower().contains(noun + " creature spell"):
				rq["type"] = "creature"
			return [{
				"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": rmana}}],
				"restrictions": [{"spend_only": {"query": rq, "abilities": line.to_lower().contains("activate an abilit")}}],
			}]

	# Seance Board: "{T}: Add X mana of any one color, where X is the number of soul counters on ~. Spend this mana only to cast
	# instant, sorcery, Demon, and Spirit spells."
	m = _match("^\\{T\\}: add x mana of any one color, where x is the number of ([a-z]+) counters on ~\\. spend this mana only to cast (.+?) spells$", line)
	if m != null:
		var any_specs: Array = []
		for part in m.get_string(2).to_lower().replace(", and ", ",").replace(" and ", ",").replace(" or ", ",").split(","):
			var pw := str(part).strip_edges()
			if pw in ["instant", "sorcery", "creature", "artifact", "enchantment", "land", "planeswalker"]:
				any_specs.append({"type": pw})
			elif pw != "":
				any_specs.append({"subtype": _cap(pw)})
		return [{
			"kind": "MANA", "costs": [{"kind": "TAP"}], "targets": [],
			"effects": [{"kind": "ADD_MANA", "params": {"mana": "{W|U|B|R|G}", "per_counter": m.get_string(1).to_lower()}}],
			"restrictions": [{"spend_only": {"query": {"any": any_specs}, "abilities": false}}],
		}]
	# "Whenever you tap a land for mana, add one mana of any type that land produced."
	if _match("^whenever you tap a land for mana, add one mana of any type that land produced$", line) != null:
		return [{"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "extra_land_mana": true}}]
	# "You have hexproof." (Leyline of Sanctity, Orbs of Warding ...)
	if _match("^you have hexproof$", line) != null:
		return [{"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "player_hexproof": true}}]
	# "You, planeswalkers you control, and other creatures you control have hexproof."
	if _match("^you, planeswalkers you control, and other creatures you control have hexproof$", line) != null:
		return [
			{"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "player_hexproof": true}},
			{"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "OTHERS", "query": {"controller": "SOURCE_CONTROLLER", "type": "creature"}, "keywords": ["Hexproof"]}},
		]
	# Forsaken Monument: "Whenever you tap a permanent for {C}, add an additional {C}."
	if _match("^whenever you tap a permanent for \\{c\\}, add an additional \\{c\\}$", line) != null:
		return [{"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "extra_colorless": 1}}]
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

	## "As long as you control your commander, ~ gets +2/+2 and creatures you control have vigilance.": one static per effect.
	var cm2 := _match("^as long as (.+?), (~ gets [^,]+?) and ((?:other )?(?:[a-z ]*)creatures[a-z ]* (?:have|gain|get) .+)$", line)
	if cm2 != null:
		var first_st := _static_line("as long as %s, %s" % [cm2.get_string(1), cm2.get_string(2)])
		var second_st := _static_line("as long as %s, %s" % [cm2.get_string(1), cm2.get_string(3)])
		if not first_st.is_empty() and not second_st.is_empty():
			return [first_st, second_st]
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
	## "As ~ enters, choose a color / a creature type": the choice is made as it enters.
	m = _match("^as (?:~|it) enters, (choose a (?:color|creature type))$", line)
	if m != null:
		var ar := OracleIr.new()
		if ar._read_effects(m.get_string(1)):
			return [{"kind": "TRIGGERED", "trigger": {"on": "ENTERS_BATTLEFIELD"}, "costs": [], "targets": [], "effects": ar._effects, "restrictions": []}]
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
	m = _match("^~ enters with (a|an|one|two|three|four|five|six|seven|eight|nine|ten|\\d+) \\+1/\\+1 counters? on it$", line)
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

	## "Whenever ~ blocks or becomes blocked [by a creature], ...": two triggers.
	var bb := _match("^(when|whenever) ~ blocks or becomes blocked(?: by a creature)?, (.+)$", line)
	if bb != null:
		var b1 := _trigger_with({"on": "BLOCKS"}, bb.get_string(2))
		var b2 := _trigger_with({"on": "BECOMES_BLOCKED"}, bb.get_string(2))
		if not b1.is_empty() and not b2.is_empty():
			return [b1, b2]
	## "When ~ enters or dies, ..." / "Whenever ~ attacks or blocks, ...": the same effect for two events, read as two triggers.
	var two := _match("^(when|whenever) ~ (enters|attacks|dies|blocks) or (enters|attacks|dies|blocks|is put into a graveyard from the battlefield), (.+)$", line)
	if two != null:
		var second := "dies" if two.get_string(3).to_lower().begins_with("is put into") else two.get_string(3).to_lower()
		var first_t := _trigger_line("%s ~ %s, %s" % [two.get_string(1), two.get_string(2).to_lower(), two.get_string(4)])
		var second_t := _trigger_line("%s ~ %s, %s" % [two.get_string(1), second, two.get_string(4)])
		if not first_t.is_empty() and not second_t.is_empty():
			return [first_t, second_t]
	## "Whenever your commander enters or attacks, ..." (Tome of Legends): two triggers.
	var cmd2 := _match("^(when|whenever) your commander enters or attacks, (.+)$", line)
	if cmd2 != null:
		var ent_t := _trigger_line("%s a commander you control enters, %s" % [cmd2.get_string(1), cmd2.get_string(2)])
		var att_t := _trigger_with({"on": "ATTACKS", "scope": "ANY", "filter": {"controller": "SOURCE_CONTROLLER", "commander": true}}, cmd2.get_string(2))
		if not ent_t.is_empty() and not att_t.is_empty():
			return [ent_t, att_t]
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
	m = _match("^((?:\\{[^}]+\\}|waterbend \\{\\d+\\}|sacrifice ~|sacrifice (?:a|an|another|two|three|four|\\d+) [a-z' -]+?|tap (?:a|an|two|three|four|\\d+) untapped [a-z' -]+? you control|untap (?:a|an|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|\\d+) tapped [a-z' -]+? you control|return (?:a|an|another) [a-z' -]+? you control to its owner's hand|discard (?:a|an) card|remove (?:a|an|one|two|three|four|five|six|seven|\\d+) [a-z0-9+/-]+ counters? from ~|pay (?:\\{e\\})+|pay life equal to the number of colors in your commanders' color identity|pay \\d+ life|put an? [a-z0-9+/-]+ counter on ~|, )+): (.+)$", line)
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
	if _match("^can't attack$", t) != null:
		spec["cant_attack"] = true
		return spec
	if _match("^can't block$", t) != null:
		spec["cant_block"] = true
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
	m = _match("^~ gets ([+-]\\d+)/([+-]\\d+) as long as it's attacking$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "condition": {"attacking": true}}}
	## "During your turn, ~ has first strike." / "~ gets +1/+1 during your turn.": the same static, only on your turn.
	m = _match("^during your turn, (.+)$", line)
	if m == null:
		m = _match("^(.+?) during your turn$", line)
	if m != null:
		var inner := _static_line(m.get_string(1))
		if inner.is_empty():
			## "~ has flying" / "~ gets +1/+1" on their own are not statics the line reader returns: build them here.
			var kmm := _match("^~ (?:has|gains) ([a-z ,]+)$", m.get_string(1))
			var pmm := _match("^~ gets ([+-]\\d+)/([+-]\\d+)$", m.get_string(1))
			var ispec := {"scope": "SELF"}
			if kmm != null and not _keywords(kmm.get_string(1)).is_empty():
				ispec["keywords"] = _keywords(kmm.get_string(1))
			elif pmm != null:
				ispec["power"] = int(pmm.get_string(1))
				ispec["toughness"] = int(pmm.get_string(2))
			if ispec.size() > 1:
				inner = {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": ispec}
		if not inner.is_empty() and inner.has("static"):
			var isp: Dictionary = inner["static"]
			var ic: Dictionary = isp.get("condition", {})
			ic["my_turn"] = true
			isp["condition"] = ic
			return inner
	## "Lands you control have "{T}: Add one mana of any color."" (Chromatic Lantern), "Creatures you control have ..." (Cryptolith Rite).
	m = _match("^(lands|creatures|artifacts|permanents) you control have \"\\{t\\}: add (one mana of any color|\\{[wubrgc]\\})\\.?\"$", line)
	if m != null:
		var gq := {"controller": "SOURCE_CONTROLLER"}
		if m.get_string(1).to_lower() != "permanents":
			gq["type"] = m.get_string(1).to_lower().trim_suffix("s")
		var gm := "{W|U|B|R|G}" if m.get_string(2).to_lower().begins_with("one mana") else m.get_string(2).to_upper()
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "ALL", "query": gq, "grant_tap_mana": gm}}
	## "Skeletons you control and other Zombies you control get +1/+1 and have deathtouch." (Death Baron)
	m = _match("^([a-z]+?)s you control and other ([a-z]+?)s you control get ([+-]\\d+)/([+-]\\d+)(?: and (?:have|gain) ([a-z ,]+))?$", line)
	if m != null:
		var lk: Array = _keywords(m.get_string(5)) if m.get_string(5) != "" else []
		if m.get_string(5) == "" or not lk.is_empty():
			var lspec := {"scope": "OTHERS", "query": {"controller": "SOURCE_CONTROLLER", "subtype_any": [_cap(m.get_string(1)), _cap(m.get_string(2))]},
				"power": int(m.get_string(3)), "toughness": int(m.get_string(4))}
			if not lk.is_empty():
				lspec["keywords"] = lk
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": lspec}
	## "~ can't be blocked as long as you control no other creatures." (Jeskai Infiltrator)
	if _match("^~ can't be blocked as long as you control no other creatures$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "keywords": ["Unblockable"], "condition": {"controls": {"controller": "SOURCE_CONTROLLER", "type": "creature", "other": true}, "max": 0}}}
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
	## "~ can't attack or block unless you control another creature with power 4 or greater." (Rhonas the Indomitable)
	m = _match("^~ can't attack or block unless you control another creature with power (\\d+) or greater$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cant_attack_block_unless": {"other_power_min": int(m.get_string(1))}}}
	m = _match("^~ can't attack or block unless you have the city's blessing$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cant_attack_block_unless": {"permanents": 10}}}

	# "Creatures your opponents control get -2/-2." (Elesh Norn) / "Creatures your opponents control have ...".
	m = _match("^((?:[a-z]+ )?creatures) (your opponents control|an opponent controls) (?:get ([+-]\\d+)/([+-]\\d+)|(?:have|gain) ([a-z ,]+))$", line)
	if m != null:
		var opq := _event_subject(m.get_string(1) + " an opponent controls", false)
		var op_kw: Array = []
		if m.get_string(5) != "":
			op_kw = _keywords(m.get_string(5))
		if not opq.is_empty() and (m.get_string(5) == "" or not op_kw.is_empty()):
			var op_spec := {"scope": "ALL", "query": opq}
			if m.get_string(3) != "":
				op_spec["power"] = int(m.get_string(3))
				op_spec["toughness"] = int(m.get_string(4))
			if not op_kw.is_empty():
				op_spec["keywords"] = op_kw
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": op_spec}
	# "Each other Angel you control enters with an additional +1/+1 counter on it [for each Angel you already control]."
	m = _match("^each (other )?(.+?) you control( of the chosen type)? enters with an additional \\+1/\\+1 counter on it(?: for each (.+?) you already control)?$", line)
	if m != null:
		var who_text := m.get_string(2).to_lower()
		var chosen_type := m.get_string(3) != "" or who_text.contains(" of the chosen type")
		who_text = who_text.replace(" of the chosen type", "")
		var eq := _event_subject(who_text + " you control", false)
		if not eq.is_empty():
			if chosen_type:
				eq["subtype"] = "$chosen"
			if m.get_string(1) != "":
				eq["other"] = true
			var ex_spec := {"query": eq, "n": 1}
			if m.get_string(4) != "":
				var per_q := _event_subject(m.get_string(4).to_lower() + " you control", false)
				if per_q.is_empty():
					return {}
				ex_spec["per"] = per_q
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "enters_extra": ex_spec}}
	# Metallic Mimic: "~ is the chosen type in addition to its other types."
	if _match("^~ is the chosen type in addition to its other types$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "SELF", "add_chosen_subtype": true}}
	# "~ gets +1/+0 for each legendary creature you control." / "Equipped creature gets +1/+1 for each soul counter on ~."
	m = _match("^(~|enchanted creature|equipped creature) gets ([+-]\\d+)/([+-]\\d+) for each (.+)$", line)
	if m != null:
		var per_spec := {"scope": {"~": "SELF", "enchanted creature": "ENCHANTED", "equipped creature": "EQUIPPED"}[m.get_string(1).to_lower()],
			"power": int(m.get_string(2)), "toughness": int(m.get_string(3))}
		var per_what := m.get_string(4).to_lower()
		var cm := _match("^([a-z+/-]+) counters? on ~$", per_what)
		if cm != null:
			per_spec["per_counter"] = cm.get_string(1)
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": per_spec}
		var pe: Variant = _count_expr(per_what)
		if pe != null and (pe as Dictionary).has("query"):
			per_spec["per"] = (pe as Dictionary)["query"]
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": per_spec}
	# Graaz: "Juggernauts you control attack each combat if able." / "... can't be blocked by Walls." / "Other creatures you control
	# have base power and toughness 5/3 and are Juggernauts in addition to their other creature types."
	m = _match("^([a-z' -]+?) you control attack each combat if able$", line)
	if m != null:
		var mq := _event_subject(m.get_string(1).to_lower() + " you control", false)
		if not mq.is_empty():
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "must_attack": true, "query": mq}}
	m = _match("^([a-z' -]+?) you control can't be blocked by ([a-z' -]+)$", line)
	if m != null:
		var bq := _event_subject(m.get_string(1).to_lower() + " you control", false)
		var by_q := _event_subject(m.get_string(2).to_lower(), false)
		if not bq.is_empty() and not by_q.is_empty():
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "cant_be_blocked_by_group": {"query": bq, "by": by_q}}}
	m = _match("^other creatures you control have base power and toughness (\\d+)/(\\d+) and are ([a-z]+)s in addition to their other creature types$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "OTHERS",
			"query": {"controller": "SOURCE_CONTROLLER", "type": "creature"}, "base_pt": [int(m.get_string(1)), int(m.get_string(2))], "add_subtypes": [_cap(m.get_string(3))]}}
	# Attack / block taxes (Archangel of Tithes, Propaganda).
	m = _match("^as long as ~ is untapped, creatures can't attack you or planeswalkers you control unless their controller pays \\{(\\d)\\} for each of those creatures$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "attack_tax": int(m.get_string(1)), "while": "UNTAPPED"}}
	m = _match("^creatures can't attack you(?: or planeswalkers you control)? unless their controller pays \\{(\\d)\\} for each creature they control that's attacking you(?: or planeswalkers you control)?$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "attack_tax": int(m.get_string(1))}}
	m = _match("^as long as ~ is attacking, creatures can't block unless their controller pays \\{(\\d)\\} for each of those creatures$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "block_tax": int(m.get_string(1))}}
	# "If you would gain life, you gain twice that much life instead." / "~'s power and toughness are each equal to your life total."
	if _match("^if you would gain life, you gain twice that much life instead$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "NONE", "life_gain_mult": 2}}
	if _match("^~'s power and toughness are each equal to your life total$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cda_pt": {"power": true, "toughness": true, "life": true, "query": {}}}}
	# "As long as ~ has four or more +1/+1 counters on it, it has flying and vigilance."
	m = _match("^as long as ~ has (two|three|four|five|six|seven|eight|nine|ten|\\d+) or more ([+/0-9a-z-]+) counters on it, (?:it|~) has ([a-z ,]+)$", line)
	if m != null:
		var ckws := _keywords(m.get_string(3))
		if not ckws.is_empty():
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "SELF", "keywords": ckws,
				"condition": {"self_counters": {"name": m.get_string(2).to_lower(), "min": _num(m.get_string(1))}}}}
	# "You can't lose the game and your opponents can't win the game."
	if _match("^you can't lose the game and your opponents can't win the game$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "cant_lose": true}}
	# Herald of War: "Angel spells and Human spells you cast cost {1} less to cast for each +1/+1 counter on ~."
	m = _match("^([a-z]+(?: spells and [a-z]+)*) spells you cast cost \\{(\\d)\\} less to cast for each \\+1/\\+1 counter on ~$", line)
	if m != null:
		var hw: Array = []
		for part in m.get_string(1).to_lower().replace(" spells", "").split(" and "):
			hw.append(_cap(str(part)))
		var hwf := {"subtype_any": hw} if hw.size() > 1 else {"subtype": hw[0]}
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(2)), "filter": hwf, "per_counter": "+1/+1"}}}
	# Angel of Vitality: "If you would gain life, you gain that much life plus 1 instead."
	m = _match("^if you would gain life, you gain that much life plus (\\d+) instead$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "life_gain_plus": int(m.get_string(1))}}
	# Serra Avenger: "You can't cast ~ during your first, second, or third turns of the game."
	if _match("^you can't cast ~ during your first, second, or third turns of the game$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "cast_condition": {"own_turns_min": 4}}}
	# "Players can't gain life." / "Your opponents can't gain life." / "You can't cast ~ unless an opponent lost life this turn."
	m = _match("^(players|your opponents|each opponent|opponents) can't gain life$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "NONE", "no_life_gain": "ALL" if m.get_string(1).to_lower() == "players" else "OPPONENTS"}}
	m = _match("^you can't cast ~ unless (.+)$", line)
	if m != null:
		var cc := _condition(m.get_string(1))
		if not cc.is_empty():
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
				"static": {"scope": "NONE", "cast_condition": cc}}
	var own_discount := _self_discount(line)
	if not own_discount.is_empty():
		return own_discount
	# Characteristic-defining power / toughness: "~'s power and toughness are each equal to the number of lands you control."
	m = _match("^~'s (power and toughness are each|power is|toughness is) equal to the number of (.+)$", line)
	if m != null:
		var ce: Variant = _count_expr(m.get_string(2))
		if ce != null and (ce as Dictionary).has("query"):
			var kind := m.get_string(1).to_lower()
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "SELF",
				"cda_pt": {"power": kind != "toughness is", "toughness": kind != "power is", "query": (ce as Dictionary)["query"]}}}
	# "~ can't be blocked." (Unblockable is checked when blockers are declared.)
	if _match("^~ can't be blocked$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": {"scope": "SELF", "keywords": ["Unblockable"]}}
	# "As long as <condition>, <lord phrase>" (Righteous Valkyrie: creatures you control get +2/+2 at 7 life over the start).
	m = _match("^as long as (.+?), (.+)$", line)
	if m != null:
		var lcond := _condition(m.get_string(1))
		if not lcond.is_empty():
			var lord := _lord_static(m.get_string(2))
			if not lord.is_empty():
				(lord["static"] as Dictionary)["condition"] = lcond
				return lord
	# "[During your turn,] [if <condition>,] you may play lands and cast spells from among cards exiled with ~."
	m = _match("^(during your turn, )?(?:if (.+?), )?you may (?:play lands and cast spells|cast spells|play cards|play lands) from among (?:the )?cards exiled with (?:~|this [a-z]+)$", line)
	if m != null:
		var pcond := {}
		var pok := true
		if m.get_string(2) != "":
			pcond = _condition(m.get_string(2))
			pok = not pcond.is_empty()
		if m.get_string(1) != "":
			pcond["my_turn"] = true
		if pok:
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
				"static": {"scope": "NONE", "play_exiled_with": true, "condition": pcond}}
	# "As long as <condition>, ~ gets +1/+1 and has flying." / "~ gets +2/+2 as long as <condition>."
	var self_part := "(?:~|this creature) (?:gets ([+-]\\d+)/([+-]\\d+)(?: and (?:has|gains?) ([a-z ,]+?))?|(?:has|gains?) ([a-z ,]+?))"
	m = _match("^as long as (.+?), " + self_part + "$", line)
	var cond_text := ""
	var off := 0
	if m != null:
		cond_text = m.get_string(1)
		off = 1
	else:
		m = _match("^" + self_part + " as long as (.+)$", line)
		if m != null:
			cond_text = m.get_string(5)
	if m != null:
		var scond := _condition(cond_text)
		var skw_text := m.get_string(3 + off) if m.get_string(3 + off) != "" else m.get_string(4 + off)
		var skws := _keywords(skw_text) if skw_text != "" else []
		if not scond.is_empty() and (skw_text == "" or not skws.is_empty()):
			var sspec := {"scope": "SELF", "condition": scond}
			if m.get_string(1 + off) != "":
				sspec["power"] = int(m.get_string(1 + off))
				sspec["toughness"] = int(m.get_string(2 + off))
			if not skws.is_empty():
				sspec["keywords"] = skws
			return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": sspec}
	# "Dinosaur spells you cast cost {1} less to cast."
	# "Black creature spells you cast cost {1} less to cast." (Bontu's Monument, Hazoret's Monument)
	m = _match("^(white|blue|black|red|green) creature spells you cast cost \\{(\\d)\\} less to cast$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(2)), "filter": {"type": "creature", "color": COLOR_LETTERS[m.get_string(1).to_lower()]}}}}
	m = _match("^(creature|[a-z]+) spells you cast( of the chosen type)? cost \\{(\\d)\\} less to cast$", line)
	if m != null and not m.get_string(1).to_lower() in ["instant", "sorcery", "artifact", "enchantment", "noncreature", "historic"]:
		var f := {"type": "creature"} if m.get_string(1).to_lower() == "creature" else {"type": "creature", "subtype": _cap(m.get_string(1))}
		if m.get_string(2) != "":
			f["subtype"] = "$chosen"
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(3)), "filter": f}}}
	m = _match("^creature spells you cast with power (\\d+) or greater cost \\{(\\d)\\} less to cast$", line)
	if m != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(2)), "filter": {"type": "creature", "power_min": int(m.get_string(1))}}}}
	m = _match("^(instant and sorcery|instant|sorcery|artifact|enchantment|noncreature|historic) spells you cast cost \\{(\\d)\\} less to cast$", line)
	if m != null:
		var kind_word := m.get_string(1).to_lower()
		var cf := {}
		match kind_word:
			"instant and sorcery":
				cf = {"type_any": ["instant", "sorcery"]}
			"noncreature":
				cf = {"not_type": "creature"}
			"historic":
				cf = {"type_any": ["artifact", "legendary", "saga"]}
			_:
				cf = {"type": kind_word}
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction": {"amount": int(m.get_string(2)), "filter": cf}}}
	return _lord_static(line)


## "When ~ enters, ...", "Whenever ~ attacks, ...", "At the beginning of your upkeep, ...".
func _trigger_line(line: String) -> Dictionary:
	var m: RegExMatch
	m = _match("^at the beginning of (your|each|the|each player's|each opponent's) (upkeep|draw step|end step|combat on your turn), (.+)$", line)
	if m != null:
		var step_word := m.get_string(2).to_lower()
		var step := "UPKEEP" if step_word == "upkeep" else ("DRAW" if step_word == "draw step" else ("END" if step_word == "end step" else "BEGIN_COMBAT"))
		var whose_word := m.get_string(1).to_lower()
		var whose := "YOURS" if whose_word == "your" else ("EACH" if whose_word in ["each", "the", "each player's"] else "OPPONENT")
		return _trigger_with({"on": "BEGIN_STEP", "step": step, "whose": whose}, m.get_string(3))
	m = _match("^at the beginning of (your|each player's) (?:first|precombat) main phase, (.+)$", line)
	if m != null:
		return _trigger_with({"on": "BEGIN_STEP", "step": "MAIN1", "whose": "YOURS" if m.get_string(1).to_lower() == "your" else "EACH"}, m.get_string(2))
	m = _match("^at the beginning of combat on your turn, (.+)$", line)
	if m != null:
		return _trigger_with({"on": "BEGIN_STEP", "step": "BEGIN_COMBAT", "whose": "YOURS"}, m.get_string(1))
	m = _match("^at the beginning of each combat, (.+)$", line)
	if m != null:
		return _trigger_with({"on": "BEGIN_STEP", "step": "BEGIN_COMBAT", "whose": "EACH"}, m.get_string(1))
	## A list inside the trigger condition has commas of its own: "an ability of an artifact, creature, or land".
	line = line.replace("artifact, creature, or land", "artifact or creature or land")
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
	## Angelic Sleuth: "..., if it had counters on it, investigate."
	if rest.to_lower().begins_with("if it had counters on it, "):
		trig["if_had_counters"] = true
		rest = rest.substr(26)
	## Harsh Mentor: only non-mana abilities are announced to this trigger anyway.
	if rest.to_lower().begins_with("if it isn't a mana ability, "):
		rest = rest.substr(28)
	var im := _match("^if (.+?), (.+)$", rest)
	if im != null and not trig.has("condition"):
		var icond := _condition(im.get_string(1))
		if not icond.is_empty():
			trig["condition"] = icond
			rest = im.get_string(2)
	return _trigger_with(trig, rest)


func _trigger_with(trig: Dictionary, effect_text: String) -> Dictionary:
	## "At the beginning of your upkeep, if <condition>, <effect>": the intervening if is checked when the trigger would go on the stack.
	var iff := _match("^if (.+?), (.+)$", effect_text)
	if iff != null and not trig.has("condition"):
		var icd := _condition(iff.get_string(1))
		if not icd.is_empty():
			trig["condition"] = icd
			effect_text = iff.get_string(2)
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
	## "When you control no Islands, sacrifice ~." (CR 603.8)
	m = _match("^you control no ([a-z]+?)s$", h)
	if m != null:
		return {"on": "STATE_NO_TYPE", "subtype": _cap(m.get_string(1))}
	## "When ~ becomes the target of a spell or ability [an opponent controls]" (CR 603.2).
	m = _match("^(?:~|this creature) becomes the target of a spell or ability( an opponent controls)?$", h)
	if m != null:
		return {"on": "BECOMES_TARGET", "opp_only": m.get_string(1) != ""}
	## "Whenever equipped creature dies" (Skullclamp): watched by the Equipment.
	if _match("^equipped creature dies$", h) != null:
		return {"on": "DIES", "scope": "EQUIPPED"}
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
	if _match("^an opponent casts a spell$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "OPPONENT"}}
	if _match("^you cast a spell that targets (?:~|this creature)$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "targets_self": true}}
	if _match("^you cast a spell from anywhere other than your hand$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "not_from_hand": true}}
	if _match("^(?:another|a) player casts a spell from anywhere other than their hand$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "OPPONENT", "not_from_hand": true}}
	if _match("^a player casts a spell$", h) != null:
		return {"on": "SPELL_CAST", "filter": {}}
	m = _match("^a player casts an? (instant or sorcery|creature|noncreature|instant|sorcery|artifact|enchantment) spell$", h)
	if m != null:
		var pf := _cast_filter(m.get_string(1))
		if not pf.is_empty():
			(pf["filter"] as Dictionary).erase("controller")
			return pf
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
	if _match("^~ blocks(?: a creature)?$", h) != null:
		return {"on": "BLOCKS"}
	if _match("^~ becomes blocked(?: by a creature)?$", h) != null:
		return {"on": "BECOMES_BLOCKED"}
	if _match("^~ leaves the battlefield$", h) != null:
		return {"on": "LEAVES"}
	## "Whenever equipped creature deals combat damage to a player, ..." (Skullclamp-style Equipment, Auras): watched by the attachment.
	m = _match("^(equipped|enchanted) creature deals combat damage to a player$", h)
	if m != null:
		return {"on": "COMBAT_DAMAGE_TO_PLAYER", "scope": "EQUIPPED" if m.get_string(1).to_lower() == "equipped" else "ENCHANTED"}
	if _match("^~ attacks alone$", h) != null:
		return {"on": "SELF_ATTACKS_ALONE"}
	m = _match("^you cast your (second|third|fourth) spell each turn$", h)
	if m != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "nth": {"second": 2, "third": 3, "fourth": 4}[m.get_string(1).to_lower()]}}
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
	m = _match("^(you|an opponent|a player) draws? a card$", h)
	if m != null:
		return {"on": "DRAWS", "who": {"you": "YOU", "an opponent": "OPPONENT", "a player": "ANY"}[m.get_string(1).to_lower()]}
	if _match("^you cast a creature spell of the chosen type$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER", "query": {"type": "creature", "subtype": "$chosen"}}}
	if _match("^you cast a spell$", h) != null:
		return {"on": "SPELL_CAST", "filter": {"controller": "SOURCE_CONTROLLER"}}
	m = _match("^you cast (?:an? )?(.+?) spell$", h)
	if m != null:
		return _cast_filter(m.get_string(1))
	m = _match("^there are (two|three|four|five|six|seven|\\d+) or more ([a-z]+) counters on ~$", h)
	if m != null:
		return {"on": "STATE_COUNTERS", "counter": m.get_string(2).to_lower(), "min": _num(m.get_string(1))}
	if _match("^equipped creature attacks$", h) != null:
		return {"on": "ATTACKS", "scope": "EQUIPPED"}
	m = _match("^you draw your (second|third|fourth) card each turn$", h)
	if m != null:
		return {"on": "DRAWS", "who": "YOU", "nth": {"second": 2, "third": 3, "fourth": 4}[m.get_string(1).to_lower()]}
	m = _match("^(one or more )?(?:an? )?([a-z' -]+?) you control deals? combat damage to a player$", h)
	if m != null:
		var cd_subject := _event_subject(m.get_string(2).to_lower(), false)
		if not cd_subject.is_empty():
			cd_subject["controller"] = "SOURCE_CONTROLLER"
			var cdt := {"on": "COMBAT_DAMAGE_TO_PLAYER", "scope": "ANY", "filter": cd_subject}
			if m.get_string(1) != "":
				cdt["once_per_turn"] = true
			return cdt
	if _match("^another permanent you control leaves the battlefield$", h) != null:
		return {"on": "LEAVES", "scope": "OTHER", "filter": {"controller": "SOURCE_CONTROLLER"}}
	m = _match("^you attack with (two|three|four|\\d+) or more creatures$", h)
	if m != null:
		return {"on": "ATTACKS", "scope": "YOU", "attackers_min": _num(m.get_string(1))}
	m = _match("^another player attacks with (two|three|four|\\d+) or more creatures$", h)
	if m != null:
		return {"on": "OPP_ATTACKS", "attackers_min": _num(m.get_string(1))}
	if _match("^you put one or more \\+1/\\+1 counters on ~$", h) != null:
		return {"on": "COUNTERS_PUT"}
	if _match("^you gain life for the first time each turn$", h) != null:
		return {"on": "LIFE_GAINED", "scope": "YOU", "first_each_turn": true}
	if _match("^an opponent loses life for the first time during each of their turns$", h) != null:
		return {"on": "OPP_LOSES_LIFE_FIRST"}
	## "Whenever an opponent activates an ability of an artifact, creature, or land (on the battlefield)".
	m = _match("^an opponent activates an ability of an? ([a-z ]+?)(?: on the battlefield)?$", h)
	if m != null:
		var types: Array = []
		for part in m.get_string(1).to_lower().replace(" or ", " ").split(" ", false):
			if str(part) in ["artifact", "creature", "land", "planeswalker"]:
				types.append(str(part))
		if not types.is_empty():
			return {"on": "OPP_ACTIVATES", "types": types}
	## "Whenever one or more other creatures die" (Morbid Opportunist).
	m = _match("^one or more (other )?(.+?) (?:die|enter)$", h)
	if m != null:
		var mf := _event_subject(m.get_string(2), false)
		if not mf.is_empty():
			return {"on": "DIES" if h.to_lower().ends_with("die") else "ENTERS_BATTLEFIELD", "scope": "OTHER" if m.get_string(1) != "" else "ANY", "filter": mf}
	## "Whenever ~ or another creature dies" (Blood Artist): itself and any other creature.
	m = _match("^~ or another (.+?) (dies|enters(?: the battlefield)?)$", h)
	if m != null:
		var of2 := _event_subject(m.get_string(1), false)
		if not of2.is_empty():
			return {"on": "DIES" if m.get_string(2) == "dies" else "ENTERS_BATTLEFIELD", "scope": "ANY", "filter": of2}
	## Any subject the generic grammar knows: "a creature an opponent controls dies", "another nontoken artifact you control
	## enters", "a creature you control with flying attacks".
	m = _match("^(an?|another|one or more) (.+?) (enters(?: the battlefield)?|dies|attacks)(?: under your control)?$", h)
	if m != null:
		var gf := _event_subject(m.get_string(2), h.to_lower().ends_with("under your control"))
		if not gf.is_empty():
			var ev := m.get_string(3).to_lower()
			var on := "ENTERS_BATTLEFIELD" if ev.begins_with("enters") else ("DIES" if ev == "dies" else "ATTACKS")
			return {"on": on, "scope": "OTHER" if m.get_string(1).to_lower() == "another" else "ANY", "filter": gf}
	return {}


## The permanents an event's subject can be: "creature an opponent controls", "nontoken artifact you control", "Goblin".
## A filter for TriggerManager (Query keys), {} when not understood.
func _event_subject(phrase: String, under_your_control: bool) -> Dictionary:
	var p := phrase.to_lower().replace(" your opponents control", " an opponent controls").replace(" your opponent controls", " an opponent controls")
	var words: Array = []
	for part in p.split(" ", false):
		var word := str(part)
		words.append(_singular_type(word).to_lower() if word.ends_with("s") and not word.ends_with("ss") and not word in ["controls"] else word)
	var q := _general_query("target " + " ".join(PackedStringArray(words)))
	if q.is_empty():
		return {}
	if under_your_control:
		q["controller"] = "SOURCE_CONTROLLER"
	return q


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
	## Combustible Gearhulk: the opponent may have you draw three cards; if not, you mill three and they take the damage.
	var pm := _match("^reveal the top (a|one|two|three|four|five|six|seven|\\d+) cards? of your library\\. an opponent separates those cards into two piles\\. put one pile into your hand and the other (into your graveyard|on the bottom of your library)$", t)
	if pm != null:
		_effects.append({"kind": "PILES", "params": {"n": _num(pm.get_string(1)), "rest": "GRAVEYARD" if pm.get_string(2).ends_with("graveyard") else "BOTTOM"}})
		return true
	if _match("^choose odd or even\\. exile each creature with mana value of the chosen quality$", t) != null:
		_effects.append({"kind": "EXILE_BY_PARITY", "params": {}})
		return true
	var cw := _match("^the owner of (target permanent) shuffles it into their library, then reveals the top card of their library\\. if it's a permanent card, they put it onto the battlefield$", t)
	if cw != null:
		var cwt := _target(cw.get_string(1))
		if cwt >= 0:
			_effects.append({"kind": "CHAOS_WARP", "params": {"target": cwt}})
			return true
	if _match("^count the number of cards in your library\\. your life total becomes that number$", t) != null:
		_effects.append({"kind": "SET_LIFE", "params": {"n": {"expr": "LIBRARY"}}})
		return true
	if _match("^target opponent may have you draw three cards\\. if the player doesn't, you mill three cards, then ~ deals damage to that player equal to the total mana value of those cards$", t) != null:
		var gslot := _add_target("PLAYER", {"opponent": true})
		if gslot >= 0:
			_effects.append({"kind": "OPP_DRAW_OR_MILL", "params": {"target": gslot}})
			return true
	if _match("^reveal the top card of your library\\. if it's a creature card that shares a creature type with a creature you control, you may cast it without paying its mana cost\\. if you don't cast it, put it on the bottom of your library$", t) != null:
		_effects.append({"kind": "REVEAL_TOP_CAST_FREE", "params": {}})
		return true
	if _match("^exile the top card of each player's library, then you may cast any number of spells from among those cards without paying their mana costs$", t) != null:
		_effects.append({"kind": "EXILE_TOP_EACH_CAST_FREE", "params": {}})
		return true
	return false


## The MODAL effect's parameters for "Choose one —" (header) and its bullet texts; {} if a mode isn't understood.
func _modal_params(header: String, bullets: Array) -> Dictionary:
	var hm := _match("^choose (one or more|one or both|one|two|three)\\b(.*)$", header)
	if hm == null or bullets.size() < 2:
		return {}
	var how := hm.get_string(1).to_lower()
	var count := 2 if how == "one or both" else (bullets.size() if how == "one or more" else _num(hm.get_string(1)))
	var rest := hm.get_string(2).to_lower()
	var modes: Array = []
	for b in bullets:
		var rd := OracleIr.new()
		rd._self_it = _self_it
		if not rd._read_effects(str(b)):
			if not lenient:
				return {}
			rd._effects = [{"kind": "NOTE_UNREAD", "params": {"text": str(b)}}]
			rd._targets = []
		modes.append({"text": str(b), "effects": rd._effects, "targets": rd._targets})
	var params := {"choose": 1 if how == "one or both" or how == "one or more" else count, "modes": modes}
	if how == "one or both" or how == "one or more":
		params["any_up_to"] = count
	if rest.contains("same mode more than once"):
		params["repeat"] = true
	if rest.contains("you control a commander"):
		params["both_if_commander"] = true
	return params


## A permanent's "When ~ enters, choose one —" / "{2}, {T}: Choose one —" line and its bullets as one ability.
## The trigger or cost is read from the line with a stand-in effect, then the modes replace that effect.
func _modal_permanent_line(def: CardDefinition, line: String, bullets: Array) -> Array:
	var cm := _match("^(.*?)(?:, |: )?(choose (?:one or more|one or both|one|two|three)\\b.*) —$", line)
	if cm == null:
		return []
	var lead := cm.get_string(1).strip_edges()
	if lead == "":
		return []
	var sep := ": " if line.substr(lead.length()).begins_with(": ") else ", "
	var stand_in := OracleIr.new()._read_line(def, lead + sep + "you gain 1 life")
	if stand_in.size() != 1:
		return []
	var ab: Dictionary = stand_in[0]
	_self_it = str((ab.get("trigger", {}) as Dictionary).get("scope", "SELF")) == "SELF"
	var params := _modal_params(cm.get_string(2), bullets)
	if params.is_empty():
		return []
	ab["effects"] = [{"kind": "MODAL", "params": params}]
	ab["targets"] = []
	return [ab]


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
	var params := _modal_params(header, bullets)
	if params.is_empty():
		return {}
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
	var sentences: Array = []
	for sentence in effect_text.split(". "):
		var s := str(sentence).strip_edges().trim_suffix(".").strip_edges()
		if s != "":
			sentences.append(s)
	var i := 0
	while i < sentences.size():
		var s2: String = sentences[i]
		var nxt: String = sentences[i + 1] if i + 1 < sentences.size() else ""
		## Star Athlete: "Choose up to one target nonland permanent. Its controller may sacrifice it. If they don't, ~ deals 5 damage
		## to that player."
		var sa := _match("^choose up to one target (.+)$", str(s2))
		if sa != null and i + 2 < sentences.size():
			var sa2 := _match("^its controller may sacrifice it$", nxt)
			var sa3 := _match("^if they don't, ~ deals (\\d+) damage to that player$", str(sentences[i + 2]))
			if sa2 != null and sa3 != null:
				var sslot := _target("up to one target " + sa.get_string(1))
				if sslot >= 0:
					_effects.append({"kind": "UNLESS_SAC", "params": {"who": "CONTROLLER_OF_TARGET_%d" % sslot, "sac_target": sslot, "n": int(sa3.get_string(1))}})
					i += 3
					continue
		## "Target opponent reveals their hand. You choose a nonland card from it. That player discards that card."
		var rv := _match("^target (player|opponent) reveals their hand$", str(s2))
		if rv != null:
			var rslot := _target("target " + rv.get_string(1).to_lower())
			if rslot >= 0:
				var cm1 := _match("^you choose (?:a|an) (?:([a-z' ,-]+?) )?card from it$", nxt)
				var third: String = sentences[i + 2] if i + 2 < sentences.size() else ""
				if cm1 != null and _match("^that player discards (?:that card|it)$", third) != null:
					var rflt: Variant = _card_filter(cm1.get_string(1))
					if rflt != null:
						_effects.append({"kind": "DISCARD_CHOSEN", "params": {"target": rslot, "filter": rflt}})
						i += 3
						continue
				_effects.append({"kind": "REVEAL_HAND", "params": {"target": rslot}})
				i += 1
				continue
		## "Look at the top N cards of your library. You may reveal a X card from among them and put it into your hand.
		## Put the rest on the bottom ...": one LOOK_TOP effect.
		var used := _look_chain(sentences, i)
		if used > 0:
			i += used
			continue
		## "You may X. If you do, Y." : a yes / no question, then Y only when the answer was yes.
		if s2.to_lower().begins_with("you may ") and _match("^(?:if you do|when you do), ", nxt) != null:
			if not _may_chain(s2, nxt):
				return false
			i += 2
			continue
		if not _clause(s2):
			if not lenient:
				return false
			_effects.append({"kind": "NOTE_UNREAD", "params": {"text": s2}})
		i += 1
	for fx in _effects:
		if str((fx as Dictionary).get("kind", "")) != "NOTE_UNREAD":
			return true
	return false


## A lord: "Black creatures get +1/+1.", "Other Zombie creatures you control get +1/+1.", "Dragon creatures you control get
## +3/+3.", "Zombie creatures you control get +2/+1 and have deathtouch." Any group the grammar knows.
func _lord_static(line: String) -> Dictionary:
	var m := _match("^(.+?) (?:get ([+-]\\d+)/([+-]\\d+)(?: and (?:have|gain) ([a-z ,]+))?|(?:have|gain) ([a-z ,]+))$", line)
	if m == null:
		return {}
	var group := m.get_string(1).to_lower().trim_prefix("all ")
	var others := group.begins_with("other ")
	group = group.trim_prefix("other ")
	var of_chosen := group.contains(" of the chosen color")
	group = group.replace(" of the chosen color", "")
	if group.begins_with("target ") or group.contains(" and ") or group.contains("enchanted") or group.contains("equipped") or group.begins_with("~") or group.begins_with("each "):
		return {}
	var q := _event_subject(group, false)
	if q.is_empty():
		return {}
	if of_chosen:
		q["color"] = "$chosen"
	var kw_text := m.get_string(4) if m.get_string(4) != "" else m.get_string(5)
	var kws: Array = _keywords(kw_text) if kw_text != "" else []
	if kw_text != "" and kws.is_empty():
		return {}
	var spec := {"scope": "OTHERS" if others else "ALL", "query": q}
	if m.get_string(2) != "":
		spec["power"] = int(m.get_string(2))
		spec["toughness"] = int(m.get_string(3))
	if not kws.is_empty():
		spec["keywords"] = kws
	return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [], "static": spec}


## "~ costs {3} less to cast if <condition>" / "~ costs {1} less to cast for each <thing you control>" as a static ability.
func _self_discount(line: String) -> Dictionary:
	if _match("^~ costs \\{x\\} less to cast, where x is the total power of creatures you control$", line) != null:
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction_self": {"total_power": true}}}
	var m := _match("^~ costs \\{(\\d+)\\} less to cast if (.+)$", line)
	if m != null:
		var cond := _condition(m.get_string(2))
		if cond.is_empty():
			return {}
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction_self": {"amount": int(m.get_string(1)), "condition": cond}}}
	m = _match("^~ costs \\{(\\d+)\\} less to cast for each (.+)$", line)
	if m != null:
		var ce: Variant = _count_expr(m.get_string(2))
		if ce == null or not (ce as Dictionary).has("query"):
			return {}
		return {"kind": "STATIC", "costs": [], "targets": [], "effects": [], "restrictions": [],
			"static": {"scope": "SELF", "cost_reduction_self": {"amount": int(m.get_string(1)), "per": (ce as Dictionary)["query"]}}}
	return {}


## A card filter written before "card(s)": "creature", "Human creature", "nonland", "" (any card). null if not understood.
func _card_filter(text: String) -> Variant:
	var t := text.strip_edges().to_lower().replace(",", "")
	if t == "":
		return {}
	var basic := false
	if t.begins_with("basic "):
		basic = true
		t = t.substr(6)
	var words: Array = []
	for part in t.split(" ", false):
		words.append(str(part))
	var q := _general_query("target " + " ".join(PackedStringArray(words)))
	if q.is_empty():
		return null
	if basic:
		q["basic_land"] = true
		q.erase("type")
	return q


## The sentences from `i` that make up one "look at the top N cards" effect: [look, take..., rest...]. Returns how many
## were used, 0 if sentence i isn't such a start or a following one isn't understood.
func _look_chain(sentences: Array, i: int) -> int:
	var lm := _match("^(?:you )?(?:look at|reveal) the top (?:card|(a|one|two|three|four|five|six|seven|eight|nine|ten|\\d+|x) cards) of your library$", str(sentences[i]))
	if lm == null:
		return 0
	var n: Variant = 1 if lm.get_string(1) == "" else _amt(lm.get_string(1))
	var take := {}
	var rest := ""
	var used := 1
	while i + used < sentences.size():
		var s := str(sentences[i + used])
		var m := _match("^you may reveal (?:(a|an|up to one|up to two|one) )?([a-z' ,-]+?) cards? from among them and put (?:it|that card|them) into your hand$", s)
		var to := "HAND"
		if m == null:
			m = _match("^you may put (a|an|up to one|up to two) ([a-z' ,-]+?) cards? from among them (into your hand|onto the battlefield tapped|onto the battlefield)$", s)
			if m != null:
				to = "BATTLEFIELD" if m.get_string(3).contains("battlefield") else "HAND"
				if m.get_string(3).ends_with("tapped"):
					take["tapped"] = true
		if m != null and take.get("filter") == null:
			var flt: Variant = _card_filter(m.get_string(2))
			if flt == null:
				return 0
			take["filter"] = flt
			take["count"] = 2 if m.get_string(1).to_lower() == "up to two" else 1
			take["optional"] = true
			take["to"] = to
			used += 1
			continue
		m = _match("^put (one|a|two) of them into your hand and the rest (on the bottom of your library(?: in a random order| in any order)?|into your graveyard)$", s)
		if m != null and take.get("filter") == null:
			take["filter"] = {}
			take["count"] = _num(m.get_string(1))
			take["optional"] = false
			take["to"] = "HAND"
			var rr := m.get_string(2).to_lower()
			rest = "GRAVEYARD" if rr.contains("graveyard") else ("BOTTOM_RANDOM" if rr.contains("random") else "BOTTOM")
			used += 1
			break
		m = _match("^put (one|a|two) of them into your hand$", s)
		if m != null and take.get("filter") == null:
			take["filter"] = {}
			take["count"] = _num(m.get_string(1))
			take["optional"] = false
			take["to"] = "HAND"
			used += 1
			continue
		m = _match("^put the rest (?:of the cards )?(on the bottom of your library(?: in a random order| in any order)?|into your graveyard|on top of your library in any order)$", s)
		if m != null:
			var r := m.get_string(1).to_lower()
			rest = "GRAVEYARD" if r.contains("graveyard") else ("TOP" if r.contains("top") else ("BOTTOM_RANDOM" if r.contains("random") else "BOTTOM"))
			used += 1
			break
		break
	if take.is_empty() and rest == "":
		return 0
	var params := {"n": n}
	if not take.is_empty():
		params["take"] = take
	if rest != "":
		params["rest"] = rest
	_effects.append({"kind": "LOOK_TOP", "params": params})
	return used


## "You may sacrifice a creature. If you do, draw a card.": MAY (asks), the action and the payoff both gated on the answer.
func _may_chain(may_sentence: String, payoff_sentence: String) -> bool:
	var e0 := _effects.size()
	var t0 := _targets.size()
	_pay_links += 1
	var link := "may_%d" % _pay_links
	_effects.append({"kind": "MAY", "params": {"link": link, "prompt": may_sentence.substr(0, 1).to_upper() + may_sentence.substr(1) + "?"}})
	var a0 := _effects.size()
	if not _clause(may_sentence.substr(8)):
		_effects.resize(e0)
		_targets.resize(t0)
		return false
	var body := _match("^(?:if you do|when you do), (.+)$", payoff_sentence).get_string(1)
	if not _clause(body):
		_effects.resize(e0)
		_targets.resize(t0)
		return false
	for k in range(a0, _effects.size()):
		((_effects[k] as Dictionary)["params"] as Dictionary)["if_link"] = link
	return true


## "If you control a Dragon, draw a card" / "Draw a card if it's your turn": the effect with a condition gate.
## 1 = read, 0 = the condition was understood but the effect wasn't, -1 = no condition here.
func _gated_clause(s: String) -> int:
	var cond := {}
	var body := ""
	var lead := _match("^if (.+?), (.+)$", s)
	if lead != null:
		cond = _condition(lead.get_string(1))
		body = lead.get_string(2)
	if cond.is_empty():
		var low := s.to_lower()
		var at := low.rfind(" if ")
		while at > 0 and cond.is_empty():
			cond = _condition(s.substr(at + 4))
			if not cond.is_empty():
				body = s.substr(0, at)
			else:
				at = low.rfind(" if ", at - 1)
	if cond.is_empty():
		return -1
	var e0 := _effects.size()
	var t0 := _targets.size()
	if _clause(body):
		_gate_effects(e0, cond)
		return 1
	_effects.resize(e0)
	_targets.resize(t0)
	return 0


## One sentence, or two joined by ", then " / " and ". Anything half-read is rolled back.
func _clause(s: String) -> bool:
	if s.to_lower().begins_with("you may "):
		s = s.substr(8)
	if _self_it and s.to_lower().begins_with("it "):
		s = "~ " + s.substr(3)
	## "exile it" / "sacrifice it" on a trigger of the permanent itself means ~ (Mazemind Tome).
	if _self_it and s.to_lower() in ["exile it", "sacrifice it", "destroy it"]:
		s = s.substr(0, s.length() - 2) + "~"
	if _try(s):
		return true
	## A condition the specific readers don't know about ("... if you control three or more artifacts").
	var gated := _gated_clause(s)
	if gated >= 0:
		return gated == 1
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
	s = s.replace("−", "-")
	if s.to_lower().begins_with("then "):
		s = s.substr(5)
		if s.to_lower().begins_with("you may "):
			s = s.substr(8)
	## "you may have ~ deal 1 damage to that player" (the "may" is dropped before this): "have ~ deal" is "~ deals".
	if s.to_lower().begins_with("have ~ deal "):
		s = "~ deals " + s.substr(12)
	var hp := _match("^have that player (lose|discard|mill) (.+)$", s)
	if hp != null:
		s = "that player %ss %s" % [hp.get_string(1).to_lower(), hp.get_string(2)]
	## "Until end of turn, creatures you control gain trample": the duration moves to the end, where the readers look for it.
	if s.to_lower().begins_with("until end of turn, "):
		s = s.substr(19) + " until end of turn"
	## "~ deals 3 damage to target creature and 2 damage to target player": the second half has no subject.
	if _match("^\\d+ damage to ", s) != null:
		s = "~ deals " + s
	## "draw a card and gain 1 life": the second half has no subject.
	for verb in ["gain ", "lose ", "draw ", "discard ", "sacrifice ", "mill "]:
		if s.to_lower().begins_with(verb) and not s.to_lower().begins_with("gain control") and not s.to_lower().contains(" at the beginning of "):
			s = "you " + s
			break
	if _self_it and s.to_lower().begins_with("it "):
		s = "~ " + s.substr(3)
	## Amounts written as "..., where X is the number of ...", "equal to the number of ..." or "for each ...": the sentence
	## is read with X standing for that count.
	var rw := _rewrite_amount(s)
	if not rw.is_empty():
		_x_override = rw[1]
		var ok := _sentence(str(rw[0])) or _more_sentence(str(rw[0]))
		_x_override = null
		if ok:
			return true
		_targets.resize(t0)
		_effects.resize(e0)
		return false
	if _sentence(s):
		return true
	_targets.resize(t0)
	_effects.resize(e0)
	if _more_sentence(s):
		return true
	_targets.resize(t0)
	_effects.resize(e0)
	return false


## [sentence with X, what X is] for a sentence whose amount is a count; [] if it isn't one.
func _rewrite_amount(s: String) -> Array:
	var m := _match("^(.+), where x is (?:the number of|the amount of) (.+)$", s)
	if m != null:
		var e: Variant = _count_expr(m.get_string(2))
		return [m.get_string(1), e] if e != null else []
	m = _match("^(.+), where x is your life total$", s)
	if m != null:
		return [m.get_string(1), {"expr": "LIFE"}]
	m = _match("^((?:you )?put x \\+1/\\+1 counters? on target .+), where x is that creature's power$", s)
	if m != null:
		return [m.get_string(1), {"expr": "TARGET_POWER", "target": 0}]
	m = _match("^(.+), where x is the greatest power among creatures you control( until end of turn)?$", s)
	if m != null:
		return [m.get_string(1) + m.get_string(2), {"expr": "GREATEST_POWER"}]
	m = _match("^target player gains (\\d+) life for each (.+)$", s)
	if m != null:
		var tpe: Variant = _count_expr(m.get_string(2))
		if tpe != null:
			(tpe as Dictionary)["mult"] = int(m.get_string(1))
			return ["target player gains x life", tpe]
		return []
	m = _match("^you gain (\\d+) life for each spell you've cast this turn$", s)
	if m != null:
		return ["you gain x life", {"expr": "SPELLS_THIS_TURN", "mult": int(m.get_string(1))}]
	m = _match("^(.+), where x is your devotion to (white|blue|black|red|green)$", s)
	if m != null:
		return [m.get_string(1), {"expr": "DEVOTION", "color": COLOR_LETTERS[m.get_string(2).to_lower()]}]
	m = _match("^(?:you )?lose life equal to the number of (.+)$", s)
	if m != null:
		var le: Variant = _count_expr(m.get_string(1))
		return ["you lose x life", le] if le != null else []
	m = _match("^(?:~|it) deals damage equal to the number of (.+?) to (target .+)$", s)
	if m != null:
		var e2b: Variant = _count_expr(m.get_string(1))
		return ["~ deals x damage to " + m.get_string(2), e2b] if e2b != null else []
	m = _match("^(?:~|it) deals damage to (.+?) equal to the number of (.+)$", s)
	if m != null:
		var e2: Variant = _count_expr(m.get_string(2))
		return ["~ deals x damage to " + m.get_string(1), e2] if e2 != null else []
	m = _match("^(?:you )?gain life equal to the number of (.+)$", s)
	if m != null:
		var e3: Variant = _count_expr(m.get_string(1))
		return ["you gain x life", e3] if e3 != null else []
	m = _match("^(?:you )?draw cards equal to the number of (.+)$", s)
	if m != null:
		var e4: Variant = _count_expr(m.get_string(1))
		return ["draw x cards", e4] if e4 != null else []
	m = _match("^(?:you )?draw a card for each (.+)$", s)
	if m != null:
		var e5: Variant = _count_expr(m.get_string(1))
		return ["draw x cards", e5] if e5 != null else []
	m = _match("^(?:you )?gain (\\d+) life for each (.+)$", s)
	if m != null:
		var e6: Variant = _count_expr(m.get_string(2))
		if e6 != null:
			(e6 as Dictionary)["mult"] = int(m.get_string(1))
			return ["you gain x life", e6]
		return []
	m = _match("^(?:~|it) deals (\\d+) damage to (.+?) for each (.+)$", s)
	if m != null:
		var e7: Variant = _count_expr(m.get_string(3))
		if e7 != null:
			(e7 as Dictionary)["mult"] = int(m.get_string(1))
			return ["~ deals x damage to " + m.get_string(2), e7]
	return []


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
		if _match("^discard (a|an) card$", p) != null:
			costs.append({"kind": "DISCARD"})
			continue
		var rcm := _match("^remove (a|an|one|two|three|four|five|six|seven|\\d+) ([a-z0-9+/-]+) counters? from ~$", p)
		if rcm != null:
			var rn := _num(rcm.get_string(1))
			costs.append({"kind": "REMOVE_COUNTER", "mana": rcm.get_string(2).to_lower() + ("" if rn <= 1 else "|%d" % rn)})
			continue
		var epm := _match("^pay ((?:\\{e\\})+)$", p)
		if epm != null:
			costs.append({"kind": "PAY_ENERGY", "mana": str(epm.get_string(1).to_lower().count("{e}"))})
			continue
		if _match("^pay life equal to the number of colors in your commanders' color identity$", p) != null:
			costs.append({"kind": "PAY_LIFE", "mana": "ID_COLORS"})
			continue
		var sm := _match("^sacrifice (a|an|another|two|three|four|\\d+) ([a-z' -]+?)$", p)
		if sm != null:
			var scount := _num(sm.get_string(1))
			var sfirst := "another" if sm.get_string(1).to_lower() == "another" else "a"
			costs.append({"kind": "SACRIFICE", "mana": ("%s|%d|%s" % [sfirst, scount, sm.get_string(2).to_lower()]) if scount > 1 else ("%s|%s" % [sfirst, sm.get_string(2).to_lower()])})
			continue
		var upm := _match("^untap (a|an|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|\\d+) tapped ([a-z' -]+?) you control$", p)
		if upm != null:
			costs.append({"kind": "UNTAP_PERMANENTS", "mana": "a|%d|%s" % [_num(upm.get_string(1)), upm.get_string(2).to_lower()]})
			continue
		var tpm := _match("^tap (a|an|two|three|four|\\d+) untapped ([a-z' -]+?) you control$", p)
		if tpm != null:
			costs.append({"kind": "TAP_PERMANENTS", "mana": "a|%d|%s" % [_num(tpm.get_string(1)), tpm.get_string(2).to_lower()]})
			continue
		var rom := _match("^return (a|an|another) ([a-z' -]+?) you control to its owner's hand$", p)
		if rom != null:
			costs.append({"kind": "RETURN_OWN", "mana": "%s|%s" % ["another" if rom.get_string(1).to_lower() == "another" else "a", rom.get_string(2).to_lower()]})
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
	var any := false
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		if line == "":
			continue
		var kept: Array = []
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
			var own_disc := _self_discount(s)
			if not own_disc.is_empty():
				own_disc["ability_id"] = "%s_discount_%d" % [_snake(def.name), _extra.size()]
				_extra.append(own_disc)
				continue
			kept.append(s)
		## The line's remaining sentences are read together (chains like "look at the top N ..." and "you may X. If you do, Y"
		## span sentences). A sentence that isn't understood is announced in History when the spell resolves.
		if not kept.is_empty() and _read_effects(". ".join(PackedStringArray(kept))):
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


## Group and player effects that many cards share, tried when no specific reader matched:
## "Destroy all planeswalkers.", "Each player loses 2 life.", "Target creature can't block this turn."
func _more_sentence(s: String) -> bool:
	var m: RegExMatch
	## "... up to two target creatures ..." / "... each of up to two target creatures": one optional slot per target, the same
	## effect repeated for each (the slots are independent, so the same creature may be picked twice).
	m = _match("^(.*?)(?:each of )?up to (two|three) target ([a-z' -]+?)( you control| you don't control| an opponent controls)?( to their owners' hands| to their owner's hand)?$", s)
	if m != null:
		var words: Array = []
		var fixed := false
		for w in m.get_string(3).split(" ", false):
			if not fixed and w.ends_with("s") and not w.ends_with("ss"):
				words.append(_singular_type(w).to_lower())
				fixed = true
			else:
				words.append(w)
		if fixed:
			var single := m.get_string(1) + "up to one target " + " ".join(PackedStringArray(words)) + m.get_string(4) + (" to its owner's hand" if m.get_string(5) != "" else "")
			var t0 := _targets.size()
			var e0 := _effects.size()
			var all_ok := true
			for _i in _num(m.get_string(2)):
				if not _try(single):
					all_ok = false
					break
			if all_ok:
				return true
			_targets.resize(t0)
			_effects.resize(e0)
			return false
	m = _match("^(?:enchanted|equipped) creature gets ([+-]\\d+)/([+-]\\d+)(?: and gains ([a-z ,]+?))? until end of turn$", s)
	if m != null:
		var ak2: Array = []
		if m.get_string(3) != "":
			ak2 = _keywords(m.get_string(3))
			if ak2.is_empty():
				return false
		_effects.append({"kind": "PUMP", "params": {"attached": true, "power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "keywords": ak2, "duration": "END_OF_TURN"}})
		return true
	m = _match("^all ([a-z' -]+?) gain ([a-z ,]+?) until end of turn$", s)
	if m != null:
		var ak := _keywords(m.get_string(2))
		var aq := _event_subject(m.get_string(1), false)
		if ak.is_empty() or aq.is_empty():
			return false
		_effects.append({"kind": "PUMP", "params": {"each": aq, "keywords": ak, "duration": "END_OF_TURN"}})
		return true
	m = _match("^exile (target (?:artifact|creature|land|instant|sorcery|enchantment|planeswalker) card) from a graveyard$", s)
	if m != null:
		var gtype := m.get_string(1).to_lower().split(" ")[1]
		var gslot := _add_target("CARD_IN_ZONE", {"zone": "GRAVEYARD", "type": gtype})
		if gslot < 0:
			return false
		_effects.append({"kind": "EXILE_CARD", "params": {"target": gslot}})
		return true
	m = _match("^exile (target player)'s graveyard$", s)
	if m != null:
		var xp := _target(m.get_string(1))
		if xp < 0:
			return false
		_effects.append({"kind": "EXILE_GRAVEYARD", "params": {"who": "TARGET_%d" % xp}})
		return true
	m = _match("^(target creature you control) deals damage equal to its power to (target creature you don't control|target creature or planeswalker you don't control)$", s)
	if m != null:
		var ba := _target(m.get_string(1))
		var bb := _target(m.get_string(2))
		if ba < 0 or bb < 0:
			return false
		_effects.append({"kind": "FIGHT", "params": {"a": ba, "b": bb, "one_sided": true}})
		return true
	m = _match("^tap (up to one target .+)$", s)
	if m != null:
		var tt := _target(m.get_string(1))
		if tt < 0:
			return false
		_effects.append({"kind": "TAP", "params": {"target": tt}})
		return true
	m = _match("^~ gets ([+-]\\d+)/([+-]\\d+) and gains ([a-z ,]+?) until end of turn$", s)
	if m != null:
		var sk := _keywords(m.get_string(3))
		if sk.is_empty():
			return false
		_effects.append({"kind": "PUMP", "params": {"self": true, "power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "keywords": sk, "duration": "END_OF_TURN"}})
		return true
	m = _match("^(target creature) can't block this turn$", s)
	if m != null:
		var cb := _target(m.get_string(1))
		if cb < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": cb, "keywords": ["Can't block"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^creatures (you don't control|your opponents control|an opponent controls|without flying) can't block this turn$", s)
	if m != null:
		var cq := {"type": "creature"}
		if m.get_string(1).to_lower() == "without flying":
			cq["not_keyword"] = "Flying"
		else:
			cq["controller"] = "OPPONENT"
		_effects.append({"kind": "PUMP", "params": {"each": cq, "keywords": ["Can't block"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^(?:~|it) deals damage equal to its power to (.+)$", s)
	if m != null:
		return _damage({"expr": "SELF_POWER"}, m.get_string(1))
	## Creature lands: "~ becomes a 3/3 green and white Llama creature until end of turn." (+ "It's still a land.")
	m = _match("^~ becomes an? (\\d+)/(\\d+) ([a-z, ]+?) creature(?: with ([a-z ,]+?))?(?: until end of turn)?$", s)
	if m != null:
		var bk: Array = []
		if m.get_string(4) != "":
			bk = _keywords(m.get_string(4))
			if bk.is_empty():
				return false
		_effects.append({"kind": "BECOME_CREATURE", "params": {"power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "keywords": bk, "duration": "END_OF_TURN"}})
		return true
	if _match("^it's still an? (?:land|artifact|enchantment|permanent)$", s) != null:
		return true
	m = _match("^(create .+? creature tokens?) named .+$", s)
	if m != null:
		return _try(m.get_string(1))
	m = _match("^each creature you control with power (\\d+) or greater gets ([+-]\\d+)/([+-]\\d+)(?: and gains ([a-z ,]+?))? until end of turn$", s)
	if m != null:
		var ek: Array = []
		if m.get_string(4) != "":
			ek = _keywords(m.get_string(4))
			if ek.is_empty():
				return false
		_effects.append({"kind": "PUMP", "params": {"each": {"controller": "SOURCE_CONTROLLER", "type": "creature", "power_min": int(m.get_string(1))},
			"power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "keywords": ek, "duration": "END_OF_TURN"}})
		return true
	m = _match("^(creatures you control) gain ([a-z ,]+?) and get \\+(x|\\d+)/\\+(x|\\d+) until end of turn$", s)
	if m != null:
		var gk := _keywords(m.get_string(2))
		var gq2 := _event_subject(m.get_string(1), true)
		if gk.is_empty() or gq2.is_empty():
			return false
		_effects.append({"kind": "PUMP", "params": {"each": gq2, "power": _amt(m.get_string(3)), "toughness": _amt(m.get_string(4)), "keywords": gk, "duration": "END_OF_TURN"}})
		return true
	m = _match("^attach (?:it|~) to (target creature you control)$", s)
	if m != null:
		var at := _target(m.get_string(1))
		if at < 0:
			return false
		_effects.append({"kind": "ATTACH", "params": {"target": at}})
		return true
	if _match("^return (?:it|~) to its owner's hand$", s) != null:
		_effects.append({"kind": "SELF_TO_HAND", "params": {}})
		return true
	if _match("^(?:~|it) can't be blocked this turn$", s) != null:
		_effects.append({"kind": "PUMP", "params": {"self": true, "keywords": ["Unblockable"], "duration": "END_OF_TURN"}})
		return true
	if _match("^draw a card at the beginning of the next turn's upkeep$", s) != null:
		_effects.append({"kind": "DELAY", "params": {"step": "UPKEEP", "whose": "ANY", "action": "DRAW", "ref": "SELF"}})
		return true
	m = _match("^exile (target .+?) until ~ leaves the battlefield$", s)
	if m != null:
		var xs := _target(m.get_string(1))
		if xs < 0:
			return false
		_effects.append({"kind": "EXILE_UNTIL_LEAVES", "params": {"target": xs}})
		return true
	m = _match("^destroy all (.+)$", s)
	if m != null:
		var dq := _event_subject(m.get_string(1), false)
		if dq.is_empty():
			return false
		_effects.append({"kind": "DESTROY_ALL", "params": {"query": dq}})
		return true
	m = _match("^exile all (graveyards|opponents' graveyards)$", s)
	if m != null:
		_effects.append({"kind": "EXILE_GRAVEYARD", "params": {"who": "EACH_PLAYER" if m.get_string(1).to_lower() == "graveyards" else "EACH_OPPONENT"}})
		return true
	m = _match("^exile all (.+)$", s)
	if m != null:
		var xq := _event_subject(m.get_string(1), false)
		if xq.is_empty():
			return false
		_effects.append({"kind": "EXILE_ALL", "params": {"query": xq}})
		return true
	m = _match("^(untap|tap) (?:all|each) (.+)$", s)
	if m != null:
		var uq := _event_subject(m.get_string(2), false)
		if uq.is_empty():
			return false
		_effects.append({"kind": "UNTAP_EACH" if m.get_string(1).to_lower() == "untap" else "TAP_EACH", "params": {"query": uq}})
		return true
	m = _match("^regenerate (?:all|each) (.+)$", s)
	if m != null:
		var rq := _event_subject(m.get_string(1), false)
		if rq.is_empty():
			return false
		_effects.append({"kind": "REGENERATE", "params": {"each": rq}})
		return true
	m = _match("^each player loses (\\d+) life(?: and draws (a|one|two|three|\\d+) cards?)?$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "EACH_PLAYER"}})
		if m.get_string(2) != "":
			_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(2)), "who": "EACH_PLAYER"}})
		return true
	m = _match("^each player discards their hand, then draws (a|one|two|three|four|five|six|seven|\\d+) cards?$", s)
	if m != null:
		_effects.append({"kind": "DISCARD", "params": {"all": true, "who": "EACH_PLAYER"}})
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)), "who": "EACH_PLAYER"}})
		return true
	m = _match("^(?:(target creature) |it |that creature )?doesn't untap during its controller's next untap step$", s)
	if m != null:
		var fz := -1
		if m.get_string(1) != "":
			fz = _target(m.get_string(1))
		elif not _targets.is_empty():
			fz = _targets.size() - 1
		if fz < 0:
			return false
		_effects.append({"kind": "FREEZE", "params": {"target": fz}})
		return true
	m = _match("^if that (?:creature|permanent|creature or planeswalker) would die this turn, exile it instead$", s)
	if m != null and not _targets.is_empty():
		_effects.append({"kind": "EXILE_IF_DIES", "params": {"target": _targets.size() - 1}})
		return true
	m = _match("^(target creature) has base power and toughness (\\d+)/(\\d+) until end of turn$", s)
	if m != null:
		var bt := _target(m.get_string(1))
		if bt < 0:
			return false
		_effects.append({"kind": "SET_CHARACTERISTICS", "params": {"target": bt, "power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "duration": "END_OF_TURN"}})
		return true
	m = _match("^target (player|opponent) creates (a|an|one|two|three) (treasure|food|clue) tokens?$", s)
	if m != null:
		var cp := _target("target " + m.get_string(1).to_lower())
		if cp < 0:
			return false
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": m.get_string(3).to_lower(), "count": _num(m.get_string(2)), "for": "TARGET_PLAYER_%d" % cp}})
		return true
	m = _match("^you may play (?:it|that card) this turn$", s)
	if m != null and not _effects.is_empty() and str((_effects[_effects.size() - 1] as Dictionary).get("kind", "")) == "EXILE_TOP":
		((_effects[_effects.size() - 1] as Dictionary)["params"] as Dictionary)["may_play"] = "END_OF_TURN"
		return true
	m = _match("^(?:you )?draw (an|one|two|three) additional cards?$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)) if m.get_string(1) != "an" else 1}})
		return true
	m = _match("^(target creature) attacks this turn if able$", s)
	if m != null:
		var ma := _target(m.get_string(1))
		if ma < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": ma, "keywords": ["Must attack"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^(target opponent|each opponent) loses that much life$", s)
	if m != null:
		if m.get_string(1).to_lower() == "each opponent":
			_effects.append({"kind": "LOSE_LIFE", "params": {"n": {"expr": "EVENT_AMOUNT"}, "who": "EACH_OPPONENT"}})
		else:
			var lt := _target("target opponent")
			if lt < 0:
				return false
			_effects.append({"kind": "LOSE_LIFE", "params": {"n": {"expr": "EVENT_AMOUNT"}, "target": lt}})
		return true
	if _match("^you gain that much life$", s) != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "EVENT_AMOUNT"}}})
		return true
	m = _match("^take (an|one|two|three) extra turns? after this one$", s)
	if m != null:
		_effects.append({"kind": "EXTRA_TURN", "params": {"n": _num(m.get_string(1)) if m.get_string(1) != "an" else 1}})
		return true
	if _match("^at the beginning of that turn's end step, you lose the game$", s) != null and not _effects.is_empty() \
			and str((_effects[_effects.size() - 1] as Dictionary).get("kind", "")) == "EXTRA_TURN":
		((_effects[_effects.size() - 1] as Dictionary)["params"] as Dictionary)["lose"] = true
		return true
	if _match("^for each creature token you control, create a token that's a copy of that creature$", s) != null:
		_effects.append({"kind": "COPY_EACH", "params": {"query": {"controller": "SOURCE_CONTROLLER", "type": "creature", "token": true}}})
		return true
	if _match("^end the turn$", s) != null:
		_effects.append({"kind": "END_TURN", "params": {}})
		return true
	m = _match("^you get ((?:\\{e\\})+)$", s)
	if m != null:
		_effects.append({"kind": "GET_ENERGY", "params": {"n": m.get_string(1).to_lower().count("{e}")}})
		return true
	m = _match("^(?:~|it) deals (\\d+) damage to you$", s)
	if m != null:
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(1)), "who": "CONTROLLER"}})
		return true
	if _match("^untap ~$", s) != null:
		_effects.append({"kind": "UNTAP", "params": {"self": true}})
		return true
	m = _match("^untap (another target .+)$", s)
	if m != null:
		var ut := _target(m.get_string(1))
		if ut < 0:
			return false
		_effects.append({"kind": "UNTAP", "params": {"target": ut}})
		return true
	m = _match("^put (target [a-z ]+?) on the bottom of its owner's library$", s)
	if m != null:
		var bt := _target(m.get_string(1))
		if bt < 0:
			return false
		_effects.append({"kind": "TUCK", "params": {"target": bt, "where": "bottom"}})
		return true
	m = _match("^it has \"(.+?)\\.?\"$", s)
	if m != null and not _effects.is_empty() and str((_effects[_effects.size() - 1] as Dictionary).get("kind", "")) == "CREATE_TOKEN":
		var tp: Dictionary = (_effects[_effects.size() - 1] as Dictionary)["params"]
		var spec: Dictionary = tp.get("spec", {})
		if spec.is_empty():
			return false
		var trules: Array = spec.get("rules", [])
		trules.append(m.get_string(1) + ".")
		spec["rules"] = trules
		tp["spec"] = spec
		return true
	if _match("^(?:you )?discard all the cards in your hand, then draw that many cards$", s) != null:
		_effects.append({"kind": "DISCARD", "params": {"all": true}})
		_effects.append({"kind": "DRAW", "params": {"n": {"expr": "DISCARDED_COUNT"}}})
		return true
	m = _match("^each player discards (a|one|two|three|\\d+) cards?$", s)
	if m != null:
		_effects.append({"kind": "DISCARD", "params": {"n": _num(m.get_string(1)), "who": "EACH_PLAYER"}})
		return true
	m = _match("^put (target [a-z ]+?) on top of its owner's library$", s)
	if m != null:
		var tk := _target(m.get_string(1))
		if tk < 0:
			return false
		_effects.append({"kind": "TUCK", "params": {"target": tk, "where": "top"}})
		return true
	m = _match("^(target (?:opponent|player)) exiles (a|an|one|two|three|\\d+) ([a-z' -]+?) (?:they|that player) controls?$", s)
	if m != null:
		var xq := _group_query(m.get_string(3))
		if xq.is_empty():
			return false
		var xp := _target(m.get_string(1))
		if xp < 0:
			return false
		_effects.append({"kind": "SACRIFICE", "params": {"n": _num(m.get_string(2)), "who": "TARGET_%d" % xp, "query": xq, "to": "EXILE"}})
		return true
	m = _match("^(target (?:opponent|player)) sacrifices (a|an|one|two|three|\\d+) ([a-z' -]+?)(?: of (?:their|his or her) choice)?$", s)
	if m != null:
		var sq := _group_query(m.get_string(3))
		if sq.is_empty():
			return false
		var sp := _target(m.get_string(1))
		if sp < 0:
			return false
		_effects.append({"kind": "SACRIFICE", "params": {"n": _num(m.get_string(2)), "who": "TARGET_%d" % sp, "query": sq}})
		return true
	m = _match("^destroy (target .+?) that was dealt damage this turn$", s)
	if m != null:
		var dd := _target(m.get_string(1))
		if dd < 0:
			return false
		var dtq: Dictionary = (_targets[dd] as Dictionary).get("query", {})
		dtq["damaged"] = true
		(_targets[dd] as Dictionary)["query"] = dtq
		_effects.append({"kind": "DESTROY", "params": {"target": dd}})
		return true
	m = _match("^(?:~|it) deals (\\d+|x) damage to each creature( without flying)? and each planeswalker( you don't control)?$", s)
	if m != null:
		var pq := {"type_any": ["creature", "planeswalker"]}
		if m.get_string(2) != "":
			pq["not_keyword"] = "Flying"
		if m.get_string(3) != "":
			pq["controller"] = "OPPONENT"
		_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": _amt(m.get_string(1)), "query": pq}})
		return true
	m = _match("^search your library for (?:a|an|one) ([a-z ,]+?) card, reveal it, then shuffle and put that card on top$", s)
	if m != null:
		var tf: Variant = _card_filter(m.get_string(1))
		if tf == null:
			return false
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filter": tf, "n": 1, "to": "TOP"}})
		return true
	m = _match("^search your library for an? ([a-z]+) card and an? ([a-z]+) card, put them onto the battlefield( tapped)?, then shuffle$", s)
	if m != null:
		var f1: Variant = _card_filter(m.get_string(1))
		var f2: Variant = _card_filter(m.get_string(2))
		if f1 == null or f2 == null:
			return false
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filters": [f1, f2], "n": 1, "to": "BATTLEFIELD", "tapped": m.get_string(3) != ""}})
		return true
	m = _match("^look at the top (a|one|two|three|four|five|six|seven|x|\\d+) cards? of your library, then put them back in any order$", s)
	if m != null:
		_effects.append({"kind": "REORDER_TOP", "params": {"n": _amt(m.get_string(1))}})
		return true
	if _match("^put (?:~|it) on top of its owner's library$", s) != null:
		_effects.append({"kind": "TUCK", "params": {"self": true, "where": "top"}})
		return true
	if _match("^put your commander into your hand from the command zone$", s) != null:
		_effects.append({"kind": "COMMANDER_TO_HAND", "params": {}})
		return true
	m = _match("^(target player) returns each commander they control from the battlefield to the command zone$", s)
	if m != null:
		var cv := _target(m.get_string(1))
		if cv < 0:
			return false
		_effects.append({"kind": "COMMANDERS_TO_COMMAND", "params": {"who": "TARGET_%d" % cv}})
		return true
	m = _match("^that (?:creature|permanent)'s controller creates (.+)$", s)
	if m != null:
		var before := _effects.size()
		if _try("create " + m.get_string(1)) and _effects.size() > before and str((_effects[_effects.size() - 1] as Dictionary).get("kind", "")) == "CREATE_TOKEN":
			((_effects[_effects.size() - 1] as Dictionary)["params"] as Dictionary)["for"] = "TARGET_CONTROLLER"
			return true
		return false
	m = _match("^put (?:~|it) into (?:your|its owner's) library (second|third|fourth|fifth|sixth|seventh) from the top$", s)
	if m != null:
		_effects.append({"kind": "SELF_TO_LIBRARY", "params": {"from_top": {"second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7}[m.get_string(1).to_lower()]}})
		return true
	m = _match("^remove (target attacking creature you control) from combat and untap it$", s)
	if m != null:
		var rc := _target("target creature you control")
		if rc < 0:
			return false
		_effects.append({"kind": "REMOVE_FROM_COMBAT", "params": {"target": rc}})
		return true
	if _match("^(?:you )?discard any number of cards, then draw that many cards$", s) != null:
		_effects.append({"kind": "DISCARD_ANY_DRAW", "params": {}})
		return true
	m = _match("^up to (two|three) target ([a-z' -]+?) each get (.+)$", s)
	if m != null:
		var nw: Array = m.get_string(2).split(" ", false)
		if not nw.is_empty() and str(nw[nw.size() - 1]).ends_with("s"):
			nw[nw.size() - 1] = _singular_type(str(nw[nw.size() - 1])).to_lower()
			var single_each := "up to one target " + " ".join(PackedStringArray(nw)) + " gets " + m.get_string(3)
			var te0 := _targets.size()
			var ee0 := _effects.size()
			var each_ok := true
			for _k in _num(m.get_string(1)):
				if not _try(single_each):
					each_ok = false
					break
			if each_ok:
				return true
			_targets.resize(te0)
			_effects.resize(ee0)
			return false
	m = _match("^(.+?) get ([+-]\\d+)/([+-]\\d+) until end of turn$", s)
	if m != null and not m.get_string(1).to_lower().begins_with("target"):
		var gq := _event_subject(m.get_string(1).to_lower().trim_prefix("all ").trim_prefix("each "), false)
		if gq.is_empty() or not str(gq.get("type", "")) == "creature":
			return false
		_effects.append({"kind": "PUMP", "params": {"each": gq, "power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "duration": "END_OF_TURN"}})
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
	m = _match("^(target creature(?: with power \\d+ or (?:less|greater))?) can't be blocked this turn$", s)
	if m != null:
		var ub := _target(m.get_string(1))
		if ub < 0:
			return false
		_effects.append({"kind": "PUMP", "params": {"target": ub, "keywords": ["Unblockable"], "duration": "END_OF_TURN"}})
		return true
	m = _match("^((?:another )?target .+?) gets \\+x/\\+0 and gains ([a-z ,]+) until end of turn$", s)
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
	if _match("^(?:you )?sacrifice (?:~|it)$", s) != null:
		_effects.append({"kind": "SACRIFICE", "params": {"self": true}})
		return true
	# "You may play an additional land this turn." / "Put that many +1/+1 counters on each creature you control."
	if _match("^(?:you may )?play an additional land this turn$", s) != null:
		_effects.append({"kind": "EXTRA_LAND", "params": {"n": 1}})
		return true
	if _match("^put that many \\+1/\\+1 counters on each creature you control$", s) != null:
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": {"expr": "EVENT_AMOUNT"}, "each": {"controller": "SOURCE_CONTROLLER", "type": "creature"}}})
		return true
	# "If you do, you gain 4 life." after a mandatory action ("exile it. If you do, ..."): it simply follows.
	m = _match("^if you do, (.+)$", s)
	if m != null and _pay_links == 0 and not _effects.is_empty():
		return _clause(m.get_string(1))
	# Thirst for Knowledge: "Discard two cards unless you discard an artifact card."
	m = _match("^you discard (a|an|one|two|three|\\d+) cards? unless you discard an? ([a-z]+) card$", s)
	if m != null:
		_effects.append({"kind": "DISCARD_ALT", "params": {"n": _num(m.get_string(1)), "unless_type": m.get_string(2).to_lower()}})
		return true
	# Master Transmuter: "You may put an artifact card from your hand onto the battlefield."
	m = _match("^put (?:a|an) ([a-z' -]+?) card from your hand onto the battlefield( tapped)?$", s)
	if m != null:
		var hq: Variant = _card_filter(m.get_string(1))
		if hq == null:
			return false
		_effects.append({"kind": "PUT_FROM_HAND", "params": {"query": hq, "optional": true, "tapped": m.get_string(2) != ""}})
		return true
	# "~ deals 2 damage to that player unless they sacrifice a creature of their choice." (Mogis, God of Slaughter)
	m = _match("^(?:~|it) deals (\\d+) damage to that player unless they sacrifice (?:a|an) ([a-z' -]+?)(?: of their choice)?$", s)
	if m != null:
		var usq := _group_query(m.get_string(2))
		if usq.is_empty():
			return false
		_effects.append({"kind": "UNLESS_SAC", "params": {"who": "TRIGGER_PLAYER", "query": usq, "n": int(m.get_string(1))}})
		return true
	# Enchanter's Bane: "target enchantment deals damage equal to its mana value to its controller unless that player sacrifices it."
	m = _match("^(target .+?) deals damage equal to its mana value to its controller unless that player sacrifices it$", s)
	if m != null:
		var ebs := _target(m.get_string(1))
		if ebs < 0:
			return false
		_effects.append({"kind": "UNLESS_SAC", "params": {"who": "CONTROLLER_OF_TARGET_%d" % ebs, "sac_target": ebs, "n": {"expr": "TARGET_MV", "target": ebs}}})
		return true
	# "Target player draws two cards and loses 2 life." (Sign in Blood): one chosen player for both halves.
	m = _match("^target player draws (a|an|one|two|three|four|five|\\d+) cards? and loses (\\d+) life$", s)
	if m != null:
		var dl := _add_target("PLAYER", {})
		if dl < 0:
			return false
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)), "who": "TARGET_%d" % dl}})
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(2)), "who": "TARGET_%d" % dl}})
		return true
	# "If it's an Angel, put two +1/+1 counters on it." (Defy Death: the card that just came back)
	m = _match("^if it's an? ([a-z]+), put (a|an|one|two|three|\\d+) \\+1/\\+1 counters? on it$", s)
	if m != null and not _effects.is_empty():
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": "+1/+1", "n": _num(m.get_string(2)), "moved": true, "if_moved_subtype": _cap(m.get_string(1))}})
		return true
	# "Exile up to two target artifacts and/or enchantments." (Angel of the Ruins): one optional slot per target.
	m = _match("^(destroy|exile) up to (two|three) target (.+)$", s)
	if m != null:
		var uphrase := m.get_string(3).to_lower().replace(" and/or ", " or ")
		var uwords: Array = []
		for part in uphrase.split(" ", false):
			var uw := str(part)
			uwords.append(_singular_type(uw).to_lower() if uw.ends_with("s") and not uw.ends_with("ss") else uw)
		var ok_up := true
		var slots: Array = []
		for _i in _num(m.get_string(2)):
			var us2 := _target("up to one target " + " ".join(PackedStringArray(uwords)))
			if us2 < 0:
				ok_up = false
				break
			slots.append(us2)
		if not ok_up:
			return false
		for sl in slots:
			if m.get_string(1).to_lower() == "destroy":
				_effects.append({"kind": "DESTROY", "params": {"target": sl}})
			else:
				_effects.append({"kind": "MOVE_ZONE", "params": {"target": sl, "to": "EXILE"}})
		return true
	# "You and target opponent each draw three cards." (Secret Rendezvous) / Cut a Deal.
	m = _match("^you and target opponent each draw (a|an|one|two|three|four|five|\\d+) cards?$", s)
	if m != null:
		var rs := _add_target("PLAYER", {"opponent": true})
		if rs < 0:
			return false
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1))}})
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)), "who": "TARGET_%d" % rs}})
		return true
	if _match("^each opponent draws a card, then you draw a card for each opponent who drew a card this way$", s) != null:
		_effects.append({"kind": "DRAW", "params": {"n": 1, "who": "EACH_OPPONENT"}})
		_effects.append({"kind": "DRAW", "params": {"n": {"expr": "OPPONENTS"}}})
		return true
	# "you gain that much life" (Metropolis Reformer: after being dealt damage).
	if _match("^you gain that much life$", s) != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "EVENT_AMOUNT"}}})
		return true
	# Each player: "each player draws a card and loses 1 life" (Stormfist Crusader).
	# "Each player draws a card, then discards a card." (Geier Reach Sanitarium)
	m = _match("^each player draws (a|an|one|two|three|\\d+) cards?, then discards (a|an|one|two|three|\\d+) cards?$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)), "who": "EACH_PLAYER"}})
		_effects.append({"kind": "DISCARD", "params": {"n": _num(m.get_string(2)), "who": "EACH_PLAYER"}})
		return true
	# "Each player sacrifices a creature of their choice." / "Each other player sacrifices six creatures."
	m = _match("^each (player|other player|opponent) sacrifices (a|an|one|two|three|four|five|six|seven|\\d+) ([a-z' -]+?)(?: of their choice)?$", s)
	if m != null:
		var esq := _group_query(m.get_string(3))
		if esq.is_empty():
			return false
		_effects.append({"kind": "SACRIFICE", "params": {"n": _num(m.get_string(2)), "who": "EACH_PLAYER" if m.get_string(1) == "player" else "EACH_OPPONENT", "query": esq}})
		return true
	# "All creatures get -1/-1 until end of turn for each Swamp you control." (Mutilate)
	m = _match("^(?:all|each) creatures get ([+-]\\d+)/([+-]\\d+) until end of turn for each (.+)$", s)
	if m != null:
		var mce: Variant = _count_expr(m.get_string(3))
		if mce != null and (mce as Dictionary).has("query"):
			var mq: Dictionary = (mce as Dictionary)["query"]
			var pw := {"query": mq, "mult": int(m.get_string(1))}
			var tg := {"query": mq, "mult": int(m.get_string(2))}
			_effects.append({"kind": "PUMP", "params": {"each": {"type": "creature"}, "power": pw, "toughness": tg, "duration": "END_OF_TURN"}})
			return true
	m = _match("^each player draws (a|an|one|two|three|\\d+) cards?(?: and loses (\\d+) life)?$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)), "who": "EACH_PLAYER"}})
		if m.get_string(2) != "":
			_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(2)), "who": "EACH_PLAYER"}})
		return true
	# "That player draws an additional card" (Spiteful Visions), "they lose 1 life", "that player loses 3 life".
	m = _match("^(?:that player|they) draws? (a|an|one|two|three|\\d+) cards?$", s)
	if m != null and m.get_string(1) != "an additional":
		_effects.append({"kind": "DRAW", "params": {"n": _num(m.get_string(1)), "who": "TRIGGER_PLAYER"}})
		return true
	m = _match("^(?:that player|they) draws? an additional card$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": 1, "who": "TRIGGER_PLAYER"}})
		return true
	m = _match("^(?:that player|they) loses? (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "TARGET_CONTROLLER" if not _targets.is_empty() else "TRIGGER_PLAYER"}})
		return true
	# "Destroy target creature. You lose life equal to that permanent's mana value." (Feed the Swarm)
	m = _match("^you lose life equal to that (?:permanent|creature)'s mana value$", s)
	if m != null and not _targets.is_empty():
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": {"expr": "TARGET_MV", "target": _targets.size() - 1}, "who": "CONTROLLER"}})
		return true
	# "~ deals that much damage to target opponent" (Brash Taunter), "deals 1 damage to that creature's controller".
	m = _match("^(?:~|it) deals that much damage to (target .+)$", s)
	if m != null:
		var tm := _target(m.get_string(1))
		if tm < 0:
			return false
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": {"expr": "EVENT_AMOUNT"}, "target": tm}})
		return true
	m = _match("^(?:~|it) deals (\\d+) damage to that (?:creature's controller|permanent's controller)$", s)
	if m != null:
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(1)), "who": "TRIGGER_PLAYER"}})
		return true
	m = _match("^(?:~|it) deals damage equal to that spell's mana value to (.+)$", s)
	if m != null:
		return _damage({"expr": "SPELL_MV"}, m.get_string(1))
	# Gray Merchant: "each opponent loses X life" / "you gain life equal to the life lost this way".
	m = _match("^each opponent loses (\\d+|x) life$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": _amt(m.get_string(1)), "who": "EACH_OPPONENT"}})
		return true
	if _match("^you gain life equal to the life lost this way$", s) != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "LIFE_LOST"}}})
		return true
	m = _match("^(?:~|it) deals damage equal to its power to that player$", s)
	if m != null:
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": {"expr": "SELF_POWER"}, "who": "TRIGGER_PLAYER"}})
		return true
	m = _match("^(?:~|it) deals (\\d+) damage to that player$", s)
	if m != null:
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": int(m.get_string(1)), "who": "TRIGGER_PLAYER"}})
		return true
	m = _match("^that player (loses|discards|mills) (\\d+|a|one|two|three) (?:life|cards?)$", s)
	if m != null:
		var tn := _num(m.get_string(2))
		match m.get_string(1).to_lower():
			"loses":
				_effects.append({"kind": "LOSE_LIFE", "params": {"n": tn, "who": "TRIGGER_PLAYER"}})
			"discards":
				_effects.append({"kind": "DISCARD", "params": {"n": tn, "who": "TRIGGER_PLAYER"}})
			_:
				_effects.append({"kind": "MILL", "params": {"n": tn, "who": "TRIGGER_PLAYER"}})
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
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": _amt("x")}})
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
	if _match("^investigate once for each opponent who has more cards in hand than you$", s) != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": "clue", "count": {"expr": "OPP_MORE_HAND"}}})
		return true
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
	m = _match("^(?:~|it) deals (\\d+|x) damage to (.+)$", s)
	if m != null:
		return _damage(_amt(m.get_string(1)), m.get_string(2))

	# CR 701.7: destroy.
	m = _match("^destroy all (?:non-?([a-z]+) )?creatures$", s)
	if m != null:
		var q := {"type": "creature"}
		if m.get_string(1) != "":
			q["not_subtype"] = _cap(m.get_string(1))
		_effects.append({"kind": "DESTROY_ALL", "params": {"query": q}})
		return true
	# "Return all attacking creatures to their owners' hands." / "Each player sacrifices all permanents they control that are
	# one or more colors." / "Exile each opponent's graveyard." / "Destroy all artifacts, creatures, and enchantments."
	if _match("^return all attacking creatures to (?:their owners' hands|their owner's hand)$", s) != null:
		_effects.append({"kind": "MOVE_ALL", "params": {"query": {"type": "creature", "attacking": true}, "to": "HAND"}})
		return true
	if _match("^each player sacrifices all permanents they control that are one or more colors$", s) != null:
		_effects.append({"kind": "MOVE_ALL", "params": {"query": {"colored": true}, "to": "GRAVEYARD"}})
		return true
	if _match("^exile each opponent's graveyard$", s) != null:
		_effects.append({"kind": "EXILE_GRAVEYARD", "params": {"who": "EACH_OPPONENT"}})
		return true
	m = _match("^destroy all (artifacts|creatures|enchantments|lands|planeswalkers)(?:,? (artifacts|creatures|enchantments|lands|planeswalkers))*(?:,? and (artifacts|creatures|enchantments|lands|planeswalkers))$", s)
	if m != null:
		var dtypes: Array = []
		for part in s.to_lower().trim_prefix("destroy all ").replace(", and ", ",").replace(" and ", ",").split(","):
			dtypes.append(str(part).strip_edges().trim_suffix("s"))
		_effects.append({"kind": "DESTROY_ALL", "params": {"query": {"type_any": dtypes}}})
		return true
	# "Destroy all tapped creatures." / "Destroy all artifacts and enchantments your opponents control."
	m = _match("^destroy all ((?:[a-z]+ )*(?:creatures?|artifacts?|enchantments?|lands?|permanents?)(?: you control| your opponents control| an opponent controls)?(?: with mana value \\d+(?: or less| or greater)?)?)$", s)
	if m != null:
		var dq := _event_subject(m.get_string(1), false)
		if dq.is_empty():
			return false
		_effects.append({"kind": "DESTROY_ALL", "params": {"query": dq}})
		return true
	# "Return a land you control to its owner's hand." (a permanent of your choice goes back)
	m = _match("^return (a|an|another|two) ([a-z ]+?) you control to its owner's hand$", s)
	if m != null:
		var rq := _group_query(m.get_string(2))
		if m.get_string(2).to_lower() == "permanent":
			rq = {"type_any": ["creature", "artifact", "enchantment", "land", "planeswalker", "battle"]}
		if rq.is_empty():
			return false
		if m.get_string(1).to_lower() == "another":
			rq["other"] = true
		_effects.append({"kind": "SACRIFICE", "params": {"n": _num(m.get_string(1)), "who": "CONTROLLER", "query": rq, "to": "HAND"}})
		return true
	m = _match("^destroy ((?:up to one )?target .+)$", s)
	if m != null:
		var slot := _target(m.get_string(1))
		if slot < 0:
			return false
		_effects.append({"kind": "DESTROY", "params": {"target": slot}})
		return true

	# CR 701.13: exile.
	m = _match("^exile ((?:up to one )?target .+)$", s)
	if m != null:
		var slot2 := _target(m.get_string(1))
		if slot2 < 0:
			return false
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": slot2, "to": "EXILE"}})
		return true

	# Bounce.
	m = _match("^return ((?:up to one )?target .+?) to its owner's hand$", s)
	if m != null:
		var slot3 := _target(m.get_string(1))
		if slot3 < 0:
			return false
		_effects.append({"kind": "MOVE_ZONE", "params": {"target": slot3, "to": "HAND"}})
		return true

	# Back from the graveyard.
	m = _match("^return (another )?target (.+?) card(?: with mana value (\\d+) or (less|greater))? from your graveyard to (your hand|the battlefield)(?: tapped)?$", s)
	if m != null:
		var gq := {"zone": "GRAVEYARD", "controller": "SOURCE_CONTROLLER"}
		if m.get_string(1) != "":
			gq["other"] = true
		var noun := m.get_string(2).to_lower()
		if noun in ["creature", "artifact", "enchantment", "land", "planeswalker"]:
			gq["type"] = noun
		elif _match("^(artifact|creature|enchantment|land|planeswalker) or (artifact|creature|enchantment|land|planeswalker)$", noun) != null:
			gq["type_any"] = noun.split(" or ")
		elif noun != "permanent":
			gq["subtype"] = _cap(noun)
		if m.get_string(3) != "" and m.get_string(3).to_lower() != "x":
			gq["mv_max" if m.get_string(4).to_lower() == "less" else "mv_min"] = int(m.get_string(3))
		var idx := _targets.size()
		_targets.append({"id": idx, "kind": "CARD_IN_ZONE", "count": 1, "query": gq})
		_effects.append({"kind": "RETURN_FROM_GRAVEYARD", "params": {"target": idx, "to": "HAND" if m.get_string(5) == "your hand" else "BATTLEFIELD"}})
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
	m = _match("^(?:you )?draw (a|an|one|two|three|four|five|\\d+|x) cards?$", s)
	if m != null:
		_effects.append({"kind": "DRAW", "params": {"n": _amt(m.get_string(1))}})
		return true

	# CR 119: life.
	m = _match("^you gain (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": int(m.get_string(1))}})
		return true
	m = _match("^you gain life equal to (?:that creature's|its) (toughness|power)$", s)
	if m != null:
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "TRIGGER_TOUGHNESS" if m.get_string(1).to_lower() == "toughness" else "TRIGGER_POWER"}}})
		return true
	m = _match("^target player gains (\\d+|x) life$", s)
	if m != null:
		var pslot := _add_target("PLAYER", {})
		if pslot < 0:
			return false
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": _amt(m.get_string(1)), "target": pslot}})
		return true
	m = _match("^each opponent loses (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "EACH_OPPONENT"}})
		return true
	if _match("^you lose x life$", s) != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": _amt("x"), "who": "CONTROLLER"}})
		return true
	# Warstorm Surge: "it deals damage equal to its power to any target" (the creature that entered).
	m = _match("^(?:it|that creature) deals damage equal to its power to (any target|target .+)$", s)
	if m != null and _targets.is_empty():
		var wt := _target(m.get_string(1))
		if wt < 0:
			return false
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": {"expr": "TRIGGER_POWER"}, "target": wt, "from_trigger_object": true}})
		return true
	m = _match("^you lose (\\d+) life$", s)
	if m != null:
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "who": "CONTROLLER"}})
		return true
	m = _match("^target player loses (\\d+) life$", s)
	if m != null:
		var plslot := _add_target("PLAYER", {})
		if plslot < 0:
			return false
		_effects.append({"kind": "LOSE_LIFE", "params": {"n": int(m.get_string(1)), "target": plslot}})
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
	m = _match("^create (a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|twenty|\\d+) (tapped )?(treasure|food|clue|junk|blood) tokens?$", s)
	if m != null:
		_effects.append({"kind": "CREATE_TOKEN", "params": {"token": m.get_string(3).to_lower(), "count": _num(m.get_string(1)), "tapped": m.get_string(2) != ""}})
		return true
	var token_for := ""
	if s.to_lower().begins_with("its controller creates "):
		token_for = "TARGET_CONTROLLER"
		s = "create " + s.substr(23)
	## A token with its own rules: create a 1/1 Devil creature token with "When this creature dies, it deals 1 damage to any target."
	var token_rules: Array = []
	var qi := s.find("\"")
	if qi > 0 and s.to_lower().begins_with("create ") and s.ends_with("\""):
		token_rules.append(s.substr(qi + 1, s.length() - qi - 2).trim_suffix(".").strip_edges())
		s = s.substr(0, qi).strip_edges().trim_suffix(" and").trim_suffix(" with")
	var x_count: Variant = null
	var xm := _match("^(create x .+?), where x is (?:its|that creature's|~'s) (power|toughness)$", s)
	if xm != null:
		s = RegEx.create_from_string("(?i)^create x ").sub(xm.get_string(1), "create one ")
		x_count = {"expr": "TRIGGER_POWER" if xm.get_string(2).to_lower() == "power" else "TRIGGER_TOUGHNESS"}
	m = _match("^create (a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|twenty|x|\\d+) (tapped )?(\\d+)/(\\d+) ((?:white|blue|black|red|green|colorless)(?:(?:,| and|, and) (?:white|blue|black|red|green))*) ([a-z' -]+?) (artifact )?creature tokens?(?: with ([a-z ,]+))?$", s)
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
		if not token_rules.is_empty():
			spec["rules"] = token_rules
		var tparams := {"spec": spec, "count": x_count if x_count != null else _amt(m.get_string(1)), "tapped": m.get_string(2) != ""}
		if token_for != "":
			tparams["for"] = token_for
		_effects.append({"kind": "CREATE_TOKEN", "params": tparams})
		return true

	# Counters.
	m = _match("^(?:you )?put (a|an|one|two|three|four|five|\\d+|x) ([+-]1/[+-]1|[a-z]+) counters? on (.+)$", s)
	if m != null:
		return _counters(_amt(m.get_string(1)), m.get_string(3), m.get_string(2).to_lower())

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
	m = _match("^((?:another |up to one )?target .+?) gets ([+-]\\d+)/([+-]\\d+)(?: and gains ([a-z ,]+))? until end of turn$", s)
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

	# Copies: "Create a token that's a copy of ~." / "...of target creature you control." / "Create two tapped tokens that are copies of it."
	m = _match("^create (a|an|one|two|three|four|five|x|\\d+) (tapped )?tokens? that(?:'s| are) (?:a )?cop(?:y|ies) of (~|it|that creature|target .+)$", s)
	if m != null:
		var cwho := m.get_string(3).to_lower()
		var cref := "SELF"
		if cwho.begins_with("target"):
			var cts := _target(cwho)
			if cts < 0:
				return false
			cref = "TARGET_%d" % cts
		elif cwho in ["it", "that creature"]:
			cref = "TARGET_%d" % (_targets.size() - 1) if not _targets.is_empty() else ("SELF" if _self_it else "TRIGGER_OBJECT")
		_effects.append({"kind": "CREATE_TOKEN", "params": {"copy_of": cref, "count": _amt(m.get_string(1)), "tapped": m.get_string(2) != ""}})
		return true
	# Damage prevention: "Prevent all combat damage that would be dealt this turn." / "Prevent the next 3 damage that would be
	# dealt to any target this turn." / "Prevent all damage that would be dealt to you this turn."
	m = _match("^prevent (all|the next (\\d+|x)) (combat )?damage that would be dealt(?: to (you|~|it|you and permanents you control|any target|target creature|target player|target creature or player|target opponent))? this turn$", s)
	if m != null:
		var pto := "ANY"
		var pwho := m.get_string(4).to_lower()
		if pwho == "you":
			pto = "YOU"
		elif pwho in ["~", "it"]:
			pto = "SELF"
		elif pwho == "you and permanents you control":
			pto = "YOUR_STUFF"
		elif pwho != "":
			var pslot2 := _target(pwho if pwho.begins_with("target") or pwho == "any target" else "target " + pwho)
			if pslot2 < 0:
				return false
			pto = "TARGET_%d" % pslot2
		var pn: Variant = -1 if m.get_string(1).to_lower() == "all" else _amt(m.get_string(2))
		_effects.append({"kind": "PREVENT", "params": {"to": pto, "combat_only": m.get_string(3) != "", "n": pn}})
		return true
	# Impulse draw: "Until the end of your next turn, you may play those cards." / "You may play that card this turn.":
	# the permission is added to the exile just before it.
	m = _match("^(?:until (?:the )?end of (your next turn|turn), )?you may play (?:that card|those cards|it|them)(?: this turn)?$", s)
	if m != null:
		for k in range(_effects.size() - 1, -1, -1):
			if str((_effects[k] as Dictionary).get("kind", "")) == "EXILE_TOP":
				((_effects[k] as Dictionary)["params"] as Dictionary)["may_play"] = "NEXT_TURN" if m.get_string(1).to_lower() == "your next turn" else "END_OF_TURN"
				return true
		return false
	# "Exile the top card of your library." (remembered as exiled with this permanent)
	m = _match("^exile the top (?:card|(two|three|four|five|\\d+) cards) of your library$", s)
	if m != null:
		_effects.append({"kind": "EXILE_TOP", "params": {"n": _num(m.get_string(1)) if m.get_string(1) != "" else 1, "link": true}})
		return true

	# A group gets a boost until end of turn: "Creatures your opponents control get -2/-2 until end of turn."
	m = _match("^((?:other |nontoken |attacking |blocking )*(?:[a-z]+ )*creatures?(?: you control| your opponents control| an opponent controls)?|creatures [a-z ]+? control) get ([+-]\\d+)/([+-]\\d+)(?: and gain ([a-z ,]+))? until end of turn$", s)
	if m != null and not m.get_string(1).to_lower().begins_with("target"):
		var grp := m.get_string(1).to_lower()
		var other_only := grp.begins_with("other ")
		var gq := _event_subject(grp.trim_prefix("other "), false)
		var gk: Array = []
		if m.get_string(4) != "":
			gk = _keywords(m.get_string(4))
			if gk.is_empty():
				return false
		if not gq.is_empty():
			if other_only:
				gq["other"] = true
			_effects.append({"kind": "PUMP", "params": {"each": gq, "power": int(m.get_string(2)), "toughness": int(m.get_string(3)), "keywords": gk, "duration": "END_OF_TURN"}})
			return true
	# Control: "Gain control of target creature until end of turn."
	m = _match("^gain control of (target .+?)( until end of turn)?$", s)
	if m != null:
		var gcs := _target(m.get_string(1))
		if gcs < 0:
			return false
		_effects.append({"kind": "GAIN_CONTROL", "params": {"target": gcs, "duration": "END_OF_TURN" if m.get_string(2) != "" else ""}})
		return true
	# Swords to Plowshares: "Its controller gains life equal to its power." / Beast Within-style leftovers.
	m = _match("^its controller gains life equal to its power$", s)
	if m != null and not _targets.is_empty():
		_effects.append({"kind": "GAIN_LIFE", "params": {"n": {"expr": "TARGET_POWER", "target": _targets.size() - 1}, "who": "TARGET_CONTROLLER"}})
		return true
	if _match("^(?:it|that creature) can't be regenerated$", s) != null:
		return true
	# Brainstorm / Ponder: "Draw three cards, then put two cards from your hand on top of your library in any order."
	m = _match("^(?:then )?put (a|one|two|three|\\d+) cards? from your hand on top of your library(?: in any order)?$", s)
	if m != null:
		_effects.append({"kind": "PUT_BACK", "params": {"n": _num(m.get_string(1))}})
		return true
	if _match("^shuffle your library$", s) != null:
		_effects.append({"kind": "SHUFFLE", "params": {}})
		return true
	# "Untap it." / "It gains haste until end of turn." / "That creature gets +2/+0 until end of turn.": the thing just chosen
	# (or made), else the permanent itself.
	m = _match("^untap (?:it|that creature|that permanent)$", s)
	if m != null and not _targets.is_empty():
		_effects.append({"kind": "UNTAP", "params": {"target": _targets.size() - 1}})
		return true
	m = _match("^(?:it|that creature) gains ([a-z ,]+) until end of turn$", s)
	if m != null and not _targets.is_empty():
		var itk := _keywords(m.get_string(1))
		if itk.is_empty():
			return false
		_effects.append({"kind": "PUMP", "params": {"target": _targets.size() - 1, "keywords": itk, "duration": "END_OF_TURN"}})
		return true
	m = _match("^(?:it|that creature) gets ([+-]\\d+)/([+-]\\d+) until end of turn$", s)
	if m != null and not _targets.is_empty():
		_effects.append({"kind": "PUMP", "params": {"target": _targets.size() - 1, "power": int(m.get_string(1)), "toughness": int(m.get_string(2)), "duration": "END_OF_TURN"}})
		return true
	# Delayed: "At the beginning of the next end step, sacrifice it." / "Exile it at the beginning of the next end step."
	m = _match("^at the beginning of (the|your) next (end step|upkeep), (exile|sacrifice|destroy|return) (it|~|that creature|that token|that permanent)(?: to its owner's hand)?$", s)
	var dm_step := ""
	var dm_whose := ""
	var dm_verb := ""
	var dm_who := ""
	var dm_hand := false
	if m != null:
		dm_whose = "YOURS" if m.get_string(1).to_lower() == "your" else "ANY"
		dm_step = m.get_string(2).to_lower()
		dm_verb = m.get_string(3).to_lower()
		dm_who = m.get_string(4).to_lower()
		dm_hand = s.to_lower().ends_with("to its owner's hand")
	else:
		m = _match("^(?:you )?(exile|sacrifice|destroy) (it|~|that creature|that token|that permanent) at the beginning of (the|your) next (end step|upkeep)$", s)
		if m != null:
			dm_verb = m.get_string(1).to_lower()
			dm_who = m.get_string(2).to_lower()
			dm_whose = "YOURS" if m.get_string(3).to_lower() == "your" else "ANY"
			dm_step = m.get_string(4).to_lower()
	if dm_verb != "" and (dm_verb != "return" or dm_hand):
		var dref := "SELF"
		if dm_who != "~":
			var made := false
			for prior in _effects:
				if str((prior as Dictionary).get("kind", "")) == "CREATE_TOKEN":
					made = true
			if made:
				dref = "LAST_CREATED"
			elif not _targets.is_empty():
				dref = "TARGET_%d" % (_targets.size() - 1)
		_effects.append({"kind": "DELAY", "params": {"step": "UPKEEP" if dm_step == "upkeep" else "END", "whose": dm_whose,
			"action": {"exile": "EXILE", "sacrifice": "SACRIFICE", "destroy": "DESTROY", "return": "RETURN_HAND"}[dm_verb], "ref": dref}})
		return true

	# "You sacrifice a creature" / "sacrifice another artifact or creature" / "sacrifice two Goblins".
	m = _match("^you sacrifice (a|an|another|two|three|\\d+) ([a-z' ]+?)(?: of your choice)?$", s)
	if m != null:
		var sq := _group_query(m.get_string(2))
		if sq.is_empty():
			return false
		if m.get_string(1).to_lower() == "another":
			sq["other"] = true
		_effects.append({"kind": "SACRIFICE", "params": {"n": _num(m.get_string(1)), "who": "CONTROLLER", "query": sq}})
		return true

	# Tap.
	m = _match("^tap (target .+)$", s)
	if m != null:
		var ts := _target(m.get_string(1))
		if ts < 0:
			return false
		_effects.append({"kind": "TAP", "params": {"target": ts}})
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
	# Any other card type / subtype / mana value: "search your library for an Equipment card with mana value 3 or less ...".
	m = _match("^search your library for (?:(a|an|one|two|three)|up to (one|two|three)) (.+?) cards?(?:, reveal (?:it|them|those cards))?,? (?:and )?put (?:it|them|that card|those cards) (onto the battlefield tapped|onto the battlefield|into your hand)(?:, then shuffle)?$", s)
	if m != null:
		var sf: Variant = _card_filter(m.get_string(3))
		if sf == null:
			return false
		var sfilt: Dictionary = sf
		var cnt := _num(m.get_string(1)) if m.get_string(1) != "" else _num(m.get_string(2))
		var sdest := m.get_string(4).to_lower()
		_effects.append({"kind": "SEARCH_LIBRARY", "params": {"filter": sfilt, "n": cnt,
			"to": "HAND" if sdest == "into your hand" else "BATTLEFIELD", "tapped": sdest.ends_with("tapped")}})
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

	# "Counter target creature spell." / "Counter target noncreature spell." / "Counter target instant or sorcery spell."
	m = _match("^counter target ((?:non)?(?:creature|artifact|enchantment|planeswalker|instant|sorcery|land)(?: or (?:non)?(?:creature|artifact|enchantment|planeswalker|instant|sorcery|land))*) spell$", s)
	if m != null:
		var sq := {}
		var kinds: Array = []
		for part in m.get_string(1).to_lower().split(" or "):
			var pw0 := str(part)
			if pw0.begins_with("non"):
				sq["not_type"] = pw0.substr(3)
			else:
				kinds.append(pw0)
		if kinds.size() == 1:
			sq["type"] = kinds[0]
		elif kinds.size() > 1:
			sq["type_any"] = kinds
		var qs := _add_target("SPELL_ON_STACK", sq)
		if qs < 0:
			return false
		_effects.append({"kind": "COUNTER_SPELL", "params": {"target": qs}})
		return true

	# "Counter target spell unless its controller pays {1}." (Mana Leak, Force Spike ...)
	m = _match("^counter target (?:([a-z]+(?: or [a-z]+)*) )?spell unless its controller pays (\\{[^.]+)$", s)
	if m != null:
		var uq := {}
		if m.get_string(1) != "":
			var ukinds: Array = []
			for part in m.get_string(1).to_lower().split(" or "):
				var up := str(part)
				if up.begins_with("non"):
					uq["not_type"] = up.substr(3)
				else:
					ukinds.append(up)
			if ukinds.size() == 1:
				uq["type"] = ukinds[0]
			elif ukinds.size() > 1:
				uq["type_any"] = ukinds
		var us := _add_target("SPELL_ON_STACK", uq)
		if us < 0:
			return false
		_effects.append({"kind": "COUNTER_UNLESS_PAY", "params": {"target": us, "cost": m.get_string(2).to_upper()}})
		return true
	# "Sacrifice ~ unless you pay {U}." (an upkeep cost)
	m = _match("^(?:you )?sacrifice ~ unless you pay (\\{[^.]+)$", s)
	if m != null:
		_pay_links += 1
		var plink := "paid_%d" % _pay_links
		_effects.append({"kind": "PAY_OPTIONAL", "params": {"cost": m.get_string(1).to_upper(), "link": plink}})
		_effects.append({"kind": "SACRIFICE", "params": {"self": true, "if_not_link": plink}})
		return true
	# Bite: "It deals damage equal to its power to target creature you don't control." after a creature was chosen.
	m = _match("^(?:it|that creature) deals damage equal to its power to (target .+)$", s)
	if m != null and not _targets.is_empty():
		var bite_from := _targets.size() - 1
		var bite_to := _target(m.get_string(1))
		if bite_to < 0:
			return false
		_effects.append({"kind": "FIGHT", "params": {"a": bite_from, "b": bite_to, "one_sided": true}})
		return true
	m = _match("^return ~ from your graveyard to (?:your|its owner's) hand$", s)
	if m != null:
		_effects.append({"kind": "RETURN_SELF_HAND", "params": {}})
		return true
	# Target player: draws, discards, mills, loses or gains life.
	m = _match("^target (player|opponent) (draws|discards|mills) (a|an|one|two|three|four|five|\\d+) cards?$", s)
	if m != null:
		var tp := _target("target " + m.get_string(1).to_lower())
		if tp < 0:
			return false
		var cnt := _num(m.get_string(3))
		match m.get_string(2).to_lower():
			"draws":
				_effects.append({"kind": "DRAW", "params": {"n": cnt, "who": "TARGET_%d" % tp}})
			"discards":
				_effects.append({"kind": "DISCARD", "params": {"n": cnt, "who": "TARGET_%d" % tp}})
			_:
				_effects.append({"kind": "MILL", "params": {"n": cnt, "who": "TARGET_%d" % tp}})
		return true

	# "Counter target blue spell." / "Counter target red or green spell with mana value 3 or less." / "Counter target spell with mana value 4."
	m = _match("^counter target ((?:white|blue|black|red|green)(?: or (?:white|blue|black|red|green))*) ?spell(?: with mana value (\\d+)( or less| or greater)?)?$", s)
	if m == null:
		m = _match("^counter target () ?spell with mana value (\\d+)( or less| or greater)?$", s)
	if m != null:
		var cq := {}
		var colors_c: Array = []
		for cw in m.get_string(1).to_lower().split(" or ", false):
			if COLOR_LETTERS.has(str(cw).strip_edges()):
				colors_c.append({"color": COLOR_LETTERS[str(cw).strip_edges()]})
		if colors_c.size() == 1:
			cq["color"] = (colors_c[0] as Dictionary)["color"]
		elif colors_c.size() > 1:
			cq["any"] = colors_c
		if m.get_string(2) != "":
			cq["mv_min" if m.get_string(3) == " or greater" else ("mv_max" if m.get_string(3) != "" else "mv")] = int(m.get_string(2))
		var cs2 := _add_target("SPELL_ON_STACK", cq)
		if cs2 < 0:
			return false
		_effects.append({"kind": "COUNTER_SPELL", "params": {"target": cs2}})
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

	if _match("^choose a color$", s) != null:
		_effects.append({"kind": "CHOOSE_COLOR", "params": {}})
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


## An amount word: a number, or X (the X paid for the spell / ability, or what a "where X is ..." clause defined).
func _amt(word: String) -> Variant:
	if word.to_lower() == "x":
		return _x_override if _x_override != null else {"expr": "X"}
	return _num(word)


## "the number of creatures you control" / "card in your graveyard" / "basic land types among lands you control" as a
## counting expression, or null when it isn't understood.
func _count_expr(phrase: String) -> Variant:
	var p := phrase.strip_edges().to_lower()
	if p == "basic land types among lands you control":
		return {"expr": "DOMAIN"}
	var any_controller := false
	if p.ends_with(" on the battlefield"):
		p = p.trim_suffix(" on the battlefield")
		any_controller = true
	var zone := ""
	for z in [[" in your graveyard", "GRAVEYARD"], [" in your hand", "HAND"], [" in exile", "EXILE"]]:
		if p.ends_with(str(z[0])):
			p = p.trim_suffix(str(z[0]))
			zone = str(z[1])
	var words: Array = []
	var other := false
	for part in p.split(" ", false):
		var word := str(part)
		if word == "other":
			other = true
			continue
		words.append(_singular_type(word).to_lower() if word.ends_with("s") and not word.ends_with("ss") and not word in ["controls", "its"] else word)
	var q: Dictionary
	if zone != "":
		## "cards in your graveyard" / "creature cards in your graveyard"
		var kinds: Array = []
		for w in words:
			if str(w) != "card":
				kinds.append(str(w))
		q = {"zone": zone}
		if kinds.size() == 1 and kinds[0] in BASE_TYPES:
			q["type"] = kinds[0]
		elif not kinds.is_empty():
			return null
	else:
		q = _general_query("target " + " ".join(PackedStringArray(words)))
		if q.is_empty():
			return null
		if not q.has("controller") and not p.contains("opponent") and not any_controller:
			return null
	if other:
		q["other"] = true
	return {"query": q}


func _damage(n: Variant, rest: String) -> bool:
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
	if r == "each player":
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": n, "who": "EACH_PLAYER"}})
		return true
	if r == "each creature and each player":
		_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": n, "query": {"type": "creature"}}})
		_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": n, "who": "EACH_PLAYER"}})
		return true
	var em := _match("^each creature(?: (with|without) ([a-z ]+?))?( you don't control| you control)?$", r)
	if em != null:
		var eq := {"type": "creature"}
		if em.get_string(1) != "":
			if not em.get_string(2) in KEYWORDS:
				return false
			eq["keyword" if em.get_string(1) == "with" else "not_keyword"] = _cap(em.get_string(2)) if not " " in em.get_string(2) else em.get_string(2).substr(0, 1).to_upper() + em.get_string(2).substr(1)
		if em.get_string(3) == " you control":
			eq["controller"] = "SOURCE_CONTROLLER"
		elif em.get_string(3) != "":
			eq["controller"] = "OPPONENT"
		_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": n, "query": eq}})
		return true
	## "each nonartifact creature and each player", "each creature you don't control": any adjectives, optional players.
	var eg := _match("^each ((?:[a-z-]+ )*creature)(?: (you control|your opponents control|an opponent controls|you don't control))?( and each player)?$", r)
	if eg != null:
		var egq := _event_subject(eg.get_string(1) + (" " + eg.get_string(2) if eg.get_string(2) != "" else ""), false)
		if not egq.is_empty():
			if eg.get_string(2) == "you don't control":
				egq["controller"] = "OPPONENT"
			_effects.append({"kind": "DEAL_DAMAGE_EACH", "params": {"n": n, "query": egq}})
			if eg.get_string(3) != "":
				_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": n, "who": "EACH_PLAYER"}})
			return true
	var slot := _target(rest)
	if slot < 0:
		return false
	_effects.append({"kind": "DEAL_DAMAGE", "params": {"n": n, "target": slot}})
	return true


func _counters(n: Variant, where: String, kind: String = "+1/+1") -> bool:
	var w := where.to_lower().strip_edges()
	if w == "~" or w == "it":
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": kind, "n": n, "self": true}})
		return true
	## "each other creature you control", "each green creature that entered this turn" ...: a group, read as a query.
	if w.begins_with("each "):
		var words: Array = []
		var other := false
		for part in w.substr(5).split(" ", false):
			var word := str(part)
			if word == "other":
				other = true
				continue
			words.append(_singular_type(word).to_lower() if word.ends_with("s") and not word.ends_with("ss") and not word in ["controls"] else word)
		var gq := _general_query("target " + " ".join(PackedStringArray(words)))
		if gq.is_empty():
			return false
		if other:
			gq["other"] = true
		_effects.append({"kind": "PUT_COUNTER", "params": {"name": kind, "n": n, "each": gq}})
		return true
	var slot := _target(where)
	if slot < 0:
		return false
	_effects.append({"kind": "PUT_COUNTER", "params": {"name": kind, "n": n, "target": slot}})
	return true


## "...a Plains, Island, Swamp, or Mountain card" / "a basic land card" / "up to two basic land cards".
func _search(m: RegExMatch) -> bool:
	var count := _num(m.get_string(1)) if m.get_string(1) != "" else _num(m.get_string(2))
	var what := m.get_string(3).to_lower().strip_edges()
	var basic_only := what.begins_with("basic ") and what != "basic land"
	if basic_only:
		what = what.trim_prefix("basic ")
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
		if basic_only:
			filt["basic_land"] = true
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
	elif low == "target opponent or planeswalker":
		idx = _add_target("ANY_TARGET", {"opponent": true, "pw_only": true})
	elif low == "target player or planeswalker":
		idx = _add_target("ANY_TARGET", {"pw_only": true})
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
			var gq := _general_query(s)
			if gq.is_empty():
				return -1
			if other:
				gq["other"] = true
			idx = _add_target("PERMANENT", gq)
			if idx >= 0 and optional:
				_targets[idx]["optional"] = true
			return idx
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


## A condition phrase ("you control three or more artifacts", "there are seven or more cards in your graveyard",
## "it's your turn", "you have no cards in hand", "a creature died this turn" ...) as a LayerManager.condition_met
## dictionary. {} when any of it is not understood.
func _condition(text: String) -> Dictionary:
	var t := text.strip_edges().trim_suffix(".").to_lower().replace("you've ", "you ")
	var m: RegExMatch
	m = _match("^it(?:'s| is) (not )?your turn$", t)
	if m != null:
		return {"my_turn": m.get_string(1) == ""}
	if t == "it isn't your turn":
		return {"my_turn": false}
	m = _match("^the (?:discarded|sacrificed|exiled) (?:card|[a-z]+)(?: card)? (was|wasn't) an? ([a-z]+)(?: card)?$", t)
	if m != null:
		return {"paid_has" if m.get_string(1) == "was" else "paid_lacks": _cap(m.get_string(2))}
	if _match("^you(?:'re| are) the monarch$", t) != null:
		return {"monarch": true}
	if _match("^you attacked(?: with a creature)? this turn$", t) != null:
		return {"attacked": true}
	if _match("^a creature died this turn$", t) != null:
		return {"creature_died": true}
	if _match("^a permanent you controlled left the battlefield this turn$", t) != null:
		return {"permanent_left": true}
	if _match("^you gained life this turn$", t) != null:
		return {"gained_life": true}
	if _match("^an opponent lost life this turn$", t) != null:
		return {"opp_lost_life": true}
	if _match("^an opponent has more life than you$", t) != null:
		return {"opp_more_life": true}
	if _match("^you control your commander$", t) != null:
		return {"controls_commander": true}
	if _match("^you control the artifact with the greatest mana value or tied for the greatest mana value$", t) != null:
		return {"greatest_artifact": true}
	if _match("^none of those creatures attacked you$", t) != null:
		return {"no_attacker_at_me": true}
	m = _match("^you have at least (\\w+) life more than your starting life total$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"life_over_start": _num(m.get_string(1))}
	m = _match("^an opponent controls more (creatures|lands) than you$", t)
	if m != null:
		return {"opp_more_creatures" if m.get_string(1) == "creatures" else "opp_more_lands": true}
	m = _match("^you gained (\\w+) or more life this turn$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"gained_life_min": _num(m.get_string(1))}
	if _match("^you have no cards in (?:your )?hand$", t) != null:
		return {"hand_max": 0}
	m = _match("^you have (\\w+) or (more|fewer) cards in (?:your )?hand$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"hand_min" if m.get_string(2) == "more" else "hand_max": _num(m.get_string(1))}
	m = _match("^(?:you have (\\w+) or (more|less|fewer) life|your life total is (\\w+) or (less|more|greater|lower|higher))$", t)
	if m != null:
		var n := _num(m.get_string(1) if m.get_string(1) != "" else m.get_string(3))
		var dir := m.get_string(2) if m.get_string(2) != "" else m.get_string(4)
		if n > 0:
			return {"life_min": n} if dir in ["more", "greater", "higher"] else {"life_max": n}
	m = _match("^(?:there are|you have) (\\w+) or more cards in your graveyard$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"controls": {"zone": "GRAVEYARD"}, "min": _num(m.get_string(1))}
	m = _match("^(?:there are|you have) (\\w+) or more card types among cards in your graveyard$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"graveyard_types_min": _num(m.get_string(1))}
	m = _match("^(?:there are|you have) (\\w+) or more (instant and/or sorcery|creature|land|artifact|permanent) cards? in your graveyard$", t)
	if m != null and _num(m.get_string(1)) > 0:
		var gq := {"zone": "GRAVEYARD"}
		match m.get_string(2):
			"instant and/or sorcery":
				gq["type_any"] = ["instant", "sorcery"]
			"permanent":
				gq["type_any"] = ["artifact", "battle", "creature", "enchantment", "land", "planeswalker"]
			_:
				gq["type"] = m.get_string(2)
		return {"controls": gq, "min": _num(m.get_string(1))}
	m = _match("^creatures you control have total power (\\w+) or greater$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"power_total_min": _num(m.get_string(1))}
	m = _match("^you control a creature with power (\\w+) or greater$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"power_any_min": _num(m.get_string(1))}
	m = _match("^you control (\\w+) or more creatures with different powers$", t)
	if m != null and _num(m.get_string(1)) > 0:
		return {"distinct_powers_min": _num(m.get_string(1))}
	m = _match("^you (?:control|don't control) (.+)$", t)
	if m != null:
		var negative := t.begins_with("you don't control")
		var noun := m.get_string(1)
		var need := 1
		var nm := _match("^(?:(a|an|another)|(no)|(\\w+) or more|at least (\\w+)|any) (.+)$", noun)
		if nm == null:
			return {}
		var rest := nm.get_string(5)
		if nm.get_string(3) != "" or nm.get_string(4) != "":
			need = _num(nm.get_string(3) if nm.get_string(3) != "" else nm.get_string(4))
			if need <= 0:
				return {}
		var other := nm.get_string(1) == "another" or rest.begins_with("other ")
		rest = rest.trim_prefix("other ")
		var words: Array = []
		for w in rest.split(" ", false):
			var word := str(w)
			words.append(_singular_type(word).to_lower() if word.ends_with("s") and not word.ends_with("ss") else word)
		var q := _general_query("target " + " ".join(PackedStringArray(words)))
		if q.is_empty():
			return {}
		q["controller"] = "SOURCE_CONTROLLER"
		if other:
			q["other"] = true
		if negative or nm.get_string(2) != "":
			return {"controls": q, "min": 0, "max": 0}
		return {"controls": q, "min": need}
	return {}


## Tags every effect added since `from` so it only happens while `cond` holds.
func _gate_effects(from: int, cond: Dictionary) -> void:
	for i in range(from, _effects.size()):
		((_effects[i] as Dictionary)["params"] as Dictionary)["if_cond"] = cond


## "creature or artifact", "Goblins", "nonland permanent": the permanents a sacrifice / each-style effect means, as a
## query without a controller (the effect says whose). {} when not understood.
func _group_query(phrase: String) -> Dictionary:
	var words: Array = []
	for part in phrase.to_lower().split(" ", false):
		var word := str(part)
		words.append(_singular_type(word).to_lower() if word.ends_with("s") and not word.ends_with("ss") else word)
	var q := _general_query("target " + " ".join(PackedStringArray(words)))
	q.erase("controller")
	return q


const BASE_TYPES :=["creature", "artifact", "enchantment", "land", "planeswalker", "battle"]


## "target nonblack creature with flying an opponent controls" -> a permanent query, composed from adjectives, nouns
## ("artifact or enchantment"), a controller phrase and "with <keyword>" / "with mana value N or less". {} if any word
## is not understood (so a half-read target never slips through).
func _general_query(phrase: String) -> Dictionary:
	var low := phrase.strip_edges().to_lower()
	if not low.begins_with("target "):
		return {}
	low = low.substr(7)
	var q := {}
	var mv := _match("^(.*?) with mana value (\\d+)( or less| or greater)?(.*)$", low)
	if mv != null:
		q["mv_min" if mv.get_string(3) == " or greater" else ("mv_max" if mv.get_string(3) != "" else "mv")] = int(mv.get_string(2))
		low = (mv.get_string(1) + mv.get_string(4)).strip_edges()
	var pw := _match("^(.*?) with (power|toughness) (\\d+) or (less|greater)(.*)$", low)
	if pw != null:
		q["%s_%s" % [pw.get_string(2), "max" if pw.get_string(4) == "less" else "min"]] = int(pw.get_string(3))
		low = (pw.get_string(1) + pw.get_string(5)).strip_edges()
	var kw := _match("^(.*?) with ([a-z ]+?)((?: you control| you don't control| an opponent controls| that player controls)?)$", low)
	if kw != null:
		var kword := kw.get_string(2)
		if not kword in KEYWORDS:
			return {}
		q["keyword"] = kword.substr(0, 1).to_upper() + kword.substr(1)
		low = (kw.get_string(1) + kw.get_string(3)).strip_edges()
	for suffix in [" you control", " you don't control", " an opponent controls", " that player controls", " they control"]:
		if low.ends_with(suffix):
			q["controller"] = "SOURCE_CONTROLLER" if suffix == " you control" else "OPPONENT"
			low = low.trim_suffix(suffix)
			break
	var types: Array = []
	var not_types: Array = []
	var subs: Array = []
	var sub_run := false
	var words := low.replace(" or ", " | ").split(" ", false)
	var noun_part := false
	for w in words:
		var word := str(w)
		if word == "|":
			noun_part = true
			continue
		if word == "tapped":
			q["tapped"] = true
		elif word == "nontoken":
			q["nontoken"] = true
		elif word == "token":
			q["token"] = true
		elif word == "legendary":
			q["legendary"] = true
		elif word == "nonlegendary":
			q["nonlegendary"] = true
		elif word == "permanent":
			pass
		elif word in BASE_TYPES:
			types.append(word)
		elif word.begins_with("non") and word.substr(3) in BASE_TYPES:
			not_types.append(word.substr(3))
		elif word.begins_with("non") and COLOR_LETTERS.has(word.substr(3)):
			q["not_color"] = COLOR_LETTERS[word.substr(3)]
		elif COLOR_LETTERS.has(word):
			q["color"] = COLOR_LETTERS[word]
		## "non-Dragon" / "nonhuman": every creature except that type.
		elif word.begins_with("non-") and word.length() > 5:
			q["not_subtype"] = _cap(word.substr(4))
		elif word.begins_with("non") and word.length() > 6 and not word in ["nonland", "noncreature", "nontoken", "nonlegendary"]:
			q["not_subtype"] = _cap(word.substr(3))
		elif (not noun_part or sub_run) and word.length() > 2 and not word.contains("'") and not word in ["with", "that", "the", "a", "an", "card", "cards", "spell", "player", "opponent", "ability",
				"graveyard", "library", "hand", "battlefield", "exile", "stack", "life", "counter", "counters", "damage", "mana", "turn", "step", "phase", "name", "type", "types",
				"power", "toughness", "its", "their", "your", "you", "control", "controls", "owner", "controller", "each", "all", "any", "of", "from", "in", "on", "to", "and"]:
			subs.append(_cap(word))
			sub_run = true
			continue
		else:
			return {}
		sub_run = false
	if subs.size() == 1:
		q["subtype"] = subs[0]
	elif subs.size() > 1:
		q["subtype_any"] = subs
	if types.size() == 1:
		q["type"] = types[0]
	elif types.size() > 1:
		q["type_any"] = types
	if not_types.size() == 1:
		q["not_type"] = not_types[0]
	elif not_types.size() > 1:
		q["not_types"] = not_types
	if q.is_empty() and not low.contains("permanent"):
		return {}
	return q


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
		## "protection from white" is a keyword the engine enforces per color.
		if kw.begins_with("protection from ") and COLOR_LETTERS.has(kw.substr(16)):
			out.append("Protection from " + kw.substr(16))
			continue
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
	## Filter lands: "Add {W}{W}, {W}{U}, or {U}{U}" is two mana, each of the two colors.
	var fl := _match("^\\{([WUBRG])\\}\\{\\1\\}, \\{\\1\\}\\{([WUBRG])\\}, or \\{\\2\\}\\{\\2\\}$", t)
	if fl != null:
		var pair := "{%s|%s}" % [fl.get_string(1), fl.get_string(2)]
		return pair + pair
	if low == "two mana in any combination of colors":
		return "{W|U|B|R|G}{W|U|B|R|G}"
	if low == "one mana of any color":
		return "{W|U|B|R|G}"
	if low == "one mana of any color in your commander's color identity":
		return "{CI}"
	if low == "one mana of any color that a land an opponent controls could produce":
		return "{OPP}"
	if low == "one mana of any type that a land you control could produce" or low == "one mana of any color that a land you control could produce":
		return "{OWN}"
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
