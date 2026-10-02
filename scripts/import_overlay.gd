class_name ImportOverlay
extends ColorRect

signal cancelled
signal play_imported(deck: NormalizedDeck, rows: Dictionary)
signal deck_saved(deck: NormalizedDeck, rows: Dictionary)

const GOLD := Color(0.93, 0.78, 0.28)

@onready var input_box: TextEdit = %InputBox
@onready var progress_label: Label = %ProgressLabel
@onready var preview_label: Label = %PreviewLabel
@onready var source_link: LinkButton = %SourceLink
@onready var unresolved_label: Label = %UnresolvedLabel
@onready var import_btn: Button = %ImportBtn
@onready var confirm_btn: Button = %ConfirmBtn
@onready var update_btn: Button = %UpdateBtn
@onready var save_new_btn: Button = %SaveNewBtn
@onready var retry_btn: Button = %RetryBtn
@onready var ignore_btn: Button = %IgnoreBtn
@onready var preview_row: HBoxContainer = %PreviewRow

var last_result: Dictionary = {}
var existing_path: String = ""
var busy := false
var auto_play := true
var _source_url := ""


func open() -> void:
	visible = true
	last_result = {}
	existing_path = ""
	progress_label.text = ""
	preview_label.text = ""
	unresolved_label.text = ""
	if source_link:
		source_link.visible = false
		source_link.uri = ""
		source_link.tooltip_text = ""
		_source_url = ""
	confirm_btn.visible = false
	update_btn.visible = false
	save_new_btn.visible = false
	retry_btn.visible = false
	ignore_btn.visible = false
	_clear_preview()


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
		if source_link:
			source_link.visible = false
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
	_show_source_link(deck)
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


func _show_source_link(deck: NormalizedDeck) -> void:
	if source_link == null:
		return
	var url := str(deck.source_url).strip_edges()
	if not DeckSource.is_http_url(url):
		source_link.visible = false
		source_link.uri = ""
		_source_url = ""
		return
	_source_url = url
	source_link.text = DeckSource.view_on_label(deck.source)
	source_link.uri = ""
	source_link.tooltip_text = url
	source_link.visible = true


func _on_source_link_pressed() -> void:
	var url := _source_url.strip_edges()
	if url == "" and last_result.has("deck") and last_result.get("deck") is NormalizedDeck:
		url = str((last_result.get("deck") as NormalizedDeck).source_url).strip_edges()
	if DeckSource.is_http_url(url):
		OS.shell_open(url)


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
