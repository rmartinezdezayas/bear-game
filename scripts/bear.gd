extends CharacterBody2D

# Configurable movement speeds
const WALK_SPEED = 10.0
const RUN_SPEED = 60.0
const SPEED_VARIATION_RANGE = 5.0 # Max speed drop (55.0 to 60.0)

# Speed randomization control
var current_run_speed: float = RUN_SPEED
var target_run_speed: float = RUN_SPEED
var speed_change_timer: float = 0.0
var speed_change_interval: float = 0.3 # How often (in seconds) the speed target shifts

# Cutscene control states
var target_x: float = 0.0
var should_move: bool = false
var is_fleeing: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_tree : AnimationTree = $AnimationTree
var state_machine

func _ready() -> void:
	state_machine = animation_tree["parameters/playback"]
	# Seed the random number generator
	randomize()

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
			var speed: float
			
			if is_fleeing:
				# Update timer to pick a new speed periodically
				speed_change_timer -= delta
				if speed_change_timer <= 0.0:
					speed_change_timer = randf_range(0.2, 0.5) # Pick a new interval
					target_run_speed = randf_range(RUN_SPEED - SPEED_VARIATION_RANGE, RUN_SPEED)
				
				# Smoothly transition to the target speed so acceleration looks natural
				current_run_speed = move_toward(current_run_speed, target_run_speed, 15.0 * delta)
				speed = current_run_speed
				
				# Set parameter to 1.0 for running
				animation_tree["parameters/walk-run/blend-walk-run/blend_amount"] = 1.0
			else:
				speed = WALK_SPEED
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
			state_machine.travel("idle")
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		state_machine.travel("idle")

	# 3. Apply physics movement
	move_and_slide()

# Public method called by the cutscene director
func move_to_position(target_x_coord: float, run_fast: bool = false) -> void:
	target_x = target_x_coord
	is_fleeing = run_fast
	should_move = true
	# Reset run speed back to base when starting a new run
	current_run_speed = RUN_SPEED
	target_run_speed = RUN_SPEED
	speed_change_timer = 0.0

func stop_movement() -> void:
	should_move = false
	is_fleeing = false
	velocity = Vector2.ZERO
