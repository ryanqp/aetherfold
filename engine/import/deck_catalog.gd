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


## Why a saved deck is not a legal Commander deck, one short line each ([] when it is legal, or a starter deck). Read from the
## validation saved with the deck; "Unresolved" cards count too, because they are left out of the game.
static func problems_of(rec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if bool(rec.get("builtin", false)):
		return out
	var v: Variant = rec.get("validation")
	if not (v is Dictionary):
		return out
	var vd: Dictionary = v
	if not bool(vd.get("ok", true)):
		for e in vd.get("errors", []):
			var line := str(e).split("\n")[0].strip_edges()
			if line != "" and not out.has(line):
				out.append(line)
		if out.is_empty():
			out.append("This deck did not pass the Commander check.")
	var missing := 0
	for w in vd.get("warnings", []):
		if str(w).begins_with("Unresolved:"):
			missing += 1
	if missing > 0:
		out.append("%d card%s could not be found and would be left out." % [missing, "s" if missing != 1 else ""])
	return out


## Whether a deck choice (a builtin id or a saved deck's path) can be played right now: {ok, text}. A deleted or unreadable
## deck is reported instead of quietly turning into Krenko.
static func playable(choice_id: String) -> Dictionary:
	if _is_builtin(choice_id):
		return {ok = true, text = ""}
	var rec: Dictionary = DeckStore.new().load_path(choice_id)
	if rec.is_empty():
		return {ok = false, text = "That deck could not be found or read any more."}
	return {ok = true, text = "", problems = problems_of(rec), name = str(rec.get("name", commander_name(rec)))}


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
	p_rec = _with_catalog_rows(p_rec)
	r_rec = _with_catalog_rows(r_rec)
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


## Cards that this computer's own catalog knows are played as the catalog has them, whatever the record carries. A guest's deck
## arrives with its own card rows; without this they could give a card different text or stats, and because both decks share
## one card database, the same change would reach the host's copies of that card too (AUDIT-015).
static func prefer_catalog_rows(rows: Dictionary, cat: Object = null) -> Dictionary:
	if cat == null:
		cat = DemoSetup._scryfall()
	if cat == null or not cat.has_method("find_by_name"):
		return rows
	var out := rows.duplicate()
	for k in rows.keys():
		var row: Variant = rows[k]
		var known: Variant = cat.find_by_name(str((row as Dictionary).get("name", k)) if row is Dictionary else str(k))
		if known is Dictionary and not (known as Dictionary).is_empty():
			out[k] = known
	return out


static func _with_catalog_rows(rec: Dictionary) -> Dictionary:
	if bool(rec.get("builtin", false)) or not (rec.get("cards", null) is Dictionary):
		return rec
	var copy := rec.duplicate()
	copy["cards"] = prefer_catalog_rows(rec.get("cards", {}))
	return copy


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


## Decks saved before the catalog kept every face hold double-faced, split and adventure cards as bare names, which play as
## blank cards. Those rows are swapped for the catalog's full rows (nothing else in the deck is touched).
static func refresh_rows(rows: Dictionary, cat: Object = null) -> Dictionary:
	if cat == null:
		cat = DemoSetup._scryfall()
	if cat == null or not cat.has_method("find_by_name"):
		return rows
	var out := rows.duplicate()
	for k in rows.keys():
		var row: Variant = rows[k]
		if not (row is Dictionary):
			continue
		var faces: Variant = (row as Dictionary).get("faces", [])
		if faces is Array and not (faces as Array).is_empty() and not ((faces as Array)[0] is Dictionary):
			var fresh: Variant = cat.find_by_name(str((row as Dictionary).get("name", k)))
			if fresh is Dictionary and not (fresh as Dictionary).is_empty():
				out[k] = fresh
	return out


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
	rows = refresh_rows(rows)
	return {
		list = deck.to_deck_list(),
		commanders = deck.commander_names(),
		name = str(rec.get("name", commander_name(rec))),
		rows = rows,
	}
