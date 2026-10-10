class_name TokenCatalog
extends RefCounted

const GOBLIN_1_1_R := "goblin_1_1_r"
const DRAKE_2_2_U_FLYING := "drake_2_2_u_flying"
const SOLDIER_1_1_W := "soldier_1_1_w"
const TREASURE := "treasure"
const FOOD := "food"
const CLUE := "clue"
const INCUBATOR := "incubator"
const PHYREXIAN_0_0 := "phyrexian_0_0"


func definition_for(token_id: String) -> CardDefinition:
	var d := CardDefinition.new()
	match token_id:
		GOBLIN_1_1_R:
			d.name = "Goblin"
			d.type_line = "Token Creature — Goblin"
			d.oracle_text = ""
			d.power = "1"
			d.toughness = "1"
			d.colors = PackedStringArray(["R"])
			d.color_identity = PackedStringArray(["R"])
			return d
		DRAKE_2_2_U_FLYING:
			d.name = "Drake"
			d.type_line = "Token Creature — Drake"
			d.oracle_text = "Flying"
			d.power = "2"
			d.toughness = "2"
			d.colors = PackedStringArray(["U"])
			d.color_identity = PackedStringArray(["U"])
			d.keywords = PackedStringArray(["Flying"])
			return d
		SOLDIER_1_1_W:
			d.name = "Soldier"
			d.type_line = "Token Creature — Soldier"
			d.oracle_text = ""
			d.power = "1"
			d.toughness = "1"
			d.colors = PackedStringArray(["W"])
			d.color_identity = PackedStringArray(["W"])
			return d
		TREASURE:
			d.name = "Treasure"
			d.type_line = "Token Artifact — Treasure"
			d.oracle_text = "{T}, Sacrifice this artifact: Add one mana of any color."
			d.abilities = _abilities([{
				"ability_id": "treasure_mana",
				"kind": "MANA",
				"costs": [{"kind": "TAP"}, {"kind": "SACRIFICE_SELF"}],
				"targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": "{W|U|B|R|G}"}}],
				"restrictions": [],
				"text": d.oracle_text,
			}])
			return d
		FOOD:
			d.name = "Food"
			d.type_line = "Token Artifact — Food"
			d.oracle_text = "{2}, {T}, Sacrifice this artifact: You gain 3 life."
			d.abilities = _abilities([{
				"ability_id": "food_life",
				"kind": "ACTIVATED",
				"costs": [{"kind": "MANA", "mana": "{2}"}, {"kind": "TAP"}, {"kind": "SACRIFICE_SELF"}],
				"targets": [],
				"effects": [{"kind": "GAIN_LIFE", "params": {"n": 3}}],
				"restrictions": [],
				"text": d.oracle_text,
			}])
			return d
		CLUE:
			d.name = "Clue"
			d.type_line = "Token Artifact — Clue"
			d.oracle_text = "{2}, Sacrifice this artifact: Draw a card."
			d.abilities = _abilities([{
				"ability_id": "clue_draw",
				"kind": "ACTIVATED",
				"costs": [{"kind": "MANA", "mana": "{2}"}, {"kind": "SACRIFICE_SELF"}],
				"targets": [],
				"effects": [{"kind": "DRAW", "params": {"n": 1}}],
				"restrictions": [],
				"text": d.oracle_text,
			}])
			return d
		"blood":
			d.name = "Blood"
			d.type_line = "Token Artifact — Blood"
			d.oracle_text = "{1}, {T}, Discard a card, Sacrifice this artifact: Draw a card."
			d.abilities = _abilities([{
				"ability_id": "blood_draw",
				"kind": "ACTIVATED",
				"costs": [{"kind": "MANA", "mana": "{1}"}, {"kind": "TAP"}, {"kind": "DISCARD"}, {"kind": "SACRIFICE_SELF"}],
				"targets": [],
				"effects": [{"kind": "DRAW", "params": {"n": 1}}],
				"restrictions": [],
				"text": d.oracle_text,
			}])
			return d
		"map":
			d.name = "Map"
			d.type_line = "Token Artifact — Map"
			d.oracle_text = "{1}, {T}, Sacrifice this artifact: Target creature you control explores. Activate only as a sorcery."
			d.abilities = _abilities([{
				"ability_id": "map_explore",
				"kind": "ACTIVATED",
				"costs": [{"kind": "MANA", "mana": "{1}"}, {"kind": "TAP"}, {"kind": "SACRIFICE_SELF"}],
				"targets": [{"id": 0, "kind": "PERMANENT", "count": 1, "query": {"type": "creature", "controller": "SOURCE_CONTROLLER"}}],
				"effects": [{"kind": "EXPLORE", "params": {"target": 0}}],
				"restrictions": ["SORCERY_SPEED"],
				"text": d.oracle_text,
			}])
			return d
		"junk":
			d.name = "Junk"
			d.type_line = "Token Artifact — Junk"
			d.oracle_text = "{T}, Sacrifice this artifact: Exile the top card of your library. You may play it this turn. Activate only as a sorcery."
			d.abilities = _abilities([{
				"ability_id": "junk_play",
				"kind": "ACTIVATED",
				"costs": [{"kind": "TAP"}, {"kind": "SACRIFICE_SELF"}],
				"targets": [],
				"effects": [{"kind": "EXILE_TOP", "params": {"n": 1, "may_play": "END_OF_TURN"}}],
				"restrictions": ["SORCERY_SPEED"],
				"text": d.oracle_text,
			}])
			return d
		INCUBATOR:
			d.name = "Incubator"
			d.type_line = "Token Artifact — Incubator"
			d.oracle_text = "{2}: Transform this artifact."
			d.abilities = _abilities([{
				"ability_id": "incubator_flip",
				"kind": "ACTIVATED",
				"costs": [{"kind": "MANA", "mana": "{2}"}],
				"targets": [],
				"effects": [{"kind": "INCUBATOR_FLIP", "params": {}}],
				"restrictions": [],
				"text": d.oracle_text,
			}])
			return d
		PHYREXIAN_0_0:
			d.name = "Phyrexian"
			d.type_line = "Token Artifact Creature — Phyrexian"
			d.oracle_text = ""
			d.power = "0"
			d.toughness = "0"
			return d
		"powerstone":
			## "{T}: Add {C}. This mana can't be spent to cast a nonartifact spell." (abilities and artifact spells may use it)
			d.name = "Powerstone"
			d.type_line = "Token Artifact — Powerstone"
			d.oracle_text = "{T}: Add {C}. This mana can't be spent to cast a nonartifact spell."
			d.abilities = _abilities([{
				"ability_id": "powerstone_c",
				"kind": "MANA",
				"costs": [{"kind": "TAP"}],
				"targets": [],
				"effects": [{"kind": "ADD_MANA", "params": {"mana": "{C}"}}],
				"restrictions": [{"spend_only": {"query": {"type": "artifact"}, "abilities": true}}],
				"text": d.oracle_text,
			}])
			return d
		_:
			if TEXT_TOKENS.has(token_id):
				var row: Array = TEXT_TOKENS[token_id]
				d.name = str(row[0])
				d.type_line = str(row[1])
				d.oracle_text = str(row[2])
				d.abilities = OracleIr.translate_permanent(d)
				return d
			return null


## Named tokens whose rules are read from their text like any card's (CR 111.10): id -> [name, type line, rules].
const TEXT_TOKENS := {
	"lander": ["Lander", "Token Artifact — Lander", "{2}, {T}, Sacrifice this token: Search your library for a basic land card, put it onto the battlefield tapped, then shuffle."],
	"mutagen": ["Mutagen", "Token Artifact — Mutagen", "{1}, {T}, Sacrifice this token: Put a +1/+1 counter on target creature. Activate only as a sorcery."],
	"gold": ["Gold", "Token Artifact — Gold", "Sacrifice this artifact: Add one mana of any color."],
	"shard": ["Shard", "Token Enchantment — Shard", "{2}, Sacrifice this enchantment: Scry 1, then draw a card."],
}


## A token described by the IR: {name, p, t, colors: ["G"], subtypes: ["Dinosaur"], keywords: ["Trample"],
## artifact: bool}. "Create a 3/3 green Dinosaur creature token with trample."
func from_spec(spec: Dictionary) -> CardDefinition:
	var d := CardDefinition.new()
	var subtypes: Array = spec.get("subtypes", [])
	d.name = str(spec.get("name", " ".join(PackedStringArray(subtypes))))
	var types := "Token Artifact Creature" if bool(spec.get("artifact", false)) else "Token Creature"
	d.type_line = "%s — %s" % [types, " ".join(PackedStringArray(subtypes))] if not subtypes.is_empty() else types
	d.power = str(spec.get("p", "0"))
	d.toughness = str(spec.get("t", "0"))
	for c in spec.get("colors", []):
		d.colors.append(str(c))
		d.color_identity.append(str(c))
	for k in spec.get("keywords", []):
		d.keywords.append(str(k))
	d.oracle_text = ", ".join(d.keywords)
	## Toxic N (CR 702.164) is read from the token's text; "This token can't block." as a line of its own.
	if int(spec.get("toxic", 0)) > 0:
		d.keywords.append("Toxic")
		d.oracle_text = ("%s\nToxic %d" % [d.oracle_text, int(spec.toxic)]).strip_edges()
	if bool(spec.get("cant_block", false)):
		d.oracle_text = (d.oracle_text + "\nThis token can't block.").strip_edges()
	## Quoted rules ("... token with "When this creature dies, ..."): read like any permanent's text.
	var rules: Array = spec.get("rules", [])
	if not rules.is_empty():
		d.oracle_text = (d.oracle_text + "\n" + "\n".join(PackedStringArray(rules))).strip_edges()
		d.abilities = OracleIr.translate_permanent(d)
	return d


func _abilities(items: Array) -> Array:
	var loader := IrLoader.new()
	return loader.from_dict({"abilities": items})
