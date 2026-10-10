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
	## A card is in the deck when its FIRST category is one the deck counts ("includedInDeck"); Maybeboard, Sideboard and
	## "Tokens & Extras" are normally off, but a player's own "Tokens" tag for token makers is on. Names are not guessed.
	var counted := {}
	var premier := {}
	var cat_list: Variant = json.get("categories", [])
	if cat_list is Array:
		for c in cat_list:
			if c is Dictionary:
				var cname := str((c as Dictionary).get("name", "")).to_lower()
				counted[cname] = bool((c as Dictionary).get("includedInDeck", true))
				if bool((c as Dictionary).get("isPremier", false)):
					premier[cname] = true
	for raw in cards:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var cats: Array = []
		var cv: Variant = row.get("categories", [])
		if cv is Array:
			for c in cv:
				cats.append(str(c).to_lower())
		if bool(row.get("companion", false)):
			continue  ## a companion waits outside the 100
		var primary := str(cats[0]) if not cats.is_empty() else ""
		var in_deck := true
		if counted.has(primary):
			in_deck = bool(counted[primary])
		elif primary in ["maybeboard", "sideboard", "considering"]:
			in_deck = false  ## a deck export without a category list
		if not in_deck:
			continue
		var n := _name_of(row)
		var q := int(row.get("quantity", 1))
		var is_cmd := false
		for c3 in cats:
			if str(c3) == "commander" or str(c3) == "commanders" or str(c3) == "partner" or premier.has(str(c3)):
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
