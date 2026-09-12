class_name SbaManager
extends RefCounted

func check(engine: RulesEngine) -> bool:
	var st := engine.state
	_check_life(st)
	_check_commander_damage(st)
	_check_legend(engine)
	_check_game_over(st)
	return st.mode == EngineEnums.EngineMode.CHOOSING_SBA or st.ended


func _check_commander_damage(st: GameState) -> void:
	var need := st.rules.commander_damage_to_lose if st.rules else 21
	for p in st.players:
		for k in p.commander_damage_from.keys():
			if int(p.commander_damage_from[k]) >= need:
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


func _check_life(st: GameState) -> void:
	for p in st.players:
		if p.life <= 0:
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
