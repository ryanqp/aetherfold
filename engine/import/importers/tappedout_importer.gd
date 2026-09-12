class_name TappedOutImporter
extends RefCounted


static func api_urls(slug: String) -> PackedStringArray:
	var s := slug.strip_edges()
	if s == "":
		return PackedStringArray()
	return PackedStringArray([
		"https://tappedout.net/mtg-decks/%s/?fmt=txt" % s,
		"https://tappedout.net/mtg-decks/%s/?fmt=json" % s,
	])


static func parse_payload(text: String, source_url: String = "") -> NormalizedDeck:
	var t := text.strip_edges()
	if t.begins_with("{") or t.begins_with("["):
		var parsed: Variant = JSON.parse_string(t)
		if parsed is Dictionary:
			return parse_json(parsed, source_url)
	var parser := TextDeckParser.new()
	var deck: NormalizedDeck = parser.parse(t)
	deck.source = "tappedout"
	deck.source_url = source_url
	if deck.name == "Imported Deck":
		deck.name = "TappedOut Deck"
	return deck


static func parse_json(json: Dictionary, source_url: String = "") -> NormalizedDeck:
	var deck := NormalizedDeck.new()
	deck.source = "tappedout"
	deck.source_url = source_url
	deck.name = DeckText.sanitize_name(str(json.get("name", "TappedOut Deck")))
	_board(deck, json.get("commander", []), true)
	_board(deck, json.get("commanders", []), true)
	_board(deck, json.get("inventory", json.get("cards", [])), false)
	return deck


static func _board(deck: NormalizedDeck, board: Variant, as_commander: bool) -> void:
	if not (board is Array):
		return
	for item in board:
		if item is Dictionary:
			var n := str(item.get("name", item.get("card", "")))
			var q := int(item.get("qty", item.get("quantity", 1)))
			if as_commander:
				deck.add_commander(n, q)
			else:
				deck.add_main(n, q)
		elif typeof(item) == TYPE_STRING:
			if as_commander:
				deck.add_commander(str(item), 1)
			else:
				deck.add_main(str(item), 1)
