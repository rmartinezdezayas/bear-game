extends CharacterBody2D

# Configurable movement speeds
const WALK_SPEED = 10.0
const RUN_SPEED = 40.0

# Cutscene control states
var target_x: float = 0.0
var should_move: bool = false
var is_fleeing: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer # Or AnimationTree/Sprite2D depending on your project

func _physics_process(delta: float) -> void:
	# 1. Apply gravity if not on the floor
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. Horizontal Movement Logic
	if should_move:
		var current_x = global_position.x
		
		# Determine direction to target
		if abs(current_x - target_x) > 5.0: # Prevent jittering when close to target
			var direction = 1.0 if target_x > current_x else -1.0
			var speed = RUN_SPEED if is_fleeing else WALK_SPEED
			
			velocity.x = direction * speed
			
			# Flip the sprite to face the moving direction
			if sprite:
				sprite.flip_h = (direction < 0)
				
			# (Optional) Handle animations here if you have them
		else:
			# Arrived at target
			velocity.x = 0
			should_move = false
			# (Optional) Handle animations here if you have them
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		# (Optional) Handle animations here if you have them

	# 3. Apply physics movement
	move_and_slide()

# Public method called by the cutscene director
func move_to_position(target_x_coord: float, run_fast: bool = false) -> void:
	target_x = target_x_coord
	is_fleeing = run_fast
	should_move = true
