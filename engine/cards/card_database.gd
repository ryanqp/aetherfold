class_name CardDatabase
extends RefCounted

const DEFAULT_IR_DIR := "res://engine/cards/ir"

var catalog: CatalogSource
var ir: Dictionary = {}
var tokens: TokenCatalog = TokenCatalog.new()
var loader: IrLoader = IrLoader.new()


func setup(p_catalog: CatalogSource, ir_dir: String = DEFAULT_IR_DIR) -> void:
	catalog = p_catalog if p_catalog != null else CatalogSource.new()
	loader = IrLoader.new()
	ir = {}
	if ir_dir != "" and DirAccess.open(ir_dir) != null:
		ir = loader.load_dir(ir_dir)


func definition_for(name_or_id: String) -> CardDefinition:
	if catalog == null or name_or_id.strip_edges() == "":
		return null
	var row := catalog.find_by_id(name_or_id)
	if row.is_empty():
		row = catalog.find_by_name(name_or_id)
	if row.is_empty():
		return null
	return _from_row(row)


func _from_row(row: Dictionary) -> CardDefinition:
	var d := CardDefinition.from_catalog_row(row)
	var abs: Array = _ir_for(d)
	if not abs.is_empty():
		d.abilities = abs
	else:
		d.abilities = _infer_basic_mana(d)
	return d


func _ir_for(d: CardDefinition) -> Array:
	if d.oracle_id != "" and ir.has(d.oracle_id):
		return ir[d.oracle_id]
	var key := d.name.strip_edges().to_lower()
	if ir.has(key):
		return ir[key]
	return []


func _infer_basic_mana(d: CardDefinition) -> Array:
	if not d.is_basic_land():
		return []
	var produced := ""
	var ability_id := &""
	if d.type_line.contains("Mountain"):
		produced = "{R}"
		ability_id = &"mountain_r"
	elif d.type_line.contains("Island"):
		produced = "{U}"
		ability_id = &"island_u"
	elif d.type_line.contains("Plains"):
		produced = "{W}"
		ability_id = &"plains_w"
	elif d.type_line.contains("Swamp"):
		produced = "{B}"
		ability_id = &"swamp_b"
	elif d.type_line.contains("Forest"):
		produced = "{G}"
		ability_id = &"forest_g"
	else:
		return []
	var ab := Ability.new()
	ab.ability_id = ability_id
	ab.kind = &"MANA"
	ab.text = "{T}: Add %s." % produced
	var tap := AbilityCost.new()
	tap.kind = &"TAP"
	ab.costs.append(tap)
	var fx := AbilityEffect.new()
	fx.kind = &"ADD_MANA"
	fx.params = {mana = produced}
	ab.effects.append(fx)
	return [ab]
