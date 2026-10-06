@tool
extends McpTestSuite

## The bug report: the last three turns of play-by-play, both boards, the text the player wrote and the saved files.

const Fixtures := preload("res://tests/engine/fixtures.gd")


func suite_name() -> String:
	return "bug_report"


func _row(name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "") -> Dictionary:
	return {name = name, oracle_id = name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}


func _session() -> GameSession:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Oddity", "{1}", 1, "Artifact", "Flurble the wombat thrice and then some."))
	var d := CardDatabase.new()
	d.setup(cat)
	var s := GameSession.new()
	s.db = d
	s.engine = Fixtures.empty_engine_1v1()
	s.you_seat = 0
	Fixtures.spawn_named(s.engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(s.engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Oddity")
	Fixtures.spawn_named(s.engine, d, 0, EngineEnums.ZoneId.HAND, "Test Bear")
	return s


func test_history_keeps_only_the_last_three_turns() -> void:
	var lines: Array = []
	for turn in range(1, 6):
		lines.append({t = "Turn %d" % turn, k = "turn", cards = []})
		lines.append({t = "action in turn %d" % turn, k = "you", cards = []})
	var kept := BugReport.history_last_turns(lines, 3)
	assert_eq(kept.size(), 6, "three turns of two lines")
	assert_true(str(kept[0]).contains("Turn 3"), "starts at turn 3")
	assert_true(str(kept[kept.size() - 1]).contains("turn 5"), "ends at turn 5")
	assert_eq(BugReport.history_last_turns(lines.slice(0, 4), 3).size(), 4, "fewer turns: everything")


func test_report_holds_what_the_player_wrote_and_the_board() -> void:
	var s := _session()
	s.history.lines = [{t = "Turn 1", k = "turn", cards = []}, {t = "You cast Test Bear.", k = "you", cards = []}]
	var r := BugReport.build(s, "The bear did nothing", "It should have attacked", "BF-test")
	assert_eq(r["what_happened"], "The bear did nothing")
	assert_eq(r["what_didnt_happen"], "It should have attacked")
	assert_true(r.has("board") and r.has("players") and r.has("history") and r.has("events"), "state sections are there")
	var board: Dictionary = r["board"]
	var mine: Dictionary = board["0"]
	assert_true(str((mine["battlefield"] as Array)[0]).begins_with("Test Bear"), "my battlefield lists the bear")
	assert_eq((mine["hand"] as Array).size(), 1, "my hand has the second bear")
	var text := BugReport.to_text(r)
	assert_true(text.contains("WHAT HAPPENED") and text.contains("The bear did nothing"), "text has the first box")
	assert_true(text.contains("WHAT DIDN'T HAPPEN") and text.contains("It should have attacked"), "text has the second box")
	assert_true(text.contains("You cast Test Bear."), "text has the play-by-play")


func test_cards_the_engine_cannot_read_are_listed() -> void:
	var s := _session()
	var r := BugReport.build(s, "", "")
	var unread: Dictionary = r["unread_lines"]
	assert_true(unread.has("Test Oddity"), "the unread artifact is named")
	assert_true(BugReport.to_text(r).contains("Flurble the wombat"), "and its line is in the text")


func test_save_writes_a_text_and_a_json_file() -> void:
	var s := _session()
	var r := BugReport.build(s, "something broke", "it should not have", "BF-test")
	var path := BugReport.save(r, "user://bug_reports_test")
	assert_true(path != "" and FileAccess.file_exists(path), "the text file exists")
	var body := FileAccess.get_file_as_string(path)
	assert_true(body.contains("something broke"), "it holds the report")
	var json_path := path.trim_suffix(".txt") + ".json"
	assert_true(FileAccess.file_exists(json_path), "the json file exists")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	assert_true(parsed is Dictionary and str((parsed as Dictionary).get("what_happened", "")) == "something broke", "the json reads back")


func test_a_guest_without_an_engine_still_gets_a_report() -> void:
	var s := GameSession.new()
	s.history.lines = [{t = "Turn 4", k = "turn", cards = []}, {t = "Rival casts Something.", k = "rival", cards = []}]
	var r := BugReport.build(s, "x", "y")
	assert_true(not r.has("board"), "no board without an engine")
	assert_true(BugReport.to_text(r).contains("Rival casts Something."), "but the play-by-play is saved")
