extends RefCounted

## Chooses blocks for a bot defender. Reads keywords and power/toughness, never card names.
##
## Order of preference for each attacker (biggest attackers first):
##   1. a block that kills the attacker and survives, or one that simply survives;
##   2. an even-or-better trade (blocker worth no more power than the attacker);
##   3. chump blocks, only while the unblocked damage would be lethal.
## Menace attackers are left alone unless chumping is forced (two blockers are spent).


## Returns {attacker_id: [blocker ids]} ready for a DECLARE_BLOCKERS action.
static func choose(engine: RulesEngine, defender_id: int) -> Dictionary:
	var out := {}
	if engine == null or not (engine.state.combat is CombatState):
		return out
	var cs := engine.state.combat as CombatState
	var attackers: Array = []
	for aid in cs.attacker_ids:
		var atk: GameObject = engine.state.objects.get(int(aid))
		if atk == null or atk.zone != EngineEnums.ZoneId.BATTLEFIELD:
			continue
		if engine.defender_of(int(aid)) != defender_id:
			continue
		attackers.append(atk)
	if attackers.is_empty():
		return out
	attackers.sort_custom(func(x: GameObject, y: GameObject) -> bool:
		return threat(engine, x) > threat(engine, y)
	)
	var used := {}
	var incoming := 0
	for atk in attackers:
		incoming += threat(engine, atk)

	# 1. Good blocks.
	for atk in attackers:
		if engine.has_keyword(atk, "Menace"):
			continue
		var best: GameObject = null
		var best_score := 0
		for blk in _untapped_creatures(engine, defender_id):
			if used.has(blk.object_id) or not engine.can_block_attacker(blk.object_id, atk.object_id):
				continue
			var res := outcome(engine, atk, blk)
			var score := 0
			if res.attacker_dies and not res.blocker_dies:
				score = 3
			elif not res.blocker_dies:
				score = 2
			## Prefer the smallest blocker that does the job.
			if score > best_score or (score == best_score and score > 0 and best != null and engine.power_of(blk) < engine.power_of(best)):
				best = blk
				best_score = score
		if best != null:
			_assign(out, used, atk, [best])
			incoming -= _prevented(engine, atk, [best])

	# 2. Trades.
	for atk in attackers:
		if out.has(atk.object_id) or engine.has_keyword(atk, "Menace"):
			continue
		for blk in _untapped_creatures(engine, defender_id):
			if used.has(blk.object_id) or not engine.can_block_attacker(blk.object_id, atk.object_id):
				continue
			var res := outcome(engine, atk, blk)
			if res.attacker_dies and engine.power_of(blk) <= engine.power_of(atk):
				_assign(out, used, atk, [blk])
				incoming -= _prevented(engine, atk, [blk])
				break

	# 3. Chump only to survive.
	var life := int(engine.state.players[defender_id].life)
	for atk in attackers:
		if incoming < life:
			break
		if out.has(atk.object_id):
			continue
		var need := 2 if engine.has_keyword(atk, "Menace") else 1
		var picks: Array = []
		for blk in _weakest_first(engine, _untapped_creatures(engine, defender_id)):
			if used.has(blk.object_id) or not engine.can_block_attacker(blk.object_id, atk.object_id):
				continue
			picks.append(blk)
			if picks.size() == need:
				break
		if picks.size() == need:
			_assign(out, used, atk, picks)
			incoming -= _prevented(engine, atk, picks)
	return out


## Damage this attacker deals to the player if unblocked.
static func threat(engine: RulesEngine, atk: GameObject) -> int:
	var p := maxi(0, engine.power_of(atk))
	return p * 2 if engine.has_keyword(atk, "Double strike") else p


## Who dies in a one-on-one block, honouring first strike, deathtouch and indestructible.
static func outcome(engine: RulesEngine, atk: GameObject, blk: GameObject) -> Dictionary:
	var a_first := _strikes_first(engine, atk)
	var b_first := _strikes_first(engine, blk)
	var a_kills := kills(engine, atk, blk)
	var b_kills := kills(engine, blk, atk)
	var attacker_dies := b_kills
	var blocker_dies := a_kills
	if a_first and not b_first:
		attacker_dies = b_kills and not a_kills
	elif b_first and not a_first:
		blocker_dies = a_kills and not b_kills
	return {attacker_dies = attacker_dies, blocker_dies = blocker_dies}


static func kills(engine: RulesEngine, src: GameObject, dst: GameObject) -> bool:
	var p := engine.power_of(src)
	if p <= 0 or engine.has_keyword(dst, "Indestructible"):
		return false
	if engine.has_keyword(src, "Deathtouch"):
		return true
	var hits := 2 if engine.has_keyword(src, "Double strike") else 1
	return p * hits >= engine.toughness_of(dst) - dst.damage_marked


static func _strikes_first(engine: RulesEngine, obj: GameObject) -> bool:
	return engine.has_keyword(obj, "First strike") or engine.has_keyword(obj, "Double strike")


## How much player damage a block stops (trample still pushes the excess through).
static func _prevented(engine: RulesEngine, atk: GameObject, blockers: Array) -> int:
	var full := threat(engine, atk)
	if not engine.has_keyword(atk, "Trample"):
		return full
	var soak := 0
	for blk in blockers:
		soak += maxi(0, engine.toughness_of(blk) - (blk as GameObject).damage_marked)
	return mini(full, soak)


static func _assign(out: Dictionary, used: Dictionary, atk: GameObject, blockers: Array) -> void:
	var ids: Array = []
	for blk in blockers:
		ids.append((blk as GameObject).object_id)
		used[(blk as GameObject).object_id] = true
	out[atk.object_id] = ids


static func _untapped_creatures(engine: RulesEngine, player_id: int) -> Array:
	var out: Array = []
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return out
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		if obj == null or obj.controller_id != player_id or obj.tapped:
			continue
		if engine.is_creature_now(obj):
			out.append(obj)
	return out


static func _weakest_first(engine: RulesEngine, objs: Array) -> Array:
	var sorted := objs.duplicate()
	sorted.sort_custom(func(x: GameObject, y: GameObject) -> bool:
		return engine.power_of(x) + engine.toughness_of(x) < engine.power_of(y) + engine.toughness_of(y)
	)
	return sorted


## Which of the bot's legal attackers to send at defender_id.
## A creature attacks unless some untapped defender could block it, kill it and survive.
## If everything together is lethal against an open board, it all goes in.
static func choose_attackers(engine: RulesEngine, player_id: int, defender_id: int) -> Array:
	var legal: Array = engine.legal_attacker_ids(player_id)
	var blockers := _untapped_creatures(engine, defender_id)
	var out: Array = []
	var total := 0
	for raw in legal:
		var atk: GameObject = engine.state.objects.get(int(raw))
		if atk == null:
			continue
		total += threat(engine, atk)
		var eaten := false
		for blk in blockers:
			if not engine.can_block_as(blk.object_id, defender_id, atk.object_id):
				continue
			var res := outcome(engine, atk, blk)
			if res.attacker_dies and not res.blocker_dies:
				eaten = true
				break
		if not eaten:
			out.append(atk.object_id)
	if blockers.is_empty() and total >= int(engine.state.players[defender_id].life):
		return legal.duplicate()
	return out
