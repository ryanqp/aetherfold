extends Node

## Match and menu selections. Lives for the whole app.

var player_deck_id: String = "builtin:krenko"
var rival_deck_id: String = "builtin:talrand"
var difficulty: int = 1
var mp_role: String = ""
var mp_code: String = ""
var skip_ai: bool = false
var you_seat: int = 0


func reset_match_flags() -> void:
	mp_role = ""
	mp_code = ""
	skip_ai = false
	you_seat = 0


func is_mp() -> bool:
	return mp_role == "host" or mp_role == "client"


func is_mp_client() -> bool:
	return mp_role == "client"


func make_demo():
	return DeckCatalog.vs_pair(player_deck_id, rival_deck_id)
