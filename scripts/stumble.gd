extends Area2D

func _ready() -> void:
	# Connect the body_entered signal via code (or connect it in the Godot inspector)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# Check if the colliding body is the player and has the stumble function
	if body.has_method("stumble"):
		body.stumble()
