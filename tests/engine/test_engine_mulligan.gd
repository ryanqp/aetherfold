@tool
extends McpTestSuite

func suite_name() -> String:
	return "engine_mulligan"


func test_deal_is_99_plus_commander() -> void:
	var engine := _fresh(1)
	assert_eq(engine.library_size(0), 99)
	assert_eq(engine.hand_size(0), 0)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, 0).size(), 1)
	assert_eq(engine.library_size(1), 99)
	assert_eq(engine.hand_size(1), 0)


func test_shuffle_is_real_fisher_yates() -> void:
	var a := _fresh(1)
	var b := _fresh(99)
	assert_ne(_lib_names(a, 0), _lib_names(b, 0))
	assert_eq(a.library_size(0), 99)
	assert_eq(_unique_ids(a).size(), _object_count(a))


func test_opening_draw_moves_seven_from_library() -> void:
	var engine := _fresh(1)
	var before := _id_set(engine, 0, EngineEnums.ZoneId.LIBRARY)
	engine.draw_n(0, 7)
	assert_eq(engine.hand_size(0), 7)
	assert_eq(engine.library_size(0), 92)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	for oid in hand.object_ids:
		var obj: GameObject = engine.state.objects[int(oid)]
		assert_false(lib.has(int(oid)))
		assert_true(before.has(obj.linked_from), "drawn card was not taken from the pre-draw library")
		assert_eq(obj.zone, EngineEnums.ZoneId.HAND)
	assert_eq(_unique_ids(engine).size(), _object_count(engine))
	assert_eq(_unique_uuids(engine).size(), _object_count(engine))


func test_session_opening_and_keep() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	assert_eq(session.match_start, GameSession.MatchStart.MULLIGAN_DECISION)
	assert_eq(session.engine.hand_size(0), 7)
	assert_eq(int(session.view.you["library"]), 92)
	assert_eq(session.view.you["hand"].size(), 7)
	for card in session.view.you["hand"]:
		assert_true(card.has("name"))
		assert_true(card.has("id"))
		assert_true(card.has("instanceId"))
		assert_true(card.has("type"))
	session.keep_hand(0)
	assert_eq(session.match_start, GameSession.MatchStart.MAIN_GAME)
	assert_eq(session.engine.hand_size(0), 7)
	assert_eq(session.engine.library_size(0), 92)


func test_mulligan_reshuffles_and_does_not_duplicate() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.take_mulligan(0)
	assert_eq(session.engine.state.players[0].mulligan_count, 1)
	assert_eq(session.engine.hand_size(0), 7)
	assert_eq(session.engine.library_size(0), 92)
	assert_eq(session.match_start, GameSession.MatchStart.MULLIGAN_DECISION)
	for card in session.view.you["hand"]:
		assert_false(session.engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0).has(int(card.get("id", 0))))
	assert_eq(_unique_ids(session.engine).size(), _object_count(session.engine))
	assert_eq(_unique_uuids(session.engine).size(), _object_count(session.engine))
	_assert_no_dual_zone(session.engine)
	session.keep_hand(0)
	assert_eq(session.match_start, GameSession.MatchStart.PUT_BACK)
	assert_eq(session.put_back_remaining, 1)
	var oid := int(session.view.you["hand"][0]["id"])
	session.put_back_card(oid)
	assert_eq(session.match_start, GameSession.MatchStart.MAIN_GAME)
	assert_eq(session.engine.hand_size(0), 6)
	assert_eq(session.engine.library_size(0), 93)


func test_draw_decrements_library_by_one() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	var lib := session.engine.library_size(0)
	var hand := session.engine.hand_size(0)
	var drawn: Dictionary = session.draw_from_library(0)
	assert_false(drawn.is_empty())
	assert_eq(session.engine.library_size(0), lib - 1)
	assert_eq(session.engine.hand_size(0), hand + 1)
	assert_eq(int(session.view.you["library"]), lib - 1)
	assert_eq(session.view.you["hand"].size(), hand + 1)
	assert_eq(str(drawn.get("zone", "")), "hand")
	assert_false(session.engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0).has(int(drawn.get("id", 0))))


func test_draw_until_empty_matches_count() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	var n := session.engine.library_size(0)
	assert_eq(n, 92)
	for i in n:
		var card: Dictionary = session.draw_from_library(0)
		assert_false(card.is_empty(), "draw %d failed" % i)
		assert_eq(session.engine.library_size(0), n - i - 1)
		assert_eq(int(session.view.you["library"]), session.engine.library_size(0))
		assert_eq(session.engine.hand_size(0), 7 + i + 1)
	assert_true(session.draw_from_library(0).is_empty())
	assert_eq(session.engine.library_size(0), 0)
	assert_eq(int(session.view.you["library"]), 0)
	_assert_no_dual_zone(session.engine)


func test_opening_hand_has_card_faces() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	assert_eq(session.view.you["hand"].size(), 7)
	var with_art := 0
	for card in session.view.you["hand"]:
		assert_true(str(card.get("name", "")) != "")
		assert_true(str(card.get("instanceId", "")) != "")
		assert_true(str(card.get("type", "")) != "")
		assert_eq(str(card.get("zone", "")), "hand")
		if str(card.get("scryfall_id", "")) != "" or str(card.get("imageUrl", "")) != "":
			with_art += 1
	var cat := DemoSetup._scryfall()
	if cat != null and bool(cat.get("loaded")):
		assert_true(with_art >= 1, "Scryfall loaded but opening hand has no image refs")


func test_mulligan_does_not_create_or_lose_cards() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	var before := _object_count(session.engine)
	assert_eq(before, 200)
	session.take_mulligan(0)
	assert_eq(_object_count(session.engine), before)
	session.take_mulligan(0)
	assert_eq(_object_count(session.engine), before)
	session.keep_hand(0)
	assert_eq(_object_count(session.engine), before)
	_assert_no_dual_zone(session.engine)


func test_empty_library_draw_is_null() -> void:
	var engine := Fixtures_empty()
	assert_eq(engine.draw_card(0), null)


func test_players_have_independent_libraries() -> void:
	var engine := _fresh(1)
	engine.draw_n(0, 7)
	assert_eq(engine.library_size(0), 92)
	assert_eq(engine.library_size(1), 99)
	assert_eq(engine.hand_size(1), 0)


func _fresh(seed: int) -> RulesEngine:
	var db := DemoSetup.memory_db()
	var engine := RulesEngine.new()
	engine.setup_demo(DemoSetup.krenko_vs_talrand(db), FormatRules.commander_1v1_table(), seed)
	return engine


func Fixtures_empty() -> RulesEngine:
	var engine := RulesEngine.new()
	engine.setup(FormatRules.commander_1v1_table(), 1)
	return engine


func _lib_names(engine: RulesEngine, player_id: int) -> Array:
	var z: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, player_id)
	var names: Array = []
	for oid in z.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		names.append((obj.definition as CardDefinition).name if obj.definition is CardDefinition else "")
	return names


func _id_set(engine: RulesEngine, player_id: int, zone_id: int) -> Dictionary:
	var d := {}
	var z: Zone = engine.state.zones.get_zone(zone_id, player_id)
	if z == null:
		return d
	for oid in z.object_ids:
		d[int(oid)] = true
	return d


func _unique_ids(engine: RulesEngine) -> Dictionary:
	var d := {}
	for oid in engine.state.objects.keys():
		d[int(oid)] = true
	return d


func _object_count(engine: RulesEngine) -> int:
	return engine.state.objects.size()


func _unique_uuids(engine: RulesEngine) -> Dictionary:
	var d := {}
	for oid in engine.state.objects.keys():
		var obj: GameObject = engine.state.objects[oid]
		d[obj.instance_uuid] = true
	return d


func _assert_no_dual_zone(engine: RulesEngine) -> void:
	var seen := {}
	var uuids := {}
	for pid in engine.state.players.size():
		for zid in [
			EngineEnums.ZoneId.LIBRARY,
			EngineEnums.ZoneId.HAND,
			EngineEnums.ZoneId.GRAVEYARD,
			EngineEnums.ZoneId.EXILE,
			EngineEnums.ZoneId.COMMAND,
		]:
			var z: Zone = engine.state.zones.get_zone(zid, pid)
			if z == null:
				continue
			for oid in z.object_ids:
				assert_false(seen.has(int(oid)), "object %d in two zones" % int(oid))
				seen[int(oid)] = true
				var obj: GameObject = engine.state.objects.get(int(oid))
				if obj != null and obj.instance_uuid != "":
					assert_false(uuids.has(obj.instance_uuid), "uuid %s in two zones" % obj.instance_uuid)
					uuids[obj.instance_uuid] = true
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf != null:
		for oid in bf.object_ids:
			assert_false(seen.has(int(oid)))
			seen[int(oid)] = true
