class_name GameHistory
extends RefCounted

## Plain-language play-by-play built from the engine's GameLog: who cast what, what entered or died,
## attacks, blocks, damage and life. The table shows it in the History panel.
##
## Object ids change on every zone move (CR 400.7), so names are remembered each time the log is
## read, and a new object also answers to the id it came from.

const CAP := 600

## Each line: {t: String, k: String, cards: Array} where k is "turn", "step", "you", "rival" or "info".
## `cards` holds a dictionary for every card the line names, so the table can show it on hover.
var lines: Array = []

var _cursor: int = 0
var _started: bool = false
var _names: Dictionary = {}
## id -> what the table needs to draw the card on hover: name, type, text, cost, power/toughness, card id.
var _info: Dictionary = {}
## Cards named in the line being built; _add() attaches them to it as `cards`.
var _cur: Array = []
var _creature: Dictionary = {}


func clear() -> void:
	lines.clear()
	_cursor = 0
	_started = false
	_names.clear()
	_info.clear()
	_cur.clear()
	_creature.clear()


## Reads any events added since the last call. While `enabled` is false (mulligans) it only skips ahead.
func pump(engine: RulesEngine, you_seat: int, enabled: bool) -> void:
	if engine == null or engine.state == null or engine.state.log == null:
		return
	_remember(engine)
	var glog: GameLog = engine.state.log
	if not enabled:
		_cursor = glog.seq()
		return
	if not _started:
		_started = true
		_cursor = glog.seq()
		_add("Game start", "info")
		return
	for e in glog.since(_cursor):
		_event(engine, e as GameEvent, you_seat)
	_cursor = glog.seq()
	while lines.size() > CAP:
		lines.remove_at(0)


func add_note(text: String, kind: String = "info") -> void:
	_add(text, kind)


func _add(text: String, kind: String) -> void:
	var shown: Array = []
	for c in _cur:
		var cd: Dictionary = c
		var dup := false
		for o in shown:
			if str((o as Dictionary).get("name", "")) == str(cd.get("name", "")):
				dup = true
		if not dup and text.contains(str(cd.get("name", ""))):
			shown.append(cd)
	_cur = []
	lines.append({t = text, k = kind, cards = shown})


func _remember(engine: RulesEngine) -> void:
	for oid in engine.state.objects.keys():
		var obj: GameObject = engine.state.objects[oid]
		if obj == null or not (obj.definition is CardDefinition):
			continue
		var def := obj.definition as CardDefinition
		_names[int(oid)] = def.name
		_creature[int(oid)] = def.is_creature()
		var brief := {
			name = def.name, type = def.type_line, text = def.oracle_text, mana_cost = def.mana_cost,
			cmc = def.cmc, cardId = def.oracle_id, kind = "land" if (def.is_land() and not def.is_creature()) else "spell",
			power = str(def.power) if def.is_creature() else "", toughness = str(def.toughness) if def.is_creature() else "",
			is_token = obj.is_token, zone = "history", scryfall_id = "", imageUrl = "", images = {},
		}
		_info[int(oid)] = brief
		if obj.linked_from != 0:
			_names[int(obj.linked_from)] = def.name
			_creature[int(obj.linked_from)] = def.is_creature()
			_info[int(obj.linked_from)] = brief


func _name(oid: int) -> String:
	if _info.has(oid):
		_cur.append(_info[oid])
	return str(_names.get(oid, "a card"))


func _who(pid: int, you_seat: int) -> String:
	return "You" if pid == you_seat else "Talrand"


func _kind(pid: int, you_seat: int) -> String:
	return "you" if pid == you_seat else "rival"


func _event(engine: RulesEngine, e: GameEvent, you_seat: int) -> void:
	_cur = []
	var p: Dictionary = e.payload
	var who := _who(e.player_id, you_seat)
	var kind := _kind(e.player_id, you_seat)
	match e.type:
		EngineEnums.EventType.STEP_BEGIN:
			_step(p, you_seat, e.player_id)
		EngineEnums.EventType.DRAW:
			if e.player_id == you_seat:
				_add("You draw %s." % _name(int(p.get("to_id", 0))), "you")
			else:
				_add("Talrand draws a card.", "rival")
		EngineEnums.EventType.SPELL_CAST:
			_add(("You cast %s." if e.player_id == you_seat else "Talrand casts %s.") % _name(int(p.get("object_id", 0))), kind)
		EngineEnums.EventType.ABILITY_ACTIVATED:
			## Tapping a land for mana is also logged; only stack abilities are worth showing.
			if bool(p.get("trigger", false)):
				_add("%s triggers." % _name(int(p.get("object_id", 0))), kind)
			elif p.has("stack_id"):
				_add("%s activate %s." % [who, _name(int(p.get("object_id", 0)))] if e.player_id == you_seat else "Talrand activates %s." % _name(int(p.get("object_id", 0))), kind)
		EngineEnums.EventType.ZONE_CHANGE:
			_zone_change(p, e.player_id, you_seat)
		EngineEnums.EventType.ATTACK:
			var names: Array = []
			for aid in p.get("attackers", []):
				names.append(_name(int(aid)))
			var target := _who(int(p.get("to_player", 0)), you_seat)
			var attacker := _who(e.player_id, you_seat)
			_add("%s attack%s %s with %s." % [attacker, "" if e.player_id == you_seat else "s", target, ", ".join(names)], kind)
		EngineEnums.EventType.BLOCK:
			if int(p.get("blocker_id", 0)) == 0:
				_add("%s %s no blockers." % [who, "declare" if e.player_id == you_seat else "declares"], kind)
			else:
				_add("%s blocks %s." % [_name(int(p.get("blocker_id", 0))), _name(int(p.get("attacker_id", 0)))], kind)
		EngineEnums.EventType.DAMAGE:
			_damage(p, you_seat)
		EngineEnums.EventType.LIFE_CHANGE:
			var pid := int(p.get("to_player", e.player_id))
			var amt := int(p.get("amount", 0))
			if bool(p.get("gain", false)):
				_add("%s gain%s %d life." % [_who(pid, you_seat), "" if pid == you_seat else "s", amt], _kind(pid, you_seat))
			else:
				_add("%s lose%s %d life." % [_who(pid, you_seat), "" if pid == you_seat else "s", amt], _kind(pid, you_seat))
		EngineEnums.EventType.GAME_OVER:
			_add("Game over.", "info")
		EngineEnums.EventType.NOTE:
			_add(str(e.payload.get("text", "")), "info")


func _step(p: Dictionary, you_seat: int, active: int) -> void:
	match int(p.get("step", -1)):
		EngineEnums.Step.UNTAP:
			var turn := int(p.get("turn", 0))
			if turn > 0:
				_add("Turn %d — %s" % [turn, "your turn" if active == you_seat else "Talrand's turn"], "turn")
		EngineEnums.Step.UPKEEP:
			_add("Upkeep", "step")
		EngineEnums.Step.DRAW:
			_add("Draw", "step")
		EngineEnums.Step.PRECOMBAT_MAIN:
			_add("Main phase 1", "step")
		EngineEnums.Step.BEGIN_COMBAT:
			_add("Combat", "step")
		EngineEnums.Step.POSTCOMBAT_MAIN:
			_add("Main phase 2", "step")
		EngineEnums.Step.END:
			_add("End step", "step")


func _zone_change(p: Dictionary, pid: int, you_seat: int) -> void:
	var from_z := int(p.get("from_zone", -1))
	var to_z := int(p.get("to_zone", -1))
	var to_id := int(p.get("to_id", 0))
	var from_id := int(p.get("from_id", 0))
	var nm := _name(to_id if to_id != 0 else from_id)
	var was_creature := bool(_creature.get(to_id, _creature.get(from_id, false)))
	var kind := _kind(pid, you_seat)
	if to_z == EngineEnums.ZoneId.BATTLEFIELD:
		## "X casts Y" already says Y is coming; saying it enters again is the same event twice.
		if from_z == EngineEnums.ZoneId.STACK:
			return
		if from_z == EngineEnums.ZoneId.HAND:
			_add("%s play %s." % [_who(pid, you_seat), nm] if pid == you_seat else "Talrand plays %s." % nm, kind)
		else:
			_add("%s enters the battlefield." % nm, kind)
	elif from_z == EngineEnums.ZoneId.BATTLEFIELD:
		match to_z:
			EngineEnums.ZoneId.GRAVEYARD:
				_add("%s %s." % [nm, "dies" if was_creature else "is destroyed"], kind)
			EngineEnums.ZoneId.EXILE:
				_add("%s is exiled." % nm, kind)
			EngineEnums.ZoneId.HAND:
				_add("%s returns to hand." % nm, kind)
			EngineEnums.ZoneId.COMMAND:
				_add("%s returns to the command zone." % nm, kind)
	elif from_z == EngineEnums.ZoneId.HAND and to_z == EngineEnums.ZoneId.GRAVEYARD:
		_add("%s is discarded." % nm, kind)
	elif from_z == EngineEnums.ZoneId.LIBRARY and to_z == EngineEnums.ZoneId.GRAVEYARD:
		_add("%s is milled." % nm, kind)


func _damage(p: Dictionary, you_seat: int) -> void:
	var amt := int(p.get("amount", 0))
	if amt <= 0:
		return
	var src := ""
	if p.has("object_id"):
		src = _name(int(p.get("object_id", 0)))
	var tag := " (combat)" if bool(p.get("combat", false)) else ""
	var target := ""
	var kind := "info"
	if p.has("to_player"):
		var pid := int(p.get("to_player", 0))
		target = _who(pid, you_seat) if pid != you_seat else "you"
		kind = _kind(pid, you_seat)
	elif p.has("to_object"):
		target = _name(int(p.get("to_object", 0)))
	if src != "":
		_add("%s deals %d damage to %s%s." % [src, amt, target, tag], kind)
	else:
		_add("%d damage to %s%s." % [amt, target, tag], kind)
