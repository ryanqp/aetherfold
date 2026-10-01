@tool
extends McpTestSuite

## Spells with no hand-written IR, read straight from Oracle text by OracleIr.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_oracle_ir"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


# --- Reading -------------------------------------------------------------------

func test_reads_damage_spell() -> void:
	var abilities := db.definition_for("Test Smite").abilities
	assert_eq(abilities.size(), 1)
	var ab := abilities[0] as Ability
	assert_eq(str(ab.kind), "SPELL")
	assert_eq(str(ab.ability_id), "test_smite_spell")
	assert_eq(ab.targets.size(), 1)
	assert_eq(str(ab.targets[0].get("kind")), "PERMANENT")
	assert_eq(str(ab.effects[0].kind), "DEAL_DAMAGE")
	assert_eq(int(ab.effects[0].params.get("n")), 4)


func test_reminder_text_is_ignored() -> void:
	var ab := db.definition_for("Test Study").abilities[0] as Ability
	assert_eq(str(ab.effects[0].kind), "DRAW")
	assert_eq(int(ab.effects[0].params.get("n")), 2)


func test_unknown_text_stays_unimplemented() -> void:
	assert_true(db.definition_for("Test Mystery").abilities.is_empty())


func test_half_understood_card_is_left_alone() -> void:
	## "Scry 2." is not understood, so the damage sentence must not run alone.
	assert_true(db.definition_for("Test Unsure").abilities.is_empty())


func test_hand_written_ir_wins() -> void:
	var ab := db.definition_for("Lightning Bolt").abilities[0] as Ability
	assert_eq(str(ab.ability_id), "lightning_bolt")


func test_creatures_are_not_read() -> void:
	assert_true(db.definition_for("Test Bear").abilities.is_empty())


# --- Activated abilities on permanents ------------------------------------------------

func test_reads_activated_ping() -> void:
	var def := db.definition_for("Test Pinger")
	assert_eq(def.abilities.size(), 1)
	var ab := def.abilities[0] as Ability
	assert_true(ab.is_activated())
	assert_true(ab.has_tap_cost())
	assert_eq(ab.targets.size(), 1)
	assert_eq(str(ab.effects[0].kind), "DEAL_DAMAGE")
	assert_eq(int(ab.effects[0].params.get("n")), 1)


func test_ping_can_only_target_the_opponent() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var pinger := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Pinger")
	var ab := db.definition_for("Test Pinger").abilities[0] as Ability
	var ids: Array = engine.targeting.legal_ids(engine, ab.targets[0], pinger.object_id)
	assert_eq(ids.size(), 1)
	assert_eq(TargetingManager.decode_player(int(ids[0])), 1)


# --- Enters-the-battlefield triggers ---------------------------------------------------

func test_reads_enters_trigger() -> void:
	var ab := db.definition_for("Test Greeter").abilities[0] as Ability
	assert_eq(str(ab.kind), "TRIGGERED")
	assert_eq(str(ab.trigger.get("on")), "ENTERS_BATTLEFIELD")
	assert_eq(str(ab.effects[0].kind), "GAIN_LIFE")


func test_enters_trigger_resolves() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var life := engine.state.players[0].life
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Greeter")
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 1)
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, life + 3)


func test_exile_until_leaves_returns_the_card() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ogre := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	var warden := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Warden")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1).size(), 1)
	engine.state.zones.move(warden.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	engine.process_zone_events()
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1).size(), 0)
	assert_false(ogre == null)


# --- Playing them ------------------------------------------------------------------

func test_smite_kills_ogre_but_not_wall() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ogre := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	var wall := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Wall")
	_cast(engine, "Test Smite", ogre.object_id)
	assert_ne(engine.state.objects[ogre.object_id].zone, EngineEnums.ZoneId.BATTLEFIELD)
	_cast(engine, "Test Smite", wall.object_id)
	assert_eq(engine.state.objects[wall.object_id].zone, EngineEnums.ZoneId.BATTLEFIELD)


func test_destroy_kills_but_indestructible_survives() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var rock := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Stalwart")
	_cast(engine, "Test Doom", bear.object_id)
	_cast(engine, "Test Doom", rock.object_id)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1).size(), 1)
	assert_eq(engine.state.objects[rock.object_id].zone, EngineEnums.ZoneId.BATTLEFIELD)


func test_exile_ignores_indestructible() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var rock := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Stalwart")
	_cast(engine, "Test Banish", rock.object_id)
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1).size(), 1)


func test_pump_changes_power_and_toughness() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_cast(engine, "Test Growth", bear.object_id)
	assert_eq(engine.power_of(bear), 5)
	assert_eq(engine.toughness_of(bear), 5)


func test_pump_grants_keyword() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	assert_false(engine.has_keyword(bear, "First strike"))
	_cast(engine, "Test Bundle", bear.object_id)
	assert_true(engine.has_keyword(bear, "First strike"))
	assert_eq(engine.power_of(bear), 4)


func test_shrink_kills_through_state_based_actions() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ogre := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	_cast(engine, "Test Shrink", ogre.object_id)
	assert_ne(engine.state.objects[ogre.object_id].zone, EngineEnums.ZoneId.BATTLEFIELD)


func test_pump_wears_off_at_end_of_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_cast(engine, "Test Growth", bear.object_id)
	engine.layers.clear_until_eot(engine.state)
	assert_eq(engine.power_of(bear), 2)


func test_gain_life() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var life := engine.state.players[0].life
	_cast(engine, "Test Mend", -1)
	assert_eq(engine.state.players[0].life, life + 4)


func test_draw_two() -> void:
	var engine := Fixtures.empty_engine_1v1()
	for _i in 3:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Island")
	var hand_before := engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size()
	_cast(engine, "Test Study", -1)
	## The spell leaves the hand when cast, then two cards arrive.
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size(), hand_before + 2)


# --- Mana abilities --------------------------------------------------------------------

func test_arcane_signet_is_read_as_commander_identity_mana() -> void:
	var abilities := _mana_of("Arcane Signet")
	assert_eq(abilities.size(), 1)
	assert_eq((abilities[0] as Ability).kind, &"MANA")
	assert_eq(str(((abilities[0] as Ability).effects[0] as AbilityEffect).params.get("mana")), "{CI}")


func test_two_type_land_gets_both_basic_abilities() -> void:
	assert_eq(_mana_of("Test Duo Land").size(), 2)


func test_pain_land_keeps_the_plain_mana_and_skips_the_damage_one() -> void:
	var abilities := _mana_of("Test Painland")
	assert_eq(abilities.size(), 1)
	assert_eq(str(((abilities[0] as Ability).effects[0] as AbilityEffect).params.get("mana")), "{C}")


func test_mana_text_forms() -> void:
	assert_eq(OracleIr._mana_text("{R} or {G}."), "{R|G}")
	assert_eq(OracleIr._mana_text("{W}, {U}, or {B}"), "{W|U|B}")
	assert_eq(OracleIr._mana_text("{C}{C}"), "{C}{C}")
	assert_eq(OracleIr._mana_text("one mana of any color"), "{W|U|B|R|G}")
	assert_eq(OracleIr._mana_text("{R}. Test deals 1 damage to you"), "")


func test_unread_lines_are_reported() -> void:
	var def := db.definition_for("Arcane Signet")
	assert_true(db.unread_lines(def).is_empty(), "fully read")
	var odd := db.definition_for("Test Painland")
	assert_eq(db.unread_lines(odd).size(), 1, "the pain ability isn't coded")


# --- Helpers -------------------------------------------------------------------------

## Casts `card_name` for player 0 with a Mountain to pay, choosing `target_id` when it needs one.
func _cast(engine: RulesEngine, card_name: String, target_id: int) -> void:
	var mtn := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.summoned_this_turn = false
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, card_name)
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = spell.object_id
	a.extra = {auto_pay = true}
	assert_true(engine.submit(a).ok, "cast " + card_name)
	if target_id >= 0:
		var t := Fixtures.choose_targets(0, [target_id])
		t.extra = {auto_pay = true}
		assert_true(engine.submit(t).ok, "target for " + card_name)
	Fixtures.both_pass(engine)


func _mana_of(card_name: String) -> Array:
	var out: Array = []
	for a in db.definition_for(card_name).abilities:
		if (a as Ability).is_mana():
			out.append(a)
	return out
