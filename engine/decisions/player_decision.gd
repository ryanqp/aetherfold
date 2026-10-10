class_name PlayerDecision
extends RefCounted

## A question the rules require a player to answer. Resolution or casting waits.
## The engine never fills this in with index 0 or a random legal option.

var decision_id: int = 0
var kind: StringName = &"OPTIONAL_YES_NO"
var player_id: int = 0
var stack_id: int = 0
var link: String = ""
var prompt: String = ""
var min_count: int = 1
var max_count: int = 1
var optional: bool = false
var candidates: Array = []
## DISTRIBUTE decisions: how many points (damage) are to be divided among the candidates. info[str(cand)] holds a label, a detail
## and the `lethal` amount; info["default"] is the automatic split {cand: amount}.
var total: int = 0
## DISTRIBUTE: at most this many candidates may get anything (0 = no limit): "divided among one, two, or three targets".
var max_targets: int = 0

## Text for the choice screen, keyed by str(candidate): {label, detail}.
var info: Dictionary = {}

## Card objects the question is about; the table shows them face up while the player decides.
var show_ids: Array = []
