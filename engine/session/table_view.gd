class_name TableView
extends RefCounted

const PHASE_NAMES := ["Untap", "Upkeep", "Draw", "Main", "Combat", "Main 2", "End"]
const YOU_EMBER := Color(0.42, 0.18, 0.08)
const RIVAL_TEAL := Color(0.18, 0.42, 0.48)

var you: Dictionary = {}
var rival: Dictionary = {}
var turn: int = 1
var active_is_you: bool = true
var phase_name_str: String = "Main"
var selected_id: String = ""
var difficulty: int = 1
var you_drew_this_turn: bool = true
var stack: Array = []
var your_priority: bool = true
var can_attack: bool = false
var attacker_count: int = 0
var step_name: String = "Main"
var game_over: bool = false
var winners: Array = []
var prompt: String = ""
var match_start: int = 0


func header_text() -> String:
	var extra := ""
	if game_over:
		extra = " · GAME OVER"
	elif not stack.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for card in stack:
			names.append(str(card.get("name", "spell")))
		extra = " · Stack: %s" % ", ".join(names)
	return "Turn %d — %s · %s%s" % [turn, active_name(), phase_name_str, extra]


func phase_name() -> String:
	return phase_name_str


func active_name() -> String:
	return str(you.get("name", "You") if active_is_you else rival.get("name", "Rival"))


func find_card(card_id: String) -> Dictionary:
	for pile in [you.get("hand", []), you.get("lands", []), you.get("creatures", []), you.get("noncreatures", []), you.get("command", []), rival.get("hand", []), rival.get("lands", []), rival.get("creatures", []), rival.get("noncreatures", []), rival.get("command", []), stack]:
		for card in pile:
			if str(card.get("id", "")) == card_id:
				return card
	return {}


func card_in_hand(card_id: String) -> Dictionary:
	for held in you.get("hand", []):
		if str(held.get("id", "")) == card_id:
			return held
	return {}


static func from_engine(engine: RulesEngine, session: GameSession) -> TableView:
	var v := TableView.new()
	if engine == null or engine.state == null:
		return v
	var st := engine.state
	v.turn = st.turn_number
	v.active_is_you = st.active_player_id == 0
	v.phase_name_str = _phase_label(st.phase)
	v.step_name = _step_label(st.step)
	v.game_over = engine.is_over()
	v.winners = st.winners.duplicate() if st.winners != null else []
	var seat := 0
	if session != null:
		seat = int(session.you_seat)
	v.your_priority = int(st.awaiting.get("player_id", -1)) == seat
	v.attacker_count = engine.legal_attacker_ids(seat).size()
	v.can_attack = v.attacker_count > 0 and st.active_player_id == seat and (
		st.step == EngineEnums.Step.DECLARE_ATTACKERS or st.phase == EngineEnums.Phase.MAIN_1
	)
	if session != null:
		v.selected_id = session.selected_id
		v.difficulty = session.difficulty
		v.you_drew_this_turn = not session.pending_draw_anim
		v.prompt = session.prompt_text()
		v.match_start = session.match_start
	var cat := _catalog()
	var other := 1 if seat == 0 else 0
	v.you = _player_dict(engine, seat, cat)
	v.rival = _player_dict(engine, other, cat)
	v.stack = _stack_cards(engine, cat)
	return v


func to_plain() -> Dictionary:
	return {
		you = you,
		rival = rival,
		turn = turn,
		active_is_you = active_is_you,
		phase_name_str = phase_name_str,
		selected_id = selected_id,
		difficulty = difficulty,
		you_drew_this_turn = you_drew_this_turn,
		stack = stack,
		your_priority = your_priority,
		can_attack = can_attack,
		attacker_count = attacker_count,
		step_name = step_name,
		game_over = game_over,
		winners = winners,
		prompt = prompt,
		match_start = match_start,
	}


## Same shape as to_plain(), but with `you`'s hand replaced by
## face-down placeholders. Use this (never to_plain()) for anything
## that crosses the network: `you` is *our own* hand from the host's
## perspective, which becomes the *opponent's* hand once the remote
## client swaps you/rival on receipt (see GameNet.receive_view). The
## remote client must never receive real card data for a hand that
## isn't theirs, even if the UI only ever renders it as a count.
func to_plain_for_remote() -> Dictionary:
	var d := to_plain()
	d.you = _redacted_player(you)
	return d


static func _redacted_player(p: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	out.hand = _redacted_hand(p.get("hand", []))
	return out


static func _redacted_hand(hand: Array) -> Array:
	var out: Array = []
	for i in hand.size():
		out.append({hidden = true, id = "hidden_%d" % i})
	return out


static func from_plain(d: Dictionary) -> TableView:
	var v := TableView.new()
	v.you = d.get("you", {})
	v.rival = d.get("rival", {})
	v.turn = int(d.get("turn", 1))
	v.active_is_you = bool(d.get("active_is_you", true))
	v.phase_name_str = str(d.get("phase_name_str", "Main"))
	v.selected_id = str(d.get("selected_id", ""))
	v.difficulty = int(d.get("difficulty", 1))
	v.you_drew_this_turn = bool(d.get("you_drew_this_turn", true))
	v.stack = d.get("stack", [])
	v.your_priority = bool(d.get("your_priority", true))
	v.can_attack = bool(d.get("can_attack", false))
	v.attacker_count = int(d.get("attacker_count", 0))
	v.step_name = str(d.get("step_name", "Main"))
	v.game_over = bool(d.get("game_over", false))
	v.winners = d.get("winners", [])
	v.prompt = str(d.get("prompt", ""))
	v.match_start = int(d.get("match_start", 0))
	return v


static func _player_dict(engine: RulesEngine, player_id: int, cat: Object) -> Dictionary:
	var p: PlayerState = engine.state.players[player_id] if player_id < engine.state.players.size() else PlayerState.new()
	var creatures: Array = []
	var noncreatures: Array = []
	var lands: Array = []
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	if bf != null:
		for oid in bf.object_ids:
			var obj: GameObject = engine.state.objects.get(oid)
			if obj == null or obj.controller_id != player_id:
				continue
			var d := _card_dict(engine, obj, cat)
			var kind := str(d.get("kind", "spell"))
			if kind == "land":
				lands.append(d)
			elif obj.definition is CardDefinition and (obj.definition as CardDefinition).is_creature():
				creatures.append(d)
			else:
				noncreatures.append(d)
	return {
		name = p.name,
		subtitle = "",
		life = p.life,
		library = engine.library_size(player_id),
		graveyard = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, player_id).size(),
		exile = engine.state.zones.get_zone(EngineEnums.ZoneId.EXILE, player_id).size(),
		command = _zone_cards(engine, EngineEnums.ZoneId.COMMAND, player_id, cat),
		creatures = creatures,
		noncreatures = noncreatures,
		lands = lands,
		hand = _zone_cards(engine, EngineEnums.ZoneId.HAND, player_id, cat),
		untapped_lands = _untapped_lands(lands),
		mana = (p.mana as ManaPool).total() if p.mana is ManaPool else 0,
	}


static func _zone_cards(engine: RulesEngine, zone_id: int, player_id: int, cat: Object) -> Array:
	var out: Array = []
	var z: Zone = engine.state.zones.get_zone(zone_id, player_id)
	if z == null:
		return out
	for oid in z.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		if obj != null:
			out.append(_card_dict(engine, obj, cat))
	return out


static func _card_dict(engine: RulesEngine, obj: GameObject, cat: Object) -> Dictionary:
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	var type_line := def.type_line if def else ""
	var is_land := def != null and def.is_land() and not def.is_creature()
	var snap: Dictionary = engine.layers.snapshot(engine.state, obj) if engine.layers != null else {}
	var d := {
		id = str(obj.object_id),
		instanceId = obj.instance_uuid if obj.instance_uuid != "" else str(obj.object_id),
		cardId = def.oracle_id if def else "",
		linked_from = str(obj.linked_from) if obj.linked_from != 0 else "",
		name = def.name if def else "",
		type = type_line,
		text = def.oracle_text if def else "",
		mana_cost = def.mana_cost if def else "",
		color = _color(def),
		kind = "land" if is_land else "spell",
		cmc = def.cmc if def else 0,
		tapped = obj.tapped,
		sick = obj.summoned_this_turn,
		zone = _zone_key(obj.zone),
		power = str(snap.get("power", "")) if def != null and def.is_creature() else "",
		toughness = str(snap.get("toughness", "")) if def != null and def.is_creature() else "",
		scryfall_id = "",
		imageUrl = "",
		images = {},
	}
	if cat != null and cat.has_method("find_by_name"):
		var found: Variant = cat.find_by_name(str(d.name))
		if found is Dictionary and not (found as Dictionary).is_empty():
			var row: Dictionary = found
			d["scryfall_id"] = str(row.get("id", ""))
			d["cardId"] = str(row.get("oracle_id", d.cardId))
			var imgs: Variant = row.get("images", {})
			if imgs is Dictionary:
				d["images"] = imgs
				d["imageUrl"] = str((imgs as Dictionary).get("normal", (imgs as Dictionary).get("small", "")))
			if str(d.get("mana_cost", "")) == "" and row.has("mana_cost"):
				d["mana_cost"] = str(row.get("mana_cost", ""))
	return d


static func _color(def: CardDefinition) -> Color:
	if def == null:
		return Color(0, 0, 0, 0.35)
	if def.name.find("Krenko") >= 0 or def.name.find("Goblin") >= 0:
		return YOU_EMBER
	if def.name.find("Talrand") >= 0 or def.name.find("Drake") >= 0:
		return RIVAL_TEAL
	if def.color_identity.has("U"):
		return RIVAL_TEAL
	if def.color_identity.has("R"):
		return YOU_EMBER
	return Color(0, 0, 0, 0.35)


static func _stack_cards(engine: RulesEngine, cat: Object) -> Array:
	var out: Array = []
	if engine.state.stack == null or not (engine.state.stack is MagicStack):
		return out
	var stack := engine.state.stack as MagicStack
	for entry in stack.entries:
		var e := entry as StackEntry
		if e == null:
			continue
		if e.object_id != 0 and engine.state.objects.has(e.object_id):
			out.append(_card_dict(engine, engine.state.objects[e.object_id], cat))
		else:
			var src: GameObject = engine.state.objects.get(e.source_id)
			var nm := "Ability"
			if src != null and src.definition is CardDefinition:
				nm = (src.definition as CardDefinition).name
			out.append({
				id = "stack-%d" % e.stack_id,
				name = nm,
				type = "on the stack",
				text = str(e.ability_id),
				zone = "stack",
			})
	return out


static func _untapped_lands(lands: Array) -> int:
	var n := 0
	for card in lands:
		if not bool(card.get("tapped", false)):
			n += 1
	return n


static func _step_label(step: int) -> String:
	match step:
		EngineEnums.Step.UNTAP:
			return "Untap"
		EngineEnums.Step.UPKEEP:
			return "Upkeep"
		EngineEnums.Step.DRAW:
			return "Draw"
		EngineEnums.Step.PRECOMBAT_MAIN:
			return "Main"
		EngineEnums.Step.BEGIN_COMBAT:
			return "Begin Combat"
		EngineEnums.Step.DECLARE_ATTACKERS:
			return "Declare Attackers"
		EngineEnums.Step.DECLARE_BLOCKERS:
			return "Declare Blockers"
		EngineEnums.Step.COMBAT_DAMAGE:
			return "Combat Damage"
		EngineEnums.Step.END_COMBAT:
			return "End Combat"
		EngineEnums.Step.POSTCOMBAT_MAIN:
			return "Main 2"
		EngineEnums.Step.END:
			return "End"
		EngineEnums.Step.CLEANUP:
			return "Cleanup"
		_:
			return "Main"


static func _zone_key(zone_id: int) -> String:
	match zone_id:
		EngineEnums.ZoneId.LIBRARY:
			return "library"
		EngineEnums.ZoneId.HAND:
			return "hand"
		EngineEnums.ZoneId.BATTLEFIELD:
			return "battlefield"
		EngineEnums.ZoneId.GRAVEYARD:
			return "graveyard"
		EngineEnums.ZoneId.EXILE:
			return "exile"
		EngineEnums.ZoneId.STACK:
			return "stack"
		EngineEnums.ZoneId.COMMAND:
			return "command"
		_:
			return "unknown"


static func _phase_label(phase: int) -> String:
	match phase:
		EngineEnums.Phase.UNTAP:
			return "Untap"
		EngineEnums.Phase.UPKEEP:
			return "Upkeep"
		EngineEnums.Phase.DRAW:
			return "Draw"
		EngineEnums.Phase.MAIN_1:
			return "Main"
		EngineEnums.Phase.COMBAT:
			return "Combat"
		EngineEnums.Phase.MAIN_2:
			return "Main 2"
		EngineEnums.Phase.ENDING:
			return "End"
		_:
			return "Main"


static func _catalog() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ScryfallCatalog")
	return null
