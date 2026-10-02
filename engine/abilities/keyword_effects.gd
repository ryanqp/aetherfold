class_name KeywordEffects
extends RefCounted

## Effects behind the keyword abilities and keyword actions: ward, echo, vanishing, fading, cumulative upkeep,
## extort, enlist, flanking, rampage, madness, miracle, adapt, connive, learn, incubate, support, manifest, cloak,
## suspect, goad, fateseal. Called by AbilityExecutor for kinds it doesn't know.
## An effect that asks the player something asks first and changes the game after, because a paused
## effect runs again from its start once the answer is in.

const KINDS := ["ECHO", "COUNTDOWN", "CUMULATIVE_UPKEEP", "EXTORT", "ENLIST", "FLANKING", "RAMPAGE", "WARD", "MADNESS",
	"MIRACLE", "ADAPT", "CONNIVE", "LEARN", "INCUBATE", "SUPPORT", "MANIFEST", "SUSPECT", "GOAD", "FATESEAL", "INCUBATOR_FLIP"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func apply(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	match str(fx.kind):
		"ECHO":
			_echo(ex, engine, entry, source, fx)
		"COUNTDOWN":
			_countdown(engine, source, fx)
		"CUMULATIVE_UPKEEP":
			_cumulative(ex, engine, entry, source, fx)
		"EXTORT":
			_extort(ex, engine, entry, fx)
		"ENLIST":
			_enlist(ex, engine, entry, source)
		"FLANKING":
			_flanking(engine, entry, source)
		"RAMPAGE":
			_rampage(engine, entry, source, fx)
		"WARD":
			_ward(ex, engine, entry, fx)
		"MADNESS", "MIRACLE":
			_cast_offer(ex, engine, entry, fx)
		"ADAPT":
			if source != null and int(source.counters.get("+1/+1", 0)) == 0:
				_counters(source, "+1/+1", int(fx.params.get("n", 1)))
		"CONNIVE":
			_connive(ex, engine, entry, source, fx)
		"LEARN":
			_learn(ex, engine, entry)
		"INCUBATE":
			_incubate(engine, entry, fx)
		"SUPPORT":
			_support(engine, entry, source, fx)
		"MANIFEST":
			_manifest(engine, entry, fx)
		"SUSPECT":
			var t := _target_obj(engine, entry, fx, source)
			if t != null:
				t.suspected = true
		"GOAD":
			var g := _target_obj(engine, entry, fx, source)
			if g != null and not g.goaded_by.has(entry.controller_id):
				g.goaded_by.append(entry.controller_id)
		"FATESEAL":
			_fateseal(ex, engine, entry, fx)
		"INCUBATOR_FLIP":
			_incubator_flip(engine, source)


# --- Small helpers ------------------------------------------------------------------------------

static func _counters(obj: GameObject, name: String, n: int) -> void:
	if obj == null or n == 0:
		return
	obj.counters[name] = maxi(0, int(obj.counters.get(name, 0)) + n)
	if int(obj.counters[name]) == 0:
		obj.counters.erase(name)


static func _target_obj(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect, source: GameObject) -> GameObject:
	if bool(fx.params.get("self", false)) or not fx.params.has("target"):
		return source
	var idx := int(fx.params.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return null
	var o: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	if o == null or o.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return null
	return o


static func _sacrifice(engine: RulesEngine, obj: GameObject) -> void:
	if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


static func _lose(engine: RulesEngine, pid: int, n: int) -> void:
	engine.state.players[pid].life -= n
	engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, pid, {to_player = pid, amount = n, gain = false})


static func _gain(engine: RulesEngine, pid: int, n: int) -> void:
	engine.state.players[pid].life += n
	engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, pid, {to_player = pid, amount = n, gain = true})


static func _can_pay(engine: RulesEngine, pid: int, cost: ManaCost, life: int) -> bool:
	if life > 0 and engine.state.players[pid].life <= life:
		return false
	return engine.can_afford(pid, cost)


static func _pay(engine: RulesEngine, pid: int, cost: ManaCost, life: int) -> bool:
	if not _can_pay(engine, pid, cost, life):
		return false
	if not cost.is_zero() and not engine.pay_now(pid, cost):
		return false
	if life > 0:
		_lose(engine, pid, life)
	return true


## Asks "pay or not?" and returns {s: "paused"|"yes"|"no"}. The rival pays whenever it can.
static func _pay_question(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, pid: int, link: String, prompt: String, can: bool) -> String:
	if not can:
		return "no"
	var ans := ex._ask_yes_no(engine, entry, pid, link, prompt)
	if ans.s == "paused":
		return "paused"
	if ans.s == "picked":
		return "yes" if bool(ans.value) else "no"
	return "yes"


static func _pump_self(engine: RulesEngine, obj: GameObject, p: int, t: int, controller: int) -> void:
	if obj == null:
		return
	var effect := ContinuousEffect.new()
	effect.object_ids = [obj.object_id]
	effect.source_id = obj.object_id
	effect.controller_id = controller
	effect.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	effect.until_eot = true
	effect.power = p
	effect.toughness = t
	engine.state.effects.append(effect)


# --- Upkeep keywords ------------------------------------------------------------------------------

## Echo (CR 702.30): pay the echo cost or sacrifice it.
static func _echo(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD or int(source.counters.get("echo", 0)) <= 0:
		return
	var cost := ManaCost.parse(str(fx.params.get("cost", "")))
	var pid := source.controller_id
	var a := _pay_question(ex, engine, entry, pid, "echo", "Pay echo %s for %s? (No sacrifices it.)" % [str(fx.params.get("cost", "")), ex._name_of(engine, source.object_id)], engine.can_afford(pid, cost))
	if a == "paused":
		return
	_counters(source, "echo", -1)
	if a == "yes" and _pay(engine, pid, cost, 0):
		return
	_sacrifice(engine, source)


## Vanishing (CR 702.63) and fading (CR 702.32): count a counter down each upkeep.
static func _countdown(engine: RulesEngine, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var name := str(fx.params.get("counter", "time"))
	var left := int(source.counters.get(name, 0))
	if str(fx.params.get("mode", "vanishing")) == "fading":
		if left <= 0:
			_sacrifice(engine, source)
		else:
			_counters(source, name, -1)
		return
	if left > 0:
		_counters(source, name, -1)
		if left - 1 <= 0:
			_sacrifice(engine, source)


## Cumulative upkeep (CR 702.24): an age counter, then pay the cost once for each.
static func _cumulative(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var age := int(source.counters.get("age", 0)) + 1
	var base := ManaCost.parse(str(fx.params.get("cost", "")))
	var total := ManaCost.new()
	for _i in age:
		total.absorb(base)
	var life := int(fx.params.get("life", 0)) * age
	var pid := source.controller_id
	var nm := ex._name_of(engine, source.object_id)
	var a := _pay_question(ex, engine, entry, pid, "cu", "Pay cumulative upkeep for %s (age %d)? (No sacrifices it.)" % [nm, age], _can_pay(engine, pid, total, life))
	if a == "paused":
		return
	_counters(source, "age", 1)
	if a == "yes" and _pay(engine, pid, total, life):
		return
	_sacrifice(engine, source)


# --- Cast triggers ----------------------------------------------------------------------------------

## Extort (CR 702.101): pay {W/B}; each opponent loses 1 life and you gain that much.
static func _extort(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var cost := ManaCost.parse("{W/B}")
	var a := _pay_question(ex, engine, entry, pid, "extort", "Extort: pay {W/B} to drain each opponent for 1?", engine.can_afford(pid, cost))
	if a != "yes" or not _pay(engine, pid, cost, 0):
		return
	var gained := 0
	for p in engine.state.players:
		if p.player_id != pid and not p.lost:
			_lose(engine, p.player_id, 1)
			gained += 1
	if gained > 0:
		_gain(engine, pid, gained)
	if engine.sba != null:
		engine.sba.check(engine)


## Madness (CR 702.35) and miracle (CR 702.94): offer to cast the card for its special cost.
static func _cast_offer(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var oid := int(fx.params.get("object_id", 0))
	var obj: GameObject = engine.state.objects.get(oid)
	if obj == null:
		return
	var is_madness := str(fx.kind) == "MADNESS"
	var want_zone := EngineEnums.ZoneId.EXILE if is_madness else EngineEnums.ZoneId.HAND
	if obj.zone != want_zone:
		return
	var pid := entry.controller_id
	var mode := "madness" if is_madness else "miracle"
	var pl: Dictionary = engine.kw.plan(pid, obj, {"mode": mode})
	var ok: bool = bool(pl.ok) and engine.kw.afford(pid, obj, pl.cost)
	var nm := ex._name_of(engine, oid)
	var a := _pay_question(ex, engine, entry, pid, mode, "%s: cast %s for its %s cost?" % [mode.capitalize(), nm, mode], ok)
	if a == "paused":
		return
	if a == "yes" and engine.kw.cast_now(pid, oid, {"mode": mode}):
		return
	if is_madness and obj.zone == EngineEnums.ZoneId.EXILE:
		engine.state.zones.move(oid, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


## Ward (CR 702.21): counter the spell or ability unless its controller pays.
static func _ward(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var sid := int(fx.params.get("target_stack_id", 0))
	var found: StackEntry = null
	for e in (engine.state.stack as MagicStack).entries:
		if (e as StackEntry).stack_id == sid:
			found = e
	if found == null:
		return
	var payer := found.controller_id
	var cost := ManaCost.parse(str(fx.params.get("cost", "")))
	var life := int(fx.params.get("life", 0))
	var label := ("%s" % str(fx.params.get("cost", ""))) if life == 0 else "%d life" % life
	var a := _pay_question(ex, engine, entry, payer, "ward", "Ward: pay %s or your spell or ability is countered." % label, _can_pay(engine, payer, cost, life))
	if a == "paused":
		return
	if a == "yes" and _pay(engine, payer, cost, life):
		return
	engine.counter_entry(sid)


# --- Combat keywords -----------------------------------------------------------------------------------

## Enlist (CR 702.154): tap a non-attacking creature to add its power.
static func _enlist(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var pid := source.controller_id
	var cs: CombatState = engine.state.combat as CombatState
	var options: Array = []
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != pid or o.tapped or o.object_id == source.object_id or not engine.is_creature_now(o):
			continue
		if cs != null and cs.attacker_ids.has(o.object_id):
			continue
		if o.summoned_this_turn and not engine.has_keyword(o, "Haste"):
			continue
		options.append(ex._card_option(engine, int(oid)))
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "enlist", "Enlist: tap a creature to add its power to %s." % ex._name_of(engine, source.object_id), options, true)
	if ans.s == "paused":
		return
	var pick := -1
	if ans.s == "picked":
		pick = int(ans.value)
	elif ans.s == "auto":
		var best := -1
		for opt in options:
			var cand: GameObject = engine.state.objects.get(int(opt.value))
			if cand != null and engine.power_of(cand) > best:
				best = engine.power_of(cand)
				pick = int(opt.value)
		if best <= 0:
			pick = -1
	var lent: GameObject = engine.state.objects.get(pick)
	if lent == null:
		return
	lent.tapped = true
	_pump_self(engine, source, engine.power_of(lent), 0, pid)


## Flanking (CR 702.25): blockers without flanking get -1/-1 until end of turn.
static func _flanking(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	for bid in entry.ctx.get("blocker_ids", []):
		var b: GameObject = engine.state.objects.get(int(bid))
		if b != null and not engine.has_keyword(b, "Flanking") and not (b.definition is CardDefinition and (b.definition as CardDefinition).kw().has("flanking")):
			_pump_self(engine, b, -1, -1, entry.controller_id)
	if engine.sba != null:
		engine.sba.check(engine)


## Rampage N (CR 702.23): +N/+N for each creature blocking it beyond the first.
static func _rampage(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var extra := int(entry.ctx.get("blocker_count", 1)) - 1
	if extra > 0 and source != null:
		var n := int(fx.params.get("n", 1))
		_pump_self(engine, source, n * extra, n * extra, entry.controller_id)


# --- Keyword actions -----------------------------------------------------------------------------------

## Connive (CR 701.50): draw, then discard; a nonland discard puts a +1/+1 counter on the creature.
static func _connive(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var who := _target_obj(engine, entry, fx, source)
	if who == null:
		return
	var pid := who.controller_id
	if not entry.choices.has("cdrawn"):
		engine.draw_card(pid)
		entry.choices["cdrawn"] = 1
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null or hand.is_empty():
		return
	var options: Array = []
	for oid in hand.object_ids:
		options.append(ex._card_option(engine, int(oid)))
	var ans := ex._ask(engine, entry, pid, "connive", "Connive: discard a card.", options)
	if ans.s == "paused":
		return
	var pick := int(ans.value) if ans.s == "picked" else ex._cheapest_in_hand(engine, pid, [])
	var card: GameObject = engine.state.objects.get(pick)
	if card == null:
		return
	var nonland: bool = card.definition is CardDefinition and not (card.definition as CardDefinition).is_land()
	engine.discard_card(pid, pick)
	if nonland:
		_counters(who, "+1/+1", 1)


## Learn (CR 701.48): with no sideboard, the rummage half: discard a card to draw one.
static func _learn(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null or hand.is_empty():
		return
	var options: Array = []
	for oid in hand.object_ids:
		options.append(ex._card_option(engine, int(oid)))
	var ans := ex._ask(engine, entry, pid, "learn", "Learn: discard a card to draw a card? (There's no sideboard to fetch a Lesson from.)", options, true)
	if ans.s == "paused" or ans.s == "declined":
		return
	var pick := int(ans.value) if ans.s == "picked" else -1
	if pick < 0:
		return
	engine.discard_card(pid, pick)
	engine.draw_card(pid)


## Incubate N (CR 701.53): an Incubator artifact token with N +1/+1 counters.
static func _incubate(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var def := TokenCatalog.new().definition_for(TokenCatalog.INCUBATOR)
	var obj: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, {
		definition = def, is_token = true, controller_id = entry.controller_id})
	if obj == null:
		return
	var raw_n: Variant = fx.params.get("n", 1)
	obj.counters["+1/+1"] = int(entry.ctx.get("exiled_count", 0)) if raw_n is Dictionary else int(raw_n)
	engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, entry.controller_id, {
		from_id = 0, to_id = obj.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0,
	})


static func _incubator_flip(engine: RulesEngine, source: GameObject) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	source.definition = TokenCatalog.new().definition_for(TokenCatalog.PHYREXIAN_0_0)


## Support N (CR 701.41): a +1/+1 counter on each of up to N other creatures you control (the biggest first).
static func _support(engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var picks: Array = []
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id == entry.controller_id and engine.is_creature_now(o) and (source == null or o.object_id != source.object_id):
			picks.append(o)
	picks.sort_custom(func(a, b) -> bool: return engine.power_of(a) > engine.power_of(b))
	for i in mini(int(fx.params.get("n", 1)), picks.size()):
		_counters(picks[i], "+1/+1", 1)


## Manifest (CR 701.40) and cloak (CR 701.58): the top card of your library as a face-down 2/2 creature.
static func _manifest(engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or lib.is_empty():
		return
	var cloak := bool(fx.params.get("cloak", false))
	for _i in int(fx.params.get("n", 1)):
		if lib.is_empty():
			break
		var top_id := int(lib.object_ids[0])
		var moved: GameObject = engine.state.zones.move(top_id, EngineEnums.ZoneId.BATTLEFIELD, pid)
		if moved == null:
			continue
		moved.face_down = true
		moved.cast_mode = "cloak" if cloak else "manifest"
		if cloak:
			moved.ward_extra = "{2}"


## Fateseal N (CR 701.29): look at the top N cards of an opponent's library; each may go to the bottom.
static func _fateseal(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, fx: AbilityEffect) -> void:
	var pid := entry.controller_id
	var opp := -1
	for p in engine.state.players:
		if p.player_id != pid and not p.lost:
			opp = p.player_id
			break
	if opp < 0:
		return
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, opp)
	if lib == null:
		return
	var tops: Array = []
	for i in mini(int(fx.params.get("n", 1)), lib.object_ids.size()):
		tops.append(int(lib.object_ids[i]))
	var away: Array = []
	for i in tops.size():
		var oid: int = tops[i]
		var ans := ex._ask_yes_no(engine, entry, pid, "seal_%d" % i, "Fateseal: put %s on the bottom of its owner's library? (No keeps it on top.)" % ex._name_of(engine, oid), [oid])
		if ans.s == "paused":
			return
		if ans.s == "picked":
			if bool(ans.value):
				away.append(oid)
		else:
			var c: GameObject = engine.state.objects.get(oid)
			if c != null and c.definition is CardDefinition and not (c.definition as CardDefinition).is_land() and (c.definition as CardDefinition).cmc >= 3:
				away.append(oid)
	for oid2 in away:
		engine.put_library_bottom(int(oid2), opp)
