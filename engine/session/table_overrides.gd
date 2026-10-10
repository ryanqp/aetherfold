class_name TableOverrides
extends RefCounted
## The Override menu's actions: the things you can do at a real table that the rules would never let a program do on its
## own (add mana, fix a life total, kill, revive, make a token ...). Each action is one plain Dictionary so it can travel
## to the other player to be agreed to before it happens (online), or be applied at once (against the bot).
##
## Player actions   {op, who: "me" | "rival", n | delta | color}
##   mana {color W/U/B/R/G/C, n}   life {delta}   poison {delta}   cmdr_damage {delta}   draw {n}   discard {n} (random)
##   mill {n}   untap_all   extra_turn   shuffle   token {preset | p, t, name, colors, who}
## Card actions     {op, object_id, ...}
##   move {to: BATTLEFIELD / HAND / GRAVEYARD / EXILE / LIBRARY}   tap   untap   counters {name, n}   pt {delta}   control   copy
##
## `apply` returns "" when it worked, else a sentence saying why not. `describe` is the one-line summary shown to the
## player who has to agree.

const TOKEN_PRESETS := {
	"treasure": {"label": "Treasure"},
	"food": {"label": "Food"},
	"clue": {"label": "Clue"},
	"soldier": {"label": "1/1 Soldier", "p": "1", "t": "1", "colors": ["W"], "subtypes": ["Soldier"]},
	"goblin": {"label": "1/1 Goblin", "p": "1", "t": "1", "colors": ["R"], "subtypes": ["Goblin"]},
	"zombie": {"label": "2/2 Zombie", "p": "2", "t": "2", "colors": ["B"], "subtypes": ["Zombie"]},
	"beast": {"label": "3/3 Beast", "p": "3", "t": "3", "colors": ["G"], "subtypes": ["Beast"]},
	"dragon": {"label": "4/4 Dragon", "p": "4", "t": "4", "colors": ["R"], "subtypes": ["Dragon"], "keywords": ["Flying"]},
}

const COLOR_NAMES := {"W": "white", "U": "blue", "B": "black", "R": "red", "G": "green", "C": "colorless"}
const ZONE_BY_NAME := {
	"BATTLEFIELD": EngineEnums.ZoneId.BATTLEFIELD, "HAND": EngineEnums.ZoneId.HAND, "GRAVEYARD": EngineEnums.ZoneId.GRAVEYARD,
	"EXILE": EngineEnums.ZoneId.EXILE, "LIBRARY": EngineEnums.ZoneId.LIBRARY,
}


## The seat an action's "me" / "rival" means when `caller` asked for it.
static func seat_of(engine: RulesEngine, op: Dictionary, caller: int) -> int:
	if str(op.get("who", "me")) == "me":
		return caller
	for p in engine.state.players:
		if p.player_id != caller and not p.lost:
			return p.player_id
	return caller


static func _name_of_seat(engine: RulesEngine, seat: int) -> String:
	if seat < 0 or seat >= engine.state.players.size():
		return "a player"
	return str(engine.state.players[seat].name)


static func _card_name(engine: RulesEngine, object_id: int) -> String:
	var obj: GameObject = engine.state.objects.get(object_id)
	if obj != null and obj.definition is CardDefinition:
		return (obj.definition as CardDefinition).name
	return "a card"


static func describe(engine: RulesEngine, op: Dictionary, caller: int) -> String:
	var seat := seat_of(engine, op, caller)
	var who := _name_of_seat(engine, seat)
	var n := clampi(int(op.get("n", 1)), 0, 100)
	var d := clampi(int(op.get("delta", 0)), -100, 100)
	match str(op.get("op", "")):
		"mana":
			return "%s gets %d %s mana" % [who, n, COLOR_NAMES.get(str(op.get("color", "C")), "colorless")]
		"life":
			return "%s %s %d life" % [who, "gains" if d >= 0 else "loses", absi(d)]
		"poison":
			return "%s %s %d poison counter%s" % [who, "gets" if d >= 0 else "loses", absi(d), "" if absi(d) == 1 else "s"]
		"cmdr_damage":
			return "%s takes %s%d commander damage" % [who, "+" if d >= 0 else "-", absi(d)]
		"draw":
			return "%s draws %d card%s" % [who, n, "" if n == 1 else "s"]
		"discard":
			return "%s discards %d card%s at random" % [who, n, "" if n == 1 else "s"]
		"mill":
			return "%s mills %d card%s" % [who, n, "" if n == 1 else "s"]
		"untap_all":
			return "%s untaps everything" % who
		"extra_turn":
			return "%s takes an extra turn" % who
		"shuffle":
			return "%s shuffles their library" % who
		"token":
			return "%s creates a %s token" % [who, str(op.get("label", "token"))]
		"move":
			var nm := _card_name(engine, int(op.get("object_id", 0)))
			match str(op.get("to", "")):
				"BATTLEFIELD":
					return "Put %s onto the battlefield" % nm
				"HAND":
					return "Return %s to hand" % nm
				"GRAVEYARD":
					return "Kill %s (to the graveyard)" % nm
				"EXILE":
					return "Exile %s" % nm
				"LIBRARY":
					return "Put %s on top of the library" % nm
		"tap":
			return "Tap %s" % _card_name(engine, int(op.get("object_id", 0)))
		"untap":
			return "Untap %s" % _card_name(engine, int(op.get("object_id", 0)))
		"counters":
			return "%s %d %s counter%s %s %s" % ["Add" if d >= 0 else "Remove", absi(d), str(op.get("name", "+1/+1")), "" if absi(d) == 1 else "s",
				"to" if d >= 0 else "from", _card_name(engine, int(op.get("object_id", 0)))]
		"pt":
			return "%s gets %s%d/%s%d" % [_card_name(engine, int(op.get("object_id", 0))), "+" if d >= 0 else "-", absi(d), "+" if d >= 0 else "-", absi(d)]
		"control":
			return "%s takes control of %s" % [_name_of_seat(engine, caller), _card_name(engine, int(op.get("object_id", 0)))]
		"copy":
			return "Make a token copy of %s" % _card_name(engine, int(op.get("object_id", 0)))
	return "an override"


## Does it. Returns "" on success, else why not.
static func apply(engine: RulesEngine, op: Dictionary, caller: int) -> String:
	if engine == null or engine.state == null:
		return "No game."
	var seat := seat_of(engine, op, caller)
	var n := clampi(int(op.get("n", 1)), 0, 100)
	var d := clampi(int(op.get("delta", 0)), -100, 100)
	var err := ""
	var pl: PlayerState = engine.state.players[seat] if seat >= 0 and seat < engine.state.players.size() else null
	match str(op.get("op", "")):
		"mana":
			if not COLOR_NAMES.has(str(op.get("color", ""))):
				return "Pick a color."
			for _i in n:
				engine.mana.add(seat, ManaCost.parse("{%s}" % str(op["color"])))
		"life":
			if pl == null:
				return "No such player."
			pl.life += d
			if d > 0:
				pl.life_gained_this_turn += d
			elif d < 0:
				pl.life_lost_this_turn += -d
			engine.state.log.append(EngineEnums.EventType.LIFE_CHANGE, seat, {to_player = seat, amount = absi(d), override = true})
		"poison":
			if pl == null:
				return "No such player."
			pl.poison = maxi(0, pl.poison + d)
		"cmdr_damage":
			err = _commander_damage(engine, seat, d)
		"draw":
			for _i in n:
				engine.draw_card(seat)
		"discard":
			for _i in n:
				var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, seat)
				if hand == null or hand.is_empty():
					break
				engine.discard_card(seat, int(hand.object_ids[engine.state.rng.randi_range(0, hand.size() - 1)]))
		"mill":
			for _i in n:
				var lib: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.LIBRARY, seat)
				if lib == null or lib.is_empty():
					break
				engine.state.zones.move(int(lib.object_ids[0]), EngineEnums.ZoneId.GRAVEYARD, seat)
		"untap_all":
			for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
				var o: GameObject = engine.state.objects.get(oid)
				if o != null and o.controller_id == seat:
					o.tapped = false
		"extra_turn":
			engine.state.extra_turns.insert(0, {"pid": seat, "lose": false})
		"shuffle":
			engine.shuffle_library(seat)
		"token":
			err = _make_token(engine, op, seat)
		"move", "tap", "untap", "counters", "pt", "control", "copy":
			err = _card_op(engine, op, caller)
		_:
			return "Unknown override."
	if err == "":
		engine.state.log.append(EngineEnums.EventType.NOTE, caller, {text = "Override: %s." % describe(engine, op, caller)})
		engine.process_zone_events()
		if engine.sba != null:
			engine.sba.check(engine)
	return err


static func _commander_damage(engine: RulesEngine, seat: int, delta: int) -> String:
	## Commander damage to `seat` from the other player's commander (the table tracks it by "owner:name").
	for p in engine.state.players:
		if p.player_id == seat:
			continue
		for cid in p.commander_ids:
			var c: GameObject = engine.state.objects.get(int(cid))
			if c == null or not (c.definition is CardDefinition):
				continue
			var key := str(c.owner_id) + ":" + (c.definition as CardDefinition).name
			var target: PlayerState = engine.state.players[seat]
			target.commander_damage_from[key] = maxi(0, int(target.commander_damage_from.get(key, 0)) + delta)
			return ""
	return "No commander to take damage from."


static func _make_token(engine: RulesEngine, op: Dictionary, seat: int) -> String:
	var def: CardDefinition = null
	var preset: Variant = TOKEN_PRESETS.get(str(op.get("preset", "")))
	if preset != null:
		var pd: Dictionary = preset
		if pd.has("p"):
			def = engine.executor.tokens.from_spec({"p": pd.p, "t": pd.t, "colors": pd.colors, "subtypes": pd.subtypes, "keywords": pd.get("keywords", [])})
		else:
			def = engine.executor.tokens.definition_for(str(op.get("preset")))
	else:
		def = engine.executor.tokens.from_spec({"p": str(clampi(int(op.get("p", 1)), 0, 99)), "t": str(clampi(int(op.get("t", 1)), 0, 99)), "colors": op.get("colors", []),
			"subtypes": op.get("subtypes", ["Token"]), "name": str(op.get("name", "Token")).substr(0, 30)})
	if def == null:
		return "Can't make that token."
	var made: GameObject = engine.state.zones.create(seat, EngineEnums.ZoneId.BATTLEFIELD, {definition = def, is_token = true, controller_id = seat})
	if made == null:
		return "Can't make that token."
	engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, seat, {
		from_id = 0, to_id = made.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0,
	})
	return ""


static func _card_op(engine: RulesEngine, op: Dictionary, caller: int) -> String:
	var obj: GameObject = engine.state.objects.get(int(op.get("object_id", 0)))
	if obj == null:
		return "That card is gone."
	var d := clampi(int(op.get("delta", 0)), -100, 100)
	match str(op.get("op", "")):
		"move":
			var to_name := str(op.get("to", ""))
			if not ZONE_BY_NAME.has(to_name):
				return "Unknown place."
			var dest: int = ZONE_BY_NAME[to_name]
			if obj.zone == dest:
				return "It is already there."
			if obj.is_token and dest != EngineEnums.ZoneId.BATTLEFIELD:
				## A token that leaves the battlefield stops existing.
				engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.EXILE, obj.owner_id)
				return ""
			var moved: GameObject = engine.state.zones.move(obj.object_id, dest, obj.owner_id)
			if moved == null:
				return "It wouldn't move."
			if dest == EngineEnums.ZoneId.BATTLEFIELD:
				moved.controller_id = obj.owner_id
		"tap":
			obj.tapped = true
		"untap":
			obj.tapped = false
		"counters":
			if obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
				return "Counters go on permanents."
			var cname := str(op.get("name", "+1/+1"))
			obj.counters[cname] = maxi(0, int(obj.counters.get(cname, 0)) + d)
			if int(obj.counters[cname]) == 0:
				obj.counters.erase(cname)
		"pt":
			if obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
				return "Only permanents can change size."
			var key := "+1/+1" if d >= 0 else "-1/-1"
			obj.counters[key] = int(obj.counters.get(key, 0)) + absi(d)
		"control":
			if obj.zone != EngineEnums.ZoneId.BATTLEFIELD:
				return "Only permanents can change hands."
			obj.controller_id = caller
		"copy":
			if obj.zone != EngineEnums.ZoneId.BATTLEFIELD or not (obj.definition is CardDefinition):
				return "Copy a permanent."
			var made: GameObject = engine.state.zones.create(caller, EngineEnums.ZoneId.BATTLEFIELD, {definition = obj.definition, is_token = true, controller_id = caller})
			if made == null:
				return "Can't copy that."
			engine.state.log.append(EngineEnums.EventType.ZONE_CHANGE, caller, {
				from_id = 0, to_id = made.object_id, from_zone = -1, to_zone = EngineEnums.ZoneId.BATTLEFIELD, linked_from = 0,
			})
	return ""
