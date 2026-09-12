extends Control

const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const PANEL := Color(0.09, 0.10, 0.11, 0.96)
const RivalAI := preload("res://scripts/rival_ai.gd")
const VS_DIFF_HINTS := ["Misses plays", "Land + a spell", "Dumps cheap spells", "Attacks and counters"]

var pages: Dictionary = {}
var current: String = "hub"
var vs_player_id: String = "builtin:krenko"
var vs_bot_id: String = "builtin:talrand"
var vs_diff: int = 1
var import_overlay: ImportOverlay
var builder_cmd_name: String = ""
var builder_cards: Dictionary = {}

@onready var status_label: Label = %StatusLabel
@onready var mp_code_edit: LineEdit = %MpCodeEdit
@onready var mp_ip_edit: LineEdit = %MpIpEdit
@onready var mp_status: Label = %MpStatus
@onready var mp_roster: Label = %MpRoster
@onready var gallery_grid: GridContainer = %GalleryGrid
@onready var builder_cmd: LineEdit = %BuilderCmd
@onready var builder_cmd_list: ItemList = %BuilderCmdList
@onready var builder_card: LineEdit = %BuilderCard
@onready var builder_card_list: ItemList = %BuilderCardList
@onready var builder_name: LineEdit = %BuilderName
@onready var builder_count: Label = %BuilderCount
@onready var settings_music: Button = %SettingsMusicBtn
@onready var settings_sfx: Button = %SettingsSfxBtn
@onready var vs_diff_option: OptionButton = %DiffOption


func _ready() -> void:
	pages = {
		"hub": %PageHub,
		"vs": %PageVs,
		"mp": %PageMp,
		"library": %PageLibrary,
		"gallery": %PageGallery,
		"builder": %PageBuilder,
		"settings": %PageSettings,
	}
	%VsAiBtn.pressed.connect(_show.bind("vs"))
	%MultiplayerBtn.pressed.connect(_show.bind("mp"))
	%LibraryBuilderBtn.pressed.connect(_show.bind("library"))
	%MenuBtn.pressed.connect(_show.bind("settings"))
	%VsBackBtn.pressed.connect(_show.bind("hub"))
	%MpBackBtn.pressed.connect(_show.bind("hub"))
	%LibraryBackBtn.pressed.connect(_show.bind("hub"))
	%BuilderBtn.pressed.connect(_show.bind("builder"))
	%GalleryBtn.pressed.connect(_show.bind("gallery"))
	%GalleryBackBtn.pressed.connect(_show.bind("hub"))
	%GalleryLibraryHomeBtn.pressed.connect(_show.bind("library"))
	%BuilderBackBtn.pressed.connect(_show.bind("hub"))
	%BuilderLibraryHomeBtn.pressed.connect(_show.bind("library"))
	%SettingsBackBtn.pressed.connect(_show.bind("hub"))
	for i in VS_DIFF_HINTS.size():
		vs_diff_option.add_item("%s — %s" % [RivalAI.label(i), VS_DIFF_HINTS[i]], i)
	vs_diff_option.select(1)
	import_overlay = preload("res://scenes/ui/import_overlay.tscn").instantiate()
	add_child(import_overlay)
	import_overlay.auto_play = false
	import_overlay.play_imported.connect(_on_imported_saved)
	import_overlay.deck_saved.connect(_on_imported_saved)
	var net := _net()
	if net and not net.status_changed.is_connected(_on_net_status):
		net.status_changed.connect(_on_net_status)
		net.peer_ready.connect(_on_peer_ready)
		net.lobby_changed.connect(_on_lobby_changed)
		net.match_begin.connect(_start_table)
	_show("hub")


func _app() -> Node:
	return get_node_or_null("/root/AppState")


func _net() -> Node:
	return get_node_or_null("/root/GameNet")


func _show(name: String) -> void:
	current = name
	for k in pages.keys():
		pages[k].visible = (str(k) == name)
	if name == "gallery":
		_refresh_gallery()
	if name == "vs":
		_refresh_vs_lists()


func _refresh_vs_lists() -> void:
	_fill_deck_list(pages["vs"].find_child("PlayerList", true, false), true)
	_fill_deck_list(pages["vs"].find_child("BotList", true, false), false)


func _fill_deck_list(list: Node, is_player: bool) -> void:
	if list == null:
		return
	while list.get_child_count() > 0:
		var ch := list.get_child(0)
		list.remove_child(ch)
		ch.queue_free()
	var selected := vs_player_id if is_player else vs_bot_id
	for rec in DeckCatalog.all_choices():
		var id := str(rec.get("id", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.toggle_mode = true
		b.button_pressed = id == selected
		b.text = "  %s" % str(rec.get("name", DeckCatalog.commander_name(rec)))
		if bool(rec.get("builtin", false)):
			b.text += "  (starter)"
		var tex := _cmd_tex(rec)
		if tex:
			b.icon = tex
			b.expand_icon = true
		b.pressed.connect(_on_pick_vs.bind(id, is_player))
		list.add_child(b)


func _on_pick_vs(id: String, is_player: bool) -> void:
	if is_player:
		vs_player_id = id
	else:
		vs_bot_id = id
	_refresh_vs_lists()


func _cmd_tex(rec: Dictionary) -> Texture2D:
	var cat := get_node_or_null("/root/ScryfallCatalog")
	if cat == null or not cat.has_method("texture_for"):
		return null
	return cat.texture_for(DeckCatalog.commander_row(rec), "small")


func _on_diff_selected(idx: int) -> void:
	vs_diff = idx


func _on_start_vs() -> void:
	var app := _app()
	if app:
		app.player_deck_id = vs_player_id
		app.rival_deck_id = vs_bot_id
		app.difficulty = vs_diff
		app.skip_ai = false
		app.mp_role = ""
		app.you_seat = 0
	_start_table()


func _start_table() -> void:
	get_tree().change_scene_to_file("res://scenes/table.tscn")


func _on_mp_host() -> void:
	var net := _net()
	if net == null:
		return
	var wanted := mp_code_edit.text
	var code: String = net.host_room(wanted)
	if code != "":
		mp_code_edit.text = code
		var ips := ", ".join(net.local_ips())
		mp_status.text = "Hosting %s. LAN code is enough on the same Wi-Fi.\nYour IP: %s" % [code, ips]


func _on_mp_join() -> void:
	var net := _net()
	if net == null:
		return
	var code := mp_code_edit.text.strip_edges()
	if code == "":
		mp_status.text = "Enter a room code to join."
		return
	net.join_room(code, mp_ip_edit.text)
	mp_status.text = net.last_status


func _on_mp_start() -> void:
	var net := _net()
	var app := _app()
	if net == null or app == null:
		return
	if net.role != "host":
		mp_status.text = "Only the host can start the match."
		return
	if not net.is_connected_peer():
		mp_status.text = "Wait for at least one player to join."
		return
	app.player_deck_id = vs_player_id
	var guest_deck: String = str(net.remote_deck_id)
	if guest_deck == "":
		guest_deck = vs_bot_id
	app.rival_deck_id = guest_deck
	net.start_match_rpc(vs_player_id, guest_deck)
	_start_table()


func _on_net_status(text: String) -> void:
	if mp_status:
		mp_status.text = text


func _on_peer_ready() -> void:
	var net := _net()
	if net and net.role == "client":
		net.announce_deck.rpc_id(1, vs_player_id)
	if mp_status:
		mp_status.text = "Connected. Host can start whenever ready."
	_on_lobby_changed()


func _on_lobby_changed() -> void:
	var net := _net()
	if net == null or mp_roster == null:
		return
	if net.role == "host":
		mp_roster.text = "Players: %d/%d (host can start with 2+)" % [net.player_count(), net.max_players()]
	elif net.role == "client":
		mp_roster.text = "Waiting on the host to start…"


func _on_open_import() -> void:
	if import_overlay:
		import_overlay.auto_play = false
		import_overlay.open()


func _on_imported_saved(_deck = null, _rows = null) -> void:
	_show("gallery")


func _refresh_gallery() -> void:
	while gallery_grid.get_child_count() > 0:
		var ch := gallery_grid.get_child(0)
		gallery_grid.remove_child(ch)
		ch.queue_free()
	var recs: Array = DeckStore.new().list_decks()
	if recs.is_empty():
		var empty := Label.new()
		empty.text = "No saved decks yet. Import a URL or use Library Builder."
		empty.add_theme_color_override("font_color", MUTED)
		gallery_grid.add_child(empty)
		return
	for rec in recs:
		gallery_grid.add_child(_gallery_card(rec))


func _gallery_card(rec: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 280)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.11, 0.10)
	st.set_corner_radius_all(10)
	st.set_border_width_all(2)
	st.border_color = GOLD.darkened(0.3)
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(160, 160)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := _cmd_tex(rec)
	if tex:
		art.texture = tex
	col.add_child(art)
	var name_edit := LineEdit.new()
	var default_nm := str(rec.get("name", ""))
	if default_nm.strip_edges() == "":
		default_nm = DeckCatalog.commander_name(rec)
	name_edit.text = default_nm
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var path := str(rec.get("_path", ""))
	name_edit.text_submitted.connect(func(n): DeckStore.new().rename(path, n))
	col.add_child(name_edit)
	var meta := Label.new()
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", MUTED)
	var total := 0
	if rec.get("validation") is Dictionary:
		total = int((rec.get("validation") as Dictionary).get("total", 0))
	if total == 0:
		var mb: Variant = rec.get("mainboard", [])
		if mb is Array:
			for e in mb:
				if e is Dictionary:
					total += int(e.get("quantity", 1))
		total += 1
	meta.text = "%s  ·  %d cards" % [DeckCatalog.commander_name(rec), total]
	col.add_child(meta)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var play := Button.new()
	play.text = "Vs AI"
	play.pressed.connect(func():
		vs_player_id = path
		_show("vs")
	)
	row.add_child(play)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func():
		DeckStore.new().delete_path(path)
		_refresh_gallery()
	)
	row.add_child(del)
	col.add_child(row)
	panel.add_child(col)
	return panel


func _on_cmd_search(q: String) -> void:
	builder_cmd_list.clear()
	var query := q.strip_edges().to_lower()
	if query.length() < 2:
		return
	var cat := get_node_or_null("/root/ScryfallCatalog")
	if cat == null:
		return
	var n := 0
	for key in cat.cards_by_name.keys():
		if str(key).find(query) >= 0:
			var row: Dictionary = cat.cards_by_name[key]
			var tl := str(row.get("type_line", ""))
			if tl.find("Legendary") < 0 and tl.find("Background") < 0:
				continue
			builder_cmd_list.add_item(str(row.get("name", key)))
			n += 1
			if n >= 20:
				break


func _on_cmd_pick(idx: int) -> void:
	builder_cmd_name = builder_cmd_list.get_item_text(idx)
	builder_cmd.text = builder_cmd_name
	if builder_name.text.strip_edges() == "":
		builder_name.text = builder_cmd_name
	_update_builder_count()


func _on_add_card(card_name: String) -> void:
	var n := DeckText.sanitize_name(card_name)
	if n == "":
		return
	builder_cards[n] = int(builder_cards.get(n, 0)) + 1
	builder_card.text = ""
	_refresh_builder_cards()


func _on_remove_card() -> void:
	var sel := builder_card_list.get_selected_items()
	if sel.is_empty():
		return
	var label := builder_card_list.get_item_text(sel[0])
	var nm := label
	var x := label.rfind(" x")
	if x > 0:
		nm = label.substr(0, x)
	builder_cards.erase(nm)
	_refresh_builder_cards()


func _refresh_builder_cards() -> void:
	builder_card_list.clear()
	for k in builder_cards.keys():
		builder_card_list.add_item("%s x%d" % [str(k), int(builder_cards[k])])
	_update_builder_count()


func _update_builder_count() -> void:
	var n := 0
	for k in builder_cards.keys():
		n += int(builder_cards[k])
	var cmd := builder_cmd_name if builder_cmd_name != "" else "no commander"
	builder_count.text = "%d / 99 library  ·  commander: %s  ·  total %d/100" % [n, cmd, n + (1 if builder_cmd_name != "" else 0)]


func _on_save_builder() -> void:
	if builder_cmd_name == "":
		builder_count.text = "Pick a commander first."
		return
	var deck := NormalizedDeck.new()
	deck.source = "builder"
	deck.name = builder_name.text.strip_edges()
	if deck.name == "":
		deck.name = builder_cmd_name
	deck.add_commander(builder_cmd_name, 1)
	for k in builder_cards.keys():
		deck.add_main(str(k), int(builder_cards[k]))
	var resolved: Dictionary = ScryfallResolver.new().resolve(deck, true)
	var val: Dictionary = CommanderValidator.new().validate(deck, resolved.get("rows", {}), resolved.get("unresolved", PackedStringArray()))
	DeckStore.new().save(deck, resolved.get("rows", {}), val)
	_show("gallery")


func _toggle_music() -> void:
	if settings_music:
		settings_music.text = "Music: Off" if settings_music.text.ends_with("On") else "Music: On"


func _toggle_sfx() -> void:
	if settings_sfx:
		settings_sfx.text = "SFX: Off" if settings_sfx.text.ends_with("On") else "SFX: On"


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_exit() -> void:
	get_tree().quit()
