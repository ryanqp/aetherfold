class_name ArchidektImporter
extends RefCounted


static func api_urls(deck_id: String) -> PackedStringArray:
	var id := deck_id.strip_edges()
	if id == "":
		return PackedStringArray()
	return PackedStringArray([
		"https://archidekt.com/api/decks/%s/" % id,
		"https://archidekt.com/api/decks/%s" % id,
	])


static func parse(json: Dictionary, source_url: String = "") -> NormalizedDeck:
	var deck := NormalizedDeck.new()
	deck.source = "archidekt"
	deck.source_url = source_url
	deck.name = DeckText.sanitize_name(str(json.get("name", "Archidekt Deck")))
	var cards: Variant = json.get("cards", [])
	if not (cards is Array):
		return deck
	for raw in cards:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var cats: Array = []
		var cv: Variant = row.get("categories", [])
		if cv is Array:
			for c in cv:
				cats.append(str(c).to_lower())
		var skip := false
		for c2 in cats:
			if str(c2) in ["maybeboard", "sideboard", "considering", "tokens"]:
				skip = true
		if skip:
			continue
		var n := _name_of(row)
		var q := int(row.get("quantity", 1))
		var is_cmd := false
		for c3 in cats:
			if str(c3) == "commander" or str(c3) == "commanders" or str(c3) == "partner":
				is_cmd = true
		if is_cmd:
			deck.add_commander(n, q)
		else:
			deck.add_main(n, q)
	return deck


static func _name_of(row: Dictionary) -> String:
	var card: Variant = row.get("card", {})
	if card is Dictionary:
		var oc: Variant = (card as Dictionary).get("oracleCard", {})
		if oc is Dictionary:
			var n := str((oc as Dictionary).get("name", ""))
			if n != "":
				return DeckText.sanitize_name(n)
		var n2 := str((card as Dictionary).get("name", ""))
		if n2 != "":
			return DeckText.sanitize_name(n2)
	return DeckText.sanitize_name(str(row.get("name", "")))
