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


func test_to_plain_for_remote_hides_your_hand_only() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	var view: TableView = session.view
	var full := view.to_plain()
	assert_true(full.you["hand"].size() > 0)
	var real_name: String = str(full.you["hand"][0].get("name", ""))
	assert_ne(real_name, "")

	var remote := view.to_plain_for_remote()
	assert_eq(remote.you["hand"].size(), full.you["hand"].size())
	for card in remote.you["hand"]:
		assert_true(bool(card.get("hidden", false)))
		assert_false(card.has("name"))
		assert_false(card.has("text"))
		assert_false(card.has("mana_cost"))

	# The other seat's hand (becomes the remote client's own hand after
	# the you/rival swap in GameNet.receive_view) must stay untouched.
	assert_eq(remote.rival["hand"].size(), full.rival["hand"].size())
	if remote.rival["hand"].size() > 0:
		assert_eq(str(remote.rival["hand"][0].get("name", "")), str(full.rival["hand"][0].get("name", "")))
