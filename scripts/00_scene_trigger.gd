extends Area2D
class_name SceneTrigger

signal scene_transition_requested(scenes_to_load: Array[PackedScene], scenes_to_unload: Array[PackedScene])

## Packed scenes to instantiate when triggered
@export var scenes_to_load: Array[PackedScene] = []

## Packed scenes (.tscn files) to match and delete from memory when triggered
@export var scenes_to_unload: Array[PackedScene] = []

## Set to true if the trigger should only execute once
@export var trigger_once: bool = true

var _has_triggered: bool = false

func _ready() -> void:
	add_to_group("scene_triggers")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _has_triggered and trigger_once:
		return

	if body.is_in_group("player") or body.name == "Player":
		_has_triggered = true
		set_deferred("monitoring", false)
		scene_transition_requested.emit(scenes_to_load, scenes_to_unload)
