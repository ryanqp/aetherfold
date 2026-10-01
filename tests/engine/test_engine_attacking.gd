@tool
extends McpTestSuite

## Turn structure around combat (CR 506-511), picking attackers, and the bot's attack choices.

const Fixtures := preload("res://tests/engine/fixtures.gd")
const AiBlocks := preload("res://engine/session/ai_blocks.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_attacking"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


# --- Turn structure ------------------------------------------------------------

func test_no_attackers_skips_blockers_and_damage() -> void:
	var engine := _at_declare_attackers()
	Fixtures.both_pass(engine)
	assert_eq(engine.state.step, EngineEnums.Step.END_COMBAT)


func test_with_attackers_goes_to_declare_blockers() -> void:
	var engine := _at_declare_attackers()
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.summoned_this_turn = false
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [bear.object_id]}
	assert_true(engine.submit(act).ok)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.step, EngineEnums.Step.DECLARE_BLOCKERS)


# --- Summoning sickness ----------------------------------------------------------

func test_creature_entering_this_turn_cannot_attack() -> void:
	var engine := _at_declare_attackers()
	var fresh := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	assert_true(fresh.summoned_this_turn)
	assert_false(engine.legal_attacker_ids(0).has(fresh.object_id))
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_ATTACKERS
	act.player_id = 0
	act.extra = {attackers = [fresh.object_id]}
	var r := engine.submit(act)
	assert_false(r.ok)
	assert_eq(r.error, "illegal attacker")


func test_sickness_wears_off_on_your_next_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var fresh := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	engine.turn.start_turn(1)
	assert_true(fresh.summoned_this_turn, "the opponent's turn doesn't count")
	engine.turn.start_turn(0)
	assert_false(fresh.summoned_this_turn)


# --- Choosing attackers from the session -------------------------------------------

func test_attack_with_only_picked_creatures() -> void:
	var session := _your_turn_session()
	var engine := session.engine
	var a := _ready(engine, 0, "Test Bear")
	var b := _ready(engine, 0, "Test Ogre")
	var life := engine.state.players[1].life
	assert_true(session.begin_attack().ok)
	assert_true(session.choosing_attackers)
	assert_true(session.attack_with([b.object_id]).ok)
	assert_false(session.choosing_attackers)
	assert_eq(engine.state.players[1].life, life - 3)
	assert_false(engine.state.objects[a.object_id].tapped)


func test_attack_with_nothing_skips_combat() -> void:
	var session := _your_turn_session()
	var engine := session.engine
	_ready(engine, 0, "Test Bear")
	var life := engine.state.players[1].life
	assert_true(session.begin_attack().ok)
	assert_true(session.attack_with([]).ok)
	assert_eq(engine.state.players[1].life, life)
	assert_ne(engine.state.phase, EngineEnums.Phase.COMBAT)


func test_begin_attack_refuses_when_everything_is_sick() -> void:
	var session := _your_turn_session()
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var r := session.begin_attack()
	assert_false(r.ok)
	assert_false(session.choosing_attackers)


# --- Bot attack choices ------------------------------------------------------------

func test_bot_holds_back_creature_that_would_be_eaten() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := _ready(engine, 1, "Test Bear")
	_ready(engine, 0, "Test Ogre")
	assert_false(AiBlocks.choose_attackers(engine, 1, 0).has(bear.object_id))


func test_bot_attacks_into_open_board() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := _ready(engine, 1, "Test Bear")
	assert_true(AiBlocks.choose_attackers(engine, 1, 0).has(bear.object_id))


func test_bot_flies_over_ground_blockers() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var flyer := _ready(engine, 1, "Test Flyer")
	_ready(engine, 0, "Test Ogre")
	assert_true(AiBlocks.choose_attackers(engine, 1, 0).has(flyer.object_id))


func test_bot_never_picks_a_sick_creature() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var fresh := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	assert_false(AiBlocks.choose_attackers(engine, 1, 0).has(fresh.object_id))


# --- Helpers -------------------------------------------------------------------

func _at_declare_attackers() -> RulesEngine:
	var engine := Fixtures.empty_engine_1v1()
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	engine.priority.give(engine.state, 0)
	return engine


func _ready(engine: RulesEngine, player_id: int, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, player_id, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	return obj


## Your first main phase with priority, cards in both libraries.
func _your_turn_session() -> GameSession:
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = db
	session.you_seat = 0
	session.skip_ai = true
	var engine := session.engine
	for pid in 2:
		for _i in 3:
			Fixtures.spawn_named(engine, db, pid, EngineEnums.ZoneId.LIBRARY, "Island")
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.priority.give(engine.state, 0)
	return session
