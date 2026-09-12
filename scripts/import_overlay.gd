class_name ImportOverlay
extends ColorRect

signal cancelled
signal play_imported(deck: NormalizedDeck, rows: Dictionary)
signal deck_saved(deck: NormalizedDeck, rows: Dictionary)

const GOLD := Color(0.93, 0.78, 0.28)
const INK := Color(0.93, 0.93, 0.90)
const MUTED := Color(0.72, 0.74, 0.70)
const TURN_GREEN := Color(0.18, 0.78, 0.32)

var input_box: TextEdit
var progress_label: Label
var preview_label: Label
var unresolved_label: Label
var import_btn: Button
var confirm_btn: Button
var update_btn: Button
var save_new_btn: Button
var retry_btn: Button
var ignore_btn: Button
var preview_row: HBoxContainer
var last_result: Dictionary = {}
var existing_path: String = ""
var busy := false
var auto_play := true


func _ready() -> void:
	color = Color(0.02, 0.03, 0.04, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 90
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.09, 0.10, 0.98)
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = GOLD
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(720, 0)
	var title := Label.new()
	title.text = "IMPORT DECK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Paste a Moxfield / Archidekt / TappedOut / Deckstats URL, or a decklist."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	input_box = TextEdit.new()
	input_box.custom_minimum_size = Vector2(680, 120)
	input_box.placeholder_text = "https://www.moxfield.com/decks/...\n\nor\n\n1 Sol Ring\n1 Command Tower\nCommander\n1 Krenko, Mob Boss"
	col.add_child(input_box)
	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", GOLD)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(progress_label)
	preview_row = HBoxContainer.new()
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_theme_constant_override("separation", 8)
	col.add_child(preview_row)
	preview_label = Label.new()
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.add_theme_font_size_override("font_size", 13)
	col.add_child(preview_label)
	unresolved_label = Label.new()
	unresolved_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unresolved_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))
	col.add_child(unresolved_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	import_btn = _btn("IMPORT", TURN_GREEN.darkened(0.1), Color(0.06, 0.12, 0.05), _on_import)
	row.add_child(import_btn)
	retry_btn = _btn("Retry", Color(0.16, 0.17, 0.18), INK, _on_import)
	retry_btn.visible = false
	row.add_child(retry_btn)
	ignore_btn = _btn("Ignore unresolved", Color(0.16, 0.17, 0.18), INK, _on_ignore)
	ignore_btn.visible = false
	row.add_child(ignore_btn)
	col.add_child(row)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 10)
	confirm_btn = _btn("IMPORT DECK", GOLD.darkened(0.15), Color(0.12, 0.10, 0.04), _on_confirm_new)
	confirm_btn.visible = false
	row2.add_child(confirm_btn)
	update_btn = _btn("Update existing deck", Color(0.16, 0.17, 0.18), INK, _on_update)
	update_btn.visible = false
	row2.add_child(update_btn)
	save_new_btn = _btn("Save as new deck", Color(0.16, 0.17, 0.18), INK, _on_confirm_new)
	save_new_btn.visible = false
	row2.add_child(save_new_btn)
	var cancel := _btn("CANCEL", Color(0.16, 0.17, 0.18), INK, _on_cancel)
	row2.add_child(cancel)
	col.add_child(row2)
	panel.add_child(col)
	center.add_child(panel)


func open() -> void:
	visible = true
	last_result = {}
	existing_path = ""
	progress_label.text = ""
	preview_label.text = ""
	unresolved_label.text = ""
	confirm_btn.visible = false
	update_btn.visible = false
	save_new_btn.visible = false
	retry_btn.visible = false
	ignore_btn.visible = false
	_clear_preview()


func _btn(text: String, bg: Color, fg: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 36)
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_color_override("font_color", fg)
	b.pressed.connect(cb)
	return b


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func _on_import() -> void:
	if busy:
		return
	busy = true
	import_btn.disabled = true
	progress_label.text = "Detecting deck source..."
	preview_label.text = ""
	unresolved_label.text = ""
	confirm_btn.visible = false
	await get_tree().process_frame
	var pipe := ImportPipeline.new()
	var result: Dictionary = pipe.run(input_box.text, true)
	last_result = result
	busy = false
	import_btn.disabled = false
	_show_result(result)


func _on_ignore() -> void:
	if last_result.is_empty():
		return
	last_result["unresolved"] = PackedStringArray()
	_show_result(last_result)


func _on_confirm_new() -> void:
	_commit("")


func _on_update() -> void:
	_commit(existing_path)


func _commit(replace_path: String) -> void:
	var deck: NormalizedDeck = last_result.get("deck")
	if deck == null:
		return
	var rows: Dictionary = last_result.get("rows", {})
	var store := DeckStore.new()
	store.save(deck, rows, last_result.get("validation", {}), replace_path)
	visible = false
	deck_saved.emit(deck, rows)
	if auto_play:
		play_imported.emit(deck, rows)


func _show_result(result: Dictionary) -> void:
	var lines := PackedStringArray(result.get("progress", PackedStringArray()))
	progress_label.text = "\n".join(lines)
	retry_btn.visible = true
	if not bool(result.get("ok", false)):
		preview_label.text = str(result.get("error", "Import failed."))
		confirm_btn.visible = false
		update_btn.visible = false
		save_new_btn.visible = false
		ignore_btn.visible = false
		return
	var deck: NormalizedDeck = result.get("deck")
	var val: Dictionary = result.get("validation", {})
	var unresolved: PackedStringArray = result.get("unresolved", PackedStringArray())
	var body := PackedStringArray()
	body.append("Deck Name: %s" % deck.name)
	body.append("Source: %s" % deck.source)
	body.append("Commander: %s" % ", ".join(deck.commander_names()))
	body.append("Total Cards: %d/100" % int(val.get("total", deck.total_cards())))
	body.append("Commander: %s" % ("VALID" if bool(val.get("commander_ok", false)) else "INVALID"))
	body.append("Singleton: %s" % ("VALID" if bool(val.get("singleton_ok", true)) else "INVALID"))
	body.append("Color Identity: %s" % ("VALID" if bool(val.get("identity_ok", true)) else "INVALID"))
	body.append("Unresolved Cards: %d" % unresolved.size())
	var errs: PackedStringArray = val.get("errors", PackedStringArray())
	if not errs.is_empty():
		body.append("")
		body.append("ERRORS:")
		for e in errs:
			body.append("- %s" % e)
	preview_label.text = "\n".join(body)
	if unresolved.size() > 0:
		unresolved_label.text = "UNRESOLVED CARDS\n- " + "\n- ".join(unresolved)
		ignore_btn.visible = true
	else:
		unresolved_label.text = ""
		ignore_btn.visible = false
	_paint_preview(deck, result.get("rows", {}))
	var existing := DeckStore.new().find_by_source_url(deck.source_url)
	existing_path = str(existing.get("_path", ""))
	var can_confirm := deck.total_cards() > 0
	confirm_btn.visible = can_confirm and existing_path == ""
	update_btn.visible = can_confirm and existing_path != ""
	save_new_btn.visible = can_confirm and existing_path != ""
	if existing_path != "":
		confirm_btn.visible = false


func _paint_preview(deck: NormalizedDeck, rows: Dictionary) -> void:
	_clear_preview()
	var cat := get_node_or_null("/root/ScryfallCatalog")
	var shown := 0
	for e in deck.commanders:
		preview_row.add_child(_mini_card(str(e.get("name", "")), rows, cat, true))
		shown += 1
	for e2 in deck.mainboard:
		if shown >= 8:
			break
		preview_row.add_child(_mini_card(str(e2.get("name", "")), rows, cat, false))
		shown += 1


func _mini_card(n: String, rows: Dictionary, cat: Object, commander: bool) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(72, 100)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.1, 0.08)
	st.set_corner_radius_all(6)
	st.set_border_width_all(2)
	st.border_color = GOLD if commander else Color(0, 0, 0, 0.5)
	wrap.add_theme_stylebox_override("panel", st)
	var row: Dictionary = rows.get(n, {})
	var tex: Texture2D = null
	if cat != null and cat.has_method("texture_for") and not row.is_empty():
		tex = cat.texture_for(row, "small")
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(72, 100)
		wrap.add_child(tr)
	else:
		var lab := Label.new()
		lab.text = "LOADING CARD...\n%s" % n if not row.is_empty() else "Missing\n%s" % n
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_font_size_override("font_size", 9)
		wrap.add_child(lab)
	return wrap


func _clear_preview() -> void:
	if preview_row == null:
		return
	while preview_row.get_child_count() > 0:
		var c := preview_row.get_child(0)
		preview_row.remove_child(c)
		c.queue_free()
