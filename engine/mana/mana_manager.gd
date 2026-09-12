class_name ManaManager
extends RefCounted

var _state_ref: WeakRef


func bind(state: GameState) -> void:
	_state_ref = weakref(state)


func on_step_end() -> void:
	var gs := _gs()
	if gs == null:
		return
	for p in gs.players:
		if p.mana is ManaPool:
			(p.mana as ManaPool).empty()


func pool(player_id: int) -> ManaPool:
	var gs := _gs()
	if gs == null or player_id < 0 or player_id >= gs.players.size():
		return null
	var m = gs.players[player_id].mana
	return m if m is ManaPool else null


func add(player_id: int, produced: ManaCost) -> void:
	var p := pool(player_id)
	if p != null:
		p.add_cost(produced)


func pay(player_id: int, cost: ManaCost) -> bool:
	var p := pool(player_id)
	if p == null:
		return cost == null or cost.is_zero()
	return p.pay(cost)


func _gs() -> GameState:
	if _state_ref == null:
		return null
	return _state_ref.get_ref() as GameState
