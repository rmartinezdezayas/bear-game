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
# Slide: the player cannot walk up a slope inside this angle band, they are pushed down it instead.
# SLIDE_MAX_ANGLE must stay below the player's floor_max_angle (56 deg in player.tscn), otherwise the
# slope counts as a wall, is_on_floor() is false and the slide never engages.
const SLIDE_MIN_ANGLE = 35.0
const SLIDE_MAX_ANGLE = 55.0
const SLIDE_SPEED = 80.0 # Travel speed along the slope surface while sliding
const SLIDE_JUMP_PUSH = 80.0 # Horizontal launch down-slope when jumping out of a slide
const SLIDE_JUMP_CONTROL_LOCK = 0.22 # Seconds the launch ignores horizontal input
# Slide exit: the slope check is a single short raycast, so it loses the surface a couple of pixels
# before the collision box actually leaves the slope. Without a handover the friction below zeroes
# the down-slope momentum on that very frame and the player stalls at the foot of the slope.
const SLIDE_EXIT_SPEED = 55.0 # Horizontal speed handed over when a slide ends, so the player runs out onto the flat
const SLIDE_EXIT_CARRY_TIME = 0.25 # Seconds the carried speed resists friction; any horizontal input cancels it at once

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
var is_sliding: bool = false
var slide_downhill: Vector2 = Vector2.ZERO # Unit vector pointing down the slope surface
var slide_direction: float = 0.0 # -1.0 slides left, 1.0 slides right, 0.0 not on a slope
var slide_jump_lock_timer: float = 10.0
var slide_exit_timer: float = 0.0 # Seconds of slide momentum still coasting after the slope ran out

@onready var slide_check: RayCast2D = $slide_check

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
	
	# --- SLIDE STATE UPDATE ---
	# Cache the previous slide state before recomputing, _check_slide_surface() clears slide_direction.
	var was_sliding: bool = is_sliding
	var exit_slide_direction: float = slide_direction
	is_sliding = _check_slide_surface()

	# The slope just ran out (foot of the slope, or the player left the surface). Hand the down-slope
	# momentum over as horizontal speed: the raycast loses the slope a couple of pixels before the
	# collision box does, and on that frame the friction below would zero velocity.x outright and
	# leave the player stalled on the last sliver of slope instead of running out onto the flat.
	if was_sliding and not is_sliding and exit_slide_direction != 0.0:
		velocity.x = exit_slide_direction * SLIDE_EXIT_SPEED
		slide_exit_timer = SLIDE_EXIT_CARRY_TIME

	# Tick down the ledge grab cooldown timer
	if ledge_cooldown_timer > 0.0:
		ledge_cooldown_timer -= delta

	# Tick down the post slide-jump window where input cannot fight the down-slope launch
	if slide_jump_lock_timer > 0.0:
		slide_jump_lock_timer -= delta

	# Tick down the window where slide momentum coasts before normal friction resumes
	if slide_exit_timer > 0.0:
		slide_exit_timer -= delta

	# Disable horizontal input entirely while on a ledge or sliding
	if input_enabled and not on_ledge and not is_sliding:
		direction = Input.get_axis("left", "right")
	else:
		direction = 0.0 # Force zero direction when on ledge or input disabled
		if not on_ledge and not is_sliding:
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

	# Never shrink the collision shape mid-slide, the slide animation owns the pose
	if is_sliding:
		is_crouching = false

	if rolling:
		direction = 0.0

	# Jump Logic 
	if input_enabled and not rolling: # Do not jump if rolling
		if is_on_floor():
			jump_hold_timer = 0.0
			jump_is_held = false

		# Jumping is currently blocked while sliding down a slope. To allow it again, delete the
		# "and not is_sliding" below and uncomment the slide branch inside — nothing else has to
		# change, SLIDE_JUMP_PUSH / SLIDE_JUMP_CONTROL_LOCK and slide_jump_lock_timer are all still
		# in place and wired up.
		if is_on_floor() and Input.is_action_just_pressed("jump") and !forced_crouch and not is_sliding:
			velocity.y = JUMP_VELOCITY
			jump_is_held = true
			jump_hold_timer = 0.0
			#if is_sliding:
			#	# Jumping out of a slide launches the player down-slope instead of straight up,
			#	# so a jump can never be used to climb the hill.
			#	velocity.x = slide_direction * SLIDE_JUMP_PUSH
			#	slide_jump_lock_timer = SLIDE_JUMP_CONTROL_LOCK
			#	is_sliding = false
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
	
	if is_sliding:
		# Travel along the slope surface, not just horizontally, so move_and_slide keeps the
		# player grounded on the way down instead of stepping off and re-landing every frame.
		velocity = slide_downhill * SLIDE_SPEED
	elif slide_jump_lock_timer > 0.0:
		pass # Preserve the down-slope launch set by the slide jump
	elif rolling:
		velocity.x = sign(velocity.x) * speed * crouch_multiplier * stumble_multiplier
	elif direction != 0.0:
		slide_exit_timer = 0.0 # The player steered, hand control straight back to the normal rules
		velocity.x = direction * speed * crouch_multiplier * stumble_multiplier
	elif slide_exit_timer > 0.0:
		pass # Coast on the momentum carried out of the slide instead of stopping dead at its foot
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
		slide_jump_lock_timer = 0.0 # Landing hands control straight back to the player
		var fall_height = air_start_y - global_position.y
		var is_holding_horizontal = Input.is_action_pressed("left") or Input.is_action_pressed("right")
		# Dropping onto a slide slope raises no landing request at all. is_sliding is still false here
		# (it was computed before the move, while we were airborne) so without this the fall height
		# alone would ask for a roll. "slide" is only reachable from "fall" in the AnimationTree, and
		# both "roll" and "land" leave only through an at-end transition to "idle", so either one
		# would have to play out in full while the player is already sliding down the hill. Staying
		# in "fall" for the single frame until _check_slide_surface() picks the slope up lets
		# animations() travel straight into "slide" with no hitch.
		if not _landed_on_slide_slope():
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

	# Handle sprite direction during slide separately
	if is_sliding:
		# Lock sprite orientation down-slope, input cannot turn the player around mid-slide
		$Sprite2D.flip_h = slide_direction < 0.0

	# Do not allow flip direction if the player is rolling
	elif not rolling:
		if moving_right:
			$Sprite2D.flip_h = false
		elif moving_left:
			$Sprite2D.flip_h = true

	# 2. Slide state logic (Highest Priority, the player is grounded on a slope)
	if is_sliding:
		# Clear the landing requests raised when we dropped onto the slope, otherwise they can
		# auto-advance the state machine straight back out of the slide.
		set_animation_condition("land_requested", false)
		set_animation_condition("roll_requested", false)
		state_machine.travel("slide")
		return

	# 3. Air/Jump state logic
	if not is_on_floor():
		if velocity.y < 0:
			state_machine.travel("jump")
		else:
			set_animation_condition("land_requested", false)
			set_animation_condition("roll_requested", false)
			state_machine.travel("fall")
		return

	# 4. Ground state logic (Only runs when is_on_floor() is true)
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

# Detects whether the player is standing on a slope steep enough to slide down, and caches the
# downhill direction for the movement and animation code.
func _check_slide_surface() -> bool:
	slide_downhill = Vector2.ZERO
	slide_direction = 0.0

	# Requires ground contact, otherwise the raycast would grab a slope the player is only
	# flying past and steal air control from them.
	if on_ledge or not is_on_floor() or not slide_check.is_colliding():
		return false

	var normal: Vector2 = slide_check.get_collision_normal()
	if not _is_slide_angle(normal):
		return false

	# Rotate the surface normal 90 degrees to get the slope tangent, then point it downhill.
	var downhill: Vector2 = Vector2(-normal.y, normal.x)
	if downhill.y < 0.0:
		downhill = -downhill

	slide_downhill = downhill
	slide_direction = signf(downhill.x)
	return true

# True when a surface normal sits inside the slide band: too steep to stand on, not steep enough to
# count as a wall. Shared by the per-frame slope check and the landing classifier so there is only
# one definition of "this is a slide slope".
func _is_slide_angle(normal: Vector2) -> bool:
	var angle: float = abs(rad_to_deg(normal.angle_to(Vector2.UP)))
	return angle >= SLIDE_MIN_ANGLE and angle <= SLIDE_MAX_ANGLE

# True when the surface the player has just touched down on is one the slide will take over on the
# next frame. Only valid on the landing frame, after move_and_slide().
# It deliberately asks the raycast rather than get_floor_normal(): _check_slide_surface() reads the
# same ray at the top of the next frame, so posing the question the same way here means the two can
# never disagree. A get_floor_normal() answer could say "slope" at the seam where the collision box
# straddles slope and flat while the ray says "flat", and then we would suppress the landing request
# for a slide that never engages, leaving the state machine stranded in "fall" (which has no
# automatic way out). The ray is force-updated because the body has moved since the physics server
# last stepped it, which puts it exactly where the next frame's check will read it from.
func _landed_on_slide_slope() -> bool:
	slide_check.force_raycast_update()
	if not slide_check.is_colliding():
		return false
	return _is_slide_angle(slide_check.get_collision_normal())
