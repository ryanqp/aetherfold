class_name Zone
extends RefCounted

var zone_id: int = EngineEnums.ZoneId.LIBRARY
var owner_id: int = 0
var ordered: bool = false
var object_ids: Array[int] = []


func size() -> int:
	return object_ids.size()


func is_empty() -> bool:
	return object_ids.is_empty()


func has(object_id: int) -> bool:
	return object_ids.has(object_id)
