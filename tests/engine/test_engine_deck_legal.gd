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
