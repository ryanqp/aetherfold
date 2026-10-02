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

## Text for the choice screen, keyed by str(candidate): {label, detail}.
var info: Dictionary = {}

## Card objects the question is about; the table shows them face up while the player decides.
var show_ids: Array = []
