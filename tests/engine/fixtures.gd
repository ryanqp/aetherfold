extends RefCounted

## Shared constructors for engine tests. Must not be named test_*.gd.


static func empty_engine(rules: FormatRules, seed: int = 1) -> RulesEngine:
	var engine := RulesEngine.new()
	engine.setup(rules, seed)
	return engine


static func empty_engine_1v1(seed: int = 1) -> RulesEngine:
	return empty_engine(FormatRules.commander_1v1_table(), seed)


static func empty_engine_4p(seed: int = 1) -> RulesEngine:
	return empty_engine(FormatRules.commander_4p(), seed)


static func spawn(engine: RulesEngine, owner_id: int, zone_id: int, opts: Dictionary = {}) -> GameObject:
	return engine.state.zones.create(owner_id, zone_id, opts)


static func memory_catalog() -> CatalogSource:
	var cat := CatalogSource.Memory.new()
	cat.add(_land_row("Mountain", "Basic Land — Mountain", "({T}: Add {R}.)", ["R"]))
	cat.add(_land_row("Island", "Basic Land — Island", "({T}: Add {U}.)", ["U"]))
	cat.add(_land_row("Forgotten Cave", "Land", "Forgotten Cave enters the battlefield tapped.\n{T}: Add {R}.\nCycling {R} ({R}, Discard this card: Draw a card.)", ["R"]))
	cat.add({
		name = "Goblin Piker",
		oracle_id = "goblin_piker",
		mana_cost = "{1}{R}",
		cmc = 2,
		type_line = "Creature — Goblin Warrior",
		oracle_text = "",
		power = "2",
		toughness = "1",
		color_identity = ["R"],
		colors = ["R"],
		commander_legal = true,
		images = {normal = "http://example.invalid/piker.png"},
	})
	cat.add({
		name = "Dragon Fodder",
		oracle_id = "dragon_fodder",
		mana_cost = "{1}{R}",
		cmc = 2,
		type_line = "Sorcery",
		oracle_text = "Create two 1/1 red Goblin creature tokens.",
		color_identity = ["R"],
		colors = ["R"],
		commander_legal = true,
	})
	cat.add({
		name = "Opt",
		oracle_id = "opt",
		mana_cost = "{U}",
		cmc = 1,
		type_line = "Instant",
		oracle_text = "Scry 1.\nDraw a card.",
		color_identity = ["U"],
		colors = ["U"],
		commander_legal = true,
	})
	cat.add({
		name = "Counterspell",
		oracle_id = "counterspell",
		mana_cost = "{U}{U}",
		cmc = 2,
		type_line = "Instant",
		oracle_text = "Counter target spell.",
		color_identity = ["U"],
		colors = ["U"],
		commander_legal = true,
	})
	cat.add({
		name = "Cancel",
		oracle_id = "cancel",
		mana_cost = "{1}{U}{U}",
		cmc = 3,
		type_line = "Instant",
		oracle_text = "Counter target spell.",
		color_identity = ["U"],
		colors = ["U"],
		commander_legal = true,
	})
	cat.add({
		name = "Unsummon",
		oracle_id = "unsummon",
		mana_cost = "{U}",
		cmc = 1,
		type_line = "Instant",
		oracle_text = "Return target creature to its owner's hand.",
		color_identity = ["U"],
		colors = ["U"],
		commander_legal = true,
	})
	cat.add({
		name = "Talrand, Sky Summoner",
		oracle_id = "talrand_sky_summoner",
		mana_cost = "{2}{U}{U}",
		cmc = 4,
		type_line = "Legendary Creature — Merfolk Wizard",
		oracle_text = "Whenever you cast an instant or sorcery spell, create a 2/2 blue Drake creature token with flying.",
		power = "2",
		toughness = "2",
		color_identity = ["U"],
		colors = ["U"],
		commander_legal = true,
	})
	cat.add(_spell_row("Sol Ring", "{1}", 1, "Artifact", "{T}: Add {C}{C}.", []))
	cat.add(_spell_row("Divination", "{2}{U}", 3, "Sorcery", "Draw two cards.", ["U"]))
	cat.add(_spell_row("Krenko's Command", "{1}{R}", 2, "Sorcery", "Create two 1/1 red Goblin creature tokens.", ["R"]))
	cat.add(_spell_row("Hordeling Outburst", "{1}{R}{R}", 3, "Sorcery", "Create three 1/1 red Goblin creature tokens.", ["R"]))
	cat.add(_spell_row("Dark Ritual", "{B}", 1, "Instant", "Add {B}{B}{B}.", ["B"]))
	cat.add({
		name = "Llanowar Elves",
		oracle_id = "llanowar elves",
		mana_cost = "{G}",
		cmc = 1,
		type_line = "Creature — Elf Druid",
		oracle_text = "{T}: Add {G}.",
		power = "1",
		toughness = "1",
		color_identity = ["G"],
		colors = ["G"],
		commander_legal = true,
	})
	cat.add(_spell_row("Boomerang", "{U}{U}", 2, "Instant", "Return target permanent to its owner's hand.", ["U"]))
	cat.add(_spell_row("Shock", "{R}", 1, "Instant", "Shock deals 2 damage to any target.", ["R"]))
	cat.add(_spell_row("Lightning Bolt", "{R}", 1, "Instant", "Lightning Bolt deals 3 damage to any target.", ["R"]))
	cat.add({
		name = "Krenko, Mob Boss",
		oracle_id = "krenko_mob_boss",
		mana_cost = "{2}{R}{R}",
		cmc = 4,
		type_line = "Legendary Creature — Goblin Warrior",
		oracle_text = "{T}: Create X 1/1 red Goblin creature tokens, where X is the number of Goblins you control.",
		power = "3",
		toughness = "3",
		color_identity = ["R"],
		colors = ["R"],
		commander_legal = true,
	})
	return cat


static func memory_db() -> CardDatabase:
	var db := CardDatabase.new()
	db.setup(memory_catalog())
	return db


static func spawn_named(engine: RulesEngine, db: CardDatabase, owner_id: int, zone_id: int, card_name: String) -> GameObject:
	var def := db.definition_for(card_name)
	return spawn(engine, owner_id, zone_id, {definition = def})


static func play_land(player_id: int, object_id: int) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.PLAY_LAND
	a.player_id = player_id
	a.object_id = object_id
	return a


static func activate_mana(player_id: int, object_id: int, ability_id: StringName = &"") -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.ACTIVATE_MANA_ABILITY
	a.player_id = player_id
	a.object_id = object_id
	a.ability_id = ability_id
	return a


static func pass_priority(player_id: int) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.PASS_PRIORITY
	a.player_id = player_id
	return a


static func cast_spell(player_id: int, object_id: int) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = player_id
	a.object_id = object_id
	return a


static func pay_mana(player_id: int) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.PAY_MANA
	a.player_id = player_id
	return a


static func confirm_pay(player_id: int) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.CONFIRM_PAY
	a.player_id = player_id
	return a


static func both_pass(engine: RulesEngine) -> void:
	engine.submit(pass_priority(int(engine.state.awaiting.get("player_id", 0))))
	engine.submit(pass_priority(int(engine.state.awaiting.get("player_id", 0))))


static func choose_targets(player_id: int, targets: Array) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.CHOOSE_TARGETS
	a.player_id = player_id
	a.targets = targets
	return a


static func activate_ability(player_id: int, object_id: int, ability_id: StringName) -> GameAction:
	var a := GameAction.new()
	a.kind = GameAction.Kind.ACTIVATE_ABILITY
	a.player_id = player_id
	a.object_id = object_id
	a.ability_id = ability_id
	return a


static func pay_and_resolve_spell(engine: RulesEngine, player_id: int, object_id: int) -> void:
	engine.submit(cast_spell(player_id, object_id))
	engine.submit(pay_mana(player_id))
	engine.submit(confirm_pay(player_id))
	both_pass(engine)


static func _spell_row(p_name: String, cost: String, cmc: int, type_line: String, oracle_text: String, ci: Array) -> Dictionary:
	var colors: Array = []
	for c in ci:
		colors.append(c)
	return {
		name = p_name,
		oracle_id = p_name.to_lower(),
		mana_cost = cost,
		cmc = cmc,
		type_line = type_line,
		oracle_text = oracle_text,
		color_identity = ci,
		colors = colors,
		commander_legal = true,
	}


static func _land_row(p_name: String, type_line: String, oracle_text: String, ci: Array) -> Dictionary:
	return {
		name = p_name,
		oracle_id = p_name.to_lower(),
		mana_cost = "",
		cmc = 0,
		type_line = type_line,
		oracle_text = oracle_text,
		color_identity = ci,
		colors = [],
		commander_legal = true,
	}
