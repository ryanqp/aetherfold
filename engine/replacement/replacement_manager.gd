class_name ReplacementManager
extends RefCounted

func rewrite(state: GameState, obj: GameObject, dest_zone: int) -> int:
	if obj == null or not obj.is_commander:
		return dest_zone
	if dest_zone != EngineEnums.ZoneId.GRAVEYARD and dest_zone != EngineEnums.ZoneId.EXILE:
		return dest_zone
	if state.mode == EngineEnums.EngineMode.CHOOSING_REPLACEMENT:
		return dest_zone
	state.mode = EngineEnums.EngineMode.CHOOSING_REPLACEMENT
	state.awaiting = {
		player_id = obj.owner_id,
		type = &"replacement",
		object_id = obj.object_id,
		from_zone = obj.zone,
		proposed = dest_zone,
		options = [EngineEnums.ZoneId.COMMAND, dest_zone],
	}
	return -1


func apply_choice(engine: RulesEngine, player_id: int, dest_zone: int) -> bool:
	var st := engine.state
	if st.mode != EngineEnums.EngineMode.CHOOSING_REPLACEMENT:
		return false
	if int(st.awaiting.get("player_id", -1)) != player_id:
		return false
	var options: Array = st.awaiting.get("options", [])
	if not options.has(dest_zone):
		return false
	var oid := int(st.awaiting.get("object_id", 0))
	st.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	engine.priority.give(st, st.active_player_id)
	if oid != 0:
		var dest_owner := player_id if dest_zone == EngineEnums.ZoneId.COMMAND else EngineIds.NONE
		engine.state.zones.move(oid, dest_zone, dest_owner, true)
	return true


func submit(engine: RulesEngine, action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	var dest := int(action.extra.get("dest_zone", EngineEnums.ZoneId.COMMAND))
	if not apply_choice(engine, action.player_id, dest):
		r.error = "illegal replacement"
		return r
	r.ok = true
	return r


func legal_actions(state: GameState, player_id: int) -> Array:
	var out: Array = []
	if int(state.awaiting.get("player_id", -1)) != player_id:
		return out
	var options: Array = state.awaiting.get("options", [])
	for dest in options:
		var a := GameAction.new()
		a.kind = GameAction.Kind.CHOOSE_REPLACEMENT
		a.player_id = player_id
		a.object_id = int(state.awaiting.get("object_id", 0))
		a.extra = {dest_zone = int(dest)}
		out.append(a)
	return out
