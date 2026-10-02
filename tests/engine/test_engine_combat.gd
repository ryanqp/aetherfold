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


func test_blocker_absorbs_damage() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _ready_attacker(engine, "Goblin Piker")
	var krenko := _ready_blocker(engine, "Krenko, Mob Boss")
	assert_true(_declare_block(engine, piker, krenko).ok)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, 40)
	assert_false(_on_battlefield(engine, "Goblin Piker"))
	assert_true(_on_battlefield(engine, "Krenko, Mob Boss"))
	assert_true(_in_graveyard(engine, 0, "Goblin Piker"))


func test_blocker_dies_to_lethal() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko := _ready_attacker(engine, "Krenko, Mob Boss")
	var piker := _ready_blocker(engine, "Goblin Piker")
	assert_true(_declare_block(engine, krenko, piker).ok)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, 40)
	assert_true(_on_battlefield(engine, "Krenko, Mob Boss"))
	assert_false(_on_battlefield(engine, "Goblin Piker"))
	assert_true(_in_graveyard(engine, 1, "Goblin Piker"))


func test_unblocked_attacker_still_hits_player() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var blocked := _ready_attacker(engine, "Goblin Piker")
	var open := _ready_attacker(engine, "Goblin Piker")
	var wall := _ready_blocker(engine, "Krenko, Mob Boss")
	var cs := engine.state.combat as CombatState
	cs.attacker_ids = [blocked.object_id, open.object_id]
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {blockers = {blocked.object_id: [wall.object_id]}}
	assert_true(engine.submit(act).ok)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, 38)
	assert_true(_on_battlefield(engine, "Krenko, Mob Boss"))


func test_tapped_creature_cannot_block() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _ready_attacker(engine, "Goblin Piker")
	var krenko := _ready_blocker(engine, "Krenko, Mob Boss")
	krenko.tapped = true
	var r := _declare_block(engine, piker, krenko)
	assert_false(r.ok)
	assert_eq(r.error, "illegal blocker")


func test_two_blockers_on_one_attacker_allowed() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _ready_attacker(engine, "Goblin Piker")
	var a := _ready_blocker(engine, "Goblin Piker")
	var b := _ready_blocker(engine, "Krenko, Mob Boss")
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {blockers = {piker.object_id: [a.object_id, b.object_id]}}
	assert_true(engine.submit(act).ok)


func test_one_creature_cannot_block_two_attackers() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var first := _ready_attacker(engine, "Goblin Piker")
	var second := _ready_attacker(engine, "Goblin Piker")
	var wall := _ready_blocker(engine, "Krenko, Mob Boss")
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {blockers = {first.object_id: [wall.object_id], second.object_id: [wall.object_id]}}
	var r := engine.submit(act)
	assert_false(r.ok)
	assert_eq(r.error, "blocker already assigned")


func test_two_attackers_hit_two_defenders() -> void:
	var engine := Fixtures.empty_engine_4p()
	var a := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	var b := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	a.summoned_this_turn = false
	b.summoned_this_turn = false
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.awaiting = {player_id = 0}
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {
		attackers = [a.object_id, b.object_id],
		defenders = {a.object_id: 2, b.object_id: 3},
	}
	assert_true(engine.submit(act).ok)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, 40)
	assert_eq(engine.state.players[2].life, 38)
	assert_eq(engine.state.players[3].life, 38)


func _ready_attacker(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	obj.tapped = true
	if not (engine.state.combat is CombatState):
		engine.state.combat = CombatState.new()
	var cs := engine.state.combat as CombatState
	cs.attacker_ids.append(obj.object_id)
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_BLOCKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.priority.give(engine.state, 1)
	return obj


func _ready_blocker(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	obj.tapped = false
	return obj


func _declare_block(engine: RulesEngine, attacker: GameObject, blocker: GameObject) -> SubmitResult:
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {blockers = {attacker.object_id: [blocker.object_id]}}
	return engine.submit(act)


func _on_battlefield(engine: RulesEngine, card_name: String) -> bool:
	return _zone_has(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, card_name)


func _in_graveyard(engine: RulesEngine, player_id: int, card_name: String) -> bool:
	return _zone_has(engine, EngineEnums.ZoneId.GRAVEYARD, player_id, card_name)


func _zone_has(engine: RulesEngine, zone_id: int, player_id: int, card_name: String) -> bool:
	var zone: Zone = engine.state.zones.get_zone(zone_id, player_id)
	if zone == null:
		return false
	for oid in zone.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		if obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).name == card_name:
			return true
	return false
