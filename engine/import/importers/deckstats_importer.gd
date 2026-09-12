class_name DeckstatsImporter
extends RefCounted


static func api_urls(owner_id: String, deck_id: String) -> PackedStringArray:
	if owner_id.strip_edges() == "" or deck_id.strip_edges() == "":
		return PackedStringArray()
	return PackedStringArray([
		"https://deckstats.net/api.php?action=get_deck&id_type=saved&owner_id=%s&id=%s&response_type=json" % [owner_id, deck_id],
		"https://deckstats.net/api.php?action=get_deck&id_type=saved&owner_id=%s&id=%s&response_type=list" % [owner_id, deck_id],
	])


static func parse_payload(text: String, source_url: String = "") -> NormalizedDeck:
	var t := text.strip_edges()
	if t.begins_with("{") or t.begins_with("["):
		var parsed: Variant = JSON.parse_string(t)
		if parsed is Dictionary:
			return parse_json(parsed, source_url)
	var parser := TextDeckParser.new()
	var deck: NormalizedDeck = parser.parse(t)
	deck.source = "deckstats"
	deck.source_url = source_url
	if deck.name == "Imported Deck":
		deck.name = "Deckstats Deck"
	return deck


static func parse_json(json: Dictionary, source_url: String = "") -> NormalizedDeck:
	var deck := NormalizedDeck.new()
	deck.source = "deckstats"
	deck.source_url = source_url
	deck.name = DeckText.sanitize_name(str(json.get("name", "Deckstats Deck")))
	var sections: Variant = json.get("sections", [])
	if sections is Array:
		for sec in sections:
			if not (sec is Dictionary):
				continue
			var sname := str(sec.get("name", "")).to_lower()
			var cards: Variant = sec.get("cards", [])
			if not (cards is Array):
				continue
			for c in cards:
				if not (c is Dictionary):
					continue
				var n := str(c.get("name", ""))
				var q := int(c.get("amount", c.get("quantity", 1)))
				if bool(c.get("isCommander", false)) or sname.find("commander") >= 0:
					deck.add_commander(n, q)
				elif sname.find("side") >= 0 or sname.find("maybe") >= 0:
					continue
				else:
					deck.add_main(n, q)
	return deck
