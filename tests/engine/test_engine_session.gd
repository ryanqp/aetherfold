@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

func suite_name() -> String:
	return "engine_session"


func test_auto_pay_taps_island_for_opt() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var db := Fixtures.memory_db()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	isl.summoned_this_turn = false
	var opt: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Opt")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = opt.object_id
	a.extra = {auto_pay = true}
	var r := engine.submit(a)
	assert_true(r.ok, r.error)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.GIVING_PRIORITY)
	assert_eq((engine.state.stack as MagicStack).size(), 1)
	assert_true(engine.state.objects[isl.object_id].tapped)


func test_basic_land_enters_untapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var db := Fixtures.memory_db()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var r := engine.submit(Fixtures.play_land(0, mtn.object_id))
	assert_true(r.ok, r.error)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	var on_bf: GameObject = engine.state.objects[bf.object_ids[0]]
	assert_false(on_bf.tapped)


func test_forgotten_cave_enters_tapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var db := Fixtures.memory_db()
	var cave: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Forgotten Cave")
	assert_true(engine.submit(Fixtures.play_land(0, cave.object_id)).ok)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	var on_bf: GameObject = engine.state.objects[bf.object_ids[0]]
	assert_true(on_bf.tapped)


func test_second_land_after_end_turn() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	var db := DemoSetup.memory_db()
	var a: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	assert_true(session.play_land(a.object_id).ok)
	session.end_you_turn()
	assert_eq(session.engine.state.active_player_id, 0)
	assert_true(session.pending_draw_anim, "P0 should have a draw to ack on turn 3")
	assert_true(
		session.engine.state.phase == EngineEnums.Phase.MAIN_1
		or session.engine.state.phase == EngineEnums.Phase.MAIN_2
	)
	var b: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Forgotten Cave")
	var r2 := session.play_land(b.object_id)
	assert_true(r2.ok, r2.error)
	assert_eq(session.view.you["lands"].size(), 2)


func test_session_plays_opening_land() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	var blocked := session.play_land(1)
	assert_false(blocked.ok)
	assert_eq(session.match_start, GameSession.MatchStart.MULLIGAN_DECISION)
	session.keep_hand(0)
	assert_eq(session.match_start, GameSession.MatchStart.MAIN_GAME)
	var land_id := 0
	for card in session.view.you["hand"]:
		if str(card.get("kind", "")) == "land":
			land_id = int(card.get("id", 0))
			break
	if land_id == 0:
		var spawned: GameObject = Fixtures.spawn_named(session.engine, DemoSetup.memory_db(), 0, EngineEnums.ZoneId.HAND, "Mountain")
		land_id = spawned.object_id
		session.rebuild_view()
	var r := session.play_land(land_id)
	assert_true(r.ok, r.error)
	assert_eq(session.view.you["lands"].size(), 1)
