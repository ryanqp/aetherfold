class_name SbaManager
extends RefCounted

func check(engine: RulesEngine) -> bool:
	var st := engine.state
	_check_creatures(engine)
	_check_planeswalkers(engine)
	_check_auras(engine)
	_check_sagas(engine)
	if engine.kw != null:
		engine.kw.update_speed()
		engine.kw.sync_day_night()
	_check_storied(engine)
	_check_life(st)
	_check_commander_damage(st)
	_check_legend(engine)
	_check_game_over(st)
	return st.mode == EngineEnums.EngineMode.CHOOSING_SBA or st.ended


## Storied (CR 702.195a): with a storied permanent, three or more artifacts, Sagas and/or legendary permanents you
## control give you an enduring story for the rest of the game.
func _check_storied(engine: RulesEngine) -> void:
	var st := engine.state
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for p in st.players:
		if p.enduring_story:
			continue
		var has_storied := false
		var count := 0
		for oid in bf.object_ids:
			var o: GameObject = st.objects.get(oid)
			if o == null or o.controller_id != p.player_id or not (o.definition is CardDefinition):
				continue
			var def := o.definition as CardDefinition
			if def.kw().has("storied"):
				has_storied = true
			if def.type_line.contains("Artifact") or def.type_line.contains("Saga") or def.type_line.contains("Legendary"):
				count += 1
		if has_storied and count >= 3:
			p.enduring_story = true


func _check_commander_damage(st: GameState) -> void:
	var need := st.rules.commander_damage_to_lose if st.rules else 21
	for p in st.players:
		for k in p.commander_damage_from.keys():
			if int(p.commander_damage_from[k]) >= need and not _cant_lose(st, p):
				p.lost = true


func apply_choose(engine: RulesEngine, player_id: int, keep_id: int) -> bool:
	var st := engine.state
	if st.mode != EngineEnums.EngineMode.CHOOSING_SBA:
		return false
	if int(st.awaiting.get("player_id", -1)) != player_id:
		return false
	var ids: Array = st.awaiting.get("object_ids", [])
	if not ids.has(keep_id):
		return false
	for oid in ids:
		if int(oid) == keep_id:
			continue
		var obj: GameObject = st.objects.get(int(oid))
		if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
			st.zones.move(int(oid), EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
	st.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	engine.priority.give(st, st.active_player_id)
	check(engine)
	return true


## CR 704.5f: toughness 0 or less goes to the graveyard (indestructible does not help).
## CR 704.5g / 704.5h: lethal damage, or any damage from a deathtouch source, destroys it
## unless it has indestructible (CR 702.12b).
func _check_creatures(engine: RulesEngine) -> void:
	var st := engine.state
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	var doomed: Array[int] = []
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj == null or not engine.is_creature_now(obj):
			continue
		var toughness := engine.toughness_of(obj)
		if toughness <= 0:
			## A printed "*" toughness reads as 0 until its defining ability is in the engine.
			## Keep those creatures alive instead of killing them on arrival.
			var printed_star: bool = obj.definition is CardDefinition and not (obj.definition as CardDefinition).toughness.is_valid_int()
			if printed_star:
				continue
			doomed.append(obj.object_id)
			continue
		if obj.damage_marked <= 0:
			continue
		var lethal := obj.damage_marked >= toughness or obj.deathtouch_damage
		if lethal and not engine.has_keyword(obj, "Indestructible"):
			doomed.append(obj.object_id)
	for oid in doomed:
		var obj: GameObject = st.objects.get(oid)
		if obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
			## Toughness 0 or less isn't destruction (CR 704.5f); lethal damage is, so regeneration applies (CR 704.5g).
			if engine.toughness_of(obj) <= 0:
				st.zones.move(oid, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
			else:
				engine.destroy_permanent(obj)


func _check_life(st: GameState) -> void:
	for p in st.players:
		if (p.life <= 0 or p.poison >= 10) and not _cant_lose(st, p):
			p.lost = true


func _check_legend(engine: RulesEngine) -> void:
	var st := engine.state
	if st.mode == EngineEnums.EngineMode.CHOOSING_SBA:
		return
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	var by_key := {}
	for oid in bf.object_ids:
		var obj: GameObject = st.objects.get(oid)
		if obj == null or obj.definition == null or not (obj.definition is CardDefinition):
			continue
		var def := obj.definition as CardDefinition
		if not def.type_line.contains("Legendary"):
			continue
		var key := "%d|%s" % [obj.controller_id, def.name]
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(obj.object_id)
	for key in by_key.keys():
		var group: Array = by_key[key]
		if group.size() < 2:
			continue
		var controller := int(str(key).get_slice("|", 0))
		st.mode = EngineEnums.EngineMode.CHOOSING_SBA
		st.awaiting = {
			player_id = controller,
			type = &"legend",
			object_ids = group,
		}
		return


func _check_game_over(st: GameState) -> void:
	var alive: Array[int] = []
	for p in st.players:
		if not p.lost:
			alive.append(p.player_id)
	if alive.size() <= 1 and st.players.size() > 1:
		st.ended = true
		st.winners = alive
		st.mode = EngineEnums.EngineMode.GAME_OVER
		st.log.append(EngineEnums.EventType.GAME_OVER, 0, {winners = alive})


## CR 704.5i: a planeswalker with no loyalty counters goes to its owner's graveyard.
func _check_planeswalkers(engine: RulesEngine) -> void:
	var st := engine.state
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids.duplicate():
		var obj: GameObject = st.objects.get(oid)
		if obj == null or obj.face_down or not (obj.definition is CardDefinition):
			continue
		if not str(engine.layers.snapshot(st, obj).get("type_line", "")).contains("Planeswalker"):
			continue
		if int(obj.counters.get("loyalty", 0)) <= 0:
			st.zones.move(oid, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


## CR 704.5m: an Aura that isn't attached to anything (what it enchanted left) goes to its owner's graveyard.
## It remembers what it was on, for "when enchanted creature dies" (Angelic Destiny).
func _check_auras(engine: RulesEngine) -> void:
	var st := engine.state
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids.duplicate():
		var obj: GameObject = st.objects.get(oid)
		if obj == null or obj.face_down or not (obj.definition is CardDefinition):
			continue
		var host: GameObject = st.objects.get(obj.attached_to) if obj.attached_to != 0 else null
		## Bestow (CR 702.103e): an Aura whose creature left becomes an enchantment creature again and stays.
		if obj.bestowed:
			if host == null or host.zone != EngineEnums.ZoneId.BATTLEFIELD:
				obj.bestowed = false
				obj.attached_to = 0
				obj.summoned_this_turn = false
			continue
		if not (obj.definition as CardDefinition).type_line.contains("Aura"):
			continue
		if host != null and host.zone == EngineEnums.ZoneId.BATTLEFIELD:
			continue
		var was_on := obj.attached_to
		var moved: GameObject = st.zones.move(oid, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)
		if moved != null:
			moved.aura_host_left = was_on


## CR 714.4: a Saga whose lore counters reached its final chapter, with no chapter ability of it still on the
## stack, is sacrificed.
func _check_sagas(engine: RulesEngine) -> void:
	var st := engine.state
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for oid in bf.object_ids.duplicate():
		var obj: GameObject = st.objects.get(oid)
		if obj == null or obj.face_down or not (obj.definition is CardDefinition):
			continue
		var def := obj.definition as CardDefinition
		if not def.type_line.contains("Saga"):
			continue
		var last := def.saga_final_chapter()
		if last <= 0 or int(obj.counters.get("lore", 0)) < last:
			continue
		var waiting := false
		for e in (st.stack as MagicStack).entries:
			if (e as StackEntry).source_id == obj.object_id:
				waiting = true
				break
		if not waiting:
			st.zones.move(oid, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


## "You can't lose the game and your opponents can't win the game." (Herald of Eternal Dawn, Platinum Angel).
func _cant_lose(st: GameState, p: PlayerState) -> bool:
	var bf: Zone = st.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return false
	for oid in bf.object_ids:
		var o: GameObject = st.objects.get(oid)
		if o == null or o.controller_id != p.player_id or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and ab.static_spec.has("cant_lose"):
				return true
	return false
