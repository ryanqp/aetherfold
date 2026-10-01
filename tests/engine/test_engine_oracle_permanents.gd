@tool
extends McpTestSuite

## Permanent abilities (triggers, statics, equipment, tokens) read from Oracle text by OracleIr.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_oracle_permanents"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func _first(card_name: String, kind: StringName) -> Ability:
	for a in db.definition_for(card_name).abilities:
		if (a as Ability).kind == kind:
			return a
	return null


func test_etb_token_is_read() -> void:
	var ab := _first("Test Egg Layer", &"TRIGGERED")
	assert_true(ab != null, "ETB trigger read")
	assert_eq(str(ab.trigger.get("on")), "ENTERS_BATTLEFIELD")
	assert_eq(str(ab.effects[0].kind), "CREATE_TOKEN")


func test_attack_trigger_puts_counter() -> void:
	var ab := _first("Test Gorger", &"TRIGGERED")
	assert_true(ab != null)
	assert_eq(str(ab.trigger.get("on")), "ATTACKS")
	assert_eq(str(ab.effects[0].kind), "PUT_COUNTER")


func test_upkeep_treasure() -> void:
	var ab := _first("Test Treasurer", &"TRIGGERED")
	assert_true(ab != null)
	assert_eq(str(ab.trigger.get("on")), "BEGIN_STEP")
	assert_eq(str(ab.trigger.get("step")), "UPKEEP")


func test_dies_trigger_gains_life() -> void:
	var ab := _first("Test Mourner", &"TRIGGERED")
	assert_true(ab != null)
	assert_eq(str(ab.trigger.get("on")), "DIES")
	assert_eq(str(ab.effects[0].kind), "GAIN_LIFE")


func test_equipment_reads_static_and_equip() -> void:
	assert_true(_first("Test Blade", &"STATIC") != null, "static boost")
	var eq := _first("Test Blade", &"ACTIVATED")
	assert_true(eq != null, "equip ability")
	assert_eq(str(eq.effects[0].kind), "ATTACH")


func test_search_and_fight_spells_are_read() -> void:
	assert_eq(str(_first("Test Fetch", &"SPELL").effects[0].kind), "SEARCH_LIBRARY")
	var rend := _first("Test Rend", &"SPELL")
	assert_eq(rend.targets.size(), 2)
	assert_eq(str(rend.effects[0].kind), "FIGHT")


func test_lord_boosts_other_dinosaurs_only() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var lord := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Raptor Lord")
	var other := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Egg Layer")
	assert_eq(engine.power_of(lord), 1, "the lord doesn't boost itself")
	assert_eq(engine.power_of(other), 2, "another Dinosaur gets +1/+1")


func test_unread_lines_shrink_when_read() -> void:
	assert_true(db.unread_lines(db.definition_for("Test Egg Layer")).is_empty(), "everything on it is read")
	assert_eq(db.unread_lines(db.definition_for("Test Unsure")).size(), 2, "a half understood spell lists both lines")
