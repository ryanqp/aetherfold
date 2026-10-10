@tool
extends McpTestSuite

## What a built game needs: the card catalog travels with it, art goes to the player's own folder, and the export presets
## exist (AUDIT-001, -002, -030). These checks read the project files, so a change that breaks packaging fails here.

func suite_name() -> String:
	return "engine_packaging"


func _catalog_node() -> Node:
	return (load("res://scripts/scryfall_catalog.gd") as GDScript).new()


func test_catalog_is_read_from_inside_the_game_not_from_a_drive() -> void:
	var cat := _catalog_node()
	var dir: String = cat.data_dir()
	assert_true(dir.begins_with("res://") or OS.get_environment("AETHERFOLD_SCRYFALL_DIR") != "", "catalog dir: %s" % dir)
	assert_false(dir.contains(":/") and not dir.begins_with("res://"), "no drive letter in the catalog path")
	assert_true(FileAccess.file_exists("res://data/scryfall/catalog.jsonl"), "the catalog is in the project")
	cat.free()


func test_downloaded_art_goes_to_the_players_data_folder() -> void:
	var cat := _catalog_node()
	assert_true(str(cat.image_dir()).begins_with("user://"), "art cache: %s" % str(cat.image_dir()))
	cat.free()


func test_the_catalog_folder_is_not_hidden_from_the_exporter() -> void:
	## A .gdignore in data/scryfall kept the catalog out of every export; only the loose pictures are hidden.
	assert_false(FileAccess.file_exists("res://data/scryfall/.gdignore"), "catalog folder is exported")
	assert_true(FileAccess.file_exists("res://data/scryfall/images/.gdignore"), "loose pictures stay out of builds")


func test_export_presets_cover_windows_and_android() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg is in the project")
	var platforms := PackedStringArray()
	var android_opts := {}
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			var platform := str(cfg.get_value(section, "platform", ""))
			platforms.append(platform)
			assert_true(str(cfg.get_value(section, "include_filter", "")).contains("*.jsonl"), "%s exports the catalog" % platform)
			assert_true(str(cfg.get_value(section, "exclude_filter", "")).contains("addons/godot_ai"), "%s leaves out the editor addon" % platform)
			if platform == "Android":
				for key in cfg.get_section_keys(section + ".options"):
					android_opts[key] = cfg.get_value(section + ".options", key)
	assert_true(platforms.has("Windows Desktop") and platforms.has("Android"), "presets: %s" % str(platforms))
	for perm in ["permissions/internet", "permissions/access_network_state", "permissions/access_wifi_state", "permissions/change_wifi_multicast_state"]:
		assert_true(bool(android_opts.get(perm, false)), "Android permission %s (online play and card art)" % perm)
	assert_eq(str(ProjectSettings.get_setting("display/window/handheld/orientation", -1)), "0", "landscape")


func test_no_secrets_in_the_presets() -> void:
	var text := FileAccess.get_file_as_string("res://export_presets.cfg").to_lower()
	for word in ["keystore/release_password", "password=\"", "keystore/debug_password"]:
		assert_false(text.contains(word), "no %s in a committed preset" % word)
