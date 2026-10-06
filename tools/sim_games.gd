extends SceneTree

## Smoke test: plays bot-vs-bot games (a saved deck against the Talrand deck) so engine errors and stalls show up.
## Usage: godot --headless --path . -s res://tools/sim_games.gd -- <deck.json> [--games=3] [--max-turns=30] [--seed=1]
## Script errors appear in the Godot output; each game prints one summary line (SIM ...) and a "STALL" line if the game stopped
## making progress.

const AiBlocks := preload("res://engine/session/ai_blocks.gd")


func _initialize() -> void:
	var deck_path := ""
	var games := 3
	var max_turns := 30
	var seed0 := 1
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--games="):
			games = int(s.substr(8))
		elif s.begins_with("--max-turns="):
			max_turns = int(s.substr(12))
		elif s.begins_with("--seed="):
			seed0 = int(s.substr(7))
		else:
			deck_path = s
	var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(deck_path))
	if not (rec is Dictionary):
		print("cannot read deck ", deck_path)
		quit(1)
		return
	var deck := NormalizedDeck.from_dict(rec)
	var names := {}
	for n in deck.unique_names():
		names[str(n).to_lower()] = str(n)
	var rows := {}
	var f := FileAccess.open("res://data/scryfall/catalog.jsonl", FileAccess.READ)
	while not f.eof_reached():
		var raw := f.get_line().strip_edges()
		if raw == "":
			continue
		var row: Variant = JSON.parse_string(raw)
		if row is Dictionary and names.has(str((row as Dictionary).get("name", "")).to_lower()):
			rows[str((row as Dictionary).get("name", ""))] = row
	for g in games:
		_play(deck, rows, seed0 + g, max_turns, g)
	quit(0)


func _play(deck: NormalizedDeck, rows: Dictionary, seed: int, max_turns: int, index: int) -> void:
	var s := GameSession.new()
	s.start_imported(deck, rows, seed)
	if s.match_start == GameSession.MatchStart.COIN_FLIP:
		s.match_start = GameSession.MatchStart.MULLIGAN_DECISION
	s.engine.interactive_seats = []
	s.all_bots = true
	s.keep_hand(0)
	var eng := s.engine
	var guard := 0
	var last_turn := -1
	var stalled := 0
	var turn_start := Time.get_ticks_msec()
	while not eng.is_over() and eng.state.turn_number <= max_turns and guard < 3000:
		guard += 1
		if eng.state.turn_number == last_turn:
			stalled += 1
		else:
			var now := Time.get_ticks_msec()
			if last_turn >= 0:
				print("TURN %d took %d ms (events %d, objects %d, effects %d, delayed %d, bf %d)" % [last_turn, now - turn_start, eng.state.log.seq(), eng.state.objects.size(), eng.state.effects.size(), eng.state.delayed.size(), eng.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids.size()])
			var parts: PackedStringArray = []
			for k in GameSession.perf.keys():
				parts.append("%s %d ms x%d" % [k, int(GameSession.perf[k][0]) / 1000, int(GameSession.perf[k][1])])
			print("  perf: ", ", ".join(parts))
			GameSession.perf = {}
			turn_start = now
			stalled = 0
			last_turn = eng.state.turn_number
		if stalled > 60:
			var top_desc := "empty"
			var stk := eng.state.stack as MagicStack
			if stk != null and not stk.is_empty():
				var te: StackEntry = stk.top()
				top_desc = "%s effects=%s ctrl=%d" % [str(te.ability_id), str(te.effects.map(func(x): return str(x.kind))), te.controller_id]
			for la2 in eng.legal_actions(int(eng.state.awaiting.get("player_id", 0))):
				var ga2 := la2 as GameAction
				if ga2.kind == GameAction.Kind.CAST_SPELL:
					var o2: GameObject = eng.state.objects.get(ga2.object_id)
					var r2 := s.cast_auto(int(eng.state.awaiting.get("player_id", 0)), ga2.object_id)
					print("  TRY cast %s -> ok=%s err=%s mode=%d tp=%s" % [(o2.definition as CardDefinition).name if o2 != null else "?", str(r2.ok), r2.error, eng.state.mode, str(s.target_pending)])
					break
			var rp := s.pass_priority(int(eng.state.awaiting.get("player_id", 0)))
			print("  TRY pass -> ok=%s err=%s step=%d mode=%d awaiting=%s" % [str(rp.ok), rp.error, eng.state.step, eng.state.mode, str(eng.state.awaiting)])
			var kinds: Array = []
			for la in eng.legal_actions(int(eng.state.awaiting.get("player_id", 0))):
				kinds.append(str((la as GameAction).kind))
			print("STALL legal=%s last_error=%s skipped_cast=%s" % [str(kinds.slice(0, 12)), s.last_error, ""])
			print("STALL game %d at turn %d step %d mode %d active %d awaiting %s stack %d (%s) pending=%s" % [index, eng.state.turn_number, eng.state.step, eng.state.mode, eng.state.active_player_id, str(eng.state.awaiting), stk.size() if stk != null else 0, top_desc, str(eng.state.pending_decision != null)])
			break
		## Seat 0 plays like a person would at the table: a target picker or a land question waits for an answer.
		if s.target_pending and not s.target_prompt.is_empty():
			if stalled < 12:
				print("  TARGETPROMPT ", str(s.target_prompt).substr(0, 300))
			s.choose_target(int(((s.target_prompt["options"] as Array)[0] as Dictionary)["id"]))
			continue
		if not s.land_prompt.is_empty():
			if stalled < 12:
				print("  LANDPROMPT ", str(s.land_prompt))
			s.answer_land(true)
			continue
		if stalled >= 3 and stalled < 8:
			print("  ITER stalled=%d turn=%d step=%d mode=%d active=%d awaiting=%s draw_pending=%s blocks=%s attackers=%s" % [stalled, eng.state.turn_number, eng.state.step, eng.state.mode, eng.state.active_player_id, str(eng.state.awaiting.get("player_id", -1)), str(eng.state.draw_pending), str(s.awaiting_blocks), str(s.choosing_attackers)])
		if s.awaiting_blocks:
			s.declare_blocks(AiBlocks.choose(eng, 0))
			continue
		if eng.state.draw_pending:
			eng.take_turn_draw(eng.state.active_player_id)
			continue
		if not s.can_play():
			break
		if eng.state.active_player_id == 0:
			s.ai_take_turn(0)
			if eng.state.active_player_id == 1 and not s.awaiting_blocks:
				s._finish_bot_turn(1)
		else:
			s._finish_bot_turn(1)
	print("SIM game %d seed %d: turn %d, life %d vs %d, over=%s" % [index, seed, eng.state.turn_number, eng.state.players[0].life, eng.state.players[1].life, str(eng.is_over())])
