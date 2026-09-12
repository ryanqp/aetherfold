class_name GameLog
extends RefCounted

const CAP := 10000

var events: Array[GameEvent] = []
var _seq: int = 0


func append(type: int, player_id: int = 0, payload: Dictionary = {}) -> GameEvent:
	var e := GameEvent.new()
	_seq += 1
	e.seq = _seq
	e.type = type
	e.player_id = player_id
	e.payload = payload
	events.append(e)
	while events.size() > CAP:
		events.remove_at(0)
	return e


func size() -> int:
	return events.size()


func last() -> GameEvent:
	if events.is_empty():
		return GameEvent.new()
	return events[events.size() - 1]


func seq() -> int:
	return _seq


func since(after_seq: int) -> Array:
	var out: Array = []
	for e in events:
		if e.seq > after_seq:
			out.append(e)
	return out
