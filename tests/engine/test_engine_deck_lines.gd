@tool
extends McpTestSuite

## Lines from the saved precon decks that the engine used to skip (the "!" cards): each is read from its real Oracle text and
## then played, so the test shows the card does what it says, not only that its text parsed.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_deck_lines"


func _row(card_name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "") -> Dictionary:
	return {name = card_name, oracle_id = card_name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Test Decree", "{2}{W}", 3, "Enchantment", "Whenever a creature attacks you or a planeswalker you control, that creature's controller loses 1 life."))
	m.add(_row("Test Vizier", "{3}", 3, "Artifact", "{T}: Add {R} for each tapped land your opponents control."))
	m.add(_row("Test Dragonfire", "{3}{R}", 4, "Creature — Dragon", "Whenever you cast a noncreature or Dragon spell, Test Dragonfire deals 1 damage to each opponent.", "4", "4"))
	m.add(_row("Test Dragon", "{2}{R}", 3, "Creature — Dragon", "", "2", "2"))
	m.add(_row("Test Bolt", "{R}", 1, "Instant", "Test Bolt deals 3 damage to any target."))
	m.add(_row("Test Zombie", "{B}", 1, "Creature — Zombie", "", "2", "2"))
	m.add(_row("Test Wight", "{2}{B}", 3, "Creature — Zombie", "Test Wight gets +1/+1 for each creature card in your opponents' graveyards.", "2", "2"))
	m.add(_row("Forest", "", 0, "Basic Land — Forest", "{T}: Add {G}."))
	m.add(_row("Test Soulless", "{3}", 3, "Creature — Zombie", "~'s power and toughness are each equal to the number of Zombies on the battlefield plus the number of Zombie cards in all graveyards.", "*", "*"))
	m.add(_row("Test Angel", "{4}", 4, "Artifact Creature — Angel", "Flying\nCreatures you control can't have -1/-1 counters put on them.", "4", "4"))
	m.add(_row("Test Tyrant", "{4}{R}{R}", 6, "Creature — Dragon", "You don't lose unspent red mana as steps and phases end.", "5", "5"))
	m.add(_row("Test Winnower", "{3}", 3, "Creature — Eldrazi", "Your opponents can't block with creatures with even mana values.\nYour opponents can't cast spells with even mana values.", "4", "4"))
	m.add(_row("Test Maneuver", "{1}{W}", 2, "Instant", "If you control a commander, you may cast ~ without paying its mana cost.\nCreatures you control gain indestructible until end of turn."))
	m.add(_row("Test Charm", "{B}{R}", 2, "Instant", "Each creature deals 1 damage to its controller."))
	m.add(_row("Test Decree2", "{7}{B}{B}", 9, "Sorcery", "Draw a card.
Cycling {4}{B}{B}\nWhen you cycle ~, all creatures get -2/-2 until end of turn."))
	m.add(_row("Test Regent", "{3}{R}{R}", 5, "Creature — Dragon", "Flying\nWhenever a Dragon you control becomes the target of a spell or ability an opponent controls, ~ deals 3 damage to that player.", "4", "4"))
	m.add(_row("Test Rakdos", "{3}{B}{R}", 5, "Legendary Creature — Devil", "Creature spells you cast cost {1} less to cast for each 1 life your opponents have lost this turn.", "6", "6"))
	m.add(_row("Test Gargaroth", "{3}{G}{G}", 5, "Creature — Elemental", "Whenever ~ attacks or blocks, choose one —\n• Create a 3/3 green Beast creature token.\n• You gain 3 life.\n• Draw a card.", "6", "6"))
	m.add(_row("Test Thrasher", "{2}{R}", 3, "Creature — Dragon", "Flying\nWhenever one or more Dragons you control deal combat damage to an opponent, choose one that hasn't been chosen this turn —\n• Destroy target artifact that opponent controls.\n• ~ deals 4 damage to each other opponent.\n• Draw a card.", "3", "3"))
	m.add(_row("Test Geyser", "{R}{R}", 2, "Instant", "Add {R} for each tapped land your opponents control."))
	m.add(_row("Test Archfiend", "{4}{B}{B}", 6, "Creature — Demon", "Flying\nAt the beginning of each end step, each opponent loses life equal to the life that player lost this turn.", "6", "6"))
	m.add(_row("Test Spire", "", 0, "Land", "{T}: Add {U} or {R}.\n{U}{R}: Until end of turn, ~ becomes a 2/1 blue and red Elemental creature with \"During your turn, ~ has first strike.\" It's still a land."))
	m.add(_row("Test Konrad", "{3}{B}", 4, "Legendary Creature — Human Knight", "Whenever another creature dies, or a creature card is put into a graveyard from anywhere other than the battlefield, or a creature card leaves your graveyard, ~ deals 1 damage to each opponent.", "5", "4"))
	m.add(_row("Test Triplets", "{1}{G}{G}", 3, "Creature — Elemental", "When ~ enters, if it isn't a token, create two tokens that are copies of it.\nWhen ~ dies, put a number of +1/+1 counters equal to its power on each creature you control named ~.", "3", "3"))
	m.add(_row("Test Bontu", "{3}{B}{B}", 5, "Legendary Creature — Zombie God", "When ~ dies or is put into exile from the battlefield, you may put it into its owner's library third from the top.", "5", "6"))
	m.add(_row("Test Pumper", "{1}", 1, "Artifact", "{T}: Target creature gets +1/+1 until end of turn."))
	m.add(_row("Test Etb", "{2}", 2, "Creature — Wizard", "When ~ enters, target creature gets +2/+2 until end of turn.", "1", "1"))
	m.add(_row("Test Ignition", "{R}", 1, "Sorcery", "Target creature you control deals damage equal to its power to each other creature and each opponent."))
	m.add(_row("Test Bite", "{R}", 1, "Sorcery", "Target creature you control deals damage equal to its power to target creature you don't control."))
	m.add(_row("Test Ridge", "", 0, "Land", "{1}, {T}: Add {B}{R}."))
	m.add(_row("Mountain", "", 0, "Basic Land — Mountain", "{T}: Add {R}."))
	m.add(_row("Test Regisaur", "{3}{R}", 4, "Creature — Dinosaur", "Whenever this creature attacks, it deals 1 damage to any target.", "4", "4"))
	m.add(_row("Test Windfall", "{2}{U}", 3, "Sorcery", "Each player discards their hand, then draws cards equal to the greatest number of cards a player discarded this way."))
	m.add(_row("Test Evacuation", "{3}{U}{U}", 5, "Instant", "Return all creatures to their owners' hands."))
	m.add(_row("Test Decimate", "{2}{R}{G}", 4, "Sorcery", "Destroy target artifact, target creature, target enchantment, and target land."))
	m.add(_row("Test Wanderings", "{2}{G}", 3, "Sorcery", "Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.\nThreshold — If there are seven or more cards in your graveyard, instead search your library for up to three basic land cards, put them onto the battlefield tapped, then shuffle."))
	m.add(_row("Test Oracle", "{1}{U}", 2, "Creature — Merfolk", "When ~ enters, reveal the top card of your library. If it's a land card, put it onto the battlefield. Otherwise, put that card into your hand.", "1", "1"))
	m.add(_row("Test Wastenot", "{1}{B}", 2, "Enchantment", "Whenever an opponent discards a noncreature, nonland card, draw a card."))
	m.add(_row("Test Upheaval", "{4}{B}", 5, "Sorcery", "Put target creature card from a graveyard onto the battlefield under your control. It gains haste."))
	m.add(_row("Test Worms", "{3}{B}{G}", 5, "Sorcery", "Create a 1/1 black and green Worm creature token for each land card in your graveyard."))
	m.add(_row("Test Cloak", "{3}", 3, "Artifact — Equipment", "Equipped creature can't be blocked and has shroud.\nEquip {2}"))
	m.add(_row("Test Chimera", "{1}{U}{R}", 3, "Creature — Chimera", "Flying\n~'s power is equal to the number of instant and sorcery cards in your graveyard.", "*", "4"))
	m.add(_row("Test Spire2", "", 0, "Land", "This land enters tapped.\nWhen this land enters, sacrifice it unless you pay {1}.\n{T}: Add one mana of any color."))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Gisa", "{2}{B}", 3, "Legendary Creature — Human Wizard", "{B}, {T}, Sacrifice another creature: Create X 2/2 black Zombie creature tokens, where X is the sacrificed creature's power.", "2", "2"))
	m.add(_row("Test Rishkar", "{2}{G}", 3, "Legendary Creature — Human Peasant", "Each creature you control with a counter on it has \"{T}: Add {G}.\"", "2", "2"))
	m.add(_row("Test Thicket", "{2}{G}", 3, "Enchantment", "At the beginning of your end step, draw two cards if you control the creature with the greatest power or tied for the greatest power."))
	m.add(_row("Test Mimic", "{2}", 2, "Land", "{2}: Test Mimic becomes a copy of target artifact, creature, enchantment, or land until end of turn."))
	m.add(_row("Test Kalitas", "{2}{B}{B}", 4, "Legendary Creature — Vampire Warrior", "If a nontoken creature an opponent controls would die, instead exile that card and create a 2/2 black Zombie creature token.", "3", "4"))
	m.add(_row("Test Gravecrawler", "{B}", 1, "Creature — Zombie", "Test Gravecrawler can't block.\nYou may cast Test Gravecrawler from your graveyard as long as you control a Zombie.", "2", "1"))
	m.add(_row("Test Recruit", "{2}{B}", 3, "Sorcery", "Return target creature card from your graveyard to your hand. If it's a Zombie card, draw a card."))
	m.add(_row("Test Zul", "{3}{B}", 4, "Legendary Creature — Zombie Wizard", "{T}: You may cast target Zombie creature card from your graveyard this turn.", "3", "3"))
	m.add(_row("Test Pulse", "{2}{R}", 3, "Enchantment", "Whenever an opponent taps a land for mana, that land doesn't untap during its controller's next untap step."))
	m.add(_row("Test Forest", "", 0, "Basic Land — Forest", "({T}: Add {G}.)"))
	m.add(_row("Test Stunner", "{2}", 2, "Creature — Test", "Whenever Test Stunner attacks while you don't control another Dinosaur, put a stun counter on it.", "2", "2"))
	m.add(_row("Test Syphon", "{2}{B}", 3, "Sorcery", "Each other player sacrifices a creature. You create a 2/2 black Zombie creature token for each creature sacrificed this way."))
	m.add(_row("Test Soldiers", "{X}{W}", 1, "Sorcery", "Create X 1/1 white Soldier creature tokens. If X is 5 or more, destroy all other creatures."))
	m.add(_row("Test Swap", "{2}{U}", 3, "Sorcery", "Two target players exchange life totals. You create an X/X colorless Horror artifact creature token, where X is the difference between those players' life totals."))
	m.add(_row("Test Beasts", "{4}{G}", 5, "Sorcery", "For each creature your opponents control, create a 4/4 green Phyrexian Beast creature token. Each of those tokens fights a different one of those creatures."))
	m.add(_row("Test Verdict", "{3}{B}", 4, "Sorcery", "Starting with the next opponent in turn order, each player chooses a creature you don't control. Destroy the chosen creatures."))
	m.add(_row("Test Rite", "{2}{U}", 3, "Sorcery", "Draw X cards, then discard X cards. Create a 1/1 white Spirit creature token with flying for each card type among cards discarded this way."))
	m.add(_row("Test Lurker", "{2}{R}", 3, "Creature — Dragon", "Whenever Test Lurker attacks, it deals 4 damage to any target and 3 damage to each of up to two other targets.", "4", "4"))
	m.add(_row("Test Parallax", "{3}{W}", 4, "Sorcery", "Exile target nonland permanent. Each player other than its controller creates a token that's a copy of it."))
	m.add(_row("Test Sacwatch", "{2}", 2, "Enchantment", "Whenever you sacrifice a permanent, you gain 1 life."))
	m.add(_row("Test Discardwatch", "{2}", 2, "Enchantment", "Whenever you discard a card, you gain 1 life."))
	m.add(_row("Test Tokenwatch", "{2}", 2, "Enchantment", "Whenever you create one or more creature tokens, you gain 1 life."))
	db = CardDatabase.new()
	db.setup(m)


func _effects(obj: GameObject, kind: StringName = &"") -> Array:
	var out: Array = []
	for a in (obj.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab == null:
			continue
		if kind == &"" or ab.kind == kind:
			out.append_array(ab.effects)
	return out


func _count(engine: RulesEngine, zone: int, owner: int, name_part: String = "") -> int:
	var n := 0
	var z: Zone = engine.state.zones.get_zone(zone, owner) if zone != EngineEnums.ZoneId.BATTLEFIELD else engine.state.zones.get_zone(zone)
	for oid in z.object_ids:
		var o: GameObject = engine.state.objects[oid]
		if zone == EngineEnums.ZoneId.BATTLEFIELD and o.controller_id != owner:
			continue
		if name_part == "" or (o.definition as CardDefinition).name.contains(name_part) or (o.definition as CardDefinition).type_line.contains(name_part):
			n += 1
	return n


func _run(engine: RulesEngine, source: GameObject, controller: int, effects: Array, ctx: Dictionary = {}, targets: Array = []) -> StackEntry:
	var e := engine.put_synthetic(source, controller, effects, ctx)
	e.targets = targets
	engine.resolve_top()
	return e


func test_every_line_is_read() -> void:
	for n in ["Test Decree", "Test Vizier", "Test Dragonfire", "Test Wight", "Test Gisa", "Test Rishkar", "Test Thicket", "Test Mimic", "Test Kalitas",
			"Test Gravecrawler", "Test Recruit", "Test Zul", "Test Pulse", "Test Stunner", "Test Syphon", "Test Soldiers", "Test Swap", "Test Beasts",
			"Test Verdict", "Test Rite", "Test Lurker", "Test Parallax", "Test Sacwatch", "Test Discardwatch", "Test Tokenwatch"]:
		assert_eq(db.unread_lines(db.definition_for(n)).size(), 0, "%s: %s" % [n, str(db.unread_lines(db.definition_for(n)))])


func test_the_decree_makes_an_attacker_lose_life() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var decree := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Decree")
	var life := engine.state.players[1].life
	_run(engine, decree, 0, _effects(decree, &"TRIGGERED"), {player_id = 1})
	assert_eq(engine.state.players[1].life, life - 1, "the attacker's controller lost 1")
	assert_eq(engine.state.players[0].life, 40, "and the Decree's controller did not")


func test_a_mana_ability_counts_what_it_is_told_to_count() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var vizier := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Vizier")
	for _i in 3:
		var land := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Forest")
		land.tapped = true
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Forest")  ## untapped: not counted
	engine.state.active_player_id = 0
	engine.priority.give(engine.state, 0)
	assert_true(engine.submit(Fixtures.activate_mana(0, vizier.object_id)).ok)
	assert_eq(engine.state.players[0].mana.total(), 3, "one red for each tapped land the opponent controls")


func test_a_noncreature_or_dragon_spell_triggers_the_dragon() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var dragon := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Dragonfire")
	var stack := engine.state.stack as MagicStack
	for pair in [["Test Bolt", 1], ["Test Dragon", 1], ["Test Zombie", 0]]:
		var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, str(pair[0]))
		var before := stack.size()
		engine.triggers.on_spell_cast(engine, spell, 0)
		assert_eq(stack.size() - before, int(pair[1]), "%s -> %d trigger(s)" % [str(pair[0]), int(pair[1])])
		while stack.size() > before:
			engine.resolve_top()
	assert_true(dragon != null)


func test_a_wight_grows_with_the_other_graveyards() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var wight := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Wight")
	assert_eq(engine.power_of(wight), 2)
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Zombie")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")  ## your own graveyard does not count
	assert_eq(engine.power_of(wight), 4, "+1/+1 for each creature card in the opponent's graveyard")


func test_gisa_makes_tokens_equal_to_the_sacrificed_power() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var gisa := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Gisa")
	gisa.summoned_this_turn = false  ## a {T} ability needs a creature that has been under your control since the turn began
	var fodder := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	fodder.counters["+1/+1"] = 1  ## a 3/3 when it is sacrificed
	var ab: Ability = null
	for a in (gisa.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"ACTIVATED":
			ab = a
	assert_true(ab != null, "the ability was read")
	engine.mana.add(0, ManaCost.parse("{B}"))
	engine.state.active_player_id = 0
	engine.priority.give(engine.state, 0)
	var activated := engine.submit(Fixtures.activate_ability(0, gisa.object_id, ab.ability_id))
	assert_true(activated.ok, "activation: %s" % activated.error)
	if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		engine.submit(Fixtures.pay_mana(0))
		engine.submit(Fixtures.confirm_pay(0))
	engine.resolve_top()
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Zombie"), 3, "three 2/2 Zombies for a power-3 creature")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Bear"), 0, "the Bear was sacrificed")


func test_rishkar_gives_a_mana_ability_to_creatures_with_counters() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Rishkar")
	var plain := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var grown := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	grown.counters["+1/+1"] = 1
	var plain_mana := 0
	for a in engine.layers.abilities_for(engine.state, plain):
		if (a as Ability).kind == &"MANA":
			plain_mana += 1
	var grown_mana := 0
	for a2 in engine.layers.abilities_for(engine.state, grown):
		if (a2 as Ability).kind == &"MANA":
			grown_mana += 1
	assert_eq(plain_mana, 0, "no counter, no mana ability")
	assert_eq(grown_mana, 1, "a counter: {T}: Add {G}")


func test_the_thicket_condition_is_about_the_greatest_power() -> void:
	var engine := Fixtures.empty_engine_1v1()
	for _i in 4:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Bear")
	var thicket := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Thicket")
	var mine := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var theirs := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	theirs.counters["+1/+1"] = 2  ## the rival's creature is bigger
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	var trig: Ability = null
	for a in (thicket.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"TRIGGERED":
			trig = a
	var cond: Dictionary = (trig.effects[0] as AbilityEffect).params.get("if_cond", {})
	assert_true(bool(cond.get("greatest_power", false)), "the condition was read: %s" % str((trig.effects[0] as AbilityEffect).params))
	assert_false(engine.layers.condition_met(engine.state, thicket, cond), "not while the rival has the biggest creature")
	mine.counters["+1/+1"] = 2  ## tied for the greatest
	assert_true(engine.layers.condition_met(engine.state, thicket, cond), "tied counts")
	assert_eq(hand.size(), 0)


func _type_line(obj: GameObject) -> String:
	return (obj.definition as CardDefinition).type_line


func test_mimic_becomes_a_copy_until_end_of_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mimic := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Mimic")
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, mimic, 0, _effects(mimic, &"ACTIVATED"), {}, [bear.object_id])
	assert_true(_type_line(mimic).contains("Bear"), "it is a Bear now: %s" % _type_line(mimic))
	assert_true(engine.is_creature_now(mimic))
	engine.layers.clear_until_eot(engine.state)
	assert_true(_type_line(mimic).contains("Land"), "and a land again at end of turn: %s" % _type_line(mimic))


func test_kalitas_exiles_the_dying_creature_and_makes_a_zombie() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Kalitas")
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	engine.destroy_permanent(bear)
	assert_eq(_count(engine, EngineEnums.ZoneId.GRAVEYARD, 1), 0, "it did not die")
	assert_eq(_count(engine, EngineEnums.ZoneId.EXILE, 1), 1, "it was exiled")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Zombie"), 1, "and Kalitas's controller got a Zombie")
	var own := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	engine.destroy_permanent(own)
	assert_eq(_count(engine, EngineEnums.ZoneId.GRAVEYARD, 0), 1, "the controller's own creatures die as usual")


func _graveyard_mode(engine: RulesEngine, obj: GameObject) -> bool:
	for opt in engine.kw.cast_options(obj.owner_id, obj):
		if str(((opt as Dictionary).get("extra", {}) as Dictionary).get("mode", "")) == "graveyard_perm":
			return true
	return false


func test_gravecrawler_can_be_cast_from_the_graveyard_only_with_a_zombie() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var crawler := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Gravecrawler")
	assert_false(_graveyard_mode(engine, crawler), "no Zombie, no cast")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	assert_true(_graveyard_mode(engine, crawler), "with a Zombie it can be cast from the graveyard")


func test_zul_ashur_lets_you_cast_a_zombie_from_the_graveyard_this_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var zul := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zul")
	var zombie := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Zombie")
	assert_false(_graveyard_mode(engine, zombie), "not by itself")
	_run(engine, zul, 0, _effects(zul, &"ACTIVATED"), {}, [zombie.object_id])
	assert_true(_graveyard_mode(engine, zombie), "after the ability: this turn")
	engine.state.turn_number += 1
	assert_false(_graveyard_mode(engine, zombie), "but not next turn")


func test_cemetery_recruitment_draws_only_for_a_zombie() -> void:
	for pair in [["Test Zombie", 2], ["Test Bear", 1]]:
		var engine := Fixtures.empty_engine_1v1()
		for _i in 3:
			Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Bear")
		var recruit := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Recruit")
		var dead := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, str(pair[0]))
		_run(engine, recruit, 0, _effects(recruit, &"SPELL"), {}, [dead.object_id])
		assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), int(pair[1]), "%s back: hand %d" % [str(pair[0]), int(pair[1])])


func test_an_opponent_tapping_a_land_freezes_it() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Pulse")
	var land := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Forest")
	engine.state.active_player_id = 1
	engine.priority.give(engine.state, 1)
	var tap := engine.submit(Fixtures.activate_mana(1, land.object_id))
	assert_true(tap.ok, "tap: %s" % tap.error)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the trigger went on the stack")
	engine.resolve_top()
	assert_true(land.marks.has("frozen"), "that land will not untap next time")


func test_a_stun_counter_replaces_an_untap() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var stunner := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Stunner")
	stunner.tapped = true
	_run(engine, stunner, 0, _effects(stunner, &"TRIGGERED"))
	assert_eq(int(stunner.counters.get("stun", 0)), 1, "the stun counter was put on it")
	engine.state.active_player_id = 0
	engine.turn._untap(engine.state)
	assert_true(stunner.tapped, "it stays tapped")
	assert_false(stunner.counters.has("stun"), "and the counter is gone")
	engine.turn._untap(engine.state)
	assert_false(stunner.tapped, "the next untap works")


func test_syphon_flesh_makes_a_zombie_for_each_creature_sacrificed() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var syphon := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Syphon")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, syphon, 0, _effects(syphon, &"SPELL"))
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), 1, "the rival sacrificed one")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Zombie"), 1, "and you got one Zombie")


func test_big_x_soldiers_wipe_the_other_creatures() -> void:
	for pair in [[5, 0], [3, 2]]:
		var engine := Fixtures.empty_engine_1v1()
		var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Soldiers")
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
		_run(engine, spell, 0, _effects(spell, &"SPELL"), {x = int(pair[0])})
		assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Soldier"), int(pair[0]), "X=%d Soldiers survive" % int(pair[0]))
		assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Bear") + _count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), int(pair[1]), "Bears left with X=%d" % int(pair[0]))


func test_exchanging_life_makes_a_horror_as_big_as_the_difference() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Swap")
	engine.state.players[0].life = 40
	engine.state.players[1].life = 12
	_run(engine, spell, 0, _effects(spell, &"SPELL"), {}, [TargetingManager.encode_player(0), TargetingManager.encode_player(1)])
	assert_eq(engine.state.players[0].life, 12)
	assert_eq(engine.state.players[1].life, 40)
	var horror: GameObject = null
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		if (engine.state.objects[oid].definition as CardDefinition).type_line.contains("Horror"):
			horror = engine.state.objects[oid]
	assert_true(horror != null and engine.power_of(horror) == 28, "a 28/28 Horror")


func test_beasts_fight_the_rivals_creatures() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Beasts")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, spell, 0, _effects(spell, &"SPELL"))
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Beast"), 2, "one Beast per rival creature")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), 0, "and each fought, and beat, a different Bear")


func test_every_player_chooses_a_creature_to_lose() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Verdict")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var big := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	big.counters["+1/+1"] = 2
	var mine := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, spell, 0, _effects(spell, &"SPELL"))
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1), 0, "both chosen creatures were destroyed: the rival gave up the small one, you took the big one")
	assert_true(mine.zone == EngineEnums.ZoneId.BATTLEFIELD, "your own creature is not in the pool")


func test_rite_draws_discards_and_makes_a_spirit_for_each_type() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Bolt")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Zombie")
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Rite")
	_run(engine, spell, 0, _effects(spell, &"SPELL"), {x = 2})
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), 0, "drew two, discarded two")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Spirit"), 2, "an instant and a creature: two card types, two Spirits")


func test_lurker_hits_three_targets() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var lurker := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lurker")
	var b1 := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var b2 := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, lurker, 0, _effects(lurker, &"TRIGGERED"), {}, [TargetingManager.encode_player(1), b1.object_id, b2.object_id])
	engine.sba.check(engine)
	assert_eq(engine.state.players[1].life, 36, "4 damage to the first target")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), 0, "3 damage to each of the other two")


func test_parallax_gives_every_other_player_a_copy() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Parallax")
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, spell, 0, _effects(spell, &"SPELL"), {}, [bear.object_id])
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), 0, "the original was exiled")
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Bear"), 1, "and you got a token copy")


func test_sacrifice_discard_and_token_watchers_trigger() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Sacwatch")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Discardwatch")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Tokenwatch")
	var stack := engine.state.stack as MagicStack
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.marks["sacrificed"] = true
	engine.state.zones.move(bear.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	engine.process_zone_events()
	assert_eq(stack.size(), 1, "a sacrifice triggers it")
	engine.resolve_top()
	var plain := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	engine.state.zones.move(plain.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	engine.process_zone_events()
	assert_eq(stack.size(), 0, "a creature that simply died does not")
	var card := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Bear")
	engine.discard_card(0, card.object_id)
	assert_eq(stack.size(), 1, "a discard triggers it")
	engine.resolve_top()
	var maker := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Soldiers")
	_run(engine, maker, 0, _effects(maker, &"SPELL"), {x = 2})
	engine.process_zone_events()
	assert_eq(stack.size(), 1, "making tokens triggers it once, however many")
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, 43, "three life gained in all")


func test_batch_two_lines_are_read() -> void:
	for n in ["Test Soulless", "Test Angel", "Test Tyrant", "Test Winnower", "Test Maneuver", "Test Charm", "Test Decree2", "Test Regent", "Test Rakdos"]:
		assert_eq(db.unread_lines(db.definition_for(n)).size(), 0, "%s: %s" % [n, str(db.unread_lines(db.definition_for(n)))])


func test_soulless_one_counts_zombies_on_the_battlefield_and_in_all_graveyards() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var one := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Soulless")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Zombie")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Zombie")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
	assert_eq(engine.power_of(one), 4, "itself + 1 more on the battlefield + 2 in graveyards")


func test_darksteel_angel_stops_minus_counters_on_your_creatures_only() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var angel := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Angel")
	var theirs := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	assert_true(engine.counters_prevented(angel, "-1/-1"))
	assert_false(engine.counters_prevented(theirs, "-1/-1"), "only your creatures")
	assert_false(engine.counters_prevented(angel, "+1/+1"), "only -1/-1 counters")


func test_void_winnower_blocks_even_mana_values() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Winnower")
	var even := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var odd := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	assert_true(engine.layers.combat_restricted(engine.state, even), "a 2-drop can't block")
	assert_false(engine.layers.combat_restricted(engine.state, odd), "a 1-drop can")
	var spell := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Test Bolt")
	var two := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Test Bear")
	assert_false(engine._cast_forbidden(spell), "an odd spell is fine")
	assert_true(engine._cast_forbidden(two), "an even spell is forbidden")


func test_leyline_tyrant_keeps_red_mana_between_steps() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Tyrant")
	var pool: ManaPool = engine.state.players[0].mana
	pool.r = 3
	pool.g = 2
	engine.mana.on_step_end()
	assert_eq(pool.r, 3, "red stays")
	assert_eq(pool.g, 0, "other colors empty")


func test_rakdos_makes_creature_spells_cheaper_for_life_lost() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Rakdos")
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Bear")
	assert_eq(engine.cost_reduction(0, bear), 0)
	engine.state.players[1].life_lost_this_turn = 3
	assert_eq(engine.cost_reduction(0, bear), 3)


func test_cycling_decree_shrinks_every_creature() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var decree := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Decree2")
	engine.triggers.on_cycled(engine, decree, 0)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the cycle trigger is on the stack")
	engine.resolve_top()
	engine.sba.check(engine)
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), 0, "a 2/2 got -2/-2")


func test_each_creature_deals_damage_to_its_controller() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var charm := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Charm")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_run(engine, charm, 0, _effects(charm, &"SPELL"))
	assert_eq(engine.state.players[0].life, 39)
	assert_eq(engine.state.players[1].life, 38)


func test_a_commander_lets_maneuver_be_cast_free() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var man := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Maneuver")
	var free := false
	for opt in engine.kw.cast_options(0, man):
		if str(((opt as Dictionary).get("extra", {}) as Dictionary).get("mode", "")) == "free_commander":
			free = true
	assert_false(free, "no commander, no free cast")
	var cmdr := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	cmdr.is_commander = true
	for opt in engine.kw.cast_options(0, man):
		if str(((opt as Dictionary).get("extra", {}) as Dictionary).get("mode", "")) == "free_commander":
			free = true
	assert_true(free, "with a commander it is offered")


func test_modal_triggers_on_two_events_and_group_damage_read() -> void:
	for n in ["Test Gargaroth", "Test Thrasher", "Test Geyser"]:
		assert_eq(db.unread_lines(db.definition_for(n)).size(), 0, "%s: %s" % [n, str(db.unread_lines(db.definition_for(n)))])
	var ons := []
	for a in db.definition_for("Test Gargaroth").abilities:
		if (a as Ability).kind == &"TRIGGERED":
			ons.append(str((a as Ability).trigger.get("on", "")))
	assert_true(ons.has("ATTACKS") and ons.has("BLOCKS"), "attacks and blocks: %s" % str(ons))


func test_mana_geyser_adds_red_for_each_tapped_opposing_land() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var geyser := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Geyser")
	for _i in 3:
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Forest").tapped = true
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Forest")
	_run(engine, geyser, 0, _effects(geyser, &"SPELL"))
	assert_eq((engine.state.players[0].mana as ManaPool).r, 3)


func test_group_combat_damage_triggers_once_per_step() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var thr := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Thrasher")
	var other := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Dragon")
	engine.triggers.on_combat_damage_to_player(engine, thr, 1, 3)
	engine.triggers.on_combat_damage_to_player(engine, other, 1, 2)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "one trigger for two Dragons in the same step")


func test_third_batch_lines_are_read() -> void:
	for n in ["Test Archfiend", "Test Spire", "Test Konrad", "Test Triplets", "Test Bontu"]:
		assert_eq(db.unread_lines(db.definition_for(n)).size(), 0, "%s: %s" % [n, str(db.unread_lines(db.definition_for(n)))])


func test_archfiend_doubles_what_opponents_already_lost() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var fiend := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Archfiend")
	engine.state.players[1].life_lost_this_turn = 7
	_run(engine, fiend, 0, _effects(fiend, &"TRIGGERED"))
	assert_eq(engine.state.players[1].life, 33)


func test_syr_konrad_pings_for_cards_entering_and_leaving_graveyards() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Konrad")
	var stack := engine.state.stack as MagicStack
	var card := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Test Zombie")
	engine.discard_card(1, card.object_id)
	engine.process_zone_events()
	assert_eq(stack.size(), 1, "a creature card discarded into a graveyard")
	engine.resolve_top()
	var mine := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Zombie")
	engine.state.zones.move(mine.object_id, EngineEnums.ZoneId.EXILE, 0)
	engine.process_zone_events()
	assert_eq(stack.size(), 1, "and one leaving your graveyard")
	engine.resolve_top()
	var theirs := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Zombie")
	engine.state.zones.move(theirs.object_id, EngineEnums.ZoneId.EXILE, 1)
	engine.process_zone_events()
	assert_eq(stack.size(), 0, "a card leaving the other graveyard does not count")


func test_gruff_triplets_copy_themselves_once() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var t := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Triplets")
	engine.process_zone_events()
	_run(engine, t, 0, _effects(t, &"TRIGGERED"))
	var named := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		if (engine.state.objects[oid].definition as CardDefinition).name == "Test Triplets":
			named += 1
	assert_true(named >= 3, "the original and two token copies: %d" % named)


func test_fourth_batch_lines_are_read() -> void:
	for n in ["Test Windfall", "Test Evacuation", "Test Decimate", "Test Wanderings", "Test Oracle", "Test Wastenot", "Test Upheaval", "Test Worms", "Test Cloak", "Test Chimera", "Test Spire2"]:
		assert_eq(db.unread_lines(db.definition_for(n)).size(), 0, "%s: %s" % [n, str(db.unread_lines(db.definition_for(n)))])


func test_windfall_draws_as_many_as_the_biggest_hand() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Windfall")
	for _i in 2:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Bear")
	for _i in 5:
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Test Bear")
	for pid in 2:
		for _j in 8:
			Fixtures.spawn_named(engine, db, pid, EngineEnums.ZoneId.LIBRARY, "Test Bear")
	_run(engine, spell, 0, _effects(spell, &"SPELL"))
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), 5)
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1) as Zone).size(), 5)


func test_evacuation_bounces_every_creature() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Evacuation")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Forest")
	_run(engine, spell, 0, _effects(spell, &"SPELL"))
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Bear") + _count(engine, EngineEnums.ZoneId.BATTLEFIELD, 1, "Bear"), 0)
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1) as Zone).size(), 1, "back to its owner's hand; the land stays")


func test_the_top_card_branch_puts_a_land_in_play_and_a_spell_in_hand() -> void:
	for pair in [["Forest", 1, 0], ["Test Bear", 0, 1]]:
		var engine := Fixtures.empty_engine_1v1()
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, str(pair[0]))
		var o := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Oracle")
		_run(engine, o, 0, _effects(o, &"TRIGGERED"))
		assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Forest"), int(pair[1]), "%s on the battlefield" % str(pair[0]))
		assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), int(pair[2]), "%s in hand" % str(pair[0]))


func test_far_wanderings_gets_three_lands_only_with_seven_cards_in_the_graveyard() -> void:
	for pair in [[0, 1], [7, 3]]:
		var engine := Fixtures.empty_engine_1v1()
		var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Wanderings")
		for _i in 5:
			Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Forest")
		for _g in int(pair[0]):
			Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
		_run(engine, spell, 0, _effects(spell, &"SPELL"))
		assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Forest"), int(pair[1]), "%d in the graveyard" % int(pair[0]))


func test_waste_not_only_counts_noncreature_nonland_discards() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Wastenot")
	var stack := engine.state.stack as MagicStack
	for pair in [["Test Bear", 0], ["Forest", 0], ["Test Bolt", 1]]:
		var c := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, str(pair[0]))
		engine.discard_card(1, c.object_id)
		assert_eq(stack.size(), int(pair[1]), "%s discarded" % str(pair[0]))
		while stack.size() > 0:
			engine.resolve_top()


func test_grave_upheaval_takes_a_creature_from_any_graveyard() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Upheaval")
	var dead := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
	_run(engine, spell, 0, _effects(spell, &"SPELL"), {}, [dead.object_id])
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Bear"), 1, "it is on the battlefield under your control")


func test_worm_harvest_counts_land_cards_in_your_graveyard() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Worms")
	for _i in 3:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Forest")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
	_run(engine, spell, 0, _effects(spell, &"SPELL"))
	assert_eq(_count(engine, EngineEnums.ZoneId.BATTLEFIELD, 0, "Worm"), 3)


func test_spellheart_chimera_counts_instants_and_sorceries() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var c := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Chimera")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Bolt")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Windfall")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
	assert_eq(engine.power_of(c), 2)


func test_a_trigger_target_prompt_says_what_the_ability_does() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.interactive_seats = [0]
	var reg := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Regisaur")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	for a in (reg.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"TRIGGERED":
			engine.triggers._put_trigger(engine, reg, a as Ability, {})
	engine.resolve_top()
	var dec := engine.state.pending_decision as PlayerDecision
	assert_true(dec != null, "asked to pick the target")
	assert_true(dec.prompt.contains("deals 1 damage"), "the prompt carries the card's text: %s" % dec.prompt)
	assert_true(dec.prompt.contains("Test Regisaur"), "and names the card, not a tilde: %s" % dec.prompt)


func test_a_filter_land_spends_one_mana_and_makes_two() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ridge := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ridge")
	var mtn := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var pool: ManaPool = engine.state.players[0].mana
	assert_false(engine.submit(Fixtures.activate_mana(0, ridge.object_id)).ok, "no mana in the pool to pay {1}")
	assert_true(engine.submit(Fixtures.activate_mana(0, mtn.object_id)).ok)
	assert_eq(pool.r, 1)
	var r := engine.submit(Fixtures.activate_mana(0, ridge.object_id))
	assert_true(r.ok, "now it can: %s" % r.error)
	assert_eq(pool.b, 1)
	assert_eq(pool.r, 1, "spent the R, got B and R")
	assert_true(ridge.tapped)


func test_a_filter_land_makes_a_spell_affordable_and_pays_for_it() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ridge")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	assert_true(engine.can_afford(0, ManaCost.parse("{B}{R}")), "Mountain feeds the Ridge: B and R")
	assert_false(engine.can_afford(0, ManaCost.parse("{B}{B}")), "but never two black")
	assert_false(engine.can_afford(0, ManaCost.parse("{B}{R}{R}")), "and only two mana in all")
	assert_true(engine.pay_now(0, ManaCost.parse("{B}{R}")), "paid by tapping both")
	var ridge_alone := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(ridge_alone, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ridge")
	assert_false(ridge_alone.can_afford(0, ManaCost.parse("{B}")), "a filter land with nothing to pay its {1} makes nothing")


func _table_session() -> GameSession:
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = db
	session.you_seat = 0
	session.skip_ai = true
	var engine := session.engine
	for pid in 2:
		for _i in 6:
			Fixtures.spawn_named(engine, db, pid, EngineEnums.ZoneId.LIBRARY, "Forest")
	engine.state.turn_number = 2
	engine.state.active_player_id = 0
	engine.state.phase = EngineEnums.Phase.MAIN_1
	engine.state.step = EngineEnums.Step.PRECOMBAT_MAIN
	engine.state.awaiting = {player_id = 0, type = &"priority"}
	return session


func test_a_spell_with_a_creature_target_asks_which_creature() -> void:
	for spell_name in ["Test Ignition", "Test Bite"]:
		var session := _table_session()
		var engine := session.engine
		var m := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
		m.summoned_this_turn = false
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Regisaur")
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
		var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, spell_name)
		session.rebuild_view()
		var r := session.cast_auto(0, spell.object_id)
		assert_true(r.ok, "%s cast: %s" % [spell_name, r.error])
		assert_true(session.target_pending, "%s waits for you to pick the creature" % spell_name)
		assert_eq((session.target_prompt.options as Array).size(), 2, "your two creatures are the choices for %s" % spell_name)


func test_activated_and_equip_abilities_ask_which_creature() -> void:
	for pair in [["Test Pumper", &"ACTIVATED"], ["Test Cloak", &"ACTIVATED"]]:
		var session := _table_session()
		var engine := session.engine
		for _i in 3:
			var m := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
			m.summoned_this_turn = false
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Regisaur")
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
		var src := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, str(pair[0]))
		src.summoned_this_turn = false
		session.rebuild_view()
		var r := session.activate_auto(src.object_id)
		assert_true(r.ok, "%s activated: %s" % [str(pair[0]), r.error])
		assert_true(session.target_pending, "%s waits for you to pick the creature" % str(pair[0]))


func test_an_enters_trigger_with_a_target_asks_which_creature() -> void:
	var session := _table_session()
	var engine := session.engine
	engine.interactive_seats = [0, 1]
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var w := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Etb")
	engine.process_zone_events()
	engine.resolve_top()
	var dec := engine.state.pending_decision as PlayerDecision
	assert_true(dec != null, "the trigger asks you to choose")
	assert_true(w != null)
