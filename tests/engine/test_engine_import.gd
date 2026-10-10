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
	assert_true(DeckSource.is_http_url("https://www.moxfield.com/decks/abc"))
	assert_false(DeckSource.is_http_url("javascript:alert(1)"))
	assert_eq(DeckSource.view_on_label("moxfield"), "View on Moxfield")
	assert_eq(DeckSource.view_on_label("archidekt"), "View on Archidekt")
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


func test_moxfield_v3_nested_cards_map() -> void:
	var json := {
		name = "V3 Nested",
		boards = {
			commanders = {
				count = 1,
				cards = {
					"abc": {quantity = 1, card = {name = "Krenko, Mob Boss"}},
				},
			},
			mainboard = {
				count = 99,
				cards = {
					"sol": {quantity = 1, card = {name = "Sol Ring"}},
					"mtn": {quantity = 98, card = {name = "Mountain"}},
				},
			},
			sideboard = {
				count = 1,
				cards = {
					"bolt": {quantity = 1, card = {name = "Lightning Bolt"}},
				},
			},
		},
	}
	var deck: NormalizedDeck = MoxfieldImporter.parse(json, "https://www.moxfield.com/decks/ZExXdg2U1UO-jl0mTquqLw")
	assert_eq(deck.commander_names()[0], "Krenko, Mob Boss")
	assert_eq(deck.library_count(), 99)
	assert_eq(deck.total_cards(), 100)
	for e in deck.commanders:
		assert_ne(str(e.get("name", "")), "cards")
	for e2 in deck.mainboard:
		assert_ne(str(e2.get("name", "")), "cards")
		assert_ne(str(e2.get("name", "")), "Lightning Bolt")


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


func test_archidekt_uses_the_decks_own_category_flags() -> void:
	## AUDIT-006: a player's "Tokens" tag for token makers is part of the deck; "Tokens & Extras" and the maybeboard are not,
	## and only a card's FIRST category decides.
	var json := {
		name = "Goblin Storm",
		categories = [
			{name = "Commander", isPremier = true, includedInDeck = true},
			{name = "Ramp", includedInDeck = true},
			{name = "Tokens", includedInDeck = true},
			{name = "Tokens & Extras", includedInDeck = false},
			{name = "Maybeboard", includedInDeck = false},
			{name = "Sideboard", includedInDeck = false},
		],
		cards = [
			{quantity = 1, categories = ["Commander"], card = {oracleCard = {name = "Zada, Hedron Grinder"}}},
			{quantity = 1, categories = ["Ramp"], card = {oracleCard = {name = "Sol Ring"}}},
			{quantity = 1, categories = ["Tokens"], card = {oracleCard = {name = "Siege-Gang Commander"}}},
			{quantity = 1, categories = ["Burn", "Tokens"], card = {oracleCard = {name = "Pashalik Mons"}}},
			{quantity = 1, categories = ["Maybeboard", "Sideboard", "Tokens"], card = {oracleCard = {name = "Searslicer Goblin"}}},
			{quantity = 1, categories = ["Tokens & Extras"], card = {oracleCard = {name = "Goblin Token Maker"}}},
			{quantity = 1, categories = ["Ramp"], companion = true, card = {oracleCard = {name = "Lurrus of the Dream-Den"}}},
		],
	}
	var deck: NormalizedDeck = ArchidektImporter.parse(json, "https://archidekt.com/decks/2")
	assert_eq(deck.commander_names()[0], "Zada, Hedron Grinder")
	var names := PackedStringArray()
	for e in deck.mainboard:
		names.append(str((e as Dictionary).get("name", "")))
	names.sort()
	assert_eq(", ".join(names), "Pashalik Mons, Siege-Gang Commander, Sol Ring", "the in-deck cards, nothing else")


func _network_import(url: String) -> Dictionary:
	var r: Dictionary = ImportPipeline.new().run(url, true)
	if not bool(r.get("ok", false)):
		skip("could not reach the deck site (%s): %s" % [url, str(r.get("error", "")).replace("\n", " ")])
	return r


func test_live_archidekt_if_network() -> void:
	var r := _network_import("https://archidekt.com/decks/22685587")
	if not bool(r.get("ok", false)):
		return
	var deck: NormalizedDeck = r.get("deck")
	assert_eq(deck.total_cards(), 100, "a Commander deck is 100 cards")
	assert_eq(deck.commander_names()[0], "Zada, Hedron Grinder")


func test_live_moxfield_if_network() -> void:
	var r := _network_import("https://www.moxfield.com/decks/bpAZEg9Kv02MRqlj1y72HA")
	if not bool(r.get("ok", false)):
		return
	var deck: NormalizedDeck = r.get("deck")
	assert_eq(deck.total_cards(), 100, "a Commander deck is 100 cards")
	assert_true(deck.commanders.size() >= 1)


func test_saved_deck_roundtrip() -> void:
	var deck := _mono_red(99)
	var rows := _rows_for(deck)
	var store := DeckStore.scratch("roundtrip")
	var path := store.save(deck, rows, {ok = true, errors = PackedStringArray(), warnings = PackedStringArray(), total = 100})
	assert_true(path != "")
	var loaded: Dictionary = store.load_path(path)
	assert_eq(str(loaded.get("name", "")), deck.name)
	assert_eq((loaded.get("commander", []) as Array).size(), 1)
	assert_true((loaded.get("cards", {}) as Dictionary).has("Mountain"))
	store.wipe()


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


func test_deck_store_finds_by_source_key_and_keeps_meta() -> void:
	var store := DeckStore.scratch("source-key")
	var deck := NormalizedDeck.new()
	deck.name = "Zz Edhrec Test"
	deck.add_commander("Zz Test Cmd", 1)
	deck.add_main("Mountain", 3)
	var key := "edhrec:zz-test-key"
	var path := store.save(deck, {}, {ok = true}, "", {is_imported = true, source_key = key, source = "edhrec_scryfall_top_100"})
	var rec := store.find_by_source_key(key)
	assert_false(rec.is_empty())
	assert_eq(str(rec.get("source")), "edhrec_scryfall_top_100")
	assert_true(bool(rec.get("is_imported")))
	store.delete_path(path)
	assert_true(store.find_by_source_key(key).is_empty())
	store.wipe()


func test_double_faced_names_resolve_by_front_face() -> void:
	assert_eq(ScryfallResolver._front_face("Fell the Profane // Fell Mire"), "Fell the Profane")
	assert_eq(ScryfallResolver._front_face("Sol Ring"), "Sol Ring")
	var deck := NormalizedDeck.new()
	deck.add_main("Treasure", 1)
	deck.remove_main("Treasure")
	assert_eq(deck.total_cards(), 0, "tokens can be dropped from a list")


func test_precons_ship_nine_commander_decks_of_100() -> void:
	var recs: Array = PreconDecks.new().bundled()
	assert_eq(recs.size(), PreconDecks.WANT, "nine bundled precons")
	var names := PackedStringArray()
	for r in recs:
		var rec: Dictionary = r
		names.append(str(rec.get("name", "")))
		assert_eq(str(rec.get("source", "")), PreconDecks.SOURCE)
		var total := 0
		for e in (rec.get("commander", []) as Array) + (rec.get("mainboard", []) as Array):
			total += int((e as Dictionary).get("quantity", 0))
		assert_eq(total, 100, "%s has 100 cards" % str(rec.get("name", "")))
		var cards: Dictionary = rec.get("cards", {})
		for e2 in (rec.get("commander", []) as Array) + (rec.get("mainboard", []) as Array):
			assert_true(cards.has(str((e2 as Dictionary).get("name", ""))), "row for %s" % str((e2 as Dictionary).get("name", "")))
		var cmd := DeckCatalog.commander_row(rec)
		assert_true(str((cmd.get("images", {}) as Dictionary).get("normal", "")) != "", "commander art for %s" % str(rec.get("name", "")))
	assert_eq(names[0], "Multiverse Reforged")
	assert_true(names.has("Calling All Angels"))
	assert_true(names.has("Odd and Ends"))


func test_precon_install_replaces_retired_starters() -> void:
	var store := DeckStore.scratch("precon-retire")
	var deck := NormalizedDeck.new()
	deck.name = "Zz Old Starter"
	deck.add_commander("Zz Test Cmd", 1)
	deck.add_main("Mountain", 3)
	var old_path := store.save(deck, {}, {ok = true}, "", {source = "moxfield_top_likes", source_key = "moxfield:zz-old"})
	assert_true(FileAccess.file_exists(old_path))
	var pd := PreconDecks.new()
	pd.store = store
	pd.install()
	assert_false(FileAccess.file_exists(old_path), "the retired starter deck is deleted")
	assert_eq(pd.saved_count(), PreconDecks.WANT)
	var again: Dictionary = pd.install()
	assert_eq(int(again.installed), 0, "a second install keeps what is saved")
	assert_eq(pd.saved_count(), PreconDecks.WANT)
	store.wipe()


func test_precon_deck_starts_a_vs_ai_game() -> void:
	var store := DeckStore.scratch("precon-game")
	var installer := PreconDecks.new()
	installer.store = store
	installer.install()
	var jace := ""
	var angels := ""
	for rec in store.list_decks():
		if str(rec.get("precon_id", "")) == "multiverse-reforged":
			jace = str(rec.get("_path", ""))
		if str(rec.get("precon_id", "")) == "calling-all-angels":
			angels = str(rec.get("_path", ""))
	assert_true(jace != "" and angels != "")
	var d := DeckCatalog.vs_pair(jace, angels)
	assert_eq(str(d.human_commanders[0]), "Jace, Multiverse Architect")
	assert_eq(str(d.rival_commanders[0]), "Giada, Font of Hope")
	store.wipe()


func test_a_deck_named_mono_red_is_kept() -> void:
	## It used to be deleted at every launch (AUDIT-004): only the player decides what is deleted.
	var store := DeckStore.scratch("mono-red")
	var deck := _mono_red(99)
	deck.name = "Mono Red Burn"
	var path := store.save(deck, _rows_for(deck), {ok = true})
	assert_true(path != "")
	assert_true(DeckStore.new().has_method("list_decks") and not DeckStore.new().has_method("purge_test_decks"), "no purge routine any more")
	assert_eq(store.list_decks().size(), 1, "the deck is still listed")
	store.wipe()


func test_saves_are_atomic_and_damaged_files_are_listed() -> void:
	var store := DeckStore.scratch("atomic")
	var deck := _mono_red(99)
	var path := store.save(deck, _rows_for(deck), {ok = true})
	assert_true(path != "" and not FileAccess.file_exists(path + ".tmp"), "no temporary file is left behind")
	## A save cut short leaves a half-written file: it is reported, not silently dropped.
	var broken := FileAccess.open(store.dir.path_join("broken-1.json"), FileAccess.WRITE)
	broken.store_string("{\"name\": \"Half a deck\", \"cards\": ")
	broken.close()
	assert_eq(store.list_decks().size(), 1, "only the good deck is a deck")
	assert_eq(store.list_damaged().size(), 1, "the broken file is listed as damaged")
	## Overwriting keeps a complete file.
	var again := store.save(deck, _rows_for(deck), {ok = true}, path)
	assert_eq(again, path)
	assert_true(store.load_path(path).has("cards"), "the replacement is a whole deck")
	store.wipe()


func test_a_failed_save_says_why() -> void:
	## A folder that can't exist: its parent is an ordinary file.
	DirAccess.make_dir_recursive_absolute("user://test_decks")
	var blocker := "user://test_decks/blocker-%d.txt" % Time.get_ticks_usec()
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var store := DeckStore.new(blocker.path_join("decks"))
	var deck := _mono_red(99)
	assert_eq(store.save(deck, _rows_for(deck), {ok = true}), "", "the save fails")
	assert_true(store.last_error != "", "and the reason is available to show")
	DirAccess.remove_absolute(blocker)


func test_unknown_cards_are_left_out_not_dealt_blank() -> void:
	## AUDIT-012: a misspelled card used to become a library object with no definition.
	var d := DemoSetup.table_demo(7)
	var list := DeckList.new()
	list.commander_oracle_ids = PackedStringArray(["krenko_mob_boss"])
	list.library.append({name = "Totally Not A Real Card", count = 2})
	list.library.append({name = "Mountain", count = 3})
	d.krenko_list = list
	var fx := preload("res://tests/engine/fixtures.gd")
	var engine := fx.empty_engine_1v1()
	d.apply(engine)
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	assert_eq(lib.size(), 3, "only the three Mountains were dealt")
	for oid in lib.object_ids:
		assert_true((engine.state.objects[oid] as GameObject).definition != null, "no card without a definition")
	assert_eq(d.missing_cards.size(), 1, "the unknown card is reported once: %s" % str(d.missing_cards))
	assert_true(str(d.missing_cards[0]).contains("Totally Not A Real Card"))


func test_a_deck_copy_is_independent_and_the_list_reads_back() -> void:
	var store := DeckStore.scratch("copy")
	var deck := _mono_red(99)
	deck.name = "Original"
	var path := store.save(deck, _rows_for(deck), {ok = true}, "", {source = "moxfield_commander_precons", source_key = "precon:x", precon_id = "x", sourceUrl = "https://example.test/deck"})
	var copy_path := store.duplicate(path)
	assert_true(copy_path != "" and copy_path != path, "a new file")
	var copy_rec: Dictionary = store.load_path(copy_path)
	assert_eq(str(copy_rec.get("name", "")), "Original (copy)")
	assert_eq(str(copy_rec.get("source", "")), "copy", "no longer a precon")
	assert_false(copy_rec.has("source_key") or copy_rec.has("precon_id") or copy_rec.has("sourceUrl"), "forgets where it came from")
	assert_eq(store.find_by_source_key("precon:x").get("_path", ""), path, "the original is still the one found by key")
	assert_eq(store.list_decks().size(), 2)
	## The exported list is what this game's own importer reads back.
	var text := DeckStore.export_text(store.load_path(path))
	var back: NormalizedDeck = TextDeckParser.new().parse(text)
	assert_eq(back.commander_names()[0], "Krenko, Mob Boss")
	assert_eq(back.total_cards(), 100, "commander plus 99")
	store.wipe()


func test_an_import_can_run_on_a_worker_thread() -> void:
	## AUDIT-005: the import window runs the pipeline off the main thread; it must not need the scene tree to find cards.
	var cat: Node = (load("res://scripts/scryfall_catalog.gd") as GDScript).new()
	cat.load_catalog()
	var pipe := ImportPipeline.new()
	pipe.catalog = cat
	var box := {"result": {}}
	var thread := Thread.new()
	thread.start(func() -> void: box["result"] = pipe.run("Commander\n1 Krenko, Mob Boss\n\nDeck\n1 Sol Ring\n1 Mountain", false))
	thread.wait_to_finish()
	var result: Dictionary = box["result"]
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq((result.get("unresolved", PackedStringArray()) as PackedStringArray).size(), 0, "all three cards found without the scene tree")
	assert_eq((result.get("rows", {}) as Dictionary).size(), 3)
	cat.free()
