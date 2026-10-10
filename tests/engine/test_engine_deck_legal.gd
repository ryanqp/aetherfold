@tool
extends McpTestSuite

func suite_name() -> String:
	return "engine_deck_legal"


func test_krenko_and_talrand_lists_are_legal() -> void:
	var db := DemoSetup.memory_db()
	var demo := DemoSetup.krenko_vs_talrand(db)
	var rules := FormatRules.commander_1v1_table()
	var k_err := DemoSetup.legality_errors(demo.krenko_list, db, DemoSetup.KRENKO, PackedStringArray(["R"]), rules)
	var t_err := DemoSetup.legality_errors(demo.talrand_list, db, DemoSetup.TALRAND, PackedStringArray(["U"]), rules)
	assert_eq(k_err.size(), 0, ",".join(k_err))
	assert_eq(t_err.size(), 0, ",".join(t_err))


func test_table_demo_is_commander_legal() -> void:
	var demo := DemoSetup.table_demo(1)
	var rules := FormatRules.commander_1v1_table()
	var k_err := DemoSetup.legality_errors(demo.krenko_list, demo.db, DemoSetup.KRENKO, PackedStringArray(["R"]), rules)
	var t_err := DemoSetup.legality_errors(demo.talrand_list, demo.db, DemoSetup.TALRAND, PackedStringArray(["U"]), rules)
	assert_eq(k_err.size(), 0, ",".join(k_err))
	assert_eq(t_err.size(), 0, ",".join(t_err))
	assert_eq(DemoSetup._list_count(demo.krenko_list), 99)
	assert_eq(DemoSetup._list_count(demo.talrand_list), 99)


func test_two_fodder_is_rejected() -> void:
	var db := DemoSetup.memory_db()
	var demo := DemoSetup.krenko_vs_talrand(db)
	var bad: DeckList = demo.krenko_list
	for entry in bad.library:
		if str(entry.get("name", "")) == "Dragon Fodder":
			entry["count"] = 2
		elif str(entry.get("name", "")) == "Goblin Volunteer 01":
			entry["count"] = 0
	var err := DemoSetup.legality_errors(bad, db, DemoSetup.KRENKO, PackedStringArray(["R"]), FormatRules.commander_1v1_table())
	var joined := ",".join(err)
	assert_true(joined.find("singleton") >= 0, joined)


func _cmdr(card_name: String, text: String, type_line: String = "Legendary Creature — Human") -> Dictionary:
	return {name = card_name, oracle_text = text, type_line = type_line, keywords = [], color_identity = []}


func test_commander_pairs_follow_the_partner_rules() -> void:
	var v := CommanderValidator.new()
	var partner_a := _cmdr("Plain A", "Partner (You can have two commanders if both have partner.)")
	var partner_b := _cmdr("Plain B", "Partner")
	var survivors_a := _cmdr("Survivor A", "Partner — Survivors (You can have two commanders if both have this ability.)")
	var survivors_b := _cmdr("Survivor B", "Partner — Survivors")
	var father_son := _cmdr("Father", "Partner — Father & Son")
	var with_a := _cmdr("Pir", "Partner with Toothy, Imaginary Friend")
	var with_b := _cmdr("Toothy, Imaginary Friend", "Partner with Pir, Imaginary Friend")
	var friends_a := _cmdr("Friend A", "Friends forever (You can have two commanders if both have friends forever.)")
	var friends_b := _cmdr("Friend B", "Friends forever")
	var chooser := _cmdr("Chooser", "Choose a Background (You can have a Background as a second commander.)")
	var background := _cmdr("A Background", "Creatures you control get +1/+1.", "Legendary Enchantment — Background")
	var doctor := _cmdr("Doctor", "", "Legendary Creature — Time Lord Doctor")
	var companion := _cmdr("Companion", "Doctor's companion (You can have two commanders if the other is a Doctor.)")
	var plain := _cmdr("Plain Legend", "Flying")
	assert_true(v._pair_legal(partner_a, partner_b), "two plain partners")
	assert_true(v._pair_legal(survivors_a, survivors_b), "the same variant")
	assert_false(v._pair_legal(survivors_a, father_son), "different variants do not pair")
	assert_false(v._pair_legal(survivors_a, partner_a), "a variant does not pair with plain Partner")
	assert_true(v._pair_legal(with_a, with_b), "Partner with names each other")
	assert_false(v._pair_legal(with_a, partner_a), "Partner with needs its partner")
	assert_true(v._pair_legal(friends_a, friends_b), "Friends forever")
	assert_true(v._pair_legal(chooser, background), "Choose a Background")
	assert_false(v._pair_legal(plain, background), "a Background needs 'Choose a Background'")
	assert_true(v._pair_legal(doctor, companion), "a Doctor and a Doctor's companion")
	assert_false(v._pair_legal(plain, companion), "a companion needs a Doctor")


func test_deck_problems_are_short_lines_and_a_missing_deck_is_reported() -> void:
	var legal := {name = "Fine", validation = {ok = true, errors = [], warnings = []}}
	assert_eq(DeckCatalog.problems_of(legal).size(), 0)
	assert_eq(DeckCatalog.problems_of({builtin = true, name = "Starter"}).size(), 0, "starters are not judged")
	var bad := {name = "Bad", validation = {ok = false, errors = ["Deck contains 90 cards including commander. Add 10 cards.", "Illegal card:\nSol Ring\n\nReason:\nBlue color identity is outside the commander's color identity."], warnings = ["Unresolved: Typo Card"]}}
	var problems := DeckCatalog.problems_of(bad)
	assert_eq(problems.size(), 3, str(problems))
	assert_eq(problems[1], "Illegal card:", "only the first line of a long error")
	assert_true(problems[2].contains("1 card could not be found"))
	var gone := DeckCatalog.playable("user://imported_decks/this-deck-was-deleted.json")
	assert_false(bool(gone.ok), "a deleted deck is not playable")
	assert_true(bool(DeckCatalog.playable(DeckCatalog.BUILTIN_KRENKO).ok))
