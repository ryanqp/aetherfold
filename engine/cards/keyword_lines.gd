class_name KeywordLines
extends RefCounted

## Reads the keyword lines of a card ("Flashback {2}{U}", "Kicker {1}{R}", "Ward {2}", "Cycling {2}") into
## a dictionary the engine looks at when casting, activating from hand, and in combat.
##
## Keys (all lower case): kicker [cost,...], multikicker cost, flashback cost, escape {cost, n}, retrace true,
## madness / miracle / dash / prowl / emerge / morph / megamorph / disguise / ninjutsu cost, suspend {n, cost},
## cycling {cost, type} (type "" is plain cycling, "land", "basic land", "plains", ... for typecycling),
## convoke / delve / extort / flanking / banding / enlist / rebound / phasing true, bloodthirst n,
## echo cost, vanishing n, fading n, cumulative_upkeep {cost, life}, ward {cost, life}, crew n, bushido n, rampage n,
## encore / eternalize / embalm / escalate cost, impending {n, cost}, gift ("card", "treasure", ...),
## demonstrate / improvise / read_ahead true, enchant (what an Aura can enchant: "creature", "creature or vehicle", ...).

const MANA := "((?:\\{[0-9wubrgcxp/]+\\})+)"


static func parse(def: CardDefinition) -> Dictionary:
	var out := {}
	if def == null:
		return out
	for raw in OracleIr.normalize(def).split("\n"):
		var line := OracleIr.strip_ability_word(str(raw).strip_edges())
		var low := line.to_lower().trim_suffix(".").strip_edges()
		if low == "" or low.contains(": "):
			continue
		if _one(low, out):
			continue
		for part in low.split(", "):
			_one(str(part).strip_edges(), out)
	var bands := read_bands(OracleIr.normalize(def))
	if not bands.is_empty():
		out["bands"] = bands
	return out


## Level up (CR 711) and station (CR 721) bands: "LEVEL 2-6" / "STATION 8+" then the band's P/T and abilities.
## Each band: {counter: "level"|"charge", min, max (-1 = no top), power, toughness (-1 = none), keywords, lines}.
static func read_bands(text: String) -> Array:
	var out: Array = []
	var cur: Dictionary = {}
	var re_head := RegEx.create_from_string("^(LEVEL|STATION) (\\d+)(?:-(\\d+)|(\\+))$")
	var re_pt := RegEx.create_from_string("^(\\d+)/(\\d+)$")
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		var m := re_head.search(line)
		if m != null:
			cur = {"counter": "level" if m.get_string(1) == "LEVEL" else "charge", "min": int(m.get_string(2)),
				"max": int(m.get_string(3)) if m.get_string(3) != "" else -1, "power": -1, "toughness": -1,
				"keywords": [], "lines": []}
			out.append(cur)
			continue
		if cur.is_empty() or line == "":
			continue
		var pt := re_pt.search(line)
		if pt != null:
			cur["power"] = int(pt.get_string(1))
			cur["toughness"] = int(pt.get_string(2))
			continue
		var words: Array = []
		for part in line.trim_suffix(".").split(", "):
			var w := str(part).strip_edges()
			if KeywordDb.lookup(w.to_lower()).is_empty():
				words = []
				break
			words.append(w.capitalize() if not w.contains(" ") else w.substr(0, 1).to_upper() + w.substr(1).to_lower())
		if not words.is_empty():
			(cur["keywords"] as Array).append_array(words)
		else:
			(cur["lines"] as Array).append(line)
	return out


## The band a permanent is in now (its level or charge counters), or {}.
static func band_for(def: CardDefinition, counters: Dictionary) -> Dictionary:
	if def == null:
		return {}
	var bands: Array = def.kw().get("bands", [])
	for b in bands:
		var bd: Dictionary = b
		var n := int(counters.get(str(bd.counter), 0))
		if n >= int(bd.min) and (int(bd.max) < 0 or n <= int(bd.max)):
			return bd
	return {}


## True when the text is a keyword line this reader knows (used to skip it when reading spell effects).
static func is_keyword_line(text: String) -> bool:
	var probe := {}
	return _one(text.to_lower().trim_suffix(".").strip_edges(), probe)


## Keywords followed by a mana cost: "Buyback {3}", "Unearth {B}" ... (key -> cost text).
const COSTED := ["buyback", "entwine", "overload", "replicate", "surge", "spectacle", "bestow", "evoke", "blitz",
	"unearth", "scavenge", "foretell", "disturb", "plot", "warp", "sneak", "mayhem", "freerunning", "offspring",
	"squad", "cleave", "web-slinging", "harmonize", "mutate", "transmute", "fortify", "outlast", "level up",
	"reconfigure", "more than meets the eye", "aura swap", "transfigure", "recover", "encore", "eternalize", "embalm",
	"escalate"]
## Keywords followed by a number: "Modular 2", "Saddle 3" ... (key -> n).
const NUMBERED := ["tribute", "amplify", "devour", "modular", "graft", "soulshift", "poisonous", "frenzy", "afflict",
	"absorb", "backup", "mobilize", "firebending", "casualty", "teamwork", "dredge", "ripple", "saddle"]
## Keywords that are just a word.
const FLAGS := ["convoke", "delve", "extort", "flanking", "banding", "enlist", "rebound", "phasing", "demonstrate",
	"improvise", "split second", "storm", "gravestorm", "epic", "conspire", "cipher", "haunt", "unleash", "wither",
	"living metal", "decayed", "exploit", "melee", "mentor", "training", "ingest", "provoke", "undaunted", "soulbond",
	"fuse", "daybound", "nightbound", "compleated", "bargain", "ravenous", "jump-start", "sunburst", "umbra armor",
	"totem armor", "increment", "storied", "paradigm", "station", "start your engines!", "for mirrodin!", "job select",
	"space sculptor", "assist", "spree", "tiered", "mayhem"]


static func _one(low: String, out: Dictionary) -> bool:
	var m: RegExMatch
	for key0 in COSTED:
		m = _m("^" + key0 + "[ —-]+" + MANA + "$", low)
		if m != null:
			out[key0.replace(" ", "_").replace("-", "_")] = _cost(m.get_string(1))
			return true
	for key1 in NUMBERED:
		m = _m("^" + key1 + " (\\d+)$", low)
		if m != null:
			out[key1] = int(m.get_string(1))
			return true
	for key2 in FLAGS:
		if low == key2:
			out[key2.replace(" ", "_").replace("-", "_").replace("!", "")] = true
			return true
	## Awaken N—{cost} (CR 702.113), reinforce N—{cost} (CR 702.77).
	m = _m("^(awaken|reinforce) (\\d+)[ —-]+" + MANA + "$", low)
	if m != null:
		out[m.get_string(1)] = {"n": int(m.get_string(2)), "cost": _cost(m.get_string(3))}
		return true
	## Prototype {cost} — P/T (CR 702.160).
	m = _m("^prototype " + MANA + " [—-] (\\d+)/(\\d+)$", low)
	if m != null:
		out["prototype"] = {"cost": _cost(m.get_string(1)), "p": m.get_string(2), "t": m.get_string(3)}
		return true
	## Splice onto Arcane {cost} (CR 702.47).
	m = _m("^splice onto ([a-z]+) " + MANA + "$", low)
	if m != null:
		out["splice"] = {"onto": m.get_string(1), "cost": _cost(m.get_string(2))}
		return true
	## Craft with <materials> {cost} (CR 702.167).
	m = _m("^craft with (.+?) " + MANA + "$", low)
	if m != null:
		out["craft"] = {"materials": m.get_string(1), "cost": _cost(m.get_string(2))}
		return true
	## Champion a creature / a Faerie (CR 702.72).
	m = _m("^champion an? ([a-z]+)$", low)
	if m != null:
		out["champion"] = m.get_string(1)
		return true
	## "Goblin offering" (CR 702.48).
	m = _m("^([a-z]+) offering$", low)
	if m != null:
		out["offering"] = m.get_string(1)
		return true
	## Landwalk (CR 702.14): islandwalk, nonbasic landwalk, legendary landwalk, snow swampwalk ...
	m = _m("^((?:nonbasic |legendary |snow |desert )?(?:plains|island|swamp|mountain|forest|land|desert))walk$", low)
	if m != null:
		var lw: Array = out.get("landwalk", [])
		lw.append(m.get_string(1))
		out["landwalk"] = lw
		return true
	## "As an additional cost to cast this spell, [you may] waterbend {N}." (CR 701.67): artifacts and creatures you
	## control can be tapped to pay up to N of the generic mana in it.
	m = _m("^as an additional cost to cast (?:this spell|~), (you may )?waterbend \\{(\\d+)\\}$", low)
	if m != null:
		out["waterbend_cost"] = {"n": int(m.get_string(2)), "optional": m.get_string(1) != ""}
		return true
	## "Collect evidence N" as an optional additional cost (CR 701.59c).
	m = _m("^as an additional cost to cast (?:this spell|~), you may collect evidence (\\d+)$", low)
	if m != null:
		out["collect_evidence"] = int(m.get_string(1))
		return true
	## "As an additional cost to cast this spell, sacrifice a creature / discard a card / pay N life." (CR 118.8)
	m = _m("^as an additional cost to cast (?:this spell|~), (sacrifice|discard) (a|an|two) ([a-z ,]+?)(?: or ([a-z]+))?$", low)
	if m != null:
		out["additional_" + m.get_string(1)] = {"n": 2 if m.get_string(2) == "two" else 1, "what": m.get_string(3), "or": m.get_string(4)}
		return true
	m = _m("^as an additional cost to cast (?:this spell|~), pay (\\d+) life$", low)
	if m != null:
		out["additional_life"] = int(m.get_string(1))
		return true
	## Sephara: "You may pay {W} and tap four untapped creatures you control with flying rather than pay ~'s mana cost."
	m = _m("^you may pay " + MANA + " and tap (two|three|four|five|\\d+) untapped creatures you control with ([a-z]+) rather than pay (?:~'s|this spell's) mana cost$", low)
	if m != null:
		out["alt_tap"] = {"cost": _cost(m.get_string(1)), "n": OracleIr._num(m.get_string(2)), "keyword": m.get_string(3)}
		return true
	## Dash, prowl ... handled below; "Companion — <condition>" is deck building only.
	if low.begins_with("companion —") or low.begins_with("companion -"):
		out["companion"] = true
		return true
	if low.begins_with("hidden agenda") or low == "double agenda":
		out["hidden_agenda"] = true
		return true
	m = _m("^kicker " + MANA + "(?: and/or " + MANA + ")?$", low)
	if m != null:
		var list: Array = [_cost(m.get_string(1))]
		if m.get_string(2) != "":
			list.append(_cost(m.get_string(2)))
		out["kicker"] = list
		return true
	## "As an additional cost to cast this spell, reveal a Dinosaur card from your hand or pay {1}." (CR 118.8)
	m = _m("^as an additional cost to cast (?:this spell|~), reveal an? ([a-z]+) card from your hand or pay " + MANA + "$", low)
	if m != null:
		out["reveal_or_pay"] = {"type": m.get_string(1), "cost": _cost(m.get_string(2))}
		return true
	## Graveyard and casting keywords from the precons (CR 702.141, 702.129, 702.128, 702.120).
	for key3 in ["encore", "eternalize", "embalm", "escalate"]:
		m = _m("^" + key3 + "[ —-]+" + MANA + "$", low)
		if m != null:
			out[key3] = _cost(m.get_string(1))
			return true
	## Impending N—{cost} (CR 702.176).
	m = _m("^impending (\\d+)[ —-]+" + MANA + "$", low)
	if m != null:
		out["impending"] = {"n": int(m.get_string(1)), "cost": _cost(m.get_string(2))}
		return true
	## Gift a card / a Treasure / a Food ... (CR 702.174).
	m = _m("^gift an? ([a-z ]+)$", low)
	if m != null:
		out["gift"] = m.get_string(1).strip_edges()
		return true
	## Enchant creature / permanent / creature or Vehicle / creature, land, or planeswalker (CR 702.5, 303.4).
	m = _m("^enchant ([a-z ,]+)$", low)
	if m != null:
		out["enchant"] = m.get_string(1).strip_edges()
		return true
	if low == "read ahead":
		out["read_ahead"] = true
		return true
	m = _m("^multikicker " + MANA + "$", low)
	if m != null:
		out["multikicker"] = _cost(m.get_string(1))
		return true
	m = _m("^flashback[ —-]+" + MANA + "$", low)
	if m != null:
		out["flashback"] = _cost(m.get_string(1))
		return true
	m = _m("^escape[ —-]+" + MANA + ", exile (a|one|two|three|four|five|six|\\d+) other cards? from your graveyard$", low)
	if m != null:
		out["escape"] = {"cost": _cost(m.get_string(1)), "n": OracleIr._num(m.get_string(2))}
		return true
	if low == "retrace":
		out["retrace"] = true
		return true
	for key in ["madness", "miracle", "dash", "prowl", "emerge", "megamorph", "morph", "disguise", "ninjutsu", "echo"]:
		m = _m("^" + key + "[ —-]+" + MANA + "$", low)
		if m != null:
			out[key] = _cost(m.get_string(1))
			return true
	m = _m("^suspend (\\d+)[ —-]+" + MANA + "$", low)
	if m != null:
		out["suspend"] = {"n": int(m.get_string(1)), "cost": _cost(m.get_string(2))}
		return true
	m = _m("^(basic land|[a-z]+)?cycling[ —-]+" + MANA + "$", low)
	if m != null:
		out["cycling"] = {"cost": _cost(m.get_string(2)), "type": m.get_string(1).strip_edges()}
		return true
	m = _m("^(basic landcycling|[a-z]+cycling) " + MANA + "$", low)
	if m != null:
		var typ := m.get_string(1).trim_suffix("cycling").strip_edges()
		out["cycling"] = {"cost": _cost(m.get_string(2)), "type": "basic land" if typ == "basic land" else typ}
		return true
	for key2 in ["bloodthirst", "vanishing", "fading", "crew", "bushido", "rampage"]:
		m = _m("^" + key2 + " (\\d+)$", low)
		if m != null:
			out[key2] = int(m.get_string(1))
			return true
	m = _m("^cumulative upkeep[ —-]+" + MANA + "$", low)
	if m != null:
		out["cumulative_upkeep"] = {"cost": _cost(m.get_string(1)), "life": 0}
		return true
	m = _m("^cumulative upkeep[ —-]+pay (\\d+) life$", low)
	if m != null:
		out["cumulative_upkeep"] = {"cost": "", "life": int(m.get_string(1))}
		return true
	m = _m("^ward[ —-]+" + MANA + "$", low)
	if m != null:
		out["ward"] = {"cost": _cost(m.get_string(1)), "life": 0}
		return true
	m = _m("^ward[ —-]+pay (\\d+) life$", low)
	if m != null:
		out["ward"] = {"cost": "", "life": int(m.get_string(1))}
		return true
	return false


static func _m(pattern: String, s: String) -> RegExMatch:
	return RegEx.create_from_string(pattern).search(s)


## Costs are matched on lower-cased text; mana symbols go back to upper case.
static func _cost(text: String) -> String:
	return text.to_upper()
