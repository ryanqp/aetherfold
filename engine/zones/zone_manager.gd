class_name ZoneManager
extends RefCounted

## Owns CR zone lists. `move()` retires the old object id (CR 400.7).

var _state_ref: WeakRef
var _shared: Dictionary = {}
var _player_zones: Array = []


static func is_shared(zone_id: int) -> bool:
	return zone_id == EngineEnums.ZoneId.BATTLEFIELD or zone_id == EngineEnums.ZoneId.STACK


func bind(state: GameState) -> void:
	_state_ref = weakref(state)


func setup(player_count: int) -> void:
	_shared = {}
	_player_zones = []
	_shared[EngineEnums.ZoneId.BATTLEFIELD] = _make(
		EngineEnums.ZoneId.BATTLEFIELD, EngineIds.NONE, true
	)
	_shared[EngineEnums.ZoneId.STACK] = _make(
		EngineEnums.ZoneId.STACK, EngineIds.NONE, true
	)
	for p in player_count:
		var d := {}
		d[EngineEnums.ZoneId.LIBRARY] = _make(EngineEnums.ZoneId.LIBRARY, p, true)
		d[EngineEnums.ZoneId.HAND] = _make(EngineEnums.ZoneId.HAND, p, false)
		d[EngineEnums.ZoneId.GRAVEYARD] = _make(EngineEnums.ZoneId.GRAVEYARD, p, true)
		d[EngineEnums.ZoneId.EXILE] = _make(EngineEnums.ZoneId.EXILE, p, false)
		d[EngineEnums.ZoneId.COMMAND] = _make(EngineEnums.ZoneId.COMMAND, p, false)
		_player_zones.append(d)


func get_zone(zone_id: int, player_id: int = EngineIds.NONE) -> Zone:
	if is_shared(zone_id):
		return _shared.get(zone_id) as Zone
	if player_id < 0 or player_id >= _player_zones.size():
		return null
	return _player_zones[player_id].get(zone_id) as Zone


func create(owner_id: int, zone_id: int, opts: Dictionary = {}) -> GameObject:
	var gs := _gs()
	if gs == null:
		return null
	if owner_id < 0 or owner_id >= gs.players.size():
		return null
	var zone := get_zone(zone_id, owner_id)
	if zone == null:
		return null
	var obj := GameObject.new()
	obj.object_id = gs.next_object_id
	gs.next_object_id += 1
	obj.owner_id = owner_id
	obj.controller_id = int(opts.get("controller_id", owner_id))
	obj.zone = zone_id
	obj.definition = opts.get("definition", null)
	obj.timestamp = gs.next_timestamp
	gs.next_timestamp += 1
	obj.linked_from = EngineIds.NONE
	obj.instance_uuid = str(opts.get("instance_uuid", ""))
	if obj.instance_uuid == "":
		obj.instance_uuid = "o%d" % obj.object_id
	obj.face_id = int(opts.get("face_id", 0))
	obj.is_token = bool(opts.get("is_token", false))
	obj.is_commander = bool(opts.get("is_commander", false))
	obj.tapped = bool(opts.get("tapped", false))
	if zone_id == EngineEnums.ZoneId.BATTLEFIELD and not opts.has("tapped"):
		obj.tapped = _etb_tapped(obj.definition)
	obj.summoned_this_turn = bool(opts.get(
		"summoned_this_turn", zone_id == EngineEnums.ZoneId.BATTLEFIELD
	))
	obj.damage_marked = int(opts.get("damage_marked", 0))
	var counters = opts.get("counters", {})
	obj.counters = counters if counters is Dictionary else {}
	gs.objects[obj.object_id] = obj
	_insert(zone, obj.object_id)
	_add_commander_id(obj)
	return obj


func move(object_id: int, dest_zone: int, dest_owner: int = EngineIds.NONE, skip_replacement: bool = false) -> GameObject:
	var gs := _gs()
	if gs == null or not gs.objects.has(object_id):
		return null
	var old: GameObject = gs.objects[object_id]
	if not skip_replacement and gs.replacement != null and gs.replacement.has_method("rewrite"):
		var rewritten: int = gs.replacement.rewrite(gs, old, dest_zone)
		if rewritten < 0:
			return null
		dest_zone = rewritten
	var src := get_zone(old.zone, old.owner_id)
	var dest_player := dest_owner
	if not is_shared(dest_zone) and dest_player == EngineIds.NONE:
		dest_player = old.owner_id
	var dst := get_zone(dest_zone, dest_player)
	if src == null or dst == null:
		return null
	if old.zone == dest_zone and src == dst:
		return old
	src.object_ids.erase(object_id)
	_detach_from_hosts(object_id)
	_drop_commander_id(old)
	if old.is_token and dest_zone != EngineEnums.ZoneId.BATTLEFIELD:
		gs.objects.erase(object_id)
		var ceased := gs.log.append(EngineEnums.EventType.ZONE_CHANGE, old.owner_id, {
			from_id = old.object_id,
			to_id = EngineIds.NONE,
			from_zone = old.zone,
			to_zone = dest_zone,
			linked_from = old.object_id,
		})
		ceased.object_ids.append(old.object_id)
		return null
	var new_obj := GameObject.new()
	new_obj.object_id = gs.next_object_id
	gs.next_object_id += 1
	new_obj.owner_id = old.owner_id
	if is_shared(dest_zone):
		new_obj.controller_id = old.controller_id if dest_owner == EngineIds.NONE else dest_owner
	else:
		new_obj.controller_id = dest_player
	new_obj.zone = dest_zone
	new_obj.definition = old.definition
	new_obj.timestamp = gs.next_timestamp
	gs.next_timestamp += 1
	new_obj.linked_from = old.object_id
	new_obj.instance_uuid = old.instance_uuid
	new_obj.face_id = old.face_id
	new_obj.is_token = old.is_token
	new_obj.is_commander = old.is_commander
	new_obj.tapped = dest_zone == EngineEnums.ZoneId.BATTLEFIELD and _etb_tapped(old.definition)
	new_obj.summoned_this_turn = dest_zone == EngineEnums.ZoneId.BATTLEFIELD
	new_obj.damage_marked = 0
	gs.objects.erase(object_id)
	gs.objects[new_obj.object_id] = new_obj
	_insert(dst, new_obj.object_id)
	_add_commander_id(new_obj)
	var ev := gs.log.append(EngineEnums.EventType.ZONE_CHANGE, new_obj.owner_id, {
		from_id = old.object_id,
		to_id = new_obj.object_id,
		from_zone = old.zone,
		to_zone = dest_zone,
		linked_from = old.object_id,
	})
	ev.object_ids.append(old.object_id)
	ev.object_ids.append(new_obj.object_id)
	return new_obj


func _etb_tapped(definition) -> bool:
	return definition is CardDefinition and (definition as CardDefinition).enters_tapped()


func _gs() -> GameState:
	if _state_ref == null:
		return null
	return _state_ref.get_ref() as GameState


func _make(zone_id: int, owner_id: int, ordered: bool) -> Zone:
	var z := Zone.new()
	z.zone_id = zone_id
	z.owner_id = owner_id
	z.ordered = ordered
	return z


func _insert(zone: Zone, object_id: int) -> void:
	# Index 0 is the top of ordered piles (library, graveyard).
	if zone.zone_id == EngineEnums.ZoneId.LIBRARY or zone.zone_id == EngineEnums.ZoneId.GRAVEYARD:
		zone.object_ids.insert(0, object_id)
	else:
		zone.object_ids.append(object_id)


func _detach_from_hosts(retired_id: int) -> void:
	var gs := _gs()
	var bf := get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if gs == null or bf == null:
		return
	for hid in bf.object_ids:
		var host: GameObject = gs.objects.get(hid)
		if host != null:
			host.attachments.erase(retired_id)


func _add_commander_id(obj: GameObject) -> void:
	if not obj.is_commander:
		return
	if obj.zone != EngineEnums.ZoneId.COMMAND and obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var gs := _gs()
	if gs == null or obj.owner_id < 0 or obj.owner_id >= gs.players.size():
		return
	var ids := gs.players[obj.owner_id].commander_ids
	if not ids.has(obj.object_id):
		ids.append(obj.object_id)


func _drop_commander_id(obj: GameObject) -> void:
	if not obj.is_commander:
		return
	var gs := _gs()
	if gs == null or obj.owner_id < 0 or obj.owner_id >= gs.players.size():
		return
	gs.players[obj.owner_id].commander_ids.erase(obj.object_id)
