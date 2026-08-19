@tool
extends StaticBody2D

enum LedgeSide {
	CUSTOM,
	LEFT,
	RIGHT
}

## Select whether this ledge is for a left side, right side, or custom position.
@export_enum("Custom", "Left", "Right") var ledge_side: int = LedgeSide.CUSTOM:
	set(value):
		ledge_side = value
		_update_offset()
		notify_property_list_changed() # Updates the Inspector UI state immediately

# Local position relative to the Ledge node where the player should snap.
@export var grab_offset: Vector2 = Vector2.ZERO

func _update_offset() -> void:
	match ledge_side:
		LedgeSide.LEFT:
			grab_offset = Vector2(-4, 1)
		LedgeSide.RIGHT:
			grab_offset = Vector2(4, 1)
		LedgeSide.CUSTOM:
			pass

# Dynamically changes grab_offset to read-only unless CUSTOM is selected
func _validate_property(property: Dictionary) -> void:
	if property.name == "grab_offset" and ledge_side != LedgeSide.CUSTOM:
		property.usage |= PROPERTY_USAGE_READ_ONLY

## Returns the global coordinate where the player's position should snap
func get_grab_position() -> Vector2:
	return global_position + grab_offset
