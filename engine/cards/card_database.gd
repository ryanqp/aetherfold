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
	for face in [d.back_face, d.other_half]:
		if face != null:
			face.abilities = _abilities_for(face)
	_build_abilities(d)
	return d


## Hand-written IR, else what the Oracle text says.
func _abilities_for(d: CardDefinition) -> Array:
	var abs: Array = _ir_for(d)
	if abs.is_empty():
		abs = OracleIr.translate(d)
		if abs.is_empty():
			abs = OracleIr.translate_permanent(d)
	return abs


func _build_abilities(d: CardDefinition) -> void:
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
		if (a as Ability).kind == &"SPELL" and (d.is_instant() or d.is_sorcery()):
			return out  ## instants and sorceries are read whole or not at all
		covered.append(str((a as Ability).text).strip_edges())
	for raw in text.split("\n"):
		var line := OracleIr.strip_ability_word(str(raw).strip_edges())
		if line == "" or covered.has(line) or _keyword_line(line):
			continue
		if _handled_elsewhere(d, line, etb):
			continue
		out.append(KeywordDb.describe_unread(line))
	return out


## Lines the engine reads straight from the permanent's text, not through an ability (extra land drops, counter rules,
## riot, "enters tapped unless ...", commander choice ...).
func _handled_elsewhere(d: CardDefinition, line: String, etb: Dictionary) -> bool:
	var low_line := line.to_lower()
	if d.enters_tapped() and low_line.begins_with("~ enters"):
		return true
	if low_line.begins_with("~ enters with") and not low_line.contains(" if ") and not ZoneManager.enters_with_counters(d).is_empty():
		return true
	if low_line == "you may play an additional land on each of your turns." or low_line == "creatures your opponents control enter tapped.":
		return true
	if low_line.ends_with("can be your commander.") or low_line.contains("causes a triggered ability of that creature to trigger"):
		return true
	if low_line.contains("can't be countered") or low_line.contains("have riot") or low_line.contains("prevent all but 1 of that damage") \
			or low_line.contains("triggers an additional time") or low_line.contains("while you're the monarch, add an additional"):
		return true
	## "enters tapped unless ..." / reveal-or-tapped / shock: handled as it enters (EtbRules).
	if not etb.is_empty() and low_line.contains("enters") and (low_line.contains("tapped") or low_line.contains("reveal") or low_line.contains("pay")):
		return true
	return false


## Every line of the card read on its own, so an instant or sorcery with one odd line no longer blames its simple
## lines: [{line, read}]. Lines handled elsewhere or that are keywords count as read; mode bullets are read as part of
## their "Choose ..." line. This is what the coverage tool counts.
func line_status(d: CardDefinition) -> Array:
	var out: Array = []
	if d == null or d.is_basic_land() or not _ir_for(d).is_empty():
		return out
	var etb := EtbRules.parse(d)
	var covered: Array = []
	for a in d.abilities:
		covered.append(str((a as Ability).text).strip_edges())
	var text := OracleIr.normalize(d)
	var is_spell := d.is_instant() or d.is_sorcery()
	var lines: Array = []
	for raw in text.split("\n"):
		lines.append(str(raw).strip_edges())
	for i in lines.size():
		var raw_line: String = lines[i]
		var line := OracleIr.strip_ability_word(raw_line)
		if line == "" or line.begins_with("•") or _keyword_line(line) or _handled_elsewhere(d, line, etb):
			continue
		if covered.has(line) and not is_spell:
			out.append({"line": line, "read": true})
			continue
		var ok := false
		var clean := line.trim_suffix(".")
		if is_spell:
			ok = OracleIr.new()._read_effects(line)
		else:
			ok = not (OracleIr._read_whole_or_by_sentence(d, clean) as Array).is_empty()
		out.append({"line": line, "read": ok})
	return out


func _keyword_line(line: String) -> bool:
	return KeywordDb.line_is_handled(line) or KeywordLines.is_keyword_line(line)


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
