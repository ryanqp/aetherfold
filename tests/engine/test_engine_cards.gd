@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

func suite_name() -> String:
	return "engine_cards"


func test_memory_catalog_lookup() -> void:
	var cat := Fixtures.memory_catalog()
	var mountain: Dictionary = cat.find_by_name("mountain")
	assert_eq(str(mountain.get("name", "")), "Mountain")
	assert_eq(str(cat.find_by_name("MOUNTAIN").get("type_line", "")), "Basic Land — Mountain")
	assert_true(cat.find_by_name("no-such-card").is_empty())


func test_printed_fields_from_catalog_without_art() -> void:
	var db := Fixtures.memory_db()
	var piker: CardDefinition = db.definition_for("Goblin Piker")
	assert_true(piker != null)
	assert_eq(piker.name, "Goblin Piker")
	assert_eq(piker.mana_cost, "{1}{R}")
	assert_eq(piker.cmc, 2)
	assert_eq(piker.type_line, "Creature — Goblin Warrior")
	assert_eq(piker.power, "2")
	assert_eq(piker.toughness, "1")
	assert_true(piker.commander_legal)
	var props := piker.get_property_list()
	var names: Array = []
	for p in props:
		names.append(str(p.get("name", "")))
	assert_false(names.has("images"), "engine CardDefinition must not carry art")
	assert_false(names.has("scryfall_id"))


func test_basic_land_mana_is_inferred() -> void:
	var db := Fixtures.memory_db()
	var mountain: CardDefinition = db.definition_for("Mountain")
	assert_true(mountain.is_basic_land())
	assert_eq(mountain.mana_abilities().size(), 1)
	var ab: Ability = mountain.mana_abilities()[0]
	assert_eq(str(ab.kind), "MANA")
	assert_true(ab.has_tap_cost())
	var fx: AbilityEffect = ab.effects[0]
	assert_eq(str(fx.kind), "ADD_MANA")
	assert_eq(str(fx.params.get("mana", "")), "{R}")
	var island: CardDefinition = db.definition_for("Island")
	var ifx: AbilityEffect = island.mana_abilities()[0].effects[0]
	assert_eq(str(ifx.params.get("mana", "")), "{U}")


func test_ir_loader_empty_abilities() -> void:
	var loader := IrLoader.new()
	var abs: Array = loader.from_dict({name = "Vanilla", abilities = []})
	assert_eq(abs.size(), 0)
	assert_eq(loader.errors.size(), 0)


func test_ir_loader_forgotten_cave_file() -> void:
	var db := Fixtures.memory_db()
	var cave: CardDefinition = db.definition_for("Forgotten Cave")
	assert_true(cave != null)
	assert_eq(cave.mana_abilities().size(), 1)
	assert_eq(str(cave.mana_abilities()[0].ability_id), "cave_r")
	var cycle: Ability = cave.find_ability(&"cave_cycle")
	assert_true(cycle != null)
	assert_true(cycle.unparsed)


func test_ir_loader_rejects_unknown_kind() -> void:
	var loader := IrLoader.new()
	var abs: Array = loader.from_dict({
		name = "Bad",
		abilities = [{ability_id = "x", kind = "EXPLODE", effects = []}],
	})
	assert_eq(abs.size(), 0)
	assert_gt(loader.errors.size(), 0)


func test_ir_loader_rejects_unknown_param() -> void:
	var loader := IrLoader.new()
	var abs: Array = loader.from_dict({
		name = "Bad",
		abilities = [{
			ability_id = "x",
			kind = "MANA",
			effects = [{kind = "ADD_MANA", params = {mana = "{R}", extra = 1}}],
		}],
	})
	assert_eq(abs.size(), 0)
	assert_gt(loader.errors.size(), 0)


func test_token_catalog_goblin() -> void:
	var tokens := TokenCatalog.new()
	var gob: CardDefinition = tokens.definition_for(TokenCatalog.GOBLIN_1_1_R)
	assert_true(gob != null)
	assert_eq(gob.name, "Goblin")
	assert_eq(gob.power, "1")
	assert_eq(gob.toughness, "1")
	assert_true(gob.is_creature())


func test_deck_list_resource() -> void:
	var deck := DeckList.new()
	deck.commander_oracle_ids = PackedStringArray(["krenko"])
	deck.library = [{name = "Mountain", count = 20}]
	assert_eq(deck.commander_oracle_ids.size(), 1)
	assert_eq(deck.library.size(), 1)


func test_scryfall_wrap_survives_missing_autoload() -> void:
	var wrap := CatalogSource.ScryfallWrap.new()
	var row: Dictionary = wrap.find_by_name("Mountain")
	assert_true(row is Dictionary)
