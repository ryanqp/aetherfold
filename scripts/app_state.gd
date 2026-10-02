extends Node

## Match and menu selections. Lives for the whole app.

const PROFILE_FILE := "user://player.cfg"

var player_deck_id: String = "builtin:krenko"
var rival_deck_id: String = "builtin:talrand"
## Online matches: the full deck records of both players (the host builds the game from these), and their names.
var player_rec: Dictionary = {}
var rival_rec: Dictionary = {}
var rival_name: String = ""
var player_name: String = ""
var mp_role: String = ""
var mp_code: String = ""
var skip_ai: bool = false
var you_seat: int = 0
var sfx_muted: bool = false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_FILE) == OK:
		player_name = str(cfg.get_value("player", "name", ""))
	if player_name.strip_edges() == "":
		player_name = OS.get_environment("USERNAME").strip_edges()
	if player_name == "":
		player_name = "Planeswalker"


func set_player_name(n: String) -> void:
	player_name = n.strip_edges().substr(0, 20)
	if player_name == "":
		player_name = "Planeswalker"
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.save(PROFILE_FILE)


func reset_match_flags() -> void:
	mp_role = ""
	mp_code = ""
	skip_ai = false
	you_seat = 0
	player_rec = {}
	rival_rec = {}
	rival_name = ""


func is_mp() -> bool:
	return mp_role == "host" or mp_role == "client"


func is_mp_client() -> bool:
	return mp_role == "client"


func make_demo():
	## An online match is built from the two players' own decks (the guest's deck was sent to the host).
	if mp_role == "host" and not player_rec.is_empty() and not rival_rec.is_empty():
		return DeckCatalog.vs_pair_recs(player_rec, rival_rec, player_name, rival_name)
	return DeckCatalog.vs_pair(player_deck_id, rival_deck_id)
