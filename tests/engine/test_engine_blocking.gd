@tool
extends McpTestSuite

## Declaring blockers from the session: the bot's blocking choices, and the bot's
## attack pausing so you can block.

const Fixtures := preload("res://tests/engine/fixtures.gd")
const AiBlocks := preload("res://engine/session/ai_blocks.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_blocking"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


# --- Bot blocking choices ------------------------------------------------------

func test_bot_blocks_when_it_kills_and_survives() -> void:
	var engine := _combat_vs_bot()
	var bear := _attack(engine, "Test Bear")
	var ogre := _bot_creature(engine, "Test Ogre")
	var blocks := AiBlocks.choose(engine, 1)
	assert_eq(blocks.get(bear.object_id, []), [ogre.object_id])


func test_bot_makes_a_free_block() -> void:
	var engine := _combat_vs_bot()
	var ogre := _attack(engine, "Test Ogre")
	var wall := _bot_creature(engine, "Test Wall")
	## A 0/5 wall survives a 3/3, so blocking costs nothing.
	assert_eq(AiBlocks.choose(engine, 1).get(ogre.object_id, []), [wall.object_id])


func test_bot_trades_deathtouch_for_bigger_attacker() -> void:
	var engine := _combat_vs_bot()
	var ogre := _attack(engine, "Test Ogre")
	var viper := _bot_creature(engine, "Test Viper")
	assert_eq(AiBlocks.choose(engine, 1).get(ogre.object_id, []), [viper.object_id])


func test_bot_skips_losing_block_when_safe() -> void:
	var engine := _combat_vs_bot()
	_attack(engine, "Test Trampler")
	_bot_creature(engine, "Test Bear")
	assert_true(AiBlocks.choose(engine, 1).is_empty())


func test_bot_chumps_when_the_hit_is_lethal() -> void:
	var engine := _combat_vs_bot()
	var ogre := _attack(engine, "Test Ogre")
	engine.state.players[1].life = 3
	var bear := _bot_creature(engine, "Test Bear")
	assert_eq(AiBlocks.choose(engine, 1).get(ogre.object_id, []), [bear.object_id])


func test_bot_cannot_block_flyer_with_ground_creature() -> void:
	var engine := _combat_vs_bot()
	_attack(engine, "Test Flyer")
	engine.state.players[1].life = 1
	_bot_creature(engine, "Test Ogre")
	assert_true(AiBlocks.choose(engine, 1).is_empty())


func test_bot_blocks_are_accepted_by_engine() -> void:
	var engine := _combat_vs_bot()
	_attack(engine, "Test Bear")
	_bot_creature(engine, "Test Ogre")
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {blockers = AiBlocks.choose(engine, 1)}
	assert_true(engine.submit(act).ok)
	assert_true((engine.state.combat as CombatState).blocks_declared)


# --- You blocking the bot ------------------------------------------------------

func test_bot_attack_pauses_for_your_blocks() -> void:
	var session := _bot_turn_session()
	var engine := session.engine
	var ogre := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	ogre.summoned_this_turn = false
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.summoned_this_turn = false
	session.ai_take_turn(1)
	assert_true(session.awaiting_blocks)
	assert_eq(engine.state.step, EngineEnums.Step.DECLARE_BLOCKERS)
	assert_true(session.blocks_needed(0))


func test_your_blocks_resolve_and_bot_turn_continues() -> void:
	var session := _bot_turn_session()
	var engine := session.engine
	var ogre := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	ogre.summoned_this_turn = false
	var reacher := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Reacher")
	reacher.summoned_this_turn = false
	var life := engine.state.players[0].life
	session.ai_take_turn(1)
	assert_true(session.awaiting_blocks)
	var r := session.declare_blocks({ogre.object_id: [reacher.object_id]})
	assert_true(r.ok)
	assert_false(session.awaiting_blocks)
	assert_eq(engine.state.players[0].life, life)
	assert_eq(engine.state.active_player_id, 0)


func test_no_pause_when_you_have_no_blockers() -> void:
	var session := _bot_turn_session()
	var engine := session.engine
	var ogre := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	ogre.summoned_this_turn = false
	var life := engine.state.players[0].life
	session.ai_take_turn(1)
	assert_false(session.awaiting_blocks)
	assert_eq(engine.state.players[0].life, life - 3)


func test_declare_blocks_rejects_illegal_menace_block() -> void:
	var session := _bot_turn_session()
	var engine := session.engine
	var brute := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Brute")
	brute.summoned_this_turn = false
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.summoned_this_turn = false
	session.ai_take_turn(1)
	assert_true(session.awaiting_blocks)
	var r := session.declare_blocks({brute.object_id: [bear.object_id]})
	assert_false(r.ok)
	assert_true(session.awaiting_blocks)
	assert_true(session.declare_blocks({}).ok)


# --- Helpers -------------------------------------------------------------------

## You (0) attack the bot (1); positioned at declare blockers with the bot holding priority.
func _combat_vs_bot() -> RulesEngine:
	var engine := Fixtures.empty_engine_1v1()
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.step = EngineEnums.Step.DECLARE_BLOCKERS
	engine.state.combat = CombatState.new()
	(engine.state.combat as CombatState).defending_player_id = 1
	engine.priority.give(engine.state, 1)
	return engine


func _attack(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	obj.tapped = true
	(engine.state.combat as CombatState).attacker_ids.append(obj.object_id)
	return obj


func _bot_creature(engine: RulesEngine, card_name: String) -> GameObject:
	var obj := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, card_name)
	obj.summoned_this_turn = false
	return obj


## The bot's main phase, with a card in each library so draws don't run dry.
func _bot_turn_session() -> GameSession:
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = db
	session.you_seat = 0
	var engine := session.engine
	for pid in 2:
		for _i in 3:
			Fixtures.spawn_named(engine, db, pid, EngineEnums.ZoneId.LIBRARY, "Island")
	engine.state.active_player_id = 1
	engine.priority.give(engine.state, 1)
	return session
