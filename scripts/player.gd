extends CharacterBody2D

const BASE_SPEED = 50.0
const PURSUIT_SPEED = 60.0
const JUMP_VELOCITY = -200.0
const CROUCH_VELOCITY_MULTIPLIER = 0.5
const MAX_JUMP_HOLD_TIME = 0.16
const JUMP_HOLD_FORCE = 110.0
const JUMP_GRAVITY_MULTIPLIER = 1.0
const FALL_GRAVITY_MULTIPLIER = 0.45
const ROLL_MIN_FALL_HEIGHT = -140.0
const ROLL_MAX_FALL_HEIGHT = -19.0
const UPDATE_GRAVITY_GOING_UP_AT_JUMP_VELOCITY_PERCENTAGE = 1
const UPDATE_GRAVITY_GOING_UP_BY_MULTIPLIER = 1
const UPDATE_GRAVITY_GOING_DOWN_WHILE_VELOCITY_Y_IS_LESS_THAN = 12
const UPDATE_GRAVITY_GOING_DOWN_BY_MULTIPLIER = 0.01
const STUMBLE_VELOCITY_MULTIPLIER = 0.5

var speed = BASE_SPEED

# Ledge climb logic
var on_ledge: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
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
var forced_crouch: bool = false
var direction := 0.0
var is_stumbling: bool = false
var ledge_cooldown_timer: float = 3.0
var was_crouch_collision_active: bool = false

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

	# Tick down the ledge grab cooldown timer
	if ledge_cooldown_timer > 0.0:
		ledge_cooldown_timer -= delta

	# Disable horizontal input entirely while on a ledge
	if input_enabled and not on_ledge:
		direction = Input.get_axis("left", "right")
	else:
		direction = 0.0 # Force zero direction when on ledge or input disabled
		if not on_ledge:
			if simulated_left:
				direction -= 1.0
			if simulated_right:
				direction += 1.0

	# -------------------------------------------------------------
	# LEDGE CLIMB STATE HANDLING
	# -------------------------------------------------------------
	if on_ledge: 
		velocity = Vector2.ZERO # Completely disable physics/gravity while hanging/climbing
		
		# Check horizontal inputs to strictly enforce pure 'Up' or 'Down'
		var holds_horizontal: bool = Input.is_action_pressed("left") or Input.is_action_pressed("right")
		
		if Input.is_action_just_pressed("up"):
			var facing_dir: float = -1.0 if $Sprite2D.flip_h else 1.0
			
			var vertical_target: Vector2 = global_position + Vector2(0.0, -15.0)
			var forward_target: Vector2 = vertical_target + Vector2(facing_dir * 10.0, -2.0)
			
			set_animation_condition("climb", true)
			set_animation_condition("ledge_grab", false)
			
			var climb_tween: Tween = create_tween()
			climb_tween.tween_interval(0.2)
			
			climb_tween.tween_property(self, "global_position", vertical_target, 0.09)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				
			climb_tween.tween_property(self, "global_position", forward_target, 0.2)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			
			climb_tween.finished.connect(func():
				on_ledge = false
				set_animation_condition("climb", false)
			)
			
		elif Input.is_action_just_pressed("down"):
			velocity.y = JUMP_VELOCITY * -0.5
			on_ledge = false
			ledge_cooldown_timer = 0.25 # Prevent instantly re-grabbing while dropping
			set_animation_condition("ledge_grab", false)

		return # Bypass gravity, movement, and move_and_slide completely while on ledge

	# -------------------------------------------------------------
	# STANDARD PHYSICS & GRAVITY (Only runs when NOT on ledge)
	# -------------------------------------------------------------
	if not is_on_floor():
		var gravity_multiplier: float

		if velocity.y < 0.0:
			# Ascending (Going UP)
			# Check if we are near the apex of the jump (low vertical velocity)
			var apex_threshold = JUMP_VELOCITY * UPDATE_GRAVITY_GOING_UP_AT_JUMP_VELOCITY_PERCENTAGE
			if velocity.y < apex_threshold:
				# Float at the peak of the jump arc
				gravity_multiplier = UPDATE_GRAVITY_GOING_UP_BY_MULTIPLIER
			else:
				gravity_multiplier = JUMP_GRAVITY_MULTIPLIER
		else:
			if velocity.y < UPDATE_GRAVITY_GOING_DOWN_WHILE_VELOCITY_Y_IS_LESS_THAN and jump_is_held:
				gravity_multiplier = JUMP_GRAVITY_MULTIPLIER * UPDATE_GRAVITY_GOING_DOWN_BY_MULTIPLIER
			else:
				# Descending (Going DOWN - snappy fall)
				gravity_multiplier = FALL_GRAVITY_MULTIPLIER

		velocity += get_gravity() * delta * gravity_multiplier
	
	var forced_crouch = $ceiling_check.is_colliding()
	var rolling := is_roll_playing()
	var is_crouching = ((Input.is_action_pressed("crouch") and is_on_floor() and not rolling) or (forced_crouch and not rolling) if input_enabled else simulated_crouch)

	if rolling:
		direction = 0.0

	# Jump Logic 
	if input_enabled and not rolling: # Do not jump if rolling
		if is_on_floor():
			jump_hold_timer = 0.0
			jump_is_held = false

		if is_on_floor() and Input.is_action_just_pressed("jump") and !forced_crouch:
			velocity.y = JUMP_VELOCITY
			jump_is_held = true
			jump_hold_timer = 0.0
		elif jump_is_held and Input.is_action_pressed("jump") and velocity.y < 0.0:
			if jump_hold_timer < MAX_JUMP_HOLD_TIME:
				velocity.y -= JUMP_HOLD_FORCE * delta
				jump_hold_timer += delta
		elif Input.is_action_just_released("jump"):
			jump_is_held = false
			if velocity.y < 0.0:
				velocity.y *= 0.6

	# Horizontal Movement
	var crouch_multiplier = CROUCH_VELOCITY_MULTIPLIER if is_crouching else 1.0
	var stumble_multiplier = STUMBLE_VELOCITY_MULTIPLIER if is_stumbling else 1.0
	if rolling:
		velocity.x = sign(velocity.x) * speed * crouch_multiplier * stumble_multiplier
	elif direction != 0.0:
		velocity.x = direction * speed * crouch_multiplier * stumble_multiplier
	else:
		velocity.x = move_toward(velocity.x, 0, speed * crouch_multiplier * stumble_multiplier)

	# Update collision shape BEFORE move_and_slide so physics uses the correct shape
	var should_crouch_collision = is_crouching or rolling
	if should_crouch_collision != was_crouch_collision_active:
		update_crouch_collision(should_crouch_collision)
		was_crouch_collision_active = should_crouch_collision

	move_and_slide()

	# Ledge Grab Detection
	_ledge_logic()

	# Raycast Offset Adjustments
	if direction != 0.0:
		if direction > 0:
			$ledge_grab_miss.target_position.x = 7.0
			$ledge_grab_hit.target_position.x = 6.0
		else:
			$ledge_grab_miss.target_position.x = -7.0
			$ledge_grab_hit.target_position.x = -6.0

	# Landing/Fall Height Calculations
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

	# Do not allow flip direction if the player is rolling
	if not rolling:
		if moving_right:
			$Sprite2D.flip_h = false
		elif moving_left:
			$Sprite2D.flip_h = true

	# 2. Air/Jump state logic (Highest Priority)
	if not is_on_floor():
		if velocity.y < 0:
			state_machine.travel("jump")
		else:
			set_animation_condition("land_requested", false)
			set_animation_condition("roll_requested", false)
			state_machine.travel("fall")
		return

	# 3. Ground state logic (Only runs when is_on_floor() is true)
	if is_crouching:
		if current_state != "idle-to-crouch" and current_state != "crouch-idle" and current_state != "crouch-walk" and current_state != "crouch-to-idle":
			set_animation_condition("run", false) # To fix bugfix that when pressing left or right and then crouching, when releasing left or right but keep crouching, the animation was transitioning to run.
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
		
# Handles ledge climb logic. Checks if we are on ledge
func _ledge_logic() -> void:
	# Block grab if on floor, moving up, or on cooldown after dropping
	if is_on_floor() or velocity.y <= 0 or ledge_cooldown_timer > 0.0:
		return
	#if !$ledge_grab_hit.is_colliding() or $ledge_grab_miss.is_colliding():
	if !$ledge_grab_hit.is_colliding():
		return
	if !Input.is_action_pressed("up") and direction == 0:
		return
		
	var collider = $ledge_grab_hit.get_collider()
	if not collider or not collider.has_method("get_grab_position"):
		return
		
	var grab_point: Vector2 = collider.get_grab_position()
	var facing_dir: float = -1.0 if $Sprite2D.flip_h else 1.0
	var hands_offset: Vector2 = Vector2(-5.0 * facing_dir, 17.0) 
	var desire_position: Vector2 = Vector2(grab_point.x, grab_point.y) + hands_offset
	
	var pos_tween: Tween = create_tween().set_trans(Tween.TRANS_SINE)
	pos_tween.tween_property(self, "global_position", desire_position, 0.05)
	
	velocity = Vector2.ZERO
	set_animation_condition("climb", false)
	set_animation_condition("ledge_grab", true)
	on_ledge = true

# Handles collision resize when crouching
func update_crouch_collision(is_crouching: bool) -> void:
	if not collision_shape or not collision_shape.shape:
		return
		
	if is_crouching:
		# Set height to 15 (crouch size)
		set_shape_height(15.0)
		# Offset shape downward by half the height difference (3px) to keep feet grounded
		collision_shape.position.y = -8.0
	else:
		# Reset height to 21 (standing size)
		set_shape_height(21.0)
		# Reset relative vertical position
		collision_shape.position.y = -10.5

# Handles collision resize
func set_shape_height(new_height: float) -> void:
	var shape = collision_shape.shape
	if shape is RectangleShape2D:
		shape.size.y = new_height

# Handles pursuit mode on character
var is_pursuit_mode: bool = false
func set_pursuit_mode(enabled: bool) -> void:
	# Avoid re-running the logic if we are already in the requested state
	if is_pursuit_mode == enabled:
		return
		
	is_pursuit_mode = enabled
	
	if is_pursuit_mode:
		speed = PURSUIT_SPEED
		animation_tree["parameters/run/run_speed/scale"] = 1.5
	else:
		speed = BASE_SPEED
		animation_tree["parameters/run/run_speed/scale"] = 1.0

# Stumble logic
func stumble(duration: float = 0.8) -> void:
	# Ignore stumble if already stumbling, on a ledge, or mid-roll
	if is_stumbling or on_ledge:
		return
		
	is_stumbling = true
	
	# Force animation tree to play the roll/stumble animation
	if state_machine:
		state_machine.travel("stumble")
	
	# Wait for the duration without freezing physics
	await get_tree().create_timer(duration).timeout
	
	# Reset states after timer finishes
	is_stumbling = false
	input_enabled = true
