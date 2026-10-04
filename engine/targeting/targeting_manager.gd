class_name TargetingManager
extends RefCounted

const PLAYER_ID_BASE := 1000000
## A spell on the stack chosen by a "spell or creature" target is STACK_ID_BASE + its stack id.
const STACK_ID_BASE := 2000000


static func encode_player(player_id: int) -> int:
	return PLAYER_ID_BASE + player_id


## Picks a target for a trigger or ability when no player chooses: harmful effects go at `me`'s
## opponents (their player first, then their biggest creature), helpful ones at `me`. -1 if none.
func auto_pick(engine: RulesEngine, slot: Dictionary, source_id: int, me: int, hostile: bool, exclude: Array = []) -> int:
	var best := -1
	var best_score := -1000000
	for tid in legal_ids(engine, slot, source_id):
		if exclude.has(int(tid)):
			continue
		var sc := auto_score(engine, int(tid), me, hostile)
		if sc > best_score:
			best_score = sc
			best = int(tid)
	return best


static func auto_score(engine: RulesEngine, tid: int, me: int, hostile: bool) -> int:
	if tid >= STACK_ID_BASE and engine.state.stack is MagicStack:
		for e1 in (engine.state.stack as MagicStack).entries:
			if (e1 as StackEntry).stack_id == tid - STACK_ID_BASE:
				return 60 if ((e1 as StackEntry).controller_id != me) == hostile else -60
		return -1000
	var pid := decode_player(tid)
	if pid >= 0:
		return 50 if (pid != me) == hostile else -50
	if engine.state.stack is MagicStack:
		for e in (engine.state.stack as MagicStack).entries:
			var entry := e as StackEntry
			if entry != null and entry.stack_id == tid:
				return 60 if (entry.controller_id != me) == hostile else -60
	var obj: GameObject = engine.state.objects.get(tid)
	if obj == null:
		return -1000
	if obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		## A card in a graveyard: the most expensive one is the best to get back.
		return 10 + (obj.definition as CardDefinition).cmc if obj.definition is CardDefinition else 10
	var power := engine.power_of(obj)
	return (30 + power * 2) if (obj.controller_id != me) == hostile else (-30 + power)


## Whether a target slot is aimed at an opponent's things. A slot that names "you control" or
## "you don't control" decides for itself; otherwise `fallback` (what the effects suggest) applies.
static func slot_hostile(slot: Dictionary, fallback: bool) -> bool:
	var q: Variant = slot.get("query", {})
	if q is Dictionary:
		var ctrl := str((q as Dictionary).get("controller", ""))
		if ctrl == "OPPONENT":
			return true
		if ctrl == "SOURCE_CONTROLLER":
			return false
	return fallback


## False when any effect is clearly helpful to its target (gain life, a pump that doesn't shrink).
static func effects_hostile(effects: Array) -> bool:
	for fx in effects:
		var f := fx as AbilityEffect
		if f == null:
			continue
		if f.kind == &"GAIN_LIFE" or f.kind == &"UNTAP" or f.kind == &"PUT_COUNTER" or f.kind == &"ATTACH" or f.kind == &"RETURN_FROM_GRAVEYARD":
			return false
		if f.kind == &"PUMP" and int(f.params.get("power", 0)) >= 0 and int(f.params.get("toughness", 0)) >= 0:
			return false
		if f.kind == &"AURA_ATTACH" and bool(f.params.get("helpful", false)):
			return false
		if f.kind == &"FLICKER":
			return false
	return true


static func decode_player(target_id: int) -> int:
	if target_id < PLAYER_ID_BASE or target_id >= STACK_ID_BASE:
		return -1
	return target_id - PLAYER_ID_BASE


func legal_ids(engine: RulesEngine, query: Dictionary, source_id: int = -1) -> Array:
	var kind := str(query.get("kind", ""))
	var out: Array = []
	var src := source_id
	if src <= 0 and engine != null:
		src = engine._cast_source
	if kind == "PLAYER" or kind == "ANY_TARGET":
		## "target opponent": the source's controller is not a legal choice.
		var opponents_only := false
		var pq: Variant = query.get("query", {})
		if pq is Dictionary:
			opponents_only = bool((pq as Dictionary).get("opponent", false))
		var src_ctrl := -1
		var src_obj0: GameObject = engine.state.objects.get(src) if src > 0 else null
		if src_obj0 != null:
			src_ctrl = src_obj0.controller_id
		for i in engine.state.players.size():
			if opponents_only and i == src_ctrl:
				continue
			## "You ... have hexproof" (a player's own static): opponents' spells and abilities can't pick them.
			if i != src_ctrl and _player_hexproof(engine, i):
				continue
			out.append(encode_player(i))
		if kind == "PLAYER":
			return out
	## "Target spell or creature" (Fatehold Charm): stack entries are encoded above STACK_ID_BASE.
	if kind == "SPELL_OR_PERMANENT":
		if engine.state.stack is MagicStack:
			for e0 in (engine.state.stack as MagicStack).entries:
				var se := e0 as StackEntry
				if se != null and se.kind == StackEntry.Kind.SPELL and se.object_id != 0:
					out.append(STACK_ID_BASE + se.stack_id)
		var bf0: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		var src_o: GameObject = engine.state.objects.get(src) if src > 0 else null
		var q0: Variant = query.get("query", {})
		if bf0 != null:
			for oid0 in bf0.object_ids:
				var o0: GameObject = engine.state.objects.get(oid0)
				if o0 != null and engine.is_creature_now(o0) and (not (q0 is Dictionary) or Query._matches(o0, src_o, q0)) and not _cant_be_targeted(engine, o0, src):
					out.append(o0.object_id)
		return out
	if kind == "SPELL_ON_STACK":
		var spec: Dictionary = {}
		var qv: Variant = query.get("query", {})
		if qv is Dictionary:
			spec = qv
		if engine.state.stack is MagicStack:
			for e in (engine.state.stack as MagicStack).entries:
				var entry := e as StackEntry
				if entry == null or entry.kind != StackEntry.Kind.SPELL:
					continue
				if not spec.is_empty():
					var spell: GameObject = engine.state.objects.get(entry.object_id)
					if spell == null or not Query._matches(spell, null, spec):
						continue
				out.append(entry.stack_id)
	elif kind == "PERMANENT":
		var src_obj: GameObject = engine.state.objects.get(src) if src > 0 else null
		var q: Dictionary = query.get("query", {})
		if not (q is Dictionary):
			q = {}
		var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf == null:
			return out
		for oid in bf.object_ids:
			var obj: GameObject = engine.state.objects.get(oid)
			if obj != null and Query._matches(obj, src_obj, q) and not _cant_be_targeted(engine, obj, src):
				out.append(obj.object_id)
	elif kind == "CARD_IN_ZONE":
		## A card in a graveyard (or other non-shared zone), e.g. "target creature card from your graveyard".
		var cq: Dictionary = query.get("query", {})
		if not (cq is Dictionary):
			cq = {}
		var zid := Query._zone_id(str(cq.get("zone", "GRAVEYARD")))
		var src_card: GameObject = engine.state.objects.get(src) if src > 0 else null
		for pid in engine.state.players.size():
			var zone: Zone = engine.state.zones.get_zone(zid, pid)
			if zone == null:
				continue
			for coid in zone.object_ids:
				var card: GameObject = engine.state.objects.get(coid)
				if card != null and Query._matches(card, src_card, cq):
					out.append(card.object_id)
	elif kind == "ANY_TARGET":
		var bf2: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
		if bf2 != null:
			for oid2 in bf2.object_ids:
				var creature: GameObject = engine.state.objects.get(oid2)
				if creature == null or not (creature.definition is CardDefinition):
					continue
				if not engine.is_creature_now(creature) and not engine.is_planeswalker_now(creature):
					continue
				## "target opponent or planeswalker": players and planeswalkers, not creatures.
				var any_q: Variant = query.get("query", {})
				if any_q is Dictionary and bool((any_q as Dictionary).get("pw_only", false)) and not engine.is_planeswalker_now(creature):
					continue
				if _cant_be_targeted(engine, creature, src):
					continue
				out.append(creature.object_id)
	return out


func is_legal(engine: RulesEngine, query: Dictionary, target_id: int, source_id: int = -1) -> bool:
	return legal_ids(engine, query, source_id).has(target_id)


## Hexproof stops opponents. Shroud stops everyone. Ward is a triggered ability, not an illegal target.
## Protection here covers "protection from {color}" against the source's colors (CR 702.16).
func _cant_be_targeted(engine: RulesEngine, obj: GameObject, source_id: int) -> bool:
	if obj == null or engine == null or engine.layers == null:
		return false
	var kws: Variant = engine.layers.snapshot(engine.state, obj).get("keywords", PackedStringArray())
	if not (kws is PackedStringArray):
		return false
	var src: GameObject = engine.state.objects.get(source_id) if source_id > 0 else null
	for kw in kws:
		var low := str(kw).to_lower()
		if low == "shroud":
			return true
		if low == "hexproof":
			if src != null and src.controller_id != obj.controller_id:
				return true
	## Protection from a color (CR 702.16b), from the card's own keyword line or a granted keyword.
	if src != null and engine.protected_from(obj, src):
		return true
	return false


func _protection_matches(keyword: String, source: GameObject) -> bool:
	if source == null or not (source.definition is CardDefinition):
		return false
	var quality := keyword.trim_prefix("protection from ").strip_edges()
	var letter := ""
	match quality:
		"white":
			letter = "W"
		"blue":
			letter = "U"
		"black":
			letter = "B"
		"red":
			letter = "R"
		"green":
			letter = "G"
		_:
			return false
	return (source.definition as CardDefinition).colors.has(letter)


func _player_hexproof(engine: RulesEngine, pid: int) -> bool:
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var o: GameObject = engine.state.objects.get(oid)
		if o == null or o.controller_id != pid or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("player_hexproof"):
				return true
	return false
