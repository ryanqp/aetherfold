class_name MoxfieldImporter
extends RefCounted



static func api_urls(public_id: String) -> PackedStringArray:
	var id := public_id.strip_edges()
	if id == "":
		return PackedStringArray()
	return PackedStringArray([
		"https://api2.moxfield.com/v3/decks/all/%s" % id,
		"https://api2.moxfield.com/v2/decks/all/%s" % id,
		"https://api.moxfield.com/v2/decks/all/%s" % id,
	])


static func parse(json: Dictionary, source_url: String = "") -> NormalizedDeck:
	# One board ingest pass; v2 dict and v3 boards are alternatives.
	var deck := NormalizedDeck.new()
	deck.source = "moxfield"
	deck.source_url = source_url
	deck.name = DeckText.sanitize_name(str(json.get("name", json.get("displayName", "Moxfield Deck"))))
	_ingest_board(deck, json.get("commanders", null), true)
	_ingest_board(deck, json.get("mainboard", null), false)
	if deck.total_cards() == 0:
		var boards: Variant = json.get("boards", {})
		if boards is Dictionary:
			_ingest_board(deck, (boards as Dictionary).get("commanders", {}), true)
			_ingest_board(deck, (boards as Dictionary).get("mainboard", {}), false)
	if json.has("cards") and json.get("cards") is Array:
		for c in json.get("cards"):
			if not (c is Dictionary):
				continue
			var board := str(c.get("board", "mainboard")).to_lower()
			if board == "sideboard" or board == "maybeboard" or board == "tokens":
				continue
			var n := _card_name(c)
			var q := int(c.get("quantity", 1))
			if board == "commanders" or board == "commander":
				deck.add_commander(n, q)
			else:
				deck.add_main(n, q)
	return deck


static func _ingest_board(deck: NormalizedDeck, board: Variant, as_commander: bool) -> void:
	if board is Dictionary:
		var b: Dictionary = board
		# v3 wraps each board as { "count": N, "cards": { id: entry } }
		if b.has("cards") and (b.get("cards") is Dictionary or b.get("cards") is Array):
			_ingest_board(deck, b.get("cards"), as_commander)
			return
		for k in b.keys():
			var v: Variant = b[k]
			if v is Dictionary:
				var n := _card_name(v)
				if n == "":
					var key := str(k)
					if key == "cards" or key == "count" or key == "board":
						continue
					n = key
				if n == "":
					continue
				var q := int(v.get("quantity", v.get("count", 1)))
				if as_commander:
					deck.add_commander(n, q)
				else:
					deck.add_main(n, q)
	elif board is Array:
		for v2 in board:
			if not (v2 is Dictionary):
				continue
			var n2 := _card_name(v2)
			var q2 := int(v2.get("quantity", 1))
			if as_commander:
				deck.add_commander(n2, q2)
			else:
				deck.add_main(n2, q2)


static func _card_name(entry: Dictionary) -> String:
	if entry.has("card") and entry.get("card") is Dictionary:
		var c: Dictionary = entry.get("card")
		var n := str(c.get("name", c.get("cardName", "")))
		if n != "":
			return DeckText.sanitize_name(n)
	var n2 := str(entry.get("name", entry.get("cardName", "")))
	return DeckText.sanitize_name(n2)
