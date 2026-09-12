class_name PriorityManager
extends RefCounted

func give(state: GameState, player_id: int) -> void:
	state.mode = EngineEnums.EngineMode.GIVING_PRIORITY
	state.priority_player_id = player_id
	state.awaiting = {player_id = player_id, type = &"priority"}
	state.log.append(EngineEnums.EventType.PRIORITY, player_id, {})


func note_action(state: GameState, player_id: int) -> void:
	state.passed_since_action.clear()
	state.priority_player_id = player_id
	if state.mode == EngineEnums.EngineMode.GIVING_PRIORITY:
		state.awaiting = {player_id = player_id, type = &"priority"}


func pass_from(state: GameState, player_id: int) -> bool:
	if not state.passed_since_action.has(player_id):
		state.passed_since_action.append(player_id)
	if state.passed_since_action.size() >= state.players.size():
		state.passed_since_action.clear()
		return true
	var nxt := next_apnap(state, player_id)
	give(state, nxt)
	return false


func next_apnap(state: GameState, from_id: int) -> int:
	var n := state.players.size()
	if n <= 0:
		return 0
	return (from_id + 1) % n


func submit_pass(engine: RulesEngine, action: GameAction) -> SubmitResult:
	var r := SubmitResult.new()
	r.ok = false
	var st := engine.state
	if st.mode != EngineEnums.EngineMode.GIVING_PRIORITY:
		r.error = "not in priority"
		return r
	if action.player_id != int(st.awaiting.get("player_id", -1)):
		r.error = "not your priority"
		return r
	var wrapped := pass_from(st, action.player_id)
	if wrapped:
		engine.turn.all_passed()
	r.ok = true
	return r
