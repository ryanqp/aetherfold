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
			## Leyline Tyrant: "You don't lose unspent red mana as steps and phases end."
			var kept_red := (p.mana as ManaPool).r if _keeps_red(gs, p.player_id) else 0
			(p.mana as ManaPool).empty()
			(p.mana as ManaPool).r = kept_red
	## Firebending (CR 702.189a): its {R} stays until end of combat. Unspent, it comes back after each combat step.
	if gs.step == EngineEnums.Step.END_COMBAT:
		gs.combat_mana.clear()
	else:
		for pid in gs.combat_mana.keys():
			var keep := int(gs.combat_mana[pid])
			var pl := pool(int(pid))
			if pl != null and keep > 0:
				pl.r += keep


func _keeps_red(gs: GameState, player_id: int) -> bool:
	var bf: Zone = gs.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD) if gs.zones != null else null
	if bf == null:
		return false
	for oid in bf.object_ids:
		var o: GameObject = gs.objects.get(oid)
		if o == null or o.controller_id != player_id or not (o.definition is CardDefinition):
			continue
		for a in (o.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab != null and ab.kind == &"STATIC" and str(ab.static_spec.get("keep_mana", "")) == "R":
				return true
	return false


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
