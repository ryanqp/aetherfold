class_name CatalogSource
extends RefCounted

## Printed-card lookup. Engine never requires the Scryfall autoload or D:.

func find_by_name(_n: String) -> Dictionary:
	return {}


func find_by_id(_id: String) -> Dictionary:
	return {}


class Memory extends CatalogSource:
	var by_name: Dictionary = {}
	var by_id: Dictionary = {}

	func add(row: Dictionary) -> void:
		var n := _norm(str(row.get("name", "")))
		var oid := str(row.get("oracle_id", ""))
		var cid := str(row.get("id", ""))
		if n != "":
			by_name[n] = row
		if oid != "":
			by_id[oid] = row
		if cid != "" and cid != oid:
			by_id[cid] = row

	func find_by_name(n: String) -> Dictionary:
		return by_name.get(_norm(n), {})

	func find_by_id(id: String) -> Dictionary:
		return by_id.get(id, {})

	static func _norm(n: String) -> String:
		return n.strip_edges().to_lower()


class ScryfallWrap extends CatalogSource:
	func find_by_name(n: String) -> Dictionary:
		var cat := _cat()
		if cat == null:
			return {}
		if cat.has_method("find_by_name"):
			var row: Variant = cat.find_by_name(n)
			return row if row is Dictionary else {}
		return {}

	func find_by_id(id: String) -> Dictionary:
		var cat := _cat()
		if cat == null:
			return {}
		if cat.has_method("find_by_id"):
			var row: Variant = cat.find_by_id(id)
			return row if row is Dictionary else {}
		return {}

	func _cat() -> Object:
		var loop := Engine.get_main_loop()
		if not (loop is SceneTree):
			return null
		return (loop as SceneTree).root.get_node_or_null("/root/ScryfallCatalog")
