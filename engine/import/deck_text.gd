class_name DeckText
extends RefCounted


static func sanitize_name(raw: String) -> String:
	var s := raw.strip_edges()
	s = s.replace("\u0000", "")
	s = s.replace("<", "")
	s = s.replace(">", "")
	if s.length() > 200:
		s = s.substr(0, 200)
	return s


static func normalize_key(raw: String) -> String:
	return sanitize_name(raw).to_lower()
