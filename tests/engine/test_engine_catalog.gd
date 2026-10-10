@tool
extends McpTestSuite

## The shipped card catalog (data/scryfall/catalog.jsonl): every game card is a real, playable card with all of its faces
## (AUDIT-003). These tests read the real file, so a bad rebuild of the catalog fails here.

var cat: Node


func suite_name() -> String:
	return "engine_catalog"


func suite_setup(_ctx: Dictionary) -> void:
	cat = (load("res://scripts/scryfall_catalog.gd") as GDScript).new()
	cat.load_catalog()


func suite_teardown() -> void:
	if cat != null:
		cat.free()


func _definition(card_name: String) -> CardDefinition:
	var row: Dictionary = cat.find_by_name(card_name)
	if row.is_empty():
		return null
	var mem := CatalogSource.Memory.new()
	mem.add(row)
	var db := CardDatabase.new()
	db.setup(mem)
	return db.definition_for(str(row.get("name", card_name)))


func test_the_catalog_loads_and_has_no_art_cards_or_tokens() -> void:
	assert_true(bool(cat.loaded), "loaded: %s" % str(cat.load_error))
	assert_true(int(cat.card_count) > 30000, "card count %d" % int(cat.card_count))
	var bad := 0
	for row in cat.cards_by_name.values():
		if str((row as Dictionary).get("layout", "")) in cat.NOT_GAME_LAYOUTS:
			bad += 1
	assert_eq(bad, 0, "rows that are not cards")


func test_a_transform_card_has_both_faces_and_is_not_the_art_card() -> void:
	var d := _definition("Delver of Secrets")
	assert_true(d != null, "Delver resolves")
	assert_eq(d.name, "Delver of Secrets // Insectile Aberration")
	assert_true(d.back_face != null, "it has a back face")
	assert_eq(d.back_face.name, "Insectile Aberration")
	assert_eq(d.power, "1")
	assert_eq(d.back_face.power, "3", "the back face has its own power")
	assert_true(d.oracle_text != "", "and rules text")


func test_a_split_card_has_both_halves() -> void:
	var d := _definition("Fire // Ice")
	assert_true(d != null and d.other_half != null, "both halves")
	assert_true(d.oracle_text.contains("2 damage") and d.other_half.oracle_text.contains("Tap target permanent"), "each half has its text")


func test_an_adventure_card_has_its_adventure() -> void:
	var d := _definition("Bonecrusher Giant")
	assert_true(d != null and d.other_half != null, "creature and adventure")
	assert_eq(d.other_half.name, "Stomp")
	assert_eq(d.power, "4")


func test_a_modal_dfc_has_both_sides() -> void:
	var d := _definition("Valki, God of Lies")
	assert_true(d != null and d.back_face != null, "both sides")
	assert_true(d.back_face.type_line.contains("Planeswalker"), "the back is Tibalt, a planeswalker")


func test_every_double_faced_card_keeps_its_faces_with_text() -> void:
	var multi := 0
	var broken: Array = []
	for row in cat.cards_by_name.values():
		var faces: Variant = (row as Dictionary).get("faces", [])
		if not (faces is Array) or (faces as Array).size() < 2:
			continue
		multi += 1
		for f in faces:
			if not (f is Dictionary) or str((f as Dictionary).get("name", "")) == "" or str((f as Dictionary).get("type_line", "")) == "":
				broken.append(str((row as Dictionary).get("name", "?")))
				break
	assert_true(multi > 800, "multi-face cards: %d" % multi)
	assert_eq(broken.size(), 0, "faces without a name or type: %s" % str(broken.slice(0, 5)))


func test_double_faced_cards_have_art() -> void:
	var row: Dictionary = cat.find_by_name("Delver of Secrets")
	assert_true(str((row.get("images", {}) as Dictionary).get("normal", "")) != "", "the front face's picture is used")


func test_an_old_saved_deck_gets_its_double_faced_cards_back() -> void:
	## A deck saved before the catalog kept faces holds "Delver of Secrets" with bare face names (AUDIT-003).
	var old_row := {name = "Delver of Secrets // Insectile Aberration", layout = "transform", faces = ["Delver of Secrets", "Insectile Aberration"], oracle_text = ""}
	var plain_row := {name = "Sol Ring", layout = "normal", faces = []}
	var fresh: Dictionary = DeckCatalog.refresh_rows({"Delver of Secrets": old_row, "Sol Ring": plain_row}, cat)
	var delver: Dictionary = fresh["Delver of Secrets"]
	assert_true((delver.get("faces", []) as Array)[0] is Dictionary, "the faces are whole again")
	assert_true(str(delver.get("oracle_text", "")) != "", "with rules text")
	assert_eq(fresh["Sol Ring"], plain_row, "other cards are left alone")
