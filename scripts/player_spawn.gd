extends Marker2D
class_name PlayerSpawn

## Assign your Player .tscn scene file here
@export var player_scene: PackedScene

## Optional spawn identifier if you have multiple spawns in a single level
@export var spawn_id: String = "default"

## If true, this spawn point forces the player to move here even if they already exist
@export var force_reposition: bool = false

func _ready() -> void:
	# Add small delay to let SceneManager finished loading nodes
	call_deferred("_handle_player_spawn")

func _handle_player_spawn() -> void:
	var existing_players = get_tree().get_nodes_in_group("player")
	
	if existing_players.is_empty():
		# Scenario 1: Direct scene launch / Load game (No player in scene yet)
		if player_scene:
			var player_instance = player_scene.instantiate() as Node2D
			player_instance.global_position = global_position
			
			# Add player to the scene parent (e.g., the level root or container)
			get_parent().add_child(player_instance)
		else:
			push_warning("PlayerSpawn: No player_scene assigned in Inspector!")
			
	elif force_reposition:
		# Scenario 2: Player exists, but you want to force move them to this spawn point
		var player = existing_players[0] as Node2D
		player.global_position = global_position
