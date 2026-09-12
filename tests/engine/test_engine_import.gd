@tool
extends McpTestSuite

func suite_name() -> String:
	return "engine_import"


func test_detects_sources() -> void:
	assert_eq(DeckSource.detect("https://www.moxfield.com/decks/bpAZEg9Kv02MRqlj1y72HA"), DeckSource.Kind.MOXFIELD)
	assert_eq(DeckSource.detect("https://archidekt.com/decks/1234567/my-deck"), DeckSource.Kind.ARCHIDEKT)
	assert_eq(DeckSource.detect("https://tappedout.net/mtg-decks/goblin-time/"), DeckSource.Kind.TAPPEDOUT)
	assert_eq(DeckSource.detect("https://deckstats.net/decks/24472/1126678-guttersniplicate"), DeckSource.Kind.DECKSTATS)
	assert_eq(DeckSource.detect("1 Sol Ring\n1 Command Tower"), DeckSource.Kind.TEXT)
	assert_eq(DeckSource.detect("https://example.com/not-a-deck"), DeckSource.Kind.UNKNOWN)
	assert_eq(DeckSource.extract_moxfield_id("https://www.moxfield.com/decks/bpAZEg9Kv02MRqlj1y72HA/primer"), "bpAZEg9Kv02MRqlj1y72HA")
	assert_eq(DeckSource.extract_archidekt_id("https://archidekt.com/decks/1234567/my-deck"), "1234567")
	var ds := DeckSource.extract_deckstats_ids("https://deckstats.net/decks/24472/1126678-guttersniplicate")
	assert_eq(ds.size(), 2)
	assert_eq(ds[0], "24472")
	assert_eq(ds[1], "1126678")


func test_unsupported_url_is_friendly() -> void:
	var pipe := ImportPipeline.new()
	var r: Dictionary = pipe.run("https://example.com/not-a-deck", false)
	assert_false(bool(r.get("ok", true)))
	assert_true(str(r.get("error", "")).find("Unsupported") >= 0)


func test_parses_plain_text_and_mtgo() -> void:
	var parser := TextDeckParser.new()
	var text := """
Commander
1 Krenko, Mob Boss
Mainboard
1 Sol Ring
1x Command Tower
1 Lightning Greaves (C21) 12
SB: 1 Negate
Maybeboard
1 Chaos Warp
"""
	var deck: NormalizedDeck = parser.parse(text)
	assert_eq(deck.commanders.size(), 1)
	assert_eq(str(deck.commanders[0].get("name", "")), "Krenko, Mob Boss")
	assert_eq(deck.mainboard.size(), 3)
	assert_eq(deck.library_count(), 3)
	assert_eq(deck.total_cards(), 4)
	for e in deck.mainboard:
		assert_ne(str(e.get("name", "")), "Negate")
		assert_ne(str(e.get("name", "")), "Chaos Warp")


func test_parses_arena_style() -> void:
	var parser := TextDeckParser.new()
	var deck: NormalizedDeck = parser.parse("Deck\n1 Sol Ring\n1 Command Tower\nCommander\n1 Atraxa, Praetors' Voice\n")
	assert_eq(deck.commander_names()[0], "Atraxa, Praetors' Voice")
	assert_eq(deck.library_count(), 2)


func test_validation_100_cards() -> void:
	var deck := _mono_red(99)
	var rows := _rows_for(deck)
	var v: Dictionary = CommanderValidator.new().validate(deck, rows)
	assert_true(bool(v.get("ok", false)), ",".join(v.get("errors", PackedStringArray())))
	assert_eq(int(v.get("total", 0)), 100)


func test_validation_99_cards() -> void:
	var deck := _mono_red(98)
	var v: Dictionary = CommanderValidator.new().validate(deck, _rows_for(deck))
	assert_false(bool(v.get("ok", true)))
	var joined := ",".join(v.get("errors", PackedStringArray()))
	assert_true(joined.find("99") >= 0, joined)
	assert_true(joined.find("Add 1 card") >= 0, joined)


func test_validation_101_cards() -> void:
	var deck := _mono_red(100)
	var v: Dictionary = CommanderValidator.new().validate(deck, _rows_for(deck))
	assert_false(bool(v.get("ok", true)))
	var joined := ",".join(v.get("errors", PackedStringArray()))
	assert_true(joined.find("101") >= 0, joined)
	assert_true(joined.find("exactly 100") >= 0, joined)


func test_illegal_duplicate() -> void:
	var deck := NormalizedDeck.new()
	deck.add_commander("Krenko, Mob Boss")
	deck.add_main("Sol Ring", 2)
	deck.add_main("Mountain", 97)
	var rows := _rows_for(deck)
	rows["Sol Ring"] = {
		name = "Sol Ring", type_line = "Artifact", oracle_text = "{T}: Add {C}{C}.",
		color_identity = [], commander_legal = true,
	}
	var v: Dictionary = CommanderValidator.new().validate(deck, rows)
	var joined := ",".join(v.get("errors", PackedStringArray()))
	assert_true(joined.find("duplicate") >= 0 or joined.find("Sol Ring") >= 0, joined)


func test_illegal_color_identity() -> void:
	var deck := NormalizedDeck.new()
	deck.add_commander("Krenko, Mob Boss")
	deck.add_main("Cyclonic Rift", 1)
	deck.add_main("Mountain", 98)
	var rows := _rows_for(deck)
	rows["Cyclonic Rift"] = {
		name = "Cyclonic Rift", type_line = "Instant", oracle_text = "",
		color_identity = ["U"], commander_legal = true,
	}
	var v: Dictionary = CommanderValidator.new().validate(deck, rows)
	var joined := ",".join(v.get("errors", PackedStringArray()))
	assert_true(joined.find("Cyclonic Rift") >= 0, joined)
	assert_true(joined.find("Blue") >= 0 or joined.find("color identity") >= 0, joined)


func test_unresolved_listed() -> void:
	var deck := NormalizedDeck.new()
	deck.add_commander("Krenko, Mob Boss")
	deck.add_main("Mountain", 99)
	var unresolved := PackedStringArray(["This Card Does Not Exist 12345"])
	var v: Dictionary = CommanderValidator.new().validate(deck, _rows_for(deck), unresolved)
	assert_eq(v.get("unresolved", PackedStringArray()).size(), 1)


func test_relentless_rats_allowed() -> void:
	var deck := NormalizedDeck.new()
	deck.add_commander("Krenko, Mob Boss")
	deck.add_main("Relentless Rats", 4)
	deck.add_main("Mountain", 95)
	var rows := _rows_for(deck)
	rows["Relentless Rats"] = {
		name = "Relentless Rats",
		type_line = "Creature — Rat",
		oracle_text = "A deck can have any number of cards named Relentless Rats.",
		color_identity = ["R"],
		commander_legal = true,
	}
	var v: Dictionary = CommanderValidator.new().validate(deck, rows)
	var joined := ",".join(v.get("errors", PackedStringArray()))
	assert_true(joined.find("duplicate") < 0, joined)


func test_text_import_then_play() -> void:
	var cat := DemoSetup._scryfall()
	if cat == null or not bool(cat.get("loaded")):
		var deck := _mono_red(99)
		var rows := _rows_for(deck)
		var session := GameSession.new()
		session.start_imported(deck, rows, 1)
		assert_eq(session.engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, 0).size(), 1)
		assert_eq(session.engine.hand_size(0), 7)
		assert_eq(session.engine.library_size(0), 92)
		assert_eq(session.match_start, GameSession.MatchStart.MULLIGAN_DECISION)
		session.keep_hand(0)
		var lib := session.engine.library_size(0)
		session.draw_from_library(0)
		assert_eq(session.engine.library_size(0), lib - 1)
		return
	var deck2 := NormalizedDeck.new()
	deck2.add_commander("Krenko, Mob Boss")
	deck2.add_main("Mountain", 99)
	var resolved: Dictionary = ScryfallResolver.new().resolve(deck2, false)
	assert_true(resolved.rows.has("Krenko, Mob Boss") or resolved.rows.has("Mountain"))
	var session2 := GameSession.new()
	session2.start_imported(deck2, resolved.rows, 1)
	assert_eq(session2.engine.library_size(0) + session2.engine.hand_size(0), 99)
	assert_eq(session2.engine.hand_size(0), 7)
	session2.keep_hand(0)
	var n := session2.engine.library_size(0)
	while session2.engine.library_size(0) > 0:
		var card: Dictionary = session2.draw_from_library(0)
		assert_false(card.is_empty())
	assert_eq(session2.engine.library_size(0), 0)
	assert_true(session2.draw_from_library(0).is_empty())
	assert_eq(n, 92)


func test_moxfield_parser_fixture() -> void:
	var json := {
		name = "Goblin Test",
		commanders = {
			"Krenko, Mob Boss": {quantity = 1, card = {name = "Krenko, Mob Boss"}},
		},
		mainboard = {
			"Sol Ring": {quantity = 1, card = {name = "Sol Ring"}},
			"Mountain": {quantity = 2, card = {name = "Mountain"}},
		},
		sideboard = {
			"Lightning Bolt": {quantity = 1, card = {name = "Lightning Bolt"}},
		},
	}
	var deck: NormalizedDeck = MoxfieldImporter.parse(json, "https://www.moxfield.com/decks/abc")
	assert_eq(deck.name, "Goblin Test")
	assert_eq(deck.commanders.size(), 1)
	assert_eq(deck.library_count(), 3, str(deck.mainboard))
	for e in deck.mainboard:
		assert_ne(str(e.get("name", "")), "Lightning Bolt")


func test_archidekt_parser_fixture() -> void:
	var json := {
		name = "Arch Test",
		cards = [
			{quantity = 1, categories = ["Commander"], card = {oracleCard = {name = "Krenko, Mob Boss"}}},
			{quantity = 1, categories = ["Ramp"], card = {oracleCard = {name = "Sol Ring"}}},
			{quantity = 1, categories = ["Maybeboard"], card = {oracleCard = {name = "Chaos Warp"}}},
			{quantity = 1, categories = ["Sideboard"], card = {oracleCard = {name = "Negate"}}},
		],
	}
	var deck: NormalizedDeck = ArchidektImporter.parse(json, "https://archidekt.com/decks/1")
	assert_eq(deck.commander_names()[0], "Krenko, Mob Boss")
	assert_eq(deck.library_count(), 1)
	assert_eq(str(deck.mainboard[0].get("name", "")), "Sol Ring")


func test_live_archidekt_if_network() -> void:
	var url := "https://archidekt.com/decks/22685587"
	var r: Dictionary = ImportPipeline.new().run(url, true)
	if not bool(r.get("ok", false)):
		var err := str(r.get("error", ""))
		assert_true(err != "", "expected a friendly error when live fetch fails")
		return
	var deck: NormalizedDeck = r.get("deck")
	assert_true(deck.total_cards() >= 1, "archidekt returned no cards")
	assert_true(deck.commanders.size() >= 1, "archidekt missing commander")


func test_live_moxfield_if_network() -> void:
	var url := "https://www.moxfield.com/decks/bpAZEg9Kv02MRqlj1y72HA"
	var r: Dictionary = ImportPipeline.new().run(url, true)
	if not bool(r.get("ok", false)):
		var err := str(r.get("error", ""))
		assert_true(err != "", "expected a friendly error when live fetch fails")
		assert_false(err.to_lower().find("crash") >= 0)
		return
	var deck: NormalizedDeck = r.get("deck")
	assert_true(deck.total_cards() >= 1)
	assert_true(deck.commanders.size() >= 1)


func test_saved_deck_roundtrip() -> void:
	var deck := _mono_red(99)
	var rows := _rows_for(deck)
	var store := DeckStore.new()
	var path := store.save(deck, rows, {ok = true, errors = PackedStringArray(), warnings = PackedStringArray(), total = 100})
	assert_true(path != "")
	var loaded: Dictionary = store.load_path(path)
	assert_eq(str(loaded.get("name", "")), deck.name)
	assert_eq((loaded.get("commander", []) as Array).size(), 1)
	assert_true((loaded.get("cards", {}) as Dictionary).has("Mountain"))


func _mono_red(mountains: int) -> NormalizedDeck:
	var deck := NormalizedDeck.new()
	deck.name = "Mono Red Test"
	deck.add_commander("Krenko, Mob Boss")
	deck.add_main("Mountain", mountains)
	return deck


func _rows_for(deck: NormalizedDeck) -> Dictionary:
	var rows := {}
	rows["Krenko, Mob Boss"] = {
		name = "Krenko, Mob Boss",
		id = "krenko-id",
		oracle_id = "krenko_mob_boss",
		type_line = "Legendary Creature — Goblin Warrior",
		oracle_text = "{T}: Create X Goblin tokens.",
		color_identity = ["R"],
		commander_legal = true,
		power = "3",
		toughness = "3",
		mana_cost = "{2}{R}{R}",
	}
	rows["Mountain"] = {
		name = "Mountain",
		id = "mountain-id",
		oracle_id = "mountain",
		type_line = "Basic Land — Mountain",
		oracle_text = "({T}: Add {R}.)",
		color_identity = ["R"],
		commander_legal = true,
	}
	return rows
