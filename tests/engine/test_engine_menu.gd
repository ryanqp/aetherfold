@tool
extends McpTestSuite

func suite_name() -> String:
	return "engine_menu"


func test_builtins_listed() -> void:
	var all: Array = DeckCatalog.all_choices()
	assert_true(all.size() >= 2)
	assert_eq(str(all[0].get("id", "")), DeckCatalog.BUILTIN_KRENKO)
	assert_eq(DeckCatalog.commander_name(all[0]), "Krenko, Mob Boss")


func test_vs_pair_krenko_talrand() -> void:
	var demo: DemoSetup = DeckCatalog.vs_pair("builtin:krenko", "builtin:talrand")
	var session := GameSession.new()
	session.start_with_demo(demo, 1)
	assert_eq(session.engine.state.players[0].name, "Krenko, Mob Boss")
	assert_eq(session.engine.state.players[1].name, "Talrand, Sky Summoner")
	assert_eq(session.engine.hand_size(0), 7)
	assert_eq(session.engine.library_size(0), 92)


func test_vs_pair_swapped() -> void:
	var demo: DemoSetup = DeckCatalog.vs_pair("builtin:talrand", "builtin:krenko")
	var session := GameSession.new()
	session.start_with_demo(demo, 1)
	assert_eq(session.engine.state.players[0].name, "Talrand, Sky Summoner")
	assert_eq(session.engine.state.players[1].name, "Krenko, Mob Boss")


func test_room_code_format() -> void:
	var net_script := load("res://scripts/net/game_net.gd")
	var net = net_script.new()
	var code: String = net.generate_code()
	assert_eq(code.length(), 6)
	for ch in code:
		assert_true("ABCDEFGHJKLMNPQRSTUVWXYZ23456789".find(ch) >= 0, ch)
	net.free()


func test_store_rename_delete() -> void:
	var deck := NormalizedDeck.new()
	deck.name = "Temp Gallery"
	deck.add_commander("Krenko, Mob Boss")
	deck.add_main("Mountain", 99)
	var rows := {
		"Krenko, Mob Boss": {name = "Krenko, Mob Boss", type_line = "Legendary Creature — Goblin Warrior", color_identity = ["R"], commander_legal = true},
		"Mountain": {name = "Mountain", type_line = "Basic Land — Mountain", color_identity = ["R"], commander_legal = true},
	}
	var store := DeckStore.new()
	var path := store.save(deck, rows, {ok = true, total = 100, errors = PackedStringArray(), warnings = PackedStringArray()})
	assert_true(path != "")
	assert_true(store.rename(path, "Renamed Krenko"))
	var loaded: Dictionary = store.load_path(path)
	assert_eq(str(loaded.get("name", "")), "Renamed Krenko")
	assert_true(store.delete_path(path))
	assert_true(store.load_path(path).is_empty())
