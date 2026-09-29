@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")
const CardFaceScript := preload("res://scripts/card_face.gd")

var db: CardDatabase
var catalog: Object


func suite_name() -> String:
	return "engine_card_face"


func suite_setup(_ctx: Dictionary) -> void:
	db = DemoSetup.memory_db()
	catalog = load("res://scripts/scryfall_catalog.gd").new()
	catalog.load_catalog()


func test_volunteer_is_a_normal_card_like_mountain_and_shock() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mountain := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Mountain")
	var shock := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Shock")
	var volunteer := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Volunteer 01")
	var cat := catalog
	var projected: Array = [
		TableView._card_dict(engine, mountain, cat),
		TableView._card_dict(engine, shock, cat),
		TableView._card_dict(engine, volunteer, cat),
	]
	for card in projected:
		assert_false(bool(card.get("is_token", true)))
		assert_true(CardFaceScript.is_normal_card(card), str(card.get("name", "")))
		assert_ne(CardFaceScript.mode(card), CardFaceScript.MODE_TOKEN)
		assert_ne(CardFaceScript.art_caption(card), "Card frame")
		assert_true(str(card.get("name", "")) != "")
		assert_true(str(card.get("type", "")) != "")
		assert_true(str(card.get("cardId", "")) != "")
		assert_true(card.has("mana_cost"))
		assert_true(card.has("text"))
		assert_true(card.has("zone"))
	var volunteer_view: Dictionary = projected[2]
	assert_eq(str(volunteer_view.get("name", "")), "Goblin Volunteer 01")
	assert_eq(str(volunteer_view.get("mana_cost", "")), "{R}")
	assert_eq(str(volunteer_view.get("type", "")), "Creature — Goblin")
	assert_eq(str(volunteer_view.get("power", "")), "1")
	assert_eq(str(volunteer_view.get("toughness", "")), "1")
	assert_eq(CardFaceScript.mode(volunteer_view), CardFaceScript.MODE_PRINTED)
	assert_eq(CardFaceScript.art_caption(volunteer_view), "")
	var mountain_view: Dictionary = projected[0]
	var shock_view: Dictionary = projected[1]
	assert_true(CardFaceScript.has_artwork(mountain_view), "Mountain should resolve catalog art")
	assert_true(CardFaceScript.has_artwork(shock_view), "Shock should resolve catalog art")
	assert_false(CardFaceScript.has_artwork(volunteer_view))
	assert_eq(CardFaceScript.mode(mountain_view), CardFaceScript.MODE_ART)
	assert_eq(CardFaceScript.mode(shock_view), CardFaceScript.MODE_ART)
	assert_eq(str(mountain_view.get("kind", "")), "land")
	assert_eq(str(shock_view.get("kind", "")), "spell")
	assert_eq(str(volunteer_view.get("kind", "")), "spell")


func test_volunteer_stays_a_card_across_zones() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var volunteer := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Volunteer 01")
	var cat := catalog
	var zones: Array[int] = [
		EngineEnums.ZoneId.HAND,
		EngineEnums.ZoneId.BATTLEFIELD,
		EngineEnums.ZoneId.GRAVEYARD,
		EngineEnums.ZoneId.EXILE,
	]
	var current := volunteer
	for dest in zones:
		var moved: GameObject = engine.state.zones.move(current.object_id, dest, 0)
		assert_true(moved != null)
		assert_false(moved.is_token)
		assert_true(moved.definition is CardDefinition)
		assert_eq((moved.definition as CardDefinition).name, "Goblin Volunteer 01")
		var view := TableView._card_dict(engine, moved, cat)
		assert_false(bool(view.get("is_token", true)))
		assert_eq(CardFaceScript.mode(view), CardFaceScript.MODE_PRINTED)
		assert_ne(CardFaceScript.art_caption(view), "Card frame")
		current = moved


func test_starter_deck_uses_real_cards_when_catalog_is_loaded() -> void:
	assert_true(bool(catalog.get("loaded")), str(catalog.get("load_error")))
	var demo := DemoSetup.from_scryfall(catalog, 1)
	assert_true(demo != null)
	assert_eq(DemoSetup._list_count(demo.krenko_list), 99)
	assert_eq(DemoSetup._list_count(demo.talrand_list), 99)
	for entry in demo.krenko_list.library:
		var name := str(entry.get("name", ""))
		assert_false(name.begins_with("Goblin Volunteer"), name)
		assert_false(name.begins_with("Merfolk Volunteer"), name)
		var row: Variant = catalog.find_by_name(name)
		assert_true(row is Dictionary and not (row as Dictionary).is_empty(), name)
	for entry2 in demo.talrand_list.library:
		var name2 := str(entry2.get("name", ""))
		assert_false(name2.begins_with("Goblin Volunteer"), name2)
		assert_false(name2.begins_with("Merfolk Volunteer"), name2)
		var row2: Variant = catalog.find_by_name(name2)
		assert_true(row2 is Dictionary and not (row2 as Dictionary).is_empty(), name2)


