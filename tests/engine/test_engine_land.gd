@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_land"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_island_enters_untapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Island")
	engine.state.active_player_id = 1
	engine.state.priority_player_id = 1
	engine.state.awaiting = {player_id = 1, type = &"priority"}
	var act := Fixtures.play_land(1, isl.object_id)
	assert_true(engine.submit(act).ok)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(engine.state.objects[bf.object_ids[0]].tapped)


func test_bot_island_stays_untapped_until_mana_ability() -> void:
	# Live table uses GameSession.ai_take_turn, not rival_ai.gd.
	# A basic Island must ETB untapped. Same-turn tap happens only if it is
	# activated for mana (auto_pay), which is legal and looks like "came in tapped"
	# if you only see the board after the bot's whole turn.
	var engine := Fixtures.empty_engine_1v1()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Island")
	engine.state.active_player_id = 1
	engine.state.priority_player_id = 1
	engine.state.awaiting = {player_id = 1, type = &"priority"}
	assert_true(engine.submit(Fixtures.play_land(1, isl.object_id)).ok)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	var land_id: int = int(bf.object_ids[0])
	assert_false(engine.state.objects[land_id].tapped, "basic must ETB untapped")
	var opt: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Opt")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 1
	a.object_id = opt.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	assert_true(engine.state.objects[land_id].tapped, "Island taps when paying for Opt")


func test_play_one_land() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var old_id := mtn.object_id
	var result := engine.submit(Fixtures.play_land(0, old_id))
	assert_true(result.ok, result.error)
	assert_true(bool(engine.state.land_played[0]))
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(hand.size(), 0)
	assert_eq(bf.size(), 1)
	var on_bf: GameObject = engine.state.objects[bf.object_ids[0]]
	assert_eq(on_bf.linked_from, old_id)
	assert_eq(on_bf.zone, EngineEnums.ZoneId.BATTLEFIELD)
	assert_true(_is_land_def(on_bf))


func test_second_land_same_turn_fails() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var a: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var b: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Island")
	assert_true(engine.submit(Fixtures.play_land(0, a.object_id)).ok)
	var second := engine.submit(Fixtures.play_land(0, b.object_id))
	assert_false(second.ok)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(hand.size(), 1)


func test_non_land_cannot_be_played_as_land() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Piker")
	var result := engine.submit(Fixtures.play_land(0, piker.object_id))
	assert_false(result.ok)


func test_inactive_player_cannot_play_land() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Mountain")
	var result := engine.submit(Fixtures.play_land(1, mtn.object_id))
	assert_false(result.ok)


func test_land_drop_resets_next_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var a: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var b: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Island")
	assert_true(engine.submit(Fixtures.play_land(0, a.object_id)).ok)
	engine.state.land_played[0] = false
	var b_id := b.object_id
	var again := engine.submit(Fixtures.play_land(0, b_id))
	assert_true(again.ok, again.error)


func test_legal_actions_offer_one_land() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var land_acts := 0
	for act in engine.legal_actions(0):
		if (act as GameAction).kind == GameAction.Kind.PLAY_LAND:
			land_acts += 1
	assert_eq(land_acts, 1)


func _is_land_def(obj: GameObject) -> bool:
	return obj.definition is CardDefinition and (obj.definition as CardDefinition).is_land()
