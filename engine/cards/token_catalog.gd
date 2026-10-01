class_name TokenCatalog
extends RefCounted

const GOBLIN_1_1_R := "goblin_1_1_r"
const DRAKE_2_2_U_FLYING := "drake_2_2_u_flying"
const SOLDIER_1_1_W := "soldier_1_1_w"
const TREASURE := "treasure"
const FOOD := "food"
const CLUE := "clue"


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
		_:
			return null


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
	return d


func _abilities(items: Array) -> Array:
	var loader := IrLoader.new()
	return loader.from_dict({"abilities": items})
