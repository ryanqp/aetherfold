extends Control

const USE_ENGINE := true
const BUILD := 30
const DEBUG_MATCH := true
const MatchStateScript := preload("res://scripts/match_state.gd")
const RivalAI := preload("res://scripts/rival_ai.gd")
const ThemeMusicScript := preload("res://scripts/theme_music.gd")
const TavernSfxScript := preload("res://scripts/tavern_sfx.gd")
const RIVAL_TEAL := Color(0.18, 0.42, 0.48)
const YOU_EMBER := Color(0.42, 0.18, 0.08)
const PANEL := Color(0.10, 0.11, 0.12, 0.94)
const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const HAND_CHIP := Vector2(80, 112)
const BOARD_CHIP := Vector2(48, 68)
const TURN_GREEN := Color(0.18, 0.78, 0.32)
const TURN_RED := Color(0.86, 0.16, 0.14)
const DIFFICULTY_HINTS := [
	"Misses draws, rarely attacks.",
	"Plays a land and one spell.",
	"Dumps cheap spells for Drakes.",
	"Always attacks, casts commander, holds counters.",
]
const DIE_SPECS := [
	{sides = 4, color = Color(0.25, 0.55, 0.48)},
	{sides = 6, color = Color(0.85, 0.82, 0.72)},
	{sides = 8, color = Color(0.72, 0.22, 0.18)},
	{sides = 10, color = Color(0.12, 0.12, 0.14)},
	{sides = 12, color = Color(0.42, 0.28, 0.62)},
	{sides = 20, color = Color(0.82, 0.58, 0.16)},
]

var state = MatchStateScript.new()
var session = null
var music
var sfx
var you_zones: Dictionary = {}
var rival_zones: Dictionary = {}
var pile_labels: Dictionary = {}
var menu_diff_buttons: Array = []
var _flash_t := 0.0
var _was_tapped: Dictionary = {}
var _dice_busy: Dictionary = {}
var _mulligan_sig := ""
var import_overlay: ImportOverlay

@onready var header_label: Label = %HeaderLabel
@onready var you_life: Label = %YouLifeLabel
@onready var rival_life: Label = %RivalLifeLabel
@onready var rival_title_label: Label = %RivalTitleLabel
@onready var inspector_art: TextureRect = %InspectorArt
@onready var inspector_title: Label = %InspectorTitle
@onready var inspector_type: Label = %InspectorType
@onready var inspector_text: Label = %InspectorText
@onready var log_label: Label = %LogLabel
@onready var mute_button: Button = %MuteBtn
@onready var sfx_button: Button = %SfxBtn
@onready var hand_row: HBoxContainer = %HandRow
@onready var menu_overlay: ColorRect = %MenuOverlay
@onready var turn_border: Panel = %TurnBorder
@onready var hover_wrap: CenterContainer = %HoverWrap
@onready var hover_art: TextureRect = %HoverArt
@onready var hover_name: Label = %HoverName
@onready var you_library_btn: Button = %YouLibraryBtn
@onready var draw_btn: Button = %DrawBtn
@onready var deck_btn: Button = %DeckBtn
@onready var play_btn: Button = %PlayBtn
@onready var pass_btn: Button = %PassBtn
@onready var attack_btn: Button = %AttackBtn
@onready var dice_overlay: ColorRect = %DiceOverlay
@onready var mulligan_overlay: ColorRect = %MulliganOverlay
@onready var mulligan_hand_row: HBoxContainer = %MulliganHandRow
@onready var mulligan_title: Label = %MulliganTitle
@onready var mulligan_sub: Label = %MulliganSub
@onready var keep_btn: Button = %KeepBtn
@onready var mulligan_btn: Button = %MulliganBtn
@onready var debug_label: Label = %DebugLabel
@onready var draw_preview_host: CenterContainer = %DrawPreviewHost

func _ready() -> void:
	music = ThemeMusicScript.new()
	music.name = "ThemeMusic"
	add_child(music)
	sfx = TavernSfxScript.new()
	sfx.name = "TavernSfx"
	add_child(sfx)
	you_zones = {
		"Creatures": %YouCreaturesCards,
		"Non-creature permanents": %YouNoncreaturesCards,
		"Lands": %YouLandsCards,
	}
	rival_zones = {
		"Creatures": %RivalCreaturesCards,
		"Non-creature permanents": %RivalNoncreaturesCards,
		"Lands": %RivalLandsCards,
	}
	pile_labels = {
		"you_library": you_library_btn,
		"you_graveyard": %YouGyLabel,
		"you_exile": %YouExileLabel,
		"you_command": %YouCommandBtn,
		"rival_library": %RivalLibraryLabel,
		"rival_graveyard": %RivalGyLabel,
		"rival_exile": %RivalExileLabel,
		"rival_command": %RivalCommandLabel,
	}
	menu_diff_buttons = [%DiffBtn0, %DiffBtn1, %DiffBtn2, %DiffBtn3]
	for i in menu_diff_buttons.size():
		var b: Button = menu_diff_buttons[i]
		b.text = "%s — %s" % [RivalAI.label(i), DIFFICULTY_HINTS[i]]
		b.pressed.connect(_on_pick_difficulty.bind(i))
	_setup_die_buttons()
	var cat := _catalog()
	if cat and cat.has_signal("art_updated") and not cat.art_updated.is_connected(_on_art_updated):
		cat.art_updated.connect(_on_art_updated)
	var net := get_node_or_null("/root/GameNet")
	if net and net.has_signal("view_received") and not net.view_received.is_connected(_refresh):
		net.view_received.connect(_refresh)
	add_to_group("aetherfold_table")
	if USE_ENGINE:
		session = GameSession.new()
		session.debug_enabled = DEBUG_MATCH
		_start_from_app_state()
	else:
		_hydrate_from_scryfall()
	import_overlay = preload("res://scenes/ui/import_overlay.tscn").instantiate()
	add_child(import_overlay)
	import_overlay.play_imported.connect(_on_play_imported)
	_paint_turn_border()
	_refresh()
	if USE_ENGINE:
		_set_status("Opening hand — Keep or Mulligan.")
	else:
		_set_status("Your turn. Hover a card to enlarge it. Click a card to play it.")


func _setup_die_buttons() -> void:
	var buttons := [%DieD4, %DieD6, %DieD8, %DieD10, %DieD12, %DieD20]
	for i in buttons.size():
		var b: Button = buttons[i]
		var spec: Dictionary = DIE_SPECS[i]
		var color: Color = spec.color
		var ink := Color(0.08, 0.08, 0.08) if color.get_luminance() > 0.45 else Color(0.95, 0.95, 0.92)
		b.add_theme_color_override("font_color", ink)
		b.pressed.connect(_roll_die.bind(int(spec.sides), b))


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
		session.debug_enabled = DEBUG_MATCH
	if app != null:
		session.difficulty = int(app.difficulty)
		session.skip_ai = bool(app.skip_ai)
		session.you_seat = int(app.you_seat)
		if app.is_mp_client():
			return
		var demo = app.make_demo()
		session.start_with_demo(demo)
		return
	session.start_table_demo()


func _on_main_menu() -> void:
	var net := get_node_or_null("/root/GameNet")
	if net and net.has_method("leave"):
		net.leave()
	var app := get_node_or_null("/root/AppState")
	if app:
		app.reset_match_flags()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func apply_net_action(kind: String, payload: Dictionary, player_id: int) -> void:
	if session == null:
		return
	match kind:
		"keep":
			session.keep_hand(player_id)
		"mulligan":
			session.take_mulligan(player_id)
		"pass":
			session.pass_once()
		"end_turn":
			session.end_you_turn()
		"attack":
			session.attack_all()
		"play":
			var oid := int(payload.get("id", 0))
			var zone := str(payload.get("zone", "hand"))
			if zone == "battlefield":
				session.activate_auto(oid)
			elif str(payload.get("kind", "")) == "land":
				session.play_land(oid)
			else:
				session.cast_auto(player_id, oid)
	_refresh()

func _set_status(text: String) -> void:
	if log_label:
		log_label.text = text

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

func _waiting_for_draw() -> bool:
	if USE_ENGINE:
		return session != null and session.pending_draw_anim
	return state != null and state.active_is_you and not state.you_drew_this_turn

func _process(dt: float) -> void:
	_flash_t += dt
	_paint_flash()

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
	if turn_border and wait:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.draw_center = false
		st.set_border_width_all(10)
		st.border_color = TURN_GREEN.lerp(Color(0.65, 1.0, 0.5), pulse)
		turn_border.add_theme_stylebox_override("panel", st)

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

func _on_hover_card(card: Dictionary) -> void:
	if hover_wrap == null:
		return
	hover_name.text = str(card.get("name", ""))
	var cat := _catalog()
	var tex: Texture2D = null
	if cat:
		tex = cat.texture_for(card, "normal")
		if tex == null:
			tex = cat.texture_for(card, "small")
	hover_art.texture = tex
	hover_art.visible = tex != null
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

func _card_chip(card: Dictionary, compact: bool = false, from_hand: bool = false) -> Button:
	var b := Button.new()
	b.clip_contents = true
	b.custom_minimum_size = BOARD_CHIP if compact else HAND_CHIP
	var selected: bool = str(card.get("id", "")) == str(_board().selected_id)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.set_corner_radius_all(6)
	st.set_border_width_all(2)
	st.border_color = GOLD if selected else Color(0, 0, 0, 0.55)
	st.content_margin_left = 0
	st.content_margin_right = 0
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.text = ""
	var face := _make_card_face(card, b.custom_minimum_size)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(face)
	var cid := str(card.get("id", ""))
	b.mouse_entered.connect(_on_hover_card.bind(card.duplicate()))
	b.mouse_exited.connect(_on_unhover_card)
	if from_hand:
		b.pressed.connect(_on_hand_card.bind(cid))
	else:
		b.pressed.connect(_on_select.bind(cid))
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

func _refresh() -> void:
	var b = _board()
	header_label.text = "%s   BF-%d" % [b.header_text(), BUILD]
	if you_life:
		you_life.text = str(b.you["life"])
	if rival_life:
		rival_life.text = str(b.rival["life"])
	if rival_title_label:
		rival_title_label.text = "Talrand · %s" % RivalAI.label(b.difficulty)
	_fill_zone(you_zones["Creatures"], b.you["creatures"])
	_fill_zone(you_zones["Non-creature permanents"], b.you["noncreatures"])
	_fill_zone(you_zones["Lands"], b.you["lands"], true)
	_fill_zone(rival_zones["Creatures"], b.rival["creatures"])
	_fill_zone(rival_zones["Non-creature permanents"], b.rival["noncreatures"])
	_fill_zone(rival_zones["Lands"], b.rival["lands"], true)
	_clear(hand_row)
	for card in b.you["hand"]:
		hand_row.add_child(_card_chip(card, false, true))
	_set_pile("you", b.you)
	_set_pile("rival", b.rival)
	if deck_btn:
		deck_btn.text = "Deck\n%d" % int(b.you["library"])
		deck_btn.tooltip_text = "Library: %d cards left. Click to ack draw." % int(b.you["library"])
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
	_paint_difficulty_buttons()
	_paint_turn_border()
	_paint_library_btn()
	_paint_match_buttons()
	_refresh_mulligan()
	_refresh_debug()
	var app := get_node_or_null("/root/AppState")
	var net := get_node_or_null("/root/GameNet")
	if app != null and app.mp_role == "host" and net != null and session != null and session.view != null:
		net.broadcast_view(session.view)
	if USE_ENGINE and session != null and session.view != null:
		if session.engine != null and session.engine.is_over():
			_set_status(str(session.view.prompt))
		elif not session.pending_draw_anim and str(session.view.prompt) != "":
			_set_status(str(session.view.prompt))

func _paint_difficulty_buttons() -> void:
	for i in menu_diff_buttons.size():
		var b: Button = menu_diff_buttons[i]
		var on: bool = i == int(_board().difficulty)
		var st := StyleBoxFlat.new()
		st.bg_color = GOLD.darkened(0.15) if on else Color(0.16, 0.17, 0.18)
		st.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_color_override("font_color", Color(0.12, 0.10, 0.04) if on else INK)

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
		session.rebuild_view()
	else:
		state.selected_id = card_id


func _on_select(card_id: String) -> void:
	_set_selected(card_id)
	_refresh()

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
	if _client_net("play", {id = int(card_id), zone = str(before.get("zone", "hand")), kind = str(before.get("kind", ""))}):
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
	if zone == "battlefield":
		r = session.activate_auto(oid)
	elif is_land and zone == "hand":
		r = session.play_land(oid)
	else:
		r = session.cast_auto(0, oid)
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
	if attack_btn:
		attack_btn.disabled = not bool(v.can_attack) or not session.can_play()
		attack_btn.tooltip_text = "Attack with every creature that can."
	if pass_btn:
		pass_btn.disabled = not session.can_play()
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
	if _client_net("attack"):
		return
	if not USE_ENGINE or session == null:
		return
	if not session.can_play():
		_set_status("Keep or Mulligan first.")
		return
	var r: SubmitResult = session.attack_all()
	_tap_sfx("card")
	_refresh()
	if not r.ok:
		_set_status(r.error)
		return
	_set_status("Attackers declared.")


func _on_next_stage() -> void:
	if _client_net("pass"):
		return
	if USE_ENGINE:
		if session == null or not session.can_play():
			_set_status("Keep or Mulligan first.")
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
	if _client_net("end_turn"):
		return
	if USE_ENGINE:
		if session == null:
			return
		if not session.can_play():
			_set_status("Keep or Mulligan first.")
			return
		var life_you := int(session.view.you.get("life", 40))
		var life_bot := int(session.view.rival.get("life", 40))
		session.end_you_turn()
		_tap_sfx("mug")
		_refresh()
		var you_lost: int = life_you - int(session.view.you.get("life", 40))
		var bot_lost: int = life_bot - int(session.view.rival.get("life", 40))
		if session.engine.is_over():
			_set_status(str(session.view.prompt))
		elif session.pending_draw_anim:
			var msg := "Your turn — click Draw."
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
		_set_status("Draw first — use the Draw button.")
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
		msg += " Your turn — click Draw."
	_tap_sfx("mug")
	_refresh()
	_set_status(msg)

func _on_click_library() -> void:
	if USE_ENGINE:
		if session == null or not session.can_play():
			_set_status("Keep or Mulligan first.")
			return
		var drawn: Dictionary = {}
		if session.pending_draw_anim:
			drawn = session.ack_draw()
		else:
			drawn = session.draw_from_library(0)
			if drawn.is_empty():
				_refresh()
				_set_status("Library is empty.")
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
		"draw":
			sfx.play_draw()
		"mug":
			sfx.play_mug()
		"dice":
			sfx.play_dice()

func _on_mute() -> void:
	if music == null:
		return
	var on: bool = music.toggle_mute()
	mute_button.text = "Music" if on else "Mute"
	_set_status("Music off." if on else "Music on.")

func _on_sfx() -> void:
	if sfx == null:
		return
	var on: bool = sfx.toggle_mute()
	sfx_button.text = "SFX off" if on else "SFX"
	_set_status("Tavern sounds off." if on else "Tavern sounds on.")

func _on_dice() -> void:
	if dice_overlay:
		dice_overlay.visible = true

func _hide_dice() -> void:
	if dice_overlay:
		dice_overlay.visible = false

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


func _refresh_debug() -> void:
	if debug_label == null or not DEBUG_MATCH or session == null or session.engine == null:
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
	debug_label.text = "\n".join(lines)


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
		wrap.add_child(tr)
		return wrap
	var awaiting_art := str(card.get("scryfall_id", "")) != "" or str(card.get("imageUrl", "")) != ""
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
	var art_lab := Label.new()
	art_lab.text = "Loading art…" if awaiting_art else "Card frame"
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


func _refresh_mulligan() -> void:
	if mulligan_overlay == null:
		return
	var board = _board()
	var st := -1
	if USE_ENGINE and session != null:
		st = session.match_start
	elif board is TableView:
		st = int(board.match_start)
	if st < 0:
		mulligan_overlay.visible = false
		return
	var show := st == GameSession.MatchStart.MULLIGAN_DECISION or st == GameSession.MatchStart.PUT_BACK
	mulligan_overlay.visible = show
	if not show:
		return
	var you: Dictionary = board.you if board != null else {}
	var hand: Array = you.get("hand", [])
	var lib_n := int(you.get("library", 0))
	var mcount := 0
	if session != null and session.engine != null:
		mcount = session.engine.state.players[session.you_seat].mulligan_count
	if st == GameSession.MatchStart.PUT_BACK:
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
	if session.match_start == GameSession.MatchStart.PUT_BACK:
		session.put_back_card(int(card_id))
		_refresh()
		if session.can_play():
			_set_status("Hand kept. Library %d. Your turn." % session.engine.library_size(0))
		elif session.match_start == GameSession.MatchStart.PUT_BACK:
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


func _on_menu() -> void:
	menu_overlay.visible = true
	_paint_difficulty_buttons()

func _hide_menu() -> void:
	menu_overlay.visible = false

func _on_pick_difficulty(d: int) -> void:
	var v := clampi(d, 0, 3)
	if USE_ENGINE and session != null:
		session.difficulty = v
		session.rebuild_view()
	else:
		state.difficulty = v
	_paint_difficulty_buttons()
	if rival_title_label:
		rival_title_label.text = "Talrand · %s" % RivalAI.label(v)
	_set_status("Talrand set to %s. End turn to let the rival play." % RivalAI.label(v))

func _on_open_import() -> void:
	_hide_menu()
	if import_overlay:
		import_overlay.open()


func _on_play_imported(deck: NormalizedDeck, rows: Dictionary) -> void:
	_mulligan_sig = ""
	if session == null:
		session = GameSession.new()
		session.debug_enabled = DEBUG_MATCH
	session.start_imported(deck, rows)
	_refresh()
	_set_status("Imported %s. Keep or Mulligan." % deck.name)


func _on_new_game() -> void:
	var d := int(_board().difficulty)
	_mulligan_sig = ""
	if USE_ENGINE:
		session = GameSession.new()
		session.difficulty = d
		session.debug_enabled = DEBUG_MATCH
		session.start_table_demo()
	else:
		state = MatchStateScript.new()
		state.difficulty = d
		_hydrate_from_scryfall()
	menu_overlay.visible = false
	if dice_overlay:
		dice_overlay.visible = false
	_was_tapped.clear()
	_refresh()
	if USE_ENGINE:
		_set_status("Opening hand — Keep or Mulligan. Library %d." % session.engine.library_size(0))
	else:
		_set_status("New game vs Talrand · %s. Hover a card to enlarge it. Click a card to play it." % RivalAI.label(d))

func _on_art_updated(_card_id: String) -> void:
	_refresh()
