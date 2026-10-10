class_name OverridePanel
extends PanelContainer

## The Override menu: a small panel under the top bar with the table-fixing actions (mana, life, draw, kill, revive, tokens,
## +1/+1 ...). It only builds the action dictionaries (see TableOverrides); the table decides whether they happen at once or
## need the other player to agree. An action that needs a number asks for it right after you pick it (1, 5, 10 ...).
##
##   act(op)                    do this now (player actions, tokens)
##   arm(op, hint)              pick this action, then click cards on the table to apply it to each (stays armed until stopped)
##   pick_card(zone, to, hint)  choose a card from your graveyard / hand / library / exile to move to `to`
##   closed                     the panel was dismissed

signal act(op: Dictionary)
signal arm(op: Dictionary, hint: String)
signal pick_card(zone: String, to: String, hint: String)
signal closed

const GOLD := Color(0.96, 0.82, 0.35)
const INK := Color(0.93, 0.91, 0.86)
const MUTED := Color(0.66, 0.66, 0.62)
const COUNTER_NAMES := ["loyalty", "charge", "time", "stun", "shield", "level"]
const AMOUNTS := [1, 2, 3, 4, 5, 10, 20]
const MANA_BUTTONS := [["W", Color(0.93, 0.90, 0.74), Color(0.12, 0.10, 0.04)], ["U", Color(0.25, 0.50, 0.85), Color(1, 1, 1)],
	["B", Color(0.22, 0.17, 0.26), Color(0.92, 0.88, 0.95)], ["R", Color(0.80, 0.25, 0.18), Color(1, 1, 1)],
	["G", Color(0.22, 0.55, 0.28), Color(1, 1, 1)], ["C", Color(0.62, 0.62, 0.60), Color(0.08, 0.08, 0.08)]]

var _who := "me"
var _who_buttons: Array = []
var _counter_pick: OptionButton
var _token_p: SpinBox
var _token_t: SpinBox
var _can_tutor := true
var _body: VBoxContainer
var _picker: VBoxContainer


## `rival_name` labels the second target button; `online` says an action needs the other player's agreement.
func setup(rival_name: String, online: bool, can_tutor: bool) -> void:
	_can_tutor = can_tutor
	_who = "me"
	_who_buttons.clear()
	for ch in get_children():
		ch.queue_free()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.035, 0.065, 0.06, 0.98)
	st.border_color = GOLD.darkened(0.15)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(560, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	add_child(col)

	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Override"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = "Close (Esc)"
	x.pressed.connect(func() -> void: closed.emit())
	head.add_child(x)
	col.add_child(head)
	var rule := Label.new()
	rule.text = "The other player must agree to each change." if online else "Applies at once (it's your table)."
	rule.add_theme_font_size_override("font_size", 12)
	rule.add_theme_color_override("font_color", MUTED)
	col.add_child(rule)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	col.add_child(_body)
	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 10)
	_picker.visible = false
	col.add_child(_picker)

	## Who the player actions are for.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.add_child(_label("For"))
	## "Talrand, Sky Summoner" is too long for a button: the name before the comma.
	var short_rival := rival_name.split(",")[0].strip_edges()
	if short_rival.length() > 14:
		short_rival = short_rival.substr(0, 13) + "…"
	for w in [["me", "You"], ["rival", short_rival]]:
		var b := _toggle(str(w[1]), func() -> void: _set_who(str(w[0])))
		_who_buttons.append([str(w[0]), b])
		top.add_child(b)
	_body.add_child(top)
	_set_who("me")

	_body.add_child(_section("Add mana"))
	var mana := HBoxContainer.new()
	mana.add_theme_constant_override("separation", 6)
	for mb in MANA_BUTTONS:
		var color_letter := str(mb[0])
		var b := Button.new()
		b.text = "◇" if color_letter == "C" else color_letter
		b.custom_minimum_size = Vector2(52, 30)
		b.tooltip_text = "Add %s mana" % TableOverrides.COLOR_NAMES[color_letter]
		_paint(b, mb[1], mb[2])
		b.pressed.connect(func() -> void:
			_ask_amount("Add how much %s mana?" % TableOverrides.COLOR_NAMES[color_letter],
				func(n: int) -> void: act.emit({"op": "mana", "who": _who, "color": color_letter, "n": n})))
		mana.add_child(b)
	_body.add_child(mana)

	_body.add_child(_section("Player"))
	_body.add_child(_row([
		_amount_btn("Gain life", "Gain life", "Gain how much life?", func(n: int) -> Dictionary: return {"op": "life", "who": _who, "delta": n}),
		_amount_btn("Lose life", "Lose life", "Lose how much life?", func(n: int) -> Dictionary: return {"op": "life", "who": _who, "delta": -n}),
		_amount_btn("Commander damage", "Commander damage taken (21 from one commander loses)", "How much commander damage?", func(n: int) -> Dictionary: return {"op": "cmdr_damage", "who": _who, "delta": n}),
		_amount_btn("Heal commander dmg", "Remove commander damage", "Remove how much commander damage?", func(n: int) -> Dictionary: return {"op": "cmdr_damage", "who": _who, "delta": -n}),
		_amount_btn("Add poison", "Poison counters (10 loses)", "How many poison counters?", func(n: int) -> Dictionary: return {"op": "poison", "who": _who, "delta": n}),
		_amount_btn("Remove poison", "Remove poison counters", "Remove how many poison counters?", func(n: int) -> Dictionary: return {"op": "poison", "who": _who, "delta": -n}),
	]))
	_body.add_child(_row([
		_amount_btn("Draw", "Draw cards", "Draw how many cards?", func(n: int) -> Dictionary: return {"op": "draw", "who": _who, "n": n}),
		_amount_btn("Discard", "Discard cards at random", "Discard how many cards (random)?", func(n: int) -> Dictionary: return {"op": "discard", "who": _who, "n": n}),
		_amount_btn("Mill", "Put the top cards of the library into the graveyard", "Mill how many cards?", func(n: int) -> Dictionary: return {"op": "mill", "who": _who, "n": n}),
		_btn("Shuffle", "Shuffle the library", func() -> void: act.emit({"op": "shuffle", "who": _who})),
		_btn("Untap all", "Untap every permanent", func() -> void: act.emit({"op": "untap_all", "who": _who})),
		_btn("Extra turn", "Take an extra turn after this one", func() -> void: act.emit({"op": "extra_turn", "who": _who})),
	]))

	_body.add_child(_section("Cards — pick one, then click cards on the table"))
	_body.add_child(_row([
		_btn("Kill", "Send to the graveyard (ignores indestructible)", func() -> void: _arm({"op": "move", "to": "GRAVEYARD"}, "Kill")),
		_btn("Exile", "Exile it", func() -> void: _arm({"op": "move", "to": "EXILE"}, "Exile")),
		_btn("To hand", "Return it to its owner's hand", func() -> void: _arm({"op": "move", "to": "HAND"}, "Return to hand")),
		_btn("Tap", "Tap it", func() -> void: _arm({"op": "tap"}, "Tap")),
		_btn("Untap", "Untap it", func() -> void: _arm({"op": "untap"}, "Untap")),
		_btn("Take control", "Gain control of it", func() -> void: _arm({"op": "control"}, "Take control of")),
		_btn("Copy", "Make a token copy of it", func() -> void: _arm({"op": "copy"}, "Copy")),
	]))
	_body.add_child(_row([
		_card_amount_btn("+1/+1 counters", "Put +1/+1 counters on creatures", "How many +1/+1 counters?", func(n: int) -> Array: return [{"op": "pt", "delta": n}, "+%d/+%d on" % [n, n]]),
		_card_amount_btn("−1/−1 counters", "Put -1/-1 counters on creatures", "How many −1/−1 counters?", func(n: int) -> Array: return [{"op": "pt", "delta": -n}, "-%d/-%d on" % [n, n]]),
		_counter_dropdown(),
		_card_amount_btn("Add counters", "Add counters of the kind on the left", "How many counters?", func(n: int) -> Array: return [{"op": "counters", "name": _counter_name(), "delta": n}, "+%d %s on" % [n, _counter_name()]]),
		_card_amount_btn("Remove counters", "Remove counters of the kind on the left", "Remove how many counters?", func(n: int) -> Array: return [{"op": "counters", "name": _counter_name(), "delta": -n}, "-%d %s on" % [n, _counter_name()]]),
	]))

	_body.add_child(_section("From a pile — choose the card"))
	var tutor := _btn("Tutor", "Search your library and put a card in hand", func() -> void: pick_card.emit("LIBRARY", "HAND", "Search your library"))
	tutor.disabled = not _can_tutor
	if not _can_tutor:
		tutor.tooltip_text = "Only the host sees the library."
	_body.add_child(_row([
		_btn("Revive", "Put a card from your graveyard onto the battlefield", func() -> void: pick_card.emit("GRAVEYARD", "BATTLEFIELD", "Revive from your graveyard")),
		_btn("Graveyard → hand", "Return a card from your graveyard to hand", func() -> void: pick_card.emit("GRAVEYARD", "HAND", "Return from your graveyard")),
		_btn("Play from hand", "Put a card from your hand onto the battlefield, free", func() -> void: pick_card.emit("HAND", "BATTLEFIELD", "Put onto the battlefield")),
		_btn("Return exiled", "Put an exiled card onto the battlefield", func() -> void: pick_card.emit("EXILE", "BATTLEFIELD", "Return from exile")),
		tutor,
	]))

	_body.add_child(_section("Tokens"))
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 6)
	presets.add_theme_constant_override("v_separation", 6)
	for key in TableOverrides.TOKEN_PRESETS.keys():
		var label := str((TableOverrides.TOKEN_PRESETS[key] as Dictionary).label)
		var tb := _btn(label, "Create %s" % label, func() -> void: act.emit({"op": "token", "who": _who, "preset": str(key), "label": label}))
		presets.add_child(tb)
	_body.add_child(presets)
	var custom := HBoxContainer.new()
	custom.add_theme_constant_override("separation", 6)
	custom.add_child(_label("Custom"))
	_token_p = _spin(1)
	_token_t = _spin(1)
	custom.add_child(_token_p)
	custom.add_child(_label("/"))
	custom.add_child(_token_t)
	custom.add_child(_btn("Create", "A token with that power and toughness", func() -> void:
		act.emit({"op": "token", "who": _who, "p": int(_token_p.value), "t": int(_token_t.value), "name": "%d/%d token" % [int(_token_p.value), int(_token_t.value)],
			"label": "%d/%d" % [int(_token_p.value), int(_token_t.value)], "subtypes": ["Token"]})))
	_body.add_child(custom)


## An action that needs a number: shows the number pad, then emits the action `make_op(n)` builds.
func _amount_btn(text: String, tip: String, question: String, make_op: Callable) -> Button:
	return _btn(text, tip, func() -> void:
		_ask_amount(question, func(n: int) -> void: act.emit(make_op.call(n))))


## Same, for an action that is then aimed at cards: `make` returns [op, hint].
func _card_amount_btn(text: String, tip: String, question: String, make: Callable) -> Button:
	return _btn(text, tip, func() -> void:
		_ask_amount(question, func(n: int) -> void:
			var made: Array = make.call(n)
			_arm(made[0] as Dictionary, str(made[1]))))


## Swaps the panel for a number pad: 1 2 3 4 5 10 20, or type one. Picking one runs `on_pick(n)`; Back returns to the menu.
func _ask_amount(question: String, on_pick: Callable) -> void:
	for ch in _picker.get_children():
		_picker.remove_child(ch)  ## gone at once, so an old number pad can't be pressed by mistake
		ch.queue_free()
	var q := Label.new()
	q.text = question
	q.add_theme_font_size_override("font_size", 18)
	q.add_theme_color_override("font_color", GOLD)
	_picker.add_child(q)
	var who := Label.new()
	who.text = "For %s" % str((_who_buttons[0 if _who == "me" else 1][1] as Button).text)
	who.add_theme_color_override("font_color", MUTED)
	_picker.add_child(who)
	var pad := HFlowContainer.new()
	pad.add_theme_constant_override("h_separation", 8)
	pad.add_theme_constant_override("v_separation", 8)
	for a in AMOUNTS:
		var b := Button.new()
		b.text = str(a)
		b.custom_minimum_size = Vector2(58, 44)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void: _finish_amount(on_pick, int(a)))
		pad.add_child(b)
	_picker.add_child(pad)
	var custom := HBoxContainer.new()
	custom.add_theme_constant_override("separation", 8)
	custom.add_child(_label("Other"))
	var spin := _spin(6)
	spin.min_value = 1
	spin.max_value = 100
	custom.add_child(spin)
	custom.add_child(_btn("OK", "Use that number", func() -> void: _finish_amount(on_pick, int(spin.value))))
	_picker.add_child(custom)
	_picker.add_child(_btn("Back", "Back to the menu", _back))
	_body.visible = false
	_picker.visible = true


func _finish_amount(on_pick: Callable, n: int) -> void:
	_back()
	on_pick.call(n)


func _back() -> void:
	_picker.visible = false
	_body.visible = true


func _arm(op: Dictionary, hint: String) -> void:
	arm.emit(op, hint)


func _set_who(who: String) -> void:
	_who = who
	for e in _who_buttons:
		(e[1] as Button).set_pressed_no_signal(str(e[0]) == who)


func _counter_name() -> String:
	return COUNTER_NAMES[_counter_pick.selected] if _counter_pick != null and _counter_pick.selected >= 0 else "charge"


func _counter_dropdown() -> Control:
	_counter_pick = OptionButton.new()
	for c in COUNTER_NAMES:
		_counter_pick.add_item(str(c))
	_counter_pick.custom_minimum_size = Vector2(86, 28)
	_counter_pick.tooltip_text = "Which counter the Add / Remove counters buttons use"
	return _counter_pick


func _spin(v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 99
	s.value = v
	s.custom_minimum_size = Vector2(70, 28)
	return s


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", MUTED)
	return l


func _section(text: String) -> Control:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", GOLD.darkened(0.2))
	return l


func _row(buttons: Array) -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	for b in buttons:
		h.add_child(b as Control)
	return h


func _btn(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 28)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(on_press)
	return b


func _toggle(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(64, 28)
	b.pressed.connect(on_press)
	return b


func _paint(b: Button, bg: Color, fg: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = bg.lightened(0.2)
	h.border_color = GOLD
	h.set_border_width_all(2)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_font_size_override("font_size", 15)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _picker != null and _picker.visible:
			_back()
		else:
			closed.emit()
		get_viewport().set_input_as_handled()
