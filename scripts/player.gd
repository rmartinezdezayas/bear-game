extends CharacterBody2D

# The three sizes the collision box takes. Crouch, roll and slide all want to resize it, so they are
# resolved to exactly one of these per frame instead of each toggling the shape on its own.
enum ShapeState { STANDING, CROUCH, SLIDE }

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
const SLIDE_SPEED = 130.0 # Travel speed along the slope surface while sliding
const SLIDE_JUMP_PUSH = 80.0 # Horizontal launch down-slope when jumping out of a slide
const SLIDE_JUMP_CONTROL_LOCK = 0.22 # Seconds the launch ignores horizontal input
# Slide exit: the slope check is a single short raycast, so it loses the surface a couple of pixels
# before the collision box actually leaves the slope. Without a handover the friction below zeroes
# the down-slope momentum on that very frame and the player stalls at the foot of the slope.
const SLIDE_EXIT_SPEED = 55.0 # Horizontal speed handed over when a slide ends, so the player runs out onto the flat
const SLIDE_EXIT_CARRY_TIME = 0.25 # Seconds the carried speed resists friction; any horizontal input cancels it at once
# Slide collision: the slide art is drawn at standing height, so on a slope the head floats with a
# visible gap under it. The fix is to collide waist-up only while sliding — the box keeps its top
# edge and loses its bottom, which drops the whole body (sprite included) down onto the slope. The
# legs clipping through the slope is the intended look, not a bug to fix later.
# These three are the body's fixed geometry rather than feel: they describe boxes the art was drawn
# around, so they stay constants while the slide's own dials below are exports.
const STAND_SHAPE_HEIGHT = 21.0 # Full standing collision box height
const CROUCH_SHAPE_HEIGHT = 15.0 # Collision box height while crouching or rolling
const CROUCH_SHAPE_OFFSET = -8.0 # Crouch box centre relative to the body origin, feet left grounded

# =============================================================
# SLIDE COLLISION BOX — every tuning knob for sitting down onto a slope and standing back up
# =============================================================
# How deep the bear sits, how long the sit takes, how long he stays sat, and how long standing back
# up takes. Exports rather than constants because they are meant to be dialled in the Inspector on
# player.tscn — or live, on the running instance, from the remote scene tree — while actually
# sliding. There are no matching values stored in player.tscn yet, so these defaults are what runs
# until the Inspector is touched.
#
# All four are cosmetic. Nothing else about the slide depends on them: input, the exit momentum
# carry (SLIDE_EXIT_SPEED / slide_exit_timer) and the animation states all hand over at slide start
# and slide end exactly as they would with the box left at standing height the whole way down.
#
# Setting either ramp time to 0 restores the old one-frame snap in that direction, which makes for a
# clean A/B while tuning.
@export_group("Slide Collision Box")

## Collision box height at full slide depth, in pixels. Standing is 21.
## LOWER = the bear sits deeper into the slope: more leg clipping through the surface, head closer
## to it, and a longer distance for both ramps below to cover. HIGHER = a shallower sit. At 21 the
## box never changes and the whole sink is switched off.
## How far the body drops is derived from this — 21 minus this height — so depth stays one dial.
@export_range(1.0, 21.0, 0.5) var slide_shape_height: float = 10.0

## Seconds for the box to shrink all the way down into the slide pose when a slide starts.
## HIGHER = the bear eases down onto the slope instead of dropping onto it; push it too far and he
## is still on his way down when a short slope has already run out. LOWER = a snappier entry.
## 0 = the old instant snap.
@export_range(0.0, 1.0, 0.01) var slide_shape_enter_time: float = 0.20

## Seconds the box stays at full slide depth after the slide ends, before it starts growing back.
## This is dead time, not motion — the hold that stops him popping upright the instant the slope
## flattens out. HIGHER = he rides further out onto the flat still sunk. LOWER = starts standing up
## sooner. 0 = the exit ramp begins on the same frame the slope runs out.
@export_range(0.0, 2.0, 0.01) var slide_shape_hold_time: float = 1.00

## Seconds for the box to grow all the way back to standing once the hold above has run out.
## HIGHER = a slower, softer stand-up; if the next slope starts mid-rise that is harmless, the ramp
## simply turns around and heads back down. LOWER = a firmer stand-up. 0 = the old instant snap.
@export_range(0.0, 1.0, 0.01) var slide_shape_exit_time: float = 0.50

@export_group("")

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
var shape_state: ShapeState = ShapeState.STANDING # Which pose the collision box was last sized for
# How far the body origin is currently displaced downward from its standing position, in pixels.
# One continuous value rather than an "entering" and an "exiting" timer, because the player
# interrupts this constantly — a short slope that runs out mid-entry, a bump from one slope straight
# onto the next, running off the foot before the rise has finished. A value that is only ever moved
# *toward* a target handles all of those for free: whatever the interruption, the sink is already at
# some legal depth and simply changes which way it is heading.
var current_sink: float = 0.0
var applied_shape_height: float = STAND_SHAPE_HEIGHT # Last height written to the collision shape
var applied_shape_offset: float = -STAND_SHAPE_HEIGHT / 2.0 # Last centre offset written to it
var is_sliding: bool = false
var slide_downhill: Vector2 = Vector2.ZERO # Unit vector pointing down the slope surface
var slide_direction: float = 0.0 # -1.0 slides left, 1.0 slides right, 0.0 not on a slope
var slide_jump_lock_timer: float = 10.0
var slide_exit_timer: float = 0.0 # Seconds of slide momentum still coasting after the slope ran out
var slide_shape_recover_timer: float = 0.0 # Seconds the sunk slide collision box is still held after the slide ended

@onready var slide_check: RayCast2D = $slide_check

func _ready() -> void:
	state_machine = animation_tree["parameters/playback"]
	air_start_y = global_position.y
	# Seed the write guard from whatever the scene actually ships the box as, so the first resize is
	# compared against reality rather than against an assumed starting pose. (player.tscn currently
	# carries 22 x -10 while the script's standing pose is 21 x -10.5 — a 1px difference that has
	# always been there and that the first restore quietly corrects. Reading it here just stops the
	# guard from lying about it.)
	if collision_shape and collision_shape.shape is RectangleShape2D:
		applied_shape_height = collision_shape.shape.size.y
		applied_shape_offset = collision_shape.position.y

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
	if was_sliding and not is_sliding:
		# Arm the shape recovery window on every slide end, including the ones with no momentum to
		# hand over: the box was sunk for the whole slide either way, so there is always a rise to
		# defer. Setting it flat also re-arms a full window when one slope runs straight into the
		# next, so the shape never restores in the gap between two slides.
		slide_shape_recover_timer = slide_shape_hold_time
		if exit_slide_direction != 0.0:
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

	# Tick down the window where the sunk slide collision box is held at full depth past the end of
	# the slide. This is only the *hold*; the rise itself is the exit ramp in _apply_shape_state.
	# Two things end the hold early instead of letting it run out:
	#  - a slide re-engaging. Bumping from one slope onto the next, or the seam at the foot of one,
	#    hands the shape back to the slide itself, so the leftover window is dropped rather than left
	#    running underneath it — the exit above re-arms a full one when that slide ends in turn.
	#  - leaving the floor. The sunk box's whole justification is that the feet stay on the surface
	#    while the body drops into the slope; there is nothing to stay on in mid-air, so there is
	#    nothing left to hold *for* and the window is cut here.
	#    Note what the airborne cut does and does not do now that the sink is continuous: it ends the
	#    hold, it does not snap the sink. The ramp keeps running in the air at the normal exit rate.
	#    That is the right answer in both directions — snapping would teleport the body up to a fifth
	#    of the screen height in one frame with nothing but sky behind it, which is the exact pop
	#    this whole change exists to remove, and freezing a partial sink would leave a body missing
	#    its lower half hanging there until it landed. Ramping in the air is also provably harmless:
	#    a ramp step moves the origin and the box's local bottom edge by the same amount, so the
	#    box's *world* footprint never moves at all, in air or on the ground — only its top edge
	#    grows back up through space the head itself vacated on the way down. Fall height is
	#    unaffected too, because air_start_y is shifted by every step alongside global_position.
	#    The one thing that cannot survive a partial sink is a ledge grab, and _ledge_logic unwinds
	#    it explicitly before setting on_ledge — see the note there.
	if is_sliding or not is_on_floor():
		slide_shape_recover_timer = 0.0
	elif slide_shape_recover_timer > 0.0:
		slide_shape_recover_timer -= delta

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

	# This used to read "never shrink the collision shape mid-slide, the slide animation owns the
	# pose". That is reversed: the slide now owns the shape and shrinks it deliberately (see
	# _apply_shape_state) so the bear sits down on the slope instead of floating above it. Crouch is
	# still suppressed here, both so it cannot fight the slide for the shape and to keep the crouch
	# speed multiplier and the crouch-* animations out of the slide.
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

	# Update collision shape BEFORE move_and_slide so physics uses the correct shape.
	# Three mechanics want to resize the box, so resolve them to one answer here rather than letting
	# each toggle it — two flags taking turns on the same shape thrash it. Slide outranks crouch: they
	# cannot overlap during the slide proper (is_crouching was forced false above), but they very much
	# can during the recovery window below, where crouch is a live input again.
	# The recovery window sits on the same rung as the slide itself rather than below crouch, on
	# purpose: it is the window that keeps the sink at full depth, and a crouch input winning it would
	# start the rise early only to have the crouch cap it again a moment later. Nothing the player
	# asked for is withheld by that — crouch speed, the crouch animations and the roll all run
	# normally through the window, only the box lags, and it lags *smaller*, so it can never fail to
	# fit anywhere the crouch box would have.
	# Unlike before, this is called on every frame rather than only on a change: the sink is a
	# continuous value now and has to be advanced whether or not the resolved pose changed.
	# _apply_shape_state keeps its own guard so the shape resource is still only written when the
	# numbers actually move, and it is the single owner of the box — nothing else in this file
	# touches collision_shape or current_sink.
	var wanted_shape: ShapeState = ShapeState.STANDING
	if is_sliding or slide_shape_recover_timer > 0.0:
		wanted_shape = ShapeState.SLIDE
	elif is_crouching or rolling:
		wanted_shape = ShapeState.CROUCH
	_apply_shape_state(wanted_shape, delta)

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
		
	# Unwind any leftover slide sink in one step before the hang starts. The exit ramp keeps running
	# in the air (see the note on the recovery window), so a grab can begin part of the way through
	# it, and the ledge branch of _physics_process returns before the shape resolution — a partial
	# sink would freeze at that depth for the whole grab and climb. Ramping through it instead is not
	# an option either: the climb writes global_position with a Tween, and a per-frame sink shift on
	# the same axis would fight it. Snapping is invisible here because pos_tween below immediately
	# overwrites global_position with an absolute grab point derived from the ledge, not from us.
	# STANDING unless a live ceiling already resolved us to CROUCH, which the hang can keep.
	var hang_shape: ShapeState = ShapeState.STANDING if shape_state == ShapeState.SLIDE else shape_state
	_apply_shape_state(hang_shape, 0.0, true)

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

# The single owner of the collision box. Called once per frame from the resolution point in
# _physics_process, always before move_and_slide(), plus once explicitly from _ledge_logic to unwind
# the sink before a hang. Nothing else in this file writes collision_shape or current_sink.
#
# It does three things in order, every frame: advance the sink toward the depth the resolved pose
# wants, hand the *change* in sink to everything that measures from the body origin, then size the
# box from the sink and the pose together.
#
# `instant` skips the ramp and jumps straight to the target depth. Only _ledge_logic uses it.
func _apply_shape_state(new_state: ShapeState, delta: float, instant: bool = false) -> void:
	if not collision_shape or not collision_shape.shape:
		return

	# --- 1. Advance the sink ---
	# The slide box keeps the standing box's top edge and loses the rest off the bottom, so the body
	# has to drop by exactly the height it lost to leave its feet on the same surface. That drop is
	# the sink, and it is ramped rather than switched: the box is at some legal fraction of the way
	# down on every single frame, which is what makes an interruption free. A slope that runs out
	# halfway through the entry ramp just flips the target to 0 and the same value walks back up.
	var sink_span: float = _slide_sink()
	var target_sink: float = sink_span if new_state == ShapeState.SLIDE else 0.0
	var next_sink: float = target_sink
	if not instant:
		var ramp_time: float = slide_shape_enter_time if target_sink > current_sink else slide_shape_exit_time
		# Rate derived from the depth, so a full ramp always takes its tuned duration no matter how
		# deep slide_shape_height sets the sink. A zero duration means "snap", which is the pre-ramp
		# behaviour and a deliberate tuning option.
		if ramp_time > 0.0 and sink_span > 0.0:
			next_sink = move_toward(current_sink, target_sink, (sink_span / ramp_time) * delta)

	# --- 2. Hand the change over to everything that measures from the body origin ---
	# Only the delta since last frame is applied, never the absolute sink, so this stays correct no
	# matter where in the ramp the pose changed its mind.
	var sink_shift: float = next_sink - current_sink
	current_sink = next_sink
	if sink_shift != 0.0:
		# Move the body by the same amount the box's bottom edge is about to move, in the same frame,
		# so a ramp step is a deterministic hand-over rather than something gravity has to re-settle:
		#  - sinking, without this the shrink leaves the body hanging above nothing, is_on_floor()
		#    goes false, _check_slide_surface() drops the slide and it re-engages next frame once
		#    gravity closes the gap: a visible stutter at the top of every slope.
		#  - rising, without this the box grows back down *into* the slope and the depenetration pops
		#    the player up, or wedges them at the foot of the slope.
		# Because both move together, the box's bottom edge in *world* space never moves during a
		# ramp at all — the feet stay exactly where they were and only the top edge travels. That is
		# what keeps the penetration argument true on every frame of the ramp and not just at its
		# ends: shrinking gives up space and can never create an overlap, and growing only ever
		# reclaims the space the body's own head vacated on the way down.
		global_position.y += sink_shift
		# air_start_y is a snapshot of global_position.y taken at takeoff, so an unmatched shift
		# would show up as free fall height. Cancel each step out of it, or a slide off a cliff lip
		# misjudges roll-vs-land by however deep the sink was.
		air_start_y += sink_shift
		# Every raycast on the body is placed for the standing pose and the sink drags them all down
		# with it. Shift them back by the same amount so all four keep reading from the exact world
		# positions they read from while standing, at any depth. slide_check is the one that must not
		# be skipped: it casts down from the body origin, which is the standing box's bottom edge, so
		# sinking would start it below the slope surface — and a RayCast2D reports nothing when it
		# begins inside a collider. The slope would read as "gone", the slide would disengage, the
		# shape would restore, the body would pop back up and the slide would re-engage: a visible
		# oscillation all the way down the hill. Enabling hit_from_inside is deliberately NOT the fix
		# — a ray starting inside a shape reports no usable surface normal, and _is_slide_angle()
		# needs that normal. Keeping the ray outside the geometry is what preserves it.
		# ceiling_check matters more now than it did with a one-frame swap: it is what answers CROUCH
		# during the recovery window, and it can only give the right answer if it is reading from
		# standing height rather than from wherever the ramp has the body at this instant.
		for sensor: RayCast2D in [slide_check, $ceiling_check, $ledge_grab_hit, $ledge_grab_miss]:
			sensor.position.y -= sink_shift

	# --- 3. Size the box from the sink and the pose together ---
	# Bottom edge pinned at local -current_sink, which is the surface the feet are still resting on;
	# height is whatever is left above it. At sink 0 this is exactly the standing box, at full sink
	# exactly the old slide box, and every value between is a straight interpolation of the two.
	var box_height: float = STAND_SHAPE_HEIGHT - current_sink
	var box_offset: float = -(STAND_SHAPE_HEIGHT + current_sink) / 2.0
	# CROUCH is a different pinning — it lowers the head and leaves the origin at the feet — so it
	# cannot simply be interpolated with the sink. It does not have to be: take whichever of the two
	# boxes is *shorter*, which is the only one guaranteed to fit. Mid-rise under a ceiling (a slide
	# running out under a low overhang, ceiling_check raising forced_crouch) that caps the growth at
	# crouch height and holds it there for the rest of the ramp, so the head never grows into the
	# overhang, while the body still rises the whole way and the crouch animation still plays at
	# ground level. Below the crossover the capped box is world-identical to the normal crouch box.
	if new_state == ShapeState.CROUCH and CROUCH_SHAPE_HEIGHT < box_height:
		box_height = CROUCH_SHAPE_HEIGHT
		box_offset = CROUCH_SHAPE_OFFSET - current_sink

	# Same change-guard as before, just measured on the numbers instead of on the pose enum, so a
	# stationary shape still costs nothing per frame while a ramping one is written every frame.
	if box_height != applied_shape_height or box_offset != applied_shape_offset:
		set_shape_height(box_height)
		collision_shape.position.y = box_offset
		applied_shape_height = box_height
		applied_shape_offset = box_offset

	shape_state = new_state

# How far the body drops at full slide depth: whatever height the slide box loses off the bottom.
# Derived rather than typed in, so slide_shape_height stays the single depth dial. Runtime rather
# than a const because it now depends on an @export, and clamped because the Inspector can be edited
# live — raising slide_shape_height mid-slide shrinks the span and the ramp just walks back up to it.
func _slide_sink() -> float:
	return maxf(STAND_SHAPE_HEIGHT - slide_shape_height, 0.0)

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
