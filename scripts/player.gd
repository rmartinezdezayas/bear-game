extends CharacterBody2D

const SPEED = 50.0
const JUMP_VELOCITY = -200.0
const CROUCH_VELOCITY_MULTIPLIER = 0.5
const MAX_JUMP_HOLD_TIME = 0.16
const JUMP_HOLD_FORCE = 110.0
const JUMP_GRAVITY_MULTIPLIER = 1
const FALL_GRAVITY_MULTIPLIER = 0.45

@onready var animation_tree : AnimationTree = $AnimationTree
var state_machine

# Virtual inputs for cutscene simulation
var simulated_left: bool = false
var simulated_right: bool = false
var simulated_crouch: bool = false
var input_enabled: bool = true
var jump_hold_timer: float = 0.0
var jump_is_held: bool = false

func _ready() -> void:
	state_machine = animation_tree["parameters/playback"]

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		var gravity_multiplier = FALL_GRAVITY_MULTIPLIER if velocity.y >= 0.0 else JUMP_GRAVITY_MULTIPLIER
		velocity += get_gravity() * delta * gravity_multiplier

	# Determine if we are crouched (either from real input or simulated)
	var is_crouching = (Input.is_action_pressed("crouch") if input_enabled else simulated_crouch)

	# Get the input direction based on control state
	var direction := 0.0
	if input_enabled:
		direction = Input.get_axis("left", "right")
	else:
		# Calculate simulated axis (-1, 0, or 1)
		if simulated_left:
			direction -= 1.0
		if simulated_right:
			direction += 1.0

	# Handle jump (Only allow if input is enabled)
	if input_enabled:
		if is_on_floor():
			jump_hold_timer = 0.0
			jump_is_held = false

		if is_on_floor() and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			jump_is_held = true
			jump_hold_timer = 0.0
		elif jump_is_held and Input.is_action_pressed("jump") and velocity.y < 0.0:
			if jump_hold_timer < MAX_JUMP_HOLD_TIME:
				velocity.y -= JUMP_HOLD_FORCE * delta
				jump_hold_timer += delta
			else:
				jump_is_held = false
		elif Input.is_action_just_released("jump"):
			jump_is_held = false
			if velocity.y < 0.0:
				velocity.y *= 0.6

	# Use the crouch multiplier when crouched
	var crouch_multiplier = CROUCH_VELOCITY_MULTIPLIER if is_crouching else 1.0
	
	if direction != 0.0:
		velocity.x = direction * SPEED * crouch_multiplier
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * crouch_multiplier)

	move_and_slide()
	animations(direction, is_crouching)

func animations(direction: float, is_crouching: bool):
	# 1. Flip player sprite logic
	# Check if moving based on current control mode
	var moving_left = Input.is_action_pressed("left") if input_enabled else simulated_left
	var moving_right = Input.is_action_pressed("right") if input_enabled else simulated_right
	var is_moving = (moving_right or moving_left) and !(moving_right and moving_left)

	if moving_right:
		$Sprite2D.flip_h = false
	elif moving_left:
		$Sprite2D.flip_h = true
	
	# 2. Air/Jump state logic (Highest Priority)
	if not is_on_floor():
		if velocity.y < 0:
			state_machine.travel("jump-max")
		else:
			state_machine.travel("fall")
			
	# 3. Ground state logic (Only runs when is_on_floor() is true)
	else:
		if is_crouching:
			if is_moving:
				state_machine.travel("crouch-walk")
			else:
				state_machine.travel("crouch-idle")
		else:
			if is_moving:
				state_machine.travel("run")
			else:
				state_machine.travel("idle")
				
# Called by cutscene director to toggle control style
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if enabled:
		# Reset virtual inputs when player takes back physical control
		simulated_left = false
		simulated_right = false
		simulated_crouch = false
