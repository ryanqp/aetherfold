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
	store.purge_test_decks()  ## the Vs. AI lists come from here, not only the gallery
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
	if _is_builtin(player_id) and _is_builtin(rival_id):
		return _builtin_pair(player_id, rival_id)
	return _pair_of_sides(player_id, _side(player_id), rival_id, _side(rival_id))


## An online match: both decks come as records (the guest's was sent over the network, so no ids or paths are
## looked up on this computer). `p_name` / `r_name` become the players' names at the table.
static func vs_pair_recs(p_rec: Dictionary, r_rec: Dictionary, p_name: String = "", r_name: String = "") -> DemoSetup:
	var pid := _id_of_rec(p_rec)
	var rid := _id_of_rec(r_rec)
	var d: DemoSetup
	if _is_builtin(pid) and _is_builtin(rid):
		d = _builtin_pair(pid, rid)
	else:
		d = _pair_of_sides(pid, _side_of_rec(p_rec), rid, _side_of_rec(r_rec))
	if p_name.strip_edges() != "":
		d.human_name = p_name
	if r_name.strip_edges() != "":
		d.rival_name = r_name
	return d


## A starter deck keeps its builtin id; anything else is "custom" and is read from the record itself.
static func _id_of_rec(rec: Dictionary) -> String:
	if bool(rec.get("builtin", false)):
		return str(rec.get("id", BUILTIN_KRENKO))
	return "custom"


static func _pair_of_sides(player_id: String, p: Dictionary, rival_id: String, r: Dictionary) -> DemoSetup:
	var extra: Array = []
	for row in p.get("rows", {}).values():
		extra.append(row)
	for row2 in r.get("rows", {}).values():
		extra.append(row2)
	## The starter decks use the same real-card builds as a starter-vs-starter game, so an imported
	## deck on one side doesn't leave the other with the offline filler cards.
	var seed := int(Time.get_unix_time_from_system())
	if seed == 0:
		seed = 1
	var d := DemoSetup.table_demo(seed, extra)
	d.krenko_list = _list_for(player_id, p, d)
	d.talrand_list = _list_for(rival_id, r, d)
	d.human_commanders = p.get("commanders", PackedStringArray([DemoSetup.KRENKO]))
	d.human_name = str(p.get("name", "You"))
	d.rival_commanders = r.get("commanders", PackedStringArray([DemoSetup.TALRAND]))
	d.rival_name = str(r.get("name", "Rival"))
	return d


## A custom deck's own list, or the real-card starter list for a starter deck.
static func _list_for(choice_id: String, side: Dictionary, base: DemoSetup) -> DeckList:
	if choice_id == BUILTIN_TALRAND:
		return base.talrand_list
	if choice_id == BUILTIN_KRENKO or choice_id == "":
		return base.krenko_list
	return side.get("list")


static func _is_builtin(choice_id: String) -> bool:
	return choice_id == "" or choice_id == BUILTIN_KRENKO or choice_id == BUILTIN_TALRAND


## Starter decks. When the Scryfall catalog is loaded, table_demo fills the
## 99 with real commander-legal cards. The in-memory "Goblin Volunteer"
## names are only the offline pad, and they are still normal cards.
static func _builtin_pair(player_id: String, rival_id: String) -> DemoSetup:
	var seed := int(Time.get_unix_time_from_system())
	if seed == 0:
		seed = 1
	var demo := DemoSetup.table_demo(seed)
	if player_id == BUILTIN_TALRAND:
		var swap: DeckList = demo.krenko_list
		demo.krenko_list = demo.talrand_list
		demo.talrand_list = swap
		demo.human_commanders = PackedStringArray([DemoSetup.TALRAND])
		demo.human_name = "Talrand, Sky Summoner"
		demo.rival_commanders = PackedStringArray([DemoSetup.KRENKO])
		demo.rival_name = "Krenko, Mob Boss"
	else:
		demo.human_commanders = PackedStringArray([DemoSetup.KRENKO])
		demo.human_name = "Krenko, Mob Boss"
		demo.rival_commanders = PackedStringArray([DemoSetup.TALRAND])
		demo.rival_name = "Talrand, Sky Summoner"
	return demo


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
	return _side_of_rec(rec)


## A custom deck read from its record (the commander, the mainboard and the card rows saved with it).
static func _side_of_rec(rec: Dictionary) -> Dictionary:
	if bool(rec.get("builtin", false)):
		return _side(str(rec.get("id", BUILTIN_KRENKO)))
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
