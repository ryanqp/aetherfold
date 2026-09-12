class_name DeckCatalog
extends RefCounted

const BUILTIN_KRENKO := "builtin:krenko"
const BUILTIN_TALRAND := "builtin:talrand"


static func builtins() -> Array:
	return [
		{
			id = BUILTIN_KRENKO,
			name = "Krenko, Mob Boss",
			builtin = true,
			commander = [{name = DemoSetup.KRENKO, quantity = 1}],
			mainboard = [],
			source = "starter",
		},
		{
			id = BUILTIN_TALRAND,
			name = "Talrand, Sky Summoner",
			builtin = true,
			commander = [{name = DemoSetup.TALRAND, quantity = 1}],
			mainboard = [],
			source = "starter",
		},
	]


static func all_choices() -> Array:
	var out: Array = builtins()
	var store := DeckStore.new()
	for rec in store.list_decks():
		var d: Dictionary = rec
		d["id"] = str(d.get("_path", d.get("id", "")))
		d["builtin"] = false
		if str(d.get("name", "")).strip_edges() == "":
			d["name"] = commander_name(d)
		out.append(d)
	return out


static func commander_name(rec: Dictionary) -> String:
	var cmds: Variant = rec.get("commander", [])
	if cmds is Array and not (cmds as Array).is_empty():
		var first = (cmds as Array)[0]
		if first is Dictionary:
			return str(first.get("name", "Untitled"))
	return str(rec.get("name", "Untitled"))


static func commander_row(rec: Dictionary) -> Dictionary:
	var nm := commander_name(rec)
	var cards: Variant = rec.get("cards", {})
	if cards is Dictionary and (cards as Dictionary).has(nm):
		var row: Variant = (cards as Dictionary)[nm]
		if row is Dictionary:
			return row
	var cat := DemoSetup._scryfall()
	if cat != null and cat.has_method("find_by_name"):
		var found: Variant = cat.find_by_name(nm)
		if found is Dictionary:
			return found
	return {name = nm}


static func vs_pair(player_id: String, rival_id: String) -> DemoSetup:
	var p: Dictionary = _side(player_id)
	var r: Dictionary = _side(rival_id)
	var mem := CatalogSource.Memory.new()
	DemoSetup._fill_catalog(mem)
	for row in p.get("rows", {}).values():
		if row is Dictionary:
			mem.add(row)
	for row2 in r.get("rows", {}).values():
		if row2 is Dictionary:
			mem.add(row2)
	var d := DemoSetup.new()
	d.db = CardDatabase.new()
	d.db.setup(mem)
	d.krenko_list = p.get("list")
	d.talrand_list = r.get("list")
	d.human_commanders = p.get("commanders", PackedStringArray([DemoSetup.KRENKO]))
	d.human_name = str(p.get("name", "You"))
	d.rival_commanders = r.get("commanders", PackedStringArray([DemoSetup.TALRAND]))
	d.rival_name = str(r.get("name", "Rival"))
	return d


static func _side(choice_id: String) -> Dictionary:
	if choice_id == BUILTIN_TALRAND:
		return {
			list = DemoSetup._build_talrand(),
			commanders = PackedStringArray([DemoSetup.TALRAND]),
			name = "Talrand, Sky Summoner",
			rows = {},
		}
	if choice_id == BUILTIN_KRENKO or choice_id == "":
		return {
			list = DemoSetup._build_krenko(),
			commanders = PackedStringArray([DemoSetup.KRENKO]),
			name = "Krenko, Mob Boss",
			rows = {},
		}
	var rec: Dictionary = DeckStore.new().load_path(choice_id)
	if rec.is_empty():
		return _side(BUILTIN_KRENKO)
	var deck := NormalizedDeck.from_dict(rec)
	if deck.commanders.is_empty():
		deck.add_commander(commander_name(rec), 1)
	var rows: Dictionary = rec.get("cards", {})
	if not (rows is Dictionary):
		rows = {}
	return {
		list = deck.to_deck_list(),
		commanders = deck.commander_names(),
		name = str(rec.get("name", commander_name(rec))),
		rows = rows,
	}
