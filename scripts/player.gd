extends CharacterBody2D

const SPEED = 50.0
const JUMP_VELOCITY = -200.0
const CROUCH_VELOCITY_MULTIPLIER = 0.5
const MAX_JUMP_HOLD_TIME = 0.16
const JUMP_HOLD_FORCE = 110.0
const JUMP_GRAVITY_MULTIPLIER = 1.0
const FALL_GRAVITY_MULTIPLIER = 0.45
const ROLL_MIN_FALL_HEIGHT = -140.0
const ROLL_MAX_FALL_HEIGHT = -19.0

@onready var animation_tree : AnimationTree = $AnimationTree
var state_machine

# Virtual inputs for cutscene simulation
var simulated_left: bool = false
var simulated_right: bool = false
var simulated_crouch: bool = false
var input_enabled: bool = true
var jump_hold_timer: float = 0.0
var jump_is_held: bool = false
var air_start_y: float = 0.0
var was_crouching: bool = false

func _ready() -> void:
	state_machine = animation_tree["parameters/playback"]
	air_start_y = global_position.y

func set_animation_condition(condition_name: StringName, value: bool) -> void:
	animation_tree["parameters/conditions/" + condition_name] = value

func get_animation_condition(condition_name: StringName) -> bool:
	return bool(animation_tree["parameters/conditions/" + condition_name])

func is_roll_playing() -> bool:
	return state_machine.get_current_node() == "roll"

func _physics_process(delta: float) -> void:
	var was_on_floor: bool = is_on_floor()

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

	var rolling := is_roll_playing()

	# Prevent horizontal direction changes during roll
	if rolling:
		direction = 0.0

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
	
	if rolling:
		# Preserve existing horizontal velocity during roll
		velocity.x = sign(velocity.x) * SPEED * crouch_multiplier
	elif direction != 0.0:
		velocity.x = direction * SPEED * crouch_multiplier
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * crouch_multiplier)

	move_and_slide()

	if was_on_floor and not is_on_floor():
		air_start_y = global_position.y
	elif not was_on_floor and is_on_floor():
		var fall_height = air_start_y - global_position.y
		var is_holding_horizontal = Input.is_action_pressed("left") or Input.is_action_pressed("right")
		if fall_height >= ROLL_MIN_FALL_HEIGHT and fall_height <= ROLL_MAX_FALL_HEIGHT and is_holding_horizontal:
			set_animation_condition("roll_requested", true)
		else:
			set_animation_condition("land_requested", true)
			

	animations(is_crouching)

func animations(is_crouching: bool):
	# 1. Flip player sprite logic
	# Check if moving based on current control mode
	var moving_left = Input.is_action_pressed("left") if input_enabled else simulated_left
	var moving_right = Input.is_action_pressed("right") if input_enabled else simulated_right
	var is_moving = (moving_right or moving_left) and !(moving_right and moving_left)
	var rolling := is_roll_playing()
	var current_state = state_machine.get_current_node()

	if not rolling:
		if moving_right:
			$Sprite2D.flip_h = false
		elif moving_left:
			$Sprite2D.flip_h = true

	# 2. Air/Jump state logic (Highest Priority)
	if not is_on_floor():
		if velocity.y < 0:
			state_machine.travel("jump-max")
		else:
			set_animation_condition("land_requested", false)
			set_animation_condition("roll_requested", false)
			state_machine.travel("fall")
		return

	# 3. Ground state logic (Only runs when is_on_floor() is true)
	if is_crouching:
		if current_state != "idle-to-crouch" and current_state != "crouch-idle" and current_state != "crouch-walk" and current_state != "crouch-to-idle":
			state_machine.travel("idle-to-crouch")
			was_crouching = true
		elif current_state == "idle-to-crouch":
			pass
		elif current_state == "crouch-idle" or current_state == "crouch-walk":
			if is_moving:
				state_machine.travel("crouch-walk")
			else:
				state_machine.travel("crouch-idle")
	elif was_crouching and current_state != "crouch-to-idle" and current_state != "idle":
		state_machine.travel("crouch-to-idle")
		was_crouching = false
	else:
		if is_moving:
			set_animation_condition("idle", false)
			set_animation_condition("run", true)
		else:
			set_animation_condition("run", false)
			set_animation_condition("idle", true)
				
# Called by cutscene director to toggle control style
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if enabled:
		# Reset virtual inputs when player takes back physical control
		simulated_left = false
		simulated_right = false
		simulated_crouch = false
