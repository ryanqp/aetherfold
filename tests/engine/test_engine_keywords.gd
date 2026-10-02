@tool
extends McpTestSuite

## Evergreen combat keywords and creature state-based actions.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_keywords"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


# --- Blocking restrictions ---------------------------------------------------

func test_flying_cannot_be_blocked_by_ground_creature() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var flyer := _attacker(engine, "Test Flyer")
	var bear := _blocker(engine, "Test Bear")
	var r := _block(engine, {flyer.object_id: [bear.object_id]})
	assert_false(r.ok)
	assert_eq(r.error, "illegal blocker")


func test_flying_can_be_blocked_by_reach_or_flying() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var flyer := _attacker(engine, "Test Flyer")
	var reacher := _blocker(engine, "Test Reacher")
	assert_true(_block(engine, {flyer.object_id: [reacher.object_id]}).ok)
	var engine2 := Fixtures.empty_engine_1v1()
	var flyer2 := _attacker(engine2, "Test Flyer")
	var other := _blocker(engine2, "Test Flyer")
	assert_true(_block(engine2, {flyer2.object_id: [other.object_id]}).ok)


func test_menace_rejects_single_blocker() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var brute := _attacker(engine, "Test Brute")
	var bear := _blocker(engine, "Test Bear")
	var r := _block(engine, {brute.object_id: [bear.object_id]})
	assert_false(r.ok)
	assert_eq(r.error, "menace needs two blockers")


func test_menace_allows_two_blockers() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var brute := _attacker(engine, "Test Brute")
	var a := _blocker(engine, "Test Bear")
	var b := _blocker(engine, "Test Bear")
	assert_true(_block(engine, {brute.object_id: [a.object_id, b.object_id]}).ok)


# --- Attacking restrictions --------------------------------------------------

func test_defender_cannot_attack() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var wall := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Wall")
	wall.summoned_this_turn = false
	assert_false(engine.legal_attacker_ids(0).has(wall.object_id))


func test_vigilance_does_not_tap() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var watcher := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Watcher")
	watcher.summoned_this_turn = false
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.awaiting = {player_id = 0}
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [watcher.object_id]}
	assert_true(engine.submit(act).ok)
	assert_false(engine.state.objects[watcher.object_id].tapped)


# --- Combat damage -------------------------------------------------------------

func test_trample_sends_excess_to_player() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var trampler := _attacker(engine, "Test Trampler")
	var bear := _blocker(engine, "Test Bear")
	var life := engine.state.players[1].life
	assert_true(_block(engine, {trampler.object_id: [bear.object_id]}).ok)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, life - 3)
	assert_false(_alive(engine, bear))


func test_blocked_without_trample_deals_no_player_damage() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ogre := _attacker(engine, "Test Ogre")
	var bear := _blocker(engine, "Test Bear")
	var life := engine.state.players[1].life
	assert_true(_block(engine, {ogre.object_id: [bear.object_id]}).ok)
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, life)


func test_deathtouch_kills_bigger_blocker() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var viper := _attacker(engine, "Test Viper")
	var ogre := _blocker(engine, "Test Ogre")
	assert_true(_block(engine, {viper.object_id: [ogre.object_id]}).ok)
	engine.apply_combat_damage()
	assert_false(_alive(engine, ogre))
	assert_false(_alive(engine, viper))


func test_lifelink_gains_life() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var healer := _attacker(engine, "Test Healer")
	var mine := engine.state.players[0].life
	var theirs := engine.state.players[1].life
	engine.apply_combat_damage()
	assert_eq(engine.state.players[0].life, mine + 3)
	assert_eq(engine.state.players[1].life, theirs - 3)
	assert_true(_alive(engine, healer))


func test_first_strike_kills_before_damage_back() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var duelist := _attacker(engine, "Test Duelist")
	var bear := _blocker(engine, "Test Bear")
	assert_true(_block(engine, {duelist.object_id: [bear.object_id]}).ok)
	engine.apply_combat_damage()
	assert_false(_alive(engine, bear))
	assert_true(_alive(engine, duelist))


func test_double_strike_hits_twice() -> void:
	var engine := Fixtures.empty_engine_1v1()
	_attacker(engine, "Test Champion")
	var life := engine.state.players[1].life
	engine.apply_combat_damage()
	assert_eq(engine.state.players[1].life, life - 4)


func test_damage_split_across_two_blockers() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ogre := _attacker(engine, "Test Ogre")
	var first := _blocker(engine, "Test Bear")
	var second := _blocker(engine, "Test Bear")
	assert_true(_block(engine, {ogre.object_id: [first.object_id, second.object_id]}).ok)
	engine.apply_combat_damage()
	assert_false(_alive(engine, first))
	assert_true(_alive(engine, second))
	assert_false(_alive(engine, ogre))


# --- State-based actions -------------------------------------------------------

func test_indestructible_survives_lethal_damage() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var stalwart := _attacker(engine, "Test Stalwart")
	var ogre := _blocker(engine, "Test Ogre")
	assert_true(_block(engine, {stalwart.object_id: [ogre.object_id]}).ok)
	engine.apply_combat_damage()
	assert_true(_alive(engine, stalwart))


func test_star_toughness_creature_is_not_killed() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var shapeless := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Shapeless")
	engine.sba.check(engine)
	assert_true(_alive(engine, shapeless))


func test_damage_wears_off_in_cleanup() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ogre := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	ogre.damage_marked = 2
	ogre.deathtouch_damage = true
	engine.turn._clear_damage(engine.state)
	assert_eq(ogre.damage_marked, 0)
	assert_false(ogre.deathtouch_damage)


# --- Helpers -------------------------------------------------------------------

func _attacker(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	obj.tapped = true
	if not (engine.state.combat is CombatState):
		engine.state.combat = CombatState.new()
	(engine.state.combat as CombatState).attacker_ids.append(obj.object_id)
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_BLOCKERS
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.priority.give(engine.state, 1)
	return obj


func _blocker(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	obj.tapped = false
	return obj


func _block(engine: RulesEngine, blocks: Dictionary) -> SubmitResult:
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {blockers = blocks}
	return engine.submit(act)


## Zone changes retire object ids (CR 400.7), so a living object keeps its id on the battlefield.
func _alive(engine: RulesEngine, obj: GameObject) -> bool:
	var cur: GameObject = engine.state.objects.get(obj.object_id)
	return cur != null and cur.zone == EngineEnums.ZoneId.BATTLEFIELD
