@tool
extends McpTestSuite

## AUDIT-037: the attacking player divides combat damage among several blockers (and the player, with trample), and the
## divided-damage spells ask for their split.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_damage_split"


func _row(card_name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "", kws: Array = []) -> Dictionary:
	return {name = card_name, oracle_id = card_name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = kws, power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Ogre", "{4}{R}", 5, "Creature — Ogre", "", "5", "5"))
	m.add(_row("Test Rhino", "{4}{G}", 5, "Creature — Rhino", "Trample", "5", "5", ["Trample"]))
	m.add(_row("Test Arc", "{R}{R}", 2, "Sorcery", "Test Arc deals 3 damage divided as you choose among one, two, or three targets."))
	m.add(_row("Test Onslaught", "{3}{R}", 4, "Instant", "Test Onslaught deals X damage divided as you choose among any number of target creatures, where X is the greatest power among creatures you control as you cast Test Onslaught."))
	db = CardDatabase.new()
	db.setup(m)


## An attack by `attacker_name` (controlled by player 0, who answers for themselves) blocked by `n` Bears.
func _blocked(attacker_name: String, n: int, human: bool = true) -> Dictionary:
	var engine := Fixtures.empty_engine_1v1()
	engine.interactive_seats = [0] if human else []
	var attacker := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, attacker_name)
	attacker.summoned_this_turn = false
	var blockers: Array = []
	for _i in n:
		blockers.append(Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear"))
	var cs := engine.state.combat as CombatState
	cs.attacker_ids = [attacker.object_id]
	cs.defending_player_id = 1
	var ids: Array = []
	for b in blockers:
		ids.append((b as GameObject).object_id)
	cs.blockers[attacker.object_id] = ids
	cs.blocks_declared = true
	return {engine = engine, attacker = attacker, blockers = blockers}


func _submit_split(engine: RulesEngine, split: Dictionary) -> SubmitResult:
	var a := GameAction.new()
	a.kind = GameAction.Kind.SUBMIT_DECISION
	a.player_id = 0
	a.extra = {split = split}
	return engine.submit(a)


func test_a_person_is_asked_how_to_divide_damage_between_two_blockers() -> void:
	var s := _blocked("Test Ogre", 2)
	var engine: RulesEngine = s.engine
	assert_false(engine.apply_combat_damage(), "it stops to ask")
	var dec := engine.state.pending_decision as PlayerDecision
	assert_true(dec != null and dec.kind == &"DISTRIBUTE" and dec.total == 5)
	assert_eq(dec.candidates.size(), 2, "the two blockers")
	var b1: GameObject = s.blockers[0]
	var b2: GameObject = s.blockers[1]
	assert_false(_submit_split(engine, {b1.object_id: 2, b2.object_id: 2}).ok, "four isn't five")
	assert_true(_submit_split(engine, {b1.object_id: 1, b2.object_id: 4}).ok)
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1) as Zone).size(), 1, "one Bear took 4 and died")
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD) as Zone).size(), 2, "the other Bear took 1 and lived (the Ogre too)")
	assert_eq(engine.state.players[1].life, 40, "no trample, nothing for the player")


func test_the_bot_divides_automatically() -> void:
	var s := _blocked("Test Ogre", 2, false)
	var engine: RulesEngine = s.engine
	assert_true(engine.apply_combat_damage(), "nobody is asked")
	assert_true(engine.state.pending_decision == null)


func test_trample_needs_lethal_on_every_blocker_before_the_player_gets_any() -> void:
	var s := _blocked("Test Rhino", 2)
	var engine: RulesEngine = s.engine
	assert_false(engine.apply_combat_damage())
	var b1: GameObject = s.blockers[0]
	var b2: GameObject = s.blockers[1]
	var player_key := TargetingManager.encode_player(1)
	assert_eq((engine.state.pending_decision as PlayerDecision).candidates.size(), 3, "two blockers and the player")
	assert_false(_submit_split(engine, {b1.object_id: 1, b2.object_id: 1, player_key: 3}).ok, "the Bears aren't dead yet")
	assert_true(_submit_split(engine, {b1.object_id: 2, b2.object_id: 2, player_key: 1}).ok)
	assert_eq(engine.state.players[1].life, 39, "one trampled over")


func test_declining_takes_the_automatic_split() -> void:
	var s := _blocked("Test Rhino", 2)
	var engine: RulesEngine = s.engine
	engine.apply_combat_damage()
	var a := GameAction.new()
	a.kind = GameAction.Kind.DECLINE_DECISION
	a.player_id = 0
	assert_true(engine.submit(a).ok)
	assert_eq(engine.state.players[1].life, 39, "lethal to each Bear, one over for the player")


func _effects(obj: GameObject) -> Array:
	var out: Array = []
	for a in (obj.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"SPELL":
			out.append_array((a as Ability).effects)
	return out


func _cast_divided(spell_name: String, human: bool) -> Dictionary:
	var engine := Fixtures.empty_engine_1v1()
	engine.interactive_seats = [0] if human else []
	var bear1 := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var bear2 := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var ogre := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, spell_name)
	engine.put_synthetic(spell, 0, _effects(spell), {})
	engine.resolve_top()
	return {engine = engine, bear1 = bear1, bear2 = bear2, ogre = ogre}


func test_arc_lightning_asks_how_to_divide_three_damage() -> void:
	var s := _cast_divided("Test Arc", true)
	var engine: RulesEngine = s.engine
	var dec := engine.state.pending_decision as PlayerDecision
	assert_true(dec != null and dec.kind == &"DISTRIBUTE", "asks")
	assert_eq(dec.total, 3)
	assert_eq(dec.max_targets, 3, "one, two, or three targets")
	var rival := TargetingManager.encode_player(1)
	assert_true(_submit_split(engine, {(s.bear1 as GameObject).object_id: 2, rival: 1}).ok)
	assert_eq(engine.state.players[1].life, 39, "one to the player")
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1) as Zone).size(), 1, "two killed a Bear")


func test_a_split_with_too_many_targets_is_refused() -> void:
	var s := _cast_divided("Test Arc", true)
	var engine: RulesEngine = s.engine
	var two_of_four := {(s.bear1 as GameObject).object_id: 1, (s.bear2 as GameObject).object_id: 1, TargetingManager.encode_player(1): 1, (s.ogre as GameObject).object_id: 1}
	assert_false(_submit_split(engine, {(s.bear1 as GameObject).object_id: 3, 9999: 0}).ok, "not something to divide among")
	var r := _submit_split(engine, two_of_four)
	assert_false(r.ok, "four targets and total 4 isn't 3: %s" % r.error)


func test_the_bot_puts_divided_damage_where_it_kills() -> void:
	var s := _cast_divided("Test Arc", false)
	var engine: RulesEngine = s.engine
	assert_true(engine.state.pending_decision == null, "nobody is asked")
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1) as Zone).size(), 1, "a Bear died")
	assert_eq(engine.state.players[1].life, 39, "the leftover point went at the player")


func test_monstrous_onslaught_deals_the_greatest_power_among_creatures() -> void:
	var s := _cast_divided("Test Onslaught", true)
	var engine: RulesEngine = s.engine
	var dec := engine.state.pending_decision as PlayerDecision
	assert_eq(dec.total, 5, "total=%d prompt=%s" % [dec.total, dec.prompt])
	assert_eq(dec.candidates.size(), 3, "creatures only: no players")
	assert_true(_submit_split(engine, {(s.bear1 as GameObject).object_id: 2, (s.bear2 as GameObject).object_id: 3}).ok)
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1) as Zone).size(), 2, "both Bears died")


# --- The dividing screen -------------------------------------------------------------------------------------

func _button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for ch in node.get_children():
		var hit := _button(ch, text)
		if hit != null:
			return hit
	return null


func test_the_dividing_screen_only_confirms_a_complete_split() -> void:
	var dlg := DistributeDialog.new()
	var opts := [{value = 11, label = "Bear", detail = "2/2", lethal = 2}, {value = 12, label = "Bear", detail = "2/2", lethal = 2}, {value = 13, label = "Other", detail = "", lethal = 0}]
	dlg.show_split("Divide 4", "", 4, opts, 2, {})
	var got: Array = []
	dlg.confirmed.connect(func(split: Dictionary) -> void: got.append(split))
	var confirm := _button(dlg, "Confirm")
	assert_true(confirm.disabled, "nothing placed yet")
	_button(dlg, "Lethal (2)").pressed.emit()
	assert_true(confirm.disabled, "two points still to place")
	var pluses: Array = []
	_collect(dlg, "+", pluses)
	(pluses[1] as Button).pressed.emit()
	(pluses[1] as Button).pressed.emit()
	assert_false(confirm.disabled, "all four placed on two targets")
	confirm.pressed.emit()
	assert_eq(got.size(), 1)
	assert_eq(int(got[0].get(11, 0)), 2)
	assert_eq(int(got[0].get(12, 0)), 2)
	dlg.free()


func test_the_dividing_screen_refuses_more_targets_than_allowed() -> void:
	var dlg := DistributeDialog.new()
	var opts := [{value = 1, label = "A", lethal = 0}, {value = 2, label = "B", lethal = 0}, {value = 3, label = "C", lethal = 0}]
	dlg.show_split("Divide 3", "", 3, opts, 2, {})
	var pluses: Array = []
	_collect(dlg, "+", pluses)
	for p in pluses:
		(p as Button).pressed.emit()
	assert_true(_button(dlg, "Confirm").disabled, "one point on each of three targets, but only two are allowed")
	dlg.free()


func _collect(node: Node, text: String, out: Array) -> void:
	if node is Button and (node as Button).text == text:
		out.append(node)
	for ch in node.get_children():
		_collect(ch, text, out)


func test_a_session_turns_the_question_into_a_dividing_prompt() -> void:
	var s := _cast_divided("Test Arc", true)
	var session := GameSession.new()
	session.engine = s.engine
	session.db = db
	session.you_seat = 0
	var prompt := session.prompt_for(0)
	assert_eq(str(prompt.get("kind", "")), "distribute")
	assert_eq(int(prompt.total), 3)
	assert_eq(int(prompt.max_targets), 3)
	assert_true((prompt.options as Array).size() >= 3, "the Bears, the Ogre and both players")
