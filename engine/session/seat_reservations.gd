class_name SeatReservations
extends RefCounted

## An online guest whose connection dropped keeps their seat for a while (AUDIT-016). The host hands every guest a secret
## token when the match starts; if the guest's line drops, the token holds the seat for `window_ms`, and the guest's game
## presents it again when it reconnects. A token that is wrong or too old gets nothing.
##
## Pure bookkeeping (times are passed in), so it can be tested without a network.

var _held: Dictionary = {}  ## token -> {name, until}


## A random token for a seat: 16 letters and digits.
static func new_token() -> String:
	var alphabet := "abcdefghjkmnpqrstuvwxyz23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in 16:
		out += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return out


func hold(token: String, player_name: String, now_msec: int, window_ms: int) -> void:
	if token == "":
		return
	_held[token] = {name = player_name, until = now_msec + window_ms}


func is_holding(now_msec: int) -> bool:
	for t in _held:
		if int((_held[t] as Dictionary).until) > now_msec:
			return true
	return false


## The seat held for `token`, or {} when there is none or it ran out. A claimed seat is no longer held.
func claim(token: String, now_msec: int) -> Dictionary:
	if token == "" or not _held.has(token):
		return {}
	var entry: Dictionary = _held[token]
	_held.erase(token)
	if int(entry.until) <= now_msec:
		return {}
	return entry


## Seats whose time ran out: returns their players' names and forgets them.
func expire(now_msec: int) -> Array:
	var gone: Array = []
	for t in _held.keys():
		if int((_held[t] as Dictionary).until) <= now_msec:
			gone.append(str((_held[t] as Dictionary).name))
			_held.erase(t)
	return gone


func clear() -> void:
	_held.clear()
