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


func test_reveal_land_enters_untapped_only_with_a_matching_card_in_hand() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var land := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Gamefield")
	var moved := engine.state.zones.move(land.object_id, EngineEnums.ZoneId.BATTLEFIELD, 0)
	assert_true(moved.tapped, "no Mountain or Forest in hand: tapped")
	var engine2 := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine2, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var land2 := Fixtures.spawn_named(engine2, db, 0, EngineEnums.ZoneId.HAND, "Test Gamefield")
	var moved2 := engine2.state.zones.move(land2.object_id, EngineEnums.ZoneId.BATTLEFIELD, 0)
	assert_false(moved2.tapped, "revealed a Mountain: untapped")


func test_checkland_and_fastland() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var chk := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Checkland")
	assert_true(engine.state.zones.move(chk.object_id, EngineEnums.ZoneId.BATTLEFIELD, 0).tapped, "no Mountain or Island")
	var fast := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Fastland")
	assert_false(engine.state.zones.move(fast.object_id, EngineEnums.ZoneId.BATTLEFIELD, 0).tapped, "only one other land")


func test_stomp_is_read_with_its_discount() -> void:
	var def := db.definition_for("Test Stomp")
	var spell := def.spell_ability()
	assert_true(spell != null, "spell read")
	assert_eq(spell.targets.size(), 2)
	assert_eq(str(spell.effects[0].kind), "PUT_COUNTER")
	assert_eq(str(spell.effects[1].kind), "FIGHT")
	var found := false
	for a in def.abilities:
		if (a as Ability).static_spec.has("cost_reduction_if_target"):
			found = true
	assert_true(found, "the discount is read")


func test_keyword_db_knows_unimplemented_keywords() -> void:
	assert_eq(str(KeywordDb.lookup("Ward {2}").get("status")), "MISSING")
	assert_true(KeywordDb.line_is_handled("Flying, vigilance"))
	assert_false(KeywordDb.line_is_handled("Ward {1}"))


func test_thriving_land_reads_chosen_color() -> void:
	var def := db.definition_for("Test Thriving")
	var kinds: Array = []
	var chosen_mana := false
	for a in def.abilities:
		var ab := a as Ability
		kinds.append(str(ab.kind))
		if ab.is_mana() and str(ab.effects[0].params.get("mana")) == "{CHOSEN}":
			chosen_mana = true
	assert_true(chosen_mana, "mana of the chosen color is read")
	assert_true(kinds.has("TRIGGERED"), "the color choice is read")


func test_discover_trigger_is_once_per_turn() -> void:
	var ab := _first("Test Discoverer", &"TRIGGERED")
	assert_true(ab != null, "discover trigger read")
	assert_eq(str(ab.trigger.get("scope")), "ANY")
	assert_true(bool(ab.trigger.get("once_per_turn", false)))
	assert_eq(str(ab.effects[0].kind), "DISCOVER")


func test_monarch_and_destroy_either_type() -> void:
	assert_eq(str(_first("Test Monarch", &"TRIGGERED").effects[0].kind), "BECOME_MONARCH")
	var br := _first("Test Breaker", &"ACTIVATED")
	assert_true(br != null, "sacrifice ability read")
	assert_true((br.targets[0].get("query") as Dictionary).has("type_any"))
