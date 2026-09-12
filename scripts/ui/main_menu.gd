extends Control

const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const PANEL := Color(0.09, 0.10, 0.11, 0.96)
const YOU_EMBER := Color(0.42, 0.18, 0.08)
const RivalAI := preload("res://scripts/rival_ai.gd")

var pages: Dictionary = {}
var current: String = "hub"
var status_label: Label
var vs_player_id: String = "builtin:krenko"
var vs_bot_id: String = "builtin:talrand"
var vs_diff: int = 1
var mp_code_edit: LineEdit
var mp_ip_edit: LineEdit
var mp_status: Label
var mp_roster: Label
var gallery_grid: GridContainer
var import_overlay: ImportOverlay
var builder_cmd: LineEdit
var builder_cmd_list: ItemList
var builder_card: LineEdit
var builder_card_list: ItemList
var builder_name: LineEdit
var builder_count: Label
var builder_cmd_name: String = ""
var builder_cards: Dictionary = {}
var settings_music: Button
var settings_sfx: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.06)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	_build_hub()
	_build_vs()
	_build_mp()
	_build_library()
	_build_gallery()
	_build_builder()
	_build_settings()
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


func _page() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	p.offset_left = 80
	p.offset_right = -80
	p.offset_top = 40
	p.offset_bottom = -40
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL
	st.set_corner_radius_all(16)
	st.set_border_width_all(2)
	st.border_color = GOLD.darkened(0.25)
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 22
	st.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", st)
	add_child(p)
	return p


func _col(parent: Node) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 12)
	parent.add_child(c)
	return c


func _title(parent: Node, text: String, size: int = 42) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	parent.add_child(l)
	return l


func _sub(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _btn(text: String, cb: Callable, min_w: float = 360, gold := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	var st := StyleBoxFlat.new()
	st.bg_color = GOLD.darkened(0.15) if gold else Color(0.16, 0.17, 0.18)
	st.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_color_override("font_color", Color(0.12, 0.10, 0.04) if gold else INK)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _back_row(parent: Node, extra: Button = null) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("Back", _show.bind("hub"), 160))
	if extra:
		row.add_child(extra)
	parent.add_child(row)


func _build_hub() -> void:
	var p := _page()
	pages["hub"] = p
	var c := _col(p)
	_title(c, "AETHERFOLD")
	_sub(c, "Commander  ·  1v1 table")
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	c.add_child(spacer)
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 10)
	wrap.add_child(_btn("Vs. AI", _show.bind("vs"), 400, true))
	wrap.add_child(_btn("Multiplayer", _show.bind("mp"), 400))
	wrap.add_child(_btn("Library Builder", _show.bind("library"), 400))
	wrap.add_child(_btn("Menu", _show.bind("settings"), 400))
	wrap.add_child(_btn("Exit Game", _on_exit, 400))
	c.add_child(wrap)
	status_label = _sub(c, "Play Krenko against a Talrand bot, or bring your own decks.")


func _build_vs() -> void:
	var p := _page()
	pages["vs"] = p
	var c := _col(p)
	_title(c, "Vs. AI", 32)
	_sub(c, "Pick a deck for you and the bot, then set difficulty.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	c.add_child(row)
	row.add_child(_vs_column("Your deck", true))
	row.add_child(_vs_column("Bot deck", false))
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var dl := Label.new()
	dl.text = "Bot difficulty"
	dl.add_theme_color_override("font_color", GOLD)
	diff_row.add_child(dl)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(220, 36)
	for i in 4:
		opt.add_item("%s — %s" % [RivalAI.label(i), ["Misses plays", "Land + a spell", "Dumps cheap spells", "Attacks and counters"][i]], i)
	opt.select(1)
	opt.item_selected.connect(func(i): vs_diff = i)
	diff_row.add_child(opt)
	c.add_child(diff_row)
	_back_row(c, _btn("Start Match", _on_start_vs, 200, true))


func _vs_column(title: String, is_player: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	var list := VBoxContainer.new()
	list.name = "PlayerList" if is_player else "BotList"
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	col.add_child(scroll)
	return col


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


func _build_mp() -> void:
	var p := _page()
	pages["mp"] = p
	var c := _col(p)
	_title(c, "Multiplayer", 32)
	_sub(c, "Peer-to-peer. Create a room code or join one on the same network.")
	mp_code_edit = LineEdit.new()
	mp_code_edit.placeholder_text = "Room code (leave blank to generate)"
	mp_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_code_edit.max_length = 8
	c.add_child(mp_code_edit)
	mp_ip_edit = LineEdit.new()
	mp_ip_edit.placeholder_text = "Host IP (optional — LAN discovery uses the code)"
	mp_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(mp_ip_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("Create room", _on_mp_host, 200, true))
	row.add_child(_btn("Join room", _on_mp_join, 200))
	c.add_child(row)
	mp_status = _sub(c, "Not connected.")
	mp_roster = _sub(c, "")
	_back_row(c, _btn("Start Match", _on_mp_start, 200, true))


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


func _build_library() -> void:
	var p := _page()
	pages["library"] = p
	var c := _col(p)
	_title(c, "Library", 32)
	_sub(c, "Import a list, build a deck, or browse what you’ve saved.")
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 10)
	wrap.add_child(_btn("Import from URL / list", _on_open_import, 420, true))
	wrap.add_child(_btn("Library Builder", _show.bind("builder"), 420))
	wrap.add_child(_btn("Library Gallery", _show.bind("gallery"), 420))
	c.add_child(wrap)
	_back_row(c)


func _on_open_import() -> void:
	if import_overlay:
		import_overlay.auto_play = false
		import_overlay.open()


func _on_imported_saved(_deck = null, _rows = null) -> void:
	_show("gallery")


func _build_gallery() -> void:
	var p := _page()
	pages["gallery"] = p
	var c := _col(p)
	_title(c, "Library Gallery", 32)
	_sub(c, "Commander art is the deck icon. Click the name to rename.")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	gallery_grid = GridContainer.new()
	gallery_grid.columns = 3
	gallery_grid.add_theme_constant_override("h_separation", 14)
	gallery_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(gallery_grid)
	c.add_child(scroll)
	_back_row(c, _btn("Library home", _show.bind("library"), 180))


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


func _build_builder() -> void:
	var p := _page()
	pages["builder"] = p
	var c := _col(p)
	_title(c, "Library Builder", 32)
	_sub(c, "Pick a commander, then add cards by name. Singleton Commander rules apply when you save.")
	builder_name = LineEdit.new()
	builder_name.placeholder_text = "Deck name (defaults to commander)"
	c.add_child(builder_name)
	builder_cmd = LineEdit.new()
	builder_cmd.placeholder_text = "Search commander…"
	builder_cmd.text_changed.connect(_on_cmd_search)
	c.add_child(builder_cmd)
	builder_cmd_list = ItemList.new()
	builder_cmd_list.custom_minimum_size = Vector2(0, 90)
	builder_cmd_list.item_selected.connect(_on_cmd_pick)
	c.add_child(builder_cmd_list)
	builder_card = LineEdit.new()
	builder_card.placeholder_text = "Add card name, then press Enter"
	builder_card.text_submitted.connect(_on_add_card)
	c.add_child(builder_card)
	builder_card_list = ItemList.new()
	builder_card_list.size_flags_vertical = SIZE_EXPAND_FILL
	builder_card_list.custom_minimum_size = Vector2(0, 180)
	c.add_child(builder_card_list)
	builder_count = Label.new()
	builder_count.add_theme_color_override("font_color", GOLD)
	builder_count.text = "0 / 99 library  ·  no commander"
	c.add_child(builder_count)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(_btn("Remove selected", _on_remove_card, 180))
	row.add_child(_btn("Save to Gallery", _on_save_builder, 200, true))
	c.add_child(row)
	_back_row(c, _btn("Library home", _show.bind("library"), 180))


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


func _build_settings() -> void:
	var p := _page()
	pages["settings"] = p
	var c := _col(p)
	_title(c, "Menu", 32)
	_sub(c, "Audio and display.")
	settings_music = _btn("Music: On", _toggle_music, 280)
	settings_sfx = _btn("SFX: On", _toggle_sfx, 280)
	c.add_child(settings_music)
	c.add_child(settings_sfx)
	c.add_child(_btn("Toggle fullscreen", _toggle_fullscreen, 280))
	_sub(c, "Aetherfold  ·  Godot 4.7  ·  fan Commander table")
	_back_row(c)


func _toggle_music() -> void:
	var bus := AudioServer.get_bus_index("Master")
	var mute := not AudioServer.is_bus_mute(bus)
	# music is on table; toggle Master here as a coarse control
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
