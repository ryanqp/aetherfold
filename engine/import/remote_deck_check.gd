class_name RemoteDeckCheck
extends RefCounted

## A deck record arrives from another computer (an online guest's chosen deck). It is untrusted input: this refuses anything
## that is not shaped like a deck or is absurdly large, before the game reads it. Whether the deck is a *legal* Commander
## deck is a separate question (CommanderValidator); this only keeps a hostile or broken client from sending junk.

const MAX_JSON_BYTES := 600000
const MAX_NAME := 80
const MAX_ENTRIES := 150
const MAX_COPIES := 99
const MAX_TEXT := 3000
const MAX_FACES := 4


## "" when the record is acceptable, else a short reason to show the host.
static func problem(rec: Variant) -> String:
	if not (rec is Dictionary):
		return "no deck was sent"
	var d: Dictionary = rec
	if d.is_empty():
		return ""  ## nothing chosen yet
	if JSON.stringify(d).length() > MAX_JSON_BYTES:
		return "the deck data is too large"
	if str(d.get("name", "")).length() > MAX_NAME:
		return "the deck name is too long"
	var total := 0
	for key in ["commander", "mainboard"]:
		var entries: Variant = d.get(key, [])
		if not (entries is Array) or (entries as Array).size() > MAX_ENTRIES:
			return "%s list is malformed or too long" % key
		for e in entries:
			if not (e is Dictionary):
				return "%s has a bad entry" % key
			var q := int((e as Dictionary).get("quantity", 1))
			if q < 1 or q > MAX_COPIES or str((e as Dictionary).get("name", "")).length() > MAX_NAME:
				return "%s has a bad entry" % key
			total += q
	if total > 140:
		return "the deck has too many cards"
	if (d.get("commander", []) as Array).size() > 2:
		return "more than two commanders"
	var cards: Variant = d.get("cards", {})
	if not (cards is Dictionary) or (cards as Dictionary).size() > MAX_ENTRIES + 10:
		return "the card rows are malformed or too many"
	for k in (cards as Dictionary).keys():
		var row: Variant = (cards as Dictionary)[k]
		if not (row is Dictionary):
			return "a card row is malformed"
		if str((row as Dictionary).get("oracle_text", "")).length() > MAX_TEXT:
			return "a card's text is too long"
		var faces: Variant = (row as Dictionary).get("faces", [])
		if not (faces is Array) or (faces as Array).size() > MAX_FACES:
			return "a card has too many faces"
	return ""
