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


# --- Group effects read by OracleIr._more_sentence ------------------------------------------------------------------

func _db_groups() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Quake", "{3}", 3, "Sorcery", "Tap all creatures your opponents control.\nEach player loses 2 life."))
	m.add(_row("Test Purge", "{2}", 2, "Sorcery", "Destroy all creatures with flying.\nExile all artifacts."))
	m.add(_row("Test Rout", "{2}", 2, "Sorcery", "Creatures you don't control get -2/-2 until end of turn.\nCreatures you don't control can't block this turn."))
	var bird_row := _row("Test Bird", "{1}", 1, "Creature — Bird", "Flying", "1", "1")
	bird_row["keywords"] = ["Flying"]
	m.add(bird_row)
	m.add(_row("Test Bear", "{1}", 1, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Rock", "{1}", 1, "Artifact", ""))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func _cast_effects(engine: RulesEngine, d: CardDatabase, who: int, card_name: String) -> void:
	var spell := Fixtures.spawn_named(engine, d, who, EngineEnums.ZoneId.HAND, card_name)
	var fxs: Array = []
	for a in (spell.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"SPELL":
			fxs.append_array((a as Ability).effects)
	assert_true(not fxs.is_empty(), "%s was read" % card_name)
	engine.put_synthetic(spell, who, fxs, {})
	engine.resolve_top()
	engine.sba.check(engine)


func test_tap_all_and_each_player_loses_life() -> void:
	var d := _db_groups()
	var engine := Fixtures.empty_engine_1v1()
	var mine := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var theirs := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var l0: int = engine.state.players[0].life
	var l1: int = engine.state.players[1].life
	_cast_effects(engine, d, 0, "Test Quake")
	assert_true(theirs.tapped, "their creature is tapped")
	assert_false(mine.tapped, "mine is not")
	assert_eq(engine.state.players[0].life, l0 - 2)
	assert_eq(engine.state.players[1].life, l1 - 2)


func test_destroy_fliers_and_exile_artifacts() -> void:
	var d := _db_groups()
	var engine := Fixtures.empty_engine_1v1()
	var bird := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bird")
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var rock := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Rock")
	_cast_effects(engine, d, 0, "Test Purge")
	assert_false(_on_bf(engine, bird), "the flier died")
	assert_true(_on_bf(engine, bear), "the ground creature lives")
	assert_false(_on_bf(engine, rock), "the artifact was exiled")


func test_opposing_creatures_shrink_and_cannot_block() -> void:
	var d := _db_groups()
	var engine := Fixtures.empty_engine_1v1()
	var theirs := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var mine := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_cast_effects(engine, d, 0, "Test Rout")
	assert_false(_on_bf(engine, theirs), "a 2/2 with -2/-2 dies")
	assert_eq(engine.toughness_of(mine), 2, "mine is untouched")
	var blocker := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bird")
	assert_false(engine.has_keyword(blocker, "Can't block"), "a creature that arrives later is not affected")


func _on_bf(engine: RulesEngine, obj: GameObject) -> bool:
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	return bf != null and bf.object_ids.has(obj.object_id)


# --- Printed restrictions, discounts and delayed draws -------------------------------------------------------------

func _db_rules() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Bargain", "{B}{B}", 2, "Enchantment", "Skip your draw step."))
	var sprite_row := _row("Test Sprite", "{1}{U}", 2, "Creature — Faerie", "Flying
Test Sprite can block only creatures with flying.", "1", "1")
	sprite_row["keywords"] = ["Flying"]
	m.add(sprite_row)
	m.add(_row("Test Skulker", "{2}{B}", 3, "Creature — Rogue", "Test Skulker can't be blocked by creatures with power 2 or less.", "3", "3"))
	m.add(_row("Test Ogre", "{3}", 3, "Creature — Ogre", "", "3", "3"))
	m.add(_row("Test Lens", "{2}", 2, "Artifact", "Instant and sorcery spells you cast cost {1} less to cast."))
	m.add(_row("Test Zap", "{1}{R}", 2, "Instant", "Test Zap deals 2 damage to any target."))
	m.add(_row("Test Boon", "{1}{U}", 2, "Instant", "Draw a card at the beginning of the next turn's upkeep."))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	var bird_row := _row("Test Bird", "{1}", 1, "Creature — Bird", "Flying", "1", "1")
	bird_row["keywords"] = ["Flying"]
	m.add(bird_row)
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_skip_your_draw_step() -> void:
	var d := _db_rules()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	engine.state.active_player_id = 0
	engine.state.turn_number = 3
	engine.state.step = EngineEnums.Step.DRAW
	engine.turn._start_tba(engine, engine.state)
	assert_eq(engine.hand_size(0), 1, "an ordinary draw step draws")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bargain")
	engine.turn._start_tba(engine, engine.state)
	assert_eq(engine.hand_size(0), 1, "the draw step is skipped")


func test_can_block_only_fliers_and_power_restriction() -> void:
	var d := _db_rules()
	var engine := Fixtures.empty_engine_1v1()
	var sprite := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Sprite")
	var bear := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var bird := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bird")
	assert_false(engine.can_block_as(sprite.object_id, 1, bear.object_id), "the sprite can't block a ground creature")
	assert_true(engine.can_block_as(sprite.object_id, 1, bird.object_id), "it can block a flier")
	var skulker := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Skulker")
	var small := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var big := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	assert_false(engine.can_block_as(small.object_id, 1, skulker.object_id), "power 2 can't block it")
	assert_true(engine.can_block_as(big.object_id, 1, skulker.object_id), "power 3 can")


func test_instant_and_sorcery_discount_and_delayed_draw() -> void:
	var d := _db_rules()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lens")
	var zap := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Zap")
	var bear := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Bear")
	assert_eq(engine.cost_reduction(0, zap), 1, "instants cost one less")
	assert_eq(engine.cost_reduction(0, bear), 0, "creatures do not")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var boon := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Boon")
	var fxs: Array = []
	for a in (boon.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"SPELL":
			fxs.append_array((a as Ability).effects)
	assert_true(not fxs.is_empty(), "the delayed draw was read")
	engine.put_synthetic(boon, 0, fxs, {})
	engine.resolve_top()
	assert_eq(engine.state.delayed.size(), 1, "a delayed trigger waits for the next upkeep")
	var before := engine.hand_size(0)
	engine.state.turn_number += 1
	engine.triggers._fire_delayed(engine, "UPKEEP", 1)
	engine.resolve_top()
	assert_eq(engine.hand_size(0), before + 1, "the draw happens at that upkeep")


# --- Class cards (CR 716) ----------------------------------------------------------------------------------------------

func _db_class() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Class", "{1}{G}", 2, "Enchantment — Class",
		"(Gain the next level as a sorcery to add its ability.)\nAt the beginning of your upkeep, you gain 1 life.\n{1}{G}: Level 2\nCreatures you control get +1/+1.\n{2}{G}: Level 3\n{T}: Add {G}."))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func _main_phase(engine: RulesEngine) -> void:
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.priority.give(engine.state, 0)


func test_class_levels_are_gained_in_order_and_gate_their_abilities() -> void:
	var d := _db_class()
	var engine := Fixtures.empty_engine_1v1()
	_main_phase(engine)
	var cls := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Class")
	var bear := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var lvl2: Ability = null
	var lvl3: Ability = null
	for a in (cls.definition as CardDefinition).abilities:
		if str((a as Ability).ability_id).ends_with("_level_2"):
			lvl2 = a
		elif str((a as Ability).ability_id).ends_with("_level_3"):
			lvl3 = a
	assert_true(lvl2 != null and lvl3 != null, "both level-up abilities were read")
	assert_eq(engine._activation_reason(cls, lvl2), "LEGAL", "level 2 can be gained first")
	assert_true(engine._activation_reason(cls, lvl3) != "LEGAL", "level 3 can't be skipped to")
	assert_eq(engine.toughness_of(bear), 2, "the level 2 lord does nothing at level 1")
	engine.mana.add(0, ManaCost.parse("{1}{G}"))
	var announced: SubmitResult = engine.submit(Fixtures.activate_ability(0, cls.object_id, lvl2.ability_id))
	assert_true(announced.ok, announced.error)
	if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
		assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)
	engine.resolve_top()
	assert_eq(int(cls.counters.get("level", 0)), 1, "a level counter was added")
	assert_eq(engine.toughness_of(bear), 3, "the level 2 lord now applies")
	assert_true(engine._activation_reason(cls, lvl2) != "LEGAL", "level 2 can't be gained twice")
	assert_eq(engine._activation_reason(cls, lvl3), "LEGAL", "level 3 is next")


func test_may_choose_not_to_untap() -> void:
	var cat := Fixtures.memory_catalog()
	(cat as CatalogSource.Memory).add(_row("Test Lamp", "{2}", 2, "Artifact", "{T}: Add {C}.\nYou may choose not to untap Test Lamp during your untap step."))
	var d := CardDatabase.new()
	d.setup(cat)
	# A bot (not an interactive seat) untaps it.
	var engine := Fixtures.empty_engine_1v1()
	var lamp := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lamp")
	lamp.tapped = true
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.UNTAP
	engine.turn._start_tba(engine, engine.state)
	assert_true(lamp.tapped, "it waits for the choice, not untapped yet")
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the choice is on the stack")
	engine.resolve_top()
	assert_false(lamp.tapped, "a bot untaps it")
	# A player who says no keeps it tapped.
	var engine2 := Fixtures.empty_engine_1v1()
	engine2.interactive_seats = [0]
	var lamp2 := Fixtures.spawn_named(engine2, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lamp")
	lamp2.tapped = true
	engine2.state.active_player_id = 0
	engine2.state.step = EngineEnums.Step.UNTAP
	engine2.turn._start_tba(engine2, engine2.state)
	engine2.resolve_top()
	assert_eq(engine2.state.mode, EngineEnums.EngineMode.AWAITING_DECISION, "the player is asked")
	assert_true(lamp2.tapped)
	(engine2.state.stack as MagicStack).top().choices["untap_%d" % lamp2.object_id] = false
	engine2.state.pending_decision = null
	engine2.resolve_top()
	assert_true(lamp2.tapped, "answering no keeps it tapped")


func test_enters_with_x_counters_is_read_but_fixed_counts_stay_a_trigger() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Hydra", "{X}{G}", 1, "Creature — Hydra", "Test Hydra enters with X +1/+1 counters on it.", "0", "0"))
	m.add(_row("Test Brute", "{3}{G}", 4, "Creature — Beast", "Test Brute enters with two +1/+1 counters on it.", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	var hydra := ZoneManager.enters_with_counters(d.definition_for("Test Hydra"))
	assert_eq(hydra.size(), 1)
	assert_true(bool(hydra[0].x), "X comes from the mana paid")
	assert_eq(str(hydra[0].name), "+1/+1")
	assert_true(ZoneManager.enters_with_counters(d.definition_for("Test Brute")).is_empty(), "a fixed count is the existing trigger")
	for st in d.line_status(d.definition_for("Test Hydra")):
		assert_true(bool((st as Dictionary).read), "the X line counts as read")


func test_cant_attack_unless_defender_controls_an_island() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Leviathan", "{4}{U}", 5, "Creature — Leviathan", "Test Leviathan can't attack unless defending player controls an Island.", "5", "5"))
	m.add(_row("Test Isle", "", 0, "Basic Land — Island", ""))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	var beast := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Leviathan")
	beast.summoned_this_turn = false
	assert_false(engine.legal_attacker_ids(0).has(beast.object_id), "no Island on their side")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Isle")
	assert_true(engine.legal_attacker_ids(0).has(beast.object_id), "they control an Island")


func test_dies_return_it_to_its_owners_hand() -> void:
	var cat := Fixtures.memory_catalog()
	(cat as CatalogSource.Memory).add(_row("Test Phoenix", "{2}{R}", 3, "Creature — Phoenix", "When Test Phoenix is put into a graveyard from the battlefield, return it to its owner's hand.", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	var phx := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Phoenix")
	engine.destroy_permanent(phx)
	engine.process_zone_events()
	assert_true((engine.state.stack as MagicStack).size() >= 1, "the dies trigger is waiting")
	while not (engine.state.stack as MagicStack).is_empty():
		engine.resolve_top()
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	var back := false
	for oid in hand.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and (o.definition as CardDefinition).name == "Test Phoenix":
			back = true
	assert_true(back, "it went back to its owner's hand")


func _db_misc() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Whirl", "{2}{R}", 3, "Sorcery", "Each player discards their hand, then draws seven cards."))
	m.add(_row("Test Frost", "{1}{U}", 2, "Instant", "Tap target creature. It doesn't untap during its controller's next untap step."))
	m.add(_row("Test Spawner", "{2}", 2, "Sorcery", "Create a 1/1 colorless Eldrazi Scion creature token. It has \"Sacrifice this creature: Add {C}.\""))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_wheel_discards_hands_and_draws_seven() -> void:
	var d := _db_misc()
	var engine := Fixtures.empty_engine_1v1()
	for pid in 2:
		for _i in 3:
			Fixtures.spawn_named(engine, d, pid, EngineEnums.ZoneId.HAND, "Test Filler")
		for _i in 8:
			Fixtures.spawn_named(engine, d, pid, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	_cast_effects(engine, d, 0, "Test Whirl")
	assert_eq(engine.hand_size(0), 7, "the caster draws seven (the helper leaves the spell in hand, so it is discarded too)")
	assert_eq(engine.hand_size(1), 7)


func test_frozen_creature_skips_its_next_untap_only() -> void:
	var d := _db_misc()
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var spell := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Frost")
	var fxs: Array = []
	for a in (spell.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"SPELL":
			fxs.append_array((a as Ability).effects)
	var e := engine.put_synthetic(spell, 0, fxs, {})
	e.targets = [bear.object_id]
	engine.resolve_top()
	assert_true(bear.tapped, "it was tapped")
	engine.state.active_player_id = 1
	engine.turn._untap(engine.state)
	assert_true(bear.tapped, "it stays tapped through its controller's next untap step")
	engine.turn._untap(engine.state)
	assert_false(bear.tapped, "and untaps the time after")


func test_scion_token_gets_its_quoted_ability() -> void:
	var d := _db_misc()
	var engine := Fixtures.empty_engine_1v1()
	_cast_effects(engine, d, 0, "Test Spawner")
	var found := false
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and (o.definition as CardDefinition).name == "Eldrazi Scion":
			found = not (o.definition as CardDefinition).abilities.is_empty()
	assert_true(found, "the Scion can be sacrificed for mana")


# --- Library tricks, token swaps and commander moves ----------------------------------------------------------------

func _db_tricks() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Peek", "{U}", 1, "Instant", "Look at the top three cards of your library, then put them back in any order."))
	m.add(_row("Test Beast", "{2}{G}", 3, "Instant", "Destroy target creature. That creature's controller creates a 3/3 green Beast creature token."))
	m.add(_row("Test Beacon", "{2}", 2, "Artifact", "{T}, Sacrifice Test Beacon: Put your commander into your hand from the command zone."))
	m.add(_row("Test Sphinx", "{3}{U}", 4, "Creature — Sphinx", "When Test Sphinx is put into your graveyard from the battlefield, put it into your library third from the top.", "3", "3"))
	m.add(_row("Test Warp", "{2}{R}", 3, "Instant", "The owner of target permanent shuffles it into their library, then reveals the top card of their library. If it's a permanent card, they put it onto the battlefield."))
	m.add(_row("Test Rumble", "{X}{R}", 1, "Sorcery", "Test Rumble deals X damage to each creature without flying and each planeswalker."))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	var bird_row := _row("Test Bird", "{1}", 1, "Creature — Bird", "Flying", "1", "1")
	bird_row["keywords"] = ["Flying"]
	m.add(bird_row)
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func _put_effects(engine: RulesEngine, d: CardDatabase, who: int, card_name: String, targets: Array = [], ctx: Dictionary = {}, zone: int = EngineEnums.ZoneId.HAND) -> StackEntry:
	var card := Fixtures.spawn_named(engine, d, who, zone, card_name)
	var fxs: Array = []
	for a in (card.definition as CardDefinition).abilities:
		fxs.append_array((a as Ability).effects)
	assert_true(not fxs.is_empty(), "%s was read" % card_name)
	var e := engine.put_synthetic(card, who, fxs, ctx)
	e.targets = targets
	return e


func test_look_and_reorder_the_top_of_the_library() -> void:
	var d := _db_tricks()
	var engine := Fixtures.empty_engine_1v1()
	engine.interactive_seats = [0]
	var a := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var b := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var c := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	var before: Array = lib.object_ids.duplicate()
	var e := _put_effects(engine, d, 0, "Test Peek")
	engine.resolve_top()
	assert_eq(engine.state.mode, EngineEnums.EngineMode.AWAITING_DECISION, "the player is asked for the new top card")
	var last_id: int = int(before[before.size() - 1])
	var mid_id: int = int(before[before.size() - 2])
	e.choices["reorder_0"] = last_id
	e.choices["reorder_1"] = mid_id
	engine.state.pending_decision = null
	engine.resolve_top()
	var after: Array = lib.object_ids
	assert_eq(int(after[0]), last_id, "the card picked first is on top")
	assert_eq(int(after[1]), mid_id)
	assert_true(a != null and b != null and c != null)


func test_beast_within_gives_the_controller_a_token() -> void:
	var d := _db_tricks()
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_put_effects(engine, d, 0, "Test Beast", [bear.object_id])
	engine.resolve_top()
	assert_false(_on_bf(engine, bear), "the creature was destroyed")
	var beasts := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.is_token and o.controller_id == 1:
			beasts += 1
	assert_eq(beasts, 1, "its controller got the 3/3")


func test_command_beacon_and_put_third_from_the_top() -> void:
	var d := _db_tricks()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.COMMAND, "Test Filler")
	_put_effects(engine, d, 0, "Test Beacon", [], {}, EngineEnums.ZoneId.BATTLEFIELD)
	engine.resolve_top()
	assert_eq(engine.hand_size(0), 1, "the commander is in hand")
	for _i in 4:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var sphinx := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Sphinx")
	engine.destroy_permanent(sphinx)
	engine.process_zone_events()
	while not (engine.state.stack as MagicStack).is_empty():
		engine.resolve_top()
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	var third: GameObject = engine.state.objects.get(int(lib.object_ids[2]))
	assert_true(third != null and (third.definition as CardDefinition).name == "Test Sphinx", "third from the top")


func test_chaos_warp_and_x_damage_to_non_fliers() -> void:
	var d := _db_tricks()
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	_put_effects(engine, d, 0, "Test Warp", [bear.object_id])
	engine.resolve_top()
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 1)
	assert_eq(lib.object_ids.size(), 1, "one card came off the top onto the battlefield")
	var engine2 := Fixtures.empty_engine_1v1()
	var b2 := Fixtures.spawn_named(engine2, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var bird := Fixtures.spawn_named(engine2, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bird")
	_put_effects(engine2, d, 0, "Test Rumble", [], {"x": 2})
	engine2.resolve_top()
	engine2.sba.check(engine2)
	assert_false(_on_bf(engine2, b2), "the ground creature took 2")
	assert_true(_on_bf(engine2, bird), "the flier is untouched")


# --- Creature lands, discounts, equipment triggers, main-phase triggers ----------------------------------------------

func _db_lands() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Prairie", "", 0, "Land", "{2}{G}{W}: Test Prairie becomes a 3/3 green and white Llama creature until end of turn. It's still a land."))
	m.add(_row("Test Goreclaw", "{3}{G}", 4, "Creature — Bear", "Creature spells you cast with power 4 or greater cost {2} less to cast.", "3", "3"))
	m.add(_row("Test Giant", "{5}", 5, "Creature — Giant", "", "5", "5"))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Clamp", "{1}", 1, "Artifact — Equipment", "Equipped creature gets +1/-1.\nWhenever equipped creature dies, draw two cards.\nEquip {1}"))
	m.add(_row("Test Hydra", "{2}{G}", 3, "Creature — Hydra", "Whenever a player casts a spell, put a +1/+1 counter on Test Hydra.", "1", "1"))
	m.add(_row("Test Raptor", "{3}{G}", 4, "Creature — Dinosaur", "At the beginning of your first main phase, add {G}{G}.", "3", "3"))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_creature_land_becomes_a_creature_until_end_of_turn() -> void:
	var d := _db_lands()
	var engine := Fixtures.empty_engine_1v1()
	var land := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Prairie")
	assert_false(engine.is_creature_now(land), "an ordinary land")
	var fxs: Array = []
	for a in (land.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"ACTIVATED":
			fxs.append_array((a as Ability).effects)
	assert_true(not fxs.is_empty(), "the animation was read")
	engine.put_synthetic(land, 0, fxs, {})
	engine.resolve_top()
	assert_true(engine.is_creature_now(land), "now a creature")
	assert_eq(engine.power_of(land), 3)
	assert_eq(engine.toughness_of(land), 3)
	engine.layers.clear_until_eot(engine.state)
	assert_false(engine.is_creature_now(land), "back to a land at end of turn")


func test_power_four_creature_spells_cost_two_less() -> void:
	var d := _db_lands()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Goreclaw")
	var giant := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Giant")
	var bear := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Bear")
	assert_eq(engine.cost_reduction(0, giant), 2)
	assert_eq(engine.cost_reduction(0, bear), 0)


func test_skullclamp_draws_when_the_equipped_creature_dies() -> void:
	var d := _db_lands()
	var engine := Fixtures.empty_engine_1v1()
	for _i in 3:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var clamp := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Clamp")
	var bear := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	clamp.attached_to = bear.object_id
	engine.destroy_permanent(bear)
	engine.process_zone_events()
	while not (engine.state.stack as MagicStack).is_empty():
		engine.resolve_top()
	assert_eq(engine.hand_size(0), 2, "two cards drawn")


func test_any_player_cast_trigger_and_first_main_phase_mana() -> void:
	var d := _db_lands()
	var hydra_def := d.definition_for("Test Hydra")
	var hit := false
	for a in hydra_def.abilities:
		var ab := a as Ability
		if ab.kind == &"TRIGGERED" and str(ab.trigger.get("on", "")) == "SPELL_CAST" and not (ab.trigger.get("filter", {}) as Dictionary).has("controller"):
			hit = true
	assert_true(hit, "any player's spell sets it off")
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Raptor")
	engine.state.active_player_id = 0
	engine.triggers._on_step_begin(engine, EngineEnums.Step.PRECOMBAT_MAIN, 0)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the trigger waits on the stack")
	engine.resolve_top()
	assert_eq(engine.mana.pool(0).g, 2, "GG added")


# --- Grants, control, energy, restrictions, bands ---------------------------------------------------------------------

func _db_more() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Lantern", "{3}", 3, "Artifact", "Lands you control have \"{T}: Add one mana of any color.\""))
	m.add(_row("Test Forest", "", 0, "Basic Land — Forest", ""))
	m.add(_row("Test Mind Control", "{3}{U}{U}", 5, "Enchantment — Aura", "Enchant creature\nYou control enchanted creature."))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Giant", "{5}", 5, "Creature — Giant", "", "5", "5"))
	m.add(_row("Test Rhonas", "{2}{G}", 3, "Creature — God", "Test Rhonas can't attack or block unless you control another creature with power 4 or greater.", "5", "5"))
	m.add(_row("Test Troll", "{2}{G}", 3, "Creature — Troll", "Each creature you control with power 4 or greater can't be blocked by more than one creature.", "4", "4"))
	m.add(_row("Test Charger", "{G}", 1, "Creature — Beast", "", "1", "1"))
	m.add(_row("Test Reactor", "{2}", 2, "Artifact", "When Test Reactor enters, you get {E}{E}{E}.\n{T}, Pay {E}{E}: Draw a card."))
	m.add(_row("Test Bog", "", 0, "Land", "{T}, Remove three spore counters from Test Bog: Add {G}{G}{G}."))
	m.add(_row("Test Isleguard", "{1}{U}", 2, "Creature — Wall", "When you control no Islands, sacrifice Test Isleguard.", "2", "2"))
	m.add(_row("Test Island", "", 0, "Basic Land — Island", ""))
	m.add(_row("Test Warden", "{2}", 2, "Artifact Creature — Golem", "Protection from artifacts", "2", "2"))
	m.add(_row("Test Rock", "{1}", 1, "Artifact", ""))
	m.add(_row("Test Mage", "{1}{U}", 2, "Creature — Wizard", "Level up {2}\nLEVEL 1-2\n1/3\n{T}: Draw a card.\nLEVEL 3+\n2/4\n{T}: Draw two cards.", "0", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_lantern_gives_every_land_a_mana_ability() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var forest := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Forest")
	var theirs := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Forest")
	var before := engine.layers.abilities_for(engine.state, forest).size()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lantern")
	assert_eq(engine.layers.abilities_for(engine.state, forest).size(), before + 1, "my land gains the ability")
	assert_eq(engine.layers.abilities_for(engine.state, theirs).size(), before, "their land does not")


func test_control_magic_style_aura_steals_and_gives_back() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var aura := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Mind Control")
	aura.attached_to = bear.object_id
	engine.sba.check(engine)
	assert_eq(bear.controller_id, 0, "I control it now")
	engine.state.zones.move(aura.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	engine.sba.check(engine)
	assert_eq(bear.controller_id, 1, "it goes back to its owner")


func test_rhonas_needs_a_big_friend_and_troll_limits_blockers() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var rhonas := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Rhonas")
	rhonas.summoned_this_turn = false
	assert_false(engine.legal_attacker_ids(0).has(rhonas.object_id), "alone it can't attack")
	var giant := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Giant")
	giant.summoned_this_turn = false
	assert_true(engine.legal_attacker_ids(0).has(rhonas.object_id), "with a power-5 friend it can")
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Troll")
	var small := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Charger")
	assert_true(engine.single_blocker_only(giant), "a power 4 or greater creature can't be double-blocked")
	assert_false(engine.single_blocker_only(small), "a small one can")


func test_energy_is_gained_and_paid() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var reactor := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Reactor")
	var fxs: Array = []
	var pay_ab: Ability = null
	for a in (reactor.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"TRIGGERED":
			fxs.append_array((a as Ability).effects)
		elif (a as Ability).kind == &"ACTIVATED":
			pay_ab = a
	assert_true(not fxs.is_empty() and pay_ab != null, "both lines were read")
	engine.put_synthetic(reactor, 0, fxs, {})
	engine.resolve_top()
	assert_eq(engine.state.players[0].energy, 3, "three energy")
	assert_true(engine.costs.can_pay(reactor, pay_ab), "can pay two")
	engine.costs.pay(reactor, pay_ab)
	assert_eq(engine.state.players[0].energy, 1, "two spent")
	reactor.tapped = false
	assert_false(engine.costs.can_pay(reactor, pay_ab), "not enough left")


func test_removing_several_counters_as_a_cost() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var bog := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bog")
	var ab: Ability = null
	for a in (bog.definition as CardDefinition).abilities:
		for c in (a as Ability).costs:
			if str((c as AbilityCost).kind) == "REMOVE_COUNTER":
				ab = a
	assert_true(ab != null, "the counter-cost mana ability was read")
	bog.counters["spore"] = 2
	assert_false(engine.costs.can_pay(bog, ab), "two counters aren't three")
	bog.counters["spore"] = 3
	assert_true(engine.costs.can_pay(bog, ab))
	engine.costs.pay(bog, ab)
	assert_eq(int(bog.counters.get("spore", 0)), 0)


func test_state_trigger_when_you_control_no_islands() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Isleguard")
	engine.triggers.check_state(engine)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "no Island: it triggers")
	engine.resolve_top()
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids.size(), 0, "and it is sacrificed")


func test_protection_from_a_card_type_and_etb_rules() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var warden := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Warden")
	var rock := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Rock")
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	assert_true(engine.protected_from(warden, rock), "protection from artifacts")
	assert_false(engine.protected_from(warden, bear))
	var rule := EtbRules.parse(_etb_def("~ enters tapped unless you control three or more other Swamps."))
	assert_eq(str(rule.get("kind")), "MIN_OTHER_TYPE")
	var rule2 := EtbRules.parse(_etb_def("~ enters tapped unless you have two or more opponents."))
	assert_true(EtbRules.tapped_on_entry(rule2, [], [], 20, 1), "tapped in a 1v1")
	assert_false(EtbRules.tapped_on_entry(rule2, [], [], 20, 3), "untapped with three opponents")


func _etb_def(text: String) -> CardDefinition:
	var def := CardDefinition.new()
	def.name = "Test Land"
	def.type_line = "Land"
	def.oracle_text = text
	return def


func test_level_band_ability_works_only_inside_its_band() -> void:
	var d := _db_more()
	var engine := Fixtures.empty_engine_1v1()
	var mage := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Mage")
	var gated := 0
	for a in (mage.definition as CardDefinition).abilities:
		var ab := a as Ability
		for r in ab.restrictions:
			if r is Dictionary and (r as Dictionary).has("cond") and ((r as Dictionary)["cond"] as Dictionary).has("counter_band"):
				gated += 1
	assert_eq(gated, 2, "both band abilities are gated on the level counters")
	var lvl1: Ability = null
	for a in (mage.definition as CardDefinition).abilities:
		if str((a as Ability).text) == "{T}: Draw a card.":
			lvl1 = a
	assert_true(lvl1 != null)
	mage.summoned_this_turn = false
	engine.state.active_player_id = 0
	engine.priority.give(engine.state, 0)
	assert_true(engine._activation_reason(mage, lvl1) != "LEGAL", "not in the band at level 0")
	mage.counters["level"] = 1
	assert_eq(engine._activation_reason(mage, lvl1), "LEGAL", "in the band at level 1")
	mage.counters["level"] = 3
	assert_true(engine._activation_reason(mage, lvl1) != "LEGAL", "past the band at level 3")


func test_time_stop_exiles_the_stack_and_ends_the_turn() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Stop", "{4}{U}{U}", 6, "Instant", "End the turn."))
	m.add(_row("Test Zap", "{1}{R}", 2, "Instant", "Test Zap deals 2 damage to any target."))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	var turn_before: int = engine.state.turn_number
	var zap := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.HAND, "Test Zap")
	var zfx: Array = []
	for a in (zap.definition as CardDefinition).abilities:
		zfx.append_array((a as Ability).effects)
	engine.put_synthetic(zap, 1, zfx, {})
	var stop := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Stop")
	var sfx: Array = []
	for a in (stop.definition as CardDefinition).abilities:
		sfx.append_array((a as Ability).effects)
	assert_true(not sfx.is_empty(), "End the turn was read")
	engine.put_synthetic(stop, 0, sfx, {})
	engine.resolve_top()
	assert_true((engine.state.stack as MagicStack).is_empty(), "the stack was emptied")
	assert_eq(engine.state.active_player_id, 1, "it is the next player's turn")
	assert_eq(engine.state.turn_number, turn_before + 1)


# --- Extra turns, parity exile, piles, library searches, combat rules -------------------------------------------------

func _db_misc2() -> CardDatabase:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Time Walk", "{1}{U}", 2, "Sorcery", "Take an extra turn after this one."))
	m.add(_row("Test Last Chance", "{1}{R}{R}", 3, "Sorcery", "Take an extra turn after this one. At the beginning of that turn's end step, you lose the game."))
	m.add(_row("Test Parity", "{3}{W}{W}", 5, "Sorcery", "Choose odd or even. Exile each creature with mana value of the chosen quality."))
	m.add(_row("Test Piles", "{3}{U}", 4, "Instant", "Reveal the top five cards of your library. An opponent separates those cards into two piles. Put one pile into your hand and the other into your graveyard."))
	m.add(_row("Test Seeker", "{1}{G}", 2, "Sorcery", "Search your library for a basic land card, reveal it, then shuffle and put that card on top."))
	m.add(_row("Test Verge", "", 0, "Land", "{2}, {T}, Sacrifice Test Verge: Search your library for a Forest card and a Plains card, put them onto the battlefield tapped, then shuffle."))
	m.add(_row("Test Forest", "", 0, "Basic Land — Forest", ""))
	m.add(_row("Test Plains", "", 0, "Basic Land — Plains", ""))
	m.add(_row("Test Lure", "{2}", 2, "Creature — Beast", "Test Lure must be blocked if able.", "2", "2"))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Giant", "{5}", 5, "Creature — Giant", "", "5", "5"))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	m.add(_row("Test Loner", "{1}", 1, "Creature — Test", "Test Loner can't attack or block alone.", "3", "3"))
	var d := CardDatabase.new()
	d.setup(cat)
	return d


func test_extra_turns_go_first_and_can_cost_the_game() -> void:
	var d := _db_misc2()
	var engine := Fixtures.empty_engine_1v1()
	engine.state.active_player_id = 0
	_cast_effects(engine, d, 0, "Test Time Walk")
	assert_eq(engine.state.extra_turns.size(), 1, "an extra turn is waiting")
	var turn_before: int = engine.state.turn_number
	engine.turn._rotate_turn(engine.state)
	assert_eq(engine.state.active_player_id, 0, "the same player goes again")
	assert_eq(engine.state.turn_number, turn_before + 1)
	assert_true(engine.state.extra_turns.is_empty())
	var engine2 := Fixtures.empty_engine_1v1()
	engine2.state.active_player_id = 0
	_cast_effects(engine2, d, 0, "Test Last Chance")
	assert_true(bool((engine2.state.extra_turns[0] as Dictionary).get("lose", false)), "the drawback was read")
	engine2.turn._rotate_turn(engine2.state)
	engine2.state.step = EngineEnums.Step.END
	engine2.turn._start_tba(engine2, engine2.state)
	assert_true(engine2.state.players[0].lost, "you lose at that turn's end step")


func test_extinction_event_exiles_the_chosen_parity() -> void:
	var d := _db_misc2()
	var engine := Fixtures.empty_engine_1v1()
	var mine := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Giant")
	var theirs1 := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var theirs2 := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_cast_effects(engine, d, 0, "Test Parity")
	assert_true(_on_bf(engine, mine), "my odd creature stays: the bot chose even")
	assert_false(_on_bf(engine, theirs1))
	assert_false(_on_bf(engine, theirs2))


func test_fact_or_fiction_splits_and_gives_one_pile() -> void:
	var d := _db_misc2()
	var engine := Fixtures.empty_engine_1v1()
	for name_ in ["Test Giant", "Test Bear", "Test Bear", "Test Filler", "Test Filler"]:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, name_)
	_cast_effects(engine, d, 0, "Test Piles")
	var hand := engine.hand_size(0)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_true(hand >= 2, "a pile came to hand")
	assert_true(gy.object_ids.size() >= 1, "the other pile went to the graveyard")
	assert_eq(hand - 1 + gy.object_ids.size(), 5, "all five cards went somewhere (the helper leaves the spell in hand)")


func test_search_puts_the_card_on_top_and_finds_two_kinds() -> void:
	var d := _db_misc2()
	var engine := Fixtures.empty_engine_1v1()
	for _i in 3:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var forest := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Forest")
	_cast_effects(engine, d, 0, "Test Seeker")
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	assert_eq(int(lib.object_ids[0]), forest.object_id, "the land is on top")
	var engine2 := Fixtures.empty_engine_1v1()
	var verge := Fixtures.spawn_named(engine2, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Verge")
	Fixtures.spawn_named(engine2, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Forest")
	Fixtures.spawn_named(engine2, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Plains")
	Fixtures.spawn_named(engine2, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var fxs: Array = []
	for a in (verge.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"ACTIVATED":
			fxs.append_array((a as Ability).effects)
	assert_true(not fxs.is_empty(), "the Verge was read")
	engine2.put_synthetic(verge, 0, fxs, {})
	engine2.resolve_top()
	var bf: Zone = engine2.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	var kinds := {}
	for oid in bf.object_ids:
		var o: GameObject = engine2.state.objects.get(oid)
		if o != null:
			kinds[(o.definition as CardDefinition).name] = true
	assert_true(kinds.has("Test Forest") and kinds.has("Test Plains"), "both lands arrived")


func test_must_be_blocked_and_alone_rules() -> void:
	var d := _db_misc2()
	var engine := Fixtures.empty_engine_1v1()
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.COMBAT
	engine.state.step = EngineEnums.Step.DECLARE_BLOCKERS
	engine.state.combat = CombatState.new()
	(engine.state.combat as CombatState).defending_player_id = 1
	engine.priority.give(engine.state, 1)
	var lure := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lure")
	lure.tapped = true
	(engine.state.combat as CombatState).attacker_ids.append(lure.object_id)
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.summoned_this_turn = false
	var act := GameAction.new()
	act.kind = GameAction.Kind.DECLARE_BLOCKERS
	act.player_id = 1
	act.extra = {"blockers": {}}
	assert_false(engine.submit(act).ok, "an unblocked 'must be blocked' attacker is rejected while a creature could block")
	var act2 := GameAction.new()
	act2.kind = GameAction.Kind.DECLARE_BLOCKERS
	act2.player_id = 1
	act2.extra = {"blockers": {lure.object_id: [bear.object_id]}}
	assert_true(engine.submit(act2).ok, "blocking it is fine")
	var loner := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Loner")
	assert_true(engine._printed_alone_rule(loner, true), "can't attack alone is read from its text")


func test_bot_equips_a_creature_and_levels_up() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Sword", "{1}", 1, "Artifact — Equipment", "Equipped creature gets +2/+0.\nEquip {1}"))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Swamp", "", 0, "Basic Land — Swamp", "{T}: Add {B}."))
	var d := CardDatabase.new()
	d.setup(cat)
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = d
	session.you_seat = 0
	var engine := session.engine
	for pid in 2:
		for _i in 3:
			Fixtures.spawn_named(engine, d, pid, EngineEnums.ZoneId.LIBRARY, "Test Swamp")
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.summoned_this_turn = false
	var sword := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Sword")
	for _j in 2:
		var land := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Swamp")
		land.summoned_this_turn = false
	engine.state.active_player_id = 1
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.priority.give(engine.state, 1)
	session.ai_take_turn(1)
	assert_eq(sword.attached_to, bear.object_id, "the bot equipped its creature")


# --- More trigger headers, exile-instead, counters by colour ---------------------------------------------------------

func _trigger_on(def: CardDefinition) -> Array:
	var out: Array = []
	for a in def.abilities:
		if (a as Ability).kind == &"TRIGGERED":
			out.append(str((a as Ability).trigger.get("on", "")))
	return out


func test_more_trigger_headers_are_read() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Brute", "{2}", 2, "Creature — Brute", "Whenever Test Brute becomes blocked, it gets +1/+1 until end of turn.\nWhen Test Brute leaves the battlefield, you gain 1 life.\nWhenever Test Brute attacks alone, you gain 1 life.", "2", "2"))
	m.add(_row("Test Twin", "{2}", 2, "Creature — Wizard", "Whenever you cast your second spell each turn, draw a card.\nWhenever Test Twin blocks or becomes blocked by a creature, you gain 1 life.", "1", "1"))
	m.add(_row("Test Edge", "{1}", 1, "Artifact — Equipment", "Whenever equipped creature deals combat damage to a player, draw a card.\nEquip {1}"))
	var d := CardDatabase.new()
	d.setup(cat)
	var brute := _trigger_on(d.definition_for("Test Brute"))
	assert_true(brute.has("BECOMES_BLOCKED") and brute.has("LEAVES") and brute.has("SELF_ATTACKS_ALONE"), "Brute: %s" % str(brute))
	var twin := _trigger_on(d.definition_for("Test Twin"))
	assert_true(twin.has("SPELL_CAST") and twin.has("BLOCKS") and twin.has("BECOMES_BLOCKED"), "Twin: %s" % str(twin))
	var edge := _trigger_on(d.definition_for("Test Edge"))
	assert_true(edge.has("COMBAT_DAMAGE_TO_PLAYER"), "Edge: %s" % str(edge))


func test_opponent_exiles_a_creature_they_control() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Banish", "{2}{W}", 3, "Sorcery", "Target opponent exiles a creature they control."))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var spell := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.HAND, "Test Banish")
	var fxs: Array = []
	for a in (spell.definition as CardDefinition).abilities:
		fxs.append_array((a as Ability).effects)
	assert_true(not fxs.is_empty(), "read")
	var e := engine.put_synthetic(spell, 0, fxs, {})
	e.targets = [TargetingManager.encode_player(1)]
	engine.resolve_top()
	assert_false(_on_bf(engine, bear), "their creature left")
	var ex: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1)
	assert_eq(ex.object_ids.size(), 1, "it was exiled, not killed")


func test_counter_target_coloured_spell_is_read() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Hush", "{U}", 1, "Instant", "Counter target blue spell."))
	m.add(_row("Test Hush Two", "{U}", 1, "Instant", "Counter target red or green spell with mana value 3 or less."))
	var d := CardDatabase.new()
	d.setup(cat)
	for nm in ["Test Hush", "Test Hush Two"]:
		var found := false
		for a in d.definition_for(nm).abilities:
			for fx in (a as Ability).effects:
				if str((fx as AbilityEffect).kind) == "COUNTER_SPELL":
					found = true
		assert_true(found, "%s was read" % nm)


func test_a_bot_turn_rebuilds_the_table_view_once() -> void:
	var cat := Fixtures.memory_catalog()
	(cat as CatalogSource.Memory).add(_row("Test Swamp", "", 0, "Basic Land — Swamp", "{T}: Add {B}."))
	var d := CardDatabase.new()
	d.setup(cat)
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = d
	session.you_seat = 0
	for pid in 2:
		for _i in 4:
			Fixtures.spawn_named(session.engine, d, pid, EngineEnums.ZoneId.LIBRARY, "Test Swamp")
		Fixtures.spawn_named(session.engine, d, pid, EngineEnums.ZoneId.HAND, "Test Swamp")
	session.engine.state.active_player_id = 1
	session.engine.state.phase = EngineEnums.Phase.MAIN_1
	session.engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	session.engine.priority.give(session.engine.state, 1)
	GameSession.perf = {}
	session.ai_take_turn(1)
	var row: Array = GameSession.perf.get("rebuild_view", [0, 0])
	assert_true(int(row[1]) <= 1, "the whole turn rebuilt the view %d times" % int(row[1]))
