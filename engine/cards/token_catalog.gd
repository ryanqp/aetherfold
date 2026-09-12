class_name TokenCatalog
extends RefCounted

const GOBLIN_1_1_R := "goblin_1_1_r"
const DRAKE_2_2_U_FLYING := "drake_2_2_u_flying"


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
		_:
			return null
