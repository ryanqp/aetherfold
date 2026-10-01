@tool
extends McpTestSuite

## Manual draw, the phase tracker, and which cards get the gold "you can play this" border.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_table_ux"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


# --- Manual draw (CR 504.1) ------------------------------------------------------------

func test_your_turn_waits_for_you_to_draw() -> void:
	var session := _session(true)
	var hand_before := session.engine.hand_size(0)
	session.end_you_turn()
	session.pass_until_active(0)
	assert_true(session.draw_waiting())
	assert_eq(session.engine.state.step, EngineEnums.Step.DRAW)
	assert_eq(session.engine.hand_size(0), hand_before, "nothing is given to you automatically")
	assert_true(session.view.you_drew_this_turn == false)


func test_turn_cannot_move_on_until_you_draw() -> void:
	var session := _session(true)
	session.end_you_turn()
	session.pass_until_active(0)
	var r := session.pass_priority(0)
	assert_false(r.ok)
	assert_eq(r.error, "draw your card first")
	assert_false(session.begin_attack().ok)


func test_clicking_the_deck_draws_one_card() -> void:
	var session := _session(true)
	var hand_before := session.engine.hand_size(0)
	var lib_before := session.engine.library_size(0)
	session.end_you_turn()
	session.pass_until_active(0)
	var card := session.ack_draw()
	assert_false(card.is_empty())
	assert_eq(session.engine.hand_size(0), hand_before + 1)
	assert_eq(session.engine.library_size(0), lib_before - 1)
	assert_false(session.draw_waiting())
	assert_true(session.ack_draw().is_empty(), "only one draw per turn")
	session.pass_until_active(0)
	assert_eq(session.engine.state.phase, EngineEnums.Phase.MAIN_1)


func test_draw_is_automatic_unless_manual_draw_is_on() -> void:
	var session := _session(false)
	var hand_before := session.engine.hand_size(0)
	session.end_you_turn()
	session.pass_until_active(0)
	assert_false(session.draw_waiting())
	assert_eq(session.engine.hand_size(0), hand_before + 1)


func test_rival_still_draws_on_its_own() -> void:
	var session := _session(true)
	var rival_before := session.engine.hand_size(1)
	session.end_you_turn()
	assert_eq(session.engine.hand_size(1), rival_before + 1)


# --- Phase tracker ---------------------------------------------------------------------

func test_phase_tracker_follows_the_turn() -> void:
	assert_eq(TableView._track_of(EngineEnums.Phase.UPKEEP), "upkeep")
	assert_eq(TableView._track_of(EngineEnums.Phase.DRAW), "draw")
	assert_eq(TableView._track_of(EngineEnums.Phase.MAIN_1), "main1")
	assert_eq(TableView._track_of(EngineEnums.Phase.COMBAT), "combat")
	assert_eq(TableView._track_of(EngineEnums.Phase.MAIN_2), "main2")
	assert_eq(TableView._track_of(EngineEnums.Phase.ENDING), "end")
	var session := _session(true)
	assert_eq(session.view.turn_track, "main1")
	session.end_you_turn()
	session.pass_until_active(0)
	assert_eq(session.view.turn_track, "draw")


# --- Gold border: what you can play ---------------------------------------------------

func test_land_in_hand_is_playable_with_a_land_drop() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	session.rebuild_view()
	assert_true(_card(session, "hand", "Mountain").get("playable"))


func test_land_is_not_playable_after_the_land_drop() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	session.engine.state.land_played[0] = true
	session.rebuild_view()
	assert_false(_card(session, "hand", "Mountain").get("playable"))


func test_spell_is_playable_only_with_enough_mana() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Piker")
	_mountains(session.engine, 1)
	session.rebuild_view()
	assert_false(_card(session, "hand", "Goblin Piker").get("playable"), "costs 2, only 1 land")
	_mountains(session.engine, 1)
	session.rebuild_view()
	assert_true(_card(session, "hand", "Goblin Piker").get("playable"))


func test_nothing_is_playable_while_you_still_owe_a_draw() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	session.end_you_turn()
	session.pass_until_active(0)
	assert_false(_card(session, "hand", "Mountain").get("playable"))


func test_commander_shows_in_the_command_zone_and_is_castable() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.COMMAND, "Krenko, Mob Boss")
	_mountains(session.engine, 3)
	session.rebuild_view()
	var cmd := _card(session, "command", "Krenko, Mob Boss")
	assert_false(cmd.is_empty(), "the commander is visible")
	assert_false(cmd.get("playable"), "costs 4, only 3 lands")
	_mountains(session.engine, 1)
	session.rebuild_view()
	assert_true(_card(session, "command", "Krenko, Mob Boss").get("playable"))


func test_commander_tax_raises_the_price() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.COMMAND, "Krenko, Mob Boss")
	session.engine.state.players[0].commander_cast_count["krenko_mob_boss"] = 1
	var tax: int = session.engine.state.rules.commander_tax_step
	_mountains(session.engine, 4)
	session.rebuild_view()
	var cmd := _card(session, "command", "Krenko, Mob Boss")
	assert_eq(cmd.get("commander_tax"), tax)
	assert_false(cmd.get("playable"), "4 lands is not enough once the tax is added")
	_mountains(session.engine, tax)
	session.rebuild_view()
	assert_true(_card(session, "command", "Krenko, Mob Boss").get("playable"))


func test_commander_can_actually_be_cast_from_the_zone() -> void:
	var session := _session(true)
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.COMMAND, "Krenko, Mob Boss")
	_mountains(session.engine, 4)
	session.rebuild_view()
	var cmd := _card(session, "command", "Krenko, Mob Boss")
	assert_true(session.cast_auto(0, int(str(cmd.get("id")))).ok)


# --- Helpers ---------------------------------------------------------------------------

## Your first main phase with priority, cards in both libraries, mid-game.
func _session(manual: bool) -> GameSession:
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = db
	session.you_seat = 0
	session.skip_ai = true
	session.manual_draw = manual
	var engine := session.engine
	engine.manual_draw_seats = [0] if manual else []
	for pid in 2:
		for _i in 6:
			Fixtures.spawn_named(engine, db, pid, EngineEnums.ZoneId.LIBRARY, "Island")
	engine.state.turn_number = 2
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.priority.give(engine.state, 0)
	session.rebuild_view()
	return session


func _mountains(engine: RulesEngine, n: int) -> void:
	for _i in n:
		var mtn := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
		mtn.summoned_this_turn = false


func _card(session: GameSession, zone: String, card_name: String) -> Dictionary:
	for card in session.view.you.get(zone, []):
		if str(card.get("name", "")) == card_name:
			return card
	return {}
