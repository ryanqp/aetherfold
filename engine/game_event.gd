class_name GameEvent
extends RefCounted

var seq: int = 0
var type: int = 0
var player_id: int = 0
var object_ids: Array[int] = []
var stack_ids: Array[int] = []
var payload: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		seq = seq,
		type = type,
		player_id = player_id,
		object_ids = object_ids,
		stack_ids = stack_ids,
		payload = payload,
	}
