extends CharacterBody2D

# Configurable movement speeds
const WALK_SPEED = 10.0
const RUN_SPEED = 58.0

# Cutscene control states
var target_x: float = 0.0
var should_move: bool = false
var is_fleeing: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_tree : AnimationTree = $AnimationTree
var state_machine

func _ready() -> void:
	state_machine = animation_tree["parameters/playback"]

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
			if is_fleeing:
				# Set parameter to 1.0 for running
				animation_tree["parameters/walk-run/blend-walk-run/blend_amount"] = 1.0
			else:
				# Set parameter to 0.0 for walking
				animation_tree["parameters/walk-run/blend-walk-run/blend_amount"] = 0.0
			
			velocity.x = direction * speed
			
			# Flip the sprite to face the moving direction
			if sprite:
				sprite.flip_h = (direction < 0)
				
			# Handle animations
			state_machine.travel("walk-run")
		else:
			# Arrived at target
			velocity.x = 0
			should_move = false
			# Handle animations
			state_machine.travel("idle")
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		state_machine.travel("idle")
		# (Optional) Handle animations here if you have them

	# 3. Apply physics movement
	move_and_slide()

# Public method called by the cutscene director
func move_to_position(target_x_coord: float, run_fast: bool = false) -> void:
	target_x = target_x_coord
	is_fleeing = run_fast
	should_move = true


func stop_movement() -> void:
	should_move = false
	is_fleeing = false
	velocity = Vector2.ZERO
