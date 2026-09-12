class_name RngStream
extends RefCounted

## Seeded RNG for the rules kernel. Never call RandomNumberGenerator.randomize().

var rng := RandomNumberGenerator.new()


func setup(p_seed: int) -> void:
	rng.seed = p_seed


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func randf() -> float:
	return rng.randf()


func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)
