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
	if abs.is_empty():
		## No hand-written IR: read what Oracle text says (instants/sorceries, activated abilities,
		## ETBs, mana abilities). Lands also get the mana ability their basic land types give (CR 305.6).
		abs = OracleIr.translate(d)
		if abs.is_empty():
			abs = OracleIr.translate_permanent(d)
		if d.is_land():
			var have := {}
			for a in abs:
				have[(a as Ability).ability_id] = true
			for a in _infer_basic_mana(d):
				if not have.has((a as Ability).ability_id):
					abs.push_front(a)
	if not abs.is_empty():
		d.abilities = abs
	return d


## Oracle lines the engine does not act on yet, for a card without hand-written IR: not a keyword the
## engine enforces, not read into an ability, not "enters tapped". The table lists them in History.
func unread_lines(d: CardDefinition) -> Array:
	var out: Array = []
	if d == null or d.is_basic_land() or not _ir_for(d).is_empty():
		return out
	var text := OracleIr.normalize(d)
	var covered: Array = []
	var etb := EtbRules.parse(d)
	for a in d.abilities:
		if (a as Ability).kind == &"SPELL":
			return out  ## instants and sorceries are read whole or not at all
		covered.append(str((a as Ability).text).strip_edges())
	for raw in text.split("\n"):
		var line := OracleIr.strip_ability_word(str(raw).strip_edges())
		if line == "" or covered.has(line) or _keyword_line(line):
			continue
		var low_line := line.to_lower()
		if d.enters_tapped() and low_line.begins_with("~ enters"):
			continue
		## "enters tapped unless ..." / reveal-or-tapped / shock: handled as it enters (EtbRules).
		if not etb.is_empty() and low_line.contains("enters") and (low_line.contains("tapped") or low_line.contains("reveal") or low_line.contains("pay")):
			continue
		out.append(KeywordDb.describe_unread(line))
	return out


func _keyword_line(line: String) -> bool:
	return KeywordDb.line_is_handled(line)


func _ir_for(d: CardDefinition) -> Array:
	if d.oracle_id != "" and ir.has(d.oracle_id):
		return ir[d.oracle_id]
	var key := d.name.strip_edges().to_lower()
	if ir.has(key):
		return ir[key]
	return []


const BASIC_TYPES := [
	["Plains", "W", "plains_w"], ["Island", "U", "island_u"], ["Swamp", "B", "swamp_b"],
	["Mountain", "R", "mountain_r"], ["Forest", "G", "forest_g"],
]


## CR 305.6: a land with a basic land type has "{T}: Add <that color>". Applies to dual lands too.
func _infer_basic_mana(d: CardDefinition) -> Array:
	var out: Array = []
	if not d.is_land():
		return out
	for t in BASIC_TYPES:
		if not d.type_line.contains(str(t[0])):
			continue
		var produced := "{%s}" % t[1]
		var ab := Ability.new()
		ab.ability_id = StringName(str(t[2]))
		ab.kind = &"MANA"
		ab.text = "{T}: Add %s." % produced
		var tap := AbilityCost.new()
		tap.kind = &"TAP"
		ab.costs.append(tap)
		var fx := AbilityEffect.new()
		fx.kind = &"ADD_MANA"
		fx.params = {mana = produced}
		ab.effects.append(fx)
		out.append(ab)
	return out
