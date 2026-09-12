class_name SubmitResult
extends RefCounted

var ok: bool = true
var error: String = ""
var events: Array = []
var mode: int = 0
var awaiting: Dictionary = {}


func to_dict() -> Dictionary:
	return {ok = ok, error = error, events = events, mode = mode, awaiting = awaiting}
