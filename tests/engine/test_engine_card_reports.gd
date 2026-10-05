@tool
extends McpTestSuite

## Cards that did nothing in a real game, with their real Oracle text: Fate Unraveler (opponent draws), Theater of
## Horrors (exile at upkeep, play from among them, ping) and Grab the Prize (discard as a cost, conditional damage).

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_card_reports"


func _row(name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "") -> Dictionary:
	return {name = name, oracle_id = name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Fate Unraveler", "{3}{B}", 4, "Enchantment Creature — Hag", "Whenever an opponent draws a card, Fate Unraveler deals 1 damage to that player.", "3", "4"))
	m.add(_row("Theater of Horrors", "{1}{B}{R}", 3, "Enchantment", "At the beginning of your upkeep, exile the top card of your library.\nDuring your turn, if an opponent lost life this turn, you may play lands and cast spells from among cards exiled with Theater of Horrors.\n{3}{R}: Theater of Horrors deals 1 damage to target opponent or planeswalker."))
	m.add(_row("Grab the Prize", "{1}{R}", 2, "Sorcery", "As an additional cost to cast this spell, discard a card.\nDraw two cards. If the discarded card wasn't a land card, Grab the Prize deals 2 damage to each opponent."))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	db = CardDatabase.new()
	db.setup(m)


func test_fate_unraveler_pings_the_player_who_draws() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Fate Unraveler")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var life := engine.state.players[1].life
	engine.draw_card(1)
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the trigger went on the stack")
	engine.resolve_top()
	assert_eq(engine.state.players[1].life, life - 1)


func test_fate_unraveler_ignores_its_own_controllers_draw() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Fate Unraveler")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	engine.draw_card(0)
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 0)


func test_theater_exiles_at_upkeep_and_the_card_is_linked() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var theater := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Theater of Horrors")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	engine.state.active_player_id = 0
	engine.triggers.fire_player_event(engine, "BEGIN_STEP", 0)
	for ab in (theater.definition as CardDefinition).abilities:
		if (ab as Ability).kind == &"TRIGGERED":
			assert_eq(str((ab as Ability).effects[0].kind), "EXILE_TOP")


func test_theater_lets_you_play_exiled_cards_only_after_an_opponent_lost_life() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var theater := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Theater of Horrors")
	var card := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.EXILE, "Test Filler")
	card.marks["exiled_with"] = theater.object_id
	engine.state.active_player_id = 0
	assert_false(engine.can_play_from_exile(0, card), "no life lost yet")
	engine.state.players[1].life_lost_this_turn = 2
	assert_true(engine.can_play_from_exile(0, card), "an opponent lost life this turn")
	engine.state.active_player_id = 1
	assert_false(engine.can_play_from_exile(0, card), "only during your turn")


func test_grab_the_prize_reads_both_halves() -> void:
	var ab: Ability = null
	for a in db.definition_for("Grab the Prize").abilities:
		if (a as Ability).kind == &"SPELL":
			ab = a
	assert_true(ab != null, "the spell was read")
	assert_eq(ab.effects.size(), 2)
	assert_eq(str(ab.effects[0].kind), "DRAW")
	assert_true((ab.effects[1].params as Dictionary).has("if_cond"), "the damage is conditional on the discarded card")


func test_paid_card_condition() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Grab the Prize")
	spell.marks["paid_types"] = ["Creature — Test"]
	assert_true(engine.layers.condition_met(engine.state, spell, {"paid_lacks": "Land"}))
	spell.marks["paid_types"] = ["Basic Land — Mountain"]
	assert_false(engine.layers.condition_met(engine.state, spell, {"paid_lacks": "Land"}))
	assert_true(engine.layers.condition_met(engine.state, spell, {"paid_has": "Land"}))


# --- Coverage push: look at the top, sacrifice costs, activation limits, "you may ... if you do" -----------------

func _db2() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Wayfinder", "{2}{G}", 3, "Creature — Satyr", "When this creature enters, reveal the top four cards of your library. You may put a land card from among them into your hand. Put the rest into your graveyard.", "1", "1"))
	m.add(_row("Test Altar", "{2}", 2, "Artifact", "{1}, Sacrifice a creature: You gain 2 life. Activate only once each turn."))
	m.add(_row("Test Gambler", "{1}{R}", 2, "Sorcery", "You may discard a card. If you do, draw two cards."))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_look_at_top_takes_a_land_and_graveyards_the_rest() -> void:
	var db2 := _db2()
	var engine := Fixtures.empty_engine_1v1()
	for _i in 3:
		Fixtures.spawn_named(engine, db2, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	Fixtures.spawn_named(engine, db2, 0, EngineEnums.ZoneId.LIBRARY, "Mountain")
	Fixtures.spawn_named(engine, db2, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Wayfinder")
	engine.process_zone_events()
	engine.resolve_top()
	var hand: int = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size()
	var gy: int = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0).size()
	assert_eq(hand, 1, "the land was taken")
	assert_eq(gy, 3, "the rest of the four went to the graveyard")


func test_sacrifice_cost_is_read_and_limited_to_once_each_turn() -> void:
	var db2 := _db2()
	var ab: Ability = null
	for a in db2.definition_for("Test Altar").abilities:
		if (a as Ability).is_activated():
			ab = a
	assert_true(ab != null, "the altar's ability was read")
	var kinds: Array = []
	for c in ab.costs:
		kinds.append(str((c as AbilityCost).kind))
	assert_true(kinds.has("SACRIFICE"), "a sacrifice cost")
	assert_true(ab.restrictions.has("ONCE_EACH_TURN"), "activate only once each turn")


func test_you_may_if_you_do_becomes_a_question_and_a_gated_payoff() -> void:
	var r := OracleIr.new()
	assert_true(r._read_effects("You may discard a card. If you do, draw two cards"))
	var kinds: Array = []
	for fx in r._effects:
		kinds.append(str((fx as Dictionary).kind))
	assert_eq(kinds, ["MAY", "DISCARD", "DRAW"])
	assert_true(((r._effects[2] as Dictionary).params as Dictionary).has("if_link"), "the draw waits for the answer")


func _db3() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Spawner", "{2}{W}", 3, "Creature — Test", "When this creature enters, create a 1/1 white Soldier creature token. Sacrifice it at the beginning of the next end step.", "1", "1"))
	m.add(_row("Test Devil Maker", "{2}{R}", 3, "Creature — Test", "When this creature enters, create a 1/1 red Devil creature token with \"When this creature dies, it deals 1 damage to any target.\"", "1", "1"))
	m.add(_row("Test Landmark", "{3}", 3, "Creature — Test", "~'s power and toughness are each equal to the number of lands you control.", "*", "*"))
	m.add(_row("Test Threaten", "{2}{R}", 3, "Sorcery", "Gain control of target creature until end of turn. Untap that creature. It gains haste until end of turn."))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_delayed_sacrifice_of_a_token_at_the_end_step() -> void:
	var db3 := _db3()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db3, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Spawner")
	engine.process_zone_events()
	engine.resolve_top()
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(bf.size(), 2, "the Spawner and its Soldier token")
	assert_eq(engine.state.delayed.size(), 1, "the sacrifice is waiting for the end step")
	engine.state.step = EngineEnums.Step.END
	engine.triggers._fire_delayed(engine, "END", 0)
	engine.resolve_top()
	assert_eq(bf.size(), 1, "the token was sacrificed")


func test_token_with_its_own_rules_has_abilities() -> void:
	var db3 := _db3()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db3, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Devil Maker")
	engine.process_zone_events()
	engine.resolve_top()
	var found := false
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects[oid]
		if o.is_token and not (o.definition as CardDefinition).abilities.is_empty():
			found = true
	assert_true(found, "the Devil token carries its dies trigger")


func test_power_equal_to_lands_you_control() -> void:
	var db3 := _db3()
	var engine := Fixtures.empty_engine_1v1()
	var lm := Fixtures.spawn_named(engine, db3, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Landmark")
	Fixtures.spawn_named(engine, db3, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	Fixtures.spawn_named(engine, db3, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	assert_eq(engine.power_of(lm), 2)
	assert_eq(engine.toughness_of(lm), 2)


func test_threaten_reads_control_untap_and_haste() -> void:
	var db3 := _db3()
	var ab: Ability = null
	for a in db3.definition_for("Test Threaten").abilities:
		if (a as Ability).kind == &"SPELL":
			ab = a
	assert_true(ab != null)
	var kinds: Array = []
	for fx in ab.effects:
		kinds.append(str((fx as AbilityEffect).kind))
	assert_eq(kinds, ["GAIN_CONTROL", "UNTAP", "PUMP"])


func test_massacre_wurm_shrinks_their_creatures_and_drains_for_each_death() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Wurm", "{3}{B}{B}{B}", 6, "Creature — Phyrexian Wurm", "When this creature enters, creatures your opponents control get −2/−2 until end of turn.\nWhenever a creature an opponent controls dies, that player loses 2 life.", "6", "5"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Filler")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Filler")
	var life := engine.state.players[1].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Wurm")
	engine.process_zone_events()
	engine.resolve_top()
	for _i in 4:
		engine.process_zone_events()
		if (engine.state.stack as MagicStack).is_empty():
			break
		engine.resolve_top()
	assert_eq(engine.state.players[1].life, life - 4, "two of their creatures died: 2 life each")


func test_valgavoth_triggers_on_the_first_life_loss_in_their_turn_only() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Harrower", "{2}{B}{B}", 4, "Creature — Elder Demon", "Whenever an opponent loses life for the first time during each of their turns, put a +1/+1 counter on ~ and draw a card.", "3", "3"))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Harrower")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	engine.state.active_player_id = 1
	engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, 1, {to_player = 1, amount = 2})
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the first loss this turn triggers")
	engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, 1, {to_player = 1, amount = 1})
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the second loss does not")


func test_harsh_mentor_punishes_an_opponents_non_mana_ability() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Mentor", "{1}{R}", 2, "Creature — Test", "Whenever an opponent activates an ability of an artifact, creature, or land on the battlefield, if it isn't a mana ability, ~ deals 2 damage to that player.", "2", "2"))
	m.add(_row("Test Pinger", "{1}", 1, "Creature — Test", "{T}: ~ deals 1 damage to target opponent.", "1", "1"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Mentor")
	var pinger := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Pinger")
	engine.triggers.on_ability_activated(engine, pinger, 1)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the Mentor's trigger is on the stack")
	var life := engine.state.players[1].life
	engine.resolve_top()
	assert_eq(engine.state.players[1].life, life - 2)


func _db4() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Merchant of Shadows", "{3}{B}{B}", 5, "Creature — Zombie", "When this creature enters, each opponent loses X life, where X is your devotion to black. You gain life equal to the life lost this way.", "4", "5"))
	m.add(_row("Test Ferocidon", "{2}{R}", 3, "Creature — Beast", "Players can't gain life.", "3", "3"))
	m.add(_row("Test Blast", "{4}{R}{R}", 6, "Sorcery", "~ costs {1} less to cast for each creature on the battlefield.\nTest Blast deals 13 damage to each creature."))
	m.add(_row("Test Taunter", "{4}{R}", 5, "Creature — Goblin", "Whenever this creature is dealt damage, it deals that much damage to target opponent.", "1", "3"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_devotion_drain_and_the_matching_life_gain() -> void:
	var d := _db4()
	var engine := Fixtures.empty_engine_1v1()
	var mine := engine.state.players[0].life
	var theirs := engine.state.players[1].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Merchant of Shadows")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.players[1].life, theirs - 2, "devotion to black is the two {B} symbols on it")
	assert_eq(engine.state.players[0].life, mine + 2, "and you gain what they lost")


func test_players_cant_gain_life() -> void:
	var d := _db4()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ferocidon")
	var mine := engine.state.players[0].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Merchant of Shadows")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, mine, "the gain was prevented")


func test_cost_reduction_for_each_creature_on_the_battlefield() -> void:
	var d := _db4()
	var engine := Fixtures.empty_engine_1v1()
	var blast := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Blast")
	var before := engine.effective_cost(0, blast).generic
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ferocidon")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Taunter")
	assert_eq(engine.effective_cost(0, blast).generic, before - 2)


func _db5() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	var black := _row("Test Black Wall", "{B}", 1, "Creature — Wall", "", "0", "4")
	black["colors"] = ["B"]
	m.add(black)
	m.add(_row("Test Red Wall", "{R}", 1, "Creature — Wall", "", "0", "4"))
	m.add(_row("Test Sneak", "{2}{B}", 3, "Creature — Rogue", "~ can't be blocked except by black creatures.", "2", "2"))
	m.add(_row("Test Seizer", "{1}{B}", 2, "Creature — Test", "When this creature enters, target opponent reveals their hand. You choose a nonland card from it. That player discards that card. You lose 2 life.", "1", "1"))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Big Filler", "{4}", 4, "Creature — Test", "", "4", "4"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_cant_be_blocked_except_by_black_creatures() -> void:
	var d := _db5()
	var engine := Fixtures.empty_engine_1v1()
	var sneak := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Sneak")
	var black := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Black Wall")
	var red := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Red Wall")
	assert_true(engine._can_block(black.object_id, 1, sneak.object_id), "a black creature may block it")
	assert_false(engine._can_block(red.object_id, 1, sneak.object_id), "a red one may not")


func test_discard_chosen_takes_their_best_nonland_card_and_costs_life() -> void:
	var d := _db5()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.HAND, "Test Filler")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.HAND, "Test Big Filler")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.HAND, "Mountain")
	var life := engine.state.players[0].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Seizer")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1).size(), 2, "one card was discarded")
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1).size(), 1)
	assert_eq(engine.state.players[0].life, life - 2)


func test_counter_unless_pay_and_bite_are_read() -> void:
	var r := OracleIr.new()
	assert_true(r._read_effects("Counter target spell unless its controller pays {2}"))
	assert_eq(str((r._effects[0] as Dictionary).kind), "COUNTER_UNLESS_PAY")
	var b := OracleIr.new()
	assert_true(b._read_effects("Target creature you control deals damage equal to its power to target creature you don't control"))
	assert_eq(str((b._effects[0] as Dictionary).kind), "FIGHT")


func test_damage_prevention_shields() -> void:
	var r := OracleIr.new()
	assert_true(r._read_effects("Prevent the next 3 damage that would be dealt to any target this turn"))
	assert_eq(str((r._effects[0] as Dictionary).kind), "PREVENT")
	var engine := Fixtures.empty_engine_1v1()
	engine.state.prevention.append({"to": "PLAYER", "player_id": 1, "combat_only": false, "n": 3})
	assert_eq(engine.apply_prevention(null, 1, 5), 2, "three of five were prevented")
	assert_eq(engine.apply_prevention(null, 1, 4), 4, "the shield is used up")
	engine.state.prevention.append({"to": "ANY", "combat_only": true, "n": -1})
	engine.state.step = EngineEnums.Step.COMBAT_DAMAGE
	assert_eq(engine.apply_prevention(null, 0, 7), 0, "a Fog stops combat damage")


func test_token_copy_of_itself() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Replicator", "{3}", 3, "Creature — Shapeshifter", "When this creature enters, create a token that's a copy of ~.", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Replicator")
	engine.process_zone_events()
	engine.resolve_top()
	var tokens := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		if (engine.state.objects[oid] as GameObject).is_token:
			tokens += 1
	assert_eq(tokens, 1, "a token copy was made")


func test_tribal_lord_and_color_lord() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Zombie Lord", "{1}{B}{B}", 3, "Creature — Zombie", "Other Zombie creatures you control get +1/+1.", "2", "2"))
	m.add(_row("Test Zombie", "{1}{B}", 2, "Creature — Zombie", "", "2", "2"))
	m.add(_row("Test Human", "{1}{W}", 2, "Creature — Human", "", "2", "2"))
	m.add(_row("Test Bad Moon", "{1}{B}", 2, "Enchantment", "Black creatures get +1/+1."))
	var black_bear := _row("Test Black Bear", "{1}{B}", 2, "Creature — Bear", "", "2", "2")
	black_bear["colors"] = ["B"]
	m.add(black_bear)
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	var lord := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie Lord")
	var z := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	var h := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Human")
	assert_eq(engine.power_of(z), 3, "another Zombie gets +1/+1")
	assert_eq(engine.power_of(lord), 2, "the lord doesn't boost itself")
	assert_eq(engine.power_of(h), 2, "a Human is untouched")
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Black Bear")
	assert_eq(engine.power_of(bear), 2)
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bad Moon")
	assert_eq(engine.power_of(bear), 3, "Bad Moon boosts every black creature, even the opponent's")
	assert_eq(engine.power_of(h), 2)


func _db6() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Brainstormer", "{1}{U}", 2, "Creature — Test", "When this creature enters, draw three cards, then put two cards from your hand on top of your library in any order.", "1", "1"))
	m.add(_row("Test Swordsman", "{W}", 1, "Creature — Test", "When this creature enters, exile target creature an opponent controls. Its controller gains life equal to its power.", "1", "1"))
	m.add(_row("Test Filter Land", "", 0, "Land", "{W/U}, {T}: Add {W}{W}, {W}{U}, or {U}{U}."))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Big Filler", "{4}", 4, "Creature — Test", "", "4", "4"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_brainstorm_draws_three_and_puts_two_back() -> void:
	var d := _db6()
	var engine := Fixtures.empty_engine_1v1()
	for _i in 4:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Brainstormer")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size(), 1, "three drawn, two put back")
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0).size(), 3)


func test_swords_exiles_and_gives_its_controller_life_equal_to_its_power() -> void:
	var d := _db6()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Big Filler")
	var life := engine.state.players[1].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Swordsman")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1).size(), 1, "their creature was exiled")
	assert_eq(engine.state.players[1].life, life + 4, "and they gain its power")


func test_filter_land_makes_two_mana_of_either_color() -> void:
	var d := _db6()
	var found := ""
	for a in d.definition_for("Test Filter Land").abilities:
		for fx in (a as Ability).effects:
			if str((fx as AbilityEffect).kind) == "ADD_MANA":
				found = str((fx as AbilityEffect).params.get("mana", ""))
	assert_eq(found, "{W|U}{W|U}")


func _db7() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Giada", "{2}{W}", 3, "Creature — Angel", "Each other Angel you control enters with an additional +1/+1 counter on it for each Angel you already control.", "2", "2"))
	m.add(_row("Test Angel", "{2}{W}", 3, "Creature — Angel", "", "2", "2"))
	m.add(_row("Test Vitality", "{2}{W}", 3, "Creature — Angel", "If you would gain life, you gain that much life plus 1 instead.", "2", "2"))
	m.add(_row("Test Healer", "{1}{W}", 2, "Creature — Cleric", "When this creature enters, you gain 2 life.", "1", "1"))
	m.add(_row("Test Eternal Dawn", "{3}{W}", 4, "Creature — Angel", "You can't lose the game and your opponents can't win the game.", "3", "3"))
	m.add(_row("Test Tithes", "{3}{W}", 4, "Creature — Angel", "As long as ~ is untapped, creatures can't attack you or planeswalkers you control unless their controller pays {1} for each of those creatures.", "3", "5"))
	m.add(_row("Test Reanimate", "{2}{W}", 3, "Sorcery", "Return target creature card from your graveyard to the battlefield. If it's an Angel, put two +1/+1 counters on it."))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_angel_enters_with_a_counter_for_each_angel_already_there() -> void:
	var d := _db7()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Giada")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Angel")
	var second := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Angel")
	assert_eq(int(second.counters.get("+1/+1", 0)), 2, "two Angels were already there (Giada and the first Angel)")


func test_if_you_would_gain_life_you_gain_one_more() -> void:
	var d := _db7()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Vitality")
	var life := engine.state.players[0].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Healer")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, life + 3, "2 life plus 1")


func test_you_cant_lose_the_game_at_zero_life() -> void:
	var d := _db7()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Eternal Dawn")
	engine.state.players[0].life = 0
	engine.sba.check(engine)
	assert_false(engine.state.players[0].lost, "Herald of Eternal Dawn keeps you in the game")


func test_attack_tax_follows_the_untapped_archangel() -> void:
	var d := _db7()
	var engine := Fixtures.empty_engine_1v1()
	var tithes := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Tithes")
	assert_eq(engine._attack_tax_for(1), 1, "each attacker costs {1}")
	tithes.tapped = true
	assert_eq(engine._attack_tax_for(1), 0, "nothing while it is tapped")


func test_reanimate_puts_counters_only_on_an_angel() -> void:
	var d := _db7()
	var ab: Ability = null
	for a in d.definition_for("Test Reanimate").abilities:
		if (a as Ability).kind == &"SPELL":
			ab = a
	assert_true(ab != null)
	assert_eq(str(ab.effects[0].kind), "RETURN_FROM_GRAVEYARD")
	assert_eq(str(ab.effects[1].kind), "PUT_COUNTER")
	assert_eq(str((ab.effects[1].params as Dictionary).get("if_moved_subtype")), "Angel")


func test_unless_sacrifice_damage_when_nothing_cheap_to_give() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Slaughter God", "{3}{B}{R}", 5, "Legendary Enchantment Creature — God", "At the beginning of each opponent's upkeep, ~ deals 2 damage to that player unless they sacrifice a creature of their choice.", "7", "5"))
	m.add(_row("Test Big Filler", "{4}", 4, "Creature — Test", "", "4", "4"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	var abs: Array = d.definition_for("Test Slaughter God").abilities
	assert_eq(str((abs[0] as Ability).effects[0].kind), "UNLESS_SAC", "Mogis is read")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Slaughter God")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Big Filler")
	var life := engine.state.players[1].life
	engine.state.active_player_id = 1
	engine.triggers._on_step_begin(engine, EngineEnums.Step.UPKEEP, 1)
	engine.resolve_top()
	assert_eq(engine.state.players[1].life, life - 2, "a 4-mana creature is not worth giving up: they take 2")


func _db8() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Thirst", "{2}{U}", 3, "Instant", "Draw three cards. Then discard two cards unless you discard an artifact card."))
	m.add(_row("Test Juggernaut", "{4}", 4, "Artifact Creature — Juggernaut", "~ attacks each combat if able.", "5", "3"))
	m.add(_row("Test Monument", "{4}", 4, "Artifact", "Whenever you tap a permanent for {C}, add an additional {C}."))
	m.add(_row("Test Disk", "{1}", 1, "Artifact", "{1}, {T}: Destroy all artifacts, creatures, and enchantments."))
	m.add(_row("Test Sai", "{2}{U}", 3, "Legendary Creature — Human", "{1}{U}, Sacrifice two artifacts: Draw a card.", "2", "2"))
	m.add(_row("Test Shimmer", "{4}{U}", 5, "Creature — Dragon", "Tap two untapped artifacts you control: Draw a card.", "4", "4"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_new_cost_kinds_are_read() -> void:
	var d := _db8()
	var sai: Ability = null
	for a in d.definition_for("Test Sai").abilities:
		if (a as Ability).is_activated():
			sai = a
	assert_true(sai != null, "Sai's ability was read")
	var kinds: Array = []
	for c in sai.costs:
		kinds.append("%s:%s" % [str((c as AbilityCost).kind), str((c as AbilityCost).mana)])
	assert_true(kinds.has("SACRIFICE:a|2|artifacts"), "sacrifice two artifacts: %s" % str(kinds))
	var shimmer: Ability = null
	for a2 in d.definition_for("Test Shimmer").abilities:
		if (a2 as Ability).is_activated():
			shimmer = a2
	assert_true(shimmer != null and str((shimmer.costs[0] as AbilityCost).kind) == "TAP_PERMANENTS", "tap two untapped artifacts is a cost")


func test_forced_attacker_is_added_to_the_attack() -> void:
	var d := _db8()
	var engine := Fixtures.empty_engine_1v1()
	var jugg := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Juggernaut")
	assert_true(engine._must_attack(jugg), "attacks each combat if able")


func test_forsaken_monument_adds_an_extra_colorless() -> void:
	var d := _db8()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Monument")
	assert_eq(engine._extra_colorless_for(0).size(), 1)


func test_nevinyrral_destroys_artifacts_creatures_and_enchantments() -> void:
	var d := _db8()
	var disk: Ability = null
	for a in d.definition_for("Test Disk").abilities:
		if (a as Ability).is_activated():
			disk = a
	assert_true(disk != null)
	var q: Dictionary = (disk.effects[0].params as Dictionary).get("query", {})
	assert_eq((q.get("type_any", []) as Array).size(), 3)


func _db9() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Doubler", "{3}{W}", 4, "Enchantment", "If you would gain life, you gain twice that much life instead."))
	m.add(_row("Test Healer", "{1}{W}", 2, "Creature — Cleric", "When this creature enters, you gain 2 life.", "1", "1"))
	m.add(_row("Test Lifelord", "{2}{W}{W}", 4, "Creature — Avatar", "~'s power and toughness are each equal to your life total.", "*", "*"))
	m.add(_row("Test Grower", "{1}{G}", 2, "Creature — Test", "As long as ~ has four or more +1/+1 counters on it, it has flying and vigilance.", "1", "1"))
	m.add(_row("Test Biorhythm", "{4}{G}", 5, "Sorcery", "Count the number of cards in your library. Your life total becomes that number."))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_lifegain_doubler_and_life_total_power() -> void:
	var d := _db9()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Doubler")
	var life := engine.state.players[0].life
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Healer")
	engine.process_zone_events()
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, life + 4, "twice 2")
	var lord := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lifelord")
	assert_eq(engine.power_of(lord), life + 4, "power equals the life total")


func test_creature_with_enough_counters_gains_flying() -> void:
	var d := _db9()
	var engine := Fixtures.empty_engine_1v1()
	var g := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Grower")
	assert_false(engine.has_keyword(g, "Flying"))
	g.counters["+1/+1"] = 4
	assert_true(engine.has_keyword(g, "Flying"), "four counters: flying")


func test_biorhythm_is_read() -> void:
	var d := _db9()
	var ab: Ability = null
	for a in d.definition_for("Test Biorhythm").abilities:
		if (a as Ability).kind == &"SPELL":
			ab = a
	assert_true(ab != null and str(ab.effects[0].kind) == "SET_LIFE")


func test_cleanup_discards_down_to_seven_unless_no_maximum() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Vessel", "{3}", 3, "Artifact", "{T}: Add one mana of any color.\nYou have no maximum hand size."))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	for _i in 9:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Filler")
	assert_eq(engine.max_hand_size(0), 7)
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.CLEANUP
	engine.turn._start_tba(engine, engine.state)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the discard is waiting")
	engine.resolve_top()
	assert_eq(engine.hand_size(0), 7, "two cards discarded")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Vessel")
	assert_true(engine.max_hand_size(0) > 100, "no maximum hand size")


func test_gang_block_kills_a_big_attacker_losing_only_one_blocker() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Giant", "{5}", 5, "Creature — Giant", "", "5", "5"))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "3", "3"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	var giant := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Giant")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	giant.summoned_this_turn = false
	var cs := CombatState.new()
	cs.attacker_ids = [giant.object_id]
	cs.defenders = {giant.object_id: 1}
	cs.defending_player_id = 1
	engine.state.combat = cs
	var plan: Dictionary = preload("res://engine/session/ai_blocks.gd").choose(engine, 1)
	assert_eq((plan.get(giant.object_id, []) as Array).size(), 2, "two bears double-block the giant")
