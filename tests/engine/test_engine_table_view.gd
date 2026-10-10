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


func test_the_waiting_table_has_every_key_a_real_table_has() -> void:
	## A guest draws this until the host's first view arrives (it replaced the old prototype board).
	var session := GameSession.new()
	session.start_table_demo(1)
	var waiting := TableView.waiting()
	for side in ["you", "rival"]:
		var real: Dictionary = session.view.get(side)
		var blank: Dictionary = waiting.get(side)
		for k in real.keys():
			assert_true(blank.has(k), "waiting %s is missing '%s'" % [side, str(k)])
	assert_true(waiting.header_text() != "", "it can draw its header")
	assert_true(waiting.find_card("1").is_empty(), "and look up cards without error")


func test_a_new_game_keeps_the_chosen_decks_and_names_the_rival() -> void:
	## AUDIT-010 / AUDIT-022: the rival is named after the deck it plays, not "Talrand".
	var demo := DeckCatalog.vs_pair(DeckCatalog.BUILTIN_TALRAND, DeckCatalog.BUILTIN_KRENKO)
	var session := GameSession.new()
	session.start_with_demo(demo, 5)
	assert_eq(session.view.you["name"], "Talrand, Sky Summoner")
	assert_eq(session.view.rival["name"], "Krenko, Mob Boss")


func _face_down_session() -> GameSession:
	var fx := preload("res://tests/engine/fixtures.gd")
	var s := GameSession.new()
	s.db = fx.memory_db()
	s.engine = fx.empty_engine_1v1()
	s.you_seat = 0
	var secret := CardDefinition.new()
	secret.name = "Secret Dragon"
	secret.type_line = "Creature — Dragon"
	secret.oracle_text = "Morph {3}{R}{R}"
	secret.power = "5"
	secret.toughness = "5"
	for seat in [0, 1]:
		var obj := fx.spawn(s.engine, seat, EngineEnums.ZoneId.BATTLEFIELD, {definition = secret})
		obj.face_down = true
	return s


func test_face_down_permanents_are_hidden_from_the_other_player() -> void:
	## AUDIT-008: CR 708.2 - the opponent sees a nameless 2/2, never the card.
	var s := _face_down_session()
	var v := TableView.from_engine(s.engine, s)
	var mine: Dictionary = (v.you["creatures"] as Array)[0]
	var theirs: Dictionary = (v.rival["creatures"] as Array)[0]
	assert_eq(str(mine.name), "Secret Dragon", "you see your own face-down card")
	assert_true(bool(mine.face_down))
	assert_eq(str(theirs.name), "Face-down creature", "the rival's is masked")
	assert_eq(str(theirs.text), "")
	assert_eq(str(theirs.power), "2")
	assert_false(str(theirs.badge).contains("5/5"), "and the badge does not give the real size away")
	var remote := v.to_plain_for_remote()
	var host_side: Dictionary = (remote.you["creatures"] as Array)[0]
	var guest_side: Dictionary = (remote.rival["creatures"] as Array)[0]
	assert_eq(str(host_side.name), "Face-down creature", "the host's card is masked on the way to the guest")
	assert_eq(str(guest_side.name), "Secret Dragon", "the guest still sees their own face-down card")
	assert_false(JSON.stringify(remote.you).contains("Secret Dragon"), "nowhere in the host's seat")


func test_a_private_library_top_does_not_cross_the_network() -> void:
	## AUDIT-009: "you may look at the top card" is for the host alone; "play with the top card revealed" is for everyone.
	var v := TableView.new()
	v.you = {hand = [], exile_cards = [], library_top = {name = "Secret Top"}, library_top_public = false}
	v.rival = {hand = [], exile_cards = [], library_top = {name = "Own Top"}, library_top_public = false}
	var private_view := v.to_plain_for_remote()
	assert_eq((private_view.you.library_top as Dictionary).size(), 0, "the host's private top card is not sent")
	v.you.library_top_public = true
	assert_eq(str((v.to_plain_for_remote().you.library_top as Dictionary).get("name", "")), "Secret Top", "a revealed top card is public")


func test_cards_with_text_the_game_cannot_play_are_marked() -> void:
	## AUDIT-007: such a card used to do nothing in silence.
	var fx := preload("res://tests/engine/fixtures.gd")
	var cat := fx.memory_catalog() as CatalogSource.Memory
	cat.add({name = "Test Oddity", oracle_id = "test_oddity", mana_cost = "{1}", cmc = 1, type_line = "Artifact",
		oracle_text = "Flurble the wombat thrice and then some.", color_identity = [], colors = [], keywords = [], commander_legal = true})
	cat.add({name = "Test Vanilla", oracle_id = "test_vanilla", mana_cost = "{1}", cmc = 1, type_line = "Creature — Bear",
		oracle_text = "", power = "1", toughness = "1", color_identity = [], colors = [], keywords = [], commander_legal = true})
	var db := CardDatabase.new()
	db.setup(cat)
	var s := GameSession.new()
	s.db = db
	s.engine = fx.empty_engine_1v1()
	s.you_seat = 0
	fx.spawn_named(s.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Oddity")
	fx.spawn_named(s.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Vanilla")
	s.view = TableView.from_engine(s.engine, s)
	s._stamp_unsupported(s.view)
	var oddity: Dictionary = {}
	var vanilla: Dictionary = {}
	for c in s.view.you["noncreatures"]:
		oddity = c
	for c2 in s.view.you["creatures"]:
		vanilla = c2
	assert_true((oddity.get("unsupported", []) as Array).size() == 1, "the oddity is marked: %s" % str(oddity.get("unsupported")))
	assert_true(str((oddity.unsupported as Array)[0]).contains("Flurble"))
	assert_false(vanilla.has("unsupported"), "a fully read card is left alone")
