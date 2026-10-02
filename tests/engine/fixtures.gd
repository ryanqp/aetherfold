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
	var obj: GameObject = engine.state.zones.create(owner_id, zone_id, opts)
	## A permanent that arrives is an event like any other, so "when this enters" triggers see it.
	if obj != null and zone_id == EngineEnums.ZoneId.BATTLEFIELD:
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, owner_id, {
			from_id = 0, to_id = obj.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0,
		})
	return obj


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
	cat.add(_creature_row("Elvish Mystic", "{G}", 1, "Creature — Elf Druid", "{T}: Add {G}.", ["G"]))
	cat.add(_creature_row("Fyndhorn Elves", "{G}", 1, "Creature — Elf Druid", "{T}: Add {G}.", ["G"]))
	cat.add(_spell_row("Flame Slash", "{R}", 1, "Sorcery", "Flame Slash deals 4 damage to target creature.", ["R"]))
	cat.add(_spell_row("Lightning Strike", "{1}{R}", 2, "Instant", "Lightning Strike deals 3 damage to any target.", ["R"]))
	cat.add(_spell_row("Tidings", "{3}{U}", 4, "Sorcery", "Draw four cards.", ["U"]))
	cat.add(_spell_row("Pyretic Ritual", "{1}{R}", 2, "Instant", "Add {R}{R}{R}.", ["R"]))
	cat.add(_spell_row("Negate", "{1}{U}", 2, "Instant", "Counter target noncreature spell.", ["U"]))
	cat.add(_spell_row("Essence Scatter", "{1}{U}", 2, "Instant", "Counter target creature spell.", ["U"]))
	cat.add(_spell_row("Vapor Snag", "{U}", 1, "Instant", "Return target creature to its owner's hand. Its controller loses 1 life.", ["U"]))
	cat.add(_spell_row("Raise the Alarm", "{1}{W}", 2, "Instant", "Create two 1/1 white Soldier creature tokens.", ["W"]))
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
	cat.add({
		name = "Kellan, Planar Trailblazer",
		oracle_id = "kellan_planar_trailblazer",
		mana_cost = "{R}",
		cmc = 1,
		type_line = "Legendary Creature — Human Faerie Scout",
		oracle_text = "{1}{R}: If Kellan is a Scout, it becomes a Human Faerie Detective and gains \"Whenever Kellan deals combat damage to a player, exile the top card of your library. You may play that card this turn.\"\n{2}{R}: If Kellan is a Detective, it becomes a 3/2 Human Faerie Rogue and gains double strike.",
		power = "2",
		toughness = "1",
		color_identity = ["R"],
		colors = ["R"],
		commander_legal = true,
	})
	## Spells with no hand-written IR: OracleIr reads these straight from Oracle text.
	cat.add(_spell_row("Test Smite", "{R}", 1, "Instant", "Test Smite deals 4 damage to target creature.", ["R"]))
	cat.add(_spell_row("Test Doom", "{R}", 1, "Instant", "Destroy target creature.", ["R"]))
	cat.add(_spell_row("Test Banish", "{R}", 1, "Instant", "Exile target creature.", ["R"]))
	cat.add(_spell_row("Test Growth", "{R}", 1, "Instant", "Target creature gets +3/+3 until end of turn.", ["R"]))
	cat.add(_spell_row("Test Bundle", "{R}", 1, "Instant", "Target creature gets +2/+0 and gains first strike until end of turn.", ["R"]))
	cat.add(_spell_row("Test Mend", "{R}", 1, "Instant", "You gain 4 life.", ["R"]))
	cat.add(_spell_row("Test Study", "{R}", 1, "Sorcery", "Draw two cards. (Reminder text.)", ["R"]))
	cat.add(_spell_row("Test Shrink", "{R}", 1, "Instant", "Target creature gets -9/-9 until end of turn.", ["R"]))
	cat.add(_spell_row("Test Mystery", "{R}", 1, "Instant", "Test Mystery does something strange.", ["R"]))
	cat.add(_spell_row("Test Unsure", "{R}", 1, "Instant", "Test Unsure deals 2 damage to any target.\nRoll two six-sided dice and add them.", ["R"]))
	## Permanents read from Oracle text: triggers, statics, equipment, tokens.
	cat.add(_creature_row("Test Raptor Lord", "{2}{R}", 3, "Creature — Dinosaur", "Other Dinosaurs you control get +1/+1.", ["R"]))
	cat.add(_creature_row("Test Egg Layer", "{1}{G}", 2, "Creature — Dinosaur", "When this creature enters, create a 1/1 green Dinosaur creature token.", ["G"]))
	cat.add(_creature_row("Test Gorger", "{2}{G}", 3, "Creature — Dinosaur", "Whenever this creature attacks, put a +1/+1 counter on it.", ["G"]))
	cat.add(_creature_row("Test Treasurer", "{2}{R}", 3, "Creature — Goblin", "At the beginning of your upkeep, create a Treasure token.", ["R"]))
	cat.add(_creature_row("Test Mourner", "{1}{W}", 2, "Creature — Human", "When this creature dies, you gain 3 life.", ["W"]))
	cat.add(_spell_row("Test Blade", "{1}", 1, "Artifact — Equipment", "Equipped creature gets +2/+2 and has menace.\nEquip {2}", []))
	cat.add(_spell_row("Test Fetch", "{1}{G}", 2, "Sorcery", "Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.", ["G"]))
	cat.add(_spell_row("Test Rend", "{1}{G}", 2, "Sorcery", "Target creature you control fights target creature you don't control.", ["G"]))
	cat.add(_land_row("Test Gamefield", "Land", "As Test Gamefield enters, you may reveal a Mountain or Forest card from your hand. If you don't, Test Gamefield enters tapped.\n{T}: Add {R} or {G}.", ["R", "G"]))
	cat.add(_land_row("Test Fastland", "Land", "Test Fastland enters tapped unless you control two or fewer other lands.\n{T}: Add {R} or {G}.", ["R", "G"]))
	cat.add(_land_row("Test Checkland", "Land", "Test Checkland enters tapped unless you control a Mountain or an Island.\n{T}: Add {U} or {R}.", ["U", "R"]))
	cat.add(_spell_row("Test Stomp", "{2}{G}", 3, "Sorcery", "Test Stomp costs {2} less to cast if it targets a Dinosaur you control.\nPut a +1/+1 counter on target creature you control. Then that creature fights target creature you don't control.", ["G"]))
	cat.add(_land_row("Test Thriving", "Land", "This land enters tapped.\nAs this land enters, choose a color other than green.\n{T}: Add {G}.\n{T}: Add one mana of the chosen color.", ["G"]))
	cat.add(_creature_row("Test Discoverer", "{3}{G}", 4, "Creature — Dinosaur", "Whenever this creature or another Dinosaur you control enters, you may discover X, where X is that creature's toughness. Do this only once each turn.", ["G"]))
	cat.add(_creature_row("Test Monarch", "{3}{W}", 4, "Creature — Human", "When this creature enters, you become the monarch.", ["W"]))
	cat.add(_creature_row("Test Breaker", "{1}{G}", 2, "Creature — Beast", "{1}, Sacrifice this creature: Destroy target artifact or enchantment.", ["G"]))
	cat.add(_land_row("Test Bridge", "Land", "Hideaway 4\nThis land enters tapped.\n{T}: Add {G}.\n{G}, {T}: You may play the exiled card without paying its mana cost if creatures you control have total power 10 or greater.", ["G"]))
	cat.add(_creature_row("Test Miller", "{2}{U}", 3, "Creature — Merfolk", "When this creature enters, each opponent mills three cards, then you surveil 2.", ["U"]))
	cat.add(_keyword_creature("Test Fearful", "2", "2", ["Fear"]))
	cat.add(_keyword_creature("Test Skulker", "2", "2", ["Skulk"]))
	cat.add(_keyword_creature("Test Infector", "2", "2", ["Infect"]))
	cat.add(_creature_row("Test Toxic", "{2}", 2, "Creature — Test", "Toxic 2", []))
	cat.add(_creature_row("Test Exalter", "{1}{W}", 2, "Creature — Human", "Exalted", ["W"]))
	cat.add(_creature_row("Test Afterlifer", "{2}{W}", 3, "Creature — Cleric", "Afterlife 2", ["W"]))
	cat.add(_creature_row("Test Annihilator", "{6}", 6, "Creature — Eldrazi", "Annihilator 2", []))
	cat.add(_creature_row("Test Undying", "{2}{G}", 3, "Creature — Beast", "Undying", ["G"]))
	cat.add(_creature_row("Test Gruul Brute", "{2}{R}{G}", 4, "Creature — Beast", "", ["R", "G"]))
	cat.add(_creature_row("Test Uncounterable", "{3}{G}", 4, "Creature — Dinosaur", "Test Uncounterable can't be countered.", ["G"]))
	cat.add(_creature_row("Test Rhythm", "{1}{G}", 2, "Creature — Elf", "Creature spells you control can't be countered.\nNontoken creatures you control have riot.", ["G"]))
	cat.add(_creature_row("Test Altisaur", "{3}{G}", 4, "Creature — Dinosaur", "If a source would deal damage to another Dinosaur you control, prevent all but 1 of that damage.", ["G"]))
	cat.add(_creature_row("Test Rager", "{2}{R}", 3, "Creature — Dinosaur", "Whenever another creature you control enters, Test Rager deals 2 damage to it. If a Dinosaur is dealt damage this way, Test Rager gets +2/+0 until end of turn.", ["R"]))
	cat.add(_creature_row("Test Rioter", "{1}{R}", 2, "Creature — Goblin", "Riot", ["R"]))
	cat.add(_creature_row("Test Investigator", "{1}{U}", 2, "Creature — Human", "When this creature enters, investigate.", ["U"]))
	## Vanilla keyword bodies for combat rules tests.
	cat.add(_keyword_creature("Test Flyer", "2", "2", ["Flying"]))
	cat.add(_keyword_creature("Test Reacher", "1", "4", ["Reach"]))
	cat.add(_keyword_creature("Test Wall", "0", "5", ["Defender"]))
	cat.add(_keyword_creature("Test Watcher", "2", "2", ["Vigilance"]))
	cat.add(_keyword_creature("Test Brute", "3", "3", ["Menace"]))
	cat.add(_keyword_creature("Test Trampler", "5", "5", ["Trample"]))
	cat.add(_keyword_creature("Test Viper", "1", "1", ["Deathtouch"]))
	cat.add(_keyword_creature("Test Healer", "3", "3", ["Lifelink"]))
	cat.add(_keyword_creature("Test Duelist", "2", "2", ["First strike"]))
	cat.add(_keyword_creature("Test Champion", "2", "2", ["Double strike"]))
	cat.add(_keyword_creature("Test Stalwart", "2", "2", ["Indestructible"]))
	cat.add(_keyword_creature("Test Bear", "2", "2", []))
	## A creature with an activated ability, read from Oracle text by OracleIr.translate_permanent.
	var pinger := _keyword_creature("Test Pinger", "1", "3", ["Reach"])
	pinger["oracle_text"] = "Reach\n{1}, {T}: Test Pinger deals 1 damage to target opponent."
	cat.add(pinger)
	var greeter := _keyword_creature("Test Greeter", "1", "1", [])
	greeter["oracle_text"] = "When Test Greeter enters, you gain 3 life."
	cat.add(greeter)
	var warden := _keyword_creature("Test Warden", "2", "2", [])
	warden["oracle_text"] = "When Test Warden enters, for each opponent, exile up to one target nonland permanent that player controls until Test Warden leaves the battlefield."
	cat.add(warden)
	## Mana from Oracle text: a rock that taps for the commander's colors, and a two-type land.
	cat.add({name = "Arcane Signet", oracle_id = "arcane_signet", mana_cost = "{2}", cmc = 2, type_line = "Artifact",
		oracle_text = "{T}: Add one mana of any color in your commander's color identity.", color_identity = [], colors = [], keywords = [], commander_legal = true})
	cat.add({name = "Test Duo Land", oracle_id = "test_duo_land", mana_cost = "", cmc = 0, type_line = "Land — Mountain Forest",
		oracle_text = "({T}: Add {R} or {G}.)", color_identity = ["R", "G"], colors = [], keywords = [], commander_legal = true})
	cat.add({name = "Test Painland", oracle_id = "test_painland", mana_cost = "", cmc = 0, type_line = "Land",
		oracle_text = "{T}: Add {C}.\n{T}: Add {R} or {G}. Test Painland deals 1 damage to you.", color_identity = ["R", "G"], colors = [], keywords = [], commander_legal = true})
	var itz := _keyword_creature("Test Itz", "2", "3", ["Flash"])
	itz["mana_cost"] = "{2}{R}{G}"
	itz["cmc"] = 4
	itz["color_identity"] = ["R", "G"]
	cat.add(itz)
	var verdant := _keyword_creature("Test Verdant", "2", "2", [])
	verdant["mana_cost"] = "{2}{G}"
	verdant["cmc"] = 3
	verdant["type_line"] = "Legendary Creature — Test"
	verdant["color_identity"] = ["G"]
	cat.add(verdant)
	var hyb := _keyword_creature("Test Hybrid", "2", "2", [])
	hyb["mana_cost"] = "{1}{G/W}{G/W}"
	hyb["cmc"] = 3
	hyb["color_identity"] = ["G", "W"]
	cat.add(hyb)
	var phy := _keyword_creature("Test Phyrexian", "2", "2", [])
	phy["mana_cost"] = "{1}{B/P}"
	phy["cmc"] = 2
	phy["color_identity"] = ["B"]
	cat.add(phy)
	var adv := _keyword_creature("Test Adventurer", "2", "2", [])
	adv["mana_cost"] = "{2}{R} // {R}"
	adv["cmc"] = 3
	cat.add(adv)
	## Keyword fixtures: cast modes, specials, upkeep and combat keywords.
	cat.add(_spell_row("Test Cantrip", "{U}", 1, "Instant", "Draw a card.\nFlashback {1}{U}", ["U"]))
	cat.add(_spell_row("Test Kicked", "{1}", 1, "Sorcery", "Draw a card.\nKicker {1}\nIf this spell was kicked, draw two cards.", []))
	cat.add(_creature_row("Test Cycler", "{3}{R}", 4, "Creature — Test", "Cycling {2}", ["R"]))
	cat.add(_creature_row("Test Landcycler", "{4}{G}", 5, "Creature — Test", "Landcycling {1}", ["G"]))
	cat.add(_creature_row("Test Elf", "{G}", 1, "Creature — Elf", "", ["G"]))
	cat.add(_spell_row("Test Convoker", "{3}{G}", 4, "Sorcery", "Convoke\nDraw a card.", ["G"]))
	cat.add(_spell_row("Test Delver", "{5}{U}", 6, "Instant", "Delve\nDraw a card.", ["U"]))
	cat.add(_creature_row("Test Dasher", "{3}{R}", 4, "Creature — Test", "Dash {2}{R}", ["R"]))
	cat.add(_creature_row("Test Warder", "{2}", 2, "Creature — Test", "Ward {2}", []))
	cat.add(_creature_row("Test Echoer", "{1}{R}", 2, "Creature — Test", "Echo {1}{R}", ["R"]))
	cat.add(_creature_row("Test Vanisher", "{1}", 1, "Creature — Test", "Vanishing 2", []))
	cat.add(_creature_row("Test Fader", "{1}", 1, "Creature — Test", "Fading 1", []))
	cat.add(_creature_row("Test Extorter", "{W}{B}", 2, "Creature — Test", "Extort", ["W", "B"]))
	cat.add(_creature_row("Test Thirst", "{2}{R}", 3, "Creature — Test", "Bloodthirst 2", ["R"]))
	cat.add(_creature_row("Test Samurai", "{1}{W}", 2, "Creature — Samurai", "Bushido 2", ["W"]))
	cat.add(_creature_row("Test Flanker", "{1}{W}", 2, "Creature — Knight", "Flanking", ["W"]))
	cat.add(_creature_row("Test Rampager", "{3}{G}", 4, "Creature — Test", "Rampage 2", ["G"]))
	var vehicle := _creature_row("Test Cart", "{2}", 2, "Artifact — Vehicle", "Crew 2", [])
	vehicle["power"] = "4"
	vehicle["toughness"] = "4"
	cat.add(vehicle)
	cat.add(_creature_row("Test Phaser", "{1}{U}", 2, "Creature — Test", "Phasing", ["U"]))
	cat.add(_creature_row("Test Madman", "{3}{R}", 4, "Creature — Test", "Madness {R}", ["R"]))
	cat.add(_creature_row("Test Morpher", "{4}{G}", 5, "Creature — Test", "Morph {2}{G}", ["G"]))
	cat.add(_creature_row("Test Adapter", "{2}", 2, "Creature — Test", "{1}{G}: Adapt 2.", []))
	cat.add(_creature_row("Test Conniver", "{1}{U}", 2, "Creature — Test", "When this creature enters, it connives.", ["U"]))
	cat.add(_creature_row("Test Incubator Man", "{3}", 3, "Creature — Test", "When this creature enters, incubate 2.", []))
	cat.add(_creature_row("Test Supporter", "{2}{G}", 3, "Creature — Test", "When this creature enters, support 2.", ["G"]))
	cat.add(_spell_row("Test Gadfly", "{R}", 1, "Sorcery", "Goad target creature.", ["R"]))
	cat.add(_spell_row("Test Suspector", "{B}", 1, "Sorcery", "Suspect target creature.", ["B"]))
	cat.add(_spell_row("Test Manifester", "{2}", 2, "Sorcery", "Manifest the top card of your library.", []))
	cat.add(_spell_row("Test Suspender", "{1}{R}", 2, "Sorcery", "Suspend 2—{R}\nTest Suspender deals 2 damage to any target.", ["R"]))
	cat.add(_spell_row("Test Rebounder", "{2}{R}", 3, "Sorcery", "Test Rebounder deals 1 damage to any target.\nRebound", ["R"]))
	cat.add(_creature_row("Test Ninja", "{3}{U}", 4, "Creature — Ninja", "Ninjutsu {1}{U}", ["U"]))
	cat.add(_creature_row("Test Escaper", "{3}{B}{B}", 5, "Creature — Test", "Escape—{3}{B}, Exile two other cards from your graveyard.", ["B"]))
	cat.add(_spell_row("Test Retracer", "{1}{R}", 2, "Sorcery", "Draw a card.\nRetrace", ["R"]))
	cat.add(_creature_row("Test Emerger", "{6}{G}", 7, "Creature — Test", "Emerge {5}{G}", ["G"]))
	cat.add(_creature_row("Test Prowler", "{3}{B}", 4, "Creature — Rogue", "Prowl {1}{B}", ["B"]))
	cat.add(_spell_row("Test Miracle", "{4}{U}", 5, "Sorcery", "Miracle {U}\nDraw a card.", ["U"]))
	cat.add(_creature_row("Test Enlister", "{2}{R}", 3, "Creature — Test", "Enlist", ["R"]))
	cat.add(_creature_row("Test Bander", "{W}", 1, "Creature — Test", "Banding", ["W"]))
	cat.add(_spell_row("Test Sealer", "{1}{U}", 2, "Sorcery", "Fateseal 2.", ["U"]))
	cat.add(_spell_row("Test Learner", "{G}", 1, "Sorcery", "Learn.", ["G"]))
	cat.add(_creature_row("Test Cumulator", "{1}{G}", 2, "Creature — Test", "Cumulative upkeep {1}", ["G"]))
	cat.add(_spell_row("Test Migration", "{1}{G}", 2, "Sorcery", "As an additional cost to cast this spell, reveal a Dinosaur card from your hand or pay {1}.\nSearch your library for a basic land card, put it onto the battlefield tapped, then shuffle.", ["G"]))
	cat.add(_creature_row("Test Dino", "{2}{G}", 3, "Creature — Dinosaur", "", ["G"]))
	cat.add(_creature_row("Test Swordtooth", "{3}{G}", 4, "Creature — Dinosaur", "You may play an additional land on each of your turns.", ["G"]))
	var vista := _spell_row("Test Vista", "", 0, "Land", "~ enters tapped unless you control two or more basic lands.\n{T}: Add {R} or {G}.", ["R", "G"])
	cat.add(vista)
	cat.add(_creature_row("Test Dreadmaw", "{4}{G}", 5, "Creature — Dinosaur", "When ~ enters, draw a card for each other Dinosaur you control.", ["G"]))
	cat.add(_spell_row("Test Exiler", "{W}", 1, "Instant", "Exile target creature. Its controller may search their library for a basic land card, put that card onto the battlefield tapped, then shuffle.", ["W"]))
	cat.add(_spell_row("Test Rampant", "{1}{G}", 2, "Sorcery", "Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.", ["G"]))
	cat.add(_creature_row("Test Untapper", "{4}{G}", 5, "Creature — Dinosaur", "When ~ enters, if you cast it, untap all lands you control.", ["G"]))
	cat.add(_creature_row("Test Sunwing", "{3}{W}", 4, "Creature — Bird", "Flying\nCreatures your opponents control enter tapped.", ["W"]))
	cat.add(_spell_row("Test Thriving Bluff", "", 0, "Land", "This land enters tapped. As it enters, choose a color other than red.\n{T}: Add {R} or one mana of the chosen color.", []))
	cat.add(_creature_row("Test Crewmate", "{2}", 2, "Creature — Test", "", []))
	cat.add(_keyword_creature("Test Ogre", "3", "3", []))
	cat.add(_keyword_creature("Test Shapeless", "*", "*", []))
	return cat


static func _keyword_creature(p_name: String, power: String, toughness: String, keywords: Array) -> Dictionary:
	return {
		name = p_name,
		oracle_id = p_name.to_lower().replace(" ", "_"),
		mana_cost = "{2}",
		cmc = 2,
		type_line = "Creature — Test",
		oracle_text = ", ".join(PackedStringArray(keywords)),
		power = power,
		toughness = toughness,
		keywords = keywords,
		color_identity = [],
		colors = [],
		commander_legal = true,
	}


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


static func _creature_row(p_name: String, cost: String, cmc: int, type_line: String, oracle_text: String, ci: Array) -> Dictionary:
	var row := _spell_row(p_name, cost, cmc, type_line, oracle_text, ci)
	row["power"] = "1"
	row["toughness"] = "1"
	return row


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
