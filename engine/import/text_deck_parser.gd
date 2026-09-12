class_name TextDeckParser
extends RefCounted

const SIDE_SECTIONS := ["sideboard", "maybeboard", "maybe", "considering", "wishlist", "tokens"]
const CMD_SECTIONS := ["commander", "commanders", "command zone", "partner"]
const MAIN_SECTIONS := ["mainboard", "main", "deck", "library", "about"]


func parse(raw: String) -> NormalizedDeck:
	var deck := NormalizedDeck.new()
	deck.source = "text"
	var section := "main"
	var pending_name := ""
	for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var s := str(line).strip_edges()
		if s.is_empty():
			continue
		if s.begins_with("#") or s.begins_with("//"):
			continue
		if s.to_lower().begins_with("about"):
			continue
		var header := _section(s)
		if header != "":
			section = header
			continue
		if s.to_lower().begins_with("sb:"):
			section = "sideboard"
			s = s.substr(3).strip_edges()
		var parsed: Dictionary = _card_line(s)
		if parsed.is_empty():
			continue
		if section in SIDE_SECTIONS:
			continue
		var n := str(parsed.get("name", ""))
		var q := int(parsed.get("quantity", 1))
		if section in CMD_SECTIONS or n.to_lower().begins_with("commander:"):
			if n.to_lower().begins_with("commander:"):
				n = n.substr(10).strip_edges()
			deck.add_commander(n, q)
		else:
			deck.add_main(n, q)
		pending_name = n
	if deck.name == "Imported Deck" and pending_name != "":
		deck.name = "Imported Deck"
	return deck


func _section(line: String) -> String:
	var s := line.strip_edges()
	if s.ends_with(":"):
		s = s.substr(0, s.length() - 1)
	s = s.to_lower()
	if s in CMD_SECTIONS:
		return "commander"
	if s in SIDE_SECTIONS:
		return "sideboard"
	if s in MAIN_SECTIONS:
		return "main"
	return ""


func _card_line(line: String) -> Dictionary:
	var s := line.strip_edges()
	if s.begins_with("- "):
		s = s.substr(2).strip_edges()
	var qty := 1
	var rest := s
	var re := RegEx.new()
	re.compile("^(\\d+)\\s*[xX]?\\s+(.+)$")
	var m := re.search(s)
	if m:
		qty = int(m.get_string(1))
		rest = m.get_string(2).strip_edges()
	rest = _strip_set(rest)
	rest = DeckText.sanitize_name(rest)
	if rest == "" or rest.to_lower() == "deck" or rest.to_lower() == "sideboard":
		return {}
	if qty < 1:
		qty = 1
	if qty > 99:
		qty = 99
	return {name = rest, quantity = qty}


func _strip_set(name: String) -> String:
	var s := name.strip_edges()
	var cut := s.find(" (")
	if cut > 0:
		s = s.substr(0, cut)
	s = s.replace("*F*", "").replace("*f*", "")
	return s.strip_edges()
