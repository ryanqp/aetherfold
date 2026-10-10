@tool
extends McpTestSuite

## AUDIT-036 (the game log trims in chunks and finds `since` by binary search) and AUDIT-029 (the city's blessing is kept).

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_perf_and_blessing"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_the_log_keeps_the_newest_events_and_stays_ordered() -> void:
	var log := GameLog.new()
	for _i in 12500:
		log.append(EngineEnums.EventType.NOTE, 0, {})
	assert_true(log.size() >= GameLog.CAP and log.size() <= GameLog.CAP + GameLog.TRIM_SLACK, "kept about %d (%d)" % [GameLog.CAP, log.size()])
	assert_eq(log.seq(), 12500)
	assert_eq(log.last().seq, 12500)
	for i in range(1, log.size()):
		assert_true(log.events[i].seq == log.events[i - 1].seq + 1, "no gaps")
		if i > 50:
			break


func test_since_returns_exactly_the_newer_events() -> void:
	var log := GameLog.new()
	for _i in 300:
		log.append(EngineEnums.EventType.NOTE, 0, {})
	assert_eq(log.since(0).size(), 300)
	assert_eq(log.since(250).size(), 50)
	assert_eq((log.since(250)[0] as GameEvent).seq, 251)
	assert_eq(log.since(300).size(), 0)
	assert_eq(log.since(999).size(), 0)
	var trimmed := GameLog.new()
	for _j in 12500:
		trimmed.append(EngineEnums.EventType.NOTE, 0, {})
	assert_eq(trimmed.since(12490).size(), 10, "after trimming too")
	assert_eq(trimmed.since(0).size(), trimmed.size(), "an old position gets everything still kept")


func test_the_citys_blessing_stays_once_you_have_had_ten_permanents() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var made: Array = []
	for _i in 10:
		made.append(Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain"))
	assert_false(engine.state.players[0].citys_blessing, "not noticed yet")
	assert_true(LayerManager.citys_blessing(engine.state, 0), "ten permanents: you have it")
	for i in 4:
		engine.state.zones.move((made[i] as GameObject).object_id, EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_true(LayerManager.citys_blessing(engine.state, 0), "and losing some doesn't take it away")
	assert_false(LayerManager.citys_blessing(engine.state, 1), "the other player never got it")


func test_the_picture_cache_stays_under_its_limit_and_keeps_the_recent_ones() -> void:
	var cat: Node = (load("res://scripts/scryfall_catalog.gd") as GDScript).new()
	var tex := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for i in 250:
		cat._remember_texture("art_%d" % i, tex)
		if i == 100:
			pass
	assert_eq(cat._textures.size(), cat.MAX_TEXTURES)
	assert_false(cat._textures.has("art_0"), "the oldest was dropped")
	assert_true(cat._textures.has("art_249"), "the newest is kept")
	cat._remember_texture("art_60", tex)  ## used again: moves to the front of the queue
	for j in range(250, 262):
		cat._remember_texture("art_%d" % j, tex)
	assert_true(cat._textures.has("art_60"), "a picture that keeps being shown stays")
	assert_false(cat._textures.has("art_61"), "while its neighbour that wasn't is gone")
	cat.free()


func _throwaway_engine() -> void:
	var e := Fixtures.empty_engine_1v1()
	for i in 60:
		Fixtures.spawn_named(e, db, i % 2, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	for i in 30:
		Fixtures.spawn_named(e, db, i % 2, EngineEnums.ZoneId.LIBRARY, "Island")
	e.process_zone_events()


func test_a_finished_engine_leaves_no_objects_behind() -> void:
	_throwaway_engine()  ## the first one warms up shared caches
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for _i in 4:
		_throwaway_engine()
	var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	assert_true(after - before < 50, "object count grew by %d over 4 dropped games (a reference cycle keeps them alive)" % (after - before))
