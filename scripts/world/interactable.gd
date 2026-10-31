class_name Interactable
extends Node3D
## Anything the operative can use with the interact key. Echoes can also trigger an
## interactable when `echo_compatible` is set: the recorded "interact" event carries `interact_id`
## and the Echo calls interact() on the matching node when it replays near it.

@export var interact_id := ""
@export var prompt := "Use"
@export var echo_compatible := false
@export var interact_range := 2.8

var enabled := true
var level: LevelBase

func _ready() -> void:
	add_to_group("interactable")

func can_interact(_who: Node) -> bool:
	return enabled

func prompt_text() -> String:
	return "[%s]  %s" % [Prefs.binding_text("interact"), prompt]

func interact(_who: Node) -> void:
	pass
