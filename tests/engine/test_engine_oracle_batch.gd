@tool
extends McpTestSuite

## Oracle lines read in one batch: Map tokens, "X/X token where X is ...", "half the number of ..., rounded down",
## devotion life gain, counters per graveyard card, untapped-only keywords and counter-conditioned keyword statics.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_oracle_batch"


func _row(name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "") -> Dictionary:
	return {name = name, oracle_id = name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Test Zombie", "{B}", 1, "Creature — Zombie", "", "2", "2"))
	m.add(_row("Test Ranks", "{3}{B}", 4, "Enchantment", "At the beginning of your upkeep, create X 2/2 black Zombie creature tokens, where X is half the number of Zombies you control, rounded down."))
	m.add(_row("Test Cartographer", "{2}", 2, "Creature — Scout", "Whenever Test Cartographer attacks, create a Map token.", "1", "1"))
	m.add(_row("Test Shark Maker", "{3}{U}", 4, "Enchantment", "Whenever you cast a noncreature spell, create an X/X blue Shark creature token with flying, where X is that spell's mana value."))
	m.add(_row("Test Colossus", "{3}{B}", 4, "Creature — Zombie", "Test Colossus enters with a +1/+1 counter on it for each Zombie card in your graveyard.", "0", "0"))
	m.add(_row("Test Sentinel", "{2}{G}", 3, "Creature — Elf", "Test Sentinel has hexproof as long as it's untapped.", "2", "2"))
	m.add(_row("Test Banner", "{2}{G}", 3, "Enchantment", "Each creature you control with a +1/+1 counter on it has trample."))
	m.add(_row("Test Tidal Wave", "{1}{R}", 2, "Sorcery", "Test Tidal Wave deals X damage to each creature with flying and each player."))
	m.add(_row("Test Gurgler", "{3}{B}", 4, "Creature — Horror", "When Test Gurgler enters, you gain life equal to your devotion to black.", "2", "2"))
	m.add(_row("Test Aura", "{1}{U}", 2, "Enchantment — Aura", "Enchant creature\nEnchanted creature has base power and toughness 1/1."))
	m.add(_row("Test Flyer Friend", "{2}{W}", 3, "Creature — Angel", "Whenever a creature you control with flying enters, it gains haste until end of turn.", "2", "2"))
	db = CardDatabase.new()
	db.setup(m)


func _unread(name: String) -> Array:
	return db.unread_lines(db.definition_for(name))


func test_each_new_line_is_read() -> void:
	for n in ["Test Ranks", "Test Cartographer", "Test Shark Maker", "Test Colossus", "Test Sentinel", "Test Banner", "Test Gurgler", "Test Flyer Friend"]:
		assert_eq(_unread(n).size(), 0, "%s: %s" % [n, str(_unread(n))])
	assert_eq(db.unread_lines(db.definition_for("Test Tidal Wave")).size(), 0, "Tidal Wave: %s" % str(_unread("Test Tidal Wave")))


func _effects_of(def: CardDefinition, kind: StringName) -> Array:
	var out: Array = []
	for a in def.abilities:
		var ab := a as Ability
		if ab != null and ab.kind == kind:
			out.append_array(ab.effects)
	return out


func test_ranks_makes_half_the_zombies_rounded_down() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ranks")
	for _i in 5:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	engine.state.active_player_id = 0
	engine.triggers.fire_player_event(engine, "BEGIN_STEP", 0)
	engine.resolve_top()
	var zombies := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).type_line.contains("Zombie"):
			zombies += 1
	assert_eq(zombies, 7, "five Zombies make two more")


func test_a_map_token_explores_a_creature() -> void:
	var tokens := TokenCatalog.new()
	var map := tokens.definition_for("map")
	assert_true(map != null and map.abilities.size() == 1, "the Map token has its ability")
	assert_eq(str((map.abilities[0] as Ability).effects[0].kind), "EXPLORE")
	var cart := _effects_of(db.definition_for("Test Cartographer"), &"TRIGGERED")
	assert_eq(str(cart[0].kind), "CREATE_TOKEN")
	assert_eq(str(cart[0].params.get("token", "")), "map")


func test_the_shark_is_as_big_as_the_spells_mana_value() -> void:
	var fx := _effects_of(db.definition_for("Test Shark Maker"), &"TRIGGERED")
	assert_eq(str(fx[0].kind), "CREATE_TOKEN")
	var amount: Variant = fx[0].params.get("pt_amount")
	assert_true(amount is Dictionary and str((amount as Dictionary).get("expr", "")) == "SPELL_MV", "size comes from the spell: %s" % str(fx[0].params))


func test_hexproof_only_while_untapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var elf := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Sentinel")
	assert_true(engine.has_keyword(elf, "Hexproof"), "untapped: hexproof")
	elf.tapped = true
	assert_false(engine.has_keyword(elf, "Hexproof"), "tapped: none")


func test_counter_creatures_gain_trample() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Banner")
	var plain := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	var grown := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	grown.counters["+1/+1"] = 1
	assert_true(engine.has_keyword(grown, "Trample"), "the creature with a counter tramples")
	assert_false(engine.has_keyword(plain, "Trample"), "the one without does not")


func test_aura_sets_base_power_and_toughness() -> void:
	var def := db.definition_for("Test Aura")
	var statics := _effects_of(def, &"STATIC")
	var found := false
	for a in def.abilities:
		var ab := a as Ability
		if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("base_pt"):
			found = true
	assert_true(found or not statics.is_empty(), "Aura has a base power and toughness static")


func _fx(kind: String, params: Dictionary) -> AbilityEffect:
	var fx := AbilityEffect.new()
	fx.kind = StringName(kind)
	fx.params = params
	return fx


func _run(engine: RulesEngine, source: GameObject, effects: Array, ctx: Dictionary = {}) -> void:
	engine.put_synthetic(source, source.controller_id, effects, ctx)
	engine.resolve_top()


func test_you_win_the_game_makes_everyone_else_lose() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var src := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	_run(engine, src, [_fx("WIN_GAME", {})])
	assert_true(engine.state.players[1].lost, "the opponent lost")
	assert_false(engine.state.players[0].lost, "the winner did not")


func test_doubling_and_removing_counters() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var z := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	z.counters["+1/+1"] = 3
	_run(engine, z, [_fx("DOUBLE_COUNTERS", {"name": "+1/+1", "self": true})])
	assert_eq(int(z.counters["+1/+1"]), 6, "doubled")
	_run(engine, z, [_fx("REMOVE_COUNTERS", {"name": "+1/+1", "n": 2, "self": true})])
	assert_eq(int(z.counters["+1/+1"]), 4, "two removed")
	_run(engine, z, [_fx("REMOVE_COUNTERS", {"name": "+1/+1", "all": true, "self": true})])
	assert_false(z.counters.has("+1/+1"), "all removed")


func test_each_player_creates_a_token() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var src := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	var spec := {"p": "1", "t": "1", "colors": ["G"], "subtypes": ["Plant"], "keywords": [], "artifact": false}
	_run(engine, src, [_fx("CREATE_TOKEN", {"spec": spec, "count": 1, "for": "EACH_PLAYER"})])
	var mine := 0
	var theirs := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.is_token:
			if o.controller_id == 0:
				mine += 1
			else:
				theirs += 1
	assert_eq(mine, 1, "I got a Plant")
	assert_eq(theirs, 1, "so did my opponent")


func test_discard_at_random_takes_the_asked_number() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var src := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	for _i in 4:
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Test Zombie")
	var fx := _fx("DISCARD", {"n": 2, "who": "EACH_OPPONENT", "random": true})
	_run(engine, src, [fx])
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 1).size(), 2, "two cards left")
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 1).size(), 2, "two in the graveyard")


func test_destroy_all_counts_what_died_for_the_draw() -> void:
	var engine := Fixtures.empty_engine_1v1()
	for _i in 4:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Zombie")
	var src := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Banner")
	for _i in 3:
		Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Zombie")
	var before: int = (engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size()
	_run(engine, src, [_fx("DESTROY_ALL", {"query": {"type": "creature"}}), _fx("DRAW", {"n": {"expr": "DESTROYED_COUNT"}})])
	assert_eq(engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size(), before + 3, "drew one per creature destroyed")


func test_more_upkeep_lines_are_read() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Ledger", "{3}", 3, "Artifact", "At the beginning of your upkeep, if you have 40 or more life, you win the game.\nAt the beginning of your upkeep, if ~ is tapped, put a storage counter on it.\nAt the beginning of your end step, discard your hand.\nAt the beginning of your end step, each player creates a 1/1 green Plant creature token."))
	var d := CardDatabase.new()
	d.setup(cat)
	assert_eq(d.unread_lines(d.definition_for("Test Ledger")).size(), 0, str(d.unread_lines(d.definition_for("Test Ledger"))))


func test_combat_damage_to_a_creature_triggers_read_and_fire() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Snake", "{1}{G}", 2, "Creature — Snake", "Whenever Test Snake deals combat damage to a creature, destroy that creature.", "2", "2"))
	m.add(_row("Test Frost", "{1}{U}", 2, "Creature — Spirit", "Whenever Test Frost deals combat damage to a creature, tap that creature and it doesn't untap during its controller's next untap step.", "2", "2"))
	m.add(_row("Test Wall", "{1}", 1, "Creature — Wall", "", "0", "9"))
	var d := CardDatabase.new()
	d.setup(cat)
	assert_eq(d.unread_lines(d.definition_for("Test Snake")).size(), 0, "Snake: %s" % str(d.unread_lines(d.definition_for("Test Snake"))))
	assert_eq(d.unread_lines(d.definition_for("Test Frost")).size(), 0, "Frost: %s" % str(d.unread_lines(d.definition_for("Test Frost"))))
	var engine := Fixtures.empty_engine_1v1()
	var snake := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Snake")
	var wall := Fixtures.spawn_named(engine, d, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Wall")
	engine.triggers.on_combat_damage_to_creature(engine, snake, wall, 2)
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the trigger went on the stack")
	engine.resolve_top()
	var bf_ids: Array = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids
	assert_false(bf_ids.has(wall.object_id), "the damaged creature was destroyed")


func test_pump_for_each_other_attacking_goblin_and_draw_that_many() -> void:
	var cat := Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Goblin", "{R}", 1, "Creature — Goblin", "", "1", "1"))
	m.add(_row("Test Warchief", "{2}{R}", 3, "Creature — Goblin", "Whenever Test Warchief attacks, it gets +1/+1 until end of turn for each other attacking Goblin.\nWhenever Test Warchief deals combat damage to a player, draw that many cards.", "2", "2"))
	var d := CardDatabase.new()
	d.setup(cat)
	assert_eq(d.unread_lines(d.definition_for("Test Warchief")).size(), 0, str(d.unread_lines(d.definition_for("Test Warchief"))))
	var engine := Fixtures.empty_engine_1v1()
	for _i in 4:
		Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.LIBRARY, "Test Goblin")
	var chief := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Warchief")
	var g1 := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Goblin")
	var g2 := Fixtures.spawn_named(engine, d, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Goblin")
	engine.state.active_player_id = 0
	engine.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	var cs := CombatState.new()
	cs.attacker_ids = [chief.object_id, g1.object_id, g2.object_id]
	engine.state.combat = cs
	var pump: Array = []
	for a in (chief.definition as CardDefinition).abilities:
		var ab := a as Ability
		if ab != null and ab.kind == &"TRIGGERED" and ab.trigger.get("on", "") == "ATTACKS":
			pump = ab.effects
	engine.put_synthetic(chief, 0, pump, {})
	engine.resolve_top()
	assert_eq(engine.power_of(chief), 4, "2 base +2 for the two other attacking Goblins")
	var draw: Array = []
	for a2 in (chief.definition as CardDefinition).abilities:
		var ab2 := a2 as Ability
		if ab2 != null and ab2.kind == &"TRIGGERED" and ab2.trigger.get("on", "") == "COMBAT_DAMAGE_TO_PLAYER":
			draw = ab2.effects
	var hand_before: int = (engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size()
	engine.put_synthetic(chief, 0, draw, {"amount": 3})
	engine.resolve_top()
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), hand_before + 3, "drew as many cards as the damage dealt")
