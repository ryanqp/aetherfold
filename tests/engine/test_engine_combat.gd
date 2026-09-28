@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_combat"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_sickness_cannot_attack() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	assert_eq(engine._legal_attacker_ids(0).size(), 0)


func test_unblocked_damage() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	piker.summoned_this_turn = false
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [piker.object_id]}
	assert_true(engine.submit(act).ok)
	assert_true(engine.state.objects[piker.object_id].tapped)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, 38)


func test_declare_attackers_uses_chosen_defender() -> void:
	var engine := Fixtures.empty_engine_4p()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	piker.summoned_this_turn = false
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.awaiting = {player_id = 0}
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [piker.object_id], defending_player_id = 2}
	assert_true(engine.submit(act).ok)
	engine.apply_combat_damage()
	assert_eq((engine.state.combat as CombatState).defending_player_id, 2)
	assert_eq(engine.state.players[1].life, 40)
	assert_eq(engine.state.players[2].life, 38)
	assert_eq(engine.state.players[3].life, 40)


func test_declare_attackers_rejects_illegal_defender() -> void:
	var engine := Fixtures.empty_engine_4p()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	piker.summoned_this_turn = false
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.awaiting = {player_id = 0}
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [piker.object_id], defending_player_id = 0}
	assert_true(engine.submit(act).ok)
	engine.apply_combat_damage()
	assert_eq((engine.state.combat as CombatState).defending_player_id, 1)


func test_default_defender_skips_eliminated_player() -> void:
	var engine := Fixtures.empty_engine_4p()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	piker.summoned_this_turn = false
	engine.state.players[1].lost = true
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.awaiting = {player_id = 0}
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [piker.object_id]}
	assert_true(engine.submit(act).ok)
	engine.apply_combat_damage()
	assert_eq((engine.state.combat as CombatState).defending_player_id, 2)


func test_commander_damage_tally() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	krenko.is_commander = true
	krenko.summoned_this_turn = false
	engine.state.combat = CombatState.new()
	(engine.state.combat as CombatState).attacker_ids = [krenko.object_id]
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, 37)
	assert_eq(engine.state.players[1].commander_damage_from.size(), 1)
