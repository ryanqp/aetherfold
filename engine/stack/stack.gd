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


func remove_by_stack_id(stack_id: int) -> StackEntry:
	for i in entries.size():
		var e: StackEntry = entries[i]
		if e != null and e.stack_id == stack_id:
			entries.remove_at(i)
			return e
	return null


func resolve_top(engine: RulesEngine) -> void:
	var entry: StackEntry = pop()
	if entry == null or engine == null:
		return
	if engine.executor != null:
		engine.executor.resolve(engine, entry)
	if entry.kind != StackEntry.Kind.SPELL:
		return
	var obj: GameObject = engine.state.objects.get(entry.object_id)
	if obj == null or obj.zone != EngineEnums.ZoneId.STACK:
		return
	var def: CardDefinition = obj.definition as CardDefinition if obj.definition is CardDefinition else null
	if def != null and def.is_permanent_type():
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.BATTLEFIELD)
	else:
		engine.state.zones.move(obj.object_id, EngineEnums.ZoneId.GRAVEYARD, obj.owner_id)


func push_spell(moved: GameObject, player_id: int, targets: Array, next_id: int, source_id: int = 0) -> StackEntry:
	var entry := StackEntry.new()
	entry.stack_id = next_id
	entry.kind = StackEntry.Kind.SPELL
	entry.object_id = moved.object_id if moved != null else 0
	entry.source_id = source_id if source_id != 0 else entry.object_id
	entry.controller_id = player_id
	if moved != null and moved.definition is CardDefinition:
		var def := moved.definition as CardDefinition
		var sp: Ability = def.spell_ability()
		if sp != null:
			entry.ability_id = sp.ability_id
			entry.effects = sp.effects.duplicate()
	entry.targets = targets.duplicate()
	push(entry)
	return entry
