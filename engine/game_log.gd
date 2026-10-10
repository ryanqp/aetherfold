class_name GameLog
extends RefCounted

## The newest `CAP` events are kept. Trimming happens in chunks of `TRIM_SLACK`, so appending is O(1) on average
## instead of shifting ten thousand entries each time (AUDIT-036).
const CAP := 10000
const TRIM_SLACK := 1000

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
	if events.size() > CAP + TRIM_SLACK:
		events = events.slice(events.size() - CAP)
	return e


func size() -> int:
	return events.size()


func last() -> GameEvent:
	if events.is_empty():
		return GameEvent.new()
	return events[events.size() - 1]


func seq() -> int:
	return _seq


## Events after `after_seq`, oldest first. Found by binary search: the events are in order of `seq`.
func since(after_seq: int) -> Array:
	var lo := 0
	var hi := events.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if events[mid].seq > after_seq:
			hi = mid
		else:
			lo = mid + 1
	return events.slice(lo)
