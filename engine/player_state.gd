class_name PlayerState
extends RefCounted

var player_id: int = 0
var name: String = ""
var life: int = 40
var mana = null
var commander_ids: Array[int] = []
var commander_cast_count: Dictionary = {}
var commander_damage_from: Dictionary = {}
var lost: bool = false
var mulligan_count: int = 0
