@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_commander"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_commander_can_go_to_command_zone() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	krenko.is_commander = true
	var old_id := krenko.object_id
	var moved: GameObject = engine.state.zones.move(old_id, EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(moved, null)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.CHOOSING_REPLACEMENT)
	var act := GameAction.new()
	act.kind = GameAction.Kind.CHOOSE_REPLACEMENT
	act.player_id = 0
	act.extra = {dest_zone = EngineEnums.ZoneId.COMMAND}
	assert_true(engine.submit(act).ok)
	var cz: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, 0)
	assert_eq(cz.size(), 1)
	var now: GameObject = engine.state.objects[cz.object_ids[0]]
	assert_true(now.is_commander)
	assert_eq(now.linked_from, old_id)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 0)


func test_commander_tax_increases() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var k1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.COMMAND, "Krenko, Mob Boss")
	k1.is_commander = true
	engine.state.players[0].commander_cast_count["krenko_mob_boss"] = 1
	assert_true(engine.submit(Fixtures.cast_spell(0, k1.object_id)).ok)
	assert_eq(engine._payment.generic, 4)
	assert_eq(engine._payment.r, 2)


## CR 903.10a: 21 combat damage from one commander loses the game even at high life.
func test_21_commander_damage_loses_the_game() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.state.players[1].life = 100
	engine.state.players[1].commander_damage_from["0:Krenko, Mob Boss"] = 18
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	krenko.is_commander = true
	krenko.summoned_this_turn = false
	engine.state.combat = CombatState.new()
	(engine.state.combat as CombatState).attacker_ids = [krenko.object_id]
	engine.apply_combat_damage()
	engine.sba.check(engine)
	assert_eq(engine.state.players[1].commander_damage_from["0:Krenko, Mob Boss"], 21)
	assert_true(engine.state.players[1].life > 0)
	assert_true(engine.state.players[1].lost)
	assert_true(engine.is_over())
	assert_eq(engine.state.winners, [0])


func test_20_commander_damage_is_not_enough() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.state.players[1].commander_damage_from["0:Krenko, Mob Boss"] = 20
	engine.sba.check(engine)
	assert_false(engine.state.players[1].lost)
	assert_false(engine.is_over())


func test_non_commander_damage_is_not_tallied() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	krenko.summoned_this_turn = false
	engine.state.combat = CombatState.new()
	(engine.state.combat as CombatState).attacker_ids = [krenko.object_id]
	engine.apply_combat_damage()
	assert_true(engine.state.players[1].commander_damage_from.is_empty())


func test_table_view_reports_commander_damage_and_reason() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.state.players[1].life = 100
	engine.state.players[1].commander_damage_from["0:Krenko, Mob Boss"] = 21
	engine.sba.check(engine)
	var view := TableView.from_engine(engine, null)
	assert_eq(view.rival.cmdr_need, 21)
	assert_eq(view.rival.cmdr_damage.size(), 1)
	assert_eq(int(view.rival.cmdr_damage[0].amount), 21)
	assert_true(str(view.rival.lose_reason).contains("commander damage"))
	assert_true(view.game_over)
