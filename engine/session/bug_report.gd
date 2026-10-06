class_name BugReport
extends RefCounted

## A bug report for the match in progress: what the player says happened and what didn't, the last few turns of play-by-play and
## engine events, both boards, the stack and the lines of the cards in play that the engine does not read yet. Saved as a readable
## .txt and a .json under user://bug_reports so it can be sent along and the problem replayed in the head.

const DIR := "user://bug_reports"
const TURNS_KEPT := 3
const MAX_EVENT_LINES := 700


## The whole report as plain data. `session` may be a guest's view-only session (no engine): then only the History is included.
static func build(session: GameSession, what_happened: String, what_didnt: String, build_label: String = "") -> Dictionary:
	var report := {
		app = str(ProjectSettings.get_setting("application/config/name", "Aetherfold")),
		build = build_label,
		saved_at = Time.get_datetime_string_from_system(),
		what_happened = what_happened.strip_edges(),
		what_didnt_happen = what_didnt.strip_edges(),
		turns_kept = TURNS_KEPT,
	}
	if session == null:
		return report
	report["seed"] = session.last_seed
	report["online"] = session.skip_ai
	report["last_error"] = session.last_error
	report["history"] = history_last_turns(session.history.lines, TURNS_KEPT)
	var dbg: PackedStringArray = session.debug_lines
	var tail: Array = []
	for i in range(maxi(0, dbg.size() - 40), dbg.size()):
		tail.append(dbg[i])
	report["debug_tail"] = tail
	report["perf"] = GameSession.perf.duplicate(true)
	var engine := session.engine
	if engine == null or engine.state == null:
		return report
	var st := engine.state
	report["turn"] = st.turn_number
	report["active_player"] = st.active_player_id
	report["phase"] = _enum_name(EngineEnums.Phase, st.phase)
	report["step"] = _enum_name(EngineEnums.Step, st.step)
	report["mode"] = _enum_name(EngineEnums.EngineMode, st.mode)
	report["players"] = players_summary(engine)
	report["board"] = board(engine)
	report["stack"] = stack_summary(engine)
	report["events"] = events_last_turns(engine, TURNS_KEPT)
	report["unread_lines"] = unread_lines_in_play(session)
	return report


## The History lines (their text) from the start of the third-from-last turn to the end.
static func history_last_turns(lines: Array, turns: int) -> Array:
	var starts: Array = []
	for i in lines.size():
		if str((lines[i] as Dictionary).get("k", "")) == "turn":
			starts.append(i)
	var from := 0
	if starts.size() > turns:
		from = int(starts[starts.size() - turns])
	var out: Array = []
	for i in range(from, lines.size()):
		var row: Dictionary = lines[i]
		var prefix := ""
		match str(row.get("k", "")):
			"turn":
				prefix = "== "
			"step":
				prefix = "   . "
			"you":
				prefix = "[you] "
			"rival":
				prefix = "[rival] "
			_:
				prefix = "- "
		out.append(prefix + str(row.get("t", "")))
	return out


## Engine events from the start of the third-from-last turn: "seq TYPE player=N {payload}".
static func events_last_turns(engine: RulesEngine, turns: int) -> Array:
	var out: Array = []
	if engine == null or engine.state == null or engine.state.log == null:
		return out
	var first_turn := engine.state.turn_number - (turns - 1)
	var started := false
	for e in engine.state.log.events:
		var ev := e as GameEvent
		if ev == null:
			continue
		if not started:
			if ev.type == EngineEnums.EventType.STEP_BEGIN and int(ev.payload.get("turn", 0)) >= first_turn:
				started = true
			else:
				continue
		out.append("%d %s p%d %s" % [ev.seq, _enum_name(EngineEnums.EventType, ev.type), ev.player_id, _compact(ev.payload)])
	if out.size() > MAX_EVENT_LINES:
		out = out.slice(out.size() - MAX_EVENT_LINES)
	return out


static func players_summary(engine: RulesEngine) -> Array:
	var out: Array = []
	for p in engine.state.players:
		out.append({
			name = p.name, life = p.life, poison = p.poison, energy = p.energy,
			library = engine.library_size(p.player_id), hand = engine.hand_size(p.player_id),
			commander_casts = p.commander_cast_count.duplicate(), lost = p.lost,
		})
	return out


## Names (with state) of every card in every zone for each player: {player: {battlefield, hand, graveyard, exile, command}}.
static func board(engine: RulesEngine) -> Dictionary:
	var out := {}
	for p in engine.state.players:
		var zones := {}
		for pair in [["battlefield", EngineEnums.ZoneId.BATTLEFIELD], ["hand", EngineEnums.ZoneId.HAND], ["graveyard", EngineEnums.ZoneId.GRAVEYARD],
				["exile", EngineEnums.ZoneId.EXILE], ["command", EngineEnums.ZoneId.COMMAND]]:
			var rows: Array = []
			var zone: Zone = engine.state.zones.get_zone(int(pair[1]), p.player_id) if int(pair[1]) != EngineEnums.ZoneId.BATTLEFIELD \
				else engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
			if zone != null:
				for oid in zone.object_ids:
					var obj: GameObject = engine.state.objects.get(oid)
					if obj == null or not (obj.definition is CardDefinition):
						continue
					if int(pair[1]) == EngineEnums.ZoneId.BATTLEFIELD and obj.controller_id != p.player_id:
						continue
					rows.append(card_line(engine, obj))
			zones[str(pair[0])] = rows
		out[str(p.player_id)] = zones
	return out


static func card_line(engine: RulesEngine, obj: GameObject) -> String:
	var def := obj.definition as CardDefinition
	var bits: Array = [def.name]
	if obj.zone == EngineEnums.ZoneId.BATTLEFIELD:
		if engine.is_creature_now(obj):
			bits.append("%d/%d" % [engine.power_of(obj), engine.toughness_of(obj)])
		if obj.tapped:
			bits.append("tapped")
		if obj.summoned_this_turn:
			bits.append("sick")
		for k in obj.counters.keys():
			if int(obj.counters[k]) != 0:
				bits.append("%s x%d" % [str(k), int(obj.counters[k])])
		if obj.attached_to != 0 and engine.state.objects.has(obj.attached_to) and (engine.state.objects[obj.attached_to] as GameObject).definition is CardDefinition:
			bits.append("on " + ((engine.state.objects[obj.attached_to] as GameObject).definition as CardDefinition).name)
		if obj.is_token:
			bits.append("token")
		if obj.controller_id != obj.owner_id:
			bits.append("owned by p%d" % obj.owner_id)
	return " ".join(PackedStringArray(bits.map(func(x): return str(x))))


static func stack_summary(engine: RulesEngine) -> Array:
	var out: Array = []
	var stk := engine.state.stack as MagicStack
	if stk == null:
		return out
	for e in stk.entries:
		var se := e as StackEntry
		if se == null:
			continue
		var src: GameObject = engine.state.objects.get(se.source_id)
		var kinds: Array = []
		for fx in se.effects:
			kinds.append(str((fx as AbilityEffect).kind))
		out.append("%s of %s (p%d) effects=%s targets=%s" % [str(se.ability_id), (src.definition as CardDefinition).name if src != null and src.definition is CardDefinition else "?",
			se.controller_id, str(kinds), str(se.targets)])
	return out


## Oracle lines of the cards in play, hand, graveyard and command zone that the engine does not act on yet: {card name: [lines]}.
static func unread_lines_in_play(session: GameSession) -> Dictionary:
	var out := {}
	if session == null or session.db == null or session.engine == null:
		return out
	var seen := {}
	for obj in session.engine.state.objects.values():
		var o := obj as GameObject
		if o == null or o.is_token or not (o.definition is CardDefinition) or o.zone == EngineEnums.ZoneId.LIBRARY:
			continue
		var def := o.definition as CardDefinition
		if seen.has(def.name):
			continue
		seen[def.name] = true
		var lines: Array = session.db.unread_lines(def)
		if not lines.is_empty():
			out[def.name] = lines
	return out


## The report as text a person can read and paste anywhere.
static func to_text(report: Dictionary) -> String:
	var t: PackedStringArray = []
	t.append("%s bug report %s" % [str(report.get("app", "Aetherfold")), str(report.get("build", ""))])
	t.append("Saved %s   seed %s   %s" % [str(report.get("saved_at", "")), str(report.get("seed", "?")), "online" if bool(report.get("online", false)) else "solo"])
	t.append("")
	t.append("WHAT HAPPENED")
	t.append(str(report.get("what_happened", "")) if str(report.get("what_happened", "")) != "" else "(nothing written)")
	t.append("")
	t.append("WHAT DIDN'T HAPPEN (what should have)")
	t.append(str(report.get("what_didnt_happen", "")) if str(report.get("what_didnt_happen", "")) != "" else "(nothing written)")
	t.append("")
	if report.has("turn"):
		t.append("STATE: turn %s, active player %s, %s / %s, engine mode %s" % [str(report["turn"]), str(report["active_player"]), str(report["phase"]), str(report["step"]), str(report["mode"])])
		for i in (report["players"] as Array).size():
			var p: Dictionary = (report["players"] as Array)[i]
			t.append("  p%d %s: life %s, poison %s, energy %s, library %s, hand %s%s" % [i, str(p.get("name", "")), str(p.get("life", "")), str(p.get("poison", 0)), str(p.get("energy", 0)),
				str(p.get("library", "")), str(p.get("hand", "")), "  (LOST)" if bool(p.get("lost", false)) else ""])
		t.append("")
		t.append("BOARD")
		var board: Dictionary = report.get("board", {})
		for pid in board.keys():
			t.append("  player %s" % str(pid))
			var zones: Dictionary = board[pid]
			for z in zones.keys():
				t.append("    %s: %s" % [str(z), ", ".join(PackedStringArray(zones[z])) if not (zones[z] as Array).is_empty() else "-"])
		t.append("")
		t.append("STACK")
		var stack: Array = report.get("stack", [])
		t.append("  (empty)" if stack.is_empty() else "\n".join(PackedStringArray(stack.map(func(x): return "  " + str(x)))))
		t.append("")
		var unread: Dictionary = report.get("unread_lines", {})
		if not unread.is_empty():
			t.append("LINES THE ENGINE DOES NOT READ YET (cards in this match)")
			for n in unread.keys():
				for l in unread[n]:
					t.append("  %s: %s" % [str(n), str(l)])
			t.append("")
	t.append("LAST %d TURNS (play-by-play)" % int(report.get("turns_kept", TURNS_KEPT)))
	for l in report.get("history", []):
		t.append(str(l))
	if str(report.get("last_error", "")) != "":
		t.append("")
		t.append("LAST ERROR SHOWN: " + str(report["last_error"]))
	if report.has("events"):
		t.append("")
		t.append("ENGINE EVENTS (last %d turns)" % int(report.get("turns_kept", TURNS_KEPT)))
		for l in report["events"]:
			t.append(str(l))
	if report.has("debug_tail") and not (report["debug_tail"] as Array).is_empty():
		t.append("")
		t.append("DEBUG TAIL")
		for l in report["debug_tail"]:
			t.append(str(l))
	return "\n".join(t) + "\n"


## Writes bugreport_<time>.txt and .json into `dir` and returns the .txt path ("" if it could not be written).
static func save(report: Dictionary, dir: String = DIR) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := str(report.get("saved_at", Time.get_datetime_string_from_system())).replace(":", "").replace("-", "").replace("T", "_").replace(" ", "_")
	var base := "%s/bugreport_%s_turn%s" % [dir, stamp, str(report.get("turn", 0))]
	var txt := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if txt == null:
		return ""
	txt.store_string(to_text(report))
	txt.close()
	var js := FileAccess.open(base + ".json", FileAccess.WRITE)
	if js != null:
		js.store_string(JSON.stringify(report, "  "))
		js.close()
	return base + ".txt"


static func _enum_name(e: Dictionary, value: int) -> String:
	for k in e.keys():
		if int(e[k]) == value:
			return str(k)
	return str(value)


## A payload on one line: {key: value ...} with long values cut.
static func _compact(payload: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in payload.keys():
		var v := str(payload[k])
		if v.length() > 60:
			v = v.substr(0, 57) + "..."
		parts.append("%s=%s" % [str(k), v])
	return " ".join(parts)
