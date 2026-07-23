extends StaticBody2D

# Local position relative to the Ledge node where the player should snap.
# You can tweak this in the Inspector for each Ledge instance!
@export var grab_offset: Vector2 = Vector2.ZERO

## Returns the global coordinate where the player's position should snap
func get_grab_position() -> Vector2:
	return global_position + grab_offset
