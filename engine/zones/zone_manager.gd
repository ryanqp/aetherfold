class_name ZoneManager
extends RefCounted

## Owns CR zone lists. `move()` retires the old object id (CR 400.7).

var _state_ref: WeakRef
var _shared: Dictionary = {}
var _player_zones: Array = []
## Optional: Callable(obj) -> {power, toughness} read just before a permanent leaves (last known information).
var lki_fn: Callable = Callable()


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
		obj.tapped = _etb_tapped(obj.definition, owner_id)
	obj.summoned_this_turn = bool(opts.get(
		"summoned_this_turn", zone_id == EngineEnums.ZoneId.BATTLEFIELD
	))
	obj.damage_marked = int(opts.get("damage_marked", 0))
	var counters = opts.get("counters", {})
	obj.counters = counters if counters is Dictionary else {}
	gs.objects[obj.object_id] = obj
	_insert(zone, obj.object_id)
	_add_commander_id(obj)
	if zone_id == EngineEnums.ZoneId.BATTLEFIELD:
		_on_enter(gs, obj)
	return obj


## What a permanent has as it enters (CR 614.12-style "enters with"): a planeswalker's loyalty counters
## (CR 306.5b), an impending permanent's time counters (CR 702.176a), and the count of nonland permanents
## that entered under each player's control this turn (celebration).
func _on_enter(gs: GameState, obj: GameObject) -> void:
	if not (obj.definition is CardDefinition):
		return
	var def := obj.definition as CardDefinition
	if def.type_line.contains("Planeswalker") and not obj.counters.has("loyalty") and not obj.face_down:
		obj.counters["loyalty"] = int(def.loyalty) if def.loyalty.is_valid_int() else 0
	if obj.cast_mode == "impending" and def.kw().has("impending"):
		obj.counters["time"] = int(def.kw().impending.n)
	if not def.is_land() and obj.controller_id >= 0 and obj.controller_id < gs.players.size():
		gs.players[obj.controller_id].nonland_entered_this_turn += 1
	_enters_with_extra(gs, obj)
	for c in enters_with_counters(def):
		var add_n: int = obj.x_paid if bool(c.get("x", false)) else int(c.n)
		obj.counters[str(c.name)] = int(obj.counters.get(str(c.name), 0)) + add_n


func move(object_id: int, dest_zone: int, dest_owner: int = EngineIds.NONE, skip_replacement: bool = false) -> GameObject:
	var gs := _gs()
	if gs == null or not gs.objects.has(object_id):
		return null
	var old: GameObject = gs.objects[object_id]
	## Finality counter (CR 122.1g): a permanent with one that would go to a graveyard from the battlefield is exiled instead.
	if dest_zone == EngineEnums.ZoneId.GRAVEYARD and old.zone == EngineEnums.ZoneId.BATTLEFIELD and int(old.counters.get("finality", 0)) > 0:
		dest_zone = EngineEnums.ZoneId.EXILE
	## Unearth (CR 702.84a) and disturb / warp-style "exile it instead": leaving for anywhere but exile, it's exiled.
	if old.zone == EngineEnums.ZoneId.BATTLEFIELD and dest_zone != EngineEnums.ZoneId.EXILE and (old.unearthed or bool(old.marks.get("exile if it would leave", false))):
		dest_zone = EngineEnums.ZoneId.EXILE
	if dest_zone == EngineEnums.ZoneId.GRAVEYARD and bool(old.marks.get("exile instead of graveyard", false)):
		dest_zone = EngineEnums.ZoneId.EXILE
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
	if old.zone == EngineEnums.ZoneId.BATTLEFIELD:
		_note_left_battlefield(gs, old, dest_zone)
	_drop_commander_id(old)
	var last_known := _last_known(old)
	if old.is_token and dest_zone != EngineEnums.ZoneId.BATTLEFIELD:
		gs.objects.erase(object_id)
		var ceased := gs.log.append(EngineEnums.EventType.ZONE_CHANGE, old.owner_id, {
			from_id = old.object_id,
			to_id = EngineIds.NONE,
			from_zone = old.zone,
			to_zone = dest_zone,
			linked_from = old.object_id,
			definition = old.definition,
			from_controller = old.controller_id,
			was_token = true,
			lki = last_known,
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
	## A transformed double-faced card is its front face again anywhere but the battlefield (CR 712.8).
	new_obj.definition = old.front_def if old.front_def != null else old.definition
	new_obj.timestamp = gs.next_timestamp
	gs.next_timestamp += 1
	new_obj.linked_from = old.object_id
	new_obj.instance_uuid = old.instance_uuid
	new_obj.face_id = old.face_id
	new_obj.is_token = old.is_token
	new_obj.is_commander = old.is_commander
	new_obj.tapped = dest_zone == EngineEnums.ZoneId.BATTLEFIELD and _etb_tapped(old.definition, new_obj.controller_id)
	new_obj.summoned_this_turn = dest_zone == EngineEnums.ZoneId.BATTLEFIELD
	new_obj.damage_marked = 0
	## What a spell carries onto the battlefield: kicker, how it was cast, face-down status, dash and suspend haste.
	if old.zone == EngineEnums.ZoneId.STACK and dest_zone == EngineEnums.ZoneId.BATTLEFIELD:
		new_obj.kicked = old.kicked
		new_obj.cast_from = old.cast_from
		new_obj.cast_mode = old.cast_mode
		new_obj.face_down = old.face_down
		new_obj.dashed = old.dashed
		new_obj.granted_haste = old.granted_haste
		new_obj.ward_extra = old.ward_extra
		new_obj.gift_promised = old.gift_promised
		new_obj.x_paid = old.x_paid
		new_obj.mana_spent = old.mana_spent
		new_obj.colors_spent = old.colors_spent.duplicate()
		new_obj.bestowed = old.bestowed
		for mk in ["exile instead of graveyard", "evoked", "blitzed", "warped", "bargained", "evidence collected",
				"offspring paid", "squad", "teamwork", "prototyped", "converted", "disturbed", "cleaved", "mutating", "sneaked",
				"bestowing", "sneak_defender", "copies_on_resolve", "evidence", "phyrexian_life"]:
			if old.marks.has(mk):
				new_obj.marks[mk] = old.marks[mk]
		if old.front_def != null:
			new_obj.front_def = old.front_def
			new_obj.definition = old.definition
	if old.zone == EngineEnums.ZoneId.BATTLEFIELD and dest_zone == EngineEnums.ZoneId.GRAVEYARD:
		gs.died_this_turn += 1
	gs.objects.erase(object_id)
	gs.objects[new_obj.object_id] = new_obj
	_insert(dst, new_obj.object_id)
	_add_commander_id(new_obj)
	if dest_zone == EngineEnums.ZoneId.BATTLEFIELD:
		_on_enter(gs, new_obj)
	## A merged (mutated) permanent's other cards go to the same zone (CR 721.3 / 702.140).
	if old.zone == EngineEnums.ZoneId.BATTLEFIELD and not old.merged.is_empty() and dest_zone != EngineEnums.ZoneId.BATTLEFIELD:
		for md in old.merged:
			var part := GameObject.new()
			part.object_id = gs.next_object_id
			gs.next_object_id += 1
			part.owner_id = old.owner_id
			part.controller_id = dest_player if dest_player >= 0 else old.owner_id
			part.zone = dest_zone
			part.definition = md
			part.timestamp = gs.next_timestamp
			gs.next_timestamp += 1
			part.instance_uuid = "o%d" % part.object_id
			gs.objects[part.object_id] = part
			_insert(dst, part.object_id)
	var ev := gs.log.append(EngineEnums.EventType.ZONE_CHANGE, new_obj.owner_id, {
		from_id = old.object_id,
		to_id = new_obj.object_id,
		from_zone = old.zone,
		to_zone = dest_zone,
		linked_from = old.object_id,
		definition = old.definition,
		from_controller = old.controller_id,
		was_token = old.is_token,
		lki = last_known,
	})
	ev.object_ids.append(old.object_id)
	ev.object_ids.append(new_obj.object_id)
	return new_obj


func _last_known(old: GameObject) -> Dictionary:
	if old.zone != EngineEnums.ZoneId.BATTLEFIELD or not lki_fn.is_valid():
		return {}
	var out: Variant = lki_fn.call(old)
	return out if out is Dictionary else {}


## -1 = automatic, 0 = the player declined the optional reveal/payment, 1 = accepted. Set by the table around a land play.
var etb_choice: int = -1


## "Creatures your opponents control enter tapped." (CR 614.1d), read from the permanents' Oracle text.
func _opponents_make_creatures_tapped(controller: int) -> bool:
	var gs := _gs()
	var bz := get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if gs == null or bz == null:
		return false
	for oid in bz.object_ids:
		var o: GameObject = gs.objects.get(oid)
		if o != null and o.controller_id != controller and o.definition is CardDefinition and not o.face_down and not o.phased_out:
			if (o.definition as CardDefinition).oracle_text.to_lower().contains("creatures your opponents control enter tapped"):
				return true
	return false


func _etb_tapped(definition, controller: int) -> bool:
	if not (definition is CardDefinition):
		return false
	var def := definition as CardDefinition
	if def.enters_tapped():
		return true
	if def.is_creature() and _opponents_make_creatures_tapped(controller):
		return true
	var rule := EtbRules.parse(def)
	if rule.is_empty():
		return false
	var gs := _gs()
	if gs == null:
		return false
	var hand: Array = []
	var hz := get_zone(EngineEnums.ZoneId.HAND, controller)
	if hz != null:
		for oid in hz.object_ids:
			hand.append(gs.objects.get(oid))
	var mine: Array = []
	var bz := get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bz != null:
		for oid in bz.object_ids:
			var o: GameObject = gs.objects.get(oid)
			if o != null and o.controller_id == controller:
				mine.append(o)
	var life := int(gs.players[controller].life) if controller >= 0 and controller < gs.players.size() else 0
	var kind := str(rule.get("kind"))
	## The player's own answer ("reveal a card?", "pay life?") when the table asked; otherwise automatic.
	if etb_choice >= 0 and (kind == "REVEAL" or kind == "PAY_LIFE"):
		if etb_choice == 0:
			return true
		if kind == "REVEAL":
			return not EtbRules._any_has(hand, rule.get("types", []))
		if life <= int(rule.get("n", 0)):
			return true
		gs.players[controller].life -= int(rule.get("n", 0))
		gs.log.append(EngineEnums.EventType.LIFE_CHANGE, controller, {to_player = controller, amount = int(rule.get("n", 0))})
		return false
	var tapped := EtbRules.tapped_on_entry(rule, hand, mine, life)
	if str(rule.get("kind")) == "PAY_LIFE" and not tapped:
		gs.players[controller].life -= int(rule.get("n", 0))
		gs.log.append(EngineEnums.EventType.LIFE_CHANGE, controller, {to_player = controller, amount = int(rule.get("n", 0))})
	return tapped


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


## Per-turn facts the "morbid" / "revolt" family asks about: a creature died this turn, a permanent left under a
## player's control this turn.
func _note_left_battlefield(gs: GameState, old: GameObject, dest_zone: int) -> void:
	if old.controller_id >= 0 and old.controller_id < gs.players.size():
		gs.players[old.controller_id].permanents_left_this_turn += 1
	if dest_zone == EngineEnums.ZoneId.GRAVEYARD and old.definition is CardDefinition and (old.definition as CardDefinition).is_creature():
		gs.creatures_died_this_turn += 1


## "~ enters with two +1/+1 counters on it" / "...with a shield counter on it": what it enters with, read from the
## Oracle text (unconditional lines only: "if ..." forms are left to the card).
static func enters_with_counters(def: CardDefinition) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?i)^(?:~|this [a-z]+) enters with (a|an|one|two|three|four|five|six|seven|eight|nine|ten|x|\\d+) (-1/-1|[a-z]+) counters? on (?:it|him|her|them)\\.?$")
	for raw in OracleIr.normalize(def).split("\n"):
		var m := re.search(str(raw).strip_edges())
		if m == null:
			continue
		## "+1/+1" counters are already read as an ability by OracleIr.
		out.append({"name": m.get_string(2).to_lower(), "n": OracleIr._num(m.get_string(1)), "x": m.get_string(1).to_lower() == "x"})
	return out


## "Each other Angel you control enters with an additional +1/+1 counter on it for each Angel you already control" (Giada),
## "Each Dragon you control enters with an additional +1/+1 counter" (Dragonstorm Globe), Metallic Mimic: statics of the
## permanents already on the battlefield that give what enters extra counters.
func _enters_with_extra(gs: GameState, entering: GameObject) -> void:
	var bf: Zone = get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf == null:
		return
	for sid in bf.object_ids:
		var src: GameObject = gs.objects.get(sid)
		if src == null or not (src.definition is CardDefinition):
			continue
		for a in (src.definition as CardDefinition).abilities:
			var ab := a as Ability
			if ab == null or ab.kind != &"STATIC" or not ab.static_spec.has("enters_extra"):
				continue
			var spec: Dictionary = ab.static_spec["enters_extra"]
			var q: Dictionary = spec.get("query", {})
			if not Query._matches(entering, src, q):
				continue
			var n := int(spec.get("n", 1))
			if spec.has("per"):
				var already := Query.count_objects(gs, src, spec["per"])
				if Query._matches(entering, src, spec["per"]):
					already -= 1
				n *= maxi(0, already)
			entering.counters["+1/+1"] = int(entering.counters.get("+1/+1", 0)) + n
