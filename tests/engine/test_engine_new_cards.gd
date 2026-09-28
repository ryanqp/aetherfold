@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_new_cards"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_elvish_mystic_adds_green() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var elf := _creature(engine, "Elvish Mystic")
	assert_true(engine.submit(Fixtures.activate_mana(0, elf.object_id, &"elvish_mystic_g")).ok)
	assert_eq(engine.mana.pool(0).g, 1)


func test_fyndhorn_elves_adds_green() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var elf := _creature(engine, "Fyndhorn Elves")
	assert_true(engine.submit(Fixtures.activate_mana(0, elf.object_id, &"fyndhorn_elves_g")).ok)
	assert_eq(engine.mana.pool(0).g, 1)


func test_two_mana_dorks_stack_in_one_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var a := _creature(engine, "Elvish Mystic")
	var b := _creature(engine, "Llanowar Elves")
	assert_true(engine.submit(Fixtures.activate_mana(0, a.object_id, &"elvish_mystic_g")).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, b.object_id, &"llanowar_g")).ok)
	assert_eq(engine.mana.pool(0).g, 2)


func test_flame_slash_kills_piker() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	engine.mana.add(0, ManaCost.parse("{R}"))
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Flame Slash")
	assert_true(_cast_auto(engine, spell).ok)
	var t := Fixtures.choose_targets(0, [piker.object_id])
	t.extra = {auto_pay = true}
	assert_true(engine.submit(t).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1).size(), 1)


func test_lightning_strike_hits_player() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{1}{R}"))
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Lightning Strike")
	assert_true(_cast_auto(engine, spell).ok)
	var t := Fixtures.choose_targets(0, [TargetingManager.encode_player(1)])
	t.extra = {auto_pay = true}
	assert_true(engine.submit(t).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.players[1].life, 37)


func test_tidings_draws_four() -> void:
	var engine := Fixtures.empty_engine_1v1()
	for _i in 4:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Island")
	engine.mana.add(0, ManaCost.parse("{3}{U}"))
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Tidings")
	assert_true(_cast_auto(engine, spell).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size(), 4)


func test_pyretic_ritual_adds_three_red() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{1}{R}"))
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Pyretic Ritual")
	assert_true(_cast_auto(engine, spell).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.mana.pool(0).r, 3)


func test_negate_counters_noncreature_and_not_a_creature() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{R}{1}{U}"))
	var shock := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Shock")
	var negate := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Negate")
	assert_true(_cast_auto(engine, shock).ok)
	var shock_target := Fixtures.choose_targets(0, [TargetingManager.encode_player(1)])
	shock_target.extra = {auto_pay = true}
	assert_true(engine.submit(shock_target).ok)
	var sid: int = (engine.state.stack as MagicStack).top().stack_id
	assert_true(_cast_auto(engine, negate).ok)
	var legal: Array = engine.targeting.legal_ids(engine, engine._cast_queries[0])
	assert_true(legal.has(sid))
	var pick := Fixtures.choose_targets(0, [sid])
	pick.extra = {auto_pay = true}
	assert_true(engine.submit(pick).ok)
	Fixtures.both_pass(engine)
	assert_true((engine.state.stack as MagicStack).is_empty())
	assert_eq(engine.state.players[1].life, 40)


func test_essence_scatter_counters_creature_spell() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{1}{R}{1}{U}"))
	var piker := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Piker")
	var scatter := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Essence Scatter")
	assert_true(_cast_auto(engine, piker).ok)
	var sid: int = (engine.state.stack as MagicStack).top().stack_id
	assert_true(_cast_auto(engine, scatter).ok)
	var legal: Array = engine.targeting.legal_ids(engine, engine._cast_queries[0])
	assert_true(legal.has(sid))
	var pick := Fixtures.choose_targets(0, [sid])
	pick.extra = {auto_pay = true}
	assert_true(engine.submit(pick).ok)
	Fixtures.both_pass(engine)
	assert_true((engine.state.stack as MagicStack).is_empty())
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(bf.size(), 0)


func test_essence_scatter_cannot_target_shock() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{R}{1}{U}"))
	var shock := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Shock")
	var scatter := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Essence Scatter")
	assert_true(_cast_auto(engine, shock).ok)
	var shock_target := Fixtures.choose_targets(0, [TargetingManager.encode_player(1)])
	shock_target.extra = {auto_pay = true}
	assert_true(engine.submit(shock_target).ok)
	var sid: int = (engine.state.stack as MagicStack).top().stack_id
	assert_true(_cast_auto(engine, scatter).ok)
	var legal: Array = engine.targeting.legal_ids(engine, engine._cast_queries[0])
	assert_false(legal.has(sid))


func test_vapor_snag_bounces_and_drains() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	engine.mana.add(0, ManaCost.parse("{U}"))
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Vapor Snag")
	assert_true(_cast_auto(engine, spell).ok)
	var t := Fixtures.choose_targets(0, [piker.object_id])
	t.extra = {auto_pay = true}
	assert_true(engine.submit(t).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.players[1].life, 39)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1)
	assert_eq(hand.size(), 1)
	assert_eq((engine.state.objects[hand.object_ids[0]].definition as CardDefinition).name, "Goblin Piker")


func test_raise_the_alarm_makes_two_soldiers() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.mana.add(0, ManaCost.parse("{1}{W}"))
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Raise the Alarm")
	assert_true(_cast_auto(engine, spell).ok)
	Fixtures.both_pass(engine)
	var soldiers := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if not obj.is_token:
			continue
		var def := obj.definition as CardDefinition
		assert_eq(def.name, "Soldier")
		assert_eq(def.power, "1")
		assert_eq(def.toughness, "1")
		assert_true(def.colors.has("W"))
		soldiers += 1
	assert_eq(soldiers, 2)


func _creature(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	return obj


func _cast_auto(engine: RulesEngine, spell: GameObject) -> SubmitResult:
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	return engine.submit(a)
