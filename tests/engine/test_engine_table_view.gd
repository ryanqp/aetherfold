@tool
extends McpTestSuite

func suite_name() -> String:
	return "engine_table_view"


func test_projected_keys_match_table() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	assert_true(session.view != null)
	assert_eq(session.match_start, GameSession.MatchStart.MULLIGAN_DECISION)
	assert_eq(session.view.you["hand"].size(), 7)
	assert_eq(int(session.view.you["library"]), 92)
	assert_eq(int(session.view.you["graveyard"]), 0)
	assert_eq(session.view.you["command"].size(), 1)
	var card: Dictionary = session.view.you["hand"][0]
	for k in ["id", "name", "type", "text", "kind", "cmc", "tapped", "sick", "instanceId", "zone", "mana_cost"]:
		assert_true(card.has(k), k)
	assert_eq(str(card.get("zone", "")), "hand")
	assert_true(session.view.header_text().find("Turn") >= 0)
	var found: Dictionary = session.view.find_card(str(card["id"]))
	assert_eq(str(found.get("name", "")), str(card["name"]))
	var in_hand: Dictionary = session.view.card_in_hand(str(card["id"]))
	assert_false(in_hand.is_empty())
	assert_eq(session.view.you["name"], "Krenko")
	assert_eq(session.view.rival["name"], "Talrand")
