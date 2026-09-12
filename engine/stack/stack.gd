class_name MagicStack
extends RefCounted

var entries: Array = []


func size() -> int:
	return entries.size()


func is_empty() -> bool:
	return entries.is_empty()


func top() -> StackEntry:
	if entries.is_empty():
		return null
	return entries[entries.size() - 1]


func push(entry: StackEntry) -> void:
	entries.append(entry)


func pop() -> StackEntry:
	if entries.is_empty():
		return null
	return entries.pop_back()
