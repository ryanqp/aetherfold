@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_ir_batch"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_divination_draws_two() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	isl.summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island").summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island").summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Piker")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Piker")
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Divination")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size(), 2)


func test_krenkos_command_makes_two_goblins() -> void:
	var engine := Fixtures.empty_engine_1v1()
	_red_mana(engine, 2)
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Krenko's Command")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	Fixtures.both_pass(engine)
	assert_eq(_token_count(engine), 2)


func test_hordeling_outburst_makes_three_goblins() -> void:
	var engine := Fixtures.empty_engine_1v1()
	_red_mana(engine, 3)
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Hordeling Outburst")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	Fixtures.both_pass(engine)
	assert_eq(_token_count(engine), 3)


func test_sol_ring_adds_two_colorless() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ring: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Sol Ring")
	ring.summoned_this_turn = false
	assert_true(engine.submit(Fixtures.activate_mana(0, ring.object_id, &"sol_ring_c")).ok)
	var pool: ManaPool = engine.mana.pool(0)
	assert_eq(pool.colorless, 2)


func test_llanowar_elves_add_green_after_sickness() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var elf: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Llanowar Elves")
	assert_true(elf.summoned_this_turn)
	elf.summoned_this_turn = false
	assert_true(engine.submit(Fixtures.activate_mana(0, elf.object_id, &"llanowar_g")).ok)
	assert_eq(engine.mana.pool(0).g, 1)


func test_dark_ritual_adds_three_black() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{B}"))
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Dark Ritual")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	var r := engine.submit(a)
	assert_true(r.ok, r.error)
	Fixtures.both_pass(engine)
	assert_eq(engine.mana.pool(0).b, 3)


func test_boomerang_returns_permanent() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	_blue_mana(engine, 2)
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Boomerang")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	var t := Fixtures.choose_targets(0, [piker.object_id])
	t.extra = {auto_pay = true}
	assert_true(engine.submit(t).ok)
	Fixtures.both_pass(engine)
	var hid: int = 0
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1)
	if hand.size() > 0:
		hid = int(hand.object_ids[0])
	assert_gt(hid, 0)
	assert_eq((engine.state.objects[hid].definition as CardDefinition).name, "Goblin Piker")


func test_shock_damages_player() -> void:
	var engine := Fixtures.empty_engine_1v1()
	_red_mana(engine, 1)
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Shock")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	var t := Fixtures.choose_targets(0, [TargetingManager.encode_player(1)])
	t.extra = {auto_pay = true}
	assert_true(engine.submit(t).ok, "target")
	Fixtures.both_pass(engine)
	assert_eq(engine.state.players[1].life, 38)


func test_lightning_bolt_kills_piker() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	_red_mana(engine, 1)
	var spell: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Lightning Bolt")
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok)
	var t := Fixtures.choose_targets(0, [piker.object_id])
	t.extra = {auto_pay = true}
	assert_true(engine.submit(t).ok)
	Fixtures.both_pass(engine)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1)
	assert_eq(gy.size(), 1)


func _red_mana(engine: RulesEngine, n: int) -> void:
	for _i in n:
		var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
		mtn.summoned_this_turn = false


func _blue_mana(engine: RulesEngine, n: int) -> void:
	for _i in n:
		var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
		isl.summoned_this_turn = false


func _basic(engine: RulesEngine, card_name: String) -> GameObject:
	var obj: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	return obj


func _token_count(engine: RulesEngine) -> int:
	var n := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if obj.is_token:
			n += 1
	return n
