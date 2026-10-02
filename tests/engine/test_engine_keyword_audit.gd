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
