extends Node2D

# --- Cutscene Timings & Constants ---
const FADE_IN_DURATION: float = 3.5      # Time to reveal scene 2 from black
const WAIT_0_DISABLE_INPUT: float = 1.0  # Time to wait initially before crouch
const WAIT_3_CROUCH_DURATION: float = 2.0 # Wait while crouched
const WAIT_4_FLIP_LOOK: float = 1.5      # Wait after flipping the player's face
const RUN_DURATION: float = 3          # How long the player runs before gaining control

# --- Positions ---
const BEAR_TARGET_X_FAST: float = -60.0 # X coordinate where the bear flees quickly
const MAX_BEAR_DISTANCE: float = 90.0  # Maximum distance to maintain from player
const BEAR_CHASE_SPEED: float = 55.0  # Pixels per second when chasing player

# --- State ---
var cutscene_finished: bool = false

# --- Node References ---
@onready var player: CharacterBody2D = $player
@onready var bear: CharacterBody2D = $bear
@onready var camera: Camera2D = $Camera2D

# Splash overlay to handle the fade-in at the start of this level
@onready var transition_canvas_layer: CanvasLayer = $transition_splash_screen/CanvasLayer
@onready var fade_rect: ColorRect = $transition_splash_screen/CanvasLayer/ColorRect

func _ready() -> void:
	# Start the cinematic sequence
	run_cutscene()

# The master timeline function that handles steps sequentially
func run_cutscene() -> void:
	# ----------------------------------------------------
	# STEP 0: Lock Player Controls & Initialize Overlay
	# ----------------------------------------------------
	set_player_control(false)
	
	if fade_rect and transition_canvas_layer:
		transition_canvas_layer.visible = true
		fade_rect.modulate.a = 1.0 # Start fully covered
		
		# Fade OUT the black screen to reveal scene_2
		var reveal_tween = create_tween()
		reveal_tween.tween_property(fade_rect, "modulate:a", 0.0, FADE_IN_DURATION)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
		await reveal_tween.finished
		transition_canvas_layer.visible = false

	# ----------------------------------------------------
	# STEP 1: Wait for a moment
	# ----------------------------------------------------
	await get_tree().create_timer(WAIT_0_DISABLE_INPUT).timeout

	# ----------------------------------------------------
	# STEP 2 & 3: Simulate crouching
	# ----------------------------------------------------
	if player:
		player.simulated_crouch = true # Virtally press down
	
	await get_tree().create_timer(WAIT_3_CROUCH_DURATION).timeout

	if player:
		player.simulated_crouch = false # Release crouch

	# ----------------------------------------------------
	# STEP 4: Flip player horizontally (Turn Left) & wait
	# ----------------------------------------------------
	if player:
		var sprite = player.get_node_or_null("Sprite2D")
		if sprite:
			sprite.flip_h = true # Look left
			
	await get_tree().create_timer(WAIT_4_FLIP_LOOK).timeout

	 # ----------------------------------------------------
	# STEP 5: Wait briefly, then make the Bear flee quickly
	# ----------------------------------------------------
	await get_tree().create_timer(0.5).timeout
	
	if bear:
		# Tell the bear script to start running to the target position
		if bear.has_method("move_to_position"):
			bear.call("move_to_position", BEAR_TARGET_X_FAST, false)
			
			# Wait until the bear is done moving
			# (We monitor its 'should_move' status until it arrives at the destination)
			while bear.should_move:
				await get_tree().process_frame
				
		# Move faster now
		if bear.has_method("move_to_position"):
			bear.call("move_to_position", 10000, true)

	# ----------------------------------------------------
	# STEP 7: Pan camera back to Player & make Player run
	# ----------------------------------------------------
	if camera and player:
		# Smoothly slide camera back to focus on our player
		var cam_return_tween = create_tween()
		cam_return_tween.tween_property(camera, "global_position:x", player.global_position.x, 1.0)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
		await cam_return_tween.finished

		# Attach camera to player so it follows during the run
		camera.reparent(player)
		
		# Virtally hold "Right" to make them run naturally
		player.simulated_right = true
		
		# Wait for the duration of the scripted run
		await get_tree().create_timer(RUN_DURATION).timeout

	# ----------------------------------------------------
	# FINISH: Return control to Player
	# ----------------------------------------------------
	set_player_control(true)
	cutscene_finished = true


# Helper function to enable/disable your gameplay input script
func set_player_control(has_control: bool) -> void:
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(has_control)


# Maintain minimum distance from player during gameplay
func _process(delta: float) -> void:
	if not cutscene_finished or not player or not bear:
		return
	
	# Calculate distance between player and bear
	var distance = player.global_position.distance_to(bear.global_position)
	
	# If distance is greater than or equal to minimum, keep it at minimum distance
	if distance >= MAX_BEAR_DISTANCE:
		# Get direction from player to bear
		var direction = (player.global_position - bear.global_position).normalized()
		
		# Move bear towards player with smooth speed-based movement
		bear.global_position += direction * BEAR_CHASE_SPEED * delta
