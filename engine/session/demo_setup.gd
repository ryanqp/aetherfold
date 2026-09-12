class_name DemoSetup
extends RefCounted

const KRENKO := "Krenko, Mob Boss"
const TALRAND := "Talrand, Sky Summoner"
const KRENKO_OPENER_NAMES: PackedStringArray = [
	"Muxus, Goblin Grandee", "Goblin Ringleader", "Dragon Fodder",
	"Conspicuous Snoop", "Forgotten Cave", "Pashalik Mons", "Mountain",
]
const TALRAND_OPENER_NAMES: PackedStringArray = [
	"Island", "Island", "Island", "Opt", "Ponder", "Unsummon", "Counterspell",
]

var db: CardDatabase
var krenko_list: DeckList
var talrand_list: DeckList
var human_commanders: PackedStringArray = PackedStringArray()
var human_name: String = "Krenko"
var rival_commanders: PackedStringArray = PackedStringArray()
var rival_name: String = "Talrand"


static func memory_db() -> CardDatabase:
	var cat := CatalogSource.Memory.new()
	_fill_catalog(cat)
	var out := CardDatabase.new()
	out.setup(cat)
	return out


static func krenko_vs_talrand(p_db: CardDatabase) -> DemoSetup:
	var d := DemoSetup.new()
	d.db = p_db
	d.krenko_list = _build_krenko()
	d.talrand_list = _build_talrand()
	return d


static func table_demo(seed: int = 1) -> DemoSetup:

	var cat := _scryfall()
	if cat != null and bool(cat.get("loaded")) and cat.has_method("pick_commander_rows"):
		var built := from_scryfall(cat, seed)
		if built != null:
			return built
	var db := memory_db()
	return krenko_vs_talrand(db)


static func _scryfall() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ScryfallCatalog")
	return null


static func from_scryfall(cat: Object, seed: int) -> DemoSetup:
	if cat == null or not cat.has_method("find_by_name") or not cat.has_method("pick_commander_rows"):
		return null
	var mem := CatalogSource.Memory.new()
	_fill_catalog(mem)
	var exclude := {}
	exclude[KRENKO] = true
	exclude[TALRAND] = true
	for n in KRENKO_OPENER_NAMES:
		if n != "Mountain":
			exclude[str(n)] = true
	for n in TALRAND_OPENER_NAMES:
		if n != "Island":
			exclude[str(n)] = true
	exclude["Cancel"] = true
	exclude["Mountain"] = true
	exclude["Island"] = true
	_ingest_scryfall_row(mem, cat, KRENKO)
	_ingest_scryfall_row(mem, cat, TALRAND)
	_ingest_scryfall_row(mem, cat, "Mountain")
	_ingest_scryfall_row(mem, cat, "Island")
	_ingest_scryfall_row(mem, cat, "Cancel")
	for n in KRENKO_OPENER_NAMES:
		_ingest_scryfall_row(mem, cat, str(n))
	for n in TALRAND_OPENER_NAMES:
		_ingest_scryfall_row(mem, cat, str(n))
	var k_core := 6
	var t_core := 5
	var k_need := 99 - k_core - 20
	var t_need := 99 - t_core - 24
	var k_rows: Array = cat.call("pick_commander_rows", ["R"], exclude, k_need, seed)
	for row in k_rows:
		var nm := str(row.get("name", ""))
		if nm != "":
			exclude[nm] = true
			mem.add(row)
	var t_rows: Array = cat.call("pick_commander_rows", ["U"], exclude, t_need, seed + 17)
	for row2 in t_rows:
		mem.add(row2)
	var d := DemoSetup.new()
	d.db = CardDatabase.new()
	d.db.setup(mem)
	d.krenko_list = DeckList.new()
	d.krenko_list.commander_oracle_ids = PackedStringArray(["krenko_mob_boss"])
	_add(d.krenko_list, "Muxus, Goblin Grandee", 1)
	_add(d.krenko_list, "Goblin Ringleader", 1)
	_add(d.krenko_list, "Dragon Fodder", 1)
	_add(d.krenko_list, "Conspicuous Snoop", 1)
	_add(d.krenko_list, "Forgotten Cave", 1)
	_add(d.krenko_list, "Pashalik Mons", 1)
	_add(d.krenko_list, "Mountain", 20)
	for row3 in k_rows:
		var kn := str(row3.get("name", ""))
		if kn != "":
			_add(d.krenko_list, kn, 1)
	var k_total := _list_count(d.krenko_list)
	var vi := 1
	while k_total < 99:
		var vn := "Goblin Volunteer %02d" % vi
		vi += 1
		_add(d.krenko_list, vn, 1)
		k_total += 1
	d.talrand_list = DeckList.new()
	d.talrand_list.commander_oracle_ids = PackedStringArray(["talrand_sky_summoner"])
	_add(d.talrand_list, "Opt", 1)
	_add(d.talrand_list, "Ponder", 1)
	_add(d.talrand_list, "Unsummon", 1)
	_add(d.talrand_list, "Counterspell", 1)
	_add(d.talrand_list, "Cancel", 1)
	_add(d.talrand_list, "Island", 24)
	for row4 in t_rows:
		var tn := str(row4.get("name", ""))
		if tn != "":
			_add(d.talrand_list, tn, 1)
	var t_total := _list_count(d.talrand_list)
	var mi := 1
	while t_total < 99:
		var mn := "Merfolk Volunteer %02d" % mi
		mi += 1
		_add(d.talrand_list, mn, 1)
		t_total += 1
	return d


static func _list_count(list: DeckList) -> int:
	var total := 0
	for entry in list.library:
		total += int(entry.get("count", 1))
	return total


static func _ingest_scryfall_row(mem: CatalogSource, cat: Object, card_name: String) -> void:
	var row: Variant = cat.call("find_by_name", card_name)
	if row is Dictionary and not (row as Dictionary).is_empty():
		mem.add(row)


func apply(engine: RulesEngine) -> void:
	var cmds0 := human_commanders
	if cmds0.is_empty():
		cmds0 = PackedStringArray([KRENKO])
	var cmds1 := rival_commanders
	if cmds1.is_empty():
		cmds1 = PackedStringArray([TALRAND])
	_deal(engine, 0, krenko_list, cmds0)
	_deal(engine, 1, talrand_list, cmds1)
	engine.state.players[0].name = human_name if human_name != "" else "Krenko"
	engine.state.players[1].name = rival_name if rival_name != "" else "Talrand"


static func imported_vs_talrand(deck: NormalizedDeck, rows: Dictionary) -> DemoSetup:
	var mem := CatalogSource.Memory.new()
	_fill_catalog(mem)
	for k in rows.keys():
		var row: Dictionary = rows[k]
		mem.add(row)
	var d := DemoSetup.new()
	d.db = CardDatabase.new()
	d.db.setup(mem)
	d.krenko_list = deck.to_deck_list()
	d.talrand_list = _build_talrand()
	d.human_commanders = deck.commander_names()
	d.human_name = deck.name if deck.name != "" else "You"
	return d


static func legality_errors(
	list: DeckList,
	p_db: CardDatabase,
	commander_name: String,
	allowed_ci: PackedStringArray,
	rules: FormatRules
) -> PackedStringArray:
	var errors := PackedStringArray()
	if list == null or p_db == null:
		errors.append("missing list or database")
		return errors
	var cmd := p_db.definition_for(commander_name)
	if cmd == null:
		errors.append("unknown commander")
		return errors
	var copies: Dictionary = {}
	var total := 1
	for entry in list.library:
		var n := str(entry.get("name", ""))
		var c := int(entry.get("count", 1))
		total += c
		copies[n] = int(copies.get(n, 0)) + c
		var def: CardDefinition = p_db.definition_for(n)
		if def == null:
			errors.append("unknown card: %s" % n)
			continue
		if not def.commander_legal:
			errors.append("not commander legal: %s" % n)
		if not _ci_subset(def.color_identity, allowed_ci):
			errors.append("color identity: %s" % n)
		if rules.singleton and not def.is_basic_land() and int(copies[n]) > 1:
			errors.append("singleton: %s" % n)
	if total != 100:
		errors.append("size %d" % total)
	if list.commander_oracle_ids.is_empty():
		errors.append("no commander id")
	return errors


func _deal(
	engine: RulesEngine,
	player_id: int,
	list: DeckList,
	commander_names: PackedStringArray
) -> void:
	var pool: Array = []
	for entry in list.library:
		var n := str(entry.get("name", ""))
		var c := int(entry.get("count", 1))
		for _i in c:
			pool.append(n)
	for cn in commander_names:
		var cmd_def: CardDefinition = db.definition_for(str(cn))
		engine.state.zones.create(player_id, EngineEnums.ZoneId.COMMAND, {
			definition = cmd_def,
			is_commander = true,
		})
	for ln in pool:
		engine.state.zones.create(player_id, EngineEnums.ZoneId.LIBRARY, {
			definition = db.definition_for(str(ln)),
		})
	engine.shuffle_library(player_id)


static func _build_krenko() -> DeckList:
	var list := DeckList.new()
	list.commander_oracle_ids = PackedStringArray(["krenko_mob_boss"])
	_add(list, "Muxus, Goblin Grandee", 1)
	_add(list, "Goblin Ringleader", 1)
	_add(list, "Dragon Fodder", 1)
	_add(list, "Conspicuous Snoop", 1)
	_add(list, "Forgotten Cave", 1)
	_add(list, "Pashalik Mons", 1)
	_add(list, "Mountain", 20)
	for i in 73:
		_add(list, "Goblin Volunteer %02d" % (i + 1), 1)
	return list


static func _build_talrand() -> DeckList:
	var list := DeckList.new()
	list.commander_oracle_ids = PackedStringArray(["talrand_sky_summoner"])
	_add(list, "Opt", 1)
	_add(list, "Ponder", 1)
	_add(list, "Unsummon", 1)
	_add(list, "Counterspell", 1)
	_add(list, "Cancel", 1)
	_add(list, "Island", 24)
	for i in 70:
		_add(list, "Merfolk Volunteer %02d" % (i + 1), 1)
	return list


static func _add(list: DeckList, n: String, count: int) -> void:
	list.library.append({name = n, count = count})


static func _ci_subset(have: PackedStringArray, allowed: PackedStringArray) -> bool:
	for c in have:
		if not allowed.has(c):
			return false
	return true


static func _fill_catalog(cat: CatalogSource.Memory) -> void:
	_add_land(cat, "Mountain", "Basic Land — Mountain", "({T}: Add {R}.)", ["R"])
	_add_land(cat, "Island", "Basic Land — Island", "({T}: Add {U}.)", ["U"])
	_add_land(cat, "Forgotten Cave", "Land", "Forgotten Cave enters the battlefield tapped.\n{T}: Add {R}.\nCycling {R}.", ["R"])
	_add_creature(cat, "Krenko, Mob Boss", "{2}{R}{R}", 4, "Legendary Creature — Goblin Warrior", "{T}: Create X 1/1 red Goblin creature tokens, where X is the number of Goblins you control.", "3", "3", ["R"])
	_add_creature(cat, "Talrand, Sky Summoner", "{2}{U}{U}", 4, "Legendary Creature — Merfolk Wizard", "Whenever you cast an instant or sorcery spell, create a 2/2 blue Drake creature token with flying.", "2", "2", ["U"])
	_add_creature(cat, "Muxus, Goblin Grandee", "{4}{R}{R}", 6, "Legendary Creature — Goblin", "", "4", "4", ["R"])
	_add_creature(cat, "Goblin Ringleader", "{3}{R}", 4, "Creature — Goblin", "", "2", "2", ["R"])
	_add_creature(cat, "Conspicuous Snoop", "{R}{R}", 2, "Creature — Goblin Rogue", "", "2", "2", ["R"])
	_add_creature(cat, "Pashalik Mons", "{2}{R}", 3, "Legendary Creature — Goblin", "", "2", "2", ["R"])
	_add_spell(cat, "Dragon Fodder", "{1}{R}", 2, "Sorcery", "Create two 1/1 red Goblin creature tokens.", ["R"])
	_add_spell(cat, "Opt", "{U}", 1, "Instant", "Scry 1.\nDraw a card.", ["U"])
	_add_spell(cat, "Ponder", "{U}", 1, "Sorcery", "Look at the top three cards of your library, then put them back in any order. You may shuffle.\nDraw a card.", ["U"])
	_add_spell(cat, "Unsummon", "{U}", 1, "Instant", "Return target creature to its owner's hand.", ["U"])
	_add_spell(cat, "Counterspell", "{U}{U}", 2, "Instant", "Counter target spell.", ["U"])
	_add_spell(cat, "Cancel", "{1}{U}{U}", 3, "Instant", "Counter target spell.", ["U"])
	for i in 73:
		var n := "Goblin Volunteer %02d" % (i + 1)
		_add_creature(cat, n, "{R}", 1, "Creature — Goblin", "", "1", "1", ["R"])
	for i in 70:
		var n2 := "Merfolk Volunteer %02d" % (i + 1)
		_add_creature(cat, n2, "{U}", 1, "Creature — Merfolk", "", "1", "1", ["U"])


static func _add_land(cat: CatalogSource.Memory, n: String, type_line: String, text: String, ci: Array) -> void:
	cat.add({
		name = n,
		oracle_id = n.to_lower(),
		mana_cost = "",
		cmc = 0,
		type_line = type_line,
		oracle_text = text,
		color_identity = ci,
		colors = [],
		commander_legal = true,
	})


static func _add_creature(
	cat: CatalogSource.Memory, n: String, cost: String, cmc: int, type_line: String, text: String,
	power: String, toughness: String, ci: Array
) -> void:
	cat.add({
		name = n,
		oracle_id = n.to_lower().replace(" ", "_").replace(",", ""),
		mana_cost = cost,
		cmc = cmc,
		type_line = type_line,
		oracle_text = text,
		power = power,
		toughness = toughness,
		color_identity = ci,
		colors = ci,
		commander_legal = true,
	})


static func _add_spell(cat: CatalogSource.Memory, n: String, cost: String, cmc: int, type_line: String, text: String, ci: Array) -> void:
	cat.add({
		name = n,
		oracle_id = n.to_lower().replace(" ", "_"),
		mana_cost = cost,
		cmc = cmc,
		type_line = type_line,
		oracle_text = text,
		color_identity = ci,
		colors = ci,
		commander_legal = true,
	})
