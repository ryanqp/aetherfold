class_name EdhrecDecks
extends RefCounted
## Imports one real, existing decklist per selected commander from EDHREC.
##
## Flow (no "average deck" is ever generated):
##   1. https://json.edhrec.com/pages/decks/<slug>.json  -> first listed deck (its urlhash)
##   2. https://edhrec.com/api/deckpreview/<urlhash>      -> the deck, with its original Moxfield/Archidekt link
##   3. the existing importers fetch that deck (full list + quantities), Scryfall resolves every card
##   4. the commander's Scryfall image is cached next to the other card images
## Once saved, a deck is never re-picked (the first import pins it); "re-import" refreshes the same deck.

const SOURCE := "edhrec_scryfall_top_100"
const INDEX_URL := "https://json.edhrec.com/pages/decks/%s.json"
const PREVIEW_URL := "https://edhrec.com/api/deckpreview/%s"
const PAGE_URL := "https://edhrec.com/commanders/%s"

const TOKEN_NAMES: Array = ["treasure", "food", "clue", "blood", "map", "powerstone", "gold", "junk", "shard", "incubator"]

const COMMANDERS: Array = [
	{slug = "yshtola-nights-blessed", name = "Y'shtola, Night's Blessed"},
	{slug = "the-ur-dragon", name = "The Ur-Dragon"},
	{slug = "krenko-mob-boss", name = "Krenko, Mob Boss"},
	{slug = "chatterfang-squirrel-general", name = "Chatterfang, Squirrel General"},
	{slug = "kaalia-of-the-vast", name = "Kaalia of the Vast"},
	{slug = "isshin-two-heavens-as-one", name = "Isshin, Two Heavens as One"},
	{slug = "jodah-the-unifier", name = "Jodah, the Unifier"},
	{slug = "miirym-sentinel-wyrm", name = "Miirym, Sentinel Wyrm"},
	{slug = "kinnan-bonder-prodigy", name = "Kinnan, Bonder Prodigy"},
	{slug = "yuriko-the-tigers-shadow", name = "Yuriko, the Tiger's Shadow"},
	{slug = "korvold-fae-cursed-king", name = "Korvold, Fae-Cursed King"},
	{slug = "kenrith-the-returned-king", name = "Kenrith, the Returned King"},
]

## Set by the caller (main thread) so worker threads never touch the scene tree.
var image_dir: String = ""
var allow_network: bool = true
var store: DeckStore = DeckStore.new()


static func source_key(slug: String) -> String:
	return "edhrec:" + slug


static func page_url(slug: String) -> String:
	return PAGE_URL % slug


## Imports every selected commander. `progress` (optional) is called as progress.call(index, total, message).
## Returns {results = [...], imported = n, skipped = n, failed = n}.
func import_all(force: bool = false, progress: Callable = Callable()) -> Dictionary:
	var results: Array = []
	var counts := {imported = 0, skipped = 0, failed = 0}
	for i in COMMANDERS.size():
		var entry: Dictionary = COMMANDERS[i]
		if progress.is_valid():
			progress.call(i, COMMANDERS.size(), "Importing %s..." % str(entry.name))
		var r: Dictionary = import_one(entry, force)
		results.append(r)
		match str(r.get("status", "failed")):
			"imported", "updated":
				counts.imported += 1
			"skipped":
				counts.skipped += 1
			_:
				counts.failed += 1
	counts["results"] = results
	if progress.is_valid():
		progress.call(COMMANDERS.size(), COMMANDERS.size(), "Done: %d imported, %d already saved, %d failed." % [counts.imported, counts.skipped, counts.failed])
	return counts


func import_one(entry: Dictionary, force: bool = false) -> Dictionary:
	var slug := str(entry.get("slug", ""))
	var cmd_name := str(entry.get("name", ""))
	var key := source_key(slug)
	var res := {slug = slug, commander = cmd_name, status = "failed", error = "", unresolved = PackedStringArray(), warnings = PackedStringArray()}
	var existing: Dictionary = store.find_by_source_key(key)
	if not existing.is_empty() and not force and _cached_ok(existing):
		res.status = "skipped"
		res.path = str(existing.get("_path", ""))
		return res
	if not allow_network:
		res.error = "Network disabled."
		return res
	## Pinned deck (re-import refreshes the SAME deck), otherwise the first deck EDHREC lists.
	var urlhash := str(existing.get("edhrec_deck_id", ""))
	if urlhash == "":
		var idx: Dictionary = DeckHttp.get_sync(INDEX_URL % slug, 30000)
		if not bool(idx.get("ok", false)):
			res.error = "EDHREC deck list unavailable (%s)." % str(idx.get("error", ""))
			return res
		urlhash = first_urlhash(str(idx.get("text", "")))
		if urlhash == "":
			res.error = "EDHREC lists no decks for this commander."
			return res
	var prev: Dictionary = DeckHttp.get_sync(PREVIEW_URL % urlhash, 30000)
	if not bool(prev.get("ok", false)):
		res.error = "EDHREC deck %s unavailable (%s)." % [urlhash, str(prev.get("error", ""))]
		return res
	var info: Dictionary = parse_preview(str(prev.get("text", "")))
	var deck: NormalizedDeck = null
	var origin_url := str(info.get("source_url", ""))
	var origin_id := str(info.get("source_deck_id", ""))
	if origin_url != "" and DeckSource.detect(origin_url) != DeckSource.Kind.UNKNOWN:
		var imp: Dictionary = _fetch_origin(origin_url)
		if bool(imp.get("ok", false)):
			deck = imp.get("deck")
	if deck == null:
		## The origin site refused: fall back to the card list EDHREC itself holds for this deck.
		deck = info.get("deck")
		origin_url = "https://edhrec.com/deckpreview/%s" % urlhash
	if deck == null or deck.total_cards() == 0:
		res.error = "Could not read the card list of EDHREC deck %s." % urlhash
		return res
	if deck.commanders.is_empty():
		deck.add_commander(cmd_name, 1)
	deck.name = cmd_name
	deck.source = SOURCE
	deck.source_url = origin_url
	var resolved: Dictionary = ScryfallResolver.new().resolve(deck, true)
	var rows: Dictionary = resolved.get("rows", {})
	var unresolved: PackedStringArray = resolved.get("unresolved", PackedStringArray())
	## Tokens that list sites sometimes include ("Treasure") are not cards: drop them instead of failing the deck.
	var still: PackedStringArray = PackedStringArray()
	for u in unresolved:
		if TOKEN_NAMES.has(str(u).to_lower()):
			deck.remove_main(str(u))
		else:
			still.append(str(u))
	unresolved = still
	res.unresolved = unresolved
	var val: Dictionary = CommanderValidator.new().validate(deck, rows, unresolved)
	var problems := validate_import(deck, rows, unresolved, cmd_name)
	var warns := import_warnings(deck, unresolved)
	var vw := PackedStringArray(val.get("warnings", PackedStringArray()))
	vw.append_array(warns)
	val["warnings"] = vw
	res.warnings = warns
	if not problems.is_empty():
		res.error = "Validation failed: " + "; ".join(problems)
		return res
	var cmd_row: Dictionary = rows.get(deck.commanders[0].get("name", ""), {})
	var art_path := cache_commander_image(cmd_row)
	var meta := {
		source = SOURCE,
		is_imported = true,
		source_key = key,
		source_url = origin_url,
		source_page = page_url(slug),
		source_commander = cmd_name,
		source_deck_id = origin_id,
		edhrec_deck_id = urlhash,
		scryfall_commander_id = str(cmd_row.get("id", "")),
		commander_image = art_path,
		local_id = str(existing.get("local_id", "")) if not existing.is_empty() else "edhrec-%s-%s" % [slug, str(Time.get_unix_time_from_system())],
	}
	var replace_path := str(existing.get("_path", ""))
	if not existing.is_empty():
		meta["id"] = str(existing.get("id", ""))
	var path := store.save(deck, rows, val, replace_path, meta)
	if path == "":
		res.error = "Could not write the deck file."
		return res
	res.status = "updated" if not existing.is_empty() else "imported"
	res.path = path
	res.cards = deck.total_cards()
	res.source_url = origin_url
	res.image = art_path
	return res


func _fetch_origin(url: String) -> Dictionary:
	var pipe := ImportPipeline.new()
	return pipe._fetch_source(DeckSource.detect(url), url)


## A saved deck counts as complete only if its commander art is still cached.
func _cached_ok(rec: Dictionary) -> bool:
	var p := str(rec.get("commander_image", ""))
	return p == "" or FileAccess.file_exists(p)


## First deck in EDHREC's deck-list JSON (`table[0].urlhash`).
static func first_urlhash(json_text: String) -> String:
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return ""
	var table: Variant = (parsed as Dictionary).get("table", [])
	if table is Array:
		for row in table:
			if row is Dictionary and str((row as Dictionary).get("urlhash", "")) != "":
				return str((row as Dictionary).get("urlhash"))
	return ""


## Reads the deck-preview JSON: the original deck link, and EDHREC's own card list as a fallback.
## Defensive on purpose: it only trusts fields it recognises and never invents cards.
static func parse_preview(json_text: String) -> Dictionary:
	var out := {source_url = "", source_deck_id = "", deck = null}
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return out
	var d: Dictionary = parsed
	var url := _find_deck_url(d)
	out.source_url = url
	if url != "":
		var kind := DeckSource.detect(url)
		match kind:
			DeckSource.Kind.ARCHIDEKT:
				out.source_deck_id = DeckSource.extract_archidekt_id(url)
			DeckSource.Kind.MOXFIELD:
				out.source_deck_id = DeckSource.extract_moxfield_id(url)
	var cards: Variant = d.get("cards", d.get("deck", []))
	if cards is Array and not (cards as Array).is_empty():
		var nd := NormalizedDeck.new()
		for c in cards:
			if c is String:
				_add_line(nd, str(c))
			elif c is Dictionary:
				var cd: Dictionary = c
				nd.add_main(str(cd.get("name", "")), int(cd.get("quantity", cd.get("qty", 1))))
		var cmd: Variant = d.get("commanders", d.get("commander", []))
		if cmd is Array:
			for c2 in cmd:
				nd.add_commander(str((c2 as Dictionary).get("name", "")) if c2 is Dictionary else str(c2), 1)
		elif cmd is String and str(cmd) != "":
			nd.add_commander(str(cmd), 1)
		if nd.total_cards() > 0:
			out.deck = nd
	return out


static func _add_line(nd: NormalizedDeck, line: String) -> void:
	var t := line.strip_edges()
	var rx := RegEx.new()
	rx.compile("^(\\d+)\\s*x?\\s+(.+)$")
	var m := rx.search(t)
	if m != null:
		nd.add_main(m.get_string(2), int(m.get_string(1)))
	else:
		nd.add_main(t, 1)


static func _find_deck_url(v: Variant) -> String:
	if v is String:
		var s := str(v)
		var low := s.to_lower()
		if low.begins_with("http") and (low.find("archidekt.com/decks/") >= 0 or low.find("moxfield.com/decks/") >= 0 or low.find("tappedout.net/mtg-decks/") >= 0 or low.find("deckstats.net/decks/") >= 0):
			return s
		return ""
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			var r := _find_deck_url((v as Dictionary)[k])
			if r != "":
				return r
	elif v is Array:
		for e in v:
			var r2 := _find_deck_url(e)
			if r2 != "":
				return r2
	return ""


## Checks before a deck may be marked imported. Returns a list of problems (empty = valid).
static func validate_import(deck: NormalizedDeck, rows: Dictionary, unresolved: PackedStringArray, expected_commander: String) -> PackedStringArray:
	var p := PackedStringArray()
	if deck.commanders.is_empty():
		p.append("no commander")
	else:
		var cn := str(deck.commanders[0].get("name", ""))
		if DeckText.normalize_key(cn) != DeckText.normalize_key(expected_commander) and not rows.has(cn):
			p.append("commander %s does not match %s" % [cn, expected_commander])
		if not rows.has(cn):
			p.append("commander did not resolve through Scryfall")
		else:
			var imgs: Variant = (rows[cn] as Dictionary).get("images", {})
			if not (imgs is Dictionary) or str((imgs as Dictionary).get("normal", "")) == "":
				p.append("commander has no Scryfall image")
	## A few cards Scryfall can't match are kept as warnings; many of them means the list is not readable.
	if unresolved.size() > 5:
		p.append("%d cards failed Scryfall resolution (%s)" % [unresolved.size(), ", ".join(unresolved.slice(0, 5))])
	if deck.total_cards() < 60:
		p.append("deck has only %d cards" % deck.total_cards())
	return p


## Things worth knowing about an imported deck that do not stop it from being saved.
static func import_warnings(deck: NormalizedDeck, unresolved: PackedStringArray) -> PackedStringArray:
	var w := PackedStringArray()
	if unresolved.size() > 0:
		w.append("%d cards not found on Scryfall: %s" % [unresolved.size(), ", ".join(unresolved.slice(0, 8))])
	if deck.total_cards() < 98 or deck.total_cards() > 102:
		w.append("The source list has %d cards (a Commander deck is 100)." % deck.total_cards())
	return w


## Downloads the commander's Scryfall image(s) into the shared card-image cache; returns the "normal" path.
func cache_commander_image(row: Dictionary) -> String:
	var cid := str(row.get("id", ""))
	var imgs: Variant = row.get("images", {})
	if cid == "" or image_dir == "" or not (imgs is Dictionary):
		return ""
	DirAccess.make_dir_recursive_absolute(image_dir)
	var normal_path := ""
	for kind in ["small", "normal"]:
		var url := str((imgs as Dictionary).get(kind, ""))
		var dest := image_dir.path_join("%s_%s.jpg" % [cid, kind])
		if FileAccess.file_exists(dest):
			if kind == "normal":
				normal_path = dest
			continue
		if url == "" or not allow_network:
			continue
		var resp: Dictionary = DeckHttp.get_sync(url, 30000)
		if bool(resp.get("ok", false)) and (resp.get("bytes", PackedByteArray()) as PackedByteArray).size() > 0:
			var f := FileAccess.open(dest, FileAccess.WRITE)
			if f != null:
				f.store_buffer(resp.bytes)
				f.close()
				if kind == "normal":
					normal_path = dest
	return normal_path
