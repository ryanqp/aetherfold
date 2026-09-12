@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

func suite_name() -> String:
	return "engine_play"


func test_cast_resolves_onto_battlefield() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	var db := DemoSetup.memory_db()
	var mtn: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	assert_true(session.play_land(mtn.object_id).ok)
	session.end_you_turn()
	if session.pending_draw_anim:
		session.ack_draw()
	var mtn2: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	assert_true(session.play_land(mtn2.object_id).ok)
	var fodder: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Dragon Fodder")
	var r: SubmitResult = session.cast_auto(0, fodder.object_id)
	assert_true(r.ok, r.error)
	assert_true(session.engine.state.stack == null or (session.engine.state.stack as MagicStack).is_empty())
	var tokens := 0
	var bf: Zone = session.engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = session.engine.state.objects[oid]
		if obj.is_token:
			tokens += 1
	assert_eq(tokens, 2)


func test_attack_from_main_deals_damage() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	var db := Fixtures.memory_db()
	var piker: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	piker.summoned_this_turn = false
	piker.tapped = false
	assert_eq(session.engine.legal_attacker_ids(0).size(), 1, "piker should be able to attack")
	var before: int = session.engine.state.players[1].life
	var r: SubmitResult = session.attack_all()
	assert_true(r.ok, r.error)
	assert_true(
		session.engine.state.players[1].life < before,
		"life %d should drop from %d (phase %d step %d)" % [
			session.engine.state.players[1].life, before,
			session.engine.state.phase, session.engine.state.step,
		]
	)


func test_krenko_activate_after_sickness() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	var db := DemoSetup.memory_db()
	var k: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	k.is_commander = true
	var blocked: SubmitResult = session.activate_auto(k.object_id)
	assert_false(blocked.ok)
	session.engine.turn.start_turn(0)
	var kid := 0
	var bf: Zone = session.engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = session.engine.state.objects[oid]
		if obj.definition is CardDefinition and (obj.definition as CardDefinition).name.begins_with("Krenko"):
			kid = obj.object_id
	assert_gt(kid, 0)
	var r: SubmitResult = session.activate_auto(kid)
	assert_true(r.ok, r.error)
	var tokens := 0
	bf = session.engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid2 in bf.object_ids:
		var obj2: GameObject = session.engine.state.objects[oid2]
		if obj2.is_token:
			tokens += 1
	assert_eq(tokens, 1)


func test_pass_advances_from_main_to_combat() -> void:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	assert_eq(session.engine.state.phase, EngineEnums.Phase.MAIN_1)
	session.pass_once()
	assert_eq(session.engine.state.phase, EngineEnums.Phase.COMBAT)
	session.pass_once()
	assert_eq(session.engine.state.step, EngineEnums.Step.DECLARE_ATTACKERS)
