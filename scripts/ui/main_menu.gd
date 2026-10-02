extends Control

const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const PANEL := Color(0.09, 0.10, 0.11, 0.96)
const YOU_EMBER := Color(0.42, 0.18, 0.08)

var pages: Dictionary = {}
var current: String = "hub"
var status_label: Label
var vs_player_id: String = "builtin:krenko"
var vs_bot_id: String = "builtin:talrand"
var mp_code_edit: LineEdit
var mp_ip_edit: LineEdit
var mp_status: Label
var gallery_grid: GridContainer
var import_overlay: ImportOverlay
var page_dim: ColorRect
var starter_msg: String = ""
var starter_label: Label
var vs_preview: TextureRect
var vs_preview_card: Dictionary = {}
var builder_cmd: LineEdit
var builder_cmd_list: ItemList
var builder_card: LineEdit
var builder_card_list: ItemList
var builder_name: LineEdit
var builder_count: Label
var builder_cmd_name: String = ""
var builder_cards: Dictionary = {}
var settings_music: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.06)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	## Every page sits on the animated mana-wheel sky (dimmed), so the whole menu looks like the title screen.
	_backdrop = Backdrop.new()
	add_child(_backdrop)
	page_dim = ColorRect.new()
	page_dim.color = Color(0.02, 0.02, 0.04, 0.68)
	page_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	page_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_dim)
	## The card catalog loads in the background at startup (T-009): show the sky and wait for it before building pages.
	var cat_gate := get_node_or_null("/root/ScryfallCatalog")
	if cat_gate != null and bool(cat_gate.get("is_loading")):
		var loading := Label.new()
		loading.text = "Loading cards…"
		loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		loading.add_theme_font_size_override("font_size", 28)
		loading.add_theme_color_override("font_color", GOLD)
		loading.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(loading)
		await cat_gate.catalog_ready
		loading.queue_free()
	DeckStore.new().purge_test_decks()  ## once per launch; the deck lists only read (T-010)
	_install_precons()
	_build_hub()
	_build_vs()
	_build_mp()
	_build_library()
	_build_gallery()
	_build_builder()
	_build_settings()
	import_overlay = ImportOverlay.new()
	add_child(import_overlay)
	import_overlay.auto_play = false
	import_overlay.play_imported.connect(_on_imported_saved)
	import_overlay.deck_saved.connect(_on_imported_saved)
	var net := _net()
	if net and not net.status_changed.is_connected(_on_net_status):
		net.status_changed.connect(_on_net_status)
		net.peer_ready.connect(_on_peer_ready)
		net.lobby_changed.connect(_on_lobby_changed)
		net.countdown_changed.connect(_on_countdown)
		net.match_begin.connect(_start_table)
	_show("hub")


## The eight Commander precon starter decks ship with the game (res://data/precons); any that aren't saved on
## this computer yet are saved now, and the starter decks they replaced are deleted.
func _install_precons() -> void:
	var res: Dictionary = PreconDecks.new().install()
	starter_msg = "Starter decks: %d Commander precons ready." % PreconDecks.new().saved_count()
	if int(res.get("removed", 0)) > 0:
		starter_msg += " (Removed %d old starter decks.)" % int(res.get("removed", 0))
	print("[precons] ", JSON.stringify(res))


func _app() -> Node:
	return get_node_or_null("/root/AppState")


func _net() -> Node:
	return get_node_or_null("/root/GameNet")


func _show(name: String) -> void:
	current = name
	if page_dim != null:
		page_dim.visible = name != "hub"
	if _backdrop != null:
		_backdrop.wheel_strength = 1.0 if name == "hub" else 0.45
	for k in pages.keys():
		pages[k].visible = (str(k) == name)
	if name == "settings" and settings_music != null:
		var mus := get_node_or_null("/root/Music")
		settings_music.text = "Music: Off" if (mus != null and mus.muted) else "Music: On"
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
	st.bg_color = Color(0.07, 0.065, 0.06, 0.88)
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
	st.bg_color = GOLD.darkened(0.15) if gold else Color(0.23, 0.20, 0.15, 0.95)
	st.border_color = Color(0.55, 0.45, 0.22, 0.9)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", st)
	## Hover / focus / press: the button lights up gold (a soft glow), the same as the painted front menu.
	var hv := st.duplicate() as StyleBoxFlat
	hv.bg_color = GOLD.lightened(0.1) if gold else Color(0.30, 0.26, 0.12)
	hv.border_color = Color(0.97, 0.82, 0.38, 0.95)
	hv.set_border_width_all(2)
	hv.shadow_color = Color(0.97, 0.78, 0.25, 0.35)
	hv.shadow_size = 8
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", hv)
	var pr := hv.duplicate() as StyleBoxFlat
	pr.bg_color = hv.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.85) if not gold else Color(0.1, 0.08, 0.02))
	b.add_theme_color_override("font_focus_color", Color(1, 0.97, 0.85) if not gold else Color(0.1, 0.08, 0.02))
	b.add_theme_color_override("font_color", Color(0.12, 0.10, 0.04) if gold else INK)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _back_row(parent: Node, extra: Node = null) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("Back", _show.bind("hub"), 160))
	if extra:
		row.add_child(extra)
	parent.add_child(row)


## The title screen: an animated Magic-themed backdrop (MagicBackdrop: stars, a turning mana wheel, drifting mana
## motes), the game's name over the wheel, and one button per page.
const HUB_ENTRIES := [
	{"id": "vs", "text": "Play vs. AI", "tip": "Play a Commander duel against the AI", "gold": true},
	{"id": "mp", "text": "Multiplayer", "tip": "Host or join a table on your network", "gold": false},
	{"id": "library", "text": "Library", "tip": "Import, build and browse your decks", "gold": false},
	{"id": "settings", "text": "Settings", "tip": "Music, volume and fullscreen", "gold": false},
	{"id": "exit", "text": "Exit Game", "tip": "Quit", "gold": false},
]

const Backdrop := preload("res://scripts/ui/magic_backdrop.gd")
var _backdrop: Control


func _build_hub() -> void:
	var p := Control.new()
	p.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	pages["hub"] = p
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var name_lab := Label.new()
	name_lab.text = "AETHERFOLD"
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.add_theme_font_size_override("font_size", 88)
	name_lab.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	name_lab.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.30))
	name_lab.add_theme_constant_override("outline_size", 14)
	name_lab.add_theme_color_override("font_shadow_color", Color(0.45, 0.30, 0.85, 0.55))
	name_lab.add_theme_constant_override("shadow_offset_x", 0)
	name_lab.add_theme_constant_override("shadow_offset_y", 6)
	col.add_child(name_lab)
	var tag := Label.new()
	tag.text = "·  A  C O M M A N D E R   T A B L E  ·"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color(0.80, 0.76, 0.95))
	col.add_child(tag)
	col.add_child(_mana_pips())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)
	for spec in HUB_ENTRIES:
		var row := CenterContainer.new()
		var b := _hub_btn(str(spec.text), _on_hub_button.bind(str(spec.id)), bool(spec.gold))
		b.tooltip_text = str(spec.tip)
		row.add_child(b)
		col.add_child(row)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.95))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_label.text = "Play Krenko against a Talrand bot, or bring your own decks."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	status_label.offset_top = -34
	status_label.offset_bottom = -8
	p.add_child(status_label)


## The five colors of mana as little glowing orbs under the title.
func _mana_pips() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for c in Backdrop.MANA:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(22, 22)
		var st := StyleBoxFlat.new()
		st.bg_color = c
		st.set_corner_radius_all(11)
		st.set_border_width_all(2)
		st.border_color = GOLD
		st.shadow_color = Color(c.r, c.g, c.b, 0.6)
		st.shadow_size = 8
		pip.add_theme_stylebox_override("panel", st)
		row.add_child(pip)
	return row


## A title-screen button: dark violet with a gold rim that blazes on hover.
func _hub_btn(text: String, cb: Callable, gold: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	var fill := Color(0.13, 0.08, 0.22, 0.90)
	var rim := Color(0.62, 0.50, 0.28, 0.9)
	if gold:
		fill = Color(0.52, 0.38, 0.10, 0.95)
		rim = Color(0.97, 0.82, 0.38, 1.0)
	var normal := _hub_style(fill, rim, false)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", _hub_style(fill.lightened(0.18), Color(1.0, 0.90, 0.55), true))
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("pressed", _hub_style(fill.lightened(0.30), Color(1.0, 0.95, 0.70), true))
	b.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82) if gold else Color(0.90, 0.88, 0.98))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.92))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 0.92))
	b.pressed.connect(cb)
	return b


func _hub_style(fill: Color, border: Color, lit: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = fill
	st.border_color = border
	st.set_border_width_all(3 if lit else 2)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0.75, 0.55, 1.0, 0.45) if lit else Color(0, 0, 0, 0.35)
	st.shadow_size = 14 if lit else 4
	return st


func _on_hub_button(id: String) -> void:
	match id:
		"vs", "mp", "library", "settings":
			_show(id)
		"exit":
			_on_exit()


func _build_vs() -> void:
	var p := _page()
	pages["vs"] = p
	var c := _col(p)
	_title(c, "Vs. AI", 32)
	_sub(c, "Pick a deck for you and for the bot.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	c.add_child(row)
	row.add_child(_vs_column("Your deck", true))
	row.add_child(_vs_column("Bot deck", false))
	## Hover a deck to see its commander here, as the full card.
	var prev_box := Control.new()
	prev_box.custom_minimum_size = Vector2(300, 0)
	vs_preview = TextureRect.new()
	vs_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vs_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	vs_preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vs_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vs_preview.visible = false
	prev_box.add_child(vs_preview)
	prev_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(prev_box)
	var cat0 := get_node_or_null("/root/ScryfallCatalog")
	if cat0 != null and cat0.has_signal("art_updated"):
		cat0.art_updated.connect(func(_cid: String) -> void: _update_vs_preview())
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
	## Three groups: the two built-in starters, the Commander precons (in Moxfield's order), then your own decks.
	var groups := {"builtin": [], "precon": [], "mine": []}
	for rec in DeckCatalog.all_choices():
		var r: Dictionary = rec
		if bool(r.get("builtin", false)):
			(groups.builtin as Array).append(r)
		elif str(r.get("source", "")) == PreconDecks.SOURCE:
			(groups.precon as Array).append(r)
		else:
			(groups.mine as Array).append(r)
	(groups.precon as Array).sort_custom(func(a, b) -> bool: return int(a.get("precon_order", 99)) < int(b.get("precon_order", 99)))
	for g in [["builtin", "Starters"], ["precon", "Commander precons"], ["mine", "Your decks"]]:
		var recs: Array = groups[g[0]]
		if recs.is_empty():
			continue
		var head := Label.new()
		head.text = str(g[1])
		head.add_theme_color_override("font_color", GOLD)
		head.add_theme_font_size_override("font_size", 15)
		list.add_child(head)
		for rec2 in recs:
			list.add_child(_deck_button(rec2, selected, is_player))


func _deck_button(rec: Dictionary, selected: String, is_player: bool) -> Button:
	var id := str(rec.get("id", ""))
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	b.toggle_mode = true
	b.button_pressed = id == selected
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var nm := str(rec.get("name", DeckCatalog.commander_name(rec)))
	var cmd := DeckCatalog.commander_name(rec)
	if str(rec.get("source", "")) == PreconDecks.SOURCE:
		b.text = "  %s\n  %s  ·  %s" % [nm, cmd, str(rec.get("precon_set", "Precon"))]
	elif bool(rec.get("builtin", false)):
		b.text = "  %s  (starter)" % nm
	else:
		b.text = "  %s" % nm
	b.tooltip_text = "%s — commander: %s" % [nm, cmd]
	var tex := _cmd_tex(rec)
	if tex:
		b.icon = tex
		b.expand_icon = true
	b.pressed.connect(_on_pick_vs.bind(id, is_player))
	var cmd_card := DeckCatalog.commander_row(rec)
	b.mouse_entered.connect(_show_vs_preview.bind(cmd_card))
	b.mouse_exited.connect(_hide_vs_preview)
	return b


## Hovering a deck in the pick lists shows its commander as a full card beside the lists.
func _show_vs_preview(card: Dictionary) -> void:
	if vs_preview == null:
		return
	vs_preview_card = card
	_update_vs_preview()
	vs_preview.visible = vs_preview.texture != null


func _update_vs_preview() -> void:
	var cat := get_node_or_null("/root/ScryfallCatalog")
	if cat == null or vs_preview_card.is_empty():
		return
	var t: Texture2D = cat.texture_for(vs_preview_card, "normal")
	if t != null:
		vs_preview.texture = t
		vs_preview.visible = true


func _hide_vs_preview() -> void:
	vs_preview_card = {}
	if vs_preview != null:
		vs_preview.visible = false


func _on_pick_vs(id: String, is_player: bool) -> void:
	if is_player:
		vs_player_id = id
	else:
		vs_bot_id = id
	_refresh_vs_lists()


func _cmd_tex(rec: Dictionary) -> Texture2D:
	var local := str(rec.get("commander_image", ""))
	if local != "" and FileAccess.file_exists(local):
		var img := Image.new()
		if img.load(local) == OK:
			return ImageTexture.create_from_image(img)
	var cat := get_node_or_null("/root/ScryfallCatalog")
	if cat == null or not cat.has_method("texture_for"):
		return null
	return cat.texture_for(DeckCatalog.commander_row(rec), "small")


func _on_start_vs() -> void:
	var app := _app()
	if app:
		app.player_deck_id = vs_player_id
		app.rival_deck_id = vs_bot_id
		app.skip_ai = false
		app.mp_role = ""
		app.you_seat = 0
	_start_table()


func _start_table() -> void:
	get_tree().change_scene_to_file("res://scenes/table.tscn")


var mp_connect_box: VBoxContainer
var mp_lobby_box: VBoxContainer
var mp_name_edit: LineEdit
var mp_deck_pick: OptionButton
var mp_roster_box: VBoxContainer
var mp_ready_btn: Button
var mp_count_label: Label
var _mp_choices: Array = []
var _mp_in_lobby := false


func _build_mp() -> void:
	var p := _page()
	pages["mp"] = p
	var c := _col(p)
	_title(c, "Multiplayer", 32)
	## Stage 1: connect. Same network: a room code. Over the internet: the host's online address.
	mp_connect_box = VBoxContainer.new()
	mp_connect_box.add_theme_constant_override("separation", 12)
	c.add_child(mp_connect_box)
	_sub(mp_connect_box, "Play on the same network with a room code, or over the internet: host a room, send your friend the online address shown, and they type it in below.")
	mp_code_edit = LineEdit.new()
	mp_code_edit.placeholder_text = "Room code (leave blank to generate)"
	mp_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_code_edit.max_length = 8
	mp_connect_box.add_child(mp_code_edit)
	mp_ip_edit = LineEdit.new()
	mp_ip_edit.placeholder_text = "Host's online address, e.g. 203.0.113.5 (blank = same network, uses the room code)"
	mp_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_connect_box.add_child(mp_ip_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_btn("Create room", _on_mp_host, 200, true))
	row.add_child(_btn("Join room", _on_mp_join, 200))
	row.add_child(_btn("Copy code", _on_mp_copy, 140))
	row.add_child(_btn("Copy address", _on_mp_copy_address, 160))
	mp_connect_box.add_child(row)
	## Stage 2: the lobby. Pick a deck, press Ready; when everyone is ready the match starts after a short countdown.
	mp_lobby_box = VBoxContainer.new()
	mp_lobby_box.add_theme_constant_override("separation", 10)
	mp_lobby_box.visible = false
	c.add_child(mp_lobby_box)
	_sub(mp_lobby_box, "Pick your deck, then press Ready. When every player is ready the match starts in 3 seconds.")
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	var nl := Label.new()
	nl.text = "Your name"
	nl.add_theme_color_override("font_color", GOLD)
	name_row.add_child(nl)
	mp_name_edit = LineEdit.new()
	mp_name_edit.custom_minimum_size = Vector2(220, 0)
	mp_name_edit.max_length = 20
	mp_name_edit.text_submitted.connect(func(_t: String) -> void: _mp_send_profile())
	mp_name_edit.focus_exited.connect(_mp_send_profile)
	name_row.add_child(mp_name_edit)
	var dl := Label.new()
	dl.text = "Deck"
	dl.add_theme_color_override("font_color", GOLD)
	name_row.add_child(dl)
	mp_deck_pick = OptionButton.new()
	mp_deck_pick.custom_minimum_size = Vector2(380, 0)
	mp_deck_pick.item_selected.connect(func(_i: int) -> void: _mp_send_profile())
	name_row.add_child(mp_deck_pick)
	mp_lobby_box.add_child(name_row)
	mp_roster_box = VBoxContainer.new()
	mp_roster_box.add_theme_constant_override("separation", 6)
	mp_roster_box.size_flags_vertical = SIZE_EXPAND_FILL
	mp_lobby_box.add_child(mp_roster_box)
	mp_count_label = Label.new()
	mp_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_count_label.add_theme_font_size_override("font_size", 30)
	mp_count_label.add_theme_color_override("font_color", GOLD)
	mp_lobby_box.add_child(mp_count_label)
	var ready_row := HBoxContainer.new()
	ready_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ready_row.add_theme_constant_override("separation", 12)
	mp_ready_btn = _btn("Ready", _on_mp_ready, 220, true)
	ready_row.add_child(mp_ready_btn)
	ready_row.add_child(_btn("Leave room", _on_mp_leave, 180))
	ready_row.add_child(_btn("Copy address", _on_mp_copy_address, 170))
	ready_row.add_child(_btn("Copy code", _on_mp_copy, 140))
	mp_lobby_box.add_child(ready_row)
	mp_status = _sub(c, "Not connected.")
	_back_row(c)


func _mp_show_lobby(on: bool) -> void:
	_mp_in_lobby = on
	mp_connect_box.visible = not on
	mp_lobby_box.visible = on
	if on:
		var app := _app()
		mp_name_edit.text = str(app.player_name) if app != null else "Player"
		_mp_fill_decks()
		_mp_send_profile()
		_on_lobby_changed()


func _mp_fill_decks() -> void:
	mp_deck_pick.clear()
	_mp_choices = DeckCatalog.all_choices()
	var pick := 0
	for i in _mp_choices.size():
		var rec: Dictionary = _mp_choices[i]
		var nm := str(rec.get("name", DeckCatalog.commander_name(rec)))
		var cmd := DeckCatalog.commander_name(rec)
		mp_deck_pick.add_item(nm if nm == cmd else "%s  (%s)" % [nm, cmd], i)
		if str(rec.get("id", "")) == vs_player_id:
			pick = i
	if not _mp_choices.is_empty():
		mp_deck_pick.select(pick)


## The deck record the lobby sends to the host (the full list, so nothing has to exist on the host's computer).
func _mp_current_deck() -> Dictionary:
	var i := mp_deck_pick.selected
	if i < 0 or i >= _mp_choices.size():
		return {}
	return _mp_choices[i]


func _mp_send_profile() -> void:
	var net := _net()
	if net == null or not _mp_in_lobby:
		return
	var rec := _mp_current_deck()
	if rec.is_empty():
		return
	var app := _app()
	if app != null:
		app.set_player_name(mp_name_edit.text)
		mp_name_edit.text = app.player_name
	vs_player_id = str(rec.get("id", vs_player_id))
	net.send_profile(mp_name_edit.text, str(rec.get("name", DeckCatalog.commander_name(rec))), rec)


func _on_mp_host() -> void:
	var net := _net()
	if net == null:
		return
	var wanted := mp_code_edit.text
	var code: String = net.host_room(wanted)
	if code != "":
		mp_code_edit.text = code
		_mp_show_lobby(true)
		var ips := ", ".join(net.local_ips())
		mp_status.text = net.last_status + "\nSame network instead? Your LAN IP: %s" % ips


func _on_mp_join() -> void:
	var net := _net()
	if net == null:
		return
	var code := mp_code_edit.text.strip_edges()
	if code == "" and mp_ip_edit.text.strip_edges() == "":
		mp_status.text = "Enter a room code (same network) or the host's online address."
		return
	net.join_room(code, mp_ip_edit.text)
	mp_status.text = net.last_status


func _on_mp_leave() -> void:
	var net := _net()
	if net != null:
		net.leave()
	_mp_show_lobby(false)
	mp_status.text = "Not connected."


func _on_net_status(text: String) -> void:
	if mp_status:
		mp_status.text = text


## A guest is connected: show the lobby. (The host showed it when it created the room.)
func _on_peer_ready() -> void:
	var net := _net()
	if net and net.role == "client" and not _mp_in_lobby:
		_mp_show_lobby(true)
	_on_lobby_changed()


func _on_lobby_changed() -> void:
	var net := _net()
	if net == null or mp_roster_box == null or not _mp_in_lobby:
		return
	if net.role == "":
		_mp_show_lobby(false)
		return
	while mp_roster_box.get_child_count() > 0:
		var ch := mp_roster_box.get_child(0)
		mp_roster_box.remove_child(ch)
		ch.queue_free()
	var me: int = net.my_id()
	var i_am_ready := false
	for r in net.roster:
		var e: Dictionary = r
		var line := Label.new()
		var ok := bool(e.get("ready", false))
		var who := str(e.get("name", "Player"))
		if int(e.get("id", 0)) == 1:
			who += "  (host)"
		if int(e.get("id", 0)) == me:
			who += "  (you)"
			i_am_ready = ok
		var deck := str(e.get("deck", ""))
		line.text = "%s   —   %s   —   %s" % [who, deck if deck != "" else "choosing a deck…", "READY" if ok else "not ready"]
		line.add_theme_font_size_override("font_size", 20)
		line.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5) if ok else INK)
		mp_roster_box.add_child(line)
	if net.roster.size() < 2:
		var wait := _sub(mp_roster_box, "Waiting for another player to join…")
		wait.add_theme_font_size_override("font_size", 18)
	mp_ready_btn.text = "Not ready" if i_am_ready else "Ready"
	mp_deck_pick.disabled = i_am_ready
	mp_name_edit.editable = not i_am_ready


func _on_countdown(seconds: int) -> void:
	if mp_count_label == null:
		return
	if seconds < 0:
		mp_count_label.text = ""
	elif seconds > 0:
		mp_count_label.text = "Match starts in %d…" % seconds
	else:
		mp_count_label.text = "Starting…"


func _on_mp_ready() -> void:
	var net := _net()
	if net == null:
		return
	var me: int = net.my_id()
	var now := false
	for r in net.roster:
		if int((r as Dictionary).get("id", 0)) == me:
			now = bool((r as Dictionary).get("ready", false))
	net.set_my_ready(not now)


func _build_library() -> void:
	var p := _page()
	pages["library"] = p
	var outer := _col(p)
	## The page scrolls (the import report can be long); Back stays pinned at the bottom.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", 12)
	scroll.add_child(c)
	_title(c, "Library", 32)
	_sub(c, "Import a list, build a deck, or browse what you’ve saved.")
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 10)
	wrap.add_child(_btn("Import from URL / list", _on_open_import, 420, true))
	wrap.add_child(_btn("Library Builder", _show.bind("builder"), 420))
	wrap.add_child(_btn("Library Gallery", _show.bind("gallery"), 420))
	starter_label = Label.new()
	starter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	starter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	starter_label.custom_minimum_size = Vector2(420, 0)
	starter_label.add_theme_color_override("font_color", MUTED)
	starter_label.text = starter_msg
	wrap.add_child(starter_label)
	c.add_child(wrap)
	_back_row(outer)


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
	DeckStore.new().purge_test_decks()
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
	c.add_child(settings_music)
	_volume_row(c)
	c.add_child(_btn("Toggle fullscreen", _toggle_fullscreen, 280))
	_sub(c, "Aetherfold  ·  Godot 4.7  ·  fan Commander table")
	_back_row(c)


func _toggle_music() -> void:
	var music := get_node_or_null("/root/Music")
	if music == null:
		return
	var off: bool = music.toggle_mute()
	if settings_music:
		settings_music.text = "Music: Off" if off else "Music: On"


func _volume_row(parent: Control) -> void:
	var music := get_node_or_null("/root/Music")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var lab := Label.new()
	lab.text = "Volume"
	row.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 1
	sl.value = (music.volume if music != null else 0.7) * 100.0
	sl.custom_minimum_size = Vector2(200, 24)
	row.add_child(sl)
	var pct := Label.new()
	pct.text = "%d%%" % int(sl.value)
	pct.custom_minimum_size = Vector2(44, 0)
	row.add_child(pct)
	sl.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v)
		if music != null:
			music.set_volume(v / 100.0)
	)
	parent.add_child(row)


func _on_mp_copy() -> void:
	var code := ""
	if mp_code_edit:
		code = mp_code_edit.text.strip_edges()
	if code == "":
		if mp_status:
			mp_status.text = "No room code to copy yet."
		return
	DisplayServer.clipboard_set(code)
	if mp_status:
		mp_status.text = "Copied room code %s." % code


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_exit() -> void:
	get_tree().quit()


## Copies the address a friend outside your network types in (your public IP), or your LAN IP if that isn't known.
func _on_mp_copy_address() -> void:
	var net := _net()
	if net == null or mp_status == null:
		return
	var addr: String = net.share_address()
	if addr == "":
		var ips: PackedStringArray = net.local_ips()
		addr = ips[0] if not ips.is_empty() else ""
	if addr == "":
		mp_status.text = "Host a room first; the address appears once it is known."
		return
	DisplayServer.clipboard_set(addr)
	mp_status.text = "Copied address %s. Send it to your friend." % addr
