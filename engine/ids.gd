class_name EngineIds
extends RefCounted

## Runtime identity is int. 0 means none.

const NONE := 0

static func is_none(id: int) -> bool:
	return id == NONE


static func is_valid(id: int) -> bool:
	return id > NONE
