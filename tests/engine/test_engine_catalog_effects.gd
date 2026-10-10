@tool
extends McpTestSuite

## Effects added for catalog coverage (CatalogEffects and new sentence readers), each read from text and then played.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_catalog_effects"


func _row(card_name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "") -> Dictionary:
	return {name = card_name, oracle_id = card_name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Ambush", "{R}", 1, "Instant", "Test Ambush deals 4 damage to target attacking or blocking creature."))
	m.add(_row("Test Downfall", "{1}{B}", 2, "Instant", "Destroy target creature. Its controller loses 2 life."))
	m.add(_row("Test Scour", "{B}", 1, "Instant", "Exile up to one target card from a graveyard."))
	m.add(_row("Test Mantle", "{R}", 1, "Enchantment — Aura", "Enchant creature\n{B}: Regenerate enchanted creature.\n{1}: Untap enchanted creature."))
	m.add(_row("Test Ghoul", "{3}{B}", 4, "Creature — Zombie", "{B}{B}{B}: Return this card from your graveyard to the battlefield tapped.", "4", "4"))
	m.add(_row("Test Ring", "{2}{W}", 3, "Enchantment", "When this enchantment enters, exile another target nonland permanent.\nWhen this enchantment leaves the battlefield, return the exiled card to the battlefield under its owner's control."))
	m.add(_row("Test Lyre", "{3}", 3, "Artifact", "{T}: Flip a coin. If you win the flip, you gain 5 life. If you lose the flip, you lose 1 life."))
	m.add(_row("Test Seer", "{1}{G}", 2, "Creature — Elf", "{T}: Look at the top card of your library. If it's a land card, you may put it onto the battlefield tapped. If you don't put the card onto the battlefield, put it on the bottom of your library.", "1", "1"))
	m.add(_row("Test Exerter", "{1}{W}", 2, "Creature — Human Warrior", "You may exert this creature as it attacks. When you do, it gets +1/+2 until end of turn. (An exerted creature won't untap during your next untap step.)", "2", "2"))
	m.add(_row("Test Taskmaster", "{2}{W}", 3, "Creature — Human", "Whenever you exert a creature, you gain 2 life.", "1", "3"))
	m.add(_row("Test Slith", "{1}{W}", 2, "Creature — Phyrexian", "When this creature enters, you get {E}{E}.\nWhenever this creature attacks, you may pay {E}{E}. If you do, it gains first strike until end of turn.", "2", "1"))
	m.add(_row("Test Samurai Lord", "{2}{W}", 3, "Creature — Human Samurai", "Whenever a Samurai or Warrior you control attacks alone, it gets +2/+2 until end of turn.", "2", "2"))
	m.add(_row("Test Theorist", "{1}{U}{B}", 3, "Creature — Human", "Whenever you surveil, put a +1/+1 counter on this creature.", "2", "2"))
	m.add(_row("Test Shade", "{3}{B}", 4, "Snow Creature — Shade", "{S}: This creature gets +1/+1 until end of turn.", "1", "1"))
	db = CardDatabase.new()
	db.setup(m)


func _effects(obj: GameObject, kind: StringName = &"") -> Array:
	var out: Array = []
	for a in (obj.definition as CardDefinition).abilities:
		if kind == &"" or (a as Ability).kind == kind:
			out.append_array((a as Ability).effects)
	return out


func _run(engine: RulesEngine, source: GameObject, effects: Array, targets: Array = []) -> StackEntry:
	var e := engine.put_synthetic(source, source.controller_id, effects, {})
	e.targets = targets
	engine.resolve_top()
	return e


func test_every_line_reads() -> void:
	for n in ["Test Ambush", "Test Downfall", "Test Scour", "Test Mantle", "Test Ghoul", "Test Ring", "Test Lyre", "Test Seer",
			"Test Exerter", "Test Taskmaster", "Test Slith", "Test Samurai Lord", "Test Theorist", "Test Shade"]:
		var unread := db.unread_lines(db.definition_for(n))
		assert_eq(unread.size(), 0, "%s: %s" % [n, str(unread)])


func test_attacking_or_blocking_is_checked_when_targeting() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Ambush")
	var slot: Dictionary = ((spell.definition as CardDefinition).abilities[0] as Ability).targets[0]
	assert_false(engine.targeting.legal_ids(engine, slot, spell.object_id).has(bear.object_id), "not in combat: not a legal target")
	(engine.state.combat as CombatState).attacker_ids.append(bear.object_id)
	assert_true(engine.targeting.legal_ids(engine, slot, spell.object_id).has(bear.object_id), "attacking: legal")


func test_its_controller_loses_life_after_the_creature_is_gone() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Downfall")
	_run(engine, spell, _effects(spell), [bear.object_id])
	assert_eq(engine.state.players[1].life, 38)


func test_a_card_is_exiled_from_a_graveyard() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var dead := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.GRAVEYARD, "Test Bear")
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.STACK, "Test Scour")
	_run(engine, spell, _effects(spell), [dead.object_id])
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1) as Zone).size(), 1)


func test_an_aura_regenerates_and_untaps_what_it_enchants() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var aura := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Mantle")
	aura.attached_to = bear.object_id
	bear.tapped = true
	var acts: Array = []
	for a in (aura.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"ACTIVATED":
			acts.append(a)
	_run(engine, aura, (acts[0] as Ability).effects)
	assert_eq(bear.regen_shields, 1, "a regeneration shield")
	_run(engine, aura, (acts[1] as Ability).effects)
	assert_false(bear.tapped, "untapped")


func test_returning_itself_from_the_graveyard_tapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var ghoul := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Ghoul")
	_run(engine, ghoul, _effects(ghoul, &"ACTIVATED"))
	var bf := engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD) as Zone
	assert_eq(bf.size(), 1)
	assert_true((engine.state.objects[bf.object_ids[0]] as GameObject).tapped)


func test_the_old_oblivion_ring_returns_what_it_exiled() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var ring := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ring")
	var trig: Array = []
	for a in (ring.definition as CardDefinition).abilities:
		if (a as Ability).kind == &"TRIGGERED":
			trig.append(a)
	_run(engine, ring, (trig[0] as Ability).effects, [bear.object_id])
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 1) as Zone).size(), 1, "exiled")
	_run(engine, ring, (trig[1] as Ability).effects)
	var back := 0
	for oid in (engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD) as Zone).object_ids:
		if (engine.state.objects[oid] as GameObject).controller_id == 1:
			back += 1
	assert_eq(back, 1, "back under its owner")


func test_a_coin_flip_does_one_of_its_two_things() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var lyre := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Lyre")
	_run(engine, lyre, _effects(lyre, &"ACTIVATED"))
	var life := engine.state.players[0].life
	assert_true(life == 45 or life == 39, "won (+5) or lost (-1): %d" % life)


func test_a_top_land_goes_onto_the_battlefield_tapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Mountain")
	var seer := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Seer")
	_run(engine, seer, _effects(seer, &"ACTIVATED"))
	var land_found := false
	for oid in (engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD) as Zone).object_ids:
		var o: GameObject = engine.state.objects[oid]
		if (o.definition as CardDefinition).name == "Mountain":
			land_found = o.tapped
	assert_true(land_found, "the bot puts the land in play, tapped")


func _stack(engine: RulesEngine) -> Array:
	return (engine.state.stack as MagicStack).entries


## Resolves everything on the stack, answering yes to every question.
func _settle(engine: RulesEngine) -> void:
	var guard := 0
	while guard < 40:
		guard += 1
		engine.process_zone_events()
		if engine.state.mode == EngineEnums.EngineMode.AWAITING_DECISION and engine.state.pending_decision is PlayerDecision:
			var a := GameAction.new()
			a.player_id = (engine.state.pending_decision as PlayerDecision).player_id
			a.kind = GameAction.Kind.SUBMIT_DECISION
			engine.submit(a)
			continue
		if not _stack(engine).is_empty():
			engine.resolve_top()
			continue
		break


func test_exerting_as_it_attacks_pumps_it_and_keeps_it_tapped() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var guard := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Exerter")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Taskmaster")
	engine.triggers._fire(engine, "ATTACKS", guard, guard, {})
	_settle(engine)
	assert_eq(engine.toughness_of(guard), 4, "+1/+2 after exerting")
	assert_true(guard.marks.has("frozen"), "won't untap next untap step")
	assert_eq(engine.state.players[0].life, 42, "whenever you exert a creature")


func test_energy_is_paid_for_a_may_pay() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var slith := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Slith")
	engine.triggers._fire(engine, "ATTACKS", slith, slith, {})
	engine.resolve_top()
	assert_false(engine.has_keyword(slith, "First strike"), "no energy: nothing paid")
	engine.state.players[0].energy = 3
	engine.triggers._fire(engine, "ATTACKS", slith, slith, {})
	engine.resolve_top()
	assert_eq(engine.state.players[0].energy, 1, "two energy paid")
	assert_true(engine.has_keyword(slith, "First strike"))


func test_attacks_alone_checks_the_lone_attacker() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Samurai Lord")
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	var warrior := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Exerter")
	var e := GameEvent.new()
	e.type = EngineEnums.EventType.ATTACK
	e.player_id = 0
	e.payload = {"attackers": [bear.object_id]}
	engine.triggers._on_attack(engine, e)
	var before := 0
	for s in _stack(engine):
		if (s as StackEntry).source_id != bear.object_id:
			before += 1
	assert_eq(before, 0, "a Bear attacking alone isn't a Samurai or Warrior")
	e.payload = {"attackers": [warrior.object_id]}
	engine.triggers._on_attack(engine, e)
	_settle(engine)
	var bonus := 0
	for ce in engine.state.effects:
		if (ce as ContinuousEffect).object_ids.has(warrior.object_id) and (ce as ContinuousEffect).power == 2:
			bonus += 1
	assert_eq(bonus, 1, "+2/+2 on the lone Warrior")


func test_surveil_sets_off_whenever_you_surveil() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Bear")
	var mirko := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Theorist")
	var fx := AbilityEffect.new()
	fx.kind = &"SURVEIL"
	fx.params = {"n": 1}
	engine.put_synthetic(mirko, 0, [fx], {})
	engine.resolve_top()
	assert_eq(_stack(engine).size(), 1, "the surveil trigger")
	engine.resolve_top()
	assert_eq(int(mirko.counters.get("+1/+1", 0)), 1)


func test_snow_mana_is_paid_as_generic() -> void:
	var shade := db.definition_for("Test Shade")
	var act: Ability = null
	for a in shade.abilities:
		if (a as Ability).kind == &"ACTIVATED":
			act = a
	assert_true(act != null, "the {S} ability reads")
	var mana := ""
	for c in act.costs:
		if (c as AbilityCost).kind == &"MANA":
			mana = str((c as AbilityCost).mana)
	assert_eq(ManaCost.parse(mana).generic, 1)
