@tool
extends McpTestSuite

## Keywords found missing when the engine was cross-checked against the Comprehensive Rules (20260925):
## wither (CR 702.80), undaunted (CR 702.125) and living metal (CR 702.161).

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_keyword_audit"


func _row(name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "", kws: Array = []) -> Dictionary:
	return {name = name, oracle_id = name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = kws, power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var cat: CatalogSource = Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Wither", "{1}{B}", 2, "Creature — Test", "Wither", "2", "2", ["Wither"]))
	m.add(_row("Test Undaunted", "{3}{U}", 4, "Sorcery", "Undaunted", "", "", ["Undaunted"]))
	m.add(_row("Test Living Metal", "{3}", 3, "Artifact — Vehicle", "Living metal\nCrew 2", "3", "3", ["Living metal", "Crew"]))
	m.add(_row("Test Target", "{1}", 1, "Creature — Test", "", "3", "3"))
	m.add(_row("Test Bridge", "", 0, "Land", "{T}: Add {G}.\n{G}, {T}: You gain 1 life.", "", ""))
	m.add(_row("Test Forest", "", 0, "Basic Land — Forest", "({T}: Add {G}.)", "", ""))
	db = CardDatabase.new()
	db.setup(cat)


func test_wither_damage_is_minus_counters() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var w: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Wither")
	var t: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Target")
	engine._mark_damage(w, t, 2)
	assert_eq(int(t.counters.get("-1/-1", 0)), 2)
	assert_eq(t.damage_marked, 0)
	assert_eq(engine.power_of(t), 1)


func test_undaunted_costs_one_less_per_opponent() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var s: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Undaunted")
	assert_eq(engine.effective_cost(0, s).generic, 2)


func test_living_metal_is_a_creature_only_on_its_controllers_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var v: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Living Metal")
	engine.state.active_player_id = 0
	assert_true(engine.is_creature_now(v))
	engine.state.active_player_id = 1
	assert_false(engine.is_creature_now(v))


## "You may play it this turn" cards exiled by impulse draw: they must be castable / playable from the exile pile.
func test_impulse_exiled_spell_has_a_cast_option() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var c: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.EXILE, "Test Target")
	assert_true(engine.kw.cast_options(0, c).is_empty(), "nothing while it is just exiled")
	c.may_play_controller = 0
	var opts: Array = engine.kw.cast_options(0, c)
	assert_eq(opts.size(), 1, "one way to cast it from exile")


func test_impulse_exiled_land_can_be_played() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var land: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.EXILE, "Mountain")
	var found := false
	for a in engine.legal_actions(0):
		if (a as GameAction).kind == GameAction.Kind.PLAY_LAND and (a as GameAction).object_id == land.object_id:
			found = true
	assert_false(found, "not while it is only exiled")
	land.may_play_controller = 0
	for a in engine.legal_actions(0):
		if (a as GameAction).kind == GameAction.Kind.PLAY_LAND and (a as GameAction).object_id == land.object_id:
			found = true
	assert_true(found, "playable once it may be played")


## A "{G}, {T}" ability must not tap its own permanent for the {G} (Mosswort Bridge): that left the {T} unpayable.
func _bridge_ability(engine: RulesEngine, bridge: GameObject) -> Ability:
	for a in engine._active_abilities(bridge):
		if (a as Ability).is_activated():
			return a
	return null


func test_tap_ability_is_not_paid_with_its_own_mana() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bridge: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bridge")
	bridge.summoned_this_turn = false
	var forest: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Forest")
	forest.summoned_this_turn = false
	var ab := _bridge_ability(engine, bridge)
	assert_true(ab != null, "the {G}, {T} ability was read")
	var act := Fixtures.activate_ability(0, bridge.object_id, ab.ability_id)
	act.extra = {"auto_pay": true}
	var r := engine.submit(act)
	assert_true(r.ok, "paid with the Forest, not with the Bridge itself: %s" % r.error)
	assert_true(bridge.tapped, "the Bridge paid its {T} cost")
	assert_true(forest.tapped, "the Forest made the {G}")


func test_tap_ability_with_no_other_mana_fails_cleanly() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bridge: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bridge")
	bridge.summoned_this_turn = false
	var ab := _bridge_ability(engine, bridge)
	var act := Fixtures.activate_ability(0, bridge.object_id, ab.ability_id)
	act.extra = {"auto_pay": true}
	var r := engine.submit(act)
	assert_false(r.ok, "no other green source: can't pay")
	assert_false(bridge.tapped, "and the Bridge was not tapped for mana on the way")
