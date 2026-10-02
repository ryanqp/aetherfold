@tool
extends McpTestSuite

## Comprehensive Rules keywords (CR 701/702) the precons don't print, played with small made-up cards.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_cr_keywords"


func _row(name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "", extra: Dictionary = {}) -> Dictionary:
	var r := {name = name, oracle_id = name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}
	for k in extra.keys():
		r[k] = extra[k]
	return r


func suite_setup(_ctx: Dictionary) -> void:
	var cat: CatalogSource = Fixtures.memory_catalog()
	var m := cat as CatalogSource.Memory
	m.add(_row("Test Evoker", "{3}{U}", 4, "Creature — Elemental", "When this creature enters, draw a card.\nEvoke {U}", "3", "3", {keywords = ["Evoke"]}))
	m.add(_row("Test Blitzer", "{2}{R}", 3, "Creature — Goblin", "Blitz {R}", "2", "2", {keywords = ["Blitz"]}))
	m.add(_row("Test Entwiner", "{1}{G}", 2, "Sorcery", "Choose one —\n• You gain 3 life.\n• Draw a card.\nEntwine {2}", "", "", {keywords = ["Entwine"]}))
	m.add(_row("Test Leveler", "{W}", 1, "Creature — Human Knight", "Level up {1}\nLEVEL 2-3\n3/3\nFlying\nLEVEL 4+\n5/5\nFlying, lifelink", "1", "1", {keywords = ["Level Up"]}))
	m.add(_row("Test Unearther", "{1}{B}", 2, "Creature — Zombie", "Unearth {B}", "2", "1", {keywords = ["Unearth"]}))
	m.add(_row("Test Plotter", "{3}{R}", 4, "Sorcery", "Test Plotter deals 3 damage to any target.\nPlot {1}{R}", "", "", {keywords = ["Plot"]}))
	m.add(_row("Test Boaster", "{1}{R}", 2, "Creature — Dwarf Berserker", "Boast — {1}: You gain 2 life.", "2", "2", {keywords = ["Boast"]}))
	m.add(_row("Test Mutator", "{2}{G}", 3, "Creature — Beast", "Mutate {1}{G}\nTrample", "4", "4", {keywords = ["Mutate", "Trample"]}))
	m.add(_row("Test Awakener", "{1}{G}", 2, "Sorcery", "You gain 1 life.\nAwaken 3—{3}{G}", "", "", {keywords = ["Awaken"]}))
	m.add(_row("Test Daybound", "{1}{G}", 2, "Creature — Human Werewolf", "Daybound", "2", "2", {keywords = ["Daybound"], layout = "transform",
		faces = [{name = "Test Daybound", mana_cost = "{1}{G}", type_line = "Creature — Human Werewolf", oracle_text = "Daybound", power = "2", toughness = "2"},
			{name = "Test Nightbound", mana_cost = "", type_line = "Creature — Werewolf", oracle_text = "Nightbound", power = "4", toughness = "4"}]}))
	m.add(_row("Test Racer", "{1}{R}", 2, "Creature — Lizard", "Start your engines!", "2", "2", {keywords = ["Start your engines!"]}))
	m.add(_row("Test Channeler", "{3}{G}", 4, "Creature — Spirit", "Channel — {1}{G}, Discard this card: You gain 4 life.", "4", "4", {keywords = ["Channel"]}))
	m.add(_row("Test Venturer", "{1}{W}", 2, "Sorcery", "Venture into the dungeon.", "", ""))
	m.add(_row("Test Overloader", "{1}{U}", 2, "Instant", "Return target creature you don't control to its owner's hand.\nOverload {3}{U}", "", "", {keywords = ["Overload"]}))
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Outlaster", "{W}", 1, "Creature — Human", "Outlast {1}", "1", "1", {keywords = ["Outlast"]}))
	m.add(_row("Test Dredger", "{1}{G}", 2, "Creature — Test", "Dredge 2", "2", "2", {keywords = ["Dredge"]}))
	m.add(_row("Test Transfigurer", "{2}", 2, "Creature — Test", "Transfigure {1}{B}", "1", "1", {keywords = ["Transfigure"]}))
	m.add(_row("Test Twin", "{1}{B}", 2, "Creature — Test", "", "2", "2"))
	m.add(_row("Test Swapper Aura", "{1}{U}", 2, "Enchantment — Aura", "Enchant creature\nAura swap {2}{U}", "", "", {keywords = ["Aura swap"]}))
	m.add(_row("Test Plain Aura", "{U}", 1, "Enchantment — Aura", "Enchant creature", "", ""))
	m.add(_row("Test Waterbender", "{2}", 2, "Creature — Test", "Waterbend {2}: You gain 1 life.", "1", "3", {keywords = ["Waterbend"]}))
	m.add(_row("Test Recoverer", "{2}{B}", 3, "Creature — Test", "Recover {B}", "2", "2", {keywords = ["Recover"]}))
	m.add(_row("Test Storied", "{2}", 2, "Legendary Creature — Test", "Storied", "2", "2", {keywords = ["Storied"]}))
	m.add(_row("Test Rock", "{1}", 1, "Artifact", "", "", ""))
	db = CardDatabase.new()
	db.setup(cat)


# --- helpers ----------------------------------------------------------------------------------

func _engine() -> RulesEngine:
	var e := Fixtures.empty_engine_1v1()
	for pid in 2:
		for _i in 12:
			Fixtures.spawn_named(e, db, pid, EngineEnums.ZoneId.LIBRARY, "Mountain")
	return e


func _mana(e: RulesEngine, text: String, pid: int = 0) -> void:
	e.mana.add(pid, ManaCost.parse(text))


func _card(e: RulesEngine, name: String, zone: int, pid: int = 0) -> GameObject:
	var o := Fixtures.spawn_named(e, db, pid, zone, name)
	if zone == EngineEnums.ZoneId.BATTLEFIELD:
		o.summoned_this_turn = false
	return o


func _cast(e: RulesEngine, obj: GameObject, extra: Dictionary = {}) -> SubmitResult:
	var a := GameAction.new()
	a.kind = GameAction.Kind.CAST_SPELL
	a.player_id = obj.controller_id
	a.object_id = obj.object_id
	a.extra = {"auto_pay": true}
	for k in extra.keys():
		a.extra[k] = extra[k]
	var r := e.submit(a)
	var guard := 0
	while r.ok and e.state.mode == EngineEnums.EngineMode.CASTING and guard < 4:
		guard += 1
		var picks: Array = []
		for la in e.legal_actions(a.player_id):
			if (la as GameAction).kind == GameAction.Kind.CHOOSE_TARGETS:
				picks.append(la)
		if picks.is_empty():
			break
		var chosen: GameAction = picks[0]
		var want: int = int(extra.get("target", -1))
		for pk in picks:
			if want >= 0 and int((pk as GameAction).targets[0]) == want:
				chosen = pk
		chosen.extra = a.extra.duplicate()
		r = e.submit(chosen)
	if r.ok and e.state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		var c := GameAction.new()
		c.kind = GameAction.Kind.CANCEL_CAST
		c.player_id = a.player_id
		e.submit(c)
		r = SubmitResult.new()
		r.ok = false
		r.error = "not payable"
	return r


## Resolves the stack; decisions for interactive seats are answered with `answers` (link -> value) or the first option.
func _resolve(e: RulesEngine, answers: Dictionary = {}) -> void:
	var guard := 0
	while guard < 60:
		guard += 1
		e.process_zone_events()
		if e.state.mode == EngineEnums.EngineMode.AWAITING_DECISION and e.state.pending_decision is PlayerDecision:
			var dec := e.state.pending_decision as PlayerDecision
			var a := GameAction.new()
			a.player_id = dec.player_id
			if answers.has(dec.link):
				var v: Variant = answers[dec.link]
				if v is bool and dec.kind == &"OPTIONAL_YES_NO":
					a.kind = GameAction.Kind.SUBMIT_DECISION if v else GameAction.Kind.DECLINE_DECISION
				elif v == null:
					a.kind = GameAction.Kind.DECLINE_DECISION
				else:
					a.kind = GameAction.Kind.SUBMIT_DECISION
					a.extra = {choice = v}
			elif dec.kind == &"OPTIONAL_YES_NO":
				a.kind = GameAction.Kind.SUBMIT_DECISION
			else:
				a.kind = GameAction.Kind.SUBMIT_DECISION
				a.extra = {choice = dec.candidates[0]}
			e.submit(a)
			continue
		if (e.state.stack as MagicStack).is_empty():
			break
		e.finish_top_resolution()
	e.process_zone_events()


func _activate(e: RulesEngine, obj: GameObject, text_start: String) -> SubmitResult:
	for ab in e._active_abilities(obj):
		var a := ab as Ability
		if a != null and a.is_activated() and a.text.begins_with(text_start):
			var act := Fixtures.activate_ability(obj.controller_id, obj.object_id, a.ability_id)
			act.extra = {"auto_pay": true}
			var r := e.submit(act)
			var guard := 0
			while r.ok and e.state.mode == EngineEnums.EngineMode.CASTING and guard < 4:
				guard += 1
				var picks: Array = []
				for la in e.legal_actions(obj.controller_id):
					if (la as GameAction).kind == GameAction.Kind.CHOOSE_TARGETS:
						picks.append(la)
				if picks.is_empty():
					break
				(picks[0] as GameAction).extra = {"auto_pay": true}
				r = e.submit(picks[0])
			return r
	var bad := SubmitResult.new()
	bad.ok = false
	bad.error = "no ability starting %s" % text_start
	return bad


func _on_bf(e: RulesEngine, name: String, pid: int = -1) -> GameObject:
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = e.state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).name == name and (pid < 0 or o.controller_id == pid):
			return o
	return null


func _count_bf(e: RulesEngine, name: String, pid: int = -1) -> int:
	var n := 0
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = e.state.objects.get(oid)
		if o != null and o.definition is CardDefinition and (o.definition as CardDefinition).name == name and (pid < 0 or o.controller_id == pid):
			n += 1
	return n


func _special(e: RulesEngine, obj: GameObject, special: String) -> SubmitResult:
	for act in e.kw.special_actions(obj.controller_id):
		var ga := act as GameAction
		if ga.object_id == obj.object_id and str(ga.extra.get("special", "")) == special:
			return e.submit(ga)
	var bad := SubmitResult.new()
	bad.ok = false
	bad.error = "no such special action"
	return bad


func _attack(e: RulesEngine, ids: Array) -> void:
	e.state.step = EngineEnums.Step.DECLARE_ATTACKERS
	e.state.phase = EngineEnums.Phase.COMBAT
	var a := GameAction.new()
	a.kind = GameAction.Kind.DECLARE_ATTACKERS
	a.player_id = 0
	a.extra = {attackers = ids}
	assert_true(e.submit(a).ok, "attack declared")
	e.process_zone_events()


func _hand_size(e: RulesEngine, pid: int = 0) -> int:
	return e.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid).size()


func _end_step(e: RulesEngine, pid: int = 0) -> void:
	e.kw.on_step_begin(EngineEnums.Step.END, pid)
	_resolve(e)


# --- tests ------------------------------------------------------------------------------------

func test_evoke_is_sacrificed_after_its_enters_trigger() -> void:
	var e := _engine()
	_mana(e, "{U}")
	var c := _card(e, "Test Evoker", EngineEnums.ZoneId.HAND)
	var before := _hand_size(e)
	assert_true(_cast(e, c, {"mode": "evoke"}).ok, "evoked for {U}")
	_resolve(e)
	assert_eq(_count_bf(e, "Test Evoker"), 0, "sacrificed")
	assert_eq(_hand_size(e), before, "drew a card for the one cast")


func test_blitz_has_haste_then_is_sacrificed_and_draws() -> void:
	var e := _engine()
	_mana(e, "{R}")
	var c := _card(e, "Test Blitzer", EngineEnums.ZoneId.HAND)
	assert_true(_cast(e, c, {"mode": "blitz"}).ok, "blitzed")
	_resolve(e)
	var b := _on_bf(e, "Test Blitzer")
	assert_true(b != null and b.granted_haste, "haste")
	var hand := _hand_size(e)
	_end_step(e)
	assert_eq(_count_bf(e, "Test Blitzer"), 0, "sacrificed at end step")
	assert_eq(_hand_size(e), hand + 1, "drew a card")


func test_entwine_does_every_mode() -> void:
	var e := _engine()
	_mana(e, "{1}{G}{2}")
	var c := _card(e, "Test Entwiner", EngineEnums.ZoneId.HAND)
	var life := e.state.players[0].life
	var hand := _hand_size(e)
	assert_true(_cast(e, c, {"entwine": true}).ok, "entwined")
	_resolve(e)
	assert_eq(e.state.players[0].life, life + 3, "gained 3")
	assert_eq(_hand_size(e), hand, "and drew (the cast card left the hand)")


func test_level_up_bands_set_power_and_flying() -> void:
	var e := _engine()
	var c := _card(e, "Test Leveler", EngineEnums.ZoneId.BATTLEFIELD)
	_mana(e, "{2}")
	assert_true(_special(e, c, "level_up").ok, "level 1")
	assert_true(_special(e, c, "level_up").ok, "level 2")
	assert_eq(e.power_of(c), 3, "level 2 band is 3/3")
	assert_true(e.has_keyword(c, "Flying"), "and flies")


func test_unearth_returns_with_haste_and_is_exiled_at_end() -> void:
	var e := _engine()
	_mana(e, "{B}")
	var c := _card(e, "Test Unearther", EngineEnums.ZoneId.GRAVEYARD)
	assert_true(_special(e, c, "unearth").ok, "unearthed")
	var u := _on_bf(e, "Test Unearther")
	assert_true(u != null and u.granted_haste, "back with haste")
	_end_step(e)
	assert_eq(_count_bf(e, "Test Unearther"), 0, "exiled at end step")
	assert_eq(e.state.zones.get_zone(EngineEnums.ZoneId.EXILE).size(), 1, "in exile")


func test_plot_then_cast_free_on_a_later_turn() -> void:
	var e := _engine()
	_mana(e, "{1}{R}")
	var c := _card(e, "Test Plotter", EngineEnums.ZoneId.HAND)
	assert_true(_special(e, c, "plot").ok, "plotted")
	var ex: GameObject = null
	for oid in e.state.zones.get_zone(EngineEnums.ZoneId.EXILE).object_ids:
		ex = e.state.objects[oid]
	assert_true(ex != null and ex.exile_cast == "plot", "plotted in exile")
	assert_false(_cast(e, ex, {"mode": "plotted"}).ok, "not the same turn")
	e.state.turn_number += 1
	var opp := e.state.players[1].life
	assert_true(_cast(e, ex, {"mode": "plotted", "target": TargetingManager.PLAYER_ID_BASE + 1}).ok, "cast free a later turn")
	_resolve(e)
	assert_eq(e.state.players[1].life, opp - 3, "it resolved")


func test_boast_only_after_attacking_and_once() -> void:
	var e := _engine()
	var c := _card(e, "Test Boaster", EngineEnums.ZoneId.BATTLEFIELD)
	_mana(e, "{2}")
	assert_false(_activate(e, c, "{1}").ok, "can't boast before attacking")
	c.attacked_turn = e.state.turn_number
	assert_true(_activate(e, c, "{1}").ok, "boast after attacking")
	_resolve(e)
	assert_false(_activate(e, c, "{1}").ok, "once per turn")


func test_mutate_merges_onto_a_non_human() -> void:
	var e := _engine()
	var bear := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	_mana(e, "{1}{G}")
	var m := _card(e, "Test Mutator", EngineEnums.ZoneId.HAND)
	assert_true(_cast(e, m, {"mode": "mutate"}).ok, "cast for mutate")
	_resolve(e)
	assert_eq(_count_bf(e, "Test Mutator"), 1, "one merged creature named for the top card")
	var top := _on_bf(e, "Test Mutator")
	assert_eq(top.object_id, bear.object_id, "the same permanent as the bear")
	assert_eq(top.merged.size(), 1, "the bear is under it")
	assert_false(top.summoned_this_turn, "not summoning sick")


func test_awaken_makes_a_land_a_creature() -> void:
	var e := _engine()
	var land := _card(e, "Mountain", EngineEnums.ZoneId.BATTLEFIELD)
	_mana(e, "{3}{G}")
	var c := _card(e, "Test Awakener", EngineEnums.ZoneId.HAND)
	assert_true(_cast(e, c, {"mode": "awaken"}).ok, "awakened")
	_resolve(e)
	assert_true(e.is_creature_now(land), "the land is a creature")
	assert_eq(e.power_of(land), 3, "with three +1/+1 counters")


func test_day_night_transforms_daybound() -> void:
	var e := _engine()
	var w := _card(e, "Test Daybound", EngineEnums.ZoneId.BATTLEFIELD)
	e.sba.check(e)
	assert_eq(e.state.day_night, "day", "it becomes day")
	e.state.players[e.state.active_player_id].spells_this_turn = []
	e.state.active_player_id = 1
	e.kw.on_new_turn()
	assert_eq(e.state.day_night, "night", "no spells last turn: night")
	assert_eq(e.power_of(w), 4, "transformed to the nightbound face")


func test_start_your_engines_speed_goes_up_once_a_turn() -> void:
	var e := _engine()
	_card(e, "Test Racer", EngineEnums.ZoneId.BATTLEFIELD)
	e.sba.check(e)
	assert_eq(e.state.players[0].speed, 1, "speed 1")
	e.state.players[1].life_lost_this_turn = 2
	e.sba.check(e)
	e.sba.check(e)
	assert_eq(e.state.players[0].speed, 2, "one increase this turn")


func test_channel_from_hand() -> void:
	var e := _engine()
	_mana(e, "{1}{G}")
	var c := _card(e, "Test Channeler", EngineEnums.ZoneId.HAND)
	var life := e.state.players[0].life
	assert_true(_special(e, c, "hand_ability").ok, "channelled")
	_resolve(e)
	assert_eq(e.state.players[0].life, life + 4, "gained 4")
	assert_eq(e.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0).size(), 1, "discarded")


func test_venture_sentence_is_read() -> void:
	var d := db.definition_for("Test Venturer")
	assert_true(d.spell_ability() != null, "read")
	assert_eq(str((d.spell_ability().effects[0] as AbilityEffect).kind), "VENTURE", "venture effect")


func test_overload_affects_each_creature() -> void:
	var e := _engine()
	_card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD, 1)
	_card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD, 1)
	_mana(e, "{3}{U}")
	var c := _card(e, "Test Overloader", EngineEnums.ZoneId.HAND)
	assert_true(_cast(e, c, {"mode": "overload"}).ok, "overloaded")
	_resolve(e)
	assert_eq(_count_bf(e, "Test Bear", 1), 0, "both bears bounced")


func test_outlast_taps_for_a_counter() -> void:
	var e := _engine()
	var c := _card(e, "Test Outlaster", EngineEnums.ZoneId.BATTLEFIELD)
	_mana(e, "{1}")
	assert_true(_special(e, c, "outlast").ok, "outlast")
	assert_true(c.tapped, "tapped")
	assert_eq(int(c.counters.get("+1/+1", 0)), 1, "counter")


# --- dredge, recover, aura swap, transfigure, waterbend, storied (CR 20260925 audit) ------------------------

func test_dredge_mills_and_returns_the_card() -> void:
	var e := _engine()
	var d := _card(e, "Test Dredger", EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(e.kw.dredge_cards(0).size(), 1, "dredge 2 with a full library")
	var lib := e.library_size(0)
	assert_true(e.kw.do_dredge(0, d.object_id))
	assert_eq(e.library_size(0), lib - 2, "milled 2")
	assert_eq(e.hand_size(0), 1, "the dredge card is in hand")


func test_dredge_needs_enough_cards_in_library() -> void:
	var e := Fixtures.empty_engine_1v1()
	_card(e, "Test Dredger", EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(e.kw.dredge_cards(0).size(), 0, "empty library can't dredge 2")


func test_dredge_is_offered_instead_of_a_draw() -> void:
	var e := _engine()
	e.interactive_seats = [0]
	var d := _card(e, "Test Dredger", EngineEnums.ZoneId.GRAVEYARD)
	var fx := AbilityEffect.new()
	fx.kind = &"DRAW"
	fx.params = {"n": 1, "who": "CONTROLLER"}
	e.put_synthetic(null, 0, [fx], {})
	e.finish_top_resolution()
	assert_eq(e.state.mode, EngineEnums.EngineMode.AWAITING_DECISION, "asked before drawing")
	var dec := e.state.pending_decision as PlayerDecision
	assert_true(dec.optional, "may decline")
	assert_eq(dec.candidates.size(), 1)
	var lib := e.library_size(0)
	_resolve(e, {dec.link: dec.candidates[0]})
	assert_eq(e.library_size(0), lib - 2, "dredged, not drawn")
	assert_eq(e.hand_size(0), 1)
	assert_true(d != null)


func test_declining_dredge_draws_normally() -> void:
	var e := _engine()
	e.interactive_seats = [0]
	_card(e, "Test Dredger", EngineEnums.ZoneId.GRAVEYARD)
	var fx := AbilityEffect.new()
	fx.kind = &"DRAW"
	fx.params = {"n": 1, "who": "CONTROLLER"}
	e.put_synthetic(null, 0, [fx], {})
	e.finish_top_resolution()
	var dec := e.state.pending_decision as PlayerDecision
	var lib := e.library_size(0)
	_resolve(e, {dec.link: null})
	assert_eq(e.library_size(0), lib - 1, "drew one card")
	assert_eq(e.hand_size(0), 1)


func test_transfigure_sacrifices_and_finds_same_mana_value() -> void:
	var e := _engine()
	var t := _card(e, "Test Transfigurer", EngineEnums.ZoneId.BATTLEFIELD)
	Fixtures.spawn_named(e, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Twin")
	_mana(e, "{1}{B}")
	assert_true(_special(e, t, "transfigure").ok, "transfigure")
	_resolve(e)
	assert_eq(_count_bf(e, "Test Transfigurer"), 0, "sacrificed")
	assert_eq(_count_bf(e, "Test Twin"), 1, "found the mana value 2 creature")


func test_aura_swap_exchanges_with_an_aura_in_hand() -> void:
	var e := _engine()
	var host := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	var aura := _card(e, "Test Swapper Aura", EngineEnums.ZoneId.BATTLEFIELD)
	aura.attached_to = host.object_id
	_card(e, "Test Plain Aura", EngineEnums.ZoneId.HAND)
	_mana(e, "{2}{U}")
	assert_true(_special(e, aura, "aura_swap").ok, "aura swap")
	_resolve(e)
	var now := _on_bf(e, "Test Plain Aura")
	assert_true(now != null, "the Aura from hand is on the battlefield")
	assert_eq(now.attached_to, host.object_id, "enchanting the same creature")
	assert_eq(_count_bf(e, "Test Swapper Aura"), 0, "the first Aura returned to hand")


func test_aura_swap_needs_an_aura_in_hand() -> void:
	var e := _engine()
	var host := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	var aura := _card(e, "Test Swapper Aura", EngineEnums.ZoneId.BATTLEFIELD)
	aura.attached_to = host.object_id
	_mana(e, "{2}{U}")
	assert_false(_special(e, aura, "aura_swap").ok, "no Aura in hand")


func test_recover_returns_the_card_when_a_creature_dies_and_it_is_paid() -> void:
	var e := _engine()
	var r := _card(e, "Test Recoverer", EngineEnums.ZoneId.GRAVEYARD)
	var bear := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	_mana(e, "{B}")
	e.state.zones.move(bear.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	_resolve(e)
	assert_eq(e.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).size(), 1, "recovered to hand")
	assert_true(r != null)


func test_recover_exiles_the_card_when_not_paid() -> void:
	var e := _engine()
	_card(e, "Test Recoverer", EngineEnums.ZoneId.GRAVEYARD)
	var bear := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	e.state.zones.move(bear.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	_resolve(e)
	assert_eq(e.state.zones.get_zone(EngineEnums.ZoneId.EXILE).size(), 1, "exiled")


func test_waterbend_taps_creatures_for_generic_mana() -> void:
	var e := _engine()
	var w := _card(e, "Test Waterbender", EngineEnums.ZoneId.BATTLEFIELD)
	var b1 := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	var b2 := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	var ab: Ability = null
	for a in (w.definition as CardDefinition).abilities:
		if (a as Ability).is_activated():
			ab = a
	assert_true(ab != null, "the waterbend ability was read")
	assert_eq(e.costs.waterbend_amount(ab), 2)
	var left := e.kw.cover_waterbend(0, w, e.costs.mana_cost(ab), 2)
	assert_true(left.is_zero(), "both generic paid by tapping")
	assert_true(b1.tapped and b2.tapped, "creatures tapped")
	assert_false(w.tapped, "the source isn't tapped for its own cost")


func test_waterbend_taps_nothing_if_it_can_not_cover_the_cost() -> void:
	var e := _engine()
	var w := _card(e, "Test Waterbender", EngineEnums.ZoneId.BATTLEFIELD)
	var b1 := _card(e, "Test Bear", EngineEnums.ZoneId.BATTLEFIELD)
	var ab: Ability = null
	for a in (w.definition as CardDefinition).abilities:
		if (a as Ability).is_activated():
			ab = a
	var left := e.kw.cover_waterbend(0, w, e.costs.mana_cost(ab), 2)
	assert_false(left.is_zero())
	assert_false(b1.tapped, "nothing tapped when the cost can't be met")


func test_storied_gives_an_enduring_story() -> void:
	var e := _engine()
	_card(e, "Test Storied", EngineEnums.ZoneId.BATTLEFIELD)
	e.sba.check(e)
	assert_false(e.state.players[0].enduring_story, "only one qualifying permanent")
	_card(e, "Test Rock", EngineEnums.ZoneId.BATTLEFIELD)
	_card(e, "Test Rock", EngineEnums.ZoneId.BATTLEFIELD)
	e.sba.check(e)
	assert_true(e.state.players[0].enduring_story, "three artifacts / legendaries")
