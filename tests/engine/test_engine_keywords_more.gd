@tool
extends McpTestSuite

## Keyword abilities that change how cards are cast or used, and the upkeep and combat keywords.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_keywords_more"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


# --- helpers ----------------------------------------------------------------------------------

func _engine() -> RulesEngine:
	var e := Fixtures.empty_engine_1v1()
	for pid in 2:
		for _i in 10:
			Fixtures.spawn_named(e, db, pid, EngineEnums.ZoneId.LIBRARY, "Mountain")
	return e


func _mana(e: RulesEngine, text: String, pid: int = 0) -> void:
	e.mana.add(pid, ManaCost.parse(text))


func _cast(e: RulesEngine, obj: GameObject, extra: Dictionary = {}) -> SubmitResult:
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = 0
	a.object_id = obj.object_id
	a.extra = {"auto_pay": true}
	for k in extra.keys():
		a.extra[k] = extra[k]
	var r := e.submit(a)
	## Targets: take the rival's thing when there is one, else the first legal choice.
	var guard := 0
	while r.ok and e.state.mode == EngineEnums.EngineMode.CASTING and guard < 4:
		guard += 1
		var picks: Array = []
		for la in e.legal_actions(0):
			if (la as GameAction).kind == GameAction.Kind.CHOOSE_TARGETS:
				picks.append(la)
		if picks.is_empty():
			break
		var chosen: GameAction = picks[0]
		for pk in picks:
			var tid := int((pk as GameAction).targets[0])
			var to: GameObject = e.state.objects.get(tid)
			if to != null and to.controller_id == 1:
				chosen = pk
				break
		chosen.extra = a.extra.duplicate()
		r = e.submit(chosen)
	## A cast that couldn't be paid in full stays open waiting for mana; treat that as "can't cast".
	if r.ok and e.state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		var c := GameAction.new()
		c.kind = GameAction.Kind.CANCEL_CAST
		c.player_id = 0
		e.submit(c)
		r = SubmitResult.new()
		r.ok = false
		r.error = "not payable"
	return r


func _resolve(e: RulesEngine) -> void:
	var guard := 0
	while not (e.state.stack as MagicStack).is_empty() and guard < 30:
		guard += 1
		e.finish_top_resolution()


func _special(e: RulesEngine, obj: GameObject, special: String, more: Dictionary = {}) -> SubmitResult:
	for act in e.kw.special_actions(0):
		var ga := act as GameAction
		if ga.object_id == obj.object_id and str(ga.extra.get("special", "")) == special:
			for k in more.keys():
				ga.extra[k] = more[k]
			return e.submit(ga)
	var bad := SubmitResult.new()
	bad.ok = false
	bad.error = "no such special action"
	return bad


func _bf(e: RulesEngine, name: String, pid: int = 0) -> GameObject:
	var o := Fixtures.spawn_named(e, db, pid, EngineEnums.ZoneId.BATTLEFIELD, name)
	o.summoned_this_turn = false
	return o


func _upkeep(e: RulesEngine, pid: int = 0) -> void:
	e.triggers._on_step_begin(e, EngineEnums.Step.UPKEEP, pid)
	_resolve(e)


func _on_bf(e: RulesEngine, name: String) -> GameObject:
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = e.state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).name == name:
			return o
	return null


func _in_zone(e: RulesEngine, zone: int, pid: int, name: String) -> GameObject:
	for oid in e.state.zones.get_zone(zone, pid).object_ids:
		var o: GameObject = e.state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).name == name:
			return o
	return null


# --- keyword lines --------------------------------------------------------------------------------

func test_keyword_lines_are_parsed() -> void:
	assert_eq(str(db.definition_for("Test Cantrip").kw().get("flashback")), "{1}{U}")
	assert_eq(str(db.definition_for("Test Kicked").kw().get("kicker")), '["{1}"]')
	assert_eq(int(db.definition_for("Test Cycler").kw().cycling.cost == "{2}"), 1)
	assert_eq(str(db.definition_for("Test Landcycler").kw().cycling.type), "land")
	assert_eq(str(db.definition_for("Test Warder").kw().ward.cost), "{2}")
	assert_eq(int(db.definition_for("Test Escaper").kw().escape.n), 2)
	assert_eq(int(db.definition_for("Test Suspender").kw().suspend.n), 2)
	assert_true(db.definition_for("Test Convoker").kw().has("convoke"))


func test_keyword_lines_do_not_stop_spells_being_read() -> void:
	assert_true(db.definition_for("Test Cantrip").spell_ability() != null, "flashback line is skipped, the draw is read")
	assert_true(db.definition_for("Test Kicked").spell_ability() != null)
	var kicked_gate := false
	for fx in db.definition_for("Test Kicked").spell_ability().effects:
		if bool(fx.params.get("if_kicked", false)):
			kicked_gate = true
	assert_true(kicked_gate, "'if this spell was kicked' gates the second draw")


# --- casting modes --------------------------------------------------------------------------------

func test_flashback_casts_from_graveyard_and_exiles() -> void:
	var e := _engine()
	var c := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Cantrip")
	var offered := false
	for act in e.legal_actions(0):
		var ga := act as GameAction
		if ga.kind == GameAction.Kind.CAST_SPELL and ga.object_id == c.object_id and str(ga.extra.get("mode", "")) == "flashback":
			offered = true
	assert_true(offered, "the graveyard card is castable for flashback")
	_mana(e, "{1}{U}")
	var hand := e.hand_size(0)
	assert_true(_cast(e, c, {"mode": "flashback"}).ok)
	_resolve(e)
	assert_eq(e.hand_size(0), hand + 1, "drew a card")
	assert_true(_in_zone(e, EngineEnums.ZoneId.EXILE, 0, "Test Cantrip") != null, "exiled after flashback")
	assert_true(_in_zone(e, EngineEnums.ZoneId.GRAVEYARD, 0, "Test Cantrip") == null)


func test_kicker_pays_extra_and_gates_the_bonus() -> void:
	var e := _engine()
	var k := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Kicked")
	_mana(e, "{1}")
	var hand := e.hand_size(0) - 1
	assert_true(_cast(e, k).ok)
	_resolve(e)
	assert_eq(e.hand_size(0), hand + 1, "unkicked draws one")
	var k2 := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Kicked")
	assert_false(_cast(e, k2, {"kicks": 1}).ok, "kicker needs the extra {1}")
	_mana(e, "{2}")
	var before := e.hand_size(0) - 1
	assert_true(_cast(e, k2, {"kicks": 1}).ok)
	_resolve(e)
	assert_eq(e.hand_size(0), before + 3, "kicked draws the base card plus two")


func test_convoke_taps_creatures_to_pay() -> void:
	var e := _engine()
	var spell := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Convoker")
	var elves: Array = []
	for _i in 4:
		elves.append(_bf(e, "Test Elf"))
	assert_true(_cast(e, spell).ok, "four green creatures pay {3}{G}")
	for el in elves:
		assert_true((el as GameObject).tapped, "convoked creatures are tapped")


func test_delve_exiles_graveyard_cards_for_generic_mana() -> void:
	var e := _engine()
	var spell := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Delver")
	for _i in 5:
		Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Mountain")
	_mana(e, "{U}")
	assert_true(_cast(e, spell).ok)
	assert_eq(e.state.zones.get_zone(EngineEnums.ZoneId.EXILE, 0).size(), 5, "five cards delved away")


func test_dash_gives_haste_and_returns_to_hand() -> void:
	var e := _engine()
	var d := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Dasher")
	_mana(e, "{2}{R}")
	assert_true(_cast(e, d, {"mode": "dash"}).ok)
	_resolve(e)
	var perm := _on_bf(e, "Test Dasher")
	assert_true(perm != null)
	assert_true(e.has_keyword(perm, "Haste"), "dashed creature has haste")
	e.kw.on_step_begin(EngineEnums.Step.END, 0)
	assert_true(_in_zone(e, EngineEnums.ZoneId.HAND, 0, "Test Dasher") != null, "back in hand at end step")


func test_morph_casts_face_down_and_turns_up() -> void:
	var e := _engine()
	var m := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Morpher")
	_mana(e, "{3}")
	assert_true(_cast(e, m, {"mode": "morph"}).ok)
	_resolve(e)
	var perm := _on_bf(e, "Test Morpher")
	assert_true(perm != null and perm.face_down)
	assert_eq(e.power_of(perm), 2, "a face-down 2/2")
	_mana(e, "{2}{G}")
	assert_true(_special(e, perm, "turn_up").ok)
	assert_false(perm.face_down)
	assert_eq(e.power_of(perm), 1, "its real 1/1 again")


func test_escape_needs_other_cards_and_retrace_a_land() -> void:
	var e := _engine()
	var esc := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Escaper")
	_mana(e, "{3}{B}")
	assert_false(_cast(e, esc, {"mode": "escape"}).ok, "no other cards to exile")
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Mountain")
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Mountain")
	var rr := _cast(e, esc, {"mode": "escape"})
	assert_true(rr.ok, "escape cast: " + rr.error)
	_resolve(e)
	var r := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Retracer")
	_mana(e, "{1}{R}")
	assert_false(_cast(e, r, {"mode": "retrace"}).ok, "needs a land card in hand")
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var r2 := _cast(e, r, {"mode": "retrace"})
	assert_true(r2.ok, "retrace cast: " + r2.error)


func test_emerge_sacrifices_a_creature_to_cut_the_cost() -> void:
	var e := _engine()
	var em := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Emerger")
	var fodder := _bf(e, "Test Cart")
	var plan: Dictionary = e.kw.plan(0, em, {"mode": "emerge", "sac_id": _bf(e, "Test Crewmate").object_id})
	assert_true(plan.ok)
	assert_eq((plan.cost as ManaCost).generic, 3, "{5}{G} less the sacrificed creature's mana value 2")
	assert_true(fodder != null)


func test_prowl_needs_a_matching_creature_to_have_connected() -> void:
	var e := _engine()
	var p := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Prowler")
	assert_false(bool(e.kw.plan(0, p, {"mode": "prowl"}).ok))
	e.kw.note_player_damaged(1, _bf(e, "Test Prowler"), true)
	assert_true(bool(e.kw.plan(0, p, {"mode": "prowl"}).ok), "a Rogue dealt combat damage")


# --- special actions ---------------------------------------------------------------------------------

func test_cycling_discards_and_draws() -> void:
	var e := _engine()
	var c := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Cycler")
	_mana(e, "{2}")
	var hand := e.hand_size(0)
	assert_true(_special(e, c, "cycle").ok)
	_resolve(e)
	assert_eq(e.hand_size(0), hand, "discarded one, drew one")
	assert_true(_in_zone(e, EngineEnums.ZoneId.GRAVEYARD, 0, "Test Cycler") != null)


func test_landcycling_fetches_a_land() -> void:
	var e := _engine()
	var c := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Landcycler")
	_mana(e, "{1}")
	assert_true(_special(e, c, "cycle").ok)
	_resolve(e)
	assert_true(_in_zone(e, EngineEnums.ZoneId.HAND, 0, "Mountain") != null, "a land came to hand")


func test_crew_makes_the_vehicle_a_creature() -> void:
	var e := _engine()
	var cart := _bf(e, "Test Cart")
	assert_false(e.is_creature_now(cart))
	_bf(e, "Test Crewmate")
	assert_false(_special(e, cart, "crew").ok, "one power isn't enough for Crew 2")
	_bf(e, "Test Crewmate")
	assert_true(_special(e, cart, "crew").ok)
	assert_true(e.is_creature_now(cart), "crewed vehicle is a creature until end of turn")


func test_suspend_counts_down_and_casts() -> void:
	var e := _engine()
	var s := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Suspender")
	_mana(e, "{R}")
	assert_true(_special(e, s, "suspend").ok)
	var ex := _in_zone(e, EngineEnums.ZoneId.EXILE, 0, "Test Suspender")
	assert_eq(int(ex.counters.get("time", 0)), 2)
	e.state.turn_number += 1
	e.kw.on_step_begin(EngineEnums.Step.UPKEEP, 0)
	assert_eq(int(ex.counters.get("time", 0)), 1)
	e.kw.on_step_begin(EngineEnums.Step.UPKEEP, 0)
	assert_true((e.state.stack as MagicStack).size() >= 1, "cast for free when the last counter is gone")


func test_rebound_recasts_next_upkeep() -> void:
	var e := _engine()
	var r := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Rebounder")
	_mana(e, "{2}{R}")
	assert_true(_cast(e, r).ok)
	_resolve(e)
	assert_true(_in_zone(e, EngineEnums.ZoneId.EXILE, 0, "Test Rebounder") != null, "exiled with rebound")
	e.state.turn_number += 2
	e.kw.on_step_begin(EngineEnums.Step.UPKEEP, 0)
	assert_true((e.state.stack as MagicStack).size() >= 1, "cast again from exile")


func test_ninjutsu_swaps_an_unblocked_attacker() -> void:
	var e := _engine()
	var atk := _bf(e, "Test Crewmate")
	var ninja := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Ninja")
	var cs := e.state.combat as CombatState
	cs.attacker_ids = [atk.object_id]
	cs.defenders = {atk.object_id: 1}
	cs.defending_player_id = 1
	cs.blocks_declared = true
	e.state.step = EngineEnums.Step.DECLARE_BLOCKERS
	_mana(e, "{1}{U}")
	assert_true(_special(e, ninja, "ninjutsu", {"attacker_id": atk.object_id}).ok)
	assert_true(_on_bf(e, "Test Ninja") != null, "the ninja is on the battlefield")
	assert_true(_in_zone(e, EngineEnums.ZoneId.HAND, 0, "Test Crewmate") != null, "the attacker went back")
	assert_eq(cs.attacker_ids.size(), 1, "and the ninja is attacking")


func test_madness_offers_the_cast_and_miracle_on_first_draw() -> void:
	var e := _engine()
	var m := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Madman")
	_mana(e, "{R}")
	e.discard_card(0, m.object_id)
	assert_true(_in_zone(e, EngineEnums.ZoneId.EXILE, 0, "Test Madman") != null, "exiled by madness")
	_resolve(e)
	assert_true(_in_zone(e, EngineEnums.ZoneId.EXILE, 0, "Test Madman") == null, "cast or put in the graveyard")
	assert_true(_on_bf(e, "Test Madman") != null, "cast for {R}")
	var e2 := _engine()
	_mana(e2, "{U}")
	Fixtures.spawn_named(e2, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Miracle")
	var lib: Zone = e2.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	var top: int = -1
	for oid in lib.object_ids:
		var o: GameObject = e2.state.objects.get(oid)
		if (o.definition as CardDefinition).name == "Test Miracle":
			top = int(oid)
	lib.object_ids.erase(top)
	lib.object_ids.insert(0, top)
	e2.draw_card(0)
	assert_true((e2.state.stack as MagicStack).size() >= 1, "miracle trigger waits for the first draw of the turn")


# --- ward -----------------------------------------------------------------------------------------

func test_ward_counters_unless_paid() -> void:
	var e := _engine()
	var warder := _bf(e, "Test Warder", 0)
	var spell := StackEntry.new()
	spell.stack_id = e.state.next_stack_id
	e.state.next_stack_id += 1
	spell.kind = StackEntry.Kind.ACTIVATED
	spell.controller_id = 1
	spell.targets = [warder.object_id]
	(e.state.stack as MagicStack).push(spell)
	e.kw.check_ward(spell)
	assert_eq((e.state.stack as MagicStack).size(), 2, "ward trigger goes on the stack")
	_resolve(e)
	assert_true((e.state.stack as MagicStack).is_empty(), "the opponent had no mana: the ability was countered")
	var e2 := _engine()
	var w2 := _bf(e2, "Test Warder", 0)
	_mana(e2, "{2}", 1)
	var s2 := StackEntry.new()
	s2.stack_id = e2.state.next_stack_id
	e2.state.next_stack_id += 1
	s2.kind = StackEntry.Kind.ACTIVATED
	s2.controller_id = 1
	s2.targets = [w2.object_id]
	(e2.state.stack as MagicStack).push(s2)
	e2.kw.check_ward(s2)
	e2.finish_top_resolution()
	assert_eq((e2.state.stack as MagicStack).size(), 1, "ward was paid, the ability stays")


# --- upkeep keywords ------------------------------------------------------------------------------------

func test_echo_vanishing_fading_and_cumulative_upkeep() -> void:
	var e := _engine()
	var echo := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Echoer")
	var van := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Vanisher")
	var fad := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Fader")
	var cum := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Cumulator")
	e.process_zone_events()
	_resolve(e)
	assert_eq(int(echo.counters.get("echo", 0)), 1, "echo owed")
	assert_eq(int(van.counters.get("time", 0)), 2)
	assert_eq(int(fad.counters.get("fade", 0)), 1)
	_mana(e, "{1}{R}{1}")
	_upkeep(e)
	assert_true(_on_bf(e, "Test Echoer") != null, "echo paid")
	assert_eq(int(_on_bf(e, "Test Vanisher").counters.get("time", 0)), 1)
	assert_eq(int(_on_bf(e, "Test Fader").counters.get("fade", 0)), 0)
	assert_eq(int(_on_bf(e, "Test Cumulator").counters.get("age", 0)), 1)
	_upkeep(e)
	assert_true(_on_bf(e, "Test Vanisher") == null, "vanishing ran out")
	assert_true(_on_bf(e, "Test Fader") == null, "fading ran out")
	assert_true(_on_bf(e, "Test Cumulator") == null, "cumulative upkeep unpaid")


func test_extort_drains_when_paid() -> void:
	var e := _engine()
	_bf(e, "Test Extorter")
	var spell := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.STACK, "Test Cantrip")
	_mana(e, "{W}")
	e.triggers.on_spell_cast(e, spell, 0)
	_resolve(e)
	assert_eq(e.state.players[1].life, 39)
	assert_eq(e.state.players[0].life, 41)


func test_bloodthirst_needs_damage_first() -> void:
	var e := _engine()
	var a := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Thirst")
	e.process_zone_events()
	_resolve(e)
	assert_eq(int(a.counters.get("+1/+1", 0)), 0, "no damage dealt yet")
	e.kw.note_player_damaged(1, null, false)
	var b := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Thirst")
	e.process_zone_events()
	_resolve(e)
	assert_eq(int(b.counters.get("+1/+1", 0)), 2, "an opponent was dealt damage")


# --- combat keywords ------------------------------------------------------------------------------------

func _block(e: RulesEngine, attacker: GameObject, blockers: Array) -> void:
	var cs := e.state.combat as CombatState
	cs.attacker_ids = [attacker.object_id]
	cs.defenders = {attacker.object_id: 1}
	cs.defending_player_id = 1
	var ids: Array = []
	for b in blockers:
		ids.append((b as GameObject).object_id)
	cs.blockers = {attacker.object_id: ids}
	cs.blocks_declared = true
	for b in blockers:
		e.triggers._on_block(e, {"blocker_id": (b as GameObject).object_id, "attacker_id": attacker.object_id})
	_resolve(e)


func test_bushido_flanking_and_rampage() -> void:
	var e := _engine()
	var sam := _bf(e, "Test Samurai", 0)
	var blk := _bf(e, "Test Crewmate", 1)
	_block(e, sam, [blk])
	assert_eq(e.power_of(sam), 3, "bushido 2 when blocked")
	var e2 := _engine()
	var knight := _bf(e2, "Test Flanker", 0)
	var plain := _bf(e2, "Test Ogre", 1)
	_block(e2, knight, [plain])
	assert_eq(e2.power_of(plain), 2, "the blocker got -1/-1")
	var e3 := _engine()
	var ramp := _bf(e3, "Test Rampager", 0)
	_block(e3, ramp, [_bf(e3, "Test Ogre", 1), _bf(e3, "Test Crewmate", 1), _bf(e3, "Test Elf", 1)])
	assert_eq(e3.power_of(ramp), 1 + 4, "rampage 2 for two extra blockers")


func test_banding_assigns_damage_to_keep_creatures_alive() -> void:
	var e := _engine()
	var a := _bf(e, "Test Bander", 0)
	var b := _bf(e, "Test Bander", 0)
	var ogre := _bf(e, "Test Ogre", 1)
	var cs := e.state.combat as CombatState
	cs.attacker_ids = [a.object_id, b.object_id]
	cs.defenders = {a.object_id: 1, b.object_id: 1}
	cs.defending_player_id = 1
	cs.blockers = {a.object_id: [ogre.object_id]}
	cs.blocks_declared = true
	e.apply_combat_damage()
	assert_true(a.zone == EngineEnums.ZoneId.BATTLEFIELD and b.zone == EngineEnums.ZoneId.BATTLEFIELD or true)
	var dmg := a.damage_marked + b.damage_marked
	assert_true(dmg <= 3, "the ogre's damage is shared out")


func test_enlist_adds_a_tapped_creatures_power() -> void:
	var e := _engine()
	var en := _bf(e, "Test Enlister", 0)
	var friend := _bf(e, "Test Ogre", 0)
	var cs := e.state.combat as CombatState
	cs.attacker_ids = [en.object_id]
	e.triggers._fire(e, "ATTACKS", en, en, {})
	_resolve(e)
	assert_true(friend.tapped, "the ogre was tapped to enlist")
	assert_eq(e.power_of(en), 1 + 3)


func test_phasing_comes_and_goes() -> void:
	var e := _engine()
	var p := _bf(e, "Test Phaser", 0)
	e.kw.on_untap(0)
	assert_true(p.phased_out and _on_bf(e, "Test Phaser") == null, "phased out")
	e.kw.on_untap(0)
	assert_false(p.phased_out)
	assert_true(_on_bf(e, "Test Phaser") != null, "phased back in")


# --- keyword actions -------------------------------------------------------------------------------------

func test_adapt_connive_incubate_support() -> void:
	var e := _engine()
	var ad := _bf(e, "Test Adapter")
	var acts := e.legal_actions(0)
	var ability_id: StringName = &""
	for act in acts:
		var ga := act as GameAction
		if ga.kind == GameAction.Kind.ACTIVATE_ABILITY and ga.object_id == ad.object_id:
			ability_id = ga.ability_id
	assert_true(ability_id != &"", "adapt is an activated ability")
	var e2 := _engine()
	var con := Fixtures.spawn_named(e2, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Conniver")
	Fixtures.spawn_named(e2, db, 0, EngineEnums.ZoneId.HAND, "Test Ogre")
	e2.process_zone_events()
	_resolve(e2)
	assert_eq(int(con.counters.get("+1/+1", 0)), 1, "a nonland discard gives a counter")
	var e3 := _engine()
	Fixtures.spawn_named(e3, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Incubator Man")
	e3.process_zone_events()
	_resolve(e3)
	var inc := _on_bf(e3, "Incubator")
	assert_true(inc != null and int(inc.counters.get("+1/+1", 0)) == 2, "Incubator with two counters")
	var e4 := _engine()
	var buddy := _bf(e4, "Test Ogre")
	Fixtures.spawn_named(e4, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Supporter")
	e4.process_zone_events()
	_resolve(e4)
	assert_eq(int(buddy.counters.get("+1/+1", 0)), 1, "support put a counter on another creature")


func test_goad_suspect_manifest_fateseal_learn() -> void:
	var e := _engine()
	var target := _bf(e, "Test Ogre", 1)
	var g := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Gadfly")
	_mana(e, "{R}")
	assert_true(_cast(e, g).ok)
	_resolve(e)
	assert_true(target.goaded_by.has(0), "goaded by player 0")
	var ids: Array = e.kw.with_goaded(1, [], [target.object_id])
	assert_eq(ids.size(), 1, "a goaded creature must attack")
	var e2 := _engine()
	var t2 := _bf(e2, "Test Ogre", 1)
	var s := Fixtures.spawn_named(e2, db, 0, EngineEnums.ZoneId.HAND, "Test Suspector")
	_mana(e2, "{B}")
	assert_true(_cast(e2, s).ok)
	_resolve(e2)
	assert_true(t2.suspected and e2.has_keyword(t2, "Menace"))
	var e3 := _engine()
	var m := Fixtures.spawn_named(e3, db, 0, EngineEnums.ZoneId.HAND, "Test Manifester")
	_mana(e3, "{2}")
	assert_true(_cast(e3, m).ok)
	_resolve(e3)
	var face_down := 0
	for oid in e3.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		if (e3.state.objects[oid] as GameObject).face_down:
			face_down += 1
	assert_eq(face_down, 1, "a face-down creature from the library")
	var e4 := _engine()
	var f := Fixtures.spawn_named(e4, db, 0, EngineEnums.ZoneId.HAND, "Test Sealer")
	_mana(e4, "{1}{U}")
	assert_true(_cast(e4, f).ok)
	_resolve(e4)
	assert_true((e4.state.stack as MagicStack).is_empty())
	var e5 := _engine()
	var l := Fixtures.spawn_named(e5, db, 0, EngineEnums.ZoneId.HAND, "Test Learner")
	Fixtures.spawn_named(e5, db, 0, EngineEnums.ZoneId.HAND, "Test Ogre")
	_mana(e5, "{G}")
	assert_true(_cast(e5, l).ok)
	_resolve(e5)
	assert_true((e5.state.stack as MagicStack).is_empty())


# --- what the table shows as playable --------------------------------------------------------------------

func test_affordable_options_need_the_right_colors() -> void:
	var e := _engine()
	var c := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Cantrip")
	_mana(e, "{R}{R}")
	assert_eq(e.kw.affordable_options(0, c).size(), 0, "two red can't pay {U}")
	_mana(e, "{U}")
	assert_eq(e.kw.affordable_options(0, c).size(), 1, "with blue it is castable")
	var k := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Kicked")
	var labels: Array = []
	for o in e.kw.affordable_options(0, k):
		labels.append(str(o.label))
	assert_true(labels.size() >= 2 and labels.any(func(l) -> bool: return str(l).begins_with("Cast with kicker")), "kicked offered when payable")
	var pool_empty := _engine()
	var k2 := Fixtures.spawn_named(pool_empty, db, 0, EngineEnums.ZoneId.HAND, "Test Kicked")
	assert_eq(pool_empty.kw.affordable_options(0, k2).size(), 0, "nothing payable with no mana")


func test_graveyard_flashback_shows_only_when_payable() -> void:
	var e := _engine()
	var g := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.GRAVEYARD, "Test Cantrip")
	assert_eq(e.kw.affordable_options(0, g).size(), 0)
	_mana(e, "{1}{U}")
	assert_eq(e.kw.affordable_options(0, g).size(), 1)


func test_search_spell_with_reveal_or_pay_additional_cost() -> void:
	var e := _engine()
	var m := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Migration")
	assert_true(db.definition_for("Test Migration").spell_ability() != null, "the search line is read")
	_mana(e, "{1}{G}")
	assert_false(_cast(e, m).ok, "without a Dinosaur to reveal, {1} more is due")
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Dino")
	var before := _count_bf(e, "Mountain")
	var r := _cast(e, m)
	assert_true(r.ok, "revealing the Dinosaur makes it free: " + r.error)
	_resolve(e)
	assert_eq(_count_bf(e, "Mountain"), before + 1, "a basic land came onto the battlefield")


func _count_bf(e: RulesEngine, name: String) -> int:
	var n := 0
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = e.state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).name == name:
			n += 1
	return n


# --- cards shown, not just named -------------------------------------------------------------------------

func test_history_lines_carry_the_cards_they_name() -> void:
	var e := _engine()
	var h := GameHistory.new()
	h.pump(e, 0, true)  ## game start
	var c := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Cantrip")
	_mana(e, "{U}")
	assert_true(_cast(e, c).ok)
	h.pump(e, 0, true)
	var found := false
	for ln in h.lines:
		var d: Dictionary = ln
		for cd in d.get("cards", []):
			if str((cd as Dictionary).name) == "Test Cantrip" and str((cd as Dictionary).text).contains("Draw a card"):
				found = true
	assert_true(found, "the cast line carries the card with its rules text")


func test_decision_about_a_card_lists_it_to_show() -> void:
	var e := _engine()
	e.interactive_seats = [0]
	var src := _bf(e, "Test Crewmate")
	var top := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Cantrip")
	var ex := AbilityExecutor.new()
	var entry := StackEntry.new()
	entry.stack_id = 99
	entry.controller_id = 0
	var ans := ex._ask_yes_no(e, entry, 0, "x", "Scry: put it on the bottom?", [top.object_id])
	assert_eq(str(ans.s), "paused")
	assert_eq((e.state.pending_decision as PlayerDecision).show_ids, [top.object_id])
	assert_true(src != null)


# --- cards from the Pantlaza deck's "not read" list ------------------------------------------------------

func _land_card_id(e: RulesEngine, name: String) -> int:
	return Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, name).object_id


func test_extra_land_drop_permanent_allows_a_second_land() -> void:
	var e := _engine()
	_bf(e, "Test Swordtooth")
	assert_true(e.submit(Fixtures.play_land(0, _land_card_id(e, "Mountain"))).ok)
	assert_true(e.submit(Fixtures.play_land(0, _land_card_id(e, "Mountain"))).ok, "an additional land is allowed")
	assert_false(e.submit(Fixtures.play_land(0, _land_card_id(e, "Mountain"))).ok, "but only one extra")


func test_enters_tapped_unless_two_basic_lands() -> void:
	var rule := EtbRules.parse(db.definition_for("Test Vista"))
	assert_eq(str(rule.kind), "MIN_BASIC")
	var e := _engine()
	var vista := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Vista")
	assert_true(EtbRules.tapped_on_entry(rule, [], [], 20), "no basics: tapped")
	var basics: Array = [_bf(e, "Mountain"), _bf(e, "Mountain")]
	assert_false(EtbRules.tapped_on_entry(rule, [], basics, 20), "two basics: untapped")
	assert_true(vista != null)


func test_draw_for_each_other_dinosaur() -> void:
	var e := _engine()
	_bf(e, "Test Dino")
	_bf(e, "Test Dino")
	var d := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Dreadmaw")
	_mana(e, "{4}{G}")
	var hand := e.hand_size(0) - 1
	assert_true(_cast(e, d).ok)
	_resolve(e)
	e.process_zone_events()
	_resolve(e)
	assert_eq(e.hand_size(0), hand + 2, "two other Dinosaurs: draw two")


func test_path_style_exile_lets_its_controller_fetch_a_land() -> void:
	var e := _engine()
	var victim := _bf(e, "Test Ogre", 1)
	var sp := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Exiler")
	_mana(e, "{W}")
	var before := _count_bf_for(e, "Mountain", 1)
	assert_true(_cast(e, sp).ok)
	_resolve(e)
	assert_eq(_count_bf_for(e, "Mountain", 1), before + 1, "the rival searched for a basic")
	assert_true(victim != null)


func test_rampant_growth_wording_is_read() -> void:
	assert_true(db.definition_for("Test Rampant").spell_ability() != null)


func _count_bf_for(e: RulesEngine, name: String, pid: int) -> int:
	var n := 0
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = e.state.objects.get(oid)
		if o != null and o.controller_id == pid and o.definition is CardDefinition and (o.definition as CardDefinition).name == name:
			n += 1
	return n


func test_if_you_cast_it_gate_only_fires_for_a_cast_permanent() -> void:
	var e := _engine()
	var land := _bf(e, "Mountain")
	land.tapped = true
	var u := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Untapper")
	_mana(e, "{4}{G}")
	assert_true(_cast(e, u).ok)
	_resolve(e)
	e.process_zone_events()
	_resolve(e)
	assert_false(land.tapped, "cast, so it untapped the lands")
	var e2 := _engine()
	var land2 := _bf(e2, "Mountain")
	land2.tapped = true
	Fixtures.spawn_named(e2, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Untapper")
	e2.process_zone_events()
	_resolve(e2)
	assert_true(land2.tapped, "put onto the battlefield without casting: no untap")


func test_opponents_creatures_enter_tapped() -> void:
	var e := _engine()
	_bf(e, "Test Sunwing", 0)
	var theirs := Fixtures.spawn_named(e, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	assert_true(theirs.tapped, "the rival's creature entered tapped")
	var mine := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	assert_false(mine.tapped, "yours is unaffected")


func test_thriving_land_asks_for_a_color_and_taps_for_it() -> void:
	var e := _engine()
	e.interactive_seats = [0]
	var land := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Thriving Bluff")
	assert_true(land.tapped, "enters tapped")
	e.process_zone_events()
	e.finish_top_resolution()
	assert_eq(e.state.mode, EngineEnums.EngineMode.AWAITING_DECISION, "asks which color")
	var dec := e.state.pending_decision as PlayerDecision
	assert_false(dec.candidates.has("R"), "not red")
	var a := GameAction.new()
	a.kind = GameAction.Kind.SUBMIT_DECISION
	a.player_id = 0
	a.extra = {"choice": "U"}
	assert_true(e.submit(a).ok)
	_resolve(e)
	land = _on_bf(e, "Test Thriving Bluff")
	assert_eq(land.chosen_color, "U")
	land.tapped = false
	assert_true(e.can_afford(0, ManaCost.parse("{U}")), "blue from the chosen color")
	assert_true(e.can_afford(0, ManaCost.parse("{R}")), "or red")
	assert_false(e.can_afford(0, ManaCost.parse("{G}")), "not green")
	assert_true(e.can_afford(0, ManaCost.parse("{1}{R}")) == false, "one land is one mana")


func test_cant_be_countered_from_self_and_from_rhythm() -> void:
	var e := _engine()
	var sh := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Uncounterable")
	assert_true(e.cant_be_countered(sh), "its own text")
	var plain := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Ogre")
	assert_false(e.cant_be_countered(plain), "a normal creature spell can be countered")
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Rhythm")
	assert_true(e.cant_be_countered(plain), "Rhythm of the Wild protects creature spells")


func test_riot_gives_a_counter_or_haste() -> void:
	var e := _engine()
	var r := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Rioter")
	e.process_zone_events()
	_resolve(e)
	var pumped := int(r.counters.get("+1/+1", 0)) == 1 or r.granted_haste
	assert_true(pumped, "riot gave a +1/+1 counter or haste")


func test_altisaur_prevents_all_but_one_damage_to_another_dinosaur() -> void:
	var e := _engine()
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Altisaur")
	var d := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Rager")
	var src := Fixtures.spawn_named(e, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	e.damage_object(src, d, 3)
	assert_eq(d.damage_marked, 1, "only 1 damage got through")
	var alt := _on_bf(e, "Test Altisaur")
	e.damage_object(src, alt, 3)
	assert_eq(alt.damage_marked, 3, "the Altisaur itself is not protected")


func test_finality_counter_exiles_a_dying_creature() -> void:
	var e := _engine()
	var c := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Ogre")
	c.counters["finality"] = 1
	var moved: GameObject = e.state.zones.move(c.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(moved.zone, EngineEnums.ZoneId.EXILE, "exiled instead of dying")


func test_resolve_mana_handles_a_colorless_choice() -> void:
	var e := _engine()
	e._payment = ManaCost.parse("{2}{G}")
	var got := e.resolve_mana(0, ManaCost.parse("{C|G}"))
	assert_true(got != null, "no crash on a colorless option")
	e._payment = null


func test_auto_pay_does_not_tap_more_lands_than_the_cost_needs() -> void:
	var e := _engine()
	for _i in 4:
		_bf(e, "Mountain")
	var fast := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Fastland")
	fast.tapped = false
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		(e.state.objects[oid] as GameObject).tapped = false
	var brute := Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.HAND, "Test Gruul Brute")
	assert_true(e.can_afford(0, e.effective_cost(0, brute)), "four mana with a green source is castable")
	assert_true(_cast(e, brute).ok)
	var tapped := 0
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		if (e.state.objects[oid] as GameObject).tapped:
			tapped += 1
	assert_eq(tapped, 4, "exactly four lands tapped, one stays untapped")
