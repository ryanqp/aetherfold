class_name KeywordActions
extends RefCounted

## Keyword actions (CR 701) and the effects of triggered keyword abilities (CR 702) that the older executor files
## don't cover: modular, graft, poisonous, mentor, mobilize, firebending, increment, exploit, backup, provoke,
## "as it enters" keywords (unleash, tribute, amplify, devour, sunburst, ravenous, modular, graft), champion, storm,
## ripple, soulbond, regenerate, triple, exchange, transform, detain, monstrosity, vote, exert, venture into the
## dungeon, the initiative, the Ring tempts you, villainous choices, time travel, forage, manifest dread, endure,
## harness, airbend, earthbend, blight, heal and recruit.
##
## Like the other effect files: an effect that needs a player's answer asks first (AbilityExecutor._ask*), returns,
## and runs again from its start once answered; answers live in entry.choices.

const KINDS := ["MOVE_COUNTERS", "GRAFT_MOVE", "POISON", "MENTOR", "MOBILIZE", "FIREBEND", "INCREMENT", "EXPLOIT",
	"BACKUP", "MARK", "PROVOKE", "AS_ENTERS", "CHAMPION", "STORM", "RIPPLE", "SOULBOND", "EQUIP_TOKEN", "TRIPLE_PT",
	"EXCHANGE_CONTROL", "EXCHANGE_LIFE", "REGENERATE", "TRANSFORM", "DETAIN", "MONSTROSITY", "VOTE", "EXERT",
	"VENTURE", "TAKE_INITIATIVE", "RING_TEMPTS", "VILLAINOUS_CHOICE", "TIME_TRAVEL", "FORAGE", "MANIFEST_DREAD",
	"ENDURE", "HARNESS", "AIRBEND", "EARTHBEND", "BLIGHT", "HEAL", "RECRUIT", "COPY_SPELL_N", "EPIC", "CIPHER",
	"HAUNT", "MELD", "SECTOR_PICK", "PARADIGM_COPY", "BLITZ_DRAW", "OFFSPRING_COPY", "SQUAD_COPIES", "COUNTERS_X",
	"SAC_SELF", "AWAKEN", "RECOVER", "AURA_SWAP"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func apply(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	var p: Dictionary = fx.params
	match str(fx.kind):
		"MOVE_COUNTERS":
			_move_counters(engine, entry, p)
		"GRAFT_MOVE":
			_graft_move(ex, engine, entry, source)
		"POISON":
			var d := int(entry.ctx.get("defender", -1))
			if d >= 0 and d < engine.state.players.size():
				engine.state.players[d].poison += int(p.get("n", 1))
				engine.sba.check(engine)
		"MENTOR":
			_mentor(engine, source)
		"MOBILIZE":
			_mobilize(engine, entry, source, int(p.get("n", 1)))
		"FIREBEND":
			var pool: ManaPool = engine.mana.pool(entry.controller_id)
			pool.r += int(p.get("n", 1))
			engine.state.combat_mana[entry.controller_id] = int(engine.state.combat_mana.get(entry.controller_id, 0)) + int(p.get("n", 1))
		"INCREMENT":
			_increment(engine, entry, source)
		"EXPLOIT":
			_exploit(ex, engine, entry, source)
		"BACKUP":
			_backup(engine, entry, source, p)
		"MARK":
			if source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
				source.marks[str(p.get("mark", ""))] = true
		"PROVOKE":
			_provoke(engine, entry, source, p)
		"AS_ENTERS":
			_as_enters(ex, engine, entry, source, p)
		"CHAMPION":
			_champion(ex, engine, entry, source, p)
		"STORM":
			_storm(engine, entry, source, p)
		"RIPPLE":
			_ripple(ex, engine, entry, source, p)
		"SOULBOND":
			_soulbond(ex, engine, entry, source)
		"EQUIP_TOKEN":
			_equip_token(engine, entry, source, p)
		"TRIPLE_PT":
			_mult_pt(ex, engine, entry, source, p, 2)
		"EXCHANGE_CONTROL":
			_exchange_control(engine, entry, p)
		"EXCHANGE_LIFE":
			_exchange_life(engine, entry, p)
		"REGENERATE":
			for o in ex._affected(engine, entry, source, fx):
				(o as GameObject).regen_shields += 1
		"TRANSFORM":
			for o2 in ex._affected(engine, entry, source, fx):
				transform(engine, o2)
		"DETAIN":
			for o3 in ex._affected(engine, entry, source, fx):
				(o3 as GameObject).detained_by = entry.controller_id
		"MONSTROSITY":
			_monstrosity(engine, entry, source, ex, p)
		"VOTE":
			_vote(ex, engine, entry, p)
		"EXERT":
			if source != null:
				source.marks["exerted"] = true
		"VENTURE":
			venture(ex, engine, entry, str(p.get("dungeon", "")))
		"TAKE_INITIATIVE":
			take_initiative(engine, entry.controller_id)
		"RING_TEMPTS":
			_ring_tempts(ex, engine, entry)
		"VILLAINOUS_CHOICE":
			_villainous(ex, engine, entry, source, p)
		"TIME_TRAVEL":
			_time_travel(ex, engine, entry)
		"FORAGE":
			_forage(ex, engine, entry)
		"MANIFEST_DREAD":
			_manifest_dread(ex, engine, entry)
		"ENDURE":
			_endure(ex, engine, entry, source, p)
		"RECOVER":
			_recover(ex, engine, entry, source, p)
		"AURA_SWAP":
			_aura_swap(ex, engine, entry, source)
		"HARNESS":
			if source != null:
				source.marks["harnessed"] = true
		"AIRBEND":
			_airbend(ex, engine, entry, source, fx)
		"EARTHBEND":
			_earthbend(engine, entry, p)
		"BLIGHT":
			_blight(ex, engine, entry, p)
		"HEAL":
			for o4 in ex._affected(engine, entry, source, fx):
				(o4 as GameObject).damage_marked = 0
		"RECRUIT":
			_recruit(ex, engine, entry)
		"COPY_SPELL_N":
			_copy_spell_n(engine, entry, p)
		"EPIC":
			engine.state.players[entry.controller_id].epic_locked = true
		"CIPHER":
			_cipher(ex, engine, entry)
		"HAUNT":
			_haunt(engine, entry, source)
		"MELD":
			_meld(engine, entry, source, p)
		"SECTOR_PICK":
			_sector_pick(ex, engine, entry, source, p)
		"PARADIGM_COPY":
			_paradigm_copy(ex, engine, entry, p)
		"BLITZ_DRAW":
			engine.draw_card(entry.controller_id)
		"OFFSPRING_COPY":
			_token_copies(engine, entry, source, 1, true)
		"SQUAD_COPIES":
			_token_copies(engine, entry, source, int(entry.ctx.get("n", p.get("n", 1))), false)
		"SAC_SELF":
			if source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD:
				engine.state.zones.move(source.object_id, EngineEnums.ZoneId.GRAVEYARD, source.owner_id)
		"AWAKEN":
			_awaken(engine, entry, int(p.get("n", 1)))
		"COUNTERS_X":
			if source != null:
				source.counters["+1/+1"] = int(source.counters.get("+1/+1", 0)) + source.x_paid


# --- Helpers ----------------------------------------------------------------------------------------

static func _def(o: GameObject) -> CardDefinition:
	return o.definition as CardDefinition if o != null and o.definition is CardDefinition else null


static func _bf(engine: RulesEngine) -> Array:
	var z: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	return z.object_ids.duplicate() if z != null else []


static func _token(engine: RulesEngine, pid: int, spec: Dictionary, tapped: bool = false) -> GameObject:
	var d := TokenCatalog.new().from_spec(spec)
	var opts := {definition = d, is_token = true, controller_id = pid}
	if tapped:
		opts["tapped"] = true
	var t: GameObject = engine.state.zones.create(pid, EngineEnums.ZoneId.BATTLEFIELD, opts)
	if t != null:
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, pid, {from_id = 0, to_id = t.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0})
	return t


static func _target_obj(engine: RulesEngine, entry: StackEntry, idx: int) -> GameObject:
	if idx < 0 or idx >= entry.targets.size():
		return null
	var o: GameObject = engine.state.objects.get(int(entry.targets[idx]))
	return o if o != null and o.zone == EngineEnums.ZoneId.BATTLEFIELD else null


static func _creatures_of(engine: RulesEngine, pid: int) -> Array:
	var out: Array = []
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id == pid and engine.is_creature_now(o):
			out.append(o)
	return out


# --- Counters keywords --------------------------------------------------------------------------------

## Modular (CR 702.43a): the +1/+1 counters it had as it died go on the target artifact creature.
static func _move_counters(engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var t := _target_obj(engine, entry, int(p.get("target", 0)))
	if t == null or not engine.is_creature_now(t):
		return
	var had: Dictionary = entry.ctx.get("counters", {})
	var n := int(had.get(str(p.get("name", "+1/+1")), 0))
	if n > 0:
		t.counters["+1/+1"] = int(t.counters.get("+1/+1", 0)) + n


## Graft (CR 702.58a): you may move a +1/+1 counter from this onto the creature that entered.
static func _graft_move(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	var other: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
	if source == null or other == null or other.zone != EngineEnums.ZoneId.BATTLEFIELD or int(source.counters.get("+1/+1", 0)) <= 0:
		return
	var ans := ex._ask_yes_no(engine, entry, entry.controller_id, "graft", "Graft: move a +1/+1 counter from %s onto %s?" % [ex._name_of(engine, source.object_id), ex._name_of(engine, other.object_id)])
	if ans.s == "paused":
		return
	## The rival grafts onto its own creatures only.
	var yes := bool(ans.value) if ans.s == "picked" else other.controller_id == source.controller_id
	if yes:
		source.counters["+1/+1"] = int(source.counters["+1/+1"]) - 1
		other.counters["+1/+1"] = int(other.counters.get("+1/+1", 0)) + 1


## Mentor (CR 702.134a): +1/+1 counter on the attacking creature with the greatest power less than this one's.
static func _mentor(engine: RulesEngine, source: GameObject) -> void:
	if source == null or not (engine.state.combat is CombatState):
		return
	var best: GameObject = null
	for aid in (engine.state.combat as CombatState).attacker_ids:
		var a: GameObject = engine.state.objects.get(int(aid))
		if a == null or a.object_id == source.object_id or engine.power_of(a) >= engine.power_of(source):
			continue
		if best == null or engine.power_of(a) > engine.power_of(best):
			best = a
	if best != null:
		best.counters["+1/+1"] = int(best.counters.get("+1/+1", 0)) + 1


## Mobilize N (CR 702.181a): N 1/1 red Warriors tapped and attacking, sacrificed at the next end step.
static func _mobilize(engine: RulesEngine, entry: StackEntry, source: GameObject, n: int) -> void:
	if not (engine.state.combat is CombatState):
		return
	var cs := engine.state.combat as CombatState
	var defender := int(cs.defenders.get(source.object_id, cs.defending_player_id)) if source != null else cs.defending_player_id
	for _i in n:
		var t := _token(engine, entry.controller_id, {"subtypes": ["Warrior"], "colors": ["R"], "p": "1", "t": "1"}, true)
		if t != null:
			t.sacrifice_at_end = true
			cs.attacker_ids.append(t.object_id)
			cs.defenders[t.object_id] = defender


## Increment (CR 702.191a): the spell cost more mana than this creature's power or toughness.
static func _increment(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null or not engine.is_creature_now(source):
		return
	var spell: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
	var spent := spell.mana_spent if spell != null else 0
	if spent > engine.power_of(source) or spent > engine.toughness_of(source):
		source.counters["+1/+1"] = int(source.counters.get("+1/+1", 0)) + 1


## Exploit (CR 702.110a): you may sacrifice a creature; "when this exploits a creature" triggers.
static func _exploit(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	var pid := entry.controller_id
	var options: Array = []
	for c in _creatures_of(engine, pid):
		options.append(ex._card_option(engine, (c as GameObject).object_id))
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "exploit", "Exploit: sacrifice a creature?", options, true)
	if ans.s == "paused" or ans.s == "declined" or ans.s == "auto":
		return
	var victim: GameObject = engine.state.objects.get(int(ans.value))
	if victim == null:
		return
	engine.state.zones.move(victim.object_id, EngineEnums.ZoneId.GRAVEYARD, victim.owner_id)
	if source != null and engine.triggers != null:
		engine.triggers.fire_object_event(engine, "EXPLOITS", source, {object_id = victim.object_id, player_id = pid})


## Backup N (CR 702.165a): counters on the target; another creature also gets this card's abilities printed below
## backup until end of turn.
static func _backup(engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var t := _target_obj(engine, entry, int(p.get("target", 0)))
	if t == null:
		return
	t.counters["+1/+1"] = int(t.counters.get("+1/+1", 0)) + int(p.get("n", 1))
	if source == null or t.object_id == source.object_id or _def(source) == null:
		return
	var below := false
	var eff := ContinuousEffect.new()
	eff.object_ids = [t.object_id]
	eff.source_id = source.object_id
	eff.controller_id = entry.controller_id
	eff.until_eot = true
	eff.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	for raw in OracleIr.normalize(_def(source)).split("\n"):
		var line := str(raw).strip_edges()
		if line.to_lower().begins_with("backup"):
			below = true
			continue
		if not below or line == "":
			continue
		for part in line.split(", "):
			var e := KeywordDb.lookup(str(part))
			if not e.is_empty() and str(part).strip_edges().to_lower() == str(e.get("name")):
				eff.add_keywords.append(str(part).strip_edges().capitalize())
		for a in _def(source).abilities:
			if (a as Ability).text == line:
				eff.add_abilities.append(a)
	engine.state.effects.append(eff)


## Provoke (CR 702.39a): untap the target; it blocks this creature if able.
static func _provoke(engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var t := _target_obj(engine, entry, int(p.get("target", 0)))
	if t == null or source == null:
		return
	t.tapped = false
	t.marks["must block %d" % source.object_id] = true


# --- "As it enters" keywords ---------------------------------------------------------------------

## Unleash, tribute, amplify, devour, sunburst, ravenous, modular and graft counters (CR 614.12 "enters with").
static func _as_enters(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var pid := entry.controller_id
	var n := int(p.get("n", 0))
	match str(p.get("what", "")):
		"modular", "graft":
			_add(source, "+1/+1", n)
		"unleash":
			var ans := ex._ask_yes_no(engine, entry, pid, "unleash", "Unleash: put a +1/+1 counter on %s? (It can't block while it has one.)" % ex._name_of(engine, source.object_id))
			if ans.s == "paused":
				return
			if ans.s == "auto" or bool(ans.value):
				_add(source, "+1/+1", 1)
		"tribute":
			var opp := -1
			for pl in engine.state.players:
				if pl.player_id != pid and not pl.lost:
					opp = pl.player_id
			if opp < 0:
				return
			var t := ex._ask_yes_no(engine, entry, opp, "tribute", "Tribute %d: put %d +1/+1 counters on %s? (If you don't, its tribute ability happens.)" % [n, n, ex._name_of(engine, source.object_id)])
			if t.s == "paused":
				return
			var paid := bool(t.value) if t.s == "picked" else true
			if paid:
				_add(source, "+1/+1", n)
				source.marks["tribute paid"] = true
		"amplify":
			var shown := 0
			var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
			var mine := Query._subtype_words(_def(source).type_line)
			for hid in hand.object_ids:
				var hd := _def(engine.state.objects.get(hid))
				if hd == null or not hd.is_creature():
					continue
				for w in Query._subtype_words(hd.type_line):
					if mine.has(w):
						shown += 1
						break
			_add(source, "+1/+1", n * shown)
		"devour":
			var eaten := 0
			var guard := 0
			while guard < 20:
				guard += 1
				var options: Array = []
				for c in _creatures_of(engine, pid):
					if (c as GameObject).object_id != source.object_id:
						options.append(ex._card_option(engine, (c as GameObject).object_id))
				if options.is_empty():
					break
				var link := "devour_%d" % eaten
				var a := ex._ask(engine, entry, pid, link, "Devour %d: sacrifice a creature? (%d eaten)" % [n, eaten], options, true)
				if a.s == "paused":
					return
				if a.s != "picked":
					break
				var v: GameObject = engine.state.objects.get(int(a.value))
				if v != null:
					engine.state.zones.move(v.object_id, EngineEnums.ZoneId.GRAVEYARD, v.owner_id)
					eaten += 1
			_add(source, "+1/+1", n * eaten)
		"sunburst":
			var colors := source.colors_spent.size()
			_add(source, "+1/+1" if engine.is_creature_now(source) else "charge", colors)
		"ravenous":
			_add(source, "+1/+1", source.x_paid)
			if source.x_paid >= 5:
				engine.draw_card(pid)


static func _add(o: GameObject, name: String, n: int) -> void:
	if n > 0:
		o.counters[name] = int(o.counters.get(name, 0)) + n


## Champion an <type> (CR 702.72a): exile another one you control, or sacrifice this. It returns when this leaves.
static func _champion(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var ty := str(p.get("type", "creature"))
	var options: Array = []
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.object_id == source.object_id or o.controller_id != entry.controller_id or _def(o) == null:
			continue
		if ty == "creature" and engine.is_creature_now(o) or Query._subtype_words(_def(o).type_line).has(ty.capitalize()):
			options.append(ex._card_option(engine, o.object_id))
	if options.is_empty():
		engine.state.zones.move(source.object_id, EngineEnums.ZoneId.GRAVEYARD, source.owner_id)
		return
	var ans := ex._ask(engine, entry, entry.controller_id, "champion", "Champion: exile one of these (it returns when %s leaves), or sacrifice it." % ex._name_of(engine, source.object_id), options, true)
	if ans.s == "paused":
		return
	if ans.s == "declined":
		engine.state.zones.move(source.object_id, EngineEnums.ZoneId.GRAVEYARD, source.owner_id)
		return
	var pick := int(ans.value) if ans.s == "picked" else int((options[0] as Dictionary).value)
	var gone: GameObject = engine.state.zones.move(pick, EngineEnums.ZoneId.EXILE, engine.state.objects[pick].owner_id)
	if gone != null:
		var ids: Array = engine.state.exile_links.get(source.object_id, [])
		ids.append(gone.object_id)
		engine.state.exile_links[source.object_id] = ids


# --- Copy keywords ----------------------------------------------------------------------------------

## Storm (CR 702.40a): a copy for each spell cast before it this turn. Gravestorm (CR 702.69a): for each permanent put
## into a graveyard from the battlefield this turn.
static func _storm(engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var n := 0
	if bool(p.get("grave", false)):
		n = engine.state.died_this_turn
	else:
		for pl in engine.state.players:
			n += pl.spells_this_turn.size()
		n -= 1
	_copies_of(engine, source, entry.controller_id, n)


static func _copies_of(engine: RulesEngine, spell_obj: GameObject, controller: int, n: int) -> void:
	if spell_obj == null or n <= 0:
		return
	var spell_entry: StackEntry = null
	for e in (engine.state.stack as MagicStack).entries:
		if (e as StackEntry).object_id == spell_obj.object_id and (e as StackEntry).kind == StackEntry.Kind.SPELL:
			spell_entry = e
	if spell_entry == null:
		return
	for _i in n:
		PreconEffects.copy_spell(engine, spell_entry, controller)


## Replicate / conspire / casualty ... : `n` copies of the spell that set this off (ctx.spell_stack_id).
static func _copy_spell_n(engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var sid := int(entry.ctx.get("spell_stack_id", 0))
	var n := int(entry.ctx.get("n", p.get("n", 1)))
	for e in (engine.state.stack as MagicStack).entries:
		var se := e as StackEntry
		if se.stack_id == sid:
			for _i in n:
				PreconEffects.copy_spell(engine, se, entry.controller_id)
			return


## Ripple N (CR 702.60a): reveal the top N; cast any with the same name free; the rest go to the bottom.
static func _ripple(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or source == null or _def(source) == null:
		return
	var top: Array = lib.object_ids.slice(0, mini(int(p.get("n", 4)), lib.object_ids.size()))
	for tid in top:
		var d := _def(engine.state.objects.get(tid))
		if d != null and d.name == _def(source).name:
			var ans := ex._ask_yes_no(engine, entry, pid, "ripple_%d" % int(tid), "Ripple: cast %s without paying its mana cost?" % d.name, [int(tid)])
			if ans.s == "paused":
				return
			if ans.s == "auto" or bool(ans.value):
				lib.object_ids.erase(tid)
				lib.object_ids.push_front(tid)
				var moved: GameObject = engine.state.zones.move(int(tid), EngineEnums.ZoneId.HAND, pid)
				if moved != null and engine.cast_free(pid, moved.object_id):
					continue
	for tid2 in top:
		if lib.object_ids.has(tid2):
			lib.object_ids.erase(tid2)
			lib.object_ids.append(tid2)


## Soulbond (CR 702.95a): pair this with another unpaired creature you control.
static func _soulbond(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	var entered: GameObject = engine.state.objects.get(int(entry.ctx.get("object_id", 0)))
	if source == null or entered == null or source.paired_with != 0 or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var partner: GameObject = null
	if entered.object_id != source.object_id:
		if entered.paired_with == 0:
			partner = entered
	else:
		var options: Array = []
		for c in _creatures_of(engine, entry.controller_id):
			var co := c as GameObject
			if co.object_id != source.object_id and co.paired_with == 0:
				options.append(ex._card_option(engine, co.object_id))
		if options.is_empty():
			return
		var ans := ex._ask(engine, entry, entry.controller_id, "soulbond", "Soulbond: pair %s with a creature?" % ex._name_of(engine, source.object_id), options, true)
		if ans.s == "paused" or ans.s == "declined":
			return
		partner = engine.state.objects.get(int(ans.value) if ans.s == "picked" else int((options[0] as Dictionary).value))
	if partner == null:
		return
	source.paired_with = partner.object_id
	partner.paired_with = source.object_id


## For Mirrodin! / job select: a token, then attach this Equipment to it.
static func _equip_token(engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var t := _token(engine, entry.controller_id, p.get("spec", {}))
	if t != null:
		source.attached_to = t.object_id


# --- Keyword actions (CR 701) -------------------------------------------------------------------------

## Double (CR 701.10) and triple (CR 701.11): +X/+X where X is (factor) times its current power and toughness.
static func _mult_pt(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary, factor: int) -> void:
	var objs: Array = []
	if p.has("each"):
		objs = ex._each(engine, entry, source, p["each"])
	else:
		var t := _target_obj(engine, entry, int(p.get("target", 0)))
		if t != null:
			objs = [t]
	for o in objs:
		var obj: GameObject = o
		var eff := ContinuousEffect.new()
		eff.object_ids = [obj.object_id]
		eff.until_eot = true
		eff.controller_id = entry.controller_id
		eff.timestamp = engine.state.next_timestamp
		engine.state.next_timestamp += 1
		if bool(p.get("power", true)):
			eff.power = engine.power_of(obj) * factor
		if bool(p.get("toughness", true)):
			eff.toughness = engine.toughness_of(obj) * factor
		engine.state.effects.append(eff)


## Exchange control of two target permanents (CR 701.12b); nothing happens unless both are still there.
static func _exchange_control(engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var a := _target_obj(engine, entry, int(p.get("a", 0)))
	var b := _target_obj(engine, entry, int(p.get("b", 1)))
	if a == null or b == null or a.controller_id == b.controller_id:
		return
	var ca := a.controller_id
	a.controller_id = b.controller_id
	b.controller_id = ca
	a.summoned_this_turn = true
	b.summoned_this_turn = true


## Exchange life totals with target player (CR 701.12c).
static func _exchange_life(engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var idx := int(p.get("target", 0))
	if idx < 0 or idx >= entry.targets.size():
		return
	var other := TargetingManager.decode_player(int(entry.targets[idx]))
	if other < 0:
		return
	var me := entry.controller_id
	var l := engine.state.players[me].life
	engine.state.players[me].life = engine.state.players[other].life
	engine.state.players[other].life = l
	engine.sba.check(engine)


## Transform / convert (CR 701.27, 701.28): a double-faced permanent turns to its other face.
static func transform(engine: RulesEngine, obj: GameObject) -> void:
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	if obj.front_def != null:
		obj.definition = obj.front_def
		obj.front_def = null
	else:
		var d := _def(obj)
		if d == null or d.back_face == null:
			return
		if d.back_face.is_instant() or d.back_face.is_sorcery():
			return
		obj.front_def = d
		obj.definition = d.back_face
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, obj.controller_id, {object_id = obj.object_id, transformed = true})


## Monstrosity N (CR 701.37a). "When ~ becomes monstrous" triggers.
static func _monstrosity(engine: RulesEngine, entry: StackEntry, source: GameObject, ex: AbilityExecutor, p: Dictionary) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD or bool(source.marks.get("monstrous", false)):
		return
	var n := ex._value(engine, entry, source, p.get("n", 1))
	source.counters["+1/+1"] = int(source.counters.get("+1/+1", 0)) + n
	source.marks["monstrous"] = true
	if engine.triggers != null:
		engine.triggers.fire_object_event(engine, "BECOMES_MONSTROUS", source, {object_id = source.object_id, player_id = source.controller_id, x = n})


## Vote (CR 701.38): each player, starting with you, votes for one of the options. The tally goes in ctx.votes.
static func _vote(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var options: Array = []
	for o in p.get("options", []):
		options.append({"value": str(o), "label": str(o).capitalize()})
	if options.is_empty():
		return
	var tally := {}
	var n := engine.state.players.size()
	for i in n:
		var pid := (entry.controller_id + i) % n
		if engine.state.players[pid].lost:
			continue
		var ans := ex._ask(engine, entry, pid, "vote_%d" % pid, "Vote:", options)
		if ans.s == "paused":
			return
		var v := str(ans.value) if ans.s == "picked" else str(options[0 if pid == entry.controller_id else options.size() - 1].value)
		tally[v] = int(tally.get(v, 0)) + 1
	entry.ctx["votes"] = tally


## Venture into the dungeon (CR 701.49) and the initiative's Undercity (CR 725).
const DUNGEONS := {
	"Lost Mine of Phandelver": {
		"Cave Entrance": {"text": "Scry 1.", "next": ["Goblin Lair", "Mine Tunnels"]},
		"Goblin Lair": {"text": "Create a 1/1 red Goblin creature token.", "next": ["Storeroom", "Dark Pool"]},
		"Mine Tunnels": {"text": "Create a Treasure token.", "next": ["Dark Pool", "Fungi Cavern"]},
		"Storeroom": {"text": "Put a +1/+1 counter on target creature.", "next": ["Temple of Dumathoin"]},
		"Dark Pool": {"text": "Each opponent loses 1 life and you gain 1 life.", "next": ["Temple of Dumathoin"]},
		"Fungi Cavern": {"text": "Target creature gets -4/-0 until your next turn.", "next": ["Temple of Dumathoin"]},
		"Temple of Dumathoin": {"text": "Draw a card.", "next": []},
	},
	"Dungeon of the Mad Mage": {
		"Yawning Portal": {"text": "You gain 1 life.", "next": ["Dungeon Level"]},
		"Dungeon Level": {"text": "Scry 1.", "next": ["Goblin Bazaar", "Twisted Caverns"]},
		"Goblin Bazaar": {"text": "Create a Treasure token.", "next": ["Lost Level"]},
		"Twisted Caverns": {"text": "Target creature can't attack until your next turn.", "next": ["Lost Level"]},
		"Lost Level": {"text": "Scry 2.", "next": ["Runestone Caverns", "Muiral's Graveyard"]},
		"Runestone Caverns": {"text": "Exile the top two cards of your library. You may play them.", "next": ["Deep Mines"]},
		"Muiral's Graveyard": {"text": "Create two 1/1 black Skeleton creature tokens.", "next": ["Deep Mines"]},
		"Deep Mines": {"text": "Scry 3.", "next": ["Mad Wizard's Lair"]},
		"Mad Wizard's Lair": {"text": "Draw three cards and reveal them. You may cast one of them without paying its mana cost.", "next": []},
	},
	"Tomb of Annihilation": {
		"Trapped Entry": {"text": "Each player loses 1 life.", "next": ["Veils of Fear", "Oubliette"]},
		"Veils of Fear": {"text": "Each player loses 2 life unless they discard a card.", "next": ["Sandfall Cell"]},
		"Sandfall Cell": {"text": "Each player loses 2 life unless they sacrifice an artifact, a creature, or a land.", "next": ["Cradle of the Death God"]},
		"Oubliette": {"text": "Discard a card and sacrifice an artifact, a creature, and a land.", "next": ["Cradle of the Death God"]},
		"Cradle of the Death God": {"text": "Create a 4/4 black God Horror creature token with deathtouch.", "next": []},
	},
	"Undercity": {
		"Secret Entrance": {"text": "Search your library for a basic land card, reveal it, put it into your hand.", "next": ["Forge", "Lost Well"]},
		"Forge": {"text": "Put two +1/+1 counters on target creature.", "next": ["Trap!", "Arena"]},
		"Lost Well": {"text": "Scry 2.", "next": ["Arena", "Stash"]},
		"Trap!": {"text": "Target player loses 5 life.", "next": ["Archives"]},
		"Arena": {"text": "Goad target creature.", "next": ["Archives", "Catacombs"]},
		"Stash": {"text": "Create a Treasure token.", "next": ["Catacombs"]},
		"Archives": {"text": "Draw a card.", "next": ["Throne of the Dead Three"]},
		"Catacombs": {"text": "Create a 4/1 black Skeleton creature token with menace.", "next": ["Throne of the Dead Three"]},
		"Throne of the Dead Three": {"text": "Reveal cards from the top of your library until you reveal a creature card. Put that card onto the battlefield and the rest on the bottom of your library in a random order.", "next": []},
	},
}
const FIRST_ROOM := {"Lost Mine of Phandelver": "Cave Entrance", "Dungeon of the Mad Mage": "Yawning Portal",
	"Tomb of Annihilation": "Trapped Entry", "Undercity": "Secret Entrance"}


static func venture(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, forced: String = "") -> void:
	var pid := entry.controller_id
	var ps: PlayerState = engine.state.players[pid]
	if ps.dungeon == "":
		var dname := forced
		if dname == "":
			var opts: Array = []
			for k in ["Lost Mine of Phandelver", "Dungeon of the Mad Mage", "Tomb of Annihilation"]:
				opts.append({"value": k, "label": k, "detail": " → ".join(PackedStringArray(DUNGEONS[k].keys()))})
			var ans := ex._ask(engine, entry, pid, "dungeon", "Venture into the dungeon: choose a dungeon.", opts)
			if ans.s == "paused":
				return
			dname = str(ans.value) if ans.s == "picked" else "Lost Mine of Phandelver"
		ps.dungeon = dname
		ps.dungeon_room = str(FIRST_ROOM[dname])
	else:
		var room: Dictionary = DUNGEONS[ps.dungeon][ps.dungeon_room]
		var nexts: Array = room.next
		if nexts.is_empty():
			## CR 309.6: a completed dungeon is removed; venture again starts a new one.
			ps.dungeons_completed.append(ps.dungeon)
			ps.dungeon = ""
			ps.dungeon_room = ""
			venture(ex, engine, entry, forced)
			return
		var pick := str(nexts[0])
		if nexts.size() > 1:
			var opts2: Array = []
			for nx in nexts:
				opts2.append({"value": str(nx), "label": str(nx), "detail": str(DUNGEONS[ps.dungeon][nx].text)})
			var a2 := ex._ask(engine, entry, pid, "room_%s" % ps.dungeon_room, "Venture: choose the next room.", opts2)
			if a2.s == "paused":
				return
			if a2.s == "picked":
				pick = str(a2.value)
		ps.dungeon_room = pick
	_room_ability(engine, pid, ps.dungeon, ps.dungeon_room)


## A room ability (CR 309.4c) is a triggered ability: it goes on the stack, read from the room's text.
static func _room_ability(engine: RulesEngine, pid: int, dungeon: String, room: String) -> void:
	var d := CardDefinition.new()
	d.name = room
	d.type_line = "Sorcery"
	d.oracle_text = str(DUNGEONS[dungeon][room].text)
	var abs: Array = OracleIr.translate(d)
	if abs.is_empty():
		return
	var ab: Ability = abs[0]
	var e := StackEntry.new()
	e.stack_id = engine.state.next_stack_id
	engine.state.next_stack_id += 1
	e.kind = StackEntry.Kind.TRIGGERED
	e.controller_id = pid
	e.ability_id = StringName("room_" + room.to_lower().replace(" ", "_"))
	e.effects = ab.effects.duplicate()
	e.ctx = {player_id = pid, room = room, dungeon = dungeon}
	var hostile := TargetingManager.effects_hostile(ab.effects)
	for slot in ab.targets:
		var tid := engine.targeting.auto_pick(engine, slot, 0, pid, TargetingManager.slot_hostile(slot, hostile), e.targets)
		if tid < 0:
			return
		e.targets.append(tid)
	(engine.state.stack as MagicStack).push(e)
	engine.state.log.append(EngineEnums.EventType.ABILITY_ACTIVATED, pid, {room = room, dungeon = dungeon, stack_id = e.stack_id, trigger = true})


## Taking the initiative (CR 725.2): you venture into Undercity.
static func take_initiative(engine: RulesEngine, pid: int) -> void:
	engine.state.initiative_id = pid
	var e := StackEntry.new()
	e.stack_id = engine.state.next_stack_id
	engine.state.next_stack_id += 1
	e.kind = StackEntry.Kind.TRIGGERED
	e.controller_id = pid
	e.ability_id = &"initiative"
	var fx := AbilityEffect.new()
	fx.kind = &"VENTURE"
	fx.params = {"dungeon": "Undercity"}
	e.effects = [fx]
	(engine.state.stack as MagicStack).push(e)


## The Ring tempts you (CR 701.54): choose your Ring-bearer; the Ring emblem gains abilities as it tempts you more.
static func _ring_tempts(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var options: Array = []
	var best := -1
	var best_p := -1000
	for c in _creatures_of(engine, pid):
		var co := c as GameObject
		options.append(ex._card_option(engine, co.object_id))
		if engine.power_of(co) > best_p:
			best_p = engine.power_of(co)
			best = co.object_id
	if not entry.choices.has("ring_done"):
		engine.state.players[pid].ring_level += 1
		entry.choices["ring_done"] = true
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "ring_bearer", "The Ring tempts you: choose your Ring-bearer.", options)
	if ans.s == "paused":
		return
	engine.state.players[pid].ring_bearer = int(ans.value) if ans.s == "picked" else best
	if engine.triggers != null:
		engine.triggers.fire_player_event(engine, "RING_TEMPTS", pid)


## A villainous choice (CR 701.55): the chosen player picks one of two options, then it happens.
static func _villainous(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var a: Array = p.get("a", [])
	var b: Array = p.get("b", [])
	var who := entry.controller_id
	for pl in engine.state.players:
		if pl.player_id != entry.controller_id and not pl.lost:
			who = pl.player_id
			break
	var ans := ex._ask(engine, entry, who, "villain", "Face a villainous choice:",
		[{"value": "a", "label": str(p.get("a_text", "Option A"))}, {"value": "b", "label": str(p.get("b_text", "Option B"))}])
	if ans.s == "paused":
		return
	var pick := str(ans.value) if ans.s == "picked" else "a"
	var saved_ctrl := entry.controller_id
	for raw in (a if pick == "a" else b):
		var f := AbilityEffect.new()
		f.kind = StringName(str((raw as Dictionary).get("kind", "")))
		f.params = ((raw as Dictionary).get("params", {}) as Dictionary).duplicate(true)
		ex._apply(engine, entry, source, f)
	entry.controller_id = saved_ctrl


## Time travel (CR 701.56): for each chosen permanent or suspended card with time counters, add or remove one.
static func _time_travel(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var objs: Array = []
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id == pid and int(o.counters.get("time", 0)) > 0:
			objs.append(o)
	var ex_zone: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, pid)
	for eid in ex_zone.object_ids:
		var e: GameObject = engine.state.objects.get(eid)
		if e != null and e.cast_mode == "suspend" and int(e.counters.get("time", 0)) > 0:
			objs.append(e)
	for o2 in objs:
		var obj: GameObject = o2
		var link := "tt_%d" % obj.object_id
		var ans := ex._ask(engine, entry, pid, link, "Time travel: %s has %d time counters." % [ex._name_of(engine, obj.object_id), int(obj.counters.get("time", 0))],
			[{"value": -1, "label": "Remove one"}, {"value": 1, "label": "Add one"}, {"value": 0, "label": "Leave it"}])
		if ans.s == "paused":
			return
		var d := int(ans.value) if ans.s == "picked" else -1
		obj.counters["time"] = maxi(0, int(obj.counters.get("time", 0)) + d)


## Forage (CR 701.61): exile three cards from your graveyard or sacrifice a Food. ctx.foraged says if it happened.
static func _forage(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, pid)
	var food: GameObject = null
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.controller_id == pid and _def(o) != null and _def(o).type_line.contains("Food"):
			food = o
	var options: Array = []
	if gy.object_ids.size() >= 3:
		options.append({"value": "exile", "label": "Exile three cards from your graveyard"})
	if food != null:
		options.append({"value": "food", "label": "Sacrifice a Food"})
	if options.is_empty():
		entry.ctx["foraged"] = false
		return
	var ans := ex._ask(engine, entry, pid, "forage", "Forage:", options)
	if ans.s == "paused":
		return
	var how := str(ans.value) if ans.s == "picked" else str(options[0].value)
	if how == "food":
		engine.state.zones.move(food.object_id, EngineEnums.ZoneId.GRAVEYARD, food.owner_id)
	else:
		for _i in 3:
			engine.state.zones.move(int(gy.object_ids[gy.object_ids.size() - 1]), EngineEnums.ZoneId.EXILE, pid)
	entry.ctx["foraged"] = true


## Manifest dread (CR 701.62): look at the top two, manifest one, the other goes to the graveyard.
static func _manifest_dread(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, pid)
	if lib == null or lib.object_ids.is_empty():
		return
	var top: Array = lib.object_ids.slice(0, mini(2, lib.object_ids.size()))
	var keep := int(top[0])
	if top.size() > 1:
		var options: Array = []
		for t in top:
			options.append(ex._card_option(engine, int(t)))
		var ans := ex._ask(engine, entry, pid, "dread", "Manifest dread: which card becomes a face-down 2/2?", options)
		if ans.s == "paused":
			return
		if ans.s == "picked":
			keep = int(ans.value)
	for t2 in top:
		if int(t2) != keep:
			engine.state.zones.move(int(t2), EngineEnums.ZoneId.GRAVEYARD, pid)
	lib.object_ids.erase(keep)
	lib.object_ids.push_front(keep)
	var m: GameObject = engine.state.zones.move(keep, EngineEnums.ZoneId.BATTLEFIELD, pid)
	if m != null:
		m.face_down = true
		m.cast_mode = "manifest"
	if engine.triggers != null:
		engine.triggers.fire_player_event(engine, "MANIFEST_DREAD", pid)


## Endure N (CR 701.63): N +1/+1 counters on it, or an N/N white Spirit token.
static func _endure(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var n := ex._value(engine, entry, source, p.get("n", 1))
	if n <= 0:
		return
	var on_it := source != null and source.zone == EngineEnums.ZoneId.BATTLEFIELD
	var pick := "counters" if on_it else "spirit"
	if on_it:
		var ans := ex._ask(engine, entry, entry.controller_id, "endure", "Endure %d:" % n,
			[{"value": "counters", "label": "%d +1/+1 counters on %s" % [n, ex._name_of(engine, source.object_id)]}, {"value": "spirit", "label": "A %d/%d white Spirit token" % [n, n]}])
		if ans.s == "paused":
			return
		if ans.s == "picked":
			pick = str(ans.value)
	if pick == "counters":
		_add(source, "+1/+1", n)
	else:
		_token(engine, entry.controller_id, {"subtypes": ["Spirit"], "colors": ["W"], "p": str(n), "t": str(n)})


## Airbend (CR 701.65): exile it; its owner may cast it for {2} for as long as it stays exiled.
static func _airbend(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, fx: AbilityEffect) -> void:
	for o in ex._affected(engine, entry, source, fx):
		var obj: GameObject = o
		var gone: GameObject = engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
		if gone != null and not obj.is_token:
			gone.exile_cast = "airbend"
	if engine.triggers != null:
		engine.triggers.fire_player_event(engine, "AIRBENDS", entry.controller_id)


## Earthbend N (CR 701.66): target land you control becomes a 0/0 haste land creature with N +1/+1 counters; when it
## dies or is exiled it comes back tapped.
static func _earthbend(engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var land := _target_obj(engine, entry, int(p.get("target", 0)))
	if land == null:
		return
	var eff := ContinuousEffect.new()
	eff.object_ids = [land.object_id]
	eff.until_eot = false
	eff.add_types.append("Creature")
	eff.sets_power = true
	eff.sets_toughness = true
	eff.set_power = 0
	eff.set_toughness = 0
	eff.add_keywords.append("Haste")
	eff.timestamp = engine.state.next_timestamp
	engine.state.next_timestamp += 1
	engine.state.effects.append(eff)
	land.counters["+1/+1"] = int(land.counters.get("+1/+1", 0)) + int(p.get("n", 1))
	engine.state.earthbent.append(land.object_id)
	if engine.triggers != null:
		engine.triggers.fire_player_event(engine, "EARTHBENDS", entry.controller_id)


## Awaken N (CR 702.113a): a land you control gets N +1/+1 counters and becomes a 0/0 Elemental creature with
## haste. The land is the one with no creature on it yet that you'd least miss: an untapped one first.
static func _awaken(engine: RulesEngine, entry: StackEntry, n: int) -> void:
	var pick: GameObject = null
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != entry.controller_id or not (o.definition is CardDefinition):
			continue
		if not (o.definition as CardDefinition).is_land() or engine.is_creature_now(o):
			continue
		if pick == null or (pick.tapped and not o.tapped):
			pick = o
	if pick == null:
		return
	var tmp := StackEntry.new()
	tmp.controller_id = entry.controller_id
	tmp.targets = [pick.object_id]
	_earthbend(engine, tmp, {"target": 0, "n": n})


## Blight N (CR 701.68): N -1/-1 counters on a creature you control.
static func _blight(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var pid := entry.controller_id
	var options: Array = []
	var weakest: GameObject = null
	for c in _creatures_of(engine, pid):
		var co := c as GameObject
		options.append(ex._card_option(engine, co.object_id))
		if weakest == null or engine.toughness_of(co) > engine.toughness_of(weakest):
			weakest = co
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "blight", "Blight %d: put -1/-1 counters on a creature you control." % int(p.get("n", 1)), options)
	if ans.s == "paused":
		return
	var tgt: GameObject = engine.state.objects.get(int(ans.value)) if ans.s == "picked" else weakest
	if tgt != null:
		tgt.counters["-1/-1"] = int(tgt.counters.get("-1/-1", 0)) + int(p.get("n", 1))
		entry.ctx["blighted"] = tgt.object_id
		engine.sba.check(engine)


## Recruit (CR 701.70): draw, discard; a nonland card discarded makes a 1/1 white Human Soldier.
static func _recruit(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var pid := entry.controller_id
	if not entry.choices.has("recruit_drew"):
		engine.draw_card(pid)
		entry.choices["recruit_drew"] = true
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand.object_ids.is_empty():
		return
	var options: Array = []
	for hid in hand.object_ids:
		options.append(ex._card_option(engine, int(hid)))
	var ans := ex._ask(engine, entry, pid, "recruit", "Recruit: discard a card (a nonland card makes a 1/1 Human Soldier).", options)
	if ans.s == "paused":
		return
	var pick := int(ans.value) if ans.s == "picked" else ex._cheapest_in_hand(engine, pid, [])
	var d := _def(engine.state.objects.get(pick))
	engine.discard_card(pid, pick)
	if d != null and not d.is_land():
		_token(engine, pid, {"subtypes": ["Human", "Soldier"], "colors": ["W"], "p": "1", "t": "1"})


# --- Cipher, haunt, meld, sectors, paradigm, copies -----------------------------------------------------

## Cipher (CR 702.99a): exile the spell encoded on a creature you control.
static func _cipher(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry) -> void:
	var options: Array = []
	for c in _creatures_of(engine, entry.controller_id):
		options.append(ex._card_option(engine, (c as GameObject).object_id))
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, entry.controller_id, "cipher", "Cipher: encode this spell on a creature you control?", options, true)
	if ans.s == "paused" or ans.s == "declined":
		return
	var host: GameObject = engine.state.objects.get(int(ans.value) if ans.s == "picked" else int((options[0] as Dictionary).value))
	if host == null:
		return
	entry.ctx["exile_self"] = true
	entry.ctx["cipher_host"] = host.object_id


## Haunt (CR 702.55a): exile it haunting target creature; when that creature dies the haunt ability triggers again.
static func _haunt(engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	var card: GameObject = source
	if card == null or (card.zone != EngineEnums.ZoneId.GRAVEYARD and card.zone != EngineEnums.ZoneId.STACK):
		return
	var best: GameObject = null
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and engine.is_creature_now(o) and (best == null or (o.controller_id != entry.controller_id and best.controller_id == entry.controller_id)):
			best = o
	if best == null:
		return
	if card.zone == EngineEnums.ZoneId.STACK:
		entry.ctx["exile_self"] = true
		entry.ctx["haunt_target"] = best.object_id
		return
	var gone: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.EXILE, card.owner_id)
	if gone != null:
		gone.haunting = best.object_id


## Meld (CR 701.42): exile this and its partner; the melded card (named in the text) enters.
static func _meld(engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var partner: GameObject = null
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and o.owner_id == entry.controller_id and o.controller_id == entry.controller_id and not o.is_token and _def(o) != null and _def(o).name == str(p.get("partner", "")):
			partner = o
	if partner == null:
		return
	var melded: CardDefinition = null
	if engine.cards != null:
		melded = engine.cards.definition_for(str(p.get("into", "")))
	if melded == null:
		return
	engine.state.zones.move(source.object_id, EngineEnums.ZoneId.EXILE, source.owner_id)
	engine.state.zones.move(partner.object_id, EngineEnums.ZoneId.EXILE, partner.owner_id)
	var m: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, {definition = melded, controller_id = entry.controller_id})
	if m != null:
		engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, entry.controller_id, {from_id = 0, to_id = m.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0})


## Space sculptor (CR 702.158c): each creature without a sector gets one, chosen by its controller.
static func _sector_pick(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	var opts := [{"value": "alpha", "label": "Alpha sector"}, {"value": "beta", "label": "Beta sector"}, {"value": "gamma", "label": "Gamma sector"}]
	if str(p.get("act", "")) != "":
		## A loyalty ability that names a sector: "the sector of your choice".
		var a := ex._ask(engine, entry, entry.controller_id, "sector", "Choose a sector.", opts)
		if a.s == "paused":
			return
		var chosen := str(a.value) if a.s == "picked" else _rival_sector(engine, entry.controller_id, str(p.act))
		for oid in _bf(engine):
			var o: GameObject = engine.state.objects.get(oid)
			if o == null or not engine.is_creature_now(o) or o.sector != chosen:
				continue
			if str(p.act) == "counters":
				o.counters["+1/+1"] = int(o.counters.get("+1/+1", 0)) + 1
			elif str(p.act) == "destroy":
				engine.destroy_permanent(o)
			elif str(p.act) == "same_sector_blocks":
				o.marks["blocked only by its sector"] = true
		return
	for oid2 in _bf(engine):
		var c: GameObject = engine.state.objects.get(oid2)
		if c == null or not engine.is_creature_now(c) or c.sector != "":
			continue
		var ans := ex._ask(engine, entry, c.controller_id, "sector_%d" % c.object_id, "Assign %s to a sector." % ex._name_of(engine, c.object_id), opts)
		if ans.s == "paused":
			return
		c.sector = str(ans.value) if ans.s == "picked" else ["alpha", "beta", "gamma"][c.object_id % 3]


static func _rival_sector(engine: RulesEngine, pid: int, act: String) -> String:
	var score := {"alpha": 0, "beta": 0, "gamma": 0}
	for oid in _bf(engine):
		var o: GameObject = engine.state.objects.get(oid)
		if o != null and engine.is_creature_now(o) and score.has(o.sector):
			score[o.sector] += (1 if o.controller_id == pid else -1) * (1 if act == "counters" else -1)
	var best := "alpha"
	for k in score.keys():
		if int(score[k]) > int(score[best]):
			best = str(k)
	return best


## Paradigm (CR 702.192a): at each of your precombat main phases, a copy of the card in exile you may cast free.
static func _paradigm_copy(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, p: Dictionary) -> void:
	var card: GameObject = engine.state.objects.get(int(p.get("object_id", 0)))
	if card == null or _def(card) == null:
		return
	var ans := ex._ask_yes_no(engine, entry, entry.controller_id, "paradigm", "Paradigm: cast a copy of %s without paying its mana cost?" % _def(card).name, [card.object_id])
	if ans.s == "paused" or (ans.s == "picked" and not bool(ans.value)):
		return
	var copy: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.EXILE, {definition = _def(card), is_token = true, controller_id = entry.controller_id})
	if copy != null:
		copy.may_play_controller = entry.controller_id
		engine.cast_free(entry.controller_id, copy.object_id)


## Token copies of the permanent (offspring: 1/1; squad: copies as they are).
static func _token_copies(engine: RulesEngine, entry: StackEntry, source: GameObject, n: int, one_one: bool) -> void:
	if source == null or _def(source) == null:
		return
	for _i in n:
		var d := _def(source).copy_def()
		if one_one:
			d.power = "1"
			d.toughness = "1"
		if not d.type_line.begins_with("Token"):
			d.type_line = "Token " + d.type_line
		var t: GameObject = engine.state.zones.create(entry.controller_id, EngineEnums.ZoneId.BATTLEFIELD, {definition = d, is_token = true, controller_id = entry.controller_id})
		if t != null:
			engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, entry.controller_id, {from_id = 0, to_id = t.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0})


## Recover (CR 702.59a): pay the cost to return this card from the graveyard to its owner's hand; otherwise exile it.
static func _recover(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject, p: Dictionary) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.GRAVEYARD:
		return
	var pid := source.owner_id
	var cost := ManaCost.parse(str(p.get("cost", "")))
	if engine.can_afford(pid, cost):
		var ans := ex._ask_yes_no(engine, entry, pid, "recover", "Recover: pay %s to return %s to your hand? If you don't, it is exiled." % [str(p.get("cost", "")), ex._name_of(engine, source.object_id)], [source.object_id])
		if ans.s == "paused":
			return
		var pay: bool = ans.s == "auto" or bool(ans.get("value", false))
		if pay and engine.pay_now(pid, cost):
			engine.state.zones.move(source.object_id, EngineEnums.ZoneId.HAND, pid)
			return
	engine.state.zones.move(source.object_id, EngineEnums.ZoneId.EXILE, pid)


## Aura swap (CR 702.65a): exchange this Aura with an Aura card in your hand. It has no effect if either half can't
## be done: you must own the Aura, and the one from your hand must be able to enchant what this one enchants.
static func _aura_swap(ex: AbilityExecutor, engine: RulesEngine, entry: StackEntry, source: GameObject) -> void:
	if source == null or source.zone != EngineEnums.ZoneId.BATTLEFIELD or source.attached_to == 0:
		return
	var pid := entry.controller_id
	if source.owner_id != pid:
		return
	var host: GameObject = engine.state.objects.get(source.attached_to)
	if host == null or not (host.definition is CardDefinition):
		return
	var options: Array = []
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, pid)
	if hand == null:
		return
	for hid in hand.object_ids:
		var c: GameObject = engine.state.objects.get(hid)
		if c != null and c.definition is CardDefinition and aura_can_enchant(c.definition as CardDefinition, host.definition as CardDefinition):
			options.append(ex._card_option(engine, int(hid)))
	if options.is_empty():
		return
	var ans := ex._ask(engine, entry, pid, "aura_swap", "Aura swap: choose the Aura card from your hand to put onto the battlefield.", options, true)
	if ans.s == "paused" or ans.s == "declined":
		return
	var chosen := int(ans.value) if ans.s == "picked" else int((options[0] as Dictionary).value)
	var host_id := source.attached_to
	engine.state.zones.move(source.object_id, EngineEnums.ZoneId.HAND, pid)
	var landed: GameObject = engine.state.zones.move(chosen, EngineEnums.ZoneId.BATTLEFIELD, pid)
	if landed != null:
		landed.attached_to = host_id


## True when the Aura card's "Enchant ..." line fits `host` (types only; "you control" qualifiers are ignored).
static func aura_can_enchant(aura: CardDefinition, host: CardDefinition) -> bool:
	if not aura.type_line.contains("Aura"):
		return false
	var m := RegEx.create_from_string("(?i)^enchant ([a-z ]+?)(?: you control| an opponent controls)?(?: with [^\n]*)?$")
	for raw in aura.oracle_text.split("\n"):
		var hit := m.search(str(raw).strip_edges())
		if hit == null:
			continue
		var what := hit.get_string(1).to_lower().strip_edges()
		if what == "permanent":
			return true
		for word in what.split(" or "):
			var w := str(word).strip_edges().replace("nonland ", "").replace("nonbasic ", "")
			if host.type_line.to_lower().contains(w):
				return true
		return false
	return false
