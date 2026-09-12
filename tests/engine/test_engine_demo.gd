@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

func suite_name() -> String:
	return "engine_demo"


func test_deal_puts_commander_and_99_library() -> void:
	var db := DemoSetup.memory_db()
	var demo := DemoSetup.krenko_vs_talrand(db)
	var engine := RulesEngine.new()
	engine.setup_demo(demo, FormatRules.commander_1v1_table(), 1)
	assert_eq(engine.state.players.size(), 2)
	assert_eq(engine.library_size(0), 99)
	assert_eq(engine.hand_size(0), 0)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, 0).size(), 1)
	var k: GameObject = engine.state.objects[engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, 0).object_ids[0]]
	assert_true(k.is_commander)
	assert_eq((k.definition as CardDefinition).name, DemoSetup.KRENKO)
	engine.draw_n(0, 7)
	assert_eq(engine.hand_size(0), 7)
	assert_eq(engine.library_size(0), 92)


func test_library_shuffle_differs_by_seed() -> void:
	var db := DemoSetup.memory_db()
	var a := RulesEngine.new()
	a.setup_demo(DemoSetup.krenko_vs_talrand(db), FormatRules.commander_1v1_table(), 1)
	var b := RulesEngine.new()
	b.setup_demo(DemoSetup.krenko_vs_talrand(db), FormatRules.commander_1v1_table(), 99)
	var top_a := _names_in(a, 0, EngineEnums.ZoneId.LIBRARY)
	var top_b := _names_in(b, 0, EngineEnums.ZoneId.LIBRARY)
	assert_eq(top_a.size(), 99)
	assert_eq(top_b.size(), 99)
	assert_ne(top_a, top_b)


func test_play_a_land_from_opening_draw() -> void:
	var db := DemoSetup.memory_db()
	var engine := RulesEngine.new()
	engine.setup_demo(DemoSetup.krenko_vs_talrand(db), FormatRules.commander_1v1_table(), 1)
	engine.draw_n(0, 7)
	var land_id := 0
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	for oid in hand.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if obj.definition is CardDefinition and (obj.definition as CardDefinition).is_land():
			land_id = obj.object_id
			break
	if land_id == 0:
		var spawned: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
		land_id = spawned.object_id
	var result := engine.submit(Fixtures.play_land(0, land_id))
	assert_true(result.ok, result.error)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).size(), 1)


func _names_in(engine: RulesEngine, player_id: int, zone_id: int) -> Array:
	var z: Zone = engine.state.zones.get_zone(zone_id, player_id)
	var names: Array = []
	for oid in z.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		names.append((obj.definition as CardDefinition).name if obj.definition is CardDefinition else "")
	return names
