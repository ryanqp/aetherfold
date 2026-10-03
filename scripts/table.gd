extends Control

const USE_ENGINE := true
const BUILD := 54
const Mats := preload("res://engine/session/playmat_catalog.gd")
const DEBUG_MATCH := true
const MatchStateScript := preload("res://scripts/match_state.gd")
const RivalAI := preload("res://scripts/rival_ai.gd")
const CardFaceScript := preload("res://scripts/card_face.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const AudioIcon := preload("res://scripts/ui/audio_icon.gd")
const RIVAL_TEAL := Color(0.18, 0.42, 0.48)
const YOU_EMBER := Color(0.42, 0.18, 0.08)
const PANEL := Color(0.10, 0.11, 0.12, 0.94)
const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const HAND_CHIP := Vector2(80, 112)
const BOARD_CHIP := Vector2(48, 68)
const SIDE_W := 228
const TURN_GREEN := Color(0.18, 0.78, 0.32)
## The match chrome: bronze header, green-black panels with brass rims (see the concept mock-up).
const BRONZE := Color(0.21, 0.14, 0.08)
const BRONZE_DARK := Color(0.12, 0.08, 0.05)
const BRASS := Color(0.62, 0.48, 0.20)
const PANEL_GREEN := Color(0.04, 0.075, 0.06)
## Gold border: a card you can play right now. Light blue border: the card you have selected.
const PLAYABLE_GOLD := Color(1.0, 0.84, 0.18)
const SELECT_BLUE := Color(0.62, 0.84, 1.0)
const COMMAND_CHIP := Vector2(72, 100)
const TRACK := [["upkeep", "Upkeep"], ["draw", "Draw"], ["main1", "Main 1"], ["combat", "Combat"], ["main2", "Main 2"], ["end", "End"]]
const TURN_RED := Color(0.86, 0.16, 0.14)
const ATTACK_RED := Color(0.92, 0.22, 0.16)
const BLOCK_BLUE := Color(0.30, 0.62, 0.98)

var state = MatchStateScript.new()
var session = null
var header_label: Label
var you_life: Label
var rival_life: Label
var rival_title_label: Label
var you_title_label: Label
var inspector_art: TextureRect
var inspector_title: Label
var inspector_type: Label
var inspector_text: Label
var log_label: Label
var audio_button: Button
var audio_panel: PanelContainer
var quit_dialog: ConfirmationDialog
var music
## Sound effects were removed (they cost frames); _tap_sfx stays as a no-op so the call sites don't change.
var sfx = null
var you_zones: Dictionary = {}
var rival_zones: Dictionary = {}
var hand_row: HBoxContainer
var pile_labels: Dictionary = {}
var menu_overlay: ColorRect
## Menu controls that only make sense against the bot: hidden in online matches (new game, import).
var menu_solo_nodes: Array = []
var turn_border: Panel
var hover_wrap: CenterContainer
var hover_art: TextureRect
var hover_name: Label
var hover_printed: Control
var you_library_btn: Button
var draw_btn: Button
var deck_btn: Button
var _deck_style: StyleBoxFlat
## Border styles of the cards you can play right now; pulsed every frame so they flash.
var _playable_styles: Array = []
## F3 shows the developer log over the board. Off by default.
var _show_debug := false
var _deck_flashing := false
var phase_chips: Dictionary = {}
var turn_owner_label: Label
var hint_label: Label
var next_turn_btn: Button
var history_panel: PanelContainer
var history_button: Button
var coin_overlay: ColorRect
var coin_face: Label
var coin_status: Label
var coin_call_row: HBoxContainer
var coin_continue: Button
var _coin_state := 0
var history_text: RichTextLabel
var _history_cards: Dictionary = {}
var _history_shown := 0
var declare_btn: Button
var _rival_target: PanelContainer
var _hint_hold := 0.0
var you_cmd_row: HBoxContainer
var rival_cmd_row: HBoxContainer
var play_btn: Button
var ability_box: VBoxContainer
var pass_btn: Button
var attack_btn: Button
var _flash_t := 0.0
var _was_tapped: Dictionary = {}
## Blocks you are lining up while the opponent attacks: attacker id -> Array of your creature ids.
var _pending_blocks: Dictionary = {}
## Your creature picked to block, waiting for you to click an attacker.
var _block_pick: String = ""
## Creatures you have clicked to attack with, while picking attackers.
var _pending_attackers: Array = []
var dice_overlay: ColorRect
var _dice_busy: Dictionary = {}
var mulligan_overlay: ColorRect
var mulligan_hand_row: HBoxContainer
var mulligan_title: Label
var mulligan_sub: Label
var keep_btn: Button
var mulligan_btn: Button
var debug_label: Label
var draw_preview: Control
var draw_preview_host: CenterContainer
var _mulligan_sig := ""
var _mulligan_wait_shown := false
## Online guest: choosing attackers on this screen (the host only hears the final list).
var _guest_attack := false
var import_overlay: ImportOverlay
var you_cmdr_label: Label
var rival_cmdr_label: Label
var gameover_overlay: ColorRect
var gameover_title: Label
var gameover_sub: Label
var gameover_again: Button
var _gameover_shown := false
var _peer_left := false

func _ready() -> void:
	clip_contents = true
	theme = UiStyle.make_theme()  ## the match look (panels, pick screens, buttons, sliders, menus)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	music = get_node_or_null("/root/Music")
	var sfx_node := get_node_or_null("/root/Sfx")
	if sfx_node != null:
		sfx_node.set_match_active(true)  ## tavern, cork and glasses play only during a match
	var cat := _catalog()
	if cat and cat.has_signal("art_updated") and not cat.art_updated.is_connected(_on_art_updated):
		cat.art_updated.connect(_on_art_updated)
	var net := get_node_or_null("/root/GameNet")
	if net and net.has_signal("view_received") and not net.view_received.is_connected(_refresh):
		net.view_received.connect(_refresh)
	add_to_group("aetherfold_table")
	if USE_ENGINE:
		session = GameSession.new()
		session.manual_draw = true
		session.coin_flip = true
		session.debug_enabled = DEBUG_MATCH
		_start_from_app_state()
	else:
		_hydrate_from_scryfall()
	_build()
	import_overlay = ImportOverlay.new()
	add_child(import_overlay)
	import_overlay.play_imported.connect(_on_play_imported)
	_refresh()
	if USE_ENGINE:
		_set_status("Opening hand — Keep or Mulligan.")
	else:
		_set_status("Your turn. Hover a card to enlarge it. Click a card to play it.")

func _catalog() -> Node:
	return get_node_or_null("/root/ScryfallCatalog")


func _board():
	var app := get_node_or_null("/root/AppState")
	if app != null and app.is_mp_client():
		var net := get_node_or_null("/root/GameNet")
		if net != null and net.last_view != null:
			return net.last_view
	if USE_ENGINE and session != null and session.view != null:
		return session.view
	return state


func _start_from_app_state() -> void:
	var app := get_node_or_null("/root/AppState")
	if session == null:
		session = GameSession.new()
		session.manual_draw = true
		session.coin_flip = true
		session.debug_enabled = DEBUG_MATCH
	if app != null:
		session.skip_ai = bool(app.skip_ai)
		session.you_seat = int(app.you_seat)
		if app.is_mp_client():
			return
		var demo = app.make_demo()
		session.start_with_demo(demo)
		return
	session.start_table_demo()


func _on_main_menu() -> void:
	if quit_dialog:
		quit_dialog.popup_centered()
		return
	_leave_to_menu()


func _leave_to_menu() -> void:
	var net := get_node_or_null("/root/GameNet")
	if net and net.has_method("leave"):
		net.leave()
	var app := get_node_or_null("/root/AppState")
	if app:
		app.reset_match_flags()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## A guest's action, run here on the host (which owns the game). Turn actions run "as" the guest's seat, so the same
## code that plays your own turn plays theirs.
func apply_net_action(kind: String, payload: Dictionary, player_id: int) -> void:
	if session == null or session.engine == null:
		return
	if kind == "call_coin":
		if session.match_start == GameSession.MatchStart.COIN_FLIP and session.flip_caller == player_id:
			session.call_coin(bool(payload.get("heads", true)), player_id)
		_refresh()
		return
	## Only keeping or mulliganing is allowed until both players have kept their hands.
	if kind != "keep" and kind != "mulligan" and session.match_start != GameSession.MatchStart.MAIN_GAME:
		return
	if kind == "keep":
		session.keep_hand(player_id)
		_refresh()
		return
	if kind == "put_back":
		session.put_back_for(player_id, int(payload.get("id", 0)))
		_refresh()
		return
	if kind == "mulligan":
		session.take_mulligan(player_id)
		_refresh()
		return
	if kind == "draw":
		if session.engine.state.draw_pending and session.engine.state.active_player_id == player_id:
			session.last_error = ""
			session.as_seat(player_id, func() -> void: session.ack_draw())
			_notice_if_failed(player_id)
		_refresh()
		return
	if kind == "answer":
		session.last_error = ""
		session.answer_prompt(player_id, str(payload.get("kind", "")), null if bool(payload.get("cancel", false)) else payload.get("value", null))
		_notice_if_failed(player_id)
		_refresh()
		return
	if kind == "blocks":
		if session.blocks_seat == player_id:
			session.last_error = ""
			session.as_seat(player_id, func() -> void: session.declare_blocks(payload.get("blocks", {})))
			_notice_if_failed(player_id)
		_refresh()
		return
	if kind == "menu" or kind == "menu_pick":
		if int(session.engine.state.awaiting.get("player_id", -1)) != player_id:
			return
		session.last_error = ""
		var moid := int(payload.get("id", 0))
		session.as_seat(player_id, func() -> void: _net_card_menu(kind, moid, int(payload.get("index", -1)), player_id))
		_notice_if_failed(player_id)
		_refresh()
		return
	## Everything else needs priority: a guest can't act in the host's turn.
	if int(session.engine.state.awaiting.get("player_id", -1)) != player_id:
		return
	session.last_error = ""
	session.as_seat(player_id, func() -> void:
		match kind:
			"pass":
				session.pass_once()
			"end_turn":
				session.end_you_turn()
			"attack":
				session.attack_all()
			"attack_with":
				session.attack_with(payload.get("ids", []))
			"play":
				var oid := int(payload.get("id", 0))
				var zone := str(payload.get("zone", "hand"))
				if zone == "battlefield":
					session.activate_auto(oid)
				elif str(payload.get("kind", "")) == "land":
					session.play_land(oid)
				else:
					session.cast_auto(player_id, oid)
	)
	_notice_if_failed(player_id)
	_refresh()

func _set_status(text: String) -> void:
	if log_label:
		log_label.text = text
	## The side log is easy to miss, so the same message shows beside the phase bar for a few seconds.
	if hint_label and text != "":
		hint_label.text = text
		_hint_hold = 7.0

func _hydrate_from_scryfall() -> void:
	var cat := _catalog()
	if cat == null or not cat.loaded:
		return
	_apply_scryfall(state.you["command"])
	_apply_scryfall(state.you["hand"])
	_apply_scryfall(state.rival["command"])
	_apply_scryfall(state.rival["hand"])
	_apply_scryfall(state.rival["library_cards"])
	_apply_scryfall(state.you["library_cards"])

func _apply_scryfall(pile: Array) -> void:
	var cat := _catalog()
	if cat == null:
		return
	for i in pile.size():
		var card: Dictionary = pile[i]
		var found: Dictionary = cat.find_by_name(str(card.get("name", "")))
		if found.is_empty():
			continue
		card["name"] = found.get("name", card["name"])
		card["type"] = found.get("type_line", card.get("type", ""))
		card["text"] = found.get("oracle_text", card.get("text", ""))
		card["scryfall_id"] = found.get("id", "")
		card["images"] = found.get("images", {})
		card["cmc"] = int(found.get("cmc", card.get("cmc", 0)))
		if found.get("power") != null:
			card["power"] = str(found.get("power"))
		if found.get("toughness") != null:
			card["toughness"] = str(found.get("toughness"))
		pile[i] = card

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.06)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	root.clip_contents = true
	add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_phase_track())

	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.clip_contents = true
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	var board := VBoxContainer.new()
	board.size_flags_horizontal = SIZE_EXPAND_FILL
	board.size_flags_vertical = SIZE_EXPAND_FILL
	board.clip_contents = true
	board.add_theme_constant_override("separation", 2)
	body.add_child(board)

	rival_zones = _make_field(board, RIVAL_TEAL, ["Lands", "Non-creature permanents", "Creatures"])
	you_zones = _make_field(board, YOU_EMBER, ["Creatures", "Non-creature permanents", "Lands"])
	var build_lab := Label.new()
	build_lab.text = "BF-%d" % BUILD
	build_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_lab.add_theme_color_override("font_color", GOLD)
	build_lab.add_theme_font_size_override("font_size", 18)
	build_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(build_lab)
	board.add_child(_build_hand())
	body.add_child(_build_sidebar())
	_build_turn_border()
	_build_hover()
	_build_deck_pile()
	_build_chat()
	_build_history_panel()
	_build_dice_tray()
	_build_menu()
	_build_gameover()
	_build_quit_confirm()
	_build_draw_preview()
	_build_mulligan_overlay()
	_build_coin_overlay()
	_build_debug_label()
	_paint_turn_border()

func _build_header() -> Control:
	## A bronze bar (darker at the bottom) with a brass line under it. Left: the turn; middle: the turn actions;
	## right: history / audio / dice, then the menus. Thin brass dividers keep the groups apart.
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	var bar := PanelContainer.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.20, 0.13, 0.08))
	grad.set_color(1, Color(0.09, 0.06, 0.04))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 4
	gtex.height = 64
	var style := StyleBoxTexture.new()
	style.texture = gtex
	style.content_margin_left = 16
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_label = Label.new()
	header_label.size_flags_horizontal = SIZE_EXPAND_FILL
	## Clipped so a long header ("... · GAME OVER") can never make the row wider than the window and push the sidebar off-screen.
	header_label.custom_minimum_size = Vector2(0, 0)
	header_label.clip_text = true
	header_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header_label.add_theme_font_size_override("font_size", 19)
	header_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78))
	header_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	header_label.add_theme_constant_override("outline_size", 4)
	row.add_child(header_label)
	## Turn actions
	pass_btn = _header_button("Next phase ▶", Color(0.20, 0.45, 0.20), Color(0.95, 1.0, 0.92), _on_next_phase, 150)
	pass_btn.tooltip_text = "Move to the next part of the turn: Upkeep, Draw, Main 1, Combat, Main 2, End."
	row.add_child(pass_btn)
	attack_btn = _header_button("Attack", Color(0.58, 0.16, 0.12), Color(0.98, 0.94, 0.88), _on_attack, 100)
	attack_btn.tooltip_text = "Attack: double-click the creatures to send, then press this (or right-click one and choose Attack). Space passes priority. Enter ends the turn."
	row.add_child(attack_btn)
	next_turn_btn = _header_button("End turn", BRONZE, INK, _on_end_turn, 104)
	next_turn_btn.tooltip_text = "Skip the rest of your turn. The rival plays, then it is your turn again."
	row.add_child(next_turn_btn)
	row.add_child(_header_divider())
	## Table tools
	history_button = _header_button("Hide history", BRONZE, INK, _toggle_history, 116)
	row.add_child(history_button)
	audio_button = _header_button("Audio", BRONZE, INK, _toggle_audio, 80)
	audio_button.tooltip_text = "Master, music and effects volume"
	row.add_child(audio_button)
	row.add_child(_header_button("Dice", BRONZE, INK, _on_dice, 72))
	row.add_child(_header_divider())
	## Menus
	row.add_child(_header_button("Menu", BRONZE, INK, _on_menu, 76))
	row.add_child(_header_button("Main menu", BRONZE, INK, _on_main_menu, 106))
	row.add_child(_header_divider())
	var build := Label.new()
	build.text = "BF-%d" % BUILD
	build.add_theme_font_size_override("font_size", 12)
	build.add_theme_color_override("font_color", Color(0.65, 0.55, 0.38))
	row.add_child(build)
	bar.add_child(row)
	holder.add_child(bar)
	var line := ColorRect.new()
	line.color = BRASS
	line.custom_minimum_size = Vector2(0, 2)
	holder.add_child(line)
	return holder


func _header_divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(0.62, 0.48, 0.20, 0.55)
	d.custom_minimum_size = Vector2(2, 24)
	d.size_flags_vertical = SIZE_SHRINK_CENTER
	return d


func _header_button(text: String, bg: Color, fg: Color, cb: Callable, width: float = 120) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 34)
	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.set_corner_radius_all(5)
	n.set_border_width_all(1)
	n.border_color = BRASS
	n.content_margin_left = 10
	n.content_margin_right = 10
	b.add_theme_stylebox_override("normal", n)
	var hv := n.duplicate() as StyleBoxFlat
	hv.bg_color = bg.lightened(0.12)
	hv.border_color = GOLD
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_color_override("font_color", fg)
	b.pressed.connect(cb)
	return b

func _make_field(parent: Control, tint: Color, zone_order: Array) -> Dictionary:
	var field := PanelContainer.new()
	field.size_flags_vertical = SIZE_EXPAND_FILL
	field.clip_contents = false
	var style := StyleBoxFlat.new()
	style.bg_color = tint.darkened(0.45)
	style.border_color = tint.lightened(0.15)
	style.set_border_width_all(2)
	field.add_theme_stylebox_override("panel", style)
	## Felt playmat behind the zones; the picture is chosen from the commander's colors in _apply_mats.
	var mat := TextureRect.new()
	mat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mat.stretch_mode = TextureRect.STRETCH_SCALE  ## whole mat visible, every color of it
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.modulate = Color(0.92, 0.92, 0.92)
	field.add_child(mat)
	var zones_col := VBoxContainer.new()
	zones_col.clip_contents = true
	var map := {}
	for zone_name in zone_order:
		var zone := HBoxContainer.new()
		zone.size_flags_vertical = SIZE_EXPAND_FILL
		zone.clip_contents = false
		zone.custom_minimum_size = Vector2(0, BOARD_CHIP.y + 16)
		var lab := Label.new()
		lab.text = str(zone_name)
		lab.custom_minimum_size = Vector2(78, 0)
		lab.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		lab.add_theme_font_size_override("font_size", 11)
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.clip_contents = false
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		var cards := HBoxContainer.new()
		cards.custom_minimum_size = Vector2(0, BOARD_CHIP.y + 8)
		cards.add_theme_constant_override("separation", 5)
		scroll.add_child(cards)
		zone.add_child(scroll)
		zones_col.add_child(zone)
		map[str(zone_name)] = cards
	field.add_child(zones_col)
	parent.add_child(field)
	map["__mat"] = mat
	return map

func _build_hand() -> Control:
	var hand_wrap := PanelContainer.new()
	hand_wrap.size_flags_vertical = SIZE_FILL
	hand_wrap.custom_minimum_size = Vector2(0, 140)
	var hand_style := StyleBoxFlat.new()
	hand_style.bg_color = Color(0.04, 0.08, 0.05)
	hand_style.content_margin_left = 8
	hand_style.content_margin_right = 8
	hand_style.content_margin_top = 4
	hand_style.content_margin_bottom = 6
	hand_wrap.add_theme_stylebox_override("panel", hand_style)
	var hand_inner := VBoxContainer.new()
	hand_inner.add_theme_constant_override("separation", 2)
	var hand_label := Label.new()
	hand_label.text = "Hand — a gold border means you can play that card now"
	hand_label.add_theme_color_override("font_color", MUTED)
	hand_label.add_theme_font_size_override("font_size", 12)
	hand_inner.add_child(hand_label)
	var hand_scroll := ScrollContainer.new()
	hand_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	hand_scroll.custom_minimum_size = Vector2(0, 114)
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.clip_contents = true
	hand_row = HBoxContainer.new()
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_row.add_theme_constant_override("separation", 6)
	hand_scroll.add_child(hand_row)
	hand_inner.add_child(hand_scroll)
	hand_wrap.add_child(hand_inner)
	return hand_wrap

func _build_sidebar() -> Control:
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(SIDE_W, 0)
	side.size_flags_horizontal = SIZE_SHRINK_END
	side.size_flags_vertical = SIZE_EXPAND_FILL
	side.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_GREEN
	style.border_width_left = 2
	style.border_color = BRASS
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	side.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var life_row := HBoxContainer.new()
	life_row.add_theme_constant_override("separation", 8)
	life_row.add_child(_life_block("You", "Krenko", true))
	life_row.add_child(_life_block("Rival", "Talrand", false))
	col.add_child(life_row)
	col.add_child(_pile_table())
	col.add_child(_build_command_panel())
	col.add_child(_build_inspector())

	ability_box = VBoxContainer.new()
	ability_box.add_theme_constant_override("separation", 4)
	ability_box.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_child(ability_box)

	play_btn = Button.new()
	play_btn.text = "Play selected"
	play_btn.custom_minimum_size = Vector2(0, 34)
	play_btn.pressed.connect(_on_activate)
	col.add_child(play_btn)
	declare_btn = Button.new()
	declare_btn.text = "Attack with this"
	declare_btn.custom_minimum_size = Vector2(0, 34)
	declare_btn.visible = false
	declare_btn.pressed.connect(_on_declare_attack)
	col.add_child(declare_btn)

	log_label = Label.new()
	log_label.add_theme_color_override("font_color", GOLD)
	log_label.add_theme_font_size_override("font_size", 12)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.max_lines_visible = 5
	log_label.size_flags_vertical = SIZE_EXPAND_FILL
	log_label.text = "What happened"
	col.add_child(log_label)

	side.add_child(col)
	return side

func _life_block(who: String, subtitle: String, is_you: bool) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	var who_lab := Label.new()
	who_lab.text = who
	who_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who_lab.add_theme_font_size_override("font_size", 11)
	who_lab.add_theme_color_override("font_color", MUTED)
	box.add_child(who_lab)
	var life := Label.new()
	life.text = "40"
	life.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	life.add_theme_font_size_override("font_size", 26)
	life.add_theme_color_override("font_color", GOLD)
	if is_you:
		you_life = life
	else:
		rival_life = life
	box.add_child(life)
	var title_label := Label.new()
	title_label.text = subtitle
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.clip_text = true
	if not is_you:
		rival_title_label = title_label
	else:
		you_title_label = title_label
	box.add_child(title_label)
	## Commander damage taken from the opposing commander; 21 from one commander loses the game.
	var cmdr := Label.new()
	cmdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cmdr.add_theme_font_size_override("font_size", 11)
	cmdr.clip_text = true
	cmdr.mouse_filter = Control.MOUSE_FILTER_PASS
	cmdr.tooltip_text = "Commander damage taken. 21 combat damage from a single commander loses the game."
	cmdr.visible = false
	box.add_child(cmdr)
	if is_you:
		you_cmdr_label = cmdr
	else:
		rival_cmdr_label = cmdr
	if is_you:
		var mine := PanelContainer.new()
		mine.size_flags_horizontal = SIZE_EXPAND_FILL
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(0.02, 0.07, 0.03)
		gs.border_color = Color(0.30, 0.72, 0.34)
		gs.set_border_width_all(3)
		gs.set_corner_radius_all(10)
		gs.set_content_margin_all(3)
		gs.shadow_color = Color(0, 0, 0, 0.55)
		gs.shadow_size = 7
		gs.shadow_offset = Vector2(0, 3)
		mine.add_theme_stylebox_override("panel", gs)
		mine.add_child(_life_face(box, Color(0.25, 0.65, 0.30)))
		return mine
	## The rival's life box is also the target of your attack: click it to send your attackers.
	_rival_target = PanelContainer.new()
	_rival_target.size_flags_horizontal = SIZE_EXPAND_FILL
	_rival_target.mouse_filter = Control.MOUSE_FILTER_STOP
	_rival_target.tooltip_text = "While you are attacking, click here to send your attackers at the rival."
	_rival_target.add_theme_stylebox_override("panel", _target_style(0.0, false))
	_rival_target.gui_input.connect(_on_rival_target_input)
	_rival_target.add_child(_life_face(box, Color(0.78, 0.20, 0.15)))
	return _rival_target


func _target_style(pulse: float, active: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	## The rival's box is always framed in red (yours is green); it flares while you pick attackers.
	st.bg_color = Color(0.5, 0.08, 0.06, 0.25 + 0.2 * pulse) if active else Color(0.20, 0.05, 0.04, 0.75)
	st.border_color = ATTACK_RED.lerp(Color(1, 1, 1), pulse * 0.6) if active else Color(0.72, 0.18, 0.14)
	st.set_border_width_all(4 if active else 3)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(3)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 7
	st.shadow_offset = Vector2(0, 3)
	return st


func _on_rival_target_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_on_rival_target_click()


## Attack target. In a two-player game the rival player is the only legal target: creatures can't
## be attacked (CR 506.2) and there are no planeswalkers or battles in the engine yet.
func _on_rival_target_click() -> void:
	if not _in_attack_mode():
		_set_status("Pick a creature and press Attack with this first.")
		return
	if _pending_attackers.is_empty():
		_set_status("Click one of your creatures first, then click the rival to attack.")
		return
	_confirm_attack()


## Sidebar button: attack with the selected creature.
func _on_declare_attack() -> void:
	if not USE_ENGINE or session == null or session.view == null:
		return
	var sid := str(session.selected_id)
	if sid == "":
		return
	if not _in_attack_mode():
		_pending_attackers.clear()
		if _is_guest():
			_guest_attack = true
		else:
			if not session.can_play():
				_set_status("Keep or Mulligan first.")
				return
			var r: SubmitResult = session.begin_attack()
			if not r.ok:
				_refresh()
				_set_status(r.error)
				return
	if not _pending_attackers.has(sid):
		_on_attack_click(sid)
	else:
		_refresh()
	if _in_attack_mode() and not _pending_attackers.is_empty():
		_set_status("Now click the rival (top right) to attack. Click more creatures first to send them too.")


func _chip_style(bg: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.content_margin_left = 8
	st.content_margin_right = 8
	return st

## The turn at a glance: Upkeep, Draw, Main 1, Combat, Main 2, End. Draw, Combat and End are buttons.
func _build_phase_track() -> Control:
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_GREEN
	style.content_margin_left = 14
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	turn_owner_label = Label.new()
	turn_owner_label.custom_minimum_size = Vector2(130, 0)
	turn_owner_label.add_theme_font_size_override("font_size", 15)
	row.add_child(turn_owner_label)
	for entry in TRACK:
		var key: String = entry[0]
		var chip := Button.new()
		chip.text = entry[1]
		chip.custom_minimum_size = Vector2(98, 28)
		chip.focus_mode = Control.FOCUS_NONE
		if key == "draw":
			chip.pressed.connect(_on_click_library)
			chip.tooltip_text = "Click your deck to draw your card for the turn."
		elif key == "combat":
			chip.pressed.connect(_on_attack)
			chip.tooltip_text = "Go to combat, then click each creature you want to attack with."
		elif key == "end":
			chip.pressed.connect(_on_end_turn)
			chip.tooltip_text = "End your turn."
		row.add_child(chip)
		phase_chips[key] = chip
	hint_label = Label.new()
	hint_label.size_flags_horizontal = SIZE_EXPAND_FILL
	hint_label.clip_text = true
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", GOLD)
	row.add_child(hint_label)
	bar.add_child(row)
	return bar

func _paint_phase_track() -> void:
	if turn_owner_label == null or session == null or session.view == null:
		return
	var v = session.view
	var mine: bool = bool(v.active_is_you)
	turn_owner_label.text = "YOUR TURN" if mine else "RIVAL'S TURN"
	turn_owner_label.add_theme_color_override("font_color", TURN_GREEN if mine else TURN_RED)
	for key in phase_chips.keys():
		var chip: Button = phase_chips[key]
		var now: bool = str(v.turn_track) == str(key)
		var bg := Color(0.07, 0.16, 0.09)
		var fg := Color(0.80, 0.86, 0.76)
		var border := Color(0.36, 0.30, 0.14)
		if now:
			bg = TURN_GREEN.darkened(0.15) if mine else TURN_RED.darkened(0.2)
			fg = Color(0.04, 0.1, 0.04) if mine else Color(1, 0.94, 0.9)
			border = GOLD
		for sname in ["normal", "hover", "pressed", "disabled", "focus"]:
			chip.add_theme_stylebox_override(sname, _chip_style(bg, border))
		for cname in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			chip.add_theme_color_override(cname, fg)

## What to do next, in plain words, beside the phase bar.
func _paint_hint() -> void:
	if hint_label == null or session == null or session.view == null:
		return
	var v = session.view
	var t := ""
	if not session.can_play():
		t = "Keep or Mulligan your hand."
	elif not bool(v.active_is_you):
		t = "Rival is taking their turn…"
	elif session.draw_waiting():
		t = "Click your deck to draw a card."
	else:
		match str(v.turn_track):
			"main1", "main2":
				t = "Play a land or spell (gold border = playable). Then Combat or Next turn."
			"combat":
				t = "Click creatures to attack with."
			_:
				t = "Press Pass to move on, or Next turn to end your turn."
	hint_label.text = t

## Both commanders, where you can see them. Click yours to cast it (the Gold border means you can).
func _build_command_panel() -> Control:
	var box := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL
	st.set_corner_radius_all(6)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "Command zone"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", MUTED)
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var you_col := VBoxContainer.new()
	you_col.add_theme_constant_override("separation", 2)
	you_col.add_child(_mini("You", GOLD))
	you_cmd_row = HBoxContainer.new()
	you_col.add_child(you_cmd_row)
	var rival_col := VBoxContainer.new()
	rival_col.add_theme_constant_override("separation", 2)
	rival_col.add_child(_mini("Rival", GOLD))
	rival_cmd_row = HBoxContainer.new()
	rival_col.add_child(rival_cmd_row)
	row.add_child(you_col)
	row.add_child(rival_col)
	col.add_child(row)
	box.add_child(col)
	return box

func _fill_command(container: HBoxContainer, cards: Array, mine: bool) -> void:
	_clear(container)
	if cards.is_empty():
		var none := Label.new()
		none.text = "on the table"
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", MUTED)
		none.custom_minimum_size = Vector2(COMMAND_CHIP.x, 20)
		container.add_child(none)
		return
	for card in cards:
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 1)
		slot.add_child(_card_chip(card, false, mine, COMMAND_CHIP))
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", PLAYABLE_GOLD if bool(card.get("playable", false)) else MUTED)
		var tax := int(card.get("commander_tax", 0))
		if mine:
			note.text = "Click to cast" if bool(card.get("playable", false)) else ("Tax +%d" % tax if tax > 0 else "Not castable yet")
		else:
			note.text = "Tax +%d" % tax if tax > 0 else "Commander"
		slot.add_child(note)
		container.add_child(slot)

func _pile_table() -> Control:
	var box := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL
	st.set_corner_radius_all(6)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", st)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	grid.add_child(_mini("", MUTED))
	grid.add_child(_mini("You", GOLD))
	grid.add_child(_mini("Rival", GOLD))
	for pile in ["Library", "GY", "Exile", "Command"]:
		var key: String = "graveyard" if pile == "GY" else pile.to_lower()
		grid.add_child(_mini(pile, MUTED))
		var rival_v := _mini("0", INK)
		if key == "library":
			you_library_btn = Button.new()
			you_library_btn.text = "0"
			you_library_btn.custom_minimum_size = Vector2(52, 22)
			you_library_btn.add_theme_font_size_override("font_size", 12)
			you_library_btn.pressed.connect(_on_click_library)
			grid.add_child(you_library_btn)
			pile_labels["you_library"] = you_library_btn
		elif key == "command":
			var you_cmd := Button.new()
			you_cmd.text = "—"
			you_cmd.custom_minimum_size = Vector2(52, 22)
			you_cmd.add_theme_font_size_override("font_size", 12)
			you_cmd.pressed.connect(_on_click_command)
			grid.add_child(you_cmd)
			pile_labels["you_command"] = you_cmd
		elif key == "graveyard" or key == "exile":
			var pile_btn := Button.new()
			pile_btn.text = "0"
			pile_btn.custom_minimum_size = Vector2(52, 22)
			pile_btn.add_theme_font_size_override("font_size", 12)
			pile_btn.tooltip_text = "Cast from here (flashback, escape, retrace, suspend)"
			var zid: int = EngineEnums.ZoneId.GRAVEYARD if key == "graveyard" else EngineEnums.ZoneId.EXILE
			pile_btn.pressed.connect(_on_click_pile.bind(zid, "your graveyard" if key == "graveyard" else "exile"))
			grid.add_child(pile_btn)
			pile_labels["you_%s" % key] = pile_btn
		else:
			var you_v := _mini("0", INK)
			grid.add_child(you_v)
			pile_labels["you_%s" % key] = you_v
		grid.add_child(rival_v)
		pile_labels["rival_%s" % key] = rival_v
	box.add_child(grid)
	return box

func _mini(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	l.custom_minimum_size = Vector2(52, 16)
	l.clip_text = true
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func _build_inspector() -> Control:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	wrap.custom_minimum_size = Vector2(0, 118)
	inspector_art = TextureRect.new()
	inspector_art.custom_minimum_size = Vector2(78, 110)
	inspector_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inspector_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wrap.add_child(inspector_art)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = SIZE_EXPAND_FILL
	inspector_title = Label.new()
	inspector_title.add_theme_font_size_override("font_size", 14)
	inspector_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_title.max_lines_visible = 2
	texts.add_child(inspector_title)
	inspector_type = Label.new()
	inspector_type.add_theme_color_override("font_color", MUTED)
	inspector_type.add_theme_font_size_override("font_size", 11)
	inspector_type.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_type.max_lines_visible = 2
	texts.add_child(inspector_type)
	inspector_text = Label.new()
	inspector_text.add_theme_font_size_override("font_size", 11)
	inspector_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_text.max_lines_visible = 4
	inspector_text.size_flags_vertical = SIZE_EXPAND_FILL
	texts.add_child(inspector_text)
	wrap.add_child(texts)
	return wrap

func _build_menu() -> void:
	menu_overlay = ColorRect.new()
	menu_overlay.color = Color(0.02, 0.03, 0.03, 0.78)
	menu_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	menu_overlay.visible = false
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	menu_overlay.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = GOLD.darkened(0.2)
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	col.add_child(title)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	var restart := Button.new()
	restart.text = "New game"
	restart.custom_minimum_size = Vector2(120, 32)
	restart.pressed.connect(_on_new_game)
	var import_b := Button.new()
	import_b.text = "Import Deck"
	import_b.custom_minimum_size = Vector2(140, 32)
	import_b.pressed.connect(_on_open_import)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(_hide_menu)
	actions.add_child(restart)
	menu_solo_nodes.append(restart)
	actions.add_child(import_b)
	menu_solo_nodes.append(import_b)
	actions.add_child(close)
	col.add_child(actions)
	panel.add_child(col)
	center.add_child(panel)
	add_child(menu_overlay)

## Victory / defeat banner shown when the game ends. It sits over the whole table (dimmed, still visible behind),
## so the result and the way out are always on screen.
func _build_gameover() -> void:
	gameover_overlay = ColorRect.new()
	gameover_overlay.color = Color(0.01, 0.01, 0.03, 0.72)
	gameover_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	gameover_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	gameover_overlay.z_index = 40
	gameover_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	gameover_overlay.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.set_corner_radius_all(16)
	st.set_border_width_all(3)
	st.border_color = GOLD
	st.shadow_color = Color(0.6, 0.45, 1.0, 0.35)
	st.shadow_size = 24
	st.content_margin_left = 48
	st.content_margin_right = 48
	st.content_margin_top = 30
	st.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	gameover_title = Label.new()
	gameover_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_title.add_theme_font_size_override("font_size", 52)
	col.add_child(gameover_title)
	gameover_sub = Label.new()
	gameover_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_sub.add_theme_font_size_override("font_size", 18)
	gameover_sub.add_theme_color_override("font_color", INK)
	gameover_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gameover_sub.custom_minimum_size = Vector2(440, 0)
	col.add_child(gameover_sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	gameover_again = _header_button("Play again", GOLD.darkened(0.15), Color(0.12, 0.10, 0.04), _on_play_again, 150)
	row.add_child(gameover_again)
	row.add_child(_header_button("View board", Color(0.16, 0.17, 0.18), INK, _on_view_board, 130))
	row.add_child(_header_button("Main menu", Color(0.16, 0.17, 0.18), INK, _leave_to_menu, 130))
	col.add_child(row)
	panel.add_child(col)
	center.add_child(panel)
	add_child(gameover_overlay)


func _refresh_gameover() -> void:
	if gameover_overlay == null:
		return
	if _peer_left:
		return
	var b = _board()
	if not bool(b.game_over):
		_gameover_shown = false
		gameover_overlay.visible = false
		return
	if _gameover_shown:
		return
	_gameover_shown = true
	var app := get_node_or_null("/root/AppState")
	var is_client: bool = app != null and app.is_mp_client()
	var won: bool = (b.winners as Array).has(1 if is_client else 0)
	gameover_title.text = "VICTORY" if won else "DEFEAT"
	gameover_title.add_theme_color_override("font_color", GOLD if won else ATTACK_RED)
	var why := str((b.rival if won else b.you).get("lose_reason", ""))
	var who := "Your rival" if won else "You"
	if why != "":
		gameover_sub.text = "%s lost: %s." % [who, why]
	else:
		gameover_sub.text = "You won the game." if won else "You lost the game."
	## Guests in a LAN room can't restart the host's table.
	gameover_again.visible = not is_client
	gameover_overlay.visible = true


func _on_view_board() -> void:
	gameover_overlay.visible = false


func _on_play_again() -> void:
	var app := get_node_or_null("/root/AppState")
	if app != null and app.is_mp():
		_leave_to_menu()
		return
	get_tree().reload_current_scene()


func _build_turn_border() -> void:
	turn_border = Panel.new()
	turn_border.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	turn_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_border.z_index = 20
	turn_border.visible = false  ## no coloured frame around the window for whose turn it is
	add_child(turn_border)

func _waiting_for_draw() -> bool:
	if USE_ENGINE:
		return session != null and session.pending_draw_anim
	return state != null and state.active_is_you and not state.you_drew_this_turn

func _process(dt: float) -> void:
	_flash_t += dt
	_paint_flash()
	if _hint_hold > 0.0:
		_hint_hold -= dt
		if _hint_hold <= 0.0:
			_paint_hint()

func _paint_flash() -> void:
	var wait := _waiting_for_draw()
	var pulse := 0.5 + 0.5 * sin(_flash_t * TAU * 1.8)
	if draw_btn:
		draw_btn.visible = wait
		if wait:
			var bst := StyleBoxFlat.new()
			bst.bg_color = TURN_GREEN.lerp(GOLD, pulse * 0.7)
			bst.set_corner_radius_all(10)
			draw_btn.add_theme_stylebox_override("normal", bst)
			draw_btn.add_theme_stylebox_override("hover", bst)
			draw_btn.add_theme_color_override("font_color", Color(0.06, 0.1, 0.04))
	_playable_styles = _playable_styles.filter(func(x) -> bool: return x != null)
	for pst in _playable_styles:
		var sb := pst as StyleBoxFlat
		sb.border_color = PLAYABLE_GOLD.lerp(Color(1, 1, 1), pulse * 0.7)
		sb.shadow_color = Color(1.0, 0.84, 0.18, 0.3 + 0.5 * pulse)
		sb.shadow_size = 8 + int(14.0 * pulse)
	if _rival_target:
		_rival_target.add_theme_stylebox_override("panel", _target_style(pulse, _in_attack_mode() and not _pending_attackers.is_empty()))
	if deck_btn:
		if wait:
			var dst := StyleBoxFlat.new()
			dst.draw_center = false
			dst.set_corner_radius_all(6)
			dst.set_border_width_all(5)
			dst.border_color = GOLD.lerp(Color(1, 1, 1), pulse)
			dst.shadow_color = Color(1.0, 0.84, 0.18, 0.35 + 0.4 * pulse)
			dst.shadow_size = 10 + int(10.0 * pulse)
			_deck_frame.add_theme_stylebox_override("panel", dst)
			deck_btn.pivot_offset = deck_btn.size * 0.5
			deck_btn.scale = Vector2.ONE * (1.0 + 0.07 * pulse)
			_deck_flashing = true
		elif _deck_flashing:
			_deck_flashing = false
			deck_btn.scale = Vector2.ONE
			_deck_frame.add_theme_stylebox_override("panel", _deck_style)
	if turn_border and wait:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.draw_center = false
		st.set_border_width_all(10)
		st.border_color = TURN_GREEN.lerp(Color(0.65, 1.0, 0.5), pulse)
		turn_border.add_theme_stylebox_override("panel", st)

## Scrollable play-by-play: casts, summons, activations, attacks, blocks, damage, life.
func _build_history_panel() -> void:
	history_panel = PanelContainer.new()
	history_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	history_panel.anchor_left = 1.0
	history_panel.anchor_right = 1.0
	history_panel.anchor_top = 0.0
	history_panel.anchor_bottom = 1.0
	history_panel.offset_left = -(SIDE_W + 352)
	history_panel.offset_right = -(SIDE_W + 10)
	history_panel.offset_top = 92
	history_panel.offset_bottom = -170
	history_panel.z_index = 30
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.border_color = GOLD.darkened(0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.content_margin_left = 10
	st.content_margin_right = 6
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	history_panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "History"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 15)
	head.add_child(title)
	var close := Button.new()
	close.text = "Hide"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_toggle_history)
	head.add_child(close)
	col.add_child(head)
	history_text = RichTextLabel.new()
	history_text.bbcode_enabled = true
	history_text.scroll_active = true
	history_text.scroll_following = true
	history_text.selection_enabled = true
	history_text.size_flags_vertical = SIZE_EXPAND_FILL
	history_text.add_theme_font_size_override("normal_font_size", 13)
	history_text.add_theme_font_size_override("bold_font_size", 13)
	history_text.meta_underlined = false
	history_text.meta_hover_started.connect(_on_history_meta_hover)
	history_text.meta_hover_ended.connect(func(_m: Variant) -> void: _on_unhover_card())
	col.add_child(history_text)
	history_panel.add_child(col)
	history_panel.visible = true
	add_child(history_panel)


func _on_history_meta_hover(meta: Variant) -> void:
	var card: Variant = _history_cards.get(str(meta))
	if card is Dictionary:
		if hover_wrap != null:
			hover_wrap.z_index = 40
		_on_hover_card(_with_catalog_art(card))


## A card dictionary from the history (name, type, text) plus its Scryfall art when the catalog has it.
func _with_catalog_art(card: Dictionary) -> Dictionary:
	var d: Dictionary = card.duplicate()
	var cat := _catalog()
	if cat != null and cat.has_method("find_by_name"):
		var found: Variant = cat.find_by_name(str(d.get("name", "")))
		if found is Dictionary and not (found as Dictionary).is_empty():
			var row: Dictionary = found
			d["scryfall_id"] = str(row.get("id", ""))
			var imgs: Variant = row.get("images", {})
			if imgs is Dictionary:
				d["images"] = imgs
				d["imageUrl"] = str((imgs as Dictionary).get("normal", (imgs as Dictionary).get("small", "")))
	return d


func _toggle_history() -> void:
	if history_panel:
		history_panel.visible = not history_panel.visible
		if history_button != null:
			history_button.text = "Hide history" if history_panel.visible else "History"
		_history_shown = -1
		_paint_history()


func _paint_history() -> void:
	if history_text == null or history_panel == null or not history_panel.visible:
		return
	if session == null or session.view == null:
		return
	var lines: Array = session.view.history
	if lines.size() == _history_shown:
		return
	_history_shown = lines.size()
	var out := ""
	_history_cards.clear()
	for entry in lines:
		var d: Dictionary = entry
		var t := str(d.get("t", "")).replace("[", "(").replace("]", ")")
		## Card names are links: hover one to see the whole card, art and rules text included.
		var ci := 0
		for c in d.get("cards", []):
			var cd: Dictionary = c
			var cname := str(cd.get("name", "")).replace("[", "(").replace("]", ")")
			var at := t.find(cname)
			if cname == "" or at < 0:
				continue
			var meta := "c%d_%d" % [_history_cards.size(), ci]
			_history_cards[meta] = cd
			ci += 1
			t = t.substr(0, at) + "[url=%s][u]%s[/u][/url]" % [meta, cname] + t.substr(at + cname.length())
		match str(d.get("k", "info")):
			"turn":
				out += "\n[b][color=#f2c94c]%s[/color][/b]\n" % t
			"step":
				out += "[color=#6f7a78]· %s[/color]\n" % t
			"you":
				out += "[color=#cfe9c6]%s[/color]\n" % t
			"rival":
				out += "[color=#f0a79c]%s[/color]\n" % t
			_:
				out += "[color=#b9c0bf]%s[/color]\n" % t
	history_text.text = out


## Text chat for online matches: bottom right, to the left of the deck.
var chat_panel: PanelContainer
var chat_log_box: RichTextLabel
var chat_input: LineEdit

func _build_chat() -> void:
	chat_panel = PanelContainer.new()
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	chat_panel.anchor_left = 1.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_right = 1.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = -(SIDE_W + 12 + 106 + 12 + 388)
	chat_panel.offset_top = -128
	chat_panel.offset_right = -(SIDE_W + 12 + 106 + 12)
	chat_panel.offset_bottom = -16
	chat_panel.z_index = 25
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	st.border_color = GOLD.darkened(0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	chat_panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	chat_log_box = RichTextLabel.new()
	chat_log_box.bbcode_enabled = true
	chat_log_box.scroll_following = true
	chat_log_box.size_flags_vertical = SIZE_EXPAND_FILL
	chat_log_box.add_theme_font_size_override("normal_font_size", 13)
	chat_log_box.add_theme_font_size_override("bold_font_size", 13)
	col.add_child(chat_log_box)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Chat — press Enter to send"
	chat_input.max_length = 200
	chat_input.text_submitted.connect(_on_chat_submit)
	col.add_child(chat_input)
	chat_panel.add_child(col)
	var app := get_node_or_null("/root/AppState")
	chat_panel.visible = app != null and app.is_mp()
	add_child(chat_panel)
	var net := get_node_or_null("/root/GameNet")
	if net != null and not net.chat_received.is_connected(_on_chat_received):
		net.chat_received.connect(_on_chat_received)
	if net != null and not net.menu_received.is_connected(_on_menu_received):
		net.menu_received.connect(_on_menu_received)
	if net != null and not net.peer_left.is_connected(_on_peer_left):
		net.peer_left.connect(_on_peer_left)
	if net != null and not net.notice_received.is_connected(_set_status):
		net.notice_received.connect(_set_status)


func _on_chat_submit(text: String) -> void:
	var net := get_node_or_null("/root/GameNet")
	if net != null:
		net.send_chat(text)
	chat_input.text = ""
	## Back to the game so Space / Enter keep working for the table.
	chat_input.release_focus()


func _on_chat_received(sender: String, text: String, mine: bool) -> void:
	if chat_log_box == null:
		return
	var clean := text.replace("[", "[lb]")
	var color := "#f0c850" if mine else "#7fd0ff"
	chat_log_box.append_text("[color=%s][b]%s:[/b][/color] %s\n" % [color, sender.replace("[", "[lb]"), clean])

const CARD_BACK := "res://assets/ui/card_back.jpg"
const DECK_SIZE := Vector2(106, 148)
var _deck_frame: Panel
var _deck_count: Label
static var _card_back_tex: Texture2D = null


## The standard Magic card back (assets/ui/card_back.jpg), read straight from the file so it needs no import step.
## Resized once with Lanczos to twice its on-screen size and given mipmaps, so it stays sharp instead of aliasing.
static func _card_back() -> Texture2D:
	if _card_back_tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(CARD_BACK))
		if img != null and not img.is_empty():
			img.resize(int(DECK_SIZE.x * 2.0), int(DECK_SIZE.y * 2.0), Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			_card_back_tex = ImageTexture.create_from_image(img)
	return _card_back_tex


func _build_deck_pile() -> void:
	deck_btn = Button.new()
	deck_btn.custom_minimum_size = DECK_SIZE
	deck_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	deck_btn.anchor_left = 1.0
	deck_btn.anchor_top = 1.0
	deck_btn.anchor_right = 1.0
	deck_btn.anchor_bottom = 1.0
	## Right edge sits just left of the sidebar (SIDE_W wide) so the deck never overlaps its gold edge.
	deck_btn.offset_right = -(SIDE_W + 12)
	deck_btn.offset_left = deck_btn.offset_right - DECK_SIZE.x
	deck_btn.offset_bottom = -12
	deck_btn.offset_top = deck_btn.offset_bottom - DECK_SIZE.y
	deck_btn.z_index = 25
	var empty := StyleBoxEmpty.new()
	for sname in ["normal", "hover", "pressed", "focus", "disabled"]:
		deck_btn.add_theme_stylebox_override(sname, empty)
	deck_btn.pressed.connect(_on_click_library)
	deck_btn.tooltip_text = "Your library. On your turn it glows: click it to draw."
	## The library is a face-down card: the Magic card back, with the card count over it.
	var back := _card_back()
	if back != null:
		var pic := TextureRect.new()
		pic.texture = back
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		deck_btn.add_child(pic)
	else:
		var flat := ColorRect.new()
		flat.color = Color(0.38, 0.12, 0.08)
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		deck_btn.add_child(flat)
	_deck_count = Label.new()
	_deck_count.text = "92"
	_deck_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_deck_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_deck_count.add_theme_font_size_override("font_size", 24)
	_deck_count.add_theme_color_override("font_color", Color(1, 0.96, 0.82))
	_deck_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_deck_count.add_theme_constant_override("outline_size", 8)
	deck_btn.add_child(_deck_count)
	## A frame over the art: a dark rim with a drop shadow normally, a pulsing gold glow while it is time to draw.
	_deck_frame = Panel.new()
	_deck_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_deck_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.set_border_width_all(2)
	fs.border_color = Color(0.05, 0.04, 0.03)
	fs.set_corner_radius_all(7)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 8
	fs.shadow_offset = Vector2(3, 5)
	_deck_style = fs
	_deck_frame.add_theme_stylebox_override("panel", fs)
	deck_btn.add_child(_deck_frame)
	add_child(deck_btn)

func _build_draw_button() -> void:
	draw_btn = Button.new()
	draw_btn.text = "Draw"
	draw_btn.custom_minimum_size = Vector2(156, 58)
	draw_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	draw_btn.anchor_left = 1.0
	draw_btn.anchor_top = 1.0
	draw_btn.anchor_right = 1.0
	draw_btn.anchor_bottom = 1.0
	draw_btn.offset_left = -186
	draw_btn.offset_top = -80
	draw_btn.offset_right = -18
	draw_btn.offset_bottom = -16
	draw_btn.z_index = 25
	draw_btn.add_theme_font_size_override("font_size", 24)
	draw_btn.pressed.connect(_on_click_library)
	draw_btn.visible = false
	add_child(draw_btn)

func _paint_turn_border() -> void:
	if turn_border == null:
		return
	if _waiting_for_draw():
		return
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.draw_center = false
	st.set_border_width_all(8)
	st.border_color = TURN_GREEN if state.active_is_you else TURN_RED
	turn_border.add_theme_stylebox_override("panel", st)

func _build_hover() -> void:
	hover_wrap = CenterContainer.new()
	hover_wrap.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hover_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_wrap.z_index = 40
	hover_wrap.visible = false
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	hover_art = TextureRect.new()
	hover_art.custom_minimum_size = Vector2(280, 392)
	hover_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hover_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hover_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_name = Label.new()
	hover_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_name.add_theme_font_size_override("font_size", 18)
	hover_name.add_theme_color_override("font_color", GOLD)
	hover_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hover_art)
	col.add_child(hover_name)
	hover_wrap.add_child(col)
	add_child(hover_wrap)

func _on_hover_card(card: Dictionary) -> void:
	if hover_wrap == null:
		return
	hover_name.text = str(card.get("name", ""))
	if hover_printed != null:
		hover_printed.queue_free()
		hover_printed = null
	var cat := _catalog()
	var tex: Texture2D = null
	if cat and CardFaceScript.mode(card) == CardFaceScript.MODE_ART:
		tex = cat.texture_for(card, "normal")
		if tex == null:
			tex = cat.texture_for(card, "small")
	hover_art.texture = tex
	hover_art.visible = tex != null
	hover_name.visible = tex != null
	if tex == null:
		hover_printed = _make_card_face(card, Vector2(280, 392))
		var col := hover_wrap.get_child(0)
		col.add_child(hover_printed)
		col.move_child(hover_printed, 0)
	hover_wrap.visible = true
	hover_wrap.modulate = Color(1, 1, 1, 0)
	hover_wrap.scale = Vector2(0.82, 0.82)
	hover_wrap.pivot_offset = hover_wrap.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(hover_wrap, "modulate:a", 1.0, 0.12)
	tw.tween_property(hover_wrap, "scale", Vector2.ONE, 0.12)

func _on_unhover_card() -> void:
	if hover_wrap:
		hover_wrap.visible = false

func _card_chip(card: Dictionary, compact: bool = false, from_hand: bool = false, chip_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.clip_contents = true
	b.custom_minimum_size = chip_size if chip_size != Vector2.ZERO else (BOARD_CHIP if compact else HAND_CHIP)
	var selected: bool = str(card.get("id", "")) == str(_board().selected_id)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.draw_center = false
	st.set_corner_radius_all(6)
	st.set_border_width_all(2)
	st.border_color = SELECT_BLUE if selected else Color(0, 0, 0, 0.55)
	if from_hand and bool(card.get("playable", false)):
		## Gold border: the rules let you play this right now and you have the mana for it.
		st.border_color = PLAYABLE_GOLD
		st.set_border_width_all(8)
		st.set_corner_radius_all(8)
		st.shadow_color = Color(1.0, 0.84, 0.18, 0.55)
		st.shadow_size = 12
		_playable_styles.append(st)
		b.tooltip_text = "You can play this now.\n%s" % str(card.get("cost_note", ""))
	var combat_color: Variant = _combat_border(card)
	if combat_color is Color:
		st.border_color = combat_color
		st.set_border_width_all(3)
	if compact and bool(card.get("summoning_sick", false)):
		## CR 302.6: shown dimmed until it can attack.
		b.modulate = Color(1, 1, 1, 0.62)
		b.tooltip_text = "Summoning sick — can attack (and use {T} abilities) on your next turn."
	st.content_margin_left = 0
	st.content_margin_right = 0
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	var plain := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", plain)
	b.add_theme_stylebox_override("hover", plain)
	b.add_theme_stylebox_override("pressed", plain)
	b.add_theme_stylebox_override("focus", plain)
	b.text = ""
	var face := _make_card_face(card, b.custom_minimum_size)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(face)
	## The border is drawn on top of the card art. As the button's own style it sat underneath the art
	## and only a thin sliver showed.
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", st)
	b.add_child(frame)
	## Loyalty, counters, current power/toughness and attachments, on a strip across the bottom of a permanent.
	var badge := str(card.get("badge", ""))
	if compact and badge != "":
		var strip := Label.new()
		strip.text = badge
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		strip.add_theme_font_size_override("font_size", 11)
		strip.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
		var sbg := StyleBoxFlat.new()
		sbg.bg_color = Color(0, 0, 0, 0.72)
		sbg.set_corner_radius_all(4)
		strip.add_theme_stylebox_override("normal", sbg)
		strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		strip.offset_top = -22
		b.add_child(strip)
		b.tooltip_text = (b.tooltip_text + "\n" + badge).strip_edges()
	var cid := str(card.get("id", ""))
	b.mouse_entered.connect(_on_hover_card.bind(card.duplicate()))
	b.mouse_exited.connect(_on_unhover_card)
	if from_hand:
		b.pressed.connect(_on_hand_card.bind(cid))
	else:
		b.pressed.connect(_on_select.bind(cid))
	if not from_hand:
		b.gui_input.connect(_on_chip_input.bind(cid))
	return b

func _clear(node: Node) -> void:
	while node.get_child_count() > 0:
		var child := node.get_child(0)
		node.remove_child(child)
		child.queue_free()

func _fill_zone(container: HBoxContainer, cards: Array, do_tap: bool = false) -> void:
	_clear(container)
	for card in cards:
		var chip := _card_chip(card, true, false)
		container.add_child(chip)
		if do_tap:
			_apply_tap_visual(chip, card)

func _apply_tap_visual(chip: Control, card: Dictionary) -> void:
	var cid := str(card.get("id", ""))
	var now := bool(card.get("tapped", false))
	var was := bool(_was_tapped.get(cid, false))
	chip.pivot_offset = Vector2(BOARD_CHIP.x * 0.5, BOARD_CHIP.y * 0.5)
	chip.clip_contents = false
	if now and not was:
		chip.rotation_degrees = 0.0
		var tw := chip.create_tween()
		tw.tween_property(chip, "rotation_degrees", 90.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif now:
		chip.rotation_degrees = 90.0
	elif was:
		chip.rotation_degrees = 90.0
		var tw2 := chip.create_tween()
		tw2.tween_property(chip, "rotation_degrees", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		chip.rotation_degrees = 0.0
	_was_tapped[cid] = now

## Each player's field gets the playmat for their commander's color identity.
func _apply_mats() -> void:
	## The mats come from the view's commander colors, so a guest (who has no engine of its own) gets them too.
	var b = _board()
	_set_mat(you_zones, b.you.get("identity", []))
	_set_mat(rival_zones, b.rival.get("identity", []))

func _set_mat(zones: Dictionary, identity: Array) -> void:
	var mat := zones.get("__mat") as TextureRect
	if mat == null:
		return
	var file := Mats.file_for(identity)
	if str(mat.get_meta("file", "")) == file:
		return
	mat.set_meta("file", file)
	mat.texture = Mats.texture(file)

## A guest's table has no engine of its own: its stand-in session mirrors the host's view, so the checks that ask the
## session (can I play yet?) work, and the card you select stays yours instead of following the host's selection.
func _sync_guest() -> void:
	var app := get_node_or_null("/root/AppState")
	if app == null or not app.is_mp_client() or session == null:
		return
	var net := get_node_or_null("/root/GameNet")
	if net == null or net.last_view == null:
		return
	var v: TableView = net.last_view
	session.match_start = v.match_start
	session.view = v
	if not bool(v.active_is_you):
		_guest_attack = false
	session.pending_draw_anim = bool(v.draw_waiting_you)
	v.selected_id = session.selected_id


func _refresh() -> void:
	_sync_guest()
	var b = _board()
	_apply_mats()
	_playable_styles.clear()
	header_label.text = b.header_text()
	_paint_life(you_life, int(b.you["life"]))
	_paint_life(rival_life, int(b.rival["life"]))
	_paint_cmdr_damage(you_cmdr_label, b.you)
	_paint_cmdr_damage(rival_cmdr_label, b.rival)
	if rival_title_label:
		var app_rt := get_node_or_null("/root/AppState")
		if app_rt != null and app_rt.is_mp():
			rival_title_label.text = str(b.rival.get("name", "Rival"))
		else:
			rival_title_label.text = "Talrand"
		var rs := str(b.rival.get("status", ""))
		if rs != "":
			rival_title_label.text += " · " + rs
		rival_title_label.tooltip_text = rs
	if you_title_label:
		var ys := str(b.you.get("status", ""))
		you_title_label.text = ys
		you_title_label.tooltip_text = ys
	_fill_zone(you_zones["Creatures"], b.you["creatures"], true)
	_fill_zone(you_zones["Non-creature permanents"], b.you["noncreatures"])
	_fill_zone(you_zones["Lands"], b.you["lands"], true)
	_fill_zone(rival_zones["Creatures"], b.rival["creatures"], true)
	_fill_zone(rival_zones["Non-creature permanents"], b.rival["noncreatures"])
	_fill_zone(rival_zones["Lands"], b.rival["lands"], true)
	_clear(hand_row)
	for card in b.you["hand"]:
		hand_row.add_child(_card_chip(card, false, true))
	_set_pile("you", b.you)
	_set_pile("rival", b.rival)
	_fill_command(you_cmd_row, b.you["command"], true)
	_fill_command(rival_cmd_row, b.rival["command"], false)
	_paint_phase_track()
	_paint_history()
	if _hint_hold <= 0.0:
		_paint_hint()
	if deck_btn:
		_deck_count.text = "%d" % int(b.you["library"])
		if _waiting_for_draw():
			deck_btn.tooltip_text = "Your draw step: click to draw a card."
		else:
			deck_btn.tooltip_text = "Library: %d cards." % int(b.you["library"])
	var selected: Dictionary = b.find_card(b.selected_id)
	if selected.is_empty() and not b.you["hand"].is_empty():
		_set_selected(str(b.you["hand"].back()["id"]))
		selected = _board().find_card(_board().selected_id)
	if not selected.is_empty():
		inspector_title.text = str(selected["name"])
		inspector_type.text = str(selected["type"])
		inspector_text.text = str(selected["text"])
		var cat := _catalog()
		var art: Texture2D = null
		if cat:
			art = cat.texture_for(selected, "small")
		inspector_art.texture = art
	_paint_turn_border()
	_paint_library_btn()
	_paint_match_buttons()
	_refresh_ability_panel()
	_update_prompts()
	_refresh_mulligan()
	_refresh_coin()
	_refresh_debug()
	_refresh_gameover()
	var app := get_node_or_null("/root/AppState")
	var net := get_node_or_null("/root/GameNet")
	if app != null and app.mp_role == "host" and net != null and session != null and session.view != null:
		net.broadcast_view(session.view)
	if USE_ENGINE and session != null and session.view != null:
		if session.engine != null and session.engine.is_over():
			_set_status(str(session.view.prompt))
		elif not session.pending_draw_anim and str(session.view.prompt) != "" and log_label:
			log_label.text = str(session.view.prompt)

func _short_cmd(player: Dictionary) -> String:
	var cmd: Array = player["command"]
	if cmd.is_empty():
		return "—"
	var n := str(cmd[0]["name"])
	var cut := n.find(",")
	return n.substr(0, cut) if cut > 0 else n

func _set_pile(who: String, player: Dictionary) -> void:
	var lib = pile_labels["%s_library" % who]
	lib.text = str(player["library"])
	pile_labels["%s_graveyard" % who].text = str(player["graveyard"])
	pile_labels["%s_exile" % who].text = str(player["exile"])
	var cmd_node = pile_labels["%s_command" % who]
	if cmd_node is Button:
		(cmd_node as Button).text = _short_cmd(player)
	else:
		cmd_node.text = _short_cmd(player)

func _set_selected(card_id: String) -> void:
	if USE_ENGINE and session != null:
		session.selected_id = card_id
		## A guest's stand-in session has no engine: rebuilding its view would replace the host's board with an empty one
		## (everything then reads "your turn, Main 1"). The view comes from the host (see _sync_guest).
		if not _is_guest():
			session.rebuild_view()
	else:
		state.selected_id = card_id


func _on_select(card_id: String) -> void:
	if _in_blocking_mode():
		_on_block_click(card_id)
		return
	if _in_attack_mode():
		## Attackers are chosen by double-click (see _on_card_double_click); a single click only selects.
		_set_selected(card_id)
		_refresh()
		return
	_set_selected(card_id)
	_refresh()


func _is_guest() -> bool:
	var app := get_node_or_null("/root/AppState")
	return app != null and app.is_mp_client()


func _in_blocking_mode() -> bool:
	if _is_guest():
		var v = _board()
		return v != null and bool(v.blocks_for_you)
	return USE_ENGINE and session != null and session.awaiting_blocks


func _in_attack_mode() -> bool:
	if _is_guest():
		return _guest_attack
	return USE_ENGINE and session != null and session.choosing_attackers


## Attack mode: click a creature to add or remove it from the attack.
func _on_attack_click(card_id: String) -> void:
	var v = session.view
	var card: Dictionary = v.find_card(card_id)
	if card.is_empty() or not _card_in(v.you.get("creatures", []), card_id):
		_set_status("Pick your own creatures to attack with.")
		return
	var nm := str(card.get("name", "That creature"))
	if _pending_attackers.has(card_id):
		_pending_attackers.erase(card_id)
		_set_status("%s stays home." % nm)
		_refresh()
		return
	if not bool(card.get("ready_to_attack", false)):
		if bool(card.get("summoning_sick", false)):
			_set_status("%s has summoning sickness — it can attack on your next turn." % nm)
		elif bool(card.get("tapped", false)):
			_set_status("%s is tapped." % nm)
		else:
			_set_status("%s can't attack." % nm)
		return
	_pending_attackers.append(card_id)
	_set_status("%s will attack. Click the rival (top right) to send %d attacker(s), or pick more creatures." % [nm, _pending_attackers.size()])
	_refresh()


func _confirm_attack() -> void:
	var ids: Array = []
	for cid in _pending_attackers:
		ids.append(int(cid))
	if _is_guest():
		## The host plays the combat out; the new board comes back as a view.
		_client_net("attack_with", {"ids": ids})
		_pending_attackers.clear()
		_guest_attack = false
		_set_status("No attack." if ids.is_empty() else "Attacking with %d creature(s)…" % ids.size())
		return
	var life_bot := int(session.view.rival.get("life", 40))
	var r: SubmitResult = session.attack_with(ids)
	_pending_attackers.clear()
	if not r.ok:
		_set_status(r.error)
		_refresh()
		return
	if not ids.is_empty():
		_tap_sfx("hit")
	_refresh()
	var dealt := life_bot - int(session.view.rival.get("life", 40))
	if ids.is_empty():
		_set_status("No attack. " + str(session.view.prompt))
	elif dealt > 0:
		_set_status("Attack dealt %d damage. %s" % [dealt, str(session.view.prompt)])
	else:
		_set_status("Attack done. " + str(session.view.prompt))


## Border for a creature in combat, or null when it should use the normal border.
func _combat_border(card: Dictionary) -> Variant:
	var cid := str(card.get("id", ""))
	if cid == "":
		return null
	if cid == _block_pick:
		return GOLD
	if _pending_attackers.has(cid):
		return ATTACK_RED
	for group in _pending_blocks.values():
		if (group as Array).has(cid):
			return BLOCK_BLUE
	if str(card.get("blocking", "")) != "":
		return BLOCK_BLUE
	if bool(card.get("attacking", false)):
		return ATTACK_RED
	return null


## Blocking mode: click your creature, then the attacker it blocks. Click an assigned
## blocker again to take it back.
func _on_block_click(card_id: String) -> void:
	var v = session.view
	var card: Dictionary = v.find_card(card_id)
	if card.is_empty():
		return
	var nm := str(card.get("name", "That creature"))
	if _card_in(v.you.get("creatures", []), card_id):
		if bool(card.get("tapped", false)):
			_set_status("%s is tapped and can't block." % nm)
			return
		if _unassign_blocker(card_id):
			_block_pick = ""
			_set_status("%s won't block." % nm)
		elif _block_pick == card_id:
			_block_pick = ""
			_set_status(str(v.prompt))
		else:
			_block_pick = card_id
			_set_status("Now click the attacker %s should block." % nm)
		_refresh()
		return
	if _card_in(v.rival.get("creatures", []), card_id) and bool(card.get("attacking", false)):
		if _block_pick == "":
			_set_status("Click one of your untapped creatures first, then %s." % nm)
			return
		var blocker: Dictionary = v.find_card(_block_pick)
		var blocker_name := str(blocker.get("name", "Your creature"))
		if session.engine != null and not session.engine.can_block_attacker(int(_block_pick), int(card_id)):
			_set_status("%s can't block %s (it may need flying or reach)." % [blocker_name, nm])
			return
		_unassign_blocker(_block_pick)
		var group: Array = _pending_blocks.get(card_id, [])
		group.append(_block_pick)
		_pending_blocks[card_id] = group
		_block_pick = ""
		_set_status("%s blocks %s. Pick another, or Confirm blocks." % [blocker_name, nm])
		_refresh()
		return
	_set_status("Blocking: click one of your creatures, then an attacking creature.")


func _card_in(pile: Array, card_id: String) -> bool:
	for c in pile:
		if str(c.get("id", "")) == card_id:
			return true
	return false


## Removes card_id from any pending block. Returns true if it was assigned.
func _unassign_blocker(card_id: String) -> bool:
	for aid in _pending_blocks.keys():
		var group: Array = _pending_blocks[aid]
		if group.has(card_id):
			group.erase(card_id)
			if group.is_empty():
				_pending_blocks.erase(aid)
			return true
	return false


func _confirm_blocks() -> void:
	var life_you := int(session.view.you.get("life", 40))
	var payload := {}
	for aid in _pending_blocks.keys():
		var ids: Array = []
		for bid in _pending_blocks[aid]:
			ids.append(int(bid))
		payload[int(aid)] = ids
	if _is_guest():
		_client_net("blocks", {"blocks": payload})
		_pending_blocks.clear()
		_block_pick = ""
		_set_status("Blocks declared.")
		return
	var r: SubmitResult = session.declare_blocks(payload)
	if not r.ok:
		if r.error == "menace needs two blockers":
			_set_status("An attacker has menace — block it with two or more creatures, or not at all.")
		else:
			_set_status("Can't block like that: %s" % r.error)
		_refresh()
		return
	_pending_blocks.clear()
	_block_pick = ""
	_tap_sfx("hit")
	_refresh()
	var lost := life_you - int(session.view.you.get("life", 40))
	var msg := str(session.view.prompt)
	if session.pending_draw_anim:
		msg = "Your turn — click your deck to draw."
	if lost > 0:
		msg = "You lost %d life. " % lost + msg
	_set_status(msg)

func _zone_anchor(zone: String) -> Vector2:
	if not you_zones.has(zone):
		return get_viewport_rect().size * 0.5
	var node: Control = you_zones[zone]
	return node.get_global_rect().get_center() - Vector2(24, 34)

func _fly_card(card: Dictionary, from_pos: Vector2, to_pos: Vector2, done: Callable) -> void:
	var flyer := TextureRect.new()
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer.z_index = 70
	flyer.custom_minimum_size = Vector2(80, 112)
	flyer.size = Vector2(80, 112)
	flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flyer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var cat := _catalog()
	var tex: Texture2D = cat.texture_for(card, "small") if cat else null
	if tex:
		flyer.texture = tex
	else:
		var dummy := ColorRect.new()
		dummy.color = card.get("color", Color(0.45, 0.16, 0.08, 0.95))
		dummy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dummy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flyer.add_child(dummy)
		var nm := Label.new()
		nm.text = str(card.get("name", "?"))
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 12)
		nm.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
		nm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flyer.add_child(nm)
	flyer.global_position = from_pos
	add_child(flyer)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(flyer, "global_position", to_pos, 0.34)
	tw.parallel().tween_property(flyer, "scale", Vector2(0.62, 0.62), 0.34)
	tw.tween_callback(func() -> void:
		flyer.queue_free()
		done.call()
	)

func _on_hand_card(card_id: String) -> void:
	if USE_ENGINE:
		_engine_play_card(card_id)
		return
	var before: Dictionary = state.card_in_hand(card_id)
	var from_pos := get_global_mouse_position() - Vector2(40, 56)
	state.selected_id = card_id
	var msg := state.play_from_hand(card_id)
	var ok: bool = msg.begins_with("Played") or msg.begins_with("Cast")
	if ok:
		_tap_sfx("card")
	var to_pos := _zone_anchor("Lands")
	if msg.find("token") >= 0 or msg.find("Cast") >= 0:
		to_pos = _zone_anchor("Creatures")
	if ok and not before.is_empty():
		_fly_card(before, from_pos, to_pos, func() -> void:
			_refresh()
			_set_status(msg)
		)
		return
	_refresh()
	_set_status(msg)


func _engine_play_card(card_id: String) -> void:
	var b = _board()
	var before: Dictionary = b.find_card(card_id) if b != null else {}
	var play_zone := str(before.get("zone", "hand"))
	var play_kind := str(before.get("kind", ""))
	if _is_guest() and play_kind != "land" and (play_zone == "hand" or play_zone == "command" or play_zone == "battlefield"):
		_client_net("menu", {"id": int(card_id)})
		return
	if _client_net("play", {id = int(card_id), zone = play_zone, kind = play_kind}):
		return
	if session == null or session.view == null:
		return
	if session.match_start == GameSession.MatchStart.PUT_BACK:
		session.put_back_card(int(card_id))
		_refresh()
		return
	if not session.can_play():
		_set_status("Keep or Mulligan first.")
		return
	if before.is_empty():
		before = session.view.find_card(card_id)
	if before.is_empty():
		_set_status("Nothing selected.")
		return
	_set_selected(card_id)
	var oid := int(card_id)
	var from_pos := get_global_mouse_position() - Vector2(40, 56)
	var zone := str(before.get("zone", "hand"))
	var is_land := str(before.get("kind", "")) == "land"
	var r: SubmitResult
	## More than one way to cast it, or something besides casting to do with it: let the player pick.
	if not is_land and (zone == "hand" or zone == "command" or zone == "battlefield"):
		var menu: Array = session.card_menu(oid)
		var plain_only: bool = menu.size() == 1 and str((menu[0] as Dictionary).kind) == "cast" and (menu[0] as Dictionary).extra.is_empty()
		if menu.size() > 1 or (menu.size() == 1 and not plain_only and zone != "battlefield") or (zone == "battlefield" and menu.size() > 1):
			_open_card_menu(oid, menu, str(before.get("name", "Card")), "Choose how to play it")
			return
		if zone == "battlefield" and menu.size() == 1:
			r = session.run_card_entry(oid, menu[0])
			_refresh()
			_set_status(r.error if not r.ok else "Done.")
			return
	if zone == "battlefield":
		r = session.activate_auto(oid)
	elif is_land and zone == "hand":
		r = session.play_land(oid)
	else:
		r = session.cast_auto(0, oid)
	if r.ok and session.target_pending:
		_refresh()
		return
	var msg := r.error if not r.ok else _play_ok_message(before, zone, is_land)
	if r.ok:
		_tap_sfx("card")
		var to_pos := _zone_anchor("Lands" if is_land else "Creatures")
		_fly_card(before, from_pos, to_pos, func() -> void:
			_refresh()
			_set_status(msg)
		)
		return
	_refresh()
	_set_status(msg)

func _play_ok_message(before: Dictionary, zone: String, is_land: bool) -> String:
	var nm := str(before.get("name", "card"))
	if zone == "battlefield":
		return "Activated %s." % nm
	if is_land:
		return "Played %s." % nm
	if zone == "command":
		return "Cast commander %s." % nm
	return "Cast %s." % nm


func _paint_match_buttons() -> void:
	if not USE_ENGINE or session == null or session.view == null:
		return
	var v = session.view
	if _in_blocking_mode():
		if attack_btn:
			attack_btn.disabled = false
			attack_btn.text = "Confirm blocks" if not _pending_blocks.is_empty() else "No blocks"
			attack_btn.tooltip_text = "Lock in your blockers. Click your creature, then the attacker, to assign one."
		if pass_btn:
			pass_btn.disabled = true
	elif _in_attack_mode():
		if attack_btn:
			attack_btn.disabled = false
			attack_btn.text = ("Attack (%d)" % _pending_attackers.size()) if not _pending_attackers.is_empty() else "No attack"
			attack_btn.tooltip_text = "Send the creatures you picked. Click a creature to add or remove it."
		if pass_btn:
			pass_btn.disabled = true
	else:
		if attack_btn:
			attack_btn.text = "Attack"
			attack_btn.disabled = not bool(v.can_attack) or not session.can_play()
			attack_btn.tooltip_text = "Go to combat and choose which creatures attack."
		if pass_btn:
			pass_btn.disabled = not session.can_play()
			pass_btn.text = _next_phase_label(v)
	if declare_btn:
		var dsel: Dictionary = v.find_card(str(v.selected_id))
		var mine_creature: bool = not dsel.is_empty() and _card_in(v.you.get("creatures", []), str(dsel.get("id", "")))
		declare_btn.visible = mine_creature and bool(v.active_is_you) and not _in_blocking_mode()
		if declare_btn.visible:
			var ready: bool = bool(dsel.get("ready_to_attack", false)) and session.can_play() and not session.draw_waiting()
			declare_btn.disabled = not ready
			declare_btn.text = "Attack with this ⚔" if ready else ("Summoning sick" if bool(dsel.get("summoning_sick", false)) else "Can't attack now")
	if play_btn:
		var sel: Dictionary = v.find_card(str(v.selected_id))
		var zone := str(sel.get("zone", ""))
		if zone == "command":
			play_btn.text = "Cast commander"
		elif zone == "battlefield":
			play_btn.text = "Activate"
		elif str(sel.get("kind", "")) == "land":
			play_btn.text = "Play land"
		elif not sel.is_empty():
			play_btn.text = "Cast selected"
		else:
			play_btn.text = "Play selected"


func _on_attack() -> void:
	if _mp_wait():
		return
	if _is_guest():
		if _in_blocking_mode():
			_confirm_blocks()
			return
		if _guest_attack:
			_confirm_attack()
			return
		var gv = _board()
		if gv == null or not bool(gv.can_attack):
			_set_status("None of your creatures can attack right now.")
			return
		_guest_attack = true
		_pending_attackers.clear()
		_set_status("Declare attackers: click your creatures, then click the rival (top right). Press Attack with none picked to skip combat.")
		_refresh()
		return
	if not USE_ENGINE or session == null:
		return
	if _in_blocking_mode():
		_confirm_blocks()
		return
	if _in_attack_mode():
		_confirm_attack()
		return
	if not session.can_play():
		_set_status("Keep or Mulligan first.")
		return
	_pending_attackers.clear()
	var r: SubmitResult = session.begin_attack()
	_refresh()
	if not r.ok:
		_set_status(r.error)
		return
	_set_status(str(session.view.prompt))


## The green button: step to the next part of the turn.
func _on_next_phase() -> void:
	if _mp_wait():
		return
	if not USE_ENGINE or session == null or session.view == null:
		_on_next_stage()
		return
	if _client_net("pass"):
		return
	if not session.can_play():
		_set_status("Keep or Mulligan first.")
		return
	if _in_blocking_mode():
		_on_next_stage()
		return
	if _in_attack_mode():
		_confirm_attack()
		return
	var v = session.view
	if bool(v.active_is_you) and not session.draw_waiting() and str(v.turn_track) == "main1" and bool(v.can_attack):
		_on_attack()
		return
	if bool(v.active_is_you) and str(v.turn_track) == "end":
		## Past the end step comes the rival's turn, which End turn plays out.
		_on_end_turn()
		return
	_on_next_stage()


func _next_phase_label(v) -> String:
	## Holding priority with something on the stack (online): the button passes it.
	if bool(v.your_priority) and not v.stack.is_empty() and app_is_mp():
		return "Pass priority ▶"
	if not bool(v.active_is_you):
		return "Rival's turn"
	if session.draw_waiting():
		return "Draw card ▶"
	match str(v.turn_track):
		"upkeep":
			return "Draw ▶"
		"draw":
			return "Main 1 ▶"
		"main1":
			return "Combat ▶" if bool(v.can_attack) else "Main 2 ▶"
		"combat":
			return "Main 2 ▶"
		"main2":
			return "End step ▶"
	return "Next turn ▶"


func _on_next_stage() -> void:
	if _mp_wait():
		return
	if _client_net("pass"):
		return
	if USE_ENGINE:
		if _in_blocking_mode():
			_set_status("Choose your blockers, then Confirm blocks (or No blocks).")
			return
		if _in_attack_mode():
			_set_status("Pick attackers, then press Attack — or press it with none picked to skip combat.")
			return
		if session == null or not session.can_play():
			_set_status("Keep or Mulligan first.")
			return
		if session.draw_waiting():
			_on_click_library()
			return
		session.pass_once()
		_refresh()
		if session.engine != null and session.engine.is_over():
			_set_status("Game over.")
		return
	if not state.active_is_you:
		return
	state.next_stage()
	_refresh()
	_set_status("Advanced to %s." % state.phase_name())

func _client_net(kind: String, payload: Dictionary = {}) -> bool:

	var app := get_node_or_null("/root/AppState")
	if app != null and app.is_mp_client():
		var net := get_node_or_null("/root/GameNet")
		if net:
			net.send_action(kind, payload)
		return true
	return false


func _on_end_turn() -> void:
	if _mp_wait():
		return
	if _client_net("end_turn"):
		return
	if USE_ENGINE:
		if session == null:
			return
		if not session.can_play():
			_set_status("Keep or Mulligan first.")
			return
		if _in_blocking_mode():
			_set_status("Choose your blockers, then Confirm blocks (or No blocks).")
			return
		if session.draw_waiting():
			_set_status("Draw first — click your deck.")
			return
		_pending_attackers.clear()
		var life_you := int(session.view.you.get("life", 40))
		var life_bot := int(session.view.rival.get("life", 40))
		session.end_you_turn()
		_tap_sfx("mug")
		if session.awaiting_blocks:
			_pending_blocks.clear()
			_block_pick = ""
			_refresh()
			_set_status("You're being attacked! " + str(session.view.prompt))
			return
		_refresh()
		var you_lost: int = life_you - int(session.view.you.get("life", 40))
		var bot_lost: int = life_bot - int(session.view.rival.get("life", 40))
		if session.engine.is_over():
			_set_status(str(session.view.prompt))
		elif session.pending_draw_anim:
			var msg := "Your turn — click your deck to draw."
			if you_lost > 0:
				msg = "You lost %d life. " % you_lost + msg
			_set_status(msg)
		else:
			var msg2 := str(session.view.prompt)
			if you_lost > 0:
				msg2 += " You lost %d life." % you_lost
			if bot_lost > 0:
				msg2 += " Talrand lost %d life." % bot_lost
			_set_status(msg2)
		return
	if not state.active_is_you:
		return
	if not state.you_drew_this_turn:
		_set_status("Draw first — click your deck.")
		return
	var life_you := int(state.you["life"])
	var life_bot := int(state.rival["life"])
	state.end_turn()
	var msg := RivalAI.take_turn(state)
	state.begin_your_turn()
	var you_lost := life_you - int(state.you["life"])
	var bot_lost := life_bot - int(state.rival["life"])
	if you_lost > 0:
		msg += " You lost %d life." % you_lost
	if bot_lost > 0:
		msg += " Talrand lost %d life." % bot_lost
	if int(state.you["life"]) <= 0:
		msg += " You lost the game."
	else:
		msg += " Your turn — click your deck to draw."
	_tap_sfx("mug")
	_refresh()
	_set_status(msg)

func _on_click_library() -> void:
	if USE_ENGINE:
		if session == null or not session.can_play():
			_set_status("Keep or Mulligan first.")
			return
		if not session.pending_draw_anim:
			_set_status("You have already drawn this turn.")
			return
		## Online guest: the host takes the card (and asks about dredge); the new hand comes back in the view.
		if _client_net("draw"):
			_set_status("Drawing…")
			return
		var drawn: Dictionary = session.ack_draw()
		if drawn.is_empty():
			_refresh()
			_set_status("No card to draw.")
			return
		_tap_sfx("draw")
		_show_draw_preview(drawn)
		var from_pos := Vector2(size.x - 250, size.y - 110)
		if deck_btn:
			from_pos = deck_btn.get_global_rect().position
		var to_pos := Vector2(size.x * 0.35, size.y - 140)
		if hand_row:
			to_pos = hand_row.get_global_rect().get_center() - Vector2(40, 56)
		_fly_card(drawn, from_pos, to_pos, func() -> void:
			_hide_draw_preview()
			_refresh()
			_set_status("Drew %s. Library %d." % [str(drawn.get("name", "a card")), int(session.view.you["library"])])
		)
		return
	var msg := state.start_your_turn()
	var drawn: Dictionary = state.find_card(state.selected_id)
	if not drawn.is_empty():
		_apply_scryfall([drawn])
	if msg.begins_with("Drew"):
		_tap_sfx("draw")
		var from_pos := Vector2(size.x - 250, size.y - 110)
		if deck_btn:
			from_pos = deck_btn.get_global_rect().position
		var to_pos := Vector2(size.x * 0.35, size.y - 140)
		if hand_row:
			to_pos = hand_row.get_global_rect().get_center() - Vector2(40, 56)
		_fly_card(drawn, from_pos, to_pos, func() -> void:
			_refresh()
			_set_status(msg)
		)
		return
	_refresh()
	_set_status(msg)

func _paint_library_btn() -> void:
	if you_library_btn == null:
		return
	var need := _waiting_for_draw()
	var st := StyleBoxFlat.new()
	st.set_corner_radius_all(4)
	st.bg_color = TURN_GREEN.darkened(0.25) if need else Color(0.16, 0.17, 0.18)
	you_library_btn.add_theme_stylebox_override("normal", st)
	you_library_btn.add_theme_color_override("font_color", Color(0.05, 0.12, 0.05) if need else INK)
	you_library_btn.tooltip_text = "Click to draw" if need else "Your library"

func _on_click_command() -> void:
	if not USE_ENGINE or session == null or session.view == null:
		return
	var cmds: Array = session.view.you.get("command", [])
	if cmds.is_empty():
		_set_status("Command zone is empty.")
		return
	_set_selected(str(cmds[0].get("id", "")))
	_refresh()
	_set_status("Selected commander. Play selected to cast.")


func _on_activate() -> void:
	if USE_ENGINE:
		if session == null:
			return
		var sid: String = str(session.selected_id)
		if sid == "":
			_set_status("Select a card first.")
			return
		_engine_play_card(sid)
		return
	if not state.active_is_you:
		return
	var msg := state.activate_selected()
	if msg.begins_with("Played") or msg.begins_with("Cast"):
		_tap_sfx("card")
	_refresh()
	_set_status(msg)

func _tap_sfx(kind: String) -> void:
	if sfx == null or sfx.muted:
		return
	match kind:
		"card":
			sfx.play_card()
		"hit":
			sfx.play_hit()
		"draw":
			sfx.play_draw()
		"mug":
			sfx.play_mug()
		"dice":
			sfx.play_dice()

## Music volume bar for the header (0-100%, default 70%).

## Shows "⚔ 12/21 Krenko" under a life total once that player has taken commander damage.
func _paint_cmdr_damage(label: Label, player: Dictionary) -> void:
	if label == null:
		return
	var hits: Array = player.get("cmdr_damage", [])
	if hits.is_empty():
		label.visible = false
		return
	var need := int(player.get("cmdr_need", 21))
	var worst: Dictionary = hits[0]
	var lines: PackedStringArray = []
	for h in hits:
		if int(h.amount) > int(worst.amount):
			worst = h
		lines.append("%s: %d/%d" % [str(h.name), int(h.amount), need])
	var n := str(worst.name)
	var cut := n.find(",")
	label.text = "⚔ %d/%d %s" % [int(worst.amount), need, n.substr(0, cut) if cut > 0 else n]
	label.tooltip_text = "Commander damage taken — " + ", ".join(lines) + ". %d from one commander loses the game." % need
	label.add_theme_color_override("font_color", ATTACK_RED if int(worst.amount) >= need - 6 else MUTED)
	label.visible = true


func _paint_life(label: Label, life: int) -> void:
	if label == null:
		return
	label.text = str(life)
	var low := Color(0.86, 0.22, 0.18)
	label.add_theme_color_override("font_color", low if life < 10 else GOLD)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_on_next_stage()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_on_end_turn()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F3:
		_show_debug = not _show_debug
		if debug_label:
			debug_label.visible = _show_debug
		_refresh_debug()
		get_viewport().set_input_as_handled()

func _on_dice() -> void:
	if dice_overlay:
		dice_overlay.visible = true

func _hide_dice() -> void:
	if dice_overlay:
		dice_overlay.visible = false

func _build_dice_tray() -> void:
	dice_overlay = ColorRect.new()
	dice_overlay.color = Color(0.02, 0.03, 0.03, 0.72)
	dice_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dice_overlay.visible = false
	dice_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	dice_overlay.z_index = 100
	dice_overlay.z_as_relative = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dice_overlay.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = GOLD.darkened(0.2)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Dice"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Click a die to roll it."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", MUTED)
	col.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var colors: Array[Color] = [
		Color(0.25, 0.55, 0.48),
		Color(0.85, 0.82, 0.72),
		Color(0.72, 0.22, 0.18),
		Color(0.12, 0.12, 0.14),
		Color(0.42, 0.28, 0.62),
		Color(0.82, 0.58, 0.16),
	]
	var sides_list: Array[int] = [4, 6, 8, 10, 12, 20]
	for i in sides_list.size():
		row.add_child(_make_die_button(sides_list[i], colors[i]))
	col.add_child(row)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 32)
	close.pressed.connect(_hide_dice)
	col.add_child(close)
	panel.add_child(col)
	center.add_child(panel)
	add_child(dice_overlay)

func _make_die_button(sides: int, color: Color) -> Button:
	var b := Button.new()
	b.text = "d%d\n-" % sides
	b.custom_minimum_size = Vector2(72, 72)
	b.add_theme_font_size_override("font_size", 16)
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(10)
	st.set_border_width_all(2)
	st.border_color = Color(1, 1, 1, 0.35)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	var ink := Color(0.08, 0.08, 0.08) if color.get_luminance() > 0.45 else Color(0.95, 0.95, 0.92)
	b.add_theme_color_override("font_color", ink)
	b.pressed.connect(_roll_die.bind(sides, b))
	return b

func _roll_die(sides: int, btn: Button) -> void:
	if bool(_dice_busy.get(sides, false)):
		return
	_dice_busy[sides] = true
	_tap_sfx("dice")
	btn.pivot_offset = btn.size * 0.5
	if btn.pivot_offset == Vector2.ZERO:
		btn.pivot_offset = Vector2(36, 36)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "rotation_degrees", btn.rotation_degrees + 420.0 + rng.randf() * 180.0, 0.55)
	tw.parallel().tween_property(btn, "scale", Vector2(1.18, 1.18), 0.16)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.22)
	var flicker := create_tween()
	for _i in 11:
		var face := rng.randi_range(1, sides)
		flicker.tween_callback(_set_die_face.bind(btn, sides, face))
		flicker.tween_interval(0.045)
	var result := rng.randi_range(1, sides)
	flicker.tween_callback(_finish_die_roll.bind(btn, sides, result))

func _set_die_face(btn: Button, sides: int, face: int) -> void:
	btn.text = "d%d\n%d" % [sides, face]

func _finish_die_roll(btn: Button, sides: int, result: int) -> void:
	btn.text = "d%d\n%d" % [sides, result]
	btn.rotation_degrees = fmod(btn.rotation_degrees, 360.0)
	_dice_busy[sides] = false
	_set_status("Rolled a d%d: %d." % [sides, result])

func _build_draw_preview() -> void:
	draw_preview_host = CenterContainer.new()
	draw_preview_host.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	draw_preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_preview_host.z_index = 60
	draw_preview_host.visible = false
	add_child(draw_preview_host)


func _show_draw_preview(card: Dictionary) -> void:
	if draw_preview_host == null:
		return
	for c in draw_preview_host.get_children():
		c.queue_free()
	var face := _make_card_face(card, Vector2(180, 252))
	draw_preview_host.add_child(face)
	draw_preview_host.visible = true


func _hide_draw_preview() -> void:
	if draw_preview_host:
		draw_preview_host.visible = false


func _refresh_ability_panel() -> void:
	if ability_box == null:
		return
	while ability_box.get_child_count() > 0:
		var old := ability_box.get_child(0)
		ability_box.remove_child(old)
		old.free()
	if not USE_ENGINE or session == null or session.engine == null:
		return
	var eng: RulesEngine = session.engine
	if eng.state.mode == EngineEnums.EngineMode.AWAITING_DECISION and int(eng.state.awaiting.get("player_id", -1)) == 0:
		var dec: PlayerDecision = eng.state.pending_decision as PlayerDecision
		if dec != null:
			var prompt := Label.new()
			prompt.text = dec.prompt
			prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			prompt.add_theme_font_size_override("font_size", 12)
			ability_box.add_child(prompt)
		return
	var sid := str(session.selected_id)
	if sid == "" or not sid.is_valid_int():
		return
	var obj: GameObject = eng.state.objects.get(int(sid))
	if obj == null or obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
		return
	var report: Dictionary = eng.activation_report(obj.object_id)
	var rows: Array = report.get("abilities", [])
	var shown := 0
	for row in rows:
		if not (row is Dictionary):
			continue
		var info: Dictionary = row
		if not bool(info.get("can_activate", false)):
			continue
		shown += 1
		var btn := Button.new()
		var cost := str(info.get("cost", ""))
		var cond := str(info.get("condition", ""))
		btn.text = cost if cond == "" or cond == "—" else "%s  (%s)" % [cost, cond]
		btn.pressed.connect(_on_ability_button.bind(obj.object_id, str(info.get("ability_id", ""))))
		ability_box.add_child(btn)
	if shown == 0 and not rows.is_empty():
		var why := Label.new()
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.add_theme_font_size_override("font_size", 11)
		var parts: PackedStringArray = PackedStringArray()
		for row2 in rows:
			if row2 is Dictionary:
				parts.append("%s: %s" % [str((row2 as Dictionary).get("cost", "")), str((row2 as Dictionary).get("reason", ""))])
		why.text = "\n".join(parts)
		ability_box.add_child(why)


## Pick screens: a land's optional reveal / life payment, targets, and the engine's own questions
## (hideaway, discard, surveil, colors, discover ...). Shown over the table until answered.
var _choice_dialog: ChoiceDialog = null
## Pick menu for one card's ways to cast or use it (kicker, dash, flashback, cycling, crew, turn face up ...).
var _menu_entries: Array = []
var _menu_oid: int = 0


func _open_card_menu(oid: int, entries: Array, title: String, sub: String = "") -> void:
	_close_choice()
	_menu_entries = entries
	_menu_oid = oid
	var options: Array = []
	for i in entries.size():
		var en: Dictionary = entries[i]
		options.append({"value": i, "label": str(en.label), "detail": str(en.detail)})
	_choice_dialog = ChoiceDialog.new()
	_choice_dialog.signature = "menu:%d:%d" % [oid, entries.size()]
	add_child(_choice_dialog)
	_choice_dialog.show_choices(title, sub, options, "Cancel")
	_choice_dialog.picked.connect(_on_menu_picked)
	_choice_dialog.cancelled.connect(func() -> void:
		_menu_entries = []
		_close_choice()
	)


func _on_menu_picked(value: Variant) -> void:
	var idx := int(value)
	var entries: Array = _menu_entries
	var oid := _menu_oid
	_menu_entries = []
	_close_choice()
	if _is_guest():
		_client_net("menu_pick", {"id": oid, "index": idx})
		return
	if session == null or idx < 0 or idx >= entries.size():
		return
	var entry: Dictionary = entries[idx]
	var target_oid := int(entry.get("object_id", oid))
	var r: SubmitResult = session.run_card_entry(target_oid, entry)
	_refresh()
	if r.ok:
		_tap_sfx("card")
	_set_status(r.error if not r.ok else "%s." % str(entry.get("label", "Done")))


func _on_click_pile(zone_id: int, title: String) -> void:
	if not USE_ENGINE or session == null:
		return
	var entries: Array = session.zone_menu(zone_id)
	if entries.is_empty():
		_set_status("Nothing in %s can be cast right now." % title)
		return
	_open_card_menu(0, entries, "Cast from %s" % title)


## The open pick screen for this player: the session's for the host (or a solo game), the host's view for a guest.
func _current_prompt() -> Dictionary:
	if _is_guest():
		var v = _board()
		return v.you_prompt if v != null else {}
	if session == null or session.engine == null:
		return {}
	return session.prompt_for(session.you_seat)


func _update_prompts() -> void:
	var data: Dictionary = _current_prompt()
	var want_sig := str(data.get("sig", ""))
	var kind := str(data.get("kind", ""))
	var title := str(data.get("title", ""))
	var sub := str(data.get("sub", ""))
	var options: Array = data.get("options", [])
	var cancel_text := str(data.get("cancel", ""))
	var faces: Array = []
	## Show the cards the question is about, face up, so you can read what they do.
	for fd in data.get("faces", []):
		faces.append(_make_card_face(fd, Vector2(210, 294)))
	if want_sig == "" and not _menu_entries.is_empty():
		return
	if want_sig == "":
		if _choice_dialog != null:
			_choice_dialog.queue_free()
			_choice_dialog = null
		return
	if _choice_dialog != null and _choice_dialog.signature == want_sig:
		return
	if _choice_dialog != null:
		_choice_dialog.queue_free()
	_choice_dialog = ChoiceDialog.new()
	_choice_dialog.signature = want_sig
	add_child(_choice_dialog)
	_choice_dialog.show_choices(title, sub, options, cancel_text, faces)
	_choice_dialog.option_hovered.connect(_on_dialog_option_hover)
	_choice_dialog.option_unhovered.connect(_on_unhover_card)
	_choice_dialog.picked.connect(_on_choice_picked.bind(kind))
	_choice_dialog.cancelled.connect(_on_choice_cancelled.bind(kind))


func _on_dialog_option_hover(card: Dictionary) -> void:
	if hover_wrap != null:
		hover_wrap.z_index = 120  ## above the pick screen
	_on_hover_card(card)


func _close_choice() -> void:
	if _choice_dialog != null:
		_choice_dialog.queue_free()
		_choice_dialog = null


func _on_choice_picked(value: Variant, kind: String) -> void:
	_close_choice()
	if _client_net("answer", {"kind": kind, "value": value}):
		return
	if session == null:
		return
	match kind:
		"land":
			var r: SubmitResult = session.answer_land(bool(value))
			_refresh()
			_set_status(r.error if not r.ok else "Land played.")
		"target":
			var r2: SubmitResult = session.choose_target(int(value))
			_refresh()
			_set_status(r2.error if not r2.ok else "Target chosen.")
		"decision":
			var dec: PlayerDecision = session.engine.state.pending_decision as PlayerDecision
			if dec != null and dec.kind == &"OPTIONAL_YES_NO":
				_on_decision_button(bool(value), null)
			else:
				_on_decision_button(true, value)


func _on_choice_cancelled(kind: String) -> void:
	_close_choice()
	if _client_net("answer", {"kind": kind, "cancel": true}):
		return
	if session == null:
		return
	match kind:
		"target":
			session.cancel_target()
			_refresh()
			_set_status("Cancelled.")
		"decision":
			_on_decision_button(false, null)


func _decision_button(label: String, accept: bool, choice: Variant) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(func() -> void:
		_on_decision_button(accept, choice)
	)
	return btn


func _on_ability_button(object_id: int, ability_id: String) -> void:
	if session == null:
		return
	var r: SubmitResult = session.activate_ability(object_id, StringName(ability_id))
	_refresh()
	if r.ok:
		_set_status("Activated.")
	else:
		_set_status(r.error)


func _on_decision_button(accept: bool, choice: Variant) -> void:
	if session == null or session.engine == null:
		return
	var a := GameAction.new()
	a.kind = GameAction.Kind.SUBMIT_DECISION if accept else GameAction.Kind.DECLINE_DECISION
	a.player_id = 0
	if choice != null:
		a.extra = {choice = choice}
	var r: SubmitResult = session.submit(a)
	if r.ok:
		session.resolve_stack_then_yield()
	_refresh()
	if not r.ok:
		_set_status(r.error)


func _build_debug_label() -> void:
	debug_label = Label.new()
	debug_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	debug_label.offset_left = 10
	debug_label.offset_top = 52
	debug_label.offset_right = 430
	debug_label.offset_bottom = 220
	debug_label.add_theme_font_size_override("font_size", 11)
	debug_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.7, 0.9))
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.z_index = 40
	debug_label.visible = _show_debug
	add_child(debug_label)


func _refresh_debug() -> void:
	if debug_label == null or not _show_debug or session == null or session.engine == null:
		if debug_label:
			debug_label.visible = false
		return
	debug_label.visible = true
	var lines := PackedStringArray()
	lines.append("BF-%d  seed %d  state %s" % [BUILD, session.last_seed, str(session.match_start)])
	lines.append("Library remaining: %d" % session.engine.library_size(0))
	lines.append("Hand size: %d" % session.engine.hand_size(0))
	lines.append("Mulligans: %d" % session.engine.state.players[0].mulligan_count)
	for dline in session.debug_lines:
		lines.append(str(dline))
	var sid := str(session.selected_id)
	if sid.is_valid_int():
		var selected_obj: GameObject = session.engine.state.objects.get(int(sid))
		if selected_obj != null and selected_obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
			var report: Dictionary = session.engine.activation_report(selected_obj.object_id)
			lines.append(str(report.get("text", "")))
	debug_label.text = "\n".join(lines)
	debug_label.offset_bottom = 560


## Before the opening hands: call heads or tails to see who goes first (CR 103.1).
func _build_coin_overlay() -> void:
	coin_overlay = ColorRect.new()
	coin_overlay.color = Color(0.02, 0.03, 0.04, 0.92)
	coin_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	coin_overlay.offset_top = 44
	coin_overlay.z_index = 90
	coin_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	coin_overlay.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = GOLD
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 24
	st.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.text = "Coin flip"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	col.add_child(title)
	coin_status = Label.new()
	coin_status.text = "Call it. The winner goes first."
	coin_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_status.add_theme_font_size_override("font_size", 16)
	coin_status.add_theme_color_override("font_color", MUTED)
	col.add_child(coin_status)
	var coin := PanelContainer.new()
	coin.custom_minimum_size = Vector2(150, 150)
	coin.size_flags_horizontal = SIZE_SHRINK_CENTER
	var cst := StyleBoxFlat.new()
	cst.bg_color = Color(0.86, 0.68, 0.16)
	cst.set_corner_radius_all(75)
	cst.set_border_width_all(8)
	cst.border_color = Color(1.0, 0.9, 0.5)
	coin.add_theme_stylebox_override("panel", cst)
	coin_face = Label.new()
	coin_face.text = "?"
	coin_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_face.add_theme_font_size_override("font_size", 30)
	coin_face.add_theme_color_override("font_color", Color(0.25, 0.16, 0.02))
	coin.add_child(coin_face)
	col.add_child(coin)
	coin_call_row = HBoxContainer.new()
	coin_call_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_call_row.add_theme_constant_override("separation", 16)
	for side in [["HEADS", true], ["TAILS", false]]:
		var b := Button.new()
		b.text = str(side[0])
		b.custom_minimum_size = Vector2(150, 46)
		b.add_theme_font_size_override("font_size", 18)
		var bst := StyleBoxFlat.new()
		bst.bg_color = TURN_GREEN.darkened(0.1)
		bst.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", bst)
		b.add_theme_color_override("font_color", Color(0.06, 0.12, 0.05))
		b.pressed.connect(_on_coin_call.bind(bool(side[1])))
		coin_call_row.add_child(b)
	col.add_child(coin_call_row)
	coin_continue = Button.new()
	coin_continue.text = "Draw opening hands"
	coin_continue.custom_minimum_size = Vector2(240, 46)
	coin_continue.add_theme_font_size_override("font_size", 18)
	coin_continue.visible = false
	coin_continue.pressed.connect(_on_coin_continue)
	col.add_child(coin_continue)
	panel.add_child(col)
	center.add_child(panel)
	add_child(coin_overlay)


## Online coin flip: the guest calls it, the host flips it. Both screens run off the host's view.
func _refresh_coin_mp() -> void:
	var v = _board()
	var show: bool = v != null and bool(v.coin_flip)
	coin_overlay.visible = show
	if not show:
		_coin_state = 0
		return

	var rival_name := str(v.rival.get("name", "Your rival"))
	if not bool(v.flip_called):
		_coin_state = 0
		coin_face.text = "?"
		coin_continue.visible = false
		coin_call_row.visible = bool(v.caller_is_you)
		coin_status.text = "Call it. The winner goes first." if bool(v.caller_is_you) else "%s is calling the coin…" % rival_name
		return
	if _coin_state != 0:
		return
	_coin_state = 1
	coin_call_row.visible = false
	coin_continue.visible = false
	var caller := "You" if bool(v.caller_is_you) else rival_name
	coin_status.text = "%s called %s…" % [caller, "heads" if bool(v.you_called_heads) else "tails"]
	_play_coin_sound()
	var tw := create_tween()
	var delay := 0.06
	for i in 14:
		var face_text := "HEADS" if i % 2 == 0 else "TAILS"
		tw.tween_callback(func() -> void: coin_face.text = face_text)
		tw.tween_interval(delay)
		delay += 0.025
	tw.tween_callback(_coin_landed_mp)


func _coin_landed_mp() -> void:
	var v = _board()
	if v == null:
		return
	var app := get_node_or_null("/root/AppState")
	coin_face.text = "HEADS" if bool(v.coin_heads) else "TAILS"
	var rival_name := str(v.rival.get("name", "Your rival"))
	coin_status.text = ("It's %s. You go first!" if bool(v.first_is_you) else "It's %s. %s goes first.") % (["heads" if bool(v.coin_heads) else "tails"] if bool(v.first_is_you) else ["heads" if bool(v.coin_heads) else "tails", rival_name])
	_coin_state = 2
	## The host deals the opening hands a moment after the result has been shown to both players.
	if app != null and app.mp_role == "host":
		## A timer node owned by the table: it goes away with the table if the host leaves first (T-012).
		var tm := Timer.new()
		tm.one_shot = true
		tm.wait_time = 2.0
		add_child(tm)
		tm.timeout.connect(_finish_coin_mp)
		tm.start()


func _refresh_coin() -> void:
	if coin_overlay == null or session == null:
		return
	var app_c := get_node_or_null("/root/AppState")
	if app_c != null and app_c.is_mp():
		_refresh_coin_mp()
		return
	var show: bool = USE_ENGINE and session.match_start == GameSession.MatchStart.COIN_FLIP
	coin_overlay.visible = show
	if not show:
		_coin_state = 0
		return
	if _coin_state == 0:
		coin_face.text = "?"
		coin_status.text = "Call it. The winner goes first."
		coin_call_row.visible = true
		coin_continue.visible = false


func _on_coin_call(heads: bool) -> void:
	if session == null or _coin_state != 0:
		return
	## A guest calls the coin on the host's table; the flip then plays on both screens from the host's view.
	if _client_net("call_coin", {"heads": heads}):
		coin_call_row.visible = false
		coin_status.text = "You called %s…" % ("heads" if heads else "tails")
		return
	_coin_state = 1
	session.call_coin(heads)
	coin_call_row.visible = false
	coin_status.text = "You called %s…" % ("heads" if heads else "tails")
	_play_coin_sound()
	var tw := create_tween()
	var delay := 0.06
	for i in 14:
		var face_text := "HEADS" if i % 2 == 0 else "TAILS"
		tw.tween_callback(func() -> void: coin_face.text = face_text)
		tw.tween_interval(delay)
		delay += 0.025
	tw.tween_callback(_coin_landed)


func _coin_landed() -> void:
	if session == null:
		return
	coin_face.text = "HEADS" if session.coin_heads else "TAILS"
	var wins: bool = session.first_player == session.you_seat
	coin_status.text = ("It's %s. You go first!" if wins else "It's %s. Talrand goes first.") % ("heads" if session.coin_heads else "tails")
	coin_continue.visible = true
	_coin_state = 2


func _on_coin_continue() -> void:
	if session == null or _coin_state != 2:
		return
	session.finish_coin_flip()
	_coin_state = 0
	_refresh()
	if session.first_player != session.you_seat:
		_set_status("Talrand won the flip and goes first.")


func _build_mulligan_overlay() -> void:
	mulligan_overlay = ColorRect.new()
	mulligan_overlay.color = Color(0.02, 0.03, 0.04, 0.88)
	mulligan_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mulligan_overlay.offset_top = 44
	mulligan_overlay.z_index = 85
	mulligan_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mulligan_overlay.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = GOLD
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	mulligan_title = Label.new()
	mulligan_title.text = "Keep hand?"
	mulligan_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mulligan_title.add_theme_font_size_override("font_size", 26)
	mulligan_title.add_theme_color_override("font_color", GOLD)
	col.add_child(mulligan_title)
	mulligan_sub = Label.new()
	mulligan_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mulligan_sub.add_theme_color_override("font_color", MUTED)
	col.add_child(mulligan_sub)
	mulligan_hand_row = HBoxContainer.new()
	mulligan_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mulligan_hand_row.add_theme_constant_override("separation", 8)
	col.add_child(mulligan_hand_row)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	keep_btn = Button.new()
	keep_btn.text = "KEEP"
	keep_btn.custom_minimum_size = Vector2(160, 44)
	keep_btn.add_theme_font_size_override("font_size", 18)
	var keep_st := StyleBoxFlat.new()
	keep_st.bg_color = TURN_GREEN.darkened(0.1)
	keep_st.set_corner_radius_all(8)
	keep_btn.add_theme_stylebox_override("normal", keep_st)
	keep_btn.add_theme_color_override("font_color", Color(0.06, 0.12, 0.05))
	keep_btn.pressed.connect(_on_keep_hand)
	btns.add_child(keep_btn)
	mulligan_btn = Button.new()
	mulligan_btn.text = "MULLIGAN"
	mulligan_btn.custom_minimum_size = Vector2(160, 44)
	mulligan_btn.add_theme_font_size_override("font_size", 18)
	var mul_st := StyleBoxFlat.new()
	mul_st.bg_color = YOU_EMBER
	mul_st.set_corner_radius_all(8)
	mulligan_btn.add_theme_stylebox_override("normal", mul_st)
	mulligan_btn.add_theme_color_override("font_color", Color(0.98, 0.94, 0.88))
	mulligan_btn.pressed.connect(_on_mulligan_hand)
	btns.add_child(mulligan_btn)
	col.add_child(btns)
	panel.add_child(col)
	center.add_child(panel)
	add_child(mulligan_overlay)


func _make_card_face(card: Dictionary, sz: Vector2) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = sz
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06)
	bg.set_corner_radius_all(8)
	bg.set_border_width_all(2)
	bg.border_color = GOLD.darkened(0.2)
	wrap.add_theme_stylebox_override("panel", bg)
	var cat := _catalog()
	var tex: Texture2D = null
	if cat:
		tex = cat.texture_for(card, "normal") if sz.x >= 120 else cat.texture_for(card, "small")
		if tex == null:
			tex = cat.texture_for(card, "small")
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = sz
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.name = "art_tex"
		wrap.add_child(tr)
		_upgrade_face_when_art_arrives(wrap, card, sz)
		return wrap
	_upgrade_face_when_art_arrives(wrap, card, sz)
	var caption := CardFaceScript.art_caption(card)
	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 2)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Label.new()
	n.text = str(card.get("name", "?"))
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_font_size_override("font_size", 11 if sz.x < 100 else 13)
	n.add_theme_color_override("font_color", Color(0.98, 0.96, 0.9))
	name_row.add_child(n)
	var mc := Label.new()
	mc.text = str(card.get("mana_cost", ""))
	mc.add_theme_font_size_override("font_size", 10)
	mc.add_theme_color_override("font_color", GOLD)
	name_row.add_child(mc)
	inner.add_child(name_row)
	var art_box := ColorRect.new()
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.color = card.get("color", Color(0.32, 0.14, 0.08, 0.95))
	art_box.custom_minimum_size = Vector2(sz.x - 12, maxf(28.0, sz.y * 0.38))
	if caption != "":
		var art_lab := Label.new()
		art_lab.text = caption
		art_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art_lab.add_theme_font_size_override("font_size", 10)
		art_lab.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
		art_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_box.add_child(art_lab)
	inner.add_child(art_box)
	var ty := Label.new()
	ty.text = str(card.get("type", ""))
	ty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ty.add_theme_font_size_override("font_size", 9)
	ty.add_theme_color_override("font_color", MUTED)
	inner.add_child(ty)
	var tx := Label.new()
	tx.text = str(card.get("text", ""))
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.add_theme_font_size_override("font_size", 9)
	tx.add_theme_color_override("font_color", INK)
	tx.size_flags_vertical = SIZE_EXPAND_FILL
	inner.add_child(tx)
	var pt := str(card.get("power", ""))
	if pt != "":
		var ptl := Label.new()
		ptl.text = "%s/%s" % [pt, str(card.get("toughness", ""))]
		ptl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ptl.add_theme_color_override("font_color", GOLD)
		inner.add_child(ptl)
	wrap.add_child(inner)
	return wrap


## A card picture still downloading ("Loading art...") turns into the full card image as soon as it arrives,
## and the small image is upgraded to the large one when that lands.
func _upgrade_face_when_art_arrives(wrap: Control, card: Dictionary, sz: Vector2) -> void:
	var cat := _catalog()
	if cat == null or not cat.has_signal("art_updated") or not CardFaceScript.has_artwork(card):
		return
	var cb := func(_cid: String) -> void:
		if not is_instance_valid(wrap):
			return
		var t: Texture2D = cat.texture_for(card, "normal")
		if t == null:
			return
		var tr := wrap.get_node_or_null("art_tex") as TextureRect
		if tr == null:
			for ch in wrap.get_children():
				ch.queue_free()
			tr = TextureRect.new()
			tr.name = "art_tex"
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.custom_minimum_size = sz
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.add_child(tr)
		tr.texture = t
	cat.art_updated.connect(cb)
	wrap.tree_exited.connect(func() -> void:
		if cat.art_updated.is_connected(cb):
			cat.art_updated.disconnect(cb))


func _refresh_mulligan() -> void:
	if mulligan_overlay == null:
		return
	var board = _board()
	## A guest has no session of its own: everything comes from the host's view (see GameNet.receive_view).
	var app := get_node_or_null("/root/AppState")
	var guest: bool = app != null and app.is_mp_client()
	var st := -1
	var you_kept := false
	var rival_kept := true
	if USE_ENGINE and session != null and not guest:
		st = session.match_start
		you_kept = bool(session.kept.get(session.you_seat, false))
		rival_kept = bool(session.kept.get(1 - int(session.you_seat), true))
	elif board is TableView:
		st = int(board.match_start)
		you_kept = bool(board.you_kept)
		rival_kept = bool(board.rival_kept)
	if st < 0:
		mulligan_overlay.visible = false
		return
	var deciding := st == GameSession.MatchStart.MULLIGAN_DECISION or st == GameSession.MatchStart.PUT_BACK
	## Once you have kept (and put cards back), the screen is yours again while you wait for the other player.
	var show := deciding and not you_kept
	mulligan_overlay.visible = show
	if deciding and you_kept and not rival_kept:
		if not _mulligan_wait_shown:
			_mulligan_wait_shown = true
			_set_status("Hand kept. Waiting for the other player to keep or mulligan.")
	else:
		_mulligan_wait_shown = false
	if not show:
		return
	var you: Dictionary = board.you if board != null else {}
	var hand: Array = you.get("hand", [])
	var lib_n := int(you.get("library", 0))
	var mcount := int(you.get("mulligans", 0))
	var guest_put: int = int(board.putback_you) if guest and board is TableView else 0
	if guest_put > 0:
		mulligan_title.text = "Put %d card(s) on the bottom" % guest_put
		mulligan_sub.text = "Click a card. Library %d. Mulligans: %d" % [lib_n, mcount]
		keep_btn.visible = false
		mulligan_btn.visible = false
	elif st == GameSession.MatchStart.PUT_BACK and session != null and not guest:
		mulligan_title.text = "Put %d card(s) on the bottom" % session.put_back_remaining
		mulligan_sub.text = "Click a card. Library %d. Mulligans: %d" % [lib_n, mcount]
		keep_btn.visible = false
		mulligan_btn.visible = false
	else:
		mulligan_title.text = "Keep hand?"
		mulligan_sub.text = "Opening 7  ·  Library remaining: %d  ·  Mulligans: %d" % [lib_n, mcount]
		keep_btn.visible = true
		mulligan_btn.visible = true
	_clear(mulligan_hand_row)
	var sig := "%d:%d:%d" % [st, mcount, hand.size()]
	var animate := sig != _mulligan_sig
	_mulligan_sig = sig
	var i := 0
	for card in hand:
		var face := _make_card_face(card, Vector2(132, 184))
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 184)
		b.clip_contents = true
		var empty := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", empty)
		b.add_theme_stylebox_override("hover", empty)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(face)
		var cid := str(card.get("id", ""))
		b.pressed.connect(_on_mulligan_card.bind(cid))
		if animate:
			b.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_interval(0.07 * i)
			tw.tween_property(b, "modulate:a", 1.0, 0.18)
		mulligan_hand_row.add_child(b)
		i += 1


func _on_mulligan_card(card_id: String) -> void:
	if session == null:
		return
	if _is_guest():
		var gb = _board()
		if gb != null and int(gb.putback_you) > 0:
			_client_net("put_back", {"id": int(card_id)})
		return
	if session.match_start == GameSession.MatchStart.PUT_BACK:
		session.put_back_card(int(card_id))
		_refresh()
		if session.can_play():
			_set_status("Hand kept. Library %d. Your turn." % session.engine.library_size(0))
		elif session.put_back_remaining > 0:
			_set_status("Put %d more on the bottom." % session.put_back_remaining)


func _on_keep_hand() -> void:
	if _client_net("keep"):
		return
	if session == null:
		return
	session.keep_hand(0)
	_refresh()
	if session.can_play():
		_set_status("Hand kept. Library %d. Your turn." % session.engine.library_size(0))
	else:
		_set_status("Put cards on the bottom of your library.")


func _on_mulligan_hand() -> void:
	if _client_net("mulligan"):
		return
	if session == null:
		return
	session.take_mulligan(0)
	_refresh()
	_set_status("Mulligan %d. New 7 from the shuffled library." % session.engine.state.players[0].mulligan_count)


func _build_quit_confirm() -> void:
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Leave match"
	quit_dialog.dialog_text = "Leave this match and return to the main menu?"
	quit_dialog.ok_button_text = "Leave"
	quit_dialog.confirmed.connect(_leave_to_menu)
	add_child(quit_dialog)


func _on_menu() -> void:
	var app_m := get_node_or_null("/root/AppState")
	for node in menu_solo_nodes:
		(node as Control).visible = not (app_m != null and app_m.is_mp())
	menu_overlay.visible = true

func _hide_menu() -> void:
	menu_overlay.visible = false

func _on_open_import() -> void:
	_hide_menu()
	if import_overlay:
		import_overlay.open()


func _on_play_imported(deck: NormalizedDeck, rows: Dictionary) -> void:
	_mulligan_sig = ""
	if session == null:
		session = GameSession.new()
		session.manual_draw = true
		session.coin_flip = true
		session.debug_enabled = DEBUG_MATCH
	session.start_imported(deck, rows)
	_refresh()
	_set_status("Imported %s. Keep or Mulligan." % deck.name)


func _on_new_game() -> void:
	_mulligan_sig = ""
	if USE_ENGINE:
		session = GameSession.new()
		session.manual_draw = true
		session.coin_flip = true
		session.debug_enabled = DEBUG_MATCH
		session.start_table_demo()
	else:
		state = MatchStateScript.new()
		_hydrate_from_scryfall()
	menu_overlay.visible = false
	if dice_overlay:
		dice_overlay.visible = false
	_was_tapped.clear()
	_refresh()
	if USE_ENGINE:
		_set_status("Opening hand — Keep or Mulligan. Library %d." % session.engine.library_size(0))
	else:
		_set_status("New game vs Talrand. Hover a card to enlarge it. Click a card to play it.")

func _on_art_updated(_card_id: String) -> void:
	_refresh()


## Online: true (with a message) while it is the other player's turn to act, so the buttons don't fire on the host's
## table out of turn.
func _mp_wait() -> bool:
	var app := get_node_or_null("/root/AppState")
	if app == null or not app.is_mp():
		return false
	var b = _board()
	if b == null or bool(b.your_priority):
		return false
	_set_status("Waiting for %s…" % str(b.rival.get("name", "the other player")))
	return true


## Tells the guest why their action didn't work (the host's session recorded the reason).
func _notice_if_failed(player_id: int) -> void:
	var net := get_node_or_null("/root/GameNet")
	if net != null and session != null and session.last_error != "" and player_id != 0:
		net.send_notice(player_id, session.last_error)


## Online: the other player left or lost their connection. The match can't go on, so say so and offer the way out.
func _on_peer_left(player_name: String) -> void:
	if gameover_overlay == null:
		return
	if _gameover_shown:
		return  ## the game was already decided; leaving afterwards is normal
	_peer_left = true
	gameover_title.text = "MATCH ENDED"
	gameover_title.add_theme_color_override("font_color", MUTED)
	gameover_sub.text = "%s left the match." % player_name
	gameover_again.visible = false
	gameover_overlay.visible = true


func _finish_coin_mp() -> void:
	if session != null and session.match_start == GameSession.MatchStart.COIN_FLIP and session.flip_called:
		session.finish_coin_flip()
		_coin_state = 0
		_refresh()


## A guest clicked a card ("menu") or chose one of its ways to be played ("menu_pick"). Runs as the guest's seat.
## One plain way plays at once; several are sent to the guest as a pick screen, like the host's own table shows.
func _net_card_menu(kind: String, oid: int, index: int, player_id: int) -> void:
	var menu: Array = session.card_menu(oid)
	if kind == "menu_pick":
		if index >= 0 and index < menu.size():
			session.run_card_entry(oid, menu[index])
		return
	var obj: GameObject = session.engine.state.objects.get(oid)
	var zone_battlefield: bool = obj != null and obj.zone == EngineEnums.ZoneId.BATTLEFIELD
	var plain_only: bool = menu.size() == 1 and str((menu[0] as Dictionary).kind) == "cast" and (menu[0] as Dictionary).extra.is_empty()
	var ask: bool = menu.size() > 1 or (menu.size() == 1 and not plain_only and not zone_battlefield)
	if ask:
		var entries: Array = []
		for en in menu:
			entries.append({"label": str(en.label), "detail": str(en.detail)})
		var name_s := "Card"
		if obj != null and obj.definition is CardDefinition:
			name_s = (obj.definition as CardDefinition).name
		var net := get_node_or_null("/root/GameNet")
		if net != null:
			net.send_menu(player_id, oid, name_s, entries)
		return
	if zone_battlefield and menu.size() == 1:
		session.run_card_entry(oid, menu[0])
	elif zone_battlefield:
		session.activate_auto(oid)
	else:
		session.cast_auto(player_id, oid)


## Guest: the host sent the ways to play the card that was clicked.
func _on_menu_received(oid: int, title: String, entries: Array) -> void:
	_open_card_menu(oid, entries, title, "Choose how to play it")


func app_is_mp() -> bool:
	var app := get_node_or_null("/root/AppState")
	return app != null and app.is_mp()


## The Audio button beside History opens a small panel with the two volume sliders (music, effects) and a mute box.
func _toggle_audio() -> void:
	if audio_panel == null:
		_build_audio_panel()
	audio_panel.visible = not audio_panel.visible


func _build_audio_panel() -> void:
	audio_panel = PanelContainer.new()
	audio_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	audio_panel.anchor_left = 1.0
	audio_panel.anchor_right = 1.0
	audio_panel.offset_left = -340
	audio_panel.offset_right = -12
	audio_panel.offset_top = 48
	audio_panel.z_index = 95
	var st := StyleBoxFlat.new()
	st.bg_color = UiStyle.BG
	st.border_color = GOLD.darkened(0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	audio_panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "AUDIO"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(_toggle_audio)
	head.add_child(close)
	col.add_child(head)
	var sub := Label.new()
	sub.text = "SOUND SETTINGS"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", MUTED)
	col.add_child(sub)
	var sfx_node := get_node_or_null("/root/Sfx")
	col.add_child(_audio_row("Master Volume", "speaker", sfx_node.master if sfx_node != null else 1.0, func(v: float) -> void:
		if sfx_node != null:
			sfx_node.set_master(v)))
	col.add_child(_audio_row("Music", "note", music.volume if music != null else 0.7, func(v: float) -> void:
		if music != null:
			music.set_volume(v)))
	col.add_child(_audio_row("Effects", "swords", sfx_node.volume if sfx_node != null else 0.7, func(v: float) -> void:
		if sfx_node != null:
			sfx_node.set_volume(v)))
	var mute := CheckBox.new()
	mute.text = "Mute music"
	mute.button_pressed = music != null and music.muted
	mute.toggled.connect(func(on: bool) -> void:
		if music != null:
			music.set_muted(on)
	)
	col.add_child(mute)
	audio_panel.add_child(col)
	audio_panel.visible = false
	add_child(audio_panel)


## One audio row: icon, name, slider and percentage. `on_change` gets the new volume as 0..1.
func _audio_row(label_text: String, icon_kind: String, start: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(AudioIcon.new(icon_kind))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(lab)
	var pct := Label.new()
	pct.text = "%d%%" % int(round(start * 100.0))
	pct.add_theme_color_override("font_color", GOLD)
	head.add_child(pct)
	col.add_child(head)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 1
	sl.value = start * 100.0
	sl.custom_minimum_size = Vector2(190, 18)
	sl.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v)
		on_change.call(v / 100.0)
	)
	col.add_child(sl)
	row.add_child(col)
	return row


func _exit_tree() -> void:
	var sfx_node := get_node_or_null("/root/Sfx")
	if sfx_node != null:
		sfx_node.set_match_active(false)


## The coin toss sound (Sfx synthesizes it, or plays audio/sfx/coin_flip.ogg if you add one).
func _play_coin_sound() -> void:
	var sfx_node := get_node_or_null("/root/Sfx")
	if sfx_node != null:
		sfx_node.play_coin_flip()


# --- Attacking with the mouse: double-click each attacker, then right-click and choose Attack (or press Attack) ----

var _last_chip_click := {"id": "", "t": 0}


## Left double-click on a permanent adds / removes it as an attacker; right-click opens the Attack menu.
func _on_chip_input(ev: InputEvent, cid: String) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var now := Time.get_ticks_msec()
		## The board is rebuilt after the first click, so a double-click is recognised by card and time too.
		var dbl: bool = mb.double_click or (str(_last_chip_click.id) == cid and now - int(_last_chip_click.t) <= 400)
		_last_chip_click = {"id": cid, "t": now}
		if dbl:
			_last_chip_click = {"id": "", "t": 0}
			_on_card_double_click.call_deferred(cid)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_on_card_right_click.call_deferred(cid)


## Double-click one of your creatures that can attack: it joins the attack (no menu, no confirmation). The first one
## starts the attack step; double-click it again to take it back out.
func _on_card_double_click(cid: String) -> void:
	if _in_blocking_mode():
		return
	var v = _board()
	if v == null or not bool(v.active_is_you) or not _card_in(v.you.get("creatures", []), cid):
		return
	if not _in_attack_mode():
		if _mp_wait():
			return
		_pending_attackers.clear()
		if _is_guest():
			if not bool(v.can_attack):
				_set_status("None of your creatures can attack right now.")
				return
			_guest_attack = true
		else:
			if session == null or not session.can_play():
				return
			var r: SubmitResult = session.begin_attack()
			if not r.ok:
				_refresh()
				_set_status(r.error)
				return
	_on_attack_click(cid)


## Right-click a creature while attackers are picked: Attack with them, or clear the choice.
func _on_card_right_click(cid: String) -> void:
	if not _in_attack_mode():
		return
	var menu := PopupMenu.new()
	var n := _pending_attackers.size()
	menu.add_item("Attack with %d creature%s" % [n, "" if n == 1 else "s"], 0)
	menu.set_item_disabled(0, n == 0)
	menu.add_item("Clear attackers", 1)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_confirm_attack()
		else:
			_pending_attackers.clear()
			_refresh()
	)
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


## The inside of a life box: a panel that shades from a lighter top to a darker bottom in the player's colour, so the
## box reads as raised (the outer frame has the border and drop shadow).
func _life_face(content: Control, accent: Color) -> Control:
	var face := PanelContainer.new()
	var grad := Gradient.new()
	grad.set_color(0, accent.darkened(0.45))
	grad.set_color(1, accent.darkened(0.80))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 4
	gtex.height = 64
	var st := StyleBoxTexture.new()
	st.texture = gtex
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	face.add_theme_stylebox_override("panel", st)
	face.add_child(content)
	return face
