extends RefCounted

## Talrand AI. Four difficulties change land, spell, commander, and attack decisions.

const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard", "Expert"]

static func label(difficulty: int) -> String:
	var i := clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	return DIFFICULTY_NAMES[i]

static func take_turn(state) -> String:
	var log: PackedStringArray = PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := clampi(int(state.difficulty), 0, 3)
	state.rival_mana_spent = 0
	_draw(state, d, rng, log)
	_play_land(state, d, rng, log)
	_cast_commander(state, d, rng, log)
	_cast_spells(state, d, rng, log)
	_attack(state, d, rng, log)
	if log.is_empty():
		return "Talrand (%s) passed." % label(d)
	return "Talrand (%s): %s" % [label(d), " ".join(log)]

static func _draw(state, d: int, rng: RandomNumberGenerator, log: PackedStringArray) -> void:
	if d == 0 and rng.randf() < 0.25:
		log.append("Forgot to draw.")
		return
	_draw_one(state, log)

static func _draw_one(state, log: PackedStringArray) -> void:
	var deck: Array = state.rival["library_cards"]
	if deck.is_empty():
		return
	var card: Dictionary = deck.pop_front()
	state.rival["library_cards"] = deck
	state.rival["library"] = deck.size()
	var hand: Array = state.rival["hand"]
	hand.append(card)
	state.rival["hand"] = hand
	log.append("Drew %s." % card.get("name", "a card"))

static func _play_land(state, d: int, rng: RandomNumberGenerator, log: PackedStringArray) -> void:
	if d == 0 and rng.randf() < 0.4:
		return
	var land := _first_land(state.rival["hand"])
	if land.is_empty():
		return
	_move(state, land, "lands")
	log.append("Played %s." % land.get("name", "a land"))

static func _cast_spells(state, d: int, rng: RandomNumberGenerator, log: PackedStringArray) -> void:
	var spell_caps: Array[int] = [1, 1, 3, 8]
	var max_spells: int = spell_caps[d]
	if d == 0 and rng.randf() < 0.35:
		max_spells = 0
	var cast_count := 0
	while cast_count < max_spells:
		var card := _cheapest_castable(state, d)
		if card.is_empty():
			break
		_play_spell(state, card, d, log)
		cast_count += 1

static func _play_spell(state, card: Dictionary, d: int, log: PackedStringArray) -> void:
	var cost := int(card.get("cmc", 0))
	if cost > _mana(state):
		return
	state.rival_mana_spent = int(state.rival_mana_spent) + cost
	state.tap_player_lands("rival", cost)
	var type_line := str(card.get("type", ""))
	if _is_instant_or_sorcery(card):
		_discard(state, card)
		log.append("Cast %s for %d." % [card.get("name", "a spell"), cost])
		if _talrand_in_play(state):
			_make_drake(state)
			log.append("Talrand made a Drake.")
		_on_spell(state, card, d, log)
	elif type_line.find("Creature") >= 0:
		card["sick"] = true
		_move(state, card, "creatures")
		log.append("Cast %s for %d." % [card.get("name", "a spell"), cost])
	else:
		_move(state, card, "noncreatures")
		log.append("Cast %s for %d." % [card.get("name", "a spell"), cost])

static func _on_spell(state, card: Dictionary, d: int, log: PackedStringArray) -> void:
	var n := str(card.get("name", "")).to_lower()
	if n == "opt" or n == "ponder":
		_draw_one(state, log)
	if n == "unsummon" and d >= 2:
		_bounce_you(state, log)

static func _bounce_you(state, log: PackedStringArray) -> void:
	var creatures: Array = state.you["creatures"]
	if creatures.is_empty():
		return
	var card: Dictionary = creatures.pop_back()
	state.you["creatures"] = creatures
	var hand: Array = state.you["hand"]
	hand.append(card)
	state.you["hand"] = hand
	log.append("Unsummoned %s." % card.get("name", "a creature"))

static func _cast_commander(state, d: int, rng: RandomNumberGenerator, log: PackedStringArray) -> void:
	var cmd: Array = state.rival["command"]
	if cmd.is_empty():
		return
	var cmd_chances: Array[float] = [0.15, 0.55, 0.9, 1.0]
	if rng.randf() > cmd_chances[d]:
		return
	var card: Dictionary = cmd[0]
	var cost := int(card.get("cmc", 4)) + int(state.rival_commander_tax)
	if _mana(state) < cost:
		return
	state.rival_mana_spent = int(state.rival_mana_spent) + cost
	state.tap_player_lands("rival", cost)
	cmd.remove_at(0)
	state.rival["command"] = cmd
	card["sick"] = true
	var creatures: Array = state.rival["creatures"]
	creatures.append(card)
	state.rival["creatures"] = creatures
	state.rival_commander_tax = int(state.rival_commander_tax) + 2
	log.append("Cast commander %s." % card.get("name", "Talrand"))

static func _attack(state, d: int, rng: RandomNumberGenerator, log: PackedStringArray) -> void:
	var attack_chances: Array[float] = [0.3, 0.7, 1.0, 1.0]
	if rng.randf() > attack_chances[d]:
		return
	var damage := 0
	var names: PackedStringArray = PackedStringArray()
	for card in state.rival["creatures"]:
		if bool(card.get("sick", false)):
			continue
		var pwr := _power_of(card)
		if pwr <= 0:
			continue
		damage += pwr
		names.append(str(card.get("name", "a creature")))
	if damage <= 0:
		return
	if d == 0:
		damage = max(int(ceil(float(damage) * 0.5)), 1)
	elif d == 1:
		damage = max(damage - 1, 1) if damage > 1 else damage
	state.you["life"] = int(state.you["life"]) - damage
	if names.size() == 1:
		log.append("%s attacked you for %d." % [names[0], damage])
	else:
		log.append("%d creatures attacked you for %d." % [names.size(), damage])

static func _mana(state) -> int:
	var n := 0
	for land in state.rival["lands"]:
		if not bool(land.get("tapped", false)):
			n += 1
	return n

static func _talrand_in_play(state) -> bool:
	for card in state.rival["creatures"]:
		var n := str(card.get("name", ""))
		if n.find("Talrand") >= 0:
			return true
	return false

static func _first_land(hand: Array) -> Dictionary:
	for card in hand:
		if _is_land_card(card):
			return card
	return {}

static func _cheapest_castable(state, d: int) -> Dictionary:
	var best := {}
	var best_cmc := 99
	var mana := _mana(state)
	for card in state.rival["hand"]:
		if _is_land_card(card):
			continue
		var cmc := int(card.get("cmc", 0))
		if cmc > mana:
			continue
		if d >= 3 and _is_counterspell(card) and mana - cmc < 2:
			continue
		var score := cmc
		if d >= 2 and _is_instant_or_sorcery(card):
			score -= 1
		if score < best_cmc:
			best_cmc = score
			best = card
	return best

static func _is_land_card(card: Dictionary) -> bool:
	var type_line := str(card.get("type", ""))
	return str(card.get("kind", "")) == "land" or (type_line.find("Land") >= 0 and type_line.find("Creature") < 0)

static func _is_instant_or_sorcery(card: Dictionary) -> bool:
	var type_line := str(card.get("type", ""))
	return type_line.find("Instant") >= 0 or type_line.find("Sorcery") >= 0

static func _is_counterspell(card: Dictionary) -> bool:
	var n := str(card.get("name", "")).to_lower()
	return n == "counterspell" or n == "cancel" or n == "swan song"

static func _power_of(card: Dictionary) -> int:
	return str(card.get("power", "0")).to_int()

static func _move(state, card: Dictionary, zone: String) -> void:
	var hand: Array = state.rival["hand"]
	hand.erase(card)
	state.rival["hand"] = hand
	var dest: Array = state.rival[zone]
	dest.append(card)
	state.rival[zone] = dest

static func _discard(state, card: Dictionary) -> void:
	var hand: Array = state.rival["hand"]
	hand.erase(card)
	state.rival["hand"] = hand
	state.rival["graveyard"] = int(state.rival["graveyard"]) + 1

static func _make_drake(state) -> void:
	var n := int(state.rival.get("drake_seq", 0)) + 1
	state.rival["drake_seq"] = n
	var drake := {
		"id": "drake_%d" % n,
		"name": "Drake",
		"type": "Token Creature — Drake",
		"text": "Flying",
		"power": "2",
		"toughness": "2",
		"cmc": 0,
		"sick": true,
		"color": Color(0.25, 0.45, 0.7),
	}
	var creatures: Array = state.rival["creatures"]
	creatures.append(drake)
	state.rival["creatures"] = creatures
