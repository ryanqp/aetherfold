@tool
extends McpTestSuite

## What an online host accepts from a guest: the room code, a deck shaped like a deck, and the host's own card data.

const GameNetScript := preload("res://scripts/net/game_net.gd")


func suite_name() -> String:
	return "online_security"


func test_the_room_code_is_checked() -> void:
	assert_true(GameNetScript.code_matches("ab12cd", "AB12CD"), "case does not matter")
	assert_true(GameNetScript.code_matches(" AB12CD ", "AB12CD"), "nor spaces")
	assert_false(GameNetScript.code_matches("", "AB12CD"), "joining by address alone is refused")
	assert_false(GameNetScript.code_matches("ZZZZZZ", "AB12CD"), "a wrong code is refused")
	assert_false(GameNetScript.code_matches("", ""), "a room with no code admits no one")


func _good_deck() -> Dictionary:
	return {
		name = "Fine Deck",
		commander = [{name = "Krenko, Mob Boss", quantity = 1}],
		mainboard = [{name = "Mountain", quantity = 40}, {name = "Sol Ring", quantity = 1}],
		cards = {"Sol Ring": {name = "Sol Ring", oracle_text = "{T}: Add {C}{C}.", faces = []}},
	}


func test_a_normal_deck_is_accepted_and_junk_is_refused() -> void:
	assert_eq(RemoteDeckCheck.problem(_good_deck()), "", "a normal deck")
	assert_eq(RemoteDeckCheck.problem({}), "", "nothing chosen yet is not an error")
	assert_true(RemoteDeckCheck.problem("a string") != "", "not a dictionary")
	var long_name := _good_deck()
	long_name.name = "x".repeat(500)
	assert_true(RemoteDeckCheck.problem(long_name) != "", "an absurd name")
	var many := _good_deck()
	var pile: Array = []
	for i in 400:
		pile.append({name = "Card %d" % i, quantity = 1})
	many.mainboard = pile
	assert_true(RemoteDeckCheck.problem(many) != "", "hundreds of entries")
	var copies := _good_deck()
	copies.mainboard = [{name = "Mountain", quantity = 5000}]
	assert_true(RemoteDeckCheck.problem(copies) != "", "5000 copies")
	var three := _good_deck()
	three.commander = [{name = "A", quantity = 1}, {name = "B", quantity = 1}, {name = "C", quantity = 1}]
	assert_true(RemoteDeckCheck.problem(three) != "", "three commanders")
	var essay := _good_deck()
	essay.cards["Sol Ring"].oracle_text = "words ".repeat(2000)
	assert_true(RemoteDeckCheck.problem(essay) != "", "a card with an essay for text")
	var bad_row := _good_deck()
	bad_row.cards["Sol Ring"] = "not a row"
	assert_true(RemoteDeckCheck.problem(bad_row) != "", "a card row that is not a dictionary")


func test_the_bundled_precons_pass_the_check() -> void:
	for rec in PreconDecks.new().bundled():
		assert_eq(RemoteDeckCheck.problem(rec), "", "%s must be sendable" % str((rec as Dictionary).get("name", "?")))


func test_a_guests_card_rows_never_override_the_hosts_catalog() -> void:
	var cat: Node = (load("res://scripts/scryfall_catalog.gd") as GDScript).new()
	cat.load_catalog()
	var tampered := {
		"Sol Ring": {name = "Sol Ring", type_line = "Artifact", oracle_text = "{T}: Add {C}{C}{C}{C}{C}{C}.", mana_cost = "{0}"},
		"Made Up Card": {name = "Made Up Card", type_line = "Creature — Imp", oracle_text = "Flying"},
	}
	var fixed: Dictionary = DeckCatalog.prefer_catalog_rows(tampered, cat)
	assert_eq(str(fixed["Sol Ring"].oracle_text), "{T}: Add {C}{C}.", "the host's text wins for a card it knows")
	assert_eq(str(fixed["Sol Ring"].mana_cost), "{1}")
	assert_eq(str(fixed["Made Up Card"].oracle_text), "Flying", "a card the host doesn't know is kept")
	cat.free()


func test_a_dropped_guest_keeps_their_seat_for_a_while() -> void:
	## AUDIT-016: the host holds the seat against a secret token; only that token, and only in time, gets it back.
	var seats := SeatReservations.new()
	var token := SeatReservations.new_token()
	assert_eq(token.length(), 16)
	assert_ne(token, SeatReservations.new_token(), "tokens differ")
	seats.hold(token, "Lunar", 1000, 120000)
	assert_true(seats.is_holding(2000), "held")
	assert_true(seats.claim("wrong-token", 2000).is_empty(), "a guess gets nothing")
	assert_true(seats.claim("", 2000).is_empty(), "an empty token gets nothing")
	var seat := seats.claim(token, 60000)
	assert_eq(str(seat.get("name", "")), "Lunar", "the right token within the window gets the seat")
	assert_true(seats.claim(token, 61000).is_empty(), "and it can only be claimed once")
	assert_false(seats.is_holding(61000))


func test_a_held_seat_runs_out() -> void:
	var seats := SeatReservations.new()
	var token := SeatReservations.new_token()
	seats.hold(token, "Lunar", 0, 120000)
	assert_eq(seats.expire(60000).size(), 0, "still held after a minute")
	assert_true(seats.claim(token, 120001).is_empty(), "too late")
	seats.hold("another", "Pat", 0, 1000)
	var gone := seats.expire(5000)
	assert_eq(gone, ["Pat"], "the host learns whose time ran out")
	assert_eq(seats.expire(9000).size(), 0, "and only once")
