extends Node
class_name SceneManager

@export var current_level_container: Node2D

func _ready() -> void:
	_connect_existing_triggers()

func _connect_existing_triggers() -> void:
	for trigger in get_tree().get_nodes_in_group("scene_triggers"):
		_connect_trigger(trigger)

func _connect_trigger(trigger: Node) -> void:
	if trigger.has_signal("scene_transition_requested"):
		if not trigger.scene_transition_requested.is_connected(_on_scene_transition_requested):
			trigger.scene_transition_requested.connect(_on_scene_transition_requested)

func _on_scene_transition_requested(scenes_to_load: Array[PackedScene], scenes_to_unload: Array[PackedScene]) -> void:
	change_scenes(scenes_to_load, scenes_to_unload)

## Public function to load/unload scenes by PackedScene resources
func change_scenes(scenes_to_load: Array[PackedScene], scenes_to_unload: Array[PackedScene] = []) -> void:
	var container = current_level_container if current_level_container else self

	# 1. Collect resource paths to unload
	var paths_to_delete: Array[String] = []
	for packed in scenes_to_unload:
		if packed and packed.resource_path != "":
			paths_to_delete.append(packed.resource_path)

	# 2. Check container AND root tree for matching nodes to delete
	if paths_to_delete.size() > 0:
		_unload_matching_nodes(container, paths_to_delete)
		# Also check scene root in case Level 01 was placed directly in the main scene
		_unload_matching_nodes(get_tree().root, paths_to_delete)

	# 3. Instantiate and add new scenes
	for packed_scene in scenes_to_load:
		if packed_scene:
			var new_scene_instance = packed_scene.instantiate()
			container.call_deferred("add_child", new_scene_instance)
			
			# Wait for node to enter tree before scanning for new triggers
			await new_scene_instance.tree_entered
			_connect_triggers_in_node(new_scene_instance)

func _unload_matching_nodes(parent_node: Node, paths_to_delete: Array[String]) -> void:
	for child in parent_node.get_children():
		# Match either scene_file_path OR filename match if file_path is empty
		if child.scene_file_path in paths_to_delete:
			child.queue_free()

func _connect_triggers_in_node(node: Node) -> void:
	if node.is_in_group("scene_triggers"):
		_connect_trigger(node)
	for child in node.get_children():
		_connect_triggers_in_node(child)
