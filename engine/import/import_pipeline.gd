class_name ImportPipeline
extends RefCounted


func run(input: String, allow_network: bool = true) -> Dictionary:
	var raw := input.strip_edges()
	var result := {
		ok = false,
		error = "",
		progress = PackedStringArray(),
		kind = DeckSource.Kind.UNKNOWN,
		deck = null,
		rows = {},
		unresolved = PackedStringArray(),
		validation = {},
	}
	if raw == "":
		result.error = "Paste a deck URL or decklist first."
		return result
	_note(result, "Detecting deck source...")
	var kind: int = DeckSource.detect(raw)
	result.kind = kind
	if kind == DeckSource.Kind.UNKNOWN and DeckSource._looks_like_url(raw.to_lower()):
		result.error = DeckSource.UNSUPPORTED
		return result
	var deck: NormalizedDeck = null
	if kind == DeckSource.Kind.TEXT or kind == DeckSource.Kind.UNKNOWN:
		_note(result, "Parsing decklist...")
		var parser := TextDeckParser.new()
		deck = parser.parse(raw)
		deck.source = "text"
	elif allow_network:
		_note(result, "Fetching deck...")
		var fetched: Dictionary = _fetch_source(kind, raw)
		if not bool(fetched.get("ok", false)):
			result.error = str(fetched.get("error", "Unable to retrieve this deck."))
			return result
		_note(result, "Parsing deck...")
		deck = fetched.get("deck")
	else:
		result.error = "Network fetch is disabled."
		return result
	if deck == null or deck.total_cards() == 0:
		result.error = "No cards found in that deck."
		return result
	result.deck = deck
	_note(result, "Resolving cards...")
	var resolver := ScryfallResolver.new()
	var resolved: Dictionary = resolver.resolve(deck, allow_network)
	result.rows = resolved.get("rows", {})
	result.unresolved = resolved.get("unresolved", PackedStringArray())
	_note(result, "Resolved %d / %d unique cards..." % [result.rows.size(), deck.unique_names().size()])
	_note(result, "Validating Commander rules...")
	var validator := CommanderValidator.new()
	result.validation = validator.validate(deck, result.rows, result.unresolved)
	result.ok = true
	_note(result, "Import complete.")
	return result


func _fetch_source(kind: int, url: String) -> Dictionary:
	match kind:
		DeckSource.Kind.MOXFIELD:
			return _fetch_urls(MoxfieldImporter.api_urls(DeckSource.extract_moxfield_id(url)), Callable(self, "_parse_moxfield").bind(url), "Unable to retrieve this Moxfield deck.\nDeck may be private, deleted, or temporarily unavailable.")
		DeckSource.Kind.ARCHIDEKT:
			return _fetch_urls(ArchidektImporter.api_urls(DeckSource.extract_archidekt_id(url)), Callable(self, "_parse_archidekt").bind(url), "Unable to retrieve this Archidekt deck.\nDeck may be private, deleted, or temporarily unavailable.")
		DeckSource.Kind.TAPPEDOUT:
			return _fetch_urls(TappedOutImporter.api_urls(DeckSource.extract_tappedout_slug(url)), Callable(self, "_parse_tappedout").bind(url), "Unable to retrieve this TappedOut deck.\nDeck may be private, deleted, or temporarily unavailable.")
		DeckSource.Kind.DECKSTATS:
			var ids := DeckSource.extract_deckstats_ids(url)
			var owner := ids[0] if ids.size() > 0 else ""
			var did := ids[1] if ids.size() > 1 else ""
			return _fetch_urls(DeckstatsImporter.api_urls(owner, did), Callable(self, "_parse_deckstats").bind(url), "Unable to retrieve this Deckstats deck.\nDeck may be private, deleted, or temporarily unavailable.")
		_:
			return {ok = false, error = DeckSource.UNSUPPORTED}


func _parse_moxfield(text: String, _u: String, source_url: String) -> NormalizedDeck:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return MoxfieldImporter.parse(parsed, source_url)


func _parse_archidekt(text: String, _u: String, source_url: String) -> NormalizedDeck:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return ArchidektImporter.parse(parsed, source_url)


func _parse_tappedout(text: String, _u: String, source_url: String) -> NormalizedDeck:
	return TappedOutImporter.parse_payload(text, source_url)


func _parse_deckstats(text: String, _u: String, source_url: String) -> NormalizedDeck:
	return DeckstatsImporter.parse_payload(text, source_url)


func _fetch_urls(urls: PackedStringArray, parse_cb: Callable, fail_msg: String) -> Dictionary:
	if urls.is_empty():
		return {ok = false, error = fail_msg}
	var last_err := fail_msg
	for u in urls:
		var resp: Dictionary = DeckHttp.get_sync(u, 25000)
		if not bool(resp.get("ok", false)):
			last_err = str(resp.get("error", fail_msg))
			if last_err.find("private") < 0:
				last_err = fail_msg
			continue
		var deck = parse_cb.call(str(resp.get("text", "")), u)
		if deck is NormalizedDeck and (deck as NormalizedDeck).total_cards() > 0:
			return {ok = true, deck = deck}
	return {ok = false, error = last_err}


func _note(result: Dictionary, msg: String) -> void:
	var p: PackedStringArray = result.get("progress", PackedStringArray())
	p.append(msg)
	result.progress = p
