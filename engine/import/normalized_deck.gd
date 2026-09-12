class_name NormalizedDeck
extends RefCounted

var name: String = "Imported Deck"
var source: String = "text"
var source_url: String = ""
var commanders: Array = []
var mainboard: Array = []


func add_commander(card_name: String, quantity: int = 1) -> void:
	_add_to(commanders, card_name, quantity)


func add_main(card_name: String, quantity: int = 1) -> void:
	_add_to(mainboard, card_name, quantity)


func commander_names() -> PackedStringArray:
	var out := PackedStringArray()
	for e in commanders:
		out.append(str(e.get("name", "")))
	return out


func unique_names() -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for e in commanders:
		var n := str(e.get("name", ""))
		if n != "" and not seen.has(n):
			seen[n] = true
			out.append(n)
	for e in mainboard:
		var n2 := str(e.get("name", ""))
		if n2 != "" and not seen.has(n2):
			seen[n2] = true
			out.append(n2)
	return out


func total_cards() -> int:
	var n := 0
	for e in commanders:
		n += int(e.get("quantity", 1))
	for e in mainboard:
		n += int(e.get("quantity", 1))
	return n


func library_count() -> int:
	var n := 0
	for e in mainboard:
		n += int(e.get("quantity", 1))
	return n


func to_dict() -> Dictionary:
	return {
		name = name,
		source = source,
		sourceUrl = source_url,
		commander = commanders.duplicate(true),
		mainboard = mainboard.duplicate(true),
	}


static func from_dict(d: Dictionary) -> NormalizedDeck:
	var deck := NormalizedDeck.new()
	deck.name = DeckText.sanitize_name(str(d.get("name", "Imported Deck")))
	deck.source = str(d.get("source", "text"))
	deck.source_url = str(d.get("sourceUrl", d.get("source_url", "")))
	for e in d.get("commander", d.get("commanders", [])):
		if e is Dictionary:
			deck.add_commander(str(e.get("name", "")), int(e.get("quantity", 1)))
	for e2 in d.get("mainboard", []):
		if e2 is Dictionary:
			deck.add_main(str(e2.get("name", "")), int(e2.get("quantity", 1)))
	return deck


func to_deck_list() -> DeckList:
	var list := DeckList.new()
	var ids := PackedStringArray()
	for e in commanders:
		var oid := str(e.get("oracle_id", e.get("cardId", "")))
		if oid == "":
			oid = str(e.get("name", "")).strip_edges().to_lower()
		ids.append(oid)
	list.commander_oracle_ids = ids
	for e2 in mainboard:
		list.library.append({
			name = str(e2.get("name", "")),
			count = int(e2.get("quantity", 1)),
		})
	return list


func stamp_entry(card_name: String, row: Dictionary) -> void:
	for e in commanders:
		if str(e.get("name", "")) == card_name:
			_stamp(e, row)
	for e2 in mainboard:
		if str(e2.get("name", "")) == card_name:
			_stamp(e2, row)


func _stamp(e: Dictionary, row: Dictionary) -> void:
	e["cardId"] = str(row.get("id", e.get("cardId", "")))
	e["oracle_id"] = str(row.get("oracle_id", e.get("oracle_id", "")))
	e["scryfall_id"] = str(row.get("id", e.get("scryfall_id", "")))
	if str(row.get("name", "")) != "":
		e["name"] = str(row.get("name", ""))


func _add_to(arr: Array, card_name: String, quantity: int) -> void:
	var n := DeckText.sanitize_name(card_name)
	if n == "":
		return
	var q := maxi(1, quantity)
	for e in arr:
		if str(e.get("name", "")) == n:
			e["quantity"] = int(e.get("quantity", 1)) + q
			return
	arr.append({name = n, quantity = q})
