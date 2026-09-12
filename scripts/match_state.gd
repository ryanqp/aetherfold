extends RefCounted

## Commander table state reconstructed from the web Aetherfold prototype.

enum Phase { UNTAP, UPKEEP, DRAW, MAIN_1, COMBAT, MAIN_2, END }
const PHASE_NAMES := ["Untap", "Upkeep", "Draw", "Main", "Combat", "Main 2", "End"]

var turn := 1
var active_is_you := true
var phase: Phase = Phase.MAIN_1
var selected_id := ""
var difficulty := 1
var rival_commander_tax := 0
var you_land_played := false
var you_mana_spent := 0
var rival_mana_spent := 0
var you_drew_this_turn := true
var you_token_seq := 0

var you := {
	"name": "Krenko",
	"subtitle": "Mob Boss",
	"life": 40,
	"library": 92,
	"graveyard": 0,
	"exile": 0,
	"command": [],
	"creatures": [],
	"noncreatures": [],
	"lands": [],
	"hand": [],
	"library_cards": [],
}

var rival := {
	"name": "Talrand",
	"subtitle": "Sky Summoner",
	"life": 40,
	"library": 92,
	"graveyard": 0,
	"exile": 0,
	"command": [],
	"creatures": [],
	"noncreatures": [],
	"lands": [],
	"hand": [],
	"library_cards": [],
	"drake_seq": 0,
}

func _init() -> void:
	seed_demo()

func seed_demo() -> void:
	turn = 1
	active_is_you = true
	phase = Phase.MAIN_1
	selected_id = ""
	rival_commander_tax = 0
	you_land_played = false
	you_mana_spent = 0
	rival_mana_spent = 0
	you_drew_this_turn = true
	you_token_seq = 0
	you["life"] = 40
	you["library"] = 92
	you["graveyard"] = 0
	you["exile"] = 0
	you["creatures"] = []
	you["noncreatures"] = []
	you["lands"] = []
	rival["life"] = 40
	rival["graveyard"] = 0
	rival["exile"] = 0
	rival["creatures"] = []
	rival["noncreatures"] = []
	rival["lands"] = []
	rival["drake_seq"] = 0
	rival["command"] = [{
		"id": "talrand",
		"name": "Talrand, Sky Summoner",
		"type": "Legendary Creature — Merfolk Wizard",
		"text": "Whenever you cast an instant or sorcery spell, create a 2/2 blue Drake creature token with flying.",
		"color": Color(0.18, 0.42, 0.62),
		"cmc": 4,
		"power": "2",
		"toughness": "2",
	}]
	you["command"] = [{
		"id": "krenko",
		"name": "Krenko, Mob Boss",
		"type": "Legendary Creature — Goblin Warrior",
		"text": "{4}{R}: Create X 1/1 red Goblin creature tokens, where X is the number of Goblins you control.",
		"color": Color(0.72, 0.22, 0.12),
		"cmc": 5,
		"power": "2",
		"toughness": "2",
	}]
	_seed_krenko()
	_seed_talrand()

func _seed_krenko() -> void:
	var deck: Array = []
	deck.append(_card("muxus", "Muxus, Goblin Grandee", "Legendary Creature — Goblin", "When Muxus enters, reveal the top six cards of your library...", Color(0.75, 0.28, 0.14), "spell", 6))
	deck.append(_card("pashalik", "Pashalik Mons", "Legendary Creature — Goblin Warrior", "Whenever Pashalik Mons or another Goblin you control dies, Pashalik Mons deals 1 damage to any target.", Color(0.68, 0.24, 0.12), "spell", 3))
	for i in range(1, 13):
		deck.append(_card("ringleader_%d" % i, "Goblin Ringleader", "Creature — Goblin", "Reveal the top four cards of your library...", Color(0.7, 0.32, 0.16), "spell", 4))
	for i in range(1, 17):
		deck.append(_card("fodder_%d" % i, "Dragon Fodder", "Sorcery", "Create two 1/1 red Goblin creature tokens.", Color(0.78, 0.38, 0.14), "spell", 2))
	for i in range(1, 15):
		deck.append(_card("snoop_%d" % i, "Conspicuous Snoop", "Creature — Goblin Rogue", "Play with the top card of your library revealed.", Color(0.62, 0.2, 0.14), "spell", 2))
	for i in range(1, 9):
		deck.append(_card("cave_%d" % i, "Forgotten Cave", "Land", "{T}: Add {R}. Cycling {R}.", Color(0.55, 0.22, 0.16), "land", 0))
	for i in range(1, 48):
		deck.append(_card("mountain_%d" % i, "Mountain", "Basic Land — Mountain", "{T}: Add {R}.", Color(0.82, 0.36, 0.22), "land", 0))
	var opener: Array = [deck[0], deck[2], deck[14], deck[30], deck[44], deck[1], deck[52]]
	var rest: Array = []
	for card in deck:
		var keep := true
		for held in opener:
			if held["id"] == card["id"]:
				keep = false
				break
		if keep:
			rest.append(card)
	rest.shuffle()
	you["hand"] = opener
	you["library_cards"] = rest
	you["library"] = rest.size()

func _seed_talrand() -> void:
	var deck: Array = []
	for i in range(1, 37):
		deck.append(_make_island(i))
	for i in range(1, 17):
		deck.append(_make_opt(i))
	for i in range(1, 15):
		deck.append(_make_ponder(i))
	for i in range(1, 13):
		deck.append(_make_unsummon(i))
	for i in range(1, 13):
		deck.append(_make_counter(i))
	for i in range(1, 10):
		deck.append(_make_cancel(i))
	var opener: Array = [
		deck[0], deck[1], deck[2],
		deck[36], deck[52], deck[66], deck[78],
	]
	var rest: Array = []
	for card in deck:
		var keep := true
		for held in opener:
			if held["id"] == card["id"]:
				keep = false
				break
		if keep:
			rest.append(card)
	rest.shuffle()
	rival["hand"] = opener
	rival["library_cards"] = rest
	rival["library"] = rest.size()

func _make_island(n: int) -> Dictionary:
	return _card("island_%d" % n, "Island", "Basic Land — Island", "{T}: Add {U}.", Color(0.2, 0.4, 0.7), "land", 0)

func _make_opt(n: int) -> Dictionary:
	return _card("opt_%d" % n, "Opt", "Instant", "Scry 1, then draw a card.", Color(0.2, 0.45, 0.75), "spell", 1)

func _make_ponder(n: int) -> Dictionary:
	return _card("ponder_%d" % n, "Ponder", "Sorcery", "Look at the top three cards of your library...", Color(0.22, 0.42, 0.72), "spell", 1)

func _make_unsummon(n: int) -> Dictionary:
	return _card("unsummon_%d" % n, "Unsummon", "Instant", "Return target creature to its owner's hand.", Color(0.25, 0.48, 0.78), "spell", 1)

func _make_counter(n: int) -> Dictionary:
	return _card("counter_%d" % n, "Counterspell", "Instant", "Counter target spell.", Color(0.18, 0.38, 0.7), "spell", 2)

func _make_cancel(n: int) -> Dictionary:
	return _card("cancel_%d" % n, "Cancel", "Instant", "Counter target spell.", Color(0.2, 0.4, 0.68), "spell", 3)

func _card(id: String, card_name: String, type_line: String, text: String, color: Color, kind: String = "spell", cmc: int = 0) -> Dictionary:
	return {
		"id": id,
		"name": card_name,
		"type": type_line,
		"text": text,
		"color": color,
		"kind": kind,
		"cmc": cmc,
		"sick": false,
		"tapped": false,
	}

func active_name() -> String:
	return str(you["name"] if active_is_you else rival["name"])

func phase_name() -> String:
	return PHASE_NAMES[phase]

func header_text() -> String:
	return "Turn %d — %s · %s" % [turn, active_name(), phase_name()]

func find_card(card_id: String) -> Dictionary:
	for pile in [you["hand"], you["lands"], you["creatures"], you["noncreatures"], you["command"], rival["hand"], rival["lands"], rival["creatures"], rival["noncreatures"], rival["command"]]:
		for card in pile:
			if str(card["id"]) == card_id:
				return card
	return {}

func card_in_hand(card_id: String) -> Dictionary:
	for held in you["hand"]:
		if str(held["id"]) == card_id:
			return held
	return {}

func next_stage() -> void:
	phase = ((int(phase) + 1) % PHASE_NAMES.size()) as Phase

func end_turn() -> void:
	if not active_is_you:
		return
	active_is_you = false
	rival_mana_spent = 0
	_untap_lands(rival)
	_clear_sick(rival)
	phase = Phase.UNTAP

func begin_your_turn() -> void:
	active_is_you = true
	turn += 1
	you_land_played = false
	you_mana_spent = 0
	you_drew_this_turn = false
	_untap_lands(you)
	_clear_sick(you)
	phase = Phase.DRAW

func start_your_turn() -> String:
	if not active_is_you:
		begin_your_turn()
	return draw_card()

func draw_card() -> String:
	if you_drew_this_turn:
		return "You already drew this turn. Click a card in your hand to play it."
	var deck: Array = you["library_cards"]
	if deck.is_empty():
		you["library"] = 0
		return "Your library is empty."
	var card: Dictionary = deck.pop_front()
	you["library_cards"] = deck
	you["library"] = deck.size()
	var hand: Array = you["hand"]
	hand.append(card)
	you["hand"] = hand
	you_drew_this_turn = true
	selected_id = str(card.get("id", ""))
	phase = Phase.MAIN_1
	return "Drew %s. Your turn — click a card to play it." % card.get("name", "a card")

func mana_available(who: String) -> int:
	var lands: Array = you["lands"] if who == "you" else rival["lands"]
	var n := 0
	for land in lands:
		if not bool(land.get("tapped", false)):
			n += 1
	return n

func tap_player_lands(who: String, amount: int) -> void:
	var lands: Array = you["lands"] if who == "you" else rival["lands"]
	var left := amount
	for i in lands.size():
		if left <= 0:
			break
		var land: Dictionary = lands[i]
		if not bool(land.get("tapped", false)):
			land["tapped"] = true
			lands[i] = land
			left -= 1
	if who == "you":
		you["lands"] = lands
	else:
		rival["lands"] = lands

func _untap_lands(player: Dictionary) -> void:
	var lands: Array = player["lands"]
	for i in lands.size():
		var land: Dictionary = lands[i]
		land["tapped"] = false
		lands[i] = land
	player["lands"] = lands

func _clear_sick(player: Dictionary) -> void:
	for card in player["creatures"]:
		card["sick"] = false

func play_from_hand(card_id: String) -> String:
	if not active_is_you:
		return "Wait for your turn."
	var card := card_in_hand(card_id)
	if card.is_empty():
		return "That card is not in your hand."
	selected_id = card_id
	if _is_land(card):
		if you_land_played:
			return "Already played a land this turn."
		_move_from_hand_to(card, "lands")
		you_land_played = true
		_select_next_hand_card()
		return "Played %s. Mana %d." % [card["name"], mana_available("you")]
	var cost := int(card.get("cmc", 0))
	var mana := mana_available("you")
	if cost > mana:
		return "Not enough mana for %s (%d, have %d). Play lands first." % [card["name"], cost, mana]
	you_mana_spent += cost
	tap_player_lands("you", cost)
	var type_line := str(card.get("type", ""))
	if type_line.find("Creature") >= 0:
		card["sick"] = true
		_move_from_hand_to(card, "creatures")
		_select_next_hand_card()
		return "Cast %s for %d. Mana left %d." % [card["name"], cost, mana_available("you")]
	if type_line.find("Instant") >= 0 or type_line.find("Sorcery") >= 0:
		var hand: Array = you["hand"]
		hand.erase(card)
		you["hand"] = hand
		you["graveyard"] = int(you["graveyard"]) + 1
		var extra := _resolve_you_spell(card)
		_select_next_hand_card()
		return "Cast %s for %d. Mana left %d.%s" % [card["name"], cost, mana_available("you"), extra]
	_move_from_hand_to(card, "noncreatures")
	_select_next_hand_card()
	return "Cast %s for %d. Mana left %d." % [card["name"], cost, mana_available("you")]

func activate_selected() -> String:
	if selected_id == "":
		return "Select a card first."
	var in_hand := card_in_hand(selected_id)
	if in_hand.is_empty():
		var card := find_card(selected_id)
		if card.is_empty():
			return "Select a card first."
		return "%s is already in play. Click a card in your hand to play it." % card["name"]
	return play_from_hand(selected_id)

func _resolve_you_spell(card: Dictionary) -> String:
	var n := str(card.get("name", "")).to_lower()
	if n == "dragon fodder":
		_make_you_token("Goblin", "Token Creature — Goblin", "1", "1", Color(0.72, 0.22, 0.12))
		_make_you_token("Goblin", "Token Creature — Goblin", "1", "1", Color(0.72, 0.22, 0.12))
		return " Created two Goblin tokens."
	return ""

func _make_you_token(token_name: String, type_line: String, power: String, toughness: String, color: Color) -> void:
	you_token_seq += 1
	var tok := {
		"id": "you_tok_%d" % you_token_seq,
		"name": token_name,
		"type": type_line,
		"text": "",
		"power": power,
		"toughness": toughness,
		"cmc": 0,
		"sick": true,
		"color": color,
	}
	var creatures: Array = you["creatures"]
	creatures.append(tok)
	you["creatures"] = creatures

func _is_land(card: Dictionary) -> bool:
	if str(card.get("kind", "")) == "land":
		return true
	var type_line := str(card.get("type", ""))
	return type_line.find("Land") >= 0 and type_line.find("Creature") < 0

func _select_next_hand_card() -> void:
	var hand: Array = you["hand"]
	if hand.is_empty():
		selected_id = ""
		return
	selected_id = str(hand.back()["id"])

func _move_from_hand_to(card: Dictionary, zone: String) -> void:
	var hand: Array = you["hand"]
	hand.erase(card)
	you["hand"] = hand
	var dest: Array = you[zone]
	dest.append(card)
	you[zone] = dest
