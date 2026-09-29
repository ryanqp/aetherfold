@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_activation"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_sick_mana_cost_can_activate() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _piker(engine)
	_give(piker, _mana_draw(&"pay1", "{1}"))
	assert_true(piker.summoned_this_turn)
	assert_true(_can(engine, piker, &"pay1"))
	var row: Dictionary = _report_row(engine, piker, 0)
	assert_false(bool(row.requires_tap))
	assert_true(bool(row.can_activate))
	assert_eq(str(row.reason), "LEGAL")


func test_sick_tap_cost_cannot_activate() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _piker(engine)
	_give(piker, _tap_draw())
	assert_true(piker.summoned_this_turn)
	assert_false(_can(engine, piker, &"tap_draw"))
	var row: Dictionary = _report_row(engine, piker, 0)
	assert_true(bool(row.requires_tap))
	assert_false(bool(row.can_activate))
	assert_eq(str(row.reason), "SUMMONING_SICKNESS")


func test_tapped_mana_cost_can_activate() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _piker(engine)
	piker.summoned_this_turn = false
	piker.tapped = true
	_give(piker, _mana_draw(&"pay1", "{1}"))
	assert_true(_can(engine, piker, &"pay1"))
	var row: Dictionary = _report_row(engine, piker, 0)
	assert_true(bool(row.can_activate))
	assert_eq(str(row.reason), "LEGAL")


func test_tapped_tap_cost_cannot_activate() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _piker(engine)
	piker.summoned_this_turn = false
	piker.tapped = true
	_give(piker, _tap_draw())
	assert_false(_can(engine, piker, &"tap_draw"))
	var row: Dictionary = _report_row(engine, piker, 0)
	assert_false(bool(row.can_activate))
	assert_eq(str(row.reason), "TAPPED")


func test_kellan_enters_with_activated_abilities() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	var report: Dictionary = engine.activation_report(kellan.object_id)
	assert_eq(int(report.abilities.size()), 2)
	assert_eq(str(_report_row(engine, kellan, 0).cost), "{1}{R}")
	assert_eq(str(_report_row(engine, kellan, 1).cost), "{2}{R}")
	assert_eq(str(_report_row(engine, kellan, 0).type), "ACTIVATED")
	assert_false(_has_ability(engine, kellan, "kellan_impulse"))
	var text := str(report.text)
	assert_true(text.contains("Source:\nKellan, Planar Trailblazer"))
	assert_true(text.contains("Abilities Found:\n2"))
	assert_true(text.find("Kellan is a Scout") < text.find("Kellan is a Detective"))


func test_kellan_sick_nontap_still_legal() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	assert_true(kellan.summoned_this_turn)
	assert_false(kellan.tapped)
	var first: Dictionary = _report_row(engine, kellan, 0)
	assert_false(bool(first.requires_tap))
	assert_false(bool(first.mana_available))
	assert_true(bool(first.can_activate))
	assert_eq(str(first.reason), "LEGAL")
	assert_eq(str(first.condition), "Kellan is a Scout")
	assert_true(bool(first.condition_result))
	assert_true(_can(engine, kellan, &"kellan_scout"))
	assert_true(_can(engine, kellan, &"kellan_detective"))
	var session := _session()
	var live: GameObject = Fixtures.spawn_named(session.engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Kellan, Planar Trailblazer")
	var blocked: SubmitResult = session.activate_auto(live.object_id)
	assert_false(blocked.ok)
	assert_eq(blocked.error, "Choose an ability.")
	assert_false(blocked.error.contains("Nothing to activate"))


func test_kellan_activation_pays_mana() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	engine.mana.add(0, ManaCost.parse("{2}{R}"))
	var announced: SubmitResult = engine.submit(Fixtures.activate_ability(0, kellan.object_id, &"kellan_scout"))
	assert_true(announced.ok, announced.error)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.PAYING_COSTS)
	assert_eq((engine.state.stack as MagicStack).size(), 0)
	assert_eq(engine.mana.pool(0).r, 1)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
	assert_eq(engine.mana.pool(0).r, 0)
	assert_eq(engine.mana.pool(0).colorless, 1)
	assert_eq((engine.state.stack as MagicStack).size(), 0)
	assert_eq(kellan.zone, EngineEnums.ZoneId.BATTLEFIELD)


func test_activated_ability_goes_on_stack() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	_pay_and_confirm(engine, kellan, &"kellan_scout", "{1}{R}")
	var stack := engine.state.stack as MagicStack
	assert_eq(stack.size(), 1)
	var entry: StackEntry = stack.top()
	assert_eq(entry.kind, StackEntry.Kind.ACTIVATED)
	assert_eq(entry.object_id, 0)
	assert_eq(entry.source_id, kellan.object_id)
	assert_eq(str(entry.ability_id), "kellan_scout")
	assert_eq(kellan.zone, EngineEnums.ZoneId.BATTLEFIELD)
	assert_true(engine.layers.has_subtype(engine.state, kellan, "Scout"))


func test_activated_ability_resolves() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	_pay_and_confirm(engine, kellan, &"kellan_scout", "{1}{R}")
	Fixtures.both_pass(engine)
	assert_eq((engine.state.stack as MagicStack).size(), 0)
	assert_eq(kellan.zone, EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.GIVING_PRIORITY)


func test_kellan_characteristics_change() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	_resolve_paid(engine, kellan, &"kellan_scout", "{1}{R}")
	var snap: Dictionary = engine.layers.snapshot(engine.state, kellan)
	var subs: PackedStringArray = snap.subtypes
	assert_true(subs.has("Human"))
	assert_true(subs.has("Faerie"))
	assert_true(subs.has("Detective"))
	assert_false(subs.has("Scout"))
	assert_eq(int(snap.power), 2)
	assert_eq(int(snap.toughness), 1)
	assert_eq(int(snap.printed_power), 2)
	assert_eq(int(snap.printed_toughness), 1)
	assert_eq((kellan.definition as CardDefinition).power, "2")
	engine.layers.clear_until_eot(engine.state)
	assert_true(engine.layers.has_subtype(engine.state, kellan, "Detective"))


func test_kellan_gains_triggered_ability() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	assert_false(_has_ability(engine, kellan, "kellan_impulse"))
	_resolve_paid(engine, kellan, &"kellan_scout", "{1}{R}")
	assert_true(_has_ability(engine, kellan, "kellan_impulse"))


func test_combat_damage_trigger_exiles_top() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	_resolve_paid(engine, kellan, &"kellan_scout", "{1}{R}")
	var pump := ContinuousEffect.new()
	pump.object_ids = [kellan.object_id]
	pump.power = -2
	engine.state.effects.append(pump)
	_unblocked(engine, kellan)
	assert_eq((engine.state.stack as MagicStack).size(), 0)
	engine.state.effects.erase(pump)
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Shock")
	var life_before: int = engine.state.players[1].life
	_unblocked(engine, kellan)
	assert_true(engine.state.players[1].life < life_before)
	assert_eq((engine.state.stack as MagicStack).size(), 1)
	assert_eq((engine.state.stack as MagicStack).top().kind, StackEntry.Kind.TRIGGERED)
	Fixtures.both_pass(engine)
	var exiled: GameObject = _find_named(engine, EngineEnums.ZoneId.EXILE, 0, "Shock")
	assert_true(exiled != null)
	assert_eq(exiled.may_play_controller, 0)
	assert_true(_action_for(engine, GameAction.Kind.CAST_SPELL, exiled.object_id))
	assert_eq(exiled.zone, EngineEnums.ZoneId.EXILE)
	engine.turn._clear_may_play(engine.state)
	assert_eq(exiled.may_play_controller, -1)
	assert_false(_action_for(engine, GameAction.Kind.CAST_SPELL, exiled.object_id))


func test_trigger_opens_player_decision() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _may_draw_creature(engine)
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Mountain")
	_unblocked(engine, piker)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.AWAITING_DECISION)
	var dec: PlayerDecision = engine.state.pending_decision as PlayerDecision
	assert_true(dec != null)
	assert_eq(str(dec.kind), "OPTIONAL_YES_NO")
	assert_eq(dec.player_id, 0)
	assert_eq(engine.hand_size(0), 0)


func test_decision_pauses_resolution() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _may_draw_creature(engine)
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Mountain")
	_unblocked(engine, piker)
	Fixtures.both_pass(engine)
	assert_eq((engine.state.stack as MagicStack).size(), 1)
	assert_eq(engine.library_size(0), 1)
	assert_eq(engine.hand_size(0), 0)
	assert_true((engine.state.stack as MagicStack).top().choices.is_empty())


func test_decision_resumes_resolution() -> void:
	var declined := Fixtures.empty_engine_1v1()
	var piker := _may_draw_creature(declined)
	Fixtures.spawn_named(declined, db, 0, EngineEnums.ZoneId.LIBRARY, "Mountain")
	_unblocked(declined, piker)
	Fixtures.both_pass(declined)
	var no := GameAction.new()
	no.kind = GameAction.Kind.DECLINE_DECISION
	no.player_id = 0
	assert_true(declined.submit(no).ok)
	assert_eq(declined.hand_size(0), 0)
	assert_eq(declined.library_size(0), 1)
	assert_eq((declined.state.stack as MagicStack).size(), 0)
	assert_eq(declined.state.mode, EngineEnums.EngineMode.GIVING_PRIORITY)

	var accepted := Fixtures.empty_engine_1v1()
	var attacker := _may_draw_creature(accepted)
	Fixtures.spawn_named(accepted, db, 0, EngineEnums.ZoneId.LIBRARY, "Mountain")
	_unblocked(accepted, attacker)
	Fixtures.both_pass(accepted)
	var yes := GameAction.new()
	yes.kind = GameAction.Kind.SUBMIT_DECISION
	yes.player_id = 0
	assert_true(accepted.submit(yes).ok)
	assert_eq(accepted.hand_size(0), 1)
	assert_eq(accepted.library_size(0), 0)
	assert_eq((accepted.state.stack as MagicStack).size(), 0)


func test_detective_check_is_on_resolution() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	assert_true(_can(engine, kellan, &"kellan_detective"))
	_resolve_paid(engine, kellan, &"kellan_detective", "{2}{R}")
	assert_true(engine.layers.has_subtype(engine.state, kellan, "Scout"))
	assert_eq(int(engine.layers.snapshot(engine.state, kellan).power), 2)


func test_later_type_keeps_gained_trigger_and_counters() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var kellan := _kellan(engine)
	engine.mana.add(0, ManaCost.parse("{4}{R}{R}{R}"))
	_resolve_paid(engine, kellan, &"kellan_scout", "")
	_resolve_paid(engine, kellan, &"kellan_detective", "")
	assert_true(engine.layers.has_subtype(engine.state, kellan, "Rogue"))
	assert_false(engine.layers.has_subtype(engine.state, kellan, "Detective"))
	assert_true(engine.layers.has_keyword(engine.state, kellan, "Double strike"))
	assert_true(_has_ability(engine, kellan, "kellan_impulse"))
	assert_eq(int(engine.layers.snapshot(engine.state, kellan).power), 3)
	_resolve_paid(engine, kellan, &"kellan_scout", "")
	assert_true(engine.layers.has_subtype(engine.state, kellan, "Rogue"))
	assert_true(_has_ability(engine, kellan, "kellan_impulse"))
	kellan.counters["+1/+1"] = 1
	var snap: Dictionary = engine.layers.snapshot(engine.state, kellan)
	assert_eq(int(snap.power), 4)
	assert_eq(int(snap.toughness), 3)
	assert_eq(int(snap.printed_power), 2)
	assert_eq((kellan.definition as CardDefinition).power, "2")


func test_haste_lets_a_new_creature_tap_and_attack() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _piker(engine)
	(piker.definition as CardDefinition).keywords = PackedStringArray(["Haste"])
	_give(piker, _tap_draw())
	assert_true(piker.summoned_this_turn)
	assert_true(_can(engine, piker, &"tap_draw"))
	assert_true(engine.legal_attacker_ids(0).has(piker.object_id))


func test_choose_waits_for_the_selected_option() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker := _piker(engine)
	piker.summoned_this_turn = false
	var trig := Ability.new()
	trig.ability_id = &"pick_type"
	trig.kind = &"TRIGGERED"
	trig.trigger = {on = "COMBAT_DAMAGE_TO_PLAYER"}
	var choose := AbilityEffect.new()
	choose.kind = &"CHOOSE"
	choose.params = {
		choice = "CHOOSE_CREATURE_TYPE",
		link = "picked",
		options = ["Scout", "Warrior"],
		prompt = "Choose a creature type.",
	}
	trig.effects = [choose]
	_give(piker, trig)
	_unblocked(engine, piker)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.AWAITING_DECISION)
	var dec: PlayerDecision = engine.state.pending_decision as PlayerDecision
	assert_eq(str(dec.candidates[0]), "Scout")
	assert_eq(str(dec.candidates[1]), "Warrior")
	assert_true((engine.state.stack as MagicStack).top().choices.is_empty())
	var pick := GameAction.new()
	pick.kind = GameAction.Kind.SUBMIT_DECISION
	pick.player_id = 0
	pick.extra = {choice = "Warrior"}
	assert_true(engine.submit(pick).ok)
	assert_eq((engine.state.stack as MagicStack).size(), 0)


func test_hexproof_shroud_protection_and_ward() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	var shock: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Shock")
	var query := {kind = "ANY_TARGET"}
	(piker.definition as CardDefinition).keywords = PackedStringArray(["Hexproof"])
	var ids: Array = engine.targeting.legal_ids(engine, query, shock.object_id)
	assert_false(ids.has(piker.object_id))
	piker.controller_id = 0
	ids = engine.targeting.legal_ids(engine, query, shock.object_id)
	assert_true(ids.has(piker.object_id))
	(piker.definition as CardDefinition).keywords = PackedStringArray(["Shroud"])
	ids = engine.targeting.legal_ids(engine, query, shock.object_id)
	assert_false(ids.has(piker.object_id))
	piker.controller_id = 1
	(piker.definition as CardDefinition).keywords = PackedStringArray(["Protection from red"])
	ids = engine.targeting.legal_ids(engine, query, shock.object_id)
	assert_false(ids.has(piker.object_id))
	(piker.definition as CardDefinition).keywords = PackedStringArray(["Ward"])
	ids = engine.targeting.legal_ids(engine, query, shock.object_id)
	assert_true(ids.has(piker.object_id))


func test_oracle_lines_classify_activated_abilities() -> void:
	var kellan: CardDefinition = db.definition_for("Kellan, Planar Trailblazer")
	var clauses: Array = OracleStructure.clauses(kellan.oracle_text)
	assert_eq(clauses.size(), 2)
	assert_eq(str((clauses[0] as Dictionary).kind), "ACTIVATED")
	assert_eq(str((clauses[0] as Dictionary).cost), "{1}{R}")
	assert_eq(str((clauses[1] as Dictionary).kind), "ACTIVATED")
	var triggered: Array = OracleStructure.clauses("Whenever you draw a card, you may draw a card.")
	assert_eq(str((triggered[0] as Dictionary).kind), "TRIGGERED")


func _session() -> GameSession:
	var session := GameSession.new()
	session.start_table_demo(1)
	session.keep_hand(0)
	return session


func _piker(engine: RulesEngine) -> GameObject:
	return Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")


func _kellan(engine: RulesEngine) -> GameObject:
	return Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Kellan, Planar Trailblazer")


func _mana_draw(ability_id: StringName, mana: String) -> Ability:
	var ab := Ability.new()
	ab.ability_id = ability_id
	ab.kind = &"ACTIVATED"
	var cost := AbilityCost.new()
	cost.kind = &"MANA"
	cost.mana = mana
	ab.costs = [cost]
	var fx := AbilityEffect.new()
	fx.kind = &"DRAW"
	fx.params = {n = 1}
	ab.effects = [fx]
	return ab


func _tap_draw() -> Ability:
	var ab := Ability.new()
	ab.ability_id = &"tap_draw"
	ab.kind = &"ACTIVATED"
	var cost := AbilityCost.new()
	cost.kind = &"TAP"
	ab.costs = [cost]
	var fx := AbilityEffect.new()
	fx.kind = &"DRAW"
	fx.params = {n = 1}
	ab.effects = [fx]
	return ab


func _give(obj: GameObject, ab: Ability) -> void:
	(obj.definition as CardDefinition).abilities = [ab]


func _may_draw_creature(engine: RulesEngine) -> GameObject:
	var piker := _piker(engine)
	piker.summoned_this_turn = false
	var trig := Ability.new()
	trig.ability_id = &"may_draw"
	trig.kind = &"TRIGGERED"
	trig.trigger = {on = "COMBAT_DAMAGE_TO_PLAYER"}
	var may := AbilityEffect.new()
	may.kind = &"MAY"
	may.params = {link = "draw_it", prompt = "Draw a card?"}
	var draw := AbilityEffect.new()
	draw.kind = &"DRAW"
	draw.params = {n = 1, if_link = "draw_it"}
	trig.effects = [may, draw]
	_give(piker, trig)
	return piker


func _can(engine: RulesEngine, obj: GameObject, ability_id: StringName) -> bool:
	return _action_for(engine, GameAction.Kind.ACTIVATE_ABILITY, obj.object_id, ability_id)


func _action_for(engine: RulesEngine, kind: int, object_id: int, ability_id: StringName = &"") -> bool:
	for act in engine.legal_actions(0):
		var ga := act as GameAction
		if ga.kind != kind or ga.object_id != object_id:
			continue
		if ability_id != &"" and ga.ability_id != ability_id:
			continue
		return true
	return false


func _report_row(engine: RulesEngine, obj: GameObject, index: int) -> Dictionary:
	var report: Dictionary = engine.activation_report(obj.object_id)
	return report.abilities[index]


func _pay_and_confirm(engine: RulesEngine, obj: GameObject, ability_id: StringName, mana_text: String) -> void:
	if mana_text != "":
		engine.mana.add(0, ManaCost.parse(mana_text))
	var announced: SubmitResult = engine.submit(Fixtures.activate_ability(0, obj.object_id, ability_id))
	assert_true(announced.ok, announced.error)
	if engine.state.mode == EngineEnums.EngineMode.PAYING_COSTS:
		assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
		assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)


func _resolve_paid(engine: RulesEngine, obj: GameObject, ability_id: StringName, mana_text: String) -> void:
	_pay_and_confirm(engine, obj, ability_id, mana_text)
	Fixtures.both_pass(engine)


func _unblocked(engine: RulesEngine, attacker: GameObject) -> void:
	var cs := CombatState.new()
	cs.attacker_ids = [attacker.object_id]
	cs.defending_player_id = 1
	cs.defenders[attacker.object_id] = 1
	engine.state.combat = cs
	engine.apply_combat_damage()


func _has_ability(engine: RulesEngine, obj: GameObject, ability_id: String) -> bool:
	for a in engine.layers.abilities_for(engine.state, obj):
		if a is Ability and str((a as Ability).ability_id) == ability_id:
			return true
	return false


func _find_named(engine: RulesEngine, zone_id: int, player_id: int, card_name: String) -> GameObject:
	var zone: Zone = engine.state.zones.get_zone(zone_id, player_id)
	if zone == null:
		return null
	for oid in zone.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		if obj != null and obj.definition is CardDefinition and (obj.definition as CardDefinition).name == card_name:
			return obj
	return null
