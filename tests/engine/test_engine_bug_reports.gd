@tool
extends McpTestSuite

## Problems players reported with the in-game Bug button, each pinned down with the real card text from the shipped catalog.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_bug_reports"


func suite_setup(_ctx: Dictionary) -> void:
	var want := ["Temple of the False God", "Lifecrafter's Bestiary", "Myr Superion", "Forest", "Island", "Mountain", "Plains", "Grizzly Bears", "Pantlaza, Sun-Favored", "Llanowar Elves"]
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	var f := FileAccess.open("res://data/scryfall/catalog.jsonl", FileAccess.READ)
	var seen := {}
	while f != null and not f.eof_reached():
		var raw := f.get_line().strip_edges()
		if raw == "":
			continue
		var r: Variant = JSON.parse_string(raw)
		if r is Dictionary and want.has(str((r as Dictionary).get("name", ""))) and not seen.has(str(r["name"])):
			seen[str(r["name"])] = true
			m.add(r)
	db = CardDatabase.new()
	db.setup(m)


func _mana_total(engine: RulesEngine, pid: int) -> int:
	return (engine.state.players[pid].mana as ManaPool).total()


func test_temple_of_the_false_god_makes_two_with_five_lands_and_nothing_with_four() -> void:
	for pair in [[4, 0], [5, 2]]:
		var engine := Fixtures.empty_engine_1v1()
		var temple := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Temple of the False God")
		temple.summoned_this_turn = false
		for _i in int(pair[0]) - 1:
			Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Forest")
		var r := engine.submit(Fixtures.activate_mana(0, temple.object_id))
		assert_eq(_mana_total(engine, 0), int(pair[1]), "%d lands: ok=%s err=%s abilities=%s" % [int(pair[0]), r.ok, r.error, str(temple.definition.abilities.map(func(a): return str(a.kind) + str(a.restrictions)))])


var _seen_decisions := 0
var _last_prompt := ""


func _untapped_lands(engine: RulesEngine) -> int:
	var n := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects[oid]
		if (o.definition as CardDefinition).name == "Forest" and not o.tapped:
			n += 1
	return n


func _answer_all(engine: RulesEngine, answers: Dictionary) -> void:
	var guard := 0
	while guard < 40:
		guard += 1
		engine.process_zone_events()
		if engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION and engine.state.pending_decision is PlayerDecision:
			var dec := engine.state.pending_decision as PlayerDecision
			_seen_decisions += 1
			_last_prompt = dec.prompt
			var a := GameAction.new()
			a.player_id = dec.player_id
			var v: Variant = answers.get(dec.link, true)
			a.kind = GameAction.Kind.SUBMIT_DECISION if (v == true or v == null and false) else GameAction.Kind.DECLINE_DECISION
			engine.submit(a)
			continue
		if (engine.state.stack as MagicStack).size() > 0:
			engine.resolve_top()
			continue
		break


func test_lifecrafters_bestiary_draws_when_you_pay_g_for_a_creature_spell() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.interactive_seats = [0]
	engine.state.turn_number = 3
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Lifecrafter's Bestiary")
	for _i in 3:
		var f := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Forest")
		f.summoned_this_turn = false
	for _j in 4:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Island")
	var bears := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Grizzly Bears")
	engine.state.awaiting = {player_id = 0, type = &"priority"}
	var cast := GameAction.new()
	cast.kind = GameAction.Kind.CAST_SPELL
	cast.player_id = 0
	cast.object_id = bears.object_id
	cast.extra = {auto_pay = true}
	var r := engine.submit(cast)
	assert_true(r.ok, "cast: %s" % r.error)
	var info := "stack=%d mode=%s" % [(engine.state.stack as MagicStack).size(), str(engine.state.mode)]
	for a in (engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids):
		var o: GameObject = engine.state.objects[a]
		if (o.definition as CardDefinition).name.begins_with("Lifecrafter"):
			for ab in (o.definition as CardDefinition).abilities:
				info += " | %s %s %s" % [str((ab as Ability).kind), str((ab as Ability).trigger), str((ab as Ability).effects.map(func(e): return str(e.kind) + str(e.params)))]
	_answer_all(engine, {})
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), 1, "paid {G}, drew a card — hand=%d lib=%d untapped=%d decisions=%d log=%s %s" % [(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), (engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0) as Zone).size(), _untapped_lands(engine), _seen_decisions, _last_prompt, info])


func _manual_draw_session() -> GameSession:
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = db
	session.you_seat = 0
	session.skip_ai = false  ## against the bot, like the player who reported it
	session.manual_draw = true
	var engine := session.engine
	engine.manual_draw_seats = [0]
	engine.interactive_seats = [0]
	for pid in 2:
		for _i in 8:
			Fixtures.spawn_named(engine, db, pid, EngineEnums.ZoneId.LIBRARY, "Island")
	engine.state.turn_number = 2
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.priority.give(engine.state, 0)
	session.rebuild_view()
	return session


func test_the_deck_keeps_asking_for_the_draw_after_an_upkeep_scry() -> void:
	var session := _manual_draw_session()
	Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Lifecrafter's Bestiary")
	session.end_you_turn()
	session.pass_until_active(0)
	var guard := 0
	while session.engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION and guard < 5:
		guard += 1
		var dec := session.engine.state.pending_decision as PlayerDecision
		## What the table's pick screen does when a choice is clicked.
		var a := GameAction.new()
		a.kind = GameAction.Kind.SUBMIT_DECISION
		a.player_id = 0
		if not dec.candidates.is_empty():
			a.extra = {choice = dec.candidates[0]}
		if session.submit(a).ok:
			session.resolve_stack_then_yield()
	assert_true(guard >= 1, "the upkeep scry asked a question (mode %s step %s)" % [str(session.engine.state.mode), str(session.engine.state.step)])
	session.pass_until_active(0)
	assert_eq(session.engine.state.step, EngineEnums.Step.DRAW, "waiting at the draw step (mode %s)" % str(session.engine.state.mode))
	assert_true(session.draw_waiting(), "the draw is still owed")
	assert_true(session.pending_draw_anim, "so the deck keeps flashing")
	assert_true(session.view.draw_waiting_you, "and the screen is told")


func test_myr_superion_can_only_be_paid_with_creature_mana() -> void:
	var engine := Fixtures.empty_engine_1v1()
	for _i in 4:
		var isl := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
		isl.summoned_this_turn = false
	var myr := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Myr Superion")
	var cost := ManaCost.parse("{2}")
	assert_false(engine.can_afford_spell(0, myr, cost), "four Islands can't pay for it")
	for _j in 2:
		var elf := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Llanowar Elves")
		elf.summoned_this_turn = false
	assert_true(engine.can_afford_spell(0, myr, cost), "two mana creatures can")
	engine.state.awaiting = {player_id = 0, type = &"priority"}
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.state.active_player_id = 0
	var cast := GameAction.new()
	cast.kind = GameAction.Kind.CAST_SPELL
	cast.player_id = 0
	cast.object_id = myr.object_id
	cast.extra = {auto_pay = true}
	var r := engine.submit(cast)
	assert_true(r.ok, "cast: %s" % r.error)
	var islands_tapped := 0
	var elves_tapped := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects[oid]
		var nm := (o.definition as CardDefinition).name
		if nm == "Island" and o.tapped:
			islands_tapped += 1
		if nm == "Llanowar Elves" and o.tapped:
			elves_tapped += 1
	assert_eq(islands_tapped, 0, "no Island was tapped for it")
	assert_eq(elves_tapped, 2, "both creatures were")
