@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

func suite_name() -> String:
	return "engine_zones"


func test_per_player_zones_are_lists() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var lib0: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 0)
	var lib1: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, 1)
	var hand0: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	var gy0: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_true(lib0 != null)
	assert_true(lib1 != null)
	assert_ne(lib0, lib1)
	assert_eq(lib0.size(), 0)
	assert_eq(hand0.size(), 0)
	assert_eq(gy0.size(), 0)
	var a: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.LIBRARY)
	var b: GameObject = Fixtures.spawn(engine, 1, EngineEnums.ZoneId.LIBRARY)
	assert_true(lib0.has(a.object_id))
	assert_false(lib0.has(b.object_id))
	assert_true(lib1.has(b.object_id))
	assert_eq(lib0.size(), 1)
	assert_eq(lib1.size(), 1)


func test_battlefield_is_shared() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	var p0: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.BATTLEFIELD)
	var p1: GameObject = Fixtures.spawn(engine, 1, EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(bf.size(), 2)
	assert_true(bf.has(p0.object_id))
	assert_true(bf.has(p1.object_id))
	assert_eq(p0.zone, EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(p1.zone, EngineEnums.ZoneId.BATTLEFIELD)


func test_zone_change_allocates_new_object_id() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var card: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.HAND)
	var old_id := card.object_id
	var old_ts := card.timestamp
	var moved: GameObject = engine.state.zones.move(old_id, EngineEnums.ZoneId.BATTLEFIELD)
	assert_true(moved != null)
	assert_ne(moved.object_id, old_id)
	assert_eq(moved.linked_from, old_id)
	assert_gt(moved.timestamp, old_ts)
	assert_false(engine.state.objects.has(old_id))
	assert_true(engine.state.objects.has(moved.object_id))
	assert_eq(moved.zone, EngineEnums.ZoneId.BATTLEFIELD)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(hand.has(old_id))
	assert_true(bf.has(moved.object_id))
	var ev: GameEvent = engine.state.log.last()
	assert_eq(ev.type, EngineEnums.EventType.ZONE_CHANGE)
	assert_eq(ev.payload.from_id, old_id)
	assert_eq(ev.payload.to_id, moved.object_id)
	assert_eq(ev.payload.from_zone, EngineEnums.ZoneId.HAND)
	assert_eq(ev.payload.to_zone, EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(ev.payload.linked_from, old_id)


func test_graveyard_is_a_list() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var first: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.HAND)
	var second: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.HAND)
	var first_id := first.object_id
	var second_id := second.object_id
	var gy_first: GameObject = engine.state.zones.move(first_id, EngineEnums.ZoneId.GRAVEYARD)
	var gy_second: GameObject = engine.state.zones.move(second_id, EngineEnums.ZoneId.GRAVEYARD)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 2)
	assert_eq(gy.object_ids[0], gy_second.object_id)
	assert_eq(gy.object_ids[1], gy_first.object_id)
	assert_eq(engine.state.objects[gy.object_ids[0]].zone, EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(engine.state.objects[gy.object_ids[1]].zone, EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(gy_first.linked_from, first_id)
	assert_eq(gy_second.linked_from, second_id)


func test_counters_do_not_copy() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var card: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.BATTLEFIELD)
	card.counters[&"p1p1"] = 3
	var moved: GameObject = engine.state.zones.move(card.object_id, EngineEnums.ZoneId.GRAVEYARD)
	assert_true(moved != null)
	assert_eq(moved.counters.size(), 0)


func test_attachments_drop() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var host: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.BATTLEFIELD)
	var aura: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.BATTLEFIELD)
	host.attachments.append(aura.object_id)
	var aura_id := aura.object_id
	var moved: GameObject = engine.state.zones.move(host.object_id, EngineEnums.ZoneId.GRAVEYARD)
	assert_true(moved != null)
	assert_eq(moved.attachments.size(), 0)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_true(bf.has(aura_id))
	assert_true(engine.state.objects.has(aura_id))


func test_token_leaving_battlefield_ceases() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var tok: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.BATTLEFIELD, {is_token = true})
	var old_id := tok.object_id
	var result: GameObject = engine.state.zones.move(old_id, EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(result, null)
	assert_false(engine.state.objects.has(old_id))
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 0)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(bf.has(old_id))
	var ev: GameEvent = engine.state.log.last()
	assert_eq(ev.type, EngineEnums.EventType.ZONE_CHANGE)
	assert_eq(ev.payload.to_id, EngineIds.NONE)
	assert_eq(ev.payload.from_id, old_id)


func test_commander_ids_follow_current_object() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var cmd: GameObject = Fixtures.spawn(engine, 0, EngineEnums.ZoneId.COMMAND, {is_commander = true})
	var old_id := cmd.object_id
	assert_true(engine.state.players[0].commander_ids.has(old_id))
	var on_bf: GameObject = engine.state.zones.move(old_id, EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(engine.state.players[0].commander_ids.has(old_id))
	assert_true(engine.state.players[0].commander_ids.has(on_bf.object_id))
	var pending: GameObject = engine.state.zones.move(on_bf.object_id, EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(pending, null)
	var act := GameAction.new()
	act.kind = GameAction.Kind.CHOOSE_REPLACEMENT
	act.player_id = 0
	act.extra = {dest_zone = EngineEnums.ZoneId.GRAVEYARD}
	assert_true(engine.submit(act).ok)
	assert_false(engine.state.players[0].commander_ids.has(on_bf.object_id))
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 1)


func test_zone_types_are_not_nodes() -> void:
	var engine := Fixtures.empty_engine_1v1()
	assert_eq(engine.state.zones.get_class(), "RefCounted")
	var z: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(z.get_class(), "RefCounted")
	var obj := GameObject.new()
	assert_eq(obj.get_class(), "RefCounted")
