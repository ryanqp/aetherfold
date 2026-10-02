@tool
extends McpTestSuite

## The keywords and keyword actions of the eight Commander precon starter decks, played with the real cards.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_precon_keywords"


func suite_setup(_ctx: Dictionary) -> void:
	var cat: CatalogSource = Fixtures.memory_catalog()
	for row in PreconDecks.all_rows():
		(cat as CatalogSource.Memory).add(row)
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


# --- coverage of the decks ----------------------------------------------------------------------

func test_every_keyword_in_the_precons_is_known_to_the_engine() -> void:
	var unknown := PackedStringArray()
	for row in PreconDecks.all_rows():
		for k in (row as Dictionary).get("keywords", []):
			var key := str(k).to_lower()
			if key == "treasure" or key == "food" or key == "clue" or key == "transform":
				continue  ## token names and the incubator's transform, handled with their tokens
			var e := KeywordDb.lookup(key)
			if e.is_empty() or str(e.get("status", "")) == "MISSING":
				unknown.append("%s (%s)" % [k, (row as Dictionary).get("name", "")])
	assert_eq(unknown.size(), 0, "unknown keywords: %s" % ", ".join(unknown))


# --- planeswalkers (CR 306, 606) --------------------------------------------------------------------

func test_planeswalker_enters_with_loyalty_and_uses_one_loyalty_ability_a_turn() -> void:
	var e := _engine()
	for _i in 3:
		_card(e, "Mountain", EngineEnums.ZoneId.HAND)
	var jace := _card(e, "Jace, Multiverse Architect", EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(int(jace.counters.get("loyalty", 0)), 4, "starting loyalty")
	var hand_before := e.hand_size(0)
	assert_true(_activate(e, jace, "+1").ok, "+1 activates")
	_resolve(e)
	assert_eq(int(jace.counters.get("loyalty", 0)), 5)
	assert_eq(e.hand_size(0), hand_before + 1, "drew two, put one back")
	assert_false(_activate(e, jace, "+1").ok, "only one loyalty ability each turn")


func test_damage_to_a_planeswalker_removes_loyalty_and_it_dies_at_zero() -> void:
	var e := _engine()
	var els := _card(e, "Elspeth, Sun's Champion", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var src := _card(e, "Mountain", EngineEnums.ZoneId.BATTLEFIELD)
	e.damage_object(src, els, 3)
	assert_eq(int(els.counters.get("loyalty", 0)), 1)
	e.damage_object(src, els, 2)
	e.sba.check(e)
	assert_true(_on_bf(e, "Elspeth, Sun's Champion") == null, "a planeswalker with no loyalty goes to the graveyard")


func test_elspeth_makes_soldiers_and_minus_three_wipes_big_creatures() -> void:
	var e := _engine()
	var els := _card(e, "Elspeth, Sun's Champion", EngineEnums.ZoneId.BATTLEFIELD)
	assert_true(_activate(e, els, "+1").ok)
	_resolve(e)
	assert_eq(_count_bf(e, "Soldier", 0), 3, "three soldiers")
	e.state.turn_number += 1
	_card(e, "Gigantosaurus", EngineEnums.ZoneId.BATTLEFIELD, 1)
	assert_true(_activate(e, els, "−3").ok)
	_resolve(e)
	e.sba.check(e)
	assert_true(_on_bf(e, "Gigantosaurus") == null, "power 4+ destroyed")
	assert_eq(_count_bf(e, "Soldier", 0), 3, "small ones stay")


func test_empower_makes_a_jace_token_and_adds_loyalty() -> void:
	var e := _engine()
	_card(e, "Plan for All Outcomes", EngineEnums.ZoneId.BATTLEFIELD)
	var opt := _card(e, "Fatehold Charm", EngineEnums.ZoneId.HAND)
	_mana(e, "{W}{U}")
	assert_true(_cast(e, opt).ok)
	_resolve(e, {"mode_0": 0})
	var tok := _on_bf(e, "Jace", 0)
	assert_true(tok != null, "a Jace token")
	## Empower 1 from Plan for All Outcomes (first noncreature spell) and empower 2 from the charm's mode.
	assert_eq(int(tok.counters.get("loyalty", 0)), 3)
	assert_true(_activate(e, tok, "−1").ok, "the token's loyalty ability works")


# --- equipment and auras -----------------------------------------------------------------------------

func test_living_weapon_makes_a_germ_wearing_the_equipment() -> void:
	var e := _engine()
	var net := _card(e, "Nettlecyst", EngineEnums.ZoneId.HAND)
	_mana(e, "{3}")
	assert_true(_cast(e, net).ok)
	_resolve(e)
	e.sba.check(e)
	var germ := _on_bf(e, "Phyrexian Germ")
	assert_true(germ != null, "germ token")
	var eq := _on_bf(e, "Nettlecyst")
	assert_eq(eq.attached_to, germ.object_id)
	assert_eq(e.power_of(germ), 1, "+1/+1 for each artifact and/or enchantment you control")


func test_aura_targets_and_attaches_and_changes_the_creature() -> void:
	var e := _engine()
	var bear := _card(e, "Gigantosaurus", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var aura := _card(e, "Kenrith's Transformation", EngineEnums.ZoneId.HAND)
	_mana(e, "{1}{G}")
	assert_true(_cast(e, aura, {"target": bear.object_id}).ok)
	_resolve(e)
	var on := _on_bf(e, "Kenrith's Transformation")
	assert_true(on != null)
	assert_eq(on.attached_to, bear.object_id)
	assert_eq(e.power_of(bear), 3, "base 3/3 Elk")
	assert_true(str(e.layers.snapshot(e.state, bear).type_line).contains("Elk"))
	e.state.zones.move(bear.object_id, EngineEnums.ZoneId.GRAVEYARD, 1)
	e.sba.check(e)
	assert_true(_on_bf(e, "Kenrith's Transformation") == null, "an Aura with nothing to enchant goes to the graveyard")


func test_angelic_destiny_pumps_and_returns_when_the_creature_dies() -> void:
	var e := _engine()
	var guy := _card(e, "Gigantosaurus", EngineEnums.ZoneId.BATTLEFIELD)
	var aura := _card(e, "Angelic Destiny", EngineEnums.ZoneId.HAND)
	_mana(e, "{2}{W}{W}")
	assert_true(_cast(e, aura, {"target": guy.object_id}).ok)
	_resolve(e)
	assert_eq(e.power_of(guy), 14)
	assert_true(e.has_keyword(guy, "Flying"))
	assert_true(e.layers.has_subtype(e.state, guy, "Angel"))
	e.state.zones.move(guy.object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	e.sba.check(e)
	_resolve(e)
	var back := false
	for hid in e.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0).object_ids:
		var h: GameObject = e.state.objects.get(hid)
		if (h.definition as CardDefinition).name == "Angelic Destiny":
			back = true
	assert_true(back, "Angelic Destiny went back to its owner's hand")


# --- combat keywords ------------------------------------------------------------------------------

func test_two_color_protection_stops_targets_blocks_and_damage() -> void:
	var e := _engine()
	var ak := _card(e, "Akroma, Angel of Fury", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var white := _card(e, "Serra Avenger", EngineEnums.ZoneId.BATTLEFIELD)
	assert_true(e.protected_from(ak, white))
	assert_false(e.can_block_as(white.object_id, 0, ak.object_id), "a white creature can't block it")
	e.damage_object(white, ak, 3)
	assert_eq(ak.damage_marked, 0, "damage from a white source is prevented")
	var red := _card(e, "Firespitter Whelp", EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(e.protected_from(ak, red))


func test_dethrone_counts_when_attacking_the_player_with_most_life() -> void:
	var e := _engine()
	var sc := _card(e, "Scourge of the Throne", EngineEnums.ZoneId.BATTLEFIELD)
	e.state.players[1].life = 40
	e.state.players[0].life = 30
	_attack(e, [sc.object_id])
	_resolve(e)
	assert_eq(int(sc.counters.get("+1/+1", 0)), 1)


# --- casting keywords ----------------------------------------------------------------------------

func test_escalate_pays_for_each_extra_mode() -> void:
	var e := _engine()
	var cr := _card(e, "Collective Resistance", EngineEnums.ZoneId.HAND)
	var art := _card(e, "Sol Ring", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var ench := _card(e, "Bad Moon", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var opts := e.kw.cast_options(0, cr)
	var found := false
	for o in opts:
		if int((o as Dictionary).extra.get("escalate", 0)) == 1:
			found = true
	assert_true(found, "a 2-mode cast option")
	_mana(e, "{1}{G}")
	assert_false(_cast(e, cr, {"escalate": 1}).ok, "two modes cost {G} more")
	_mana(e, "{G}")
	assert_true(_cast(e, cr, {"escalate": 1}).ok)
	e.interactive_seats = [0]
	_resolve(e, {"mode_0": 0, "mode_1": 1})
	e.sba.check(e)
	assert_true(_on_bf(e, "Sol Ring") == null and _on_bf(e, "Bad Moon") == null, "both modes happened")
	assert_true(art != null and ench != null)


func test_gift_draws_the_opponent_a_card_and_enables_the_bonus() -> void:
	var e := _engine()
	_card(e, "Sol Ring", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var sh := _card(e, "Scrapshooter", EngineEnums.ZoneId.HAND)
	var opp_hand := e.hand_size(1)
	_mana(e, "{1}{G}{G}")
	assert_true(_cast(e, sh, {"gift": true}).ok)
	_resolve(e)
	e.sba.check(e)
	assert_eq(e.hand_size(1), opp_hand + 1, "the opponent drew their gift")
	assert_true(_on_bf(e, "Sol Ring") == null, "the gift was promised, so the artifact was destroyed")
	var e2 := _engine()
	_card(e2, "Sol Ring", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var sh2 := _card(e2, "Scrapshooter", EngineEnums.ZoneId.HAND)
	_mana(e2, "{1}{G}{G}")
	assert_true(_cast(e2, sh2).ok)
	_resolve(e2)
	assert_true(_on_bf(e2, "Sol Ring") != null, "no gift, no destroy trigger")


func test_impending_enters_as_a_non_creature_with_time_counters() -> void:
	var e := _engine()
	var ov := _card(e, "Overlord of the Mistmoors", EngineEnums.ZoneId.HAND)
	_mana(e, "{2}{W}{W}")
	assert_true(_cast(e, ov, {"mode": "impending"}).ok)
	_resolve(e)
	var on := _on_bf(e, "Overlord of the Mistmoors")
	assert_eq(int(on.counters.get("time", 0)), 4)
	assert_false(e.is_creature_now(on), "not a creature while it has time counters")
	assert_eq(_count_bf(e, "Insect", 0), 2, "its enter trigger still made two Insects")
	e.kw.on_step_begin(EngineEnums.Step.END, 0)
	assert_eq(int(on.counters.get("time", 0)), 3, "a time counter comes off at your end step")


func test_improvise_taps_artifacts_for_generic_mana() -> void:
	var e := _engine()
	for _i in 4:
		_card(e, "Ornithopter of Paradise", EngineEnums.ZoneId.BATTLEFIELD)
	var k := _card(e, "Kappa Cannoneer", EngineEnums.ZoneId.HAND)
	_mana(e, "{1}{U}")
	assert_true(_cast(e, k).ok, "four artifacts pay for {4}")
	_resolve(e)
	assert_true(_on_bf(e, "Kappa Cannoneer") != null)


func test_encore_and_eternalize_make_token_copies_from_the_graveyard() -> void:
	var e := _engine()
	var fan := _card(e, "Fanatic of Rhonas", EngineEnums.ZoneId.GRAVEYARD)
	_mana(e, "{2}{G}{G}")
	assert_true(_special(e, fan, "eternalize").ok)
	var tok := _on_bf(e, "Fanatic of Rhonas")
	assert_true(tok != null and tok.is_token)
	assert_eq(e.power_of(tok), 4)
	assert_true(str(e.layers.snapshot(e.state, tok).type_line).contains("Zombie"))
	var ang := _card(e, "Angel of Indemnity", EngineEnums.ZoneId.GRAVEYARD)
	_mana(e, "{6}{W}{W}")
	assert_true(_special(e, ang, "encore").ok)
	var copy := _on_bf(e, "Angel of Indemnity")
	assert_true(copy != null and copy.granted_haste and copy.sacrifice_at_end)
	e.kw.on_step_begin(EngineEnums.Step.END, 0)
	assert_true(_on_bf(e, "Angel of Indemnity") == null, "sacrificed at the end step")


func test_demonstrate_copies_for_you_and_the_opponent() -> void:
	var e := _engine()
	_card(e, "Sol Ring", EngineEnums.ZoneId.BATTLEFIELD, 1)
	_card(e, "Mind Stone", EngineEnums.ZoneId.BATTLEFIELD, 1)
	_card(e, "Commander's Sphere", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var ex := _card(e, "Excavation Technique", EngineEnums.ZoneId.HAND)
	_mana(e, "{3}{W}")
	assert_true(_cast(e, ex).ok)
	_resolve(e)
	var treasures := _count_bf(e, "Treasure", 1) + _count_bf(e, "Treasure", 0)
	assert_eq(treasures, 6, "three copies destroyed three permanents, two Treasures each")


# --- Sagas ----------------------------------------------------------------------------------------

func test_read_ahead_starts_at_the_chosen_chapter() -> void:
	var e := _engine()
	e.interactive_seats = [0]
	var war := _card(e, "The Elder Dragon War", EngineEnums.ZoneId.HAND)
	_mana(e, "{2}{R}{R}")
	assert_true(_cast(e, war).ok)
	_resolve(e, {"read_ahead": 3})
	e.sba.check(e)
	_resolve(e)
	e.sba.check(e)
	assert_eq(_count_bf(e, "Dragon", 0), 1, "chapter III made a Dragon")
	assert_true(_on_bf(e, "The Elder Dragon War") == null, "sacrificed after its last chapter")


func test_saga_gains_lore_each_precombat_main() -> void:
	var e := _engine()
	var song := _card(e, "The Elder Dragon War", EngineEnums.ZoneId.HAND)
	_mana(e, "{2}{R}{R}")
	assert_true(_cast(e, song).ok)
	_resolve(e)
	var saga := _on_bf(e, "The Elder Dragon War")
	assert_eq(int(saga.counters.get("lore", 0)), 1)
	e.triggers._on_step_begin(e, EngineEnums.Step.PRECOMBAT_MAIN, 0)
	assert_eq(int(saga.counters.get("lore", 0)), 2)


# --- keyword actions -------------------------------------------------------------------------------

func test_behold_a_dragon_makes_a_treasure() -> void:
	var e := _engine()
	_card(e, "Thundermane Dragon", EngineEnums.ZoneId.HAND)
	var sk := _card(e, "Sarkhan, Dragon Ascendant", EngineEnums.ZoneId.HAND)
	_mana(e, "{1}{R}")
	assert_true(_cast(e, sk).ok)
	_resolve(e)
	assert_eq(_count_bf(e, "Treasure", 0), 1)


func test_clash_win_draws() -> void:
	var e := _engine()
	var lib0: Zone = e.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	var big := _card(e, "Gigantosaurus", EngineEnums.ZoneId.LIBRARY)
	lib0.object_ids.erase(big.object_id)
	lib0.object_ids.push_front(big.object_id)
	var marvo := _card(e, "Marvo, Deep Operative", EngineEnums.ZoneId.BATTLEFIELD)
	var hand := e.hand_size(0)
	_attack(e, [marvo.object_id])
	_resolve(e)
	assert_true(e.hand_size(0) >= hand + 1, "won the clash (5 against a land) and drew")


func test_double_doubles_power_and_toughness() -> void:
	var e := _engine()
	_card(e, "Unnatural Growth", EngineEnums.ZoneId.BATTLEFIELD)
	var g := _card(e, "Gigantosaurus", EngineEnums.ZoneId.BATTLEFIELD)
	e.triggers._on_step_begin(e, EngineEnums.Step.BEGIN_COMBAT, 0)
	_resolve(e)
	assert_eq(e.power_of(g), 20)


func test_celebration_makes_goddric_a_dragon() -> void:
	var e := _engine()
	var g := _card(e, "Goddric, Cloaked Reveler", EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(e.power_of(g), 3)
	_card(e, "Sol Ring", EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(e.power_of(g), 4, "two nonland permanents entered this turn (Goddric and Sol Ring)")
	assert_true(e.has_keyword(g, "Flying"))
	var granted := false
	for a in e._active_abilities(g):
		if (a as Ability).text.begins_with("{R}"):
			granted = true
	assert_true(granted, "it has the quoted {R} ability")


func test_corrupted_gives_toxic_creatures_lifelink() -> void:
	var e := _engine()
	_card(e, "Skrelv's Hive", EngineEnums.ZoneId.BATTLEFIELD)
	e.triggers._on_step_begin(e, EngineEnums.Step.UPKEEP, 0)
	_resolve(e)
	var mite := _on_bf(e, "Phyrexian Mite")
	assert_true(mite != null, "the upkeep made a Mite")
	assert_false(e.has_keyword(mite, "Lifelink"))
	e.state.players[1].poison = 3
	assert_true(e.has_keyword(mite, "Lifelink"))
	assert_false(e.can_block_as(mite.object_id, 0, -1) and false)


func test_eminence_works_from_the_command_zone() -> void:
	var e := _engine()
	var ur := _card(e, "The Ur-Sphinx", EngineEnums.ZoneId.COMMAND)
	ur.is_commander = true
	var sph := _card(e, "Enigma Sphinx", EngineEnums.ZoneId.HAND)
	assert_eq(e.cost_reduction(0, sph), 1)


func test_imprint_duplicant_takes_the_exiled_creatures_size() -> void:
	var e := _engine()
	var big := _card(e, "Gigantosaurus", EngineEnums.ZoneId.BATTLEFIELD, 1)
	var dup := _card(e, "Duplicant", EngineEnums.ZoneId.HAND)
	_mana(e, "{6}")
	assert_true(_cast(e, dup).ok)
	_resolve(e)
	var on := _on_bf(e, "Duplicant")
	assert_true(_on_bf(e, "Gigantosaurus") == null, "exiled")
	assert_eq(e.power_of(on), 10)
	assert_true(big != null)


func test_pack_tactics_puts_a_dragon_in_attacking() -> void:
	var e := _engine()
	var minion := _card(e, "Minion of the Mighty", EngineEnums.ZoneId.BATTLEFIELD)
	var g := _card(e, "Gigantosaurus", EngineEnums.ZoneId.BATTLEFIELD)
	_card(e, "Thundermane Dragon", EngineEnums.ZoneId.HAND)
	_attack(e, [minion.object_id, g.object_id])
	_resolve(e)
	var d := _on_bf(e, "Thundermane Dragon")
	assert_true(d != null and d.tapped, "a Dragon came in tapped")
	assert_true((e.state.combat as CombatState).attacker_ids.has(d.object_id), "and attacking")
