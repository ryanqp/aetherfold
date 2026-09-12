class_name DeckSource
extends RefCounted

enum Kind {
	UNKNOWN,
	MOXFIELD,
	ARCHIDEKT,
	TAPPEDOUT,
	DECKSTATS,
	TEXT,
}

const UNSUPPORTED := "Unsupported deck source. Try Moxfield, Archidekt, TappedOut, Deckstats, or paste a decklist."


static func detect(raw: String) -> int:
	var t := raw.strip_edges()
	if t == "":
		return Kind.UNKNOWN
	var low := t.to_lower()
	if low.find("moxfield.com") >= 0:
		return Kind.MOXFIELD
	if low.find("archidekt.com") >= 0:
		return Kind.ARCHIDEKT
	if low.find("tappedout.net") >= 0:
		return Kind.TAPPEDOUT
	if low.find("deckstats.net") >= 0:
		return Kind.DECKSTATS
	if _looks_like_url(low):
		return Kind.UNKNOWN
	return Kind.TEXT


static func kind_name(kind: int) -> String:
	match kind:
		Kind.MOXFIELD:
			return "moxfield"
		Kind.ARCHIDEKT:
			return "archidekt"
		Kind.TAPPEDOUT:
			return "tappedout"
		Kind.DECKSTATS:
			return "deckstats"
		Kind.TEXT:
			return "text"
		_:
			return "unknown"


static func extract_moxfield_id(url: String) -> String:
	var parts := _path_parts(url)
	var i := parts.find("decks")
	if i >= 0 and i + 1 < parts.size():
		return parts[i + 1].split("?")[0].split("#")[0]
	return ""


static func extract_archidekt_id(url: String) -> String:
	var parts := _path_parts(url)
	var i := parts.find("decks")
	if i >= 0 and i + 1 < parts.size():
		var raw := parts[i + 1].split("?")[0]
		var id := ""
		for ch in raw:
			if ch >= "0" and ch <= "9":
				id += ch
			elif id != "":
				break
		return id
	return ""


static func extract_tappedout_slug(url: String) -> String:
	var parts := _path_parts(url)
	var i := parts.find("mtg-decks")
	if i >= 0 and i + 1 < parts.size():
		return parts[i + 1].split("?")[0].split("#")[0]
	return ""


static func extract_deckstats_ids(url: String) -> PackedStringArray:
	var parts := _path_parts(url)
	var i := parts.find("decks")
	if i >= 0 and i + 2 < parts.size():
		var owner := parts[i + 1]
		var rest := parts[i + 2].split("?")[0]
		var deck_id := rest.split("-")[0]
		return PackedStringArray([owner, deck_id])
	return PackedStringArray()


static func _looks_like_url(low: String) -> bool:
	return low.begins_with("http://") or low.begins_with("https://") or low.begins_with("www.")


static func _path_parts(url: String) -> PackedStringArray:
	var u := url.strip_edges().replace("\\", "/")
	u = u.replace("https://", "").replace("http://", "")
	var slash := u.split("/")
	var out := PackedStringArray()
	for p in slash:
		var s := str(p).strip_edges()
		if s != "":
			out.append(s)
	return out
